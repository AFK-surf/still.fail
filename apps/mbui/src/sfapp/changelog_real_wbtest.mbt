// 更新日志 at the size of the beta's changelog of 2026-11-11 (client/core-ts/test/real-size.ts says it): its Android tab
// held 137 changes of its newest 200, by day 37, 62, 9, 4, 11 and 14, a line about 50 Chinese characters. The page
// makes each part only while it shows (@sf.page_node, View::scrolls_window): the owner found it slow on his phone
// (「还有一些很卡的东西，比如 changelog」), each day one block, a day of 62 changes made whole in the frame it came into
// view and counted 80 high till then. Here it is opened 窄排法 on a phone's 390 × 844 (its list's blocks on its pixels),
// on a source that answers as the core does (a tab asked, its first `limit` changes, how many more), scrolled to its end
// (pages more asked and answered on the way), back to its top, to another tab (answered a while later: what was shown
// stays meanwhile, no bones) and back, and every frame of it is held to that: no more changes made than meet the list's
// room (scrolls_window makes no block past its edges: at most one partly in at each), the whole its bar shows the
// share of counted, as a page comes, within a screen of what the same comes to once made, and the pieces of a day's
// card meeting with no seam. What the window's tree did in the frames (made, laid out, words measured) is printed, not
// asserted (apps/mbui/AGENTS.md: no speed is a verdict).

///|
/// The tabs as the core lists them for Android, and how many changes each has by day (Android's the beta's; the
/// station's some; the others none).
let real_tabs : Array[(String, String, Array[Int])] = [
  ("android", "安卓", [37, 62, 9, 4, 11, 14]),
  ("desktop", "桌面", []),
  ("web", "网页", []),
  ("station", "Station", [12, 20, 9]),
  ("cloud", "云端", []),
]

///|
/// A made-up line of the changelog, about 50 characters as the beta's are.
fn real_line(i : Int) -> String {
  let wheres = ["对话列表", "Station 页面", "更新日志", "设置里的账号", "聊天输入框", "图片预览", "文件面板", "通知"]
  let whats = [
    "在网络断开又恢复后不再一直显示正在连接，切回前台时也会立刻读到最新的消息",
    "滚动到很长的对话中间时不再跳回底部，新消息到来时只在看到最后一条时才跟随",
    "打开时先显示设备上已经有的内容，再在后台读取更新，不再先闪一下空白的骨架",
    "字号调大以后文字不再被截断，按钮在窄屏上换行排列，长名字在中间省略显示",
  ]
  wheres[i * 7 % wheres.length()] + whats[(i * 5 + i / 3) % whats.length()]
}

///|
/// Tab `t`'s changes (real_tabs'), newest first, each with the day it is of.
fn real_changes(t : Int) -> Array[(Int, Json)] {
  let (_, _, days) = real_tabs[t]
  let out = []
  let kinds = [("fix", "修复"), ("improve", "改进"), ("new", "新功能")]
  for d, n in days {
    for _ in 0..<n {
      let i = out.length()
      let version = 8400 - t * 1000 - i * 2
      let line = fn(k : Int) -> Json {
        let (kind, label) = kinds[k % kinds.length()]
        { "kind": Json::string(kind), "label": Json::string(label), "text": Json::string(real_line(k + t * 300)) }
      }
      let lines : Array[Json] = if i % 17 == 5 { [line(i), line(i + 1000)] } else { [line(i)] }
      let note = if i < 4 { "未发布" } else if i < 40 { "更新到 0.1.8320 后可用" } else { "" }
      out.push((d, Json::object({
        "version": Json::number(version.to_double()),
        "versionName": Json::string("0.1.\{version}"),
        "lines": Json::array(lines),
        "has": Json::boolean(i >= 40),
        "note": Json::string(note),
      })))
    }
  }
  out
}

