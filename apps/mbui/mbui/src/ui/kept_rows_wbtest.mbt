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
            let w = if i == 5 { 40.0 + spring.value(c.now) } else { 40.0 }
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
test "a list's rows as messages come: one all read through signals builds again only what read it, another all" {
  let k = TestRows::new()
  // (row 3 reads `mark`; a message on "rows-read" sets it, one on "rows-other" changes what is no signal)
  on_message_read("rows-read", fn(json, _) {
    k.mark.set(json.length())
    true
  })
  on_message("rows-other", fn(_, _) {  })
  let t = Tester::new(k.view(), w=320.0, h=420.0, platform=2)
  t.keep_parts(true)
  t.draw()
  t.frame()
  t.frame()
  let builds = k.builds.copy()
  t.post("rows-read", "12345")
  t.frame()
  assert_eq(t.messages_taken(), 1)
  assert_true(t.find("row 3 mark 5") is Some(_))
  assert_eq(k.builds[3], builds[3] + 1)
  assert_eq(k.builds[2], builds[2])
  assert_eq(k.builds[4], builds[4])
  assert_true(t.rows_kept() > 0, msg="\{t.rows_kept()}")
  t.post("rows-other", "x")
  t.frame()
  assert_eq(t.messages_taken(), 1)
  assert_eq(t.rows_kept(), 0)
  assert_eq(k.builds[2], builds[2] + 1)
}
