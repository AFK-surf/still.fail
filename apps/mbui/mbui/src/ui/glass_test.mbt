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
test "contained glass frosts its own box alone: a capture of its own even right after glass of the same blur" {
  let contained = @ui.Glass::frosted(blur=14.0, tint=0L, solid=0L, contained=true)
  let t = @ui.Tester::new(fn(c) {
    c.box(w=Fill(1.0), h=Fill(1.0), bg=0x1559C4FFL, fn() {
      c.layer(fn() {
        c.box(w=Fill(1.0), h=Px(50.0), glass=contained, fn() {  }) |> ignore
        c.box(w=Fill(1.0), h=Px(30.0), glass=contained, fn() {  }) |> ignore
        c.box(w=Fill(1.0), h=Px(30.0), glass=@ui.Glass::frosted(blur=14.0, tint=0L, solid=0L), fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  let gs = t.drawn_glass()
  assert_eq(gs.length(), 3)
  assert_eq(t.drawn_glass_contained(), [true, true, false])
  assert_true(gs[0].5 != gs[1].5)
  assert_true(gs[1].5 != gs[2].5)
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
test "frosted glass sharing a capture takes the last frosted one, past liquid glass drawn between" {
  let frost = @ui.Glass::frosted(blur=20.0, tint=0xFFFFFFB8L, solid=0xFDFCFBFFL)
  let t = @ui.Tester::new(fn(c) {
    c.box(w=Fill(1.0), h=Fill(1.0), bg=0x1559C4FFL, fn() {
      c.box(w=Px(300.0), h=Px(60.0), glass=frost, fn() {  }) |> ignore
      c.box(w=Px(56.0), h=Px(56.0), radius=28.0, glass=@ui.Glass::liquid(), fn() {  }) |> ignore
      c.box(w=Px(56.0), h=Px(56.0), radius=28.0, glass=frost.sharing(), fn() {  }) |> ignore
    })
    |> ignore
  })
  let runs = t.drawn_glass().map(fn(g) { g.5 })
  assert_eq(runs.length(), 3)
  assert_true(runs[1] != runs[0])
  assert_eq(runs[2], runs[0])
}

///|
test "liquid glass of a group merges with none drawn right before or after it" {
  let t = @ui.Tester::new(fn(c) {
    c.box(w=Fill(1.0), h=Fill(1.0), bg=0xE5704AFFL, fn() {
      c.box(w=Px(56.0), h=Px(56.0), radius=28.0, glass=@ui.Glass::liquid(), fn() {  }) |> ignore
      c.box(dir=Row, gap=8.0, glass_group=true, fn() {
        for _ in 0..<2 {
          c.box(w=Px(56.0), h=Px(56.0), radius=28.0, glass=@ui.Glass::liquid(), fn() {  }) |> ignore
        }
      })
      |> ignore
      c.box(w=Px(56.0), h=Px(56.0), radius=28.0, glass=@ui.Glass::liquid(), fn() {  }) |> ignore
    })
    |> ignore
  })
  let runs = t.drawn_glass().map(fn(g) { g.5 })
  assert_eq(runs.length(), 4)
  assert_eq(runs[1], runs[2])
  assert_true(runs[0] != runs[1])
  assert_true(runs[3] != runs[2])
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

///|
/// A bar with a notch cut into its top (Bar.kt's), a line drawn over it, then a ball and a disc of glass over it that
/// frost what the bar frosts.
fn notched_scene(c : @ui.Ctx) -> Unit {
  let frost = @ui.Glass::frosted(blur=20.0, tint=0xFFFFFFB8L, solid=0xFDFCFBFFL)
  c.box(w=Fill(1.0), h=Fill(1.0), bg=0x1559C4FFL, fn() {
    c.layer(fn() {
      c.spacer()
      c.box(w=Px(346.0), h=Px(56.0), radius=28.0, glass=frost, notch_y=-4.0, notch_r=34.0, notch_fillet=8.0, fn() {
        c.box(w=Fill(1.0), h=Px(1.0), bg=0xFFFFFFB3L, fn() {  }) |> ignore
        c.box(w=Px(68.0), h=Px(68.0), radius=34.0, glass=frost.sharing(), shadow=4.0, fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
    c.layer(fn() {
      c.box(w=Px(56.0), h=Px(56.0), radius=28.0, glass=frost.sharing(), fn() {  }) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
test "a notch is cut into a box's glass, and into its ground where glass is solid" {
  let t = @ui.Tester::new(notched_scene)
  let ns = t.drawn_notches()
  assert_eq(ns.length(), 1)
  let (kind, _, cy, r, f) = ns[0]
  assert_eq((kind, cy, r, f), (5, -4.0, 34.0, 8.0))
  t.set_reduce_transparency(true)
  t.frame()
  let ns = t.drawn_notches()
  assert_eq(ns.length(), 1)
  let (kind, _, cy, r, f) = ns[0]
  assert_eq((kind, cy, r, f), (0, -4.0, 34.0, 8.0))
  t.set_reduce_transparency(false)
  t.frame()
}

///|
test "glass made to share a capture frosts what the glass before it frosts, over it and after what is drawn between" {
  let t = @ui.Tester::new(notched_scene)
  let gs = t.drawn_glass()
  assert_eq(gs.length(), 3)
  let (_, _, _, _, _, bar) = gs[0]
  let (_, _, _, _, _, ball) = gs[1]
  let (_, _, _, _, _, disc) = gs[2]
  assert_eq(ball, bar)
  assert_eq(disc, bar)
  // the shared glass has no notch of its own
  assert_eq(t.drawn_notches().length(), 1)
}
