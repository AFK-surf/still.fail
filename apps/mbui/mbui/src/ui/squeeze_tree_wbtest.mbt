// The squeeze's rules held to the window's tree (squeeze_tree.mbt): each rule's least case made of nodes, and the same
// made as an old view, said alike; and what the rule lets be, let be alike. Ctx::tree_squeeze_said says the tree's alone,
// Tester::squeeze_faults both.

///|
/// How these tests' words are set: 10 points, on one line (`wrap`: else on lines).
fn sq_look(wrap? : Bool = false, size? : Double = 10.0) -> @view.WordsLook {
  { size, weight: 400, line: 14.0, wrap, tracking: @view.letters_own, balance: false, max_lines: 0 }
}

///|
/// The tree's faults on a window 400 by 200 made by `tree`, as first drawn.
fn sq_tree(tree : (@view.View) -> Unit, w? : Double = 400.0) -> Array[String] {
  let t = Tester::new(fn(_c) {  }, w~, h=200.0, tree~)
  t.draw()
  g().tree_squeeze_said()
}

///|
/// The old view's faults on a window 400 by 200 built by `view`, as first drawn.
fn sq_old(view : (Ctx) -> Unit, w? : Double = 400.0) -> Array[String] {
  let t = Tester::new(view, w~, h=200.0)
  t.draw()
  t.squeeze_faults()
}

///|
/// Whether `faults` are one, saying `what`.
fn sq_one(faults : Array[String], what : String) -> Bool {
  faults.length() == 1 && faults[0].contains(what)
}

// (g) words broken onto lines only for what shares their row

///|
/// A row 140 wide, 12 between: a column growing in it holding a note on lines (`titled`: a title over it; `allowed`:
/// said it may end in an ellipsis), then a box
/// 44 by 26 across their middle (a switch's room). Alone in the row the note is one line; beside the box, two.
fn sq_note_row(titled~ : Bool, allowed? : Bool = false) -> (@view.View) -> Unit {
  fn(root) {
    root.box(fn(row) {
      row.row(Is(true)).width(Is(Some(140.0))).gap(Is(12.0)).lines_up(Is(Some(@view.Middle))) |> ignore
      row.box(fn(col) {
        col.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
        if titled {
          col.box(fn(v) { v.words(Is("Title"), look=sq_look()) |> ignore }) |> ignore
        }
        col.box(fn(v) { v.words(Is("a note of some length"), look=sq_look(wrap=true)).allow_ellipsis(Is(allowed)) |> ignore }) |> ignore
      })
      |> ignore
      row.box(fn(v) { v.width(Is(Some(44.0))).height(Is(Some(26.0))).ground(Is(0x00FF00FFL)) |> ignore }) |> ignore
    })
    |> ignore
  }
}

///|
test "(g) the window tree's words on two lines only for what shares their row, as an old view's; a note under its title beside a control, none" {
  let tree = sq_tree(sq_note_row(titled=false))
  assert_true(sq_one(tree, "2 lines for what shares their row"), msg=tree.join("\n"))
  // (and where it was made)
  assert_true(tree[0].contains("made at"), msg=tree[0])
  let old = sq_old(note_beside(titled=false, middle=true, end=true))
  assert_true(sq_one(old, "2 lines for what shares their row"), msg=old.join("\n"))
  assert_eq(sq_tree(sq_note_row(titled=true)), [])
  assert_eq(sq_old(note_beside(titled=true, middle=true, end=true)), [])
}

// (c) words wrapped narrower than a word of them

///|
/// A box `w` wide holding "Studio settings" on lines, at 14.
fn sq_wrapped(w : Double) -> (@view.View) -> Unit {
  fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(w))).words(Is("Studio settings"), look=sq_look(wrap=true, size=14.0)) |> ignore
    })
    |> ignore
  }
}

