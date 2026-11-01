// The library's button as a node of the window's tree (button_node) and the keyboard, as the old one (button): Tab goes
// to it, Enter and Space press it, once each; at work or unable to be pressed, it takes the focus no more.

///|
/// A button node "按钮" at the window's top left (presses counted in `pressed`), at work while `busy`, unable while
/// `off`; a node before it taking the focus, "别处".
fn button_focus_case(pressed : Ref[Int], busy : @signals.Signal[Bool], off : @signals.Signal[Bool]) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
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
    button_node(root, fn() { "按钮" }, fn() { pressed.val += 1 }, busy=fn() { busy.get() }, disabled=fn() { off.get() })
    |> ignore
  })
  t.draw()
  t
}

///|
test "the button as a node: Tab goes to it from what is before it; Enter presses it once, Space once more" {
  let pressed = Ref(0)
  let t = button_focus_case(pressed, @signals.signal(false), @signals.signal(false))
  t.act(Button, Focus, label="别处")
  t.tab()
  let focused = t.focused().map(fn(s) { s.label })
  t.enter()
  let entered = pressed.val
  t.key(@ui.key_space)
  assert_eq((focused, entered, pressed.val), (Some("按钮"), 1, 2))
}

///|
test "the button as a node with the focus set to work, or unable to be pressed: the focus let go of it, Tab passing it" {
  let got = []
  for which in [0, 1] {
    let (busy, off) = (@signals.signal(false), @signals.signal(false))
    let pressed = Ref(0)
    let t = button_focus_case(pressed, busy, off)
    t.act(Button, Focus, label="别处")
    t.tab()
    let had = t.focused().map(fn(s) { s.label })
    if which == 0 {
      busy.set(true)
    } else {
      off.set(true)
    }
    // (at that cause, no frame drawn)
    let lost = t.focused().map(fn(s) { s.label })
    t.draw()
    t.act(Button, Focus, label="别处")
    t.tab()
    t.enter()
    got.push((had, lost, t.focused().map(fn(s) { s.label }) != Some("按钮"), pressed.val))
  }
  assert_eq(got, [(Some("按钮"), None, true, 0), (Some("按钮"), None, true, 0)])
}
