import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:runtrail/data/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test('C01 failed database open must allow another attempt', () async {
    final dir = await Directory.systemTemp.createTemp('runtrail-db-audit-');
    final blocker = File('${dir.path}/blocker');
    await blocker.writeAsString('force an invalid database parent');
    final db = RunDatabase(name: '${blocker.path}/audit.db');
    final failedAttempt = db.db;
    await expectLater(failedAttempt, throwsA(anything));
    await blocker.delete();
    await Directory(blocker.path).create();
    final fresh = RunDatabase(name: '${blocker.path}/healthy.db');
    final opened = await fresh.db;
    expect(opened.isOpen, isTrue);
    await fresh.close();
    expect(
      identical(failedAttempt, db.db),
      isFalse,
      reason: 'A failed attempt must not be returned forever after filesystem recovery',
    );
    expect(await db.listRuns(), isEmpty);
    await db.close();
  });
}
