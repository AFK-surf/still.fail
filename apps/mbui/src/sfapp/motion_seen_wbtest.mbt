// What the user asked of the motion of a chat and the chats' list (docs/motion.md, the mbui skill's design.md, said in
// the chats from 2026-09-28 on), held on what a person sees and nothing else: the words drawn in each frame a host
// shows (Tester::run_as_host's frames, a frame the app did not ask for showing the one before), where, how big and how
// faded. Nothing here names a node, a flight, a list or a motion of the app's: any way of doing it that shows the same
// passes, any that shows otherwise fails.
//
// What is held, each over every word seen in a step:
// - nothing jumps (「一帧跳」「瞬移」「突变」): a word that moves in a frame many times as far as in the frames either side;
// - nothing goes back and forth when no hand holds it (「来回动」「反复运动」「两个位置之间来回跳」);
// - nothing stops on its way and goes on (「顿一下」「松手顿一下」「滚到最顶上前一瞬间会顿一下」);
// - what comes, comes (「凭空出现」), and what goes, goes (「凭空消失」): not there whole in one frame and gone the next,
//   nor there whole all at once where nothing was;
// - and, where a step says so, what must not move or fade does not (another chat chosen, a page come back to).

///|
/// A word as a frame shows it: where its box is, how big, how opaque.
priv struct SeenWord {
  x : Double
  y : Double
  w : Double
  h : Double
  alpha : Double
  /// how much of it shows: the area of its glyphs drawn, each by how opaque it is (a word scaled from small, faded in
  /// glyph by glyph or cut by what holds it shows less than whole)
  ink : Double
} derive(Show)

///|
/// What a frame a host showed had on the screen: each words drawn once (words drawn twice told apart by nothing a person
/// sees, left out), at the frame's time, and whether a hand held the screen as it was drawn.
priv struct SeenFrame {
  at : Double
  hand : Bool
  words : Map[String, SeenWord]
}

///|
/// A watch over the frames shown: begun on a Tester, each frame drawn caught; taken as SeenFrames once a step is done.
priv struct Watch {
  t : @ui.Tester
  w : Double
  h : Double
  caught : Array[(Double, Bool, Map[String, SeenWord])]
  hand : Ref[Bool]
  /// the words drawn twice in some frame since the watch was taken: which is which is not seen, so neither is held
  twice : Map[String, Bool]
}

///|
/// The words drawn now inside the window, faded no further than a person can see, each drawn once.
fn seen_now(t : @ui.Tester, w : Double, h : Double, twice? : Map[String, Bool] = {}) -> Map[String, SeenWord] {
  let count : Map[String, Int] = {}
  let out : Map[String, SeenWord] = {}
  // (each glyph drawn: its box as cut by its clip, how opaque)
  let glyphs : Array[(Double, Double, Double, Double, Double)] = []
  for g in t.drawn_instances() {
    if g[5] == 1.0 && g[11] > 0.0 {
      let x0 = if g[0] > g[16] { g[0] } else { g[16] }
      let y0 = if g[1] > g[17] { g[1] } else { g[17] }
      let x1 = if g[0] + g[2] < g[18] { g[0] + g[2] } else { g[18] }
      let y1 = if g[1] + g[3] < g[19] { g[1] + g[3] } else { g[19] }
      if x1 > x0 && y1 > y0 {
        glyphs.push((x0, y0, x1, y1, g[11]))
      }
    }
  }
  for d in t.words() {
    let (words, x, y, ww, hh, alpha) = d
    if alpha < 0.05 || x + ww <= 0.0 || x >= w || y + hh <= 0.0 || y >= h || words.trim().is_empty() {
      continue
    }
    count[words] = count.get(words).unwrap_or(0) + 1
    let mut ink = 0.0
    for gl in glyphs {
      let (x0, y0, x1, y1, a) = gl
      let (cx, cy) = ((x0 + x1) / 2.0, (y0 + y1) / 2.0)
      if cx >= x && cx <= x + ww && cy >= y && cy <= y + hh {
        ink = ink + (x1 - x0) * (y1 - y0) * a
      }
    }
    out[words] = { x, y, w: ww, h: hh, alpha, ink }
  }
  for k in count.keys().collect() {
    if count.get(k).unwrap_or(0) > 1 {
      out.remove(k)
      twice[k] = true
    }
  }
  out
}

