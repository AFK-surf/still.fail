// Shared elements (MyGo's Match, set off by its cause): two nodes said to be one thing by an id (View::shared). One a
// structure lets go of or sets leaving (show, pick, each: it or what holds it) and one made with the same id in the same
// change (an event, a batch of signals set outside, a moment come on the timeline) are paired as that change is
// committed whole (Tree::pairs_now), whichever structure ran first: never by comparing frames. The new one flies from
// where the old one was drawn as the change came, as it looked then, to where the change lays it out (said once, then
// followed as a way's end is: what moves it after for another cause, a window made narrower, it goes with). On its way
// it is drawn over the rest of its layer (the node of the root's it is in), in the window's terms: cut, faded and grown
// by nothing that holds it, and found by a press where it is drawn. The old one is kept as a copy on the same way, laid
// out nowhere and taking nothing, under it: the new one comes in over the first half, the old one goes over the second.
// Both are drawn as their ground, edge, corners and ink go from the old one's to the new one's (the new one's as it is
// said now, followed). What it holds is drawn as it is laid out at its end, as big as the way has it (grown with it).
// Where it is at a moment is worked out from where it set out, where it went, its way and that moment alone.
//
// No pair: one only let go of (or leaving) goes as it would have (what was let go of let go as the change ends, nothing
// drawn between); one only made comes as it would have. One let go of that no layout ever placed (made and let go in
// one change: a page's list's blocks shown by their count in one pass of its fill, then not in a later; or made in a
// box placed before, the box let go of in the same change) is none to fly from (Tree::departs_of, Node's `placed`).
// Two of an id let go of or made in one change, or one made while another of its id lives, is a fault (Tree::fault: a
// test fails), and none of them flies. A pair made again on its way (opened, then closed before it is there) sets out
// from where it is drawn then, its old copy let go of at once.
// One end may stay where it is (View::shared's `stays`: a picture's thumbnail, the other end the picture opened over
// everything): it is never let go of for a flight nor made for one, and pairs with no other that stays. One that moves
// may fly with one that stays alone (`with_stays`): made in the place of another of its id that moves (the picture's
// viewer made again for another tier of the window), it is there at once, the other let go of, no flight between. While one of its
// id that moves lives, it keeps its room and is drawn nowhere, whatever holds it says (the tree's say, by the id, never
// what holds it). One that moves made in a change while it lives flies from where it was drawn as the change came, as
// it looked; one that moves let go of in a change while it lives is drawn there no more, and it flies from where that
// one was drawn back to its own place, drawn again as it sets out. Neither fades: one picture moves. The one that moves
// is drawn where it is held, not over the rest of its layer: what is drawn after it there (its viewer's bar) over it.
// Its room cut by what holds it as it set out, and less what lies over the top of what scrolls it and what is pinned
// over that one's foot (Scroll::top_covered, a page's list's foot: the bar a chat's list runs under, its composer), is
// what is drawn of it, on its way, as far as it is there (the cut opens to the window as it leaves, closes to it as it
// comes back); one wholly under them is drawn nowhere and pairs with nothing; a picture in it drawn on the way as the end that stays draws
// it (covering, contained) in the box the way has, so it is as that end draws it at that end and as the other draws it
// at the other. One that stays that is drawn nowhere (no layout placed it, scrolled out of the window, cut to nothing)
// pairs with nothing: the other comes or goes as it would have. A change of the id of one that moves pairs nothing:
// what stays of its old id is drawn again at once, what stays of its new one drawn nowhere; nor does one that moves let
// go of and another made in one change by other ids (a picture stepped to the one beside it, one in the other's place).
// Not yet: what the new one holds laid out again at each size on its way (it is drawn grown as it is laid out at its
// end), its words morphing glyph by glyph, its scale and turn mixed, a way going on as fast as it went.

///|
/// How a shared node flies (View::shared): for a flight `far` points long (the furthest its place or size goes), how long
/// it takes (ms; 0: there at once, as with motion reduced) and how far along it is at each ms from its start (0 → 1):
/// @motion's shared, a Move.
pub(all) struct Flight {
  way : (Double) -> (Double, (Double) -> Double)
}

///|
/// The look a flight sets out from (the old one's as the change came, or where one on its way had got to): its ground,
/// its edge, its corners (points, as drawn), its words' ink.
priv struct FromLook {
  ground : Int64
  edge : (Double, Int64)
  corners : (Double, Double, Double, Double)
  ink : Int64
}

///|
/// One drawn on a flight's way (Node's `lift`): the node whose place and size it goes to (the new one: itself, or the
/// one its old copy goes with), the node of the root's it is drawn over the rest of (the layer it is in), how far off
/// that place and size it set out (across, down, wider, taller), how much of the way is left (1 → 0) and how far it is
/// faded in (the new one) or not yet out (the old one), and the look it set out from.
priv struct Lift {
  follow : Int
  top : Int
  d : (Double, Double, Double, Double)
  mut k : Double
  mut a : Double
  from : FromLook
  /// a flight with an end that stays (View::shared's `stays`): how that end draws its picture (covering, along; contained),
  /// drawn so on the way; and its room as cut by what held it, what is drawn of it at that end (`at_start`: the end it
  /// sets out from)
  stays : StaysEnd?
}

///|
/// The end of a flight that stays where it is (Lift's `stays`): how it draws its picture (View::image_covers,
/// image_covers_at, image_contains), its room in the window cut by what holds it, and whether it is where the flight
/// sets out (else where it comes to).
priv struct StaysEnd {
  cover : Bool
  cover_at : Double?
  contain : Bool
  cut : (Double, Double, Double, Double)
  at_start : Bool
}

///|
/// A node with an id let go of (or set leaving) in the change being committed: the id, the node with it, where it was
/// drawn as the change came and as it looked, and what the structure let go of with it (it, or what holds it): parked
/// till the change is committed (`leaving`: leaving, where it is).
priv struct Departure {
  id : String
  node : NodeId
  from : (Double, Double, Double, Double)
  look : FromLook
  held : NodeId
  leaving : Bool
}

