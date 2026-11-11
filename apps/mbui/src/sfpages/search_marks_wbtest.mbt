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
/// The highlighters drawn in `ink` (Ctx::shapes' bands of them put back together): a box each, top to bottom.
fn marker_boxes(t : @ui.Tester, ink : Int64) -> Array[(Double, Double, Double, Double)] {
  let out : Array[(Double, Double, Double, Double)] = []
  let bands = t.drawn_shapes().filter(fn(b) { b.5 == ink })
  bands.sort_by(fn(p, q) { p.1.compare(q.1) })
  for b in bands {
    // (the box above it it meets: the same shape's band before it)
    match out.search_by(fn(o) { b.1 <= o.1 + o.3 + 0.5 && b.0 < o.0 + o.2 && b.0 + b.2 > o.0 }) {
      Some(k) => {
        let (x, y, w, h) = out[k]
        let l = dmin(x, b.0)
        let r = dmax(x + w, b.0 + b.2)
        out[k] = (l, y, r - l, dmax(y + h, b.1 + b.3) - y)
      }
      None => out.push((b.0, b.1, b.2, b.3))
    }
  }
  out
}

///|
test "chat find colours in every match, still, and strokes only the current occurrence, drawn in as it moves" {
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
        found_scribbles(c, "find-message", ["hit"], x, y)
        found_strokes(c, "find-message", ["hit"], drawn.get(), x, y, only=current.get())
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
    let rects = ranges.map(fn(r) { w.rects(r.0, r.1)[0] })
    let ink = find_marker_ink(dark)
    let theme = @sf.theme()
    let page = @sf.over(theme.p.bg, ink)
    let code = @sf.over(theme.p.code_ground, ink)
    assert_true(@ui.contrast_ratio(theme.p.text, page) >= 4.5, msg="message text stays legible")
    assert_true(@ui.contrast_ratio(theme.p.accent_text, page) >= 4.5, msg="links stay legible")
    assert_true(@ui.contrast_ratio(theme.p.code_ink, code) >= 4.5, msg="code stays legible")
    let markers = fn() { marker_boxes(t, ink) }
    // every match coloured in, whole from the first frame: nothing of it waits on the stroke
    let coloured = fn(rect : (Double, Double, Double, Double)) {
      markers().iter().any(fn(m) { (m.0 - rect.0).abs() < 4.0 && (m.2 - rect.2 - 4.0).abs() < 3.0 && m.1 > rect.1 && m.1 < rect.1 + rect.3 })
    }
    assert_eq(markers().length(), 3, msg="\{Repr(markers())}")
    assert_true(rects.iter().all(coloured), msg="\{Repr(markers())} \{Repr(rects)}")
    let strokes_under = fn(rect : (Double, Double, Double, Double)) {
      t.drawn_lines().iter().any(fn(l) { l.5 == theme.p.accent && l.0 >= rect.0 - 3.0 && l.0 <= rect.0 + rect.2 + 3.0 && l.1 >= rect.1 && l.1 <= rect.1 + rect.3 + 8.0 })
    }
    assert_true(strokes_under(rects[0]) && !strokes_under(rects[1]) && !strokes_under(rects[2]), msg="the current occurrence's stroke alone")
    let reach = fn() {
      t.drawn_lines().filter(fn(l) { l.5 == theme.p.accent }).fold(init=0.0, fn(m, l) { dmax(m, dmax(l.0, l.2)) })
    }
    assert_true(reach() < rects[0].0 + rects[0].2, msg="the stroke draws in")
    drawn.set(@sf.stroke_ms)
    t.frame()
    // the colouring in short of the stroke under it: the stroke shows whole
    let m = markers().iter().find_first(fn(m) { (m.0 - rects[0].0).abs() < 4.0 }).unwrap()
    let stroke_top = t.drawn_lines()
      .filter(fn(l) { l.5 == theme.p.accent && l.0 >= m.0 - 1.0 && l.2 <= m.0 + m.2 + 1.0 })
      .fold(init=1.0e9, fn(top, l) { dmin(top, dmin(l.1, l.3) - l.4 / 2.0) })
    assert_true(stroke_top < 1.0e9, msg="the current match has its stroke")
    // (its bands are whole pixels, a pixel of room round its edges: the scribble itself ends marker_below under the
    // baseline, short of the stroke's highest, 0.75)
    assert_true(m.1 + m.3 <= stroke_top + 1.0, msg="the colouring in reaches over the stroke: \{Repr(m)} \{stroke_top}")
    current.set(2)
    t.frame()
    assert_true(!strokes_under(rects[0]) && strokes_under(rects[2]), msg="the stroke moved to the third match in the next paragraph")
    assert_eq(markers().length(), 3, msg="the colouring in stays")
    current.set(-1)
    t.frame()
    assert_true(!rects.iter().any(strokes_under), msg="no stroke in a message the reader is not at")
    assert_eq(markers().length(), 3)
  }
  @sf.set_dark(None)
}

///|
test "chat find colours in a wrapped match across its lines" {
  let t = @ui.Tester::new(fn(c) {
    let id = c.id("wrapped-match")
    let (x, y) = match c.laid_rect(id) {
      Some((x, y, _, _)) => (x, y)
      None => (0.0, 0.0)
    }
    let box = c.box(id~, fn() {
      found_scribbles(c, "wrapped-match", ["甲乙丙丁戊己庚辛壬癸"], x, y)
      c.rich([@ui.plain("甲乙丙丁戊己庚辛壬癸")], size=16.0, w=Px(40.0)) |> ignore
    })
    c.words(box, "wrapped-match")
  }, w=100.0, h=200.0)
  t.frame()
  t.frame()
  let w = t.ctx().words_of("wrapped-match").unwrap()
  let rects = w.rects(0, w.text.length())
  assert_true(rects.length() > 1)
  assert_eq(marker_boxes(t, find_marker_ink(@sf.theme().dark)).length(), rects.length())
}

///|
test "a highlighter scribbled up and down: within its box, the strokes close enough to cover" {
  for seed in 0..<6 {
    let (w, h) = (60.0, 16.0)
    let pen = marker_pen(h)
    let whole = marker_scribble(w, h, seed)
    let xs = []
    let ys = []
    for k in 0..<(whole.length() / 2) {
      xs.push(whole[k * 2])
      ys.push(whole[k * 2 + 1])
    }
    // its tip inside the box
    assert_true(xs.iter().all(fn(x) { x >= pen / 2.0 - 0.001 && x <= w - pen / 2.0 + 0.001 }))
    assert_true(ys.iter().all(fn(y) { y >= pen / 2.0 - 0.001 && y <= h - pen / 2.0 + 0.001 }))
    // up and down, left to right, each stroke within a tip's width of the one before
    for k in 1..<xs.length() {
      assert_true((ys[k] - ys[k - 1]).abs() > h / 2.0, msg="stroke \{k} goes up or down")
      assert_true(xs[k] >= xs[k - 1] - 0.001 && xs[k] - xs[k - 1] <= pen, msg="stroke \{k} \{Repr(xs)}")
    }
    assert_true(xs[xs.length() - 1] > w - pen, msg="it reaches the band's end")
  }
}
