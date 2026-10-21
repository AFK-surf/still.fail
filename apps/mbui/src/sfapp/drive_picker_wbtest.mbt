// The folder picker (drive_sheets.mbt picker_sheet) over a core that answers between frames, as a real one does: its
// answer is taken by the frame after the one that asked (the outside standing for the core: `answer`).

///|
/// The app over the drive's fixture, `drive.folders` asked kept and answered only when the test says (between
/// frames), the others at once.
fn picker_tester(asks : Array[Json], pending : Array[() -> Unit]) -> @ui.Tester {
  reset()
  let base = fixture("files")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      if name == "drive.folders" {
        asks.push(params)
        pending.push(fn() { (base.call)(name, params, done) })
      } else {
        (base.call)(name, params, done)
      }
    },
  }
  open_drive_fixture("files")
  @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
}

///|
/// What the core said by now, taken by the next frame.
fn answer(t : @ui.Tester, pending : Array[() -> Unit]) -> Unit {
  let now = pending.copy()
  pending.clear()
  for p in now {
    p()
  }
  t.draw()
}

///|
/// On to where the drive's sheet rests (kit's sheet_rest), when it moves.
fn run_to_sheet(t : @ui.Tester) -> Unit {
  let e = @kit.sheet_rest("dv-sheet")
  if e > t.time() && e < 1.0e300 {
    t.run_for(e - t.time())
  }
}

///|
/// A tap on the last drawn of the words exactly `w` (the sheet's, over the page).
fn tap_sheet_words(t : @ui.Tester, w : String) -> Unit {
  let at = t.locate("=" + w)
  let (x, y) = at[at.length() - 1]
  t.tap(x, y)
}

///|
test "the folder picker asks for a place's folders once: opened, its answer between frames, a step of its way" {
  let asks : Array[Json] = []
  let pending : Array[() -> Unit] = []
  let t = picker_tester(asks, pending)
  t.run_for(@ui.nav_push_ms)
  // opened (as 选择文件夹 does): the station's home asked, once
  dv_open_picker(t.ctx(), "ws1/st1", [])
  t.draw()
  assert_eq(asks.length(), 1)
  answer(t, pending)
  run_to_sheet(t)
  assert_true(t.find("文档") is Some(_))
  assert_eq(asks.length(), 1)
  // into a folder: that folder asked, once
  tap_sheet_words(t, "文档")
  answer(t, pending)
  assert_eq(asks.length(), 2)
  assert_eq(text(Some(asks[1]), "path"), "/Users/lin/文档")
  // back by its way's first step: the home asked, once
  tap_sheet_words(t, "lin")
  answer(t, pending)
  assert_eq(asks.length(), 3)
  assert_eq(text(Some(asks[2]), "path"), "/Users/lin")
  assert_eq(pending.length(), 0)
}

///|
test "文件's folder picker is drawn over 文件 alone while a drive's page slides in over it (one filter field)" {
  let asks : Array[Json] = []
  let pending : Array[() -> Unit] = []
  let t = picker_tester(asks, pending)
  t.run_for(@ui.nav_push_ms)
  // opened from 文件 (its ＋ is in its build), then a station's drive pushed over it: both pages drawn while it
  // slides in; before, each drew the sheet, and the filter's one Field went to two editors in one build
  dv.building = dv_page_of(None)
  dv_open_picker(t.ctx(), "ws1/st1", [])
  answer(t, pending)
  app.nav.push(Drive({ station: "ws1/st1", root: None, path: "" }))
  t.draw()
  t.run_for(@ui.nav_push_ms / 2.0)
  assert_eq(t.locate("=" + tr("android-misc.drive.pick.title")).length(), 1)
}
