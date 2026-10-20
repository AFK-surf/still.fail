// A flow of e2e/flows seen again in a Tester, its steps written as a test's (docs/stillfail-port.md, "Seen again"):
// the app (source.mbt) over a run's conversation with its core (e2e/traces), every input given by the test. An input
// draws only the frames it causes (Tester::draw); what the core said comes as the run had it, at a frame's start, each
// message once what it came after has been asked again (Replay::deliver); a step that looks (see, gone) looks then,
// waiting for nothing; time goes on only by `run_for` a declared length. At its end nothing is left to come, the app
// asked all the run asked and is idle (Flow::end).
//
// Each flow runs as the run had it, then again with what may come at once in orders drawn from seeds (Replay::shuffle):
// the same screen at the end every time (orders).

///|
/// A flow being seen again: the run's conversation, the tester showing the app over it.
pub struct Flow {
  r : @core.Replay
  t : @ui.Tester
}

///|
/// The app over `trace` in a w × h window (a phone's by default; the wide flows' 1280 × 800), what may come at once
/// in the order drawn from `seed` (0: as it came). `skip`: the run's calls a Tester does not make (the engine's start
/// told the core what the device is: sfcore.start). `drop`: asks of the run's its timing made, by words in them
/// (Replay::drop), each with what came for it.
pub fn Flow::start(
  trace : String,
  seed? : UInt = 0,
  skip? : Array[String] = ["client.device"],
  drop? : Array[String] = [],
  w? : Double = 390.0,
  h? : Double = 844.0,
  env? : Array[(String, String)] = [],
) -> Flow {
  let r = @core.Replay::parse(trace)
  for call in skip {
    r.skip(call)
  }
  // (asks the run's timing made, with what came for them: each test says which and why)
  for text in drop {
    if r.drop(text) == 0 {
      abort("flow: nothing in the run holds " + text + " to drop")
    }
  }
  r.shuffle(seed)
  r.attach()
  let t = @ui.Tester::new(
    fn(c) {
      r.deliver() |> ignore
      app(c)
    },
    w~,
    h~,
    env~,
  )
  let f = { r, t }
  f.core()
  f
}

///|
/// What the core has for the app now, given, a frame drawn for each lot: until nothing more may come (the next
/// message waits for an ask the app has not made again). Each turn gives at least one: it ends with the trace.
pub fn Flow::core(self : Flow) -> Unit {
  while self.r.due() {
    self.t.draw()
  }
}

///|
/// Where `what` is on screen, lowest first (in a chat, the newest): words, `=WORDS` exactly, `icon:NAME`, `img:NAME`,
/// as a flow's steps find them (Tester::locate).
fn Flow::spots(self : Flow, what : String) -> Array[(Double, Double)] {
  let at = self.t.locate(what)
  at.sort_by(fn(a, b) { b.1.compare(a.1) })
  at
}

///|
/// The test fails, saying what was not so and what is on screen.
fn Flow::fail(self : Flow, why : String) -> Unit {
  let s = "flow: " + why + "\n" + self.t.dump()
  println(s)
  abort(s)
}

///|
/// `what` is on screen now.
pub fn Flow::see(self : Flow, what : String) -> Unit {
  if self.spots(what).length() == 0 {
    self.fail("not on screen: " + what)
  }
}

///|
/// `n` or more of `what` on screen now.
pub fn Flow::see_n(self : Flow, n : Int, what : String) -> Unit {
  let k = self.spots(what).length()
  if k < n {
    self.fail("\{k} of \{what} on screen, not \{n}")
  }
}

///|
/// `what` is not on screen now.
pub fn Flow::gone(self : Flow, what : String) -> Unit {
  if self.spots(what).length() > 0 {
    self.fail("still on screen: " + what)
  }
}

///|
/// The focused field's words contain `words` (`""`: it is empty).
pub fn Flow::field(self : Flow, words : String) -> Unit {
  let now = self.t.field_words()
  if (words == "" && now != "") || !now.contains(words) {
    self.fail("the field holds \{now.escape()}, not \{words.escape()}")
  }
}

