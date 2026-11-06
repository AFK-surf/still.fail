// A list laid out first with no room to show anything in (a page pushed on, laid out before it is where it goes, its
// foot's room more than its height), then where it shows: its rows laid out then as if it had been there from the
// first, what it was asked to put put.

///|
fn late_case(put_first : (Int, Double)?, outer? : Bool = false) -> (@view.Tree, Map[Int, @view.View], @signals.Signal[Array[Int]], @signals.Signal[Double]) {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(100, fn(i) { i }), same=fn(a, b) { physical_equal(a, b) })
  let live : Map[Int, @view.View] = Map([])
  let shown : @signals.Signal[Array[Int]] = @signals.signal([], same=fn(a, b) { a == b })
  let put : @signals.Signal[(Int, Double)?] = @signals.signal(put_first)
  let tall = @signals.signal(0.0, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    let list = fn(o : @view.View) {
      o.scrolls_anchored(scroll, fn() { keys.get() }, est=80.0, ahead=0.0, shown~, put~, foot_room=fn() { 44.0 }, fn(b, k) {
        live[k] = b
        b.owns(fn() { live.remove(k) }) |> ignore
        b.height(Is(Some(40.0))) |> ignore
      })
      |> ignore
    }
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(By(fn() { Some(tall.get()) })) |> ignore
      // (its own room the same, the box it is in given its height: its room comes from where it is)
      if outer {
        o.box(fn(i) { i.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore; list(i) }) |> ignore
      } else {
        list(o)
      }
    })
    |> ignore
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  (tree, live, shown, tall)
}

///|
test "scrolls_anchored: laid out first where it has no room, then where it shows: its last rows in sight" {
  let (tree, live, shown, tall) = late_case(None)
  tall.set(144.0)
  tree.frame(390.0, 844.0, now=16.0) |> ignore
  assert_eq(shown.get(), [97, 98, 99])
  assert_true(live.length() >= 3)
}

///|
test "scrolls_anchored: put while it has no room yet, put once it shows" {
  let (tree, _, shown, tall) = late_case(Some((10, 0.0)))
  tall.set(144.0)
  tree.frame(390.0, 844.0, now=16.0) |> ignore
  assert_eq(shown.get(), [10, 11, 12])
}

///|
test "scrolls_anchored: its room given by the box it is in, nothing it reads changed: laid out again where it shows" {
  let (tree, _, shown, tall) = late_case(Some((10, 0.0)), outer=true)
  tall.set(144.0)
  tree.frame(390.0, 844.0, now=16.0) |> ignore
  assert_eq(shown.get(), [10, 11, 12])
}

