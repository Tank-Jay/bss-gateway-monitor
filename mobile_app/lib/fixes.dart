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

/// Build a command payload BOTH firmware generations accept.
///
/// The gateway's JSON command key was renamed `"op"` -> `"cmd"` in
/// BLE_handler.cpp on 2026-08-31. Firmware from before that reads `doc["op"]`
/// and ignores `cmd`; firmware after it reads `doc["cmd"]` and ignores `op`.
/// Emitting both means one APK drives a fleet that is only partly reflashed,
/// for about twelve extra bytes on a characteristic with a 512-byte budget.
///
/// An unknown key is simply absent to the other generation — neither firmware
/// errors on the one it does not recognise, because both fetch by name.
String buildCommand(String verb, [Map<String, dynamic> extra = const {}]) =>
    json.encode({'cmd': verb, 'op': verb, ...extra});

/// The verb out of a gateway reply, whichever key it arrived under.
String? commandVerb(Map<String, dynamic> j) {
  final v = j['cmd'] ?? j['op'];
  return v is String ? v : null;
}

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

/// Word codes the firmware will clear via `{"cmd":"ack"}`.
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
/// The unlock pulse for one slot, independent of any fault.
///
/// The gateway accepts `pod_action` for any slot it has — the fault is not part
/// of the check (`BLE_handler.cpp`, the `pod_action` branch) — so an operator
/// can release a battery whose lock is simply stuck, with nothing reported.
/// [fixesFor] raises the same action when LOCK_FAIL or LOCK_STUCK is active.
///
/// Returns null when [slot] is outside what the station reports, so a button is
/// never offered for a slot the gateway would answer `"status":"error"` on.
/// Pass `totalPods: 0` before the first summary and the unlock is withheld
/// rather than guessed.
///
/// The key is deliberately identical to the fault-driven one: one pulse
/// resolves either, so pressing from the pod page must damp the button on the
/// Diagnostics page too.
FixAction? unlockActionFor(int slot, {required int totalPods}) {
  if (slot < 1 || slot > totalPods) return null;
  return FixAction(
    label: 'UNLOCK SLOT $slot',
    description: 'Re-pulse the lock on slot $slot. '
        'This physically releases the battery in that bay.',
    kind: FixKind.podUnlock,
    payload: buildCommand('pod_action', {'slot': slot, 'action': 'unlock'}),
    key: 'pod_action:unlock:$slot',
  );
}

List<FixAction> fixesFor(FaultCode f, {required int totalPods}) {
  final code = f.wordCode;

  if (!f.isStation) {
    if (!kUnlockableCodes.contains(code)) return const [];
    final a = unlockActionFor(f.slot, totalPods: totalPods);
    if (a == null) return const [];
    // Shorter label in a fault row, where the slot is already on the line.
    return [
      FixAction(
        label: 'UNLOCK',
        description: a.description,
        kind: a.kind,
        payload: a.payload,
        key: a.key,
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
        payload: buildCommand('fix', {'code': code}),
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
        payload: buildCommand('ack', {'code': code}),
        key: 'ack:$code',
      ),
      const FixAction(
        label: 'REBOOT',
        description: 'Restart the gateway. Drops the BLE link and all pod '
            'sessions.',
        kind: FixKind.reboot,
        payload: '{"cmd":"reboot","op":"reboot"}',
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

  /// Verbs whose replies are a fault-fix outcome.
  ///
  /// Deliberately NOT widened to set_param / save_reboot / factory_reset. Those
  /// replies share the {verb, status} shape, but a FixResult sets
  /// [BleService.lastFixResult], which drives fix-outcome UI and releases a Fix
  /// button's cooldown — a config write must not do either. Their outcome is
  /// already visible: the response listener logs every frame verbatim.
  static const Set<String> _fixOps = {'pod_action', 'fix', 'ack', 'reboot'};

  static FixResult? fromResponse(Map<String, dynamic> j) {
    final op = commandVerb(j);
    if (op == null || !_fixOps.contains(op)) return null;
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
