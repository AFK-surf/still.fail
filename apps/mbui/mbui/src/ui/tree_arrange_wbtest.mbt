///|
test "parent arrangements measure plain and rich words from the captured theme" {
  for rich in [false, true] {
    let t = Tester::new(fn(_) { }, w=300.0, h=200.0)
    t.check_looks(false)
    t.tabular_wider(0.5)
    let tabular = @signals.signal(true)
    let word : Ref[@view.View?] = Ref(None)
    set_view_app(fn(root) {
      set_tree_theme(fn() { { ..Theme::light(), tabular: tabular.get() } })
      let child = root.box(fn(child) {
        if rich {
          child.words_runs(Is([@view.words_run("12345")])) |> ignore
        } else {
          child.words(Is("12345")) |> ignore
        }
      })
      word.val = Some(child)
      root.layout(Is(0), fn(_, space) {
        let words = space.measure(child)
        @view.arrangement(space.width().unwrap_or(0.0), space.height().unwrap_or(0.0), [words.at(0.0, 0.0)])
      }) |> ignore
    })
    t.draw()
    let wide = word.val.unwrap().laid_size().0
    tabular.set(false)
    let narrow = word.val.unwrap().laid_size().0
    assert_true(wide > narrow, msg="the initial theme and its change both reach the measurement")
    tabular.set(true)
    assert_eq(word.val.unwrap().laid_size().0, wide)
    t.draw()
    assert_eq(word.val.unwrap().laid_size().0, wide)
  }
}
