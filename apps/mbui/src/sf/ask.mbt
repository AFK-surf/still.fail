// A card that asks (docs/ui-panels.md, 要人拍板的卡片): its title the question, the one line the answer turns on, its
// buttons in its foot corners; one alone in the middle of what it is over (a player's), all of it in its middle and its
// buttons across its foot. An agent's ask in a chat (settings' vault_ask, phone_ask; sfbase's adb_link_card) and
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
/// `centred`: each line in the card's middle (a card alone in the middle of what it is over).
pub fn ask_words(c : @ui.Ctx, title : String, note : String, centred? : Bool = false) -> Unit {
  let night = on_night.val
  let ink = if night { media_dark_text } else { theme().p.text }
  let title_style = if centred { ask_title.then(ask_in_middle) } else { ask_title }
  let note_style = if night { ask_note.then(@ui.text_style(color=Data(media_dark_muted))) } else { ask_note }
  c.box(style=ask_what, fn() {
    if centred {
      c.text(title, style=title_style.then(@ui.text_style(weight=Semibold, color=Data(ink)))) |> ignore
    } else {
      c.rich([@ui.span(title, weight=600, color=ink)], style=title_style) |> ignore
    }
    if note != "" {
      c.text(note, style=if centred { note_style.then(ask_in_middle) } else { note_style }) |> ignore
    }
  })
  |> ignore
}

///|
/// An answered card's result, with a small disclosure to show that its original contents can be read again. Its
/// caller opens the history from the returned id; the press room grows around the line without moving its neighbours.
pub fn ask_history_trigger(c : @ui.Ctx, key : String, words : Array[@ui.Run], style : @ui.TextStyle) -> Int {
  let id = c.id("ask-history/" + key)
  let lit = @motion.animate(c, "ask-history-lit/" + key, if c.lit(id) || c.has_focus(id) { 1.0 } else { 0.0 }, spec=@motion.tween(dur_ms, ease=Out))
  let b = c.box(style=ask_history_line, id~, fn() {
    c.rich(words, style~) |> ignore
    c.box(style=ask_history_mark, fn() { icon(c, "chevron-right", size=12.0, color=mix(theme().p.text, lit, theme().p.muted)) |> ignore }) |> ignore
  })
  c.semantics(b, Button, id~, label=words.map(fn(w) { w.text }).join("") + " · " + t("web-main.history.details"))
  c.focusable(id, node=b)
  id
}

///|
// kept across runs: a value (no field of it changes)
let ask_history_line : @ui.Style = @ui.css("row gap=S1 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let ask_history_mark : @ui.Style = @ui.css("h=S5 justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let ask_in_middle : @ui.TextStyle = @ui.text_style(center=true)

///|
/// Its answer's buttons, out in the card's foot corners. What does not fit goes onto a line above, leaving the first
/// action in the card's bottom left.
pub fn ask_buttons(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=ask_foot.then(foot_reach(button_height())), flow_reverse=true, line_gap=ask_foot_lines(), fn() { card_foot_words(body) }) |> ignore
}

///|
/// The buttons of a card alone in the middle of what it is over: across its foot, each its share (foot_fills), the
/// first and the last concentric with its foot corners (foot_reach); nothing to one side.
pub fn ask_buttons_across(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=ask_across.then(foot_reach(button_height())), flow=true, line_gap=ask_foot_lines(), fn() {
    let was = foot_fills.val
    foot_fills.val = true
    body()
    foot_fills.val = was
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let ask_across : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
/// `body` on the night (a player's picture, a stage): the buttons and an ask's words in it the night's.
pub fn on_the_night(body : () -> Unit) -> Unit {
  let was = on_night.val
  on_night.val = true
  body()
  on_night.val = was
}
