import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

/// 예배 시간 정보를 로컬에 저장하는 구조체
class LocalServiceInfo {
  final String serviceDate;
  final String startTime;
  final String endTime;
  final double churchLatitude;
  final double churchLongitude;
  final double churchRadiusMeters;
  final DateTime cachedAt;

  LocalServiceInfo({
    required this.serviceDate,
    required this.startTime,
    required this.endTime,
    required this.churchLatitude,
    required this.churchLongitude,
    required this.churchRadiusMeters,
    required this.cachedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'serviceDate': serviceDate,
      'startTime': startTime,
      'endTime': endTime,
      'churchLatitude': churchLatitude,
      'churchLongitude': churchLongitude,
      'churchRadiusMeters': churchRadiusMeters,
      'cachedAt': cachedAt.toIso8601String(),
    };
  }

  factory LocalServiceInfo.fromJson(Map<String, dynamic> json) {
    return LocalServiceInfo(
      serviceDate: json['serviceDate'],
      startTime: json['startTime'],
      endTime: json['endTime'],
      churchLatitude: json['churchLatitude'],
      churchLongitude: json['churchLongitude'],
      churchRadiusMeters: json['churchRadiusMeters'],
      cachedAt: DateTime.parse(json['cachedAt']),
    );
  }
}

/// 로컬 저장소를 통한 인증 세션 관리 서비스
/// Supabase 세션 정보를 영구적으로 저장하고 복원하는 기능 제공
class AuthStorageService {
  static const String _sessionKey = 'supabase_session';
  static const String _userKey = 'supabase_user';
  static const String _lastLoginTimeKey = 'last_login_time';
  static const String _serviceInfoKey = 'local_service_info';

  static final AuthStorageService _instance = AuthStorageService._internal();
  factory AuthStorageService() => _instance;
  AuthStorageService._internal();

  SharedPreferences? _prefs;

  /// SharedPreferences 초기화
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// 현재 세션 정보를 로컬에 저장
  Future<bool> saveSession({
    required String accessToken,
    required String refreshToken,
    required String userId,
    required String email,
    Map<String, dynamic>? userData,
  }) async {
    try {
      if (_prefs == null) {
        await init();
      }

      final sessionData = {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'userId': userId,
        'email': email,
        'savedAt': DateTime.now().toIso8601String(),
        if (userData != null) 'userData': userData,
      };

      final sessionJson = jsonEncode(sessionData);
      await _prefs!.setString(_sessionKey, sessionJson);
      await _prefs!.setString(_userKey, userId);
      await _prefs!.setString(
        _lastLoginTimeKey,
        DateTime.now().toIso8601String(),
      );

      return true;
    } catch (e) {
      debugPrint('세션 저장 오류: $e');
      return false;
    }
  }

  /// 저장된 세션 정보를 가져오기
  Future<Map<String, dynamic>?> getSavedSession() async {
    try {
      if (_prefs == null) {
        await init();
      }

      final sessionJson = _prefs!.getString(_sessionKey);
      if (sessionJson == null) {
        return null;
      }

      final sessionData = jsonDecode(sessionJson) as Map<String, dynamic>;

      // 세션 유효성 검사 (30일 이상 된 세션은 무효화)
      final savedAt = DateTime.parse(sessionData['savedAt'] as String);
      final now = DateTime.now();
      if (now.difference(savedAt).inDays > 30) {
        await clearSession();
        return null;
      }

      return sessionData;
    } catch (e) {
      debugPrint('세션 복원 오류: $e');
      return null;
    }
  }

  /// 저장된 세션 정보 삭제
  Future<bool> clearSession() async {
    try {
      if (_prefs == null) {
        await init();
      }

      await _prefs!.remove(_sessionKey);
      await _prefs!.remove(_userKey);
      await _prefs!.remove(_lastLoginTimeKey);

      return true;
    } catch (e) {
      debugPrint('세션 삭제 오류: $e');
      return false;
    }
  }

  /// 마지막 로그인 시간 가져오기
  Future<DateTime?> getLastLoginTime() async {
    try {
      if (_prefs == null) {
        await init();
      }

      final lastLoginStr = _prefs!.getString(_lastLoginTimeKey);
      if (lastLoginStr == null) {
        return null;
      }

      return DateTime.parse(lastLoginStr);
    } catch (e) {
      debugPrint('마지막 로그인 시간 조회 오류: $e');
      return null;
    }
  }