///|
/// A flight under way: the new node, the old one's copy (none once let go), its start and length, how far along it is
/// at each ms, the layer it is drawn over, and what ends it (its binding and its end on the timeline).
priv struct Flying {
  node : NodeId
  mut ghost : NodeId?
  /// faded in as it comes (false: one with an end that stays, one picture moving)
  fades : Bool
  start : Double
  dur : Double
  along : (Double) -> Double
  top : Int
  mut stop : () -> Unit
}

///|
/// One with id `id`, flying as `flight` says from the one with its id let go of in the change it is made in (or that
/// sets it this id): see the head of this file. The id said By follows what it reads; a change of it pairs nothing.
/// `stays`: the end that stays where it is. `with_stays`: one that moves flying only from or to one of its id that stays,
/// never from another that moves (the same thing made again in another place, as a window changes tier: there at once).
#callsite(autofill(loc))
pub fn View::shared(
  self : View,
  id : Live[String],
  flight : Flight,
  stays? : Bool = false,
  with_stays? : Bool = false,
  loc~ : SourceLoc,
) -> View {
  guard self.live() is Some(n) else { return self }
  ignore(loc)
  n.share_flight = Some(flight)
  n.share_stays = stays
  n.share_with_stays = with_stays && !stays
  let tree = self.tree
  let at = self.at
  let gen = self.gen
  let first = Ref(true)
  let set = fn(s : String) {
    let n = tree.nodes[at]
    guard n.live && n.gen == gen else { return }
    match n.share {
      Some(was) if was == s => return
      Some(was) => tree.share_counted(at, was, -1)
      None => ()
    }
    n.share = Some(s)
    tree.share_counted(at, s, 1)
    // (made in a change: one that may pair with one let go of in it, as it is committed whole; one that stays never)
    if first.val && tree.in_change() && !n.share_stays {
      tree.arrivals.push({ at, gen })
      tree.pairs_due()
    }
    first.val = false
  }
  match id {
    Is(s) => set(s)
    By(f) => {
      let stop = tree.queued(f, set)
      self.owns(stop) |> ignore
    }
  }
  self
}


///|
/// One made in a change that flies in from what is none of the window's tree (View::flies_in): the node, and where it
/// sets out given where it is laid out as that change is committed (its place and size in the window).
priv struct Incoming {
  node : NodeId
  from : ((Double, Double, Double, Double)) -> (Double, Double, Double, Double)?
}

///|
/// Made in the change being committed, it flies, as that change is committed whole, from what is none of the window's
/// tree (an old view's words, a text field's: nothing of it here to let go of, so no old copy) to where that change
/// lays it out: from where `from` says, given that place and size in the window (None: no flight, there at once),
/// looking there as a thing with no ground and no edge would, its corners and ink its own, coming to its own look on
/// the way; one thing moving, never faded, drawn over the rest of its layer all the way, as one View::shared pairs
/// (the head of this file). `flight` is the way, @motion's shared, a Move. Made outside a change it is there at once.
#callsite(autofill(loc))
pub fn View::flies_in(
  self : View,
  flight : Flight,
  from : ((Double, Double, Double, Double)) -> (Double, Double, Double, Double)?,
  loc~ : SourceLoc,
) -> View {
  ignore(loc)
  guard self.live() is Some(n) && self.tree.in_change() else { return self }
  n.share_flight = Some(flight)
  self.tree.incoming.push({ node: { at: self.at, gen: self.gen }, from })
  self.tree.pairs_due()
  self
}

///|
/// Those made in the change committed now that fly in from outside the tree (View::flies_in), each set flying from
/// where it says, given where it is laid out now; one let go of meanwhile, or no longer in the window's tree, none.
fn Tree::incoming_now(self : Tree) -> Unit {
  let all = self.incoming.copy()
  self.incoming.clear()
  for i in all {
    guard self.alive_id(i.node) && self.attached(i.node.at) else { continue }
    let n = self.nodes[i.node.at]
    let to = self.handle(i.node.at).laid_window_now()
    guard (i.from)(to) is Some(from) else { continue }
    let (a, b, c, d) = corners_of(n.look)
    let look : FromLook = {
      ground: n.look.ground & 0xFFFFFF00L,
      edge: (0.0, n.look.edge.1 & 0xFFFFFF00L),
      corners: (a, b, c, d),
      ink: n.look.ink,
    }
    self.fly_from(i.node, from, look, None) |> ignore
  }
}
///|
/// The id it is shared by (View::shared), none where it is not.
pub fn View::shared_id(self : View) -> String? {
  guard self.live() is Some(n) else { return None }
  n.share
}

///|
/// Where the one of id `id` on a flight's way is drawn in the window now (x, y, w, h) and its corners as drawn there
/// (top left, then round it), the one that comes (not an old copy); none where none of it flies.
pub fn Tree::flight_drawn(
  self : Tree,
  id : String,
) -> ((Double, Double, Double, Double), (Double, Double, Double, Double))? {
  for f in self.flights {
    guard self.alive_id(f.node) else { continue }
    let n = self.nodes[f.node.at]
    guard n.share == Some(id) && n.lift is Some(l) else { continue }
    return Some((self.lift_rect(l), self.look_from(f.node.at, 1.0).corners))
  }
  None
}

///|
/// When the flight of the one of id `id` under way ends (ms, the clock's); none where none of it flies.
pub fn Tree::flight_ends_at(self : Tree, id : String) -> Double? {
  for f in self.flights {
    guard self.alive_id(f.node) else { continue }
    let n = self.nodes[f.node.at]
    guard n.share == Some(id) && n.lift is Some(_) else { continue }
    return Some(f.start + f.dur)
  }
  None
}

