import 'dart:io';

import 'package:aurasync/core/audio/dsp_bridge.dart';
import 'package:aurasync/core/models/sensory_state.dart';
import 'package:aurasync/data/json_database.dart';
import 'package:aurasync/data/local_database.dart';
import 'package:aurasync/data/models.dart';
import 'package:aurasync/data/sensory_profile_repository.dart';
import 'package:aurasync/data/voice_library.dart';
import 'package:aurasync/ui/launch_intent.dart';
import 'package:aurasync/ui/screens/home_sos_screen.dart';
import 'package:aurasync/ui/screens/session_screen.dart';
import 'package:aurasync/ui/widgets/about_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<SensoryProfileRepository> repo([SensoryProfile? p]) async {
    final r = SensoryProfileRepository(
        await LocalDatabase.openJson(MemoryKeyValueStore()));
    if (p != null) await r.saveProfile(p);
    return r;
  }

  Widget home(SensoryProfileRepository r, LaunchMode? mode) => MaterialApp(
        home: HomeSosScreen(
          audio: PureDartDsp(),
          repository: r,
          library: VoiceLibrary(root: Directory.systemTemp),
          launchMode: mode,
        ),
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 450)));
    // The profile read resolves, then the launch waits for a frame, then the route builds.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  group('home-screen shortcut launch', () {
    testWidgets('no mode shows the home screen and starts nothing',
        (tester) async {
      final r = (await tester.runAsync(repo))!;
      await tester.pumpWidget(home(r, null));
      await settle(tester);
      expect(find.text('SOS'), findsOneWidget);
      expect(find.byType(SessionScreen), findsNothing);
    });

    for (final c in <(LaunchMode, SessionPreset)>[
      (LaunchMode.sos, SessionPreset.isoDownRegulator),
      (LaunchMode.focus, SessionPreset.focusClassroom),
      (LaunchMode.calm, SessionPreset.calmStim),
      (LaunchMode.deep, SessionPreset.deepCrisisAnchor),
    ]) {
      testWidgets('?mode=${c.$1.name} starts ${c.$2.name} by itself',
          (tester) async {
        final r = (await tester.runAsync(repo))!;
        await tester.pumpWidget(home(r, c.$1));
        await settle(tester);
        final session =
            tester.widget<SessionScreen>(find.byType(SessionScreen));
        expect(session.preset, c.$2);
        await leave(tester);
      });
    }

    testWidgets("SOS shortcut honours the caregiver's chosen SOS mode",
        (tester) async {
      final r = (await tester.runAsync(() => repo(const SensoryProfile(
          preferredPreset: SessionPreset.deepCrisisAnchor))))!;
      await tester.pumpWidget(home(r, LaunchMode.sos));
      await settle(tester);
      expect(tester.widget<SessionScreen>(find.byType(SessionScreen)).preset,
          SessionPreset.deepCrisisAnchor);
      await leave(tester);
    });
  });

  group('About section', () {
    testWidgets('shows the name, version and an expandable privacy summary',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: AboutSection())),
      ));
      expect(find.textContaining('AuraSOS '), findsOneWidget);
      expect(find.textContaining('1.0.1'), findsOneWidget);
      expect(find.text('Privacy'), findsOneWidget);
      expect(find.textContaining('nothing anywhere'), findsNothing);
      await tester.tap(find.text('Privacy'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Everything stays on this device'),
          findsOneWidget);
      expect(find.textContaining('not a medical device'), findsOneWidget);
    });

    testWidgets('native builds show no offline row or reload button',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: AboutSection())),
      ));
      expect(find.textContaining('offline'), findsNothing);
      expect(find.textContaining('Reload app'), findsNothing);
    });
  });
}
