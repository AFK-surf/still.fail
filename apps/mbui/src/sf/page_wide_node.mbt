// A page made once laid out wide (page.mbt wide_page, desk_lanes; the web's desktop pages: pages.css.ts page, pageHead,
// list, card; ui.tsx Section), as nodes: its head (back over its title on a page under another, its title, what it
// does at its line's end, what it is for under it), then its blocks in the lanes' column in the pane's middle, 80 at its
// foot; and the parts of it as a wide page has them, each taking its form from where it is made (part_of: lent by the
// page, a section, a group), what is shown in it later as well: a section with its title, a group's list card or card
// of words, a row that goes somewhere on it, a switch's row. Their styles page.mbt's and parts.mbt's, the same.

///|
/// What a wide page made once holds, in its order: what stands over it, its head, its blocks by their keys, the room
/// at its foot.
#derive(Eq, Hash)
priv enum WideItem {
  WideTop
  WideHead
  WideLead
  WideBlock(String)
  WideFoot
}

///|
/// A wide page made once (wide_page's) in node `v`: under what stands over it as the frame says (`frame`'s top), its
/// head (wide_head_node) where the frame's bar does not name it, else what it is for alone (barred_page's), its blocks (each made by `block` in the column, at its
/// edges: desk_block's 16 in; the first 16 under the head), then 80 at its foot and the frame's room; each part in its
/// lane (lane_node) and made only while it shows (as desk_lanes' old list builds only the rows in view).
#callsite(autofill(loc))
fn wide_page_node(
  v : @view.View,
  title : () -> String,
  blocks : () -> Array[String],
  block : (@view.View, String) -> Unit,
  on_back : () -> Unit,
  frame : () -> PageFrame,
  lead : () -> String,
  actions : ((@view.View) -> Unit)?,
  scroll : @view.Scroll,
  about : () -> String,
  tips : TipLayer,
  head : ((@view.View) -> Unit)?,
  near_foot : (Double, () -> Bool, () -> Unit)?,
  loc~ : SourceLoc,
) -> Unit {
  let items = fn() -> Array[WideItem] {
    let f = frame()
    let out = []
    if f.top > 0.0 {
      out.push(WideTop)
    }
    if head is Some(_) || !f.named {
      out.push(WideHead)
    } else if lead() != "" {
      out.push(WideLead)
    }
    for k in blocks() {
      out.push(WideBlock(k))
    }
    out.push(WideFoot)
    out
  }
  v.box(made_for=loc, fn(sc) {
    sc.grow(Is(1.0)) |> ignore
    // (at once, as it was: a debt of 方案 A, given its way list by list, shown to the owner: list-comes-off)
    sc.scrolls_window(scroll, items, bar=@ui.tree_scroll_bar(), est=pg_block_est, at_once=true, near_foot?, fn(s, item) {
      match item {
        // the room the frame keeps over it (a status bar's)
        WideTop => s.height(By(fn() { Some(frame().top) })) |> ignore
        WideHead =>
          match head {
            // (a head of its own as far down as a title's head stands, back over it where the frame says it goes;
            // under the frame's bar that names it, as far under it as what follows a head: wide_page's, barred_page's)
            Some(h) => lane_node(s, fn(col) { own_head_lane_node(col, h, on_back, frame) })
            None => lane_node(s, fn(col) { wide_head_node(col, title, on_back, frame, lead, actions, about, tips) })
          }
        // what it is for under the frame's bar that names it (barred_page's: desk_barred_lead, 16 in, 12 under)
        WideLead =>
          lane_node(s, fn(col) {
            col.padding(Is((head_in(col), 0.0, head_in(col), desk_head_foot))) |> ignore
            words_node(col, lead, fn() { desk_muted }) |> ignore
          })
        // what it holds, at the column's edges, the first 28 under the head (its own 12 and these 16)
        WideBlock(k) =>
          lane_node(s, fn(col) {
            col.box(fn(room) {
              room
              .padding(By(fn() {
                let first = blocks().get(0) == Some(k)
                (desk_column_in, if first { desk_first_top } else { 0.0 }, desk_column_in, 0.0)
              }))
              |> ignore
              block(room, k)
            })
            |> ignore
          })
        WideFoot => s.height(By(fn() { Some(desk_foot_h + frame().foot) })) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// How far under the head its first block stands (desk_first's pt=S4).
let desk_first_top : Double = 16.0

///|
/// A lane across the page (desk_lane: 24 from its sides at least), its column in the middle (desk_lane_column: 792 at
/// most), `make` making what is in the column.
#callsite(autofill(loc))
fn lane_node(parent : @view.View, make : (@view.View) -> Unit, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(lane) {
    // (in a panel of its own none in from its sides, its blocks' own 16 there its cards' panel_card_in: desk_lane_now)
    let side = if in_pane_node(parent) { 0.0 } else { desk_lane_in }
    lane.row(Is(true)).padding(Is((side, 0.0, side, 0.0))).lies_along(Is(Middle)) |> ignore
    lane.box(fn(col) {
      col.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))).max_width(Is(Some(desk_lane_most))) |> ignore
      make(col)
    })
    |> ignore
  })
  |> ignore
}

///|
/// A wide page's head (wide_page's: desk_head, 16 in, 12 under it; 40 over it, 20 with back over its title): back
/// (desk_back's) where the frame says it goes, its title (cut short where its line has less, 80 at least), what it does
/// at the line's end, what it is for under it (6 under the title, the meta's muted).
#callsite(autofill(loc))
fn wide_head_node(
  col : @view.View,
  title : () -> String,
  on_back : () -> Unit,
  frame : () -> PageFrame,
  lead : () -> String,
  actions : ((@view.View) -> Unit)?,
  about : () -> String,
  tips : TipLayer,
  loc~ : SourceLoc,
) -> Unit {
  col
  .padding(By(fn() {
    (head_in(col), if frame().back is Some(_) { desk_head_deep_top } else { desk_head_top }, head_in(col), desk_head_foot)
  }))
  .ground(By(fn() { @ui.tree_theme().color(Bg) }))
  |> ignore
  col.show(fn() { frame().back is Some(_) }, fn(line) {
    // (as wide as its words, its line the rest: what is pressed is back's own)
    line.row(Is(true)).padding(Is((0.0, 0.0, 0.0, desk_back_foot))) |> ignore
    desk_back_node(line, fn() { frame().back.unwrap_or("") }, on_back)
  })
  col.box(made_for=loc, fn(l) {
    l.row(Is(true)).gap(Is(desk_title_gap)).lines_up(Is(Some(Middle))) |> ignore
    // (its title, and what it is for by a mark after it where it says (desk_title_about: 6 apart, across their middle),
    // the title cut short before it)
    l.box(fn(w) {
      w.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(pg_title_least))).row(Is(true)).gap(Is(desk_about_gap)).lines_up(Is(Some(Middle)))
      |> ignore
      w.box(fn(t) {
        t.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
        styled_words(t, title, fn() { desk_title }) |> ignore
      })
      |> ignore
      w.show(fn() { about() != "" }, fn(m) { about_mark_node(m, about, fn() { t("web-main.about") }, tips) |> ignore })
    })
    |> ignore
    match actions {
      Some(f) =>
        l.box(fn(a) {
          a.row(Is(true)).gap(Is(desk_title_gap)).lines_up(Is(Some(Middle))) |> ignore
          f(a)
        })
        |> ignore
      None => ()
    }
  })
  |> ignore
  col.show(fn() { lead() != "" }, fn(l) {
    l.padding(Is((0.0, desk_lead_top, 0.0, 0.0))) |> ignore
    words_node(l, lead, fn() { desk_muted }) |> ignore
  })
}

