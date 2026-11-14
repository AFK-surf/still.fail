///|
/// Text of `len` characters 7 wide and lines 18 high, cheap to measure so
/// the benchmark times the layout.
fn cheap_text(len : Int) -> @flex.MeasureFn {
  let full = len.to_double() * 7.0
  fn(width, wm, _h, _hm) {
    let w = match wm {
      Exactly => width
      AtMost => if width < full { width } else { full }
      Undefined => full
    }
    let lines = if w > 0.0 { (full / w).ceil() } else { 1.0 }
    (w, lines * 18.0)
  }
}

///|
/// A chat screen's worth of rows like the demo's: avatar, then a column
/// with a name line and a bubble of wrapping text.
fn chat_rows(n : Int) -> @flex.Node {
  let root = @flex.Node::new()
  for i in 0..<n {
    let r = @flex.Node::new()
    r.style.direction = Row
    r.style.set_padding_left(Pt(16.0))
    r.style.set_padding_right(Pt(16.0))
    r.style.set_padding_top(Pt(6.0))
    r.style.set_padding_bottom(Pt(6.0))
    r.style.set_gap_col(Pt(10.0))
    r.style.align_items = FlexStart
    let avatar = @flex.Node::new()
    avatar.style.set_width(Pt(36.0))
    avatar.style.set_height(Pt(36.0))
    avatar.style.align_items = Center
    avatar.style.justify = Center
    let initial = @flex.Node::new()
    initial.measure = Some(cheap_text(1))
    avatar.add(initial)
    r.add(avatar)
    let body = @flex.Node::new()
    body.style.grow = 1.0
    body.style.shrink = 1.0
    body.style.set_basis(Pt(0.0))
    body.style.set_gap_row(Pt(4.0))
    body.style.align_items = FlexStart
    let head = @flex.Node::new()
    head.style.direction = Row
    head.style.set_gap_col(Pt(8.0))
    let name = @flex.Node::new()
    name.measure = Some(cheap_text(7))
    let time = @flex.Node::new()
    time.measure = Some(cheap_text(5))
    head.add(name)
    head.add(time)
    body.add(head)
    let bubble = @flex.Node::new()
    bubble.style.set_padding_left(Pt(12.0))
    bubble.style.set_padding_right(Pt(12.0))
    bubble.style.set_padding_top(Pt(8.0))
    bubble.style.set_padding_bottom(Pt(8.0))
    let text = @flex.Node::new()
    text.style.shrink = 1.0
    text.measure = Some(cheap_text(20 + i * 7 % 90))
    bubble.add(text)
    body.add(bubble)
    r.add(body)
    root.add(r)
  }
  root
}

///|
test "bench: 20 chat rows" (b : @bench.T) {
  let root = chat_rows(20)
  b.bench(name="chat_rows_20", fn() {
    @flex.compute(root, width=390.0, round=false)
    b.keep(root.height)
  })
}

///|
test "work for 20 chat rows" {
  let root = chat_rows(20)
  let before = [@flex.counters[0], @flex.counters[1], @flex.counters[2]]
  @flex.compute(root, width=390.0, round=false)
  println(
    "sized=\{@flex.counters[0] - before[0]} cached=\{@flex.counters[1] - before[1]} measured=\{@flex.counters[2] - before[2]} nodes=\{20 * 9 + 1}",
  )
}
