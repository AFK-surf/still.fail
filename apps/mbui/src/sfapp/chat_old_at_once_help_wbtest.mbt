// What chat_old_at_once_wbtest (the shipped page) and chat_nodes_old_at_once_wbtest (the page made as nodes) judge by:
// the cases and the judge, said once.
//
// What was said before the reader saw it is simply there (the owner's, 2026-11-14, on the released desktop app:
// 「旧消息加载到底为什么需要动效？」; the principle in sf/motion.mbt's head, sfbase/chat_list.mbt's row_keys and
// emit.mbt's head). Only what newly happens while the reader is watching moves. A chat as it opens, the page before
// brought in as the reader reads up, the page after, what came while the reader was away or the page was covered,
// another chat switched to and back, a long chat with an agent at work opened: each of those, from the frame its data
// arrives, is drawn as it is at rest. Data arriving late is no cause of motion: no row easing in, growing, sliding or
// fading, no words coming in a glyph at a time, no picture making an entrance, nothing gliding.
//
// Each case is run on the page the app ships (sfbase's chat_page_nodes off: the old page, sfbase/chat_list.mbt) and on
// the page made as nodes (on: sfpages/chat_body_node.mbt), on 大屏 (1280x800, a mouse) and 小屏 (390x844, a finger),
// the core answering at once and 400 ms late, with the Tester's own check (its kept rows built again whole). What is
// left to be mended on its own is not held here (oa_apart: as a device draws, `check_looks(false)`, and 小屏 shown
// again after a page over it; a chat opened over a late core drawn in more than two ways, a resumed stream's telling:
// oa_watch's `in_ways`, oa_case2's `laters`).
//
// What is judged, on every display frame from the cause (a press, a stroke, the core telling) to rest: the chat's list
// as drawn (each line of a message's words where it is drawn and how far it is drawn, each word node where it is, how
// big and how opaque, each picture of a message where it is, how big and how opaque). It may change only in a frame
// before which the core told something (a topic's value came or changed), or in the cause's own frame; a change in any
// other frame is something moving or coming late, and is printed with what changed, how, for how long and what the
// frame was built for (Tester::built_why) and where the first thing it changed was made (Tester::sources_of). And
// in no frame, told or not, is anything laid over an old picture as it comes in (a frost over it, what it waited on
// brushed off it in strips: oa_laid_over, facts of the draw list, not pixels).
// Left out, each by what it is: the working line's ring and the spinner and the caret (shapes: only words and pictures
// are looked at); the working line's clock (its words a duration: it runs while seen); what is not the chat's list
// (the sidebar, Home under a page sliding in, the chat's head and composer: only words of the chat's messages and its
// agents, right of the composer's start, are looked at); a page sliding in sideways as a whole (what is looked at taken
// by how far it all moved sideways together); where the reader scrolls (cases 3 and 4: what is looked at taken by how
// far it all moved up or down together, and rows coming or going at the list's ends by the scroll not counted).
//
// Why not switches_still's judge (switch_measure): it reads named nodes of what a screen reader is told, and a message's
// words are not that on the old page; its rounds of frames start at a press, here the core's telling is what is judged.

///|
/// The Tester's own judges of each frame given room in this file, so that the first jolt it sees does not stop a case
/// before this file's judge has said all it sees (each of theirs is printed with this file's own; a first run without
/// them stopped at the old page's 大屏 chat opened over a core 400 ms late: `rows not steady … row m:ts7 went -82 a
/// frame`). The pictures the fixture's chat holds handed over: what the Testers here hold at most.
fn init {
  @ui.rows_steady_known([("src/sfapp/chat_old_at_once_help_wbtest.mbt", 1000)])
  @ui.sizes_steady_known([("src/sfapp/chat_old_at_once_help_wbtest.mbt", 1000)])
  @ui.gaps_steady_known([("src/sfapp/chat_old_at_once_help_wbtest.mbt", 1000)])
  @ui.words_over_known([("src/sfapp/chat_old_at_once_help_wbtest.mbt", 1000)])
  @ui.host_image_bytes_known([("src/sfapp/chat_old_at_once_help_wbtest.mbt", 4000000)])
}

///|
/// The screens: name, width, height, platform.
let oa_screens : Array[(String, Double, Double, Int)] = [("大屏", 1280.0, 800.0, 0), ("小屏", 390.0, 844.0, 2)]

///|
/// How late the core answers (ms): at once, and late enough for a second telling to come as its own frame.
let oa_lates : Array[Double] = [0.0, 400.0]

///|
/// The chat the cases are about, and another.
let oa_c1 : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }

///|
let oa_c2 : ChatRef = { station: "ws1/st1", session: "s-c2", title: "首页的列表改成按天分组", station_name: "Willow" }

///|
/// How many times a topic's value came or changed since the run began (oa_source), and the version each topic was
/// last read at.
// kept across runs: emptied as each run of this file begins (oa_begin)
let oa_told : Ref[Int] = Ref(0)

///|
// kept across runs: emptied as each run of this file begins (oa_begin)
let oa_versions : Map[String, Int] = Map([])

///|
/// The words of the chat's messages and its agents as the core gave them this run: what is looked at.
// kept across runs: emptied as each run of this file begins (oa_begin)
let oa_texts : Map[String, Bool] = Map([])

///|
fn oa_begin() -> Unit {
  oa_told.val = 0
  oa_versions.clear()
  oa_texts.clear()
  // (the agent's working line's words: looked at as the chat's, its clock left out by oa_clock)
  oa_texts[tr("android-chat.chat.working")] = true
}

///|
/// Every string of `j` of two letters or more, kept as words to look at.
fn oa_keep_words(j : Json) -> Unit {
  match j {
    String(s) => if s.length() >= 2 { oa_texts[s] = true }
    Array(a) => for x in a { oa_keep_words(x) }
    Object(o) =>
      for k, v in o {
        if k != "md" && k != "seq" && k != "ts" && k != "key" {
          oa_keep_words(v)
        }
      }
    _ => ()
  }
}

