// One line asked of the viewer on an option's ground (parts.mbt's ask_line_card, ask_line_mark, ask_line_button) as
// nodes of the window's tree, made once: what a chat needs at its end, its bell where an option's number is, 忽略
// ending it, quiet; under the hand its ground, eased over dur_ms from its cause, as a control answers.

///|
/// One line asked of the viewer (ask_line_card's) in `parent`: a row laid as an option's alone (pad_in in on every
/// side, its corner an option row's), on the text at 5%; `column` lays it a column instead. `body` makes what it holds.
pub fn ask_line_card_node(parent : @view.View, column : () -> Bool, body : (@view.View) -> Unit) -> @view.View {
  parent.box(fn(card) {
    card
    .row(By(fn() { !column() }))
    .gap(By(fn() { if column() { 0.0 } else { ask_line_gap } }))
    .lines_up(Is(Some(Start)))
    .padding(By(fn() {
      let p = option_type().pad_in
      (p, p, p, p)
    }))
    .radius(Is(option_row_corner))
    .ground(By(fn() { alpha(theme().p.text, 0.05) }))
    |> ignore
    body(card)
  })
}

///|
/// How far apart ask_line_card's words and what ends them are (ask_line_row's gap, S3).
let ask_line_gap : Double = 12.0

///|
/// What leads ask_line_card_node's words (ask_line_mark's): a column as wide and as high as an option's disc, what it
/// holds in its middle. `body` makes it.
pub fn ask_line_mark_node(parent : @view.View, body : (@view.View) -> Unit) -> @view.View {
  parent.box(fn(m) {
    m
    .width(By(fn() { Some(ask_line_disc()) }))
    .height(By(fn() { Some(ask_line_disc()) }))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    |> ignore
    body(m)
  })
}

///|
/// Room at the start of ask_line_card_node's words where no mark leads them (ask_line_start's): where the mark `icon`
/// wide would start in ask_line_mark_node's column.
pub fn ask_line_start_room(icon : Double) -> Double {
  (ask_line_disc() - icon) / 2.0
}

///|
/// The words of ask_line_card_node's row in `look` (ask_line_words'): on lines as high as its mark's column.
pub fn ask_line_words_look(look : @ui.TextStyle) -> @view.WordsLook {
  @ui.style_words(ask_line_words(look))
}

///|
/// Words to press ending ask_line_card_node's row (ask_line_button's: 忽略), `label`, in `parent`: quiet, the line's
/// own words, in its ink under the hand; their room a button's (as tall, round as it), its ground under the hand or the
/// finger concentric with the row's end corner, its words as far in as the row's start mark `mark` wide is from its
/// start. Not `live`: there and faded, taking no press. `press` told it pressed.
pub fn ask_line_button_node(
  parent : @view.View,
  label : () -> String,
  mark : Double,
  live : () -> Bool,
  press : () -> Unit,
) -> @view.View {
  parent.box(fn(b) {
    let lit = EdgeWay::new(0.0)
    let seen = EdgeWay::new(if @signals.untracked(live) { 1.0 } else { ask_line_faded })
    b.reacts(fn() { live() && (b.pointed() || b.pressed()) }, fn(on) { lit.go(b, if on { 1.0 } else { 0.0 }, dur_ms) })
    b.reacts(live, fn(on) { seen.go(b, if on { 1.0 } else { ask_line_faded }, dur_ms) })
    let out = fn() { option_type().pad_in - capsule_in(option_row_corner, button_height()) }
    b
    .row(Is(true))
    .height(By(fn() { Some(button_height()) }))
    .padding(By(fn() {
      let side = out() + (ask_line_disc() - mark) / 2.0
      (side, 0.0, side, 0.0)
    }))
    .margin(By(fn() {
      let o = out()
      (0.0, -o, -o, -o)
    }))
    .radius(By(fn() { button_height() / 2.0 }))
    .lines_up(Is(Some(Middle)))
    .ground(By(fn() { alpha(theme().p.hover, lit.shown(b)) }))
    .alpha(By(fn() { seen.shown(b) }))
    .says(By(fn() { Some(@view.said(Button, label=label())) }))
    .presses(By(live))
    |> ignore
    presses_node(b, press, on=live)
    b.box(fn(w) {
      let look = theme().chat_list.state_quiet.then(ask_line_button_words)
      w
      .words(By(label))
      .words_look(By(fn() { ask_line_words_look(look) }))
      .ink(By(fn() { mix(theme().p.text, lit.shown(w), theme().p.muted) }))
      |> ignore
    })
    |> ignore
  })
}

///|
/// How faded ask_line_button_node is where it takes no press (ask_line_button's 0.45).
let ask_line_faded : Double = 0.45
