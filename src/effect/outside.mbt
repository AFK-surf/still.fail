// What a runtime waits on from outside it: a host's work for the app (an image decoded, a page loaded, files read),
// asked for and answered by the host's own event. Each is started with what it is and when (a ticket), and ended once
// its event is in; nothing here waits for real time. With it the runtime knows when it is settled: nothing is ready,
// no fiber waits for a frame, nothing outside is awaited and no timer is due within `within` ms. That is what a
// screenshot or a scripted step waits for, the same on every host and under the Tester, and what is still awaited
// (`awaited`) says what a run that does not settle hangs on.

///|
/// Starts waiting on something outside (`what` says what: "image 12 photo.jpg"): its ticket, for `outside_end`.
pub fn Runtime::outside_start(self : Runtime, what : String) -> Int {
  self.tickets += 1
  self.awaited[self.tickets] = (what, self.now())
  self.tickets
}

///|
/// Its answer is in (or it was given up: what asked for it is gone). A ticket ended already, or never given, is
/// nothing.
pub fn Runtime::outside_end(self : Runtime, ticket : Int) -> Unit {
  if self.awaited.contains(ticket) {
    self.awaited.remove(ticket)
    // a frame soon: what was waited on may change what is shown
    (self.waker)()
  }
}

///|
/// How many are awaited from outside.
pub fn Runtime::awaiting(self : Runtime) -> Int {
  self.awaited.length()
}

///|
/// What is awaited from outside, oldest first: what it is and since when (the runtime's clock).
pub fn Runtime::awaited(self : Runtime) -> Array[(String, Int64)] {
  let out : Array[(Int, String, Int64)] = []
  self.awaited.each(fn(k, v) { out.push((k, v.0, v.1)) })
  out.sort_by_key(x => x.0)
  out.map(x => (x.1, x.2))
}

///|
/// Settled: nothing ready, no fiber waiting for a frame, nothing awaited from outside, and no timer set that what is
/// shown waits for (every timer but those set `later`: a refresh, a blink, words going back after a while).
pub fn Runtime::settled(self : Runtime) -> Bool {
  self.ready.is_empty() &&
  self.frame_waiters.is_empty() &&
  self.awaited.is_empty() &&
  !self.timers.items.iter().any(t => t.live && !t.later)
}

///|
/// Waits on something outside as a fiber: `start` asks for it and is given the way to answer (a host's callback,
/// once); the answer is the result. Awaited (`awaited`) until then; given up if the fiber is interrupted.
pub async fn[X] outside(what : String, start : ((X) -> Unit) -> Unit) -> X {
  let rt = current_task().rt
  let d : Deferred[X] = Deferred::new()
  let ticket = rt.outside_start(what)
  defer rt.outside_end(ticket)
  start(fn(x) {
    rt.outside_end(ticket)
    ignore(d.succeed(x))
  })
  d.wait()
}

///|
/// Why it is not settled, said ("" when it is): fibers ready, waiting for a frame, what is awaited from outside, the
/// timers what is shown waits for (when, and the fiber that set it if named).
pub fn Runtime::unsettled(self : Runtime) -> String {
  let why : Array[String] = []
  if !self.ready.is_empty() {
    why.push("\{self.ready.length()} fibers ready")
  }
  if !self.frame_waiters.is_empty() {
    why.push("\{self.frame_waiters.tasks.length()} fibers waiting for a frame")
  }
  for a in self.awaited() {
    why.push("awaiting \{a.0} since \{a.1} ms")
  }
  for t in self.timers.items {
    if t.live && !t.later {
      why.push("a timer at \{t.at} ms" + (if t.who == "" { "" } else { " (\{t.who})" }))
    }
  }
  why.join("; ")
}
