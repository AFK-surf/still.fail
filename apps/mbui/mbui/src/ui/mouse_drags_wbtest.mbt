// Whether a mouse's drag moves a list, said once by a node of the window's tree (mouse_drags_lists) as what it reads
// changes, not each frame by an old view: an old view saying it in a frame over it for that frame; nothing said once the
// node is let go.

///|
test "a node says for the window whether a mouse drags the lists, as what it reads changes, with no old view built" {
  let drags = @signals.signal(false)
  let shown = @signals.signal(true)
  let builds = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.show(fn() { shown.get() }, fn(n) {
      n.grow(Is(1.0)) |> ignore
      mouse_drags_lists(n, fn() { drags.get() })
    })
    // (an old view beside it that says nothing of it: what it builds counted)
    old(root, fn(c) {
      builds.val = builds.val + 1
      c.box(w=Px(100.0), h=Px(20.0), fn() {  }) |> ignore
    })
    .height(Is(Some(20.0)))
    |> ignore
  })
  t.draw()
  assert_eq(desk.mouse_drags, false)
  // (frames drawn as a host draws them, and after this only those the app asks for (frames_owed): Tester::draw tells
  // what the test changed as an event from outside, building every old view again)
  t.measure_as_host()
  t.draw()
  let was = builds.val
  drags.set(true)
  t.frames_owed()
  assert_eq(desk.mouse_drags, true, msg="said again as what it reads changes")
  drags.set(false)
  t.frames_owed()
  assert_eq(desk.mouse_drags, false)
  assert_eq(builds.val, was, msg="no old view built for it: \{t.built_why()}")
  // the node let go: nothing said, as before anything was (a finger's way)
  shown.set(false)
  t.frames_owed()
  assert_eq(desk.mouse_drags, true, msg="nothing said once the node is let go")
}

///|
test "an old view saying whether a mouse drags the lists in a frame is over what the window's node says, for that frame" {
  let old_says : Ref[Bool?] = Ref(None)
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    mouse_drags_lists(root, fn() { false })
    old(root, fn(c) {
      match old_says.val {
        Some(on) => c.mouse_drags_lists(on)
        None => ()
      }
      c.box(w=Px(100.0), h=Px(20.0), fn() {  }) |> ignore
    }, key=fn() { old_says.val.to_string() })
    .height(Is(Some(20.0)))
    |> ignore
  })
  t.draw()
  assert_eq(desk.mouse_drags, false)
  old_says.val = Some(true)
  t.draw()
  assert_eq(desk.mouse_drags, true, msg="the old view's, for the frame it says it in")
}

///|
test "a node let go after another has said whether a mouse drags the lists leaves what the other said (a shell made anew)" {
  let a_shown = @signals.signal(true)
  let b_shown = @signals.signal(false)
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.show(fn() { a_shown.get() }, fn(a) { mouse_drags_lists(a, fn() { false }) })
    root.show(fn() { b_shown.get() }, fn(b) { mouse_drags_lists(b, fn() { false }) })
  })
  t.draw()
  assert_eq(desk.mouse_drags, false, msg="A's")
  // (Tester::draw tells what the test changed as an event from outside; frames_owed draws only what the app asks)
  b_shown.set(true)
  t.frames_owed()
  assert_eq(desk.mouse_drags, false, msg="B's")
  a_shown.set(false)
  t.frames_owed()
  assert_eq(desk.mouse_drags, false, msg="A let go after B said it: B's still")
  b_shown.set(false)
  t.frames_owed()
  assert_eq(desk.mouse_drags, true, msg="B let go too: nothing said")
}
