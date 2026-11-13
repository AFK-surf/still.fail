// An allowance as nodes of a page made once (fill_chip.mbt's, quota_chip.mbt's and dials' parts, the same look): a fill
// chip, an allowance's chips in a line, an allowance's windows as dials. What they show followed as it changes.

///|
/// A fill chip (fill_chip's, as a node) in `parent`: on the neutral ground, filled from the left as far as `fill` (0–100)
/// says now, grey while `level` is ok, faintly the level's colour once it is not; `mark` and `words` in the text's
/// colour; `small` a lower one. `said` (what is left and when it fills again) over it while it is pointed at, in `tips`.
/// In a page's bones, one piece. Never squeezed, but `squeezes`: given way to its row where that has not the room for it
/// left, its figure cut short with an ellipsis (meter_chips_brief_node's, the old line's `keep`).
#callsite(autofill(loc))
pub fn fill_chip_node(
  parent : @view.View,
  fill : () -> Int,
  level : () -> String,
  mark : () -> String,
  words : () -> String,
  small? : Bool = false,
  said? : () -> String,
  tips? : TipLayer,
  squeezes? : Bool = false,
  loc~ : SourceLoc,
) -> @view.View {
  let part = fn() {
    let f = fill()
    if f < 0 {
      0
    } else if f > 100 {
      100
    } else {
      f
    }
  }
  let chip = parent.box(made_for=loc, fn(b) {
    // (as high as its words' line at the system's size of words where that is higher than the chip: at 1.3 a small
    // chip's 16 held words of 20, over the line above and below it, a station's row in 选择运行的 station, main
    // df98aad1 42956992852, 2026-11-11)
    style_node(b, fn() { chip_box_at(b.words_scale(), small) })
    b.bone_whole(Is(true)).shrink(Is(if squeezes { 1.0 } else { 0.0 })) |> ignore
    if squeezes {
      b.min_width(Is(Some(0.0))) |> ignore
    }
    // (its fill a plain rectangle cut along the chip's corners, its end square where it stops)
    b.box(fn(f) {
      style_node(f, fn() { chip_fill_row })
      f.over(Is(true)).clips(Is(true)) |> ignore
      f.box(fn(x) {
        style_node(x, fn() { chip_fill_part })
        x
        .grow(By(fn() { part().to_double() }))
        .basis(Is(Some(0.0)))
        .ground(By(fn() {
          let t = theme()
          let lv = level()
          if lv == "amber" || lv == "red" {
            alpha(level_color(lv), chip_fill_share)
          } else if lv == "progress" {
            alpha(t.p.accent_text, chip_fill_share)
          } else {
            alpha(t.p.muted, chip_fill_share)
          }
        }))
        |> ignore
      })
      |> ignore
      f.box(fn(x) {
        style_node(x, fn() { chip_fill_part })
        x.grow(By(fn() { (100 - part()).to_double() })).basis(Is(Some(0.0))) |> ignore
      })
      |> ignore
    })
    |> ignore
    b.box(fn(w) {
      style_node(w, fn() {
        let s = if small { chip_words_small } else { chip_words }
        if chip_joined(mark(), words()) {
          s.then(chip_joined_gap)
        } else {
          s
        }
      })
      w.show(fn() { mark() != "" }, fn(m) { words_node(m, mark, fn() { chip_text }) |> ignore })
      let f = words_node(w, words, fn() { chip_text })
      // (squeezed where it may be: its figure cut short with an ellipsis, as the old line's chips kept to the last are)
      if squeezes {
        w.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
        f.shrink(Is(1.0)).min_width(Is(Some(0.0))).cuts(Is(true)).allow_ellipsis(Is(true)) |> ignore
      }
    })
    |> ignore
  })
  match (tips, said) {
    // (shown by the pointer within it: a chip takes no press, so is never pointed at itself, tip_node's `within`)
    (Some(t), Some(s)) => tip_node(t, chip, s, within=true) |> ignore
    _ => ()
  }
  chip
}

///|
/// An allowance's windows as chips in a line (quota_chips', not worded, as a node) in `parent`, `q` as the core says it
/// now: a chip per window, what is left in it, filled as far as that, its mark before it where `marked`; `small` a lower
/// line; `gap` apart; nothing while the core cannot say or there is no window. Each says what is left of it and when it
/// fills again over it while it is pointed at, in `tips`.
pub fn quota_chips_node(
  parent : @view.View,
  q : () -> Json?,
  small? : Bool = false,
  marked? : Bool = true,
  gap? : Double = 8.0,
  tips? : TipLayer,
) -> Unit {
  let windows = fn() {
    match chip_field(q(), "windows") {
      Some(Array(a)) => a
      _ => []
    }
  }
  parent.show(fn() { has_quota(q()) }, fn(x) {
    x.box(fn(r) {
      style_node(r, fn() { quota_chips_row.then(@ui.style(gap=room(gap))) }, in_row=true)
      r.shrink(Is(0.0)) |> ignore
      r.each(fn() { Array::makei(windows().length(), fn(i) { i }) }, fn(i) { i }, fn(c, i) {
        let k = i.untracked()
        let w = fn() { windows().get(k) }
        fill_chip_node(
          c,
          fn() { chip_left(w()) },
          fn() { chip_str(w(), "level") },
          fn() { if marked { chip_str(w(), "mark") } else { "" } },
          fn() { chip_left(w()).to_string() + "%" },
          small~,
          said=fn() { quota_said(w()) },
          tips?,
        )
        |> ignore
      })
    })
    |> ignore
  })
}

