// Where a node is drawn as of an event's moment (View::drawn_now): what an event's handler reads once to say what is to
// move from there (a picture opened from its thumbnail, closed back to it), never followed.

///|
/// Where a node is drawn in the window and how (View::drawn_now): its box as drawn (its offsets, drawn or not, and its
/// scale and its holders' with it), what of it its holders' cuts leave seen, its corners as drawn (each, scaled; None:
/// as square as its box), how much it and its holders are grown, and how opaque they make it.
pub(all) struct DrawnNow {
  rect : (Double, Double, Double, Double)
  seen : (Double, Double, Double, Double)
  corners : (Double, Double, Double, Double)?
  scale : Double
  alpha : Double
} derive(Eq, Debug)

///|
/// Where it is drawn as of the logic's moment (Tree::logic_at: an event's, a due thing's), read once by what moves from
/// there for that cause, never followed (what is drawn each frame is read as it is painted: Laid).
///
/// - What it reads: every change of what is bound (a node's properties, what a binding reads) made before it is asked,
///   the same event's before it included (a room changed, then this read, in one handler), laid out and placed as a
///   frame would at that moment (Painted looks worked out from that layout), nothing drawn. What is made, let go or
///   reordered (View::show, pick, each) is the event's change committed as the event's handler ends, not before: what
///   reads where things are after such a change of its own event reads in View::after_event (committed whole, at the
///   same moment). A change made after it is asked is not in what it said: ask again.
/// - Asked as a node is being built (a View::show's or pick's `then`), it lays out a tree half made: ask it in the
///   event that made it, or in View::after_event, never in a build.
/// - Whether a frame was drawn between the change and the ask changes nothing: it is the same state at the same moment.
/// - The clock is set to that moment for the layout and set back to where it was drawn at; what moves by the time is
///   where it is at that moment, nothing advanced by it, nothing due then done by it (what is due is done as its moment
///   comes, Tree::advance_loop). No input is taken by it: what that layout tells (what is under the pointer) is told as
///   a frame's layout tells it.
/// - The window as big as the host's last frame gave it (Tree::frame): a size the host reports between frames is the
///   window's as its frame comes, so an event before that frame is laid out at the size before it.
/// - None: it is let go (a handle never stands for another made in its place), laid out nowhere (View::shown_nowhere),
///   the window not sized yet (no layout is the window's), or asked inside such a layout already (a layout's own
///   callback, a settle under way): the caller does without it (a picture closed fading where it is), never takes an old
///   place for this moment's.
/// - What it costs: a layout of that moment where one is due then, owed (counted as a settle, Tree::work), as many as
///   changes are asked of between the asks; none where nothing changed.
pub fn View::drawn_now(self : View) -> DrawnNow? {
  guard self.alive() else { return None }
  let tree = self.tree
  guard tree.layout_owner < 0 && tree.laying == 0 else { return None }
  // (looked at as of the logic's moment, read there, and laid out as drawn again: what reads the drawing's moment or what
  // a layout tells for its own sake (a structure's binding, a reaction, an effect, what waits for a change told whole)
  // told nothing of the look, Tree::settled_at)
  let found : Ref[DrawnNow?] = Ref(None)
  let read = fn() {
    guard self.alive() && !tree.out_at(self.at) else { return }
    guard tree.drawn_of(self.id()) is Some(d) else { return }
    let scale = tree.drawn_scale(self.id())
    let b = tree.seen_bounds(self.id(), drawing=true)
    let (left, top) = (dmax(d.x, b.0), dmax(d.y, b.1))
    let (right, foot) = (dmin(d.x + d.w, b.2), dmin(d.y + d.h, b.3))
    found.val = Some({
      rect: (d.x, d.y, d.w, d.h),
      seen: (left, top, dmax(0.0, right - left), dmax(0.0, foot - top)),
      corners: d.corners.map(fn(c) { (c.0 * scale, c.1 * scale, c.2 * scale, c.3 * scale) }),
      scale,
      alpha: d.alpha,
    })
  }
  guard @signals.effects_held(fn() { tree.settled_at(tree.logic_at(), look=read) }) else { return None }
  found.val
}

///|
/// `f` done once the event being taken now is committed whole (what its handler made, let go or reordered made so, each
/// a change of its own of that moment, in order), at that event's moment, before anything else is taken or drawn; taken
/// in no event, now. Not done once it is let go. For what reads where things are once the event's own changes are in
/// (View::drawn_now): a picture closed back to its thumbnail after the handler that closed it moved the list.
pub fn View::after_event(self : View, f : () -> Unit) -> Unit {
  guard self.alive() else { return }
  let id = self.id()
  let tree = self.tree
  tree.after_event(fn() { if tree.alive_id(id) { f() } })
}
