// A flow of e2e/flows seen again in a Tester, its steps written as a test's (e2e/README.md):
// the app (source.mbt) over a run's conversation with its core (e2e/traces), every input given by the test. An input
// draws only the frames it causes (Tester::draw); what the core said comes as the run had it, posted to mbui's queue
// (Tester::post on "core") as a frame ends once what it came after has been asked again (Replay::deliver,
// Tester::between_frames), taken as the next frame begins and handed to @core.receive, as a real core's is; a step
// that looks (see, gone) looks then,
// waiting for nothing; time goes on only by `run_for` a declared length. At its end nothing is left to come, the app
// asked all the run asked and is idle (Flow::end).
//
// Each flow runs first as the run had it, strictly: each message at the run's own pace (the gap to the one before it in
// the run's wall clock, the Tester's clock stepped a frame at a time to it), every ask compared with the run's. Then
// again three ways the timing could have gone (at once, twice as fast, twice as slow; what is due at one moment in an
// order drawn from a seed): the same screen and state at the end, nothing asked left unanswered, the app idle; the
// reports it makes on the way (Replay::pace) as their timing makes them (orders).

///|
/// A flow being seen again: the run's conversation, the tester showing the app over it.
pub struct Flow {
  r : @core.Replay
  t : @ui.Tester
  /// the strict pass (the run's pace, every ask compared), not one of the others (orders)
  strict : Bool
  /// what was said to move (Tester::moving's lines) since the last step was taken
  priv said : Array[String]
  /// what may come is given a message at a time (Flow::until), not all at each frame's end
  priv one_by_one : Ref[Bool]
  /// what moved as the last step that acts was taken (Tester::moving's lines): not what it began
  priv at_step : Array[String]
}

///|
/// The Tester's frame: its clock goes on a frame at a time, one each 16 ms (Tester::run_for).
pub let frame_ms : Double = 16.0

///|
/// The pass `seed` names (orders): 0 the strict one, at the run's pace; then at once, twice as fast, twice as slow.
fn pace_of(seed : UInt) -> @core.Pace {
  match seed {
    0 => @core.AsRun(1.0)
    1 => @core.AtOnce
    2 => @core.AsRun(0.5)
    _ => @core.AsRun(2.0)
  }
}

