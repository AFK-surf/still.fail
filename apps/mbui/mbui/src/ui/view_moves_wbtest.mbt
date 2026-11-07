// A finger's moves on what of the window's tree holds it (view_host.mbt's view_moves): told it once a frame, the last
// one's place and moment, the others for how fast it goes; where a list is and how it flings after the same whatever
// frames came between, and a finger held on words in a list picks the word as it did, moved within the slop or not.

///|
/// A page's list 300 by 200 of 40 rows of words, picked with the pointer where `picks`, on a touch screen.
fn moves_list_tester(picks : Bool) -> (Tester, @view.Scroll) {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=2)
  t.check_looks(false)
  let s = @view.Scroll::list()
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.height(Is(Some(200.0))).width(Is(Some(300.0))) |> ignore
      if picks {
        words_picked(page)
      }
      page.scrolls_window(s, fn() { Array::makei(40, fn(i) { i }) }, est=22.0, fn(b, i) {
        b.box(fn(n) {
          n
          .words_runs(Is([plain("第 \{i} 段 "), bold("hello")]), ink=0x333333FFL, look={ size: 15.0, weight: 400, line: 22.0, wrap: true, tracking: @view.letters_own, balance: false })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  (t, s)
}

///|
/// A finger down on the list, moved up 5 points every 4 ms 24 times, a frame drawn after every `each`th move, let go,
/// the fling run out: where the list was as the finger went up and where it came to rest.
fn moved_with_frames(each : Int) -> (Double, Double) {
  let (t, s) = moves_list_tester(false)
  let tree = view_tree().unwrap()
  t.touch(0, 150.0, 180.0)
  t.draw()
  for k in 1..=24 {
    t.advance(4.0)
    t.touch(1, 150.0, 180.0 - 5.0 * k.to_double())
    if k % each == 0 {
      t.draw()
    }
  }
  t.draw()
  let held = s.at(tree)
  t.touch(2, 150.0, 60.0)
  t.run_for(3000.0)
  (held, s.at(tree))
}

///|
test "a finger's moves on a page's list: where it is as it goes up and where its fling ends the same, a frame after each move or after every third" {
  let each = moved_with_frames(1)
  let third = moved_with_frames(3)
  assert_true(each.0 > 50.0, msg="scrolled by the finger: \{each}")
  assert_true(each.1 > each.0, msg="flung on: \{each}")
  assert_eq(third, each)
}

///|
test "a finger held on words in a page's list, moved within the slop, a long press's time: the word under it picked; moved past it, the list scrolled and nothing picked" {
  let (t, _) = moves_list_tester(true)
  t.touch(0, 60.0, 11.0)
  t.draw()
  t.advance(30.0)
  t.touch(1, 61.0, 12.0)
  t.run_for(long_press_ms)
  assert_true(t.ctx().selected_text() != "", msg="picked after moving within the slop")
  t.touch(2, 61.0, 12.0)
  t.draw()
  let (t, s) = moves_list_tester(true)
  let tree = view_tree().unwrap()
  t.touch(0, 60.0, 100.0)
  t.draw()
  t.advance(30.0)
  t.touch(1, 60.0, 60.0)
  t.run_for(long_press_ms)
  assert_eq(t.ctx().selected_text(), "")
  assert_true(s.at(tree) > 0.0, msg="scrolled by the finger")
  t.touch(2, 60.0, 60.0)
  t.draw()
}
