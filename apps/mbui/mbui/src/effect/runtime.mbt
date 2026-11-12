// The scheduler: one thread, a list of ready tasks and a heap of timers. It
// never runs on its own: whoever owns it (a test, or a host's run loop) says
// when it runs and how far time moves.
//
// - Virtual time (`Runtime::new`): `advance(ms)` moves the clock from timer to
//   timer, running what each wakes before the next; nothing waits for real
//   time. With a seed, which ready task runs next is drawn from it, so a test
//   can try many interleavings and replay any one of them exactly.
// - Frame time (`frame(t)`): a UI's frames drive the virtual clock (mbui's
//   loop does, on every host, and the Tester on its clock): each frame moves it
//   to the frame's time, runs what that wakes, then the fibers waiting for a
//   frame (`next_frame`). UI, animation and logic share that one clock.
// - Host time (`Runtime::live`): the host calls `tick()` from its run loop (a
//   timer it set for `next_timer()`, a callback that completed a Deferred);
//   ready tasks run in FIFO order.
//
// Nothing of a runtime refers back to it once its fibers have ended (no cycle
// for native's reference counting to leak): `holding` says what it still
// holds, and a test checks it is nothing after `shutdown`.

///|
priv enum Resume {
  Go
  Stop
}

///|
priv enum End {
  NotYet
  Done
  Raised(Error)
  Cut
}

///|
/// A task: the code of one fiber, run by the scheduler between suspensions.
struct Task {
  id : Int
  rt : Runtime
  name : String
  /// parked: what resumes it (none while it runs, and once it ended)
  mut state : ((Resume) -> Unit)?
  mut end : End
  /// Asked to stop: the next suspension (outside a shield) raises the
  /// cancellation signal.
  mut interrupted : Bool
  /// Inside `uninterruptible` (finalizers, acquisition): not cut.
  mut shield : Int
  mut queued : Bool
  /// When it became ready: a frame's turn runs it at that moment, in its place among the timers due by then
  /// (Runtime::make_ready).
  mut since : Int64
  /// Where it was made ready among what was set (the timers' `seq`): at one moment, what was set first goes first.
  mut seq : Int
  /// The host's event it was made ready in between frames (Runtime::outside_event): those of one are ready together.
  mut event : Int
  watchers : Map[Int, () -> Unit]
}

///|
priv struct Timer {
  at : Int64
  seq : Int
  mut fire : () -> Unit
  mut live : Bool
  /// set for a change some time later (a refresh, a caret's blink, words that go back after a while): what is
  /// shown is not waiting for it to be settled (outside.mbt's `settled`)
  later : Bool
  /// who set it (the sleeping fiber's name; "" not said), for `unsettled`
  who : String
}

///|
fn Timer::before(self : Timer, other : Timer) -> Bool {
  self.at < other.at || (self.at == other.at && self.seq < other.seq)
}

///|
/// A binary heap of timers: by time, then by when they were set.
priv struct Heap {
  items : Array[Timer]
}

///|
fn Heap::push(self : Heap, t : Timer) -> Unit {
  self.items.push(t)
  let mut i = self.items.length() - 1
  while i > 0 {
    let p = (i - 1) / 2
    if self.items[i].before(self.items[p]) {
      self.items.swap(i, p)
      i = p
    } else {
      break
    }
  }
}

///|
fn Heap::peek(self : Heap) -> Timer? {
  if self.items.is_empty() {
    None
  } else {
    Some(self.items[0])
  }
}

///|
fn Heap::pop(self : Heap) -> Timer? {
  let n = self.items.length()
  if n == 0 {
    return None
  }
  let top = self.items[0]
  let last = self.items.pop().unwrap()
  if n > 1 {
    self.items[0] = last
    let m = n - 1
    let mut i = 0
    while true {
      let l = 2 * i + 1
      let r = l + 1
      let mut s = i
      if l < m && self.items[l].before(self.items[s]) {
        s = l
      }
      if r < m && self.items[r].before(self.items[s]) {
        s = r
      }
      if s == i {
        break
      }
      self.items.swap(i, s)
      i = s
    }
  }
  Some(top)
}

