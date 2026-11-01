// A chat's files downloaded to this device by the core (sfbase/downloads.mbt, client/core-ts views/downloads.ts):
// asked from the preview, on by themselves whatever page shows, how far each has come on its message's card (✕ calls
// one off, ↻ asks a failed one again), and saved a part at a time where the system keeps downloads once all of each is
// here, then said done.

///|
/// The fixture `mode` with the core's `downloads` as `list` says (what it brings as `keeping`), its calls kept in
/// `calls`; `download.take` answered as taken, `download.read` (the saving's) answered with `bytes` (of `type`) a part
/// at a time, `part` at most.
fn downloads_src(
  mode : String,
  list : Array[Json],
  calls : Array[(String, Json)],
  keeping? : Array[Json] = [],
  bytes? : Bytes = b"PK\x03\x04",
  part? : Int = 4 * 1024 * 1024,
) -> Source {
  let base = fixture(mode)
  {
    ..base,
    topic: fn(name, params) {
      if name == "downloads" {
        { value: Some({ "downloads": Json::array(list), "keeping": Json::array(keeping) }), error: None, version: 1 }
      } else {
        (base.topic)(name, params)
      }
    },
    call: fn(name, params, done) {
      calls.push((name, params))
      match name {
        "download.take" => done(Ok({ "taken": true }))
        "download.start" | "download.retry" | "download.done" | "download.cancel" | "fill.want" | "fill.stop" =>
          done(Ok({}))
        _ => (base.call)(name, params, done)
      }
    },
    read_bytes: fn(name, params, done) {
      calls.push((name, params))
      // (the saving's reads, off the device: a preview's own go to the fixture)
      if name == "download.read" {
        let from = number(Some(params), "offset").to_int()
        let to = if from + part > bytes.length() { bytes.length() } else { from + part }
        let got = Bytes::makei(to - from, fn(i) { bytes[from + i] })
        done(Ok(({ "type": "application/zip", "total": Json::number(bytes.length().to_double()) }, got)))
      } else {
        (base.read_bytes)(name, params, done)
      }
    },
  }
}

///|
/// A download as the core lists it.
fn listed(name : String, state : String, loaded : Double, size : Double, said : String) -> Json {
  {
    "id": Json::string("ws1/st1|s-c1|" + name),
    "station": "ws1/st1",
    "key": "s-c1",
    "name": Json::string(name),
    "size": Json::number(size),
    "loaded": Json::number(loaded),
    "progress": Json::number(if size > 0.0 { loaded / size } else { 0.0 }),
    "state": Json::string(state),
    "active": Json::boolean(state != "failed"),
    "statusText": Json::string(said),
    "startedAt": 1.0,
  }
}

