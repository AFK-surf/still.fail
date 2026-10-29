// A box with `clip` and a `radius` cuts what it holds to its rounded rect (Compose's clip(RoundedCornerShape)): the
// instances of what it holds carry that rounded rect (scene.mbt 16-19, the corners' radii 24-27 and how smooth they
// are 28-31), the renderers cover their edge as the box's own ground's, and a press in a corner it cut away reaches
// nothing there. What a box that does not cut holds is drawn where it shows, past the box too.

///|
let red : Int64 = 0xFF3B30FFL

///|
/// The instances of the last frame: (their 32 numbers) each.
fn insts() -> Array[Array[Double]] {
  let c = g()
  Array::makei(c.ninst, fn(k) { Array::makei(inst_size, fn(j) { c.inst[k * inst_size + j] }) })
}

///|
/// The instance of a rect of `color` drawn last frame (the last of them).
fn rect_of_color(color : Int64) -> Array[Double] raise {
  let want = ((color >> 24) & 0xFFL).to_double() / 255.0
  let mut found : Array[Double]? = None
  for a in insts() {
    if a[5] == 0.0 && a[8] == want && a[9] == ((color >> 16) & 0xFFL).to_double() / 255.0 {
      found = Some(a)
    }
  }
  match found {
    Some(a) => a
    None => fail("no rect of \{color}")
  }
}

///|
/// A box 80 by 40 at (20, 20), rounded 12 and cutting what it holds, filled by a red box (`id`, tapped: `taps`), with
/// words and a layer over it; `cut` false: the box itself red, rounded, nothing in it.
fn rounded_view(cut : Bool, taps : Ref[Int]) -> (Ctx) -> Unit {
  fn(c) {
    c.box(pad=20.0, align=AStart, fn() {
      if cut {
        c.box(w=Px(80.0), h=Px(40.0), radius=12.0, clip=true, fn() {
          let id = c.id("fill")
          if c.clicked(id) {
            taps.val = taps.val + 1
          }
          c.box(w=Fill(1.0), h=Fill(1.0), bg=red, id~, fn() { c.text("Fill", wrap=false) |> ignore })
          |> ignore
          c.layer(fn() { c.box(w=Px(10.0), h=Px(10.0), bg=0x0000FFFFL, fn() { () }) |> ignore }) |> ignore
        })
        |> ignore
      } else {
        c.box(w=Px(80.0), h=Px(40.0), radius=12.0, bg=red, fn() { () }) |> ignore
      }
    })
    |> ignore
  }
}

///|
test "what a rounded clipping box holds is cut to its rounded rect: its rect and its corners' radii on each instance" {
  let t = Tester::new(rounded_view(true, Ref(0)), w=200.0, h=120.0)
  t.draw()
  let a = rect_of_color(red)
  assert_eq([a[0], a[1], a[2], a[3]], [20.0, 20.0, 80.0, 40.0])
  assert_eq([a[16], a[17], a[18], a[19]], [20.0, 20.0, 100.0, 60.0])
  assert_eq([a[24], a[25], a[26], a[27]], [12.0, 12.0, 12.0, 12.0])
  // its words and what its layer holds too: everything drawn within it
  let within = insts().filter(fn(b) { b[16] == 20.0 && b[17] == 20.0 && b[18] == 100.0 && b[19] == 60.0 })
  assert_true(within.iter().any(fn(b) { b[5] == 1.0 || b[5] == 3.0 }))
  assert_true(within.iter().any(fn(b) { b[5] == 0.0 && b[10] == 1.0 }))
  assert_true(within.iter().all(fn(b) { b[24] == 12.0 && b[25] == 12.0 && b[26] == 12.0 && b[27] == 12.0 }))
  // what is outside it is not cut so
  assert_true(insts().filter(fn(b) { b[16] != 20.0 }).iter().all(fn(b) { b[24] == 0.0 && b[27] == 0.0 }))
  // wholly smooth: the box (80 by 40) has room (20) for 12 a quarter longer
  assert_eq([a[28], a[29], a[30], a[31]], [1.0, 1.0, 1.0, 1.0])
  // the draw list carries them (mbui-dl 4: an instance's 32 numbers)
  let dl = t.drawlist()
  assert_true(dl.has_prefix("mbui-dl 4\n"))
  let line = dl.split("\n").filter(fn(l) { l.has_prefix("i 20 20 80 40 0 0 ") }).collect()
  assert_eq(line.length(), 1)
  assert_true(line[0].has_suffix(" 20 20 100 60 0 0 0 0 12 12 12 12 1 1 1 1"))
}