///|
/// What of the window node `id` is drawn within on a flight with an end that stays (View::shared's `stays`): that end's
/// room as cut by what held it, opening to its layer's as it leaves it, closing to it as it comes back (x0, y0, x1, y1);
/// none, on any other flight or none.
pub fn Tree::lift_cut(self : Tree, id : NodeId) -> (Double, Double, Double, Double)? {
  guard self.alive_id(id) && self.nodes[id.at].lift is Some(l) && l.stays is Some(e) else { return None }
  let (wx, wy, ww, wh) = self.placed_window(l.top)
  let (x0, y0, x1, y1) = (wx, wy, wx + ww, wy + wh)
  let (c0, c1, c2, c3) = e.cut
  let (c0, c1, c2, c3) = (dmax(c0, x0), dmax(c1, y0), dmin(c2, x1), dmin(c3, y1))
  // (how far it is from that end: 0 there, 1 at the other)
  let p = 1.0 - l.k
  let t = if e.at_start { p } else { 1.0 - p }
  // (and within where it is drawn on its way: what is seen of it, the box its corners round, Tree::lift_cut_corners)
  let (lx, ly, lw, lh) = self.lift_rect(l)
  Some(
    (
      dmax(c0 + (x0 - c0) * t, lx),
      dmax(c1 + (y0 - c1) * t, ly),
      dmin(c2 + (x1 - c2) * t, lx + lw),
      dmin(c3 + (y1 - c3) * t, ly + lh),
    ),
  )
}

///|
/// The corners (top left, then round it) what Tree::lift_cut gives is rounded by: the flight's own as it is drawn then,
/// so that what is seen of it on its way, cut to the window or to that room, is as round as the flight has it; none
/// where Tree::lift_cut gives none.
pub fn Tree::lift_cut_corners(self : Tree, id : NodeId) -> (Double, Double, Double, Double)? {
  guard self.alive_id(id) && self.nodes[id.at].lift is Some(l) && l.stays is Some(_) else { return None }
  Some(self.look_from(id.at, 1.0).corners)
}

///|
/// Whether it is drawn on a flight's way now (View::shared): the new one or the old one's copy.
pub fn View::flies(self : View) -> Bool {
  guard self.live() is Some(n) else { return false }
  n.lift is Some(_)
}

///|
/// How many living nodes have id `id` (View::shared) told `by` more.
fn Tree::share_count(self : Tree, id : String, by : Int) -> Unit {
  let k = self.shared_live.get(id).unwrap_or(0) + by
  if k <= 0 {
    self.shared_live.remove(id)
  } else {
    self.shared_live[id] = k
  }
  self.shared_n = self.shared_n + by
}

///|
/// Node `at`'s id `id` counted `by` more (View::shared): all of them, and those that move or those that stay apart; where
/// one that moves comes to be or no longer is, what stays of its id drawn again (Tree::stays_marked).
fn Tree::share_counted(self : Tree, at : Int, id : String, by : Int) -> Unit {
  self.share_count(id, by)
  if self.nodes[at].share_stays {
    let all = self.shared_stays.get(id).unwrap_or([])
    if by > 0 {
      if !all.contains(at) {
        all.push(at)
      }
      self.shared_stays[id] = all
    } else {
      all.retain(fn(i) { i != at })
      if all.is_empty() {
        self.shared_stays.remove(id)
      } else {
        self.shared_stays[id] = all
      }
    }
    // (one that stays come or gone as one that moves lives: drawn nowhere, or there again)
    self.lift_marked(at)
    return
  }
  let was = self.shared_moving.get(id).unwrap_or(0)
  let k = was + by
  if k <= 0 {
    self.shared_moving.remove(id)
  } else {
    self.shared_moving[id] = k
  }
  if (was > 0) != (k > 0) {
    self.stays_marked(id)
  }
}

///|
/// Whether node `n` (one that stays: View::shared's `stays`) is drawn nowhere now: one of its id that moves lives.
fn Tree::stays_hidden(self : Tree, n : Node) -> Bool {
  match n.share {
    Some(id) => self.shared_moving.get(id).unwrap_or(0) > 0
    None => false
  }
}

///|
/// What stays of id `id` drawn again as it is drawn nowhere or there once more.
fn Tree::stays_marked(self : Tree, id : String) -> Unit {
  match self.shared_stays.get(id) {
    Some(all) =>
      for at in all {
        if self.nodes[at].live {
          self.lift_marked(at)
        }
      }
    None => ()
  }
}

///|
/// The one that stays of id `id` a flight may come from or go to now: living, held in the window's tree, placed by a
/// layout, and some of it seen in its layer as what holds it cuts it and as what covers what scrolls it leaves it
/// (Tree::stays_bounds); none, none.
fn Tree::stays_end(self : Tree, id : String) -> Int? {
  guard self.shared_stays.get(id) is Some(all) else { return None }
  for at in all {
    let n = self.nodes[at]
    guard n.live && n.placed && self.attached(at) else { continue }
    let (x, y, _, s) = self.projected(at)
    let (w, h) = (n.lw * s, n.lh * s)
    let (bx0, by0, bx1, by1) = self.stays_bounds(at)
    // (and within its layer, the window's part it is drawn in)
    let (lx, ly, lw, lh) = self.placed_window(self.top_node_of(at))
    let (x0, y0) = (dmax(dmax(x, bx0), lx), dmax(dmax(y, by0), ly))
    let (x1, y1) = (dmin(dmin(x + w, bx1), lx + lw), dmin(dmin(y + h, by1), ly + lh))
    if x1 > x0 && y1 > y0 && w > 0.0 && h > 0.0 {
      return Some(at)
    }
  }
  None
}

///|
/// What of the window node `at` (one that stays) is seen within (x0, y0, x1, y1): what holds it cuts it to
/// (Tree::seen_bounds), less what lies over the top of what scrolls it and what is pinned over its foot
/// (Scroll::top_covered, a page's list's foot: the bar it runs under, its composer), as they are said now.
fn Tree::stays_bounds(self : Tree, at : Int) -> (Double, Double, Double, Double) {
  let n = self.nodes[at]
  let (bx0, by0, bx1, by1) = self.seen_bounds({ at, gen: n.gen })
  let mut top = by0
  let mut foot = by1
  let mut i = n.parent
  while i >= 0 {
    match self.scrolls_at.get(i) {
      Some(sc) if !sc.across => {
        let (_, y, s) = self.placed(i)
        let h = self.nodes[i].flex.height * s
        let (over, under) = @signals.untracked(fn() { (sc.top_covered(), sc.foot_covered_now()) })
        top = dmax(top, y + over * s)
        foot = dmin(foot, y + h - under * s)
      }
      _ => ()
    }
    i = self.nodes[i].parent
  }
  (bx0, top, bx1, foot)
}

