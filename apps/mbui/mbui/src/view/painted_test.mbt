// What reads where layout put things reads it as the frame is painted (Live's `Painted`, retained.md "Layout read
// back"), in that frame, and lays nothing out again; where it is read by the hand, as the tree last placed it
// (View::shown_rect); what a box holds chosen by its room in its own layout (View::by_room); a width within its holder
// said, not read back (View::min_width_within, max_width_within).

///|
test "a ring offset by where another node is laid out: in the frame that laid it out, one layout in it" {
  let wide = @signals.signal(80.0)
  let at : Ref[(@view.View, @view.View)?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(r) {
        r.row(Is(true)) |> ignore
        let card = r.box(fn(c) { c.width(By(fn() { Some(wide.get()) })).height(Is(Some(20.0))) |> ignore })
        let ring = r.box(fn(g) {
          g.width(Is(Some(10.0))).height(Is(Some(10.0))) |> ignore
          // (beside the card's right edge, wherever the row lays the card out)
          g.offset(Painted(fn(laid) { laid.rect(card).map(fn(c) { (c.0 + c.2, 0.0) }).unwrap_or((0.0, 0.0)) })) |> ignore
        })
        at.val = Some((card, ring))
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  let (card, ring) = at.val.unwrap()
  assert_eq(card.rect().2, 80.0)
  // (the ring laid out after the card, at 80, drawn off by the card's right edge, 80 more)
  assert_eq(ring.rect().0, 160.0)
  let computes = tree.work().computes
  wide.set(120.0)
  tree.frame(390.0, 844.0, now=16.0) |> ignore
  assert_eq(ring.rect().0, 240.0, msg="drawn where the card is in the frame it was laid out in")
  assert_eq(tree.work().computes - computes, 1, msg="one layout")
  // (nothing changed: no frame owed)
  assert_false(tree.frame(390.0, 844.0, now=32.0))
  tree.dispose()
}

///|
test "a Painted value reading a signal: drawn again as it changes, nothing laid out" {
  let shift = @signals.signal(0.0)
  let at : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      at.val = Some(root.box(fn(b) {
        b.width(Is(Some(10.0))).height(Is(Some(10.0))).offset(Painted(fn(_) { (shift.get(), 0.0) })) |> ignore
      }))
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  let b = at.val.unwrap()
  assert_eq(b.rect().0, 0.0)
  let computes = tree.work().computes
  shift.set(30.0)
  tree.frame(390.0, 844.0, now=16.0) |> ignore
  assert_eq(b.rect().0, 30.0)
  assert_eq(tree.work().computes - computes, 0, msg="nothing laid out for a place")
  tree.dispose()
}

///|
test "panic: a property layout reads said Painted aborts" {
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(b) { b.width(Painted(fn(_) { Some(10.0) })) |> ignore }) |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
}

///|
test "where the hand finds a node: as the tree last placed it" {
  let at : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(holder) {
      holder.padding(Is((12.0, 8.0, 0.0, 0.0))) |> ignore
      at.val = Some(holder.box(fn(b) { b.width(Is(Some(50.0))).height(Is(Some(20.0))) |> ignore }))
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(at.val.unwrap().shown_rect(), Some((12.0, 8.0, 50.0, 20.0)))
  assert_eq(at.val.unwrap().shown_size(), Some((50.0, 20.0)))
  tree.dispose()
}

///|
test "what a box holds chosen by its room, in its own layout: the other made as the room changes, one layout a frame" {
  let made : Array[String] = []
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(b) {
        b.grow(Is(1.0)) |> ignore
        b.by_room(Is(()), fn(_, w, _) { if w < 600.0 { "narrow" } else { "wide" } }, fn(v, k) {
          made.push(k)
          v.box(fn(x) { x.height(Is(Some(10.0))) |> ignore }) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  assert_eq(made, ["narrow"])
  let computes = tree.work().computes
  tree.frame(800.0, 844.0, now=16.0) |> ignore
  assert_eq(made, ["narrow", "wide"])
  assert_eq(tree.work().computes - computes, 1, msg="one layout")
  tree.dispose()
}

///|
test "a card at least 360 and at most 560 within its room: said, not read back" {
  let at : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(col) {
      at.val = Some(col.box(fn(c) {
        c.min_width_within(Is(Some(360.0))).max_width_within(Is(Some(560.0))).height(Is(Some(10.0))) |> ignore
      }))
    })
    |> ignore
  })
  tree.frame(300.0, 844.0) |> ignore
  // (a room of 300: the least is all of it, 300)
  assert_eq(at.val.unwrap().rect().2, 300.0)
  tree.frame(800.0, 844.0) |> ignore
  // (a room of 800: a column stretches it, at most 560)
  assert_eq(at.val.unwrap().rect().2, 560.0)
  tree.dispose()
}

///|
test "Laid::drawn: where another is drawn this frame, its drawn_off and scale counted, in the frame it moved in; Laid::at the frame's moment" {
  let off = @signals.signal(0.0)
  let at : Ref[(@view.View, @view.View)?] = Ref(None)
  let seen : Array[Double] = []
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(r) {
        let row = r.box(fn(c) {
          c
          .width(Is(Some(40.0)))
          .height(Is(Some(20.0)))
          .offset(Is((10.0, 100.0)))
          .drawn_off(By(fn() { (0.0, off.get()) }))
          |> ignore
        })
        let flyer = r.box(fn(g) {
          g.over(Is(true)).width(Is(Some(10.0))).height(Is(Some(10.0))) |> ignore
          // (on the row as it is drawn, wherever it is drawn off to)
          g.offset(
            Painted(fn(laid) {
              seen.push(laid.at())
              laid.drawn(row).map(fn(d) { (d.0, d.1) }).unwrap_or((0.0, 0.0))
            }),
          )
          |> ignore
        })
        at.val = Some((row, flyer))
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  let (_, flyer) = at.val.unwrap()
  assert_eq((flyer.rect().0, flyer.rect().1), (10.0, 100.0))
  let computes = tree.work().computes
  off.set(-30.0)
  tree.frame(390.0, 844.0, now=16.0) |> ignore
  assert_eq((flyer.rect().0, flyer.rect().1), (10.0, 70.0), msg="on the row as drawn off, the same frame")
  assert_eq(tree.work().computes - computes, 0, msg="nothing laid out")
  assert_eq(seen.last(), Some(16.0), msg="the frame's moment")
  tree.dispose()
}

///|
test "Layout::report: what a box's own layout says, read by what holds it as it measures it, in the same layout" {
  let lines = @signals.signal(1.0, same=fn(a, b) { a == b })
  let at : Ref[@view.NodeId?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(page) {
        page
        .width(Is(Some(300.0)))
        .height(Is(Some(400.0)))
        .layout_box(Is(()), fn(l, _) {
          let composer = l.child("composer", fn(c) {
            c.layout_box(By(fn() { lines.get() }), sized=true, fn(cl, n) {
              cl.report("cap", 10.0 + 30.0 * (n - 1.0))
              cl.size_to(20.0 * n + 16.0)
            })
            |> ignore
          })
          let note = l.child("note", fn(n) { at.val = Some(n.id()); n.width(Is(Some(10.0))).height(Is(Some(10.0))) |> ignore })
          let (_, ch) = l.measure(composer, l.width)
          l.measure(note, 10.0) |> ignore
          l.place(composer, 0.0, l.height - ch)
          // (by the cap the composer reported: over its last line's top)
          let cap = l.reported(composer, "cap").unwrap_or(0.0)
          l.place(note, 0.0, l.height - ch + cap - 10.0)
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  let note_y = fn() { tree.drawn_of(at.val.unwrap()).unwrap().y }
  let one = note_y()
  let computes = tree.work().computes
  lines.set(3.0)
  tree.frame(390.0, 844.0, now=16.0) |> ignore
  // (one line: 36 tall, cap 10, at 364 + 10 − 10; three: 76 tall, cap 70, at 324 + 70 − 10)
  assert_eq((one, note_y()), (364.0, 384.0))
  assert_eq(tree.work().computes - computes, 1, msg="one layout")
  tree.dispose()
}

///|
test "Roomed: a width worked out from how big a node holding it is laid out, layers down, in the same layout" {
  let wide = @signals.signal(400.0, same=fn(a, b) { a == b })
  let ids : Map[String, @view.NodeId] = {}
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(talk) {
        talk.width(By(fn() { Some(wide.get()) })).height(Is(Some(300.0))) |> ignore
        talk.box(fn(bar) {
          bar.row(Is(true)).padding(Is((8.0, 0.0, 8.0, 0.0))) |> ignore
          bar.box(fn(group) {
            group.grow(Is(1.0)) |> ignore
            group.box(fn(title) {
              ids["title"] = title.id()
              title.height(Is(Some(20.0))).width(Roomed(talk, fn(w, _) { Some(if 0.42 * w > 80.0 { 0.42 * w } else { 80.0 }) })) |> ignore
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(800.0, 600.0, now=0.0) |> ignore
  let w = fn() { tree.drawn_of(ids["title"]).unwrap().w }
  let at_400 = w()
  let computes = tree.work().computes
  wide.set(100.0)
  tree.frame(800.0, 600.0, now=16.0) |> ignore
  assert_eq((at_400, w()), (168.0, 80.0))
  assert_eq(tree.work().computes - computes, 1, msg="one layout")
  tree.dispose()
}

///|
test "opens_across: as wide as its share of what it holds, what it holds laid out whole, in one layout as the share changes" {
  let share = @signals.signal(Some(0.5), same=fn(a, b) { a == b })
  let ids : Map[String, @view.NodeId] = {}
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(row) {
        row.row(Is(true)).height(Is(Some(20.0))) |> ignore
        row.box(fn(cut) {
          ids["cut"] = cut.id()
          cut.opens_across(By(fn() { share.get() })).clips(Is(true)) |> ignore
          cut.box(fn(words) {
            ids["words"] = words.id()
            words.width(Is(Some(200.0))).height(Is(Some(20.0))) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(800.0, 600.0, now=0.0) |> ignore
  let ws = fn() { (tree.drawn_of(ids["cut"]).unwrap().w, tree.drawn_of(ids["words"]).unwrap().w) }
  let half = ws()
  let computes = tree.work().computes
  share.set(None)
  tree.frame(800.0, 600.0, now=16.0) |> ignore
  assert_eq((half, ws()), ((100.0, 200.0), (200.0, 200.0)))
  assert_eq(tree.work().computes - computes, 1, msg="one layout")
  tree.dispose()
}

///|
test "panic: Layout::reported read of a child not measured in the same layout aborts" {
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(page) {
      page
      .width(Is(Some(300.0)))
      .height(Is(Some(300.0)))
      .layout_box(Is(()), fn(l, _) {
        let c = l.child("c", fn(c) {
          c.layout_box(Is(()), sized=true, fn(cl, _) {
            cl.report("cap", 10.0)
            cl.size_to(20.0)
          })
          |> ignore
        })
        // (read before it is measured: what a layout before said, never this one's)
        l.reported(c, "cap") |> ignore
        l.measure(c, l.width) |> ignore
        l.place(c, 0.0, 0.0)
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
}

///|
test "drawn_each: a few nodes found where and in the order the scene's walk finds them, the tree not gone through" {
  // (a run of its own begun, as a Tester begins one: the panic test before it in this program stopped in a layout, its
  // guard said, @signals.reset_globals; nothing of it to let go here, what it told run at once, run_told)
  @signals.reset_globals()
  @signals.run_told()
  let ids : Array[@view.NodeId] = []
  let on = @signals.signal(true)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(a) {
        a.padding(Is((10.0, 20.0, 0.0, 0.0))).offset(Is((3.0, 4.0))) |> ignore
        a.box(fn(b) {
          ids.push(b.id())
          b.width(Is(Some(40.0))).height(Is(Some(20.0))).scale(Is(0.5)).drawn_off(Is((1.0, 2.0))) |> ignore
          b.box(fn(c) {
            ids.push(c.id())
            c.width(Is(Some(10.0))).height(Is(Some(10.0))).alpha(Is(0.5)) |> ignore
          })
          |> ignore
        })
        |> ignore
        a.show(fn() { on.get() }, fn(d) {
          ids.push(d.id())
          d.width(Is(Some(30.0))).height(Is(Some(30.0))) |> ignore
        })
      })
      |> ignore
      root.box(fn(e) {
        ids.push(e.id())
        e.over(Is(true)).stacked(Is(2)).width(Is(Some(50.0))).height(Is(Some(50.0))) |> ignore
      })
      |> ignore
      root.box(fn(f) {
        ids.push(f.id())
        f.width(Is(Some(5.0))).height(Is(Some(5.0))) |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.set_pixel_grid(2.0)
  tree.frame(400.0, 300.0) |> ignore
  let walked : Array[String] = []
  tree.each_drawn_laid(fn(c, x, y, a, s, ux, uy) {
    if ids.contains(c.id) {
      walked.push("\{c.id.at} \{x} \{y} \{a} \{s} \{ux} \{uy}")
    }
  })
  // (asked in another order than they are drawn)
  let asked = ids.copy()
  asked.rev_in_place()
  let found = tree.drawn_each(asked).map(fn(d) { "\{d.0.id.at} \{d.1} \{d.2} \{d.3} \{d.4} \{d.5} \{d.6}" })
  assert_eq(found, walked)
}