///|
/// A watch begun: every frame drawn from now caught, as recorded for its host.
fn watch(t : @ui.Tester, w : Double, h : Double) -> Watch {
  t.record_host()
  t.host_frames() |> ignore
  let wt = { t, w, h, caught: [], hand: Ref(false), twice: {} }
  t.each_frame(Some(fn() { wt.caught.push((t.time(), wt.hand.val, seen_now(t, w, h, twice=wt.twice))) }))
  wt
}

///|
/// The frames a host showed since the watch began or was last taken, oldest first: a frame the app did not ask for
/// shows what the one before it showed, as a phone's screen stands still until something asks.
fn Watch::take(self : Watch) -> Array[SeenFrame] {
  let asked : Map[String, Bool] = {}
  for f in self.t.host_frames() {
    asked[f.at.to_string()] = f.asked || !f.changed
  }
  let out : Array[SeenFrame] = []
  for c in self.caught {
    let (at, hand, all) = c
    let words : Map[String, SeenWord] = {}
    for k, v in all {
      if !self.twice.contains(k) {
        words[k] = v
      }
    }
    let shown = asked.get(at.to_string()).unwrap_or(true)
    match out.last() {
      Some(before) if !shown => out.push({ at, hand, words: before.words })
      _ => out.push({ at, hand, words })
    }
  }
  self.caught.clear()
  self.twice.clear()
  out
}

///|
fn Watch::stop(self : Watch) -> Unit {
  self.t.each_frame(None)
}

///|
/// How far a word went from one frame to the next: the furthest of its place and its size, across and down.
fn seen_step(a : SeenWord, b : SeenWord) -> Double {
  // (its place alone: a box's laid-out size is not drawn, what shows of it is its glyphs, `ink`)
  let dx = (b.x - a.x).abs()
  let dy = (b.y - a.y).abs()
  if dx > dy {
    dx
  } else {
    dy
  }
}

///|
/// Points a word may move in a frame more than its neighbours' moves allow before it is a jump.
let jump_over : Double = 6.0

///|
/// How many times its moves in the frames either side a word's move in one frame may be before it is a jump.
let jump_times : Double = 2.5

///|
/// Each word's place in the frames it is seen in one after another (a frame it is not in breaks the run).
fn seen_runs(frames : Array[SeenFrame]) -> Map[String, Array[(Int, SeenWord)]] {
  let out : Map[String, Array[(Int, SeenWord)]] = {}
  for i, f in frames {
    for k, v in f.words {
      match out.get(k) {
        Some(run) => run.push((i, v))
        None => out[k] = [(i, v)]
      }
    }
  }
  out
}

///|
fn short(words : String) -> String {
  if words.length() > 24 {
    words.unsafe_substring(start=0, end=24) + "…"
  } else {
    words
  }
}

