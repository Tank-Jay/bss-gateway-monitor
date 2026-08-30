import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bss_gateway_monitor/faults.dart';
import 'package:bss_gateway_monitor/mesh.dart';

/// The §8.3 example payload, verbatim from doc/BLE_App_Integration.md.
const String kDocExample =
    '{ "station": "Other", "faultBits": 16, "mainFault": "RS485_DEAD", '
    '"faultSlot": 0, "severity": 2 }';

List<int> _access(String jsonBody) =>
    [...kMeshStatusOpcode, ...utf8.encode(jsonBody)];

final DateTime _t0 = DateTime(2026, 8, 30, 12, 0, 0);

void main() {
  group('normaliseUuid', () {
    test('reduces every spelling of an adopted UUID to the short form', () {
      // flutter_blue_plus has used all of these across versions/platforms.
      for (final s in [
        '1827',
        '0x1827',
        '00001827-0000-1000-8000-00805f9b34fb',
        '00001827-0000-1000-8000-00805F9B34FB',
        '000018270000100080000080 5f9b34fb'.replaceAll(' ', ''),
      ]) {
        expect(normaliseUuid(s), '1827', reason: 'failed for "$s"');
      }
    });

    test('leaves a vendor UUID alone', () {
      expect(normaliseUuid('e1ec0401-1234-4321-abcd-0123456789ab'),
          'e1ec040112344321abcd0123456789ab');
    });
  });

  group('serviceDataFor', () {
    test('matches regardless of how the platform spelled the key', () {
      final data = {
        '00001828-0000-1000-8000-00805F9B34FB': [0x00, 1, 2, 3, 4, 5, 6, 7, 8],
      };
      expect(serviceDataFor(data, kMeshProxyUuid), isNotNull);
      expect(serviceDataFor(data, kMeshProvisioningUuid), isNull);
    });
  });

  group('MeshDeviceUuid', () {
    // 0x3210 + MAC 24:6F:28:AA:BB:CC + 8 pad bytes, as Mesh_Init() builds it.
    final bss = [0x32, 0x10, 0x24, 0x6F, 0x28, 0xAA, 0xBB, 0xCC,
                 0, 0, 0, 0, 0, 0, 0, 0];

    test('recognises the firmware marker and recovers the MAC', () {
      final u = MeshDeviceUuid.parse(bss)!;
      expect(u.isBssStation, isTrue);
      expect(u.mac, '24:6F:28:AA:BB:CC');
      expect(u.shortMac, 'AA:BB:CC');
    });

    test('foreign mesh hardware is not claimed as ours', () {
      final other = List<int>.filled(16, 0x11);
      final u = MeshDeviceUuid.parse(other)!;
      expect(u.isBssStation, isFalse);
      expect(u.mac, isEmpty, reason: 'bytes 2..7 are meaningless here');
      expect(u.toString(), u.hex);
    });

    test('rejects a wrong-length UUID instead of padding it', () {
      expect(MeshDeviceUuid.parse(bss.sublist(0, 15)), isNull);
      expect(MeshDeviceUuid.parse([...bss, 0]), isNull);
      expect(MeshDeviceUuid.parse(const []), isNull);
    });
  });

  group('MeshBeacon', () {
    final uuid = [0x32, 0x10, 0x24, 0x6F, 0x28, 0x01, 0x02, 0x03,
                  0, 0, 0, 0, 0, 0, 0, 0];

    test('unprovisioned beacon carries UUID and OOB info', () {
      final b = MeshBeacon.fromServiceData({
        '1827': [...uuid, 0x00, 0x08],
      })!;
      expect(b.kind, MeshBeaconKind.unprovisioned);
      expect(b.isProvisioned, isFalse);
      expect(b.deviceUuid!.mac, '24:6F:28:01:02:03');
      expect(b.oobInfo, 0x0008);
    });

    test('a stack that omits the OOB field still yields the UUID', () {
      final b = MeshBeacon.fromServiceData({'1827': uuid})!;
      expect(b.kind, MeshBeaconKind.unprovisioned);
      expect(b.deviceUuid!.isBssStation, isTrue);
      expect(b.oobInfo, isNull);
    });

    test('proxy Network ID beacon', () {
      final b = MeshBeacon.fromServiceData({
        '1828': [0x00, 1, 2, 3, 4, 5, 6, 7, 8],
      })!;
      expect(b.kind, MeshBeaconKind.proxyNetworkId);
      expect(b.isProvisioned, isTrue);
      expect(b.networkId, [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(b.deviceUuid, isNull,
          reason: 'a proxy beacon does not disclose the device UUID');
    });

    test('proxy Node Identity beacon', () {
      final b = MeshBeacon.fromServiceData({
        '1828': [0x01, ...List.filled(8, 0xAA), ...List.filled(8, 0xBB)],
      })!;
      expect(b.kind, MeshBeaconKind.proxyNodeIdentity);
      expect(b.isProvisioned, isTrue);
      expect(b.identityHash, List.filled(8, 0xAA));
      expect(b.identityRandom, List.filled(8, 0xBB));
    });

    test('an unrecognised identification type is unknown, not provisioned', () {
      // 0x02/0x03 are Mesh Protocol 1.1 private identities.
      final b = MeshBeacon.fromServiceData({
        '1828': [0x02, ...List.filled(8, 0)],
      })!;
      expect(b.kind, MeshBeaconKind.unknown);
      expect(b.isProvisioned, isFalse);
    });

    test('a truncated proxy payload does not throw', () {
      final b = MeshBeacon.fromServiceData({'1828': [0x00, 1, 2]})!;
      expect(b.kind, MeshBeaconKind.unknown);
    });

    test('a non-mesh advertisement decodes to null', () {
      expect(MeshBeacon.fromServiceData({'180a': [1, 2, 3]}), isNull);
      expect(MeshBeacon.fromServiceData(const {}), isNull);
    });

    test('provisioning data wins when both are somehow present', () {
      final b = MeshBeacon.fromServiceData({
        '1828': [0x00, 1, 2, 3, 4, 5, 6, 7, 8],
        '1827': uuid,
      })!;
      expect(b.kind, MeshBeaconKind.unprovisioned);
    });
  });

  group('vendor opcode', () {
    test('matches ESP_BLE_MESH_MODEL_OP_3(0x01, CID_ESP)', () {
      // 3-octet vendor opcode = 0xC0|op, then CID little-endian.
      expect(kMeshStatusOpcode, [0xC1, 0xE5, 0x02]);
      expect(kMeshStatusOpcode[1] | (kMeshStatusOpcode[2] << 8), kMeshCompanyId);
    });

    test('strips its own opcode and rejects anything else', () {
      expect(stripStatusOpcode([...kMeshStatusOpcode, 0x7B, 0x7D]), [0x7B, 0x7D]);
      expect(stripStatusOpcode([0xC2, 0xE5, 0x02, 0x7B]), isNull,
          reason: 'another vendor opcode on the same network');
      expect(stripStatusOpcode(kMeshStatusOpcode), isNull,
          reason: 'opcode with no payload is not a status');
      expect(stripStatusOpcode(const [0xC1]), isNull);
    });
  });

  group('word codes', () {
    test('cover exactly the bits the shared fault tables cover', () {
      expect(kStaCode.length, kStaText.length);
      expect(kPodCode.length, kPodText.length);
    });

    test('map back to the bit that produced them', () {
      expect(staBitForCode('RS485_DEAD'), 4);
      expect(staBitForCode('LOW_HEAP'), 9);
      expect(podBitForCode('POD_OFFLINE'), 0);
      expect(podBitForCode('OVER_TEMP'), 6);
      expect(staBitForCode('OVER_TEMP'), isNull,
          reason: 'pod and station codes are separate namespaces');
      expect(podBitForCode('RS485_DEAD'), isNull);
      expect(staBitForCode(kStaCodeUnknown), isNull,
          reason: 'every unnamed bit 10..31 produces STA_FAULT, so it is '
              'not reversible');
    });

    test('rebuild the same wording Fault_MainError would have sent', () {
      // Pod path: snprintf(msg, "Slot %u %s", slot, Fault_PodText(b)).
      expect(meshMainMessage('LOCK_FAIL', 2), 'Slot 2 lock failed to open');
      // Station path: the bare text.
      expect(meshMainMessage('RS485_DEAD', 0), 'RS485/STM32 link dead');
      expect(meshMainMessage('OK', 0), isEmpty);
      expect(meshMainMessage(kStaCodeUnknown, 0), kUnknownFaultText);
      // A code from firmware newer than this app: shown, not swallowed.
      expect(meshMainMessage('SOME_FUTURE_CODE', 0), 'SOME_FUTURE_CODE');
    });
  });

  group('MeshStatus', () {
    test("decodes the doc's own §8.3 example", () {
      final s = MeshStatus.fromAccessPayload(_access(kDocExample), at: _t0)!;
      expect(s.station, 'Other');
      expect(s.faultBits, 16);
      expect(s.mainFault, 'RS485_DEAD');
      expect(s.faultSlot, 0);
      expect(s.severity, 2);
      expect(s.isOk, isFalse);
      expect(s.isPodFault, isFalse);
    });

    test('faultBits decode through the shared STA table', () {
      final s = MeshStatus.fromAccessPayload(_access(kDocExample), at: _t0)!;
      final f = s.stationFaults;
      expect(f, hasLength(1), reason: 'bit 4 only');
      expect(f.single.code, 'STA-05');
      expect(f.single.text, 'RS485/STM32 link dead');
      expect(f.single.sev, 2);
    });

    test('several bits at once decode in full', () {
      // bits 2, 3, 9 → CLOUD_DOWN, WIFI_DOWN, LOW_HEAP
      final s = MeshStatus.fromJson({
        'station': 'Depot-1',
        'faultBits': (1 << 2) | (1 << 3) | (1 << 9),
        'mainFault': 'CLOUD_DOWN',
        'faultSlot': 0,
        'severity': 1,
      }, at: _t0);
      expect(s.stationFaults.map((f) => f.code),
          containsAll(['STA-03', 'STA-04', 'STA-10']));
    });

    test('a pod-level headline keeps its slot and reads like the GATT path',
        () {
      final s = MeshStatus.fromJson({
        'station': 'Depot-1',
        'faultBits': 0,
        'mainFault': 'OVER_TEMP',
        'faultSlot': 3,
        'severity': 2,
      }, at: _t0);
      expect(s.isPodFault, isTrue);
      expect(s.main.msg, 'Slot 3 over-temperature');
      expect(s.main.slot, 3);
      expect(s.main.isOk, isFalse);
    });

    test('a healthy node is OK even though severity is 0', () {
      final s = MeshStatus.fromJson({
        'station': 'Depot-1',
        'faultBits': 0,
        'mainFault': 'OK',
        'faultSlot': 0,
        'severity': 0,
      }, at: _t0);
      expect(s.isOk, isTrue);
      expect(s.main.isOk, isTrue);
      expect(s.main.msg, isEmpty);
      expect(s.stationFaults, isEmpty);
    });

    test('LOW_HEAP is a real fault despite reporting severity 0', () {
      // The exact trap MainFault.isOk exists to avoid — must not read as OK.
      final s = MeshStatus.fromJson({
        'station': 'Depot-1',
        'faultBits': 1 << 9,
        'mainFault': 'LOW_HEAP',
        'faultSlot': 0,
        'severity': 0,
      }, at: _t0);
      expect(s.severity, 0);
      expect(s.isOk, isFalse);
      expect(s.main.isOk, isFalse);
      expect(s.main.msg, 'Low memory');
    });

    test('foreign or malformed traffic is ignored, not guessed at', () {
      // Wrong opcode — another model publishing on the same network.
      expect(MeshStatus.fromAccessPayload(
          [0xC2, 0xE5, 0x02, ...utf8.encode(kDocExample)], at: _t0), isNull);
      // Right opcode, truncated JSON (a lost segment).
      expect(MeshStatus.fromAccessPayload(
          _access('{"station":"Oth'), at: _t0), isNull);
      // Right opcode, valid JSON that is not an object.
      expect(MeshStatus.fromAccessPayload(_access('[1,2,3]'), at: _t0), isNull);
      // Bytes that are not UTF-8 at all.
      expect(MeshStatus.fromJsonBytes(const [0xFF, 0xFE, 0xFD], at: _t0),
          isNull);
    });

    test('missing fields fall back rather than throwing', () {
      final s = MeshStatus.fromJsonBytes(utf8.encode('{}'), at: _t0)!;
      expect(s.station, isEmpty);
      expect(s.faultBits, 0);
      expect(s.mainFault, 'OK');
      expect(s.isOk, isTrue);
    });
  });

  group('MeshNode', () {
    MeshNode node({MeshStatus? status, MeshDeviceUuid? uuid, DateTime? seen}) =>
        MeshNode(
          id: 'AA:BB:CC:DD:EE:FF',
          kind: MeshBeaconKind.unprovisioned,
          rssi: -60,
          seenAt: seen ?? _t0,
          deviceUuid: uuid,
          status: status,
        );

    final uuid = MeshDeviceUuid.parse(
        [0x32, 0x10, 0x24, 0x6F, 0x28, 0x01, 0x02, 0x03,
         0, 0, 0, 0, 0, 0, 0, 0])!;

    test('label prefers the published name, then the MAC, then the scan id',
        () {
      final withName = node(
        uuid: uuid,
        status: MeshStatus.fromJson(
            {'station': 'Depot-1', 'mainFault': 'OK'}, at: _t0),
      );
      expect(withName.label, 'Depot-1');
      expect(node(uuid: uuid).label, 'Station 01:02:03');
      expect(node().label, 'AA:BB:CC:DD:EE:FF');
    });

    test('an empty station name does not win over the MAC', () {
      // MESH_STATION_NAME is a build constant and can be left blank.
      final n = node(
        uuid: uuid,
        status: MeshStatus.fromJson({'station': '', 'mainFault': 'OK'}, at: _t0),
      );
      expect(n.label, 'Station 01:02:03');
    });

    test('a node with no status reads as unknown, not healthy', () {
      final n = node();
      expect(n.status, isNull);
      expect(n.sortSeverity, -1);
      expect(n.statusStaleAt(_t0), isTrue);
    });

    test('status goes stale ~10 s after the last publish', () {
      final n = node(
          status: MeshStatus.fromJson({'mainFault': 'OK'}, at: _t0));
      expect(n.statusStaleAt(_t0.add(const Duration(seconds: 8))), isFalse);
      expect(n.statusStaleAt(_t0.add(const Duration(seconds: 11))), isTrue);
    });

    test('beacon staleness is looser than status staleness', () {
      final n = node();
      expect(n.beaconStaleAt(_t0.add(const Duration(seconds: 20))), isFalse);
      expect(n.beaconStaleAt(_t0.add(const Duration(seconds: 31))), isTrue);
      expect(kMeshBeaconStale, greaterThan(kMeshStatusStale));
    });
  });

  group('MeshStore', () {
    final provUuid = [0x32, 0x10, 0x24, 0x6F, 0x28, 0x01, 0x02, 0x03,
                      0, 0, 0, 0, 0, 0, 0, 0];

    MeshBeacon unprov() =>
        MeshBeacon.fromServiceData({'1827': [...provUuid, 0, 0]})!;
    MeshBeacon proxy() =>
        MeshBeacon.fromServiceData({'1828': [0x00, 1, 2, 3, 4, 5, 6, 7, 8]})!;

    test('keeps the device UUID learned before the node was provisioned', () {
      final s = MeshStore();
      s.observe(id: 'n1', beacon: unprov(), rssi: -50, at: _t0);
      expect(s['n1']!.deviceUuid!.mac, '24:6F:28:01:02:03');

      // After provisioning the node stops advertising its UUID.
      s.observe(id: 'n1', beacon: proxy(), rssi: -55, at: _t0);
      expect(s['n1']!.isProvisioned, isTrue);
      expect(s['n1']!.deviceUuid!.mac, '24:6F:28:01:02:03',
          reason: 'must not regress to null');
      expect(s.length, 1, reason: 'same node, not a second entry');
    });

    test('a re-observation does not drop the status already attached', () {
      final s = MeshStore();
      s.observe(id: 'n1', beacon: proxy(), rssi: -50, at: _t0);
      s.applyStatus('n1',
          MeshStatus.fromJson({'station': 'D1', 'mainFault': 'OK'}, at: _t0));
      s.observe(id: 'n1', beacon: proxy(), rssi: -70, at: _t0);
      expect(s['n1']!.status, isNotNull);
      expect(s['n1']!.rssi, -70);
    });

    test('a status can arrive for a node this phone never heard directly', () {
      // The §8.1 ESP32 forwarder relays stations out of the phone's range.
      final s = MeshStore();
      s.applyStatus('far',
          MeshStatus.fromJson({'station': 'Depot-9', 'mainFault': 'OK'}, at: _t0));
      expect(s.length, 1);
      expect(s['far']!.label, 'Depot-9');
      expect(s['far']!.kind, MeshBeaconKind.unknown);
    });

    test('sorts worst first, then by name', () {
      final s = MeshStore();
      for (final e in [
        ('n1', 'Zeta', 'OK', 0),
        ('n2', 'Alpha', 'RS485_DEAD', 2),
        ('n3', 'Beta', 'WIFI_DOWN', 1),
        ('n4', 'Alpha2', 'OVER_TEMP', 2),
      ]) {
        s.applyStatus(e.$1, MeshStatus.fromJson(
            {'station': e.$2, 'mainFault': e.$3, 'severity': e.$4}, at: _t0));
      }
      s.observe(id: 'n5', beacon: proxy(), rssi: -50, at: _t0); // no status
      final order = s.sorted().map((n) => n.label).toList();
      expect(order.take(2), ['Alpha', 'Alpha2'], reason: 'both CRITICAL');
      expect(order[2], 'Beta');
      expect(order[3], 'Zeta');
      expect(order.last, 'n5',
          reason: 'unknown sorts below INFO, never above it');
    });

    test('counts separate provisioned, unprovisioned and faulted', () {
      final s = MeshStore();
      s.observe(id: 'n1', beacon: unprov(), rssi: -50, at: _t0);
      s.observe(id: 'n2', beacon: proxy(), rssi: -50, at: _t0);
      s.observe(id: 'n3', beacon: proxy(), rssi: -50, at: _t0);
      expect(s.unprovisionedCount, 1);
      expect(s.provisionedCount, 2);
      expect(s.faultedCount, 0, reason: 'no status yet is not a fault');

      s.applyStatus('n2', MeshStatus.fromJson(
          {'mainFault': 'RS485_DEAD', 'severity': 2}, at: _t0));
      expect(s.faultedCount, 1);
      expect(s.anyCriticalAt(_t0), isTrue);
    });

    test('statusCount separates "all healthy" from "nothing reported"', () {
      // The distinction the "reports not readable" card hangs on.
      final s = MeshStore();
      s.observe(id: 'n1', beacon: proxy(), rssi: -50, at: _t0);
      s.observe(id: 'n2', beacon: proxy(), rssi: -50, at: _t0);
      expect(s.statusCount, 0);
      expect(s.faultedCount, 0, reason: 'both zero, but for opposite reasons');

      s.applyStatus('n1', MeshStatus.fromJson({'mainFault': 'OK'}, at: _t0));
      s.applyStatus('n2', MeshStatus.fromJson({'mainFault': 'OK'}, at: _t0));
      expect(s.statusCount, 2, reason: 'healthy nodes still count as reporting');
      expect(s.faultedCount, 0);
    });

    test('a critical that went stale stops raising the alarm', () {
      final s = MeshStore();
      s.applyStatus('n1', MeshStatus.fromJson(
          {'mainFault': 'RS485_DEAD', 'severity': 2}, at: _t0));
      expect(s.anyCriticalAt(_t0.add(const Duration(seconds: 5))), isTrue);
      expect(s.anyCriticalAt(_t0.add(const Duration(seconds: 30))), isFalse);
    });

    test('clear empties the store', () {
      final s = MeshStore();
      s.observe(id: 'n1', beacon: proxy(), rssi: -50, at: _t0);
      s.clear();
      expect(s.isEmpty, isTrue);
      expect(s.length, 0);
    });
  });
}
