// A part kept as it was drawn (kept_part.mbt): built once, drawn again while nothing it shows can have changed (a list
// beside it scrolled), built anew by what can change it: what it read (a signal), its key, an event from outside, a
// wake it asked for, a motion of its own.

///|
/// What the part is built from, and how many times it was built.
priv struct TestPart {
  builds : Ref[Int]
  count : @signals.Signal[Int]
  key : Ref[String]
  /// its build asks for a frame this long after it (0: none)
  wake : Ref[Double]
  /// its build sets a move of its own out, once
  moves : Ref[Bool]
}

///|
fn TestPart::new() -> TestPart {
  { builds: Ref(0), count: @signals.signal(0), key: Ref("a"), wake: Ref(0.0), moves: Ref(false) }
}

///|
/// How far the part's move goes in its tests, and for how long; when its wake comes.
let kept_move_ms : Double = 300.0

///|
let kept_wake_ms : Double = 1000.0

///|
/// A list of rows at the left (150 wide), the part at the right.
fn TestPart::view(self : TestPart) -> (Ctx) -> Unit {
  fn(c) {
    c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), fn() {
      c.box(w=Px(150.0), h=Fill(1.0), fn() {
        c.list("rows", 40, 40.0, fn(i) {
          c.box(h=Px(40.0), fn() { c.text("row \{i}", size=10.0) |> ignore }) |> ignore
        })
        |> ignore
      })
      |> ignore
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        c.kept_part(c.id("part"), self.key.val, fn() {
          self.builds.val = self.builds.val + 1
          let n = self.count.get()
          if self.moves.val {
            self.moves.val = false
            c.move_state([("kept", ["--kept-x"])], duration=kept_move_ms)
          }
          let x = c.moved("--kept-x", if n > 0 { 40.0 } else { 0.0 })
          c.box(w=Px(160.0), h=Px(60.0), ml=x, bg=0x3366CCFFL, radius=8.0, fn() {
            c.text("count \{n}", size=12.0) |> ignore
          })
          |> ignore
          if self.wake.val > 0.0 {
            c.wake_in(self.wake.val, later=true)
          }
        })
      })
      |> ignore
    })
    |> ignore
  }
}

///|
/// The last frame's instances drawn at the part's side (from 150 across), as numbers.
fn kept_drawn() -> Array[Double] {
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b] >= 150.0 {
      for j in 0..<inst_size {
        out.push(c.inst[b + j])
      }
    }
  }
  out
}

///|
test "a part kept: drawn again as it was drawn while a list beside it scrolls, none of it built; built again once the hand lets go" {
  let k = TestPart::new()
  let t = Tester::new(k.view(), w=400.0, h=300.0)
  t.keep_parts(true)
  t.draw()
  let drawn = kept_drawn()
  assert_true(drawn.length() > 0)
  // a finger down on the list: an event from outside, the part built anew
  t.press_at(75.0, 250.0)
  let built = k.builds.val
  for i in 1..=12 {
    t.move(75.0, 250.0 - 10.0 * i.to_double())
  }
  assert_true(t.list_offset() > 50.0, msg="the list scrolled \{t.list_offset()}")
  assert_eq(k.builds.val, built)
  assert_true(g().part_kept(g().id("part")))
  assert_eq(kept_drawn(), drawn)
  // let go: built again, as it was, not read out (only drawn, built or kept alike)
  t.release(75.0, 130.0)
  assert_true(k.builds.val > built)
  assert_eq(kept_drawn(), drawn)
  assert_true(t.all(Role::Text, label="count 0").is_empty())
}

