/// Fault-fix ops — doc/BLE_App_Integration.md §3.5.
///
/// An operator taps "Fix" next to a fault, the app writes a JSON op to the
/// Command characteristic (`e1ec0301`), and the fault bit clears in the next
/// Faults notify. No Flutter imports here, so the mapping and its guard rails
/// are unit-testable.
///
/// Everything below is keyed by the firmware's WORD code ([FaultCode.wordCode]
/// — `LOCK_FAIL`, `CLOUD_DOWN`), never by this app's `STA-05` display label.
/// The gateway compares `doc["code"]` against its own strings, so sending the
/// display label would earn `"status":"error"` on every press.
library;

import 'dart:convert';

import 'faults.dart';

/// What the op does, so the UI can style and confirm appropriately.
enum FixKind {
  /// Re-pulses one pod's lock GPIO. Physically moves hardware.
  podUnlock,

  /// A station-level remedy: reconnect MQTT / WiFi, re-probe NTP.
  stationFix,

  /// Clears a sticky latch without restarting anything.
  ack,

  /// Restarts the gateway. Drops the BLE link and every pod session with it.
  reboot,
}

/// One offered remedy for one fault.
class FixAction {
  /// Button text. Short — these sit inside a fault row.
  final String label;

  /// What it will do, for the confirm sheet and for accessibility.
  final String description;

  final FixKind kind;

  /// Exact bytes to write to the Command characteristic.
  final String payload;

  /// Identity for cooldown bookkeeping. Two faults offering the same op on the
  /// same slot share a key, so pressing one damps the other — which is what
  /// you want when LOCK_FAIL and LOCK_STUCK are both lit on one pod and both
  /// resolve to the same unlock pulse.
  final String key;

  const FixAction({
    required this.label,
    required this.description,
    required this.kind,
    required this.payload,
    required this.key,
  });

  /// True for ops that interrupt service and deserve a confirmation step.
  ///
  /// A reboot drops every pod session, and an unlock physically releases a
  /// battery — possibly with a customer standing at the cabinet. The station
  /// fixes and the latch acks are safe to fire on one tap.
  bool get needsConfirm => kind == FixKind.reboot || kind == FixKind.podUnlock;

  @override
  String toString() => '$label -> $payload';
}

/// Cooldown after a fix is sent.
///
/// §3.5: "do not re-enable the button until the fault clears or ~5 s pass".
/// The remedies are asynchronous — an NTP probe or a WiFi reassociation takes
/// seconds — and the fault bit only clears on the next 1 Hz Faults notify, so
/// without this an impatient operator queues a dozen reconnects.
const Duration kFixCooldown = Duration(seconds: 5);

/// Ops the firmware accepts for a station-level fault, keyed by word code.
/// Mirrors the `strcmp(code, ...)` ladder in the `"fix"` branch of
/// BLE_handler.cpp — anything absent here returns `"status":"error"`.
const Map<String, String> kStationFixLabels = {
  'CLOUD_DOWN': 'RECONNECT',
  'WIFI_DOWN': 'RECONNECT',
  'TIME_UNSYNCED': 'RE-SYNC',
};

const Map<String, String> kStationFixDescriptions = {
  'CLOUD_DOWN': 'Force an MQTT reconnect to the broker.',
  'WIFI_DOWN': 'Drop WiFi and reassociate using the stored credentials.',
  'TIME_UNSYNCED': 'Re-arm and re-probe the NTP time sync.',
};

/// Word codes the firmware will clear via `{"op":"ack"}`.
/// Mirrors the `Fault_Clear(...)` ladder in the `"ack"` branch.
const Set<String> kAckableCodes = {
  'BROWNOUT',
  'REBOOT_ABNORMAL',
  'LOW_HEAP',
};

/// Pod word codes the unlock pulse is offered for.
const Set<String> kUnlockableCodes = {
  'LOCK_FAIL',
  'LOCK_STUCK',
};