///|
test "a capsule's clip is round, not smooth; one with a little more room than its radius, smooth as far as that goes" {
  let view = fn(radius : Double) {
    fn(c : Ctx) {
      c.box(pad=20.0, align=AStart, fn() {
        c.box(w=Px(80.0), h=Px(40.0), radius~, clip=true, fn() {
          c.box(w=Fill(1.0), h=Fill(1.0), bg=red, fn() { () }) |> ignore
        })
        |> ignore
      })
      |> ignore
    }
  }
  let t = Tester::new(view(20.0), w=200.0, h=120.0)
  t.draw()
  let a = rect_of_color(red)
  assert_eq([a[24], a[28]], [20.0, 0.0])
  // room 20 for 18: (20 - 18) / (18 / 4)
  let t = Tester::new(view(18.0), w=200.0, h=120.0)
  t.draw()
  let a = rect_of_color(red)
  assert_eq(a[24], 18.0)
  assert_true((a[28] - 2.0 / 4.5).abs() < 1.0e-12)
}

///|
/// How much of the pixel centred at `p` an instance `a` (a rect, kind 0) covers, as the renderers say (scene.mbt's
/// shader): its own rounded rect's edge, times its clip's when that is rounded, times its outer clip's where it has one.
fn covered(a : Array[Double], px : Double, py : Double, scale : Double) -> Double {
  let cover = fn(d : Double) { dclamp(0.5 - d * scale, 0.0, 1.0) }
  let own = cover(sd_box(px - (a[0] + a[2] / 2.0), py - (a[1] + a[3] / 2.0), a[2] / 2.0, a[3] / 2.0, a[4]))
  // a clip: its rect at `k`, its corners' radii at `kr`, how smooth they are at `ks` (sd_clip, the renderers')
  let cut = fn(k : Int, kr : Int, ks : Int) {
    if dmax(dmax(a[kr], a[kr + 1]), dmax(a[kr + 2], a[kr + 3])) <= 0.0 {
      return if px < a[k] || py < a[k + 1] || px > a[k + 2] || py > a[k + 3] { 0.0 } else { 1.0 }
    }
    cover(
      sd_clip(
        px,
        py,
        a[k],
        a[k + 1],
        a[k + 2],
        a[k + 3],
        (a[kr], a[kr + 1], a[kr + 2], a[kr + 3]),
        (a[ks], a[ks + 1], a[ks + 2], a[ks + 3]),
      ),
    )
  }
  let outer = if dmax(dmax(a[44], a[45]), dmax(a[46], a[47])) > 0.0 { cut(40, 44, 48) } else { 1.0 }
  own * cut(16, 24, 28) * outer
}

///|
test "a child filling a rounded clipping box covers its four corners pixel by pixel as the box's own rounded ground" {
  let cut = Tester::new(rounded_view(true, Ref(0)), w=200.0, h=120.0)
  cut.draw()
  let child = rect_of_color(red)
  let plain = Tester::new(rounded_view(false, Ref(0)), w=200.0, h=120.0)
  plain.draw()
  let ground = rect_of_color(red)
  let scale = 2.0
  let mut cut_away = 0
  // each corner's 12 × 12 square, at 2 device pixels a point
  for corner in [(20.0, 20.0), (88.0, 20.0), (88.0, 48.0), (20.0, 48.0)] {
    for i in 0..<24 {
      for j in 0..<24 {
        let px = corner.0 + (i.to_double() + 0.5) / scale
        let py = corner.1 + (j.to_double() + 0.5) / scale
        let a = covered(child, px, py, scale)
        let b = covered(ground, px, py, scale)
        if a != b {
          fail("(\{px}, \{py}): the child covers \{a}, the box's ground \{b}")
        }
        if a == 0.0 {
          cut_away = cut_away + 1
        }
      }
    }
  }
  // the corners are cut: of each 900 pixels (12 smooth: 15 long, at 2×), what the curve leaves out (about 13% of it,
  // the superellipse's 1 - Γ(1 + 1/n)² / Γ(1 + 2/n), less the edge's)
  assert_true(cut_away > 4 * 70, msg="\{cut_away}")
}