///|
/// The app over `trace` in a w × h window (a phone's by default; the wide flows' 1280 × 800), in the pass `seed`
/// names (0: the strict one, as the run had it; else what is due at once in the order drawn from it, at that pass's
/// pace: pace_of). `drop`: asks of the run's its timing made, by words in them
/// (Replay::drop), each with what came for it. `platform`: the system it is on (Tester::new's), by default by its width:
/// a phone's (Android) narrower than medium_from, else the Mac.
#callsite(autofill(loc))
pub fn Flow::start(
  trace : String,
  seed? : UInt = 0,
  drop? : Array[String] = [],
  w? : Double = 390.0,
  h? : Double = 844.0,
  env? : Array[(String, String)] = [],
  platform? : Int,
  loc~ : SourceLoc,
) -> Flow {
  let r = @core.Replay::parse(trace)
  use_recorded_jobs(r)
  // (asks the run's timing made, with what came for them: each test says which and why)
  for text in drop {
    if r.drop(text) == 0 {
      abort("flow: nothing in the run holds " + text + " to drop")
    }
  }
  // (the core's pure calls the app has kept answers for are answered here, not asked of the run's core: src/sfreplay
  // source.mbt; the run's asks of them not waited for)
  r.skip_where(fn(name, params) { @sfkept.has(name, params) })
  r.shuffle(seed)
  // (a test's steps written as a scripted run (FLOW_EMIT) over a trace the app may have outgrown: at once, as the steps
  // do not hang on the run's pace, and an older trace's asks have no wall clock to keep it by)
  r.pace(if seed == 0 && emit_path() != "" { @core.AtOnce } else { pace_of(seed) }, strict=seed == 0)
  r.attach()
  // (on the screen it was made on: a phone's window's runs a phone's, Android's, pointed at by a finger; a wider one's
  // the Mac's, by a mouse, and keyboard and mouse's window made narrow (`platform` 0); the live run recording it again on a Mac
  // plays that system too)
  let platform = match platform {
    Some(p) => p
    None => if w < @sf.medium_from { 2 } else { 0 }
  }
  emit_start(seed, w, h, if platform == 2 { env + [("MBUI_PLATFORM", "android")] } else { env })
  // what the core says comes through mbui's queue, as the app's does (src/stillfail: sfcore.start)
  @ui.on_message("core", @core.receive)
  // (the app started with what the run's was: its trace's env, then what the test says of its own; a trace that does
  // not say it is one recorded before it was kept, to record again: never run as if started with nothing)
  if r.env().is_empty() && emit_path() == "" {
    abort(
      "flow: this test's trace has no {\"env\":…} head, what its run's app was started with (src/stillfail: CORETRACE env): record it again (scripts/rerecord.sh)",
    )
  }
  // (and its host's answers as the run's gave them, where it kept them: a word's bounds as the system splits words)
  // (on the system the run was on, its core told so: above)
  let t = match r.text() {
    Some(text) => @ui.Tester::new(app, w~, h~, env=r.env() + env, text~, platform~, tree=@sfapp.app_tree(the_source), loc~)
    None => @ui.Tester::new(app, w~, h~, env=r.env() + env, platform~, tree=@sfapp.app_tree(the_source), loc~)
  }
  // (which station this machine is, as the run's host said)
  if r.local_station() != "" {
    t.set_local_station(r.local_station())
  }
  // (the time of day the run's: its first event that has happened here (the app's first ask, made as it started) at
  // the run's moment of it, going on with the frames' clock from there, @ui.wall_ms)
  match r.first_happened() {
    Some((at, wall)) => t.set_wall(wall + (t.time() - at))
    None => ()
  }
  // what the run's host said of its views (a player's state, a video's frames) said to the Tester's in its place
  r.host(fn(line) { ignore(t.view_said(line)) })
  // the run's pace kept on the Tester's clock: when an ask is made again, when a message is given
  r.clock(fn() { t.time() })
  // the run's core answering as it did: what is due is posted as each frame ends, taken by the next (but while a
  // waiting step is given what came for it a message at a time: Flow::until)
  let one_by_one = Ref::new(false)
  // (the last of the run's frames given to the Tester's display)
  let frames_to = Ref::new(-@double.infinity)
  let said : Array[String] = []
  // (and when the next is due, a frame drawn then however the clock is run on: what came at a time came at it)
  // (what the run's host said comes before the frame it was said for: given as a frame ends, it is the next one's, by
  // that frame's time, as a host's events before a vsync are that frame's)
  t.between_frames(fn() {
    for m in t.moving() {
      if !said.contains(m) {
        said.push(m)
      }
    }
    if !one_by_one.val {
      r.deliver(now=t.time(), host_by=t.taken_at(), taken_at=t.taken_at(), to=fn(json, bytes) { t.post("core", json, bytes?) }) |> ignore
    }
    // (the run's pace: while its host's lines come, a frame each, the display's frames where the run's were, Tester::
    // set_frame_times: each run of them mapped onto this clock by its first line given here; between them, the
    // display's own period)
    if seed == 0 && emit_path() == "" {
      match r.host_given() {
        // (one given late, held for a step, says nothing of when the run's frames fall here: one given in its time)
        Some((at, wall)) if wall > frames_to.val && at > t.time() - t.frame_period() => {
          let run = []
          for w in r.host_frames() {
            if w < wall {
              continue
            }
            match run.last() {
              // (a pause, not a frame: the run of frames over)
              Some(last) if w - last > 2.0 * t.frame_period() => break
              _ => run.push(w)
            }
          }
          frames_to.val = run.last().unwrap_or(wall)
          let now = t.time()
          // (and the time of day the run's again from here: this run of frames' first line's on its clock)
          t.set_wall(wall + (now - at))
          let times = run.map(fn(w) { w - wall + at }).filter(fn(x) { x > now })
          if times.length() > 0 {
            t.set_frame_times(times)
          }
        }
        _ => ()
      }
    }
  }, due=fn() { r.next_due().unwrap_or(@double.infinity) })
  // (the run's own pace: its display's frames as far apart as its host's lines say they were; a trace whose host said
  // none, a display's 60 Hz: what came between two of its frames taken by the later together, as the run's display took
  // it, not each at its own moment)
  if seed == 0 && emit_path() == "" {
    t.set_frame_period(r.frame_period().unwrap_or(run_frame_ms))
  }
  // what the system lets the app show as the run's host said it (its app's notify.permission): a Tester's own lets it
  match notice_permission_of(trace) {
    Some(state) => t.set_notice_permission(state)
    None => ()
  }
  let f = {
    r,
    t,
    strict: seed == 0,
    one_by_one,
    said,
    at_step: [],
  }
  // each step the test says taken when the run took it, at this pace (at once: as soon as the test takes it), what
  // came after it in the run let come (Replay::step_taken)
  step_hook.val = Some(fn(line) { f.take_step(line) })
  // what the run had before its script's first step (its start: the account, the lists), as it came, the clock on to
  // each: a step holds what came after it (Replay::step_taken)
  f.settle_start()
  f
}

