/// The Magnet Rush sound bank.
///
/// Every cue is synthesized at boot by [Synth] and played from memory through
/// a small pool of players. Two things matter more than fidelity here:
///
///  * **No spam.** Collecting a hundred pieces in two seconds must not fire a
///    hundred one-shots. Collection is grouped into a rate-limited voice whose
///    pitch rises with the swarm, so a fast pickup run reads as one rising
///    arpeggio rather than a machine-gun.
///  * **Never throw into the frame loop.** Audio is best-effort. A missing
///    platform channel disables the service instead of breaking gameplay.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'synth.dart';

enum Sfx {
  uiTap,
  uiConfirm,
  attractStart,
  collectLow,
  collectMid,
  collectHigh,
  collectTop,
  swarmStage,
  maxCharge,
  repulse,
  perfectRelease,
  metalImpact,
  wallDestroy,
  armourHit,
  armourBreak,
  bridgeAssemble,
  bridgeLock,
  keyCollect,
  portalUnlock,
  levelComplete,
  failure,
}

class AudioService {
  AudioService();

  final Map<Sfx, Uint8List> _bank = {};
  final List<AudioPlayer> _pool = [];
  AudioPlayer? _ambience;
  AudioPlayer? _attractLoop;
  int _next = 0;
  bool _ready = false;
  bool _disabled = false;

  double sfxVolume = 0.85;
  double musicVolume = 0.55;

  static const int _poolSize = 6;

  bool get ready => _ready && !_disabled;

  // ---------------------------------------------------------------------
  // Boot
  // ---------------------------------------------------------------------

  /// Synthesizes the bank off the UI thread, then warms the player pool.
  Future<void> load() async {
    try {
      final bank = await compute(_buildBank, 0);
      _bank.addAll(bank);
      for (var i = 0; i < _poolSize; i++) {
        final p = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
        _pool.add(p);
      }
      _ambience = AudioPlayer()..setReleaseMode(ReleaseMode.loop);
      _attractLoop = AudioPlayer()..setReleaseMode(ReleaseMode.loop);
      _ready = true;
    } catch (e) {
      debugPrint('AudioService disabled: $e');
      _disabled = true;
    }
  }

  Future<void> dispose() async {
    for (final p in _pool) {
      await p.dispose();
    }
    await _ambience?.dispose();
    await _attractLoop?.dispose();
    _pool.clear();
    _ready = false;
  }

  // ---------------------------------------------------------------------
  // Playback
  // ---------------------------------------------------------------------

  void play(Sfx sfx, {double volume = 1.0, double rate = 1.0}) {
    if (!ready) return;
    final bytes = _bank[sfx];
    if (bytes == null) return;
    final p = _pool[_next];
    _next = (_next + 1) % _pool.length;
    unawaited(() async {
      try {
        await p.stop();
        await p.setVolume((volume * sfxVolume).clamp(0.0, 1.0));
        if (rate != 1.0) await p.setPlaybackRate(rate);
        await p.play(BytesSource(bytes));
      } catch (_) {
        // A busy or torn-down player must never break the frame loop.
      }
    }());
  }

  Future<void> startAmbience() async {
    if (!ready || musicVolume <= 0.001) return;
    final bytes = _bank[Sfx.attractStart];
    if (bytes == null) return;
    try {
      await _ambience!.setVolume(musicVolume * 0.35);
      await _ambience!.play(BytesSource(_bank[_ambienceKey] ?? bytes));
    } catch (_) {}
  }

  Future<void> stopAmbience() async {
    try {
      await _ambience?.stop();
    } catch (_) {}
  }

  static const Sfx _ambienceKey = Sfx.attractStart;

  // ---------------------------------------------------------------------
  // Grouped collection voice
  // ---------------------------------------------------------------------

  double _collectCooldown = 0;
  int _pendingCollects = 0;

  /// Records a pickup. Call freely — the service decides when to make noise.
  void noteCollect() => _pendingCollects++;

