// What only a look of the library's parts moves (a button's ground under the pointer, words' ink, a dialog dimmed over
// itself as another comes over it) is read as each frame is painted: told as the part is built, nothing built again
// for it while it goes.

///|
/// The frames after the one now, to `until` (each the next one a motion asks for), what each was built for (none where
/// it was painted alone), and `seen` read off each. The frame after one that laid out otherwise is built once more for
/// that, as the frame after any such build is (frame_watch.mbt): that one is not said.
fn[T : Eq] painted_until(t : @ui.Tester, until : Double, seen : () -> T) -> (Array[String], Array[T]) {
  let built : Array[String] = []
  let got : Array[T] = []
  let mut first = true
  while t.time() < until {
    let w = t.wanted_after()
    if w == @double.infinity {
      break
    }
    t.frame_at(if w <= t.time() { t.next_frame_time() } else { t.display_frame(w) })
    let why = t.built_why()
    if why != "" && !(first && why == "the one before it laid out otherwise") {
      built.push("\{t.time()}: \{why}")
    }
    first = false
    let s = seen()
    if !got.contains(s) {
      got.push(s)
    }
  }
  (built, got)
}

///|
test "a button the pointer comes onto: its ground eases to the hover's as each frame is painted, nothing built for it" {
  let t = @ui.Tester::new(
    fn(c) {
      c.box(w=Px(300.0), h=Px(200.0), align=AStart, fn() { button(c, "Join", key="b") |> ignore }) |> ignore
    },
    w=400.0,
    h=300.0,
  )
  t.check_looks(false)
  t.draw()
  let ground = fn() { t.drawn_rects()[0].4 }
  let (x, y) = {
    let r = t.drawn_rects()[0]
    (r.0 + r.2 / 2.0, r.1 + r.3 / 2.0)
  }
  let rest = ground()
  // (the pointer come onto it: built for that, its ground told to go to the hover's)
  t.move_to(x, y)
  let (built, grounds) = painted_until(t, t.time() + dur_ms, ground)
  // (it eases, through colours between, to the one under the hand)
  assert_true(grounds.length() > 3 && !grounds.contains(rest), msg="\{Repr(grounds)}")
  assert_eq(built, [], msg="\{built.length()} frames built: \{Repr(built)}")
}

///|
test "a dialog with another come over it: dimmed over itself as each frame is painted, nothing built for its dimming" {
  let covered = @signals.signal(false, same=fn(a, b) { a == b })
  let veil = @motion.Anim::new(0.0)
  let t = @ui.Tester::new(
    fn(c) {
      // (as the presenters tell it: by its cause, the one over it opened)
      if covered.get() && veil.target() != 1.0 {
        veil.animate(c, 1.0, @motion.tween(confirm_ground_ms, ease=Out))
      }
      dialog(c, "d", true, "标题", fn() { c.text("内容") |> ignore }, veil~) |> ignore
    },
    w=800.0,
    h=600.0,
  )
  t.check_looks(false)
  t.draw()
  // (in, to its way in's end: no motion of its own left; its fade and its move set off the frame after it was first
  // built, as an old view's motion is)
  let in_rest = t.rest_of("dialog/")
  assert_true(in_rest > t.time(), msg="\{Repr(t.moving())}")
  t.run_for(in_rest - t.time())
  let before = t.drawn_rects()
  // what is drawn that was not before, seen through: its veil, as dark as it has come (not what else is drawn anew
  // once its layer is built, solid or clear: the dialog's white, none at all)
  let see_through = fn(c : Int64) { (c & 0xFFL) > 0L && (c & 0xFFL) < 0xFFL }
  let veiled = fn() { t.drawn_rects().filter(fn(r) { !before.contains(r) && see_through(r.4) }).map(fn(r) { r.4 }) }
  // (the one over it opened: built for that, its veil told to come)
  covered.set(true)
  t.draw()
  let (built, veils) = painted_until(t, t.time() + confirm_ground_ms, veiled)
  // (its veil coming, one ground over it, darker frame by frame)
  let one = veils.iter().all(fn(v) { v.length() == 1 && v[0] >> 8 == veils[0][0] >> 8 })
  let darker = one && Array::makei(veils.length(), fn(k) { k == 0 || (veils[k - 1][0] & 0xFFL) < (veils[k][0] & 0xFFL) })
  .iter()
  .all(fn(b) { b })
  assert_true(veils.length() > 3 && darker, msg="\{Repr(veils)}")
  assert_eq(built, [], msg="\{built.length()} frames built: \{Repr(built)}")
}

///|
/// The colour (r, g, b, a: 0 … 1 each, as drawn) of every glyph of words drawn in the last frame (instance kinds 1 and 7: not a colour emoji).
fn glyph_inks(t : @ui.Tester) -> Array[Array[Double]] {
  t.drawn_instances().filter(fn(i) { i[5] == 1.0 || i[5] == 7.0 }).map(fn(i) { [i[8], i[9], i[10], i[11]] })
}

///|
/// `c` as a glyph of it is drawn whole (r, g, b, a: 0 … 1 each).
fn ink_drawn(c : Int64) -> Array[Double] {
  [24, 16, 8, 0].map(fn(s) { ((c >> s) & 0xFFL).to_double() / 255.0 })
}

///|
test "words to press the pointer comes onto (忽略): their ink mixed from the quiet one to the words' as each frame is painted, nothing built for it" {
  // (how far it is lit, read off the motion its words' ink follows: the same key, told the same)
  let lit : Ref[@motion.Anim?] = Ref(None)
  let t = @ui.Tester::new(
    fn(c) {
      c.box(w=Px(300.0), h=Px(200.0), align=AStart, fn() { ask_line_button(c, "忽略", key="k", mark=20.0) }) |> ignore
      let id = c.id("k")
      lit.val = Some(
        @motion.told(c, "sf-ask-line-btn/\{id}", if c.lit(id) || c.pressed(id) { 1.0 } else { 0.0 }, spec=@motion.tween(dur_ms, ease=Out)),
      )
    },
    w=400.0,
    h=300.0,
  )
  t.check_looks(false)
  t.draw()
  let (text, muted) = (theme().p.text, theme().p.muted)
  assert_true(glyph_inks(t).length() > 0 && glyph_inks(t).iter().all(fn(g) { g == ink_drawn(muted) }), msg="\{Repr(glyph_inks(t))}")
  let (x, y) = match t.rect_of("忽略") {
    Some(r) => (r.0 + r.2 / 2.0, r.1 + r.3 / 2.0)
    None => fail("no 忽略")
  }
  t.move_to(x, y)
  // each frame: how far it is lit, and whether every glyph is drawn in the mix of the two inks that far (as one ink
  // mixed, whole: nothing under it showing through)
  let (built, seen) = painted_until(t, t.time() + dur_ms, fn() {
    let k = lit.val.unwrap().get(t.ctx())
    (k, glyph_inks(t).iter().all(fn(g) { g == ink_drawn(mix(text, k, muted)) }))
  })
  assert_true(seen.iter().all(fn(s) { s.1 }), msg="\{Repr(seen)} \{Repr(glyph_inks(t))}")
  // (part way: inks between the two, more than a few)
  assert_true(seen.filter(fn(s) { s.0 > 0.0 && s.0 < 1.0 }).length() > 3, msg="\{Repr(seen)}")
  assert_eq(built, [], msg="\{built.length()} frames built: \{Repr(built)}")
}
