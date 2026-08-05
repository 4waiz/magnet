/// Level description and its JSON parser.
///
/// Levels are data, not code: `assets/levels/level_01.json` drives everything
/// the runtime places, so the layout can change without touching Dart and can
/// be checked by [LevelValidator] before it ever reaches a device.
library;

import 'dart:convert';

import 'package:vector_math/vector_math.dart';

class LevelParseException implements Exception {
  LevelParseException(this.message);
  final String message;
  @override
  String toString() => 'LevelParseException: $message';
}

// ---------------------------------------------------------------------------
// Value types
// ---------------------------------------------------------------------------

enum MassClass { light, medium, heavy }

MassClass _massFromName(String? s) => switch (s) {
  'light' => MassClass.light,
  'heavy' => MassClass.heavy,
  _ => MassClass.medium,
};

extension MassClassPhysics on MassClass {
  /// Heavier pieces resist the field briefly and hit harder on release.
  double get mass => switch (this) {
    MassClass.light => 0.55,
    MassClass.medium => 1.0,
    MassClass.heavy => 2.1,
  };

  double get impactDamage => switch (this) {
    MassClass.light => 0.7,
    MassClass.medium => 1.0,
    MassClass.heavy => 1.9,
  };
}

class PlatformPlacement {
  const PlatformPlacement({
    required this.asset,
    required this.position,
    this.rotationY = 0,
    this.scale = 1,
    this.decorative = false,
  });

  final String asset;
  final Vector3 position;
  final double rotationY;
  final double scale;

  /// Decorative platforms are culled first on low quality and never carry
  /// gameplay collision.
  final bool decorative;
}

class MetalGroup {
  const MetalGroup({
    required this.id,
    required this.centre,
    required this.count,
    required this.spread,
    required this.massClass,
    required this.templates,
    this.stage = 0,
  });

  final String id;
  final Vector3 centre;
  final int count;
  final Vector3 spread;
  final MassClass massClass;

  /// Asset paths of the low-poly silhouettes this group draws from.
  final List<String> templates;

  /// Which swarm stage this group is intended to feed. Used by the validator
  /// to check the level can actually reach its required stages.
  final int stage;
}

class ArmourGroup {
  const ArmourGroup({
    required this.centre,
    required this.count,
    required this.spread,
    required this.templates,
    required this.absorbs,
  });

  final Vector3 centre;
  final int count;
  final Vector3 spread;
  final List<String> templates;

  /// How many hazard hits the armour can absorb before the Core takes damage.
  final int absorbs;
}

class BreakableWall {
  const BreakableWall({
    required this.centre,
    required this.columns,
    required this.rows,
    required this.blockSize,
    required this.hitsPerBlock,
  });

  final Vector3 centre;
  final int columns;
  final int rows;
  final double blockSize;
  final int hitsPerBlock;

  int get blockCount => columns * rows;
}

class HazardSpec {
  const HazardSpec({
    required this.id,
    required this.position,
    required this.triggerZ,
    required this.telegraphSeconds,
    required this.damage,
  });

  final String id;
  final Vector3 position;

  /// The Core's forward position at which the telegraph begins.
  final double triggerZ;
  final double telegraphSeconds;
  final int damage;
}

class BridgeSpec {
  const BridgeSpec({
    required this.pieceCount,
    required this.piecesRequired,
    required this.pieceCentre,
    required this.pieceSpread,
    required this.anchors,
    required this.spanFrom,
    required this.spanTo,
    required this.templates,
  });

  final int pieceCount;
  final int piecesRequired;
  final Vector3 pieceCentre;
  final Vector3 pieceSpread;
  final List<Vector3> anchors;
  final Vector3 spanFrom;
  final Vector3 spanTo;
  final List<String> templates;
}

class GapSpec {
  const GapSpec({required this.startZ, required this.endZ});
  final double startZ;
  final double endZ;
  bool contains(double z) => z > startZ && z < endZ;
}

