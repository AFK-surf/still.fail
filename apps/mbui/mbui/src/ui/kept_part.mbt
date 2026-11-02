// A part kept as its nodes (Ctx::kept_part): what the view builds in it is kept as the nodes it built, under a watch of
// its own, and built again only as what it read changes, what it is built from besides (`key`) does, or what is no
// signal came (kept_nodes.mbt). `own`: an island (docs/retained.md, the way there's 3), kept whatever else the frame
// built anew.
//
// What a build reads of time is read as signals here (KeptClock): the frame, where what it shows changes each frame (a
// motion going on read where it is now, a layer it opened), and the moment what it shows changes at (a clock's step, a
// timer's end), whoever told the motion or the timer and wherever it was told. What is not a signal is caught by what
// changes it: an event from outside (outside_events: what the host or the runtime did, not a pointer moved nor a wheel
// turned), its `key`, the hand's events.

///|
priv struct PartsRun {
  mut ctx : Ctx?
  /// the runtime's steps as the last frame began (an event of its own since then is one from outside)
  mut steps : Int
}

///|
// kept across runs: the run it holds is compared with the frame's as each frame begins (parts_frame_start)
let parts_run : PartsRun = { ctx: None, steps: -1 }

/// How many events have come from outside the hand: an input other than a pointer
/// moved or a wheel turned, a message, a host's answer, a step of the runtime's fibers or timers, a test's draw.
// kept across runs: it only counts on
let outside_events : Ref[Int] = Ref(0)

///|
/// An event from outside came (kept_part.mbt's head): every part kept is built anew by the next frame.
fn outside_came() -> Unit {
  outside_events.val = outside_events.val + 1
  // (and what each frame's build reads of it: frame_watch.mbt)
  outside_counted()
}

///|
/// What came from outside that is no signal (a made-up core answering a call at once, as a core's message is): taken
/// as an event from outside, what is kept built anew for it (outside_came).
pub fn came_from_outside() -> Unit {
  outside_came()
}

///|
/// A list's rows laid on the device's pixels as a host lays them (Ctx::rows_on_grid), from now on, or not (as every
/// frame of a Tester's was always laid out).
pub fn Tester::keep_parts(self : Tester, on : Bool) -> Unit {
  ignore(self)
  // (how frames are built changed by the test, a list's rows set on the pixels with it: the next built whole)
  if rows_grid_test.val != on {
    test_stepped()
  }
  rows_grid_test.val = on
}

///|
/// A frame begins: what is kept of another run forgotten; the runtime's steps since the last frame an event from
/// outside.
fn parts_frame_start(c : Ctx) -> Unit {
  match parts_run.ctx {
    Some(was) if physical_equal(was, c) => ()
    _ => {
      parts_forget()
      parts_run.ctx = Some(c)
    }
  }
  let steps = fx.val.steps
  if steps != parts_run.steps {
    parts_run.steps = steps
    outside_came()
  }
}

///|
/// The frame is built: the rows and parts kept as their nodes that did not show in it let go; the moments those that
/// did read are waited for.
fn parts_frame_end(c : Ctx) -> Unit {
  rows_nodes_end(c)
  clock_frame_end(c)
}

///|
fn parts_forget() -> Unit {
  kept_clock.dues.clear()
}

/// What `body` builds, in a box of its own filling the one being built (out of the flow: the one being built laid out
/// as if it held nothing else), not read out, and kept: built again only once something it shows can have changed
/// (kept_part.mbt's head), else drawn again as its last build drew it where its box is now, nothing of it built. `id`
/// names it; `key` is what its caller builds it from besides what it reads (its size, its ground: what else changes it;
/// not where it is, which moves what it drew with it), another key building it anew. Not read out, for a part nobody uses where it is (a panel behind the one in use); `read_out`,
/// read out as its build said it, built or drawn again (a panel in use: what reads the widgets reads it as a list's
/// row kept, semantics.mbt), built each frame while it holds what is built each frame wherever it is (a native view, the
/// field that takes the keys).
#callsite(autofill(loc))
pub fn Ctx::kept_part(
  self : Ctx,
  id : Int,
  key : String,
  body : () -> Unit,
  read_out? : Bool = false,
  own? : Bool = false,
  loc~ : SourceLoc,
) -> Unit {
  // kept as its nodes, under a watch of its own (kept_nodes.mbt); `own`: built from its key and what it reads alone,
  // nothing handed it as what builds it was built, so kept whatever else the frame built anew (docs/retained.md, the
  // way there's 3: an island)
  self.part_nodes(id, key, body, read_out, own~, made_at=loc)
}

