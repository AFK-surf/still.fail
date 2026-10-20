// A box with `clip` and a `radius` cuts what it holds to its rounded rect (Compose's clip(RoundedCornerShape)): the
// instances of what it holds carry that rounded rect (scene.mbt 16-19, the corners' radii 24-27 and how smooth they
// are 28-31), the renderers cover their edge as the box's own ground's, and a press in a corner it cut away reaches
// nothing there.

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
/// shader): its own rounded rect's edge, times its clip's when that is rounded.
fn covered(a : Array[Double], px : Double, py : Double, scale : Double) -> Double {
  let cover = fn(d : Double) { dclamp(0.5 - d * scale, 0.0, 1.0) }
  let own = cover(sd_box(px - (a[0] + a[2] / 2.0), py - (a[1] + a[3] / 2.0), a[2] / 2.0, a[3] / 2.0, a[4]))
  if dmax(dmax(a[24], a[25]), dmax(a[26], a[27])) <= 0.0 {
    return if px < a[16] || py < a[17] || px > a[18] || py > a[19] { 0.0 } else { own }
  }
  let hx = (a[18] - a[16]) / 2.0
  let hy = (a[19] - a[17]) / 2.0
  let mx = a[16] + hx
  let my = a[17] + hy
  let j = if px < mx {
    if py < my {
      0
    } else {
      3
    }
  } else if py < my {
    1
  } else {
    2
  }
  own * cover(sd_corner(px - mx, py - my, hx, hy, dmin(a[24 + j], dmin(hx, hy)), a[28 + j]))
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
