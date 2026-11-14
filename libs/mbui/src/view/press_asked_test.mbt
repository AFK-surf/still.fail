// A node pressed by what is no press delivered to it (View::press: a gesture of its own that ends in one, a moment):
// taken as a delivered one is, so none where the hand's would be none.

///|
test "View::press: its on_press done as a delivered press's is; none while it or what holds it is said to take none, in its bones, under a modal layer that does not hold it, leaving, or let go" {
  let now = Ref(0.0)
  let flag = fn(v : Bool) { @signals.signal(v, same=fn(a : Bool, b : Bool) { a == b }) }
  let (own, holder, modal, there) = (flag(true), flag(true), flag(false), flag(true))
  let bones = @signals.signal(0L, same=fn(a, b) { a == b })
  let pressed = Ref(0)
  let node : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(h) {
        h.presses(By(fn() { holder.get() })).bones(By(fn() { bones.get() })) |> ignore
        h.show(at_once=true, fn() { there.get() }, leave=200.0, fn(b) {
          node.val = Some(b)
          b
          .width(Is(Some(100.0)))
          .height(Is(Some(40.0)))
          .presses(By(fn() { own.get() }))
          .on_press(fn() { pressed.val += 1 })
          |> ignore
        })
      })
      |> ignore
      root.box(fn(m) { m.over(Is(true)).modal(By(fn() { modal.get() })) |> ignore }) |> ignore
    },
    time=fn() { now.val },
  )
  let frame = fn() {
    now.val += 16.0
    tree.frame(300.0, 400.0, now=now.val) |> ignore
  }
  frame()
  let b = node.val.unwrap()
  // (each: what keeps the hand from it said, a frame, asked; then taken back, a frame, asked)
  let got : Array[(Bool, Bool)] = []
  let asked = fn(off : () -> Unit, on : () -> Unit) {
    off()
    frame()
    let kept = b.press()
    on()
    frame()
    got.push((kept, b.press()))
  }
  let first = b.press()
  asked(fn() { own.set(false) }, fn() { own.set(true) })
  asked(fn() { holder.set(false) }, fn() { holder.set(true) })
  asked(fn() { bones.set(0x808080FFL) }, fn() { bones.set(0L) })
  asked(fn() { modal.set(true) }, fn() { modal.set(false) })
  // (leaving: none; come back as it leaves, pressed again; gone, none)
  asked(fn() { there.set(false) }, fn() { there.set(true) })
  there.set(false)
  now.val += 400.0
  tree.frame(300.0, 400.0, now=now.val) |> ignore
  assert_eq(
    (first, got, b.alive(), b.press(), pressed.val),
    (true, [(false, true), (false, true), (false, true), (false, true), (false, true)], false, false, 6),
  )
}
