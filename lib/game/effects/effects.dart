/// Pooled visual effects.
///
/// Everything here is real geometry stamped into the batchers — low-poly mesh
/// particles, ribbon trails, expanding ring meshes and tumbling debris. There
/// are deliberately no flat translucent circles: a billboarded disc reads as a
/// sticker at this camera angle, and the design brief calls them out by name.
///
/// Every particle comes from a fixed pool sized by the quality preset, so a
/// hundred-object release allocates nothing.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../renderer/mesh_batcher.dart';
import '../renderer/mesh_template.dart';

enum ParticleShape { shard, spark, cube, ring, ribbon }

class Particle {
  final Vector3 position = Vector3.zero();
  final Vector3 velocity = Vector3.zero();
  final Vector4 colour = Vector4(1, 1, 1, 1);
  double life = 0;
  double maxLife = 1;
  double size = 0.1;
  double sizeEnd = 0.0;
  double spin = 0;
  double spinRate = 0;
  double gravity = 0;
  double drag = 0.5;
  ParticleShape shape = ParticleShape.shard;
  bool alive = false;

  final Matrix4 _m = Matrix4.identity();

  double get t => maxLife <= 0 ? 1 : 1.0 - (life / maxLife);

  Matrix4 transform() {
    final s = size + (sizeEnd - size) * t;
    _m.setIdentity();
    _m.setTranslation(position);
    _m.rotateY(spin);
    _m.rotateX(spin * 0.6);
    _m.scaleByDouble(s, s, s, 1.0);
    return _m;
  }
}

/// An expanding ring — shockwaves, portal pulses, swarm-stage rings.
class RingWave {
  final Vector3 position = Vector3.zero();
  final Vector4 colour = Vector4(1, 1, 1, 1);
  double life = 0;
  double maxLife = 1;
  double radius = 0;
  double radiusEnd = 4;
  double thickness = 0.16;
  double tiltX = 0;
  bool alive = false;

  double get t => maxLife <= 0 ? 1 : 1.0 - (life / maxLife);
}

class Effects {
  Effects({required int particleCapacity, required int debrisCapacity})
    : _particles = List.generate(
        particleCapacity,
        (_) => Particle(),
        growable: false,
      ),
      _debris = List.generate(
        debrisCapacity,
        (_) => Particle(),
        growable: false,
      ),
      _rings = List.generate(12, (_) => RingWave(), growable: false);

  final List<Particle> _particles;
  final List<Particle> _debris;
  final List<RingWave> _rings;
  final math.Random _rng = math.Random(9931);

  /// Templates, supplied once at load from the Blender library.
  late MeshTemplate shardTemplate;
  late MeshTemplate sparkTemplate;
  late MeshTemplate cubeTemplate;
  late MeshTemplate ringTemplate;

  int get liveParticles => _particles.where((p) => p.alive).length;
  int get liveDebris => _debris.where((p) => p.alive).length;

  void setTemplates({
    required MeshTemplate shard,
    required MeshTemplate spark,
    required MeshTemplate cube,
    required MeshTemplate ring,
  }) {
    shardTemplate = shard;
    sparkTemplate = spark;
    cubeTemplate = cube;
    ringTemplate = ring;
  }

  void clear() {
    for (final p in _particles) {
      p.alive = false;
    }
    for (final d in _debris) {
      d.alive = false;
    }
    for (final r in _rings) {
      r.alive = false;
    }
  }

  Particle? _free(List<Particle> pool) {
    for (final p in pool) {
      if (!p.alive) return p;
    }
    return null;
  }

