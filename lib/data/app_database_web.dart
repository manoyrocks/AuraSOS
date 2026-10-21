import 'package:web/web.dart' as web;

import 'json_database.dart';
import 'local_database.dart';

/// `localStorage` as a [KeyValueStore]. Storage can be blocked (private mode, quota), in
/// which case reads return null and writes are dropped: the app still runs, it just forgets.
class _LocalStorageStore implements KeyValueStore {
  @override
  String? read(String key) {
    try {
      return web.window.localStorage.getItem(key);
    } catch (_) {
      return null;
    }
  }

  @override
  void write(String key, String value) {
    try {
      web.window.localStorage.setItem(key, value);
    } catch (_) {
      // Storage unavailable: keep running without persistence.
    }
  }
}

/// The app's database in the browser: JSON in `localStorage`, no SQLite or wasm download.
Future<LocalDatabase> openAppDatabase() => LocalDatabase.openJson(_LocalStorageStore());
