import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:church_attendance_app/services/test_data_service.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  late SupabaseClient _supabase;
  late TestDataService _testDataService;

  User? _cachedUser;
  Map<String, dynamic>? _cachedCurrentService;
  DateTime? _serviceCacheTime;
  final Duration _cacheDuration = const Duration(minutes: 30);
  int? _cachedUserIntId;

  Future<void> init() async {
    try {
      final supabaseUrl = dotenv.env['SUPABASE_URL'];
      final supabaseKey = dotenv.env['SUPABASE_ANON_KEY'];

      debugPrint('환경 변수 확인 - URL: $supabaseUrl');
      debugPrint('환경 변수 확인 - KEY: ${supabaseKey?.substring(0, 10)}...');

      if (supabaseUrl == null || supabaseKey == null) {
        throw Exception('Supabase 환경 변수가 설정되지 않았습니다. .env 파일을 확인하세요.');
      }

      if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
        throw Exception('Supabase 환경 변수가 비어있습니다. .env 파일을 확인하세요.');
      }

      _supabase = Supabase.instance.client;
      _testDataService = TestDataService(this);
      debugPrint('Supabase 클라이언트 연결 성공');
      // 네트워크가 없는 백그라운드 환경을 고려하여 즉시 쿼리 테스트는 수행하지 않음
    } catch (e) {
      debugPrint('Supabase 연결 실패: $e');
      // 백그라운드에서는 네트워크 부재가 빈번할 수 있으므로 fatal로 보지 않음
    }
  }

  SupabaseClient get client => _supabase;

  Future<AuthResponse> signIn(String username, String password) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: username,
        password: password,
      );

      if (response.user != null) {
        await _syncUserToPublicTable(response.user!);
      }

      return response;
    } catch (e) {
      debugPrint('로그인 오류: $e');
      rethrow;
    }
  }

  Future<void> _syncUserToPublicTable(User authUser) async {
    try {
      final userEmail = authUser.email;
      if (userEmail == null) {
        debugPrint('사용자 이메일 정보가 없습니다.');
        return;
      }

      final existingUser = await _supabase
          .from('users')
          .select()
          .eq('email', userEmail)
          .maybeSingle();

      if (existingUser == null) {
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
    }
  }

  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
      _clearCache();
    } catch (e) {
      debugPrint('로그아웃 오류: $e');
      rethrow;
    }
  }

  Map<String, String?> getCurrentTokens() {
    try {
      final session = _supabase.auth.currentSession;
      final access = session?.accessToken;
      final refresh = session?.refreshToken;
      return {'accessToken': access, 'refreshToken': refresh};
    } catch (e) {
      debugPrint('토큰 조회 오류: $e');
      return {'accessToken': null, 'refreshToken': null};
    }
  }

  void _clearCache() {
    _cachedUser = null;
    _cachedCurrentService = null;
    _serviceCacheTime = null;
    _cachedUserIntId = null;
  }

  Future<void> submitAttendanceCheck({
    required double latitude,
    required double longitude,
    required String userId,
    required String serviceId,
  }) async {
    try {
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

  Future<void> insertLocationLog({
    required double latitude,
    required double longitude,
    double? accuracy,
    String source = 'foreground',
  }) async {
    try {
      final user = getCurrentUser();
      if (user == null) {
        debugPrint('위치 로그 건너뜀: 로그인 사용자 없음');
        return;
      }

      final userIdInt = await _resolveInternalUserId(user.id);
      if (userIdInt == null) {
        debugPrint('위치 로그 건너뜀: users 매핑 ID 없음');
        return;
      }

      int? serviceIdInt;
      final currentService = await getCurrentService();
      if (currentService != null) {
        final sid = currentService['id'];
        serviceIdInt = sid is int ? sid : int.tryParse(sid.toString());
      }

      final payload = <String, dynamic>{
        'user_id': userIdInt,
        'latitude': latitude,
        'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
        'source': source,
        'captured_at': DateTime.now().toIso8601String(),
        if (serviceIdInt != null) 'service_id': serviceIdInt,
      };

      await _supabase.from('location_logs').insert(payload);
      debugPrint('위치 로그 저장 완료: $source, $latitude,$longitude');
    } catch (e) {
      debugPrint('위치 로그 저장 오류: $e');
    }
  }

  User? getCurrentUser() {
    if (_cachedUser != null) {
      return _cachedUser;
    }
    _cachedUser = _supabase.auth.currentUser;
    return _cachedUser;
  }

  Future<Map<String, dynamic>?> getCurrentService() async {
    try {
      final now = DateTime.now();

      if (_cachedCurrentService != null &&
          _serviceCacheTime != null &&
          now.difference(_serviceCacheTime!) < _cacheDuration) {
        return _cachedCurrentService;
      }

      final today = now.toIso8601String().split('T')[0];
      debugPrint('오늘 날짜로 예배 서비스 조회: $today');

      final response = await _supabase
          .from('services')
          .select()
          .eq('service_date', today);

      debugPrint('예배 서비스 쿼리 결과: ${response.length}개 발견');

      if (response.isEmpty) {
        debugPrint('오늘 예배 서비스가 없습니다. 테스트용 서비스를 생성합니다.');

        final testService = await _testDataService.createTestService(today);
        if (testService != null) {
          _cachedCurrentService = testService;
          _serviceCacheTime = now;
          return testService;
        }

        return null;
      }

      final service = response[0];

      _cachedCurrentService = service;
      _serviceCacheTime = now;

      return service;
    } catch (e) {
      debugPrint('예배 서비스 정보 가져오기 오류: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> checkAttendanceRecord({
    required String userId,
    required String serviceId,
  }) async {
    try {
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

  Stream<AuthState> onAuthStateChange() {
    return _supabase.auth.onAuthStateChange;
  }

  Future<int?> _resolveInternalUserId(String authUserId) async {
    if (_cachedUserIntId != null) {
      return _cachedUserIntId;
    }
    try {
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
