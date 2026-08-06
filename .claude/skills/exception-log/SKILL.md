---
name: exception-log
description: 예외 처리나 로그를 작성하거나 수정할 때 일관된 메시지와 로그 포맷을 적용하기 위해 사용
---

# 예외 / 로그 포맷

## 규칙
- 사용자 메시지와 내부 원인을 구분한다.
- 사용자 메시지는 짧게 작성하고 내부 원인은 로그에만 기록한다.

## 로그 포맷
- 형식: [작업명] key=value result=SUCCESS|FAIL reason=snake_case

## 로그 항목
- 주요 식별자(userId, bookId 등)
- 요청 대상(API, 플랫폼 연동)
- result, reason
- 필요시 status, duration(ms)

## 적용 대상
- API 요청, 외부 서비스·플랫폼 연동
- 데이터 변경 작업(생성/수정/삭제)
- 인증/인가 실패, not_found, validation 실패

## 금지
- 임시 출력 유지 금지
- 민감 정보 기록 금지
