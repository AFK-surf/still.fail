// A fake host supplies deliberately large glyphs to exercise the real atlas allocator. These are not pixel
// references: field_present_wbtest supplies recorded glyphs for the real renderers.

///|
test "a retained layer whose glyphs did not fit tells the host where they first become drawable" {
  let crowd = @signals.signal(0)
  let there = @signals.signal(false)
  let word = letters(0x6000, 4)
  let t = Tester::new(fn(_) { }, w=1000.0, h=500.0)
  t.check_looks(false)
  t.glyph_box(120.0, 120.0)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(100.0))) |> ignore
      old(h, fn(c) {
        let k = crowd.get()
        if k >= 0 { c.text(letters(0x4E00 + k * 64, 64), size=15.0, wrap=true) |> ignore }
      }).grow(Is(1.0)) |> ignore
    }) |> ignore
    root.show(fn() { there.get() }, fn(n) {
      n.over(Is(true)).offset(Is((600.0, 200.0))).width(Is(Some(200.0)))
        .words(Is(word), ink=0x333333FFL,
          look={ size: 15.0, weight: 400, line: 22.0, wrap: false, tracking: @view.letters_own, balance: false }) |> ignore
    })
    root.box(fn(n) {
      n.over(Is(true)).offset(Is((920.0, 20.0))).width(Is(Some(60.0))).height(Is(Some(60.0))).ground(Is(0x1559C4FFL)) |> ignore
    }) |> ignore
  })
  t.draw()
  t.measure_as_host()
  crowd.set(1)
  there.set(true)
  let at = t.time()
  // First no room; next the allocator starts over; still too much, so only the layer's retry remains.
  for ms in [20.0, 40.0, 60.0] { t.frame_at(at + ms) }
  assert_true(text_cache.short && text_cache.too_much, msg="sustained atlas pressure, past its first whole reset")
  assert_true(word.iter().any(fn(ch) { !text_cache.glyphs.contains(ch.to_int()) }), msg="some requested glyphs still cannot be drawn")
  let before = t.glyphs_shown().filter(fn(r) { r.0 >= 600.0 })
  t.record_host()
  crowd.set(-1)
  t.frame_at(at + 80.0)
  let frame = t.host_frames()[0]
  let after = t.glyphs_shown().filter(fn(r) { r.0 >= 600.0 })
  assert_eq(after.length(), 4, msg="the first frame with room draws every requested glyph")
  assert_true(after.length() > before.length(), msg="the retry adds previously missing drawing")
  assert_true(frame.changed)
  assert_true(after.iter().all(fn(r) { paint_damage_covers(frame, r) }), msg="the newly drawable glyphs reach h_present: \{frame}")
  assert_true(frame.damage.iter().all(fn(p) { p.2 >= 0.0 && p.0 + p.2 < 920.0 }), msg="the unrelated blue region remains kept: \{frame}")
  println("glyph retry: before \{before}, after \{after}, host \{frame}")
}

///|
test "the same text input at the same moments has the same drawing at 60 Hz, 120 Hz and a direct jump" {
  let pictures : Array[Array[Int64]] = []
  for hz in [0, 60, 120] {
    let f = Field::new(text="one\ntwo\nthree\nfour\nfive\n")
    let t = Tester::new(fn(_) { }, w=300.0, h=300.0, platform=2, text=paint_damage_text)
    set_view_app(fn(root) {
      root.box(fn(n) {
        n.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(200.0))) |> ignore
        field(n, f, font_size=16.0, line=24.0, min_lines=6, max_lines=6) |> ignore
      }) |> ignore
    })
    t.draw()
    f.focus()
    t.draw()
    t.measure_as_host()
    t.record_host()
    let at = t.time()
    let count = t.frames
    t.text_told("six", at)
    let hashes = []
    let mut tick = 1
    for elapsed in [20.0, caret_blink_ms * 1.5, caret_blink_ms * 2.5] {
      let target = at + elapsed
      if hz > 0 {
        while at + tick.to_double() * 1000.0 / hz.to_double() < target {
          t.frame_at(at + tick.to_double() * 1000.0 / hz.to_double())
          tick += 1
        }
      }
      t.frame_at(target)
      hashes.push(t.frame_hash())
    }
    let frames = t.host_frames()
    assert_eq(frames.length(), t.frames - count, msg="every actual frame is in this record")
    for frame in frames { if frame.changed { paint_damage_local(frame) } }
    assert_eq(f.text(), "one\ntwo\nthree\nfour\nfive\nsix")
    println("paint schedule \{hz} Hz (0: direct): actual frames \{frames.map(fn(f) { f.at })}")
    pictures.push(hashes)
  }
  assert_eq(pictures[1], pictures[0], msg="60 Hz and direct: the three target pictures")
  assert_eq(pictures[2], pictures[0], msg="120 Hz and direct: the three target pictures")
}

///|
test "a field redrawn and moved before its caret wakes erases its old places and repaints its current place" {
  let x = @signals.signal(20.0)
  let f = Field::new(text="word")
  let t = Tester::new(fn(_) { }, w=400.0, h=300.0, platform=2, text=paint_damage_text)
  set_view_app(fn(root) {
    root.box(fn(n) {
      n.over(Is(true)).offset(By(fn() { (x.get(), 20.0) })).width(Is(Some(100.0))) |> ignore
      field(n, f, font_size=16.0, line=24.0) |> ignore
    }) |> ignore
    root.box(fn(n) {
      n.over(Is(true)).offset(Is((320.0, 20.0))).width(Is(Some(60.0))).height(Is(Some(60.0))).ground(Is(0x1559C4FFL)) |> ignore
    }) |> ignore
  })
  t.draw()
  f.focus()
  t.draw()
  t.measure_as_host()
  t.record_host()
  let at = t.time()
  let mut before = t.glyphs_shown()
  for (x_to, ms) in [(80.0, 20.0), (140.0, 40.0)] {
    x.set(x_to)
    t.frame_at(at + ms)
    let frame = t.host_frames()[0]
    let after = t.glyphs_shown()
    assert_true(before.iter().all(fn(r) { paint_damage_covers(frame, r) }), msg="the intermediate old place erased: \{frame}")
    assert_true(after.iter().all(fn(r) { paint_damage_covers(frame, r) }), msg="the intermediate new place drawn: \{frame}")
    before = after
  }
  let wakes = scene.wakes.length()
  let work = scene.parts.work()
  t.frame_at(at + caret_blink_ms * 1.5)
  let frame = t.host_frames()[0]
  paint_damage_local(frame)
  assert_true(before.iter().all(fn(r) { paint_damage_covers(frame, r) }), msg="the wake covers the field at its latest position: \{frame}")
  println("wake after two moves: pending \{wakes}, damage work \{scene.parts.work() - work}, host \{frame}")
}