///|
pub struct Runtime {
  priv mut time : Int64
  priv clock : (() -> Int64)?
  priv ready : Array[Task]
  /// Tasks made ready between frames (Runtime::make_ready), in the order they were: ready all the same, run by a frame's
  /// turn at their moment among the timers.
  priv later : Array[Task]
  priv timers : Heap
  priv mut seq : Int
  priv shuffle : Bool
  priv sched : Rng
  /// Draws for simulations (jitter, order, loss): apart from the scheduler's,
  /// from the same seed.
  rng : Rng
  /// The seed the run was made with (0: none, FIFO).
  seed : Int
  priv mut ids : Int
  /// The root scope's state (a Scope made on demand around it: the runtime
  /// holds no Scope, which would hold the runtime)
  priv root_state : ScopeState
  /// Fibers waiting for the next frame (`next_frame`).
  priv frame_waiters : Waiters
  /// Timers dead in the heap (a sleep interrupted), dropped in bulk.
  priv mut dead : Int
  /// Tasks started and not ended.
  priv mut live_tasks : Int
  /// Frames so far (`frame`).
  mut frames : Int
  /// Told of a fiber of a scope that failed, or a finalizer (Runner.onDefect).
  priv mut defect : (Error) -> Unit
  /// Told when a task becomes ready outside a turn (a host's callback gave a
  /// Deferred its value): the host then schedules a `tick`.
  priv mut waker : () -> Unit
  /// Told of a timer set while no turn runs (a test's or a host's callback between frames: Runtime::on_timer), its
  /// moment: the host then wakes for it, as for the next timer a turn leaves.
  priv mut timer_waker : (Int64) -> Unit
  /// The clock as it stands between frames, where what owns the runtime has one (Runtime::outside_clock): what is set
  /// then (a timer, a sleep) starts from it, not from the last frame's time, however long ago that was; a negative
  /// answer: none (in a frame, its time)
  priv mut outside : () -> Int64
  /// The host's event a task made ready between frames comes in (Runtime::outside_event), -1: one of its own.
  priv mut outside_event : () -> Int
  priv mut turning : Bool
  /// What failed, as said, when nobody else was told.
  defects : Array[String]
  /// What the run said (`trace`), each line with its time.
  log : Array[String]
  /// Task resumptions and timers fired so far: what the run did of its own (a frame begun after it moved on builds
  /// what it left anew: mbui's still.mbt).
  mut steps : Int
  /// What it waits on from outside (outside.mbt): by ticket, what it is and since when.
  priv awaited : Map[Int, (String, Int64)]
  priv mut tickets : Int
  /// What ended of it since the mark asked last (outside_ended): what each was, and how many had ended before it;
  /// kept only once someone asks (a scripted run)
  priv ended : Array[(Int, String)]
  priv mut ended_n : Int
  priv mut keep_ended : Bool
}

///|
let current : Ref[Task?] = Ref(None)

///|
fn Runtime::make(seed : Int, shuffle : Bool, start : Int64, clock : (() -> Int64)?) -> Runtime {
  let defects = []
  {
    time: start,
    clock,
    ready: [],
    later: [],
    timers: { items: [] },
    seq: 0,
    shuffle,
    sched: Rng::new(seed),
    rng: Rng::new(seed * 7919 + 17),
    seed,
    ids: 0,
    root_state: ScopeState::new(true),
    frame_waiters: Waiters::new(),
    dead: 0,
    live_tasks: 0,
    frames: 0,
    defect: e => defects.push(e.to_string()),
    waker: () => (),
    timer_waker: _ => (),
    outside: () => -1L,
    outside_event: () => -1,
    turning: false,
    defects,
    log: [],
    steps: 0,
    awaited: Map([]),
    ended: [],
    ended_n: 0,
    keep_ended: false,
    tickets: 0,
  }
}

