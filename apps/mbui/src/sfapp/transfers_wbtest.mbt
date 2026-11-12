// The list of what comes and goes (sfdesk's transfers.mbt, 传输): what is being brought, the downloads, the copies
// between stations, each how it stands, and what each of their keys does; as a sheet on a small screen (touch, and
// keyboard and mouse), beside the rail on a wide window; rows coming, changing and going as the core says.

///|
/// A copy between stations as the `driveTransfers` topic says it: `id`, what goes (`title`), how it stands (`state`:
/// copying, done, failed, cancelled), how far, how many files, whether it moves, from another station or the same.
fn copy_said(
  id : String,
  title : String,
  state : String,
  progress? : Double = 0.4,
  files? : Int = 1,
  moves? : Bool = false,
  across? : Bool = true,
  said? : String = "18.3 MB / 48.2 MB",
) -> Json {
  {
    "id": Json::string(id),
    "station": "ws1/st2",
    "stationName": "Maple",
    "fromStation": if across { "ws1/st1" } else { "ws1/st2" },
    "fromStationName": "Willow",
    "toRoot": "/Users/lin/照片",
    "toPath": "旅行",
    "toText": "Maple › 旅行",
    "title": Json::string(title),
    "move": Json::boolean(moves),
    "state": Json::string(state),
    "active": Json::boolean(state == "copying"),
    "progress": Json::number(progress),
    "files": Json::number(files.to_double()),
    "statusText": Json::string(said),
  }
}

///|
/// The copies most of these list: one copying (three files), one moved there done, one failed, one called off.
fn copies_said() -> Array[Json] {
  [
    copy_said("t1", "演示录屏.mp4", "copying", files=3),
    copy_said("t2", "设计稿", "done", moves=true, across=false, said="已完成", files=2),
    copy_said("t3", "季度报告.pdf", "failed", said="空间不足"),
    copy_said("t4", "旧照片", "cancelled", said="已取消"),
  ]
}

///|
/// The app on Home with every kind of what comes (fix_every_transfer: three files brought, a download) and `copies`,
/// its calls kept in `calls`, in a phone's window (`platform` its input) or, `wide`, one 1200 by 800; then the list
/// opened (open_transfers), at rest (`rest`) or at the frame it opened in.
fn transfers_up(
  calls : Array[(String, Json)],
  platform? : Int = 2,
  wide? : Bool = false,
  rest? : Bool = true,
  copies? : Array[Json] = copies_said(),
  failed_download? : Bool = false,
) -> @ui.Tester {
  new_run()
  let base = fixture("home")
  @sffixture.fix_every_transfer("ws1/st1", "s-c1", @sffixture.fix_docs)
  if failed_download {
    @sffixture.fix_downloads.push({
      station: "ws1/st1",
      key: "s-c1",
      root: "",
      path: "",
      zip: false,
      name: "日志.tar",
      size: 4.0 * 1024.0 * 1024.0,
      loaded: 1.0 * 1024.0 * 1024.0,
      state: "failed",
    })
  }
  for x in copies {
    @sffixture.fix_transfers.push(x)
  }
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push((name, params))
      // (the made-up core has none of a copy's: taken, as a station takes them)
      if name.has_prefix("drive.transfer.") {
        done(Ok(Json::object({})))
      } else {
        (base.call)(name, params, done)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform~)
  if wide {
    t.resize(1200.0, 800.0)
  }
  t.run_for(@ui.move_most_ms)
  @sfdesk.open_transfers()
  t.draw()
  t.frame()
  if rest {
    t.run_for(@ui.move_most_ms)
  }
  t
}

///|
/// The calls named `name` made.
fn calls_named(calls : Array[(String, Json)], name : String) -> Array[Json] {
  calls.filter(fn(m) { m.0 == name }).map(fn(m) { m.1 })
}

///|
/// Where words `words` are drawn (the first of them): left, top, width, height.
fn transfer_word(t : @ui.Tester, words : String) -> (Double, Double, Double, Double) {
  match t.words().iter().find_first(fn(w) { w.0 == words }) {
    Some(w) => (w.1, w.2, w.3, w.4)
    None => @halt.saying("\{words} is not drawn: \{t.words().map(fn(w) { w.0 }).join("|")}")
  }
}

///|
/// The middle of button `label` (the `i`th of them).
fn button_mid(t : @ui.Tester, label : String, i? : Int = 0) -> (Double, Double) {
  let all = t.all(Button, label~)
  guard all.length() > i else { @halt.saying("no \{label} #\{i}: \{all.length()}") }
  let (x, y, w, h) = all[i].rect
  (x + w / 2.0, y + h / 2.0)
}

