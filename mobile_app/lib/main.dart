// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ══════════════════════════════════════════════════════════════
//  BLE UUIDs — must match BLE_handler.h
// ══════════════════════════════════════════════════════════════
class BleUuids {
  static final svcInfo     = Guid('e1ec0001-1234-4321-abcd-0123456789ab');
  static final svcPod      = Guid('e1ec0002-1234-4321-abcd-0123456789ab');
  static final svcControl  = Guid('e1ec0003-1234-4321-abcd-0123456789ab');
  static final charStation = Guid('e1ec0101-1234-4321-abcd-0123456789ab');
  static final charSummary = Guid('e1ec0201-1234-4321-abcd-0123456789ab');
  static final charSelect  = Guid('e1ec0202-1234-4321-abcd-0123456789ab');
  static final charDetail  = Guid('e1ec0203-1234-4321-abcd-0123456789ab');
  static final charCommand = Guid('e1ec0301-1234-4321-abcd-0123456789ab');
  static final charResponse= Guid('e1ec0302-1234-4321-abcd-0123456789ab');
}

// ══════════════════════════════════════════════════════════════
//  Palette (matches web app)
// ══════════════════════════════════════════════════════════════
class Palette {
  static const bg        = Color(0xFF0F1923);
  static const card      = Color(0xFF1A2733);
  static const border    = Color(0xFF2A3A4A);
  static const accent    = Color(0xFF00D4AA);
  static const text      = Color(0xFFE0E8F0);
  static const textDim   = Color(0xFF8899AA);
  static const success   = Color(0xFF00CC66);
  static const warn      = Color(0xFFFFAA00);
  static const danger    = Color(0xFFFF4444);
  static const volt      = Color(0xFF4FC3F7);
  static const curr      = Color(0xFFFFB74D);
  static const soc       = Color(0xFF81C784);
  static const soh       = Color(0xFFCE93D8);
  static const temp      = Color(0xFFEF5350);
  static const cycle     = Color(0xFF90A4AE);
  static const cap       = Color(0xFF4DD0E1);
  static const dataBg    = Color(0xFF0F1923);
  static const logBg     = Color(0xFF0A0F14);
}

// ══════════════════════════════════════════════════════════════
//  Main
// ══════════════════════════════════════════════════════════════
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFF1A2733),
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const BssApp());
}

class BssApp extends StatelessWidget {
  const BssApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BSS Gateway Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Palette.bg,
        fontFamily: 'Roboto',
        colorScheme: const ColorScheme.dark(
          primary: Palette.accent,
          surface: Palette.card,
          error: Palette.danger,
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  Login Screen
// ══════════════════════════════════════════════════════════════
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String _err = '';

  static const _creds = [
    {'user': 'Jaytank', 'pass': 'Jay@2526'},
    {'user': 'admin',   'pass': 'admin'},
  ];

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('bss_auth') == true) {
      _goHome();
    }
  }

  void _doLogin() async {
    final u = _userCtrl.text.trim();
    final p = _passCtrl.text;
    final ok = _creds.any((c) => c['user'] == u && c['pass'] == p);
    if (ok) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('bss_auth', true);
      _goHome();
    } else {
      setState(() => _err = 'Invalid username or password');
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _err = '');
      });
    }
  }

  void _goHome() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Palette.card,
              border: Border.all(color: Palette.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('BSS',
                  style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: Palette.accent, letterSpacing: 4)),
                const Text('GATEWAY MONITOR',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Palette.text, letterSpacing: 1)),
                const SizedBox(height: 4),
                const Text('Sign in to continue',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Palette.textDim)),
                const SizedBox(height: 24),
                _inputField('Username', _userCtrl, false),
                const SizedBox(height: 10),
                _inputField('Password', _passCtrl, true),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _doLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Palette.accent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('LOGIN',
                      style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 15)),
                  ),
                ),
                if (_err.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_err, style: const TextStyle(color: Palette.danger, fontSize: 13)),
                  ),
                const SizedBox(height: 18),
                const Text('v1.0 · BSS IoT Gateway ESP32-S3',
                  style: TextStyle(fontSize: 11, color: Palette.textDim, letterSpacing: 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _inputField(String label, TextEditingController ctrl, bool obscure) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: const TextStyle(color: Palette.text, fontSize: 15),
      decoration: InputDecoration(
        hintText: label,
        hintStyle: const TextStyle(color: Palette.textDim),
        filled: true,
        fillColor: Palette.dataBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Palette.accent),
        ),
      ),
      onSubmitted: (_) => _doLogin(),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  BLE Service (state holder)
