/// The orbiting metal swarm.
///
/// Three deliberate concentric layers rather than a cloud of noise:
///
///   inner  — fast, small scrap, tight to the Core
///   middle — armour plates, slower, counter-rotating
///   outer  — loose heavy scrap, widest and slowest
///
/// Pieces never snap. A captured piece flies a *curved* magnetic trajectory to
/// its assigned slot, then eases into orbit over a blend window, so the swarm
/// grows by accretion instead of by objects teleporting into formation.
///
/// Nothing here is a rigid body: orbit position is closed-form from
/// (layer, slot index, phase), which keeps it deterministic, resettable, and
/// a couple of trig ops per piece.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../levels/level_data.dart';
import '../renderer/mesh_template.dart';

enum PieceState { idle, capturing, orbiting, launched, dead }

enum PieceKind { scrap, armour, bridge, key }

/// Layer tuning, mirroring `orbit_layers` in
/// assets/models/core/kanban_core_rig.json.
class OrbitLayer {
  const OrbitLayer({
    required this.radius,
    required this.height,
    required this.speed,
    required this.tilt,
    required this.share,
  });

  final double radius;
  final double height;
  final double speed;
  final double tilt;

  /// Fraction of the swarm this layer takes.
  final double share;
}

const List<OrbitLayer> kOrbitLayers = [
  OrbitLayer(radius: 1.02, height: 0.00, speed: 2.55, tilt: 0.10, share: 0.28),
  OrbitLayer(radius: 1.46, height: 0.08, speed: -1.70, tilt: 0.42, share: 0.34),
  OrbitLayer(radius: 1.96, height: -0.06, speed: 1.15, tilt: 0.78, share: 0.38),
];

const int kTrailSegments = 8;

class MetalPiece {
  MetalPiece({
    required this.template,
    required this.homePosition,
    required this.massClass,
    required this.kind,
    required this.scale,
    required this.tint,
  }) : position = homePosition.clone();

  final MeshTemplate template;
  final Vector3 homePosition;
  final MassClass massClass;
  final PieceKind kind;
  final double scale;
  final Vector4 tint;

  final Vector3 position;
  final Vector3 velocity = Vector3.zero();
  PieceState state = PieceState.idle;

  // Orbit assignment
  int layer = 0;
  int slot = 0;
  double tumbleX = 0;
  double tumbleY = 0;
  double tumbleRate = 1.0;

  /// Capture animation
  double captureT = 0;
  double captureDuration = 0.34;
  final Vector3 captureFrom = Vector3.zero();
  final Vector3 captureControl = Vector3.zero();

  /// 0..1 easing from the captured position into the pure orbit solution.
  double blend = 0;

  /// Decaying capture/impact flash.
  double flash = 0;

  /// Launched lifetime.
  double life = 0;
  bool hasHit = false;

  final List<Vector3> trail = List.generate(
    kTrailSegments,
    (_) => Vector3.zero(),
    growable: false,
  );
  int trailCount = 0;

  final Matrix4 _m = Matrix4.identity();

  Matrix4 transform() {
    _m.setIdentity();
    _m.setTranslation(position);
    _m.rotateY(tumbleY);
    _m.rotateX(tumbleX);
    _m.scaleByDouble(scale, scale, scale, 1.0);
    return _m;
  }

  void pushTrail() {
    for (var i = kTrailSegments - 1; i > 0; i--) {
      trail[i].setFrom(trail[i - 1]);
    }
    trail[0].setFrom(position);
    if (trailCount < kTrailSegments) trailCount++;
  }

  void clearTrail() => trailCount = 0;
}

class SwarmStats {
  int orbiting = 0;
  int launched = 0;
  int collected = 0;
  int armourOrbiting = 0;
  int bridgeOrbiting = 0;
  bool keyOrbiting = false;
}

class Swarm {
  Swarm({required this.capacity});

  int capacity;

  final List<MetalPiece> pieces = [];
  final SwarmStats stats = SwarmStats();

  double _phase = 0;
  final List<int> _layerCounts = [0, 0, 0];
  final List<int> _layerNext = [0, 0, 0];

  /// 0..1 — how full the swarm is. Drives orbit expansion and Core scale.
  double fraction = 0;

  /// Height at which a launched piece comes to rest on a deck.
  double landingY = 0.34;

  /// Whether a world position is over solid deck. Supplied by the level, since
  /// the swarm has no map of its own.
  bool Function(Vector3 position)? canLandAt;

  /// Current visual stage index, derived from level thresholds.
  int stage = 0;

  void clear() {
    pieces.clear();
    _phase = 0;
    fraction = 0;
    stage = 0;
    for (var i = 0; i < 3; i++) {
      _layerCounts[i] = 0;
      _layerNext[i] = 0;
    }
    stats
      ..orbiting = 0
      ..launched = 0
      ..collected = 0
      ..armourOrbiting = 0
      ..bridgeOrbiting = 0
      ..keyOrbiting = false;
  }

