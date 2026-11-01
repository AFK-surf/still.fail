// The keyboard's focus on a node of the window's tree: what can take it (View::focusable), in the tree's order with what
// hosts an old view at its place (Tree::focus_order: ui splices each old view's own there, as it does what is read out),
// which has it and whether it shows (Tree::focus_to; View::focused, View::focus_shown, each node's own cells told only
// as it comes or goes). It is let go of at the cause that keeps its node from input: the node let go, leaving, said to
// take no press, under a modal layer that does not hold it; what hosts the tree is told so then (Tree::on_focus_lost).

///|
/// Enter and Space, as what presses a node that has the focus (View::focusable's `keys`).
pub let focus_enter : Int = 1

///|
pub let focus_space : Int = 2

///|
/// A node of the window's tree as Tab goes among them (Tree::focus_order): which, whether it hosts an old view (whose
/// own go at its place), which keys press it as it has the focus (focus_enter, focus_space).
pub(all) struct FocusAt {
  id : NodeId
  hosted : Bool
  keys : Int
} derive(Eq, Debug)

///|
/// It can take the keyboard's focus while `on` holds (Tab goes to it in the tree's order), pressed as it has it by
/// `keys` (focus_enter, focus_space: its on_press, as a press on it runs it). Not on, the focus on it let go of then;
/// what it holds takes it or not by its own saying (what holds a node said to take no press, View::presses, keeps it
/// from it). `tab`: whether Tab stops on it (false: it takes the focus as it is given it, a layer's own ground as it
/// opens, Tab passing it by).
pub fn View::focusable(self : View, on : Live[Bool], keys? : Int = focus_enter | focus_space, tab? : Bool = true) -> View {
  // (whether it takes the focus is the logic's, as whether it takes presses is (View::presses): said at the moment it
  // changes, as the change saying it is committed, the focus on it let go of then; said anew, what was said before let
  // go of)
  guard self.live() is Some(n) else { return self }
  match n.props.get(Focusable) {
    Some(stop) => {
      n.props.remove(Focusable)
      stop()
    }
    None => ()
  }
  // (`tell`: said by this call, not as what a binding read changed (Tree::structured marks the tree for that):
  // what is read out of it told by the frame then owed, where it changed)
  let set = fn(on : Bool, tell : Bool) {
    guard self.live() is Some(n) else { return }
    let was = (n.focusable, n.focus_keys, n.focus_tab)
    n.focusable = on
    n.focus_keys = keys
    n.focus_tab = tab
    if tell && was != (on, keys, tab) {
      self.tree.marked()
    }
    // (its own focus let go of, not what it holds: whether they take it is their own, View::presses what holds them
    // all; what is read out of it told as the change is committed, a frame owed for it: Tree::structured)
    if !on && self.tree.focused == Some(self.id()) {
      self.tree.focus_lost_in(self.at)
    }
  }
  match on {
    Is(v) => set(v, true)
    By(f) =>
      self.owning(fn() {
        // (its first reading, done as it is said, by this call; each after it, as what it read changed)
        let first = Ref(true)
        let stop = self.tree.structured(f, fn(v) {
          self.owning(fn() { set(v, first.val) })
          first.val = false
        })
        n.props[Focusable] = stop
      })
  }
  self
}

///|
/// Whether it has the keyboard's focus: what reads it told only as the focus comes to it or leaves it. Its cell made as
/// first read, let go with it.
pub fn View::focused(self : View) -> Bool {
  guard self.live() is Some(n) else { return false }
  let s = match n.focused_cell {
    Some(s) => s
    None => {
      let s = @signals.signal(self.tree.focused == Some(self.id()), same=fn(a, b) { a == b })
      n.focused_cell = Some(s)
      s
    }
  }
  s.get()
}

///|
/// Whether it has the focus and it shows (it came by the keyboard: where a focus ring is drawn, as a browser's
/// :focus-visible). Its cell made as first read, let go with it.
pub fn View::focus_shown(self : View) -> Bool {
  guard self.live() is Some(n) else { return false }
  let s = match n.focus_shown_cell {
    Some(s) => s
    None => {
      let s = @signals.signal(self.tree.focused == Some(self.id()) && self.tree.focus_visible, same=fn(a, b) {
        a == b
      })
      n.focus_shown_cell = Some(s)
      s
    }
  }
  s.get()
}

///|
/// What can take the focus now, and what hosts an old view (whose own take it at its place), in the tree's order (each
/// before what it holds, what it holds in its order): those that take input now (a modal layer over them says not:
/// Tree::allows) and take presses (not leaving, not said to take none).
pub fn Tree::focus_order(self : Tree) -> Array[FocusAt] {
  let out : Array[FocusAt] = []
  fn walk(at : Int) -> Unit {
    let n = self.nodes[at]
    if !n.live {
      return
    }
    if (n.hosted || (n.focusable && n.focus_tab)) && !self.pressless_at(at) {
      out.push({ id: { at, gen: n.gen }, hosted: n.hosted, keys: n.focus_keys })
    }
    for k in self.kids_in_order(at) {
      walk(k)
    }
  }

  if self.nodes.length() > 0 {
    walk(0)
  }
  out
}

