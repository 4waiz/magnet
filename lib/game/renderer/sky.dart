/// The sky behind the facility.
///
/// Painted in 2D underneath the 3D scene rather than as geometry: it costs a
/// few gradient and blob fills instead of draw calls, it never needs to be
/// depth-sorted against the level, and it can parallax against the Core's
/// forward travel for free.
///
/// Kept deliberately dark and low-contrast. The Core has to remain the
/// brightest thing on screen, so the sky is atmosphere, not a feature.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

/// One pre-generated cloud, in normalised coordinates.
class _Cloud {
  const _Cloud(this.x, this.y, this.scale, this.puffs);
  final double x;
  final double y;
  final double scale;
  final List<ui.Offset> puffs;
}

class _Band {
  _Band({
    required this.clouds,
    required this.drift,
    required this.parallax,
    required this.alpha,
    required this.colour,
    required this.blur,
  });

  final List<_Cloud> clouds;

  /// Horizontal drift, screen-widths per second.
  final double drift;

  /// How strongly the band responds to the Core's forward travel.
  final double parallax;
  final double alpha;
  final ui.Color colour;
  final double blur;
}

class SkyPainter {
  SkyPainter({int seed = 20260805}) {
    final rng = math.Random(seed);

    List<_Cloud> band(
      int count,
      double minScale,
      double maxScale,
      double top,
      double bottom,
    ) {
      return List.generate(count, (_) {
        final puffCount = 3 + rng.nextInt(4);
        final puffs = <ui.Offset>[];
        for (var i = 0; i < puffCount; i++) {
          // Puffs spread mostly horizontally so clouds stay wide and flat
          // rather than reading as bubbles.
          puffs.add(
            ui.Offset(
              (i / math.max(1, puffCount - 1) - 0.5) * 1.7 +
                  (rng.nextDouble() - 0.5) * 0.25,
              (rng.nextDouble() - 0.5) * 0.34,
            ),
          );
        }
        return _Cloud(
          rng.nextDouble(),
          top + rng.nextDouble() * (bottom - top),
          minScale + rng.nextDouble() * (maxScale - minScale),
          puffs,
        );
      });
    }

    _bands = [
      // Far, faint, almost static.
      _Band(
        clouds: band(5, 0.20, 0.34, 0.10, 0.34),
        drift: 0.004,
        parallax: 0.0016,
        alpha: 0.30,
        colour: const ui.Color(0xFF2A3550),
        blur: 26,
      ),
      // Mid.
      _Band(
        clouds: band(4, 0.30, 0.48, 0.20, 0.46),
        drift: 0.009,
        parallax: 0.0034,
        alpha: 0.34,
        colour: const ui.Color(0xFF33405F),
        blur: 20,
      ),
      // Near, largest, moves most.
      _Band(
        clouds: band(3, 0.46, 0.70, 0.30, 0.55),
        drift: 0.017,
        parallax: 0.0062,
        alpha: 0.26,
        colour: const ui.Color(0xFF3C4A6B),
        blur: 16,
      ),
    ];
  }

  late final List<_Band> _bands;

  /// Paints sky and clouds across [size].
  ///
  /// [time] drives drift, [scroll] is the Core's forward position so the sky
  /// slides as the level advances.
  void paint(ui.Canvas canvas, ui.Size size, double time, double scroll) {
    final rect = ui.Offset.zero & size;

    // Sky gradient. Darkest overhead, warming very slightly toward the
    // horizon so the facility silhouettes read against something.
    canvas.drawRect(
      rect,
      ui.Paint()
        ..shader = ui.Gradient.linear(
          ui.Offset(0, 0),
          ui.Offset(0, size.height * 0.72),
          const [
            ui.Color(0xFF070A12),
            ui.Color(0xFF101728),
            ui.Color(0xFF1B2740),
          ],
          const [0.0, 0.45, 1.0],
        ),
    );

    // A soft horizon glow, low on the screen, where the facility sits.
    canvas.drawRect(
      rect,
      ui.Paint()
        ..shader = ui.Gradient.radial(
          ui.Offset(size.width * 0.5, size.height * 0.60),
          size.width * 0.95,
          const [ui.Color(0x33314A78), ui.Color(0x00000000)],
        ),
    );

    for (final b in _bands) {
      final paint = ui.Paint()
        ..color = b.colour.withValues(alpha: b.alpha)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, b.blur);

      final shift = time * b.drift + scroll * b.parallax;
      for (final c in b.clouds) {
        // Wrap horizontally so the band is endless.
        var cx = (c.x + shift) % 1.0;
        if (cx < 0) cx += 1.0;
        // Draw twice near the seam so a cloud never pops in at the edge.
        for (final wrap in const [0.0, -1.0]) {
          final ox = (cx + wrap) * size.width * 1.4 - size.width * 0.2;
          final oy = c.y * size.height;
          final r = c.scale * size.width * 0.16;
          if (ox < -r * 3 || ox > size.width + r * 3) continue;
          for (final p in c.puffs) {
            canvas.drawCircle(
              ui.Offset(ox + p.dx * r * 1.6, oy + p.dy * r),
              r * (0.62 + p.dy.abs() * 0.5),
              paint,
            );
          }
        }
      }
    }
  }
}
