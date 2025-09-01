# CRUSH.md - 교회 예배 출석 체크 애플리케이션

## 빌드 및 실행 방법
- 의존성 설치: `flutter pub get`
- 로컬 실행: `flutter run -d <device>` (예: `-d ios`, `-d chrome`)
- 릴리스 빌드: `flutter build ios --release`, `flutter build apk --release`

## 포맷팅 및 정적 분석
- 포맷팅: `dart format .`
- 정적 분석: `flutter analyze`

## 테스트
- 전체 테스트 실행: `flutter test -j 1`
- 단일 테스트 파일 실행: `flutter test test/파일명.dart`
- 개별 테스트 또는 그룹 실행: `flutter test --plain-name "테스트명"`
- 특정 플랫폼 테스트: `flutter test --platform chrome`
- 커버리지 포함 테스트: `flutter test --coverage`

## 코딩 스타일 & 네이밍 규칙
- 기준: Dart/Flutter 공식 스타일 + `flutter_lints`(see `analysis_options.yaml`)
- 들여쓰기 2칸 스페이스, 줄바꿈/임포트 순서는 포맷터에 따름
- 파일: `snake_case.dart`
- 타입/위젯: `PascalCase`, 메서드/변수/상수: `lowerCamelCase`
- 상수: `UPPER_CASE_SNAKE_CASE`
- 함수는 단일 책임, 가급적 30줄 이내. 불필요한 중첩은 조기 반환
- 로그는 `debugPrint` 사용, 민감정보 로깅 금지

## 코드 구조
- `lib/`: 앱 소스 코드
  - `screens/`: 화면(UI) 구성 위젯
  - `services/`: Supabase, GPS, 알림 등 도메인 서비스
  - `view_models/`: 화면별 뷰모델
  - `background_location_callback.dart`: Workmanager 백그라운드 엔트리포인트
- `test/`: 단위/위젯 테스트(`*_test.dart`)

## 에러 처리
- 모든 비동기 작업에 try-catch 사용
- 에러 메시지에는 민감정보 포함 금지
- 사용자에게 적절한 피드백 제공

## 테스트 가이드라인
- 프레임워크: `flutter_test`
- 파일명: `*_test.dart`, 구조: `group`/`test`로 시나리오 명확화
- 플러그인/백엔드 의존 테스트는 필요 시 `skip` 처리 후 통합 테스트로 대체
- Given-When-Then 구조 사용

## 보안
- `.env`는 개발 편의를 위한 예시 파일입니다. 배포 환경에서는 런타임 환경변수/비밀관리 사용
- Supabase Key 등 비밀정보를 코드/로그/이슈에 노출하지 마세요

## SOLID & DRY 원칙
- 단일 책임 원칙(SRP): 각 클래스/함수는 하나의 책임만 가집니다.
- 개방-폐쇄 원칙(OCP): 확장에는 열려 있으나 수정에는 닫혀 있어야 합니다.
- 중복 코드를 최소화하고, 재사용 가능한 컴포넌트와 함수를 설계합니다.

## 임포트 순서
1. Dart SDK 관련 (`import 'dart:...'`)
2. Flutter 패키지 (`import 'package:flutter/...'`)
3. 외부 패키지 (`import 'package:...'`)
4. 내부 패키지 (`import 'package:church_attendance_app/...'`)

각 그룹 내에서는 알파벳 순으로 정렬