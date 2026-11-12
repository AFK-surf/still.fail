// What waits as nodes (waiting_node, view's View::bones) drawn as an old view's wait (waiting, ui's Ctx::bones): the
// same sample (a card of rows, one of its notes over lines, an icon, a button drawn whole, a ground that says something
// by its colour and its edge, a grey one, a picture, a wait in it) drawn the same, every instance, as it breathes; and
// none of it pressed, read out, found by its words or asking for its picture.

///|
/// The sample's words: one of a row's notes long enough to go over lines.
let bones_note : Int = 60

///|
/// The sample as an old view's (what `waiting` is given).
fn bones_sample_old(c : @ui.Ctx, pressed : Ref[Int]) -> Unit {
  group(c, fn() {
    link_row(c, "b1", sample_words(6), note=sample_words(bones_note), on_press=fn() {
      pressed.val += 1
    }) |> ignore
    link_row(c, "b2", sample_words(4), value=sample_words(3), on_press=fn() {
      pressed.val += 1
    }) |> ignore
  })
  c.box(dir=Row, gap=8.0, align=ACenter, fn() {
    icon(c, "bell", size=20.0, color=theme().p.muted) |> ignore
    let whole = c.box(w=Px(64.0), h=Px(28.0), radius=8.0, bg=theme().p.accent, fn() {
      c.text("按钮", style=bones_words) |> ignore
    })
    c.bone_whole(whole)
    c.box(w=Px(60.0), h=Px(28.0), radius=6.0, bg=theme().p.accent, border=1.0, border_color=theme().p.red, fn() {  })
    |> ignore
    c.box(w=Px(60.0), h=Px(28.0), radius=6.0, bg=theme().p.neutral_bg, border=1.0, border_color=theme().p.line, fn() {  })
    |> ignore
    c.image(bones_picture, w=Px(40.0), h=Px(40.0), radius=20.0) |> ignore
  })
  |> ignore
  waiting(c, fn() { c.text(sample_words(10), style=bones_words) |> ignore })
}

///|
/// The same as nodes (what `waiting_node` is given).
fn bones_sample_node(v : @view.View, pressed : Ref[Int]) -> Unit {
  group_node(v, fn(g) {
    link_row_node(g, fn() { sample_words(6) }, fn() { pressed.val += 1 }, note=fn() { sample_words(bones_note) })
    link_row_node(g, fn() { sample_words(4) }, fn() { pressed.val += 1 }, value=fn() { sample_words(3) })
  })
  v.box(fn(r) {
    r.row(Is(true)).gap(Is(8.0)).lines_up(Is(Some(Middle))) |> ignore
    icon_node(r, "bell", 20.0, By(fn() { theme().p.muted })) |> ignore
    r.box(fn(w) {
      w
      .width(Is(Some(64.0)))
      .height(Is(Some(28.0)))
      .radius(Is(8.0))
      .ground(By(fn() { theme().p.accent }))
      .bone_whole(Is(true))
      |> ignore
      w.box(fn(t) { styled_words(t, fn() { "按钮" }, fn() { bones_words }) |> ignore }) |> ignore
    })
    |> ignore
    r.box(fn(b) {
      b
      .width(Is(Some(60.0)))
      .height(Is(Some(28.0)))
      .radius(Is(6.0))
      .ground(By(fn() { theme().p.accent }))
      .edge(By(fn() { (1.0, theme().p.red) }))
      |> ignore
    })
    |> ignore
    r.box(fn(b) {
      b
      .width(Is(Some(60.0)))
      .height(Is(Some(28.0)))
      .radius(Is(6.0))
      .ground(By(fn() { theme().p.neutral_bg }))
      .edge(By(fn() { (1.0, theme().p.line) }))
      |> ignore
    })
    |> ignore
    r.box(fn(p) {
      p.width(Is(Some(40.0))).height(Is(Some(40.0))).radius(Is(20.0)).image(Is(Some((bones_picture, "", 2048)))) |> ignore
    })
    |> ignore
  })
  |> ignore
  waiting_node(v, fn(n) { n.box(fn(t) { styled_words(t, fn() { sample_words(10) }, fn() { bones_words }) |> ignore }) |> ignore })
}

