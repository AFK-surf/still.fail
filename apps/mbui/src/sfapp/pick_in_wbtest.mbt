// What the system's pickers answer (a recent photo or 照片 from ＋'s sheet or panel, ＋ or ⌘U on a computer, a station's
// mark, a vault item's file, a drive folder's 上传) comes in as the host's event tells it, with no other input,
// Tester::draw, or whole-frame comparison pass to build the kept view again.

///|
fn pick_test_source(calls : Array[Made], mode? : String = "chat") -> Source {
  let base = fixture(mode)
  {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      if name.has_prefix("composer.") {
        (base.call)(name, params, done)
      } else {
        done(Ok(Json::object({})))
      }
    },
    call_bytes: fn(name, params, bytes, done) {
      calls.push({ name, params, bytes: Some(bytes), done })
      (base.call_bytes)(name, params, bytes, done)
    },
    stream: fn(name, params, bytes, on_value, done) {
      if name != "station.upload.part" {
        return (base.stream)(name, params, bytes, on_value, done)
      }
      calls.push({ name, params, bytes, done })
      0
    },
  }
}

///|
fn pick_test_png() -> Bytes {
  @pixels.png(4, 4, FixedArray::make(4 * 4 * 4, b'\x80'))
}

///|
test "small touch ＋ → recent photo in the strip: what Picks.photo reads goes into the chat's composer as the host's event tells it" {
  for nodes in [false, true] {
    new_run()
    @sfbase.chat_page_nodes.set(nodes)
    let calls : Array[Made] = []
    let src = pick_test_source(calls)
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
    t.check_looks(false)
    let shot : @hostapi.GalleryPhoto = {
      id: 1L,
      src: "content://media/external/images/media/1",
      added: 1_792_200_000L,
      modified: 1_792_200_000L,
      taken: -1L,
      video: false,
    }
    t.add_image(shot.src, 1080, 2400)
    t.gallery([shot])
    t.run_for(@ui.move_most_ms)
    t.picks_by_hand()
    let (rx, ry, rw, rh) = t.get(Button, label=@sf.t("web-main.composer.attach")).rect
    t.tap(rx + rw / 2.0, ry + rh / 2.0)
    t.run_for(@ui.move_most_ms)
    // first gallery photo tile after the camera tile (24 + 98..214), below its selection ring
    let (_, py) = t.locate("=照片和视频")[0]
    t.tap(150.0, py - 80.0)
    t.run_for(@ui.move_most_ms)
    assert_true(t.pick_asks() == [Photos], msg="nodes=\{nodes}")
    assert_eq(named(calls, "composer.add").length(), 0, msg="nodes=\{nodes}")
    t.picks([("recent.png", pick_test_png())])
    t.pick_answer(1)
    t.run_for(@ui.move_most_ms)
    let added = named(calls, "composer.add")
    assert_eq(added.length(), 1, msg="nodes=\{nodes}")
    assert_eq(text(handed(added[0]), "name"), "recent.png", msg="nodes=\{nodes}")
    let remove = @sf.t("web-main.file.remove", args=[("name", "recent.png")])
    assert_true(
      t.query(Button, label=remove) is Some(_),
      msg="nodes=\{nodes}, sems=\{Repr(t.semantics().map(fn(s) { (s.role, s.label, s.hidden) }))}",
    )
  }
}

