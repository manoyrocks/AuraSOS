import 'dart:io';

import 'package:aurasync/core/audio/dsp_bridge.dart';
import 'package:aurasync/core/audio/sound_gate.dart';
import 'package:aurasync/core/models/sensory_state.dart';
import 'package:aurasync/data/json_database.dart';
import 'package:aurasync/data/local_database.dart';
import 'package:aurasync/data/sensory_profile_repository.dart';
import 'package:aurasync/ui/screens/session_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _GatedEngine extends PureDartDsp implements SoundGate {
  final ValueNotifier<bool> blocked = ValueNotifier<bool>(true);

  @override
  ValueListenable<bool> get soundBlocked => blocked;
}

void main() {
  const hint = 'Tap the screen to turn on sound';

  Future<SensoryProfileRepository> repo() async => SensoryProfileRepository(
      await LocalDatabase.openJson(MemoryKeyValueStore()));

  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  group('"turn on sound" hint', () {
    testWidgets(
        'shows while the platform is holding sound back, and goes away when it lets go',
        (tester) async {
      final engine = _GatedEngine();
      final r = (await tester.runAsync(repo))!;
      await tester.pumpWidget(MaterialApp(
        home: SessionScreen(
            preset: SessionPreset.isoDownRegulator,
            audio: engine,
            repository: r),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(hint), findsOneWidget);

      engine.blocked.value = false;
      await tester.pump();
      expect(find.text(hint), findsNothing);

      engine.blocked.value =
          true; // e.g. after a phone call suspends the audio session
      await tester.pump();
      expect(find.text(hint), findsOneWidget);
      await leave(tester);
    });

    testWidgets(
        'never appears for engines that cannot be blocked (native apps)',
        (tester) async {
      final r = (await tester.runAsync(repo))!;
      await tester.pumpWidget(MaterialApp(
        home: SessionScreen(
            preset: SessionPreset.calmStim,
            audio: PureDartDsp(),
            repository: r),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(hint), findsNothing);
      await leave(tester);
    });
  });

  /// The browser engine cannot run in the VM, so its unlock rules are pinned by inspecting the source.
  group('browser audio unlock rules', () {
    final src = File('lib/core/audio/web_audio_engine.dart').readAsStringSync();

    test('listens for every gesture type, including the release of a tap', () {
      for (final e in [
        'pointerdown',
        'pointerup',
        'touchstart',
        'touchend',
        'mousedown',
        'mouseup',
        'click',
        'keydown'
      ]) {
        expect(src, contains("'$e'"), reason: e);
      }
    });

    test(
        'listens on the window in the capture phase so Flutter cannot swallow the events',
        () {
      expect(src, contains('web.window.addEventListener'));
      expect(src, contains('capture: true'));
    });

    test('keeps listening so sound recovers after an interruption', () {
      // Listeners are only removed in dispose().
      final removals = RegExp(r'removeEventListener').allMatches(src).length;
      expect(removals, 1);
      expect(src.indexOf('removeEventListener'),
          greaterThan(src.indexOf('void dispose()')));
    });

    test(
        'asks iOS Safari for media playback so the silent switch does not mute it',
        () {
      expect(src, contains("'audioSession'"));
      expect(src, contains("'playback'"));
    });

    test('resumes whenever the context is not running and tracks its state',
        () {
      expect(src, contains('resume()'));
      expect(src, contains('onstatechange'));
      expect(src, contains('soundBlocked'));
    });
  });
}
