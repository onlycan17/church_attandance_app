# 교회 출석 체크 애플리케이션 - 코딩 규칙 및 개발 가이드라인

## 1. 프로젝트 개요

- **프로젝트명**: 교회 출석 체크 애플리케이션
- **목적**: 교회 구성원의 예배 출석을 GPS 기반으로 자동화
- **기술 스택**: Flutter, Supabase, Geolocator, WorkManager
- **대상 플랫폼**: iOS, Android

## 2. 기술 스택 및 아키텍처

### 2.1 필수 기술 스택
- **Flutter**: ^3.9.0 이상
- **Dart**: ^3.5.0 이상
- **Supabase**: ^2.7.0 (데이터베이스 및 인증)
- **Geolocator**: ^14.0.2 (GPS 위치 수집)
- **WorkManager**: ^0.9.0 (백그라운드 작업)
- **Flutter Local Notifications**: ^19.0.0 (알림)

### 2.2 아키텍처 패턴
- **MVVM 패턴**: View-ViewModel-Model 구조
- **Service Layer**: 비즈니스 로직 분리
- **Singleton 패턴**: SupabaseService 등 핵심 서비스
- **Provider 패턴**: 상태 관리 (필요시)

## 3. 코딩 스타일 및 규칙

### 3.1 네이밍 규칙
```dart
// 클래스명: PascalCase
class ChurchAttendanceApp extends StatelessWidget

// 메서드명: camelCase
void checkAttendance()

// 변수명: camelCase
String userEmail = 'test@test.com';

// 상수명: UPPER_SNAKE_CASE
const String API_BASE_URL = 'https://api.example.com';

// 파일명: snake_case.dart
church_attendance_app.dart
```

### 3.2 코드 구조
```dart
// 1. Import statements
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 2. Constants (if any)
// 3. Class definition
class LoginScreen extends StatefulWidget {
  // 4. Constructor
  const LoginScreen({super.key});

  // 5. Override methods
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

// 6. Private class
class _LoginScreenState extends State<LoginScreen> {
  // 7. Fields
  final TextEditingController _emailController = TextEditingController();

  // 8. Lifecycle methods
  @override
  void initState() {
    super.initState();
    // initialization code
  }

  // 9. Public methods
  Future<void> _login() async {
    // implementation
  }

  // 10. Build method
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // UI implementation
    );
  }

  // 11. Dispose method
  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }
}
```

### 3.3 Flutter 위젯 규칙
- **StatelessWidget vs StatefulWidget**: 상태가 필요할 때만 StatefulWidget 사용
- **const 생성자**: 가능한 모든 위젯에 const 사용
- **Key 사용**: 동적 리스트에서는 UniqueKey 또는 ValueKey 사용
- **위젯 분리**: 복잡한 위젯은 별도 메서드로 분리

```dart
// ✅ Good
const Icon(Icons.church, size: 80, color: Colors.blue)

// ❌ Bad
Icon(Icons.church, size: 80, color: Colors.blue)
```

### 3.4 에러 처리
```dart
// ✅ Good: try-catch with proper error handling
try {
  final response = await supabaseService.signIn(email, password);
  if (response.user != null) {
    // Success handling
  }
} catch (e) {
  debugPrint('로그인 오류: $e');
  setState(() {
    _errorMessage = '로그인 중 오류가 발생했습니다: ${e.toString()}';
  });
}

// ❌ Bad: Bare catch
try {
  // some code
} catch (e) {
  print(e); // Don't use print in production
}
```

## 4. 개발 워크플로우

### 4.1 Git 워크플로우
```bash
# 1. 메인 브랜치에서 작업 브랜치 생성
git checkout -b feature/login-screen

# 2. 작업 완료 후 커밋
git add .
git commit -m "feat: 로그인 화면 구현

- 이메일/비밀번호 입력 필드 추가
- Supabase 인증 연동
- 에러 처리 및 로딩 상태 구현"

# 3. 메인 브랜치로 병합
git checkout main
git pull origin main
git merge feature/login-screen
git push origin main
```

