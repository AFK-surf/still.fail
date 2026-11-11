// ＋'s Station 文件, the station files picker (sfdesk's station_pick.mbt), on the three screens: a sheet from the foot
// with touch and with keyboard and mouse on a small window, a dialog in the middle of a wide one. The places (each
// station's name over its home and its folders), a folder gone into (the way back over it, the folder as a whole
// first, a folder entered, a file ticked), 添加 n 个 putting what is ticked into the draft, 取消; what shows while the
// stations or a folder are read the first time, where reading them fails, and where no station lends a folder.

///|
/// Willow's 文档 as the picker shows it, from its place.
fn pick_docs() -> @sfdesk.PickAt {
  { station: "ws1/st1", station_name: "Willow", root: fix_docs, root_name: "文档", path: "" }
}

///|
/// The fixture's chat open on a window of `platform` (390 by 844; `wide`: 1200 by 800), ＋'s Station 文件 opened over
/// it for draft `key` (the chat's own; `at` a folder put up in it as it opens, `ticked` ticked), the core `src_of` the
/// fixture's; at rest unless not `rest` (the frame it opened in).
fn pick_open(
  key~ : String = "ws1/st1:s-c1",
  platform~ : Int = 2,
  wide~ : Bool = false,
  at? : @sfdesk.PickAt,
  ticked? : Array[Dragged] = [],
  src_of? : (Source) -> Source = fn(s) { s },
  rest? : Bool = true,
) -> (@ui.Tester, Source) {
  new_run()
  let src = src_of(fixture("chat"))
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform~)
  if wide {
    t.resize(1200.0, 800.0)
  }
  t.draw()
  t.run_for(@ui.move_most_ms)
  @sfdesk.station_files_pick(src, key)
  match at {
    Some(a) => @sfdesk.station_pick_set(a, ticked)
    None => ()
  }
  t.draw()
  if rest {
    t.run_for(@ui.move_most_ms)
  }
  (t, src)
}

///|
/// The core with no station lending a folder: its stations' list empty.
fn pick_no_stations(base : Source) -> Source {
  {
    ..base,
    topic_read: fn(name, params) {
      if name == "stations" {
        { value: Some(Json::array([])), error: None, version: 1 }
      } else {
        base.topic(name, params).get().snapshot()
      }
    },
  }
}

///|
/// The three screens these look at: touch on a small window (a sheet), keyboard and mouse there (a sheet too), a wide
/// window (a dialog in the middle).
let pick_screens : Array[(Int, Bool)] = [(2, false), (0, false), (0, true)]

///|
/// Where the words `words` are drawn (the first of them): left, top, width, height.
fn pick_word(t : @ui.Tester, words : String) -> (Double, Double, Double, Double) {
  match t.words().iter().find_first(fn(w) { w.0 == words && w.5 > 0.0 }) {
    Some(w) => (w.1, w.2, w.3, w.4)
    None => @halt.saying("\{words} is not drawn")
  }
}

///|
/// Pressed in the middle of the words `words`, then on to where what it set off is at rest.
fn pick_press(t : @ui.Tester, words : String) -> Unit {
  let (x, y, w, h) = pick_word(t, words)
  t.tap(x + w / 2.0, y + h / 2.0)
  t.draw()
  t.run_for(@ui.move_most_ms)
}

///|
test "Station 文件: the places on each screen, each station's name over its home and its folders, Maple's saying it is away" {
  for s in pick_screens {
    let (t, _) = pick_open(platform=s.0, wide=s.1)
    let about = "platform \{s.0}, wide \{s.1}"
    for w in ["Station 文件", "所有位置", "主目录", "文档", "/Users/lin", fix_docs, "Maple · 离线", "照片", "取消", "添加"] {
      assert_true(t.find(w) is Some(_), msg="\{about}: \{w}")
    }
    // (the way first, then Willow's home, 文档 under it; Maple's name under them)
    let (way, home, docs, maple) = (pick_word(t, "所有位置"), pick_word(t, "主目录"), pick_word(t, "文档"), pick_word(t, "Maple · 离线"))
    assert_true(way.1 < home.1 && home.1 < docs.1 && docs.1 < maple.1, msg="\{about}")
    // (a place's words in from a station's name, its mark before them)
    assert_true(home.0 > maple.0, msg="\{about}: \{Repr(home)} \{Repr(maple)}")
    assert_true((docs.0 - home.0).abs() < 0.5, msg="\{about}: \{Repr(docs)} \{Repr(home)}")
    // (nothing ticked: 添加 takes no press)
    pick_press(t, "添加")
    assert_true(t.find("所有位置") is Some(_), msg="\{about}: still up")
  }
}

