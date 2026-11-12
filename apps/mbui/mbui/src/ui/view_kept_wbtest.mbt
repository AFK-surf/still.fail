// What holds others kept with all it holds (view_ride.mbt, Riding's `holder`): drawn again as kept where nothing of it
// changed, one kept inside another or inside a list's row, what changed gone through down to itself and no further;
// what is drawn so is what drawing all of it anew draws.

///|
/// A window 240 by 400: a bar of three, the last its words by `clock`, over a body of four cards, each of three, the
/// second card's last its words by `card`.
fn kept_tester(clock : @signals.Signal[String], card : @signals.Signal[String]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=240.0, h=400.0, scale=2.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(240.0))).height(Is(Some(400.0))) |> ignore
      o.box(fn(bar) {
        bar.width(Is(Some(240.0))).height(Is(Some(40.0))).ground(Is(0xEEF0F4FFL)) |> ignore
        for i in 0..<3 {
          bar.box(fn(b) {
            let words : @view.Live[String] = if i == 2 { By(fn() { clock.get() }) } else { Is("bar \{i}") }
            b.offset(Is((10.0 + 70.0 * i.to_double(), 10.0))).words(words, ink=0x222222FFL) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      o.box(fn(body) {
        body.width(Is(Some(240.0))).height(Is(Some(300.0))) |> ignore
        for i in 0..<4 {
          body.box(fn(r) {
            r
            .width(Is(Some(220.0)))
            .height(Is(Some(60.0)))
            .ground(Is(0xFFFFFFFFL))
            .radius(Is(8.0))
            .edge(Is((1.0, 0x99999999L)))
            |> ignore
            for j in 0..<3 {
              r.box(fn(w) {
                let words : @view.Live[String] = if i == 1 && j == 2 {
                  By(fn() { card.get() })
                } else {
                  Is("card \{i} \{j}")
                }
                w.offset(Is((12.0, 4.0 + 18.0 * j.to_double()))).words(words, ink=0x222222FFL) |> ignore
              })
              |> ignore
            }
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "what holds others drawn again as kept round what changed in it, as drawn anew" {
  let clock = @signals.signal("12:00")
  let card = @signals.signal("waiting")
  let t = kept_tester(clock, card)
  // (the bar's words changed each time: the body, gone through as it was twice running, kept, drawn again as kept)
  let again = []
  for i in 1..=4 {
    let drawn = ride_drawn.val
    clock.set("12:0\{i}")
    t.draw()
    again.push(ride_drawn.val - drawn)
  }
  let kept = t.drawn_text()
  assert_eq(kept, kept_tester(clock, card).drawn_text(), msg="the bar's words changed")
  assert_true(again[2] > 0 && again[3] > 0, msg="the body drawn again as kept: \{Repr(again)}")
  // (a card's words changed each time: the bar and the three other cards kept, drawn again as kept)
  let t = kept_tester(clock, card)
  let again = []
  for i in 1..=4 {
    let drawn = ride_drawn.val
    card.set("answered \{i}")
    t.draw()
    again.push(ride_drawn.val - drawn)
  }
  let kept = t.drawn_text()
  assert_eq(kept, kept_tester(clock, card).drawn_text(), msg="a card's words changed")
  assert_true(again[2] >= 4 && again[3] >= 4, msg="the bar and the other cards drawn again as kept: \{Repr(again)}")
}

///|
/// A page's list 300 tall of 12 rows, each 50 tall: its words (the third's by `third`) and a badge of two of its own;
/// scrolled by `at`.
fn kept_rows(at : @view.Scroll, third : @signals.Signal[String]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=240.0, h=400.0, scale=2.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(240.0))).height(Is(Some(300.0))).clips(Is(true)) |> ignore
      o.scrolls(at, fn(s) {
        for i in 0..<12 {
          s.box(fn(r) {
            r.width(Is(Some(240.0))).height(Is(Some(50.0))).ground(Is(0xEEF0F4FFL)) |> ignore
            r.box(fn(w) {
              let words : @view.Live[String] = if i == 2 { By(fn() { third.get() }) } else { Is("row \{i}") }
              w.offset(Is((12.0, 15.0))).words(words, ink=0x222222FFL) |> ignore
            })
            |> ignore
            r.box(fn(b) {
              b
              .over(Is(true))
              .offset(Is((150.0, 10.0)))
              .width(Is(Some(60.0)))
              .height(Is(Some(30.0)))
              .radius(Is(8.0))
              .ground(Is(0x3366CCFFL))
              |> ignore
              for j in 0..<2 {
                b.box(fn(d) {
                  d.offset(Is((6.0 + 26.0 * j.to_double(), 5.0))).width(Is(Some(20.0))).height(Is(Some(20.0))).ground(Is(0xFFCC00FFL)) |> ignore
                })
                |> ignore
              }
            })
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "a list's row changed each time drawn with its parts that did not change as kept, as drawn anew" {
  let at = @view.Scroll::list()
  let third = @signals.signal("row 2")
  let t = kept_rows(at, third)
  at.put(10.0)
  t.draw()
  // (the other rows drawn again as kept each time; its badge inside it too once kept)
  let again = []
  for i in 1..=4 {
    let drawn = ride_drawn.val
    third.set("the third row \{i}")
    t.draw()
    again.push(ride_drawn.val - drawn)
  }
  let kept = t.drawn_text()
  let fresh = {
    let at = @view.Scroll::list()
    at.put(10.0)
    kept_rows(at, third).drawn_text()
  }
  assert_eq(kept, fresh, msg="its words as they are now")
  assert_true(again[2] > again[0] && again[3] > again[0], msg="its badge drawn again as kept: \{Repr(again)}")
}
