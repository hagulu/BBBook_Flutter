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
    FinishedCsvField(name: 'platform_name', label: '플랫폼명'),
  ];

  static final prompt =
      '''
아래 독서 기록을 완독 기록 CSV 파일로 변환해 주세요.

[출력 형식]
- 첫 줄에는 아래 헤더를 그대로 넣어 주세요.
  $header
- 한 줄에 책 한 권씩 작성해 주세요.
- 값에 쉼표(,)나 줄바꿈이 있으면 큰따옴표(")로 감싸 주세요.
- 결과는 UTF-8 인코딩의 .csv 파일로 만들어 주세요. 파일을 만들 수 없다면 CSV 내용만 출력하고 다른 설명은 붙이지 마세요.

[작성 규칙]
- title(책 제목)은 반드시 입력해 주세요.
- 모르는 값은 추측하지 말고 비워 주세요.
- isbn13: 확실히 아는 경우에만 하이픈 없이 13자리 숫자로 입력해 주세요.
- total_pages: 확인할 수 있는 경우에만 숫자로 입력해 주세요.
- finished_at: 완독일을 yyyy-MM-dd 형식으로 입력하고, 모르면 비워 주세요.
- my_rating: 0.5 ~ 5.0 사이 숫자로, 소수점 첫째 자리까지 입력해 주세요.
- short_review: 한줄 감상을 150자 이내로 요약해 주세요.
- source_type: 종이책은 PAPER_BOOK, 전자책은 EBOOK, 오디오북은 AUDIO_BOOK 중 하나로 입력해 주세요.
- platform_name: 밀리의서재, 리디북스, 교보eBook처럼 이용한 플랫폼을 아는 경우에만 입력해 주세요.'''
          .trim();
}
