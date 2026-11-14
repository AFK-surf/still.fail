// The room a press has round what is drawn smaller than it (still.fail's rules 1 and 2, the user, 2026-10-26: what
// always shows is pressed in 44×44 at least): what a finger or the pointer at a point reaches from round it. One way
// of working it out, here, under both views (ui imports this package): the window's tree's hit test
// (Tree::target_at), the old view's (ui's press_reach) and the check of the room each has (ui's rooms.mbt) all ask it.

///|
/// The room a press has round what is drawn (x0, y0)–(x1, y1): each way it is drawn smaller than `least`, it grown to
/// it round its middle (not drawn so, nor laid out); moved in where that passes an edge past which nothing is pressed
/// (`edge`: the window, what cuts it) rather than cut short there; cut where it passes what holds it that takes presses
/// (`cut`: a row's small button keeps to its row, the row's own room round it the row's). What the hit tests reach
/// (press_reaches) and the room rules measure (ui's rooms.mbt), one.
pub fn press_room(
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  cut : (Double, Double, Double, Double),
  edge : (Double, Double, Double, Double),
  least : Double,
) -> (Double, Double, Double, Double) {
  let (ax0, ax1) = room_across(x0, x1, cut.0, cut.2, edge.0, edge.2, least)
  let (ay0, ay1) = room_across(y0, y1, cut.1, cut.3, edge.1, edge.3, least)
  (ax0, ay0, ax1, ay1)
}

///|
/// One way of press_room: `lo`–`hi` grown to `least` round its middle where shorter, moved in from `elo`–`ehi`'s ends,
/// cut to `clo`–`chi`.
fn room_across(
  lo : Double,
  hi : Double,
  clo : Double,
  chi : Double,
  elo : Double,
  ehi : Double,
  least : Double,
) -> (Double, Double) {
  let mut a = lo
  let mut b = hi
  if hi - lo < least {
    let mid = (lo + hi) / 2.0
    a = mid - least / 2.0
    b = mid + least / 2.0
    // (moved in from an edge it passes, not cut short at it)
    if a < elo {
      b = b + (elo - a)
      a = elo
    }
    if b > ehi {
      a = a - (b - ehi)
      b = ehi
    }
  }
  (dmax(a, dmax(clo, elo)), dmin(b, dmin(chi, ehi)))
}

///|
/// Whether what is drawn (x0, y0)–(x1, y1) is reached from round it at all: drawn, and smaller than `least` some way
/// (one as big each way is pressed where it is drawn).
pub fn press_small(x0 : Double, y0 : Double, x1 : Double, y1 : Double, least : Double) -> Bool {
  let (w, h) = (x1 - x0, y1 - y0)
  w > 0.0 && h > 0.0 && (w < least || h < least)
}

///|
/// How far a press at (x, y) is from what is drawn (x0, y0)–(x1, y1) (the square of it), where it reaches that from
/// round it: drawn smaller than `least` (press_small), its room (press_room in `cut` and `edge`) holding (x, y); none
/// where not. Of several a press reaches, the nearest is what it is on (where rooms meet, each has the part nearer it;
/// as near, the one drawn first): the window's tree's (Tree::target_at) and the old view's (ui's press_reach) alike.
pub fn press_reaches(
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  cut : (Double, Double, Double, Double),
  edge : (Double, Double, Double, Double),
  least : Double,
  x : Double,
  y : Double,
) -> Double? {
  guard press_small(x0, y0, x1, y1, least) else { return None }
  let (rx0, ry0, rx1, ry1) = press_room(x0, y0, x1, y1, cut, edge, least)
  if x < rx0 || x >= rx1 || y < ry0 || y >= ry1 {
    return None
  }
  let dx = dmax(0.0, dmax(x0 - x, x - x1))
  let dy = dmax(0.0, dmax(y0 - y, y - y1))
  Some(dx * dx + dy * dy)
}

