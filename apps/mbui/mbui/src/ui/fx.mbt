// The window's effect.mb runtime (src/effect): logic and animation as fibers on the frames' own clock. Each frame
// starts by moving the runtime to the frame's time (Runtime::frame: the timers due fire at their times, what they wake
// runs, then the fibers waiting for a frame go on, all before the view is built); the view reads what they left,
// synchronously. What a frame's handlers fork first runs at the start of the next frame. The frame ends asking for
// another while a fiber waits for one, and for a wake at the next timer. On every host it is the same code (the
// host's frames drive it, a host's callback that wakes a fiber asks for a frame); under the Tester it is the
// Tester's clock, and `Tester::new(seed=n)` draws the order ready fibers run in from n (SEED=n replays a run).

///|
let fx : Ref[@effect.Runtime] = Ref(fx_runtime(None))

///|
/// A scope that lives while its key is asked for each frame (Ctx::lifetime).
priv struct Life {
  scope : @effect.Scope
  mut seen : Int
}

///|
let lives : Map[Int, Life] = Map([])

///|
fn fx_runtime(seed : Int?) -> @effect.Runtime {
  let rt = match seed {
    Some(s) => @effect.Runtime::new(seed=s)
    None => @effect.Runtime::new()
  }
  // a fiber woken between frames (a host's callback gave it its answer, a handler forked it): a frame soon
  rt.on_wake(() => if !offscreen_frame() { h_request_frame() })
  // (between frames its clock the host's as it stands: what a callback come long after the last frame sets starts
  // from its own moment; in a frame, the frame's time from its very start, before its fibers run up to it: what came
  // from outside handed on as it begins, messages_arrive's and take_messages', an offscreen frame's view at its `t`)
  rt.outside_clock(() => whole_ms(if frame_moment.val >= 0.0 { frame_moment.val } else { h_now() }).to_int64())
  // (what a frame makes ready, its view's forks, its messages' handlers', is ready together, the seed choosing among
  // them: no frame of the host's comes between them; a callback between frames is an event of its own)
  rt.outside_event(() => if frame_moment.val >= 0.0 { frame_serial.val } else { -1 })
  // a timer set between frames (a host's callback, a test's): a frame at its moment, the runtime brought there (it
  // runs only as a frame is built: fx_frame_start)
  // (one set as a frame is built is the frame's: fx_frame_end wakes for the next; one set as it begins, before it is
  // said built whole or not, as a moment asked before: a frame of its paint or its looks alone wakes for it too)
  rt.on_timer(at => if frame_moment.val < 0.0 {
    g().wake_at_time(at.to_double(), later=true)
    // (the host told, as a frame's end tells it: idle, it draws nothing till then otherwise. Between frames a host
    // draws, for a wake `ms` after, the first frame whose time is at or after its clock now and `ms`, on the frames'
    // clock (ios_app.m mb_host_wake_after, linux_app.c, the fake's): so `at` less the host's clock now, not less the
    // runtime's, which is the last frame's time where that frame was drawn for a moment ahead of the host's clock;
    // no floor of a ms, which would wake it a frame late for a moment less than a ms on: the hosts take any wait)
    h_wake_after(dmax(at.to_double() - h_now(), 0.0))
  } else if frame_running.val && !frame_built.val {
    // (what came from outside handed on as the frame begins: a message one said, messages_arrive)
    g().wake_at_time(at.to_double(), later=true)
  })
  rt
}

///|
/// A new runtime (a Tester starting): what the last one ran is forgotten.
fn fx_reset(seed : Int?) -> Unit {
  fx.val = fx_runtime(seed)
  lives.clear()
}

///|
/// The window's runtime: its clock is the frames' clock.
pub fn runtime() -> @effect.Runtime {
  fx.val
}

///|
/// A frame starts at `c.clock`: the runtime goes there (whole milliseconds), its fibers run. They run outside the
/// frame's reading, as a handler does (frame_body runs under the frame's watch): what a timer or a fiber reads is not
/// the frame's to follow, so its changing later builds no frame whole (it did, once, till the next frame built whole
/// read the watch anew), and what it changes is drawn by this frame all the same, read by the view after it. An effect
/// one makes is owned by nothing (no owner set, whatever was set around the frame): a root of the signals' graph, as
/// one made in a handler, let go only by the function `@signals.effect` gave back, which its maker keeps (a fiber,
/// by its scope's finalizer); never the frame's watch's, which let it go as it read the next frame (#5594's fault).
fn fx_frame_start(c : Ctx) -> Unit {
  let at = whole_ms(c.clock).to_int64()
  let was = @signals.set_active_sub(None)
  let owner = @signals.set_owner(None)
  fx.val.frame(at)
  @signals.set_active_sub(was) |> ignore
  @signals.set_owner(owner) |> ignore
}

///|
/// A frame is built: the lifetimes not asked for end; another frame while a fiber waits for one (the host's next, as
/// the clock goes: no frame owed at this moment), else a wake at the next timer.
fn fx_frame_end(c : Ctx) -> Unit {
  if !lives.is_empty() {
    let gone : Array[Int] = []
    lives.each(fn(id, l) { if l.seen != c.build_no { gone.push(id) } })
    for id in gone {
      match lives.get(id) {
        Some(l) => l.scope.close_now()
        None => ()
      }
      lives.remove(id)
    }
  }
  let rt = fx.val
  // (one ready, forked by this frame or woken in it: it runs at the next frame, at this moment, as an input's
  // frame after)
  if !rt.idle() {
    c.request_frame()
  }
  c.fiber_frame = rt.wants_frame()
  match rt.next_timer() {
    Some(at) => c.wake_at_time(at.to_double(), later=true)
    None => ()
  }
}

///|
/// Starts `f` as a fiber of the window's runtime (its root scope): it first runs at the start of the next frame (at the time it was forked).
pub fn[X] Ctx::fork(self : Ctx, f : async () -> X, name? : String = "") -> @effect.Fiber[X] {
  ignore(self)
  fx.val.fork(f, name~)
}

///|
/// A scope that lives while `key` (in the current id scope) is asked for each frame: the first frame it is not, it
/// closes (its fibers interrupted, its finalizers run, last first), as a component's life ends when it is no longer
/// built.
pub fn Ctx::lifetime(self : Ctx, key : String) -> @effect.Scope {
  let id = self.id("\u{2}life/" + key)
  match lives.get(id) {
    Some(l) => {
      l.seen = self.build_no
      l.scope
    }
    None => {
      let l = { scope: fx.val.scope(), seen: self.build_no }
      lives[id] = l
      l.scope
    }
  }
}

///|
/// Runs `f` once, when `key` is first asked for, as a fiber of its lifetime (Ctx::lifetime): interrupted, its
/// finalizers run, once `key` is no longer asked for (React's useEffect with no dependencies; Effect's forkScoped).
pub fn Ctx::effect(self : Ctx, key : String, f : async (@effect.Scope) -> Unit) -> Unit {
  let fresh = !lives.contains(self.id("\u{2}life/" + key))
  let s = self.lifetime(key)
  if fresh {
    ignore(s.fork(() => f(s), name=key))
  }
}