///|
test "(c) the window tree's words wrapped narrower than a word of them, as an old view's; between words, none" {
  let tree = sq_tree(sq_wrapped(30.0))
  assert_true(sq_one(tree, "wrapped 30 across"), msg=tree.join("\n"))
  let old = sq_old(fn(c) { c.box(w=Px(30.0), fn() { c.text("Studio settings", size=14.0) |> ignore }) |> ignore })
  assert_true(sq_one(old, "wrapped 30 across"), msg=old.join("\n"))
  assert_eq(sq_tree(sq_wrapped(80.0)), [])
}

// (d) the outermost box past the window's edge

///|
/// A box 500 wide in a window 400 wide (`clipped`: in one 300 wide that clips it; `across`: in one that scrolls
/// across; `over`: laid over what holds it).
fn sq_wide(clipped? : Bool = false, across? : Bool = false) -> (@view.View) -> Unit {
  fn(root) {
    let wide = fn(v : @view.View) {
      v.box(fn(b) { b.width(Is(Some(500.0))).height(Is(Some(20.0))).ground(Is(0x00FF00FFL)) |> ignore }) |> ignore
    }
    if across {
      root.box(fn(h) {
        h.width(Is(Some(300.0))).height(Is(Some(20.0))) |> ignore
        h.scrolls(@view.Scroll::across(), fn(s) { wide(s) }) |> ignore
      })
      |> ignore
    } else if clipped {
      root.box(fn(h) {
        h.width(Is(Some(300.0))).clips(Is(true)) |> ignore
        wide(h)
      })
      |> ignore
    } else {
      wide(root)
    }
  }
}

///|
test "(d) the window tree's box past the window's edge, as an old view's; in what clips or scrolls across, none" {
  let tree = sq_tree(sq_wide())
  assert_true(sq_one(tree, "runs 100 past the window's edge"), msg=tree.join("\n"))
  let old = sq_old(fn(c) { c.box(w=Px(500.0), h=Px(20.0), bg=0x00FF00FFL, fn() {  }) |> ignore })
  assert_true(sq_one(old, "runs 100 past the window's edge"), msg=old.join("\n"))
  assert_eq(sq_tree(sq_wide(clipped=true)), [])
  assert_eq(sq_tree(sq_wide(across=true)), [])
}

// (e) words cut off part way by what clips them

///|
/// Words 100 wide (a box of their own) in a box 60 wide that clips (`across`: one that scrolls across instead).
fn sq_clipped(across? : Bool = false) -> (@view.View) -> Unit {
  fn(root) {
    let words = fn(v : @view.View) {
      v.box(fn(b) { b.width(Is(Some(100.0))).words(Is("abc"), look=sq_look()) |> ignore }) |> ignore
    }
    root.box(fn(h) {
      h.width(Is(Some(60.0))).height(Is(Some(20.0))) |> ignore
      if across {
        h.scrolls(@view.Scroll::across(), fn(s) { words(s) }) |> ignore
      } else {
        h.clips(Is(true)) |> ignore
        words(h)
      }
    })
    |> ignore
  }
}

///|
test "(e) the window tree's words cut off part way by what clips them, as an old view's; in what scrolls across, none" {
  let tree = sq_tree(sq_clipped())
  assert_true(sq_one(tree, "is cut off 40 by what clips it"), msg=tree.join("\n"))
  let old = sq_old(fn(c) {
    c.box(w=Px(60.0), h=Px(20.0), clip=true, fn() { c.box(w=Px(100.0), fn() { c.text("abc", size=10.0) |> ignore }) |> ignore })
    |> ignore
  })
  assert_true(old.iter().any(fn(f) { f.contains("is cut off 40 by what clips it") }), msg=old.join("\n"))
  assert_eq(sq_tree(sq_clipped(across=true)), [])
}

// (f) two beside each other in a box drawn over each other

