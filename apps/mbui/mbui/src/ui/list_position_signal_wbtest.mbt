///|
test "a list's position can be followed without rebuilding its reader" {
  let reader : Ref[ListReader?] = Ref(None)
  let t = Tester::new(fn(c) {
    c.list("messages", 100, 50.0, fn(i) {
      c.box(h=Px(50.0), fn() { c.text("message \{i}") |> ignore }) |> ignore
    })
    |> ignore
    if reader.val is None {
      reader.val = Some(c.list_reader("messages"))
    }
  }, w=390.0, h=400.0)
  t.draw()
  let reader = reader.val.unwrap()
  let seen : Array[ListSnapshot?] = []
  let during_build : Array[Bool] = []
  let stop = @signals.effect(fn() {
    seen.push(reader.snapshot())
    during_build.push(building.val)
  })
  let first = seen.last().unwrap().unwrap()
  assert_eq(first.info.first, 0)
  t.wheel(200.0, 200.0, 10.0)
  let within_row = seen.last().unwrap().unwrap()
  assert_eq(within_row.info.first, first.info.first)
  assert_true(within_row.place != first.place)
  t.wheel(200.0, 200.0, 250.0)
  let after = reader.snapshot().unwrap()
  assert_true(after.info.first > first.info.first)
  assert_true(seen.length() > 1)
  assert_eq(seen.last().unwrap(), Some(after))
  assert_true(during_build.iter().all(fn(b) { !b }))
  let n = seen.length()
  t.frame()
  assert_eq(seen.length(), n)
  t.resize(390.0, 300.0)
  assert_eq(seen.last().unwrap().unwrap().info.height, 300.0)
  let n = seen.length()
  stop()
  t.wheel(200.0, 200.0, 100.0)
  assert_eq(seen.length(), n)
}

///|
test "a list can be followed before it is first made" {
  let show = @signals.signal(false, same=fn(a, b) { a == b })
  let reader : Ref[ListReader?] = Ref(None)
  let t = Tester::new(fn(c) {
    if reader.val is None {
      reader.val = Some(c.list_reader("messages"))
    }
    if show.get() {
      c.list("messages", 20, 50.0, fn(i) { c.text("message \{i}") |> ignore }) |> ignore
    }
  })
  let seen : Array[ListSnapshot?] = []
  let stop = @signals.effect(fn() { seen.push(reader.val.unwrap().snapshot()) })
  assert_eq(seen.last(), Some(None))
  show.set(true)
  t.draw()
  assert_true(seen.last().unwrap() is Some(_))
  stop()
}

///|
test "a list follower is told when its page is released" {
  let nav = Nav::new(0)
  let reader : Ref[ListReader?] = Ref(None)
  let t = Tester::new(fn(c) {
    c.nav(nav, fn(page) {
      if page == 1 {
        c.list("messages", 20, 50.0, fn(i) { c.text("message \{i}") |> ignore }) |> ignore
        if reader.val is None {
          reader.val = Some(c.list_reader("messages"))
        }
      }
    }) |> ignore
  })
  nav.push(1)
  t.run_for(move_most_ms)
  let seen : Array[ListSnapshot?] = []
  let during_build : Array[Bool] = []
  let stop = @signals.effect(fn() {
    seen.push(reader.val.unwrap().snapshot())
    during_build.push(building.val)
  })
  assert_true(seen.last().unwrap() is Some(_))
  nav.pop() |> ignore
  t.run_for(move_most_ms)
  assert_eq(seen.last(), Some(None))
  assert_true(during_build.iter().all(fn(b) { !b }))
  stop()
}