///|
/// A runtime on virtual time from `start` (ms). With a `seed`, the ready task
/// that runs next is drawn from it; without, they run in the order they
/// became ready.
pub fn Runtime::new(seed? : Int, start? : Int64 = 0L) -> Runtime {
  match seed {
    Some(s) => Runtime::make(s, true, start, None)
    None => Runtime::make(0, false, start, None)
  }
}

///|
/// A runtime on the host's clock (ms): the host calls `tick` when it is due.
pub fn Runtime::live(now : () -> Int64) -> Runtime {
  Runtime::make(0, false, now(), Some(now))
}

///|
/// Who is told of failures nobody waited for (by default `defects` keeps them).
pub fn Runtime::on_defect(self : Runtime, f : (Error) -> Unit) -> Unit {
  self.defect = f
}

///|
fn Runtime::report(self : Runtime, e : Error) -> Unit {
  (self.defect)(e)
}

///|
/// Who is told that a task became ready while no turn runs (Runtime::live:
/// the host then calls `tick` soon, on its run loop).
pub fn Runtime::on_wake(self : Runtime, f : () -> Unit) -> Unit {
  self.waker = f
}

///|
/// Who is told of a timer set while no turn runs, at its moment (`f(at)`): what owns the runtime wakes then (a UI's
/// frame at it), as for the next timer a turn leaves (Runtime::next_timer).
pub fn Runtime::on_timer(self : Runtime, f : (Int64) -> Unit) -> Unit {
  self.timer_waker = f
}

///|
/// The clock between frames (ms; negative: none, as in a frame), for what is set while no turn runs: a host's callback
/// come long after the last frame starts its timers from its own moment, as the host's clock has it.
pub fn Runtime::outside_clock(self : Runtime, f : () -> Int64) -> Unit {
  self.outside = f
}

///|
/// Which of the host's events a task made ready between frames comes in (-1: one of its own, as a callback of its own
/// is). What one event makes ready (a frame's view forking two fibers) is ready together, the seed choosing among them;
/// what two do keeps their order, a host's frame able to come between them (Runtime::fire_until).
pub fn Runtime::outside_event(self : Runtime, f : () -> Int) -> Unit {
  self.outside_event = f
}

///|
/// The core's own scope: closing it ends everything.
pub fn Runtime::root(self : Runtime) -> Scope {
  { rt: self, st: self.root_state }
}

///|
/// The runtime's clock, in whole ms: under a window's frames, the frame's time rounded down (a display's frames come
/// 1000/60 ms apart, its timers are whole ms: what a host's own clock gives too).
pub fn Runtime::now(self : Runtime) -> Int64 {
  match self.clock {
    Some(f) => f()
    None if self.turning => self.time
    None => {
      let t = (self.outside)()
      if t > self.time {
        t
      } else {
        self.time
      }
    }
  }
}

///|
/// Notes a line in the run's log, with the time.
pub fn Runtime::trace(self : Runtime, s : String) -> Unit {
  self.log.push("\{self.now()} \{s}")
}

///|
/// The log as one text, a line each.
pub fn Runtime::trace_text(self : Runtime) -> String {
  self.log.join("\n")
}

///|
fn current_task() -> Task {
  match current.val {
    Some(t) => t
    None => @halt.saying("effect: not inside a task")
  }
}

///|
/// The runtime the running code is on.
pub fn runtime() -> Runtime {
  current_task().rt
}

///|
/// The time on the running code's clock (ms).
pub fn now() -> Int64 {
  current_task().rt.now()
}

///|
/// Notes a line in the run's log (`Runtime::trace`).
pub fn trace(s : String) -> Unit {
  current_task().rt.trace(s)
}

