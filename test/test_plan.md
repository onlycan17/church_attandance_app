# 교회 출석 체크 앱 테스트 계획

## 1. 테스트 개요

### 1.1 목적
교회 출석 체크 애플리케이션의 기능적, 비기능적 요구사항을 검증하고 품질을 보장하기 위한 체계적인 테스트 계획 수립

### 1.2 범위
- GPS 위치 수집 및 검증 기능
- Supabase 데이터베이스 연동
- 백그라운드 위치 모니터링
- 로컬 알림 기능
- 사용자 인증
- UI/UX 기능

### 1.3 테스트 방법론
- 단위 테스트 (Unit Test)
- 통합 테스트 (Integration Test)
- UI 테스트 (Widget Test)
- 수동 테스트 (Manual Test)

## 2. 테스트 환경

### 2.1 개발 환경
- Flutter SDK: 3.24.0 이상
- Dart SDK: 3.5.0 이상
- Android Studio / VS Code
- iOS Simulator / Android Emulator

### 2.2 테스트 디바이스
- Android: API 21 이상
- iOS: iOS 12.0 이상
- 실제 디바이스: GPS 기능 지원

### 2.3 테스트 데이터
- 테스트용 Supabase 계정
- 가상의 교회 위치 좌표 (서울 시청 근처)
- 테스트용 사용자 계정

## 3. 테스트 케이스

### 3.1 단위 테스트

#### GPS 서비스 테스트
```dart
// GPS 권한 요청 테스트
test('GPS 권한 요청 성공', () async {
  // Given
  final gpsService = GPSService();

  // When
  final result = await gpsService.requestLocationPermission();

  // Then
  expect(result, true);
});

// 위치 정확도 테스트
test('현재 위치 정확도 검증', () async {
  // Given
  final gpsService = GPSService();

  // When
  final position = await gpsService.getCurrentLocation();

  // Then
  expect(position.accuracy, lessThan(100.0)); // 100m 이내 정확도
});

// 교회 반경 판별 테스트
test('교회 위치 내 판별', () async {
  // Given
  final gpsService = GPSService();
  final churchPosition = Position(
    latitude: 37.5665,
    longitude: 126.9780,
    accuracy: 10.0,
  );

  // When
  final result = await gpsService.isWithinChurchRadius(churchPosition);

  // Then
  expect(result, true);
});
```

#### Supabase 서비스 테스트
```dart
// 사용자 인증 테스트
test('사용자 로그인 성공', () async {
  // Given
  final supabaseService = SupabaseService();
  await supabaseService.init();

  // When
  final user = await supabaseService.signIn('test@example.com', 'password');

  // Then
  expect(user, isNotNull);
  expect(user.email, 'test@example.com');
});

// 출석 데이터 전송 테스트
test('출석 체크 데이터 저장', () async {
  // Given
  final supabaseService = SupabaseService();
  final testData = {
    'user_id': 'test-user-id',
    'service_id': 'test-service-id',
    'latitude': 37.5665,
    'longitude': 126.9780,
  };

  // When
  final result = await supabaseService.submitAttendanceCheck(
    latitude: testData['latitude'],
    longitude: testData['longitude'],
    userId: testData['user_id'],
    serviceId: testData['service_id'],
  );

  // Then
  expect(result, isNotNull);
});
```

#### 알림 서비스 테스트
```dart
// 알림 예약 테스트
test('예배 알림 예약', () async {
  // Given
  final notificationService = NotificationService();
  await notificationService.init();

  // When
  await notificationService.scheduleWorshipNotification(
    title: '테스트 알림',
    body: '예배 시작 30분 전입니다',
    scheduledDate: DateTime.now().add(const Duration(minutes: 30)),
  );

  // Then
  // 알림이 성공적으로 예약되었는지 검증
});

// 알림 취소 테스트
test('모든 알림 취소', () async {
  // Given
  final notificationService = NotificationService();

  // When
  await notificationService.cancelAllNotifications();

  // Then
  // 알림이 모두 취소되었는지 검증
});
```

