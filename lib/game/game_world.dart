/// The Level 1 world: loading, simulation, encounter sequencing and rendering.
///
/// Draw-call budget, roughly:
///   * environment — one node per placement, all sharing cached meshes, so the
///     geometry is uploaded once per unique asset
///   * Kanban Core — one node per animated part (11)
///   * entire swarm, debris and every particle — 2 batched draws
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import '../core/audio/audio_service.dart';
import '../core/haptics/haptics_service.dart';
import '../core/performance/quality.dart';
import '../core/persistence/settings_store.dart';
import 'camera/game_camera.dart';
import 'effects/effects.dart';
import 'levels/level_data.dart';
import 'levels/level_validator.dart';
import 'magnet/magnet_field.dart';
import 'player/kanban_core.dart';
import 'renderer/glb_template_loader.dart';
import 'renderer/mesh_batcher.dart';
import 'renderer/mesh_template.dart';
import 'renderer/sky.dart';
import 'scoring/scoring.dart';
import 'swarm/swarm.dart';

/// Prints the camera rig once a second in debug builds. Kept because framing
/// bugs are near-impossible to diagnose from a screenshot alone — the eye and
/// target numbers settle in seconds what guesswork does not.
///
///   flutter run --dart-define=MR_LOG_CAMERA=true
const bool kLogCamera = bool.fromEnvironment('MR_LOG_CAMERA');

/// Forces the vertical-flip compensation on or off instead of auto-detecting.
/// Values: 'auto' (default), 'on', 'off'. See [GameWorld._flipY].
const String kFlipY = String.fromEnvironment('MR_FLIP_Y', defaultValue: 'auto');

enum GamePhase { loading, intro, playing, complete, failed }

/// Transient banner text the HUD shows ("PERFECT!", "BRIDGE FORMED").
class Toast {
  Toast(this.text, this.colour, this.life);
  final String text;
  final ui.Color colour;
  double life;
}

class WallBlock {
  WallBlock(this.position, this.size);
  final Vector3 position;
  final double size;
  bool alive = true;
  int hits = 0;
  final Vector3 velocity = Vector3.zero();
  double spin = 0;
  double deadTime = 0;

  final Matrix4 _m = Matrix4.identity();
  Matrix4 transform() {
    _m.setIdentity();
    _m.setTranslation(position);
    if (!alive) {
      _m.rotateX(spin);
      _m.rotateZ(spin * 1.3);
    }
    _m.scaleByDouble(size, size, size, 1.0);
    return _m;
  }
}

class GameWorld {
  GameWorld({
    required this.settings,
    required this.audio,
    required this.haptics,
  });

  final SettingsStore settings;
  final AudioService audio;
  final HapticsService haptics;

  final Scene scene = Scene();
  late LevelData level;
  ValidationResult? validation;

  final KanbanCore core = KanbanCore();
  final Swarm swarm = Swarm(capacity: 120);
  final MagnetField field = MagnetField();
  final GameCamera camera = GameCamera();
  final RunScore score = RunScore();
  final ChargeState charge = ChargeState();
  late Effects effects;

  late MeshBatcher _metalBatch;
  late MeshBatcher _glowBatch;
  final SkyPainter _sky = SkyPainter();

  /// Whether the composited 3D image needs flipping vertically.
  ///
  /// **Confirmed renderer bug.** Impeller's GLES backend composites the
  /// offscreen scene texture with the opposite vertical orientation from
  /// Vulkan, so the level renders upside down on GLES while being correct on
  /// Vulkan. Verified by capturing the identical game state on both backends
  /// (docs/shots/cmp_debug_vulkan.png vs cmp_release_gles.png).
  ///
  /// The proper fix belongs below flutter_scene, in Impeller's texture
  /// handling; this compensates at the composite instead.
  ///
  /// **Detection is a heuristic, not a guarantee.** Nothing in the Flutter GPU
  /// Dart API reports the active backend. The only capability that differed
  /// between the two on the test device was the minimum uniform alignment
  /// (Vulkan 64, GLES 256), so that is what `auto` keys off. It is a driver
  /// property, not a backend contract, and a Vulkan device reporting 256 would
  /// be flipped wrongly — hence the `MR_FLIP_Y` override:
  ///
  ///   flutter run --dart-define=MR_FLIP_Y=on    # force the flip
  ///   flutter run --dart-define=MR_FLIP_Y=off   # never flip
  bool _flipY = false;

  /// The empirically observed GLES signature. See [_flipY].
  static const int _glesUniformAlignment = 256;

  final Map<String, MeshTemplate> _templates = {};
  final Map<String, List<(Mesh, Matrix4)>> _meshCache = {};
  final List<Node> _envNodes = [];

  // Portal / key / hazard scene nodes we animate.
  Node? _portalNode;
  Node? _portalDisc;
  Node? _keyBarsNode;
  Node? _hazardNode;

  GamePhase phase = GamePhase.loading;
  bool holding = false;
  bool loaded = false;
  String loadError = '';

  double _coreZ = 0;
  final Vector3 _corePos = Vector3.zero();
  double _introT = 0;
  double _time = 0;
  double _timeScale = 1.0;
  double _hitStop = 0;
  String failureReason = '';

  final List<WallBlock> _wall = [];
  final List<Toast> toasts = [];
  final math.Random _rng = math.Random(1337);

  // Encounter state
  int _lastStage = 0;
  int _armourRemaining = 0;
  bool _armourActive = false;
  bool _hazardFired = false;
  double _hazardTelegraph = 0;
  bool _hazardTelegraphing = false;
  bool _bridgeFormed = false;
  double _bridgeBuild = 0;
  bool _keyCollected = false;
  bool _portalUnlocked = false;
  double _portalCharge = 0;
  double _completeT = 0;

  final List<MetalPiece> _bridgePieces = [];

  QualitySettings get quality => settings.value.qualitySettings;

  // -------------------------------------------------------------------------
  // Public state for the HUD
  // -------------------------------------------------------------------------

  int get orbiting => swarm.stats.orbiting;
  int get collected => score.metalCollected;
  int get stage => swarm.stage;
  double get chargeValue => charge.charge;
  bool get perfectWindow => charge.inPerfectWindow;
  double get ventPressure => charge.ventPressure;
  bool get bridgeFormed => _bridgeFormed;
  bool get keyCollected => _keyCollected;
  bool get portalUnlocked => _portalUnlocked;
  int get armourRemaining => _armourRemaining;
  double get progress =>
      (_coreZ / math.max(1.0, level.finishZ)).clamp(0.0, 1.0);

