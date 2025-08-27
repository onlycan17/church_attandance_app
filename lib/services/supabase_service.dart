import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  late SupabaseClient _supabase;

  // 캐시를 위한 변수들
  User? _cachedUser;
  Map<String, dynamic>? _cachedCurrentService;
  DateTime? _serviceCacheTime;
  final Duration _cacheDuration = const Duration(minutes: 30); // 30분 캐시

  Future<void> init() async {
    // Supabase 초기화 - 실제 앱에서는 환경 변수에서 URL과 키를 가져와야 함
    final supabase = await Supabase.initialize(
      url: 'https://qqgvkfsgloyggqpnemol.supabase.co',
      anonKey: 'sbp_6269ac90378f3a770b45820e69139e1e3f696227',
    );
    _supabase = supabase.client;
  }

  SupabaseClient get client => _supabase;

  // 사용자 인증 관련 메서드
  Future<AuthResponse> signIn(String username, String password) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: username,
        password: password,
      );
      return response;
    } catch (e) {
      debugPrint('로그인 오류: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
      // 캐시 정리
      _clearCache();
    } catch (e) {
      debugPrint('로그아웃 오류: $e');
      rethrow;
    }
  }

  // 캐시 정리 메서드
  void _clearCache() {
    _cachedUser = null;
    _cachedCurrentService = null;
    _serviceCacheTime = null;
  }

  // 출석 체크 데이터 전송
  Future<void> submitAttendanceCheck({
    required double latitude,
    required double longitude,
    required String userId,
    required String serviceId,
  }) async {
    try {
      final response = await _supabase.from('attendance').insert({
        'user_id': userId,
        'service_id': serviceId,
        'is_present': true,
        'check_in_time': DateTime.now().toIso8601String(),
        'location_latitude': latitude,
        'location_longitude': longitude,
      });

      debugPrint('출석 체크 데이터 전송 성공: $response');
    } catch (e) {
      debugPrint('출석 체크 데이터 전송 오류: $e');
      rethrow;
    }
  }

  // 현재 사용자 정보 가져오기 (캐싱 적용)
  User? getCurrentUser() {
    if (_cachedUser != null) {
      return _cachedUser;
    }
    _cachedUser = _supabase.auth.currentUser;
    return _cachedUser;
  }

  // 예배 서비스 정보 가져오기 (현재 시간 기준) - 캐싱 적용
  Future<Map<String, dynamic>?> getCurrentService() async {
    try {
      final now = DateTime.now();

      // 캐시가 유효한지 확인
      if (_cachedCurrentService != null &&
          _serviceCacheTime != null &&
          now.difference(_serviceCacheTime!) < _cacheDuration) {
        return _cachedCurrentService;
      }

      final response = await _supabase
          .from('services')
          .select()
          .eq('service_date', now.toIso8601String().split('T')[0])
          .single();

      // 캐시에 저장
      _cachedCurrentService = response;
      _serviceCacheTime = now;

      return response;
    } catch (e) {
      debugPrint('예배 서비스 정보 가져오기 오류: $e');
      return null;
    }
  }

  // 출석 기록 확인
  Future<Map<String, dynamic>?> checkAttendanceRecord({
    required String userId,
    required String serviceId,
  }) async {
    try {
      final response = await _supabase
          .from('attendance')
          .select()
          .eq('user_id', userId)
          .eq('service_id', serviceId)
          .single();

      return response;
    } catch (e) {
      debugPrint('출석 기록 확인 오류: $e');
      return null;
    }
  }

  // 위치 정보 가져오기
  Future<Map<String, dynamic>?> getChurchLocation(String serviceId) async {
    try {
      final response = await _supabase
          .from('locations')
          .select()
          .eq('service_id', serviceId)
          .single();

      return response;
    } catch (e) {
      debugPrint('교회 위치 정보 가져오기 오류: $e');
      return null;
    }
  }

  // 로그인 상태 변경 스트림
  Stream<AuthState> onAuthStateChange() {
    return _supabase.auth.onAuthStateChange;
  }
}
