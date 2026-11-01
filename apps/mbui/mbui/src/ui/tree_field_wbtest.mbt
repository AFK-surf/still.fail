// A field of the window's tree's (ui's field) does what an old view's field does in the same place (Ctx::editor in an
// old view hosted there): each case run on both, the same results asked of both.

///|
/// A window 300 by 200 whose tree holds, at `at` ((20, 20)), a box 200 by 20 (`tall`, 100) drawn `s` as big about its top left, holding a
/// field of `f` (10 big, one line): the tree's own (`tree`) or an old view's editor hosted there. What its words given
/// up were told, in order (the tree's: `submitted`; the old view's: as its build reads them). `at` off the pixels: the
/// box on them (at its whole pixels), the field in it as far off them as `at` is (the tree's, a node of its so far in
/// it; the old view's, its editor's box so far in the old view: as an old view holding a field off the pixels).
fn one_field(
  tree : Bool,
  s : @signals.Signal[Double],
  f : Field,
  said : Array[String],
  platform? : Int = 0,
  tall? : Bool = false,
  at? : (Double, Double) = (20.0, 20.0),
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform~)
  set_view_app(fn(root) {
    root.box(fn(h) {
      let whole = (at.0.floor(), at.1.floor())
      let off = (at.0 - whole.0, at.1 - whole.1)
      h
      .over(Is(true))
      .offset(Is(whole))
      .width(Is(Some(200.0)))
      // (`tall`: 100, room under the field for what hangs from it, a handle; an old view hosted there all of it)
      .height(Is(Some(if tall { 100.0 } else { 20.0 })))
      .scale(By(fn() { s.get() }), about=At(0.0, 0.0))
      |> ignore
      if tree && off == (0.0, 0.0) {
        // (as tall as its words lay out, as the old view's editor is in its box: what holds it no taller)
        field(h, f, font_size=10.0, max_lines=1, submitted=fn(w) { said.push(w) }) |> ignore
      } else if tree {
        h.box(fn(v) {
          v.over(Is(true)).offset(Is(off)).width(Is(Some(200.0))) |> ignore
          field(v, f, font_size=10.0, max_lines=1, submitted=fn(w) { said.push(w) }) |> ignore
        })
        |> ignore
      } else {
        old(h, fn(c) {
          c.box(w=Px(200.0), h=Px(20.0), left=off.0, top=off.1, fn() {
            match c.editor("e", field=f, font_size=10.0, max_lines=1, plain=true).submitted {
              Some(w) => said.push(w)
              None => ()
            }
          })
          |> ignore
        })
        .grow(Is(1.0))
        |> ignore
      }
    })
    |> ignore
  })
  t.draw()
  t
}

///|
/// The field drawn `scale` as big at `at` ((20, 20)), tapped 33 along its line (in its own terms), "ab" typed at its end
/// and Enter: its words, the caret the tap put down, what the host was told (the field's words and caret; where the
/// caret is), what its words given up were told, the lines of words drawn (where they stand: Tester::text_runs).
fn field_typed(
  tree : Bool,
  scale : Double,
  at? : (Double, Double) = (20.0, 20.0),
) -> (String, Int, (Bool, String, Int, Int), (Double, Double, Double, Double), Array[String], Array[(String, Double, Double, Double, Double, Double)]) {
  let s = @signals.signal(scale, same=fn(a, b) { a == b })
  let f = Field::new(text="abcdefghij")
  let said = []
  let t = one_field(tree, s, f, said, at~)
  t.tap(at.0 + 33.0 * scale, at.1 + 10.0 * scale)
  t.draw()
  let tapped = f.selection().1
  f.set(f.text(), caret=f.text().length())
  t.draw()
  t.type_text("ab")
  t.draw()
  let told = t.ime()
  let rect = t.ime_rect()
  t.enter()
  // (frames drawn after it: told no more)
  t.draw()
  t.draw()
  (f.text(), tapped, told, rect, said, t.text_runs().map(fn(r) { (r.text, r.x0, r.x1, r.base, r.top, r.bottom) }))
}

///|
test "a field of the tree's as an old view's in its place: tapped, typed into and Enter; the caret, the host told, its words given up once, drawn" {
  for scale in [1.0, 0.5] {
    let (words, tapped, told, rect, said, drawn) = field_typed(false, scale)
    assert_true(tapped > 0 && tapped < 10, msg="old, \{scale}: the tap's caret in its words: \{tapped}")
    assert_eq((words, told, said), ("abcdefghijab", (true, "abcdefghijab", 12, 12), ["abcdefghijab"]), msg="old, \{scale}")
    assert_true(drawn.iter().any(fn(r) { r.0 == "abcdefghijab" }), msg="old, \{scale}: its words drawn: \{drawn}")
    let theirs = field_typed(true, scale)
    assert_eq(theirs, (words, tapped, told, rect, said, drawn), msg="the tree's, \{scale}: as the old view's: \{theirs}, the old view's \{(words, tapped, told, rect, said, drawn)}")
  }
}

///|
/// The field drawn `scale` as big at `at`, tapped and "ab" typed at its end: the caret drawn (where, how big) and where
/// the host is told it is.
fn caret_typed(tree : Bool, scale : Double, at : (Double, Double)) -> (Array[Double], (Double, Double, Double, Double)) raise {
  let s = @signals.signal(scale, same=fn(a, b) { a == b })
  let f = Field::new(text="abcdefghij")
  let t = one_field(tree, s, f, [], at~)
  t.tap(at.0 + 33.0 * scale, at.1 + 10.0 * scale)
  t.draw()
  f.set(f.text(), caret=f.text().length())
  t.draw()
  t.type_text("ab")
  t.draw()
  // (the caret's colour, 0x0A84FF: its red; taller than wide, whatever it is drawn as big as)
  let carets = insts().filter(fn(i) { i[5] == 0.0 && i[8] == 10.0 / 255.0 && i[3] > i[2] })
  guard carets is [.., c] else { fail("\{tree}, \{scale}, at \{at}: no caret drawn") }
  (c[0:4].to_array(), t.ime_rect())
}

///|
test "a field of the tree's as an old view's, placed off the pixels, whole and half as big: its words, the caret drawn and where the host is told it is, each where the old view's are" {
  for at in [(20.0, 20.0), (20.13, 20.37)] {
    for scale in [1.0, 0.5] {
      let old_typed = field_typed(false, scale, at~)
      let theirs = field_typed(true, scale, at~)
      assert_eq(theirs, old_typed, msg="the tree's, at \{at}, \{scale}: as the old view's: \{theirs}, the old view's \{old_typed}")
      let old_caret = caret_typed(false, scale, at)
      let caret = caret_typed(true, scale, at)
      assert_eq(caret, old_caret, msg="the tree's caret, at \{at}, \{scale}: drawn and told as the old view's: \{caret}, the old view's \{old_caret}")
    }
  }
}

///|
test "a field of the tree's, half as big: where the host is told its caret is, as the old view's whole, half as big about its top left" {
  let (_, _, _, (x, y, w, h), _, _) = field_typed(true, 1.0)
  let (_, _, _, half, _, _) = field_typed(true, 0.5)
  assert_eq(half, (20.0 + (x - 20.0) * 0.5, 20.0 + (y - 20.0) * 0.5, w * 0.5, h * 0.5))
}

///|
test "a field of the tree's: no old view in the window, its node read out as a field of its words" {
  let s = @signals.signal(1.0, same=fn(a, b) { a == b })
  let f = Field::new(text="abc")
  let t = one_field(true, s, f, [])
  assert_eq(old_islands.length(), 0, msg="no old view hosted")
  let n = t.get(TextField)
  assert_eq(n.value, "abc")
}

///|
test "a field of the tree's as an old view's: the keyboard put away, the field let go of, the host told so" {
  for tree in [false, true] {
    let s = @signals.signal(1.0, same=fn(a, b) { a == b })
    let f = Field::new(text="abc")
    let t = one_field(tree, s, f, [], platform=2)
    t.tap(40.0, 30.0)
    t.draw()
    assert_true(t.ime().0, msg="\{tree}: focused, told")
    t.keyboard_gone()
    assert_true(!t.ime().0, msg="\{tree}: let go of, told")
  }
}

