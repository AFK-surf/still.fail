// The composer's unopened picture and file card take the pointer without passing a press to its field.

///|
fn disabled_picture_cursor(w : Double, h : Double) -> (String, Bool, String, Bool) {
  let t = wide_tester([], mode="chat-attach-pic", w~, h~, platform=0)
  t.run_for(@ui.move_most_ms * 2.0)
  // The picture itself has no label; its remove button is at its upper end. Stay outside that button's reach.
  let (rx, ry, _, _) = t.query(Button, label="移除 compare.png").unwrap().rect
  let (px, py) = (rx - 20.0, ry + 25.0)
  let (x, y, wide, high) = t.query(Group, label="build.log").unwrap().rect
  let (fx, fy) = (x + wide / 2.0, y + high / 2.0)
  t.move(px, py)
  t.frame()
  let picture = ("\{t.cursor()}", @ui.view_tree().unwrap().target_at(px, py) is Off(_))
  t.move(fx, fy)
  t.frame()
  let file = ("\{t.cursor()}", @ui.view_tree().unwrap().target_at(fx, fy) is Off(_))
  println("PICTURECURSOR \{(w, h)} picture=\{picture} file=\{file}")
  (picture.0, picture.1, file.0, file.1)
}

///|
test "unavailable composer picture and file take the pointer on a narrow screen" {
  assert_eq(disabled_picture_cursor(390.0, 844.0), ("Arrow", true, "Arrow", true))
}

///|
test "unavailable composer picture and file take the pointer on a wide screen" {
  assert_eq(disabled_picture_cursor(1280.0, 800.0), ("Arrow", true, "Arrow", true))
}