///|
/// The core's `changelog` asked with `params`: every tab, the one asked (`part`; the first where none or another is
/// said) with its first `limit` changes by day and how many it has past them; without a `limit` (an app before it
/// asked one: main's) every tab with all of its changes.
fn real_changelog(params : Map[String, Json]) -> Json {
  let asked = match params.get("part") {
    Some(String(p)) if real_tabs.iter().any(fn(x) { x.0 == p }) => p
    _ => real_tabs[0].0
  }
  let limit = match params.get("limit") {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
  let more = Ref(0)
  let tabs = real_tabs.mapi(fn(t, tab) {
    let (part, label, _) = tab
    let all = real_changes(t)
    let shown = match limit {
      None => all
      Some(l) if part == asked => {
        more.val = @cmp.maximum(0, all.length() - l)
        all[:@cmp.minimum(l, all.length())].to_owned()
      }
      Some(_) => []
    }
    let days : Array[Json] = []
    let mut at = -1
    for c in shown {
      let (d, e) = c
      if d != at {
        at = d
        days.push({
          "day": Json::number((20400 - d).to_double()),
          "label": Json::string(["今天", "昨天", "星期一", "星期日", "星期六", "星期五"][d % 6]),
          "entries": [],
        })
      }
      match days.last() {
        Some(Object(m)) =>
          match m.get("entries") {
            Some(Array(a)) => a.push(e)
            _ => ()
          }
        _ => ()
      }
    }
    Json::object({ "part": Json::string(part), "label": Json::string(label), "days": Json::array(days) })
  })
  let out : Map[String, Json] = { "app": "android", "build": 8320, "tabs": Json::array(tabs) }
  if more.val > 0 {
    out["more"] = Json::number(more.val.to_double())
  }
  Json::object(out)
}

///|
/// The phone's device pixels a point (a Pixel's 2.625).
let real_scale : Double = 2.625

///|
/// What the walk saw: each frame's tree work, where it was in the walk; the faults found.
struct RealSeen {
  frames : Array[(String, @ui.TreeFrame, Int, Double)]
  faults : Array[String]
  asks : Array[String]
  real_h : Double
  /// the whole as counted as each page came and once scrolled through
  wholes : Array[String]
}

///|
/// 更新日志 opened 窄排法 at 390 × 844 on the real-size source, walked as the head says, every frame looked at: what the
/// tree did (with the stage of the walk, the changes alive after it, the list's whole as counted then), the faults
/// (more changes alive than meet the list's room; the whole as counted further than a screen from what it came to).
fn changelog_real_walk() -> RealSeen {
  new_run()
  let asks = []
  // (while held, an ask not answered before is not answered yet: the core's round trip for a tab chosen)
  let hold = @signals.signal(false)
  let answered : Map[String, Bool] = Map([])
  let base = fixture("settings")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "changelog" && !(params.get("news") is Some(True)) {
        let said = Json::object(params).stringify()
        if !asks.contains(said) {
          asks.push(said)
        }
        if !answered.contains(said) && hold.get() {
          return { value: None, error: None, version: 0 }
        }
        answered[said] = true
        return { value: Some(real_changelog(params)), error: None, version: 1 }
      }
      base.topic(name, params).get().snapshot()
    },
  }
  // (on a phone's pixels, 2.625 a point, its list's blocks set on them as every host sets them)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2, scale=real_scale)
  t.set_rows_on_pixels(true)
  t.draw()
  app.nav.push(Settings)
  t.run_for(@ui.move_most_ms)
  let frames = []
  let faults : Array[String] = []
  let said_wholes = []
  // (the list's whole as counted in each frame, with the stage and how many pages had been asked)
  let wholes : Array[(String, Int, Double)] = []
  let tree = @ui.view_tree().unwrap()
  // (the changelog's list: the tallest of the page's lists that show)
  let list = fn() {
    let mut best : (Double, Double, Double, Double)? = None
    for l in tree.lists_reckoned() {
      if l.1 > 0.0 && (best is None || l.0 > best.unwrap().0) {
        best = Some(l)
      }
    }
    best
  }
  // (the changes alive: their versions' words, where each is drawn down the window)
  let versions : Map[String, Bool] = Map([])
  for i, _ in real_tabs {
    for c in real_changes(i) {
      versions[text(Some(c.1), "versionName")] = true
    }
  }
  let alive = fn() {
    tree.drawn().filter(fn(d) { !d.hosted && versions.contains(d.words) }).map(fn(d) { (d.words, d.y) })
  }
  // (the least a change is tall, as laid out: the least step between two changes' versions one under the other)
  let least = Ref(@double.infinity)
  // (the pieces of a day's card: grounds of the card's ink, one under another as wide, that come within a point of each
  // other meet, or they show a seam: within a 64th of a device pixel, what the draw list says a place in (its numbers
  // in 64ths: ui's drawn_text), as the blocks' heights summed in floating point leave them; one further apart shows)
  let card = @ui.tree_theme().color(@ui.Color::Card)
  let seams = fn() {
    let grounds = tree.drawn().filter(fn(d) { !d.hosted && d.ground == card }).map(fn(d) { (d.x, d.y, d.w, d.h) })
    grounds.sort_by(fn(a, b) { if a.0 != b.0 { a.0.compare(b.0) } else { a.1.compare(b.1) } })
    let out = []
    for i in 1..<grounds.length() {
      let (a, b) = (grounds[i - 1], grounds[i])
      let gap = b.1 - (a.1 + a.3)
      if a.0 == b.0 && a.2 == b.2 && gap.abs() < 1.0 && gap.abs() * real_scale > 1.0 / 64.0 {
        out.push(gap)
      }
    }
    out
  }
  let look = fn(stage : String) {
    let seam = seams()
    if seam.length() > 0 && !faults.iter().any(fn(f) { f.has_prefix("seam") }) {
      faults.push("seams between a card's pieces at \{stage}: \{Repr(seam)}")
    }
    let kept = t.tree_frames()
    t.tree_frames_from_now()
    let a = alive()
    let ys = a.map(fn(x) { x.1 })
    ys.sort()
    for i in 1..<ys.length() {
      if ys[i] - ys[i - 1] > 1.0 {
        least.val = @cmp.minimum(least.val, ys[i] - ys[i - 1])
      }
    }
    for f in kept {
      frames.push((stage, f, a.length(), list().map_or(0.0, fn(l) { l.0 })))
    }
    match list() {
      Some(l) => wholes.push((stage, asks.length(), l.0))
      None => ()
    }
  }
  let steps = fn(stage : String, n : Int) {
    for _ in 0..<n {
      t.frame()
      look(stage)
    }
  }
  t.tree_frames_from_now()
  app.nav.push(Setting(Changelog))
  steps("open", 40)
  // to its end, pages more on the way (a wheel's notch of 400 a step)
  let mut was = -1.0
  for _ in 0..<400 {
    t.wheel(195.0, 500.0, 400.0)
    steps("down", 8)
    match list() {
      Some((h, vh, at, _)) if at >= h - vh - 0.5 && at == was => break
      Some((_, _, at, _)) => was = at
      None => ()
    }
  }
  let end = list()
  // back to its top
  for _ in 0..<400 {
    t.wheel(195.0, 500.0, -400.0)
    steps("up", 8)
    match list() {
      Some((_, _, at, _)) if at <= 0.0 => break
      _ => ()
    }
  }
  // to another tab, the core answering it later (what was shown stays meanwhile, no bones), and back
  hold.set(true)
  t.tap_text("Station")
  steps("tab", 20)
  if t.bones_drawn() > 0 {
    faults.push("a tab chosen, not answered yet: its bones (\{t.bones_drawn()})")
  }
  if alive().length() == 0 {
    faults.push("a tab chosen, not answered yet: nothing shown")
  }
  hold.set(false)
  steps("tab", 20)
  t.tap_text("安卓")
  steps("tab back", 40)
  // what the whole came to, all of it made once: as it was counted at its end, every change measured on the way
  let real_h = match end {
    Some(l) => l.0
    None => 0.0
  }
  let vh = match list() {
    Some(l) => l.1
    None => 0.0
  }
  if real_h <= vh {
    faults.push("never longer than its room: \{real_h} in \{vh}")
  }
  // In no frame more changes alive than meet its room: as many as the room holds of the least tall, and one partly in at
  // each edge.
  let most = (vh / least.val).ceil().to_int() + 2
  for f in frames {
    if f.2 > most {
      faults.push("\{f.0}: \{f.2} changes made, more than meet its room (\{vh} high, a change \{least.val} at least: \{most})")
      break
    }
  }
  // As its bar shows it: the whole as counted as a page comes (what it has not made yet as tall as counted) within a
  // screen of what the same comes to once scrolled through, every part of it made (as the next page is asked, or at
  // its end): of the whole, what a page more brings aside, no more than a screen is found otherwise than counted.
  let mut i = 0
  while i < wholes.length() {
    let (stage, pages, first) = wholes[i]
    let mut j = i
    while j + 1 < wholes.length() && wholes[j + 1].0 == stage && wholes[j + 1].1 == pages {
      j = j + 1
    }
    let last = wholes[j].2
    if stage == "down" && (last - first).abs() > vh {
      faults.push("down, \{pages} asked: its whole counted \{first} as it came, \{last} once scrolled through, more than a screen (\{vh}) apart")
    }
    if stage == "down" {
      said_wholes.push("\{pages} asked: \{first} to \{last}")
    }
    i = j + 1
  }
  { frames, faults, asks, real_h, wholes: said_wholes }
}

