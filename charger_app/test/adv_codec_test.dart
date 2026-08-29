import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bss_charger_monitor/src/models/charger_adv.dart';

/// Builds a manufacturer payload byte-for-byte the way
/// `ChargerBLE_BuildAdvPayload()` does in the firmware. If this helper and the
/// C function ever drift apart, these tests are what catches it.
///
/// Note the payload here excludes the 2-byte company ID: flutter_blue_plus
/// keys `manufacturerData` by company ID and hands back only the bytes after
/// it, which is exactly what the decoder is given at runtime.
Uint8List buildPayload({
  int protoVer = 1,
  required int chargerId,
  int chargerState = 1,
  int faultBitmap = 0,
  int aFlags = 0,
  int aSoc = 0,
  int aVoltDeci = 0,
  int aTemp = 0,
  int bFlags = 0,
  int bSoc = 0,
  int bVoltDeci = 0,
  int bTemp = 0,
  int seq = 0,
}) {
  final d = Uint8List(17);
  final bd = ByteData.sublistView(d);
  d[0] = protoVer;
  bd.setUint16(1, chargerId, Endian.little);
  d[3] = chargerState;
  d[4] = faultBitmap;
  d[5] = aFlags;
  d[6] = aSoc;
  bd.setUint16(7, aVoltDeci, Endian.little);
  bd.setInt8(9, aTemp);
  d[10] = bFlags;
  d[11] = bSoc;
  bd.setUint16(12, bVoltDeci, Endian.little);
  bd.setInt8(14, bTemp);
  bd.setUint16(15, seq, Endian.little);
  return d;
}

/// Bay flags: bit7 present, bit6 relay, bit5 balancing, bits3..0 state.
int bayFlags({
  bool present = false,
  bool relay = false,
  bool balancing = false,
  int state = 0,
}) =>
    (present ? 0x80 : 0) |
    (relay ? 0x40 : 0) |
    (balancing ? 0x20 : 0) |
    (state & 0x0F);

ChargerSnapshot? decode(Uint8List payload) => ChargerAdvCodec.decode(
      manufacturerPayload: payload,
      deviceId: 'AA:BB:CC:DD:EE:FF',
      name: 'BSSC_0007',
      rssi: -61,
      seenAt: DateTime(2026, 8, 24, 12, 0, 0),
    );

