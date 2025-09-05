import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:church_attendance_app/services/attendance_service.dart';

class GPSService {
  static const Duration locationUpdateInterval = Duration(
    seconds: 10,
  ); // 배터리 절약을 위해 10초로 변경
  static const int distanceFilter = 10; // 이동 거리 필터 (미터)
  static const Duration positionTimeout = Duration(
    seconds: 90,
  ); // 위치 요청 타임아웃 (백그라운드에서는 90초로 완화)
  static const Duration lastKnownMaxAge = Duration(minutes: 5); // 마지막 위치 허용 나이

  StreamSubscription<Position>? _positionStream;
  final StreamController<bool> _locationStatusController =
      StreamController<bool>.broadcast();

  late AttendanceService _attendanceService;

  Stream<bool> get locationStatus => _locationStatusController.stream;

  void setAttendanceService(AttendanceService attendanceService) {
    _attendanceService = attendanceService;
  }

  /// 백그라운드 위치 모니터링 시작
  /// 기본 15분 간격, 테스트 시 더 짧은 주기는 OneOff 자체 재스케줄 방식 적용
  Future<void> startBackgroundLocationMonitoring({
    Duration? interval,
    String? accessToken,
    String? refreshToken,
  }) async {
    try {
      final Duration target = interval ?? const Duration(minutes: 15);
      // 내부 user_id(int) 조회(가능 시) → WorkManager inputData로 전달
      int? userIdInt;
      try {
        userIdInt = await _attendanceService.getInternalUserId();
      } catch (_) {}
      if (target < const Duration(minutes: 15)) {
        await Workmanager().registerOneOffTask(
          'location_monitoring_debug',
          'background_location_check',
          initialDelay: target,
          existingWorkPolicy: ExistingWorkPolicy.replace,
          constraints: Constraints(
            networkType: NetworkType.connected,
            requiresBatteryNotLow: true,
          ),
          backoffPolicy: BackoffPolicy.exponential,
          backoffPolicyDelay: const Duration(minutes: 5),
          inputData: <String, dynamic>{
            'scheduled_at': DateTime.now().toIso8601String(),
            'note': 'background_location_check_debug',
            'reschedule_interval_sec': target.inSeconds,
            // 테스트 버스트(짧은 간격 연속 로그) 파라미터: 15초 간격으로 60초간 추가 저장
            'test_burst_interval_sec': 15,
            'test_burst_total_sec': 60,
            if (userIdInt != null) 'user_id_int': userIdInt,
            if (accessToken != null) 'access_token': accessToken,
            if (refreshToken != null) 'refresh_token': refreshToken,
          },
        );
        debugPrint(
          '백그라운드 위치 모니터링 시작 (테스트 모드: ${target.inMinutes}분 간격, OneOff 재스케줄)',
        );
      } else {
        await Workmanager().registerPeriodicTask(
          'location_monitoring',
          'background_location_check',
          frequency: const Duration(minutes: 15), // 최소 15분
          constraints: Constraints(
            networkType: NetworkType.connected,
            requiresBatteryNotLow: true,
          ),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
          backoffPolicy: BackoffPolicy.exponential,
          backoffPolicyDelay: const Duration(minutes: 5),
          inputData: <String, dynamic>{
            'scheduled_at': DateTime.now().toIso8601String(),
            'note': 'background_location_check',
            if (userIdInt != null) 'user_id_int': userIdInt,
            if (accessToken != null) 'access_token': accessToken,
            if (refreshToken != null) 'refresh_token': refreshToken,
          },
        );
        debugPrint('백그라운드 위치 모니터링 시작 (15분 간격)');
      }
    } catch (e) {
      debugPrint('백그라운드 위치 모니터링 시작 오류: $e');
    }
  }

  /// 백그라운드 위치 모니터링 중지
  Future<void> stopBackgroundLocationMonitoring() async {
    try {
      await Workmanager().cancelByUniqueName('location_monitoring');
      await Workmanager().cancelByUniqueName('location_monitoring_debug');
      debugPrint('백그라운드 위치 모니터링 중지');
    } catch (e) {
      debugPrint('백그라운드 위치 모니터링 중지 오류: $e');
    }
  }