  /// Drains queued pickups into at most one voice per ~70 ms, stepping up the
  /// pitch tier with swarm progress so a run of collections rises.
  void tickCollect(double dt, double swarmFraction) {
    if (!ready) return;
    _collectCooldown -= dt;
    if (_pendingCollects <= 0 || _collectCooldown > 0) return;
    _collectCooldown = 0.07;

    final grouped = _pendingCollects;
    _pendingCollects = 0;

    final tier = (swarmFraction.clamp(0.0, 1.0) * 3.99).floor();
    final sfx = switch (tier) {
      0 => Sfx.collectLow,
      1 => Sfx.collectMid,
      2 => Sfx.collectHigh,
      _ => Sfx.collectTop,
    };
    // More pieces in the group -> slightly louder, never louder than a hit.
    final vol = (0.34 + math.min(grouped, 6) * 0.055).clamp(0.0, 0.66);
    play(sfx, volume: vol);
  }

  void resetCollect() {
    _pendingCollects = 0;
    _collectCooldown = 0;
  }

  // ---------------------------------------------------------------------
  // Sustained attraction
  // ---------------------------------------------------------------------

  bool _attracting = false;

  Future<void> setAttracting(bool on, double charge) async {
    if (!ready) return;
    if (on == _attracting) {
      if (on) {
        try {
          await _attractLoop!.setVolume(
            ((0.10 + charge * 0.30) * sfxVolume).clamp(0.0, 1.0),
          );
          await _attractLoop!.setPlaybackRate(0.85 + charge * 0.55);
        } catch (_) {}
      }
      return;
    }
    _attracting = on;
    try {
      if (on) {
        final bytes = _bank[Sfx.attractStart];
        if (bytes == null) return;
        await _attractLoop!.setVolume((0.12 * sfxVolume).clamp(0.0, 1.0));
        await _attractLoop!.play(BytesSource(bytes));
      } else {
        await _attractLoop!.stop();
      }
    } catch (_) {}
  }
}

// -------------------------------------------------------------------------
// Bank construction (runs in an isolate)
// -------------------------------------------------------------------------

