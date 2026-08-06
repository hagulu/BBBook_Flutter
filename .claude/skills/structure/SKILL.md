---
name: structure
description: 새로운 파일이나 컴포넌트를 생성할 때 프로젝트 디렉토리 구조를 일관되게 적용하기 위해 사용
---

# 파일 구조

## 규칙
- 새 파일 생성 시 아래 구조를 따른다.

- lib/
  - main.dart : 앱 진입점
  - app/ : 앱 설정, 라우팅, 테마
  - core/ : 네트워크, 공통 설정, 유틸
  - features/ : 기능별 화면, 위젯, 모델, 서비스
  - shared/widgets/ : 공통 UI 위젯

- test/ : `lib/` 구조에 대응하는 테스트