///|
/// The focus to node `id` (none: to none of the tree's), shown where `visible` (moved by the keyboard): where it can
/// take it now (living, focusable, taking presses, under no modal layer that does not hold it). What it can take is
/// what the changes committed so far said (whether it takes the focus, or presses, or a modal layer is over it: each
/// said as the change saying it is committed, View::focusable, View::presses), whatever frame comes: in an event, what
/// that event set and has not committed yet is not seen. The one that had it and the one that has it told, nothing
/// else. Whether `id` has it now.
pub fn Tree::focus_to(self : Tree, id : NodeId?, visible? : Bool = false) -> Bool {
  let ok = match id {
    Some(i) =>
      self.can_focus(i)
    None => true
  }
  if !ok {
    return false
  }
  self.focus_set(id, visible && id is Some(_))
  true
}

///|
/// The node with the focus now (Tree::focus_to), and whether it shows.
pub fn Tree::focused_now(self : Tree) -> (NodeId?, Bool) {
  (self.focused, self.focus_visible)
}

///|
/// The keys that press node `id` as it has the focus (View::focusable; 0: it takes none, or it is gone).
pub fn Tree::focus_keys_of(self : Tree, id : NodeId) -> Int {
  if self.alive_id(id) {
    self.nodes[id.at].focus_keys
  } else {
    0
  }
}

///|
/// The focus let go of where the node with it is `at` or in it (0: wherever it is, as a modal layer over it says it
/// takes no input), at the moment of what did it: what had it told, and what hosts the tree (Tree::on_focus_lost).
fn Tree::focus_lost_in(self : Tree, at : Int) -> Unit {
  guard self.focused is Some(f) else { return }
  let mut i = f.at
  let mut under = false
  while i >= 0 && i < self.nodes.length() {
    if i == at {
      under = true
      break
    }
    i = self.nodes[i].parent
  }
  if !under {
    return
  }
  self.focus_set(None, false)
  (self.on_focus_lost)(f)
}

///|
/// What hosts the tree told as the focus on one of its nodes is let go of at a cause (the node let go, leaving, said to
/// take no press or no focus, a modal layer over it): which it was.
pub fn Tree::on_focus_lost(self : Tree, f : (NodeId) -> Unit) -> Unit {
  self.on_focus_lost = f
}

///|
fn Tree::focus_set(self : Tree, id : NodeId?, visible : Bool) -> Unit {
  let was = self.focused
  let shown_was = self.focus_visible
  self.focused = id
  self.focus_visible = visible
  // (told as one change: what reads both never sees one half of it)
  @signals.start_batch()
  if was != id {
    self.hand_told(was, fn(n) { n.focused_cell }, false)
    self.hand_told(id, fn(n) { n.focused_cell }, true)
  }
  if was != id || shown_was != visible {
    self.hand_told(was, fn(n) { n.focus_shown_cell }, false)
    self.hand_told(id, fn(n) { n.focus_shown_cell }, visible)
  }
  @signals.end_batch()
}

///|
/// Whether node `id` can take the focus now (View::focusable, taking presses, under no modal layer that does not hold
/// it): what a screen reader may give it.
pub fn Tree::can_focus(self : Tree, id : NodeId) -> Bool {
  self.alive_id(id) && self.nodes[id.at].focusable && !self.pressless_at(id.at)
}

///|
/// The node with the focus pressed as a key that presses it does (Enter, Space: View::focusable's `keys`), as one event
/// at `at`: where it still has the focus then, can take it and takes presses, its on_press, as a press on it runs it.
/// Whether it was pressed.
pub fn Tree::press_focused_at(self : Tree, id : NodeId, at : Double) -> Bool {
  let pressed = Ref(false)
  self.event(at, fn() {
    // (what it says as of then: its bindings marked worked out first, Tree::pull)
    self.pull()
    if self.focused != Some(id) || !self.can_focus(id) || !self.takes_presses(id) {
      return
    }
    match self.nodes[id.at].on_press {
      Some(f) => {
        pressed.val = true
        f()
      }
      None => ()
    }
  })
  pressed.val
}

///|
/// Whether a screen reader may give node `id` the focus now (its Focus action), as the tree is now (its bindings marked
/// worked out first): read out (it says what it is, nothing hides it, no modal layer it is not in over it:
/// Tree::reads_out) and able to take the focus (Tree::can_focus).
pub fn Tree::focus_asked_takes(self : Tree, id : NodeId) -> Bool {
  self.reads_out(id) && self.said_now(id.at) && self.can_focus(id)
}

