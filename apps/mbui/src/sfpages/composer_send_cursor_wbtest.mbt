// The send button's pointer and action, inside the same focusable composer ground in either rendering.

///|
fn composer_send_cursor_probe(node : Bool, ready : Bool) -> (String, Bool, Int, Int) raise {
  @sfbase.reset()
  composing_reset()
  @sf.set_words(@sfbase.fill)
  let cap_clicks = Ref(0)
  let sends = Ref(0)
  let t = @ui.Tester::new(fn(c) {
    @sf.begin(c) |> ignore
    if !node {
      let cap = c.id("cursor-composer")
      c.cursor(cap, IBeam)
      if c.clicked(cap) { cap_clicks.val += 1 }
      c.box(w=Px(120.0), h=Px(60.0), id=cap, fn() {
        send_button(c, ready, false, fn() { sends.val += 1 }) |> ignore
      }) |> ignore
    }
  }, w=120.0, h=60.0, platform=0)
  if node {
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      root.box(fn(cap) {
        cap.width(Is(Some(120.0))).height(Is(Some(60.0)))
        .on_press(fn() { cap_clicks.val += 1 }).cursor(Is(Some(IBeam))) |> ignore
        @sf.composer_send_node(cap, fn() { ready }, fn() { false }, fn() { sends.val += 1 }) |> ignore
      }) |> ignore
    })
  }
  t.draw()
  let said = t.get(Button, label=@sf.t("web-main.composer.send"))
  let (x, y, w, h) = said.rect
  t.move(x + w / 2.0, y + h / 2.0)
  t.draw()
  let shape = "\{t.cursor()}"
  t.tap(x + w / 2.0, y + h / 2.0)
  t.draw()
  (shape, said.disabled, sends.val, cap_clicks.val)
}

///|
test "a disabled send button owns the pointer without becoming an action" {
  let old = composer_send_cursor_probe(false, false)
  let node = composer_send_cursor_probe(true, false)
  println("SENDCURSOR old=\{old} node=\{node}")
  assert_eq((old.0, old.1, old.2), ("Arrow", true, 0), msg="the old disabled button")
  assert_eq(node, old, msg="the disabled tree button has the same pointer and action")
}

///|
test "an enabled send button owns the pointer and sends" {
  let old = composer_send_cursor_probe(false, true)
  let node = composer_send_cursor_probe(true, true)
  assert_eq((old.0, old.1, old.2), ("Hand", false, 1), msg="the old enabled button")
  assert_eq(node, old, msg="the enabled tree button has the same pointer and action")
}

///|
test "the send button answers a screen reader only when there is something to send" {
  @sfbase.reset()
  composing_reset()
  @sf.set_words(@sfbase.fill)
  let ready = @signals.signal(false)
  let sends = Ref(0)
  let send : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=120.0, h=60.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    send.val = Some(@sf.composer_send_node(root, fn() { ready.get() }, fn() { false }, fn() { sends.val += 1 }))
  })
  t.draw()
  let tree = @ui.view_tree().unwrap()
  let id = send.val.unwrap().id()
  let disabled = fn() { tree.said_order().iter().find_first(fn(s) { s.id == id }).map(fn(s) { s.disabled }) }
  assert_eq(disabled(), Some(true))
  assert_false(tree.activate_at(id, t.time()), msg="a screen reader cannot activate an empty send button")
  assert_eq(sends.val, 0)
  ready.set(true)
  t.draw()
  assert_eq(disabled(), Some(false))
  assert_true(tree.activate_at(id, t.time()), msg="a screen reader can send once the button is ready")
  assert_eq(sends.val, 1)
}
