###수파베이스 MCP 연결시 
EXPO_PUBLIC_SUPABASE_URL=https://qqgvkfsgloyggqpnemol.supabase.co
EXPO_PUBLIC_SUPABASE_KEY=sbp_6269ac90378f3a770b45820e69139e1e3f696227

### 코드 작성 규칙 (SOLID & DRY 원칙 준수)
- 모든 소스코드는 DRY(Don't Repeat Yourself) 원칙을 따릅니다.
- 중복 코드를 최소화하고, 재사용 가능한 컴포넌트와 함수를 설계합니다.
- SOLID 원칙 적용:
  - 단일 책임 원칙(SRP): 각 클래스/함수는 하나의 책임만 가집니다.
  - 개방-폐쇄 원칙(OCP): 확장에는 열려 있으나 수정에는 닫혀 있어야 합니다.
  - 리스코프 치환 원칙(LSP): 상위 타입의 객체를 하위 타입의 객체로 대체해도 프로그램은 정상적으로 동작해야 합니다.
  - 인터페이스 분리 원칙(ISP): 클라이언트는 자신이 사용하지 않는 인터페이스에 의존해서는 안 됩니다.
  - 의존성 역전 원칙(DIP): 고수준 모듈은 저수준 모듈에 의존해서는 안 되며, 둘 다 추상화에 의존해야 합니다.

### 코드 명명 규칙
- 변수 및 함수명: camelCase (예: getUserData, calculateDistance)
- 클래스명: PascalCase (예: AttendanceService, LocationChecker)
- 상수명: UPPER_CASE_SNAKE_CASE (예: MAX_DISTANCE_METER = 80)
- 파일명: PascalCase 또는 lower_case_with_underscores (예: attendance_service.dart, location_checker.dart)

### 코드 구조 및 설계 원칙
- 컴포넌트 분리: UI 컴포넌트와 비즈니스 로직을 분리합니다.
- 상태 관리: Provider, Riverpod 또는 Bloc 패턴을 사용한 효율적인 상태 관리
- 에러 처리: 일관된 에러 핸들링 방식 적용
- 문서화: 함수 및 클래스에 대한 주석 설명 추가

### 기술 스택 및 라이브러리 규칙
- Flutter 프로젝트 구조:
  - lib/
    - core/ : 공통 컴포넌트와 유틸리티
    - features/ : 각 기능별 모듈 (예: attendance, location, auth)
    - services/ : 백엔드 서비스 및 데이터 로직
    - ui/ : UI 컴포넌트와 위젯들
- 의존성 주입: Injectable 또는 GetIt를 사용한 의존성 관리

### 보안 규칙
- 민감 정보는 환경 변수나 암호화된 저장소에 저장합니다.
- 위치 데이터 전송 시 HTTPS 사용
- 인증 정보는 안전하게 관리하고, 테스트용 계정은 별도의 보안 정책 적용

### 성능 및 최적화 규칙
- 불필요한 리빌드 방지: const 위젯과 StatefulWidget/StatelessWidget 적절한 사용
- 메모리 누수 방지를 위한 dispose 패턴 준수
- 위치 정보 수집은 배터리 효율성을 고려하여 5초 간격으로 설정

### 테스트 규칙
- 단위 테스트: 각 핵심 함수와 클래스에 대한 테스트 작성
- 위젯 테스트: UI 컴포넌트의 정상 동작 검증
- 통합 테스트: 기능별 전체 흐름 검증

### 코드 품질 관리
- Linter 규칙 적용 (flutter_lints 패키지 사용)
- 포맷팅 자동화 (dart format 명령어 사용)
- 모든 후크(hook) 문제는 절대 허용되지 않음 (포맷팅, 린팅, 오류 없이 녹색 상태 유지)

### 디버깅 및 로그
- 개발 모드에서만 상세 로그 출력
- 중요한 로직에 대한 로그 추가 (위치 수집, 출석 체크 등)
- 에러 발생 시 구체적인 로그 메시지 제공

### 프로젝트 유지보수 규칙
- 주석 및 문서화: 코드 변경 사항은 반드시 주석과 문서화로 기록
- 커밋 메시지: 명확하고 일관된 형식의 커밋 메시지 사용 (예: feat: 예배 출석 기능 추가, fix: 위치 계산 오류 수정)
- 브랜치 전략: main/master 브랜치에 직접 커밋 금지, feature 브랜치에서 개발 후 PR 요청

### Flutter 특화 규칙
- StatefulWidget과 StatelessWidget의 적절한 사용
- 메모리 관리를 위한 dispose 패턴 준수
- 비동기 처리: Future와 Stream을 통한 효과적인 비동기 처리
- 위치 권한 관리: 사용자에게 명확한 권한 요청 및 설명 제공

### 예외 처리 규칙
- 모든 예외는 적절하게 핸들링되어야 함
- 사용자 친화적인 에러 메시지 제공
- 시스템 오류 로그는 개발자만 확인 가능하도록 관리
