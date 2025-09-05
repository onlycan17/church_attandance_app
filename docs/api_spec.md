# API 명세서(Supabase 테이블 기준)

## location_logs
- INSERT: 본문
```
{
  "user_id": <int>,
  "service_id": <int|null>,
  "latitude": <double>,
  "longitude": <double>,
  "accuracy": <double|null>,
  "source": "foreground|background",
  "captured_at": "ISO8601"
}
```
- SELECT (최근 N개): `?select=*&order=captured_at.desc&limit=N`

## attendance
- INSERT: 출석 체크
```
{
  "user_id": <int>,
  "service_id": <int>,
  "is_present": true,
  "check_in_time": "ISO8601",
  "location_latitude": <double>,
  "location_longitude": <double>
}
```
- SELECT existing: `?select=*&user_id=eq.{id}&service_id=eq.{sid}`

## services
- TODAY: `?select=*&service_date=eq.{YYYY-MM-DD}`

## users
- GET BY EMAIL: `?select=id&email=eq.{email}`