///|
/// The jumps seen: a word that in one frame went `jump_times` as far as in the frame before and the frame after, and
/// `jump_over` points more (「一帧跳一截」「瞬移」).
fn seen_jumps(frames : Array[SeenFrame]) -> Array[String] {
  let out : Array[String] = []
  for k, run in seen_runs(frames) {
    for j in 1..<run.length() {
      let (i, b) = run[j]
      let (i0, a) = run[j - 1]
      if i0 != i - 1 {
        continue
      }
      let d = seen_step(a, b)
      let before = if j >= 2 && run[j - 2].0 == i0 - 1 { seen_step(run[j - 2].1, a) } else { 0.0 }
      let after = if j + 1 < run.length() && run[j + 1].0 == i + 1 { seen_step(b, run[j + 1].1) } else { 0.0 }
      let near = if before > after { before } else { after }
      if d > jump_over + jump_times * near {
        let alike = frames[i].words.iter().filter(fn(e) {
          e.0 != k && frames[i0].words.get(e.0).map(fn(p) { (seen_step(p, e.1) - d).abs() < 1.0 }).unwrap_or(false)
        }).count()
        out.push(
          "(\{alike} other words moved as far in that frame) " +
          "「\{short(k)}」 jumped \{d.round()} pt at \{frames[i].at.round()} ms ((\{a.x.round()}, \{a.y.round()}) \{a.w.round()}×\{a.h.round()} → (\{b.x.round()}, \{b.y.round()}) \{b.w.round()}×\{b.h.round()}; \{before.round()} before, \{after.round()} after)",
        )
      }
    }
  }
  out
}

///|
/// Points a word's way must go one way and then the other before it went back and forth.
let back_over : Double = 4.0

///|
/// The words that went back and forth while no hand held the screen: down (or right) at least `back_over` points, then
/// up (or left) as far, or the other way (「来回动」「反复运动」).
fn seen_back_and_forth(frames : Array[SeenFrame]) -> Array[String] {
  let out : Array[String] = []
  for k, run in seen_runs(frames) {
    for axis in 0..<2 {
      // (the way's legs, each at least back_over long: a zigzag)
      let mut low = 0.0
      let mut high = 0.0
      let mut dir = 0
      let mut legs = 0
      let mut from_at = 0.0
      let mut started = false
      for p in run {
        let (i, s) = p
        if frames[i].hand {
          started = false
          continue
        }
        let v = if axis == 0 { s.y } else { s.x }
        if !started {
          low = v
          high = v
          dir = 0
          legs = 0
          started = true
          from_at = frames[i].at
          continue
        }
        if dir >= 0 && v > high {
          high = v
        }
        if dir <= 0 && v < low {
          low = v
        }
        if dir >= 0 && high - v >= back_over && high - low >= back_over {
          if dir > 0 || high - low >= back_over {
            legs += 1
          }
          dir = -1
          low = v
        } else if dir <= 0 && v - low >= back_over && high - low >= back_over {
          legs += 1
          dir = 1
          high = v
        }
        if legs >= 2 {
          out.push("「\{short(k)}」 went back and forth \{if axis == 0 { "up and down" } else { "across" }} from \{from_at.round()} ms to \{frames[i].at.round()} ms")
          break
        }
      }
      if legs >= 2 {
        break
      }
    }
  }
  out
}

///|
/// Points a word goes in a frame for it to be on its way.
let going : Double = 3.0

///|
/// The words that stopped on their way and went on: moving `going` points a frame, then for a frame to six standing
/// (or nearly: under a third of their way either side), then moving as fast again (「顿一下」「松手顿一下」).
fn seen_stops(frames : Array[SeenFrame]) -> Array[String] {
  let out : Array[String] = []
  for k, run in seen_runs(frames) {
    let steps : Array[(Int, Double)] = []
    for j in 1..<run.length() {
      if run[j - 1].0 == run[j].0 - 1 {
        steps.push((run[j].0, seen_step(run[j - 1].1, run[j].1)))
      } else {
        steps.push((run[j].0, -1.0))
      }
    }
    let mut j = 0
    while j < steps.length() {
      let (_, v) = steps[j]
      if v >= going {
        // (then standing, a frame to six, then going on)
        let mut e = j + 1
        while e < steps.length() && steps[e].1 >= 0.0 && steps[e].1 < v / 3.0 && steps[e].1 < going {
          e += 1
        }
        let stood = e - j - 1
        if stood >= 1 && stood <= 6 && e < steps.length() && steps[e].1 >= going && steps[e].1 >= 0.0 {
          let (i, _) = steps[j + 1]
          let (ie, _) = steps[e]
          out.push("「\{short(k)}」 stopped on its way at \{frames[i].at.round()} ms for \{stood} frame(s), going \{v.round()} pt a frame before and \{steps[e].1.round()} after (\{frames[ie].at.round()} ms)")
          break
        }
        j = e
      } else {
        j += 1
      }
    }
  }
  out
}

