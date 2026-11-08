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

///|
test "chat find marks only the current occurrence across paragraphs, sweeping in and moving on" {
  for dark in [false, true] {
    let current = @signals.signal(0)
    let drawn = @signals.signal(@sf.stroke_ms / 2.0)
    let t = @ui.Tester::new(fn(c) {
      @sf.set_dark(Some(dark))
      @sf.begin(c) |> ignore
      let id = c.id("find-message")
      let (x, y) = match c.laid_rect(id) {
        Some((x, y, _, _)) => (x, y)
        None => (0.0, 0.0)
      }
      let box = c.box(id~, fn() {
        found_marker(c, "find-message", ["hit"], current.get(), drawn.get(), x, y)
        c.rich([@ui.plain("hit hit")], size=16.0) |> ignore
        c.rich([@ui.plain("another hit")], size=16.0) |> ignore
      })
      c.words(box, "find-message")
    }, w=500.0, h=100.0)
    t.frame()
    t.frame()
    let w = t.ctx().words_of("find-message").unwrap()
    let ranges = @sf.find_words(w.text, ["hit"])
    assert_eq(ranges.length(), 3)
    let first = w.rects(ranges[0].0, ranges[0].1)[0]
    let third = w.rects(ranges[2].0, ranges[2].1)[0]
    let ink = find_marker_ink(dark)
    let theme = @sf.theme()
    let page = @sf.over(theme.p.bg, ink)
    let code = @sf.over(theme.p.code_ground, ink)
    assert_true(@ui.contrast_ratio(theme.p.text, page) >= 4.5, msg="message text stays legible")
    assert_true(@ui.contrast_ratio(theme.p.accent_text, page) >= 4.5, msg="links stay legible")
    assert_true(@ui.contrast_ratio(theme.p.code_ink, code) >= 4.5, msg="code stays legible")
    let markers = fn() { t.drawn_rects().filter(fn(r) { r.4 == ink }) }
    assert_eq(markers().length(), 1)
    assert_true(markers()[0].2 > 0.0 && markers()[0].2 < first.2 + 4.0, msg="the marker sweeps in")
    assert_true((markers()[0].0 - first.0).abs() < 3.0, msg="the first match is current")
    drawn.set(@sf.stroke_ms)
    t.frame()
    assert_true((markers()[0].2 - first.2 - 4.0).abs() < 0.1, msg="the full marker stays")
    current.set(2)
    t.frame()
    assert_eq(markers().length(), 1)
    assert_true((markers()[0].0 - third.0).abs() < 3.0 && (markers()[0].1 - third.1).abs() < third.3, msg="the marker moved to the third match in the next paragraph")
    current.set(-1)
    t.frame()
    assert_eq(markers().length(), 0)
  }
  @sf.set_dark(None)
}

///|
test "chat find draws a wrapped current match across its lines in order" {
  let drawn = @signals.signal(@sf.stroke_ms)
  let t = @ui.Tester::new(fn(c) {
    let id = c.id("wrapped-match")
    let (x, y) = match c.laid_rect(id) {
      Some((x, y, _, _)) => (x, y)
      None => (0.0, 0.0)
    }
    let box = c.box(id~, fn() {
      found_marker(c, "wrapped-match", ["甲乙丙丁戊己庚辛壬癸"], 0, drawn.get(), x, y)
      c.rich([@ui.plain("甲乙丙丁戊己庚辛壬癸")], size=16.0, w=Px(40.0)) |> ignore
    })
    c.words(box, "wrapped-match")
  }, w=100.0, h=200.0)
  t.frame()
  t.frame()
  let w = t.ctx().words_of("wrapped-match").unwrap()
  let rects = w.rects(0, w.text.length())
  assert_true(rects.length() > 1)
  let ink = find_marker_ink(@sf.theme().dark)
  let markers = fn() { t.drawn_rects().filter(fn(r) { r.4 == ink }) }
  assert_eq(markers().length(), rects.length())
  drawn.set(@sf.stroke_ms / 4.0)
  t.frame()
  assert_true(markers().length() < rects.length(), msg="later lines wait for the sweep")
}
