# Repository Guidelines

## 프로젝트 구조 및 모듈 구성
- `lib/`: 앱 소스 코드
  - `screens/`: 화면(UI) 구성 위젯
  - `services/`: Supabase, GPS, 알림 등 도메인 서비스
  - `background_location_callback.dart`: Workmanager 백그라운드 엔트리포인트
- `test/`: 단위/위젯 테스트(`*_test.dart`)
- `android/`, `ios/`, `macos/`, `web/`, `windows/`, `linux/`: 플랫폼별 설정
- `pubspec.yaml`: 의존성/자산 정의(예: `.env` 로드)
- `.env`: 개발용 환경변수(Supabase URL/Key). 배포는 안전한 비밀 저장소 사용 권장

## 빌드 · 테스트 · 개발 명령
- 의존성 설치: `flutter pub get`
- 포맷팅: `dart format .`
- 정적 분석: `flutter analyze`
- 테스트: `flutter test -j 1`
- 로컬 실행: `flutter run -d <device>` (예: `-d ios`, `-d chrome`)
- 릴리스 빌드: `flutter build ios --release`, `flutter build apk --release`

## 코딩 스타일 & 네이밍 규칙
- 기준: Dart/Flutter 공식 스타일 + `flutter_lints`(see `analysis_options.yaml`)
- 들여쓰기 2칸 스페이스, 줄바꿈/임포트 순서는 포맷터에 따름
- 파일: `snake_case.dart`
- 타입/위젯: `PascalCase`, 메서드/변수/상수: `lowerCamelCase`
- 함수는 단일 책임, 가급적 30줄 이내. 불필요한 중첩은 조기 반환
- 로그는 `debugPrint` 사용, 민감정보 로깅 금지

## 테스트 가이드라인
- 프레임워크: `flutter_test`
- 파일명: `*_test.dart`, 구조: `group`/`test`로 시나리오 명확화
- 플러그인/백엔드 의존 테스트는 필요 시 `skip` 처리 후 통합 테스트로 대체
- 실행: `flutter test` (필요 시 `--coverage` 활용)

## 커밋 & PR 가이드
- 커밋: Conventional Commits 권장(e.g., `feat:`, `fix:`, `chore:`, `refactor:`)
- 내용: 변경 이유와 효과를 1~2줄로 명확히 기술
- PR 요구사항:
  - 변경 요약과 스크린샷(UX 변경 시)
  - 관련 이슈 링크, 재현/검증 방법
  - 훅 사전 통과: `dart format`, `flutter analyze`, `flutter test` 모두 ✅

## 보안 & 설정 팁
- `.env`는 개발 편의를 위한 예시 파일입니다. 배포 환경에서는 런타임 환경변수/비밀관리 사용
- Supabase Key 등 비밀정보를 코드/로그/이슈에 노출하지 마세요