///|
/// A window 300 by 200 holding at (20, 20) a box 80 by 20 that cuts what it holds, in it one 200 by 20 drawn half as
/// big about its top left holding a field of `words` (10 big, one line): the tree's own (`tree`) or an old view's
/// editor hosted there. What is drawn, each with what cuts it (Tester::drawn_cut).
fn field_cut_half(tree : Bool, words : String) -> Array[(Int, Double, Double, Double, Double, (Double, Double, Double, Double))] {
  let f = Field::new(text=words)
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(o) {
      o.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(80.0))).height(Is(Some(20.0))).clips(Is(true)) |> ignore
      o.box(fn(h) {
        h.width(Is(Some(200.0))).height(Is(Some(20.0))).scale(Is(0.5), about=At(0.0, 0.0)) |> ignore
        if tree {
          field(h, f, font_size=10.0, max_lines=1) |> ignore
        } else {
          old(h, fn(c) { c.box(w=Px(200.0), h=Px(20.0), fn() { c.editor("e", field=f, font_size=10.0, max_lines=1, plain=true) |> ignore }) |> ignore })
          .grow(Is(1.0))
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.draw()
  t.drawn_cut()
}

///|
test "a field of the tree's drawn half as big in a box that cuts it short: its words drawn and cut as the old view's in its place, to the box's end" {
  let words = "abcdefghijklmnopqrstuvwxyz0123456789"
  let old_cut = field_cut_half(false, words)
  assert_true(old_cut.iter().any(fn(d) { d.5.2 == 100.0 }), msg="the old view's: cut at the box's end, 100: \{old_cut}")
  let theirs = field_cut_half(true, words)
  let differ = fn(a : Array[(Int, Double, Double, Double, Double, (Double, Double, Double, Double))], b : Array[(Int, Double, Double, Double, Double, (Double, Double, Double, Double))]) {
    let mut k = 0
    while k < a.length() && k < b.length() && a[k] == b[k] {
      k += 1
    }
    k
  }
  let k = differ(theirs, old_cut)
  assert_eq(
    theirs,
    old_cut,
    msg="the tree's: as the old view's: \{theirs.length()} drawn, the old view's \{old_cut.length()}; first apart at \{k}: \{theirs.get(k)}, the old view's \{old_cut.get(k)}",
  )
}

///|
test "a field of the tree's let go, its Field then an old view's editor's: no longer the tree's, typed into and told where it is drawn as the old view's" {
  let tree = @signals.signal(true, same=fn(a, b) { a == b })
  let f = Field::new(text="abc")
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(200.0))).height(Is(Some(20.0))).scale(Is(0.5), about=At(0.0, 0.0)) |> ignore
      h.show(fn() { tree.get() }, fn(v) {
        v.width(Is(Some(200.0))).height(Is(Some(20.0))) |> ignore
        field(v, f, font_size=10.0, max_lines=1) |> ignore
      })
      h.show(fn() { !tree.get() }, fn(v) {
        v.width(Is(Some(200.0))).height(Is(Some(20.0))) |> ignore
        old(v, fn(c) { c.box(w=Px(200.0), h=Px(20.0), fn() { c.editor("e", field=f, font_size=10.0, max_lines=1, plain=true) |> ignore }) |> ignore })
        .grow(Is(1.0))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  tree.set(false)
  // (as its node is let go, before anything is built or drawn again: the old view's editor not yet given it)
  assert_true(f.st.tree_node is None, msg="the tree's no longer")
  assert_eq(tree_fields.length(), 0, msg="no field of the tree's left")
  t.draw()
  t.tap(20.0 + 1.0, 25.0)
  t.draw()
  t.type_text("d")
  t.draw()
  let (x, y, w, h) = t.ime_rect()
  assert_eq(
    (f.text(), x >= 20.0 && x < 120.0 && y >= 20.0 && y < 30.0 && h <= 10.0),
    ("dabc", true),
    msg="\{(x, y, w, h)}: \{f.text()}, told \{t.ime()}, laid out \{f.st.tl is Some(_)}, focus \{g().focus}, old views \{old_islands.length()}",
  )
}

///|
/// The field of `words` (10 big, one line) drawn whole at (20, 20), the tree's own (`tree`) or an old view's editor
/// there, on `platform`'s host (0 a desktop's: a mouse's presses; 2 Android's: a finger's): `act` done to it, then what
/// it holds, what is picked in it, whether the floating menu is up, what was felt, what the host was told of it.
fn field_after(
  tree : Bool,
  words : String,
  act : (Tester, Field) -> Unit,
  platform? : Int = 0,
  scale? : Double = 1.0,
  tall? : Bool = false,
) -> (String, (Int, Int), Bool, Array[Haptic], (Bool, String, Int, Int)) {
  let s = @signals.signal(scale, same=fn(a, b) { a == b })
  let f = Field::new(text=words)
  let t = one_field(tree, s, f, [], platform~, tall~)
  act(t, f)
  t.draw()
  (f.text(), f.selection(), t.text_menu().0, t.haptics(), t.ime())
}

///|
/// `act` done to the old view's field and to the tree's in its place: the same comes of each.
fn field_alike(
  what : String,
  words : String,
  act : (Tester, Field) -> Unit,
  platform? : Int = 0,
  scale? : Double = 1.0,
  tall? : Bool = false,
) -> Unit raise {
  let old_one = field_after(false, words, act, platform~, scale~, tall~)
  let tree_one = field_after(true, words, act, platform~, scale~, tall~)
  assert_eq(tree_one, old_one, msg="\{what}: the tree's \{tree_one}, the old view's \{old_one}")
}

///|
test "a field of the tree's as an old view's: a double click picks the word, a triple the paragraph, a drag on from them by words; Shift widens what is picked to a click" {
  let words = "hello brave world, here we go"
  field_alike("a double click", words, fn(t, _) {
    t.tap(20.0 + 45.0, 30.0)
    t.tap(20.0 + 45.0, 30.0)
  })
  field_alike("a triple click", words, fn(t, _) {
    t.tap(20.0 + 45.0, 30.0)
    t.tap(20.0 + 45.0, 30.0)
    t.tap(20.0 + 45.0, 30.0)
  })
  field_alike("a double click dragged on", words, fn(t, _) {
    t.tap(20.0 + 45.0, 30.0)
    t.touch(0, 20.0 + 45.0, 30.0)
    t.touch(1, 20.0 + 110.0, 30.0)
    t.touch(2, 20.0 + 110.0, 30.0)
  })
  field_alike("Shift's click", words, fn(t, _) {
    t.tap(20.0 + 10.0, 30.0)
    t.hold_mods(mod_shift_key)
    t.tap(20.0 + 80.0, 30.0)
    t.hold_mods(0)
  })
}

///|
test "a field of the tree's as an old view's on Android's: a long press picks the word, its menu up as it is let go, felt; a double tap picks it; a tap puts the caret" {
  let words = "hello brave world"
  field_alike("a long press", words, platform=2, fn(t, _) {
    t.press_at(20.0 + 45.0, 30.0)
    t.run_for(long_press_ms)
    t.release(20.0 + 45.0, 30.0)
  })
  field_alike("a long press slid on", words, platform=2, fn(t, _) {
    t.press_at(20.0 + 45.0, 30.0)
    t.run_for(long_press_ms)
    t.touch(1, 20.0 + 80.0, 30.0)
    t.release(20.0 + 80.0, 30.0)
  })
  field_alike("a double tap", words, platform=2, fn(t, _) {
    t.tap(20.0 + 45.0, 30.0)
    t.tap(20.0 + 45.0, 30.0)
  })
  field_alike("a tap", words, platform=2, fn(t, _) { t.tap(20.0 + 45.0, 30.0) })
}

///|
test "a field of the tree's as an old view's on Android's, half as big: its picked words' end handle dragged where it is drawn; its caret's handle tapped, its menu" {
  let words = "ab cd ef gh ij kl mn op qr st uv wx yz"
  // (in a box with room under the field for its handles: the old view hosted there all of it)
  field_alike("an end handle dragged", words, platform=2, scale=0.5, tall=true, fn(t, f) {
    let (x, y) = (20.0 + 120.0 * 0.5, 20.0 + 5.0 * 0.5)
    t.tap(x, y)
    t.tap(x, y)
    let st = f.st
    // (the end's circle, to its tip's right, as placed; drawn about the holder's top left, half as big)
    let (cx, cy) = (st.sel_bx + handle_r, st.sel_by + handle_r)
    let (hx, hy) = (20.0 + (cx - 20.0) * 0.5, 20.0 + (cy - 20.0) * 0.5)
    t.touch(0, hx, hy)
    t.touch(1, hx + 15.0, hy)
    t.touch(2, hx + 15.0, hy)
  })
  field_alike("the caret's handle tapped", words, platform=2, scale=0.5, tall=true, fn(t, f) {
    t.tap(20.0 + 120.0 * 0.5, 20.0 + 5.0 * 0.5)
    t.draw()
    let st = f.st
    let (hx, hy) = (20.0 + (st.handle_x - 20.0) * 0.5, 20.0 + (st.handle_y + handle_r - 20.0) * 0.5)
    t.tap(hx, hy)
  })
}

///|
test "a field of the tree's as an old view's: ⌘V's words from the clipboard in place of what is picked; a screen reader's words in place of all" {
  field_alike("⌘V", "abc", fn(t, _) {
    t.tap(20.0 + 50.0, 30.0)
    t.key(key_of_char('v'), mods=mod_cmd)
    t.clipboard_gives("XY")
    t.draw()
  })
  field_alike("a screen reader's", "abc", fn(t, _) { t.act(TextField, SetText("新的字")) catch { _ => () } })
}

///|
test "a field of the tree's as an old view's on Android's: a finger down on it, its press called off before it is held long (the window behind, a second finger), then past that moment: nothing picked, no focus, nothing felt; held long, the word picked" {
  let words = "hello brave world"
  field_alike("the window behind before it is held long", words, platform=2, fn(t, _) {
    t.press_at(20.0 + 45.0, 30.0)
    t.run_for(long_press_ms / 2.0)
    t.app_state(true, false)
    t.run_for(long_press_ms)
    t.app_state(true, true)
  })
  // (a second finger: the tree's press called off by it, as any of its presses is (view_host's: a second finger on a
  // press); an old view's long press went on regardless, its word picked: not kept)
  let second = fn(t : Tester, _f : Field) {
    t.touch_raw(0, 0, 20.0 + 45.0, 30.0, t.time())
    t.run_for(long_press_ms / 2.0)
    t.touch_raw(0, 1, 20.0 + 100.0, 30.0, t.time())
    t.run_for(long_press_ms)
    t.touch_raw(2, 1, 20.0 + 100.0, 30.0, t.time())
    t.touch_raw(2, 0, 20.0 + 45.0, 30.0, t.time())
  }
  let old_second = field_after(false, words, platform=2, second)
  assert_eq(
    field_after(true, words, platform=2, second),
    (words, (17, 17), false, [], (false, "", 0, 0)),
    msg="a second finger before it is held long: nothing picked, no focus, nothing felt (the old view's: \{old_second})",
  )
  let (_, picked, _, felt, _) = field_after(true, words, platform=2, fn(t, _) {
    t.press_at(20.0 + 45.0, 30.0)
    t.run_for(long_press_ms)
    t.release(20.0 + 45.0, 30.0)
  })
  assert_eq((picked, felt), ((6, 11), [LongPress]), msg="held long: the word picked, felt")
}

///|
/// A window 300 by 200 whose tree holds, at (20, 20) in a box 200 by 150 that cuts what it holds, `at` down in it a
/// column: a field of `f` (10 big, 4 lines at most), the tree's own (`tree`) or an old view's editor, and under it a
/// button read out as 「after」 10 tall.
fn field_over_after(tree : Bool, f : Field, at : @signals.Signal[Double]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(o) {
      o.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(200.0))).height(Is(Some(150.0))).clips(Is(true)) |> ignore
      o.box(fn(h) {
        h.width(Is(Some(200.0))).offset(By(fn() { (0.0, at.get()) })) |> ignore
        if tree {
          field(h, f, font_size=10.0, max_lines=4) |> ignore
          h.box(fn(a) { a.height(Is(Some(10.0))).says(Is(Some(@view.said(Button, label="after")))) |> ignore }) |> ignore
        } else {
          old(h, fn(c) {
            c.box(w=Px(200.0), fn() {
              c.editor("e", field=f, font_size=10.0, max_lines=4, plain=true) |> ignore
              let k = c.box(w=Px(200.0), h=Px(10.0), fn() {  })
              c.semantics(k, Button, label="after")
            })
            |> ignore
          })
          // (as tall as its field's words lay out and what is under it: as an old view holding a field is measured, the
          // note's)
          .measured(By(fn() { f.laid(font_size=10.0, max_lines=4) }), fn(l, w) {
            let (lw, lh) = l.size(w)
            (lw, lh + 10.0)
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
/// The field tapped, ⌘V and the clipboard giving three lines (a Tester's answer, by the frame): in the one frame they
/// come with (the display's next, no other drawn after it), what it holds, how tall it is, where what is under it is,
/// where the host is told its caret is.
fn pasted_lines(tree : Bool) -> (String, Double, Double, (Double, Double, Double, Double)) raise {
  let f = Field::new()
  let at = @signals.signal(0.0, same=fn(a, b) { a == b })
  let t = field_over_after(tree, f, at)
  t.tap(20.0 + 10.0, 20.0 + 5.0)
  t.key(key_of_char('v'), mods=mod_cmd)
  t.clipboard_gives("one\ntwo\nthree")
  // (the one frame they come with, the display's next, alone: nothing after it to mend what it drew)
  t.frame()
  let (_, _, _, fh) = t.get(TextField).rect
  let (_, ay, _, _) = t.get(Button, label="after").rect
  (f.text(), fh, ay, t.ime_rect())
}

///|
test "a field of the tree's as an old view's: three lines from ⌘V, in the first frame drawn once they come: it as tall as they lay out, what is under it under them, its caret told after them" {
  let old_one = pasted_lines(false)
  assert_eq(old_one.0, "one\ntwo\nthree", msg="the old view's: pasted")
  let tree_one = pasted_lines(true)
  assert_eq(tree_one, old_one, msg="the tree's \{tree_one}, the old view's \{old_one}")
}

///|
test "a field of the tree's as an old view's: ⌘V's words come while it is cut out of sight: taken once all the same; back in sight, not again" {
  for tree in [false, true] {
    let f = Field::new()
    let at = @signals.signal(0.0, same=fn(a, b) { a == b })
    let t = field_over_after(tree, f, at)
    t.tap(20.0 + 10.0, 20.0 + 5.0)
    t.key(key_of_char('v'), mods=mod_cmd)
    at.set(400.0)
    t.draw()
    t.clipboard_gives("XY")
    // (the one frame they come with, alone)
    t.frame()
    let out_of_sight = f.text()
    at.set(0.0)
    t.draw()
    t.draw()
    assert_eq((out_of_sight, f.text()), ("XY", "XY"), msg="\{tree}")
  }
}

///|
/// A window 300 by 200 whose tree holds at (20, 20) a box 120 by 20 holding a field of `f` (10 big, one line) said so
/// (`placeholder` and its `shorter` ways, `secret`, `look`, `ime_action`): the tree's own (`tree`) or an old view's
/// editor there, focused by a tap, `typed` typed and Enter: what is read out of it, the lines drawn (where they stand),
/// the glyphs' colours in order, the input method's action told, its words given up.
fn field_said_so(
  tree : Bool,
  typed : String,
  placeholder? : String = "",
  shorter? : Array[String] = [],
  secret? : Bool = false,
  look? : (String) -> (String, Array[(Int, Int, Int64)]),
  ime_action? : Int = 0,
) -> (String, Array[(String, Double, Double, Double, Double, Double)], Array[Int64], Int, Array[String]) raise {
  let f = Field::new()
  let said = []
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(120.0))).height(Is(Some(20.0))) |> ignore
      if tree {
        field(h, f, font_size=10.0, max_lines=1, placeholder~, shorter~, secret~, look?, ime_action~, submitted=fn(w) {
          said.push(w)
        })
        |> ignore
      } else {
        old(h, fn(c) {
          c.box(w=Px(120.0), h=Px(20.0), fn() {
            let e = c.editor("e", field=f, font_size=10.0, max_lines=1, plain=true, placeholder~, shorter~, secret~, look?, ime_action~)
            match e.submitted {
              Some(w) => said.push(w)
              None => ()
            }
          })
          |> ignore
        })
        .grow(Is(1.0))
        |> ignore
      }
    })
    |> ignore
  })
  t.draw()
  let unfocused = t.text_runs().map(fn(r) { (r.text, r.x0, r.x1, r.base, r.top, r.bottom) })
  t.tap(20.0 + 5.0, 25.0)
  t.draw()
  if typed != "" {
    t.type_text(typed)
    t.draw()
  }
  let value = t.get(TextField).value
  let runs = if typed == "" { unfocused } else { t.text_runs().map(fn(r) { (r.text, r.x0, r.x1, r.base, r.top, r.bottom) }) }
  let inks = t.drawn_glyphs().map(fn(gl) { gl.2 })
  let action = t.ime_action()
  t.enter()
  t.draw()
  (value, runs, inks, action, said)
}

///|
test "a field of the tree's as an old view's, said so: its placeholder said its shorter way where the longest does not fit; a secret's words neither read out nor drawn; a look's colours; the input method's key and Enter by it" {
  let long = "a placeholder far longer than its field can show"
  let alike = fn(what : String, run : (Bool) -> (String, Array[(String, Double, Double, Double, Double, Double)], Array[Int64], Int, Array[String]) raise) raise {
    let old_one = run(false)
    let tree_one = run(true)
    assert_eq(tree_one, old_one, msg="\{what}: the tree's \{tree_one}, the old view's \{old_one}")
  }
  alike("its placeholder's shorter way", fn(tree) { field_said_so(tree, "", placeholder=long, shorter=["shorter", "short"]) })
  alike("a secret", fn(tree) { field_said_so(tree, "hunter2", secret=true) })
  alike("a look", fn(tree) {
    field_said_so(tree, "abc def", look=fn(d) { (d, if d.length() >= 3 { [(0, 3, 0xFF0000FFL)] } else { [] }) })
  })
  alike("the input method's key", fn(tree) { field_said_so(tree, "go", ime_action=3) })
}

///|
/// A window 300 by 200 whose tree holds at (20, 20) a box `w` wide holding a field of `f` (10 big, `max_lines` lines at
/// most, said so: `secret`, `look`, `paste_limit`), the tree's own (`tree`) or an old view's editor there (its node as
/// tall as the field lays out, as the note's), focused by a tap. What long pastes it gave up were told, in order.
fn field_in(
  tree : Bool,
  f : Field,
  w : Double,
  pasted : Array[String],
  max_lines? : Int = 1,
  secret? : Bool = false,
  look? : (String) -> (String, Array[(Int, Int, Int64)]),
  paste_limit? : Int = 0,
  platform? : Int = 0,
  scale? : Double = 1.0,
  cut? : Double = 300.0,
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform~)
  set_view_app(fn(root) {
    // (what holds it cut to `cut` wide from the window's left; it drawn `scale` as big about its top left)
    root.box(fn(c) {
    c.over(Is(true)).width(Is(Some(cut))).height(Is(Some(200.0))).clips(Is(true)) |> ignore
    c.box(fn(h) {
      h.offset(Is((20.0, 20.0))).width(Is(Some(w))).scale(Is(scale), about=At(0.0, 0.0)) |> ignore
      if tree {
        field(h, f, font_size=10.0, max_lines~, secret~, look?, paste_limit~, pasted=fn(p) { pasted.push(p) }) |> ignore
      } else {
        old(h, fn(c) {
          c.box(w=Px(w), fn() {
            let e = c.editor("e", field=f, font_size=10.0, max_lines~, plain=true, secret~, look?, paste_limit~)
            match e.pasted {
              Some(p) => pasted.push(p)
              None => ()
            }
          })
          |> ignore
        })
        .measured(By(fn() { f.laid(font_size=10.0, max_lines~) }), fn(l, w) { l.size(w) })
        |> ignore
      }
    })
    |> ignore
    })
    |> ignore
  })
  t.draw()
  t.tap(20.0 + 2.0, 20.0 + 5.0 * scale)
  t.draw()
  t
}

