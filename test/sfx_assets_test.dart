import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the bundled sound-effect assets.
///
/// The audio engine pre-dated registration of these cues: `AudioCache`
/// prepends its own `assets/` prefix to the path handed to an `AssetSource`,
/// so passing the full `assets/sfx/...` path resolved to
/// `assets/assets/sfx/...` — which doesn't exist in the bundle, threw, and was
/// swallowed into silence. `AudioService` now strips the leading `assets/`, so
/// these tests pin the *correct* bundle key for every shipped cue.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const cues = [
    'assets/sfx/buy.ogg',
    'assets/sfx/sell.ogg',
    'assets/sfx/hack.ogg',
    'assets/sfx/laser.ogg',
    'assets/sfx/warp.ogg',
    'assets/sfx/lottery.ogg',
    'assets/sfx/land.ogg',
  ];

  for (final key in cues) {
    test('$key loads via the AudioCache-prefixed key', () async {
      final data = await rootBundle.load(key);
      expect(data.lengthInBytes, greaterThan(0));
    });

    test('$key fails if double-prefixed (the old silent bug)', () async {
      var threw = false;
      try {
        await rootBundle.load('assets/$key');
      } catch (_) {
        threw = true;
      }
      expect(threw, isTrue);
    });
  }
}
