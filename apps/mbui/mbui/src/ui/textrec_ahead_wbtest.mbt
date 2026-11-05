///|
priv struct RecordedGlyphHost {}

///|
impl @hostapi.Host for RecordedGlyphHost with font_metrics(_, _, _, _, out) {
  out[0] = 9.0
  out[1] = 3.0
  out[2] = 12.0
}

///|
impl @hostapi.Host for RecordedGlyphHost with shape(_, text, _, _, _, out) {
  for i in 0..<text.length() {
    out[i * 4] = i.to_double()
    out[i * 4 + 1] = 1.0
    out[i * 4 + 2] = 7.0
    out[i * 4 + 3] = text.at(i).to_int().to_double()
  }
  text.length()
}

///|
impl @hostapi.Host for RecordedGlyphHost with glyph(_, _, out) {
  out[2] = 7.0
  out[3] = 12.0
  out[5] = -9.0
}

///|
impl @hostapi.Host for RecordedGlyphHost with atlas_size(_, _) {
  1024
}

///|
test "recording a paragraph off screen keeps its glyphs when the replay brings it into view" {
  let paragraph = fn(root : @view.View, y : Double) {
    root.box(fn(cut) {
      cut.over(Is(true)).width(Is(Some(100.0))).height(Is(Some(60.0))).clips(Is(true)) |> ignore
      cut.box(fn(w) {
        w.offset(Is((0.0, y))).width(Is(Some(80.0))).words(Is("ab")) |> ignore
      }) |> ignore
    }) |> ignore
  }
  let host = RecordedGlyphHost::{ }
  let t = Tester::new(fn(_) { }, w=100.0, h=60.0,
    env=[("MBUI_TEXT_RECORD", "1")], live={ host, turn: fn() { } })
  t.check_looks(false)
  set_view_app(fn(root) { paragraph(root, 100.0) })
  t.draw()
  assert_eq(t.drawn_glyphs(), [], msg="the paragraph was shaped outside the screen")
  let kept = t.fake.logs.filter(fn(s) { s.has_prefix("TEXTREC ") }).join("\n")
  assert_true(kept.contains("\"ab\""), msg="the off-screen paragraph was shaped and recorded: \{t.fake.logs}")
  let replay = Tester::new(fn(_) { }, w=100.0, h=60.0, text=kept)
  set_view_app(fn(root) { paragraph(root, 0.0) })
  replay.draw()
  assert_true(!replay.drawn_glyphs().is_empty())
  assert_eq(replay.text_missing(), [], msg="the recorded paragraph can be drawn in another timing: \{replay.text_missing()}")
}
