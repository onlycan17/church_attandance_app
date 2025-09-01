import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:church_attendance_app/services/attendance_service.dart';

class GPSService {
  static const Duration locationUpdateInterval = Duration(seconds: 5);

  StreamSubscription<Position>? _positionStream;
  final StreamController<bool> _locationStatusController =
      StreamController<bool>();

  late AttendanceService _attendanceService;

  Stream<bool> get locationStatus => _locationStatusController.stream;

  void setAttendanceService(AttendanceService attendanceService) {
    _attendanceService = attendanceService;
  }

  Future<void> startBackgroundLocationMonitoring() async {
    try {
      await Workmanager().registerPeriodicTask(
        'location_monitoring',
        'background_location_check',
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        inputData: <String, dynamic>{},
      );

      debugPrint('백그라운드 위치 모니터링 시작');
    } catch (e) {
      debugPrint('백그라운드 위치 모니터링 시작 오류: $e');
    }
  }

  Future<void> stopBackgroundLocationMonitoring() async {
    try {
      await Workmanager().cancelByUniqueName('location_monitoring');
      debugPrint('백그라운드 위치 모니터링 중지');
    } catch (e) {
      debugPrint('백그라운드 위치 모니터링 중지 오류: $e');
    }
  }

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

      _positionStream =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              distanceFilter: 10,
            ),
          ).listen((Position position) {
            _attendanceService.checkAttendance(position);
          });

      _locationStatusController.add(true);
    } catch (e) {
      debugPrint('GPS 위치 모니터링 시작 오류: $e');
      _locationStatusController.add(false);
    }
  }

  void stopLocationMonitoring() {
    _positionStream?.cancel();
    _locationStatusController.close();
  }

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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 30),
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

  Future<bool> isWithinChurchRadius(Position position) async {
    return await _attendanceService.isWithinChurchRadius(position);
  }
}