///|
/// Dials side by side (dials', as nodes): `dials` as they are said, `details` a quiet line under each where there is one
/// (a GPU's model). Wide, each 96 wide at least (`columns` > 0: each 96), 36 apart, on as many lines as they take (12
/// between). Narrow: sharing the line's width, 16 apart, their cells narrower; `columns` > 0, that many a line (the last
/// line's room kept where it has fewer); `lines` > 0, the same, a note longer than its dial going on under itself (an
/// allowance's, two a line: its windows have no shorter words, and three in a line cut 每周 · Fable and 2 天 4 小时后刷新
/// at a third of a phone's card; with its models' own weeks, five, they ran past the card); else all in a line, in
/// their full words where the line has the room for all of them so, else all in their short ones (one way for all).
#callsite(autofill(loc))
pub fn dials_node(
  parent : @view.View,
  dials : () -> Array[Dial],
  details? : () -> Array[String] = fn() { [] },
  columns? : Int = 0,
  lines? : Int = 0,
  loc~ : SourceLoc,
) -> Unit {
  let narrow = part_of(parent).look == Narrow
  let dial = fn(d : @view.View, i : Int, short : Bool, wraps : Bool) {
    dial_node(d, fn() { dials().get(i) }, fn() { details().get(i) }, fn() { !details().is_empty() }, short, wraps, narrow, columns)
  }
  let line = fn(r : @view.View, short : Bool) {
    style_node(r, fn() { if narrow { dl_row_narrow } else { dl_row_wide } }, in_row=narrow)
    if !narrow {
      r.wraps(Is(Some(dl_lines))) |> ignore
    }
    r.each(fn() { Array::makei(dials().length(), fn(i) { i }) }, fn(i) { i }, fn(d, i) {
      dial(d, i.untracked(), short, false)
    })
  }
  // (a line `per` of them, the last one's room kept where it has fewer)
  let in_lines = fn(b : @view.View, per : Int, wraps : Bool) {
    style_node(b, fn() { dl_rows })
    b.each(fn() { Array::makei((dials().length() + per - 1) / per, fn(k) { k }) }, fn(k) { k }, fn(r, k) {
      let start = k.untracked() * per
      style_node(r, fn() { dl_row_narrow })
      for i in start..<(start + per) {
        r.pick(fn() { i < dials().length() }, fn(d, there) {
          if there {
            dial(d, i, false, wraps)
          } else {
            style_node(d, fn() { dl_dial_narrow }, in_row=true)
          }
        })
      }
    })
  }
  parent.box(made_for=loc, fn(b) {
    if narrow && columns > 0 {
      in_lines(b, columns, false)
    } else if narrow && lines > 0 {
      in_lines(b, lines, true)
    } else if narrow {
      // all of them in their full words where the line has the room for all, else all in their short ones: the full
      // line left out of its row where it has not the room, the short one there only while it is (View::drops)
      let ways = fn() { dials().iter().any(fn(d) { d.label_short != "" || d.note_short != "" }) }
      style_node(b, fn() { dl_row_ways })
      b.fits(Is(true)) |> ignore
      b.box(fn(r) {
        r.drops(By(fn() { if ways() { 1 } else { 0 } })) |> ignore
        line(r, false)
      })
      |> ignore
      b.show(ways, fn(s) {
        s.drops(Is(-1)) |> ignore
        line(s, true)
      })
    } else {
      line(b, false)
    }
  })
  |> ignore
}