///|
test "a field of the tree's as an old view's: a paste of its limit's length or more not put in, given up once; drawn again, not again" {
  for tree in [false, true] {
    let f = Field::new(text="ab")
    let pasted = []
    let t = field_in(tree, f, 200.0, pasted, paste_limit=5)
    t.paste("a long paste")
    t.draw()
    t.draw()
    assert_eq((f.text(), pasted), ("ab", ["a long paste"]), msg="\{tree}")
  }
}

///|
test "a field of the tree's: what its look reads changed, its words and node not: its words drawn in the look's colour from the next frame" {
  let ink = @signals.signal(0xFF0000FFL, same=fn(a, b) { a == b })
  let f = Field::new(text="abc")
  let t = field_in(true, f, 200.0, [], look=fn(d) { (d, [(0, d.length(), ink.get())]) })
  let before = t.drawn_glyphs().map(fn(gl) { gl.2 })
  ink.set(0x00FF00FFL)
  t.frame()
  let after = t.drawn_glyphs().map(fn(gl) { gl.2 })
  assert_eq((before, after), ([0xFF0000FFL, 0xFF0000FFL, 0xFF0000FFL], [0x00FF00FFL, 0x00FF00FFL, 0x00FF00FFL]))
}

///|
test "a field of the tree's as an old view's: a secret's words laid out as what it shows (its dots), not as they are: as tall in a narrow field" {
  // (each word as wide as its size, its dots half that: as the Tester's host measures them, laid out on more lines than
  // its dots)
  let words = "汉字汉字汉字汉字汉字汉字汉字汉字汉字汉字"
  let tall = fn(tree : Bool) raise {
    let f = Field::new(text=words)
    let t = field_in(tree, f, 60.0, [], max_lines=4, secret=true)
    t.get(TextField).rect.3
  }
  let old_h = tall(false)
  assert_eq(tall(true), old_h, msg="as tall as the old view's, \{old_h}")
}


