///|
test "every match is stroked when a message has more than twelve" {
  let text = Array::make(16, "hit").join(" ")
  let drawn = @signals.signal(found_draw_ms - @sf.stroke_ms / 2.0)
  let t = @ui.Tester::new(fn(c) {
    let id = c.id("many-matches")
    let (x, y) = match c.laid_rect(id) {
      Some((x, y, _, _)) => (x, y)
      None => (0.0, 0.0)
    }
    let box = c.box(id~, fn() {
      found_strokes(c, "many-matches", ["hit"], drawn.get(), x, y)
      c.rich([@ui.plain(text)], size=10.0) |> ignore
    })
    c.words(box, "many-matches")
  }, w=1000.0, h=100.0)
  t.frame()
  t.frame()
  let words = t.ctx().words_of("many-matches").unwrap()
  let ranges = @sf.find_words(words.text, ["hit"])
  assert_eq(ranges.length(), 16)
  let (a, b) = ranges[15]
  let (x, y, w, h) = words.rects(a, b)[0]
  assert_true(t.drawn_lines().iter().any(fn(l) {
    l.4 == @sf.message_stroke.width && l.0 >= x - 3.0 && l.0 <= x + w + 3.0 && l.1 >= y && l.1 <= y + h + 8.0
  }), msg="the last match has not started drawing in")
  drawn.set(found_draw_ms)
  t.frame()
  assert_true(t.drawn_lines().iter().any(fn(l) {
    l.4 == @sf.message_stroke.width && l.2 >= x + w && l.2 <= x + w + 3.0 && l.3 >= y && l.3 <= y + h + 8.0
  }), msg="the last match's stroke did not finish")
}

///|
test "multiple matches on one search result line are each stroked under their own word" {
  let text = "hit hit hit"
  let t = @ui.Tester::new(fn(c) {
    @sf.found_line(c, "many", text, [(0, 3), (4, 7), (8, 11)], @sf.theme().chat_list.found.words, @sf.theme().p.text)
  }, w=500.0, h=100.0)
  t.run_for(@sf.strokes_ms(3))
  let words = t.ctx().words_of("search/found/many").unwrap()
  let (x, y, w, h) = words.rects(8, 11)[0]
  assert_true(t.drawn_lines().iter().any(fn(l) {
    l.4 == @sf.line_stroke.width && l.0 >= x - 3.0 && l.0 <= x + w + 3.0 && l.1 >= y && l.1 <= y + h + 6.0
  }), msg="the third match has no stroke underneath it")
}
