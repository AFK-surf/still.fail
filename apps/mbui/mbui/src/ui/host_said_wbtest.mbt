// What the host has once (on_host_said): asked as each frame begins, handed to its one holder once, before any of the
// window's tree is built; asked no more once its holder is let go; what is laid out never read as it is handed on.

///|
/// A host's thing had once, as its ABI says it (taken as it is read): `put` puts one there, `said` takes it, `asked`
/// how many times it was asked.
priv struct OnceHad {
  had : Ref[String?]
  asked : Ref[Int]
}

///|
fn OnceHad::new() -> OnceHad {
  { had: Ref(None), asked: Ref(0) }
}

///|
fn OnceHad::said(self : OnceHad) -> String? {
  self.asked.val = self.asked.val + 1
  let v = self.had.val
  self.had.val = None
  v
}

///|
test "what the host has once is handed to its holder once, as the frame begins, what it sets read by that frame's build" {
  let host = OnceHad::new()
  let got : Array[String] = []
  let shared = @signals.signal("")
  let built : Array[String] = []
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    on_host_said(root, kind="shared-in", fn() { host.said() }, fn(words) {
      got.push(words)
      // (reads and sets signals as it likes: what it sets read as the frame is built after it)
      if shared.get() == "" {
        shared.set(words)
      }
    })
    root.show(fn() { shared.get() != "" }, fn(n) {
      built.push(@signals.untracked(fn() { shared.get() }))
      n.height(Is(Some(10.0))) |> ignore
    })
  })
  t.draw()
  assert_eq(got, [])
  host.had.val = Some("from another app")
  t.draw()
  assert_eq(got, ["from another app"], msg="handed on once")
  assert_eq(built, ["from another app"], msg="the frame it came in builds what reads it")
  t.draw()
  t.draw()
  assert_eq(got, ["from another app"], msg="not again: the host had it once")
}

///|
test "a holder let go is asked no more, and one let go as another's is handed on is not asked that frame" {
  let first = OnceHad::new()
  let second = OnceHad::new()
  let held = @signals.signal(true)
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.show(fn() { held.get() }, fn(n) {
      // the first one's f lets the second's holder go
      on_host_said(n, kind="first", fn() { first.said() }, fn(_) { held.set(false) })
    })
    root.show(fn() { held.get() }, fn(n) {
      on_host_said(n, kind="second", fn() { second.said() }, fn(_) {  })
    })
  })
  t.draw()
  let asked = second.asked.val
  t.draw()
  assert_eq(second.asked.val, asked + 1, msg="asked as each frame begins while held")
  first.had.val = Some("go")
  t.draw()
  let then = second.asked.val
  assert_true(then <= asked + 2, msg="not asked once let go by the first's, that frame: \{then}")
  t.draw()
  t.draw()
  assert_eq(second.asked.val, then, msg="asked no more once let go")
}

///|
test "panic: what is laid out read as what the host has once is handed on aborts" {
  let host = OnceHad::new()
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    on_host_said(root, kind="keep-result", fn() { host.said() }, fn(_) { root.laid_size_told() |> ignore })
  })
  t.draw()
  host.had.val = Some("kept")
  t.draw()
}

///|
test "panic: two holders of one kind of what the host has once abort" {
  let host = OnceHad::new()
  let _t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    on_host_said(root, kind="shared-in", fn() { host.said() }, fn(_) {  })
    on_host_said(root, kind="shared-in", fn() { host.said() }, fn(_) {  })
  })
  _t.draw()
}

///|
test "what the host has once handed on writes what another node's reaction follows, that reading where it is laid out: no fault, it told where" {
  let host = OnceHad::new()
  let flash = @signals.signal(0)
  let seen : Array[(Int, Bool)] = []
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.width(Is(Some(100.0))).height(Is(Some(40.0))) |> ignore
      // (another node's own reaction: what it follows read as told last)
      b.reacts(fn() { (flash.get(), b.laid_window_told()) }, fn(now) { seen.push((now.0, now.1 is Some(_))) })
    })
    |> ignore
    on_host_said(root, kind="notice-opened", fn() { host.said() }, fn(_) { flash.set(1) })
  })
  t.draw()
  t.draw()
  host.had.val = Some("opened")
  t.draw()
  assert_eq(seen.last(), Some((1, true)))
}

///|
test "what the host has once handed on shows a node whose binding reads its own size as told: no fault, it laid out" {
  let host = OnceHad::new()
  let shown = @signals.signal(false)
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.show(fn() { shown.get() }, fn(n) {
      n.width(Is(Some(100.0))).height(By(fn() { n.laid_size_told().map(fn(z) { z.0 / 2.0 }) })) |> ignore
    })
    on_host_said(root, kind="page-opened", fn() { host.said() }, fn(_) { shown.set(true) })
  })
  t.draw()
  host.had.val = Some("opened")
  t.draw()
  t.draw()
  assert_eq(shown.get(), true)
}

///|
test "what the host has once handed on lays the tree out as of its moment (laid_size, laid_window_now): the tree tells where it placed what follows that, no fault" {
  let host = OnceHad::new()
  let wide = @signals.signal(100.0)
  let seen : Array[Bool] = []
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.width(By(fn() { Some(wide.get()) })).height(Is(Some(40.0))) |> ignore
      // (what follows where it is placed: the tree tells it once laid out, Tree::sizes_told)
      b.reacts(fn() { b.laid_window_told() }, fn(r) { seen.push(r is Some(_)) })
      on_host_said(root, kind="slide-asked", fn() { host.said() }, fn(_) {
        wide.set(160.0)
        // (how wide it is and where as of now, laid out for it there and then: a slide's length said by it; reads that
        // lay out as of the moment, not shut)
        b.laid_size() |> ignore
        b.laid_window_now() |> ignore
      })
    })
    |> ignore
  })
  t.draw()
  host.had.val = Some("asked")
  t.draw()
  assert_eq(seen.last(), Some(true))
}

///|
test "panic: what is laid out read by what is handed on itself, laid_window_told, aborts" {
  let host = OnceHad::new()
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    on_host_said(root, kind="notice-opened", fn() { host.said() }, fn(_) { root.laid_window_told() |> ignore })
  })
  t.draw()
  host.had.val = Some("opened")
  t.draw()
}