///|
test "downloads: a message's video right clicked, 加载: the core brings it before all else from what is here, not saved; while it is brought, loaded or in the background alike, 停止加载 stops it" {
  new_run()
  let calls : Array[(String, Json)] = []
  let list : Array[Json] = []
  let keeping : Array[Json] = []
  let src = downloads_src("chat-download", list, calls, keeping~)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  open_fixture_mode("chat-download")
  t.run_for(@ui.move_most_ms)
  // (in its picture's middle: nothing is over it there)
  let (rx, ry, rw, rh) = t.get(Button, label=tr("web-main.file.play", args=[("name", "演示录屏.mp4")])).rect
  let (x, y) = (rx + rw / 2.0, ry + rh / 2.0)
  let video = fn() {
    t.right_click(x, y)
    t.draw()
  }
  video()
  assert_eq(t.words().filter(fn(w) { w.0 == tr("web-main.file.stopLoading") }).length(), 0)
  let first = @sf.last_presented()
  t.tap_text(tr("web-main.file.load"))
  t.frame()
  assert_false(@sf.presented_open_of(first))
  // (gone as it closes)
  t.run_for(@kit.pop_out_ms)
  assert_eq(calls.filter(fn(m) { m.0 == "download.start" }).length(), 0)
  let wants = calls.filter(fn(m) { m.0 == "fill.want" })
  assert_eq(wants.length(), 1)
  let p = Some(wants[0].1)
  assert_eq(text(p, "key"), "s-c1")
  assert_eq(text(p, "name"), "演示录屏.mp4")
  assert_true(field(p, "from") is Some(Object(_)))
  // nothing opened over the chat
  assert_true(viewer.get() is None)
  // brought as loaded: how far over its picture, its menu stops it
  let id = "chat\nws1/st1\ns-c1\n演示录屏.mp4"
  let brought = fn(state : String, said : String, wanted : Bool) -> Json {
    let o : Map[String, Json] = {
      "id": Json::string(id),
      "station": "ws1/st1",
      "key": "s-c1",
      "name": "演示录屏.mp4",
      "title": "演示录屏.mp4",
      "size": 5242880.0,
      "loaded": 1048576.0,
      "progress": 0.2,
      "state": Json::string(state),
      "statusText": Json::string(said),
    }
    if wanted {
      o["wanted"] = Json::boolean(true)
    }
    Json::object(o)
  }
  keeping.push(brought("going", "正在加载 20% · 5 MB", true))
  t.draw()
  t.run_for(@sf.dur_ms)
  assert_true(t.find("20%") is Some(_))
  let stop_it = fn() raise {
    video()
    assert_true(@sf.last_presented() != first && @sf.presented_open_of(@sf.last_presented()))
    // (加载 alone, not in 停止加载)
    assert_eq(t.words().filter(fn(w) { w.0 == tr("web-main.file.load") }).length(), 0)
    let stop = t.reachable(tr("web-main.file.stopLoading"))
    assert_eq(stop.length(), 1)
    t.tap(stop[0].0, stop[0].1)
    t.frame()
    t.run_for(@kit.pop_out_ms)
  }
  stop_it()
  assert_eq(calls.filter(fn(m) { m.0 == "fill.stop" }).map(fn(m) { text(Some(m.1), "id") }), [id])
  // brought in the background (opened and let go): the same, one thing whichever way it began
  keeping.clear()
  keeping.push(brought("queued", "后台缓存排队中 · 20%", false))
  t.draw()
  t.run_for(@sf.dur_ms)
  assert_true(t.find("20%") is Some(_))
  stop_it()
  assert_eq(calls.filter(fn(m) { m.0 == "fill.stop" }).length(), 2)
  assert_eq(calls.filter(fn(m) { m.0 == "fill.want" }).length(), 1, msg="加载 not asked again over it")
}

///|
test "downloads: one the core has all here is taken once, read off the device a part at a time into the host's keep, then said done once the host has kept it, whatever page shows" {
  new_run()
  let calls : Array[(String, Json)] = []
  let bytes = Bytes::makei(10, fn(i) { (i * 7).to_byte() })
  let src = downloads_src("home", [listed("dist.zip", "ready", 10.0, 10.0, "已下载 · 10 B")], calls, bytes~, part=4)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.frame()
  t.frame()
  t.frame()
  assert_eq(calls.filter(fn(m) { m.0 == "download.take" }).length(), 1)
  // read off the device, as the core keeps it with its chat (not asked of the station again), 4 at a time
  let reads = calls.filter(fn(m) { m.0 == "download.read" })
  assert_eq(reads.map(fn(r) { number(Some(r.1), "offset") }), [0.0, 4.0, 8.0])
  assert_eq(text(Some(reads[0].1), "id"), "ws1/st1|s-c1|dist.zip")
  // nothing of it read whole
  assert_eq(calls.filter(fn(m) { m.0 == "station.file" }).length(), 0)
  let kept = t.kept()
  assert_eq(kept.length(), 1)
  assert_eq(kept[0].0, "dist.zip")
  assert_eq(kept[0].1, "application/zip")
  assert_eq(kept[0].2, bytes)
  // the host has answered: done, once, with where the host put it (read back from there: the core's `saved`)
  let done = calls.filter(fn(m) { m.0 == "download.done" })
  assert_eq(done.map(fn(m) { text(Some(m.1), "id") }), ["ws1/st1|s-c1|dist.zip"])
  assert_eq(text(Some(done[0].1), "at"), "Download/dist.zip")
}

