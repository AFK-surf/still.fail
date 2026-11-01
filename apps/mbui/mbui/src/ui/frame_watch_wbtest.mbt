// What a frame does again (frame_watch.mbt): built anew where what it read changed (a signal, the clock read as it was
// built, an input, a change the test made, a moment it waits for); where nothing did but its looks by the clock (what
// turns, steps or breathes), drawn from the last frame's instances, each look applied at the frame's time, nothing
// built. A Tester draws each frame of the looks alone whole as well and the two must be the same: that every test
// holds; these say when a frame is one.

///|
/// How long the mark's turn takes (looks_tester).
let looks_turn_ms : Double = 800.0

///|
/// How long after the view is first built what shows later shows (the last test's).
let looks_later_ms : Double = 500.0

///|
/// A mark turned by the clock beside a word (`resident`: on the resident clock's steps), the view's builds counted.
fn looks_tester(builds : Ref[Int], resident? : Bool = false) -> Tester {
  Tester::new(fn(c) {
    builds.val = builds.val + 1
    c.box(w=Fill(1.0), h=Fill(1.0), align=ACenter, justify=JCenter, fn() {
      c.text("waiting", size=12.0) |> ignore
      let mark = c.box(w=Px(20.0), h=Px(8.0), bg=0x3366CCFFL, fn() {  })
      c.cycle_look(mark, looks_turn_ms, fn(f) { look(rot=f * 6.283185307179586, alpha=0.5 + 0.5 * f) }, resident~)
    })
    |> ignore
  })
}

///|
test "a mark turning alone: its frames are of its look alone, each as the frame built whole draws it" {
  let builds = Ref(0)
  let t = looks_tester(builds)
  // (built whole once more: what it drew settled, the same twice)
  t.clock_frame()
  let was = looks_frames.val
  t.clock_frame()
  t.clock_frame(ms=looks_turn_ms / 4.0)
  // (each drawn whole as well and compared: looks_compare would have failed the test)
  assert_eq(looks_frames.val - was, 2)
  assert_eq(t.cycles().length(), 1)
}

///|
test "a mark turning alone, drawn as a host draws it: nothing is built for its frames, and where it is drawn turns" {
  let builds = Ref(0)
  let t = looks_tester(builds)
  t.check_looks(false)
  t.clock_frame()
  let built = builds.val
  let drawn = fn() {
    let c = g()
    let a = FixedArray::make(c.ninst * inst_size + 1, 0.0)
    c.inst.blit_to(a, len=c.ninst * inst_size)
    a
  }
  let a0 = drawn()
  t.clock_frame(ms=looks_turn_ms / 4.0)
  assert_eq(builds.val, built)
  assert_true(looks_drawn.val)
  let a1 = drawn()
  let mut differs = false
  for k in 0..<a0.length() {
    if a0[k] != a1[k] {
      differs = true
    }
  }
  assert_true(differs, msg="the mark drawn a quarter turn on as at the first")
}

///|
test "a mark turning on the resident clock: a frame of its look alone at each step, none between" {
  let builds = Ref(0)
  let t = looks_tester(builds, resident=true)
  t.check_looks(false)
  t.clock_frame()
  let built = builds.val
  let was = looks_frames.val
  t.clock_frame(ms=cycle_step_ms)
  t.clock_frame(ms=cycle_step_ms)
  assert_eq(builds.val, built)
  assert_eq(looks_frames.val - was, 2)
}

///|
test "a mark turning, then a tap: the frame after it is built whole, and those after it of the look alone again" {
  let builds = Ref(0)
  let t = looks_tester(builds)
  t.check_looks(false)
  t.clock_frame()
  t.clock_frame()
  assert_true(looks_drawn.val)
  let built = builds.val
  t.tap(10.0, 10.0)
  assert_true(builds.val > built)
  // (the input's frames drawn, what it changed late in the frame after: then the look alone again)
  t.run_for(looks_turn_ms)
  let settled = builds.val
  t.clock_frame(ms=looks_turn_ms / 4.0)
  assert_true(looks_drawn.val)
  assert_eq(builds.val, settled)
}

