// 中屏's page panel's line takes no room: what it holds is laid out to its edge, under its line, and cut at its edge
// (mbui's push_box_clip), not at the line's inside. Cut there, a chat's rows across the panel were cut a point at each
// side, none ever wholly inside the clip it is painted in (so none kept as drawn: mbui's Ctx::paint_list_row).

///|
test "中屏: a chat's rows across the page panel lie inside what it cuts them to, left and right" {
  let t = kept_rows_open("chat", 720.0, 800.0)
  // (the panel's clip: of the round ones what is drawn is cut by, the widest)
  let mut pane : (Double, Double, Double, Double)? = None
  for inst in t.drawn_instances() {
    let r = dmax(dmax(inst[24], inst[25]), dmax(inst[26], inst[27]))
    if r >= 30.0 {
      let w = inst[18] - inst[16]
      match pane {
        Some(p) if p.2 - p.0 >= w => ()
        _ => pane = Some((inst[16], inst[17], inst[18], inst[19]))
      }
    }
  }
  guard pane is Some((x0, _, x1, _)) else { fail("no round clip of the page panel drawn") }
  // (the rows of the lists laid out across it: from its left)
  let mut across = 0
  for rows in t.list_row_boxes() {
    for row in rows {
      let (x, _, w, _) = row
      if (x - x0).abs() <= 4.0 && w >= (x1 - x0) / 2.0 {
        across += 1
        assert_true(x >= x0 && x + w <= x1, msg="a row at \{x} \{w} wide, the panel cutting at \{x0} to \{x1}")
      }
    }
  }
  assert_true(across >= 3, msg="the chat's rows across the panel: \{across}")
}
