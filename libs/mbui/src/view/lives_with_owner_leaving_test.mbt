// What lives with a node held elsewhere (View::lives_with: a tip, a row's menu in a layer over the window) as that node
// leaves down a column on a Move: out of sight and out of reach from the moment it starts leaving, not as it is let go;
// back as it is called back before it has gone; let go with it.

///|
/// A layer over all of it holding a box (旁, 50 by 20 at its top left, pressed into `pressed`) that lives with the box
/// `owner` in what `here` shows down a column; `kept` that box.
fn owner_leaving_tree(here : @signals.Signal[Bool], pressed : Ref[Int], kept : Ref[@view.View?]) -> @view.Tree {
  @view.Tree::new(fn(root) {
    let layer = root.box(fn(l) { l.over(Is(true)) |> ignore })
    root.box(fn(col) {
      col.box(fn(b) { b.height(Is(Some(30.0))).words(Is("上")) |> ignore }) |> ignore
      col.show(fn() { here.get() }, fn(a) {
        a.box(fn(owner) {
          owner.height(Is(Some(40.0))).words(Is("甲")) |> ignore
          kept.val = Some(
            layer
            .box(fn(k) {
              k
              .width(Is(Some(50.0)))
              .height(Is(Some(20.0)))
              .words(Is("旁"))
              .presses(Is(true))
              .on_press(fn() { pressed.val += 1 })
              |> ignore
            })
            .lives_with(owner),
          )
        })
        |> ignore
      })
      col.box(fn(b) { b.height(Is(Some(30.0))).words(Is("下")) |> ignore }) |> ignore
    })
    |> ignore
  })
}

///|
fn owner_drawn(t : @view.Tree, words : String) -> Bool {
  t.drawn().iter().any(fn(d) { d.words == words })
}

///|
test "what lives with a node leaving on a Move: out of sight and out of reach as it starts leaving, kept till it is let go, then let go" {
  let here = @signals.signal(true, same=fn(a, b) { a == b })
  let pressed = Ref(0)
  let kept : Ref[@view.View?] = Ref(None)
  let t = owner_leaving_tree(here, pressed, kept)
  t.frame(390.0, 844.0, now=0.0) |> ignore
  assert_true(owner_drawn(t, "旁") && t.press(10.0, 10.0), msg="there, pressed")
  here.set(false)
  t.frame(390.0, 844.0, now=16.0) |> ignore
  assert_true(owner_drawn(t, "甲"), msg="its owner still drawn as it leaves")
  assert_false(owner_drawn(t, "旁"), msg="out of sight as its owner starts leaving")
  assert_false(t.press(10.0, 10.0), msg="out of reach as its owner starts leaving")
  assert_true(kept.val.unwrap().alive(), msg="kept till its owner is let go")
  t.frame(390.0, 844.0, now=600.0) |> ignore
  assert_eq((owner_drawn(t, "甲"), kept.val.unwrap().alive(), pressed.val), (false, false, 1))
}

///|
test "what lives with a node called back as it leaves: back in sight and in reach" {
  let here = @signals.signal(true, same=fn(a, b) { a == b })
  let pressed = Ref(0)
  let kept : Ref[@view.View?] = Ref(None)
  let t = owner_leaving_tree(here, pressed, kept)
  t.frame(390.0, 844.0, now=0.0) |> ignore
  here.set(false)
  t.frame(390.0, 844.0, now=16.0) |> ignore
  assert_false(owner_drawn(t, "旁"), msg="out of sight as its owner starts leaving")
  here.set(true)
  t.frame(390.0, 844.0, now=48.0) |> ignore
  assert_true(owner_drawn(t, "旁") && t.press(10.0, 10.0), msg="back, pressed")
  assert_eq((kept.val.unwrap().alive(), pressed.val), (true, 1))
}

///|
test "what lives with a node, over all of its layer (a tip's holder), what it shows in it: called back as it leaves, back in sight; shown again then" {
  let here = @signals.signal(true, same=fn(a, b) { a == b })
  let open = @signals.signal(true, same=fn(a, b) { a == b })
  let t = @view.Tree::new(fn(root) {
    let layer = root.box(fn(l) { l.over(Is(true)) |> ignore })
    root.box(fn(col) {
      col.box(fn(b) { b.height(Is(Some(30.0))).words(Is("上")) |> ignore }) |> ignore
      col.show(fn() { here.get() }, fn(owner) {
        owner.height(Is(Some(40.0))).words(Is("甲")) |> ignore
        layer
        .box(fn(h) { h.over(Is(true)) |> ignore })
        .lives_with(owner)
        .show(fn() { open.get() }, leave=150.0, fn(k) { k.width(Is(Some(50.0))).height(Is(Some(20.0))).words(Is("旁")) |> ignore })
      })
      col.box(fn(b) { b.height(Is(Some(30.0))).words(Is("下")) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.frame(390.0, 844.0, now=0.0) |> ignore
  assert_true(owner_drawn(t, "旁"), msg="there")
  here.set(false)
  t.frame(390.0, 844.0, now=16.0) |> ignore
  assert_false(owner_drawn(t, "旁"), msg="out of sight as its owner starts leaving")
  here.set(true)
  t.frame(390.0, 844.0, now=48.0) |> ignore
  assert_true(owner_drawn(t, "旁"), msg="back as its owner is called back")
  open.set(false)
  t.frame(390.0, 844.0, now=64.0) |> ignore
  t.frame(390.0, 844.0, now=600.0) |> ignore
  assert_false(owner_drawn(t, "旁"), msg="closed")
  open.set(true)
  t.frame(390.0, 844.0, now=616.0) |> ignore
  t.frame(390.0, 844.0, now=1000.0) |> ignore
  assert_true(owner_drawn(t, "旁"), msg="shown again")
}
