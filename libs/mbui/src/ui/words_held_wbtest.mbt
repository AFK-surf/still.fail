// Words a box with its height said does not hold (words_held.mbt): said of a node of the window's tree and of an old
// view's box; what lets its words push it open (a least), what lies apart from it on purpose, and a height worked out of
// the words' line at the system's size of words, not.

///|
/// How these tests' words are set: 10 points on a line of 14, on one line.
fn wh_look() -> @view.WordsLook {
  { size: 10.0, weight: 400, line: 14.0, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }
}

///|
/// What Tester::fixed_outgrown says of a window 400 by 200 made by `tree`, the system's size of words `scale`.
fn wh_tree(tree : (@view.View) -> Unit, scale? : Double = 1.0) -> Array[String] {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0, tree~)
  if scale != 1.0 {
    t.set_font_scale(scale)
  }
  t.draw()
  t.fixed_outgrown()
}

///|
/// A box `h` high (by `held`: its height, else a least of it) holding one line of words (`words`: what is said of
/// their node besides).
fn wh_box(
  h : (@view.View) -> Double?,
  least? : Bool = false,
  words? : (@view.View) -> Unit = fn(_w) {  },
) -> (@view.View) -> Unit {
  fn(root) {
    root.box(fn(b) {
      if least {
        b.min_height(By(fn() { h(b) })) |> ignore
      } else {
        b.height(By(fn() { h(b) })) |> ignore
      }
      b.box(fn(w) {
        w.words(Is("Studio"), look=wh_look()) |> ignore
        words(w)
      })
      |> ignore
    })
    |> ignore
  }
}

///|
test "words on a line of 14 in a box said 10 high: said, with the box and by how much; in one said 14, none" {
  let f = wh_tree(wh_box(fn(_b) { Some(10.0) }))
  assert_eq(f.length(), 1, msg=f.join("\n"))
  assert_true(f[0].contains("Studio") && f[0].contains("its height said, by 4"), msg=f[0])
  // (and where the box was made)
  assert_true(f[0].contains("made at"), msg=f[0])
  assert_eq(wh_tree(wh_box(fn(_b) { Some(14.0) })), [])
}

///|
test "a least of 10 (min_height) lets the words push the box open: none" {
  assert_eq(wh_tree(wh_box(fn(_b) { Some(10.0) }, least=true)), [])
}

///|
test "at the system's size of words 1.3 a box said 14 no longer holds the line; one as high as the line at that size does" {
  let f = wh_tree(wh_box(fn(_b) { Some(14.0) }), scale=1.3)
  assert_eq(f.length(), 1, msg=f.join("\n"))
  assert_eq(wh_tree(wh_box(fn(b) { Some(sp_at(b.words_scale(), 14.0)) }), scale=1.3), [])
}

///|
test "words apart from the box on purpose: pulled out of it by a margin below 0, laid over it, drawn at another size: none" {
  let small = fn(_b : @view.View) { Some(10.0) }
  assert_eq(wh_tree(wh_box(small, words=fn(w) { w.margin(Is((0.0, -2.0, 0.0, -2.0))) |> ignore })), [])
  assert_eq(wh_tree(wh_box(small, words=fn(w) { w.over(Is(true)) |> ignore })), [])
  assert_eq(wh_tree(wh_box(small, words=fn(w) { w.scale(Is(0.5)) |> ignore })), [])
  // (the box and its words drawn smaller than laid out together, as a row lifted in the hand: judged at rest)
  let lifted = fn(root : @view.View) {
    root.box(fn(l) {
      l.scale(Is(0.9)) |> ignore
      wh_box(fn(_b) { Some(14.0) })(l)
    })
    |> ignore
  }
  assert_eq(wh_tree(lifted), [])
}

///|
test "an old view's box said 10 high round its words: said; let grow, none" {
  let t = Tester::new(fn(c) { c.box(h=Px(10.0), fn() { c.text("Studio", wrap=false) |> ignore }) |> ignore }, w=400.0, h=200.0)
  t.draw()
  let f = t.fixed_outgrown()
  assert_eq(f.length(), 1, msg=f.join("\n"))
  let t = Tester::new(fn(c) { c.box(fn() { c.text("Studio", wrap=false) |> ignore }) |> ignore }, w=400.0, h=200.0)
  t.draw()
  assert_eq(t.fixed_outgrown(), [])
}
