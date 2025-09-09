# Supabase 프로젝트 정보 및 스키마

## 프로젝트
- Project: church_prototype
- Project ID: `qqgvkfsgloyggqpnemol`
- API URL: `https://qqgvkfsgloyggqpnemol.supabase.co`
- Region: `ap-northeast-2`

앱은 `.env` 파일의 `SUPABASE_URL`, `SUPABASE_ANON_KEY` 값을 사용합니다. 키는 코드에 저장하지 마세요.

## 사용 테이블 개요
- `users`(public): auth 사용자 이메일을 매핑하는 공개 사용자 테이블
- `services`(public): 예배 서비스 일정/ID
- `locations`(public): 서비스별 교회 위치/반경
- `attendance`(public): 출석 기록
- `location_logs`(public): 테스트용 위치 히스토리(주기적 로깅)

## 보안(프로토타입)
- 모든 사용 테이블에서 RLS 비활성: location_logs, attendance, locations, services, users
- 이유: 데모/프로토타입 단계로 접근 제어 최소화(운영 전환 시에는 RLS 필수)

## location_logs 스키마(프로토타입)
- 생성됨: MCP migration(create_location_logs)
- RLS: 비활성

컬럼
- `id` bigserial PK
- `user_id` int not null → public.users(id) 참조
- `latitude` double precision not null
- `longitude` double precision not null
- `accuracy` double precision null
- `source` text not null ('foreground'|'background')
- `captured_at` timestamptz not null (클라이언트 기준 수집 시각)
- `service_id` int null (가능 시 현재 예배 ID 연결)
- `created_at` timestamptz default now()

인덱스
- `idx_location_logs_user_time` on (user_id, captured_at desc)
- `idx_location_logs_service` on (service_id)
- `idx_location_logs_source` on (source)

## 앱 저장 로직
### 위치 데이터 저장
#### 포그라운드 모드
- 위치 스트림 업데이트마다 `insertLocationLog()` 호출
- 출석(attendance) 저장은 교회 반경 내 최초 1회만 자동 insert
- 사용자 인증 상태 확인 후 위치 로깅

#### 백그라운드 모드 (개선됨)
- WorkManager로 3분마다 콜백 실행
- **로컬 세션 복원**: `background_location_callback.dart`에서 저장된 refresh token으로 인증 상태 복원
- 현재 위치 1회 획득 → 출석 체크 시도 + `location_logs` 저장
- 버스트 저장: 이후 60초간 15초 간격으로 추가 위치 저장
- **인증 실패 시**: 위치 수집 중단, 다음 주기에 재시도
- 다음 3분 후 OneOff 재등록 (토큰 전달 없이 로컬 저장소 활용)

### 인증 세션 저장 (신규)
- **로컬 세션 관리**: shared_preferences를 통한 영구적인 세션 저장
- **자동 로그인**: `AuthStorageService`가 앱 시작 시 세션 복원
- **세션 생명주기**:
  - 로그인 → `SupabaseService.signIn()` → `AuthStorageService.saveSession()`
  - 앱 시작 → `AuthWrapper._checkAutoLogin()` → 세션 복원 시도
  - 백그라운드 → `background_location_callback.dart` → 로컬 세션 복원
  - 로그아웃 → `SupabaseService.signOut()` → `AuthStorageService.clearSession()`
- **보안 설정**: 7일 자동 로그인 제한, 30일 세션 수명 제한
- **오류 처리**: 세션 복원 실패 시 자동 삭제 및 로그인 화면으로 리다이렉트

### 예배 시간 정보 로컬 저장 (신규)
- **LocalServiceInfo 클래스**: 예배 날짜, 시간, 교회 위치, 반경 정보를 로컬에 저장
- **로컬 캐시 관리**: 1일간 유효한 예배 정보를 shared_preferences에 저장
- **기기 시간 판단**: 네트워크 요청 없이 `DateTime.now()`로 예배 시간 확인
- **기본 예배 시간**: 주일 오전 9-13시를 기본값으로 설정 (네트워크 오류 시)

### Supabase 클라이언트 통합
- **이중 보호**: Supabase 내부 세션 관리 + 로컬 백업
- **네트워크 오류 대응**: 로컬 세션으로 인증 유지 가능
- **세션 갱신**: Supabase 자동 갱신 + 로컬 동기화
- **백그라운드 지원**: 저장된 세션 정보로 백그라운드에서도 안정적인 인증 유지

### 출석 설정 후 백그라운드 추적 (개선됨)
1. **출석 체크 완료**: 교회 반경 내에서 자동 출석 체크
2. **백그라운드 모니터링 시작**: 홈 화면에서 3분 간격 모니터링 활성화
3. **기기 시간 기반 예배 시간 판단**: 네트워크 요청 없이 `LocalServiceInfo.isWithinServiceTime()`으로 시간 확인
4. **지속적인 위치 추적**: 백그라운드에서 로컬 세션으로 인증 상태 유지
5. **조건부 출석 체크**:
   - 로컬 예배 정보로 시간/장소 확인
   - 네트워크 연결 시에만 실제 출석 체크 수행
   - 네트워크 없을 시 위치만 로깅
6. **자동 재시작**: 앱 재시작 후에도 로컬 세션으로 백그라운드 추적 계속
7. **안정성 보장**: 네트워크 오류 시에도 다음 주기에 재시도