///|
/// Words come whole (「凭空出现」): not seen in the frame before, seen whole (as opaque as it gets) in its first frame,
/// where it has no way in from (inside the window, below its top `edge` points, where a page's bars stand and rows
/// come in from under).
fn seen_popped(frames : Array[SeenFrame], words : Array[String], edge : Double) -> Array[String] {
  let out : Array[String] = []
  for k in words {
    let most = seen_most(frames, k)
    for i in 1..<frames.length() {
      match (frames[i - 1].words.get(k), frames[i].words.get(k)) {
        (None, Some(s)) if most > 0.0 && s.ink >= 0.9 * most && s.y > edge => {
          out.push("「\{short(k)}」 came whole at \{frames[i].at.round()} ms at (\{s.x.round()}, \{s.y.round()})")
          break
        }
        _ => ()
      }
    }
  }
  out
}

///|
/// Words gone whole (「凭空消失」): seen as opaque as they get in a frame, in none after, in the middle of the window
/// (below `edge`), where nothing they went to is.
fn seen_vanished(frames : Array[SeenFrame], words : Array[String], edge : Double) -> Array[String] {
  let out : Array[String] = []
  for k in words {
    let most = seen_most(frames, k)
    for i in 1..<frames.length() {
      match (frames[i - 1].words.get(k), frames[i].words.get(k)) {
        (Some(s), None) if most > 0.0 && s.ink >= 0.9 * most && s.y > edge => {
          out.push("「\{short(k)}」 went whole at \{frames[i].at.round()} ms from (\{s.x.round()}, \{s.y.round()})")
          break
        }
        _ => ()
      }
    }
  }
  out
}

///|
/// The most a word ever shows in a step (SeenWord's ink): what it is whole.
fn seen_most(frames : Array[SeenFrame], k : String) -> Double {
  let mut most = 0.0
  for f in frames {
    match f.words.get(k) {
      Some(s) if s.ink > most => most = s.ink
      _ => ()
    }
  }
  most
}

///|
/// Words faded part way in some frame (more than clear, less than whole): what a crossfade shows.
fn seen_faded(frames : Array[SeenFrame]) -> Array[String] {
  let out : Array[String] = []
  for k, run in seen_runs(frames) {
    for p in run {
      let (i, s) = p
      if s.alpha > 0.1 && s.alpha < 0.9 {
        out.push("「\{short(k)}」 faded to \{(s.alpha * 100.0).round()}% at \{frames[i].at.round()} ms")
        break
      }
    }
  }
  out
}

///|
/// Words that moved at all (more than half a point, or changed their size) between the step's first frame and any
/// after it, among `of` (all, if empty).
fn seen_moved(frames : Array[SeenFrame], of : Array[String]) -> Array[String] {
  let out : Array[String] = []
  if frames.is_empty() {
    return out
  }
  for k, first in frames[0].words {
    if !of.is_empty() && !of.contains(k) {
      continue
    }
    for f in frames {
      match f.words.get(k) {
        Some(s) if seen_step(first, s) > 0.5 => {
          out.push("「\{short(k)}」 moved \{seen_step(first, s).round()} pt by \{f.at.round()} ms")
          break
        }
        _ => ()
      }
    }
  }
  out
}

///|
/// The words of every frame of a step that were not in its first (what came in it).
fn seen_new(frames : Array[SeenFrame]) -> Array[String] {
  let out : Array[String] = []
  if frames.is_empty() {
    return out
  }
  for f in frames {
    for k, _ in f.words {
      if !frames[0].words.contains(k) && !out.contains(k) {
        out.push(k)
      }
    }
  }
  out
}