///|
test "a field of the tree's as an old view's: a screen reader's words of its paste's limit's length or more: not put in, given up once" {
  for tree in [false, true] {
    let f = Field::new(text="ab")
    let pasted = []
    let t = field_in(tree, f, 200.0, pasted, paste_limit=5)
    t.act(TextField, SetText("a long reading"))
    t.draw()
    t.draw()
    assert_eq((f.text(), pasted), ("ab", ["a long reading"]), msg="\{tree}")
  }
}

///|
test "a field of the tree's: what is composed put in as written, its look's words wider than it: as tall as they lay out in the first frame after, as the same written at once" {
  // (its look: each written word as wide as its size, what is composed as it is, half that, as the Tester's host measures)
  let look = fn(d : String) {
    let b = StringBuilder()
    for _ in 0..<d.length() {
      b.write_char('汉')
    }
    (b.to_string(), [])
  }
  let tall = fn(compose : Bool) raise {
    let f = Field::new()
    let t = field_in(true, f, 40.0, [], max_lines=4, look~)
    if compose {
      t.compose("abcdefgh")
      on_text(2, "", 0, 0)
    } else {
      on_text(0, "abcdefgh", 0, 0)
    }
    // (the one frame after, alone)
    t.frame()
    t.get(TextField).rect.3
  }
  let written = tall(false)
  assert_eq(tall(true), written, msg="as tall as written at once, \{written}")
}


///|
/// A field of eight lines' words showing three (`platform`'s: 0 a desktop's, 2 Android's), the tree's own (`tree`) or
/// an old view's, focused by a tap with its caret at their end (its last lines in sight), then `act` done to it: what
/// shows of each glyph (where, cut by the field), whether it still has the focus, whether the host still has its
/// keyboard up for it, its scroll bar's thumbs as drawn once come in.
fn field_scrolled(
  tree : Bool,
  act : (Tester) -> Unit,
  platform? : Int = 0,
) -> (Array[(Double, Double, Double, Double)], Bool, Bool, Array[(Double, Double, Double, Double, Int64)]) {
  let f = Field::new(text="l0\nl1\nl2\nl3\nl4\nl5\nl6\nl7")
  let t = field_in(tree, f, 200.0, [], max_lines=3, platform~)
  // (a tap on Android's waits to be one: the focus its as it is let go)
  t.draw()
  f.set(f.text(), caret=f.text().length())
  t.draw()
  act(t)
  t.draw()
  // (its bar's thumb come in over its fade)
  t.run_for(scrollbar_fade_ms)
  let thumbs = t.drawn_rects().filter(fn(r) { r.2 == scroll_bar_size || r.3 == scroll_bar_size })
  (t.glyphs_shown(), t.focused().map(fn(s) { s.role }) == Some(TextField), t.ime().0, thumbs)
}

