/// Home screen.
///
/// The hero is a painted 2D projection of the Core rather than a second live
/// 3D scene: it animates continuously at a fraction of the cost, and it means
/// the renderer is only ever initialised once, when gameplay starts.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/audio/audio_service.dart';
import '../../core/haptics/haptics_service.dart';
import '../../core/persistence/settings_store.dart';
import '../../shared/theme/mr_theme.dart';
import '../../shared/widgets/mr_widgets.dart';
import '../gameplay/gameplay_screen.dart';
import '../settings/settings_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.settings,
    required this.audio,
    required this.haptics,
  });

  final SettingsStore settings;
  final AudioService audio;
  final HapticsService haptics;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  bool _showSettings = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _play() {
    widget.audio.play(Sfx.uiConfirm);
    widget.haptics.impact(HapticStrength.light, important: true);
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, _, _) => GameplayScreen(
          settings: widget.settings,
          audio: widget.audio,
          haptics: widget.haptics,
          // Frame-time overlay for measured performance runs:
          //   flutter run --dart-define=MR_STATS=true
          showDebugStats: const bool.fromEnvironment(
            'MR_STATS',
            defaultValue: false,
          ),
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: MrColors.background,
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) =>
                  CustomPaint(painter: _AmbientPainter(_c.value * math.pi * 2)),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              // Scrollable: the menu is taller than a short phone in
              // landscape-ish aspect ratios, and a fixed Column silently
              // clips its lower half there.
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(MrSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: MrSpace.md),
                    Text(
                      'Magnet Rush',
                      textAlign: TextAlign.center,
                      style: MrType.display.copyWith(fontSize: 34),
                    ),
                    const SizedBox(height: MrSpace.xs),
                    Text(
                      'Attract · Charge · Blast',
                      textAlign: TextAlign.center,
                      style: MrType.caption,
                    ),
                    const SizedBox(height: MrSpace.lg),
                    AnimatedBuilder(
                      animation: _c,
                      builder: (context, child) {
                        // A slow float, so the hero is alive without
                        // demanding attention.
                        final t = _c.value * math.pi * 2;
                        return Transform.translate(
                          offset: Offset(0, math.sin(t) * 6),
                          child: Transform.scale(
                            scale: 1 + math.sin(t * 0.7) * 0.012,
                            child: child,
                          ),
                        );
                      },
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 260,
                            maxHeight: 260,
                          ),
                          child: Image.asset(
                            'assets/branding/icon.png',
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: MrSpace.lg),
                    Row(
                      children: [
                        Expanded(
                          child: MrPanel(
                            radius: 10,
                            padding: const EdgeInsets.symmetric(
                              horizontal: MrSpace.md,
                              vertical: MrSpace.sm,
                            ),
                            child: const MrStat(
                              label: 'World 1 · Level',
                              value: '01',
                            ),
                          ),
                        ),
                        const SizedBox(width: MrSpace.sm),
                        Expanded(
                          child: MrPanel(
                            radius: 10,
                            padding: const EdgeInsets.symmetric(
                              horizontal: MrSpace.md,
                              vertical: MrSpace.sm,
                            ),
                            child: const MrStat(
                              label: 'Coins',
                              value: '0',
                              colour: MrColors.reward,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: MrSpace.md),
                    MrButton(
                      label: 'Play',
                      primary: true,
                      width: double.infinity,
                      onPressed: _play,
                    ),
                    const SizedBox(height: MrSpace.md),
                    const MrDivider(label: 'Coming soon'),
                    const SizedBox(height: MrSpace.md),
                    Wrap(
                      spacing: MrSpace.sm,
                      runSpacing: MrSpace.sm,
                      children: const [
                        MrLockedTile(label: 'Upgrades', note: 'Coming soon'),
                        MrLockedTile(label: 'Skins', note: 'Coming soon'),
                        MrLockedTile(label: 'Daily', note: 'Coming soon'),
                        MrLockedTile(label: 'Endless', note: 'Coming soon'),
                        MrLockedTile(label: 'Missions', note: 'Coming soon'),
                      ],
                    ),
                    const SizedBox(height: MrSpace.md),
                    MrButton(
                      label: _showSettings ? 'Close settings' : 'Settings',
                      width: double.infinity,
                      compact: true,
                      onPressed: () {
                        widget.audio.play(Sfx.uiTap);
                        setState(() => _showSettings = !_showSettings);
                      },
                    ),
                    if (_showSettings) ...[
                      const SizedBox(height: MrSpace.md),
                      SettingsSheet(
                        settings: widget.settings,
                        audio: widget.audio,
                        haptics: widget.haptics,
                      ),
                    ],
                    const SizedBox(height: MrSpace.sm),
                    Text(
                      'Vertical slice build · World 1, Level 1',
                      textAlign: TextAlign.center,
                      style: MrType.caption.copyWith(color: MrColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A quiet ambient backdrop behind the menu.
///
/// The hero itself is now the app icon, so this only supplies a soft vignette
/// and a few drifting motes — enough to keep the screen from feeling static,
/// without competing with the artwork.
class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.5, size.height * 0.42);

    canvas.drawCircle(
      c,
      size.width * 0.62,
      Paint()
        ..shader = RadialGradient(
          colors: [
            MrColors.surfaceHigh.withValues(alpha: 0.42),
            const Color(0x00000000),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: size.width * 0.62)),
    );

    // Drifting motes, far enough back to read as dust rather than gameplay.
    final paint = Paint()..color = MrColors.textMuted.withValues(alpha: 0.30);
    for (var i = 0; i < 16; i++) {
      final a = t * (0.10 + (i % 4) * 0.035) + i * 0.9;
      final r = size.width * (0.30 + (i % 5) * 0.075);
      final p = Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r * 0.62);
      final s = 2.0 + (i % 3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: p, width: s * 2, height: s * 2),
          Radius.circular(s * 0.4),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.t != t;
}
