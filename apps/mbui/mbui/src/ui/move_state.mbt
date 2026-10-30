// A change of state moved to, not jumped to: the web's moveState (still.fail web/ui/src/motion.ts). Boxes are named to
// be moved (Ctx::box `moves`, the web's selector); a move says which of their properties go (their CSS names, as the
// web lists them) and sets out once (Ctx::move_state). From then the view builds the new state as usual, and each box
// so named is shown from what it showed as the move set out to what it is built as now, all of them on one clock and
// curve. What the view builds stays the truth: a move holds nothing once it ends. Said again over one going on, it
// goes on from wherever that had got to. Motion as data (docs/determinism.md): what is shown at a moment is a
// function of that moment, however many frames came between.
//
// Its first frame builds the new state, which may take longer than the display's frame (a page built for the first
// time as it is brought over, its words shaped, its rows laid out): its clock does not run while that frame is late to
// the screen (the host says how late: @hostapi.frame_late), up to nav_late_most, so it moves from where that frame drew
// it at the display's pace, no step skipped, the wait before it moves instead (as a stack's slide does: nav.mbt; as
// the web's transitions start once their first frame is drawn); and so for each frame after it late one after
// another (what it shows built over more than one: a native view made as it is laid where it goes).

///|
/// The properties a move takes, by their CSS names (one name may stand for several: `margin` for its four,
/// `box-shadow` for the blur, the fall and the colour). A size moves only between two of the same kind (points or a
/// share); between others (what it holds, what is left) it is at once what it is built as.
// kept across runs: a table, never written
let move_props : Map[String, Array[Int]] = {
  "width": [0],
  "height": [1],
  "min-width": [2],
  "max-width": [3],
  "min-height": [4],
  "max-height": [5],
  "margin-left": [6],
  "margin-inline-start": [6],
  "margin-top": [7],
  "margin-right": [8],
  "margin-inline-end": [8],
  "margin-bottom": [9],
  "margin": [6, 7, 8, 9],
  "padding-left": [10],
  "padding-inline-start": [10],
  "padding-top": [11],
  "padding-right": [12],
  "padding-inline-end": [12],
  "padding-bottom": [13],
  "padding": [10, 11, 12, 13],
  "left": [14],
  "top": [15],
  "right": [16],
  "bottom": [17],
  "inset": [14, 15, 16, 17],
  "gap": [18],
  "background-color": [19],
  // (each corner its own: top left, top right, bottom right, bottom left)
  "border-radius": [20, 29, 30, 31],
  "border-width": [21],
  "border-color": [22],
  "box-shadow": [23, 24, 25],
  "opacity": [26],
  "transform": [27, 28],
}

///|
/// How many numbers a box is shown as (move_props' indices), and where a size's kind is kept.
let move_count : Int = 32

///|
let move_w_kind : Int = 32

///|
let move_h_kind : Int = 33

///|
/// The properties that are colours (0xRRGGBBAA), mixed as the web's motion mixes them.
fn move_is_colour(k : Int) -> Bool {
  k == 19 || k == 22 || k == 25
}

///|
/// What a box named to be moved was shown as: its properties' numbers (move_props' indices), its sizes' kinds after
/// them; or a value moved by its own name (Ctx::moved): one number.
struct MoveShown {
  v : FixedArray[Double]
}

///|
/// A move going on: when it set out, for how long, by what curve; what of each name it moves (indices into
/// move_props' numbers), the values it moves (their `--` names); where the boxes and values were shown as it set out.
/// Its start moved on by how late its first frame reached the screen: whether that is still to be, and that frame's
/// time (-1: not drawn yet).
struct MoveRun {
  who : Mover
  mut start : Double
  /// how long: as said, or a Move's over the furthest any of its boxes goes (`far`, in points, found as they are
  /// built in the first frame that builds them anew, `far_frame`: its new state may come a frame or more after it is
  /// said, a page brought over once it shows), solved in the frame after (`solved`)
  mut dur : Double
  mut far : Double
  mut far_frame : Int
  mut solved : Bool
  ease : Ease
  names : Map[String, FixedArray[Bool]]
  vars : Array[String]
  from : Map[String, MoveShown]
  mut waits_late : Bool
  mut late_at : Double
}