///|
/// Whether one of id `id` that stays (View::shared's `stays`) would be flown to now: one placed, some of it drawn in the
/// window. What closes the other end asks it, to let that one go at once (flown back to it) rather than fade it out.
pub fn Tree::stays_seen(self : Tree, id : String) -> Bool {
  self.stays_end(id) is Some(_)
}

///|
/// The end that stays at node `at` as a flight takes it (Lift's `stays`): how it draws its picture, its room cut by what
/// holds it and by what covers what scrolls it (Tree::stays_bounds), which end it is.
fn Tree::stays_of(self : Tree, at : Int, at_start : Bool) -> StaysEnd {
  let n = self.nodes[at]
  let (bx0, by0, bx1, by1) = self.stays_bounds(at)
  {
    cover: n.look.image_cover,
    cover_at: n.look.image_cover_at,
    contain: n.look.image_contain,
    cut: (bx0, by0, bx1, by1),
    at_start,
  }
}

///|
/// Whether a change is being committed now (an event, a structure's change, a moment come on the timeline).
fn Tree::in_change(self : Tree) -> Bool {
  self.committing > 0 || self.cause_at >= 0.0
}

///|
/// The shared nodes in node `at` (it, or what it holds), the outermost of each: none in another of them.
fn Tree::shared_in(self : Tree, at : Int, out : Array[Int]) -> Unit {
  let n = self.nodes[at]
  if n.share is Some(_) {
    out.push(at)
    return
  }
  for k in n.kids {
    self.shared_in(k, out)
  }
}

///|
/// Where node `at` stands in the window as it was last placed (its place and each holder's, as far as a column scrolls
/// it: View::placed_window_now's), and how big.
fn Tree::placed_window(self : Tree, at : Int) -> (Double, Double, Double, Double) {
  let mut x = 0.0
  let mut y = 0.0
  let mut i = at
  while i >= 0 {
    let m = self.nodes[i]
    if !m.slot {
      x = x + m.lx
      y = y + m.ly
      if m.scroll_off is Some(_) {
        let (sx, sy) = self.scroll_off_now(m)
        x = x + sx
        y = y + sy
      }
    }
    i = m.parent
  }
  (x, y, self.nodes[at].lw, self.nodes[at].lh)
}

///|
/// Where node `n`, on a flight's way as `l` says, is drawn in the window now and how big: off the place and size of the
/// one it goes with by what is left of how far off it set out.
fn Tree::lift_rect(self : Tree, l : Lift) -> (Double, Double, Double, Double) {
  let (x, y, w, h) = self.placed_window(l.follow)
  let k = l.k
  (x + l.d.0 * k, y + l.d.1 * k, dmax(w + l.d.2 * k, 0.0), dmax(h + l.d.3 * k, 0.0))
}

///|
/// How big what node `n` holds is drawn on its flight's way (`w` wide as it is drawn): as wide as it is drawn for as
/// wide as it is laid out.
fn lift_scale(n : Node, w : Double) -> Double {
  if n.lw > 0.0 {
    w / n.lw
  } else {
    1.0
  }
}

///|
/// Where node `at` is drawn in the window, how opaque and how big, where it is on a flight's way (Node's `lift`): the
/// window's terms, nothing that holds it counted.
fn Tree::lifted_place(self : Tree, n : Node, l : Lift) -> (Double, Double, Double, Double) {
  let (x, y, w, _) = self.lift_rect(l)
  (x, y, n.look.alpha * l.a, lift_scale(n, w))
}

///|
/// Its corners in points: those it says, else its radius at each.
fn corners_of(look : Look) -> (Double, Double, Double, Double) {
  match look.corners {
    Some(c) => c
    None => (look.radius, look.radius, look.radius, look.radius)
  }
}

///|
/// What node `n` looks like where it is drawn now, as a flight sets out from it: its ground, edge, corners as big as
/// it is drawn (`s`) and ink; one on a flight's way as it is drawn there.
fn Tree::look_from(self : Tree, at : Int, s : Double) -> FromLook {
  let n = self.nodes[at]
  match n.lift {
    Some(l) => {
      let p = 1.0 - l.k
      let to = self.nodes[l.follow].look
      let c = corners_mix(l.from.corners, corners_of(to), p)
      {
        ground: colour_mix(l.from.ground, to.ground, p),
        edge: (l.from.edge.0 + (to.edge.0 - l.from.edge.0) * p, colour_mix(l.from.edge.1, to.edge.1, p)),
        corners: c,
        ink: colour_mix(l.from.ink, to.ink, p),
      }
    }
    None => {
      let (a, b, c, d) = corners_of(n.look)
      {
        ground: n.look.ground,
        edge: (n.look.edge.0 * s, n.look.edge.1),
        corners: (a * s, b * s, c * s, d * s),
        ink: n.look.ink,
      }
    }
  }
}

///|
/// Four corners from `a` to `b`, `p` of the way.
fn corners_mix(
  a : (Double, Double, Double, Double),
  b : (Double, Double, Double, Double),
  p : Double,
) -> (Double, Double, Double, Double) {
  (a.0 + (b.0 - a.0) * p, a.1 + (b.1 - a.1) * p, a.2 + (b.2 - a.2) * p, a.3 + (b.3 - a.3) * p)
}

///|
/// Two colours (0xRRGGBBAA) mixed `p` of the way, each channel by its square and the alpha straight (ui's mix_colour,
/// the web's mixColor); one of them none (clear): the other's colour, its alpha from none.
fn colour_mix(a : Int64, b : Int64, p : Double) -> Int64 {
  if a == b || p >= 1.0 {
    return b
  }
  if p <= 0.0 {
    return a
  }
  let a = if (a & 0xFFL) == 0L { b & 0xFFFFFF00L } else { a }
  let b = if (b & 0xFFL) == 0L { a & 0xFFFFFF00L } else { b }
  let ch = fn(c : Int64, s : Int) { ((c >> s) & 0xFFL).to_double() / 255.0 }
  let one = fn(s : Int) {
    let x = ch(a, s)
    let y = ch(b, s)
    let e = x * x + (y * y - x * x) * p
    let v = if e < 0.0 { 0.0 } else { e.sqrt() }
    (v * 255.0 + 0.5).floor().to_int64()
  }
  let x = ch(a, 0)
  let y = ch(b, 0)
  let alpha = ((x + (y - x) * p) * 255.0 + 0.5).floor().to_int64()
  (one(24) << 24) | (one(16) << 16) | (one(8) << 8) | alpha
}

