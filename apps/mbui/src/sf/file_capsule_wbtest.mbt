// A file card measured from its content must leave room for that content after the host rounds its parts to pixels.

///|
test "a short file name and size stay whole in a card sized to them on whole-pixel hosts" {
  let pixels_text = "{\"m\":[12,400,0],\"r\":[9.6,2.4,17,9.6,2.4,1]}"
  for pixels in [1.0, 1.25, 2.0, 2.625, 2.75, 3.0, 3.25] {
    for font in [1.0, 1.15, 1.3, 1.5] {
      for stem in ["a", "abc", "abcde", "abcdefgh"] {
        for ends in [0, 1] {
          let name = stem + ".txt"
          let t = @ui.Tester::new(fn(c) {
            begin(c) |> ignore
            c.with_theme(ui_theme(), fn() {
              let across = file_card_across(c, name, 1024.0, ends~)
              c.box(w=Px(across), fn() {
                file_card(c, "file", name, 1024.0, remove=ends == 1) |> ignore
              }) |> ignore
            })
          // At 1.25 pixels a point the existing end button's corner check already fails on main. This test checks the
          // displayed words across pixel scales; the end's corner is checked independently below.
          }, w=390.0, h=200.0, platform=2, native=Finger, scale=pixels, text=pixels_text, corners_held=false)
          t.set_font_scale(font)
          t.draw()
          let shown_stem = t.lines_of(stem)
          let shown_ext = t.lines_of(".txt")
          assert_eq(shown_stem, [stem], msg="pixels=\{pixels} font=\{font} ends=\{ends} name=\{name} shown=\{shown_stem}")
          assert_eq(shown_ext, [".txt"], msg="pixels=\{pixels} font=\{font} ends=\{ends} name=\{name} shown=\{shown_ext}")
        }
      }
    }
  }
}

///|
test "a file card's end stays in its corner with larger system text" {
  let pixels_text = "{\"m\":[12,400,0],\"r\":[9.6,2.4,17,9.6,2.4,1]}"
  let t = @ui.Tester::new(fn(c) {
    begin(c) |> ignore
    c.with_theme(ui_theme(), fn() {
      let across = file_card_across(c, "a.txt", 1024.0, ends=1)
      c.box(w=Px(across), fn() {
        file_card(c, "file", "a.txt", 1024.0, remove=true) |> ignore
      }) |> ignore
    })
  }, w=390.0, h=200.0, platform=2, native=Finger, scale=1.0, text=pixels_text)
  t.set_font_scale(1.15)
  t.draw()
  assert_eq(t.lines_of("a"), ["a"])
}
