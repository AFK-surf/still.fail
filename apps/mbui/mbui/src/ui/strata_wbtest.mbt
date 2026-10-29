// Strata (strata.mbt): each over the ones under it, whatever order they are built in, pair by pair.

///|
/// A page: its content 90 by 90 holding what flies (50 by 30) and a row held for a menu (40 by 25), a composer 60 by
/// 20, its bar 70 by 40; with `cover`, a cover 80 by 60 over it, the composer over that; with `menu`, a modal layer
/// with a scrim (the window's size) and a panel 100 by 100 in it.
fn strata_page(cover : Bool, menu : Bool) -> (Ctx) -> Unit {
  fn(c) {
    c.column(fn() {
      c.box(w=Px(90.0), h=Px(90.0), bg=0x333333FFL, fn() {
        let f = c.box(w=Px(50.0), h=Px(30.0), bg=0x336699FFL, fn() {  })
        c.stratum(f, Flying)
        let held = c.box(w=Px(40.0), h=Px(25.0), bg=0x996633FFL, fn() {  })
        c.stratum(held, OverScrim)
      })
      |> ignore
      let composer = c.layer(fn() { c.box(w=Px(60.0), h=Px(20.0), bg=0x993366FFL, fn() {  }) |> ignore })
      c.stratum(composer, OverCover)
      let bar = c.layer(fn() { c.box(w=Px(70.0), h=Px(40.0), bg=0x669933FFL, fn() {  }) |> ignore })
      c.stratum(bar, Bar)
      if cover {
        let l = c.layer(fn() { c.box(w=Px(80.0), h=Px(60.0), bg=0x999999FFL, fn() {  }) |> ignore })
        c.stratum(l, Cover)
      }
      if menu {
        c.overlay("menu", modal=true, scrim=0x00000040L, fn() {
          c.box(w=Px(100.0), h=Px(100.0), bg=0xFFFFFFFFL, fn() {  }) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  }
}

///|
/// Whether each of `sizes` is painted, in this order.
fn painted_in_order(sizes : Array[(Double, Double)]) -> Bool {
  let at = sizes.map(fn(s) { painted_at(s.0, s.1) })
  for k, a in at {
    if a < 0 || (k > 0 && at[k - 1] >= a) {
      return false
    }
  }
  true
}

///|
test "strata: content, what floats over it, what flies, the bar" {
  let t = Tester::new(strata_page(false, false), w=400.0, h=300.0)
  t.frame()
  // (with no cover the composer is in its place; the held row with no scrim too)
  assert_true(painted_in_order([(90.0, 90.0), (40.0, 25.0), (60.0, 20.0), (50.0, 30.0), (70.0, 40.0)]))
}

///|
/// A page drawn moved by `page_dy` (a page sliding, a keyboard), its content 90 by 90 holding a box drawn moved by
/// `held_dy` (a row gliding) that holds what flies (50 by 30); a composer 60 by 20 and its bar 70 by 40 over them.
fn strata_moving(page_dy : Double, held_dy : Double) -> (Ctx) -> Unit {
  fn(c) {
    let page = c.column(fn() {
      c.box(w=Px(90.0), h=Px(90.0), bg=0x333333FFL, fn() {
        let held = c.box(w=Px(60.0), h=Px(40.0), fn() {
          let f = c.box(w=Px(50.0), h=Px(30.0), bg=0x336699FFL, fn() {  })
          c.stratum(f, Flying)
        })
        c.look(held, look(dy=held_dy))
      })
      |> ignore
      let composer = c.layer(fn() { c.box(w=Px(60.0), h=Px(20.0), bg=0x993366FFL, fn() {  }) |> ignore })
      c.stratum(composer, OverCover)
      let bar = c.layer(fn() { c.box(w=Px(70.0), h=Px(40.0), bg=0x669933FFL, fn() {  }) |> ignore })
      c.stratum(bar, Bar)
    })
    c.look(page, look(dy=page_dy))
  }
}

///|
/// Where instance `w` by `h` is drawn down the window.
fn painted_y(w : Double, h : Double) -> Double {
  let c = g()
  c.inst[painted_at(w, h) * inst_size + 1]
}

///|
test "strata: what flies in what moves: over what floats over the page, under its bar, moved with what holds it" {
  // (a row gliding in a still page)
  let t = Tester::new(strata_moving(0.0, 20.0), w=400.0, h=300.0)
  t.frame()
  assert_true(painted_in_order([(90.0, 90.0), (60.0, 20.0), (50.0, 30.0), (70.0, 40.0)]))
  assert_eq(painted_y(50.0, 30.0), 20.0)
  // (and the page moving too: its bar drawn moved with it, over what flies all the same)
  let t = Tester::new(strata_moving(30.0, 20.0), w=400.0, h=300.0)
  t.frame()
  assert_true(painted_in_order([(90.0, 90.0), (60.0, 20.0), (50.0, 30.0), (70.0, 40.0)]))
  assert_eq(painted_y(50.0, 30.0), 50.0)
  assert_eq(painted_y(70.0, 40.0), 30.0)
}

///|
test "strata: the cover over the bar and what flies, what is over it over it" {
  let t = Tester::new(strata_page(true, false), w=400.0, h=300.0)
  t.frame()
  assert_true(painted_in_order([(90.0, 90.0), (50.0, 30.0), (70.0, 40.0), (80.0, 60.0), (60.0, 20.0)]))
}

///|
test "strata: a modal layer over all of the page, what is held over its scrim and under what it holds" {
  let t = Tester::new(strata_page(false, true), w=400.0, h=300.0)
  t.frame()
  assert_true(painted_in_order([(50.0, 30.0), (70.0, 40.0), (400.0, 300.0), (40.0, 25.0), (100.0, 100.0)]))
}

///|
test "strata: what is over the layers over a layer opened over the page, built before it or not" {
  let t = Tester::new(
    fn(c) {
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        c.box(w=Px(90.0), h=Px(90.0), bg=0x336699FFL, fn() {  }) |> ignore
        let bar = c.layer(fn() { c.box(w=Px(70.0), h=Px(40.0), bg=0x669933FFL, fn() {  }) |> ignore })
        c.stratum(bar, Bar)
        c.stratum(bar, OverLayers)
        c.overlay("viewer", modal=true, fn() {
          c.box(w=Px(100.0), h=Px(100.0), bg=0xFFFFFFFFL, fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
  )
  t.frame()
  assert_true(painted_in_order([(90.0, 90.0), (100.0, 100.0), (70.0, 40.0)]))
}
