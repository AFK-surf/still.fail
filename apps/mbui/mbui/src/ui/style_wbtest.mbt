// Styles (style.mbt): what each token and property comes to on the node, what is said in the call over the style,
// the state blocks' order, `then`, the theme picked by the window's width, `Inner` corners.

///|
/// The node built by `c.box`/`c.text` under `view`, by its index in the frame (0 the root).
fn style_node(view : (Ctx) -> Unit, w? : Double = 390.0, at? : Int = 1) -> Node {
  let t = Tester::new(view, w~)
  t.draw()
  ignore(t)
  g().nodes[at]
}

///|
test "style: each property's token on the node, in the theme in force" {
  let s = style(
    row=true,
    w=Full,
    h=S11,
    max_w=Fixed(420.0),
    px=S4,
    py=S3_5,
    gap=S2,
    align=ACenter,
    justify=JBetween,
    bg=Card,
    radius=Xl2,
    border=B1,
    border_color=A(Fg, O10),
    shadow=Md,
    clip=true,
    opacity=O50,
  )
  let n = style_node(fn(c) { c.box(style=s, fn() {  }) |> ignore })
  let th = Theme::light()
  assert_true(n.dir == Row)
  assert_true(n.w == Fill(1.0))
  assert_true(n.h == Px(44.0))
  assert_eq(n.max_w, 420.0)
  assert_eq((n.pad_l, n.pad_t, n.pad_r, n.pad_b), (16.0, 14.0, 16.0, 14.0))
  assert_eq(n.gap, 8.0)
  assert_true(n.align == ACenter && n.justify == JBetween)
  assert_eq(n.bg, th.card)
  assert_eq(n.radius, 16.0)
  assert_eq(n.border_w, 1.0)
  assert_eq(n.border_c, alpha(th.fg, 0.1))
  assert_eq((n.shadow, n.shadow_y, n.shadow_c), (6.0, 4.0, th.shadow))
  assert_true(n.clip)
  assert_eq(n.opacity, 0.5)
}

///|
test "style: words' size comes with its line, from the theme's scale; Exact as said" {
  let n = style_node(fn(c) {
    c.text("a", style=text_style(size=Sm, weight=Semibold, color=Muted, w=Full, center=true, wrap=false)) |> ignore
  })
  assert_eq((n.font_size, n.line_h, n.weight), (14.0, 20.0, 600))
  assert_eq(n.color, Theme::light().muted)
  assert_true(n.w == Fill(1.0) && n.center && !n.wrap)
  let n = style_node(fn(c) { c.text("a", style=text_style(size=Exact(15.0, 21.0))) |> ignore })
  assert_eq((n.font_size, n.line_h), (15.0, 21.0))
  // a size said in the call keeps the style's line
  let n = style_node(fn(c) { c.text("a", style=text_style(size=Sm), size=13.0) |> ignore })
  assert_eq((n.font_size, n.line_h), (13.0, 20.0))
}

///|
test "style: leading says the line apart from the size, from the theme's scale; Font the font's own; line= over it" {
  // the size's own line (Sm: 14/20) given up for L4's 16
  let n = style_node(fn(c) { c.text("a", style=text_style(size=Sm, leading=L4)) |> ignore })
  assert_eq((n.font_size, n.line_h), (14.0, 16.0))
  let n = style_node(fn(c) { c.text("a", style=text_style(size=Sm, leading=Font)) |> ignore })
  assert_eq((n.font_size, n.line_h), (14.0, 0.0))
  let n = style_node(fn(c) { c.text("a", style=text_style(size=Sm, leading=Exact(24.75))) |> ignore })
  assert_eq(n.line_h, 24.75)
  // an app's scale in its theme
  let n = style_node(fn(c) {
    c.with_theme({ ..Theme::light(), leading: { ..LeadingScale::tailwind(), l5: 18.0 } }, fn() {
      c.text("a", style=text_style(size=Sm, leading=L5)) |> ignore
    })
  })
  assert_eq(n.line_h, 18.0)
  // what the call says wins over the style's, as every property's
  let n = style_node(fn(c) { c.text("a", style=text_style(size=Sm, leading=L4), line=30.0) |> ignore })
  assert_eq(n.line_h, 30.0)
  // `then`: the later's leading over the earlier's; a later size keeps the earlier's leading (each property its own)
  let a = text_style(size=Sm, leading=L4)
  let n = style_node(fn(c) { c.text("a", style=a.then(text_style(leading=L6))) |> ignore })
  assert_eq(n.line_h, 24.0)
  let n = style_node(fn(c) { c.text("a", style=a.then(text_style(size=Lg))) |> ignore })
  assert_eq((n.font_size, n.line_h), (18.0, 16.0))
  assert_eq(Theme::light().leading(Font), None)
}

///|
test "style: what the call says wins over the style's same property; coarser padding over the style's finer" {
  let s = style(pl=S2, pr=S2, pt=S1, pb=S1, bg=Card, radius=Xl)
  let n = style_node(fn(c) { c.box(style=s, pad=10.0, bg=0x112233FFL, fn() {  }) |> ignore })
  assert_eq((n.pad_l, n.pad_t, n.pad_r, n.pad_b), (10.0, 10.0, 10.0, 10.0))
  assert_eq(n.bg, 0x112233FFL)
  assert_eq(n.radius, 12.0)
  let n = style_node(fn(c) { c.box(style=s, padx=3.0, fn() {  }) |> ignore })
  assert_eq((n.pad_l, n.pad_t, n.pad_r, n.pad_b), (3.0, 4.0, 3.0, 4.0))
  // Ctx::row's -1 is no padding said
  let n = style_node(fn(c) { c.box(style=s, padx=-1.0, fn() {  }) |> ignore })
  assert_eq(n.pad_l, 8.0)
}

///|
test "style: a margin below 0 as CSS's, an Exact one too (a list reaching past its column, a padding taken back)" {
  let n = style_node(fn(c) { c.box(style=style(mx=Exact(-12.0), mt=Exact(-3.0), px=Exact(12.0)), fn() {  }) |> ignore })
  assert_eq((n.mar_l, n.mar_r, n.mar_t, n.mar_b), (-12.0, -12.0, -3.0, 0.0))
  assert_eq((n.pad_l, n.pad_r), (12.0, 12.0))
}

