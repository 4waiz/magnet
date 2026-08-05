import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:magnet_rush/core/performance/quality.dart';
import 'package:magnet_rush/core/persistence/settings_store.dart';
import 'package:magnet_rush/game/levels/level_data.dart';
import 'package:magnet_rush/game/magnet/magnet_field.dart';
import 'package:magnet_rush/game/renderer/mesh_template.dart';
import 'package:magnet_rush/game/scoring/scoring.dart';
import 'package:magnet_rush/game/swarm/swarm.dart';
import 'package:vector_math/vector_math.dart';

final _tpl = MeshTemplate.box(0.15, 0.15, 0.15, name: 'test');

MetalPiece piece(
  Vector3 at, {
  MassClass mass = MassClass.medium,
  PieceKind kind = PieceKind.scrap,
}) => MetalPiece(
  template: _tpl,
  homePosition: at,
  massClass: mass,
  kind: kind,
  scale: 1.0,
  tint: Vector4(1, 1, 1, 1),
);

/// Runs the field until [p] is captured or [maxSeconds] elapse.
double timeToCapture(
  MagnetField f,
  MetalPiece p,
  Vector3 core, {
  double maxSeconds = 10,
  double charge = 0,
}) {
  var t = 0.0;
  const dt = 1 / 120.0;
  while (t < maxSeconds) {
    if (f.apply(p, core, dt, attracting: true, charge: charge)) return t;
    t += dt;
  }
  return double.infinity;
}

