// ══════════════════════════════════════════════════════════════
//  health.dart — the station's own health record
//
//  Mirrors the Health characteristic (e1ec0004 / e1ec0402), which carries
//  byte-for-byte the same JSON the gateway publishes to the MQTT .../health
//  topic. One builder in the firmware feeds both, so what this screen shows
//  and what the server dashboard shows cannot diverge.
//
//  Spec: doc/md/BLE_App_Integration.md §3.9
// ══════════════════════════════════════════════════════════════

/// Cabinet probe flags, register 32339. The three "fitted" bits are
/// compile-time constants on the STM32 master: they exist so the app can tell
/// "reads 0 because the probe reports 0" from "reads 0 because no probe is
/// installed". Never raise an alarm on a zero whose fitted bit is clear.
class SensorFlags {
  static const int waterHigh     = 0x0001;
  static const int smokeDetected = 0x0002;
  static const int dht11Fitted   = 0x0100;
  static const int waterFitted   = 0x0200;
  static const int smokeFitted   = 0x0400;
}

/// One decoded gateway fault, as a display pair.
class HealthFlag {
  final String key;    // JSON key, e.g. "rs485_fault"
  final String label;  // human text, e.g. "RS485 link"
  const HealthFlag(this.key, this.label);
}

/// The gateway's own fault booleans, in the order the firmware sets them
/// (FaultIdTypeDef in Task_handler.h). `bitmap` carries the same word in hex.
const List<HealthFlag> kHealthFlags = [
  HealthFlag('sd_fault',     'SD card'),
  HealthFlag('ntp_fault',    'Time sync'),
  HealthFlag('mqtt_fault',   'Cloud (MQTT)'),
  HealthFlag('wifi_fault',   'WiFi'),
  HealthFlag('rs485_fault',  'RS485 link'),
  HealthFlag('reboot_fault', 'Abnormal reboot'),
  HealthFlag('brownout',     'Brownout'),
  HealthFlag('queue_full',   'Offline queue full'),
  HealthFlag('low_heap',     'Low memory'),
];

/// A parsed health record. Every block below the gateway's own fields is
/// OPTIONAL: the firmware omits the master block until it has actually read
/// the STM32's status registers, and omits each sensor whose probe is not
/// fitted. A missing key therefore means "unknown", never "zero" — which is
/// why every accessor here is nullable rather than defaulting.
class StationHealth {
  final DateTime at;
  final String stationId;
  final String ts;
  final String bitmapHex;
  final Map<String, bool> flags;   // keyed by HealthFlag.key

  final String resetReason;
  final int? totalHeap, freeHeap, rssi;
  final String sdMounted;
  final int? pods;                 // "slaves"
  final String version;

  // ── Master (STM32) block — absent until the status read succeeds ──
  final int? podsOnline, podsOffline, masterFw, masterReset;
  final bool masterCrashed, masterBrownout;

  // ── Cabinet sensors — each absent when its probe is not fitted ──
  final int? sensorFlags;
  final double? cabTempC, cabHumidity;
  final int? waterRaw, smokeRaw;
  final bool waterAlarm, smokeAlarm;

  const StationHealth({
    required this.at,
    required this.stationId,
    required this.ts,
    required this.bitmapHex,
    required this.flags,
    required this.resetReason,
    required this.totalHeap,
    required this.freeHeap,
    required this.rssi,
    required this.sdMounted,
    required this.pods,
    required this.version,
    required this.podsOnline,
    required this.podsOffline,
    required this.masterFw,
    required this.masterReset,
    required this.masterCrashed,
    required this.masterBrownout,
    required this.sensorFlags,
    required this.cabTempC,
    required this.cabHumidity,
    required this.waterRaw,
    required this.smokeRaw,
    required this.waterAlarm,
    required this.smokeAlarm,
  });

  /// Returns null when the frame carries no station_id — a truncated payload
  /// must never overwrite a good record.
  static StationHealth? fromJson(Map<String, dynamic> j, DateTime at) {
    final sid = (j['station_id'] as String?)?.trim();
    if (sid == null || sid.isEmpty) return null;

    int? asInt(String k) => (j[k] as num?)?.toInt();
    double? asDouble(String k) => (j[k] as num?)?.toDouble();
    bool asBool(String k) => ((j[k] as num?)?.toInt() ?? 0) != 0;

    final f = <String, bool>{};
    for (final hf in kHealthFlags) {
      f[hf.key] = asBool(hf.key);
    }

    return StationHealth(
      at: at,
      stationId: sid,
      ts: (j['TS'] as String?) ?? '',
      bitmapHex: (j['bitmap'] as String?) ?? '0x00000000',
      flags: f,
      resetReason: (j['reset_reason'] as String?) ?? '',
      totalHeap: asInt('total_heap'),
      freeHeap: asInt('free_heap'),
      rssi: asInt('rssi'),
      sdMounted: (j['sd_mounted'] as String?) ?? '',
      pods: asInt('slaves'),
      version: (j['version'] as String?) ?? '',
      podsOnline: asInt('pods_online'),
      podsOffline: asInt('pods_offline'),
      masterFw: asInt('master_fw'),
      masterReset: asInt('master_reset'),
      masterCrashed: asBool('master_crashed'),
      masterBrownout: asBool('master_brownout'),
      sensorFlags: asInt('sensor_flags'),
      cabTempC: asDouble('cab_temp_c'),
      cabHumidity: asDouble('cab_humidity'),
      waterRaw: asInt('water_raw'),
      smokeRaw: asInt('smoke_raw'),
      waterAlarm: asBool('water_alarm'),
      smokeAlarm: asBool('smoke_alarm'),
    );
  }

