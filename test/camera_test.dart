import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magnet_rush/game/camera/game_camera.dart';
import 'package:magnet_rush/game/levels/level_data.dart';
import 'package:vector_math/vector_math.dart';

LevelData level() => LevelData.fromJsonString(
  File('assets/levels/level_01.json').readAsStringSync(),
);

/// Advances the camera for [seconds] with the Core parked at [corePos].
PerspectiveCameraSnapshot run(
  GameCamera cam,
  LevelData l, {
  required Vector3 corePos,
  double seconds = 1.0,
  bool shake = true,
  bool reducedMotion = false,
  double swarmFraction = 0,
}) {
  late var eye = Vector3.zero();
  late var target = Vector3.zero();
  const dt = 1 / 60.0;
  for (var t = 0.0; t < seconds; t += dt) {
    final c = cam.update(
      dt,
      corePos: corePos,
      level: l,
      swarmFraction: swarmFraction,
      aspect: 1080 / 2400,
      shakeEnabled: shake,
      reducedMotion: reducedMotion,
    );
    eye = c.position;
    target = c.target;
  }
  return PerspectiveCameraSnapshot(eye, target);
}

class PerspectiveCameraSnapshot {
  PerspectiveCameraSnapshot(this.eye, this.target);
  final Vector3 eye;
  final Vector3 target;
}

void main() {
  group('GameCamera framing', () {
    test('horizontal FOV is preserved across aspect ratios', () {
      // A 45-degree horizontal FOV must stay 45 degrees horizontally whether
      // the device is 9:16 or 3:4. Authoring vertical FOV directly is what
      // framed a 4 m lane as if it were 2 m across on a phone.
      final portrait = GameCamera.verticalFovFor(45, 1080 / 2400);
      final tallish = GameCamera.verticalFovFor(45, 1080 / 1920);
      expect(portrait, greaterThan(tallish));
      expect(portrait, lessThanOrEqualTo(78.0));
      expect(portrait, greaterThanOrEqualTo(35.0));
    });

    test('vertical FOV is clamped to avoid extreme edge distortion', () {
      expect(GameCamera.verticalFovFor(120, 0.2), 78.0);
      expect(GameCamera.verticalFovFor(2, 3.0), 35.0);
    });

    test('the camera sits behind and above the Core', () {
      final l = level();
      final snap = run(
        GameCamera(),
        l,
        corePos: Vector3(0, 0.95, 10),
        seconds: 3,
        shake: false,
      );
      expect(snap.eye.z, lessThan(10), reason: 'camera must be behind');
      expect(
        snap.eye.y,
        greaterThan(0.95 + 3),
        reason: 'camera must be elevated',
      );
      expect(
        snap.target.z,
        greaterThan(10),
        reason: 'the camera looks ahead of the Core',
      );
    });

    test('repeated shake impulses do not drift the aim', () {
      // Regression: shake was being folded into the smoothed target every
      // frame, so each impulse permanently biased the framing and the level
      // slid off-axis over a run.
      final l = level();
      final cam = GameCamera();
      final core = Vector3(0, 0.95, 10);

      final settled = run(cam, l, corePos: core, seconds: 4, shake: false);

      for (var i = 0; i < 12; i++) {
        cam.impulse(CameraImpulse.wallBreak);
        run(cam, l, corePos: core, seconds: 1.5);
      }
      // Let the shake fully decay, then compare.
      final after = run(cam, l, corePos: core, seconds: 4, shake: false);

      expect((after.target.x - settled.target.x).abs(), lessThan(0.02));
      expect((after.target.z - settled.target.z).abs(), lessThan(0.05));
      expect((after.eye.x - settled.eye.x).abs(), lessThan(0.02));
    });

    test('reduced motion shrinks shake without moving the framing', () {
      final l = level();
      final core = Vector3(0, 0.95, 10);

      final normal = GameCamera();
      run(normal, l, corePos: core, seconds: 3, shake: false);
      normal.impulse(CameraImpulse.perfectRelease);
      final normalShot = run(normal, l, corePos: core, seconds: 0.1);

      final reduced = GameCamera();
      run(
        reduced,
        l,
        corePos: core,
        seconds: 3,
        shake: false,
        reducedMotion: true,
      );
      reduced.impulse(CameraImpulse.perfectRelease);
      final reducedShot = run(
        reduced,
        l,
        corePos: core,
        seconds: 0.1,
        reducedMotion: true,
      );

      // Same subject, less violence.
      expect((reducedShot.target.z - normalShot.target.z).abs(), lessThan(1.0));
      expect(reduced.shakeAmount, closeTo(normal.shakeAmount, 1e-6));
    });

    test('the camera widens as the swarm grows', () {
      final l = level();
      final core = Vector3(0, 0.95, 10);
      final empty = run(
        GameCamera(),
        l,
        corePos: core,
        seconds: 4,
        shake: false,
      );
      final full = run(
        GameCamera(),
        l,
        corePos: core,
        seconds: 4,
        shake: false,
        swarmFraction: 1.0,
      );
      final emptyDist = (empty.eye - core).length;
      final fullDist = (full.eye - core).length;
      expect(fullDist, greaterThan(emptyDist));
    });

    test('camera zones ease rather than cut between sections', () {
      // The eye tracks the Core's Z rigidly — that is the follow. What must
      // not jump is the *rig*: distance behind, height above, and FOV.
      final l = level();
      final cam = GameCamera();
      run(cam, l, corePos: Vector3(0, 0.95, 10), seconds: 4, shake: false);
      final settled = run(
        cam,
        l,
        corePos: Vector3(0, 0.95, 10),
        seconds: 1 / 60,
        shake: false,
      );
      final settledBack = 10 - settled.eye.z;
      final settledUp = settled.eye.y - 0.95;

      // Zone 1 (distance 10.6) to zone 4 (distance 12.6) in a single frame.
      final jumped = run(
        cam,
        l,
        corePos: Vector3(0, 0.95, 50),
        seconds: 1 / 60,
        shake: false,
      );
      final jumpedBack = 50 - jumped.eye.z;
      final jumpedUp = jumped.eye.y - 0.95;

      expect(
        (jumpedBack - settledBack).abs(),
        lessThan(0.5),
        reason: 'distance behind the Core must ease, not cut',
      );
      expect(
        (jumpedUp - settledUp).abs(),
        lessThan(0.5),
        reason: 'height above the Core must ease, not cut',
      );

      // Given time it does reach the new zone's framing.
      final arrived = run(
        cam,
        l,
        corePos: Vector3(0, 0.95, 50),
        seconds: 5,
        shake: false,
      );
      expect(50 - arrived.eye.z, greaterThan(settledBack));
    });

    test('reset returns the rig to a clean state', () {
      final l = level();
      final cam = GameCamera();
      cam.impulse(CameraImpulse.wallBreak);
      run(cam, l, corePos: Vector3(0, 0.95, 40), seconds: 0.5);
      cam.reset();
      expect(cam.shakeAmount, 0);

      final a = run(
        cam,
        l,
        corePos: Vector3(0, 0.95, 10),
        seconds: 3,
        shake: false,
      );
      final fresh = run(
        GameCamera(),
        l,
        corePos: Vector3(0, 0.95, 10),
        seconds: 3,
        shake: false,
      );
      expect((a.eye - fresh.eye).length, lessThan(0.01));
    });
  });
}
