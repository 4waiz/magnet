/// A tiny offline synthesizer.
///
/// Every sound effect in Magnet Rush is generated here as 16-bit PCM at boot
/// and played from memory. That keeps the APK free of audio assets, sidesteps
/// sample licensing entirely, and lets the sound design be expressed as code
/// that can be tuned alongside the gameplay it accompanies.
library;

import 'dart:math' as math;
import 'dart:typed_data';

const int kSampleRate = 22050;

enum Wave { sine, triangle, saw, square, noise }

/// A mono float buffer under construction.
class Buf {
  Buf(this.samples);
  Buf.seconds(double s) : samples = Float64List((s * kSampleRate).round());

  final Float64List samples;
  int get length => samples.length;
  double get seconds => samples.length / kSampleRate;

  void add(int i, double v) {
    if (i >= 0 && i < samples.length) samples[i] += v;
  }

  /// Normalizes to [peak] and applies a short fade in/out so nothing clicks.
  Buf finish({double peak = 0.82, double fade = 0.004}) {
    var max = 0.0;
    for (final s in samples) {
      final a = s.abs();
      if (a > max) max = a;
    }
    if (max > 1e-9) {
      final k = peak / max;
      for (var i = 0; i < samples.length; i++) {
        samples[i] *= k;
      }
    }
    final f = math.max(1, (fade * kSampleRate).round());
    for (var i = 0; i < f && i < samples.length; i++) {
      final g = i / f;
      samples[i] *= g;
      samples[samples.length - 1 - i] *= g;
    }
    return this;
  }

  /// 16-bit mono WAV bytes.
  Uint8List toWav() {
    final n = samples.length;
    final bytes = Uint8List(44 + n * 2);
    final bd = ByteData.sublistView(bytes);
    void ascii(int off, String s) {
      for (var i = 0; i < s.length; i++) {
        bytes[off + i] = s.codeUnitAt(i);
      }
    }

    ascii(0, 'RIFF');
    bd.setUint32(4, 36 + n * 2, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little); // PCM
    bd.setUint16(22, 1, Endian.little); // mono
    bd.setUint32(24, kSampleRate, Endian.little);
    bd.setUint32(28, kSampleRate * 2, Endian.little);
    bd.setUint16(32, 2, Endian.little);
    bd.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    bd.setUint32(40, n * 2, Endian.little);
    for (var i = 0; i < n; i++) {
      final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
      bd.setInt16(44 + i * 2, v, Endian.little);
    }
    return bytes;
  }
}

class Synth {
  Synth([int seed = 1234]) : _rng = math.Random(seed);
  final math.Random _rng;

  double _osc(Wave w, double phase) {
    switch (w) {
      case Wave.sine:
        return math.sin(phase * math.pi * 2);
      case Wave.triangle:
        final t = phase % 1.0;
        return 4 * (t < 0.5 ? t : 1 - t) - 1;
      case Wave.saw:
        return 2 * (phase % 1.0) - 1;
      case Wave.square:
        return (phase % 1.0) < 0.5 ? 1.0 : -1.0;
      case Wave.noise:
        return _rng.nextDouble() * 2 - 1;
    }
  }

  /// Adds an oscillator with an exponential decay envelope and optional
  /// frequency glide from [freq] to [toFreq].
  void tone(
    Buf buf, {
    required double freq,
    double? toFreq,
    double start = 0.0,
    required double dur,
    Wave wave = Wave.sine,
    double gain = 1.0,
    double decay = 3.0,
    double attack = 0.006,
    double vibrato = 0.0,
    double vibratoHz = 6.0,
  }) {
    final s0 = (start * kSampleRate).round();
    final n = (dur * kSampleRate).round();
    var phase = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / kSampleRate;
      final u = i / n;
      var f = toFreq == null ? freq : freq + (toFreq - freq) * u;
      if (vibrato > 0) {
        f *= 1.0 + vibrato * math.sin(t * vibratoHz * math.pi * 2);
      }
      phase += f / kSampleRate;
      final atk = attack <= 0 ? 1.0 : math.min(1.0, t / attack);
      final env = atk * math.exp(-decay * u * (dur > 0 ? 1.0 : 1.0));
      buf.add(s0 + i, _osc(wave, phase) * env * gain);
    }
  }

  /// Filtered noise — the body of every impact and destruction sound.
  void noiseBurst(
    Buf buf, {
    double start = 0.0,
    required double dur,
    double gain = 1.0,
    double decay = 6.0,
    double lowpass = 0.35,
    double bandCentre = 0.0,
  }) {
    final s0 = (start * kSampleRate).round();
    final n = (dur * kSampleRate).round();
    var lp = 0.0;
    var lp2 = 0.0;
    for (var i = 0; i < n; i++) {
      final u = i / n;
      final raw = _rng.nextDouble() * 2 - 1;
      lp += (raw - lp) * lowpass;
      var v = lp;
      if (bandCentre > 0) {
        // Cheap band-pass: subtract a slower low-pass from a faster one.
        lp2 += (lp - lp2) * bandCentre;
        v = lp - lp2;
      }
      buf.add(s0 + i, v * math.exp(-decay * u) * gain);
    }
  }

  /// A metallic cluster: several inharmonic partials, as struck metal has.
  void metallic(
    Buf buf, {
    required double freq,
    double start = 0.0,
    required double dur,
    double gain = 1.0,
    double decay = 7.0,
    int partials = 5,
    double spread = 1.0,
  }) {
    const ratios = [1.0, 1.73, 2.41, 3.14, 4.27, 5.61];
    for (var p = 0; p < partials && p < ratios.length; p++) {
      tone(
        buf,
        freq: freq * (1 + (ratios[p] - 1) * spread),
        start: start,
        dur: dur * (1.0 - p * 0.10),
        wave: Wave.sine,
        gain: gain / (1.4 + p * 1.1),
        decay: decay + p * 1.8,
        attack: 0.001,
      );
    }
  }
}
