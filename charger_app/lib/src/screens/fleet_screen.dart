import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/fleet_scanner.dart';
import '../models/charger_adv.dart';
import '../theme/palette.dart';
import '../widgets/charger_tile.dart';
import '../widgets/common.dart';
import 'charger_screen.dart';
import 'settings_screen.dart';

/// The home screen: every charger in range, and every battery in them.
class FleetScreen extends StatefulWidget {
  final FleetScanner scanner;
  const FleetScreen({super.key, required this.scanner});

  @override
  State<FleetScreen> createState() => _FleetScreenState();
}

class _FleetScreenState extends State<FleetScreen> {
  final _searchCtl = TextEditingController();
  bool _searchOpen = false;

  FleetScanner get s => widget.scanner;

  @override
  void initState() {
    super.initState();
    // Kick the scan off as soon as the screen mounts; the fleet view is the
    // reason the app exists, so it should never need a button press to fill.
    WidgetsBinding.instance.addPostFrameCallback((_) => s.start());
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: P.bg,
          appBar: AppBar(
            backgroundColor: P.card,
            titleSpacing: 14,
            title: _searchOpen
                ? TextField(
                    controller: _searchCtl,
                    autofocus: true,
                    style: TextStyle(color: P.text, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Search charger name or ID',
                      hintStyle: TextStyle(color: P.textDim, fontSize: 14),
                      border: InputBorder.none,
                    ),
                    onChanged: s.setSearch,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Charger Fleet',
                          style: TextStyle(
                              color: P.text,
                              fontSize: 17,
                              fontWeight: FontWeight.w700)),
                      Text(
                        '${s.chargerCount} chargers · ${s.batteryCount} batteries',
                        style: TextStyle(color: P.textDim, fontSize: 11.5),
                      ),
                    ],
                  ),
            actions: [
              IconButton(
                tooltip: _searchOpen ? 'Close search' : 'Search',
                icon: Icon(_searchOpen ? Icons.close : Icons.search,
                    color: P.textDim),
                onPressed: () {
                  setState(() {
                    _searchOpen = !_searchOpen;
                    if (!_searchOpen) {
                      _searchCtl.clear();
                      s.setSearch('');
                    }
                  });
                },
              ),
              PopupMenuButton<FleetSort>(
                tooltip: 'Sort',
                icon: Icon(Icons.sort, color: P.textDim),
                color: P.card,
                initialValue: s.sort,
                onSelected: s.setSort,
                itemBuilder: (_) => FleetSort.values
                    .map((v) => PopupMenuItem(
                          value: v,
                          child: Text(v.label,
                              style: TextStyle(color: P.text, fontSize: 13.5)),
                        ))
                    .toList(),
              ),
              IconButton(
                tooltip: 'Settings',
                icon: Icon(Icons.settings_outlined, color: P.textDim),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => SettingsScreen(scanner: s)),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              if (s.demoMode) _demoBanner(),
              if (s.error != null) _errorBanner(s.error!),
              _summaryStrip(),
              _filterStrip(),
              Expanded(child: _grid()),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: s.scanning ? P.danger : P.accent,
            foregroundColor: P.bg,
            icon: Icon(s.scanning ? Icons.stop : Icons.radar),
            label: Text(s.scanning ? 'Stop scan' : 'Scan'),
            onPressed: () => s.scanning ? s.stop() : s.start(),
          ),
        );
      },
    );
  }

  // ── Header pieces ──

  Widget _demoBanner() => Container(
        width: double.infinity,
        color: P.warn.withValues(alpha: 0.18),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.science_outlined, size: 16, color: P.warn),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Demo mode — simulated fleet, no real hardware',
                style: TextStyle(
                    color: P.warn, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () {
                s.stopDemo();
                s.start();
              },
              child: Text('Exit', style: TextStyle(color: P.warn)),
            ),
          ],
        ),
      );

  Widget _errorBanner(String msg) => Container(
        width: double.infinity,
        color: P.danger.withValues(alpha: 0.16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 16, color: P.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(msg,
                  style: TextStyle(color: P.danger, fontSize: 12)),
            ),
            TextButton(
              onPressed: s.start,
              child: Text('Retry', style: TextStyle(color: P.danger)),
            ),
          ],
        ),
      );

  Widget _summaryStrip() {
    final avg = s.fleetAverageSoc;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          _stat('Batteries', '${s.batteryCount}', P.accent, Icons.battery_full),
          _stat('Charging', '${s.chargingCount}', P.success, Icons.bolt),
          _stat('Full', '${s.fullCount}', P.info, Icons.check_circle_outline),
          _stat('Faults', '${s.faultCount}', s.faultCount > 0 ? P.danger : P.textDim,
              Icons.warning_amber_rounded),
          _stat('Avg SOC', avg == null ? '--' : '${avg.round()} %',
              avg == null ? P.textDim : P.socColor(avg), Icons.speed),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color, IconData icon) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: SizedBox(
          width: 108,
          child: MetricTile(label: label, value: value, color: color, icon: icon),
        ),
      );

  Widget _filterStrip() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          if (s.scanning || s.demoMode) ...[
            const LiveDot(),
            const SizedBox(width: 7),
            Text(s.demoMode ? 'Simulating' : 'Scanning',
                style: TextStyle(color: P.textDim, fontSize: 12)),
          ] else
            Text('Idle', style: TextStyle(color: P.textDim, fontSize: 12)),
          const Spacer(),
          FilterChip(
            label: const Text('Faults only'),
            labelStyle: TextStyle(
              color: s.showOnlyFaults ? P.bg : P.textDim,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
            selected: s.showOnlyFaults,
            showCheckmark: false,
            backgroundColor: P.cardAlt,
            selectedColor: P.danger,
            side: BorderSide(color: P.border),
            onSelected: s.setFaultFilter,
          ),
        ],
      ),
    );
  }

  // ── Grid ──

  Widget _grid() {
    final items = s.visible;

    if (items.isEmpty) {
      return EmptyState(
        icon: s.scanning ? Icons.radar : Icons.bluetooth_disabled,
        title: s.scanning ? 'Looking for chargers…' : 'No chargers found',
        message: s.scanning
            ? 'Chargers broadcast once a second. Anything in range will appear here on its own.'
            : 'Start a scan, or try demo mode to explore the app without hardware.',
        action: s.scanning
            ? null
            : Wrap(
                spacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: s.start,
                    icon: const Icon(Icons.radar, size: 18),
                    label: const Text('Scan'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => s.startDemo(),
                    icon: const Icon(Icons.science_outlined, size: 18),
                    label: const Text('Demo mode'),
                  ),
                ],
              ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // One column on a phone, more on tablets and landscape — a 50-unit
        // fleet is much easier to scan when the tiles tile.
        final cols = (constraints.maxWidth / 340).floor().clamp(1, 4);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: 132,
          ),
          itemBuilder: (context, i) {
            final c = items[i];
            return ChargerTile(
              charger: c,
              onTap: () => _openCharger(c),
            );
          },
        );
      },
    );
  }

  Future<void> _openCharger(ChargerSnapshot c) async {
    if (s.demoMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Demo chargers have no radio — exit demo mode to connect to real hardware.'),
          backgroundColor: P.warn,
        ),
      );
      return;
    }

    // Pause the fleet scan for the duration of the session: Android will
    // happily scan and connect at once, but the scan starves the connection
    // of radio time and 1 Hz notifications start arriving late.
    final wasScanning = s.scanning;
    await s.stop();

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChargerScreen(
          device: BluetoothDevice.fromId(c.deviceId),
          snapshot: c,
        ),
      ),
    );

    if (wasScanning && mounted) await s.start();
  }
}