///|
impl Moving for MoveRun with rest_at(self, now, frame) {
  ignore(now)
  ignore(frame)
  self.ends()
}

///|
/// When it is over: as long as its way is far, as far as it is known (said again each frame: a way found later is
/// longer).
fn MoveRun::ends(self : MoveRun) -> Double {
  self.start + self.dur
}

///|
/// Box (or value) `key` built as `to` while it goes, from `from`: how far it goes counted (the points of what it moves
/// of it: a size in points, a margin, a padding, a side, a gap, a shift; not a colour, a corner, an opacity), in the
/// first frame that builds it otherwise than it was.
fn MoveRun::count_far(self : MoveRun, on : FixedArray[Bool]?, from : FixedArray[Double], to : FixedArray[Double], frame : Int) -> Unit {
  if self.solved || (self.far_frame >= 0 && frame > self.far_frame) {
    return
  }
  let n = if on is None { 1 } else { move_count }
  for k in 0..<n {
    let moves = match on {
      Some(on) => on[k] && (k <= 18 || k == 27 || k == 28)
      None => true
    }
    if !moves {
      continue
    }
    let a = from[k]
    let b = to[k]
    // (none said, or none to it: a max of none)
    if a.is_nan() || b.is_nan() || a.is_inf() || b.is_inf() {
      continue
    }
    if (k == 0 || k == 1) && on is Some(_) {
      let kind = if k == 0 { move_w_kind } else { move_h_kind }
      if from[kind] != 1.0 || to[kind] != 1.0 {
        continue
      }
    }
    if (b - a).abs() > 0.0 {
      self.far = dmax(self.far, (b - a).abs())
      if self.far_frame < 0 {
        self.far_frame = frame
      }
    }
  }
  if !self.solved {
    self.dur = move_ms(self.far)
  }
}

///|
/// Handed each frame's time: each frame after its first, told how late the one before was to the screen, its start
/// moved on that much (nav_late_most at most each), as long as they are late one after another; the first on time, it
/// waits no more. (Its new state may take more than one frame to build: a page built as it is brought over, then its
/// native view made as it is laid where it goes; each late frame its clock ran past would show as a step skipped.)
impl Moving for MoveRun with sample(self, now) {
  if !self.waits_late {
    return
  }
  if self.late_at < 0.0 {
    self.late_at = now
  } else if now > self.late_at {
    let late = dmin(h_frame_late(), nav_late_most)
    if late > 0.0 {
      self.start = self.start + late
      self.late_at = now
    } else {
      self.waits_late = false
    }
  }
}

///|
/// How far the move has gone at `now` (its curve's, 0 as it set out, 1 from its end on), in `frame`: its length solved
/// from the frame after the one that built what it moves (till then, as long as what that has found so far takes).
fn MoveRun::at(self : MoveRun, now : Double, frame : Int) -> Double {
  if !self.solved {
    if self.far_frame >= 0 && frame > self.far_frame {
      self.solved = true
    }
    self.dur = move_ms(self.far)
  }
  let t = whole_ms(now - self.start)
  if t <= 0.0 {
    0.0
  } else if t >= self.dur || self.dur <= 0.0 {
    1.0
  } else {
    self.ease.at(t / self.dur)
  }
}

