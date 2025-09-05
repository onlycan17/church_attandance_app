import 'package:church_attendance_app/services/attendance_service.dart';
import 'package:church_attendance_app/services/gps_service.dart';
import 'package:church_attendance_app/services/supabase_service.dart';
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
      // 세션 복구 시도(테스트/프로토타입 목적): inputData에 전달된 토큰 사용
      try {
        final at = (inputData?['access_token'] as String?)?.trim();
        final rt = (inputData?['refresh_token'] as String?)?.trim();

        // 우선 접근 토큰으로 인증 헤더 설정(네트워크 없이도 설정 가능)
        if (at != null && at.isNotEmpty) {
          // SupabaseService에 보조 저장(사용자 정보가 null일 때 JWT 디코드용)
          try {
            SupabaseService().registerExternalAccessToken(at);
          } catch (_) {}
          debugPrint('백그라운드: access token 수신 및 보조 저장');
        }

        // 가능하면 refresh token으로 세션 복구(네트워크 필요, 실패해도 치명적 아님)
        if (rt != null && rt.isNotEmpty) {
          try {
            await Supabase.instance.client.auth.setSession(rt);
            debugPrint('백그라운드: 세션 복구 시도 완료');
          } catch (e) {
            debugPrint('백그라운드: 세션 복구 실패: $e');
          }
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
      await attendanceService.logBackgroundLocation(
        position,
        userIdIntOverride: uidOverride,
      );

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
        final int loops = (burstTotalSec / burstIntervalSec).floor();
        for (int i = 0; i < loops; i++) {
          await Future.delayed(Duration(seconds: burstIntervalSec));
          try {
            // 빠른 저장을 위해 우선 lastKnownPosition 사용
            final last = await Geolocator.getLastKnownPosition();
            if (last != null) {
              await attendanceService.logBackgroundLocation(
                last,
                userIdIntOverride: uidOverride,
              );
              debugPrint('백그라운드 테스트 버스트 저장 ${i + 1}/$loops');
            } else {
              // fallback: 현재 위치 재시도(짧은 시도)
              final quick = await gpsService.getCurrentLocation(
                forBackground: true,
              );
              await attendanceService.logBackgroundLocation(
                quick,
                userIdIntOverride: uidOverride,
              );
              debugPrint('백그라운드 테스트 버스트(현재 위치) 저장 ${i + 1}/$loops');
            }
          } catch (e) {
            debugPrint('백그라운드 테스트 버스트 저장 실패: $e');
          }
        }
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
              if ((inputData?['access_token'] as String?) != null)
                'access_token': inputData?['access_token'],
              if ((inputData?['refresh_token'] as String?) != null)
                'refresh_token': inputData?['refresh_token'],
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
              if ((inputData?['access_token'] as String?) != null)
                'access_token': inputData?['access_token'],
              if ((inputData?['refresh_token'] as String?) != null)
                'refresh_token': inputData?['refresh_token'],
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