///|
/// How many parts the last frame kept as their nodes (Ctx::kept_part, kept_nodes.mbt), not built.
pub fn Tester::parts_kept(self : Tester) -> Int {
  ignore(self)
  nodes_run.kept_at.iter().filter(fn(k) { k.1 < 0 }).count()
}

///|
/// Whether what is built now is kept as it was built (a list's row or a part kept as its nodes, kept_nodes.mbt): what
/// it reads of time is followed.
fn part_building() -> Bool {
  nodes_run.building is Some(_)
}

///|
/// What a build reads of time, as signals (kept_part.mbt's head): the frame, set as each begins (what shows what
/// changes each frame reads it: a motion going on, a cycle drawn each frame, a frame owed), and the moments what is
/// shown changes at (a clock's step, a timer's end, a motion's), each set as the first frame at or past it begins, in
/// order, with whether what is shown waits for it (`later`: none of those that read it does).
priv struct KeptClock {
  frame : @signals.Signal[Int]
  dues : Array[KeptDue]
}

///|
priv struct KeptDue {
  at : Double
  mut later : Bool
  come : @signals.Signal[Bool]
}

///|
// kept across runs: its frame only counts on; its moments let go as they come and with the parts (parts_forget)
let kept_clock : KeptClock = { frame: @signals.signal(0), dues: [] }

///|
/// What is built now shows what changes each frame (as what it holds moves): built again each frame, kept or not.
fn part_live() -> Unit {
  if part_building() {
    kept_clock.frame.get() |> ignore
  }
}

///|
/// What is built now changes at `t` (`later`: what is shown does not wait for it): built again in the first frame at
/// or past it, kept or not; one past already, the next frame's.
fn part_wake(now : Double, t : Double, later : Bool) -> Unit {
  if !part_building() || t == @double.infinity {
    return
  }
  if t <= now {
    kept_clock.frame.get() |> ignore
    return
  }
  let dues = kept_clock.dues
  let mut i = 0
  while i < dues.length() && dues[i].at < t {
    i = i + 1
  }
  let d = if i < dues.length() && dues[i].at == t {
    dues[i]
  } else {
    let d = { at: t, later: true, come: @signals.signal(false) }
    dues.insert(i, d)
    d
  }
  d.later = d.later && later
  d.come.get() |> ignore
}

///|
/// What is being built shows where `who`'s motion is now (an Anim, a Value, a spring: read so as they are read): built
/// again as it is told anew, wherever and whenever that is, and each frame while it goes (`going`); kept as it was drawn
/// or not (a part's, a list's row's: kept_part.mbt's head).
pub fn Ctx::shows_motion(self : Ctx, who : Mover, going : Bool) -> Unit {
  // (going, what reads it reads the clock: built again each frame, frame_watch.mbt; and the next frame asked for as
  // this one ends, to read it again: what goes is sampled each frame it is read in, whatever else is said to move)
  if going {
    clock_read_here(who~)
    if self.in_frame() {
      self.motion_read = true
    }
  }
  if !part_building() {
    return
  }
  let said = match who.said {
    Some(s) => s
    None => {
      let s = @signals.signal(who.told)
      who.said = Some(s)
      s
    }
  }
  said.get() |> ignore
  if going {
    kept_clock.frame.get() |> ignore
  }
}

///|
/// What is being built changes at `t` (the frames' clock: a motion's declared end, read as whether it is over): built
/// again in the first frame at or past it (painted again, where it is read as it is painted: frame_watch.mbt), kept as
/// it was drawn or not.
pub fn Ctx::shows_until(self : Ctx, t : Double) -> Unit {
  if t > self.clock && t < @double.infinity {
    self.wake_at_time(t, later=true)
  } else {
    part_wake(self.clock, t, true)
  }
}

///|
/// A frame begins (frame_drawn, before what it does again is decided): what read the frame told it changed, and what
/// read a moment come.
fn clock_frame_start(t : Double) -> Unit {
  @signals.start_batch()
  kept_clock.frame.set(@signals.untracked(fn() { kept_clock.frame.get() }) + 1)
  let dues = kept_clock.dues
  let mut n = 0
  while n < dues.length() && dues[n].at <= t {
    dues[n].come.set(true)
    n = n + 1
  }
  if n > 0 {
    let left = dues.length() - n
    for k in 0..<left {
      dues[k] = dues[k + n]
    }
    dues.truncate(left)
  }
  @signals.end_batch()
}

