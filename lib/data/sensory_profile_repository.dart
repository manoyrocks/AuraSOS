import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/models/sensory_state.dart';
import 'local_database.dart';
import 'models.dart';

class SensoryProfileRepository {
  SensoryProfileRepository(this._database);

  final LocalDatabase _database;

  Database get _db => _database.db;

  /// The single active profile (lowest id); a default one is created if absent.
  Future<SensoryProfile> activeProfile() async {
    final List<Map<String, Object?>> rows =
        await _db.query('sensory_profiles', orderBy: 'id ASC', limit: 1);
    if (rows.isNotEmpty) return SensoryProfile.fromMap(rows.first);
    final SensoryProfile d = SensoryProfile.defaults();
    await _db.insert('sensory_profiles', d.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return d;
  }

  Future<void> saveProfile(SensoryProfile p) async {
    await _db.insert('sensory_profiles', p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> startSessionLog(SessionPreset p, DateTime at) {
    return _db.insert(
      'meltdown_logs',
      SessionLog(startedAt: at, durationSec: 0, preset: p).toMap(),
    );
  }

  Future<void> finishSessionLog(int id,
      {required int durationSec, required IsoPhase reachedPhase}) async {
    await _db.update(
      'meltdown_logs',
      <String, Object?>{
        'duration_sec': durationSec < 0 ? 0 : durationSec,
        'reached_phase': reachedPhase.name,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> rateSession(int id, EfficacyRating r) async {
    await _db.update(
      'meltdown_logs',
      <String, Object?>{'rating': r.name},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// Stores the caregiver's trigger tags and note for a session (replacing earlier ones).
  Future<void> annotateSession(int id,
      {required List<String> triggers, String? note}) async {
    final String trimmed = (note ?? '').trim();
    final List<String> clean = <String>{
      for (final String t in triggers)
        if (t.trim().isNotEmpty) t.trim(),
    }.toList();
    await _db.update(
      'meltdown_logs',
      <String, Object?>{
        'trigger_tags': jsonEncode(clean),
        'note': trimmed.isEmpty
            ? null
            : (trimmed.length > 500 ? trimmed.substring(0, 500) : trimmed),
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// Most recent first.
  Future<List<SessionLog>> sessions({int? limit}) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'meltdown_logs',
      orderBy: 'started_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(SessionLog.fromMap).toList();
  }
}
