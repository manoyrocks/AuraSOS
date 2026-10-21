import 'package:aurasync/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SensoryProfile.effectiveHighCutHz', () {
    test('no limits means no cut', () {
      expect(const SensoryProfile().effectiveHighCutHz, 0);
    });

    test('explicit cut is used on its own', () {
      expect(const SensoryProfile(highCutHz: 2500).effectiveHighCutHz, 2500);
    });

    test('soften-high-tones switch caps at 1200 Hz', () {
      expect(const SensoryProfile(disableHighPiano: true).effectiveHighCutHz, 1200);
    });

    test('blacklist rule is honoured', () {
      const p = SensoryProfile(blacklist: ['Block frequencies > 1800 Hz']);
      expect(p.effectiveHighCutHz, 1800);
    });

    test('strictest of all sources wins', () {
      const p = SensoryProfile(
        highCutHz: 3000,
        disableHighPiano: true,
        blacklist: ['block frequencies > 900 hz', 'Disable water sounds'],
      );
      expect(p.effectiveHighCutHz, 900);
    });
  });
}