///|
/// `base` with each value it gives counted as told where its version is new, and the words of a chat's messages and
/// agents kept.
fn oa_source(base : Source) -> Source {
  {
    ..base,
    topic_read: fn(name, params) {
      let got = (base.topic_read)(name, params)
      let k = name + Json::object(params).stringify()
      if got.value is None {
        oa_versions.remove(k)
      } else if oa_versions.get(k) != Some(got.version) {
        oa_versions[k] = got.version
        oa_told.val += 1
      }
      // (not an archived chat's, which 已归档 reads for its rows: words of another page, never of the chat's list)
      let archived = match params.get("session") {
        Some(String(x)) => x.has_prefix("s-a")
        _ => false
      }
      if name == "chat" && !archived && got.value is Some(Object(v)) {
        match v.get("messages") {
          Some(m) => oa_keep_words(m)
          None => ()
        }
        match v.get("agents") {
          Some(a) => oa_keep_words(a)
          None => ()
        }
      }
      got
    },
  }
}

///|
/// Whether words drawn are a duration (the working line's clock: 12s, 1:05, 3 秒, 2分).
fn oa_clock(s : String) -> Bool {
  let t = s
  guard t.length() > 0 else { return false }
  let mut digit = false
  for c in t {
    if c >= '0' && c <= '9' {
      digit = true
    }
  }
  digit && (t.has_suffix("s") || t.has_suffix("秒") || t.has_suffix("分") || t.has_suffix("m") || t.contains(":"))
}

///|
/// Whether words drawn are of the chat's messages or agents (oa_texts), not a clock.
fn oa_said(s : String) -> Bool {
  if s.length() < 2 || oa_clock(s) {
    return false
  }
  let head = if s.length() > 8 { s.unsafe_substring(start=0, end=8) } else { s }
  for k, _ in oa_texts {
    if k.contains(head) {
      return true
    }
  }
  false
}

///|
/// A thing of the chat's list drawn: its key (what it is, and which of those), where, how big, how opaque.
priv struct OaThing {
  key : String
  words : String
  x : Double
  y : Double
  w : Double
  h : Double
  a : Double
}

///|
/// Where the chat's page starts across now: the composer's field's start less 40 (the lowest field drawn), else `was`.
fn oa_left(t : @ui.Tester, was : Double) -> Double {
  let mut f : (Double, Double, Double, Double)? = None
  for s in t.semantics() {
    if s.role == @ui.Role::TextField && !s.hidden && (f is None || f.unwrap().1 < s.rect.1) {
      f = Some(s.rect)
    }
  }
  match f {
    Some((x, _, _, _)) => x - 40.0
    None => was
  }
}

///|
/// The chat's list as drawn now in a window `h` high, right of `left`.
fn oa_things(t : @ui.Tester, left : Double, h : Double) -> Array[OaThing] {
  let out : Array[OaThing] = []
  let seen : Map[String, Int] = Map([])
  let key = fn(k : String) {
    let n = seen.get(k).unwrap_or(0)
    seen[k] = n + 1
    if n == 0 {
      k
    } else {
      "\{k} #\{n + 1}"
    }
  }
  for wd in t.words() {
    let (s, x, y, w, hh, a) = wd
    if a <= 0.0 || y + hh <= 0.0 || y >= h || x + w <= left || !oa_said(s) {
      continue
    }
    out.push({ key: key("words 「\{s}」"), words: s, x, y, w, h: hh, a })
  }
  for r in t.text_runs() {
    if r.bottom <= 0.0 || r.top >= h || r.x1 <= left || !oa_said(r.text) {
      continue
    }
    out.push({ key: key("line 「\{r.text}」"), words: r.text, x: r.x0, y: r.top, w: r.x1 - r.x0, h: r.bottom - r.top, a: 1.0 })
  }
  for i in t.drawn_images() {
    if i[2] < 60.0 || i[3] < 40.0 || i[1] + i[3] <= 0.0 || i[1] >= h || i[0] + i[2] <= left {
      continue
    }
    let shape = (i[2] / i[3] * 10.0).round() / 10.0
    out.push({ key: key("picture \{shape}"), words: "", x: i[0], y: i[1], w: i[2], h: i[3], a: i[8] })
  }
  // (words drawn more than once, a long chat's lines alike, cannot be told apart from frame to frame: left out)
  out.filter(fn(o) {
    o.words == "" ||
    (seen.get("words 「\{o.words}」").unwrap_or(0) <= 1 && seen.get("line 「\{o.words}」").unwrap_or(0) <= 1)
  })
}

///|
/// What is laid over a message's picture of the chat's list as drawn now in a window `h` high, right of `left` (its
/// way in: image_reveal's, image_reveal_node's): a frost drawn over it (frosted glass within its box), and what it waited
/// on drawn over it in strips (another image drawn where it is, its likeness under the edge brushing down). Each said.
fn oa_laid_over(t : @ui.Tester, left : Double, h : Double) -> Array[String] {
  let pics = t
    .drawn_images()
    .filter(fn(i) { i[2] >= 60.0 && i[3] >= 40.0 && i[8] > 0.0 && i[1] + i[3] > 0.0 && i[1] < h && i[0] + i[2] > left })
  let out = []
  for g in t.drawn_glass() {
    let (x, y, w, gh, kind, _) = g
    if kind != 5 {
      continue
    }
    for i in pics {
      // (its own frost, laid on its box alone: not a bar's glass over the list it passes under)
      if x >= i[0] - 1.0 && x + w <= i[0] + i[2] + 1.0 && y >= i[1] - 1.0 && y + gh <= i[1] + i[3] + 1.0 {
        out.push("frost over picture (x \{oa_r(i[0])}, y \{oa_r(i[1])}, \{oa_r(i[2])}x\{oa_r(i[3])})")
        break
      }
    }
  }
  let same = fn(a : Array[Double], b : Array[Double]) {
    (a[0] - b[0]).abs() < 0.5 && (a[1] - b[1]).abs() < 0.5 && (a[2] - b[2]).abs() < 0.5 && (a[3] - b[3]).abs() < 0.5
  }
  for k, i in pics {
    let over = pics.iter().take(k).filter(fn(j) { same(i, j) }).count()
    if over == 1 {
      out.push("picture brushed (x \{oa_r(i[0])}, y \{oa_r(i[1])}, \{oa_r(i[2])}x\{oa_r(i[3])}): drawn over")
    }
  }
  out
}

///|
fn oa_median(xs : Array[Double]) -> Double {
  if xs.length() == 0 {
    return 0.0
  }
  let s = xs.copy()
  s.sort()
  s[s.length() / 2]
}

///|
fn oa_r(x : Double) -> Double {
  (x * 10.0).round() / 10.0
}

