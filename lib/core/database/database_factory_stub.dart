import 'package:sqflite/sqflite.dart';

Future<Database> openAppDatabase(
  String path, {
  required int version,
  OnDatabaseConfigureFn? onConfigure,
  OnDatabaseCreateFn? onCreate,
  OnDatabaseVersionChangeFn? onUpgrade,
}) => openDatabase(
  path,
  version: version,
  onConfigure: onConfigure,
  onCreate: onCreate,
  onUpgrade: onUpgrade,
);

