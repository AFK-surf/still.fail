// A look's `rot` (draw.mbt): what it draws turned about its point, the instances keeping their rects as laid out and
// carrying how they are turned (scene.mbt 32-34); a turn inside a turn one turn about the point the two come to (or,
// adding up to none, a move); the draw list's 36 numbers an instance (mbui-dl 5) only when something is turned.

///|
/// Where the point (`x`, `y`) of instance `a`'s rect is drawn, turned as it says.
fn drawn_at(a : Array[Double], x : Double, y : Double) -> (Double, Double) {
  if a[32] == 0.0 {
    return (x, y)
  }
  let (c, s) = (@dmath.cos(a[32]), @dmath.sin(a[32]))
  let (dx, dy) = (x - a[33], y - a[34])
  (a[33] + c * dx - s * dy, a[34] + s * dx + c * dy)
}

///|
fn near(a : (Double, Double), b : (Double, Double)) -> Bool {
  (a.0 - b.0).abs() < 1.0e-9 && (a.1 - b.1).abs() < 1.0e-9
}

///|
/// A red box 100 by 40 at (20, 20) turned by `outer` about its top's middle, holding at its top left a blue box 20 by 10
/// turned by `inner` about its own top left.
fn turned_view(outer : Double, inner : Double) -> (Ctx) -> Unit {
  fn(c) {
    c.box(pad=20.0, align=AStart, fn() {
      let b = c.box(w=Px(100.0), h=Px(40.0), bg=red, align=AStart, fn() {
        let k = c.box(w=Px(20.0), h=Px(10.0), bg=0x0000FFFFL, fn() { () })
        if inner != 0.0 {
          c.look(k, look(ox=0.0, oy=0.0, rot=inner))
        }
      })
      if outer != 0.0 {
        c.look(b, look(oy=0.0, rot=outer))
      }
    })
    |> ignore
  }
}

///|
test "a turned box: its rect as laid out, turned about its point" {
  let t = Tester::new(turned_view(0.1, 0.0), w=200.0, h=120.0)
  t.draw()
  let a = rect_of_color(red)
  assert_eq((a[0], a[1], a[2], a[3]), (20.0, 20.0, 100.0, 40.0))
  assert_eq((a[32], a[33], a[34]), (0.1, 70.0, 20.0))
  // what it holds turns with it, about the same point
  let k = rect_of_color(0x0000FFFFL)
  assert_eq((k[0], k[1], k[32], k[33], k[34]), (20.0, 20.0, 0.1, 70.0, 20.0))
}

///|
test "a turn in a turn: one turn, where the two put it" {
  let (o, i) = (0.1, 0.25)
  let t = Tester::new(turned_view(o, i), w=200.0, h=120.0)
  t.draw()
  let k = rect_of_color(0x0000FFFFL)
  assert_true((k[32] - (o + i)).abs() < 1.0e-12)
  // each corner where the inner turn (about (20, 20)) then the outer one (about (70, 20)) take it
  let turn = fn(r : Double, px : Double, py : Double, p : (Double, Double)) {
    let (c, s) = (@dmath.cos(r), @dmath.sin(r))
    (px + c * (p.0 - px) - s * (p.1 - py), py + s * (p.0 - px) + c * (p.1 - py))
  }
  for p in [(20.0, 20.0), (40.0, 20.0), (20.0, 30.0), (40.0, 30.0)] {
    let want = turn(o, 70.0, 20.0, turn(i, 20.0, 20.0, p))
    assert_true(near(drawn_at(k, p.0, p.1), want), msg="\{p}: \{drawn_at(k, p.0, p.1)} for \{want}")
  }
}

///|
test "turned back as far: not turned, moved" {
  let still = Tester::new(turned_view(0.0, 0.0), w=200.0, h=120.0)
  still.draw()
  let k0 = rect_of_color(0x0000FFFFL)
  let t = Tester::new(turned_view(0.3, -0.3), w=200.0, h=120.0)
  t.draw()
  let k = rect_of_color(0x0000FFFFL)
  assert_eq(k[32], 0.0)
  // the inner turn takes (20, 20) nowhere, the outer one about (70, 20) does
  let (c, s) = (@dmath.cos(0.3), @dmath.sin(0.3))
  let want = (70.0 + c * -50.0, 20.0 + s * -50.0)
  assert_true(near((k[0], k[1]), want), msg="\{(k[0], k[1])} for \{want}")
  // what cuts it from outside (the window) where it was
  for j in 16..<20 {
    assert_eq(k[j], k0[j])
  }
}

///|
test "what cuts a turned box from outside stays where it is drawn; what cuts inside it turns with it" {
  let green = 0x34C759FFL
  let t = Tester::new(
    fn(c) {
      c.box(pad=20.0, align=AStart, fn() {
        c.box(w=Px(100.0), h=Px(60.0), clip=true, align=AStart, fn() {
          let b = c.box(w=Px(100.0), h=Px(60.0), bg=red, align=AStart, fn() {
            c.box(w=Px(40.0), h=Px(20.0), clip=true, fn() {
              c.box(w=Px(60.0), h=Px(30.0), bg=green, fn() { () }) |> ignore
            })
            |> ignore
          })
          c.look(b, look(oy=0.0, rot=0.07))
        })
        |> ignore
      })
      |> ignore
    },
    w=200.0,
    h=120.0,
  )
  t.draw()
  let r = rect_of_color(red)
  assert_eq((r[16], r[17], r[18], r[19]), (20.0, 20.0, 120.0, 80.0))
  assert_eq(r[35], 1.0)
  let k = rect_of_color(green)
  assert_eq(k[32], 0.07)
  assert_eq(k[35], 0.0)
}

///|
test "the draw list: 36 numbers an instance only when something is turned" {
  let still = Tester::new(turned_view(0.0, 0.0), w=200.0, h=120.0)
  still.draw()
  let dl = drawlist_of(g())
  assert_true(dl.has_prefix("mbui-dl 4\n"))
  let line = dl.split("\n").find_first(fn(l) { l.has_prefix("i ") }).unwrap()
  assert_eq(line.split(" ").count() - 1, 32)
  let turned = Tester::new(turned_view(0.1, 0.0), w=200.0, h=120.0)
  turned.draw()
  let dl = drawlist_of(g())
  assert_true(dl.has_prefix("mbui-dl 5\n"))
  let line = dl.split("\n").find_first(fn(l) { l.has_prefix("i ") }).unwrap()
  assert_eq(line.split(" ").count() - 1, 36)
}