///|
test "a mark turning, then a change the test made: the frame that shows it is built whole" {
  let builds = Ref(0)
  let word = Ref("waiting")
  let t = Tester::new(fn(c) {
    builds.val = builds.val + 1
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      c.text(word.val, size=12.0) |> ignore
      let mark = c.box(w=Px(20.0), h=Px(8.0), bg=0x3366CCFFL, fn() {  })
      c.cycle_look(mark, looks_turn_ms, fn(f) { look(rot=f * 6.283185307179586) })
    })
    |> ignore
  })
  t.frame()
  t.frame()
  word.val = "done"
  t.draw()
  assert_true(t.find("done") is Some(_))
  assert_true(!looks_drawn.val)
}

///|
test "a wake asked as it was built: the frame at it is built whole, those before it of the look alone" {
  let builds = Ref(0)
  let shown = Ref(false)
  let from = Ref(-1.0)
  let t = Tester::new(fn(c) {
    builds.val = builds.val + 1
    if from.val < 0.0 {
      from.val = c.moment()
    }
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      // (what shows after a while: read as it is built, woken at its moment)
      if c.moment() - from.val >= looks_later_ms {
        shown.val = true
        c.text("later", size=12.0) |> ignore
      } else {
        c.wake_in(looks_later_ms - (c.moment() - from.val))
      }
      let mark = c.box(w=Px(20.0), h=Px(8.0), bg=0x3366CCFFL, fn() {  })
      c.cycle_look(mark, looks_turn_ms, fn(f) { look(rot=f * 6.283185307179586) })
    })
    |> ignore
  })
  t.check_looks(false)
  t.clock_frame()
  let built = builds.val
  t.clock_frame()
  assert_eq(builds.val, built)
  t.run_for(looks_later_ms)
  assert_true(shown.val)
  assert_true(t.find("later") is Some(_))
}

///|
/// A word read from `word` beside a mark turning, and `other` read by none; the view's builds counted.
fn signal_tester(builds : Ref[Int], word : @signals.Signal[String]) -> Tester {
  Tester::new(fn(c) {
    builds.val = builds.val + 1
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      c.text(word.get(), size=12.0) |> ignore
      let mark = c.box(w=Px(20.0), h=Px(8.0), bg=0x3366CCFFL, fn() {  })
      c.cycle_look(mark, looks_turn_ms, fn(f) { look(rot=f * 6.283185307179586) })
    })
    |> ignore
  })
}

///|
test "a signal the view read, set between frames: a frame asked for, built whole, showing it" {
  let builds = Ref(0)
  let word = @signals.signal("waiting")
  let t = signal_tester(builds, word)
  t.check_looks(false)
  t.clock_frame()
  let built = builds.val
  assert_true(!t.fake.wants)
  word.set("done")
  // (what read it, told: a frame owed)
  assert_true(t.fake.wants)
  t.clock_frame()
  assert_true(builds.val > built)
  assert_true(t.find("done") is Some(_))
}

///|
test "a signal the view did not read, set: the next frame is of the look alone" {
  let builds = Ref(0)
  let word = @signals.signal("waiting")
  let other = @signals.signal(0)
  let t = signal_tester(builds, word)
  t.check_looks(false)
  t.clock_frame()
  let built = builds.val
  other.set(1)
  t.clock_frame()
  assert_eq(builds.val, built)
  assert_true(looks_drawn.val)
}

///|
test "the clock read as the view is built: each frame built whole, said where it was read" {
  let builds = Ref(0)
  let t = Tester::new(fn(c) {
    builds.val = builds.val + 1
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      c.text("at \{c.now()}", size=12.0) |> ignore
      let mark = c.box(w=Px(20.0), h=Px(8.0), bg=0x3366CCFFL, fn() {  })
      c.cycle_look(mark, looks_turn_ms, fn(f) { look(rot=f * 6.283185307179586) })
    })
    |> ignore
  })
  t.clock_frame()
  let built = builds.val
  t.clock_frame()
  assert_true(builds.val > built)
  assert_true(t.built_why().contains("the clock read at"), msg=t.built_why())
}