void main() {
  group('ChargerAdvCodec.decode', () {
    test('decodes a charger with both bays occupied', () {
      final snap = decode(buildPayload(
        chargerId: 7,
        chargerState: 1, // charging
        aFlags: bayFlags(present: true, relay: true, state: 2), // charging
        aSoc: 64,
        aVoltDeci: 4682, // 468.2 V
        aTemp: 34,
        bFlags: bayFlags(present: true, state: 3), // full
        bSoc: 100,
        bVoltDeci: 5120, // 512.0 V
        bTemp: 29,
        seq: 4821,
      ))!;

      expect(snap.chargerId, 7);
      expect(snap.name, 'BSSC_0007');
      expect(snap.state, ChargerState.charging);
      expect(snap.seq, 4821);
      expect(snap.rssi, -61);
      expect(snap.hasFault, isFalse);
      expect(snap.batteriesPresent, 2);

      final a = snap.bays[0];
      expect(a.bay, 1);
      expect(a.label, 'A');
      expect(a.present, isTrue);
      expect(a.relayClosed, isTrue);
      expect(a.balancing, isFalse);
      expect(a.state, BayState.charging);
      expect(a.soc, 64);
      expect(a.volts, closeTo(468.2, 0.001));
      expect(a.tempC, 34);

      final b = snap.bays[1];
      expect(b.label, 'B');
      expect(b.state, BayState.full);
      expect(b.soc, 100);
      expect(b.volts, closeTo(512.0, 0.001));
      expect(b.relayClosed, isFalse);

      expect(snap.averageSoc, closeTo(82.0, 0.001));
    });

    test('an empty bay reports no SOC rather than zero', () {
      // A slot with nothing in it must not read as a flat battery — the fleet
      // low-SOC worklist would fill up with empty bays.
      final snap = decode(buildPayload(
        chargerId: 12,
        aFlags: bayFlags(present: true, state: 2),
        aSoc: 55,
        aVoltDeci: 4400,
        aTemp: 30,
        bFlags: bayFlags(state: 0), // empty
        bSoc: 0,
      ))!;

      expect(snap.batteriesPresent, 1);
      expect(snap.bays[1].present, isFalse);
      expect(snap.bays[1].state, BayState.empty);
      expect(snap.bays[1].soc, isNull);
      expect(snap.bays[1].tempC, isNull);
      expect(snap.averageSoc, closeTo(55.0, 0.001));
    });

    test('honours the unknown sentinels', () {
      final snap = decode(buildPayload(
        chargerId: 3,
        aFlags: bayFlags(present: true, state: 1),
        aSoc: 0xFF, // CHG_SOC_UNKNOWN
        aVoltDeci: 0,
        aTemp: -128, // CHG_TEMP_UNKNOWN
      ))!;

      expect(snap.bays[0].present, isTrue);
      expect(snap.bays[0].soc, isNull);
      expect(snap.bays[0].tempC, isNull);
    });

    test('reads negative bay temperatures as signed', () {
      final snap = decode(buildPayload(
        chargerId: 4,
        aFlags: bayFlags(present: true, state: 1),
        aSoc: 40,
        aTemp: -15,
      ))!;
      expect(snap.bays[0].tempC, -15);
    });

    test('decodes the fault bitmap into labels', () {
      final snap = decode(buildPayload(
        chargerId: 9,
        chargerState: 3,
        faultBitmap: (1 << 3) | (1 << 7), // over-temp + mains fail
      ))!;

      expect(snap.hasFault, isTrue);
      expect(snap.state, ChargerState.fault);
      expect(snap.faults, ['Over-temperature', 'Mains supply failure']);
    });

    test('a charger with no batteries has no average SOC', () {
      final snap = decode(buildPayload(chargerId: 21, chargerState: 0))!;
      expect(snap.batteriesPresent, 0);
      expect(snap.averageSoc, isNull);
    });

    test('rejects a truncated payload', () {
      expect(
        ChargerAdvCodec.decode(
          manufacturerPayload: List.filled(10, 0),
          deviceId: 'x',
          name: 'BSSC_0001',
          rssi: -50,
          seenAt: DateTime(2026),
        ),
        isNull,
      );
    });

    test('rejects an unknown protocol version', () {
      expect(decode(buildPayload(protoVer: 0x02, chargerId: 1)), isNull);
    });

    test('falls back to a synthetic name when the scan response is missing', () {
      // Android often delivers the ADV packet before the scan response, so the
      // advertised name can be empty on the first sighting.
      final snap = ChargerAdvCodec.decode(
        manufacturerPayload: buildPayload(chargerId: 42),
        deviceId: 'AA',
        name: '',
        rssi: -70,
        seenAt: DateTime(2026),
      )!;
      expect(snap.name, 'BSSC_0042');
    });

    test('16-bit fields survive values above one byte', () {
      final snap = decode(buildPayload(
        chargerId: 50,
        aFlags: bayFlags(present: true, state: 2),
        aSoc: 77,
        aVoltDeci: 6553, // 655.3 V
        seq: 65535,
      ))!;
      expect(snap.chargerId, 50);
      expect(snap.seq, 65535);
      expect(snap.bays[0].volts, closeTo(655.3, 0.001));
    });
  });

  group('staleness', () {
    test('a charger unheard past the window is stale', () {
      final snap = decode(buildPayload(chargerId: 1))!;
      final seen = snap.seenAt;
      expect(
          snap.isStale(seen.add(const Duration(seconds: 5)),
              const Duration(seconds: 12)),
          isFalse);
      expect(
          snap.isStale(seen.add(const Duration(seconds: 30)),
              const Duration(seconds: 12)),
          isTrue);
    });
  });
}
