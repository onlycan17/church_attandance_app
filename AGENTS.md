# Repository Guidelines

## 프로젝트 구조 & 모듈 구성
- `lib/`: 앱 소스 코드
  - `screens/`: 화면(UI) 위젯
  - `services/`: Supabase, GPS, 알림 등 도메인 서비스
  - `background_location_callback.dart`: 백그라운드 위치 콜백 엔트리포인트
- `test/`: 단위/위젯 테스트(`*_test.dart`)
- `android/`, `ios/`, `web/`, `macos/`, `windows/`, `linux/`: 플랫폼별 설정
- `pubspec.yaml`: 의존성/자산 정의, `.env` 로드
- `.env`: 개발용 환경변수(배포는 비밀관리 사용 권장)

## 빌드 · 테스트 · 개발 명령
- `flutter pub get`: 의존성 설치
- `dart format .`: 코드 포맷터(설명: 코드 자동 정렬 도구)
- `flutter analyze`: 린터(설명: 코드 규칙 자동 검사 도구)
- `flutter test -j 1`: 테스트 실행(병렬 1)
- `flutter run -d <device>`: 로컬 실행 예) `-d ios`, `-d chrome`
- 릴리스: `flutter build ios --release`, `flutter build apk --release`

## 코딩 스타일 & 네이밍
- 스타일: Dart/Flutter 공식 + `flutter_lints`
- 들여쓰기: 스페이스 2칸, 임포트/줄바꿈은 포맷터에 따름
- 파일: `snake_case.dart`
- 타입/위젯: `PascalCase`, 변수/함수: `lowerCamelCase`
- 함수는 단일 책임, 가급적 30줄 이내, 조기 반환 지향

## 테스트 가이드
- 프레임워크: `flutter_test`
- 파일명: `*_test.dart`; `group`/`test`로 시나리오 구분
- 실행: `flutter test -j 1` (필요 시 `--coverage`)
- 외부 플러그인 의존 시 통합 테스트로 대체하거나 `skip` 고려

## 커밋 & PR 가이드
- 커밋: Conventional Commits 예) `feat:`, `fix:`, `refactor:`
- PR 필수사항:
  - 변경 요약, 관련 이슈 링크, 재현/검증 방법
  - UI 변경 시 스크린샷
  - 사전 훅 모두 통과: `dart format`, `flutter analyze`, `flutter test` ✅

## 보안 & 설정 팁
- `.env`는 개발 전용. 배포는 환경변수/비밀관리 사용
- Supabase Key 등 비밀정보는 코드/로그/이슈에 노출 금지
- 로그는 `debugPrint` 사용, 민감정보 마스킹. CI(설명: 자동 테스트·검사 파이프라인)에서 경고를 오류로 처리해 품질을 보장합니다.
