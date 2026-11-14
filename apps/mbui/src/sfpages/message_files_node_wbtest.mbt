// A message's files as nodes (message_files_node.mbt) and a file's card in a message (sf's file_card_node.mbt).

///|
/// A message's file: `name`, `size` bytes, kept by the agent `ag` at `path` (its name under uploads by default).
fn files_one(name : String, size? : Double = 12345.0, width? : Double = 0.0, height? : Double = 0.0) -> Attachment {
  attachment_of({
    "name": Json::string(name),
    "path": Json::string("/w/uploads/" + name),
    "size": Json::number(size),
    "owner": Json::string("ag"),
    "width": Json::number(width),
    "height": Json::number(height),
  })
}

///|
/// A core that says the downloads in `list` and what it brings once let go in `keeping`, of the agent `ag` on `st`.
fn files_src(list? : Array[Json] = [], keeping? : Array[Json] = [], calls? : Array[(String, Json)] = []) -> Source {
  @sfbase.made_source(
    topic=fn(name, _) {
      if name == "downloads" {
        Some({ "downloads": Json::array(list), "keeping": Json::array(keeping) })
      } else {
        None
      }
    },
    call=fn(name, params, done) {
      calls.push((name, params))
      done(Ok(Json::null()))
    },
  )
}

///|
/// The core's download of the file named `name`: `state`, active or not, how far, what it says.
fn files_download(name : String, state : String, active : Bool, progress : Double, words : String) -> Json {
  {
    "id": Json::string("d-" + name),
    "station": "st",
    "key": "ag",
    "name": Json::string(name),
    "state": Json::string(state),
    "active": Json::boolean(active),
    "progress": Json::number(progress),
    "statusText": Json::string(words),
  }
}

///|
/// Where the files are shown in these tests: out of a list, its chat empty.
fn files_here() -> MessageHere {
  {
    station: "st",
    session: "s1",
    view: @sfbase.chat_view_made({ "title": Json::string(""), "messages": [] }),
    go: None,
    inline: false,
    gutter: 0.0,
    list: None,
    core: None,
  }
}

///|
fn files_place() -> MessageFilesAt {
  let here = files_here()
  { station: fn() { here.station }, session: fn() { here.session }, view: fn() { here.view }, said: fn() { true } }
}

///|
/// A message's files as nodes in a column `w` wide, the core `src`, `mine` whether they are the viewer's.
fn files_new(w : Double, src : Source, list : Array[Attachment], mine : Bool) -> @ui.Tester {
  files_new_by(w, src, fn() { list }, mine)
}

///|
/// The same, the files read as `list` says them as it changes.
fn files_new_by(w : Double, src : Source, list : () -> Array[Attachment], mine : Bool) -> @ui.Tester {
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() { @ui.old_views_here(c) })
    },
    tree=fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      let col = root.box(fn(v) { v.width(Is(Some(w))) |> ignore })
      let popup = root.box(fn(v) { v.over(Is(true)) |> ignore })
      let tips = @sf.TipLayer::new(fn() { Some(popup) })
      message_files_node(col, src, tips, files_place(), list, fn() { mine }, fn() { None }, "")
    },
    w=w + 40.0,
    h=400.0,
    platform=0,
  )
  t.draw()
  t
}

///|
/// How tall a file's card is (a capsule's: file_capsule_h).
fn files_capsule_h() -> Double {
  match @sf.file_capsule_h {
    Fixed(h) => h
    _ => 52.0
  }
}

///|
/// Each card's capsule (its ground, as tall as file_capsule_h), left to right and down: (x, y, w).
fn files_capsules(t : @ui.Tester) -> Array[(Double, Double, Double)] {
  let h = files_capsule_h()
  t.drawn_rects().filter(fn(r) { (r.3 - h).abs() < 0.01 }).map(fn(r) { (r.0, r.1, r.2) })
}