  // -------------------------------------------------------------------------
  // Loading
  // -------------------------------------------------------------------------

  Future<void> load({String levelAsset = 'assets/levels/level_01.json'}) async {
    try {
      await Scene.initializeStaticResources();

      final source = await rootBundle.loadString(levelAsset);
      level = LevelData.fromJsonString(source);
      validation = const LevelValidator().validate(level);

      swarm.capacity = math.min(level.swarmCapacity, quality.maxSwarm);

      effects = Effects(
        particleCapacity: quality.maxParticles,
        debrisCapacity: quality.maxDebris,
      );

      // Effect primitives are procedural: they must exist before any asset
      // loads so a failed asset can never leave the pools without templates.
      effects.setTemplates(
        shard: MeshTemplate.icosphere(0.5, 0, name: 'fx_shard'),
        spark: MeshTemplate.box(0.22, 0.22, 0.5, name: 'fx_spark'),
        cube: MeshTemplate.box(0.5, 0.5, 0.5, name: 'fx_cube'),
        ring: _ringTemplate(),
      );

      await core.load();
      scene.add(core.root);

      await _loadTemplates();
      await _buildEnvironment();

      _setupLighting();

      final align = scene.debugGpuFingerprint['uniformAlign'];
      _flipY = switch (kFlipY) {
        'on' => true,
        'off' => false,
        _ => align is int && align >= _glesUniformAlignment,
      };
      // ignore: avoid_print
      print(
        '[render] antiAliasing=${scene.antiAliasingMode.name} '
        'flipY=$_flipY (MR_FLIP_Y=$kFlipY) '
        'gpu=${scene.debugGpuFingerprint}',
      );

      // Launched metal that comes down over solid deck is recoverable.
      swarm.canLandAt = _isOverSolidDeck;

      resetLevel();
      loaded = true;
      phase = GamePhase.intro;
    } catch (e, st) {
      loadError = '$e';
      // Surface rather than silently rendering an empty scene.
      // ignore: avoid_print
      print('GameWorld.load failed: $e\n$st');
      rethrow;
    }
  }

  static MeshTemplate _ringTemplate() {
    // A flat low-poly ring in XZ, radius 1, used for every shock front.
    const seg = 22;
    const inner = 0.82;
    final positions = <double>[];
    final indices = <int>[];
    for (var i = 0; i < seg; i++) {
      final a0 = i / seg * math.pi * 2;
      final a1 = (i + 1) / seg * math.pi * 2;
      final base = positions.length ~/ 3;
      positions.addAll([
        math.cos(a0) * inner,
        0,
        math.sin(a0) * inner,
        math.cos(a0),
        0,
        math.sin(a0),
        math.cos(a1),
        0,
        math.sin(a1),
        math.cos(a1) * inner,
        0,
        math.sin(a1) * inner,
      ]);
      indices.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
    }
    return MeshTemplate.fromTriangleSoup(
      Float32List.fromList(positions),
      Uint16List.fromList(indices),
      name: 'fx_ring',
    );
  }

  Future<void> _loadTemplates() async {
    final paths = <String>{
      for (final g in level.metalGroups) ...g.templates,
      if (level.armour != null) ...level.armour!.templates,
      if (level.bridge != null) ...level.bridge!.templates,
      if (level.key != null) level.key!.asset,
    };
    for (final p in paths) {
      try {
        _templates[p] = (await GlbTemplateLoader.load(p)).normalizedTo(0.30);
      } catch (e) {
        // A single bad asset must not sink the level; substitute a cube and
        // keep the failure visible in the log.
        // ignore: avoid_print
        print('template load failed for $p: $e');
        _templates[p] = MeshTemplate.box(0.16, 0.16, 0.16, name: p);
      }
    }
  }

  Future<List<(Mesh, Matrix4)>> _meshesFor(String asset) async {
    final hit = _meshCache[asset];
    if (hit != null) return hit;
    final out = <(Mesh, Matrix4)>[];
    try {
      final node = await Node.fromGlbAsset(asset);
      void walk(Node n, Matrix4 parent) {
        final world = parent.multiplied(n.localTransform);
        final mesh = n.mesh;
        if (mesh != null) out.add((mesh, world));
        for (final c in n.children) {
          walk(c, world);
        }
      }

      walk(node, Matrix4.identity());
    } catch (e) {
      // ignore: avoid_print
      print('mesh load failed for $asset: $e');
    }
    _meshCache[asset] = out;
    return out;
  }

  Future<void> _buildEnvironment() async {
    for (final node in _envNodes) {
      scene.remove(node);
    }
    _envNodes.clear();

    final density = quality.decorDensity;
    var decorIndex = 0;

    for (final p in level.platforms) {
      if (p.decorative) {
        decorIndex++;
        // Thin decorative scenery deterministically on lower presets.
        if (density < 1.0 && (decorIndex * 0.37) % 1.0 > density) continue;
      }
      final meshes = await _meshesFor(p.asset);
      for (final (mesh, local) in meshes) {
        final placement = Matrix4.identity()
          ..setTranslation(p.position)
          ..rotateY(p.rotationY)
          ..scaleByDouble(p.scale, p.scale, p.scale, 1.0);
        final node = Node(name: p.asset, mesh: mesh)
          ..localTransform = placement.multiplied(local);
        scene.add(node);
        _envNodes.add(node);
      }
    }

    // Key bars, portal, hazard emitter are animated, so keep references.
    final key = level.key;
    if (key != null) {
      _keyBarsNode = await _spawnProp(key.barsAsset, key.barsPosition);
    }
    _portalNode = await _spawnProp(level.portal.asset, level.portal.position);
    _portalDisc = await _spawnProp(
      level.portal.discAsset,
      level.portal.position,
    );
    for (final h in level.hazards) {
      _hazardNode = await _spawnProp(
        'assets/models/obstacles/obstacle_hazard_emitter.glb',
        h.position,
      );
    }
  }

  Future<Node?> _spawnProp(String asset, Vector3 position) async {
    final meshes = await _meshesFor(asset);
    if (meshes.isEmpty) return null;
    final root = Node(name: asset);
    for (final (mesh, local) in meshes) {
      root.add(Node(mesh: mesh)..localTransform = local);
    }
    root.localTransform = Matrix4.identity()..setTranslation(position);
    scene.add(root);
    _envNodes.add(root);
    return root;
  }

