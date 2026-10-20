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
  assert_eq(p.bg, Some(Faint))
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
  assert_eq(g().nodes[1].bg, th.faint)
  t.touch(0, 10.0, 10.0)
  t.draw()
  assert_eq(g().nodes[1].bg, th.line)
  // without an id: the blocks do nothing
  let t = Tester::new(fn(c) { c.box(style=s, fn() {  }) |> ignore })
  t.move(10.0, 10.0)
  t.touch(0, 10.0, 10.0)
  t.draw()
  assert_eq(g().nodes[1].bg, th.card)
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
