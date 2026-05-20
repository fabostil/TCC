import 'package:app_voz/database/app_database.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void configureRepositoryTestDatabase() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

Future<void> useRepositoryTestDatabase(String databaseName) async {
  await AppDatabase.instance.setDatabaseNameForTesting(databaseName);
}

Future<void> resetRepositoryTestDatabase(String databaseName) async {
  await AppDatabase.instance.close();
  final path = join(await getDatabasesPath(), databaseName);
  await deleteDatabase(path);
}