class KeySpec {
  const KeySpec({
    required this.position,
    required this.asset,
    required this.barsAsset,
    required this.barsPosition,
    required this.barGapWidth,
  });

  final Vector3 position;
  final String asset;
  final String barsAsset;
  final Vector3 barsPosition;

  /// The clear width between bars. The key must be narrower than this.
  final double barGapWidth;
}

class PortalSpec {
  const PortalSpec({
    required this.position,
    required this.asset,
    required this.discAsset,
    required this.locked,
    required this.requiresKey,
  });

  final Vector3 position;
  final String asset;
  final String discAsset;
  final bool locked;
  final bool requiresKey;
}

class CameraZone {
  const CameraZone({
    required this.startZ,
    required this.endZ,
    required this.distance,
    required this.height,
    required this.fovDegrees,
    this.lookAhead = 2.0,
    this.lateral = 0.45,
  });

  final double startZ;
  final double endZ;
  final double distance;
  final double height;
  final double fovDegrees;
  final double lookAhead;
  final double lateral;

  bool contains(double z) => z >= startZ && z < endZ;
}

class Objective {
  const Objective({
    required this.id,
    required this.description,
    required this.target,
  });
  final String id;
  final String description;
  final int target;
}

// ---------------------------------------------------------------------------
// Level
// ---------------------------------------------------------------------------

class LevelData {
  const LevelData({
    required this.id,
    required this.world,
    required this.index,
    required this.name,
    required this.coreStart,
    required this.coreSpeed,
    required this.route,
    required this.platforms,
    required this.metalGroups,
    required this.armour,
    required this.wall,
    required this.hazards,
    required this.bridge,
    required this.gap,
    required this.key,
    required this.portal,
    required this.cameraZones,
    required this.swarmStages,
    required this.swarmCapacity,
    required this.objectives,
    required this.finishZ,
  });

  final String id;
  final int world;
  final int index;
  final String name;

  final Vector3 coreStart;
  final double coreSpeed;
  final List<Vector3> route;
  final List<PlatformPlacement> platforms;
  final List<MetalGroup> metalGroups;
  final ArmourGroup? armour;
  final BreakableWall? wall;
  final List<HazardSpec> hazards;
  final BridgeSpec? bridge;
  final GapSpec? gap;
  final KeySpec? key;
  final PortalSpec portal;
  final List<CameraZone> cameraZones;

  /// Object counts at which the swarm visibly steps up a stage.
  final List<int> swarmStages;
  final int swarmCapacity;
  final List<Objective> objectives;
  final double finishZ;

  /// Total metal the level actually spawns, across every group.
  int get totalMetal =>
      metalGroups.fold(0, (a, g) => a + g.count) +
      (armour?.count ?? 0) +
      (bridge?.pieceCount ?? 0);

  /// Every asset path the level references.
  Set<String> get referencedAssets => {
    for (final p in platforms) p.asset,
    for (final g in metalGroups) ...g.templates,
    if (armour != null) ...armour!.templates,
    if (bridge != null) ...bridge!.templates,
    if (key != null) ...[key!.asset, key!.barsAsset],
    portal.asset,
    portal.discAsset,
  };

  /// Interpolates the authored route to a position at forward distance [z].
  Vector3 routeAt(double z) {
    if (route.isEmpty) return Vector3(0, 0, z);
    if (z <= route.first.z) return route.first.clone();
    for (var i = 0; i < route.length - 1; i++) {
      final a = route[i], b = route[i + 1];
      if (z >= a.z && z <= b.z) {
        final span = (b.z - a.z).abs();
        final t = span < 1e-6 ? 0.0 : (z - a.z) / span;
        // Smoothstep so route bends ease rather than corner.
        final e = t * t * (3 - 2 * t);
        return Vector3(a.x + (b.x - a.x) * e, a.y + (b.y - a.y) * e, z);
      }
    }
    final last = route.last;
    return Vector3(last.x, last.y, z);
  }

