import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/core/ui_scale.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';

/// Regression guard for the "UI scale isn't saved across restarts" bug.
///
/// The scale, density, video and audio prefs must all survive a
/// settings.json round-trip and old save files must keep legacy defaults.
void main() {
  test('UI scale / density and video/audio prefs survive a JSON round-trip',
      () {
    final original = GameSettings.defaults().copyWith(
      uiScale: 1.75,
      uiScaleAuto: false,
      uiDensity: UiDensity.cozy,
      fontFamily: 'monospace',
      fontSize: 16,
      fullscreen: true,
      windowScale: 0.9,
      resolutionWidth: 1920,
      resolutionHeight: 1080,
      musicVolume: 0.4,
      sfxVolume: 0.3,
    );

    final restored = GameSettings.fromJson(original.toJson());

    expect(restored.uiScale, 1.75);
    expect(restored.uiScaleAuto, false);
    expect(restored.uiDensity, UiDensity.cozy);
    expect(restored.fontFamily, 'monospace');
    expect(restored.fontSize, 16);
    expect(restored.fullscreen, true);
    expect(restored.windowScale, 0.9);
    expect(restored.resolutionWidth, 1920);
    expect(restored.resolutionHeight, 1080);
    expect(restored.musicVolume, 0.4);
    expect(restored.sfxVolume, 0.3);
  });

  test('manual scale with auto off stays intact through a round-trip', () {
    final original = GameSettings.defaults().copyWith(
      uiScale: 1.8,
      uiScaleAuto: false,
      uiDensity: UiDensity.compact,
    );

    final restored = GameSettings.fromJson(original.toJson());

    expect(restored.uiScale, 1.8);
    expect(restored.uiScaleAuto, false);
    expect(restored.uiDensity, UiDensity.compact);
  });

  test(
      'legacy settings files fall back to scale 1.0, auto on, normal '
      'density', () {
    final restored = GameSettings.fromJson(const {});

    expect(restored.uiScale, 1.0);
    expect(restored.uiScaleAuto, true);
    expect(restored.uiDensity, UiDensity.normal);
  });
}
