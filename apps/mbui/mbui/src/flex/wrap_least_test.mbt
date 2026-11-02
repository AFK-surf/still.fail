// Style's wrap_least (not CSS's): a row that wraps goes on in another line only where a line has not the room for its
// items at the least each comes to, and none of them comes to less; on one line its items share it as without it.

///|
/// A row `w` wide that wraps (`least`: by its items' least), 10 apart along a line and 6 between lines, at its end: a
/// title 120 wide by what it holds, growing and giving way, 80 at least; and a row of what it does, giving way, its
/// least not said: 分享 30 wide, never giving way, and a choice 100 wide, giving way down to 60, 10 apart. The title,
/// the row, 分享, the choice.
fn least_row(w : Double, least : Bool) -> (@flex.Node, @flex.Node, @flex.Node, @flex.Node) {
  let root = least_root(w, least)
  let ends = root.children[1]
  (root.children[0], ends, ends.children[0], ends.children[1])
}

///|
/// least_row's row, laid out.
fn least_root(w : Double, least : Bool) -> @flex.Node {
  let root = @flex.Node::new()
  root.style.position = Absolute
  root.style.direction = Row
  root.style.wrap = Wrap
  root.style.wrap_least = least
  root.style.justify = FlexEnd
  root.style.align_items = FlexStart
  root.style.set_gap_col(Pt(10.0))
  root.style.set_gap_row(Pt(6.0))
  root.style.set_width(Pt(w))
  let title = @flex.Node::new()
  title.style.set_width(Pt(120.0))
  title.style.set_height(Pt(20.0))
  title.style.grow = 1.0
  title.style.shrink = 1.0
  title.style.set_min_width(Pt(80.0))
  let ends = @flex.Node::new()
  ends.style.direction = Row
  ends.style.set_gap_col(Pt(10.0))
  ends.style.shrink = 1.0
  let share = @flex.Node::new()
  share.style.set_width(Pt(30.0))
  share.style.set_height(Pt(30.0))
  let choice = @flex.Node::new()
  choice.style.set_width(Pt(100.0))
  choice.style.set_height(Pt(30.0))
  choice.style.shrink = 1.0
  choice.style.set_min_width(Pt(60.0))
  ends.add(share)
  ends.add(choice)
  root.add(title)
  root.add(ends)
  @flex.compute(root)
  root
}

///|
test "wrap_least: room for all as they ask, one line, the title growing" {
  let (title, ends, share, choice) = least_row(400.0, true)
  check("title", title, 0.0, 0.0, 250.0, 20.0)
  check("ends", ends, 260.0, 0.0, 140.0, 30.0)
  check("share", share, 0.0, 0.0, 30.0, 30.0)
  check("choice", choice, 40.0, 0.0, 100.0, 30.0)
}

///|
test "wrap_least: less room than they ask but enough for their least, one line, sharing the lack by their widths as without it; there without it two lines" {
  // (270 asked, 257: 13 less, the title 120 of 260 of it, the row 140)
  let (title, ends, _, choice) = least_row(257.0, true)
  check("title", title, 0.0, 0.0, 114.0, 20.0)
  check("ends", ends, 124.0, 0.0, 133.0, 30.0)
  check("choice", choice, 40.0, 0.0, 93.0, 30.0)
  let (title, ends, _, _) = least_row(257.0, false)
  check("title", title, 0.0, 0.0, 257.0, 20.0)
  check("ends", ends, 117.0, 26.0, 140.0, 30.0)
}

///|
test "wrap_least: the row never less than what it holds at their least, the title giving way for it" {
  // (78 less: by their widths the row would come to 98, under its 30 + 10 + 60)
  let (title, ends, _, choice) = least_row(192.0, true)
  check("title", title, 0.0, 0.0, 82.0, 20.0)
  check("ends", ends, 92.0, 0.0, 100.0, 30.0)
  check("choice", choice, 40.0, 0.0, 60.0, 30.0)
}

///|
test "wrap_least: room for their least exactly, one line; a point less, the row under the title, at the line's end, as wide as it asks" {
  let (title, ends, _, _) = least_row(190.0, true)
  check("title", title, 0.0, 0.0, 80.0, 20.0)
  check("ends", ends, 90.0, 0.0, 100.0, 30.0)
  let (title, ends, _, choice) = least_row(189.0, true)
  check("title", title, 0.0, 0.0, 189.0, 20.0)
  check("ends", ends, 49.0, 26.0, 140.0, 30.0)
  check("choice", choice, 40.0, 0.0, 100.0, 30.0)
}

///|
/// What a node's items come to (left, top, width, height each), laid out again as it is now.
fn laid_again(root : @flex.Node) -> Array[(Double, Double, Double, Double)] {
  @flex.compute(root)
  root.children.map(fn(c) { (c.left, c.top, c.width, c.height) })
}

