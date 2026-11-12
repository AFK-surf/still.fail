// Words a part of the window's tree says are at the size they are said (View::box's `words_as_said`: a mark's letter),
// measured and drawn so whatever the system's size of words, all made in it with them; what is outside it grows as
// ever.

///|
/// How these tests' words are set: 10 points on a line of 14, on one line.
fn was_look() -> @view.WordsLook {
  { size: 10.0, weight: 400, line: 14.0, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }
}

///|
/// The ink of the words inside the part, and of those outside it.
fn was_in_ink() -> Int64 {
  0xFF0000FFL
}

///|
fn was_out_ink() -> Int64 {
  0x0000FFFFL
}

///|
/// A window 400 by 200 at the system's size of words `scale`: words in a part said to be at their size where `said`,
/// words outside it under them. What it draws, the words (Tester::words: where and how big each is laid out) and the
/// glyphs of each ink (where each is drawn).
fn was_drawn(
  said : Bool,
  scale : Double,
) -> (Array[(String, Double, Double, Double, Double, Double)], Array[(Double, Double, Int64)]) {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0, tree=fn(root) {
    root.box(words_as_said=said, fn(m) {
      m.box(fn(w) { w.words(Is("里面 Studio"), ink=was_in_ink(), look=was_look()) |> ignore }) |> ignore
    })
    |> ignore
    root.box(fn(w) { w.words(Is("外面 Studio"), ink=was_out_ink(), look=was_look()) |> ignore }) |> ignore
  })
  t.set_font_scale(scale)
  t.draw()
  (t.words(), t.drawn_glyphs())
}

///|
test "words said to be at their size: at the system's 1.3 drawn as at 1 not said, each glyph where it was; those outside grow as ever" {
  let (said_words, said_glyphs) = was_drawn(true, 1.3)
  let (plain_words, plain_glyphs) = was_drawn(false, 1.0)
  let (grown_words, _) = was_drawn(false, 1.3)
  let inside = fn(ws : Array[(String, Double, Double, Double, Double, Double)]) {
    ws.filter(fn(w) { w.0.contains("里面") })
  }
  let outside = fn(ws : Array[(String, Double, Double, Double, Double, Double)]) {
    ws.filter(fn(w) { w.0.contains("外面") })
  }
  let inked = fn(gs : Array[(Double, Double, Int64)], k : Int64) { gs.filter(fn(g) { g.2 == k }) }
  assert_eq(inside(said_words).length(), 1)
  assert_eq(inside(said_words), inside(plain_words))
  assert_true(inked(said_glyphs, was_in_ink()).length() > 0)
  assert_eq(inked(said_glyphs, was_in_ink()), inked(plain_glyphs, was_in_ink()))
  // (what is outside it as tall as at 1.3 not said: grown, taller than at 1; under the inside, as high up as that is
  // shorter than it is grown)
  let o = outside(said_words)
  let g = outside(grown_words)
  let p = outside(plain_words)
  assert_eq(o.length(), 1)
  assert_eq(o[0].4, g[0].4)
  assert_true(o[0].4 > p[0].4, msg="\{Repr(o)} \{Repr(p)}")
  // (the inside not said at 1.3 grown: what the part's saying kept it from)
  assert_true(inside(grown_words)[0].4 > inside(plain_words)[0].4)
}

///|
test "what is made in it later (a show coming to show, what that makes) takes it: at 1 at the system's 1.3, its words_scale 1" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let later : Ref[@view.View?] = Ref(None)
  let outer : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0, tree=fn(root) {
    outer.val = Some(root)
    root.box(words_as_said=true, fn(m) {
      m.show(fn() { on.get() }, fn(s) {
        s.box(fn(w) {
          later.val = Some(w)
          w.words(Is("后来 Studio"), look=was_look()) |> ignore
        })
        |> ignore
      })
    })
    |> ignore
  })
  t.set_font_scale(1.3)
  t.draw()
  on.set(true)
  t.run_for(move_most_ms)
  let w = t.words().filter(fn(w) { w.0.contains("后来") })
  assert_eq(w.length(), 1)
  // (asked while this Tester's host is the one: another's says another size of words)
  assert_eq(later.val.unwrap().words_scale(), 1.0)
  assert_eq(outer.val.unwrap().words_scale(), 1.3)
  t.set_font_scale(1.0)
  let (plain, _) = was_drawn(false, 1.0)
  let at_one = plain.filter(fn(w) { w.0.contains("里面") })
  // (as tall and as wide as words as long at 1: their line 14)
  assert_eq(w[0].4, at_one[0].4)
  assert_eq(w[0].4, 14.0)
}

///|
test "a height worked out of words_scale in it is at 1: a box said 14 at the system's 1.3 is 14 high, one outside it as tall as 14 is drawn at 1.3" {
  let inside : Ref[@view.View?] = Ref(None)
  let beside : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0, tree=fn(root) {
    root.box(words_as_said=true, fn(m) {
      m.box(fn(b) {
        inside.val = Some(b)
        b.height(By(fn() { Some(sp_at(b.words_scale(), 14.0)) })) |> ignore
      })
      |> ignore
    })
    |> ignore
    root.box(fn(b) {
      beside.val = Some(b)
      b.height(By(fn() { Some(sp_at(b.words_scale(), 14.0)) })) |> ignore
    })
    |> ignore
  })
  t.set_font_scale(1.3)
  t.draw()
  assert_eq(inside.val.unwrap().laid_size().1, 14.0)
  assert_eq(beside.val.unwrap().laid_size().1, sp_at(1.3, 14.0))
  assert_true(sp_at(1.3, 14.0) > 14.0)
  t.set_font_scale(1.0)
}

///|
test "a box said 14 round a line of 14 said to be at its size: at the system's 1.3 fixed_outgrown says none of it; not said, it does" {
  let boxed = fn(said : Bool) {
    fn(root : @view.View) {
      root.box(words_as_said=said, fn(m) {
        m.box(fn(b) {
          b.height(Is(Some(14.0))) |> ignore
          b.box(fn(w) { w.words(Is("Studio"), look=was_look()) |> ignore }) |> ignore
        })
        |> ignore
      })
      |> ignore
    }
  }
  let outgrown = fn(said : Bool) {
    let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0, tree=boxed(said))
    t.set_font_scale(1.3)
    t.draw()
    let f = t.fixed_outgrown()
    t.set_font_scale(1.0)
    f
  }
  assert_eq(outgrown(true), [])
  assert_eq(outgrown(false).length(), 1)
}

///|
test "a field made where words are said to be at their size: a fault saying where and why; elsewhere none" {
  let told : Array[String] = []
  @view.faults_stop.val = false
  @view.fault_told.val = Some(fn(said) { told.push(said) })
  let made = fn(said : Bool) {
    let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0, tree=fn(root) {
      root.box(words_as_said=said, fn(m) { field(m, Field::new(text="甲"), label="名字") |> ignore }) |> ignore
    })
    t.draw()
  }
  made(false)
  let before = told.length()
  made(true)
  @view.faults_stop.val = true
  @view.fault_told.val = None
  assert_eq(before, 0, msg=told.join("\n"))
  assert_eq(told.length(), 1, msg=told.join("\n"))
  assert_true(told[0].contains("a field made at") && told[0].contains("words_as_said"), msg=told[0])
}