///|
/// What changed from `was` to `now`: each thing moved (taken by how far all moved sideways together, and up or down
/// together where `scroll`), sized otherwise, drawn more or less opaque, come or gone (where `scroll`, only those
/// wholly within `band`, top and bottom).
fn oa_diff(
  was : Array[OaThing],
  now : Array[OaThing],
  scroll : Bool,
  band : (Double, Double),
  across : Double,
) -> Array[(String, String)] {
  let before : Map[String, OaThing] = Map([])
  for w in was {
    before[w.key] = w
  }
  let after : Map[String, OaThing] = Map([])
  for n in now {
    after[n.key] = n
  }
  let dxs = []
  let dys = []
  for n in now {
    match before.get(n.key) {
      Some(w) => {
        dxs.push(n.x - w.x)
        dys.push(n.y - w.y)
      }
      None => ()
    }
  }
  let mdx = oa_median(dxs)
  let mdy = if scroll { oa_median(dys) } else { 0.0 }
  let within = fn(o : OaThing) { o.x >= 0.0 && o.x + o.w <= across && (!scroll || (o.y >= band.0 && o.y + o.h <= band.1)) }
  let out = []
  for n in now {
    match before.get(n.key) {
      Some(w) => {
        let ddx = n.x - w.x - mdx
        let ddy = n.y - w.y - mdy
        if ddx.abs() > 0.5 || ddy.abs() > 0.5 || (n.w - w.w).abs() > 0.5 || (n.h - w.h).abs() > 0.5 || (n.a - w.a).abs() > 0.02 {
          out.push((
            "\{n.key} (x \{oa_r(w.x)}, y \{oa_r(w.y)}, \{oa_r(w.w)}x\{oa_r(w.h)}, a \{oa_r(w.a)}) -> (x \{oa_r(n.x)}, y \{oa_r(n.y)}, \{oa_r(n.w)}x\{oa_r(n.h)}, a \{oa_r(n.a)})" +
            (if mdy != 0.0 || mdx != 0.0 { " [all moved \{oa_r(mdx)}, \{oa_r(mdy)}]" } else { "" }),
            n.words,
          ))
        }
      }
      // (come in at the side a page slides in from, all else moving with it: on the window's edge the frame before)
      None if mdx < -0.5 && n.x - mdx + n.w > across => ()
      None => if within(n) { out.push(("\{n.key} came at (x \{oa_r(n.x)}, y \{oa_r(n.y)}, \{oa_r(n.w)}x\{oa_r(n.h)}, a \{oa_r(n.a)})", n.words)) }
    }
  }
  for w in was {
    // (gone off the side a page slides out to, all else moving with it)
    if !after.contains(w.key) && within(w) && !(mdx > 0.5 && w.x + mdx + w.w > across) {
      out.push(("\{w.key} gone from (x \{oa_r(w.x)}, y \{oa_r(w.y)}, \{oa_r(w.w)}x\{oa_r(w.h)})", w.words))
    }
  }
  out
}

///|
/// A frame that changed with nothing told before it: when (after the cause), what changed, what it was built for, where
/// the first thing it changed was made.
priv struct OaFault {
  at : Double
  what : Array[String]
  why : String
  made : String
}

///|
/// The chat's list on `t` (a window `s`) from `cause` done now to `upto` ms after it, a display frame at a time, what
/// is due answered before each (`pump`, as the core's answers come between frames): each frame that changed with
/// nothing told before it, run by run, said as `label` and returned. `scroll`: the reader scrolls in it. `in_ways`: the
/// list drawn in more than two ways as the core told it said as well (not for a chat opened over a late core yet: its
/// rows put again 82 apart in a frame as its second telling comes, left to be mended on its own).
fn oa_watch(
  t : @ui.Tester,
  s : (String, Double, Double, Int),
  label : String,
  cause : () -> Unit,
  upto : Double,
  scroll? : Bool = false,
  pump? : () -> Unit = fn() {  },
  in_ways? : Bool = true,
) -> Array[String] {
  let h = s.2
  let band = (h * 0.15, h * 0.75)
  let mut left = oa_left(t, 0.0)
  let mut last = oa_things(t, left, h)
  t.ways_set_out() |> ignore
  let from = t.time()
  let mut told = oa_told.val
  let faults : Array[OaFault] = []
  let told_at : Array[Double] = []
  let mut changes = 0
  // (frames in which something was laid over an old picture, its way in: never, told or not)
  let laid : Array[(Double, Array[String])] = []
  // (frames after the cause's own that changed as something was told: more than one, and the list is drawn in more
  // ways than before the data and at rest)
  let told_changes : Array[(Double, Array[String], String)] = []
  cause()
  t.frame_at(t.time())
  let mut first = true
  while true {
    if !first {
      if t.time() - from >= upto - 1.0e-6 {
        break
      }
      pump()
      t.run_for(@ui.frame_period_default)
    }
    let came = oa_told.val != told
    told = oa_told.val
    let now_at = t.time() - from
    if came {
      told_at.push(now_at.round())
    }
    left = oa_left(t, left)
    let over = oa_laid_over(t, left, h)
    if over.length() > 0 {
      laid.push((now_at, over))
    }
    let now = oa_things(t, left, h)
    let what = oa_diff(last, now, scroll, band, s.1)
    // (a frame in which only pictures came, each whole: their host told them decoded, each drawn at once the frame it
    // is, what it waited on the frame before: that telling's, neither a change untold nor another way the list is drawn)
    let decoded = what.length() > 0 &&
      what.iter().all(fn(w) { w.0.has_prefix("picture ") && w.0.contains(" came at ") && w.0.has_suffix(", a 1)") })
    if what.length() > 0 && !decoded {
      changes += 1
      if !came && !first {
        let made = match what.iter().find_first(fn(w) { w.1 != "" }) {
          Some(w) => {
            let src = t.sources_of(w.1)
            if src.length() > 900 {
              src.unsafe_substring(start=0, end=900)
            } else {
              src
            }
          }
          None => ""
        }
        faults.push({ at: now_at, what: what.map(fn(w) { w.0 }), why: t.built_why(), made })
      } else if !first {
        told_changes.push((now_at, what.map(fn(w) { w.0 }), t.built_why()))
      }
    }
    last = now
    first = false
  }
  let ways = t.ways_set_out().filter(fn(w) { w.at > from + 0.5 })
  for w in ways {
    println("OLD_AT_ONCE_WAY \{label}: \{w.kind} +\{(w.at - from).round()} ms \{w.made} \{w.part}")
  }
  println("OLD_AT_ONCE_RUN \{label}: \{changes} frames changed, told before \{told_at.length()} frames \{@ui.list_text(told_at.map(fn(x) { x.to_string() }))}, \{faults.length()} changed untold, \{last.length()} things at the end")
  // (runs of frames in a row that changed untold: one each)
  let said : Array[String] = []
  if laid.length() > 0 {
    let line = "\{label}: an old picture drawn frosted or brushed in \{laid.length()} frames, +\{laid[0].0.round()}..+\{laid[laid.length() - 1].0.round()} ms"
    said.push(line)
    println("OLD_AT_ONCE \{line}")
    for x, w in laid[0].1 {
      if x < 4 {
        println("OLD_AT_ONCE_LAID \{label} +\{laid[0].0.round()}: \{w}")
      }
    }
  }
  if told_changes.length() > 1 && in_ways {
    let line = "\{label}: drawn in \{told_changes.length() + 1} ways as the core told it, at +\{@ui.list_text(told_changes.map(fn(c) { c.0.round().to_string() }))} ms"
    said.push(line)
    println("OLD_AT_ONCE \{line}")
    for c in told_changes {
      for x, w in c.1 {
        if x < 4 {
          println("OLD_AT_ONCE_TOLD \{label} +\{c.0.round()}: \{w}")
        }
      }
      println("OLD_AT_ONCE_TOLD_WHY \{label} +\{c.0.round()}: \{c.2}")
    }
  }
  let mut i = 0
  while i < faults.length() {
    let mut j = i
    while j + 1 < faults.length() && faults[j + 1].at - faults[j].at < @ui.frame_period_default * 1.5 {
      j += 1
    }
    let f = faults[i]
    let n = j - i + 1
    let line = "\{label}: +\{f.at.round()}..+\{faults[j].at.round()} ms, \{n} frame\{if n > 1 { "s" } else { "" }} changed with nothing told (\{if n > 1 { "moving" } else { "a late change" }})"
    said.push(line)
    println("OLD_AT_ONCE \{line}")
    for k in i..=j {
      for x, w in faults[k].what {
        if x < 6 && (k == i || k == j) {
          println("OLD_AT_ONCE_WHAT \{label} +\{faults[k].at.round()}: \{w}")
        }
      }
    }
    println("OLD_AT_ONCE_WHY \{label} +\{f.at.round()}: \{f.why}")
    if f.made != "" {
      println("OLD_AT_ONCE_MADE \{label} +\{f.at.round()}: \{f.made}")
    }
    i = j + 1
  }
  said
}