### 3.2 통합 테스트

#### 위치 기반 출석 체크 통합 테스트
```dart
// 위치 수집부터 데이터 저장까지의 전체 플로우
testWidgets('전체 출석 체크 플로우', (WidgetTester tester) async {
  // Given
  await tester.pumpWidget(const MyApp());

  // When
  // 1. 로그인
  await tester.enterText(find.byType(TextField).first, 'test@example.com');
  await tester.enterText(find.byType(TextField).last, 'password');
  await tester.tap(find.text('로그인'));
  await tester.pumpAndSettle();

  // 2. 위치 서비스 활성화 대기
  await tester.pump(const Duration(seconds: 2));

  // 3. 수동 출석 체크 실행
  await tester.tap(find.text('수동 출석 체크'));
  await tester.pumpAndSettle();

  // Then
  // 출석 체크 성공 메시지 확인
  expect(find.text('출석 체크 완료!'), findsOneWidget);
});
```

#### 백그라운드 모니터링 통합 테스트
```dart
// 백그라운드 작업 등록 및 실행 테스트
test('백그라운드 위치 모니터링', () async {
  // Given
  final gpsService = GPSService();

  // When
  await gpsService.startBackgroundLocationMonitoring();

  // Then
  // 백그라운드 작업이 등록되었는지 검증
  // (실제 백그라운드 실행은 수동 테스트에서 확인)
});
```

### 3.3 UI 테스트

#### 로그인 화면 테스트
```dart
testWidgets('로그인 화면 UI 테스트', (WidgetTester tester) async {
  // Given
  await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

  // Then
  // 필수 UI 요소 존재 확인
  expect(find.text('교회 출석 체크 시스템'), findsOneWidget);
  expect(find.text('로그인'), findsOneWidget);
  expect(find.byType(TextField), findsNWidgets(2)); // 이메일, 비밀번호
  expect(find.byType(ElevatedButton), findsOneWidget);
});

testWidgets('로그인 유효성 검사', (WidgetTester tester) async {
  // Given
  await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

  // When
  // 빈 필드로 로그인 시도
  await tester.tap(find.text('로그인'));
  await tester.pump();

  // Then
  expect(find.text('이메일과 비밀번호를 입력해주세요.'), findsOneWidget);
});
```

#### 홈 화면 테스트
```dart
testWidgets('홈 화면 상태 표시', (WidgetTester tester) async {
  // Given
  await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

  // Then
  expect(find.text('현재 상태'), findsOneWidget);
  expect(find.text('위치 서비스'), findsOneWidget);
  expect(find.text('출석 체크'), findsOneWidget);
  expect(find.text('백그라운드 모니터링'), findsOneWidget);
  expect(find.text('예배 알림'), findsOneWidget);
});

testWidgets('버튼 상태 테스트', (WidgetTester tester) async {
  // Given
  await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

  // Then
  // 위치 서비스가 비활성화된 상태에서 버튼들이 비활성화되는지 확인
  final manualButton = find.text('수동 출석 체크');
  final backgroundButton = find.text('백그라운드 모니터링 시작');

  // 버튼이 비활성화되어 있어야 함
  expect(tester.widget<ElevatedButton>(manualButton).enabled, false);
  expect(tester.widget<ElevatedButton>(backgroundButton).enabled, false);
});
```

## 4. 수동 테스트 시나리오

### 4.1 기능 테스트
1. **앱 설치 및 초기 실행**
   - 앱이 정상적으로 설치되는지 확인
   - 초기 권한 요청이 적절하게 표시되는지 확인
   - 로그인 화면이 올바르게 표시되는지 확인

2. **사용자 인증**
   - 유효한 계정으로 로그인 성공
   - 잘못된 계정으로 로그인 실패
   - 빈 필드 입력 시 적절한 오류 메시지 표시