// ══════════════════════════════════════════════════════════════
class BleService extends ChangeNotifier {
  BluetoothDevice? device;
  BluetoothCharacteristic? charStation, charSummary, charSelect, charDetail, charCommand, charResponse;

  ConnectionState state = ConnectionState.disconnected;
  String? deviceName;
  int readCount = 0;
  int selectedPod = 1;

  Map<String, dynamic>? stationInfo;
  Map<String, dynamic>? podSummary;
  Map<String, dynamic>? podDetail;
  String lastCmdResponse = 'Waiting for command...';

  final List<LogEntry> logs = [];
  StreamSubscription<List<int>>? _summarySub, _responseSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  void log(LogType t, String msg) {
    logs.add(LogEntry(DateTime.now(), t, msg));
    if (logs.length > 200) logs.removeAt(0);
    notifyListeners();
  }

  void _setState(ConnectionState s) { state = s; notifyListeners(); }

  Future<bool> requestPermissions() async {
    if (await Permission.bluetoothScan.request().isGranted &&
        await Permission.bluetoothConnect.request().isGranted) {
      await Permission.locationWhenInUse.request();
      return true;
    }
    return false;
  }

  Future<void> scanAndConnect() async {
    _setState(ConnectionState.scanning);
    log(LogType.info, 'Scanning for BSSX_ devices...');

    try {
      if (!await requestPermissions()) {
        log(LogType.err, 'Bluetooth permissions denied');
        _setState(ConnectionState.disconnected);
        return;
      }

      // Start scan
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
        withKeywords: ['BSSX_', 'BSS_'],
      );

      BluetoothDevice? found;
      final sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final name = r.device.platformName;
          if (name.startsWith('BSSX_') || name.startsWith('BSS_')) {
            found = r.device;
          }
        }
      });

      await Future.delayed(const Duration(seconds: 8));
      await FlutterBluePlus.stopScan();
      await sub.cancel();

      if (found == null) {
        log(LogType.err, 'No BSS device found');
        _setState(ConnectionState.disconnected);
        return;
      }

      device = found;
      deviceName = found!.platformName;
      log(LogType.info, 'Found: $deviceName');

      _setState(ConnectionState.connecting);
      log(LogType.info, 'Connecting to GATT...');
      await found!.connect(timeout: const Duration(seconds: 15), autoConnect: false);
      log(LogType.info, 'GATT connected');

      _connSub = device!.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          log(LogType.info, 'Device disconnected');
          _setState(ConnectionState.disconnected);
          _cleanup();
        }
      });

      // Discover services
      log(LogType.info, 'Discovering services...');
      final services = await device!.discoverServices();

      for (final s in services) {
        if (s.uuid == BleUuids.svcInfo) {
          for (final c in s.characteristics) {
            if (c.uuid == BleUuids.charStation) charStation = c;
          }
        } else if (s.uuid == BleUuids.svcPod) {
          for (final c in s.characteristics) {
            if (c.uuid == BleUuids.charSummary) charSummary = c;
            else if (c.uuid == BleUuids.charSelect) charSelect = c;
            else if (c.uuid == BleUuids.charDetail) charDetail = c;
          }
        } else if (s.uuid == BleUuids.svcControl) {
          for (final c in s.characteristics) {
            if (c.uuid == BleUuids.charCommand) charCommand = c;
            else if (c.uuid == BleUuids.charResponse) charResponse = c;
          }
        }
      }

      if (charStation == null || charSummary == null || charSelect == null ||
          charDetail == null || charCommand == null || charResponse == null) {
        log(LogType.err, 'Missing one or more characteristics');
        await device!.disconnect();
        return;
      }

      log(LogType.info, 'All 6 characteristics found');

      // Subscribe to Pod Summary notify (1-second auto-update)
      await charSummary!.setNotifyValue(true);
      _summarySub = charSummary!.lastValueStream.listen((val) {
        if (val.isEmpty) return;
        try {
          final txt = utf8.decode(val);
          podSummary = json.decode(txt) as Map<String, dynamic>;
          readCount++;
          log(LogType.rx, 'SUMMARY (${txt.length}B)');
          notifyListeners();
        } catch (e) { log(LogType.err, 'Summary parse: $e'); }
      });

      // Subscribe to Response notify
      await charResponse!.setNotifyValue(true);
      _responseSub = charResponse!.lastValueStream.listen((val) {
        if (val.isEmpty) return;
        try {
          final txt = utf8.decode(val);
          log(LogType.rx, 'RESPONSE: $txt');
          lastCmdResponse = txt;
          notifyListeners();
        } catch (e) { log(LogType.err, 'Response parse: $e'); }
      });

      _setState(ConnectionState.connected);
      log(LogType.info, 'Connected successfully!');

      // Auto-read station info
      Future.delayed(const Duration(milliseconds: 500), () => readStationInfo());

    } catch (e) {
      log(LogType.err, 'Connect failed: $e');
      _setState(ConnectionState.disconnected);
    }
  }

  Future<void> disconnect() async {
    try { await device?.disconnect(); } catch (_) {}
    _cleanup();
  }

  void _cleanup() {
    _summarySub?.cancel();
    _responseSub?.cancel();
    _connSub?.cancel();
    device = null;
    charStation = charSummary = charSelect = charDetail = charCommand = charResponse = null;
    deviceName = null;
  }

  Future<void> readStationInfo() async {
    if (charStation == null) return;
    try {
      log(LogType.tx, 'READ Station Info');
      final val = await charStation!.read();
      final txt = utf8.decode(val);
      stationInfo = json.decode(txt) as Map<String, dynamic>;
      readCount++;
      log(LogType.rx, 'STATION (${txt.length}B)');
      notifyListeners();
    } catch (e) { log(LogType.err, 'Station read: $e'); }
  }

  Future<void> selectPod(int n) async {
    selectedPod = n;
    notifyListeners();
    if (charSelect == null) return;
    try {
      await charSelect!.write(utf8.encode('$n'), withoutResponse: false);
      log(LogType.tx, 'Pod Select: $n');
    } catch (e) { log(LogType.err, 'Pod Select: $e'); }
  }

  Future<void> readPodDetail() async {
    if (charSelect != null) {
      try { await charSelect!.write(utf8.encode('$selectedPod'), withoutResponse: false); } catch (_) {}
    }
    if (charDetail == null) return;
    try {
      log(LogType.tx, 'READ Pod $selectedPod Detail');
      final val = await charDetail!.read();
      final txt = utf8.decode(val);
      podDetail = json.decode(txt) as Map<String, dynamic>;
      readCount++;
      log(LogType.rx, 'DETAIL (${txt.length}B)');
      notifyListeners();
    } catch (e) { log(LogType.err, 'Pod Detail: $e'); }
  }

  Future<void> sendCommand(String cmd) async {
    if (charCommand == null) return;
    try {
      await charCommand!.write(utf8.encode(cmd), withoutResponse: false);
      log(LogType.tx, 'CMD: $cmd');
    } catch (e) { log(LogType.err, 'CMD: $e'); }
  }

  void clearLog() {
    logs.clear();
    readCount = 0;
    notifyListeners();
  }
}

