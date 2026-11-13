// What a look holds as faint as it says (Look's `words`, words_alpha): its surface's own ground and edge (the box it is
// on, or one said to be: Ctx::surface) as faint as the look, all else it holds as one at `words` (a box's ground and
// edge, words, a nested look's content, what is put off to be painted over the layers), whatever it looks like.

///|
fn faint(words : Double, dx? : Double = 0.0) -> Look {
  { alpha: 1.0, dx, dy: 0.0, sx: 1.0, sy: 1.0, ox: 0.5, oy: 0.5, rot: 0.0, circle: 0.0, words }
}

///|
/// Under looks of `words` 0.5, each its own sizes:
/// - on a panel 200 by 150 (its ground, an edge drawn over what it holds) holding a box 100 by 40 with a ground and an
///   edge, and words;
/// - on what holds a panel said to be its surface (180 by 60) holding a box 90 by 20: the panel whole, the box faint;
/// - on what holds a card 170 by 50 not said to be (the same as the panel above but for that) holding a box 85 by 20:
///   both faint;
/// - on what holds a box 80 by 30 under a look of `words` 1 (moved only) holding a box 30 by 20: both as faint as the
///   outer look's;
/// - on what holds a box 75 by 30 under a look of `words` 0.5 holding a box 25 by 20: the first 0.5, the second 0.25;
/// - on what holds a box 50 by 30 put off over the layers (OverLayers): 0.5;
/// - on what holds a panel said to be its surface (160 by 45) put off over the layers, holding a box 70 by 18; and on
///   what holds a box that cuts holding a panel said to be (150 by 40) holding a box 65 by 18: each panel whole, what
///   is on it 0.5.
fn held_page() -> (Ctx) -> Unit {
  fn(c) {
    c.column(fn() {
      let panel = c.box(w=Px(200.0), h=Px(150.0), bg=0xFFFFFFFFL, style=style(border=B2, border_color=Fg), fn() {
        c.box(w=Px(100.0), h=Px(40.0), bg=0x336699FFL, style=style(border=B1, border_color=Fg), fn() {  }) |> ignore
        c.text("字", size=15.0) |> ignore
      })
      c.look(panel, faint(0.5))
      let said = c.box(fn() {
        let p = c.box(w=Px(180.0), h=Px(60.0), bg=0xEEEEEEFFL, fn() {
          c.box(w=Px(90.0), h=Px(20.0), bg=0x333366FFL, fn() {  }) |> ignore
        })
        c.surface(p)
      })
      c.look(said, faint(0.5))
      let unsaid = c.box(fn() {
        c.box(w=Px(170.0), h=Px(50.0), bg=0xEEEEEEFFL, fn() {
          c.box(w=Px(85.0), h=Px(20.0), bg=0x333366FFL, fn() {  }) |> ignore
        })
        |> ignore
      })
      c.look(unsaid, faint(0.5))
      let moved = c.box(fn() {
        let inner = c.box(w=Px(80.0), h=Px(30.0), bg=0x996633FFL, fn() {
          c.box(w=Px(30.0), h=Px(20.0), bg=0x669933FFL, fn() {  }) |> ignore
        })
        c.look(inner, faint(1.0, dx=3.0))
      })
      c.look(moved, faint(0.5))
      let twice = c.box(fn() {
        let inner = c.box(w=Px(75.0), h=Px(30.0), bg=0x996699FFL, fn() {
          c.box(w=Px(25.0), h=Px(20.0), bg=0x669999FFL, fn() {  }) |> ignore
        })
        c.look(inner, faint(0.5))
      })
      c.look(twice, faint(0.5))
      let off = c.box(fn() {
        let put_off = c.box(w=Px(50.0), h=Px(30.0), bg=0x993366FFL, fn() {  })
        c.stratum(put_off, OverLayers)
      })
      c.look(off, faint(0.5))
      let said_off = c.box(fn() {
        let p = c.box(w=Px(160.0), h=Px(45.0), bg=0xDDDDDDFFL, fn() {
          c.box(w=Px(70.0), h=Px(18.0), bg=0x336633FFL, fn() {  }) |> ignore
        })
        c.surface(p)
        c.stratum(p, OverLayers)
      })
      c.look(said_off, faint(0.5))
      let said_cut = c.box(fn() {
        c.box(clip=true, fn() {
          let p = c.box(w=Px(150.0), h=Px(40.0), bg=0xCCCCCCFFL, fn() {
            c.box(w=Px(65.0), h=Px(18.0), bg=0x663333FFL, fn() {  }) |> ignore
          })
          c.surface(p)
        })
        |> ignore
      })
      c.look(said_cut, faint(0.5))
      // (a look of its own in it come to nothing now, a surface said in that: as faint as what holds it, all the same)
      let still = c.box(fn() {
        let inner = c.box(fn() {
          let p = c.box(w=Px(140.0), h=Px(35.0), bg=0xBBBBBBFFL, fn() {
            c.box(w=Px(60.0), h=Px(15.0), bg=0x333333FFL, fn() {  }) |> ignore
          })
          c.surface(p)
        })
        c.look(inner, faint(1.0))
      })
      c.look(still, faint(0.5))
    })
    |> ignore
  }
}

