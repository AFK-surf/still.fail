// A station's file in the draft, its card pressed (sfpages composer_ref.mbt): its panel on each screen (a sheet from
// the foot with a finger, beside its card with a mouse, a dialog in the window's middle where nothing opened it), what
// it says and what its parts do, over the fixture's chat (chat-station-file: 发布清单.md sent as a file, 设计稿 a
// folder as a zip, both on the chat's own station).

///|
/// The chat with the fixture's two station files in its draft, in a window as `platform` and `wide` say (a phone's
/// 390×844, or 1200×800), its calls kept in `calls`, its source in `src`; at rest.
fn ref_chat(calls : Array[Made], src : Ref[Source?], platform~ : Int, wide~ : Bool) -> @ui.Tester {
  @sf.presenters_reset()
  let t = wide_tester(
    calls,
    mode="chat-station-file",
    w=if wide { 1200.0 } else { 390.0 },
    h=if wide { 800.0 } else { 844.0 },
    platform~,
    before=fn(s) {
      src.val = Some(s)
      // (as the screen's fixture puts them in: open_fixture_mode's chat-station-file)
      @sffixture.fix_draft_ref("ws1/st1:s-c1", "发布清单.md", false, 4210.0, "file", true)
      @sffixture.fix_draft_ref("ws1/st1:s-c1", "设计稿", true, 0.0, "file", false)
    },
  )
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// Where `words` are drawn whole and seen, the lowest of them (the composer's, under what the chat shows).
fn ref_words_at(t : @ui.Tester, words : String) -> (Double, Double, Double, Double)? {
  let mut at = None
  for w in t.words() {
    if w.0 == words && w.5 > 0.5 {
      match at {
        Some((_, y, _, _)) if y >= w.2 => ()
        _ => at = Some((w.1, w.2, w.3, w.4))
      }
    }
  }
  at
}

///|
/// `words` pressed where they are drawn (ref_words_at's).
fn ref_tap(t : @ui.Tester, words : String) -> Unit raise {
  guard ref_words_at(t, words) is Some((x, y, w, h)) else {
    fail("no \{words} drawn: " + t.words().map(fn(w) { w.0 }).join("|"))
  }
  t.tap(x + w / 2.0, y + h / 2.0)
}

///|
/// The card of 发布清单.md pressed: its panel, at the frame it opened in.
fn ref_open(t : @ui.Tester) -> Unit raise {
  ref_tap(t, "发布清单")
  t.draw()
}

///|
/// Each screen the panel opens on from its card: a phone with a finger (a sheet), a phone's width with a mouse and a
/// desktop's window (beside its card).
let ref_screens : Array[(String, Int, Bool)] = [("sheet", 2, false), ("mouse", 0, false), ("wide", 0, true)]

///|
/// The panel closed as each screen closes it (the system's back with a finger, Escape with a mouse), gone at rest.
fn ref_close(t : @ui.Tester, platform : Int, at : String) -> Unit raise {
  if platform == 2 {
    t.back()
  } else {
    t.key(@ui.key_escape)
  }
  t.run_for(@ui.move_most_ms)
  assert_false(@sf.presented_drawn(), msg="\{at}: closed")
  assert_true(ref_words_at(t, "发送方式") is None, msg="\{at}: its words gone")
}

///|
test "a station's file's card pressed: its panel says where it is, how it goes and this chat's say, one under another, on every screen" {
  for s in ref_screens {
    let (at, platform, wide) = s
    let calls : Array[Made] = []
    let src : Ref[Source?] = Ref(None)
    let t = ref_chat(calls, src, platform~, wide~)
    ref_open(t)
    t.run_for(@ui.move_most_ms)
    assert_true(@sf.presented_open_of(@sf.last_presented()), msg="\{at}: open")
    guard ref_words_at(t, "发布清单.md") is Some((_, title_y, _, _)) else { fail("\{at}: no title") }
    // where it is: its station and its folder, under its title
    let where_ = t.words().filter(fn(w) { w.0.has_prefix("Willow · ") && w.0 != "Willow · 文件" && w.5 > 0.5 })
    assert_eq(where_.length(), 1, msg="\{at}: where it is: \{Repr(where_.map(fn(w) { w.0 }))}")
    assert_true(where_[0].2 > title_y, msg="\{at}: where it is under its title")
    guard ref_words_at(t, "发送方式") is Some((how_x, how_y, _, _)) else { fail("\{at}: no 发送方式") }
    assert_true(how_y > where_[0].2, msg="\{at}: how it goes under where it is")
    // (each on the panel's words' line)
    assert_eq(how_x, where_[0].1, msg="\{at}: where it is and how it goes on one line")
    guard ref_words_at(t, "此对话默认发送文件") is Some((_, say_y, _, _)) else { fail("\{at}: no chat's say") }
    // its two ways side by side under 发送方式, the chat's say under them
    let ways = t.words().filter(fn(w) { (w.0 == "路径" || w.0 == "文件") && w.2 > how_y && w.2 < say_y && w.5 > 0.5 })
    assert_eq(ways.length(), 2, msg="\{at}: its ways: \{Repr(ways.map(fn(w) { w.0 }))}")
    assert_eq(ways[0].2, ways[1].2, msg="\{at}: side by side")
    ref_close(t, platform, at)
  }
}

///|
test "how it goes picked in its panel: the draft told (composer.mode), by path or as the file; this chat's say turned: prefs.set" {
  for s in ref_screens {
    let (at, platform, wide) = s
    let calls : Array[Made] = []
    let src : Ref[Source?] = Ref(None)
    let t = ref_chat(calls, src, platform~, wide~)
    ref_open(t)
    t.run_for(@ui.move_most_ms)
    guard ref_words_at(t, "发送方式") is Some((_, how_y, _, _)) else { fail("\{at}: no 发送方式") }
    let path = t.words().filter(fn(w) { w.0 == "路径" && w.2 > how_y && w.5 > 0.5 })
    assert_eq(path.length(), 1, msg=at)
    t.tap(path[0].1 + path[0].3 / 2.0, path[0].2 + path[0].4 / 2.0)
    t.run_for(@ui.move_most_ms)
    let told = named(calls, "composer.mode")
    assert_eq(told.length(), 1, msg="\{at}: told once")
    assert_eq(text(Some(told[0].params), "id"), "ref-发布清单.md", msg=at)
    assert_eq(text(Some(told[0].params), "mode"), "path", msg=at)
    assert_eq(text(Some(told[0].params), "key"), "ws1/st1:s-c1", msg=at)
    // (the way it goes already: nothing told)
    let file = t.words().filter(fn(w) { w.0 == "文件" && w.2 > how_y && w.5 > 0.5 })
    t.tap(file[0].1 + file[0].3 / 2.0, file[0].2 + file[0].4 / 2.0)
    t.run_for(@ui.move_most_ms)
    assert_eq(named(calls, "composer.mode").length(), 1, msg="\{at}: the way it goes picked: nothing more told")
    // this chat's say: the switch alone answers
    let before = named(calls, "prefs.set").length()
    t.click(Switch, label="此对话默认发送文件")
    t.run_for(@ui.move_most_ms)
    let set = named(calls, "prefs.set")
    assert_eq(set.length(), before + 1, msg="\{at}: prefs.set once")
    assert_eq(field(field(Some(set[before].params), "dropFiles"), "ws1/st1:s-c1"), Some(Json::boolean(true)), msg=at)
    assert_true(@sf.presented_open_of(@sf.last_presented()), msg="\{at}: still open")
    ref_close(t, platform, at)
  }
}

///|
test "a folder's card pressed: how it goes by its path or as a zip" {
  for s in ref_screens {
    let (at, platform, wide) = s
    let calls : Array[Made] = []
    let src : Ref[Source?] = Ref(None)
    let t = ref_chat(calls, src, platform~, wide~)
    ref_tap(t, "设计稿")
    t.draw()
    t.run_for(@ui.move_most_ms)
    guard ref_words_at(t, "发送方式") is Some((_, how_y, _, _)) else { fail("\{at}: no 发送方式") }
    let ways = t.words().filter(fn(w) { (w.0 == "路径" || w.0 == "zip") && w.2 > how_y && w.5 > 0.5 })
    assert_eq(ways.map(fn(w) { w.0 }), ["路径", "zip"], msg=at)
    t.tap(ways[0].1 + ways[0].3 / 2.0, ways[0].2 + ways[0].4 / 2.0)
    t.run_for(@ui.move_most_ms)
    let told = named(calls, "composer.mode")
    assert_eq(told.length(), 1, msg=at)
    assert_eq(text(Some(told[0].params), "id"), "ref-设计稿", msg=at)
    assert_eq(text(Some(told[0].params), "mode"), "path", msg=at)
    ref_close(t, platform, at)
  }
}

///|
test "its panel put up from no card (a screen's fixture): a sheet with a finger, a dialog in the window's middle with a mouse" {
  for s in [("sheet", 2, false), ("dialog", 0, true)] {
    let (at, platform, wide) = s
    let calls : Array[Made] = []
    let src : Ref[Source?] = Ref(None)
    let t = ref_chat(calls, src, platform~, wide~)
    @sfpages.ref_panel_put(src.val.unwrap(), "ws1/st1:s-c1", "ws1/st1", "ref-发布清单.md", "发布清单.md")
    t.draw()
    t.run_for(@ui.move_most_ms)
    guard ref_words_at(t, "发布清单.md") is Some((_, title_y, _, _)) else { fail("\{at}: no title") }
    guard ref_words_at(t, "发送方式") is Some((_, how_y, _, _)) else { fail("\{at}: no 发送方式") }
    guard ref_words_at(t, "此对话默认发送文件") is Some((_, say_y, _, _)) else { fail("\{at}: no chat's say") }
    assert_true(title_y < how_y && how_y < say_y, msg=at)
    ref_close(t, platform, at)
  }
}

///|
test "the file taken out of the draft while its panel is open: the panel closes, what it said kept whole as it goes" {
  for s in ref_screens {
    let (at, platform, wide) = s
    let calls : Array[Made] = []
    let src : Ref[Source?] = Ref(None)
    let t = ref_chat(calls, src, platform~, wide~)
    ref_open(t)
    t.run_for(@ui.move_most_ms)
    let panel = @sf.last_presented()
    let s = src.val.unwrap()
    @sfbase.writing_remove(s, @sfbase.writing(s, "ws1/st1:s-c1"), "ref-发布清单.md")
    t.draw()
    assert_false(@sf.presented_open_of(panel), msg="\{at}: closing")
    // (as it goes: all it said, not emptied under its title)
    assert_true(ref_words_at(t, "发送方式") is Some(_), msg="\{at}: 发送方式 kept as it goes")
    assert_true(ref_words_at(t, "此对话默认发送文件") is Some(_), msg="\{at}: its say kept as it goes")
    t.run_for(@ui.move_most_ms)
    assert_false(@sf.presented_drawn(), msg="\{at}: gone")
    assert_true(ref_words_at(t, "发布清单.md") is None, msg="\{at}: its title gone")
  }
}
