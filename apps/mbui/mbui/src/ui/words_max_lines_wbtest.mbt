// Words of the window's tree that say how many lines they are drawn on at most (WordsLook's `max_lines`, a style's
// `max_lines` through style_words): cut after the last, ending in an ellipsis where it has not the room, measured and
// drawn so, as an old view's words in the same style are (Ctx::text's, Ctx::rich's).

///|
/// `words` in `style` in a column `width` wide at the system's size of words `scale`, drawn by an old view (Ctx::text,
/// or Ctx::rich where `who` is said: it in bold, then the words) or by a node of the window's tree (View::words,
/// View::words_runs, its look style_words'). What is read of it at the moment it is drawn (the Tester's reads are the
/// last made's): its words as Tester::words has them, where they are drawn from the words' top left and how big they
/// are laid out; their lines (plain words: Tester::lines_of, found by `probe`, their start); each glyph drawn and the
/// rectangles, from that top left.
fn max_lines_read(
  node : Bool,
  words : String,
  probe : String,
  who : String?,
  style : TextStyle,
  width : Double,
  scale : Double,
) -> (
  Array[(String, Double, Double, Double, Double)],
  Array[String],
  Array[(Double, Double, Int64)],
  Array[(Double, Double, Double, Double, Int64)],
) {
  let runs = match who {
    Some(w) => [bold(w), plain(words)]
    None => []
  }
  let t = if node {
    Tester::new(fn(_c) {  }, w=400.0, h=400.0)
  } else {
    Tester::new(
      fn(c) {
        c.column(w=Px(width), align=AStart, fn() {
          if runs.is_empty() {
            c.text(words, style~) |> ignore
          } else {
            c.rich(runs, style~) |> ignore
          }
        })
        |> ignore
      },
      w=400.0,
      h=400.0,
    )
  }
  t.check_looks(false)
  t.set_font_scale(scale)
  if node {
    set_view_app(fn(root) {
      root.lines_up(Is(Some(Start))) |> ignore
      root.box(fn(col) {
        col.width(Is(Some(width))).lines_up(Is(Some(Start))) |> ignore
        col.box(fn(w) {
          if runs.is_empty() {
            w.words(Is(words)).words_look(By(fn() { style_words(style) })) |> ignore
          } else {
            w.words_runs(Is(runs)).words_look(By(fn() { style_words(style) })) |> ignore
          }
          w.ink(By(fn() { style_ink(style) })) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
  }
  t.draw()
  t.draw()
  let r2 = fn(x : Double) { (x * 100.0).round() / 100.0 }
  let all = t.words()
  guard all.get(0) is Some((_, x0, y0, _, _, _)) else { return ([], [], [], []) }
  let said = all.map(fn(w) { (w.0, r2(w.1 - x0), r2(w.2 - y0), r2(w.3), r2(w.4)) })
  let lines = if runs.is_empty() { t.lines_of(probe) } else { [] }
  let glyphs = t.drawn_glyphs().map(fn(g) { (r2(g.0 - x0), r2(g.1 - y0), g.2) })
  let rects = t.drawn_rects().map(fn(r) { (r2(r.0 - x0), r2(r.1 - y0), r2(r.2), r2(r.3), r.4) })
  (said, lines, glyphs, rects)
}

///|
/// Long words of each kind (what each is, the words, their start): Chinese, English with words longer than a line,
/// lines broken as written, and words short enough for a line.
// kept across runs: a value (no field of it changes)
let max_lines_words : Array[(String, String, String)] = [
  ("中文", "这是一段很长的中文引用，用来看它在窄的宽度下折成几行，以及最后一行在放不下的地方收成省略号；再多写一些字，让它超过三行还有余。", "这是"),
  (
    "long English words",
    "Supercalifragilisticexpialidocious antidisestablishmentarianism pneumonoultramicroscopicsilicovolcanoconiosis and more",
    "Super",
  ),
  ("breaks", "第一行\n第二行比较长，长到在窄的宽度下自己也要折一次\n第三行\n第四行", "第一"),
  ("short", "短短一行", "短短"),
]

///|
test "words saying how many lines at most, plain and in pieces: cut after the last, its ellipsis where it has not the room, laid out, measured and drawn as an old view's in the same style, at each width and number of lines" {
  for wl in max_lines_words {
    let (kind, words, probe) = wl
    for most in [1, 2, 3] {
      let style = text_style(size=Meta, leading=L5, color=Muted, max_lines=most)
      for width in [80.0, 150.0, 300.0] {
        for who in [None, Some("谁：")] {
          let at = "\{kind}, \{most} lines at most, \{width} wide\{if who is Some(_) { ", in pieces" } else { "" }}"
          let old = max_lines_read(false, words, probe, who, style, width, 1.0)
          let made = max_lines_read(true, words, probe, who, style, width, 1.0)
          assert_eq(made.0, old.0, msg="\{at}: words")
          assert_eq(made.1, old.1, msg="\{at}: lines")
          assert_eq(made.2, old.2, msg="\{at}: glyphs")
          assert_eq(made.3, old.3, msg="\{at}: rects")
          // (cut so: no more lines than it says)
          let (said, lines, _, _) = made
          assert_eq(said.length(), 1, msg="\{at}: \{Repr(said)}")
          if who is None {
            assert_true(lines.length() >= 1 && lines.length() <= most, msg="\{at}: \{Repr(lines)}")
          }
        }
      }
    }
  }
}

///|
test "words saying how many lines at most at the system's words 1.3: cut, measured and drawn alike" {
  for wl in max_lines_words {
    let (kind, words, probe) = wl
    let style = text_style(size=Meta, leading=L5, color=Muted, max_lines=2)
    for width in [80.0, 150.0, 300.0] {
      for who in [None, Some("谁：")] {
        let at = "\{kind} at 1.3, \{width} wide\{if who is Some(_) { ", in pieces" } else { "" }}"
        let old = max_lines_read(false, words, probe, who, style, width, 1.3)
        let made = max_lines_read(true, words, probe, who, style, width, 1.3)
        assert_eq(made, old, msg=at)
      }
    }
  }
}

///|
test "long Chinese words saying two lines at most, 150 wide: two lines, the second ending in an ellipsis; saying none, more" {
  let (_, words, probe) = max_lines_words[0]
  let two = max_lines_read(true, words, probe, None, text_style(size=Meta, leading=L5, max_lines=2), 150.0, 1.0)
  assert_eq(two.1.length(), 2, msg="\{Repr(two.1)}")
  assert_true(two.1[1].has_suffix("…"), msg="\{Repr(two.1)}")
  // (as tall as two of its lines)
  let one = max_lines_read(true, "短短一行", "短短", None, text_style(size=Meta, leading=L5), 150.0, 1.0)
  assert_eq(two.0[0].4, 2.0 * one.0[0].4, msg="\{Repr(two.0)} | \{Repr(one.0)}")
  let all = max_lines_read(true, words, probe, None, text_style(size=Meta, leading=L5), 150.0, 1.0)
  assert_true(all.1.length() > 3 && !all.1.iter().any(fn(l) { l.has_suffix("…") }), msg="\{Repr(all.1)}")
}

///|
test "words saying how many lines at most read whole, and told cut short (View::words_cut_now), as an old view's (Ctx::shows_cut)" {
  let node : Ref[@view.View?] = Ref(None)
  let words = max_lines_words[0].1
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(col) {
      col.width(Is(Some(150.0))).lines_up(Is(Some(Start))).says(Is(Some(@view.said(Group)))) |> ignore
      col.box(fn(w) {
        node.val = Some(w)
        w.words(Is(words)).words_look(By(fn() { style_words(text_style(size=Meta, leading=L5, max_lines=2)) })) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.draw()
  assert_true(t.find(words) is Some(_), msg="\{Repr(t.words())}")
  assert_true(t.semantics().iter().any(fn(s) { s.role == Group && s.label == words }), msg="\{Repr(t.semantics())}")
  assert_true(node.val.unwrap().words_cut_now())
}
