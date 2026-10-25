// What the hand changes (hand_moves.mbt): a look, never how big words are, nor how tall a thing it lights is or how
// far down it stands; across, a row may make room for what shows in it under the hand.

///|
/// A row 300 wide of words to press (`words` its words, as lit or not), and under it another to press; and, shown
/// under the hand only, `under_hand` at the first row's end.
fn hand_rows(words : (Ctx, Bool) -> Unit, under_hand? : (Ctx) -> Unit = fn(_) {  }) -> Tester {
  Tester::new(
    fn(c) {
      c.box(w=Px(300.0), fn() {
        let id = c.id("first")
        c.box(dir=Row, w=Fill(1.0), align=ACenter, gap=4.0, id~, fn() {
          words(c, c.lit(id))
          c.hand_shown(c.lit(id), fn() { under_hand(c) })
        })
        |> ignore
        c.box(w=Fill(1.0), id=c.id("second"), fn() { c.text("second", wrap=false) |> ignore }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=200.0,
  )
}

///|
test "the hand: words a size larger lit are a fault, said by them; their ink alone is none" {
  let t = hand_rows(fn(c, lit) { c.text("全部 1 个 · 在侧栏查看", size=if lit { 14.0 } else { 12.0 }, wrap=false) |> ignore })
  t.draw()
  let faults = t.hand_moves()
  assert_eq(faults.length(), 1, msg=faults.join("\n"))
  assert_true(faults[0].contains("「全部 1 个 · 在侧栏查看」"), msg=faults[0])
  let t = hand_rows(fn(c, lit) {
    c.text("全部 1 个 · 在侧栏查看", size=12.0, color=if lit { 0x000000FFL } else { 0x888888FFL }, wrap=false) |> ignore
  })
  t.draw()
  assert_eq(t.hand_moves(), [])
}

///|
test "the hand: what shows under it taller than its row's line makes the row taller, a fault; as tall, cutting the words shorter, none" {
  let title = fn(c : Ctx, _lit : Bool) { c.text("一个很长很长很长很长很长很长很长很长很长的标题", line=20.0, w=Fill(1.0), wrap=false) |> ignore }
  let t = hand_rows(title, under_hand=fn(c) { c.box(w=Px(40.0), h=Px(22.0), id=c.id("dismiss"), fn() {  }) |> ignore })
  t.draw()
  let faults = t.hand_moves()
  assert_eq(faults.length(), 1, msg=faults.join("\n"))
  assert_true(faults[0].contains("20 at rest") || faults[0].contains("×20 at rest"), msg=faults[0])
  let t = hand_rows(title, under_hand=fn(c) { c.box(w=Px(40.0), h=Px(18.0), id=c.id("dismiss"), fn() {  }) |> ignore })
  t.draw()
  assert_eq(t.hand_moves(), [])
}
