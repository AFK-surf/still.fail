///|
fn glass_scene(c : @ui.Ctx) -> Unit {
  let frost = @ui.Glass::frosted(blur=24.0, tint=0xF5F3EFB3L, solid=0xF5F3EFFFL)
  c.box(w=Fill(1.0), h=Fill(1.0), bg=0x1559C4FFL, fn() {
    c.layer(fn() {
      // two bars one after the other: one capture
      c.box(w=Fill(1.0), h=Px(50.0), glass=frost, fn() {  }) |> ignore
      c.box(w=Fill(1.0), h=Px(30.0), glass=frost, fn() {  }) |> ignore
      c.spacer()
      // a floating capsule with words in it, its shadow outside it
      c.box(
        w=Px(200.0),
        h=Px(44.0),
        radius=22.0,
        glass=@ui.Glass::frosted(blur=20.0, tint=0xFFFFFFB8L, solid=0xFFFFFFFFL),
        shadow=2.0,
        fn() { c.text("在这里输入", wrap=false) |> ignore },
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
test "glass one after another shares a capture; glass after something drawn takes its own" {
  let t = @ui.Tester::new(glass_scene)
  let gs = t.drawn_glass()
  assert_eq(gs.length(), 3)
  let (_, y0, _, h0, k0, run0) = gs[0]
  let (_, y1, _, _, _, run1) = gs[1]
  let (_, _, w2, h2, _, run2) = gs[2]
  assert_eq((y0, h0, k0), (0.0, 50.0, 5))
  assert_eq(y1, 50.0)
  assert_eq(run0, run1)
  // the capsule's glass: a capture of its own
  assert_eq((w2, h2), (200.0, 44.0))
  assert_true(run2 != run0)
  // its ground is glass, not a rectangle of its tint
  assert_true(
    t.drawn_rects().iter().all(fn(r) { r.4 != 0xF5F3EFB3L && r.4 != 0xFFFFFFB8L }),
  )
}

///|
test "where less transparency is asked for, glass is its solid ground" {
  let t = @ui.Tester::new(glass_scene)
  t.set_reduce_transparency(true)
  t.frame()
  assert_eq(t.drawn_glass().length(), 0)
  let rects = t.drawn_rects()
  assert_true(rects.iter().any(fn(r) { r.1 == 0.0 && r.3 == 50.0 && r.4 == 0xF5F3EFFFL }))
  assert_true(rects.iter().any(fn(r) { r.2 == 200.0 && r.4 == 0xFFFFFFFFL }))
  t.set_reduce_transparency(false)
  t.frame()
  assert_eq(t.drawn_glass().length(), 3)
}

///|
test "liquid glass of a group is drawn first, as one capture, its words inked by what is under it" {
  let t = @ui.Tester::new(fn(c) {
    c.box(w=Fill(1.0), h=Fill(1.0), bg=0xE5704AFFL, fn() {
      c.box(dir=Row, gap=8.0, glass_group=true, fn() {
        for i in 0..<3 {
          c.box(w=Px(56.0), h=Px(56.0), radius=28.0, glass=@ui.Glass::liquid(), fn() {
            c.text("\{i}", wrap=false) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      c.box(
        w=Px(120.0),
        h=Px(40.0),
        glass=@ui.Glass::liquid(adaptive=false),
        fn() { c.text("plain", wrap=false) |> ignore },
      )
      |> ignore
    })
    |> ignore
  })
  let gs = t.drawn_glass()
  assert_eq(gs.length(), 4)
  let runs = gs.map(fn(g) { g.5 })
  assert_eq(runs[0], runs[1])
  assert_eq(runs[1], runs[2])
  assert_true(runs[3] != runs[0])
  assert_eq(gs.map(fn(g) { g.4 }), [6, 6, 6, 6])
  assert_eq(gs.map(fn(g) { g.0 }), [0.0, 64.0, 128.0, 0.0])
  // "0", "1", "2" inked by the glass; "plain" as it was asked
  assert_eq(t.adaptive_glyphs(), 3)
}
