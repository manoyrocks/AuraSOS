import 'package:aurasync/ui/widgets/aura_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host({bool reducedMotion = false, double size = 96}) => MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: MaterialApp(
            home: Scaffold(body: Center(child: AuraLoader(size: size)))),
      );

  group('breathing curve', () {
    test('rests at the ends, peaks after 4 s, and takes 6 s to settle', () {
      expect(AuraLoaderProbe.breath(0), closeTo(0, 1e-9));
      expect(AuraLoaderProbe.breath(0.4), closeTo(1, 1e-9));
      expect(AuraLoaderProbe.breath(1.0), closeTo(0, 1e-9));
      for (var t = 0.0; t < 0.4; t += 0.01) {
        expect(AuraLoaderProbe.breath(t + 0.01),
            greaterThanOrEqualTo(AuraLoaderProbe.breath(t)),
            reason: 'inhale at $t');
      }
      for (var t = 0.4; t < 1.0; t += 0.01) {
        expect(AuraLoaderProbe.breath(t + 0.01),
            lessThanOrEqualTo(AuraLoaderProbe.breath(t) + 1e-9),
            reason: 'exhale at $t');
      }
    });
  });

  group('AuraLoader', () {
    testWidgets('animates, is announced as Loading, and cleans up its ticker',
        (tester) async {
      await tester.pumpWidget(host());
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      final before = tester.getSize(find.byType(AuraLoader));
      expect(before, const Size(96, 96));
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
      await tester
          .pumpWidget(const SizedBox()); // disposing must not leak the ticker
      expect(tester.takeException(), isNull);
    });

    testWidgets('stays still when the device asks for reduced motion',
        (tester) async {
      await tester.pumpWidget(host(reducedMotion: true));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('moves otherwise', (tester) async {
      await tester.pumpWidget(host());
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('scales to any size', (tester) async {
      await tester.pumpWidget(host(size: 40));
      expect(tester.getSize(find.byType(AuraLoader)), const Size(40, 40));
      await tester.pumpWidget(const SizedBox());
    });
  });
}
