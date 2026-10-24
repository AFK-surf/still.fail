// A chat's files downloaded to this device by the core (sfbase/downloads.mbt, client/core-ts views/downloads.ts):
// asked from the preview, on by themselves whatever page shows, how far each has come on its message's card, and kept
// where the system keeps downloads once all of each is here.

///|
/// The fixture `mode` with the core's `downloads` as `list` says, its calls kept in `calls`; `download.take` answered
/// as taken, `station.file` read with `keep` answered with `bytes` of `type`.
fn downloads_src(mode : String, list : Array[Json], calls : Array[(String, Json)], bytes? : Bytes = b"PK\x03\x04") -> Source {
  let base = fixture(mode)
  {
    ..base,
    topic: fn(name, params) {
      if name == "downloads" {
        { value: Some({ "downloads": Json::array(list) }), error: None, version: 1 }
      } else {
        (base.topic)(name, params)
      }
    },
    call: fn(name, params, done) {
      calls.push((name, params))
      match name {
        "download.take" => done(Ok({ "taken": true }))
        "download.start" => done(Ok({}))
        _ => (base.call)(name, params, done)
      }
    },
    read_bytes: fn(name, params, done) {
      calls.push((name, params))
      if name == "station.file" {
        done(Ok(({ "type": "application/zip" }, bytes)))
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
    "statusText": Json::string(said),
    "startedAt": 1.0,
  }
}

///|
test "downloads: one the core has all here is taken once and read as it keeps it, then kept where the system keeps downloads, whatever page shows" {
  reset()
  let calls : Array[(String, Json)] = []
  let src = downloads_src("home", [listed("dist.zip", "ready", 2048.0, 2048.0, "已下载 · 2 KB")], calls)
  // (asked in this run, as a preview's 下载 asks it)
  download_start(src, "ws1/st1", "s-c1", "dist.zip", 2048.0)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  t.frame()
  t.frame()
  t.frame()
  let takes = calls.filter(fn(m) { m.0 == "download.take" })
  assert_eq(takes.length(), 1)
  let reads = calls.filter(fn(m) { m.0 == "station.file" })
  assert_eq(reads.length(), 1)
  // read off the device, as the core keeps it with its chat: not asked of the station again
  assert_eq(field(Some(reads[0].1), "keep"), Some(Json::boolean(true)))
  assert_eq(field(Some(reads[0].1), "size"), Some(Json::number(2048.0)))
  let kept = t.kept()
  assert_eq(kept.length(), 1)
  assert_eq(kept[0].0, "dist.zip")
  assert_eq(kept[0].1, "application/zip")
}

///|
test "downloads: a file's card says how far the core has downloaded it in its size's place; failed, why" {
  reset()
  let calls : Array[(String, Json)] = []
  let going = listed("发布包.zip", "going", 22020096.0, 52428800.0, "正在下载 42% · 50 MB")
  let src = downloads_src("chat-download", [going], calls)
  download_start(src, "ws1/st1", "s-c1", "发布包.zip", 52428800.0)
  open_fixture_mode("chat-download")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("正在下载 42% · 50 MB") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  // (in its size's place)
  assert_true(!t.words().iter().any(fn(w) { w.0 == "50 MB" }))
  // the desk's: failed, why, in its size's place
  reset()
  let failed = listed("发布包.zip", "failed", 0.0, 52428800.0, "下载失败：没连上 station")
  let src = downloads_src("chat-download", [failed], calls)
  download_start(src, "ws1/st1", "s-c1", "发布包.zip", 52428800.0)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  open_fixture_mode("chat-download")
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("下载失败：没连上 station") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
}

///|
test "downloads: on the desk a file's sheet fills from its foot as the core downloads it (the web's FileTile)" {
  // in the sheet's points, whatever the screen's pixels a point
  for scale in [1.0, 2.0, 3.0] {
    let ys = fn(part : Double) -> Array[Double] {
      let out = []
      for o in file_sheet_fill(scale, part, 0x000000FFL).outlines {
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
  reset()
  let calls : Array[(String, Json)] = []
  let src = downloads_src("home", [], calls)
  let file : Json = { "name": "dist.zip", "path": "work/s-c1/dist.zip", "size": 52428800.0, "owner": "s-c1" }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  open_preview("ws1/st1", "s-c1", attachment_of(file))
  t.run_for(@ui.nav_push_ms)
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
test "desk: a file's card has its name's extension right after its stem, not at the card's end (the web's FileName)" {
  reset()
  let src = fixture("chat-download")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  open_fixture_mode("chat-download")
  t.run_for(@ui.nav_push_ms)
  let words = t.words()
  let stem = words.filter(fn(w) { w.0 == "发布包" })
  let ext = words.filter(fn(w) { w.0 == ".zip" })
  assert_eq(stem.length(), 1)
  assert_eq(ext.length(), 1)
  // right after three characters of 13 (not some 180 on, where the card's words end)
  assert_true((ext[0].1 - (stem[0].1 + stem[0].3)).abs() < 0.5, msg="\{stem[0]} \{ext[0]}")
  assert_true(ext[0].1 - stem[0].1 < 3.0 * 13.0 + 1.0, msg="\{stem[0]} \{ext[0]}")
}
