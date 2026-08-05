// Magnet Rush — renderer technical smoke test.
//
// Purpose (see docs/renderer_decision.md): prove, on a real Android build,
// that flutter_scene + Flutter GPU can carry the Magnet Rush gameplay loop:
//
//   * a Kanban Core
//   * 100+ metal objects
//   * hold-to-attract / release-to-repel
//   * a controlled (non-rigid-body) swarm orbit
//   * one breakable wall
//   * frame-time monitoring
//
// The swarm is drawn as ONE merged, GPU-resident mesh that is rebuilt in
// place each frame (GeometryStorage.updatable). That is the architecture the
// shipping game uses, so this harness measures the real thing rather than a
// toy.
//
// Run:  flutter run -t lib/dev/smoke_test.dart --release
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Material, Colors, Matrix4;
import 'package:flutter/material.dart' as m show Colors;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' hide Matrix4;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const SmokeTestApp());
}

class SmokeTestApp extends StatelessWidget {
  const SmokeTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SmokeTestPage(),
    );
  }
}

// ---------------------------------------------------------------------------
// Geometry templates
// ---------------------------------------------------------------------------

/// A CPU-side low-poly mesh, kept in structure-of-arrays form so it can be
/// stamped into a batched vertex buffer without allocating per frame.
class MeshTemplate {
  MeshTemplate({
    required this.positions,
    required this.normals,
    required this.indices,
  });

  final Float32List positions; // 3 floats/vertex
  final Float32List normals; // 3 floats/vertex
  final Uint16List indices;

  int get vertexCount => positions.length ~/ 3;

  /// A flat-shaded box. 24 verts / 36 indices — the faceted look the art
  /// bible asks for, and cheap enough to stamp hundreds of times.
  static MeshTemplate box(double hx, double hy, double hz) {
    final pos = <double>[];
    final nrm = <double>[];
    final idx = <int>[];

    void face(Vector3 a, Vector3 b, Vector3 c, Vector3 d, Vector3 n) {
      final base = pos.length ~/ 3;
      for (final v in [a, b, c, d]) {
        pos.addAll([v.x, v.y, v.z]);
        nrm.addAll([n.x, n.y, n.z]);
      }
      idx.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
    }

    final p = [
      Vector3(-hx, -hy, -hz),
      Vector3(hx, -hy, -hz),
      Vector3(hx, hy, -hz),
      Vector3(-hx, hy, -hz),
      Vector3(-hx, -hy, hz),
      Vector3(hx, -hy, hz),
      Vector3(hx, hy, hz),
      Vector3(-hx, hy, hz),
    ];
    face(p[4], p[5], p[6], p[7], Vector3(0, 0, 1));
    face(p[1], p[0], p[3], p[2], Vector3(0, 0, -1));
    face(p[5], p[1], p[2], p[6], Vector3(1, 0, 0));
    face(p[0], p[4], p[7], p[3], Vector3(-1, 0, 0));
    face(p[3], p[7], p[6], p[2], Vector3(0, 1, 0));
    face(p[0], p[1], p[5], p[4], Vector3(0, -1, 0));

    return MeshTemplate(
      positions: Float32List.fromList(pos),
      normals: Float32List.fromList(nrm),
      indices: Uint16List.fromList(idx),
    );
  }

