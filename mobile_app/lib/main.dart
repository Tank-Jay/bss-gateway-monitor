// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
//  Theme System — Dark + Light palettes
// ══════════════════════════════════════════════════════════════
class _Colors {
  final Color bg, card, border, accent, text, textDim;
  final Color success, warn, danger;
  final Color volt, curr, soc, soh, temp, cycle, cap;
  final Color dataBg, logBg;
  const _Colors({
    required this.bg, required this.card, required this.border, required this.accent,
    required this.text, required this.textDim,
    required this.success, required this.warn, required this.danger,
    required this.volt, required this.curr, required this.soc, required this.soh,
    required this.temp, required this.cycle, required this.cap,
    required this.dataBg, required this.logBg,
  });
}

const _darkColors = _Colors(
  bg: Color(0xFF0F1923),
  card: Color(0xFF1A2733),
  border: Color(0xFF2A3A4A),
  accent: Color(0xFF00D4AA),
  text: Color(0xFFE0E8F0),
  textDim: Color(0xFF8899AA),
  success: Color(0xFF00CC66),
  warn: Color(0xFFFFAA00),
  danger: Color(0xFFFF4444),
  volt: Color(0xFF4FC3F7),
  curr: Color(0xFFFFB74D),
  soc: Color(0xFF81C784),
  soh: Color(0xFFCE93D8),
  temp: Color(0xFFEF5350),
  cycle: Color(0xFF90A4AE),
  cap: Color(0xFF4DD0E1),
  dataBg: Color(0xFF0F1923),
  logBg: Color(0xFF0A0F14),
);

const _lightColors = _Colors(
  bg: Color(0xFFF0F4F8),
  card: Color(0xFFFFFFFF),
  border: Color(0xFFD0DAE6),
  accent: Color(0xFF00A882),
  text: Color(0xFF1A2733),
  textDim: Color(0xFF5A7080),
  success: Color(0xFF00A855),
  warn: Color(0xFFE09000),
  danger: Color(0xFFE03333),
  volt: Color(0xFF0288D1),
  curr: Color(0xFFEF6C00),
  soc: Color(0xFF388E3C),
  soh: Color(0xFF7B1FA2),
  temp: Color(0xFFD32F2F),
  cycle: Color(0xFF546E7A),
  cap: Color(0xFF00838F),
  dataBg: Color(0xFFE8F0F8),
  logBg: Color(0xFFE0E8F0),
);

/// Theme controller — notifier-driven so toggle rebuilds entire app.
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.dark);

/// Legacy Palette class kept as read-only bridge to active theme.
/// Widgets read `Palette.bg` etc., which returns the currently-active theme's color.
class Palette {
  static _Colors get _c => themeModeNotifier.value == ThemeMode.light ? _lightColors : _darkColors;
  static Color get bg      => _c.bg;
  static Color get card    => _c.card;
  static Color get border  => _c.border;
  static Color get accent  => _c.accent;
  static Color get text    => _c.text;
  static Color get textDim => _c.textDim;
  static Color get success => _c.success;
  static Color get warn    => _c.warn;
  static Color get danger  => _c.danger;
  static Color get volt    => _c.volt;
  static Color get curr    => _c.curr;
  static Color get soc     => _c.soc;
  static Color get soh     => _c.soh;
  static Color get temp    => _c.temp;
  static Color get cycle   => _c.cycle;
  static Color get cap     => _c.cap;
  static Color get dataBg  => _c.dataBg;
  static Color get logBg   => _c.logBg;
}

Future<void> loadSavedTheme() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('bss_theme');
  if (saved == 'light') themeModeNotifier.value = ThemeMode.light;
}

Future<void> toggleTheme(ThemeMode mode) async {
  themeModeNotifier.value = mode;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('bss_theme', mode == ThemeMode.light ? 'light' : 'dark');
}

// ══════════════════════════════════════════════════════════════
//  Main
// ══════════════════════════════════════════════════════════════
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadSavedTheme();
  await UpdateChecker.init();
  runApp(const BssApp());
}

