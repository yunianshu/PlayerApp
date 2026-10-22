import '../data/database.dart';
import '../models/run_record.dart';
import 'app_data.dart';
import 'run_draft.dart';

class RunStorage {
  RunStorage._();

  static Future<void> save(RunRecord record, List<RunPoint> points) async {
    await RunDatabase.instance.insertRun(record, points);
    // If cleanup fails, retrying is safe: the database enforces session identity.
    await RunDraft.clear(sessionId: record.sessionKey);
    AppData.instance.bump();
  }

  static Future<void> discard(String sessionId) async {
    await RunDraft.clear(sessionId: sessionId);
    AppData.instance.bump();
  }
}