///|
test "Station 文件: a place pressed goes into it, the way over it; a folder entered, a step of the way pressed going back to it, 所有位置 to the places" {
  for s in pick_screens {
    let (t, _) = pick_open(platform=s.0, wide=s.1)
    let about = "platform \{s.0}, wide \{s.1}"
    pick_press(t, "文档")
    for w in ["所有位置", "Willow · 文档", "整个文件夹", "设计稿", "会议记录", "发布清单.md"] {
      assert_true(t.find(w) is Some(_), msg="\{about}: \{w}")
    }
    // (the folder as a whole first, where it is under it; then what is in it, a folder by when it changed, a file by its
    // size and when)
    let (whole, design) = (pick_word(t, "整个文件夹"), pick_word(t, "设计稿"))
    assert_true(whole.1 < design.1, msg="\{about}")
    assert_true(t.find("4.1 KB · 09:30") is Some(_) || t.find("4 KB · 09:30") is Some(_), msg="\{about}: a file's size and time")
    // (the way on its own line over them)
    let way = pick_word(t, "Willow · 文档")
    assert_true(way.1 + way.3 <= whole.1, msg="\{about}: \{Repr(way)} \{Repr(whole)}")
    pick_press(t, "设计稿")
    for w in ["Willow · 文档", "设计稿", "图标.png", "配色说明.md", "旧版"] {
      assert_true(t.find(w) is Some(_), msg="\{about}: in 设计稿, \{w}")
    }
    assert_true(t.find("发布清单.md") is None, msg="\{about}")
    pick_press(t, "Willow · 文档")
    assert_true(t.find("发布清单.md") is Some(_) && t.find("图标.png") is None, msg="\{about}: back in 文档")
    pick_press(t, "所有位置")
    assert_true(t.find("主目录") is Some(_) && t.find("整个文件夹") is None, msg="\{about}: the places again")
  }
}

///|
test "Station 文件: files ticked and the folder as a whole, 添加 n 个 counting them, ticked again let go; 添加 puts them into the draft and closes" {
  // (for another chat's draft than the one on screen, whose composer takes them: what they come to there is the
  // composer's, drive_wbtest's ＋ test)
  let key = "ws1/st1:s-c2"
  for s in pick_screens {
    let (t, _) = pick_open(key~, platform=s.0, wide=s.1, at=pick_docs())
    let about = "platform \{s.0}, wide \{s.1}"
    pick_press(t, "发布清单.md")
    assert_true(t.find("添加 1 个") is Some(_), msg="\{about}")
    pick_press(t, "整个文件夹")
    assert_true(t.find("添加 2 个") is Some(_), msg="\{about}")
    pick_press(t, "季度数据.csv")
    assert_true(t.find("添加 3 个") is Some(_), msg="\{about}")
    pick_press(t, "整个文件夹")
    assert_true(t.find("添加 2 个") is Some(_), msg="\{about}: let go")
    assert_eq(@sfbase.files_taken(key).length(), 0, msg="\{about}: nothing in the draft yet")
    pick_press(t, "添加 2 个")
    assert_eq(@sfbase.files_taken(key).map(fn(d) { d.abs }), [fix_docs + "/发布清单.md", fix_docs + "/季度数据.csv"], msg="\{about}")
    assert_true(t.find("所有位置") is None && t.find("整个文件夹") is None, msg="\{about}: closed")
  }
}

///|
test "Station 文件: 取消 closes it, nothing put into the draft" {
  for s in pick_screens {
    let (t, src) = pick_open(platform=s.0, wide=s.1, at=pick_docs())
    let about = "platform \{s.0}, wide \{s.1}"
    pick_press(t, "发布清单.md")
    pick_press(t, "取消")
    assert_true(t.find("所有位置") is None, msg="\{about}: closed")
    assert_eq(@sfbase.writing(src, "ws1/st1:s-c1").files.get().length(), 0, msg="\{about}")
  }
}

