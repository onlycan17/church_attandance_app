# 아키텍처 명세서

## 개요
- 클라이언트: Flutter
- 위치: geolocator (포그라운드 스트림/백그라운드 단발 조회)
- 스케줄링: Android WorkManager(3분 디버그 OneOff 재스케줄). iOS는 별도 설계 필요
- 백엔드: Supabase(PostgREST, Auth)

## 주요 흐름
1) 포그라운드
- 10초 간격 + 10m distanceFilter로 위치 스트림 수신
- 매 업데이트 시 `AttendanceService.checkAttendance()` → `location_logs` 삽입

2) 백그라운드(테스트 모드)
- WorkManager로 3분마다 콜백 실행
- 현재 위치 1회 획득 → 출석 체크 시도 + `location_logs` 저장
- 버스트 저장: 이후 60초간 15초 간격으로 lastKnownPosition 또는 현재 위치로 추가 저장
- 다음 3분 후 OneOff 재등록

## 인증/세션
- 기본: Supabase 세션 복구 시도(refresh)
- 실패 대비: access token 전달 → JWT 이메일 디코드 → `users` 매핑 후 저장 시도
- 향후: 내부 `user_id(int)` 포그라운드에서 캐시/전달하여 매핑 REST 제거

## 신뢰성 보강 계획
- 오프라인 큐(SQLite)로 오프라인에서도 누락 없이 적재 → 네트워크 복구 시 업로드
- 포그라운드 서비스 전환(상시 알림) 옵션으로 짧은 주기 보장

## 안드로이드 제약
- Doze/App Standby/제조사 절전으로 짧은 주기 보장 어려움
- WorkManager 반복작업 15분 미만 보장 불가 → OneOff 대체

## 로그/진단
- 권한/세션/DNS/위치/삽입결과를 `debugPrint`로 표준화하여 수집

