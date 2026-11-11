// A chat's composer (still.fail apps/android chat/screens/Composer.kt ComposerBar, DraftExtras, Drafts, upload; ChatHost.kt
// HostComposer; Attach.kt; PastedText.kt; SendText.kt): a capsule floating over the list's foot. ＋, a field that grows
// with the words up to six lines, the round send button; focused or holding something, the field takes the whole
// width and the buttons go under it. What waits to go with the words sits over the field: the quotes (each with a
// line for a comment) and the files (pictures as tiles, a long paste as its card, any other file as a card), each
// handed to the core as soon as it is added, which sends it up to the station (`composer.add`, its bytes beside the
// call; a station that has it already copies its own), where it waits in no chat until a message takes it. A message
// sent while one is still going up names it (`uploads`) and waits in the outbox until it is up; one that failed goes
// again from what the core kept (`composer.retry`). Enter is a new line, as the Android app's field has it; send sends.
//
// Each chat has its own draft (`<station>:<session>`, as the Android app keys it): the words, the quotes with what is
// said about them, the files already up, kept by the core on the device (`draft.get`, `draft.put` a moment after each
// change and as the chat is left) and put back when the chat is opened again. A long paste (5000 characters or more at
// once) goes as a text file, not into the field.
//
// Sending empties the composer at once: the message shows from the chat's outbox until the station has it (正在发送
// under it after a moment; 未发送 with 重试 and 删除 when it failed, messages.mbt), and the list goes to its end. A send
// the core refuses before the outbox (`invalid_params`) gives the words back and says why.
//
// With MBUI_READONLY=1 (Source.read_only) nothing leaves: no send, no draft kept, no file put up (said in a toast).

///|
/// Whether the files' row (or the station files') is in the capsule's top left corner this frame (capsule_top).
let files_cornered : Ref[Bool] = Ref(false)

///|
fn draft_key(r : ChatRef) -> String {
  r.station + ":" + r.session
}

///|
/// How long after a change to the draft it is kept.
pub let draft_keep_ms : Double = 400.0

///|
/// What the page keeps of its composer.
priv struct ComposerUi {
  /// why restoring the chat failed, by its draft
  restore_error : @sf.LiveMap[String, String]
  /// the outbox's entries being sent again or dropped (their buttons spin meanwhile)
  doing : @sf.LiveMap[String, Bool]
}

///|
let cui : ComposerUi = { restore_error: @sf.LiveMap::new(), doing: @sf.LiveMap::new() }

// ── ＋'s sheet ──────────────────────────────────────────────

///|
/// ＋'s sheet up (@sf.last_presented; 0 none), and what it shows as the composer's frame has it.
// kept across runs: put back by attach_reset
let attach_shown : Ref[Int] = Ref(0)

///|
/// No ＋ sheet (the app begun again).
fn attach_reset() -> Unit {
  attach_shown.val = 0
}