///|
test "wrap_least: the same node a column, or said not to, as one that wraps without it: a row's alone" {
  for w in [400.0, 257.0, 192.0, 189.0] {
    let root = least_root(w, true)
    let plain = least_root(w, false)
    // (a column: as one that wraps by its items' asks, the same node turned and turned back)
    for d in [@flex.Column, @flex.Row] {
      root.style.direction = d
      plain.style.direction = d
      root.style.set_height(Pt(50.0))
      plain.style.set_height(Pt(50.0))
      if d == @flex.Column {
        assert_eq(laid_again(root), laid_again(plain), msg="\{w}: a column")
      }
    }
    root.style.set_height(Auto)
    plain.style.set_height(Auto)
    // (said not to, and said again: as without it, then as with it)
    let said = laid_again(root)
    root.style.wrap_least = false
    assert_eq(laid_again(root), laid_again(plain), msg="\{w}: said not to")
    root.style.wrap_least = true
    assert_eq(laid_again(root), said, msg="\{w}: said again")
  }
}

///|
/// A row `w` wide that wraps by its items' least (least_row's, 10 and 6 apart, at its end): a title 120 wide by what it
/// holds, growing and giving way, 80 at least; then a row giving way, its least not said, holding `part`. The title, the
/// row, the part.
fn least_with(w : Double, part : @flex.Node) -> (@flex.Node, @flex.Node, @flex.Node) {
  let root = @flex.Node::new()
  root.style.position = Absolute
  root.style.direction = Row
  root.style.wrap = Wrap
  root.style.wrap_least = true
  root.style.justify = FlexEnd
  root.style.align_items = FlexStart
  root.style.set_gap_col(Pt(10.0))
  root.style.set_gap_row(Pt(6.0))
  root.style.set_width(Pt(w))
  let title = @flex.Node::new()
  title.style.set_width(Pt(120.0))
  title.style.set_height(Pt(20.0))
  title.style.grow = 1.0
  title.style.shrink = 1.0
  title.style.set_min_width(Pt(80.0))
  let ends = @flex.Node::new()
  ends.style.direction = Row
  ends.style.shrink = 1.0
  ends.add(part)
  root.add(title)
  root.add(ends)
  @flex.compute(root)
  (title, ends, part)
}

///|
test "wrap_least: a part that gives way, its least not said, counted at its padding at least (as the line brings it no lower)" {
  // (a column 10 in on each side, nothing in it: 20 at least; 80 + 10 + 20 = 110)
  let part = fn() {
    let p = @flex.Node::new()
    p.style.shrink = 1.0
    p.style.set_min_width(Pt(0.0))
    p.style.set_padding_left(Pt(10.0))
    p.style.set_padding_right(Pt(10.0))
    p.style.set_width(Pt(60.0))
    p.style.set_height(Pt(10.0))
    p
  }
  let (title, ends, p) = least_with(110.0, part())
  check("title", title, 0.0, 0.0, 80.0, 20.0)
  check("ends", ends, 90.0, 0.0, 20.0, 10.0)
  check("part", p, 0.0, 0.0, 20.0, 10.0)
  let (title, ends, _) = least_with(109.0, part())
  check("title", title, 0.0, 0.0, 109.0, 20.0)
  check("ends", ends, 49.0, 26.0, 60.0, 10.0)
}

///|
test "wrap_least: a part that never gives way counted at its flex basis, not its width (as the line has it)" {
  // (100 wide, its basis 30: 30 in its row; 80 + 10 + 30 = 120)
  let part = fn() {
    let p = @flex.Node::new()
    p.style.set_width(Pt(100.0))
    p.style.set_basis(Pt(30.0))
    p.style.set_height(Pt(10.0))
    p
  }
  let (title, ends, p) = least_with(125.0, part())
  check("title", title, 0.0, 0.0, 85.0, 20.0)
  check("ends", ends, 95.0, 0.0, 30.0, 10.0)
  check("part", p, 0.0, 0.0, 30.0, 10.0)
  let (title, ends, _) = least_with(119.0, part())
  check("title", title, 0.0, 0.0, 119.0, 20.0)
  check("ends", ends, 89.0, 26.0, 30.0, 10.0)
}

///|
test "wrap_least: a part that gives way but is never narrower than what it holds (min_held) counted at that, as the line has it" {
  // (a column of no basis, 0 at least but never narrower than the 60 it holds: 80 + 10 + 60 = 150)
  let part = fn() {
    let p = @flex.Node::new()
    p.style.set_basis(Pt(0.0))
    p.style.shrink = 1.0
    p.style.set_min_width(Pt(0.0))
    p.style.min_held = true
    let held = @flex.Node::new()
    held.style.set_width(Pt(60.0))
    held.style.set_height(Pt(10.0))
    p.add(held)
    p
  }
  let (title, ends, p) = least_with(150.0, part())
  check("title", title, 0.0, 0.0, 80.0, 20.0)
  check("ends", ends, 90.0, 0.0, 60.0, 10.0)
  check("part", p, 0.0, 0.0, 60.0, 10.0)
  let (title, ends, p) = least_with(149.0, part())
  check("title", title, 0.0, 0.0, 149.0, 20.0)
  check("ends", ends, 89.0, 26.0, 60.0, 10.0)
  check("part", p, 0.0, 0.0, 60.0, 10.0)
}