///|
/// A wide page's own head in its lane (wide_page's desk_own_head: 16 in, 40 over it, 20 with back over it; under the
/// frame's bar that names it, 16 under that, barred_page's desk_first): back (desk_back's) where the frame says it goes,
/// then what `head` makes.
fn own_head_lane_node(col : @view.View, head : (@view.View) -> Unit, on_back : () -> Unit, frame : () -> PageFrame) -> Unit {
  col
  .padding(By(fn() {
    let f = frame()
    let top = if f.named {
      desk_first_top
    } else if f.back is Some(_) {
      desk_head_deep_top
    } else {
      desk_head_top
    }
    (head_in(col), top, head_in(col), 0.0)
  }))
  |> ignore
  col.show(fn() { frame().back is Some(_) && !frame().named }, fn(line) {
    line.row(Is(true)).padding(Is((0.0, 0.0, 0.0, desk_back_foot))) |> ignore
    desk_back_node(line, fn() { frame().back.unwrap_or("") }, on_back)
  })
  head(col)
}

///|
/// desk_head's room (pt=S10, deep pt=S5, pb=S3), its title line's gap (S2_5), what it is for under it (pt=S1_5),
/// back's line's room under it (pb=S2).
let desk_head_top : Double = 40.0

///|
let desk_head_deep_top : Double = 20.0

