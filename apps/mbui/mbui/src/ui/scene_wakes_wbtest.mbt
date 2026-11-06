// The moments the window's tree's layers wait for (scene_wake_said, Ctx::scene_wakes): each layer's its own, let go of
// as it is drawn anew and asked again by what it draws then, kept where it is not drawn anew, let go of with the layer,
// and none of them asked or let go of by a check's drawing of the frame (scene_unrecorded).

///|
/// What one host frame of `waiting` showed as it was drawn: its moment, whether it was asked for, whether it changed,
/// and the words of each counting view in it ("" where it shows none).
priv struct Waited {
  at : Double
  asked : Bool
  changed : Bool
  a : String
  c : String
  d : String
} derive(Eq, Show, Debug)

///|
/// When `waiting` told each change from outside, between frames: the word changed (three times), the view waiting for
/// two moments drawn with nothing more, the one waiting for one let go of.
priv struct Told {
  words : Array[Double]
  c_done : Double
  d_gone : Double
} derive(Show)

///|
/// The moments `waiting` tells its changes at, from its start: each told between the frames round it.
let told_word_ms : Array[Double] = [90.0, 190.0, 440.0]

///|
let told_c_done_ms : Double = 690.0

///|
let told_d_gone_ms : Double = 760.0

///|
/// A window whose tree holds four old views: `a` counting every 300 ms; `c` counting every 300 ms and every 470 ms (one
/// layer waiting for two moments), till it draws nothing more (drawn anew, no longer waiting); `d` counting every
/// 250 ms, till its old view is let go of, its node gone from the tree (the layer gone); one saying a word, changed
/// now and then (a layer drawn anew between). Each display frame `period` ms apart for 1000 ms, as a host draws them,
/// each checked (`checked`) or not, taken as it is drawn: when it began, when each change was told, and each frame
/// with what it showed then.
fn waiting(period : Double, checked : Bool) -> (Double, Told, Array[Waited]) raise {
  let word = @signals.signal("b0")
  let c_drawn = @signals.signal(true)
  let d_kept = @signals.signal(true, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=300.0, h=240.0)
  set_view_app(fn(root) {
    root.box(fn(c) {
      c.box(fn(h) {
        h.offset(Is((10.0, 10.0))) |> ignore
        old(h, fn(c) { c.text("a \{c.every(300.0)}") |> ignore }) |> ignore
      })
      |> ignore
      c.box(fn(h) {
        h.offset(Is((10.0, 50.0))) |> ignore
        old(h, fn(c) { if c_drawn.get() { c.text("c \{c.every(300.0)} \{c.every(470.0)}") |> ignore } }) |> ignore
      })
      |> ignore
      c.box(fn(h) {
        h.offset(Is((10.0, 100.0))) |> ignore
        h.show(fn() { d_kept.get() }, fn(slot) {
          old(slot, fn(c) { c.text("d \{c.every(250.0)}") |> ignore }) |> ignore
        })
      })
      |> ignore
      c.box(fn(h) {
        h.offset(Is((10.0, 150.0))) |> ignore
        old(h, fn(c) { c.text(word.get()) |> ignore }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.set_frame_period(period)
  t.check_looks(checked)
  let start = t.time()
  t.record_host()
  let shown = fn(prefix : String) {
    match t.words().filter(fn(w) { w.0.has_prefix(prefix) }) {
      [w, ..] => w.0
      [] => ""
    }
  }
  let words = []
  let mut c_done = -1.0
  let mut d_gone = -1.0
  let seen = []
  while t.time() < start + 1000.0 - 1.0e-9 {
    // (each change told once its moment is past, between this frame and the next)
    let at = t.time() - start
    if words.length() < told_word_ms.length() && at >= told_word_ms[words.length()] {
      word.set("b\{words.length() + 1}")
      words.push(t.time())
    }
    if c_done < 0.0 && at >= told_c_done_ms {
      c_drawn.set(false)
      c_done = t.time()
    }
    if d_gone < 0.0 && at >= told_d_gone_ms {
      d_kept.set(false)
      d_gone = t.time()
    }
    // (one display frame, taken as it is drawn: what it showed is its own, not a later frame's)
    t.run_as_host(period)
    let frames = t.host_frames()
    assert_eq(frames.length(), 1, msg="at \{t.time()}: \{frames}")
    let f = frames[0]
    // (each one's words as drawn: d's gone in the frame its layer went in, drawn by the window's tree alone, though its
    // old view's nodes stay in the old frame till that is built again: Tester::words_marked)
    seen.push({
      at: f.at,
      asked: f.asked,
      changed: f.changed,
      a: shown("a "),
      c: shown("c "),
      d: shown("d "),
    })
  }
  (start, { words, c_done, d_gone }, seen)
}

///|
test "layers waiting for moments, one for two, one drawn anew with nothing more, one let go of, another drawn anew between: each frame shows each count as at its moment, asked for at each step and at none past the last; the same checked or not, at 60 Hz and 120 Hz" {
  let count = fn(at : Double, period : Double) { periods_at(at, 0.0, period).0 }
  for period in [1000.0 / 60.0, 1000.0 / 120.0] {
    let (start, told, checked) = waiting(period, true)
    let (_, _, unchecked) = waiting(period, false)
    let parted = []
    for i, f in checked {
      if i < unchecked.length() && f != unchecked[i] && parted.length() < 4 {
        parted.push((f, unchecked[i]))
      }
    }
    assert_eq(checked, unchecked, msg="at \{period}, \{checked.length()} and \{unchecked.length()} frames, part at \{parted}")
    let mut before = start
    for f in checked {
      let msg = "at \{period}, told \{told}: \{f}"
      // (c drawn, and d there, in the frames before each was told: from the next, neither)
      let c_shown = f.at < told.c_done + 1.0e-9
      let d_shown = f.at < told.d_gone + 1.0e-9
      assert_eq(f.a, "a \{count(f.at, 300.0)}", msg~)
      assert_eq(f.c, if c_shown { "c \{count(f.at, 300.0)} \{count(f.at, 470.0)}" } else { "" }, msg~)
      assert_eq(f.d, if d_shown { "d \{count(f.at, 250.0)}" } else { "" }, msg~)
      // (asked for at a step since the frame before of a count it shows, and at a change told since it: at no other)
      let before_at = before
      let stepped = fn(p : Double) { count(f.at, p) != count(before_at, p) }
      let steps = stepped(300.0) || (c_shown && stepped(470.0)) || (d_shown && stepped(250.0))
      let came = (told.words + [told.c_done, told.d_gone]).iter().any(fn(w) { w > before_at - 1.0e-9 && w < f.at })
      assert_eq(f.asked, steps || came, msg~)
      before = f.at
    }
    // (a step of c's and one of d's come in the run after each was let go: what the frames there, none asked for by
    // them, show)
    let end = checked[checked.length() - 1].at
    let next_step = fn(after : Double, p : Double) { periods_at(after, 0.0, p).1 }
    assert_true(next_step(told.c_done, 470.0) <= end && next_step(told.d_gone, 250.0) <= end, msg="at \{period}: \{told}, to \{end}")
  }
}
