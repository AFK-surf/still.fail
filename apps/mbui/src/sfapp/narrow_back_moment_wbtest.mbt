// Back at the narrow stack's root as the place in view changes (a tab of the bottom bar pressed), told and taken at
// that moment, no frame drawn between: from the chats to 文件 the host told back is the app's and back goes to the
// chats; from 文件 to the chats the host told it is not, nothing kept of 文件's way back to take it. With touch and
// with keyboard and mouse (a narrow window).

///|
/// The fixture's chat laid out Small on `platform` in a window `w` × `h`, popped to the chats' list.
fn narrow_at_chats(platform : Int, w : Double, h : Double, width : String, height : String) -> @ui.Tester raise {
  let t = tape_chat(platform, w, h, width~, height~)
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Home && app.nav.depth() == 1, msg="at the chats")
  t
}

///|
/// The bottom bar's tab said `label` pressed and let go at `at`, as the host hands it on, no frame drawn.
fn tab_at(t : @ui.Tester, label : String, at : Double) -> Unit raise {
  match said_at(t, label) {
    Some((x, y, w, h)) => {
      t.touch_at(0, x + w / 2.0, y + h / 2.0, at)
      t.touch_at(2, x + w / 2.0, y + h / 2.0, at)
    }
    None => fail("nothing said \{label}")
  }
}

///|
let narrow_cases : Array[(Int, Double, Double, String, String)] = [
  (2, 390.0, 844.0, "compact", "medium"),
  (0, 500.0, 800.0, "", ""),
]

///|
test "laid out Small, the chats to 文件 by its tab, back at once with no frame between: the host told back is the app's, and back goes to the chats" {
  for case in narrow_cases {
    let (platform, w, h, width, height) = case
    let t = narrow_at_chats(platform, w, h, width, height)
    let at = t.time()
    tab_at(t, "文件", at)
    let files = app.nav.top() == Files
    let told = t.takes_back()
    t.back_raw(2, 0.0, at)
    // (gone back as it is taken, before any frame; and so once frames are drawn)
    let now = (app.nav.top() == Home, app.nav.depth())
    t.draw()
    t.run_for(@ui.move_most_ms)
    assert_eq(
      (files, told, now, app.nav.top() == Home, app.nav.depth()),
      (true, true, (true, 1), true, 1),
      msg="platform \{platform}",
    )
  }
}

///|
test "laid out Small, 文件 to the chats by their tab, at once with no frame between: the host told back is not the app's" {
  for case in narrow_cases {
    let (platform, w, h, width, height) = case
    let t = narrow_at_chats(platform, w, h, width, height)
    tap_said(t, "文件")
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.top() == Files && t.takes_back(), msg="at 文件")
    let at = t.time()
    tab_at(t, "对话", at)
    let chats = app.nav.top() == Home
    let told = t.takes_back()
    assert_eq((chats, told), (true, false), msg="platform \{platform}")
  }
}

///|
/// 文件 at the narrow stack's root on `platform` in a window `w` × `h` (the home fixture), its source.
fn narrow_at_files(platform : Int, w : Double, h : Double, width : String, height : String) -> (@ui.Tester, Source) raise {
  new_run()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  if width != "" {
    say_room(t, width, height)
  }
  app.nav.replace(Files)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Files && app.nav.depth() == 1 && t.takes_back(), msg="at 文件")
  (t, src)
}

///|
test "laid out Small, 文件 with a presenter over it (Pin 文件夹's): back closes that alone, 文件 kept; back again goes to the chats" {
  for case in narrow_cases {
    let (platform, w, h, width, height) = case
    let (t, src) = narrow_at_files(platform, w, h, width, height)
    @sfdesk.add_folder(src, "ws1", @sfdesk.pin_stations(src, "ws1"))
    t.run_for(@ui.move_most_ms)
    let shown = @sf.presenting() && t.find("选择一台 station，然后选择其中要 pin 的文件夹") is Some(_)
    t.back_raw(2, 0.0, t.time())
    t.run_for(@ui.move_most_ms)
    let first = (@sf.presenting(), app.nav.top() == Files)
    t.back_raw(2, 0.0, t.time())
    t.run_for(@ui.move_most_ms)
    assert_eq((shown, first, app.nav.top() == Home), (true, (false, true), true), msg="platform \{platform}")
  }
}

///|
/// At 文件, the system's back gesture begun at `at`, `meanwhile` done at the same moment, then the gesture let go there:
/// whether the stack's top is `top`, and how deep it is.
fn files_gesture(platform : Int, w : Double, h : Double, width : String, height : String, top : Page, meanwhile : (@ui.Tester) -> Unit) -> (Bool, Int) raise {
  let (t, _) = narrow_at_files(platform, w, h, width, height)
  let at = t.time()
  t.back_raw(0, 0.0, at)
  t.back_raw(1, 120.0, at)
  meanwhile(t)
  t.back_raw(2, 120.0, at)
  t.draw()
  t.run_for(@ui.move_most_ms)
  (app.nav.top() == top, app.nav.depth())
}

///|
test "laid out Small, a back gesture begun at 文件: let go, to the chats; the chats come by their tab meanwhile, or a page pushed, the gesture let go does nothing to what came" {
  for case in narrow_cases {
    let (platform, w, h, width, height) = case
    // (the gesture as it goes: taken by the root's back)
    let plain = files_gesture(platform, w, h, width, height, Home, fn(_t) {  })
    let tabbed = files_gesture(platform, w, h, width, height, Home, fn(t) { try! tab_at(t, "对话", t.time()) })
    let pushed = files_gesture(platform, w, h, width, height, Archived, fn(_t) { @sfbase.open_page(Archived) })
    assert_eq(
      (plain, tabbed, pushed),
      ((true, 1), (true, 1), (true, 2)),
      msg="platform \{platform}",
    )
  }
}