///|
/// The properties of `moves` (each a box's name and the CSS names of what of it moves, as the web's moveState lists
/// them) move from what they are shown as now to what the view builds from now on, together, over `duration` ms on
/// `ease` (by default a Move as long as the furthest of them goes: move_ms). Said as the state changes: in the handler that changes it,
/// before or after. A value of the view's own goes with them where a box lists it by its `--` name (Ctx::moved). A box
/// shown for the first time as it sets out is at once what it is built as; with motion reduced (Ctx::still) every box
/// is. Its clock waits as long as its first frame is late to the screen (nav_late_most at most).
#callsite(autofill(loc))
pub fn Ctx::move_state(
  self : Ctx,
  moves : Array[(String, Array[String])],
  duration? : Double,
  ease? : Ease = Move,
  loc~ : SourceLoc,
) -> Unit {
  if self.still() {
    return
  }
  let names : Map[String, FixedArray[Bool]] = {}
  let vars : Array[String] = []
  for m in moves {
    let (name, props) = m
    let on = match names.get(name) {
      Some(on) => on
      None => {
        let on = FixedArray::make(move_count, false)
        names[name] = on
        on
      }
    }
    for p in props {
      if p.has_prefix("--") {
        if !vars.contains(p) {
          vars.push(p)
        }
        continue
      }
      match move_props.get(p) {
        Some(ks) => for k in ks { on[k] = true }
        None => abort("move_state: \{name}'s \{p} is no property a box moves by")
      }
    }
  }
  // what was shown as it sets out: in a frame, the last frame's (what this build has built so far may be the new
  // state already); between frames, the last frame's is what this frame's builds made
  let from = if self.in_frame() { self.shown_last } else { self.shown_now }
  // (the moment it is said: this frame's, or between frames the clock's then, a frame asked for to show it)
  let start = if self.in_frame() {
    self.clock
  } else {
    self.owe_frame()
    h_now()
  }
  let who = Mover::new()
  // (its first frame: this one, said in it; else the next drawn, as it is handed its time)
  let late_at = if self.in_frame() { start } else { -1.0 }
  let run : MoveRun = {
    who,
    start,
    dur: duration.unwrap_or(move_ms(0.0)),
    far: 0.0,
    far_frame: -1,
    solved: duration is Some(_),
    ease,
    names,
    vars,
    from,
    waits_late: true,
    late_at,
  }
  self.moving_as(who, run as &Moving, "a move of \{names.keys().collect()} set out at \{loc}")
  self.move_runs.push(run)
}

///|
/// A value of the view's own, `name` (a `--` name, as the web's custom properties), as shown now: `target`, or where a
/// move listing it (Ctx::move_state) has got from what it was shown as when that set out. Read while that goes on, what
/// is built from it changes each frame: a part kept that reads it is built each frame until it is over (kept_part.mbt).
pub fn Ctx::moved(self : Ctx, name : String, target : Double) -> Double {
  let mut v = target
  let mut k = self.move_runs.length() - 1
  while k >= 0 {
    let run = self.move_runs[k]
    if run.vars.contains(name) {
      match run.from.get(name) {
        Some(f) => {
          run.count_far(None, f.v, FixedArray::make(1, target), self.frame_no)
          let p = run.at(self.now(), self.frame_no)
          v = f.v[0] + (target - f.v[0]) * p
          if p < 1.0 {
            part_live()
          }
        }
        None => ()
      }
      break
    }
    k = k - 1
  }
  let shown = FixedArray::make(1, v)
  self.shown_now[name] = { v: shown }
  // (held by what is being built: a row kept says it again from its nodes, moves_said_again)
  if self.cur >= 0 {
    let n = self.nodes[self.cur]
    match n.moved_vars {
      Some(vs) => vs.push((name, shown))
      None => n.moved_vars = Some([(name, shown)])
    }
  }
  v
}