Map<Sfx, Uint8List> _buildBank(int _) {
  final s = Synth(20260805);
  final out = <Sfx, Uint8List>{};

  Uint8List make(
    double seconds,
    void Function(Buf b) build, {
    double peak = 0.8,
  }) {
    final b = Buf.seconds(seconds);
    build(b);
    return b.finish(peak: peak).toWav();
  }

  // --- UI ---------------------------------------------------------------
  out[Sfx.uiTap] = make(0.09, (b) {
    s.tone(
      b,
      freq: 1180,
      toFreq: 1560,
      dur: 0.07,
      wave: Wave.triangle,
      gain: 0.5,
      decay: 9,
    );
  }, peak: 0.5);

  out[Sfx.uiConfirm] = make(0.26, (b) {
    s.tone(b, freq: 620, dur: 0.10, wave: Wave.triangle, gain: 0.5, decay: 7);
    s.tone(
      b,
      freq: 930,
      start: 0.07,
      dur: 0.16,
      wave: Wave.sine,
      gain: 0.5,
      decay: 6,
    );
  }, peak: 0.6);

  // --- Attraction: a rising electromagnetic hum -------------------------
  out[Sfx.attractStart] = make(0.50, (b) {
    s.tone(
      b,
      freq: 88,
      toFreq: 132,
      dur: 0.50,
      wave: Wave.saw,
      gain: 0.30,
      decay: 0.5,
      attack: 0.05,
      vibrato: 0.02,
      vibratoHz: 7,
    );
    s.tone(
      b,
      freq: 176,
      toFreq: 264,
      dur: 0.50,
      wave: Wave.sine,
      gain: 0.16,
      decay: 0.6,
      attack: 0.08,
    );
    s.noiseBurst(b, dur: 0.50, gain: 0.05, decay: 0.4, lowpass: 0.08);
  }, peak: 0.55);

  // --- Collection tiers -------------------------------------------------
  const collectTiers = [
    (Sfx.collectLow, 540.0),
    (Sfx.collectMid, 680.0),
    (Sfx.collectHigh, 850.0),
    (Sfx.collectTop, 1060.0),
  ];
  for (final (sfx, f) in collectTiers) {
    out[sfx] = make(0.16, (b) {
      s.metallic(
        b,
        freq: f,
        dur: 0.13,
        gain: 0.55,
        decay: 12,
        partials: 3,
        spread: 0.55,
      );
      s.tone(
        b,
        freq: f * 1.5,
        toFreq: f * 2.1,
        dur: 0.07,
        wave: Wave.sine,
        gain: 0.22,
        decay: 11,
      );
    }, peak: 0.6);
  }

  // --- Progression ------------------------------------------------------
  out[Sfx.swarmStage] = make(0.44, (b) {
    for (var i = 0; i < 3; i++) {
      s.tone(
        b,
        freq: 440 * math.pow(1.26, i).toDouble(),
        start: i * 0.055,
        dur: 0.30,
        wave: Wave.triangle,
        gain: 0.34,
        decay: 5,
      );
    }
    s.noiseBurst(
      b,
      dur: 0.20,
      gain: 0.10,
      decay: 8,
      lowpass: 0.30,
      bandCentre: 0.12,
    );
  }, peak: 0.72);

  out[Sfx.maxCharge] = make(0.70, (b) {
    s.tone(
      b,
      freq: 150,
      toFreq: 300,
      dur: 0.70,
      wave: Wave.saw,
      gain: 0.26,
      decay: 0.8,
      vibrato: 0.05,
      vibratoHz: 11,
    );
    s.tone(
      b,
      freq: 900,
      toFreq: 1500,
      dur: 0.55,
      wave: Wave.sine,
      gain: 0.18,
      decay: 2.2,
      vibrato: 0.03,
      vibratoHz: 14,
    );
  }, peak: 0.7);

  // --- Release ----------------------------------------------------------
  out[Sfx.repulse] = make(0.85, (b) {
    // Compression, then the blast.
    s.tone(
      b,
      freq: 300,
      toFreq: 90,
      dur: 0.10,
      wave: Wave.saw,
      gain: 0.35,
      decay: 2,
    );
    s.noiseBurst(
      b,
      start: 0.09,
      dur: 0.42,
      gain: 0.95,
      decay: 5.5,
      lowpass: 0.55,
      bandCentre: 0.05,
    );
    s.tone(
      b,
      freq: 210,
      toFreq: 44,
      start: 0.09,
      dur: 0.60,
      wave: Wave.sine,
      gain: 0.75,
      decay: 3.6,
      attack: 0.001,
    );
    s.metallic(b, freq: 320, start: 0.10, dur: 0.40, gain: 0.35, decay: 7);
  }, peak: 0.95);

  out[Sfx.perfectRelease] = make(1.05, (b) {
    s.tone(
      b,
      freq: 380,
      toFreq: 108,
      dur: 0.12,
      wave: Wave.square,
      gain: 0.30,
      decay: 2,
    );
    s.noiseBurst(
      b,
      start: 0.10,
      dur: 0.50,
      gain: 1.0,
      decay: 4.6,
      lowpass: 0.70,
      bandCentre: 0.04,
    );
    s.tone(
      b,
      freq: 240,
      toFreq: 40,
      start: 0.10,
      dur: 0.72,
      wave: Wave.sine,
      gain: 0.85,
      decay: 3.0,
    );
    // The bright signature that separates a perfect release from a normal one.
    s.tone(
      b,
      freq: 1560,
      toFreq: 2400,
      start: 0.10,
      dur: 0.30,
      wave: Wave.sine,
      gain: 0.40,
      decay: 5,
    );
    s.tone(
      b,
      freq: 2340,
      start: 0.13,
      dur: 0.34,
      wave: Wave.triangle,
      gain: 0.24,
      decay: 6,
    );
  }, peak: 1.0);

  // --- Impacts ----------------------------------------------------------
  out[Sfx.metalImpact] = make(0.20, (b) {
    s.metallic(b, freq: 300, dur: 0.16, gain: 0.60, decay: 14, partials: 4);
    s.noiseBurst(b, dur: 0.09, gain: 0.35, decay: 16, lowpass: 0.6);
  }, peak: 0.7);

  out[Sfx.wallDestroy] = make(0.95, (b) {
    s.noiseBurst(b, dur: 0.55, gain: 1.0, decay: 4.2, lowpass: 0.42);
    s.tone(
      b,
      freq: 130,
      toFreq: 38,
      dur: 0.65,
      wave: Wave.sine,
      gain: 0.80,
      decay: 3.2,
    );
    for (var i = 0; i < 7; i++) {
      s.metallic(
        b,
        freq: 220 + i * 95.0,
        start: 0.04 + i * 0.055,
        dur: 0.24,
        gain: 0.24,
        decay: 12,
        partials: 3,
      );
    }
  }, peak: 1.0);

  out[Sfx.armourHit] = make(0.34, (b) {
    s.metallic(b, freq: 190, dur: 0.28, gain: 0.72, decay: 9, partials: 5);
    s.noiseBurst(b, dur: 0.14, gain: 0.42, decay: 11, lowpass: 0.30);
  }, peak: 0.85);

  out[Sfx.armourBreak] = make(0.62, (b) {
    s.noiseBurst(b, dur: 0.34, gain: 0.75, decay: 6, lowpass: 0.5);
    for (var i = 0; i < 4; i++) {
      s.metallic(
        b,
        freq: 340 + i * 130.0,
        start: i * 0.05,
        dur: 0.26,
        gain: 0.34,
        decay: 11,
        partials: 3,
      );
    }
    s.tone(
      b,
      freq: 160,
      toFreq: 70,
      dur: 0.35,
      wave: Wave.sine,
      gain: 0.4,
      decay: 5,
    );
  }, peak: 0.9);

  // --- Objectives -------------------------------------------------------
  out[Sfx.bridgeAssemble] = make(0.55, (b) {
    for (var i = 0; i < 5; i++) {
      s.metallic(
        b,
        freq: 420 + i * 70.0,
        start: i * 0.07,
        dur: 0.18,
        gain: 0.35,
        decay: 12,
        partials: 3,
      );
    }
  }, peak: 0.72);

  out[Sfx.bridgeLock] = make(0.50, (b) {
    s.tone(
      b,
      freq: 300,
      toFreq: 640,
      dur: 0.30,
      wave: Wave.triangle,
      gain: 0.45,
      decay: 4,
    );
    s.metallic(b, freq: 640, start: 0.24, dur: 0.24, gain: 0.5, decay: 9);
  }, peak: 0.78);

  out[Sfx.keyCollect] = make(0.80, (b) {
    const notes = [660.0, 880.0, 1100.0, 1320.0];
    for (var i = 0; i < notes.length; i++) {
      s.tone(
        b,
        freq: notes[i],
        start: i * 0.075,
        dur: 0.42,
        wave: Wave.sine,
        gain: 0.36,
        decay: 4.5,
      );
    }
    s.tone(
      b,
      freq: 1760,
      start: 0.28,
      dur: 0.40,
      wave: Wave.triangle,
      gain: 0.20,
      decay: 5,
    );
  }, peak: 0.82);

  out[Sfx.portalUnlock] = make(1.30, (b) {
    s.tone(
      b,
      freq: 120,
      toFreq: 480,
      dur: 0.95,
      wave: Wave.saw,
      gain: 0.32,
      decay: 1.1,
      attack: 0.10,
    );
    s.tone(
      b,
      freq: 480,
      toFreq: 960,
      dur: 0.85,
      start: 0.15,
      wave: Wave.sine,
      gain: 0.30,
      decay: 1.6,
    );
    s.noiseBurst(
      b,
      start: 0.75,
      dur: 0.45,
      gain: 0.35,
      decay: 5,
      lowpass: 0.5,
      bandCentre: 0.06,
    );
    s.metallic(b, freq: 720, start: 0.80, dur: 0.45, gain: 0.42, decay: 6);
  }, peak: 0.9);

  out[Sfx.levelComplete] = make(1.70, (b) {
    const chord = [523.25, 659.25, 783.99, 1046.5];
    for (var i = 0; i < chord.length; i++) {
      s.tone(
        b,
        freq: chord[i],
        start: i * 0.10,
        dur: 1.25 - i * 0.08,
        wave: Wave.triangle,
        gain: 0.30,
        decay: 2.2,
      );
      s.tone(
        b,
        freq: chord[i] * 2,
        start: i * 0.10 + 0.02,
        dur: 0.60,
        wave: Wave.sine,
        gain: 0.12,
        decay: 3.5,
      );
    }
    s.noiseBurst(
      b,
      start: 0.0,
      dur: 0.30,
      gain: 0.22,
      decay: 7,
      lowpass: 0.6,
      bandCentre: 0.08,
    );
  }, peak: 0.88);

  out[Sfx.failure] = make(1.15, (b) {
    s.tone(
      b,
      freq: 320,
      toFreq: 70,
      dur: 0.85,
      wave: Wave.saw,
      gain: 0.40,
      decay: 2.0,
    );
    s.tone(
      b,
      freq: 214,
      toFreq: 52,
      dur: 0.95,
      wave: Wave.sine,
      gain: 0.34,
      decay: 1.8,
    );
    s.noiseBurst(b, dur: 0.40, gain: 0.30, decay: 4.5, lowpass: 0.22);
  }, peak: 0.82);

  return out;
}