///|
let desk_head_foot : Double = 12.0

///|
let desk_title_gap : Double = 10.0

///|
let desk_lead_top : Double = 6.0

///|
let desk_back_foot : Double = 8.0

///|
/// A wide title's mark after it (desk_title_about's gap=S1_5).
let desk_about_gap : Double = 6.0

///|
/// Back over a wide page's head (desk_back's, as a node): its chevron and where it goes (`label`), muted, the text's
/// ink under the hand; `back` done as it is pressed; read out a link by where it goes.
#callsite(autofill(loc))
fn desk_back_node(parent : @view.View, label : () -> String, back : () -> Unit, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(b) {
    b.row(Is(true)).gap(Is(4.0)).lines_up(Is(Some(Middle))) |> ignore
    presses_node(b, back)
    b.says(By(fn() { Some(@view.said(Link, label=label())) })) |> ignore
    let ink = fn() { if lit_node(b) { theme().p.text } else { theme().p.muted } }
    icon_node(b, "chevron-left", desk_back_icon, By(ink)) |> ignore
    b.box(fn(w) { styled_words(w, label, fn() { if lit_node(b) { desk_back_lit } else { desk_back_words } }) |> ignore })
    |> ignore
  })
  |> ignore
}

///|
/// What a section says in place of what it holds where it has none, `words` as it says it now: narrow, 12 from the
/// page's sides, none over and 8 under, the meta's muted as wide as the page (mMemoryNote); wide, as it is, the UI's
/// muted.
#callsite(autofill(loc))
pub fn section_none_node(parent : @view.View, words : () -> String, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(n) {
    match look_node(n) {
      Narrow => {
        n.padding(Is((section_none_x, 0.0, section_none_x, section_none_foot))) |> ignore
        words_node(n, words, fn() { said_narrow }) |> ignore
      }
      Wide => words_node(n, words, fn() { desk_muted }) |> ignore
    }
  })
  |> ignore
}

///|
/// section_none_node's room, narrow: from the page's sides, and under it.
let section_none_x : Double = 12.0

///|
let section_none_foot : Double = 8.0

