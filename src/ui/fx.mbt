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
let lives : Map[Int, Life] = Map::new()

///|
fn fx_runtime(seed : Int?) -> @effect.Runtime {
  let rt = match seed {
    Some(s) => @effect.Runtime::new(seed=s)
    None => @effect.Runtime::new()
  }
  // a fiber woken between frames (a host's callback gave it its answer, a handler forked it): a frame soon
  rt.on_wake(() => h_request_frame())
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
/// A frame starts at `c.now`: the runtime goes there (whole milliseconds), its fibers run.
fn fx_frame_start(c : Ctx) -> Unit {
  fx.val.frame(c.now.floor().to_int64())
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

