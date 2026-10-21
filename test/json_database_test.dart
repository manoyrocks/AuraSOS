import 'package:aurasync/core/models/sensory_state.dart';
import 'package:aurasync/data/clinical_report_exporter.dart';
import 'package:aurasync/data/json_database.dart';
import 'package:aurasync/data/local_database.dart';
import 'package:aurasync/data/models.dart';
import 'package:aurasync/data/sensory_profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// The browser build stores everything as JSON in localStorage. These tests run the real
/// repository and exporter over that backend so the PWA behaves like the SQLite app.
void main() {
  late MemoryKeyValueStore store;
  late LocalDatabase db;
  late SensoryProfileRepository repo;

  setUp(() async {
    store = MemoryKeyValueStore();
    db = await LocalDatabase.openJson(store);
    repo = SensoryProfileRepository(db);
  });

  test('a default profile is seeded on first open', () async {
    final p = await repo.activeProfile();
    expect(p.masterVolumeCap, SensoryProfile.defaults().masterVolumeCap);
    expect(store.read('aurasync.db'), isNotNull);
  });

  test('profile round-trips and replaces by id', () async {
    final p = await repo.activeProfile();
    await repo.saveProfile(p.copyWith(
      childName: 'Ana',
      masterVolumeCap: 0.3,
      blacklist: ['Block frequencies > 1500 Hz'],
      visualMode: VisualMode.blackScreen,
      focusMinutes: 40,
      voiceEnabled: true,
    ));
    final read = await repo.activeProfile();
    expect(read.childName, 'Ana');
    expect(read.masterVolumeCap, 0.3);
    expect(read.effectiveHighCutHz, 1500);
    expect(read.visualMode, VisualMode.blackScreen);
    expect(read.focusMinutes, 40);
    expect(read.voiceEnabled, isTrue);
    // Still a single profile row.
    expect(await db.db.query('sensory_profiles'), hasLength(1));
  });

  test('session lifecycle: start, finish, rate, annotate; newest first',
      () async {
    final a = await repo.startSessionLog(
        SessionPreset.calmStim, DateTime(2026, 10, 1, 9));
    final b = await repo.startSessionLog(
        SessionPreset.isoDownRegulator, DateTime(2026, 10, 2, 22));
    expect(b, a + 1, reason: 'ids auto-increment');
    await repo.finishSessionLog(b,
        durationSec: 540, reachedPhase: IsoPhase.thinning);
    await repo.rateSession(b, EfficacyRating.effective);
    await repo.annotateSession(b,
        triggers: ['Loud noise', 'Tired'], note: '  bus ride ');

    final logs = await repo.sessions();
    expect(logs.map((l) => l.id), [b, a]);
    expect(logs.first.durationSec, 540);
    expect(logs.first.reachedPhase, IsoPhase.thinning);
    expect(logs.first.rating, EfficacyRating.effective);
    expect(logs.first.triggers, ['Loud noise', 'Tired']);
    expect(logs.first.note, 'bus ride');
    expect(logs.last.rating, isNull);
    expect(await repo.sessions(limit: 1), hasLength(1));
  });

  test('data survives a reload from the same store', () async {
    final id = await repo.startSessionLog(
        SessionPreset.deepCrisisAnchor, DateTime(2026, 10, 3));
    await repo.rateSession(id, EfficacyRating.neutral);
    await repo
        .saveProfile((await repo.activeProfile()).copyWith(childName: 'Kept'));

    final reopened =
        SensoryProfileRepository(await LocalDatabase.openJson(store));
    expect((await reopened.activeProfile()).childName, 'Kept');
    final logs = await reopened.sessions();
    expect(logs.single.preset, SessionPreset.deepCrisisAnchor);
    expect(logs.single.rating, EfficacyRating.neutral);
    // New ids continue after the stored ones.
    expect(
        await reopened.startSessionLog(
            SessionPreset.calmStim, DateTime(2026, 10, 4)),
        id + 1);
  });

  test('a corrupted or foreign store falls back to a fresh database', () async {
    for (final bad in ['not json', '[1,2,3]', '{"sensory_profiles": 5}', '']) {
      final s = MemoryKeyValueStore()..write('aurasync.db', bad);
      final r = SensoryProfileRepository(await LocalDatabase.openJson(s));
      expect((await r.activeProfile()).childName, 'Child',
          reason: 'store: "$bad"');
      expect(await r.sessions(), isEmpty);
    }
  });

  test('unsupported queries fail loudly instead of returning wrong rows',
      () async {
    final json = JsonDatabase(MemoryKeyValueStore());
    expect(() => json.query('meltdown_logs', where: "preset = 'calmStim'"),
        throwsUnsupportedError);
    expect(
        () => json.update('meltdown_logs', {'a': 1},
            where: 'id > ?', whereArgs: [1]),
        throwsUnsupportedError);
    expect(() => json.rawQuery('SELECT 1'), throwsUnsupportedError);
  });

  test('inserting a duplicate id without replace is rejected', () async {
    final json = JsonDatabase(MemoryKeyValueStore());
    await json.insert('t', {'id': 1, 'v': 'a'});
    expect(() => json.insert('t', {'id': 1, 'v': 'b'}), throwsStateError);
    expect((await json.query('t')).single['v'], 'a');
  });

  test('the clinical report works over the browser backend', () async {
    final id = await repo.startSessionLog(
        SessionPreset.isoDownRegulator, DateTime(2026, 10, 5, 8));
    await repo.rateSession(id, EfficacyRating.effective);
    await repo.annotateSession(id, triggers: ['Transition']);
    final ex = ClinicalReportExporter(repo);
    final csv = await ex.toCsv();
    expect(csv.split('\r\n').first, endsWith('rating,triggers,note'));
    expect(csv, contains('effective,Transition,'));
    final md = await ex.toMarkdown();
    expect(md, contains('## Reported Triggers'));
    expect(md.toLowerCase(), contains('not medical advice'));
  });
}
