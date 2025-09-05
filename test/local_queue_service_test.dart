import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:church_attendance_app/services/local_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalQueueService', () {
    late LocalQueueService service;
    late Database db;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      service = LocalQueueService();
      await service.initWithDb(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('enqueue and fetchEligibleBatch', () async {
      final before = await service.count();
      expect(before, 0);

      await service.enqueue(
        userId: 1,
        serviceId: null,
        lat: 37.0,
        lng: 127.0,
        accuracy: 10.0,
        source: 'background',
        capturedAt: DateTime.now(),
      );

      final list = await service.fetchEligibleBatch(10);
      expect(list.length, 1);
      expect(list.first['user_id'], 1);
    });

    test(
      'incrementRetries sets next_attempt_at and pruneExceededRetries',
      () async {
        // Insert an item
        final id = await service.enqueue(
          userId: 2,
          serviceId: null,
          lat: 36.0,
          lng: 128.0,
          accuracy: null,
          source: 'background',
          capturedAt: DateTime.now(),
        );

        // Force increment retries multiple times
        for (int i = 0; i < LocalQueueService.maxRetries; i++) {
          await service.incrementRetries([id]);
        }

        // After maxRetries increments, prune should remove it
        final pruned = await service.pruneExceededRetries();
        expect(pruned, greaterThanOrEqualTo(1));
      },
    );
  });
}
