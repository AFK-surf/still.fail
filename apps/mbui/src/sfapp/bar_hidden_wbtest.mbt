///|
test "a hidden bar does not rebuild as its unseen motions finish, and works when shown again" {
  let (t, _) = bar_at_rest()
  t.keep_parts(true)
  t.check_looks(false)
  t.set_frame_period(host_phone_period)
  // Switching place swaps the notch's icon. A page opened at once hides the bar before that swap and the notch end.
  let place = bar_place_with("plus")
  assert_true(@sfbase.go_place(place))
  t.frame_at(t.next_frame_time())
  app.nav.push(Settings)
  t.frame_at(t.next_frame_time())
  let hidden_at = bar.vis.end()
  assert_true(bar.vis.target == 0.0 && bar.icon_swap.end() > hidden_at, msg="the bar is hidden before its icon settles")
  let motions_end = bar_rest()
  assert_true(motions_end > hidden_at, msg="a bar motion remains after it is hidden")
  ignore(host_frames_till(t, t.display_frame(hidden_at)))
  if t.time() < hidden_at { t.frame_at(t.display_frame(hidden_at)) }
  assert_true(bar.vis.at(t.time()).0 <= 0.0 && bar.told.map(fn(x) { x.shown }) == Some(false))
  t.record_host()
  let (_, built) = steps_built(t, motions_end - t.time() + 2.0 * host_phone_period)
  let bar_builds = built.filter(fn(why) { why.contains("part kept at src/sfapp/bar.mbt") })
  assert_eq(bar_builds, [], msg="an unseen bar must not build for its own motion ending")
  // Returning to the place shows a live bar with its current state; it still takes a place press.
  t.back()
  t.frame_at(t.next_frame_time())
  assert_true(bar.told.map(fn(x) { x.shown }) == Some(true), msg="the bar is shown on return")
  ignore(host_frames_till(t, t.time() + @ui.move_most_ms))
  let (xs, y) = bar_places_at()
  t.tap(xs[0], y)
  t.frame_at(t.next_frame_time())
  assert_true(bar.told.map(fn(x) { x.active }) == Some(Some("chats")), msg="the returned bar takes a place press")
}
