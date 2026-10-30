// The checks of what a frame draws (contrast, words held seen whole, words over words) on what the window's tree draws:
// who drew each instance and each glyph's cell kept with the node's instances, as made and as kept drawn again.

///|
/// A Tester over the window's tree `make` builds, drawn.
fn tree_tester(make : (@view.View) -> Unit) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, words_over_held=false)
  set_view_app(make)
  t.draw()
  t
}

///|
test "contrast: a node of the tree's words too faint on its ground found, as made and as its instances kept drawn again" {
  let t = tree_tester(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).ground(Is(0xFFFFFFFFL)) |> ignore
      b.box(fn(w) { w.width(Is(Some(200.0))).words(Is("faint words"), ink=0xDDDDDDFFL) |> ignore }) |> ignore
    })
    |> ignore
  })
  let first = t.contrast_faults().filter(fn(f) { f.contains("faint words") })
  let made = view_painted().made
  let again = t.contrast_faults().filter(fn(f) { f.contains("faint words") })
  assert_eq((first.length(), again.length(), view_painted().made), (1, 1, made), msg="\{first} \{again}")
}

///|
/// Words of a node of the tree's ("held words"), a solid ground of another node over them drawn after (`covered`) or
/// below them: what the words held seen whole are drawn over by, on the frame first drawn and on one drawn again with
/// all of it moved (the nodes' instances kept, composed where they are then), and whether none was made again.
fn held_covered(covered : Bool) -> ((String, Double, Double)?, (String, Double, Double)?, Bool) {
  let dx = @signals.signal(0.0, same=fn(a, b) { a == b })
  let t = tree_tester(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).offset(By(fn() { (dx.get(), 0.0) })) |> ignore
      b.box(fn(w) { w.width(Is(Some(200.0))).words(Is("held words")) |> ignore }) |> ignore
    })
    |> ignore
    root.box(fn(b) {
      b.over(Is(true)).offset(By(fn() { (dx.get(), if covered { 0.0 } else { 100.0 }) })) |> ignore
      b.box(fn(g) { g.width(Is(Some(200.0))).height(Is(Some(30.0))).ground(Is(0x336699FFL)) |> ignore }) |> ignore
    })
    |> ignore
  })
  let first = g().seen_whole_faults("held words")
  let made = view_painted().made
  dx.set(40.0)
  t.frame_at(t.time() + 16.0)
  (first, g().seen_whole_faults("held words"), view_painted().made == made)
}

///|
test "words held seen whole: a node of the tree's words drawn over by another's solid ground found, first and as kept drawn again; beside them, none" {
  let (first, again, kept) = held_covered(true)
  assert_true(first is Some(_) && again is Some(_) && kept, msg="\{first} \{again} \{kept}")
  let (first, again, _) = held_covered(false)
  assert_eq((first, again), (None, None))
}

