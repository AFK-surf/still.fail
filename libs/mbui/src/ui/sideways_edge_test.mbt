// Words picked with the pointer in a box scrolled sideways (a code block's line, a wide table): held past its start or
// its end, it scrolls on toward the pointer, picked as they come, as a browser's overflowing box does.

///|
let sideways_edge_line : String = "let total = items.map(fn(x) { x.price * x.count }).fold(init=0, fn(a, b) { a + b }) // the end"

///|
/// Long enough for the box to be brought on at select_edge's pace for 50 px past its end to the line's end.
let sideways_edge_to_end_ms : Double = 5000.0

///|
test "desktop: words picked in a box scrolled sideways, the pointer held past its end: it scrolls on toward the pointer till the line's end, picked as they come; held past its start, back; let go, still" {
  let t = @ui.Tester::new(
    fn(c) {
      c.mouse_drags_lists(false)
      c.selectable(fn() {
        c.column(w=Fill(1.0), fn() {
          c.box(w=Px(200.0), fn() {
            c.sideways("code", fn() { c.rich([@ui.span(sideways_edge_line, mono=true)], size=12.0, wrap=false) |> ignore })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
    },
    w=300.0,
    h=200.0,
  )
  t.draw()
  let (x, y, _, h) = t.rect_of(sideways_edge_line).unwrap()
  t.press_at(x + 0.5, y + h / 2.0)
  // (held past its end, the pointer still: it scrolls on by itself, more picked as it does)
  t.move_to(250.0, y + h / 2.0)
  let s0 = t.ctx().sideways_at("code")
  let p0 = t.ctx().selected_text()
  t.run_for(@ui.scrollbar_hold_ms)
  let s1 = t.ctx().sideways_at("code")
  let p1 = t.ctx().selected_text()
  assert_true(s1 > s0 + 40.0, msg="scrolled on: \{s0} \{s1}")
  assert_true(p1.length() > p0.length() && p1.has_prefix(p0), msg="picked on: \{p0} -> \{p1}")
  // (on till the line's end: all of it picked)
  t.run_for(sideways_edge_to_end_ms)
  assert_eq(t.ctx().selected_text(), sideways_edge_line)
  // (back in it: still)
  t.move_to(150.0, y + h / 2.0)
  t.draw()
  let s2 = t.ctx().sideways_at("code")
  t.run_for(@ui.scrollbar_hold_ms)
  assert_eq(t.ctx().sideways_at("code"), s2)
  // (held past its start: back toward it)
  t.move_to(-20.0, y + h / 2.0)
  t.run_for(@ui.scrollbar_hold_ms)
  let s3 = t.ctx().sideways_at("code")
  assert_true(s3 < s2, msg="back: \{s2} \{s3}")
  // (let go: still where it is)
  t.release(-20.0, y + h / 2.0)
  let s4 = t.ctx().sideways_at("code")
  t.run_for(@ui.scrollbar_hold_ms + @ui.scrollbar_fade_ms)
  assert_eq(t.ctx().sideways_at("code"), s4)
}

///|
test "desktop: words in a box scrolled sideways, scrolled on: a press and a drag pick the words drawn under the pointer" {
  let t = @ui.Tester::new(
    fn(c) {
      c.mouse_drags_lists(false)
      c.selectable(fn() {
        c.column(w=Fill(1.0), fn() {
          c.box(w=Px(200.0), fn() {
            c.sideways("code", fn() { c.rich([@ui.span(sideways_edge_line, mono=true)], size=12.0, wrap=false) |> ignore })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
    },
    w=300.0,
    h=200.0,
  )
  t.draw()
  let (x, y, w, h) = t.rect_of(sideways_edge_line).unwrap()
  let per = w / sideways_edge_line.length().to_double()
  // (scrolled on by the wheel, 20 glyphs' worth)
  t.wheel_with(x + 20.0, y + h / 2.0, per * 20.0, 0.0, 0)
  t.run_for(@ui.wheel_ease_ms)
  let s = t.ctx().sideways_at("code")
  assert_true(s > 0.0, msg="scrolled: \{s}")
  // (from the glyph drawn at the box's start to five on)
  t.press_at(x + per * 0.25, y + h / 2.0)
  t.move_to(x + per * 5.0 + per * 0.25, y + h / 2.0)
  t.release(x + per * 5.0 + per * 0.25, y + h / 2.0)
  let first = (s / per).round().to_int()
  let want = sideways_edge_line.exact_view(start=first, end=first + 5).to_owned()
  assert_eq(t.ctx().selected_text(), want)
}
