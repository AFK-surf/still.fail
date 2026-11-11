// A page's list's rows on a host's pixels (Tree::set_rows_grid; flex's Style rows_grid): every row's top and height the
// grid's own number for a whole device pixel, bit for bit, not a hair either side of one, at a scale that is no whole
// number (2.75, 3.5), with what is added down the list (its gap, the rows' margins, its padding) no whole number of
// pixels as said; so a row is placed the same, to the bit, however the list came to where it is. On main alone a windowed list's rows are laid
// out from its top in one order every time, so the three ways below come out the same there too: they hold it for the
// list whose slots are kept only near what shows, where the rows are added from where its slots start.

///|
/// How tall key `k`'s row is: no binary fraction, and no whole number of pixels at either scale.
fn grid_tall(k : Int) -> Double {
  match k % 3 {
    0 => 40.0 * 1.3
    1 => 51.7
    _ => 63.1
  }
}

///|
/// Whether `v` is the grid's own number for its pixel: the same double, bit for bit, as that pixel put back on the grid
/// of `g` pixels a point (one number for each pixel, however it was come to; times a scale that is no power of two it
/// need not come back as the whole number itself, so it is not asked to), and that pixel within far less than half of
/// one of it.
fn grid_whole(v : Double, g : Double) -> Bool {
  let p = v * g
  v.reinterpret_as_int64() == ((p.round() / g).reinterpret_as_int64()) && (p - p.round()).abs() < 0.000001
}

///|
/// Whether `v` is within far less than half a pixel of a whole one on the grid of `g` pixels a point: a place drawn,
/// worked out of two numbers on the grid (a row's top and where its list is moved to), no one double of the grid's.
fn grid_near(v : Double, g : Double) -> Bool {
  let p = v * g
  (p - p.round()).abs() < 0.000001
}

///|
test "a page's list on 2.75 and 3.5 pixels a point, its gap, margins and padding no whole pixels: each row's top and height the grid's own number for a pixel, the room between rows the same" {
  for g in [2.75, 3.5] {
    let rows : Array[View] = []
    let tree = Tree::new(fn(root) {
      root.box(fn(o) {
        o.width(Is(Some(300.0))).height(Is(Some(400.0))) |> ignore
        o.scrolls(Scroll::list(), fn(held) {
          held.padding(Is((0.0, 3.3, 0.0, 0.0))).gap(Is(6.0)) |> ignore
          held.each(fn() { Array::makei(40, fn(i) { i }) }, fn(k) { k }, fn(r, item) {
            let k = item.untracked()
            r.height(Is(Some(grid_tall(k)))).margin(Is((0.0, 5.0, 0.0, 2.5))) |> ignore
            rows.push(r)
          }, at_once=true)
        })
        |> ignore
      })
      |> ignore
    })
    tree.set_rows_grid(g)
    tree.frame(390.0, 844.0) |> ignore
    let off = []
    let rooms = []
    for i, r in rows {
      let n = tree.nodes[r.at].flex
      if !grid_whole(n.top, g) || !grid_whole(n.height, g) {
        off.push((n.top * g, n.height * g))
      }
      // (the room between one row and the next, in pixels: the same everywhere)
      if i + 1 < rows.length() {
        let m = tree.nodes[rows[i + 1].at].flex
        let room = ((m.top - (n.top + n.height)) * g).round()
        if !rooms.contains(room) {
          rooms.push(room)
        }
      }
    }
    assert_eq(off, [], msg="on \{g} pixels a point, rows' top and height in pixels: \{Repr(off)}")
    assert_eq(rooms.length(), 1, msg="on \{g} pixels a point, the room between rows in pixels: \{Repr(rooms)}")
  }
}

///|
/// A windowed list of 300 keys on `g` pixels a point (0: none) brought to `at` after all its rows are measured in the
/// order `way` says ("down": from its top down; "up": from its foot up; "asked": each asked to its top in a shuffled
/// order, then down); each row in sight's key, its top as laid out (its slot's, in the column) and as drawn (its
/// block's, in the window), and whether its slot's top and height are whole pixels.
fn grid_window_at(g : Double, way : String, at : Double) -> Array[(Int, Double, Double, Bool)] {
  let scroll = Scroll::list()
  let place : ListPlace[Int] = ListPlace::new()
  let live : Map[Int, View] = Map([])
  let tree = Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      o.scrolls_window(scroll, fn() { Array::makei(300, fn(i) { i }) }, est=80.0, place~, fn(b, k) {
        live[k] = b
        b.owns(fn() { live.remove(k) }) |> ignore
        b.height(Is(Some(grid_tall(k)))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.set_rows_grid(g)
  tree.frame(390.0, 844.0) |> ignore
  let through = fn(dy : Double) {
    let mut n = 0
    while n < 1000 {
      let was = scroll.at(tree)
      tree.wheel_at(150.0, 50.0, 0.0, dy, 0, 10.0) |> ignore
      tree.frame(390.0, 844.0) |> ignore
      n = n + 1
      if scroll.at(tree) == was {
        break
      }
    }
  }
  match way {
    "down" => through(90.0)
    "up" => {
      place.to_end(glide=false)
      tree.frame(390.0, 844.0) |> ignore
      through(-90.0)
    }
    _ => {
      // (each a cause of its own, the frame after it drawn: brought to its top in this order)
      for k in Array::makei(300, fn(i) { i * 7919 % 300 }) {
        place.bring(k)
        tree.frame(390.0, 844.0) |> ignore
      }
      place.bring(0)
      tree.frame(390.0, 844.0) |> ignore
      through(90.0)
    }
  }
  scroll.put(at)
  tree.frame(390.0, 844.0) |> ignore
  let ks = live.keys().collect()
  ks.sort()
  ks.filter_map(fn(k) {
    let b = live[k]
    guard b.parent().bind(fn(p) { p.parent() }) is Some(slot) else { return None }
    let n = tree.nodes[slot.at].flex
    let (_, drawn, _) = tree.placed(b.at)
    if drawn + n.height > 0.0 && drawn < 100.0 {
      Some((k, n.top, drawn, g == 0.0 || (grid_whole(n.top, g) && grid_whole(n.height, g) && grid_near(drawn, g))))
    } else {
      None
    }
  })
}

///|
test "a windowed list on 2.75 and 3.5 pixels a point, at the same place come to three ways (its rows measured top down, foot up, asked in a shuffled order): each row in sight laid out and drawn the same to the bit, on whole pixels" {
  for g in [2.75, 3.5] {
    for at in [130.37, 1000.0, 7777.77, 8001.25, 15000.5] {
      let down = grid_window_at(g, "down", at)
      let up = grid_window_at(g, "up", at)
      let asked = grid_window_at(g, "asked", at)
      let bits = fn(rows : Array[(Int, Double, Double, Bool)]) {
        rows.map(fn(r) { (r.0, r.1.reinterpret_as_int64(), r.2.reinterpret_as_int64(), r.3) })
      }
      assert_true(down.length() > 0, msg="nothing in sight at \{at}")
      assert_eq(bits(up), bits(down), msg="on \{g} at \{at}: from its foot \{Repr(up)}, from its top \{Repr(down)}")
      assert_eq(bits(asked), bits(down), msg="on \{g} at \{at}: asked \{Repr(asked)}, from its top \{Repr(down)}")
      assert_eq(down.filter(fn(r) { !r.3 }), [], msg="on \{g} at \{at}: rows not on whole pixels: \{Repr(down.map(fn(r) { (r.0, r.1 * g, r.2 * g) }))}")
    }
  }
}
