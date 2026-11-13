// Sizes steady (sizes_steady.mbt) in what a node of the window's tree scrolls (View::scrolls): what it holds measured
// where it stands in what scrolls, as a list's rows are in their list. Something come or gone at once over its rows is
// their jolt; the hand's scroll moving them all the same way is none of theirs.

///|
/// A column of the tree's 200 tall that scrolls, at the top of a window 400 by 300, holding (while `over` says so) a box
/// 100 tall over twelve rows of words 40 tall, each on a ground of its own (what sizes steady measures draws its own):
/// sizes steady said but not held (its faults read here, steady_faults).
fn steady_scroll_case(over : @signals.Signal[Bool]) -> (Tester, @view.Scroll) {
  let scroll = @view.Scroll::new()
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, words_over_held=false)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(v) {
      v
      .width(Is(Some(400.0)))
      .height(Is(Some(200.0)))
      .scrolls(scroll, fn(held) {
        held.show(at_once=true, fn() { over.get() }, fn(o) { o.box(fn(b) { b.height(Is(Some(100.0))) |> ignore }) |> ignore })
        for i in 0..<12 {
          held.box(fn(r) {
            r.width(Is(Some(160.0))).height(Is(Some(40.0))).ground(Is(0x336699FFL)).words(Is("第\{i}行")) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, scroll)
}

///|
/// `frames` frames drawn one at a time, the display's; what sizes steady finds in each, gathered.
fn steady_faults(t : Tester, frames : Int) -> Array[String] {
  let out = []
  for _ in 0..<frames {
    t.frame()
    out.append(g().sizes_steady_faults(t.fake.time, t.period))
  }
  out
}

///|
test "sizes steady in what a node of the tree's scrolls: a box gone at once over its rows a jolt of theirs; the same move by the wheel none" {
  // (gone at once, nobody scrolling: its rows 100 up in one frame)
  let over = @signals.signal(true, same=fn(a, b) { a == b })
  let (t, _) = steady_scroll_case(over)
  let before = steady_faults(t, 4)
  over.set(false)
  let gone = steady_faults(t, 4)
  // (the wheel 100 down over it, at once: its rows 100 up in one frame, by the hand)
  let still = @signals.signal(true, same=fn(a, b) { a == b })
  let (w, scroll) = steady_scroll_case(still)
  let rest = steady_faults(w, 4)
  w.wheel(80.0, 100.0, 100.0)
  let wheeled = steady_faults(w, 4)
  assert_eq((before, rest), ([], []))
  assert_true(gone.length() > 0, msg="gone at once over its rows: no jolt found")
  assert_eq((scroll.at(view_tree().unwrap()), wheeled), (100.0, []))
}

// Its bar's thumb (View::scroll_bar) goes along its track as far as the column is scrolled (Node's scroll_off): the
// wheel of a trackpad taking the column 100 down in one frame takes the thumb its share of that in the same frame, the
// hand's, as it takes the rows (as the sidebar's chats' list on 大屏 is wheeled while its bar still shows from the turn
// before, chats_window_wbtest.mbt). The thumb stepping with nothing done by the hand, what scrolls come to hold another
// height at once under it, is still a jolt.

///|
/// steady_scroll_case's column (the box 100 tall over its rows while `over` says so) with these bars, a mouse over it:
/// sizes steady said but not held (steady_faults).
fn steady_bar_case(over : @signals.Signal[Bool]) -> (Tester, @view.Scroll) {
  let scroll = @view.Scroll::new()
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0, words_over_held=false)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(v) {
      v
      .width(Is(Some(400.0)))
      .height(Is(Some(200.0)))
      .scrolls(scroll, bar=tree_scroll_bar(), fn(held) {
        held.show(at_once=true, fn() { over.get() }, fn(o) { o.box(fn(b) { b.height(Is(Some(100.0))) |> ignore }) |> ignore })
        for i in 0..<12 {
          held.box(fn(r) {
            r.width(Is(Some(160.0))).height(Is(Some(40.0))).ground(Is(0x336699FFL)).words(Is("第\{i}行")) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.move_to(80.0, 100.0)
  (t, scroll)
}

///|
test "sizes steady in what a node of the tree's scrolls with a bar: the wheel taking it 100 down at once while its bar shows, its thumb along with it, none; the thumb stepping as what it holds comes to another height at once, a jolt" {
  let thumb = fn(faults : Array[String]) { faults.filter(fn(f) { !f.contains("行") }) }
  // (the wheel 100 down: its bar coming in; out all of it a third of a second on, the wheel 100 down again at once)
  let still = @signals.signal(true, same=fn(a, b) { a == b })
  let (t, scroll) = steady_bar_case(still)
  let rest = steady_faults(t, 4)
  t.wheel(80.0, 100.0, 100.0)
  let came = steady_faults(t, 20)
  t.wheel(80.0, 100.0, 100.0)
  let wheeled = steady_faults(t, 8)
  let shown = thumb_opacity(t, 380.0).unwrap_or(0.0)
  let at = scroll.at(view_tree().unwrap())
  // (the same, and the box over its rows gone at once, nobody scrolling, as its bar shows: the thumb longer and further
  // down its track in one frame)
  let over = @signals.signal(true, same=fn(a, b) { a == b })
  let (w, _) = steady_bar_case(over)
  steady_faults(w, 4) |> ignore
  w.wheel(80.0, 100.0, 100.0)
  steady_faults(w, 20) |> ignore
  w.wheel(80.0, 100.0, 100.0)
  steady_faults(w, 8) |> ignore
  over.set(false)
  let gone = thumb(steady_faults(w, 8))
  assert_eq((at, shown > 0.0), (200.0, true))
  assert_eq((rest, came, wheeled), ([], [], []))
  assert_true(gone.length() > 0, msg="the thumb stepping with nothing done by the hand: no jolt found")
}

// An old list put elsewhere at once by the app (Ctx::list_scroll_to: put_at): what its rows hold at its top, a head
// stuck under its edge (Ctx::stick), steps in its row with the list's put, for no cause of its own; that same head
// stepping in its row with the list where it was is a jolt, as is a step of it a few frames after a put.

///|
/// An old list 300 tall in a window 400 by 300, ten rows 200 tall, each a head stuck at the list's top (`gap` over it
/// in its row) over its words; put at row `put` (its top 100 over the list's) as the next frame is built where `put` says
/// one: sizes steady said but not held (its faults read here, steady_faults).
fn steady_stuck_case(put : Ref[Int], gap : Ref[Double]) -> Tester {
  let t = Tester::new(
    fn(c) {
      c.list("stuck", 10, 200.0, fn(i) {
        c.column(h=Px(200.0), fn() {
          c.box(h=Px(gap.val), fn() {  }) |> ignore
          let head = c.column(fn() { c.text("第\{i}行的头", size=14.0, line=20.0) |> ignore })
          c.stick(head, 0.0)
          c.text("第\{i}行", size=14.0, line=20.0) |> ignore
        })
        |> ignore
      })
      |> ignore
      if put.val >= 0 {
        c.list_scroll_to("stuck", put.val, offset=100.0)
        put.val = -1
      }
    },
    w=400.0,
    h=300.0,
    words_over_held=false,
  )
  t.check_looks(false)
  t.draw()
  t
}

///|
test "sizes steady in an old list put elsewhere at once: its rows' stuck heads stepping with the put none; a head stepping with no put, or a few frames after one, a jolt" {
  // (put at row 0, its top 100 over the list's: row 0's head held at the list's top, 100 down in its row, in the put's
  // frame)
  let put = Ref(-1)
  let gap = Ref(0.0)
  let t = steady_stuck_case(put, gap)
  let rest = steady_faults(t, 4)
  put.val = 0
  t.stepped()
  let put_faults = steady_faults(t, 6)
  assert_eq((rest, put_faults), ([], []))
  // (the list where it was, a head 30 down in its row at once: its own step)
  let put = Ref(-1)
  let gap = Ref(0.0)
  let t = steady_stuck_case(put, gap)
  steady_faults(t, 4) |> ignore
  gap.val = 30.0
  t.stepped()
  let stepped = steady_faults(t, 4)
  assert_true(stepped.length() > 0, msg="a head stepping in its row with the list where it was: no jolt found")
  // (put, then four frames on a head 30 down in its row with no put: that one a jolt)
  let put = Ref(-1)
  let gap = Ref(0.0)
  let t = steady_stuck_case(put, gap)
  steady_faults(t, 4) |> ignore
  put.val = 0
  t.stepped()
  let after_put = steady_faults(t, 4)
  gap.val = 30.0
  t.stepped()
  let later = steady_faults(t, 4)
  assert_eq(after_put, [])
  assert_true(later.length() > 0, msg="a step a few frames after a put: no jolt found")
}

///|
/// A column 300 tall in a window 400 by 300: a box 150 tall over what scrolls (`open` showing it, making its way in),
/// and what scrolls taking the rest, holding six rows of words 40 tall on grounds of their own (the first while `first`
/// says so, gone at once): 240 in all, as much as it shows at first, more once the box over it has opened past 60. Its
/// Tester's sizes steady said but not held (steady_faults).
fn steady_squeezed_case(open : @signals.Signal[Bool], first : @signals.Signal[Bool]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, words_over_held=false)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(400.0))).height(Is(Some(300.0))) |> ignore
      col.show(fn() { open.get() }, fn(s) {
        s.box(fn(b) { b.height(Is(Some(150.0))).ground(Is(0x663399FFL)) |> ignore }) |> ignore
      })
      col.box(fn(v) {
        v.scrolls(@view.Scroll::new(), fn(held) {
          for i in 0..<6 {
            let row = fn(r : @view.View) {
              r.width(Is(Some(160.0))).height(Is(Some(40.0))).ground(Is(0x336699FFL)).words(Is("第\{i}行")) |> ignore
            }
            if i == 0 {
              held.show(at_once=true, fn() { first.get() }, fn(o) { o.box(row) |> ignore })
            } else {
              held.box(row) |> ignore
            }
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "sizes steady in what a node of the tree's scrolls: what it holds measured from its top all along, as what it holds comes to be taller than it; a row gone at once then still a jolt" {
  // (the box over it opening: what scrolls squeezed under it, its rows going down in the window with its top, what it
  // holds coming to be more than it shows half way; nothing of its rows' own)
  let open = @signals.signal(false, same=fn(a, b) { a == b })
  let first = @signals.signal(true, same=fn(a, b) { a == b })
  let t = steady_squeezed_case(open, first)
  let rest = steady_faults(t, 4)
  open.set(true)
  let squeezed = steady_faults(t, 40).filter(fn(f) { f.contains("行") })
  // (the same, and its first row gone at once as the box over it is half way open: the rows under it up 40 in one frame)
  let open = @signals.signal(false, same=fn(a, b) { a == b })
  let first = @signals.signal(true, same=fn(a, b) { a == b })
  let w = steady_squeezed_case(open, first)
  steady_faults(w, 4) |> ignore
  open.set(true)
  steady_faults(w, 10) |> ignore
  first.set(false)
  let jolted = steady_faults(w, 30).filter(fn(f) { f.contains("行") })
  assert_eq((rest, squeezed), ([], []))
  assert_true(jolted.length() > 0, msg="a row gone at once half way: no jolt found")
}

///|
test "sizes steady: a dead stop said as the frame it stops on is drawn, a turn back through rest by what it slowed before, not by what comes after" {
  let p = 1000.0 / 60.0
  // (judged each frame as a run's frames are, on what was drawn up to then)
  let said = fn(ys : Array[Double]) {
    let all = ys.mapi(fn(i, y) { (i.to_double() * p, i.to_double() * p, y) })
    let mut dead = false
    for k in 1..=all.length() {
      if sizes_steady_fault(all[:k].to_owned(), p, turned=-1.0e9).0 is Some(s) && s.contains("stopped dead") {
        dead = true
      }
    }
    dead
  }
  // (at speed, then at rest)
  assert_true(said([0.0, -30.0, -59.0, -59.5, -59.5]))
  // (a sheet closed as it grows: up 29 a frame, then down, its turn between two frames: slowing 1 a frame, then 31.8
  // at once, whatever it does after; the coordinator of the migration, 2026-11-11)
  assert_true(said([0.0, -30.0, -59.0, -56.2, -11.4]))
  // (turned back through rest between two frames slowing at one rate: none)
  assert_true(!said([0.0, -30.0, -50.0, -60.0, -60.0, -50.0, -30.0]))
}

// A page's list's foot (View::scrolls_window's `foot`) stands pinned at the foot of the scroller, over what scrolls,
// not inside `scroll_held`: what stands at the foot's bottom stays in place in the window when room grows over it inside
// the foot, and stays in place when rows measured above what shows correct the list's scroll (`Tree::scroll_corrected`),
// while a real step inside the foot still jolts.

///|
/// A page's list 400 by 200 of eighty rows 50 tall (`est` 20, so scrolling up corrects what was counted above what
/// shows), following its foot, with a pinned foot holding `over` room above a 40-tall bar "脚底" and `under` room
/// below it: sizes steady said but not held (`steady_faults`).
fn steady_list_foot_case(over : @signals.Signal[Double], under : @signals.Signal[Bool]) -> Tester {
  let scroll = @view.Scroll::list()
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, words_over_held=false)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
      col.scrolls_window(
        scroll,
        fn() { Array::makei(80, fn(i) { i }) },
        est=20.0,
        follows=fn() { true },
        foot=fn(f) {
          f.box(fn(g) { g.height(By(fn() { Some(over.get()) })).shrink(Is(0.0)) |> ignore }) |> ignore
          f.box(fn(b) {
            b.width(Is(Some(160.0))).height(Is(Some(40.0))).shrink(Is(0.0)).ground(Is(0x336699FFL)).words(Is("脚底"))
            |> ignore
          })
          |> ignore
          f.show(at_once=true, fn() { under.get() }, fn(u) {
            u.box(fn(g) { g.height(Is(Some(40.0))).shrink(Is(0.0)) |> ignore }) |> ignore
          })
        },
        fn(b, k) {
          b.width(Is(Some(160.0))).height(Is(Some(50.0))).ground(Is(0x445566FFL)).words(Is("第\{k}行")) |> ignore
        },
      )
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "sizes steady in a page's list's pinned foot: room growing over what stands at its bottom, or the list correcting its scroll as it reads up, is no jolt; a step of what is in the foot still is" {
  // (room growing 60 at once over "脚底" inside the pinned foot: the foot's top goes up 60, "脚底" stays at y=160)
  let over = @signals.signal(0.0, same=fn(a, b) { a == b })
  let under = @signals.signal(false, same=fn(a, b) { a == b })
  let t = steady_list_foot_case(over, under)
  let rest = steady_faults(t, 4)
  over.set(60.0)
  let grown = steady_faults(t, 4).filter(fn(f) { f.contains("脚底") })
  // (scrolled up into rows taller than `est`, correcting the list's scroll: "脚底" stays pinned at y=160)
  let over2 = @signals.signal(0.0, same=fn(a, b) { a == b })
  let under2 = @signals.signal(false, same=fn(a, b) { a == b })
  let r = steady_list_foot_case(over2, under2)
  steady_faults(r, 4) |> ignore
  r.move_to(80.0, 80.0)
  r.wheel(80.0, 80.0, -100.0)
  let read_up = steady_faults(r, 12).filter(fn(f) { f.contains("脚底") })
  let corrected = view_tree().unwrap().lists_reckoned()[0].3
  // (room under "脚底" in the foot gone at once with no hand input: "脚底" drops 40 in one frame in the window)
  let over3 = @signals.signal(0.0, same=fn(a, b) { a == b })
  let under3 = @signals.signal(true, same=fn(a, b) { a == b })
  let j = steady_list_foot_case(over3, under3)
  steady_faults(j, 4) |> ignore
  under3.set(false)
  let stepped = steady_faults(j, 4).filter(fn(f) { f.contains("脚底") })
  assert_eq((rest, grown, read_up), ([], [], []))
  assert_true(corrected.abs() > 0.5, msg="expected non-zero scroll correction reading up, got \{corrected}")
  assert_true(stepped.length() > 0, msg="a real step in the pinned foot: no jolt found")
}

// A page's list put elsewhere at once (Scroll::put: brought to a block, as a chat's page goes to a message): its bar's
// thumb, moved by the column's offset alone, goes there in the frame that takes the put, as far along its track and as
// long as what the list holds came to in that layout, as it does in a frame the hand scrolled it. No jolt of the
// thumb's: the put's (rows_steady.mbt takes a list put elsewhere at once so). What the thumb does with nothing put and
// nothing done by the hand is still judged (the test above, a plain column's).

///|
/// A page's list 400 by 200, at the top of a window 400 by 300, of eighty rows 50 tall (`est` 30: what is measured
/// comes out another height than counted) with these bars, a mouse over it: sizes steady said but not held
/// (steady_faults); its scroll.
fn steady_list_put_case() -> (Tester, @view.Scroll) {
  let scroll = @view.Scroll::list()
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0, words_over_held=false)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
      col.scrolls_window(scroll, fn() { Array::makei(80, fn(i) { i }) }, est=30.0, bar=tree_scroll_bar(), fn(b, k) {
        b.width(Is(Some(160.0))).height(Is(Some(50.0))).ground(Is(0x445566FFL)).words(Is("第\{k}行")) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.move_to(80.0, 100.0)
  (t, scroll)
}

///|
test "sizes steady: a page's list put elsewhere at once while its bar shows, the thumb there and as long as the list came to in the put's frame, none said of it" {
  let thumb = fn(faults : Array[String]) { faults.filter(fn(f) { !f.contains("行") }) }
  let (t, scroll) = steady_list_put_case()
  steady_faults(t, 4) |> ignore
  // (the wheel 100 down: its bar coming in; the hand's frames gone by, the bar out)
  t.wheel(80.0, 100.0, 100.0)
  let came = thumb(steady_faults(t, 20))
  let shown = thumb_opacity(t, 380.0).unwrap_or(0.0)
  let before = scroll.at(view_tree().unwrap())
  // (put 2000 down at once, nobody's hand on it: the thumb down its track in one frame)
  view_event(fn() { scroll.put(2000.0) })
  let put = thumb(steady_faults(t, 6))
  let after = scroll.at(view_tree().unwrap())
  // (each by its own line, all of what was found said: the scroll from and to, the thumb as it came in, its opacity, what
  // was said of it after the put)
  let found = "scrolled \{before} to \{after}; came \{Repr(came)}; shown \{shown}; put \{Repr(put)}"
  assert_true(came.is_empty(), msg="the thumb coming in said: " + found)
  assert_true(shown > 0.0, msg="the thumb not shown at the put: " + found)
  assert_true(after - before > 1000.0, msg="not put: " + found)
  assert_true(put.is_empty(), msg="the thumb said in the put's frame: " + found)
}

// A page's list's keys changed by data (keys put in at its head as it is read up: what it holds much longer in one
// frame) take its bar's thumb shorter and elsewhere along its track in the frame that takes them: where the reader is
// in what the list holds changes then, as it does in the frame the list is put at once (the coordinator of the
// migration, 2026-11-13). No jolt of the thumb's. The thumb stepping with nothing put, nothing done by the hand and no
// keys changed is still one (a plain column's, above).

///|
/// A page's list 400 by 200 at the top of a window 400 by 300, of the keys `keys` says, each a row 50 tall (counted so)
/// with these bars, a mouse over it: sizes steady said but not held (steady_faults); its scroll.
fn steady_list_keys_case(keys : @signals.Signal[Array[Int]]) -> (Tester, @view.Scroll) {
  let scroll = @view.Scroll::list()
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0, words_over_held=false)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
      col.scrolls_window(scroll, fn() { keys.get() }, est=50.0, bar=tree_scroll_bar(), fn(b, k) {
        b.width(Is(Some(160.0))).height(Is(Some(50.0))).ground(Is(0x445566FFL)).words(Is("第\{k}行")) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.move_to(80.0, 100.0)
  (t, scroll)
}

///|
test "sizes steady: a page's list read up, its bar showing, keys put in at its head by data, the thumb shorter and elsewhere in that frame: none said of it" {
  let thumb = fn(faults : Array[String]) { faults.filter(fn(f) { !f.contains("行") }) }
  let keys = @signals.signal(Array::makei(80, fn(i) { i }), same=fn(a, b) { a == b })
  let (t, scroll) = steady_list_keys_case(keys)
  steady_faults(t, 4) |> ignore
  // (read 1000 down by the wheel: its bar coming in; the hand's frames gone by, the bar out)
  t.wheel(80.0, 100.0, 1000.0)
  let came = thumb(steady_faults(t, 20))
  let shown = thumb_opacity(t, 380.0).unwrap_or(0.0)
  let before = scroll.at(view_tree().unwrap())
  // (forty keys put in at its head, nobody's hand on it: 2000 more over what is read, the thumb shorter and further
  // down its track in one frame)
  view_event(fn() { keys.set(Array::makei(120, fn(i) { i - 40 })) })
  let put = thumb(steady_faults(t, 6))
  let after = scroll.at(view_tree().unwrap())
  let found = "scrolled \{before} to \{after}; came \{Repr(came)}; shown \{shown}; put \{Repr(put)}"
  assert_true(came.is_empty(), msg="the thumb coming in said: " + found)
  assert_true(shown > 0.0, msg="the thumb not shown as the keys come: " + found)
  assert_true(after - before > 1000.0, msg="what is read not held as the keys come over it: " + found)
  assert_true(put.is_empty(), msg="the thumb said in the frame the keys came: " + found)
}

///|
/// steady_list_keys_case's list, its row 5 250 tall where `tall` says so (50 else), at once.
fn steady_list_tall_case(keys : @signals.Signal[Array[Int]], tall : @signals.Signal[Bool]) -> (Tester, @view.Scroll) {
  let scroll = @view.Scroll::list()
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0, words_over_held=false)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
      col.scrolls_window(scroll, fn() { keys.get() }, est=50.0, bar=tree_scroll_bar(), fn(b, k) {
        b
        .width(Is(Some(160.0)))
        .height(By(fn() { Some(if k == 5 && tall.get() { 250.0 } else { 50.0 }) }))
        .ground(Is(0x445566FFL))
        .words(Is("第\{k}行"))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.move_to(80.0, 100.0)
  (t, scroll)
}

///|
test "sizes steady: a page's list given the same keys again as another array while its bar shows, the thumb stepping as a row it shows comes to another height at once: a jolt still" {
  let thumb = fn(faults : Array[String]) { faults.filter(fn(f) { !f.contains("行") }) }
  // (every array its keys are given told on, the same keys in it or not)
  let keys = @signals.signal(Array::makei(12, fn(i) { i }), same=fn(a, b) { physical_equal(a, b) })
  let tall = @signals.signal(false, same=fn(a, b) { a == b })
  let (t, scroll) = steady_list_tall_case(keys, tall)
  steady_faults(t, 4) |> ignore
  // (twelve rows, 600 in all: read 200 down by the wheel, its bar coming in; the hand's frames gone by, the bar out)
  t.wheel(80.0, 100.0, 200.0)
  let came = thumb(steady_faults(t, 20))
  let shown = thumb_opacity(t, 380.0).unwrap_or(0.0)
  let before = scroll.at(view_tree().unwrap())
  // (the same keys given again, and row 5, in what shows, 200 taller at once, nobody's hand on it: 800 in all, the thumb
  // a quarter shorter and higher up its track in one frame, for nothing of the keys')
  view_event(fn() {
    keys.set(Array::makei(12, fn(i) { i }))
    tall.set(true)
  })
  let stepped = thumb(steady_faults(t, 6))
  let after = scroll.at(view_tree().unwrap())
  let found = "scrolled \{before} to \{after}; came \{Repr(came)}; shown \{shown}; stepped \{Repr(stepped)}"
  assert_true(came.is_empty(), msg="the thumb coming in said: " + found)
  assert_true(shown > 0.0, msg="the thumb not shown as the row grows: " + found)
  assert_true(stepped.length() > 0, msg="the thumb stepping with the same keys given again: no jolt found: " + found)
}
