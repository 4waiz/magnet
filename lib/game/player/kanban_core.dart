/// The Kanban Core — the player character, and the brightest thing on screen.
///
/// Loaded as *separable* Blender parts rather than one welded mesh, because
/// every state in the design needs pieces moving independently: the shell caps
/// split apart as charge rises, the chamber pulses through the seam, three
/// rings spin on different axes at different rates, and fragments orbit and
/// are thrown outward on release.
///
/// Materials are captured from the imported glTF and animated in place, so
/// brightening the cracks or flashing white on a perfect release costs a few
/// float writes rather than a mesh swap.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import '../../core/performance/quality.dart';

enum CoreState { idle, attracting, overcharged, repelling, damaged, complete }

/// Mirrors `CORE_SEAM_NORMAL` in art/blender/mr_hero.py, converted from
/// Blender's Z-up to the glTF/game Y-up axis convention: Blender (x, y, z)
/// becomes (x, z, -y).
final Vector3 kSeamNormal = Vector3(0.30, 1.0, -0.16)..normalize();

/// Ring rest tilts, mirroring `CORE_RING_AXES`. Rotation about game X and
/// game -Z, since Blender +Y maps to game -Z.
const List<(double, double)> _kRingTilts = [
  (0.14, 0.06),
  (1.02, 0.34),
  (0.52, -1.18),
];
const List<double> _kRingSpeeds = [1.35, -0.95, 0.62];

/// The Core is authored at 1.0 m diameter so its parts stay in metric scale,
/// but at that size it is a small object inside a 4 m lane and does not read
/// as the hero. Scaling the whole rig at runtime keeps the source assets
/// honest while giving the Core the presence the design calls for.
const double kCoreScale = 1.38;

class KanbanCore {
  KanbanCore();

  static const List<String> assetPaths = [
    'assets/models/core/core_shell_upper.glb',
    'assets/models/core/core_shell_lower.glb',
    'assets/models/core/core_cracks.glb',
    'assets/models/core/core_chamber.glb',
    'assets/models/core/core_heart.glb',
    'assets/models/core/core_ring_inner.glb',
    'assets/models/core/core_ring_mid.glb',
    'assets/models/core/core_ring_outer.glb',
    'assets/models/core/core_fragment_0.glb',
    'assets/models/core/core_fragment_1.glb',
    'assets/models/core/core_fragment_2.glb',
  ];

  final Node root = Node(name: 'kanban_core');

  Node? _shellUpper;
  Node? _shellLower;
  Node? _cracks;
  Node? _chamber;
  Node? _heart;
  final List<Node> _rings = [];
  final List<Node> _fragments = [];

  final List<_AnimMaterial> _crackMats = [];
  final List<_AnimMaterial> _chamberMats = [];
  final List<_AnimMaterial> _heartMats = [];
  final List<_AnimMaterial> _ringMats = [];
  final List<_AnimMaterial> _shellMats = [];

  bool loaded = false;

  // --- live state --------------------------------------------------------
  final Vector3 position = Vector3(0, 0, 0);
  CoreState state = CoreState.idle;
  double charge = 0;
  double swarmFraction = 0;

  double _t = 0;
  double _seamOpen = 0;
  double _compress = 0;
  double _flash = 0;
  double _damage = 0;
  double _spin = 0;
  double _ringSpinBoost = 0;
  double _completeSpin = 0;
  final List<double> _ringPhase = [0, 0, 0];
  double _flicker = 0;
  double _flickerTimer = 1.4;

  /// 0..1. Drives the field-line and attraction-radius visuals.
  double get seamOpen => _seamOpen;
  double get flash => _flash;
  double get radius => 0.5;

  // -----------------------------------------------------------------------
  // Loading
  // -----------------------------------------------------------------------

  Future<void> load() async {
    final nodes = await Future.wait(assetPaths.map(Node.fromGlbAsset));

    Node adopt(int i) {
      final n = nodes[i];
      root.add(n);
      return n;
    }

    _shellUpper = adopt(0);
    _shellLower = adopt(1);
    _cracks = adopt(2);
    _chamber = adopt(3);
    _heart = adopt(4);
    for (var i = 5; i <= 7; i++) {
      _rings.add(adopt(i));
    }
    for (var i = 8; i <= 10; i++) {
      _fragments.add(adopt(i));
    }

    _collect(_shellUpper, _shellMats);
    _collect(_shellLower, _shellMats);
    _collect(_cracks, _crackMats);
    _collect(_chamber, _chamberMats);
    _collect(_heart, _heartMats);
    for (final r in _rings) {
      _collect(r, _ringMats);
    }
    assert(() {
      for (var i = 0; i < assetPaths.length; i++) {
        var meshes = 0, prims = 0;
        void walk(Node n) {
          final m = n.mesh;
          if (m != null) {
            meshes++;
            prims += m.primitives.length;
          }
          for (final c in n.children) {
            walk(c);
          }
        }

        walk(nodes[i]);
        debugPrint(
          '[core] ${assetPaths[i].split('/').last} '
          'meshes=$meshes prims=$prims '
          'visible=${nodes[i].visible}',
        );
      }
      return true;
    }());
    loaded = true;
  }