///|
/// What `seen`'s frames did at most, by stage: nodes made, laid out, words measured, changes alive; its whole as
/// counted, least and most.
fn real_said(seen : RealSeen) -> String {
  let stages = ["open", "down", "up", "tab", "tab back"]
  let lines = ["whole once made \{seen.real_h}; asked: \{Repr(seen.asks)}", "the whole down, by pages asked: \{Repr(seen.wholes)}"]
  for s in stages {
    let fs = seen.frames.filter(fn(f) { f.0 == s })
    let most = fn(get : ((String, @ui.TreeFrame, Int, Double)) -> Double) {
      fs.fold(init=0.0, fn(m, f) { @cmp.maximum(m, get(f)) })
    }
    let least_whole = fs.fold(init=@double.infinity, fn(m, f) { @cmp.minimum(m, f.3) })
    lines.push(
      "\{s}: \{fs.length()} frames; most in one frame: made \{most(fn(f) { f.1.made.to_double() })}, laid \{most(fn(f) { f.1.laid.to_double() })}, measured \{most(fn(f) { f.1.measured.to_double() })}, changes alive \{most(fn(f) { f.2.to_double() })}; whole counted \{least_whole} to \{most(fn(f) { f.3 })}",
    )
  }
  lines.join("\n")
}

///|
test "更新日志 of the beta's size, opened 窄排法, scrolled to its end, back and to another tab: in no frame more changes made than meet its room, its whole counted within a screen of what it is" {
  let seen = changelog_real_walk()
  println(real_said(seen))
  // (its pages asked as it came near their last: a page, then more, each tab's own)
  assert_true(seen.asks.contains("{\"limit\":30}") && seen.asks.contains("{\"limit\":60}"), msg="\{Repr(seen.asks)}")
  assert_true(seen.asks.iter().any(fn(a) { a.contains("station") }), msg="\{Repr(seen.asks)}")
  assert_eq(seen.faults, [])
}