///|
/// A titled block of a page made once (section's): narrow, a heading over what it holds where it `heads` (none where
/// not: what it holds alone, as the web's mobile pages leave a group's title out), what it holds said under it
/// (`note`); wide, wide_section's whatever it `heads` (its title, 14 on 22, 600; `note` under it, the meta's muted, 3
/// under, 624 at most; 10 over what it holds, 28 under all of it), what is made in it a section's (part_of). `body`
/// makes what it holds. `about`: what it is for, as the web's pages say it: wide under its title (`note`'s, where it
/// says none), narrow under what it holds (the mobile pages' note at a section's foot). `actions`: what is done to all
/// it holds (all of them back as they were), made while it says so: wide at its title's end, 8 apart (wide_section's
/// section_actions); narrow at the section's foot after what it is for, in a page's note's room (pg_note_box: 快捷键's
/// 全部恢复默认 as its old view put it). Not the old view's section's narrow `actions`, which stand on its heading's line
/// (heading's): a section whose actions belong there says its title's own (`ends`: what is done on its title's line,
/// at its end, either way: narrow, heading_node's `ends`; wide, as `actions` stand). `title_after`: what its title holds
/// after its words, wide (a count: 8 after them in a line, section_title_line's); narrow none, as section's.
#callsite(autofill(loc))
pub fn section_node(
  parent : @view.View,
  title : () -> String,
  body : (@view.View) -> Unit,
  heads? : Bool = true,
  note? : () -> String = fn() { "" },
  about? : () -> String = fn() { "" },
  actions? : (() -> Bool, (@view.View) -> Unit),
  ends? : (@view.View) -> Unit,
  title_after? : (@view.View) -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  let at = part_of(parent)
  match at.look {
    Narrow => {
      if heads {
        parent.show(fn() { title() != "" }, fn(h) {
          heading_node(h, title, ends?)
          h.show(fn() { note() != "" }, fn(n) { page_note_node(n, note) })
        })
      }
      body(parent)
      parent.show(fn() { about() != "" }, fn(n) { page_note_node(n, about) })
      match actions {
        Some((shown, make)) =>
          parent.show(shown, fn(a) {
            a.box(fn(r) {
              r.row(Is(true)).padding(Is((pg_note_x, pg_note_top, pg_note_x, pg_note_foot))) |> ignore
              make(r)
            })
            |> ignore
          })
        None => ()
      }
    }
    Wide =>
      parent.box(made_for=loc, fn(sec) {
        sec.padding(Is((0.0, 0.0, 0.0, section_foot))) |> ignore
        sec.box(fn(line) {
          // (in a panel of its own on the panel's words' line, its cards 16 in: section_head_in_pane)
          let side = if in_pane_node(line) { panel_words - panel_card_in } else { 0.0 }
          line
          .row(Is(true))
          .padding(Is((side, 0.0, side, title_card_wide)))
          .gap(Is(section_actions_apart))
          .lines_up(Is(Some(Middle)))
          |> ignore
          line.box(fn(head) {
            head.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
            match title_after {
              Some(after) =>
                head.box(fn(l) {
                  l.row(Is(true)).gap(Is(section_title_after_gap)).lines_up(Is(Some(Middle))) |> ignore
                  words_node(l, title, fn() { section_title }) |> ignore
                  after(l)
                })
                |> ignore
              None => words_node(head, title, fn() { section_title }) |> ignore
            }
            // (what it holds said, and what it is for: under its title)
            let said = fn() {
              match (note(), about()) {
                ("", a) => a
                (n, _) => n
              }
            }
            head.show(fn() { said() != "" }, fn(n) {
              n.padding(Is((0.0, section_note_gap, 0.0, 0.0))).max_width(Is(Some(section_note_w))) |> ignore
              words_node(n, said, fn() { section_note }) |> ignore
            })
          })
          |> ignore
          match actions {
            Some((shown, make)) =>
              line.show(shown, fn(a) {
                a.box(fn(r) {
                  r.row(Is(true)).gap(Is(section_actions_gap)).lines_up(Is(Some(Middle))) |> ignore
                  make(r)
                })
                |> ignore
              })
            None => ()
          }
          match ends {
            Some(make) =>
              line.box(fn(r) {
                r.row(Is(true)).gap(Is(section_actions_gap)).lines_up(Is(Some(Middle))) |> ignore
                make(r)
              })
              |> ignore
            None => ()
          }
        })
        |> ignore
        sec.box(fn(b) {
          b.lends(part_at, { ..at, section: true }) |> ignore
          body(b)
        })
        |> ignore
      })
      |> ignore
  }
}

///|
/// section_head's room between its words and what is done at its end (gap=S3), section_actions' between those (gap=S2).
let section_actions_apart : Double = 12.0