  static void _collect(Node? node, List<_AnimMaterial> out) {
    if (node == null) return;
    void walk(Node n) {
      final mesh = n.mesh;
      if (mesh != null) {
        for (final p in mesh.primitives) {
          final m = p.material;
          if (m is PhysicallyBasedMaterial) out.add(_AnimMaterial(m));
        }
      }
      for (final c in n.children) {
        walk(c);
      }
    }

    walk(node);
  }

  // -----------------------------------------------------------------------
  // Events
  // -----------------------------------------------------------------------

  /// Brief compression then explosive expansion. [power] 0..1.
  void onRelease(double power, {bool perfect = false}) {
    state = CoreState.repelling;
    _compress = 1.0;
    _flash = perfect ? 1.0 : 0.72;
    _ringSpinBoost = perfect ? 7.0 : 4.2;
    _fragmentBurst = 1.0;
  }

  void onDamage() {
    state = CoreState.damaged;
    _damage = 1.0;
    _flash = 0.5;
  }

  void onComplete() {
    state = CoreState.complete;
    _completeSpin = 0.001;
  }

  void reset() {
    state = CoreState.idle;
    charge = 0;
    swarmFraction = 0;
    _t = 0;
    _seamOpen = 0;
    _compress = 0;
    _flash = 0;
    _damage = 0;
    _spin = 0;
    _ringSpinBoost = 0;
    _completeSpin = 0;
    _fragmentBurst = 0;
    _flicker = 0;
    _flickerTimer = 1.4;
    for (var i = 0; i < _ringPhase.length; i++) {
      _ringPhase[i] = 0;
    }
  }

  double _fragmentBurst = 0;

  // -----------------------------------------------------------------------
  // Per-frame
  // -----------------------------------------------------------------------

  void update(
    double dt, {
    required bool attracting,
    required QualitySettings quality,
    required double effectIntensity,
  }) {
    if (!loaded) return;
    _t += dt;

    // Decays
    _compress = math.max(0, _compress - dt * 5.5);
    _flash = math.max(0, _flash - dt * 3.4);
    _damage = math.max(0, _damage - dt * 1.15);
    _ringSpinBoost = math.max(0, _ringSpinBoost - dt * 4.0);
    _fragmentBurst = math.max(0, _fragmentBurst - dt * 1.7);

    if (state == CoreState.repelling && _flash < 0.05) {
      state = CoreState.idle;
    }
    if (state == CoreState.damaged && _damage < 0.02) {
      state = CoreState.idle;
    }
    if (state != CoreState.repelling &&
        state != CoreState.damaged &&
        state != CoreState.complete) {
      state = charge > 0.92
          ? CoreState.overcharged
          : (attracting ? CoreState.attracting : CoreState.idle);
    }

    // Occasional electrical flicker while idle — keeps a still Core alive.
    _flickerTimer -= dt;
    if (_flickerTimer <= 0) {
      _flickerTimer = 0.9 + math.Random().nextDouble() * 2.4;
      _flicker = 1.0;
    }
    _flicker = math.max(0, _flicker - dt * 7.0);

    // The seam widens with charge; the chamber becomes visible through it.
    final targetSeam = (charge * 0.85 + swarmFraction * 0.25).clamp(0.0, 1.0);
    _seamOpen += (targetSeam - _seamOpen) * math.min(1.0, dt * 6.0);

    final hoverY = math.sin(_t * 1.35) * 0.055 + math.sin(_t * 0.61) * 0.022;
    _spin += dt * (0.35 + charge * 0.55);
    if (state == CoreState.complete) {
      _completeSpin += dt;
      _spin += dt * math.min(4.0, _completeSpin * 2.2);
    }

    // Root: hover, gentle rotation, compression squash on release. Squashing
    // vertically bulges horizontally by the same amount, so the Core keeps its
    // volume and the compression reads as a wind-up rather than a shrink.
    final squash = 1.0 - _compress * 0.22;
    final bulge = 1.0 + _compress * 0.16;
    final grow = kCoreScale * (1.0 + swarmFraction * 0.10 + _flash * 0.16);
    root.localTransform = Matrix4.identity()
      ..setTranslation(Vector3(position.x, position.y + hoverY, position.z))
      ..rotateY(_spin)
      ..scaleByDouble(grow * bulge, grow * squash, grow * bulge, 1.0);

    _updateShell();
    _updateRings(dt);
    _updateFragments();
    _updateMaterials(effectIntensity, quality);
  }