///|
/// The words of the step's first frame not in its last (what went in it).
fn seen_gone(frames : Array[SeenFrame]) -> Array[String] {
  let out : Array[String] = []
  match (frames.get(0), frames.last()) {
    (Some(a), Some(b)) =>
      for k, _ in a.words {
        if !b.words.contains(k) {
          out.push(k)
        }
      }
    _ => ()
  }
  out
}

///|
/// What a step showed against what the user asked of every motion: no jump, no stop on the way, nothing back and
/// forth when no hand holds it (`hand_free_back`: false where the hand or an edge's give is a way back of its own).
fn seen_faults(name : String, frames : Array[SeenFrame], back? : Bool = true) -> Array[String] {
  let out : Array[String] = []
  for s in seen_jumps(frames) {
    out.push("\{name}: \{s}")
  }
  for s in seen_stops(frames) {
    out.push("\{name}: \{s}")
  }
  if back {
    for s in seen_back_and_forth(frames) {
      out.push("\{name}: \{s}")
    }
  }
  out
}

///|
/// The screens a step is seen on: a phone's (390 × 844 at 120 Hz, touch) and a desktop's large screen (1280 × 800 at
/// 60 Hz, a mouse).
let seen_screens : Array[(String, Double, Double, Int)] = [("small", 390.0, 844.0, 2), ("large", 1280.0, 800.0, 0)]

///|
/// The app over the fixture's `mode` on a screen, its first page settled as a host shows it.
fn seen_app(mode : String, w : Double, h : Double, platform : Int) -> @ui.Tester {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode~, w~, h~, platform~)
  t.set_frame_period(if platform == 0 { 1000.0 / 60.0 } else { 1000.0 / 120.0 })
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// A tap where `words` are drawn, as a host hands it on: no frame drawn for it.
fn seen_tap(t : @ui.Tester, words : String) -> Unit {
  match t.find(words) {
    Some((x, y)) => {
      t.touch_at(0, x, y, t.time())
      t.touch_at(2, x, y, t.time())
    }
    None => abort("no 「\{words}」 to tap")
  }
}

///|
/// The send button tapped, as a host hands it on.
fn seen_send(t : @ui.Tester) -> Unit {
  match t.query(Button, label=@sf.t("web-main.composer.send")) {
    Some(s) => {
      let (x, y) = (s.rect.0 + s.rect.2 / 2.0, s.rect.1 + s.rect.3 / 2.0)
      t.touch_at(0, x, y, t.time())
      t.touch_at(2, x, y, t.time())
    }
    None => abort("no send button")
  }
}

///|
/// The composer focused and `words` typed in it, a key at a time a display's few frames apart, as a host shows it.
fn seen_type(t : @ui.Tester, words : String) -> Unit {
  for ch in words {
    t.text_told(ch.to_string(), t.time())
    t.run_as_host(50.0)
  }
}

///|
/// A finger put down at (x0, y0), moved to (x1, y1) over `ms` a display's frame at a time, and let go there, the watch
/// told a hand holds the screen meanwhile.
fn hand_drag(wt : Watch, x0 : Double, y0 : Double, x1 : Double, y1 : Double, ms : Double) -> Unit {
  let t = wt.t
  let p = t.frame_period()
  let n = (ms / p).ceil().to_int()
  wt.hand.val = true
  t.touch_at(0, x0, y0, t.time())
  for i in 1..=n {
    t.run_as_host(p)
    let k = i.to_double() / n.to_double()
    t.touch_at(1, x0 + (x1 - x0) * k, y0 + (y1 - y0) * k, t.time())
  }
  t.touch_at(2, x1, y1, t.time())
  wt.hand.val = false
}

// The chat page.

