import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:church_attendance_app/services/supabase_service.dart';

class GPSService {
  // 테스트용 상수들 (실제 운영에서는 데이터베이스에서 가져옴)
  static const double churchRadiusMeters = 80.0;
  static const churchLatitude = 37.5665; // 서울 시청 위도 (테스트용)
  static const churchLongitude = 126.9780; // 서울 시청 경도 (테스트용)

  static const Duration locationUpdateInterval = Duration(seconds: 5);

  StreamSubscription<Position>? _positionStream;
  final StreamController<bool> _locationStatusController =
      StreamController<bool>();

  late SupabaseService _supabaseService;

  Stream<bool> get locationStatus => _locationStatusController.stream;

  // SupabaseService 의존성 주입
  void setSupabaseService(SupabaseService supabaseService) {
    _supabaseService = supabaseService;
  }

  // 백그라운드 작업 초기화 (main.dart에서 처리하므로 제거)
  Future<void> initializeBackgroundService() async {
    // main.dart에서 Workmanager를 초기화하므로 여기서는 아무것도 하지 않음
    debugPrint('백그라운드 서비스 초기화는 main.dart에서 처리됩니다');
  }

  // 백그라운드 위치 모니터링 시작
  Future<void> startBackgroundLocationMonitoring() async {
    try {
      // 백그라운드 작업 등록
      await Workmanager().registerPeriodicTask(
        'location_monitoring',
        'background_location_check',
        frequency: const Duration(minutes: 15), // 15분마다 실행 - 더 빈번한 체크
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
      // 데이터베이스에서 교회 위치 정보 가져오기
      final currentService = await _supabaseService.getCurrentService();
      if (currentService == null) {
        debugPrint('현재 예배 서비스 정보를 찾을 수 없습니다.');
        return false;
      }

      final serviceId = (currentService['id'] as int);
      final churchLocation = await _supabaseService.getChurchLocation(
        serviceId,
      );
      if (churchLocation == null) {
        debugPrint('교회 위치 정보를 찾을 수 없습니다.');
        return false;
      }

      final churchLatitude = double.parse(
        churchLocation['latitude'].toString(),
      );
      final churchLongitude = double.parse(
        churchLocation['longitude'].toString(),
      );
      final churchRadiusMeters = double.parse(
        churchLocation['radius_meters'].toString(),
      );

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

      final serviceId = currentService['id'].toString();
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
      debugPrint('GPS: 현재 위치 요청 시작');

      // 위치 서비스 활성화 확인
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      debugPrint('GPS: 위치 서비스 활성화 상태: $serviceEnabled');

      if (!serviceEnabled) {
        throw Exception('위치 서비스가 활성화되지 않았습니다. 설정에서 위치 서비스를 켜주세요.');
      }

      // 위치 권한 확인 및 요청
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

      // 위치 정보 가져오기 (타임아웃/정확도 설정)
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

      // 더 자세한 오류 메시지 제공
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

  // 위치 권한 상태 확인
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

  // 위치 서비스 상태 확인
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
}
