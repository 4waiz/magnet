/// Reusable Magnet Rush UI primitives.
///
/// Hand-built on `widgets` rather than Material, so nothing carries Material's
/// default chrome — but the shapes are ordinary: rounded rectangles, solid
/// fills, flat colour. No chamfers, no neon edges, no glow.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/mr_theme.dart';

/// A rounded surface panel.
class MrPanel extends StatelessWidget {
  const MrPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MrSpace.md),
    this.colour = MrColors.surface,
    this.radius = MrRadius.md,
    this.border,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color colour;
  final double radius;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(radius),
        border: border == null ? null : Border.all(color: border!, width: 1),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// The primary action button: a solid rounded rectangle with a press response.
class MrButton extends StatefulWidget {
  const MrButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.enabled = true,
    this.icon,
    this.width,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool enabled;
  final Widget? icon;
  final double? width;
  final bool compact;

  @override
  State<MrButton> createState() => _MrButtonState();
}

class _MrButtonState extends State<MrButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 110),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled && widget.onPressed != null;
    final base = widget.primary ? MrColors.primary : MrColors.surfaceHigh;
    final pressed = widget.primary ? MrColors.primaryDark : MrColors.surface;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: on ? (_) => _c.forward() : null,
      onTapUp: on
          ? (_) {
              _c.reverse();
              widget.onPressed!();
            }
          : null,
      onTapCancel: on ? () => _c.reverse() : null,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          return Transform.scale(
            scale: 1 - t * 0.03,
            child: Opacity(
              opacity: on ? 1.0 : 0.4,
              child: SizedBox(
                width: widget.width,
                child: MrPanel(
                  colour: Color.lerp(base, pressed, t)!,
                  radius: widget.compact ? MrRadius.sm : MrRadius.md,
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.compact ? MrSpace.sm : MrSpace.lg,
                    vertical: widget.compact ? 10 : 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        widget.icon!,
                        const SizedBox(width: MrSpace.sm),
                      ],
                      // Flexible so a long label in a narrow button (the three
                      // quality presets share a row on a 360 pt screen) shrinks
                      // instead of overflowing.
                      Flexible(
                        child: Text(
                          widget.label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: widget.compact
                              ? MrType.button.copyWith(fontSize: 14)
                              : MrType.button,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A plain horizontal rule with an optional centred label.
class MrDivider extends StatelessWidget {
  const MrDivider({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    const line = Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(color: MrColors.divider),
        child: SizedBox(height: 1, width: double.infinity),
      ),
    );
    if (label == null) return const Row(children: [line]);
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: MrSpace.md),
          child: Text(label!, style: MrType.caption),
        ),
        line,
      ],
    );
  }
}

/// A labelled statistic.
class MrStat extends StatelessWidget {
  const MrStat({
    super.key,
    required this.label,
    required this.value,
    this.colour = MrColors.textPrimary,
    this.align = CrossAxisAlignment.start,
  });

  final String label;
  final String value;
  final Color colour;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: MrType.caption),
        const SizedBox(height: 3),
        Text(value, style: MrType.value.copyWith(color: colour)),
      ],
    );
  }
}

/// A smooth rounded progress bar.
class MrProgressBar extends StatelessWidget {
  const MrProgressBar({
    super.key,
    required this.value,
    this.colour = MrColors.primary,
    this.height = 6,
    this.track = MrColors.divider,
  });

  final double value;
  final Color colour;
  final double height;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: track),
              child: const SizedBox.expand(),
            ),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(color: colour),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A circular charge indicator for the HUD.
class MrChargeDial extends StatelessWidget {
  const MrChargeDial({
    super.key,
    required this.charge,
    required this.perfect,
    required this.ventPressure,
    this.size = 52,
  });

  final double charge;
  final bool perfect;
  final double ventPressure;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DialPainter(charge, perfect, ventPressure)),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter(this.charge, this.perfect, this.vent);
  final double charge;
  final bool perfect;
  final double vent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 3;
    const start = -math.pi / 2;

    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      start,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = MrColors.divider,
    );

    // The perfect band, marked so the window is visible without explanation.
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      start + math.pi * 2 * 0.85,
      math.pi * 2 * 0.15,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = MrColors.reward.withValues(alpha: 0.45),
    );

    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      start,
      math.pi * 2 * charge.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = perfect ? MrColors.reward : MrColors.primary,
    );

    if (vent > 0.01) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - 7),
        start,
        math.pi * 2 * vent,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..color = MrColors.danger,
      );
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.charge != charge || old.perfect != perfect || old.vent != vent;
}

/// A star row for the results screen, animating in one at a time.
class MrStars extends StatelessWidget {
  const MrStars({
    super.key,
    required this.stars,
    required this.reveal,
    this.size = 40,
  });
  final int stars;
  final double reveal;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final t = ((reveal - i * 0.28) / 0.4).clamp(0.0, 1.0);
        final earned = i < stars;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Transform.scale(
            scale: earned ? 0.7 + t * 0.45 : 0.9,
            child: Opacity(
              opacity: earned ? t : 0.25,
              child: CustomPaint(
                size: Size(size, size),
                painter: _StarPainter(
                  earned ? MrColors.reward : MrColors.textMuted,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.colour);
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final rr = i.isEven ? r : r * 0.45;
      final p = Offset(c.dx + math.cos(a) * rr, c.dy + math.sin(a) * rr);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.colour != colour;
}

/// A "coming later" tile for home-screen features that are not built yet.
class MrLockedTile extends StatelessWidget {
  const MrLockedTile({super.key, required this.label, required this.note});
  final String label;
  final String note;

  @override
  Widget build(BuildContext context) {
    return MrPanel(
      colour: MrColors.surfaceLow,
      radius: MrRadius.sm,
      padding: const EdgeInsets.symmetric(
        horizontal: MrSpace.md,
        vertical: MrSpace.sm + 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: MrType.label.copyWith(color: MrColors.textMuted)),
          const SizedBox(height: 2),
          Text(note, style: MrType.caption),
        ],
      ),
    );
  }
}

/// A small rounded status pill for the HUD.
class MrPill extends StatelessWidget {
  const MrPill({super.key, required this.label, required this.colour});
  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: MrSpace.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(MrRadius.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          child: Text(
            label,
            style: MrType.caption.copyWith(
              color: colour,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
