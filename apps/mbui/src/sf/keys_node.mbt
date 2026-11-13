// 快捷键's parts as nodes of the window's tree, made once (controls.css.ts textToggle): an action's
// row, the button that shows its keys and records new ones, the rows together as the page's width lays them out, and a
// quiet word to press.

///|
/// A quiet word to press (controls.css.ts textToggle, keys_toggle's): the meta's size, muted, the words' ink under the
/// hand, 2 by 4 in; pressed as an old view's box with an id is (its ripple and sink, square), `press` done then; read
/// out a button named as it says.
#callsite(autofill(loc))
pub fn text_toggle_node(parent : @view.View, words : () -> String, press : () -> Unit, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(b) {
    b.padding(Is((text_toggle_x, text_toggle_y, text_toggle_x, text_toggle_y))) |> ignore
    b.radius(Is(tap_corner)) |> ignore
    pressed_node(b, press, Is(tap_corner), Button, words)
    words_node(b, words, fn() { if lit_node(b) { text_toggle_hot } else { text_toggle_words } }) |> ignore
  })
  |> ignore
}

///|
/// textToggle's room round its words (px=S1 py=S0_5).
let text_toggle_x : Double = 4.0

///|
let text_toggle_y : Double = 2.0

///|
// kept across runs: a value (no field of it changes)
let text_toggle_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L4_75, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let text_toggle_hot : @ui.TextStyle = text_toggle_words.then(@ui.text_style(color=Fg))

///|
/// The rows of keys of a group, made by `rows` in it, 2 apart: wide, on the page as they are;
/// narrow, on a page's card, reaching into its room over the first and under the last by as much as a row's keys stand
/// in from its top and foot, less what holds the first's and the last's keys out of the card's corners: on the card's
/// words' line at its end (card_pad in), as far down as its corner is round (the user's 第 3 版, 2026-11-03: a control
/// in a card's corner stays out of it, its row's spacing as it was).
#callsite(autofill(loc))
pub fn keys_rows_node(parent : @view.View, rows : (@view.View) -> Unit, loc~ : SourceLoc) -> Unit {
  let list = fn(p : @view.View, reach : Double) {
    p.box(fn(l) {
      l.gap(Is(keys_rows_gap)).margin(Is((0.0, reach, 0.0, reach))) |> ignore
      rows(l)
    })
    |> ignore
  }
  match part_of(parent).look {
    Wide => list(parent, 0.0)
    Narrow => page_card_node(loc~, parent, fn(k) { list(k, (keys_record_h - keys_row_h) / 2.0 + (card_corner - card_pad)) })
  }
}

///|
let keys_rows_gap : Double = 2.0

///|
/// An action's row: its `name` across what is left, 恢复默认 (`reset_words`) once it is
/// `changed`, then its keys on a button (keys_record_node: `keys` as they read, subtle where it has `none`); 40 high
/// at least, 8 apart, in the middle of its line. Where the line has not the room for its name whole beside them, what
/// follows it goes on in a line of its own under it, at its end, its name the whole of the first; its keys cut short
/// only where they are wider than a line alone.
#callsite(autofill(loc))
pub fn keys_row_node(
  parent : @view.View,
  name : () -> String,
  keys : () -> String,
  none : () -> Bool,
  recording : () -> Bool,
  record : () -> Unit,
  changed : () -> Bool,
  reset : () -> Unit,
  reset_words : () -> String,
  recording_words : () -> String,
  loc~ : SourceLoc,
) -> Unit {
  parent.box(made_for=loc, fn(r) {
    r
    .row(Is(true))
    .min_height(Is(Some(keys_row_h)))
    .gap(Is(keys_row_gap))
    .wraps(Is(Some(0.0)))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(End))
    |> ignore
    r.box(fn(l) {
      // (its line as high as the row at least, its words across its middle: a line of a row that wraps is as high as
      // what is on it, not the row's least)
      l
      .grow(Is(1.0))
      .shrink(Is(1.0))
      .min_width(Is(Some(0.0)))
      .min_height(Is(Some(keys_row_h)))
      .lies_along(Is(Middle))
      |> ignore
      words_node(l, name, fn() { keys_row_words }) |> ignore
    })
    |> ignore
    r.show(changed, fn(t) { text_toggle_node(t, reset_words, reset) })
    keys_record_node(r, name, keys, none, recording, record, recording_words)
  })
  |> ignore
}

///|
let keys_row_h : Double = 40.0

///|
let keys_row_gap : Double = 8.0

///|
// kept across runs: a value (no field of it changes)
let keys_row_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L5, color=Fg)

///|
/// An action's keys on a button: 120 wide at least, 30 high, 12 in, the ladder's small
/// block's corner, the hover's ground, its words in the middle (subtle where it has `none`); while it records
/// (`recording`), the accent's ground and words, saying so (`recording_words`); under the hand the hover's laid over its
/// ground (record's hovered, as Style::resolve lays it: the pointer over it, pressed, the keyboard's focus on it,
/// lit_node). Pressed as an old view's box
/// with an id is (its ripple and sink in its corner), `record`; read out a button named `name`.
#callsite(autofill(loc))
fn keys_record_node(
  parent : @view.View,
  name : () -> String,
  keys : () -> String,
  none : () -> Bool,
  recording : () -> Bool,
  record : () -> Unit,
  recording_words : () -> String,
  loc~ : SourceLoc,
) -> Unit {
  parent.box(made_for=loc, fn(b) {
    b
    .row(Is(true))
    // (on a line of its own and wider than it, giving way down to its least, its keys cut short)
    .shrink(Is(1.0))
    .min_width(Is(Some(keys_record_w)))
    .height(Is(Some(keys_record_h)))
    .padding(Is((keys_record_x, 0.0, keys_record_x, 0.0)))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    .radius(Is(small_corner))
    .ground(By(fn() {
      // (the hover's over its own under the hand, record's hovered: the accent's kept while it records)
      let theme = @ui.tree_theme()
      let under = theme.color(if recording() { AccentBg } else { Hover })
      if lit_node(b) {
        @ui.over(under, theme.color(Hover))
      } else {
        under
      }
    }))
    |> ignore
    pressed_node(b, record, Is(small_corner), Button, name)
    words_node(b, fn() { if recording() { recording_words() } else { keys() } }, fn() {
      if recording() {
        keys_record_on_words
      } else if none() {
        keys_record_none
      } else {
        keys_record_words
      }
    })
    |> ignore
  })
  |> ignore
}

///|
let keys_record_w : Double = 120.0

///|
let keys_record_h : Double = 30.0

///|
let keys_record_x : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let keys_record_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L5, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let keys_record_none : @ui.TextStyle = keys_record_words.then(@ui.text_style(color=Subtle))

///|
// kept across runs: a value (no field of it changes)
let keys_record_on_words : @ui.TextStyle = keys_record_words.then(@ui.text_style(color=AccentText))
