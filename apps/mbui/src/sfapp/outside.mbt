// What a draft refers to, shared before it goes (still.fail apps/android chat/screens/Composer.kt sendSharing, askToShare;
// NewChat.kt's first message the same), the phone's asking: what is asked of the core and what its
// yes does are sfbase's (outside.mbt), for every composer; here, its sheet. It says which chats first, each saying
// whose (来自 its workspace), those the viewer may not share saying so; 分享并发送 shares those they may (the button
// turning meanwhile), then closes and sends; a share failing is said in the sheet, nothing sent, the draft as it was.
// With none they may share, 仍然发送 sends it as it is. 取消 (or the scrim) leaves the draft as it was.

///|
/// The presenter asking for each draft's sharing (@sf.last_presented), while it is drawn.
// kept across runs: emptied as each goes (outside_sheet); reset by the app with the presenters (outside_reset)
let outside_shown : Map[String, Int] = Map([])

///|
/// No sheet asking (the app begun again).
fn outside_reset() -> Unit {
  outside_shown.clear()
}
