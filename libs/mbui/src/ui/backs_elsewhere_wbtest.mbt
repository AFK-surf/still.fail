// A page made once whose stack takes no back, swiped from its edge: each step to what takes back outside it (Nav's
// backs_over handing on), from where the finger went down in the window, whatever moved the page before the swipe was
// taken over.

///|
test "a page made once, back not its stack's: its edge's swipe handed to what takes back over the window, begun where the finger went down, though what holds the page moved and grew before it was taken over" {
  let nav = Nav::new("a")
  let shift = @signals.signal(100.0, same=fn(a, b) { a == b })
  let grow = @signals.signal(1.0, same=fn(a, b) { a == b })
  let steps : Array[String] = []
  let t = Tester::new(fn(_c) {  }, w=600.0, h=400.0, platform=1)
  set_view_app(fn(root) {
    // (what takes back over the window: each step it is told, x from its left)
    root.box(fn(b) {
      b
      .over(Is(true))
      .follows_back(fn(s) {
        steps.push(
          match s {
            Began(x, _) => "began \{x}"
            Moved(x, _) => "moved \{x}"
            LetGo(x, _) => "let go \{x}"
            CalledOff => "off"
            Back => "back"
          },
        )
      })
      |> ignore
    })
    |> ignore
    // (the page, in what holds it moved across and grown as `shift` and `grow` say)
    root.box(fn(h) {
      h.over(Is(true)).offset(By(fn() { (shift.get(), 0.0) })).scale(By(fn() { grow.get() })) |> ignore
      h.box(fn(m) {
        m.width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
        nav.backs_over(m, nav.pages[0].serial, 20.0, fn() {  })
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  // (down 5 into the page's edge: 105 in the window)
  t.touch(0, 105.0, 50.0)
  // (what holds it moved 40 across and grown before the finger goes past the slop)
  shift.set(140.0)
  grow.set(1.25)
  t.draw()
  t.advance(input_step_ms)
  t.touch(1, 125.0, 50.0)
  t.advance(input_step_ms)
  t.touch(1, 185.0, 50.0)
  t.advance(input_step_ms)
  t.touch(2, 185.0, 50.0)
  t.run_for(move_most_ms)
  assert_true(steps.length() >= 3 && steps[0] == "began 105" && steps.last() == Some("let go 185"), msg="\{Repr(steps)}")
}
