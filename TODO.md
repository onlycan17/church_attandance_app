# 교회 예배 출석 체크 - 통합 TODO 리스트

## 현재 작업
- [ ] 백그라운드 신뢰성 B안: 오프라인 큐(SQLite) — 진단 로그 보강, 단위 테스트 추가
- [ ] iOS 백그라운드 위치 업데이트 지원(Background Modes/설명 키/구현)
- [ ] 배터리 최적화 예외 안내 UI/문서 정리(제조사별 가이드)

## 완료
- [x] 요구사항 분석/PRD/아키텍처 문서 정리(docs)
- [x] Flutter 프로젝트 구조 설계/생성
- [x] Supabase 초기화/연결 테스트, 기본 테이블 연동
- [x] 위치 서비스 라이브러리/권한 설정(geolocator 등)
- [x] WorkManager 초기화 문제 해결 및 안정화(채널 오류 해결)
- [x] 백그라운드 3분 테스트 모드(OneOff 재스케줄) 구현
- [x] Android 백그라운드 위치 알림(포그라운드 서비스) 활성화
- [x] 콜백/서비스 로깅 강화(권한/세션/env/위치)
- [x] 위치 히스토리 로그 테이블(location_logs) 생성 및 앱 연동
- [x] 훅 검증 통과(dart format, flutter analyze, flutter test)
- [x] LoginViewModel dispose 안전화(폐기 후 notify 차단)
- [x] 위치 상태 스트림 broadcast 전환(중복 구독 에러 방지)
- [x] 백그라운드 테스트 버스트(15초 간격, 60초) 저장 추가
- [x] 세션 부재 시 access token 이메일 디코드 경로로 저장 시도
- [x] 오프라인 큐 1단계: sqflite 기반 로컬 큐/콜백 연동(실패 시 enqueue, 성공 시 배치 업로드)

## 다음 단계
- [ ] 핵심 기능 고도화: 예배 시간대/교회 반경/중복 방지 DB 제약(운영 전환 시)
- [ ] UI/UX 다듬기: 권한 상태/배터리 예외 안내 개선, 상태 표시 고도화
- [ ] 대시보드: location_logs 시각화(사용자/예배별 필터)
- [ ] 운영 전환 시 보안: RLS 정책/정책 테스트(프로토타입 단계에서는 제외)
- [ ] 포그라운드 서비스 전환 옵션 설계(A/B 테스트)

## 세부 작업(TODO Breakdowns)

### B안: 오프라인 큐(SQLite)
- [x] 의존성 추가: `sqflite`, `path_provider`, `path`
- [x] 로컬 큐 스키마 설계: `log_queue(id, user_id, service_id, lat, lng, accuracy, source, captured_at, retries, created_at)`
- [x] `LocalQueueService` 작성: enqueue/dequeue(batch)/delete(ids)/count
- [x] 백그라운드 콜백: 삽입 실패 시 enqueue, 성공 시 큐 비우기 시도(100건)
- [x] 업로드 재시도: 지수 백오프, 최대 재시도 한도(예: 5회) — next_attempt_at 컬럼 기반
- [ ] 진단 로그: 원인별(네트워크/DNS/권한) 분기 로깅
- [ ] 테스트: 서비스 단위 테스트(큐 입출력/정렬/삭제)

## 상세 작업 항목(참고)

### 1. Flutter 프로젝트 설정
- [x] 프로젝트 생성/디렉터리 구조
- [x] 패키지 설치(geolocator, workmanager, supabase_flutter 등)
- [x] 환경 변수 설정(.env)

### 2. Supabase 백엔드 설정
- [x] 프로젝트 설정 및 기본 테이블 연결
- [x] location_logs 생성(프로토타입, RLS 비활성)
- [ ] (운영) RLS/인덱스/유니크 제약 재점검

### 3. 핵심 기능 개발
- [x] GPS 위치 수집/거리 계산/출석 체크(교회 반경 내 최초 1회)
- [x] 서버 전송 로직(Attendance/Logs)
- [ ] 예배 시간대 로직 보강

### 4. 백그라운드 실행 지원
- [x] Android: WorkManager + ForegroundNotificationConfig
- [x] 테스트 모드: 3분 간격 반복(OneOff 재스케줄)
- [ ] iOS: Background Modes 구성 및 대안(지오펜싱/로컬 알림)

- [x] 백그라운드 신뢰성 A안: 내부 `user_id(int)` 캐시/전달로 매핑 REST 제거
  - WorkManager `inputData`에 `user_id_int` 포함 → 콜백에서 override로 사용
  - `location_logs` 삽입 시 이메일 매핑 REST 제거 경로 확보(네트워크 실패 민감도 완화)
  - 훅 통과: format/analyze/test ✅
### 5. 인증/세션
- [x] 로그인/세션 캐시
- [ ] WorkManager 콜백에서 세션 복구(A안: 토큰 전달)

### 6. UI 구성
- [x] 로그인/홈 화면 초기 구성
- [ ] 권한/배터리 안내 UX 개선

### 7. 테스트/디버깅
- [x] 훅 통과 파이프라인 정착(format/analyze/test)
- [ ] 실기기 E2E 체크리스트(권한/배터리/알림/반경/주기)