  /// 포그라운드 위치 모니터링 시작
  /// 앱이 실행 중일 때 10초 간격으로 위치 확인
  Future<void> startLocationMonitoring() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('GPS: 위치 서비스가 비활성화되어 있습니다.');
        _locationStatusController.add(false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('GPS: 현재 권한 상태: $permission');

      if (permission == LocationPermission.denied) {
        debugPrint('GPS: 위치 권한 요청 중...');
        permission = await Geolocator.requestPermission();
        debugPrint('GPS: 권한 요청 결과: $permission');

        if (permission == LocationPermission.denied) {
          debugPrint('GPS: 사용자가 위치 권한을 거부했습니다.');
          _locationStatusController.add(false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('GPS: 위치 권한이 영구적으로 거부되었습니다. 설정에서 권한을 허용해주세요.');
        _locationStatusController.add(false);
        return;
      }

      // 기존 스트림이 있다면 취소
      await _positionStream?.cancel();

      // 위치 스트림 시작 (10초 간격, 10m 이동 시 업데이트)
      final LocationSettings streamSettings = _streamSettings();
      _positionStream =
          Geolocator.getPositionStream(locationSettings: streamSettings).listen(
            (Position position) async {
              debugPrint(
                'GPS: 위치 업데이트 - 위도: ${position.latitude}, 경도: ${position.longitude}',
              );
              _locationStatusController.add(true);
              await _attendanceService.checkAttendance(position);
            },
            onError: (error) async {
              debugPrint('GPS: 위치 스트림 오류 - $error');
              _locationStatusController.add(false);
              final msg = error.toString();
              if (msg.contains('Time limit') || error is TimeoutException) {
                await Future.delayed(const Duration(seconds: 2));
                try {
                  await _positionStream?.cancel();
                } catch (_) {}
                await _restartPositionStream();
              }
            },
          );

      _locationStatusController.add(true);
      debugPrint('GPS: 위치 모니터링 시작 (10초 간격)');
    } catch (e) {
      debugPrint('GPS 위치 모니터링 시작 오류: $e');
      _locationStatusController.add(false);
    }
  }

  /// 위치 모니터링 중지
  void stopLocationMonitoring() {
    _positionStream?.cancel();
    _locationStatusController.close();
    debugPrint('GPS: 위치 모니터링 중지');
  }

  Future<void> _restartPositionStream() async {
    try {
      final LocationSettings s = _streamSettings();
      _positionStream = Geolocator.getPositionStream(locationSettings: s).listen(
        (Position position) async {
          debugPrint(
            'GPS: 위치 업데이트(재시작) - 위도: ${position.latitude}, 경도: ${position.longitude}',
          );
          _locationStatusController.add(true);
          await _attendanceService.checkAttendance(position);
        },
        onError: (error) {
          debugPrint('GPS: 위치 스트림 오류(재시작) - $error');
          _locationStatusController.add(false);
        },
      );
      debugPrint('GPS: 위치 스트림 재시작 완료');
    } catch (e) {
      debugPrint('GPS: 위치 스트림 재시작 실패: $e');
    }
  }

  LocationSettings _streamSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: distanceFilter,
        intervalDuration: locationUpdateInterval,
      );
    }
    return LocationSettings(
      accuracy: LocationAccuracy.medium,
      distanceFilter: distanceFilter,
    );
  }

  /// 현재 위치 가져오기 (고정밀도)
  /// forBackground=true 시 Android에서 포그라운드 알림을 사용해 위치 접근
  Future<Position> getCurrentLocation({bool forBackground = false}) async {
    try {
      debugPrint('GPS: 현재 위치 요청 시작');

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      debugPrint('GPS: 위치 서비스 활성화 상태: $serviceEnabled');

      if (!serviceEnabled) {
        throw Exception('위치 서비스가 활성화되지 않았습니다. 설정에서 위치 서비스를 켜주세요.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('GPS: 현재 권한 상태: $permission');

      if (permission == LocationPermission.denied) {
        debugPrint('GPS: 위치 권한 요청 중...');
        permission = await Geolocator.requestPermission();
        debugPrint('GPS: 권한 요청 결과: $permission');

        if (permission == LocationPermission.denied) {
          throw Exception('위치 권한이 거부되었습니다. 앱 설정에서 위치 권한을 허용해주세요.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('위치 권한이 영구 거부되었습니다. 앱 설정에서 위치 권한을 허용해주세요.');
      }

      debugPrint('GPS: 위치 정보 요청 중...');

      final LocationSettings settings;
      if (forBackground && defaultTargetPlatform == TargetPlatform.android) {
        settings = AndroidSettings(
          accuracy: LocationAccuracy.medium, // 배터리/획득속도 균형
          timeLimit: positionTimeout,
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: '위치 확인 중',
            notificationText: '백그라운드에서 위치를 확인하고 있습니다.',
            enableWakeLock: true,
          ),
        );
      } else {
        settings = LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: positionTimeout,
        );
      }

      Position position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: settings,
        );
      } on TimeoutException catch (_) {
        debugPrint('GPS: 현재 위치 타임아웃 - lastKnownPosition 시도');
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          final ts = last.timestamp;
          if (DateTime.now().difference(ts) <= lastKnownMaxAge) {
            debugPrint(
              'GPS: lastKnownPosition 사용 - 위도: ${last.latitude}, 경도: ${last.longitude}',
            );
            return last;
          }
        }
        rethrow;
      }

      debugPrint(
        'GPS: 위치 정보 획득 성공 - 위도: ${position.latitude}, 경도: ${position.longitude}, 정확도: ${position.accuracy}m',
      );

      return position;
    } catch (e) {
      debugPrint('GPS: 현재 위치 가져오기 오류: $e');

      if (e.toString().contains('timeout')) {
        throw Exception('위치 정보를 가져오는 데 시간이 너무 오래 걸렸습니다. 다시 시도해주세요.');
      } else if (e.toString().contains('permission')) {
        throw Exception('위치 권한이 필요합니다. 앱 설정에서 위치 권한을 허용해주세요.');
      } else if (e.toString().contains('service')) {
        throw Exception('위치 서비스가 비활성화되어 있습니다. 설정에서 위치 서비스를 켜주세요.');
      } else {
        throw Exception('위치 정보를 가져올 수 없습니다: ${e.toString()}');
      }
    }
  }

  /// 위치 권한 상태 확인
  Future<LocationPermission> checkLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('GPS: 권한 상태 확인 - $permission');
      return permission;
    } catch (e) {
      debugPrint('GPS: 권한 상태 확인 오류: $e');
      return LocationPermission.denied;
    }
  }

  /// 위치 서비스 활성화 상태 확인
  Future<bool> isLocationServiceEnabled() async {
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      debugPrint('GPS: 위치 서비스 상태 - $enabled');
      return enabled;
    } catch (e) {
      debugPrint('GPS: 위치 서비스 상태 확인 오류: $e');
      return false;
    }
  }

  /// 교회 반경 내에 있는지 확인
  Future<bool> isWithinChurchRadius(Position position) async {
    return await _attendanceService.isWithinChurchRadius(position);
  }
}
