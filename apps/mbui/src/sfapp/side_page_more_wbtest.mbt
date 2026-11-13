// The chats' list in the sidebar of a long account (sffixture's long-paged): the rows a page more brings are there at
// once, whole and seen in the frame they come, the list at its foot or gliding into them; only a chat that arrives (new,
// or moved up) opens where it is (motion_wbtest's "a chat with news goes to the top" holds that). One page asked as the
// list nears its foot, not one for each frame it is near (the coordinator of the migration's ruling, 2026-11-13: a page
// more's rows opening one by one from small and unseen, measured as they opened, asked four pages in one frame and showed
// the list's ground under a fling; side_fling_wbtest's 24 a second).

///|
/// The sidebar's list of the long account opened at rest, 840 by 900 on a touch tablet, its sidebar `side_pm_w` wide:
/// what the core was asked in `asked`.
fn side_pm_open(asked : Array[String]) -> @ui.Tester raise {
  new_run()
  let src = window_asks(asked)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=840.0, h=900.0, platform=2)
  let log = t.drive("system {\"size_class\":{\"width\":\"expanded\",\"height\":\"regular\"}}\n")
  assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  t.draw()
  t.run_for(window_opened_ms)
  t
}

///|
let side_pm_w : Double = 300.0

///|
/// The words of the sidebar's list drawn not whole between `top` and `foot` (seen less than half, or drawn under half
/// their line: a row opening from small, its words seen at its scale), as "words at y".
fn side_pm_unseen(t : @ui.Tester, top : Double, foot : Double) -> Array[String] {
  t
  .words()
  .filter(fn(w) { w.1 < side_pm_w && w.2 + w.4 > top && w.2 < foot && (w.5 < 0.5 || w.4 < 10.0) })
  .map(fn(w) { "\{w.0} at \{w.2.to_int()} seen \{w.5} tall \{w.4}" })
}

///|
/// How many pages more were asked in `asked` (its window grown: "window n" said after the first).
fn side_pm_pages(asked : Array[String]) -> Int {
  asked.filter(fn(a) { a.has_prefix("window ") }).length()
}

///|
test "touch tablet: the sidebar's chats flung into the rows of a page more: those rows whole and seen in every frame they show, one page asked as it nears its foot" {
  let asked : Array[String] = []
  let t = side_pm_open(asked)
  let at = t.time()
  let unseen : Array[String] = []
  let many : Array[String] = []
  for _ in 0..<3 {
    t.drag(150.0, 780.0, 150.0, 300.0, steps=3)
    let rest = t.time()
    while t.time() - rest < window_rest_ms - 1.0e-6 {
      let pages = side_pm_pages(asked)
      t.run_for(side_frame_ms)
      let more = side_pm_pages(asked) - pages
      if more > 1 {
        many.push("\{(t.time() - at).to_int()} ms: \{more} pages")
      }
      for u in side_pm_unseen(t, 160.0, 780.0) {
        if unseen.length() < 6 {
          unseen.push("\{(t.time() - at).to_int()} ms: \{u}")
        }
      }
    }
  }
  assert_true(side_pm_pages(asked) > 1, msg="no page more asked: \{Repr(asked)}")
  assert_eq(unseen, [])
  assert_eq(many, [])
}

///|
test "touch tablet: the sidebar's chats dragged slowly to their foot: the rows a page more brings there whole and seen in the frame they come" {
  let asked : Array[String] = []
  let t = side_pm_open(asked)
  let at = t.time()
  let unseen : Array[String] = []
  let mut came = false
  for _ in 0..<12 {
    let pages = side_pm_pages(asked)
    t.drag(150.0, 700.0, 150.0, 400.0, steps=6)
    t.run_for(side_frame_ms)
    if side_pm_pages(asked) > pages {
      came = true
      // (the frames from the one it came in on)
      for _ in 0..<12 {
        for u in side_pm_unseen(t, 160.0, 780.0) {
          if unseen.length() < 6 {
            unseen.push("\{(t.time() - at).to_int()} ms: \{u}")
          }
        }
        t.run_for(side_frame_ms)
      }
    }
    t.run_for(window_rest_ms)
  }
  assert_true(came, msg="no page more asked: \{Repr(asked)}")
  assert_eq(unseen, [])
}