///|
/// Node `n`'s content as a flight draws it (Node's `lift`): as big as its way has it (in its own terms, `s` as big as
/// what it holds is drawn), its ground, edge, corners and ink from those it set out from to the one it goes with's.
fn Tree::lifted_content(self : Tree, n : Node, l : Lift, c : Content) -> Content {
  let (_, _, w, h) = self.lift_rect(l)
  let s = lift_scale(n, w)
  let p = 1.0 - l.k
  let to = self.nodes[l.follow].look
  let (a, b, cc, d) = corners_mix(l.from.corners, corners_of(to), p)
  {
    ..c,
    w: if s > 0.0 { w / s } else { c.w },
    h: if s > 0.0 { h / s } else { c.h },
    ground: colour_mix(l.from.ground, to.ground, p),
    edge: ((l.from.edge.0 + (to.edge.0 - l.from.edge.0) * p) / s, colour_mix(l.from.edge.1, to.edge.1, p)),
    corners: Some((a / s, b / s, cc / s, d / s)),
    radius: a / s,
    ink: colour_mix(l.from.ink, to.ink, p),
    // (a picture drawn on the way as the end that stays draws it, in the box the way has: as that end at it, as the
    // other at its end, where the box is the picture's own)
    image_cover: match l.stays {
      Some(e) => e.cover
      None => c.image_cover
    },
    image_cover_at: match l.stays {
      Some(e) => e.cover_at
      None => c.image_cover_at
    },
    image_contain: match l.stays {
      Some(e) => e.contain
      None => c.image_contain
    },
  }
}

///|
/// Node `v` (held by `holder`, a structure's) let go of in the change being committed, where it is or holds a shared
/// node: taken out of what holds it (View::park) and kept till the change is committed whole, then let go of, or kept
/// as the copy of what flies (Tree::pairs_now). Whether it was so kept.
fn Tree::departs(self : Tree, holder : View, v : View) -> Bool {
  guard self.shared_n > 0 && self.in_change() && v.live() is Some(n) && n.left_at < 0.0 else {
    return false
  }
  let found = self.departs_of(v)
  // (none to fly: `v` let go of as it would have been, nothing parked)
  guard found.length() > 0 else { return false }
  self.departed(found, v.id(), false)
  holder.park(v) |> ignore
  true
}

///|
/// Node `v` set leaving in the change being committed (View::leave), where it is or holds a shared node: what may fly
/// from it as the change is committed whole (Tree::pairs_now), it leaving meanwhile.
fn Tree::departs_leaving(self : Tree, v : View) -> Unit {
  guard self.shared_n > 0 && self.in_change() && v.live() is Some(_) else { return }
  let found = self.departs_of(v)
  guard found.length() > 0 else { return }
  self.departed(found, v.id(), true)
}

///|
/// The shared nodes in node `v` (Tree::shared_in) that may fly from where they were drawn: each a layout has placed.
/// It is the node that would fly that is asked, not `v`: one never placed (made and let go of in one change, a page's
/// list's fill's passes; or made in a change in a box placed before it, the box let go of in the same change) was drawn
/// nowhere, nothing flies from it, and it is let go of as it would have been.
fn Tree::departs_of(self : Tree, v : View) -> Array[Int] {
  let found : Array[Int] = []
  self.shared_in(v.at, found)
  found.filter(fn(at) { self.nodes[at].placed })
}

///|
/// The shared nodes `found`, let go of with `held` (or leaving with it), told as such: where each was drawn as the
/// change came (where it was on a flight's way, its flight ended), as it looked.
fn Tree::departed(self : Tree, found : Array[Int], held : NodeId, leaving : Bool) -> Unit {
  for at in found {
    let n = self.nodes[at]
    guard n.share is Some(id) else { continue }
    let (from, look) = match n.lift {
      Some(l) => {
        // (on a flight's way: where it is drawn as of the change's moment, as it looks there; that flight over)
        match self.flying_of(at) {
          Some(f) => self.flight_at(f, self.cause_now())
          None => ()
        }
        let (x, y, w, h) = self.lift_rect(l)
        let look = self.look_from(at, 1.0)
        match self.flying_of(at) {
          Some(f) => self.flight_over(f)
          None => ()
        }
        ((x, y, w, h), look)
      }
      None => {
        let (x, y, _, s) = self.projected(at)
        ((x, y, n.lw * s, n.lh * s), self.look_from(at, s))
      }
    }
    self.departures.push({ id, node: { at, gen: n.gen }, from, look, held, leaving })
  }
  self.pairs_due()
}

///|
/// What is let go of and made in the change being committed to be paired once it is committed whole: then, where it is
/// none's (a batch of signals set outside, told as its flush ends); else as that change ends (Tree::event_said,
/// Tree::advance_loop, Tree::at_cause).
fn Tree::pairs_due(self : Tree) -> Unit {
  if self.pairs_asked {
    return
  }
  self.pairs_asked = true
}

///|
/// The pairs of the change committed now at `at`, where any was told (Tree::pairs_due), outside every change: once its
/// flush ends.
fn Tree::pairs_after(self : Tree, at : Double) -> Unit {
  guard self.pairs_asked else { return }
  @signals.after_flush(fn() {
    if self.committing > 0 || self.cause_at >= 0.0 {
      return
    }
    let was = self.cause_at
    self.cause_at = at
    self.pairs_now()
    self.cause_at = was
  })
}