  void _setupLighting() {
    // Cool key from high front-left. The Core supplies its own light through
    // emissive materials, so the directional light stays restrained — pushing
    // it higher washes out the facets that make the crystal read.
    scene.directionalLight = DirectionalLight(
      direction: Vector3(-0.42, -1.0, 0.30)..normalize(),
      color: Vector3(0.72, 0.86, 1.0),
      intensity: 2.6,
    );
    scene.exposure = 1.05;
    // The default studio probe is bright. At higher intensities it lit the
    // whole facility to a flat mid-grey and the Core stopped being the
    // brightest thing on screen, which is the one rule the art direction
    // cannot break.
    scene.environmentIntensity = 0.16;

    _metalBatch = MeshBatcher(
      maxVertices: 32000,
      maxIndices: 48000,
      name: 'swarm',
      // Metallic is moderate, not near-1. A fully metallic surface draws its
      // colour from the environment probe, and with the probe dialled down to
      // keep the facility dark the whole swarm rendered as near-black chunks.
      material: PhysicallyBasedMaterial()
        ..baseColorFactor = Vector4(1, 1, 1, 1)
        ..metallicFactor = 0.35
        ..roughnessFactor = 0.45
        ..vertexColorWeight = 1.0,
    );
    _glowBatch = MeshBatcher(
      maxVertices: 24000,
      maxIndices: 36000,
      name: 'glow',
      material: GlowMaterial(),
    );
  }

  // -------------------------------------------------------------------------
  // Level setup / reset
  // -------------------------------------------------------------------------

  /// Deterministic: every retry rebuilds from the same seed, so a run is
  /// exactly repeatable.
  void resetLevel() {
    final rng = math.Random(20260805);

    swarm.clear();
    field.reset();
    effects.clear();
    camera.reset();
    core.reset();
    score.reset();
    charge.reset();
    haptics.reset();
    audio.resetCollect();
    toasts.clear();
    _wall.clear();
    _bridgePieces.clear();

    _coreZ = level.coreStart.z;
    _corePos.setFrom(level.coreStart);
    core.position.setFrom(_corePos);
    _introT = 0;
    _time = 0;
    _timeScale = 1.0;
    _hitStop = 0;
    _lastStage = 0;
    _armourActive = false;
    _armourRemaining = 0;
    _hazardFired = false;
    _hazardTelegraph = 0;
    _hazardTelegraphing = false;
    _bridgeFormed = false;
    _bridgeBuild = 0;
    _keyCollected = false;
    _portalUnlocked = false;
    _portalCharge = 0;
    _completeT = 0;
    _stuckFor = 0;
    failureReason = '';
    holding = false;
    phase = GamePhase.intro;

    // --- metal ---------------------------------------------------------
    for (final g in level.metalGroups) {
      for (var i = 0; i < g.count; i++) {
        _spawnPiece(
          rng: rng,
          templates: g.templates,
          centre: g.centre,
          spread: g.spread,
          massClass: g.massClass,
          kind: PieceKind.scrap,
        );
      }
    }

    // --- armour --------------------------------------------------------
    final armour = level.armour;
    if (armour != null) {
      for (var i = 0; i < armour.count; i++) {
        _spawnPiece(
          rng: rng,
          templates: armour.templates,
          centre: armour.centre,
          spread: armour.spread,
          massClass: MassClass.medium,
          kind: PieceKind.armour,
        );
      }
    }

    // --- bridge --------------------------------------------------------
    final bridge = level.bridge;
    if (bridge != null) {
      for (var i = 0; i < bridge.pieceCount; i++) {
        final p = _spawnPiece(
          rng: rng,
          templates: bridge.templates,
          centre: bridge.pieceCentre,
          spread: bridge.pieceSpread,
          massClass: MassClass.medium,
          kind: PieceKind.bridge,
          scaleOverride: 1.35,
        );
        if (p != null) _bridgePieces.add(p);
      }
    }

    // --- key -----------------------------------------------------------
    final key = level.key;
    if (key != null) {
      _spawnPiece(
        rng: rng,
        templates: [key.asset],
        centre: key.position,
        spread: Vector3.zero(),
        massClass: MassClass.light,
        kind: PieceKind.key,
        scaleOverride: 1.5,
      );
    }

    // --- wall ----------------------------------------------------------
    final wall = level.wall;
    if (wall != null) {
      final w = wall.blockSize;
      for (var row = 0; row < wall.rows; row++) {
        for (var col = 0; col < wall.columns; col++) {
          _wall.add(
            WallBlock(
              Vector3(
                wall.centre.x + (col - (wall.columns - 1) / 2) * w,
                wall.centre.y + 0.34 + row * w,
                wall.centre.z,
              ),
              // The cube template is a unit cube, so `size` is the block's
              // FULL width. Using half the grid spacing left a sparse lattice
              // of floating cubes that neither read as a wall nor reliably
              // stopped projectiles; a block must fill its cell.
              w * 0.96,
            ),
          );
        }
      }
    }
  }

  MetalPiece? _spawnPiece({
    required math.Random rng,
    required List<String> templates,
    required Vector3 centre,
    required Vector3 spread,
    required MassClass massClass,
    required PieceKind kind,
    double scaleOverride = 1.0,
  }) {
    if (templates.isEmpty) return null;
    final path = templates[rng.nextInt(templates.length)];
    final t = _templates[path];
    if (t == null) return null;

    final pos = Vector3(
      centre.x + (rng.nextDouble() * 2 - 1) * spread.x,
      centre.y + (rng.nextDouble() * 2 - 1) * spread.y,
      centre.z + (rng.nextDouble() * 2 - 1) * spread.z,
    );
    final baseScale = switch (massClass) {
      MassClass.light => 0.75,
      MassClass.medium => 1.0,
      MassClass.heavy => 1.35,
    };
    final tint = switch (kind) {
      PieceKind.armour => Vector4(1.05, 1.10, 1.20, 1),
      PieceKind.bridge => Vector4(0.85, 1.15, 1.30, 1),
      PieceKind.key => Vector4(1.60, 1.25, 0.45, 1),
      PieceKind.scrap => Vector4(1, 1, 1, 1),
    };
    final piece = MetalPiece(
      template: t,
      homePosition: pos,
      massClass: massClass,
      kind: kind,
      scale: baseScale * scaleOverride * (0.85 + rng.nextDouble() * 0.35),
      tint: tint,
    );
    piece.tumbleY = rng.nextDouble() * math.pi * 2;
    piece.tumbleX = rng.nextDouble() * math.pi * 2;
    swarm.add(piece);
    return piece;
  }

  // -------------------------------------------------------------------------
  // Input
  // -------------------------------------------------------------------------

