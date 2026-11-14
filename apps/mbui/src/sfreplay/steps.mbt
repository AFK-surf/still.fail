// A flow of e2e/flows seen again in a Tester, its steps written as a test's (scripts/e2e-local.sh):
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
  /// the words followed down the screen (Flow::follow; "": none), and where their middle was drawn each frame since
  priv followed : Ref[String]
  priv follow_ys : Array[(Double, Double)]
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
    // (the strict pass again, its run_for's frames at a rate: pace_between)
    10 | 11 => @core.AsRun(1.0)
    _ => @core.AsRun(2.0)
  }
}

///|
/// The strict pass again (its run's pace: its steps and the core's messages each at its own moment, its asks held to
/// the run's), its display's frames at 7 a second and at 120 in the run's frames' place (orders' pace passes): what the
/// app tells the core is to be the same message by message wherever the frames fall.
fn pace_between(seed : UInt) -> Double? {
  match seed {
    10 => Some(1000.0 / 7.0)
    11 => Some(1000.0 / 120.0)
    _ => None
  }
}

///|
/// The run's display's own frames, where its trace keeps them (`{"frame":…}`), for the strict pass: each at its
/// moment here, timed as the steps are: from the run's first step as it was taken again (before it, from the first of
/// the run that happened again here), once (its first step taken as what it waits for is so, not at the run's moment:
/// the run's timeline from there on, Replay::due_at). Each step after falls at its moment on that same timeline; one
/// that does not is said (FRAME-DRIFT), never mended by timing the frames anew from it (the coordinator of the
/// migration, 2026-11-12). The strict pass's frames then fall where the run's did, not on a grid of its own a phase
/// apart from them.
fn frames_as_run(t : @ui.Tester, r : @core.Replay) -> Unit {
  guard r.run_frames().length() > 0 else { return }
  let anchor = match r.first_step_anchor() {
    Some(a) => Some(a)
    None => r.first_happened()
  }
  match anchor {
    Some((at, wall)) if run_framed.val != Some((at, wall)) => {
      run_framed.val = Some((at, wall))
      let now = t.time()
      let times = r.run_frames().map(fn(w) { w - wall + at }).filter(fn(x) { x > now })
      if times.length() > 0 {
        t.set_frame_times(times)
      }
    }
    _ => ()
  }
}

///|
/// The anchor the run's frames were last timed from (frames_as_run), None not yet.
// kept across runs: put back as a flow starts (Flow::start)
let run_framed : Ref[(Double, Double)?] = Ref(None)

///|
/// Whether pass `seed` is the strict one or one of its pace passes (pace_between).
fn strict_pass(seed : UInt) -> Bool {
  seed == 0 || pace_between(seed) is Some(_)
}

///|
/// What the app told the core in the pass that ended last (Flow::end: Replay::outs).
// kept across runs: written as each pass ends
let pass_outs : Ref[Array[String]] = Ref([])

///|
/// What the app told the core in the flow's strict pass (orders): what a pace pass is held to, message by message.
// kept across runs: written as each flow's strict pass ends (orders)
let strict_outs : Ref[Array[String]] = Ref([])

///|
/// Where a pace pass first told the core otherwise than the strict pass ("" not yet): it stops there, its steps after
/// it none of its own (Flow's steps return at once), what comes after only what that set off.
// kept across runs: put back as each pass begins (Flow::start)
let pace_split : Ref[String] = Ref("")

///|
/// How many steps a pace pass has taken (Flow::take_step): where it split, said by the step.
// kept across runs: put back as each pass begins (Flow::start)
let pace_steps : Ref[Int] = Ref(0)

///|
/// Whether the pace pass told the core otherwise than the strict pass so far (the first message apart, which the app
/// said in it and which the strict pass did): "" none; then the pass is split, said once (PACE-SPLIT).
fn Flow::split_seen(self : Flow, at : String) -> Unit {
  if !pace_pass.val || pace_split.val != "" {
    return
  }
  let outs = self.r.outs()
  let strict = strict_outs.val
  let n = outs.length()
  let mut k = 0
  while k < n && k < strict.length() && outs[k] == strict[k] {
    k += 1
  }
  if k < n {
    let theirs = if k < strict.length() { strict[k] } else { "-" }
    pace_split.val = "step \{pace_steps.val} (\{at}): message #\{k}: \{outs[k]} | strict \{theirs}"
    println("PACE-SPLIT \{pass_trace.val}: " + pace_split.val)
  }
}

///|
/// The trace the pass that began last replays (Flow::start).
// kept across runs: written as each pass begins
let pass_trace : Ref[String] = Ref("")

///|
/// Whether the pass that began last is one of orders' pace passes (pace_between), and whether it failed yet: a failure
/// in it said (`PACE-FAIL`), not ended on, while what fails at a rate is counted.
// kept across runs: written as each pass begins
let pace_pass : Ref[Bool] = Ref(false)

///|
// kept across runs: written as each pass begins and as it first fails
let pace_failed : Ref[Bool] = Ref(false)