///|
test "Station 文件: a folder read the first time shows its bones, none of its entries; where reading it fails, why and 重试" {
  for s in pick_screens {
    let about = "platform \{s.0}, wide \{s.1}"
    let (t, _) = pick_open(platform=s.0, wide=s.1, at=pick_docs(), src_of=fn(b) { @sffixture.held_topics(b, ["drive"]) })
    assert_true(t.find("Willow · 文档") is Some(_), msg="\{about}: its way")
    assert_true(t.find("整个文件夹") is None && t.find("发布清单.md") is None, msg="\{about}: nothing of it yet")
    assert_true(t.find("重试") is None, msg="\{about}")
    let (t, _) = pick_open(platform=s.0, wide=s.1, at=pick_docs(), src_of=fn(b) {
      @sffixture.failed_topics(b, ["drive"], "无法读取：权限不足")
    })
    assert_true(t.find("Willow · 文档") is Some(_), msg="\{about}: its way")
    let (why, again) = (pick_word(t, "无法读取：权限不足"), pick_word(t, "重试"))
    // (why, then 重试 at the end of its line)
    assert_true((why.1 + why.3 / 2.0 - (again.1 + again.3 / 2.0)).abs() < 1.0 && again.0 > why.0 + why.2, msg="\{about}: \{Repr(why)} \{Repr(again)}")
    assert_true(t.find("整个文件夹") is None, msg="\{about}")
  }
}

///|
/// `base` with Willow's folders failing to be read, the core saying why as `why`, till it is asked to read one again
/// (drive.refresh): then, where it `reads`, they are read as the fixture has them, the topic said anew as the core says
/// it (Fixture::changed's way); where not, they fail as before. Each call it is asked, by its name and parameters, in
/// `asked`.
fn pick_folder_failing(base : Source, why : String, reads : Bool, asked : Array[(String, Json)]) -> Source {
  let read = Ref(false)
  {
    ..base,
    topic_read: fn(name, params) {
      @settings.fixture_followed()
      if name == "drive" && !read.val {
        { value: None, error: Some({ "message": Json::string(why) }), version: 1 }
      } else {
        base.topic(name, params).get().snapshot()
      }
    },
    call: fn(name, params, done) {
      asked.push((name, params))
      if name == "drive.refresh" && reads {
        read.val = true
        @settings.fixture_changed()
      }
      (base.call)(name, params, done)
    },
  }
}

///|
/// The drive.refresh calls of `asked`, each its parameters.
fn pick_refreshes(asked : Array[(String, Json)]) -> Array[Json] {
  asked.filter(fn(a) { a.0 == "drive.refresh" }).map(fn(a) { a.1 })
}

///|
test "Station 文件: a folder that could not be read, 重试 pressed: the core asked to read it again; read, what is in it, why and 重试 gone" {
  // (a sheet with touch, a dialog in the middle of a wide window)
  for s in [(2, false), (0, true)] {
    let about = "platform \{s.0}, wide \{s.1}"
    let asked : Array[(String, Json)] = []
    let (t, _) = pick_open(platform=s.0, wide=s.1, at=pick_docs(), src_of=fn(b) {
      pick_folder_failing(b, "无法读取：权限不足", true, asked)
    })
    assert_true(t.find("无法读取：权限不足") is Some(_) && pick_refreshes(asked).length() == 0, msg="\{about}")
    pick_press(t, "重试")
    let folder : Json = { "station": "ws1/st1", "root": Json::string(fix_docs), "path": "" }
    assert_eq(pick_refreshes(asked), [folder], msg="\{about}: Willow's 文档 read again, once")
    assert_true(t.find("整个文件夹") is Some(_) && t.find("发布清单.md") is Some(_), msg="\{about}: what is in it")
    assert_true(t.find("无法读取：权限不足") is None && t.find("重试") is None, msg="\{about}: why and 重试 gone")
  }
}