///|
/// A target of the tree's drawn smaller than its room near a point, as a walk finding what takes a finger there passes
/// it (Tree::near_said): where it is in the order drawn, which it is and how (Pressed or Dragged), its box in the window.
priv struct Near {
  order : Int
  target : Target
  box : (Double, Double, Double, Double)
}

///|
/// How far across each way the room a press has is at least where what hosts the tree draws it, as it is asked (ui's
/// room_least: by the native input; a finger's 44, a keyboard and mouse's 36); none said, none: each pressed only
/// where it is drawn (a tree no host draws, its input not known).
pub fn Tree::press_least(self : Tree, f : () -> Double) -> Unit {
  self.press_least = f
}

///|
/// The least room a press has as of now (Tree::press_least), nothing followed.
fn Tree::least_now(self : Tree) -> Double {
  @signals.untracked(self.press_least)
}

///|
/// Whether node `n` is pressed only where it is drawn, no room grown round it: a column's edge or a corner, its pointer's
/// shape a resize (the user, 2026-10-28: 左右各 6px, 同 web; the old view's the same, ui's as_drawn).
fn Node::as_drawn(self : Node) -> Bool {
  self.cursor is Some(ResizeX | ResizeY | ResizeNWSE | ResizeNESW)
}

///|
/// Whether node `n`, drawn `a` opaque, hides what is drawn under it where it is drawn: a ground of its own drawn whole
/// (no ink showing through it, the node not fading), or glass (a bar frosted over what scrolls under it). What is under
/// it there is out of sight (Tree::reached: an old view's own under a bar is none of it there).
fn Node::covers(self : Node, a : Double) -> Bool {
  self.look.glass is Some(_) || (a >= 1.0 && (self.look.ground & 0xFFL) == 0xFFL)
}

///|
/// The node over all else of the window (View::over_all) node `id` is in, it or what holds it; -1 none.
fn Tree::over_all_of(self : Tree, id : NodeId) -> Int {
  guard self.alive_id(id) else { return -1 }
  let mut i = id.at
  while i >= 0 {
    if self.nodes[i].over_all {
      return i
    }
    i = self.nodes[i].parent
  }
  -1
}

///|
/// Whether node `id` of the tree is pressed only where it is drawn (a column's edge: Node::as_drawn): what the hit test
/// reaches from round it (Tree::near_said) and the room rules measure (ui's tree_room_faults) ask it alike.
pub fn Tree::pressed_as_drawn(self : Tree, id : NodeId) -> Bool {
  self.alive_id(id) && self.nodes[id.at].as_drawn()
}

///|
/// Node `n` (content `c`, drawn at (cx, cy), `s` as big) passed by a walk finding what takes a finger at (x, y), not
/// there: kept in `out` (its place `order` in the walk) where it may be reached from round it, a press's room (`least`
/// across) away at most. One that does something pressed or held as its own (View::on_press; View::on_drag, not one
/// taking over holds), drawn smaller than its room, taking presses now; not one only pointed at (View::points), nor
/// one pressed only where it is drawn: a column's edge (Node::as_drawn), one saying where it takes a finger
/// (View::takes), one hosting an old view (whose own are its). Only arithmetic on what the walk gives it, but for one that near.
fn Tree::near_said(
  self : Tree,
  n : Node,
  c : Content,
  cx : Double,
  cy : Double,
  s : Double,
  x : Double,
  y : Double,
  least : Double,
  order : Int,
  out : Array[Near],
) -> Unit {
  let target = if n.on_drag is Some(_) && n.claims is None {
    Dragged(c.id)
  } else if n.on_press is Some(_) {
    Pressed(c.id)
  } else {
    return
  }
  let (x0, y0, x1, y1) = (cx, cy, cx + c.w * s, cy + c.h * s)
  if x < x0 - least || x >= x1 + least || y < y0 - least || y >= y1 + least || !press_small(x0, y0, x1, y1, least) {
    return
  }
  if n.points || n.hosted || n.takes is Some(_) || n.as_drawn() {
    return
  }
  if self.pressless_at(c.id.at) {
    return
  }
  self.work.near_kept = self.work.near_kept + 1
  out.push({ order, target, box: (x0, y0, x1, y1) })
}