  /// The master block is present only once the gateway has read the STM32's
  /// status registers and they passed their sanity check.
  bool get hasMaster => podsOnline != null;

  /// True when the gateway reports no faults of its own.
  bool get healthy => !flags.values.any((v) => v);

  /// Names of the active gateway faults, ready to list.
  List<String> get activeFaults =>
      kHealthFlags.where((hf) => flags[hf.key] == true).map((hf) => hf.label).toList();

  /// "v1.7" from the BCD word the master reports (263 == 0x0107).
  String get masterVersion {
    final v = masterFw;
    if (v == null) return '-';
    return 'v${(v >> 8) & 0xFF}.${v & 0xFF}';
  }

  /// Pod numbers the MASTER believes are responding. Read from the bitmap
  /// rather than the pod list, so it reflects the STM32's own debounced view.
  List<int> get onlinePods {
    final m = podsOnline;
    final n = pods ?? 0;
    if (m == null) return const [];
    return [for (var i = 0; i < n; i++) if ((m >> i) & 1 == 1) i + 1];
  }

  List<int> get offlinePods {
    final m = podsOffline;
    final n = pods ?? 0;
    if (m == null) return const [];
    return [for (var i = 0; i < n; i++) if ((m >> i) & 1 == 1) i + 1];
  }

  bool _fitted(int mask) => ((sensorFlags ?? 0) & mask) != 0;

  bool get hasClimate    => _fitted(SensorFlags.dht11Fitted);
  bool get hasWaterProbe => _fitted(SensorFlags.waterFitted);
  bool get hasSmokeProbe => _fitted(SensorFlags.smokeFitted);
  bool get hasAnySensor  => hasClimate || hasWaterProbe || hasSmokeProbe;

  /// Anything here should interrupt the operator, not sit in a list.
  bool get hasUrgentAlarm => waterAlarm || smokeAlarm || masterCrashed;

  @override
  String toString() =>
      'StationHealth($stationId, $bitmapHex, master=${hasMaster ? masterVersion : "-"})';
}

// ══════════════════════════════════════════════════════════════
//  Pod lock state — Pod Locks characteristic (e1ec0002 / e1ec0204)
//  Spec: doc/md/BLE_App_Integration.md §3.5
// ══════════════════════════════════════════════════════════════

class PodLock {
  final int pod;
  final String lock;    // "open" / "close" — the same word the MQTT ACK uses
  final int raw;        // full pod status word; lock is bit 0
  final int relay;      // relay drive register — NOT the lock
  final bool online;
  final bool swapping;  // a swap is in progress: the door was opened on purpose
  final int swapTimeout;

  const PodLock({
    required this.pod,
    required this.lock,
    required this.raw,
    required this.relay,
    required this.online,
    required this.swapping,
    required this.swapTimeout,
  });

  bool get isOpen => lock == 'open';

  /// An open door with no swap behind it is the case worth flagging: nobody
  /// asked for it to be open. With a swap in progress it is simply normal.
  bool get isUnexplainedOpen => isOpen && !swapping;

  static PodLock? fromJson(Map<String, dynamic> j) {
    final p = (j['pod'] as num?)?.toInt();
    if (p == null) return null;
    return PodLock(
      pod: p,
      lock: (j['lock'] as String?) ?? '',
      raw: (j['raw'] as num?)?.toInt() ?? 0,
      relay: (j['relay'] as num?)?.toInt() ?? 0,
      online: ((j['online'] as num?)?.toInt() ?? 0) != 0,
      swapping: ((j['swap'] as num?)?.toInt() ?? 0) != 0,
      swapTimeout: (j['swap_to'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() => 'Pod $pod $lock${swapping ? " (swapping)" : ""}';
}

/// Parsed Pod Locks frame: every pod's door in one payload.
class PodLockSet {
  final DateTime at;
  final String stationId;
  final int totalPods;
  final Map<int, PodLock> byPod;

  const PodLockSet({
    required this.at,
    required this.stationId,
    required this.totalPods,
    required this.byPod,
  });

  static PodLockSet? fromJson(Map<String, dynamic> j, DateTime at) {
    final sid = (j['station_id'] as String?)?.trim();
    if (sid == null || sid.isEmpty) return null;

    final list = j['locks'];
    if (list is! List) return null;

    final map = <int, PodLock>{};
    for (final e in list) {
      if (e is! Map) continue;
      final pl = PodLock.fromJson(e.cast<String, dynamic>());
      if (pl != null) map[pl.pod] = pl;
    }

    return PodLockSet(
      at: at,
      stationId: sid,
      totalPods: (j['total_pods'] as num?)?.toInt() ?? map.length,
      byPod: map,
    );
  }

  PodLock? operator [](int pod) => byPod[pod];

  List<int> get openPods =>
      (byPod.values.where((l) => l.isOpen).map((l) => l.pod).toList()..sort());

  /// Doors that are open with no swap explaining it.
  List<int> get unexplainedOpenPods =>
      (byPod.values.where((l) => l.isUnexplainedOpen).map((l) => l.pod).toList()..sort());

  @override
  String toString() => 'PodLockSet($stationId, ${byPod.length} pods, open=$openPods)';
}