  void add(MetalPiece p) => pieces.add(p);

  /// The layer a kind belongs in. Armour rides the middle band so it reads as
  /// a shield; the key gets the inner band so it is never lost in the crowd.
  int layerFor(PieceKind kind, math.Random rng) => switch (kind) {
    PieceKind.armour => 1,
    PieceKind.key => 0,
    PieceKind.bridge => 2,
    PieceKind.scrap => rng.nextInt(3),
  };

  // -------------------------------------------------------------------------
  // Capture
  // -------------------------------------------------------------------------

  /// Begins the curved flight into orbit. Returns false when the swarm is full.
  bool capture(MetalPiece p, Vector3 corePos, math.Random rng) {
    if (stats.orbiting >= capacity) return false;

    p.layer = layerFor(p.kind, rng);
    p.slot = _layerNext[p.layer]++;
    _layerCounts[p.layer]++;

    p.state = PieceState.capturing;
    p.captureT = 0;
    // Heavier pieces take visibly longer to reel in.
    p.captureDuration = 0.24 + p.massClass.mass * 0.12;
    p.captureFrom.setFrom(p.position);

    // Control point pushed perpendicular to the approach so the path bows —
    // a straight line here is what made the old capture read as a snap.
    final toCore = corePos - p.position;
    final dist = toCore.length;
    final side = Vector3(-toCore.z, 0, toCore.x);
    if (side.length2 > 1e-6) side.normalize();
    final bow = (0.25 + dist * 0.22) * (rng.nextBool() ? 1 : -1);
    p.captureControl
      ..setFrom(p.position + toCore * 0.5)
      ..add(side * bow)
      ..y += 0.25 + rng.nextDouble() * 0.35;

    p.blend = 0;
    p.flash = 1.0;
    p.velocity.setZero();
    p.tumbleRate = 0.8 + rng.nextDouble() * 2.4;
    p.clearTrail();
    stats.collected++;
    return true;
  }

  // -------------------------------------------------------------------------
  // Release
  // -------------------------------------------------------------------------

  /// Launches every orbiting piece. [forward] is the level's forward axis.
  ///
  /// Launch direction is *biased* toward forward rather than radial: an even
  /// radial burst sprays a third of the swarm backwards where it can never
  /// hit anything, which makes a release feel weak no matter how loud it is.
  int release({
    required Vector3 corePos,
    required Vector3 forward,
    required double charge,
    required bool perfect,
    required math.Random rng,
    Vector3? target,
  }) {
    var launched = 0;
    final aim = Vector3.copy(forward)..normalize();
    if (target != null) {
      final toTarget = target - corePos;
      if (toTarget.length2 > 1e-4) {
        toTarget.normalize();
        aim
          ..scale(0.45)
          ..add(toTarget * 0.55)
          ..normalize();
      }
    }

    for (final p in pieces) {
      if (p.state != PieceState.orbiting && p.state != PieceState.capturing) {
        continue;
      }
      final out = p.position - corePos;
      if (out.length2 < 1e-6) {
        out.setValues(rng.nextDouble() - 0.5, 0.2, 1.0);
      }
      out.normalize();

      // Keep some lateral spread so the burst still reads as an explosion.
      final dir = (out * 0.38 + aim * 0.92)..normalize();
      dir.y += 0.10;
      dir.normalize();

      // Heavier pieces move slower but carry more damage (see MassClass).
      final speed =
          (16.5 + charge * 12.0 + (perfect ? 6.5 : 0.0)) /
          math.sqrt(p.massClass.mass);
      p.velocity
        ..setFrom(dir)
        ..scale(speed * (0.88 + rng.nextDouble() * 0.24));
      p.state = PieceState.launched;
      p.life = 2.4;
      p.hasHit = false;
      p.flash = perfect ? 1.0 : 0.6;
      p.tumbleRate = 5.0 + rng.nextDouble() * 9.0;
      p.clearTrail();
      launched++;
    }

    for (var i = 0; i < 3; i++) {
      _layerCounts[i] = 0;
      _layerNext[i] = 0;
    }
    return launched;
  }

  // -------------------------------------------------------------------------
  // Per-frame
  // -------------------------------------------------------------------------

