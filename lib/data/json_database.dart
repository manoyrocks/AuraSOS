import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Where a [JsonDatabase] keeps its serialised tables. Web uses `localStorage`; tests use
/// [MemoryKeyValueStore].
abstract class KeyValueStore {
  String? read(String key);
  void write(String key, String value);
}

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  String? read(String key) => values[key];

  @override
  void write(String key, String value) => values[key] = value;
}

/// Minimal [Database] for platforms without SQLite (the browser PWA). It supports exactly
/// what `SensoryProfileRepository` uses: `query` (orderBy / limit), `insert` (with replace)
/// and `update` filtered by `id = ?`. Anything else throws [UnsupportedError] rather than
/// silently misbehaving. Data persists as one JSON document in a [KeyValueStore].
class JsonDatabase implements Database {
  JsonDatabase(this._store, {this.storageKey = 'aurasync.db'}) {
    _load();
  }

  final KeyValueStore _store;
  final String storageKey;
  final Map<String, List<Map<String, Object?>>> _tables = <String, List<Map<String, Object?>>>{};
  bool _open = true;

  @override
  bool get isOpen => _open;

  @override
  Future<void> close() async => _open = false;

  void _load() {
    final String? raw = _store.read(storageKey);
    if (raw == null) return;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final MapEntry<dynamic, dynamic> e in decoded.entries) {
        final Object? rows = e.value;
        if (e.key is String && rows is List) {
          _tables[e.key as String] = <Map<String, Object?>>[
            for (final Object? r in rows)
              if (r is Map) <String, Object?>{for (final MapEntry<dynamic, dynamic> c in r.entries) '${c.key}': c.value as Object?},
          ];
        }
      }
    } on FormatException {
      _tables.clear(); // a damaged document starts a fresh database
    }
  }

  void _persist() => _store.write(storageKey, jsonEncode(_tables));

  List<Map<String, Object?>> _rows(String table) =>
      _tables.putIfAbsent(table, () => <Map<String, Object?>>[]);

  bool Function(Map<String, Object?>) _filter(String? where, List<Object?>? args) {
    if (where == null) return (Map<String, Object?> _) => true;
    if (where.trim() != 'id = ?' || args == null || args.length != 1) {
      throw UnsupportedError('JsonDatabase only supports "id = ?" (got "$where")');
    }
    final Object? wanted = args.first;
    return (Map<String, Object?> r) => r['id'] == wanted;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final bool Function(Map<String, Object?>) keep = _filter(where, whereArgs);
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[
      for (final Map<String, Object?> r in _rows(table))
        if (keep(r)) <String, Object?>{...r},
    ];
    if (orderBy != null) {
      final List<(String, bool)> keys = <(String, bool)>[
        for (final String part in orderBy.split(','))
          (part.trim().split(RegExp(r'\s+')).first, part.trim().toUpperCase().endsWith(' DESC')),
      ];
      rows.sort((Map<String, Object?> a, Map<String, Object?> b) {
        for (final (String, bool) k in keys) {
          final int c = _compare(a[k.$1], b[k.$1]);
          if (c != 0) return k.$2 ? -c : c;
        }
        return 0;
      });
    }
    final int skip = offset ?? 0;
    final List<Map<String, Object?>> windowed = skip > 0 ? rows.skip(skip).toList() : rows;
    return limit == null ? windowed : windowed.take(limit).toList();
  }

  static int _compare(Object? a, Object? b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (a is num && b is num) return a.compareTo(b);
    return '$a'.compareTo('$b');
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final List<Map<String, Object?>> rows = _rows(table);
    final Map<String, Object?> row = <String, Object?>{...values};
    int id;
    final Object? given = row['id'];
    if (given is int) {
      id = given;
      final int at = rows.indexWhere((Map<String, Object?> r) => r['id'] == id);
      if (at >= 0) {
        if (conflictAlgorithm != ConflictAlgorithm.replace) {
          throw StateError('UNIQUE constraint failed: $table.id');
        }
        rows[at] = row;
        _persist();
        return id;
      }
    } else {
      id = rows.fold<int>(0, (int m, Map<String, Object?> r) => (r['id'] as int? ?? 0) > m ? r['id'] as int : m) + 1;
      row['id'] = id;
    }
    rows.add(row);
    _persist();
    return id;
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final bool Function(Map<String, Object?>) keep = _filter(where, whereArgs);
    var changed = 0;
    for (final Map<String, Object?> r in _rows(table)) {
      if (keep(r)) {
        r.addAll(values);
        changed++;
      }
    }
    if (changed > 0) _persist();
    return changed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
      'JsonDatabase does not implement ${invocation.memberName}');
}
