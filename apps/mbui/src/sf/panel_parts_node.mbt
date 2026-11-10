// A small panel's parts as nodes of the window's tree, for a panel whose body is nodes (panel_nodes): a group of its rows
// under a small label (panel_group's), a note (panel_note's), a row to press (menu_item's `panel` row) and a row that
// turns something on or off (switch_row's in a panel). Each laid out from where its presenter put the body (lent to
// the column it makes the body in: panel_in_lend), as the old frame's presenters say it to an old body (in_small_panel,
// words_in_now, rows_out), so they stand where the old ones did.

///|
/// Where a panel's body made of nodes is laid out, lent by its presenter to the column it makes it in: how far in from
/// that column its words go (words_in_now's), how far its rows reach out across the room the panel leaves (rows_out's),
/// whether it is a small panel beside what opened it (in_small_panel's), whether it is a dialog in the middle of the
/// window (in_dialog's) and how far clear of an untitled dialog's close button at its end its words keep
/// (untitled_clear's); with its look (look_lent: a sheet's narrow, a small panel's and
/// a dialog's wide), so what the body makes reads them however late it is made.
priv struct PanelIn {
  words : Double
  /// how far in from the panel's sides the column is (its presenter's own room at its sides): what a card a page lays
  /// out itself in the body stands `panel_card_in` from the sides by (panel_card_out_node)
  sides : Double
  rows_out : Double
  small : Bool
  centred : Bool
  clear : Double
}

///|
// kept across runs: what each presenter lends the body it makes, let go with it
let panel_in_lent : @view.Lent[PanelIn] = @view.Lent::new()

///|
/// The column `col` a panel's body is made in by its presenter, laid out `look`, `sides` in from the panel's sides, its
/// words `words` in, its rows out `rows_out`, in a small panel where `small`, in a dialog in the middle of the window
/// where `centred`, `clear` clear of an untitled dialog's close button.
fn panel_in_lend(
  col : @view.View,
  look : Look,
  words : Double,
  sides~ : Double,
  rows_out? : Double = 0.0,
  small? : Bool = false,
  centred? : Bool = false,
  clear? : Double = 0.0,
) -> Unit {
  look_lent(col, look)
  col.lends(panel_in_lent, { words, sides, rows_out, small, centred, clear }) |> ignore
}

///|
/// Where the tips of what a panel's body and foot are made of are shown (panel_icon_button_node's): the window's layer
/// of them over all of it, lent by presented_nodes to each of what it presents, read as what the panel holds is made.
// kept across runs: what each presented one is lent, let go with it
let panel_tips_lent : @view.Lent[TipLayer] = @view.Lent::new()

///|
/// Where a row of a panel's body stands across: how far its ground reaches out of the column it is made in (`out`) and
/// how far in from its ground its words are (`side`).
priv struct PanelRowAt {
  out : Double
  side : Double
}

///|
/// Where a row of a panel's body laid out `at` stands across, row_line's, its ground's corner left to the row (each
/// kind's ground its own): its ground out across the room the panel leaves at its sides (rows_out), no further than its
/// own words are in from its ground (`own`, none said: all of it); its words in a small panel a row's padding in
/// (text_in, its ground at the panel's padding, reaching none), else as far in as the panel says (`words`: a sheet a
/// press opened, a panel's list), else back on the column's line (as far in as its ground reaches out). None outside a
/// panel's body or on a group's card in one (`card`): the row stands as its kind does on a page. The rule of every row
/// of a panel's: choice_row_node's, link_row_node's (narrow and wide), panel_row_node's reach.
fn panel_row_at(at : PanelIn, own? : Double = @double.infinity, card? : Bool = false) -> PanelRowAt? {
  guard !card else { return None }
  let out = if at.small { 0.0 } else { dmin(at.rows_out, own) }
  if at.small {
    Some({ out, side: text_in })
  } else if at.words > 0.0 {
    Some({ out, side: at.words })
  } else if out > 0.0 {
    Some({ out, side: out })
  } else {
    None
  }
}

