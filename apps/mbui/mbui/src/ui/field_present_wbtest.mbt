// The draw list and the parts actually sent to the host must describe the same change. These frames can also be
// drawn by a real renderer (scripts/render_paint_damage.sh): each partial frame must equal its whole rendering.

///|
fn paint_damage_print(t : Tester, name : String) -> Unit {
  if @env.get_env_var("MBUI_PAINT_DAMAGE_PRINT").unwrap_or("") == "1" {
    println("DLBEGIN \{name}")
    println(t.drawlist())
    // Read what h_present handed the host, including an empty region. scene_parts() keeps the last nonempty set.
    let parts = host_parts_last.val.0
    if parts.is_empty() {
      println("parts none")
    }
    for (x, y, w, h) in parts {
      if w < 0.0 { println("parts all") }
      else { println("parts \{x} \{y} \{w} \{h}") }
    }
    println("DLEND")
  }
}

///|
fn paint_damage_covers(frame : HostFrame, r : (Double, Double, Double, Double)) -> Bool {
  frame.damage.iter().any(fn(p) {
    p.2 < 0.0 || (p.0 <= r.0 && p.1 <= r.1 && p.0 + p.2 >= r.2 && p.1 + p.3 >= r.3)
  })
}

///|
fn paint_damage_local(frame : HostFrame) -> Unit raise {
  assert_true(frame.changed, msg="the drawing changed: \{frame}")
  assert_false(frame.damage.is_empty(), msg="the host must draw the change: \{frame}")
  assert_true(frame.damage.iter().all(fn(p) { p.2 >= 0.0 && p.0 + p.2 < 280.0 }),
    msg="the unchanged right edge is kept, not covered by a whole frame: \{frame}")
}

///|
test "typing into an existing line tells the host to redraw the changed text" {
  let f = Field::new(text="one\ntwo\nthree\nfour\nfive\n")
  let t = Tester::new(fn(_c) { }, w=300.0, h=300.0, platform=2, text=paint_damage_text())
  set_view_app(fn(root) {
    root.box(fn(box) {
      box.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(200.0))) |> ignore
      field(box, f, font_size=16.0, line=24.0, min_lines=6, max_lines=6) |> ignore
    }) |> ignore
  })
  t.draw()
  g().focus_field(f)
  t.draw()
  t.measure_as_host()
  t.record_host()
  paint_damage_print(t, "typing-before")
  let at = t.time()
  t.text_told("six", at)
  t.frame_at(at + 1000.0 / 60.0)
  paint_damage_print(t, "typing-after")
  assert_eq(f.text(), "one\ntwo\nthree\nfour\nfive\nsix")
  assert_true(t.text_runs().iter().any(fn(r) { r.text == "six" }), msg="the sixth line is in the draw list")
  let frames = t.host_frames()
  assert_true(frames.length() > 0, msg="the host received a frame")
  assert_true(frames.iter().any(fn(frame) { frame.changed }), msg="the host replaced the frame")
  for frame in frames {
    if frame.changed {
      paint_damage_local(frame)
      assert_true(frame.damage.iter().any(fn(p) {
        p.2 < 0.0 || (p.0 <= 20.0 && p.1 <= 140.0 && p.0 + p.2 >= 40.0 && p.1 + p.3 >= 160.0)
      }), msg="the changed sixth line must reach the host's redraw area: \{frame}")
    }
  }
}

///|
test "a retained field's timed caret redraws where it disappears and appears" {
  let f = Field::new()
  let t = Tester::new(fn(_c) { }, w=300.0, h=300.0, platform=2, text=paint_damage_text())
  set_view_app(fn(root) {
    root.ground(Is(0xF5F5F7FFL)) |> ignore
    // A stationary layer keeps the caret-hidden draw list renderable, too; the root's ground is the clear colour.
    root.box(fn(still) {
      still.over(Is(true)).offset(Is((250.0, 250.0))).width(Is(Some(20.0))).height(Is(Some(20.0)))
        .ground(Is(0x1559C4FFL)) |> ignore
    }) |> ignore
    root.box(fn(box) {
      box.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(200.0))) |> ignore
      field(box, f, font_size=16.0, line=24.0) |> ignore
    }) |> ignore
  })
  t.draw()
  g().focus_field(f)
  t.draw()
  t.measure_as_host()
  t.record_host()
  let at = t.time()
  let shown = t.frame_hash()
  paint_damage_print(t, "caret-before")
  t.frame_at(at + caret_blink_ms * 1.5)
  paint_damage_print(t, "caret-hidden")
  assert_true(t.frame_hash() != shown, msg="the caret disappeared")
  t.frame_at(at + caret_blink_ms * 2.5)
  paint_damage_print(t, "caret-shown")
  assert_eq(t.frame_hash(), shown, msg="the caret appeared again")
  let frames = t.host_frames()
  assert_eq(frames.length(), 2)
  for frame in frames {
    paint_damage_local(frame)
    assert_true(frame.changed && frame.damage.iter().any(fn(p) {
      p.2 < 0.0 || (p.0 <= 20.0 && p.1 <= 20.0 && p.0 + p.2 >= 21.0 && p.1 + p.3 >= 40.0)
    }), msg="the caret's change must reach the host's redraw area: \{frame}")
  }
}