  void onPointerDown() {
    if (phase == GamePhase.intro) phase = GamePhase.playing;
    if (phase != GamePhase.playing) return;
    holding = true;
  }

  void onPointerUp() {
    if (!holding) return;
    holding = false;
    if (phase != GamePhase.playing) return;
    _release();
  }

  void _release() {
    if (swarm.stats.orbiting == 0) {
      charge.reset();
      return;
    }
    final perfect = charge.inPerfectWindow;
    final power = charge.charge;

    // Bridge assembly takes priority near the anchors: the same gesture forms
    // the bridge instead of firing the swarm away.
    if (_tryFormBridge()) return;

    final target = _bestTarget();
    final launched = swarm.release(
      corePos: _corePos,
      forward: Vector3(0, 0.14, 1.0)..normalize(),
      charge: power,
      perfect: perfect,
      rng: _rng,
      target: target,
    );

    score.releases++;
    if (perfect) {
      score.perfectReleases++;
      _toast('PERFECT RELEASE', const ui.Color(0xFFCFFBFF));
      audio.play(Sfx.perfectRelease);
      haptics.impact(HapticStrength.heavy, important: true);
      camera.impulse(CameraImpulse.perfectRelease);
      effects.ringWave(
        at: _corePos.clone(),
        colour: Vector4(0.85, 1.0, 1.0, 0.95),
        radiusEnd: 7.5,
        life: 0.6,
        thickness: 0.30,
      );
    } else {
      audio.play(Sfx.repulse);
      haptics.impact(HapticStrength.medium, important: true);
      camera.impulse(CameraImpulse.release);
    }

    core.onRelease(power, perfect: perfect);
    effects.ringWave(
      at: _corePos.clone(),
      colour: Vector4(0.35, 0.88, 1.0, 0.85),
      radiusEnd: 5.4 + power * 2.5,
      life: 0.5,
      thickness: 0.22,
    );
    effects.burst(
      at: _corePos.clone(),
      count: 22,
      colour: Vector4(0.6, 0.95, 1.0, 1),
      speed: 9.0,
      life: 0.45,
      size: 0.10,
      shape: ParticleShape.spark,
      intensity: settings.value.effectIntensity,
    );

    if (launched > 0) _hitStop = perfect ? 0.085 : 0.045;
    charge.reset();
  }

  /// Prefers a live wall, then the nearest surviving obstacle ahead.
  Vector3? _bestTarget() {
    Vector3? best;
    var bestD = double.infinity;
    for (final b in _wall) {
      if (!b.alive) continue;
      final d = (b.position - _corePos).length;
      if (d < bestD && b.position.z > _corePos.z - 1.0) {
        bestD = d;
        best = b.position;
      }
    }
    return bestD < 22.0 ? best : null;
  }

  // -------------------------------------------------------------------------
  // Simulation
  // -------------------------------------------------------------------------

  void update(double rawDt) {
    if (!loaded) return;
    var dt = rawDt.clamp(0.0, 1 / 20.0);
    haptics.tickClock(Duration(microseconds: (_time * 1e6).round()));

    // Hit-stop: a brief global slowdown that makes a big hit land.
    if (_hitStop > 0) {
      _hitStop -= rawDt;
      _timeScale = 0.22;
    } else {
      _timeScale += (1.0 - _timeScale) * math.min(1.0, rawDt * 8.0);
    }
    dt *= _timeScale;
    _time += dt;

    switch (phase) {
      case GamePhase.loading:
        return;
      case GamePhase.intro:
        _updateIntro(dt);
      case GamePhase.playing:
        _updatePlaying(dt);
      case GamePhase.complete:
        _updateComplete(dt);
      case GamePhase.failed:
        break;
    }

    _updateToasts(rawDt);
    effects.update(dt);
    core.position.setFrom(_corePos);
    core.charge = charge.charge;
    core.swarmFraction = swarm.fraction;
    core.update(
      dt,
      attracting: holding,
      quality: quality,
      effectIntensity: settings.value.effectIntensity,
    );
    _updateProps(dt);
    _rebuildBatches();
  }

  void _updateIntro(double dt) {
    // A short scripted reveal: the Core drifts in and the nearby metal gets a
    // magnetic twitch so the player sees what is collectable before touching.
    _introT += dt;
    _corePos.setFrom(level.routeAt(_coreZ));
    _corePos.y = level.coreStart.y + math.sin(_introT * 1.6) * 0.05;

    if (_introT > 0.4 && _introT < 1.9) {
      for (final p in swarm.pieces) {
        if (p.kind != PieceKind.scrap) continue;
        if ((p.homePosition.z - _coreZ).abs() > 12) continue;
        final wobble = math.sin(_time * 9.0 + p.homePosition.x * 3.0) * 0.035;
        p.position.y = p.homePosition.y + wobble;
      }
    }
    if (_introT > 1.1 && toasts.isEmpty && score.metalCollected == 0) {
      _toast('HOLD TO ATTRACT', const ui.Color(0xFF3FE0FF), life: 2.4);
    }
    if (_introT > 3.0) phase = GamePhase.playing;
  }

  void _updatePlaying(double dt) {
    score.tick(dt);

    // --- charge ---------------------------------------------------------
    final vented = charge.update(dt, holding: holding);
    if (vented) {
      _toast('OVERLOAD — VENTED', const ui.Color(0xFFFF7A2F), life: 1.2);
      haptics.impact(HapticStrength.light);
    }
    haptics.chargePulse(charge.charge, dt);
    audio.setAttracting(holding, charge.charge);
    if (charge.inPerfectWindow && !_perfectAnnounced) {
      _perfectAnnounced = true;
      audio.play(Sfx.maxCharge, volume: 0.5);
    } else if (!charge.inPerfectWindow) {
      _perfectAnnounced = false;
    }

    // --- advance --------------------------------------------------------
    // The Core slows while carrying a big swarm, which makes growth felt.
    final drag = 1.0 - swarm.fraction * 0.30;
    final blocked = _isBlockedByWall() || _isOverGapWithoutBridge();
    if (!blocked) {
      _coreZ += level.coreSpeed * drag * dt;
    }
    final routed = level.routeAt(_coreZ);
    _corePos
      ..setFrom(routed)
      ..y =
          level.coreStart.y +
          math.sin(_time * 1.4) * 0.05 +
          (_bridgeFormed && level.gap!.contains(_coreZ) ? -0.15 : 0.0);

    camera.setAttracting(holding, dt);

    // --- magnet ---------------------------------------------------------
    for (final p in swarm.pieces) {
      if (p.state != PieceState.idle) continue;
      if (p.kind == PieceKind.armour && !_armourActive) continue;
      if (p.kind == PieceKind.key && !_keyReachable(p)) continue;
      final captured = field.apply(
        p,
        _corePos,
        dt,
        attracting: holding,
        charge: charge.charge,
      );
      if (captured && swarm.capture(p, _corePos, _rng)) {
        _onCaptured(p);
      }
    }

    swarm.update(
      dt,
      _corePos,
      charge: charge.charge,
      stageThresholds: level.swarmStages,
      trailSegments: quality.trailSegments,
    );
    audio.tickCollect(dt, swarm.fraction);

    if (swarm.stats.orbiting > score.largestSwarm) {
      score.largestSwarm = swarm.stats.orbiting;
    }
    if (swarm.stage > _lastStage) {
      _lastStage = swarm.stage;
      _onSwarmStage(swarm.stage);
    }

    _updateProjectiles();
    _updateWallDebris(dt);
    _updateHazards(dt);
    _updateArmour();
    _updateKeyAndPortal(dt);
    _checkFailure();
  }

