/// The Magnet Rush design system.
///
/// Clean and modern rather than sci-fi: rounded corners, solid fills, no glow,
/// and normal typography. The 3D scene supplies the science-fiction; the
/// interface stays out of its way and simply reads well.
///
/// Deliberately avoided: chamfered/angular panels, neon edge glows, glowing
/// hairline dividers, and wide-tracked monospace "console" type. Those are the
/// vocabulary of a HUD, and they made every screen look like an instrument
/// panel instead of a game menu.
///
/// It is still a *dark* interface, because it sits over a dark 3D scene and a
/// light one would fight it — but the palette is neutral charcoal, not navy.
library;

import 'package:flutter/widgets.dart';

abstract final class MrColors {
  // Surfaces — neutral dark, slightly warm so it does not read as "tech blue".
  static const Color background = Color(0xFF14161B);
  static const Color surface = Color(0xFF1D2027);
  static const Color surfaceHigh = Color(0xFF262A33);
  static const Color surfaceLow = Color(0xFF181A20);
  static const Color divider = Color(0xFF2E323C);

  // Text
  static const Color textPrimary = Color(0xFFF4F6F8);
  static const Color textSecondary = Color(0xFF9BA3B0);
  static const Color textMuted = Color(0xFF646C7A);

  // Accents. Flat fills, no glow.
  static const Color primary = Color(0xFF3E7BFA);
  static const Color primaryDark = Color(0xFF2C5FD0);
  static const Color reward = Color(0xFFF5A524);
  static const Color danger = Color(0xFFE5484D);
  static const Color success = Color(0xFF30A46C);

  /// Kept for the small in-world readouts that must match the 3D scene's
  /// colour language (cyan = the player's own technology, orange = hazard).
  /// Used sparingly, and never as interface chrome.
  static const Color worldSafe = Color(0xFF4FC3E8);
  static const Color worldHazard = Color(0xFFE8834F);

  static const Color scrim = Color(0xE614161B);
}

abstract final class MrRadius {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double pill = 999;
}

abstract final class MrType {
  static const TextStyle display = TextStyle(
    color: MrColors.textPrimary,
    fontSize: 34,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    height: 1.1,
  );
  static const TextStyle title = TextStyle(
    color: MrColors.textPrimary,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    height: 1.2,
  );
  static const TextStyle label = TextStyle(
    color: MrColors.textSecondary,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );
  static const TextStyle value = TextStyle(
    color: MrColors.textPrimary,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const TextStyle body = TextStyle(
    color: MrColors.textSecondary,
    fontSize: 15,
    height: 1.45,
  );
  static const TextStyle button = TextStyle(
    color: MrColors.textPrimary,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
  );
  static const TextStyle caption = TextStyle(
    color: MrColors.textMuted,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );
}

abstract final class MrSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 22;
  static const double xl = 34;
}