///|
/// The room a press has round node `id`, drawn as `box` (x0, y0, x1, y1), as the hit test gives it (Tree::target_at
/// asked, nothing worked out beside it; one answering a hold alone, what a finger held there holds, Tree::hold_at; what a
/// layer presented over all else takes there not counted against it, View::over_all): across, on the line through its middle, from as far before its left edge to as
/// far past its right as a press there is on it; down, so on the line through its middle across. Each way it is drawn
/// as big as a press's room at least it is pressed only where drawn (press_small), its box. So what the room rules
/// measure (ui's rooms.mbt) is what a press does where the tree is drawn: what is drawn over another and within it
/// takes the press there first, where two reach the nearer has it, what the press lands in cuts what it reaches. What
/// the tree counts of its searches (found_walked, near_kept) is left as it was: a check's asking is none of its work.
/// Measured on its middle lines alone, a row as crowded is said only where its middle is under its neighbour: a line
/// 9 under a head, whose start is as near, not where it is long enough that its middle is past the head's last (a
/// rig's request granted). That is as little as the rule says, never what it lets pass; measured whole (the narrowest
/// along each edge) is to come (the coordinator of the migration, 2026-11-12).
pub fn Tree::press_room_found(
  self : Tree,
  id : NodeId,
  box : (Double, Double, Double, Double),
) -> (Double, Double, Double, Double) {
  let least = self.least_now()
  let (x0, y0, x1, y1) = box
  let (walked, kept) = (self.work.found_walked, self.work.near_kept)
  let (mx, my) = ((x0 + x1) / 2.0, (y0 + y1) / 2.0)
  let (rx0, rx1) = if x1 - x0 < least {
    let far = least - (x1 - x0)
    (x0 - self.reached_past(id, x0, my, -1.0, 0.0, far), x1 + self.reached_past(id, x1, my, 1.0, 0.0, far))
  } else {
    (x0, x1)
  }
  let (ry0, ry1) = if y1 - y0 < least {
    let far = least - (y1 - y0)
    (y0 - self.reached_past(id, mx, y0, 0.0, -1.0, far), y1 + self.reached_past(id, mx, y1, 0.0, 1.0, far))
  } else {
    (y0, y1)
  }
  self.work.found_walked = walked
  self.work.near_kept = kept
  (rx0, ry0, rx1, ry1)
}

///|
/// How far from (x, y), an edge of what node `id` draws, going (dx, dy) out of it, a press is still on it
/// (Tree::target_at), `far` at most (a press's room past one edge: as much as the room is wider than what is drawn, it
/// moved in from the window's edge whole): found in eight steps out and halved sixteen times in the last, to the
/// 1024th of a point (a place the layout gives, a half's or a third's, read as it is, no hair of a halving left on it).
fn Tree::reached_past(
  self : Tree,
  id : NodeId,
  x : Double,
  y : Double,
  dx : Double,
  dy : Double,
  far : Double,
) -> Double {
  // (one answering a hold alone: what a finger held there holds, Tree::hold_at; else what a press there is on)
  let held = self.alive_id(id) && self.nodes[id.at].hold_only is Some(_)
  let layer = self.over_all_of(id)
  let on = fn(d : Double) {
    let (px, py) = (x + dx * d, y + dy * d)
    if held && self.hold_at(px, py) == Some(id) {
      return true
    }
    match self.target_at(px, py) {
      Pressed(t) | Dragged(t) => {
        if t == id && !held {
          return true
        }
        // (what a layer presented over all else takes there (a hover card, a tip: View::over_all, opened by its
        // cause, gone at a press elsewhere) is its to take, as what a modal layer covers is none of the rules': not
        // room this one lacks (the coordinator of the migration, 2026-11-12). Not what is merely drawn after it, nor
        // what is in the same layer as it)
        let l = self.over_all_of(t)
        l >= 0 && l != layer
      }
      _ => false
    }
  }
  let step = far / 8.0
  let mut hit = 0.0
  let mut miss = -1.0
  for k = 1; k <= 8; k = k + 1 {
    let d = step * k.to_double()
    if on(d) {
      hit = d
    } else {
      miss = d
      break
    }
  }
  if miss < 0.0 {
    return far
  }
  for _ in 0..<16 {
    let d = (hit + miss) / 2.0
    if on(d) {
      hit = d
    } else {
      miss = d
    }
  }
  (hit * 1024.0).round() / 1024.0
}