enum ConnectionState { disconnected, scanning, connecting, connected }

enum LogType { info, tx, rx, err }

class LogEntry {
  final DateTime ts;
  final LogType type;
  final String msg;
  LogEntry(this.ts, this.type, this.msg);
}

// ══════════════════════════════════════════════════════════════
//  Home Screen (Tabs)
// ══════════════════════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _ble = BleService();
  int _tabIdx = 0;

  @override
  void initState() {
    super.initState();
    _ble.addListener(_refresh);
  }

  @override
  void dispose() {
    _ble.removeListener(_refresh);
    _ble.disconnect();
    super.dispose();
  }

  void _refresh() => setState(() {});

  Color _connColor() {
    switch (_ble.state) {
      case ConnectionState.connected: return Palette.success;
      case ConnectionState.connecting:
      case ConnectionState.scanning: return Palette.warn;
      case ConnectionState.disconnected: return Palette.danger;
    }
  }

  String _connLabel() {
    switch (_ble.state) {
      case ConnectionState.connected: return 'DISCONNECT';
      case ConnectionState.connecting: return 'CONNECTING...';
      case ConnectionState.scanning: return 'SCANNING...';
      case ConnectionState.disconnected: return 'CONNECT';
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardTab(ble: _ble),
      PodDetailTab(ble: _ble),
      LogTab(ble: _ble),
      SettingsTab(ble: _ble),
    ];

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Palette.card,
        elevation: 0,
        titleSpacing: 16,
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('BSS Gateway',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Palette.accent, letterSpacing: 1)),
                  Text(_ble.deviceName ?? 'Not Connected',
                    style: const TextStyle(fontSize: 11, color: Palette.textDim)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () {
                if (_ble.state == ConnectionState.connected) { _ble.disconnect(); }
                else if (_ble.state == ConnectionState.disconnected) { _ble.scanAndConnect(); }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: _connColor(),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_connLabel(),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _ble.state == ConnectionState.scanning || _ble.state == ConnectionState.connecting ? Colors.black : Colors.white,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  )),
              ),
            ),
          ],
        ),
      ),
      body: pages[_tabIdx],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Palette.card,
        selectedItemColor: Palette.accent,
        unselectedItemColor: Palette.textDim,
        currentIndex: _tabIdx,
        onTap: (i) => setState(() => _tabIdx = i),
        selectedLabelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined, size: 20), activeIcon: Icon(Icons.dashboard, size: 20), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.battery_charging_full_outlined, size: 20), activeIcon: Icon(Icons.battery_charging_full, size: 20), label: 'Pods'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt_outlined, size: 20), activeIcon: Icon(Icons.list_alt, size: 20), label: 'Log'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outlined, size: 20), activeIcon: Icon(Icons.person, size: 20), label: 'Profile'),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  Reusable Widgets
