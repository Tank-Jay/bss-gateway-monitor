import 'dart:typed_data';

/// Charger-level state, advertisement byte 3.
enum ChargerState { idle, charging, complete, fault, maintenance, unknown }

/// Per-bay state, low nibble of the bay flags byte.
enum BayState { empty, idle, charging, full, fault, balancing, unknown }

ChargerState chargerStateFromInt(int v) => switch (v) {
      0 => ChargerState.idle,
      1 => ChargerState.charging,
      2 => ChargerState.complete,
      3 => ChargerState.fault,
      4 => ChargerState.maintenance,
      _ => ChargerState.unknown,
    };

BayState bayStateFromInt(int v) => switch (v) {
      0 => BayState.empty,
      1 => BayState.idle,
      2 => BayState.charging,
      3 => BayState.full,
      4 => BayState.fault,
      5 => BayState.balancing,
      _ => BayState.unknown,
    };

extension ChargerStateLabel on ChargerState {
  String get label => switch (this) {
        ChargerState.idle => 'Idle',
        ChargerState.charging => 'Charging',
        ChargerState.complete => 'Complete',
        ChargerState.fault => 'Fault',
        ChargerState.maintenance => 'Maintenance',
        ChargerState.unknown => 'Unknown',
      };
}

extension BayStateLabel on BayState {
  String get label => switch (this) {
        BayState.empty => 'Empty',
        BayState.idle => 'Idle',
        BayState.charging => 'Charging',
        BayState.full => 'Full',
        BayState.fault => 'Fault',
        BayState.balancing => 'Balancing',
        BayState.unknown => 'Unknown',
      };
}

/// Fault bitmap, advertisement byte 4.
const List<String> kFaultLabels = [
  'Over-voltage',
  'Under-voltage',
  'Over-current',
  'Over-temperature',
  'Under-temperature',
  'BMS comm loss',
  'Door / interlock open',
  'Mains supply failure',
];

List<String> decodeFaults(int bitmap) {
  final out = <String>[];
  for (var i = 0; i < kFaultLabels.length; i++) {
    if (bitmap & (1 << i) != 0) out.add(kFaultLabels[i]);
  }
  return out;
}

/// One bay as seen from the advertisement. Everything here arrives without a
/// connection, which is what lets the fleet screen show 100 batteries at once.
class BaySnapshot {
  final int bay; // 1 or 2
  final bool present;
  final bool relayClosed;
  final bool balancing;
  final BayState state;

  /// null when the bay is empty or the charger reported the unknown sentinel.
  final int? soc;
  final double volts;
  final int? tempC;

  const BaySnapshot({
    required this.bay,
    required this.present,
    required this.relayClosed,
    required this.balancing,
    required this.state,
    required this.soc,
    required this.volts,
    required this.tempC,
  });

  String get label => bay == 1 ? 'A' : 'B';

  const BaySnapshot.empty(this.bay)
      : present = false,
        relayClosed = false,
        balancing = false,
        state = BayState.empty,
        soc = null,
        volts = 0,
        tempC = null;
}

/// A charger as seen from a scan result — no GATT connection involved.
class ChargerSnapshot {
  final String deviceId; // BLE MAC / remote id
  final String name; // BSSC_0001
  final int chargerId; // 1..50
  final int protoVer;
  final ChargerState state;
  final int faultBitmap;
  final int seq; // firmware heartbeat counter
  final int rssi;
  final DateTime seenAt;
  final List<BaySnapshot> bays;

  const ChargerSnapshot({
    required this.deviceId,
    required this.name,
    required this.chargerId,
    required this.protoVer,
    required this.state,
    required this.faultBitmap,
    required this.seq,
    required this.rssi,
    required this.seenAt,
    required this.bays,
  });

  bool get hasFault => faultBitmap != 0 || state == ChargerState.fault;

  List<String> get faults => decodeFaults(faultBitmap);

  int get batteriesPresent => bays.where((b) => b.present).length;

  /// Mean SOC across occupied bays — used for the fleet summary header.
  double? get averageSoc {
    final vals = bays
        .where((b) => b.present && b.soc != null)
        .map((b) => b.soc!)
        .toList();
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  /// A charger that has stopped advertising is stale, not gone — the fleet
  /// screen greys it out rather than dropping the row, so an operator can see
  /// that a unit went quiet.
  bool isStale(DateTime now, Duration after) =>
      now.difference(seenAt) > after;
}

/// Decodes the 17-byte manufacturer payload defined in
/// `doc/Charger_BLE_Protocol.md` §2.3.
class ChargerAdvCodec {
  static const int payloadLen = 17;
  static const int socUnknown = 0xFF;
  static const int tempUnknown = -128;

  /// Returns null when the payload is not ours, is truncated, or carries a
  /// protocol version this build does not understand. Callers treat null as
  /// "not a charger" and skip the scan result.
  static ChargerSnapshot? decode({
    required List<int> manufacturerPayload,
    required String deviceId,
    required String name,
    required int rssi,
    required DateTime seenAt,
  }) {
    if (manufacturerPayload.length < payloadLen) return null;

    final d = Uint8List.fromList(manufacturerPayload);
    final bd = ByteData.sublistView(d);

    final protoVer = d[0];
    if (protoVer != 0x01) return null;

    final chargerId = bd.getUint16(1, Endian.little);
    final state = chargerStateFromInt(d[3]);
    final faults = d[4];

    final bayA = _decodeBay(bay: 1, flags: d[5], soc: d[6], voltRaw: bd.getUint16(7, Endian.little), tempRaw: bd.getInt8(9));
    final bayB = _decodeBay(bay: 2, flags: d[10], soc: d[11], voltRaw: bd.getUint16(12, Endian.little), tempRaw: bd.getInt8(14));

    final seq = bd.getUint16(15, Endian.little);

    return ChargerSnapshot(
      deviceId: deviceId,
      name: name.isNotEmpty ? name : 'BSSC_${chargerId.toString().padLeft(4, '0')}',
      chargerId: chargerId,
      protoVer: protoVer,
      state: state,
      faultBitmap: faults,
      seq: seq,
      rssi: rssi,
      seenAt: seenAt,
      bays: [bayA, bayB],
    );
  }

  static BaySnapshot _decodeBay({
    required int bay,
    required int flags,
    required int soc,
    required int voltRaw,
    required int tempRaw,
  }) {
    final present = flags & 0x80 != 0;
    return BaySnapshot(
      bay: bay,
      present: present,
      relayClosed: flags & 0x40 != 0,
      balancing: flags & 0x20 != 0,
      state: bayStateFromInt(flags & 0x0F),
      soc: (!present || soc == socUnknown) ? null : soc.clamp(0, 100),
      volts: voltRaw / 10.0, // firmware sends 0.1 V units
      tempC: (!present || tempRaw == tempUnknown) ? null : tempRaw,
    );
  }
}
