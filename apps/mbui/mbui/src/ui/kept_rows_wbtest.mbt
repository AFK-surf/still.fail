// A list's rows kept as they were drawn (kept_rows.mbt): drawn again where they are as the list scrolls, as their build
// would draw them there, and still pressed, pointed at and read as built rows are; built again by what changes them.
// Each scene runs twice, its rows drawn again and its rows built every frame (Tester::drawn_again), and every frame of the two
// is the same.

///|
/// What the rows are built from, and what they said.
priv struct TestRows {
  /// how many times each row was built
  builds : Array[Int]
  clicks : Array[Int]
  /// what row 3 shows
  mark : @signals.Signal[Int]
}

///|
fn TestRows::new() -> TestRows {
  { builds: Array::make(60, 0), clicks: [], mark: @signals.signal(0) }
}

///|
/// 60 rows in a card with round corners, each its words and a button, lit under the pointer; row 9 taller than the
/// window, row 3's words what `mark` says.
fn TestRows::view(self : TestRows) -> (Ctx) -> Unit {
  fn(c) {
    c.box(w=Fill(1.0), h=Fill(1.0), pad=12.0, fn() {
      c.box(w=Fill(1.0), h=Fill(1.0), radius=16.0, clip=true, bg=0xF2F2F2FFL, fn() {
        c.list("rows", 60, 50.0, fn(i) {
          self.builds[i] = self.builds[i] + 1
          let row = c.id("row")
          let go = c.id("go")
          if c.clicked(go) {
            self.clicks.push(i)
          }
          let h = if i == 9 { 900.0 } else { 50.0 + (i % 3).to_double() * 10.0 }
          let n = if i == 3 { self.mark.get() } else { 0 }
          c.box(
            id=row,
            h=Px(h),
            dir=Row,
            padx=10.0,
            gap=8.0,
            align=ACenter,
            bg=if c.hovered(row) { 0xDDE6FFFFL } else { 0L },
            fn() {
              c.box(w=Fill(1.0), fn() { c.text("row \{i} mark \{n}", size=12.0) |> ignore }) |> ignore
              c.box(id=go, w=Px(44.0), h=Px(26.0), radius=8.0, bg=0x3366CCFFL, align=ACenter, justify=JCenter, fn() {
                c.text("go \{i}", size=10.0, color=0xFFFFFFFFL) |> ignore
              })
              |> ignore
            },
          )
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  }
}

///|
/// The last frame's instances, as numbers.
fn rows_frame() -> Array[Double] {
  let c = g()
  let out = []
  for v in 0..<(c.ninst * inst_size) {
    out.push(c.inst[v])
  }
  out
}

///|
/// How long a scene's fling is let run, and how long between the wheel's notches.
let rows_fling_ms : Double = 1200.0

///|
let rows_notch_ms : Double = 50.0

///|
/// A scene run with its rows drawn again where they can be (`replay`), or built every frame: each frame drawn, the rows
/// drawn again in all, the rows' clicks.
fn rows_scene(replay : Bool, platform : Int, steps : (Tester, TestRows) -> Unit) -> RowsRun {
  let k = TestRows::new()
  let t = Tester::new(k.view(), w=320.0, h=420.0, platform~)
  t.keep_parts(true)
  drawn_again_on.val = replay
  let frames = []
  let kept = Ref(0)
  frame_hook.val = Some(fn() {
    frames.push(rows_frame())
    kept.val = kept.val + t.rows_kept()
  })
  t.draw()
  steps(t, k)
  frame_hook.val = None
  drawn_again_on.val = true
  { frames, kept: kept.val, clicks: k.clicks }
}

///|
priv struct RowsRun {
  frames : Array[Array[Double]]
  kept : Int
  clicks : Array[Int]
}

///|
/// The two runs drew the same frames (to a millionth of a point: a row drawn again is moved by where it is now less
/// where it was built).
fn rows_same(a : RowsRun, b : RowsRun) -> Unit raise {
  assert_eq(a.frames.length(), b.frames.length())
  for f in 0..<a.frames.length() {
    let x = a.frames[f]
    let y = b.frames[f]
    if x.length() != y.length() {
      fail("frame \{f}: \{x.length() / inst_size} instances drawn again, \{y.length() / inst_size} built")
    }
    for v in 0..<x.length() {
      if (x[v] - y[v]).abs() > 0.000001 {
        fail("frame \{f}: instance \{v / inst_size}'s \{v % inst_size} is \{x[v]} drawn again, \{y[v]} built")
      }
    }
  }
}

///|
/// A finger drags the list up three times and lets it fling: past what the tall row's build drew.
fn rows_strokes(t : Tester, k : TestRows) -> Unit {
  ignore(k)
  t.drag(160.0, 390.0, 160.0, 90.0, steps=30)
  t.run_for(rows_fling_ms)
  t.drag(160.0, 390.0, 160.0, 90.0, steps=30)
  t.run_for(rows_fling_ms)
  t.drag(160.0, 90.0, 160.0, 390.0, steps=30)
  t.run_for(rows_fling_ms)
}

///|
test "a list's rows dragged and flung: drawn again where they are, as their build draws them there" {
  let kept = rows_scene(true, 2, rows_strokes)
  let built = rows_scene(false, 2, rows_strokes)
  assert_true(kept.kept > 200, msg="rows drawn again: \{kept.kept}")
  assert_eq(built.kept, 0)
  rows_same(kept, built)
}

///|
test "a list's rows dragged: built only as they come, as the press changes hands, and past what their build drew" {
  let k = TestRows::new()
  let t = Tester::new(k.view(), w=320.0, h=844.0, platform=2)
  t.keep_parts(true)
  t.draw()
  t.frame()
  t.press_at(160.0, 820.0)
  t.move(160.0, 810.0)
  t.move(160.0, 800.0)
  // (the list has the drag: what the press was on no longer is)
  let builds = k.builds.copy()
  t.move(160.0, 790.0)
  t.move(160.0, 780.0)
  // the rows in view drawn again; the tall one's band holds what shows of it
  assert_eq(k.builds, builds)
  assert_true(t.rows_kept() >= 8, msg="\{t.rows_kept()}")
  // the tall row (9) scrolled past what its build drew: built again
  let tall = k.builds[9]
  for i in 1..=56 {
    t.move(160.0, 780.0 - 10.0 * i.to_double())
  }
  assert_true(k.builds[9] > tall)
  t.release(160.0, 220.0)
}

///|
/// 40 rows none of whose heights is a whole number of pixels at 2.625 (Android's 420 dpi), at the list's end its last
/// as tall as `foot` says (what is under the messages: the composer's room, words sent flying in).
fn pixel_rows(foot : @signals.Signal[Double]) -> (Ctx) -> Unit {
  fn(c) {
    c.list(
      "rows",
      40,
      40.0,
      fn(i) {
        let h = if i == 39 { foot.get() } else { 37.3 + (i % 5).to_double() * 1.37 }
        c.box(h=Px(h), fn() { c.text("row \{i}", size=13.0) |> ignore }) |> ignore
      },
      stick_end=true,
    )
    |> ignore
  }
}

///|
/// The rows of the last frame's list whose tops are off the device's pixels: what moves them part of a pixel sets their
/// lines apart (each glyph is set on the pixels where it is).
fn rows_off_pixels() -> Array[String] {
  let c = g()
  let off = []
  for i in 0..<c.count {
    if c.nodes[i].kind == kind_list {
      let mut r = c.nodes[i].first
      while r >= 0 {
        let v = c.nodes[r].y * c.scale
        if (v - v.round()).abs() > 0.000001 {
          off.push("row \{c.nodes[r].item} at \{c.nodes[r].y}")
        }
        r = c.nodes[r].next
      }
    }
  }
  off
}

///|
test "a list's rows on the device's pixels however it stands: at its end as what is under them grows, dragged, said from another row" {
  let foot = @signals.signal(20.0)
  let t = Tester::new(pixel_rows(foot), w=390.0, h=700.0, platform=2, scale=2.625)
  t.keep_parts(true)
  t.draw()
  assert_eq(rows_off_pixels(), [])
  // at its end, what is under the rows growing by parts of a pixel
  foot.set(20.37)
  t.draw()
  assert_eq(rows_off_pixels(), [])
  foot.set(23.85)
  t.draw()
  assert_eq(rows_off_pixels(), [])
  // dragged by part of a pixel, then past a row's height: said from the row now first in view
  t.press_at(200.0, 300.0)
  t.move(200.0, 310.0)
  t.move(200.0, 320.73)
  assert_eq(rows_off_pixels(), [])
  t.move(200.0, 390.31)
  assert_eq(rows_off_pixels(), [])
  t.release(200.0, 390.31)
  t.run_for(rows_fling_ms)
  assert_eq(rows_off_pixels(), [])
}

///|
/// A Tester's host that sets things on whole device pixels, as Android's does: its font's metrics in whole pixels at
/// 3.25 (Android's 520 dpi), saying so (whole_px_layout).
let whole_px_text = "{\"m\":[13,400,0],\"r\":[10.461538461538462,2.769230769230769,18,10.461538461538462,2.769230769230769,1]}"

///|
/// 40 rows 78 pixels high at 3.25, in each a picture 59 high centred and its words beside it centred: 19 pixels over
/// each, half of it either side.
fn centred_rows() -> (Ctx) -> Unit {
  fn(c) {
    c.list(
      "rows",
      40,
      24.0,
      fn(_) {
        c.box(dir=Row, h=Px(78.0 / 3.25), align=ACenter, fn() {
          c.box(w=Px(30.0 / 3.25), h=Px(59.0 / 3.25), bg=0xFF808080L, fn() { () }) |> ignore
          c.text("row", size=13.0) |> ignore
        })
        |> ignore
      },
      stick_end=true,
    )
    |> ignore
  }
}

///|
/// What the last frame's lists' rows hold whose tops are off the device's pixels.
fn row_parts_off_pixels() -> Array[String] {
  let c = g()
  let off = []
  for i in 0..<c.count {
    let v = c.nodes[i].y * c.scale
    if c.list_of(i) >= 0 && (v - v.round()).abs() > 0.000001 {
      off.push("node \{i} of kind \{c.nodes[i].kind} at \{v}")
    }
  }
  off
}

///|
test "on a host that sets things on whole pixels, what a list's rows hold is on them too however the rows move: its words move as their row" {
  let t = Tester::new(centred_rows(), w=390.0, h=700.0, platform=2, scale=3.25, text=whole_px_text)
  t.keep_parts(true)
  t.draw()
  assert_eq(row_parts_off_pixels(), [])
  // dragged by parts of a pixel, then flung
  t.press_at(200.0, 300.0)
  t.move(200.0, 310.0)
  t.move(200.0, 320.73)
  assert_eq(row_parts_off_pixels(), [])
  t.move(200.0, 390.31)
  assert_eq(row_parts_off_pixels(), [])
  t.release(200.0, 390.31)
  t.run_for(rows_fling_ms / 2.0)
  assert_eq(row_parts_off_pixels(), [])
  t.run_for(rows_fling_ms / 2.0)
  assert_eq(row_parts_off_pixels(), [])
}

///|
/// The pointer over the rows, the wheel turned notch by notch: the row under it lit as they pass.
fn rows_wheel(t : Tester, k : TestRows) -> Unit {
  ignore(k)
  t.move(160.0, 200.0)
  for _ in 0..<20 {
    t.wheel(160.0, 200.0, 40.0)
    t.run_for(rows_notch_ms)
  }
  t.move(160.0, 300.0)
  t.run_for(rows_notch_ms)
}

///|
test "a list's rows under the mouse: the row pointed at lit as the wheel scrolls them, the others drawn again" {
  let kept = rows_scene(true, 0, rows_wheel)
  let built = rows_scene(false, 0, rows_wheel)
  assert_true(kept.kept > 100, msg="rows drawn again: \{kept.kept}")
  rows_same(kept, built)
}

///|
/// The list dragged a little and still: row 3's mark changed, its button tapped, another row's button after it.
fn rows_taps(t : Tester, k : TestRows) -> Unit {
  t.drag(160.0, 390.0, 160.0, 340.0, steps=5)
  t.run_for(rows_fling_ms)
  k.mark.set(5)
  t.frame()
  t.frame()
  // what a tap finds there is what the last frame drew: the rows drawn again
  match t.rect_of("go 3") {
    Some((x, y, w, h)) => t.tap(x + w / 2.0, y + h / 2.0)
    None => ()
  }
  t.run_for(rows_notch_ms)
  match t.rect_of("go 5") {
    Some((x, y, w, h)) => t.tap(x + w / 2.0, y + h / 2.0)
    None => ()
  }
  t.run_for(rows_notch_ms)
}

///|
test "a list's rows still: a row's mark drawn as it changes, a kept row's button pressed as a built one's" {
  let kept = rows_scene(true, 2, rows_taps)
  let built = rows_scene(false, 2, rows_taps)
  assert_eq(kept.clicks, [3, 5])
  assert_eq(built.clicks, [3, 5])
  assert_true(kept.kept > 10, msg="rows drawn again: \{kept.kept}")
  rows_same(kept, built)
}

///|
test "a list's row reading a signal is built as it changes, the others drawn again" {
  let k = TestRows::new()
  let t = Tester::new(k.view(), w=320.0, h=420.0, platform=2)
  t.keep_parts(true)
  t.draw()
  t.frame()
  t.frame()
  let builds = k.builds.copy()
  k.mark.set(3)
  t.frame()
  assert_eq(k.builds[3], builds[3] + 1)
  assert_eq(k.builds[2], builds[2])
  assert_eq(k.builds[4], builds[4])
  assert_true(t.find("row 3 mark 3") is Some(_))
}

///|
/// 40 rows of words under a bar of `more` marks, as a page's list under what floats over it (still.fail's bar, a
/// mark more or less in it as it moves).
fn marked_rows(more : @signals.Signal[Int]) -> (Ctx) -> Unit {
  fn(c) {
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      c.box(dir=Row, h=Px(20.0), gap=4.0, fn() {
        for _ in 0..<more.get() {
          c.box(w=Px(10.0), h=Px(10.0), bg=0x3366CCFFL, fn() {  }) |> ignore
        }
      })
      |> ignore
      c.list("rows", 40, 50.0, fn(i) {
        c.box(h=Px(50.0), dir=Row, padx=10.0, gap=8.0, align=ACenter, fn() {
          c.box(w=Fill(1.0), fn() { c.text("row \{i}", size=12.0) |> ignore }) |> ignore
          c.text("\{i * 7}", size=10.0) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  }
}

///|
test "a list's rows built anew after a node more before them: laid out as before, not each of them again" {
  let more = @signals.signal(1)
  let t = Tester::new(marked_rows(more), w=320.0, h=420.0, platform=2)
  t.draw()
  t.frame()
  t.frame()
  // a mark more in the bar: the frame built anew for it (what it read changed), its rows with it
  more.set(2)
  let placed = commit_counts[0]
  t.frame()
  // laid out anew: the mark, the bar and what holds it; no row (eight of them show, four nodes each)
  assert_true(commit_counts[0] - placed < 8, msg="laid anew: \{commit_counts[0] - placed}")
  assert_true(t.find("row 3") is Some(_))
}

///|
/// How far apart the moments are that rows left still are looked at (no step of their clock's falls on one).
let rows_still_ms : Double = 70.0

///|
/// 30 rows, not in a part kept (as a chat's messages on 小屏): row 2 turning with the clock (Ctx::cycle, a spinner's),
/// row 4 stepping once a 100 ms (Ctx::every, a ring's steps, a clock's seconds), the others still; how many times each
/// was built.
fn timed_rows(builds : Array[Int]) -> (Ctx) -> Unit {
  fn(c) {
    c.list("timed", 30, 50.0, fn(i) {
      builds[i] = builds[i] + 1
      let words = if i == 2 {
        "turned \{(c.cycle(800.0) * 360.0).to_int()}"
      } else if i == 4 {
        "step \{c.every(100.0) % 8}"
      } else {
        "row \{i}"
      }
      c.box(h=Px(50.0), padx=10.0, fn() { c.text(words, size=12.0) |> ignore }) |> ignore
    })
    |> ignore
  }
}

///|
test "a list's rows left still: a row going on with the clock built as it goes, the others drawn again" {
  let run = fn(replay : Bool) -> (Array[Array[Double]], Int) {
    let builds = Array::make(30, 0)
    let t = Tester::new(timed_rows(builds), w=320.0, h=420.0, platform=2)
    t.keep_parts(true)
    drawn_again_on.val = replay
    t.draw()
    let frames = []
    let mut kept = 0
    for _ in 0..<20 {
      t.run_for(rows_still_ms)
      frames.push(rows_frame())
      kept = kept + t.rows_kept()
    }
    drawn_again_on.val = true
    (frames, kept)
  }
  let (kept, n) = run(true)
  let (built, _) = run(false)
  assert_true(n > 100, msg="rows drawn again: \{n}")
  rows_same({ frames: kept, kept: n, clicks: [] }, { frames: built, kept: 0, clicks: [] })
}

///|
/// 30 rows, not in a part kept: row 2's mark turned by the clock (a spinner's), row 4's breathing and beating on the
/// resident clock's steps (Ctx::cycle_look), the others still; how many times each was built.
fn looked_rows(builds : Array[Int]) -> (Ctx) -> Unit {
  fn(c) {
    c.list("looked", 30, 50.0, fn(i) {
      builds[i] = builds[i] + 1
      c.box(h=Px(50.0), padx=10.0, dir=Row, gap=8.0, align=ACenter, fn() {
        if i == 2 {
          let mark = c.box(w=Px(14.0), h=Px(6.0), bg=0x3366FFFFL, fn() {  })
          c.cycle_look(mark, looked_turn_ms, fn(f) { look(rot=f * 6.283185307179586) })
        } else if i == 4 {
          let mark = c.box(w=Px(14.0), h=Px(14.0), radius=7.0, bg=0xFF6633FFL, fn() {  })
          c.cycle_look(mark, looked_breath_ms, fn(f) { look(alpha=0.35 + 0.65 * f, scale=1.0 + 0.3 * f) }, resident=true)
        }
        c.text("row \{i}", size=12.0) |> ignore
      })
      |> ignore
    })
    |> ignore
  }
}

///|
/// How long looked_rows' turn takes, and its breath.
let looked_turn_ms : Double = 800.0

///|
let looked_breath_ms : Double = 1400.0

///|
test "a list's rows left still: a row's look by the clock goes on as it is drawn again, the row not built for it" {
  let run = fn(replay : Bool) -> (Array[Array[Double]], Array[Int]) {
    let builds = Array::make(30, 0)
    let t = Tester::new(looked_rows(builds), w=320.0, h=420.0, platform=2)
    t.keep_parts(true)
    drawn_again_on.val = replay
    t.draw()
    let frames = []
    for _ in 0..<20 {
      t.run_for(rows_still_ms)
      frames.push(rows_frame())
    }
    drawn_again_on.val = true
    (frames, builds)
  }
  let (kept, builds) = run(true)
  let (built, _) = run(false)
  // (built no more than a still row: nothing in them is read of the clock)
  assert_eq(builds[2], builds[3])
  assert_eq(builds[4], builds[3])
  // (and drawn as they go on: turned, breathing)
  assert_true(kept[1] != kept[2] && kept[1] != kept[19], msg="the looks stand still")
  rows_same({ frames: kept, kept: 0, clicks: [] }, { frames: built, kept: 0, clicks: [] })
}

///|
/// A part kept holding a list (`list_part`), another part beside it (`other`); row 3 of the list shows what `mark` says,
/// which nothing but it reads, and row 5 is as wide as `spring` is now, a spring the other part sets going as it is
/// built.
fn parted_rows(mark : @signals.Signal[Int], spring : SpringPath, go : @signals.Signal[Double]) -> (Ctx) -> Unit {
  fn(c) {
    c.box(w=Fill(1.0), h=Fill(1.0), dir=Row, fn() {
      c.box(w=Px(100.0), h=Fill(1.0), fn() {
        c.kept_part(c.id("other"), "", fn() {
          let to = go.get()
          if to != spring.target() {
            spring.go_at(c, to)
          }
          c.text("other", size=12.0) |> ignore
        })
      })
      |> ignore
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        c.kept_part(c.id("list_part"), "", fn() {
          c.list("parted", 30, 50.0, fn(i) {
            let words = if i == 3 { "row 3 mark \{mark.get()}" } else { "row \{i}" }
            let w = if i == 5 { 40.0 + spring.value(c.now()) } else { 40.0 }
            c.box(h=Px(50.0), padx=10.0, dir=Row, fn() {
              c.box(w=Px(w), h=Px(10.0), bg=0x3366CCFFL, fn() {  }) |> ignore
              c.text(words, size=12.0) |> ignore
            })
            |> ignore
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
test "a list's row in a part kept reads what nothing else there reads: the part is built again as it changes" {
  let mark = @signals.signal(0)
  let t = Tester::new(
    parted_rows(mark, SpringPath::new(0.0, k=420.0, c=32.0), @signals.signal(0.0)),
    w=420.0,
    h=420.0,
    platform=2,
  )
  t.keep_parts(true)
  t.draw()
  t.frame()
  t.frame()
  assert_true(t.parts_kept() > 0, msg="parts drawn again: \{t.parts_kept()}")
  mark.set(7)
  t.frame()
  assert_true(t.find("row 3 mark 7") is Some(_))
}

///|
test "a list's row in a part kept shows a motion another part told: drawn as it goes, as building it draws it" {
  let run = fn(replay : Bool) -> Array[Array[Double]] {
    let go = @signals.signal(0.0)
    let t = Tester::new(
      parted_rows(@signals.signal(0), SpringPath::new(0.0, k=420.0, c=32.0), go),
      w=420.0,
      h=420.0,
      platform=2,
    )
    t.keep_parts(true)
    drawn_again_on.val = replay
    t.draw()
    t.frame()
    go.set(120.0)
    let frames = []
    for _ in 0..<12 {
      t.run_for(rows_still_ms)
      frames.push(rows_frame())
    }
    drawn_again_on.val = true
    frames
  }
  let kept = run(true)
  let built = run(false)
  rows_same({ frames: kept, kept: 0, clicks: [] }, { frames: built, kept: 0, clicks: [] })
}

///|
test "a list's rows read out as they are dragged and flung: kept, read out as building them says them" {
  let run = fn(replay : Bool) -> (Array[String], Int) {
    let k = TestRows::new()
    let t = Tester::new(k.view(), w=320.0, h=420.0, platform=2)
    t.keep_parts(true)
    t.set_a11y(true)
    drawn_again_on.val = replay
    let said = []
    let mut kept = 0
    frame_hook.val = Some(fn() {
      said.push(t.a11y_said())
      kept = kept + t.rows_kept()
    })
    t.draw()
    rows_strokes(t, k)
    frame_hook.val = None
    drawn_again_on.val = true
    (said, kept)
  }
  let (kept, n) = run(true)
  let (built, _) = run(false)
  assert_true(n > 200, msg="rows drawn again: \{n}")
  assert_eq(kept.length(), built.length())
  for f in 0..<kept.length() {
    if kept[f] != built[f] {
      fail("frame \{f}: read out drawn again:\n\{kept[f]}\nbuilt:\n\{built[f]}")
    }
  }
}

///|
test "a list's row drawn again keeps what its build read of the layout: built again, it reads it at once" {
  let mark = @signals.signal(0)
  let read : Array[Bool] = []
  let view = fn(c : Ctx) {
    c.list("reads", 30, 50.0, fn(i) {
      let words = c.id("words")
      if i == 3 {
        // (what it shows sized by what its words took as laid out: none the first frame)
        let laid = c.laid_size(words)
        read.push(laid is Some(_))
        ignore(mark.get())
      }
      c.box(h=Px(50.0), padx=10.0, dir=Row, fn() {
        c.box(id=words, fn() { c.text("row \{i}", size=12.0) |> ignore }) |> ignore
      })
      |> ignore
    })
    |> ignore
  }
  let t = Tester::new(view, w=320.0, h=420.0, platform=2)
  t.keep_parts(true)
  t.draw()
  t.frame()
  t.frame()
  t.frame()
  assert_true(t.rows_kept() > 0, msg="\{t.rows_kept()}")
  read.clear()
  mark.set(1)
  t.frame()
  assert_eq(read, [true])
}

///|
/// 30 rows, each saying once a frame's builds are over that it showed (Ctx::after_build), its button telling once of a
/// tap on it (Ctx::tell): how many times each said it showed, how many taps were told.
fn telling_rows(seen : Array[Int], taps : Ref[Int]) -> (Ctx) -> Unit {
  fn(c) {
    c.list("telling", 30, 50.0, fn(i) {
      let go = c.id("go")
      if c.clicked(go) {
        c.tell("tapped", fn() { taps.val = taps.val + 1 })
      }
      c.after_build("shown", fn() { seen[i] = seen[i] + 1 })
      c.box(h=Px(50.0), dir=Row, padx=10.0, align=ACenter, fn() {
        c.box(w=Fill(1.0), fn() { c.text("row \{i}", size=12.0) |> ignore }) |> ignore
        c.box(id=go, w=Px(60.0), h=Px(30.0), bg=0x3366CCFFL, fn() { c.text("go \{i}", size=10.0) |> ignore })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  }
}

///|
test "a list's row drawn again says again what every build of it says, but tells what one build saw only once" {
  let run = fn(replay : Bool) -> (Array[Int], Int, Int) {
    let seen = Array::make(30, 0)
    let taps = Ref(0)
    let t = Tester::new(telling_rows(seen, taps), w=320.0, h=420.0, platform=2)
    t.keep_parts(true)
    drawn_again_on.val = replay
    t.draw()
    t.run_for(rows_notch_ms)
    let (x, y, w, h) = t.rect_of("go 2").unwrap()
    t.tap(x + w / 2.0, y + h / 2.0)
    let kept = Ref(0)
    frame_hook.val = Some(fn() { kept.val = kept.val + t.rows_kept() })
    t.run_for(rows_fling_ms)
    frame_hook.val = None
    drawn_again_on.val = true
    (seen, taps.val, kept.val)
  }
  let (seen_kept, taps_kept, kept) = run(true)
  let (seen_built, taps_built, _) = run(false)
  // (drawn again after the tap's build: what it told not told again)
  assert_true(kept > 0, msg="rows drawn again: \{kept}")
  assert_eq(taps_kept, 1)
  assert_eq(taps_built, 1)
  assert_eq(seen_kept, seen_built)
}

///|
test "a list's rows kept as their nodes on the device's pixels as a host lays them: at its end as what is under them grows, dragged, flung" {
  let foot = @signals.signal(20.0)
  let t = Tester::new(pixel_rows(foot), w=390.0, h=700.0, platform=2, scale=2.625)
  // (as a host lays them: its rows on the pixels, kept as their nodes, no part kept as drawn; how frames are built
  // changed by the test, the next built whole)
  rows_grid_test.val = true
  test_stepped()
  t.draw()
  assert_eq(rows_off_pixels(), [])
  foot.set(20.37)
  t.draw()
  assert_eq(rows_off_pixels(), [])
  t.press_at(200.0, 300.0)
  t.move(200.0, 310.0)
  t.move(200.0, 320.73)
  assert_eq(rows_off_pixels(), [])
  // (the rows that stayed in view kept, put back where the list lays them, on the pixels with the rest)
  assert_true(t.rows_as_nodes().0 > 0)
  t.move(200.0, 390.31)
  assert_eq(rows_off_pixels(), [])
  t.release(200.0, 390.31)
  t.run_for(rows_fling_ms)
  assert_eq(rows_off_pixels(), [])
}