### 4.2 커밋 메시지 규칙
```
feat: 새로운 기능 추가
fix: 버그 수정
docs: 문서 수정
style: 코드 포맷팅 (기능 변경 없음)
refactor: 코드 리팩토링
test: 테스트 코드 추가/수정
chore: 기타 작업 (빌드, 설정 등)
```

### 4.3 코드 리뷰 체크리스트
- [ ] 코딩 스타일 준수
- [ ] 에러 처리 구현
- [ ] 테스트 코드 작성
- [ ] 문서 업데이트
- [ ] 성능 고려사항 검토

## 5. Supabase 데이터베이스 규칙

### 5.1 테이블 구조
```sql
-- users 테이블 (사용자 정보)
CREATE TABLE users (
  id INTEGER PRIMARY KEY,
  username VARCHAR(255) UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

-- services 테이블 (예배 서비스 정보)
CREATE TABLE services (
  id INTEGER PRIMARY KEY,
  service_date DATE NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

-- attendance 테이블 (출석 기록)
CREATE TABLE attendance (
  id INTEGER PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  service_id INTEGER REFERENCES services(id),
  is_present BOOLEAN DEFAULT FALSE,
  check_in_time TIMESTAMP,
  location_latitude DECIMAL(10,8),
  location_longitude DECIMAL(11,8),
  created_at TIMESTAMP DEFAULT NOW()
);

-- locations 테이블 (교회 위치 정보)
CREATE TABLE locations (
  id INTEGER PRIMARY KEY,
  service_id INTEGER REFERENCES services(id),
  latitude DECIMAL(10,8) NOT NULL,
  longitude DECIMAL(11,8) NOT NULL,
  radius_meters INTEGER DEFAULT 80,
  created_at TIMESTAMP DEFAULT NOW()
);
```

### 5.2 RLS (Row Level Security) 정책
```sql
-- 출석 기록은 본인만 조회 가능
ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own attendance" ON attendance
FOR SELECT USING (auth.uid()::text = user_id::text);

-- 출석 기록은 본인만 삽입 가능
CREATE POLICY "Users can insert own attendance" ON attendance
FOR INSERT WITH CHECK (auth.uid()::text = user_id::text);
```

## 6. GPS 및 위치 서비스 규칙

### 6.1 권한 요청
```dart
// ✅ Good: 권한 요청 후 상태 확인
LocationPermission permission = await Geolocator.requestPermission();
if (permission == LocationPermission.denied) {
  // 권한 거부 처리
  return;
}

// 위치 서비스 활성화 확인
bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
if (!serviceEnabled) {
  // 위치 서비스 비활성화 처리
  return;
}
```

### 6.2 위치 정확도 설정
```dart
// ✅ Good: 적절한 정확도 설정
Position position = await Geolocator.getCurrentPosition(
  desiredAccuracy: LocationAccuracy.high,
  timeLimit: const Duration(seconds: 10),
);
```

### 6.3 백그라운드 위치 수집
```dart
// WorkManager를 사용한 백그라운드 작업
await Workmanager().registerPeriodicTask(
  'location_check',
  'check_location',
  frequency: const Duration(minutes: 15),
  constraints: Constraints(
    networkType: NetworkType.connected,
    requiresBatteryNotLow: true,
  ),
);
```

## 7. 테스트 및 품질 관리

### 7.1 단위 테스트
```dart
// GPS 서비스 테스트 예시
test('현재 위치 정확도 검증', () async {
  final gpsService = GPSService();

  final position = await gpsService.getCurrentLocation();

  expect(position.accuracy, lessThan(100.0));
  expect(position.latitude, isNotNull);
  expect(position.longitude, isNotNull);
});
```

### 7.2 위젯 테스트
```dart
testWidgets('로그인 화면 UI 테스트', (WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

  expect(find.text('교회 출석 체크 시스템'), findsOneWidget);
  expect(find.byType(TextField), findsNWidgets(2));
  expect(find.byType(ElevatedButton), findsOneWidget);
});
```

