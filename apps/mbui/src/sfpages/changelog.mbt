// What the last update brought, at the top of the chats' lists until it is seen (ember web/src/mobile/Changelog.tsx
// ChangelogNews; the `changelog` topic's `news`), where the frame puts it (the phone's Home: beside the wide frame's
// rail the web says it in a bubble of its own, cloud/workspace.tsx): the build it is now and its first three changes,
// a press opens the changelog; its × lets it go at once and tells the core (`changelog.seen`).

///|
/// The news let go here (before the core has it): none shows while the core's is this one.
// kept across runs: put back as a run begins (news_reset)
let news_gone : @signals.Signal[Json?] = @signals.signal(None)

///|
/// As at the start (tests).
fn news_reset() -> Unit {
  news_gone.set(None)
}

///|
/// The news as the core has it, unless let go here.
pub fn news_of(src : Source) -> Json? {
  match field((src.topic)("changelog", Map::new()).value, "news") {
    Some(Object(_)) as n if news_gone.get() != n => n
    _ => None
  }
}

///|
// kept across runs: a value (no field of it changes)
let news_title : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Fg, wrap=false)

///|
/// A change (13 on 18, muted, one line).
// kept across runs: a value (no field of it changes)
let news_line : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, leading=L5, wrap=false, w=Full)

///|
/// Its ×'s side (news_close's S8).
let news_close_side : Double = 32.0

///|
/// How many of its changes it says before "还有 n 项".
let news_lines_most : Int = 3

///|
/// Whether the update wants the person over a small screen's list (update_card): the leave to install apps it waits
/// for (sfbase updates.mbt: a build ready that Android puts in place by itself once given it).
pub fn update_card_shown() -> Bool {
  @sfbase.update_now() is Allow(_)
}

///|
/// Why, wrapping (the news card's lines, whole).
// kept across runs: a value (no field of it changes)
let update_card_line : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, leading=L5, w=Full)
