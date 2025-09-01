import 'package:church_attendance_app/view_models/home_view_model.dart';
import 'package:church_attendance_app/view_models/login_view_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  // SupabaseService 초기화
  final supabaseService = SupabaseService();
  await supabaseService.init();

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

  runApp(MyApp(supabaseService: supabaseService));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.supabaseService});
  final SupabaseService supabaseService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SupabaseService>.value(value: supabaseService),
        Provider(create: (_) => NotificationService()),
        ChangeNotifierProvider(create: (_) => LoginViewModel()),
        ChangeNotifierProvider(create: (_) => HomeViewModel()),
      ],
      child: MaterialApp(
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
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    return StreamBuilder<User?>(
      stream: supabaseService.client.auth.onAuthStateChange.map((event) => event.session?.user),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasData) {
          return const HomeScreen();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}