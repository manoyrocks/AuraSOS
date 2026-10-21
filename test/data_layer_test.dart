import 'dart:io';

import 'package:aurasync/core/models/sensory_state.dart';
import 'package:aurasync/data/clinical_report_exporter.dart';
import 'package:aurasync/data/local_database.dart';
import 'package:aurasync/data/models.dart';
import 'package:aurasync/data/sensory_profile_repository.dart';
import 'package:aurasync/ui/screens/session_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late LocalDatabase db;
  late SensoryProfileRepository repo;

  setUp(() async {
    db = await LocalDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    repo = SensoryProfileRepository(db);
  });

  tearDown(() async => db.close());

  group('profile', () {
    test('a default profile is seeded on first open', () async {
      final p = await repo.activeProfile();
      expect(p.masterVolumeCap, SensoryProfile.defaults().masterVolumeCap);
      expect(p.blacklist, isEmpty);
    });

    test('saved profile round-trips including blacklist and preset', () async {
      final saved = (await repo.activeProfile()).copyWith(
        childName: 'Sam, "Sammy"',
        masterVolumeCap: 0.35,
        brightnessCap: 0.5,
        highCutHz: 2200,
        disableWater: true,
        disableHighPiano: true,
        blacklist: ['Block frequencies > 1800 Hz', 'Disable water sounds'],
        preferredPreset: SessionPreset.deepCrisisAnchor,
      );
      await repo.saveProfile(saved);
      final read = await repo.activeProfile();
      expect(read.childName, 'Sam, "Sammy"');
      expect(read.masterVolumeCap, 0.35);
      expect(read.brightnessCap, 0.5);
      expect(read.highCutHz, 2200);
      expect(read.disableWater, isTrue);
      expect(read.disableHighPiano, isTrue);
      expect(read.blacklist,
          ['Block frequencies > 1800 Hz', 'Disable water sounds']);
      expect(read.preferredPreset, SessionPreset.deepCrisisAnchor);
      expect(read.effectiveHighCutHz, 1200);
    });
  });

  group('session log', () {
    test('start, finish and rate update one row', () async {
      final at = DateTime(2026, 10, 21, 14, 30);
      final id = await repo.startSessionLog(SessionPreset.isoDownRegulator, at);
      await repo.finishSessionLog(id,
          durationSec: 540, reachedPhase: IsoPhase.thinning);
      await repo.rateSession(id, EfficacyRating.effective);

      final logs = await repo.sessions();
      expect(logs, hasLength(1));
      expect(logs.single.id, id);
      expect(logs.single.startedAt, at);
      expect(logs.single.durationSec, 540);
      expect(logs.single.preset, SessionPreset.isoDownRegulator);
      expect(logs.single.reachedPhase, IsoPhase.thinning);
      expect(logs.single.rating, EfficacyRating.effective);
    });

    test('unrated sessions stay unrated and newest comes first', () async {
      await repo.startSessionLog(SessionPreset.calmStim, DateTime(2026, 10, 1));
      await repo.startSessionLog(
          SessionPreset.focusClassroom, DateTime(2026, 10, 2));
      final logs = await repo.sessions();
      expect(logs.map((l) => l.preset),
          [SessionPreset.focusClassroom, SessionPreset.calmStim]);
      expect(logs.every((l) => l.rating == null), isTrue);
      expect(await repo.sessions(limit: 1), hasLength(1));
    });
  });

  group('clinical report', () {
    Future<void> seed() async {
      final a = await repo.startSessionLog(
          SessionPreset.isoDownRegulator, DateTime(2026, 10, 3, 8, 0));
      await repo.finishSessionLog(a,
          durationSec: 600, reachedPhase: IsoPhase.baseline);
      await repo.rateSession(a, EfficacyRating.effective);
      final b = await repo.startSessionLog(
          SessionPreset.isoDownRegulator, DateTime(2026, 10, 4, 22, 0));
      await repo.finishSessionLog(b,
          durationSec: 120, reachedPhase: IsoPhase.match);
      await repo.rateSession(b, EfficacyRating.escalated);
      await repo.startSessionLog(
          SessionPreset.calmStim, DateTime(2026, 10, 5, 13, 0));
    }

    test('CSV has a header, chronological rows and valid quoting', () async {
      await seed();
      final csv = await ClinicalReportExporter(repo).toCsv();
      final lines = csv.trim().split('\r\n');
      expect(lines.first, startsWith('id,started_at'));
      expect(lines, hasLength(4));
      expect(lines[1], contains('2026-10-03'));
      expect(lines[3], contains('2026-10-05'));
      expect(lines[3], contains('unrated'));
    });

    test('Markdown summarises efficacy per preset and includes the disclaimer',
        () async {
      await seed();
      await repo.saveProfile((await repo.activeProfile())
          .copyWith(blacklist: ['Block frequencies > 1800 Hz | test']));
      final md = await ClinicalReportExporter(repo).toMarkdown();
      expect(md, contains('Block frequencies > 1800 Hz'));
      expect(md, contains('50%')); // 1 of 2 rated iso sessions was effective
      expect(md.toLowerCase(), contains('not medical advice'));
    });

    test('empty history still produces a valid report', () async {
      final exporter = ClinicalReportExporter(repo);
      expect((await exporter.toCsv()).trim().split('\r\n'), hasLength(1));
      expect(await exporter.toMarkdown(), isNotEmpty);
    });

    test('writeReports writes both files to disk', () async {
      await seed();
      final dir = await Directory.systemTemp.createTemp('aurasos_report_');
      addTearDown(() => dir.delete(recursive: true));
      final md = await ClinicalReportExporter(repo).writeReports(dir);
      expect(md.path, endsWith('.md'));
      expect(await md.exists(), isTrue);
      expect(await File('${dir.path}/aurasos_report.csv').exists(), isTrue);
    });
  });

  group('schema v2 (familiar voice)', () {
    test('voice fields default off and round-trip', () async {
      final p = await repo.activeProfile();
      expect(p.voiceEnabled, isFalse);
      expect(p.voiceGain, 0.12);
      expect(p.voiceIntervalSec, 45);
      await repo.saveProfile(
          p.copyWith(voiceEnabled: true, voiceGain: 0.2, voiceIntervalSec: 90));
      final read = await repo.activeProfile();
      expect(read.voiceEnabled, isTrue);
      expect(read.voiceGain, 0.2);
      expect(read.voiceIntervalSec, 90);
    });

    test('maps without voice keys still decode with defaults', () {
      final m = SensoryProfile.defaults().toMap()
        ..remove('voice_enabled')
        ..remove('voice_gain')
        ..remove('voice_interval_sec');
      final p = SensoryProfile.fromMap(m);
      expect(p.voiceEnabled, isFalse);
      expect(p.voiceGain, 0.12);
      expect(p.voiceIntervalSec, 45);
    });

    test('v1 database migrates and keeps its profile', () async {
      final dir = await Directory.systemTemp.createTemp('aura_v1');
      final path = '${dir.path}/old.db';
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (d, _) async {
            await d.execute('''CREATE TABLE sensory_profiles (
  id INTEGER PRIMARY KEY, child_name TEXT NOT NULL, master_volume_cap REAL NOT NULL,
  brightness_cap REAL NOT NULL, high_cut_hz REAL NOT NULL, disable_water INTEGER NOT NULL,
  disable_high_piano INTEGER NOT NULL, blacklist TEXT NOT NULL, preferred_preset TEXT NOT NULL)''');
            await d.execute('''CREATE TABLE meltdown_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT, started_at INTEGER NOT NULL, duration_sec INTEGER NOT NULL,
  preset TEXT NOT NULL, reached_phase TEXT, rating TEXT)''');
            await d.insert('sensory_profiles', {
              'id': 1,
              'child_name': 'Mia',
              'master_volume_cap': 0.4,
              'brightness_cap': 0.5,
              'high_cut_hz': 1500.0,
              'disable_water': 1,
              'disable_high_piano': 0,
              'blacklist': '["Block frequencies > 1800 Hz"]',
              'preferred_preset': 'deepCrisisAnchor',
            });
            await d.insert('meltdown_logs', {
              'started_at': 1000,
              'duration_sec': 60,
              'preset': 'isoDownRegulator',
            });
          },
        ),
      );
      await old.close();

      final migrated =
          await LocalDatabase.open(path: path, factory: databaseFactoryFfi);
      final r = SensoryProfileRepository(migrated);
      final p = await r.activeProfile();
      expect(p.childName, 'Mia');
      expect(p.masterVolumeCap, 0.4);
      expect(p.disableWater, isTrue);
      expect(p.preferredPreset, SessionPreset.deepCrisisAnchor);
      expect(p.voiceEnabled, isFalse);
      expect(p.voiceGain, 0.12);
      expect(p.voiceIntervalSec, 45);
      expect(await migrated.db.query('meltdown_logs'), hasLength(1));
      await r.saveProfile(p.copyWith(voiceEnabled: true));
      expect((await r.activeProfile()).voiceEnabled, isTrue);
      await migrated.close();
      await dir.delete(recursive: true);
    });
  });

  group('schema v3 (visuals and focus timer)', () {
    test('defaults, round-trip and clamping', () async {
      final p = await repo.activeProfile();
      expect(p.visualMode, VisualMode.auto);
      expect(p.focusMinutes, 20);
      await repo.saveProfile(
          p.copyWith(visualMode: VisualMode.blackScreen, focusMinutes: 35));
      final read = await repo.activeProfile();
      expect(read.visualMode, VisualMode.blackScreen);
      expect(read.focusMinutes, 35);
      expect(
          SensoryProfile.fromMap({...read.toMap(), 'focus_minutes': 999})
              .focusMinutes,
          60);
      expect(
          SensoryProfile.fromMap({...read.toMap(), 'focus_minutes': 0})
              .focusMinutes,
          5);
      expect(
          SensoryProfile.fromMap({...read.toMap(), 'visual_mode': 'nonsense'})
              .visualMode,
          VisualMode.auto);
    });

    test('maps without the new keys decode with defaults', () {
      final m = SensoryProfile.defaults().toMap()
        ..remove('visual_mode')
        ..remove('focus_minutes');
      final p = SensoryProfile.fromMap(m);
      expect(p.visualMode, VisualMode.auto);
      expect(p.focusMinutes, 20);
    });

    test('a v2 database migrates and keeps its voice settings', () async {
      final dir = await Directory.systemTemp.createTemp('aura_v2');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/v2.db';
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (d, _) async {
            await d.execute('''CREATE TABLE sensory_profiles (
  id INTEGER PRIMARY KEY, child_name TEXT NOT NULL, master_volume_cap REAL NOT NULL,
  brightness_cap REAL NOT NULL, high_cut_hz REAL NOT NULL, disable_water INTEGER NOT NULL,
  disable_high_piano INTEGER NOT NULL, blacklist TEXT NOT NULL, preferred_preset TEXT NOT NULL,
  voice_enabled INTEGER NOT NULL DEFAULT 0, voice_gain REAL NOT NULL DEFAULT 0.12,
  voice_interval_sec REAL NOT NULL DEFAULT 45)''');
            await d.execute('''CREATE TABLE meltdown_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT, started_at INTEGER NOT NULL, duration_sec INTEGER NOT NULL,
  preset TEXT NOT NULL, reached_phase TEXT, rating TEXT)''');
            await d.insert('sensory_profiles', {
              'id': 1,
              'child_name': 'Leo',
              'master_volume_cap': 0.5,
              'brightness_cap': 0.6,
              'high_cut_hz': 0.0,
              'disable_water': 0,
              'disable_high_piano': 0,
              'blacklist': '[]',
              'preferred_preset': 'isoDownRegulator',
              'voice_enabled': 1,
              'voice_gain': 0.2,
              'voice_interval_sec': 60.0,
            });
          },
        ),
      );
      await old.close();

      final migrated =
          await LocalDatabase.open(path: path, factory: databaseFactoryFfi);
      final p = await SensoryProfileRepository(migrated).activeProfile();
      expect(p.childName, 'Leo');
      expect(p.voiceEnabled, isTrue);
      expect(p.voiceGain, 0.2);
      expect(p.visualMode, VisualMode.auto);
      expect(p.focusMinutes, 20);
      await migrated.close();
    });
  });

  group('SessionScreen.visualFor', () {
    test('auto keeps each preset\'s own shader', () {
      for (final preset in SessionPreset.values) {
        expect(SessionScreen.visualFor(preset, VisualMode.auto),
            SessionScreen.shaderFor(preset));
      }
    });

    test('explicit modes override the preset and black screen means no shader',
        () {
      expect(
          SessionScreen.visualFor(
              SessionPreset.focusClassroom, VisualMode.tunnel),
          ShaderKind.tunnel);
      expect(
          SessionScreen.visualFor(
              SessionPreset.deepCrisisAnchor, VisualMode.breathingOrb),
          ShaderKind.breathingOrb);
      for (final preset in SessionPreset.values) {
        expect(SessionScreen.visualFor(preset, VisualMode.blackScreen), isNull);
      }
    });
  });

  group('schema v4 (session notes and triggers)', () {
    test('annotate stores trimmed, de-duplicated triggers and a capped note',
        () async {
      final id = await repo.startSessionLog(
          SessionPreset.calmStim, DateTime(2026, 10, 2, 9));
      await repo.annotateSession(id,
          triggers: ['Loud noise', ' Loud noise ', '', 'Tired'],
          note: '  vacuum started  ');
      var log = (await repo.sessions()).single;
      expect(log.triggers, ['Loud noise', 'Tired']);
      expect(log.note, 'vacuum started');

      await repo.annotateSession(id, triggers: const [], note: 'x' * 900);
      log = (await repo.sessions()).single;
      expect(log.triggers, isEmpty);
      expect(log.note, hasLength(500));

      await repo.annotateSession(id, triggers: const [], note: '   ');
      expect((await repo.sessions()).single.note, isNull);
    });

    test('annotating does not disturb the rating or duration', () async {
      final id = await repo.startSessionLog(
          SessionPreset.isoDownRegulator, DateTime(2026, 10, 2));
      await repo.finishSessionLog(id,
          durationSec: 480, reachedPhase: IsoPhase.thinning);
      await repo.rateSession(id, EfficacyRating.neutral);
      await repo.annotateSession(id, triggers: ['Transition']);
      final log = (await repo.sessions()).single;
      expect(log.rating, EfficacyRating.neutral);
      expect(log.durationSec, 480);
      expect(log.reachedPhase, IsoPhase.thinning);
      expect(log.triggers, ['Transition']);
    });

    test('damaged or missing tag cells read as no tags', () {
      final base = SessionLog(
              startedAt: DateTime(2026),
              durationSec: 1,
              preset: SessionPreset.calmStim)
          .toMap();
      expect(SessionLog.fromMap({...base, 'trigger_tags': 'not json'}).triggers,
          isEmpty);
      expect(SessionLog.fromMap({...base, 'trigger_tags': '{"a":1}'}).triggers,
          isEmpty);
      expect(
          SessionLog.fromMap({...base, 'trigger_tags': '["A", 3, " "]'})
              .triggers,
          ['A']);
      expect(
          (Map.of(base)
                ..remove('trigger_tags')
                ..remove('note'))
              .isNotEmpty,
          isTrue);
      expect(
          SessionLog.fromMap(Map.of(base)
                ..remove('trigger_tags')
                ..remove('note'))
              .triggers,
          isEmpty);
    });

    test('CSV and Markdown carry triggers and notes, escaped', () async {
      final id = await repo.startSessionLog(
          SessionPreset.isoDownRegulator, DateTime(2026, 10, 3, 8));
      await repo.rateSession(id, EfficacyRating.effective);
      await repo.annotateSession(id,
          triggers: ['Loud noise', 'Crowd / busy place'],
          note: 'Bus, "very" loud | stop');
      final ex = ClinicalReportExporter(repo);

      final csv = await ex.toCsv();
      expect(csv.split('\r\n').first, endsWith('rating,triggers,note'));
      expect(csv, contains('effective,Loud noise; Crowd / busy place,"Bus'));
      expect(csv, contains('"Bus, ""very"" loud | stop"'));

      final md = await ex.toMarkdown();
      expect(md, contains('## Reported Triggers'));
      expect(md, contains('| Loud noise | 1 |'));
      expect(md, contains(r'Bus, "very" loud \| stop'));
    });

    test('a report with no triggers has no triggers section', () async {
      await repo.startSessionLog(SessionPreset.calmStim, DateTime(2026, 10, 3));
      expect(await ClinicalReportExporter(repo).toMarkdown(),
          isNot(contains('Reported Triggers')));
    });

    test('a v3 database migrates and keeps its sessions', () async {
      final dir = await Directory.systemTemp.createTemp('aura_v3');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/v3.db';
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (d, _) async {
            await d.execute('''CREATE TABLE sensory_profiles (
  id INTEGER PRIMARY KEY, child_name TEXT NOT NULL, master_volume_cap REAL NOT NULL,
  brightness_cap REAL NOT NULL, high_cut_hz REAL NOT NULL, disable_water INTEGER NOT NULL,
  disable_high_piano INTEGER NOT NULL, blacklist TEXT NOT NULL, preferred_preset TEXT NOT NULL,
  voice_enabled INTEGER NOT NULL DEFAULT 0, voice_gain REAL NOT NULL DEFAULT 0.12,
  voice_interval_sec REAL NOT NULL DEFAULT 45, visual_mode TEXT NOT NULL DEFAULT 'auto',
  focus_minutes INTEGER NOT NULL DEFAULT 20)''');
            await d.execute('''CREATE TABLE meltdown_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT, started_at INTEGER NOT NULL, duration_sec INTEGER NOT NULL,
  preset TEXT NOT NULL, reached_phase TEXT, rating TEXT)''');
            await d.insert('meltdown_logs', {
              'started_at': 5000,
              'duration_sec': 300,
              'preset': 'calmStim',
              'rating': 'effective',
            });
          },
        ),
      );
      await old.close();

      final migrated =
          await LocalDatabase.open(path: path, factory: databaseFactoryFfi);
      final r = SensoryProfileRepository(migrated);
      final log = (await r.sessions()).single;
      expect(log.rating, EfficacyRating.effective);
      expect(log.triggers, isEmpty);
      expect(log.note, isNull);
      await r.annotateSession(log.id!, triggers: ['Hungry']);
      expect((await r.sessions()).single.triggers, ['Hungry']);
      await migrated.close();
    });
  });
}