///|
let section_actions_gap : Double = 8.0

///|
/// What a wide section's title holds after its words, how far after them (section_title_line's gap=S2).
let section_title_after_gap : Double = 8.0

///|
/// section_box's room under it (mb=S7), its note's widest (section_note_most).
let section_foot : Double = 28.0

///|
let section_note_w : Double = 624.0

///|
/// A section's heading alone, a block of a page's list over the pieces of its card (card_piece_node): as section_node
/// heads a section, narrow heading_node's, wide its title on its line, as far over the card as it stands there.
#callsite(autofill(loc))
pub fn section_heading_node(parent : @view.View, title : () -> String, loc~ : SourceLoc) -> Unit {
  match look_node(parent) {
    Narrow => heading_node(loc~, parent, title)
    Wide =>
      parent.box(made_for=loc, fn(line) {
        let side = if in_pane_node(line) { panel_words - panel_card_in } else { 0.0 }
        line.padding(Is((side, 0.0, side, title_card_wide))) |> ignore
        words_node(line, title, fn() { section_title }) |> ignore
      })
      |> ignore
  }
}

///|
/// Rows together on a wide page (group's, wide): at the column's edges, a list card (desk_list: its rows `list_pad` in,
/// 2 apart, its corner the list card's: what is made on it a list's rows, part_of) or, a `card` of words, desk_card
/// (20 in, 14 apart, Xl3); standing as a section does where it is in none (wide_alone: 28 under it), where it says so (`alone`).
#callsite(autofill(loc))
fn wide_group_node(
  parent : @view.View,
  at : PartAt,
  rows : (@view.View) -> Unit,
  card : Bool,
  alone? : Bool = true,
  loc~ : SourceLoc,
) -> Unit {
  let make = fn(p : @view.View) {
    p.box(fn(k) {
      if card {
        k
        .padding(Is((card_pad, card_pad, card_pad, card_pad)))
        .gap(Is(page_card_gap))
        .radius(By(fn() { @ui.tree_theme().corner(Xl3) }))
        |> ignore
      } else {
        // (in a panel of its own a card of the panel's: its rows the ladder's inset in, a card's corner; desk_list_card)
        let (pad, corner) = list_card_in(k)
        // (in a panel's card its words 24 in from its edges, over and under too: desk_list_pane)
        let ends = if in_pane_node(k) { card_pad - wide_row_over } else { pad }
        k.padding(Is((pad, ends, pad, ends))).gap(Is(desk_list_gap)).radius(Is(corner))
        |> ignore
      }
      k.ground(By(fn() { @ui.tree_theme().color(Card) })).lends(part_at, { ..at, list: !card }) |> ignore
      rows(k)
    })
    |> ignore
  }
  if at.section || !alone {
    make(parent)
  } else {
    parent.box(made_for=loc, fn(r) {
      r.padding(Is((0.0, 0.0, 0.0, section_foot))) |> ignore
      make(r)
    })
    |> ignore
  }
}

///|
/// A list card (desk_list's, wide whatever the page's width) in `parent`: its rows `list_pad` in, 2 apart, its corner the
/// list card's, nothing under it of a section's.
#callsite(autofill(loc))
pub fn list_card_node(parent : @view.View, rows : (@view.View) -> Unit, loc~ : SourceLoc) -> Unit {
  wide_group_node(loc~, parent, { ..part_of(parent), look: Wide }, rows, false, alone=false)
}

///|
/// A wide list's rows apart (desk_list's gap=S0_5).
let desk_list_gap : Double = 2.0

