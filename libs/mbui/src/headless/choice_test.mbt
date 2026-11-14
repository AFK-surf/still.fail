// The headless choice (@headless.choice), under a look of the tests' own: found a button or a radio by its name,
// selected or not as its caller says; chosen by the pointer, by Enter and Space, by a screen reader's ask; disabled,
// none of these. Each window is made by `window` (window_test.mbt), which holds that the choice's own file draws and
// lays out nothing.

///|
struct ChoiceCase {
  t : @ui.Tester
  chosen_at : Array[Int]
  off : @signals.Signal[Bool]
}

///|
fn choice_case(kind? : @headless.ChoiceKind = Button) -> ChoiceCase raise {
  let chosen_at : Array[Int] = []
  let picked = @signals.signal(0, same=fn(a : Int, b : Int) { a == b })
  let off = @signals.signal(false, same=fn(a : Bool, b : Bool) { a == b })
  let t = window(fn(root) {
    for i, name in ["浅色", "深色"] {
      let idx = i
      let label = name
      @headless.choice(
        root,
        kind,
        fn() { label },
        fn() { picked.get() == idx },
        fn(_) {
          chosen_at.push(idx)
          picked.set(idx)
        },
        fn(v, s) {
          v
          .width(Is(Some(120.0)))
          .height(Is(Some(40.0)))
          .ground(By(fn() { if s.chosen() { c_pressed } else { c_rest } }))
          |> ignore
        },
        disabled=fn() { idx == 1 && off.get() },
      )
      |> ignore
    }
  })
  { t, chosen_at, off }
}

///|
test "a button choice is read out a button with selected true on the chosen one; clicking another chooses it" {
  let k = choice_case()
  let s0 = k.t.get(Button, label="浅色")
  let s1 = k.t.get(Button, label="深色")
  k.t.click(Button, label="深色")
  assert_eq(
    (
      s0.selected,
      s1.selected,
      k.t.get(Button, label="浅色").selected,
      k.t.get(Button, label="深色").selected,
      k.chosen_at,
    ),
    (Some(true), Some(false), Some(false), Some(true), [1]),
  )
}

///|
test "a radio choice is read out a radio with selected; disabled choice takes no press" {
  let k = choice_case(kind=Radio)
  k.off.set(true)
  k.t.frame()
  let s1 = k.t.get(Radio, label="深色")
  let (x, y, w, h) = s1.rect
  k.t.tap(x + w / 2.0, y + h / 2.0)
  assert_eq((k.t.get(Radio, label="浅色").selected, s1.disabled, k.chosen_at), (Some(true), true, []))
}
