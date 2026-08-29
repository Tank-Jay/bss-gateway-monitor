import 'package:flutter/material.dart';

import '../models/charger_adv.dart';
import '../theme/palette.dart';

/// Standard bordered panel used everywhere in the app.
class Panel extends StatelessWidget {
  final String? title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const Panel({
    super.key,
    this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: P.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: P.border),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    title!.toUpperCase(),
                    style: TextStyle(
                      color: P.textDim,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }
}

/// Label / value row with an optional accent on the value.
class DataRow2 extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;

  const DataRow2(this.label, this.value, {super.key, this.valueColor, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: P.textDim),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Text(label,
                style: TextStyle(color: P.textDim, fontSize: 13)),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? P.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact metric tile — big number, small caption.
class MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final Color color;
  final IconData? icon;

  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: P.cardAlt,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: P.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: P.textDim,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 3),
                Text(unit!,
                    style: TextStyle(color: P.textDim, fontSize: 11)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Horizontal SOC bar with the percentage written inside.
class SocBar extends StatelessWidget {
  final int? soc;
  final double height;
  final bool showLabel;

  const SocBar({super.key, required this.soc, this.height = 20, this.showLabel = true});

  @override
  Widget build(BuildContext context) {
    final pct = soc ?? 0;
    final color = soc == null ? P.textDim : P.socColor(pct.toDouble());
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Stack(
        children: [
          Container(height: height, color: P.cardAlt),
          FractionallySizedBox(
            widthFactor: (pct / 100).clamp(0.0, 1.0),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color.withValues(alpha: 0.65), color],
                ),
              ),
            ),
          ),
          if (showLabel)
            SizedBox(
              height: height,
              child: Center(
                child: Text(
                  soc == null ? 'No battery' : '$pct %',
                  style: TextStyle(
                    color: P.text,
                    fontSize: height * 0.55,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small rounded status chip.
class StatusChip extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final bool filled;

  const StatusChip(this.text,
      {super.key, required this.color, this.icon, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: filled ? P.bg : color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: filled ? P.bg : color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Colour + icon vocabulary for bay state, shared by every screen so a
/// "charging" bay looks identical in the fleet grid and the detail view.
({Color color, IconData icon}) bayStyle(BayState s) => switch (s) {
      BayState.empty => (color: P.textDim, icon: Icons.crop_square),
      BayState.idle => (color: P.info, icon: Icons.pause_circle_outline),
      BayState.charging => (color: P.success, icon: Icons.bolt),
      BayState.full => (color: P.accent, icon: Icons.check_circle_outline),
      BayState.fault => (color: P.danger, icon: Icons.error_outline),
      BayState.balancing => (color: P.warn, icon: Icons.tune),
      BayState.unknown => (color: P.textDim, icon: Icons.help_outline),
    };

Color chargerStateColor(ChargerState s) => switch (s) {
      ChargerState.idle => P.info,
      ChargerState.charging => P.success,
      ChargerState.complete => P.accent,
      ChargerState.fault => P.danger,
      ChargerState.maintenance => P.warn,
      ChargerState.unknown => P.textDim,
    };

/// Pulsing dot that signals live data is arriving.
class LiveDot extends StatefulWidget {
  final Color? color;
  const LiveDot({super.key, this.color});

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? P.success;
    return FadeTransition(
      opacity: _ctl.drive(Tween(begin: 0.25, end: 1.0)),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      ),
    );
  }
}

/// Full-panel empty state.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: P.textDim.withValues(alpha: 0.6)),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: P.text, fontSize: 16, fontWeight: FontWeight.w600)),
            if (message != null) ...[
              const SizedBox(height: 7),
              Text(message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: P.textDim, fontSize: 13, height: 1.4)),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}
