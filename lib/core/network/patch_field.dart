/// PATCH 요청 한 필드의 3-상태(유지/수정/삭제)를 표현한다.
///
/// 서버의 PATCH 규칙(api-doc `api-me-books-userBookId-patch.md`)은 세 가지를
/// 구분한다.
/// - 요청 body에 키 자체가 없음 → 기존 값 유지
/// - 키가 있고 값이 `null` → 기존 값 삭제(DB에 NULL 저장)
/// - 키가 있고 실제 값 → 그 값으로 수정. 빈 문자열(`""`)도 "삭제"가 아니라
///   문자열 값 그대로 저장된다.
///
/// Dart의 `T?` 파라미터 하나로는 "생략"과 "명시적 null"을 구분할 수 없어
/// (둘 다 `null`) 삭제를 표현할 방법이 없다. 그래서 파라미터 타입을
/// `PatchField<T>?`로 두고 다음처럼 읽는다.
/// - `null` → 생략(유지)
/// - `PatchField.value(v)` → `v`로 수정
/// - `PatchField.clear()` → 명시적 `null`(삭제)
///
/// [PatchField.value]의 `T`는 non-nullable이라 `PatchField.value(null)`은
/// 컴파일되지 않는다 — 삭제 의도는 항상 [PatchField.clear]로만 표현된다.
class PatchField<T extends Object> {
  /// 이 값으로 수정한다. 빈 문자열도 유효한 값이다(삭제가 아니다).
  const PatchField.value(T this.value) : isCleared = false;

  /// 사용자가 기존 값을 제거했다 — 요청에 명시적 `null`을 실어 보낸다.
  const PatchField.clear() : value = null, isCleared = true;

  final T? value;
  final bool isCleared;

  @override
  bool operator ==(Object other) =>
      other is PatchField<T> &&
      other.value == value &&
      other.isCleared == isCleared;

  @override
  int get hashCode => Object.hash(value, isCleared);

  @override
  String toString() =>
      isCleared ? 'PatchField.clear()' : 'PatchField.value($value)';
}

/// 값이 있으면 "그 값으로 수정", null이면 "생략(기존 값 유지)".
///
/// "사용자가 입력하지 않았다"를 그대로 옮길 때만 쓴다 — 삭제 의도는 이
/// 함수로 표현되지 않으며 반드시 [PatchField.clear]로 적어야 한다.
PatchField<T>? patchIfPresent<T extends Object>(T? value) =>
    value == null ? null : PatchField.value(value);

extension PatchFieldNullable<T extends Object> on PatchField<T>? {
  /// 이 필드가 요청에 포함되는가(수정 또는 삭제).
  bool get isPresent => this != null;

  /// 요청에 실을 값. 생략인 경우에도 `null`이라 [isPresent]로 먼저 걸러야
  /// 한다.
  T? get requestValue => this?.value;

  /// 로컬 반영용: 생략이면 [fallback](기존 값)을, 삭제면 `null`을, 수정이면
  /// 그 값을 돌려준다.
  T? applyTo(T? fallback) => this == null ? fallback : this!.value;
}
