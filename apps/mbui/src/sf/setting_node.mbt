// A page's settings made once (setting's, setting_switch's, setting_link's, as nodes): wide, each a row of the page's
// list card, its title (as strong as the list's rows': setting_title) and what it is for under it, its control at its
// end; narrow, each a section of its own, its title over its control and what it is for under that.

///|
/// One setting (setting's): `title`, what it is for (`note`), what `control` makes (a choice, a button, the colour
/// themes' dots): wide, a row with the control at its end (wide_control_row_node: on a list's card, a row of it);
/// narrow, a section of its own, its title over the control, what it is for under it; `in_card` (a group's, narrow), a
/// row of it: its title over the control, what it is for under it, as far in as its rows' words (setting's in a card:
/// a section of the page there stood at the card's edge, 2026-10-29 高级网络设置).
#callsite(autofill(loc))
pub fn setting_node(
  parent : @view.View,
  title : () -> String,
  control : (@view.View) -> Unit,
  note? : () -> String = fn() { "" },
  in_card? : Bool = false,
  loc~ : SourceLoc,
) -> Unit {
  match look_node(parent) {
    Wide =>
      wide_control_row_node(parent, title, note, None, control, looks=(fn() { setting_title() }, fn() {
        theme().rows.note
      }))
    Narrow if in_card =>
      parent.box(made_for=loc, fn(r) {
        r.padding(Is((text_in, text_in, text_in, text_in))).min_height(By(fn() { Some(theme().items.least) })) |> ignore
        words_node(r, title, fn() { pg_switch_title }) |> ignore
        // (between its title and its note, 8 from each: setting_in_card_control)
        r.box(fn(k) {
          k.padding(Is((0.0, setting_in_card_y, 0.0, setting_in_card_y))) |> ignore
          control(k)
        })
        |> ignore
        r.show(fn() { note() != "" }, fn(n) { words_node(n, note, fn() { meta.then(full_words) }) |> ignore })
      })
      |> ignore
    Narrow => section_node(parent, title, control, about=note)
  }
}

///|
/// A narrow card's setting's control's room over and under it (setting_in_card_control's py=S2).
let setting_in_card_y : Double = 8.0

///|
/// A setting of a few choices (setting's with page_choice's in it): wide, its row with the options at its end, as wide
/// as they are (seg_node); narrow, a section of its own, the options as wide as the page's room (page_choice_node), what
/// it is for under them. `labels`, `chosen`, `choose`: page_choice_node's. `alone`: the page's only setting there, not
/// one of a group's rows: wide, a list card of its own (group_node) round its row.
#callsite(autofill(loc))
pub fn setting_choice_node(
  parent : @view.View,
  title : () -> String,
  labels : () -> Array[String],
  chosen : () -> Int,
  choose : (Int) -> Unit,
  note? : () -> String = fn() { "" },
  alone? : Bool = false,
  loc~ : SourceLoc,
) -> Unit {
  match look_node(parent) {
    Wide if alone =>
      group_node(loc~, parent, fn(g) {
        setting_node(loc~, g, title, fn(r) { seg_node(r, labels, chosen, choose) |> ignore }, note~)
      })
    Wide => setting_node(loc~, parent, title, fn(r) { seg_node(r, labels, chosen, choose) |> ignore }, note~)
    Narrow => section_node(parent, title, fn(s) { page_choice_node(s, labels, chosen, choose) }, about=note)
  }
}

///|
/// A setting turned on or off (setting_switch's): wide, its row with a small switch at its end; narrow, a section of
/// its own, the switch on its heading's line at its end, what it is for under it. `on`, `turn`: switch_node's.
#callsite(autofill(loc))
pub fn setting_switch_node(
  parent : @view.View,
  title : () -> String,
  on : () -> Bool,
  turn : (Bool) -> Unit,
  note? : () -> String = fn() { "" },
  loc~ : SourceLoc,
) -> Unit {
  let control = fn(r : @view.View) { switch_node(r, on, turn, title, small=true) }
  match look_node(parent) {
    Wide => setting_node(loc~, parent, title, control, note~)
    Narrow => {
      heading_node(parent, title, ends=control)
      parent.show(fn() { note() != "" }, fn(n) { page_note_node(n, note) })
    }
  }
}

///|
/// A setting that opens a page of its own (setting_link's): wide, a row of the list going there, what it is now
/// (`value`) at its end; narrow, a section of its own, a row on a card saying what it is now going there, what it is
/// for under it. `press` done as it is pressed.
#callsite(autofill(loc))
pub fn setting_link_node(
  parent : @view.View,
  title : () -> String,
  value : () -> String,
  press : () -> Unit,
  note? : () -> String = fn() { "" },
  loc~ : SourceLoc,
) -> Unit {
  match look_node(parent) {
    Wide => link_row_node(loc~, parent, title, press, value~, note~, wide_title=fn() { setting_title() })
    Narrow =>
      section_node(parent, title, about=note, fn(s) { group_node(s, fn(g) { link_row_node(g, value, press) }) })
  }
}