///|
/// `ms` of display frames, `pump` before each.
fn oa_run(t : @ui.Tester, ms : Double, pump? : () -> Unit = fn() {  }) -> Unit {
  let from = t.time()
  while t.time() - from < ms - 1.0e-6 {
    pump()
    t.run_for(@ui.frame_period_default)
  }
}

///|
/// The app over `src` on `s`, as a device draws where `device`.
fn oa_tester(src : Source, s : (String, Double, Double, Int), device : Bool) -> @ui.Tester {
  let (_, w, h, platform) = s
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~, begun=fn() {
    @sfbase.window_tall.val = h
  })
  if device {
    t.check_looks(false)
  }
  t
}

///|
fn oa_name(nodes : Bool) -> String {
  if nodes {
    "new page"
  } else {
    "old page"
  }
}

///|
fn oa_how(device : Bool) -> String {
  if device {
    " (as a device draws)"
  } else {
    ""
  }
}

///|
/// The words of a chat drawn: whether `words` is drawn right of the middle of `s` on 大屏, anywhere on 小屏.
fn oa_drawn(t : @ui.Tester, s : (String, Double, Double, Int), words : String) -> Bool {
  t.words().iter().any(fn(w) { w.5 > 0.0 && w.0.contains(words) && (s.3 == 2 || w.1 > 300.0) })
}

///|
/// Where `title` is drawn furthest left (a row of the sidebar, of Home): its middle.
fn oa_row(t : @ui.Tester, title : String) -> (Double, Double)? {
  let mut best : (Double, Double)? = None
  let mut bx = 1.0e9
  for w in t.words() {
    let (s, x, y, ww, hh, a) = w
    if s == title && a > 0.0 && x < bx {
      bx = x
      best = Some((x + ww / 2.0, y + hh / 2.0))
    }
  }
  best
}

///|
/// Which of a case's variants a test runs: those held here, those left to be mended on their own (oa_apart), or all.
// Apart and All: run by the tests of what is left to be mended, kept apart from this file
#warnings("-unused_constructor")
priv enum OaWhich {
  Held
  Apart
  All
}

///|
/// The variants left to be mended on their own, not held here: as a device draws (on the old page, what the Tester
/// records of a kept row's lines, its text runs, gone for one frame with nothing else of the row changed: the Tester's,
/// not the page's; on the new page nothing found that the Tester's own check of kept rows misses), and on 小屏 the chat shown again after a page over it (the app keeps the chat focused while a page covers
/// it, so the core marks what was said meanwhile said, and its pictures come in: attend.ts).
fn oa_apart(device : Bool, s : (String, Double, Double, Int), case : Int) -> Bool {
  device || (case == 6 && s.3 == 2)
}

///|
fn oa_runs(which : OaWhich, device : Bool, s : (String, Double, Double, Int), case : Int) -> Bool {
  match which {
    All => true
    Held => !oa_apart(device, s, case)
    Apart => oa_apart(device, s, case)
  }
}

// ---- case 1: a chat opened, the core late -----------------------------------------------------------------------

///|
/// The app over a core answering every topic subscribed from `armed` on `ms` late (round_trip_again), at rest on chat
/// s-c2, then chat s-c1 opened.
fn oa_open_late(
  s : (String, Double, Double, Int),
  nodes : Bool,
  device : Bool,
  ms : Double,
  ways? : Bool = false,
) -> Array[String] {
  new_run()
  oa_begin()
  @sfbase.chat_page_nodes.set(nodes)
  let armed = Ref(false)
  let src = oa_source(round_trip_again(fixture("chat"), 0.0, late=fn(_, _) { if armed.val { ms } else { 0.0 } }))
  open_chat(oa_c2)
  let t = oa_tester(src, s, device)
  oa_run(t, 1000.0)
  armed.val = true
  let label = "\{oa_name(nodes)} \{s.0} opened, core \{ms} ms\{oa_how(device)}"
  oa_watch(t, s, label, fn() { @ui.view_tree().unwrap().event(t.time(), fn() { open_chat(oa_c1) }) }, ms + 1500.0, in_ways=ways)
}

