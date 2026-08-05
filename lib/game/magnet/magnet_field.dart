/// Attraction physics.
///
/// Tuned around one requirement: the field must feel like it responds on
/// touch-down, with no perceptible delay. That rules out a pure force model —
/// integrating acceleration from zero means a piece sits still for the first
/// few frames, which reads as input lag even when the input was handled
/// instantly.
///
/// So attraction is two terms:
///
///   * an immediate **seat** impulse applied the first frame a piece enters
///     range, scaled by proximity, so something visibly moves at once;
///   * a continuous **pull** that ramps in over [engageTime], so distant
///     pieces accelerate rather than jerk.
///
/// Mass divides both, which is what makes light scrap snap in and heavy stock
/// resist for a beat before it commits.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../levels/level_data.dart';
import '../swarm/swarm.dart';

class MagnetTuning {
  const MagnetTuning({
    this.range = 8.2,
    this.strength = 34.0,
    this.seatImpulse = 4.6,
    this.engageTime = 0.42,
    this.captureRadius = 1.25,
    this.drag = 0.055,
    this.chargeRangeBonus = 2.4,
  });

  /// Metres. Pieces beyond this are unaffected.
  final double range;

  /// Peak acceleration at the Core, in m/s^2 for a unit-mass piece.
  final double strength;

  /// One-shot velocity kick when a piece first enters the field.
  final double seatImpulse;

  /// Seconds for a piece's pull to ramp from 0 to full.
  final double engageTime;

  /// Distance at which a piece is taken into orbit.
  final double captureRadius;

  /// Velocity retained per second (exponential).
  final double drag;

  /// Extra range at full charge.
  final double chargeRangeBonus;
}

class MagnetField {
  MagnetField({this.tuning = const MagnetTuning()});

  MagnetTuning tuning;

  /// Per-piece engagement ramp, keyed by identity.
  final Map<MetalPiece, double> _engaged = {};

  double rangeAt(double charge) =>
      tuning.range + charge.clamp(0.0, 1.0) * tuning.chargeRangeBonus;

  /// Whether [piece] is inside the field.
  bool inRange(MetalPiece piece, Vector3 corePos, double charge) =>
      (corePos - piece.position).length <= rangeAt(charge);

  /// Normalised 0..1 pull strength at [distance]. 1 at the Core, 0 at the edge.
  double falloff(double distance, double charge) {
    final r = rangeAt(charge);
    if (distance >= r) return 0;
    final t = 1.0 - (distance / r);
    // Slightly super-linear so the field has a clear "grabby" core without a
    // hard singularity at distance 0.
    return t * t * (0.55 + 0.45 * t);
  }

  /// Advances one free piece. Returns true when it should be captured.
  bool apply(
    MetalPiece piece,
    Vector3 corePos,
    double dt, {
    required bool attracting,
    required double charge,
  }) {
    if (!attracting) {
      _engaged.remove(piece);
      // Settle: bleed off velocity and drift home so a released field does not
      // leave debris hanging in mid-air.
      piece.velocity.scale(math.pow(0.02, dt).toDouble());
      piece.position.addScaled(piece.velocity, dt);
      final home = piece.homePosition - piece.position;
      if (home.length2 > 1e-4) {
        piece.position.addScaled(home, math.min(1.0, dt * 1.6));
      }
      return false;
    }

    final delta = corePos - piece.position;
    final dist = delta.length;
    final r = rangeAt(charge);
    if (dist > r) {
      _engaged.remove(piece);
      piece.velocity.scale(math.pow(0.25, dt).toDouble());
      piece.position.addScaled(piece.velocity, dt);
      return false;
    }

    if (dist > 1e-5) delta.scale(1.0 / dist);
    final mass = piece.massClass.mass;
    final near = falloff(dist, charge);

    // First frame in range: seat the piece so motion starts immediately.
    final wasEngaged = _engaged.containsKey(piece);
    if (!wasEngaged) {
      piece.velocity.addScaled(delta, tuning.seatImpulse * near / mass);
      _engaged[piece] = 0.0;
      piece.state = PieceState.idle;
    }

    final ramp = math.min(1.0, (_engaged[piece]! + dt) / tuning.engageTime);
    _engaged[piece] = _engaged[piece]! + dt;

    final accel = tuning.strength * near * ramp / mass;
    piece.velocity.addScaled(delta, accel * dt);
    piece.velocity.scale(math.pow(tuning.drag, dt).toDouble());
    piece.position.addScaled(piece.velocity, dt);

    return dist < tuning.captureRadius;
  }

  /// Forgets ramp state. Call on level reset so retries are deterministic.
  void reset() => _engaged.clear();

  void forget(MetalPiece piece) => _engaged.remove(piece);

  /// How long a piece of [massClass] takes to travel [distance] to the Core
  /// under a sustained field. Used by tests and by level tuning; not by the
  /// simulation itself.
  double estimateTravelTime(
    double distance,
    MassClass massClass, {
    double charge = 0,
  }) {
    var d = distance;
    var v = 0.0;
    var t = 0.0;
    const dt = 1 / 120.0;
    final mass = massClass.mass;
    var engaged = 0.0;
    var seated = false;
    while (d > tuning.captureRadius && t < 12.0) {
      final near = falloff(d, charge);
      if (!seated) {
        v += tuning.seatImpulse * near / mass;
        seated = true;
      }
      engaged += dt;
      final ramp = math.min(1.0, engaged / tuning.engageTime);
      v += tuning.strength * near * ramp / mass * dt;
      v *= math.pow(tuning.drag, dt).toDouble();
      d -= v * dt;
      t += dt;
    }
    return t;
  }
}
