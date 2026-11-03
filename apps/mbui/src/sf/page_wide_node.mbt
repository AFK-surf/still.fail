// A page made once laid out wide (page.mbt wide_page, desk_lanes; the web's desktop pages: pages.css.ts page, pageHead,
// list, card; ui.tsx Section), as nodes: its head (back over its title on a page under another, its title, what it
// does at its line's end, what it is for under it), then its blocks in the lanes' column in the pane's middle, 80 at its
// foot; and the parts of it as a wide page has them, each taking its form from where it is made (part_of: lent by the
// page, a section, a group), what is shown in it later as well: a section with its title, a group's list card or card
// of words, a row that goes somewhere on it, a switch's row. Their styles page.mbt's and parts.mbt's, the same.

///|
/// What a wide page made once holds, in its order: what stands over it, its head, its blocks by their keys, the room
/// at its foot.
priv enum WideItem {
  WideTop
  WideHead
  WideLead
  WideBlock(String)
  WideFoot
} derive(Eq, Hash)

///|
/// A wide page made once (wide_page's) in node `v`: under what stands over it as the frame says (`frame`'s top), its
/// head (wide_head_node) where the frame's bar does not name it, else what it is for alone (barred_page's), its blocks (each made by `block` in the column, at its
/// edges: desk_block's 16 in; the first 16 under the head), then 80 at its foot and the frame's room; each part in its
/// lane (lane_node) and made only while it shows (as desk_lanes' old list builds only the rows in view).
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
) -> Unit {
  let items = fn() -> Array[WideItem] {
    let f = frame()
    let out = []
    if f.top > 0.0 {
      out.push(WideTop)
    }
    if !f.named {
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
  v.box(fn(sc) {
    sc.grow(Is(1.0)) |> ignore
    sc.scrolls_window(scroll, items, bar=@ui.tree_scroll_bar(), est=pg_block_est, fn(s, item) {
      match item {
        // the room the frame keeps over it (a status bar's)
        WideTop => s.height(By(fn() { Some(frame().top) })) |> ignore
        WideHead => lane_node(s, fn(col) { wide_head_node(col, title, on_back, frame, lead, actions, about, tips) })
        // what it is for under the frame's bar that names it (barred_page's: desk_barred_lead, 16 in, 12 under)
        WideLead =>
          lane_node(s, fn(col) {
            col.padding(Is((desk_column_in, 0.0, desk_column_in, desk_head_foot))) |> ignore
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
fn lane_node(parent : @view.View, make : (@view.View) -> Unit) -> Unit {
  parent.box(fn(lane) {
    lane.row(Is(true)).padding(Is((desk_lane_in, 0.0, desk_lane_in, 0.0))).lies_along(Is(Middle)) |> ignore
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
fn wide_head_node(
  col : @view.View,
  title : () -> String,
  on_back : () -> Unit,
  frame : () -> PageFrame,
  lead : () -> String,
  actions : ((@view.View) -> Unit)?,
  about : () -> String,
  tips : TipLayer,
) -> Unit {
  col
  .padding(By(fn() {
    (desk_column_in, if frame().back is Some(_) { desk_head_deep_top } else { desk_head_top }, desk_column_in, desk_head_foot)
  }))
  .ground(By(fn() { @ui.tree_theme().color(Bg) }))
  |> ignore
  col.show(fn() { frame().back is Some(_) }, fn(line) {
    // (as wide as its words, its line the rest: what is pressed is back's own)
    line.row(Is(true)).padding(Is((0.0, 0.0, 0.0, desk_back_foot))) |> ignore
    desk_back_node(line, fn() { frame().back.unwrap_or("") }, on_back)
  })
  col.box(fn(l) {
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
fn desk_back_node(parent : @view.View, label : () -> String, back : () -> Unit) -> Unit {
  parent.box(fn(b) {
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
pub fn section_none_node(parent : @view.View, words : () -> String) -> Unit {
  parent.box(fn(n) {
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
/// (heading's): a section whose actions belong there says its title's own.
pub fn section_node(
  parent : @view.View,
  title : () -> String,
  body : (@view.View) -> Unit,
  heads? : Bool = true,
  note? : () -> String = fn() { "" },
  about? : () -> String = fn() { "" },
  actions? : (() -> Bool, (@view.View) -> Unit),
) -> Unit {
  let at = part_of(parent)
  match at.look {
    Narrow => {
      if heads {
        parent.show(fn() { title() != "" }, fn(h) {
          heading_node(h, title)
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
      parent.box(fn(sec) {
        sec.padding(Is((0.0, 0.0, 0.0, section_foot))) |> ignore
        sec.box(fn(line) {
          line
          .row(Is(true))
          .padding(Is((0.0, 0.0, 0.0, title_card_wide)))
          .gap(Is(section_actions_apart))
          .lines_up(Is(Some(Middle)))
          |> ignore
          line.box(fn(head) {
            head.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
            words_node(head, title, fn() { section_title }) |> ignore
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
/// section_box's room under it (mb=S7), its note's widest (section_note_most).
let section_foot : Double = 28.0

///|
let section_note_w : Double = 624.0

///|
/// Rows together on a wide page (group's, wide): at the column's edges, a list card (desk_list: its rows `list_pad` in,
/// 2 apart, its corner the list card's: what is made on it a list's rows, part_of) or, a `card` of words, desk_card
/// (20 in, 14 apart, Xl3); standing as a section does where it is in none (wide_alone: 28 under it).
fn wide_group_node(parent : @view.View, at : PartAt, rows : (@view.View) -> Unit, card : Bool) -> Unit {
  let make = fn(p : @view.View) {
    p.box(fn(k) {
      if card {
        k
        .padding(Is((card_pad, card_pad, card_pad, card_pad)))
        .gap(Is(page_card_gap))
        .radius(By(fn() { @ui.tree_theme().corner(Xl3) }))
        |> ignore
      } else {
        k.padding(Is((list_pad, list_pad, list_pad, list_pad))).gap(Is(desk_list_gap)).radius(Is(list_card_corner))
        |> ignore
      }
      k.ground(By(fn() { @ui.tree_theme().color(Card) })).lends(part_at, { ..at, list: !card }) |> ignore
      rows(k)
    })
    |> ignore
  }
  if at.section {
    make(parent)
  } else {
    parent.box(fn(r) {
      r.padding(Is((0.0, 0.0, 0.0, section_foot))) |> ignore
      make(r)
    })
    |> ignore
  }
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
fn wide_link_row_node(
  parent : @view.View,
  title : () -> String,
  press : () -> Unit,
  value : () -> String,
  value_bad : () -> Bool,
  value_dot : () -> Bool,
  note : () -> String,
  trouble : () -> String,
  strong : Bool,
  lead : RowLead,
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
) -> Unit {
  let at = part_of(parent)
  let under = fn() { note() != "" || trouble() != "" || below is Some(_) }
  let titled = if strong { desk_list_title.then(row_strong) } else { desk_list_title }
  parent.box(fn(r) {
    r
    .row(Is(true))
    .gap(Is(12.0))
    .padding(Is((text_in, text_in, text_in, text_in)))
    .radius(By(fn() { if at.list { inner_corner(list_card_corner, list_pad) } else { @ui.tree_theme().corner(Xl2) } }))
    .min_height(By(fn() { Some(theme().items.least) }))
    .lines_up(By(fn() { Some(if under() { Start } else { Middle }) }))
    |> ignore
    if goes {
      r.ground(By(fn() { if lit_node(r) { @ui.tree_theme().color(Hover) } else { 0L } })) |> ignore
      presses_node(r, press)
      r.says(By(fn() { Some(@view.said(Link, label=title(), expanded?=folds.map(fn(f) { f() }))) })) |> ignore
    }
    // what it is by: on its first line where lines are under it (row_lead: as tall as a list's title's line at least,
    // across its middle)
    match lead {
      NoLead => ()
      LeadIcon(name) =>
        r.box(fn(l) {
          l
          .row(Is(true))
          .lines_up(Is(Some(Middle)))
          .min_height(By(fn() {
            if under() {
              l.words_redone() |> ignore
              Some(@ui.current().sp(@ui.tree_theme().leading(L6).unwrap_or(@ui.tree_theme().text_size(Ui).1)))
            } else {
              None
            }
          }))
          |> ignore
          icon_node(l, name, desk_mark, By(fn() { theme().p.muted })) |> ignore
        })
        |> ignore
      LeadMade(f) => r.box(fn(l) { f(l) }) |> ignore
    }
    r.box(fn(words) {
      words.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))).gap(Is(desk_list_gap)) |> ignore
      words.box(fn(first) {
        first.row(Is(true)).gap(Is(12.0)).lines_up(Is(Some(Middle))) |> ignore
        first.box(fn(t) {
          t.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
          // (what follows its title on its line while it is said, 8 apart across their middle, the title cut short where
          // the line leaves it less: link_row's title_line; its title the same words all along)
          t.row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
          t.box(fn(w) {
            w.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
            styled_words(w, title, fn() {
              if title_after is Some(_) && title_after_shown() { titled.then(cut_words) } else { titled }
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
          said.box(fn(w) { styled_words(w, value, fn() { if value_bad() { wide_value.then(bad) } else { wide_value } }) |> ignore })
          |> ignore
        })
        if ends {
          icon_node(first, mark(), desk_chevron, By(fn() { theme().p.muted }), name_now=mark) |> ignore
        }
      })
      |> ignore
      words.show(fn() { note() != "" }, fn(n) {
        styled_words(n, note, fn() { if note_cut { wide_list_note.then(cut_words) } else { wide_list_note } }) |> ignore
      })
      words.show(fn() { trouble() != "" }, fn(n) { styled_words(n, trouble, fn() { desk_note_bad }) |> ignore })
      match below {
        Some(f) => row_below_node(words, f, below_open)
        None => ()
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A switch's row on a wide page (switch_row's, wide): its title, `note` quieter under it (the theme's rows'), the
/// switch at its end across their middle, 16 apart; on a list's card (part_of) a row of it (wide_in_list: as far in as
/// its rows' words, 10 over and under, as high as one at least, its corner concentric with the card's), its title as
/// strong as the list's other rows' (setting_title). The switch alone answers.
fn wide_switch_row_node(
  parent : @view.View,
  title : () -> String,
  on : () -> Bool,
  turn : (Bool) -> Unit,
  note : () -> String,
) -> Unit {
  let at = part_of(parent)
  let row = fn(r : @view.View) {
    r.row(Is(true)).gap(Is(16.0)).lines_up(Is(Some(Middle))) |> ignore
    r.box(fn(words) {
      words.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))).gap(Is(desk_list_gap)) |> ignore
      words_node(words, title, fn() { if at.list { setting_title() } else { theme().rows.title } }) |> ignore
      words.show(fn() { note() != "" }, fn(n) { styled_words(n, note, fn() { theme().rows.note }) |> ignore })
    })
    |> ignore
    switch_node(r, on, turn, title)
  }
  if at.list {
    parent.box(fn(cell) {
      cell
      .padding(Is((text_in, text_in, text_in, text_in)))
      .lies_along(Is(Middle))
      .radius(Is(inner_corner(list_card_corner, list_pad)))
      .min_height(By(fn() { Some(theme().items.least) }))
      |> ignore
      cell.box(row) |> ignore
    })
    |> ignore
  } else {
    parent.box(row) |> ignore
  }
}
