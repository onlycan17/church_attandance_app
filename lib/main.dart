import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:workmanager/workmanager.dart';
import 'package:church_attendance_app/screens/home_screen.dart';
import 'package:church_attendance_app/screens/login_screen.dart';
import 'package:church_attendance_app/services/supabase_service.dart';
import 'package:church_attendance_app/services/notification_service.dart';
import 'package:church_attendance_app/background_location_callback.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 환경 변수 로드
  await dotenv.load(fileName: ".env");

  // Supabase 초기화
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // 알림 서비스 초기화 (에러 처리 추가)
  try {
    await NotificationService().init();
    debugPrint('알림 서비스 초기화 성공');
  } catch (e) {
    debugPrint('알림 서비스 초기화 실패: $e');
    // 알림 서비스 실패해도 앱은 계속 실행
  }

  // 백그라운드 작업 초기화 (잠시 지연 후 실행)
  try {
    await Future.delayed(const Duration(milliseconds: 500));
    await Workmanager().initialize(callbackDispatcher);
    debugPrint('Workmanager 초기화 성공');
  } catch (e) {
    debugPrint('Workmanager 초기화 실패: $e');
    // Workmanager 실패해도 앱은 계속 실행
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '교회 예배 출석 체크',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthWrapper(),
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final SupabaseService _supabaseService = SupabaseService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    try {
      await _supabaseService.init();
      final currentUser = _supabaseService.getCurrentUser();

      if (mounted) {
        if (currentUser != null) {
          // 이미 로그인된 상태 - 홈 화면으로 이동
          Navigator.of(context).pushReplacementNamed('/home');
        } else {
          // 로그인되지 않은 상태 - 로그인 화면으로 이동
          Navigator.of(context).pushReplacementNamed('/login');
        }
      }
    } catch (e) {
      // 오류 발생 시 로그인 화면으로 이동
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : const Text('초기화 중...'),
      ),
    );
  }
}
