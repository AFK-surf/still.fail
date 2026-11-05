// What the host says of the app and the window, read as signals: what reads it is told as it changes and nothing as it
// does not (app_visible, app_focused, app_awake; ime_inset; window_corner_at).

///|
test "the app shown or not: what reads it built again as the host says it otherwise, nothing else and never as it does not" {
  let shown_builds = Ref(0)
  let other_reads = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.show(fn() { app_visible() }, fn(n) {
      shown_builds.val = shown_builds.val + 1
      n.height(Is(Some(10.0))) |> ignore
    })
    root.box(fn(o) {
      o.height(By(fn() {
        other_reads.val = other_reads.val + 1
        Some(10.0)
      }))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let (shown, other) = (shown_builds.val, other_reads.val)
  t.draw()
  t.draw()
  assert_eq((shown_builds.val, other_reads.val), (shown, other), msg="frames with the app as it was build nothing")
  t.app_state(false, false)
  assert_eq(app_visible(), false)
  t.app_state(true, true)
  assert_eq(shown_builds.val, shown + 1, msg="shown again: what reads it built again, once")
  assert_eq(other_reads.val, other, msg="what reads it not: nothing")
}

///|
test "the window's corners: what reads them built again the frame they change, nothing on a frame they do not" {
  let reads = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, window_corners=[10.0, 10.0, 10.0, 10.0])
  set_view_app(fn(root) {
    root.box(fn(o) {
      o.height(By(fn() {
        reads.val = reads.val + 1
        Some(window_corner_at(0) + 10.0)
      }))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  assert_eq(window_corner_at(0), 10.0)
  let was = reads.val
  t.draw()
  t.draw()
  assert_eq(reads.val, was, msg="frames with the corners as they were read nothing again")
  // full screen: no corners of the system's
  h_set_full_screen(true)
  t.draw()
  assert_eq(window_corner_at(0), 0.0, msg="the frame they changed in")
  assert_eq(reads.val, was + 1, msg="read again once, that frame")
  h_set_full_screen(false)
}

///|
test "the soft keyboard's height read outside a frame's Ctx: what reads it told as it moves" {
  let reads = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(o) {
      o.height(By(fn() {
        reads.val = reads.val + 1
        Some(ime_inset() + 10.0)
      }))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let was = reads.val
  t.draw()
  assert_eq(reads.val, was, msg="a frame with it as it was reads nothing again")
  t.set_ime_inset(120.0)
  t.draw()
  assert_eq(ime_inset(), 120.0)
  assert_eq(reads.val, was + 1, msg="read again once, the frame it came up in")
  t.draw()
  assert_eq(reads.val, was + 1, msg="nothing again while it stays")
}