///|
test "a field of the tree's as an old view's, of more lines than it shows: the wheel over it scrolls its words, the focus and the keyboard kept" {
  let act = fn(t : Tester) {
    t.move(20.0 + 50.0, 25.0)
    t.wheel(20.0 + 50.0, 25.0, -40.0)
  }
  let old_one = field_scrolled(false, act)
  assert_eq(old_one.3.length(), 1, msg="the old view's: its bar's thumb drawn \{old_one.3}")
  let tree_one = field_scrolled(true, act)
  assert_eq(tree_one, old_one, msg="the tree's \{tree_one}, the old view's \{old_one}")
}

///|
test "a field of the tree's as an old view's on Android's, of more lines than it shows: a finger drawn down on it scrolls its words, the focus and the keyboard kept" {
  let act = fn(t : Tester) { t.drag(20.0 + 50.0, 25.0, 20.0 + 50.0, 25.0 + 40.0) }
  let old_one = field_scrolled(false, act, platform=2)
  let tree_one = field_scrolled(true, act, platform=2)
  assert_eq(tree_one, old_one, msg="the tree's \{tree_one}, the old view's \{old_one}")
}

///|
/// A finger's steps as it is drawn fast down a field: one after another, a frame's apart.
let flick_step_ms : Double = 16.0

///|
/// A finger held still before it is let go: long enough that what it drew is no longer going anywhere.
let flick_held_ms : Double = 200.0

///|
/// Moments after a fling is let go its words are looked at: early on, further on, and long past any fling's end.
let flung_early_ms : Double = 50.0

///|
let flung_later_ms : Double = 100.0

///|
let flung_long_ms : Double = 3000.0

///|
/// How soon after it is let go a finger comes down on a fling going on.
let fling_caught_ms : Double = 30.0

///|
/// A field of eight lines' words showing three on Android's (the tree's own, `tree`, or an old view's), its caret at
/// their end, a finger drawn down on it fast and let go (`stopped`: held still a while first), then `after` done (what
/// it says: whether anything was still moving then): what shows of each glyph flung_early_ms after it was let go,
/// flung_later_ms more, and flung_long_ms more (all at rest by then, told so); what `after` said.
fn field_flung(
  tree : Bool,
  stopped : Bool,
  after : (Tester) -> Bool,
) -> (Array[Array[(Double, Double, Double, Double)]], Bool) raise {
  let f = Field::new(text="l0\nl1\nl2\nl3\nl4\nl5\nl6\nl7")
  let t = field_in(tree, f, 200.0, [], max_lines=3, platform=2)
  t.draw()
  f.set(f.text(), caret=f.text().length())
  t.draw()
  let (x, y) = (20.0 + 50.0, 25.0)
  t.touch(0, x, y)
  t.run_for(flick_step_ms)
  t.touch(1, x, y + 20.0)
  t.run_for(flick_step_ms)
  t.touch(1, x, y + 30.0)
  if stopped {
    t.run_for(flick_held_ms)
  }
  t.touch(2, x, y + 30.0)
  let said = after(t)
  let out = []
  t.run_for(flung_early_ms)
  out.push(t.glyphs_shown())
  t.run_for(flung_later_ms)
  out.push(t.glyphs_shown())
  t.run_for(flung_long_ms)
  out.push(t.glyphs_shown())
  assert_true(t.at_rest(), msg=t.rest_why())
  (out, said)
}

///|
test "a field of the tree's as an old view's on Android's: its words flung on as a finger is let go, as far at each moment and at rest; held still first, not flung; a finger down on them as they go, stopped there" {
  // (whether its words still go: where they show, a step apart)
  let going = fn(t : Tester) {
    let a = t.glyphs_shown()
    t.run_for(flick_step_ms)
    a != t.glyphs_shown()
  }
  let cases : Array[(String, Bool, (Tester) -> Bool, Bool)] = [
    ("flung", false, going, true),
    ("held still first", true, going, false),
    (
      "stopped by a finger",
      false,
      fn(t) {
        t.run_for(fling_caught_ms)
        // (its words still going as the finger comes down on them)
        let was = going(t)
        t.touch(0, 20.0 + 50.0, 25.0)
        t.touch(2, 20.0 + 50.0, 25.0)
        was
      },
      true,
    ),
  ]
  for c in cases {
    let (what, stopped, after, goes) = c
    let old_one = field_flung(false, stopped, after)
    assert_eq(old_one.1, goes, msg="\{what}: the old view's words going then as it was meant")
    let tree_one = field_flung(true, stopped, after)
    assert_eq(tree_one, old_one, msg="\{what}: the tree's \{tree_one}, the old view's \{old_one}")
  }
}


///|
/// A field of eight lines' words showing three on a desktop's (the tree's own, `tree`, or an old view's), drawn `scale`
/// as big, what holds it cut `cut` wide, its caret at their end; the mouse's pointer brought along its right edge where
/// it is drawn, then its bar's thumb taken where it is drawn and drawn up `dy`: whether the thumb came out as the
/// pointer neared it (its thumbs drawn once come in), what shows of each glyph and the thumbs after the drag.
fn bar_taken(
  tree : Bool,
  dy : Double,
  scale? : Double = 1.0,
  cut? : Double = 300.0,
) -> (Array[(Double, Double, Double, Double, Int64)], Array[(Double, Double, Double, Double)], Array[(Double, Double, Double, Double, Int64)]) {
  let f = Field::new(text="l0\nl1\nl2\nl3\nl4\nl5\nl6\nl7")
  let t = field_in(tree, f, 200.0, [], max_lines=3, scale~, cut~)
  // (a mouse's, its pointer what brings a bar out)
  t.host_says_finger(Some(false))
  t.draw()
  f.set(f.text(), caret=f.text().length())
  t.draw()
  let thumbs = fn() { t.drawn_rects().filter(fn(r) { r.2 == scroll_bar_size * scale || r.3 == scroll_bar_size * scale }) }
  // (along its right edge where it is drawn, its middle)
  let (ex, ey) = (20.0 + (200.0 - 3.0) * scale, 20.0 + 21.0 * scale)
  t.move(ex, ey)
  t.run_for(scrollbar_fade_ms)
  let came = thumbs()
  let thumb = came.get(0).unwrap_or((ex, ey, 0.0, 0.0, 0L))
  let (tx, ty) = (thumb.0 + thumb.2 / 2.0, thumb.1 + thumb.3 / 2.0)
  t.touch(0, tx, ty)
  t.touch(1, tx, ty - dy)
  t.touch(2, tx, ty - dy)
  t.draw()
  (came, t.glyphs_shown(), thumbs())
}

///|
test "a field of the tree's on a desktop's, of more lines than it shows: its bar out as the pointer nears its edge, its thumb taken and drawn up scrolls its words as far as it goes; drawn half as big, and cut, where it is drawn" {
  // (an old view's field hosted in the tree finds no bar near the pointer, none of its thumb to take (its bar kept for
  // the pointer only where the frame's targets are not found alone): measured in b240, not what is asked here)
  let (whole_came, whole_after, _) = bar_taken(true, 10.0)
  assert_eq(whole_came.length(), 1, msg="whole: its thumb out as the pointer neared it")
  let (_, at_rest, _) = bar_taken(true, 0.0)
  assert_true(whole_after != at_rest, msg="whole: its words scrolled by its thumb drawn up")
  // (half as big: the same drawn half as far, where it is drawn, what shows of it the whole's half as big about the
  // field's top left)
  for cut in [300.0, 119.0] {
    let (half_came, half_after, _) = bar_taken(true, 5.0, scale=0.5, cut~)
    assert_eq(half_came.length(), 1, msg="half, cut \{cut}: its thumb out as the pointer neared it where it is drawn")
    let halved = whole_after.map(fn(g) { (20.0 + (g.0 - 20.0) * 0.5, 20.0 + (g.1 - 20.0) * 0.5, 20.0 + (g.2 - 20.0) * 0.5, 20.0 + (g.3 - 20.0) * 0.5) })
    assert_eq(half_after, halved.filter(fn(g) { g.0 < cut }), msg="half, cut \{cut}: scrolled as the whole is, where it is drawn")
  }
}

