// still.fail's corner rule, measured (its docs/ui-panels.md, "所有带圆角的东西"): what has a ground of its own (a
// button, a row, a field, a block) and lies in the corner of a rounded container stands as far from the two edges of
// that corner, and its corner is concentric with the container's (smooth.mbt concentric: the container's less that
// distance over 1.25, both corners smooth); a circle or a capsule there is as far from both, and the container's corner
// that distance more than its own (ui-panels.md: not over 1.25, which would leave a crescent by the capsule; the
// container's fault when not). A
// container's corner is its own ground's, or a ground of its size laid under it as a layer. A test asks the frame it
// drew (Tester::corner_faults); the gallery's components keep to it.
//
// What a page writes is a box's corner standing alone: in a container's corner, a smooth one's is worked out here
// (corners_in_corners), so the concentric part holds by itself wherever the window or what it holds puts a box. What
// is left to a page is where things stand, and which corners there are: the theme's ladder (Theme::corner_ladder), the
// few corners nested things are round by, each the next one in at the ladder's step, and capsules' heights; the
// check holds both to it.

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
/// Whether node `n` is a row pressed as a whole (a press target wider than tall: a list's row, a menu's), whose ground
/// shows while it is pointed at or pressed: what is in it stands in that ground's corner then, not its card's (the web's
/// test/browser/measure.mjs pressedBox the same).
fn Node::pressed_row(self : Node) -> Bool {
  self.kind == kind_box && self.id != 0 && self.hit && self.fw > self.fh * 1.5
}

