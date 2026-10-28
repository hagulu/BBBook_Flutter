# 리뷰 결과

## 요약

- 현재 미커밋 변경 9개 파일에서 iOS 앱·테스트 타깃의 서명 팀 불일치 P2 문제 1건을 확인했다. 노트 이미지 한도 변경에서는 추가 기능 결함을 찾지 못했다.
- 범위: `PHOTO` 메모의 이미지 한도 포함 기준, 기존 사진 교체 시 한도 검사, 화면·DAO·Repository 연결, Import 사전 검증 주석, 관련 테스트 변경, 분석 제외 설정, iOS 프로젝트 설정. 이미지 개수 조회·메모 수정·이미지 업로드 API 문서를 함께 대조했다.
- 검증: `flutter analyze`는 `No issues found!`로 통과했다. `git diff --check`와 `plutil -lint ios/Runner.xcodeproj/project.pbxproj`도 통과했다.
- 앱 실행·빌드·테스트 실행은 하지 않았다. 아래 iOS 영향은 프로젝트 설정과 Apple 문서를 대조해 판단한 것으로, 실제 기기에서 재현한 결과는 아니다. 구현 코드는 수정하지 않았다.

## 문제점

- [P2] **앱의 서명 팀만 변경해 실제 기기에서 호스트 앱 기반 테스트가 실패할 수 있다.**

  위치: [project.pbxproj:692](../../ios/Runner.xcodeproj/project.pbxproj#L692). 같은 변경이 Profile 505행·Release 716행에도 적용되어 있다.

  `Runner`의 `DEVELOPMENT_TEAM`은 세 구성 모두 `R2WD38VM42`로 바뀌었지만, `RunnerTests`는 Debug 528행·Release 547행·Profile 564행에서 `9W487JRW2B`를 유지한다. `RunnerTests`는 `TEST_HOST`와 `BUNDLE_LOADER`로 `Runner.app`에 연결되며, 공유 [Runner.xcscheme:65](../../ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme#L65)의 TestAction에도 활성화되어 있다.

  별도의 팀 오버라이드 없이 실제 iOS 기기를 대상으로 이 스킴의 Test를 실행하면 호스트 앱과 테스트 번들이 서로 다른 팀으로 서명된다. iOS는 프로세스에 로드하는 외부 코드의 팀 식별자를 검증하므로, 테스트 번들을 로드하지 못할 수 있다. 기존 팀의 서명 자산이 없는 새 팀 개발 환경에서는 그 전에 테스트 타깃의 프로비저닝부터 실패할 수 있다. 이 영향은 현재 설정과 Apple의 [타깃 팀 지정 안내](https://help.apple.com/xcode/mac/current/en.lproj/dev23aab79b4.html), [라이브러리 서명 검증 규칙](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)에 근거한 판단이다.

## 개선 제안

- 앱·테스트 타깃의 서명 팀 불일치 → `RunnerTests`의 Debug·Release·Profile도 `Runner`와 같은 팀을 사용하도록 맞춘다. 팀 지정이 개발 환경별 설정이라면 두 타깃에 동일하게 적용되도록 관리한다.
- 이번 변경의 핵심 경계가 기존 테스트에서 직접 검증되지 않음 → 이미지 경로가 모두 null인 활성 `PHOTO`도 한도에 포함되는 경우, 삭제된 `PHOTO`는 제외되는 경우, 이미 한 자리를 차지한 메모는 한도를 초과한 상태에서도 이미지를 교체할 수 있는 경우를 모델·DAO의 비즈니스 로직 회귀 테스트로 보강할 가치가 있다. 현재 변경된 정책 테스트는 개수 3·한도 3에서 boolean 인자의 동작을 확인하므로, 새 집계 조건과 한도 초과 시 DAO 분기까지 검증하지는 않는다.
