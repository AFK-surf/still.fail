// The sidebar's panel on a tape 600 wide: what it draws cut to its column, as the old view in a box of its own was.

///|
/// The clips of what is drawn at the sidebar's panel (6 in, 297 wide) in a clip, from the draw list: x0 y0 x1 y1.
fn side_panel_clips(t : @ui.Tester) -> Array[String] {
  let out = []
  for line in t.drawlist().split("\n") {
    let f = line.split(" ").map(fn(s) { s.to_string() }).collect()
    if f.length() > 20 && f[0] == "i" && f[1] == "6" && f[3] == "297" && f[19] != "1000000000" {
      out.push(f[17] + " " + f[18] + " " + f[19] + " " + f[20])
    }
  }
  out
}

///|
test "the sidebar's panel on a tape 600 wide is cut at its column, its shadow none of the gap's past it" {
  for platform in [0, 2] {
    let t = wide_tester([], mode="home", w=600.0, h=844.0, platform~)
    t.run_for(@ui.move_most_ms * 2.0)
    // (its shadow, its ground and its edge, each cut 311 across: the column's 6 + 297 + 8)
    assert_eq(side_panel_clips(t), ["0 0 311 844", "0 0 311 844", "0 0 311 844"])
  }
}
