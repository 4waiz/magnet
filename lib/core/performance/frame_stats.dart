/// Rolling frame-time statistics from the engine's own timings callback.
///
/// Measures `totalSpan` (build + raster), which is the number that decides
/// whether a frame was delivered on time. The first second of samples is
/// discarded: shader warm-up and first-frame uploads are not steady state and
/// including them makes every measurement look worse than the game runs.
library;

class FrameStats {
  FrameStats({this.window = 300, this.warmupFrames = 60});

  final int window;
  final int warmupFrames;

  final List<double> _samples = [];
  int _seen = 0;

  double avgMs = 0;
  double p95Ms = 0;
  double p99Ms = 0;
  double maxMs = 0;
  int get sampleCount => _samples.length;

  /// Frames whose total span exceeded 16.7 ms.
  int droppedFrames = 0;

  void onTimings(List<dynamic> timings) {
    for (final t in timings) {
      final micros = (t as dynamic).totalSpan.inMicroseconds as int;
      final ms = micros / 1000.0;
      _seen++;
      if (_seen < warmupFrames) continue;
      _samples.add(ms);
      if (ms > maxMs) maxMs = ms;
      if (ms > 16.7) droppedFrames++;
      if (_samples.length > window) _samples.removeAt(0);
    }
    _recompute();
  }

  void _recompute() {
    if (_samples.length < 20) return;
    final sorted = List<double>.from(_samples)..sort();
    var sum = 0.0;
    for (final s in _samples) {
      sum += s;
    }
    avgMs = sum / _samples.length;
    p95Ms = sorted[(sorted.length * 0.95).floor().clamp(0, sorted.length - 1)];
    p99Ms = sorted[(sorted.length * 0.99).floor().clamp(0, sorted.length - 1)];
  }

  void reset() {
    _samples.clear();
    _seen = 0;
    avgMs = 0;
    p95Ms = 0;
    p99Ms = 0;
    maxMs = 0;
    droppedFrames = 0;
  }

  Map<String, Object> toReport() => {
    'samples': _samples.length,
    'avgMs': double.parse(avgMs.toStringAsFixed(2)),
    'p95Ms': double.parse(p95Ms.toStringAsFixed(2)),
    'p99Ms': double.parse(p99Ms.toStringAsFixed(2)),
    'maxMs': double.parse(maxMs.toStringAsFixed(2)),
    'droppedFrames': droppedFrames,
  };
}