///|
test "large touch ＋ → 照片 (an unfolded phone or tablet's panel beside ＋): the photo picked (including HEIC) goes into the composer with its bytes preview as the host's event tells it" {
  let heic : Bytes = Bytes::from_array([
    // ftyp heic (24 bytes)
    0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63, 0, 0, 0, 0,
    0x6d, 0x69, 0x66, 0x31, 0x68, 0x65, 0x69, 0x63,
    // meta (version 0: 12 + 14 + 49 = 75 bytes)
    0, 0, 0, 75, 0x6d, 0x65, 0x74, 0x61, 0, 0, 0, 0,
    // pitm (version 0: item_id = 1, 14 bytes)
    0, 0, 0, 14, 0x70, 0x69, 0x74, 0x6d, 0, 0, 0, 0, 0, 1,
    // iprp (8 + 28 + 13 = 49 bytes)
    0, 0, 0, 49, 0x69, 0x70, 0x72, 0x70,
    // ipco (8 + 20 = 28 bytes)
    0, 0, 0, 28, 0x69, 0x70, 0x63, 0x6f,
    // ispe (20 bytes: 4032 x 3024)
    0, 0, 0, 20, 0x69, 0x73, 0x70, 0x65, 0, 0, 0, 0, 0, 0, 0x0f, 0xc0, 0, 0, 0x0b, 0xd0,
    // ipma (version 0, flags 0, 1 item, item 1 -> 1 assoc: index 1 = 13 bytes)
    0, 0, 0, 13, 0x69, 0x70, 0x6d, 0x61, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0x81,
  ].map(fn(x) { x.to_byte() }))
  for nodes in [false, true] {
    new_run()
    @sfbase.chat_page_nodes.set(nodes)
    let calls : Array[Made] = []
    let src = pick_test_source(calls)
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=960.0, h=844.0, platform=2)
    t.check_looks(false)
    t.run_for(@ui.move_most_ms)
    t.picks_by_hand()
    let (rx, ry, rw, rh) = t.get(Button, label=@sf.t("web-main.composer.attach")).rect
    t.tap(rx + rw / 2.0, ry + rh / 2.0)
    t.run_for(@ui.move_most_ms)
    let (x, y) = t.locate("=照片和视频")[0]
    t.tap(x, y)
    t.run_for(@ui.move_most_ms)
    assert_true(t.pick_asks() == [Photos], msg="nodes=\{nodes}")
    assert_eq(named(calls, "composer.add").length(), 0, msg="nodes=\{nodes}")
    t.picks([("IMG_0001.HEIC", heic)])
    t.pick_answer(1)
    t.run_for(@ui.move_most_ms)
    let added = named(calls, "composer.add")
    assert_eq(added.length(), 1, msg="nodes=\{nodes}")
    let one = handed(added[0])
    assert_eq(text(one, "name"), "IMG_0001.HEIC", msg="nodes=\{nodes}")
    let pic = @sfbase.writing_pictures.get(text(one, "id")).unwrap_or("")
    assert_true(pic.has_prefix("mem:writing/"), msg="nodes=\{nodes}, pic=\{pic}")
  }
}

///|
test "pointer ＋ (with the field let go) and ⌘U: the file picked goes into the chat's composer as the host's event tells it" {
  for by_key in [false, true] {
    new_run()
    let calls : Array[Made] = []
    let src = pick_test_source(calls)
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
    t.check_looks(false)
    t.run_for(@ui.move_most_ms)
    // let go of the field first so clicking ＋ does not start composer/let-go
    t.tap(800.0, 200.0)
    t.run_for(@ui.move_most_ms)
    t.picks_by_hand()
    if by_key {
      t.key_told(@ui.key_of_char('u'), @ui.mod_cmd, t.time())
      t.frames_owed()
    } else {
      let (rx, ry, rw, rh) = t.get(Button, label=@sf.t("web-main.composer.attach")).rect
      t.tap(rx + rw / 2.0, ry + rh / 2.0)
    }
    t.run_for(@ui.move_most_ms)
    assert_true(t.pick_asks() == [Files], msg="by_key=\{by_key}")
    assert_eq(named(calls, "composer.add").length(), 0, msg="by_key=\{by_key}")
    t.picks([("photo.png", pick_test_png())])
    t.pick_answer(1)
    t.run_for(@ui.move_most_ms)
    let added = named(calls, "composer.add")
    assert_eq(added.length(), 1, msg="by_key=\{by_key}")
    assert_eq(text(handed(added[0]), "name"), "photo.png", msg="by_key=\{by_key}")
  }
}

