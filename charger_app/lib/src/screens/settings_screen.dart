import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../ble/ble_uuids.dart';
import '../ble/fleet_scanner.dart';
import '../models/charger_adv.dart';
import '../theme/palette.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  final FleetScanner scanner;
  const SettingsScreen({super.key, required this.scanner});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = '${p.version} (${p.buildNumber})');
    });
  }

  FleetScanner get s => widget.scanner;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(
        backgroundColor: P.card,
        title: Text('Settings',
            style: TextStyle(
                color: P.text, fontSize: 16.5, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Panel(
            title: 'Appearance',
            child: Row(
              children: [
                Expanded(
                  child: Text('Dark theme',
                      style: TextStyle(color: P.text, fontSize: 14)),
                ),
                Switch(
                  value: themeModeNotifier.value == ThemeMode.dark,
                  onChanged: (v) async {
                    await setTheme(v ? ThemeMode.dark : ThemeMode.light);
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          ),
          Panel(
            title: 'Fleet',
            child: Column(
              children: [
                DataRow2('Chargers in range', '${s.chargerCount}'),
                DataRow2('Batteries detected', '${s.batteryCount}'),
                DataRow2('Charging now', '${s.chargingCount}'),
                DataRow2('Faulted chargers', '${s.faultCount}',
                    valueColor: s.faultCount > 0 ? P.danger : P.success),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          s.restart();
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.refresh, size: 17),
                        label: const Text('Clear and rescan'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: P.accent,
                            side: BorderSide(color: P.border)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          s.demoMode ? s.stopDemo() : s.startDemo();
                          if (!s.demoMode) s.start();
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.science_outlined, size: 17),
                        label: Text(s.demoMode ? 'Exit demo' : 'Demo mode'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: P.warn,
                            side: BorderSide(color: P.border)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Panel(
            title: 'Export',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Writes a CSV snapshot of every charger and battery currently in range.',
                  style: TextStyle(color: P.textDim, fontSize: 12.5, height: 1.4),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _exportCsv,
                    icon: const Icon(Icons.ios_share, size: 17),
                    label: const Text('Export fleet CSV'),
                    style: FilledButton.styleFrom(
                        backgroundColor: P.accent, foregroundColor: P.bg),
                  ),
                ),
              ],
            ),
          ),
          Panel(
            title: 'About',
            child: Column(
              children: [
                DataRow2('App version', _version.isEmpty ? '--' : _version),
                const DataRow2('Protocol version', 'v${ChargerUuids.protoVer}'),
                const DataRow2('Device prefix', ChargerUuids.namePrefix),
                const DataRow2('Bays per charger', '2'),
                const SizedBox(height: 8),
                Text(
                  'Fleet data is read straight from charger advertisements, so every unit in range stays live without connecting. Tap a charger for per-cell BMS detail and control.',
                  style: TextStyle(color: P.textDim, fontSize: 12, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv() async {
    final rows = <String>[
      'charger_id,name,device_id,charger_state,faults,rssi_dbm,seq,bay,present,bay_state,soc_pct,volts,temp_c',
    ];

    for (final c in s.all) {
      for (final b in c.bays) {
        rows.add([
          c.chargerId,
          c.name,
          c.deviceId,
          c.state.label,
          '"${c.faults.join('; ')}"',
          c.rssi,
          c.seq,
          b.label,
          b.present,
          b.state.label,
          b.soc ?? '',
          b.present ? b.volts.toStringAsFixed(1) : '',
          b.tempC ?? '',
        ].join(','));
      }
    }

    try {
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File('${dir.path}/bss_fleet_$stamp.csv');
      await file.writeAsString(rows.join('\n'));
      await Share.shareXFiles([XFile(file.path)],
          subject: 'BSS charger fleet snapshot');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: P.danger),
      );
    }
  }
}
