// A page's list's foot declared to resize (View::resizes) on a host that sets its rows on its pixels, at 2.75 pixels a
// point, at its foot: closing 90 to 30 as a key 400 tall comes at its end, and opening 30 to 90 alone. On run_for's
// way, so at 60 and 120 a second judged frame by frame (MBUI_TEST_MOTION); at every frame each row's top on a pixel,
// each under the one before with no seam, the foot's top on a pixel, and where nothing comes the last row's foot at it.

///|
/// The ground of row `k`, and of the foot.
fn foot_rz_ink(k : Int) -> Int64 {
  0x40000000L + (k + 10).to_int64() * 0x100L + 0xFFL
}

///|
let foot_rz_foot_ink : Int64 = 0x40FFFFFFL

///|
/// How tall row `k` is: 20.3, but key 77, 400.
fn foot_rz_tall(k : Int) -> Double {
  if k == 77 {
    400.0
  } else {
    20.3
  }
}

///|
/// A list 300 by 300 of keys 0 to 29 following its foot, a foot `foot` tall, on a host setting its rows on its pixels
/// at 2.75 a point: the Tester, its keys, the foot's height and its box.
fn foot_rz_case(foot : Double) -> (Tester, @signals.Signal[Array[Int]], @signals.Signal[Double], Ref[@view.View?]) {
  let keys = @signals.signal(Array::makei(30, fn(i) { i }), same=fn(a, b) { a == b })
  let foot_h = @signals.signal(foot, same=fn(a, b) { a == b })
  let foot_box : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_c) {  }, w=300.0, h=400.0, platform=0, scale=2.75)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
      col.scrolls_window(
        @view.Scroll::list(),
        fn() { keys.get() },
        est=20.3,
        follows=fn() { true },
        foot=fn(f) {
          f.box(fn(b) {
            foot_box.val = Some(b)
            b.height(By(fn() { Some(foot_h.get()) })).shrink(Is(0.0)).ground(Is(foot_rz_foot_ink)) |> ignore
          })
          |> ignore
        },
        fn(b, k) { b.height(Is(Some(foot_rz_tall(k)))).ground(Is(foot_rz_ink(k))) |> ignore },
      )
      |> ignore
    })
    |> ignore
  })
  t.set_rows_on_pixels(true)
  t.draw()
  (t, keys, foot_h, foot_box)
}

///|
/// What is wrong as drawn now of rows `keys` and the foot: a row's top or the foot's off a pixel, a row under the one
/// before anywhere but where that one's slot ends, the last of `keys` (where `last_meets`) ending anywhere but at the
/// foot's top.
fn foot_rz_faults(t : Tester, keys : Array[Int], last_meets : Bool, at : String) -> Array[String] {
  let out = []
  let rects = t.drawn_rects()
  let rect = fn(ink : Int64) {
    match rects.search_by(fn(r) { r.4 == ink }) {
      Some(i) => Some((rects[i].1, rects[i].3))
      None => None
    }
  }
  let on_pixel = fn(v : Double) { (v * 2.75 - (v * 2.75).round()).abs() < 1.0e-6 }
  let foot_top = match rect(foot_rz_foot_ink) {
    Some((y, _)) => {
      if !on_pixel(y) {
        out.push("\{at}: the foot's top \{y} off a pixel")
      }
      y
    }
    None => {
      out.push("\{at}: no foot drawn")
      -1.0
    }
  }
  let mut before : (Int, Double, Double)? = None
  for k in keys {
    match rect(foot_rz_ink(k)) {
      Some((y, _)) => {
        if !on_pixel(y) {
          out.push("\{at}: row \{k}'s top \{y} off a pixel")
        }
        match before {
          Some((b, yb, hb)) if (y - yb - @view.rows_slot_on(hb, 2.75)).abs() > 1.0e-6 =>
            out.push("\{at}: row \{k} at \{y} under row \{b} at \{yb}")
          _ => ()
        }
        before = Some((k, y, foot_rz_tall(k)))
      }
      None => before = None
    }
  }
  if last_meets {
    match (keys.last(), before) {
      (Some(l), Some((k, y, h))) if k == l && (y + @view.rows_slot_on(h, 2.75) - foot_top).abs() > 1.0e-6 =>
        out.push("\{at}: row \{l} ends at \{y + @view.rows_slot_on(h, 2.75)}, the foot's top at \{foot_top}")
      _ => ()
    }
  }
  out
}

///|
test "a page's list on a host's pixels, its foot declared closing 90 to 30 as a key 400 tall comes at its end, and opening 30 to 90 alone: at its foot, steady frame by frame, each row's top and the foot's on a pixel, no seam, the last row's foot at the foot's top where nothing comes" {
  let faults = []
  // (closing as a key 400 tall comes)
  let (t, keys, foot, foot_box) = foot_rz_case(90.0)
  let came = Array::makei(30, fn(i) { i })
  came.push(77)
  t.each_frame(Some(fn() { faults.append(foot_rz_faults(t, came, false, "closing at \{t.time()}")) }))
  view_event(fn() {
    foot_box.val.unwrap().resizes() |> ignore
    foot.set(30.0)
    keys.set(came)
  })
  t.run_for(move_most_ms + 100.0)
  t.each_frame(None)
  faults.append(foot_rz_faults(t, came, true, "closed"))
  // (opening alone)
  let (t, _, foot, foot_box) = foot_rz_case(30.0)
  let ks = Array::makei(30, fn(i) { i })
  t.each_frame(Some(fn() { faults.append(foot_rz_faults(t, ks, true, "opening at \{t.time()}")) }))
  view_event(fn() {
    foot_box.val.unwrap().resizes() |> ignore
    foot.set(90.0)
  })
  t.run_for(move_most_ms + 100.0)
  t.each_frame(None)
  faults.append(foot_rz_faults(t, ks, true, "opened"))
  assert_eq(faults, [])
}