///|
fn Runtime::start(self : Runtime, name : String, body : async () -> Unit) -> Task {
  self.ids += 1
  let t : Task = {
    id: self.ids,
    rt: self,
    name,
    state: None,
    end: NotYet,
    interrupted: false,
    shield: 0,
    queued: false,
    since: 0L,
    seq: 0,
    event: 0,
    watchers: {},
  }
  t.state = Some(fn(r) {
    // Interrupted before it ever ran: it never does (as Effect has it).
    if r is Stop {
      t.end = Cut
      t.state = None
      t.finish()
      return
    }
    run_raw(() => {
      try capture_cancel(body, handler=() => t.end = Cut) catch {
        e => t.end = Raised(e)
      } noraise {
        _ => if t.end is NotYet { t.end = Done }
      }
      t.state = None
      t.finish()
    })
  })
  self.live_tasks += 1
  self.make_ready(t)
  t
}

///|
/// `t` ready: it runs at the moment it became so. One made ready between frames (a host's callback, come long after
/// the last frame or not: Runtime::outside_clock) runs at that moment, in its place among the timers set then, by the
/// order they were set (Runtime::fire_until), as a timer set then would: not before them at the last frame's time,
/// whatever frames came. It is ready all the same (idle, wants_frame, run_ready, holding, unsettled say so).
fn Runtime::make_ready(self : Runtime, t : Task) -> Unit {
  t.queued = true
  t.since = if self.turning { self.time } else { self.now() }
  if self.clock is None && !self.turning {
    self.seq += 1
    t.seq = self.seq
    let e = (self.outside_event)()
    // (one of its own: the seq, negative, no event's)
    t.event = if e >= 0 { e } else { -self.seq }
    self.later.push(t)
  } else {
    self.ready.push(t)
  }
  if !self.turning {
    (self.waker)()
  }
}

///|
fn Task::finish(self : Task) -> Unit {
  self.rt.live_tasks -= 1
  let ws = self.watchers.values().to_array()
  self.watchers.clear()
  for w in ws {
    w()
  }
}

///|
fn Task::watch(self : Task, f : () -> Unit) -> Int {
  self.rt.ids += 1
  let id = self.rt.ids
  self.watchers.set(id, f)
  id
}

///|
fn Task::wake(self : Task) -> Unit {
  if !self.queued && self.state is Some(_) {
    self.rt.make_ready(self)
  }
}

///|
fn Task::interrupt(self : Task) -> Unit {
  if self.end is NotYet {
    self.interrupted = true
    if self.shield == 0 {
      self.wake()
    }
  }
}

///|
/// Parks the running task until something wakes it; interrupted, it raises
/// the cancellation signal (outside a shield).
async fn park() -> Unit noraise {
  let t = current_task()
  if t.interrupted && t.shield == 0 {
    raise_cancel()
  }
  let r : Resume = suspend_raw(k => { t.state = Some(k) })
  if r is Stop {
    raise_cancel()
  }
}

///|
async fn Task::wait_once(self : Task) -> Unit noraise {
  let me = current_task()
  let id = self.watch(() => me.wake())
  defer self.watchers.remove(id)
  park()
}

///|
async fn Task::await_end(self : Task) -> Unit noraise {
  while self.end is NotYet {
    self.wait_once()
  }
}

///|
/// Lets the other ready tasks run first.
pub async fn pause() -> Unit noraise {
  let t = current_task()
  if t.interrupted && t.shield == 0 {
    raise_cancel()
  }
  let r : Resume = suspend_raw(k => {
    t.state = Some(k)
    t.queued = true
    t.since = t.rt.time
    t.rt.ready.push(t)
  })
  if r is Stop {
    raise_cancel()
  }
}

///|
fn Runtime::add_timer(
  self : Runtime,
  at : Int64,
  fire : () -> Unit,
  later? : Bool = false,
  who? : String = "",
) -> Timer {
  self.seq += 1
  let t = { at, seq: self.seq, fire, live: true, later, who }
  self.timers.push(t)
  if !self.turning {
    (self.timer_waker)(at)
  }
  t
}

