/// Run scoring, combo, and the perfect-release window.
///
/// The perfect window is a *band*, not a floor. Charge rises to full, holds
/// briefly, then vents back down — so "hold forever" is not a winning strategy
/// and the skill is releasing while the Core is white-hot. The window is wide
/// enough (see [perfectWindowStart] and [overchargeGrace]) to be fair on a
/// phone, and both its opening and its venting are telegraphed visually,
/// audibly and haptically.
library;

import 'dart:math' as math;

class ChargeState {
  ChargeState();

  /// 0..1.
  double charge = 0;

  /// Seconds spent at full charge. Once past [overchargeGrace] the Core vents.
  double overchargeTime = 0;

  /// True from the moment charge vents until the next hold begins.
  bool vented = false;

  static const double chargeRate = 0.62;
  static const double decayRate = 1.8;
  static const double perfectWindowStart = 0.85;
  static const double overchargeGrace = 0.85;
  static const double ventTo = 0.30;

  bool get inPerfectWindow => !vented && charge >= perfectWindowStart;

  /// 0..1 across the perfect band, for HUD display.
  double get windowProgress => vented
      ? 0
      : ((charge - perfectWindowStart) / (1.0 - perfectWindowStart)).clamp(
          0.0,
          1.0,
        );

  /// How close the overcharge is to venting, 0..1.
  double get ventPressure =>
      charge >= 0.999 ? (overchargeTime / overchargeGrace).clamp(0.0, 1.0) : 0;

  /// Returns true on the frame the Core vents.
  bool update(double dt, {required bool holding}) {
    if (!holding) {
      charge = math.max(0, charge - decayRate * dt);
      overchargeTime = 0;
      if (charge <= 0.001) vented = false;
      return false;
    }
    if (vented) {
      // Recharging after a vent is allowed, just from a lower base.
      charge = math.min(1.0, charge + chargeRate * dt);
      return false;
    }
    if (charge >= 0.999) {
      overchargeTime += dt;
      if (overchargeTime >= overchargeGrace) {
        charge = ventTo;
        overchargeTime = 0;
        vented = true;
        return true;
      }
      charge = 1.0;
      return false;
    }
    charge = math.min(1.0, charge + chargeRate * dt);
    return false;
  }

  void reset() {
    charge = 0;
    overchargeTime = 0;
    vented = false;
  }
}

class RunScore {
  int metalCollected = 0;
  int destructionScore = 0;
  int largestSwarm = 0;
  int perfectReleases = 0;
  int releases = 0;
  int blocksDestroyed = 0;
  int armourLost = 0;
  int damageTaken = 0;
  int combo = 0;
  int bestCombo = 0;
  double comboTimer = 0;
  double elapsed = 0;

  static const double comboWindow = 2.6;

  int get total =>
      metalCollected * 10 +
      destructionScore +
      perfectReleases * 250 +
      bestCombo * 40;

  int get coins => (total / 22).floor();

  /// 0..3.
  int stars(int metalTarget) {
    var s = 1;
    if (metalCollected >= metalTarget) s++;
    if (perfectReleases >= 2 && damageTaken == 0) s++;
    return s.clamp(0, 3);
  }

  double get comboMultiplier => 1.0 + math.min(combo, 20) * 0.06;

  void addCollect() {
    metalCollected++;
    if (metalCollected > 0) {
      combo++;
      if (combo > bestCombo) bestCombo = combo;
      comboTimer = comboWindow;
    }
  }

  void addDestruction(int base) {
    destructionScore += (base * comboMultiplier).round();
    combo++;
    if (combo > bestCombo) bestCombo = combo;
    comboTimer = comboWindow;
  }

  void tick(double dt) {
    elapsed += dt;
    if (comboTimer > 0) {
      comboTimer -= dt;
      if (comboTimer <= 0) combo = 0;
    }
  }

  void reset() {
    metalCollected = 0;
    destructionScore = 0;
    largestSwarm = 0;
    perfectReleases = 0;
    releases = 0;
    blocksDestroyed = 0;
    armourLost = 0;
    damageTaken = 0;
    combo = 0;
    bestCombo = 0;
    comboTimer = 0;
    elapsed = 0;
  }
}
