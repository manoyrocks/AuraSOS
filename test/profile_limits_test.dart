import 'package:aurasync/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('default maximum volume', () {
    test('is 80% for a new profile', () {
      expect(const SensoryProfile().masterVolumeCap, 0.8);
      expect(SensoryProfile.defaults().masterVolumeCap, 0.8);
    });

    test('is 80% when a saved record has no volume value', () {
      final m = SensoryProfile.defaults().toMap()..remove('master_volume_cap');
      expect(SensoryProfile.fromMap(m).masterVolumeCap, 0.8);
    });

    test('a value the caregiver saved is kept, not overwritten by the default',
        () {
      final m = const SensoryProfile(masterVolumeCap: 0.45).toMap();
      expect(SensoryProfile.fromMap(m).masterVolumeCap, 0.45);
    });
  });

  group('SensoryProfile.effectiveHighCutHz', () {
    test('no limits means no cut', () {
      expect(const SensoryProfile().effectiveHighCutHz, 0);
    });

    test('explicit cut is used on its own', () {
      expect(const SensoryProfile(highCutHz: 2500).effectiveHighCutHz, 2500);
    });

    test('soften-high-tones switch caps at 1200 Hz', () {
      expect(const SensoryProfile(disableHighPiano: true).effectiveHighCutHz,
          1200);
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
