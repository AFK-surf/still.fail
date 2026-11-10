// A small panel's parts as nodes of the window's tree, for a panel whose body is nodes (panel_nodes): a group of its rows
// under a small label (panel_group's), a note (panel_note's), a row to press (menu_item's `panel` row) and a row that
// turns something on or off (switch_row's in a panel). Each laid out from where its presenter put the body (lent to
// the column it makes the body in: panel_in_lend), as the old frame's presenters say it to an old body (in_small_panel,
// words_in_now, rows_out), so they stand where the old ones did.

///|
/// Where a panel's body made of nodes is laid out, lent by its presenter to the column it makes it in: how far in from
/// that column its words go (words_in_now's), how far its rows reach out across the room the panel leaves (rows_out's),
/// whether it is a small panel beside what opened it (in_small_panel's) and how far clear of an untitled dialog's close
/// button at its end its words keep (untitled_clear's); with its look (look_lent: a sheet's narrow, a small panel's and
/// a dialog's wide), so what the body makes reads them however late it is made.
priv struct PanelIn {
  words : Double
  rows_out : Double
  small : Bool
  clear : Double
}

///|
// kept across runs: what each presenter lends the body it makes, let go with it
let panel_in_lent : @view.Lent[PanelIn] = @view.Lent::new()

///|
/// The column `col` a panel's body is made in by its presenter, laid out `look`, its words `words` in, its rows out
/// `rows_out`, in a small panel where `small`, `clear` clear of an untitled dialog's close button.
fn panel_in_lend(
  col : @view.View,
  look : Look,
  words : Double,
  rows_out? : Double = 0.0,
  small? : Bool = false,
  clear? : Double = 0.0,
) -> Unit {
  look_lent(col, look)
  col.lends(panel_in_lent, { words, rows_out, small, clear }) |> ignore
}

///|
/// Where the tips of what a panel's body and foot are made of are shown (panel_icon_button_node's): the window's layer
/// of them over all of it, lent by presented_nodes to each of what it presents, read as what the panel holds is made.
// kept across runs: what each presented one is lent, let go with it
let panel_tips_lent : @view.Lent[TipLayer] = @view.Lent::new()

///|
/// How far a row of a panel's body laid out `at` reaches out of the column it is made in, its ground across the room
/// the panel leaves at its sides, its words back on the column's line (row_reach's): that room (rows_out), no further
/// than its own words are in from its ground (`own`, none said: all of it); none in a small panel (its rows at its
/// padding) or outside a panel. The rule of every row of a panel's: panel_row_node's, choice_row_node's.
fn panel_rows_out(at : PanelIn, own? : Double = @double.infinity) -> Double {
  if at.small {
    0.0
  } else {
    dmin(at.rows_out, own)
  }
}

///|
/// Which of what a dialog in the middle of the window holds takes the keyboard's focus as the dialog opens, where what
/// it holds says one (panel_opens_on_node): lent by panel_centred_node to its dialog, read as all it holds is made.
// kept across runs: what each dialog lends, let go with it
let panel_opens_lent : @view.Lent[Ref[@view.View?]] = @view.Lent::new()

///|
/// `v`, a part of what a panel's body or foot is made of, takes the keyboard's focus as its panel opens in the middle
/// of the window, in place of the first of what it holds that takes it: what Enter does there at once (a question's
/// yes). Said as the panel's body or foot is made. Nothing where the panel gives the focus to none of what it holds (a
/// sheet, a panel beside what opened it).
pub fn panel_opens_on_node(v : @view.View) -> Unit {
  match v.lent(panel_opens_lent) {
    Some(r) => r.val = Some(v)
    None => ()
  }
}

///|
/// Where node `v` of a panel's body is laid out (none outside a panel).
fn panel_in_of(v : @view.View) -> PanelIn {
  v.lent(panel_in_lent).unwrap_or({ words: 0.0, rows_out: 0.0, small: false, clear: 0.0 })
}

///|
/// A group of a panel's rows in `parent` (panel_group's): under a small `label` (12, muted, in by a row's padding, 2
/// over its rows; none where it is ""), what `body` makes, 2 apart.
#callsite(autofill(loc))
pub fn panel_group_node(
  parent : @view.View,
  label : () -> String,
  body : (@view.View) -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  parent.box(made_for=loc, fn(g) {
    style_node(g, fn() { panel_group_box })
    g.show(fn() { label() != "" }, fn(l) {
      style_node(l, fn() { panel_label_at })
      words_node(l, label, fn() { panel_note_words }) |> ignore
    })
    body(g)
  })
  |> ignore
}

///|
/// A note in a panel in `parent` (panel_note's): 12, muted, in by a row's padding.
#callsite(autofill(loc))
pub fn panel_note_node(parent : @view.View, words : () -> String, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(n) {
    style_node(n, fn() { panel_text_box })
    words_node(n, words, fn() { panel_note_words }) |> ignore
  })
  |> ignore
}