///|
test "上传图片 in the mark sheet: answered through settings_core's pick_picture as the host's event tells it" {
  @sf.presenters_reset()
  new_run()
  let calls : Array[Made] = []
  let src = pick_test_source(calls)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=2)
  t.check_looks(false)
  t.run_for(@ui.move_most_ms)
  let set : Array[(String, String)] = []
  let w : Workspace = { id: "ws1", name: "星火工作室", emoji: "", icon: "", email: "lin@example.com" }
  let core = settings_core(src, w)
  @settings.open_mark_pick(core, "Willow", "🚀", "glyph:rocket:orange", "图标", fn(e, i, _) { set.push((e, i)) })
  t.frames_owed()
  t.run_for(@ui.move_most_ms)
  t.picks_by_hand()
  mark_press(t, "图片")
  let (x, y, bw, bh) = mark_word(t, "上传图片")
  t.tap(x + bw / 2.0, y + bh / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.pick_asks() == [Photos])
  assert_eq(set, [])
  t.picks([("mark.png", b"\x89PNG\r\n\x1a\nxyz")])
  t.pick_answer(1)
  t.run_for(@ui.move_most_ms)
  assert_eq(set, [("", "data:image/png;base64,iVBORw0KGgp4eXo=")])
  assert_false(@sf.presenter_visible())
  t.assert_idle()
}

///|
test "vault editor 选择文件 on touch: the file picked shows in the dialog as the host's event tells it" {
  @sf.presenters_reset()
  new_run()
  let calls : Array[Made] = []
  let src = pick_test_source(calls)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.check_looks(false)
  t.run_for(@ui.move_most_ms)
  let w : Workspace = { id: "ws1", name: "星火工作室", emoji: "", icon: "", email: "lin@example.com" }
  let core = settings_core(src, w)
  @sfpages.vault_editor_dialog(core, "ws1", "v1", None, kind="file", kinds=false)
  t.frames_owed()
  t.run_for(@ui.move_most_ms)
  t.picks_by_hand()
  let (rx, ry, rw, rh) = t.get(Button, label=@sf.t("web-pages.vault.editor.pickFile")).rect
  t.tap(rx + rw / 2.0, ry + rh / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.pick_asks() == [Files])
  t.picks([("secret.pem", b"abcdef")])
  t.pick_answer(1)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("secret.pem · 6 B") is Some(_))
}

///|
test "drive folder 上传: the file picked goes up into the folder as the host's event tells it" {
  new_run()
  let calls : Array[Made] = []
  let base = fixture("home")
  let src : Source = {
    ..base,
    call_bytes: fn(name, params, bytes, done) {
      calls.push({ name, params, bytes: Some(bytes), done })
      if name != "drive.upload.part" {
        (base.call_bytes)(name, params, bytes, done)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=2)
  t.check_looks(false)
  app.nav.replace(Files)
  app.nav.push(Drive({ station: "ws1/st1", root: Some(fix_docs), path: "" }))
  t.run_for(@ui.move_most_ms)
  t.picks_by_hand()
  let (rx, ry, rw, rh) = t.get(Button, label=@sf.t("web-pages.drive.upload")).rect
  t.tap(rx + rw / 2.0, ry + rh / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.pick_asks() == [Files])
  assert_eq(named(calls, "drive.upload.part").length(), 0)
  t.picks([("新建记录.txt", @utf8.encode("另一行\n"))])
  t.pick_answer(1)
  t.frame()
  let parts = named(calls, "drive.upload.part")
  assert_eq(parts.length(), 1)
  assert_eq(text(Some(parts[0].params), "path"), "新建记录.txt")
  assert_true(t.find("新建记录.txt") is Some(_))
  (parts[0].done)(Err(Json::object({ "message": Json::string("offline") })))
  t.run_for(@ui.move_most_ms)
}