///|
/// The change being committed, committed whole: what was let go of and made in it with the same id paired, each pair
/// set flying from its moment; what was let go of and paired with nothing let go of now.
fn Tree::pairs_now(self : Tree) -> Unit {
  guard self.pairs_asked else { return }
  self.pairs_asked = false
  let deps = self.departures.copy()
  self.departures.clear()
  let arrs = self.arrivals.copy()
  self.arrivals.clear()
  self.committing += 1
  @signals.start_batch()
  // (made in it, there still, in the window's tree (none in what was let go of meanwhile), each once)
  let made : Array[NodeId] = []
  for a in arrs {
    if self.alive_id(a) && self.attached(a.at) && !made.contains(a) && self.nodes[a.at].share is Some(_) {
      made.push(a)
    }
  }
  let ids : Array[String] = []
  for d in deps {
    if !ids.contains(d.id) {
      ids.push(d.id)
    }
  }
  for a in made {
    match self.nodes[a.at].share {
      Some(id) if !ids.contains(id) => ids.push(id)
      _ => ()
    }
  }
  // (what was let go of with what flies from it: kept as its old copy, the rest let go of already)
  let flown : Array[NodeId] = []
  // (those that move made or let go of alone of their ids, where one of the id stays)
  let from_stays : Array[(Int, NodeId)] = []
  let to_stays : Array[(Departure, Int)] = []
  let came_alone = Ref(false)
  let went_alone = Ref(false)
  for id in ids {
    let gone = deps.filter(fn(d) { d.id == id })
    let come = made.filter(fn(a) { self.nodes[a.at].share == Some(id) })
    // (those that move: one that stays is none of them, View::shared's `stays`)
    let living = self.shared_moving.get(id).unwrap_or(0) - gone.length()
    if gone.length() > 1 || come.length() > 1 {
      // (the node it is told under: one made, else one let go of; never both looked up, as `unwrap_or(gone[0]…)`
      // did, which with none let go stopped the run on an index out of bounds before the fault was told)
      let under = match come.get(0) {
        Some(c) => c
        None => gone[0].node
      }
      self.fault(under, "shared: \{id} let go of or made more than once in one change")
    } else if come.length() == 1 && living > 1 {
      self.fault(come[0], "shared: \{id} made while another of it lives")
    } else if gone.length() == 1 && come.length() == 1 {
      // (one said `with_stays` made in the place of another that moves: the same thing made again, there at once, the
      // old let go of with the rest)
      if !self.nodes[come[0].at].share_with_stays && self.paired(gone[0], come[0]) is Some(_) {
        flown.push(gone[0].held)
      }
    } else if come.length() == 1 && gone.length() == 0 {
      came_alone.val = true
      // (one that moves made where one of its id stays: from that one, below)
      match self.stays_end(id) {
        Some(st) => from_stays.push((st, come[0]))
        None => ()
      }
    } else if gone.length() == 1 && come.length() == 0 && living == 0 {
      went_alone.val = true
      // (the last that moves let go of where one of its id stays: back to that one, below)
      match self.stays_end(id) {
        Some(st) => to_stays.push((gone[0], st))
        None => ()
      }
    }
  }
  // (one that moves let go of and another made in the same change, by other ids, is one in the other's place (a
  // picture stepped to the one beside it): neither flies to or from what stays, what stays of either id drawn again or
  // nowhere at once, as where the id of one changes; else each flies)
  let swapped = came_alone.val && went_alone.val
  if !swapped {
    for e in from_stays {
      self.from_stays(e.0, e.1)
    }
    for e in to_stays {
      if self.to_stays(e.0, e.1) {
        flown.push(e.0.held)
      }
    }
  }
  // (what was let go of with no flight from it: let go of now, as it would have been; what leaves, left leaving)
  let let_go : Array[NodeId] = []
  for d in deps {
    if !d.leaving && !flown.contains(d.held) && !let_go.contains(d.held) && self.alive_id(d.held) {
      let_go.push(d.held)
    }
  }
  for h in let_go {
    self.handle(h.at).let_go()
  }
  // (what flies in from outside the tree, made in it: View::flies_in)
  self.incoming_now()
  @signals.end_batch()
  self.committing -= 1
  self.modals_settled()
}

///|
/// Whether node `at` is held in the window's tree (by the root, through what holds it): none parked, let go of or a
/// flight's old copy.
fn Tree::attached(self : Tree, at : Int) -> Bool {
  let mut i = at
  while i > 0 {
    i = self.nodes[i].parent
  }
  i == 0
}

///|
/// The node of the root's node `at` is in (it, where the root holds it), through what holds it.
fn Tree::top_node_of(self : Tree, at : Int) -> Int {
  let mut i = at
  let mut top = at
  while i > 0 {
    if !self.nodes[i].slot {
      top = i
    }
    i = self.nodes[i].parent
  }
  top
}

///|
/// Departure `d` and node `to` made in the same change paired: `to` set flying from where `d`'s was drawn, `d`'s node
/// kept as its old copy on the same way (what it was let go of with let go of now, all but it). Its old copy, where it
/// flies.
fn Tree::paired(self : Tree, d : Departure, to : NodeId) -> NodeId? {
  guard self.alive_id(d.node) && self.alive_id(d.held) else { return None }
  let ghost = d.node.at
  let held = d.held.at
  // (leaving: none of it leaves now, it is let go of as the flight takes its place)
  if d.leaving {
    let h = self.nodes[held]
    h.left_at = -1.0
    h.back_at = -1.0
    told_going(h)
    self.timeline.retain(fn(e) {
      match e {
        Leaves(i, _) => i != d.held
        _ => true
      }
    })
    if h.parent >= 0 {
      self.handle(h.parent).park(self.handle(held)) |> ignore
    }
  }
  // (its old copy alone kept: taken out of what it was let go of with, the rest of that let go of)
  if ghost != held {
    let g = self.nodes[ghost]
    let p = g.parent
    if p >= 0 {
      match self.nodes[p].kids.search(ghost) {
        Some(i) => self.nodes[p].kids.remove(i) |> ignore
        None => ()
      }
    }
    g.parent = -1
    self.handle(held).let_go()
  }
  let g = self.nodes[ghost]
  // (taking nothing, read out as nothing, its id none of the living's)
  g.inert = true
  g.said_hidden = true
  match g.share {
    Some(id) => {
      self.share_counted(ghost, id, -1)
      g.share = None
    }
    None => ()
  }
  let to_v = self.handle(to.at)
  let flight = match self.nodes[to.at].share_flight {
    Some(f) => f
    None => return None
  }
  let (tx, ty, tw, th) = to_v.laid_window_now()
  let (fx, fy, fw, fh) = d.from
  let dd = (fx - tx, fy - ty, fw - tw, fh - th)
  let far = dmax(dmax((dd.0 * dd.0 + dd.1 * dd.1).sqrt(), dd.2.abs()), dd.3.abs())
  let (ms, along) = (flight.way)(far)
  if ms <= 0.0 || far <= 0.5 {
    self.handle(ghost).let_go()
    return None
  }
  let at = self.cause_now()
  let top = self.top_node_of(to.at)
  let f : Flying = {
    node: to,
    ghost: Some({ at: ghost, gen: g.gen }),
    fades: true,
    start: at,
    dur: ms,
    along,
    top,
    stop: fn() {  },
  }
  self.flights.push(f)
  self.nodes[to.at].lift = Some({ follow: to.at, top, d: dd, k: 1.0, a: 0.0, from: d.look, stays: None })
  g.lift = Some({ follow: to.at, top, d: dd, k: 1.0, a: 1.0, from: d.look, stays: None })
  self.lifted_order()
  // (drawn as of each frame's moment while it goes; over at its end, a moment of its own)
  let stop_way = self.queued(fn() { self.drawn_at() }, fn(t) { self.flight_at(f, t) })
  let stop_end = to_v.at_moment(at + ms, fn() { self.flight_over(f) })
  let unkeep = to_v.owns_while(fn() { self.flight_over(f) })
  f.stop = fn() {
    stop_way()
    stop_end()
    unkeep()
  }
  Some({ at: ghost, gen: g.gen })
}

