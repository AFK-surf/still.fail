// A flow of e2e/flows seen again in a Tester, its steps written as a test's (docs/stillfail-port.md, "Seen again"):
// the app (source.mbt) over a run's conversation with its core (e2e/traces), every input given by the test. An input
// draws only the frames it causes (Tester::draw); what the core said comes as the run had it, posted to mbui's queue
// (Tester::post on "core") as a frame ends once what it came after has been asked again (Replay::deliver,
// Tester::between_frames), taken as the next frame begins and handed to @core.receive, as a real core's is; a step
// that looks (see, gone) looks then,
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
  /// what may come is given a message at a time (Flow::until), not all at each frame's end
  priv one_by_one : Ref[Bool]
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
  // (writing the steps as a scripted run, FLOW_EMIT: the reports an older build of the app made, where its list was
  // and what it kept, waited for by nothing, so a trace the app has outgrown takes the steps on)
  if seed == 0 && emit_path() != "" {
    for call in ["client.focus", "chat.place", "draft.put"] {
      r.skip(call)
    }
  }
  r.shuffle(seed)
  r.attach()
  emit_start(seed, w, h, env)
  // what the core says comes through mbui's queue, as the app's does (src/stillfail: sfcore.start)
  @ui.on_message("core", @core.receive)
  let t = @ui.Tester::new(app, w~, h~, env~)
  // what the run's host said of its views (a player's state, a video's frames) said to the Tester's in its place
  r.host(fn(line) { ignore(t.view_said(line)) })
  // the run's core answering as soon as asked: what may come is posted as each frame ends, taken by the next
  let one_by_one = Ref::new(false)
  t.between_frames(fn() {
    if !one_by_one.val {
      r.deliver(to=fn(json, bytes) { t.post("core", json, bytes?) }) |> ignore
    }
  })
  // what the system lets the app show as the run's host said it (its app's notify.permission): a Tester's own lets it
  match notice_permission_of(trace) {
    Some(state) => t.set_notice_permission(state)
    None => ()
  }
  let f = { r, t, one_by_one }
  // each step the test says lets what came after it in the run come (Replay::step_taken)
  step_hook.val = Some(fn(line) { ignore(r.step_taken(line)) })
  f.core()
  f
}

///|
/// The notifications' permission the run's app told its core (`notify.permission`'s state), if it did.
fn notice_permission_of(trace : String) -> String? {
  let key = "\"call\":\"notify.permission\",\"params\":{\"state\":\""
  guard trace.find(key) is Some(i) else { return None }
  let rest = trace.view(start_offset=i + key.length())
  guard rest.find("\"") is Some(j) else { return None }
  Some(rest.view(end_offset=j).to_owned())
}

///|
/// What the core has for the app now, posted, the frame that takes it drawn for each lot: until nothing more may come
/// (the next message waits for an ask the app has not made again). Each turn gives at least one: it ends with the trace.
pub fn Flow::core(self : Flow) -> Unit {
  while self.r.due() || self.t.posted() > 0 {
    self.r.deliver(to=fn(json, bytes) { self.t.post("core", json, bytes?) }) |> ignore
    self.t.draw()
  }
  // (in a scripted run, the step waits for what it asked of the core to be answered: answered NAME)
  emit_answered(self.r.take_asked())
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
  // (and where the conversation stood: what the app asked that the run did not, what the next message waits for)
  let r = self.r
  let talk = "replay: \{r.left()} messages in not given, waiting for \{r.waiting().unwrap_or("-")}; diverged: \{r.diverged().join(", ")}; fuzzy: \{r.fuzzy().join(", ")}"
  let s = "flow: " + why + "\n" + talk + "\n" + self.t.dump()
  println(s)
  // (writing the steps as a scripted run, FLOW_EMIT, over a trace the app has outgrown: said, and the steps after it
  // written all the same, for the run to record the trace they need)
  if script.val is Some(_) {
    return
  }
  abort(s)
}

///|
/// What the run's script waited through at a step that waits (`until`, `gone`: what came after it began, Replay::
/// step_taken), given a message at a time, each with its frame, until `so` holds: as the run's script saw it come,
/// not past it (a player's place told after the script saw 0:02 is not given before it looks).
fn Flow::until(self : Flow, so : () -> Bool) -> Unit {
  self.one_by_one.val = true
  while !so() && (self.r.due() || self.t.posted() > 0) {
    self.r.deliver(at_most=1, to=fn(json, bytes) { self.t.post("core", json, bytes?) }) |> ignore
    self.t.draw()
  }
  self.one_by_one.val = false
}

///|
/// `what` is on screen now.
pub fn Flow::see(self : Flow, what : String) -> Unit {
  emit("until " + what)
  self.until(fn() { self.spots(what).length() > 0 })
  if self.spots(what).length() == 0 {
    self.fail("not on screen: " + what)
  }
}

///|
/// `n` or more of `what` on screen now.
pub fn Flow::see_n(self : Flow, n : Int, what : String) -> Unit {
  emit("untiln \{n} " + what)
  self.until(fn() { self.spots(what).length() >= n })
  let k = self.spots(what).length()
  if k < n {
    self.fail("\{k} of \{what} on screen, not \{n}")
  }
}

///|
/// `what` is not on screen now.
pub fn Flow::gone(self : Flow, what : String) -> Unit {
  emit("gone " + what)
  self.until(fn() { self.spots(what).length() == 0 })
  if self.spots(what).length() > 0 {
    self.fail("still on screen: " + what)
  }
}

