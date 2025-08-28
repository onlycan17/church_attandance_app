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
  int? _cachedUserIntId; // users 테이블의 내부 정수 ID 캐시

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
      final testQuery = await _supabase.from('users').select('email').limit(1);
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

      // 로그인 성공 시 public.users 테이블에 사용자 정보 동기화
      if (response.user != null) {
        await _syncUserToPublicTable(response.user!);
      }

      return response;
    } catch (e) {
      debugPrint('로그인 오류: $e');
      rethrow;
    }
  }

  // Supabase Auth 사용자 정보를 public.users 테이블에 동기화
  Future<void> _syncUserToPublicTable(User authUser) async {
    try {
      final userEmail = authUser.email;
      if (userEmail == null) {
        debugPrint('사용자 이메일 정보가 없습니다.');
        return;
      }

      // 이미 존재하는지 확인 (이메일로 확인)
      final existingUser = await _supabase
          .from('users')
          .select()
          .eq('email', userEmail)
          .maybeSingle();

      if (existingUser == null) {
        // 존재하지 않으면 새로 생성
        await _supabase.from('users').insert({
          'email': userEmail,
          'created_at': DateTime.now().toIso8601String(),
        });
        debugPrint('public.users 테이블에 새 사용자 정보 동기화 완료: $userEmail');
      } else {
        debugPrint('사용자 정보가 이미 존재합니다: $userEmail');
      }
    } catch (e) {
      debugPrint('사용자 정보 동기화 오류: $e');
      // 동기화 실패해도 로그인 과정은 계속 진행
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
    _cachedUserIntId = null; // 사용자 ID 캐시도 초기화
  }

  // 출석 체크 데이터 전송
  Future<void> submitAttendanceCheck({
    required double latitude,
    required double longitude,
    required String userId,
    required String serviceId,
  }) async {
    try {
      // auth.users UUID -> users 테이블 정수 ID 매핑
      final userIdInt = await _resolveInternalUserId(userId);
      if (userIdInt == null) {
        throw Exception('users 테이블에 현재 사용자가 없습니다. 관리자에게 문의하세요.');
      }
      final serviceIdInt = int.parse(serviceId);

      final response = await _supabase.from('attendance').insert({
        'user_id': userIdInt,
        'service_id': serviceIdInt,
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

      // 오늘 날짜에 해당하는 예배 서비스 조회
      final today = now.toIso8601String().split('T')[0];
      debugPrint('오늘 날짜로 예배 서비스 조회: $today');

      final response = await _supabase
          .from('services')
          .select()
          .eq('service_date', today);

      debugPrint('예배 서비스 쿼리 결과: ${response.length}개 발견');

      if (response.isEmpty) {
        debugPrint('오늘 예배 서비스가 없습니다. 테스트용 서비스를 생성합니다.');

        // 테스트용 서비스가 없으면 생성 (개발용)
        final testService = await _createTestService(today);
        if (testService != null) {
          _cachedCurrentService = testService;
          _serviceCacheTime = now;
          return testService;
        }

        return null;
      }

      // 첫 번째 서비스를 반환 (여러 개일 경우)
      final service = response[0];

      // 캐시에 저장
      _cachedCurrentService = service;
      _serviceCacheTime = now;

      return service;
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
      // auth.users UUID -> users 테이블 정수 ID 매핑
      final userIdInt = await _resolveInternalUserId(userId);
      if (userIdInt == null) {
        debugPrint('users 매핑 ID가 없어 출석 기록 확인을 건너뜁니다.');
        return null;
      }
      final serviceIdInt = int.parse(serviceId);

      final response = await _supabase
          .from('attendance')
          .select()
          .eq('user_id', userIdInt)
          .eq('service_id', serviceIdInt)
          .maybeSingle();

      return response;
    } catch (e) {
      debugPrint('출석 기록 확인 오류: $e');
      return null;
    }
  }

  // 위치 정보 가져오기
  Future<Map<String, dynamic>?> getChurchLocation(int serviceId) async {
    try {
      final response = await _supabase
          .from('locations')
          .select()
          .eq('service_id', serviceId)
          .maybeSingle();

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

  // 테스트용 예배 서비스 생성 (개발용)
  Future<Map<String, dynamic>?> _createTestService(String date) async {
    try {
      debugPrint('테스트용 예배 서비스 생성 시작: $date');

      // 현재 시간을 기준으로 예배 시간 설정 (오전 10시)
      final now = DateTime.now();

      final serviceData = {
        'service_date': date,
        'start_time': '10:00:00',
        'end_time': '12:00:00',
        'created_at': now.toIso8601String(),
      };

      final response = await _supabase
          .from('services')
          .insert(serviceData)
          .select()
          .single();

      debugPrint('테스트용 예배 서비스 생성 성공: ${response['id']}');

      // 해당 서비스의 위치 정보도 생성
      await _createTestLocation(response['id'] as int);

      return response;
    } catch (e) {
      debugPrint('테스트용 예배 서비스 생성 오류: $e');
      return null;
    }
  }

  // 테스트용 교회 위치 정보 생성 (개발용)
  Future<void> _createTestLocation(int serviceId) async {
    try {
      debugPrint('테스트용 교회 위치 정보 생성 시작: $serviceId');

      // 현재 위치를 교회 위치로 설정 (테스트용)
      const churchLatitude = 36.4255072; // 현재 위치 위도
      const churchLongitude = 127.3995609; // 현재 위치 경도

      final locationData = {
        'service_id': serviceId,
        'latitude': churchLatitude,
        'longitude': churchLongitude,
        'radius_meters': 80,
        'created_at': DateTime.now().toIso8601String(),
      };

      await _supabase.from('locations').insert(locationData);

      debugPrint('테스트용 교회 위치 정보 생성 성공');
    } catch (e) {
      debugPrint('테스트용 교회 위치 정보 생성 오류: $e');
    }
  }

  // auth.users의 이메일을 users 테이블의 내부 정수 ID로 변환 (캐싱 포함)
  Future<int?> _resolveInternalUserId(String authUserId) async {
    if (_cachedUserIntId != null) {
      return _cachedUserIntId;
    }
    try {
      // 현재 로그인된 사용자의 이메일로 매핑
      final email = _supabase.auth.currentUser?.email;
      if (email == null) {
        debugPrint('현재 사용자 이메일 정보를 찾을 수 없습니다.');
        return null;
      }

      final userRecord = await _supabase
          .from('users')
          .select('id')
          .eq('email', email)
          .maybeSingle();

      if (userRecord != null) {
        final id = userRecord['id'];
        final intId = id is int ? id : int.tryParse(id.toString());
        _cachedUserIntId = intId;
        debugPrint('사용자 ID 매핑 성공: $email -> $intId');
        return intId;
      } else {
        debugPrint('public.users 테이블에서 사용자 정보를 찾을 수 없습니다: $email');
        return null;
      }
    } catch (e) {
      debugPrint('사용자 ID 매핑 오류: $e');
      return null;
    }
  }
}
