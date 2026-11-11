// View::grows_now: how tall a node is laid out at a change's moment and how fast that height goes then, of the layout
// itself (laid out at that moment and a little after). What it says against the frames drawn about that moment, for
// what the layout makes of ways on their way (a column's sum, a row's tallest, a most holding it, a group under way,
// a binding following a way); and that asking it leaves no trace.

///|
/// What is asked of: `inside` built in a box (the one asked of) over 下; `change` set at 100, `ask` at moment `at`.
/// Where 下 is drawn at `at` and a ms either side, the frames drawn only there; and, in a tree of its own, what
/// grows_now says at `at` (asked in an event then).
fn gn_case(inside : (@view.View, @signals.Signal[Bool]) -> Unit, at : Double) -> ((Double, Double), (Double, Double)) {
  let make = fn() {
    let on = @signals.signal(false, same=fn(a, b) { a == b })
    let held : Ref[@view.View?] = Ref(None)
    let t = @view.Tree::new(fn(root) {
      root.box(fn(b) {
        held.val = Some(b)
        inside(b, on)
      })
      |> ignore
      root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
    })
    t.frame(390.0, 844.0) |> ignore
    t.event(100.0, fn() { on.set(true) })
    (t, held)
  }
  let (t, _) = make()
  let y = fn(ms : Double) {
    t.at(ms)
    t.frame(390.0, 844.0) |> ignore
    cg_drawn(t, "下").0
  }
  let before = y(at - 1.0)
  let here = y(at)
  let after = y(at + 1.0)
  let (u, held) = make()
  let said = Ref((0.0, 0.0))
  u.event(at, fn() { said.val = held.val.unwrap().grows_now() })
  ((said.val.0, said.val.1), (here, (after - before) / 2.0))
}

///|
test "grows_now: as tall as laid out and as fast as the frames about that moment go, whatever the layout makes of the ways" {
  let cases : Array[(String, (@view.View, @signals.Signal[Bool]) -> Unit)] = [
    ("a column, a show opening", fn(b, on) {
      b.box(fn(x) { x.height(Is(Some(30.0))) |> ignore }) |> ignore
      b.show(fn() { on.get() }, fn(s) { s.height(Is(Some(120.0))) |> ignore })
    }),
    ("a row, its tallest a column opening", fn(b, on) {
      b.box(fn(r) {
        r.row(Is(true)) |> ignore
        r.box(fn(x) { x.width(Is(Some(50.0))).height(Is(Some(40.0))) |> ignore }) |> ignore
        r.box(fn(c) { c.show(fn() { on.get() }, fn(s) { s.height(Is(Some(90.0))) |> ignore }) }) |> ignore
      })
      |> ignore
    }),
    ("held to a most", fn(b, on) {
      b.max_height(Is(Some(70.0))).clips(Is(true)) |> ignore
      b.show(fn() { on.get() }, fn(s) { s.height(Is(Some(200.0))) |> ignore })
    }),
    ("two in one way, one going as the other comes", fn(b, on) {
      b.show(fn() { !on.get() }, fn(s) { s.height(Is(Some(44.0))) |> ignore })
      b.show(fn() { on.get() }, fn(s) { s.height(Is(Some(71.1))) |> ignore })
    }),
  ]
  for c in cases {
    let (name, inside) = c
    for at in [101.0, 130.0, 200.0, 320.0] {
      let ((h, v), (y, fd)) = gn_case(inside, at)
      // (下 under it: as tall as it is laid out then)
      assert_true((h - y).abs() < 1.0e-6, msg="\{name} at \{at}: \{h} laid, 下 at \{y}")
      assert_true((v - fd).abs() < 2.0e-3, msg="\{name} at \{at}: \{v} said, \{fd} by the frames")
    }
  }
}

///|
test "grows_now asked leaves no trace: every frame after the same as where it was not asked, whatever frames are drawn" {
  let run = fn(ask : Bool, step : Double) -> Array[(String, Double, Double)] {
    let on = @signals.signal(false, same=fn(a, b) { a == b })
    let held : Ref[@view.View?] = Ref(None)
    let t = @view.Tree::new(fn(root) {
      root.box(fn(b) {
        held.val = Some(b)
        b.box(fn(x) { x.height(Is(Some(30.0))).words(Is("上")) |> ignore }) |> ignore
        b.show(fn() { on.get() }, fn(s) { s.height(Is(Some(120.0))).words(Is("开")) |> ignore })
      })
      |> ignore
      root.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
    })
    t.frame(390.0, 844.0) |> ignore
    t.event(100.0, fn() { on.set(true) })
    let out = []
    let mut f = 0
    let mut at = 100.0
    let mut asked = false
    while at <= 100.0 + @flex.move_most_ms {
      if ask && !asked && at >= 160.0 {
        asked = true
        t.event(160.0, fn() { held.val.unwrap().grows_now() |> ignore })
      }
      t.at(at)
      t.frame(390.0, 844.0) |> ignore
      for d in t.drawn() {
        out.push((d.words, d.y, d.h))
      }
      f = f + 1
      at = 100.0 + f.to_double() * step
    }
    out
  }
  for step in [1000.0 / 60.0, 1000.0 / 120.0, 1000.0 / 24.0, 1000.0 / 7.0] {
    assert_eq(run(true, step), run(false, step), msg="\{step}")
  }
}
