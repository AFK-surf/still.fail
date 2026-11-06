// The chats' list on a phone flung, its frames as their host gets them (Tester::run_as_host): rows come into the
// window and go out of it, and no frame of it that builds nothing again is drawn again whole: each put together from
// the layers' blocks, what changed of them drawn again where its reference is (a phone's list flung was painted
// whole, the old frame and all of the tree gone through, 1885 frames of 2310, 2026-11-05; docs/retained.md rule 16).

///|
test "the chats' list flung on a phone: no frame of it drawn again whole, rows coming and going" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="long", w=390.0, h=844.0, platform=2)
  t.set_frame_period(1000.0 / 120.0)
  t.run_for(@ui.move_most_ms)
  t.record_host()
  t.host_frames() |> ignore
  let (x, y0) = (195.0, 700.0)
  t.touch_at(0, x, y0, t.time())
  t.run_as_host(1000.0 / 240.0)
  for i in 1..=12 {
    t.touch_at(1, x, y0 - 37.5 * i.to_double(), t.time())
    t.run_as_host(1000.0 / 240.0)
  }
  t.touch_at(2, x, y0 - 450.0, t.time())
  t.run_as_host(2000.0)
  let frames = t.host_frames()
  let out : Array[String] = []
  for f in frames {
    if f.changed && !f.old_built && f.whole_why != 0 {
      out.push("at \{f.at}: drawn again whole (\{f.whole_why})")
    }
  }
  println("scene check: \{@ui.scene_check_said()}")
  assert_true(frames.length() > 100, msg="\{frames.length()} frames")
  assert_eq(out, [])
}

///|
/// The same fling: each layer drawn again in a frame of it drawn for what changed of it (a row coming into the
/// window, drawn first; one marked, the list as rows come and go), every other put together of what is kept, moved
/// where it moved (docs/retained.md rule 16: a layer moved is its reference so, nothing of it drawn again).
test "the chats' list flung on a phone: no layer drawn again but for what changed, rows coming and going" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="long", w=390.0, h=844.0, platform=2)
  t.set_frame_period(1000.0 / 120.0)
  t.run_for(@ui.move_most_ms)
  t.record_host()
  t.host_frames() |> ignore
  let (x, y0) = (195.0, 700.0)
  t.touch_at(0, x, y0, t.time())
  t.run_as_host(1000.0 / 240.0)
  for i in 1..=12 {
    t.touch_at(1, x, y0 - 37.5 * i.to_double(), t.time())
    t.run_as_host(1000.0 / 240.0)
  }
  t.touch_at(2, x, y0 - 450.0, t.time())
  t.run_as_host(2000.0)
  let frames = t.host_frames()
  let causes = ["not kept", "not drawn the frame before", "marked or told"]
  let out : Array[String] = []
  // (each kind of frame counted: drawing what differs, the old frame built again, drawing the same as before)
  let mut drew = 0
  let mut built = 0
  let mut same = 0
  for f in frames {
    if f.old_built {
      built = built + 1
    } else if f.changed {
      drew = drew + 1
    } else {
      same = same + 1
    }
    // (in each, the old frame built again or not: a layer drawn again for what changed of it)
    for w in f.drawn_why {
      if !causes.contains(w.0) {
        out.push("at \{f.at}: \{w.1} drawn again: \{w.0}")
      }
    }
    // (every layer drawn again said why: as many whys as layers drawn)
    let whys = f.drawn_why.fold(init=0, fn(n, w) { n + w.1 })
    if whys != f.layers_drawn {
      out.push("at \{f.at}: \{f.layers_drawn} layers drawn again, \{whys} said why")
    }
    // (one drawing what it drew before: nothing of the tree drawn again, nothing of the window told its host)
    if !f.changed && !f.old_built && (f.layers_drawn > 0 || !f.damage.is_empty()) {
      out.push("at \{f.at}: the same as before, \{f.layers_drawn} layers drawn again, parts \{f.damage}")
    }
  }
  let recorded = frames.fold(init=0, fn(n, f) { n + f.insts_recorded })
  let drawn = frames.fold(init=0, fn(n, f) { n + f.layers_drawn })
  println("frames: \{frames.length()}, drawing what differs \{drew}, the old frame built \{built}, the same \{same}; layers drawn \{drawn}, their own instances \{recorded}")
  assert_true(frames.length() > 100 && drew > 100, msg="\{frames.length()} frames, \{drew} drawing what differs")
  assert_eq(out, [])
}