///|
/// A row of a wide list's (link_row's, wide: desk_list_link, wide_list_row): 10 in (list_words_room, py=S2_5), its parts
/// 12 apart, as high as the native input's rows at least (desk_row_least), its corner concentric with its list card's
/// (on none: Xl2's); lit under the hand where it `goes`. Its words desk_list_title's (strong: bolder; one that `acts` in
/// the link's ink), what it says wide_value's, its chevron (an arrow out where it goes `out`) 16 in the muted ink; its
/// note and what is wrong under its first line, wide_list_note's, 2 apart; what is `below` as link_row_node has it.
/// `press`: what is done as the row (given it) is pressed (link_row_made's `pressed_by`).
#callsite(autofill(loc))
fn wide_link_row_node(
  parent : @view.View,
  title : () -> String,
  press : (@view.View) -> () -> Unit,
  value : () -> String,
  value_bad : () -> Bool,
  value_dot : () -> Bool,
  note : () -> String,
  trouble : () -> String,
  strong : Bool,
  danger : Bool,
  value_look : (@ui.TextStyle) -> @ui.TextStyle,
  note_look : (@ui.TextStyle) -> @ui.TextStyle,
  lead : RowLead,
  face : Bool,
  lead_ink : () -> Int64,
  goes : Bool,
  ends : Bool,
  mark : () -> String,
  acts : Bool,
  below : ((@view.View) -> Unit)?,
  below_open : () -> Double,
  note_cut : Bool,
  title_after : ((@view.View) -> Unit)?,
  title_after_shown : () -> Bool,
  folds : (() -> Bool)?,
  tail : ((@view.View) -> Unit)?,
  tail_shown : () -> Bool,
  control : ((@view.View) -> Unit)?,
  title_look : (() -> @ui.TextStyle)?,
  title_cut : Bool,
  value_cut : Bool,
  chevron_room : Bool,
  loc~ : SourceLoc,
) -> Unit {
  let at = part_of(parent)
  let under = fn() { note() != "" || trouble() != "" || below is Some(_) }
  // (its title's look, a setting's where it is one: link_row's `title_style`)
  let title_base = fn() {
    match title_look {
      Some(f) => f()
      None => desk_list_title
    }
  }
  let titled = fn() {
    match (strong, danger) {
      (_, true) => title_base().then(bad)
      (true, false) => title_base().then(row_strong)
      (false, false) => title_base()
    }
  }
  // (in a panel's card, pressed: its ground reaching `link_pane_out` past the row over and under, to the card's rows'
  // inset where it is first or last, the row itself where it stands, what is pressed: a press beside it its
  // neighbour's, none of the two drawn over each other; desk_list_link)
  let reach = at.list && goes && in_pane_node(parent)
  // (where it stands across in a panel's body, row_line's: panel_row_at; on a group's card in one, as on a page's card,
  // as the narrow row's; elsewhere as ever)
  let pin = panel_in_of(parent)
  let (out, side) = match panel_row_at(pin, own=desk_list_out, card=on_card_node(parent)) {
    Some(p) => (p.out, p.side)
    None => (0.0, text_in)
  }
  parent.box(made_for=loc, fn(o) {
    if reach {
      o
      .margin(Is((0.0, -link_pane_out, 0.0, -link_pane_out)))
      .padding(Is((0.0, link_pane_out, 0.0, link_pane_out)))
      .radius(By(fn() { list_row_corner(o) }))
      |> ignore
    }
    o.box(fn(r) {
    r
    .row(Is(true))
    .gap(Is(12.0))
    // (its words a row's room in at its sides, 10 over and under: the old view's wide_list_row_ground; in a panel's
    // card none of its own where it is not pressed, none in the card's corners: wide_list_row)
    .margin(Is((-out, 0.0, -out, 0.0)))
    .padding(Is((side, wide_row_over, side, wide_row_over)))
    .radius(By(fn() {
      if pin.small {
        small_panel_inner(r_menu)
      } else if at.list {
        if (in_pane_node(r) && !goes) || reach { 0.0 } else { list_row_corner(r) }
      } else {
        @ui.tree_theme().corner(Xl2)
      }
    }))
    .min_height(By(fn() { Some(theme().items.least) }))
    // (a face across its middle, as its words: the old view's, row_top only where it is not a face)
    .lines_up(By(fn() { Some(if under() && !face { Start } else { Middle }) }))
    |> ignore
    // (a face's row not pressed holds its face as the old view's row did, by its corner: its picture across its middle,
    // in no corner of the card it is in; wide_list_row_ground's InnerOr, a container to the corner rule)
    if face && !goes {
      r.clips(Is(true)) |> ignore
    }
    if goes {
      (if reach { o } else { r }).ground(By(fn() { if lit_node(r) { @ui.tree_theme().color(Hover) } else { 0L } })) |> ignore
      presses_node(r, press(r))
      r.says(By(fn() { Some(@view.said(Link, label=title(), expanded?=folds.map(fn(f) { f() }))) })) |> ignore
    }
    // what it is by: on its first line where lines are under it (row_lead: as tall as a list's title's line at least,
    // across its middle)
    match lead {
      NoLead => ()
      LeadIcon(_) | LeadLine(_) =>
        r.box(fn(l) {
          l
          .row(Is(true))
          .lines_up(Is(Some(Middle)))
          .min_height(By(fn() {
            if under() {
              l.words_redone() |> ignore
              Some(node_sp(l, @ui.tree_theme().leading(L6).unwrap_or(@ui.tree_theme().text_size(Ui).1)))
            } else {
              None
            }
          }))
          |> ignore
          match lead {
            LeadIcon(name) => icon_node(l, name, desk_mark, By(lead_ink)) |> ignore
            LeadLine(f) => f(l)
            _ => ()
          }
        })
        |> ignore
      LeadMade(f) => r.box(fn(l) { f(l) }) |> ignore
      // (in the row's corner, out from its words to the ladder's inset from its start and top)
      LeadTile(f) =>
        r.box(fn(l) {
          l.margin(Is((corner_inset - text_in, corner_inset - text_in, 0.0, corner_inset - text_in))) |> ignore
          f(l)
        })
        |> ignore
    }
    r.box(fn(words) {
      words.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))).gap(Is(desk_list_gap)) |> ignore
      words.box(fn(first) {
        first.row(Is(true)).gap(Is(12.0)).lines_up(Is(Some(Middle))) |> ignore
        first.box(fn(t) {
          t.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
          // (what follows its title on its line while it is said, 8 apart across their middle, the title cut short where
          // the line leaves it less: link_row's title_line; its title the same words all along)
          t.row(Is(true)).lines_up(Is(Some(Middle))).fits(Is(title_after is Some(_))) |> ignore
          t.box(fn(w) {
            w.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
            styled_words(w, title, fn() {
              if (title_after is Some(_) && title_after_shown()) || title_cut { titled().then(cut_words) } else { titled() }
            })
            |> ignore
            if acts {
              w.ink(By(fn() { link_ink() })) |> ignore
            }
          })
          |> ignore
          match title_after {
            Some(after) =>
              t.show(title_after_shown, fn(a) {
                a.margin(Is((8.0, 0.0, 0.0, 0.0))) |> ignore
                after(a)
              })
            None => ()
          }
        })
        |> ignore
        first.show(fn() { value() != "" }, fn(said) {
          said.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Middle))) |> ignore
          said.show(value_dot, fn(d) { status_dot_node(d) })
          if value_cut {
            said.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
          }
          said.box(fn(w) {
            styled_words(w, value, fn() {
              let look = value_look(if value_bad() { wide_value.then(bad) } else { wide_value })
              if value_cut { look.then(cut_words) } else { look }
            })
            |> ignore
          })
          |> ignore
        })
        row_tail_node(first, tail, tail_shown)
        if ends {
          icon_node(first, mark(), desk_chevron, By(fn() { theme().p.muted }), name_now=mark) |> ignore
        } else if chevron_room {
          first.box(fn(e) { e.width(Is(Some(desk_chevron))).height(Is(Some(desk_chevron))) |> ignore }) |> ignore
        }
        row_control_node(first, control, under, face, false)
      })
      |> ignore
      words.show(fn() { note() != "" }, fn(n) {
        styled_words(n, note, fn() { note_look(if note_cut { wide_list_note.then(cut_words) } else { wide_list_note }) }) |> ignore
      })
      words.show(fn() { trouble() != "" }, fn(n) { styled_words(n, trouble, fn() { desk_note_bad }) |> ignore })
      match below {
        Some(f) => row_below_node(words, f, below_open)
        None => ()
      }
    })
    |> ignore
    row_control_node(r, control, under, face, true)
    })
    |> ignore
  })
  |> ignore
}