///|
test "Station 文件: a folder that could not be read, 重试 pressed and it still cannot be: why and 重试 as they were" {
  let asked : Array[(String, Json)] = []
  let (t, _) = pick_open(platform=0, at=pick_docs(), src_of=fn(b) {
    pick_folder_failing(b, "无法读取：权限不足", false, asked)
  })
  let before = (pick_word(t, "无法读取：权限不足"), pick_word(t, "重试"))
  pick_press(t, "重试")
  assert_eq(pick_refreshes(asked).length(), 1, msg="asked again")
  assert_eq((pick_word(t, "无法读取：权限不足"), pick_word(t, "重试")), before)
  assert_true(t.find("整个文件夹") is None && t.find("发布清单.md") is None)
}

///|
test "Station 文件: the stations read the first time, nothing of them yet; where reading them fails, why; where none lends a folder, saying so" {
  for s in pick_screens {
    let about = "platform \{s.0}, wide \{s.1}"
    let (t, _) = pick_open(platform=s.0, wide=s.1, src_of=fn(b) { @sffixture.held_topics(b, ["stations"]) })
    assert_true(t.find("所有位置") is Some(_), msg="\{about}: its way")
    assert_true(t.find("主目录") is None && t.find("Maple · 离线") is None, msg="\{about}: nothing yet")
    let (t, _) = pick_open(platform=s.0, wide=s.1, src_of=fn(b) { @sffixture.failed_topics(b, ["stations"], "网络连接失败") })
    assert_true(t.find("所有位置") is Some(_) && t.find("网络连接失败") is Some(_), msg="\{about}: why")
    assert_true(t.find("主目录") is None, msg="\{about}")
    let (t, _) = pick_open(platform=s.0, wide=s.1, src_of=pick_no_stations)
    assert_true(t.find("暂无可浏览的文件夹") is Some(_), msg="\{about}: none")
    assert_true(pick_word(t, "所有位置").1 < pick_word(t, "暂无可浏览的文件夹").1, msg="\{about}")
  }
}

///|
test "Station 文件: where its words stand on each screen, the way and each station's name at its title's start, a folder's name, a file's and a place's on one line down, 取消 and 添加 n 个 side by side at its foot" {
  for s in pick_screens {
    let about = "platform \{s.0}, wide \{s.1}"
    let (t, _) = pick_open(platform=s.0, wide=s.1)
    let title = pick_word(t, "Station 文件")
    let (way, maple, home, home_at) = (pick_word(t, "所有位置"), pick_word(t, "Maple · 离线"), pick_word(t, "主目录"), pick_word(t, "/Users/lin"))
    assert_true((way.0 - title.0).abs() < 0.5 && (maple.0 - title.0).abs() < 0.5, msg="\{about}: \{Repr(title)} \{Repr(way)} \{Repr(maple)}")
    // (a place's name and where it is under it on one line down, after its mark)
    assert_true((home.0 - home_at.0).abs() < 0.5 && home.0 > title.0 + 20.0, msg="\{about}: \{Repr(home)} \{Repr(home_at)}")
    let (t, _) = pick_open(platform=s.0, wide=s.1, at=pick_docs(), ticked=[])
    let (whole, folder, file) = (pick_word(t, "整个文件夹"), pick_word(t, "设计稿"), pick_word(t, "发布清单.md"))
    // (the folder as a whole, a folder in it and a file in it, a place before: their names on one line down)
    assert_true((folder.0 - whole.0).abs() < 0.5 && (file.0 - whole.0).abs() < 0.5, msg="\{about}: \{Repr(whole)} \{Repr(folder)} \{Repr(file)}")
    assert_true((home.0 - whole.0).abs() < 0.5, msg="\{about}: a place \{Repr(home)}, a folder's rows \{Repr(whole)}")
    // (the way over them: its first step at the title's start, the folder's after it on its line)
    let (first, docs) = (pick_word(t, "所有位置"), pick_word(t, "Willow · 文档"))
    assert_true((first.0 - title.0).abs() < 0.5 && docs.0 > first.0 + first.2 && docs.1 + docs.3 <= whole.1, msg="\{about}: \{Repr(first)} \{Repr(docs)} \{Repr(whole)}")
    pick_press(t, "发布清单.md")
    let (cancel, add) = (pick_word(t, "取消"), pick_word(t, "添加 1 个"))
    assert_true((cancel.1 + cancel.3 / 2.0 - (add.1 + add.3 / 2.0)).abs() < 1.0 && cancel.0 + cancel.2 < add.0, msg="\{about}: \{Repr(cancel)} \{Repr(add)}")
  }
}
