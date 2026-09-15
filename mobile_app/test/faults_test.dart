import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:bss_gateway_monitor/faults.dart';

/// These tests pin the decode tables to the firmware, not to the prose in
/// doc/BLE_App_Integration.md — the doc's §4.3 tier list disagrees with
/// Fault_MainError in two places, and the firmware is what ships.
///
/// Firmware source of truth:
///   src/Mqtt_Handler/Mqtt_handler.cpp:272-342
///   src/Task_Handler/Task_handler.h:57-66
void main() {
  group('station bit decoding', () {
    test('every documented bit maps to its code and text', () {
      final expected = {
        0: ['STA-01', 'SD card fault'],
        1: ['STA-02', 'Time not synced'],
        2: ['STA-03', 'Cloud link down'],
        3: ['STA-04', 'WiFi disconnected'],
        4: ['STA-05', 'RS485/STM32 link dead'],
        5: ['STA-06', 'Abnormal reboot'],
        6: ['STA-07', 'Brownout reset'],
        7: ['STA-08', 'Audio module not ready'],
        8: ['STA-09', 'Offline queue full'],
        9: ['STA-10', 'Low memory'],
      };
      expected.forEach((bit, want) {
        final got = decodeStation(1 << bit);
        expect(got, hasLength(1), reason: 'bit $bit');
        expect(got.single.code, want[0]);
        expect(got.single.text, want[1]);
        expect(got.single.slot, 0);
        expect(got.single.isStation, isTrue);
      });
    });

    test('severities match Fault_StaSev', () {
      // RS485, BROWNOUT, SD_MOUNT are CRITICAL; LOW_HEAP is INFO; rest WARNING.
      expect(staSev(4), 2);
      expect(staSev(6), 2);
      expect(staSev(0), 2);
      expect(staSev(9), 0);
      for (final b in [1, 2, 3, 5, 7, 8]) {
        expect(staSev(b), 1, reason: 'bit $b should be WARNING');
      }
    });

    test('a clear word decodes to nothing', () {
      expect(decodeStation(0), isEmpty);
    });

    test('multiple bits all decode', () {
      final got = decodeStation((1 << 3) | (1 << 4) | (1 << 9));
      expect(got.map((e) => e.code), containsAll(['STA-04', 'STA-05', 'STA-10']));
    });

    test('bits past the enum still decode with the firmware fallback text', () {
      // The firmware scan loop covers 0..31 but FaultIdTypeDef stops at 9, so
      // an unknown bit must render, not crash or show "undefined".
      final got = decodeStation(1 << 10);
      expect(got.single.code, 'STA-11');
      expect(got.single.text, kUnknownFaultText);
      expect(got.single.sev, 1);
      expect(got.single.weight, 10);
    });

    test('the top bit does not overflow or get dropped', () {
      final got = decodeStation(1 << 31);
      expect(got.single.code, 'STA-32');
    });
  });

  group('pod bit decoding', () {
    test('every bit maps to its code, text and severity', () {
      final expected = {
        0: ['POD-01', 'BMS comm lost', 2],
        1: ['POD-02', 'lock failed to open', 2],
        2: ['POD-03', 'lock stuck', 1],
        3: ['POD-04', 'STM32 no-echo', 2],
        4: ['POD-05', 'cell over-voltage', 1],
        5: ['POD-06', 'cell under-voltage', 1],
        6: ['POD-07', 'over-temperature', 2],
        7: ['POD-08', 'BMS hard error', 2],
      };
      expected.forEach((bit, want) {
        final got = decodePod(1 << bit, 3);
        expect(got, hasLength(1), reason: 'bit $bit');
        expect(got.single.code, want[0]);
        expect(got.single.text, want[1]);
        expect(got.single.sev, want[2]);
        expect(got.single.slot, 3);
        expect(got.single.isStation, isFalse);
      });
    });

    test('no pod fault ever reports INFO', () {
      for (var b = 0; b < 8; b++) {
        expect(podSev(b), greaterThanOrEqualTo(1));
      }
    });

    test('withPod matches the firmware main.msg composition', () {
      // Firmware: snprintf(msg, "Pod %u %s", slot, Fault_PodText(b))
      final f = decodePod(1 << 1, 2).single;
      expect(f.withPod, 'Pod 2 lock failed to open');
      // And a station fault carries no prefix.
      expect(decodeStation(1 << 4).single.withPod, 'RS485/STM32 link dead');
    });

    test('sentence capitalises without mutating the wire text', () {
      final f = decodePod(1 << 2, 1).single;
      expect(f.text, 'lock stuck');
      expect(f.sentence, 'Lock stuck');
    });

    test('bit index round-trips from the code', () {
      for (var b = 0; b < 8; b++) {
        expect(decodePod(1 << b, 1).single.bit, b);
      }
    });

    test('bits the shipping build cannot set are flagged, not hidden', () {
      // CURRENT_BMS = OTHER_METHOD compiles out the battery decode branches.
      for (final b in [3, 4, 5, 6, 7]) {
        expect(decodePod(1 << b, 1).single.notInstrumented, isTrue,
            reason: 'bit $b');
      }
      for (final b in [0, 1, 2]) {
        expect(decodePod(1 << b, 1).single.notInstrumented, isFalse,
            reason: 'bit $b');
      }
    });
  });

  group('priority ordering mirrors Fault_MainError', () {
    test('pod weights match the firmware switch', () {
      expect(podWeight(6), 100);
      expect(podWeight(7), 98);
      expect(podWeight(1), 70);
      expect(podWeight(3), 68);
      expect(podWeight(0), 66);
      expect(podWeight(4), 40);
      expect(podWeight(5), 38);
      expect(podWeight(2), 35);
    });

    test('station weights match the firmware switch', () {
      expect(staWeight(4), 90); // RS485
      expect(staWeight(6), 88); // BROWNOUT
      expect(staWeight(0), 50); // SD_MOUNT
      expect(staWeight(2), 45); // MQTT
      expect(staWeight(3), 44); // WIFI
      expect(staWeight(8), 40); // SD_QUEUE_FULL
      expect(staWeight(7), 30); // AUDIO
      expect(staWeight(1), 25); // NTP
      expect(staWeight(5), 24); // REBOOT
      expect(staWeight(9), 20); // LOW_HEAP
    });

    test('STA-09 outranks POD-06 and POD-03, contradicting the doc tiers', () {
      // doc §4.3 buries STA-09 in the bottom "Info" tier. Firmware gives it
      // weight 40 — above POD-06 (38) and POD-03 (35). Ranking from the doc
      // would put a data-losing fault below a cosmetic one.
      expect(staWeight(8), greaterThan(podWeight(5)));
      expect(staWeight(8), greaterThan(podWeight(2)));
    });

    test('audio outranks NTP, contradicting the doc tier order', () {
      expect(staWeight(7), greaterThan(staWeight(1)));
    });

    test('on an exact weight tie the pod wins, as the firmware scan does', () {
      // POD-05 and STA-09 are both weight 40. Fault_MainError scans pods first
      // with a strict '>', so the pod entry survives.
      final pod05 = decodePod(1 << 4, 1).single;
      final sta09 = decodeStation(1 << 8).single;
      expect(pod05.weight, sta09.weight);
      final list = [sta09, pod05]..sort(compareFaults);
      expect(list.first.code, 'POD-05');
    });

    test('allActive sorts most-urgent first across both sources', () {
      final s = StationFaults(
        sid: 'IDR001',
        sta: (1 << 4) | (1 << 9), // STA-05 (90), STA-10 (20)
        pods: [
          const PodFault(p: 1, online: true, f: 1 << 2),  // POD-03 (35)
          const PodFault(p: 2, online: false, f: 1 << 6), // POD-07 (100)
        ],
        main: MainFault.ok,
        receivedAt: DateTime(2026),
      );
      expect(s.allActive.map((e) => e.code).toList(),
          ['POD-07', 'STA-05', 'POD-03', 'STA-10']);
    });
  });

  group('MainFault', () {
    test('OK is detected by code, never by severity', () {
      expect(const MainFault(code: 'OK', slot: 0, sev: 0, msg: '').isOk, isTrue);
      // STA-10 also reports sev 0 and slot 0 — it must NOT read as OK, or a
      // genuine low-memory fault is silently swallowed.
      const lowHeap =
          MainFault(code: 'STA-10', slot: 0, sev: 0, msg: 'Low memory');
      expect(lowHeap.isOk, isFalse);
      expect(lowHeap.sev, 0);
    });

    test('parses the firmware no-fault payload', () {
      final m = MainFault.fromJson(
          json.decode('{"code":"OK","slot":0,"sev":0,"msg":""}')
              as Map<String, dynamic>);
      expect(m.isOk, isTrue);
      expect(m.msg, isEmpty); // firmware sends "", not a friendly phrase
    });

    test('a missing main object degrades to OK rather than throwing', () {
      expect(MainFault.fromJson(null).isOk, isTrue);
    });
  });

  group('StationFaults.fromJson', () {
    final sample = '''
    {"sid":"IDR001","sta":16,
     "pods":[{"p":1,"on":1,"f":0},{"p":2,"on":0,"f":1}],
     "main":{"code":"STA-05","slot":0,"sev":2,"msg":"RS485/STM32 link dead"}}
    ''';

    test('parses the spec example', () {
      final s = StationFaults.fromJson(
          json.decode(sample) as Map<String, dynamic>, DateTime(2026, 8, 25))!;
      expect(s.sid, 'IDR001');
      expect(s.sta, 16);
      expect(s.pods, hasLength(2));
      expect(s.podFor(1)!.online, isTrue);
      expect(s.podFor(1)!.hasFault, isFalse);
      expect(s.podFor(2)!.online, isFalse);
      expect(s.podFor(2)!.decoded.single.code, 'POD-01');
      expect(s.main.code, 'STA-05');
      expect(s.main.sev, 2);
      expect(s.healthy, isFalse);
    });

    test('a frame with no sid is rejected so it can never overwrite good data', () {
      expect(
        StationFaults.fromJson(
            json.decode('{"sta":0,"pods":[]}') as Map<String, dynamic>,
            DateTime(2026)),
        isNull,
      );
    });

    test('podFor returns null for a pod absent from the fault array', () {
      // Summary pods[] is clamped by BLE_MAX_PODS (5) while faults pods[] is
      // clamped by NUMBER_OF_SLAVE (2) — the lengths legitimately differ, and
      // a missing entry means UNKNOWN, not healthy.
      final s = StationFaults.fromJson(
          json.decode(sample) as Map<String, dynamic>, DateTime(2026))!;
      expect(s.podFor(5), isNull);
    });

    test('worstSev reports the highest bit present', () {
      const p = PodFault(p: 1, online: true, f: (1 << 2) | (1 << 6));
      expect(p.worstSev, 2);
      expect(p.hasCritical, isTrue);
      const clean = PodFault(p: 2, online: true, f: 0);
      expect(clean.worstSev, isNull);
    });
  });

  group('FaultsStore', () {
    StationFaults mk(String sid, int sta, DateTime at) => StationFaults(
          sid: sid, sta: sta, pods: const [], main: MainFault.ok, receivedAt: at);

    test('upsert replaces only that sid', () {
      final store = FaultsStore();
      store.upsert(mk('A', 1, DateTime(2026)));
      store.upsert(mk('B', 2, DateTime(2026)));
      store.upsert(mk('A', 8, DateTime(2026)));
      expect(store.stationCount, 2);
      expect(store['A']!.sta, 8);
      expect(store['B']!.sta, 2);
    });

    test('a station absent from a frame is never dropped', () {
      // The firmware collapses multi-station ticks into one notification, so
      // absence carries no information and must not evict an entry.
      final store = FaultsStore();
      store.upsert(mk('A', 1, DateTime(2026)));
      store.upsert(mk('B', 2, DateTime(2026)));
      store.upsert(mk('B', 4, DateTime(2026))); // a tick carrying only B
      expect(store.stationCount, 2);
      expect(store['A'], isNotNull);
    });

    test('worstMain picks the highest severity and ignores OK stations', () {
      final store = FaultsStore();
      store.upsert(mk('A', 0, DateTime(2026)));
      store.upsert(StationFaults(
        sid: 'B', sta: 0, pods: const [],
        main: const MainFault(code: 'STA-02', slot: 0, sev: 1, msg: 'Time not synced'),
        receivedAt: DateTime(2026)));
      store.upsert(StationFaults(
        sid: 'C', sta: 0, pods: const [],
        main: const MainFault(code: 'STA-05', slot: 0, sev: 2, msg: 'RS485/STM32 link dead'),
        receivedAt: DateTime(2026)));
      expect(store.worstMain!.code, 'STA-05');
    });

    test('worstMain is null when every station is OK', () {
      final store = FaultsStore()..upsert(mk('A', 0, DateTime(2026)));
      expect(store.worstMain, isNull);
    });

    test('activeCount and anyCritical aggregate across stations', () {
      final store = FaultsStore();
      store.upsert(mk('A', 1 << 1, DateTime(2026)));  // STA-02 warning
      store.upsert(mk('B', 1 << 4, DateTime(2026)));  // STA-05 critical
      expect(store.activeCount, 2);
      expect(store.anyCritical, isTrue);
    });

    test('staleness is time-based, tolerating several missed ticks', () {
      final t = DateTime(2026, 8, 25, 12, 0, 0);
      final s = mk('A', 0, t);
      expect(s.isStale(t.add(const Duration(seconds: 3))), isFalse);
      expect(s.isStale(t.add(const Duration(seconds: 9))), isTrue);
    });
  });
}