// ══════════════════════════════════════════════════════════════
class _Card extends StatelessWidget {
  final Widget? title;
  final Widget child;
  final Widget? action;
  const _Card({this.title, required this.child, this.action});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Palette.card,
        border: Border.all(color: Palette.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(child: DefaultTextStyle(
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Palette.accent, letterSpacing: 1.5),
                    child: title!,
                  )),
                  if (action != null) action!,
                ],
              ),
            ),
          if (title != null) Container(height: 1, color: Palette.border, margin: const EdgeInsets.only(bottom: 10)),
          child,
        ],
      ),
    );
  }
}

class _DataItem extends StatelessWidget {
  final String label, value, unit;
  final Color color;
  const _DataItem({required this.label, required this.value, this.unit = '', this.color = Palette.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Palette.dataBg, borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Text(label.toUpperCase(),
            style: const TextStyle(fontSize: 10, color: Palette.textDim, letterSpacing: 0.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color, fontFamily: 'monospace')),
          if (unit.isNotEmpty) Text(unit, style: const TextStyle(fontSize: 10, color: Palette.textDim)),
        ],
      ),
    );
  }
}

Color _socColor(num s) => s >= 60 ? Palette.soc : s >= 30 ? Palette.warn : Palette.danger;
Color _tempColor(num t) => t <= 45 ? Palette.soc : t <= 55 ? Palette.warn : Palette.danger;
Color _cellColor(num mv) => (mv >= 3200 && mv <= 3650) ? Palette.soc : (mv >= 3000 && mv <= 3800) ? Palette.warn : Palette.danger;

Widget _statusBadge(String? v) {
  if (v == 'yes') return const Text('YES', style: TextStyle(color: Palette.success, fontWeight: FontWeight.w700, fontSize: 18));
  if (v == 'no') return const Text('NO', style: TextStyle(color: Palette.danger, fontWeight: FontWeight.w700, fontSize: 18));
  return const Text('--', style: TextStyle(color: Palette.text, fontWeight: FontWeight.w700, fontSize: 18));
}

// ══════════════════════════════════════════════════════════════
//  Dashboard Tab
// ══════════════════════════════════════════════════════════════
class DashboardTab extends StatelessWidget {
  final BleService ble;
  const DashboardTab({super.key, required this.ble});

