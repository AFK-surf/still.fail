// What a draft refers to, shared before it goes (still.fail apps/android chat/screens/Composer.kt sendSharing, askToShare;
// NewChat.kt's first message the same; docs/chat-share.md), the phone's asking: what is asked of the core and what its
// yes does are sfbase's (outside.mbt), for every composer; here, its sheet. It says which chats first, each saying
// whose (来自 its workspace), those the viewer may not share saying so; 分享并发送 shares those they may (the button
// turning meanwhile), then closes and sends; a share failing is said in the sheet, nothing sent, the draft as it was.
// With none they may share, 仍然发送 sends it as it is. 取消 (or the scrim) leaves the draft as it was.

///|
/// What it says first: 14/20, muted, 8 over the chats.
// kept across runs: a value (no field of it changes)
let outside_lead_box : @ui.Style = @ui.css("w=Full pb=S2")

///|
// kept across runs: a value (no field of it changes)
let outside_lead : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, w=Full)

///|
/// A chat's row: 5 above and under; its title after `@` (15/22, the link's ink, `@` at 70% of it) and whose it is in a
/// tag, 6 apart; why it may not be shared under them (13/18, red, 2 under).
// kept across runs: a value (no field of it changes)
let outside_row : @ui.Style = @ui.style(w=Full, py=@sf.space_5)

///|
// kept across runs: a value (no field of it changes)
let outside_line : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let outside_title_box : @ui.Style = @ui.css("row")

///|
// kept across runs: a value (no field of it changes)
let outside_at : @ui.TextStyle = @ui.text_style(size=Ui, leading=L7, color=A(Link, O70), wrap=false)

///|
// kept across runs: a value (no field of it changes)
let outside_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L7, color=Link, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let outside_cannot_box : @ui.Style = @ui.css("w=Full pt=S0_5")

///|
// kept across runs: a value (no field of it changes)
let outside_cannot : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Danger, w=Full)

///|
/// Why sharing failed: 13/18, red, 8 under the chats.
// kept across runs: a value (no field of it changes)
let outside_failed_box : @ui.Style = @ui.css("w=Full pt=S2")

///|
/// Whose a chat is, in a small outlined pill (PageParts.kt StationTag: 104 at most, 8 and 2 in, its mark 4 before its
/// words 12/16 muted on one line).
// kept across runs: a value (no field of it changes)
let words_tag : @ui.Style = @ui.style(
  row=true,
  max_w=@sf.tag_max,
  px=S2,
  py=S0_5,
  gap=S1,
  radius=Full,
  border=B1,
  border_color=Line,
  align=ACenter,
)

///|
// kept across runs: a value (no field of it changes)
let words_tag_words : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4, color=Muted, wrap=false)

///|
/// The presenter asking for each draft's sharing (@sf.last_presented), while it is drawn.
// kept across runs: emptied as each goes (outside_sheet); reset by the app with the presenters (outside_reset)
let outside_shown : Map[String, Int] = {}

///|
/// No sheet asking (the app begun again).
fn outside_reset() -> Unit {
  outside_shown.clear()
}