///|
test "style: a box with no style is as before, every default" {
  let n = style_node(fn(c) { c.box(fn() {  }) |> ignore })
  assert_true(n.dir == Column && n.w == Auto && n.h == Auto)
  assert_eq((n.pad_l, n.pad_t, n.pad_r, n.pad_b, n.gap), (0.0, 0.0, 0.0, 0.0, 0.0))
  assert_eq((n.min_w, n.max_w, n.min_h, n.max_h), (0.0, 1.0e9, 0.0, 1.0e9))
  assert_true(n.align == AStretch && n.justify == JStart)
  assert_eq((n.bg, n.border_c, n.shadow_c), (0L, 0L, 0x0000002EL))
  assert_eq((n.radius, n.border_w, n.shadow, n.shadow_y, n.opacity), (0.0, 0.0, 0.0, -1.0, 1.0))
  assert_true(!n.clip)
  let n = style_node(fn(c) { c.text("a") |> ignore })
  assert_eq((n.font_size, n.line_h, n.weight), (15.0, 0.0, 400))
  assert_eq(n.color, Theme::light().fg)
  assert_true(n.wrap && !n.center && n.w == Auto)
}

///|
test "style: `then` lays the second over the first; coarser padding takes the finer with it; blocks merge" {
  let a = style(pl=S2, px=S4, bg=Card, pressed=patch(bg=Faint, radius=Sm))
  let b = style(px=S1, pressed=patch(bg=Line))
  let s = a.then(b)
  assert_eq(s.base.pl, None)
  assert_eq(s.base.px, Some(S1))
  assert_eq(s.base.bg, Some(Card))
  assert_eq(s.pressed.unwrap().bg, Some(Line))
  assert_eq(s.pressed.unwrap().radius, Some(Sm))
  let s = a.then(style(p=S3))
  assert_eq((s.base.p, s.base.px, s.base.pl), (Some(S3), None, None))
}

///|
test "style: the states' blocks laid on in their order, the later winning" {
  let s = style(
    bg=Card,
    narrow=patch(bg=Bg, radius=Sm),
    dark=patch(radius=Md),
    selected=patch(bg=Selected),
    hovered=patch(bg=Hover),
    focused=patch(border=B2),
    pressed=patch(bg=Faint),
    disabled=patch(opacity=O50, bg=Line),
  )
  let p = s.resolve(true, true, true, true, true, true, false)
  // (what answers the hand laid over the ground under it: Patch::lit_by)
  assert_eq(p.bg, Some(Over(Over(Selected, Hover), Faint)))
  assert_eq(p.radius, Some(Md))
  assert_eq(p.border, Some(B2))
  let p = s.resolve(true, false, true, false, false, false, true)
  assert_eq(p.bg, Some(Line))
  assert_eq(p.radius, Some(Sm))
  assert_eq(p.opacity, Some(O50))
  assert_eq(s.resolve(false, false, false, false, false, false, false).bg, Some(Card))
}

///|
test "style: pressed and hovered read the box's id, as Ctx::pressed and hovered do" {
  let s = style(w=S20, h=S20, bg=Card, hovered=patch(bg=Faint), pressed=patch(bg=Line))
  let t = Tester::new(fn(c) { c.box(style=s, id=c.id("b"), fn() {  }) |> ignore })
  t.draw()
  let th = Theme::light()
  assert_eq(g().nodes[1].bg, th.card)
  t.move(10.0, 10.0)
  t.draw()
  assert_eq(g().nodes[1].bg, over(th.card, th.faint))
  // (a finger's press lights it too: pressed over lit)
  t.touch(0, 10.0, 10.0)
  t.draw()
  assert_eq(g().nodes[1].bg, over(over(th.card, th.faint), th.line))
  // without an id: the blocks do nothing
  let t = Tester::new(fn(c) { c.box(style=s, fn() {  }) |> ignore })
  t.move(10.0, 10.0)
  t.touch(0, 10.0, 10.0)
  t.draw()
  assert_eq(g().nodes[1].bg, th.card)
}

///|
test "style: what answers the hand is a tint laid over the ground under it, the box's own or its selected one" {
  let s = style(bg=Card, selected=patch(bg=Selected), hovered=patch(bg=Hover), pressed=patch(bg=Hover))
  assert_eq(s.resolve(false, false, false, true, false, false, false).bg, Some(Over(Card, Hover)))
  assert_eq(s.resolve(false, false, true, true, false, false, false).bg, Some(Over(Selected, Hover)))
  assert_eq(s.resolve(false, false, false, true, false, true, false).bg, Some(Over(Over(Card, Hover), Hover)))
  // with no ground of its own: the tint alone
  let s = style(hovered=patch(bg=Hover))
  assert_eq(s.resolve(false, false, false, true, false, false, false).bg, Some(Hover))
  // a tint over a tint is the two as one tint, what is under them showing through
  let th = Theme::light()
  let two = over(th.hover, th.hover)
  assert_true((two & 0xFFL) > (th.hover & 0xFFL) && (two & 0xFFL) < 0xFFL)
  assert_eq(two & 0xFFFFFF00L, th.hover & 0xFFFFFF00L)
}

///|
test "hover: what holds the one pointed at is pointed at too, as drawn; what lies over it is not in it" {
  let lit = style(bg=Card, hovered=patch(bg=Hover))
  let view = fn(c : Ctx) {
    c.box(w=Px(200.0), h=Px(100.0), fn() {
      // a tab (0 … 100) and its × (60 … 80) in it
      c.box(style=lit, w=Px(100.0), h=Px(40.0), id=c.id("tab"), fn() {
        c.box(style=lit, w=Px(20.0), h=Px(20.0), ml=60.0, mt=10.0, id=c.id("x"), fn() {  }) |> ignore
      })
      |> ignore
      // something else over the end of the tab's room, not in it (80 … 120 across, drawn after it)
      c.box(style=lit, w=Px(40.0), h=Px(40.0), left=80.0, top=0.0, id=c.id("over"), fn() {  }) |> ignore
    })
    |> ignore
  }
  let t = Tester::new(view, w=200.0, h=100.0)
  t.draw()
  let th = Theme::light()
  assert_eq((g().nodes[2].bg, g().nodes[3].bg, g().nodes[4].bg), (th.card, th.card, th.card))
  // the tab alone
  t.move(20.0, 20.0)
  assert_eq((g().nodes[2].bg, g().nodes[3].bg), (over(th.card, th.hover), th.card))
  // its ×: both, the × a step more (its tint drawn over the tab's)
  t.move(70.0, 20.0)
  assert_eq((g().nodes[2].bg, g().nodes[3].bg), (over(th.card, th.hover), over(th.card, th.hover)))
  assert_true(g().hover_in.length() == 1 && g().hovered(g().hover_in[0]))
  // what lies over the tab's room: it alone
  t.move(90.0, 20.0)
  assert_eq((g().nodes[2].bg, g().nodes[4].bg), (th.card, over(th.card, th.hover)))
  assert_eq(g().hover_in.length(), 0)
}

