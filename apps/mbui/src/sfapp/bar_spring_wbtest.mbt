// The bar's notch on its way, drawn as each frame is painted (bar.mbt: bar_drawn reads what goes in the phase that draws
// it): back from a chat laid out Small, the bar comes back and its notch opens (a chat's page offers no action, the
// chats' 令), after the stack's slide is over the only thing that moves. Each frame draws the notch, the discs in it
// and the places beside it where the notch has them then, nothing of the bar built or laid out again for it; a place
// pressed where it is drawn then is that place; and each frame painted so is the frame built whole (the Tester's
// looks_check, on wherever nothing is counted).

///|
/// The fixture's chat open laid out Small with a finger, gone back from (the system's back): the notch opening from
/// then, the display's frames on.
fn bar_backed() -> @ui.Tester raise {
  let t = tape_chat(2, 390.0, 844.0)
  assert_eq(bar.k.to, 0.0)
  t.set_frame_period(t.frame_period())
  t.back()
  assert_eq(bar.k.to, 1.0)
  t
}

///|
/// The fixture's chat open laid out Small with a finger, gone back from: drawn on to the end of the stack's slide (the
/// slide across the window), the display's frames from then on.
fn bar_back() -> @ui.Tester raise {
  let t = tape_chat(2, 390.0, 844.0)
  // (a chat's page: the bar gone, its notch closed)
  assert_eq(bar.k.to, 0.0)
  t.back()
  t.run_for(@ui.move_ms(390.0))
  t.set_frame_period(t.frame_period())
  // (the notch still opening, for a few frames more at least)
  assert_true(bar.k.to == 1.0 && bar.k.end() > t.time() + t.frame_period() * 4.0, msg="\{bar.k.end()} \{t.time()}")
  t
}

///|
/// The notch the last frame drew in the bar's glass (Tester::drawn_notches: the frosted glass's, its circle's middle
/// below its top and its radius), (0, 0) none.
fn glass_notch(t : @ui.Tester) -> (Double, Double) {
  for n in t.drawn_notches() {
    if n.0 == 5 {
      return (n.2, n.3)
    }
  }
  (0.0, 0.0)
}

///|
/// The notch with it `k` open, as the bar draws it: where its circle's middle is below the glass's top, its radius.
fn notch_of(k : Double) -> (Double, Double) {
  (-lift * k, (drop / 2.0 + notch_gap) * k)
}

///|
/// Where the bar's place `key` is at the last frame, across, in the window: where it is said to be (its middle), where
/// its icon is drawn (the middle of the shapes drawn across its room, at or below it, in a place's inks, dim or lit: not
/// what slides under it; the bar coming up drawn lower than it is laid out), and where the notch as it is at the frame's moment has it (bar_centres, in the bar's frame 22 in).
fn place_across(t : @ui.Tester, key : String) -> (Double, Double, Double) raise {
  let told = bar.told.unwrap()
  let items = told.sets[told.cur]
  let j = items.search(key).unwrap()
  let (x, y, w, _) = said_at(t, place_label(key)).unwrap()
  let mut lo = @double.infinity
  let mut hi = -@double.infinity
  for s in t.drawn_shapes() {
    let (cx, cy) = (s.0 + s.2 / 2.0, s.1 + s.3 / 2.0)
    let ink = s.5 >> 8
    if cx >= x && cx <= x + w && cy >= y && (ink == 0x6B7280L || ink == 0x111827L) {
      lo = dmin(lo, s.0)
      hi = dmax(hi, s.0 + s.2)
    }
  }
  assert_true(hi > lo, msg="no icon drawn in \{key}'s room")
  (x + w / 2.0, (lo + hi) / 2.0, 22.0 + bar_centres(told.width, bar.k_at(t.time()), items.length())[j])
}

///|
test "bar: back from a chat, the notch opening frame by frame: drawn where it is then, nothing of the bar built or laid out for it" {
  let t = bar_back()
  // (counted: each frame as it is drawn, none built whole beside it)
  t.check_looks(false)
  // (two frames after the stack's slide: built whole for what came from outside as it ended (an old view's watch told,
  // what it told outside), on main as on this; the bar not among them)
  t.frame_at(t.next_frame_time())
  let warm1 = "\{t.frame_perf().nodes} \{t.built_why()}"
  t.frame_at(t.next_frame_time())
  let warm2 = "\{t.frame_perf().nodes} \{t.built_why()}"
  let first = glass_notch(t)
  t.frame_at(t.next_frame_time())
  let p1 = t.frame_perf()
  let why1 = t.built_why()
  let second = glass_notch(t)
  let at = t.time()
  t.frame_at(t.next_frame_time())
  let p2 = t.frame_perf()
  let third = glass_notch(t)
  t.check_looks(true)
  // it moves: the notch drawn where it is at each frame's moment
  assert_true(first != second && second != third, msg="\{first} \{second} \{third}")
  let (cy, r) = notch_of(bar.k_at(at))
  assert_eq(second, (cy, r))
  // and nothing of the bar is built or laid out for it
  assert_eq((p1.nodes, p1.laid, p2.nodes, p2.laid), (0, 0, 0, 0), msg="before: \{warm1} / \{warm2}; counted: \{p1} \{why1} / \{p2} \{t.built_why()}")
}

///|
test "bar: the notch opening, each frame painted so is the frame built whole; the places drawn and read out where it has them" {
  let t = bar_backed()
  // (the bar coming up from below the window: its places in it from the third frame on)
  t.frame_at(t.next_frame_time())
  t.frame_at(t.next_frame_time())
  t.frame_at(t.next_frame_time())
  let one = place_across(t, "files")
  t.frame_at(t.next_frame_time())
  let two = place_across(t, "files")
  // its icon drawn where the notch has it at each frame, moving with it (on the device's pixels: half a point at the
  // Tester's scale of 2; the icon's drawing as off its middle at both), and read out there
  let off = one.1 - one.2
  assert_true(one.1 != two.1 && off.abs() <= 2.0 && (two.1 - two.2 - off).abs() <= 0.5, msg="\{one} \{two}")
  assert_true((one.0 - one.2).abs() <= 0.5 && (two.0 - two.2).abs() <= 0.5, msg="\{one} \{two}")
  // to its end, each frame compared with the frame built whole (looks_check)
  t.run_for(bar_rest() - t.time())
  assert_eq(glass_notch(t), notch_of(1.0))
}

///|
test "bar: a place pressed where it is drawn as the notch opens is that place" {
  let t = bar_back()
  t.frame_at(t.next_frame_time())
  // (where its icon is drawn then, the middle of its row)
  let (_, drawn, _) = place_across(t, "files")
  let (_, y, _, h) = said_at(t, place_label("files")).unwrap()
  t.tap(drawn, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Files)
}
