import 'package:church_attendance_app/services/attendance_service.dart';
import 'package:church_attendance_app/services/gps_service.dart';
import 'package:church_attendance_app/services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // 백그라운드 Isolate에서 Flutter 엔진 바인딩 및 서비스 초기화
    WidgetsFlutterBinding.ensureInitialized();
    await dotenv.load(fileName: ".env");
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );

    try {
      final supabaseService = SupabaseService();
      await supabaseService.init();

      final gpsService = GPSService();
      final attendanceService = AttendanceService(supabaseService);
      gpsService.setAttendanceService(attendanceService);

      final position = await gpsService.getCurrentLocation();
      if (position != null) {
        await attendanceService.checkAttendance(position);
      }

      return Future.value(true);
    } catch (e) {
      // 에러 로깅을 위해 print 대신 debugPrint 사용 고려
      debugPrint(e.toString());
      return Future.value(false);
    }
  });
}