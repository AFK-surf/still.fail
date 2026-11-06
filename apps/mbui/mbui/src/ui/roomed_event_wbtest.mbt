// A layout read in the same event as an edit sees the edit before its node is removed.

///|
test "a roomed field set in an event is measured as written before its page is removed" {
  for by_room in [false, true] {
    let text = Field::new()
    let shown = @signals.signal(true)
    let node : Ref[@view.View?] = Ref(None)
    let read : Ref[Double] = Ref(0.0)
    let t = Tester::new(fn(_) { }, w=300.0, h=400.0, platform=0)
    set_view_app(fn(root) {
      root.show(fn() { shown.get() }, fn(page) {
        page.width(Is(Some(200.0))) |> ignore
        node.val = Some(if by_room {
          field(page, text, font_size=16.0, line=20.0, max_lines_in=(page, fn(_, _) { 6 }))
        } else {
          field(page, text, font_size=16.0, line=20.0, max_lines=6)
        })
      })
    })
    t.draw()
    let v = node.val.unwrap()
    let before = v.laid_size().1
    let tree = view_tree().unwrap()
    tree.event(t.time(), fn() {
      text.set("one\ntwo\nthree\nfour\nfive\nsix")
      read.val = v.laid_size().1
      shown.set(false)
    })
    assert_true(read.val > before, msg="roomed=\{by_room}: field height \{before} -> \{read.val}")
  }
}

///|
test "a roomed value changed in an event is measured before its node is removed" {
  let height = @signals.signal(20.0)
  let shown = @signals.signal(true)
  let node : Ref[@view.View?] = Ref(None)
  let read : Array[Double] = []
  let t = Tester::new(fn(_) { }, w=300.0, h=400.0, platform=0)
  set_view_app(fn(root) {
    root.show(fn() { shown.get() }, fn(page) {
      node.val = Some(page.box(fn(part) {
        part.width(Is(Some(200.0))).height(Roomed(page, fn(_, _) { Some(height.get()) })) |> ignore
      }))
    })
  })
  t.draw()
  let v = node.val.unwrap()
  assert_eq(v.laid_size().1, 20.0)
  let tree = view_tree().unwrap()
  tree.event(t.time(), fn() {
    height.set(120.0)
    read.push(v.laid_size().1)
    height.set(60.0)
    read.push(v.laid_size().1)
    shown.set(false)
  })
  assert_eq(read, [120.0, 60.0], msg="both reads include their changes before the page is removed")
}

///|
test "a roomed field inside a layout box is measured as written during the event" {
  let text = Field::new()
  let field_node : Ref[@view.View?] = Ref(None)
  let holder : Ref[@view.View?] = Ref(None)
  let read : Ref[(Double, Double)] = Ref((0.0, 0.0))
  let t = Tester::new(fn(_) { }, w=300.0, h=400.0, platform=0)
  set_view_app(fn(root) {
    root.layout_box(Is(()), fn(l, _) {
      let page = l.child("page", fn(page) {
        holder.val = Some(page.box(fn(box) {
          field_node.val = Some(field(box, text, font_size=16.0, line=20.0, max_lines_in=(root, fn(_, h) { if h >= 300.0 { 6 } else { 1 } })))
        }))
      })
      l.measure(page, 200.0) |> ignore
      l.place(page, 0.0, 0.0)
    }) |> ignore
  })
  t.draw()
  let page = holder.val.unwrap()
  let v = field_node.val.unwrap()
  let before = (page.laid_size().1, v.laid_size().1)
  let tree = view_tree().unwrap()
  tree.event(t.time(), fn() {
    text.set("one\ntwo\nthree\nfour\nfive\nsix")
    read.val = (page.laid_size().1, v.laid_size().1)
  })
  assert_true(read.val.0 > before.0 && read.val.1 > before.1,
    msg="holder and field grow inside the event: \{before} -> \{read.val}")
}

