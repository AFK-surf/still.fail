///|
test "a retained composer's hint is absent while focused and while the box closes, then returns at its final place" {
  @sfbase.reset()
  composing_reset()
  @sf.set_words(@sfbase.fill)
  let src = @sfbase.made_source(call=fn(_, _, done) { done(Ok({})) })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=390.0, h=900.0, platform=2, stable=false)
  let made : Ref[ChatComposerNode?] = Ref(None)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.lies_along(Is(End)) |> ignore
    made.val = Some(chat_composer_node(root, src,
      { station: "ws/st", session: "chat", title: "Chat", station_name: "Studio" },
      fn() { Some(@sfbase.chat_view_made({})) }, fn() { 10.0 }, (root, fn(_, _) { 900.0 }), fn(_) { 12.0 }, fn() { composer_alone }, fn(_) {  }))
  })
  t.draw()
  let n = made.val.unwrap().composer
  let id = n.field.id()
  let hint = fn() {
    let (x, y, w, h) = n.field.rect()
    t.drawn_glyphs().filter(fn(g) { g.2 >> 8 == @sf.theme().p.subtle >> 8 &&
      (g.2 & 0xFFL) > 0L && g.0 >= x && g.0 < x + w && g.1 >= y && g.1 < y + h })
  }
  let at = hint()
  assert_true(at.length() > 0)
  n.writing.field.focus()
  t.draw()
  assert_eq(hint().length(), 0)
  t.run_for(composer_shape_ms)
  assert_eq(hint().length(), 0)
  assert_eq(t.locate("icon:plus").length(), 1)
  assert_eq(t.locate("icon:arrow-up").length(), 1)
  t.ctx().blur()
  t.run_for(let_go_ms)
  assert_eq(hint().length(), 0)
  t.run_for(composer_shape_ms / 2.0)
  assert_eq(hint().length(), 0)
  t.run_for(composer_shape_ms / 2.0 + @sf.hint_back_ms)
  assert_eq(hint(), at)
  assert_eq(n.field.id(), id)
}

///|
test "a quote-only send hides the retained field's hint from the moment its card is taken" {
  @sfbase.reset()
  composing_reset()
  let field = @ui.Field::new()
  let opacity : Ref[() -> Double] = Ref(fn() { 1.0 })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=390.0, h=600.0, platform=2, stable=false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    let (hint, _) = composer_hint_node(root, "quoted", fn() { false }, fn() { "same box" })
    opacity.val = hint
    @ui.field(root, field, placeholder="写一点说明", colors_by=fn() {
      let p = @sf.theme().p
      (p.text, @sf.alpha(p.subtle, hint()), p.accent)
    }) |> ignore
  })
  t.draw()
  assert_true(t.glyphs_seen().length() > 0)
  let ff : @sfbase.FlyingFile = {
    key: @sfbase.quote_key(0), from: (20.0, 400.0, 300.0, 120.0), shown: None, picture: None, paint: None,
    ground: 0L, quote_words: None, quote_to: None, source_scale: 1.0, leaving: None, leaving_node: None, face: fn() { }, node: None,
  }
  @sfbase.flight_start_from(t.ctx(), "quoted", "quoted", "row", "", [ff], field.lines(), hold=fn(_) { }, desk=true)
  t.draw()
  assert_eq((opacity.val)(), 0.0)
  assert_eq(t.glyphs_seen().length(), 0)
  t.run_for(@sf.dur_ms)
  assert_eq(t.glyphs_seen().length(), 0)
  @sfbase.send_flight.set(None)
  t.run_for(@sf.hint_back_ms)
  assert_eq((opacity.val)(), 1.0)
  assert_true(t.glyphs_seen().length() > 0)
}
