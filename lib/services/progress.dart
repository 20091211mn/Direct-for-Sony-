/// Moving-average speed meter used to estimate the remaining time.
class SpeedMeter {
  SpeedMeter({this.window = const Duration(seconds: 15)});

  final Duration window;
  final Stopwatch _clock = Stopwatch()..start();
  final List<_Sample> _samples = [];

  /// Record the total number of bytes transferred so far.
  void add(int bytes) {
    final now = _clock.elapsed;
    _samples.add(_Sample(now, bytes));
    while (_samples.length > 2 && now - _samples.first.time > window) {
      _samples.removeAt(0);
    }
  }

  /// Average speed over the window, in bytes per second (0 if unknown).
  double get bytesPerSecond {
    if (_samples.length < 2) return 0;
    final a = _samples.first;
    final b = _samples.last;
    final seconds = (b.time - a.time).inMilliseconds / 1000.0;
    if (seconds <= 0) return 0;
    final speed = (b.bytes - a.bytes) / seconds;
    return speed > 0 ? speed : 0;
  }

  /// Estimated time left, or null while the speed is still unknown.
  Duration? eta(int total, int done) {
    final speed = bytesPerSecond;
    if (speed < 1024 || total <= done) return null;
    return Duration(seconds: ((total - done) / speed).ceil());
  }
}

class _Sample {
  _Sample(this.time, this.bytes);
  final Duration time;
  final int bytes;
}