///|
/// 「消息永远优先上屏」「发出去的东西保持写的时候的样子」「发消息好像会瞬间把 composer 高度重置」「发消息偶尔会出现跳到某个地方
/// 再跳到最底下」「回复消息会先瞬间滚动」「activity 出现好像没有动效，导致消息列表瞬移」: words sent at the chat's foot,
/// delivered, answered and the turn over, each frame as a host shows it: the words always on the screen from the tap
/// till they are in their message, nothing jumping, stopping on its way or going back and forth; the answer coming in
/// (not there whole at once), nothing going whole.
test "a chat: words sent, delivered and answered: shown from the tap on, nothing jumps, stops on its way, goes back and forth, comes or goes whole" {
  let out : Array[String] = []
  for s in seen_screens {
    let (name, w, h, platform) = s
    let t = seen_app("chat", w, h, platform)
    seen_tap(t, "发消息")
    t.run_as_host(@ui.move_most_ms)
    let words = "发布前再看一眼签名"
    t.text_told(words, t.time())
    t.run_as_host(@ui.move_most_ms)
    let wt = watch(t, w, h)
    seen_send(t)
    t.run_as_host(fix_deliver_ms + fix_answer_ms + fix_turn_end_ms + @ui.move_most_ms)
    let frames = wt.take()
    wt.stop()
    out.append(seen_faults("\{name}, sent", frames))
    // (the words from the tap to their message: in every frame)
    for f in frames {
      if !f.words.contains(words) {
        out.push("\{name}, sent: 「\{words}」 not on the screen at \{f.at.round()} ms")
        break
      }
    }
    for s in seen_popped(frames, seen_new(frames), 110.0) {
      out.push("\{name}, sent: \{s}")
    }
    for s in seen_vanished(frames, seen_gone(frames), 110.0) {
      out.push("\{name}, sent: \{s}")
    }
  }
  assert_eq(out, [])
}

///|
/// 「从多行变回一行没有过渡」「为啥第二个回车导致的高度变化就没有动效了」「composer 从多行收到 1 行的动画有 bug」「输入框变高
/// 的时候会盖住发送按钮」: lines typed into the composer one after another and taken out again, as a host shows it: what
/// is on the page moves with the composer as it grows and shrinks, nothing jumping, stopping or going back and forth.
test "a chat: lines typed into the composer and taken out again move nothing by a jump, a stop or back and forth" {
  let out : Array[String] = []
  for s in seen_screens {
    let (name, w, h, platform) = s
    let t = seen_app("chat", w, h, platform)
    seen_tap(t, "发消息")
    t.run_as_host(@ui.move_most_ms)
    let wt = watch(t, w, h)
    for line in ["第一行", "\n第二行", "\n第三行", "\n第四行"] {
      t.text_told(line, t.time())
      t.run_as_host(@ui.move_most_ms)
    }
    out.append(seen_faults("\{name}, lines typed", wt.take()))
    // (each line taken out: its characters and the line break, a key at a time)
    for _ in 0..<3 {
      for _ in 0..<4 {
        t.key_told(8, 0, t.time())
        t.run_as_host(50.0)
      }
      t.run_as_host(@ui.move_most_ms)
    }
    out.append(seen_faults("\{name}, lines taken out", wt.take()))
    wt.stop()
  }
  assert_eq(out, [])
}

///|
/// 「换 chat 感觉也不应该缩小」「去掉切换 chat 的那个淡入淡出闪烁」「大屏上切换 chat 为啥现在会触发 composer 动效」「What
/// does not move: content swapped」: another chat chosen in a large screen's sidebar and the first chosen back: the
/// page's words are there at once, nothing faded part way (no crossfade), nothing of what stays (the sidebar, the
/// composer's words) moving.
test "a large screen: another chat chosen and chosen back swaps the page at once: nothing fades part way, nothing that stays moves" {
  let out : Array[String] = []
  let (w, h) = (1280.0, 800.0)
  let t = seen_app("chat", w, h, 0)
  for name in ["夜里的构建又失败了", "整理发布清单"] {
    let wt = watch(t, w, h)
    seen_tap(t, name)
    t.run_as_host(@ui.move_most_ms)
    let frames = wt.take()
    wt.stop()
    out.append(seen_faults("\{name} chosen", frames))
    for s in seen_faded(frames) {
      out.push("\{name} chosen: \{s}")
    }
    // (what stays: the words in both the first frame and the last)
    let stays = frames[0].words.keys().filter(fn(k) { frames.last().unwrap().words.contains(k) }).collect()
    for s in seen_moved(frames, stays) {
      out.push("\{name} chosen: \{s}")
    }
  }
  assert_eq(out, [])
}

