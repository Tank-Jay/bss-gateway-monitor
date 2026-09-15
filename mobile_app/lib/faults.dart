// ══════════════════════════════════════════════════════════════
//  Fault model for the Diagnostics service (e1ec0004 / e1ec0401)
//
//  Pure Dart — no Flutter imports — so it is unit-testable and so the
//  decode tables live in exactly one place.
//
//  Every table here mirrors the firmware, NOT the prose tiers in
//  doc/BLE_App_Integration.md §4.3. The doc's tier list disagrees with the
//  shipping firmware in two places (STA-09 is ranked far too low, and
//  STA-02/STA-08 are swapped), so ranking faults app-side from the doc would
//  disagree with the `main` object the gateway actually sends.
//
//  Source of truth:
//    src/Mqtt_Handler/Mqtt_handler.cpp  Fault_PodPriority / Fault_PodSev /
//                                       Fault_PodText / Fault_StaPriority /
//                                       Fault_StaSev / Fault_StaText /
//                                       Fault_MainError
//    src/Task_Handler/Task_handler.h    FaultIdTypeDef (station bit order)
// ══════════════════════════════════════════════════════════════

/// Per-pod fault text, bit 0..7 → POD-01..POD-08.
/// Verbatim from Fault_PodText(). The lowercase entries are deliberate: the
/// firmware composes `main.msg` as "Pod N <text>", so keeping the same
/// strings means a fault never appears with two different wordings on one
/// screen. Use [FaultCode.sentence] when rendering the text standalone.
const List<String> kPodText = [
  'BMS comm lost',        // bit 0 — POD-01
  'lock failed to open',  // bit 1 — POD-02
  'lock stuck',           // bit 2 — POD-03
  'STM32 no-echo',        // bit 3 — POD-04
  'cell over-voltage',    // bit 4 — POD-05
  'cell under-voltage',   // bit 5 — POD-06
  'over-temperature',     // bit 6 — POD-07
  'BMS hard error',       // bit 7 — POD-08
];

/// Station fault text, bit 0..9 → STA-01..STA-10. Verbatim from Fault_StaText().
const List<String> kStaText = [
  'SD card fault',           // bit 0 — STA-01
  'Time not synced',         // bit 1 — STA-02
  'Cloud link down',         // bit 2 — STA-03
  'WiFi disconnected',       // bit 3 — STA-04
  'RS485/STM32 link dead',   // bit 4 — STA-05
  'Abnormal reboot',         // bit 5 — STA-06
  'Brownout reset',          // bit 6 — STA-07
  'Audio module not ready',  // bit 7 — STA-08
  'Offline queue full',      // bit 8 — STA-09
  'Low memory',              // bit 9 — STA-10
];

/// Firmware's default text for a station bit with no enum member.
/// The scan loop covers bits 0..31 but FaultIdTypeDef stops at 9, so bits
/// 10..31 arrive as STA-11..STA-32 carrying this literal.
const String kUnknownFaultText = 'Fault';

/// Pod bits that cannot be set by the shipping firmware build.
///
/// `CURRENT_BMS = OTHER_METHOD` in src/Feature_Config.h, so the LITHION and
/// AKTIVOLT decode branches are compiled out and bits 4..7 stay 0; bit 3 has
/// no per-pod echo store yet (TODO in Fault_ComputePodBytes).
///
/// This exists so the UI can say "not reported by this firmware" instead of
/// implying a healthy battery. It must never be used to *suppress* a bit —
/// if a future build sets one, it has to show up.
const Set<int> kPodBitsNotInstrumented = {3, 4, 5, 6, 7};

/// Mirrors Fault_PodPriority(). Higher = more urgent.
int podWeight(int bit) {
  switch (bit) {
    case 6: return 100;
    case 7: return 98;
    case 1: return 70;
    case 3: return 68;
    case 0: return 66;
    case 4: return 40;
    case 5: return 38;
    case 2: return 35;
  }
  return 10;
}

/// Mirrors Fault_PodSev(): bits 0,1,3,6,7 are CRITICAL, the rest WARNING.
/// No pod fault ever reports INFO.
int podSev(int bit) =>
    (bit == 6 || bit == 7 || bit == 1 || bit == 3 || bit == 0) ? 2 : 1;

