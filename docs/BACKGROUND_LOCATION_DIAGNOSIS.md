# 백그라운드 위치 수집 진단 계획

본 문서는 "백그라운드 위치정보 수집 미동작" 이슈의 원인을 단계적으로 줄여가며 해결하기 위한 실행 계획입니다. 코딩 전 설계/진단 우선이며, 모든 변경은 훅(git hooks) 사전 통과를 전제로 합니다.

## 목표
- 안정적인 백그라운드 위치 수집 및 출석 자동 체크 동작 확보
- OS/권한/배터리 제약 하에서도 최소 요구조건 충족
- 로깅 확장으로 현상 재현과 원인 파악을 쉽게 함

## 현상 가설(우선순위 순)
1) Workmanager 콜백 자체가 실행되지 않음(등록/제약/최소주기/OS 최적화 영향)
2) 콜백은 실행되나 Supabase 세션이 없어 RLS로 DB 접근이 차단됨
3) 권한(특히 Android의 `ACCESS_BACKGROUND_LOCATION`/iOS Always) 미충족 또는 "앱 사용 중" 수준으로만 허용
4) 배터리 최적화(Doze/App standby)로 주기가 과도하게 지연됨
5) 백그라운드 Isolate에서 `.env`/Assets 초기화 실패로 Supabase 초기화 실패

## 점검 체크리스트
- [ ] 플랫폼/OS 버전 확인(안드로이드/아이폰, 버전, 기기 제조사)
- [ ] 위치 권한 상태: Always 허용 여부(안드 10+은 별도 요청/설정 필요)
- [ ] 배터리 최적화 예외 처리(제조사별 백그라운드 제한)
- [ ] Workmanager 등록 성공/중복 정책/제약 구성 확인
- [ ] 콜백에서 `.env` 로드 및 Supabase 초기화 성공 여부 로그
- [ ] 콜백에서 `auth.currentUser`/세션 복구 여부

## 제안 변경(코드 적용 전 합의 필요)
1) Workmanager 초기화/등록 개선
   - `initialize(callbackDispatcher, isInDebugMode: true)` (디버그 빌드 한정)
   - `registerPeriodicTask`에 `existingWorkPolicy: ExistingWorkPolicy.update`, `backoffPolicy` 명시
   - 입력 데이터에 최소 진단 정보 포함: 앱/버전/시간/플랫폼

2) 로깅 강화(콜백/등록 양쪽)
   - 콜백 진입/작업명/입력데이터 키/권한/서비스 상태/현재 세션 유무 명확 로그
   - 오류는 원인별 메시지 구분(권한/서비스/세션/env/supabase 통신)

3) Supabase 세션 복구 경로 설계
   - A안: Workmanager `inputData`로 `accessToken`/`refreshToken` 전달 → 콜백에서 `setSession`/`recoverSession` 시도
   - B안: 포그라운드에서 내부 사용자 ID 캐시 후 콜백은 익명 키로 최소 쓰기(백엔드 RLS 정책에 따라 불가할 수 있음)
   - 우선 A안 제안(변경 범위 작고 안전)

4) 권한/가이드 개선(UI)
   - Android: Always 권한 요청 경로 노출, 배터리 최적화 예외로 이동 유도
   - iOS: Background Modes(Location updates) 및 설명 키 확인

## 검증 시나리오
- 디버그 빌드에서 15분 대기(최소 주기) → 콜백 로그 수집
- 권한 거부/앱사용중/항상허용 각 상태에서 동작 비교
- 세션 전송 전/후로 DB 접근 성공 여부 비교

## 훅/검증 명령
- 포맷: `dart format .`
- 정적분석: `flutter analyze`
- 테스트: `flutter test -j 1`

문제 해결 후에도 주기적 리그레션 방지를 위해 콜백 로깅은 유지(개발 모드 한정)합니다.