class BssApp extends StatelessWidget {
  const BssApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (_, mode, __) {
        final isLight = mode == ThemeMode.light;
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Palette.card,
          statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
        ));
        return MaterialApp(
          title: 'BSS Gateway Monitor',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: _buildTheme(false),
          darkTheme: _buildTheme(true),
          home: const LoginScreen(),
        );
      },
    );
  }

  ThemeData _buildTheme(bool dark) {
    final c = dark ? _darkColors : _lightColors;
    return ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: c.bg,
      fontFamily: 'Roboto',
      colorScheme: dark
        ? ColorScheme.dark(primary: c.accent, surface: c.card, error: c.danger)
        : ColorScheme.light(primary: c.accent, surface: c.card, error: c.danger),
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
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
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
                Text('BSS',
                  style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: Palette.accent, letterSpacing: 4)),
                Text('GATEWAY MONITOR',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Palette.text, letterSpacing: 1)),
                const SizedBox(height: 4),
                Text('Sign in to continue',
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
                    child: Text(_err, style: TextStyle(color: Palette.danger, fontSize: 13)),
                  ),
                const SizedBox(height: 14),
                Text('v1.0 · BSS IoT Gateway ESP32-S3',
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
      style: TextStyle(color: Palette.text, fontSize: 15),
      decoration: InputDecoration(
        hintText: label,
        hintStyle: TextStyle(color: Palette.textDim),
        filled: true,
        fillColor: Palette.dataBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Palette.accent),
        ),
      ),
      onSubmitted: (_) => _doLogin(),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  Update Checker — GitHub Releases
// ══════════════════════════════════════════════════════════════
class UpdateInfo {
  final String latestVersion;
  final String apkUrl;
  final String releaseNotes;
  final String releasePageUrl;
  UpdateInfo({required this.latestVersion, required this.apkUrl, required this.releaseNotes, required this.releasePageUrl});
}

class UpdateChecker {
  static const String repo = 'Tank-Jay/bss-gateway-monitor';
  static String _currentVersion = '1.0.0';

