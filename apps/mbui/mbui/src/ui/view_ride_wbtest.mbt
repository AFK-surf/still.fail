// A list's rows of the window's tree drawn again as kept, moved (view_ride.mbt): what a frame scrolled by whole pixels
// draws is what drawing each of them anew draws there; one changed since, or moved by part of a pixel, drawn anew.

///|
/// A page's list 300 tall scrolling 20 rows, each 50 tall, round, edged and clipping: its words, an icon and a box of its
/// own round and clipping in it; how far it is scrolled, and the third row's words.
fn ride_tester(at : @view.Scroll, third : @signals.Signal[String]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=240.0, h=400.0, scale=2.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(240.0))).height(Is(Some(300.0))).clips(Is(true)) |> ignore
      o.scrolls(at, fn(s) {
        for i in 0..<20 {
          s.box(fn(r) {
            r
            .width(Is(Some(240.0)))
            .height(Is(Some(50.0)))
            .ground(Is(0xEEF0F4FFL))
            .radius(Is(8.0))
            .edge(Is((1.0, 0x99999999L)))
            .clips(Is(true))
            |> ignore
            r.box(fn(w) {
              let words : @view.Live[String] = if i == 2 { By(fn() { third.get() }) } else { Is("row \{i}") }
              w.offset(Is((12.0, 15.0))).words(words, ink=0x222222FFL) |> ignore
            })
            |> ignore
            r.box(fn(k) {
              k
              .over(Is(true))
              .offset(Is((200.0, 15.0)))
              .width(Is(Some(20.0)))
              .height(Is(Some(20.0)))
              .shapes(Is([shape_of([([0.0, 0.0, 20.0, 0.0, 20.0, 20.0], true)], fill=0xCC3333FFL)]))
              |> ignore
            })
            |> ignore
            r.box(fn(b) {
              b
              .over(Is(true))
              .offset(Is((150.0, 10.0)))
              .width(Is(Some(30.0)))
              .height(Is(Some(30.0)))
              .radius(Is(15.0))
              .clips(Is(true))
              .ground(Is(0x3366CCFFL))
              |> ignore
              b.box(fn(d) {
                d.over(Is(true)).offset(Is((-5.0, -5.0))).width(Is(Some(20.0))).height(Is(Some(20.0))).ground(Is(0xFFCC00FFL)) |> ignore
              })
              |> ignore
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
/// What is drawn scrolled to `to` with nothing of the rows kept: each drawn anew there (first drawn a quarter of a pixel
/// off it, kept there, then moved by part of a pixel: drawn anew).
fn ride_fresh(t : Tester, at : @view.Scroll, to : Double) -> String raise {
  at.put(to + 0.125)
  t.draw()
  at.put(to)
  let again = ride_drawn.val
  t.draw()
  assert_eq(ride_drawn.val, again, msg="moved by part of a pixel: drawn anew")
  t.drawn_text()
}

///|
test "rows scrolled by whole pixels drawn as kept, moved: as each drawn anew there" {
  let at = @view.Scroll::list()
  let third = @signals.signal("row 2")
  let t = ride_tester(at, third)
  for to in [20.0, 57.5, 150.0, 151.0] {
    let again = ride_drawn.val
    let heads = ride_heads.val
    at.put(to)
    t.draw()
    assert_true(ride_drawn.val > again, msg="scrolled to \{to}: rows drawn as kept")
    // (by a header of what the host keeps, drawn out as the paint ends as a host draws it)
    assert_true(ride_heads.val > heads, msg="scrolled to \{to}: rows said by their groups' headers")
    assert_true(ride_spans.is_empty(), msg="scrolled to \{to}: the Tester's frame drawn out")
    let kept = t.drawn_text()
    assert_eq(kept, ride_fresh(t, at, to), msg="scrolled to \{to}: as drawn anew")
  }
}

///|
test "a row changed since it was kept drawn anew, as it is now" {
  let at = @view.Scroll::list()
  let third = @signals.signal("row 2")
  let t = ride_tester(at, third)
  at.put(10.0)
  t.draw()
  third.set("the third row")
  at.put(30.0)
  t.draw()
  let kept = t.drawn_text()
  assert_eq(kept, ride_fresh(t, at, 30.0), msg="its words as they are now")
}
