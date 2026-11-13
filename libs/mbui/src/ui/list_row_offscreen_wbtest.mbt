// A paint-only signal is changed inside an offscreen frame after the row has already been painted. Compare the host
// requests and resulting drawing with the same list built each frame, so the row's paint watch cannot hide a change.

///|
fn row_offscreen_result(keep : Bool) -> (Bool, Double, Bool, Bool, Bool) raise {
  let ink = @signals.signal(0xCC6633FFL)
  let change = Ref(false)
  let changed = Ref(false)
  let rows : ListRows[Int] = ListRows::new()
  let view = fn(c : Ctx) {
    if change.val {
      change.val = false
      changed.val = true
      ink.set(0x229944FFL)
    }
    let ids = Array::makei(30, fn(i) { i })
    let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
    c.list("rows", items.length(), 40.0, fn(k) {
      let item = items[k]
      let n = c.box(h=Px(40.0), bg=0x224466FFL, fn() {  })
      if item == 2 {
        c.bg_by(n, fn() { ink.get() })
      }
    }, rows_read=true, sized=rows.sized()) |> ignore
  }
  let t = Tester::new(view, w=300.0, h=160.0)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.drawn_again(keep)
  t.draw()
  t.frame_at(t.time() + 16.0)
  let mut cached = false
  for _, rn in kept_nodes {
    if rn.item == 2 {
      match rn.drawing {
        Some(d) if d.valid && !d.watch.is_stale() => cached = true
        _ => ()
      }
    }
  }
  assert_eq(cached, keep, msg="the comparison must start with the requested paint-cache mode")
  change.val = true
  t.stepped()
  t.fake.wants = false
  let wake = t.fake.wake
  frame_offscreen(view, 300.0, 160.0, 1.0, t.time() + 8.0) |> ignore
  assert_true(changed.val, msg="the signal was set inside the offscreen frame")
  let wants = t.fake.wants
  let after_wake = t.fake.wake
  let offscreen_shows = t.drawn_rects().iter().any(fn(r) { r.4 == 0x229944FFL })
  t.frame_at(t.time() + 16.0)
  let display_shows = t.drawn_rects().iter().any(fn(r) { r.4 == 0x229944FFL })
  (wants, after_wake - wake, offscreen_shows, display_shows, cached)
}

///|
test "a row paint change in an offscreen frame has the same host requests and drawing with and without a cache" {
  let cached = row_offscreen_result(true)
  let rebuilt = row_offscreen_result(false)
  println("ROW_OFFSCREEN cached=\{Repr(cached)} rebuilt=\{Repr(rebuilt)}")
  assert_eq((cached.0, cached.1), (rebuilt.0, rebuilt.1), msg="host requests differ between the same frames")
  assert_true(cached.2 && cached.3 && rebuilt.2 && rebuilt.3, msg="both offscreen and subsequent display frames must show the new color")
}
