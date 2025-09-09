import 'package:church_attendance_app/services/supabase_service.dart';
import 'package:church_attendance_app/services/auth_storage_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

class AttendanceService {
  final SupabaseService _supabaseService;
  final AuthStorageService _authStorage = AuthStorageService();

  AttendanceService(this._supabaseService);

  static const int graceBeforeMinutes = 30; // 예배 시작 전 허용 시간
  static const int graceAfterMinutes = 30; // 예배 종료 후 허용 시간

  Future<void> checkAttendance(Position position) async {
    try {
      // 사용자 인증 상태 확인
      final currentUser = _supabaseService.getCurrentUser();
      if (currentUser == null) {
        debugPrint('출석 체크 스킵: 사용자가 로그인되지 않음');
        // 위치는 로그하지만 출석 체크는 스킵
        await _supabaseService.insertLocationLog(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          source: 'foreground',
        );
        return;
      }

      // 기기 시간을 활용한 예배 시간 판단 (네트워크 요청 최소화)
      bool isServiceTime = false;

      try {
        // 1. 로컬 저장소에서 예배 정보 먼저 확인
        final localServiceInfo = await _authStorage.getLocalServiceInfo();
        if (localServiceInfo != null) {
          isServiceTime = _authStorage.isWithinServiceTime(localServiceInfo);
          debugPrint('로컬 예배 시간 판단: ${isServiceTime ? '예배 시간' : '예배 시간 아님'}');
        } else {
          debugPrint('로컬 예배 정보 없음, 네트워크에서 조회 시도');
        }

        // 2. 로컬 정보가 없거나 시간이 맞지 않으면 네트워크에서 조회
        if (!isServiceTime) {
          try {
            final currentService = await _supabaseService.getCurrentService();
            if (currentService != null) {
              // 로컬에 저장
              await _cacheServiceInfo(currentService);

              // 다시 로컬 시간으로 판단
              final cachedInfo = await _authStorage.getLocalServiceInfo();
              if (cachedInfo != null) {
                isServiceTime = _authStorage.isWithinServiceTime(cachedInfo);
                debugPrint(
                  '네트워크 조회 후 예배 시간 판단: ${isServiceTime ? '예배 시간' : '예배 시간 아님'}',
                );
              }
            } else {
              debugPrint('예배 서비스 정보 없음, 기본 시간으로 판단');
              // 기본 예배 시간 (주일 오전 11시)으로 판단
              isServiceTime = _isDefaultServiceTime();
            }
          } catch (e) {
            final errorMsg = e.toString();
            if (errorMsg.contains('SocketException') ||
                errorMsg.contains('Failed host lookup') ||
                errorMsg.contains('No address associated with hostname')) {
              debugPrint('출석 체크: 네트워크 오류로 예배 서비스 정보 조회 실패');
              // 네트워크 오류 처리
              // 기본 예배 시간으로 판단
              isServiceTime = _isDefaultServiceTime();
            } else {
              debugPrint('출석 체크 중 예배 서비스 조회 오류: $e');
              // 오류 시 기본적으로 허용
              isServiceTime = true;
            }
          }
        }

        // 예배 시간일 때만 출석 체크
        if (isServiceTime) {
          final isWithinRadius = await isWithinChurchRadius(position);
          if (isWithinRadius) {
            await _handleAttendanceCheck(position);
          }
        } else {
          debugPrint('출석 체크 스킵: 예배 시간대가 아님');
        }
      } catch (e) {
        debugPrint('출석 체크 중 시간 판단 오류: $e');
        // 오류 시 기본적으로 허용
        final isWithinRadius = await isWithinChurchRadius(position);
        if (isWithinRadius) {
          await _handleAttendanceCheck(position);
        }
      }

      // 위치 히스토리 로그는 출석 여부와 무관하게 기록(테스트용)
      // 네트워크 오류 시에도 로컬 큐에 저장됨
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
      final errorMsg = e.toString();
      if (errorMsg.contains('SocketException') ||
          errorMsg.contains('Failed host lookup') ||
          errorMsg.contains('No address associated with hostname')) {
        debugPrint('거리 계산: 네트워크 오류로 교회 위치 정보 조회 실패');
        // 네트워크 오류 시 기본 반경 80m로 간단한 거리 계산 시도
        // 실제 운영에서는 적절한 기본값 사용
        return false;
      }
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
    try {
      // 백그라운드에서도 사용자 인증 상태 확인
      final currentUser = _supabaseService.getCurrentUser();
      if (currentUser == null && userIdIntOverride == null) {
        debugPrint('백그라운드: 사용자가 로그인되지 않아 위치 로깅 스킵');
        return;
      }

      // 네트워크 오류 발생 시에도 위치 로깅 시도 (로컬 큐로 저장됨)
      try {
        await _supabaseService.insertLocationLog(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          source: 'background',
          userIdIntOverride: userIdIntOverride,
        );
        debugPrint(
          '백그라운드 위치 로깅 성공: ${position.latitude}, ${position.longitude}',
        );
      } catch (e) {
        final errorMsg = e.toString();
        if (errorMsg.contains('SocketException') ||
            errorMsg.contains('Failed host lookup') ||
            errorMsg.contains('No address associated with hostname')) {
          debugPrint('백그라운드: 네트워크 오류로 위치 로깅 실패, 큐에 저장됨: $e');
        } else {
          debugPrint('백그라운드 위치 로깅 오류: $e');
        }
      }
    } catch (e) {
      debugPrint('백그라운드 위치 로깅 오류: $e');
      // 백그라운드에서는 오류를 던지지 않고 로그만 남김
    }
  }

  Future<int?> getInternalUserId() async {
    return _supabaseService.getInternalUserId();
  }

  /// 기본 예배 시간 판단 (네트워크 오류 시 사용)
  bool _isDefaultServiceTime() {
    try {
      final now = DateTime.now();
      final dayOfWeek = now.weekday; // 1 = Monday, 7 = Sunday

      // 주일(일요일) 오전 10시-12시를 기본 예배 시간으로 설정
      if (dayOfWeek == DateTime.sunday) {
        final start = DateTime(now.year, now.month, now.day, 9, 30); // 9:30
        final end = DateTime(now.year, now.month, now.day, 12, 30); // 12:30

        final startWithGrace = start.subtract(const Duration(minutes: 30));
        final endWithGrace = end.add(const Duration(minutes: 30));

        return now.isAfter(startWithGrace) && now.isBefore(endWithGrace);
      }

      // 주일이 아닌 경우에는 제한 없이 허용 (테스트용)
      return true;
    } catch (e) {
      debugPrint('기본 예배 시간 판단 오류: $e');
      return true; // 오류 시 제한 없이 허용
    }
  }

  /// 예배 서비스 정보를 로컬에 캐시
  Future<void> _cacheServiceInfo(Map<String, dynamic> service) async {
    try {
      final dateStr = service['service_date']?.toString() ?? '';
      final startStr = service['start_time']?.toString() ?? '11:00';
      final endStr = service['end_time']?.toString() ?? '12:00';

      // 교회 위치 정보 가져오기
      double churchLatitude = 37.5665; // 서울 시청 기본값
      double churchLongitude = 126.9780;
      double churchRadiusMeters = 80.0;

      try {
        final serviceId = service['id'] as int;
        final churchLocation = await _supabaseService.getChurchLocation(
          serviceId,
        );
        if (churchLocation != null) {
          churchLatitude = double.parse(churchLocation['latitude'].toString());
          churchLongitude = double.parse(
            churchLocation['longitude'].toString(),
          );
          churchRadiusMeters = double.parse(
            churchLocation['radius_meters'].toString(),
          );
        }
      } catch (e) {
        debugPrint('교회 위치 정보 조회 실패, 기본값 사용: $e');
      }

      final serviceInfo = LocalServiceInfo(
        serviceDate: dateStr,
        startTime: startStr,
        endTime: endStr,
        churchLatitude: churchLatitude,
        churchLongitude: churchLongitude,
        churchRadiusMeters: churchRadiusMeters,
        cachedAt: DateTime.now(),
      );

      await _authStorage.saveLocalServiceInfo(serviceInfo);
      debugPrint('예배 서비스 정보 로컬 캐시 완료: $dateStr');
    } catch (e) {
      debugPrint('예배 서비스 정보 캐시 오류: $e');
    }
  }

}