///|
/// Whether node `p` is a row whose corner says it follows its container's (`Inner`, `InnerOr`: a list's row the
/// ladder's inset in), wider than tall: a row of the list whether it can be pressed or not, what is in it its, as in a
/// pressed row (pressed_row).
fn Ctx::inner_row(self : Ctx, p : Int) -> Bool {
  let n = self.nodes[p]
  if n.fw <= n.fh * 1.5 {
    return false
  }
  // (the inners are in the order they were built: by their numbers)
  let mut lo = 0
  let mut hi = self.inners.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    let x = self.inners[mid]
    if x == p {
      return true
    }
    if x < p {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  false
}

///|
/// The corner a node draws: its radius, at most half its shorter side (the roundest of its corners, where they are each
/// their own).
fn Node::corner(self : Node) -> Double {
  dmin(self.radius, dmin(self.fw, self.fh) / 2.0)
}

///|
/// Its corner `k` as drawn (0 top left, then round it: radius_at's), at most half its shorter side.
fn Node::corner_at(self : Node, k : Int) -> Double {
  dmin(self.radius_at(k), dmin(self.fw, self.fh) / 2.0)
}

///|
/// The rounded container something lies in, as the corner rule sees it (Ctx::corner_container): its node, the node whose
/// ground its corners are (its own, or one of its size laid under it as a layer), and whether it is the window (its
/// corners the system's).
priv struct Container {
  node : Int
  ground : Int
  window : Bool
}

///|
/// Corner `k` of container `ct` (0 top left, then round it): the window's the system's (@hostapi.window_corner), else
/// its ground's, each corner its own.
fn Ctx::container_r(self : Ctx, ct : Container, k : Int) -> Double {
  if ct.window {
    self.window_corner
  } else {
    self.nodes[ct.ground].corner_at(k)
  }
}

///|
/// The roundest of container `ct`'s corners.
fn Ctx::container_most(self : Ctx, ct : Container) -> Double {
  if ct.window {
    self.window_corner
  } else {
    self.nodes[ct.ground].corner()
  }
}

///|
/// What the corners are called, 0 top left, then round it (scene.mbt's, an instance's 36-39).
// kept across runs: a table, never written
let corner_names : Array[String] = ["top left", "top right", "bottom right", "bottom left"]

///|
/// Whether corner `k` (0 top left, then round it) is on the left.
fn corner_left(k : Int) -> Bool {
  k == 0 || k == 3
}

///|
/// How far box `b` stands from the two edges of `a` that meet at its corner `k` (0 top left, then round it): from its
/// side, from its top or foot.
fn corner_gaps(a : Node, b : Node, k : Int) -> (Double, Double) {
  let dx = if corner_left(k) { b.x - a.x } else { a.x + a.fw - (b.x + b.fw) }
  let dy = if k < 2 { b.y - a.y } else { a.y + a.fh - (b.y + b.fh) }
  (dx, dy)
}

///|
/// Where the last frame breaks the corner rule (see the file's head): one line for each grounded node in a rounded
/// container's corner that is not as far from both edges, or not concentric (within half a pixel).
pub fn Tester::corner_faults(self : Tester) -> Array[String] {
  ignore(self)
  g().corner_faults()
}

///|
/// Where the frame just built breaks the corner rule (Tester::corner_faults; a scripted run's `corners`).
fn Ctx::corner_faults(self : Ctx) -> Array[String] {
  let c = self
  // the corners said `Inner` that could not be worked out (corners_after_layout), first
  let out : Array[String] = c.inner_faults.copy()
  let grounds = c.layer_grounds()
  let pictures = c.pictures()
  let ladder = c.corner_ladder
  let off_ladder : Set[Int] = Set::new()
  for i in 0..<c.count {
    let b = c.nodes[i]
    if !b.grounded() || b.layer {
      continue
    }
    let ct = match c.corner_container(i, grounds) {
      Some(found) => found
      None => continue
    }
    let p = ct.node
    if c.corner_exempt(i, p, c.container_most(ct), ct.ground, pictures) {
      continue
    }
    let a = c.nodes[p]
    let l = b.x - a.x
    let t = b.y - a.y
    let r = a.x + a.fw - (b.x + b.fw)
    let d = a.y + a.fh - (b.y + b.fh)
    // (where one of its corners lies in a container's corner off the ladder, one following the window's, it stands
    // where that corner has it: its corners in the ladder's at that place concentric with them, and nothing more: a
    // composer across a panel's foot, 6.5 in to follow its corner in the window's, 28.8 round in its other, 34)
    let mut off_at : Double? = None
    if ladder.length() > 0 {
      for k in 0..<4 {
        let ra = c.container_r(ct, k)
        if !on_ladder(ladder, ra) {
          match c.corner_inset_at(i, p, k, ra) {
            Some(e) => off_at = Some(e)
            None => ()
          }
        }
      }
    }
    // each corner by the container's corner it lies in, each its own (a panel's in the window's corners following
    // them, the others standing alone)
    for k in 0..<4 {
      let ra = c.container_r(ct, k)
      let rb = b.corner_at(k)
      // a whole circle or a capsule (its corner half its shorter side: an avatar, a switch's knob, a dot, a ×) is round
      // by what it is. One in the middle of the container along an axis (as far from its top as from its foot, or from
      // its two sides) is set in a corner only where the container is round all along that axis (a capsule's end: a
      // switch's knob in its track, a send button in a capsule field, a chip's dot): a card's trailing × in the middle
      // of a card taller than its corners are round is in none. (Where it stands, not how it is laid out: one in the
      // middle of a short row along a container's edge, a bar's button by a panel's corner, is in that corner.)
      let round = rb >= dmin(b.fw, b.fh) / 2.0 - 0.5
      if round {
        if ((t - d).abs() <= 0.5 && ra < a.fh / 2.0 - 0.5) || ((l - r).abs() <= 0.5 && ra < a.fw / 2.0 - 0.5) {
          continue
        }
        // a mark smaller than the gap it would leave round it standing concentric (the corner's radius less its own
        // half: a status dot or ring leading a line of words) reads as a point, not as a shape the corner's arc runs
        // beside: it stands where the words it leads do, not by the corner
        let side = dmax(b.fw, b.fh)
        if side < ra - side / 2.0 + 0.5 {
          continue
        }
      }
      let (dx, dy) = corner_gaps(a, b, k)
      if dx < -0.5 || dy < -0.5 || dx >= ra || dy >= ra || !nearest_corner(k, l, t, r, d) {
        continue
      }
      // a corner that never shows: past the window's foot or head (a sheet held past the bottom so its foot's corners
      // are under it). Not past its sides: a pane beside the one in use comes over whole
      let cy = if k < 2 { a.y } else { a.y + a.fh }
      if cy > c.height + 0.5 || cy < -0.5 || c.corner_cut_off(i, p, k) {
        continue
      }
      // flush in the corner of something between it and the container that cuts with a rounded corner (a clip=true
      // box with a corner, cut along it since mbui#42): what shows of it there is the cut's corner, not its own
      if c.cut_round_at(i, p, k) {
        continue
      }
      // linked (Radius::Linked, corner_of.mbt) and following what it is linked to: held to its link, as far in from
      // the container's edges as the link says, the container's corner there the one it follows
      match b.links {
        Some(ls) =>
          match (ls[k].inset(), ls[k].source()) {
            (Some(e), Some(src)) if (dx - e).abs() > 0.5 || (dy - e).abs() > 0.5 || (ra - src).abs() > 0.5 => {
              out.push(
                "\{c.named(i)} (corner \{rb}) in the \{corner_names[k]} of \{c.named(p)} (corner \{ra}): linked to follow a corner \{src} round from \{e} in, it stands \{dx} and \{dy} from its edges",
              )
              continue
            }
            _ => ()
          }
        None => ()
      }
      let even = (dx - dy).abs() <= 0.5
      // a round one at a corner: it is the container whose corner follows it (ui-panels.md: 外圆角 = 距离 + 半高), the
      // fault the container's when it does not
      let in_step = if round {
        (ra - (dmax(dx, dy) + rb)).abs() <= 0.5
      } else {
        (rb - concentric(ra, dmax(dx, dy))).abs() <= 0.5
      }
      let corner = corner_names[k]
      // none of the theme's ranges makes it concentric there (Theme::corner_fit: the container too square for it, or
      // too round, a window's corner among them): it stands as it would alone, and the rule asks nothing more of it
      if !in_step && !c.fit_there(ra, rb, round) {
        continue
      }
      // concentric where it stands, but with a corner the ranges do not let it have (squarer than the least: as good
      // as square in a round corner) where some place in them would: it stands where that is (Ctx::fit_place)
      if !round && even && in_step && !c.corner_fits(rb) && c.fit_there(ra, rb, round) {
        let place = c.fit_place(ra, dx)
        out.push(
          "\{c.named(i)} (corner \{rb}) in the \{corner} of \{c.named(p)} (corner \{ra}): \{dx} from its edges, a corner the theme's ranges do not let it have; \{place} in, it would be \{concentric(ra, place)}",
        )
        continue
      }
      // the ladder's corners (Theme::corner_ladder): the container's, unless round by its shape, said once; what lies
      // in it, when it is as it should be by the rule above, unless round by its shape. Not a control's own parts
      // hugging its edge (under half the ladder's step in: a segmented control's thumb in its track, a table's head
      // inside its line), nor what is in the ladder's last (a small block's own marks): concentric with it and nothing
      // more
      if ladder.length() > 0 &&
        even &&
        in_step &&
        dmax(dx, dy) >= ladder_hug(ladder) &&
        ra > ladder[ladder.length() - 1] + 0.5 {
        let round_a = ra >= dmin(a.fw, a.fh) / 2.0 - 0.5
        // (not one round as it is because it lies in a corner of its own, concentric with it there: a panel in the
        // window's; nor the window, round as the system has it; nor one whose corners are linked, round as what they
        // come from has them: a strip along the window's edge, the window's less its inset all round)
        if !round_a &&
          !on_ladder(ladder, ra) &&
          !off_ladder.contains(p) &&
          !c.follows_corner(p, k, ra, grounds) &&
          c.nodes[ct.ground].links is None {
          off_ladder.add(p)
          out.push(
            "\{c.named(p)} (corner \{ra}): something lies in its \{corner}, and its corner is not one of the ladder's \{ladder}",
          )
        }
        let placed_off = match off_at {
          Some(e) => (e - dmax(dx, dy)).abs() <= 0.5
          None => false
        }
        if !round && on_ladder(ladder, ra) && !on_ladder(ladder, rb) && !placed_off {
          out.push(
            "\{c.named(i)} (corner \{rb}) in the \{corner} of \{c.named(p)} (corner \{ra}): \{dx} from its edges, so a corner not one of the ladder's \{ladder} (\{ladder_in(ladder, ra)})",
          )
        }
      }
      if !(even && in_step) {
        out.push(
          if round && even {
            "\{c.named(p)} (corner \{ra}): wants corner \{dmax(dx, dy) + rb}, for \{c.named(i)} (round, corner \{rb}) in its \{corner}, \{dx} from both edges"
          } else {
            "\{c.named(i)} (corner \{rb}) in the \{corner} of \{c.named(p)} (corner \{ra}): \{dx} and \{dy} from its edges" +
            (
              if in_step || round {
                ""
              } else if c.corner_fits(concentric(ra, dmax(dx, dy))) {
                ", wants corner \{concentric(ra, dmax(dx, dy))}"
              } else {
                // (concentric there, a corner the ranges do not let it have: where it would fit)
                ", too far in to follow it; \{c.fit_place(ra, dmax(dx, dy))} in, it would be \{concentric(ra, c.fit_place(ra, dmax(dx, dy)))}"
              }
            )
          },
        )
      }
    }
  }
  out
}

///|
/// Whether what lies in a corner `ra` round, its own corner `rb`, could be concentric with it anywhere and in any shape
/// the theme lets it (Theme::corner_fit): a circle or a capsule (`round`) where it stands `ra - rb` in, if that is a
/// place it may stand; a smooth box as round as concentric asks where it stands, if some place it may stand makes that
/// a corner it may have. Always, where the theme says no ranges.
fn Ctx::fit_there(self : Ctx, ra : Double, rb : Double, round : Bool) -> Bool {
  match self.corner_fit {
    None => true
    Some(f) =>
      if round {
        self.place_fits(ra - rb)
      } else {
        concentric(ra, f.far) <= f.most + 0.5 && concentric(ra, f.near) >= f.least - 0.5
      }
  }
}

///|
/// Where a smooth box in a corner `ra` round, `d` in, would stand concentric with a corner the theme's ranges let it
/// have (Theme::corner_fit): the place nearest `d` among those (still.fail's sf box_fit picks the same).
fn Ctx::fit_place(self : Ctx, ra : Double, d : Double) -> Double {
  match self.corner_fit {
    None => d
    Some(f) => {
      let nearest = dmax(f.near, (ra - f.most) * smooth_scale)
      let furthest = dmin(f.far, (ra - f.least) * smooth_scale)
      dmin(dmax(d, nearest), furthest)
    }
  }
}

///|
/// Whether corner `k` (0 top left, then round it) of a container is one a box `l`, `t`, `r`, `d` from its left, top,
/// right and foot edges lies in by where it stands: on the side of the container it is nearer (or in its middle), not
/// the far one a short container brings within reach too (a copy key in a one-line block's top right corner, its
/// foot's within the block's corner from it as well).
fn nearest_corner(k : Int, l : Double, t : Double, r : Double, d : Double) -> Bool {
  let side_ok = if corner_left(k) { l <= r + 0.5 } else { r <= l + 0.5 }
  let end_ok = if k < 2 { t <= d + 0.5 } else { d <= t + 0.5 }
  side_ok && end_ok
}

///|
/// Whether corner `r` is one of the ladder's (within half a pixel).
fn on_ladder(ladder : Array[Double], r : Double) -> Bool {
  ladder.iter().any(fn(x) { (x - r).abs() <= 0.5 })
}

///|
/// How far in a control's own parts hug its edge, the ladder's rule not theirs (corner_faults): under half the
/// ladder's inset (its step over smooth.mbt's 1.25).
fn ladder_hug(ladder : Array[Double]) -> Double {
  if ladder.length() < 2 {
    return 0.0
  }
  (ladder[0] - ladder[1]) * smooth_scale / 2.0
}

///|
/// How far in from a corner of `ra` (one of the ladder's) a smooth box stands to be round by the next of the ladder's,
/// said for a fault.
fn ladder_in(ladder : Array[Double], ra : Double) -> String {
  match ladder.iter().find_first(fn(x) { x < ra - 0.5 }) {
    Some(next) => "the next, \{next}, \{(ra - next) * smooth_scale} in"
    None => "none in from it"
  }
}

///|
/// Whether box `i`, in the corner of container `p` (corner `ra`, its ground `ground`'s), is none of the rule's: in
/// what scrolls in the container (a list, a box kept to a height, a strip scrolled sideways, each with more than it
/// shows: what it holds scrolls under its edges, so where one is from the container's corner is not fixed: a sheet's
/// content scrolling in it, cut by its foot; a composer's quotes, its files' strip, once more than fit); the container's own ground drawn on (the same fill, no
/// edge: a grouped row's square patch over its rounded corners: its shape, not something in its corner); a line (under
/// corner_line across: a bar's track, a rule), which has no corner to keep; a mark hung on
/// something small in it (laid over it as a layer, moved off its place by an offset, or placed out of the flow in it: a
/// badge on an icon, a remove button on a picture, a dot's halo, its place that thing's, not the corner's), or on the
/// corner of something larger, moved off its place past the edge of what it is laid over (a file card's remove button
/// over its top right corner: its place the card's corner, not the container's).
fn Ctx::corner_exempt(self : Ctx, i : Int, p : Int, ra : Double, ground : Int, pictures : Set[Int]) -> Bool {
  let (up_down, across) = self.scrolls_between(i, p)
  if up_down || across || self.in_picture(p, pictures) {
    return true
  }
  let b = self.nodes[i]
  if dmin(b.fw, b.fh) < corner_line {
    return true
  }
  // (a row pressed as a whole shows no ground at rest: what it lies on is the ground under it, its container's)
  let mut gi = ground
  while gi >= 0 && (self.nodes[gi].bg & 0xFFL) == 0L && self.nodes[gi].glass is None {
    gi = self.nodes[gi].parent
  }
  let gn = self.nodes[if gi >= 0 { gi } else { ground }]
  if b.bg == gn.bg && b.border_w <= 0.0 && gn.glass is None {
    return true
  }
  let mut q = i
  while q >= 0 && q != p {
    let n = self.nodes[q]
    let placed = n.layer ||
      n.tx != 0.0 ||
      n.ty != 0.0 ||
      !n.at_l.is_nan() ||
      !n.at_t.is_nan() ||
      !n.at_r.is_nan() ||
      !n.at_b.is_nan()
    if placed && n.parent >= 0 && n.parent != p {
      let host = self.nodes[n.parent]
      if host.fw < 2.0 * ra && host.fh < 2.0 * ra {
        return true
      }
      // (the mark itself moved past an edge of what it is laid over, smaller than the corner: hung on that corner)
      if q == i && b.fw < 2.0 * ra && b.fh < 2.0 * ra && reaches_past(n, host) {
        return true
      }
    }
    q = n.parent
  }
  false
}

///|
/// Whether node `n` reaches past an edge of `host` (by more than half a pixel).
fn reaches_past(n : Node, host : Node) -> Bool {
  n.x < host.x - 0.5 || n.y < host.y - 0.5 || n.x + n.fw > host.x + host.fw + 0.5 || n.y + n.fh > host.y + host.fh + 0.5
}

///|
/// How thin a box is a line, not a ground with corners (a progress bar's track, 4; a rule).
let corner_line : Double = 6.0

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
/// What scrolls between node `i` and its ancestor `p` (`i` in what it holds): whether something scrolls up and down (a
/// list, a box kept to a height: Ctx::capped), and whether something scrolls sideways (Ctx::sideways). A box kept to
/// a height or scrolled sideways that has nothing to scroll (Ctx::scroll_still) does not: what it holds stays where it
/// is, as in any box.
fn Ctx::scrolls_between(self : Ctx, i : Int, p : Int) -> (Bool, Bool) {
  let mut up_down = false
  let mut across = false
  let mut q = self.nodes[i].parent
  while q >= 0 && q != p {
    let n = self.nodes[q]
    if n.kind == kind_list {
      up_down = true
    } else if n.sideways {
      match sideways.get(n.id) {
        Some(st) if self.scroll_still(q, st) => ()
        Some(st) if st.vertical => up_down = true
        _ => across = true
      }
    }
    q = n.parent
  }
  (up_down, across)
}

///|
/// Whether the box `q` kept to a height or scrolled sideways (its state `st`) has nothing to scroll this frame: at its
/// start, and what it holds as long (or as wide) as it at most, so it does not move. What lies in it then lies where it
/// is for good, in a container's corner as anything else does (a table as narrow as its column on a card: the card's
/// ladder rounds it there); one that holds more moves it under its edges, so where it is from a corner is not fixed.
fn Ctx::scroll_still(self : Ctx, q : Int, st : Sideways) -> Bool {
  if st.x > 0.5 || st.max > 0.5 || st.frame != self.build_no {
    return false
  }
  let inner = if st.box == q {
    st.inner
  } else {
    match st.others.iter().find_first(fn(bi) { bi.0 == q }) {
      Some(bi) => bi.1
      None => -1
    }
  }
  if inner < 0 || inner >= self.count {
    return false
  }
  let o = self.nodes[q]
  let n = self.nodes[inner]
  if st.vertical {
    n.fh <= o.fh + 0.5
  } else {
    n.fw <= o.fw + 0.5
  }
}

///|
/// The nodes said to be pictures (Role Image) this frame (in_picture).
fn Ctx::pictures(self : Ctx) -> Set[Int] {
  let out : Set[Int] = Set::new()
  for s in self.sems {
    if s.role == Image {
      out.add(s.node)
    }
  }
  out
}

///|
/// Whether node `i` is in a picture (said to be one: Role Image, itself or what holds it): a drawing of something else
/// (another system's screen, its banner and its dock, as a setting's preview shows them), whose corners, and what is
/// in them, are what it draws, not the theme's. (A picture in a container's corner is the rule's as any box.)
fn Ctx::in_picture(self : Ctx, i : Int, pictures : Set[Int]) -> Bool {
  if pictures.is_empty() {
    return false
  }
  let mut q = i
  while q >= 0 {
    if pictures.contains(q) {
      return true
    }
    q = self.nodes[q].parent
  }
  false
}

///|
/// The rounded container node `i` lies in, as the corner rule sees it: the nearest round it that shows (a ground, an
/// edge, glass, or what it cuts) with a corner of 6 or more (its roundest), its own or one laid under it as a layer of
/// the same size (a composer's glass drawn beside what it holds: `grounds`, Ctx::layer_grounds). Its node, the node
/// whose ground its corners are, whether it is the window; None when there is none. Tester::corner_faults and `Inner` (corners_after_layout) both ask
/// this, so they measure against the same container.
fn Ctx::corner_container(self : Ctx, i : Int, grounds : Map[Int, Int]) -> Container? {
  let mut p = self.nodes[i].parent
  let mut top = i
  while p >= 0 {
    let a = self.nodes[p]
    if a.kind == kind_box &&
      a.corner() >= 6.0 &&
      (a.grounded() || a.glass is Some(_) || a.clip || a.pressed_row() || self.inner_row(p)) {
      return Some({ node: p, ground: p, window: false })
    }
    match grounds.get(p) {
      Some(gi) if gi != i => return Some({ node: p, ground: gi, window: false })
      _ => ()
    }
    top = p
    p = a.parent
  }
  // none rounded round it: the window, where the system rounds its corners (window_container)
  if top != i && self.window_container(top) {
    return Some({ node: top, ground: top, window: true })
  }
  None
}

///|
/// Whether node `n`, a root of what is built (the page's, or a layer's), is the window to the corner rule: the size of
/// the window, where the system rounds its corners (@hostapi.window_corner, at least as round as a container's corner
/// is to count): the outermost container, its corner the system's, what lies in it concentric with it as with any.
fn Ctx::window_container(self : Ctx, n : Int) -> Bool {
  let r = self.nodes[n]
  self.window_corner >= 6.0 &&
  r.parent < 0 &&
  r.x.abs() <= 0.5 &&
  r.y.abs() <= 0.5 &&
  (r.fw - self.width).abs() <= 0.5 &&
  (r.fh - self.height).abs() <= 0.5
}

///|
/// Whether a corner `k` round may be had by what lies in a container's corner (Theme::corner_fit: `least` to `most`;
/// any where the theme says none).
fn Ctx::corner_fits(self : Ctx, k : Double) -> Bool {
  match self.corner_fit {
    Some(f) => k >= f.least - 0.5 && k <= f.most + 0.5
    None => true
  }
}

///|
/// Whether what lies in a container's corner may stand `d` from its edges to be concentric with it (Theme::corner_fit:
/// `near` to `far`; anywhere where the theme says none).
fn Ctx::place_fits(self : Ctx, d : Double) -> Bool {
  match self.corner_fit {
    Some(f) => d >= f.near - 0.5 && d <= f.far + 0.5
    None => true
  }
}

///|
/// Whether container `p`'s corner `k` (`ra` round) is round as it is because it lies in its own container's corner,
/// concentric with it there (a panel 6 in from the window's corner, as round as the window's less that): its corner
/// the outer one's, not one of the ladder's to keep. One past the window's side there (a pane beside the one in use,
/// which comes over whole into the window's side) by how far it stands from the window's top and foot, where it will
/// be in that corner.
fn Ctx::follows_corner(self : Ctx, p : Int, k : Int, ra : Double, grounds : Map[Int, Int]) -> Bool {
  if self.window_container(p) {
    return true
  }
  match self.corner_container(p, grounds) {
    Some(ct) => {
      let rq = self.container_r(ct, k)
      match self.corner_inset_at(p, ct.node, k, rq) {
        Some(e) => (ra - concentric(rq, e)).abs() <= 0.5
        None => {
          let a = self.nodes[ct.node]
          let b = self.nodes[p]
          let (dx, dy) = corner_gaps(a, b, k)
          let t = b.y - a.y
          let d = a.y + a.fh - (b.y + b.fh)
          ct.window &&
          dx < -0.5 &&
          (t - d).abs() <= 0.5 &&
          dy >= -0.5 &&
          dy < rq &&
          (ra - concentric(rq, dy)).abs() <= 0.5
        }
      }
    }
    None => false
  }
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
/// concentric with it across the box's distance from that container's edges it is near (nearer than the container's
/// corner is round), those distances the same (smooth.mbt concentric); so the box is concentric with it by how it is
/// written, and corner_faults finds nothing
/// in it. In the order they were built, a container `Inner` itself worked out first. A box in no rounded container,
/// near none of its edges, or near edges at different distances (the window narrowed, a max_w come into force) is
/// drawn square, and said so: corner_faults lists it, so a test fails where a person's screen would not. One said
/// `InnerOr` keeps its own corner in no container or near none of its edges (it stands alone there), and at different
/// distances keeps it too, said so.
fn Ctx::corners_after_layout(self : Ctx) -> Unit {
  self.inner_faults.clear()
  // the containers whose corner is what lies in it (`Around`), before the boxes worked out from their containers
  self.arounds_after_layout()
  let grounds = self.layer_grounds()
  // then every box in a container's corner, `Inner` and the rest, outermost first (a container worked out before what
  // is in it, as the window's corner makes a panel's)
  self.corners_in_corners(grounds)
}

///|
/// A corner said `Inner` or `InnerOr`, node `i`'s (corners_in_corners, in the order built: its container worked out
/// before it).
fn Ctx::inner_after_layout(self : Ctx, i : Int, grounds : Map[Int, Int]) -> Unit {
  let n = self.nodes[i]
  // (`InnerOr`: its own corners where they lie in no container's corner, as built)
  let own = if self.inners_or.contains(i) { Some(n.radii_now()) } else { None }
  n.radius = 0.0
  n.radii = None
  let ct = match self.corner_container(i, grounds) {
    Some(found) => found
    None => {
      match own {
        Some(r) => n.set_radii(r)
        None => self.inner_faults.push("\{self.named(i)}: radius=Inner, in no rounded container")
      }
      return
    }
  }
  let p = ct.node
  let ra = self.container_most(ct)
  let a = self.nodes[p]
  let sides = [
    ("left", n.x - a.x),
    ("top", n.y - a.y),
    ("right", a.x + a.fw - (n.x + n.fw)),
    ("bottom", a.y + a.fh - (n.y + n.fh)),
  ]
  // (an edge it reaches past is no edge of its: it is cut there, as corner_faults leaves out a corner it overhangs; a
  // row of a list in it scrolls past its top and foot, so what it is near is the sides it lies between; a card of a
  // strip scrolled sideways, past its sides, so what it is near is its top and foot)
  let (up_down, across) = self.scrolls_between(i, p)
  let near = sides.filter(fn(s) {
    s.1 >= -inner_even &&
    s.1 < ra &&
    !(up_down && (s.0 == "top" || s.0 == "bottom")) &&
    !(across && (s.0 == "left" || s.0 == "right"))
  })
  if near.is_empty() {
    match own {
      Some(r) => n.set_radii(r)
      None =>
        self.inner_faults.push(
          "\{self.named(i)}: radius=Inner, near none of the edges of \{self.named(p)} (corner \{ra})",
        )
    }
    return
  }
  let d = near[0].1
  if near.iter().any(fn(s) { (s.1 - d).abs() > inner_even }) {
    let said = near.map(fn(s) { "\{s.0} \{s.1}" }).join(", ")
    self.inner_faults.push(
      "\{self.named(i)}: radius=Inner, at different distances from the edges of \{self.named(p)} (corner \{ra}): \{said}",
    )
    match own {
      Some(r) => n.set_radii(r)
      None => ()
    }
    return
  }
  // each corner by the container's corner there (a panel's in the window's corners following them, the others alone):
  // concentric with it across `d`. `InnerOr` keeps its own where it lies in no corner of the container's (near the two
  // edges that meet there, an edge it scrolls past counted near: a composer at a panel's foot, its top's corners its
  // own), and where it is round of its own and round there too, as a pill or a circle is in a corner as round as it
  // (its own corner kept, the same box drawn the same); and its own where no place the theme's ranges let it stand
  // makes a capsule of it concentric there (the container too square for it), or where it stands its corner would be
  // one they do not let it have: it stands as alone, and corner_faults says where it would fit, if anywhere; and, as
  // corners_in_corners leaves it, its own where it is not round of its own and the corner it would have there would
  // round it whole (a row 38 high 8 from a panel's side, the panel's 34 in reach of it as it scrolls): too small for
  // that corner, it keeps its shape
  let half = dmin(n.fw, n.fh) / 2.0
  let rs = FixedArray::make(4, 0.0)
  for k in 0..<4 {
    let rk = self.container_r(ct, k)
    let kk = concentric(rk, d)
    let side = sides[if corner_left(k) { 0 } else { 2 }].1
    let end = sides[if k < 2 { 1 } else { 3 }].1
    let lies = (across || (side >= -inner_even && side < rk)) && (up_down || (end >= -inner_even && end < rk))
    rs[k] = match own {
      Some(r) if !lies => r[k]
      Some(r) if r[k] >= half && kk >= half => r[k]
      Some(r) if r[k] >= half && !self.place_fits(rk - half) => r[k]
      Some(r) if r[k] < half - 0.5 && kk >= half - 0.5 => r[k]
      Some(r) if !self.corner_fits(kk) => r[k]
      _ => kk
    }
  }
  n.set_radii(rs)
}

///|
/// Every other box with a corner of its own (not `Inner`, `InnerOr` or `Around`: worked out before it), whose shape is
/// not round by its size: the corner it is given is the one it has standing alone; each of its corners lying in the
/// corner of a rounded container (corner_container: near two of its edges that meet, nearer than the container's
/// corner there is round, as far from both), concentric with it, as corner_faults asks; the others its own. So no page says it, and a box the window or what it holds
/// moves into a corner or out of one is right in both. In the order built, a container before what it holds. A capsule
/// or a circle (its corner half its shorter side) is round by its shape: where it stands is what makes it concentric
/// (ui-panels.md: 外圆角 = 距离 + 半高), which corner_faults checks; so is one too small for the corner it would have
/// there, and one at different distances from the two edges: each keeps its own.
fn Ctx::corners_in_corners(self : Ctx, grounds : Map[Int, Int]) -> Unit {
  let inner : Set[Int] = Set::new()
  for i in self.inners {
    inner.add(i)
  }
  let said : Set[Int] = Set::new()
  for i in self.arounds {
    said.add(i)
  }
  let pictures = self.pictures()
  for i in 0..<self.count {
    if inner.contains(i) {
      self.inner_after_layout(i, grounds)
      continue
    }
    let b = self.nodes[i]
    // (nor one linked: its corners come from where its links say, and the rule holds it to them, corner_faults)
    if b.kind != kind_box ||
      b.layer ||
      b.radius < 0.5 ||
      b.fw <= 0.0 ||
      b.fh <= 0.0 ||
      said.contains(i) ||
      b.links is Some(_) {
      continue
    }
    let half = dmin(b.fw, b.fh) / 2.0
    let ct = match self.corner_container(i, grounds) {
      Some(found) => found
      None => continue
    }
    if self.corner_exempt(i, ct.node, self.container_most(ct), ct.ground, pictures) {
      continue
    }
    // each corner by the container's corner it lies in (a panel's in the window's corners following them, the others
    // its own). (Not where that would round it whole: a box too small for the corner it would have keeps its shape,
    // and stands where its shape is concentric, as a capsule would, or corner_faults says so; nor a corner round by
    // its shape, a capsule's end; nor where it would be rounder or squarer than the theme lets what lies in a corner
    // be, Theme::corner_fit: it stands as it would alone)
    let rs = b.radii_now()
    let mut moved = false
    for k in 0..<4 {
      if rs[k] >= half - 0.5 {
        continue
      }
      match self.corner_inset_at(i, ct.node, k, self.container_r(ct, k)) {
        Some(d) => {
          let kk = concentric(self.container_r(ct, k), d)
          if kk < half - 0.5 && self.corner_fits(kk) {
            rs[k] = kk
            moved = true
          }
        }
        None => ()
      }
    }
    if moved {
      b.set_radii(rs)
    }
  }
}

///|
/// How far box `i` stands from the two edges of container `p`'s corner `k` (`ra` round), where it lies in it (nearer
/// to both than `ra`, not past either; not where a cut between them bounds it: cut_round_at) as far from both; None
/// when it lies in none, or not as far from each.
fn Ctx::corner_inset_at(self : Ctx, i : Int, p : Int, k : Int, ra : Double) -> Double? {
  let a = self.nodes[p]
  let b = self.nodes[i]
  let l = b.x - a.x
  let t = b.y - a.y
  let r = a.x + a.fw - (b.x + b.fw)
  let d = a.y + a.fh - (b.y + b.fh)
  let (dx, dy) = corner_gaps(a, b, k)
  if dx < -0.5 ||
    dy < -0.5 ||
    dx >= ra ||
    dy >= ra ||
    !nearest_corner(k, l, t, r, d) ||
    self.cut_round_at(i, p, k) ||
    self.corner_cut_off(i, p, k) ||
    (dx - dy).abs() > 0.5 {
    return None
  }
  Some(dmax(dx, dy))
}

///|
/// Whether node `i`'s corner `k` (0 top left, then round it) is cut off by something
/// between it and its container `p` that cuts what it holds (clip, or what scrolls sideways in it): past its edge, it
/// does not show (a table wider than its column, scrolled sideways in it).
fn Ctx::corner_cut_off(self : Ctx, i : Int, p : Int, k : Int) -> Bool {
  let b = self.nodes[i]
  let x = if corner_left(k) { b.x } else { b.x + b.fw }
  let y = if k < 2 { b.y } else { b.y + b.fh }
  let mut q = b.parent
  while q >= 0 && q != p {
    let n = self.nodes[q]
    if (n.clip || n.sideways) &&
      (x < n.x - 0.5 || x > n.x + n.fw + 0.5 || y < n.y - 0.5 || y > n.y + n.fh + 0.5) {
      return true
    }
    q = n.parent
  }
  false
}

///|
/// Whether what shows at node `i`'s corner `k` (0 top left, then round it) is the curve of
/// a box between it and its container `p` (`p` included) that cuts what it holds with a rounded corner (clip, a corner of
/// its own): the node's own corner there lies wholly outside the cut's curve (within half a pixel), so the cut's bounds
/// it (a square corner flush along its edge, a capsule's fill as round as it). Both corners as drawn (smooth.mbt: each
/// as smooth as its box has room for); the node's measured at 16 fixed directions over the quarter toward the corner,
/// one point inside the cut's curve and its own shows: checked as any other.
fn Ctx::cut_round_at(self : Ctx, i : Int, p : Int, k : Int) -> Bool {
  let b = self.nodes[i]
  let rb = b.corner_at(k)
  let sb = smoothness(rb, dmin(b.fw, b.fh) / 2.0)
  let nb = 2.0 + (smooth_exponent - 2.0) * sb
  let big = rb * (1.0 + (smooth_scale - 1.0) * sb)
  let mut q = b.parent
  while q >= 0 {
    let n = self.nodes[q]
    // (the window cuts what is drawn in it as a clip with its corner does)
    let window = q == p && self.window_container(q)
    let r = if window { self.window_corner } else { n.corner_at(k) }
    if (n.clip || window) && r >= 0.5 {
      // the corner's own frame: the cut's corner at the origin, inward positive
      let dx = if corner_left(k) { b.x - n.x } else { n.x + n.fw - (b.x + b.fw) }
      let dy = if k < 2 { b.y - n.y } else { n.y + n.fh - (b.y + b.fh) }
      let hx = n.fw / 2.0
      let hy = n.fh / 2.0
      let sn = smoothness(r, dmin(hx, hy))
      if dx >= -0.5 && dy >= -0.5 && dx < r * (1.0 + (smooth_scale - 1.0) * sn) && dy < r * (1.0 + (smooth_scale - 1.0) * sn) {
        let mut outside = true
        for j in 0..<cut_arc_steps {
          let a = half_pi * j.to_double() / (cut_arc_steps - 1).to_double()
          let c = @dmath.cos(a)
          let s = @dmath.sin(a)
          let rho = 1.0 / det_pow(det_pow(c, nb) + det_pow(s, nb), 1.0 / nb)
          let px = dx + big - big * rho * c
          let py = dy + big - big * rho * s
          // (from the cut's middle, toward this corner)
          if sd_corner(hx - px, hy - py, hx, hy, r, sn) < -0.5 {
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

///|
/// The corners said `Around`, from where what lies in their corners is as laid out (corners_after_layout, first): the
/// box in the container's corner (the nearest to two of its edges of the boxes with a corner of their own in it, through
/// boxes with none: a key's round, filled or not, a button) as far from both; the container's corner that distance more
/// than a circle's or a capsule's own (ui-panels.md: 外圆角 = 距离 + 半高; still.fail's Android Smooth(8.dp + 17.dp)), or
/// concentric round a smooth one (smooth.mbt concentric_out, Android's concentricOut). As corner_faults checks it,
/// the other way round. A box with nothing with a corner in its corner, one at different distances from the two edges,
/// or one whose corner is `Inner` itself (each worked out from the other) is drawn square, and said so.
fn Ctx::arounds_after_layout(self : Ctx) -> Unit {
  for p in self.arounds {
    let a = self.nodes[p]
    a.radius = 0.0
    a.radii = None
    // (corner index, the box, its distances from the corner's two edges)
    let mut best : (Int, Int, Double, Double)? = None
    let mut best_d = 1.0e9
    for i in 0..<self.count {
      let b = self.nodes[i]
      if i == p ||
        b.kind != kind_box ||
        b.layer ||
        (b.radius < 0.5 && !self.inners.contains(i)) ||
        b.fw <= 0.0 ||
        b.fh <= 0.0 {
        continue
      }
      if !self.lies_in_bare(i, p) {
        continue
      }
      for k in 0..<4 {
        let (dx, dy) = corner_gaps(a, b, k)
        if dx < -inner_even || dy < -inner_even {
          continue
        }
        let far = dmax(dx, dy)
        if far < best_d {
          best_d = far
          best = Some((k, i, dx, dy))
        }
      }
    }
    match best {
      None => self.inner_faults.push("\{self.named(p)}: radius=Around, nothing with a corner in its corners")
      Some((k, i, dx, dy)) => {
        let corner = corner_names[k]
        if self.inners.contains(i) {
          self.inner_faults.push(
            "\{self.named(p)}: radius=Around round \{self.named(i)} in its \{corner}, whose corner is Inner: each worked out from the other",
          )
          continue
        }
        if (dx - dy).abs() > inner_even {
          self.inner_faults.push(
            "\{self.named(p)}: radius=Around round \{self.named(i)} in its \{corner}, at different distances from its edges: \{dx} and \{dy}",
          )
          continue
        }
        let b = self.nodes[i]
        let rb = b.corner_at(k)
        let round = rb >= dmin(b.fw, b.fh) / 2.0 - 0.5
        a.radius = if round { dx + rb } else { concentric_out(rb, dx) }
      }
    }
  }
}

///|
/// Whether box `i` lies in `p` with nothing between them that has a corner of its own (what `Around` reads a corner
/// round, as corner_container finds `p` from it).
fn Ctx::lies_in_bare(self : Ctx, i : Int, p : Int) -> Bool {
  let mut q = self.nodes[i].parent
  while q >= 0 {
    if q == p {
      return true
    }
    if self.nodes[q].radius >= 0.5 {
      return false
    }
    q = self.nodes[q].parent
  }
  false
}
