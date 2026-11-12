// A page of a stack the window's tree holds made once as nodes (nav_view's `made`, Nav::made): made as it is put on,
// kept while it is on the stack (covered by another and come back to: the same nodes, what they hold as it was), what
// it becomes in place followed by those nodes, let go once as it has gone; back the stack's as its swipe from the left
// edge alone (a hold that went down in the middle, or on the edge of a page moved off it, no swipe back), the page's
// own back before the stack's; mixed with pages that are old views on the same stack.

///|
/// What the made pages did: how many times each kind was made, let go, and its taps counted by its own nodes.
priv struct MadeLog {
  made : Array[String]
  gone : Array[String]
  taps : Map[String, @signals.Signal[Int]]
  scrolls : Map[String, @view.Scroll]
  roots : Map[String, @view.NodeId]
  /// backs taken by a page's own (one named with "own" takes back itself)
  owns : Ref[Int]
  /// each page's time on top, as the stack gives it (what a picture it shows is asked for on)
  stints : Map[String, () -> Int]
  /// each page's times on top as what read it was told them (View::reacts), in order
  seen : Map[String, Array[Int]]
}

///|
/// A stack of pages named by words in the window's tree (390 × 844, a finger's): those starting "m" made once as nodes
/// (kind "m"): its name as it is now (what it becomes in place), a tap target counting its taps in a field of its own,
/// and 2000 high of words that scroll; the rest old views of their name.
fn made_stack() -> (Tester, Nav[String], MadeLog, Array[String]) {
  let left : Array[String] = []
  let log : MadeLog = { made: [], gone: [], taps: Map([]), scrolls: Map([]), roots: Map([]), owns: Ref(0), stints: Map([]), seen: Map([]) }
  let nav = Nav::new("a", on_leave=fn(p) { left.push(p) })
  let t = Tester::new(fn(_c) {  }, platform=1)
  t.check_looks(false)
  set_view_app(fn(root) {
    nav_view(
      root,
      nav,
      fn(c, p) { c.text(p, size=12.0) |> ignore },
      bg=fn() { 0xFFFFFFFFL },
      made=fn(p) {
        if p.has_prefix("m") {
          Some(
            (
              "m",
              fn(v, page, _under, stint, _k) {
                let first = @signals.untracked(page)
                log.made.push(first)
                let taps = @signals.signal(0)
                let scroll = @view.Scroll::new()
                log.taps[first] = taps
                log.scrolls[first] = scroll
                log.roots[first] = v.id()
                log.stints[first] = stint
                log.seen[first] = []
                v.reacts(stint, fn(s) { log.seen[first].push(s) })
                v.owns(fn() { log.gone.push(first) }) |> ignore
                if first.contains("own") {
                  v.box(fn(b) { b.over(Is(true)).takes_back(fn() { log.owns.val += 1 }) |> ignore }) |> ignore
                }
                v.box(fn(head) {
                  head
                  .height(Is(Some(60.0)))
                  .words(By(fn() { page() + " " + taps.get().to_string() }), look={ ..@view.words_plain, size: 12.0 })
                  .presses(Is(true))
                  .on_press(fn() { taps.set(taps.untracked() + 1) })
                  |> ignore
                })
                |> ignore
                v.box(fn(s) {
                  s.grow(Is(1.0)) |> ignore
                  s.scrolls(scroll, fn(body) { body.height(Is(Some(2000.0))) |> ignore }) |> ignore
                })
                |> ignore
              },
            ),
          )
        } else {
          None
        }
      },
    )
    |> ignore
  })
  t.draw()
  (t, nav, log, left)
}

///|
/// Moments on a test's clock after what was done: long after a fling of a finger's drag here set out (at rest by then),
/// a second on, half of one, and one a few frames into a push's slide (short of its end).
let long_after_ms : Double = 2000.0

///|
let a_second_ms : Double = 1000.0

///|
let half_a_second_ms : Double = 500.0

///|
let into_slide_ms : Double = 60.0