///|
test "downloads: on a phone a picture or a film is kept in the photo album, said so; on the Mac, and a zip anywhere, in the downloads" {
  for case in [
    ("截图.png", 2, "Photos", "已保存到相册"),
    ("录屏.MOV", 1, "Photos", "已保存到相册"),
    ("截图.png", 0, "Downloads", "已保存到「下载」"),
    ("dist.zip", 2, "Downloads", "已保存到「下载」"),
  ] {
    let (name, platform, way, said) = case
    new_run()
    let calls : Array[(String, Json)] = []
    let src = downloads_src("home", [listed(name, "ready", 4.0, 4.0, "已下载 · 4 B")], calls)
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform~)
    t.frame()
    t.frame()
    t.frame()
    assert_eq(t.kept_ways().map(fn(k) { (k.0, k.1.to_string()) }), [(name, way)])
    assert_true(t.find(said) is Some(_), msg="\{case}: \{t.words().map(fn(w) { w.0 }).join("|")}")
  }
}

///|
test "downloads: a file's card says how far the core has downloaded it in its size's place, ✕ calls it off; failed, why, ↻ asks it again" {
  new_run()
  let calls : Array[(String, Json)] = []
  let going = listed("发布包.zip", "going", 22020096.0, 52428800.0, "正在下载 42% · 50 MB")
  let src = downloads_src("chat-download", [going], calls)
  open_fixture_mode("chat-download")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("正在下载 42% · 50 MB") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  // (in its size's place)
  assert_true(!t.words().iter().any(fn(w) { w.0 == "50 MB" }))
  t.click(Button, label=tr("web-main.file.cancelDownload"))
  t.frame()
  assert_eq(calls.filter(fn(m) { m.0 == "download.cancel" }).map(fn(m) { text(Some(m.1), "id") }), ["ws1/st1|s-c1|发布包.zip"])
  // nothing opened by it
  assert_true(viewer.get() is None)
  // the desk's: failed, why, in its size's place; ↻ asks it again
  new_run()
  let failed = listed("发布包.zip", "failed", 0.0, 52428800.0, "下载失败：无法连接 station")
  let src = downloads_src("chat-download", [failed], calls)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  open_fixture_mode("chat-download")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("下载失败：无法连接 station") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  t.click(Button, label=tr("web-main.file.retryDownload"))
  t.frame()
  let again = calls.filter(fn(m) { m.0 == "download.retry" })
  assert_eq(again.map(fn(m) { text(Some(m.1), "id") }), ["ws1/st1|s-c1|发布包.zip"])
}

///|
test "downloads: a video's block in the chat says how far the core has downloaded it in its capsule" {
  new_run()
  let calls : Array[(String, Json)] = []
  let going = listed("演示录屏.mp4", "waiting", 1048576.0, 5242880.0, "等待连接 station · 20%")
  let src = downloads_src("chat-download", [going], calls)
  open_fixture_mode("chat-download")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("20%") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
}

///|
test "downloads: on the desk a file's sheet fills from its foot as the core downloads it (the web's FileTile)" {
  // in the sheet's points, whatever the screen's pixels a point
  for scale in [1.0, 2.0, 3.0] {
    let ys = fn(part : Double) -> Array[Double] {
      let out = []
      for o in @sf.file_tile_fill(scale, part, 0x000000FFL).outlines {
        for i, v in o.0 {
          if i % 2 == 1 {
            out.push(v)
          }
        }
      }
      out
    }
    let least = fn(a : Array[Double]) { a.fold(init=100.0, fn(m, y) { if y < m { y } else { m } }) }
    let most = fn(a : Array[Double]) { a.fold(init=0.0, fn(m, y) { if y > m { y } else { m } }) }
    // nothing of it here: nothing filled
    assert_eq(ys(0.0).length(), 0)
    // a quarter: from 27 down to its foot (34.25)
    assert_true((least(ys(0.25)) - 27.0).abs() < 0.001, msg="\{scale}: \{least(ys(0.25))}")
    assert_true((most(ys(0.25)) - 34.25).abs() < 0.01, msg="\{scale}: \{most(ys(0.25))}")
    // three quarters: from 9, where its fold ends
    assert_true((least(ys(0.75)) - 9.0).abs() < 0.001, msg="\{scale}: \{least(ys(0.75))}")
    // whole: the whole sheet, from its top (1.75)
    assert_true((least(ys(1.0)) - 1.75).abs() < 0.001, msg="\{scale}: \{least(ys(1.0))}")
  }
}