///|
/// The lowest `what` on screen (`top`: the highest) tapped, and what the core answers to it given.
pub fn Flow::tap(self : Flow, what : String, top? : Bool = false) -> Unit {
  let at = self.spots(what)
  if at.length() == 0 {
    self.fail("nothing to tap: " + what)
    return
  }
  let (x, y) = if top { at[at.length() - 1] } else { at[0] }
  self.t.tap(x, y)
  self.core()
}

///|
/// A tap at (x, y) (negative: from the right, the bottom).
pub fn Flow::tap_at(self : Flow, x : Double, y : Double) -> Unit {
  let (w, h) = self.t.size()
  self.t.tap(if x < 0.0 { w + x } else { x }, if y < 0.0 { h + y } else { y })
  self.core()
}

///|
/// The lowest `what` pressed for `ms` (a declared length: a long press's), then let go.
pub fn Flow::hold(self : Flow, what : String, ms : Double) -> Unit {
  let at = self.spots(what)
  if at.length() == 0 {
    self.fail("nothing to hold: " + what)
    return
  }
  let (x, y) = at[0]
  self.t.press_at(x, y)
  self.t.run_for(ms)
  self.t.release(x, y)
  self.t.draw()
  self.core()
}

///|
/// Words committed by the input method.
pub fn Flow::type_text(self : Flow, s : String) -> Unit {
  self.t.type_text(s)
  self.t.draw()
  self.core()
}

///|
/// Words composed by the input method, not committed yet.
pub fn Flow::compose(self : Flow, s : String) -> Unit {
  self.t.compose(s)
  self.t.draw()
  self.core()
}

///|
/// `s` on the clipboard, then the system's paste.
pub fn Flow::paste(self : Flow, s : String) -> Unit {
  self.t.paste(s)
  self.core()
}

///|
/// A key by name, with what is held before it (as a flow's `key`: esc, enter, cmd+k, shift+enter).
pub fn Flow::key(self : Flow, name : String) -> Unit {
  if !self.t.key_named(name) {
    self.fail("no such key: " + name)
  }
  self.core()
}

///|
pub fn Flow::enter(self : Flow) -> Unit {
  self.t.enter()
  self.core()
}

///|
pub fn Flow::back(self : Flow) -> Unit {
  self.t.back()
  self.core()
}

///|
/// `ms` on the frames' clock (a declared length: a motion's, a timer's), what the core has meanwhile given.
pub fn Flow::run_for(self : Flow, ms : Double) -> Unit {
  self.t.run_for(ms)
  self.core()
}

///|
/// The flow's end: all the run's conversation given, every ask of the run's made again as it was (but `unmade`, the
/// run's asks this one does not make, each said why at the test), nothing else asked, and the app idle. The screen
/// as it ends, in a number (screen_sum). The app's core the engine again.
pub fn Flow::end(self : Flow, unmade? : Array[String] = [], unsettled_ok? : String = "") -> String {
  self.core()
  // (unsettled_ok: why the app still asks for frames of its own here, until its migration lands; the idle check is
  // left out for this flow, said on the log)
  if unsettled_ok == "" {
    self.t.assert_idle()
  } else {
    println("flow: not checked idle: " + unsettled_ok)
  }
  let r = self.r
  let why = []
  if r.left() > 0 {
    why.push("\{r.left()} messages in not given, the next waiting for \{r.waiting().unwrap_or("-")}")
  }
  if r.diverged().length() > 0 {
    why.push("asked what the run did not: " + r.diverged().join(", "))
  }
  if r.fuzzy().length() > 0 {
    why.push("asked with other params: " + r.fuzzy().join(", "))
  }
  let left = r.unmade().filter(fn(u) { !unmade.iter().any(fn(k) { u.contains(k) }) })
  if left.length() > 0 {
    why.push("did not ask what the run did: " + left.join(", "))
  }
  let sum = screen_sum(self.t)
  @core.Replay::detach()
  if why.length() > 0 {
    self.fail(why.join("; "))
  }
  sum
}

