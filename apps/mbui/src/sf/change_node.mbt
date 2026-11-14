// A page's dated record made once, laid
// out by the width the page's frame gives it (look_node): a day's label, and under it its changes, each a block of the
// page's list of its own (a piece of the day's card, narrow), one change's lines each led by its kind, and what a page
// says in place of what it lists. The page keeps what they say and who each is (its topic,
// its days and changes by their keys); these only how they are laid out.

///|
/// One line of a change: its words, led by its kind's `label` (none: no label, its room kept where it is wide), the
/// accent's where it is something `fresh`.
#derive(Eq)
pub(all) struct ChangeLine {
  label : String
  text : String
  fresh : Bool
}

///|
/// What a page says in place of what it lists (waiting over, nothing there, what went wrong), `words` as it says it now:
/// narrow, 12 in, 8 over and under, the meta's muted (mNote); wide, as it is, the UI's muted; in red where it says what
/// is wrong (`bad`).
#callsite(autofill(loc))
pub fn page_said_node(parent : @view.View, words : () -> String, bad? : Bool = false, loc~ : SourceLoc) -> Unit {
  match look_node(parent) {
    Narrow =>
      parent.box(made_for=loc, fn(n) {
        n.padding(Is((said_narrow_x, said_narrow_y, said_narrow_x, said_narrow_y))) |> ignore
        words_node(n, words, fn() { if bad { said_narrow_bad } else { said_narrow } }) |> ignore
      })
      |> ignore
    Wide => words_node(parent, words, fn() { if bad { desk_note_bad } else { desk_muted } }) |> ignore
  }
}

///|
/// A day's heading of a record made a block of its own, its changes each one after it (day_change_node), so a long day
/// is made only as far as it shows: `label` as it is now; narrow, a heading over the card its changes are pieces of
/// (heading_node); wide, its label (10 in, the meta's medium muted), 20 over it.
#callsite(autofill(loc))
pub fn day_heading_node(parent : @view.View, label : () -> String, loc~ : SourceLoc) -> Unit {
  match look_node(parent) {
    Narrow => heading_node(loc~, parent, label)
    Wide =>
      parent.box(made_for=loc, fn(d) {
        d.padding(Is((0.0, day_top, 0.0, 0.0))) |> ignore
        d.box(fn(h) {
          h.padding(Is((change_in, 0.0, change_in, 0.0))) |> ignore
          words_node(h, label, fn() { day_heading }) |> ignore
        })
        |> ignore
      })
      |> ignore
  }
}

///|
/// One change of a day made a block of its own under its day's heading (day_heading_node), change_node's: narrow, a
/// piece of the day's list card (card_piece_node, `piece` saying which as it is now); wide, 2 under what is over it.
/// Laid out one under another, a day's heading and its changes are what one block of all of them was.
#callsite(autofill(loc))
pub fn day_change_node(
  parent : @view.View,
  piece : () -> CardPiece,
  lines : () -> Array[ChangeLine],
  version : () -> String,
  note : () -> String,
  coming : () -> Bool,
  loc~ : SourceLoc,
) -> Unit {
  match look_node(parent) {
    Narrow => card_piece_node(loc~, parent, piece, fn(card) { change_narrow_node(card, lines, version, note, coming) })
    Wide =>
      parent.box(made_for=loc, fn(d) {
        d.padding(Is((0.0, day_gap, 0.0, 0.0))) |> ignore
        change_wide_node(d, lines, version, note, coming)
      })
      |> ignore
  }
}

///|
/// One change of a day (change_item), `lines`, `version` and `note` (what is not out yet; in the
/// accent where an update would bring it: `coming`) as they are now, each line by where it is in it. Narrow: each line
/// led by its kind on a small tinted label in its words, one paragraph of pieces wrapping under it; then its version
/// and the note, 10 apart; 16 by 10 in, its lines 2 apart. Wide: each line with its kind before it in a room of 52 (a
/// small label; none: its room kept), 10 apart, its words, its version at the end of the first; under them the note,
/// as far in as the words; 10 by 8 in, its lines 4 apart.
#callsite(autofill(loc))
pub fn change_node(
  parent : @view.View,
  lines : () -> Array[ChangeLine],
  version : () -> String,
  note : () -> String,
  coming : () -> Bool,
  loc~ : SourceLoc,
) -> Unit {
  match look_node(parent) {
    Narrow => change_narrow_node(loc~, parent, lines, version, note, coming)
    Wide => change_wide_node(parent, lines, version, note, coming)
  }
}

///|
#callsite(autofill(loc))
fn change_narrow_node(
  parent : @view.View,
  lines : () -> Array[ChangeLine],
  version : () -> String,
  note : () -> String,
  coming : () -> Bool,
  loc~ : SourceLoc,
) -> Unit {
  parent.box(made_for=loc, fn(c) {
    c.padding(Is((change_narrow_x, change_narrow_y, change_narrow_x, change_narrow_y))).gap(Is(change_narrow_gap))
    |> ignore
    c.each(fn() { lines().mapi(fn(i, l) { (i, l) }) }, fn(il) { il.0 }, fn(row, il) {
      let l = fn() { il.get().1 }
      row.pick(fn() { l().label == "" }, fn(line, plain) {
        if plain {
          words_node(line, fn() { l().text }, fn() { change_narrow_line }) |> ignore
        } else {
          line.box(fn(w) {
            w
            .words_runs(By(fn() { change_kind_runs(l()) }))
            .words_look(By(fn() { @ui.style_words(change_narrow_line) }))
            .ink(By(fn() { @ui.style_ink(change_narrow_line) }))
            |> ignore
          })
          |> ignore
        }
      })
    })
    c.box(fn(m) {
      m.row(Is(true)).gap(Is(change_gap)) |> ignore
      words_node(m, version, fn() { change_narrow_version }) |> ignore
      m.show(fn() { note() != "" }, fn(n) {
        words_node(n, note, fn() { if coming() { change_narrow_coming } else { change_narrow_version } }) |> ignore
      })
    })
    |> ignore
  })
  |> ignore
}

