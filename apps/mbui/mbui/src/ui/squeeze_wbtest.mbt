// Short of room (docs/style.md): what holds its size, what gives way and how, and what Tester::squeeze_faults says.

///|
/// Box `id` as the last frame laid it out (x, y, w, h) and how it shows (its opacity).
fn laid_box(id : Int) -> (Double, Double, Double, Double, Double) {
  let c = g()
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.id == id {
      return (n.x, n.y, n.fw, n.fh, n.opacity)
    }
  }
  abort("no box \{id}")
}

///|
test "a box sized by what it holds is never laid narrower than that in a short row: what does not fit lies past it" {
  let ids = Ref((0, 0))
  let t = Tester::new(
    fn(c) {
      let a = c.id("a")
      let b = c.id("b")
      ids.val = (a, b)
      c.box(dir=Row, w=Px(100.0), h=Px(20.0), fn() {
        c.box(dir=Row, id=a, taps=false, fn() {
          c.box(w=Px(40.0), h=Px(20.0), fn() {  }) |> ignore
          c.box(w=Px(40.0), h=Px(20.0), fn() {  }) |> ignore
        })
        |> ignore
        c.box(dir=Row, id=b, taps=false, fn() { c.box(w=Px(40.0), h=Px(20.0), fn() {  }) |> ignore }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=100.0,
  )
  t.draw()
  let (a, b) = ids.val
  let (_, _, aw, _, _) = laid_box(a)
  let (bx, _, bw, _, _) = laid_box(b)
  assert_eq(aw, 80.0)
  assert_eq(bw, 40.0)
  assert_eq(bx, 80.0)
}

///|
test "a row leaves out what it may, the lowest drop first, and shows its ⋯ only while it does" {
  let ids : Ref[Array[Int]] = Ref([])
  let width = Ref(100.0)
  let t = Tester::new(
    fn(c) {
      let x = c.id("x")
      let y = c.id("y")
      let m = c.id("more")
      ids.val = [x, y, m]
      c.box(dir=Row, w=Px(width.val), h=Px(20.0), fn() {
        c.box(w=Px(60.0), h=Px(20.0), fn() {  }) |> ignore
        c.box(w=Px(30.0), h=Px(20.0), id=x, taps=false, drop=2, fn() {  }) |> ignore
        c.box(w=Px(30.0), h=Px(20.0), id=y, taps=false, drop=1, fn() {  }) |> ignore
        c.box(w=Px(20.0), h=Px(20.0), id=m, taps=false, more=true, fn() {  }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=100.0,
  )
  t.draw()
  let (x, y, m) = (ids.val[0], ids.val[1], ids.val[2])
  // 60 + 30 + 30 is more than 100: the ⋯ comes (20), y goes (the lowest), then x; 60 and the ⋯ are left
  assert_eq(laid_box(y).4, 0.0)
  assert_eq(laid_box(x).4, 0.0)
  let (mx, _, mw, _, mo) = laid_box(m)
  assert_eq((mx, mw, mo), (60.0, 20.0, 1.0))
  // with the room for all of them, none goes and there is no ⋯
  width.val = 200.0
  t.frame()
  assert_eq(laid_box(x).4, 1.0)
  assert_eq(laid_box(y).4, 1.0)
  assert_eq(laid_box(m).2, 0.0)
  assert_eq(laid_box(m).4, 0.0)
}

///|
test "what a row left out is said as it is built (Ctx::left_out), in the same frame" {
  let said : Ref[Bool?] = Ref(None)
  let t = Tester::new(
    fn(c) {
      let x = c.id("x")
      c.box(dir=Row, w=Px(50.0), h=Px(20.0), fn() {
        c.box(w=Px(40.0), h=Px(20.0), fn() {  }) |> ignore
        c.box(w=Px(40.0), h=Px(20.0), id=x, taps=false, drop=1, fn() {  }) |> ignore
      })
      |> ignore
      said.val = Some(c.left_out(x))
    },
    w=400.0,
    h=100.0,
  )
  t.draw()
  assert_eq(said.val, Some(true))
}

///|
test "the boxes words show cut short in are said so (Ctx::shows_cut), and not where they show whole" {
  let width = Ref(100.0)
  let said : Ref[(Bool, Bool, Bool)] = Ref((false, false, false))
  let t = Tester::new(
    fn(c) {
      let (x, y, z) = (c.id("x"), c.id("y"), c.id("z"))
      c.box(dir=Column, w=Px(width.val), fn() {
        // one line, cut with an ellipsis where it has not the room
        c.box(dir=Row, id=x, taps=false, fn() {
          c.text("words longer than the row has room for", w=Cut, wrap=false) |> ignore
        })
        |> ignore
        // short: whole in any of these widths
        c.box(dir=Row, id=y, taps=false, fn() { c.text("short", wrap=false) |> ignore }) |> ignore
        // wrapped, its lines after the first left off
        c.box(id=z, taps=false, fn() { c.text("words longer than the row has room for", max_lines=1) |> ignore }) |> ignore
      })
      |> ignore
      said.val = (c.shows_cut(x), c.shows_cut(y), c.shows_cut(z))
    },
    w=800.0,
    h=200.0,
  )
  t.draw()
  t.frame()
  assert_eq(said.val, (true, false, true))
  // with the room for all of it, nothing is cut
  width.val = 700.0
  t.frame()
  t.frame()
  assert_eq(said.val, (false, false, false))
}

///|
test "words said to be cut (Cut) are as wide as they are, and cut with an ellipsis where the row has less" {
  let ids = Ref(0)
  let t = Tester::new(
    fn(c) {
      c.box(dir=Row, w=Px(100.0), h=Px(20.0), fn() {
        let i = c.text("words longer than the row has room for", w=Cut, wrap=false)
        ids.val = i
        c.box(w=Px(40.0), h=Px(20.0), fn() {  }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=100.0,
  )
  t.draw()
  let n = g().nodes[ids.val]
  assert_eq(n.fw, 60.0)
  assert_true(t.squeeze_faults().is_empty(), msg=t.squeeze_faults().join("\n"))
}

///|
test "squeeze_faults: what a box that takes its room squeezes lies over what is beside it" {
  let t = Tester::new(
    fn(c) {
      c.box(dir=Row, w=Px(100.0), h=Px(20.0), fn() {
        c.box(dir=Row, w=Fill(1.0), fn() { c.box(w=Px(80.0), h=Px(20.0), bg=0xFF0000FFL, fn() {  }) |> ignore })
        |> ignore
        c.box(w=Px(50.0), h=Px(20.0), bg=0x00FF00FFL, fn() {  }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=100.0,
  )
  t.draw()
  let faults = t.squeeze_faults()
  assert_eq(faults.length(), 1, msg=faults.join("\n"))
  assert_true(faults[0].contains("overlap by 30"), msg=faults[0])
}

///|
test "squeeze_faults: words wrapped narrower than a word of them (broken inside it) are squeezed; wrapped between words they are not" {
  let narrow = Ref(30.0)
  let t = Tester::new(
    fn(c) { c.box(w=Px(narrow.val), fn() { c.text("Studio settings", size=14.0) |> ignore }) |> ignore },
    w=400.0,
    h=200.0,
  )
  t.draw()
  let faults = t.squeeze_faults()
  assert_eq(faults.length(), 1, msg=faults.join("\n"))
  assert_true(faults[0].contains("wrapped"), msg=faults[0])
  narrow.val = 80.0
  t.frame()
  assert_true(t.squeeze_faults().is_empty(), msg=t.squeeze_faults().join("\n"))
}

///|
test "a row leaves out what it may before words cut short in it go under four of their size; then they take its room" {
  let ids = Ref((0, 0))
  let t = Tester::new(
    fn(c) {
      let d = c.id("d")
      c.box(dir=Row, w=Px(100.0), h=Px(20.0), fn() {
        let i = c.text("words much longer than the row", size=10.0, w=Cut, wrap=false)
        c.box(w=Px(70.0), h=Px(20.0), id=d, taps=false, drop=1, fn() {  }) |> ignore
        ids.val = (i, d)
      })
      |> ignore
    },
    w=400.0,
    h=100.0,
  )
  t.draw()
  let (i, d) = ids.val
  // (70 beside them would leave the words 30, less than four of their 10)
  assert_eq(laid_box(d).4, 0.0)
  assert_eq(g().nodes[i].fw, 100.0)
}

///|
test "one_line: a line break with the spaces round it one space, none at the ends, across runs; none where no break" {
  assert_eq(one_line(["a  b", "c "]), None)
  assert_eq(one_line(["\n a \n\t b \n"]), Some(["a b"]))
  assert_eq(one_line(["ab \n", "\n cd"]), Some(["ab ", "cd"]))
  assert_eq(one_line(["a\r\nb"]), Some(["a b"]))
  assert_eq(one_line(["x", "\n", "y"]), Some(["x", " ", "y"]))
}

///|
test "words on one line hold their row alike, plain or in runs: as wide as they are while there is room, cut as a last resort" {
  let ids : Map[Bool, Int] = {}
  let t = Tester::new(
    fn(c) {
      for rich in [false, true] {
        let id = c.id("held/\{rich}")
        ids[rich] = id
        c.box(dir=Row, w=Px(100.0), h=Px(20.0), fn() {
          c.box(dir=Row, id~, taps=false, fn() {
            let words = "words much longer than the row"
            if rich {
              c.rich([plain(words)], size=10.0, wrap=false) |> ignore
            } else {
              c.text(words, size=10.0, wrap=false) |> ignore
            }
          })
          |> ignore
          c.box(w=Fill(1.0), h=Px(20.0), fn() {  }) |> ignore
        })
        |> ignore
      }
    },
    w=400.0,
    h=100.0,
  )
  t.draw()
  let (_, _, plain_w, _, _) = laid_box(ids[false])
  let (_, _, rich_w, _, _) = laid_box(ids[true])
  // (longer than the row: all of it theirs, what is beside them nothing, they cut to it)
  assert_eq(plain_w, 100.0)
  assert_eq(rich_w, plain_w)
  assert_true(laid_words("words much").least > 100.0)
}

///|
test "squeeze_faults: words on one line cut to nothing, plain or in runs" {
  let t = Tester::new(
    fn(c) {
      c.box(dir=Row, w=Px(30.0), h=Px(20.0), fn() {
        c.text("plain words", size=10.0, wrap=false, w=Cut) |> ignore
        c.box(w=Px(28.0), h=Px(20.0), fn() {  }) |> ignore
      })
      |> ignore
      c.box(dir=Row, w=Px(30.0), h=Px(20.0), fn() {
        c.rich([plain("words in runs")], size=10.0, wrap=false, w=Cut) |> ignore
        c.box(w=Px(28.0), h=Px(20.0), fn() {  }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=100.0,
  )
  t.draw()
  let faults = t.squeeze_faults()
  assert_eq(faults.length(), 2, msg=faults.join("\n"))
  assert_true(faults.iter().all(fn(f) { f.contains("cut to 0 characters") }), msg=faults.join("\n"))
}

///|
test "squeeze_faults: an unannounced ellipsis is a fault even with several characters showing" {
  let t = Tester::new(fn(c) {
    c.box(w=Px(20.0), fn() { c.text("10:06", size=10.0, wrap=false) |> ignore }) |> ignore
    c.box(w=Px(20.0), fn() { c.text("12.3%", size=10.0, wrap=false) |> ignore }) |> ignore
    c.box(w=Px(20.0), fn() { c.text("Ready", size=10.0, wrap=false) |> ignore }) |> ignore
    // The title explicitly says it may be cut, so its ellipsis is not an unexpected one.
    c.box(w=Px(20.0), fn() { c.text("A long title", size=10.0, wrap=false, w=Cut) |> ignore }) |> ignore
    c.box(w=Px(20.0), fn() { c.text("Another title", size=10.0, wrap=false, max_lines=1) |> ignore }) |> ignore
  }, w=400.0, h=100.0)
  t.draw()
  assert_true(t.lines_of("10:06")[0].has_suffix("…"))
  assert_true(t.lines_of("12.3%")[0].has_suffix("…"))
  assert_true(t.lines_of("Ready")[0].has_suffix("…"))
  assert_true(t.lines_of("A long title")[0].has_suffix("…"))
  let faults = t.squeeze_faults()
  assert_eq(faults.length(), 3, msg=faults.join("\n"))
}

///|
test "squeeze_faults finds a title given no room beside a fixed control" {
  let t = Tester::new(fn(c) {
    c.box(dir=Row, w=Px(20.0), h=Px(20.0), fn() {
      c.text("Missing title", size=10.0, wrap=false) |> ignore
      c.box(w=Px(20.0), h=Px(20.0), keep=true, fn() {  }) |> ignore
    }) |> ignore
  }, w=400.0, h=100.0)
  t.draw()
  assert_true(laid_words("Missing title").fw < 0.001)
  let faults = t.squeeze_faults()
  assert_true(faults.iter().any(fn(f) { f.contains("Missing title") && f.contains("cut to 0") }), msg=faults.join("\n"))
}

///|
test "squeeze_faults: a shorter wording ending in an ellipsis is not a layout cut" {
  let t = Tester::new(fn(c) {
    c.box(w=Px(60.0), fn() {
      c.text("Search all conversations and their contents", size=10.0, wrap=false, shorter=["Search…"]) |> ignore
    }) |> ignore
  }, w=400.0, h=100.0)
  t.draw()
  assert_eq(t.lines_of("Search all"), ["Search…"])
  assert_eq(t.squeeze_faults(), [])
}

///|
test "squeeze_faults does not report a line faded out by its holder's look" {
  for width in [10.0, 20.0] {
    let t = Tester::new(fn(c) {
      let i = c.box(w=Px(width), fn() { c.text("10:06", size=10.0, wrap=false) |> ignore })
      c.look(i, look(alpha=0.0))
    }, w=400.0, h=100.0)
    t.draw()
    assert_true(t.words().iter().any(fn(w) { w.0 == "10:06" && w.5 == 0.0 }))
    assert_eq(t.squeeze_faults(), [], msg="width=\{width}")
  }
}

///|
/// The node of the first words that start with `s`, as the last frame laid them out.
fn laid_words(s : String) -> Node {
  let c = g()
  for i in 0..<c.count {
    let n = c.nodes[i]
    if (n.kind == kind_text || n.kind == kind_rich) && n.text.has_prefix(s) {
      return n
    }
  }
  abort("no words \{s}")
}

///|
test "a row without the room for every least cuts the words that say not how they give as a last resort, the widest first" {
  let t = Tester::new(
    fn(c) {
      c.box(dir=Row, w=Px(200.0), h=Px(20.0), gap=4.0, fn() {
        c.text("Station", size=10.0, wrap=false) |> ignore
        c.text("words written by someone else, much longer than the row has room for", size=10.0, wrap=false, allow_ellipsis=true)
        |> ignore
        c.box(w=Px(20.0), h=Px(20.0), fn() {  }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=100.0,
  )
  t.draw()
  let label = laid_words("Station")
  let long = laid_words("words written")
  // the short one whole, the long one cut to what is left, what never gives way kept
  assert_eq(label.fw, label.text_layout(1.0e9).w)
  assert_true(long.fw < long.least, msg="\{long.fw} of \{long.least}")
  assert_true(long.x + long.fw + 4.0 + 20.0 <= 200.0 + 0.5, msg="\{long.x} + \{long.fw}")
  match long.tl {
    Some(tl) => assert_true(tl.w <= long.fw + 0.5, msg="drawn \{tl.w} in \{long.fw}")
    None => fail("not laid out")
  }
  // nothing over another, nothing past the row: nothing squeezed
  assert_true(t.squeeze_faults().is_empty(), msg=t.squeeze_faults().join("\n"))
}

///|
test "a last resort brings the widest down first, to one width, each in what holds it" {
  let t = Tester::new(
    fn(c) {
      c.box(dir=Row, w=Px(200.0), h=Px(20.0), fn() {
        c.box(dir=Row, gap=2.0, fn() {
          c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore
          c.text("first words, long enough to need cutting here", size=10.0, wrap=false, allow_ellipsis=true) |> ignore
        })
        |> ignore
        c.text("second words, as long as they need to be cut too", size=10.0, wrap=false, allow_ellipsis=true) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=100.0,
  )
  t.draw()
  let first = laid_words("first words")
  let second = laid_words("second words")
  let holder = g().nodes[first.parent]
  // the two at one width (the first's with its mark), the row no wider than its room, nothing over another
  assert_true((holder.fw - second.fw).abs() < 1.0, msg="\{holder.fw} and \{second.fw}")
  assert_true(second.x + second.fw <= 200.0 + 0.5, msg="\{second.x} + \{second.fw}")
  assert_true(first.x + first.fw <= holder.x + holder.fw + 0.5, msg="\{first.x} + \{first.fw} in \{holder.fw}")
  assert_true(t.squeeze_faults().is_empty(), msg=t.squeeze_faults().join("\n"))
}

///|
test "a last resort never cuts a control: what is pressed keeps its words whole, the words beside it give" {
  let ids = Ref(0)
  let t = Tester::new(
    fn(c) {
      let b = c.id("button")
      ids.val = b
      c.box(dir=Row, w=Px(120.0), h=Px(20.0), gap=4.0, fn() {
        c.text("words written by someone else, longer than the row", size=10.0, wrap=false, allow_ellipsis=true) |> ignore
        c.box(dir=Row, id=b, padx=6.0, fn() { c.text("Cancel", size=10.0, wrap=false) |> ignore }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=100.0,
  )
  t.draw()
  let label = laid_words("Cancel")
  assert_eq(label.fw, label.text_layout(1.0e9).w)
  let (bx, _, bw, _, _) = laid_box(ids.val)
  assert_true(bx + bw <= 120.0 + 0.5, msg="\{bx} + \{bw}")
  assert_true(laid_words("words written").fw < laid_words("words written").least)
  assert_true(t.squeeze_faults().is_empty(), msg=t.squeeze_faults().join("\n"))
}

///|
test "a last resort cuts none in vain: where what never gives way is wider than the row, the words stay whole" {
  let t = Tester::new(
    fn(c) {
      c.box(dir=Row, w=Px(100.0), h=Px(20.0), fn() {
        c.text("Size", size=10.0, wrap=false) |> ignore
        c.box(w=Px(120.0), h=Px(20.0), fn() {  }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=100.0,
  )
  t.draw()
  let label = laid_words("Size")
  assert_eq(label.fw, label.text_layout(1.0e9).w)
}

///|
/// How many code units of the words `n` shows (laid out as `tl`), -1 none laid out.
fn shown_len(tl : TextLayout?) -> Int {
  match tl {
    Some(tl) => tl.shaped.len
    None => -1
  }
}

///|
test "words on one line said a shorter way: the longest that fits whole, in a row needing no more than the shortest" {
  let long = "the longest way of saying it"
  let shorter = ["a shorter way", "short way"]
  let width = Ref(400.0)
  let t = Tester::new(
    fn(c) {
      c.box(dir=Row, w=Px(width.val), h=Px(20.0), fn() {
        c.text(long, size=10.0, wrap=false, shorter~) |> ignore
        c.box(w=Px(40.0), h=Px(20.0), fn() {  }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=100.0,
  )
  t.draw()
  let n = laid_words(long)
  assert_eq(shown_len(n.tl), long.length())
  // (less room than all of them take: the longest shorter way that fits there, whole)
  width.val = 40.0 + n.worded(shorter[0]).w + 1.0
  t.frame()
  assert_eq(shown_len(laid_words(long).tl), shorter[0].length())
  width.val = 40.0 + n.worded(shorter[1]).w + 1.0
  t.frame()
  assert_eq(shown_len(laid_words(long).tl), shorter[1].length())
  assert_true(t.squeeze_faults().is_empty(), msg=t.squeeze_faults().join("\n"))
  // (what they need at least, the box beside them squeezed by nothing: the shortest whole)
  assert_eq(laid_words(long).least, n.worded(shorter[1]).w)
  // (less room than the shortest takes: that cut with an ellipsis, as a last resort)
  width.val = 40.0 + n.worded(shorter[1]).w - 8.0
  t.frame()
  let cut = laid_words(long).tl.unwrap()
  assert_true(cut.w <= laid_words(long).fw + 0.5)
  assert_eq(cut.shaped.cu[cut.shaped.cu.length() - 1], '…'.to_int())
}

///|
/// What of its placeholder the field shows now, laid out.
fn hint_now() -> TextLayout {
  let c = g()
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.kind == kind_editor {
      match c.editors.get(n.id) {
        Some(_) => return n.hint_shown()
        None => ()
      }
    }
  }
  abort("no field")
}

///|
test "a field's placeholder is said the longest way that fits it, whole, the shortest cut where none does; never cut by its edge" {
  let long = "the longest way of saying it"
  let shorter = ["a shorter way", "short way"]
  let width = Ref(400.0)
  let wide = fn(s : String) { layout_text(s, 10.0, 400, 1.0e9, false).w }
  let t = Tester::new(
    fn(c) {
      c.box(w=Px(width.val), h=Px(20.0), fn() {
        c.editor("field", placeholder=long, shorter~, font_size=10.0, max_lines=1, plain=true) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=100.0,
  )
  t.draw()
  assert_eq(hint_now().shaped.len, long.length())
  width.val = wide(shorter[0]) + 1.0
  t.frame()
  assert_eq(hint_now().shaped.len, shorter[0].length())
  assert_true(t.squeeze_faults().is_empty(), msg=t.squeeze_faults().join("\n"))
  // (less room than its shortest way: that cut with an ellipsis in the field, as words on one line are)
  width.val = wide(shorter[1]) - 1.0
  t.frame()
  let cut = hint_now()
  assert_true(cut.w <= width.val + 0.5, msg="\{cut.w} in \{width.val}")
  assert_eq(cut.shaped.cu[cut.shaped.cu.length() - 1], '…'.to_int())
  assert_true(t.squeeze_faults().is_empty(), msg=t.squeeze_faults().join("\n"))
  // (cut down to nothing: squeezed)
  width.val = wide("…") + 1.0
  t.frame()
  let faults = t.squeeze_faults()
  assert_eq(faults.length(), 1, msg=faults.join("\n"))
  assert_true(faults[0].contains("placeholder cut to 0"), msg=faults[0])
}