///|
/// Node `to` (one that moves) made where node `st` of its id stays: set flying from where `st` is drawn as the change
/// came, as it looks, its picture as `st` draws it, its room as cut where `st` is (the file's head). `st` drawn nowhere
/// meanwhile, as one of its id that moves lives.
fn Tree::from_stays(self : Tree, st : Int, to : NodeId) -> Unit {
  let n = self.nodes[st]
  let (x, y, _, s) = self.projected(st)
  self.fly_stays(to, (x, y, n.lw * s, n.lh * s), self.look_from(st, s), self.stays_of(st, true)) |> ignore
}

///|
/// Departure `d` (the last of its id that moves) let go of where node `st` of its id stays: `st` set flying from where
/// `d`'s was drawn, as it looked, back to its own place, its picture as it draws it, its room as cut where it is; what
/// `d`'s was let go of with let go of as it would have been, its node drawn no more. Whether it flies.
fn Tree::to_stays(self : Tree, d : Departure, st : Int) -> Bool {
  guard self.alive_id(d.node) && self.alive_id(d.held) else { return false }
  let to : NodeId = { at: st, gen: self.nodes[st].gen }
  if !self.fly_stays(to, d.from, d.look, self.stays_of(st, false)) {
    return false
  }
  // (what moved drawn no more: taken out of what it was let go of with and let go of, the rest as it would have gone)
  let at = d.node.at
  if at != d.held.at {
    let g = self.nodes[at]
    let p = g.parent
    if p >= 0 {
      match self.nodes[p].kids.search(at) {
        Some(i) => self.nodes[p].kids.remove(i) |> ignore
        None => ()
      }
    }
    g.parent = -1
    self.handle(at).let_go()
    false
  } else {
    // (it alone let go of: let go of now, nothing left of it to go)
    self.handle(at).let_go()
    true
  }
}

///|
/// Node `to` set flying from `from` (where it sets out, how it looks there) to its place, one picture moving: not faded,
/// no old copy, `stays` its end that stays. Whether it flies (not, at once: as with motion reduced, or as far as nothing).
fn Tree::fly_stays(
  self : Tree,
  to : NodeId,
  from : (Double, Double, Double, Double),
  look : FromLook,
  stays : StaysEnd,
) -> Bool {
  self.fly_from(to, from, look, Some(stays))
}

///|
/// Node `to` set flying from `from` (where it sets out, how it looks there) to its place, one thing moving: not faded,
/// no old copy, `stays` its end that stays where there is one (View::shared's; none: View::flies_in's). Whether it
/// flies (not, at once: as with motion reduced, or as far as nothing).
fn Tree::fly_from(
  self : Tree,
  to : NodeId,
  from : (Double, Double, Double, Double),
  look : FromLook,
  stays : StaysEnd?,
) -> Bool {
  guard self.alive_id(to) && self.nodes[to.at].share_flight is Some(flight) else { return false }
  let to_v = self.handle(to.at)
  let (tx, ty, tw, th) = to_v.laid_window_now()
  let (fx, fy, fw, fh) = from
  let dd = (fx - tx, fy - ty, fw - tw, fh - th)
  let far = dmax(dmax((dd.0 * dd.0 + dd.1 * dd.1).sqrt(), dd.2.abs()), dd.3.abs())
  let (ms, along) = (flight.way)(far)
  if ms <= 0.0 || far <= 0.5 {
    return false
  }
  // (one already on its way: over, this one from where it was)
  match self.flying_of(to.at) {
    Some(f) => self.flight_over(f)
    None => ()
  }
  let at = self.cause_now()
  let top = self.top_node_of(to.at)
  let f : Flying = { node: to, ghost: None, fades: false, start: at, dur: ms, along, top, stop: fn() {  } }
  self.flights.push(f)
  self.nodes[to.at].lift = Some({ follow: to.at, top, d: dd, k: 1.0, a: 1.0, from: look, stays }) 
  self.lifted_order()
  let stop_way = self.queued(fn() { self.drawn_said() }, fn(t) { self.flight_at(f, t) })
  let stop_end = to_v.at_moment(at + ms, fn() { self.flight_over(f) })
  let unkeep = to_v.owns_while(fn() { self.flight_over(f) })
  f.stop = fn() {
    stop_way()
    stop_end()
    unkeep()
  }
  true
}