///|
test "downloads: 下载 on a file told of asks the core to download it, which goes on as the preview closes" {
  new_run()
  let calls : Array[(String, Json)] = []
  let src = downloads_src("home", [], calls)
  let file : Json = { "name": "dist.zip", "path": "work/s-c1/dist.zip", "size": 52428800.0, "owner": "s-c1" }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  open_preview("ws1/st1", "s-c1", attachment_of(file))
  t.run_for(@ui.move_most_ms)
  let (x, y) = t.find("下载").unwrap()
  t.tap(x, y)
  t.frame()
  let starts = calls.filter(fn(m) { m.0 == "download.start" })
  assert_eq(starts.length(), 1)
  assert_eq(field(Some(starts[0].1), "name"), Some(Json::string("dist.zip")))
  assert_eq(field(Some(starts[0].1), "key"), Some(Json::string("s-c1")))
  assert_eq(field(Some(starts[0].1), "size"), Some(Json::number(52428800.0)))
  // not read whole by the preview itself: the core's download is the one
  assert_eq(calls.filter(fn(m) { m.0 == "station.file" }).length(), 0)
}

///|
test "downloads: while the core downloads a file told of, the preview says how far over a bar, and calls it off" {
  new_run()
  let calls : Array[(String, Json)] = []
  let src = downloads_src("home", [listed("dist.zip", "going", 1048576.0, 52428800.0, "正在下载 2% · 50 MB")], calls)
  let file : Json = { "name": "dist.zip", "path": "work/s-c1/dist.zip", "size": 52428800.0, "owner": "s-c1" }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  open_preview("ws1/st1", "s-c1", attachment_of(file))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("正在下载 2% · 50 MB") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  t.tap_text(tr("web-main.file.cancelDownload"))
  t.frame()
  assert_eq(calls.filter(fn(m) { m.0 == "download.cancel" }).length(), 1)
}

///|
test "desk: a file's card has its name's extension right after its stem, not at the card's end (the web's FileName)" {
  new_run()
  let src = fixture("chat-download")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  open_fixture_mode("chat-download")
  t.run_for(@ui.move_most_ms)
  let words = t.words()
  let stem = words.filter(fn(w) { w.0 == "发布包" })
  let ext = words.filter(fn(w) { w.0 == ".zip" })
  assert_eq(stem.length(), 1)
  assert_eq(ext.length(), 1)
  // right after three characters of 13 (not some 180 on, where the card's words end)
  assert_true((ext[0].1 - (stem[0].1 + stem[0].3)).abs() < 0.5, msg="\{stem[0]} \{ext[0]}")
  assert_true(ext[0].1 - stem[0].1 < 3.0 * 13.0 + 1.0, msg="\{stem[0]} \{ext[0]}")
}

///|
test "downloads: a drive's file downloading shows how far on its row; a folder being zipped for it, 0 while the station zips it" {
  new_run()
  let src = fixture("drive-download")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  open_fixture_mode("drive-download")
  t.run_for(@ui.move_most_ms + 600.0)
  assert_true(t.find("40%") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("0%") is Some(_))
}

///|
test "downloads: the desk's files page lists the drive's downloads among its transfers: how far, 正在打包, ✕ calls one off" {
  new_run()
  let calls : Array[(String, Json)] = []
  let base = fixture("drive-download")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push((name, params))
      (base.call)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  open_fixture_mode("drive-download")
  t.run_for(@ui.move_most_ms)
  // (the rail's key: what comes, how far)
  let (x, y, w, h) = t.query(Button, label="2 个传输 · 40%").unwrap().rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("到此设备") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("正在打包") is Some(_))
  assert_true(t.find("正在下载 40%") is Some(_))
  // (the file's, the first: the folder's is being zipped)
  let cancels = t.all(Button, label=tr("web-main.file.cancelDownload"))
  assert_eq(cancels.length(), 2)
  let (x, y, w, h) = cancels[0].rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.frame()
  assert_eq(calls.filter(fn(m) { m.0 == "download.cancel" }).length(), 1)
}