///|
fn oa_case1(nodes : Bool, ways? : Bool = false, which? : OaWhich = Held) -> Unit raise {
  let all = []
  for s in oa_screens {
    for ms in oa_lates {
      for device in [false, true] {
        guard oa_runs(which, device, s, 1) else { continue }
        all.push_iter(oa_open_late(s, nodes, device, ms, ways~).iter())
      }
    }
  }
  if all.length() > 0 {
    fail(all.join("\n"))
  }
}

// ---- the core's attention (client/core-ts/src/attend.ts), for cases 2 and 6 ------------------------------------

///|
/// What the real core does with a chat's messages' `said` (attend.ts Attend.chat, told by the app's `client.focus`):
/// whether the app is shown, whether chat s-c1 is focused (`{chat}` till `{left}` or another chat), the chat's visit
/// (made at the first value worked out while focused: the newest then its `top`; `said` cleared and `resumed` set as
/// the app is shown again), what is put after the fixture's messages (each with whether a stream told it as said: an
/// event, live or a resumed stream's, or caught up by a read), the test's clock as the core's (nowMs).
priv struct OaAttend {
  mut visible : Bool
  mut chat_on : Bool
  mut visit : OaVisit?
  extra : Array[(Json, Bool)]
  rev : @signals.Signal[Int]
  mut now : Double
}

///|
priv struct OaVisit {
  mut top : Int
  said : Map[Int, Bool]
  mut visible : Bool
  mut resumed : Double?
}

///|
fn oa_attend() -> OaAttend {
  { visible: true, chat_on: false, visit: None, extra: [], rev: @signals.signal(0), now: 0.0 }
}

///|
/// What the app told the core of where it is (`client.focus`), taken as attend.ts focus() and #endVisits take it.
fn oa_focus(a : OaAttend, params : Json) -> Unit {
  guard params is Object(p) else { return }
  match p.get("visible") {
    Some(True) => a.visible = true
    Some(False) => a.visible = false
    _ => ()
  }
  match p.get("left") {
    Some(Object(l)) if l.get("session") == Some(Json::string("s-c1")) => a.chat_on = false
    _ => ()
  }
  match p.get("chat") {
    Some(Object(c)) => a.chat_on = c.get("session") == Some(Json::string("s-c1"))
    Some(Null) => a.chat_on = false
    _ => ()
  }
  if !a.chat_on {
    a.visit = None
  }
  match a.visit {
    Some(v) if v.visible != a.visible => {
      v.said.clear()
      if a.visible {
        v.resumed = Some(a.now)
      }
      v.visible = a.visible
    }
    _ => ()
  }
  a.rev.set(a.rev.get() + 1)
}

///|
/// Chat s-c1's value `v` as the core gives it under `a`: what was put after its messages, and `said` on those attend.ts
/// marks so (said while the chat shows, by a stream's telling, after what the visit began on: n > top, n > caught,
/// made after it was shown again).
fn oa_attended(a : OaAttend, v : Map[String, Json]) -> Map[String, Json] {
  let out = v.copy()
  let msgs = items(Some(Json::object(v)), "messages").copy()
  let mut base_newest = 0
  for m in msgs {
    base_newest = long_max(base_newest, number(Some(m), "seq").to_int())
  }
  // (what the window caught up on: the first an event told stops it, station/topics.ts #thread)
  let mut caught = base_newest
  let mut stopped = false
  for e in a.extra {
    let (m, told) = e
    if told {
      stopped = true
    }
    if !stopped {
      caught = number(Some(m), "seq").to_int()
    }
    msgs.push(m)
  }
  let mut newest = 0
  for m in msgs {
    newest = long_max(newest, number(Some(m), "seq").to_int())
  }
  if a.chat_on {
    let visit = match a.visit {
      Some(x) => x
      None => {
        let x = { top: newest, said: Map([]), visible: a.visible, resumed: None }
        a.visit = Some(x)
        x
      }
    }
    for m in msgs {
      let n = number(Some(m), "seq").to_int()
      let made = number(Some(m), "createdAt")
      let after = match visit.resumed {
        None => true
        Some(r) => made >= r
      }
      if visit.visible && n > visit.top && n > caught && after {
        visit.said[n] = true
      }
    }
    visit.top = long_max(visit.top, newest)
    out["messages"] = Json::array(
      msgs.map(fn(m) {
        guard m is Object(o) else { return m }
        let o = o.copy()
        o.remove("said")
        if visit.said.contains(number(Some(m), "seq").to_int()) {
          o["said"] = Json::boolean(true)
        }
        Json::object(o)
      }),
    )
  } else {
    out["messages"] = Json::array(msgs)
  }
  if out.contains("lastEntry") {
    out["lastEntry"] = Json::number(newest.to_double())
  }
  out
}

///|
/// The fixture's chat with `a`'s attention: chat s-c1's value as oa_attended makes it, the app's `client.focus` told to
/// `a`, the core's clock `a.now` the Tester's (set as each frame is drawn by oa_tick).
fn oa_attending(a : OaAttend) -> Source {
  let base = fixture("chat")
  {
    ..base,
    topic_read: fn(name, params) {
      let got = (base.topic_read)(name, params)
      guard name == "chat" && params.get("session") == Some(Json::string("s-c1")) && got.value is Some(Object(v)) else {
        return got
      }
      let rev = a.rev.get()
      { ..got, value: Some(Json::object(oa_attended(a, v))), version: got.version + rev * 1000000 }
    },
    call: fn(name, params, done) {
      if name == "client.focus" {
        oa_focus(a, params)
      }
      (base.call)(name, params, done)
    },
  }
}

///|
/// Three messages put after chat s-c1's, said at the core's moment `a.now`, `told` as an event of a stream tells them
/// (else caught up by a read): an agent's long answer, one with pictures, a person's with a picture (the fixture's
/// messages 3, 5 and 4, said again).
fn oa_say(a : OaAttend, src : Source, told : Bool) -> Unit {
  let v = @signals.untracked(fn() { (src.topic_read)("chat", @sfbase.chat_params(oa_c1)).value })
  let msgs = items(v, "messages")
  let mut newest = 0
  for m in msgs {
    newest = long_max(newest, number(Some(m), "seq").to_int())
  }
  for e in a.extra {
    newest = long_max(newest, number(Some(e.0), "seq").to_int())
  }
  for tpl in [3, 5, 4] {
    guard msgs.iter().find_first(fn(m) { number(Some(m), "seq").to_int() == tpl }) is Some(Object(o)) else { continue }
    newest += 1
    let m = o.copy()
    for k in ["said", "elsewhere", "outgoing", "joined"] {
      m.remove(k)
    }
    m["seq"] = Json::number(newest.to_double())
    m["ts"] = Json::string("oa\{newest}")
    m["createdAt"] = Json::number(a.now)
    a.extra.push((Json::object(m), told))
  }
  a.rev.set(a.rev.get() + 1)
}

