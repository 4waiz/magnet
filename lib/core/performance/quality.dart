/// Graphics quality presets.
///
/// Presets scale *presentation* only. Attraction range, repulsion force, orbit
/// slot counts, hazard timing and scoring are identical at every preset, so a
/// player on low never has an easier or harder game — only a cheaper-looking
/// one. The one thing that does change is [maxSwarm], because the swarm is the
/// dominant per-frame cost; the gameplay cap in level data is clamped to it and
/// the HUD shows the effective number.
library;

enum QualityPreset { low, medium, high }

extension QualityPresetLabel on QualityPreset {
  String get label => switch (this) {
    QualityPreset.low => 'Low',
    QualityPreset.medium => 'Medium',
    QualityPreset.high => 'High',
  };
}

class QualitySettings {
  const QualitySettings({
    required this.preset,
    required this.maxSwarm,
    required this.maxParticles,
    required this.maxDebris,
    required this.fieldLines,
    required this.decorDensity,
    required this.glowIntensity,
    required this.trailSegments,
    required this.contactShadows,
    required this.backgroundLayers,
  });

  final QualityPreset preset;
  final int maxSwarm;
  final int maxParticles;
  final int maxDebris;
  final int fieldLines;

  /// 0..1 multiplier on decorative (non-gameplay) scenery counts.
  final double decorDensity;

  /// 0..1 multiplier on emissive/glow strength.
  final double glowIntensity;

  final int trailSegments;
  final bool contactShadows;
  final int backgroundLayers;

  static const QualitySettings low = QualitySettings(
    preset: QualityPreset.low,
    maxSwarm: 60,
    maxParticles: 90,
    maxDebris: 40,
    fieldLines: 4,
    decorDensity: 0.45,
    glowIntensity: 0.75,
    trailSegments: 4,
    contactShadows: false,
    backgroundLayers: 1,
  );

  static const QualitySettings medium = QualitySettings(
    preset: QualityPreset.medium,
    maxSwarm: 110,
    maxParticles: 200,
    maxDebris: 90,
    fieldLines: 7,
    decorDensity: 0.75,
    glowIntensity: 0.9,
    trailSegments: 6,
    contactShadows: true,
    backgroundLayers: 2,
  );

  static const QualitySettings high = QualitySettings(
    preset: QualityPreset.high,
    maxSwarm: 160,
    maxParticles: 340,
    maxDebris: 150,
    fieldLines: 10,
    decorDensity: 1.0,
    glowIntensity: 1.0,
    trailSegments: 8,
    contactShadows: true,
    backgroundLayers: 3,
  );

  static QualitySettings of(QualityPreset p) => switch (p) {
    QualityPreset.low => low,
    QualityPreset.medium => medium,
    QualityPreset.high => high,
  };
}
