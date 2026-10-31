// A node of the window's tree as tall as the old view it hosts lays out (View::measured, FieldLaid::size): a field that
// grows a line as one is written, laid out so in the first frame it is shown in, in the first after its words, what is
// composed in them, the window's width or the system's size of words change; what follows it placed under it then;
// measured again for nothing else (a frame still, the node moved or drawn bigger).

///|
/// A column over the window `w` wide: at its top a node holding an old view all of it (old's node measured), as tall as the field in it
/// lays out (an editor of `field`, 16 on 21, 8 lines at most, plain) `w` wide; under it a node 20 tall. Drawn `scale`
/// as big, moved by `moved`, the node holding the field. The tester, the holder's id, the one under it's.
fn measured_field(
  field : Field,
  w? : Double = 300.0,
  scale? : @signals.Signal[Double] = @signals.signal(1.0),
  moved? : @signals.Signal[(Double, Double)] = @signals.signal((0.0, 0.0)),
) -> (Tester, Ref[@view.NodeId?], Ref[@view.NodeId?]) {
  let t = Tester::new(fn(_c) {  }, w~, h=400.0, platform=0)
  let holder : Ref[@view.NodeId?] = Ref(None)
  let under : Ref[@view.NodeId?] = Ref(None)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.over(Is(true)) |> ignore
      col.box(fn(h) {
        holder.val = Some(h.id())
        h.scale(By(fn() { scale.get() }), about=At(0.0, 0.0)).offset(By(fn() { moved.get() })) |> ignore
        old(h, fn(c) {
          c.editor("e", field~, font_size=16.0, line=21.0, max_lines=8, plain=true, enter_sends=false) |> ignore
        })
        .measured(By(fn() { field.laid(font_size=16.0, line=21.0, max_lines=8) }), fn(l, w) { l.size(w) })
        |> ignore
      })
      |> ignore
      col.box(fn(f) {
        under.val = Some(f.id())
        f.height(Is(Some(20.0))).ground(Is(0xCC3333FFL)) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, holder, under)
}

///|
/// Where node `id` is drawn and how big (x, y, w, h).
fn measured_at(id : Ref[@view.NodeId?]) -> (Double, Double, Double, Double) {
  match (view_app.val, id.val) {
    (Some(t), Some(i)) =>
      match t.drawn_of(i) {
        Some(d) => (d.x, d.y, d.w, d.h)
        None => (-1.0, -1.0, -1.0, -1.0)
      }
    _ => (-1.0, -1.0, -1.0, -1.0)
  }
}

///|
/// The holder's height, where the one under it is drawn from, and how tall the field is read out: each where the frame
/// just drawn has it.
fn measured_now(t : Tester, holder : Ref[@view.NodeId?], under : Ref[@view.NodeId?]) -> (Double, Double, Double) raise {
  let (_, _, _, h) = measured_at(holder)
  let (_, uy, _, _) = measured_at(under)
  let (_, _, _, rh) = t.get(TextField).rect
  (h, uy, rh)
}

///|
test "a node as tall as the field in the old view it hosts: shown, a line; a line written, two in the first frame after, what is under it under them; taken out, one; its caret as it was each time" {
  let field = Field::new()
  let (t, holder, under) = measured_field(field)
  assert_eq(measured_now(t, holder, under), (21.0, 21.0, 21.0), msg="shown: a line, what is under it under it")
  t.tap(50.0, 10.0)
  t.text_told("a", t.time())
  t.key_told(key_enter, 0, t.time())
  t.text_told("b", t.time())
  let caret = field.selection()
  t.draw()
  assert_eq(measured_now(t, holder, under), (42.0, 42.0, 42.0), msg="a line written: two, the first frame after")
  assert_eq(field.selection(), caret, msg="a line written: its caret as it was")
  t.key_told(key_code_backspace, 0, t.time())
  t.key_told(key_code_backspace, 0, t.time())
  let caret = field.selection()
  t.draw()
  assert_eq(measured_now(t, holder, under), (21.0, 21.0, 21.0), msg="taken out: one, the first frame after")
  assert_eq(field.selection(), caret, msg="taken out: its caret as it was")
}

///|
test "a node as tall as the field in the old view it hosts: what the input method composes running past its width, a line more in the first frame, its words still those given; put in, as tall; called off, a line again" {
  let field = Field::new()
  let (t, holder, under) = measured_field(field)
  t.tap(50.0, 10.0)
  let long = "composed words that run on past the field's width and onto a line more"
  on_text(1, long, long.length(), 0)
  t.draw()
  let (h, uy, rh) = measured_now(t, holder, under)
  assert_true(h > 21.0 && uy == h && rh == h, msg="composed: taller, the first frame: \{(h, uy, rh)}")
  assert_eq(field.text(), "", msg="composed: its words still those given")
  on_text(1, "", 0, 0)
  t.draw()
  assert_eq(measured_now(t, holder, under), (21.0, 21.0, 21.0), msg="called off: a line again, the first frame")
  on_text(1, long, long.length(), 0)
  on_text(2, "", 0, 0)
  t.draw()
  assert_eq(measured_now(t, holder, under), (h, h, h), msg="put in: as tall, the first frame")
  assert_eq(field.text(), long, msg="put in: its words")
}

///|
test "a node as tall as the field in the old view it hosts, words on a line at its width: the window narrower, two lines in the first frame so wide; wider again, one" {
  let field = Field::new(text="words that fit in three hundred")
  let (t, holder, under) = measured_field(field)
  assert_eq(measured_now(t, holder, under), (21.0, 21.0, 21.0), msg="300 wide: a line")
  t.resize(120.0, 400.0)
  let (h, uy, rh) = measured_now(t, holder, under)
  assert_true(h > 21.0 && uy == h && rh == h, msg="120 wide: more lines, the first frame: \{(h, uy, rh)}")
  t.resize(300.0, 400.0)
  assert_eq(measured_now(t, holder, under), (21.0, 21.0, 21.0), msg="300 again: a line, the first frame")
}

///|
test "a node as tall as the field in the old view it hosts: the system's words made bigger, taller in the first frame they are, what is under it under it" {
  let field = Field::new(text="a")
  let (t, holder, under) = measured_field(field)
  t.set_font_scale(1.5)
  t.draw()
  let (h, uy, rh) = measured_now(t, holder, under)
  assert_true(h > 21.0 && uy == h && rh == h, msg="bigger words: taller, the first frame: \{(h, uy, rh)}")
}

///|
test "a node as tall as the field in the old view it hosts: frames still, it moved and drawn half as big: not measured again, as tall" {
  let field = Field::new(text="a")
  let scale = @signals.signal(1.0, same=fn(a, b) { a == b })
  let moved = @signals.signal((0.0, 0.0), same=fn(a, b) { a == b })
  let (t, holder, _) = measured_field(field, scale~, moved~)
  t.draw()
  let measured = fn() { view_app.val.unwrap().work().measured }
  let before = measured()
  t.draw()
  t.draw()
  assert_eq(measured(), before, msg="still: not measured again")
  moved.set((10.0, 30.0))
  t.draw()
  scale.set(0.5)
  t.draw()
  assert_eq(measured(), before, msg="moved, drawn half as big: not measured again")
  let (x, y, _, h) = measured_at(holder)
  assert_eq((x, y, h), (10.0, 30.0, 10.5), msg="moved, half as big: drawn so, as tall as laid out")
}

///|
test "a field set by the app with no frame and no event round it: what reads its words, them with what is composed in them and its caret sees all three as set, told once; taken while composing, told once, empty" {
  let field = Field::new(text="abc")
  let seen : Array[(String, String, Int)] = []
  let stop = @signals.effect(fn() { seen.push((field.text(), field.composed_said(), field.selection().1)) })
  field.set("x", caret=1)
  assert_eq(seen, [("abc", "abc", 3), ("x", "x", 1)], msg="set: all three as set, told once")
  stop()
  let field = Field::new()
  let t = Tester::new(fn(c) { c.editor("field", field~, font_size=10.0) |> ignore }, w=300.0, h=100.0, platform=0)
  t.tap(50.0, 20.0)
  t.draw()
  t.type_text("ab")
  t.compose("cd")
  let seen : Array[(String, String)] = []
  let stop = @signals.effect(fn() { seen.push((field.text(), field.composed_said())) })
  assert_eq(seen, [("ab", "abcd")], msg="composing: its words alone, and with what is composed")
  field.take() |> ignore
  assert_eq(seen, [("ab", "abcd"), ("", "")], msg="taken: told once, empty")
  stop()
}

///|
test "a field composing, its caret put elsewhere by the app (Field::pick): what reads its words with what is composed in them told them as the field now shows them" {
  let field = Field::new()
  let t = Tester::new(fn(c) { c.editor("field", field~, font_size=10.0) |> ignore }, w=300.0, h=100.0, platform=0)
  t.tap(50.0, 20.0)
  t.draw()
  t.type_text("abcd")
  t.compose("xy")
  assert_eq(field.composed_said(), "abcdxy", msg="composing at its end")
  field.pick(1, 1)
  assert_eq(field.composed_said(), field.st.display(), msg="picked at 1: as it shows them")
  assert_eq(field.composed_said(), "axybcd", msg="picked at 1")
}

///|
/// A column over the window 300 wide: at its top a node holding an old view all of it, as tall as a plain field of
/// `field`'s, 16 big on no line said (the theme's), in it lays out; its tree drawn in a theme whose line is `text_line`
/// of the words' size. The tester, the holder's id.
fn measured_themed(field : Field, text_line : @signals.Signal[Double]) -> (Tester, Ref[@view.NodeId?]) {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=400.0, platform=0)
  let holder : Ref[@view.NodeId?] = Ref(None)
  // (one theme, the tree's and the old view's built in it)
  let theme = fn() { { ..Theme::light(), text_line: text_line.get() } }
  set_view_app(fn(root) {
    set_tree_theme(theme)
    root.box(fn(col) {
      col.over(Is(true)) |> ignore
      col.box(fn(h) {
        holder.val = Some(h.id())
        old(h, fn(c) {
          c.with_theme(theme(), fn() { c.editor("e", field~, font_size=16.0, max_lines=8, plain=true, enter_sends=false) |> ignore })
        })
        .measured(By(fn() { field.laid(font_size=16.0, max_lines=8) }), fn(l, w) { l.size(w) })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, holder)
}

///|
test "a node as tall as a plain field with no line said in the old view it hosts: as tall as its editor, the line the theme its tree is drawn in says; that theme's line otherwise, as tall again in the first frame" {
  let field = Field::new(text="a")
  let text_line = @signals.signal(1.5, same=fn(a, b) { a == b })
  let (t, holder) = measured_themed(field, text_line)
  // (the tree's theme's line, and its editor's: both 1.5 of 16)
  let line = fn() {
    match field.st.tl {
      Some(tl) => tl.line_h
      None => -1.0
    }
  }
  assert_eq((tree_theme().text_line, line()), (1.5, 24.0), msg="its tree's theme and its editor's line")
  let (_, _, _, h) = measured_at(holder)
  let (_, _, _, rh) = t.get(TextField).rect
  assert_eq(h, rh, msg="as tall as its editor: \{(h, rh)}")
  text_line.set(2.0)
  t.draw()
  assert_eq((tree_theme().text_line, line()), (2.0, 32.0), msg="2: its tree's theme and its editor's line")
  let (_, _, _, h2) = measured_at(holder)
  let (_, _, _, rh2) = t.get(TextField).rect
  assert_true(h2 > h && h2 == rh2, msg="the theme's line longer: taller, as its editor: \{(h, h2, rh2)}")
}

///|
/// A row across the window 300 wide: a key 36 across, a node holding an old view (a plain field of `text`, 16 on 21, 8
/// lines at most) in all the room the row leaves (as an old view's Fill: no width of its own before it is shared out,
/// growing, giving way), its node as tall as the field lays out, a key 36 across: where the node is and how big, where
/// the key after it is, how tall the field is read out.
fn measured_between(text : String) -> ((Double, Double, Double, Double), Double, Double) raise {
  let field = Field::new(text~)
  let t = Tester::new(fn(_c) {  }, w=300.0, h=400.0, platform=0)
  let holder : Ref[@view.NodeId?] = Ref(None)
  let after : Ref[@view.NodeId?] = Ref(None)
  set_view_app(fn(root) {
    root.box(fn(row) {
      row.over(Is(true)).row(Is(true)).lines_up(Is(Some(Start))) |> ignore
      row.box(fn(k) { k.width(Is(Some(36.0))).height(Is(Some(36.0))) |> ignore }) |> ignore
      row.box(fn(h) {
        holder.val = Some(h.id())
        h.grow(Is(1.0)).basis(Is(Some(0.0))).shrink(Is(1.0)) |> ignore
        old(h, fn(c) { c.editor("e", field~, font_size=16.0, line=21.0, max_lines=8, plain=true, enter_sends=false) |> ignore })
        .measured(By(fn() { field.laid(font_size=16.0, line=21.0, max_lines=8) }), fn(l, w) { l.size(w) })
        |> ignore
      })
      |> ignore
      row.box(fn(k) {
        after.val = Some(k.id())
        k.width(Is(Some(36.0))).height(Is(Some(36.0))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let (ax, _, _, _) = measured_at(after)
  let (_, _, _, rh) = t.get(TextField).rect
  (measured_at(holder), ax, rh)
}

///|
test "a node as tall as the field in the old view it hosts, in all the room a row leaves between two keys 36 across: as wide as that, the key after it at its end, its words empty, short or wrapping; as tall as its editor lays them out" {
  for text in ["", "a", "words that run on past the room this field has and onto lines more"] {
    let ((x, _, w, h), ax, rh) = measured_between(text)
    assert_eq((x, w, ax), (36.0, 228.0, 264.0), msg="\{text.length()} long: in the room left, the key after it at its end")
    assert_eq(h, rh, msg="\{text.length()} long: as tall as its editor")
    if text.length() > 20 {
      assert_true(h > 21.0, msg="wrapping: taller: \{h}")
    }
  }
}