  CameraZone cameraZoneAt(double z) {
    for (final zone in cameraZones) {
      if (zone.contains(z)) return zone;
    }
    return cameraZones.isNotEmpty
        ? cameraZones.last
        : const CameraZone(
            startZ: 0,
            endZ: 1e9,
            distance: 11,
            height: 6.4,
            fovDegrees: 46,
          );
  }

  // -------------------------------------------------------------------------
  // Parsing
  // -------------------------------------------------------------------------

  static LevelData fromJsonString(String source) =>
      fromJson(jsonDecode(source) as Map<String, dynamic>);

  static LevelData fromJson(Map<String, dynamic> j) {
    T req<T>(String key) {
      final v = j[key];
      if (v == null) throw LevelParseException('missing required field "$key"');
      if (v is! T) {
        throw LevelParseException(
          'field "$key" should be $T but was ${v.runtimeType}',
        );
      }
      return v;
    }

    return LevelData(
      id: req<String>('id'),
      world: (j['world'] as num?)?.toInt() ?? 1,
      index: (j['index'] as num?)?.toInt() ?? 1,
      name: j['name'] as String? ?? req<String>('id'),
      coreStart: _vec(j['coreStart']) ?? Vector3(0, 0.95, 0),
      coreSpeed: (j['coreSpeed'] as num?)?.toDouble() ?? 5.0,
      route: _vecList(j['route']),
      platforms: _list(j['platforms']).map(_platform).toList(),
      metalGroups: _list(j['metalGroups']).map(_metalGroup).toList(),
      armour: j['armour'] == null
          ? null
          : _armour(j['armour'] as Map<String, dynamic>),
      wall: j['wall'] == null ? null : _wall(j['wall'] as Map<String, dynamic>),
      hazards: _list(j['hazards']).map(_hazard).toList(),
      bridge: j['bridge'] == null
          ? null
          : _bridge(j['bridge'] as Map<String, dynamic>),
      gap: j['gap'] == null
          ? null
          : GapSpec(
              startZ: (j['gap']['startZ'] as num).toDouble(),
              endZ: (j['gap']['endZ'] as num).toDouble(),
            ),
      key: j['key'] == null ? null : _key(j['key'] as Map<String, dynamic>),
      portal: _portal(req<Map<String, dynamic>>('portal')),
      cameraZones: _list(j['cameraZones']).map(_cameraZone).toList(),
      swarmStages: _list(
        j['swarmStages'],
      ).map((e) => (e as num).toInt()).toList(growable: false),
      swarmCapacity: (j['swarmCapacity'] as num?)?.toInt() ?? 120,
      objectives: _list(j['objectives'])
          .map(
            (e) => Objective(
              id: e['id'] as String,
              description: e['description'] as String? ?? '',
              target: (e['target'] as num?)?.toInt() ?? 1,
            ),
          )
          .toList(),
      finishZ: (j['finishZ'] as num?)?.toDouble() ?? 100.0,
    );
  }

  static List<dynamic> _list(Object? v) => v is List ? v : const <dynamic>[];

  static Vector3? _vec(Object? v) {
    if (v is List && v.length >= 3) {
      return Vector3(
        (v[0] as num).toDouble(),
        (v[1] as num).toDouble(),
        (v[2] as num).toDouble(),
      );
    }
    return null;
  }

  static List<Vector3> _vecList(Object? v) =>
      _list(v).map(_vec).whereType<Vector3>().toList();

  static PlatformPlacement _platform(dynamic e) => PlatformPlacement(
    asset: e['asset'] as String,
    position: _vec(e['position']) ?? Vector3.zero(),
    rotationY: (e['rotationY'] as num?)?.toDouble() ?? 0,
    scale: (e['scale'] as num?)?.toDouble() ?? 1,
    decorative: e['decorative'] as bool? ?? false,
  );

  static MetalGroup _metalGroup(dynamic e) => MetalGroup(
    id: e['id'] as String? ?? 'metal',
    centre: _vec(e['centre']) ?? Vector3.zero(),
    count: (e['count'] as num?)?.toInt() ?? 0,
    spread: _vec(e['spread']) ?? Vector3(3, 1, 4),
    massClass: _massFromName(e['massClass'] as String?),
    templates: _list(e['templates']).cast<String>(),
    stage: (e['stage'] as num?)?.toInt() ?? 0,
  );