///|
test "a press just outside a rounded clip's corner misses what it holds; just inside, it reaches it" {
  let taps = Ref(0)
  let t = Tester::new(rounded_view(true, taps), w=200.0, h=120.0)
  t.draw()
  // the top left corner's curve is about (35, 35), 12 smooth (15 long): it crosses the diagonal at 23.26, so (22, 22)
  // is outside it and (25, 25) in
  t.tap(22.0, 22.0)
  t.draw()
  assert_eq(taps.val, 0)
  t.tap(98.0, 58.0)
  t.draw()
  assert_eq(taps.val, 0)
  t.tap(25.0, 25.0)
  t.draw()
  assert_eq(taps.val, 1)
  t.tap(60.0, 21.0)
  t.draw()
  assert_eq(taps.val, 2)
}

///|
test "a rect clip inside a rounded one: its corners round where they are the rounded clip's, square elsewhere" {
  let t = Tester::new(
    fn(c) {
      c.box(pad=20.0, align=AStart, fn() {
        c.box(w=Px(80.0), h=Px(80.0), radius=12.0, clip=true, fn() {
          // a header, then what scrolls (a rect clip) down to the card's foot
          c.box(h=Px(20.0), fn() { () }) |> ignore
          c.box(h=Fill(1.0), clip=true, fn() {
            c.box(w=Fill(1.0), h=Px(200.0), bg=red, fn() { () }) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    w=200.0,
    h=160.0,
  )
  t.draw()
  let a = rect_of_color(red)
  assert_eq([a[16], a[17], a[18], a[19]], [20.0, 40.0, 100.0, 100.0])
  assert_eq([a[24], a[25], a[26], a[27]], [0.0, 0.0, 12.0, 12.0])
  // as smooth as the card had room for (40 of it, for 12), not as the list's rect (60 high) would be
  assert_eq([a[28], a[29], a[30], a[31]], [0.0, 0.0, 1.0, 1.0])
}

///|
test "a band sharing a rounded clip's corners with no room to draw them as long: drawn by them, pixel by pixel" {
  // a frame 80 square at (20, 20), rounded 12 (wholly smooth: 15 long) and cutting what it holds; in it a band 8 high
  // across its top and one 6 high along its foot, each cutting a fill (a picture's likeness brushed off in steps), and
  // one 40 high between them, room enough for a corner of its own
  let blue = 0x0000FFFFL
  let green = 0x00FF00FFL
  let band = fn(c : Ctx, h : Double, color : Int64) {
    c.box(w=Fill(1.0), h=Px(h), clip=true, fn() { c.box(w=Fill(1.0), h=Fill(1.0), bg=color, fn() { () }) |> ignore })
    |> ignore
  }
  let t = Tester::new(
    fn(c) {
      c.box(pad=20.0, align=AStart, fn() {
        c.box(w=Px(80.0), h=Px(80.0), radius=12.0, clip=true, fn() {
          band(c, 8.0, red)
          c.box(w=Fill(1.0), h=Fill(1.0), fn() { () }) |> ignore
          band(c, 6.0, blue)
        })
        |> ignore
        c.box(w=Px(80.0), h=Px(80.0), radius=12.0, clip=true, fn() { band(c, 40.0, green) }) |> ignore
      })
      |> ignore
    },
    w=200.0,
    h=260.0,
  )
  t.draw()
  let top = rect_of_color(red)
  let foot = rect_of_color(blue)
  // the frame's corners their own, drawn where the frame has them however short the band (sd_clip): no outer
  assert_eq([top[24], top[25], top[26], top[27]], [12.0, 12.0, 0.0, 0.0])
  assert_eq([foot[24], foot[25], foot[26], foot[27]], [0.0, 0.0, 12.0, 12.0])
  for a in [top, foot] {
    assert_eq([a[44], a[45], a[46], a[47]], [0.0, 0.0, 0.0, 0.0])
  }
  // one with room for them alike
  let tall = rect_of_color(green)
  assert_eq([tall[24], tall[25]], [12.0, 12.0])
  assert_eq([tall[44], tall[45], tall[46], tall[47]], [0.0, 0.0, 0.0, 0.0])
  // and each covers its corners as the frame's ground would: none of it past the frame's curve
  let plain = Tester::new(
    fn(c) {
      c.box(pad=20.0, align=AStart, fn() { c.box(w=Px(80.0), h=Px(80.0), radius=12.0, bg=red, fn() { () }) |> ignore })
      |> ignore
    },
    w=200.0,
    h=120.0,
  )
  plain.draw()
  let ground = rect_of_color(red)
  let scale = 2.0
  for part in [(top, 20.0, 8.0), (foot, 94.0, 6.0)] {
    let (a, y0, h) = part
    for x0 in [20.0, 85.0] {
      for i in 0..<30 {
        for j in 0..<(h * scale).to_int() {
          let px = x0 + (i.to_double() + 0.5) / scale
          let py = y0 + (j.to_double() + 0.5) / scale
          let have = covered(a, px, py, scale)
          let want = covered(ground, px, py, scale)
          if have != want {
            fail("(\{px}, \{py}): the band covers \{have}, the frame's ground \{want}")
          }
        }
      }
    }
  }
}

///|
test "a band across a frame's curve, in a clip that cuts a pane's: the frame its outer, not the pane far off, pixel by pixel" {
  // a pane 300 square at (20, 20), rounded 30; in it a list's clip from 10 in, through the pane's curves (its outer the
  // pane); in that a frame 100 by 60, rounded 12, far from the pane's corners; in the frame a band 3 high across its
  // top (its corners the frame's) and one 5 high across its left curve below that (at no corner of it)
  let blue = 0x0000FFFFL
  let band = fn(c : Ctx, h : Double, color : Int64) {
    c.box(w=Fill(1.0), h=Px(h), clip=true, fn() { c.box(w=Fill(1.0), h=Fill(1.0), bg=color, fn() { () }) |> ignore })
    |> ignore
  }
  let framed = fn(inner : (Ctx) -> Unit) {
    fn(c : Ctx) {
      c.box(pad=20.0, align=AStart, fn() {
        c.box(w=Px(300.0), h=Px(300.0), radius=30.0, clip=true, fn() {
          c.box(w=Px(290.0), h=Px(300.0), left=10.0, top=0.0, clip=true, fn() {
            c.box(w=Px(100.0), h=Px(60.0), left=10.0, top=200.0, radius=12.0, clip=true, fn() { inner(c) }) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
  }
  let t = Tester::new(
    framed(fn(c) {
      band(c, 3.0, red)
      c.box(w=Fill(1.0), h=Px(4.0), fn() { () }) |> ignore
      band(c, 5.0, blue)
    }),
    w=360.0,
    h=360.0,
  )
  t.draw()
  let top = rect_of_color(red)
  let across = rect_of_color(blue)
  // the one across the curve keeps the frame whole, its outer
  assert_eq([across[40], across[41], across[42], across[43]], [40.0, 220.0, 140.0, 280.0])
  assert_eq([across[44], across[45], across[46], across[47]], [12.0, 12.0, 12.0, 12.0])
  // each covers what the frame's own ground covers, no more
  let plain = Tester::new(
    framed(fn(c) { c.box(w=Fill(1.0), h=Fill(1.0), bg=red, fn() { () }) |> ignore }),
    w=360.0,
    h=360.0,
  )
  plain.draw()
  let ground = rect_of_color(red)
  let scale = 3.0
  for part in [(top, 220.0, 3.0), (across, 227.0, 5.0)] {
    let (a, y0, h) = part
    for x0 in [40.0, 124.0] {
      for i in 0..<(16.0 * scale).to_int() {
        for j in 0..<(h * scale).to_int() {
          let px = x0 + (i.to_double() + 0.5) / scale
          let py = y0 + (j.to_double() + 0.5) / scale
          let have = covered(a, px, py, scale)
          let want = covered(ground, px, py, scale)
          if (have - want).abs() > 0.02 {
            fail("(\{px}, \{py}): the band covers \{have}, the frame's ground \{want}")
          }
        }
      }
    }
  }
}

///|
test "a rounded clip inside another: the inner's corners, and the outer's where a corner is both's (the rounder)" {
  let t = Tester::new(
    fn(c) {
      c.box(pad=20.0, align=AStart, fn() {
        c.box(w=Px(80.0), h=Px(80.0), radius=16.0, clip=true, fn() {
          c.box(w=Px(40.0), h=Px(80.0), radius=6.0, clip=true, fn() {
            c.box(w=Fill(1.0), h=Fill(1.0), bg=red, fn() { () }) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    w=200.0,
    h=160.0,
  )
  t.draw()
  let a = rect_of_color(red)
  assert_eq([a[16], a[17], a[18], a[19]], [20.0, 20.0, 60.0, 100.0])
  // the left corners both's (16 the rounder), the right ones the inner's alone
  assert_eq([a[24], a[25], a[26], a[27]], [16.0, 6.0, 6.0, 16.0])
}

///|
test "what a box that does not cut holds past its own rect is drawn where it shows, the box laid out outside the clip" {
  // ten tiles 100 wide in a row 200 wide in a box that cuts, moved 650 to the left (as ＋'s recent photos are
  // dragged): the row itself lies wholly left of the cut, its 7th, 8th and 9th tiles (each red as its number) in it
  let t = Tester::new(
    fn(c) {
      c.box(dir=Row, w=Px(200.0), h=Px(100.0), clip=true, fn() {
        c.box(dir=Row, w=Px(200.0), tx=-650.0, fn() {
          for k in 0..<10 {
            c.box(w=Px(100.0), h=Px(100.0), bg=(k.to_int64() << 24) | 0xFFL, fn() { () }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=200.0,
  )
  t.draw()
  let rows = t.boxes().filter(fn(b) { b.kind == "row" })
  let row = rows[rows.length() - 1]
  assert_true(row.x + row.w < 0.0)
  let shown = insts()
    .filter(fn(a) { a[5] == 0.0 && a[2] == 100.0 && a[3] == 100.0 })
    .map(fn(a) { ((a[8] * 255.0).round().to_int(), a[0]) })
  assert_eq(shown, [(6, -50.0), (7, 50.0), (8, 150.0)])
}

///|
/// A pane 200 square at (20, 20), rounded 30 and cutting what it holds; in it two frames rounded 8 that cut theirs,
/// filled red (tapped: `taps`) and blue: the red one's top left corner (30, 22) in the pane's corner, the blue one in
/// its middle.
fn pane_frames(taps : Ref[Int]) -> (Ctx) -> Unit {
  fn(c) {
    c.box(pad=20.0, align=AStart, fn() {
      c.box(w=Px(200.0), h=Px(200.0), radius=30.0, clip=true, fn() {
        c.box(w=Px(60.0), h=Px(40.0), radius=8.0, clip=true, left=10.0, top=2.0, fn() {
          let id = c.id("frame")
          if c.clicked(id) {
            taps.val = taps.val + 1
          }
          c.box(w=Fill(1.0), h=Fill(1.0), bg=red, id~, fn() { () }) |> ignore
        })
        |> ignore
        c.box(w=Px(60.0), h=Px(40.0), radius=8.0, clip=true, left=80.0, top=80.0, fn() {
          c.box(w=Fill(1.0), h=Fill(1.0), bg=0x0000FFFFL, fn() { () }) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  }
}

///|
test "a rounded clip cutting through another's corner: what it holds cut by both, the other whole as its outer (40-51)" {
  let taps = Ref(0)
  let t = Tester::new(pane_frames(taps), w=260.0, h=260.0)
  t.draw()
  let a = rect_of_color(red)
  // its own clip: the frame's rect, its corners its own (the pane's curve crosses its edges, at no corner of it)
  assert_eq([a[16], a[17], a[18], a[19]], [30.0, 22.0, 90.0, 62.0])
  assert_eq([a[24], a[25], a[26], a[27]], [8.0, 8.0, 8.0, 8.0])
  // and the pane's, whole: its rect, its corners, as smooth as it is
  assert_eq([a[40], a[41], a[42], a[43]], [20.0, 20.0, 220.0, 220.0])
  assert_eq([a[44], a[45], a[46], a[47]], [30.0, 30.0, 30.0, 30.0])
  assert_eq([a[48], a[49], a[50], a[51]], [1.0, 1.0, 1.0, 1.0])
  // the one in the pane's middle reaches into none of its corners: no outer
  let b = rect_of_color(0x0000FFFFL)
  assert_eq([b[44], b[45], b[46], b[47]], [0.0, 0.0, 0.0, 0.0])
  // the draw list says it (mbui-dl 7, 52 numbers)
  assert_true(t.drawlist().has_prefix("mbui-dl 7\n"))
  // a press in the frame but past the pane's curve misses it; within both, it reaches it
  t.tap(31.0, 23.0)
  t.draw()
  assert_eq(taps.val, 0)
  t.tap(60.0, 40.0)
  t.draw()
  assert_eq(taps.val, 1)
}

///|
test "a rounded clip mostly past the window's edge keeps what shows of its rect: its far corner as round as its line" {
  let t = Tester::new(
    fn(c) {
      // a card 240 wide, 184 of it past the window's left edge: 56 shown, its foot right corner 46 round
      c.box(w=Px(240.0), h=Px(200.0), radius=46.0, clip=true, left=-184.0, top=0.0, fn() {
        c.box(w=Fill(1.0), h=Fill(1.0), bg=red, fn() { () }) |> ignore
      })
      |> ignore
    },
    w=260.0,
    h=260.0,
  )
  t.draw()
  let a = rect_of_color(red)
  // cut to the 56 shown, its far corners its own, drawn 46 round where the card has them (sd_clip), not flattened to
  // the 28 half of what shows
  assert_eq([a[16], a[17], a[18], a[19]], [0.0, 0.0, 56.0, 200.0])
  assert_eq([a[25], a[26]], [46.0, 46.0])
  let scale = 2.0
  for k in 0..<(46.0 * scale).to_int() {
    let px = 10.0 + (k.to_double() + 0.5) / scale
    for py in [1.0, 199.0] {
      let want = dclamp(0.5 - sd_box(px - (56.0 - 120.0), py - 100.0, 120.0, 100.0, 46.0) * scale, 0.0, 1.0)
      let have = covered(a, px, py, scale)
      if (have - want).abs() > 0.01 {
        fail("(\{px}, \{py}): the clip keeps \{have}, the card's ground \{want}")
      }
    }
  }
}

///|
test "a clip two curves cut into at once: the one that cuts more of it its outer" {
  let t = Tester::new(
    fn(c) {
      c.box(pad=20.0, align=AStart, fn() {
        // the pane, a card in its corner (cutting through its curve), a frame in the card's corner (cutting through
        // both curves): its outer the card's, which cuts more of it; the pane's the error left (scene.mbt clip_stack)
        c.box(w=Px(200.0), h=Px(200.0), radius=30.0, clip=true, fn() {
          c.box(w=Px(120.0), h=Px(120.0), radius=20.0, clip=true, left=6.0, top=6.0, fn() {
            c.box(w=Px(40.0), h=Px(40.0), radius=4.0, clip=true, left=2.0, top=2.0, fn() {
              c.box(w=Fill(1.0), h=Fill(1.0), bg=red, fn() { () }) |> ignore
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    w=260.0,
    h=260.0,
  )
  t.draw()
  let a = rect_of_color(red)
  assert_eq([a[40], a[41], a[42], a[43]], [26.0, 26.0, 146.0, 146.0])
  assert_eq([a[44], a[45], a[46], a[47]], [20.0, 20.0, 20.0, 20.0])
}
