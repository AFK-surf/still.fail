// Words of the window's tree on one line (WordsLook's `wrap` false) set as an old view's are (Ctx::text, one_line): what
// breaks them run on with a space, one line high, measured and drawn so, found and read out so.

///|
test "words of the tree's on one line: a break in them run on, one line high, as an old view's words on one line are" {
  let node : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    // (in a group read out by what it holds, no label of its own: Tree::words_within)
    root.box(fn(g) {
      g.says(Is(Some(@view.said(Group)))) |> ignore
      g.box(fn(w) {
        node.val = Some(w)
        w.words(Is("一行\n两行")).words_look(Is({ ..@view.words_plain, wrap: false })) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let (_, h) = @signals.untracked(fn() { node.val.unwrap().laid_size() })
  assert_eq(h, 22.0)
  assert_true(t.find("一行 两行") is Some(_), msg="\{t.words()}")
  // (found so by a drive's step, exactly; read out so by the group holding it)
  assert_eq(tree_on_screen(t.ctx(), "=一行 两行").length(), 1)
  assert_true(t.semantics().iter().any(fn(s) { s.role == Group && s.label == "一行 两行" }), msg="\{t.semantics()}")
}

///|
/// Words in pieces (View::words_runs) of two weights and inks, a break between them with blanks after it in the next,
/// set to wrap or not; how high they are laid out.
fn runs_high(wrap : Bool) -> (Tester, Double) {
  let node : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(w) {
      node.val = Some(w)
      w.words_runs(
        Is([{ text: "粗体\n", weight: 700, ink: 0xC03020FFL }, { text: "  细体", weight: 400, ink: 0x2050C0FFL }]),
        look={ ..@view.words_plain, wrap: wrap },
      )
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, @signals.untracked(fn() { node.val.unwrap().laid_size() }).1)
}

///|
test "words in pieces on one line: a break across them run on as one, one line high; wrapped, two lines" {
  let (t, h) = runs_high(false)
  assert_eq(h, 22.0)
  assert_true(t.find("粗体 细体") is Some(_), msg="\{t.words()}")
  let (_, h) = runs_high(true)
  assert_eq(h, 44.0)
}

///|
test "words on one line saying shorter ones, breaks in them all: each run on as it is drawn, the first that fits so chosen, as wide as it is drawn" {
  let probe : Ref[@view.View?] = Ref(None)
  let node : Ref[@view.View?] = Ref(None)
  let room = @signals.signal(1000.0)
  let one = { ..@view.words_plain, wrap: false }
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    // (the shorter one as it is set on one line, alone: how wide that is)
    root.box(fn(p) {
      probe.val = Some(p)
      p.words(Is("一二 三")).words_look(Is(one)) |> ignore
    })
    |> ignore
    root.box(fn(r) {
      r.row(Is(true)).width(By(fn() { Some(room.get()) })) |> ignore
      r.box(fn(w) {
        node.val = Some(w)
        w.words(Is("一二三\n四五六")).words_look(Is(one)).shorter(Is(["一二\n三", "一"])) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let (fits, _) = @signals.untracked(fn() { probe.val.unwrap().laid_size() })
  // (room for that one on one line and no more: it, its break run on, as wide as it is so)
  room.set(fits + 0.5)
  t.draw()
  t.draw()
  let (w, h) = @signals.untracked(fn() { node.val.unwrap().laid_size() })
  let (x, y, _, _) = node.val.unwrap().rect()
  let glyphs = t.drawn_instances().filter(fn(a) { a[5] == 1.0 && a[1] >= y - 1.0 && a[1] <= y + h + 1.0 && a[0] >= x - 1.0 })
  assert_eq((w, h), (fits, 22.0), msg="\{w} of \{fits}")
  assert_eq(glyphs.length(), 3, msg="drawn: \{glyphs.length()} glyphs")
}
