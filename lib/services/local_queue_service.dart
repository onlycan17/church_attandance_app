import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class LocalQueueService {
  static final LocalQueueService _instance = LocalQueueService._internal();
  factory LocalQueueService() => _instance;
  LocalQueueService._internal();

  Database? _db;
  static const int maxRetries = 5;
  static const int baseDelaySec = 60; // 지수 백오프 기본 지연(초)

  Future<void> init() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'app_cache.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS log_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            service_id INTEGER NULL,
            lat REAL NOT NULL,
            lng REAL NOT NULL,
            accuracy REAL NULL,
            source TEXT NOT NULL,
            captured_at TEXT NOT NULL,
            retries INTEGER NOT NULL DEFAULT 0,
            next_attempt_at TEXT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
          );
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_log_queue_user ON log_queue(user_id);',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_log_queue_captured ON log_queue(captured_at);',
        );
      },
    );
    await _ensureColumns();
  }

  Future<void> _ensureColumns() async {
    final db = _db!;
    final cols = await db.rawQuery("PRAGMA table_info('log_queue')");
    final names = cols.map((e) => (e['name'] as String).toLowerCase()).toSet();
    if (!names.contains('next_attempt_at')) {
      await db.execute(
        "ALTER TABLE log_queue ADD COLUMN next_attempt_at TEXT NULL",
      );
    }
  }

  Future<int> enqueue({
    required int userId,
    int? serviceId,
    required double lat,
    required double lng,
    double? accuracy,
    required String source,
    required DateTime capturedAt,
  }) async {
    final db = _db;
    if (db == null) throw StateError('LocalQueueService not initialized');
    return await db.insert('log_queue', {
      'user_id': userId,
      'service_id': serviceId,
      'lat': lat,
      'lng': lng,
      'accuracy': accuracy,
      'source': source,
      'captured_at': capturedAt.toIso8601String(),
      'retries': 0,
      'next_attempt_at': null,
    });
  }

  Future<List<Map<String, dynamic>>> fetchBatch(int limit) async {
    final db = _db;
    if (db == null) throw StateError('LocalQueueService not initialized');
    return await db.query(
      'log_queue',
      orderBy: 'captured_at ASC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> fetchEligibleBatch(int limit) async {
    final db = _db;
    if (db == null) throw StateError('LocalQueueService not initialized');
    final nowIso = DateTime.now().toIso8601String();
    return await db.query(
      'log_queue',
      where:
          '(next_attempt_at IS NULL OR next_attempt_at <= ?) AND retries < ?',
      whereArgs: [nowIso, maxRetries],
      orderBy: 'captured_at ASC',
      limit: limit,
    );
  }

  Future<int> deleteByIds(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final db = _db;
    if (db == null) throw StateError('LocalQueueService not initialized');
    final placeholders = List.filled(ids.length, '?').join(',');
    return await db.delete(
      'log_queue',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<int> incrementRetries(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final db = _db;
    if (db == null) throw StateError('LocalQueueService not initialized');
    final placeholders = List.filled(ids.length, '?').join(',');
    // 현재 retries 읽어와서 지수 백오프를 반영한 next_attempt_at 설정
    final rows = await db.query(
      'log_queue',
      columns: ['id', 'retries'],
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    final batch = db.batch();
    for (final r in rows) {
      final id = r['id'] as int;
      final currentRetries = (r['retries'] as int?) ?? 0;
      final newRetries = currentRetries + 1;
      int delaySec = baseDelaySec * (1 << (newRetries - 1));
      if (delaySec > 1800) delaySec = 1800; // 30분 상한
      final next = DateTime.now()
          .add(Duration(seconds: delaySec))
          .toIso8601String();
      batch.update(
        'log_queue',
        {'retries': newRetries, 'next_attempt_at': next},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    final res = await batch.commit(noResult: true);
    return res.length;
  }

  Future<int> count() async {
    final db = _db;
    if (db == null) throw StateError('LocalQueueService not initialized');
    final res = await db.rawQuery('SELECT COUNT(*) as cnt FROM log_queue');
    return (res.first['cnt'] as int?) ?? 0;
  }

  Future<int> pruneExceededRetries() async {
    final db = _db;
    if (db == null) throw StateError('LocalQueueService not initialized');
    return await db.delete(
      'log_queue',
      where: 'retries >= ?',
      whereArgs: [maxRetries],
    );
  }
}
