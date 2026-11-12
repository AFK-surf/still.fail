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
  assert_true(t.find("一行 两行") is Some(_), msg="\{Repr(t.words())}")
  // (found so by a drive's step, exactly; read out so by the group holding it)
  assert_eq(tree_on_screen(t.ctx(), "=一行 两行").length(), 1)
  assert_true(t.semantics().iter().any(fn(s) { s.role == Group && s.label == "一行 两行" }), msg="\{Repr(t.semantics())}")
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
        Is([@view.words_run("粗体\n", weight=700, ink=0xC03020FFL), @view.words_run("  细体", weight=400, ink=0x2050C0FFL)]),
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
  assert_true(t.find("粗体 细体") is Some(_), msg="\{Repr(t.words())}")
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

///|
/// `words` at 15 on 22 in a column 300 wide, wrapped where `wrap`, else on their lines as written (`breaks` kept) or run
/// on: drawn by an old view (Ctx::text, or Ctx::rich in two pieces, the second bold, where `runs`) or by a node of the
/// window's tree (View::words, View::words_runs: WordsLook's `wrap`, View::words_breaks). What is read of it at once (the
/// Tester's reads are the last made's): how big its words are laid out, their lines, where each line is from their
/// start (words in pieces), what a screen reader is told of them.
fn breaks_read(
  node : Bool,
  runs : Bool,
  wrap : Bool,
  breaks : Bool,
  words : String,
  cut : Int,
) -> ((Double, Double), Array[String], Array[String], Array[String]) {
  let first = words.exact_view(end=cut).to_owned()
  let second = words.exact_view(start=cut).to_owned()
  let t = if node {
    Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  } else {
    Tester::new(
      fn(c) {
        c.column(w=Px(300.0), align=AStart, fn() {
          if runs {
            c.rich([plain(first), bold(second)], size=15.0, line=22.0, wrap~, breaks~) |> ignore
          } else {
            c.text(words, size=15.0, line=22.0, wrap~, breaks~) |> ignore
          }
        })
        |> ignore
      },
      w=400.0,
      h=300.0,
    )
  }
  t.check_looks(false)
  if node {
    let look = { ..@view.words_plain, wrap }
    set_view_app(fn(root) {
      root.lines_up(Is(Some(Start))) |> ignore
      root.box(fn(col) {
        // (in a group read out by what it holds, no label of its own: Tree::words_within, as an old view's words are)
        col.width(Is(Some(300.0))).lines_up(Is(Some(Start))).says(Is(Some(@view.said(Group)))) |> ignore
        col.box(fn(w) {
          if runs {
            w.words_runs(Is([@view.words_run(first), @view.words_run(second, weight=700)]), look~).words_breaks(Is(breaks)) |> ignore
          } else {
            w.words(Is(words)).words_look(Is(look)).words_breaks(Is(breaks)) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    })
  }
  t.draw()
  t.draw()
  let probe = words.split("\n").to_array().filter(fn(l) { l != "" }).map(fn(l) { l.to_owned() })
  let (x0, y0, w, h) = t.rect_of(probe[0]).unwrap()
  let r2 = fn(x : Double) { (x * 100.0).round() / 100.0 }
  let at = if runs {
    probe.map(fn(l) { "\{l}: \{list_text(t.run_rects(l).map(fn(r) { rect_text((r2(r.0 - x0), r2(r.1 - y0), r2(r.2), r2(r.3))) }))}" })
  } else {
    []
  }
  let said = t.semantics().filter(fn(s) { s.label.contains(probe[0]) }).map(fn(s) { s.label })
  ((r2(w), r2(h)), t.lines_of(probe[0]), at, said)
}

///|
test "words on their lines as written (View::words_breaks): a line each, as wide as the widest, as tall as their lines, laid out, drawn and read out as an old view's (Ctx::text's, Ctx::rich's breaks); wrapped, their breaks kept as ever" {
  // (an empty line, a line longer than the others and a break at their end)
  let words = "ab cd\n\na longer line of words\nx\n"
  for runs in [false, true] {
    for mode in [(false, true), (true, false), (true, true), (false, false)] {
      let (wrap, breaks) = mode
      let at = "\{if runs { "in pieces" } else { "plain" }}, wrap \{wrap}, breaks \{breaks}"
      let old = breaks_read(false, runs, wrap, breaks, words, 9)
      let made = breaks_read(true, runs, wrap, breaks, words, 9)
      assert_eq(made, old, msg="\{at}: made \{Repr(made)} | old \{Repr(old)}".replace_all(old="\n", new="\\n"))
      // (kept: its four lines, 22 each, one under the other; run on: one line)
      let (size, _, _, _) = made
      if wrap || breaks {
        assert_true(size.1 >= 4.0 * 22.0, msg="\{at}: \{Repr(size)}")
      } else {
        assert_eq(size.1, 22.0, msg=at)
      }
    }
  }
}