///|
/// A line's kind as a label before its words, and its words (narrow: the label in ems of its 13 (6 either side, 19
/// high, 6 round, 6 before the words), the accent's for something fresh).
fn change_kind_runs(l : ChangeLine) -> Array[@ui.Run] {
  let t = theme()
  let ground : @ui.Ground = { room: 6.0 / 13.0, height: 19.0 / 13.0, corner: 6.0 / 13.0, after: 6.0 / 13.0 }
  [
    @ui.span(
      l.label,
      scale=13.0 / 15.0,
      color=if l.fresh { t.p.accent_text } else { t.p.muted },
      bg=if l.fresh { t.p.accent_bg } else { t.p.chip },
      ground=Some(ground),
    ),
    @ui.plain(l.text),
  ]
}

///|
#callsite(autofill(loc))
fn change_wide_node(
  parent : @view.View,
  lines : () -> Array[ChangeLine],
  version : () -> String,
  note : () -> String,
  coming : () -> Bool,
  loc~ : SourceLoc,
) -> Unit {
  parent.box(made_for=loc, fn(c) {
    c.padding(Is((change_in, change_y, change_in, change_y))).gap(Is(change_wide_gap)) |> ignore
    let row_of = fn(r : @view.View) { r.row(Is(true)).gap(Is(change_gap)).lines_up(Is(Some(Start))) |> ignore }
    let kind_room = fn(r : @view.View, make : (@view.View) -> Unit) {
      r.box(fn(k) {
        k.width(Is(Some(change_kind_w))).lines_up(Is(Some(Start))) |> ignore
        make(k)
      })
      |> ignore
    }
    c.each(fn() { lines().mapi(fn(i, l) { (i, l) }) }, fn(il) { il.0 }, fn(row, il) {
      let l = fn() { il.get().1 }
      let first = il.get().0 == 0
      row_of(row)
      kind_room(row, fn(k) {
        k.show(fn() { l().label != "" }, fn(b) {
          b
          .padding(Is((change_kind_x, 0.0, change_kind_x, 0.0)))
          .radius(By(fn() { @ui.tree_theme().corner(Base) }))
          .ground(By(fn() { @ui.tree_theme().color(if l().fresh { AccentBg } else { Neutral }) }))
          |> ignore
          words_node(b, fn() { l().label }, fn() { if l().fresh { change_kind_fresh } else { change_kind } }) |> ignore
        })
      })
      // (taking what its line leaves, its version at the line's end: change_line's w=grow)
      words_node(row, fn() { l().text }, fn() { change_line }).grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0)))
      |> ignore
      if first {
        words_node(row, version, fn() { change_version }) |> ignore
      }
    })
    // (under the words: the kind's room and the gap after it)
    c.show(fn() { note() != "" }, fn(n) {
      row_of(n)
      kind_room(n, fn(_) {  })
      words_node(n, note, fn() { if coming() { change_note_coming } else { change_note } })
      .grow(Is(1.0))
      .shrink(Is(1.0))
      .min_width(Is(Some(0.0)))
      |> ignore
    })
  })
  |> ignore
}

///|
/// The wide day's room over it (pt=S5) and between what is in it (gap=S0_5); a change's in (px=S2_5), over and under
/// (py=S2), its lines apart (gap=S1), a line's gap (S2_5), its kind's room (52) and in (px=S1_5).
let day_top : Double = 20.0

///|
let day_gap : Double = 2.0

///|
let change_in : Double = 10.0

///|
let change_y : Double = 8.0

///|
let change_wide_gap : Double = 4.0

///|
let change_gap : Double = 10.0

///|
let change_kind_w : Double = 52.0

///|
let change_kind_x : Double = 6.0

///|
/// The narrow said's room (px=S3 py=S2), a narrow change's (px=S4 py=S2_5 gap=S0_5).
let said_narrow_x : Double = 12.0

///|
let said_narrow_y : Double = 8.0

///|
let change_narrow_x : Double = 16.0

///|
let change_narrow_y : Double = 10.0

///|
let change_narrow_gap : Double = 2.0

///|
// kept across runs: a value (no field of it changes)
let day_heading : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=Muted, w=grow)

///|
// kept across runs: a value (no field of it changes)
let change_kind : @ui.TextStyle = @ui.text_style(size=Caption, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let change_kind_fresh : @ui.TextStyle = @ui.text_style(size=Caption, leading=L5, color=AccentText, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let change_line : @ui.TextStyle = @ui.text_style(size=Ui, leading=L5, color=Fg, w=grow)

///|
// kept across runs: a value (no field of it changes)
let change_version : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let change_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=grow)

///|
// kept across runs: a value (no field of it changes)
let change_note_coming : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=AccentText, w=grow)

///|
// kept across runs: a value (no field of it changes)
let said_narrow : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let said_narrow_bad : @ui.TextStyle = said_narrow.then(@ui.text_style(color=Danger))

///|
// kept across runs: a value (no field of it changes)
let change_narrow_line : @ui.TextStyle = body.then(full_words)

///|
// kept across runs: a value (no field of it changes)
let change_narrow_version : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let change_narrow_coming : @ui.TextStyle = change_narrow_version.then(@ui.text_style(color=AccentText))