///|
/// A field of `lines` lines' words showing `shows` on a desktop's, the tree's own, drawn `scale` as big at (20, 20), its
/// caret at their end (its last lines in sight); beside it an old view opening a modal layer over all of the window
/// while `modal` says so (`modal_layer`: modal, else a layer that is not, a popover's, over all the same). The tester, the field, its bar's thumbs as drawn (each's opacity).
fn bar_field(
  scale : Double,
  modal : @signals.Signal[Bool],
  lines? : Int = 8,
  shows? : Int = 3,
  modal_layer? : Bool = true,
) -> (Tester, Field, () -> Array[(Double, Double, Double, Double, Int64)]) {
  let f = Field::new(text=(0).until(lines).map(fn(i) { "l\{i}" }).collect().join("\n"))
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  t.host_says_finger(Some(false))
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(200.0))).scale(Is(scale), about=At(0.0, 0.0)) |> ignore
      field(h, f, font_size=10.0, max_lines=shows) |> ignore
    })
    |> ignore
    // (an old view of its own beside it, 10 by 10 at the window's foot, nothing over the field; its modal layer, open,
    // raised over all of the window to the old frame's root, as an old view's sheet is: over_all_wbtest's)
    old(root, fn(c) {
      if modal.get() {
        c.overlay("cover", modal=modal_layer, outside=false, fn() {
          // (pressed where it is: its own, whatever is under it)
          let k = c.id("cover box")
          c.clicked(k) |> ignore
          c.box(id=k, w=Px(300.0), h=Px(200.0), bg=0x00000020L, fn() {  }) |> ignore
        })
        |> ignore
      }
    })
    .over(Is(true))
    .offset(Is((0.0, 190.0)))
    .width(Is(Some(10.0)))
    .height(Is(Some(10.0)))
    |> ignore
  })
  t.draw()
  f.set(f.text(), caret=f.text().length())
  t.draw()
  (t, f, fn() { t.drawn_rects().filter(fn(r) { r.2 == scroll_bar_size * scale || r.3 == scroll_bar_size * scale }) })
}

///|
test "a field of the tree's bar hidden: a press where its thumb would be is the field's (the focus its), its caret put there, nothing scrolled" {
  let (t, f, _) = bar_field(1.0, @signals.signal(false))
  guard g().bars.get(0) is Some(b) else { fail("no bar kept for the pointer") }
  let shown = t.glyphs_shown()
  t.tap(b.tx + b.tw / 2.0, b.ty + b.th / 2.0)
  t.draw()
  // (the field's: the focus its, which it had not; its caret put there, at its last line's end)
  assert_eq((g().bar_drag, t.glyphs_shown() == shown, t.focused().map(fn(s) { s.role }), f.selection().1), (0, true, Some(TextField), f.text().length()))
}

///|
test "a field of the tree's bar out: its thumb lit as the pointer is on it (as drawn, whole and half as big), and as it is held; not as it is only near" {
  for scale in [1.0, 0.5] {
    let (t, _, thumbs) = bar_field(scale, @signals.signal(false))
    let ink = fn() { thumbs().get(0).map_or(-1L, fn(r) { r.4 & 0xFFL }) }
    let (ex, ey) = (20.0 + (200.0 - 10.0) * scale, 20.0 + 3.0 * scale)
    t.move(ex, ey)
    t.run_for(scrollbar_fade_ms)
    let near = ink()
    guard g().bars.get(0) is Some(b) else { fail("no bar kept for the pointer") }
    let (tx, ty) = (b.tx + b.tw / 2.0, b.ty + b.th / 2.0)
    t.move(tx, ty)
    let on = ink()
    t.move(ex, ey)
    let off = ink()
    t.move(tx, ty)
    t.touch(0, tx, ty)
    t.draw()
    let held = ink()
    t.touch(2, tx, ty)
    assert_true(near > 0L && on > near && off == near && held == on, msg="\{scale}: near \{near}, on \{on}, off \{off}, held \{held}")
  }
}

///|
test "a field of the tree's bar near the still pointer: the old frame's layer opened over it (modal or not; drawn, taking a press there), its bar goes; closed, it comes again" {
  for modal_layer in [true, false] {
  let modal = @signals.signal(false)
  let (t, f, thumbs) = bar_field(1.0, modal, modal_layer~)
  // (first, alone: the layer open drawn over all of the window, and a press on the field there its, not the field's)
  modal.set(true)
  t.draw()
  let drawn = t.drawn_rects().any(fn(r) { r.4 == 0x00000020L && r.2 >= 300.0 })
  let had = f.selection()
  t.tap(20.0 + 10.0, 25.0)
  let pressed = f.selection() != had
  modal.set(false)
  t.draw()
  // (then the pointer on its thumb, still from here on: its bar out, lit; the layer opened over it: not lit as it is
  // still shown, no field of the tree's found there; then gone; closed, out again)
  guard g().bars.get(0) is Some(b) else { fail("modal \{modal_layer}: no bar kept for the pointer") }
  let (tx, ty) = (b.tx + b.tw / 2.0, b.ty + b.th / 2.0)
  t.move(tx, ty)
  t.run_for(scrollbar_fade_ms)
  let ink = fn() { thumbs().get(0).map_or(-1L, fn(r) { r.4 & 0xFFL }) }
  let lit = ink()
  let before = thumbs().length()
  modal.set(true)
  t.draw()
  let under = ink()
  let found = tree_field_at(tx, ty) is Some(_)
  assert_true(
    lit > under && under > 0L && !found,
    msg="modal \{modal_layer}: lit \{lit}, under the layer \{under}, a field found there \{found}, the old frame's over it \{old_layer_over(tx, ty)}",
  )
  t.run_for(scrollbar_hold_ms + scrollbar_fade_ms * 2.0)
  let covered = thumbs().length()
  modal.set(false)
  t.draw()
  t.run_for(scrollbar_fade_ms)
  assert_eq((drawn, pressed, before, covered, thumbs().length()), (true, false, 1, 0, 1), msg="modal \{modal_layer}")
  }
}

///|
test "a field of the tree's thumb lit as it comes under the still pointer and not as it goes: faded in under it, scrolled away from it, the pointer gone from the window" {
  // (forty lines showing eight: its thumb short, far from its foot at its top)
  let (t, _, thumbs) = bar_field(1.0, @signals.signal(false), lines=40, shows=8)
  let ink = fn() { thumbs().get(0).map_or(-1L, fn(r) { r.4 & 0xFFL }) }
  // (where its thumb is, hidden: its words at their end, the thumb at the bar's foot)
  guard g().bars.get(0) is Some(b) else { fail("no bar kept for the pointer") }
  let (tx, ty) = (b.tx + b.tw / 2.0, b.ty + b.th / 2.0)
  t.move(tx, ty)
  t.run_for(scrollbar_fade_ms)
  let faded_in = ink()
  // (its words scrolled to their top by the wheel elsewhere on it: its thumb gone from under the pointer)
  // (the wheel moves not the pointer: what it said last is where it still is)
  t.wheel(20.0 + 50.0, 30.0, -500.0)
  let away = ink()
  // (scrolled back to their end: its thumb under the still pointer again, lit; then the pointer gone from the window)
  t.wheel(20.0 + 50.0, 30.0, 500.0)
  let back = ink()
  t.leave()
  let gone = ink()
  assert_true(
    faded_in > away && away > 0L && back == faded_in && gone < back,
    msg="faded in \{faded_in}, away \{away}, back \{back}, gone \{gone}",
  )
}


///|
test "a field of the tree's thumb faded in under the still pointer, lit; the pointer moved off it along its edge: not lit, in that frame" {
  let (t, _, thumbs) = bar_field(1.0, @signals.signal(false), lines=40, shows=8)
  let ink = fn() { thumbs().get(0).map_or(-1L, fn(r) { r.4 & 0xFFL }) }
  guard g().bars.get(0) is Some(b) else { fail("no bar kept for the pointer") }
  t.move(b.tx + b.tw / 2.0, b.ty + b.th / 2.0)
  t.run_for(scrollbar_fade_ms)
  let lit = ink()
  // (along its edge, at the field's top: near it, off its thumb at the foot)
  t.move(b.tx + b.tw / 2.0, 22.0)
  let off = ink()
  assert_true(lit > off && off > 0L, msg="lit \{lit}, off \{off}")
}


///|
/// A field taking files (the tree's own, `tree`, or an old view's editor there, its files read by Ctx::field_files),
/// "abc" in it, tapped; ⌘V and the clipboard giving `give`'s, then three frames: its words, the files it was told of
/// (each time, as told).
fn files_pasted(tree : Bool, give : (Tester) -> Unit) -> (String, Array[Array[(String, Bytes)]]) {
  let f = Field::new(text="abc")
  let told : Array[Array[(String, Bytes)]] = []
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(200.0))) |> ignore
      if tree {
        field(h, f, font_size=10.0, max_lines=1, files=fn(fs) { told.push(fs) }) |> ignore
      } else {
        old(h, fn(c) {
          c.box(w=Px(200.0), fn() {
            c.editor("e", field=f, font_size=10.0, max_lines=1, plain=true, files=true) |> ignore
            match c.field_files("e") {
              Some(fs) => told.push(fs)
              None => ()
            }
          })
          |> ignore
        })
        .height(Is(Some(20.0)))
        |> ignore
      }
    })
    |> ignore
  })
  t.draw()
  t.tap(20.0 + 50.0, 25.0)
  t.key(key_of_char('v'), mods=mod_cmd)
  give(t)
  t.draw()
  t.draw()
  t.draw()
  (f.text(), told)
}