///|
/// What the nodes `from` until `to` showed as they were built (a list's row or a part kept as its nodes, put back
/// unbuilt: kept_nodes.mbt), said again as their builds said it: the boxes named to be moved, in order, and the values
/// of the view's own shown in them.
fn Ctx::moves_said_again(self : Ctx, from : Int, to : Int) -> Unit {
  for i in from..<to {
    let n = self.nodes[i]
    if n.moves != "" {
      let nth = self.move_seen.get(n.moves).unwrap_or(0)
      self.move_seen[n.moves] = nth + 1
      let key = if n.id != 0 { n.moves + "\u{1}#\{n.id}" } else { n.moves + "\u{1}\{nth}" }
      self.shown_now[key] = { v: node_shown(n) }
    }
    match n.moved_vars {
      Some(vs) =>
        for v in vs {
          self.shown_now[v.0] = { v: v.1 }
        }
      None => ()
    }
  }
}

///|
/// A frame begins: what this frame's builds show becomes the last frame's, and the moves that ended are let go.
fn Ctx::moves_frame_start(self : Ctx) -> Unit {
  self.shown_last = self.shown_now
  self.shown_now = {}
  let now = self.clock
  self.move_runs.retain(fn(r) { r.ends() > now })
}

///|
/// A build begins: none of the names built yet (what it shows replaces what an earlier build of the frame showed).
fn Ctx::moves_build_start(self : Ctx) -> Unit {
  self.shown_now = {}
  self.move_seen.clear()
}

///|
/// Box `i`, named to be moved (`moves`), is built: shown where the newest move of each of its properties has got to,
/// and what it is shown as kept for a move setting out later.
fn Ctx::move_node(self : Ctx, i : Int) -> Unit {
  let n = self.nodes[i]
  let name = n.moves
  let nth = self.move_seen.get(name).unwrap_or(0)
  self.move_seen[name] = nth + 1
  // (a box with an id is itself whatever was built before it; others are the nth so named)
  let key = if n.id != 0 { name + "\u{1}#\{n.id}" } else { name + "\u{1}\{nth}" }
  let built = node_shown(n)
  let shown = built.copy()
  if self.move_runs.length() > 0 {
    for k in 0..<move_count {
      match self.move_of(name, k) {
        Some(run) =>
          match run.from.get(key) {
            Some(f) => {
              run.count_far(run.names.get(name), f.v, built, self.frame_no)
              let p = run.at(self.now(), self.frame_no)
              shown[k] = move_mix(k, f.v, built, p)
              // (shown otherwise each frame while it goes: what holds it, kept, built each frame till it is over)
              if p < 1.0 {
                part_live()
              }
            }
            None => ()
          }
        None => ()
      }
    }
    node_show(n, shown)
  }
  self.shown_now[key] = { v: shown }
}

///|
/// The newest move going on that moves property `k` of the boxes named `name`.
fn Ctx::move_of(self : Ctx, name : String, k : Int) -> MoveRun? {
  let mut j = self.move_runs.length() - 1
  while j >= 0 {
    let run = self.move_runs[j]
    match run.names.get(name) {
      Some(on) if on[k] => return Some(run)
      _ => ()
    }
    j = j - 1
  }
  None
}

///|
/// Property `k` at `p` of the way from what `from` shows to what `to` does.
fn move_mix(k : Int, from : FixedArray[Double], to : FixedArray[Double], p : Double) -> Double {
  let a = from[k]
  let b = to[k]
  // (a side not said on either end: what it is built as)
  if a.is_nan() || b.is_nan() {
    return b
  }
  if k == 0 || k == 1 {
    // a size: between two of the same kind, points or a share
    let kind = if k == 0 { move_w_kind } else { move_h_kind }
    if from[kind] != to[kind] || !(to[kind] == 1.0 || to[kind] == 3.0) {
      return b
    }
  }
  if move_is_colour(k) {
    mix_colour(a.to_int64(), b.to_int64(), p).to_double()
  } else {
    a + (b - a) * p
  }
}