/// Mirrors Fault_StaPriority(), keyed by FaultIdTypeDef bit.
int staWeight(int bit) {
  switch (bit) {
    case 4: return 90;  // RS485
    case 6: return 88;  // BROWNOUT
    case 0: return 50;  // SD_MOUNT
    case 2: return 45;  // MQTT_CONNECT
    case 3: return 44;  // WIFI
    case 8: return 40;  // SD_QUEUE_FULL
    case 7: return 30;  // AUDIO
    case 1: return 25;  // NTP_SYNC
    case 5: return 24;  // REBOOT
    case 9: return 20;  // LOW_HEAP
  }
  return 10;
}

/// Mirrors Fault_StaSev(). Note LOW_HEAP is the only fault that reports INFO —
/// which is why a banner must never be hidden on `sev == 0`.
int staSev(int bit) {
  if (bit == 4 || bit == 6 || bit == 0) return 2; // RS485, BROWNOUT, SD_MOUNT
  if (bit == 9) return 0;                         // LOW_HEAP
  return 1;
}

String staText(int bit) =>
    (bit >= 0 && bit < kStaText.length) ? kStaText[bit] : kUnknownFaultText;

String _code(String prefix, int bit) =>
    '$prefix-${(bit + 1).toString().padLeft(2, '0')}';

/// One decoded fault bit.
class FaultCode {
  /// "POD-07" / "STA-05". Format matches the firmware's `"%s-%02u"`.
  final String code;

  /// Firmware wording, verbatim.
  final String text;

  /// 2 = CRITICAL, 1 = WARNING, 0 = INFO.
  final int sev;

  /// Firmware priority weight; higher is more urgent.
  final int weight;

  /// Pod number, or 0 for a station-level fault.
  final int slot;

  const FaultCode({
    required this.code,
    required this.text,
    required this.sev,
    required this.weight,
    required this.slot,
  });

  bool get isStation => slot == 0;

  /// Bit index this decoded from (0-based), derived from the code number.
  int get bit => int.parse(code.substring(4)) - 1;

  /// True when the firmware build cannot currently set this bit, so "not
  /// active" carries no information about the hardware.
  bool get notInstrumented => !isStation && kPodBitsNotInstrumented.contains(bit);

  /// The firmware's own word code for this bit — `RS485_DEAD`, `LOCK_FAIL`.
  ///
  /// A different identifier from [code]: `STA-05` is the label this app
  /// composes for display, while this is what the gateway actually puts on the
  /// wire. The fault-fix ops in §3.5 are keyed by THIS one, so a Fix button
  /// that sent [code] instead would get `"status":"error"` every time.
  String get wordCode {
    if (isStation) {
      return bit >= 0 && bit < kStaCode.length ? kStaCode[bit] : kStaCodeUnknown;
    }
    return bit >= 0 && bit < kPodCode.length ? kPodCode[bit] : kStaCodeUnknown;
  }

  /// Text with a capital first letter, for standalone display. Derived from
  /// [text] rather than stored, so the two can never drift apart.
  String get sentence =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

  /// How this fault reads with its slot, matching the firmware's `main.msg`
  /// composition ("Pod 2 lock failed to open").
  String get withPod => isStation ? text : 'Pod $slot $text';

  @override
  String toString() => '$code($sev) $withPod';
}

/// Decode the 32-bit station fault word. Covers bits 0..31 the way the
/// firmware's scan loop does — anything past bit 9 becomes STA-11..STA-32.
List<FaultCode> decodeStation(int sta) {
  final out = <FaultCode>[];
  for (var b = 0; b < 32; b++) {
    if (sta & (1 << b) == 0) continue;
    out.add(FaultCode(
      code: _code('STA', b),
      text: staText(b),
      sev: staSev(b),
      weight: staWeight(b),
      slot: 0,
    ));
  }
  return out;
}

/// Decode one pod's fault byte. [slot] is the 1-based pod number.
List<FaultCode> decodePod(int f, int slot) {
  final out = <FaultCode>[];
  for (var b = 0; b < 8; b++) {
    if (f & (1 << b) == 0) continue;
    out.add(FaultCode(
      code: _code('POD', b),
      text: kPodText[b],
      sev: podSev(b),
      weight: podWeight(b),
      slot: slot,
    ));
  }
  return out;
}

/// Sort faults the way Fault_MainError picks its winner: by weight descending,
/// and on an exact tie the pod entry wins (the firmware scans pods first and
/// uses a strict `>`). Without the tie rule, POD-05 and STA-09 — both weight
/// 40 — would order arbitrarily and disagree with the gateway's own `main`.
int compareFaults(FaultCode a, FaultCode b) {
  if (a.weight != b.weight) return b.weight.compareTo(a.weight);
  if (a.isStation != b.isStation) return a.isStation ? 1 : -1;
  return a.slot.compareTo(b.slot);
}