  static Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
    } catch (_) {}
  }

  static String get currentVersion => _currentVersion;

  static List<int> _parseVersion(String v) {
    // "v1.0.2-build8" -> [1, 0, 2];  "1.0.1" -> [1, 0, 1]
    var s = v.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    final dash = s.indexOf('-');
    if (dash >= 0) s = s.substring(0, dash);
    final plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus);
    final parts = s.split('.').map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();
    while (parts.length < 3) parts.add(0);
    return parts;
  }

  static int _cmpVersion(String a, String b) {
    final pa = _parseVersion(a);
    final pb = _parseVersion(b);
    for (int i = 0; i < 3; i++) {
      if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
    }
    return 0;
  }

  static Future<UpdateInfo?> check() async {
    try {
      final resp = await http
          .get(Uri.parse('https://api.github.com/repos/$repo/releases/latest'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final tag = (data['tag_name'] as String?) ?? '';
      final notes = (data['body'] as String?) ?? '';
      final htmlUrl = (data['html_url'] as String?) ?? '';
      final assets = (data['assets'] as List?) ?? [];
      String? apk;
      for (final a in assets) {
        final name = (a['name'] as String?) ?? '';
        if (name.endsWith('.apk')) {
          apk = a['browser_download_url'] as String?;
          break;
        }
      }
      if (apk == null || tag.isEmpty) return null;
      if (_cmpVersion(tag, _currentVersion) <= 0) return null;
      return UpdateInfo(latestVersion: tag, apkUrl: apk, releaseNotes: notes, releasePageUrl: htmlUrl);
    } catch (_) {
      return null;
    }
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

  /// Check permissions + Bluetooth state. Returns true if ready to scan.
  Future<bool> _preflightCheck() async {
    log(LogType.info, 'Checking permissions...');
    if (!await requestPermissions()) {
      log(LogType.err, 'Bluetooth permissions denied — grant in Settings');
      return false;
    }
    if (await FlutterBluePlus.isSupported == false) {
      log(LogType.err, 'Bluetooth not supported on this device');
      return false;
    }
    final btState = await FlutterBluePlus.adapterState.first;
    if (btState != BluetoothAdapterState.on) {
      log(LogType.err, 'Bluetooth is OFF — turn it on in system settings');
      return false;
    }
    return true;
  }

  /// Start scanning. Exposes results via FlutterBluePlus.scanResults stream.
  /// Caller (UI) listens and shows picker. Call [stopScanning] when done.
  Future<bool> startScanning() async {
    if (!await _preflightCheck()) return false;
    _setState(ConnectionState.scanning);
    log(LogType.info, 'Scan started (20s timeout)');
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));
      return true;
    } catch (e) {
      log(LogType.err, 'Scan start failed: $e');
      _setState(ConnectionState.disconnected);
      return false;
    }
  }

  Future<void> stopScanning() async {
    try { await FlutterBluePlus.stopScan(); } catch (_) {}
    if (state == ConnectionState.scanning) _setState(ConnectionState.disconnected);
  }

  /// Connect to a user-selected device.
  Future<void> connectToDevice(BluetoothDevice target) async {
    try {
      await stopScanning();
      device = target;
      deviceName = target.platformName.isNotEmpty ? target.platformName : target.remoteId.str;
      log(LogType.info, 'Selected: $deviceName');

      _setState(ConnectionState.connecting);
      log(LogType.info, 'Connecting to GATT...');
      await target.connect(timeout: const Duration(seconds: 15), autoConnect: false);
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

          // Route op:"params" to the params handler; others are just status.
          try {
            final decoded = json.decode(txt);
            if (decoded is Map<String, dynamic> && decoded['op'] == 'params') {
              _handleParamsResponse(decoded);
              return;
            }
          } catch (_) {}

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

  // ── Parameter editing (get_params, set_param, save_reboot) ──

  /// Currently-loaded params from firmware (null until readParams() runs).
  Map<String, dynamic>? params;

  /// Ask firmware to send current params. Response arrives via onResponseNotify
  /// which calls _handleParamsResponse() if op=="params".
  Future<void> requestParams() async {
    if (charCommand == null) { log(LogType.err, 'Not connected'); return; }
    try {
      await charCommand!.write(utf8.encode('{"op":"get_params"}'), withoutResponse: false);
      log(LogType.tx, 'get_params');
    } catch (e) { log(LogType.err, 'get_params: $e'); }
  }

  /// Write a single param. App layer should call requestParams() after to refresh.
  Future<void> setParam(String key, String value) async {
    if (charCommand == null) { log(LogType.err, 'Not connected'); return; }
    try {
      final payload = json.encode({'op': 'set_param', 'key': key, 'value': value});
      await charCommand!.write(utf8.encode(payload), withoutResponse: false);
      log(LogType.tx, 'set $key');
    } catch (e) { log(LogType.err, 'set_param: $e'); }
  }

  Future<void> saveAndReboot() async {
    if (charCommand == null) return;
    try {
      await charCommand!.write(utf8.encode('{"op":"save_reboot"}'), withoutResponse: false);
      log(LogType.tx, 'save_reboot');
    } catch (e) { log(LogType.err, 'save_reboot: $e'); }
  }

  /// Called by onResponseNotify if op=="params" — updates params map.
  void _handleParamsResponse(Map<String, dynamic> data) {
    params = data;
    notifyListeners();
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
  UpdateInfo? _update;

  @override
  void initState() {
    super.initState();
    _ble.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    final info = await UpdateChecker.check();
    if (info != null && mounted) setState(() => _update = info);
  }

  Future<void> _openUpdate() async {
    if (_update == null) return;
    final uri = Uri.parse(_update!.apkUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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

  void _showDevicePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Palette.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DevicePickerSheet(ble: _ble),
    );
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
                  Text('BSS Gateway',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Palette.accent, letterSpacing: 1)),
                  Text(_ble.deviceName ?? 'Not Connected',
                    style: TextStyle(fontSize: 11, color: Palette.textDim)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () {
                if (_ble.state == ConnectionState.connected) { _ble.disconnect(); }
                else if (_ble.state == ConnectionState.disconnected) { _showDevicePicker(); }
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
      body: Column(children: [
        if (_update != null)
          Material(
            color: Palette.accent,
            child: InkWell(
              onTap: _openUpdate,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  Icon(Icons.system_update, color: Palette.bg, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Update available: ${_update!.latestVersion} — tap to download',
                      style: TextStyle(color: Palette.bg, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _update = null),
                    child: Icon(Icons.close, color: Palette.bg, size: 18),
                  ),
                ]),
              ),
            ),
          ),
        Expanded(child: pages[_tabIdx]),
      ]),
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
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Palette.accent, letterSpacing: 1.5),
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
  final Color? color;
  const _DataItem({required this.label, required this.value, this.unit = '', this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Palette.dataBg, borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Text(label.toUpperCase(),
            style: TextStyle(fontSize: 10, color: Palette.textDim, letterSpacing: 0.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color ?? Palette.text, fontFamily: 'monospace')),
          if (unit.isNotEmpty) Text(unit, style: TextStyle(fontSize: 10, color: Palette.textDim)),
        ],
      ),
    );
  }
}