  bool _perfectAnnounced = false;

  void _onCaptured(MetalPiece p) {
    score.addCollect();
    audio.noteCollect();
    haptics.impact(HapticStrength.tick);
    effects.burst(
      at: p.position.clone(),
      count: 3,
      colour: Vector4(0.55, 0.95, 1.0, 1),
      speed: 1.6,
      life: 0.30,
      size: 0.055,
      gravity: 0,
      shape: ParticleShape.spark,
      intensity: settings.value.effectIntensity,
    );
    if (p.kind == PieceKind.key) {
      _keyCollected = true;
      audio.play(Sfx.keyCollect);
      haptics.impact(HapticStrength.medium, important: true);
      _toast('MAGNETIC KEY ACQUIRED', const ui.Color(0xFFFFC24D), life: 2.0);
      effects.ringWave(
        at: p.position.clone(),
        colour: Vector4(1.0, 0.78, 0.30, 0.9),
        radiusEnd: 3.4,
        life: 0.7,
      );
    }
  }

  void _onSwarmStage(int stage) {
    audio.play(Sfx.swarmStage);
    haptics.impact(HapticStrength.light, important: true);
    camera.impulse(CameraImpulse.collectMilestone);
    _toast('SWARM STAGE $stage', const ui.Color(0xFF3FE0FF), life: 1.4);
    effects.ringWave(
      at: _corePos.clone(),
      colour: Vector4(0.4, 0.92, 1.0, 0.8),
      radius: 1.2,
      radiusEnd: 4.2,
      life: 0.55,
    );
    effects.burst(
      at: _corePos.clone(),
      count: 14,
      colour: Vector4(0.6, 0.95, 1.0, 1),
      speed: 4.5,
      life: 0.5,
      size: 0.08,
      shape: ParticleShape.shard,
      intensity: settings.value.effectIntensity,
    );
  }

  bool _isBlockedByWall() {
    final wall = level.wall;
    if (wall == null) return false;
    if (_wall.every((b) => !b.alive)) return false;
    return _coreZ > wall.centre.z - 2.6 && _coreZ < wall.centre.z + 1.0;
  }

  /// A coarse "is there deck here" test, from the level's own route and gap
  /// rather than from per-platform collision: the lane is 4 m wide and follows
  /// the route, and the gap is the only hole in it.
  bool _isOverSolidDeck(Vector3 position) {
    if (position.z < -3 || position.z > level.finishZ + 6) return false;
    final gap = level.gap;
    if (gap != null && gap.contains(position.z) && !_bridgeFormed) return false;
    final lane = level.routeAt(position.z);
    return (position.x - lane.x).abs() < 3.4;
  }

  bool _isOverGapWithoutBridge() {
    final gap = level.gap;
    if (gap == null) return false;
    if (_bridgeFormed) return false;
    return _coreZ > gap.startZ - 1.6 && _coreZ < gap.endZ;
  }

  // --- projectiles ------------------------------------------------------

  /// Collision is a radius test against live wall blocks; launched pieces move
  /// far enough per frame that a point test tunnels straight through, so the
  /// radius is deliberately generous.
  void _updateProjectiles() {
    for (final p in swarm.pieces) {
      if (p.state != PieceState.launched || p.hasHit) continue;
      _hitWall(p);
    }
  }

  void _hitWall(MetalPiece p) {
    final wall = level.wall;
    if (wall == null) return;
    for (final b in _wall) {
      if (!b.alive) continue;
      // Radius, not a point test: launched pieces cover up to a metre
      // per frame at 30 fps and would otherwise tunnel through.
      if ((b.position - p.position).length2 > 1.75) continue;

      b.hits++;
      p.hasHit = true;
      p.life = math.min(p.life, 0.22);
      audio.play(Sfx.metalImpact, volume: 0.45);
      effects.burst(
        at: p.position.clone(),
        count: 5,
        colour: Vector4(1.0, 0.72, 0.30, 1),
        speed: 4.5,
        life: 0.32,
        size: 0.06,
        shape: ParticleShape.spark,
        intensity: settings.value.effectIntensity,
      );

      if (b.hits >= wall.hitsPerBlock) {
        b.alive = false;
        b.velocity
          ..setFrom(b.position - p.position)
          ..normalize()
          ..scale(4.5 * p.massClass.impactDamage)
          ..y += 3.4;
        score.blocksDestroyed++;
        score.addDestruction(60);
        effects.burst(
          at: b.position.clone(),
          count: 6,
          colour: Vector4(0.55, 0.62, 0.75, 1),
          speed: 5.0,
          life: 0.9,
          size: 0.13,
          gravity: 12,
          shape: ParticleShape.cube,
          useDebrisPool: true,
          intensity: settings.value.effectIntensity,
        );
        _onWallProgress();
      }
      return;
    }
  }

  void _onWallProgress() {
    final remaining = _wall.where((b) => b.alive).length;
    if (remaining == 0) {
      audio.play(Sfx.wallDestroy);
      haptics.impact(HapticStrength.heavy, important: true);
      camera.impulse(CameraImpulse.wallBreak);
      _hitStop = math.max(_hitStop, 0.09);
      _toast('BARRIER DESTROYED', const ui.Color(0xFFFF7A2F), life: 1.6);
      effects.ringWave(
        at: level.wall!.centre.clone()..y += 1.2,
        colour: Vector4(1.0, 0.62, 0.25, 0.9),
        radiusEnd: 8.0,
        life: 0.7,
        thickness: 0.3,
      );
      _armourActive = true;
    }
  }