3. **위치 서비스**
   - GPS 권한 요청 및 승인
   - 현재 위치 정확도 확인
   - 교회 위치 내/외 판별 정확성

4. **출석 체크**
   - 수동 출석 체크 기능
   - 교회 범위 내에서만 체크 가능
   - 중복 체크 방지
   - Supabase 데이터베이스에 데이터 저장 확인

5. **백그라운드 모니터링**
   - 백그라운드 모니터링 시작/중지
   - 15분 간격 위치 확인
   - 앱이 백그라운드에서도 정상 작동

6. **알림 기능**
   - 예배 알림 설정
   - 주일 예배 시간에 알림 표시
   - 알림 클릭 시 앱 실행

### 4.2 비기능 테스트
1. **성능 테스트**
   - 위치 수집 응답 시간 (< 5초)
   - 데이터 전송 응답 시간 (< 3초)
   - 메모리 사용량 (백그라운드 실행 시)
   - 배터리 소모량

2. **호환성 테스트**
   - 다양한 Android 버전에서의 작동
   - 다양한 iOS 버전에서의 작동
   - 다양한 화면 크기에서의 UI 표시

3. **네트워크 테스트**
   - 오프라인 상태에서의 동작
   - 느린 네트워크 환경에서의 동작
   - 네트워크 재연결 시 데이터 동기화

## 5. 테스트 실행 계획

### 5.1 단계별 실행
1. **단위 테스트 실행** (개발 중 지속적)
2. **통합 테스트 실행** (기능 개발 완료 시)
3. **UI 테스트 실행** (화면 개발 완료 시)
4. **수동 테스트 실행** (모든 기능 개발 완료 시)

### 5.2 테스트 데이터 준비
- 테스트용 Supabase 프로젝트 설정
- 테스트용 사용자 계정 생성
- 가상의 교회 위치 좌표 설정
- 테스트 시나리오별 예상 결과 정의

### 5.3 버그 추적
- GitHub Issues를 통한 버그 추적
- 버그 재현 단계, 예상 결과, 실제 결과 기록
- 버그 우선순위 및 심각도 분류

## 6. 테스트 완료 기준

### 6.1 성공 기준
- 모든 단위 테스트 100% 통과
- 모든 통합 테스트 100% 통과
- 모든 UI 테스트 100% 통과
- 수동 테스트에서 Blocker/Critical 버그 0건
- Major 버그 2건 이하
- Minor/Trivial 버그는 기능에 영향 없음

### 6.2 테스트 커버리지 목표
- 코드 커버리지: 80% 이상
- 기능 커버리지: 100%
- UI 컴포넌트 커버리지: 100%

## 7. 리스크 및 대응 방안

### 7.1 기술적 리스크
- **GPS 정확도**: 실내 환경에서 정확도 저하 가능성
  - 대응: GPS + 네트워크 위치 혼합 사용 고려

- **배터리 소모**: 백그라운드 위치 모니터링으로 인한 배터리 소모
  - 대응: 최적화된 위치 업데이트 간격 설정

- **iOS 백그라운드 제한**: iOS의 엄격한 백그라운드 정책
  - 대응: 로컬 알림과 지오펜싱으로 보완

### 7.2 테스트 환경 리스크
- **실제 디바이스 부족**: 다양한 디바이스에서의 테스트 어려움
  - 대응: 에뮬레이터 + 주요 디바이스 모델 테스트

- **네트워크 환경**: 다양한 네트워크 환경 테스트 어려움
  - 대응: 시뮬레이션 도구 활용

## 8. 테스트 결과 보고

### 8.1 보고서 내용
- 테스트 실행 요약
- 발견된 버그 목록 및 상태
- 테스트 커버리지 보고
- 성능 테스트 결과
- 개선 권고사항

### 8.2 보고 시점
- 단위 테스트: 매일 (CI/CD 파이프라인)
- 통합/UI 테스트: 스프린트 종료 시
- 수동 테스트: 릴리즈 전
- 최종 보고: 프로젝트 완료 시