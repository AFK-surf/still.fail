// A machine's chips in a line (meter_line's, meter_chip's) as nodes of the window's tree: each whole, in words where
// the line has the room for all of them, else all by their figures, one way for all; what each is over it while it is
// pointed at, in the tips of the panel it is in.

///|
/// A machine's CPU, memory and disk (`meters`, as they are now) in `parent` (meter_line's): a line as wide as what holds
/// it, its chips 8 apart, each whole: in words (内存剩 9.2 G) where the line has the room for all of them, else all by
/// their figures (内存 9.2G), never one cut short. Each says what it is over it while it is pointed at (MeterChips' tip:
/// its name, how much of how much, a note) in the layer of tips the panel it is in is lent (panel_tips_lent; none
/// outside a panel). `in_row`: what holds it lays what it holds in a row (its width what that leaves it).
#callsite(autofill(loc))
pub fn meter_line_node(
  parent : @view.View,
  meters : () -> Array[Json],
  in_row? : Bool = false,
  loc~ : SourceLoc,
) -> Unit {
  let tips = parent.lent(panel_tips_lent)
  let line = fn(r : @view.View, figure : Bool) {
    style_node(r, fn() { meter_line_way }, in_row=true)
    r.each(fn() { Array::makei(meters().length(), fn(i) { i }) }, fn(i) { i }, fn(c, i) {
      let k = i.untracked()
      meter_chip_node(c, fn() { meters().get(k) }, figure, tips)
    })
  }
  parent.box(made_for=loc, fn(b) {
    style_node(b, fn() { quota_chips_line }, in_row~)
    b.fits(Is(true)) |> ignore
    // (in words where the line has the room for all of them, else by their figures: the words' line left out of its
    // row where it has not the room, the figures' there only while it is, View::drops)
    b.box(fn(r) {
      r.drops(Is(1)) |> ignore
      line(r, false)
    })
    |> ignore
    b.box(fn(r) {
      r.drops(Is(-1)) |> ignore
      line(r, true)
    })
    |> ignore
  })
  |> ignore
}

///|
/// A machine's CPU, memory or disk (`m`, as it is now) in `c` (meter_chip's): its mark and what is left, filled as far as
/// is used; `figure`, the figure alone with its unit's first letter at the chip's own size. What it is over it while
/// pointed at, in `tips`.
fn meter_chip_node(c : @view.View, m : () -> Json?, figure : Bool, tips : TipLayer?) -> Unit {
  let words = fn() {
    let unit = chip_str(m(), "unit")
    if figure && chip_str(m(), "big") != "" {
      chip_str(m(), "big") + (if unit == "%" || unit == "" { unit } else { unit.clamped_view(end=1).to_owned() })
    } else {
      chip_str(m(), "remaining")
    }
  }
  let said = fn() {
    let note = chip_str(m(), "note")
    match chip_str(m(), "label") {
      "" => ""
      label => label + " " + chip_str(m(), "value") + (if note != "" { " · " + note } else { "" })
    }
  }
  fill_chip_node(
    c,
    fn() { 100 - chip_left(m()) },
    fn() { chip_str(m(), "level") },
    fn() { chip_str(m(), "short") },
    words,
    said~,
    tips?,
  )
  |> ignore
}
