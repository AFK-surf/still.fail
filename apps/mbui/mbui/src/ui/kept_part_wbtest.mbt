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