///|
/// A part kept beside a list (as TestPart's), a mark in it turned and fading by the clock (Ctx::cycle_look); how many
/// times it was built.
fn looked_part(builds : Ref[Int]) -> (Ctx) -> Unit {
  fn(c) {
    c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), fn() {
      c.box(w=Px(150.0), h=Fill(1.0), fn() {
        c.list("rows", 40, 40.0, fn(i) {
          c.box(h=Px(40.0), fn() { c.text("row \{i}", size=10.0) |> ignore }) |> ignore
        })
        |> ignore
      })
      |> ignore
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        c.kept_part(c.id("part"), "", fn() {
          builds.val = builds.val + 1
          c.box(w=Px(160.0), h=Px(60.0), bg=0x3366CCFFL, radius=8.0, align=ACenter, justify=JCenter, fn() {
            let mark = c.box(w=Px(20.0), h=Px(8.0), bg=0xFFFFFFFFL, fn() {  })
            c.cycle_look(mark, looked_turn_ms, fn(f) { look(rot=f * 6.283185307179586, alpha=0.5 + 0.5 * f) })
          })
          |> ignore
        })
      })
      |> ignore
    })
    |> ignore
  }
}

///|
test "a part kept: its look by the clock goes on as it is drawn again, the part not built for it" {
  let run = fn(replay : Bool) -> (Array[Array[Double]], Int, Bool) {
    let builds = Ref(0)
    let t = Tester::new(looked_part(builds), w=400.0, h=300.0)
    t.keep_parts(true)
    drawn_again_on.val = replay
    t.draw()
    // a finger down on the list beside it, scrolling it: the part drawn again
    t.press_at(75.0, 250.0)
    t.move(75.0, 240.0)
    let built = builds.val
    let frames = []
    for i in 1..=10 {
      t.move(75.0, 240.0 - 10.0 * i.to_double())
      t.run_for(rows_still_ms)
      frames.push(kept_drawn())
    }
    let kept = g().part_kept(g().id("part"))
    let builds = builds.val - built
    t.release(75.0, 130.0)
    drawn_again_on.val = true
    (frames, builds, kept)
  }
  let (again, builds, kept) = run(true)
  let (built, _, _) = run(false)
  assert_true(kept, msg="the part was built")
  assert_eq(builds, 0)
  assert_true(again[0] != again[1], msg="its look stands still")
  assert_eq(again, built)
}

///|
test "a part kept is built again by what it read, its key, an event from outside, a message" {
  let k = TestPart::new()
  let t = Tester::new(k.view(), w=400.0, h=300.0)
  t.keep_parts(true)
  t.draw()
  t.frame()
  let built = k.builds.val
  t.frame()
  assert_eq(k.builds.val, built)
  // a signal it read
  k.count.set(1)
  t.frame()
  assert_eq(k.builds.val, built + 1)
  t.frame()
  assert_eq(k.builds.val, built + 1)
  // its key
  k.key.val = "b"
  t.frame()
  assert_eq(k.builds.val, built + 2)
  // what the test changed (as what comes from outside), a message
  t.draw()
  assert_eq(k.builds.val, built + 3)
  t.post("kept-test", "{}")
  t.frame()
  assert_eq(k.builds.val, built + 4)
  t.frame()
  assert_eq(k.builds.val, built + 4)
}

///|
test "a part kept is built again at the wake its build asked for, and each frame while a motion of its own goes" {
  let k = TestPart::new()
  k.wake.val = kept_wake_ms
  let t = Tester::new(k.view(), w=400.0, h=300.0)
  t.keep_parts(true)
  t.draw()
  let at = t.time()
  let built = k.builds.val
  // a frame before the wake: kept; at it, built (and asking again)
  t.move(300.0, 200.0)
  assert_eq(k.builds.val, built)
  t.run_for(at + kept_wake_ms - t.time())
  assert_eq(k.builds.val, built + 1)
  // a move of its own set out: built each frame it goes, kept once it is over
  k.wake.val = 0.0
  k.moves.val = true
  k.count.set(1)
  t.frame()
  let set_out = k.builds.val
  t.frame()
  t.frame()
  assert_eq(k.builds.val, set_out + 2)
  t.run_for(kept_move_ms)
  let rested = k.builds.val
  t.frame()
  t.frame()
  assert_eq(k.builds.val, rested)
  t.assert_idle()
}

