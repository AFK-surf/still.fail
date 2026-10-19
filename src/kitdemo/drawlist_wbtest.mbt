///|
test "the controls page's last frame as a draw list: a line an instance, every glyph named by what the host shaped" {
  let t = @ui.Tester::new(fn(c) { gallery(c, "controls") }, w=960.0, h=720.0, text=run_mini1_controls, scale=1.0, time=7950001676.833502 - 16.0, stable=true)
  t.replay_frames(run_mini1_controls) |> ignore
  let dl = t.drawlist()
  let lines = dl.split("\n").map(fn(l) { l.to_string() }).to_array()
  assert_eq(lines[0], "mbui-dl 1")
  assert_eq(lines[1], "window 960 720 1")
  let insts = lines.filter(fn(l) { l.has_prefix("i ") })
  assert_true(insts.length() > 100)
  assert_true(insts.iter().all(fn(l) { l.split(" ").count() == 25 }))
  let glyphs = lines.filter(fn(l) { l.has_prefix("glyph ") })
  assert_true(glyphs.length() > 20)
  // named: a key the host gave, its font, the cluster and words it shaped
  let unnamed = glyphs.filter(fn(l) { l.contains(" -1 0 0 0 -1 ") || l.has_suffix(" \"\"") })
  assert_eq(unnamed, [])
  // the same frame, the same list
  assert_eq(t.drawlist(), dl)
}
