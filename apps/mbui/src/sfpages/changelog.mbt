// What the last update brought, at the top of the chats' lists until it is seen (still.fail web/src/mobile/Changelog.tsx
// ChangelogNews; the `changelog` topic's `news`), where the frame puts it (the phone's Home: beside the wide frame's
// rail the web says it in a bubble of its own, cloud/workspace.tsx): the build it is now and its first three changes,
// a press opens the changelog; its × lets it go at once and tells the core (`changelog.seen`).

///|
/// The news let go here (before the core has it): none shows while the core's is this one; what shows it follows it.
let news_gone : @signals.Signal[Json?] = @signals.signal(None)

///|
/// As at the start (tests).
fn news_reset() -> Unit {
  news_gone.set(None)
}

///|
/// The changelog asked for its news alone (the core's `changelog` with `news`: no tab of it made or sent; the whole is
/// the changelog page's, 125 KB on a phone where this is a few hundred bytes, 2026-11-10).
pub fn news_params() -> Map[String, Json] {
  { "news": Json::boolean(true) }
}

///|
/// The news as the core has it, unless let go here.
pub fn news_of(src : Source) -> Json? {
  match field(src.topic("changelog", news_params()).get().value, "news") {
    Some(Object(_)) as n if news_gone.get() != n => n
    _ => None
  }
}

///|
/// Its room in the list: 4 over it, 10 under; its sides those of what stands over the list (changelog_news_node).
// kept across runs: a value (no field of it changes)
let news_room : @ui.Style = @ui.css("w=Full pt=S1 pb=S2_5")

///|
/// The card (a card's corner of the ladder's, its × in its top right corner concentric with it: news_close_place), on
/// the surface.
// kept across runs: a value (no field of it changes)
let news_card : @ui.Style = @ui.css("w=Full radius=Xl3 bg=Surface clip")

///|
/// What it says, 16 in (44 on the right, for the ×), 12 over and under, its lines 2 apart; rippled where it is pressed.
// kept across runs: a value (no field of it changes)
let news_words : @ui.Style = @ui.css("w=Full pl=S4 pr=S11 pt=S3 pb=S3 gap=S0_5")

///|
/// Its head: the sparks and the build, 6 apart, 2 over the lines.
// kept across runs: a value (no field of it changes)
let news_head : @ui.Style = @ui.css("row pb=S0_5 gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let news_title : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Fg, wrap=false)

///|
/// A change (13 on 18, muted, one line).
// kept across runs: a value (no field of it changes)
let news_line : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, leading=L5, wrap=false, w=Full)

///|
/// Its ×: 32, round, as far from the card's top and right as makes it concentric with its corner (capsule_in: 10).
// kept across runs: a value (no field of it changes)
let news_close_place : @ui.Style = @ui.style(
  w=Full,
  p=@sf.room_of(@ui.capsule_in(@sf.card_corner, news_close_side)),
  align=AEnd,
)

///|
/// Its ×'s side (news_close's S8).
let news_close_side : Double = 32.0

///|
// kept across runs: a value (no field of it changes)
let news_close : @ui.Style = @ui.css("w=S8 h=S8 radius=Full align=ACenter justify=JCenter")

///|
/// How many of its changes it says before "还有 n 项".
let news_lines_most : Int = 3

///|
/// Whether the update wants the person over a small screen's list (update_card_node): the leave to install apps it waits
/// for (sfbase updates.mbt: a build ready that Android puts in place by itself once given it).
pub fn update_card_shown() -> Bool {
  @sfbase.update_now() is Allow(_)
}

///|
/// What the update's card says: the news card's, 16 in on both sides (no × at its end).
// kept across runs: a value (no field of it changes)
let update_card_words : @ui.Style = @ui.css("w=Full px=S4 pt=S3 pb=S3 gap=S0_5")

///|
/// Why, wrapping (the news card's lines, whole).
// kept across runs: a value (no field of it changes)
let update_card_line : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, leading=L5, w=Full)