Color _socColor(num s) => s >= 60 ? Palette.soc : s >= 30 ? Palette.warn : Palette.danger;
Color _tempColor(num t) => t <= 45 ? Palette.soc : t <= 55 ? Palette.warn : Palette.danger;
Color _cellColor(num mv) => (mv >= 3200 && mv <= 3650) ? Palette.soc : (mv >= 3000 && mv <= 3800) ? Palette.warn : Palette.danger;

Widget _statusBadge(String? v) {
  if (v == 'yes') return Text('YES', style: TextStyle(color: Palette.success, fontWeight: FontWeight.w700, fontSize: 18));
  if (v == 'no') return Text('NO', style: TextStyle(color: Palette.danger, fontWeight: FontWeight.w700, fontSize: 18));
  return Text('--', style: TextStyle(color: Palette.text, fontWeight: FontWeight.w700, fontSize: 18));
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
                style: TextStyle(fontSize: 11, color: Palette.textDim, letterSpacing: 1),
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
                  _DataItem(label: 'Slaves', value: '${s['slaves'] ?? '--'}', unit: 'pods', color: Palette.cap),
                  _DataItem(label: 'IP', value: '${s['ip'] ?? '--'}', color: Palette.volt),
                  _DataItem(label: 'Faults', value: '0x${(s['fault'] as num? ?? 0).toInt().toRadixString(16).toUpperCase().padLeft(2,'0')}',
                    color: (s['fault'] as num? ?? 0) == 0 ? Palette.success : Palette.danger),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Palette.dataBg, borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('MAC', style: TextStyle(fontSize: 10, color: Palette.textDim, fontWeight: FontWeight.w700, letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text('${s['mac'] ?? '--'}',
                    style: TextStyle(fontSize: 14, color: Palette.volt, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
                ]),
              ),
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
                  child: Text('Total Pods: ${p['total_pods'] ?? 0}', style: TextStyle(fontSize: 11, color: Palette.textDim, fontFamily: 'monospace')),
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
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Palette.accent, letterSpacing: 1)),
          const Spacer(),
          Text('Relay: ${pod['relay'] ?? '--'}',
            style: TextStyle(fontSize: 10, color: Palette.textDim, fontFamily: 'monospace')),
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
    Text(label.toUpperCase(), style: TextStyle(fontSize: 9, color: Palette.textDim, fontWeight: FontWeight.w700)),
    const SizedBox(height: 2),
    Text(val, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color, fontFamily: 'monospace')),
  ]));

  Widget _refreshBtn(VoidCallback onTap, {String label = 'READ'}) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(border: Border.all(color: Palette.accent), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(fontSize: 10, color: Palette.accent, fontWeight: FontWeight.w700)),
    ),
  );

  Widget _noData({String hint = 'Connect and read'}) => Padding(
    padding: const EdgeInsets.all(20),
    child: Text(hint, style: TextStyle(color: Palette.textDim, fontSize: 11, letterSpacing: 1), textAlign: TextAlign.center),
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
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.circle, size: 8, color: Palette.success),
      const SizedBox(width: 4),
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
              child: Text('READ', style: TextStyle(fontSize: 10, color: Palette.accent, fontWeight: FontWeight.w700)),
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
                _DataItem(label: 'Min Cell', value: (d['min_cv'] is num) ? ((d['min_cv'] as num) / 1000).toStringAsFixed(3) : '--', unit: 'V', color: Palette.volt),
                _DataItem(label: 'Max Cell', value: (d['max_cv'] is num) ? ((d['max_cv'] as num) / 1000).toStringAsFixed(3) : '--', unit: 'V', color: Palette.volt),
                _DataItem(label: 'Avail Cap', value: (d['avail_cap'] is num) ? ((d['avail_cap'] as num) / 1000).toStringAsFixed(3) : '--', unit: 'Ah', color: Palette.cap),
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
            child: Text('Select pod, tap READ', style: TextStyle(color: Palette.textDim, letterSpacing: 1), textAlign: TextAlign.center),
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
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Palette.textDim, letterSpacing: 0.5)),
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
      title: const Text('CELL VOLTAGES (V)'),
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
              Text('C${i+1}', style: TextStyle(fontSize: 10, color: Palette.textDim, fontWeight: FontWeight.w600)),
              Text((mv / 1000).toStringAsFixed(3), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color, fontFamily: 'monospace')),
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
              Text('$prefix${i+1}', style: TextStyle(fontSize: 10, color: Palette.textDim, fontWeight: FontWeight.w600)),
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
        Text('[$ts] ', style: TextStyle(fontSize: 10, color: Palette.textDim, fontFamily: 'monospace')),
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
          Text('Administrator', style: TextStyle(fontSize: 13, color: Palette.textDim, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Palette.accent.withOpacity(0.2),
              border: Border.all(color: Palette.accent),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('● Session Active', style: TextStyle(fontSize: 11, color: Palette.accent, fontWeight: FontWeight.w600)),
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

        // Device Parameters (WiFi + MQTT) — editable via BLE
        _Card(
          title: const Text('DEVICE PARAMETERS'),
          action: GestureDetector(
            onTap: () => ble.requestParams(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(border: Border.all(color: Palette.accent), borderRadius: BorderRadius.circular(4)),
              child: Text('READ', style: TextStyle(fontSize: 10, color: Palette.accent, fontWeight: FontWeight.w700)),
            ),
          ),
          child: ble.params == null
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text('Tap READ to load current parameters',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Palette.textDim, fontSize: 12)),
              )
            : Column(children: [
                _paramRow(context, 'WiFi SSID', 'wifi_ssid', ble.params!['wifi_ssid'], Icons.wifi, false),
                _paramRow(context, 'WiFi Password', 'wifi_pass', ble.params!['wifi_pass'], Icons.lock, true),
                _paramRow(context, 'MQTT Host', 'mqtt_host', ble.params!['mqtt_host'], Icons.cloud, false),
                _paramRow(context, 'MQTT Port', 'mqtt_port', '${ble.params!['mqtt_port'] ?? '--'}', Icons.numbers, false, isNumeric: true),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmSaveReboot(context),
                    icon: Icon(Icons.save_alt, color: Palette.warn, size: 18),
                    label: Text('SAVE & REBOOT',
                      style: TextStyle(color: Palette.warn, fontWeight: FontWeight.w700, letterSpacing: 1)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Palette.warn),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ]),
        ),

        // Appearance — Dark/Light theme toggle
        _Card(
          title: const Text('APPEARANCE'),
          child: ValueListenableBuilder<ThemeMode>(
            valueListenable: themeModeNotifier,
            builder: (_, mode, __) {
              final isLight = mode == ThemeMode.light;
              return Row(children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(color: Palette.volt.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                  child: Icon(isLight ? Icons.light_mode : Icons.dark_mode, size: 18, color: Palette.volt),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isLight ? 'Light Mode' : 'Dark Mode',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text('Tap to switch theme',
                      style: TextStyle(fontSize: 11, color: Palette.textDim)),
                  ],
                )),
                Switch(
                  value: isLight,
                  activeColor: Palette.accent,
                  onChanged: (v) => toggleTheme(v ? ThemeMode.light : ThemeMode.dark),
                ),
              ]);
            },
          ),
        ),

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
                style: TextStyle(fontSize: 11, color: Palette.accent, fontFamily: 'monospace')),
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
              side: BorderSide(color: Palette.danger),
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
      Text(val, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Palette.accent, fontFamily: 'monospace')),
      const SizedBox(height: 2),
      Text(label.toUpperCase(), style: TextStyle(fontSize: 10, color: Palette.textDim)),
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
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Palette.border))),
    child: Row(children: [
      Container(
        width: 34, height: 34,
        decoration: BoxDecoration(color: iconColor.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 18, color: iconColor),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        Text(subtitle, style: TextStyle(fontSize: 11, color: Palette.textDim, fontFamily: 'monospace')),
      ])),
    ]),
  );

  void _confirmCmd(BuildContext context, String cmd) {
    final isReboot = cmd == 'reboot';
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: Palette.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Palette.border)),
      title: Text(isReboot ? 'REBOOT DEVICE?' : 'FACTORY RESET?',
        style: TextStyle(color: isReboot ? Palette.warn : Palette.danger, fontWeight: FontWeight.w900, letterSpacing: 1)),
      content: Text(
        isReboot ? 'The device will restart. You will need to reconnect after boot.'
                 : 'This ERASES all stored settings (WiFi, MQTT, SD, OTA) and reboots. Cannot be undone.',
        style: TextStyle(color: Palette.textDim, fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('CANCEL', style: TextStyle(color: Palette.textDim))),
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
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text('SIGN OUT', style: TextStyle(color: Palette.danger))),
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

  Widget _paramRow(BuildContext context, String label, String key, dynamic value, IconData icon, bool isPassword, {bool isNumeric = false}) {
    final displayValue = (value == null || value.toString().isEmpty)
      ? '(not set)'
      : (isPassword ? '••••••••' : value.toString());

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Palette.border))),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(color: Palette.accent.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 18, color: Palette.accent),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(displayValue,
              style: TextStyle(fontSize: 11, color: Palette.textDim, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis),
          ],
        )),
        IconButton(
          icon: Icon(Icons.edit, size: 18, color: Palette.accent),
          tooltip: 'Edit',
          onPressed: () => _editParam(context, label, key, value, isPassword, isNumeric),
        ),
      ]),
    );
  }

  void _editParam(BuildContext context, String label, String key, dynamic currentValue, bool isPassword, bool isNumeric) {
    final ctrl = TextEditingController(text: isPassword ? '' : (currentValue?.toString() ?? ''));
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: Palette.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Palette.border)),
      title: Text('Edit $label',
        style: TextStyle(color: Palette.accent, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: isPassword,
          keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
          style: TextStyle(color: Palette.text),
          decoration: InputDecoration(
            hintText: isPassword ? 'Enter new password' : 'Enter value',
            hintStyle: TextStyle(color: Palette.textDim),
            filled: true,
            fillColor: Palette.dataBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Palette.border)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'After saving, tap "SAVE & REBOOT" to apply changes.',
          style: TextStyle(fontSize: 11, color: Palette.textDim),
          textAlign: TextAlign.center,
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('CANCEL', style: TextStyle(color: Palette.textDim))),
        TextButton(
          onPressed: () async {
            final val = ctrl.text;
            if (val.isEmpty) { Navigator.pop(context); return; }
            Navigator.pop(context);
            await ble.setParam(key, val);
            // Refresh params after short delay
            Future.delayed(const Duration(milliseconds: 500), () => ble.requestParams());
          },
          child: Text('SAVE', style: TextStyle(color: Palette.accent, fontWeight: FontWeight.w700)),
        ),
      ],
    ));
  }

  void _confirmSaveReboot(BuildContext context) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: Palette.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Palette.border)),
      title: Text('Apply & Reboot?',
        style: TextStyle(color: Palette.warn, fontWeight: FontWeight.w900, letterSpacing: 1)),
      content: Text(
        'Device will restart to apply parameter changes. You will need to reconnect after boot.',
        style: TextStyle(color: Palette.textDim, fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('CANCEL', style: TextStyle(color: Palette.textDim))),
        TextButton(
          onPressed: () { Navigator.pop(context); ble.saveAndReboot(); },
          child: Text('REBOOT', style: TextStyle(color: Palette.warn, fontWeight: FontWeight.w700)),
        ),
      ],
    ));
  }
}

