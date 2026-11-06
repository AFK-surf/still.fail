// Isolated prototype: exercise the real legacy sheet rather than a stand-in portal.

///|
let staged_change_ms : Double = 50.0

///|
let staged_exit_sample_ms : Double = 100.0

///|
test "a real legacy sheet is measured at its opening event before a frame" {
  let open = @signals.signal(false)
  let content_h = @signals.signal(120.0)
  let host : Ref[@view.View?] = Ref(None)
  let window : Ref[@view.View?] = Ref(None)
  let requested = Ref(0.0)
  let told = Ref(0)
  let body_told = Ref(0)
  let built = Ref(0)
  let field = @ui.Field::new()
  let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, w=390.0, h=844.0, tree=fn(root) {
    window.val = Some(root)
    @ui.old(root, fn(c) { c.text("Page") |> ignore }).height(Is(Some(40.0))) |> ignore
    root.show(fn() { open.get() }, fn(layer) {
      let v = @ui.old(layer, fn(c) {
        let fit = c.id("presenter/fit")
        let h = c.laid_size(fit).map(fn(x) { x.1 }).unwrap_or(422.0)
        requested.val = h
        c.tell("sheet/body-created", fn() { told.val += 1 })
        sheet(c, "real-sheet", true, h~, fn() {
          built.val += 1
          c.tell("sheet/body-action", fn() { body_told.val += 1 })
          c.box(w=Px(200.0), h=Px(content_h.get()), id=fit, fn() {
            c.capped("body", 100.0, fn() {
              c.editor("query", field~, placeholder="Query") |> ignore
            }) |> ignore
          }) |> ignore
        }) |> ignore
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  t.check_looks(false)
  t.draw()
  let root = window.val.unwrap()
  root.event_action(fn() {
    open.set(true)
    root.after_event_action(fn() { @ui.probe_old_layer(host.val.unwrap()) })
  })
  assert_eq(requested.val, 120.0)
  assert_eq(told.val, 0)
  assert_eq(body_told.val, 0)
  root.event_action(fn() {
    content_h.set(220.0)
    @ui.probe_old_layer(host.val.unwrap())
  })
  assert_eq(requested.val, 220.0, msg="changed content is measured in the same event, before a frame")
  let built_at_event = built.val
  t.frame_at(t.time())
  assert_eq(built.val, built_at_event, msg="body was built again on its first frame: \{built_at_event} -> \{built.val}")
  assert_eq(told.val, 1)
  assert_eq(body_told.val, 1)
  t.frame_at(t.time())
  assert_eq(built.val, built_at_event + 1)
  assert_eq(body_told.val, 2)
}

///|
fn legacy_staged_change(intermediate_frame : Bool) -> Double {
  let open = @signals.signal(false)
  let content_h = @signals.signal(120.0)
  let host : Ref[@view.View?] = Ref(None)
  let window : Ref[@view.View?] = Ref(None)
  let below = Ref(0.0)
  let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, w=390.0, h=844.0, tree=fn(root) {
    window.val = Some(root)
    @ui.old(root, fn(c) { c.text("Page") |> ignore }).height(Is(Some(40.0))) |> ignore
    root.show(fn() { open.get() }, fn(layer) {
      let v = @ui.old(layer, fn(c) {
        let fit = c.id("presenter/fit")
        let h = c.laid_size(fit).map(fn(x) { x.1 }).unwrap_or(422.0)
        sheet(c, "real-sheet", true, h~, look=fn(ctx, state, body) {
          below.val = state.below
          ctx.box(w=Fill(1.0), h=Px(state.h), body) |> ignore
        }, fn() {
          c.box(w=Px(200.0), h=Px(content_h.get()), id=fit, fn() {  }) |> ignore
        }) |> ignore
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  t.check_looks(false)
  t.draw()
  let root = window.val.unwrap()
  root.event_action(fn() {
    open.set(true)
    root.after_event_action(fn() { @ui.probe_old_layer(host.val.unwrap()) })
  })
  if intermediate_frame { t.frame_at(t.time()) }
  t.advance(staged_change_ms)
  root.event_action(fn() {
    content_h.set(220.0)
    @ui.probe_old_layer(host.val.unwrap())
  })
  below.val
}

///|
test "a real legacy sheet keeps its opening trajectory across content changes without a frame" {
  let with_frame = legacy_staged_change(true)
  let no_frame = legacy_staged_change(false)
  assert_true((with_frame - no_frame).abs() < 0.01, msg="opening below at 50ms: with=\{with_frame}, without=\{no_frame}")
}

///|
fn legacy_staged_touch(intermediate_frame : Bool, y : Double, deferred? : Bool = false) -> (Double, Int, Int, Int) {
  let open = @signals.signal(false)
  let host : Ref[@view.View?] = Ref(None)
  let window : Ref[@view.View?] = Ref(None)
  let button = Ref(0)
  let hit = Ref(0)
  let built = Ref(0)
  let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, w=390.0, h=844.0, tree=fn(root) {
    window.val = Some(root)
    @ui.old(root, fn(c) { c.text("Page") |> ignore }).height(Is(Some(40.0))) |> ignore
    root.show(fn() { open.get() }, fn(layer) {
      let v = @ui.old(layer, fn(c) {
        sheet(c, "real-sheet", true, h=120.0, look=fn(ctx, state, body) {
          ctx.box(w=Fill(1.0), h=Px(state.h), body) |> ignore
        }, fn() {
          built.val += 1
          let id = c.id("sheet-button")
          button.val = id
          c.box(w=Fill(1.0), h=Px(40.0), id~, label="Sheet button", fn() {  }) |> ignore
          if deferred {
            if c.clicked(id) { hit.val += 1 }
          } else {
            c.on_press(id, fn() { hit.val += 1 })
          }
        }) |> ignore
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  t.check_looks(false)
  t.draw()
  let root = window.val.unwrap()
  root.event_action(fn() {
    open.set(true)
    root.after_event_action(fn() { @ui.probe_old_layer(host.val.unwrap()) })
  })
  let built_at_open = built.val
  t.advance(staged_exit_sample_ms)
  if intermediate_frame { t.frame_at(t.time()) }
  let target = if intermediate_frame {
    let rect = t.ctx().rect_of(button.val).unwrap()
    rect.1 + rect.3 / 2.0
  } else { y }
  t.touch(0, 20.0, target)
  t.touch(2, 20.0, target)
  if deferred { t.frame_at(t.time()) }
  (target, hit.val, built_at_open, built.val)
}

///|
test "a staged real legacy sheet delivers the old clicked callback after an unframed touch" {
  let (y, framed, _, _) = legacy_staged_touch(true, 0.0, deferred=true)
  let (_, unframed, _, _) = legacy_staged_touch(false, y, deferred=true)
  assert_eq((framed, unframed), (1, 1))
}

///|
test "a staged real legacy sheet takes a touch at its current position without a frame" {
  let (y, framed, _, _) = legacy_staged_touch(true, 0.0)
  let (_, unframed, open_built, final_built) = legacy_staged_touch(false, y)
  assert_eq(framed, 1)
  assert_eq(unframed, 1, msg="same touch y=\{y}, framed=\{framed}, unframed=\{unframed}")
  assert_eq(final_built, open_built, msg="repositioning the shell must not rerun its unchanged body")
}

///|
test "a staged legacy sheet is reused when it is the only old island" {
  let open = @signals.signal(false)
  let host : Ref[@view.View?] = Ref(None)
  let window : Ref[@view.View?] = Ref(None)
  let built = Ref(0)
  let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, w=390.0, h=844.0, tree=fn(root) {
    window.val = Some(root)
    root.show(fn() { open.get() }, fn(layer) {
      let v = @ui.old(layer, fn(c) {
        sheet(c, "real-sheet", true, h=120.0, fn() {
          built.val += 1
          c.box(w=Px(200.0), h=Px(120.0), fn() {  }) |> ignore
        }) |> ignore
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  t.check_looks(false)
  t.draw()
  let root = window.val.unwrap()
  root.event_action(fn() {
    open.set(true)
    root.after_event_action(fn() { @ui.probe_old_layer(host.val.unwrap()) })
  })
  let staged = built.val
  t.frame_at(t.time())
  assert_eq(built.val, staged, msg="the only old island reran its staged body: \{staged} -> \{built.val}")
}

///|
test "a staged legacy sheet consumes a real click only once while remeasuring" {
  let open = @signals.signal(false)
  let content_h = @signals.signal(120.0)
  let host : Ref[@view.View?] = Ref(None)
  let window : Ref[@view.View?] = Ref(None)
  let button = Ref(0)
  let clicked = Ref(0)
  let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, w=390.0, h=844.0, tree=fn(root) {
    window.val = Some(root)
    @ui.old(root, fn(c) { c.text("Page") |> ignore }).height(Is(Some(40.0))) |> ignore
    root.show(fn() { open.get() }, fn(layer) {
      let v = @ui.old(layer, fn(c) {
        let fit = c.id("presenter/fit")
        let h = c.laid_size(fit).map(fn(x) { x.1 }).unwrap_or(422.0)
        sheet(c, "real-sheet", true, h~, fn() {
          let id = c.id("sheet-button")
          button.val = id
          c.box(w=Fill(1.0), h=Px(content_h.get()), id=fit, fn() {
            c.box(w=Px(100.0), h=Px(40.0), id~, label="Sheet button", fn() {  }) |> ignore
          }) |> ignore
          if c.clicked(id) { clicked.val += 1 }
        }) |> ignore
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  t.check_looks(false)
  t.draw()
  let root = window.val.unwrap()
  root.event_action(fn() {
    open.set(true)
    root.after_event_action(fn() { @ui.probe_old_layer(host.val.unwrap()) })
  })
  t.advance(@ui.move_most_ms)
  t.frame_at(t.time())
  let rect = t.ctx().rect_of(button.val).unwrap()
  t.touch(0, rect.0 + 20.0, rect.1 + 20.0)
  t.touch(2, rect.0 + 20.0, rect.1 + 20.0)
  root.event_action(fn() {
    content_h.set(220.0)
    @ui.probe_old_layer(host.val.unwrap())
  })
  assert_eq(clicked.val, 0, msg="the partial staging build must leave a pending click for the full frame: \{clicked.val}")
  t.frame_at(t.time())
  assert_eq(clicked.val, 1, msg="the following frame must take the click exactly once: \{clicked.val}")
}

///|
test "a partial old build leaves a pending sheet drag for the full frame" {
  let open = @signals.signal(false)
  let host : Ref[@view.View?] = Ref(None)
  let window : Ref[@view.View?] = Ref(None)
  let top = Ref(0)
  let closed = Ref(0)
  let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, w=390.0, h=844.0, tree=fn(root) {
    window.val = Some(root)
    @ui.old(root, fn(c) { c.text("Page") |> ignore }).height(Is(Some(40.0))) |> ignore
    root.show(fn() { open.get() }, fn(layer) {
      let v = @ui.old(layer, fn(c) {
        top.val = c.id("real-sheet/top")
        let r = sheet(c, "real-sheet", true, h=300.0, fn() {
          c.box(w=Px(200.0), h=Px(80.0), fn() {  }) |> ignore
        })
        if r.dragged is Some(DraggedClosed) { closed.val += 1 }
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  t.check_looks(false)
  t.draw()
  let root = window.val.unwrap()
  root.event_action(fn() {
    open.set(true)
    root.after_event_action(fn() { @ui.probe_old_layer(host.val.unwrap()) })
  })
  t.advance(@ui.move_most_ms)
  t.frame_at(t.time())
  let rect = t.ctx().rect_of(top.val).unwrap()
  let x = rect.0 + 30.0
  let y = rect.1 + 10.0
  t.advance(@ui.input_step_ms)
  t.touch(0, x, y)
  t.advance(@ui.input_step_ms)
  t.touch(1, x, y + 150.0)
  t.advance(@ui.input_step_ms)
  t.touch(2, x, y + 150.0)
  root.event_action(fn() { @ui.probe_old_layer(host.val.unwrap()) })
  assert_eq(closed.val, 0, msg="the partial build must not consume the drag's end")
  t.frame_at(t.time())
  assert_eq(closed.val, 1, msg="the complete frame takes the drag exactly once")
}

///|
test "an event-staged real sheet exposes its body to accessibility" {
  let open = @signals.signal(false)
  let host : Ref[@view.View?] = Ref(None)
  let window : Ref[@view.View?] = Ref(None)
  let presses = Ref(0)
  let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, w=390.0, h=844.0, tree=fn(root) {
    window.val = Some(root)
    @ui.old(root, fn(c) { c.text("Page") |> ignore }).height(Is(Some(40.0))) |> ignore
    root.show(fn() { open.get() }, fn(layer) {
      let v = @ui.old(layer, fn(c) {
        sheet(c, "real-sheet", true, h=160.0, fn() {
          let id = c.id("action")
          let i = c.box(w=Px(100.0), h=Px(40.0), id~, fn() {  })
          c.semantics(i, Button, id~, label="Sheet action", actions=[Activate])
          c.on_press(id, fn() { presses.val += 1 })
        }) |> ignore
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  t.draw()
  let root = window.val.unwrap()
  root.event_action(fn() {
    open.set(true)
    root.after_event_action(fn() { @ui.probe_old_layer(host.val.unwrap()) })
  })
  assert_true(t.query(Button, label="Sheet action") is Some(_))
  t.act(Button, Activate, label="Sheet action")
  assert_eq(presses.val, 1)
}

///|
fn legacy_change_then_close(intermediate_frame : Bool) -> (Double, Double, Double, Int) raise {
  let shown = @signals.signal(false)
  let open = @signals.signal(true)
  let content_h = @signals.signal(120.0)
  let host : Ref[@view.View?] = Ref(None)
  let window : Ref[@view.View?] = Ref(None)
  let requested = Ref(0.0)
  let final_state = Ref({ t: 0.0, h: 0.0, below: 0.0 })
  let gone = Ref(0)
  let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, w=390.0, h=844.0, tree=fn(root) {
    window.val = Some(root)
    @ui.old(root, fn(c) { c.text("Page") |> ignore }).height(Is(Some(40.0))) |> ignore
    root.show(fn() { shown.get() }, fn(layer) {
      let v = @ui.old(layer, fn(c) {
        let fit = c.id("presenter/fit")
        let h = c.laid_size(fit).map(fn(x) { x.1 }).unwrap_or(422.0)
        requested.val = h
        let r = sheet(c, "real-sheet", open.get(), h~, look=fn(ctx, state, body) {
          final_state.val = state
          ctx.box(w=Fill(1.0), h=Px(state.h), body) |> ignore
        }, fn() {
          c.box(w=Px(200.0), h=Px(content_h.get()), id=fit, fn() {  }) |> ignore
        })
        if !r.shown {
          c.tell("sheet/gone", fn() { gone.val += 1; shown.set(false) })
        }
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  t.check_looks(false)
  t.draw()
  let root = window.val.unwrap()
  root.event_action(fn() {
    shown.set(true)
    root.after_event_action(fn() { @ui.probe_old_layer(host.val.unwrap()) })
  })
  if intermediate_frame { t.frame_at(t.time()) }
  t.advance(staged_change_ms)
  root.event_action(fn() {
    content_h.set(220.0)
    // A presenter snapshots a still-open old layer before it publishes the closing stack.
    @ui.probe_old_layer(host.val.unwrap())
    open.set(false)
    @ui.probe_old_layer(host.val.unwrap())
  })
  let h = requested.val
  let at_close = final_state.val.h
  t.advance(staged_exit_sample_ms)
  root.event_action(fn() { @ui.probe_old_layer(host.val.unwrap()) })
  let below = final_state.val.below
  let rest = sheet_rest("real-sheet")
  if rest > t.time() { t.advance(rest - t.time() + 1.0) }
  root.event_action(fn() { @ui.probe_old_layer(host.val.unwrap()) })
  assert_eq(gone.val, 0, msg="old Ctx::tell remains owned by the complete frame")
  t.frame_at(t.time())
  assert_eq(gone.val, 1)
  (h, at_close, below, gone.val)
}

///|
test "a changed real legacy sheet closes with the same height and trajectory without a frame" {
  let framed = legacy_change_then_close(true)
  let unframed = legacy_change_then_close(false)
  assert_eq(framed.0, 220.0)
  assert_eq(unframed.0, 220.0)
  assert_true((framed.1 - unframed.1).abs() < 0.01, msg="height at close: \{framed.1} / \{unframed.1}")
  assert_true((framed.2 - unframed.2).abs() < 0.01, msg="exit after 100ms: \{framed.2} / \{unframed.2}")
  assert_eq((framed.3, unframed.3), (1, 1))
}

///|
test "a staged legacy sheet sees the new window during resize structure changes" {
  let open = @signals.signal(false)
  let host : Ref[@view.View?] = Ref(None)
  let at_resize : Ref[(Double, Double)?] = Ref(None)
  let h_at_resize = Ref(0.0)
  let narrow_at_resize = Ref(false)
  let last_built_size = Ref((0.0, 0.0))
  let last_built_h = Ref(0.0)
  let last_built_narrow = Ref(false)
  let window : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, w=390.0, h=844.0, tree=fn(root) {
    window.val = Some(root)
    root.show(fn() { open.get() }, fn(layer) {
      let v = @ui.old(layer, fn(c) {
        last_built_size.val = c.window_size()
        last_built_narrow.val = c.narrow()
        sheet(c, "real-sheet", true, share=0.7, look=fn(ctx, state, body) {
          last_built_h.val = state.h
          ctx.box(w=Fill(1.0), h=Px(state.h), body) |> ignore
        }, fn() {
          c.box(w=Px(200.0), h=Px(120.0), fn() {  }) |> ignore
        }) |> ignore
      })
      v.over(Is(true)).width(By(fn() { Some(root.window().0) })).height(By(fn() { Some(root.window().1) })) |> ignore
      host.val = Some(v)
    })
    root.reacts(fn() { root.window() }, fn(size) {
      if size.1 == 600.0 && host.val is Some(v) {
        root.after_event_action(fn() {
          @ui.probe_old_layer(v)
          at_resize.val = Some(last_built_size.val)
          h_at_resize.val = last_built_h.val
          narrow_at_resize.val = last_built_narrow.val
        })
      }
    }) |> ignore
  })
  let wide = t.ctx().theme()
  let narrow = { ..wide, bg: 0xFFEEDDFFL }
  t.ctx().set_theme(wide, narrow~, narrow_below=350.0)
  t.draw()
  let root = window.val.unwrap()
  root.event_action(fn() {
    open.set(true)
    root.after_event_action(fn() { @ui.probe_old_layer(host.val.unwrap()) })
  })
  t.resize(320.0, 600.0)
  assert_eq(at_resize.val, Some((320.0, 600.0)))
  assert_eq(h_at_resize.val, 420.0)
  assert_true(narrow_at_resize.val)
}

///|
fn legacy_sheet_body_rect(staged : Bool) -> Array[(Double, Double, Double, Double)] {
  let open = @signals.signal(false)
  let host : Ref[@view.View?] = Ref(None)
  let window : Ref[@view.View?] = Ref(None)
  let body_ids : Array[Int] = []
  let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, w=390.0, h=844.0, tree=fn(root) {
    window.val = Some(root)
    @ui.old(root, fn(c) { c.text("Page") |> ignore }).height(Is(Some(40.0))) |> ignore
    root.show(fn() { open.get() }, fn(layer) {
      let v = @ui.old(layer, fn(c) {
        sheet(c, "real-sheet", true, h=180.0, fn() {
          body_ids.clear()
          for k in 0..<3 {
            let id = c.id("body-\{k}")
            body_ids.push(id)
            c.box(w=Fill(1.0), h=if k == 1 { Fill(1.0) } else { Px(20.0) }, id~, fn() {  }) |> ignore
          }
        }) |> ignore
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  t.draw()
  let root = window.val.unwrap()
  root.event_action(fn() {
    open.set(true)
    if staged { root.after_event_action(fn() { @ui.probe_old_layer(host.val.unwrap()) }) }
  })
  t.frame_at(t.time())
  body_ids.map(fn(id) { t.ctx().rect_of(id).unwrap() })
}

///|
test "a staged legacy sheet keeps its body's original layout" {
  let ordinary = legacy_sheet_body_rect(false)
  let staged = legacy_sheet_body_rect(true)
  assert_eq(staged, ordinary, msg="body bounds after one first frame: staged=\{staged}, ordinary=\{ordinary}")
}

///|
test "a staged legacy sheet updates its body when the theme changes before a frame" {
  let open = @signals.signal(false)
  let host : Ref[@view.View?] = Ref(None)
  let window : Ref[@view.View?] = Ref(None)
  let body_bg = Ref(0L)
  let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, w=390.0, h=844.0, tree=fn(root) {
    window.val = Some(root)
    root.show(fn() { open.get() }, fn(layer) {
      let v = @ui.old(layer, fn(c) {
        sheet(c, "real-sheet", true, h=180.0, fn() {
          body_bg.val = c.theme().bg
          c.box(w=Fill(1.0), h=Px(100.0), bg=body_bg.val, fn() {  }) |> ignore
        }) |> ignore
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  t.check_looks(false)
  t.draw()
  let root = window.val.unwrap()
  let original = t.ctx().theme()
  let changed = { ..original, bg: 0xFF1188FFL }
  root.event_action(fn() {
    open.set(true)
    root.after_event_action(fn() { @ui.probe_old_layer(host.val.unwrap()) })
  })
  assert_eq(body_bg.val, original.bg)
  t.ctx().set_theme(changed)
  root.event_action(fn() { @ui.probe_old_layer(host.val.unwrap()) })
  assert_eq(body_bg.val, changed.bg)
}

///|
test "a staged legacy sheet preserves a navigation body on its first frame" {
  let open = @signals.signal(false)
  let host : Ref[@view.View?] = Ref(None)
  let window : Ref[@view.View?] = Ref(None)
  let nav = @ui.Nav::new(0)
  let builds = Ref(0)
  let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, w=390.0, h=844.0, tree=fn(root) {
    window.val = Some(root)
    root.show(fn() { open.get() }, fn(layer) {
      let v = @ui.old(layer, fn(c) {
        sheet(c, "real-sheet", true, h=180.0, fn() {
          builds.val += 1
          c.nav(nav, fn(page) { c.text("Page \{page}") |> ignore }) |> ignore
        }) |> ignore
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  t.check_looks(false)
  t.draw()
  let root = window.val.unwrap()
  root.event_action(fn() {
    open.set(true)
    root.after_event_action(fn() { @ui.probe_old_layer(host.val.unwrap()) })
  })
  let built_at_event = builds.val
  t.advance(staged_change_ms)
  root.event_action(fn() { @ui.probe_old_layer(host.val.unwrap()) })
  assert_eq(builds.val, built_at_event, msg="sampling the shell must not rebuild the navigation body")
  t.frame_at(t.time())
  assert_eq(builds.val, built_at_event, msg="the body containing navigation was built a second time")
  assert_true(t.query(Text, label="Page 0") is Some(_))
}