///|
fn Flow::settle_start(self : Flow) -> Unit {
  while true {
    self.r.deliver(now=self.t.time(), host_by=self.t.taken_at(), taken_at=self.t.taken_at(), to=fn(json, bytes) { self.t.post("core", json, bytes?) }) |> ignore
    if self.t.posted() > 0 {
      self.t.draw()
      continue
    }
    match self.r.next_due() {
      Some(at) if at < @double.infinity => self.t.run_for(frame_ms)
      _ => break
    }
  }
  emit_answered(self.r.take_asked())
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
/// The step `line` (as the script says it) taken when the run took it, at this pace: the clock on to that moment, what
/// is due meanwhile given (the run's script typed, then waited for an upload, then tapped: as long here). A step the
/// trace does not hold, or one whose time waits for an ask not made again, is taken now.
fn Flow::take_step(self : Flow, line : String) -> Unit {
  match self.r.step_at(line) {
    Some(at) => {
      let now = self.t.time()
      if at > now && at < @double.infinity {
        self.t.run_for(at - now)
      }
      // (the time of day the run's as it took the step: what the app names by it, a picture marked, the same)
      // (as when the run's clock frames went on from where the run took it: later here, later in the day by as much)
      match self.r.step_wall(line) {
        Some(wall) =>
          self.t.set_wall(
            wall + (if at > -@double.infinity && at < @double.infinity { self.t.time() - at } else { 0.0 }),
          )
        None => ()
      }
      // (a step that acts begins what a later run_to_rest may wait for: what was said before it is not)
      if self.r.step_taken(line) && !waiting_step(line) {
        self.said.clear()
      }
    }
    None => ()
  }
  if !waiting_step(line) {
    self.at_step.clear()
    self.at_step.push_iter(self.t.moving().iter())
  }
}

///|
/// What the core has for the app, each message when it is due: the clock stepped a frame at a time to it, posted, taken
/// by the frame after; until nothing more may come (the next message waits for an ask the app has not made again).
pub fn Flow::core(self : Flow) -> Unit {
  // (writing the steps as a scripted run, FLOW_EMIT: what may come given a frame at a time on a clock that stands, as
  // before the run's pace was kept, for a trace the app has outgrown to take the test's steps to their end)
  if self.strict && emit_path() != "" {
    while self.r.due() || self.t.posted() > 0 {
      self.r.deliver(to=fn(json, bytes) { self.t.post("core", json, bytes?) }) |> ignore
      self.t.draw()
    }
    emit_answered(self.r.take_asked())
    return
  }
  // what is due now, each lot taken by a frame; the clock stands: it goes on only as the test lets it (run_for, run_to,
  // a step taken when the run took it, a waiting step until what it waits for has come: Flow::until)
  while true {
    self.r.deliver(now=self.t.time(), host_by=self.t.taken_at(), taken_at=self.t.taken_at(), to=fn(json, bytes) { self.t.post("core", json, bytes?) })
    |> ignore
    if self.t.posted() > 0 {
      self.t.draw()
    } else {
      break
    }
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
/// Those of them a finger reaches, lowest first (Tester::reachable): where a tap goes, as a scripted run's does.
fn Flow::reach_spots(self : Flow, what : String) -> Array[(Double, Double)] {
  let at = self.t.reachable(what)
  at.sort_by(fn(a, b) { b.1.compare(a.1) })
  at
}

///|
/// What the test says must hold here, `why` said when it does not: the test fails, as an assert would; but while it
/// writes the steps as a scripted run over a trace the app has outgrown (FLOW_EMIT), said and the steps after it
/// written all the same (Flow::fail).
pub fn Flow::check(self : Flow, so : Bool, why : String) -> Unit {
  if !so {
    self.fail(why)
  }
}

///|
/// The test fails, saying what was not so and what is on screen.
fn Flow::fail(self : Flow, why : String) -> Unit {
  // (and where the conversation stood: what the app asked that the run did not, what the next message waits for)
  let r = self.r
  let talk = "replay: \{r.left()} messages in not given, waiting for \{r.waiting().unwrap_or("-")}; diverged: \{r.diverged().join(", ")}; fuzzy: \{r.fuzzy().join(", ")}"
  let pass = if self.strict { "as the run had it" } else { "in another timing" }
  let s = "flow: " + why + " (at \{self.t.time()} ms, \{pass})\n" + talk + "\n" + self.t.dump()
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
pub fn Flow::until(self : Flow, so : () -> Bool) -> Unit {
  self.one_by_one.val = true
  let began = self.t.time()
  while !so() {
    // (bounded on the run's clock: what it waits for never coming, said, not run on)
    if self.t.time() - began > until_most_ms {
      self.fail("not so after \{until_most_ms.to_int()} ms; moving: \{self.t.moving().join("; ")}")
      break
    }
    let n = self.r.deliver(at_most=1, now=self.t.time(), host_by=self.t.taken_at(), taken_at=self.t.taken_at(), to=fn(json, bytes) { self.t.post("core", json, bytes?) })
    if n > 0 || self.t.posted() > 0 {
      self.t.draw()
      continue
    }
    // (nothing due yet at the run's pace, or nothing more to come: the clock on a frame at a time, as the run's step
    // waited on, until what it waits for is so (a page pushed when its answer came, sliding in; a line a timer brings)
    // or the most it waits)
    self.t.run_for(frame_ms)
  }
  self.one_by_one.val = false
}

///|
/// The display's frame period of a run whose trace does not say it (Flow::start): a phone's 60 Hz.
let run_frame_ms : Double = 1000.0 / 60.0

///|
/// The most a step waits on the run's clock (Flow::until) for what it waits for.
let until_most_ms : Double = 60000.0

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
  // (as a scripted run's tap waits for what it taps to show, where a finger reaches it, not under a sheet or a scrim:
  // what came for it given first, Flow::until)
  self.until(fn() { self.reach_spots(what).length() > 0 })
  let at = self.reach_spots(what)
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
  // (as a scripted run's tap waits for what it taps to show: what came for it given first, Flow::until)
  self.until(fn() { self.spots(what).length() > 0 })
  let at = self.spots(what)
  if at.length() == 0 {
    self.fail("nothing to hold: " + what)
    return
  }
  let (x, y) = at[0]
  // (held as the run's host held it, past the threshold: not released on its very moment)
  self.t.press_at(x, y)
  self.t.run_for(ms * 2.0)
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
/// The run's `n`-th answer to a call `call` (counted from its start) given: a scripted run's `answered CALL`, what a
/// step waits for when what it waits on is what the app asked of the core and nothing on screen says it (a site view's
/// page loaded, its requests through the core answered).
pub fn Flow::answered(self : Flow, call : String, n : Int) -> Unit {
  // (what was asked before, written as the steps would have; this call's own counted by the n written here, not
  // written again by the next step: a scripted run waits for the n-th, not for more)
  emit_answered(self.r.take_asked().filter(fn(c) { c != call }))
  emit_answered_to(call, n)
  self.until(fn() { self.r.answers_given(call) >= n })
  emit_answered(self.r.take_asked().filter(fn(c) { c != call }))
  if self.r.answers_given(call) < n {
    self.fail("\{call} answered \{self.r.answers_given(call)} times, not \{n}")
  }
}

///|
/// `s` again and again to `n` characters, pasted (as a flow's `pasten N TEXT`: a paste too long to write out).
pub fn Flow::paste_n(self : Flow, n : Int, s : String) -> Unit {
  emit("pasten \{n} " + s)
  let words = StringBuilder::new()
  let chars = s.to_array()
  for i in 0..<n {
    words.write_char(chars[i % chars.length()])
  }
  self.t.paste(words.to_string())
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
/// The flow's end: the app idle; strict, all the run's conversation given, every ask of the run's made again as it was
/// (but `unmade`, the run's asks this one does not make, each said why at the test), nothing else asked; another
/// timing, all it asked answered. The screen
/// as it ends, in a number (screen_sum). The app's core the engine again.
pub fn Flow::end(self : Flow, unmade? : Array[String] = []) -> String {
  self.core()
  // (the rest of the run's conversation as it came, the clock on to each; what came after the test's last step, that
  // it did not wait for (an agent's turn ending after the run's last step, and in another timing later still), told
  // motions of its own: each run to the end it says, Tester::rest_of; and again while what those motions' frames asked
  // is answered, a page gone at its slide's end telling the core where it was)
  let mut rounds = 0
  let wakes : Map[String, Int] = {}
  while true {
    rounds += 1
    // (what never stops asking: said, not hidden behind the idle check)
    if rounds > end_rounds {
      self.fail(
        "the end still not quiet after \{end_rounds} rounds: \{self.r.left()} messages in left, the next due at \{self.r.next_due()}, \{self.t.posted()} posted, moving: \{self.t.moving().join("; ")}",
      )
      break
    }
    while self.r.next_due() is Some(_) || self.t.posted() > 0 {
      self.r.deliver(now=self.t.time(), host_by=self.t.taken_at(), taken_at=self.t.taken_at(), to=fn(json, bytes) {
        self.t.post("core", json, bytes?)
      })
      |> ignore
      self.t.run_for(frame_ms)
    }
    while self.t.rest_of("") > self.t.time() {
      self.t.run_for(self.t.rest_of("") - self.t.time())
    }
    // (a toast's time too, before the frame owed: what is shown does not wait for it, but one left at the end goes at
    // its time, not as the end's last frame happens to fall)
    let toast = @kit.toast_due("toast")
    if toast > self.t.time() {
      self.t.run_for(toast - self.t.time())
      continue
    }
    // (the frame the last one left owed: what it asks (a page gone, its player's place told) answered too; what it sets
    // moving (a box laid out anew by what came last) run to its end as the others)
    self.t.draw()
    if self.t.rest_of("") > self.t.time() {
      continue
    }
    // (and what is told to happen at a time of its own (a timer: an agent's activity lingering), to that time, as a
    // motion to its end; one that keeps telling itself again never ends: said, not run on)
    match self.t.next_wake() {
      Some((at, by)) if at > self.t.time() => {
        let n = wakes.get(by).unwrap_or(0) + 1
        wakes[by] = n
        if n > end_wakes {
          self.fail("a timer that keeps telling itself again (\{by}): the flow's end never quiet")
          break
        }
        self.t.run_for(at - self.t.time())
        continue
      }
      _ => ()
    }
    if self.r.next_due() is None && self.t.posted() == 0 {
      break
    }
  }
  self.t.assert_idle()
  let r = self.r
  let why = []
  if !self.strict {
    // another timing: the reports it makes its own, its asks not compared; what it asked all answered
    if r.unanswered() > 0 {
      why.push(
        "\{r.unanswered()} messages in for asks it made not given, the next waiting for \{r.waiting().unwrap_or("-")}",
      )
    }
  } else {
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
  }
  let sum = screen_sum(self.t)
  @core.Replay::detach()
  // (what the app asked as the flow ended (a page gone at its slide's end, its player's place told): the script
  // written waits for its answers too, so the run keeps them)
  emit_answered(self.r.take_asked())
  emit_end()
  step_hook.val = None
  if why.length() > 0 {
    self.fail(why.join("; "))
  }
  sum
}

///|
/// How many times a flow's end gives what came, runs what moves to its end and draws the frame left owed, before it
/// says it never goes quiet (Flow::end).
let end_rounds : Int = 10

///|
/// How many times one timer may be run to at a flow's end before it is said to keep telling itself again (Flow::end).
let end_wakes : Int = 3

///|
/// The other passes a flow is run in (pace_of): at once, twice as fast, twice as slow, each in an order of its seed's.
pub let seeds : Array[UInt] = [1, 2, 3]

///|
/// `flow` (a flow's test from Flow::start(seed=…) to its end's screen) run strictly as the run had it, then in the
/// other passes (`seeds`): the same end each time.
pub fn orders(flow : (UInt) -> String raise) -> Unit raise {
  let first = flow(0)
  for seed in seeds {
    let again = flow(seed)
    if again != first {
      let s = "flow: in the pass \{seed} (\{pace_of(seed)}) the screen ends otherwise (\{again}, not \{first})"
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
    self.fail("no motion to run to (its end: \{end}); said since the last step that acted: \{self.said.join(" | ")}")
    return
  }
  let now = self.t.time()
  if end > now {
    // (in a scripted run, the same length on its clock, as run_for writes it: a step after it at once looks for what
    // is there then, not for a page still sliding in over the one it leaves (two ＋ in a bar, the lower page's taken)
    // or a sheet still going down over what is under it)
    emit_wait(end - now)
    self.t.run_for(end - now)
  }
  self.core()
}

///|
/// Whether a step's line waits for something to be so (until, gone…), as against acting on the app.
fn waiting_step(line : String) -> Bool {
  ["until ", "untiln ", "gone ", "noticed ", "nonotice ", "field ", "empty", "now until ", "now gone "].iter().any(fn(
    p,
  ) {
    line.has_prefix(p)
  })
}

///|
/// On the frames' clock to the end of what moves named `name` (Tester::rest_of: a line of Tester::moving that says it),
/// as run_to. At the run's pace it may be over already, the run's own waiting having taken the clock past it: when a
/// motion so named was said since the last step that acted and is at rest now, that is where the test would have run it to. One
/// not said since, or the at-once pass: no motion.
pub fn Flow::run_to_rest(self : Flow, name : String) -> Unit {
  let end = self.t.rest_of(name)
  if end < 0.0 && self.rest_passed(name) {
    self.core()
    return
  }
  self.run_to(end)
}

///|
/// Whether what moves named `name` was said since the last step that acted and is at rest now (Flow::run_to_rest):
/// a motion said and over, not one never said.
pub fn Flow::rest_passed(self : Flow, name : String) -> Bool {
  self.t.rest_of(name) < 0.0 && self.said.iter().any(fn(m) { m.contains(name) })
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
  // (a page pushed over Home slides in, to its end)
  if @ui.nav_rest() >= 0.0 {
    self.run_to(@ui.nav_rest())
  }
}

// ── batch C's steps (appended): a desktop's pointer, the window, a drag ─────────────────────────────

///|
/// The lowest `what` (`top`: the highest) on screen, or the test fails.
fn Flow::spot(self : Flow, what : String, top? : Bool = false) -> (Double, Double)? {
  // (as a scripted run's tap waits for what it taps to show: what came for it given first, Flow::until)
  self.until(fn() { self.spots(what).length() > 0 })
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
/// The list under the lowest `what` scrolled by `dy` (a mouse wheel's: down the page as it grows), and what the core
/// answers to it given.
pub fn Flow::wheel_at(self : Flow, what : String, dy : Double) -> Unit {
  emit("wheelat \{dy.to_int()} " + what)
  guard self.spot(what) is Some((x, y)) else { return }
  self.t.wheel(x, y, dy)
  self.core()
  // the list's wheel eased to where it goes (a phone's lists, Android's, go there at once)
  let eased = self.t.rest_of("wheel ease")
  if eased > self.t.time() && eased < @double.infinity {
    self.run_to(eased)
  }
}

///|
/// The toast on screen gone: its time shown (`@sfapp.toast_ms`, a timer), then the frame that sends it away and its way
/// out (`@kit.toast_rest`).
pub fn Flow::toast_gone(self : Flow) -> Unit {
  self.run_for(@sfapp.toast_ms)
  self.t.draw()
  // (its way out over already where it began before the test looked at it: a step that waited took the clock past)
  let out = @kit.toast_rest("toast")
  if out > self.t.time() {
    self.run_to(out)
  }
}

///|
/// One of the app's notifications holds `text` in its title or words.
fn Flow::holds_notice(self : Flow, text : String) -> Bool {
  self.t.notices().iter().any(fn(n) { n.title.contains(text) || n.body.contains(text) })
}

///|
/// One of the app's notifications (the system's, @ui.notice_show: Tester::notices) holds `text` in its title or words
/// now.
pub fn Flow::noticed(self : Flow, text : String) -> Unit {
  emit("noticed " + text)
  // (as a scripted run's `noticed` waits for it: what came for it given first, Flow::until)
  self.until(fn() { self.holds_notice(text) })
  if !self.holds_notice(text) {
    self.fail("no notice holds " + text)
  }
}

///|
/// None of the app's notifications holds `text` now.
pub fn Flow::no_notice(self : Flow, text : String) -> Unit {
  emit("nonotice " + text)
  self.until(fn() { !self.holds_notice(text) })
  if self.holds_notice(text) {
    self.fail("a notice holds " + text)
  }
}

///|
/// The notification holding `text` tapped, as the system's shade sends the tap (Tester::tap_notice), and what the
/// core answers to what that opens given.
pub fn Flow::tap_notice(self : Flow, text : String) -> Unit {
  emit("notice " + text)
  self.until(fn() { self.holds_notice(text) })
  if !self.t.tap_notice(text) {
    self.fail("no notice to tap holds " + text)
    return
  }
  self.core()
}

///|
/// A finger down at (x, y) (negative: from the right, the bottom), moved by (dx, dy) a move a frame over `steps`
/// frames, then lifted there (a flow's `drag X Y DX DY`); what the core answers given.
pub fn Flow::drag_at(self : Flow, x : Double, y : Double, dx : Double, dy : Double, steps? : Int = 10) -> Unit {
  emit("drag \{x.to_int()} \{y.to_int()} \{dx.to_int()} \{dy.to_int()} \{(steps.to_double() * @ui.drag_step_ms).to_int()}")
  let (w, h) = self.t.size()
  let x0 = if x < 0.0 { w + x } else { x }
  let y0 = if y < 0.0 { h + y } else { y }
  self.t.drag(x0, y0, x0 + dx, y0 + dy, steps~)
  self.t.draw()
  self.core()
}

///|
/// The lowest `what` (`top`: the highest) tapped and the frames that tap draws, nothing more: what the core says to
/// it comes as the clock goes on (until_moving, Tester::run_for), a motion it sets off seen on its way. The frame after
/// the one that took the tap: where what the tap sets off from the next frame starts (a card let go: decide.mbt
/// ask_dismiss, marked as the tap is taken, going from the frame after).
pub fn Flow::tap_now(self : Flow, what : String, top? : Bool = false) -> Double {
  emit((if top { "tap1 " } else { "tap " }) + what)
  // (as a scripted run's tap waits for what it taps to show: what came for it given first, Flow::until)
  self.until(fn() { self.spots(what).length() > 0 })
  let at = self.spots(what)
  if at.length() == 0 {
    self.fail("nothing to tap: " + what)
    return -1.0
  }
  let (x, y) = if top { at[at.length() - 1] } else { at[0] }
  // (down and up, taken by a frame; then the frame that one left owed, where what the tap sets off starts: at the
  // tap's moment, or a host's run's next two frames)
  self.t.touch(0, x, y)
  self.t.touch(2, x, y)
  self.t.draw()
  self.t.time()
}

///|
/// The display's frame that took the answer to the run's latest call `call` (Replay::given_at: when it was given here,
/// as the tape has it at this pace; taken by the frame after): where what that answer sets off starts. -1 while none
/// is given.
pub fn Flow::answer_taken(self : Flow, call : String) -> Double {
  self.frame_taking(self.r.given_at(call))
}

///|
/// The display's frame that took the latest message in `which` holds for (Replay::given_at_where: a topic's change):
/// where what it sets off starts. -1 while none is given.
pub fn Flow::message_taken(self : Flow, which : (Json) -> Bool) -> Double {
  self.frame_taking(self.r.given_at_where(which))
}


///|
fn Flow::frame_taking(self : Flow, given : Double?) -> Double {
  // (Replay::deliver's taken_at: the display's frame that took it)
  given.unwrap_or(-1.0)
}

///|
/// The clock stepped a frame at a time, what is due given as it comes, until something said to move holds `name`
/// (Tester::moving, Tester::rest_of): when it is at rest. The test fails if nothing more may come first and none does.
pub fn Flow::until_moving(self : Flow, name : String) -> Double {
  // (one the last step that acts began: one of its name moving as it was taken, its coming in not over at a tap, is not
  // it)
  let told = fn() { self.t.moving().iter().any(fn(l) { l.contains(name) && !self.at_step.contains(l) }) }
  while !told() || self.t.rest_of(name) <= self.t.time() {
    if self.t.posted() == 0 && self.r.next_due() is None {
      // (what it waits for came while the run's script was in its next step that waits (until 已保留 after the tap):
      // waiting too, it is in that step with it: taken now, the clock not run to when the run took it, for what comes
      // after it to come at its pace from here, a frame at a time)
      match self.r.next_step() {
        Some(l) if waiting_step(l) => {
          if self.r.step_taken(l) {
            continue
          }
        }
        _ => ()
      }
      self.fail("nothing moves that is " + name)
      return -1.0
    }
    self.t.run_for(frame_ms)
  }
  // (told, not started yet: it starts with the frame after)
  if self.t.rest_of(name) == @double.infinity {
    self.t.draw()
  }
  self.t.rest_of(name)
}

///|
/// `what` (its key or its words, Tester::look_of) going to `to` of its size on a tween of `ms` by `ease`, at rest at
/// `rest` (Tester::rest_of): half way, drawn as the curve has it then (within what a frame moves it); at rest, gone or
/// whole again (what has gone is drawn as nothing).
pub fn Flow::shrinks(
  self : Flow,
  what : String,
  to~ : Double,
  ease~ : @ui.Ease,
  ms~ : Double,
  rest~ : Double,
) -> Unit {
  let start = rest - ms
  self.t.run_for(start + ms / 2.0 - self.t.time())
  let p = (self.t.time() - start) / ms
  let size = fn(q : Double) { to + (1.0 - to) * (1.0 - ease.at(if q > 1.0 { 1.0 } else { q })) }
  let want = size(p)
  // (a frame of the curve either way: where the frame fell)
  let slack = (size(p - frame_ms / ms) - size(p + frame_ms / ms)).abs()
  match self.t.look_of(what) {
    Some((sx, sy, _)) =>
      if (sx - want).abs() > slack || (sy - want).abs() > slack {
        self.fail("\{what} half way drawn at \{sx} × \{sy}, not \{want} (±\{slack})")
      }
    None => self.fail("not drawn half way: " + what)
  }
  self.t.run_for(rest - self.t.time())
  match self.t.look_of(what) {
    Some((sx, sy, _)) if sx != 1.0 || sy != 1.0 =>
      self.fail("\{what} at rest drawn at \{sx} × \{sy}")
    _ => ()
  }
}

///|
/// Files shared in from another app before anything else (macOS: MBUI_SHARE_FILES, the run's files dir's; Android:
/// the first staged in the app's own provider and sent as ACTION_SEND), their bytes the run's (what it sent of each:
/// Replay::sent_bytes), as Tester::share_in gives them.
pub fn Flow::share_files(self : Flow, names : Array[String]) -> Unit raise {
  emit("#before android-stage " + names[0])
  emit(
    "#android-intent -a android.intent.action.SEND -t " + (if names[0].has_suffix(".pdf") { "application/pdf" } else { "image/jpeg" }) +
    " --eu android.intent.extra.STREAM content://{PKG}.shared/" + names[0],
  )
  emit("#env MBUI_SHARE_FILES=" + names.map(fn(n) { "{FILES}/" + n }).join("|"))
  let files = []
  for n in names {
    // (handed to the core whole: composer.add; a run from before, its parts: station.upload.part)
    let handed = match self.r.sent_bytes("composer.add", "name", n) {
      Some(b) => Some(b)
      None => self.r.sent_bytes("station.upload.part", "name", n)
    }
    match handed {
      Some(b) => files.push((n, b))
      None => fail("flow: the trace has none of " + n + "'s bytes (over scripts/trace make's MAX_BYTES?)")
    }
  }
  self.t.share_in("", files~)
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