///|
/// The focused field's words contain `words` (`""`: it is empty).
pub fn Flow::field(self : Flow, words : String) -> Unit {
  emit(if words == "" { "empty" } else { "field " + words.replace_all(old="\n", new="\\n") })
  let now = self.t.field_words()
  if (words == "" && now != "") || !now.contains(words) {
    self.fail("the field holds \{now.escape()}, not \{words.escape()}")
  }
}

///|
/// The lowest `what` on screen (`top`: the highest) tapped, and what the core answers to it given.
pub fn Flow::tap(self : Flow, what : String, top? : Bool = false) -> Unit {
  emit((if top { "tap1 " } else { "tap " }) + what)
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
  emit("tapxy \{x.to_int()} \{y.to_int()}")
  let (w, h) = self.t.size()
  self.t.tap(if x < 0.0 { w + x } else { x }, if y < 0.0 { h + y } else { y })
  self.core()
}

///|
/// The lowest `what` pressed for `ms` (a declared length: a long press's), then let go.
pub fn Flow::hold(self : Flow, what : String, ms : Double) -> Unit {
  // (a host's long press is held past its threshold: as long again, not to the frame)
  emit("hold \{(ms * 2.0).to_int()} " + what)
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
  emit("type " + s)
  self.t.type_text(s)
  self.t.draw()
  self.core()
}

///|
/// Words composed by the input method, not committed yet.
pub fn Flow::compose(self : Flow, s : String) -> Unit {
  emit("mark " + s)
  self.t.compose(s)
  self.t.draw()
  self.core()
}

///|
/// `s` on the clipboard, then the system's paste.
pub fn Flow::paste(self : Flow, s : String) -> Unit {
  emit("paste " + s)
  self.t.paste(s)
  self.core()
}

///|
/// A key by name, with what is held before it (as a flow's `key`: esc, enter, cmd+k, shift+enter).
pub fn Flow::key(self : Flow, name : String) -> Unit {
  emit("key " + name)
  if !self.t.key_named(name) {
    self.fail("no such key: " + name)
  }
  self.core()
}

///|
pub fn Flow::enter(self : Flow) -> Unit {
  emit("enter")
  self.t.enter()
  self.core()
}

///|
pub fn Flow::back(self : Flow) -> Unit {
  emit("back")
  self.t.back()
  self.core()
}

///|
/// `ms` on the frames' clock (a declared length: a motion's, a timer's), what the core has meanwhile given.
pub fn Flow::run_for(self : Flow, ms : Double) -> Unit {
  emit_wait(ms)
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
  emit_end()
  step_hook.val = None
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
  emit("clear")
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
    // (in a scripted run, the same time on: a step that does not wait for words, a tap at a place, comes after the
    // motion as here)
    emit_wait(end - now)
    self.t.run_for(end - now)
  }
  self.core()
}

///|
/// `page` pushed over Home, as a scripted run's `#env MBUI_OPEN_PAGE` has it (src/stillfail/main.mbt; there before
/// the first frame, here once the Tester has drawn Home: the same asks, matched whatever their order), in place once
/// its push is over (@ui.nav_rest).
pub fn Flow::open_page(self : Flow, page : @sfapp.Page) -> Unit {
  emit("#env MBUI_OPEN_PAGE=" + page_name(page))
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
  emit("hover " + what)
  guard self.spot(what) is Some((x, y)) else { return }
  self.t.move(x, y)
  self.t.draw()
  self.core()
}

///|
/// A secondary click on the lowest `what` (a flow's `rightclick`: a row's menu).
pub fn Flow::right_click(self : Flow, what : String) -> Unit {
  emit("rightclick " + what)
  guard self.spot(what) is Some((x, y)) else { return }
  self.t.right_click(x, y)
  self.core()
}

///|
/// The window made w × h (a flow's `resize`: a desktop's window across the wide frame's breakpoint).
pub fn Flow::resize(self : Flow, w : Double, h : Double) -> Unit {
  emit("resize \{w.to_int()} \{h.to_int()}")
  self.t.resize(w, h)
  self.core()
}

///|
/// The wheel turned by `dy` over the window's middle (a flow's `wheel`).
pub fn Flow::wheel(self : Flow, dy : Double) -> Unit {
  emit("wheel \{dy.to_int()}")
  let (w, h) = self.t.size()
  self.t.wheel(w / 2.0, h / 2.0, dy)
  self.core()
}

///|
/// The lowest `what` dragged by (dx, dy) in `steps` moves, a frame apart, then let go (a flow's `dragon`).
pub fn Flow::drag(self : Flow, what : String, dx : Double, dy : Double, steps? : Int = 10) -> Unit {
  // (a host's drag moves a frame a step: as many frames)
  emit("dragon \{dx.to_int()} \{dy.to_int()} \{(steps.to_double() * @ui.drag_step_ms).to_int()} " + what)
  guard self.spot(what) is Some((x, y)) else { return }
  self.t.drag(x, y, x + dx, y + dy, steps~)
  self.t.draw()
  self.core()
}

///|
/// Another app shares `text` (a link) titled `title` into the app (the Tester's share_in; a scripted run's
/// MBUI_SHARE_TEXT and MBUI_SHARE_TITLE, `#env` lines its run starts the app with), taken by the frame after.
pub fn Flow::share_in(self : Flow, text : String, title? : String = "") -> Unit {
  emit("#env MBUI_SHARE_TEXT=" + text)
  if title != "" {
    emit("#env MBUI_SHARE_TITLE=" + title)
  }
  self.t.share_in(text, title~)
  self.t.draw()
  self.core()
}