///|
test "hover: a box only pointed at is pointed at, and a press on it is what holds it's (a chip's tip in a row), on it" {
  let pressed : Array[String] = []
  let view = fn(c : Ctx) {
    c.box(w=Px(200.0), h=Px(100.0), fn() {
      // a row (0 … 160) and in it a chip (60 … 100) that says what it is on hover, pressing nothing of its own
      let row = c.id("row")
      let chip = c.id("chip")
      if c.clicked(row) {
        pressed.push("row")
      }
      // (where in the row: on its chip)
      if c.clicked_on(row, chip) {
        pressed.push("on the chip")
      }
      c.cursor(row, Hand)
      c.box(w=Px(160.0), h=Px(40.0), id=row, fn() {
        c.box(w=Px(40.0), h=Px(20.0), ml=60.0, mt=10.0, id=chip, taps=false, points=true, fn() {  }) |> ignore
      })
      |> ignore
      // one only measured by: not pointed at
      c.box(w=Px(20.0), h=Px(20.0), left=170.0, top=0.0, id=c.id("measured"), taps=false, fn() {  }) |> ignore
    })
    |> ignore
  }
  let t = Tester::new(view, w=200.0, h=100.0)
  t.draw()
  t.move(70.0, 20.0)
  t.draw()
  // the chip, and the row that holds it
  assert_true(g().hovered(g().id("chip")) && g().hovered(g().id("row")))
  assert_eq(g().rect_of(g().id("chip")), Some((60.0, 10.0, 40.0, 20.0)))
  assert_eq(g().rect_of(g().id("measured")), None)
  // the row's shape over it, the chip saying none
  assert_eq(desk.shown, Cursor::Hand.code())
  // pressed there, the row is, on its chip
  t.tap(70.0, 20.0)
  t.draw()
  assert_eq(pressed, ["row", "on the chip"])
  // pressed beside it, the row, on none of its parts
  pressed.clear()
  t.tap(20.0, 20.0)
  t.draw()
  assert_eq(pressed, ["row"])
}

///|
test "style: the narrow theme in frames narrower than its bound, picked from the width; dark by the theme" {
  let s = style(bg=Bg, narrow=patch(radius=Sm), dark=patch(radius=Lg))
  let view = fn(c : Ctx) {
    c.set_theme(Theme::light(), narrow=Theme::narrow_light(), narrow_below=700.0)
    c.box(style=s, fn() {  }) |> ignore
  }
  let n = style_node(view, w=390.0)
  assert_eq(n.bg, Theme::narrow_light().bg)
  assert_eq(n.radius, 2.0)
  assert_true(g().narrow())
  let n = style_node(view, w=700.0)
  assert_eq(n.bg, Theme::light().bg)
  assert_eq(n.radius, 0.0)
  let n = style_node(fn(c) {
    c.set_theme(Theme::dark())
    c.box(style=s, fn() {  }) |> ignore
  })
  assert_eq(n.bg, Theme::dark().bg)
  assert_eq(n.radius, 8.0)
}

///|
test "style: set once, the narrow theme is picked again each frame as the window's width changes" {
  let set = Ref::new(false)
  let t = Tester::new(
    fn(c) {
      if !set.val {
        c.set_theme(Theme::light(), narrow=Theme::narrow_light())
        set.val = true
      }
      c.box(style=style(bg=Bg), fn() {  }) |> ignore
    },
    w=390.0,
  )
  t.draw()
  assert_eq(g().nodes[1].bg, Theme::narrow_light().bg)
  t.resize(1000.0, 800.0)
  t.draw()
  assert_eq(g().nodes[1].bg, Theme::light().bg)
}