///|
/// A row of words with a control at its end on a wide page (control_row's: switch_row's, a setting's wide): its title,
/// `note` quieter under it (the theme's rows'), what `control` makes at its end across their middle, 16 apart; on a
/// list's card (part_of) a row of it (wide_in_list: as far in as its rows' words, 10 over and under, as high as one at
/// least, its corner concentric with the card's), its title as strong as the list's other rows' (setting_title); its
/// words' looks `looks` where given. The control alone answers.
#callsite(autofill(loc))
fn wide_control_row_node(
  parent : @view.View,
  title : () -> String,
  note : () -> String,
  lead : ((@view.View) -> Unit)?,
  control : (@view.View) -> Unit,
  looks? : (() -> @ui.TextStyle, () -> @ui.TextStyle),
  loc~ : SourceLoc,
) -> Unit {
  let at = part_of(parent)
  let (title_look, note_look) = match looks {
    Some(l) => l
    None => (fn() { if at.list { setting_title() } else { theme().rows.title } }, fn() { theme().rows.note })
  }
  let row = fn(r : @view.View) {
    r.row(Is(true)).gap(Is(16.0)).lines_up(Is(Some(Middle))) |> ignore
    r.box(fn(words) {
      words.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))).gap(Is(desk_list_gap)) |> ignore
      led_title_node(words, title, title_look, lead)
      words.show(fn() { note() != "" }, fn(n) { styled_words(n, note, note_look) |> ignore })
    })
    |> ignore
    control(r)
  }
  if at.list {
    parent.box(made_for=loc, fn(cell) {
      cell
      // (as wide_in_list's: a row's room in at its start, at its end what holds its switch out of the card's corner,
      // 10 over and under)
      .padding(Is((text_in, wide_row_over, if in_pane_node(parent) { text_in } else { list_control_end }, wide_row_over)))
      .lies_along(Is(Middle))
      .radius(Is(if in_pane_node(parent) { 0.0 } else { list_row_corner(cell) }))
      .min_height(By(fn() { Some(theme().items.least) }))
      |> ignore
      cell.box(row) |> ignore
    })
    |> ignore
  } else {
    parent.box(row) |> ignore
  }
}

