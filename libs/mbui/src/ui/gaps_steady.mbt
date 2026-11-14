// Gaps steady: two lines of words one over the other, both moving, keep the room between them on its way from what it
// was to what it comes to: it never opens and closes again (or closes and opens again) on the way. Each may go
// smoothly on its own way, and rows_steady, sizes_steady and words_over all hold, while the room between them comes
// and goes: words sent rising late on their flight's curve as the rows over them went up at once on the list's way, the
// room between them 78, 100, then 28, every time anything was sent (the user, 2026-11-10: 「新消息距离上一条 agent 消息的
// 距离能突变三次」「我一天碰到几百次」, #5231 for that one, taken out again by #5256; 「加间距检查」 for all of them). Held on every frame a
// Tester draws, as rows_steady.mbt's rule is.
//
// Measured on the words drawn (Tester::words_said: as they are drawn, as faded), each line by its words where those
// are drawn once in the frame, seen (words_over_seen_least) and in the window: the line nearest under each whose words
// are across some of the same width is the one under it, the room between them from the foot of the one to the top of
// the other. Only while both move (each a quarter of a point a frame or more): one standing while the other goes is the
// other's own way, held by the rules of what moves. A room opened (or closed) by gaps_back_least points all told on
// the way, then closed (or opened) again by as much, both moving all the while, is a fault. Not across a gap of more
// than a few frames, the window made another size (or words by the system's setting), nor a frame with the pointer down
// (what the hand moves goes as it goes).
//
// What is found now is known, a file at a time (`gaps_steady_known`, given by the app's tests as their package starts):
// a Tester made in a file shows at most as many as its file's bar, which only falls as they are mended.

///|
/// How far (points, all told) a room opens one way and then back the other, both lines moving, to be a fault.
let gaps_back_least : Double = 2.0

///|
/// How far (points) a line goes in a frame to be moving.
let gaps_moving_least : Double = 0.25

///|
/// One pair's way: where each line stood the frame before and when, the room between them then, the way the room last
/// went (1 opening, -1 closing, 0 none yet), how far it went that way all told and from what, and how far back since.
priv struct GapWay {
  mut top : Double
  mut under : Double
  mut at : Double
  mut room : Double
  mut way : Double
  mut went : Double
  mut from : Double
  mut back : Double
}

///|
priv struct GapsSteady {
  mut held : Bool
  mut file : String
  ways : Map[String, GapWay]
  found : Set[String]
  mut window : (Double, Double)
  mut words : Double
}

///|
// kept across runs: begun anew by each Tester (gaps_steady_begin)
let gaps_steady : GapsSteady = {
  held: true,
  file: "",
  ways: {},
  found: Set([]),
  window: (-1.0, -1.0),
  words: -1.0,
}

///|
/// Each file's bar: how many faults a Tester made there may show.
// kept across runs: said once as a test program starts (its packages' `init`)
let gaps_steady_bars : Map[String, Int] = Map([])

///|
/// The faults known in the tests of the files `bars` names, each how many a Tester made there may show (as
/// rows_steady_known). Said by a test package as it starts (`fn init`); only falls.
pub fn gaps_steady_known(bars : Array[(String, Int)]) -> Unit {
  motion_bars_said("gaps_steady", bars)
  for b in bars {
    gaps_steady_bars.set(b.0, b.1)
  }
}

///|
fn gaps_steady_begin(loc : String, held : Bool) -> Unit {
  gaps_steady.held = held
  gaps_steady.ways.clear()
  gaps_steady.found.clear()
  gaps_steady.window = (-1.0, -1.0)
  gaps_steady.words = -1.0
  gaps_steady.file = match loc.find(":") {
    Some(i) => loc.unsafe_substring(start=0, end=i)
    None => loc
  }
}

///|
fn gaps_said(s : String) -> String {
  let one = s.replace_all(old="\n", new=" ")
  if one.length() > 24 {
    one.clamped_view(end=24).to_owned() + "…"
  } else {
    one
  }
}

