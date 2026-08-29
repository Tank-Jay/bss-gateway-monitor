import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/charger_adv.dart';
import 'ble_uuids.dart';

/// How long a charger may go unheard before the fleet screen greys it out.
const Duration kStaleAfter = Duration(seconds: 12);

/// How long before a silent charger is dropped from the list entirely.
const Duration kDropAfter = Duration(minutes: 3);

/// Sort orders offered on the fleet screen.
enum FleetSort { chargerId, socAsc, socDesc, faultsFirst, signal }

extension FleetSortLabel on FleetSort {
  String get label => switch (this) {
        FleetSort.chargerId => 'Charger ID',
        FleetSort.socAsc => 'SOC low to high',
        FleetSort.socDesc => 'SOC high to low',
        FleetSort.faultsFirst => 'Faults first',
        FleetSort.signal => 'Signal strength',
      };
}

/// Owns the long-running BLE scan and the decoded fleet.
///
/// This is the tier that makes the headline feature work: every charger in
/// range is decoded straight out of its advertisement, so 50 chargers and
/// 100 batteries stay live without a single GATT connection.
class FleetScanner extends ChangeNotifier {
  final Map<String, ChargerSnapshot> _chargers = {};
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  Timer? _sweepTimer;

  bool _scanning = false;
  bool _demoMode = false;
  String? _error;

  FleetSort sort = FleetSort.chargerId;
  bool showOnlyFaults = false;
  String search = '';

  bool get scanning => _scanning;
  bool get demoMode => _demoMode;
  String? get error => _error;

  // ── Fleet roll-ups shown in the header ──

  List<ChargerSnapshot> get all => _chargers.values.toList();

  int get chargerCount => _chargers.length;

  int get batteryCount =>
      _chargers.values.fold(0, (n, c) => n + c.batteriesPresent);

  int get chargingCount => _chargers.values
      .expand((c) => c.bays)
      .where((b) => b.state == BayState.charging)
      .length;

  int get fullCount => _chargers.values
      .expand((c) => c.bays)
      .where((b) => b.state == BayState.full)
      .length;

  int get faultCount => _chargers.values.where((c) => c.hasFault).length;

