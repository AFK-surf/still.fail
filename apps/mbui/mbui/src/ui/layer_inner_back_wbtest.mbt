// What an old layer holds that takes back (its own take_back) said after the layer's own: back
// goes a step in it first, the layer open still; nothing in it taking back, the next closes the layer.

///|
/// An old view the whole window, a modal layer "外" over it while open (closed by back), holding what takes back while
/// `inner` is on: its own take_back ("内", turning itself off); where `base`, the view's own take_back under it ("底页").
/// What was closed, in turn.
fn inner_back_tester(base? : Bool = false) -> (Tester, Array[String], @signals.Signal[Bool]) {
  let closed : Array[String] = []
  let outer = @signals.signal(true)
  let inner = @signals.signal(true)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.grow(Is(1.0)) |> ignore
      old(h, fn(c) {
        if base {
          c.take_back(fn() { closed.push("底页") })
        }
        guard outer.get() else { return }
        let o = c.overlay("外", modal=true, outside=false, fn() {
          if inner.get() {
            c.take_back(fn() {
              closed.push("内")
              inner.set(false)
            })
          }
          c.box(w=Px(400.0), h=Px(300.0), bg=0xFFFFFFFFL, fn() {  }) |> ignore
        })
        if o.dismissed is Some(_) {
          closed.push("外")
          outer.set(false)
        }
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, closed, outer)
}

///|
test "an old layer with its own take_back said in it: back takes that, the layer open; the next back closes the layer" {
  let (t, closed, outer) = inner_back_tester()
  on_back(2, 0.0, 1.0, 0)
  t.draw()
  let first = (closed.copy(), outer.get())
  on_back(2, 0.0, 1.0, 0)
  t.draw()
  assert_eq((first, closed, outer.get()), ((["内"], true), ["内", "外"], false))
}

///|
test "an old layer with its own take_back said in it over the view's own: Escape closes the layer; no frame drawn, back is the view's, nothing of the layer's done" {
  let (t, closed, outer) = inner_back_tester(base=true)
  // (Escape, no frame drawn after it)
  t.key_told(key_escape, 0, t.time())
  on_back(2, 0.0, 1.0, 0)
  let at_once = closed.copy()
  t.draw()
  assert_eq((at_once, outer.get()), (["底页"], false), msg="\{closed}")
}
