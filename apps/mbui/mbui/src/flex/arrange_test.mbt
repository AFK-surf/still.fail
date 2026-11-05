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
test "overlays added beside an arrangement follow the current container without replacing explicit placements" {
  let root = @flex.Node::new()
  root.style.position = Relative
  let owned = @flex.Node::new()
  owned.style.position = Absolute
  owned.style.set_inset_right(Pt(0.0))
  root.add(owned)
  root.arrange = Some(fn(room) {
    let child = room.measure(owned, width=40.0, height=20.0)
    @flex.arrangement(room.width().unwrap(), 200.0, [child.at(13.0, 17.0)])
  })
  let overlay = @flex.Node::new()
  overlay.style.position = Absolute
  overlay.style.set_width(Pt(30.0))
  overlay.style.set_height(Pt(16.0))
  overlay.style.set_inset_right(Pt(10.0))
  overlay.style.set_inset_bottom(Pt(12.0))
  root.add(overlay)
  for width in [300.0, 450.0, 300.0, 300.0] {
    @flex.compute(root, width~, round=false, reuse=true)
    assert_eq((owned.left, owned.top, owned.width, owned.height), (13.0, 17.0, 40.0, 20.0))
    assert_eq((overlay.left, overlay.top, overlay.width, overlay.height), (width - 40.0, 172.0, 30.0, 16.0))
  }
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

///|
test "equal occupied sizes do not make arrangements at different available widths interchangeable" {
  let root = @flex.Node::new()
  root.style.direction = Row
  root.style.align_items = FlexStart
  let fold = @flex.Node::new()
  let content = @flex.Node::new()
  fold.add(content)
  root.add(fold)
  fold.arrange = Some(fn(room) {
    let child = room.measure(content, width=room.max_width().unwrap(), height=20.0)
    @flex.arrangement(50.0, 20.0, [child.at(0.0, 0.0)])
  })
  for width in [300.0, 200.0, 400.0, 200.0] {
    @flex.compute(root, width~, round=false, reuse=true)
    assert_eq((fold.width, fold.height), (50.0, 20.0))
    assert_eq((content.width, content.height), (width, 20.0))
  }
}

///|
test "a parent's chosen measurement retains its child placement after other measurements" {
  let root = @flex.Node::new()
  let card = @flex.Node::new()
  let content = @flex.Node::new()
  root.add(card)
  card.add(content)
  card.style.set_padding_left(Pt(7.0))
  card.arrange = Some(fn(room) {
    let w = room.width().unwrap()
    let child = room.measure(content, width=w / 2.0, height=w / 4.0)
    @flex.arrangement(w, w / 2.0, [child.at(w / 4.0, 3.0)])
  })
  root.arrange = Some(fn(room) {
    let chosen = room.measure(card, width=127.0)
    for width in 140..<180 { room.measure(card, width=width.to_double()) |> ignore }
    @flex.arrangement(300.0, 100.0, [chosen.at(11.0, 13.0)])
  })
  @flex.compute(root, width=300.0, round=false)
  assert_eq((card.left, card.top, card.width, card.height), (11.0, 13.0, 127.0, 60.0))
  assert_eq((content.left, content.top, content.width, content.height), (37.0, 3.0, 60.0, 30.0))
}
