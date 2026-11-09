// A page's list of the window's tree drawn again as kept, moved (view_ride.mbt): what a frame scrolled by whole pixels
// draws, by the header of the group the host keeps of it, is what drawing each of its rows anew draws there; one
// changed since drawn anew.

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
/// What is drawn scrolled to `to` with nothing of the rows kept: a window's tree as `third` says made anew, scrolled
/// there before it is first drawn, each row drawn anew there.
fn ride_fresh(to : Double, third : @signals.Signal[String]) -> String {
  let at = @view.Scroll::list()
  at.put(to)
  ride_tester(at, third).drawn_text()
}

///|
test "a page's list scrolled by whole pixels drawn by its group's header, moved: as each row drawn anew there" {
  let third = @signals.signal("row 2")
  let steps = [20.0, 30.0, 57.5, 140.0, 145.0]
  for k in 0..<steps.length() {
    // (scrolled on to each step in turn, each drawn: what the last draws as it was kept)
    let at = @view.Scroll::list()
    let t = ride_tester(at, third)
    let mut alone = 0
    for i in 0..=k {
      alone = t.looks_alone()
      at.put(steps[i])
      // (a frame as a host's: a test's draw is an event from outside, built whole: Tester::frame)
      t.frame()
    }
    let to = steps[k]
    // (by the header of what the host keeps of it, drawn out as the paint ends as a host draws it)
    assert_true(!list_heads.is_empty(), msg="scrolled to \{to}: the list said by its group's header")
    assert_true(ride_spans.is_empty(), msg="scrolled to \{to}: the Tester's frame drawn out")
    // (no row come into its window: nothing painted, the header moved alone)
    if to == 30.0 || to == 145.0 {
      assert_eq(t.looks_alone(), alone + 1, msg="scrolled to \{to}: drawn of its looks alone, not: \{t.built_why()}\{t.painted_why()}")
    }
    let kept = t.drawn_text()
    assert_eq(kept, ride_fresh(to, third), msg="scrolled to \{to}: as drawn anew")
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
  // (the list drawn again for it: the rows kept said in its group by their own groups' headers, drawn out in their
  // places)
  assert_true(ride_drawn.val > 0, msg="its other rows drawn as kept")
  assert_true(ride_groups.values().any(fn(g) { g.heads }), msg="the list's group holds its rows' headers")
  let kept = t.drawn_text()
  assert_eq(kept, ride_fresh(30.0, third), msg="its words as they are now")
}

///|
/// What a page's list keeps of its rows past where it shows is cut away by its group's header's clip, its column's,
/// though what is cut is clipped round of its own and has no outer (a row's words in its round box: the history's
/// commands scrolled past its top, drawn over its details' figures, 2026-11-09): cut as the square clip it is in cuts
/// a round one, never by an outer with no corner's radius, which is none (scene.mbt 40-51), what it cut drawn whole.
test "a page's list's rows past its top cut by its clip where they are round and have no outer, as where they are square" {
  let at = @view.Scroll::list()
  at.put(60.0)
  let t = ride_tester(at, @signals.signal("row 2"))
  assert_true(!list_heads.is_empty(), msg="the list said by its group's header")
  let mut round = 0
  for a in t.drawn_instances() {
    // (a shape's pieces, kind 12, are none drawn: its band's numbers)
    if a[2] <= 0.0 || a[3] <= 0.0 || a[5] == 12.0 {
      continue
    }
    if a[5] == 1.0 && (a[24] > 0.0 || a[25] > 0.0 || a[26] > 0.0 || a[27] > 0.0) {
      round += 1
    }
    // (where it may be seen, as the renderers cut it: its clip, and its outer where that has a corner's radius)
    let outer = a[44] > 0.0 || a[45] > 0.0 || a[46] > 0.0 || a[47] > 0.0
    let y0 = if outer { dmax(a[17], a[41]) } else { a[17] }
    let y1 = if outer { dmin(a[19], a[43]) } else { a[19] }
    assert_true(
      y1 <= y0 || (y0 >= 0.0 && y1 <= 300.0),
      msg="kind \{a[5]} at (\{a[0]}, \{a[1]}) seen from \{y0} to \{y1}: past the list's column (0 to 300)",
    )
  }
  assert_true(round > 0, msg="words clipped round of their own in the rows drawn")
}
