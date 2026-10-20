// The core's timers in a run on a clock of its own (a settled screenshot run, Android's shot_at, the web's: what the
// app is given as `own_clock`): on the app's clock, not the machine's, and waits of the app's runtime like its own.
// The core (apps/mbui/core/clock.ts) is told the app's clock (`{"clock": ms}`) where one of its timers is due, and
// before anything the app sends it (what that sets off is timed from then); it runs what is due by then and says
// when its next ones are (`{"clocked": ms, "next": due, "later": due}`, again whenever either changes). Each is a wait
// of the runtime's: one what is shown waits for (a retry, a request's time running out), and one it does not (a
// keepalive, a shown clock's next second: `later`), so a run's end goes on to the first (Tester::next_wake) and a
// picture at rest waits for it (Ctx::at_rest). While the core runs what is due it is awaited (the runtime's outside),
// so the clock stands still till it is done. Said to the engine only: never to a kept conversation given again
// (replay.mbt), never on a run's trace. On a device none of this: the core keeps its timers on real time.

///|
/// What the app's runtime gives for it (`own_clock`): its clock (ms), a wait on it of so many ms (`later`: nothing
/// shown waits on it) that does `then` at its end, given back as what lets it go, and its outside's start and end.
pub(all) struct ClockRuntime {
  now : () -> Double
  wait : (Int, Bool, () -> Unit) -> () -> Unit
  start : (String) -> Int
  end : (Int) -> Unit
  /// said of each answer (MB_CORE_TRACE)
  log : ((String) -> Unit)?
}

///|
priv struct OwnClock {
  mut runtime : ClockRuntime?
  /// the clock last told the core
  mut told : Double
  /// the wait on the core running what is due (0: none), and the clock it was told then
  mut ticket : Int
  mut asked : Double
  /// what lets go of the runtime's waits for the core's next timers: what is shown waits for, and not
  mut next : (() -> Unit)?
  mut later : (() -> Unit)?
}

///|
let own : OwnClock = {
  runtime: None,
  told: -1.0,
  ticket: 0,
  asked: 0.0,
  next: None,
  later: None,
}

///|
/// The core's timers taken onto the app's clock from now (those it set as it started go over with what they had
/// left): call once its engine is started, in a run on a clock of its own.
pub fn own_clock(runtime : ClockRuntime) -> Unit {
  own.runtime = Some(runtime)
  tick()
}

///|
/// The core told the app's clock, awaited till it has run what is due by then.
fn tick() -> Unit {
  guard own.runtime is Some(rt) else { return }
  let now = (rt.now)()
  own.asked = now
  if own.ticket == 0 {
    own.ticket = (rt.start)("core: its timers due by \{now.to_int64()} ms")
  }
  tell(now)
}

///|
fn tell(now : Double) -> Unit {
  own.told = now
  if engine.started {
    ffi_send(Json::object({ "clock": Json::number(now) }).stringify())
  }
}

///|
/// Before the app sends the core anything: the app's clock, where it has gone on since the core was last told.
fn clock_before_send() -> Unit {
  guard own.runtime is Some(rt) else { return }
  let now = (rt.now)()
  if now > own.told {
    tell(now)
  }
}

///|
/// A core started anew (it runs on real time till told) told the app's clock again.
fn clock_again() -> Unit {
  guard own.runtime is Some(rt) else { return }
  tell((rt.now)())
}

///|
/// One of the runtime's waits in place of `was`, for the core's next due at `due`.
fn core_wait(
  rt : ClockRuntime,
  was : (() -> Unit)?,
  due : Double?,
  later : Bool,
) -> (() -> Unit)? {
  match was {
    Some(let_go) => let_go()
    None => ()
  }
  match due {
    Some(at) => {
      let ms = (at - (rt.now)()).ceil().to_int()
      Some((rt.wait)(if ms < 0 { 0 } else { ms }, later, tick))
    }
    None => None
  }
}

///|
/// What the core answered a `clock` (or said as its next ones changed).
fn clocked(m : Map[String, Json]) -> Unit {
  guard own.runtime is Some(rt) else { return }
  let at = match m.get("clocked") {
    Some(Number(d, ..)) => d
    _ => return
  }
  let due = fn(k) {
    match m.get(k) {
      Some(Number(d, ..)) => Some(d)
      _ => None
    }
  }
  match rt.log {
    Some(log) => log("[core clock] at \{at} ms: next \{due("next")}, later \{due("later")}")
    None => ()
  }
  if own.ticket != 0 && at >= own.asked {
    (rt.end)(own.ticket)
    own.ticket = 0
  }
  own.next = core_wait(rt, own.next, due("next"), false)
  own.later = core_wait(rt, own.later, due("later"), true)
}
