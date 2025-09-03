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
- 포그라운드: 위치 스트림 업데이트마다 `insertLocationLog()` 호출
- 백그라운드: 3분 주기 콜백에서 위치 획득 후 `logBackgroundLocation()` 호출
- 출석(attendance) 저장은 교회 반경 내 최초 1회만 자동 insert