///|
/// Whether it takes input now (a press, a key, the focus): living, neither it nor what holds it leaving or said to take
/// no press, under no modal layer that does not hold it. What reads it told as that changes, at the cause that changes
/// it, once that is committed whole, whatever frames come. Its cell made as first read, let go with it.
pub fn View::takes_input(self : View) -> Bool {
  guard self.live() is Some(n) else { return false }
  let s = match n.input_cell {
    Some(s) => s
    None => {
      let s = @signals.signal(!self.tree.pressless_at(self.at), same=fn(a, b) { a == b })
      n.input_cell = Some(s)
      if !self.tree.inputs_at.contains(self.at) {
        self.tree.inputs_at.push(self.at)
      }
      s
    }
  }
  s.get()
}

///|
/// Each node whose taking input is read told it as it is now (View::takes_input): as what decides it changes (a modal
/// layer, a node leaving, said to take no press), once the change is committed whole. Those let go dropped.
fn Tree::inputs_told(self : Tree) -> Unit {
  let live = self.inputs_at.filter(fn(at) { self.nodes[at].live && self.nodes[at].input_cell is Some(_) })
  self.inputs_at.clear()
  self.inputs_at.append(live)
  for at in self.inputs_at {
    match self.nodes[at].input_cell {
      Some(s) => s.set(!self.pressless_at(at))
      None => ()
    }
  }
}

///|
/// A layer (a node over others, modal or not) that gives the keyboard's focus to `to`, a node it holds, as it opens,
/// and gives it back to what had it then as it goes (leaving, or let go), where the focus is in it or nowhere then, as
/// the old frame's layers do (Ctx::overlay's initial_focus and return_focus). Both done once the change that opened or
/// closed it is committed whole, as what a modal layer says is (Tree::modals_now): the layers opened in one change
/// each in turn from the lowest, as they are drawn, the focus on the topmost's `to`, each giving it back to what the
/// one under it gave it to (Tree::on_layers_focus).
pub fn View::focus_opens(self : View, to : View) -> View {
  guard self.live() is Some(_) else { return self }
  let layer = self.id()
  let tree = self.tree
  let target = to.id()
  // (gone: told once as it goes; come back as it leaves (the same node, shown again), opened again)
  let gone = Ref(false)
  let went = fn() {
    if !gone.val {
      gone.val = true
      tree.focus_gone.push(layer)
      tree.modals_told()
    }
  }
  tree.focus_opened.push((layer, target))
  tree.modals_told()
  self.reacts(fn() { self.leaving() }, fn(leaving) {
    if leaving {
      went()
    } else if gone.val {
      gone.val = false
      tree.focus_opened.push((layer, target))
      tree.modals_told()
    }
  })
  self.owns(went) |> ignore
  self
}

///|
/// What hosts the tree told, as a change is committed whole, of the layers that give the focus (View::focus_opens):
/// those gone since (`gone`: the focus given back from each, where it is in it or nowhere), then those opened, the
/// lowest first as they are drawn, each with the node it gives the focus to (`opened`: the focus to the topmost's,
/// where it can take it; each giving it back to what had it before it, the one under it's).
pub fn Tree::on_layers_focus(self : Tree, f : (Array[NodeId], Array[(NodeId, NodeId)]) -> Unit) -> Unit {
  self.on_layers_focus = f
}

///|
/// The layers that give the focus opened and gone since last told, told what hosts the tree (Tree::on_layers_focus):
/// those opened that still are and are not leaving, as they are drawn, the lowest first.
fn Tree::layers_focus_told(self : Tree) -> Unit {
  if self.focus_opened.is_empty() && self.focus_gone.is_empty() {
    return
  }
  let gone : Array[NodeId] = []
  for l in self.focus_gone {
    if !gone.contains(l) {
      gone.push(l)
    }
  }
  self.focus_gone.clear()
  // (those open as the change leaves them: not let go, not leaving; one gone and come back in it, open)
  let opened : Array[(NodeId, NodeId)] = []
  for o in self.focus_opened {
    if self.alive_id(o.0) && !self.leaving_at(o.0.at) && !opened.iter().any(fn(p) { p.0 == o.0 }) {
      opened.push(o)
    }
  }
  self.focus_opened.clear()
  let by : Array[((NodeId, NodeId), Array[Int])] = []
  for o in opened {
    match self.layer_path(o.0.at) {
      Some(p) => {
        let mut j = by.length()
        while j > 0 && drawn_after(by[j - 1].1, p) {
          j = j - 1
        }
        by.insert(j, (o, p))
      }
      None => ()
    }
  }
  (self.on_layers_focus)(gone, by.map(fn(e) { e.0 }))
}
