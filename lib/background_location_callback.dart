import 'package:church_attendance_app/services/attendance_service.dart';
import 'package:church_attendance_app/services/gps_service.dart';
import 'package:church_attendance_app/services/supabase_service.dart';
import 'package:church_attendance_app/services/local_queue_service.dart';
import 'package:church_attendance_app/services/auth_storage_service.dart';
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

      // 로컬 저장소에서 세션 정보 복원
      final authStorage = AuthStorageService();
      await authStorage.init();

      // 저장된 세션으로 인증 상태 복원
      bool sessionRestored = false;
      try {
        final savedSession = await authStorage.getSavedSession();
        if (savedSession != null) {
          final refreshToken = savedSession['refreshToken'] as String;
          if (refreshToken.isNotEmpty) {
            // 저장된 refresh token으로 세션 복원 시도
            await Supabase.instance.client.auth.setSession(refreshToken);
            sessionRestored = true;
            debugPrint('백그라운드: 저장된 세션으로 인증 복원 성공');
          }
        }
      } catch (e) {
        debugPrint('백그라운드: 세션 복원 실패: $e');
        // 복원 실패 시 저장된 세션 삭제
        await authStorage.clearSession();
      }

      // 이전 방식과의 호환성 유지 (access token이 전달된 경우)
      if (!sessionRestored) {
        try {
          final at = (inputData?['access_token'] as String?)?.trim();
          if (at != null && at.isNotEmpty) {
            SupabaseService().registerExternalAccessToken(at);
            debugPrint('백그라운드: access token으로 대체 인증 사용');
          }
        } catch (e) {
          debugPrint('백그라운드: 토큰 파싱 실패: $e');
        }
      }

      final currentUser = Supabase.instance.client.auth.currentUser;
      debugPrint('백그라운드: 현재 사용자 세션 ${currentUser != null ? '존재' : '없음'}');

      // 사용자 세션이 없으면 위치 수집 중단
      if (currentUser == null) {
        debugPrint('백그라운드: 사용자 세션이 없어 위치 수집 중단');
        return Future.value(false);
      }

      // 네트워크 연결 상태 확인
      bool hasNetworkConnection = true;
      try {
        // 현재 세션이 있는지 확인하여 네트워크 연결 상태 추정
        final currentSession = Supabase.instance.client.auth.currentSession;
        if (currentSession != null) {
          // 세션이 있으면 일반적으로 네트워크가 연결되어 있다고 가정
          hasNetworkConnection = true;
        } else {
          // 세션이 없으면 네트워크 연결을 직접 테스트
          hasNetworkConnection = false;
        }
      } catch (e) {
        if (e.toString().contains('SocketException') ||
            e.toString().contains('Failed host lookup') ||
            e.toString().contains('No address associated with hostname')) {
          hasNetworkConnection = false;
          debugPrint('백그라운드: 네트워크 연결 없음, 오프라인 모드로 진행');
        }
      }

      // DNS 오류 감지를 위한 추가 확인
      if (!hasNetworkConnection) {
        debugPrint('백그라운드: 네트워크 연결 문제 감지, 오프라인 모드로 작업 진행');
      }

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

      // 사용자 ID 추출 (위치 로깅에 사용)
      final uidOverride = inputData?['user_id_int'] as int?;

      // 출석 체크 (기기 시간을 활용하여 네트워크 요청 최소화)
      bool shouldCheckAttendance = true;

      try {
        // 1. 로컬 저장소에서 예배 정보 확인 (네트워크 요청 없음)
        final localServiceInfo = await authStorage.getLocalServiceInfo();
        if (localServiceInfo != null) {
          final isServiceTime = authStorage.isWithinServiceTime(
            localServiceInfo,
          );
          shouldCheckAttendance = isServiceTime;
          debugPrint('백그라운드 로컬 시간 판단: ${isServiceTime ? "예배 시간" : "예배 시간 아님"}');

          // 로컬 정보가 있으면 교회 위치도 확인
          if (isServiceTime) {
            final distance = Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              localServiceInfo.churchLatitude,
              localServiceInfo.churchLongitude,
            );
            final isWithinRadius =
                distance <= localServiceInfo.churchRadiusMeters;
            shouldCheckAttendance = isWithinRadius;
            debugPrint('백그라운드 교회 반경 확인: ${isWithinRadius ? "반경 내" : "반경 밖"}');
          }
        } else {
          debugPrint('백그라운드: 로컬 예배 정보 없음, 기본 시간으로 판단');
          // 기본 예배 시간 (주일 오전 11시)으로 간단히 판단
          final now = DateTime.now();
          if (now.weekday == DateTime.sunday &&
              now.hour >= 9 &&
              now.hour <= 13) {
            shouldCheckAttendance = true;
            debugPrint('백그라운드 기본 시간 판단: 주일 오전 9-13시로 간주');
          } else {
            shouldCheckAttendance = false;
            debugPrint('백그라운드 기본 시간 판단: 기본 예배 시간 아님');
          }
        }
      } catch (e) {
        debugPrint('백그라운드 예배 시간 판단 오류: $e, 기본값 사용');
        shouldCheckAttendance = true; // 오류 시 기본적으로 허용
      }

      // 출석 체크 조건에 따라 실행
      if (shouldCheckAttendance && hasNetworkConnection) {
        try {
          await attendanceService.checkAttendance(position);
        } catch (e) {
          debugPrint('백그라운드 출석 체크 오류: $e');
        }
      } else if (shouldCheckAttendance && !hasNetworkConnection) {
        debugPrint('백그라운드: 네트워크 없음, 출석 체크 스킵, 위치만 로깅');
        await attendanceService.logBackgroundLocation(
          position,
          userIdIntOverride: uidOverride,
        );
      } else {
        debugPrint('백그라운드: 출석 조건 불충족, 위치만 로깅');
        await attendanceService.logBackgroundLocation(
          position,
          userIdIntOverride: uidOverride,
        );
      }

      // 위치 로그(백그라운드) - 네트워크 연결 여부에 관계없이 시도
      final saved = await supabaseService.tryInsertLocationLog(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        source: 'background',
        userIdIntOverride: uidOverride,
      );

      if (!saved) {
        // 네트워크 오류나 기타 이유로 저장 실패 시 큐에 적재
        if (uidOverride != null) {
          await queue.enqueue(
            userId: uidOverride,
            serviceId: null,
            lat: position.latitude,
            lng: position.longitude,
            accuracy: position.accuracy,
            source: 'background',
            capturedAt: DateTime.now(),
          );
          debugPrint(
            '백그라운드: 저장 실패로 큐 적재(user=$uidOverride, network=$hasNetworkConnection)',
          );
        } else {
          debugPrint('백그라운드: 사용자 ID 없어 큐 적재 불가');
        }
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
              if (!saved) {
                if (uidOverride != null) {
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
                } else {
                  debugPrint('백그라운드: 버스트 - 사용자 ID 없어 큐 적재 불가');
                }
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
              if (!saved) {
                if (uidOverride != null) {
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
                } else {
                  debugPrint('백그라운드: 버스트(현재 위치) - 사용자 ID 없어 큐 적재 불가');
                }
              }
              debugPrint('백그라운드 테스트 버스트(현재 위치) 저장 ${i + 1}/$loops');
            }
          } catch (e) {
            debugPrint('백그라운드 테스트 버스트 저장 실패: $e');
          }
        }
      }

      // 오프라인 큐 플러시(최대 100건, eligible 조건) - 네트워크 연결 시에만 시도
      if (hasNetworkConnection) {
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
      } else {
        debugPrint('백그라운드: 네트워크 연결 없어 큐 플러시 스킵');
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
              // 토큰은 더 이상 전달하지 않음 - 로컬 저장소에서 복원
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