/// Remedies available for [f], most-recommended first. Empty when the firmware
/// offers nothing for that fault — RS485_DEAD, CELL_OV and POD_OFFLINE among
/// them, which need a human at the cabinet rather than a command.
///
/// [totalPods] is the station's reported pod count. It gates the unlock op
/// because the gateway validates `slot` against `SEND_QUERY_SLAVE_SIZE`, not
/// against the BLE array cap — offering a button for a slot beyond that would
/// return `"status":"error"` on every press. Pass 0 when the count is not
/// known yet and the unlock is withheld rather than guessed.
List<FixAction> fixesFor(FaultCode f, {required int totalPods}) {
  final code = f.wordCode;

  if (!f.isStation) {
    if (!kUnlockableCodes.contains(code)) return const [];
    if (f.slot < 1 || f.slot > totalPods) return const [];
    return [
      FixAction(
        label: 'UNLOCK',
        description: 'Re-pulse the lock on slot ${f.slot}.',
        kind: FixKind.podUnlock,
        payload: json.encode(
            {'op': 'pod_action', 'slot': f.slot, 'action': 'unlock'}),
        key: 'pod_action:unlock:${f.slot}',
      ),
    ];
  }

  final stationLabel = kStationFixLabels[code];
  if (stationLabel != null) {
    return [
      FixAction(
        label: stationLabel,
        description: kStationFixDescriptions[code] ?? '',
        kind: FixKind.stationFix,
        payload: json.encode({'op': 'fix', 'code': code}),
        key: 'fix:$code',
      ),
    ];
  }

  if (kAckableCodes.contains(code)) {
    // Ack first: it is the non-destructive option, and these three faults are
    // latches describing something that already happened, so clearing the
    // latch is usually the whole job. Reboot stays available for LOW_HEAP,
    // where the condition is live rather than historical.
    return [
      FixAction(
        label: 'CLEAR',
        description: 'Clear the $code latch without restarting.',
        kind: FixKind.ack,
        payload: json.encode({'op': 'ack', 'code': code}),
        key: 'ack:$code',
      ),
      const FixAction(
        label: 'REBOOT',
        description: 'Restart the gateway. Drops the BLE link and all pod '
            'sessions.',
        kind: FixKind.reboot,
        payload: '{"op":"reboot"}',
        key: 'reboot',
      ),
    ];
  }

  return const [];
}

/// Tracks which fixes are cooling down.
///
/// Keyed by [FixAction.key] rather than by fault, so the same op pressed from
/// two different rows is damped once — see the note on that field.
class FixCooldowns {
  final Map<String, DateTime> _sentAt = {};

  /// Record that [key] was just sent.
  void mark(String key, DateTime at) => _sentAt[key] = at;

  bool isCooling(String key, DateTime now) {
    final t = _sentAt[key];
    return t != null && now.difference(t) < kFixCooldown;
  }

  /// Seconds left, for a countdown on the button. 0 when ready.
  ///
  /// Rounded up, so a button showing "1s" is still genuinely blocked; an
  /// `inSeconds + 1` would instead read "6s" the instant a 5 s cooldown starts.
  int remaining(String key, DateTime now) {
    final t = _sentAt[key];
    if (t == null) return 0;
    final leftMs = (kFixCooldown - now.difference(t)).inMilliseconds;
    return leftMs <= 0 ? 0 : (leftMs / 1000).ceil();
  }

  /// Drop a cooldown early — the fault cleared, so the op worked and there is
  /// nothing left to protect against. §3.5 allows either exit condition.
  void release(String key) => _sentAt.remove(key);

  void clear() => _sentAt.clear();
}

/// Parse the gateway's reply to a fix op (§3.5 reply column, arriving on
/// Response per §3.6). Null when the payload is some other Response shape —
/// the version push or a params dump.
class FixResult {
  /// `pod_action`, `fix`, `ack` or `reboot`.
  final String op;

  /// Word code echoed back, empty for ops that carry none.
  final String code;

  /// 0 for an op with no slot.
  final int slot;

  final bool ok;

  const FixResult({
    required this.op,
    required this.code,
    required this.slot,
    required this.ok,
  });

  /// The [FixAction.key] this reply corresponds to, so a cooldown can be
  /// released the moment a failure comes back — a rejected op did nothing, so
  /// making the operator wait out the full 5 s only hides the error.
  String get key {
    switch (op) {
      case 'pod_action':
        return 'pod_action:unlock:$slot';
      case 'fix':
        return 'fix:$code';
      case 'ack':
        return 'ack:$code';
      case 'reboot':
        return 'reboot';
    }
    return op;
  }

  String get message {
    if (ok) return 'Accepted';
    if (op == 'pod_action') return 'Rejected — slot $slot out of range';
    return 'Rejected by gateway';
  }

  static const Set<String> _fixOps = {'pod_action', 'fix', 'ack', 'reboot'};

  static FixResult? fromResponse(Map<String, dynamic> j) {
    final op = j['op'];
    if (op is! String || !_fixOps.contains(op)) return null;
    final status = j['status'];
    if (status is! String) return null;
    return FixResult(
      op: op,
      code: (j['code'] as String?) ?? '',
      slot: (j['slot'] as num?)?.toInt() ?? 0,
      ok: status == 'ok',
    );
  }
}
