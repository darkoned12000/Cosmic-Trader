import 'dart:io' show Directory, File;

import 'package:flutter/material.dart';
import 'package:tradewars_2050/data/models/game_settings.dart';

class FontSettingsWidget extends StatefulWidget {
  final String fontFamily;
  final double fontSize;
  final ValueChanged<String> onFontFamilyChanged;
  final ValueChanged<double> onFontSizeChanged;
  final GameSettings Function() buildSettings;
  final ValueChanged<GameSettings>? onSaveSettings;

  const FontSettingsWidget({
    super.key,
    required this.fontFamily,
    required this.fontSize,
    required this.onFontFamilyChanged,
    required this.onFontSizeChanged,
    required this.buildSettings,
    this.onSaveSettings,
  });

  @override
  State<FontSettingsWidget> createState() => _FontSettingsWidgetState();
}

class _FontSettingsWidgetState extends State<FontSettingsWidget> {
  static const _fontExtensions = ['.ttf', '.otf', '.ttc'];
  List<String> _customFonts = [];
  bool _scanning = true;

  @override
  void initState() {
    super.initState();
    _scanForFonts();
  }

  Future<void> _scanForFonts() async {
    try {
      final dir = Directory('assets/fonts');
      if (await dir.exists()) {
        final files = dir
            .listSync()
            .whereType<File>()
            .where((f) =>
                _fontExtensions.any((ext) => f.path.toLowerCase().endsWith(ext)))
            .map((f) => f.path.split('/').last)
            .toList();
        if (mounted) {
          setState(() {
            _customFonts = files;
            _scanning = false;
          });
        }
        return;
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _scanning = false);
    }
  }

  List<String> get _fontOptions {
    final options = <String>['System Default'];
    options.addAll(_customFonts);
    return options;
  }

  String get _currentLabel {
    if (widget.fontFamily.isEmpty) return 'System Default';
    return widget.fontFamily;
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
          leading: Icon(Icons.font_download_rounded, color: accent),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('▒ ',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w100,
                      color: accent.withValues(alpha: 0.5))),
              Text('FONTS',
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
                  _sectionLabel(context, 'FONT FAMILY'),
                  const SizedBox(height: 8),
                  _fontFamilySelector(context),
                  const SizedBox(height: 16),
                  _divider(accent),
                  const SizedBox(height: 16),
                  _sectionLabel(context, 'FONT SIZE'),
                  const SizedBox(height: 8),
                  _fontSizeSlider(context),
                  const SizedBox(height: 16),
                  _divider(accent),
                  const SizedBox(height: 16),
                  _sectionLabel(context, 'PREVIEW'),
                  const SizedBox(height: 8),
                  _fontPreview(context),
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

  Widget _fontFamilySelector(BuildContext context) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.text_fields_rounded, size: 18, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Typeface',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: dimText,
                  ),
                ),
              ),
              if (_scanning)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent,
                  ),
                )
              else
                DropdownButton<String>(
                  value: _currentLabel,
                  underline: const SizedBox(),
                  style: TextStyle(
                    fontSize: 13,
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                  dropdownColor: cs.surfaceContainerHighest,
                  items: _fontOptions.map((f) {
                    return DropdownMenuItem(
                      value: f,
                      child: Text(
                        f,
                        style: TextStyle(
                          fontFamily:
                              f == 'System Default' ? null : f.split('.').first,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    widget.onFontFamilyChanged(
                        v == 'System Default' ? '' : v.split('.').first);
                    widget.onSaveSettings?.call(widget.buildSettings());
                  },
                ),
            ],
          ),
          if (_customFonts.isEmpty && !_scanning)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(
                'Place .ttf / .otf files in assets/fonts/ to add custom '
                'typefaces, then declare them in pubspec.yaml under flutter → fonts.',
                style: TextStyle(
                  fontSize: 10,
                  height: 1.3,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fontSizeSlider(BuildContext context) {
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
              Icon(Icons.format_size_rounded, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                'BASE SIZE',
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
                  '${widget.fontSize.round()}pt',
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
              value: widget.fontSize,
              onChanged: widget.onFontSizeChanged,
              onChangeEnd: (_) =>
                  widget.onSaveSettings?.call(widget.buildSettings()),
              min: 10,
              max: 24,
              divisions: 14,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Small',
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                Text(
                  'Large',
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fontPreview(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = cs.primary;

    final family =
        widget.fontFamily.isEmpty ? null : widget.fontFamily;
    final size = widget.fontSize;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.15), width: 0.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The quick brown fox jumps over the lazy dog.',
            style: TextStyle(
              fontFamily: family,
              fontSize: size,
              height: 1.4,
              color: cs.onSurface.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
            style: TextStyle(
              fontFamily: family,
              fontSize: size * 0.85,
              letterSpacing: 2,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'abcdefghijklmnopqrstuvwxyz 0123456789',
            style: TextStyle(
              fontFamily: family,
              fontSize: size * 0.85,
              letterSpacing: 1,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'TradeWars 2050 — Sector Navigation • Cargo Management • '
            'Combat Systems • Galaxy Map',
            style: TextStyle(
              fontFamily: family,
              fontSize: size * 0.7,
              height: 1.3,
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
