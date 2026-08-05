/// The Level 1 gameplay screen: frame loop, 3D surface, HUD, and the results
/// and failure flows.
library;

import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../core/audio/audio_service.dart';
import '../../core/haptics/haptics_service.dart';
import '../../core/performance/frame_stats.dart';
import '../../core/persistence/settings_store.dart';
import '../../game/game_world.dart';
import '../../shared/theme/mr_theme.dart';
import '../../shared/widgets/mr_widgets.dart';
import '../results/results_overlay.dart';
import '../settings/settings_sheet.dart';

class GameplayScreen extends StatefulWidget {
  const GameplayScreen({
    super.key,
    required this.settings,
    required this.audio,
    required this.haptics,
    this.showDebugStats = false,
  });

  final SettingsStore settings;
  final AudioService audio;
  final HapticsService haptics;
  final bool showDebugStats;

  @override
  State<GameplayScreen> createState() => _GameplayScreenState();
}

class _GameplayScreenState extends State<GameplayScreen>
    with SingleTickerProviderStateMixin {
  late final GameWorld _world = GameWorld(
    settings: widget.settings,
    audio: widget.audio,
    haptics: widget.haptics,
  );
  late final Ticker _ticker;
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  final FrameStats _stats = FrameStats();

  Duration _last = Duration.zero;
  double _dt = 1 / 60;
  bool _ready = false;
  bool _paused = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onFrame)..start();
    _boot();
    SchedulerBinding.instance.addTimingsCallback(_stats.onTimings);
  }

  Future<void> _boot() async {
    try {
      await _world.load();
      if (!mounted) return;
      setState(() => _ready = true);
      _applySettings();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  void _applySettings() {
    widget.audio.sfxVolume = widget.settings.value.soundVolume;
    widget.audio.musicVolume = widget.settings.value.musicVolume;
    widget.haptics.enabled = widget.settings.value.hapticsEnabled;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    SchedulerBinding.instance.removeTimingsCallback(_stats.onTimings);
    widget.audio.setAttracting(false, 0);
    super.dispose();
  }

  void _onFrame(Duration elapsed) {
    _dt = _last == Duration.zero
        ? 1 / 60
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (!_ready || _paused) return;
    _world.update(_dt);
    _repaint.value++;
  }

  void _retry() {
    setState(() {
      _stats.reset();
      _world.resetLevel();
      _paused = false;
    });
  }

  void _exit() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _ErrorPane(message: _error!, onBack: _exit);
    if (!_ready) return const _LoadingPane();

    return ColoredBox(
      color: MrColors.background,
      child: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) {
                if (_paused ||
                    _world.phase == GamePhase.complete ||
                    _world.phase == GamePhase.failed) {
                  return;
                }
                _world.onPointerDown();
              },
              onPointerUp: (_) => _world.onPointerUp(),
              onPointerCancel: (_) => _world.onPointerUp(),
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _WorldPainter(
                    world: _world,
                    dtOf: () => _dt,
                    repaint: _repaint,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),

          // Vignette: darkens the frame edges so the Core holds the eye.
          const Positioned.fill(child: IgnorePointer(child: _Vignette())),

          Positioned.fill(
            child: SafeArea(
              child: ListenableBuilder(
                listenable: _repaint,
                builder: (context, _) => _Hud(
                  world: _world,
                  stats: _stats,
                  showDebug: widget.showDebugStats,
                  onPause: () => setState(() => _paused = true),
                ),
              ),
            ),
          ),

          ListenableBuilder(
            listenable: _repaint,
            builder: (context, _) {
              if (_world.phase == GamePhase.complete) {
                return ResultsOverlay(
                  world: _world,
                  onRetry: _retry,
                  onContinue: _exit,
                );
              }
              if (_world.phase == GamePhase.failed) {
                return FailureOverlay(
                  reason: _world.failureReason,
                  onRetry: _retry,
                  onHome: _exit,
                );
              }
              return const SizedBox.shrink();
            },
          ),

          if (_paused)
            _PauseOverlay(
              settings: widget.settings,
              audio: widget.audio,
              haptics: widget.haptics,
              onResume: () => setState(() => _paused = false),
              onRetry: _retry,
              onHome: _exit,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3D surface
// ---------------------------------------------------------------------------

class _WorldPainter extends CustomPainter {
  _WorldPainter({
    required this.world,
    required this.dtOf,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final GameWorld world;
  final double Function() dtOf;

  @override
  void paint(ui.Canvas canvas, ui.Size size) =>
      world.render(canvas, size, dtOf());

  @override
  bool shouldRepaint(_WorldPainter oldDelegate) => false;
}

class _Vignette extends StatelessWidget {
  const _Vignette();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, 0.15),
          radius: 0.95,
          colors: [Color(0x00000000), Color(0x00000000), Color(0x7A000000)],
          stops: [0.0, 0.62, 1.0],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

// ---------------------------------------------------------------------------
// HUD
// ---------------------------------------------------------------------------

class _Hud extends StatelessWidget {
  const _Hud({
    required this.world,
    required this.stats,
    required this.showDebug,
    required this.onPause,
  });

  final GameWorld world;
  final FrameStats stats;
  final bool showDebug;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    final hidden =
        world.phase == GamePhase.complete || world.phase == GamePhase.failed;
    if (hidden) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MrSpace.md,
        MrSpace.sm,
        MrSpace.md,
        MrSpace.md,
      ),
      child: Column(
        children: [
          // --- top bar ---------------------------------------------------
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PauseButton(onTap: onPause),
              const SizedBox(width: MrSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Level ${world.level.index}',
                          style: MrType.label.copyWith(
                            color: MrColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: MrSpace.sm),
                        Expanded(
                          child: Text(
                            _titleCase(world.level.name),
                            style: MrType.caption,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    MrProgressBar(value: world.progress),
                  ],
                ),
              ),
              const SizedBox(width: MrSpace.md),
              _MetalCounter(count: world.collected),
            ],
          ),

          const SizedBox(height: MrSpace.sm),

          // --- objective chips -------------------------------------------
          Row(
            children: [
              if (world.armourRemaining > 0)
                MrPill(
                  label: 'Armour ${world.armourRemaining}',
                  colour: MrColors.worldSafe,
                ),
              if (world.bridgeFormed)
                const MrPill(label: 'Bridge', colour: MrColors.success),
              if (world.keyCollected)
                const MrPill(label: 'Key', colour: MrColors.reward),
              if (world.portalUnlocked)
                const MrPill(label: 'Portal open', colour: MrColors.success),
            ],
          ),

          const Spacer(),

          // --- toasts -----------------------------------------------------
          for (final t in world.toasts)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Opacity(
                opacity: (t.life * 2.2).clamp(0.0, 1.0),
                child: Text(
                  t.text,
                  textAlign: TextAlign.center,
                  style: MrType.title.copyWith(fontSize: 17, color: t.colour),
                ),
              ),
            ),

          const SizedBox(height: MrSpace.md),

          // --- bottom bar -------------------------------------------------
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MrChargeDial(
                charge: world.chargeValue,
                perfect: world.perfectWindow,
                ventPressure: world.ventPressure,
              ),
              const SizedBox(width: MrSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text('Swarm', style: MrType.label),
                        const SizedBox(width: MrSpace.sm),
                        Text(
                          '${world.orbiting}',
                          style: MrType.value.copyWith(
                            color: world.stage >= 3
                                ? MrColors.reward
                                : MrColors.textPrimary,
                          ),
                        ),
                        Text('  Stage ${world.stage}', style: MrType.caption),
                        const Spacer(),
                        if (world.score.combo > 1)
                          Text(
                            '${world.score.combo} chain  '
                            'x${world.score.comboMultiplier.toStringAsFixed(2)}',
                            style: MrType.caption.copyWith(
                              color: MrColors.reward,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    MrProgressBar(
                      value: world.level.swarmStages.isEmpty
                          ? 0
                          : world.orbiting /
                                world.level.swarmStages.last.toDouble(),
                      colour: world.stage >= 3
                          ? MrColors.reward
                          : MrColors.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (showDebug) ...[
            const SizedBox(height: MrSpace.sm),
            Text(
              'avg ${stats.avgMs.toStringAsFixed(2)}ms  '
              'p95 ${stats.p95Ms.toStringAsFixed(2)}ms  '
              'max ${stats.maxMs.toStringAsFixed(1)}ms  '
              'tris ${world.batchTriangles}',
              style: MrType.caption.copyWith(
                color: stats.avgMs < 17
                    ? MrColors.success
                    : MrColors.worldHazard,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: MrPanel(
        radius: 9,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 3, height: 13, color: MrColors.textPrimary),
            const SizedBox(width: 3.5),
            Container(width: 3, height: 13, color: MrColors.textPrimary),
          ],
        ),
      ),
    );
  }
}

/// Level names are authored in caps to suit the in-world signage; the
/// interface presents them as ordinary title case.
String _titleCase(String s) => s
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

class _MetalCounter extends StatelessWidget {
  const _MetalCounter({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return MrPanel(
      radius: MrRadius.pill,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: MrColors.worldSafe,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: MrSpace.sm),
          Text('$count', style: MrType.value.copyWith(fontSize: 16)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Panes
// ---------------------------------------------------------------------------

class _LoadingPane extends StatelessWidget {
  const _LoadingPane();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: MrColors.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Magnet Rush', style: MrType.title),
            SizedBox(height: MrSpace.sm),
            Text('Loading…', style: MrType.caption),
          ],
        ),
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.message, required this.onBack});
  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: MrColors.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MrSpace.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Level failed to load',
                style: MrType.title.copyWith(color: MrColors.danger),
              ),
              const SizedBox(height: MrSpace.md),
              Text(message, style: MrType.body, textAlign: TextAlign.center),
              const SizedBox(height: MrSpace.lg),
              MrButton(label: 'Back', onPressed: onBack, primary: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay({
    required this.settings,
    required this.audio,
    required this.haptics,
    required this.onResume,
    required this.onRetry,
    required this.onHome,
  });

  final SettingsStore settings;
  final AudioService audio;
  final HapticsService haptics;
  final VoidCallback onResume;
  final VoidCallback onRetry;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: MrColors.scrim,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(MrSpace.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Paused',
                      style: MrType.display.copyWith(fontSize: 30),
                    ),
                    const SizedBox(height: MrSpace.lg),
                    SettingsSheet(
                      settings: settings,
                      audio: audio,
                      haptics: haptics,
                    ),
                    const SizedBox(height: MrSpace.lg),
                    MrButton(
                      label: 'Resume',
                      onPressed: onResume,
                      primary: true,
                      width: double.infinity,
                    ),
                    const SizedBox(height: MrSpace.sm),
                    Row(
                      children: [
                        Expanded(
                          child: MrButton(label: 'Retry', onPressed: onRetry),
                        ),
                        const SizedBox(width: MrSpace.sm),
                        Expanded(
                          child: MrButton(label: 'Home', onPressed: onHome),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
