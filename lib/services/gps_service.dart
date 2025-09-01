import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:church_attendance_app/services/attendance_service.dart';

class GPSService {
  static const Duration locationUpdateInterval = Duration(seconds: 10); // 배터리 절약을 위해 10초로 변경
  static const int distanceFilter = 10; // 이동 거리 필터 (미터)
  static const Duration positionTimeout = Duration(seconds: 45); // 위치 요청 타임아웃 (45초로 증가)

  StreamSubscription<Position>? _positionStream;
  final StreamController<bool> _locationStatusController =
      StreamController<bool>();

  late AttendanceService _attendanceService;

  Stream<bool> get locationStatus => _locationStatusController.stream;

  void setAttendanceService(AttendanceService attendanceService) {
    _attendanceService = attendanceService;
  }

  /// 백그라운드 위치 모니터링 시작
  /// 15분 간격으로 위치 확인 (배터리 절약)
  Future<void> startBackgroundLocationMonitoring() async {
    try {
      await Workmanager().registerPeriodicTask(
        'location_monitoring',
        'background_location_check',
        frequency: const Duration(minutes: 15), // 15분마다 실행
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        inputData: <String, dynamic>{},
      );

      debugPrint('백그라운드 위치 모니터링 시작 (15분 간격)');
    } catch (e) {
      debugPrint('백그라운드 위치 모니터링 시작 오류: $e');
    }
  }

  /// 백그라운드 위치 모니터링 중지
  Future<void> stopBackgroundLocationMonitoring() async {
    try {
      await Workmanager().cancelByUniqueName('location_monitoring');
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
      _positionStream =
          Geolocator.getPositionStream(
            locationSettings: LocationSettings(
              accuracy: LocationAccuracy.medium,
              distanceFilter: distanceFilter,
              timeLimit: positionTimeout,
            ),
          ).listen(
        (Position position) async {
          debugPrint('GPS: 위치 업데이트 - 위도: ${position.latitude}, 경도: ${position.longitude}');
          await _attendanceService.checkAttendance(position);
        },
        onError: (error) {
          debugPrint('GPS: 위치 스트림 오류 - $error');
          _locationStatusController.add(false);
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

  /// 현재 위치 가져오기 (고정밀도)
  Future<Position> getCurrentLocation() async {
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

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: positionTimeout,
        ),
      );

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