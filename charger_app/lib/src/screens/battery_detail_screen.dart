import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../ble/charger_ble_service.dart';
import '../models/charger_adv.dart';
import '../models/log_entry.dart';
import '../theme/palette.dart';
import '../widgets/common.dart';

/// Per-cell BMS view for one battery, streamed at 1 Hz from the connected
/// charger. This is the deepest level of the app — everything the pack knows.
class BatteryDetailScreen extends StatefulWidget {
  final ChargerBleService service;
  final int bay;

  const BatteryDetailScreen({super.key, required this.service, required this.bay});

  @override
  State<BatteryDetailScreen> createState() => _BatteryDetailScreenState();
}

class _BatteryDetailScreenState extends State<BatteryDetailScreen> {
  ChargerBleService get svc => widget.service;

  @override
  void initState() {
    super.initState();
    // The firmware streams whichever bay was last selected; make sure that is
    // the one this screen is about.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => svc.selectBay(widget.bay));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: svc,
      builder: (context, _) {
        final d = svc.detail;
        final accent = widget.bay == 1 ? P.bayA : P.bayB;

        return Scaffold(
          backgroundColor: P.bg,
          appBar: AppBar(
            backgroundColor: P.card,
            title: Text('Bay ${widget.bay == 1 ? 'A' : 'B'} battery',
                style: TextStyle(
                    color: P.text, fontSize: 16.5, fontWeight: FontWeight.w700)),
            actions: [
              // Jump between the two bays without going back a screen.
              IconButton(
                tooltip: 'Other bay',
                icon: Icon(Icons.swap_horiz, color: P.textDim),
                onPressed: () {
                  final other = widget.bay == 1 ? 2 : 1;
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          BatteryDetailScreen(service: svc, bay: other),
                    ),
                  );
                },
              ),
            ],
          ),
          body: d == null
              ? Center(child: CircularProgressIndicator(color: accent))
              : (d['present'] != true
                  ? const EmptyState(
                      icon: Icons.battery_unknown,
                      title: 'No battery in this bay',
                      message: 'Insert a pack to see its cell-level detail.',
                    )
                  : _content(d)),
        );
      },
    );
  }

  Widget _content(Map<String, dynamic> d) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _overview(d),
        _trendChart(),
        _cellPanel(d),
        _tempPanel(d),
      ],
    );
  }

  // ── Overview ──

  Widget _overview(Map<String, dynamic> d) {
    final state = bayStateFromInt((d['state'] as num?)?.toInt() ?? -1);
    final style = bayStyle(state);
    final faults = decodeFaults((d['fault'] as num?)?.toInt() ?? 0);

    return Panel(
      title: 'Pack ${d['pack_id'] ?? ''}',
      trailing: StatusChip(state.label, color: style.color, icon: style.icon),
      child: Column(
        children: [
          SocBar(soc: (d['soc'] as num?)?.round(), height: 28),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: MetricTile(label: 'Pack V', value: _f(d['pack_v'], 1), unit: 'V', color: P.volt, icon: Icons.electric_bolt)),
            const SizedBox(width: 8),
            Expanded(child: MetricTile(label: 'Pack A', value: _f(d['pack_i'], 1), unit: 'A', color: P.curr, icon: Icons.trending_up)),
            const SizedBox(width: 8),
            Expanded(child: MetricTile(label: 'SOH', value: _f(d['soh'], 0), unit: '%', color: P.soh, icon: Icons.favorite_outline)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: MetricTile(label: 'Capacity', value: _f(d['avail_cap'], 1), unit: 'Ah', color: P.cap, icon: Icons.battery_std)),
            const SizedBox(width: 8),
            Expanded(child: MetricTile(label: 'Cycles', value: _f(d['cycles'], 0), color: P.cycle, icon: Icons.loop)),
            const SizedBox(width: 8),
            Expanded(child: MetricTile(label: 'Delta', value: _delta(d), unit: 'mV', color: _deltaColor(d), icon: Icons.compare_arrows)),
          ]),
          const SizedBox(height: 10),
          DataRow2('Lowest cell', '${d['min_cv'] ?? '--'} mV'),
          DataRow2('Highest cell', '${d['max_cv'] ?? '--'} mV'),
          DataRow2('Output relay', d['relay'] == 1 ? 'Closed' : 'Open',
              valueColor: d['relay'] == 1 ? P.success : P.textDim),
          if (faults.isNotEmpty)
            DataRow2('Faults', faults.join(', '), valueColor: P.danger),
        ],
      ),
    );
  }

  /// Cell imbalance is the single best early warning of a failing pack, so it
  /// gets promoted to a headline metric rather than being left to the reader.
  String _delta(Map<String, dynamic> d) {
    final lo = d['min_cv'], hi = d['max_cv'];
    if (lo is! num || hi is! num) return '--';
    return (hi - lo).toStringAsFixed(0);
  }

  Color _deltaColor(Map<String, dynamic> d) {
    final lo = d['min_cv'], hi = d['max_cv'];
    if (lo is! num || hi is! num) return P.textDim;
    final delta = hi - lo;
    if (delta >= 120) return P.danger;
    if (delta >= 60) return P.warn;
    return P.success;
  }

  // ── Trend chart ──

  Widget _trendChart() {
    final hist = svc.historyFor(widget.bay);
    if (hist.length < 2) {
      return Panel(
        title: 'Trend',
        child: SizedBox(
          height: 90,
          child: Center(
            child: Text('Collecting samples…',
                style: TextStyle(color: P.textDim, fontSize: 13)),
          ),
        ),
      );
    }

    final t0 = hist.first.t.millisecondsSinceEpoch.toDouble();
    List<FlSpot> spots(double Function(BaySample) pick) => [
          for (final s in hist)
            FlSpot((s.t.millisecondsSinceEpoch - t0) / 1000.0, pick(s)),
        ];

    return Panel(
      title: 'Trend · last ${hist.length}s',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        _legend('SOC %', P.soc),
        const SizedBox(width: 10),
        _legend('Current A', P.curr),
      ]),
      child: SizedBox(
        height: 160,
        child: LineChart(
          LineChartData(
            minY: 0,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: P.border, strokeWidth: 0.6),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  getTitlesWidget: (v, _) => Text(
                    v.toStringAsFixed(0),
                    style: TextStyle(color: P.textDim, fontSize: 9),
                  ),
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: [
              LineChartBarData(
                spots: spots((s) => s.soc),
                color: P.soc,
                barWidth: 2,
                dotData: const FlDotData(show: false),
                isCurved: true,
              ),
              LineChartBarData(
                spots: spots((s) => s.amps),
                color: P.curr,
                barWidth: 2,
                dotData: const FlDotData(show: false),
                isCurved: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legend(String label, Color c) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 9, height: 3, color: c),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: P.textDim, fontSize: 10)),
        ],
      );

  // ── Cells ──

  Widget _cellPanel(Map<String, dynamic> d) {
    final raw = d['cells'];
    if (raw is! List || raw.isEmpty) {
      return const Panel(title: 'Cells', child: Text('No cell data'));
    }
    final cells = raw.whereType<num>().map((e) => e.toInt()).toList();
    final lo = cells.reduce((a, b) => a < b ? a : b);
    final hi = cells.reduce((a, b) => a > b ? a : b);
    final span = (hi - lo) == 0 ? 1 : (hi - lo);

    return Panel(
      title: '${cells.length} cells · ${hi - lo} mV spread',
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < cells.length; i++)
            _cellChip(i + 1, cells[i], lo, hi, span),
        ],
      ),
    );
  }

  Widget _cellChip(int index, int mv, int lo, int hi, int span) {
    // Colour each cell by where it sits between the pack min and max, so an
    // outlier is visible at a glance without reading any numbers.
    final t = (mv - lo) / span;
    final color = mv == lo
        ? P.danger
        : (mv == hi ? P.info : Color.lerp(P.warn, P.success, t)!);

    return Container(
      width: 68,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      decoration: BoxDecoration(
        color: P.cardAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('C$index',
              style: TextStyle(color: P.textDim, fontSize: 9.5)),
          const SizedBox(height: 2),
          Text(
            '$mv',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  // ── Temperatures ──

  Widget _tempPanel(Map<String, dynamic> d) {
    final raw = d['temps'];
    if (raw is! List || raw.isEmpty) {
      return const Panel(title: 'Temperatures', child: Text('No probe data'));
    }
    final temps = raw.whereType<num>().map((e) => e.toDouble()).toList();

    return Panel(
      title: 'Temperature probes',
      child: Row(
        children: [
          for (var i = 0; i < temps.length; i++) ...[
            Expanded(
              child: MetricTile(
                label: 'T${i + 1}',
                value: temps[i].toStringAsFixed(1),
                unit: '°C',
                color: temps[i] >= 55
                    ? P.danger
                    : (temps[i] >= 45 ? P.warn : P.temp),
                icon: Icons.thermostat,
              ),
            ),
            if (i != temps.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

String _f(dynamic v, int digits) =>
    v is num ? v.toDouble().toStringAsFixed(digits) : '--';