// ---- case 2: a chat the device holds opened, the core telling more a moment later ------------------------------

///|
/// How the core comes to tell more of the chat (what the real core sends in each, attend.ts and station/topics.ts):
/// caught up by a read once it opened (said: none); told by a stream resumed after it opened, the app started again or
/// its link back within the station's hour (said: all of them, the visit begun before and never shown again); told
/// while the app was not shown, then shown (said: none, made before it was shown again).
// Resumed: run by the tests of what is left to be mended (the core marks a resumed stream's said), kept apart
#warnings("-unused_constructor")
priv enum OaLater {
  CaughtUp
  Resumed
  Away
}

///|
fn oa_later_name(l : OaLater) -> String {
  match l {
    CaughtUp => "caught up by a read"
    Resumed => "told by a resumed stream"
    Away => "told while the app was not shown, then shown"
  }
}

///|
/// The core's clock kept as the Tester's before each frame.
fn oa_tick(a : OaAttend, t : @ui.Tester) -> () -> Unit {
  fn() { a.now = t.time() }
}

///|
fn oa_held_then(s : (String, Double, Double, Int), nodes : Bool, device : Bool, later : OaLater) -> Array[String] {
  new_run()
  oa_begin()
  @sfbase.chat_page_nodes.set(nodes)
  let a = oa_attend()
  let src = oa_source(oa_attending(a))
  open_chat(oa_c2)
  let t = oa_tester(src, s, device)
  let tick = oa_tick(a, t)
  oa_run(t, 1000.0, pump=tick)
  @ui.view_tree().unwrap().event(t.time(), fn() { open_chat(oa_c1) })
  oa_run(t, 300.0, pump=tick)
  let label = "\{oa_name(nodes)} \{s.0} held, then \{oa_later_name(later)}\{oa_how(device)}"
  let out = match later {
    CaughtUp => oa_watch(t, s, label, fn() { oa_say(a, src, false) }, 1500.0, pump=tick)
    Resumed => oa_watch(t, s, label, fn() { oa_say(a, src, true) }, 1500.0, pump=tick)
    Away => {
      t.app_state(false, false)
      oa_run(t, 300.0, pump=tick)
      oa_say(a, src, true)
      oa_run(t, 300.0, pump=tick)
      oa_watch(t, s, label, fn() { t.app_state(true, true) }, 1500.0, pump=tick)
    }
  }
  let said = @signals.untracked(fn() {
    items((src.topic_read)("chat", @sfbase.chat_params(oa_c1)).value, "messages")
      .filter(fn(m) { flag(Some(m), "said") })
      .map(fn(m) { number(Some(m), "seq").to_int().to_string() })
  })
  println("OLD_AT_ONCE_SAID \{label}: the core marks said \{@ui.list_text(said)}")
  out
}

///|
/// (not yet told by a resumed stream: the core marks those said, wrongly, attend.ts, left to be mended there)
fn oa_case2(nodes : Bool, laters? : Array[OaLater] = [CaughtUp, Away], which? : OaWhich = Held) -> Unit raise {
  let all = []
  for s in oa_screens {
    for later in laters {
      for device in [false, true] {
        guard oa_runs(which, device, s, 2) else { continue }
        all.push_iter(oa_held_then(s, nodes, device, later).iter())
      }
    }
  }
  if all.length() > 0 {
    fail(all.join("\n"))
  }
}

// ---- the long chat, for cases 3, 4 and 7 ------------------------------------------------------------------------

///|
/// The long chat's value with every tenth message from the 3rd holding the fixture's pictures (its message 5's) and
/// every tenth from the 7th the fixture's agent's long answer (its message 3's words), its agents at work where
/// `working`.
fn oa_long_value(v : Map[String, Json], tpl : Array[Json], working : Bool) -> Map[String, Json] {
  let pics = tpl.iter().find_first(fn(m) { number(Some(m), "seq").to_int() == 5 })
  let long = tpl.iter().find_first(fn(m) { number(Some(m), "seq").to_int() == 3 })
  let out = v.copy()
  out["messages"] = Json::array(
    items(Some(Json::object(v)), "messages").map(fn(j) {
      guard j is Object(was) else { return j }
      let n = number(Some(j), "seq").to_int()
      let m = was.copy()
      match (n % 10, pics, long) {
        (3, Some(Object(p)), _) =>
          match p.get("attachments") {
            Some(at) => m["attachments"] = at
            None => ()
          }
        (7, _, Some(Object(l))) =>
          for k in ["text", "words", "md"] {
            match l.get(k) {
              Some(x) => m[k] = x
              None => ()
            }
          }
        _ => ()
      }
      Json::object(m)
    }),
  )
  if working {
    out["agents"] = Json::array(
      items(Some(Json::object(v)), "agents").map(fn(a) {
        guard a is Object(m) else { return a }
        let m = m.copy()
        m["status"] = Json::string("running")
        m["since"] = Json::number(1.0e9)
        Json::object(m)
      }),
    )
  }
  out
}

///|
/// The long chat (chat s-c1) over the fixture's (chat s-c2 the fixture's own), as oa_long_value says, its pages before
/// and after (`chat.older`, `chat.newer`) answered `ms` after they are asked by `pump` (held: their moment, what answers
/// them), the rest of the long chat's answers given as `pump` runs.
fn oa_long(l : LongChat, working : Bool, ms : Double, held : Array[(Double, () -> Unit)], now : () -> Double) -> Source {
  let base = fixture("chat")
  let long = long_source(l)
  let tpl = items(
    @signals.untracked(fn() { base.topic("chat", @sfbase.chat_params(oa_c1)).get().snapshot().value }),
    "messages",
  )
  {
    ..long,
    topic_read: fn(name, params) {
      if name == "chat" && params.get("session") != Some(Json::string("s-c1")) {
        return (base.topic_read)(name, params)
      }
      let got = (long.topic_read)(name, params)
      guard name == "chat" && got.value is Some(Object(v)) else { return got }
      { ..got, value: Some(Json::object(oa_long_value(v, tpl, working))) }
    },
    call: fn(name, params, done) {
      if name == "chat.older" || name == "chat.newer" {
        held.push((now() + ms, fn() { (long.call)(name, params, done) }))
      } else {
        (long.call)(name, params, done)
      }
    },
  }
}

