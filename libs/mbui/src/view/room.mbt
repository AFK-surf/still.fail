// What is made by the room it is given (View::by_room), Flutter's LayoutBuilder: as the layout comes to a node, what
// holds it has given it its width; what it holds is made and said by that width there, and laid out in the same layout,
// after it. The room goes one way, down: nothing made in it changes the room it is given or anything outside it (what
// it would change there is a fault, told at once), and what it comes to is laid out by what holds it as any box's is.
// Nothing laid out is told afterwards as a change to make things by: no size read back once all is laid out, no layout
// done again for it.

///|
/// The room a node made by it is given (View::by_room): how wide, as the layout comes to it, and how tall what is
/// measured in it comes to at that width (Room::tall). Read by what is made in it alone.
pub struct Room {
  priv tree : Tree
  /// the node it is the room of (View::by_room's own)
  priv at : Int
  priv wide : @signals.Signal[Double]
  /// what is measured in it, each with how tall it comes to (Room::tall)
  priv measured : Array[(View, @signals.Signal[Double])]
}

///|
/// A box whose content `make` makes in `held` by the room it is given (`room`): how wide that is (Room::width) is
/// told as the layout comes to it, what `make` made reading it (what shows, which rows, how wide each is, what it draws)
/// made and said again by it there and laid out in that same layout, nothing laid out again afterwards. `make` is done
/// once, as it is first laid out (its width known then). Its width is what holds it gives it (stretched across a
/// column, its share of a row), never what it holds: `held` is as wide as its room, as tall as what it holds. What is
/// made in it never says its own box by its room (a fault where it does); what reads it outside it (none should) is
/// laid out after, as a change of its own. Where it is given
/// another room in the same layout (measured in a row before its share is known), made by each in turn, laid out by
/// the last.
#callsite(autofill(loc))
pub fn View::by_room(self : View, make : (View, Room) -> Unit, loc~ : SourceLoc) -> View {
  self.box(loc~, fn(x) {
    guard x.live() is Some(n) else { return }
    let tree = x.tree
    let room : Room = {
      tree,
      at: x.at,
      wide: @signals.signal(0.0, same=fn(a, b) { a == b }),
      measured: [],
    }
    let made = Ref(false)
    let held = x.box(loc~, fn(_) {  })
    n.flex.room = true
    n.flex.measure = Some(fn(w, wm, _h, _hm) {
      if wm is Undefined || !held.alive() {
        return (0.0, 0.0)
      }
      let changed = tree.in_room(x.at, fn() {
        if !made.val {
          made.val = true
          room.wide.set(w)
          held.owning(fn() { make(held, room) })
        } else {
          room.wide.set(w)
        }
        tree.room_bindings_run()
        room.measure(w)
      })
      (if changed { 1.0 } else { 0.0 }, 0.0)
    })
  })
}

///|
/// How wide what is made in it is given to be (the content box of View::by_room's node, as the layout comes to it),
/// followed: what reads it made and said again as it comes out otherwise, in that same layout.
pub fn Room::width(self : Room) -> Double {
  self.wide.get()
}

///|
/// How tall `v` (made in it, stretched across what holds it there) comes to laid out whole at the room's width (less
/// the margins and padding on its way to it: Room::height_at), followed: told in the same layout, before what holds it is laid out, as the width is; what
/// reads it is never in `v` (a fault where what it makes changes how tall `v` comes to). 0 till it is first laid out.
pub fn Room::tall(self : Room, v : View) -> Double {
  for m in self.measured {
    if m.0.at == v.at && m.0.gen == v.gen {
      return m.1.get()
    }
  }
  let cell = @signals.signal(0.0, same=fn(a, b) { a == b })
  self.measured.push((v, cell))
  // (first asked as it is made in the layout: measured there; else as it is next laid out)
  if self.tree.rooming == self.at {
    self.measure_one(v, cell, self.wide.untracked())
    return cell.get()
  }
  self.tree.layout_marked_at(self.at)
  cell.get()
}

///|
/// What is measured in it, each measured at width `w` and told, what reads it made and said by that; then measured
/// again, each the same (what reads how tall it is changes nothing in it). Those let go forgotten.
fn Room::measure(self : Room, w : Double) -> Unit {
  let live = self.measured.filter(fn(m) { m.0.alive() })
  self.measured.clear()
  self.measured.append(live)
  let mut i = 0
  // (one asked as those read are made is measured as it is asked: those after it too)
  while i < self.measured.length() {
    let (v, cell) = self.measured[i]
    self.measure_one(v, cell, w)
    self.tree.room_bindings_run()
    i = i + 1
  }
  for m in self.measured {
    let (v, cell) = m
    if v.alive() {
      let h = self.height_at(v, w)
      if h != cell.untracked() {
        @halt.saying(
          "Room::tall: what reads how tall a node made by its room comes to changed that (\{h} for \{cell.untracked()}): say it outside what is measured",
        )
      }
    }
  }
}

///|
fn Room::measure_one(self : Room, v : View, cell : @signals.Signal[Double], w : Double) -> Unit {
  guard v.alive() else { return }
  cell.set(self.height_at(v, w))
}

