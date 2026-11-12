// A picture of a chat's page made as nodes, out of sight at its foot, scrolled into sight: its block made as it comes
// into sight, its decode asked for by what draws the page as it comes to its node (View::image_ready asks for none),
// the picture brushed in as its host says it is decoded; as when the block asked for it as it was made (the same
// frames, presented one by one, with and without that change).

///|
/// A notch of the wheel, up the chat.
let pictures_notch : Double = -200.0

///|
/// How long the test looks after each notch: its glide over, a picture's reveal (@sf.reveal_ms) not yet.
let pictures_notch_ms : Double = 400.0

///|
/// The picture `src` as drawn in the last frame (its rect and opacity), none where it is not.
fn picture_drawn(t : @ui.Tester, src : String) -> (Double, Double, Double, Double, Double)? {
  for a in t.drawn_instances() {
    if a[5] == 4.0 && t.image_src(a[20].to_int()) == src {
      return Some((a[0], a[1], a[2], a[3], a[11]))
    }
  }
  None
}

///|
/// How many decodes of `bytes` bytes handed over the host was asked for so far.
fn pictures_asked(t : @ui.Tester, bytes : Int) -> Int {
  t.image_loads().filter(fn(l) { l.0 == "bytes:\{bytes}" }).length()
}

///|
test "a picture of a chat's page made as nodes, out of sight at its foot on a phone, scrolled into sight: nothing asked of it till then, its decode asked once, the picture still brushing in 400 ms after the notch that brought it" {
  // (home-after.png, its bytes as the fixture hands them over)
  let (src, bytes) = ("mem:fixture/home-after.png", 31398)
  let t = chat_pictures_open(390.0, 844.0, "compact", false, true)
  assert_eq(picture_drawn(t, src), None)
  assert_eq(pictures_asked(t, bytes), 0)
  // (notch by notch, each looked at once its glide is over)
  let first : Ref[(Double, Double)?] = Ref(None)
  let look = fn() {
    if first.val is None {
      match picture_drawn(t, src) {
        Some((_, _, w, h, _)) => first.val = Some((w, h))
        None => ()
      }
    }
  }
  for _ in 0..<60 {
    t.wheel(195.0, 420.0, pictures_notch)
    t.run_for(pictures_notch_ms)
    look()
    if first.val is Some(_) {
      break
    }
  }
  guard first.val is Some((w, h)) else { fail("\{src} never scrolled into sight") }
  assert_eq(pictures_asked(t, bytes), 1)
  // (its reveal under way then: grown, coming to its own size)
  t.run_for(@sf.reveal_ms)
  guard picture_drawn(t, src) is Some((_, _, rw, rh, _)) else { fail("\{src} gone from sight") }
  assert_true(w > rw && h > rh, msg="as it first shows \{Repr((w, h))}, at rest \{Repr((rw, rh))}")
}
