import 'dart:collection';

/// Lightweight named-span profiler for finding *what* caused a frame spike,
/// not just that one happened.
///
/// Wrap any suspect block with a trace call:
///
/// ```dart
/// void _runNpcTick() {
///   DevProfiler.instance.trace('npc_tick', () {
///     for (final npc in npcs) {
///       npc.update();
///     }
///   });
/// }
/// ```
///
/// `SystemResourcesWidget` reads `DevProfiler.instance.recentSpans()` and
/// lists anything over its spike threshold, so once your 30s NPC tick is
/// wrapped, you'll see a line like `npc_tick  41.2ms  3s ago` show up right
/// when the frame-time graph spikes.
///
/// This is a no-op-adjacent dev tool: a `Stopwatch` per call and a bounded
/// in-memory queue. Fine to leave wrapped in debug builds; consider gating
/// calls behind `kDebugMode` if you ship this code to release builds.
class DevProfiler {
  DevProfiler._();
  static final DevProfiler instance = DevProfiler._();

  static const int maxSpans = 200;

  final Queue<ProfileSpan> _spans = Queue<ProfileSpan>();

  /// Times [fn] and records it under [label]. Returns whatever [fn] returns,
  /// so you can wrap an existing call in place without restructuring it.
  T trace<T>(String label, T Function() fn) {
    final sw = Stopwatch()..start();
    try {
      return fn();
    } finally {
      sw.stop();
      record(label, sw.elapsedMicroseconds / 1000.0);
    }
  }

  /// Same idea as [trace] but for async work, since `await` can't happen
  /// inside a `finally` around a sync call cleanly.
  Future<T> traceAsync<T>(String label, Future<T> Function() fn) async {
    final sw = Stopwatch()..start();
    try {
      return await fn();
    } finally {
      sw.stop();
      record(label, sw.elapsedMicroseconds / 1000.0);
    }
  }

  /// Record an already-measured duration directly.
  void record(String label, double durationMs) {
    _spans.addLast(ProfileSpan(
      label: label,
      durationMs: durationMs,
      at: DateTime.now(),
    ));
    while (_spans.length > maxSpans) {
      _spans.removeFirst();
    }
  }

  /// Most recent spans, newest first.
  List<ProfileSpan> recentSpans({int limit = 20}) {
    return _spans.toList().reversed.take(limit).toList();
  }

  void clear() => _spans.clear();
}

class ProfileSpan {
  final String label;
  final double durationMs;
  final DateTime at;

  const ProfileSpan({
    required this.label,
    required this.durationMs,
    required this.at,
  });
}