///|
test "a field of the tree's as an old view's: ⌘V with files on the clipboard, or a picture, told them once, its words as they were; with words alone, the words put in" {
  let png = b"\x89PNG\r\n\x1a\nxx"
  let cases : Array[(String, (Tester) -> Unit)] = [
    ("files", fn(t) { t.clipboard_gives_files([("a.txt", b"hello")], text="a.txt") }),
    ("a picture", fn(t) { t.clipboard_gives_png(png, text="caption") }),
    ("words", fn(t) { t.clipboard_gives("XY") }),
  ]
  for c in cases {
    let (what, give) = c
    let old_one = files_pasted(false, give)
    let tree_one = files_pasted(true, give)
    assert_eq(tree_one, old_one, msg="\{what}: the tree's \{tree_one}, the old view's \{old_one}")
  }
}


///|
test "a field of the tree's of a size and colours followed: as each changes alone, laid out and drawn so in the next frame" {
  let size = @signals.signal(10.0, same=fn(a, b) { a == b })
  let ink = @signals.signal(0xFF0000FFL, same=fn(a, b) { a == b })
  let f = Field::new(text="abc")
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(200.0))) |> ignore
      field(h, f, max_lines=1, size_by=fn() { size.get() }, colors_by=fn() {
        let k = ink.get()
        (k, k, k)
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let tall = fn() raise { t.get(TextField).rect.3 }
  let inks = fn() { t.drawn_glyphs().map(fn(gl) { gl.2 }) }
  let (h1, k1) = (tall(), inks())
  // (its size alone, one frame)
  size.set(20.0)
  t.frame()
  let (h2, k2) = (tall(), inks())
  // (then its colour alone, one frame: nothing laid out anew for it)
  ink.set(0x00FF00FFL)
  t.frame()
  let (h3, k3) = (tall(), inks())
  assert_true(h2 > h1 && h3 == h2, msg="taller as its size grows, as tall as its colour changes: \{h1}, \{h2}, \{h3}")
  assert_eq(
    (k1, k2, k3),
    ([0xFF0000FFL, 0xFF0000FFL, 0xFF0000FFL], [0xFF0000FFL, 0xFF0000FFL, 0xFF0000FFL], [0x00FF00FFL, 0x00FF00FFL, 0x00FF00FFL]),
  )
}

///|
test "a field of the tree's focus asked before its node is made: given it as the node is, words typed in the first frame its; the tree's focus and the window's one" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let f = Field::new()
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.show(fn() { on.get() }, fn(h) {
      h.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(200.0))) |> ignore
      field(h, f, font_size=10.0, max_lines=1) |> ignore
    })
  })
  t.draw()
  f.focus()
  on.set(true)
  t.frame()
  t.type_text("ab")
  assert_eq((f.text(), t.focused().map(fn(s) { s.role }), t.ime().0), ("ab", Some(TextField), true))
}

///|
test "a field of the tree's focus asked under a modal layer over it that holds the focus: not taken, the focus left where it is" {
  let f = Field::new()
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(200.0))) |> ignore
      field(h, f, font_size=10.0, max_lines=1) |> ignore
    })
    |> ignore
    root.box(fn(m) {
      m
      .over(Is(true))
      .modal(Is(true))
      .width(Is(Some(300.0)))
      .height(Is(Some(200.0)))
      .presses(Is(true))
      .focusable(Is(true))
      .says(Is(Some(@view.said(Button, label="上面"))))
      .on_press(fn() {  })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  // (the focus its, as a screen reader gives it)
  t.act(Button, Focus, label="上面") catch { _ => () }
  t.draw()
  let before = t.focused().map(fn(s) { s.label })
  f.focus()
  t.frame()
  assert_eq((before, t.focused().map(fn(s) { s.label })), (Some("上面"), Some("上面")))
}


///|
test "a field given the focus by Ctx::focus_field in a window that is a tree: an old view's editor holding it, that editor; a field of the tree's made after, that field; given back to an old view's editor, no ask of the tree's left" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let old_on = @signals.signal(false, same=fn(a, b) { a == b })
  let held = Field::new()
  let later = Field::new()
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(200.0))).height(Is(Some(20.0))) |> ignore
      old(h, fn(c) { c.box(w=Px(200.0), h=Px(20.0), fn() { c.editor("held", field=held, font_size=10.0, max_lines=1, plain=true) |> ignore }) |> ignore })
      .grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.show(fn() { on.get() }, fn(h) {
      h.over(Is(true)).offset(Is((20.0, 80.0))).width(Is(Some(200.0))) |> ignore
      field(h, later, font_size=10.0, max_lines=1) |> ignore
    })
    root.show(fn() { old_on.get() }, fn(h) {
      h.over(Is(true)).offset(Is((20.0, 140.0))).width(Is(Some(200.0))).height(Is(Some(20.0))) |> ignore
      old(h, fn(c) { c.box(w=Px(200.0), h=Px(20.0), fn() { c.editor("later old", field=later, font_size=10.0, max_lines=1, plain=true) |> ignore }) |> ignore })
      .grow(Is(1.0))
      |> ignore
    })
  })
  t.draw()
  g().focus_field(held)
  t.draw()
  t.type_text("a")
  let old_one = held.text()
  g().focus_field(later)
  on.set(true)
  t.frame()
  t.type_text("b")
  let tree_one = later.text()
  // (the tree's field let go, its Field asked for again and held by an old view's editor: no ask of the tree's left)
  on.set(false)
  t.draw()
  g().focus_field(later)
  let asked = later.st.focus_asked
  old_on.set(true)
  t.draw()
  t.type_text("c")
  assert_eq((old_one, tree_one, asked, later.st.focus_asked, later.text()), ("a", "b", true, false, "bc"))
}


///|
test "Ctx::focus_field: an old view's editor holding a Field taken away, the Field then a field of the tree's: that field given it, words typed its" {
  let old_on = @signals.signal(true, same=fn(a, b) { a == b })
  let tree_on = @signals.signal(false, same=fn(a, b) { a == b })
  let f = Field::new()
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.show(fn() { old_on.get() }, fn(h) {
      h.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(200.0))).height(Is(Some(20.0))) |> ignore
      old(h, fn(c) { c.box(w=Px(200.0), h=Px(20.0), fn() { c.editor("e", field=f, font_size=10.0, max_lines=1, plain=true) |> ignore }) |> ignore })
      .grow(Is(1.0))
      |> ignore
    })
    root.show(fn() { tree_on.get() }, fn(h) {
      h.over(Is(true)).offset(Is((20.0, 80.0))).width(Is(Some(200.0))) |> ignore
      field(h, f, font_size=10.0, max_lines=1) |> ignore
    })
  })
  t.draw()
  old_on.set(false)
  t.draw()
  g().focus_field(f)
  tree_on.set(true)
  t.frame()
  t.type_text("ab")
  assert_eq((f.text(), t.focused().map(fn(s) { s.role })), ("ab", Some(TextField)))
}

