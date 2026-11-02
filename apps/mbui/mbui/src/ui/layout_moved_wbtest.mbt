// What a node holds moved to another node and back (the first built in a scope of its own is who it is wherever what
// holds it is: Ctx::node_known), laid out where it stands now: the one holding it laid out anew, not as it was laid out
// the last time it held it (@flex's compute: a node moved under another parent dirties both).

///|
test "a box whose scope's first box was held by another box while it was not built: laid out as tall as what it holds now" {
  let phase = @signals.signal(0)
  let t = Tester::new(
    fn(c) {
      // (the scope's first box, holding a box `h` high)
      let inner = fn(h : Double) {
        c.scope(7, fn() { c.box(fn() { c.box(h=Px(h), fn() {  }) |> ignore }) |> ignore })
      }
      match phase.get() {
        // (the second box under the root holds it, tall; then the first holds it, short, the second not built; then the
        // second again, the same box, holding it short)
        1 => c.box(bg=0x112233FFL, fn() { inner(36.0) }) |> ignore
        p => {
          c.box(fn() {  }) |> ignore
          c.box(bg=0x445566FFL, fn() { inner(if p == 0 { 594.0 } else { 36.0 }) }) |> ignore
        }
      }
    },
    w=300.0,
    h=800.0,
  )
  t.draw()
  let tall = fn(ink : Int64) {
    match t.drawn_rects().iter().find_first(fn(r) { r.4 == ink }) {
      Some(r) => r.3
      None => -1.0
    }
  }
  assert_eq(tall(0x445566FFL), 594.0)
  phase.set(1)
  t.draw()
  assert_eq(tall(0x112233FFL), 36.0)
  phase.set(2)
  t.draw()
  assert_eq(tall(0x445566FFL), 36.0)
}
