// Formula/image runs share text's layout, selection and link handling. Geometry comes from the caller, in em.

///|
fn drawing_runs() -> Array[@ui.Run] {
  let d : @ui.InlineDrawing = {
    width: 2.0, height: 1.5, baseline: 1.0,
    paths: [ [ ([0.0,0.0,2.0,0.0,2.0,1.5,0.0,1.5],true) ] ], words: [],
  }
  [@ui.plain("a "), @ui.span("x + y", drawing=Some(d), link="formula"), @ui.plain(" b")]
}

///|
test "a drawing uses its intrinsic width and leaves its alternative whole on a line" {
  let went = []
  let t = rich_view(drawing_runs(), 35.0, on_link=fn(h) { went.push(h) })
  let lines = t.lines_of("a ")
  assert_eq(lines.join(""), "a x + y b")
  assert_true(lines.iter().any(fn(s) { s.contains("x + y") }))
  let rs = t.run_rects("x + y")
  assert_eq(rs.length(),1)
  assert_eq(rs[0].2,20.0)
  let (x,y,w,h) = rs[0]
  t.tap(x+w/2.0,y+h/2.0)
  assert_eq(went,["formula"])
  let (lay,_,_) = t.rich_of("a ").unwrap()
  let selected = lay.rects(2,7)
  assert_eq(selected.length(),1)
  assert_eq(selected[0].2,20.0)
  assert_true(lay.offset_at(selected[0].0+1.0,selected[0].1+1.0) == 2)
  assert_true(lay.offset_at(selected[0].0+19.0,selected[0].1+1.0) == 7)
}

///|
test "drawing ascenders and descenders expand the line without displacing its neighbouring text baseline" {
  let t = rich_view(drawing_runs(),200.0)
  let glyphs = t.drawn_glyphs()
  assert_eq(glyphs.length(),2) // alternative text is not drawn over its vector
  assert_eq(glyphs[0].1,glyphs[1].1)
  let baseline = glyphs[0].1 + 10.0
  let (x,_,_,_) = t.run_rects("x + y")[0]
  assert_eq(t.shape_cover(x+10.0,baseline-9.0),1.0)
  assert_eq(t.shape_cover(x+10.0,baseline+4.0),1.0)
  assert_eq(t.shape_cover(x+10.0,baseline+6.0),0.0)
}