///|
test "Ctx::focus_field under a modal layer of the tree's holding the focus: a Field not yet held, then held by a field under it: the layer's button keeps the focus throughout" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let f = Field::new()
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.show(fn() { on.get() }, fn(h) {
      h.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(200.0))) |> ignore
      field(h, f, font_size=10.0, max_lines=1) |> ignore
    })
    root.box(fn(m) {
      m
      .over(Is(true))
      .modal(Is(true))
      .width(Is(Some(300.0)))
      .height(Is(Some(200.0)))
      .presses(Is(true))
      .focusable(Is(true))
      .says(Is(Some(@view.said(Button, label="上面"))))
      .on_press(fn() {  })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.act(Button, Focus, label="上面") catch { _ => () }
  t.draw()
  let before = t.focused().map(fn(s) { s.label })
  g().focus_field(f)
  t.draw()
  let asked = t.focused().map(fn(s) { s.label })
  on.set(true)
  t.frame()
  assert_eq((before, asked, t.focused().map(fn(s) { s.label })), (Some("上面"), Some("上面"), Some("上面")))
}


///|
/// A window whose tree holds, while `on` says so, a Field `f` held by an old view's editor (`old_one`) or a field of
/// the tree's, under a modal layer of the tree's whose button 「上面」 has the focus. The tester.
fn under_modal(old_one : Bool, on : @signals.Signal[Bool], f : Field) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.show(fn() { on.get() }, fn(h) {
      h.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(200.0))).height(Is(Some(20.0))) |> ignore
      if old_one {
        old(h, fn(c) { c.box(w=Px(200.0), h=Px(20.0), fn() { c.editor("e", field=f, font_size=10.0, max_lines=1, plain=true) |> ignore }) |> ignore })
        .grow(Is(1.0))
        |> ignore
      } else {
        field(h, f, font_size=10.0, max_lines=1) |> ignore
      }
    })
    root.box(fn(m) {
      m
      .over(Is(true))
      .modal(Is(true))
      .width(Is(Some(300.0)))
      .height(Is(Some(200.0)))
      .presses(Is(true))
      .focusable(Is(true))
      .says(Is(Some(@view.said(Button, label="上面"))))
      .on_press(fn() {  })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.act(Button, Focus, label="上面") catch { _ => () }
  t.draw()
  t
}

///|
test "Ctx::focus_field under a modal layer of the tree's holding the focus, for a Field an old view's editor or a field of the tree's holds: asked before it is made, or as it is, the layer's button keeps the focus" {
  for old_one in [true, false] {
    for made_first in [false, true] {
      let on = @signals.signal(made_first, same=fn(a, b) { a == b })
      let f = Field::new()
      let t = under_modal(old_one, on, f)
      let before = t.focused().map(fn(s) { s.label })
      g().focus_field(f)
      t.draw()
      on.set(true)
      t.frame()
      t.draw()
      assert_eq(
        (before, t.focused().map(fn(s) { s.label })),
        (Some("上面"), Some("上面")),
        msg="old view's \{old_one}, made first \{made_first}",
      )
    }
  }
}


///|
test "Ctx::focus_field: an old view's editor built at a key with one Field, then with another: the first asked for, not the second given the focus, the first's ask kept" {
  let second = @signals.signal(false, same=fn(a, b) { a == b })
  let a = Field::new(text="a")
  let b = Field::new(text="b")
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(200.0))).height(Is(Some(20.0))) |> ignore
      old(h, fn(c) {
        let f = if second.get() { b } else { a }
        c.box(w=Px(200.0), h=Px(20.0), fn() { c.editor("e", field=f, font_size=10.0, max_lines=1, plain=true) |> ignore }) |> ignore
      })
      .grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  second.set(true)
  t.draw()
  g().focus_field(a)
  t.draw()
  assert_eq((t.ime().0, a.st.focus_asked), (false, true))
}

///|
test "a field of the tree's of more lines than it shows, drawn half as big about its foot, clear of the system's bar over the window's top that its place as laid out is under: its bar from its own top where it is drawn" {
  let f = Field::new(text="l0\nl1\nl2\nl3\nl4\nl5\nl6\nl7")
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  system_bars_now.set({ top: 40.0, bottom: 0.0, left: 0.0, right: 0.0 })
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(200.0))).scale(Is(0.5), about=At(0.0, 1.0)) |> ignore
      // (six lines of 20 shown: a bar long enough to keep clear of what is over it, the 20 under the system's bar where
      // it is laid out and all, bar_track; not so short that it runs the whole edge whatever is over it)
      field(h, f, font_size=10.0, line=20.0, max_lines=6) |> ignore
    })
    |> ignore
  })
  // (a mouse's, its pointer what brings a bar out)
  t.host_says_finger(Some(false))
  t.draw()
  let (fx, fy, fw, fh) = t.get(TextField).rect
  // (laid out from 20 down, under the bar's 40; drawn clear of it; as tall laid out as its bar keeps clear in, what is
  // under the bar where it is laid out kept clear of)
  assert_true(fy >= 40.0, msg="drawn clear of the system's bar: \{(fx, fy, fw, fh)}")
  assert_true(fh / 0.5 - (40.0 - 20.0) >= scroll_bar_least * 2.0, msg="its bar as long as keeps clear: \{(fx, fy, fw, fh)}")
  t.tap(fx + 2.0, fy + 2.0)
  t.draw()
  f.set(f.text(), caret=0)
  t.draw()
  // (along its right edge where it is drawn, its middle)
  t.move(fx + fw - 1.5, fy + fh / 2.0)
  t.run_for(scrollbar_fade_ms)
  let thumbs = t.drawn_rects().filter(fn(r) { r.2 == scroll_bar_size * 0.5 || r.3 == scroll_bar_size * 0.5 })
  system_bars_now.set({ top: 0.0, bottom: 0.0, left: 0.0, right: 0.0 })
  guard thumbs is [thumb, ..] else { fail("no thumb drawn: \{t.drawn_rects()}") }
  // (its words at their top: its thumb at its bar's top, its own top where it is drawn, nothing over it to keep clear of)
  assert_true(thumb.1 >= fy && thumb.1 < fy + scroll_bar_size, msg="its thumb from its top: \{thumb} in \{(fx, fy, fw, fh)}")
}

///|
/// A window 300 by 200 whose tree holds a box at `at` drawn `s` as big about its top left, holding one at `local` in
/// it, 200 wide, holding a field of the tree's of "abcdefghij" (10 big, one line, nothing about its words: plain) or,
/// in its place (`words`), the same words of the tree's laid out as the field lays out its own (as big, its line its
/// theme's for that size, one line): each `put` in turn, the same nodes moved and drawn so, the glyphs drawn each time.
fn field_or_words(
  words : Bool,
  put : Array[((Double, Double), (Double, Double), Double)],
) -> Array[Array[(Double, Double)]] {
  let (at0, local0, s0) = put[0]
  let at = @signals.signal(at0, same=fn(a, b) { a == b })
  let local = @signals.signal(local0, same=fn(a, b) { a == b })
  let s = @signals.signal(s0, same=fn(a, b) { a == b })
  let f = Field::new(text="abcdefghij")
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.over(Is(true)).offset(By(fn() { at.get() })).width(Is(Some(220.0))).scale(By(fn() { s.get() }), about=At(0.0, 0.0))
      |> ignore
      h.box(fn(v) {
        v.over(Is(true)).offset(By(fn() { local.get() })).width(Is(Some(200.0))) |> ignore
        if words {
          v
          .words(Is("abcdefghij"), look={ size: 10.0, weight: 400, line: tree_theme().text_line * 10.0, wrap: false })
          .ink(By(fn() { tree_theme().color(Fg) }))
          |> ignore
        } else {
          field(v, f, font_size=10.0, max_lines=1) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  put.map(fn(p) {
    at.set(p.0)
    local.set(p.1)
    s.set(p.2)
    t.draw()
    t.drawn_glyphs().map(fn(g) { (g.0, g.1) })
  })
}

///|
test "a field of the tree's and words of the tree's in its place: its node off the pixels itself, on them in one off them, drawn as big or half as big: each glyph where the words' is" {
  // (the same nodes each time: the outer one a quarter pixel and more off the pixels; then on them, the inner one so
  // far off them in it; then only drawn otherwise, half as big, 0.7 as big)
  let put = [
    ((20.13, 20.37), (0.0, 0.0), 1.0),
    ((20.0, 20.0), (0.13, 0.37), 1.0),
    ((20.0, 20.0), (0.13, 0.37), 0.5),
    ((20.0, 20.0), (0.13, 0.37), 0.7),
  ]
  let fields = field_or_words(false, put)
  let words = field_or_words(true, put)
  for k, p in put {
    assert_true(words[k].length() == 10, msg="\{p}: the words' glyphs drawn: \{words[k]}")
    // (as scaled_words_wbtest's glyphs_alike: the same to the last bits but what the two ways of working out the
    // same place round off, 1e-14 at 0.7)
    let alike = fields[k].length() == words[k].length() &&
      fields[k].iter().zip(words[k].iter()).all(fn(q) { (q.0.0 - q.1.0).abs() <= 1.0e-9 && (q.0.1 - q.1.1).abs() <= 1.0e-9 })
    assert_true(alike, msg="\{p}: the field's glyphs where the words' are: \{fields[k]}, the words' \{words[k]}")
  }
}
