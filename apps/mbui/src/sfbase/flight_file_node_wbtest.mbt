///|
fn retained_file_flight(steps : Int, picture : Bool) -> Array[Array[Double]] raise {
  reset()
  let ink = 0x335599FFL
  let from = (20.0, 400.0, if picture { 96.0 } else { 240.0 }, 96.0)
  let source = @signals.signal(true)
  let row = @signals.signal(false)
  let destination : Map[String, FileLandingNode] = {}
  let field = @ui.Field::new()
  let fitted : Ref[() -> @ui.Fit] = Ref(fn() { FitCover })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=390.0, h=600.0, platform=2, stable=false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(list) {
      list.height(Is(Some(160.0))).clips(Is(true)) |> ignore
      list.show(fn() { row.get() }, fn(file) {
        file.width(Is(Some(300.0))).height(Is(Some(120.0))).offset(Is((40.0, 30.0))).ground(Is(ink)) |> ignore
        destination["file"] = {
          view: file, share: fn() { (0.8, 1.0) }, top_crop: fn() { true },
          copy: fn(p, _, _, fit, corner) {
            fitted.val = fit
            // (as big as what holds it, as the message's own picture's copy is: the flight lays that out)
            p.box(fn(content) {
              content.width_share(Is(1.0)).height_share(Is(1.0)).radius(By(corner)).ground(Is(ink)) |> ignore
            }) |> ignore
          },
        }
        file.owns(fn() { destination.remove("file") }) |> ignore
      })
    }) |> ignore
    root.show(fn() { source.get() }, fn(tile) {
      tile.over(Is(true)).width(Is(Some(from.2))).height(Is(Some(from.3)))
      .offset(Is((from.0, from.1))).ground(Is(ink)) |> ignore
    })
    root.box(fn(input) { @ui.field(input, field) |> ignore }) |> ignore
    root.box(fn(layer) {
      layer.over(Is(true)) |> ignore
      send_flight_node(layer, "files", fn(_) { if row.get() { Some("row") } else { None } }, fn(_) { None }, files=fn(_, key) {
        destination.get(key)
      })
    }) |> ignore
  })
  t.draw()
  let ff : FlyingFile = {
    key: "file", from, shown: None, picture: if picture { Some("mem:fixture/picture") } else { None },
    paint: None, ground: 0L, quote_words: None, quote_to: None, source_scale: 1.0, leaving: None, leaving_node: None,
    face: fn() { }, node: Some(fn(p) { p.ground(Is(ink)) |> ignore }),
  }
  flight_start_from(t.ctx(), "files", "files", "row", "", 140.0, [ff], field.lines(), hold=fn(_) { }, desk=true)
  source.set(false)
  t.draw()
  let f = send_flight.get().unwrap()
  let shown = fn() { t.drawn_rects().filter(fn(r) { r.4 == ink }) }
  assert_false(f.placed)
  assert_eq(shown(), [(from.0, from.1, from.2, from.3, ink)])
  row.set(true)
  t.draw()
  // (its row told laid out in that frame, it sets out as the next change, at that frame's moment)
  t.draw()
  assert_true(f.placed, msg="a file-only send starts when its own real row has a place")
  let start = f.set_out
  let end = f.way.ends()
  assert_eq(shown(), [(from.0, from.1, from.2, from.3, ink)])
  if picture { assert_true((fitted.val)() == FitCoverAt(0.5)) }
  for i in 1..<(steps + 1) {
    t.run_for(start + (end - start) * 0.5 * i.to_double() / steps.to_double() - t.time())
  }
  t.run_for(start + (end - start) * 0.5 - t.time())
  assert_eq(shown().length(), 1, msg="the message and the flying file share one visible owner")
  let mid = t.drawn_instances().map(fn(a) { a.map(fn(x) { (x * 100.0).round() / 100.0 }) })
  t.run_for(end - 1.0 - t.time())
  if picture {
    let r = shown()[0]
    assert_true((r.0 - 70.0).abs() < 1.0 && (r.2 - 240.0).abs() < 1.0, msg="the picture lands in the message's letterbox: \{r}")
    match (fitted.val)() {
      FitCoverAt(top) => assert_true(top < 0.01)
      _ => fail("a tall picture reaches the same top crop as its message")
    }
  }
  t.run_for(end - t.time())
  assert_true(send_flight.get() is None)
  assert_eq(shown(), [(40.0, 30.0, 300.0, 120.0, ink)])
  mid
}

///|
test "a sent picture waits in its tile, flies past the list's cut into its own letterbox and top crop, then gives back the real file" {
  assert_eq(retained_file_flight(0, true), retained_file_flight(12, true))
}

///|
test "a sent file card carries its contents at the tile's scale and gives back its message on the same path" {
  assert_eq(retained_file_flight(0, false), retained_file_flight(12, false))
}
