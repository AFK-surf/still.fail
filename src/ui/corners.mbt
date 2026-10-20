// still.fail's corner rule, measured (its docs/ui-panels.md, "所有带圆角的东西"): what has a ground of its own (a
// button, a row, a field, a block) and lies in the corner of a rounded container stands as far from the two edges of
// that corner, and its corner is the container's less that distance (concentric); a circle or a capsule there is as
// far from both, and the container's corner that distance more than its own (the container's fault when not). A
// container's corner is its own ground's, or a ground of its size laid under it as a layer. A test asks the frame it
// drew (Tester::corner_faults); the gallery's components keep to it.

///|
/// Whether node `n` shows a ground of its own (a fill or an edge) and is drawn.
fn Node::grounded(self : Node) -> Bool {
  self.kind == kind_box &&
  self.opacity > 0.01 &&
  self.fw > 0.0 &&
  self.fh > 0.0 &&
  ((self.bg & 0xFFL) != 0L || (self.border_w > 0.0 && (self.border_c & 0xFFL) != 0L))
}

///|
/// The corner a node draws: its radius, at most half its shorter side.
fn Node::corner(self : Node) -> Double {
  dmin(self.radius, dmin(self.fw, self.fh) / 2.0)
}

///|
/// Where the last frame breaks the corner rule (see the file's head): one line for each grounded node in a rounded
/// container's corner that is not as far from both edges, or not concentric (within half a pixel).
pub fn Tester::corner_faults(self : Tester) -> Array[String] {
  ignore(self)
  let c = g()
  // the corners said `Inner` that could not be worked out (corners_after_layout), first
  let out : Array[String] = c.inner_faults.copy()
  let grounds = c.layer_grounds()
  for i in 0..<c.count {
    let b = c.nodes[i]
    if !b.grounded() || b.layer {
      continue
    }
    let (p, ra, ground) = match c.corner_container(i, grounds) {
      Some(found) => found
      None => continue
    }
    // the container's own ground drawn on (the same fill, no edge: a grouped row's square patch over its rounded
    // corners): its shape, not something in its corner
    let gn = c.nodes[ground]
    if b.bg == gn.bg && b.border_w <= 0.0 && gn.glass is None {
      continue
    }
    let a = c.nodes[p]
    let rb = b.corner()
    // a whole circle or a capsule (its corner half its shorter side: an avatar, a switch's knob, a dot, a ×) is round
    // by what it is. One the layout centres along an axis is set in a corner only where the container is round all
    // along that axis (a capsule's end: a switch's knob in its track, a send button in a capsule field, a chip's dot):
    // a card's trailing × centred up and down in a card taller than its corners are round is in none
    let round = rb >= dmin(b.fw, b.fh) / 2.0 - 0.5
    if round {
      let (across_y, across_x) = c.centred_in(i, p)
      if (across_y && ra < a.fh / 2.0 - 0.5) || (across_x && ra < a.fw / 2.0 - 0.5) {
        continue
      }
    }
    let l = b.x - a.x
    let t = b.y - a.y
    let r = a.x + a.fw - (b.x + b.fw)
    let d = a.y + a.fh - (b.y + b.fh)
    for k, (dx, dy) in [(l, t), (r, t), (l, d), (r, d)] {
      if dx < -0.5 || dy < -0.5 || dx >= ra || dy >= ra {
        continue
      }
      // flush in the corner of something between it and the container that cuts with a rounded corner (a clip=true
      // box with a corner, cut along it since mbui#42): what shows of it there is the cut's corner, not its own
      if c.cut_round_at(i, p, k) {
        continue
      }
      let even = (dx - dy).abs() <= 0.5
      // a round one at a corner: it is the container whose corner follows it (ui-panels.md: 外圆角 = 距离 + 半高), the
      // fault the container's when it does not
      let concentric = (rb - (ra - dmax(dx, dy))).abs() <= 0.5
      if !(even && concentric) {
        let corner = ["top left", "top right", "bottom left", "bottom right"][k]
        out.push(
          if round && even {
            "\{c.named(p)} (corner \{ra}): wants corner \{dmax(dx, dy) + rb}, for \{c.named(i)} (round, corner \{rb}) in its \{corner}, \{dx} from both edges"
          } else {
            "\{c.named(i)} (corner \{rb}) in the \{corner} of \{c.named(p)} (corner \{ra}): \{dx} and \{dy} from its edges" +
            (if concentric || round { "" } else { ", wants corner \{ra - dmax(dx, dy)}" })
          },
        )
      }
    }
  }
  out
}

