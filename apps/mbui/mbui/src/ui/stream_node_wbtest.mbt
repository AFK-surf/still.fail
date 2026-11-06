// Streams drawn by retained nodes, using the same host events as a remote screen.

///|
fn tree_stream_instances() -> Array[Array[Double]] {
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let at = k * inst_size
    if c.inst[at + 5] == 4.0 && c.inst[at + 20] >= @hostapi.stream_tex_base.to_double() {
      out.push(Array::makei(inst_size, fn(i) { c.inst[at + i] }))
    }
  }
  out
}

///|
test "tree stream texture follows the node's size, place, ancestor clip and opacity" {
  let t = Tester::new(fn(_) {  }, w=400.0, h=300.0)
  let current : @signals.Signal[Stream?] = @signals.signal(None)
  let place = @signals.signal((0.0, 0.0))
  let size = @signals.signal((200.0, 100.0))
  let alpha = @signals.signal(0.5)
  let fit = @signals.signal(FitCover)
  set_view_app(fn(root) {
    root.box(fn(clip) {
      clip.over(Is(true)).offset(Is((30.0, 20.0))).width(Is(Some(100.0))).height(Is(Some(80.0)))
      .clips(Is(true)).alpha(By(fn() { alpha.get() })) |> ignore
      clip.box(fn(n) {
        n.over(Is(true)).offset(By(fn() { place.get() })).width(By(fn() { Some(size.get().0) }))
        .height(By(fn() { Some(size.get().1) })) |> ignore
        stream_in(n, fn() { current.get() }, fit=fn() { fit.get() }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  let s = Stream::new(shown=fn(_) {  }, broken=fn() {  })
  current.set(Some(s))
  s.jpeg(b"jpeg", 1.0)
  t.draw()
  assert_eq(tree_stream_instances().length(), 0, msg="no decoded frame")
  t.stream_shows(s.id(), 1.0, 100, 100)
  t.draw()
  let first = tree_stream_instances()[0]
  assert_eq((first[0], first[1], first[2], first[3], first[11]), (30.0, 20.0, 200.0, 100.0, 0.5))
  assert_eq((first[12], first[13], first[14], first[15]), (0.0, 0.25, 1.0, 0.5))
  assert_eq((first[16], first[17], first[18], first[19]), (30.0, 20.0, 130.0, 100.0))
  fit.set(FitContain)
  t.draw()
  let contained = tree_stream_instances()[0]
  assert_eq((contained[0], contained[1], contained[2], contained[3]), (80.0, 20.0, 100.0, 100.0))
  place.set((-20.0, -10.0))
  size.set((100.0, 50.0))
  alpha.set(0.25)
  fit.set(FitFill)
  t.draw()
  let moved = tree_stream_instances()[0]
  assert_eq((moved[0], moved[1], moved[2], moved[3], moved[11]), (10.0, 10.0, 100.0, 50.0, 0.25))
  assert_eq((moved[12], moved[13], moved[14], moved[15]), (0.0, 0.0, 1.0, 1.0))
  assert_eq((moved[16], moved[17], moved[18], moved[19]), (30.0, 20.0, 130.0, 100.0))
  s.close()
  t.draw()
  assert_eq(tree_stream_instances().length(), 0, msg="a closed stream leaves no picture")
}

///|
test "tree streams: two pictures keep their order; removing and replacing a node does not close either decoder" {
  let t = Tester::new(fn(_) {  }, w=400.0, h=300.0)
  let whole = Stream::new(shown=fn(_) {  }, broken=fn() {  })
  let part = Stream::new(shown=fn(_) {  }, broken=fn() {  })
  let current : @signals.Signal[Stream?] = @signals.signal(Some(whole))
  let show_part = @signals.signal(true)
  set_view_app(fn(root) {
    root.box(fn(n) {
      n.over(Is(true)).width(Is(Some(200.0))).height(Is(Some(100.0))) |> ignore
      stream_in(n, fn() { current.get() }) |> ignore
    }) |> ignore
    root.show(fn() { show_part.get() }, fn(slot) {
      slot.box(fn(n) {
        n.over(Is(true)).offset(Is((40.0, 20.0))).width(Is(Some(80.0))).height(Is(Some(40.0))) |> ignore
        stream_in(n, fn() { Some(part) }) |> ignore
      }) |> ignore
    })
  })
  whole.jpeg(b"whole", 1.0)
  part.jpeg(b"part", 2.0)
  t.stream_shows(whole.id(), 1.0, 400, 200)
  t.stream_shows(part.id(), 2.0, 160, 80)
  t.draw()
  let ids = fn() { tree_stream_instances().map(fn(i) { i[20].to_int() - @hostapi.stream_tex_base }) }
  assert_eq(ids(), [whole.id(), part.id()])
  show_part.set(false)
  t.draw()
  assert_eq(ids(), [whole.id()])
  assert_false(part.closed)
  current.set(Some(part))
  t.draw()
  assert_eq(ids(), [part.id()])
  assert_false(whole.closed)
  current.set(None)
  t.draw()
  assert_eq(ids(), [])
  whole.close()
  part.close()
}

///|
test "tree stream readers are told the first decoded frame, later frames and sizes, but not a dropped frame" {
  let t = Tester::new(fn(_) {  })
  let s = Stream::new(shown=fn(_) {  }, broken=fn() {  })
  let seen : Array[(Double?, (Int, Int)?)] = []
  set_view_app(fn(root) {
    root.reacts(fn() { (s.shown_at(), s.size()) }, fn(value) { seen.push(value) })
    root.box(fn(n) {
      n.width(Is(Some(200.0))).height(Is(Some(100.0))) |> ignore
      stream_in(n, fn() { Some(s) }) |> ignore
    }) |> ignore
  })
  t.draw()
  s.jpeg(b"one", 1.0)
  t.stream_shows(s.id(), 1.0, 400, 200)
  t.draw()
  s.jpeg(b"two", 2.0)
  t.stream_drops(s.id(), 2.0)
  t.draw()
  s.jpeg(b"three", 3.0)
  t.stream_shows(s.id(), 3.0, 800, 600)
  t.draw()
  assert_eq(seen, [(None, None), (Some(1.0), Some((400, 200))), (Some(3.0), Some((800, 600)))])
  s.close()
}

///|
test "tree stream readers see whole and part decoded together as one state" {
  let t = Tester::new(fn(_) {  })
  let whole = Stream::new(shown=fn(_) {  }, broken=fn() {  })
  let part = Stream::new(shown=fn(_) {  }, broken=fn() {  })
  let seen : Array[(Double?, Double?)] = []
  set_view_app(fn(root) {
    root.reacts(fn() { (whole.shown_at(), part.shown_at()) }, fn(value) { seen.push(value) })
  })
  t.draw()
  whole.jpeg(b"whole", 1.0)
  part.jpeg(b"part", 2.0)
  t.stream_shows(whole.id(), 1.0, 400, 200)
  t.stream_shows(part.id(), 2.0, 160, 80)
  t.draw()
  assert_eq(seen, [(None, None), (Some(1.0), Some(2.0))])
  whole.close()
  part.close()
}

///|
test "tree stream layer visibility is actual and hides its pointer when the layer leaves" {
  let current : Ref[Stream?] = Ref(None)
  let layer = Ref(true)
  let t = Tester::new(fn(c) {
    match current.val {
      Some(s) => c.stream(s, w=Px(200.0), h=Px(100.0), layer=layer.val) |> ignore
      None => ()
    }
  }, h264=true)
  t.set_stream_layers(true)
  let s = Stream::new(shown=fn(_) {  }, broken=fn() {  }, layer=true)
  current.val = Some(s)
  s.h264(wb_avcc, 400, 200)
  s.frame(b"\x00\x00\x00\x01\x65", true, 1.0)
  t.stream_shows(s.id(), 1.0, 400, 200)
  t.draw()
  assert_true(s.layer_visible())
  s.pointer_at(Some((0.5, 0.5)))
  layer.val = false
  t.draw()
  assert_false(s.layer_visible())
  assert_eq(t.stream_fed(s.id()).filter(fn(x) { x.has_prefix("pointer") }), ["pointer at 0.5 0.5", "pointer none"])
  layer.val = true
  t.draw()
  assert_true(s.layer_visible())
  s.pointer_at(Some((0.1, 0.2)))
  s.close()
  assert_false(s.layer_visible())
  assert_eq(t.stream_fed(s.id()).filter(fn(x) { x.has_prefix("pointer") }).last(), Some("pointer none"))
}

///|
test "tree stream switches between its system layer and texture as its ancestor fades and moves" {
  let t = Tester::new(fn(_) {  }, w=400.0, h=300.0, h264=true)
  t.set_stream_layers(true)
  let s = Stream::new(shown=fn(_) {  }, broken=fn() {  }, layer=true)
  let alpha = @signals.signal(1.0)
  let offset = @signals.signal((0.0, 0.0))
  let shown = @signals.signal(true)
  set_view_app(fn(root) {
    root.box(fn(clip) {
      clip.over(Is(true)).width(Is(Some(200.0))).height(Is(Some(100.0))).clips(Is(true))
      .alpha(By(fn() { alpha.get() })) |> ignore
      clip.show(fn() { shown.get() }, fn(slot) {
        slot.box(fn(n) {
          n.over(Is(true)).width(Is(Some(200.0))).height(Is(Some(100.0))).offset(By(fn() { offset.get() })) |> ignore
          stream_in(n, fn() { Some(s) }) |> ignore
        }) |> ignore
      })
    }) |> ignore
  })
  s.h264(wb_avcc, 400, 200)
  s.frame(b"\x00\x00\x00\x01\x65", true, 1.0)
  t.stream_shows(s.id(), 1.0, 400, 200)
  t.draw()
  assert_true(s.layer_visible())
  assert_true(t.drawn_instances().iter().any(fn(i) { i[5] == 9.0 }))
  assert_eq(tree_stream_instances().length(), 0)
  s.pointer_at(Some((0.5, 0.5)))
  // A normal frame on the layer does not ask for a tree frame.
  s.frame(b"\x00\x00\x00\x01\x41", false, 2.0)
  t.stream_shows(s.id(), 2.0, 400, 200)
  let frames = t.frames
  on_outside(outside_streamed, s.id(), 0)
  assert_eq(t.frames, frames)
  assert_eq(s.shown_at(), Some(2.0))
  // Its holder fading switches in the same paint, and clears the pointer left on the layer.
  alpha.set(0.5)
  t.draw()
  assert_false(s.layer_visible())
  assert_eq(tree_stream_instances().length(), 1)
  assert_eq(tree_stream_instances()[0][11], 0.5)
  assert_eq(t.stream_fed(s.id()).filter(fn(x) { x.has_prefix("pointer") }).last(), Some("pointer none"))
  alpha.set(1.0)
  offset.set((50.0, 20.0))
  t.frame()
  assert_true(s.layer_visible())
  assert_true(t.fake.views.iter().any(fn(x) { x.has_prefix("place 1 50 20 200 100") && !x.contains("hidden") }), msg="\{t.fake.views}")
  // A tree-only move entirely outside the clip hides the host view; moving it back places it again. This uses the
  // frame scheduler rather than forcing a rebuild, so a retained scene cannot leave a stale host layer behind.
  offset.set((250.0, 20.0))
  t.frame()
  assert_false(s.layer_visible())
  offset.set((10.0, 0.0))
  t.frame()
  assert_true(s.layer_visible())
  assert_true(t.fake.views.iter().any(fn(x) { x.has_prefix("place 1 10 0 200 100") && !x.contains("hidden") }), msg="\{t.fake.views}")
  shown.set(false)
  t.frame()
  assert_false(s.layer_visible())
  assert_false(s.closed)
  s.close()
}

///|
test "tree stream restores from a transparent ancestor in the first frame" {
  let t = Tester::new(fn(_) {  }, w=300.0, h=200.0, h264=true)
  t.set_stream_layers(true)
  let alpha = @signals.signal(0.0)
  let s = Stream::new(shown=fn(_) {  }, broken=fn() {  }, layer=true)
  set_view_app(fn(root) {
    root.box(fn(holder) {
      holder.over(Is(true)).width(Is(Some(200.0))).height(Is(Some(100.0))).alpha(By(fn() { alpha.get() })) |> ignore
      holder.box(fn(n) {
        n.over(Is(true)).width(Is(Some(200.0))).height(Is(Some(100.0))) |> ignore
        stream_in(n, fn() { Some(s) }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  s.h264(wb_avcc, 400, 200)
  s.frame(b"\x00\x00\x00\x01\x65", true, 1.0)
  t.stream_shows(s.id(), 1.0, 400, 200)
  t.draw()
  assert_false(s.layer_visible())
  alpha.set(1.0)
  t.frame()
  assert_true(s.layer_visible())
  assert_true(t.drawn_instances().iter().any(fn(i) { i[5] == 9.0 }))
  alpha.set(0.0)
  t.frame()
  assert_false(s.layer_visible())
  alpha.set(0.5)
  t.frame()
  assert_false(s.layer_visible())
  assert_eq(tree_stream_instances().length(), 1)
  assert_eq(tree_stream_instances()[0][11], 0.5)
  s.close()
}

///|
test "tree stream leaves its system layer when its next frame switches to jpeg" {
  let t = Tester::new(fn(_) {  }, w=300.0, h=200.0, h264=true)
  t.set_stream_layers(true)
  let s = Stream::new(shown=fn(_) {  }, broken=fn() {  }, layer=true)
  set_view_app(fn(root) {
    root.box(fn(n) {
      n.width(Is(Some(200.0))).height(Is(Some(100.0))) |> ignore
      stream_in(n, fn() { Some(s) }) |> ignore
    }) |> ignore
  })
  s.h264(wb_avcc, 400, 200)
  s.frame(b"\x00\x00\x00\x01\x65", true, 1.0)
  t.stream_shows(s.id(), 1.0, 400, 200)
  t.draw()
  assert_true(s.layer_visible())
  s.jpeg(b"jpeg", 2.0)
  t.stream_shows(s.id(), 2.0, 400, 200)
  on_outside(outside_streamed, s.id(), 0)
  t.frames_owed()
  assert_eq(s.shown_at(), Some(2.0))
  assert_false(s.layer_visible())
  assert_eq(tree_stream_instances().length(), 1)
  s.close()
}

///|
test "tree stream shared pointer follows the actual two-picture composition in the same frame" {
  let t = Tester::new(fn(_) {  }, w=400.0, h=300.0, h264=true)
  t.set_stream_layers(true)
  t.add_image("mem:stream-pointer", 20, 20)
  let pointer = StreamPointer::new()
  pointer.image("mem:stream-pointer", fn() { b"pointer png" }, 20.0, 20.0, 2.0, 2.0)
  pointer.at(Some((0.5, 0.5)))
  let whole = Stream::new(shown=fn(_) {  }, broken=fn() {  }, layer=true)
  let part = Stream::new(shown=fn(_) {  }, broken=fn() {  }, layer=true)
  let whole_layer = @signals.signal(true)
  let part_layer = @signals.signal(true)
  let alpha = @signals.signal(1.0)
  let show_part = @signals.signal(true)
  let show_pointer = @signals.signal(true)
  set_view_app(fn(root) {
    root.box(fn(stage) {
      stage.over(Is(true)).offset(Is((30.0, 20.0))).width(Is(Some(200.0))).height(Is(Some(100.0)))
      .clips(Is(true)) |> ignore
      stage.box(fn(pictures) {
        pictures.over(Is(true)).width(Is(Some(200.0))).height(Is(Some(100.0))).alpha(By(fn() { alpha.get() })) |> ignore
        pictures.box(fn(n) {
          n.over(Is(true)).width(Is(Some(200.0))).height(Is(Some(100.0))) |> ignore
          stream_in(n, fn() { Some(whole) }, layer=fn() { whole_layer.get() }, pointer=Some(pointer)) |> ignore
        }) |> ignore
        pictures.show(fn() { show_part.get() }, fn(slot) {
          slot.box(fn(n) {
            n.over(Is(true)).offset(Is((40.0, 20.0))).width(Is(Some(80.0))).height(Is(Some(40.0))) |> ignore
            stream_in(n, fn() { Some(part) }, layer=fn() { part_layer.get() }, pointer=Some(pointer)) |> ignore
          }) |> ignore
        })
      }) |> ignore
      stage.show(fn() { show_pointer.get() }, fn(slot) {
        slot.box(fn(n) {
          n.over(Is(true)).width(Is(Some(200.0))).height(Is(Some(100.0))) |> ignore
          stream_pointer_in(n, pointer) |> ignore
        }) |> ignore
      })
    }) |> ignore
  })
  whole.h264(wb_avcc, 400, 200)
  part.h264(wb_avcc, 160, 80)
  whole.frame(b"\x00\x00\x00\x01\x65", true, 1.0)
  part.frame(b"\x00\x00\x00\x01\x65", true, 1.0)
  t.stream_shows(whole.id(), 1.0, 400, 200)
  t.stream_shows(part.id(), 1.0, 160, 80)
  t.draw()
  let pointers = fn(s : Stream) { t.stream_fed(s.id()).filter(fn(x) { x.has_prefix("pointer at") || x == "pointer none" }) }
  let canvas_pointer = fn() {
    t.drawn_order().filter(fn(i) { i.0 == 4 && i.3 == 20.0 && i.4 == 20.0 })
  }
  assert_true(whole.layer_visible())
  assert_true(part.layer_visible())
  assert_true(canvas_pointer().is_empty())
  assert_eq(pointers(whole).last(), Some("pointer at 0.5 0.5"))
  assert_eq(pointers(part).last(), Some("pointer at 0.75 0.75"))
  let frames = t.frames
  pointer.at(Some((0.1, 0.5)))
  assert_eq(t.frames, frames, msg="two system pointers move without a frame")
  assert_eq(pointers(whole).last(), Some("pointer at 0.1 0.5"))
  assert_eq(pointers(part).last(), Some("pointer at -0.25 0.75"))
  // The part becomes a texture, while the whole remains a system layer. One canvas pointer replaces both layer
  // pointers in that same frame, even outside or across the part's edge.
  part_layer.set(false)
  t.frame()
  t.frames_owed()
  assert_true(whole.layer_visible())
  assert_false(part.layer_visible())
  assert_eq(pointers(whole).last(), Some("pointer none"))
  assert_eq(pointers(part).last(), Some("pointer none"))
  assert_eq(canvas_pointer(), [(4, 48.0, 68.0, 20.0, 20.0, 1.0)])
  pointer.at(Some((0.3, 0.5)))
  t.frames_owed()
  assert_eq(canvas_pointer(), [(4, 88.0, 68.0, 20.0, 20.0, 1.0)])
  // The opposite mixture also keeps the pointer above both pictures and off the native layer.
  whole_layer.set(false)
  part_layer.set(true)
  t.frame()
  t.frames_owed()
  assert_false(whole.layer_visible())
  assert_true(part.layer_visible())
  assert_eq(pointers(part).last(), Some("pointer none"))
  assert_eq(canvas_pointer(), [(4, 88.0, 68.0, 20.0, 20.0, 1.0)])
  // Both videos fade; the pointer remains whole, above them, and is hidden when the source says so.
  whole_layer.set(true)
  alpha.set(0.4)
  t.frame()
  t.frames_owed()
  assert_eq(tree_stream_instances().length(), 2)
  assert_eq(canvas_pointer(), [(4, 88.0, 68.0, 20.0, 20.0, 1.0)])
  pointer.at(None)
  t.frames_owed()
  assert_true(canvas_pointer().is_empty())
  // Showing again on system layers and then removing the overlay clears both host pointers.
  alpha.set(1.0)
  pointer.at(Some((0.5, 0.5)))
  t.frame()
  t.frames_owed()
  assert_eq(pointers(whole).last(), Some("pointer at 0.5 0.5"))
  assert_eq(pointers(part).last(), Some("pointer at 0.75 0.75"))
  show_part.set(false)
  t.frame()
  assert_eq(pointers(part).last(), Some("pointer none"))
  show_pointer.set(false)
  t.frame()
  assert_eq(pointers(whole).last(), Some("pointer none"))
  whole.close()
  part.close()
}

///|
test "tree stream pointer follows the newest whole or part and becomes a tree picture while faded" {
  let t = Tester::new(fn(_) {  }, w=400.0, h=300.0, h264=true)
  t.set_stream_layers(true)
  let part_cell : Ref[Stream?] = Ref(None)
  let whole_cell : Ref[Stream?] = Ref(None)
  let part_shown = fn() {
    let a = whole_cell.val.bind(fn(s) { s.shown_at() })
    let b = part_cell.val.bind(fn(s) { s.shown_at() })
    match b { Some(p) => match a { Some(w) => p > w; None => true }; None => false }
  }
  let whole = Stream::new(shown=fn(_) {  }, broken=fn() {  }, layer=true, quiet=Some(fn(_) { !part_shown() }))
  let part = Stream::new(shown=fn(_) {  }, broken=fn() {  }, layer=true, quiet=Some(fn(_) { true }))
  whole_cell.val = Some(whole)
  part_cell.val = Some(part)
  let live = @signals.signal(true)
  set_view_app(fn(root) {
    root.reacts(fn() { (whole.shown_at(), part.shown_at(), live.get()) }, fn(state) {
      let top_is_part = match state.1 { Some(p) => match state.0 { Some(w) => p > w; None => true }; None => false }
      if !state.2 {
        whole.pointer_at(None)
        part.pointer_at(None)
      } else if top_is_part {
        // Each system layer clips its pointer to the video it shows. Telling both keeps it whole outside, inside and
        // across the part's edge; the part's video covers the whole's pointer wherever it overlaps.
        whole.pointer_at(Some((0.5, 0.5)))
        // Whole pointer (100, 50) expressed in the part at (40, 20), 80 by 40.
        part.pointer_at(Some((0.75, 0.75)))
      } else if state.0 is Some(_) {
        part.pointer_at(None)
        whole.pointer_at(Some((0.5, 0.5)))
      }
    })
    root.box(fn(stage) {
      stage.over(Is(true)).width(Is(Some(200.0))).height(Is(Some(100.0))).clips(Is(true)) |> ignore
      stage.box(fn(n) {
        n.over(Is(true)).width(Is(Some(200.0))).height(Is(Some(100.0))).alpha(By(fn() { if live.get() { 1.0 } else { 0.5 } })) |> ignore
        stream_in(n, fn() { Some(whole) }, layer=fn() { live.get() }) |> ignore
      }) |> ignore
      stage.show(part_shown, fn(slot) {
        slot.box(fn(n) {
          n.over(Is(true)).offset(Is((40.0, 20.0))).width(Is(Some(80.0))).height(Is(Some(40.0)))
          .alpha(By(fn() { if live.get() { 1.0 } else { 0.5 } })) |> ignore
          stream_in(n, fn() { Some(part) }, layer=fn() { live.get() }) |> ignore
        }) |> ignore
      })
      stage.show(fn() { whole.shown_any() && !live.get() }, fn(slot) {
        slot.box(fn(pointer) {
          pointer.over(Is(true)).offset(Is((95.0, 45.0))).width(Is(Some(10.0))).height(Is(Some(10.0)))
          .ground(Is(0xFFFFFFFFL)) |> ignore
        }) |> ignore
      })
    }) |> ignore
  })
  whole.h264(wb_avcc, 400, 200)
  part.h264(wb_avcc, 160, 80)
  whole.frame(b"\x00\x00\x00\x01\x65", true, 1.0)
  t.stream_shows(whole.id(), 1.0, 400, 200)
  t.draw()
  assert_true(whole.layer_visible())
  assert_eq(t.stream_fed(whole.id()).filter(fn(x) { x.has_prefix("pointer") }).last(), Some("pointer at 0.5 0.5"))
  part.frame(b"\x00\x00\x00\x01\x65", true, 2.0)
  t.stream_shows(part.id(), 2.0, 160, 80)
  t.draw()
  assert_true(part.layer_visible())
  assert_true(whole.view.unwrap().seq < part.view.unwrap().seq, msg="the sharper part is above the whole")
  assert_eq(t.stream_fed(whole.id()).filter(fn(x) { x.has_prefix("pointer") }).last(), Some("pointer at 0.5 0.5"))
  assert_eq(t.stream_fed(part.id()).filter(fn(x) { x.has_prefix("pointer") }).last(), Some("pointer at 0.75 0.75"))
  // A later frame of the same part shows directly, without building a new tree frame.
  part.frame(b"\x00\x00\x00\x01\x41", false, 2.5)
  t.stream_shows(part.id(), 2.5, 160, 80)
  let frames = t.frames
  on_outside(outside_streamed, part.id(), 0)
  assert_eq(t.frames, frames)
  // A pointer outside the part still belongs on the whole. Both host layers move without a frame.
  whole.pointer_at(Some((0.1, 0.5)))
  part.pointer_at(Some((-0.25, 0.75)))
  assert_eq(t.frames, frames)
  assert_eq(t.stream_fed(whole.id()).filter(fn(x) { x.has_prefix("pointer") }).last(), Some("pointer at 0.1 0.5"))
  assert_eq(t.stream_fed(part.id()).filter(fn(x) { x.has_prefix("pointer") }).last(), Some("pointer at -0.25 0.75"))
  // A newer whole replaces the part and its pointer in one frame.
  whole.frame(b"\x00\x00\x00\x01\x41", false, 3.0)
  t.stream_shows(whole.id(), 3.0, 400, 200)
  t.draw()
  assert_false(part.layer_visible())
  assert_eq(t.stream_fed(part.id()).filter(fn(x) { x.has_prefix("pointer") }).last(), Some("pointer none"))
  assert_eq(t.stream_fed(whole.id()).filter(fn(x) { x.has_prefix("pointer") }).last(), Some("pointer at 0.5 0.5"))
  live.set(false)
  t.draw()
  assert_false(whole.layer_visible())
  assert_eq(tree_stream_instances()[0][11], 0.5)
  assert_true(t.drawn_rects().iter().any(fn(r) { r.0 == 95.0 && r.1 == 45.0 && r.2 == 10.0 && r.3 == 10.0 }))
  assert_eq(t.stream_fed(whole.id()).filter(fn(x) { x.has_prefix("pointer") }).last(), Some("pointer none"))
  whole.close()
  part.close()
}