///|
test "scrolls_anchored: the room under its rows given by what holds it as it measures it, a composer measured first: in sight as that leaves it, in the same layout" {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(100, fn(i) { i }), same=fn(a, b) { physical_equal(a, b) })
  let shown : @signals.Signal[Array[Int]] = @signals.signal([], same=fn(a, b) { a == b })
  let composer_h = @signals.signal(100.0, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(page) {
      page
      .width(Is(Some(300.0)))
      .height(Is(Some(300.0)))
      .layout_box(Is(()), fn(l, _) {
        let list = l.child("list", fn(o) {
          o.scrolls_anchored(scroll, fn() { keys.get() }, est=40.0, ahead=0.0, shown~, fn(b, _) {
            b.height(Is(Some(40.0))) |> ignore
          })
          |> ignore
        })
        let composer = l.child("composer", fn(c) { c.height(By(fn() { Some(composer_h.get()) })) |> ignore })
        let (_, ch) = l.measure(composer, l.width)
        l.measure(list, l.width, height=l.height, foot=(ch, ch)) |> ignore
        l.place(list, 0.0, 0.0)
        l.place(composer, 0.0, l.height - ch)
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  let tall = shown.get()
  let computes = tree.work().computes
  composer_h.set(20.0)
  tree.frame(390.0, 844.0, now=16.0) |> ignore
  assert_eq((tall, shown.get()), ([95, 96, 97, 98, 99], [93, 94, 95, 96, 97, 98, 99]))
  assert_eq(tree.work().computes - computes, 1, msg="one layout")
  tree.dispose()
}

///|
test "scrolls_anchored: a part of a row asked to the window's middle: put there where it lies further down than asked, in the layout that brings it in; left where it lies otherwise" {
  let case = fn(part : (Double, Double)) {
    let scroll = @view.Scroll::list()
    let keys = @signals.signal(Array::makei(100, fn(i) { i }), same=fn(a, b) { physical_equal(a, b) })
    let shown : @signals.Signal[Array[Int]] = @signals.signal([], same=fn(a, b) { a == b })
    let passage : @signals.Signal[(Int, String, Double)?] = @signals.signal(None)
    let tree = @view.Tree::new(fn(root) {
      root.box(fn(o) {
        o.width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
        o.scrolls_anchored(scroll, fn() { keys.get() }, est=300.0, ahead=0.0, shown~, put_passage=passage, fn(b, _) {
          b.layout_box(Is(()), sized=true, fn(l, _) {
            l.report_span("passage", part)
            l.size_to(300.0)
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    tree.frame(390.0, 844.0, now=0.0) |> ignore
    passage.set(Some((50, "passage", 0.8)))
    tree.frame(390.0, 844.0, now=16.0) |> ignore
    let at = shown.get()
    tree.dispose()
    at
  }
  // (its middle at 270 of 300, past 240: the row's top at 150 − 270, the next row in sight under it)
  assert_eq(case((250.0, 290.0)), [50, 51])
  // (its middle at 70: the row at the window's top, left there)
  assert_eq(case((60.0, 80.0)), [50])
}

///|
test "scrolls_anchored: a node kept in sight clear of what covers its foot, in the layout that cover grows in; not moved as it shrinks, nor as the hand has it, till kept again" {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(100, fn(i) { i }), same=fn(a, b) { physical_equal(a, b) })
  let cover = @signals.signal(20.0, same=fn(a, b) { a == b })
  let keeping = @signals.signal(false, same=fn(a, b) { a == b })
  let fields : Map[Int, @view.View] = Map([])
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(page) {
      page
      .width(Is(Some(300.0)))
      .height(Is(Some(300.0)))
      .layout_box(By(fn() { cover.get() }), fn(l, cover) {
        let list = l.child("list", fn(o) {
          o.scrolls_anchored(scroll, fn() { keys.get() }, est=40.0, ahead=0.0, fn(b, k) {
            b.height(Is(Some(40.0))) |> ignore
            b.box(fn(f) {
              f.height(Is(Some(20.0))) |> ignore
              fields[k] = f
            })
            |> ignore
          }, keep=fn() {
            if keeping.get() {
              fields.get(88).map(fn(f) { (f.id(), None, 16.0) })
            } else {
              None
            }
          })
          |> ignore
        })
        // (a composer over the list's foot: none of its rows laid out by it, only covered)
        l.measure(list, l.width, height=l.height, foot=(0.0, cover)) |> ignore
        l.place(list, 0.0, 0.0)
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  // (400 toward its start: row 88's field at 220..240, over the cover by 16 and more)
  tree.wheel_at(150.0, 50.0, 0.0, -400.0, 0, 16.0) |> ignore
  tree.frame(390.0, 844.0, now=32.0) |> ignore
  let field_y = fn() { fields[88].rect().1 }
  assert_eq(field_y(), 220.0)
  keeping.set(true)
  tree.frame(390.0, 844.0, now=48.0) |> ignore
  assert_eq(field_y(), 220.0, msg="between the covers: not moved")
  // (the cover grows to 100: the field's foot 16 over it, in that layout, laid out once)
  let computes = tree.work().computes
  cover.set(100.0)
  tree.frame(390.0, 844.0, now=64.0) |> ignore
  assert_eq(field_y(), 164.0)
  assert_eq(tree.work().computes - computes, 1, msg="one layout")
  // (it shrinks: not moved back)
  cover.set(20.0)
  tree.frame(390.0, 844.0, now=80.0) |> ignore
  assert_eq(field_y(), 164.0)
  // (the hand scrolls it 60 toward its start: the hand's, the cover growing again moves it no more)
  tree.wheel_at(150.0, 50.0, 0.0, -60.0, 0, 96.0) |> ignore
  tree.frame(390.0, 844.0, now=112.0) |> ignore
  assert_eq(field_y(), 224.0)
  cover.set(100.0)
  tree.frame(390.0, 844.0, now=128.0) |> ignore
  assert_eq(field_y(), 224.0, msg="the hand's: let go")
  // (let go and kept again: kept clear in that layout)
  keeping.set(false)
  tree.frame(390.0, 844.0, now=144.0) |> ignore
  keeping.set(true)
  tree.frame(390.0, 844.0, now=160.0) |> ignore
  assert_eq(field_y(), 164.0)
  // (a cover so tall the field fits under the top's room alone: its top first, 16 under the window's top)
  cover.set(290.0)
  tree.frame(390.0, 844.0, now=176.0) |> ignore
  assert_eq(field_y(), 16.0)
  tree.dispose()
}

///|
test "scrolls_anchored: a kept field that moves releases an earlier fractional placement" {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(100, fn(i) { i }), same=fn(a, b) { physical_equal(a, b) })
  let cover = @signals.signal(20.0, same=fn(a, b) { a == b })
  let keeping = @signals.signal(false, same=fn(a, b) { a == b })
  let fraction : @signals.Signal[(Int, Double, Double)?] = @signals.signal(Some((50, 0.0, 220.0)))
  let fields : Map[Int, @view.View] = Map([])
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(page) {
      page
      .width(Is(Some(300.0)))
      .height(Is(Some(300.0)))
      .layout_box(By(fn() { cover.get() }), fn(l, cover) {
        let list = l.child("list", fn(o) {
          o.scrolls_anchored(scroll, fn() { keys.get() }, est=40.0, ahead=0.0, put_fraction=fraction, fn(b, k) {
            b.height(Is(Some(40.0))) |> ignore
            b.box(fn(f) {
              f.height(Is(Some(20.0))) |> ignore
              fields[k] = f
            }) |> ignore
          }, keep=fn() {
            if keeping.get() { fields.get(50).map(fn(f) { (f.id(), None, 16.0) }) } else { None }
          }) |> ignore
        })
        l.measure(list, l.width, height=l.height, foot=(0.0, cover)) |> ignore
        l.place(list, 0.0, 0.0)
      }) |> ignore
    }) |> ignore
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  let field_y = fn() { fields[50].rect().1 }
  assert_eq(field_y(), 220.0, msg="fractional placement")
  keeping.set(true)
  cover.set(100.0)
  tree.frame(390.0, 844.0, now=16.0) |> ignore
  assert_eq(field_y(), 164.0, msg="kept clear of the larger cover")
  cover.set(20.0)
  tree.frame(390.0, 844.0, now=32.0) |> ignore
  assert_eq(field_y(), 164.0, msg="shrinking the cover does not restore the old fraction")
  keeping.set(false)
  tree.frame(390.0, 844.0, now=48.0) |> ignore
  assert_eq(field_y(), 164.0, msg="losing focus does not restore the old fraction")
  tree.dispose()
}

///|
test "scrolls_anchored from its start: a node kept in sight clear of what covers its foot, in the layout that cover grows in; not moved back as it shrinks" {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(100, fn(i) { i }), same=fn(a, b) { physical_equal(a, b) })
  let cover = @signals.signal(20.0, same=fn(a, b) { a == b })
  let keeping = @signals.signal(false, same=fn(a, b) { a == b })
  let fields : Map[Int, @view.View] = Map([])
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(page) {
      page
      .width(Is(Some(300.0)))
      .height(Is(Some(300.0)))
      .layout_box(By(fn() { cover.get() }), fn(l, cover) {
        let list = l.child("list", fn(o) {
          o.scrolls_anchored(scroll, fn() { keys.get() }, est=40.0, ahead=0.0, from_end=false, fn(b, k) {
            b.height(Is(Some(40.0))) |> ignore
            b.box(fn(f) {
              f.height(Is(Some(20.0))) |> ignore
              fields[k] = f
            })
            |> ignore
          }, keep=fn() {
            if keeping.get() { fields.get(5).map(fn(f) { (f.id(), None, 16.0) }) } else { None }
          })
          |> ignore
        })
        l.measure(list, l.width, height=l.height, foot=(0.0, cover)) |> ignore
        l.place(list, 0.0, 0.0)
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  // (row 5's field at 200..220, over the cover by 16 and more: not moved)
  let field_y = fn() { fields[5].rect().1 }
  assert_eq(field_y(), 200.0)
  keeping.set(true)
  tree.frame(390.0, 844.0, now=8.0) |> ignore
  assert_eq(field_y(), 200.0, msg="between the covers: not moved")
  // (the cover grows to 100: the field's foot 16 over it, in that layout, laid out once)
  let computes = tree.work().computes
  cover.set(100.0)
  tree.frame(390.0, 844.0, now=16.0) |> ignore
  assert_eq(field_y(), 164.0)
  assert_eq(tree.work().computes - computes, 1, msg="one layout")
  // (it shrinks: not moved back)
  cover.set(20.0)
  tree.frame(390.0, 844.0, now=32.0) |> ignore
  assert_eq(field_y(), 164.0)
  tree.dispose()
}

///|
test "scrolls_anchored: keeping a field above the top cover stops following the end" {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(100, fn(i) { i }), same=fn(a, b) { physical_equal(a, b) })
  let following = @signals.signal(true, same=fn(a, b) { a == b })
  let keeping = @signals.signal(false, same=fn(a, b) { a == b })
  let fields : Map[Int, @view.View] = Map([])
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(list) {
      list.width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
      list.scrolls_anchored(scroll, fn() { keys.get() }, est=40.0, ahead=0.0,
        follows=following, cover=fn() { 70.0 }, fn(b, k) {
          b.height(Is(Some(40.0))) |> ignore
          b.box(fn(f) {
            f.height(Is(Some(20.0))) |> ignore
            fields[k] = f
          }) |> ignore
        }, keep=fn() {
          if keeping.get() { fields.get(93).map(fn(f) { (f.id(), None, 16.0) }) } else { None }
        }) |> ignore
    }) |> ignore
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  assert_true(following.get(), msg="the list starts at its end")
  assert_eq(fields[93].rect().1, 20.0)
  keeping.set(true)
  tree.frame(390.0, 844.0, now=16.0) |> ignore
  assert_eq(fields[93].rect().1, 86.0, msg="the field is brought below the bar")
  assert_false(following.get(), msg="the moved list is no longer at its end")
  tree.dispose()
}

///|
test "scrolls_anchored: a kept field stops following after its parent measures twice" {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(100, fn(i) { i }), same=fn(a, b) { physical_equal(a, b) })
  let following = @signals.signal(true, same=fn(a, b) { a == b })
  let keeping = @signals.signal(false, same=fn(a, b) { a == b })
  let probing = @signals.signal(false, same=fn(a, b) { a == b })
  let fields : Map[Int, @view.View] = Map([])
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(300.0))).height(Is(Some(301.0))) |> ignore
      page.layout_box(By(fn() { probing.get() }), fn(l, probe) {
        let list = l.child("list", fn(list) {
          list.scrolls_anchored(scroll, fn() { keys.get() }, est=40.0, ahead=0.0,
            follows=following, cover=fn() { 70.0 }, fn(b, k) {
              b.height(Is(Some(40.0))) |> ignore
              b.box(fn(f) {
                f.height(Is(Some(20.0))) |> ignore
                fields[k] = f
              }) |> ignore
            }, keep=fn() {
              if keeping.get() { fields.get(93).map(fn(f) { (f.id(), None, 16.0) }) } else { None }
            }) |> ignore
        })
        if probe { l.measure(list, l.width, height=300.0) |> ignore }
        l.measure(list, l.width, height=301.0) |> ignore
        l.place(list, 0.0, 0.0)
      }) |> ignore
    }) |> ignore
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  assert_true(following.get())
  keeping.set(true)
  probing.set(true)
  tree.frame(390.0, 844.0, now=16.0) |> ignore
  assert_true(fields[93].rect().1 >= 86.0, msg="the field is clear of the bar")
  assert_false(following.get(), msg="the final layout is short of its end")
  tree.dispose()
}
