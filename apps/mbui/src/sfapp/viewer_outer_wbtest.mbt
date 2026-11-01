// What the viewer does round what it shows of a file that is no picture, film or song (its outer life: coming, read,
// failed, its kind sniffed, 源码 and 预览, closed three ways and the page's again, a reader's own Esc first, beside an
// iPhone Duo's bars), as main's viewer does it (acb0068613), whatever draws it.

///|
/// The buttons read out now.
fn outer_buttons(t : @ui.Tester) -> Array[String] {
  t.semantics().filter(fn(s) { s.role == @ui.Role::Button }).map(fn(s) { s.label })
}

///|
/// What parts were asked, in order (outer_viewer's made file's): for what a case says as it fails.
// kept across runs: cleared by each outer_viewer
let outer_asked : Array[String] = []

///|
/// The bytes of preview_files' `name`.
fn outer_bytes(name : String) -> Bytes {
  for f in preview_files() {
    if f.0.name == name {
      return (f.1)()
    }
  }
  b""
}

///|
/// The fixture's chat with its `what` open in the viewer (MBUI_FIXTURE=chat-preview-<what>; `made`: this one instead,
/// the fixture's chat alone opening it,
/// each part of it asked (`station.file.part`) held in `parts` till the test answers it), a window `w` × `h`; the
/// file's whole asked of the station (`station.file`) held in `held` (how much has come, and the answer) till the test
/// gives it.
fn outer_viewer(
  what : String,
  held : Ref[((Json) -> Unit, (Result[(Json, Bytes), Json]) -> Unit)?],
  w? : Double = 390.0,
  h? : Double = 844.0,
  platform? : Int = 0,
  native? : Bool = false,
  made? : Attachment? = None,
  parts? : Ref[Array[(Double, Int, (Result[(Json, Bytes), Json]) -> Unit)]] = Ref([]),
  words_over? : Bool = true,
) -> @ui.Tester {
  new_run()
  outer_asked.clear()
  // (a file made here opened in the chat alone: none of the fixture's opened before it)
  let base = fixture(if made is Some(_) { "chat" } else { "chat-preview-" + what })
  let src : Source = {
    ..base,
    read_going: fn(name, params, on_value, done) {
      if name == "station.file" {
        held.val = Some((on_value, done))
      } else {
        (base.read_going)(name, params, on_value, done)
      }
    },
    read_bytes: fn(name, params, done) {
      match made {
        // (each of its parts asked held in `parts`, from where and how long, till the test answers it; another file's
        // the fixture's)
        Some(a) if name == "station.file.part" && text(Some(params), "name") == a.name => {
          outer_asked.push(params.stringify())
          parts.val.push((number(Some(params), "offset"), number(Some(params), "length").to_int(), done))
        }
        _ => (base.read_bytes)(name, params, done)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~, nav_able=native, words_over_held=words_over)
  if native {
    t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":20,\"left\":0,\"right\":84}}")
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  match made {
    Some(a) => open_preview("ws1/st1", "s-c1", a)
    None => ()
  }
  t.draw()
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The whole held, given: `what`'s bytes.
fn outer_give(t : @ui.Tester, held : Ref[((Json) -> Unit, (Result[(Json, Bytes), Json]) -> Unit)?], name : String) -> Unit raise {
  match held.val {
    Some((_, done)) => done(Ok((Json::object({}), outer_bytes(name))))
    None => fail("\{name}: its whole not asked for")
  }
  t.draw()
  t.run_for(@ui.move_most_ms)
}

///|
test "a table read as it comes: 正在打开 on its stage, then how much has come once the core says, nothing of it in the bar; read, the table, its bar's 预览 and 源码" {
  let held = Ref(None)
  let t = outer_viewer("csv", held)
  let v = viewer.get().unwrap()
  assert_true(v.bytes.get() is None && t.find("正在打开") is Some(_), msg="coming: \{t.words().map(fn(w) { w.0 })}")
  let coming = outer_buttons(t)
  assert_true(coming.contains("数据.csv") && coming.contains("下载") && coming.contains("关闭（Esc）"), msg="its bar as it comes: \{coming}")
  match held.val {
    Some((on_value, _)) => on_value({ "loaded": 100.0, "total": 200.0 })
    None => fail("its whole not asked for")
  }
  t.draw()
  assert_true(t.find("正在读取 100 B / 200 B") is Some(_), msg="how much has come: \{t.words().map(fn(w) { w.0 })}")
  assert_eq(outer_buttons(t).filter(fn(b) { b.contains("100 B") }), [], msg="nothing of it in the bar")
  outer_give(t, held, "数据.csv")
  assert_true(v.bytes.get() is Some(_) && t.find("帧时间（毫秒）") is Some(_), msg="read: the table")
  assert_true(outer_buttons(t).contains("数据.csv 预览 源码"), msg="its bar's 预览 and 源码: \{outer_buttons(t)}")
}

///|
test "a table's 源码 its words as they are, 预览 the table again, said in the frame after each press" {
  let held = Ref(None)
  let t = outer_viewer("csv", held)
  outer_give(t, held, "数据.csv")
  let v = viewer.get().unwrap()
  // (the words drawn, each run whole: a cell's, or the source's line)
  let words = fn() { t.words().map(fn(w) { w.0 }) }
  t.tap_text("源码")
  t.draw()
  assert_true(v.source && words().iter().any(fn(w) { w.has_prefix("名字,平台,帧时间（毫秒）,通过\n") }) && !words().contains("帧时间（毫秒）"), msg="源码: \{v.source} \{words()}")
  t.tap_text("预览")
  t.draw()
  assert_true(!v.source && words().contains("帧时间（毫秒）") && !words().iter().any(fn(w) { w.has_prefix("名字,平台,帧时间（毫秒）,通过") }), msg="预览: \{words()}")
}

///|
test "a PDF whose read failed: why on its stage, its bar's name, 下载 and close as ever" {
  let held = Ref(None)
  let t = outer_viewer("pdf", held)
  assert_true(t.find("正在打开") is Some(_))
  match held.val {
    Some((_, done)) => done(Err({ "message": "连接已断开" }))
    None => fail("its whole not asked for")
  }
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq(viewer.get().unwrap().error.get(), Some("连接已断开"))
  assert_true(t.find("无法读取：连接已断开") is Some(_), msg="\{t.words().map(fn(w) { w.0 })}")
  let bar = outer_buttons(t)
  assert_true(bar.contains("设计说明.pdf") && bar.contains("下载") && bar.contains("关闭（Esc）"), msg="\{bar}")
}

///|
/// The part of `parts` asked from `offset`, `length` long (a sniff's first 8192; what reads it as it comes, flow_part),
/// not answered yet, answered with `bytes` of a whole `total` long.
fn outer_part(
  t : @ui.Tester,
  parts : Ref[Array[(Double, Int, (Result[(Json, Bytes), Json]) -> Unit)]],
  offset : Double,
  length : Int,
  bytes : Bytes,
  total : Double,
) -> Unit raise {
  guard parts.val.search_by(fn(p) { p.0 == offset && p.1 == length }) is Some(i) else {
    fail("no part asked from \{offset}, \{length} long: \{outer_asked}")
  }
  let (_, _, done) = parts.val.remove(i)
  done(Ok(({ "total": Json::number(total) }, bytes)))
  t.draw()
}

///|
test "a file of no kind it knows by its name, its first part words, bigger than is read whole: 正在打开 as its first part is read; then read as it comes in the same viewer, more as its next part comes, never told of" {
  let held = Ref(None)
  let parts = Ref([])
  let total = 3.0 * 1024.0 * 1024.0
  let a : Attachment = {
    name: "备忘",
    path: "uploads/fx/备忘",
    size: total,
    width: 0.0,
    height: 0.0,
    thumbhash: "",
    owner: "s-c1",
    upload: "",
    duration: 0.0,
    frames: 0,
    held: false,
  }
  let t = outer_viewer("none", held, made=Some(a), parts~)
  // (its first part asked to know what it is: none known yet, coming)
  let v = viewer.get().unwrap()
  assert_true(v.kind is None && v.sniffed.get() is None, msg="its kind not known yet")
  assert_true(t.find("正在打开") is Some(_), msg="coming: \{t.words().map(fn(w) { w.0 })}")
  let first = @utf8.encode("今天要做的事：\n一、核对安装包签名\n")
  // (asked to know what it is: its first 8192)
  outer_part(t, parts, 0.0, 8192, first, total)
  // (words: read as it comes, its first part asked anew by what reads it)
  outer_part(t, parts, 0.0, @sfbase.flow_part, first, total)
  t.run_for(@ui.move_most_ms)
  assert_true(physical_equal(viewer.get().unwrap(), v), msg="the same viewer")
  assert_eq(v.sniffed.get(), Some(true))
  assert_true(v.shown_kind() == Some(KText) && !v.told_of(), msg="sniffed as words")
  assert_true(v.flowing() && v.bytes.get() is None, msg="read as it comes, not whole: flow \{v.flow.map(fn(f) { f.parts.get() })}, whole \{v.bytes.get().map(fn(b) { b.length() })}, parts waiting \{parts.val.map(fn(p) { (p.0, p.1) })}, asked \{outer_asked}, held whole \{held.val is Some(_)}, the same viewer \{physical_equal(viewer.get().unwrap(), v)}, its flow \{viewer.get().unwrap().flow.map(fn(f) { f.parts.get() })}")
  assert_true(t.find("此文件类型不支持预览") is None, msg="not told of")
  assert_true(t.find("一、核对安装包签名") is Some(_), msg="what has come of it: \{t.words().map(fn(w) { w.0 })}")
  // (its next part, once asked, given: what it adds shown)
  if parts.val.search_by(fn(p) { p.0 == first.length().to_double() }) is Some(_) {
    outer_part(t, parts, first.length().to_double(), @sfbase.flow_part, @utf8.encode("二、发布说明\n"), total)
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("二、发布说明") is Some(_), msg="its next part: \{t.words().map(fn(w) { w.0 })}")
  } else {
    fail("its next part not asked for: \{outer_asked}")
  }
  assert_true(physical_equal(viewer.get().unwrap(), v), msg="the same viewer still")
}

///|
/// A table read in the viewer over its chat on a phone's screen, closed by `how` (Esc, back, its ×): gone from the
/// viewer at once, going till its fade ends, then none; the chat's composer then takes a tap and what is typed.
fn outer_closed(how : String) -> Unit raise {
  let held = Ref(None)
  let t = outer_viewer("csv", held)
  outer_give(t, held, "数据.csv")
  match how {
    "esc" => t.key(@ui.key_escape)
    "back" => t.back()
    _ => t.click(@ui.Role::Button, label="关闭（Esc）")
  }
  t.draw()
  assert_true(viewer.get() is None && pv_leaving.get() is Some(_), msg="\{how}: going")
  if how == "esc" {
    // (while it goes, the page's: its composer tapped and typed into, the viewer going still)
    t.tap_text("按空格输入")
    t.draw()
    t.type_text("ab")
    t.draw()
    let (focused, words, _, _) = t.ime()
    assert_true(focused && words == "ab" && pv_leaving.get() is Some(_), msg="esc: the composer's as it goes: \{t.ime()}")
    return
  }
  t.run_for(@ui.move_most_ms)
  assert_true(viewer.get() is None && pv_leaving.get() is None, msg="\{how}: gone")
  t.tap_text("按空格输入")
  t.draw()
  t.type_text("ab")
  t.draw()
  let (focused, words, _, _) = t.ime()
  assert_true(focused && words == "ab", msg="\{how}: the composer's: \{t.ime()}")
}

///|
test "a table read in the viewer closed by Esc: going; the chat's composer under it takes a tap and what is typed as it goes" {
  outer_closed("esc")
}

///|
test "a table read in the viewer closed by back: going, gone; the chat's composer takes what is typed then" {
  outer_closed("back")
}

///|
test "a table read in the viewer closed by its ×: going, gone; the chat's composer takes what is typed then" {
  outer_closed("x")
}

///|
test "desk: Markdown in the viewer's reader, its find open: Esc closes the find, the viewer staying; Esc again closes the viewer" {
  let held = Ref(None)
  let t = outer_viewer("md", held, w=1280.0, h=800.0)
  outer_give(t, held, "说明.md")
  t.run_for(@sf.reader_place_ms)
  t.key(@ui.key_of_char('f'), mods=@ui.mod_cmd)
  t.draw()
  assert_true(t.find("在全文中搜索") is Some(_), msg="its find: \{t.words().map(fn(w) { w.0 })}")
  t.key(@ui.key_escape)
  t.draw()
  assert_true(t.find("在全文中搜索") is None, msg="its find closed")
  assert_true(viewer.get() is Some(_), msg="the viewer staying")
  t.key(@ui.key_escape)
  t.draw()
  assert_true(viewer.get() is None && pv_leaving.get() is Some(_), msg="the viewer closing")
}

///|
test "beside an iPhone Duo's own bars: a PDF, a file of no kind and a table hand them no picture's actions (none to mark, copy or fit)" {
  for at in [("pdf", "设计说明.pdf"), ("none", "备份.bin"), ("csv", "数据.csv")] {
    let held = Ref(None)
    let t = outer_viewer(at.0, held, w=951.0, h=669.0, platform=1, native=true)
    match held.val {
      Some((_, done)) => done(Ok((Json::object({}), outer_bytes(at.1))))
      None => ()
    }
    t.draw()
    t.run_for(@ui.move_most_ms)
    // (it open and shown: its file, what shows of it)
    assert_true(viewer.get().map(fn(v) { v.file.name }) == Some(at.1), msg="\{at.0}: open")
    let shown = match at.0 {
      "pdf" => t.views().iter().any(fn(l) { l.has_prefix("pdf ") })
      "csv" => t.find("帧时间（毫秒）") is Some(_)
      _ => t.find("此文件类型不支持预览") is Some(_)
    }
    assert_true(shown, msg="\{at.0}: shown: \{t.words().map(fn(w) { w.0 })}")
    let said = t.nav_said()
    for id in ["over/mark", "over/copy", "over/fit", "over/actual"] {
      assert_true(!said.contains("\"" + id + "\""), msg="\{at.0}: no \{id}: \{said}")
    }
  }
}