///|
test "a part kept is built each frame a press is held down on what it draws, and as a wheel turns over it, not over the list beside it" {
  let k = TestPart::new()
  let t = Tester::new(k.view(), w=400.0, h=300.0)
  t.keep_parts(true)
  t.draw()
  t.frame()
  // held down on it: built each frame it is held (what it holds may take the press)
  t.press_at(300.0, 30.0)
  let held = k.builds.val
  t.frame()
  t.frame()
  assert_eq(k.builds.val, held + 2)
  t.release(300.0, 30.0)
  // held down where it draws nothing (in its box, past what it drew): drawn again
  t.press_at(300.0, 250.0)
  let away = k.builds.val
  t.frame()
  t.frame()
  assert_eq(k.builds.val, away)
  t.release(300.0, 250.0)
  t.frame()
  let after = k.builds.val
  t.frame()
  assert_eq(k.builds.val, after)
  // a wheel over it: built; over the list beside it: drawn again
  t.wheel(300.0, 30.0, 40.0)
  assert_true(k.builds.val > after)
  let wheeled = k.builds.val
  t.wheel(75.0, 100.0, 40.0)
  assert_eq(k.builds.val, wheeled)
}

///|
/// How long a wheel's notch is let ease on in the tests below.
let kept_ease_ms : Double = 400.0