///|
test "paint invalidation covers a field moved, shrunk, removed and first shown, preserving an unrelated layer" {
  let x = @signals.signal(20.0)
  let width = @signals.signal(120.0)
  let shown = @signals.signal(true)
  let f = Field::new(text="word")
  let t = Tester::new(fn(_c) { }, w=400.0, h=300.0, platform=2, text=paint_damage_text())
  set_view_app(fn(root) {
    root.box(fn(still) {
      still.over(Is(true)).offset(Is((320.0, 20.0))).width(Is(Some(60.0))).height(Is(Some(60.0)))
        .ground(Is(0x1559C4FFL)) |> ignore
    }) |> ignore
    root.show(fn() { shown.get() }, fn(slot) {
      slot.over(Is(true)).offset(By(fn() { (x.get(), 20.0) })).width(By(fn() { Some(width.get()) })) |> ignore
      field(slot, f, font_size=16.0, line=24.0) |> ignore
    })
  })
  t.draw()
  f.focus()
  t.draw()
  t.measure_as_host()
  t.record_host()
  paint_damage_print(t, "regions-before")
  let before = t.glyphs_shown()
  let at = t.time()
  x.set(100.0)
  t.text_told("x", at)
  t.frame_at(at + 20.0)
  paint_damage_print(t, "regions-moved")
  let moved = t.glyphs_shown()
  width.set(70.0)
  t.text_told("y", at + 20.0)
  t.frame_at(at + 40.0)
  paint_damage_print(t, "regions-shrunk")
  let shrunk = t.glyphs_shown()
  shown.set(false)
  t.frame_at(at + 60.0)
  paint_damage_print(t, "regions-gone")
  shown.set(true)
  t.frame_at(at + 80.0)
  paint_damage_print(t, "regions-new")
  let frames = t.host_frames()
  assert_eq(frames.length(), 4)
  for frame in frames { paint_damage_local(frame) }
  assert_false(before.is_empty())
  assert_true(before.iter().all(fn(r) { paint_damage_covers(frames[0], r) }), msg="the old field's words erased")
  assert_true(moved.iter().all(fn(r) { paint_damage_covers(frames[0], r) }), msg="the field drawn at its new place")
  assert_true(shrunk.iter().all(fn(r) { paint_damage_covers(frames[2], r) }), msg="the removed field erased")
  assert_true(t.glyphs_shown().iter().all(fn(r) { paint_damage_covers(frames[3], r) }), msg="a new field without an old reach drawn")
  assert_eq(t.drawn_rects().filter(fn(r) { r.4 == 0x1559C4FFL }), [(320.0, 20.0, 60.0, 60.0, 0x1559C4FFL)])
}

///|
fn paint_damage_under(glass : Bool) -> Unit raise {
  let f = Field::new(text="one\ntwo\nthree\nfour\nfive\n")
  let t = Tester::new(fn(_c) { }, w=400.0, h=300.0, platform=2, scale=2.0, text=paint_damage_text())
  set_view_app(fn(root) {
    root.box(fn(outer) {
      outer.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(200.0))).height(Is(Some(180.0)))
        .clips(Is(true)).radius(Is(12.0)) |> ignore
      outer.box(fn(inner) {
        inner.over(Is(true)).offset(Is((10.0, 10.0))).width(Is(Some(170.0))).height(Is(Some(150.0)))
          .clips(Is(true)).radius(Is(8.0)) |> ignore
        field(inner, f, font_size=16.0, line=24.0, min_lines=6, max_lines=6) |> ignore
      }) |> ignore
    }) |> ignore
    if glass {
      root.box(fn(g) {
        g.over(Is(true)).offset(Is((20.0, 145.0))).width(Is(Some(170.0))).height(Is(Some(40.0)))
          .radius(Is(12.0)).glass(Is(Some(Glass::frosted(blur=4.0, tint=0xFFFFFF40L, solid=0xFFFFFFFFL)))) |> ignore
      }) |> ignore
    }
    root.box(fn(still) {
      still.over(Is(true)).offset(Is((320.0, 20.0))).width(Is(Some(60.0))).height(Is(Some(60.0)))
        .ground(Is(0x1559C4FFL)) |> ignore
    }) |> ignore
  })
  t.draw()
  f.focus()
  t.draw()
  t.measure_as_host()
  t.record_host()
  let name = if glass { "glass" } else { "clips" }
  paint_damage_print(t, name + "-before")
  let at = t.time()
  t.text_told("six", at)
  t.frame_at(at + 20.0)
  paint_damage_print(t, name + "-after")
  let frame = t.host_frames()[0]
  paint_damage_local(frame)
  assert_true(paint_damage_covers(frame, (30.0, 150.0, 50.0, 170.0)), msg="changed text inside nested clips: \{frame}")
  if glass {
    assert_true(frame.glass > 0.0, msg="the changed text's blur must be captured again: \{frame}")
    assert_true(paint_damage_covers(frame, (20.0, 145.0, 190.0, 185.0)), msg="the whole glass captured: \{frame}")
  } else {
    assert_true(frame.damage.iter().all(fn(p) { p.0 >= 18.0 && p.1 >= 18.0 && p.0 + p.2 <= 222.0 && p.1 + p.3 <= 202.0 }),
      msg="damage stays inside the outer clip, allowing the raster edge: \{frame}")
  }
}