///|
/// Calls `f` (sync code: a simulated host, a delivery) `ms` from now on the
/// runtime's clock. `later`: a change some time later that what is shown does not wait for to be settled (a
/// refresh); by default it does.
pub fn Runtime::after(
  self : Runtime,
  ms : Int,
  f : () -> Unit,
  later? : Bool = false,
  who? : String = "",
) -> Unit {
  ignore(self.add_timer(self.now() + ms.to_int64(), f, later~, who~))
}

///|
/// Waits `ms` on the runtime's clock. `later`: what is shown is not waiting for it (a refresh loop's pause, words
/// that go back after a while); by default it is, and the runtime is not settled until it is over.
pub async fn sleep(ms : Int, later? : Bool = false) -> Unit noraise {
  let t = current_task()
  let rt = t.rt
  let at = rt.now() + ms.to_int64()
  let timer = rt.add_timer(at, () => t.wake(), later~, who=t.name)
  defer {
    if timer.live {
      timer.live = false
      // what it would wake is not held by the heap meanwhile
      timer.fire = () => ()
      rt.dropped()
    }
  }
  while rt.now() < at {
    park()
  }
}

///|
fn Runtime::pick(self : Runtime) -> Task? {
  if self.ready.is_empty() {
    None
  } else if self.shuffle {
    Some(self.ready.remove(self.sched.below(self.ready.length())))
  } else {
    Some(self.ready.remove(0))
  }
}

///|
/// When the first task made ready between frames did, if one is waiting (Runtime::make_ready).
fn Runtime::ready_later(self : Runtime) -> Int64? {
  let mut first : Int64? = None
  if self.clock is None {
    for t in self.later {
      match first {
        Some(f) if f <= t.since => ()
        _ => first = Some(t.since)
      }
    }
  }
  first
}

///|
/// Runs the ready tasks that became so by the clock's time, and what they make ready, until none is (a frame's turn:
/// Runtime::fire_until); those made ready later than it (Runtime::make_ready) are left ready, in their order.
fn Runtime::run_ready_now(self : Runtime) -> Unit {
  if !self.later.is_empty() {
    for t in self.later {
      if t.since <= self.time {
        self.ready.push(t)
      }
    }
    self.later.retain(t => t.since > self.time)
  }
  ignore(self.run_tasks())
}

///|
fn Runtime::step_task(self : Runtime, t : Task) -> Unit {
  t.queued = false
  guard t.state is Some(k) else { return }
  t.state = None
  let prev = current.val
  current.val = Some(t)
  self.steps += 1
  k(if t.interrupted && t.shield == 0 { Stop } else { Go })
  current.val = prev
}

///|
/// A timer was given up (a sleep interrupted): once most of the heap is such,
/// it is rebuilt of the live ones (what a dead one's closure holds goes).
fn Runtime::dropped(self : Runtime) -> Unit {
  self.dead += 1
  if self.dead >= 32 && self.dead * 2 > self.timers.items.length() {
    let live = self.timers.items.filter(t => t.live)
    self.timers.items.clear()
    for t in live {
      self.timers.push(t)
    }
    self.dead = 0
  }
}

///|
/// Runs ready tasks until none is, those made ready between frames at a later moment too (at the clock's time: only a
/// frame's turn, advance or tick runs them at theirs, Runtime::make_ready); returns how many resumptions that took.
pub fn Runtime::run_ready(self : Runtime) -> Int {
  for t in self.later {
    self.ready.push(t)
  }
  self.later.clear()
  self.run_tasks()
}

///|
/// Runs what is ready until none is; how many resumptions that took.
fn Runtime::run_tasks(self : Runtime) -> Int {
  let outer = self.turning
  self.turning = true
  defer {
    self.turning = outer
  }
  let mut n = 0
  while self.pick() is Some(t) {
    self.step_task(t)
    n += 1
    if n > 10_000_000 {
      @halt.saying("effect: tasks kept each other ready without end (\{t.name})")
    }
  }
  n
}