///|
/// Pushed, its slide run out.
fn pushed(t : Tester, nav : Nav[String], p : String) -> Unit {
  view_event(fn() { nav.push(p) })
  t.run_for(nav.rest() - t.time() + 16.0)
}

///|
test "window tree: a made page covered and come back to is the same nodes, what they hold as it was; let go once as it goes" {
  let (t, nav, log, left) = made_stack()
  pushed(t, nav, "m1")
  assert_eq(log.made, ["m1"])
  // (tapped twice on its head, scrolled 300 down)
  t.tap(100.0, 30.0)
  t.tap(100.0, 30.0)
  t.drag(200.0, 600.0, 200.0, 300.0)
  t.run_for(long_after_ms)
  let tree = view_tree().unwrap()
  let scrolled = log.scrolls["m1"].at(tree)
  assert_eq(log.taps["m1"].get(), 2)
  assert_true(scrolled > 100.0, msg="scrolled \{scrolled}")
  // (an old view's page over it, its slide over: it shows no more, its nodes kept)
  pushed(t, nav, "b")
  assert_eq(log.gone, [])
  assert_true(t.find("m1 2") is None)
  // (back to it: the same nodes, its taps and where it was scrolled as they were, made no more)
  t.back()
  t.run_for(nav.rest() - t.time() + 16.0)
  assert_eq(log.made, ["m1"])
  assert_eq(log.gone, [])
  assert_eq(log.scrolls["m1"].at(view_tree().unwrap()), scrolled)
  assert_true(t.find("m1 2") is Some(_))
  // (gone back off the stack: let go once its slide is over, the stack told once)
  t.back()
  t.run_for(nav.rest() - t.time() + 16.0)
  assert_eq(log.gone, ["m1"])
  assert_eq(left.filter(fn(p) { p == "m1" }).length(), 1)
}

