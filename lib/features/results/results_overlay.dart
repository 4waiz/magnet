/// Results and failure flows.
///
/// Results animate in rather than appearing at once: stars land one at a time
/// and each statistic counts up, so the screen reads as a reward instead of a
/// receipt.
library;

import 'package:flutter/widgets.dart';

import '../../game/game_world.dart';
import '../../shared/theme/mr_theme.dart';
import '../../shared/widgets/mr_widgets.dart';

class ResultsOverlay extends StatefulWidget {
  const ResultsOverlay({
    super.key,
    required this.world,
    required this.onRetry,
    required this.onContinue,
  });

  final GameWorld world;
  final VoidCallback onRetry;
  final VoidCallback onContinue;

  @override
  State<ResultsOverlay> createState() => _ResultsOverlayState();
}

class _ResultsOverlayState extends State<ResultsOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2100),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final score = widget.world.score;
    final metalTarget = widget.world.level.objectives
        .firstWhere(
          (o) => o.id == 'collect_40',
          orElse: () => widget.world.level.objectives.first,
        )
        .target;
    final stars = score.stars(metalTarget);

    return Positioned.fill(
      child: ColoredBox(
        color: MrColors.scrim,
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              double reveal(double from, double to) =>
                  ((t - from) / (to - from)).clamp(0.0, 1.0);
              final panel = reveal(0.0, 0.25);
              final statsT = reveal(0.35, 1.0);

              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(MrSpace.lg),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Opacity(
                      opacity: panel,
                      child: Transform.translate(
                        offset: Offset(0, (1 - panel) * 26),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Level complete',
                              style: MrType.display.copyWith(fontSize: 30),
                            ),
                            const SizedBox(height: MrSpace.xs),
                            Text(
                              'Level ${widget.world.level.index}',
                              style: MrType.caption,
                            ),
                            const SizedBox(height: MrSpace.lg),
                            MrStars(stars: stars, reveal: reveal(0.2, 1.1)),
                            const SizedBox(height: MrSpace.lg),
                            MrPanel(
                              padding: const EdgeInsets.all(MrSpace.md),
                              child: Column(
                                children: [
                                  _Row(
                                    label: 'Metal collected',
                                    value: score.metalCollected,
                                    t: statsT,
                                  ),
                                  const SizedBox(height: MrSpace.sm),
                                  _Row(
                                    label: 'Destruction',
                                    value: score.destructionScore,
                                    t: statsT,
                                  ),
                                  const SizedBox(height: MrSpace.sm),
                                  _Row(
                                    label: 'Largest swarm',
                                    value: score.largestSwarm,
                                    t: statsT,
                                  ),
                                  const SizedBox(height: MrSpace.sm),
                                  _Row(
                                    label: 'Perfect releases',
                                    value: score.perfectReleases,
                                    t: statsT,
                                    colour: MrColors.reward,
                                  ),
                                  const SizedBox(height: MrSpace.sm),
                                  _Row(
                                    label: 'Best chain',
                                    value: score.bestCombo,
                                    t: statsT,
                                  ),
                                  const SizedBox(height: MrSpace.md),
                                  const MrDivider(label: 'Total'),
                                  const SizedBox(height: MrSpace.md),
                                  _Row(
                                    label: 'Score',
                                    value: score.total,
                                    t: statsT,
                                    big: true,
                                  ),
                                  const SizedBox(height: MrSpace.sm),
                                  _Row(
                                    label: 'Coins earned',
                                    value: score.coins,
                                    t: statsT,
                                    colour: MrColors.reward,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: MrSpace.lg),
                            MrButton(
                              label: 'Continue',
                              primary: true,
                              width: double.infinity,
                              onPressed: widget.onContinue,
                            ),
                            const SizedBox(height: MrSpace.sm),
                            MrButton(
                              label: 'Retry',
                              width: double.infinity,
                              onPressed: widget.onRetry,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    required this.t,
    this.colour = MrColors.textPrimary,
    this.big = false,
  });

  final String label;
  final int value;
  final double t;
  final Color colour;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final shown = (value * Curves.easeOutCubic.transform(t)).round();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: MrType.label.copyWith(fontSize: big ? 12 : 11)),
        Text(
          '$shown',
          style: MrType.value.copyWith(color: colour, fontSize: big ? 26 : 17),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class FailureOverlay extends StatelessWidget {
  const FailureOverlay({
    super.key,
    required this.reason,
    required this.onRetry,
    required this.onHome,
  });

  final String reason;
  final VoidCallback onRetry;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: MrColors.scrim,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(MrSpace.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Core lost',
                      style: MrType.display.copyWith(
                        fontSize: 30,
                        color: MrColors.danger,
                      ),
                    ),
                    const SizedBox(height: MrSpace.md),
                    MrPanel(
                      border: MrColors.danger,
                      padding: const EdgeInsets.all(MrSpace.md),
                      child: Text(
                        reason,
                        textAlign: TextAlign.center,
                        style: MrType.body.copyWith(
                          color: MrColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: MrSpace.xl),
                    MrButton(
                      label: 'Retry',
                      primary: true,
                      width: double.infinity,
                      onPressed: onRetry,
                    ),
                    const SizedBox(height: MrSpace.sm),
                    MrButton(
                      label: 'Home',
                      width: double.infinity,
                      onPressed: onHome,
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