///|
test "paint invalidation reaches the host through nested rounded clips" {
  paint_damage_under(false)
}

///|
test "paint invalidation includes glass sampling the changed text and keeps unrelated regions" {
  paint_damage_under(true)
}

///|
fn paint_damage_text() -> String {
  let text = @env.get_env_var("MBUI_PAINT_DAMAGE_TEXT").unwrap_or("")
  if text == "" { paint_damage_coretext } else { text }
}

// Core Text, macOS 27.0.1, 2026-11-06, scale 2: MBUI_TEXT_RECORD=1 from the fields above.
// These are host replies, not invented glyph metrics; the renderer rejects a draw list with missing glyphs.
// Unit tests use these fixed replies. Pixel checks first record the rendering host's own replies and supply them
// through MBUI_PAINT_DAMAGE_TEXT, so cluster numbers, glyph boxes and layout all belong to the host drawing them.
///|
let paint_damage_coretext : String =
  #|TEXTREC {"g":0,"r":[0,0,9.5,10.5,0,-9.5,0]}
  #|TEXTREC {"g":1,"r":[0,0,8.5,10,0.5,-9.5,0]}
  #|TEXTREC {"g":10,"r":[0,0,9,9.5,0,-9,0]}
  #|TEXTREC {"g":11,"r":[0,0,8.5,10.5,0,-9.5,0]}
  #|TEXTREC {"g":12,"r":[0,0,8.5,9.5,0,-9,0]}
  #|TEXTREC {"g":13,"r":[0,0,9,13.5,0,-12.5,0]}
  #|TEXTREC {"g":14,"r":[0,0,9,12.5,0,-9,0]}
  #|TEXTREC {"g":2,"r":[0,0,9,10.5,0,-9.5,0]}
  #|TEXTREC {"g":3,"r":[0,0,6.5,12.5,-0.5,-11.5,0]}
  #|TEXTREC {"g":4,"r":[0,0,12.5,9.5,0,-9,0]}
  #|TEXTREC {"g":5,"r":[0,0,8.5,13,0.5,-12.5,0]}
  #|TEXTREC {"g":6,"r":[0,0,6,10,0.5,-9.5,0]}
  #|TEXTREC {"g":7,"r":[0,0,6.5,13,-0.5,-12.5,0]}
  #|TEXTREC {"g":8,"r":[0,0,8.5,10,0.5,-9,0]}
  #|TEXTREC {"g":9,"r":[0,0,3,13,0.5,-12.5,0]}
  #|TEXTREC {"m":[16,400,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}
  #|TEXTREC {"s":[16,400,0,"one\ntwo\nthree\nfour\nfive\n"],"r":[0,1,9.140625,0,1,1,9.0234375,1,2,1,8.828125,2,3,1,0,-1,4,1,5.5,3,5,1,11.921875,4,6,1,8.984375,0,7,1,0,-1,8,1,5.5,3,9,1,9.1015625,5,10,1,5.6640625,6,11,1,8.7109375,2,12,1,8.828125,2,13,1,0,-1,14,1,5.30078125,7,15,1,8.96484375,0,16,1,9.0234375,8,17,1,5.78125,6,18,1,0,-1,19,1,5.4765625,7,20,1,3.640625,9,21,1,8.203125,10,22,1,8.671875,2,23,1,0,-1]}
  #|TEXTREC {"s":[16,400,0,"one\ntwo\nthree\nfour\nfive\nsix"],"r":[0,1,9.140625,0,1,1,9.0234375,1,2,1,8.828125,2,3,1,0,-1,4,1,5.5,3,5,1,11.921875,4,6,1,8.984375,0,7,1,0,-1,8,1,5.5,3,9,1,9.1015625,5,10,1,5.6640625,6,11,1,8.7109375,2,12,1,8.828125,2,13,1,0,-1,14,1,5.30078125,7,15,1,8.96484375,0,16,1,9.0234375,8,17,1,5.78125,6,18,1,0,-1,19,1,5.4765625,7,20,1,3.640625,9,21,1,8.203125,10,22,1,8.671875,2,23,1,0,-1,24,1,8.0625,11,25,1,3.640625,9,26,1,8.078125,12]}
  #|TEXTREC {"s":[16,400,0,"word"],"r":[0,1,11.921875,4,1,1,8.984375,0,2,1,5.6640625,6,3,1,9.3984375,13]}
  #|TEXTREC {"s":[16,400,0,"wordx"],"r":[0,1,11.921875,4,1,1,8.984375,0,2,1,5.6640625,6,3,1,9.3984375,13,4,1,8.078125,12]}
  #|TEXTREC {"s":[16,400,0,"wordxy"],"r":[0,1,11.921875,4,1,1,8.984375,0,2,1,5.6640625,6,3,1,9.3984375,13,4,1,8.078125,12,5,1,8.375,14]}
