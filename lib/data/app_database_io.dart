import 'local_database.dart';

/// The app's database: SQLite on mobile / desktop.
Future<LocalDatabase> openAppDatabase() => LocalDatabase.open();
