///|
test "an old box reports its unconstrained requested height without changing its placed size" {
  let content = @signals.signal(40.0)
  let asked : Ref[(Double, Double)?] = Ref(None)
  let placed : Ref[(Double, Double)?] = Ref(None)
  let t = Tester::new(fn(c) {
    let id = c.id("fit")
    asked.val = c.laid_asked_size(id)
    placed.val = c.laid_size(id)
    c.box(w=Px(200.0), h=Px(100.0), fn() {
      c.box(w=Px(200.0), id~, fn() {
        c.box(w=Px(200.0), h=Px(30.0), fn() {  }) |> ignore
        c.capped("body", 800.0, shrinks=true, fn() {
          c.box(w=Px(200.0), h=Px(content.get()), fn() {  }) |> ignore
        }) |> ignore
      }) |> ignore
    }) |> ignore
  }, w=390.0, h=800.0)
  t.draw()
  assert_eq(asked.val, Some((200.0, 70.0)))
  assert_eq(placed.val, Some((200.0, 70.0)))
  content.set(500.0)
  t.draw()
  assert_eq(asked.val, Some((200.0, 530.0)))
  assert_true(placed.val.unwrap().1 < asked.val.unwrap().1)
  content.set(40.0)
  t.draw()
  assert_eq(asked.val, Some((200.0, 70.0)))
  assert_eq(placed.val, Some((200.0, 70.0)))
}

///|
test "a kept old part follows the requested size it read" {
  let content = @signals.signal(80.0)
  let asked : Ref[(Double, Double)?] = Ref(None)
  let t = Tester::new(fn(c) {
    let id = c.id("fit")
    let part = c.id("reader")
    c.part_nodes(part, "reader", fn() {
      asked.val = c.laid_asked_size(id)
      c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore
    }, true, own=true)
    c.box(w=Px(200.0), h=Px(content.get()), id~, fn() {  }) |> ignore
  }, w=390.0, h=800.0)
  t.draw()
  assert_eq(asked.val, Some((200.0, 80.0)))
  content.set(160.0)
  t.draw()
  assert_eq(asked.val, Some((200.0, 160.0)))
}