  void _updateShell() {
    // Caps slide apart along the tilted seam normal.
    final open = _seamOpen * 0.075 + _flash * 0.05;
    final n = kSeamNormal;
    _shellUpper?.localTransform = Matrix4.identity()..setTranslation(n * open);
    _shellLower?.localTransform = Matrix4.identity()..setTranslation(n * -open);

    // Chamber breathes; heart only becomes prominent near maximum charge.
    final breathe =
        1.0 + math.sin(_t * 2.4) * 0.035 + charge * 0.13 + _flash * 0.30;
    _chamber?.localTransform = Matrix4.identity()
      ..scaleByDouble(breathe, breathe, breathe, 1.0);

    final heartScale = (0.45 + charge * 0.9 + _flash * 0.5).clamp(0.0, 1.9);
    _heart?.localTransform = Matrix4.identity()
      ..scaleByDouble(heartScale, heartScale, heartScale, 1.0);
    _heart?.visible = charge > 0.22 || _flash > 0.05;

    _cracks?.localTransform = Matrix4.identity();
  }

  void _updateRings(double dt) {
    for (var i = 0; i < _rings.length; i++) {
      final speed =
          _kRingSpeeds[i] *
          (1.0 + charge * 2.4 + swarmFraction * 0.9) *
          (1.0 + _ringSpinBoost);
      _ringPhase[i] += dt * speed;

      // Rings snap outward on release, then settle.
      final push = 1.0 + _flash * 0.42 + _seamOpen * 0.06;
      final wobble = _damage > 0.01
          ? math.sin(_t * 21.0 + i * 2.1) * _damage * 0.28
          : 0.0;
      final (tx, tz) = _kRingTilts[i];

      _rings[i].localTransform = Matrix4.identity()
        ..rotateX(tx + wobble)
        ..rotateZ(-tz + wobble * 0.5)
        ..rotateY(_ringPhase[i])
        ..scaleByDouble(push, push, push, 1.0);
    }
  }

  void _updateFragments() {
    const orbits = [
      (0.74, 0.20, 0.85, 0.0),
      (0.82, -0.14, -0.62, 2.1),
      (0.68, 0.30, 0.48, 4.2),
    ];
    for (var i = 0; i < _fragments.length && i < orbits.length; i++) {
      final (baseR, h, speed, phase) = orbits[i];
      // Pulled inward while attracting, flung outward on release.
      final r = baseR * (1.0 - charge * 0.22 + _fragmentBurst * 0.85);
      final a = phase + _t * speed * (1.0 + charge * 1.4);
      _fragments[i].localTransform = Matrix4.identity()
        ..setTranslation(
          Vector3(
            math.cos(a) * r,
            h + math.sin(a * 1.7) * 0.10,
            math.sin(a) * r,
          ),
        )
        ..rotateY(a * 2.1)
        ..rotateX(a * 1.3);
    }
  }

  void _updateMaterials(double effectIntensity, QualitySettings quality) {
    final glow = quality.glowIntensity * effectIntensity;

    // Cracks brighten with charge and spike on flash / flicker.
    final crackBoost =
        (0.55 + charge * 2.6 + _flash * 3.2 + _flicker * 1.1) * glow;
    for (final m in _crackMats) {
      m.setEmissiveScale(crackBoost);
    }

    // Chamber: the hero glow. Damage tints it red-orange.
    final chamberBoost = (0.85 + charge * 1.9 + _flash * 2.4) * glow;
    final dmg = _damage;
    for (final m in _chamberMats) {
      m.setEmissiveScale(chamberBoost);
      m.tint(Vector3(1.0 + dmg * 0.9, 1.0 - dmg * 0.55, 1.0 - dmg * 0.75));
    }
    for (final m in _heartMats) {
      m.setEmissiveScale((1.1 + charge * 2.6 + _flash * 3.0) * glow);
    }

    final ringBoost = (0.75 + charge * 1.5 + _flash * 1.8) * glow;
    for (final m in _ringMats) {
      m.setEmissiveScale(ringBoost);
      m.tint(Vector3(1.0 + dmg * 0.8, 1.0 - dmg * 0.4, 1.0 - dmg * 0.6));
    }

    // The shell itself stays comparatively dark so the facets keep reading.
    for (final m in _shellMats) {
      m.setEmissiveScale((1.0 + _flash * 1.3) * glow);
      m.tint(Vector3(1.0 + dmg * 0.7, 1.0 - dmg * 0.3, 1.0 - dmg * 0.45));
    }
  }
}

/// Captures a material's authored emissive/base colour so runtime animation is
/// expressed as a multiplier and can always return to the art-directed value.
class _AnimMaterial {
  _AnimMaterial(this.material)
    : _baseEmissive = material.emissiveFactor.clone(),
      _baseColor = material.baseColorFactor.clone();

  final PhysicallyBasedMaterial material;
  final Vector4 _baseEmissive;
  final Vector4 _baseColor;

  void setEmissiveScale(double k) {
    material.emissiveFactor = Vector4(
      _baseEmissive.x * k,
      _baseEmissive.y * k,
      _baseEmissive.z * k,
      _baseEmissive.w,
    );
  }

  void tint(Vector3 rgb) {
    material.baseColorFactor = Vector4(
      (_baseColor.x * rgb.x).clamp(0.0, 4.0),
      (_baseColor.y * rgb.y).clamp(0.0, 4.0),
      (_baseColor.z * rgb.z).clamp(0.0, 4.0),
      _baseColor.w,
    );
  }
}
