import 'package:church_attendance_app/services/attendance_service.dart';
import 'package:church_attendance_app/services/gps_service.dart';
import 'package:church_attendance_app/services/supabase_service.dart';
import 'package:church_attendance_app/services/local_queue_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // 백그라운드 Isolate에서 Flutter 엔진 바인딩 및 서비스 초기화
      WidgetsFlutterBinding.ensureInitialized();

      // .env 파일 로드
      await dotenv.load(fileName: ".env");

      // Supabase 초기화
      await Supabase.initialize(
        url: dotenv.env['SUPABASE_URL']!,
        anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
      );
      debugPrint('백그라운드: Supabase 초기화 완료');

      // 서비스 초기화
      final supabaseService = SupabaseService();
      await supabaseService.init();
      final queue = LocalQueueService();
      await queue.init();
      // 세션 복구 시도(주의): refresh token 재사용은 세션 폐기 리스크가 있어 사용하지 않음
      try {
        final at = (inputData?['access_token'] as String?)?.trim();

        // access token은 이메일 디코딩 등 보조 용도로만 보관(세션 교체 없음)
        if (at != null && at.isNotEmpty) {
          try {
            SupabaseService().registerExternalAccessToken(at);
          } catch (_) {}
          debugPrint('백그라운드: access token 수신(세션 교체 없음)');
        }
      } catch (e) {
        debugPrint('백그라운드: 토큰 파싱 실패: $e');
      }

      final currentUser = Supabase.instance.client.auth.currentUser;
      debugPrint('백그라운드: 현재 사용자 세션 ${currentUser != null ? '존재' : '없음'}');

      final gpsService = GPSService();
      final attendanceService = AttendanceService(supabaseService);
      gpsService.setAttendanceService(attendanceService);

      // 백그라운드에서 위치 서비스 상태 확인
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('백그라운드: 위치 서비스 비활성화됨');
        return Future.value(false);
      }

      // 위치 권한 확인
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        debugPrint('백그라운드: 위치 권한 없음 - $permission');
        return Future.value(false);
      }

      // 현재 위치 가져오기 (Android 백그라운드에서 포그라운드 알림 사용)
      final position = await gpsService.getCurrentLocation(forBackground: true);
      debugPrint(
        '백그라운드 위치 확인: 위도 ${position.latitude}, 경도 ${position.longitude}',
      );

      // 출석 체크
      await attendanceService.checkAttendance(position);
      // 위치 로그(백그라운드)
      final uidOverride = inputData?['user_id_int'] as int?;
      final saved = await supabaseService.tryInsertLocationLog(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        source: 'background',
        userIdIntOverride: uidOverride,
      );
      if (!saved && uidOverride != null) {
        await queue.enqueue(
          userId: uidOverride,
          serviceId: null,
          lat: position.latitude,
          lng: position.longitude,
          accuracy: position.accuracy,
          source: 'background',
          capturedAt: DateTime.now(),
        );
        debugPrint('백그라운드: 네트워크 실패로 큐 적재(user=$uidOverride)');
      }

      debugPrint('백그라운드 출석 체크 완료');

      // 디버그 모드: 짧은 간격(기본 15초)으로 연속 위치 로그 저장(총 60초 등)
      final int burstIntervalSec =
          (inputData?['test_burst_interval_sec'] as int?) ??
          int.tryParse(dotenv.env['TEST_BURST_INTERVAL_SEC'] ?? '') ??
          0;
      final int burstTotalSec =
          (inputData?['test_burst_total_sec'] as int?) ??
          int.tryParse(dotenv.env['TEST_BURST_TOTAL_SEC'] ?? '') ??
          0;
      if (burstIntervalSec > 0 && burstTotalSec > 0) {
        debugPrint(
          '백그라운드: 버스트 시작 interval=${burstIntervalSec}s total=${burstTotalSec}s',
        );
        final int loops = (burstTotalSec / burstIntervalSec).floor();
        for (int i = 0; i < loops; i++) {
          await Future.delayed(Duration(seconds: burstIntervalSec));
          try {
            // 빠른 저장을 위해 우선 lastKnownPosition 사용
            final last = await Geolocator.getLastKnownPosition();
            if (last != null) {
              final saved = await supabaseService.tryInsertLocationLog(
                latitude: last.latitude,
                longitude: last.longitude,
                accuracy: last.accuracy,
                source: 'background',
                userIdIntOverride: uidOverride,
              );
              if (!saved && uidOverride != null) {
                await queue.enqueue(
                  userId: uidOverride,
                  serviceId: null,
                  lat: last.latitude,
                  lng: last.longitude,
                  accuracy: last.accuracy,
                  source: 'background',
                  capturedAt: DateTime.now(),
                );
                debugPrint('백그라운드: 버스트 큐 적재(user=$uidOverride)');
              }
              debugPrint('백그라운드 테스트 버스트 저장 ${i + 1}/$loops');
            } else {
              // fallback: 현재 위치 재시도(짧은 시도)
              final quick = await gpsService.getCurrentLocation(
                forBackground: true,
              );
              final saved = await supabaseService.tryInsertLocationLog(
                latitude: quick.latitude,
                longitude: quick.longitude,
                accuracy: quick.accuracy,
                source: 'background',
                userIdIntOverride: uidOverride,
              );
              if (!saved && uidOverride != null) {
                await queue.enqueue(
                  userId: uidOverride,
                  serviceId: null,
                  lat: quick.latitude,
                  lng: quick.longitude,
                  accuracy: quick.accuracy,
                  source: 'background',
                  capturedAt: DateTime.now(),
                );
                debugPrint('백그라운드: 버스트 큐 적재(user=$uidOverride)');
              }
              debugPrint('백그라운드 테스트 버스트(현재 위치) 저장 ${i + 1}/$loops');
            }
          } catch (e) {
            debugPrint('백그라운드 테스트 버스트 저장 실패: $e');
          }
        }
      }

      // 오프라인 큐 플러시(최대 100건, eligible 조건)
      try {
        await queue.pruneExceededRetries();
        final total = await queue.count();
        final items = await queue.fetchEligibleBatch(100);
        debugPrint('백그라운드: 큐 상태 total=$total eligible=${items.length}');
        if (items.isNotEmpty) {
          final rows = items
              .map(
                (m) => {
                  'user_id': m['user_id'],
                  if (m['service_id'] != null) 'service_id': m['service_id'],
                  'latitude': m['lat'],
                  'longitude': m['lng'],
                  if (m['accuracy'] != null) 'accuracy': m['accuracy'],
                  'source': m['source'],
                  'captured_at': m['captured_at'],
                },
              )
              .toList();
          final ok = await supabaseService.bulkInsertLocationLogs(rows);
          final ids = items.map<int>((m) => m['id'] as int).toList();
          if (ok) {
            await queue.deleteByIds(ids);
            debugPrint('로컬 큐 업로드 성공: ${ids.length}건 제거');
          } else {
            await queue.incrementRetries(ids);
            debugPrint('로컬 큐 업로드 실패: 재시도 카운트 증가');
          }
        }
      } catch (e) {
        debugPrint('로컬 큐 플러시 오류: $e');
      }

      // 디버그(3분 등) 테스트용: 입력 데이터에 재스케줄 간격이 있으면 OneOff 재등록
      final nextSec = (inputData?['reschedule_interval_sec'] as int?) ?? 0;
      if (nextSec > 0) {
        try {
          await Workmanager().registerOneOffTask(
            'location_monitoring_debug',
            'background_location_check',
            initialDelay: Duration(seconds: nextSec),
            existingWorkPolicy: ExistingWorkPolicy.replace,
            constraints: Constraints(
              networkType: NetworkType.connected,
              requiresBatteryNotLow: true,
            ),
            inputData: <String, dynamic>{
              'scheduled_at': DateTime.now().toIso8601String(),
              'note': 'background_location_check_debug',
              'reschedule_interval_sec': nextSec,
              'test_burst_interval_sec': burstIntervalSec,
              'test_burst_total_sec': burstTotalSec,
              if (uidOverride != null) 'user_id_int': uidOverride,
              // 토큰은 재스케줄에 전달하지 않음(재사용 위험 제거)
            },
          );
          debugPrint('백그라운드 OneOff 재스케줄 (${nextSec}s 후)');
        } catch (e) {
          debugPrint('백그라운드 OneOff 재스케줄 실패: $e');
        }
      }

      return Future.value(true);
    } catch (e) {
      debugPrint('백그라운드 작업 오류: $e');
      final msg = e.toString();
      // 실패 시에도 디버그 모드(3분 간격)라면 스스로 재스케줄
      final nextSec = (inputData?['reschedule_interval_sec'] as int?) ?? 0;
      if (nextSec > 0) {
        try {
          final int burstIntervalSec =
              (inputData?['test_burst_interval_sec'] as int?) ?? 0;
          final int burstTotalSec =
              (inputData?['test_burst_total_sec'] as int?) ?? 0;
          final uidOverride = inputData?['user_id_int'] as int?;
          await Workmanager().registerOneOffTask(
            'location_monitoring_debug',
            'background_location_check',
            initialDelay: Duration(seconds: nextSec),
            existingWorkPolicy: ExistingWorkPolicy.replace,
            constraints: Constraints(
              networkType: NetworkType.connected,
              requiresBatteryNotLow: true,
            ),
            inputData: <String, dynamic>{
              'scheduled_at': DateTime.now().toIso8601String(),
              'note': 'background_location_check_debug',
              'reschedule_interval_sec': nextSec,
              'test_burst_interval_sec': burstIntervalSec,
              'test_burst_total_sec': burstTotalSec,
              if (uidOverride != null) 'user_id_int': uidOverride,
              // 토큰은 재스케줄에 전달하지 않음(재사용 위험 제거)
            },
          );
          debugPrint('백그라운드 OneOff 재스케줄(실패 경로) ${nextSec}s 후');
        } catch (e) {
          debugPrint('백그라운드 OneOff 재스케줄 실패(실패 경로): $e');
        }
      }
      // 네트워크/DNS/타임아웃은 성공 처리 → 즉시 RETRY 방지, 다음 주기에 재시도
      if (msg.contains('SocketException') ||
          msg.contains('Failed host lookup') ||
          msg.contains('TimeoutException')) {
        debugPrint('백그라운드: 일시적 이슈(네트워크/타임아웃) - 다음 주기에 재시도');
        return Future.value(true);
      }
      return Future.value(false);
    }
  });
}
