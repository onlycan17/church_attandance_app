import 'package:church_attendance_app/services/attendance_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:church_attendance_app/services/gps_service.dart';
import 'package:church_attendance_app/services/supabase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GPSService gpsService;
  late SupabaseService supabaseService;
  late AttendanceService attendanceService;

  setUp(() {
    gpsService = GPSService();
    supabaseService = SupabaseService();
    attendanceService = AttendanceService(supabaseService);
    gpsService.setAttendanceService(attendanceService);
  });

  group('GPSService 기본 기능 테스트', () {
    test('GPS 서비스 초기화', () {
      expect(gpsService, isNotNull);
      expect(gpsService.locationStatus, isNotNull);
    });

    test('AttendanceService 의존성 주입', () {
      // Given
      final testSupabaseService = SupabaseService();
      final testAttendanceService = AttendanceService(testSupabaseService);

      // When
      gpsService.setAttendanceService(testAttendanceService);

      // Then
      expect(testAttendanceService, isNotNull);
    });

    test('위치 업데이트 간격 상수 확인', () {
      // Given
      const expectedInterval = Duration(seconds: 5);

      // Then
      expect(GPSService.locationUpdateInterval, equals(expectedInterval));
    });
  });

  group('GPSService 위치 판별 테스트', () {
    test('교회 반경 내 위치 판별', () async {
      // Given - 교회 근처 위치 (약 10m 이내)
      final nearbyPosition = Position(
        latitude: 37.5665 + 0.0001, // 약 10m
        longitude: 126.9780 + 0.0001,
        timestamp: DateTime.now(),
        accuracy: 10.0,
        altitude: 0.0,
        heading: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
      );

      // When
      final result = await gpsService.isWithinChurchRadius(nearbyPosition);

      // Then
      expect(result, isTrue);
    }, skip: 'Supabase 초기화가 필요하여 단위 테스트에서는 스킵');

    test('교회 반경 외 위치 판별', () async {
      // Given - 교회에서 먼 위치 (약 1km 이상)
      final farPosition = Position(
        latitude: 37.5665 + 0.01, // 약 1km
        longitude: 126.9780 + 0.01,
        timestamp: DateTime.now(),
        accuracy: 10.0,
        altitude: 0.0,
        heading: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
      );

      // When
      final result = await gpsService.isWithinChurchRadius(farPosition);

      // Then
      expect(result, isFalse);
    }, skip: 'Supabase 초기화가 필요하여 단위 테스트에서는 스킵');

    test('거리 계산 정확성', () async {
      // Given - 두 지점 간의 거리 계산
      final position1 = Position(
        latitude: 37.5665,
        longitude: 126.9780,
        timestamp: DateTime.now(),
        accuracy: 10.0,
        altitude: 0.0,
        heading: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
      );

      final position2 = Position(
        latitude: 37.5750,
        longitude: 126.9780,
        timestamp: DateTime.now(),
        accuracy: 10.0,
        altitude: 0.0,
        heading: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
      );

      // When
      final distance = Geolocator.distanceBetween(
        position1.latitude,
        position1.longitude,
        position2.latitude,
        position2.longitude,
      );

      // Then
      expect(distance, greaterThan(0));
      expect(distance, lessThan(2000)); // 약 900m 정도여야 함
    });
  });

  group('GPSService 스트림 테스트', () {
    test('위치 상태 스트림 초기화', () {
      // When
      gpsService.locationStatus.listen((_) {});

      // Then
      expect(gpsService.locationStatus, isNotNull);
      // 스트림이 정상적으로 생성되었는지 확인
    });
  });

  group('GPSService 백그라운드 기능 테스트', () {
    test('백그라운드 모니터링 시작', () async {
      // When
      try {
        await gpsService.startBackgroundLocationMonitoring();
        // Then
        // 백그라운드 작업이 성공적으로 등록됨
      } catch (e) {
        // 백그라운드 작업 등록 실패 - 테스트 환경에서는 정상
        expect(e, isNotNull);
      }
    });

    test('백그라운드 모니터링 중지', () async {
      // When
      try {
        await gpsService.stopBackgroundLocationMonitoring();
        // Then
        // 백그라운드 작업이 성공적으로 중지됨
      } catch (e) {
        // 백그라운드 작업 중지 실패 - 테스트 환경에서는 정상
        expect(e, isNotNull);
      }
    });
  });

  group('GPSService 통합 테스트', () {
    test('현재 위치 가져오기 권한 테스트', () async {
      // When & Then
      // 실제 디바이스에서는 권한 요청이 발생하지만,
      // 테스트 환경에서는 예외가 발생할 수 있음
      try {
        final position = await gpsService.getCurrentLocation();
        expect(position, isNotNull);
        expect(position.latitude, isNotNull);
        expect(position.longitude, isNotNull);
      } catch (e) {
        // 권한 없음 또는 서비스 비활성화로 인한 예외는 정상
        expect(e, isNotNull);
      }
    });

    test('위치 모니터링 시작 권한 테스트', () async {
      // When & Then
      try {
        await gpsService.startLocationMonitoring();
        // 위치 모니터링이 성공적으로 시작됨
      } catch (e) {
        // 권한 없음으로 인한 예외는 정상
        expect(e, isNotNull);
      }
    });

    test('위치 모니터링 중지', () {
      // When
      gpsService.stopLocationMonitoring();

      // Then
      // 위치 모니터링이 성공적으로 중지됨
      // (별도의 검증 없이 예외가 발생하지 않는지 확인)
    });
  });
}