///|
/// The faults the frame just drawn (at `now`, the display's frames `period` apart) shows, each pair's once: whose
/// words, how the room between them went.
fn Tester::gaps_steady_faults(self : Tester, now : Double, period : Double) -> Array[String] {
  let out : Array[String] = []
  let words = @signals.untracked(font_scale)
  let resized = gaps_steady.window != (self.w, self.h) || gaps_steady.words != words
  gaps_steady.window = (self.w, self.h)
  gaps_steady.words = words
  if resized || g().down {
    gaps_steady.ways.clear()
    return out
  }
  // (each line drawn once, seen, in the window)
  let said = self.words_said().filter(fn(w) { w.5 >= words_over_seen_least })
  let count : Map[String, Int] = Map([])
  for w in said {
    count[w.0] = count.get(w.0).unwrap_or(0) + 1
  }
  let lines = said.filter(fn(w) {
    count.get(w.0) == Some(1) &&
    w.4 > 0.0 &&
    w.3 > 0.0 &&
    w.2 + w.4 > 0.0 &&
    w.2 < self.h &&
    w.1 + w.3 > 0.0 &&
    w.1 < self.w
  })
  let here : Set[String] = Set([])
  for a in lines {
    // (the nearest under it across some of the same width)
    let mut under : (String, Double, Double, Double, Double, Double)? = None
    for b in lines {
      if b.0 == a.0 || b.2 < a.2 + a.4 - 0.5 || b.1 >= a.1 + a.3 || b.1 + b.3 <= a.1 {
        continue
      }
      match under {
        Some(u) if u.2 <= b.2 => ()
        _ => under = Some(b)
      }
    }
    guard under is Some(b) else { continue }
    // (each pair by its whole words: two pairs whose words begin alike, a message in a list and its row in a panel over
    // it cut short otherwise, are two ways, not one seen to jump between them)
    let key = a.0 + "\u{1}" + b.0
    let said = gaps_said(a.0) + " | " + gaps_said(b.0)
    here.add(key)
    let room = b.2 - (a.2 + a.4)
    let w = match gaps_steady.ways.get(key) {
      Some(w) if now - w.at <= 2.5 * period => w
      _ => {
        gaps_steady.ways[key] = { top: a.2, under: b.2, at: now, room, way: 0.0, went: 0.0, from: room, back: 0.0 }
        continue
      }
    }
    let both = (a.2 - w.top).abs() >= gaps_moving_least && (b.2 - w.under).abs() >= gaps_moving_least
    let d = room - w.room
    w.top = a.2
    w.under = b.2
    w.at = now
    let was = w.room
    w.room = room
    if !both {
      // (one standing: the other's own way; from here anew)
      w.way = 0.0
      w.went = 0.0
      w.back = 0.0
      continue
    }
    if d.abs() < 0.05 {
      continue
    }
    let way = if d > 0.0 { 1.0 } else { -1.0 }
    if w.way == 0.0 {
      w.way = way
      w.went = d.abs()
      w.from = was
      w.back = 0.0
    } else if way == w.way {
      if w.back > 0.0 {
        // (back a little, then on again: the way it went is still its way)
        w.back = 0.0
      }
      w.went = w.went + d.abs()
    } else {
      w.back = w.back + d.abs()
      if w.went >= gaps_back_least && w.back >= gaps_back_least {
        let peak = w.from + w.way * w.went
        out.push(
          said + ": the room between them went \{w.from} to \{peak} and back to \{room} at \{now}, both moving (" +
          (if w.way > 0.0 { "opened, then closed" } else { "closed, then opened" }) +
          ")",
        )
        // (from here its own way the other way)
        w.way = way
        w.went = w.back
        w.from = peak
        w.back = 0.0
      }
    }
  }
  // (pairs gone: forgotten)
  let gone : Array[String] = []
  gaps_steady.ways.each(fn(k, _) { if !here.contains(k) { gone.push(k) } })
  for k in gone {
    gaps_steady.ways.remove(k)
  }
  out
}

///|
/// The rule held on the frame just drawn: a fault not found before by this Tester, past its file's bar, fails the test
/// at once, with what and where.
fn Tester::hold_gaps_steady(self : Tester) -> Unit {
  let faults = self.gaps_steady_faults(self.fake.time, self.motion_period())
  if !gaps_steady.held {
    return
  }
  for f in faults {
    // (each pair's once)
    let who = match f.find(": ") {
      Some(i) => f.unsafe_substring(start=0, end=i)
      None => f
    }
    if gaps_steady.found.contains(who) {
      continue
    }
    gaps_steady.found.add(who)
    let bar = gaps_steady_bars.get(gaps_steady.file).unwrap_or(0)
    motion_known_said("gaps_steady", gaps_steady.file, gaps_steady.found.length(), bar, f)
    if self.motion == Count {
      println("MOTION gaps_steady \{gaps_steady.file}: \{f} (the Tester made at \{looks_made_at.val})")
      continue
    }
    if gaps_steady.found.length() > bar {
      let said = "gaps not steady (gaps_steady.mbt), on a frame drawn \{self.w}×\{self.h} at \{self.fake.time}, the Tester made at \{looks_made_at.val}: " +
        "\{f}; \{gaps_steady.found.length()} now, \{bar} known in \{gaps_steady.file}"
      @halt.saying(said)
    }
  }
}