/// The firmware-selected headline fault for one station.
class MainFault {
  final String code;
  final int slot;
  final int sev;

  /// Ready-to-display text. Empty string when [isOk] — the firmware sends
  /// `"msg":""` rather than a friendly phrase, so the app supplies its own.
  final String msg;

  const MainFault({
    required this.code,
    required this.slot,
    required this.sev,
    required this.msg,
  });

  /// The ONLY safe test for "nothing wrong".
  ///
  /// Do not gate on `sev == 0`: STA-10 (low memory) is a genuine INFO fault
  /// that also reports sev 0 and slot 0, so hiding on severity would silently
  /// swallow it.
  bool get isOk => code == 'OK';

  static const MainFault ok =
      MainFault(code: 'OK', slot: 0, sev: 0, msg: '');

  factory MainFault.fromJson(Map<String, dynamic>? j) {
    if (j == null) return ok;
    return MainFault(
      code: (j['code'] as String?) ?? 'OK',
      slot: (j['slot'] as num?)?.toInt() ?? 0,
      sev: (j['sev'] as num?)?.toInt() ?? 0,
      msg: (j['msg'] as String?) ?? '',
    );
  }
}

/// One pod entry inside a Faults payload.
class PodFault {
  final int p;
  final bool online;
  final int f;

  const PodFault({required this.p, required this.online, required this.f});

  List<FaultCode> get decoded => decodePod(f, p);

  bool get hasFault => f != 0;

  bool get hasCritical => decoded.any((c) => c.sev >= 2);

  /// Worst severity present, or null when the byte is clear.
  int? get worstSev {
    if (f == 0) return null;
    return decoded.map((c) => c.sev).reduce((a, b) => a > b ? a : b);
  }
}

/// One station's Diagnostics payload, plus when the app received it.
class StationFaults {
  final String sid;
  final int sta;
  final List<PodFault> pods;
  final MainFault main;

  /// Stamped by the app — the firmware sends no timestamp on this
  /// characteristic.
  final DateTime receivedAt;

  const StationFaults({
    required this.sid,
    required this.sta,
    required this.pods,
    required this.main,
    required this.receivedAt,
  });

  static StationFaults? fromJson(Map<String, dynamic> j, DateTime at) {
    final sid = j['sid'];
    if (sid is! String || sid.isEmpty) return null; // not a faults frame
    final rawPods = j['pods'];
    final pods = <PodFault>[];
    if (rawPods is List) {
      for (final e in rawPods) {
        if (e is! Map) continue;
        final m = e.cast<String, dynamic>();
        final p = (m['p'] as num?)?.toInt();
        if (p == null) continue;
        pods.add(PodFault(
          p: p,
          online: (m['on'] as num?)?.toInt() == 1,
          f: (m['f'] as num?)?.toInt() ?? 0,
        ));
      }
    }
    return StationFaults(
      sid: sid,
      sta: (j['sta'] as num?)?.toInt() ?? 0,
      pods: pods,
      main: MainFault.fromJson((j['main'] as Map?)?.cast<String, dynamic>()),
      receivedAt: at,
    );
  }

  /// Lookup by 1-based pod number.
  ///
  /// Returns null when this station reported no entry for that pod. The Pod
  /// Summary array and the Faults array are clamped by different firmware
  /// constants (BLE_MAX_PODS=5 vs NUMBER_OF_SLAVE=2), so their lengths can
  /// legitimately disagree — a missing entry means "unknown", never "healthy".
  PodFault? podFor(int p) {
    for (final e in pods) {
      if (e.p == p) return e;
    }
    return null;
  }

  /// Every active fault on this station, most urgent first.
  List<FaultCode> get allActive {
    final out = <FaultCode>[
      ...decodeStation(sta),
      for (final p in pods) ...p.decoded,
    ];
    out.sort(compareFaults);
    return out;
  }

  bool get healthy => main.isOk && sta == 0 && pods.every((p) => p.f == 0);

  bool isStale(DateTime now, {Duration after = kFaultStale}) =>
      now.difference(receivedAt) > after;
}

/// A station is stale after ~4 missed ticks.
///
/// The notify cadence is 1 s plus Arduino-loop jitter, and a busy loop can
/// skip a tick, so anything tighter than this produces false "offline" flags.
const Duration kFaultStale = Duration(seconds: 5);

