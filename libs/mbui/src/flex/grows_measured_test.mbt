// A row sized by what it holds (its width not given: measured at most the room it has) counts what grows in it at what
// it holds, to find how wide it comes to. Once that is known, by whatever made it known (the room it has, its max, its
// min), what grows flexes from its own flex basis, as its layout given that width does: what it holds measured at the
// width that layout gives it, its height the height laid out. Where what it holds fits and the row's width stays
// unknown, what grows is as wide as what it holds, as before.

///|
/// What grows from nothing (flex: 1 0 0, as narrow as nothing) holding words `text` long (10 a character, 10 a line).
fn from_none(text : String) -> @flex.Node {
  let c = @flex.Node::new()
  c.style.grow = 1.0
  c.style.shrink = 0.0
  c.style.set_basis(Pt(0.0))
  c.style.set_min_width(Pt(0.0))
  let w = @flex.Node::new()
  w.measure = Some(text_measure(text, row=false))
  c.add(w)
  c
}

///|
/// A lane `w` wide (a row, 24 in from either side, what it holds in its middle) holding `row`.
fn lane_of(row : @flex.Node) -> @flex.Node {
  let lane = @flex.Node::new()
  lane.style.direction = Row
  lane.style.set_padding_left(Pt(24.0))
  lane.style.set_padding_right(Pt(24.0))
  lane.style.justify = Center
  lane.add(row)
  lane
}

///|
/// A row with a gap of 12: a mark 16 wide, then what grows from nothing holding `text`.
fn marked_row(text : String) -> (@flex.Node, @flex.Node) {
  let row = @flex.Node::new()
  row.style.direction = Row
  row.style.set_gap_col(Pt(12.0))
  let mark = @flex.Node::new()
  mark.style.set_width(Pt(16.0))
  mark.style.set_height(Pt(10.0))
  row.add(mark)
  let grows = from_none(text)
  row.add(grows)
  (row, grows)
}

///|
/// How tall `lane` is measured at `w`, then laid out at `w` (reused): its height and those of `parts`.
fn measured_then_laid(lane : @flex.Node, w : Double, parts : Array[@flex.Node]) -> (Double, Double, Array[Double]) {
  let measured = @flex.measured_height(lane, w)
  @flex.compute(lane, width=w, round=false, reuse=true)
  (measured, lane.height, parts.map(fn(p) { p.height }))
}

///|
/// Words 280 on one line.
let grows_words : String = "words twenty eight long now."

///|
test "a row sized by what it holds, its growing words more than the room it has leaves them: measured as tall as it is laid out" {
  let words = grows_words
  // (the room it has: 300, in a column of a lane 1100 wide growing to at most 300, the row 308 asked; the words 272
  // wide, on two lines)
  let (row, grows) = marked_row(words)
  let capped = @flex.Node::new()
  capped.style.grow = 1.0
  capped.style.shrink = 1.0
  capped.style.set_min_width(Pt(0.0))
  capped.style.set_max_width(Pt(300.0))
  capped.add(row)
  let lane = lane_of(capped)
  assert_eq(measured_then_laid(lane, 1100.0, [grows]), (20.0, 20.0, [20.0]))
}

///|
test "a row sized by what it holds, at most 300, its growing words more than that leaves them: measured as tall as it is laid out" {
  let words = grows_words
  // (its max: 300, in a lane 1100 wide)
  let (row, grows) = marked_row(words)
  row.style.set_max_width(Pt(300.0))
  let lane = lane_of(row)
  assert_eq(measured_then_laid(lane, 1100.0, [grows]), (20.0, 20.0, [20.0]))
}

///|
test "a row sized by what it holds, at least 400, two growing from nothing: measured as tall as it is laid out, each as wide as the other" {
  // (its min: 400 holding two that grow from nothing, 260 and 50 of words: each 194, the first on two lines)
  let row = @flex.Node::new()
  row.style.direction = Row
  row.style.set_gap_col(Pt(12.0))
  row.style.set_min_width(Pt(400.0))
  let a = from_none("words of twenty five long.")
  let b = from_none("short")
  row.add(a)
  row.add(b)
  let lane = lane_of(row)
  assert_eq(measured_then_laid(lane, 1100.0, [a, b]), (20.0, 20.0, [20.0, 20.0]))
  assert_eq((a.width, b.width), (194.0, 194.0))
}

///|
test "a row sized by what it holds, its growing words fitting the room it has: as wide as its words, on one line, as before" {
  let words = grows_words
  // (the room it has more than it asks: its width unknown, what grows as wide as its words, on one line)
  let (row, grows) = marked_row(words)
  let lane = lane_of(row)
  assert_eq(measured_then_laid(lane, 1100.0, [grows]), (10.0, 10.0, [10.0]))
}

///|
test "a column sized by what it holds, more than the height it has: what grows from nothing in it as tall as what it holds, as before" {
  // (along a column the main size is the height itself, and what grows is counted at what it holds by its measure and
  // its layout alike: nothing of its width rides on it. A column 60 high at most in a row (not stretched), holding a
  // head 30 high and what grows from nothing holding 50: 80 high, past the 60, what grows 50, not squeezed to nothing)
  let root = @flex.Node::new()
  root.style.direction = Row
  root.style.align_items = FlexStart
  let col = @flex.Node::new()
  let head = @flex.Node::new()
  head.style.set_height(Pt(30.0))
  col.add(head)
  let grows = @flex.Node::new()
  grows.style.grow = 1.0
  grows.style.shrink = 0.0
  grows.style.set_basis(Pt(0.0))
  grows.style.set_min_height(Pt(0.0))
  let inner = @flex.Node::new()
  inner.style.set_height(Pt(50.0))
  grows.add(inner)
  col.add(grows)
  root.add(col)
  @flex.compute(root, width=400.0, height=60.0, round=false, reuse=true)
  assert_eq((col.height, grows.height), (80.0, 50.0))
}