///|
/// A panel's row to press in `parent` (menu_item's `panel` row): its icon 18 in a column 20 wide, 10 from its words, in
/// the red where `danger`, what it is at now (`note`) at its end, quiet, and `end` an icon after that; reaching past the
/// panel's padding as a menu's row does (menu_row_reach), its words a row's padding in, its ground under the hand.
/// Read out a button named by its words and its note; `press` as it is pressed.
#callsite(autofill(loc))
pub fn panel_row_node(
  parent : @view.View,
  label : () -> String,
  press : () -> Unit,
  icon? : () -> String = fn() { "" },
  note? : () -> String = fn() { "" },
  end? : String = "",
  danger? : Bool = false,
  loc~ : SourceLoc,
) -> Unit {
  panel_row_by(loc~, parent, label, fn(_) { press() }, icon, note, end, danger)
}

///|
/// A panel's row (panel_row_node's) that opens a panel beside itself: `open` given the row, as it is pressed, what that
/// panel goes beside (Anchor's Node); a chevron at its end.
#callsite(autofill(loc))
pub fn panel_row_opens_node(
  parent : @view.View,
  label : () -> String,
  open : (Anchor) -> Unit,
  icon? : () -> String = fn() { "" },
  note? : () -> String = fn() { "" },
  loc~ : SourceLoc,
) -> Unit {
  panel_row_by(loc~, parent, label, fn(r) { open(Node(r)) }, icon, note, "chevron-right", false)
}

///|
/// panel_row_node's row, `press` given the row itself as it is pressed.
#callsite(autofill(loc))
fn panel_row_by(
  parent : @view.View,
  label : () -> String,
  press : (@view.View) -> Unit,
  icon : () -> String,
  note : () -> String,
  end : String,
  danger : Bool,
  loc~ : SourceLoc,
) -> Unit {
  let at = panel_in_of(parent)
  parent.box(made_for=loc, fn(r) {
    let t = fn() { theme() }
    // (out across the room a large panel leaves, a card's corner there; else a capsule in a small panel's corners, past
    // its padding to where it is concentric with them: menu_item's)
    let reach = fn() { menu_row_reach(t().rows.pick) }
    let across = panel_rows_out(at)
    let out = fn() { if across > 0.0 { across } else { reach() } }
    let words_at = fn() { if across > 0.0 { across } else { text_in + reach() } }
    let corner = if across > 0.0 { card_corner } else { small_panel_inner(r_menu) }
    r
    .row(Is(true))
    .min_height(By(fn() { Some(t().rows.pick) }))
    .margin(By(fn() { (-out(), 0.0, -out(), 0.0) }))
    .padding(By(fn() { (words_at(), menu_row_over, words_at(), menu_row_over) }))
    .gap(Is(panel_row_gap))
    .lines_up(Is(Some(Middle)))
    .radius(Is(corner))
    .ground(By(fn() { if lit_node(r) { t().p.hover } else { 0L } }))
    .says(By(fn() {
      let n = note()
      Some(@view.said(Button, label=if n == "" { label() } else { label() + " " + n }))
    }))
    |> ignore
    presses_node(r, fn() { press(r) })
    r.show(fn() { icon() != "" }, fn(col) {
      style_node(col, fn() { panel_row_icon }, in_row=true)
      icon_node(col, "", panel_icon, By(fn() { t().p.muted }), name_now=icon) |> ignore
    })
    r.box(fn(w) {
      w
      .grow(Is(1.0))
      .basis(Is(Some(0.0)))
      .min_width(Is(Some(0.0)))
      .words(By(label))
      .words_look(By(fn() { { size: t().t.ui, weight: 400, line: panel_row_line, wrap: false, tracking: @view.letters_own, balance: false } }))
      .ink(By(fn() { if danger { t().p.red } else { t().p.text } }))
      |> ignore
    })
    |> ignore
    r.show(fn() { note() != "" }, fn(w) {
      w
      .words(By(note))
      .words_look(By(fn() {
        { size: t().t.meta, weight: 400, line: -@ui.tree_theme().text_line, wrap: false, tracking: @view.letters_own, balance: false }
      }))
      .ink(By(fn() { t().p.muted }))
      |> ignore
    })
    if end != "" {
      icon_node(r, end, panel_end_icon, By(fn() { t().p.subtle })) |> ignore
    }
  })
  |> ignore
}

///|
/// A panel's row's line (menu_item's words: 20).
let panel_row_line : Double = 20.0

///|
/// A panel's row that turns something on or off in `parent` (switch_row's in a panel): `title`, its switch at its end,
/// which alone answers (`on`, `turn`: switch_node's). In a sheet (narrow) a narrow row's (min a row's height, 12
/// between), its words as far in as the panel's (words_in_now's); beside what opened it (wide) a wide control row's,
/// its title as strong as a setting's.
#callsite(autofill(loc))
pub fn panel_switch_row_node(
  parent : @view.View,
  title : () -> String,
  on : () -> Bool,
  turn : (Bool) -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  let control = fn(r : @view.View) { switch_node(r, on, turn, title) }
  if look_node(parent) is Wide {
    wide_control_row_node(parent, title, fn() { "" }, None, control, looks=(fn() { setting_title() }, fn() { theme().rows.note }))
    return
  }
  let at = panel_in_of(parent)
  parent.box(made_for=loc, fn(r) {
    style_node(r, fn() { pg_said_row_square.then(@ui.style(min_h=Fixed(theme().items.least), px=room(at.words))) })
    r.box(fn(words) {
      style_node(words, fn() { pg_row_words }, in_row=true)
      words.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
      words_node(words, title, fn() { pg_switch_title }) |> ignore
    })
    |> ignore
    control(r)
  })
  |> ignore
}