///|
let bones_picture : String = "https://example.com/p.png"

///|
// kept across runs: a value (no field of it changes)
let bones_words : @ui.TextStyle = @ui.text_style(size=Body)

///|
/// The sample waiting, 390 by 600 to touch: drawn by an old view (`node` false) or as nodes; what was pressed counted.
fn bones_tester(node : Bool, pressed : Ref[Int]) -> @ui.Tester {
  let images = [(bones_picture, 80, 80)]
  if node {
    // (the library's theme, the tree's too, as the app's view sets it: begin)
    let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, images~, finish=false, w=390.0, h=600.0, platform=2)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      waiting_node(root, fn(v) { bones_sample_node(v, pressed) })
    })
    t.draw()
    t
  } else {
    let t = @ui.Tester::new(
      fn(c) {
        begin(c) |> ignore
        // (laid out by its width, as a page of the library's is: narrow on a phone)
        c.with_theme(ui_theme(), fn() {
          with_look(look_for(c.width), fn() { waiting(c, fn() { bones_sample_old(c, pressed) }) })
        })
      },
      images~,
      finish=false,
      w=390.0,
      h=600.0,
      platform=2,
    )
    t.draw()
    t
  }
}

///|
/// What the window draws, each instance's numbers rounded to a hundredth (a glyph's place in its atlas left out), in one
/// order; read at once.
fn bones_drawn(t : @ui.Tester) -> Array[String] {
  let all = t.drawn_instances().map(fn(a) {
    a
    .mapi(fn(j, x) {
      if a[5] == 1.0 && j == 12 {
        if x >= 16384.0 { "colour" } else { "mono" }
      } else if a[5] == 1.0 && j == 13 {
        "-"
      } else {
        ((x * 100.0).round() / 100.0).to_string()
      }
    })
    .join(",")
  })
  all.sort()
  all
}

///|
test "what waits as nodes drawn in its bones as an old view's wait: every instance the same, as it breathes" {
  let seen = fn(node : Bool) {
    let t = bones_tester(node, Ref(0))
    let t0 = t.time()
    let out = [bones_drawn(t)]
    // (a quarter of its breath, and half: at its faintest)
    for dt in [breath_ms / 4.0, breath_ms / 2.0] {
      t.frame_at(t0 + dt)
      out.push(bones_drawn(t))
    }
    out
  }
  let old = seen(false)
  let made = seen(true)
  for i, o in old {
    assert_true(o.length() > 0, msg="nothing drawn at step \{i}")
    if made[i] != o {
      let only_old = o.filter(fn(x) { !made[i].contains(x) })
      let only_made = made[i].filter(fn(x) { !o.contains(x) })
      fail("at step \{i}: made \{made[i].length()}, old \{o.length()}\nold's alone:\n  \{only_old.join("\n  ")}\nmade's alone:\n  \{only_made.join("\n  ")}")
    }
  }
}

///|
test "what waits as nodes, in its bones: none of it pressed, read out, found by its words or asking for its picture" {
  let pressed = Ref(0)
  let t = bones_tester(true, pressed)
  // (where its rows are: a finger on each)
  for y in [20.0, 60.0, 100.0, 140.0] {
    t.tap(195.0, y)
  }
  assert_eq(pressed.val, 0)
  // (no words of its sample found, nor read out)
  assert_true(!t.words().iter().any(fn(w) { w.0.contains("字") || w.0.contains("按钮") }), msg="\{Repr(t.words())}")
  assert_true(t.find("字") is None)
  assert_true(!t.semantics_dump().contains("字"), msg=t.semantics_dump())
  // (its picture never asked for)
  assert_eq(t.pending().length(), 0)
  assert_eq(t.image_loads().length(), 0)
}
