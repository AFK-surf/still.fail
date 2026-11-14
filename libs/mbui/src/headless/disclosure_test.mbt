// The headless disclosure (@headless.disclosure), under a look of the tests' own: found a button by its name, expanded
// or not as its caller says; pressed by the pointer, by Enter and Space, by a screen reader's ask; disabled, none of
// these and the focus let go. Each window is made by `window` (window_test.mbt), which holds that the disclosure's own
// file draws and lays out nothing.

///|
struct DisclosureCase {
  t : @ui.Tester
  pressed : Ref[Int]
  state : Ref[@headless.Disclosure?]
  off : @signals.Signal[Bool]
}

///|
fn disclosure_case() -> DisclosureCase raise {
  let flag = fn(v : Bool) { @signals.signal(v, same=fn(a : Bool, b : Bool) { a == b }) }
  let (pressed, state) = (Ref(0), Ref(None))
  let (open, off) = (flag(false), flag(false))
  let t = window(fn(root) {
    root.box(fn(e) {
      e
      .width(Is(Some(50.0)))
      .height(Is(Some(50.0)))
      .presses(Is(true))
      .focusable(Is(true))
      .says(Is(Some(@view.said(Button, label="别处"))))
      .on_press(fn() {  })
      |> ignore
    })
    |> ignore
    @headless.disclosure(
      root,
      fn() { "更多" },
      fn() { open.get() },
      fn(_) {
        pressed.val += 1
        open.set(!open.untracked())
      },
      fn(v, s) {
        state.val = Some(s)
        v
        .width(Is(Some(120.0)))
        .height(Is(Some(40.0)))
        .ground(By(fn() {
          if s.disabled() {
            c_disabled
          } else if s.pressed() {
            c_pressed
          } else if s.focus_shown() {
            c_focus
          } else if s.hovered() {
            c_hovered
          } else {
            c_rest
          }
        }))
        |> ignore
      },
      disabled=fn() { off.get() },
    )
    |> ignore
  })
  { t, pressed, state, off }
}

///|
test "a disclosure is read out a button by its name, expanded false then true as its caller opens it" {
  let k = disclosure_case()
  let s0 = k.t.get(Button, label="更多")
  k.t.click(Button, label="更多")
  let s1 = k.t.get(Button, label="更多")
  assert_eq(
    (s0.expanded, s1.expanded, k.pressed.val, k.state.val.unwrap().open()),
    (Some(false), Some(true), 1, true),
  )
}

///|
test "a disclosure disabled: read out disabled, takes no press or focus" {
  let k = disclosure_case()
  k.off.set(true)
  k.t.frame()
  let s = k.t.get(Button, label="更多")
  let (x, y, w, h) = s.rect
  k.t.tap(x + w / 2.0, y + h / 2.0)
  k.state.val.unwrap().press()
  assert_eq((s.disabled, s.actions.contains(Activate), k.pressed.val), (true, false, 0))
}