///|
/// A part holding a list of rows, and a box at its top lit under the pointer.
fn kept_list_view(builds : Ref[Int]) -> (Ctx) -> Unit {
  fn(c) {
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      c.kept_part(c.id("part"), "k", fn() {
        builds.val = builds.val + 1
        c.box(w=Fill(1.0), h=Fill(1.0), fn() {
          let lit = c.id("lit")
          c.box(id=lit, w=Px(200.0), h=Px(40.0), bg=if c.hovered(lit) { 0xDDE6FFFFL } else { 0xEEEEEEFFL }, fn() {
            c.text("lit", size=12.0) |> ignore
          })
          |> ignore
          c.list("in-part", 80, 40.0, fn(i) {
            c.box(h=Px(40.0), fn() { c.text("item \{i}", size=12.0) |> ignore }) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
    })
    |> ignore
  }
}

///|
/// Every frame `steps` draws with the part kept where it can be (`keep`) or built every frame (its drawing taken as
/// when it is kept), as numbers.
fn kept_frames(
  keep : Bool,
  platform : Int,
  steps : (Tester) -> Unit,
  pointing? : Pointing = Finger,
) -> Array[Array[Double]] {
  let t = Tester::new(kept_list_view(Ref(0)), w=300.0, h=400.0, platform~, pointing~)
  t.keep_parts(true)
  t.drawn_again(keep)
  let frames = []
  frame_hook.val = Some(fn() {
    let c = g()
    let f = []
    for v in 0..<(c.ninst * inst_size) {
      f.push(c.inst[v])
    }
    frames.push(f)
  })
  t.draw()
  steps(t)
  frame_hook.val = None
  frames
}

///|
/// The two runs drew the same frames.
fn kept_same(kept : Array[Array[Double]], built : Array[Array[Double]]) -> Unit raise {
  assert_eq(kept.length(), built.length())
  for f in 0..<kept.length() {
    let x = kept[f]
    let y = built[f]
    if x.length() != y.length() {
      fail("frame \{f}: \{x.length() / inst_size} instances kept, \{y.length() / inst_size} built")
    }
    for v in 0..<x.length() {
      if x[v] != y[v] {
        let b = v / inst_size * inst_size
        fail(
          "frame \{f}: instance \{v / inst_size} (kind \{y[b + 5]} at \{y[b]},\{y[b + 1]} \{y[b + 2]}x\{y[b + 3]})'s \{v % inst_size} is \{x[v]} kept, \{y[v]} built",
        )
      }
    }
  }
}

///|
test "a part kept is built each frame what moves in it goes, told as it was not built: its list eased by a wheel" {
  let steps = fn(t : Tester) {
    t.run_for(kept_ease_ms)
    t.wheel(150.0, 200.0, 120.0)
    t.run_for(kept_ease_ms)
  }
  let kept = kept_frames(true, 2, steps)
  let built = kept_frames(false, 2, steps)
  kept_same(kept, built)
}

///|
test "a part kept is built while the mouse's pointer is over it: what it points at lit, and unlit once it leaves" {
  let steps = fn(t : Tester) {
    t.run_for(kept_ease_ms)
    t.move(100.0, 20.0)
    t.run_for(kept_ease_ms)
    t.move(100.0, 300.0)
    t.run_for(kept_ease_ms)
    t.move(100.0, 20.0)
    t.move(100.0, 30.0)
    t.run_for(kept_ease_ms)
  }
  let kept = kept_frames(true, 0, steps, pointing=Mouse)
  let built = kept_frames(false, 0, steps, pointing=Mouse)
  kept_same(kept, built)
}

///|
/// A list of rows at the left, a part kept at the right holding two buttons, a button under it: what takes the focus,
/// in Tab's order, the part's first; how many times the part was built.
fn focus_part_view(ids : Array[Int], builds : Ref[Int]) -> (Ctx) -> Unit {
  fn(c) {
    c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), fn() {
      c.box(w=Px(150.0), h=Fill(1.0), fn() {
        c.list("rows", 40, 40.0, fn(i) {
          c.box(h=Px(40.0), fn() { c.text("row \{i}", size=10.0) |> ignore }) |> ignore
        })
        |> ignore
      })
      |> ignore
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        c.box(h=Px(100.0), fn() {
          c.kept_part(c.id("part"), "", fn() {
            builds.val = builds.val + 1
            for k in 0..<2 {
              let id = c.id("in \{k}")
              ids[k] = id
              c.interact(id) |> ignore
              c.box(id~, w=Px(80.0), h=Px(30.0), bg=0x3366CCFFL, fn() { c.text("in \{k}", size=10.0) |> ignore })
              |> ignore
            }
          })
        })
        |> ignore
        let id = c.id("under")
        ids[2] = id
        c.interact(id) |> ignore
        c.box(id~, w=Px(80.0), h=Px(30.0), bg=0x3366CCFFL, fn() { c.text("under", size=10.0) |> ignore }) |> ignore
      })
      |> ignore
    })
    |> ignore
  }
}

///|
/// The list beside the part scrolled by the wheel, then Tab: where the focus went, and whether the part was drawn again
/// (not built) as Tab came.
fn tab_beside(t : Tester, builds : Ref[Int], went : Array[Int]) -> Bool {
  t.wheel(75.0, 200.0, 40.0)
  t.run_for(kept_ease_ms)
  let before = builds.val
  t.frame()
  let again = builds.val == before
  t.tab()
  went.push(g().focused_id())
  again
}

///|
test "a part kept drawn again: what takes the focus in it is in Tab's order, as built" {
  let run = fn(replay : Bool) -> (Array[Int], Array[Int], Array[Bool]) {
    let ids = [0, 0, 0]
    let builds = Ref(0)
    let t = Tester::new(focus_part_view(ids, builds), w=420.0, h=400.0, platform=0)
    t.keep_parts(true)
    drawn_again_on.val = replay
    t.draw()
    let went = []
    let again = [tab_beside(t, builds, went), tab_beside(t, builds, went), tab_beside(t, builds, went)]
    drawn_again_on.val = true
    (went, ids, again)
  }
  let (went_kept, ids, again) = run(true)
  let (went_built, _, _) = run(false)
  assert_eq(again, [true, true, true])
  assert_eq(went_kept, ids)
  assert_eq(went_built, went_kept)
}