  /// 저장된 사용자 ID 가져오기
  Future<String?> getSavedUserId() async {
    try {
      if (_prefs == null) {
        await init();
      }

      return _prefs!.getString(_userKey);
    } catch (e) {
      debugPrint('저장된 사용자 ID 조회 오류: $e');
      return null;
    }
  }

  /// 세션이 존재하는지 확인
  Future<bool> hasSavedSession() async {
    try {
      final session = await getSavedSession();
      return session != null;
    } catch (e) {
      return false;
    }
  }

  /// 자동 로그인 가능 여부 확인
  Future<bool> canAutoLogin() async {
    try {
      final session = await getSavedSession();
      if (session == null) {
        return false;
      }

      // 마지막 로그인으로부터 7일 이내만 자동 로그인 허용
      final lastLoginTime = DateTime.parse(session['savedAt'] as String);
      final now = DateTime.now();
      final daysSinceLastLogin = now.difference(lastLoginTime).inDays;

      return daysSinceLastLogin <= 7;
    } catch (e) {
      return false;
    }
  }

  /// 로컬 예배 서비스 정보 저장
  Future<bool> saveLocalServiceInfo(LocalServiceInfo serviceInfo) async {
    try {
      if (_prefs == null) {
        await init();
      }

      final serviceJson = jsonEncode(serviceInfo.toJson());
      await _prefs!.setString(_serviceInfoKey, serviceJson);
      debugPrint('로컬 예배 서비스 정보 저장 완료: ${serviceInfo.serviceDate}');
      return true;
    } catch (e) {
      debugPrint('로컬 예배 서비스 정보 저장 오류: $e');
      return false;
    }
  }

  /// 로컬 예배 서비스 정보 가져오기
  Future<LocalServiceInfo?> getLocalServiceInfo() async {
    try {
      if (_prefs == null) {
        await init();
      }

      final serviceJson = _prefs!.getString(_serviceInfoKey);
      if (serviceJson == null) {
        return null;
      }

      final serviceInfo = LocalServiceInfo.fromJson(jsonDecode(serviceJson));

      // 캐시 유효성 검사 (1일 이상 된 데이터는 무효화)
      final now = DateTime.now();
      if (now.difference(serviceInfo.cachedAt).inDays > 1) {
        await _prefs!.remove(_serviceInfoKey);
        return null;
      }

      return serviceInfo;
    } catch (e) {
      debugPrint('로컬 예배 서비스 정보 조회 오류: $e');
      return null;
    }
  }

  /// 기기 시간으로 예배 시간 판단
  bool isWithinServiceTime(LocalServiceInfo serviceInfo) {
    try {
      final now = DateTime.now();
      final today = now.toIso8601String().split('T')[0];

      // 날짜 확인
      if (serviceInfo.serviceDate != today) {
        return false;
      }

      // 시간 파싱
      final startParts = serviceInfo.startTime.split(':');
      final endParts = serviceInfo.endTime.split(':');
      if (startParts.length < 2 || endParts.length < 2) {
        return true; // 시간 정보가 없으면 제한 없이 허용
      }

      // 예배 시작/종료 시간 계산
      final start = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(startParts[0]),
        int.parse(startParts[1]),
      );
      final end = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(endParts[0]),
        int.parse(endParts[1]),
      );

      // 여유 시간 적용 (시작 30분 전, 종료 30분 후)
      final startWithGrace = start.subtract(const Duration(minutes: 30));
      final endWithGrace = end.add(const Duration(minutes: 30));

      return now.isAfter(startWithGrace) && now.isBefore(endWithGrace);
    } catch (e) {
      debugPrint('예배 시간 판단 오류: $e');
      return true; // 오류 시 제한 없이 허용
    }
  }

  /// 기본 예배 시간 정보 생성 (네트워크 오류 시 사용)
  LocalServiceInfo createDefaultServiceInfo() {
    final now = DateTime.now();
    final today = now.toIso8601String().split('T')[0];

    return LocalServiceInfo(
      serviceDate: today,
      startTime: '11:00',
      endTime: '12:00',
      churchLatitude: 37.5665, // 서울 시청 기본값
      churchLongitude: 126.9780,
      churchRadiusMeters: 80.0,
      cachedAt: now,
    );
  }
}