///|
/// A card rounded 24, padded `pad`, holding a column (no corner of its own) of rows rounded `Inner`.
fn inner_card(pad : Style) -> (Ctx) -> Unit {
  fn(c) {
    c.box(pad=20.0, fn() {
      c.box(style=style(w=Full, radius=Xl3, bg=Card).then(pad), fn() {
        c.box(w=Fill(1.0), gap=4.0, fn() {
          for k in 0..<3 {
            c.box(style=style(w=Full, h=S10, radius=Inner, bg=Faint), fn() {  }) |> ignore
            ignore(k)
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  }
}

///|
test "style: radius=Inner is concentric with the container's corner across how far in it lies, through a column with no corner" {
  let t = Tester::new(inner_card(style(p=S2)))
  t.draw()
  let c = g()
  for i in 4..<7 {
    assert_eq(c.nodes[i].radius, concentric(24.0, 8.0))
  }
  assert_eq(t.corner_faults(), [])
  // the edges it is near at one distance, the far one not: the near ones are what count (the card taller than its
  // rows: none is near its bottom)
  let t = Tester::new(inner_card(style(px=S2, pt=S2, pb=S6, h=S96)))
  t.draw()
  assert_eq(g().nodes[4].radius, concentric(24.0, 8.0))
  assert_eq(g().nodes[6].radius, concentric(24.0, 8.0))
  assert_eq(t.corner_faults(), [])
}

///|
test "style: radius=Inner in a container whose corner is a ground laid beside it (a composer's glass)" {
  let t = Tester::new(fn(c) {
    c.box(pad=20.0, align=AStart, fn() {
      c.box(w=Px(300.0), pad=8.0, fn() {
        c.layer(fn() { c.box(w=Fill(1.0), h=Fill(1.0), radius=20.0, bg=0xEEEEEEFFL, fn() {  }) |> ignore })
        |> ignore
        c.box(style=style(w=Full, h=S10, radius=Inner, bg=Faint), fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let c = g()
  let row = c.count - 1
  assert_eq(c.nodes[row].radius, concentric(20.0, 8.0))
  assert_eq(t.corner_faults(), [])
}

///|
/// A card rounded 24 that cuts, padded 8 at its sides and `pt` at its top, holding a row 40 high rounded `row`.
fn clip_card_row(row : Radius, pt : Double) -> (Ctx) -> Unit {
  fn(c) {
    c.box(pad=20.0, align=AStart, fn() {
      c.box(w=Px(200.0), h=Px(120.0), radius=24.0, bg=0xD0D4DAFFL, clip=true, padx=8.0, pt~, fn() {
        c.box(style=style(w=Full, h=S10, radius=row, bg=Faint), fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  }
}

///|
test "corners: flush against a rounded clip's edge, whose arc shows decides" {
  // a: square, flush along the top: the cut's arc is what shows there (Inner says it cannot be concentric: its own fault)
  let t = Tester::new(clip_card_row(Sharp, 0.0))
  t.draw()
  assert_eq(t.corner_faults(), [])
  // b: its own arc (16) inside the cut's circle: its arc shows, not concentric with the card's
  let t = Tester::new(clip_card_row(Exact(16.0), 0.0))
  t.draw()
  let faults = t.corner_faults()
  assert_true(faults.length() == 2, msg=faults.join("\n"))
  // c: as far from the top as from the sides, Inner: concentric
  let t = Tester::new(clip_card_row(Inner, 8.0))
  t.draw()
  assert_eq(g().nodes[g().count - 1].radius, concentric(24.0, 8.0))
  assert_eq(t.corner_faults(), [])
}

///|
test "style: radius=Inner that cannot be concentric is drawn square and said, not stopped" {
  // nearer its container's top than its sides
  let t = Tester::new(inner_card(style(px=S2, pt=S4)))
  t.draw()
  assert_eq(g().nodes[4].radius, 0.0)
  let faults = t.corner_faults()
  assert_true(faults.length() >= 1)
  assert_true(faults[0].contains("radius=Inner, at different distances"), msg=faults[0])
  // near none of its edges: a small box in the middle of a large card
  let t = Tester::new(fn(c) {
    c.box(pad=20.0, fn() {
      c.box(w=Fill(1.0), h=Px(300.0), radius=24.0, bg=0xEEEEEEFFL, align=ACenter, justify=JCenter, fn() {
        c.box(style=style(w=S20, h=S10, radius=Inner, bg=Faint), fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  assert_eq(g().nodes[g().count - 1].radius, 0.0)
  assert_true(t.corner_faults()[0].contains("near none of the edges"))
  // in no rounded container at all
  let t = Tester::new(fn(c) { c.box(style=style(w=S20, h=S10, radius=Inner, bg=Faint), fn() {  }) |> ignore })
  t.draw()
  assert_true(t.corner_faults()[0].contains("in no rounded container"))
}

///|
/// A capsule 44 high, `pad` in from a panel rounded `corner` at its sides and foot (`corner` 0: no panel, the capsule
/// alone), holding a round button 32 across 6 in at its start: both `InnerOr(Full)`.
fn capsule_in_panel(corner : Double, pad : Double) -> (Ctx) -> Unit {
  let capsule = fn(c : Ctx) {
    c.box(style=style(w=Full, h=Fixed(44.0), p=S1_5, radius=InnerOr(Full), bg=Faint), fn() {
      c.box(style=style(w=S8, h=S8, radius=InnerOr(Full), bg=Card), fn() {  }) |> ignore
    })
    |> ignore
  }
  fn(c) {
    c.box(pad=20.0, align=AStart, fn() {
      if corner > 0.0 {
        c.box(w=Px(300.0), h=Px(200.0), radius=corner, bg=0xEEEEEEFFL, pad~, justify=JEnd, fn() { capsule(c) })
        |> ignore
      } else {
        c.box(w=Px(300.0), fn() { capsule(c) }) |> ignore
      }
    })
    |> ignore
  }
}

///|
test "style: radius=InnerOr: alone its own corner; in a panel's corner the panel's, whatever the panel's is, and what lies in it the same" {
  // alone: a capsule, and its button round
  let t = Tester::new(capsule_in_panel(0.0, 0.0))
  t.draw()
  let c = g()
  let (capsule, button) = (c.count - 2, c.count - 1)
  assert_eq(c.nodes[capsule].corner(), 22.0)
  assert_eq(c.nodes[button].corner(), 16.0)
  assert_eq(t.corner_faults(), [])
  // in the corner of a panel rounded as far in as the capsule's half height (12 + 22, as a circle reads the panel's:
  // round_like): a capsule still
  let t = Tester::new(capsule_in_panel(round_like_out(34.0), 12.0))
  t.draw()
  let c = g()
  assert_eq(c.nodes[capsule].corner(), 22.0)
  assert_eq(c.nodes[button].corner(), 16.0)
  assert_eq(t.corner_faults(), [])
  // a panel less round: concentric in its foot corners alone, the capsule's corners would be unlike (its top's round
  // as alone): never worked out so; a capsule still, its button round in it. Across the panel's foot its ends are in
  // its foot corners (the user, 2026-10-26: a composer's capsule there, its ends not on the page's corners): the panel
  // wants a corner as far in as they stand and their half, said
  let t = Tester::new(capsule_in_panel(24.0, 12.0))
  t.draw()
  let c = g()
  assert_eq(drawn4(c.nodes[capsule]), (22.0, 22.0, 22.0, 22.0))
  assert_eq(drawn4(c.nodes[button]), (16.0, 16.0, 16.0, 16.0))
  let faults = t.corner_faults()
  assert_true(
    faults.length() == 2 && faults.iter().all(fn(f) { f.contains("wants corner 35.5") }),
    msg=faults.join("\n"),
  )
  // nearer the panel's foot than its sides: its own corner kept, and said
  let t = Tester::new(fn(c) {
    c.box(pad=20.0, align=AStart, fn() {
      c.box(w=Px(300.0), h=Px(200.0), radius=24.0, bg=0xEEEEEEFFL, padx=12.0, pb=4.0, justify=JEnd, fn() {
        c.box(style=style(w=Full, h=Fixed(44.0), radius=InnerOr(Full), bg=Faint), fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  assert_eq(g().nodes[g().count - 1].corner(), 22.0)
  assert_true(t.corner_faults().iter().any(fn(f) { f.contains("at different distances") }), msg=t.corner_faults().join("\n"))
}

///|
test "style: Ctx's tokens outside a style: space, color, text_size" {
  let got : Ref[(Double, Bool, Bool, (Double, Double))] = Ref::new((0.0, false, false, (0.0, 0.0)))
  let t = Tester::new(fn(c) {
    got.val = (
      c.space(S11),
      c.color(Danger) == c.theme().danger,
      c.color(Over(Card, A(Fg, O5))) == over(c.theme().card, alpha(c.theme().fg, 0.05)),
      c.text_size(Xl2),
    )
  })
  t.draw()
  assert_eq(got.val, (44.0, true, true, (24.0, 32.0)))
}

///|
test "census: the last frame's values by kind, sorted" {
  let t = Tester::new(fn(c) {
    c.box(pad=8.0, gap=4.0, bg=0x112233FFL, radius=12.0, fn() {
      c.text("a", size=13.0, line=18.0) |> ignore
      c.text("b", size=13.0, line=18.0, weight=600, color=0xFF0000FFL) |> ignore
    })
    |> ignore
  })
  t.draw()
  let k = t.census()
  assert_eq(k.text, ["13/18"])
  assert_eq(k.weight, ["400", "600"])
  assert_eq(k.space, ["4", "8"])
  assert_eq(k.radius, ["12"])
  assert_eq(k.color, ["112233FF", "24272BFF", "FF0000FF"])
}

///|
test "style: a list's rows, built as it is laid out, are built in the theme in force where the list was" {
  let t = Tester::new(fn(c) {
    c.with_theme(Theme::dark(), fn() {
      c.list("rows", 2, 40.0, fn(i) {
        c.box(style=style(w=Full, h=S10, bg=Bg), fn() { c.text("row " + i.to_string(), style=text_style(size=Sm)) |> ignore })
        |> ignore
      })
      |> ignore
    })
  })
  t.draw()
  let c = g()
  let mut grounds = 0
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.kind == kind_box && n.bg == Theme::dark().bg {
      grounds += 1
    }
    if n.kind == kind_text {
      assert_eq(n.color, Theme::dark().fg)
    }
  }
  assert_eq(grounds, 2)
}

///|
test "style: a cover, built once its items are laid out, is built in the theme and direction where it was asked for" {
  let seen : Ref[(Int64, Bool)] = Ref::new((0L, false))
  let t = Tester::new(fn(c) {
    c.with_direction(Rtl, fn() {
      c.with_theme(Theme::dark(), fn() {
        c.box(fn() {
          let holder = c.layer(fn() {  })
          let a = c.box(w=Px(80.0), h=Px(40.0), fn() {  })
          let b = c.box(w=Px(80.0), h=Px(40.0), fn() {  })
          c.cover("pick", holder, [a, b], 0, fn(c, _w, _h) {
            seen.val = (c.color(Bg), c.rtl())
            c.box(style=style(w=Full, h=Full, bg=Bg), fn() {  }) |> ignore
          })
        })
        |> ignore
      })
    })
  })
  t.draw()
  assert_eq(seen.val, (Theme::dark().bg, true))
}

///|
test "style: a list's rows are built in the direction where the list was" {
  let rtl : Ref[Bool] = Ref::new(false)
  let t = Tester::new(fn(c) {
    c.with_direction(Rtl, fn() {
      c.list("rows", 1, 40.0, fn(_) {
        rtl.val = c.rtl()
        c.box(h=Px(40.0), fn() {  }) |> ignore
      })
      |> ignore
    })
  })
  t.draw()
  assert_true(rtl.val)
}

///|
test "style: radius=Inner leaves out an edge it reaches past (cut there, in a row too narrow for it)" {
  let t = Tester::new(fn(c) {
    c.box(pad=20.0, align=AStart, fn() {
      c.box(w=Px(200.0), radius=24.0, bg=0xEEEEEEFFL, pad=8.0, fn() {
        c.box(dir=Row, w=Fill(1.0), gap=8.0, clip=true, fn() {
          for _ in 0..<2 {
            c.box(style=style(w=Fixed(120.0), h=S10, radius=Inner, bg=Faint), fn() {  }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let c = g()
  assert_eq(c.nodes[c.count - 1].radius, concentric(24.0, 8.0))
  assert_eq(t.corner_faults(), [])
}

///|
/// A panel rounded `Around`, 8 in at its top and end, holding a row whose end is a key (a circle of 34, filled or not)
/// and, when `smooth`, a button rounded 12 in its corner instead.
fn around_panel(smooth : Bool, filled : Bool, pt? : Double = 8.0, pb? : Double = 8.0) -> (Ctx) -> Unit {
  fn(c) {
    c.box(pad=20.0, align=AStart, fn() {
      c.box(style=style(w=Fixed(300.0), radius=Around, bg=Card), fn() {
        c.box(dir=Row, w=Fill(1.0), pl=18.0, pr=8.0, pt~, pb~, gap=12.0, fn() {
          c.box(w=Fill(1.0), h=Px(20.0), fn() {  }) |> ignore
          if smooth {
            c.box(w=Px(60.0), h=Px(34.0), radius=12.0, bg=0xD0D4DAFFL, fn() {  }) |> ignore
          } else {
            c.box(style=style(w=Fixed(34.0), h=Fixed(34.0), radius=Full), bg=if filled { 0xD0D4DAFFL } else { 0L }, fn() {  })
            |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  }
}

///|
test "style: radius=Around is a circle's distance from the two edges and its half (Android's Smooth(8.dp + 17.dp))" {
  for filled in [true, false] {
    let t = Tester::new(around_panel(false, filled))
    t.draw()
    let c = g()
    assert_eq(c.nodes[c.arounds[0]].radius, 25.0)
    assert_eq(t.corner_faults(), [])
  }
}

///|
test "style: radius=Around round a smooth box is concentric with it (concentricOut)" {
  let t = Tester::new(around_panel(true, true))
  t.draw()
  assert_eq(g().nodes[g().arounds[0]].radius, concentric_out(12.0, 8.0))
  assert_eq(t.corner_faults(), [])
}

///|
test "style: radius=Around with what is in its corner at different distances from the two edges is square, and said" {
  // 8 from its end, 12 from its top and its foot: in neither corner evenly
  let t = Tester::new(around_panel(false, true, pt=12.0, pb=12.0))
  t.draw()
  assert_eq(g().nodes[g().arounds[0]].radius, 0.0)
  let faults = t.corner_faults()
  assert_eq(faults.length(), 1)
  assert_true(faults[0].contains("radius=Around"))
  assert_true(faults[0].contains("different distances"))
}

///|
test "style: radius=Around round a box whose corner is Inner is each worked out from the other: square, and said" {
  let t = Tester::new(fn(c) {
    c.box(pad=20.0, align=AStart, fn() {
      c.box(style=style(w=Fixed(200.0), p=S2, radius=Around, bg=Card), fn() {
        c.box(style=style(w=Full, h=S10, radius=Inner, bg=Faint), fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  assert_true(t.corner_faults().iter().any(fn(f) { f.contains("each worked out from the other") }))
}

///|
test "style: Wash the same on every width, #322D24 at 6.5% (white at 5% in the dark); Xs2 11 on 16, Xs3 10 on 14" {
  let s = style(bg=Wash)
  let view = fn(c : Ctx) {
    c.set_theme(Theme::light(), narrow=Theme::narrow_light(), narrow_below=700.0)
    c.box(style=s, fn() {  }) |> ignore
  }
  assert_eq(style_node(view, w=390.0).bg, 0x322D2411L)
  assert_eq(style_node(view, w=700.0).bg, 0x322D2411L)
  let dark = fn(c : Ctx) {
    c.set_theme(Theme::dark(), narrow=Theme::narrow_dark(), narrow_below=700.0)
    c.box(style=s, fn() {  }) |> ignore
  }
  assert_eq(style_node(dark, w=390.0).bg, 0xFFFFFF0DL)
  assert_eq(style_node(dark, w=700.0).bg, 0xFFFFFF0DL)
  let th = Theme::light()
  assert_eq(th.text_size(Xs2), (11.0, 16.0))
  assert_eq(th.text_size(Xs3), (10.0, 14.0))
}

///|
/// A card 26 round with `inner` (its corner `own`, `side` square) `inset` in from its top and left, under the light
/// theme with `ladder` (none: any).
fn corner_card(inset : Double, own : Double, side : Double, ladder? : Array[Double] = []) -> (Ctx) -> Unit {
  fn(c) {
    c.with_theme({ ..Theme::light(), corner_ladder: ladder }, fn() {
      c.box(pad=20.0, align=AStart, fn() {
        c.box(w=Px(300.0), h=Px(200.0), radius=26.0, bg=0xEEEEEEFFL, pl=inset, pt=inset, align=AStart, fn() {
          c.box(w=Px(side), h=Px(side), radius=own, bg=0x333333FFL, fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
  }
}

///|
test "corners: what lies in a container's corner keeps one corner for all four; not concentric there, it is said" {
  // 4 round, 10 in: concentric it would be 18 at its top left alone, its others 4, corners unlike, which only a
  // design says: its own kept, and said
  let t = Tester::new(corner_card(10.0, 4.0, 40.0))
  t.draw()
  assert_true(g().nodes[3].radii is None && g().nodes[3].radius == 4.0)
  assert_eq(t.corner_faults().length(), 1)
  // the ladder's next step there: concentric
  let t = Tester::new(corner_card(10.0, concentric(26.0, 10.0), 40.0))
  t.draw()
  assert_eq(t.corner_faults(), [])
  // filling the card, in all four of its corners: concentric with them, worked out
  let t = Tester::new(fn(c) {
    c.box(pad=20.0, align=AStart, fn() {
      c.box(w=Px(300.0), h=Px(200.0), radius=26.0, bg=0xEEEEEEFFL, pad=10.0, fn() {
        c.box(w=Fill(1.0), h=Fill(1.0), radius=4.0, bg=0x333333FFL, fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  assert_true(g().nodes[3].radii is None && g().nodes[3].radius == concentric(26.0, 10.0))
  assert_eq(t.corner_faults(), [])
  // out of its corner (further in than the container is round): its own
  let t = Tester::new(corner_card(30.0, 4.0, 40.0))
  t.draw()
  assert_eq(g().nodes[3].radius, 4.0)
  assert_eq(t.corner_faults(), [])
}

///|
test "corners: a capsule in a container's corner keeps its shape, and is concentric only where it stands so" {
  // 32 round 16, 8.87 in: the container's 26, as a circle reads it (round_like: 24.87), is its distance and its half
  let t = Tester::new(corner_card(round_like(26.0) - 16.0, 16.0, 32.0))
  t.draw()
  assert_eq(g().nodes[3].radius, 16.0)
  assert_eq(t.corner_faults(), [])
  // 4 in: it would want a corner of 20 round it
  let t = Tester::new(corner_card(4.0, 16.0, 32.0))
  t.draw()
  assert_eq(g().nodes[3].radius, 16.0)
  assert_eq(t.corner_faults().length(), 1)
  // a box too small for the corner it would have keeps its own, and is said
  let t = Tester::new(corner_card(4.0, 6.0, 30.0))
  t.draw()
  assert_eq(g().nodes[3].radius, 6.0)
  assert_eq(t.corner_faults().length(), 1)
}

///|
test "corners: with a ladder, a container with something in its corner and what is there are round by its steps" {
  let ladder = [34.0, 26.0, 18.0, 10.0]
  // 10 in: 18, the next step
  let t = Tester::new(corner_card(10.0, 18.0, 40.0, ladder~))
  t.draw()
  assert_eq(t.corner_faults(), [])
  // 14 in: concentric, but 14.8, no step (drawn so on purpose: not held to it as it is drawn)
  let t = Tester::new(corner_card(14.0, concentric(26.0, 14.0), 40.0, ladder~), corners_held=false)
  t.draw()
  assert_eq(t.corner_faults().length(), 1)
  // a control's own part hugging its edge (2 in): concentric is all
  let t = Tester::new(corner_card(2.0, concentric(26.0, 2.0), 60.0, ladder~))
  t.draw()
  assert_eq(t.corner_faults(), [])
}

///|
/// A card 26 round with a box (`wide` wide, 60 tall, its corner 18: a table) in a strip scrolled sideways across it, 20
/// in from its left and foot, as a page's words are.
fn corner_strip(wide : Double) -> (Ctx) -> Unit {
  fn(c) {
    c.box(pad=20.0, align=AStart, fn() {
      c.box(w=Px(300.0), h=Px(140.0), radius=26.0, bg=0xEEEEEEFFL, pad=20.0, justify=JEnd, fn() {
        c.sideways("strip", fn() {
          c.box(w=Px(wide), h=Px(60.0), radius=18.0, bg=0x333333FFL, fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  }
}

///|
/// Node `n`'s corners as drawn (top left, then round it), each at most half its shorter side.
fn drawn4(n : Node) -> (Double, Double, Double, Double) {
  (n.corner_at(0), n.corner_at(1), n.corner_at(2), n.corner_at(3))
}

///|
/// The box corner_strip draws (its ground).
fn strip_box() -> Node {
  let c = g()
  for i in 0..<c.count {
    if c.nodes[i].bg == 0x333333FFL {
      return c.nodes[i]
    }
  }
  abort("no box")
}

///|
test "corners: in a strip scrolled sideways with nothing to scroll, a box lies where it is: in the card's corner" {
  // as narrow as the strip: still, so it lies in the card's corner (its foot's left), its own corner kept all round
  // (followed there alone, its corners would be unlike), and said
  let t = Tester::new(corner_strip(200.0))
  t.draw()
  assert_eq(drawn4(strip_box()), (18.0, 18.0, 18.0, 18.0))
  assert_eq(t.corner_faults().length(), 1)
  // wider: it moves under the strip's edges, so where it is from the corner is not fixed; its own
  let t = Tester::new(corner_strip(400.0))
  t.draw()
  t.draw()
  assert_eq(strip_box().radius, 18.0)
  assert_eq(t.corner_faults(), [])
}

///|
/// still.fail's ranges (its Theme::corner_fit): a corner 6 to 34, standing 4 to 16 in.
let fit_ranges : CornerFit = { least: 6.0, most: 34.0, near: 4.0, far: 16.0 }

///|
/// A panel `edge` in from the window's every edge, its corner 34 standing alone (its ground: `shade`), with what `inside`
/// builds in it; the theme's ladder and ranges.
fn window_panel(edge : Double, inside? : (Ctx) -> Unit = fn(_) {  }) -> (Ctx) -> Unit {
  fn(c) {
    c.with_theme({ ..Theme::light(), corner_ladder: [34.0, 26.0, 18.0, 10.0], corner_fit: Some(fit_ranges) }, fn() {
      c.box(w=Fill(1.0), h=Fill(1.0), pad=edge, fn() {
        c.box(w=Fill(1.0), h=Fill(1.0), radius=34.0, bg=0x333333FFL, fn() { inside(c) }) |> ignore
      })
      |> ignore
    })
  }
}

///|
test "corners: the window is the outermost container: a panel 6 in from its corners round as the window's less that" {
  // a Mac's window, 16 round: 6 in, 11.2, within the ranges
  let t = Tester::new(window_panel(6.0), w=600.0, h=400.0, window_corner=16.0)
  t.draw()
  assert_eq(strip_box().radius, concentric(16.0, 6.0))
  assert_eq(t.corner_faults(), [])
  // Windows 11's 8: 6 in would leave 3.2, too square for the ranges, and nowhere in them squarer than 6: as alone
  let t = Tester::new(window_panel(6.0), w=600.0, h=400.0, window_corner=8.0)
  t.draw()
  assert_eq(strip_box().radius, 34.0)
  assert_eq(t.corner_faults(), [])
  // square (filling the screen): no corner to follow
  let t = Tester::new(window_panel(6.0), w=600.0, h=400.0)
  t.draw()
  assert_eq(strip_box().radius, 34.0)
  assert_eq(t.corner_faults(), [])
}

///|
test "corners: a box in a corner too square for the corner it has keeps it, alone, wherever it stands" {
  // a box said `InnerOr` (a composer, 26) in from a Mac window's panel (11.2): concentric there it would be 8 at the
  // nearest it may stand, squarer than it by far; it keeps its own corner, all four alike, as it would alone, and
  // nothing is said, 10 in or 6.5 (the user, 2026-10-25: a composer's corner followed a window's its send could not)
  let inside = fn(pad : Double) {
    fn(c : Ctx) {
      c.box(w=Fill(1.0), h=Fill(1.0), pad~, justify=JEnd, fn() {
        c.box(style=style(w=Full, h=Fixed(80.0), radius=InnerOr(Exact(26.0)), bg=Faint), fn() {  }) |> ignore
      })
      |> ignore
    }
  }
  for pad in [10.0, 6.5] {
    let t = Tester::new(window_panel(6.0, inside=inside(pad)), w=600.0, h=400.0, window_corner=16.0)
    t.draw()
    let c = g()
    let b = c.nodes[c.count - 1]
    assert_true(b.radii is None && b.radius == 26.0, msg="\{drawn4(b)}")
    assert_eq(t.corner_faults(), [])
  }
}

///|
test "corners: a mark smaller than the gap it would leave in a corner stands by its words, a bigger circle by the corner" {
  // a card 26 round, a round thing `side` across 20 in from its top and start (a status dot before a name, an avatar)
  let dot = fn(side : Double) {
    fn(c : Ctx) {
      c.with_theme({ ..Theme::light(), corner_ladder: [34.0, 26.0, 18.0, 10.0], corner_fit: Some(fit_ranges) }, fn() {
        c.box(pad=20.0, align=AStart, fn() {
          c.box(w=Px(300.0), h=Px(120.0), radius=26.0, bg=0xEEEEEEFFL, pad=20.0, fn() {
            c.box(w=Px(side), h=Px(side), radius=side / 2.0, bg=0x333333FFL, fn() {  }) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
    }
  }
  let t = Tester::new(dot(7.0), corners_held=false)
  t.draw()
  assert_eq(t.corner_faults(), [])
  let t = Tester::new(dot(20.0), corners_held=false)
  t.draw()
  assert_eq(t.corner_faults().length(), 1)
}

///|
test "corners: a panel beside the window's, past its side, follows the window's corner as it will when it comes over" {
  // two panels on a strip as a Mac's 16 window lays them (6 from its top and foot), the second past the window's right
  // edge: its right corners, at the window's right edge when it comes over, as round as the first's, 11.2, its left
  // ones (never at the window's) the ladder's 34; what lies in its corners 6.5 in concentric with each (6 and 28.8:
  // where its right ones have it, off the ladder there)
  let follow = concentric(16.0, 6.0)
  let tape = fn(c : Ctx) {
    c.with_theme({ ..Theme::light(), corner_ladder: [34.0, 26.0, 18.0, 10.0], corner_fit: Some(fit_ranges) }, fn() {
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        c.box(w=Px(588.0), h=Px(388.0), left=6.0, top=6.0, radius=follow, bg=0x333333FFL, fn() {  }) |> ignore
        c.box(
          style=style(radius=Corners(34.0, follow, follow, 34.0)),
          w=Px(300.0),
          h=Px(388.0),
          left=602.0,
          top=6.0,
          bg=0x333333FFL,
          pad=6.5,
          fn() {
          c.box(w=Fill(1.0), h=Fill(1.0), radius=concentric(follow, 6.5), bg=0xEEEEEEFFL, fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
  }
  let t = Tester::new(tape, w=600.0, h=400.0, window_corner=16.0)
  t.draw()
  assert_eq(t.corner_faults(), [])
  // in a square window (no corner to follow) the same panel is one round off the ladder, said
  let t = Tester::new(tape, w=600.0, h=400.0, corners_held=false)
  t.draw()
  assert_eq(t.corner_faults().length(), 1)
}

///|
test "corners: what could follow a corner within the ranges, standing where it cannot, is said" {
  // a circle 30 across 13 in from a 16 window's corner would stand 1 in to follow it, past the ranges: nothing stands
  // by the window's corner not concentric with it (the user, 2026-10-30: 圆形可以改方圆角, 只有长胶囊不行), said
  let in_corner = fn(inset : Double, side : Double, radius : Double) {
    fn(c : Ctx) {
      c.with_theme({ ..Theme::light(), corner_ladder: [34.0, 26.0, 18.0, 10.0], corner_fit: Some(fit_ranges) }, fn() {
        c.box(w=Fill(1.0), h=Fill(1.0), pad=inset, justify=JEnd, fn() {
          c.box(w=Px(side), h=Px(side), radius~, bg=0x333333FFL, fn() {  }) |> ignore
        })
        |> ignore
      })
    }
  }
  let t = Tester::new(in_corner(13.0, 30.0, 15.0), w=600.0, h=400.0, window_corner=16.0, corners_held=false)
  t.draw()
  assert_eq(t.corner_faults().length(), 1)
  assert_true(t.corner_faults()[0].contains("not concentric with it"))
  // a block 6 in, its corner concentric with the window's (a bar's key there: @sf.bar_keys_link): nothing said
  let t = Tester::new(in_corner(6.0, 30.0, concentric(16.0, 6.0)), w=600.0, h=400.0, window_corner=16.0)
  t.draw()
  assert_eq(t.corner_faults(), [])
  // and clear of the corner, as far in as it is round (a floating button's: its shape kept), nothing said
  let t = Tester::new(in_corner(16.0, 30.0, 15.0), w=600.0, h=400.0, window_corner=16.0)
  t.draw()
  assert_eq(t.corner_faults(), [])
  // a bar's last long capsule, 6 under the window's top: beside the arc 16 in from the side (said), past it by the
  // bar's 12 not
  let bar_end = fn(side : Double) {
    fn(c : Ctx) {
      c.with_theme({ ..Theme::light(), corner_ladder: [34.0, 26.0, 18.0, 10.0], corner_fit: Some(fit_ranges) }, fn() {
        c.box(w=Fill(1.0), h=Fill(1.0), pt=6.0, pr=side, align=AEnd, fn() {
          c.box(w=Px(80.0), h=Px(32.0), radius=16.0, bg=0x333333FFL, fn() {  }) |> ignore
        })
        |> ignore
      })
    }
  }
  let t = Tester::new(bar_end(16.0), w=600.0, h=400.0, window_corner=16.0, corners_held=false)
  t.draw()
  assert_eq(t.corner_faults().length(), 1)
  let t = Tester::new(bar_end(28.0), w=600.0, h=400.0, window_corner=16.0)
  t.draw()
  assert_eq(t.corner_faults(), [])
  // a pill 24 high in a 26 card's top corner, in the middle of a short row there (a bar's button), 20 from its side and
  // 22 from its top: in the corner, at different distances, though it could stand 14 from both
  let pill = fn(c : Ctx) {
    c.with_theme({ ..Theme::light(), corner_ladder: [34.0, 26.0, 18.0, 10.0], corner_fit: Some(fit_ranges) }, fn() {
      c.box(pad=20.0, align=AStart, fn() {
        c.box(w=Px(300.0), h=Px(200.0), radius=26.0, bg=0xEEEEEEFFL, pad=20.0, fn() {
          c.box(dir=Row, w=Fill(1.0), h=Px(28.0), align=ACenter, justify=JEnd, fn() {
            c.box(w=Px(80.0), h=Px(24.0), radius=12.0, bg=0x333333FFL, fn() {  }) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
  }
  let t = Tester::new(pill, corners_held=false)
  t.draw()
  assert_eq(t.corner_faults().length(), 1)
}

///|
test "corners: a linked corner too large for its box is checked as it is drawn" {
  // At 50% zoom a Mac's 16-point window corner is 32 content points, but its 32-point bar key is still only 32 wide.
  // The requested linked corner is 27.2, so the key is drawn as a circle of radius 16 and no longer follows the window.
  let link : CornerOf = Follow(Window, 6.0, 16.0)
  let t = Tester::new(fn(c) {
    c.with_theme({ ..Theme::light(), corner_fit: Some(fit_ranges) }, fn() {
      c.box(w=Fill(1.0), h=Fill(1.0), pt=6.0, pr=6.0, align=AEnd, fn() {
        c.box(style=style(w=Fixed(32.0), h=Fixed(32.0), radius=Linked(link)), bg=0x333333FFL, fn() {  }) |> ignore
      })
      |> ignore
    })
  }, w=600.0, h=400.0, window_corner=32.0, corners_held=false)
  t.draw()
  assert_true(!t.corner_faults().is_empty(), msg="the drawn circle is not concentric with the window")
}
