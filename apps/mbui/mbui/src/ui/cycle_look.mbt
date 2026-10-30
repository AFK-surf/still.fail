// A look by the clock (Ctx::cycle_look): what a mark that never ends while it is shown changes as its cycle goes on (a
// spinner's turn, the spokes' step, a waiting dot's breath, a beat), worked out where the frame's drawing ends, not
// where it is built. Its build reads no time: what holds it (a part kept, a list's row) is kept while nothing else it
// shows changes, drawn again as its build drew it, and only its look moves on (Compose's graphicsLayer read as it is
// drawn, Flutter's transitions on a render object, mygo's paint parts painted again: none builds anew for time
// alone). (Built again each step, a chat's spokes built the panel they are in again ten times a second: on a phone,
// its whole sidebar, 10 ms each.)
//
// What its node draws is tagged as it is painted (instance slot 20, the picture's: none for what it tags, rects,
// glyphs, shadows, lines and shapes), and the tag goes wherever the instances go: into a part's or a row's recording,
// drawn again, moved, put in a clip, put over everything. As the frame's paint ends, each tagged instance takes the
// look its cycle gives now, its tag let go: its opacity times the look's, scaled and turned about the middle of what
// the node drew (all its instances' rects together, as it is drawn there), moved by the look's offset. A recording
// keeps the cycles of the tags it holds (KeptPart's `cycles`), so a look drawn again goes on from the cycle its build
// said. Pictures, glass and native views in it are drawn as they are.
// A frame where nothing but these looks changed is of them alone: the last frame's instances, each look applied at its
// time, nothing built, laid out or painted (frame_watch.mbt).

///|
/// A look by the clock: a cycle of `period` ms, stepping on the resident clock (`resident`, Ctx::cycle's) or each
/// frame; held at its start while motion is reduced (`held`); what `look` gives where the cycle is (0 to 1).
priv struct CycleLook {
  period : Double
  resident : Bool
  held : Bool
  look : (Double) -> Look
  loc : SourceLoc
}

///|
/// The cycles of the tags drawn this frame (painted or drawn again), by tag.
// kept across runs: emptied as each frame's paint begins (cycle_looks_begin)
let cycle_frame : Map[Int, CycleLook] = {}

///|
/// The last tag given (they are not given again: a recording keeps its own).
// kept across runs: only counts on, a tag being any number not given before
let cycle_tagged : Ref[Int] = Ref(0)

///|
/// Node `i` drawn with what `look` gives where a cycle of `period` ms is (0 to 1, as Ctx::cycle reads it; `resident`:
/// on the resident clock's steps, a frame each, none between), over any look it has: worked out as each frame's
/// drawing ends, never read as it is built, so what holds it is not built again for it. Held at the cycle's start
/// while motion is reduced (`held`). Scaled and turned about the middle of what it draws. Said as a cycle
/// (Tester::cycles): what never ends while shown.
#callsite(autofill(loc))
pub fn Ctx::cycle_look(
  self : Ctx,
  i : Int,
  period : Double,
  look : (Double) -> Look,
  resident? : Bool = false,
  held? : Bool = false,
  loc~ : SourceLoc,
) -> Unit {
  if period <= 0.0 || i < 0 {
    return
  }
  self.tick_said(true, period, loc, node=i)
  self.drawn_of(i).cycle = Some(CycleLook::{ period, resident, held, look, loc })
}

///|
/// As each frame's paint begins: no cycle drawn yet.
fn cycle_looks_begin() -> Unit {
  cycle_frame.clear()
}

///|
/// Whether an instance of `kind` takes a tag: what it is drawn of is its rect, its colour and its corners (no picture,
/// glass or native view, whose slot 20 is theirs).
fn cycle_takes(kind : Double) -> Bool {
  kind == 0.0 || kind == 1.0 || kind == 2.0 || kind == 3.0 || kind == 10.0 || kind == 11.0
}

///|
/// Instances `i0` to `i1` of `a`, what a node with cycle `cy` drew, tagged with a new tag (those tagged already, by a
/// cycle look inside it, keep theirs).
fn cycle_tag(a : FixedArray[Double], i0 : Int, i1 : Int, cy : CycleLook) -> Unit {
  cycle_tagged.val = cycle_tagged.val + 1
  let tag = cycle_tagged.val
  cycle_frame[tag] = cy
  for q in i0..<i1 {
    let b = q * inst_size
    if cycle_takes(a[b + 5]) && a[b + 20] == 0.0 {
      a[b + 20] = -tag.to_double()
    }
  }
}

///|
/// The tag instance `b` of `a` has (0: none).
fn cycle_tag_of(a : FixedArray[Double], b : Int) -> Int {
  if a[b + 20] < 0.0 && cycle_takes(a[b + 5]) {
    (-a[b + 20]).to_int()
  } else {
    0
  }
}