///|
/// How far a wide list's row's words stand under its top and over its foot (wide_list_row_ground's, wide_in_list's
/// S2_5): 10, its sides a row's room (text_in).
let wide_row_over : Double = @ui.Space::S2_5.px()

///|
/// How far in from its column a wide page's head stands (desk_head's 16): in a panel of its own on the panel's words'
/// line (desk_head_in_pane: panel_words), its lane none in.
fn head_in(col : @view.View) -> Double {
  if in_pane_node(col) {
    panel_words
  } else {
    desk_column_in
  }
}

///|
/// A wide list card's rows' room in it and its corner (desk_list_card): a list card's, `list_pad` in; in a panel of its
/// own a card of the panel's, the ladder's inset in, a card's corner.
fn list_card_in(v : @view.View) -> (Double, Double) {
  if in_pane_node(v) {
    (corner_inset, card_corner)
  } else {
    (list_pad, list_card_corner)
  }
}

///|
/// The corner of a row of a wide list card (list_card_in), concentric with it.
fn list_row_corner(v : @view.View) -> Double {
  let (pad, corner) = list_card_in(v)
  @ui.concentric(corner, pad)
}

///|
/// How far a pressed row's ground reaches past it over and under on a panel's card (desk_list_link's): to the card's
/// rows' inset (corner_inset) from its edge where it is first or last, its words card_pad in.
let link_pane_out : Double = card_pad - @ui.Space::S2_5.px() - corner_inset