///|
test "a message's file as a card: its capsule as wide as what it says, its name over its size; the viewer's at the column's end; under the pointer, the hover ground" {
  let t = files_new(390.0, files_src(), [files_one("report.pdf")], false)
  let caps = files_capsules(t)
  assert_eq(caps.length(), 1)
  let (cx, cy, cw) = caps[0]
  assert_eq(cx, 0.0)
  assert_true(cw < @sf.file_card_w)
  let (sx, sy, sw, _) = t.rect_of("report").unwrap()
  let (ex, ey, _, _) = t.rect_of(".pdf").unwrap()
  let (mx, my, _, _) = t.rect_of(@sf.file_size(12345.0)).unwrap()
  // (its mark before its words, the extension right after the stem, the size under the name from the same start)
  assert_true(sx > cx + 24.0)
  assert_eq(ex, sx + sw)
  assert_eq(ey, sy)
  assert_eq(mx, sx)
  assert_true(my > sy)
  assert_true(sx + sw < cx + cw)
  assert_eq(t.audit(), [])
  // under the pointer, its ground the hover's
  let ground = fn() { t.drawn_rects().filter(fn(r) { r.1 == cy && r.2 == cw }).map(fn(r) { r.4 }) }
  let at_rest = ground()
  t.move_to(cx + cw / 2.0, cy + 10.0)
  t.run_for(@ui.move_most_ms)
  assert_true(ground() != at_rest)
  t.move_to(380.0, 300.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(ground(), at_rest)
  // the viewer's: at the column's end
  let mine = files_new(390.0, files_src(), [files_one("report.pdf")], true)
  let (mx, _, mw) = files_capsules(mine)[0]
  assert_eq(mx + mw, 390.0)
  assert_eq(mine.audit(), [])
}

///|
test "a message's files in rows by the width given: as wide as two cards and the gap, side by side; a point less, the second at the start of the next row, the gap under the first" {
  let two = [files_one("notes.md", size=900.0), files_one("a-longer-design-document.docx", size=2400000.0)]
  let wide = files_capsules(files_new(760.0, files_src(), two, false))
  assert_eq(wide.length(), 2)
  let across = wide[0].2 + 6.0 + wide[1].2
  for w in [across, across + 0.5] {
    let c = files_capsules(files_new(w, files_src(), two, false))
    assert_eq(c[1].1, c[0].1, msg="\{w}")
    assert_eq(c[1].0, c[0].0 + c[0].2 + 6.0, msg="\{w}")
  }
  for w in [across - 0.5, across - 1.0] {
    let t = files_new(w, files_src(), two, false)
    let c = files_capsules(t)
    assert_eq(c[1].0, 0.0, msg="\{w}")
    assert_eq(c[1].1, c[0].1 + files_capsule_h() + 6.0, msg="\{w}")
    assert_eq(t.audit(), [], msg="\{w}")
  }
}

///|
test "a file the core downloads: how far in its size's place, ✕ calls it off; failed, why, ↻ asks it again; brought once let go, ✕ stops that" {
  let calls : Array[(String, Json)] = []
  let coming = files_new(
    390.0,
    files_src(list=[files_download("report.pdf", "going", true, 0.4, "40% · 4.9 KB")], calls~),
    [files_one("report.pdf")],
    false,
  )
  assert_true(coming.find("40% · 4.9 KB") is Some(_))
  assert_true(coming.find(@sf.file_size(12345.0)) is None)
  assert_true(coming.query(Button, label=@sf.t("web-main.file.retryDownload")) is None)
  coming.click(Button, label=@sf.t("web-main.file.cancelDownload"))
  coming.run_for(@ui.move_most_ms)
  assert_eq(calls.map(fn(c) { c.0 }), ["download.cancel"])
  assert_eq(text(Some(calls[0].1), "id"), "d-report.pdf")
  assert_eq(coming.audit(), [])
  calls.clear()
  let failed = files_new(
    390.0,
    files_src(list=[files_download("report.pdf", "failed", false, 0.2, "网络断开了")], calls~),
    [files_one("report.pdf")],
    false,
  )
  assert_true(failed.find("网络断开了") is Some(_))
  assert_true(failed.query(Button, label=@sf.t("web-main.file.cancelDownload")) is None)
  failed.click(Button, label=@sf.t("web-main.file.retryDownload"))
  failed.run_for(@ui.move_most_ms)
  assert_eq(calls.map(fn(c) { c.0 }), ["download.retry"])
  assert_eq(failed.audit(), [])
  calls.clear()
  let kept = files_new(
    390.0,
    files_src(keeping=[files_download("report.pdf", "yielding", false, 0.7, "70%")], calls~),
    [files_one("report.pdf")],
    false,
  )
  assert_true(kept.find("70%") is Some(_))
  kept.click(Button, label=@sf.t("web-pages.files.stopKeeping"))
  kept.run_for(@ui.move_most_ms)
  assert_eq(calls.map(fn(c) { c.0 }), ["fill.stop"])
  assert_eq(kept.audit(), [])
}

///|
test "a picture among a message's files takes its box by its data before anything is drawn in it: the card after it the gap past it; in a column narrower than it, as wide as the column and as much less high, the card under it" {
  let pic = files_one("shot.png", width=800.0, height=600.0)
  let list = [pic, files_one("report.pdf")]
  let (bw, bh, _) = image_box(pic, image_least, min_side=image_min_side)
  let t = files_new(760.0, files_src(), list, false)
  let c = files_capsules(t)
  assert_eq(c.length(), 1)
  assert_eq(c[0].0, bw + 6.0)
  assert_eq(c[0].1, 0.0)
  assert_eq(t.audit(), [])
  let w = bw - 40.0
  let n = files_new(w, files_src(), list, false)
  let c = files_capsules(n)
  assert_eq(c[0].0, 0.0)
  assert_eq(c[0].1, bh * w / bw + 6.0)
  assert_eq(n.audit(), [])
}

///|
test "a file's card right clicked, or held by a finger, asks for its menu where, and opens nothing; a mouse's button held long opens it as pressed; its ↻ is its own" {
  for platform in [0, 2] {
    let asked : Array[String] = []
    let t = @ui.Tester::new(
      fn(c) {
        @sf.begin(c) |> ignore
        c.with_theme(@sf.ui_theme(), fn() { @ui.old_views_here(c) })
      },
      tree=fn(root) {
        @ui.set_tree_theme(@sf.ui_theme_now)
        let col = root.box(fn(v) { v.width(Is(Some(390.0))) |> ignore })
        let popup = root.box(fn(v) { v.over(Is(true)) |> ignore })
        let tips = @sf.TipLayer::new(fn() { Some(popup) })
        @sf.file_card_node(
          col,
          tips,
          fn() { "report.pdf" },
          fn() { "12 KB" },
          fn() { false },
          fn() { true },
          fn() { false },
          fn() { "重新下载" },
          fn() { "" },
          fn(on) { asked.push("\{on}") },
          menu=fn(x, y) { asked.push("menu \{x.round()},\{y.round()}") },
        )
        |> ignore
      },
      w=430.0,
      h=400.0,
      platform~,
    )
    t.draw()
    let (x, y, _, _) = t.rect_of("report").unwrap()
    let at = "\{x.round()},\{y.round()}"
    if platform == 0 {
      t.right_click(x, y)
      t.run_for(@ui.move_most_ms)
      assert_eq(asked, ["menu \{at}"], msg="\{platform}")
      asked.clear()
    }
    t.press_at(x, y)
    t.run_for(@ui.long_press_ms)
    t.release(x, y)
    t.run_for(@ui.move_most_ms)
    assert_eq(asked, if platform == 0 { ["Open"] } else { ["menu \{at}"] }, msg="\{platform}")
    asked.clear()
    t.tap(x, y)
    t.run_for(@ui.move_most_ms)
    assert_eq(asked, ["Open"], msg="\{platform}")
    asked.clear()
    t.click(Button, label="重新下载")
    t.run_for(@ui.move_most_ms)
    assert_eq(asked, ["Retry"], msg="\{platform}")
    assert_true(t.query(Group, label="report.pdf") is Some(_), msg="\{platform}")
    assert_eq(t.audit(), [], msg="\{platform}")
  }
}

///|
test "a file in the place of another, its key another: what is drawn there is the new file's name and size, not the old one's" {
  let list = @signals.signal([files_one("report.pdf"), files_one("data.csv", size=900.0)])
  let t = files_new_by(390.0, files_src(), fn() { list.get() }, false)
  assert_true(t.find("report") is Some(_))
  assert_true(t.find(@sf.file_size(12345.0)) is Some(_))
  list.set([files_one("budget.xlsx", size=2400000.0), files_one("data.csv", size=900.0)])
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("report") is None)
  assert_true(t.find(".pdf") is None)
  assert_true(t.find(@sf.file_size(12345.0)) is None)
  assert_true(t.find("budget") is Some(_))
  assert_true(t.find(".xlsx") is Some(_))
  assert_true(t.find(@sf.file_size(2400000.0)) is Some(_))
  assert_true(t.find("data") is Some(_))
  assert_eq(files_capsules(t).length(), 2)
  assert_eq(t.audit(), [])
}

