import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'json_database.dart';
import 'models.dart';

/// On-device SQLite store. No network access of any kind.
class LocalDatabase {
  LocalDatabase._(this._db);

  static const int schemaVersion = 4;
  static const String fileName = 'aurasync.db';

  final Database _db;

  Database get db => _db;

  /// SQLite-free store for the browser PWA: tables live as JSON in [store]. A default profile
  /// is seeded on first use, exactly like a fresh SQLite install.
  static Future<LocalDatabase> openJson(KeyValueStore store) async {
    final JsonDatabase json = JsonDatabase(store);
    if ((await json.query('sensory_profiles', limit: 1)).isEmpty) {
      await json.insert('sensory_profiles', SensoryProfile.defaults().toMap());
    }
    return LocalDatabase._(json);
  }

  static Future<LocalDatabase> open(
      {String? path, DatabaseFactory? factory}) async {
    final DatabaseFactory f = factory ?? databaseFactory;
    final String resolved =
        path ?? p.join(await f.getDatabasesPath(), fileName);
    final Database database = await f.openDatabase(
      resolved,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (Database d) async {
          await d.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
    return LocalDatabase._(database);
  }

  static Future<void> _onCreate(Database d, int version) async {
    await _createV1(d);
    await _addVoiceColumns(d);
    await _addDisplayColumns(d);
    await _addNoteColumns(d);
    await d.insert('sensory_profiles', SensoryProfile.defaults().toMap());
  }

  static Future<void> _createV1(Database d) async {
    await d.execute('''
CREATE TABLE IF NOT EXISTS sensory_profiles (
  id INTEGER PRIMARY KEY,
  child_name TEXT NOT NULL,
  master_volume_cap REAL NOT NULL,
  brightness_cap REAL NOT NULL,
  high_cut_hz REAL NOT NULL,
  disable_water INTEGER NOT NULL,
  disable_high_piano INTEGER NOT NULL,
  blacklist TEXT NOT NULL,
  preferred_preset TEXT NOT NULL
)''');
    await d.execute('''
CREATE TABLE IF NOT EXISTS meltdown_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  started_at INTEGER NOT NULL,
  duration_sec INTEGER NOT NULL,
  preset TEXT NOT NULL,
  reached_phase TEXT,
  rating TEXT
)''');
    await d.execute(
        'CREATE INDEX IF NOT EXISTS idx_meltdown_logs_started_at ON meltdown_logs (started_at)');
    await d.execute(
        'CREATE INDEX IF NOT EXISTS idx_meltdown_logs_preset ON meltdown_logs (preset)');
  }

  static Future<void> _addVoiceColumns(Database d) async {
    await d.execute(
        'ALTER TABLE sensory_profiles ADD COLUMN voice_enabled INTEGER NOT NULL DEFAULT 0');
    await d.execute(
        'ALTER TABLE sensory_profiles ADD COLUMN voice_gain REAL NOT NULL DEFAULT 0.12');
    await d.execute(
        'ALTER TABLE sensory_profiles ADD COLUMN voice_interval_sec REAL NOT NULL DEFAULT 45');
  }

  static Future<void> _addDisplayColumns(Database d) async {
    await d.execute(
        "ALTER TABLE sensory_profiles ADD COLUMN visual_mode TEXT NOT NULL DEFAULT 'auto'");
    await d.execute(
        'ALTER TABLE sensory_profiles ADD COLUMN focus_minutes INTEGER NOT NULL DEFAULT 20');
  }

  static Future<void> _addNoteColumns(Database d) async {
    await d.execute('ALTER TABLE meltdown_logs ADD COLUMN note TEXT');
    await d.execute(
        "ALTER TABLE meltdown_logs ADD COLUMN trigger_tags TEXT NOT NULL DEFAULT '[]'");
  }

  /// Migrations are additive and run in order. Fresh installs go through [_onCreate]
  /// (v1 tables + voice columns), so [_addVoiceColumns] runs at most once per database.
  static Future<void> _onUpgrade(
      Database d, int oldVersion, int newVersion) async {
    if (oldVersion < 1) {
      await _createV1(d);
    }
    if (oldVersion < 2) {
      await _addVoiceColumns(d);
    }
    if (oldVersion < 3) {
      await _addDisplayColumns(d);
    }
    if (oldVersion < 4) {
      await _addNoteColumns(d);
    }
  }

  Future<void> close() => _db.close();
}
