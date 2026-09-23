import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:collection';

import 'dev_profiler.dart';

class SystemResourcesWidget extends StatefulWidget {
  const SystemResourcesWidget({super.key});

  @override
  State<SystemResourcesWidget> createState() => _SystemResourcesWidgetState();
}

class _SystemResourcesWidgetState extends State<SystemResourcesWidget> {
  // Only Android/Linux expose /proc. Everywhere else we skip file reads
  // entirely instead of retrying-and-failing every 2 seconds.
  static final bool _procFsSupported = Platform.isAndroid || Platform.isLinux;

  // Anything at or above this counts as a visible "spike" in the list below.
  // Half a 60fps frame budget (16.7ms) is a reasonable default.
  static const double _spikeThresholdMs = 8.0;

  double _fps = 0.0;
  int _frameCount = 0;
  DateTime _lastFpsUpdate = DateTime.now();
  DateTime? _lastFrameTime;

  double _worstFrameTimeMs = 0.0; // worst single frame in the current second
  double _lastReportedWorstFrameTimeMs = 0.0; // what's shown in the UI

  int _framesRendered = 0; // renamed from "rebuild count" -- see note below

  int _totalRamMB = 0;
  int _usedRamMB = 0;
  int _appRamMB = 0;
  double _processCpu = 0.0;

  final int _pid = pid;
  final Queue<double> _fpsHistory = Queue<double>();
  static const int _historySize = 40;

