///|
test "a parent measures one child and allocates the remaining space in the same layout" {
  let root = @flex.Node::new()
  let body = @flex.Node::new()
  let foot = @flex.Node::new()
  root.add(body)
  root.add(foot)
  let lines = Ref(2.0)
  foot.measure = Some(fn(w, _, _, _) { (w, lines.val * 20.0) })
  root.arrange = Some(fn(room) {
    let w = room.width().unwrap()
    let h = room.height().unwrap()
    let f = room.measure(foot, width=w)
    let b = room.measure(body, width=w, height=h - f.size().1)
    @flex.arrangement(w, h, [b.at(0.0, 0.0), f.at(0.0, b.size().1)])
  })
  for n in [2.0, 6.0, 1.0] {
    lines.val = n
    foot.dirty = true
    root.dirty = true
    @flex.compute(root, width=300.0, height=600.0, round=false, reuse=true)
    assert_eq((foot.top, foot.height), (600.0 - n * 20.0, n * 20.0))
    assert_eq((body.height, body.top), (foot.top, 0.0))
  }
}

///|
test "a custom container uses its content constraints and places overlays once" {
  let root = @flex.Node::new()
  root.style.set_padding_left(Pt(10.0))
  root.style.set_padding_right(Pt(20.0))
  root.style.set_padding_top(Pt(7.0))
  let child = @flex.Node::new()
  child.style.position = Absolute
  child.style.set_inset_right(Pt(0.0))
  root.add(child)
  root.arrange = Some(fn(room) {
    let w = room.width().unwrap()
    let c = room.measure(child, width=w / 2.0, height=30.0)
    @flex.arrangement(w, 30.0, [c.at(3.0, 0.0)])
  })
  @flex.compute(root, width=330.0, round=false)
  assert_eq((root.width, root.height), (330.0, 37.0))
  assert_eq((child.left, child.top, child.width, child.height), (13.0, 7.0, 150.0, 30.0))
}

///|
test "an intrinsic container measures children inside its maximum content width" {
  let root = @flex.Node::new()
  root.style.align_items = FlexStart
  let card = @flex.Node::new()
  card.style.set_max_width(Pt(200.0))
  card.style.set_padding_left(Pt(10.0))
  card.style.set_padding_right(Pt(10.0))
  let text = @flex.Node::new()
  text.measure = Some(fn(w, _, _, _) { (w, 30.0) })
  card.add(text)
  root.add(card)
  card.arrange = Some(fn(room) {
    let t = room.measure(text)
    let (w, h) = t.size()
    @flex.arrangement(w, h, [t.at(0.0, 0.0)])
  })
  @flex.compute(root, width=500.0, round=false)
  assert_eq((card.width, text.width, text.left), (200.0, 180.0, 10.0))
}

///|
test "placing a folded container consumes its measured content without measuring it at the folded width" {
  let root = @flex.Node::new()
  root.style.direction = Row
  root.style.align_items = FlexStart
  let fold = @flex.Node::new()
  let content = @flex.Node::new()
  content.measure = Some(fn(w, mode, _, _) {
    (if mode == Undefined || w > 120.0 { 120.0 } else { w }, 20.0)
  })
  fold.add(content)
  root.add(fold)
  let fraction = Ref(0.5)
  fold.arrange = Some(fn(room) {
    let child = room.measure(content)
    let (w, h) = child.size()
    @flex.arrangement(w * fraction.val, h, [child.at(0.0, 0.0)])
  })
  for k in [0.5, 0.0, 1.0] {
    fraction.val = k
    fold.dirty = true
    root.dirty = true
    @flex.compute(root, width=300.0, round=false, reuse=true)
    assert_eq((fold.width, fold.height), (120.0 * k, 20.0))
    assert_eq((content.width, content.height), (120.0, 20.0))
  }
}
