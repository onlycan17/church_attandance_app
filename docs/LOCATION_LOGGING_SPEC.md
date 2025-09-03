# 위치 히스토리 로깅 설계(테스트용)

## 목적
- 테스트를 위해 주기적으로 수집된 위치를 Supabase에 기록하여, 콜백/주기/권한 동작을 검증한다.

## 제안 테이블: `location_logs`
- id: bigint, PK
- user_id: int, not null (public.users.id 참조)
- latitude: double precision, not null
- longitude: double precision, not null
- accuracy: double precision, null
- source: text, not null (예: 'foreground' | 'background')
- captured_at: timestamptz, not null (클라이언트 기준 시각)
- service_id: int, null (가능하면 현재 예배 서비스 id 연결)
- created_at: timestamptz default now()

### 예시 SQL
```
create table if not exists public.location_logs (
  id bigserial primary key,
  user_id integer not null references public.users(id),
  latitude double precision not null,
  longitude double precision not null,
  accuracy double precision,
  source text not null,
  captured_at timestamptz not null,
  service_id integer,
  created_at timestamptz not null default now()
);

-- RLS/권한은 운영 정책에 따라 추가(예: 본인 데이터만 읽기, 관리자 조회 허용 등)
```

## 앱 동작
- 포그라운드 스트림 업데이트 시 1건 기록
- 백그라운드 콜백 실행 시 1건 기록
- 출석 체크(insert)와 무관하게 별도 로그 테이블에 저장(중복 방지 없음)

## 참고
- 네트워크/세션 이슈로 insert 실패 시 앱 로그에 남기고, 재시도는 다음 주기에 맡긴다.

