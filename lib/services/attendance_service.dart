import 'package:church_attendance_app/services/supabase_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

class AttendanceService {
  final SupabaseService _supabaseService;

  AttendanceService(this._supabaseService);

  static const int graceBeforeMinutes = 30; // 예배 시작 전 허용 시간
  static const int graceAfterMinutes = 30; // 예배 종료 후 허용 시간

  Future<void> checkAttendance(Position position) async {
    try {
      // 시간대 확인
      final currentService = await _supabaseService.getCurrentService();
      if (currentService != null) {
        final now = DateTime.now();
        final withinTime = _isWithinServiceWindow(now, currentService);
        if (!withinTime) {
          debugPrint('출석 체크 스킵: 예배 시간대가 아님');
        } else {
          final isWithinRadius = await isWithinChurchRadius(position);
          if (isWithinRadius) {
            await _handleAttendanceCheck(position);
          }
        }
      }
      // 위치 히스토리 로그는 출석 여부와 무관하게 기록(테스트용)
      await _supabaseService.insertLocationLog(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        source: 'foreground',
      );
    } catch (e) {
      debugPrint('출석 체크 중 오류: $e');
    }
  }

  Future<bool> isWithinChurchRadius(Position position) async {
    try {
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

  Future<void> _handleAttendanceCheck(Position position) async {
    try {
      final currentUser = _supabaseService.getCurrentUser();
      if (currentUser == null) {
        debugPrint('사용자가 로그인되지 않았습니다.');
        return;
      }

      final currentService = await _supabaseService.getCurrentService();
      if (currentService == null) {
        debugPrint('현재 예배 서비스 정보를 찾을 수 없습니다.');
        return;
      }

      final serviceId = currentService['id'].toString();
      final userId = currentUser.id;

      final existingRecord = await _supabaseService.checkAttendanceRecord(
        userId: userId,
        serviceId: serviceId,
      );

      if (existingRecord != null) {
        debugPrint('이미 출석 체크가 완료되었습니다.');
        return;
      }

      await _supabaseService.submitAttendanceCheck(
        latitude: position.latitude,
        longitude: position.longitude,
        userId: userId,
        serviceId: serviceId,
      );

      debugPrint('출석 체크 데이터 전송 성공');
    } catch (e) {
      debugPrint('출석 체크 처리 중 오류: $e');
      rethrow;
    }
  }

  Future<void> logBackgroundLocation(
    Position position, {
    int? userIdIntOverride,
  }) async {
    await _supabaseService.insertLocationLog(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      source: 'background',
      userIdIntOverride: userIdIntOverride,
    );
  }

  Future<int?> getInternalUserId() async {
    return _supabaseService.getInternalUserId();
  }

  bool _isWithinServiceWindow(DateTime now, Map<String, dynamic> service) {
    try {
      final dateStr = service['service_date']?.toString();
      final startStr = service['start_time']?.toString();
      final endStr = service['end_time']?.toString();
      if (dateStr == null || startStr == null || endStr == null) {
        // 시간 정보가 없으면 시간 제한 없이 허용(프로토타입 기본)
        return true;
      }

      final startParts = startStr.split(':');
      final endParts = endStr.split(':');
      if (startParts.length < 2 || endParts.length < 2) {
        return true;
      }

      final date = DateTime.parse('${dateStr}T00:00:00');
      final start = DateTime(
        date.year,
        date.month,
        date.day,
        int.parse(startParts[0]),
        int.parse(startParts[1]),
      );
      final end = DateTime(
        date.year,
        date.month,
        date.day,
        int.parse(endParts[0]),
        int.parse(endParts[1]),
      );

      final startWithGrace = start.subtract(
        const Duration(minutes: graceBeforeMinutes),
      );
      final endWithGrace = end.add(const Duration(minutes: graceAfterMinutes));
      final within = now.isAfter(startWithGrace) && now.isBefore(endWithGrace);
      return within;
    } catch (e) {
      debugPrint('예배 시간 파싱 오류, 시간 제한 미적용: $e');
      return true;
    }
  }
}
