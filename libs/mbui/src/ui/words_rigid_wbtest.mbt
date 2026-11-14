// Words are rigid in the box they are in (scene.mbt on_glyph_row): a page's list's row put on the pixels, moved by whole
// pixels, draws its words as many pixels under its top wherever it is, drawn anew there or as it was kept, moved, at
// every scale of pixels a point and whether the host keeps groups of instances or not. Rounded as one sum with the
// row's top, a baseline half way between two pixels went to either by the float bits of the top: at 2.75 a point, a row
// of words 44 tall had them 15 pixels under its top in one place and 16 in another. So too words in a box of their own
// in the row, its top off the pixels (under a padding: flex puts only a list's rows on them).

///|
/// Key `k`'s row's ground, its own.
fn rigid_ground(k : Int) -> Int64 {
  0x50000000L + (k + 10).to_int64() * 0x100L + 0xFFL
}

///|
/// A page's list 300 tall of 30 rows 44 tall, each its words on a ground of its own, on `sc` pixels a point, its rows on
/// them, the host keeping groups of instances or not; scrolled to `to`. Where `padded`, each row's words in a box of their
/// own under a top padding of its own, 1 to 12 points (rigid_pad).
fn rigid_list(sc : Double, groups : Bool, at : @view.Scroll, padded? : Bool = false) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=400.0, platform=0, scale=sc)
  t.set_rows_on_pixels(true)
  t.set_groups(groups)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
      col.scrolls_window(at, fn() { Array::makei(30, fn(i) { i }) }, est=44.0, fn(b, k) {
        b.box(fn(r) {
          r.height(Is(Some(44.0))).ground(Is(rigid_ground(k))) |> ignore
          if padded {
            r.padding(Is((0.0, rigid_pad(k), 0.0, 0.0))) |> ignore
            r.box(fn(w) { w.words(Is("row \{k}: its words")) |> ignore }) |> ignore
          } else {
            r.words(Is("row \{k}: its words")) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
/// The top padding over key `k`'s row's words where they are in a box of their own: 1 to 12 points, by its key.
fn rigid_pad(k : Int) -> Double {
  (1 + k % 12).to_double()
}

///|
/// Key `k`'s row as drawn now: where its top is, in device pixels, and how many device pixels under it each of its
/// glyphs' pictures is (to a millionth of one); none where it is not drawn.
fn rigid_row(t : Tester, k : Int, sc : Double) -> (Double, Array[Double])? {
  guard t.drawn_rects().iter().find_first(fn(r) { r.4 == rigid_ground(k) }) is Some(g) else { return None }
  let top = g.1
  let under : Array[Double] = []
  for a in t.drawn_instances() {
    // (a glyph's picture, kind 1, within the row's band)
    if a[5] == 1.0 && a[2] < 40.0 && a[1] >= top && a[1] + a[3] <= top + 44.0 {
      under.push(((a[1] - top) * sc * 1.0e6).round() / 1.0e6)
    }
  }
  Some(((top * sc * 1.0e6).round() / 1.0e6, under))
}

///|
test "a page's list's row moved by whole pixels: its words as many pixels under its top wherever it is, drawn anew there or kept, moved, at 1.25, 1.5, 2, 2.75, 3 and 3.5 pixels a point, the host keeping groups or not" {
  let faults = []
  for sc in [1.25, 1.5, 2.0, 2.75, 3.0, 3.5] {
    for groups in [true, false] {
      // (scrolled a pixel at a time over 48: the third row, 88 down, each of those pixels higher)
      let ks = Array::makei(48, fn(i) { i })
      let anew : Array[Array[Double]] = []
      for k in ks {
        let at = @view.Scroll::list()
        at.put(k.to_double() / sc)
        match rigid_row(rigid_list(sc, groups, at), 2, sc) {
          Some((_, under)) => anew.push(under)
          None => faults.push("\{sc} groups \{groups}: the third row not drawn at \{k} pixels")
        }
      }
      let kept : Array[Array[Double]] = []
      let at = @view.Scroll::list()
      let t = rigid_list(sc, groups, at)
      for k in ks {
        at.put(k.to_double() / sc)
        t.draw()
        match rigid_row(t, 2, sc) {
          Some((_, under)) => kept.push(under)
          None => faults.push("\{sc} groups \{groups}: the third row not drawn at \{k} pixels, kept")
        }
      }
      for i in 0..<anew.length() {
        if anew[i] != anew[0] {
          faults.push("\{sc} groups \{groups}: drawn anew \{i} pixels on, its glyphs \{Repr(anew[i])} pixels under its top, at 0 \{Repr(anew[0])}")
          break
        }
      }
      for i in 0..<kept.length() {
        if kept[i] != anew[0] {
          faults.push("\{sc} groups \{groups}: scrolled \{i} pixels on, its glyphs \{Repr(kept[i])} pixels under its top, drawn anew \{Repr(anew[0])}")
          break
        }
      }
    }
  }
  assert_eq(faults, [])
}

///|
/// The row measured (a list's bench scene, 44 tall rows of words): its baseline about 15.5 pixels under its top on
/// 2.75 a point, the row at 40 points (110 pixels) and at 45.0909 (124): its words as far under its top at both.
test "a row of words 44 tall on 2.75 pixels a point, the host keeping no groups: at 40 and at 45.0909 points its words as far under its top" {
  let sc = 2.75
  let unders = []
  // (the third row, 88 down: scrolled 48 and 42.909 points, 132 and 118 pixels)
  for to in [48.0, 118.0 / sc] {
    let at = @view.Scroll::list()
    at.put(to)
    match rigid_row(rigid_list(sc, false, at), 2, sc) {
      Some((top, under)) => {
        println("words_rigid: the row at \{top} pixels, its glyphs \{Repr(under)} under its top")
        unders.push(under)
      }
      None => fail("the third row not drawn scrolled to \{to}")
    }
  }
  assert_eq(unders[1], unders[0])
}

///|
test "rows whose words are in a box under a top padding of 1 to 12 points, moved by whole pixels: each row's words as many pixels under its top wherever it is, drawn anew there or kept, moved, at 1.25, 1.5, 2, 2.75, 3 and 3.5 pixels a point, the host keeping groups or not" {
  let faults = []
  for sc in [1.25, 1.5, 2.0, 2.75, 3.0, 3.5] {
    for groups in [true, false] {
      let ks = Array::makei(48, fn(i) { i })
      // (each row by its key: its glyphs under its top, as first seen; then each time it is drawn, anew or kept)
      let seen : Map[Int, Array[Double]] = Map([])
      let differs : Map[Int, String] = Map([])
      let look = fn(t : Tester, k : Int, how : String) {
        for key in 0..<30 {
          match rigid_row(t, key, sc) {
            Some((_, under)) if under.length() > 0 =>
              match seen.get(key) {
                None => seen[key] = under
                Some(was) =>
                  if was != under && !differs.contains(key) {
                    differs[key] = "\{how} \{k} pixels on \{Repr(under)}, before \{Repr(was)}"
                  }
              }
            _ => ()
          }
        }
      }
      for k in ks {
        let at = @view.Scroll::list()
        at.put(k.to_double() / sc)
        look(rigid_list(sc, groups, at, padded=true), k, "drawn anew")
      }
      let at = @view.Scroll::list()
      let t = rigid_list(sc, groups, at, padded=true)
      for k in ks {
        at.put(k.to_double() / sc)
        t.draw()
        look(t, k, "kept")
      }
      for key, d in differs {
        faults.push("\{sc} groups \{groups}: row \{key} (padding \{rigid_pad(key)}): \{d}")
      }
    }
  }
  assert_eq(faults, [])
}