///|
/// A dial (dials' draw): what is left large, its unit after it quieter on its line; its ten cells, as many lit as `fill`
/// says in its level's colour; its label and its note under (`short`: their short words where they have them), its
/// `detail` under that where there is one (`detailed`: the note in the detail's look, as wide as it is).
#callsite(autofill(loc))
fn dial_node(
  d : @view.View,
  dial : () -> Dial?,
  detail : () -> String?,
  detailed : () -> Bool,
  short : Bool,
  wraps : Bool,
  narrow : Bool,
  columns : Int,
  loc~ : SourceLoc,
) -> Unit {
  let blank : Dial = { number: "", unit: "", fill: 0, level: "", label: "", note: "", label_short: "", note_short: "" }
  let now = fn() { dial().unwrap_or(blank) }
  let ink = fn() {
    let t = theme()
    match now().level {
      "amber" | "warn" => t.p.warn_ink
      "red" => t.p.red
      _ => t.p.green
    }
  }
  let low = fn() {
    match now().level {
      "amber" | "warn" | "red" => true
      _ => false
    }
  }
  let lit = fn() {
    let f = now().fill
    let fill = if f < 0 { 0 } else if f > 100 { 100 } else { f }
    (fill.to_double() / 10.0).round().to_int()
  }
  style_node(d, fn() { if narrow { dl_dial_narrow } else if columns > 0 { dl_dial_wide_fixed } else { dl_dial_wide } }, in_row=true)
  // (the figure and its unit one line's runs: the unit on the figure's baseline)
  let number = fn() { if low() { dl_number.then(@ui.text_style(color=Data(ink()))) } else { dl_number } }
  d.box(made_for=loc, fn(w) {
    w
    .words_runs(By(fn() {
      let t = theme()
      [@ui.span(now().number), @ui.span(now().unit, weight=500, scale=t.t.meta / dl_number_size, color=t.p.muted)]
    }))
    .words_look(By(fn() { @ui.style_words(number()) }))
    .ink(By(fn() { @ui.style_ink(number()) }))
    |> ignore
  })
  |> ignore
  d.box(fn(cells) {
    style_node(cells, fn() { if narrow { dl_cells_narrow } else { dl_cells_wide } })
    let cell = if narrow { dl_cell_narrow } else { dl_cell_wide }
    for i in 0..<10 {
      cells.box(fn(x) { style_node(x, fn() { if i < lit() { cell.then(@ui.style(bg=Data(ink()))) } else { cell } }, in_row=true) })
      |> ignore
    }
  })
  |> ignore
  words_node(d, fn() { if short && now().label_short != "" { now().label_short } else { now().label } }, fn() {
    if wraps { dl_label_lines } else { dl_label }
  })
  |> ignore
  words_node(
    d,
    fn() {
      let n = now()
      if n.note == "" {
        " "
      } else if short && n.note_short != "" {
        n.note_short
      } else {
        n.note
      }
    },
    fn() { if detailed() { dl_detail } else if wraps { dl_reset_lines } else { dl_reset } },
  )
  |> ignore
  d.show(fn() { detail().unwrap_or("") != "" }, fn(s) { words_node(s, fn() { detail().unwrap_or("") }, fn() { dl_detail }) |> ignore })
}

///|
/// A machine's CPU, memory and disk (meter_line's, as nodes) in `parent`, as `meters` says them now: each a chip, what
/// is left in it, filled as far as is used, its mark before it; 8 apart in a line; what it is (its name, how much of
/// how much, a note) over it while it is pointed at, in `tips`.
#callsite(autofill(loc))
pub fn meter_chips_node(parent : @view.View, meters : () -> Array[Json], tips? : TipLayer, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(r) {
    style_node(r, fn() { meter_line_way }, in_row=true)
    r.shrink(Is(0.0)) |> ignore
    r.each(fn() { Array::makei(meters().length(), fn(i) { i }) }, fn(i) { i }, fn(c, i) {
      let k = i.untracked()
      let m = fn() { meters().get(k) }
      fill_chip_node(
        c,
        fn() { 100 - chip_left(m()) },
        fn() { chip_str(m(), "level") },
        fn() { chip_str(m(), "short") },
        fn() { chip_str(m(), "remaining") },
        said=fn() {
          let note = chip_str(m(), "note")
          match chip_str(m(), "label") {
            "" => ""
            label => label + " " + chip_str(m(), "value") + (if note != "" { " · " + note } else { "" })
          }
        },
        tips?,
      )
      |> ignore
    })
  })
  |> ignore
}

///|
/// A fill chip's box (chip_box's, chip_box_small's) at the system's size of words `scale`: as high as chip_text's line
/// drawn at that size where that is higher than the chip (box_at: kept for the last theme and size, each its own).
fn chip_box_at(scale : Double, small : Bool) -> @ui.Style {
  if small {
    box_at(chip_small_kept, chip_box_small, fill_chip_small_h, chip_text, scale)
  } else {
    box_at(chip_kept, chip_box, fill_chip_h, chip_text, scale)
  }
}

///|
// kept across runs: the last theme and size of words a fill chip was asked at and its box (box_at), worked out again
// for any other
let chip_kept : Ref[WordsBoxKept?] = Ref(None)

///|
// kept across runs: the same of a small fill chip
let chip_small_kept : Ref[WordsBoxKept?] = Ref(None)