///|
test "传输: what is brought, then the downloads, then the copies, each what it is, where it goes and how it stands" {
  for screen in [(2, false), (0, false), (0, true)] {
    let about = "platform \{screen.0}, wide \{screen.1}"
    let calls : Array[(String, Json)] = []
    let t = transfers_up(calls, platform=screen.0, wide=screen.1)
    assert_true(t.find("传输") is Some(_), msg=about)
    let order = ["产品演示.mp4", "周会录音.m4a", "上线演练.mov", "发布包.zip", "演示录屏.mp4", "设计稿", "季度报告.pdf", "旧照片"]
    let tops = order.map(fn(w) { transfer_word(t, w).1 })
    for i in 1..<tops.length() {
      assert_true(tops[i - 1] < tops[i], msg="\{about}: \{order[i - 1]} at \{tops[i - 1]}, \{order[i]} at \{tops[i]}")
    }
    // what is brought: how it stands
    assert_true(t.find("后台缓存 45% · 186 MB") is Some(_) || t.words().iter().any(fn(w) { w.0.has_prefix("后台缓存") }), msg=about)
    // the download: to this device, how far
    assert_true(t.find("到此设备") is Some(_), msg=about)
    assert_true(t.words().iter().any(fn(w) { w.0.has_prefix("正在下载 60%") }), msg=about)
    // the copies: from where to where (moved), how many files while it copies, why it failed
    assert_true(t.find("Willow → Maple › 旅行") is Some(_), msg=about)
    assert_true(t.find("移动 → Maple › 旅行") is Some(_), msg=about)
    assert_true(t.find("18.3 MB / 48.2 MB · 3 个文件") is Some(_), msg=about)
    assert_true(t.find("已完成 · 2 个文件") is Some(_), msg=about)
    assert_true(t.find("空间不足") is Some(_), msg=about)
    assert_true(t.find("已取消") is Some(_), msg=about)
    // the keys: ✕ for each that goes (three brought, the download, the copy), ↻ for the failed copy, 显示 for the done
    assert_eq(t.all(Button, label="停止缓存").length(), 3, msg=about)
    assert_eq(t.all(Button, label="取消下载").length(), 1, msg=about)
    assert_eq(t.all(Button, label="取消传输").length(), 1, msg=about)
    assert_eq(t.all(Button, label="重试").length(), 1, msg=about)
    assert_eq(t.all(Button, label="显示").length(), 1, msg=about)
    // its row's key at its end, level with its words' top: in the list, not past its side
    let (title_x, _, _, _) = transfer_word(t, "传输")
    let (kx, _) = button_mid(t, "取消传输")
    let (sx, _, sw, _) = transfer_word(t, "18.3 MB / 48.2 MB · 3 个文件")
    assert_true(kx > sx + sw && sx > title_x, msg="\{about}: ✕ at \{kx}, status \{sx}+\{sw}, title \{title_x}")
  }
}

///|
test "传输: each key asks the core what it says; 显示 goes to the copy's folder and closes the list" {
  for screen in [(2, false), (0, true)] {
    let about = "platform \{screen.0}, wide \{screen.1}"
    let calls : Array[(String, Json)] = []
    let t = transfers_up(calls, platform=screen.0, wide=screen.1, failed_download=true)
    // what is brought, stopped (the first: 产品演示.mp4)
    let (x, y) = button_mid(t, "停止缓存")
    t.tap(x, y)
    t.draw()
    let stopped = calls_named(calls, "fill.stop")
    assert_eq(stopped.length(), 1, msg=about)
    assert_true(text(Some(stopped[0]), "id") != "", msg=about)
    // the download going, called off; the failed one, asked again
    let (x, y) = button_mid(t, "取消下载")
    t.tap(x, y)
    t.draw()
    assert_eq(calls_named(calls, "download.cancel").length(), 1, msg=about)
    let (x, y) = button_mid(t, "重新下载")
    t.tap(x, y)
    t.draw()
    let again = calls_named(calls, "download.retry")
    assert_eq(again.length(), 1, msg=about)
    assert_true(text(Some(again[0]), "id").has_suffix("日志.tar"), msg="\{about}: \{Repr(again)}")
    // the copy going, called off; the failed one, tried again: each by its station and id
    let (x, y) = button_mid(t, "取消传输")
    t.tap(x, y)
    t.draw()
    let off = calls_named(calls, "drive.transfer.cancel")
    assert_eq(off.length(), 1, msg=about)
    assert_eq(text(Some(off[0]), "station"), "ws1/st2")
    assert_eq(text(Some(off[0]), "id"), "t1")
    let (x, y) = button_mid(t, "重试")
    t.tap(x, y)
    t.draw()
    let retried = calls_named(calls, "drive.transfer.retry")
    assert_eq(retried.length(), 1, msg=about)
    assert_eq(text(Some(retried[0]), "id"), "t3")
    // the list still up
    assert_true(t.find("传输") is Some(_), msg=about)
    // 显示, a moment on: the list goes, the copy's folder shown
    t.run_for(@ui.move_most_ms)
    let (x, y) = button_mid(t, "显示")
    t.tap(x, y)
    t.draw()
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("季度报告.pdf") is None, msg="\{about}: \{t.words().map(fn(w) { w.0 }).join("|")}")
    assert_true(t.find("旅行") is Some(_), msg="\{about}: \{t.words().map(fn(w) { w.0 }).join("|")}")
  }
}

