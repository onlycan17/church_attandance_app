import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class LocalQueueService {
  static final LocalQueueService _instance = LocalQueueService._internal();
  factory LocalQueueService() => _instance;
  LocalQueueService._internal();

  Database? _db;

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
    return await db.rawUpdate(
      'UPDATE log_queue SET retries = retries + 1 WHERE id IN ($placeholders)',
      ids,
    );
  }

  Future<int> count() async {
    final db = _db;
    if (db == null) throw StateError('LocalQueueService not initialized');
    final res = await db.rawQuery('SELECT COUNT(*) as cnt FROM log_queue');
    return (res.first['cnt'] as int?) ?? 0;
  }
}