///|
/// Node `i` as a fault names it: the words built in it, else its nearest container's that has any (said so), where
/// it is and how large, and its number in the frame.
fn Ctx::named(self : Ctx, i : Int) -> String {
  let n = self.nodes[i]
  let place = "at \{n.x.round()},\{n.y.round()} \{n.fw.round()}×\{n.fh.round()}, node \{i}"
  match self.words_cut(i) {
    Some(w) => "「\{w}」 (\{place})"
    None => {
      let mut p = n.parent
      while p >= 0 {
        match self.words_cut(p) {
          Some(w) => return "a box in 「\{w}」 (\{place})"
          None => p = self.nodes[p].parent
        }
      }
      "a box (\{place})"
    }
  }
}

///|
/// The words built in node `i` (semantics.mbt's), cut to 24 characters; None when it has none.
fn Ctx::words_cut(self : Ctx, i : Int) -> String? {
  let w = self.words_in(i)
  if w == "" {
    return None
  }
  let sb = StringBuilder()
  let mut count = 0
  for ch in w {
    if count == 24 {
      sb.write_string("…")
      break
    }
    sb.write_char(ch)
    count += 1
  }
  Some(sb.to_string())
}

///|
/// Whether node `i` is laid out centred by something between it and its container `p`: up and down (a row centring
/// what it holds across, a column centring it along), and side to side (a column across, a row along).
fn Ctx::centred_in(self : Ctx, i : Int, p : Int) -> (Bool, Bool) {
  let mut y = false
  let mut x = false
  let mut n = i
  while n >= 0 && n != p {
    let q = self.nodes[n].parent
    if q < 0 {
      break
    }
    let pq = self.nodes[q]
    let across = pq.align == ACenter
    let along = pq.justify == JCenter
    match pq.dir {
      Row => {
        y = y || across
        x = x || along
      }
      Column => {
        x = x || across
        y = y || along
      }
    }
    n = q
  }
  (y, x)
}
///|
/// The rounded container node `i` lies in, as the corner rule sees it: the nearest round it that shows (a ground, an
/// edge, glass, or what it cuts) with a corner of 6 or more, its own or one laid under it as a layer of the same size
/// (a composer's glass drawn beside what it holds: `grounds`, Ctx::layer_grounds). Its node, its corner, the node whose
/// ground that corner is; None when there is none. Tester::corner_faults and `Inner` (corners_after_layout) both ask
/// this, so they measure against the same container.
fn Ctx::corner_container(self : Ctx, i : Int, grounds : Map[Int, Int]) -> (Int, Double, Int)? {
  let mut p = self.nodes[i].parent
  while p >= 0 {
    let a = self.nodes[p]
    if a.kind == kind_box && a.corner() >= 6.0 && (a.grounded() || a.glass is Some(_) || a.clip) {
      return Some((p, a.corner(), p))
    }
    match grounds.get(p) {
      Some(gi) if gi != i => return Some((p, self.nodes[gi].corner(), gi))
      _ => ()
    }
    p = a.parent
  }
  None
}

///|
/// The rounded grounds laid as layers the size of what they are under: for a box, the rounded node (a fill, an edge or
/// glass) of its own size below it, through boxes all of that size (the composer's glass, a card's ground drawn
/// apart from what it holds): the box's corner is that ground's.
fn Ctx::layer_grounds(self : Ctx) -> Map[Int, Int] {
  let out : Map[Int, Int] = Map::new()
  for gi in 0..<self.count {
    let gn = self.nodes[gi]
    if gn.kind != kind_box || gn.corner() < 6.0 || !(gn.grounded() || gn.glass is Some(_)) {
      continue
    }
    let mut n = gi
    while self.nodes[n].parent >= 0 {
      let q = self.nodes[n].parent
      let qn = self.nodes[q]
      if (qn.x - gn.x).abs() > 0.5 ||
        (qn.y - gn.y).abs() > 0.5 ||
        (qn.fw - gn.fw).abs() > 0.5 ||
        (qn.fh - gn.fh).abs() > 0.5 {
        break
      }
      if !out.contains(q) {
        out[q] = gi
      }
      n = q
    }
  }
  out
}

///|
/// How far apart two of a box's distances from its container's edges may be and still be one (half a pixel, as
/// corner_faults measures).
let inner_even : Double = 0.5