///|
test "传输: a row comes as the core lists it, says how far it is as that changes, and goes; the list closes with the last" {
  let calls : Array[(String, Json)] = []
  let t = transfers_up(calls, copies=[copy_said("t1", "演示录屏.mp4", "copying")])
  assert_true(t.find("演示录屏.mp4") is Some(_))
  // another copy asked: its row, under the one there was
  @sffixture.fix_now(fn() { @sffixture.fix_transfers.push(copy_said("t9", "合同.docx", "copying", said="1 MB / 2 MB")) })
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(transfer_word(t, "合同.docx").1 > transfer_word(t, "演示录屏.mp4").1)
  assert_true(t.find("1 MB / 2 MB") is Some(_))
  // it goes on: what it says with it
  @sffixture.fix_now(fn() {
    @sffixture.fix_transfers[1] = copy_said("t9", "合同.docx", "copying", progress=0.9, said="1.8 MB / 2 MB")
  })
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("1.8 MB / 2 MB") is Some(_))
  assert_true(t.find("1 MB / 2 MB") is None)
  // done: ✕ gone, 显示 there
  @sffixture.fix_now(fn() {
    @sffixture.fix_transfers[1] = copy_said("t9", "合同.docx", "done", progress=1.0, said="已完成")
  })
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq(t.all(Button, label="取消传输").length(), 1)
  assert_eq(t.all(Button, label="显示").length(), 1)
  // the first let go of: its row goes, the other's stays
  @sffixture.fix_now(fn() { @sffixture.fix_transfers.remove(0) |> ignore })
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("演示录屏.mp4") is None)
  assert_true(t.find("合同.docx") is Some(_))
  assert_true(t.find("传输") is Some(_))
  // nothing comes or goes any more: the list closes
  @sffixture.fix_now(fn() {
    @sffixture.fix_transfers.clear()
    @sffixture.fix_downloads.clear()
    @sffixture.fix_keeping_reset()
  })
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("传输") is None)
  assert_true(t.find("合同.docx") is None)
}

///|
test "传输 with keyboard and mouse: a key's name shows by it as the pointer rests on it; Escape closes the list" {
  for wide in [false, true] {
    let calls : Array[(String, Json)] = []
    let t = transfers_up(calls, platform=0, wide~)
    let (x, y) = button_mid(t, "取消传输")
    t.move_to(x, y)
    t.run_for(@sf.tip_delay_ms + @ui.move_most_ms)
    let tip = t.words().iter().find_first(fn(w) { w.0 == "取消传输" })
    assert_true(tip is Some(w) && w.2 > y, msg="wide \{wide}: \{Repr(tip)}, the key at \{y}")
    // drawn over the list: the last of what is drawn under its words its own ground, no larger than it; the list's
    // ground, under it, before it
    let (tx, ty, tw, th) = match tip {
      Some(w) => (w.1, w.2, w.3, w.4)
      None => (0.0, 0.0, 0.0, 0.0)
    }
    let (mx, my) = (tx + tw / 2.0, ty + th / 2.0)
    let under = t.drawn_rects().filter(fn(r) { r.0 <= mx && mx <= r.0 + r.2 && r.1 <= my && my <= r.1 + r.3 })
    assert_true(under.length() >= 2, msg="wide \{wide}: under the tip \{Repr(under)}")
    let top = under[under.length() - 1]
    assert_true(top.2 < 200.0 && top.3 < 40.0, msg="wide \{wide}: the last under the tip \{Repr(top)}")
    assert_true(under[0].2 >= 300.0, msg="wide \{wide}: the first under the tip \{Repr(under[0])}")
    // (Escape shuts the tip first, then the list)
    t.key(@ui.key_escape)
    t.draw()
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("演示录屏.mp4") is Some(_), msg="wide \{wide}")
    t.key(@ui.key_escape)
    t.draw()
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("演示录屏.mp4") is None, msg="wide \{wide}: \{t.words().map(fn(w) { w.0 }).join("|")}")
  }
}

///|
test "传输 on a wide window: beside the rail, its foot level with the rail's key; a press outside closes it" {
  let calls : Array[(String, Json)] = []
  let t = transfers_up(calls, platform=0, wide=true)
  let (x, y, _, _) = transfer_word(t, "传输")
  assert_true(x >= @sfdesk.rail_w && x < @sfdesk.rail_w + 40.0, msg="its title at \{x}")
  // its foot over the window's, its last row's words under its title
  let (_, last_y, _, _) = transfer_word(t, "旧照片")
  assert_true(y < last_y && last_y < 800.0, msg="its title at \{y}, its last row at \{last_y}")
  t.tap(1100.0, 60.0)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("演示录屏.mp4") is None)
}
