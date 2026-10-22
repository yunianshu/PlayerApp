import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/run_record.dart';

/// Recoverable snapshot; all file operations share one ordered queue.
class RunDraft {
  final DateTime start;
  final DateTime? end;
  final String? sessionId;
  final int elapsedMs;
  final double distanceM;
  final double climbM;
  final List<RunPoint> points;

  const RunDraft({
    required this.start,
    this.end,
    this.sessionId,
    required this.elapsedMs,
    required this.distanceM,
    required this.climbM,
    required this.points,
  });

  String get sessionKey => sessionId ?? 'run-${start.microsecondsSinceEpoch}';
  bool get recoverable => distanceM >= 20 && points.length >= 2;
  RunRecord get record => RunRecord(
    sessionId: sessionKey,
    start: start,
    end: end ?? points.last.time,
    distanceM: distanceM,
    durationS: elapsedMs ~/ 1000,
    calories: (distanceM / 1000 * 65 * 1.036).round(),
    climbM: climbM,
  );

  static const _fileName = 'runtrail_draft.json';
  static Future<void> _pending = Future.value();

  static Future<T> _ordered<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    // A failed write must not prevent a later retry or delete.
    _pending = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace stack) {},
    );
    return result;
  }

  Map<String, Object?> toMap() => {
    'session_id': sessionKey,
    'start_ms': start.millisecondsSinceEpoch,
    'end_ms': end?.millisecondsSinceEpoch,
    'elapsed_ms': elapsedMs,
    'distance_m': distanceM,
    'climb_m': climbM,
    'points': [
      for (final p in points)
        [
          p.lat,
          p.lng,
          p.altitude,
          p.time.millisecondsSinceEpoch,
          p.startsSegment,
          p.elapsedMs,
        ],
    ],
  };

  static RunDraft? fromMap(Map<String, Object?> m) {
    try {
      final raw = m['points'];
      if (raw is! List) return null;
      final pts = <RunPoint>[];
      for (final row in raw) {
        if (row is! List || row.length < 4) return null;
        final lat = (row[0] as num).toDouble();
        final lng = (row[1] as num).toDouble();
        final altitude = (row[2] as num?)?.toDouble() ?? 0;
        if (!lat.isFinite ||
            lat.abs() > 90 ||
            !lng.isFinite ||
            lng.abs() > 180 ||
            !altitude.isFinite) {
          return null;
        }
        pts.add(
          RunPoint(
            lat: lat,
            lng: lng,
            altitude: altitude,
            time: DateTime.fromMillisecondsSinceEpoch((row[3] as num).toInt()),
            startsSegment: row.length > 4 && row[4] == true,
            elapsedMs: row.length > 5 ? (row[5] as num?)?.toInt() : null,
          ),
        );
      }
      if (pts.isEmpty) return null;
      final elapsed = (m['elapsed_ms'] as num?)?.toInt() ?? 0;
      final distance = (m['distance_m'] as num?)?.toDouble() ?? 0;
      final climb = (m['climb_m'] as num?)?.toDouble() ?? 0;
      if (elapsed < 0 ||
          !distance.isFinite ||
          distance < 0 ||
          !climb.isFinite ||
          climb < 0) {
        return null;
      }
      return RunDraft(
        sessionId: m['session_id'] as String?,
        start: DateTime.fromMillisecondsSinceEpoch(
          (m['start_ms'] as num).toInt(),
        ),
        end: m['end_ms'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((m['end_ms'] as num).toInt()),
        elapsedMs: elapsed,
        distanceM: distance,
        climbM: climb,
        points: pts,
      );
    } on Object {
      return null;
    }
  }

  static Future<File?> _file() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/$_fileName');
    } on MissingPluginException {
      return null; // Unsupported hosts (e.g. a widget test without a path plugin).
    }
  }

  static Future<void> save(RunDraft draft) {
    // Capture data now, before another GPS update can mutate the caller's list.
    final json = jsonEncode(draft.toMap());
    return _ordered(() async {
      final f = await _file();
      if (f == null) return;
      final temporary = File('${f.path}.tmp');
      await temporary.writeAsString(json, flush: true);
      // Same-directory rename replaces the previous complete snapshot.
      await temporary.rename(f.path);
    });
  }

  static Future<RunDraft?> _read(File f) async {
    if (!await f.exists()) return null;
    try {
      final data = jsonDecode(await f.readAsString());
      return data is Map<String, dynamic> ? fromMap(data) : null;
    } on FormatException {
      return null;
    }
  }

  static Future<RunDraft?> load() => _ordered(() async {
    final f = await _file();
    return f == null ? null : _read(f);
  });

  /// A stale page can only clear the session it actually saved/discarded.
  static Future<void> clear({String? sessionId}) => _ordered(() async {
    final f = await _file();
    if (f == null) return;
    if (sessionId != null && (await _read(f))?.sessionKey != sessionId) return;
    if (await f.exists()) await f.delete();
    final temporary = File('${f.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
  });
}