  void _updateWallDebris(double dt) {
    for (final b in _wall) {
      if (b.alive) continue;
      b.deadTime += dt;
      b.velocity.y -= 13.0 * dt;
      b.position.addScaled(b.velocity, dt);
      b.spin += dt * 7;
    }
  }

  // --- armour -----------------------------------------------------------

  void _updateArmour() {
    _armourRemaining = swarm.stats.armourOrbiting;
    if (_armourActive && _armourRemaining > 0 && !_armourAnnounced) {
      _armourAnnounced = true;
      _toast('ARMOUR ONLINE', const ui.Color(0xFF3FE0FF), life: 1.5);
    }
  }

  bool _armourAnnounced = false;

  // --- hazards ----------------------------------------------------------

  void _updateHazards(double dt) {
    for (final h in level.hazards) {
      if (_hazardFired) continue;
      if (_coreZ < h.triggerZ) continue;

      if (!_hazardTelegraphing) {
        _hazardTelegraphing = true;
        _hazardTelegraph = 0;
        _toast('DISCHARGE INCOMING', const ui.Color(0xFFFF7A2F), life: 1.4);
      }
      _hazardTelegraph += dt;

      // Telegraph: pulsing orange sparks from the emitter.
      if (_rng.nextDouble() < dt * 22) {
        effects.burst(
          at: h.position.clone(),
          count: 2,
          colour: Vector4(1.0, 0.45, 0.10, 1),
          speed: 2.2,
          life: 0.4,
          size: 0.07,
          gravity: 1.0,
          shape: ParticleShape.spark,
          intensity: settings.value.effectIntensity,
        );
      }

      if (_hazardTelegraph >= h.telegraphSeconds) {
        _hazardFired = true;
        _fireHazard(h);
      }
    }
  }

  void _fireHazard(HazardSpec h) {
    effects.ringWave(
      at: h.position.clone(),
      colour: Vector4(1.0, 0.42, 0.12, 0.95),
      radiusEnd: 7.0,
      life: 0.5,
      thickness: 0.26,
      tiltX: math.pi / 2,
    );
    effects.burst(
      at: h.position.clone(),
      count: 20,
      colour: Vector4(1.0, 0.50, 0.14, 1),
      speed: 8.5,
      life: 0.55,
      size: 0.09,
      direction: (_corePos - h.position)..normalize(),
      spread: 0.35,
      shape: ParticleShape.spark,
      intensity: settings.value.effectIntensity,
    );

    if (_armourRemaining > 0) {
      // Armour absorbs it and visibly sheds plates.
      final shed = math.min(_armourRemaining, 3);
      var removed = 0;
      for (final p in swarm.pieces) {
        if (removed >= shed) break;
        if (p.kind != PieceKind.armour) continue;
        if (p.state != PieceState.orbiting && p.state != PieceState.capturing) {
          continue;
        }
        p.state = PieceState.launched;
        p.life = 1.4;
        p.hasHit = true;
        p.velocity.setValues(
          (_rng.nextDouble() * 2 - 1) * 5.0,
          3.5 + _rng.nextDouble() * 2.0,
          (_rng.nextDouble() * 2 - 1) * 5.0,
        );
        p.tumbleRate = 8.0;
        removed++;
        score.armourLost++;
      }
      audio.play(Sfx.armourHit);
      audio.play(Sfx.armourBreak, volume: 0.7);
      haptics.impact(HapticStrength.heavy, important: true);
      camera.impulse(CameraImpulse.damage);
      _toast('ARMOUR ABSORBED IMPACT', const ui.Color(0xFF3FE0FF), life: 1.8);
      effects.burst(
        at: _corePos.clone(),
        count: 12,
        colour: Vector4(0.75, 0.85, 1.0, 1),
        speed: 5.0,
        life: 0.6,
        size: 0.11,
        shape: ParticleShape.shard,
        useDebrisPool: true,
        intensity: settings.value.effectIntensity,
      );
    } else {
      score.damageTaken += h.damage;
      core.onDamage();
      audio.play(Sfx.armourHit);
      haptics.impact(HapticStrength.heavy, important: true);
      camera.impulse(CameraImpulse.damage);
      _fail('THE CORE TOOK A DIRECT HIT');
    }
  }

  // --- bridge -----------------------------------------------------------

  bool _tryFormBridge() {
    final bridge = level.bridge;
    final gap = level.gap;
    if (bridge == null || gap == null || _bridgeFormed) return false;
    // Must be near the near-side anchor.
    final anchor = bridge.anchors.first;
    if ((_coreZ - anchor.z).abs() > 4.0) return false;
    if (swarm.stats.bridgeOrbiting < bridge.piecesRequired) {
      _toast(
        'NEED ${bridge.piecesRequired - swarm.stats.bridgeOrbiting} MORE BEAMS',
        const ui.Color(0xFFFF7A2F),
        life: 1.6,
      );
      return false;
    }

    _bridgeFormed = true;
    _bridgeBuild = 0;

    // Lay the collected beams across the span.
    final used = <MetalPiece>[];
    for (final p in swarm.pieces) {
      if (p.kind != PieceKind.bridge) continue;
      if (p.state != PieceState.orbiting && p.state != PieceState.capturing) {
        continue;
      }
      used.add(p);
    }
    for (var i = 0; i < used.length; i++) {
      final t = used.length == 1 ? 0.5 : i / (used.length - 1);
      final p = used[i];
      p.state = PieceState.capturing;
      p.captureT = 0;
      p.captureDuration = 0.45 + i * 0.05;
      p.captureFrom.setFrom(p.position);
      p.captureControl
        ..setFrom(p.position)
        ..y += 1.6;
      // Park it on the span; _updateBridge holds it there.
      p.homePosition.setValues(
        bridge.spanFrom.x + (bridge.spanTo.x - bridge.spanFrom.x) * t,
        bridge.spanFrom.y - 0.30,
        bridge.spanFrom.z + (bridge.spanTo.z - bridge.spanFrom.z) * t,
      );
    }
    _bridgeBeams
      ..clear()
      ..addAll(used);

    audio.play(Sfx.bridgeAssemble);
    haptics.impact(HapticStrength.medium, important: true);
    camera.impulse(CameraImpulse.collectMilestone);
    _toast('BRIDGE FORMED', const ui.Color(0xFF3FE0FF), life: 2.0);
    score.addDestruction(150);
    charge.reset();
    return true;
  }

  final List<MetalPiece> _bridgeBeams = [];