///|
test "a roomed field in nested sized layouts uses its page height during an event" {
  let text = Field::new()
  let field_node : Ref[@view.View?] = Ref(None)
  let holder : Ref[@view.View?] = Ref(None)
  let page_node : Ref[@view.View?] = Ref(None)
  let read : Ref[(Double, Double)] = Ref((0.0, 0.0))
  let t = Tester::new(fn(_) { }, w=390.0, h=800.0, platform=0)
  set_view_app(fn(root) {
    root.show(fn() { true }, fn(page) {
      page.width_share(Is(1.0)).height_share(Is(1.0)) |> ignore
      page_node.val = Some(page)
      page.layout_box(Is(()), fn(l, _) {
        let editor = l.child("editor", fn(editor) {
          holder.val = Some(editor)
          editor.box(fn(wrapper) {
            let cap = wrapper.box(fn(cap) {
              field_node.val = Some(field(cap, text, font_size=16.0, line=20.0,
                max_lines_in=(page, fn(_, h) { if h >= 300.0 { 6 } else { 1 } })))
            })
            wrapper.layout_box(Is(()), sized=true, fn(inner, _) {
              let (_, h) = inner.measure(cap, inner.width)
              inner.size_to(h)
              inner.place(cap, 0.0, 0.0)
            }) |> ignore
          }) |> ignore
        })
        l.measure(editor, l.width - 16.0) |> ignore
        l.place(editor, 8.0, 0.0)
      }) |> ignore
    })
  })
  t.draw()
  let page = page_node.val.unwrap()
  let editor = holder.val.unwrap()
  let v = field_node.val.unwrap()
  assert_true(page.laid_size().1 >= 300.0, msg="the page actually has room for six lines: \{page.laid_size()}")
  let before = (editor.laid_size().1, v.laid_size().1)
  let tree = view_tree().unwrap()
  tree.event(t.time(), fn() {
    text.set("one\ntwo\nthree\nfour\nfive\nsix")
    page.laid_size() |> ignore
    read.val = (editor.laid_size().1, v.laid_size().1)
  })
  assert_true(read.val.0 > before.0 && read.val.1 > before.1,
    msg="nested holder and field grow inside the event: \{before} -> \{read.val}")
}

///|
test "a roomed measurement can be read again after an unchanged computed value and a rebind" {
  let n = @signals.signal(0, same=fn(a, b) { a == b })
  let parity = @signals.computed(fn(_) { n.get() % 2 }, same=fn(a, b) { a == b })
  let node : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_) { }, w=300.0, h=400.0, platform=0)
  set_view_app(fn(root) {
    node.val = Some(root.box(fn(v) {
      v.height(Roomed(root, fn(_, _) { Some(20.0 + 40.0 * parity.get().to_double()) })) |> ignore
    }))
  })
  t.draw()
  let v = node.val.unwrap()
  let tree = view_tree().unwrap()
  let sizes : Array[Double] = []
  let before = tree.work().computes
  let after_same = Ref(0)
  tree.event(t.time(), fn() {
    n.set(2)
    sizes.push(v.laid_size().1)
    after_same.val = tree.work().computes
    n.set(3)
    sizes.push(v.laid_size().1)
    n.set(4)
    v.height(Is(Some(80.0))) |> ignore
    sizes.push(v.laid_size().1)
    n.set(5)
    sizes.push(v.laid_size().1)
  })
  assert_eq(after_same.val, before, msg="an unchanged computed value does not require layout")
  assert_eq(sizes, [20.0, 60.0, 80.0, 80.0])
}

///|
test "a roomed read pulls only the bindings marked in the event" {
  let still = @signals.signal(1.0, same=fn(a, b) { a == b })
  let changed = @signals.signal(1.0, same=fn(a, b) { a == b })
  let node : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_) { }, w=300.0, h=400.0, platform=0)
  set_view_app(fn(root) {
    for _ in 0..<100 {
      root.box(fn(v) { v.height(Roomed(root, fn(_, _) { Some(still.get()) })) |> ignore }) |> ignore
    }
    node.val = Some(root.box(fn(v) { v.height(Roomed(root, fn(_, _) { Some(changed.get()) })) |> ignore }))
  })
  t.draw()
  let tree = view_tree().unwrap()
  let before = tree.work().pulled
  tree.event(t.time(), fn() {
    changed.set(2.0)
    node.val.unwrap().laid_size() |> ignore
  })
  assert_eq(tree.work().pulled - before, 1)
  assert_eq(node.val.unwrap().laid_size().1, 2.0)
}