///|
/// What moves for ever while a test reads it (frame_watch_wbtest's motions named): never at rest.
priv struct Endless {}

///|
impl Moving for Endless with rest_at(self, now, frame) {
  ignore((self, now, frame))
  @double.infinity
}

///|
/// Where it is called (a test's place, as the app's would be told).
#callsite(autofill(loc))
fn place_here(loc~ : SourceLoc) -> SourceLoc {
  loc
}

///|
test "a frame built again for a motion going names the motion and the place that told it, in the view or in a part kept" {
  let who = Mover::new()
  let in_part = Ref(false)
  let t = Tester::new(fn(c) {
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      if in_part.val {
        c.kept_part(c.id("part"), "", fn() {
          c.shows_motion(who, true)
          c.box(w=Px(20.0), h=Px(8.0), fn() {  }) |> ignore
        })
      } else {
        c.shows_motion(who, true)
      }
    })
    |> ignore
  })
  // (said to go, as an Anim says it: Ctx::moving with where to, then who it is for the record)
  t.ctx().moving(who, Endless::{  }, what="Anim \"slide\" to 1")
  let at = place_here()
  who.told_as("Anim \"slide\"", at)
  t.clock_frame()
  t.clock_frame()
  let why = t.built_why()
  assert_eq(why, "the clock read at a motion of Anim \"slide\", told at \{at}")
  assert_eq(built_motion.val, "a motion of Anim \"slide\", told at \{at}")
  assert_true(at.to_string().contains("frame_watch_wbtest.mbt"), msg=at.to_string())
  // (in a part kept: the part built again, said so, and what in it read the clock)
  in_part.val = true
  t.frame()
  t.clock_frame()
  t.clock_frame()
  let why = t.built_why()
  assert_true(
    why.has_prefix("what a part or a list's row read changed") &&
    why.has_suffix(", the clock read in it at a motion of Anim \"slide\", told at \{at}"),
    msg=why,
  )
}

///|
/// How long the mark's move takes (moved_tester).
let moved_ms : Double = 400.0

///|
/// A word, and a mark moved across by a look worked out as it is painted, going `moved_ms` from the view's first frame
/// (`from`); the view's builds counted.
fn moved_tester(builds : Ref[Int], from : Ref[Double]) -> Tester {
  Tester::new(fn(c) {
    builds.val = builds.val + 1
    if from.val < 0.0 {
      from.val = c.moment()
    }
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      c.text("moving", size=12.0) |> ignore
      let mark = c.box(w=Px(20.0), h=Px(8.0), bg=0x3366CCFFL, fn() {  })
      c.look_by(mark, fn() {
        let p = dclamp((c.now_before(from.val + moved_ms) - from.val) / moved_ms, 0.0, 1.0)
        look(dx=p * 100.0)
      })
    })
    |> ignore
  })
}

///|
/// Where the mark is drawn across (the first rect of its colour).
fn mark_x() -> Double {
  let c = g()
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 0.0 && c.inst[b + 2] == 20.0 && c.inst[b + 3] == 8.0 {
      return c.inst[b]
    }
  }
  -1.0
}

///|
test "a look worked out as it is painted, going: its frames painted alone, each as the frame built whole draws it" {
  let builds = Ref(0)
  let from = Ref(-1.0)
  let t = moved_tester(builds, from)
  // (built whole once more: what it laid out settled, the same twice)
  t.clock_frame()
  let was = paints_alone.val
  t.clock_frame(ms=moved_ms / 4.0)
  t.clock_frame(ms=moved_ms / 4.0)
  // (each drawn whole as well and compared: looks_compare would have failed the test)
  assert_eq(paints_alone.val - was, 2)
  assert_true(t.painted_why().contains("the clock read as it was painted"), msg=t.painted_why())
}

