# 교회 예배 출석 체크 어플리케이션 - 데이터베이스 스키마

## 개요
이 문서는 Supabase 기반의 교회 예배 출석 체크 어플리케이션의 데이터베이스 테이블 구조를 설명합니다.

## 테이블 목록

### 1. users (사용자 테이블)
- **설명**: 테스트용 단일 계정 정보 저장
- **컬럼**:
  - `id` (INTEGER, PRIMARY KEY): 사용자 고유 ID
  - `username` (VARCHAR(255), UNIQUE NOT NULL): 사용자 이름
  - `password_hash` (TEXT, NOT NULL): 비밀번호 해시
  - `created_at` (TIMESTAMP, DEFAULT NOW()): 생성 일자

### 2. services (예배 서비스 테이블)
- **설명**: 예배 일정 정보 저장
- **컬럼**:
  - `id` (INTEGER, PRIMARY KEY): 예배 서비스 고유 ID
  - `service_date` (DATE, NOT NULL): 예배 날짜
  - `start_time` (TIME, NOT NULL): 예배 시작 시간
  - `end_time` (TIME, NOT NULL): 예배 종료 시간
  - `created_at` (TIMESTAMP, DEFAULT NOW()): 생성 일자

### 3. attendance (출석 기록 테이블)
- **설명**: 사용자의 출석 정보 저장
- **컬럼**:
  - `id` (INTEGER, PRIMARY KEY): 출석 기록 고유 ID
  - `user_id` (INTEGER, REFERENCES users(id)): 사용자 ID
  - `service_id` (INTEGER, REFERENCES services(id)): 예배 서비스 ID
  - `is_present` (BOOLEAN, DEFAULT FALSE): 출석 여부
  - `check_in_time` (TIMESTAMP): 출석 체크 시간
  - `created_at` (TIMESTAMP, DEFAULT NOW()): 생성 일자

### 4. locations (위치 정보 테이블)
- **설명**: 예배 장소 위치 및 반경 정보 저장
- **컬럼**:
  - `id` (INTEGER, PRIMARY KEY): 위치 정보 고유 ID
  - `service_id` (INTEGER, REFERENCES services(id)): 예배 서비스 ID
  - `latitude` (DECIMAL(10,8), NOT NULL): 위도 좌표
  - `longitude` (DECIMAL(11,8), NOT NULL): 경도 좌표
  - `radius_meters` (INTEGER, DEFAULT 80): 출석 반경 (미터 단위)
  - `created_at` (TIMESTAMP, DEFAULT NOW()): 생성 일자

## 관계 설정

### users ↔ attendance
- One-to-Many: 하나의 사용자가 여러 출석 기록을 가짐

### services ↔ attendance
- One-to-Many: 하나의 예배 서비스에 여러 출석 기록이 가능

### services ↔ locations
- One-to-One: 하나의 예배 서비스에 하나의 위치 정보만 존재

## 특징
- 모든 테이블은 `created_at` 컬럼을 포함하여 생성 일자를 추적
- 출석 체크는 GPS 위치 기반으로 자동화됨
- 교회 위치 반경은 80미터로 설정 (radius_meters = 80)