///|
/// A row 100 wide: a box growing in it holding one 80 wide, then one 50 wide (`pulled`: its margin before it -30).
fn sq_over(pulled? : Bool = false) -> (@view.View) -> Unit {
  fn(root) {
    root.box(fn(row) {
      row.row(Is(true)).width(Is(Some(100.0))).height(Is(Some(20.0))) |> ignore
      row.box(fn(o) {
        o.row(Is(true)).grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
        o.box(fn(b) { b.width(Is(Some(80.0))).height(Is(Some(20.0))).ground(Is(0xFF0000FFL)) |> ignore }) |> ignore
      })
      |> ignore
      row.box(fn(b) {
        b.width(Is(Some(50.0))).height(Is(Some(20.0))).ground(Is(0x00FF00FFL)) |> ignore
        if pulled {
          b.margin(Is((-30.0, 0.0, 0.0, 0.0))) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  }
}

///|
test "(f) two of the window tree's beside each other drawn over each other, as an old view's; pulled over on purpose, none" {
  let tree = sq_tree(sq_over())
  assert_true(sq_one(tree, "overlap by 30"), msg=tree.join("\n"))
  let old = sq_old(fn(c) {
    c.box(dir=Row, w=Px(100.0), h=Px(20.0), fn() {
      c.box(dir=Row, w=Fill(1.0), fn() { c.box(w=Px(80.0), h=Px(20.0), bg=0xFF0000FFL, fn() {  }) |> ignore }) |> ignore
      c.box(w=Px(50.0), h=Px(20.0), bg=0x00FF00FFL, fn() {  }) |> ignore
    })
    |> ignore
  })
  assert_true(sq_one(old, "overlap by 30"), msg=old.join("\n"))
  assert_eq(sq_tree(sq_over(pulled=true)), [])
}

// (b) a field's placeholder cut down to nothing

///|
/// A field of the window's tree in a box `w` wide, its placeholder a long way and two shorter.
fn sq_field(w : Double) -> (@view.View) -> Unit {
  fn(root) {
    root.box(fn(h) {
      h.width(Is(Some(w))).height(Is(Some(20.0))) |> ignore
      field(
        h,
        Field::new(text=""),
        placeholder="the longest way of saying it",
        shorter=["a shorter way", "short way"],
        font_size=10.0,
        max_lines=1,
      )
      |> ignore
    })
    |> ignore
  }
}

///|
test "(b) the window tree's field's placeholder cut down to nothing, as an old view's; said a shorter way, or cut keeping some, none" {
  let tree = sq_tree(sq_field(8.0))
  assert_true(sq_one(tree, "placeholder cut to 0"), msg=tree.join("\n"))
  let old = sq_old(fn(c) {
    c.box(w=Px(8.0), h=Px(20.0), fn() {
      c.editor("field", placeholder="the longest way of saying it", shorter=["a shorter way", "short way"], font_size=10.0, max_lines=1, plain=true)
      |> ignore
    })
    |> ignore
  })
  assert_true(old.iter().any(fn(f) { f.contains("placeholder cut to 0") }), msg=old.join("\n"))
  assert_eq(sq_tree(sq_field(400.0)), [])
  assert_eq(sq_tree(sq_field(60.0)), [])
}

// (a) through the same rules, the one way of it

///|
test "(a) the window tree's words cut short without saying so; said so, or in a box said to be cut short, none" {
  let t = unsaid_cut_tester(unsaid_cut_long, fn(_v) {  })
  t.draw()
  let said = g().tree_squeeze_said()
  assert_true(sq_one(said, "cut short without saying they may be"), msg=said.join("\n"))
  // (and Tester::squeeze_faults says it once: one way of it)
  assert_eq(t.squeeze_faults(), said)
  let t = unsaid_cut_tester(unsaid_cut_long, fn(v) { v.allow_ellipsis(Is(true)) |> ignore })
  t.draw()
  assert_eq(g().tree_squeeze_said(), [])
  let t = unsaid_cut_in_giving(fn(_o) {  })
  t.draw()
  assert_true(sq_one(g().tree_squeeze_said(), "cut short without saying"), msg=g().tree_squeeze_said().join("\n"))
  let t = unsaid_cut_in_giving(fn(o) { o.cuts(Is(true)) |> ignore })
  t.draw()
  assert_eq(g().tree_squeeze_said(), [])
}

// (g) cut short beside what shares their row: said they may be cut is Tree::allows_ellipsis's say, the one of (a)

///|
/// A row 200 wide: a box growing in it from nothing holding words on one line (`allowed`: said they may end in an
/// ellipsis; `gives`: the words its own, it giving way along the row), then a box 120 wide. Alone in the row the
/// words fit; beside the box, cut.
fn sq_cut_row(gives~ : Bool, allowed~ : Bool) -> (@view.View) -> Unit {
  fn(root) {
    root.box(fn(row) {
      row.row(Is(true)).width(Is(Some(200.0))).lines_up(Is(Some(@view.Middle))) |> ignore
      row.box(fn(w) {
        w.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
        if gives {
          w.shrink(Is(1.0)).words(Is("the words of a row here"), look=sq_look()) |> ignore
        } else {
          w.box(fn(v) {
            v.words(Is("the words of a row here"), look=sq_look()) |> ignore
            if allowed {
              v.allow_ellipsis(Is(true)) |> ignore
            }
          })
          |> ignore
        }
      })
      |> ignore
      row.box(fn(v) { v.width(Is(Some(120.0))).height(Is(Some(20.0))).ground(Is(0x00FF00FFL)) |> ignore }) |> ignore
    })
    |> ignore
  }
}

///|
test "(g) the window tree's words cut short for what shares their row: said they may be (as (a) has it), none; not said, as an old view's" {
  let unsaid = sq_tree(sq_cut_row(gives=false, allowed=false))
  assert_true(unsaid.iter().any(fn(f) { f.contains("cut short for what shares their row") }), msg=unsaid.join("\n"))
  let old = sq_old(fn(c) {
    c.box(dir=Row, w=Px(200.0), fn() {
      c.box(w=Fill(1.0), fn() { c.text("the words of a row here", size=10.0, wrap=false) |> ignore }) |> ignore
      c.box(w=Px(120.0), h=Px(20.0), bg=0x00FF00FFL, fn() {  }) |> ignore
    })
    |> ignore
  })
  assert_true(old.iter().any(fn(f) { f.contains("cut short for what shares their row") }), msg=old.join("\n"))
  // (said so: the words' own say, or their own giving way along the row, as Tree::allows_ellipsis has it)
  let allowed = sq_tree(sq_cut_row(gives=false, allowed=true))
  assert_eq(allowed.filter(fn(f) { f.contains("shares their row") }), [], msg=allowed.join("\n"))
  let gives = sq_tree(sq_cut_row(gives=true, allowed=false))
  assert_eq(gives.filter(fn(f) { f.contains("shares their row") }), [], msg=gives.join("\n"))
}

///|
test "(g) words broken onto lines for what shares their row are said, cut short or not: what may be cut short is not what may break" {
  let tree = sq_tree(sq_note_row(titled=false, allowed=true))
  assert_true(sq_one(tree, "2 lines for what shares their row"), msg=tree.join("\n"))
}

// (g) what gives way beside words that go on in lines: how narrow each may come to as the layout takes it

///|
/// A row 160 wide: words on lines growing in it from nothing, giving way, then words on one line, giving way down to
/// `least` (none: as the layout takes what says none, its padding across: 0).
fn sq_gives_row(least : Double?) -> (@view.View) -> Unit {
  fn(root) {
    root.box(fn(row) {
      row.row(Is(true)).width(Is(Some(160.0))) |> ignore
      row.box(fn(v) {
        v.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
        v.words(Is("a short name"), look=sq_look(wrap=true)) |> ignore
      })
      |> ignore
      row.box(fn(v) {
        v.shrink(Is(1.0)).words(Is("what its machine is, at length"), look=sq_look(wrap=true)) |> ignore
        match least {
          Some(l) => v.min_width(Is(Some(l))) |> ignore
          None => ()
        }
      })
      |> ignore
    })
    |> ignore
  }
}

///|
test "(g) words on lines beside what gives way too: what says no least gives way (as the layout has it, down to its padding), said; what may give none, not" {
  // (no least said: the layout gives it way down to nothing, so it is held to give way: said, never let pass)
  let unsaid = sq_tree(sq_gives_row(None))
  assert_true(unsaid.iter().any(fn(f) { f.contains("which gives way too") }), msg=unsaid.join("\n"))
  // (its least said as wide as it is: it gives none, nothing said)
  let kept = sq_tree(sq_gives_row(Some(400.0)))
  assert_eq(kept.filter(fn(f) { f.contains("which gives way too") }), [])
}

// (d) what is drawn where its own move says

///|
/// A row 600 wide in a window 400 wide, drawn where its offset, bound, says (`bound`: else nothing said of it), at 0.
fn sq_tape(bound~ : Bool) -> (@view.View) -> Unit {
  fn(root) {
    root.box(fn(t) {
      t.row(Is(true)).width(Is(Some(600.0))).height(Is(Some(20.0))).ground(Is(0x00FF00FFL)) |> ignore
      if bound {
        t.offset(By(fn() { (0.0, 0.0) })) |> ignore
      }
    })
    |> ignore
  }
}

///|
test "(d) a box wider than the window, drawn where its own bound offset says, at rest at 0: none; nothing said of it, past the edge" {
  assert_eq(sq_tree(sq_tape(bound=true)), [])
  let said = sq_tree(sq_tape(bound=false))
  assert_true(sq_one(said, "runs 200 past the window's edge"), msg=said.join("\n"))
}

// what is the tree's and what is an old view's, in one window

///|
test "an old view hosted in a node: its fault is the old view's alone, the node's beside it the tree's alone, each once" {
  // (no old frame round the tree: its old views are where it puts them, old_frame)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.width(Is(Some(200.0))).height(Is(Some(60.0))) |> ignore
      old(h, fn(c) { c.box(w=Px(30.0), fn() { c.text("Studio settings", size=14.0) |> ignore }) |> ignore }).grow(Is(1.0)) |> ignore
    })
    |> ignore
    sq_wrapped(30.0)(root)
  })
  t.draw()
  let tree = g().tree_squeeze_said()
  assert_true(sq_one(tree, "wrapped 30 across"), msg=tree.join("\n"))
  // (the tree's names the node, made here; the old view's, its box)
  assert_true(tree[0].contains("made at"), msg=tree[0])
  let all = t.squeeze_faults().filter(fn(f) { f.contains("wrapped") })
  assert_eq(all.length(), 2, msg=t.squeeze_faults().join("\n"))
  // (one the old view's, named in it; one the node's)
  assert_eq(all.filter(fn(f) { f.contains("in an old view") }).length(), 1, msg=all.join("\n"))
}

///|
test "an old view under a layer of nodes: its fault is the old view's alone, the layer's the tree's alone, each once" {
  let t = Tester::new(
    fn(c) { c.box(w=Px(30.0), fn() { c.text("Studio settings", size=14.0) |> ignore }) |> ignore },
    w=400.0,
    h=200.0,
    tree=fn(root) {
      root.box(fn(layer) {
        layer.over(Is(true)) |> ignore
        layer.box(fn(o) { o.height(Is(Some(100.0))) |> ignore }) |> ignore
        sq_over()(layer)
      })
      |> ignore
    },
  )
  t.draw()
  let tree = g().tree_squeeze_said()
  assert_true(sq_one(tree, "overlap by 30"), msg=tree.join("\n"))
  let all = t.squeeze_faults()
  assert_eq(all.length(), 2, msg=all.join("\n"))
  assert_true(sq_one(all.filter(fn(f) { f.contains("wrapped 30 across") }), "wrapped 30 across"), msg=all.join("\n"))
  assert_true(sq_one(all.filter(fn(f) { f.contains("overlap") }), "overlap by 30"), msg=all.join("\n"))
}