///|
/// The instances drawn `w` by `h`: each its fill's alpha and its edge's where it draws one (rounded to hundredths).
fn held_alphas(w : Double, h : Double) -> Array[(Double, Double)] {
  let c = g()
  let out = []
  let r = fn(v : Double) { (v * 100.0).round() / 100.0 }
  for k in 0..<c.ninst {
    let q = k * inst_size
    if c.inst[q + 2] == w && c.inst[q + 3] == h {
      out.push((r(c.inst[q + 11]), if c.inst[q + 5] == 0.0 && c.inst[q + 6] > 0.0 { r(c.inst[q + 15]) } else { -1.0 }))
    }
  }
  out
}

///|
test "a look's words: its surface whole (the box it is on, or one said to be), all else it holds as one at its words, whatever it looks like; a look of words 1 in it, or one put off, keeping its words; two looks' together" {
  let t = Tester::new(held_page(), w=400.0, h=1300.0)
  t.frame()
  let c = g()
  let glyphs = []
  for k in 0..<c.ninst {
    let q = k * inst_size
    if c.inst[q + 5] == 1.0 && c.inst[q + 11] > 0.0 {
      glyphs.push((c.inst[q + 11] * 100.0).round() / 100.0)
    }
  }
  assert_eq(
    [
      ("panel", held_alphas(200.0, 150.0)),
      ("on the panel", held_alphas(100.0, 40.0)),
      ("said", held_alphas(180.0, 60.0)),
      ("on it", held_alphas(90.0, 20.0)),
      ("not said", held_alphas(170.0, 50.0)),
      ("on that", held_alphas(85.0, 20.0)),
      ("under words 1", held_alphas(80.0, 30.0)),
      ("in that", held_alphas(30.0, 20.0)),
      ("under two", held_alphas(75.0, 30.0)),
      ("in those", held_alphas(25.0, 20.0)),
      ("put off", held_alphas(50.0, 30.0)),
      ("said, put off", held_alphas(160.0, 45.0)),
      ("on it, put off", held_alphas(70.0, 18.0)),
      ("said, in a cut", held_alphas(150.0, 40.0)),
      ("on it, in a cut", held_alphas(65.0, 18.0)),
      ("said, in a still look", held_alphas(140.0, 35.0)),
      ("on it, in a still look", held_alphas(60.0, 15.0)),
    ],
    [
      // (its ground whole, its edge left to be drawn over what it holds; that edge whole)
      ("panel", [(1.0, 0.0), (0.0, 1.0)]),
      ("on the panel", [(0.5, 0.5)]),
      ("said", [(1.0, -1.0)]),
      ("on it", [(0.5, -1.0)]),
      // (a card not said to be the surface: what the look holds, as a button's ground in a panel is)
      ("not said", [(0.5, -1.0)]),
      ("on that", [(0.5, -1.0)]),
      ("under words 1", [(0.5, -1.0)]),
      ("in that", [(0.5, -1.0)]),
      ("under two", [(0.5, -1.0)]),
      ("in those", [(0.25, -1.0)]),
      ("put off", [(0.5, -1.0)]),
      // (a surface said, put off over the layers or in a box that cuts: whole all the same, what is on it as faint)
      ("said, put off", [(1.0, -1.0)]),
      ("on it, put off", [(0.5, -1.0)]),
      ("said, in a cut", [(1.0, -1.0)]),
      ("on it, in a cut", [(0.5, -1.0)]),
      // (its scope that look's, still or not: its surface as faint as what holds it, not as the one outside)
      ("said, in a still look", [(0.5, -1.0)]),
      ("on it, in a still look", [(0.5, -1.0)]),
    ],
  )
  assert_eq(glyphs.length() > 0 && glyphs.iter().all(fn(a) { a == 0.5 }), true, msg="\{Repr(glyphs)}")
}
