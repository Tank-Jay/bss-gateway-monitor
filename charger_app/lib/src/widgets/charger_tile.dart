import 'package:flutter/material.dart';

import '../ble/fleet_scanner.dart';
import '../models/charger_adv.dart';
import '../theme/palette.dart';
import 'common.dart';

/// One charger in the fleet grid: the unit header plus both of its bays.
///
/// Everything drawn here comes from the advertisement — no connection — which
/// is why the whole fleet can render at once.
class ChargerTile extends StatelessWidget {
  final ChargerSnapshot charger;
  final VoidCallback onTap;

  const ChargerTile({super.key, required this.charger, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final stale = charger.isStale(DateTime.now(), kStaleAfter);
    final stateColor = chargerStateColor(charger.state);

    return Opacity(
      opacity: stale ? 0.45 : 1.0,
      child: Material(
        color: P.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: charger.hasFault ? P.danger.withValues(alpha: 0.65) : P.border,
                width: charger.hasFault ? 1.4 : 1,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _header(stale, stateColor),
                const SizedBox(height: 9),
                _BayRow(bay: charger.bays[0], accent: P.bayA),
                const SizedBox(height: 7),
                _BayRow(bay: charger.bays[1], accent: P.bayB),
                if (charger.hasFault && charger.faults.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 13, color: P.danger),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          charger.faults.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: P.danger,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(bool stale, Color stateColor) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: stateColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: stateColor.withValues(alpha: 0.45)),
          ),
          child: Text(
            '${charger.chargerId}',
            style: TextStyle(
              color: stateColor,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                charger.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: P.text, fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 1),
              Text(
                stale ? 'No signal' : charger.state.label,
                style: TextStyle(
                    color: stale ? P.warn : stateColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        _RssiBars(rssi: charger.rssi, dimmed: stale),
      ],
    );
  }
}

/// One bay line: label, state icon, SOC bar, voltage and temperature.
class _BayRow extends StatelessWidget {
  final BaySnapshot bay;
  final Color accent;

  const _BayRow({required this.bay, required this.accent});

  @override
  Widget build(BuildContext context) {
    final style = bayStyle(bay.state);

    if (!bay.present) {
      return Row(
        children: [
          _badge(accent.withValues(alpha: 0.35)),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: P.cardAlt,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                    color: P.border, style: BorderStyle.solid, width: 1),
              ),
              child: Text('Empty',
                  style: TextStyle(color: P.textDim, fontSize: 10.5)),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        _badge(accent),
        const SizedBox(width: 8),
        Expanded(child: SocBar(soc: bay.soc, height: 18)),
        const SizedBox(width: 8),
        Icon(style.icon, size: 14, color: style.color),
        const SizedBox(width: 6),
        SizedBox(
          width: 44,
          child: Text(
            bay.volts > 0 ? bay.volts.toStringAsFixed(0) : '--',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: P.volt,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Text('V', style: TextStyle(color: P.textDim, fontSize: 9)),
        const SizedBox(width: 7),
        SizedBox(
          width: 26,
          child: Text(
            bay.tempC != null ? '${bay.tempC}' : '--',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: (bay.tempC ?? 0) >= 55 ? P.danger : P.temp,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Text('°', style: TextStyle(color: P.textDim, fontSize: 9)),
      ],
    );
  }

  Widget _badge(Color c) => Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: c.withValues(alpha: 0.5)),
        ),
        child: Text(bay.label,
            style: TextStyle(
                color: c, fontSize: 10, fontWeight: FontWeight.w800)),
      );
}

/// Four-step signal indicator derived from RSSI.
class _RssiBars extends StatelessWidget {
  final int rssi;
  final bool dimmed;

  const _RssiBars({required this.rssi, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    // -55 or better is right next to you; below -90 is barely reachable.
    final level = switch (rssi) {
      >= -55 => 4,
      >= -70 => 3,
      >= -82 => 2,
      >= -92 => 1,
      _ => 0,
    };
    final color = dimmed
        ? P.textDim
        : (level >= 3 ? P.success : (level == 2 ? P.warn : P.danger));

    return Tooltip(
      message: '$rssi dBm',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (i) {
          return Container(
            width: 3,
            height: 5.0 + i * 3,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: i < level ? color : P.border,
              borderRadius: BorderRadius.circular(1.5),
            ),
          );
        }),
      ),
    );
  }
}