///|
test "a look worked out as it is painted, drawn as a host draws it: nothing built for its frames, the mark moved, then still" {
  let builds = Ref(0)
  let from = Ref(-1.0)
  let t = moved_tester(builds, from)
  t.check_looks(false)
  t.clock_frame()
  let built = builds.val
  let x0 = mark_x()
  t.clock_frame(ms=moved_ms / 2.0)
  assert_eq(builds.val, built)
  assert_true(painted_alone.val)
  assert_true(mark_x() > x0, msg="the mark drawn moved on: \{x0} then, \{mark_x()} now")
  // past its end the paint reads the clock no more: painted again once it drew the same twice, then nothing built nor
  // painted
  t.clock_frame(ms=moved_ms)
  let end = mark_x()
  t.clock_frame(ms=moved_ms / 4.0)
  t.clock_frame(ms=moved_ms / 4.0)
  assert_eq(builds.val, built)
  assert_eq(mark_x(), end)
  assert_true(end > x0)
  assert_true(!painted_alone.val)
  assert_true(looks_drawn.val)
}

///|
test "a page pushed: the frames of its slide are painted alone, the one at its end built whole" {
  let nav = Nav::new(0)
  let builds = Ref(0)
  let t = Tester::new(fn(c) {
    builds.val = builds.val + 1
    c.nav(nav, fn(i) { c.text("title \{i}", wrap=false) |> ignore }, bg=0xFFFFFFFFL) |> ignore
  })
  t.check_looks(false)
  t.draw()
  nav.push(1)
  // (its first frames built whole: what was pushed, and laid out the same twice)
  t.clock_frame()
  t.clock_frame()
  let built = builds.val
  let was = paints_alone.val
  t.clock_frame(ms=move_ms(390.0) / 4.0)
  assert_eq(builds.val, built, msg="built: \{t.built_why()}")
  t.clock_frame(ms=move_ms(390.0) / 4.0)
  assert_eq(builds.val, built, msg="built: \{t.built_why()}")
  assert_eq(paints_alone.val - was, 2)
  t.run_for(nav.rest() - t.time())
  assert_true(builds.val > built)
  assert_eq(nav.depth(), 2)
  t.assert_idle()
}

///|
test "a frame built again for what a part or a list's row read names it and where what it read was set, in a batch too" {
  let shown = @signals.signal(0)
  let t = Tester::new(fn(c) {
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      c.kept_part(c.id("part"), "", fn() {
        c.text("part \{shown.get()}", size=12.0) |> ignore
      })
      c.box(w=Fill(1.0), h=Px(200.0), fn() {
        c.list("chats", 20, 40.0, fn(i) {
          c.box(h=Px(40.0), fn() {
            c.text("row \{i} \{if i == 2 { shown.get() * 2 } else { 0 }}", size=10.0) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.keep_parts(true)
  t.draw()
  t.frame()
  // (set in a batch, as a core's delta is: told as it ends, no set under way then)
  @signals.start_batch()
  let at = place_here(); shown.set(1)
  @signals.end_batch()
  t.clock_frame()
  let why = t.built_why()
  assert_true(why.has_prefix("what a part or a list's row read changed, "), msg=why)
  // (which: the part, or the list's row, whichever was told last; where Ctx::kept_part or Ctx::list was said)
  assert_true(
    why.contains(", the part kept at src/ui/frame_watch_wbtest.mbt:") ||
    why.contains(", a row of list \"chats\" made at src/ui/frame_watch_wbtest.mbt:"),
    msg=why,
  )
  // (set on `at`'s line)
  let parts = at.to_string().split(":").take(2).map(fn(v) { v.to_string() }).collect()
  assert_true(why.contains(", set at \{parts[0]}:\{parts[1]}:"), msg=why)
}