  static ArmourGroup _armour(Map<String, dynamic> e) => ArmourGroup(
    centre: _vec(e['centre']) ?? Vector3.zero(),
    count: (e['count'] as num?)?.toInt() ?? 0,
    spread: _vec(e['spread']) ?? Vector3(3, 1, 3),
    templates: _list(e['templates']).cast<String>(),
    absorbs: (e['absorbs'] as num?)?.toInt() ?? 1,
  );

  static BreakableWall _wall(Map<String, dynamic> e) => BreakableWall(
    centre: _vec(e['centre']) ?? Vector3.zero(),
    columns: (e['columns'] as num?)?.toInt() ?? 7,
    rows: (e['rows'] as num?)?.toInt() ?? 4,
    blockSize: (e['blockSize'] as num?)?.toDouble() ?? 0.62,
    hitsPerBlock: (e['hitsPerBlock'] as num?)?.toInt() ?? 1,
  );

  static HazardSpec _hazard(dynamic e) => HazardSpec(
    id: e['id'] as String? ?? 'hazard',
    position: _vec(e['position']) ?? Vector3.zero(),
    triggerZ: (e['triggerZ'] as num?)?.toDouble() ?? 0,
    telegraphSeconds: (e['telegraphSeconds'] as num?)?.toDouble() ?? 1.2,
    damage: (e['damage'] as num?)?.toInt() ?? 1,
  );

  static BridgeSpec _bridge(Map<String, dynamic> e) => BridgeSpec(
    pieceCount: (e['pieceCount'] as num?)?.toInt() ?? 0,
    piecesRequired: (e['piecesRequired'] as num?)?.toInt() ?? 0,
    pieceCentre: _vec(e['pieceCentre']) ?? Vector3.zero(),
    pieceSpread: _vec(e['pieceSpread']) ?? Vector3(3, 1, 3),
    anchors: _vecList(e['anchors']),
    spanFrom: _vec(e['spanFrom']) ?? Vector3.zero(),
    spanTo: _vec(e['spanTo']) ?? Vector3.zero(),
    templates: _list(e['templates']).cast<String>(),
  );

  static KeySpec _key(Map<String, dynamic> e) => KeySpec(
    position: _vec(e['position']) ?? Vector3.zero(),
    asset: e['asset'] as String? ?? 'assets/models/metal/magnetic_key.glb',
    barsAsset:
        e['barsAsset'] as String? ??
        'assets/models/obstacles/obstacle_key_chamber.glb',
    barsPosition: _vec(e['barsPosition']) ?? Vector3.zero(),
    barGapWidth: (e['barGapWidth'] as num?)?.toDouble() ?? 0.37,
  );

  static PortalSpec _portal(Map<String, dynamic> e) => PortalSpec(
    position: _vec(e['position']) ?? Vector3.zero(),
    asset:
        e['asset'] as String? ??
        'assets/models/obstacles/obstacle_finish_portal.glb',
    discAsset:
        e['discAsset'] as String? ??
        'assets/models/obstacles/obstacle_portal_disc.glb',
    locked: e['locked'] as bool? ?? true,
    requiresKey: e['requiresKey'] as bool? ?? true,
  );

  static CameraZone _cameraZone(dynamic e) => CameraZone(
    startZ: (e['startZ'] as num).toDouble(),
    endZ: (e['endZ'] as num).toDouble(),
    distance: (e['distance'] as num?)?.toDouble() ?? 11,
    height: (e['height'] as num?)?.toDouble() ?? 6.4,
    fovDegrees: (e['fovDegrees'] as num?)?.toDouble() ?? 46,
    lookAhead: (e['lookAhead'] as num?)?.toDouble() ?? 2.0,
    lateral: (e['lateral'] as num?)?.toDouble() ?? 0.45,
  );
}
