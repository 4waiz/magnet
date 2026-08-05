/// Settings, usable both from the home screen and from the pause overlay.
library;

import 'package:flutter/widgets.dart';

import '../../core/audio/audio_service.dart';
import '../../core/haptics/haptics_service.dart';
import '../../core/performance/quality.dart';
import '../../core/persistence/settings_store.dart';
import '../../shared/theme/mr_theme.dart';
import '../../shared/widgets/mr_widgets.dart';

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({
    super.key,
    required this.settings,
    required this.audio,
    required this.haptics,
  });

  final SettingsStore settings;
  final AudioService audio;
  final HapticsService haptics;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final s = settings.value;
        void apply(GameSettings next) {
          settings.update(next);
          audio.sfxVolume = next.soundVolume;
          audio.musicVolume = next.musicVolume;
          haptics.enabled = next.hapticsEnabled;
        }

        return MrPanel(
          padding: const EdgeInsets.all(MrSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const MrDivider(label: 'Audio'),
              const SizedBox(height: MrSpace.md),
              _Slider(
                label: 'Sound',
                value: s.soundVolume,
                onChanged: (v) {
                  apply(s.copyWith(soundVolume: v));
                  audio.play(Sfx.uiTap, volume: 0.6);
                },
              ),
              _Slider(
                label: 'Music',
                value: s.musicVolume,
                onChanged: (v) => apply(s.copyWith(musicVolume: v)),
              ),
              const SizedBox(height: MrSpace.md),
              const MrDivider(label: 'Feel'),
              const SizedBox(height: MrSpace.md),
              _Toggle(
                label: 'Haptics',
                note: haptics.supported
                    ? 'Vibration feedback'
                    : 'Not available on this device',
                value: s.hapticsEnabled && haptics.supported,
                enabled: haptics.supported,
                onChanged: (v) => apply(s.copyWith(hapticsEnabled: v)),
              ),
              _Toggle(
                label: 'Camera shake',
                note: 'Impact camera movement',
                value: s.cameraShake,
                onChanged: (v) => apply(s.copyWith(cameraShake: v)),
              ),
              _Toggle(
                label: 'Reduced motion',
                note: 'Less shake and zoom. Gameplay is unchanged.',
                value: s.reducedMotion,
                onChanged: (v) => apply(s.copyWith(reducedMotion: v)),
              ),
              _Slider(
                label: 'Effect intensity',
                value: s.effectIntensity,
                onChanged: (v) => apply(s.copyWith(effectIntensity: v)),
              ),
              const SizedBox(height: MrSpace.md),
              const MrDivider(label: 'Graphics'),
              const SizedBox(height: MrSpace.md),
              Row(
                children: [
                  for (final q in QualityPreset.values) ...[
                    Expanded(
                      child: MrButton(
                        label: q.label,
                        compact: true,
                        primary: s.quality == q,
                        onPressed: () => apply(s.copyWith(quality: q)),
                      ),
                    ),
                    if (q != QualityPreset.values.last)
                      const SizedBox(width: MrSpace.sm),
                  ],
                ],
              ),
              const SizedBox(height: MrSpace.sm),
              Text(
                'Swarm cap ${s.qualitySettings.maxSwarm} · '
                'particles ${s.qualitySettings.maxParticles} · '
                'debris ${s.qualitySettings.maxDebris}',
                style: MrType.caption,
              ),
              const SizedBox(height: 3),
              Text(
                'Quality changes take effect on the next level start.',
                style: MrType.caption.copyWith(color: MrColors.textMuted),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MrSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: MrType.label),
              Text('${(value * 100).round()}%', style: MrType.caption),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, c) {
              void setFrom(Offset local) =>
                  onChanged((local.dx / c.maxWidth).clamp(0.0, 1.0));
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => setFrom(d.localPosition),
                onHorizontalDragUpdate: (d) => setFrom(d.localPosition),
                child: SizedBox(
                  height: 22,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: MrProgressBar(value: value, height: 8),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.note,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final String note;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MrSpace.md),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: MrType.label),
                    const SizedBox(height: 2),
                    Text(note, style: MrType.caption),
                  ],
                ),
              ),
              const SizedBox(width: MrSpace.md),
              _Switch(on: value),
            ],
          ),
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 46,
      height: 26,
      decoration: BoxDecoration(
        color: on ? MrColors.primary : MrColors.divider,
        borderRadius: BorderRadius.circular(MrRadius.pill),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: const BoxDecoration(
            color: MrColors.textPrimary,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
