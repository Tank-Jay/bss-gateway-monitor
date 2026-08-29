import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/log_entry.dart';
import 'ble_uuids.dart';

enum LinkState { disconnected, connecting, connected }

/// GATT link to exactly one charger — the connected tier of the protocol.
///
/// The fleet screen never uses this; it only comes alive when the user taps
/// into a charger and wants per-cell BMS detail or control.
class ChargerBleService extends ChangeNotifier {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _cInfo, _cSummary, _cSelect, _cDetail, _cCommand, _cResponse;

  LinkState state = LinkState.disconnected;
  String? deviceName;
  int rxCount = 0;
  int selectedBay = 1;

  Map<String, dynamic>? info;
  Map<String, dynamic>? summary;
  Map<String, dynamic>? detail;
  Map<String, dynamic>? params;
  String lastResponse = '';

  final List<LogEntry> logs = [];

  /// Rolling per-bay history for the detail charts. ~3 minutes at 1 Hz.
  static const int _historyMax = 180;
  final Map<int, List<BaySample>> _history = {1: [], 2: []};

  List<BaySample> historyFor(int bay) => _history[bay] ?? const [];

  StreamSubscription<List<int>>? _summarySub, _detailSub, _responseSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  bool get isConnected => state == LinkState.connected;

  /// disconnect() is async but the screen that owns this service disposes it
  /// synchronously on pop. Without this guard the in-flight teardown notifies a
  /// disposed ChangeNotifier and throws on the way out of every charger screen.
  bool _disposed = false;

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  void _log(LogType t, String msg) {
    logs.add(LogEntry(DateTime.now(), t, msg));
    if (logs.length > 300) logs.removeAt(0);
    _notify();
  }

  void _setState(LinkState s) {
    state = s;
    _notify();
  }

  // ── Connect / disconnect ──

