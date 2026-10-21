import 'dart:io';

import 'package:aurasync/core/models/sensory_state.dart';
import 'package:aurasync/data/local_database.dart';
import 'package:aurasync/data/sensory_profile_repository.dart';
import 'package:aurasync/ui/screens/insights_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  final dbFiles = <File>[];
  tearDownAll(() {
    for (final f in dbFiles) {
      if (f.existsSync()) f.deleteSync();
    }
  });

  /// Every test gets its own database file; a shared in-memory database leaks rows between
  /// tests because the widget tests never close it.
  Future<SensoryProfileRepository> repoWith(
      Future<void> Function(SensoryProfileRepository) seed) async {
    final file = File('${Directory.systemTemp.path}/aura_insights_'
        '${DateTime.now().microsecondsSinceEpoch}_${dbFiles.length}.db');
    dbFiles.add(file);
    final db =
        await LocalDatabase.open(path: file.path, factory: databaseFactoryFfi);
    final repo = SensoryProfileRepository(db);
    await seed(repo);
    return repo;
  }

  testWidgets('empty history shows a gentle explanation', (tester) async {
    final repo = await tester.runAsync(() => repoWith((_) async {}));
    await tester
        .pumpWidget(MaterialApp(home: InsightsScreen(repository: repo!)));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(find.textContaining('No sessions yet'), findsOneWidget);
  });

  testWidgets('seeded history shows totals, best mode and recent sessions',
      (tester) async {
    final repo = await tester.runAsync(() => repoWith((r) async {
          for (var k = 0; k < 3; k++) {
            final id = await r.startSessionLog(SessionPreset.isoDownRegulator,
                DateTime.now().subtract(Duration(hours: k)));
            await r.finishSessionLog(id,
                durationSec: 600, reachedPhase: IsoPhase.baseline);
            await r.rateSession(id, EfficacyRating.effective);
          }
          final id =
              await r.startSessionLog(SessionPreset.calmStim, DateTime.now());
          await r.rateSession(id, EfficacyRating.escalated);
        }));
    await tester
        .pumpWidget(MaterialApp(home: InsightsScreen(repository: repo!)));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(find.text('4'), findsWidgets); // total and last-7-days tiles
    expect(find.text('sessions'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget); // 1 of 4 rated sessions escalated
    expect(find.textContaining('Most effective: Iso Down-Regulator'),
        findsOneWidget);
    expect(find.textContaining('100% of 3 rated sessions'), findsOneWidget);
    // The stacked rating bar must take up space (it once collapsed to zero height).
    final bar = find.descendant(
        of: find.byKey(const ValueKey('rating-bar-isoDownRegulator')),
        matching: find.byType(ColoredBox));
    expect(bar, findsWidgets);
    expect(tester.getSize(bar.first).height, 12);
    await tester.scrollUntilVisible(find.text('Recent sessions'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Recent sessions'), findsOneWidget);
    expect(find.text('Escalated'), findsWidgets);
  });

  testWidgets('tapping a session lets a caregiver tag triggers and add a note',
      (tester) async {
    late SensoryProfileRepository repo;
    await tester.runAsync(() async {
      repo = await repoWith((r) async {
        final id =
            await r.startSessionLog(SessionPreset.calmStim, DateTime.now());
        await r.rateSession(id, EfficacyRating.neutral);
      });
    });
    await tester
        .pumpWidget(MaterialApp(home: InsightsScreen(repository: repo)));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    await tester.scrollUntilVisible(find.byType(ListTile), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.text('What happened before?'), findsOneWidget);

    await tester.tap(find.text('Loud noise'));
    await tester.tap(find.text('Tired'));
    await tester.enterText(find.byType(TextField), 'Vacuum cleaner');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump();

    final saved = (await tester.runAsync(() => repo.sessions()))!.single;
    expect(saved.triggers, ['Loud noise', 'Tired']);
    expect(saved.note, 'Vacuum cleaner');
    expect(find.textContaining('Loud noise · 1'), findsOneWidget);
  });
}