///|
/// 「我经常点进去看到一堆乱七八糟的动效乱动」「Existing chat messages show at full opacity in their first frame」「小屏进出
/// chat 页面动效有 bug」「what is on the page does not move of its own as it comes」: on a phone, a chat opened from the
/// list and gone back from: its messages there whole from their first frame (nothing fading in), nothing jumping,
/// stopping or going back and forth as the pages slide.
test "a phone: a chat opened from the list and gone back from slides whole: its messages whole from the first frame, nothing jumps or stops" {
  let out : Array[String] = []
  let (w, h) = (390.0, 844.0)
  let t = seen_app("home", w, h, 2)
  let wt = watch(t, w, h)
  seen_tap(t, "整理发布清单")
  t.run_as_host(@ui.move_most_ms)
  let frames = wt.take()
  out.append(seen_faults("opened", frames))
  for s in seen_faded(frames.filter(fn(f) { f.at > frames[0].at })) {
    out.push("opened: \{s}")
  }
  t.back_told(t.time())
  t.run_as_host(@ui.move_most_ms)
  let frames = wt.take()
  wt.stop()
  out.append(seen_faults("gone back", frames))
  for s in seen_faded(frames) {
    out.push("gone back: \{s}")
  }
  assert_eq(out, [])
}

///|
/// 「从 chat 左侧按住滑到右侧，然后再加速滑回来再放手，会顿一下」「小屏退出 chat 还是有问题，按住滑然后放手会顿一下才播动画，
/// 感觉是没有做惯性」「手指滑出 chat 松手会顿一下」: on a phone, a chat swiped back from by a finger and let go on its way:
/// the page goes on as fast as the finger went, never stopping as it is let go.
test "a phone: a chat swiped back from and let go goes on from the finger without a stop" {
  let out : Array[String] = []
  let (w, h) = (390.0, 844.0)
  let t = seen_app("chat", w, h, 2)
  let wt = watch(t, w, h)
  hand_drag(wt, 20.0, 400.0, 220.0, 400.0, 120.0)
  t.run_as_host(@ui.move_most_ms)
  out.append(seen_faults("swiped back", wt.take(), back=false))
  wt.stop()
  assert_eq(out, [])
}

///|
/// 「惯性滚动到头之前还是会顿一下，这都修多少遍了」「滚动过程中全他妈是抖动」: a long chat flung by a finger, let go, on
/// until it stops: nothing jumping, never stopping on its way and going on.
test "a phone: a long chat flung goes on from the finger and slows without a jump or a stop on its way" {
  let out : Array[String] = []
  let (w, h) = (390.0, 844.0)
  let t = seen_app("chat-long", w, h, 2)
  let wt = watch(t, w, h)
  hand_drag(wt, 200.0, 300.0, 200.0, 600.0, 80.0)
  t.run_as_host(2000.0)
  out.append(seen_faults("flung", wt.take(), back=false))
  wt.stop()
  assert_eq(out, [])
}

///|
/// 「打开右边栏再关掉就不知道飘到哪去了」: a chat's side panel opened and closed on a large screen, as a host shows it:
/// its messages move with the room they have, nothing jumping, stopping or going back and forth.
test "a large screen: a chat's side panel opened and closed moves its messages without a jump, a stop or back and forth" {
  let out : Array[String] = []
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  let (w, h) = (1280.0, 800.0)
  let t = seen_app("chat", w, h, 0)
  let wt = watch(t, w, h)
  side_change(r, "open", Some("s-c1"))
  t.run_as_host(@ui.move_most_ms)
  out.append(seen_faults("side opened", wt.take()))
  side_change(r, "close", Some("s-c1"))
  t.run_as_host(@ui.move_most_ms)
  out.append(seen_faults("side closed", wt.take()))
  wt.stop()
  assert_eq(out, [])
}

