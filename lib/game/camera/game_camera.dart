/// The gameplay camera: an elevated three-quarter portrait follow rig.
///
/// Everything is damped. The camera never jumps to a new target — it eases
/// toward one, so a zone change or a swarm milestone reads as a move rather
/// than a cut. Impulses are additive and decay, so several can overlap without
/// fighting each other.
///
/// Reduced motion scales shake, FOV swing and impulse magnitude toward zero
/// but leaves framing, distance and gameplay untouched.
library;

import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import '../levels/level_data.dart';

enum CameraImpulse {
  collectMilestone,
  wallBreak,
  perfectRelease,
  release,
  damage,
}

class GameCamera {
  GameCamera();

  // Smoothed rig state.
  double _distance = 10.6;
  double _height = 6.2;
  double _fov = 45;
  double _lookAhead = 2.6;
  double _lateral = 0.45;

  final Vector3 _target = Vector3.zero();
  final Vector3 _eye = Vector3.zero();
  bool _seeded = false;

  // Impulses
  double _shake = 0;
  double _kick = 0;
  double _fovPunch = 0;
  double _zoomOut = 0;
  double _forwardEmphasis = 0;
  double _completionOrbit = 0;

  double _t = 0;
  final math.Random _rng = math.Random(4242);

  double get shakeAmount => _shake;

  void reset() {
    _seeded = false;
    _shake = 0;
    _kick = 0;
    _fovPunch = 0;
    _zoomOut = 0;
    _forwardEmphasis = 0;
    _completionOrbit = 0;
    _t = 0;
  }

  void impulse(CameraImpulse kind) {
    switch (kind) {
      case CameraImpulse.collectMilestone:
        _shake = math.max(_shake, 0.22);
        _kick = math.max(_kick, 0.20);
      case CameraImpulse.release:
        _shake = math.max(_shake, 0.45);
        _kick = math.max(_kick, 0.55);
        _fovPunch = math.max(_fovPunch, 0.55);
      case CameraImpulse.wallBreak:
        _shake = math.max(_shake, 0.72);
        _kick = math.max(_kick, 0.70);
        _zoomOut = math.max(_zoomOut, 1.0);
      case CameraImpulse.perfectRelease:
        _shake = math.max(_shake, 0.95);
        _kick = math.max(_kick, 0.95);
        _fovPunch = math.max(_fovPunch, 1.0);
        _zoomOut = math.max(_zoomOut, 0.7);
      case CameraImpulse.damage:
        _shake = math.max(_shake, 0.85);
        _kick = math.max(_kick, 0.40);
    }
  }

  /// A small forward push while attracting, so holding feels like leaning in.
  void setAttracting(bool attracting, double dt) {
    final target = attracting ? 1.0 : 0.0;
    _forwardEmphasis += (target - _forwardEmphasis) * math.min(1.0, dt * 3.0);
  }

  void startCompletionOrbit() => _completionOrbit = 0.0001;

  /// Converts an authored *horizontal* field of view into the vertical one
  /// the renderer wants.
  ///
  /// `PerspectiveCamera` derives horizontal FOV as `tan(fovY/2) * aspect`. On a
  /// 1080x2400 phone the aspect is 0.45, so a 45-degree vertical FOV yields
  /// barely 21 degrees horizontally — a 4 m lane then fills the entire screen
  /// width and the level reads as a corridor two metres across. Authoring the
  /// horizontal angle and solving for the vertical one keeps framing stable
  /// across aspect ratios.
  ///
  /// The vertical result is clamped: past roughly 78 degrees the perspective
  /// distortion at the frame edges becomes obvious.
  static double verticalFovFor(double horizontalDegrees, double aspect) {
    final a = aspect <= 0.01 ? 0.45 : aspect;
    final tanH = math.tan(horizontalDegrees * degrees2Radians * 0.5);
    final vertical = 2 * math.atan(tanH / a) * radians2Degrees;
    return vertical.clamp(35.0, 78.0);
  }

