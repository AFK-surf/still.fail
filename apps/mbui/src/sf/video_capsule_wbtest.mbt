// The compact video label must say its whole time or progress, including on screens with fractional pixel scales and
// when the system makes words larger. Looking up the original text alone does not tell what survived layout.

///|
test "a video capsule shows the whole duration at the system's text and pixel scales" {
  for pixels in [1.0, 1.25, 2.0, 2.75, 3.0] {
    for font in [1.0, 1.15, 1.3, 1.5, 2.0] {
      for ms in [5500.0, 72500.0, 3605000.0] {
        let t = @ui.Tester::new(fn(c) {
          begin(c) |> ignore
          c.with_theme(ui_theme(), fn() {
            c.box(w=Px(200.0), h=Px(160.0), fn() { video_capsule(c, "duration", ms) }) |> ignore
          })
        }, w=390.0, h=844.0, platform=2, native=Finger, scale=pixels)
        t.set_font_scale(font)
        t.draw()
        let expected = clock(ms)
        assert_eq(t.lines_of(expected), [expected], msg="pixels=\{pixels} font=\{font} duration=\{ms}")
      }
    }
  }
}

///|
test "a video capsule shows the whole duration when the host rounds layout to pixels" {
  // A host's metrics say it lays out in whole pixels, as Android does. Other shapes fall back to the test face.
  let pixels_text = "{\"m\":[12,400,0],\"r\":[9.6,2.4,17,9.6,2.4,1]}"
  for pixels in [1.0, 1.25, 2.0, 2.625, 2.75, 3.0, 3.25] {
    for font in [1.0, 1.15, 1.3, 1.5, 2.0] {
      for ms in [5500.0, 72500.0, 3605000.0] {
        let t = @ui.Tester::new(fn(c) {
          begin(c) |> ignore
          c.with_theme(ui_theme(), fn() {
            c.box(w=Px(200.0), h=Px(160.0), fn() { video_capsule(c, "duration", ms) }) |> ignore
          })
        }, w=390.0, h=844.0, platform=2, native=Finger, scale=pixels, text=pixels_text)
        t.set_font_scale(font)
        t.draw()
        let expected = clock(ms)
        assert_eq(t.lines_of(expected), [expected], msg="pixels=\{pixels} font=\{font} duration=\{ms}")
      }
    }
  }
}

///|
test "a short duration stays whole at a 3.25 pixel scale with fractional glyph advances" {
  // A whole-pixel host and a plausible tabular face, whose advances do not themselves fall on the pixel grid.
  let text = "{\"m\":[12,400,0],\"r\":[9.6,2.4,17,9.6,2.4,1]}\n" +
    "{\"s\":[12,400,32,\"0:06\"],\"r\":[0,1,6.7,48,1,1,4.12,58,2,1,6.7,48,3,1,6.7,54]}"
  let t = @ui.Tester::new(fn(c) {
    begin(c) |> ignore
    c.with_theme(ui_theme(), fn() {
      c.box(w=Px(200.0), h=Px(160.0), fn() { video_capsule(c, "fractional-duration", 5500.0) }) |> ignore
    })
  }, w=351.0, h=805.0, platform=2, native=Finger, scale=3.25, text~)
  t.draw()
  assert_eq(t.lines_of("0:06"), ["0:06"])
}

///|
test "a video capsule shows the whole download percentage on whole-pixel hosts" {
  let pixels_text = "{\"m\":[12,400,0],\"r\":[9.6,2.4,17,9.6,2.4,1]}"
  for pixels in [1.0, 1.25, 2.625, 3.25] {
    for font in [1.0, 1.3, 1.5] {
      for (part, expected) in [(0.0, "0%"), (0.2, "20%"), (0.99, "99%"), (1.0, "100%")] {
        let t = @ui.Tester::new(fn(c) {
          begin(c) |> ignore
          c.with_theme(ui_theme(), fn() {
            c.box(w=Px(200.0), h=Px(160.0), fn() {
              video_capsule(c, "progress/" + expected, 5500.0, coming=Some(part))
            }) |> ignore
          })
        }, w=390.0, h=844.0, platform=2, native=Finger, scale=pixels, text=pixels_text)
        t.set_font_scale(font)
        t.draw()
        assert_eq(t.lines_of(expected), [expected], msg="pixels=\{pixels} font=\{font} progress=\{expected}")
      }
    }
  }
}