///|
test "a long name in a card at its widest: its stem cut short, its extension whole right after it, all of it in the card" {
  for w in [760.0, 390.0] {
    let long = "a-very-long-file-name-that-is-certainly-cut-short-in-its-middle-somewhere.tar.gz"
    let t = files_new(w, files_src(), [files_one(long), files_one("a-longer-design-document.docx")], false)
    let caps = files_capsules(t)
    assert_eq(caps.length(), 2, msg="\{w}")
    for i, pair in [("a-very-long-file-name-that-is-certainly-cut-short-in-its-middle-somewhere.tar", ".gz"), ("a-longer-design-document", ".docx")] {
      let (stem, ext) = pair
      let (cx, _, cw) = caps[i]
      assert_eq(cw, @sf.file_card_w, msg="\{w} \{ext}")
      let (sx, _, sw, _) = t.rect_of(stem).unwrap()
      let (ex, _, ew, _) = t.rect_of(ext).unwrap()
      assert_eq(ex, sx + sw, msg="\{w} \{ext}: right after the stem")
      assert_true(sx > cx && ex + ew <= cx + cw, msg="\{w} \{ext}: \{sx}..\{ex + ew} in \{cx}..\{cx + cw}")
    }
    assert_eq(t.audit(), [], msg="\{w}")
  }
}

///|
test "a file's card whose name shows cut short says it whole by it as the pointer rests on it; one whose name shows whole, nothing" {
  let long = "一份说得很长很长的季度财务报告最终版本第三稿.pdf"
  for name in [long, "report.pdf"] {
    let t = files_new(390.0, files_src(), [files_one(name)], false)
    let (cx, cy, cw) = files_capsules(t)[0]
    t.move_to(cx + cw / 2.0, cy + 10.0)
    t.run_for(@sf.tip_delay_ms + @ui.move_most_ms)
    let tips = t.semantics().filter(fn(s) { s.role == Tooltip }).map(fn(s) { s.label })
    assert_eq(tips, if name == long { [long] } else { [] }, msg=name)
  }
}
