import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'src/ble/fleet_scanner.dart';
import 'src/screens/fleet_screen.dart';
import 'src/theme/palette.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep the plugin quiet in release; verbose only helps on the bench.
  FlutterBluePlus.setLogLevel(LogLevel.none, color: false);
  await loadSavedTheme();
  runApp(const ChargerApp());
}

class ChargerApp extends StatefulWidget {
  const ChargerApp({super.key});

  @override
  State<ChargerApp> createState() => _ChargerAppState();
}

class _ChargerAppState extends State<ChargerApp> {
  // One scanner for the whole app lifetime — the fleet should not reset every
  // time the user navigates back to the home screen.
  final _scanner = FleetScanner();

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'BSS Charger Monitor',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          home: FleetScreen(scanner: _scanner),
        );
      },
    );
  }
}