### 7.3 통합 테스트
```dart
testWidgets('전체 출석 체크 플로우', (WidgetTester tester) async {
  await tester.pumpWidget(const MyApp());

  // 로그인
  await tester.enterText(find.byType(TextField).first, 'test@test.com');
  await tester.enterText(find.byType(TextField).last, 'test123');
  await tester.tap(find.text('로그인'));
  await tester.pumpAndSettle();

  // 출석 체크
  await tester.tap(find.text('수동 출석 체크'));
  await tester.pumpAndSettle();

  expect(find.text('출석 체크 완료!'), findsOneWidget);
});
```

## 8. 성능 및 최적화

### 8.1 메모리 관리
- 불필요한 객체 생성 피하기
- 위젯 dispose 시 리소스 정리
- 이미지 캐싱 사용
- 리스트뷰에서 ListView.builder 사용

### 8.2 배터리 최적화
```dart
// 위치 업데이트 최적화
await Geolocator.getPositionStream(
  desiredAccuracy: LocationAccuracy.medium,
  distanceFilter: 10, // 10미터 이상 이동 시에만 업데이트
  timeInterval: 30000, // 30초 간격
).listen((Position position) {
  // 위치 데이터 처리
});
```

### 8.3 네트워크 최적화
- 불필요한 API 호출 피하기
- 캐싱 전략 구현
- 배치 처리 사용
- 오프라인 모드 지원

## 9. 보안 가이드라인

### 9.1 데이터 보호
- 민감한 정보 암호화 저장
- HTTPS 통신만 허용
- API 키 노출 방지
- 사용자 데이터 최소 수집

### 9.2 인증 보안
```dart
// ✅ Good: 안전한 인증 처리
final response = await supabase.auth.signInWithPassword(
  email: email,
  password: password,
);

// 세션 만료 처리
supabase.auth.onAuthStateChange.listen((event) {
  if (event.event == AuthChangeEvent.signedOut) {
    // 로그아웃 처리
  }
});
```

## 10. 배포 및 운영

### 10.1 빌드 설정
```yaml
# pubspec.yaml
version: 1.0.0+1

environment:
  sdk: ^3.9.0
  flutter: ^3.24.0
```

### 10.2 플랫폼별 설정
- **Android**: 위치 권한, 백그라운드 실행 권한 설정
- **iOS**: 위치 권한, 백그라운드 모드 설정
- **Info.plist 및 AndroidManifest.xml**에 필요한 권한 추가

### 10.3 모니터링 및 로깅
```dart
// 디버그 모드에서만 로깅
if (kDebugMode) {
  debugPrint('디버그 메시지: $data');
}

// 프로덕션에서는 별도 로깅 서비스 사용
void logError(String message, dynamic error) {
  // Firebase Crashlytics, Sentry 등 사용
}
```

## 11. 유지보수 및 확장

### 11.1 코드 모듈화
- 기능별로 파일 분리
- 공통 로직은 별도 서비스로 분리
- 재사용 가능한 위젯 생성

### 11.2 버전 관리
- 의미 있는 버전 번호 사용 (Semantic Versioning)
- 변경사항에 대한 CHANGELOG 유지
- 하위 호환성 유지

### 11.3 문서화
- 모든 public 메서드에 문서화 주석 추가
- 복잡한 로직에 대한 설명 추가
- API 변경 시 문서 업데이트

---

## 부록: 자주 묻는 질문 (FAQ)

### Q: 언제 StatefulWidget을 사용해야 하나요?
A: 위젯의 상태가 변경될 때 (사용자 입력, 데이터 업데이트 등) StatefulWidget을 사용하세요.

### Q: 백그라운드 위치 수집은 어떻게 구현하나요?
A: WorkManager를 사용하여 주기적으로 위치를 수집하고, Supabase에 저장하세요.

### Q: 에러 처리는 어떻게 해야 하나요?
A: 모든 비동기 작업에 try-catch를 사용하고, 사용자에게 적절한 피드백을 제공하세요.

### Q: 테스트는 어떻게 작성하나요?
A: 단위 테스트, 위젯 테스트, 통합 테스트를 모두 작성하여 코드의 신뢰성을 높이세요.

이 가이드라인을 준수하여 일관성 있고 유지보수 가능한 코드를 작성해주세요.