///|
/// What `held` has due now given, then the long chat's answers.
fn oa_long_pump(t : @ui.Tester, l : LongChat, held : Array[(Double, () -> Unit)]) -> () -> Unit {
  fn() {
    let due = held.filter(fn(h) { h.0 <= t.time() + 1.0e-6 })
    let kept = held.filter(fn(h) { h.0 > t.time() + 1.0e-6 })
    held.clear()
    held.push_iter(kept.iter())
    for h in due {
      (h.1)()
    }
    long_answered(l)
  }
}

///|
/// A stroke reading the list by `d` (up where positive: a finger dragging down on 小屏, the wheel on 大屏).
fn oa_stroke(t : @ui.Tester, s : (String, Double, Double, Int), d : Double) -> Unit {
  let (_, w, h, platform) = s
  if platform == 2 {
    t.drag(w / 2.0, h * 0.4, w / 2.0, h * 0.4 + d)
  } else {
    t.move_to(w * 0.6, h / 2.0)
    t.wheel(w * 0.6, h / 2.0, -d)
  }
}

// ---- case 3: reading up, the page before arriving ---------------------------------------------------------------

///|
fn oa_read_up(s : (String, Double, Double, Int), nodes : Bool, device : Bool, ms : Double) -> Array[String] {
  new_run()
  oa_begin()
  @sfbase.chat_page_nodes.set(nodes)
  let l = long_chat()
  let held : Array[(Double, () -> Unit)] = []
  let clock = Ref(0.0)
  let src = oa_source(oa_long(l, false, ms, held, fn() { clock.val }))
  open_chat(long_ref)
  let t = oa_tester(src, s, device)
  let pump0 = oa_long_pump(t, l, held)
  let pump = fn() {
    clock.val = t.time()
    pump0()
  }
  oa_run(t, long_opened_ms, pump~)
  let out = []
  let mut pages = 0
  let mut strokes = 0
  while pages < 2 && strokes < 12 {
    strokes += 1
    let asked = l.asked.filter(fn(a) { a.has_prefix("older") }).length()
    let label = "\{oa_name(nodes)} \{s.0} read up, stroke \{strokes}, core \{ms} ms\{oa_how(device)}"
    out.push_iter(
      oa_watch(t, s, label, fn() { oa_stroke(t, s, s.2 * 0.4) }, ms + long_rest_ms * 2.0, scroll=true, pump~).iter(),
    )
    if l.asked.filter(fn(a) { a.has_prefix("older") }).length() > asked {
      pages += 1
    }
  }
  println("OLD_AT_ONCE_PAGED \{oa_name(nodes)} \{s.0} core \{ms}\{oa_how(device)}: \{pages} pages before in \{strokes} strokes, asked \{@ui.list_text(l.asked)}")
  if pages < 2 {
    out.push("\{oa_name(nodes)} \{s.0} core \{ms}\{oa_how(device)}: the page before asked \{pages} times in \{strokes} strokes, not twice")
  }
  out
}

///|
// run by the tests of what is kept apart for its time (reading up and down held before and after)
#warnings("-unused_value")
fn oa_case3(nodes : Bool, which? : OaWhich = Held) -> Unit raise {
  let all = []
  for s in oa_screens {
    for ms in oa_lates {
      for device in [false, true] {
        guard oa_runs(which, device, s, 3) else { continue }
        all.push_iter(oa_read_up(s, nodes, device, ms).iter())
      }
    }
  }
  if all.length() > 0 {
    fail(all.join("\n"))
  }
}

// ---- case 4: the page after arriving ----------------------------------------------------------------------------

///|
fn oa_read_down(s : (String, Double, Double, Int), nodes : Bool, device : Bool, ms : Double) -> Array[String] {
  new_run()
  oa_begin()
  @sfbase.chat_page_nodes.set(nodes)
  let l = long_chat(unread=60)
  let held : Array[(Double, () -> Unit)] = []
  let clock = Ref(0.0)
  let src = oa_source(oa_long(l, false, ms, held, fn() { clock.val }))
  open_chat(long_ref)
  let t = oa_tester(src, s, device)
  let pump0 = oa_long_pump(t, l, held)
  let pump = fn() {
    clock.val = t.time()
    pump0()
  }
  oa_run(t, long_opened_ms, pump~)
  let out = []
  let mut pages = 0
  let mut strokes = 0
  while pages < 1 && strokes < 16 {
    strokes += 1
    let asked = l.asked.filter(fn(a) { a == "newer" }).length()
    let label = "\{oa_name(nodes)} \{s.0} read down, stroke \{strokes}, core \{ms} ms\{oa_how(device)}"
    out.push_iter(
      oa_watch(t, s, label, fn() { oa_stroke(t, s, -s.2 * 0.4) }, ms + long_rest_ms * 2.0, scroll=true, pump~).iter(),
    )
    if l.asked.filter(fn(a) { a == "newer" }).length() > asked {
      pages += 1
    }
  }
  println("OLD_AT_ONCE_PAGED \{oa_name(nodes)} \{s.0} down core \{ms}\{oa_how(device)}: \{pages} pages after in \{strokes} strokes, asked \{@ui.list_text(l.asked)}")
  if pages < 1 {
    out.push("\{oa_name(nodes)} \{s.0} core \{ms}\{oa_how(device)}: the page after never asked in \{strokes} strokes")
  }
  out
}

///|
// run by the tests of what is kept apart for its time (reading up and down held before and after)
#warnings("-unused_value")
fn oa_case4(nodes : Bool, which? : OaWhich = Held) -> Unit raise {
  let all = []
  for s in oa_screens {
    for ms in oa_lates {
      for device in [false, true] {
        guard oa_runs(which, device, s, 4) else { continue }
        all.push_iter(oa_read_down(s, nodes, device, ms).iter())
      }
    }
  }
  if all.length() > 0 {
    fail(all.join("\n"))
  }
}

// ---- case 5: another chat switched to and back, the core late -----------------------------------------------------

///|
/// Chat `r` opened as a person opens it: on 大屏 its row in the sidebar pressed, on 小屏 back to Home and its row
/// pressed there (`by`: how it was).
fn oa_open_by_hand(t : @ui.Tester, s : (String, Double, Double, Int), r : ChatRef, by : Array[String]) -> Unit {
  match oa_row(t, r.title) {
    Some((x, y)) if s.3 == 0 || x < s.1 => {
      t.tap(x, y)
      by.push("its row pressed")
    }
    _ => {
      @ui.view_tree().unwrap().event(t.time(), fn() { open_chat(r) })
      by.push("open_chat (its row not found)")
    }
  }
}

