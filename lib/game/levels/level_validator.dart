/// Static checks a level must pass before it can be shipped or played.
///
/// The point is to turn "the level is subtly unfinishable" into a build-time
/// error. Every rule here corresponds to a way a level can look fine in the
/// editor and then strand the player: a locked portal with no key, a bridge
/// that needs more pieces than exist, a hazard sitting on the spawn.
library;

import '../levels/level_data.dart';

enum IssueSeverity { error, warning }

class ValidationIssue {
  const ValidationIssue(this.severity, this.code, this.message);
  final IssueSeverity severity;
  final String code;
  final String message;

  bool get isError => severity == IssueSeverity.error;

  @override
  String toString() => '[${severity.name.toUpperCase()}] $code: $message';
}

class ValidationResult {
  const ValidationResult(this.issues);
  final List<ValidationIssue> issues;

  bool get isValid => issues.every((i) => !i.isError);
  List<ValidationIssue> get errors => issues.where((i) => i.isError).toList();
  List<ValidationIssue> get warnings =>
      issues.where((i) => !i.isError).toList();

  @override
  String toString() => issues.isEmpty
      ? 'valid (no issues)'
      : issues.map((i) => i.toString()).join('\n');
}

class LevelValidator {
  const LevelValidator({this.knownAssets = const <String>{}});

  /// Asset paths known to exist. When empty, the asset-existence rule is
  /// skipped so unit tests need no bundle.
  final Set<String> knownAssets;