///|
/// The frame is built (parts_frame_end): the moments a part or a row kept that showed reads are the host's wakes (one
/// drawn again asks none itself, its build not run); those nothing reads let go. Not the frame's own: what reads one
/// is built again as it comes, by what read it (its watch, told by clock_frame_start), not the frame anew.
fn clock_frame_end(c : Ctx) -> Unit {
  kept_clock.dues.retain(fn(d) { d.come.watched() })
  dues_wake(c)
}

///|
/// The moments a part or a row kept waits for asked of the host: the soonest is the frame's wake, where it is sooner
/// (a frame drawn from the last build's tree too: frame_watch.mbt).
fn dues_wake(c : Ctx) -> Unit {
  for d in kept_clock.dues {
    if d.at > c.clock {
      if c.wake_at < 0.0 || d.at < c.wake_at {
        c.wake_at = d.at
      }
      if !d.later && (c.wake_waited < 0.0 || d.at < c.wake_waited) {
        c.wake_waited = d.at
      }
    }
  }
}


///|
/// Instances painted before (the first `floats` numbers of `insts`, the pieces of their shapes `segs`) drawn again,
/// where they were: their shapes' pieces among this frame's, their glass frosting captures of this frame's.
fn Ctx::insts_replay(self : Ctx, insts : FixedArray[Double], floats : Int, segs : Array[Double]) -> Unit {
  let count = floats / inst_size
  while (self.ninst + count + 1) * inst_size > self.inst.length() {
    self.grow()
  }
  let i0 = self.ninst
  let a = self.inst
  let base = i0 * inst_size
  insts.blit_to(a, len=floats, dst_offset=base)
  let seg0 = (self.segs.length() / 4).to_double()
  self.segs.append(segs)
  let caps : Map[Int, Int] = {}
  for j in 0..<count {
    let b = base + j * inst_size
    let kind = a[b + 5]
    if kind == 11.0 {
      a[b + 12] = a[b + 12] + seg0
    } else if (kind == 5.0 || kind == 6.0) && a[b + 20] < 0.0 {
      // (a capture of its own in this frame, as it took one of its own in its build's)
      let was = (-a[b + 20]).to_int()
      let now = match caps.get(was) {
        Some(n) => n
        None => {
          glass_paint.run = glass_paint.run + 1
          caps[was] = glass_paint.run
          glass_paint.run
        }
      }
      a[b + 20] = -now.to_double()
      if kind == 5.0 {
        glass_paint.frost_run = now
      }
      glass_paint.run_start = -1
      glass_paint.run_len = 0
    }
  }
  self.ninst = i0 + count
  // A saved frame is painted by this node, as a kept drawing is. The instance slots can have belonged to different
  // nodes in the previous frame; leaving their owners there assigns the saved glyphs to unrelated current words.
  if inst_owners_kept() {
    for k in i0..<self.ninst {
      inst_owned(k)
    }
  }
}

///|
/// Where what is laid out in node `i` can show (x0, y0, x1, y1): what holds it all (the window, a layer over it), cut by
/// each box round it that clips, as laid out.
fn Ctx::shown_at(self : Ctx, i : Int) -> (Double, Double, Double, Double) {
  let mut x0 = -@double.infinity
  let mut y0 = -@double.infinity
  let mut x1 = @double.infinity
  let mut y1 = @double.infinity
  let mut j = self.nodes[i].parent
  while j >= 0 {
    let n = self.nodes[j]
    if n.clip || n.parent < 0 {
      x0 = dmax(x0, n.x)
      y0 = dmax(y0, n.y)
      x1 = dmin(x1, n.x + n.fw)
      y1 = dmin(y1, n.y + n.fh)
    }
    j = n.parent
  }
  (x0, y0, x1, y1)
}

///|
/// Every part and row kept built anew from the next build: what they show changed by what they do not read (the
/// screen's corners as the host first says them).
pub fn Ctx::forget_parts(self : Ctx) -> Unit {
  for _, rn in kept_nodes {
    rn.watch.touch()
  }
  ignore(self)
}
