// The fill chip (fill_chip.mbt's) and an allowance's chips (quota_chip.mbt's quota_chips, not worded) as nodes of the
// window's tree, made once: what they say followed as it changes, the same size, corner and colours as theirs.

///|
/// A fill chip in `parent` (fill_chip's): on the neutral ground, filled from the left as far as `fill` (0–100) in its
/// level's tint (`level`, as level_color), `mark` and `words` in the text's colour; `small` 16 high, else 22;
/// `compact` gives a small chip less horizontal padding. `said` over it while it is pointed at, in `tips` (none: no
/// tip). Drawn whole in bones. Each as it changes. The node.
pub fn fill_chip_node(
  parent : @view.View,
  fill : () -> Int,
  level : () -> String,
  mark : () -> String,
  words : () -> String,
  small? : Bool = false,
  compact? : Bool = false,
  said? : () -> String = fn() { "" },
  tips? : TipLayer,
) -> @view.View {
  let filled = fn() {
    let f = fill()
    if f < 0 {
      0
    } else if f > 100 {
      100
    } else {
      f
    }
  }
  let ground = fn() {
    let t = theme()
    match level() {
      "amber" | "red" => alpha(level_color(level()), chip_fill_share)
      "progress" => alpha(t.p.accent_text, chip_fill_share)
      _ => alpha(t.p.muted, chip_fill_share)
    }
  }
  parent.box(fn(b) {
    b
    .bone_whole(Is(true))
    .height(Is(Some(if small { fill_chip_small_h } else { fill_chip_h })))
    .radius(Is(fill_chip_corner))
    .ground(By(fn() { @ui.tree_theme().neutral }))
    .lies_along(Is(Middle))
    |> ignore
    // (its fill a plain rectangle cut along the chip's corners, its end square where it stops, under its words; the
    // chip itself cuts nothing: fill_chip's layer)
    b.show(fn() { filled() > 0 }, fn(f) {
      f
      .over(Is(true))
      .row(Is(true))
      .width_share(Is(1.0))
      .height_share(Is(1.0))
      .radius(Is(fill_chip_corner))
      .clips(Is(true))
      |> ignore
      f.box(fn(p) { p.grow(By(fn() { filled().to_double() })).ground(By(ground)) |> ignore }) |> ignore
      f.show(fn() { filled() < 100 }, fn(r) { r.grow(By(fn() { (100 - filled()).to_double() })) |> ignore })
    })
    b.box(fn(w) {
      w
      .row(Is(true))
      .padding(Is(if small && compact { (4.0, 0.0, 4.0, 0.0) } else if small { (5.0, 0.0, 5.0, 0.0) } else { (8.0, 0.0, 8.0, 0.0) }))
      .gap(By(fn() { if chip_joined(mark(), words()) { 0.0 } else { 5.0 } }))
      .lines_up(Is(Some(Middle)))
      |> ignore
      w.show(fn() { mark() != "" }, fn(m) {
        m.words(By(mark)).words_look(By(fn() { @ui.style_words(chip_text) })).ink(By(fn() { @ui.style_ink(chip_text) }))
        |> ignore
      })
      w.box(fn(n) {
        n.words(By(words)).words_look(By(fn() { @ui.style_words(chip_text) })).ink(By(fn() { @ui.style_ink(chip_text) }))
        |> ignore
      })
      |> ignore
    })
    |> ignore
    match tips {
      Some(t) => {
        // A fill chip never takes a press from the row holding it. It does take the pointer for its tip.
        b.points(By(fn() { said() != "" })) |> ignore
        tip_node(t, b, said) |> ignore
      }
      None => ()
    }
  })
}

///|
/// An allowance's chips in `parent` (quota_chips', not worded): a row of its windows' chips `gap` apart, each its
/// mark (`marked`) and what is left of it, what is left in words and when it fills again over it while pointed at (in
/// `tips`); nothing while `q` has none. Each as it changes.
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
      Some(Array(a)) if has_quota(q()) => a
      _ => []
    }
  }
  parent.show(fn() { windows().length() > 0 }, fn(row) {
    row.row(Is(true)).gap(Is(gap)).lines_up(Is(Some(Middle))) |> ignore
    // (each window by its mark)
    row.each(windows, fn(w) { chip_str(Some(w), "mark") }, fn(chip, one) {
      let w = fn() { Some(one.get()) }
      fill_chip_node(
        chip,
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
}
