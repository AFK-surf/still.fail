// Picking a passage of a message (pick.mbt, MessagePick.kt), over the made-up chat. The fake host has no word
// boundaries of its own: a Han character is a word, letters and digits together are one.

///|
/// The finger held still on `words` a long press's time (and a little more), then let go there; where it was.
fn hold_on(t : @ui.Tester, words : String) -> (Double, Double) {
  // near the start of its first line (the message's words run on past it)
  let (rx, ry, _, _) = t.rect_of(words).unwrap()
  let (x, y) = (rx + 24.0, ry + 8.0)
  t.press_at(x, y)
  t.frame(ms=250.0)
  t.frame(ms=250.0)
  t.release(x, y)
  t.settle(unsettled_ok=true) |> ignore
  (x, y)
}

///|
/// A finger already down moved from (x0, y0) to (x1, y1) in `steps` moves, a frame apart.
fn slide(t : @ui.Tester, x0 : Double, y0 : Double, x1 : Double, y1 : Double, steps : Int) -> Unit {
  for i in 1..=steps {
    let k = i.to_double() / steps.to_double()
    t.move(x0 + (x1 - x0) * k, y0 + (y1 - y0) * k)
  }
}

///|
test "held still on a message's words: the word under the finger is picked, the bar over it" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  assert_true(pk.ts != "")
  assert_eq(pk.b - pk.a, 1)
  assert_true(t.find("引用") is Some(_))
  assert_true(t.find("复制") is Some(_))
  assert_true(t.find("全选") is Some(_))
  // the passage drawn behind the words, in the accent at 26%
  let ground = @sf.alpha(@sf.theme().p.accent, 0.26)
  assert_true(t.drawn_rects().iter().any(fn(r) { r.4 == ground }))
}

///|
test "a finger sliding on widens it by words, from the word first held; the list holds still" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  let (rx, ry, _, _) = t.rect_of("做完了：列表、跳到最新的按钮").unwrap()
  let (x, y) = (rx + 24.0, ry + 8.0)
  let before = t.list_offset()
  t.press_at(x, y)
  t.frame(ms=250.0)
  t.frame(ms=250.0)
  let first = (pk.a, pk.b)
  slide(t, x, y, x + 60.0, y, 6)
  t.release(x + 60.0, y)
  t.settle() |> ignore
  assert_eq(pk.a, first.0)
  assert_true(pk.b > first.1 + 2)
  assert_eq(t.list_offset(), before)
  // lifting it tapped nothing: still picked
  assert_true(pk.ts != "")
}

///|
test "复制 puts the passage on the clipboard and lets go; 全选 takes all of the message" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  let one = t.ctx().words_of(pk.key).unwrap().slice(pk.a, pk.b)
  t.tap_text("复制")
  assert_eq(t.clipboard(), one)
  assert_eq(pk.ts, "")
  assert_true(t.find("已复制") is Some(_))
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  t.tap_text("全选")
  assert_true(t.find("全选") is None)
  t.tap_text("复制")
  assert_true(t.clipboard().has_prefix("做完了：列表、跳到最新的按钮"))
}

///|
test "a handle moves its end: the passage's end follows the finger" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  let w = t.ctx().words_of(pk.key).unwrap()
  let lines = w.rects(pk.a, pk.b)
  let last = lines[lines.length() - 1]
  // the end's knob is under the line's end
  let (kx, ky) = (last.0 + last.2, last.1 + last.3 + 6.0)
  let was = pk.b
  t.press_at(kx, ky)
  slide(t, kx, ky, kx + 50.0, ky, 5)
  t.release(kx + 50.0, ky)
  t.settle() |> ignore
  assert_true(pk.b > was + 2)
  assert_true(pk.ts != "")
}

///|
test "a tap anywhere else lets go of it, as back does" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  t.tap(195.0, 300.0)
  assert_eq(pk.ts, "")
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  t.back()
  t.settle(unsettled_ok=true) |> ignore
  assert_eq(pk.ts, "")
  // the chat is still the page shown (back let go of the pick only)
  assert_eq(app.nav.depth(), 2)
}
