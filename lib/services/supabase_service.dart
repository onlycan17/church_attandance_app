import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:church_attendance_app/services/test_data_service.dart';
import 'package:church_attendance_app/services/auth_storage_service.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  late SupabaseClient _supabase;
  late TestDataService _testDataService;
  late AuthStorageService _authStorage;

  User? _cachedUser;
  Map<String, dynamic>? _cachedCurrentService;
  DateTime? _serviceCacheTime;
  final Duration _cacheDuration = const Duration(minutes: 30);
  int? _cachedUserIntId;
  String? _lastAccessToken;

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
      _authStorage = AuthStorageService();
      await _authStorage.init();
      debugPrint('Supabase 클라이언트 연결 성공');

      // 저장된 세션 복원 시도
      await _restoreSavedSession();
      // 네트워크가 없는 백그라운드 환경을 고려하여 즉시 쿼리 테스트는 수행하지 않음
    } catch (e) {
      debugPrint('Supabase 연결 실패: $e');
      // 백그라운드에서는 네트워크 부재가 빈번할 수 있으므로 fatal로 보지 않음
    }
  }

  SupabaseClient get client => _supabase;

  void registerExternalAccessToken(String token) {
    _lastAccessToken = token;
  }

  /// 현재 로그인 사용자의 내부 user_id(int) 조회(캐시 사용)
  Future<int?> getInternalUserId() async {
    final user = getCurrentUser();
    if (user == null) return null;
    return _resolveInternalUserId(user.id);
  }

  Future<AuthResponse> signIn(String username, String password) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: username,
        password: password,
      );

      if (response.user != null && response.session != null) {
        await _syncUserToPublicTable(response.user!);

        // 로그인 성공 시 세션 정보를 로컬에 저장
        await _saveSessionToLocal(
          accessToken: response.session!.accessToken,
          refreshToken: response.session!.refreshToken ?? '',
          user: response.user!,
        );

        debugPrint('로그인 성공 및 세션 저장 완료: ${response.user!.email}');
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

      // 로그아웃 시 로컬 세션도 삭제
      await _authStorage.clearSession();
      debugPrint('로그아웃 완료 및 로컬 세션 삭제');

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
    int? userIdIntOverride,
  }) async {
    try {
      int? userIdInt = userIdIntOverride;
      if (userIdInt == null) {
        final user = getCurrentUser();
        if (user != null) {
          userIdInt = await _resolveInternalUserId(user.id);
        } else {
          // currentUser가 없으면 access token 기반으로 이메일 추출 후 사용자 ID 매핑 시도
          final token =
              _lastAccessToken ?? _supabase.auth.currentSession?.accessToken;
          final email = token != null ? _decodeEmailFromJwt(token) : null;
          if (email != null) {
            userIdInt = await _resolveInternalUserIdByEmail(email);
          }
          if (userIdInt == null) {
            debugPrint('위치 로그 건너뜀: 로그인 사용자 없음');
            return;
          }
        }
      }

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

  Future<bool> tryInsertLocationLog({
    required double latitude,
    required double longitude,
    double? accuracy,
    String source = 'foreground',
    int? userIdIntOverride,
  }) async {
    try {
      int? userIdInt = userIdIntOverride;
      if (userIdInt == null) {
        final user = getCurrentUser();
        if (user != null) {
          userIdInt = await _resolveInternalUserId(user.id);
        } else {
          final token =
              _lastAccessToken ?? _supabase.auth.currentSession?.accessToken;
          final email = token != null ? _decodeEmailFromJwt(token) : null;
          if (email != null) {
            userIdInt = await _resolveInternalUserIdByEmail(email);
          }
        }
      }

      if (userIdInt == null) {
        return false;
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
      return true;
    } catch (e) {
      final kind = _classifyError(e);
      debugPrint('위치 로그 저장 실패[$kind]: $e');
      return false;
    }
  }

  Future<bool> bulkInsertLocationLogs(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return true;
    try {
      await _supabase.from('location_logs').insert(rows);
      return true;
    } catch (e) {
      final kind = _classifyError(e);
      debugPrint('위치 로그 일괄 저장 오류[$kind]: $e');
      return false;
    }
  }

  String _classifyError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('failed host lookup') || msg.contains('dns')) {
      return 'dns';
    }
    if (msg.contains('socketexception') || msg.contains('network')) {
      return 'network';
    }
    if (msg.contains('timeout')) {
      return 'timeout';
    }
    if (msg.contains('unauthorized') || msg.contains('401')) {
      return 'auth';
    }
    return 'unknown';
  }

  String? _decodeEmailFromJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      String normalized(String s) {
        var out = s.replaceAll('-', '+').replaceAll('_', '/');
        while (out.length % 4 != 0) {
          out += '=';
        }
        return out;
      }

      final payload = parts[1];
      final decoded = utf8.decode(base64.decode(normalized(payload)));
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      return map['email']?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<int?> _resolveInternalUserIdByEmail(String email) async {
    try {
      final userRecord = await _supabase
          .from('users')
          .select('id')
          .eq('email', email)
          .maybeSingle();
      if (userRecord != null) {
        final id = userRecord['id'];
        return id is int ? id : int.tryParse(id.toString());
      }
      return null;
    } catch (e) {
      debugPrint('사용자 ID 이메일 매핑 오류: $e');
      return null;
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

      // 네트워크 오류 감지 및 처리
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
      final errorMsg = e.toString();
      debugPrint('예배 서비스 정보 가져오기 오류: $e');

      // DNS 오류나 네트워크 오류인 경우 특별 처리
      if (errorMsg.contains('SocketException') ||
          errorMsg.contains('Failed host lookup') ||
          errorMsg.contains('No address associated with hostname')) {
        debugPrint('예배 서비스 조회 실패: 네트워크 연결 문제, 캐시된 데이터 사용 시도');

        // 캐시된 데이터가 있다면 반환, 없다면 기본 테스트 서비스 생성
        if (_cachedCurrentService != null) {
          return _cachedCurrentService;
        }

        // 네트워크 오류 시에도 기본 서비스 반환하여 위치 추적 계속
        final now = DateTime.now();
        final today = now.toIso8601String().split('T')[0];
        final testService = await _testDataService.createTestService(today);
        if (testService != null) {
          _cachedCurrentService = testService;
          _serviceCacheTime = now;
          debugPrint('네트워크 오류 시 테스트 서비스 생성');
          return testService;
        }
      }

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
      final errorMsg = e.toString();
      debugPrint('사용자 ID 매핑 오류: $e');

      // DNS 오류나 네트워크 오류인 경우 특별 처리
      if (errorMsg.contains('SocketException') ||
          errorMsg.contains('Failed host lookup') ||
          errorMsg.contains('No address associated with hostname')) {
        debugPrint('사용자 ID 매핑 실패: 네트워크 연결 문제');

        // 네트워크 오류 시에도 기본 사용자 ID 반환 (테스트용)
        // 실제 운영에서는 적절한 기본값 또는 오류 처리 필요
        debugPrint('네트워크 오류 시 기본 사용자 ID 사용 (테스트 모드)');
        return 1; // 테스트용 기본 ID
      }

      return null;
    }
  }

  /// 저장된 세션 정보를 Supabase에 복원
  Future<void> _restoreSavedSession() async {
    try {
      final savedSession = await _authStorage.getSavedSession();
      if (savedSession != null) {
        final refreshToken = savedSession['refreshToken'] as String;

        // 저장된 토큰으로 세션 복원 시도
        try {
          await _supabase.auth.setSession(refreshToken);
          debugPrint('저장된 세션 복원 성공: ${savedSession['email']}');
        } catch (e) {
          debugPrint('세션 복원 실패, 저장된 세션 삭제: $e');
          await _authStorage.clearSession();
        }
      } else {
        debugPrint('저장된 세션 정보가 없습니다.');
      }
    } catch (e) {
      debugPrint('세션 복원 중 오류: $e');
    }
  }

  /// 현재 세션 정보를 로컬에 저장
  Future<void> _saveSessionToLocal({
    required String accessToken,
    required String refreshToken,
    required User user,
  }) async {
    try {
      await _authStorage.saveSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        userId: user.id,
        email: user.email ?? '',
        userData: {
          'id': user.id,
          'email': user.email,
          'createdAt': user.createdAt,
        },
      );
    } catch (e) {
      debugPrint('세션 로컬 저장 오류: $e');
      // 로컬 저장 실패는 로그인 자체에는 영향을 주지 않음
    }
  }

  /// 자동 로그인 가능 여부 확인
  Future<bool> canAutoLogin() async {
    return await _authStorage.canAutoLogin();
  }

  /// 저장된 세션 정보가 있는지 확인
  Future<bool> hasSavedSession() async {
    return await _authStorage.hasSavedSession();
  }
}
