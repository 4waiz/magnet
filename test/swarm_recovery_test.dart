import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:magnet_rush/game/levels/level_data.dart';
import 'package:magnet_rush/game/renderer/mesh_template.dart';
import 'package:magnet_rush/game/swarm/swarm.dart';
import 'package:vector_math/vector_math.dart';

final _tpl = MeshTemplate.box(0.15, 0.15, 0.15, name: 'test');

MetalPiece piece(Vector3 at) => MetalPiece(
  template: _tpl,
  homePosition: at,
  massClass: MassClass.medium,
  kind: PieceKind.scrap,
  scale: 1.0,
  tint: Vector4(1, 1, 1, 1),
);

Swarm loadedSwarm({bool Function(Vector3)? canLand}) {
  final s = Swarm(capacity: 20)..canLandAt = canLand;
  final rng = math.Random(3);
  for (var i = 0; i < 6; i++) {
    final p = piece(Vector3(0, 1, 1.0));
    s.add(p);
    s.capture(p, Vector3.zero(), rng);
  }
  for (var i = 0; i < 120; i++) {
    s.update(
      1 / 60,
      Vector3.zero(),
      charge: 0,
      stageThresholds: const [],
      trailSegments: 0,
    );
  }
  return s;
}

void main() {
  group('Launched metal recovery', () {
    test('metal landing over solid deck becomes collectable again', () {
      // Regression: launched pieces that missed were destroyed permanently.
      // A player who wasted releases at the blocking wall ran out of metal and
      // could not continue, with no failure state to escape through.
      final s = loadedSwarm(canLand: (_) => true);
      s.release(
        corePos: Vector3.zero(),
        forward: Vector3(0, 0, 1),
        charge: 0.6,
        perfect: false,
        rng: math.Random(4),
      );
      expect(s.pieces.every((p) => p.state == PieceState.launched), isTrue);

      for (var i = 0; i < 600; i++) {
        s.update(
          1 / 60,
          Vector3.zero(),
          charge: 0,
          stageThresholds: const [],
          trailSegments: 0,
        );
      }

      final recovered = s.pieces
          .where((p) => p.state == PieceState.idle)
          .length;
      expect(recovered, greaterThan(0));
      for (final p in s.pieces.where((p) => p.state == PieceState.idle)) {
        expect(p.position.y, closeTo(s.landingY, 1e-6));
        // Its new resting place becomes its home, so the settle-back behaviour
        // does not drag it across the level.
        expect(p.homePosition.x, closeTo(p.position.x, 1e-6));
        expect(p.homePosition.z, closeTo(p.position.z, 1e-6));
      }
    });

    test('metal falling over the void is destroyed', () {
      final s = loadedSwarm(canLand: (_) => false);
      s.release(
        corePos: Vector3.zero(),
        forward: Vector3(0, 0, 1),
        charge: 0.6,
        perfect: false,
        rng: math.Random(5),
      );
      for (var i = 0; i < 600; i++) {
        s.update(
          1 / 60,
          Vector3.zero(),
          charge: 0,
          stageThresholds: const [],
          trailSegments: 0,
        );
      }
      expect(s.pieces.every((p) => p.state == PieceState.dead), isTrue);
    });

    test('with no predicate supplied nothing lands', () {
      final s = loadedSwarm();
      s.release(
        corePos: Vector3.zero(),
        forward: Vector3(0, 0, 1),
        charge: 0.6,
        perfect: false,
        rng: math.Random(6),
      );
      for (var i = 0; i < 600; i++) {
        s.update(
          1 / 60,
          Vector3.zero(),
          charge: 0,
          stageThresholds: const [],
          trailSegments: 0,
        );
      }
      expect(s.pieces.every((p) => p.state == PieceState.dead), isTrue);
    });

    test('a piece only lands while descending', () {
      final s = Swarm(capacity: 5)..canLandAt = (_) => true;
      final p = piece(Vector3(0, 5, 0));
      s.add(p);
      p.state = PieceState.launched;
      p.life = 3;
      p.velocity.setValues(0, 8, 4); // rising through the landing height
      p.position.setValues(0, 0.2, 0);
      s.update(
        1 / 60,
        Vector3.zero(),
        charge: 0,
        stageThresholds: const [],
        trailSegments: 0,
      );
      expect(
        p.state,
        PieceState.launched,
        reason: 'a rising piece must not snap to the deck',
      );
    });
  });
}