  void update(
    double dt,
    Vector3 corePos, {
    required double charge,
    required List<int> stageThresholds,
    required int trailSegments,
  }) {
    _phase += dt;

    stats
      ..orbiting = 0
      ..launched = 0
      ..armourOrbiting = 0
      ..bridgeOrbiting = 0
      ..keyOrbiting = false;

    // Layer radius expands with swarm size, which is the primary read for
    // "the swarm grew".
    final expand = 1.0 + fraction * 0.42 + charge * 0.10;

    for (final p in pieces) {
      p.flash = math.max(0, p.flash - dt * 3.2);
      switch (p.state) {
        case PieceState.idle:
          break;

        case PieceState.capturing:
          p.captureT += dt / p.captureDuration;
          p.tumbleY += dt * p.tumbleRate * 3.0;
          p.tumbleX += dt * p.tumbleRate * 1.7;
          if (trailSegments > 0) p.pushTrail();
          final slotPos = _slotPosition(p, corePos, expand);
          if (p.captureT >= 1.0) {
            p.state = PieceState.orbiting;
            p.blend = 0.0;
            p.position.setFrom(slotPos);
          } else {
            // Quadratic Bezier from the capture origin, through the bowed
            // control point, to the moving slot.
            final t = _easeOutCubic(p.captureT.clamp(0.0, 1.0));
            final u = 1 - t;
            p.position
              ..setFrom(p.captureFrom * (u * u))
              ..add(p.captureControl * (2 * u * t))
              ..add(slotPos * (t * t));
          }
          _countOrbiting(p);

        case PieceState.orbiting:
          p.blend = math.min(1.0, p.blend + dt * 3.4);
          p.tumbleY += dt * p.tumbleRate * 0.55;
          p.tumbleX += dt * p.tumbleRate * 0.30;
          final slotPos = _slotPosition(p, corePos, expand);
          // Ease toward the analytic slot rather than teleporting to it.
          final k = _easeOutCubic(p.blend);
          p.position
            ..scale(1 - k * math.min(1.0, dt * 9.0))
            ..add(slotPos * (k * math.min(1.0, dt * 9.0)));
          // Once fully blended, sit exactly on the solution so orbits stay
          // crisp and the reset is bit-for-bit repeatable.
          if (p.blend >= 1.0) p.position.setFrom(slotPos);
          _countOrbiting(p);

        case PieceState.launched:
          stats.launched++;
          p.life -= dt;
          p.velocity.y -= 11.0 * dt;
          p.position.addScaled(p.velocity, dt);
          p.tumbleY += dt * p.tumbleRate;
          p.tumbleX += dt * p.tumbleRate * 0.7;
          if (trailSegments > 0) p.pushTrail();

          // Metal that lands on solid deck is recoverable. Without this a
          // release that misses destroys the ammunition permanently, and a
          // player who wastes shots at a blocking wall is soft-locked with
          // nothing left to attract.
          final landed =
              p.velocity.y < 0 &&
              p.position.y <= landingY &&
              (canLandAt?.call(p.position) ?? false);
          if (landed) {
            p.position.y = landingY;
            p.velocity.setZero();
            p.state = PieceState.idle;
            p.homePosition.setFrom(p.position);
            p.clearTrail();
          } else if (p.life <= 0 || p.position.y < -14) {
            p.state = PieceState.dead;
            p.clearTrail();
          }

        case PieceState.dead:
          break;
      }
    }

    fraction = capacity == 0 ? 0 : (stats.orbiting / capacity).clamp(0.0, 1.0);

    var s = 0;
    for (var i = 0; i < stageThresholds.length; i++) {
      if (stats.orbiting >= stageThresholds[i]) s = i + 1;
    }
    stage = s;
  }

  void _countOrbiting(MetalPiece p) {
    stats.orbiting++;
    switch (p.kind) {
      case PieceKind.armour:
        stats.armourOrbiting++;
      case PieceKind.bridge:
        stats.bridgeOrbiting++;
      case PieceKind.key:
        stats.keyOrbiting = true;
      case PieceKind.scrap:
        break;
    }
  }

  /// Closed-form orbit position for a piece's (layer, slot).
  Vector3 _slotPosition(MetalPiece p, Vector3 corePos, double expand) {
    final layer = kOrbitLayers[p.layer.clamp(0, 2)];
    final count = math.max(1, _layerCounts[p.layer.clamp(0, 2)]);

    // The key rides its own dedicated slot so it stays findable.
    if (p.kind == PieceKind.key) {
      final a = _phase * 1.9;
      return Vector3(
        corePos.x + math.cos(a) * 1.24 * expand,
        corePos.y + 0.34,
        corePos.z + math.sin(a) * 1.24 * expand,
      );
    }

    final a = _phase * layer.speed + (p.slot % count) / count * math.pi * 2;
    final r = layer.radius * expand;
    // Small per-slot vertical variation so a layer is a band, not a wire.
    final wobble = math.sin(a * 2.0 + p.slot * 1.7) * 0.10;
    return Vector3(
      corePos.x + math.cos(a) * r,
      corePos.y + layer.height + wobble + math.sin(a) * r * layer.tilt * 0.35,
      corePos.z + math.sin(a) * r * math.cos(layer.tilt),
    );
  }

  static double _easeOutCubic(double t) {
    final u = 1 - t;
    return 1 - u * u * u;
  }
}
