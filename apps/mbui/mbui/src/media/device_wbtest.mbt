///|
test "the device art leaves the screen open and keeps the hardware" {
  for model in [Device::IPhone11Pro, Device::IPadPro11, Device::MacBookPro16] {
    let g = model.geometry()
    let screen = model.screen()
    assert_eq((screen.width * screen.scale, screen.height * screen.scale), (g.screen_width, g.screen_height))
    let (_, svg) = model.art()
    guard @svg.rasterize(@utf8.encode(svg), 512) is Some((w, h, rgba)) else {
      fail("device art could not be drawn")
    }
    let k = if g.width > g.height { w.to_double() / g.width } else { h.to_double() / g.height }
    let alpha = fn(x : Double, y : Double) {
      let at = (y.to_int() * w + x.to_int()) * 4 + 3
      rgba[at].to_int()
    }
    assert_eq(alpha(0.0, 0.0), 0)
    assert_eq(alpha((g.screen_x + g.screen_width / 2.0) * k, (g.screen_y + g.screen_height / 2.0) * k), 0)
    assert_eq(alpha(g.width / 2.0 * k, g.height * 0.015 * k), 255)
    if model == Device::IPhone11Pro {
      // The notch is hardware, not part of the opening.
      assert_eq(alpha(g.width / 2.0 * k, (g.screen_y + 40.0) * k), 255)
      // App content below the system's reserved top clears the notch.
      assert_eq(alpha(g.width / 2.0 * k, (g.screen_y + screen.top * screen.scale) * k), 0)
    }
  }
}

///|
test "a device places the screen at the artwork's scale" {
  let model = Device::IPhone11Pro
  let t = @ui.Tester::new(
    fn(c) { device(c, model, "screen.png", 648.0) |> ignore },
    w=900.0,
    h=1500.0,
    images=[("screen.png", 1125, 2436)],
  )
  t.draw()
  let boxes = t.boxes()
  guard boxes.iter().find_first(fn(b) { b.name == "media-device" }) is Some(outer) else {
    fail("no device")
  }
  guard boxes.iter().find_first(fn(b) { b.name == "media-screen" }) is Some(screen) else {
    fail("no screen")
  }
  let g = model.geometry()
  assert_eq((outer.w, outer.h), (648.0, 1296.0))
  assert_eq((screen.x - outer.x, screen.y - outer.y), (g.screen_x * 0.5, g.screen_y * 0.5))
  assert_eq((screen.w, screen.h), (g.screen_width * 0.5, g.screen_height * 0.5))
}

///|
test "device art still draws when the app's vector renderer does not handle it" {
  // An app may have its own renderer for its own SVGs. The device library must supply its art without replacing it.
  let app_asked = Ref(0)
  @ui.set_vector_pictures(fn(_, _) { app_asked.val += 1; None })
  let model = Device::IPhone11Pro
  let (_, svg) = model.art()
  let raw = "bytes:\{@utf8.encode(svg).length()}"
  let t = @ui.Tester::new(
    fn(c) { device(c, model, "screen.png", 216.0) |> ignore },
    w=300.0,
    h=500.0,
    images=[("screen.png", 1125, 2436)],
  )
  let art = t.image_loads().filter(fn(load) { load.0.has_prefix("bytes:") })
  assert_true(art.length() == 1 && art[0].0 != raw, msg="the device SVG was handed to the host without being drawn")
  assert_eq(app_asked.val, 0)
  let app = @ui.Tester::new(fn(c) { c.image("mem:app-svg", w=Px(80.0), h=Px(80.0)) |> ignore })
  @ui.add_image("mem:app-svg", b"<svg width='2' height='2'/>")
  app.draw()
  assert_true(app_asked.val > 0, msg="the app's own renderer was replaced")
  @ui.set_vector_pictures(fn(_, _) { None })
}
