/// Haptics, rate-limited and degrading gracefully.
///
/// Flutter only exposes a small set of canned patterns, so "strength" is
/// expressed by choosing between them and, for sustained effects, by pulse
/// *cadence* rather than amplitude. Devices without a vibrator simply do
/// nothing — `HapticFeedback` is a no-op there, and we additionally probe once
/// at boot so a platform channel failure can never throw into the frame loop.
library;

import 'package:flutter/services.dart';

enum HapticStrength { tick, light, medium, heavy }

class HapticsService {
  HapticsService();

  bool _supported = true;
  bool _enabled = true;
  Duration _last = Duration.zero;
  Duration _now = Duration.zero;

  /// Minimum spacing between pulses. Collecting 100 objects fires 100 capture
  /// events; without this the motor saturates into a continuous buzz and the
  /// meaningful hits (wall break, perfect release) stop being distinguishable.
  static const Duration _minGap = Duration(milliseconds: 55);

  bool get supported => _supported;

  set enabled(bool v) => _enabled = v;

  /// Called once per frame with the game clock so pacing needs no timers.
  void tickClock(Duration now) => _now = now;

  Future<void> probe() async {
    try {
      await HapticFeedback.selectionClick();
      _supported = true;
    } catch (_) {
      _supported = false;
    }
  }

  void impact(HapticStrength strength, {bool important = false}) {
    if (!_enabled || !_supported) return;
    if (!important && _now - _last < _minGap) return;
    _last = _now;
    try {
      switch (strength) {
        case HapticStrength.tick:
          HapticFeedback.selectionClick();
        case HapticStrength.light:
          HapticFeedback.lightImpact();
        case HapticStrength.medium:
          HapticFeedback.mediumImpact();
        case HapticStrength.heavy:
          HapticFeedback.heavyImpact();
      }
    } catch (_) {
      _supported = false;
    }
  }

  // ---------------------------------------------------------------------
  // Sustained charge pulse
  // ---------------------------------------------------------------------

  double _chargeAccum = 0;

  /// Pulses faster as [charge] (0..1) rises, so the player feels the build-up
  /// without looking at the HUD. At full charge this is a rhythmic ~7 Hz tap.
  void chargePulse(double charge, double dt) {
    if (!_enabled || !_supported || charge <= 0.12) {
      _chargeAccum = 0;
      return;
    }
    final rate = 2.0 + charge * charge * 5.5;
    _chargeAccum += dt * rate;
    if (_chargeAccum >= 1.0) {
      _chargeAccum -= 1.0;
      impact(
        charge > 0.85 ? HapticStrength.medium : HapticStrength.tick,
        important: true,
      );
      _last = _now;
    }
  }

  void reset() {
    _chargeAccum = 0;
    _last = Duration.zero;
  }
}
