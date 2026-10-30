// A card that asks (docs/ui-panels.md, 要人拍板的卡片): its title the question, the one line the answer turns on, its
// buttons in its foot corners. An agent's ask in a chat (settings' vault_ask, phone_ask; sfbase's adb_link_card) and
// what a player asks over its picture (player.mbt: 无法播放, 播放结束) alike; on the night (on_night: a player's, a
// stage's) in the night's words and buttons.

///|
/// What is asked, over the answer: its lines 2 apart (VaultAsk.css.ts what).
// kept across runs: a value (no field of it changes)
pub let ask_what : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
/// Its title, 14 on 20 (the account after it quieter, its own run).
// kept across runs: a value (no field of it changes)
pub let ask_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L5, color=Fg, w=Full)

///|
/// A line of what is out of the ordinary, or where there is no answer to give here: 12 and quiet.
// kept across runs: a value (no field of it changes)
pub let ask_note : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4_75, color=Muted, w=Full)

///|
/// The answer's buttons, 10 apart (pages.css.ts cardFoot).
// kept across runs: a value (no field of it changes)
pub let ask_foot : @ui.Style = @ui.css("row gap=S2_5 align=ACenter")

///|
/// Between the foot's lines, where its buttons go on to a second: 8, more where a press's room is taller than a button
/// and the one under it (a finger's 44 round a button of 34).
pub fn ask_foot_lines() -> Double {
  let more = @ui.room_least() - button_height()
  if more > 8.0 {
    more
  } else {
    8.0
  }
}

///|
/// An ask's title and under it the one line the answer turns on ("" none), 12 and quiet: in the theme's words, on the
/// night the night's.
pub fn ask_words(c : @ui.Ctx, title : String, note : String) -> Unit {
  let night = on_night.val
  let ink = if night { media_dark_text } else { theme().p.text }
  c.box(style=ask_what, fn() {
    c.rich([@ui.span(title, weight=600, color=ink)], style=ask_title) |> ignore
    if note != "" {
      c.text(note, style=if night { ask_note.then(@ui.text_style(color=Data(media_dark_muted))) } else { ask_note }) |> ignore
    }
  })
  |> ignore
}

///|
/// Its answer's buttons, as vault_foot lays them last on its card: a line of them, on to a second what has not the room
/// on the first, out in the card's foot corners.
pub fn ask_buttons(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=ask_foot.then(foot_reach(button_height())), flow=true, line_gap=ask_foot_lines(), body) |> ignore
}

///|
/// `body` on the night (a player's picture, a stage): the buttons and an ask's words in it the night's.
pub fn on_the_night(body : () -> Unit) -> Unit {
  let was = on_night.val
  on_night.val = true
  body()
  on_night.val = was
}