  @override
  Widget build(BuildContext context) {
    final s = ble.stationInfo;
    final p = ble.podSummary;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          if (s != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${s['station_id'] ?? '--'} • ${s['version'] ?? '--'} • ${s['fw_date'] ?? ''}',
                style: const TextStyle(fontSize: 11, color: Palette.textDim, letterSpacing: 1),
                textAlign: TextAlign.center,
              ),
            ),
          _Card(
            title: const Text('STATION INFO'),
            action: _refreshBtn(() => ble.readStationInfo()),
            child: s == null ? _noData() : Column(children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.7,
                children: [
                  _DataItem(label: 'Station ID', value: '${s['station_id'] ?? '--'}', color: Palette.accent),
                  _DataItem(label: 'Version', value: '${s['version'] ?? '--'}', color: Palette.accent),
                  Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Palette.dataBg, borderRadius: BorderRadius.circular(8)),
                    child: Column(children: [
                      const Text('WIFI', style: TextStyle(fontSize: 10, color: Palette.textDim)),
                      const SizedBox(height: 4),
                      _statusBadge(s['wifi'] as String?),
                      Text('${s['wifi_ssid'] ?? ''}', style: const TextStyle(fontSize: 10, color: Palette.textDim)),
                    ]),
                  ),
                  Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Palette.dataBg, borderRadius: BorderRadius.circular(8)),
                    child: Column(children: [
                      const Text('MQTT', style: TextStyle(fontSize: 10, color: Palette.textDim)),
                      const SizedBox(height: 4),
                      _statusBadge(s['mqtt'] as String?),
                      const Text('broker', style: TextStyle(fontSize: 10, color: Palette.textDim)),
                    ]),
                  ),
                  Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Palette.dataBg, borderRadius: BorderRadius.circular(8)),
                    child: Column(children: [
                      const Text('SD CARD', style: TextStyle(fontSize: 10, color: Palette.textDim)),
                      const SizedBox(height: 4),
                      _statusBadge(s['sd'] as String?),
                      const Text('storage', style: TextStyle(fontSize: 10, color: Palette.textDim)),
                    ]),
                  ),
                  _DataItem(label: 'Slaves', value: '${s['slaves'] ?? '--'}', unit: 'pods', color: Palette.cap),
                  _DataItem(label: 'Free Heap', value: s['free_heap'] != null ? ((s['free_heap'] as num)/1024).toStringAsFixed(1) : '--', unit: 'KB', color: Palette.cap),
                  _DataItem(label: 'Faults', value: '0x${(s['fault'] as num? ?? 0).toInt().toRadixString(16).toUpperCase().padLeft(2,'0')}',
                    color: (s['fault'] as num? ?? 0) == 0 ? Palette.success : Palette.danger),
                ],
              ),
              const SizedBox(height: 10),
              Text('${s['mac'] ?? '--'}  ·  ${s['ip'] ?? '--'}  ·  ${s['wifi_rssi'] ?? '--'} dBm',
                style: const TextStyle(fontSize: 11, color: Palette.textDim, fontFamily: 'monospace'), textAlign: TextAlign.center),
            ]),
          ),
          _Card(
            title: Row(children: const [Text('POD SUMMARY'), SizedBox(width: 8), _LiveDot()]),
            action: _refreshBtn(() {/* auto-notify handles it */}, label: 'LIVE'),
            child: p == null ? _noData(hint: 'Waiting for auto-notify...') : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Total Pods: ${p['total_pods'] ?? 0}', style: const TextStyle(fontSize: 11, color: Palette.textDim, fontFamily: 'monospace')),
                ),
                if (p['pods'] is List) ...(p['pods'] as List).map((pod) => _podSummaryCard(pod as Map<String, dynamic>)).toList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _podSummaryCard(Map<String, dynamic> pod) {
    final soc = (pod['soc'] as num?) ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.dataBg,
        border: Border.all(color: Palette.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(children: [
        Row(children: [
          Text('POD ${pod['pod']}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Palette.accent, letterSpacing: 1)),
          const Spacer(),
          Text('Relay: ${pod['relay'] ?? '--'}',
            style: const TextStyle(fontSize: 10, color: Palette.textDim, fontFamily: 'monospace')),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _statCol('Voltage', '${(pod['v'] as num?)?.toStringAsFixed(2) ?? '--'}V', Palette.volt),
          _statCol('Current', '${(pod['i'] as num?)?.toStringAsFixed(2) ?? '--'}A', Palette.curr),
          _statCol('Temp', '${(pod['temp'] as num?)?.toStringAsFixed(1) ?? '--'}°', _tempColor(pod['temp'] as num? ?? 0)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          _statCol('SOC', '$soc%', _socColor(soc)),
          _statCol('SOH', '${pod['soh'] ?? '--'}%', Palette.soh),
          const Expanded(child: SizedBox()),
        ]),
      ]),
    );
  }

  Widget _statCol(String label, String val, Color color) => Expanded(child: Column(children: [
    Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, color: Palette.textDim, fontWeight: FontWeight.w700)),
    const SizedBox(height: 2),
    Text(val, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color, fontFamily: 'monospace')),
  ]));

  Widget _refreshBtn(VoidCallback onTap, {String label = 'READ'}) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(border: Border.all(color: Palette.accent), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: const TextStyle(fontSize: 10, color: Palette.accent, fontWeight: FontWeight.w700)),
    ),
  );

  Widget _noData({String hint = 'Connect and read'}) => Padding(
    padding: const EdgeInsets.all(20),
    child: Text(hint, style: const TextStyle(color: Palette.textDim, fontSize: 11, letterSpacing: 1), textAlign: TextAlign.center),
  );
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true); }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _ctrl,
    child: Row(mainAxisSize: MainAxisSize.min, children: const [
      Icon(Icons.circle, size: 8, color: Palette.success),
      SizedBox(width: 4),
      Text('LIVE', style: TextStyle(fontSize: 9, color: Palette.success, fontWeight: FontWeight.w700)),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════
//  Pod Detail Tab
// ══════════════════════════════════════════════════════════════
class PodDetailTab extends StatelessWidget {
  final BleService ble;
  const PodDetailTab({super.key, required this.ble});

  @override
  Widget build(BuildContext context) {
    final d = ble.podDetail;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        _Card(
          title: const Text('SELECT POD'),
          action: GestureDetector(
            onTap: () => ble.readPodDetail(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(border: Border.all(color: Palette.accent), borderRadius: BorderRadius.circular(4)),
              child: const Text('READ', style: TextStyle(fontSize: 10, color: Palette.accent, fontWeight: FontWeight.w700)),
            ),
          ),
          child: Row(children: List.generate(5, (i) {
            final n = i + 1;
            final active = ble.selectedPod == n;
            return Expanded(child: Padding(
              padding: EdgeInsets.only(right: i < 4 ? 4 : 0),
              child: GestureDetector(
                onTap: () => ble.selectPod(n),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: active ? Palette.accent : Palette.dataBg,
                    border: Border.all(color: active ? Palette.accent : Palette.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$n',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                      color: active ? Colors.black : Palette.textDim)),
                ),
              ),
            ));
          })),
        ),
        if (d != null) ...[
          _socBar(d),
          _Card(
            title: const Text('TELEMETRY'),
            child: GridView.count(
              crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.7,
              children: [
                _DataItem(label: 'Pack V', value: (d['pack_v'] as num?)?.toStringAsFixed(3) ?? '--', unit: 'V', color: Palette.volt),
                _DataItem(label: 'Pack I', value: (d['pack_i'] as num?)?.toStringAsFixed(2) ?? '--', unit: 'A', color: Palette.curr),
                _DataItem(label: 'SOH', value: '${d['soh'] ?? '--'}', unit: '%', color: Palette.soh),
                _DataItem(label: 'Cycles', value: '${d['cycles'] ?? '--'}', unit: 'count', color: Palette.cycle),
                _DataItem(label: 'Min Cell', value: '${d['min_cv'] ?? '--'}', unit: 'mV', color: Palette.volt),
                _DataItem(label: 'Max Cell', value: '${d['max_cv'] ?? '--'}', unit: 'mV', color: Palette.volt),
                _DataItem(label: 'Avail Cap', value: '${d['avail_cap'] ?? '--'}', unit: 'mAh', color: Palette.cap),
                _DataItem(label: 'Relay', value: '${d['relay'] ?? '--'}', unit: 'state', color: Palette.text),
              ],
            ),
          ),
          if (d['cells'] is List) _cellsCard(d['cells'] as List),
          if (d['temps'] is List) _tempsCard('NTC TEMPERATURES', d['temps'] as List, 'T'),
          if (d['pdu_temps'] is List) _tempsCard('PDU TEMPERATURES', d['pdu_temps'] as List, 'PDU'),
          _Card(child: _DataItem(label: 'Pod NTC Temp', value: (d['pod_temp'] as num?)?.toStringAsFixed(1) ?? '--', unit: 'C', color: Palette.temp)),
        ] else
          Container(
            padding: const EdgeInsets.all(40),
            child: const Text('Select pod, tap READ', style: TextStyle(color: Palette.textDim, letterSpacing: 1), textAlign: TextAlign.center),
          ),
      ]),
    );
  }

  Widget _socBar(Map<String, dynamic> d) {
    final soc = (d['soc'] as num?) ?? 0;
    return _Card(child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Palette.dataBg, borderRadius: BorderRadius.circular(8)),
      child: Column(children: [
        Row(children: [
          Text('POD ${d['pod']} - SOC',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Palette.textDim, letterSpacing: 0.5)),
          const Spacer(),
          Text('${(soc as num).toStringAsFixed(1)} %',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _socColor(soc), fontFamily: 'monospace')),
        ]),
        const SizedBox(height: 6),
        Container(
          height: 10,
          decoration: BoxDecoration(color: Palette.card, borderRadius: BorderRadius.circular(5)),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: (soc.toDouble() / 100).clamp(0.0, 1.0),
            child: Container(decoration: BoxDecoration(color: _socColor(soc), borderRadius: BorderRadius.circular(5))),
          ),
        ),
      ]),
    ));
  }

  Widget _cellsCard(List cells) {
    final vals = cells.map((e) => (e as num).toInt()).toList();
    final vMin = vals.where((v) => v > 0).fold<int>(99999, (a,b) => a < b ? a : b);
    final vMax = vals.fold<int>(0, (a,b) => a > b ? a : b);
    return _Card(
      title: const Text('CELL VOLTAGES (mV)'),
      child: GridView.count(
        crossAxisCount: 4, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6, crossAxisSpacing: 6, childAspectRatio: 1.6,
        children: List.generate(vals.length, (i) {
          final mv = vals[i];
          final color = mv == vMin ? Palette.danger : mv == vMax ? Palette.success : _cellColor(mv);
          return Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Palette.dataBg,
              border: Border(left: BorderSide(color: color, width: 3)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('C${i+1}', style: const TextStyle(fontSize: 10, color: Palette.textDim, fontWeight: FontWeight.w600)),
              Text('$mv', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color, fontFamily: 'monospace')),
            ]),
          );
        }),
      ),
    );
  }

  Widget _tempsCard(String title, List temps, String prefix) {
    return _Card(
      title: Text(title),
      child: Wrap(spacing: 6, runSpacing: 6,
        children: List.generate(temps.length, (i) {
          final t = (temps[i] as num).toDouble();
          final color = t > 55 ? Palette.danger : t > 45 ? Palette.warn : Palette.success;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: Palette.dataBg, borderRadius: BorderRadius.circular(6)),
            child: Column(children: [
              Text('$prefix${i+1}', style: const TextStyle(fontSize: 10, color: Palette.textDim, fontWeight: FontWeight.w600)),
              Text(t.toStringAsFixed(1), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color, fontFamily: 'monospace')),
            ]),
          );
        }),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  Log Tab
