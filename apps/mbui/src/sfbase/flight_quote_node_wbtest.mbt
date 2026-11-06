///|
fn retained_quote_flight(steps : Int) -> Array[Array[Double]] raise {
  reset()
  let source = @signals.signal(true)
  let row = @signals.signal(false)
  let target : @sf.LiveMap[String, @sf.QuoteCardNode] = @sf.LiveMap::new()
  let from : Ref[@sf.QuoteCardNode?] = Ref(None)
  let quoted = "同一张引用卡的两行原文，发送后继续保留原来的断行，再沿着同一条路径到消息里。"
  let comment = "这段也一起带过去"
  let field = @ui.Field::new()
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=390.0, h=600.0, platform=2, stable=false)
  let make = fn(p : @view.View, width : Double?) {
    @sf.quote_card_node(p, fn() { "作者" }, fn() { quoted }, comment=fn() { comment },
      composer=true, corner=fn() { 16.0 },
      words_width?=width.map(@sf.WordsWidth::fixed))
  }
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    flight_page(root, [fn(root) {
    root.box(fn(list) {
      list.height(Is(Some(160.0))).clips(Is(true)) |> ignore
      list.show(fn() { row.get() }, fn(r) {
        r.width(Is(Some(350.0))).offset(Is((20.0, 35.0))) |> ignore
        let q = @sf.quote_card_node(r, fn() { "作者" }, fn() { quoted }, comment=fn() { comment })
        target[quote_key(0)] = q
        r.owns(fn() { target.remove(quote_key(0)) }) |> ignore
      })
    }) |> ignore
    root.show(fn() { source.get() }, fn(p) {
      p.over(Is(true)).width(Is(Some(350.0))).offset(Is((20.0, 410.0))) |> ignore
      from.val = Some(make(p, None))
      @ui.field(p, field) |> ignore
    })
    }, fn(root) {
    root.box(fn(layer) {
      layer.over(Is(true)) |> ignore
      send_flight_node(layer, "quotes", fn(_) { None }, quotes=fn(_, key) { target.get(key) })
    }) |> ignore
    }])
  })
  t.draw()
  let q = from.val.unwrap()
  let r = q.card.placed_window_now()
  let w = q.words.laid_size().0
  let glyphs = t.glyphs_seen()
  let ff : FlyingFile = {
    key: quote_key(0), from: r, shown: None, picture: None, paint: None, ground: @ui.tree_theme().color(Neutral),
    quote_words: Some(("quote", w)), quote_to: None, source_scale: 1.0, leaving: None, leaving_node: None,
    face: fn() { }, node: Some(fn(p) { make(p, Some(w)) |> ignore }),
  }
  flight_start_from(t.ctx(), "quotes", "quotes", "row", "", [ff], field.lines(), hold=fn(_) { }, desk=false)
  source.set(false)
  t.draw()
  assert_eq(t.glyphs_seen(), glyphs, msg="while the row is absent the source's words stay where they were")
  let f = send_flight.get().unwrap()
  assert_false(f.placed)
  row.set(true)
  t.draw()
  assert_true(f.placed, msg="a quote-only send starts from its own card's landing")
  let end = f.way.ends()
  let start = f.set_out
  assert_true(t.glyphs_seen().length() > 10)
  for i in 1..<(steps + 1) {
    t.run_for(start + (end - start) * 0.5 * i.to_double() / steps.to_double() - t.time())
  }
  t.run_for(start + (end - start) * 0.5 - t.time())
  let mid = t.drawn_instances().map(fn(i) { i.map(fn(x) { (x * 100.0).round() / 100.0 }) })
  assert_eq(@ui.view_tree().unwrap().drawn_of(target.get(quote_key(0)).unwrap().card.id()).unwrap().alpha, 0.0)
  t.run_for(end - t.time())
  assert_true(send_flight.get() is None)
  assert_true(t.find(comment) is Some(_))
  assert_eq(@ui.view_tree().unwrap().drawn_of(target.get(quote_key(0)).unwrap().card.id()).unwrap().alpha, 1.0)
  mid
}

///|
test "a quote-only send waits with its source words, uses one path beyond the list clip, and gives back its real card" {
  assert_eq(retained_quote_flight(0), retained_quote_flight(12))
}
