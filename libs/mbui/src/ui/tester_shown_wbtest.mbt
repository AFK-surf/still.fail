// Tester::run_shown: the clock run on with the frames a host draws on its way, the display's while the app asks for
// frames, none while it is at rest, one at what is due and at the end.

///|
/// A page's list of 30 rows whose keys `keys` says, its Tester: a key that comes at its foot makes its way there
/// (list_way_pixels_wbtest's).
fn shown_list(keys : @signals.Signal[Array[Int]]) -> Tester {
  let s = @view.Scroll::list()
  let t = Tester::new(fn(_c) {  }, w=300.0, h=400.0, platform=0, scale=2.0)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
      col.scrolls_window(s, fn() { keys.get() }, est=20.3, follows=fn() { true }, fn(b, k) {
        b.height(Is(Some(way_px_tall(k)))).ground(Is(way_px_ink(k))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "run_shown: the display's frames on its way while a row makes its way, none once it rests, one at the end" {
  let keys = @signals.signal(Array::makei(30, fn(i) { i }), same=fn(a, b) { a == b })
  let t = shown_list(keys)
  let at : Array[Double] = []
  t.each_frame(Some(fn() { at.push(t.time()) }))
  let from = t.time()
  let more = Array::makei(30, fn(i) { i })
  more.push(99)
  keys.set(more)
  let way = @flex.come_way_ms(0.0, 0.0, 33.3)
  let rest = 500.0
  t.run_shown(way + rest)
  t.each_frame(None)
  // (the last at the end, to the bit)
  assert_eq(at[at.length() - 1], from + way + rest)
  // (while the row was on its way: a frame a display's period apart at most, as many as the way is long)
  let on_way = at.filter(fn(m) { m <= from + way + 1.0e-6 })
  assert_true(
    on_way.length().to_double() >= (way / frame_period_default).floor(),
    msg="\{on_way.length()} frames on a way of \{way} ms: \{Repr(at)}",
  )
  let mut before = from
  for m in on_way {
    assert_true(m - before <= frame_period_default + 1.0e-6, msg="a frame \{m - before} ms after the one before: \{Repr(at)}")
    before = m
  }
  // (at rest after it: no frame a display's period after the way's end till the end's own)
  let after = at.filter(fn(m) { m > from + way + frame_period_default + 1.0e-6 })
  assert_eq(after, [from + way + rest])
}

///|
test "run_shown: an app at rest draws no frame on its way, but at the moment the outside says something next" {
  let keys = @signals.signal(Array::makei(30, fn(i) { i }), same=fn(a, b) { a == b })
  let t = shown_list(keys)
  let at : Array[Double] = []
  t.each_frame(Some(fn() { at.push(t.time()) }))
  let from = t.time()
  // (the outside's next at 437 ms on, off the display's frames: a key told then)
  let due = Ref(from + 437.0)
  t.between_frames(
    fn() {
      if t.time() >= due.val {
        due.val = @double.infinity
        came_from_outside()
        let more = Array::makei(30, fn(i) { i })
        more.push(99)
        keys.set(more)
      }
    },
    due=fn() { due.val },
  )
  let way = @flex.come_way_ms(0.0, 0.0, 33.3)
  t.run_shown(437.0 + way + 300.0)
  t.each_frame(None)
  t.between_frames(fn() {  })
  // (nothing before the outside's moment; a frame at it, to the bit; then the way's, a period apart at most)
  assert_eq(at.filter(fn(m) { m < from + 437.0 }), [])
  assert_eq(at[0], from + 437.0)
  let on_way = at.filter(fn(m) { m <= from + 437.0 + way + 1.0e-6 })
  assert_true(
    on_way.length().to_double() >= (way / frame_period_default).floor(),
    msg="\{on_way.length()} frames on a way of \{way} ms: \{Repr(at)}",
  )
  assert_eq(at[at.length() - 1], from + 437.0 + way + 300.0)
}
