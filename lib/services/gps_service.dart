import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:church_attendance_app/services/supabase_service.dart';
import 'package:church_attendance_app/background_location_callback.dart';

class GPSService {
  static const double churchRadiusMeters = 80.0;
  static const Duration locationUpdateInterval = Duration(
    seconds: 10,
  ); // 배터리 절약을 위해 10초로 증가

  // 교회 위치 (예시 좌표 - 실제 앱에서는 Supabase에서 가져와야 함)
  static const churchLatitude = 37.5665; // 서울 시청 위도
  static const churchLongitude = 126.9780; // 서울 시청 경도

  StreamSubscription<Position>? _positionStream;
  final StreamController<bool> _locationStatusController =
      StreamController<bool>();

  late SupabaseService _supabaseService;

  Stream<bool> get locationStatus => _locationStatusController.stream;

  // SupabaseService 의존성 주입
  void setSupabaseService(SupabaseService supabaseService) {
    _supabaseService = supabaseService;
  }

  // 백그라운드 작업 초기화
  Future<void> initializeBackgroundService() async {
    try {
      // Workmanager 초기화
      await Workmanager().initialize(callbackDispatcher, isInDebugMode: true);

      debugPrint('백그라운드 서비스 초기화 완료');
    } catch (e) {
      debugPrint('백그라운드 서비스 초기화 오류: $e');
    }
  }

  // 백그라운드 위치 모니터링 시작
  Future<void> startBackgroundLocationMonitoring() async {
    try {
      // 백그라운드 작업 등록
      await Workmanager().registerPeriodicTask(
        'location_monitoring',
        'background_location_check',
        frequency: const Duration(minutes: 30), // 30분마다 실행 - 배터리 절약
        constraints: Constraints(
          networkType: NetworkType.connected, // 네트워크 연결 필요
          requiresBatteryNotLow: true, // 배터리가 부족하지 않아야 함
        ),
        inputData: <String, dynamic>{},
      );

      debugPrint('백그라운드 위치 모니터링 시작');
    } catch (e) {
      debugPrint('백그라운드 위치 모니터링 시작 오류: $e');
    }
  }

  // 백그라운드 위치 모니터링 중지
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
        _locationStatusController.add(false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _locationStatusController.add(false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _locationStatusController.add(false);
        return;
      }

      // 위치 업데이트 시작
      _positionStream =
          Geolocator.getPositionStream(
            locationSettings: LocationSettings(
              accuracy: LocationAccuracy.medium, // 배터리 절약을 위해 중간 정확도로 변경
              distanceFilter: 10, // 10미터 단위로만 업데이트 - 배터리 절약
            ),
          ).listen((Position position) {
            _checkAttendance(position);
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

  Future<bool> isWithinChurchRadius(Position position) async {
    try {
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        churchLatitude,
        churchLongitude,
      );
      return distance <= churchRadiusMeters;
    } catch (e) {
      debugPrint('거리 계산 오류: $e');
      return false;
    }
  }

  void _checkAttendance(Position position) async {
    try {
      bool isWithinRadius = await isWithinChurchRadius(position);

      // 여기서는 단순히 로그만 출력하지만, 실제 구현에서는 Supabase에 데이터 전송
      debugPrint(
        '위치 업데이트 - 위도: ${position.latitude}, 경도: ${position.longitude}, '
        '교회 반경 내: $isWithinRadius',
      );

      if (isWithinRadius) {
        // 교회 범위 내에 있을 경우 출석 체크 로직 호출
        await handleAttendanceCheck(position);
      }
    } catch (e) {
      debugPrint('출석 체크 중 오류: $e');
    }
  }

  Future<void> handleAttendanceCheck(Position position) async {
    try {
      debugPrint('출석 체크 발생 - 위치: ${position.latitude}, ${position.longitude}');

      // 현재 사용자 확인
      final currentUser = _supabaseService.getCurrentUser();
      if (currentUser == null) {
        debugPrint('사용자가 로그인되지 않았습니다.');
        return;
      }

      // 현재 예배 서비스 정보 가져오기
      final currentService = await _supabaseService.getCurrentService();
      if (currentService == null) {
        debugPrint('현재 예배 서비스 정보를 찾을 수 없습니다.');
        return;
      }

      final serviceId = currentService['id'] as String;
      final userId = currentUser.id;

      // 이미 출석 체크했는지 확인
      final existingRecord = await _supabaseService.checkAttendanceRecord(
        userId: userId,
        serviceId: serviceId,
      );

      if (existingRecord != null) {
        debugPrint('이미 출석 체크가 완료되었습니다.');
        return;
      }

      // 출석 데이터 전송
      await _supabaseService.submitAttendanceCheck(
        latitude: position.latitude,
        longitude: position.longitude,
        userId: userId,
        serviceId: serviceId,
      );

      debugPrint('출석 체크 데이터 전송 성공');

      // 출석 체크 성공 상태 알림
      _locationStatusController.add(true);
    } catch (e) {
      debugPrint('출석 체크 처리 중 오류: $e');
      rethrow;
    }
  }

  Future<Position> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('위치 서비스가 활성화되지 않았습니다.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('위치 권한이 거부되었습니다.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('위치 권한이 영구 거부되었습니다.');
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium, // 배터리 절약을 위해 중간 정확도로 변경
      );

      return position;
    } catch (e) {
      debugPrint('현재 위치 가져오기 오류: $e');
      rethrow;
    }
  }
}
