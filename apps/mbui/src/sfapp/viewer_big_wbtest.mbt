// A picture too big to show (past big_file): the viewer tells of it (its name, size and kind) with 下载, never its
// picture, the old frame's; read whole once 下载 is pressed (a drive's: Viewer::ask_save), it is told of still, and
// nothing offers to mark a picture it does not show. One it shows is the window's tree's (viewer_tree.mbt).

///|
/// The buttons read out now.
fn buttons_said(t : @ui.Tester) -> Array[String] {
  t.semantics().filter(fn(s) { s.role == @ui.Role::Button }).map(fn(s) { s.label })
}

///|
/// What offers `label` (the system's bars' `id` where they hold its actions, an iPhone Duo's on its side: `native`).
fn big_offers(t : @ui.Tester, native : Bool, label : String, id : String) -> Bool {
  if native {
    t.nav_said().contains("\"" + id + "\"")
  } else {
    buttons_said(t).contains(label)
  }
}

///|
/// A picture too big to show, from a drive, open in a window `w` × `h` (beside an iPhone Duo's own bars on its side,
/// `native`, its actions in them once it is read): told of with 下载 on it; read whole once that is pressed, told of
/// still; 标注图片 offered neither before nor after.
fn big_picture_told_of(w : Double, h : Double, native : Bool) -> Unit raise {
  let at = (w, h, native)
  new_run()
  let src = fixture("drive")
  let t = if native {
    @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform=1, nav_able=true)
  } else {
    @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~)
  }
  if native {
    t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":20,\"left\":0,\"right\":84}}")
  }
  t.draw()
  let big : @sfbase.DriveFile = {
    station: "ws1/st1",
    root: "~",
    path: "照片/全景.png",
    name: "全景.png",
    size: big_file * 2.0,
    mtime: 1792300000000.0,
    kind: "image",
    mime: "image/png",
  }
  open_drive_file(big, [])
  t.draw()
  t.run_for(@ui.move_most_ms)
  let v = viewer.get().unwrap()
  assert_true(v.shown_kind() == Some(KImage) && v.file.size > big_file && v.told_of(), msg="\{at}: told of, the old frame's")
  assert_true(v.bytes.get() is None, msg="\{at}: not read before 下载")
  // (下载 its told of's own, on the stage, whatever bars there are: those beside the system's hold none while it comes,
  // Viewer::coming)
  assert_true(buttons_said(t).contains("下载"), msg="\{at}: 下载 offered: \{buttons_said(t)}")
  assert_true(!big_offers(t, native, "标注图片", "over/mark"), msg="\{at}: 标注图片 not offered: \{buttons_said(t)} \{t.nav_said()}")
  t.click(@ui.Role::Button, label="下载")
  t.run_for(@ui.move_most_ms)
  assert_true(v.bytes.get() is Some(_), msg="\{at}: read whole once 下载 is pressed")
  assert_true(v.told_of(), msg="\{at}: told of still")
  assert_true(big_offers(t, native, "下载", "over/download"), msg="\{at}: 下载 offered still: \{buttons_said(t)} \{t.nav_said()}")
  assert_true(!big_offers(t, native, "标注图片", "over/mark"), msg="\{at}: 标注图片 not offered, its picture not shown: \{buttons_said(t)} \{t.nav_said()}")
  assert_true(!marking.on, msg="\{at}: not marking")
}

///|
test "a picture too big to show, from a drive, narrow: told of with 下载; read whole once 下载 is pressed, told of still; 标注图片 offered neither before nor after" {
  big_picture_told_of(390.0, 844.0, false)
}

///|
test "a picture too big to show, from a drive, wide: told of with 下载; read whole once 下载 is pressed, told of still; 标注图片 offered neither before nor after" {
  big_picture_told_of(1200.0, 844.0, false)
}

///|
test "a picture too big to show, from a drive, beside an iPhone Duo's own bars: told of with 下载 on it; read whole once that is pressed, told of still, 下载 handed them then; 标注图片 handed them neither before nor after" {
  big_picture_told_of(951.0, 669.0, true)
}
