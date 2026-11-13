// The window's tree walked to what holds an old view (Tree::laid_held_hosted) only where something it is worked out of
// changed: a frame an old view builds with the tree as it was walks none of it; one after a change to the tree walks it
// once. That what is kept is what would be worked out anew, frame by frame, is the Tester's look's (tester_corners.mbt),
// on in every Tester: each frame below is held to it too.

///|
test "corners kept: a frame an old view builds with the window's tree unchanged walks none of the tree; one after a node of it sized, placed otherwise (as big or not), said as round otherwise, made, let go or said to take no press walks it once; each frame what holds the old view fades on a way walks it" {
  // (its changes made at once by the test, no motion of theirs: not judged frame to frame, sizes_steady.mbt)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0, corners_held=false, words_over_held=false)
  // (what the old view alone reads, the tree nothing of it)
  let tick = @signals.signal(0)
  let builds = Ref(0)
  let wide = @signals.signal(200.0)
  let pad = @signals.signal(6.0)
  let more = @signals.signal(false)
  let presses = @signals.signal(true)
  // (how far in what holds the card holds it, that as big as the window: the card placed lower, as big)
  let above = @signals.signal(0.0)
  // (how round the card says it is: what the old view's box said Inner is worked out against)
  let round = @signals.signal(20.0)
  // (when the card's way out is over, none yet: as opaque as its way has it as it is drawn, View::drawn_while)
  let fade_end = @signals.signal(-1.0)
  let fade_ms = 200.0
  set_view_app(fn(root) {
    root.box(fn(wrap) {
      wrap.width(Is(Some(400.0))).height(Is(Some(300.0))).pad(By(fn() { above.get() })) |> ignore
      wrap.box(fn(card) {
        card
        .width(By(fn() { Some(wide.get()) }))
        .pad(By(fn() { pad.get() }))
        .ground(Is(0x333333FFL))
        .radius(By(fn() { round.get() }))
        .alpha(By(fn() {
          let end = fade_end.get()
          if end < 0.0 {
            1.0
          } else {
            let at = card.drawn_while(fn(now) { now < end })
            if at >= end {
              0.0
            } else {
              (end - at) / fade_ms
            }
          }
        }))
        .presses(By(fn() { presses.get() }))
        .says(Is(Some(@view.said(Button, label="卡片"))))
        .on_press(fn() {  })
        |> ignore
        card.box(fn(v) {
          v.height(Is(Some(108.0))) |> ignore
          old(v, fn(c) {
            ignore(tick.get())
            builds.val += 1
            c.box(style=style(w=Full, h=Full, radius=Inner), bg=0x55AA77FFL, fn() {  }) |> ignore
          }).grow(Is(1.0))
          |> ignore
        })
        |> ignore
        card.show(fn() { more.get() }, fn(v) { v.height(Is(Some(20.0))).ground(Is(0xEEEEEEFFL)) |> ignore }, at_once=true)
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let tree = view_tree().unwrap()
  // (what `change` does, then the old view built again in a frame: how many times the tree was walked in it, and
  // whether the old view was built)
  let step = fn(change : () -> Unit) -> (Int, Bool) {
    let walked = tree.held_walked()
    let built = builds.val
    change()
    tick.set(tick.get() + 1)
    t.frame()
    (tree.held_walked() - walked, builds.val > built)
  }
  // (the frame after the tree was first drawn places a node of it once more (Tree::places_rev): walked then, as told)
  ignore(step(fn() {  }))
  let steps = [
    ("unchanged", step(fn() {  })),
    ("sized", step(fn() { wide.set(240.0) })),
    ("unchanged after", step(fn() {  })),
    ("placed otherwise", step(fn() { pad.set(10.0) })),
    ("placed lower, as big", step(fn() { above.set(30.0) })),
    ("as round otherwise", step(fn() { round.set(8.0) })),
    ("unchanged after", step(fn() {  })),
    ("another made", step(fn() { more.set(true) })),
    ("unchanged after", step(fn() {  })),
    ("one let go", step(fn() { more.set(false) })),
    ("a press said on one found", step(fn() { presses.set(false) })),
    ("unchanged at last", step(fn() {  })),
  ]
  assert_eq(steps, [
    ("unchanged", (0, true)),
    ("sized", (1, true)),
    ("unchanged after", (0, true)),
    ("placed otherwise", (1, true)),
    ("placed lower, as big", (1, true)),
    ("as round otherwise", (1, true)),
    ("unchanged after", (0, true)),
    ("another made", (1, true)),
    ("unchanged after", (0, true)),
    ("one let go", (1, true)),
    ("a press said on one found", (1, true)),
    ("unchanged at last", (0, true)),
  ])
  // What holds the old view going out on a way, the old view built each frame: nothing of what is kept is worked out by
  // the clock (a flight's place apart, never kept), so each frame of the way places the card as opaque as it is then
  // (Tree::place, counted) and walks the tree; the look holds each to what is worked out anew, through the frame the
  // card is no container of the box any more (as good as unseen). Once the way is over, none.
  let end = t.time() + fade_ms
  assert_eq(step(fn() { fade_end.set(end) }), (1, true))
  let mut going = 1
  while t.time() < end {
    assert_eq(step(fn() {  }), (1, true))
    going += 1
  }
  assert_true(going > 3)
  assert_eq(step(fn() {  }), (0, true))
}