///|
/// The next timer said once (not `later`: what is shown waits for it) that is due, when and who said it, if one is.
pub fn Runtime::next_due(self : Runtime) -> (Int64, String)? {
  let mut best : (Int64, String)? = None
  for t in self.timers.items {
    if t.live && !t.later {
      match best {
        Some((at, _)) if at <= t.at => ()
        _ => best = Some((t.at, t.who))
      }
    }
  }
  best
}

///|
/// When the next timer is due, if one is set.
pub fn Runtime::next_timer(self : Runtime) -> Int64? {
  while self.timers.peek() is Some(t) && !t.live {
    ignore(self.timers.pop())
    self.dead -= 1
  }
  match self.timers.peek() {
    Some(t) => Some(t.at)
    None => None
  }
}

///|
/// Fires the timers due by `until`, one instant at a time, running what each
/// instant wakes before the next; a task made ready between frames
/// (Runtime::make_ready) runs at its instant among the timers due then, in the
/// order they were set.
fn Runtime::fire_until(self : Runtime, until : Int64) -> Unit {
  let outer = self.turning
  self.turning = true
  defer {
    self.turning = outer
  }
  ignore(self.run_tasks())
  // (the next instant: a timer's, or a task's made ready between frames at its own moment, the earlier)
  while self.next_instant() is Some(at) && at <= until {
    if self.clock is None && at > self.time {
      self.time = at
    }
    // (at one instant the timers due and the tasks made ready then, in the order they were set: what was set first
    // goes first, whatever frames came between, Runtime::make_ready)
    // (each found again after each: a timer's callback may make ready, or run what is ready, Runtime::run_ready)
    while true {
      let task = self.later_due()
      match self.timers.peek() {
        Some(t) if t.at <= at &&
          (match task {
            Some(i) => t.seq < self.later[i].seq
            None => true
          }) => {
          ignore(self.timers.pop())
          if t.live {
            t.live = false
            self.steps += 1
            (t.fire)()
          } else {
            self.dead -= 1
          }
        }
        _ =>
          match task {
            Some(i) => {
              // (the first set and those its host's event made ready with it, before the next timer set at this
              // instant, together, each with what it makes ready: which runs first among them is the scheduler's,
              // drawn from the seed if the runtime has one, as among any ready; what another event made ready after
              // goes after, a host's frame able to come between the two, the first run in it before the second was)
              // (they lie together in later from the first: one event's are made ready one after the other, at its one
              // moment, none of another's between; so as many looked at as go)
              let event = self.later[i].event
              let before = match self.timers.peek() {
                Some(t) if t.at <= at => Some(t.seq)
                _ => None
              }
              let mut end = i
              while end < self.later.length() &&
                    self.later[end].event == event &&
                    self.later[end].since <= self.time &&
                    (match before {
                      Some(b) => self.later[end].seq < b
                      None => true
                    }) {
                self.ready.push(self.later[end])
                end += 1
              }
              let n = end - i
              for k in i..<(self.later.length() - n) {
                self.later[k] = self.later[k + n]
              }
              for _ in 0..<n {
                ignore(self.later.pop())
              }
              ignore(self.run_tasks())
            }
            None => break
          }
      }
    }
    ignore(self.run_tasks())
  }
}

///|
/// Of the tasks made ready between frames (Runtime::make_ready), where the first set of those due by now is, if one is:
/// they lie in the order they were set.
fn Runtime::later_due(self : Runtime) -> Int? {
  for i, t in self.later {
    if t.since <= self.time {
      return Some(i)
    }
  }
  None
}

///|
/// The next instant a frame's turn comes to: the next timer's, or a task's made ready between frames
/// (Runtime::make_ready), the earlier.
fn Runtime::next_instant(self : Runtime) -> Int64? {
  match (self.next_timer(), self.ready_later()) {
    (Some(a), Some(b)) => Some(if a < b { a } else { b })
    (Some(a), None) => Some(a)
    (None, b) => b
  }
}

