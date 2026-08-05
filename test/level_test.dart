import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magnet_rush/game/levels/level_data.dart';
import 'package:magnet_rush/game/levels/level_validator.dart';

LevelData loadLevel1() => LevelData.fromJsonString(
  File('assets/levels/level_01.json').readAsStringSync(),
);

Set<String> discoverAssets() {
  final out = <String>{};
  for (final dir in ['core', 'metal', 'platforms', 'obstacles']) {
    final d = Directory('assets/models/$dir');
    if (!d.existsSync()) continue;
    for (final f in d.listSync().whereType<File>()) {
      if (f.path.endsWith('.glb')) {
        out.add('assets/models/$dir/${f.uri.pathSegments.last}');
      }
    }
  }
  return out;
}

Map<String, dynamic> level1Json() =>
    jsonDecode(File('assets/levels/level_01.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  group('LevelData parsing', () {
    test('parses Level 1 completely', () {
      final l = loadLevel1();
      expect(l.id, 'w1_l01');
      expect(l.world, 1);
      expect(l.index, 1);
      expect(l.route.length, greaterThanOrEqualTo(2));
      expect(l.platforms, isNotEmpty);
      expect(l.metalGroups.length, 5);
      expect(l.wall, isNotNull);
      expect(l.armour, isNotNull);
      expect(l.hazards, hasLength(1));
      expect(l.bridge, isNotNull);
      expect(l.gap, isNotNull);
      expect(l.key, isNotNull);
      expect(l.portal.requiresKey, isTrue);
      expect(l.cameraZones, hasLength(6));
      expect(l.swarmStages, [12, 28, 48]);
      expect(l.objectives, hasLength(3));
    });

    test('totalMetal covers every spawned object', () {
      final l = loadLevel1();
      final groups = l.metalGroups.fold(0, (a, g) => a + g.count);
      expect(l.totalMetal, groups + l.armour!.count + l.bridge!.pieceCount);
      expect(l.totalMetal, greaterThanOrEqualTo(l.swarmStages.last));
    });

    test('routeAt interpolates and eases between authored points', () {
      final l = loadLevel1();
      final a = l.routeAt(10.0);
      final b = l.routeAt(20.0);
      expect(a.z, closeTo(10.0, 1e-9));
      expect(b.x, closeTo(-1.4, 1e-6));
      // Midway between two points the eased x lies strictly between them.
      final mid = l.routeAt(15.0);
      expect(mid.x, lessThan(a.x));
      expect(mid.x, greaterThan(b.x));
    });

    test('routeAt clamps outside the authored range', () {
      final l = loadLevel1();
      expect(l.routeAt(-100).z, l.route.first.z);
      expect(l.routeAt(1000).x, closeTo(l.route.last.x, 1e-9));
    });

    test('cameraZoneAt selects the covering zone', () {
      final l = loadLevel1();
      expect(l.cameraZoneAt(0).endZ, 20.0);
      expect(l.cameraZoneAt(50).distance, 12.6);
      expect(l.cameraZoneAt(9999).endZ, 90.0);
    });

    test('missing required fields throw a clear error', () {
      expect(
        () => LevelData.fromJsonString('{}'),
        throwsA(isA<LevelParseException>()),
      );
      final noPortal = level1Json()..remove('portal');
      expect(
        () => LevelData.fromJson(noPortal),
        throwsA(isA<LevelParseException>()),
      );
    });
  });

  group('LevelValidator', () {
    test('Level 1 is valid against the real asset set', () {
      final result = LevelValidator(
        knownAssets: discoverAssets(),
      ).validate(loadLevel1());
      expect(result.isValid, isTrue, reason: result.toString());
      expect(result.errors, isEmpty, reason: result.toString());
    });

    test('flags a referenced asset that does not exist', () {
      final j = level1Json();
      (j['platforms'] as List)[0]['asset'] =
          'assets/models/platforms/does_not_exist.glb';
      final r = LevelValidator(
        knownAssets: discoverAssets(),
      ).validate(LevelData.fromJson(j));
      expect(r.errors.map((e) => e.code), contains('missing_asset'));
    });

    test('flags an asset outside every known category', () {
      final j = level1Json();
      (j['platforms'] as List)[0]['asset'] = 'assets/audio/beep.wav';
      final r = LevelValidator().validate(LevelData.fromJson(j));
      expect(r.errors.map((e) => e.code), contains('unknown_object_type'));
    });

    test('flags a locked portal with no key', () {
      final j = level1Json()..remove('key');
      final r = LevelValidator().validate(LevelData.fromJson(j));
      expect(
        r.errors.map((e) => e.code),
        contains('missing_key_for_locked_portal'),
      );
    });

    test('flags a portal behind the Core spawn', () {
      final j = level1Json();
      j['portal']['position'] = [0.0, 0.0, -5.0];
      final r = LevelValidator().validate(LevelData.fromJson(j));
      expect(r.errors.map((e) => e.code), contains('missing_finish_portal'));
    });

    test('flags insufficient bridge pieces', () {
      final j = level1Json();
      j['bridge']['pieceCount'] = 3;
      j['bridge']['piecesRequired'] = 6;
      final r = LevelValidator().validate(LevelData.fromJson(j));
      expect(
        r.errors.map((e) => e.code),
        contains('insufficient_bridge_pieces'),
      );
    });

    test('flags a gap with no bridge', () {
      final j = level1Json()..remove('bridge');
      final r = LevelValidator().validate(LevelData.fromJson(j));
      expect(
        r.errors.map((e) => e.code),
        contains('insufficient_bridge_pieces'),
      );
    });

    test('flags too few bridge anchors', () {
      final j = level1Json();
      j['bridge']['anchors'] = [
        [0.0, 0.0, 47.4],
      ];
      final r = LevelValidator().validate(LevelData.fromJson(j));
      expect(
        r.errors.map((e) => e.code),
        contains('insufficient_bridge_anchors'),
      );
    });

    test('flags a non-advancing route', () {
      final j = level1Json();
      j['route'] = [
        [0.0, 0.0, 0.0],
        [0.0, 0.0, -5.0],
        [0.0, 0.0, 80.0],
      ];
      final r = LevelValidator().validate(LevelData.fromJson(j));
      expect(r.errors.map((e) => e.code), contains('invalid_route'));
    });

    test('flags a route that ends before the finish', () {
      final j = level1Json();
      j['route'] = [
        [0.0, 0.0, 0.0],
        [0.0, 0.0, 10.0],
      ];
      final r = LevelValidator().validate(LevelData.fromJson(j));
      expect(r.errors.map((e) => e.code), contains('invalid_route'));
    });

    test('flags a level whose platforms are all decorative', () {
      final j = level1Json();
      for (final p in (j['platforms'] as List)) {
        p['decorative'] = true;
      }
      final r = LevelValidator().validate(LevelData.fromJson(j));
      expect(
        r.errors.map((e) => e.code),
        contains('invalid_platform_reference'),
      );
    });

    test('flags a hazard sitting on the spawn', () {
      final j = level1Json();
      (j['hazards'] as List)[0]['position'] = [0.0, 1.0, 2.0];
      (j['hazards'] as List)[0]['triggerZ'] = 1.0;
      final r = LevelValidator().validate(LevelData.fromJson(j));
      expect(r.errors.map((e) => e.code), contains('hazard_overlaps_spawn'));
    });

    test('flags a hazard whose telegraph is too short to react to', () {
      final j = level1Json();
      (j['hazards'] as List)[0]['telegraphSeconds'] = 0.1;
      final r = LevelValidator().validate(LevelData.fromJson(j));
      expect(
        r.errors.map((e) => e.code),
        contains('hazard_telegraph_too_short'),
      );
    });

    test('flags invalid camera zones', () {
      final j = level1Json();
      (j['cameraZones'] as List)[2]['endZ'] = 1.0;
      final r = LevelValidator().validate(LevelData.fromJson(j));
      expect(r.errors.map((e) => e.code), contains('invalid_camera_zone'));
    });

    test('flags camera zones that stop before the finish', () {
      final j = level1Json();
      (j['cameraZones'] as List).removeLast();
      final r = LevelValidator().validate(LevelData.fromJson(j));
      expect(r.errors.map((e) => e.code), contains('invalid_camera_zone'));
    });

    test('flags a swarm stage the level cannot possibly reach', () {
      final j = level1Json();
      j['swarmStages'] = [12, 28, 5000];
      final r = LevelValidator().validate(LevelData.fromJson(j));
      expect(
        r.errors.map((e) => e.code),
        contains('impossible_swarm_requirement'),
      );
    });

    test('flags swarm stages that do not increase', () {
      final j = level1Json();
      j['swarmStages'] = [30, 12];
      final r = LevelValidator().validate(LevelData.fromJson(j));
      expect(
        r.errors.map((e) => e.code),
        contains('impossible_swarm_requirement'),
      );
    });

    test('flags bars the key cannot fit through', () {
      final j = level1Json();
      j['key']['barGapWidth'] = 0.05;
      final r = LevelValidator().validate(LevelData.fromJson(j));
      expect(r.errors.map((e) => e.code), contains('invalid_bars'));
    });

    test('flags a wall the player cannot have enough metal for', () {
      final j = level1Json();
      j['swarmStages'] = [40, 44, 48];
      // Move every metal group past the wall.
      for (final g in (j['metalGroups'] as List)) {
        final c = (g['centre'] as List).cast<num>();
        g['centre'] = [c[0], c[1], 60.0];
      }
      final r = LevelValidator().validate(LevelData.fromJson(j));
      expect(
        r.errors.map((e) => e.code),
        contains('impossible_swarm_requirement'),
      );
    });
  });
}