// The chats' list.

///|
/// 「chatlist 滚动感觉有问题，滚到最顶上前一瞬间会顿一下」「全都会停顿」: the chats' list scrolled down by a finger, then
/// flung back to its top, let go: on until it stops at the top, never stopping on its way and going on, nothing
/// jumping.
test "a phone: the chats' list flung back to its top goes there without a jump or a stop on its way" {
  let out : Array[String] = []
  let (w, h) = (390.0, 844.0)
  let t = seen_app("long", w, h, 2)
  let wt = watch(t, w, h)
  hand_drag(wt, 200.0, 700.0, 200.0, 200.0, 300.0)
  t.run_as_host(1500.0)
  wt.take() |> ignore
  hand_drag(wt, 200.0, 300.0, 200.0, 600.0, 80.0)
  t.run_as_host(2000.0)
  out.append(seen_faults("flung to its top", wt.take(), back=false))
  wt.stop()
  assert_eq(out, [])
}

///|
/// 「chat list 里的 chat 消失没有动效」「缩小淡出吧」「列表滚动到最下面的时候，归档 chat，动效很奇怪」「achive 按钮会瞬间消失」:
/// a chat swiped off the list on a phone and archived: its words go by fading, the rows under it close up after it,
/// nothing jumping, going whole or back and forth once the finger is off.
test "a phone: a chat swiped off the list goes by fading, the rows after it closing up without a jump" {
  let out : Array[String] = []
  let (w, h) = (390.0, 844.0)
  let t = seen_app("home", w, h, 2)
  let (_, y) = t.find("整理发布清单").unwrap()
  let wt = watch(t, w, h)
  hand_drag(wt, 300.0, y, 40.0, y, 120.0)
  t.run_as_host(@ui.move_most_ms + 600.0)
  let frames = wt.take()
  wt.stop()
  out.append(seen_faults("swiped off", frames))
  for s in seen_vanished(frames.filter(fn(f) { !f.hand }), seen_gone(frames), 110.0) {
    out.push("swiped off: \{s}")
  }
  assert_eq(out, [])
}

///|
/// 「进 chat 出来就播一次，导致总是滑动」「Home: back from a chat, the list drawn as it is」: on a phone, back on the list
/// from a chat: the list's words slide in with it, nothing of it fading, coming in or moving on its own.
test "a phone: back on the chats' list from a chat, nothing of the list fades, comes in or moves on its own" {
  let out : Array[String] = []
  let (w, h) = (390.0, 844.0)
  let t = seen_app("home", w, h, 2)
  seen_tap(t, "整理发布清单")
  t.run_as_host(@ui.move_most_ms)
  let list_words = ["盯着 CI，绿了告诉我", "夜里的构建又失败了", "看一下新的崩溃报告"]
  let wt = watch(t, w, h)
  t.back_told(t.time())
  t.run_as_host(@ui.move_most_ms)
  let frames = wt.take()
  wt.stop()
  out.append(seen_faults("back", frames))
  for s in seen_faded(frames) {
    out.push("back: \{s}")
  }
  // (the list's rows, once there, only going across with the page: never up or down)
  for k in list_words {
    let ys : Array[Double] = []
    for f in frames {
      match f.words.get(k) {
        Some(s) => ys.push(s.y)
        None => ()
      }
    }
    match (ys.get(0), ys.last()) {
      (Some(a), _) =>
        for v in ys {
          if (v - a).abs() > 0.5 {
            out.push("back: 「\{k}」 moved up or down, \{a.round()} → \{v.round()}")
            break
          }
        }
      _ => ()
    }
  }
  assert_eq(out, [])
}
