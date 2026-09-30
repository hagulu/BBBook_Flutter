import '../data/finished_csv_importer.dart';

/// 완독 CSV 필드 안내 한 줄(`my-import.md` CSV 형식 표 대응).
class FinishedCsvField {
  const FinishedCsvField({
    required this.name,
    required this.label,
    this.rule,
    this.required = false,
  });

  final String name;
  final String label;
  final String? rule;
  final bool required;
}

/// "완독 기록 가져오기" 화면의 CSV 형식·AI 프롬프트 내용.
/// 규칙은 [FinishedCsvImporter]의 검증 조건과 같게 유지한다.
abstract final class FinishedCsvGuide {
  static final header = FinishedCsvImporter.headers.join(',');

  static const fields = [
    FinishedCsvField(name: 'title', label: '도서 제목', required: true),
    FinishedCsvField(name: 'author', label: '저자'),
    FinishedCsvField(name: 'publisher', label: '출판사'),
    FinishedCsvField(
      name: 'isbn13',
      label: 'ISBN-13',
      rule: '하이픈·공백을 뺀 13자리 숫자',
    ),
    FinishedCsvField(name: 'total_pages', label: '총 페이지 수', rule: '양수만'),
    FinishedCsvField(
      name: 'started_at',
      label: '시작일',
      rule: 'yyyy-MM-dd, 완독일보다 늦으면 안 됨',
    ),
    FinishedCsvField(
      name: 'finished_at',
      label: '완독일',
      rule: 'yyyy-MM-dd, 비우면 오늘 날짜',
    ),
    FinishedCsvField(name: 'my_rating', label: '별점', rule: '0.5 ~ 5.0'),
    FinishedCsvField(name: 'short_review', label: '한줄 감상', rule: '최대 150자'),
    FinishedCsvField(
      name: 'source_type',
      label: '독서 매체',
      rule: 'PAPER_BOOK, EBOOK, AUDIO_BOOK',
    ),
    FinishedCsvField(
      name: 'platform_name',
      label: '플랫폼명',
      rule: '최대 50자, 종이책이면 무시',
    ),
    FinishedCsvField(
      name: 'difficulty',
      label: '난이도',
      rule: 'EASY, MODERATE, HARD',
    ),
    FinishedCsvField(
      name: 'discovery_source',
      label: '알게 된 경로',
      rule: '최대 50자',
    ),
    FinishedCsvField(
      name: 'is_masterpiece',
      label: '명작 여부',
      rule: 'true / false, 기본값 false',
    ),
    FinishedCsvField(name: 'reread_count', label: '회독 수', rule: '1 이상, 기본값 1'),
    FinishedCsvField(name: 'tags', label: '태그', rule: '| 로 구분, 태그당 15자·최대 10개'),
  ];

  static final prompt =
      '''
제공된 자료의 독서 기록을 아래 형식의 CSV 파일로 변환해줘.

첫 줄은 반드시 아래 헤더를 그대로 사용해.

$header

## 규칙

- 자료에서 확인되는 정보만 사용하고, 불확실하면 비워둬.
- `title`은 필수야. 제목을 확인할 수 없으면 해당 항목은 제외해.
- CSV는 반드시 UTF-8로 저장해.
- 쉼표, 큰따옴표, 줄바꿈이 포함된 값은 올바른 CSV 형식으로 처리해.
- `isbn13`: 확실한 ISBN-13만 하이픈 없이 13자리 숫자로 입력
- `total_pages`: 종이책 기준 쪽수, 양의 정수
- `started_at`, `finished_at`: `yyyy-MM-dd`
  - 시작일은 완독일보다 늦을 수 없어.
  - 완독일을 모르면 비워둬.
- `my_rating`: `0.5 ~ 5.0`, 소수점 첫째 자리까지
- `short_review`: 최대 150자
- `source_type`: `PAPER_BOOK`, `EBOOK`, `AUDIO_BOOK` 중 하나
- `platform_name`: 확인되는 경우만 입력, 최대 50자
- `difficulty`: `EASY`, `MODERATE`, `HARD` 중 하나
- `discovery_source`: 책을 알게 된 경로, 최대 50자
- `is_masterpiece`: 인생책이면 `true`, 아니면 `false` 또는 빈 값
- `reread_count`: 읽은 횟수, 양의 정수
- `tags`: 여러 개면 `|`로 구분
  - 태그 하나는 최대 15자, 책 한 권당 최대 10개
  - 제한을 넘으면 의미를 유지하면서 간결하게 다듬고, 중요한 태그를 최대 10개까지 추려줘.

각 행의 컬럼 수와 순서는 반드시 헤더와 일치시켜.

**결과는 UTF-8 `.csv` 파일로 만들어서 다운로드할 수 있게 제공해줘. CSV 내용은 채팅에 출력하지 마.**'''
          .trim();
}