/// Keyed store of the latest fault payload per station.
///
/// UPSERT ONLY — never replace the whole map from one notification.
/// `pCharFaults->notify()` in the firmware is called with no arguments, which
/// in NimBLE only flags the characteristic modified; the host task then sends
/// ONE frame carrying whatever value was stored last. So a tick that writes
/// four stations can still deliver a single frame. Absence of a station in any
/// given frame carries no information, and entries are aged out by time, never
/// dropped for being missing.
class FaultsStore {
  final Map<String, StationFaults> _bySid = {};

  Map<String, StationFaults> get bySid => Map.unmodifiable(_bySid);

  List<StationFaults> get stations {
    final list = _bySid.values.toList();
    list.sort((a, b) => a.sid.compareTo(b.sid));
    return list;
  }

  bool get isEmpty => _bySid.isEmpty;

  int get stationCount => _bySid.length;

  void upsert(StationFaults s) => _bySid[s.sid] = s;

  StationFaults? operator [](String sid) => _bySid[sid];

  void clear() => _bySid.clear();

  /// The single station whose payload the single-gateway UI should show.
  /// Today the firmware only ever reports one (BLE_SetStationFault has no call
  /// sites), but this keeps the UI correct if satellites ever appear.
  StationFaults? get primary =>
      _bySid.isEmpty ? null : stations.first;

  /// Highest-severity headline across every known station, for a global
  /// banner. Ignores stations reporting OK.
  MainFault? get worstMain {
    MainFault? best;
    for (final s in stations) {
      if (s.main.isOk) continue;
      if (best == null || s.main.sev > best.sev) best = s.main;
    }
    return best;
  }

  /// Every active fault across every station, most urgent first.
  List<FaultCode> get allActive {
    final out = <FaultCode>[];
    for (final s in stations) {
      out.addAll(s.allActive);
    }
    out.sort(compareFaults);
    return out;
  }

  int get activeCount => allActive.length;

  bool get anyCritical => allActive.any((c) => c.sev >= 2);
}

// ══════════════════════════════════════════════════════════════
//  Word codes — Fault_StaCode() / Fault_PodCode()
//
//  A SECOND namespace for the same bits. The "STA-05"/"POD-02" labels
//  above are composed by this app; these word codes are what the firmware
//  itself puts on the wire, in FaultMainTypeDef.code, in the mesh payload,
//  and in the fault-fix ops of spec 3.5 — which is why they live here
//  beside the text tables rather than in any one feature's file.
// ══════════════════════════════════════════════════════════════

/// Station word codes, bit 0..9. Verbatim from Fault_StaCode() in
/// src/Mqtt_Handler/Mqtt_handler.cpp, in FaultIdTypeDef order.
///
/// These are what `mainFault` actually contains. Note this is a different
/// namespace from the `STA-05` labels the app renders elsewhere: the firmware
/// never sends those, faults.dart composes them from the bit index.
const List<String> kStaCode = [
  'SD_FAULT', // bit 0 — FAULT_SD_MOUNT
  'TIME_UNSYNCED', // bit 1 — FAULT_NTP_SYNC
  'CLOUD_DOWN', // bit 2 — FAULT_MQTT_CONNECT
  'WIFI_DOWN', // bit 3 — FAULT_WIFI
  'RS485_DEAD', // bit 4 — FAULT_RS485
  'REBOOT_ABNORMAL', // bit 5 — FAULT_REBOOT
  'BROWNOUT', // bit 6 — FAULT_BROWNOUT
  'AUDIO_FAULT', // bit 7 — FAULT_AUDIO
  'QUEUE_FULL', // bit 8 — FAULT_SD_QUEUE_FULL
  'LOW_HEAP', // bit 9 — FAULT_LOW_HEAP
];

/// Per-pod word codes, bit 0..7. Verbatim from Fault_PodCode().
const List<String> kPodCode = [
  'POD_OFFLINE', // bit 0
  'LOCK_FAIL', // bit 1
  'LOCK_STUCK', // bit 2
  'NO_ECHO', // bit 3
  'CELL_OV', // bit 4
  'CELL_UV', // bit 5
  'OVER_TEMP', // bit 6
  'BMS_ERROR', // bit 7
];

/// Fault_StaCode()'s fallback for bits 10..31, which have no enum member.
/// It is not reversible to a bit — every unnamed station bit produces it.
const String kStaCodeUnknown = 'STA_FAULT';

/// Station bit for a word code, or null if it is not a station code.
int? staBitForCode(String code) {
  final i = kStaCode.indexOf(code);
  return i < 0 ? null : i;
}

/// Pod bit for a word code, or null if it is not a pod code.
int? podBitForCode(String code) {
  final i = kPodCode.indexOf(code);
  return i < 0 ? null : i;
}