///|
/// Moves virtual time on `ms`: every timer due meanwhile fires at its time.
pub fn Runtime::advance(self : Runtime, ms : Int) -> Unit {
  guard self.clock is None else { @halt.saying("effect: advance on the host's clock") }
  let until = self.time + ms.to_int64()
  self.fire_until(until)
  self.time = until
}

///|
/// The host's turn (Runtime::live): fires what is due on its clock and runs
/// what is ready. It then sets a timer for `next_timer()`, if any.
pub fn Runtime::tick(self : Runtime) -> Unit {
  self.fire_until(self.now())
}

///|
/// A frame at `at` (ms, the frame's time on a UI's clock; virtual time): the
/// clock moves there as `advance` moves it, each timer due firing at its own
/// time; then the fibers waiting for a frame (`next_frame`) go on, all at `at`,
/// with what is ready. A frame at or before the clock's time runs what is due by
/// the clock's time, what is ready and what waits for a frame. What starts
/// waiting for a frame in it waits for the next one.
pub fn Runtime::frame(self : Runtime, at : Int64) -> Unit {
  guard self.clock is None else { @halt.saying("effect: frame on the host's clock") }
  let outer = self.turning
  self.turning = true
  defer {
    self.turning = outer
  }
  self.frames += 1
  // (what is due by the frame's time, or by the clock's for a frame at or before it: the clock never goes back, and a
  // frame at the clock's time takes what was set at it between frames in the order it was set)
  let moment = if at > self.time { at } else { self.time }
  self.fire_until(moment - 1L)
  // (those that waited before it, or since at a moment before its own: one run at its moment, there when the host's
  // frame came or not, that waits for a frame waits for the next)
  let waited = self.frame_waiters.next
  self.fire_until(moment)
  if at > self.time {
    self.time = at
  }
  self.frame_waiters.wake_until(waited)
  // (one made ready later than the frame, between frames on a clock ahead of it, at a frame to come: Runtime::make_ready)
  self.run_ready_now()
}

///|
/// Whether it needs another frame: a fiber waits for one, or one is ready (forked
/// between frames, by a frame's handler).
pub fn Runtime::wants_frame(self : Runtime) -> Bool {
  !self.idle() || !self.frame_waiters.is_empty()
}

///|
/// Waits for the next frame (Runtime::frame): what animates steps once a frame.
pub async fn next_frame() -> Unit noraise {
  current_task().rt.frame_waiters.wait()
}

///|
/// What it still holds: fibers not ended, tasks ready, timers set, the root
/// scope's fibers and finalizers, fibers waiting for a frame. All 0 once
/// `shutdown` has run (`settle`): nothing is left to keep alive.
pub fn Runtime::holding(self : Runtime) -> (Int, Int, Int, Int, Int, Int) {
  (
    self.live_tasks,
    self.ready.length() + self.later.length(),
    self.timers.items.filter(t => t.live).length(),
    self.root_state.children.length(),
    self.root_state.finalizers.length(),
    self.frame_waiters.tasks.length(),
  )
}

///|
/// Timers in the heap, live or given up (given up ones are dropped in bulk).
pub fn Runtime::timer_slots(self : Runtime) -> Int {
  self.timers.items.length()
}

///|
/// Nothing is ready to run.
pub fn Runtime::idle(self : Runtime) -> Bool {
  self.ready.is_empty() && self.later.is_empty()
}

///|
/// Starts `f` as a fiber of the root scope: interrupted when the runtime shuts
/// down; a failure is told to `on_defect`.
pub fn[X] Runtime::fork(self : Runtime, f : async () -> X, name? : String = "") -> Fiber[X] {
  self.root().fork(f, name~)
}

///|
/// Closes the root scope: everything is interrupted, finalizers run.
pub fn Runtime::shutdown(self : Runtime) -> Unit {
  self.root().close_now()
}
