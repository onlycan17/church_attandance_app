import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'package:geolocator/geolocator.dart';
import 'package:church_attendance_app/services/supabase_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      debugPrint('백그라운드 작업 시작: $task');

      // 현재 시간 확인 (KST)
      final now = DateTime.now();
      final kstOffset = const Duration(hours: 9);
      final kstNow = now.add(kstOffset);
      final currentHour = kstNow.hour;
      final currentMinute = kstNow.minute;

      // 테스트용 시간 제한: 오전 7시부터 12시까지
      if (currentHour < 7 || currentHour >= 12) {
        debugPrint(
          '백그라운드: GPS 수집 시간대가 아닙니다. 현재 시간: ${currentHour}:${currentMinute.toString().padLeft(2, '0')} KST',
        );
        return true; // 작업 취소가 아닌 정상 완료로 처리
      }

      // 30분 간격 확인 (정각 또는 30분에만 실행)
      if (currentMinute != 0 && currentMinute != 30) {
        debugPrint('백그라운드: 30분 간격이 아닙니다. 현재 분: $currentMinute');
        return true;
      }

      debugPrint(
        '백그라운드: GPS 수집 조건 만족 - 시간: ${currentHour}:${currentMinute.toString().padLeft(2, '0')} KST',
      );

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

      // 데이터베이스에서 교회 위치 정보 가져오기
      final serviceId = currentService['id'].toString();
      final churchLocation = await supabaseService.getChurchLocation(serviceId);
      if (churchLocation == null) {
        debugPrint('백그라운드: 교회 위치 정보를 찾을 수 없습니다.');
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

      // 거리 계산
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        churchLatitude,
        churchLongitude,
      );

      if (distance <= churchRadiusMeters) {
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

          debugPrint('백그라운드 출석 체크 성공 - 거리: ${distance}m');
        } else {
          debugPrint('백그라운드: 이미 출석 체크가 완료되었습니다.');
        }
      } else {}

      return true;
    } catch (e) {
      debugPrint('백그라운드 작업 오류: $e');
      return false;
    }
  });
}