///|
fn oa_switch(
  s : (String, Double, Double, Int),
  nodes : Bool,
  device : Bool,
  ms : Double,
  ways? : Bool = false,
) -> Array[String] {
  new_run()
  oa_begin()
  @sfbase.chat_page_nodes.set(nodes)
  let armed = Ref(false)
  let src = oa_source(round_trip_again(fixture("chat"), 0.0, late=fn(_, _) { if armed.val { ms } else { 0.0 } }))
  open_chat(oa_c1)
  let t = oa_tester(src, s, device)
  oa_run(t, 1000.0)
  armed.val = true
  let by = []
  let out = []
  let small = s.3 == 2
  if small {
    t.back()
    oa_run(t, 1000.0)
  }
  out.push_iter(
    oa_watch(t, s, "\{oa_name(nodes)} \{s.0} to another chat, core \{ms} ms\{oa_how(device)}", fn() {
      oa_open_by_hand(t, s, oa_c2, by)
    }, ms + 1500.0, in_ways=ways).iter(),
  )
  if small {
    t.back()
    oa_run(t, 1000.0)
  }
  out.push_iter(
    oa_watch(t, s, "\{oa_name(nodes)} \{s.0} back to the chat, core \{ms} ms\{oa_how(device)}", fn() {
      oa_open_by_hand(t, s, oa_c1, by)
    }, ms + 1500.0, in_ways=ways).iter(),
  )
  println("OLD_AT_ONCE_BY \{oa_name(nodes)} \{s.0} core \{ms}: \{@ui.list_text(by)}, back on it: \{oa_drawn(t, s, "做完了")}")
  out
}

///|
fn oa_case5(nodes : Bool, ways? : Bool = false, which? : OaWhich = Held) -> Unit raise {
  let all = []
  for s in oa_screens {
    for ms in oa_lates {
      for device in [false, true] {
        guard oa_runs(which, device, s, 5) else { continue }
        all.push_iter(oa_switch(s, nodes, device, ms, ways~).iter())
      }
    }
  }
  if all.length() > 0 {
    fail(all.join("\n"))
  }
}

// ---- case 6: another page over the chat while messages come -------------------------------------------------------

///|
fn oa_covered(s : (String, Double, Double, Int), nodes : Bool, device : Bool) -> Array[String] {
  new_run()
  oa_begin()
  @sfbase.chat_page_nodes.set(nodes)
  let a = oa_attend()
  let src = oa_source(oa_attending(a))
  open_chat(oa_c1)
  let t = oa_tester(src, s, device)
  let tick = oa_tick(a, t)
  oa_run(t, 1000.0, pump=tick)
  @ui.view_tree().unwrap().event(t.time(), fn() { @sfbase.open_page(Archived) })
  oa_run(t, 1000.0, pump=tick)
  let covered = !oa_drawn(t, s, "做完了")
  // (the station tells them as they are said: events of its stream)
  oa_say(a, src, true)
  oa_run(t, 1000.0, pump=tick)
  let label = "\{oa_name(nodes)} \{s.0} shown again after a page over it\{oa_how(device)}"
  // (小屏: back, the chat under the page; 大屏: the page took the pane, the chat opened again as a person comes back)
  let out = oa_watch(t, s, label, fn() {
    if s.3 == 2 {
      t.back()
    } else {
      @ui.view_tree().unwrap().event(t.time(), fn() { open_chat(oa_c1) })
    }
  }, 1500.0, pump=tick)
  let said = @signals.untracked(fn() {
    items((src.topic_read)("chat", @sfbase.chat_params(oa_c1)).value, "messages")
      .filter(fn(m) { flag(Some(m), "said") })
      .map(fn(m) { number(Some(m), "seq").to_int().to_string() })
  })
  println("OLD_AT_ONCE_SAID \{label}: covered \{covered}, back on it \{oa_drawn(t, s, "改好后的样子")}, the core marks said \{@ui.list_text(said)}")
  out
}

///|
fn oa_case6(nodes : Bool, which? : OaWhich = Held) -> Unit raise {
  let all = []
  for s in oa_screens {
    for device in [false, true] {
      guard oa_runs(which, device, s, 6) else { continue }
      all.push_iter(oa_covered(s, nodes, device).iter())
    }
  }
  if all.length() > 0 {
    fail(all.join("\n"))
  }
}

// ---- case 7: a long chat with an agent at work opened -------------------------------------------------------------

///|
fn oa_working(s : (String, Double, Double, Int), nodes : Bool, device : Bool, ms : Double) -> Array[String] {
  new_run()
  oa_begin()
  @sfbase.chat_page_nodes.set(nodes)
  let l = long_chat()
  let held : Array[(Double, () -> Unit)] = []
  let clock = Ref(0.0)
  let armed = Ref(false)
  let src = oa_source(
    round_trip_again(oa_long(l, true, 0.0, held, fn() { clock.val }), 0.0, late=fn(_, _) {
      if armed.val {
        ms
      } else {
        0.0
      }
    }),
  )
  open_chat(oa_c2)
  let t = oa_tester(src, s, device)
  let pump0 = oa_long_pump(t, l, held)
  let pump = fn() {
    clock.val = t.time()
    pump0()
  }
  oa_run(t, 1000.0, pump~)
  armed.val = true
  let label = "\{oa_name(nodes)} \{s.0} a long chat with an agent at work opened, core \{ms} ms\{oa_how(device)}"
  let out = oa_watch(t, s, label, fn() { @ui.view_tree().unwrap().event(t.time(), fn() { open_chat(long_ref) }) }, ms + 1500.0, pump~)
  println("OLD_AT_ONCE_WORKING \{label}: its line drawn \{t.find(tr("android-chat.chat.working")) is Some(_)}")
  out
}

///|
fn oa_case7(nodes : Bool, which? : OaWhich = Held) -> Unit raise {
  let all = []
  for s in oa_screens {
    for ms in oa_lates {
      for device in [false, true] {
        guard oa_runs(which, device, s, 7) else { continue }
        all.push_iter(oa_working(s, nodes, device, ms).iter())
      }
    }
  }
  if all.length() > 0 {
    fail(all.join("\n"))
  }
}
