// What is leaving kept till a move it holds is over (View::moved_by's `holds_leaving`): its end the move's, as that move
// says it at the size it is laid out, not a length said as it was shown.

///|
/// How long what is shown takes to leave by itself (its fade): shorter than any sheet's sinking here.
let fade_ms : Double = 100.0

///|
/// How long a sheet's sinking takes for each point of its height.
let sink_ms_per_point : Double = 2.0

///|
/// A layer shown while `on()`, leaving over fade_ms, holding a sheet `height()` tall that sinks away by its own height
/// from the moment `sinks_from` says (none: at rest), over sink_ms_per_point a point of its height; its move holding
/// the layer's leaving (`holds`) or not. The tree, the layer.
fn sinking(
  on : @signals.Signal[Bool],
  height : @signals.Signal[Double],
  sinks_from : @signals.Signal[Double?],
  holds : Bool,
) -> (@view.Tree, Ref[@view.View?]) {
  let layer : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.show(
      fn() { on.get() },
      fn(l) {
        layer.val = Some(l)
        l.box(fn(s) {
          s
          .width(Is(Some(100.0)))
          .height(By(fn() { Some(height.get()) }))
          .moved_by(
            fn(_, h, t) {
              match sinks_from.get() {
                None => (0.0, 0.0)
                Some(t0) => {
                  let ms = h * sink_ms_per_point
                  let gone = if ms <= 0.0 || t - t0 >= ms { 1.0 } else { (t - t0) / ms }
                  (0.0, h * gone)
                }
              }
            },
            fn(_, h) {
              match sinks_from.get() {
                None => 0.0
                Some(t0) => t0 + h * sink_ms_per_point
              }
            },
            holds_leaving=holds,
          )
          |> ignore
        })
        |> ignore
      },
      leave=fade_ms,
    )
  })
  (tree, layer)
}

///|
test "a layer leaving holding a sheet whose sinking holds it: let go as the sheet has sunk, as long as its own height takes" {
  for tall in [100.0, 200.0] {
    let on = @signals.signal(true, same=fn(a, b) { a == b })
    let height = @signals.signal(tall, same=fn(a, b) { a == b })
    let sinks_from : @signals.Signal[Double?] = @signals.signal(None)
    let (tree, layer) = sinking(on, height, sinks_from, true)
    tree.frame(390.0, 844.0) |> ignore
    let l = layer.val.unwrap()
    let sunk = tall * sink_ms_per_point
    // (closed, sinking from now: its end the sheet's, not the fade's)
    sinks_from.set(Some(tree.logic_at()))
    on.set(false)
    tree.frame(390.0, 844.0) |> ignore
    assert_true(l.leaving())
    assert_eq(l.leaves_at(), sunk, msg="its end, \{tall} tall")
    assert_eq(tree.wake(), Some(sunk))
    // (past its own fade, still there, sinking)
    tree.at(fade_ms + (sunk - fade_ms) / 2.0)
    tree.frame(390.0, 844.0) |> ignore
    assert_true(l.alive(), msg="kept past its fade, \{tall} tall")
    // (sunk: let go then, nothing more woken for)
    tree.at(sunk)
    tree.frame(390.0, 844.0) |> ignore
    assert_false(l.alive(), msg="let go as it has sunk, \{tall} tall")
    assert_eq(tree.wake(), None)
    assert_false(tree.clock_read())
  }
}

///|
test "a layer leaving holding a sheet whose sinking holds it not: let go as its own leaving ends" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let height = @signals.signal(100.0, same=fn(a, b) { a == b })
  let sinks_from : @signals.Signal[Double?] = @signals.signal(None)
  let (tree, layer) = sinking(on, height, sinks_from, false)
  tree.frame(390.0, 844.0) |> ignore
  let l = layer.val.unwrap()
  sinks_from.set(Some(tree.logic_at()))
  on.set(false)
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(tree.wake(), Some(fade_ms))
  tree.at(fade_ms)
  tree.frame(390.0, 844.0) |> ignore
  assert_false(l.alive())
}

///|
test "a layer leaving all at once, its leaving's end worked out at its moment: let go as the sheet has sunk, whatever frames come between" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let height = @signals.signal(200.0, same=fn(a, b) { a == b })
  let sinks_from : @signals.Signal[Double?] = @signals.signal(None)
  let (tree, layer) = sinking(on, height, sinks_from, true)
  tree.frame(390.0, 844.0) |> ignore
  let l = layer.val.unwrap()
  let sunk = 200.0 * sink_ms_per_point
  sinks_from.set(Some(tree.logic_at()))
  on.set(false)
  // (no frame till past its fade: still there; then sunk)
  tree.at(fade_ms + (sunk - fade_ms) / 2.0)
  tree.frame(390.0, 844.0) |> ignore
  assert_true(l.alive())
  tree.at(sunk)
  tree.frame(390.0, 844.0) |> ignore
  assert_false(l.alive())
}