  ValidationResult validate(LevelData level) {
    final issues = <ValidationIssue>[];
    void err(String code, String msg) =>
        issues.add(ValidationIssue(IssueSeverity.error, code, msg));
    void warn(String code, String msg) =>
        issues.add(ValidationIssue(IssueSeverity.warning, code, msg));

    // --- assets ---------------------------------------------------------
    if (knownAssets.isNotEmpty) {
      for (final asset in level.referencedAssets) {
        if (!knownAssets.contains(asset)) {
          err('missing_asset', 'referenced asset does not exist: $asset');
        }
      }
    }

    // --- unknown object types -------------------------------------------
    const validPrefixes = [
      'assets/models/platforms/',
      'assets/models/obstacles/',
      'assets/models/metal/',
      'assets/models/core/',
    ];
    for (final asset in level.referencedAssets) {
      if (!validPrefixes.any(asset.startsWith)) {
        err(
          'unknown_object_type',
          'asset is outside every known model category: $asset',
        );
      }
    }

    // --- route ----------------------------------------------------------
    if (level.route.length < 2) {
      err(
        'invalid_route',
        'route needs at least 2 points, has ${level.route.length}',
      );
    } else {
      for (var i = 1; i < level.route.length; i++) {
        if (level.route[i].z <= level.route[i - 1].z) {
          err(
            'invalid_route',
            'route points must strictly advance in z; point $i '
                '(z=${level.route[i].z}) does not follow '
                '${level.route[i - 1].z}',
          );
        }
      }
      if (level.route.last.z < level.finishZ) {
        err(
          'invalid_route',
          'route ends at z=${level.route.last.z} before finishZ='
              '${level.finishZ}',
        );
      }
    }

    // --- platforms ------------------------------------------------------
    if (level.platforms.isEmpty) {
      err('invalid_platform_reference', 'level has no platforms');
    }
    final playable = level.platforms
        .where((p) => !p.decorative)
        .toList(growable: false);
    if (playable.isEmpty) {
      err(
        'invalid_platform_reference',
        'every platform is marked decorative; nothing is walkable',
      );
    }
    for (final p in level.platforms) {
      if (p.scale <= 0) {
        err(
          'invalid_platform_reference',
          'platform ${p.asset} has non-positive scale ${p.scale}',
        );
      }
    }

    // --- portal ---------------------------------------------------------
    if (level.portal.position.z <= level.coreStart.z) {
      err(
        'missing_finish_portal',
        'portal must be ahead of the Core start position',
      );
    }
    if (level.portal.requiresKey && level.key == null) {
      err(
        'missing_key_for_locked_portal',
        'portal requires a key but the level defines none',
      );
    }
    if (!level.portal.locked && level.portal.requiresKey) {
      warn(
        'portal_unlocked_but_requires_key',
        'portal is unlocked yet still marked requiresKey',
      );
    }

    // --- key / bars -----------------------------------------------------
    final key = level.key;
    if (key != null) {
      if (key.barGapWidth <= 0) {
        err('invalid_bars', 'bar gap width must be positive');
      } else if (key.barGapWidth < 0.22) {
        err(
          'invalid_bars',
          'bar gap ${key.barGapWidth} m is narrower than the key can pass',
        );
      }
      if (key.position.z >= level.portal.position.z) {
        err('invalid_key_placement', 'key must be reachable before the portal');
      }
    }

    // --- bridge / gap ---------------------------------------------------
    final bridge = level.bridge;
    final gap = level.gap;
    if (gap != null && bridge == null) {
      err(
        'insufficient_bridge_pieces',
        'level has a gap but no bridge specification',
      );
    }
    if (bridge != null) {
      if (bridge.pieceCount < bridge.piecesRequired) {
        err(
          'insufficient_bridge_pieces',
          'bridge needs ${bridge.piecesRequired} pieces but only '
              '${bridge.pieceCount} spawn',
        );
      }
      if (bridge.anchors.length < 2) {
        err(
          'insufficient_bridge_anchors',
          'bridge needs at least 2 anchors, has ${bridge.anchors.length}',
        );
      }
      if (gap != null) {
        if (bridge.pieceCentre.z > gap.startZ) {
          err(
            'invalid_bridge_placement',
            'bridge pieces spawn past the gap they are meant to cross',
          );
        }
        if (bridge.spanFrom.z > gap.startZ + 0.5 ||
            bridge.spanTo.z < gap.endZ - 0.5) {
          warn('bridge_span_short', 'bridge span does not fully cover the gap');
        }
      }
    }
    if (gap != null && gap.endZ <= gap.startZ) {
      err('invalid_gap', 'gap endZ must be greater than startZ');
    }

    // --- hazards --------------------------------------------------------
    for (final h in level.hazards) {
      final dz = (h.position.z - level.coreStart.z).abs();
      final dx = (h.position.x - level.coreStart.x).abs();
      if (dz < 6.0 && dx < 3.0) {
        err(
          'hazard_overlaps_spawn',
          'hazard "${h.id}" is ${dz.toStringAsFixed(1)} m from the Core '
              'spawn; the player cannot react',
        );
      }
      if (h.triggerZ >= h.position.z) {
        err(
          'hazard_trigger_too_late',
          'hazard "${h.id}" triggers at or after its own position, so the '
              'telegraph never plays',
        );
      }
      if (h.telegraphSeconds < 0.4) {
        err(
          'hazard_telegraph_too_short',
          'hazard "${h.id}" telegraphs for only ${h.telegraphSeconds}s',
        );
      }
    }

    // --- camera zones ---------------------------------------------------
    if (level.cameraZones.isEmpty) {
      err('invalid_camera_zone', 'level defines no camera zones');
    } else {
      final sorted = [...level.cameraZones]
        ..sort((a, b) => a.startZ.compareTo(b.startZ));
      if (sorted.first.startZ > level.coreStart.z) {
        err(
          'invalid_camera_zone',
          'first camera zone starts after the Core spawn',
        );
      }
      for (final z in sorted) {
        if (z.endZ <= z.startZ) {
          err(
            'invalid_camera_zone',
            'camera zone ${z.startZ}..${z.endZ} is empty or inverted',
          );
        }
        if (z.distance <= 0 || z.height <= 0) {
          err(
            'invalid_camera_zone',
            'camera zone ${z.startZ} has non-positive distance/height',
          );
        }
        if (z.fovDegrees < 20 || z.fovDegrees > 90) {
          err(
            'invalid_camera_zone',
            'camera zone ${z.startZ} fov ${z.fovDegrees} is out of range',
          );
        }
      }
      for (var i = 1; i < sorted.length; i++) {
        if (sorted[i].startZ > sorted[i - 1].endZ + 0.001) {
          warn(
            'camera_zone_gap',
            'no camera zone covers z ${sorted[i - 1].endZ}..'
                '${sorted[i].startZ}',
          );
        }
      }
      if (sorted.last.endZ < level.finishZ) {
        err(
          'invalid_camera_zone',
          'camera zones stop at ${sorted.last.endZ} before finishZ '
              '${level.finishZ}',
        );
      }
    }

    // --- swarm feasibility ----------------------------------------------
    if (level.swarmStages.isEmpty) {
      warn('no_swarm_stages', 'level defines no swarm stage thresholds');
    } else {
      for (var i = 1; i < level.swarmStages.length; i++) {
        if (level.swarmStages[i] <= level.swarmStages[i - 1]) {
          err(
            'impossible_swarm_requirement',
            'swarm stages must increase; ${level.swarmStages}',
          );
        }
      }
      final highest = level.swarmStages.last;
      if (highest > level.totalMetal) {
        err(
          'impossible_swarm_requirement',
          'highest swarm stage needs $highest objects but the level only '
              'spawns ${level.totalMetal}',
        );
      }
      if (highest > level.swarmCapacity) {
        err(
          'impossible_swarm_requirement',
          'highest swarm stage ($highest) exceeds swarm capacity '
              '(${level.swarmCapacity})',
        );
      }
    }

    // --- wall -----------------------------------------------------------
    final wall = level.wall;
    if (wall != null) {
      if (wall.blockCount <= 0) {
        err('invalid_wall', 'wall has no blocks');
      }
      final firstStage = level.swarmStages.isEmpty
          ? 1
          : level.swarmStages.first;
      final availableBefore = level.metalGroups
          .where((g) => g.centre.z < wall.centre.z)
          .fold(0, (a, g) => a + g.count);
      if (availableBefore < firstStage) {
        err(
          'impossible_swarm_requirement',
          'only $availableBefore metal pieces spawn before the wall, but '
              'stage 1 needs $firstStage',
        );
      }
    }

    // --- objectives ------------------------------------------------------
    for (final o in level.objectives) {
      if (o.target <= 0) {
        warn(
          'invalid_objective',
          'objective "${o.id}" has non-positive target ${o.target}',
        );
      }
    }

    return ValidationResult(issues);
  }
}
