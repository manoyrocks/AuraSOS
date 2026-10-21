import 'dart:io';

import 'package:aurasync/core/audio/dsp_bridge.dart';
import 'package:aurasync/core/models/sensory_state.dart';
import 'package:aurasync/data/json_database.dart';
import 'package:aurasync/data/local_database.dart';
import 'package:aurasync/data/models.dart';
import 'package:aurasync/data/sensory_profile_repository.dart';
import 'package:aurasync/data/voice_library.dart';
import 'package:aurasync/ui/mode_labels.dart';
import 'package:aurasync/ui/screens/home_sos_screen.dart';
import 'package:aurasync/ui/screens/session_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every mode and phase has a short plain-language name', () {
    for (final p in SessionPreset.values) {
      expect(modeLabel(p), isNotEmpty);
      expect(modeLabel(p).length, lessThanOrEqualTo(12),
          reason: 'must fit a small button');
    }
    expect(SessionPreset.values.map(modeLabel).toSet(),
        hasLength(SessionPreset.values.length),
        reason: 'two modes must never share a name');
    expect(IsoPhase.values.map(phaseHint).toSet(),
        hasLength(IsoPhase.values.length));
  });

  Future<SensoryProfileRepository> repo([SensoryProfile? profile]) async {
    final r = SensoryProfileRepository(
        await LocalDatabase.openJson(MemoryKeyValueStore()));
    if (profile != null) await r.saveProfile(profile);
    return r;
  }

  Widget home(SensoryProfileRepository r, PureDartDsp audio) => MaterialApp(
        home: HomeSosScreen(
          audio: audio,
          repository: r,
          library: VoiceLibrary(root: Directory.systemTemp),
        ),
      );

  testWidgets('home shows the SOS and mode names', (tester) async {
    final audio = PureDartDsp();
    final r = (await tester.runAsync(repo))!;
    await tester.pumpWidget(home(r, audio));
    await tester.pump();
    expect(find.text('SOS'), findsOneWidget);
    expect(find.text('Calm down'), findsOneWidget,
        reason: 'SOS sub-label (default mode)');
    expect(find.text('Focus'), findsOneWidget);
    expect(find.text('Play & calm'), findsOneWidget);
    expect(find.text('Deep calm'), findsOneWidget);
  });

  testWidgets('SOS names the mode the caregiver chose', (tester) async {
    final audio = PureDartDsp();
    final r = (await tester.runAsync(() => repo(const SensoryProfile(
        preferredPreset: SessionPreset.deepCrisisAnchor))))!;
    await tester.pumpWidget(home(r, audio));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(find.text('Deep calm'), findsNWidgets(2),
        reason: 'SOS sub-label and the Deep button');
    expect(find.text('Calm down'), findsNothing);
  });

  for (final size in const <(String, Size)>[
    ('small phone', Size(320, 568)),
    ('phone', Size(390, 844)),
    ('phone landscape', Size(812, 375)),
    ('tiny landscape', Size(568, 320)),
    ('tablet portrait', Size(820, 1180)),
    ('tablet landscape', Size(1180, 820)),
  ]) {
    testWidgets(
        'no overflow on ${size.$1} (${size.$2.width.toInt()}x${size.$2.height.toInt()})',
        (tester) async {
      tester.view.physicalSize = size.$2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final r = (await tester.runAsync(repo))!;
      await tester.pumpWidget(home(r, PureDartDsp()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      for (final t in ['SOS', 'Focus', 'Play & calm', 'Deep calm']) {
        expect(find.text(t), findsOneWidget,
            reason: '$t missing at ${size.$1}');
      }
    });
  }

  testWidgets('the session names its mode and stage, then fades away',
      (tester) async {
    final audio = PureDartDsp();
    final r = (await tester.runAsync(repo))!;
    await tester.pumpWidget(MaterialApp(
      home: SessionScreen(
        preset: SessionPreset.isoDownRegulator,
        audio: audio,
        repository: r,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Calm down · Matching'), findsOneWidget);

    double opacity() => tester
        .widget<AnimatedOpacity>(find.ancestor(
            of: find.text('Calm down · Matching'),
            matching: find.byType(AnimatedOpacity)))
        .opacity;
    expect(opacity(), 1);
    await tester.pump(const Duration(seconds: 9));
    expect(opacity(), 0,
        reason: 'the chip must not stay on the child\'s screen');

    // Replace the screen so the session timers are disposed.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
