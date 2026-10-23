// The actual core answer also drawn by Android's FormulaTest and the web. The optional draw lists are rendered by
// the host's offscreen GPU renderer for inspection, not pictures of a whole app on a device.
///|
test "core formulas use the packaged outlines, retain source and share the text baseline" {
  let fixture = @json.parse(math_fixture)
  let text = math_string(math_field(fixture, "text"))
  let tree = math_field(fixture, "md")
  for dark in [false, true] {
    let t = @ui.Tester::new(fn(c) {
      set_dark(Some(dark))
      let look = begin(c)
      c.set_clear((look.p.bg >> 8) & 0xFFFFFFL)
      c.box(w=Fill(1.0), h=Fill(1.0), bg=look.p.bg, pad=24.0, fn() {
        markdown(c, text, tree=Some(tree), size=18.0) |> ignore
      }) |> ignore
    }, w=390.0, h=540.0, scale=2.0, text=math_text)
    t.draw()
    assert_eq(t.text_missing(), [])
    let (lay,_,_) = t.rich_of("Inline ").unwrap()
    assert_eq(t.run_rects("E=mc^2").length(), 1)
    assert_true(t.find("Invalid ") is Some(_))
    let blocks = core_blocks(math_array(tree), text)
    guard blocks[0] is Paragraph(xs) else { fail("missing inline formula") }
    guard xs[1] is Formula(source,drawing) else { fail("missing core formula") }
    let d = math_inline(drawing).unwrap()
    assert_eq(source,"E=mc^2")
    assert_true(d.paths.length() >= 5)
    assert_true(d.width > 0.0 && d.height > 0.0)
    // TeX remains the selected/copied value; only its positioned paths are painted.
    assert_true(lay.text.contains("E=mc^2"))
    if math_evidence() != "" {
      println("DLBEGIN " + (if dark { "native-dark" } else { "native-light" }))
      println(t.drawlist(bytes=true))
      println("DLEND")
    }
  }
  set_dark(None)
}