///|
/// The seeds a flow's other orders are drawn from (Replay::shuffle).
pub let seeds : Array[UInt] = [1, 2, 3]

///|
/// `flow` (a flow's test from Flow::start(seed=…) to its end's screen) run as the run had it, then in the orders
/// drawn from `seeds`: the same end each time.
pub fn orders(flow : (UInt) -> String raise) -> Unit raise {
  let first = flow(0)
  for seed in seeds {
    let again = flow(seed)
    if again != first {
      let s = "flow: in the order drawn from seed \{seed} the screen ends otherwise (\{again}, not \{first})"
      println(s)
      abort(s)
    }
  }
}

///|
/// The focused field emptied (all of it chosen, then deleted), as a flow's `clear`.
pub fn Flow::clear(self : Flow) -> Unit {
  self.t.clear()
  self.core()
}

///|
/// On the frames' clock to `end`, a motion's own end as it says it (`@kit.sheet_rest(key)`, `@ui.nav_rest()`): the
/// test fails if it has not started yet (+inf: draw first) or does not move (-1).
pub fn Flow::run_to(self : Flow, end : Double) -> Unit {
  if end < 0.0 || end > 1.0e300 {
    self.fail("no motion to run to (its end: \{end})")
    return
  }
  let now = self.t.time()
  if end > now {
    self.t.run_for(end - now)
  }
  self.core()
}

///|
/// `page` pushed over Home, as a scripted run's `#env MBUI_OPEN_PAGE` has it (src/stillfail/main.mbt; there before
/// the first frame, here once the Tester has drawn Home: the same asks, matched whatever their order), in place once
/// its push is over (@ui.nav_rest).
pub fn Flow::open_page(self : Flow, page : @sfapp.Page) -> Unit {
  @sfapp.open_page(page)
  self.t.draw()
  self.core()
  self.run_to(@ui.nav_rest())
}

// ── batch C's steps (appended): a desktop's pointer, the window, a drag ─────────────────────────────

///|
/// The lowest `what` (`top`: the highest) on screen, or the test fails.
fn Flow::spot(self : Flow, what : String, top? : Bool = false) -> (Double, Double)? {
  let at = self.spots(what)
  if at.length() == 0 {
    self.fail("not on screen: " + what)
    return None
  }
  Some(if top { at[at.length() - 1] } else { at[0] })
}

///|
/// The pointer over the lowest `what`, no button down (a flow's `hover`).
pub fn Flow::hover(self : Flow, what : String) -> Unit {
  guard self.spot(what) is Some((x, y)) else { return }
  self.t.move(x, y)
  self.t.draw()
  self.core()
}

///|
/// A secondary click on the lowest `what` (a flow's `rightclick`: a row's menu).
pub fn Flow::right_click(self : Flow, what : String) -> Unit {
  guard self.spot(what) is Some((x, y)) else { return }
  self.t.right_click(x, y)
  self.core()
}

///|
/// The window made w × h (a flow's `resize`: a desktop's window across the wide frame's breakpoint).
pub fn Flow::resize(self : Flow, w : Double, h : Double) -> Unit {
  self.t.resize(w, h)
  self.core()
}

///|
/// The wheel turned by `dy` over the window's middle (a flow's `wheel`).
pub fn Flow::wheel(self : Flow, dy : Double) -> Unit {
  let (w, h) = self.t.size()
  self.t.wheel(w / 2.0, h / 2.0, dy)
  self.core()
}

///|
/// The lowest `what` dragged by (dx, dy) in `steps` moves, a frame apart, then let go (a flow's `dragon`).
pub fn Flow::drag(self : Flow, what : String, dx : Double, dy : Double, steps? : Int = 10) -> Unit {
  guard self.spot(what) is Some((x, y)) else { return }
  self.t.drag(x, y, x + dx, y + dy, steps~)
  self.t.draw()
  self.core()
}
