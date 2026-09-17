import 'package:flutter_test/flutter_test.dart';
import 'package:bss_gateway_monitor/health.dart';

final DateTime _t0 = DateTime(2026, 9, 15, 12, 0, 0);

/// The §3.9 health payload, trimmed to the fields these tests care about.
/// `station_id` is mandatory — fromJson rejects a frame without one.
Map<String, dynamic> _health({
  Object? masterFw,
  Object? sensorFlags,
}) =>
    <String, dynamic>{
      'station_id': 'BLR001',
      'pods_online': 63,
      'pods_offline': 0,
      if (masterFw != null) 'master_fw': masterFw,
      if (sensorFlags != null) 'sensor_flags': sensorFlags,
    };

void main() {
  group('master_fw / sensor_flags accept hex text and plain numbers', () {
    // The gateway now sends these two register words as hex strings, because
    // 263 and 1792 hide what "0x0107" and "0x0700" state outright. Stations in
    // the field are not all reflashed the day the app updates, so both forms
    // have to keep working — reading one only would blank the entire master
    // block and every cabinet probe.

    test('hex string is the current firmware form', () {
      final h = StationHealth.fromJson(
          _health(masterFw: '0x0107', sensorFlags: '0x0700'), _t0)!;
      expect(h.masterFw, 263);
      expect(h.masterVersion, 'v1.7');
      expect(h.sensorFlags, 0x0700);
      expect(h.hasClimate, isTrue);
      expect(h.hasWaterProbe, isTrue);
      expect(h.hasSmokeProbe, isTrue);
    });

    test('plain number is the older firmware form and still decodes', () {
      final h = StationHealth.fromJson(
          _health(masterFw: 263, sensorFlags: 1792), _t0)!;
      expect(h.masterFw, 263);
      expect(h.masterVersion, 'v1.7');
      expect(h.sensorFlags, 0x0700);
      expect(h.hasAnySensor, isTrue);
    });

    test('both forms of the same word decode identically', () {
      final hex = StationHealth.fromJson(
          _health(masterFw: '0x0107', sensorFlags: '0x0700'), _t0)!;
      final dec = StationHealth.fromJson(
          _health(masterFw: 263, sensorFlags: 1792), _t0)!;
      expect(hex.masterFw, dec.masterFw);
      expect(hex.sensorFlags, dec.sensorFlags);
      expect(hex.masterVersion, dec.masterVersion);
    });

    test('uppercase 0X and surrounding space are tolerated', () {
      final h = StationHealth.fromJson(
          _health(masterFw: ' 0X0107 ', sensorFlags: '0X0700'), _t0)!;
      expect(h.masterFw, 263);
      expect(h.sensorFlags, 0x0700);
    });

    test('a probe that is not fitted stays not fitted', () {
      // 0x0100 = DHT11 only. A missing bit must not be read as "assume fitted".
      final h = StationHealth.fromJson(_health(sensorFlags: '0x0100'), _t0)!;
      expect(h.hasClimate, isTrue);
      expect(h.hasWaterProbe, isFalse);
      expect(h.hasSmokeProbe, isFalse);
    });

    test('garbage reads as absent, not as zero', () {
      // "not reported" and "reported as 0" must stay distinguishable: a zero
      // sensor_flags would claim, confidently, that no probes are installed.
      final h = StationHealth.fromJson(
          _health(masterFw: 'v1.7', sensorFlags: ''), _t0)!;
      expect(h.masterFw, isNull);
      expect(h.masterVersion, '-');
      expect(h.sensorFlags, isNull);
      expect(h.hasAnySensor, isFalse);
    });

    test('an absent master block leaves the fields null', () {
      final h = StationHealth.fromJson(_health(), _t0)!;
      expect(h.masterFw, isNull);
      expect(h.sensorFlags, isNull);
    });
  });

  test('a frame with no station_id is rejected outright', () {
    // A truncated payload must never overwrite a good record.
    expect(StationHealth.fromJson({'master_fw': '0x0107'}, _t0), isNull);
  });

  group('nested payload decodes the same as the flat one', () {
    // Firmware now groups health into Fault / Master / System / Pod_Status /
    // Sensor, each an ARRAY OF SINGLE-KEY OBJECTS. Stations in the field still
    // send the flat shape until they are reflashed, so one app build has to
    // read both. These tests pin that: same numbers in, same record out.

    Map<String, dynamic> grouped() => <String, dynamic>{
          'TS': '2026-09-17T10:07:51Z',
          'event': 'health',
          'station_id': 'BLR001',
          'version': '1.0.0',
          'bitmap': '0x00000000',
          'master': <String, dynamic>{
            'reset_reason': 'power_on',
            'master_fw': 263,
            'master_reset': 5,
            'master_crashed': 1,
            'master_brownout': 0,
          },
          'system': <String, dynamic>{
            'total_heap': 295924,
            'free_heap': 68868,
          },
          'pod_status': <String, dynamic>{
            'slaves': 6,
            'pods_online': 63,
            'pods_offline': 0,
          },
          'sensor': <String, dynamic>{
            'sensor_flags': 1792,
            'cab_temp_c': 29.3,
            'cab_humidity': 72,
            'water_raw': 0,
            'water_alarm': 0,
            'smoke_raw': 375,
            'smoke_alarm': 0,
          },
        };
    Map<String, dynamic> flat() => <String, dynamic>{
          'TS': '2026-09-17T10:07:51+05:30',
          'event': 'health',
          'station_id': 'BLR001',
          'version': '1.0.0',
          'bitmap': '0x00000000',
          'sd_fault': 0,
          'ntp_fault': 0,
          'mqtt_fault': 0,
          'wifi_fault': 0,
          'rs485_fault': 0,
          'reboot_fault': 0,
          'brownout': 0,
          'queue_full': 0,
          'low_heap': 0,
          'reset_reason': 'power_on',
          'master_fw': 263,
          'master_reset': 5,
          'master_crashed': 1,
          'master_brownout': 0,
          'total_heap': 295924,
          'free_heap': 68868,
          'rssi': -41,
          'sd_mounted': 'yes',
          'slaves': 6,
          'pods_online': 63,
          'pods_offline': 0,
          'sensor_flags': 1792,
          'cab_temp_c': 29.3,
          'cab_humidity': 72,
          'water_raw': 0,
          'water_alarm': 0,
          'smoke_raw': 375,
          'smoke_alarm': 0,
        };

    test('every field survives the grouping', () {
      final h = StationHealth.fromJson(grouped(), _t0)!;

      expect(h.stationId, 'BLR001');
      expect(h.ts, '2026-09-17T10:07:51Z');
      expect(h.version, '1.0.0');
      expect(h.bitmapHex, '0x00000000');
      expect(h.healthy, isTrue);
      expect(h.activeFaults, isEmpty);

      expect(h.resetReason, 'power_on');
      expect(h.masterFw, 263);
      expect(h.masterVersion, 'v1.7');
      expect(h.masterReset, 5);
      expect(h.masterCrashed, isTrue);
      expect(h.masterBrownout, isFalse);

      expect(h.totalHeap, 295924);
      expect(h.freeHeap, 68868);
      // rssi and sd_mounted are no longer published
      expect(h.rssi, isNull);
      expect(h.sdMounted, '');

      expect(h.pods, 6);
      expect(h.podsOnline, 63);
      expect(h.hasMaster, isTrue);
      expect(h.onlinePods, [1, 2, 3, 4, 5, 6]);
      expect(h.offlinePods, isEmpty);

      expect(h.sensorFlags, 1792);
      expect(h.cabTempC, 29.3);
      expect(h.cabHumidity, 72);
      expect(h.waterRaw, 0);
      expect(h.smokeRaw, 375);
      expect(h.waterAlarm, isFalse);
      expect(h.smokeAlarm, isFalse);
      expect(h.hasClimate, isTrue);
      expect(h.hasWaterProbe, isTrue);
      expect(h.hasSmokeProbe, isTrue);
    });

    test('grouped and flat produce the same record', () {
      final g = StationHealth.fromJson(grouped(), _t0)!;
      final f = StationHealth.fromJson(flat(), _t0)!;

      expect(g.bitmapHex, f.bitmapHex);
      expect(g.flags, f.flags);
      expect(g.resetReason, f.resetReason);
      expect(g.masterFw, f.masterFw);
      expect(g.masterReset, f.masterReset);
      expect(g.masterCrashed, f.masterCrashed);
      expect(g.totalHeap, f.totalHeap);
      expect(g.freeHeap, f.freeHeap);
      expect(g.pods, f.pods);
      expect(g.podsOnline, f.podsOnline);
      expect(g.sensorFlags, f.sensorFlags);
      expect(g.cabTempC, f.cabTempC);
      expect(g.smokeRaw, f.smokeRaw);
      expect(g.onlinePods, f.onlinePods);
    });

    test('a raised fault inside the group is still seen', () {
      final j = grouped();
      j['bitmap'] = '0x00000010';   // bit 4 = FAULT_RS485

      final h = StationHealth.fromJson(j, _t0)!;
      expect(h.healthy, isFalse);
      expect(h.activeFaults, ['RS485 link']);
      expect(h.bitmapHex, '0x00000010');
    });

    test('an alarm inside the Sensor group still reads as urgent', () {
      final j = grouped();
      (j['sensor'] as Map)['smoke_raw'] = 3000;
      (j['sensor'] as Map)['smoke_alarm'] = 1;

      final h = StationHealth.fromJson(j, _t0)!;
      expect(h.smokeAlarm, isTrue);
      expect(h.hasUrgentAlarm, isTrue);
    });

    test('groups the gateway omits mean unknown, not zero', () {
      // Before the STM32 status read lands, firmware sends Master carrying
      // only reset_reason and no Sensor block at all. Nothing may default to 0.
      final j = grouped();
      j['master'] = <String, dynamic>{'reset_reason': 'power_on'};
      j['pod_status'] = <String, dynamic>{'slaves': 6};
      j.remove('sensor');

      final h = StationHealth.fromJson(j, _t0)!;
      expect(h.hasMaster, isFalse);
      expect(h.podsOnline, isNull);
      expect(h.masterFw, isNull);
      expect(h.sensorFlags, isNull);
      expect(h.cabTempC, isNull);
      expect(h.hasAnySensor, isFalse);
      expect(h.onlinePods, isEmpty);
    });

    test('hex text inside a group is decoded too', () {
      final j = grouped();
      (j['master'] as Map)['master_fw'] = '0x0107';
      (j['sensor'] as Map)['sensor_flags'] = '0x0700';

      final h = StationHealth.fromJson(j, _t0)!;
      expect(h.masterFw, 263);
      expect(h.masterVersion, 'v1.7');
      expect(h.sensorFlags, 0x0700);
    });

    test('faults decode from the bitmap alone, across the bit-7 gap', () {
      // FaultIdTypeDef reserves bit 7 for FAULT_AUDIO and never names it in
      // JSON, so queue_full is bit 8 and low_heap is bit 9. Counting along
      // the list instead would read them one bit early and report the wrong
      // fault, which is exactly the kind of mistake nobody notices.
      final j = grouped();
      j['bitmap'] = '0x00000300';   // bits 8 and 9

      final h = StationHealth.fromJson(j, _t0)!;
      expect(h.activeFaults, ['Offline queue full', 'Low memory']);
      expect(h.flags['brownout'], isFalse);
      expect(h.healthy, isFalse);
    });

    test('bit 7 on its own raises nothing that has a name', () {
      final j = grouped();
      j['bitmap'] = '0x00000080';   // FAULT_AUDIO, no JSON key

      final h = StationHealth.fromJson(j, _t0)!;
      expect(h.activeFaults, isEmpty);
      expect(h.bitmapHex, '0x00000080');
    });

    test('an explicit boolean still wins over the bitmap', () {
      // Older firmware sends both. If they ever disagree, show what the
      // gateway itself concluded.
      final j = grouped();
      j['bitmap'] = '0x00000000';
      j['rs485_fault'] = 1;

      final h = StationHealth.fromJson(j, _t0)!;
      expect(h.activeFaults, ['RS485 link']);
    });
    test('the short-lived array-of-single-key-objects form still decodes', () {
      // An intermediate shape that existed between flat and nested. Keeping
      // the branch costs nothing and covers any station flashed mid-change.
      final h = StationHealth.fromJson(<String, dynamic>{
        'station_id': 'BLR001',
        'Fault': <Map<String, dynamic>>[
          {'bitmap': '0x00000010'},
          {'rs485_fault': 1},
        ],
        'Pod_Status': <Map<String, dynamic>>[
          {'slaves': 6},
          {'pods_online': 63},
        ],
      }, _t0)!;
      expect(h.bitmapHex, '0x00000010');
      expect(h.activeFaults, ['RS485 link']);
      expect(h.podsOnline, 63);
      expect(h.onlinePods, [1, 2, 3, 4, 5, 6]);
    });
    test('a grouped frame with no station_id is still rejected', () {
      final j = grouped();
      j.remove('station_id');
      expect(StationHealth.fromJson(j, _t0), isNull);
    });
  });

}
