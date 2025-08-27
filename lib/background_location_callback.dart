import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'package:geolocator/geolocator.dart';
import 'package:church_attendance_app/services/supabase_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      debugPrint('백그라운드 작업 시작: $task');

      // 백그라운드에서 위치 권한 확인
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('백그라운드: 위치 서비스가 비활성화됨');
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('백그라운드: 위치 권한이 없음');
        return false;
      }

      // 현재 위치 가져오기
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      debugPrint('백그라운드 위치 수집: ${position.latitude}, ${position.longitude}');

      // Supabase 초기화 및 데이터 전송
      final supabaseService = SupabaseService();
      await supabaseService.init();

      // 현재 사용자 확인
      final currentUser = supabaseService.getCurrentUser();
      if (currentUser == null) {
        debugPrint('백그라운드: 사용자가 로그인되지 않았습니다.');
        return false;
      }

      // 현재 예배 서비스 정보 가져오기
      final currentService = await supabaseService.getCurrentService();
      if (currentService == null) {
        debugPrint('백그라운드: 현재 예배 서비스 정보를 찾을 수 없습니다.');
        return false;
      }

      // 교회 위치 확인 (하드코딩된 값 사용)
      const churchLatitude = 37.5665;
      const churchLongitude = 126.9780;
      const churchRadiusMeters = 80.0;

      // 거리 계산
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        churchLatitude,
        churchLongitude,
      );

      if (distance <= churchRadiusMeters) {
        final serviceId = currentService['id'] as String;
        final userId = currentUser.id;

        // 이미 출석 체크했는지 확인
        final existingRecord = await supabaseService.checkAttendanceRecord(
          userId: userId,
          serviceId: serviceId,
        );

        if (existingRecord == null) {
          // 출석 데이터 전송
          await supabaseService.submitAttendanceCheck(
            latitude: position.latitude,
            longitude: position.longitude,
            userId: userId,
            serviceId: serviceId,
          );

          debugPrint('백그라운드 출석 체크 성공');
        } else {
          debugPrint('백그라운드: 이미 출석 체크가 완료되었습니다.');
        }
      } else {
        debugPrint('백그라운드: 교회 범위 밖입니다. 거리: ${distance}m');
      }

      return true;
    } catch (e) {
      debugPrint('백그라운드 작업 오류: $e');
      return false;
    }
  });
}
