/// 계정 없이(로그인하지 않고) 이 기기에서만 기록을 남기는 사용자의 개인 기록
/// 소유자 id.
///
/// `book_note`/`book_reflection`의 `owner_user_id`는 NOT NULL이고, 노트·독후감
/// 조회는 모두 이 값으로 계정을 격리한다. 비로그인 사용자는 서버 계정이
/// 없으므로 서버가 절대 발급하지 않는 음수 하나를 고정 소유자로 쓴다 — 실제
/// 계정 id와 겹치지 않아, 그 기록이 어떤 로그인 사용자의 기록으로도 섞이지
/// 않는다.
///
/// 로그인으로 전환할 때는 이 소유자를 실제 계정 id로 한 번에 바꿔 끼운다
/// ([LocalAuthStore.rekeyRecordOwner]) — 기록을 복사하거나 다시 만들지 않는다.
const int standaloneOwnerUserId = -1;

/// 계정 없이 쌓아 둔 로컬 기록을 로그인 시 어떻게 이어 갈지.
enum StandaloneRecordAction {
  /// 계정에 올려 동기화한다. 새 이전 기능을 만들지 않고 기존 로컬 → 서버
  /// 저장 방식 전환(Import) 흐름을 그대로 쓴다.
  uploadToAccount,

  /// 이 기기에만 둔다(로컬 저장 모드 유지).
  keepOnDevice,
}