// ══════════════════════════════════════════════════════════════
class LogTab extends StatelessWidget {
  final BleService ble;
  const LogTab({super.key, required this.ble});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: _Card(
        title: const Text('BLE LOG'),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Palette.logBg, borderRadius: BorderRadius.circular(8)),
            constraints: const BoxConstraints(maxHeight: 500),
            child: SingleChildScrollView(
              reverse: true,
              child: Column(children: ble.logs.map((e) => _logEntry(e)).toList()),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () => ble.clearLog(),
            style: ElevatedButton.styleFrom(backgroundColor: Palette.border, foregroundColor: Palette.text),
            child: const Text('Clear Log', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          )),
        ]),
      ),
    );
  }

  Widget _logEntry(LogEntry e) {
    final ts = '${e.ts.hour.toString().padLeft(2,'0')}:${e.ts.minute.toString().padLeft(2,'0')}:${e.ts.second.toString().padLeft(2,'0')}';
    Color color;
    String prefix;
    switch (e.type) {
      case LogType.tx: color = Palette.curr; prefix = 'TX'; break;
      case LogType.rx: color = Palette.soc; prefix = 'RX'; break;
      case LogType.err: color = Palette.danger; prefix = 'ERR'; break;
      case LogType.info: color = Palette.volt; prefix = 'INFO'; break;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('[$ts] ', style: const TextStyle(fontSize: 10, color: Palette.textDim, fontFamily: 'monospace')),
        Text('[$prefix] ', style: TextStyle(fontSize: 10, color: color, fontFamily: 'monospace', fontWeight: FontWeight.w700)),
        Expanded(child: Text(e.msg, style: TextStyle(fontSize: 10, color: color, fontFamily: 'monospace'))),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  Settings / Profile Tab
// ══════════════════════════════════════════════════════════════
class SettingsTab extends StatelessWidget {
  final BleService ble;
  const SettingsTab({super.key, required this.ble});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        // Profile Card
        _Card(child: Column(children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Palette.accent, Palette.accent.withOpacity(0.6)]),
            ),
            child: const Center(child: Text('JT', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white))),
          ),
          const SizedBox(height: 10),
          const Text('Jaytank', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1)),
          const Text('Administrator', style: TextStyle(fontSize: 13, color: Palette.textDim, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Palette.accent.withOpacity(0.2),
              border: Border.all(color: Palette.accent),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('● Session Active', style: TextStyle(fontSize: 11, color: Palette.accent, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _statBox('${ble.readCount}', 'Reads')),
            const SizedBox(width: 8),
            Expanded(child: _statBox(ble.state == ConnectionState.connected ? 'Online' : 'Offline', 'BLE')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _statBox((ble.deviceName ?? '--').replaceAll(RegExp(r'^BSS[X]?_'), ''), 'Station')),
            const SizedBox(width: 8),
            Expanded(child: _statBox('${ble.stationInfo?['version'] ?? '--'}', 'FW Ver')),
          ]),
        ])),

        // Control commands
        _Card(
          title: const Text('REMOTE CONTROL'),
          child: Column(children: [
            _cmdButton(context, 'REBOOT DEVICE', Palette.warn, () => _confirmCmd(context, 'reboot')),
            const SizedBox(height: 10),
            _cmdButton(context, 'FACTORY RESET', Palette.danger, () => _confirmCmd(context, 'factory_reset')),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Palette.dataBg, borderRadius: BorderRadius.circular(6)),
              child: Text(ble.lastCmdResponse,
                style: const TextStyle(fontSize: 11, color: Palette.accent, fontFamily: 'monospace')),
            ),
          ]),
        ),

        // About
        _Card(
          title: const Text('ABOUT'),
          child: Column(children: [
            _aboutRow(Icons.phone_android, 'BSS Gateway Monitor', 'Flutter Native App · v1.0', Palette.volt),
            _aboutRow(Icons.person, 'Developed by', 'Jay Tank', Palette.success),
            _aboutRow(Icons.settings, 'Station ID', '${ble.stationInfo?['station_id'] ?? 'Not connected'}', Palette.warn),
            _aboutRow(Icons.memory, 'Firmware', '${ble.stationInfo?['version'] ?? '--'} · ${ble.stationInfo?['fw_date'] ?? ''}', Palette.danger),
          ]),
        ),

        // Logout
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: () => _logout(context),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Palette.danger),
              foregroundColor: Palette.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('◼  SIGN OUT', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 14)),
          ),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _statBox(String val, String label) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Palette.dataBg, borderRadius: BorderRadius.circular(8)),
    child: Column(children: [
      Text(val, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Palette.accent, fontFamily: 'monospace')),
      const SizedBox(height: 2),
      Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, color: Palette.textDim)),
    ]),
  );

  Widget _cmdButton(BuildContext ctx, String label, Color color, VoidCallback onTap) => SizedBox(
    width: double.infinity,
    height: 50,
    child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color),
        foregroundColor: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1, fontSize: 14)),
    ),
  );

  Widget _aboutRow(IconData icon, String title, String subtitle, Color iconColor) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Palette.border))),
    child: Row(children: [
      Container(
        width: 34, height: 34,
        decoration: BoxDecoration(color: iconColor.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 18, color: iconColor),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        Text(subtitle, style: const TextStyle(fontSize: 11, color: Palette.textDim, fontFamily: 'monospace')),
      ])),
    ]),
  );

  void _confirmCmd(BuildContext context, String cmd) {
    final isReboot = cmd == 'reboot';
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: Palette.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Palette.border)),
      title: Text(isReboot ? 'REBOOT DEVICE?' : 'FACTORY RESET?',
        style: TextStyle(color: isReboot ? Palette.warn : Palette.danger, fontWeight: FontWeight.w900, letterSpacing: 1)),
      content: Text(
        isReboot ? 'The device will restart. You will need to reconnect after boot.'
                 : 'This ERASES all stored settings (WiFi, MQTT, SD, OTA) and reboots. Cannot be undone.',
        style: const TextStyle(color: Palette.textDim, fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL', style: TextStyle(color: Palette.textDim))),
        TextButton(
          onPressed: () { Navigator.pop(context); ble.sendCommand(cmd); },
          child: Text(isReboot ? 'REBOOT' : 'RESET',
            style: TextStyle(color: isReboot ? Palette.warn : Palette.danger, fontWeight: FontWeight.w700)),
        ),
      ],
    ));
  }

  void _logout(BuildContext context) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      backgroundColor: Palette.card,
      title: const Text('Sign Out?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('SIGN OUT', style: TextStyle(color: Palette.danger))),
      ],
    ));
    if (confirm == true) {
      await ble.disconnect();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('bss_auth');
      if (context.mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      }
    }
  }
}