  Future<bool> connect(BluetoothDevice target) async {
    try {
      _device = target;
      deviceName = target.platformName.isNotEmpty
          ? target.platformName
          : target.remoteId.str;
      _setState(LinkState.connecting);
      _log(LogType.info, 'Connecting to $deviceName');

      await target.connect(timeout: const Duration(seconds: 15), autoConnect: false);
      _log(LogType.info, 'GATT connected');

      _connSub = target.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _log(LogType.info, 'Charger disconnected');
          _teardown();
          _setState(LinkState.disconnected);
        }
      });

      // A full bay-detail payload with 32 cells runs past the 23-byte default.
      try {
        final mtu = await target.requestMtu(ChargerUuids.mtu);
        _log(LogType.info, 'MTU negotiated: $mtu');
      } catch (e) {
        _log(LogType.err, 'MTU request failed: $e');
      }

      final services = await target.discoverServices();
      for (final s in services) {
        if (s.uuid == ChargerUuids.svcInfo) {
          for (final c in s.characteristics) {
            if (c.uuid == ChargerUuids.charInfo) _cInfo = c;
          }
        } else if (s.uuid == ChargerUuids.svcBattery) {
          for (final c in s.characteristics) {
            if (c.uuid == ChargerUuids.charBaySummary) _cSummary = c;
            if (c.uuid == ChargerUuids.charBaySelect) _cSelect = c;
            if (c.uuid == ChargerUuids.charBayDetail) _cDetail = c;
          }
        } else if (s.uuid == ChargerUuids.svcControl) {
          for (final c in s.characteristics) {
            if (c.uuid == ChargerUuids.charCommand) _cCommand = c;
            if (c.uuid == ChargerUuids.charResponse) _cResponse = c;
          }
        }
      }

      final missing = <String>[
        if (_cInfo == null) 'Info',
        if (_cSummary == null) 'Bay Summary',
        if (_cSelect == null) 'Bay Select',
        if (_cDetail == null) 'Bay Detail',
        if (_cCommand == null) 'Command',
        if (_cResponse == null) 'Response',
      ];
      if (missing.isNotEmpty) {
        _log(LogType.err, 'Not a BSS charger — missing: ${missing.join(", ")}');
        await target.disconnect();
        _teardown();
        _setState(LinkState.disconnected);
        return false;
      }

      await _cSummary!.setNotifyValue(true);
      _summarySub = _cSummary!.lastValueStream.listen(_onSummary);

      await _cDetail!.setNotifyValue(true);
      _detailSub = _cDetail!.lastValueStream.listen(_onDetail);

      await _cResponse!.setNotifyValue(true);
      _responseSub = _cResponse!.lastValueStream.listen(_onResponse);

      _setState(LinkState.connected);
      _log(LogType.info, 'Subscribed — streaming at 1 Hz');

      unawaited(readInfo());
      unawaited(selectBay(selectedBay));
      return true;
    } catch (e) {
      _log(LogType.err, 'Connect failed: $e');
      _teardown();
      _setState(LinkState.disconnected);
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _device?.disconnect();
    } catch (_) {}
    _teardown();
    _setState(LinkState.disconnected);
  }

  void _teardown() {
    _summarySub?.cancel();
    _detailSub?.cancel();
    _responseSub?.cancel();
    _connSub?.cancel();
    _summarySub = _detailSub = _responseSub = null;
    _connSub = null;
    _device = null;
    _cInfo = _cSummary = _cSelect = _cDetail = _cCommand = _cResponse = null;
    info = summary = detail = params = null;
    _history[1]!.clear();
    _history[2]!.clear();
  }

  // ── Notification handlers ──

  void _onSummary(List<int> raw) {
    if (raw.isEmpty) return;
    try {
      final txt = utf8.decode(raw);
      summary = json.decode(txt) as Map<String, dynamic>;
      rxCount++;
      _recordSamples(summary);
      _log(LogType.rx, 'SUMMARY ${txt.length}B');
    } catch (e) {
      _log(LogType.err, 'Summary parse: $e');
    }
  }

  void _onDetail(List<int> raw) {
    if (raw.isEmpty) return;
    try {
      final txt = utf8.decode(raw);
      final parsed = json.decode(txt) as Map<String, dynamic>;
      // The firmware streams whichever bay is selected; a late packet for the
      // previous bay would otherwise flicker the wrong data onto the screen.
      if (parsed['bay'] is num && (parsed['bay'] as num).toInt() != selectedBay) {
        return;
      }
      detail = parsed;
      rxCount++;
      _log(LogType.rx, 'DETAIL bay $selectedBay ${txt.length}B');
    } catch (e) {
      _log(LogType.err, 'Detail parse: $e');
    }
  }

  void _onResponse(List<int> raw) {
    if (raw.isEmpty) return;
    try {
      final txt = utf8.decode(raw);
      lastResponse = txt;
      _log(LogType.rx, 'RESP $txt');
      final decoded = json.decode(txt);
      if (decoded is Map<String, dynamic> && decoded['op'] == 'params') {
        params = decoded;
      }
      _notify();
    } catch (e) {
      _log(LogType.err, 'Response parse: $e');
    }
  }

  void _recordSamples(Map<String, dynamic>? s) {
    if (s == null) return;
    final bays = s['bays'];
    if (bays is! List) return;
    final now = DateTime.now();
    for (final raw in bays) {
      if (raw is! Map) continue;
      final b = raw.cast<String, dynamic>();
      final n = (b['bay'] as num?)?.toInt();
      if (n == null || !_history.containsKey(n)) continue;
      if (b['present'] != true) continue;
      final buf = _history[n]!;
      buf.add(BaySample(
        t: now,
        soc: (b['soc'] as num?)?.toDouble() ?? 0,
        volts: (b['v'] as num?)?.toDouble() ?? 0,
        amps: (b['i'] as num?)?.toDouble() ?? 0,
        tempC: (b['temp'] as num?)?.toDouble() ?? 0,
      ));
      if (buf.length > _historyMax) buf.removeAt(0);
    }
  }

  // ── Reads and commands ──

  Future<void> readInfo() async {
    if (_cInfo == null) return;
    try {
      _log(LogType.tx, 'READ Charger Info');
      final txt = utf8.decode(await _cInfo!.read());
      info = json.decode(txt) as Map<String, dynamic>;
      rxCount++;
      _notify();
    } catch (e) {
      _log(LogType.err, 'Info read: $e');
    }
  }

  Future<void> selectBay(int bay) async {
    if (bay < 1 || bay > 2) return;
    selectedBay = bay;
    // Drop the previous bay detail so the UI shows a loading state rather than
    // the other bay numbers while the first notification is in flight.
    detail = null;
    _notify();
    if (_cSelect == null) return;
    try {
      await _cSelect!.write(utf8.encode('$bay'), withoutResponse: false);
      _log(LogType.tx, 'Bay select: $bay');
    } catch (e) {
      _log(LogType.err, 'Bay select: $e');
    }
  }

  Future<void> _send(Map<String, dynamic> payload) async {
    if (_cCommand == null) {
      _log(LogType.err, 'Not connected');
      return;
    }
    try {
      final txt = json.encode(payload);
      await _cCommand!.write(utf8.encode(txt), withoutResponse: false);
      _log(LogType.tx, 'CMD $txt');
    } catch (e) {
      _log(LogType.err, 'CMD failed: $e');
    }
  }

  Future<void> startBay(int bay) => _send({'op': 'start', 'bay': bay});
  Future<void> stopBay(int bay) => _send({'op': 'stop', 'bay': bay});
  Future<void> unlockBay(int bay) => _send({'op': 'unlock', 'bay': bay});
  Future<void> clearFaults() => _send({'op': 'clear_fault'});
  Future<void> requestParams() => _send({'op': 'get_params'});
  Future<void> setParam(String key, String value) =>
      _send({'op': 'set_param', 'key': key, 'value': value});
  Future<void> saveAndReboot() => _send({'op': 'save_reboot'});
  Future<void> reboot() => _send({'op': 'reboot'});
  Future<void> factoryReset() => _send({'op': 'factory_reset'});

  void clearLogs() {
    logs.clear();
    rxCount = 0;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _teardown();
    super.dispose();
  }
}