  RingWave? _freeRing() {
    for (final r in _rings) {
      if (!r.alive) return r;
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Emitters
  // -------------------------------------------------------------------------

  void burst({
    required Vector3 at,
    required int count,
    required Vector4 colour,
    double speed = 4.0,
    double spread = 1.0,
    double size = 0.09,
    double sizeEnd = 0.0,
    double life = 0.6,
    double gravity = 6.0,
    double drag = 0.25,
    ParticleShape shape = ParticleShape.shard,
    Vector3? direction,
    double intensity = 1.0,
    bool useDebrisPool = false,
  }) {
    final n = (count * intensity).round();
    final pool = useDebrisPool ? _debris : _particles;
    for (var i = 0; i < n; i++) {
      final p = _free(pool);
      if (p == null) return;
      p.alive = true;
      p.position.setFrom(at);
      final dir = direction == null
          ? Vector3(
              _rng.nextDouble() * 2 - 1,
              _rng.nextDouble() * 2 - 1,
              _rng.nextDouble() * 2 - 1,
            )
          : (Vector3.copy(direction)..add(
              Vector3(
                (_rng.nextDouble() * 2 - 1) * spread,
                (_rng.nextDouble() * 2 - 1) * spread,
                (_rng.nextDouble() * 2 - 1) * spread,
              ),
            ));
      if (dir.length2 < 1e-6) dir.setValues(0, 1, 0);
      dir.normalize();
      p.velocity
        ..setFrom(dir)
        ..scale(speed * (0.55 + _rng.nextDouble() * 0.9));
      p.colour.setFrom(colour);
      p.maxLife = life * (0.7 + _rng.nextDouble() * 0.6);
      p.life = p.maxLife;
      p.size = size * (0.7 + _rng.nextDouble() * 0.7);
      p.sizeEnd = sizeEnd;
      p.spin = _rng.nextDouble() * math.pi * 2;
      p.spinRate = (_rng.nextDouble() * 2 - 1) * 9.0;
      p.gravity = gravity;
      p.drag = drag;
      p.shape = shape;
    }
  }

  void ringWave({
    required Vector3 at,
    required Vector4 colour,
    double radius = 0.4,
    double radiusEnd = 5.0,
    double thickness = 0.18,
    double life = 0.55,
    double tiltX = 0,
  }) {
    final r = _freeRing();
    if (r == null) return;
    r.alive = true;
    r.position.setFrom(at);
    r.colour.setFrom(colour);
    r.radius = radius;
    r.radiusEnd = radiusEnd;
    r.thickness = thickness;
    r.maxLife = life;
    r.life = life;
    r.tiltX = tiltX;
  }

  // -------------------------------------------------------------------------
  // Simulation
  // -------------------------------------------------------------------------

  void update(double dt) {
    void step(List<Particle> pool) {
      for (final p in pool) {
        if (!p.alive) continue;
        p.life -= dt;
        if (p.life <= 0) {
          p.alive = false;
          continue;
        }
        p.velocity.y -= p.gravity * dt;
        p.velocity.scale(math.pow(p.drag, dt).toDouble());
        p.position.addScaled(p.velocity, dt);
        p.spin += p.spinRate * dt;
      }
    }

    step(_particles);
    step(_debris);

    for (final r in _rings) {
      if (!r.alive) continue;
      r.life -= dt;
      if (r.life <= 0) r.alive = false;
    }
  }

  // -------------------------------------------------------------------------
  // Rendering
  // -------------------------------------------------------------------------

  /// Stamps every live effect into [glow] (emissive, alpha blended) and
  /// [opaque] (lit debris).
  void render(MeshBatcher glow, MeshBatcher opaque) {
    final tint = Vector4(1, 1, 1, 1);

    for (final p in _particles) {
      if (!p.alive) continue;
      final fade = math.pow(1.0 - p.t, 0.65).toDouble();
      tint.setValues(p.colour.x, p.colour.y, p.colour.z, p.colour.w * fade);
      glow.add(
        _templateFor(p.shape),
        p.transform(),
        tint,
        useTemplateColors: false,
      );
    }

    for (final d in _debris) {
      if (!d.alive) continue;
      tint.setValues(d.colour.x, d.colour.y, d.colour.z, 1.0);
      opaque.add(
        _templateFor(d.shape),
        d.transform(),
        tint,
        useTemplateColors: false,
      );
    }

    for (final r in _rings) {
      if (!r.alive) continue;
      final t = r.t;
      final radius = r.radius + (r.radiusEnd - r.radius) * _easeOut(t);
      final fade = (1.0 - t) * (1.0 - t);
      tint.setValues(r.colour.x, r.colour.y, r.colour.z, r.colour.w * fade);
      // The ring template is a unit torus in XZ; scaling non-uniformly keeps
      // it thin as it expands so it reads as a shock front, not a doughnut.
      final m = Matrix4.identity()
        ..setTranslation(r.position)
        ..rotateX(r.tiltX)
        ..scaleByDouble(radius, r.thickness * (1.0 - t * 0.55), radius, 1.0);
      glow.add(ringTemplate, m, tint, useTemplateColors: false);
    }
  }

  MeshTemplate _templateFor(ParticleShape s) => switch (s) {
    ParticleShape.shard => shardTemplate,
    ParticleShape.spark => sparkTemplate,
    ParticleShape.cube => cubeTemplate,
    ParticleShape.ring => ringTemplate,
    ParticleShape.ribbon => sparkTemplate,
  };

  static double _easeOut(double t) {
    final u = 1 - t;
    return 1 - u * u * u;
  }
}

/// Draws a tapering ribbon through a piece's recorded trail points.
///
/// Trails are built from real triangles rather than a sprite so they hold up
/// against the camera angle and never billboard into a flat streak.
void stampTrail(
  MeshBatcher glow,
  MeshTemplate segmentTemplate,
  List<Vector3> points,
  int count,
  Vector4 colour, {
  double width = 0.075,
  int maxSegments = 8,
}) {
  if (count < 2) return;
  final n = math.min(count, maxSegments);
  final tint = Vector4.zero();
  final m = Matrix4.identity();
  for (var i = 0; i < n - 1; i++) {
    final a = points[i];
    final b = points[i + 1];
    final delta = b - a;
    final len = delta.length;
    if (len < 1e-4) continue;
    final f = 1.0 - (i / n);
    tint.setValues(colour.x, colour.y, colour.z, colour.w * f * f);
    final mid = (a + b)..scale(0.5);

    m.setIdentity();
    m.setTranslation(mid);
    // Orient the segment along the trail direction.
    final dir = delta / len;
    final yaw = math.atan2(dir.x, dir.z);
    final pitch = math.asin(dir.y.clamp(-1.0, 1.0));
    m.rotateY(yaw);
    m.rotateX(-pitch);
    final w = width * f;
    m.scaleByDouble(w, w, len * 0.55, 1.0);
    glow.add(segmentTemplate, m, tint, useTemplateColors: false);
  }
}