  double? get fleetAverageSoc {
    final vals = _chargers.values
        .expand((c) => c.bays)
        .where((b) => b.present && b.soc != null)
        .map((b) => b.soc!)
        .toList();
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  /// The list the fleet screen renders — filtered and sorted.
  List<ChargerSnapshot> get visible {
    var list = _chargers.values.toList();

    if (showOnlyFaults) {
      list = list.where((c) => c.hasFault).toList();
    }

    if (search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      list = list.where((c) {
        if (c.name.toLowerCase().contains(q)) return true;
        if (c.chargerId.toString().contains(q)) return true;
        return c.deviceId.toLowerCase().contains(q);
      }).toList();
    }

    int bySoc(ChargerSnapshot a, ChargerSnapshot b) {
      // Chargers with no battery sort last either way — an empty slot is not
      // a "0 %" battery and should not lead a low-SOC worklist.
      final sa = a.averageSoc, sb = b.averageSoc;
      if (sa == null && sb == null) return a.chargerId.compareTo(b.chargerId);
      if (sa == null) return 1;
      if (sb == null) return -1;
      return sa.compareTo(sb);
    }

    switch (sort) {
      case FleetSort.chargerId:
        list.sort((a, b) => a.chargerId.compareTo(b.chargerId));
      case FleetSort.socAsc:
        list.sort(bySoc);
      case FleetSort.socDesc:
        list.sort((a, b) => bySoc(b, a));
      case FleetSort.faultsFirst:
        list.sort((a, b) {
          if (a.hasFault != b.hasFault) return a.hasFault ? -1 : 1;
          return a.chargerId.compareTo(b.chargerId);
        });
      case FleetSort.signal:
        list.sort((a, b) => b.rssi.compareTo(a.rssi));
    }
    return list;
  }

  ChargerSnapshot? byDeviceId(String id) => _chargers[id];

  // ── Scan lifecycle ──

  Future<bool> _preflight() async {
    if (!await FlutterBluePlus.isSupported) {
      _error = 'This device has no Bluetooth LE radio.';
      return false;
    }

    final scanOk = await Permission.bluetoothScan.request().isGranted;
    final connectOk = await Permission.bluetoothConnect.request().isGranted;
    if (!scanOk || !connectOk) {
      _error = 'Bluetooth permission denied — grant it in system Settings.';
      return false;
    }
    // Android 11 and below will not return scan results without location.
    await Permission.locationWhenInUse.request();

    final adapter = await FlutterBluePlus.adapterState.first;
    if (adapter != BluetoothAdapterState.on) {
      _error = 'Bluetooth is off — turn it on to see the fleet.';
      return false;
    }

    _error = null;
    return true;
  }

  Future<void> start() async {
    if (_scanning || _demoMode) return;
    if (!await _preflight()) {
      notifyListeners();
      return;
    }

    _scanning = true;
    notifyListeners();

    _adapterSub ??= FlutterBluePlus.adapterState.listen((s) {
      if (s != BluetoothAdapterState.on && _scanning) {
        _error = 'Bluetooth turned off — scanning stopped.';
        stop();
      }
    });

    _scanSub = FlutterBluePlus.scanResults.listen(_ingest, onError: (e) {
      _error = 'Scan error: $e';
      notifyListeners();
    });

    try {
      // No timeout: the fleet view is meant to sit open on a depot wall.
      // continuousUpdates is essential — without it flutter_blue_plus reports
      // each device once and the telemetry would freeze at first sighting.
      await FlutterBluePlus.startScan(
        continuousUpdates: true,
        androidScanMode: AndroidScanMode.lowLatency,
      );
    } catch (e) {
      _error = 'Could not start scan: $e';
      _scanning = false;
      notifyListeners();
      return;
    }

    // Re-evaluate staleness on a timer; advertisements arriving is what keeps
    // a charger fresh, but nothing arrives to tell us one went quiet.
    _sweepTimer = Timer.periodic(const Duration(seconds: 2), (_) => _sweep());
  }

  Future<void> stop() async {
    _sweepTimer?.cancel();
    _sweepTimer = null;
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    _scanning = false;
    notifyListeners();
  }

  Future<void> restart() async {
    await stop();
    _chargers.clear();
    notifyListeners();
    await start();
  }

  void _ingest(List<ScanResult> results) {
    final now = DateTime.now();
    var changed = false;

    for (final r in results) {
      final payload = r.advertisementData.manufacturerData[ChargerUuids.companyId];
      if (payload == null) continue;

      final snap = ChargerAdvCodec.decode(
        manufacturerPayload: payload,
        deviceId: r.device.remoteId.str,
        name: r.advertisementData.advName,
        rssi: r.rssi,
        seenAt: now,
      );
      if (snap == null) continue;

      // Another product could pick the same test company ID; the name prefix
      // is the second gate that keeps foreign devices out of the fleet.
      if (!snap.name.startsWith(ChargerUuids.namePrefix)) continue;

      _chargers[snap.deviceId] = snap;
      changed = true;
    }

    if (changed) notifyListeners();
  }

  void _sweep() {
    final now = DateTime.now();
    final gone = _chargers.entries
        .where((e) => now.difference(e.value.seenAt) > kDropAfter)
        .map((e) => e.key)
        .toList();
    for (final k in gone) {
      _chargers.remove(k);
    }
    // Always notify: tiles re-render their stale badge from seenAt.
    notifyListeners();
  }

  void setSort(FleetSort s) {
    sort = s;
    notifyListeners();
  }

  void setFaultFilter(bool v) {
    showOnlyFaults = v;
    notifyListeners();
  }

  void setSearch(String v) {
    search = v;
    notifyListeners();
  }

  // ── Demo mode ──

  /// Populates a synthetic 50-charger fleet so the UI can be exercised, shown
  /// and reviewed without hardware on the bench. Purely local — it never
  /// touches the radio, and the banner on the fleet screen makes it obvious
  /// that the numbers are not real.
  void startDemo({int chargers = 50}) {
    stop();
    _demoMode = true;
    _chargers.clear();
    final rnd = Random(42); // fixed seed so demo screenshots are reproducible

    void tick() {
      final now = DateTime.now();
      for (var i = 1; i <= chargers; i++) {
        final id = 'DEMO:${i.toString().padLeft(2, '0')}';
        final prev = _chargers[id];

        BaySnapshot mkBay(int bay, int seed) {
          final present = (i + bay) % 7 != 0; // a few empty slots
          if (!present) return BaySnapshot.empty(bay);

          final prevSoc = prev?.bays[bay - 1].soc ?? (10 + rnd.nextInt(80));
          final charging = prevSoc < 100;
          final soc = charging ? (prevSoc + (rnd.nextInt(2))).clamp(0, 100) : 100;
          return BaySnapshot(
            bay: bay,
            present: true,
            relayClosed: charging,
            balancing: soc > 95 && charging,
            state: soc >= 100 ? BayState.full : BayState.charging,
            soc: soc,
            volts: 380 + soc * 1.4,
            tempC: 26 + (seed % 12),
          );
        }

        final bays = [mkBay(1, i), mkBay(2, i * 3)];
        final faulted = i % 13 == 0;
        _chargers[id] = ChargerSnapshot(
          deviceId: id,
          name: 'BSSC_${i.toString().padLeft(4, '0')}',
          chargerId: i,
          protoVer: 1,
          state: faulted
              ? ChargerState.fault
              : (bays.any((b) => b.state == BayState.charging)
                  ? ChargerState.charging
                  : ChargerState.complete),
          faultBitmap: faulted ? (1 << (i % 8)) : 0,
          seq: (prev?.seq ?? 0) + 1,
          rssi: -45 - (i % 40),
          seenAt: now,
          bays: bays,
        );
      }
      notifyListeners();
    }

    tick();
    _sweepTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void stopDemo() {
    _sweepTimer?.cancel();
    _sweepTimer = null;
    _demoMode = false;
    _chargers.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _sweepTimer?.cancel();
    _scanSub?.cancel();
    _adapterSub?.cancel();
    try {
      FlutterBluePlus.stopScan();
    } catch (_) {}
    super.dispose();
  }
}
