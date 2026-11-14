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
/// (untitled_clear's); whether it is a row of a panel's list (panel_list_node's: `listed`); with its look (look_lent: a sheet's narrow, a small panel's and
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
  listed : Bool
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
  listed? : Bool = false,
) -> Unit {
  look_lent(col, look)
  col.lends(panel_in_lent, { words, sides, rows_out, small, centred, clear, listed }) |> ignore
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
/// The corner of a row of a panel's body (not a small panel's) reaching `out` past its column: row_corner where it still
/// stands in from the panel's sides (PanelIn's `sides`), never a square patch there (the corner rule's lit square,
/// 2026-11-13); square where it reaches them, a sheet's row across it.
fn panel_row_corner(at : PanelIn, out : Double) -> Double {
  if at.sides - out > 0.5 {
    row_corner
  } else {
    0.0
  }
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
/// Whether a panel gives its field `self` the keys as it opens, shown as a sheet from the foot (`as_sheet`) or in the
/// window's middle or beside what opened it: a field it is for (panel_opens_in_node), always; a search at hand
/// (panel_search_at_hand_node), only where it is no sheet and the app's native input is keys and a mouse. With a finger
/// the keys given are an input method raised over what it lists, in the window's middle (a tablet, a fold laid open) as
/// on a sheet.
fn PanelField::keyed(self : PanelField, as_sheet : Bool) -> Bool {
  self.sheet || (!as_sheet && !(native_input() is Finger))
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
/// show it in the window's middle or beside what opened it and the app's native input is keys and a mouse (typed into
/// at once there), as panel_opens_in_node's has (View::focus_opens, given back as it goes); not on a sheet from its
/// foot, nor anywhere the native input is a finger (a tablet's dialog in the middle, a fold laid open), where what it
/// lists is looked at first and an input method raised would cover it: there the focus is left where it is (a dialog
/// in the middle keeps it on its own ground, no field of it), the field taken when it is pressed (PanelField::keyed).
/// The old frame's presenters' `field` (panel's `field`: given it where it is not a sheet). Said once as the panel's
/// body is made; a page never says how its panel is shown.
///
/// | caller | its field | shown |
/// |---|---|---|
/// | sfpages outline.mbt, 对话目录 from its round button | what it finds | a sheet on 小屏, beside the button |
/// | sfdesk drive_dialogs.mbt, the folder picker | its filter | a sheet on 小屏, a dialog in the middle |
/// | sfpages presets.mbt, 添加目录 | its search | a sheet on 小屏, a dialog in the middle |
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
  v.lent(panel_in_lent).unwrap_or({ words: 0.0, sides: 0.0, rows_out: 0.0, small: false, centred: false, clear: 0.0, listed: false })
}

///|
/// A group of a panel's rows in `parent` (panel_group's): under a small `label` (12, muted, in by a row's padding, 2
/// over its rows; none where it is ""), what `body` makes, 2 apart. `lead`: what it makes before the label, on its line
/// 6 apart (panel_group's `lead`: a head of the group's own before how many).
#callsite(autofill(loc))
pub fn panel_group_node(
  parent : @view.View,
  label : () -> String,
  body : (@view.View) -> Unit,
  lead? : (@view.View) -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  parent.box(made_for=loc, fn(g) {
    style_node(g, fn() { panel_group_box })
    g.show(fn() { label() != "" }, fn(l) { panel_label_in(l, label, lead?=lead, loc~) })
    body(g)
  })
  |> ignore
}

///|
/// A heading of a panel's rows in `parent`, standing alone (panel_group_node's label: where its rows are a list's, each
/// made as it shows, panel_list_node's): 12, muted, in by a row's padding, 2 over the rows under it.
#callsite(autofill(loc))
pub fn panel_heading_node(parent : @view.View, label : () -> String, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(l) { panel_label_in(l, label, loc~) }) |> ignore
}

///|
/// What a group's label is (panel_group_node's, panel_heading_node's) in `l`, what `lead` makes before it.
fn panel_label_in(l : @view.View, label : () -> String, lead? : (@view.View) -> Unit, loc~ : SourceLoc) -> Unit {
  let at = panel_in_of(l)
  // (in a sheet's list, its words said where the sheet's are: on that line, as the rows' words and faces are)
  if at.listed && !at.small && at.words > 0.0 {
    style_node(l, fn() { panel_label_at.then(@ui.style(px=room(at.words))) })
  } else {
    style_node(l, fn() { panel_label_at })
  }
  match lead {
    Some(draw) =>
      l.box(made_for=loc, fn(r) {
        style_node(r, fn() { panel_label_led })
        draw(r)
        words_node(r, label, fn() { panel_note_words }) |> ignore
      })
      |> ignore
    None => words_node(l, label, fn() { panel_note_words }) |> ignore
  }
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
  lit? : () -> Bool = fn() { false },
  titled? : Bool = true,
  face? : (Double, (@view.View) -> Unit),
  point? : () -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  let at = panel_in_of(parent)
  let foot = parent.lent(foot_rows_lent)
  @headless.button(
    made_for=loc,
    parent,
    fn() {
      let n = note()
      if n == "" {
        label()
      } else {
        label() + " " + n
      }
    },
    press,
    fn(r, _) {
      let t = fn() { theme() }
      // (at a dialog's foot, out to where it is concentric with its foot corners, its words on its line; out across the
      // room a large panel leaves, a card's corner there; else a capsule in a small panel's corners, past its padding to
      // where it is concentric with them: menu_item's)
      let reach = fn() { menu_row_reach(t().rows.pick) }
      // (a row of a list in a sheet, its words said where the sheet's are and no room to reach: its ground panel_card_in in
      // from the sheet's sides, as a card the body lays out itself is (panel_card_out_node: `sides`), its words on the
      // sheet's words' line; not a small panel's capsule at the list's edge)
      let sheet_listed = at.listed && !at.small && at.words > 0.0 && (match panel_row_at(at) {
        Some(p) => p.out == 0.0
        None => false
      })
      let sheet_in = if sheet_listed { dmax(0.0, panel_card_in - at.sides) } else { 0.0 }
      // (its reach alone the rows' rule's, panel_row_at: where that is none, a small panel's or a sheet's, a menu's row's
      // capsule, menu_item's own, not a page row's padding; at a dialog's foot, out to its foot corners: foot_rows_lent)
      let across = match panel_row_at(at) {
        Some(p) => p.out
        None => 0.0
      }
      let out = fn() {
        match foot {
          Some(f) => f()
          None => if sheet_listed { -sheet_in } else if across > 0.0 { across } else { reach() }
        }
      }
      let words_at = fn() {
        match foot {
          Some(f) => f()
          None => if sheet_listed { at.words - sheet_in } else if across > 0.0 { across } else { text_in + reach() }
        }
      }
      // (a sheet's list's: a sheet's row's corner, as a pick's rows are (pick_row_node), its words a row's padding in; a
      // card's corner there made a capsule of it, its words in the curve of its ends)
      let corner = if sheet_listed { row_corner } else if across > 0.0 { card_corner } else { small_panel_inner(r_menu) }
      if foot is Some(_) {
        style_node(r, fn() { menu_row_capsule })
      } else {
        r.radius(Is(corner)) |> ignore
      }
      r
      .row(Is(true))
      .min_height(By(fn() { Some(t().rows.pick) }))
      .margin(By(fn() { (-out(), 0.0, -out(), 0.0) }))
      |> ignore
      // (`face`: a round one `size` across first, in a column of its own: stood in from the row's start as far as its
      // top is from the row's (concentric in its corner, the corner less its radius), the column reaching on to where an
      // icon's ends, so what follows it stands where it does after an icon)
      let face_in = fn() {
        match face {
          // (a sheet's list's ground stands as a sheet's rows' do: the face concentric in its corner, though that is
          // further in than its words would be)
          // (the corner as drawn: no rounder than half the row's least height, a capsule's)
          Some((size, _)) if sheet_listed => dmin(corner, t().rows.pick / 2.0) - size / 2.0
          Some((size, _)) => dmin(words_at(), dmin(corner, t().rows.pick / 2.0) - size / 2.0)
          None => words_at()
        }
      }
      r
      .padding(By(fn() { (face_in(), menu_row_over, words_at(), menu_row_over) }))
      .gap(Is(if plain { menu_row_gap } else { panel_row_gap }))
      .lines_up(Is(Some(Middle)))
      // (the hand's ground, and the one the keys are at only where the hand rests (a pointer and keys): a finger moves no
      // keys' row, and on it that ground stood under the reader's row at rest, a second beside the one pressed. Where the
      // pointer moving onto a row takes the keys there (`point`), the pointer's own is that one: one ground, never two)
      .ground(By(fn() {
        let hand = if point is Some(_) { lit_node(r) && !hovered_node(r) } else { lit_node(r) }
        if hand || (lit() && pointer_rests()) { t().p.hover } else { 0L }
      }))
      |> ignore
      // (the pointer's own moving onto it, never a list scrolled under a pointer at rest: what the keys move stays theirs)
      if point is Some(p) {
        r.on_pointer_moved(p) |> ignore
      }
      match face {
        Some((face_size, fill)) =>
          r.box(fn(col) {
            style_node(
              col,
              fn() { panel_row_face.then(@ui.style(w=Fixed(dmax(face_size, panel_row_icon_w + words_at() - face_in())))) },
              in_row=true,
            )
            fill(col)
          })
          |> ignore
        None => ()
      }
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
      // (its label as its words; not where what it is made of says them: `titled` false, a said row's, its label read
      // out only)
      if titled {
        r.box(fn(w) {
          w
          .grow(Is(1.0))
          .basis(Is(Some(0.0)))
          .min_width(Is(Some(0.0)))
          .words(By(label))
          .words_look(By(fn() { { size: t().t.ui, weight: 400, line: panel_row_line, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 } }))
          .ink(By(fn() { if danger { t().p.red } else { t().p.text } }))
          |> ignore
        })
        |> ignore
      }
      r.show(fn() { note() != "" }, fn(w) {
        w
        .words(By(note))
        .words_look(By(fn() {
          { size: t().t.meta, weight: 400, line: -@ui.tree_theme().text_line, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }
        }))
        .ink(By(fn() { t().p.muted }))
        |> ignore
      })
      if end != "" {
        icon_node(r, end, panel_end_icon, By(fn() { t().p.subtle })) |> ignore
      }
      made(r)
    },
  )
  |> ignore
}

///|
/// A panel's row's line (menu_item's words: 20).
let panel_row_line : Double = 20.0

///|
/// A row of a panel's that is something said (a chat's outline's, what was found in it) in `parent`, laid out as
/// panel_row_node's (its reach past the panel's padding, its words a row's padding in, its corner, its ground under the
/// hand or the keyboard's focus): `words` on one line, cut short where it has not the room; `end` at that line's end,
/// quiet (a time); `lead` in the icon's column before them (a face), the column kept where it draws none, so the words
/// of rows with and without one start together; `who`, a quiet line over the words (those words), its face in that column
/// before both lines; each given how large a face is there (a row's icon's). `chosen`: the one the reader is at, in the accent's ink
/// as a pick's chosen choice is (pick_row_node's). `lit`: the one the keys are at (a list's ↑ ↓ from its field), where the hand rests on
/// the ground the hand's is; `point`, the pointer moving onto it, to take the keys there. Read out a button named `label`; `press` as it is pressed (a press, Enter or Space with the focus on it).
#callsite(autofill(loc))
pub fn panel_said_row_node(
  parent : @view.View,
  words : () -> Array[@ui.Run],
  press : () -> Unit,
  label : () -> String,
  lead? : (@view.View, Double) -> Unit,
  end? : () -> String = fn() { "" },
  who? : (() -> String, (@view.View, Double) -> Unit),
  chosen? : () -> Bool = fn() { false },
  lit? : () -> Bool = fn() { false },
  point? : () -> Unit,
  made? : (@view.View) -> Unit = fn(_) {  },
  loc~ : SourceLoc,
) -> Unit {
  let t = fn() { theme() }
  let quiet = fn() -> @view.WordsLook {
    { size: t().t.meta, weight: 400, line: -@ui.tree_theme().text_line, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }
  }
  let said = fn(into : @view.View) {
    into.box(fn(w) {
      w
      .grow(Is(1.0))
      .basis(Is(Some(0.0)))
      .min_width(Is(Some(0.0)))
      .words_runs(By(words))
      .words_look(By(fn() {
        { size: t().t.ui, weight: if chosen() { 500 } else { 400 }, line: panel_row_line, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }
      }))
      .ink(By(fn() { if chosen() { t().p.accent_text } else { t().p.text } }))
      .allow_ellipsis(Is(true))
      |> ignore
    })
    |> ignore
    into.show(fn() { end() != "" }, fn(e) {
      e.shrink(Is(0.0)).words(By(end)).words_look(By(quiet)).ink(By(fn() { t().p.muted })) |> ignore
    })
  }
  // (the face in a column of its own before the words, a found row's before both its lines: the words of every row
  // start together)
  let face = match (who, lead) {
    (Some((_, f)), _) | (None, Some(f)) => Some((panel_icon, fn(col : @view.View) { f(col, panel_icon) }))
    _ => None
  }
  panel_row_by(loc~, parent, label, fn(_) { press() }, fn() { "" }, fn() { "" }, "", false, lit~, titled=false, face?, point?, made=fn(r) {
    match who {
      Some((name, _)) =>
        // (who over what they said, both as far in as the row's words)
        r.box(fn(lines) {
          lines.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))).gap(Is(@ui.Space::px(S0_5))) |> ignore
          lines.box(fn(n) {
            n.min_width(Is(Some(0.0))).words(By(name)).words_look(By(quiet)).ink(By(fn() { t().p.muted })).allow_ellipsis(Is(true))
            |> ignore
          })
          |> ignore
          lines.box(fn(l) {
            l.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(menu_row_gap)) |> ignore
            said(l)
          })
          |> ignore
        })
        |> ignore
      None => said(r)
    }
    made(r)
  })
}

///|
/// A panel's row that turns something on or off in `parent` (switch_row's in a panel): `title`, its switch at its end,
/// which alone answers (`on`, `turn`: switch_node's), in by a row's padding as the panel's labels, notes and choices are
/// (its words where theirs are, its switch where their ends are). In a sheet (narrow) a narrow row's (min a row's
/// height, 12 between); beside what opened it (wide) a wide control row's, its title as strong as a setting's.
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
    parent.box(made_for=loc, fn(b) {
      style_node(b, fn() { panel_text_box })
      wide_control_row_node(b, title, fn() { "" }, None, control, looks=(fn() { setting_title() }, fn() { theme().rows.note }), loc~)
    })
    |> ignore
    return
  }
  let at = panel_in_of(parent)
  // (as panel_label_in's: a sheet's list's words where the sheet's are, else a row's padding in)
  let sides = if at.listed && !at.small && at.words > 0.0 { room(at.words) } else { @ui.Space::S2_5 }
  parent.box(made_for=loc, fn(r) {
    style_node(r, fn() { pg_said_row_square.then(@ui.style(min_h=Fixed(theme().items.least), px=sides)) })
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
