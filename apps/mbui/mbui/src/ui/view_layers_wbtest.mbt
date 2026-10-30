// Old views one over another, each the whole window (the narrow shell's shape: what is under the pages, a page, what
// floats over them): a press is the old view's whose hit target the old frame finds there, whatever boxes lie over it
// (one drawing nothing there passes it on), held so till it is let go; the others, reading nothing that changed, are
// not built for it.

///|
priv struct Layers {
  t : Tester
  builds : Array[Int]
  taps : Array[Int]
}

///|
/// Under (no button), a page (a button at its top left, 100 by 100) and over it (a button at (200, 600), 100 by 100;
/// nothing elsewhere), each the whole window; their builds and their buttons' presses counted, in that order.
fn layers() -> Layers {
  let builds = [0, 0, 0]
  let taps = [0, 0, 0]
  let layer = fn(k : Int, button : (Double, Double)?) {
    fn(c : Ctx) {
      builds[k] = builds[k] + 1
      match button {
        Some((x, y)) => {
          let id = c.id("button \{k}")
          if c.clicked(id) {
            taps[k] = taps[k] + 1
          }
          c.box(left=x, top=y, w=Px(100.0), h=Px(100.0), bg=0x3366CCFFL, id~, fn() {  }) |> ignore
        }
        None => ()
      }
    }
  }
  let t = Tester::new(fn(_c) {  })
  t.keep_parts(true)
  t.check_looks(false)
  set_view_app(fn(root) {
    old(root, layer(0, None)).over(Is(true)) |> ignore
    old(root, layer(1, Some((0.0, 0.0)))).over(Is(true)) |> ignore
    old(root, layer(2, Some((200.0, 600.0)))).over(Is(true)) |> ignore
  })
  t.draw()
  t.drawn_now()
  { t, builds, taps }
}

///|
test "window tree: old views one over another: a press on the page's button builds the page alone" {
  let w = layers()
  let b0 = w.builds.copy()
  tree_tap(w.t, 50.0, 50.0)
  assert_eq(w.taps, [0, 1, 0])
  assert_true(w.builds[1] > b0[1])
  assert_eq((w.builds[0], w.builds[2]), (b0[0], b0[2]))
}

///|
test "window tree: old views one over another: a press on the top one's button builds that one alone" {
  let w = layers()
  let b0 = w.builds.copy()
  tree_tap(w.t, 250.0, 650.0)
  assert_eq(w.taps, [0, 0, 1])
  assert_true(w.builds[2] > b0[2])
  assert_eq((w.builds[0], w.builds[1]), (b0[0], b0[1]))
}

///|
test "window tree: old views one over another: held on the page's button, let go over the top one's: the page's alone" {
  let w = layers()
  let b0 = w.builds.copy()
  finger(0, 50.0, 50.0)
  w.t.drawn_now()
  finger(1, 250.0, 650.0)
  w.t.drawn_now()
  finger(2, 250.0, 650.0)
  w.t.drawn_now()
  // (let go off it: no press of the page's; none of the top one's, which it was never held by)
  assert_eq(w.taps, [0, 0, 0])
  assert_eq((w.builds[0], w.builds[2]), (b0[0], b0[2]))
}
