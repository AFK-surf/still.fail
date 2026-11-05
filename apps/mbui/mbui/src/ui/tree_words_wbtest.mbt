///|
test "a retained rich paragraph supplies the same line ranges and rectangles as its old selectable words, through edits and width changes" {
  let text = @signals.signal("第一行 words\n第二行 more words and a link")
  let wide = @signals.signal(140.0)
  let runs = fn() { [span(text.get(), weight=500)] }
  let node : Ref[@view.View?] = Ref(None)
  let made = Ref(0)
  let t = Tester::new(fn(_) {  }, w=400.0, h=500.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    made.val += 1
    root.box(fn(slot) {
      slot.height(Is(Some(200.0))) |> ignore
      old(slot, fn(c) {
        let para = c.box(w=Px(wide.get()), fn() {
          c.rich(runs(), size=15.0, line=22.0, words=true) |> ignore
        })
        c.words(para, "old words")
      }).grow(Is(1.0)) |> ignore
    }) |> ignore
    root.box(fn(para) {
      node.val = Some(para)
      para.width(By(fn() { Some(wide.get()) }))
      .words_runs(By(runs), look={ size: 15.0, line: 22.0, weight: 400, wrap: true, tracking: @view.letters_own, balance: false })
      .runs_look(Is({ ..@view.runs_plain, words: true })) |> ignore
    }) |> ignore
  })
  for (width, words) in [(140.0, text.get()), (240.0, text.get()), (140.0, "替换成新的字，仍然用同一个节点和新的分行。\nMore.")] {
    wide.set(width)
    text.set(words)
    t.draw()
    let old = t.ctx().words_shape_of("old words").unwrap()
    let now = runs_words_now(node.val.unwrap()).unwrap()
    assert_eq(now.text, old.text)
    let (a, b) = (old.pieces[0], now.pieces[0])
    assert_eq((b.x, b.y - 200.0, b.w, b.h), (a.x, a.y, a.w, a.h))
    assert_eq(b.layout.line_count(), a.layout.line_count())
    for line in 0..<a.layout.line_count() {
      assert_eq(b.layout.line_range(line), a.layout.line_range(line))
    }
    for start in 0..<words.length() {
      assert_eq(b.layout.rects(start, start + 1), a.layout.rects(start, start + 1))
    }
  }
  assert_eq(made.val, 1)
}

///|
test "tester lines follow retained text's layout through drawing scales; leaving words remain findable until released" {
  let leaving_ms = 200.0
  let scale = @signals.signal(1.0)
  let shown = @signals.signal(true)
  let plain = "plain words wrap across several short lines"
  let rich = "rich words wrap across several short lines"
  let t = Tester::new(fn(_) {  }, w=400.0, h=600.0)
  set_view_app(fn(root) {
    root.show(fn() { shown.get() }, fn(holder) {
      holder.width(Is(Some(130.0))).scale(By(fn() { scale.get() })) |> ignore
      holder.box(fn(p) { p.words(Is(plain)) |> ignore }) |> ignore
      holder.box(fn(p) { p.words_runs(Is([@view.words_run(rich)])) |> ignore }) |> ignore
    }, leave=leaving_ms)
  })
  t.draw()
  let before_plain = t.lines_of(plain)
  let before_rich = t.lines_of(rich)
  assert_true(before_plain.length() > 1)
  assert_true(before_rich.length() > 1)
  scale.set(0.5)
  t.draw()
  assert_eq(t.lines_of(plain), before_plain)
  assert_eq(t.lines_of(rich), before_rich)
  assert_true(t.rect_of(plain) is Some(_))
  let found_plain = t.find(plain)
  let found_rich = t.find_last(rich)
  let rich_rect = t.rect_of(rich)
  shown.set(false)
  t.draw()
  assert_eq(t.lines_of(plain), [])
  // Structural lookups retain the same words until release, as for plain text in tester_find_wbtest.
  assert_eq(t.find(plain), found_plain)
  assert_eq(t.find_last(rich), found_rich)
  assert_eq(t.rect_of(rich), rich_rect)
  // A driver must not press the departing copy.
  assert_eq(tree_on_screen(t.ctx(), plain).length(), 0)
  t.run_for(leaving_ms)
  assert_eq(t.find(plain), None)
  assert_eq(t.find_last(rich), None)
  assert_eq(t.rect_of(rich), None)
}