///|
/// How tall `v` comes to at room `w` (Tree::height_in, from the room's own).
fn Room::height_at(self : Room, v : View, w : Double) -> Double {
  self.tree.height_in(v.at, self.at, w)
}

///|
/// How tall node `at` comes to laid out whole where node `top`, holding it, gives what it holds `w` across: as wide as
/// that less what is across it on its way there (its margins, and each holding it under `top`: their margins and
/// padding), as each is stretched across what holds it. Measured, as it stands (@flex.measured_height).
fn Tree::height_in(self : Tree, at : Int, top : Int, w : Double) -> Double {
  let pt = fn(k : Int, x : Double) { if k == @flex.LEN_PT { x } else { 0.0 } }
  let mut across = 0.0
  let mut i = at
  while i >= 0 && i != top {
    let s = self.nodes[i].flex.style
    across = across +
      pt(s.margin_left_kind(), s.margin_left_value()) +
      pt(s.margin_right_kind(), s.margin_right_value())
    if i != at {
      across = across +
        pt(s.padding_left_kind(), s.padding_left_value()) +
        pt(s.padding_right_kind(), s.padding_right_value())
    }
    i = self.nodes[i].parent
  }
  @flex.measured_height(self.nodes[at].flex, dmax(0.0, w - across))
}

///|
/// `f` done as node `at`'s room is told (View::by_room), in its layout: what it marks laid out again marked in it alone
/// (its own and what is outside it a fault), nothing laid out or settled meanwhile, of the logic's moment, nothing due
/// on the timeline done in it (what it makes said due now done in its turn as the layout is done, each a change of its
/// own: Tree::advance). Whether it marked anything.
fn Tree::in_room(self : Tree, at : Int, f : () -> Unit) -> Bool {
  let was_room = self.rooming
  let was_marks = self.room_marks
  let was_standing = self.standing
  let was_cause = self.cause_at
  let was_advancing = self.advancing
  self.rooming = at
  self.room_marks = 0
  self.standing = true
  self.advancing = true
  self.committing += 1
  self.cause_at = self.logic
  @signals.untracked(f)
  self.boxes_flushed()
  let marked = self.room_marks > 0
  self.committing -= 1
  self.cause_at = was_cause
  self.advancing = was_advancing
  self.standing = was_standing
  self.room_marks = was_marks
  self.rooming = was_room
  // (what is bound outside it, told meanwhile, worked out once all of it is laid out, in this same pass; what was
  // marked outside it marked then)
  if self.rooming < 0 && (!self.bindings_due.is_empty() || !self.room_spill.is_empty()) {
    let spill = self.room_spill.copy()
    self.room_spill.clear()
    self.once_laid_out(fn() {
      for at in spill {
        if at < self.nodes.length() && self.nodes[at].live {
          self.layout_marked_at(at)
        }
      }
    })
  }
  // (what takes input changed by what it made, told once all of it is laid out, not in the middle of that layout)
  if self.committing == 0 && self.modals_due {
    self.once_laid_out(fn() { self.modals_settled() })
  }
  marked
}

///|
/// The bindings told by what a room told, of nodes in it, worked out now, in its layout (Tree::in_room); the rest (of
/// nodes outside it, told meanwhile by what else changed) left for once all of it is laid out, as they would be. Where
/// what runs the queue (Tree::laid_out, Tree::measured_now) is in the middle of it, this layout come of a binding it
/// ran, the queue is left as it stands, those run in it no more queued, for it to go on through from where it was.
fn Tree::room_bindings_run(self : Tree) -> Unit {
  let rest : Array[Bound] = []
  let mut i = 0
  while i < self.bindings_due.length() {
    let b = self.bindings_due[i]
    i = i + 1
    if !b.queued {
      continue
    }
    if b.at >= 0 && self.under_node(b.at, self.rooming) {
      (b.run)()
    } else {
      rest.push(b)
    }
  }
  if self.draining == 0 {
    self.bindings_due.clear()
    self.bindings_due.append(rest)
  }
  self.boxes_flushed()
}

///|
/// Whether node `at` is node `top` or held by it.
fn Tree::under_node(self : Tree, at : Int, top : Int) -> Bool {
  let mut i = at
  while i >= 0 {
    if i == top {
      return true
    }
    i = self.nodes[i].parent
  }
  false
}

///|
/// Node `at` to be laid out again as a room it is in is told (Tree::in_room): it and what holds it up to the room's
/// node, which is being laid out, marked so (what that layout measured of them before forgotten), nothing else. The
/// room's own node is a fault (boundary.mbt): what it said of its own box is not laid out by it.
fn Tree::room_marked_at(self : Tree, at : Int) -> Unit {
  if at == self.rooming {
    self.fault(
      { at, gen: self.nodes[at].gen },
      "View::by_room: its own box said by the room it is given, as it is laid out by it: say it of what it holds",
    )
    return
  }
  if self.under_node(at, self.rooming) {
    let mut i = at
    while i != self.rooming {
      let n = self.nodes[i]
      n.flex.dirty = true
      n.flex.cache_gen = -1
      i = n.parent
    }
    self.room_marks = self.room_marks + 1
    return
  }
  // (outside it: what reads what it told and is not in it (a layer over it reading how far it scrolls), marked once all
  // of it is laid out, a change of its own then)
  self.room_spill.push(at)
}