///|
/// The app over `trace`, drawn by what the run's host gave its frames (the trace's `{"settings":…}`: its window, its
/// scale, the system it is and its settings, @ui.trace_settings), in the pass `seed` names (0: the strict one, as the
/// run had it; else what is due at once in the order drawn from it, at that pass's pace: pace_of). `drop`: asks of the
/// run's its timing made, by words in them (Replay::drop), each with what came for it. `w`, `h`, `platform`: what the
/// test says its run was (the wide flows' 1280 × 800, the Mac's), held to the trace's: one that differs is refused, as
/// is a trace that does not say.
#callsite(autofill(loc))
pub fn Flow::start(
  trace : String,
  seed? : UInt = 0,
  drop? : Array[String] = [],
  w? : Double,
  h? : Double,
  env? : Array[(String, String)] = [],
  platform? : Int,
  loc~ : SourceLoc,
) -> Flow {
  // (the app of the run before let go first, while the core it talks to is that run's: what it says as it goes (a
  // page's drafts dropped) is that run's, never heard by this one, whichever flow ran before it)
  @ui.run_let_go()
  // Legacy scopes outlive a frame's tree. Release the previous run's watches before its core is replaced, so their
  // reset notifications cannot subscribe them into the next recording. Tester::new resets the rest of the app later.
  @sfbase.reset()
  let r = @core.Replay::parse(trace)
  use_recorded_jobs(r)
  // (a run from before the stations' rows: its `stations` the replay's own to keep, the app's asks of them read out of
  // those, source.mbt)
  if !switch_was_on(r, env, "MBUI_STATION_ROWS") {
    r.keep_stations()
  }
  // (asks the run's timing made, with what came for them: each test says which and why)
  for text in drop {
    if r.drop(text) == 0 {
      @halt.saying("flow: nothing in the run holds " + text + " to drop")
    }
  }
  // (the core's pure calls the app has kept answers for are answered here, not asked of the run's core: src/sfreplay
  // source.mbt; the run's asks of them not waited for)
  r.skip_where(fn(name, params) { @sfkept.has(name, params) })
  r.shuffle(seed)
  // (a test's steps written as a scripted run (FLOW_EMIT) over a trace the app may have outgrown: at once, as the steps
  // do not hang on the run's pace, and an older trace's asks have no wall clock to keep it by)
  r.pace(if seed == 0 && emit_path() != "" { @core.AtOnce } else { pace_of(seed) })
  r.attach()
  // (on the screen it was made on, as its host gave it: a phone's window's runs a phone's, Android's, pointed at by a
  // finger; a wider one's the Mac's, by a mouse, and keyboard and mouse's window made narrow (`platform` 0); the live
  // run recording it again on a Mac plays that system too)
  let (w_said, h_said, platform_said) = (w, h, platform)
  let settings = match r.settings() {
    Some(s) => s
    None =>
      @halt.saying(
        "flow: this test's trace has no {\"settings\":…}, what its run's host gave its frames (mbui's @ui.trace_settings): record it again (scripts/rerecord.sh)",
      )
  }
  let (w, h, scale, platform, native, dark) = match @ui.settings_of(settings) {
    Ok(s) => s
    Err(why) => @halt.saying("flow: this test's trace: " + why + " (mbui's @ui.trace_settings): record it again (scripts/rerecord.sh)")
  }
  let said = fn(what : String, by_test : Double?, run : Double) {
    if by_test is Some(v) && v != run {
      @halt.saying("flow: the test says its run's \{what} was \{v}, its trace's was \{run}")
    }
  }
  // (the window's buttons in the app's top row as its host had them from the first frame: never set by the test after)
  let window_inset = match settings {
    Object(m) => m.get("inset") is Some(Number(n, ..)) && n != 0.0
    _ => false
  }
  said("width", w_said, w)
  said("height", h_said, h)
  said("platform", platform_said.map(fn(p) { p.to_double() }), platform.to_double())
  emit_start(seed, w, h, if platform == 2 { env + [("MBUI_PLATFORM", "android")] } else { env })
  // what the core says taken as the app takes it on a device (sfcore.start's listen: through mbui's queue, what changes
  // only signals as it comes)
  @sfcore.listen(@sfapp.core_taking())
  // (the app started with what the run's was: its trace's env, then what the test says of its own; a trace that does
  // not say it is one recorded before it was kept, to record again: never run as if started with nothing)
  if r.env().is_empty() && emit_path() == "" {
    @halt.saying(
      "flow: this test's trace has no {\"env\":…} head, what its run's app was started with (src/stillfail: CORETRACE env): record it again (scripts/rerecord.sh)",
    )
  }
  // (and its host's answers as the run's gave them, where it kept them: a word's bounds as the system splits words)
  // (on the system the run was on, its core told so: above)
  // (what the app asks as it starts, in the Tester's first frame, asked at the Tester's first moment: the run's answers
  // to it due as long after it as they came in the run, its first step too, not as long after the replay's clock began)
  let started_at = 1000.0
  r.clock(fn() { started_at })
  let t = match r.text() {
    Some(text) =>
      @ui.Tester::new(app, w~, h~, scale~, dark~, window_inset~, native~, env=r.env() + env, text~, platform~, tree=@sfapp.app_tree(the_source), time=started_at, loc~)
    None => @ui.Tester::new(app, w~, h~, scale~, dark~, window_inset~, native~, env=r.env() + env, platform~, tree=@sfapp.app_tree(the_source), time=started_at, loc~)
  }
  // (and the rest of what its host gave its first frame: the system's settings, the minutes it was off UTC)
  ignore(t.settings_said(settings.stringify()))
  // (and none of them changed by the test after: a run's host's settings are its trace's)
  t.host_settings_from("the trace's {\"settings\":…}")
  // (a pace pass: its failures said, not ended on; its frames not judged, only what it tells the core: orders)
  pace_pass.val = pace_between(seed) is Some(_)
  // (a pace pass's frames are not the run's: its steps at the run's moments, from one to the next, and no frame drawn
  // past the next ahead of it, Tester::inputs_next; the strict pass's frames are the run's own, mapped with its steps)
  if pace_pass.val {
    r.chain_steps()
  }
  // (the strict pass keeps each input as it worked it out of the screen (where it tapped, how far it wheeled, when
  // what it waited for was so); a pace pass gives the same, at the same moments, and judges nothing of the screen:
  // the same inputs, only the frames between them other)
  if seed == 0 && emit_path() == "" {
    kept_inputs.clear()
    strict_answers.clear()
    strict_steps.clear()
    keeping.val = 1
  } else if pace_pass.val {
    kept_next.clear()
    pace_answers.clear()
    pace_step_next.val = 0
    keeping.val = 2
  } else {
    keeping.val = 0
  }
  step_moment.val = None
  first_taken.val = false
  opening_late.val = 0.0
  first_step_run_at.val = None
  opening_given.val = -@double.infinity
  pace_failed.val = false
  pace_split.val = ""
  pace_steps.val = 0
  @sfkept.asks_kept.val = !pace_pass.val
  // (nor the strict pass's: how what moves goes frame to frame is judged on the pass run through at the default rate,
  // as ever; the strict pass's frames are the run's, its own judgement the moments)
  t.frames_unjudged(pace_pass.val || strict_mode.val)
  // (what it says from here, MOTION lines too, the pace pass's till its PACE-END)
  if pace_pass.val {
    println("PACE-BEGIN \{pass_trace.val} at \{(1000.0 / pace_between(seed).unwrap_or(1000.0)).round()} a second")
  }
  // (which station this machine is, as the run's host said)
  if r.local_station() != "" {
    t.set_app_said("local_station", r.local_station())
  }
  // (the time of day the run's: its first event that has happened here (the app's first ask, made as it started) at
  // the run's moment of it, going on with the frames' clock from there, @ui.wall_ms)
  match r.first_happened() {
    Some((at, wall)) => t.set_wall(wall + (t.time() - at))
    None => ()
  }
  // what the run's host said of its views (a player's state, a video's frames) said to the Tester's in its place
  // (and what it gave its later frames, where that changed: its window, its settings)
  r.host(fn(line) { if !t.settings_said(line) { ignore(t.view_said(line)) } })
  // the run's pace kept on the Tester's clock: when an ask is made again, when a message is given
  r.clock(fn() { t.time() })
  // the run's core answering as it did: what is due is posted as each frame ends, taken by the next (but while a
  // waiting step is given what came for it a message at a time: Flow::until)
  let one_by_one = Ref(false)
  // (the last of the run's frames given to the Tester's display)
  let frames_to = Ref(-@double.infinity)
  let said : Array[String] = []
  let followed = Ref("")
  let follow_ys : Array[(Double, Double)] = []
  // (and when the next is due, a frame drawn then however the clock is run on: what came at a time came at it)
  // (what the run's host said comes before the frame it was said for: given as a frame ends, it is the next one's, by
  // that frame's time, as a host's events before a vsync are that frame's)
  run_framed.val = None
  t.between_frames(fn() {
    if followed.val != "" {
      match t.find(followed.val) {
        Some((_, y)) => follow_ys.push((t.time(), y))
        None => ()
      }
    }
    for m in t.moving() {
      if !said.contains(m) {
        said.push(m)
      }
    }
    if !one_by_one.val {
      r.deliver(now=t.time(), host_by=t.taken_at(), taken_at=t.taken_at(), to=fn(json, bytes) { t.post("core", json, bytes?) }) |> ignore
    }
    if seed == 0 && emit_path() == "" && strict_mode.val {
      frames_as_run(t, r)
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
  if strict_pass(seed) && emit_path() == "" {
    t.set_frame_period(pace_between(seed).unwrap_or(r.frame_period().unwrap_or(run_frame_ms)))
  }
  // what the system lets the app show as the run's host said it (its app's notify.permission): a Tester's own lets it
  match notice_permission_of(trace) {
    Some(state) => t.set_notice_permission(state)
    None => ()
  }
  let f = {
    r,
    t,
    strict: strict_pass(seed),
    one_by_one,
    said,
    at_step: [],
    followed,
    follow_ys,
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
  // (the strict pass: the display's frames only as the clock passes them, from the start, till all the run had before
  // its first step has happened again (its asks made, what came for them given at its moment); the first step's
  // moment is the run's after the last of it (Replay::due_at), not known before it: the step itself comes to it)
  if keeping.val == 1 {
    self.t.frames_by_clock(true)
    let began = self.t.time()
    while true {
      self.r.deliver(now=self.t.time(), host_by=self.t.taken_at(), taken_at=self.t.taken_at(), to=fn(json, bytes) { self.t.post("core", json, bytes?) }) |> ignore
      let first = self.r.next_step_at()
      self.t.inputs_next(first)
      let due = self.r.next_due().unwrap_or(@double.infinity)
      // (or, nothing more to come for what was asked, the first step's moment come with the run's asks before it not
      // all made again: it is taken then all the same, and what it says of the screen is held to that moment)
      let now = self.t.time()
      if (due == @double.infinity &&
        (!self.r.asks_before_step() ||
        (now >= first - 1.0e-6 && now >= self.r.asks_before_step_due() - 1.0e-6))) ||
        now - began > until_most_ms {
        let given = self.r.last_given()
        opening_given.val = if given > -@double.infinity { given } else { began }
        break
      }
      self.t.come_to(if due > now && due < now + frame_ms { due } else { now + frame_ms })
    }
    emit_answered(self.r.take_asked())
    return
  }
  // (a pace pass alike: up to the strict pass's first step, the display's frames none past it, the input given at its
  // own moment as a device's host gives it; what is due after comes as the steps go)
  let first = if keeping.val == 2 && strict_steps.length() > 0 {
    strict_steps[0].1
  } else {
    @double.infinity
  }
  if first < @double.infinity {
    self.t.inputs_next(first)
    // (its frames only as the clock passes them: what comes waits for the next, none drawn ahead of the clock)
    self.t.frames_by_clock(true)
  }
  while true {
    self.r.deliver(now=self.t.time(), host_by=self.t.taken_at(), taken_at=self.t.taken_at(), to=fn(json, bytes) { self.t.post("core", json, bytes?) }) |> ignore
    let posted = self.t.posted()
    if posted > 0 {
      self.t.draw()
      // (the host's next frame after the first step's moment: what came taken by that frame, after the step)
      if self.t.posted() >= posted && first < @double.infinity {
        break
      }
      continue
    }
    match self.r.next_due() {
      Some(at) if at < first => {
        let step = first - self.t.time()
        if step <= 0.0 {
          break
        }
        self.t.come_to(self.t.time() + (if step < frame_ms { step } else { frame_ms }))
      }
      Some(at) if at < @double.infinity && first == @double.infinity => self.t.run_for(frame_ms)
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
  let rest = trace.exact_view(start=i + key.length())
  guard rest.find("\"") is Some(j) else { return None }
  Some(rest.exact_view(end=j).to_owned())
}

///|
/// The step `line` (as the script says it) taken when the run took it, at this pace: the clock on to that moment, what
/// is due meanwhile given (the run's script typed, then waited for an upload, then tapped: as long here). A step the
/// trace does not hold, or one whose time waits for an ask not made again, is taken now.
fn Flow::take_step(self : Flow, line : String) -> Unit {
  // (a pace pass: what it told the core so far, held to the strict pass's before this step is taken)
  if pace_pass.val {
    self.split_seen(line)
    pace_steps.val += 1
    if pace_split.val != "" {
      return
    }
  }
  // (a pace pass takes each step at the moment the strict pass took it: the same inputs at the same moments, only the
  // frames between them other; not by the run's events as they happened again here, which come with its frames)
  let at_strict = if keeping.val == 2 {
    let i = pace_step_next.val
    if i < strict_steps.length() && strict_steps[i].0 == line {
      pace_step_next.val = i + 1
      Some(strict_steps[i].1)
    } else {
      println("PACE-STEP \{pass_trace.val}: step \{i} \{line} is not the strict pass's (\{if i < strict_steps.length() { strict_steps[i].0 } else { "none" }})")
      None
    }
  } else {
    None
  }
  match (match at_strict { Some(t) => Some(t); None => self.r.step_at(line) }) {
    Some(at) => {
      let now = self.t.time()
      // (the strict pass: a step's moment before the step before it was taken is the replay's own fault (its timeline
      // left on a line the run had before that step), never the app's lateness: said, and stopped)
      if strict_on() && at > -@double.infinity {
        // (the run's step before it as taken here: one of its script's that says its moment, not a line of the test's
        // own (`#env …`, `#before …`) the run kept none of)
        match self.r.step_anchor() {
          Some((taken, _)) if at < taken - 1.0e-6 =>
            @halt.saying(
              "replay \{pass_trace.val}: the run's moment for `\{line}` (\{at} ms) comes before its step before it was taken (\{taken} ms): the replay's timeline, not the app (Replay::due_at)",
            )
          _ => ()
        }
      }
      if at_strict is Some(_) && now > at + 0.001 {
        println("STEP-LATE \{pass_trace.val}: \{line} at \{now}, strict \{at}")
      }
      if at > now && at < @double.infinity {
        // (the strict pass and its pace passes: the clock on to the step's moment between the host's frames, none
        // drawn past it)
        if timed_on() {
          self.t.come_to(at)
        } else {
          self.t.run_for(at - now)
        }
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
      // (the strict pass: the run's frames timed from its first step taken, once; each step after it on that timeline,
      // or said)
      if strict_on() && emit_path() == "" {
        frames_as_run(self.t, self.r)
        match (self.r.first_step_anchor(), self.r.step_anchor()) {
          (Some((a0, w0)), Some((a, w))) if (a - (a0 + (w - w0))).abs() > frame_drift_most && self.r.run_frames().length() > 0 =>
            println("FRAME-DRIFT \{pass_trace.val}: \{line} taken at \{a}, the run's frames' timeline has it at \{a0 + (w - w0)}")
          _ => ()
        }
      }
      // (and what it sets off drawn on the host's frames up to the next step's moment, none past it: the next input
      // comes at its own moment at any frame rate, Tester::inputs_next)
      if keeping.val == 1 {
        // (the first step's moment in the run, on this clock: how much later its first screen let it be taken,
        // Flow::first_screen)
        if strict_steps.is_empty() {
          first_step_run_at.val = if at > -@double.infinity && at < @double.infinity { Some(at) } else { None }
        }
        strict_steps.push((line, self.t.time()))
        step_moment.val = if at < @double.infinity { Some(self.t.time()) } else { None }
        if strict_steps.length() > 1 {
          first_taken.val = true
        }
      }
      if timed_on() {
        // (a step at its moment (the run's, the strict pass's): no frame past that moment till the next step, the
        // input it gives given at it, not after a frame of the host's that falls later; what it sets off drawn on the
        // way to the next)
        self.t.inputs_next(
          if at_strict is Some(_) {
            let i = pace_step_next.val
            if i < strict_steps.length() { strict_steps[i].1 } else { @double.infinity }
          } else {
            self.r.next_step_at()
          },
        )
      }
    }
    None =>
      if keeping.val == 1 {
        strict_steps.push((line, self.t.time()))
        step_moment.val = None
        if strict_steps.length() > 1 {
          first_taken.val = true
        }
      }
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
  if pace_split.val != "" {
    return
  }
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
    let posted = self.t.posted()
    if posted > 0 {
      self.t.draw()
      // (the host's next frame after the next step's moment: what came taken by a frame after that input, as a host's
      // would be, Tester::inputs_next)
      if self.t.posted() >= posted {
        break
      }
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
  if pace_split.val != "" {
    return
  }
  if self.judges() && !so {
    self.fail(why)
  }
}

///|
/// As check, `so` asked only where it is judged: what it reads of the screen may not be there in a pass that is not
/// (a pace pass split, its steps after taken as nothing: the list `Tester::at_end` reads never opened).
pub fn Flow::check_by(self : Flow, so : () -> Bool, why : String) -> Unit {
  if pace_split.val != "" {
    return
  }
  if self.judges() && !so() {
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
  // (one traced to its line, said as it is known: noted, the flow going on to its next step, its checks after it judged
  // as ever: judged_traced_known)
  if !pace_pass.val {
    let said = why + " (at \{self.t.time()} ms)"
    let known = judged_traced_known.get(pass_trace.val).unwrap_or([])
    if known.iter().any(fn(k) { k.0 == said }) {
      if !traced_said.contains(said) {
        traced_said.push(said)
      }
      println("TRACED \{pass_trace.val}: " + said)
      return
    }
  }
  if pace_pass.val {
    if !pace_failed.val {
      pace_failed.val = true
      println("PACE-FAIL \{pass_trace.val}: " + why + " (at \{self.t.time()} ms)")
    }
    return
  }
  // (the strict pass: its first failure kept, held to strict_known by orders, and the pass stopped there, its steps
  // after it taken as none; the flow's own checks are the lenient pass's, which runs it whole after it)
  if strict_on() {
    if strict_failures.is_empty() {
      strict_failures.push(why)
      println("STRICT-FAIL \{pass_trace.val}: " + why + " (at \{self.t.time()} ms)")
    }
    pace_split.val = "the strict pass stopped"
    return
  }
  let s = "flow: " + why + " (at \{self.t.time()} ms, \{pass})\n" + talk + "\n" + self.t.dump()
  println(s)
  // (writing the steps as a scripted run, FLOW_EMIT, over a trace the app has outgrown: said, and the steps after it
  // written all the same, for the run to record the trace they need)
  if script.val is Some(_) {
    return
  }
  @halt.saying(s)
}

///|
/// What the run's script waited through at a step that waits (`until`, `gone`: what came after it began, Replay::
/// step_taken), given a message at a time, each with its frame, until `so` holds: as the run's script saw it come,
/// not past it (a player's place told after the script saw 0:02 is not given before it looks).
#callsite(autofill(loc))
pub fn Flow::until(self : Flow, so : () -> Bool, loc~ : SourceLoc) -> Unit {
  if pace_split.val != "" {
    return
  }
  step_moment.val = None
  self.until_at(loc.to_string(), so)
}

///|
/// Flow::until, its inputs kept by `site` (the test's line that asked: Kept).
fn Flow::until_at(self : Flow, site : String, so : () -> Bool) -> Unit {
  // (a pace pass waits to when the strict pass found it so, what comes meanwhile given: not looking at its screen)
  if keeping.val == 2 {
    match self.kept(site) {
      Some(Waited(at)) => self.wait_to(at)
      Some(k) => self.fail("the strict pass kept \{Repr(k)} here, not a wait")
      None => ()
    }
    return
  }
  self.one_by_one.val = true
  let began = self.t.time()
  // (the strict pass: the step falls at the run's moment, never where what it waits for came to be so; the wait is
  // an assertion of it then: at the moment of its own line as the run took it (Flow::take_step came to it), or, a wait
  // the run's script did not write, by the run's next step. Not so then, it fails, saying how much later it came;
  // looked for on to there only to say that)
  // Before the run's first step is taken the strict pass waits for what it waits for, as before: those moments are
  // the app's that recorded the run (its traces older than what the app now reads first, #5589, #5618), and what it
  // waited is measured (first_screen_known) till they are recorded again (the coordinator of the migration,
  // 2026-11-12: B). From the step on, the run's timeline from there, later by as much (opening_late).
  let opening = strict_on() && !first_taken.val
  let first_own = opening && strict_steps.length() == 1 && step_moment.val is Some(_)
  let by = if strict_on() && !opening {
    match step_moment.val {
      Some(t) => t
      None => self.r.next_step_at()
    }
  } else {
    @double.infinity
  }
  let run_at = step_moment.val
  step_moment.val = None
  let mut late = false
  // (the strict pass: what comes meanwhile told at its own moment between the host's frames, all that came by then at
  // once, as a device's host tells it (Tester::come_to), not a message a frame: one at a time, each with a frame of its
  // own, put a frame's wait on every message after the first that came together, and the screen it waits for later by
  // as many frames)
  if keeping.val == 1 {
    self.one_by_one.val = false
  }
  while !so() {
    // (bounded on the run's clock: what it waits for never coming, said, not run on)
    if self.t.time() - began > until_most_ms {
      self.fail(
        (if late { "not so at \{by} ms, the run's moment for it, nor " } else { "not so " }) +
        "after \{until_most_ms.to_int()} ms; moving: \{self.t.moving().join("; ")}",
      )
      late = false
      break
    }
    if self.t.time() >= by - 1.0e-6 {
      late = true
    }
    if keeping.val == 1 {
      let now = self.t.time()
      let due = self.r.next_due().unwrap_or(@double.infinity)
      self.t.come_to(if due > now && due < now + frame_ms { due } else { now + frame_ms })
      continue
    }
    let n = self.r.deliver(at_most=1, now=self.t.time(), host_by=self.t.taken_at(), taken_at=self.t.taken_at(), to=fn(json, bytes) { self.t.post("core", json, bytes?) })
    if n > 0 || self.t.posted() > 0 {
      self.t.draw()
      // (what the next frame takes, where that frame falls after the next step's moment (Tester::inputs_next): the
      // test waits on, the clock on to it below)
      if self.t.posted() == 0 {
        continue
      }
    }
    // (nothing due yet at the run's pace, or nothing more to come: the clock on a frame at a time, as the run's step
    // waited on, until what it waits for is so (a page pushed when its answer came, sliding in; a line a timer brings)
    // or the most it waits)
    self.t.run_for(frame_ms)
  }
  if late {
    let at = self.t.time()
    let said = "\{site}: not so at \{by} ms, the run's moment for it (its timeline \{opening_late.val} ms later from its first step): so at \{at} ms, \{at - by} ms later"
    // (a trace without its display's frames: the strict pass's on a grid of its own, a phase apart from the run's, so
    // a screen a few frames after its cause comes up to a frame later or sooner than the run's did: measured, not
    // judged, till the trace is recorded again with them (frames_unrecorded_known; the coordinator of the migration,
    // 2026-11-12))
    if self.r.run_frames().is_empty() {
      println("LATE-UNFRAMED \{pass_trace.val}: " + said)
    } else {
      self.fail(said)
    }
  }
  if first_own {
    self.first_screen(
      match first_step_run_at.val {
        Some(a) => a
        None => run_at.unwrap_or(self.t.time())
      },
    )
  }
  self.one_by_one.val = false
  if keeping.val == 1 {
    kept_push(site, Waited(self.t.time()))
  }
}

///|
/// The clock on to `at` (a pace pass's wait, Flow::until), what comes meanwhile given a message at a time with its
/// frame, as the strict pass's wait gave it.
fn Flow::wait_to(self : Flow, at : Double) -> Unit {
  // (a pass of the run's pace: as the strict pass's wait, what comes told at its own moment, Tester::come_to)
  if timed_on() {
    while self.t.time() < at - 1.0e-9 {
      let now = self.t.time()
      let due = self.r.next_due().unwrap_or(@double.infinity)
      let next = if due > now && due < now + frame_ms { due } else { now + frame_ms }
      self.t.come_to(if next < at { next } else { at })
    }
    return
  }
  self.one_by_one.val = true
  while self.t.time() < at - 1.0e-9 {
    let n = self.r.deliver(at_most=1, now=self.t.time(), host_by=self.t.taken_at(), taken_at=self.t.taken_at(), to=fn(json, bytes) { self.t.post("core", json, bytes?) })
    if n > 0 || self.t.posted() > 0 {
      self.t.draw()
      if self.t.posted() == 0 {
        continue
      }
    }
    let step = at - self.t.time()
    if timed_on() {
      self.t.come_to(self.t.time() + (if step < frame_ms { step } else { frame_ms }))
    } else {
      self.t.run_for(if step < frame_ms { step } else { frame_ms })
    }
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
#callsite(autofill(loc))
pub fn Flow::see(self : Flow, what : String, loc~ : SourceLoc) -> Unit {
  if pace_split.val != "" {
    return
  }
  let site = loc.to_string()
  emit("until " + what)
  self.until_at(site, fn() { self.spots(what).length() > 0 })
  if self.judges() && self.spots(what).length() == 0 {
    self.fail("not on screen: " + what)
  }
}

///|
/// `n` or more of `what` on screen now.
#callsite(autofill(loc))
pub fn Flow::see_n(self : Flow, n : Int, what : String, loc~ : SourceLoc) -> Unit {
  if pace_split.val != "" {
    return
  }
  let site = loc.to_string()
  emit("untiln \{n} " + what)
  self.until_at(site, fn() { self.spots(what).length() >= n })
  let k = self.spots(what).length()
  if self.judges() && k < n {
    self.fail("\{k} of \{what} on screen, not \{n}")
  }
}

///|
/// `what` is not on screen now.
#callsite(autofill(loc))
pub fn Flow::gone(self : Flow, what : String, loc~ : SourceLoc) -> Unit {
  if pace_split.val != "" {
    return
  }
  let site = loc.to_string()
  emit("gone " + what)
  self.until_at(site, fn() { self.spots(what).length() == 0 })
  if self.judges() && self.spots(what).length() > 0 {
    self.fail("still on screen: " + what)
  }
}

///|
/// The focused field's words contain `words` (`""`: it is empty).
pub fn Flow::field(self : Flow, words : String) -> Unit {
  if pace_split.val != "" {
    return
  }
  emit(if words == "" { "empty" } else { "field " + words.replace_all(old="\n", new="\\n") })
  let now = self.t.field_words()
  if self.judges() && ((words == "" && now != "") || !now.contains(words)) {
    self.fail("the field holds \{now.escape()}, not \{words.escape()}")
  }
}

///|
/// A visible field holds words even when it has lost focus, as for a restored draft.
pub fn Flow::field_visible(self : Flow, words : String) -> Unit {
  if pace_split.val != "" {
    return
  }
  emit("field " + words.replace_all(old="\n", new="\\n"))
  if self.judges() && !self.t.all(@ui.Role::TextField).iter().any(fn(field) { field.value.contains(words) }) {
    self.fail("no visible field holds \{words.escape()}")
  }
}

///|
/// The lowest `what` on screen (`top`: the highest) tapped, and what the core answers to it given.
#callsite(autofill(loc))
pub fn Flow::tap(self : Flow, what : String, top? : Bool = false, loc~ : SourceLoc) -> Unit {
  if pace_split.val != "" {
    return
  }
  let site = loc.to_string()
  emit((if top { "tap1 " } else { "tap " }) + what)
  // Messages posted as the last frame ended are taken in the next frame. Show them before locating the target, so a
  // response that reorders the rows cannot move it between choosing its coordinates and taking the tap.
  self.core()
  // (as a scripted run's tap waits for what it taps to show, where a finger reaches it, not under a sheet or a scrim:
  // what came for it given first, Flow::until)
  self.until_at(site, fn() { self.reach_spots(what).length() > 0 })
  let p = self.kept_point(site, fn() {
    let at = self.reach_spots(what)
    if at.length() == 0 {
      self.fail("nothing to tap: " + what)
      return None
    }
    Some(if top { at[at.length() - 1] } else { at[0] })
  })
  guard p is Some((x, y)) else { return }

  self.t.tap(x, y)
  self.input_framed()
  self.core()
}

///|
/// The strict pass and its pace passes: the host's frame after an input given at its moment drawn, as a device draws
/// the frame that takes it, where that falls before the run's next step (an old view takes a press in its frame: what
/// the test looks at after the tap is that frame's, not the one before it).
fn Flow::input_framed(self : Flow) -> Unit {
  if timed_on() {
    let next = self.t.next_frame_time()
    if next <= self.r.next_step_at() + 1.0e-6 {
      self.t.come_to(next)
    }
  }
}

///|
/// A tap at (x, y) (negative: from the right, the bottom).
pub fn Flow::tap_at(self : Flow, x : Double, y : Double) -> Unit {
  if pace_split.val != "" {
    return
  }
  emit("tapxy \{x.to_int()} \{y.to_int()}")
  let (w, h) = self.t.size()
  self.t.tap(if x < 0.0 { w + x } else { x }, if y < 0.0 { h + y } else { y })
  self.input_framed()
  self.core()
}

///|
/// The lowest `what` pressed for `ms` (a declared length: a long press's), then let go.
#callsite(autofill(loc))
pub fn Flow::hold(self : Flow, what : String, ms : Double, loc~ : SourceLoc) -> Unit {
  if pace_split.val != "" {
    return
  }
  let site = loc.to_string()
  // (a host's long press is held past its threshold: as long again, not to the frame)
  emit("hold \{(ms * 2.0).to_int()} " + what)
  // (as a scripted run's tap waits for what it taps to show: what came for it given first, Flow::until)
  self.until_at(site, fn() { self.spots(what).length() > 0 })
  let p = self.kept_point(site, fn() {
    let at = self.spots(what)
    if at.length() == 0 {
      self.fail("nothing to hold: " + what)
      return None
    }
    Some(at[0])
  })
  guard p is Some((x, y)) else { return }
  // (held as the run's host held it, past the threshold: not released on its very moment)
  self.t.press_at(x, y)
  self.t.run_for(ms * 2.0)
  self.t.release(x, y)
  self.input_framed()
  self.t.draw()
  self.core()
}

///|
/// Words committed by the input method.
pub fn Flow::type_text(self : Flow, s : String) -> Unit {
  if pace_split.val != "" {
    return
  }
  emit("type " + s)
  self.t.type_text(s)
  self.input_framed()
  self.t.draw()
  self.core()
}

///|
/// Words composed by the input method, not committed yet.
pub fn Flow::compose(self : Flow, s : String) -> Unit {
  if pace_split.val != "" {
    return
  }
  emit("mark " + s)
  self.t.compose(s)
  self.input_framed()
  self.t.draw()
  self.core()
}

///|
/// `s` on the clipboard, then the system's paste.
pub fn Flow::paste(self : Flow, s : String) -> Unit {
  if pace_split.val != "" {
    return
  }
  emit("paste " + s)
  self.t.paste(s)
  self.input_framed()
  self.core()
}

///|
/// The run's `n`-th answer to a call `call` (counted from its start) given: a scripted run's `answered CALL`, what a
/// step waits for when what it waits on is what the app asked of the core and nothing on screen says it (a site view's
/// page loaded, its requests through the core answered).
#callsite(autofill(loc))
pub fn Flow::answered(self : Flow, call : String, n : Int, loc~ : SourceLoc) -> Unit {
  if pace_split.val != "" {
    return
  }
  let site = loc.to_string()
  // (what was asked before, written as the steps would have; this call's own counted by the n written here, not
  // written again by the next step: a scripted run waits for the n-th, not for more)
  emit_answered(self.r.take_asked().filter(fn(c) { c != call }))
  emit_answered_to(call, n)
  // (a pace pass neither waits on it nor stops at it: when the app asked it and when it was answered is said at the
  // flow's end, beside the strict pass's, and that it was answered as often judged there; the inputs after it go on at
  // the run's moments, Flow::end)
  if keeping.val == 2 {
    pace_answers.push((site, call, n))
    return
  }
  step_moment.val = None
  self.until_at(site, fn() { self.r.answers_given(call) >= n })
  if keeping.val == 1 {
    strict_answers[site + " " + call + " \{n}"] = self.r.nth_call_at(call, n)
    // (and the host's frame after it, as a scripted run's `answered` waits for one drawn after the frame that saw it
    // (drive.mbt): what the answer sets off in the frame that takes it (a link handed to the system's browser) done
    // there, given at its moment between frames as it now is, not taken with a frame of its own; none past the run's
    // next step)
    self.input_framed()
  }
  emit_answered(self.r.take_asked().filter(fn(c) { c != call }))
  if self.r.answers_given(call) < n {
    self.fail("\{call} answered \{self.r.answers_given(call)} times, not \{n}")
  }
}

///|
/// `s` again and again to `n` characters, pasted (as a flow's `pasten N TEXT`: a paste too long to write out).
pub fn Flow::paste_n(self : Flow, n : Int, s : String) -> Unit {
  if pace_split.val != "" {
    return
  }
  emit("pasten \{n} " + s)
  let words = StringBuilder()
  let chars = s.to_array()
  for i in 0..<n {
    words.write_char(chars[i % chars.length()])
  }
  self.t.paste(words.to_string())
  self.input_framed()
  self.core()
}

///|
/// A key by name, with what is held before it (as a flow's `key`: esc, enter, cmd+k, shift+enter).
pub fn Flow::key(self : Flow, name : String) -> Unit {
  if pace_split.val != "" {
    return
  }
  emit("key " + name)
  if !self.t.key_named(name) {
    self.fail("no such key: " + name)
  }
  self.core()
}

///|
pub fn Flow::enter(self : Flow) -> Unit {
  if pace_split.val != "" {
    return
  }
  emit("enter")
  self.t.enter()
  self.input_framed()
  self.core()
}

///|
pub fn Flow::back(self : Flow) -> Unit {
  if pace_split.val != "" {
    return
  }
  emit("back")
  self.t.back()
  self.input_framed()
  self.core()
}

///|
/// `ms` on the frames' clock (a declared length: a motion's, a timer's), what the core has meanwhile given.
pub fn Flow::run_for(self : Flow, ms : Double) -> Unit {
  if pace_split.val != "" {
    return
  }
  emit_wait(ms)
  // (a pace pass: as long on the clock, the host's frames on the way, none past its end ahead of the next input)
  if keeping.val == 2 {
    self.t.come_to(self.t.time() + ms)
  } else {
    self.t.run_for(ms)
  }
  self.core()
}

///|
/// The flow's end: the app idle; strict, all the run's conversation given, every ask of the run's made again as it was
/// (but `unmade`, the run's asks this one does not make, each said why at the test), nothing else asked; another
/// timing, all it asked answered. The screen
/// as it ends, in a number (screen_sum). The app's core the engine again.
pub fn Flow::end(self : Flow, unmade? : Array[String] = []) -> String {
  // (a pace pass split before its end: stopped there, what came after it not looked at; its line said, PACE-SPLIT)
  if pace_pass.val {
    self.split_seen("the end")
  }
  if (pace_pass.val || strict_on()) && pace_split.val != "" {
    pass_outs.val = self.r.outs()
    println("PACE-END \{pass_trace.val}")
    @core.Replay::detach()
    emit_end()
    step_hook.val = None
    self.t.frames_by_clock(false)
    @sfkept.asks_kept.val = true
    return ""
  }
  // (no input after the test's last: what is left drawn on, whatever of the run's steps it did not take)
  self.t.inputs_next(@double.infinity)
  self.t.frames_by_clock(false)
  self.core()
  // (the rest of the run's conversation as it came, the clock on to each; what came after the test's last step, that
  // it did not wait for (an agent's turn ending after the run's last step, and in another timing later still), told
  // motions of its own: each run to the end it says, Tester::rest_of; and again while what those motions' frames asked
  // is answered, a page gone at its slide's end telling the core where it was)
  let mut rounds = 0
  let wakes : Map[String, Int] = Map([])
  while true {
    rounds += 1
    // (what never stops asking: said, not hidden behind the idle check)
    if rounds > end_rounds {
      self.fail(
        "the end still not quiet after \{end_rounds} rounds: \{self.r.left()} messages in left, the next due at \{Repr(self.r.next_due())}, \{self.t.posted()} posted, moving: \{self.t.moving().join("; ")}",
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
      let before = self.t.time()
      self.t.run_for(self.t.rest_of("") - before)
      // run_for treats a rounding-sized difference as the same frame. If the motion's end is just beyond that
      // frame, show the next one so the motion is actually sampled at rest instead of waiting forever.
      if self.t.time() == before {
        self.t.frame()
      }
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
  // (the strict pass: each of the run's unsubscriptions made after messages the run had after it came, said, not
  // held to anything: the replay gives those without waiting for it, Replay::ready)
  if strict_on() {
    for u in r.late_unsubs() {
      println("LATE-UNSUB \{pass_trace.val}: \{u.0} after \{u.1} messages the run had after it, \{u.2} ms after the first")
    }
  }
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
    match strict_diverged_said(pass_trace.val, r.diverged_at()) {
      Some(w) => why.push(w)
      None => ()
    }
    if r.fuzzy().length() > 0 {
      why.push("asked with other params: " + r.fuzzy().join(", "))
    }
    let left = r.unmade().filter(fn(u) { !unmade.iter().any(fn(k) { u.contains(k) }) })
    if left.length() > 0 {
      why.push("did not ask what the run did: " + left.join(", "))
    }
  }
  // (what it told the core, kept for orders' pace passes)
  pass_outs.val = self.r.outs()
  // (a pace pass's `answered` steps: when its app asked each and when it was answered, beside the strict pass's, a
  // call asked at another moment said (ASKED-LATE, counted per flow); answered as often as the test says, judged here)
  if pace_pass.val {
    for a in pace_answers {
      let (site, call, n) = a
      let (asked, given) = self.r.nth_call_at(call, n)
      let (s_asked, s_given) = strict_answers.get(site + " " + call + " \{n}").unwrap_or((None, None))
      let at = fn(t : Double?) { match t { Some(t) => t.to_string(); None => "-" } }
      println("ANSWERED \{pass_trace.val}: \{call} #\{n} at \{site}: asked \{at(asked)} answered \{at(given)} (strict \{at(s_asked)}, \{at(s_given)})")
      match (asked, s_asked) {
        (Some(t), Some(s)) if t != s => println("ASKED-LATE \{pass_trace.val}: \{call} at \{t} (\{t - s}), strict \{s}, at \{site}")
        (None, Some(s)) => println("ASKED-LATE \{pass_trace.val}: \{call} never asked, strict \{s}, at \{site}")
        _ => ()
      }
      if self.r.answers_given(call) < n {
        why.push("\{call} answered \{self.r.answers_given(call)} times by the flow's end, not \{n} (\{site})")
      }
    }
    // (and all the run's talk said, none of it otherwise: what is left of the strict pass's not said is a split too)
    self.split_seen("the end")
    if pace_split.val == "" && self.r.outs().length() != strict_outs.val.length() {
      let k = self.r.outs().length()
      pace_split.val = "step \{pace_steps.val} (the end): message #\{k}: - | strict \{if k < strict_outs.val.length() { strict_outs.val[k] } else { "-" }}"
      println("PACE-SPLIT \{pass_trace.val}: " + pace_split.val)
    }
    println("PACE-END \{pass_trace.val}")
  }
  let sum = screen_sum(self.t)
  @core.Replay::detach()
  // (what the app asked as the flow ended (a page gone at its slide's end, its player's place told): the script
  // written waits for its answers too, so the run keeps them)
  emit_answered(self.r.take_asked())
  emit_end()
  step_hook.val = None
  @sfkept.asks_kept.val = true
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
  // the strict pass first: the run's steps at the run's moments on its frames, each wait an assertion of its moment
  // (strict_on); its first failure held to strict_known, the pass stopped there. Then the flow run through at the
  // default rate, its waits waited for: each of its own checks on it, as ever, and the passes after it held to it (the
  // coordinator of the migration, 2026-11-12: a new measure in with its baseline, which only falls; no check of the
  // flow's lost for it; what comes given at its moment in every pass, none by the frame)
  strict_failures.clear()
  traced_said.clear()
  strict_mode.val = true
  flow(0) |> ignore
  strict_mode.val = false
  let failed = strict_failures.copy()
  match (failed.get(0), strict_known.get(pass_trace.val)) {
    (Some(said), None) =>
      fail("flow \{pass_trace.val}: its strict pass fails, not known (strict_known, pace_known.mbt): " + said)
    (Some(said), Some((known, _))) if said != known =>
      fail("flow \{pass_trace.val}: its strict pass fails otherwise than strict_known says (pace_known.mbt): " + said + " (known: " + known + ")")
    (None, Some(_)) =>
      fail("flow \{pass_trace.val}: its strict pass fails no more: take it out of strict_known (pace_known.mbt)")
    _ => ()
  }
  let first = flow(0)
  for k in judged_traced_known.get(pass_trace.val).unwrap_or([]) {
    if !traced_said.contains(k.0) {
      fail("flow \{pass_trace.val}: no pass says what judged_traced_known has: take it out (pace_known.mbt): " + k.0)
    }
  }
  let strict = pass_outs.val
  strict_outs.val = strict
  for seed in seeds {
    let again = flow(seed)
    if again != first {
      let s = "flow: in the pass \{seed} (\{Repr(pace_of(seed))}) the screen ends otherwise (\{again}, not \{first})"
      @halt.saying(s)
    }
  }
  // what the app tells the core the same however the frames fall: the strict pass again with run_for's frames at 7
  // a second and at 120, each held to the strict pass message by message and stopped where it first tells it
  // otherwise (PACE-SPLIT); which flows split at which rate is known (pace_splits_known) and only falls
  let split_at : Array[Int] = []
  let said : Array[String] = []
  for p in [(10U, 7), (11U, 120)] {
    let (seed, rate) = p
    flow(seed) |> ignore
    if pace_split.val != "" {
      split_at.push(rate)
      said.push("at \{rate} a second " + pace_split.val)
    } else {
      said.push("at \{rate} a second the same (\{strict.length()})")
    }
  }
  println("PACE \{pass_trace.val}: " + said.join(" || "))
  let known = pace_splits_known.get(pass_trace.val).unwrap_or([]) +
    pace_splits_untraced.get(pass_trace.val).unwrap_or([])
  let unknown = split_at.filter(fn(r) { !known.contains(r) })
  let healed = known.filter(fn(r) { !split_at.contains(r) })
  if unknown.length() > 0 {
    fail(
      "flow \{pass_trace.val}: its pace pass splits from the strict pass at \{Repr(unknown)} a second, not known (pace_known.mbt): " +
      said.join(" || "),
    )
  }
  if healed.length() > 0 {
    fail(
      "flow \{pass_trace.val}: its pace pass at \{Repr(healed)} a second no longer splits: take it out of pace_splits_known (pace_known.mbt)",
    )
  }
}

///|
/// The focused field emptied (all of it chosen, then deleted), as a flow's `clear`.
pub fn Flow::clear(self : Flow) -> Unit {
  if pace_split.val != "" {
    return
  }
  emit("clear")
  self.t.clear()
  self.input_framed()
  self.core()
}

///|
/// On the frames' clock to `end`, a motion's own end as it says it (`@kit.sheet_rest`, `@ui.nav_rest`,
/// `@sf.presented_rest`, `@sfapp.bar_rest`: asked, not its answer, so the strict pass can ask again at the run's next
/// step, Flow::run_to_at), or none where the clock is past it already (the run's own waiting took it there: each says
/// its end as it was once it is over, whichever frames were drawn): the test fails if it has not started yet (+inf:
/// draw first) or nothing of it ever moved (-1).
#callsite(autofill(loc))
pub fn Flow::run_to(self : Flow, end : () -> Double, loc~ : SourceLoc) -> Unit {
  if pace_split.val != "" {
    return
  }
  self.run_to_at(loc.to_string(), end)
}

///|
/// Flow::run_to, kept by `site` (Kept): a pace pass runs to where the strict pass ran, the moment it came to.
fn Flow::run_to_at(self : Flow, site : String, end_of : () -> Double) -> Unit {
  if keeping.val == 2 {
    match self.kept(site) {
      Some(Waited(at)) => self.wait_to(at)
      Some(k) => self.fail("the strict pass kept \{Repr(k)} here, not where it ran to")
      None => ()
    }
    self.core()
    return
  }
  let mut end = end_of()
  // (the strict pass: to the run's moment, not the motion's: what an input just given at its moment sets off is not
  // taken till the host's next frame (none drawn ahead of the clock), so its end may not be said yet; the clock to the
  // run's next step, and the motion's end asked again there. Either way it is at rest by then, or the test fails,
  // saying by how much)
  if strict_on() && first_taken.val {
    let by = self.r.next_step_at()
    if (end < 0.0 || end > 1.0e300) && by < @double.infinity && by > self.t.time() {
      self.t.come_to(by)
      end = end_of()
    }
    if end >= 0.0 && end <= 1.0e300 && by < @double.infinity && end > by + 1.0e-6 {
      self.fail(
        "its motion at rest at \{end} ms, \{end - by} ms after the run's next step (\{by} ms; its timeline \{opening_late.val} ms later from its first step); said since the last step that acted: \{self.said.join(" | ")}",
      )
    }
  }
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
  if keeping.val == 1 {
    kept_push(site, Waited(self.t.time()))
  }
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
/// motion so named was said since the last step that acted and is at rest now, that is where the test would have run it to;
/// one over before that step, its end as it said it (Tester::rest_of). One never said: no motion.
#callsite(autofill(loc))
pub fn Flow::run_to_rest(self : Flow, name : String, loc~ : SourceLoc) -> Unit {
  if pace_split.val != "" {
    return
  }
  let site = loc.to_string()
  let end = self.t.rest_of(name)
  if end <= self.t.time() && self.rest_passed(name) {
    self.core()
    return
  }
  // (one so named over before the last step that acted: its end as it said it (Tester::rest_of), run_to there)
  self.run_to_at(site, fn() { self.t.rest_of(name) })
}

///|
/// Whether what moves named `name` was said since the last step that acted and is at rest now (Flow::run_to_rest):
/// a motion said and over, not one never said.
pub fn Flow::rest_passed(self : Flow, name : String) -> Bool {
  self.t.rest_of(name) <= self.t.time() && self.said.iter().any(fn(m) { m.contains(name) })
}

///|
/// `page` pushed over Home, as a scripted run's `#env MBUI_OPEN_PAGE` has it (src/stillfail/main.mbt; there before
/// the first frame, here once the Tester has drawn Home: the same asks, matched whatever their order), in place once
/// its push is over (@ui.nav_rest).
#callsite(autofill(loc))
pub fn Flow::open_page(self : Flow, page : @sfapp.Page, loc~ : SourceLoc) -> Unit {
  if pace_split.val != "" {
    return
  }
  let site = loc.to_string()
  emit("#env MBUI_OPEN_PAGE=" + page_name(page))
  @sfapp.open_page(page)
  self.t.draw()
  self.core()
  // (a page pushed over Home slides in, to its end)
  if @ui.nav_rest() >= 0.0 {
    self.run_to_at(site, @ui.nav_rest)
  }
}

// ── batch C's steps (appended): a desktop's pointer, the window, a drag ─────────────────────────────

///|
/// The lowest `what` (`top`: the highest) on screen, or the test fails.
/// An input as the strict pass worked it out of the screen (Flow::start): a pace pass's own, the same.
#derive(Debug)
priv enum Kept {
  Point(Double, Double)
  NoPoint
  Waited(Double)
  Amount(Double)
}

///|
/// What the strict pass worked its inputs out to, by the test's line that asked (a step there skipped or taken more
/// often, as what the test reads of its screen decides, does not shift the others'), in the order taken there (Kept).
// kept across runs: emptied as each strict pass begins, read on by the pace passes after it (Flow::start)
let kept_inputs : Map[String, Array[Kept]] = Map([])

///|
/// How many of each line's kept inputs a pace pass has given.
// kept across runs: emptied as each pace pass begins
let kept_next : Map[String, Int] = Map([])

///|
/// `k` kept for the step the test's line `site` asked (the strict pass's).
fn kept_push(site : String, k : Kept) -> Unit {
  match kept_inputs.get(site) {
    Some(a) => a.push(k)
    None => kept_inputs[site] = [k]
  }
}

///|
/// When the strict pass's app asked each `answered` step's call and when it was answered, by the test's line, the call
/// and which of its calls (Flow::answered).
// kept across runs: emptied as each strict pass begins, read by the pace passes after it
let strict_answers : Map[String, (Double?, Double?)] = Map([])

///|
/// The `answered` steps a pace pass came to (the test's line, the call, which of its calls): said at its end.
// kept across runs: emptied as each pace pass begins
let pace_answers : Array[(String, String, Int)] = []

///|
/// The steps the strict pass took (as the script says each) and the moment it took each, in order (Flow::take_step):
/// a pace pass takes each at that moment.
// kept across runs: emptied as each strict pass begins, read by the pace passes after it
let strict_steps : Array[(String, Double)] = []

///|
/// Which of the strict pass's steps a pace pass takes next.
// kept across runs: put back as each pace pass begins
let pace_step_next : Ref[Int] = Ref(0)

///|
/// The strict pass: the run's moment of the step whose line was just taken (Flow::take_step), for the wait that line
/// says (Flow::until_at) to hold at; None where it has none (a wait the run's script did not write: Flow::until,
/// Flow::answered; a line the trace has not).
// kept across runs: put back as each flow starts
let step_moment : Ref[Double?] = Ref(None)

///|
/// The strict pass: whether its first step has been taken, what it waited for so (Flow::until_at): from then on its
/// waits hold at the run's moments.
// kept across runs: put back as each flow starts
let first_taken : Ref[Bool] = Ref(false)

///|
/// The strict pass: how much later than the run's moment its first step was taken (Flow::first_screen): the run's
/// timeline from there on later by as much, each step after timed from that one (Replay::due_at), said with a wait
/// not so in time.
// kept across runs: put back as each flow starts
let opening_late : Ref[Double] = Ref(0.0)

///|
/// The strict pass: the run's moment for its first step on this clock (Replay::step_at), its first screen what may let
/// it be taken later (Flow::first_screen: opening_late); None at once, or not taken yet.
// kept across runs: put back as each flow starts
let first_step_run_at : Ref[Double?] = Ref(None)

///|
/// The strict pass: when the last message the run had before its first step was given (Flow::settle_start).
// kept across runs: put back as each flow starts
let opening_given : Ref[Double] = Ref(0.0)

///|
/// The strict pass's first step taken now, what it waited for so (the run had it at `run_at`): the run's timeline on
/// from here (Replay::step_moved_to, and the pace passes' first step here too), and how long after the last message
/// the run had before it that was, in ms and frames drawn, held to first_screen_known.
fn Flow::first_screen(self : Flow, run_at : Double) -> Unit {
  let now = self.t.time()
  first_taken.val = true
  opening_late.val = if now > run_at { now - run_at } else { 0.0 }
  self.r.step_moved_to(now)
  if strict_steps.length() > 0 {
    strict_steps[0] = (strict_steps[0].0, now)
  }
  let ms = now - opening_given.val
  let frames = self.t.frames_between(opening_given.val, now)
  println("FIRST-SCREEN \{pass_trace.val}: \{ms} ms, \{frames} frames after the last message the run had before its first step")
  match first_screen_known.get(pass_trace.val) {
    Some((most, most_frames)) if ms > most + 1.0e-3 || frames > most_frames =>
      self.fail(
        "flow \{pass_trace.val}: its first step's screen \{ms} ms (\{frames} frames) after the last message before it, more than its bar \{most} ms (\{most_frames} frames: first_screen_known)",
      )
    Some((most, most_frames)) if ms < most - 1.0e-3 || frames < most_frames =>
      self.fail(
        "flow \{pass_trace.val}: its first step's screen \{ms} ms (\{frames} frames) after the last message before it, under its bar \{most} ms (\{most_frames} frames): bring it down (first_screen_known)",
      )
    Some(_) => ()
    None => println("TEMP not in first_screen_known")
  }
}

///|
/// 1: the strict pass, keeping its inputs; 2: a pace pass, giving them; 0: neither.
// kept across runs: set as each pass begins (Flow::start)
let keeping : Ref[Int] = Ref(0)

///|
/// The next input kept, in a pace pass: None where the strict pass kept no more (said).
fn Flow::kept(self : Flow, site : String) -> Kept? {
  let i = kept_next.get(site).unwrap_or(0)
  let all = kept_inputs.get(site).unwrap_or([])
  if i >= all.length() {
    self.fail("the strict pass kept no input for this step (\{site})")
    return None
  }
  kept_next[site] = i + 1
  Some(all[i])
}

///|
/// Where an input goes, worked out of the screen by `find` in the strict pass (kept), the strict pass's in a pace pass.
fn Flow::kept_point(self : Flow, site : String, find : () -> (Double, Double)?) -> (Double, Double)? {
  match keeping.val {
    2 =>
      match self.kept(site) {
        Some(Point(x, y)) => Some((x, y))
        Some(NoPoint) => None
        Some(k) => {
          self.fail("the strict pass kept \{Repr(k)} here, not where an input went")
          find()
        }
        None => find()
      }
    _ => {
      let p = find()
      if keeping.val == 1 {
        kept_push(site, match p {
          Some((x, y)) => Point(x, y)
          None => NoPoint
        })
      }
      p
    }
  }
}

///|
/// What the test worked out of the screen at line `loc` (a choice it makes by it: whether to wheel again), as the
/// strict pass saw it: a pace pass takes the same way through the test, its screen another rate's.
#callsite(autofill(loc))
pub fn Flow::saw(self : Flow, so : Bool, loc~ : SourceLoc) -> Bool {
  self.measured(if so { 1.0 } else { 0.0 }, loc~) != 0.0
}

///|
/// A distance the test measured on the screen at line `loc` (how far to wheel to line two things up), as the strict
/// pass measured it: a pace pass's the same.
#callsite(autofill(loc))
pub fn Flow::measured(self : Flow, x : Double, loc~ : SourceLoc) -> Double {
  let site = loc.to_string()
  match keeping.val {
    2 =>
      match self.kept(site) {
        Some(Amount(d)) => d
        Some(k) => {
          self.fail("the strict pass kept \{Repr(k)} here, not what it measured")
          x
        }
        None => x
      }
    1 => {
      kept_push(site, Amount(x))
      x
    }
    _ => x
  }
}

///|
/// Whether what the test says of the screen is judged: not in a pace pass, whose inputs are the strict pass's and whose
/// screen is another rate's (what it judges: what the app tells the core, and a flow that cannot go on).
pub fn Flow::judges(self : Flow) -> Bool {
  ignore(self)
  keeping.val != 2
}

///|
fn Flow::spot(self : Flow, what : String, site : String, top? : Bool = false) -> (Double, Double)? {
  // (as a scripted run's tap waits for what it taps to show: what came for it given first, Flow::until)
  self.until_at(site, fn() { self.spots(what).length() > 0 })
  self.kept_point(site, fn() {
    let at = self.spots(what)
    if at.length() == 0 {
      self.fail("not on screen: " + what)
      return None
    }
    Some(if top { at[at.length() - 1] } else { at[0] })
  })
}

///|
/// The pointer over the lowest `what`, no button down (a flow's `hover`).
#callsite(autofill(loc))
pub fn Flow::hover(self : Flow, what : String, loc~ : SourceLoc) -> Unit {
  if pace_split.val != "" {
    return
  }
  let site = loc.to_string()
  emit("hover " + what)
  guard self.spot(what, site) is Some((x, y)) else { return }
  self.t.move_to(x, y)
  self.input_framed()
  self.t.draw()
  self.core()
}

///|
/// A secondary click on the lowest `what` (a flow's `rightclick`: a row's menu).
#callsite(autofill(loc))
pub fn Flow::right_click(self : Flow, what : String, loc~ : SourceLoc) -> Unit {
  if pace_split.val != "" {
    return
  }
  let site = loc.to_string()
  emit("rightclick " + what)
  guard self.spot(what, site) is Some((x, y)) else { return }
  self.t.right_click(x, y)
  self.input_framed()
  self.core()
}

///|
/// The window made w × h (a flow's `resize`: a desktop's window across the wide frame's breakpoint).
pub fn Flow::resize(self : Flow, w : Double, h : Double) -> Unit {
  if pace_split.val != "" {
    return
  }
  emit("resize \{w.to_int()} \{h.to_int()}")
  self.t.resize(w, h)
  self.core()
}

///|
/// The wheel turned by `dy` over the window's middle (a flow's `wheel`).
pub fn Flow::wheel(self : Flow, dy : Double) -> Unit {
  if pace_split.val != "" {
    return
  }
  emit("wheel \{dy.to_int()}")
  let (w, h) = self.t.size()
  self.t.wheel(w / 2.0, h / 2.0, dy)
  self.input_framed()
  self.core()
}

///|
/// Align content using a distance measured on the current frame. In another timing, that distance can change while
/// the same scroll is needed; match the recorded wheel step in the same direction while applying the measured distance.
#callsite(autofill(loc))
pub fn Flow::wheel_aligned(self : Flow, dy : Double, loc~ : SourceLoc) -> Unit {
  if pace_split.val != "" {
    return
  }
  let site = loc.to_string()
  let actual = "wheel \{dy.to_int()}"
  let step = if !self.strict {
    match self.r.next_step() {
      Some(recorded) if recorded.has_prefix("wheel ") && recorded != "wheel 0" &&
        ((dy < 0.0 && recorded.has_prefix("wheel -")) || (dy > 0.0 && !recorded.has_prefix("wheel -"))) => recorded
      _ => actual
    }
  } else { actual }
  emit(step)
  // (how far, as the strict pass measured it on its screen: a pace pass's the same)
  let dy = match keeping.val {
    2 =>
      match self.kept(site) {
        Some(Amount(d)) => d
        Some(k) => {
          self.fail("the strict pass kept \{Repr(k)} here, not how far it wheeled")
          dy
        }
        None => dy
      }
    1 => {
      kept_push(site, Amount(dy))
      dy
    }
    _ => dy
  }
  let (w, h) = self.t.size()
  self.t.wheel(w / 2.0, h / 2.0, dy)
  self.input_framed()
  self.core()
}

///|
/// The lowest `what` dragged by (dx, dy) in `steps` moves, a frame apart, then let go (a flow's `dragon`).
#callsite(autofill(loc))
pub fn Flow::drag(self : Flow, what : String, dx : Double, dy : Double, steps? : Int = 10, loc~ : SourceLoc) -> Unit {
  if pace_split.val != "" {
    return
  }
  let site = loc.to_string()
  // (a host's drag moves a frame a step: as many frames)
  emit("dragon \{dx.to_int()} \{dy.to_int()} \{(steps.to_double() * @ui.drag_step_ms).to_int()} " + what)
  guard self.spot(what, site) is Some((x, y)) else { return }
  self.t.drag(x, y, x + dx, y + dy, steps~)
  self.input_framed()
  self.t.draw()
  self.core()
}

///|
/// The list under the lowest `what` scrolled by `dy` (a mouse wheel's: down the page as it grows), and what the core
/// answers to it given.
#callsite(autofill(loc))
pub fn Flow::wheel_at(self : Flow, what : String, dy : Double, loc~ : SourceLoc) -> Unit {
  if pace_split.val != "" {
    return
  }
  let site = loc.to_string()
  emit("wheelat \{dy.to_int()} " + what)
  guard self.spot(what, site) is Some((x, y)) else { return }
  self.t.wheel(x, y, dy)
  self.input_framed()
  self.core()
  // the list's wheel eased to where it goes (a phone's lists, Android's, go there at once)
  let eased = self.t.rest_of("wheel ease")
  if eased > self.t.time() && eased < @double.infinity {
    self.run_to_at(site, fn() { self.t.rest_of("wheel ease") })
  }
}

///|
/// The toast on screen gone: its time shown (`@sfapp.toast_ms`, a timer), then the frame that sends it away and its way
/// out (`@kit.toast_rest`).
#callsite(autofill(loc))
pub fn Flow::toast_gone(self : Flow, loc~ : SourceLoc) -> Unit {
  if pace_split.val != "" {
    return
  }
  let site = loc.to_string()
  self.run_for(@sfapp.toast_ms)
  self.t.draw()
  // (its way out over already where it began before the test looked at it: a step that waited took the clock past)
  let out = @kit.toast_rest("toast")
  if out > self.t.time() {
    self.run_to_at(site, fn() { @kit.toast_rest("toast") })
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
#callsite(autofill(loc))
pub fn Flow::noticed(self : Flow, text : String, loc~ : SourceLoc) -> Unit {
  if pace_split.val != "" {
    return
  }
  let site = loc.to_string()
  emit("noticed " + text)
  // (as a scripted run's `noticed` waits for it: what came for it given first, Flow::until)
  self.until_at(site, fn() { self.holds_notice(text) })
  if self.judges() && !self.holds_notice(text) {
    self.fail("no notice holds " + text)
  }
}

///|
/// None of the app's notifications holds `text` now.
#callsite(autofill(loc))
pub fn Flow::no_notice(self : Flow, text : String, loc~ : SourceLoc) -> Unit {
  if pace_split.val != "" {
    return
  }
  let site = loc.to_string()
  emit("nonotice " + text)
  self.until_at(site, fn() { !self.holds_notice(text) })
  if self.judges() && self.holds_notice(text) {
    self.fail("a notice holds " + text)
  }
}

///|
/// The notification holding `text` tapped, as the system's shade sends the tap (Tester::tap_notice), and what the
/// core answers to what that opens given.
#callsite(autofill(loc))
pub fn Flow::tap_notice(self : Flow, text : String, loc~ : SourceLoc) -> Unit {
  if pace_split.val != "" {
    return
  }
  let site = loc.to_string()
  emit("notice " + text)
  self.until_at(site, fn() { self.holds_notice(text) })
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
  if pace_split.val != "" {
    return
  }
  emit("drag \{x.to_int()} \{y.to_int()} \{dx.to_int()} \{dy.to_int()} \{(steps.to_double() * @ui.drag_step_ms).to_int()}")
  let (w, h) = self.t.size()
  let x0 = if x < 0.0 { w + x } else { x }
  let y0 = if y < 0.0 { h + y } else { y }
  self.t.drag(x0, y0, x0 + dx, y0 + dy, steps~)
  self.input_framed()
  self.t.draw()
  self.core()
}

///|
/// The lowest `what` (`top`: the highest) tapped and the frames that tap draws, nothing more: what the core says to
/// it comes as the clock goes on (until_moving, Tester::run_for), a motion it sets off seen on its way. The frame after
/// the one that took the tap: where what the tap sets off from the next frame starts (a card let go: decide.mbt
/// ask_dismiss, marked as the tap is taken, going from the frame after).
#callsite(autofill(loc))
pub fn Flow::tap_now(self : Flow, what : String, top? : Bool = false, loc~ : SourceLoc) -> Double {
  if pace_split.val != "" {
    return self.t.time()
  }
  let site = loc.to_string()
  emit((if top { "tap1 " } else { "tap " }) + what)
  // (as a scripted run's tap waits for what it taps to show: what came for it given first, Flow::until)
  self.until_at(site, fn() { self.spots(what).length() > 0 })
  let p = self.kept_point(site, fn() {
    let at = self.spots(what)
    if at.length() == 0 {
      self.fail("nothing to tap: " + what)
      return None
    }
    Some(if top { at[at.length() - 1] } else { at[0] })
  })
  guard p is Some((x, y)) else { return -1.0 }
  // (down and up, taken by a frame; then the frame that one left owed, where what the tap sets off starts: at the
  // tap's moment, or a host's run's next two frames)
  self.t.touch(0, x, y)
  self.t.touch(2, x, y)
  self.input_framed()
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
fn Flow::frame_taking(_self : Flow, given : Double?) -> Double {
  // (Replay::deliver's taken_at: the display's frame that took it)
  given.unwrap_or(-1.0)
}

///|
/// The clock stepped a frame at a time, what is due given as it comes, until something said to move holds `name`
/// (Tester::moving, Tester::rest_of): when it is at rest. The test fails if nothing more may come first and none does.
pub fn Flow::until_moving(self : Flow, name : String) -> Double {
  if pace_split.val != "" {
    return self.t.time()
  }
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
  if pace_split.val != "" {
    return
  }
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
  if pace_split.val != "" {
    return
  }
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
  self.input_framed()
  self.t.draw()
  self.core()
}

///|
/// Another app shares `text` (a link) titled `title` into the app (the Tester's share_in; a scripted run's
/// MBUI_SHARE_TEXT and MBUI_SHARE_TITLE, `#env` lines its run starts the app with), taken by the frame after.
pub fn Flow::share_in(self : Flow, text : String, title? : String = "") -> Unit {
  if pace_split.val != "" {
    return
  }
  emit("#env MBUI_SHARE_TEXT=" + text)
  if title != "" {
    emit("#env MBUI_SHARE_TITLE=" + title)
  }
  self.t.share_in(text, title~)
  self.input_framed()
  self.t.draw()
  self.core()
}

///|
/// From here, where `what` (words on screen, as Tester::find finds them) is drawn down the screen each frame, till
/// Flow::followed: what the reader sees of the list carrying it, whatever moved it.
pub fn Flow::follow(self : Flow, what : String) -> Unit {
  if pace_split.val != "" {
    return
  }
  self.followed.val = what
  self.follow_ys.clear()
}

///|
/// How many times what was followed (Flow::follow) turned back since, more than `least` points each way: 0 where the
/// screen took it one way only (2026-11-09 the user, of a card's option picked and the agent answering at once, the
/// list up and then down: 「点一个决策后上下摇晃」). Following it stops.
pub fn Flow::turns_followed(self : Flow, least? : Double = 1.0) -> Int {
  self.followed.val = ""
  let ys = self.follow_ys
  let mut turns = 0
  let mut way = 0.0
  let mut from = if ys.length() > 0 { ys[0].1 } else { 0.0 }
  for p in ys {
    let d = p.1 - from
    if d.abs() < least {
      continue
    }
    if way != 0.0 && d * way < 0.0 {
      turns += 1
    }
    way = d
    from = p.1
  }
  turns
}

///|
/// What a strict pass asked that its run did not, held to what is known of its flow (strict_diverged_known): None where
/// it asked nothing else, or exactly the known asks at their moments, in their order; else what to say.
fn strict_diverged_said(flow : String, asked : Array[(Double, String)]) -> String? {
  match strict_diverged_known.get(flow) {
    None =>
      if asked.length() > 0 {
        Some("asked what the run did not: " + asked.map(fn(a) { a.1 }).join(", "))
      } else {
        None
      }
    Some(known) => {
      let mut same = known.length() == asked.length()
      for i, k in known {
        if same && ((k.0 - asked[i].0).abs() >= 1.0e-6 || k.1 != asked[i].1) {
          same = false
        }
      }
      if same {
        println("STRICT-KNOWN \{flow}: " + asked.map(fn(a) { "\{a.1} at \{a.0}" }).join(", "))
        None
      } else if asked.length() == 0 {
        Some("its strict pass asks nothing the run did not now: take it out of strict_diverged_known (pace_known.mbt)")
      } else {
        Some(
          "asked what the run did not, not as strict_diverged_known says (pace_known.mbt): " +
          asked.map(fn(a) { "\{a.1} at \{a.0}" }).join(", "),
        )
      }
    }
  }
}

///|
/// How far a step of the strict pass may fall from the run's frames' timeline (frames_as_run) before it is said: a
/// rounding.
let frame_drift_most : Double = 0.5

///|
/// Whether the pass now is the strict one (orders' first: the run's steps at the run's moments, on the run's frames where
/// its trace keeps them, each wait an assertion of its moment), not the one run through after it (its waits waited
/// for, at the default rate: what the flow's own checks are held on, and what the pace passes are held to).
fn strict_on() -> Bool {
  keeping.val == 1 && strict_mode.val
}

///|
/// Whether the pass now gives what comes at its moment between the host's frames and its inputs at their moments
/// (Tester::come_to): every pass but a test's own (the strict pass, the one run through, the pace passes); never a
/// frame's take of what came since the last (the coordinator of the migration, 2026-11-12: no pass takes messages by
/// the frame, a timing no device has).
fn timed_on() -> Bool {
  keeping.val >= 1
}

///|
/// Whether the strict pass is the one running now (orders), not the lenient one after it.
// kept across runs: set by orders around its strict pass
let strict_mode : Ref[Bool] = Ref(false)

///|
/// The strict pass's failure, its first, the pass stopped there (Flow::fail): held to strict_known by orders.
// kept across runs: emptied by orders before its strict pass
let strict_failures : Array[String] = []

///|
/// What of judged_traced_known a flow's passes said (Flow::fail): each of its entries is to be said, by orders.
// kept across runs: emptied by orders before its strict pass
let traced_said : Array[String] = []