///|
/// Where cycle `cy` is at `now` (0 to 1), and the moment its next step is drawn at (-1: each frame; infinity: none,
/// held).
fn CycleLook::at(self : CycleLook, now : Double) -> (Double, Double) {
  // (a frame measured for contrast: each loop at its start: contrast.mbt)
  if inst_owners.on || (self.held && reduced_motion()) {
    return (0.0, @double.infinity)
  }
  if self.resident {
    let step = (now / cycle_step_ms).floor()
    let p = step * cycle_step_ms / self.period
    (p - p.floor(), (step + 1.0) * cycle_step_ms)
  } else {
    let p = now / self.period
    (p - p.floor(), -1.0)
  }
}

///|
/// The frame's paint over: each tagged instance drawn with the look its cycle gives now, its tag let go; the frame
/// its cycle draws next asked for (a step's, or the next frame), said as a cycle.
fn Ctx::cycle_looks(self : Ctx) -> Unit {
  if cycle_tagged.val == 0 {
    return
  }
  let a = self.inst
  // what each tag's instances cover, together (x0 y0 x1 y1)
  let boxes : Map[Int, (Double, Double, Double, Double)] = {}
  for q in 0..<self.ninst {
    let b = q * inst_size
    let tag = cycle_tag_of(a, b)
    if tag == 0 {
      continue
    }
    let (x0, y0, x1, y1) = (a[b], a[b + 1], a[b] + a[b + 2], a[b + 1] + a[b + 3])
    match boxes.get(tag) {
      Some((u0, v0, u1, v1)) => boxes[tag] = (dmin(u0, x0), dmin(v0, y0), dmax(u1, x1), dmax(v1, y1))
      None => boxes[tag] = (x0, y0, x1, y1)
    }
  }
  if boxes.is_empty() {
    return
  }
  let looks : Map[Int, Look] = {}
  for tag, _ in boxes {
    match cycle_frame.get(tag) {
      Some(cy) => {
        let (f, next) = cy.at(self.clock)
        looks[tag] = (cy.look)(f)
        if !self.cycles.iter().any(fn(c) { c.1.to_string() == cy.loc.to_string() }) {
          self.cycles.push((cy.period, cy.loc))
        }
        if next < 0.0 {
          self.cycling = true
          looks_own.cycling = true
        } else if next < @double.infinity {
          self.wake_at_time(next, later=true)
        }
      }
      // (a drawing kept without its cycle: a row's copy as it leaves, drawn as it was)
      None => ()
    }
  }
  for q in 0..<self.ninst {
    let b = q * inst_size
    let tag = cycle_tag_of(a, b)
    if tag == 0 {
      continue
    }
    a[b + 20] = 0.0
    match looks.get(tag) {
      Some(l) => {
        let (x0, y0, x1, y1) = boxes[tag]
        look_inst(a, b, l, x0 + l.ox * (x1 - x0), y0 + l.oy * (y1 - y0))
      }
      None => ()
    }
  }
}

///|
/// Instance `b` of `a` drawn with look `l` about (`px`, `py`): its opacity times the look's (its border's too), scaled
/// about the point and moved, then turned about it where it is moved to. What cuts it stays: it came from outside what
/// the look is of (a cycle look draws a mark, inside what it is in).
fn look_inst(a : FixedArray[Double], b : Int, l : Look, px : Double, py : Double) -> Unit {
  let kind = a[b + 5]
  if l.alpha != 1.0 {
    a[b + 11] = a[b + 11] * l.alpha
    // (a rect's border colour)
    if kind == 0.0 {
      a[b + 15] = a[b + 15] * l.alpha
    }
  }
  let scales = l.sx != 1.0 || l.sy != 1.0
  if scales || l.dx != 0.0 || l.dy != 0.0 {
    a[b] = px + (a[b] - px) * l.sx + l.dx
    a[b + 1] = py + (a[b + 1] - py) * l.sy + l.dy
    if a[b + 32] != 0.0 {
      a[b + 33] = px + (a[b + 33] - px) * l.sx + l.dx
      a[b + 34] = py + (a[b + 34] - py) * l.sy + l.dy
    }
  }
  if scales {
    let sm = dmin(l.sx, l.sy)
    a[b + 2] = a[b + 2] * l.sx
    a[b + 3] = a[b + 3] * l.sy
    a[b + 4] = a[b + 4] * sm
    for j in 36..<40 {
      a[b + j] = a[b + j] * sm
    }
    a[b + 6] = a[b + 6] * sm
    a[b + 7] = a[b + 7] * sm
    // a rect's notch (scene.mbt)
    if kind == 0.0 {
      a[b + 21] = a[b + 21] * sm
      a[b + 22] = a[b + 22] * sm
      a[b + 23] = a[b + 23] * sm
    }
  }
  if l.rot != 0.0 {
    // (its clip where it is drawn: from outside the look's)
    turn_insts(a, b / inst_size, b / inst_size + 1, l.rot, px + l.dx, py + l.dy, (
      a[b + 16],
      a[b + 17],
      a[b + 18],
      a[b + 19],
    ))
  }
}