  void _updateBridge(double dt) {
    if (!_bridgeFormed) return;
    _bridgeBuild = math.min(1.0, _bridgeBuild + dt * 1.6);
    for (var i = 0; i < _bridgeBeams.length; i++) {
      final p = _bridgeBeams[i];
      p.state = PieceState.idle;
      final target = p.homePosition;
      p.position.addScaled(target - p.position, math.min(1.0, dt * 6.0));
      p.tumbleX *= 0.90;
      p.tumbleY *= 0.90;
    }
    if (_bridgeBuild >= 1.0 && !_bridgeLocked) {
      _bridgeLocked = true;
      audio.play(Sfx.bridgeLock);
      final gap = level.gap!;
      effects.ringWave(
        at: Vector3(0, 0, (gap.startZ + gap.endZ) * 0.5),
        colour: Vector4(0.4, 0.95, 1.0, 0.9),
        radiusEnd: 6.0,
        life: 0.8,
        tiltX: math.pi / 2,
      );
    }
  }

  bool _bridgeLocked = false;

  // --- key / portal -----------------------------------------------------

  bool _keyReachable(MetalPiece key) {
    // The key sits behind bars: it can only be pulled through once the Core is
    // close enough and roughly aligned with the opening.
    final k = level.key!;
    if ((_coreZ - k.position.z).abs() > 9.0) return false;
    return (_corePos.x - k.position.x).abs() < 2.2;
  }

  void _updateKeyAndPortal(double dt) {
    _updateBridge(dt);

    if (!_portalUnlocked && _keyCollected) {
      _portalCharge = math.min(1.0, _portalCharge + dt * 0.9);
      if (_portalCharge >= 1.0) {
        _portalUnlocked = true;
        audio.play(Sfx.portalUnlock);
        haptics.impact(HapticStrength.heavy, important: true);
        camera.impulse(CameraImpulse.collectMilestone);
        _toast('PORTAL UNLOCKED', const ui.Color(0xFF3FE0FF), life: 2.0);
        effects.ringWave(
          at: level.portal.position.clone()..y += 1.75,
          colour: Vector4(0.45, 0.95, 1.0, 0.95),
          radiusEnd: 6.5,
          life: 0.9,
          tiltX: math.pi / 2,
        );
      }
    }

    // Reaching the portal.
    if (_portalUnlocked && _coreZ >= level.portal.position.z - 0.6) {
      _complete();
    } else if (!_portalUnlocked && _coreZ >= level.portal.position.z - 1.4) {
      // Held at a locked portal: stop and tell the player why.
      _coreZ = level.portal.position.z - 1.4;
      if (!_lockedAnnounced) {
        _lockedAnnounced = true;
        _toast(
          'PORTAL LOCKED — FIND THE KEY',
          const ui.Color(0xFFFF7A2F),
          life: 2.4,
        );
      }
    }
  }

  bool _lockedAnnounced = false;

  void _complete() {
    if (phase == GamePhase.complete) return;
    phase = GamePhase.complete;
    _completeT = 0;
    core.onComplete();
    camera.startCompletionOrbit();
    audio.play(Sfx.levelComplete);
    haptics.impact(HapticStrength.heavy, important: true);
    audio.setAttracting(false, 0);
    effects.ringWave(
      at: _corePos.clone(),
      colour: Vector4(0.6, 1.0, 1.0, 1.0),
      radiusEnd: 11.0,
      life: 1.2,
      thickness: 0.34,
    );
    effects.burst(
      at: _corePos.clone(),
      count: 46,
      colour: Vector4(0.7, 1.0, 1.0, 1),
      speed: 7.5,
      life: 1.4,
      size: 0.11,
      gravity: -1.6,
      shape: ParticleShape.shard,
      intensity: settings.value.effectIntensity,
    );
  }

  void _updateComplete(double dt) {
    _completeT += dt;
    // Fragments rise, swarm slowly spirals up into the portal.
    for (final p in swarm.pieces) {
      if (p.state == PieceState.orbiting) {
        p.position.y += dt * 0.9;
      }
    }
    swarm.update(
      dt,
      _corePos,
      charge: 0,
      stageThresholds: level.swarmStages,
      trailSegments: quality.trailSegments,
    );
    if (_completeT < 1.2 && _rng.nextDouble() < dt * 12) {
      effects.burst(
        at: _corePos.clone(),
        count: 3,
        colour: Vector4(0.7, 1.0, 1.0, 1),
        speed: 3.0,
        life: 1.0,
        size: 0.09,
        gravity: -2.0,
        shape: ParticleShape.spark,
        intensity: settings.value.effectIntensity,
      );
    }
  }

  void _checkFailure() {
    // Fell into the void.
    if (_corePos.y < -6.0) {
      _fail('THE CORE FELL INTO THE VOID');
      return;
    }

    // Soft-lock guard. If the route is blocked and there is no metal left
    // anywhere the Core could reach, the run cannot continue — say so and
    // offer an instant retry rather than leaving the player sitting there.
    final blocked = _isBlockedByWall() || _isOverGapWithoutBridge();
    if (!blocked || swarm.stats.orbiting > 0) {
      _stuckFor = 0;
      return;
    }
    var reachable = 0;
    for (final p in swarm.pieces) {
      if (p.state != PieceState.idle) continue;
      if (p.kind == PieceKind.armour && !_armourActive) continue;
      // Generous: anything ahead of the Core is potentially reachable once it
      // advances, so only count what is genuinely within grabbing distance.
      if ((p.position - _corePos).length <= field.rangeAt(1.0) + 1.0) {
        reachable++;
      }
    }
    if (reachable > 0) {
      _stuckFor = 0;
      return;
    }
    _stuckFor += 1 / 60.0;
    if (_stuckFor > 3.0) {
      _fail('OUT OF METAL — NOTHING LEFT TO ATTRACT');
    }
  }

  double _stuckFor = 0;

  void _fail(String reason) {
    if (phase == GamePhase.failed || phase == GamePhase.complete) return;
    phase = GamePhase.failed;
    failureReason = reason;
    audio.play(Sfx.failure);
    audio.setAttracting(false, 0);
    haptics.impact(HapticStrength.heavy, important: true);
    camera.impulse(CameraImpulse.damage);
    effects.burst(
      at: _corePos.clone(),
      count: 30,
      colour: Vector4(1.0, 0.35, 0.28, 1),
      speed: 7.0,
      life: 0.9,
      size: 0.10,
      shape: ParticleShape.shard,
      intensity: settings.value.effectIntensity,
    );
  }

  // --- props ------------------------------------------------------------