///|
/// Which of what a dialog in the middle of the window holds takes the keyboard's focus as the dialog opens, where what
/// it holds says one (panel_opens_on_node): lent by panel_centred_node to its dialog, read as all it holds is made. A
/// field it opens to be typed in is panel_field_lent's, on every way a panel is shown.
// kept across runs: what each dialog lends, let go with it
let panel_opens_lent : @view.Lent[Ref[@view.View?]] = @view.Lent::new()

///|
/// `v`, a part of what a panel's body or foot is made of, takes the keyboard's focus as its panel opens in the middle
/// of the window, in place of the first of what it holds that takes it: what Enter does there at once (a question's
/// yes). Said as the panel's body or foot is made. Nothing where the panel gives the focus to none of what it holds (a
/// sheet, a panel beside what opened it): there Enter is the foot's action. A field to be typed in as it opens is
/// panel_opens_in_node's.
pub fn panel_opens_on_node(v : @view.View) -> Unit {
  match v.lent(panel_opens_lent) {
    Some(r) => r.val = Some(v)
    None => ()
  }
}

///|
/// Which field of what a panel holds has the keys as the panel opens (panel_opens_in_node, panel_search_at_hand_node):
/// lent by each of the panel's ways (panel_centred_node, sheet_node, panel_node) to what it holds, read as all it holds
/// is made.
// kept across runs: what each panel lends, let go with it
let panel_field_lent : @view.Lent[Ref[PanelField?]] = @view.Lent::new()

///|
/// The field a panel opens on: the field, and whether a sheet gives it the keys too (`sheet`: panel_opens_in_node's;
/// not panel_search_at_hand_node's).
priv struct PanelField {
  field : @view.View
  sheet : Bool
}

///|
/// `field`, a field of what a panel's body is made of, has the keyboard's focus as its panel opens, however the
/// presenters show it (in the window's middle, a sheet from its foot, beside what opened it), the input method up for it
/// with a finger: given it by the panel's layer as it opens (View::focus_opens), as anything a layer opens on is, given
/// back as it goes. Said once as the panel's body is made; a page never says how its panel is shown. For a field the
/// panel is for, to be typed in before anything else; a search over what the panel lists is
/// panel_search_at_hand_node's.
///
/// | caller | its field | shown |
/// |---|---|---|
/// | sfdesk files_go.mbt, 前往文件夹 | the path | a dialog in the middle (中屏, 大屏) |
/// | sfpages workspace.mbt, 新建 workspace | its name | a sheet on 小屏, a dialog in the middle |
pub fn panel_opens_in_node(field : @view.View) -> Unit {
  match field.lent(panel_field_lent) {
    Some(r) => r.val = Some({ field, sheet: true })
    None => ()
  }
}

///|
/// `field`, a search over what a panel's body lists, has the keyboard's focus as its panel opens where the presenters
/// show it in the window's middle or beside what opened it (typed into at once there), as panel_opens_in_node's has
/// (View::focus_opens, given back as it goes); not on a sheet from its foot, where what it lists is looked at first
/// and an input method raised would cover it: there the focus is left where it is, the field taken when it is pressed.
/// The old frame's presenters' `field` (panel's `field`: given it where it is not a sheet). Said once as the panel's
/// body is made; a page never says how its panel is shown.
///
/// | caller | its field | shown |
/// |---|---|---|
/// | (the old frame's panels that say `field`, as they move over) | | |
pub fn panel_search_at_hand_node(field : @view.View) -> Unit {
  match field.lent(panel_field_lent) {
    Some(r) => r.val = Some({ field, sheet: false })
    None => ()
  }
}