///|
/// Flight `f` drawn as of moment `t`: how much of its way is left and how far each is faded, both marked to be drawn so.
fn Tree::flight_at(self : Tree, f : Flying, t : Double) -> Unit {
  let ms = t - f.start
  let p = if ms <= 0.0 {
    0.0
  } else if ms >= f.dur {
    1.0
  } else {
    (f.along)(ms)
  }
  let k = 1.0 - p
  // (the new one in over the first half of the way, the old one under it out over the second: never both half seen)
  let a_in = dmin(1.0, dmax(0.0, p * 2.0))
  let a_out = dmin(1.0, dmax(0.0, (1.0 - p) * 2.0))
  if self.alive_id(f.node) {
    match self.nodes[f.node.at].lift {
      Some(l) => {
        l.k = k
        l.a = if f.fades { a_in } else { 1.0 }
        self.lift_marked(f.node.at)
      }
      None => ()
    }
  }
  match f.ghost {
    Some(g) if self.alive_id(g) =>
      match self.nodes[g.at].lift {
        Some(l) => {
          l.k = k
          l.a = a_out
          self.lift_marked(g.at)
          // (what it is drawn over the rest of drawn again with it)
          if self.alive_id(f.node) {
            self.touched(f.node.at)
          }
        }
        None => ()
      }
    _ => ()
  }
}

///|
/// Node `at` on a flight's way moved along it: drawn again (its content as big as it is drawn there), composed again.
fn Tree::lift_marked(self : Tree, at : Int) -> Unit {
  let n = self.nodes[at]
  self.look_marked_at(at)
  self.composed.push({ at, gen: n.gen })
  self.places_rev = self.places_rev + 1
  self.hits_bump()
}

///|
/// Flight `f` over (come to its end, set off again, or its new one let go of): the new one drawn where it is laid out
/// again, in its place, its old copy let go of.
fn Tree::flight_over(self : Tree, f : Flying) -> Unit {
  guard self.flights.search_by(fn(o) { physical_equal(o, f) }) is Some(i) else { return }
  self.flights.remove(i) |> ignore
  let stop = f.stop
  f.stop = fn() {  }
  stop()
  if self.alive_id(f.node) {
    self.nodes[f.node.at].lift = None
    self.places_rev = self.places_rev + 1
    self.look_marked_at(f.node.at)
    self.place_marked_at(f.node.at)
  }
  match f.ghost {
    Some(g) => {
      f.ghost = None
      if self.alive_id(g) {
        self.handle(g.at).let_go()
      }
    }
    None => ()
  }
  self.lifted_order()
}

///|
/// The flight node `at` is the new one of, if it is.
fn Tree::flying_of(self : Tree, at : Int) -> Flying? {
  self.flights.iter().find_first(fn(f) { f.node.at == at && self.alive_id(f.node) })
}

///|
/// What is drawn on a flight's way, come or gone: the order made again whole (what flies drawn over the rest of its
/// layer, Tree::ordered), what is found where it is drawn with it.
fn Tree::lifted_order(self : Tree) -> Unit {
  self.order_whole = true
  self.order_due = true
  self.hits_bump()
  self.draws_rev = self.draws_rev + 1
  self.draws_any_rev = self.draws_any_rev + 1
  self.marked()
}

///|
/// What flies over the rest of layer `top` (the node of the root's at `me` in the order), in the order: each flight's old
/// copy, then its new one over it.
fn Tree::ordered_lifted(self : Tree, top : Int, me : Int) -> Unit {
  for f in self.flights {
    if f.top != top {
      continue
    }
    match f.ghost {
      Some(g) if self.alive_id(g) => {
        self.lifting = true
        self.ordered(g.at, me, top)
      }
      _ => ()
    }
    if self.alive_id(f.node) && f.node.at != top {
      match self.nodes[f.node.at].lift {
        Some(l) if !self.lifted_over(self.nodes[f.node.at], l) => ()
        _ => {
          self.lifting = true
          self.ordered(f.node.at, me, top)
        }
      }
    }
  }
  self.lifting = false
}

///|
/// Whether node `n`, on flight `l`'s way, is drawn over the rest of its layer: all are but the one that moves of a
/// flight with an end that stays (the picture opened over everything from its thumbnail, and back), drawn where it is
/// held, what is drawn after it in its layer (its viewer's bar) over it, where the flight has it.
fn Tree::lifted_over(self : Tree, n : Node, l : Lift) -> Bool {
  ignore(self)
  !(l.stays is Some(_) && !n.share_stays)
}

///|
/// Node `at` let go of: a flight it is the new one of over (its old copy let go of), its id no more counted.
fn Tree::share_let_go(self : Tree, at : Int) -> Unit {
  let n = self.nodes[at]
  match n.share {
    Some(id) => {
      self.share_counted(at, id, -1)
      n.share = None
    }
    None => ()
  }
  n.share_stays = false
  n.share_with_stays = false
  n.share_flight = None
  if n.lift is Some(_) {
    match self.flying_of(at) {
      Some(f) => self.flight_over(f)
      None => ()
    }
    n.lift = None
    self.places_rev = self.places_rev + 1
  }
}

///|
/// The pictures asked for (View::image_ask) since this was last done, asked of what hosts the tree now, each where the
/// node that asked still stands in the window's tree, each once: one made and let go of before now (in a change told
/// in parts, or in one pass of a layout and gone in a later, a page's list's block) has nothing asked. Done as a change
/// ends, the outermost (Tree::change_ended), and as a frame's layout ends outside every change (Tree::brought).
fn Tree::images_asked_now(self : Tree) -> Unit {
  if self.images_wanted.is_empty() {
    return
  }
  let wanted = self.images_wanted.copy()
  self.images_wanted.clear()
  let asked : Array[(String, Double)] = []
  for w in wanted {
    let (id, src, px) = w
    if self.alive_id(id) && self.attached(id.at) && !asked.contains((src, px)) {
      asked.push((src, px))
      (self.env.image_ask)(src, px)
    }
  }
}

///|
/// A change of the tree ended (an event told, a moment come on the timeline, a change at its cause, a structure's, a
/// binding's run at the moment it was told; one told outside every event, as where things stand is settled after it:
/// Tree::settle_now): the pictures asked for in it (View::image_ask) asked now, where it was the outermost and no layout
/// is under way (a frame's ends in Tree::brought, which asks for what its passes left standing).
/// Nothing asked for, nothing done but this test.
fn Tree::change_ended(self : Tree) -> Unit {
  if self.images_wanted.is_empty() || self.in_change() || self.laying || self.draining > 0 {
    return
  }
  self.images_asked_now()
}
