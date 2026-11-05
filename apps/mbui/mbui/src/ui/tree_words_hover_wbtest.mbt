///|
test "hover underlines plain and rich wrapped words without reshaping, moving glyphs or computing layout" {
  for rich in [false, true] {
    let t = Tester::new(fn(_) { }, w=300.0, h=300.0, platform=0)
    t.check_looks(false)
    let node : Ref[@view.View?] = Ref(None)
    set_view_app(fn(root) {
      root.lines_up(Is(Some(Start))) |> ignore
      root.box(fn(n) {
        node.val = Some(n)
        let words = "several words wrap over several lines"
        let look : @view.WordsLook = { ..@view.words_plain, size: 15.0, line: 22.0, wrap: true }
        n.max_width(Is(Some(110.0))).on_press(fn() { }) |> ignore
        if rich {
          n.words_runs(Is([@view.words_run(words)]), ink=0x335577FFL, look~) |> ignore
        } else {
          n.words(Is(words), ink=0x335577FFL, look~) |> ignore
        }
        n.words_underlined(By(fn() { n.pointed() })) |> ignore
      }) |> ignore
    })
    t.draw()
    let n = node.val.unwrap()
    let tree = view_tree().unwrap()
    let glyphs = t.drawn_glyphs()
    let rect = n.rect()
    let measured = tree.work().measured
    let computes = tree.work().computes
    assert_true(rect.3 > 22.0)
    assert_false(t.drawn_rects().any(fn(r) { r.4 == 0x335577FFL }))
    t.move(10.0, 10.0)
    assert_true(t.drawn_rects().filter(fn(r) { r.4 == 0x335577FFL }).length() >= 2,
      msg="every wrapped line is underlined, rich=\{rich}")
    assert_eq(t.drawn_glyphs(), glyphs)
    assert_eq(n.rect(), rect)
    assert_eq(tree.work().measured, measured)
    assert_eq(tree.work().computes, computes)
    t.move(250.0, 250.0)
    assert_false(t.drawn_rects().any(fn(r) { r.4 == 0x335577FFL }))
    assert_eq(t.drawn_glyphs(), glyphs)
    assert_eq(tree.work().computes, computes)
  }
}