// ══════════════════════════════════════════════════════════════
//  Device Picker Bottom Sheet
// ══════════════════════════════════════════════════════════════
class DevicePickerSheet extends StatefulWidget {
  final BleService ble;
  const DevicePickerSheet({super.key, required this.ble});

  @override
  State<DevicePickerSheet> createState() => _DevicePickerSheetState();
}

class _DevicePickerSheetState extends State<DevicePickerSheet> {
  final Map<String, ScanResult> _devices = {};  // Keyed by MAC
  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _scanning = false;
  bool _bssOnly = true;  // Filter toggle

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    widget.ble.stopScanning();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() { _devices.clear(); _scanning = true; });

    final ok = await widget.ble.startScanning();
    if (!ok) {
      if (mounted) setState(() => _scanning = false);
      return;
    }

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;
      setState(() {
        for (final r in results) {
          _devices[r.device.remoteId.str] = r;
        }
      });
    });

    // Auto-stop after 20s
    Future.delayed(const Duration(seconds: 20), () {
      if (mounted && _scanning) {
        setState(() => _scanning = false);
        widget.ble.stopScanning();
      }
    });
  }

  Future<void> _onDeviceTap(ScanResult r) async {
    _scanSub?.cancel();
    await widget.ble.stopScanning();
    if (!mounted) return;
    Navigator.pop(context);
    await widget.ble.connectToDevice(r.device);
  }

  String _deviceName(ScanResult r) {
    final a = r.device.platformName;
    final b = r.advertisementData.advName;
    if (a.isNotEmpty) return a;
    if (b.isNotEmpty) return b;
    return 'Unknown';
  }

  bool _isBss(String name) => name.startsWith('BSS_') || name.startsWith('BSSX_');

  @override
  Widget build(BuildContext context) {
    final all = _devices.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    final list = _bssOnly ? all.where((r) => _isBss(_deviceName(r))).toList() : all;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollCtrl) => Column(children: [
        // Drag handle
        Container(
          margin: const EdgeInsets.only(top: 8),
          width: 36, height: 4,
          decoration: BoxDecoration(color: Palette.border, borderRadius: BorderRadius.circular(2)),
        ),
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
          child: Row(children: [
            Expanded(child: Text('SELECT DEVICE',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Palette.accent))),
            IconButton(
              icon: Icon(_scanning ? Icons.stop_circle_outlined : Icons.refresh, color: Palette.accent),
              tooltip: _scanning ? 'Stop scan' : 'Rescan',
              onPressed: () {
                if (_scanning) {
                  widget.ble.stopScanning();
                  setState(() => _scanning = false);
                } else {
                  _startScan();
                }
              },
            ),
          ]),
        ),
        // Filter toggle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Text('Filter:', style: TextStyle(fontSize: 12, color: Palette.textDim)),
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text('BSS only (${all.where((r) => _isBss(_deviceName(r))).length})', style: const TextStyle(fontSize: 11)),
              selected: _bssOnly,
              onSelected: (v) => setState(() => _bssOnly = v),
              selectedColor: Palette.accent,
              backgroundColor: Palette.dataBg,
              labelStyle: TextStyle(color: _bssOnly ? Colors.black : Palette.text),
            ),
            const SizedBox(width: 6),
            ChoiceChip(
              label: Text('All (${all.length})', style: const TextStyle(fontSize: 11)),
              selected: !_bssOnly,
              onSelected: (v) => setState(() => _bssOnly = !v),
              selectedColor: Palette.accent,
              backgroundColor: Palette.dataBg,
              labelStyle: TextStyle(color: !_bssOnly ? Colors.black : Palette.text),
            ),
          ]),
        ),
        // Scan indicator
        if (_scanning)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Palette.warn.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Palette.warn)),
              SizedBox(width: 10),
              Text('Scanning...', style: TextStyle(color: Palette.warn, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        // Device list
        Expanded(
          child: list.isEmpty
            ? Center(child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text(
                  _scanning
                    ? (_bssOnly ? 'Scanning for BSS devices...' : 'Scanning...')
                    : (_bssOnly ? 'No BSS device found. Try "All" filter or rescan.' : 'No devices found'),
                  style: TextStyle(color: Palette.textDim, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ))
            : ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: list.length,
                itemBuilder: (_, i) => _deviceTile(list[i]),
              ),
        ),
      ]),
    );
  }

  Widget _deviceTile(ScanResult r) {
    final name = _deviceName(r);
    final isBss = _isBss(name);
    final rssi = r.rssi;
    final rssiIcon = rssi > -60 ? Icons.signal_cellular_alt
                   : rssi > -80 ? Icons.signal_cellular_alt_2_bar
                   : Icons.signal_cellular_alt_1_bar;
    final rssiColor = rssi > -60 ? Palette.success : rssi > -80 ? Palette.warn : Palette.danger;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Palette.dataBg,
        border: Border.all(color: isBss ? Palette.accent : Palette.border, width: isBss ? 2 : 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onDeviceTap(r),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: isBss ? Palette.accent.withOpacity(0.2) : Palette.card,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isBss ? Icons.settings_input_antenna : Icons.bluetooth,
                  color: isBss ? Palette.accent : Palette.textDim,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isBss ? Palette.accent : Palette.text,
                    )),
                  const SizedBox(height: 2),
                  Text(r.device.remoteId.str,
                    style: TextStyle(fontSize: 11, color: Palette.textDim, fontFamily: 'monospace')),
                ],
              )),
              const SizedBox(width: 8),
              Column(children: [
                Icon(rssiIcon, color: rssiColor, size: 16),
                Text('$rssi', style: TextStyle(fontSize: 10, color: rssiColor, fontFamily: 'monospace')),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
