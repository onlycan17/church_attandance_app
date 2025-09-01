import 'package:church_attendance_app/services/supabase_service.dart';
import 'package:geolocator/geolocator.dart';

class AttendanceService {
  final SupabaseService _supabaseService;

  AttendanceService(this._supabaseService);

  Future<void> checkAttendance(Position position) async {
    try {
      bool isWithinRadius = await isWithinChurchRadius(position);

      if (isWithinRadius) {
        await _handleAttendanceCheck(position);
      }
    } catch (e) {
      print('출석 체크 중 오류: $e');
    }
  }

  Future<bool> isWithinChurchRadius(Position position) async {
    try {
      final currentService = await _supabaseService.getCurrentService();
      if (currentService == null) {
        print('현재 예배 서비스 정보를 찾을 수 없습니다.');
        return false;
      }

      final serviceId = (currentService['id'] as int);
      final churchLocation = await _supabaseService.getChurchLocation(
        serviceId,
      );
      if (churchLocation == null) {
        print('교회 위치 정보를 찾을 수 없습니다.');
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
      print('거리 계산 오류: $e');
      return false;
    }
  }

  Future<void> _handleAttendanceCheck(Position position) async {
    try {
      final currentUser = _supabaseService.getCurrentUser();
      if (currentUser == null) {
        print('사용자가 로그인되지 않았습니다.');
        return;
      }

      final currentService = await _supabaseService.getCurrentService();
      if (currentService == null) {
        print('현재 예배 서비스 정보를 찾을 수 없습니다.');
        return;
      }

      final serviceId = currentService['id'].toString();
      final userId = currentUser.id;

      final existingRecord = await _supabaseService.checkAttendanceRecord(
        userId: userId,
        serviceId: serviceId,
      );

      if (existingRecord != null) {
        print('이미 출석 체크가 완료되었습니다.');
        return;
      }

      await _supabaseService.submitAttendanceCheck(
        latitude: position.latitude,
        longitude: position.longitude,
        userId: userId,
        serviceId: serviceId,
      );

      print('출석 체크 데이터 전송 성공');
    } catch (e) {
      print('출석 체크 처리 중 오류: $e');
      rethrow;
    }
  }
}
