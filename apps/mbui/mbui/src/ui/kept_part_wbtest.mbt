// A part kept as it was drawn (kept_part.mbt): built once, drawn again while nothing it shows can have changed (a list
// beside it scrolled), built anew by what can change it: what it read (a signal), its key, an event from outside, a
// wake it asked for, a motion of its own.

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
  t.set_rows_on_pixels(true)
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
    t.move_to(100.0, 20.0)
    t.run_for(kept_ease_ms)
    t.move_to(100.0, 300.0)
    t.run_for(kept_ease_ms)
    t.move_to(100.0, 20.0)
    t.move_to(100.0, 30.0)
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
    t.set_rows_on_pixels(true)
    nodes_run.on = replay
    t.draw()
    let went = []
    let again = [tab_beside(t, builds, went), tab_beside(t, builds, went), tab_beside(t, builds, went)]
    nodes_run.on = true
    (went, ids, again)
  }
  let (went_kept, ids, _) = run(true)
  let (went_built, _, _) = run(false)
  assert_eq(went_kept, ids)
  assert_eq(went_built, went_kept)
}