  int _prevTotalJiffies = 0;
  int _prevProcessJiffies = 0;

  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _startMonitoring();
    if (_procFsSupported) {
      _updateSystemStats();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Frame monitoring. Uses a self-rescheduling transient frame callback
  // instead of addPersistentFrameCallback, since persistent callbacks have
  // no way to be removed -- they'd otherwise keep running forever even
  // after this widget is disposed.
  // ---------------------------------------------------------------------

  void _startMonitoring() {
    SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
  }

  void _onFrame(Duration timeStamp) {
    if (_disposed) return;

    final now = DateTime.now();
    _frameCount++;
    _framesRendered++;

    if (_lastFrameTime != null) {
      final frameMs = now.difference(_lastFrameTime!).inMicroseconds / 1000.0;
      if (frameMs > _worstFrameTimeMs) _worstFrameTimeMs = frameMs;
    }
    _lastFrameTime = now;

    if (now.difference(_lastFpsUpdate).inMilliseconds >= 1000) {
      if (mounted) {
        setState(() {
          _fps = _frameCount.toDouble();
          _frameCount = 0;
          _lastFpsUpdate = now;
          _lastReportedWorstFrameTimeMs = _worstFrameTimeMs;
          _worstFrameTimeMs = 0.0;

          _fpsHistory.add(_fps);
          if (_fpsHistory.length > _historySize) _fpsHistory.removeFirst();
        });
      }
    }

    // Re-arm for the next frame. This only fires again once the engine
    // actually produces another frame -- it doesn't force extra frames
    // itself, so it stays a passive observer of the game's real render
    // loop rather than skewing it.
    SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
  }

  // ---------------------------------------------------------------------
  // System stats (Android/Linux only -- procfs doesn't exist elsewhere)
  // ---------------------------------------------------------------------

  Future<void> _updateSystemStats() async {
    try {
      final meminfo = await File('/proc/meminfo').readAsString();
      final totalMatch = RegExp(r'MemTotal:\s+(\d+)').firstMatch(meminfo);
      final availMatch = RegExp(r'MemAvailable:\s+(\d+)').firstMatch(meminfo);

      if (totalMatch != null) {
        _totalRamMB = int.parse(totalMatch.group(1)!) ~/ 1024;
      }
      if (availMatch != null) {
        final avail = int.parse(availMatch.group(1)!) ~/ 1024;
        _usedRamMB = _totalRamMB - avail;
      }

      final status = await File('/proc/$_pid/status').readAsString();
      final rssMatch = RegExp(r'VmRSS:\s+(\d+)').firstMatch(status);
      if (rssMatch != null) {
        _appRamMB = int.parse(rssMatch.group(1)!) ~/ 1024;
      }

      _processCpu = await _getProcessCpuUsage();
    } catch (e) {
      debugPrint('Stats error: $e');
    }

    if (mounted && !_disposed) {
      setState(() {});
      Future.delayed(const Duration(seconds: 2), _updateSystemStats);
    }
  }

  Future<double> _getProcessCpuUsage() async {
    try {
      final stat = await File('/proc/stat').readAsString();
      final lines = stat.split('\n');
      if (lines.isNotEmpty) {
        final cpuLine = lines[0].split(RegExp(r'\s+'));
        if (cpuLine.length > 8) {
          final user = int.parse(cpuLine[1]);
          final nice = int.parse(cpuLine[2]);
          final system = int.parse(cpuLine[3]);
          final idle = int.parse(cpuLine[4]);
          final iowait = int.parse(cpuLine[5]);
          final totalJiffies = user + nice + system + idle + iowait;

          final pstat = await File('/proc/$_pid/stat').readAsString();
          final pparts = pstat.split(' ');
          if (pparts.length > 14) {
            final utime = int.parse(pparts[13]);
            final stime = int.parse(pparts[14]);
            final processJiffies = utime + stime;

            final isFirstSample =
                _prevTotalJiffies == 0 && _prevProcessJiffies == 0;
            final deltaTotal = totalJiffies - _prevTotalJiffies;
            final deltaProcess = processJiffies - _prevProcessJiffies;

            _prevTotalJiffies = totalJiffies;
            _prevProcessJiffies = processJiffies;

            if (!isFirstSample && deltaTotal > 0) {
              // deltaTotal is jiffies across ALL cores, so normalize back
              // up to a single-core percentage (matches how `top` reports
              // per-process CPU%) instead of underreporting on multi-core
              // devices.
              final raw = deltaProcess / deltaTotal * 100;
              final cores = Platform.numberOfProcessors.clamp(1, 64);
              return (raw * cores).clamp(0.0, 100.0 * cores);
            }
          }
        }
      }
    } catch (_) {}
    return 0.0;
  }

  void _resetStats() {
    setState(() {
      _framesRendered = 0;
      _fpsHistory.clear();
      DevProfiler.instance.clear();
    });
  }

  /// Manufactures a fake ~20ms span so you can confirm the profiler
  /// pipeline (record -> recentSpans -> Recent Spikes panel) is alive
  /// without needing to have wrapped any real game code yet.
  void _testProfiler() {
    DevProfiler.instance.trace('test_spike', () {
      final sw = Stopwatch()..start();
      while (sw.elapsedMilliseconds < 20) {
        // Deliberately busy-wait -- this is a synthetic spike, not real
        // work. Safe to leave in; it only runs when you tap the button.
      }
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: const Icon(Icons.monitor_rounded, color: Colors.orange),
          title: const Text('System Resources (Dev)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('Real-time performance monitoring'),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SizedBox(
                    height: 60,
                    child: CustomPaint(
                      painter: FpsSparklinePainter(_fpsHistory.toList()),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildLabeledMetric(
                    label: 'Current FPS',
                    value: '${_fps.toStringAsFixed(1)} fps',
                    tooltip:
                        'Frames rendered per second. Aim for 60+ for smooth gameplay.',
                    color: _fps > 55 ? Colors.green : Colors.orange,
                  ),
                  _buildLabeledMetric(
                    label: 'Worst Frame Time (last 1s)',
                    value:
                        '${_lastReportedWorstFrameTimeMs.toStringAsFixed(1)} ms',
                    tooltip:
                        'The single slowest frame in the last second. Spikes above ~16.7ms drop you below 60 FPS; this is what to watch when hunting for jank.',
                    color: _lastReportedWorstFrameTimeMs > 16.7
                        ? Colors.redAccent
                        : (_lastReportedWorstFrameTimeMs > 8
                            ? Colors.orange
                            : null),
                  ),
                  _buildLabeledMetric(
                    label: 'Frames Rendered (session)',
                    value: '$_framesRendered',
                    tooltip:
                        'Total frames rendered since last reset. Not a widget-rebuild count -- true per-widget rebuild tracking would need separate instrumentation.',
                  ),
                  _buildLabeledMetric(
                    label: 'Game ProcessID',
                    value: '$_pid',
                    tooltip:
                        'Operating System Process ID for this game instance.',
                  ),
                  const Divider(height: 24),
                  if (_procFsSupported) ...[
                    _buildLabeledMetric(
                      label: 'Game Memory (in use)',
                      value: '$_appRamMB MB',
                      tooltip:
                          'Resident Set Size (RSS) - physical memory used by the game.',
                    ),
                    _buildLabeledMetric(
                      label: 'Total System Memory (in use)',
                      value: '$_usedRamMB / $_totalRamMB MB',
                      tooltip:
                          'How much RAM is currently used across the entire system.',
                    ),
                    _buildLabeledMetric(
                      label: 'Game CPU Utilization',
                      value: '${_processCpu.toStringAsFixed(1)}%',
                      tooltip:
                          'Percentage of one CPU core used by the game process (normalized like `top`).',
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Memory/CPU stats aren\'t available on this platform (procfs is Android/Linux only).',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  const Divider(height: 24),
                  _buildSpikePanel(cs),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _copyStats,
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy All Stats'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _resetStats,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reset Counters'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _testProfiler,
                        icon: const Icon(Icons.bug_report_rounded, size: 18),
                        label: const Text('Test Spike'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Recent Spikes -- reads DevProfiler.instance so any code you've wrapped
  // with DevProfiler.instance.trace('label', () { ... }) shows up here the
  // moment it takes longer than _spikeThresholdMs.
  // ---------------------------------------------------------------------

  Widget _buildSpikePanel(ColorScheme cs) {
    final spans = DevProfiler.instance.recentSpans(limit: 15);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.query_stats_rounded, size: 18, color: cs.tertiary),
            const SizedBox(width: 8),
            const Text(
              'Recent Spikes',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (spans.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No profiled spans yet. Wrap suspect code with '
              "DevProfiler.instance.trace('label', () { ... }) to see it "
              'show up here when it spikes -- e.g. your NPC tick function.',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          )
        else
          ...spans.map((span) => _buildSpikeRow(cs, span)),
      ],
    );
  }

  Widget _buildSpikeRow(ColorScheme cs, ProfileSpan span) {
    final isSpike = span.durationMs >= _spikeThresholdMs;
    final color = span.durationMs >= 16.7
        ? Colors.redAccent
        : (isSpike ? Colors.orange : cs.onSurface.withValues(alpha: 0.5));

    final secondsAgo = DateTime.now().difference(span.at).inSeconds;
    final agoText = secondsAgo < 1 ? 'just now' : '${secondsAgo}s ago';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          if (isSpike)
            Icon(Icons.warning_rounded, size: 14, color: color)
          else
            const SizedBox(width: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              span.label,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${span.durationMs.toStringAsFixed(1)}ms',
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              fontWeight: isSpike ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            agoText,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabeledMetric({
    required String label,
    required String value,
    required String tooltip,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      preferBelow: true,
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[700]!),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 13),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 15)),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color ?? Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _copyStats() {
    final spikeLines = DevProfiler.instance
        .recentSpans(limit: 10)
        .map((s) => '  ${s.label}: ${s.durationMs.toStringAsFixed(1)}ms')
        .join('\n');

    final stats = '''
=== Cosmic Trader Dev Stats ===
Time: ${DateTime.now()}
Current FPS: ${_fps.toStringAsFixed(1)}
Worst Frame Time (last 1s): ${_lastReportedWorstFrameTimeMs.toStringAsFixed(1)} ms
Frames Rendered: $_framesRendered
Game ProcessID: $_pid
Game Memory: $_appRamMB MB
System Memory: $_usedRamMB / $_totalRamMB MB
Game CPU: ${_processCpu.toStringAsFixed(1)}%
Recent Spikes:
$spikeLines
''';

    Clipboard.setData(ClipboardData(text: stats));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stats copied to clipboard!')),
    );
  }
}

// Sparkline Painter
class FpsSparklinePainter extends CustomPainter {
  final List<double> data;
  FpsSparklinePainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final paint = Paint()
      ..color = Colors.orange
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final maxValue = data.reduce((a, b) => a > b ? a : b) * 1.1;
    final clampedMax = maxValue.clamp(1.0, 200.0);

    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height * (1 - (data[i] / clampedMax));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
