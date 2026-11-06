// Focus carried across a structural replacement must not take focus back after another decision.

///|
fn focus_return_fixture() -> (@view.Tree, @signals.Signal[Int], Map[String, @view.View]) {
  let which = @signals.signal(0)
  let nodes : Map[String, @view.View] = Map([])
  let tree = @view.Tree::new(fn(root) {
    root.pick(fn() { which.get() }, fn(v, n) {
      nodes[if n == 0 { "before" } else { "after" }] = v
      v.width(Is(Some(30.0))).height(Is(Some(30.0))).focusable(Is(true)) |> ignore
    })
    root.box(fn(v) {
      nodes["outside"] = v
      v.width(Is(Some(30.0))).height(Is(Some(30.0))).focusable(Is(true)) |> ignore
    }) |> ignore
    root.box(fn(v) {
      nodes["disabled"] = v
      v.width(Is(Some(30.0))).height(Is(Some(30.0))).focusable(Is(false)) |> ignore
    }) |> ignore
  }, time=fn() { 0.0 })
  tree.frame(400.0, 400.0) |> ignore
  (tree, which, nodes)
}

///|
test "focus return survives a replacement once, preserving the visible focus" {
  let (tree, which, nodes) = focus_return_fixture()
  assert_true(nodes["before"].focus_return() is None)
  assert_true(tree.focus_to(Some(nodes["before"].id()), visible=true))
  let back = nodes["before"].focus_return().unwrap()
  tree.event(10.0, fn() { which.set(1) })
  tree.frame(400.0, 400.0, now=10.0) |> ignore
  assert_true(back.valid())
  assert_true(back.give(nodes["after"]))
  assert_eq(tree.focused_now(), (Some(nodes["after"].id()), true))
  assert_false(back.give(nodes["after"]))
}

///|
test "focus return expires on another focus or an explicit request for none" {
  for change in ["outside", "none"] {
    let (tree, which, nodes) = focus_return_fixture()
    assert_true(tree.focus_to(Some(nodes["before"].id())))
    let back = nodes["before"].focus_return().unwrap()
    tree.event(10.0, fn() { which.set(1) })
    tree.frame(400.0, 400.0, now=10.0) |> ignore
    if change == "outside" {
      assert_true(tree.focus_to(Some(nodes["outside"].id())))
    }
    assert_true(tree.focus_to(None))
    assert_false(back.give(nodes["after"]), msg=change)
    assert_eq(tree.focused_now(), (None, false), msg=change)
  }
}

///|
test "focus return refuses disabled, off-screen and foreign controls" {
  let (tree, which, nodes) = focus_return_fixture()
  let (_, _, other) = focus_return_fixture()
  assert_true(tree.focus_to(Some(nodes["before"].id())))
  let back = nodes["before"].focus_return().unwrap()
  tree.event(10.0, fn() { which.set(1) })
  tree.frame(400.0, 400.0, now=10.0) |> ignore
  assert_false(back.give(nodes["disabled"]))
  assert_false(back.give(other["before"]))
  nodes["after"].offset(Is((500.0, 0.0))) |> ignore
  tree.frame(400.0, 400.0, now=10.0) |> ignore
  assert_false(back.give(nodes["after"]))
  assert_eq(tree.focused_now(), (None, false))
  nodes["after"].offset(Is((0.0, 0.0))) |> ignore
  tree.frame(400.0, 400.0, now=10.0) |> ignore
  assert_true(back.give(nodes["after"]))
}

///|
test "focus return does not capture a focused control outside the last laid out window" {
  let (tree, _, nodes) = focus_return_fixture()
  let before = nodes["before"]
  assert_true(tree.focus_to(Some(before.id())))
  let back = before.focus_return().unwrap()
  assert_true(back.valid())
  before.offset(Is((500.0, 0.0))) |> ignore
  tree.frame(400.0, 400.0, now=10.0) |> ignore
  assert_eq(tree.focused_now().0, Some(before.id()))
  assert_false(back.valid())
  assert_true(before.focus_return() is None)
}

///|
test "focus return does not capture a focused control outside its clip" {
  let nodes : Map[String, @view.View] = Map([])
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(clip) {
      clip.width(Is(Some(100.0))).height(Is(Some(100.0))).clips(Is(true)) |> ignore
      clip.box(fn(button) {
        button.width(Is(Some(30.0))).height(Is(Some(30.0))).focusable(Is(true)) |> ignore
        nodes["button"] = button
      }) |> ignore
    }) |> ignore
  }, time=fn() { 0.0 })
  tree.frame(400.0, 400.0) |> ignore
  let button = nodes["button"]
  assert_true(tree.focus_to(Some(button.id())))
  let back = button.focus_return().unwrap()
  button.offset(Is((120.0, 0.0))) |> ignore
  tree.frame(400.0, 400.0, now=10.0) |> ignore
  assert_eq(tree.focused_now().0, Some(button.id()))
  assert_false(back.valid())
  assert_true(button.focus_return() is None)
}

///|
test "focus return expires when its source loses input, even if it later takes input again" {
  for cause in ["disabled", "no presses", "bones", "modal"] {
    let which = @signals.signal(0)
    let enabled = @signals.signal(true)
    let presses = @signals.signal(true)
    let bones = @signals.signal(false)
    let modal = @signals.signal(false)
    let nodes : Map[String, @view.View] = Map([])
    let tree = @view.Tree::new(fn(root) {
      root.pick(fn() { which.get() }, fn(holder, n) {
        holder.presses(By(fn() { presses.get() })).bones(By(fn() { if bones.get() { 1L } else { 0L } })) |> ignore
        holder.box(fn(button) {
          button.width(Is(Some(30.0))).height(Is(Some(30.0))).focusable(By(fn() { enabled.get() })) |> ignore
          nodes[if n == 0 { "before" } else { "after" }] = button
        }) |> ignore
      })
      root.box(fn(layer) { layer.over(Is(true)).modal(By(fn() { modal.get() })) |> ignore }) |> ignore
    }, time=fn() { 0.0 })
    tree.frame(400.0, 400.0) |> ignore
    assert_true(tree.focus_to(Some(nodes["before"].id())), msg=cause)
    let back = nodes["before"].focus_return().unwrap()
    tree.event(10.0, fn() {
      match cause {
        "disabled" => enabled.set(false)
        "no presses" => presses.set(false)
        "bones" => bones.set(true)
        _ => modal.set(true)
      }
    })
    assert_eq(tree.focused_now().0, None, msg=cause)
    assert_false(back.valid(), msg=cause)
    tree.event(20.0, fn() {
      enabled.set(true)
      presses.set(true)
      bones.set(false)
      modal.set(false)
    })
    assert_false(back.valid(), msg=cause)
    tree.event(30.0, fn() { which.set(1) })
    tree.frame(400.0, 400.0, now=30.0) |> ignore
    assert_false(back.valid(), msg=cause)
    assert_false(back.give(nodes["after"]), msg=cause)
  }
}