///|
/// Two colours (0xRRGGBBAA) mixed as the web's motion mixes them (Motion's mixColor): each channel by its square, the
/// alpha straight.
fn mix_colour(a : Int64, b : Int64, p : Double) -> Int64 {
  let ch = fn(c : Int64, s : Int) { ((c >> s) & 0xFFL).to_double() / 255.0 }
  let one = fn(s : Int) {
    let x = ch(a, s)
    let y = ch(b, s)
    let e = x * x + (y * y - x * x) * p
    let v = if e < 0.0 { 0.0 } else { e.sqrt() }
    (v * 255.0 + 0.5).floor().to_int64()
  }
  let alpha = {
    let x = ch(a, 0)
    let y = ch(b, 0)
    ((x + (y - x) * p) * 255.0 + 0.5).floor().to_int64()
  }
  (one(24) << 24) | (one(16) << 16) | (one(8) << 8) | alpha
}

///|
/// What box `n` is built as, as a move takes it (move_props' indices; its sizes' kinds after them).
fn node_shown(n : Node) -> FixedArray[Double] {
  let v = FixedArray::make(move_count + 2, 0.0)
  let size = fn(s : Size, at : Int, kind : Int) {
    match s {
      Auto | Cut => v[kind] = 0.0
      Px(p) => {
        v[at] = p
        v[kind] = 1.0
      }
      Fill(k) => {
        v[at] = k
        v[kind] = 2.0
      }
      Pct(p) => {
        v[at] = p
        v[kind] = 3.0
      }
    }
  }
  size(n.w, 0, move_w_kind)
  size(n.h, 1, move_h_kind)
  v[2] = n.min_w
  v[3] = n.max_w
  v[4] = n.min_h
  v[5] = n.max_h
  v[6] = n.mar_l
  v[7] = n.mar_t
  v[8] = n.mar_r
  v[9] = n.mar_b
  v[10] = n.pad_l
  v[11] = n.pad_t
  v[12] = n.pad_r
  v[13] = n.pad_b
  v[14] = n.at_l
  v[15] = n.at_t
  v[16] = n.at_r
  v[17] = n.at_b
  v[18] = n.gap
  v[19] = n.bg.to_double()
  v[20] = n.radius_at(0)
  v[29] = n.radius_at(1)
  v[30] = n.radius_at(2)
  v[31] = n.radius_at(3)
  v[21] = n.border_w
  v[22] = n.border_c.to_double()
  v[23] = n.shadow
  v[24] = n.shadow_y
  v[25] = n.shadow_c.to_double()
  v[26] = n.opacity
  v[27] = n.tx
  v[28] = n.ty
  v
}

///|
/// Box `n` shown as `v` says (node_shown's numbers).
fn node_show(n : Node, v : FixedArray[Double]) -> Unit {
  let size = fn(at : Int, kind : Int) -> Size {
    let k = v[kind]
    if k == 1.0 {
      Px(v[at])
    } else if k == 2.0 {
      Fill(v[at])
    } else if k == 3.0 {
      Pct(v[at])
    } else {
      Auto
    }
  }
  n.w = size(0, move_w_kind)
  n.h = size(1, move_h_kind)
  n.min_w = v[2]
  n.max_w = v[3]
  n.min_h = v[4]
  n.max_h = v[5]
  n.mar_l = v[6]
  n.mar_t = v[7]
  n.mar_r = v[8]
  n.mar_b = v[9]
  n.pad_l = v[10]
  n.pad_t = v[11]
  n.pad_r = v[12]
  n.pad_b = v[13]
  n.at_l = v[14]
  n.at_t = v[15]
  n.at_r = v[16]
  n.at_b = v[17]
  n.gap = v[18]
  n.bg = v[19].to_int64()
  n.set_radii(FixedArray::from_array([v[20], v[29], v[30], v[31]]))
  n.border_w = v[21]
  n.border_c = v[22].to_int64()
  n.shadow = v[23]
  n.shadow_y = v[24]
  n.shadow_c = v[25].to_int64()
  n.opacity = v[26]
  n.tx = v[27]
  n.ty = v[28]
}