///|
/// Where node `v` of a panel's body is laid out (none outside a panel).
fn panel_in_of(v : @view.View) -> PanelIn {
  v.lent(panel_in_lent).unwrap_or({ words: 0.0, sides: 0.0, rows_out: 0.0, small: false, centred: false, clear: 0.0 })
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
/// Read out a button named by its words and its note; `press` as it is pressed. `plain`: a menu's row (menu_item's,
/// not its `panel` one: its icon 16 with no column, 8 from its words).
#callsite(autofill(loc))
pub fn panel_row_node(
  parent : @view.View,
  label : () -> String,
  press : () -> Unit,
  icon? : () -> String = fn() { "" },
  note? : () -> String = fn() { "" },
  end? : String = "",
  danger? : Bool = false,
  plain? : Bool = false,
  loc~ : SourceLoc,
) -> Unit {
  panel_row_by(loc~, parent, label, fn(_) { press() }, icon, note, end, danger, plain~)
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
/// How far the rows at a dialog's foot reach out past its words (dialog_foot_rows_node's, foot_rows_out's): lent by it
/// to what it holds, as it is now; none elsewhere.
// kept across runs: what each dialog's foot rows are lent, let go with them
let foot_rows_lent : @view.Lent[() -> Double] = @view.Lent::new()

///|
/// panel_row_node's row, `press` given the row itself as it is pressed. `plain`: a menu's row (menu_item's, not its
/// `panel` one): its icon 16 with no column of its own, 8 from its words. At a dialog's foot (foot_rows_lent) a capsule
/// out to where it is concentric with the dialog's foot corners, its words on the dialog's line. `made`: given the row
/// as it is made.
#callsite(autofill(loc))
fn panel_row_by(
  parent : @view.View,
  label : () -> String,
  press : (@view.View) -> Unit,
  icon : () -> String,
  note : () -> String,
  end : String,
  danger : Bool,
  plain? : Bool = false,
  made? : (@view.View) -> Unit = fn(_) {  },
  loc~ : SourceLoc,
) -> Unit {
  let at = panel_in_of(parent)
  let foot = parent.lent(foot_rows_lent)
  parent.box(made_for=loc, fn(r) {
    let t = fn() { theme() }
    // (at a dialog's foot, out to where it is concentric with its foot corners, its words on its line; out across the
    // room a large panel leaves, a card's corner there; else a capsule in a small panel's corners, past its padding to
    // where it is concentric with them: menu_item's)
    let reach = fn() { menu_row_reach(t().rows.pick) }
    // (its reach alone the rows' rule's, panel_row_at: where that is none, a small panel's or a sheet's, a menu's row's
    // capsule, menu_item's own, not a page row's padding; at a dialog's foot, out to its foot corners: foot_rows_lent)
    let across = match panel_row_at(at) {
      Some(p) => p.out
      None => 0.0
    }
    let out = fn() {
      match foot {
        Some(f) => f()
        None => if across > 0.0 { across } else { reach() }
      }
    }
    let words_at = fn() {
      match foot {
        Some(f) => f()
        None => if across > 0.0 { across } else { text_in + reach() }
      }
    }
    let corner = if across > 0.0 { card_corner } else { small_panel_inner(r_menu) }
    if foot is Some(_) {
      style_node(r, fn() { menu_row_capsule })
    } else {
      r.radius(Is(corner)) |> ignore
    }
    r
    .row(Is(true))
    .min_height(By(fn() { Some(t().rows.pick) }))
    .margin(By(fn() { (-out(), 0.0, -out(), 0.0) }))
    .padding(By(fn() { (words_at(), menu_row_over, words_at(), menu_row_over) }))
    .gap(Is(if plain { menu_row_gap } else { panel_row_gap }))
    .lines_up(Is(Some(Middle)))
    .ground(By(fn() { if lit_node(r) { t().p.hover } else { 0L } }))
    .says(By(fn() {
      let n = note()
      Some(@view.said(Button, label=if n == "" { label() } else { label() + " " + n }))
    }))
    |> ignore
    presses_node(r, fn() { press(r) })
    r.show(fn() { icon() != "" }, fn(col) {
      if plain {
        // (a menu's row's: the icon alone, 16, in the red where `danger`)
        icon_node(col, "", menu_item_icon, By(fn() { if danger { t().p.red } else { t().p.muted } }), name_now=icon)
        |> ignore
      } else {
        style_node(col, fn() { panel_row_icon }, in_row=true)
        icon_node(col, "", panel_icon, By(fn() { t().p.muted }), name_now=icon) |> ignore
      }
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
    made(r)
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