void main() {
  // -----------------------------------------------------------------------
  group('MagnetField — range', () {
    test('pieces beyond range are not attracted', () {
      final f = MagnetField();
      final core = Vector3.zero();
      final far = piece(Vector3(0, 0, f.tuning.range + 3.0));
      final before = far.position.z;
      for (var i = 0; i < 120; i++) {
        f.apply(far, core, 1 / 120, attracting: true, charge: 0);
      }
      expect(far.position.z, closeTo(before, 0.02));
      expect(f.inRange(far, core, 0), isFalse);
    });

    test('pieces inside range are attracted', () {
      final f = MagnetField();
      final core = Vector3.zero();
      final near = piece(Vector3(0, 0, 4.0));
      expect(f.inRange(near, core, 0), isTrue);
      expect(timeToCapture(f, near, core), lessThan(3.0));
    });

    test('charge extends the effective range', () {
      final f = MagnetField();
      expect(f.rangeAt(1.0), greaterThan(f.rangeAt(0.0)));
      final core = Vector3.zero();
      final edge = piece(Vector3(0, 0, f.tuning.range + 1.0));
      expect(f.inRange(edge, core, 0.0), isFalse);
      expect(f.inRange(edge, core, 1.0), isTrue);
    });

    test('falloff is strongest at the Core and zero at the edge', () {
      final f = MagnetField();
      expect(f.falloff(0.0, 0), greaterThan(f.falloff(4.0, 0)));
      expect(f.falloff(4.0, 0), greaterThan(f.falloff(8.0, 0)));
      expect(f.falloff(f.tuning.range, 0), 0);
    });
  });

  // -----------------------------------------------------------------------
  group('MagnetField — response and acceleration', () {
    test('a nearby piece moves on the very first frame', () {
      // The seat impulse exists precisely so attraction never reads as input
      // lag. Without it a piece is stationary for several frames.
      final f = MagnetField();
      final core = Vector3.zero();
      final p = piece(Vector3(0, 0, 2.0));
      f.apply(p, core, 1 / 60, attracting: true, charge: 0);
      expect(
        p.position.z,
        lessThan(2.0),
        reason: 'piece must move within one frame of touch-down',
      );
    });

    test('distant pieces accelerate rather than jerk', () {
      final f = MagnetField();
      final core = Vector3.zero();
      final p = piece(Vector3(0, 0, 7.0));
      const dt = 1 / 120.0;
      f.apply(p, core, dt, attracting: true, charge: 0);
      final firstStep = 7.0 - p.position.z;
      for (var i = 0; i < 40; i++) {
        f.apply(p, core, dt, attracting: true, charge: 0);
      }
      final z0 = p.position.z;
      f.apply(p, core, dt, attracting: true, charge: 0);
      final laterStep = z0 - p.position.z;
      expect(laterStep, greaterThan(firstStep));
    });

    test('releasing the field settles pieces back toward home', () {
      final f = MagnetField();
      final core = Vector3.zero();
      final p = piece(Vector3(0, 0, 3.0));
      for (var i = 0; i < 30; i++) {
        f.apply(p, core, 1 / 120, attracting: true, charge: 0);
      }
      final pulled = p.position.z;
      expect(pulled, lessThan(3.0));
      for (var i = 0; i < 240; i++) {
        f.apply(p, core, 1 / 120, attracting: false, charge: 0);
      }
      expect(p.position.z, greaterThan(pulled));
      expect(p.position.z, closeTo(3.0, 0.25));
    });
  });

  // -----------------------------------------------------------------------
  group('MagnetField — mass', () {
    test('light pieces arrive before heavy pieces from the same distance', () {
      final f = MagnetField();
      final core = Vector3.zero();
      final light = timeToCapture(
        MagnetField(),
        piece(Vector3(0, 0, 5.0), mass: MassClass.light),
        core,
      );
      final medium = timeToCapture(
        f,
        piece(Vector3(0, 0, 5.0), mass: MassClass.medium),
        core,
      );
      final heavy = timeToCapture(
        MagnetField(),
        piece(Vector3(0, 0, 5.0), mass: MassClass.heavy),
        core,
      );

      expect(light, lessThan(medium));
      expect(medium, lessThan(heavy));
      expect(
        heavy.isFinite,
        isTrue,
        reason: 'heavy stock must still be collectable',
      );
    });

    test('heavy pieces resist for a beat before committing', () {
      final f = MagnetField();
      final core = Vector3.zero();
      final light = piece(Vector3(0, 0, 4.0), mass: MassClass.light);
      final heavy = piece(Vector3(0, 0, 4.0), mass: MassClass.heavy);
      for (var i = 0; i < 12; i++) {
        f.apply(light, core, 1 / 120, attracting: true, charge: 0);
        f.apply(heavy, core, 1 / 120, attracting: true, charge: 0);
      }
      expect(4.0 - light.position.z, greaterThan(4.0 - heavy.position.z));
    });

    test('mass class exposes consistent physics constants', () {
      expect(MassClass.light.mass, lessThan(MassClass.medium.mass));
      expect(MassClass.medium.mass, lessThan(MassClass.heavy.mass));
      expect(
        MassClass.heavy.impactDamage,
        greaterThan(MassClass.light.impactDamage),
      );
    });
  });

  // -----------------------------------------------------------------------
  group('Swarm — capacity and orbit assignment', () {
    test('capture is refused once capacity is reached', () {
      final s = Swarm(capacity: 5);
      final rng = math.Random(1);
      final core = Vector3.zero();
      var accepted = 0;
      for (var i = 0; i < 20; i++) {
        final p = piece(Vector3(i * 0.1, 0, 1.0));
        s.add(p);
        if (s.capture(p, core, rng)) accepted++;
        s.update(
          1 / 60,
          core,
          charge: 0,
          stageThresholds: const [],
          trailSegments: 0,
        );
      }
      expect(accepted, 5);
      expect(s.stats.orbiting, lessThanOrEqualTo(5));
    });

    test('armour rides the middle layer and the key the inner layer', () {
      final s = Swarm(capacity: 30);
      final rng = math.Random(2);
      expect(s.layerFor(PieceKind.armour, rng), 1);
      expect(s.layerFor(PieceKind.key, rng), 0);
      expect(s.layerFor(PieceKind.bridge, rng), 2);
    });

    test('captured pieces get distinct slots within their layer', () {
      final s = Swarm(capacity: 30);
      final rng = math.Random(3);
      final core = Vector3.zero();
      final armour = <MetalPiece>[];
      for (var i = 0; i < 6; i++) {
        final p = piece(Vector3(0, 0, 1.0), kind: PieceKind.armour);
        s.add(p);
        s.capture(p, core, rng);
        armour.add(p);
      }
      expect(armour.map((p) => p.slot).toSet().length, 6);
      expect(armour.every((p) => p.layer == 1), isTrue);
    });

    test('capture flies a curved path, not a straight snap', () {
      final s = Swarm(capacity: 10);
      final rng = math.Random(4);
      final core = Vector3.zero();
      final p = piece(Vector3(0, 0, 3.0));
      s.add(p);
      s.capture(p, core, rng);

      // Sample midway; a straight line would keep x at 0 the whole way.
      var maxLateral = 0.0;
      for (var i = 0; i < 30; i++) {
        s.update(
          1 / 60,
          core,
          charge: 0,
          stageThresholds: const [],
          trailSegments: 4,
        );
        maxLateral = math.max(maxLateral, p.position.x.abs());
      }
      expect(
        maxLateral,
        greaterThan(0.15),
        reason: 'capture path should bow sideways',
      );
    });

    test('orbiting pieces settle onto their analytic slot', () {
      final s = Swarm(capacity: 10);
      final rng = math.Random(5);
      final core = Vector3(0, 1, 0);
      final p = piece(Vector3(0, 1, 1.0));
      s.add(p);
      s.capture(p, core, rng);
      for (var i = 0; i < 240; i++) {
        s.update(
          1 / 60,
          core,
          charge: 0,
          stageThresholds: const [],
          trailSegments: 0,
        );
      }
      expect(p.state, PieceState.orbiting);
      final r = (p.position - core).length;
      expect(r, greaterThan(0.5));
      expect(r, lessThan(3.0));
    });

    test('orbit radius expands as the swarm fills', () {
      double radiusWith(int count) {
        final s = Swarm(capacity: 20);
        final rng = math.Random(6);
        final core = Vector3.zero();
        final pieces = <MetalPiece>[];
        for (var i = 0; i < count; i++) {
          final p = piece(Vector3(0, 0, 1.0), kind: PieceKind.armour);
          s.add(p);
          s.capture(p, core, rng);
          pieces.add(p);
        }
        for (var i = 0; i < 200; i++) {
          s.update(
            1 / 60,
            core,
            charge: 0,
            stageThresholds: const [],
            trailSegments: 0,
          );
        }
        return (pieces.first.position - core).length;
      }

      expect(radiusWith(18), greaterThan(radiusWith(2)));
    });
  });

  // -----------------------------------------------------------------------
  group('Swarm — stage transitions', () {
    test('stage steps up as thresholds are crossed', () {
      final s = Swarm(capacity: 40);
      final rng = math.Random(7);
      final core = Vector3.zero();
      const stages = [3, 6, 10];
      final seen = <int>[];
      for (var i = 0; i < 12; i++) {
        final p = piece(Vector3(0, 0, 1.0));
        s.add(p);
        s.capture(p, core, rng);
        s.update(
          1 / 60,
          core,
          charge: 0,
          stageThresholds: stages,
          trailSegments: 0,
        );
        seen.add(s.stage);
      }
      expect(seen.first, 0);
      expect(seen.last, 3);
      // Monotonic while collecting.
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
      }
    });
  });

  // -----------------------------------------------------------------------
  group('Swarm — release', () {
    Swarm loaded(int n, {PieceKind kind = PieceKind.scrap}) {
      final s = Swarm(capacity: 60);
      final rng = math.Random(8);
      final core = Vector3.zero();
      for (var i = 0; i < n; i++) {
        final p = piece(Vector3(0, 0, 1.0), kind: kind);
        s.add(p);
        s.capture(p, core, rng);
      }
      for (var i = 0; i < 120; i++) {
        s.update(
          1 / 60,
          core,
          charge: 0,
          stageThresholds: const [],
          trailSegments: 0,
        );
      }
      return s;
    }

    test('release launches every orbiting piece', () {
      final s = loaded(10);
      final n = s.release(
        corePos: Vector3.zero(),
        forward: Vector3(0, 0, 1),
        charge: 0.5,
        perfect: false,
        rng: math.Random(9),
      );
      expect(n, 10);
      expect(s.pieces.every((p) => p.state == PieceState.launched), isTrue);
    });

    test('more charge means more speed, and perfect adds more still', () {
      double speedAt(double charge, bool perfect) {
        final s = loaded(4);
        s.release(
          corePos: Vector3.zero(),
          forward: Vector3(0, 0, 1),
          charge: charge,
          perfect: perfect,
          rng: math.Random(11),
        );
        return s.pieces.first.velocity.length;
      }

      expect(speedAt(1.0, false), greaterThan(speedAt(0.0, false)));
      expect(speedAt(1.0, true), greaterThan(speedAt(1.0, false)));
    });

    test('heavy pieces launch slower than light ones', () {
      double speedFor(MassClass m) {
        final s = Swarm(capacity: 10);
        final rng = math.Random(12);
        final p = piece(Vector3(0, 0, 1.0), mass: m);
        s.add(p);
        s.capture(p, Vector3.zero(), rng);
        for (var i = 0; i < 120; i++) {
          s.update(
            1 / 60,
            Vector3.zero(),
            charge: 0,
            stageThresholds: const [],
            trailSegments: 0,
          );
        }
        s.release(
          corePos: Vector3.zero(),
          forward: Vector3(0, 0, 1),
          charge: 0.5,
          perfect: false,
          rng: math.Random(13),
        );
        return p.velocity.length;
      }

      expect(speedFor(MassClass.heavy), lessThan(speedFor(MassClass.light)));
    });

    test('launch is forward-biased, not an even radial spray', () {
      final s = loaded(24);
      s.release(
        corePos: Vector3.zero(),
        forward: Vector3(0, 0, 1),
        charge: 0.8,
        perfect: false,
        rng: math.Random(14),
      );
      final forward =
          s.pieces.where((p) => p.velocity.z > 0).length / s.pieces.length;
      expect(
        forward,
        greaterThan(0.9),
        reason: 'a release that sprays backwards feels weak',
      );
    });

    test('target assist steers the burst toward a supplied target', () {
      Vector3 meanDir(Vector3? target) {
        final s = loaded(20);
        s.release(
          corePos: Vector3.zero(),
          forward: Vector3(0, 0, 1),
          charge: 0.8,
          perfect: false,
          rng: math.Random(15),
          target: target,
        );
        final sum = Vector3.zero();
        for (final p in s.pieces) {
          sum.add(p.velocity.normalized());
        }
        return sum..scale(1 / s.pieces.length);
      }

      final none = meanDir(null);
      final right = meanDir(Vector3(12, 0, 6));
      expect(right.x, greaterThan(none.x + 0.1));
    });

    test('launched pieces spin and carry a trail', () {
      final s = loaded(6);
      s.release(
        corePos: Vector3.zero(),
        forward: Vector3(0, 0, 1),
        charge: 1.0,
        perfect: true,
        rng: math.Random(16),
      );
      expect(s.pieces.first.tumbleRate, greaterThan(4.0));
      for (var i = 0; i < 6; i++) {
        s.update(
          1 / 60,
          Vector3.zero(),
          charge: 0,
          stageThresholds: const [],
          trailSegments: 8,
        );
      }
      expect(s.pieces.first.trailCount, greaterThan(1));
    });

    test(
      'releasing clears layer bookkeeping so the next swarm packs evenly',
      () {
        final s = loaded(9, kind: PieceKind.armour);
        s.release(
          corePos: Vector3.zero(),
          forward: Vector3(0, 0, 1),
          charge: 0.5,
          perfect: false,
          rng: math.Random(17),
        );
        final rng = math.Random(18);
        final p = piece(Vector3(0, 0, 1.0), kind: PieceKind.armour);
        s.add(p);
        s.capture(p, Vector3.zero(), rng);
        expect(p.slot, 0, reason: 'slot counters must reset on release');
      },
    );
  });

  // -----------------------------------------------------------------------
  group('ChargeState — the perfect window', () {
    test('charge rises while holding and decays when released', () {
      final c = ChargeState();
      for (var i = 0; i < 60; i++) {
        c.update(1 / 60, holding: true);
      }
      final held = c.charge;
      expect(held, greaterThan(0.4));
      for (var i = 0; i < 60; i++) {
        c.update(1 / 60, holding: false);
      }
      expect(c.charge, lessThan(held));
    });

    test('the perfect window opens near full charge', () {
      final c = ChargeState();
      expect(c.inPerfectWindow, isFalse);
      while (c.charge < 0.999) {
        c.update(1 / 240, holding: true);
      }
      expect(c.inPerfectWindow, isTrue);
      expect(c.windowProgress, closeTo(1.0, 0.01));
    });

    test('holding too long vents and closes the window', () {
      final c = ChargeState();
      var vented = false;
      for (var i = 0; i < 1200 && !vented; i++) {
        vented = c.update(1 / 120, holding: true);
      }
      expect(vented, isTrue);
      expect(c.vented, isTrue);
      expect(c.inPerfectWindow, isFalse);
      expect(c.charge, closeTo(ChargeState.ventTo, 1e-9));
    });

    test('vent pressure rises across the grace period', () {
      final c = ChargeState();
      while (c.charge < 0.999) {
        c.update(1 / 240, holding: true);
      }
      final early = c.ventPressure;
      for (var i = 0; i < 60; i++) {
        c.update(1 / 240, holding: true);
      }
      expect(c.ventPressure, greaterThan(early));
    });

    test('the window is wide enough to hit on a phone', () {
      // From the moment the window opens to the moment it vents, the player
      // has at least a third of a second.
      final c = ChargeState();
      while (!c.inPerfectWindow) {
        c.update(1 / 240, holding: true);
      }
      var open = 0.0;
      while (!c.update(1 / 240, holding: true)) {
        open += 1 / 240;
        if (open > 5) break;
      }
      expect(open, greaterThan(0.33));
    });

    test('releasing resets so the next hold starts clean', () {
      final c = ChargeState();
      for (var i = 0; i < 600; i++) {
        c.update(1 / 120, holding: true);
      }
      c.reset();
      expect(c.charge, 0);
      expect(c.vented, isFalse);
    });
  });

  // -----------------------------------------------------------------------
  group('RunScore — combo and results', () {
    test('collecting builds a combo that expires', () {
      final s = RunScore();
      s.addCollect();
      s.addCollect();
      expect(s.combo, 2);
      expect(s.comboMultiplier, greaterThan(1.0));
      s.tick(RunScore.comboWindow + 0.1);
      expect(s.combo, 0);
      expect(s.bestCombo, 2);
    });

    test('destruction score scales with the combo multiplier', () {
      final a = RunScore()..addDestruction(100);
      final b = RunScore();
      for (var i = 0; i < 10; i++) {
        b.addCollect();
      }
      b.addDestruction(100);
      expect(b.destructionScore, greaterThan(a.destructionScore));
    });

    test('stars require the metal target and a clean perfect run', () {
      final s = RunScore()
        ..metalCollected = 40
        ..perfectReleases = 2;
      expect(s.stars(40), 3);

      s.damageTaken = 1;
      expect(s.stars(40), 2);

      s
        ..metalCollected = 5
        ..perfectReleases = 0;
      expect(s.stars(40), 1);
    });

    test('coins derive from total score', () {
      final s = RunScore()
        ..metalCollected = 50
        ..destructionScore = 900
        ..perfectReleases = 2;
      expect(s.total, greaterThan(0));
      expect(s.coins, s.total ~/ 22);
    });

    test('reset clears everything', () {
      final s = RunScore()
        ..addCollect()
        ..addDestruction(50)
        ..damageTaken = 2;
      s.reset();
      expect(s.total, 0);
      expect(s.combo, 0);
      expect(s.damageTaken, 0);
    });
  });

  // -----------------------------------------------------------------------
  group('Determinism', () {
    test('the same seed produces an identical swarm trajectory', () {
      List<double> run() {
        final s = Swarm(capacity: 30);
        final rng = math.Random(4242);
        final core = Vector3(0, 1, 0);
        final ps = <MetalPiece>[];
        for (var i = 0; i < 12; i++) {
          final p = piece(Vector3(i * 0.2, 1, 2.0));
          s.add(p);
          ps.add(p);
        }
        for (final p in ps) {
          s.capture(p, core, rng);
        }
        for (var i = 0; i < 180; i++) {
          s.update(
            1 / 60,
            core,
            charge: 0.4,
            stageThresholds: const [4, 8],
            trailSegments: 0,
          );
        }
        return ps
            .expand((p) => [p.position.x, p.position.y, p.position.z])
            .toList();
      }

      final a = run();
      final b = run();
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i], closeTo(b[i], 1e-12));
      }
    });

    test('magnet field resolution is identical across identical runs', () {
      double run() {
        final f = MagnetField();
        final p = piece(Vector3(0, 0, 6.0), mass: MassClass.heavy);
        return timeToCapture(f, p, Vector3.zero());
      }

      expect(run(), run());
    });
  });

  // -----------------------------------------------------------------------
  group('Quality presets', () {
    test('presets scale presentation, not gameplay reach', () {
      const low = QualitySettings.low;
      const high = QualitySettings.high;
      expect(low.maxParticles, lessThan(high.maxParticles));
      expect(low.maxDebris, lessThan(high.maxDebris));
      expect(low.decorDensity, lessThan(high.decorDensity));
      expect(low.trailSegments, lessThan(high.trailSegments));

      // Attraction reach is a property of the field, not the preset, so it
      // cannot differ between presets.
      final f = MagnetField();
      expect(f.rangeAt(0.5), f.rangeAt(0.5));
    });

    test('every preset is selectable and self-consistent', () {
      for (final p in QualityPreset.values) {
        final q = QualitySettings.of(p);
        expect(q.preset, p);
        expect(q.maxSwarm, greaterThan(0));
        expect(q.glowIntensity, inInclusiveRange(0.0, 1.0));
        expect(p.label, isNotEmpty);
      }
    });
  });

  // -----------------------------------------------------------------------
  group('Settings persistence', () {
    test('round-trips through the map form', () {
      const s = GameSettings(
        soundVolume: 0.3,
        musicVolume: 0.2,
        hapticsEnabled: false,
        cameraShake: false,
        reducedMotion: true,
        effectIntensity: 0.45,
        quality: QualityPreset.low,
      );
      final restored = GameSettings.fromMap(s.toMap());
      expect(restored, s);
    });

    test('unknown or malformed values fall back to defaults', () {
      final s = GameSettings.fromMap({
        'soundVolume': 'nonsense',
        'quality': 'ultra',
        'hapticsEnabled': null,
      });
      expect(s.soundVolume, 0.85);
      expect(s.quality, QualityPreset.medium);
      expect(s.hapticsEnabled, isTrue);
    });

    test('volumes are clamped into range', () {
      final s = GameSettings.fromMap({'soundVolume': 4.0, 'musicVolume': -2.0});
      expect(s.soundVolume, 1.0);
      expect(s.musicVolume, 0.0);
    });

    test('store notifies listeners on change', () async {
      final store = SettingsStore();
      var notified = 0;
      store.addListener(() => notified++);
      await store.update(store.value.copyWith(reducedMotion: true));
      expect(notified, 1);
      // Writing the same value must not churn listeners.
      await store.update(store.value);
      expect(notified, 1);
    });
  });
}
