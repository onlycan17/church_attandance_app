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

      // 서비스 초기화
      final supabaseService = SupabaseService();
      await supabaseService.init();

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

      // 현재 위치 가져오기
      final position = await gpsService.getCurrentLocation();
      debugPrint('백그라운드 위치 확인: 위도 ${position.latitude}, 경도 ${position.longitude}');
      
      // 출석 체크
      await attendanceService.checkAttendance(position);
      
      debugPrint('백그라운드 출석 체크 완료');
      return Future.value(true);
    } catch (e) {
      debugPrint('백그라운드 작업 오류: $e');
      return Future.value(false);
    }
  });
}