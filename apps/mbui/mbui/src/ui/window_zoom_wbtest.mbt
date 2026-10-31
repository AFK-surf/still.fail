// A host's physical window, pointer, embedded page and accessibility agree on the same content zoom.

///|
test "window zoom: changing the scale owes a frame even between inputs" {
  let t = Tester::new(fn(c) { c.text("hello") |> ignore }, w=400.0, h=300.0)
  t.frames_owed()
  assert_true(t.at_rest())
  set_window_zoom(2.0)
  assert_false(t.at_rest(), msg="the frame at the new scale is still owed")
  t.frames_owed()
  assert_eq(t.ctx().window_size(), (200.0, 150.0))
  assert_true(t.at_rest())
}

///|
test "window zoom: a scale chosen during a frame is drawn in the next frame" {
  let change = Ref(false)
  let t = Tester::new(fn(c) {
    if change.val {
      c.after_build("zoom-test", fn() { set_window_zoom(1.25) })
    }
    c.text("hello") |> ignore
  }, w=400.0, h=300.0)
  change.val = true
  t.draw()
  assert_eq(t.ctx().window_size(), (320.0, 240.0))
  assert_true(t.at_rest())
}

///|
test "window zoom: a host press and accessibility agree at both extremes" {
  for (zoom, width, height) in [(0.5, "50", "20"), (2.0, "200", "80")] {
    let hits = Ref(0)
    let t = Tester::new(fn(c) {
      let id = c.id("zoom-test-button")
      if c.clicked(id) {
        hits.val += 1
      }
      c.box(id~, label="Zoom test", w=Px(100.0), h=Px(40.0), fn() {  }) |> ignore
    }, w=400.0, h=300.0, window_corner=16.0)
    t.set_a11y(true)
    set_window_zoom(zoom)
    t.frame()
    assert_eq(t.ctx().window_size(), (400.0 / zoom, 300.0 / zoom))
    assert_eq(window_corner(), 16.0 / zoom)
    let line = t.a11y_said().split("\n").find_first(fn(s) { s.contains("Zoom test") }).unwrap()
    let fields = line.split("\u{1F}").map(fn(s) { s.to_string() }).to_array()
    assert_eq((fields[7], fields[8]), (width, height), msg="zoom \{zoom}")
    host_pointer(0, 75.0 * zoom, 20.0 * zoom, 0)
    host_pointer(2, 75.0 * zoom, 20.0 * zoom, 0)
    t.draw()
    assert_eq(hits.val, 1, msg="press inside at zoom \{zoom}")
    host_pointer(0, 101.0 * zoom, 20.0 * zoom, 0)
    host_pointer(2, 101.0 * zoom, 20.0 * zoom, 0)
    t.draw()
    assert_eq(hits.val, 1, msg="press outside at zoom \{zoom}")
  }
}

///|
test "window zoom: an embedded page is placed and rendered at the same size as its hole" {
  for (zoom, place, scale) in [
    (0.5, "place 1 0 0 50 40 in 0 0 50 40", "control 1 8 0.5"),
    (2.0, "place 1 0 0 200 160 in 0 0 200 160", "control 1 8 2"),
  ] {
    let page : Ref[NativeView?] = Ref(None)
    let t = Tester::new(fn(c) {
      let v = match page.val {
        Some(v) => v
        None => {
          let v = NativeView::page("<p>hello</p>")
          page.val = Some(v)
          v
        }
      }
      c.native(v, w=Px(100.0), h=Px(80.0)) |> ignore
    }, w=400.0, h=300.0)
    set_window_zoom(zoom)
    t.frame()
    assert_true(t.views().contains(place), msg="position at zoom \{zoom}: \{t.views()}")
    assert_true(t.views().contains(scale), msg="page scale at zoom \{zoom}: \{t.views()}")
    page.val.unwrap().close()
  }
}

///|
test "window zoom: an offscreen renderer is told the scale before the frame it draws" {
  let scales : Array[Double] = []
  let t = Tester::new(fn(c) { c.text("hello") |> ignore }, before=fn() { scales.push(window_zoom()) })
  assert_eq(scales[0], 1.0)
  set_window_zoom(1.25)
  t.frame()
  assert_eq(scales.last(), Some(1.25))
}

///|
test "window zoom: a host without content zoom keeps its layout and rendering in agreement" {
  let t = Tester::new(fn(c) { c.text("hello") |> ignore }, w=400.0, h=300.0, platform=2)
  assert_false(window_zoom_supported())
  set_window_zoom(2.0)
  t.frame()
  assert_eq(t.ctx().window_size(), (400.0, 300.0))
}
