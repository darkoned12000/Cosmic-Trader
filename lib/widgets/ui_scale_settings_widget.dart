import 'package:flutter/material.dart';
import 'package:cosmic_trader/core/ui_scale.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';

/// Settings UI for the global interface magnification (UI scale).
///
/// Mirrors the visual style of [VideoSettingsWidget]: a card with a
/// labelled expansion tile, styled section headers, and dense control rows.
class UiScaleSettingsWidget extends StatelessWidget {
  final bool auto;
  final double scale;
  final UiDensity density;
  final ValueChanged<bool> onAutoChanged;
  final ValueChanged<double> onScaleChanged;
  final ValueChanged<double>? onScaleChangeEnd;
  final ValueChanged<UiDensity> onDensityChanged;
  final VoidCallback? onReDetect;
  final GameSettings Function() buildSettings;
  final ValueChanged<GameSettings>? onSaveSettings;

  const UiScaleSettingsWidget({
    super.key,
    required this.auto,
    required this.scale,
    required this.density,
    required this.onAutoChanged,
    required this.onScaleChanged,
    this.onScaleChangeEnd,
    required this.onDensityChanged,
    this.onReDetect,
    required this.buildSettings,
    this.onSaveSettings,
  });

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
          leading: Icon(Icons.zoom_out_map_rounded, color: accent),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('▒ ',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w100,
                      color: accent.withValues(alpha: 0.5))),
              Text('UI SCALE',
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
                  _sectionLabel(context, 'SCALING'),
                  const SizedBox(height: 8),
                  _autoToggle(context),
                  const SizedBox(height: 4),
                  if (auto) _detectRow(context) else _slider(context),
                  const SizedBox(height: 16),
                  _divider(accent),
                  const SizedBox(height: 16),
                  _sectionLabel(context, 'DENSITY'),
                  const SizedBox(height: 8),
                  _densitySelector(context),
                  const SizedBox(height: 16),
                  _divider(accent),
                  const SizedBox(height: 16),
                  Text(
                    'Scales the entire interface — panels, icons, spacing and '
                    'maps — to fill high-resolution displays. Kept separate '
                    'from the font-size setting, which scales text on top. '
                    'Density is a separate knob that tightens or relaxes the '
                    'space between panels, rows and list items without '
                    'changing the scale. At 100% OS scaling this is the '
                    'recommended fix for 4K.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _densitySelector(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: UiDensity.values.map((d) {
            return ChoiceChip(
              label: Text(d.label),
              selected: density == d,
              visualDensity: VisualDensity.compact,
              onSelected: (_) {
                onDensityChanged(d);
                onSaveSettings?.call(buildSettings());
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Text(
          'Compact fits more rows and panels on screen; Cozy adds breathing '
          'room. Works alongside the UI scale above — scale sets the overall '
          'size, density sets how tightly things are packed.',
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: cs.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
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

  Widget _autoToggle(BuildContext context) {
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
          Icon(Icons.auto_awesome_rounded, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto-detect from display',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: dimText,
                  ),
                ),
                Text(
                  auto
                      ? 'Scale is derived from your monitor on launch'
                      : 'Use the manual scale below',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: auto,
            onChanged: (v) {
              onAutoChanged(v);
              onSaveSettings?.call(buildSettings());
            },
            activeThumbColor: accent,
            activeTrackColor: accent,
          ),
        ],
      ),
    );
  }

  Widget _detectRow(BuildContext context) {
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.monitor_rounded, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Detected: ${scale.toStringAsFixed(2)}×',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: dimText,
                  ),
                ),
                Text(
                  'Wide displays suggest a bigger scale (e.g. 4K @100% → 1.50×).',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onReDetect,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Detect now', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _slider(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = cs.primary;
    final dimText = cs.onSurface.withValues(alpha: 0.6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: UiScale.presets.map((p) {
            final selected = (scale - p.value).abs() < 0.005;
            return ChoiceChip(
              label: Text(p.label),
              selected: selected,
              visualDensity: VisualDensity.compact,
              onSelected: (_) {
                onScaleChanged(p.value);
                onSaveSettings?.call(buildSettings());
              },
            );
          }).toList(),
        ),
        Container(
          margin: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: accent.withValues(alpha: 0.15), width: 0.5),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.zoom_in_rounded, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Text(
                    'UI SCALE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: dimText,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: accent.withValues(alpha: 0.3), width: 0.5),
                    ),
                    child: Text(
                      '${(scale * 100).round()}%',
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
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 8),
                ),
                child: Slider(
                  value: scale.clamp(UiScale.minScale, UiScale.maxScale),
                  onChanged: onScaleChanged,
                  onChangeEnd: (v) {
                    onScaleChangeEnd?.call(v);
                    onSaveSettings?.call(buildSettings());
                  },
                  min: UiScale.minScale,
                  max: UiScale.maxScale,
                  divisions: 20,
                ),
              ),
              Text(
                '100% = default · 125% = comfy · 150% = cozy · 200% = max. '
                'Applies instantly to the whole interface.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
