import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
    try {
      // 환경 변수에서 Supabase 설정 읽기
      final supabaseUrl = dotenv.env['EXPO_PUBLIC_SUPABASE_URL'];
      final supabaseKey = dotenv.env['EXPO_PUBLIC_SUPABASE_KEY'];

      debugPrint('환경 변수 확인 - URL: $supabaseUrl');
      debugPrint('환경 변수 확인 - KEY: ${supabaseKey?.substring(0, 10)}...');

      if (supabaseUrl == null || supabaseKey == null) {
        throw Exception('Supabase 환경 변수가 설정되지 않았습니다. .env 파일을 확인하세요.');
      }

      if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
        throw Exception('Supabase 환경 변수가 비어있습니다. .env 파일을 확인하세요.');
      }

      // 이미 main.dart에서 초기화된 Supabase 클라이언트를 사용
      _supabase = Supabase.instance.client;
      debugPrint('Supabase 클라이언트 연결 성공');

      // 연결 테스트 - 간단한 쿼리로 테스트
      final testQuery = await _supabase.from('users').select('id').limit(1);
      debugPrint('Supabase 연결 테스트 성공: ${testQuery.length}개의 레코드 확인');
    } catch (e) {
      debugPrint('Supabase 연결 실패: $e');
      rethrow;
    }
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