///|
/// The corners said `Inner` (style.mbt), from where their boxes lie as laid out (the covers moved: after
/// covers_after_layout, before anything is painted or its clip and hit target recorded): the corner of the container
/// the corner rule measures against (corner_container: through boxes with no corner, a ground laid beside as a layer)
/// less the box's distance from that container's edges it is near (nearer than the container's corner is round),
/// those distances the same; so the box is concentric with it by how it is written, and corner_faults finds nothing
/// in it. In the order they were built, a container `Inner` itself worked out first. A box in no rounded container,
/// near none of its edges, or near edges at different distances (the window narrowed, a max_w come into force) is
/// drawn square, and said so: corner_faults lists it, so a test fails where a person's screen would not.
fn Ctx::corners_after_layout(self : Ctx) -> Unit {
  self.inner_faults.clear()
  if self.inners.is_empty() {
    return
  }
  let grounds = self.layer_grounds()
  for i in self.inners {
    let n = self.nodes[i]
    n.radius = 0.0
    let (p, ra, _) = match self.corner_container(i, grounds) {
      Some(found) => found
      None => {
        self.inner_faults.push("\{self.named(i)}: radius=Inner, in no rounded container")
        continue
      }
    }
    let a = self.nodes[p]
    let sides = [
      ("left", n.x - a.x),
      ("top", n.y - a.y),
      ("right", a.x + a.fw - (n.x + n.fw)),
      ("bottom", a.y + a.fh - (n.y + n.fh)),
    ]
    // (an edge it reaches past is no edge of its: it is cut there, as corner_faults leaves out a corner it overhangs)
    let near = sides.filter(fn(s) { s.1 >= -inner_even && s.1 < ra })
    if near.is_empty() {
      self.inner_faults.push(
        "\{self.named(i)}: radius=Inner, near none of the edges of \{self.named(p)} (corner \{ra})",
      )
      continue
    }
    let d = near[0].1
    if near.iter().any(fn(s) { (s.1 - d).abs() > inner_even }) {
      let said = near.map(fn(s) { "\{s.0} \{s.1}" }).join(", ")
      self.inner_faults.push(
        "\{self.named(i)}: radius=Inner, at different distances from the edges of \{self.named(p)} (corner \{ra}): \{said}",
      )
      continue
    }
    n.radius = dmax(ra - d, 0.0)
  }
}

///|
/// Whether what shows at node `i`'s corner `k` (0 top left, 1 top right, 2 bottom left, 3 bottom right) is the arc of a
/// box between it and its container `p` (`p` included) that cuts what it holds with a rounded corner (clip, a corner of
/// its own): the node's own arc there lies wholly outside the cut's circle (within half a pixel), so the cut's arc
/// bounds it (a square corner flush along its edge, a capsule's fill as round as it). Its arc measured at 16 fixed
/// directions over the quarter toward the corner; one point inside the cut's circle and its own arc shows: checked as
/// any other.
fn Ctx::cut_round_at(self : Ctx, i : Int, p : Int, k : Int) -> Bool {
  let b = self.nodes[i]
  let rb = b.corner()
  let mut q = b.parent
  while q >= 0 {
    let n = self.nodes[q]
    let r = n.corner()
    if n.clip && r >= 0.5 {
      // the corner's own frame: the cut's corner at the origin, inward positive; the cut's circle about (r, r)
      let dx = if k == 0 || k == 2 { b.x - n.x } else { n.x + n.fw - (b.x + b.fw) }
      let dy = if k < 2 { b.y - n.y } else { n.y + n.fh - (b.y + b.fh) }
      if dx >= -0.5 && dy >= -0.5 && dx < r && dy < r {
        let mut outside = true
        for j in 0..<cut_arc_steps {
          let a = half_pi * j.to_double() / (cut_arc_steps - 1).to_double()
          let px = dx + rb - rb * @math.cos(a)
          let py = dy + rb - rb * @math.sin(a)
          let ex = px - r
          let ey = py - r
          if (ex * ex + ey * ey).sqrt() < r - 0.5 {
            outside = false
            break
          }
        }
        if outside {
          return true
        }
      }
    }
    if q == p {
      break
    }
    q = n.parent
  }
  false
}

///|
/// How many directions a node's corner arc is measured at against a cut's circle (cut_round_at): fixed, so the answer is
/// the same every run.
let cut_arc_steps : Int = 16

///|
let half_pi : Double = 1.5707963267948966