///|
/// What a press at (x, y) is on, `top` found there (the topmost that takes it, at `top_order` in the walk, drawn as
/// `top_box`; Nothing: none): `top`, or what of `near` (Tree::near_said) is drawn over it and within it whose room
/// (press_reaches: cut to `top`, moved in from what bounds its input and the window) holds (x, y), the nearest of
/// several (where rooms meet, each has the part nearer it): a row's small button from round it, not the row's
/// neighbour's. By a finger and a pointer alike (the user, 2026-10-26: drawn small with a keyboard and mouse, a press's
/// room is not), so what lights under the pointer is what a click there presses. On what a drag pans whole
/// (View::on_drag's `whole`, the old view's `capture`: a picture) the press is its own, nothing over it reached. On one
/// hosting an old view, the old view's where it has something of its own there, as its host says (Tree::hosts_at: one
/// of its targets or its room round one, words of it to pick; the old view reaches what it draws itself); where it has
/// nothing, what is drawn over it is reached as though nothing were under the press, so a small key of the tree's over
/// an app's shell has its room as anywhere (none of it reached: still the old view's). Where what is drawn over the old
/// view there hides it (`covered`, its place in the walk: a bar's ground or glass over a chat's messages, Node::covers),
/// what the old view has there is out of sight and none of it: a key on the bar has its room over it as anywhere.
fn Tree::reached(
  self : Tree,
  top : Target,
  top_order : Int,
  top_box : (Double, Double, Double, Double),
  near : Array[Near],
  x : Double,
  y : Double,
  least : Double,
  covered? : Int = -1,
) -> Target {
  if near.is_empty() {
    return top
  }
  let (ww, wh) = self.room.untracked()
  let window = (0.0, 0.0, ww, wh)
  // (on one hosting an old view: the old view's where it has something of its own there (Tree::hosts_at); where it has
  // nothing, as though nothing were under the press, what is drawn over it reached from round it as anywhere)
  let (cut, on) = match top {
    Nothing => (window, false)
    Hosted(id) => {
      if covered <= top_order && (self.hosts_at)(id, x, y) is Some(_) {
        return top
      }
      (window, false)
    }
    Dragged(id) if self.nodes[id.at].drags_whole => return top
    _ => (top_box, true)
  }
  let mut best = top
  let mut best_d = 1.0e18
  for k in near {
    let (x0, y0, x1, y1) = k.box
    // (drawn over what the press is on, and within it)
    if k.order <= top_order || (on && (x0 < cut.0 || y0 < cut.1 || x1 > cut.2 || y1 > cut.3)) {
      continue
    }
    let id = match k.target {
      Pressed(id) | Dragged(id) => id
      _ => continue
    }
    let (bx0, by0, bx1, by1) = self.input_bounds(id)
    let edge = (dmax(0.0, bx0), dmax(0.0, by0), dmin(ww, bx1), dmin(wh, by1))
    // (none of it where it is found: out of sight, nothing reached round it, Tree::input_bounds)
    if x1 <= edge.0 || y1 <= edge.1 || x0 >= edge.2 || y0 >= edge.3 {
      continue
    }
    match press_reaches(x0, y0, x1, y1, cut, edge, least, x, y) {
      Some(d) if d < best_d => {
        best_d = d
        best = k.target
      }
      _ => ()
    }
  }
  best
}
