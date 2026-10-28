# 리뷰 결과

## 요약
ZIP 경로·CRC·관계 검증과 DB 복원 트랜잭션은 갖춰져 있습니다. 성공한 내보내기의 임시 파일 정리에 P2 1건이 있습니다.

## 확인 범위
ZIP 내보내기, 이미지 확보와 누락 안내, JSON·CSV·HTML 생성, 파일 저장 취소, ZIP 크기/경로/중복/심볼릭 링크/CRC, 이미지 준비, 동일 기록 재가져오기, ISBN 대응, 복원 실패 파일 정리를 확인했습니다.

## 문제점

### [ARC-01][P2] 내보내기에 성공하거나 저장을 취소한 뒤 작업용 ZIP이 남음

- 근거: [lib/features/record_archive/services/record_archive_service.dart:236](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/record_archive/services/record_archive_service.dart:236)은 매번 `bookkureomi_export_*` 임시 폴더를 만듭니다. 예외일 때만 그 폴더를 삭제하고 성공하면 File을 반환합니다. [lib/features/record_archive/providers/record_archive_provider.dart:74](/Users/hagulu/develop/service/BBBook/project/app/bbbook/lib/features/record_archive/providers/record_archive_provider.dart:74)은 파일 선택기에 바이트를 넘긴 후 저장 성공·취소 어느 경우에도 반환된 파일/폴더를 정리하지 않습니다.
- 영향: 내보내기를 반복할 때 이미지와 개인 기록을 담은 전체 ZIP이 앱 임시 영역에 계속 쌓입니다. OS가 언젠가 비울 수는 있지만 앱의 작업 완료 시점에 정리되는 것은 아닙니다. 반복 백업으로 불필요한 저장 공간을 차지합니다.

## 개선 제안

파일 저장 Future가 끝난 뒤, 앱이 이번 작업에서 만든 임시 ZIP과 전용 디렉터리를 성공·취소 공통 finally에서 정리합니다. 사용자가 선택한 저장 위치의 파일은 정리 대상에 포함하지 않습니다. 이 작업에 별도 캐시 시스템을 도입할 필요는 없습니다.

## 확인된 보호 장치

- ZIP 원본 헤더에서 중복 경로·절대 경로·상위 경로·심볼릭 링크·드라이브 경로와 압축 해제 합계 제한을 확인합니다. 사용자가 지정한 경로로 ZIP을 직접 풀지 않습니다.
- manifest와 참조 이미지에 CRC 검증을 하고, 관계를 검증한 뒤 한 트랜잭션으로 DB에 반영합니다. 실패하면 새로 만든 이미지 파일을 정리합니다.
- 기존 멱등 키와 ISBN 대응을 구분하고 기록 간 관계가 다르면 전체 복원을 중단합니다.
- HTML에는 텍스트 escape, 링크 scheme 제한과 CSP가 있습니다. 계정 토큰이나 서버 PK를 ZIP의 복원 식별자로 사용하지 않습니다.

## 관련 경계와 한계

[IMP-02](./20261028-124818-external-import.md)의 작업 락은 ZIP에도 적용해야 합니다. 대용량 manifest 파싱·이미지 해제 시 메모리와 UI 정지는 기기 측정이 필요하며, 허용 최대치에 가까운 비정상 입력만을 가정해 이번 결함 수를 늘리지는 않았습니다.
