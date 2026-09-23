import 'package:flutter/material.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';
import 'package:window_manager/window_manager.dart' as window_manager;

class VideoSettingsWidget extends StatelessWidget {
  final bool fullscreen;
  final int resolutionWidth;
  final int resolutionHeight;
  final double animationSpeed;
  final ValueChanged<bool> onFullscreenChanged;
  final ValueChanged<int> onResolutionWidthChanged;
  final ValueChanged<int> onResolutionHeightChanged;
  final ValueChanged<double> onAnimationSpeedChanged;
  final GameSettings Function() buildSettings;
  final ValueChanged<GameSettings>? onSaveSettings;

  const VideoSettingsWidget({
    super.key,
    required this.fullscreen,
    required this.resolutionWidth,
    required this.resolutionHeight,
    required this.animationSpeed,
    required this.onFullscreenChanged,
    required this.onResolutionWidthChanged,
    required this.onResolutionHeightChanged,
    required this.onAnimationSpeedChanged,
    required this.buildSettings,
    this.onSaveSettings,
  });

  static const _resolutions = [
    (label: '1280 × 720', width: 1280, height: 720),
    (label: '1366 × 768', width: 1366, height: 768),
    (label: '1600 × 900', width: 1600, height: 900),
    (label: '1920 × 1080', width: 1920, height: 1080),
    (label: '2560 × 1440', width: 2560, height: 1440),
    (label: '3840 × 2160', width: 3840, height: 2160),
  ];

  String get _currentLabel {
    for (final r in _resolutions) {
      if (r.width == resolutionWidth && r.height == resolutionHeight) {
        return r.label;
      }
    }
    return '$resolutionWidth × $resolutionHeight';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = cs.primary;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent.withValues(alpha: 0.2)),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: Icon(Icons.video_settings_rounded, color: accent),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('▒ ',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w100,
                      color: accent.withValues(alpha: 0.5))),
              Text('VIDEO SETTINGS',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  )),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel(context, 'DISPLAY'),
                  const SizedBox(height: 8),
                  _fullscreenToggle(context),
                  const SizedBox(height: 4),
                  _resolutionSelector(context),
                  const SizedBox(height: 16),
                  _divider(accent),
                  const SizedBox(height: 16),
                  _sectionLabel(context, 'EFFECTS SPEED'),
                  const SizedBox(height: 8),
                  _speedSlider(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final accent = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: accent.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  Widget _divider(Color accent) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.4),
            accent.withValues(alpha: 0.1),
            Colors.transparent,
          ],
        ),
      ),
    );
  }

  Widget _fullscreenToggle(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = cs.primary;
    final dimText = cs.onSurface.withValues(alpha: 0.6);

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.15), width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.fullscreen_rounded, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fullscreen',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: dimText,
                  ),
                ),
                Text(
                  fullscreen ? 'Borderless window' : 'Windowed',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: fullscreen,
            onChanged: (v) async {
              onFullscreenChanged(v);
              try {
                await window_manager.WindowManager.instance.setFullScreen(v);
                if (!v) {
                  await window_manager.WindowManager.instance.setSize(
                    Size(resolutionWidth.toDouble(),
                        resolutionHeight.toDouble()),
                  );
                  await window_manager.WindowManager.instance.center();
                }
              } catch (_) {}
              onSaveSettings?.call(buildSettings());
            },
            activeThumbColor: accent,
          ),
        ],
      ),
    );
  }

  Widget _resolutionSelector(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = cs.primary;
    final dimText = cs.onSurface.withValues(alpha: 0.6);

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.15), width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.aspect_ratio_rounded, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Resolution',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: dimText,
              ),
            ),
          ),
          DropdownButton<String>(
            value: _currentLabel,
            underline: const SizedBox(),
            style: TextStyle(
              fontSize: 13,
              color: accent,
              fontWeight: FontWeight.w600,
            ),
            dropdownColor: cs.surfaceContainerHighest,
            items: _resolutions.map((r) {
              return DropdownMenuItem(
                value: r.label,
                child: Text(r.label),
              );
            }).toList(),
            onChanged: (v) {
              if (v == null) return;
              for (final r in _resolutions) {
                if (r.label == v) {
                  onResolutionWidthChanged(r.width);
                  onResolutionHeightChanged(r.height);
                  try {
                    window_manager.WindowManager.instance.setSize(
                      Size(r.width.toDouble(), r.height.toDouble()),
                    );
                    window_manager.WindowManager.instance.center();
                  } catch (_) {}
                  onSaveSettings?.call(buildSettings());
                  return;
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _speedSlider(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = cs.primary;
    final dimText = cs.onSurface.withValues(alpha: 0.6);

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.15), width: 0.5),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.speed_rounded, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                'EFFECTS SPEED',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: dimText,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: accent.withValues(alpha: 0.3), width: 0.5),
                ),
                child: Text(
                  '${(animationSpeed * 100).round()}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: accent,
              inactiveTrackColor: accent.withValues(alpha: 0.15),
              thumbColor: accent,
              overlayColor: accent.withValues(alpha: 0.12),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: animationSpeed,
              onChanged: onAnimationSpeedChanged,
              onChangeEnd: (_) => onSaveSettings?.call(buildSettings()),
              min: 0.1,
              max: 2.0,
              divisions: 19,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Controls animation speed for tactical display effects '
              '(pings, scans, transitions). Higher = faster animations.',
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
