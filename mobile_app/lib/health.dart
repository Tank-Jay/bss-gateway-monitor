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
  final int bit;       // position in `bitmap`, FaultIdTypeDef in Task_handler.h
  const HealthFlag(this.key, this.label, this.bit);
}

/// The gateway's own faults. Current firmware publishes only `bitmap` and
/// leaves the named booleans out, so these are decoded from the word; older
/// firmware sends both and the explicit key wins.
///
/// The bit numbers are NOT the list positions. FaultIdTypeDef reserves bit 7
/// for FAULT_AUDIO, which has never been published under a name of its own,
/// so counting along this list would report `queue_full` and `low_heap` one
/// bit early. Each entry carries its real bit.
const List<HealthFlag> kHealthFlags = [
  HealthFlag('sd_fault',     'SD card',            0),
  HealthFlag('ntp_fault',    'Time sync',          1),
  HealthFlag('mqtt_fault',   'Cloud (MQTT)',       2),
  HealthFlag('wifi_fault',   'WiFi',               3),
  HealthFlag('rs485_fault',  'RS485 link',         4),
  HealthFlag('reboot_fault', 'Abnormal reboot',    5),
  HealthFlag('brownout',     'Brownout',           6),
  // bit 7 = FAULT_AUDIO, never given a JSON key
  HealthFlag('queue_full',   'Offline queue full', 8),
  HealthFlag('low_heap',     'Low memory',         9),
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

  /// Collapses the payload to one flat key/value map, accepting every shape
  /// the gateway has published:
  ///
  ///   nested   {"fault":{"bitmap":"0x0","sd_fault":0}, "system":{...}}
  ///   arrays   {"Fault":[{"bitmap":"0x0"},{"sd_fault":0}], ...}
  ///   flat     {"bitmap":"0x0", "sd_fault":0, ...}
  ///
  /// Nested is what current firmware sends. Flat is what every station still
  /// in the field sends until it is reflashed, and one phone build meets both
  /// on the same day, so reading only the new shape would blank every screen.
  /// The array form was a short-lived middle step; accepting it costs one
  /// branch and saves a support call if any station ever shipped with it.
  ///
  /// Key names are unique across the five groups, so flattening them into one
  /// map cannot collide.
  static Map<String, dynamic> _flatten(Map<String, dynamic> j) {
    final out = <String, dynamic>{};
    j.forEach((k, v) {
      if (v is Map) {
        v.forEach((k2, v2) => out['$k2'] = v2);
      } else if (v is List) {
        for (final e in v) {
          if (e is Map) {
            e.forEach((k2, v2) => out['$k2'] = v2);
          }
        }
      } else {
        out[k] = v;
      }
    });
    return out;
  }

  /// Returns null when the frame carries no station_id — a truncated payload
  /// must never overwrite a good record.
  static StationHealth? fromJson(Map<String, dynamic> raw, DateTime at) {
    final j = _flatten(raw);

    final sid = (j['station_id'] as String?)?.trim();
    if (sid == null || sid.isEmpty) return null;

    int? asInt(String k) => (j[k] as num?)?.toInt();

    /// A field the gateway sends as hex TEXT ("0x0107"), but that older
    /// firmware sent as a plain number (263). Both are accepted: a gateway in
    /// the field is not reflashed the same day the app updates, and reading
    /// one form only turns the whole master block into "not reported".
    int? asHexOrInt(String k) {
      final v = j[k];
      if (v is num) return v.toInt();
      if (v is! String) return null;
      final t = v.trim();
      if (t.isEmpty) return null;
      if (t.startsWith('0x') || t.startsWith('0X')) {
        return int.tryParse(t.substring(2), radix: 16);
      }
      return int.tryParse(t);
    }
    double? asDouble(String k) => (j[k] as num?)?.toDouble();
    bool asBool(String k) => ((j[k] as num?)?.toInt() ?? 0) != 0;

    // Current firmware publishes `bitmap` alone and drops the nine named
    // booleans, so they are decoded from the word. Where a station still
    // sends an explicit key, that key wins: it is what the gateway itself
    // concluded, and a disagreement should show the gateway's answer.
    final bmHex = (j['bitmap'] as String?) ?? '0x00000000';
    final bm = asHexOrInt('bitmap') ?? 0;

    final f = <String, bool>{};
    for (final hf in kHealthFlags) {
      f[hf.key] = j.containsKey(hf.key)
          ? asBool(hf.key)
          : (bm >> hf.bit) & 1 == 1;
    }

    return StationHealth(
      at: at,
      stationId: sid,
      ts: (j['TS'] as String?) ?? '',
      bitmapHex: bmHex,
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
      masterFw: asHexOrInt('master_fw'),
      masterReset: asInt('master_reset'),
      masterCrashed: asBool('master_crashed'),
      masterBrownout: asBool('master_brownout'),
      sensorFlags: asHexOrInt('sensor_flags'),
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