///|
/// Two nodes of the tree's words side by side in a row (each glyph's picture spilling past its advance into the
/// other's, their cells meeting, not crossing), the row drawn `dx` off: the words over words found, on the frame first
/// drawn and on one drawn again moved, the instances kept.
fn side_by_side() -> (Int, Int, Bool) {
  let dx = @signals.signal(0.0, same=fn(a, b) { a == b })
  let t = tree_tester(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).offset(By(fn() { (dx.get(), 0.0) })) |> ignore
      b.box(fn(r) {
        r.row(Is(true)) |> ignore
        r.box(fn(w) { w.words(Is("WWW")) |> ignore }) |> ignore
        r.box(fn(w) { w.words(Is("WWW")) |> ignore }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  let first = g().words_over_faults().length()
  let made = view_painted().made
  dx.set(40.0)
  t.frame_at(t.time() + 16.0)
  (first, g().words_over_faults().length(), view_painted().made == made)
}

///|
test "words over words: two nodes of the tree's words side by side, their glyphs' pictures meeting but not their cells: none, made and moved as kept" {
  assert_eq(side_by_side(), (0, 0, true))
}

///|
/// An icon of a node of the tree's (a 20 square's shapes in `ink` on a white ground), what is over it drawn after it
/// (`covered`: a solid ground of another node; else nothing) and how opaque its node is: the contrast faults said of an
/// icon, as made and as its instances kept drawn again.
fn icon_faults(ink : Int64, covered : Bool, alpha : Double) -> (Array[String], Array[String]) {
  let t = tree_tester(fn(root) {
    root.box(fn(b) { b.over(Is(true)).ground(Is(0xFFFFFFFFL)) |> ignore }) |> ignore
    root.box(fn(n) {
      n
      .over(Is(true))
      .offset(Is((40.0, 40.0)))
      .width(Is(Some(20.0)))
      .height(Is(Some(20.0)))
      .alpha(Is(alpha))
      .shapes(Is([shape_of([([2.0, 2.0, 18.0, 2.0, 18.0, 18.0, 2.0, 18.0], true)], fill=0x000000FFL)]))
      .tint(Is(ink))
      |> ignore
    })
    |> ignore
    if covered {
      root.box(fn(b) {
        b.over(Is(true)).offset(Is((30.0, 30.0))).width(Is(Some(40.0))).height(Is(Some(40.0))).ground(Is(0x336699FFL))
        |> ignore
      })
      |> ignore
    }
  })
  let icons = fn() { t.contrast_faults().filter(fn(f) { f.has_prefix("icon (a node of the window's tree's)") }) }
  let first = icons()
  (first, icons())
}

///|
test "contrast: a node of the tree's icon too faint on its ground found, as an old view's is, as made and kept drawn again; covered, unseen or strong enough, none" {
  let (first, again) = icon_faults(0xDDDDDDFFL, false, 1.0)
  assert_true(first.length() == 1 && again == first, msg="\{first} \{again}")
  assert_true(first[0].contains("under \{contrast_icon_least}"), msg="\{first}")
  assert_eq(icon_faults(0xDDDDDDFFL, true, 1.0), ([], []))
  assert_eq(icon_faults(0xDDDDDDFFL, false, 0.0), ([], []))
  assert_eq(icon_faults(0x333333FFL, false, 1.0), ([], []))
}

///|
test "contrast: a node of the tree's with words too faint and an icon dark enough beside them: the words found, each checked as its own, as made and kept drawn again; the other way round, the icon" {
  let faults = fn(words : Int64, icon : Int64) {
    let t = tree_tester(fn(root) {
      root.box(fn(b) { b.over(Is(true)).ground(Is(0xFFFFFFFFL)) |> ignore }) |> ignore
      root.box(fn(n) {
        n
        .over(Is(true))
        .offset(Is((20.0, 40.0)))
        .width(Is(Some(200.0)))
        .words(Is("faint words"), ink=words)
        .shapes(Is([shape_of([([170.0, 2.0, 186.0, 2.0, 186.0, 18.0, 170.0, 18.0], true)], fill=icon)]))
        |> ignore
      })
      |> ignore
    })
    let said = fn() {
      t
      .contrast_faults()
      .filter(fn(f) { f.contains("(a node of the window's tree's)") })
      .map(fn(f) { if f.has_prefix("icon") || f.has_prefix("line") { "shape" } else { "words" } })
    }
    let first = said()
    (first, said())
  }
  assert_eq(faults(0xDDDDDDFFL, 0x333333FFL), (["words"], ["words"]))
  assert_eq(faults(0x333333FFL, 0xDDDDDDFFL), (["shape"], ["shape"]))
}

///|
/// A node of the tree's shape `w` by `h` in grey 0x999999 (2.85:1 on white: past a line's least, short of an icon's) on
/// a white ground, in a node 200 wide: the contrast faults said of it.
fn grey_shape_faults(w : Double, h : Double) -> Array[String] {
  let t = tree_tester(fn(root) {
    root.box(fn(b) { b.over(Is(true)).ground(Is(0xFFFFFFFFL)) |> ignore }) |> ignore
    root.box(fn(n) {
      n
      .over(Is(true))
      .offset(Is((20.0, 20.0)))
      .width(Is(Some(200.0)))
      .height(Is(Some(120.0)))
      .shapes(Is([shape_of([([0.0, 0.0, w, 0.0, w, h, 0.0, h], true)], fill=0x999999FFL)]))
      |> ignore
    })
    |> ignore
  })
  t.contrast_faults().filter(fn(f) { f.contains("(a node of the window's tree's)") })
}

///|
test "contrast: a node of the tree's shape checked as the whole shape is, not by its pieces: a narrow tall one a line, a small one an icon" {
  assert_eq(grey_shape_faults(20.0, 100.0), [])
  let small = grey_shape_faults(16.0, 16.0)
  assert_true(small.length() == 1 && small[0].has_prefix("icon"), msg="\{small}")
}

///|
test "contrast: a node of the tree's icon after an old view whose field's handle is raised over everything: still checked as an icon, as made and kept drawn again" {
  let field = Field::new()
  field.set("hello world")
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform=2, words_over_held=false)
  set_view_app(fn(root) {
    root.box(fn(b) { b.over(Is(true)).ground(Is(0xFFFFFFFFL)) |> ignore }) |> ignore
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(300.0))).height(Is(Some(80.0))) |> ignore
      old(b, fn(c) { c.editor("field", font_size=16.0, field~) |> ignore }).grow(Is(1.0)) |> ignore
    })
    |> ignore
    root.box(fn(n) {
      n
      .over(Is(true))
      .offset(Is((240.0, 150.0)))
      .width(Is(Some(20.0)))
      .height(Is(Some(20.0)))
      .shapes(Is([shape_of([([2.0, 2.0, 18.0, 2.0, 18.0, 18.0, 2.0, 18.0], true)], fill=0xDDDDDDFFL)]))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.tap(20.0, 10.0)
  t.draw()
  assert_true(g().editors.get(g().focus).unwrap().handle_on)
  let icons = fn() { t.contrast_faults().filter(fn(f) { f.has_prefix("icon (a node of the window's tree's)") }) }
  let first = icons()
  assert_true(first.length() == 1 && icons() == first, msg="\{first}")
}
