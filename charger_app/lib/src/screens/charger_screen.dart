import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/charger_ble_service.dart';
import '../models/charger_adv.dart';
import '../theme/palette.dart';
import '../widgets/common.dart';
import 'battery_detail_screen.dart';
import 'log_screen.dart';

/// The connected view of one charger: both bays live at 1 Hz, plus control.
class ChargerScreen extends StatefulWidget {
  final BluetoothDevice device;
  final ChargerSnapshot snapshot;

  const ChargerScreen({
    super.key,
    required this.device,
    required this.snapshot,
  });

  @override
  State<ChargerScreen> createState() => _ChargerScreenState();
}

class _ChargerScreenState extends State<ChargerScreen> {
  final svc = ChargerBleService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => svc.connect(widget.device));
  }

  @override
  void dispose() {
    svc.disconnect();
    svc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: svc,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: P.bg,
          appBar: AppBar(
            backgroundColor: P.card,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.snapshot.name,
                    style: TextStyle(
                        color: P.text, fontSize: 16.5, fontWeight: FontWeight.w700)),
                Row(
                  children: [
                    if (svc.isConnected) ...[
                      const LiveDot(),
                      const SizedBox(width: 6),
                    ],
                    Text(_linkLabel,
                        style: TextStyle(color: _linkColor, fontSize: 11.5)),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'BLE log',
                icon: Icon(Icons.terminal, color: P.textDim),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => LogScreen(service: svc)),
                ),
              ),
              IconButton(
                tooltip: svc.isConnected ? 'Disconnect' : 'Reconnect',
                icon: Icon(
                  svc.isConnected ? Icons.link_off : Icons.link,
                  color: svc.isConnected ? P.danger : P.accent,
                ),
                onPressed: () => svc.isConnected
                    ? svc.disconnect()
                    : svc.connect(widget.device),
              ),
            ],
          ),
          body: _body(),
        );
      },
    );
  }

  String get _linkLabel => switch (svc.state) {
        LinkState.connected => 'Connected · ${svc.rxCount} packets',
        LinkState.connecting => 'Connecting…',
        LinkState.disconnected => 'Disconnected',
      };

  Color get _linkColor => switch (svc.state) {
        LinkState.connected => P.success,
        LinkState.connecting => P.warn,
        LinkState.disconnected => P.danger,
      };

  Widget _body() {
    if (svc.state == LinkState.connecting) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: P.accent),
            const SizedBox(height: 18),
            Text('Connecting to ${widget.snapshot.name}…',
                style: TextStyle(color: P.textDim, fontSize: 13.5)),
          ],
        ),
      );
    }

    if (svc.state == LinkState.disconnected) {
      return EmptyState(
        icon: Icons.link_off,
        title: 'Not connected',
        message:
            'The charger is still broadcasting its summary to the fleet screen. Reconnect for per-cell detail and control.',
        action: FilledButton.icon(
          onPressed: () => svc.connect(widget.device),
          icon: const Icon(Icons.link, size: 18),
          label: const Text('Reconnect'),
        ),
      );
    }

    final bays = _bayList;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _chargerPanel(),
        for (final b in bays) _bayPanel(b),
        _controlPanel(),
      ],
    );
  }

  List<Map<String, dynamic>> get _bayList {
    final raw = svc.summary?['bays'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  // ── Panels ──

  Widget _chargerPanel() {
    final info = svc.info;
    final state = chargerStateFromInt((svc.summary?['state'] as num?)?.toInt() ?? -1);
    final faults = decodeFaults((svc.summary?['fault'] as num?)?.toInt() ?? 0);

    return Panel(
      title: 'Charger',
      trailing: StatusChip(state.label, color: chargerStateColor(state)),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  label: 'Mains',
                  value: info?['mains_v'] == null
                      ? '--'
                      : (info!['mains_v'] as num).toStringAsFixed(1),
                  unit: 'V',
                  color: P.volt,
                  icon: Icons.power,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricTile(
                  label: 'Bays used',
                  value:
                      '${_bayList.where((b) => b['present'] == true).length}/2',
                  color: P.accent,
                  icon: Icons.battery_charging_full,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricTile(
                  label: 'Uptime',
                  value: _uptime(info?['uptime_s']),
                  color: P.cycle,
                  icon: Icons.schedule,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (info != null) ...[
            DataRow2('Charger ID', '${info['charger_id'] ?? '--'}'),
            DataRow2('Firmware', '${info['fw_ver'] ?? '--'}  (${info['fw_date'] ?? '--'})'),
            DataRow2('MAC', '${info['mac'] ?? '--'}'),
            DataRow2('Wi-Fi', info['wifi'] == 'yes'
                ? '${info['wifi_ssid']}  ${info['wifi_rssi']} dBm'
                : 'Not connected',
                valueColor: info['wifi'] == 'yes' ? P.success : P.textDim),
          ],
          if (faults.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: P.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: P.danger.withValues(alpha: 0.45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.warning_amber_rounded, size: 15, color: P.danger),
                    const SizedBox(width: 6),
                    Text('Active faults',
                        style: TextStyle(
                            color: P.danger,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 5),
                  ...faults.map((f) => Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('• $f',
                            style: TextStyle(color: P.text, fontSize: 12.5)),
                      )),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bayPanel(Map<String, dynamic> b) {
    final bay = (b['bay'] as num?)?.toInt() ?? 0;
    final present = b['present'] == true;
    final state = bayStateFromInt((b['state'] as num?)?.toInt() ?? -1);
    final style = bayStyle(state);
    final accent = bay == 1 ? P.bayA : P.bayB;

    return Panel(
      title: 'Bay ${bay == 1 ? 'A' : 'B'}',
      trailing: StatusChip(state.label, color: style.color, icon: style.icon),
      child: !present
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.battery_unknown, size: 18, color: P.textDim),
                  const SizedBox(width: 8),
                  Text('No battery in this bay',
                      style: TextStyle(color: P.textDim, fontSize: 13)),
                ],
              ),
            )
          : Column(
              children: [
                SocBar(soc: (b['soc'] as num?)?.round(), height: 26),
                const SizedBox(height: 11),
                Row(
                  children: [
                    Expanded(
                      child: MetricTile(
                        label: 'Voltage',
                        value: _fmt(b['v'], 1),
                        unit: 'V',
                        color: P.volt,
                        icon: Icons.electric_bolt,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MetricTile(
                        label: 'Current',
                        value: _fmt(b['i'], 1),
                        unit: 'A',
                        color: P.curr,
                        icon: Icons.trending_up,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MetricTile(
                        label: 'Temp',
                        value: _fmt(b['temp'], 1),
                        unit: '°C',
                        color: ((b['temp'] as num?)?.toDouble() ?? 0) >= 55
                            ? P.danger
                            : P.temp,
                        icon: Icons.thermostat,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DataRow2('Pack ID', '${b['pack_id'] ?? '--'}'),
                DataRow2('State of health', '${b['soh'] ?? '--'} %',
                    valueColor: P.soh),
                DataRow2('Output relay', b['relay'] == 1 ? 'Closed' : 'Open',
                    valueColor: b['relay'] == 1 ? P.success : P.textDim),
                DataRow2('Time to full', _eta(b['eta_min'])),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: state == BayState.charging
                            ? () => svc.stopBay(bay)
                            : () => svc.startBay(bay),
                        icon: Icon(
                            state == BayState.charging
                                ? Icons.pause
                                : Icons.play_arrow,
                            size: 17),
                        label: Text(
                            state == BayState.charging ? 'Stop' : 'Start'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              state == BayState.charging ? P.warn : P.success,
                          side: BorderSide(color: P.border),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => svc.unlockBay(bay),
                        icon: const Icon(Icons.lock_open, size: 17),
                        label: const Text('Unlock'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: P.info,
                          side: BorderSide(color: P.border),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          svc.selectBay(bay);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  BatteryDetailScreen(service: svc, bay: bay),
                            ),
                          );
                        },
                        icon: const Icon(Icons.insights, size: 17),
                        label: const Text('Detail'),
                        style: FilledButton.styleFrom(
                            backgroundColor: accent, foregroundColor: P.bg),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _controlPanel() {
    return Panel(
      title: 'Control',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: svc.clearFaults,
            icon: const Icon(Icons.cleaning_services_outlined, size: 17),
            label: const Text('Clear faults'),
            style: OutlinedButton.styleFrom(
                foregroundColor: P.warn, side: BorderSide(color: P.border)),
          ),
          OutlinedButton.icon(
            onPressed: () => _confirm(
              'Reboot charger?',
              'Charging stops for about 10 seconds while the unit restarts.',
              svc.reboot,
            ),
            icon: const Icon(Icons.restart_alt, size: 17),
            label: const Text('Reboot'),
            style: OutlinedButton.styleFrom(
                foregroundColor: P.info, side: BorderSide(color: P.border)),
          ),
          OutlinedButton.icon(
            onPressed: () => _confirm(
              'Factory reset?',
              'Wipes charger ID, Wi-Fi credentials and charge limits. This cannot be undone.',
              svc.factoryReset,
              destructive: true,
            ),
            icon: const Icon(Icons.warning_amber_rounded, size: 17),
            label: const Text('Factory reset'),
            style: OutlinedButton.styleFrom(
                foregroundColor: P.danger, side: BorderSide(color: P.border)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(String title, String body, VoidCallback onOk,
      {bool destructive = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: P.card,
        title: Text(title, style: TextStyle(color: P.text, fontSize: 17)),
        content: Text(body, style: TextStyle(color: P.textDim, fontSize: 13.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: P.textDim)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: destructive ? P.danger : P.accent,
                foregroundColor: P.bg),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok == true) onOk();
  }
}

// ── Small formatters shared by this screen ──

String _fmt(dynamic v, int digits) =>
    v is num ? v.toDouble().toStringAsFixed(digits) : '--';

String _uptime(dynamic seconds) {
  if (seconds is! num) return '--';
  final s = seconds.toInt();
  final d = s ~/ 86400, h = (s % 86400) ~/ 3600, m = (s % 3600) ~/ 60;
  if (d > 0) return '${d}d ${h}h';
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

String _eta(dynamic minutes) {
  if (minutes is! num) return '--';
  final m = minutes.toInt();
  if (m <= 0) return 'Complete';
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${m % 60} min';
}