///|
test "window tree: a made page become another of its kind in place: the same nodes follow what it is now, their state kept" {
  let (t, nav, log, _) = made_stack()
  pushed(t, nav, "m1")
  t.tap(100.0, 30.0)
  view_event(fn() { nav.become("m2") })
  t.draw()
  assert_eq(log.made, ["m1"])
  assert_true(t.find("m2 1") is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  // (become an old view's: its nodes let go once, the old view there)
  view_event(fn() { nav.become("c") })
  t.draw()
  assert_eq(log.gone, ["m1"])
  assert_true(t.find("c") is Some(_))
  // (and a made one again: made anew)
  view_event(fn() { nav.become("m3") })
  t.draw()
  assert_eq(log.made, ["m1", "m3"])
}

///|
test "window tree: a made page taken back by a swipe from its left edge alone, not from its middle nor from where it was moved off" {
  let (t, nav, _, _) = made_stack()
  pushed(t, nav, "m1")
  // (from its middle across: not back)
  t.drag(200.0, 400.0, 380.0, 400.0)
  t.run_for(a_second_ms)
  assert_eq(nav.depth(), 2)
  // (from its left edge across, most of the way: back)
  t.drag(4.0, 400.0, 300.0, 400.0)
  t.run_for(nav.rest() - t.time() + 16.0)
  assert_eq(nav.depth(), 1)
  // (pushed again and, while it still slides in, a finger down where its left edge is not yet: not back)
  view_event(fn() { nav.push("m2") })
  t.run_for(into_slide_ms)
  t.drag(4.0, 400.0, 300.0, 400.0)
  t.run_for(nav.rest() - t.time() + 16.0)
  assert_eq(nav.depth(), 2)
}

///|
test "window tree: back on a made page taken by what the page says takes it before the stack's" {
  let (t, nav, log, _) = made_stack()
  pushed(t, nav, "m-own")
  t.back()
  t.run_for(half_a_second_ms)
  assert_eq(log.owns.val, 1)
  assert_eq(nav.depth(), 2)
}

///|
test "window tree: a made page covered while the window changes height: come back to, how far it can scroll the window's as it is now, and followed after" {
  let (t, nav, log, _) = made_stack()
  pushed(t, nav, "m1")
  t.drag(200.0, 600.0, 200.0, 300.0)
  t.run_for(long_after_ms)
  let scroll = log.scrolls["m1"]
  let most_before = scroll.most()
  let at_before = scroll.at(view_tree().unwrap())
  assert_true(at_before > 0.0)
  pushed(t, nav, "b")
  // (made 300 shorter while covered: its room 300 more to scroll through)
  t.h = t.h - 300.0
  t.draw()
  t.back()
  t.run_for(nav.rest() - t.time() + 16.0)
  assert_eq(log.made, ["m1"])
  assert_eq(scroll.most(), most_before + 300.0)
  assert_eq(scroll.at(view_tree().unwrap()), at_before)
  // (and taller again while it shows: followed, as it changes)
  t.h = t.h + 500.0
  t.draw()
  assert_eq(scroll.most(), most_before - 200.0)
  assert_true(scroll.at(view_tree().unwrap()) <= scroll.most())
}

///|
test "window tree: a made page's time on top its own entry's: kept while another is over it, a new one as it is come back to" {
  let (t, nav, log, _) = made_stack()
  pushed(t, nav, "m1")
  let s1 = (log.stints["m1"])()
  pushed(t, nav, "m2")
  let s2 = (log.stints["m2"])()
  assert_true(s2 != s1)
  // (covered: its own still, not the one on top's)
  assert_eq((log.stints["m1"])(), s1)
  t.back()
  t.run_for(nav.rest() - t.time() + 16.0)
  let again = (log.stints["m1"])()
  assert_true(again != s1 && again != s2, msg="\{s1} \{s2} \{again}")
}

///|
test "window tree: a made page in the hand by a scripted run's drag (its steps taken after each frame's work, as a device's input between frames): each frame that drew it in the hand says a page held by a finger, none other does; at rest again, none" {
  let (t, nav, _, _) = made_stack()
  pushed(t, nav, "m1")
  let held = Ref(0)
  let missed : Array[Int] = []
  let said_free : Array[Int] = []
  // (in the hand as the frame was drawn: as the step of the frame before left it, nothing between the two)
  let drawn_held = Ref(nav.mode == 3)
  t.drive("drag 4 400 60 0 300\nwait 800\nexit", each=fn(_) {
    if drawn_held.val {
      held.val += 1
      if !g().page_in_hand {
        missed.push(g().frame_no)
      }
    } else if g().page_in_hand {
      said_free.push(g().frame_no)
    }
    drawn_held.val = nav.mode == 3
  })
  |> ignore
  assert_true(held.val > 3, msg="frames in the hand: \{held.val}")
  assert_eq((missed, said_free), ([], []))
  // (let go short of a third: back where it was, at rest, no page in the hand)
  assert_eq(nav.depth(), 2)
  assert_eq(nav.mode, 0)
  assert_true(!g().page_in_hand, msg="at rest")
}

///|
test "window tree: a made page come back to tells what reads its time on top the new one, by a back and by the stack's own pop" {
  let (t, nav, log, _) = made_stack()
  pushed(t, nav, "m1")
  pushed(t, nav, "m2")
  t.back()
  t.run_for(nav.rest() - t.time() + 16.0)
  let again = (log.stints["m1"])()
  assert_eq(log.seen["m1"].last(), Some(again), msg="by a back: \{Repr(log.seen["m1"])}")
  pushed(t, nav, "m3")
  view_event(fn() { nav.pop() |> ignore })
  t.run_for(nav.rest() - t.time() + 16.0)
  let then = (log.stints["m1"])()
  assert_true(then != again)
  assert_eq(log.seen["m1"].last(), Some(then), msg="by the stack's pop: \{Repr(log.seen["m1"])}")
  // (popped as an app pops it from outside any event: what reads its time on top told the new one all the same)
  pushed(t, nav, "m4")
  nav.pop() |> ignore
  t.run_for(nav.rest() - t.time() + 16.0)
  let last = (log.stints["m1"])()
  assert_true(last != then)
  assert_eq(log.seen["m1"].last(), Some(last), msg="by a pop from outside an event: \{Repr(log.seen["m1"])}")
}