  void _updateProps(double dt) {
    final t = _time;

    // Portal: rings idle-spin; once unlocked they accelerate and the energy
    // disc fades in.
    final portal = _portalNode;
    if (portal != null) {
      final spin = t * (_portalUnlocked ? 2.6 : 0.5);
      portal.localTransform = Matrix4.identity()
        ..setTranslation(level.portal.position)
        ..rotateZ(spin * 0.4);
      for (var i = 0; i < portal.children.length; i++) {
        portal.children[i].localTransform = Matrix4.identity()
          ..rotateZ(spin * (i.isEven ? 1.0 : -1.4));
      }
    }
    final disc = _portalDisc;
    if (disc != null) {
      final s = _portalCharge;
      disc.visible = s > 0.01;
      disc.localTransform = Matrix4.identity()
        ..setTranslation(level.portal.position)
        ..rotateZ(t * 1.6)
        ..scaleByDouble(s, s, s, 1.0);
    }

    // Hazard emitter leans toward the Core while telegraphing.
    final hazard = _hazardNode;
    if (hazard != null && level.hazards.isNotEmpty) {
      final h = level.hazards.first;
      final pulse = _hazardTelegraphing && !_hazardFired
          ? 1.0 + math.sin(t * 26.0) * 0.10
          : 1.0;
      hazard.localTransform = Matrix4.identity()
        ..setTranslation(h.position)
        ..scaleByDouble(pulse, pulse, pulse, 1.0);
    }

    // Key bars retract into the deck once the key is out.
    final bars = _keyBarsNode;
    if (bars != null && level.key != null) {
      final k = level.key!;
      _barRetract +=
          ((_keyCollected ? 1.0 : 0.0) - _barRetract) * math.min(1.0, dt * 2.2);
      bars.localTransform = Matrix4.identity()
        ..setTranslation(
          Vector3(
            k.barsPosition.x,
            k.barsPosition.y - _barRetract * 1.9,
            k.barsPosition.z,
          ),
        );
    }
  }

  double _barRetract = 0;

  void _updateToasts(double dt) {
    for (final t in toasts) {
      t.life -= dt;
    }
    toasts.removeWhere((t) => t.life <= 0);
  }

  void _toast(String text, ui.Color colour, {double life = 1.6}) {
    if (toasts.any((t) => t.text == text)) return;
    if (toasts.length > 3) toasts.removeAt(0);
    toasts.add(Toast(text, colour, life));
  }

  // -------------------------------------------------------------------------
  // Rendering
  // -------------------------------------------------------------------------

  void _rebuildBatches() {
    _metalBatch.begin();
    _glowBatch.begin();

    final hot = Vector4(1.35, 1.55, 1.70, 1);
    final trailColour = Vector4(0.35, 0.92, 1.0, 0.85);
    final maxTrail = quality.trailSegments;

    for (final p in swarm.pieces) {
      if (p.state == PieceState.dead) continue;
      final tint = Vector4.copy(p.tint);
      if (p.flash > 0.01) {
        final f = p.flash;
        tint
          ..x += f * 1.6
          ..y += f * 1.9
          ..z += f * 2.1;
      } else if (p.state == PieceState.orbiting ||
          p.state == PieceState.capturing) {
        tint.multiply(hot);
      }
      _metalBatch.add(p.template, p.transform(), tint);

      if (maxTrail > 0 &&
          p.trailCount > 1 &&
          (p.state == PieceState.launched || p.state == PieceState.capturing)) {
        stampTrail(
          _glowBatch,
          effects.sparkTemplate,
          p.trail,
          p.trailCount,
          p.kind == PieceKind.key ? Vector4(1.0, 0.80, 0.30, 0.9) : trailColour,
          width: 0.09 * p.scale,
          maxSegments: maxTrail,
        );
      }
    }

    for (final b in _wall) {
      if (!b.alive && b.deadTime > 2.4) continue;
      _metalBatch.add(
        effects.cubeTemplate,
        b.transform(),
        b.alive ? Vector4(0.42, 0.47, 0.58, 1) : Vector4(0.95, 0.52, 0.24, 1),
        useTemplateColors: false,
      );
    }

    effects.render(_glowBatch, _metalBatch);

    _metalBatch.flush(scene);
    _glowBatch.flush(scene);
  }

  int get batchTriangles =>
      _metalBatch.triangleCount + _glowBatch.triangleCount;

  void render(ui.Canvas canvas, ui.Size size, double dt) {
    if (!loaded) return;
    final cam = camera.update(
      dt,
      corePos: _corePos,
      level: level,
      swarmFraction: swarm.fraction,
      aspect: size.height <= 0 ? 0.45 : size.width / size.height,
      shakeEnabled: settings.value.cameraShake,
      reducedMotion: settings.value.reducedMotion,
    );
    // Outside `assert`, so it also works in a *release* build. Release runs
    // roughly three times faster than debug on the emulator, which is the
    // difference between a scripted playthrough that can reach the end of the
    // level and one that stalls. `kLogCamera` is a const, so this whole block
    // is tree-shaken away when the define is absent.
    if (kLogCamera) {
      _camLog += dt;
      if (_camLog > 1.0) {
        _camLog = 0;
        // ignore: avoid_print
        print(
          '[state] coreZ=${_coreZ.toStringAsFixed(1)} '
          'phase=${phase.name} '
          'wallAlive=${_wall.where((b) => b.alive).length}/${_wall.length} '
          'orbit=${swarm.stats.orbiting} '
          'idle=${swarm.pieces.where((p) => p.state == PieceState.idle).length} '
          'dead=${swarm.pieces.where((p) => p.state == PieceState.dead).length} '
          'armour=$_armourRemaining '
          'bridge=$_bridgeFormed key=$_keyCollected portal=$_portalUnlocked '
          'blocked=${_isBlockedByWall()} gap=${_isOverGapWithoutBridge()} '
          'eye=(${cam.position.x.toStringAsFixed(1)},'
          '${cam.position.y.toStringAsFixed(1)},'
          '${cam.position.z.toStringAsFixed(1)}) '
          'fovY=${(cam.fovRadiansY * 57.2958).toStringAsFixed(1)}',
        );
      }
    }
    _sky.paint(canvas, size, _time, _coreZ);

    if (_flipY) {
      canvas.save();
      canvas.translate(0, size.height);
      canvas.scale(1, -1);
      scene.render(cam, canvas, viewport: ui.Offset.zero & size);
      canvas.restore();
    } else {
      scene.render(cam, canvas, viewport: ui.Offset.zero & size);
    }
  }

  double _camLog = 0;
}
