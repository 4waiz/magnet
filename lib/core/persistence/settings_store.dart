/// Player settings, persisted with `shared_preferences`.
///
/// A [ValueNotifier] so the game loop and the UI observe the same instance —
/// changing effect intensity mid-run takes effect on the next frame without
/// any restart or plumbing.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../performance/quality.dart';

@immutable
class GameSettings {
  const GameSettings({
    this.soundVolume = 0.85,
    this.musicVolume = 0.55,
    this.hapticsEnabled = true,
    this.cameraShake = true,
    this.reducedMotion = false,
    this.effectIntensity = 1.0,
    this.quality = QualityPreset.medium,
  });

  final double soundVolume;
  final double musicVolume;
  final bool hapticsEnabled;
  final bool cameraShake;

  /// Reduces shake, FOV change and rapid camera movement. Explicitly does not
  /// change gameplay timing, forces or scoring.
  final bool reducedMotion;

  /// 0..1 multiplier on particle counts and glow.
  final double effectIntensity;

  final QualityPreset quality;

  QualitySettings get qualitySettings => QualitySettings.of(quality);

  GameSettings copyWith({
    double? soundVolume,
    double? musicVolume,
    bool? hapticsEnabled,
    bool? cameraShake,
    bool? reducedMotion,
    double? effectIntensity,
    QualityPreset? quality,
  }) {
    return GameSettings(
      soundVolume: soundVolume ?? this.soundVolume,
      musicVolume: musicVolume ?? this.musicVolume,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      cameraShake: cameraShake ?? this.cameraShake,
      reducedMotion: reducedMotion ?? this.reducedMotion,
      effectIntensity: effectIntensity ?? this.effectIntensity,
      quality: quality ?? this.quality,
    );
  }

  Map<String, Object> toMap() => {
    'soundVolume': soundVolume,
    'musicVolume': musicVolume,
    'hapticsEnabled': hapticsEnabled,
    'cameraShake': cameraShake,
    'reducedMotion': reducedMotion,
    'effectIntensity': effectIntensity,
    'quality': quality.name,
  };

  static GameSettings fromMap(Map<String, Object?> m) {
    QualityPreset parseQuality(Object? v) {
      for (final q in QualityPreset.values) {
        if (q.name == v) return q;
      }
      return QualityPreset.medium;
    }

    double clamp01(Object? v, double fallback) {
      if (v is num) return v.toDouble().clamp(0.0, 1.0);
      return fallback;
    }

    return GameSettings(
      soundVolume: clamp01(m['soundVolume'], 0.85),
      musicVolume: clamp01(m['musicVolume'], 0.55),
      hapticsEnabled: m['hapticsEnabled'] as bool? ?? true,
      cameraShake: m['cameraShake'] as bool? ?? true,
      reducedMotion: m['reducedMotion'] as bool? ?? false,
      effectIntensity: clamp01(m['effectIntensity'], 1.0),
      quality: parseQuality(m['quality']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GameSettings &&
      other.soundVolume == soundVolume &&
      other.musicVolume == musicVolume &&
      other.hapticsEnabled == hapticsEnabled &&
      other.cameraShake == cameraShake &&
      other.reducedMotion == reducedMotion &&
      other.effectIntensity == effectIntensity &&
      other.quality == quality;

  @override
  int get hashCode => Object.hash(
    soundVolume,
    musicVolume,
    hapticsEnabled,
    cameraShake,
    reducedMotion,
    effectIntensity,
    quality,
  );
}

class SettingsStore extends ValueNotifier<GameSettings> {
  SettingsStore([super.initial = const GameSettings()]);

  static const String _key = 'mr.settings.v1';
  SharedPreferences? _prefs;

  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      // No platform channel (unit tests, or a device without storage) — run
      // with defaults rather than failing to boot.
      return;
    }
    final raw = _prefs!.getStringList(_key);
    if (raw == null) return;
    final map = <String, Object?>{};
    for (final entry in raw) {
      final i = entry.indexOf('=');
      if (i <= 0) continue;
      final k = entry.substring(0, i);
      final v = entry.substring(i + 1);
      map[k] = switch (v) {
        'true' => true,
        'false' => false,
        _ => double.tryParse(v) ?? v,
      };
    }
    value = GameSettings.fromMap(map);
  }

  Future<void> update(GameSettings next) async {
    if (next == value) return;
    value = next;
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setStringList(
      _key,
      next.toMap().entries.map((e) => '${e.key}=${e.value}').toList(),
    );
  }
}