  PerspectiveCamera update(
    double dt, {
    required Vector3 corePos,
    required LevelData level,
    required double swarmFraction,
    required double aspect,
    required bool shakeEnabled,
    required bool reducedMotion,
  }) {
    _t += dt;

    final motion = reducedMotion ? 0.25 : 1.0;
    _shake = math.max(0, _shake - dt * 2.6);
    _kick = math.max(0, _kick - dt * 3.4);
    _fovPunch = math.max(0, _fovPunch - dt * 2.2);
    _zoomOut = math.max(0, _zoomOut - dt * 1.35);
    if (_completionOrbit > 0) _completionOrbit += dt;

    // --- zone targets ---------------------------------------------------
    final zone = level.cameraZoneAt(corePos.z);
    // Widen as the swarm grows so a full swarm never fills the frame.
    final wide = swarmFraction.clamp(0.0, 1.0);
    final targetDistance = zone.distance + wide * 2.6 + _zoomOut * 2.4 * motion;
    final targetHeight = zone.height + wide * 1.1;
    final targetFov =
        zone.fovDegrees +
        wide * 3.5 +
        _fovPunch * 5.0 * motion -
        _forwardEmphasis * 1.2 * motion;

    // Damped approach. Zone changes therefore ease rather than cut.
    final k = math.min(1.0, dt * 2.4);
    _distance += (targetDistance - _distance) * k;
    _height += (targetHeight - _height) * k;
    _fov += (targetFov - _fov) * math.min(1.0, dt * 3.2);
    _lookAhead += (zone.lookAhead - _lookAhead) * k;
    _lateral += (zone.lateral - _lateral) * k;

    // --- target point ---------------------------------------------------
    // Framed low-middle: the Core sits below centre so the route ahead and
    // any upcoming hazard are visible.
    final desiredTarget = Vector3(
      corePos.x * _lateral,
      corePos.y + 0.85,
      corePos.z + _lookAhead + _forwardEmphasis * 0.6 * motion,
    );
    if (!_seeded) {
      _target.setFrom(desiredTarget);
      _seeded = true;
    } else {
      _target.addScaled(desiredTarget - _target, math.min(1.0, dt * 5.0));
    }

    // --- eye ------------------------------------------------------------
    var orbitX = 0.0;
    var orbitZ = 0.0;
    if (_completionOrbit > 0) {
      // Slow cinematic push-in and arc once the level is won.
      final a = math.min(_completionOrbit * 0.55, math.pi * 0.42);
      orbitX = math.sin(a) * 5.0;
      orbitZ = (1 - math.cos(a)) * 2.2;
    }

    final eyeX = corePos.x * _lateral * 0.85 + orbitX;
    final eyeY = corePos.y + _height - _kick * 0.35 * motion;
    final eyeZ = corePos.z - _distance + orbitZ + _kick * 0.9 * motion;
    _eye.setValues(eyeX, eyeY, eyeZ);

    // Shake is applied to the *outgoing* camera only, never folded back into
    // `_eye`/`_target`. Those are smoothed persistent state: adding an offset
    // to them each frame accumulates, so every impulse permanently biased the
    // aim and the framing drifted further off-axis with every wall break.
    var shakeEyeX = 0.0;
    var shakeEyeY = 0.0;
    var shakeTargetX = 0.0;
    if (shakeEnabled && _shake > 0.001) {
      final amp = _shake * _shake * 0.42 * motion;
      // Two frequencies so it reads as an impact, not a vibration.
      shakeEyeX = (math.sin(_t * 61.0) * 0.6 + _rng.nextDouble() - 0.5) * amp;
      shakeEyeY = (math.sin(_t * 47.0) * 0.6 + _rng.nextDouble() - 0.5) * amp;
      shakeTargetX = math.sin(_t * 53.0) * amp * 0.35;
    }

    // `_fov` is tracked in authored (horizontal) degrees; the renderer wants
    // vertical, and derives the aspect from the render target itself.
    return PerspectiveCamera(
      fovRadiansY: verticalFovFor(_fov, aspect) * degrees2Radians,
      position: Vector3(_eye.x + shakeEyeX, _eye.y + shakeEyeY, _eye.z),
      target: Vector3(_target.x + shakeTargetX, _target.y, _target.z),
      fovNear: 0.25,
      fovFar: 260.0,
    );
  }
}