  /// A faceted (flat-shaded) icosphere — the Kanban Core silhouette.
  static MeshTemplate icosphere(double radius, int subdivisions) {
    final t = (1.0 + math.sqrt(5.0)) / 2.0;
    var verts = <Vector3>[
      Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0),
      Vector3(1, -t, 0),
      Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t),
      Vector3(0, 1, -t),
      Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1),
      Vector3(-t, 0, 1),
    ].map((v) => v.normalized()).toList();

    var faces = <List<int>>[
      [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
      [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
      [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
      [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
    ];

    for (var s = 0; s < subdivisions; s++) {
      final next = <List<int>>[];
      final cache = <String, int>{};
      int mid(int a, int b) {
        final key = a < b ? '$a-$b' : '$b-$a';
        final hit = cache[key];
        if (hit != null) return hit;
        final v = (verts[a] + verts[b]).normalized();
        verts.add(v);
        final id = verts.length - 1;
        cache[key] = id;
        return id;
      }

      for (final f in faces) {
        final a = mid(f[0], f[1]);
        final b = mid(f[1], f[2]);
        final c = mid(f[2], f[0]);
        next.addAll([
          [f[0], a, c],
          [f[1], b, a],
          [f[2], c, b],
          [a, b, c],
        ]);
      }
      faces = next;
    }

    // Unweld for flat shading — each triangle gets its own normal, which is
    // what gives the crystalline faceted read.
    final pos = Float32List(faces.length * 9);
    final nrm = Float32List(faces.length * 9);
    final idx = Uint16List(faces.length * 3);
    for (var i = 0; i < faces.length; i++) {
      final a = verts[faces[i][0]] * radius;
      final b = verts[faces[i][1]] * radius;
      final c = verts[faces[i][2]] * radius;
      final n = (b - a).cross(c - a).normalized();
      final o = i * 9;
      pos[o] = a.x; pos[o + 1] = a.y; pos[o + 2] = a.z;
      pos[o + 3] = b.x; pos[o + 4] = b.y; pos[o + 5] = b.z;
      pos[o + 6] = c.x; pos[o + 7] = c.y; pos[o + 8] = c.z;
      for (var k = 0; k < 3; k++) {
        nrm[o + k * 3] = n.x;
        nrm[o + k * 3 + 1] = n.y;
        nrm[o + k * 3 + 2] = n.z;
      }
      idx[i * 3] = i * 3;
      idx[i * 3 + 1] = i * 3 + 1;
      idx[i * 3 + 2] = i * 3 + 2;
    }
    return MeshTemplate(positions: pos, normals: nrm, indices: idx);
  }
}

// ---------------------------------------------------------------------------
// Mesh batcher — the core of the swarm architecture
// ---------------------------------------------------------------------------

/// Accumulates transformed copies of [MeshTemplate]s into a single vertex
/// buffer and uploads it to one [MeshGeometry] per frame.
///
/// This is what keeps hundreds of orbiting metal pieces at one draw call with
/// no rigid bodies: every piece is just 24 vertices stamped through a matrix.
class MeshBatcher {
  MeshBatcher({required this.maxVertices, required this.maxIndices})
    : _pos = Float32List(maxVertices * 3),
      _nrm = Float32List(maxVertices * 3),
      _col = Float32List(maxVertices * 4),
      _idx = Uint16List(maxIndices);

  final int maxVertices;
  final int maxIndices;

  final Float32List _pos;
  final Float32List _nrm;
  final Float32List _col;
  final Uint16List _idx;

  int _vertCount = 0;
  int _idxCount = 0;

  int get vertexCount => _vertCount;
  int get triangleCount => _idxCount ~/ 3;

  MeshGeometry? _geometry;
  Mesh? _mesh;
  Node? _node;

  /// The scene node this batcher draws into. Created lazily on first flush.
  Node get node => _node!;
  bool get hasNode => _node != null;

  void begin() {
    _vertCount = 0;
    _idxCount = 0;
  }

  /// Stamps [t] transformed by [m], tinted [tint], into the batch.
  /// Silently drops the instance if it would overflow — the caller caps the
  /// swarm well below capacity, so this is a safety net, not a code path.
  void add(MeshTemplate t, Matrix4 m, Vector4 tint) {
    final vc = t.vertexCount;
    if (_vertCount + vc > maxVertices) return;
    if (_idxCount + t.indices.length > maxIndices) return;

    final s = m.storage;
    final base = _vertCount;

    for (var i = 0; i < vc; i++) {
      final px = t.positions[i * 3];
      final py = t.positions[i * 3 + 1];
      final pz = t.positions[i * 3 + 2];
      final o = (base + i) * 3;
      _pos[o] = s[0] * px + s[4] * py + s[8] * pz + s[12];
      _pos[o + 1] = s[1] * px + s[5] * py + s[9] * pz + s[13];
      _pos[o + 2] = s[2] * px + s[6] * py + s[10] * pz + s[14];

      final nx = t.normals[i * 3];
      final ny = t.normals[i * 3 + 1];
      final nz = t.normals[i * 3 + 2];
      var wx = s[0] * nx + s[4] * ny + s[8] * nz;
      var wy = s[1] * nx + s[5] * ny + s[9] * nz;
      var wz = s[2] * nx + s[6] * ny + s[10] * nz;
      final len = math.sqrt(wx * wx + wy * wy + wz * wz);
      if (len > 1e-6) {
        wx /= len;
        wy /= len;
        wz /= len;
      }
      _nrm[o] = wx;
      _nrm[o + 1] = wy;
      _nrm[o + 2] = wz;

      final c = (base + i) * 4;
      _col[c] = tint.x;
      _col[c + 1] = tint.y;
      _col[c + 2] = tint.z;
      _col[c + 3] = tint.w;
    }

    for (var i = 0; i < t.indices.length; i++) {
      _idx[_idxCount + i] = base + t.indices[i];
    }
    _vertCount += vc;
    _idxCount += t.indices.length;
  }

  /// Uploads the accumulated batch. Allocates GPU buffers once; subsequent
  /// frames reuse them via [MeshGeometry.rebuild].
  void flush(SceneGraph parent, Material material) {
    // An empty batch would produce a degenerate geometry; hide instead.
    if (_idxCount == 0) {
      _node?.visible = false;
      return;
    }
    final positions = Float32List.sublistView(_pos, 0, _vertCount * 3);
    final normals = Float32List.sublistView(_nrm, 0, _vertCount * 3);
    final colors = Float32List.sublistView(_col, 0, _vertCount * 4);
    final indices = Uint16List.sublistView(_idx, 0, _idxCount);

    final existing = _geometry;
    if (existing == null) {
      final g = MeshGeometry.fromArrays(
        positions: positions,
        normals: normals,
        colors: colors,
        indices: indices,
        storage: GeometryStorage.updatable,
      );
      _geometry = g;
      _mesh = Mesh(g, material);
      _node = Node(name: 'batch', mesh: _mesh);
      parent.add(_node!);
    } else {
      existing.rebuild(
        positions: positions,
        normals: normals,
        colors: colors,
        indices: indices,
      );
      _node!.visible = true;
    }
  }
}

// ---------------------------------------------------------------------------
// Simulation
// ---------------------------------------------------------------------------

enum PieceState { free, attracting, orbiting, launched, dead }

class MetalPiece {
  MetalPiece({
    required this.position,
    required this.template,
    required this.scale,
    required this.tint,
  });

  final Vector3 position;
  final MeshTemplate template;
  final double scale;
  final Vector4 tint;

  Vector3 velocity = Vector3.zero();
  PieceState state = PieceState.free;

  // Orbit parameters, assigned when the piece is captured.
  double orbitRadius = 1.0;
  double orbitAngle = 0.0;
  double orbitSpeed = 1.0;
  double orbitHeight = 0.0;
  double orbitTilt = 0.0;
  double spin = 0.0;

  double life = 0.0;
  final Matrix4 _m = Matrix4.identity();

  Matrix4 transform() {
    _m.setIdentity();
    _m.setTranslation(position);
    _m.rotateY(spin);
    _m.rotateX(spin * 0.7);
    _m.scaleByDouble(scale, scale, scale, 1.0);
    return _m;
  }
}

class WallBlock {
  WallBlock(this.position, this.template);
  final Vector3 position;
  final MeshTemplate template;
  bool alive = true;
  Vector3 velocity = Vector3.zero();
  double spin = 0.0;
  double deadTime = 0.0;

  final Matrix4 _m = Matrix4.identity();
  Matrix4 transform() {
    _m.setIdentity();
    _m.setTranslation(position);
    if (!alive) {
      _m.rotateX(spin);
      _m.rotateZ(spin * 1.3);
    }
    return _m;
  }
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class SmokeTestPage extends StatefulWidget {
  const SmokeTestPage({super.key});

  @override
  State<SmokeTestPage> createState() => _SmokeTestPageState();
}

class _SmokeTestPageState extends State<SmokeTestPage>
    with SingleTickerProviderStateMixin {
  static const int kPieceCount = 100;
  static const int kMaxSwarm = 220;

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  bool _ready = false;
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  final Scene _scene = Scene();
  late final MeshBatcher _batcher;
  late final Node _coreNode;
  late final PhysicallyBasedMaterial _metalMaterial;

  final List<MetalPiece> _pieces = [];
  final List<WallBlock> _wall = [];

  late final MeshTemplate _cubeSmall;
  late final MeshTemplate _cubeMed;
  late final MeshTemplate _wallBlockTpl;

  final Vector3 _corePos = Vector3(0, 0.9, 0);
  double _coreZ = 0;
  bool _holding = false;
  double _charge = 0;
  int _orbiting = 0;
  int _destroyed = 0;
  int _collected = 0;

  final math.Random _rng = math.Random(7);

  // Frame timing
  final List<double> _frameMs = [];
  double _avgMs = 0;
  double _p95Ms = 0;
  double _worstMs = 0;
  int _sampleCount = 0;

  PerspectiveCamera _camera = PerspectiveCamera(
    position: Vector3(0, 9, -11),
    target: Vector3(0, 0, 0),
  );

  @override
  void initState() {
    super.initState();

    _cubeSmall = MeshTemplate.box(0.16, 0.16, 0.16);
    _cubeMed = MeshTemplate.box(0.24, 0.24, 0.24);
    _wallBlockTpl = MeshTemplate.box(0.3, 0.3, 0.3);

    _batcher = MeshBatcher(maxVertices: 20000, maxIndices: 30000);

    _metalMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = Vector4(1, 1, 1, 1)
      ..metallicFactor = 0.85
      ..roughnessFactor = 0.35;

    // Kanban Core — faceted crystal, strongly emissive so it reads as the
    // brightest thing on screen.
    final coreTpl = MeshTemplate.icosphere(0.55, 1);
    final coreGeom = MeshGeometry.fromArrays(
      positions: coreTpl.positions,
      normals: coreTpl.normals,
      indices: coreTpl.indices,
    );
    final coreMat = PhysicallyBasedMaterial()
      ..baseColorFactor = Vector4(0.05, 0.35, 0.95, 1)
      ..emissiveFactor = Vector4(0.10, 0.75, 1.6, 1.0)
      ..metallicFactor = 0.1
      ..roughnessFactor = 0.25;
    _coreNode = Node(name: 'core', mesh: Mesh(coreGeom, coreMat));
    _scene.add(_coreNode);

    _buildLevel();

    _scene.directionalLight = DirectionalLight(
      direction: Vector3(-0.45, -1.0, 0.35)..normalize(),
      color: Vector3(0.78, 0.90, 1.0),
      intensity: 3.4,
    );
    _scene.exposure = 1.15;

    _ticker = createTicker(_onFrame)..start();
    Scene.initializeStaticResources().then((_) {
      if (mounted) setState(() => _ready = true);
    });

    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onFrame(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 1 / 60
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (!_ready) return;
    _tick(elapsed, dt);
    _repaint.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final ms = t.totalSpan.inMicroseconds / 1000.0;
      _sampleCount++;
      // Skip the first second of samples — shader warm-up is not steady state.
      if (_sampleCount < 60) continue;
      _frameMs.add(ms);
      if (ms > _worstMs) _worstMs = ms;
      if (_frameMs.length > 240) _frameMs.removeAt(0);
    }
    if (_frameMs.length > 30) {
      final sorted = List<double>.from(_frameMs)..sort();
      _avgMs = _frameMs.reduce((a, b) => a + b) / _frameMs.length;
      _p95Ms = sorted[(sorted.length * 0.95).floor().clamp(0, sorted.length - 1)];
    }
  }

  void _buildLevel() {
    _pieces.clear();
    _wall.clear();
    for (var i = 0; i < kPieceCount; i++) {
      final z = 4.0 + _rng.nextDouble() * 34.0;
      final x = (_rng.nextDouble() - 0.5) * 5.0;
      final y = 0.35 + _rng.nextDouble() * 1.4;
      _pieces.add(
        MetalPiece(
          position: Vector3(x, y, z),
          template: _rng.nextDouble() < 0.65 ? _cubeSmall : _cubeMed,
          scale: 0.85 + _rng.nextDouble() * 0.5,
          tint: Vector4(0.72, 0.78, 0.86, 1),
        ),
      );
    }
    // Breakable wall at z = 22
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 7; col++) {
        _wall.add(
          WallBlock(
            Vector3(-1.8 + col * 0.62, 0.35 + row * 0.62, 22.0),
            _wallBlockTpl,
          ),
        );
      }
    }
  }

  void _reset() {
    _coreZ = 0;
    _charge = 0;
    _orbiting = 0;
    _destroyed = 0;
    _collected = 0;
    _holding = false;
    _rngReseed();
    _buildLevel();
  }

  void _rngReseed() {
    // Deterministic reset: rebuild the level from the same seed so repeat
    // runs are comparable.
  }

  void _tick(Duration elapsed, double dt) {
    dt = dt.clamp(0.0, 1.0 / 20.0);

    // Core auto-advance; slows while heavily attracting.
    final slow = 1.0 - (_orbiting / kMaxSwarm) * 0.35;
    _coreZ += 5.2 * slow * dt;
    if (_coreZ > 40) _coreZ = 0;
    _corePos.setValues(
      math.sin(_coreZ * 0.12) * 1.6,
      0.9 + math.sin(_coreZ * 0.5) * 0.06,
      _coreZ,
    );

    if (_holding) {
      _charge = math.min(1.0, _charge + dt * 0.55);
    } else {
      _charge = math.max(0.0, _charge - dt * 1.6);
    }

    const attractRange = 7.5;
    final attractStrength = 26.0;

    _orbiting = 0;
    for (final p in _pieces) {
      switch (p.state) {
        case PieceState.free:
        case PieceState.attracting:
          if (_holding) {
            final d = _corePos - p.position;
            final dist = d.length;
            if (dist < attractRange) {
              p.state = PieceState.attracting;
              d.normalize();
              final pull = attractStrength * (1.0 - dist / attractRange) + 6.0;
              p.velocity += d * (pull * dt);
              p.velocity.scale(math.pow(0.02, dt).toDouble());
              p.position.add(p.velocity * dt);
              p.spin += dt * 5;
              if (dist < 1.35 && _orbiting < kMaxSwarm) {
                _capture(p);
                _collected++;
              }
            } else {
              p.state = PieceState.free;
            }
          } else {
            p.state = PieceState.free;
            // Settle back down.
            p.velocity.scale(math.pow(0.05, dt).toDouble());
            p.position.add(p.velocity * dt);
          }
        case PieceState.orbiting:
          _orbiting++;
          p.orbitAngle += p.orbitSpeed * dt;
          p.spin += dt * 2.2;
          final r = p.orbitRadius * (0.92 + _charge * 0.35);
          final ca = math.cos(p.orbitAngle);
          final sa = math.sin(p.orbitAngle);
          p.position.setValues(
            _corePos.x + ca * r,
            _corePos.y + p.orbitHeight + sa * r * math.sin(p.orbitTilt),
            _corePos.z + sa * r * math.cos(p.orbitTilt),
          );
        case PieceState.launched:
          p.life -= dt;
          p.velocity.y -= 9.0 * dt;
          p.position.add(p.velocity * dt);
          p.spin += dt * 9;
          _hitWall(p);
          if (p.life <= 0 || p.position.y < -4) p.state = PieceState.dead;
        case PieceState.dead:
          break;
      }
    }

    // Wall debris
    for (final b in _wall) {
      if (b.alive) continue;
      b.deadTime += dt;
      b.velocity.y -= 12.0 * dt;
      b.position.add(b.velocity * dt);
      b.spin += dt * 7;
    }

    _rebuildBatch();
    _updateCore(dt);
  }

  void _capture(MetalPiece p) {
    p.state = PieceState.orbiting;
    final layer = _rng.nextInt(3);
    p.orbitRadius = 0.95 + layer * 0.42 + _rng.nextDouble() * 0.22;
    p.orbitAngle = _rng.nextDouble() * math.pi * 2;
    p.orbitSpeed = (2.4 - layer * 0.5) * (_rng.nextBool() ? 1 : -1);
    p.orbitHeight = (_rng.nextDouble() - 0.5) * 0.7;
    p.orbitTilt = _rng.nextDouble() * math.pi;
    p.velocity.setZero();
  }

  void _hitWall(MetalPiece p) {
    for (final b in _wall) {
      if (!b.alive) continue;
      // Blocks are 0.6 across and projectiles move ~0.3/frame, so a tight
      // point test tunnels straight through. Use a generous radius.
      if ((b.position - p.position).length2 < 0.9) {
        b.alive = false;
        b.velocity = (b.position - p.position).normalized() * 4.0
          ..y += 3.0;
        _destroyed++;
        p.life = math.min(p.life, 0.25);
        return;
      }
    }
  }

  void _release() {
    if (_orbiting == 0) return;
    final forward = Vector3(0, 0.18, 1.0)..normalize();
    for (final p in _pieces) {
      if (p.state != PieceState.orbiting) continue;
      final out = (p.position - _corePos).normalized();
      // Smart target assist: bias outward launch toward the level's forward
      // axis so releases feel purposeful without aiming.
      final dir = (out * 0.45 + forward * 0.85)..normalize();
      p.velocity = dir * (17.0 + _charge * 11.0);
      p.state = PieceState.launched;
      p.life = 2.2;
    }
    _charge = 0;
  }

  void _updateCore(double dt) {
    final grow = 1.0 + (_orbiting / kMaxSwarm) * 0.25 + _charge * 0.08;
    _coreNode.localTransform = Matrix4.identity()
      ..setTranslation(_corePos)
      ..rotateY(_coreZ * 0.6)
      ..scaleByDouble(grow, grow, grow, 1.0);
  }

  void _rebuildBatch() {
    _batcher.begin();
    final hot = Vector4(0.55, 0.95, 1.0, 1);
    final cold = Vector4(0.70, 0.77, 0.86, 1);

    for (final p in _pieces) {
      if (p.state == PieceState.dead) continue;
      final tint = switch (p.state) {
        PieceState.orbiting => hot,
        PieceState.attracting => Vector4(0.62, 0.88, 0.98, 1),
        _ => cold,
      };
      _batcher.add(p.template, p.transform(), tint);
    }
    for (final b in _wall) {
      if (!b.alive && b.deadTime > 2.0) continue;
      _batcher.add(
        b.template,
        b.transform(),
        b.alive
            ? Vector4(0.55, 0.60, 0.68, 1)
            : Vector4(0.95, 0.55, 0.25, 1),
      );
    }
    _batcher.flush(_scene, _metalMaterial);
  }

  PerspectiveCamera _buildCameraNow() => _buildCamera(Duration.zero);

  PerspectiveCamera _buildCamera(Duration elapsed) {
    // Elevated three-quarter follow; widens as the swarm grows.
    final wide = (_orbiting / kMaxSwarm).clamp(0.0, 1.0);
    final dist = 9.0 + wide * 3.0;
    final height = 5.4 + wide * 1.8;
    _camera = PerspectiveCamera(
      fovRadiansY: (44 + wide * 6) * degrees2Radians,
      position: Vector3(
        _corePos.x * 0.45,
        _corePos.y + height,
        _corePos.z - dist,
      ),
      target: Vector3(_corePos.x * 0.75, _corePos.y + 0.9, _corePos.z + 2.0),
    );
    return _camera;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070C18),
      body: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _holding = true,
        onPointerUp: (_) {
          _holding = false;
          _release();
        },
        onPointerCancel: (_) {
          _holding = false;
          _release();
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _ScenePainter(
                    scene: _scene,
                    cameraFor: _buildCameraNow,
                    ready: () => _ready,
                    repaint: _repaint,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 44,
              child: ListenableBuilder(
                listenable: _repaint,
                builder: (context, _) => DefaultTextStyle(
                style: const TextStyle(
                  color: Color(0xFF8FE9FF),
                  fontSize: 12,
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MAGNET RUSH — RENDERER SMOKE TEST',
                      style: TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text('orbiting   $_orbiting / $kMaxSwarm'),
                    Text('collected  $_collected'),
                    Text('destroyed  $_destroyed'),
                    Text('batch tris ${_batcher.triangleCount}'),
                    Text('batch vtx  ${_batcher.vertexCount}'),
                    const SizedBox(height: 6),
                    Text(
                      'frame avg  ${_avgMs.toStringAsFixed(2)} ms',
                      style: TextStyle(
                        color: _avgMs < 17 ? m.Colors.greenAccent : m.Colors.orangeAccent,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text('frame p95  ${_p95Ms.toStringAsFixed(2)} ms'),
                    Text('frame max  ${_worstMs.toStringAsFixed(2)} ms'),
                    Text('samples    ${_frameMs.length}'),
                  ],
                ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: Center(
                child: ListenableBuilder(
                  listenable: _repaint,
                  builder: (context, _) => Text(
                    _holding ? 'ATTRACTING…' : 'PRESS & HOLD TO ATTRACT',
                    style: TextStyle(
                      color: _holding
                          ? const Color(0xFF7CF3FF)
                          : const Color(0x99FFFFFF),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 12,
              top: 44,
              child: TextButton(
                onPressed: _reset,
                child: const Text(
                  'RESET',
                  style: TextStyle(color: Color(0xFFFF9A4D)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bridges the [Scene] into Flutter's paint phase. `repaint` is bumped once
/// per simulation tick, so the scene is drawn exactly once per frame.
class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.scene,
    required this.cameraFor,
    required this.ready,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Scene scene;
  final PerspectiveCamera Function() cameraFor;
  final bool Function() ready;

  @override
  void paint(Canvas canvas, Size size) {
    if (!ready()) return;
    scene.render(
      cameraFor(),
      canvas,
      viewport: Offset.zero & size,
    );
  }

  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) => false;
}
