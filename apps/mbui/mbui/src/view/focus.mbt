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
/// opens, Tab passing it by). `typing`: an editor whose existing focus a modal layer may leave in place for text
/// input alone (View::leaves_typing); this does not give it the layer's keys or presses. Omitted, whether it is an
/// editor stays as it was: changing an editor's enabled state does not change what takes its text.
pub fn View::focusable(self : View, on : Live[Bool], keys? : Int = focus_enter | focus_space, tab? : Bool = true, typing? : Bool) -> View {
  // (whether it takes the focus is the logic's, as whether it takes presses is (View::presses): said at the moment it
  // changes, as the change saying it is committed, the focus on it let go of then; said anew, what was said before let
  // go of)
  guard self.live() is Some(n) else { return self }
  let typing = typing.unwrap_or(n.focus_typing)
  match n.props.get(Focusable) {
    Some(stop) => {
      n.props.remove(Focusable)
      stop()
    }
    None => ()
  }
  // (its `tab` the last said of Tab's stop on it: View::tab_stop said before let go of)
  match n.props.get(TabStop) {
    Some(stop) => {
      n.props.remove(TabStop)
      stop()
    }
    None => ()
  }
  n.tab_by_stop = false
  // (`tell`: said by this call, not as what a binding read changed (Tree::structured marks the tree for that):
  // what is read out of it told by the frame then owed, where it changed)
  let set = fn(on : Bool, tell : Bool) {
    guard self.live() is Some(n) else { return }
    let was = (n.focusable, n.focus_keys, n.focus_tab, n.focus_typing)
    n.focusable = on
    n.focus_typing = typing
    n.focus_keys = keys
    // (Tab's stop on it View::tab_stop's where that was said after this: not undone as whether it takes the focus
    // changes)
    if !n.tab_by_stop {
      n.focus_tab = tab
    }
    if tell && was != (on, keys, tab, typing) {
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
    Painted(_) => not_painted("what is said here")
    Roomed(_, _) => not_roomed()
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
      self.can_focus(i) || (self.focused == Some(i) && self.typing_kept(i))
    None => true
  }
  if !ok {
    return false
  }
  // (an explicit request for none is still a new decision when the focus was already let go of: an old hosted view
  // may have taken it, or the hand may have left it with nothing; a return captured before that cannot take it back)
  if id is None {
    self.focus_epoch += 1L
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
/// A chance to return one control's focus to its replacement. It belongs to its original tree and expires as soon as
/// any later focus request succeeds, even if that request gives the focus to nothing or to a hosted old view.
pub struct FocusReturn {
  tree : Tree
  source : NodeId
  epoch : Int64
  visible : Bool
}

///|
/// Capture the focus on this node for a structural replacement. Nothing is captured if it does not have focus or was
/// outside the window or a clip in the last layout. That layout's window is used even if a resize has already arrived.
/// Losing the node itself does not expire the return; any later focus request does. A replacement may use
/// FocusReturn::give once the new node is made.
pub fn View::focus_return(self : View) -> FocusReturn? {
  guard self.live() is Some(_) && self.tree.focused == Some(self.id()) && self.focus_in_sight() else { return None }
  Some({ tree: self.tree, source: self.id(), epoch: self.tree.focus_epoch, visible: self.tree.focus_visible })
}

///|
/// Whether this chance is still current. While its original node has focus, it must still be visible; after that node
/// is removed it remains current until a later focus decision. This can be read while a replacement is not yet made.
pub fn FocusReturn::valid(self : FocusReturn) -> Bool {
  guard self.tree.focus_epoch == self.epoch else { return false }
  match self.tree.focused {
    None => true
    Some(id) if id == self.source =>
      match self.tree.view_of(id) {
        Some(node) => node.focus_in_sight()
        None => false
      }
    Some(_) => false
  }
}

///|
/// Return the captured focus to `node`, if it belongs to the same tree, the captured request is still current and no
/// node has taken focus. Once laid out, the node must still be in sight and able to take input. A successful return
/// consumes this chance; a node that cannot take it leaves the chance for another copy of that control.
pub fn FocusReturn::give(self : FocusReturn, node : View) -> Bool {
  guard physical_equal(self.tree, node.tree) && self.tree.focus_epoch == self.epoch && self.tree.focused is None &&
    node.focus_in_sight() else {
    return false
  }
  node.ask_focus(visible=self.visible)
}

///|
/// Whether any of this node remains inside the window and every clip holding it, as just laid out. A focus return
/// does not scroll to a control that disappeared from sight in its replacement.
fn View::focus_in_sight(self : View) -> Bool {
  guard self.live() is Some(_) && !self.tree.out_at(self.at) else { return false }
  let (x, y, w, h) = self.rect()
  let (rx, ry, rw, rh) = self.tree.handle(0).rect()
  let (left, top, right, bottom) = self.tree.seen_bounds(self.id())
  w > 0.0 && h > 0.0 && x + w > dmax(rx, left) && x < dmin(rx + rw, right) &&
    y + h > dmax(ry, top) && y < dmin(ry + rh, bottom)
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
fn Tree::focus_lost_in(self : Tree, at : Int, replacement? : Bool = false) -> Unit {
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
  // A node going away can be replaced by the same control. Losing input for another reason is a new decision and
  // must permanently expire a captured return, even if the control is enabled or uncovered again later.
  if !replacement {
    self.focus_epoch += 1L
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
/// What hosts the tree gives the node that asks for the focus (View::ask_focus): its own focus moved to it, `visible`
/// or not, and the tree told back of it as any move of that focus is (one focus, read on either side).
pub fn Tree::on_focus_asked(self : Tree, f : (NodeId, Bool) -> Unit) -> Unit {
  self.on_focus_asked = Some(f)
}

///|
/// The focus asked for by it (a menu's row the menu's keys or the pointer come to), shown or not as `visible`
/// says: what hosts the tree moves its own focus there (Tree::on_focus_asked), the tree told back; where nothing
/// hosts it, the tree's alone (Tree::focus_to). Whether it has it then.
pub fn View::ask_focus(self : View, visible? : Bool = false) -> Bool {
  match self.tree.on_focus_asked {
    Some(f) => {
      f(self.id(), visible)
      @signals.untracked(fn() { self.focused() })
    }
    None => self.tree.focus_to(Some(self.id()), visible~)
  }
}

///|
fn Tree::focus_set(self : Tree, id : NodeId?, visible : Bool) -> Unit {
  // (come to another: what waited for its node no longer does)
  if id is Some(_) {
    self.focus_epoch += 1L
    self.focus_parked = None
  }
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
  // (come to one: brought into sight by what holds it, once laid out: Tree::show_in_sight)
  match id {
    Some(to) if was != id => self.show_in_sight(to)
    _ => ()
  }
  @signals.end_batch()
}

///|
/// What brings a part of what it holds into its sight (Tree::show_in_sight: the focus come to it): `f` given where that
/// is in its own terms (its top, its foot; `across`, its start, its end), answering how far it moved what it holds to
/// (down, or `across` along it: a column that scrolls, a row that scrolls sideways, View::scrolls), all of it laid out,
/// before it is drawn.
pub fn View::shows(self : View, f : (Double, Double) -> Double, across? : Bool = false) -> View {
  guard self.live() is Some(n) else { return self }
  n.shows = Some(f)
  n.shows_across = across
  self
}

///|
/// Whether node `id` can take the focus now (View::focusable, taking presses, under no modal layer that does not hold
/// it): what a screen reader may give it.
pub fn Tree::can_focus(self : Tree, id : NodeId) -> Bool {
  self.alive_id(id) && self.nodes[id.at].focusable && !self.pressless_at(id.at)
}

///|
/// An editor's existing focus kept under a layer that leaves typing. An old-only layer keeps a retained editor's focus
/// without sending text to it. Its presses and keys belong to the layer; leaving or disabling it drops focus as usual.
fn Tree::typing_kept(self : Tree, id : NodeId) -> Bool {
  self.alive_id(id) && self.nodes[id.at].focusable && self.nodes[id.at].focus_typing &&
    self.typing_left_under() && !self.pressless_own_at(id.at)
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
  self.layer_focus(Some(to.id()))
}

///|
/// A layer that gives the focus, as it opens, to the first of what it holds that takes it (as Tab goes: its nodes and
/// what the old views it hosts take, as those are built), as the old frame's trapping layers do (Ctx::overlay's
/// initial_focus, by default); to its own ground while none does; given back as it goes (View::focus_opens's). Given
/// once: what the person or the app does with the focus after that its own. Its ground takes the focus (View::focusable,
/// no keys, no Tab stop: a dialog's), given it as it opens.
pub fn View::focus_opens_first(self : View) -> View {
  guard self.live() is Some(_) else { return self }
  let layer = self.id()
  let tree = self.tree
  tree.focus_firsts.add(layer)
  self.owns(fn() { tree.focus_firsts.remove(layer) }) |> ignore
  self.layer_focus(Some(layer))
}

///|
/// Whether layer `layer` gives the focus to the first of what it holds that takes it as it opens
/// (View::focus_opens_first).
pub fn Tree::opens_first(self : Tree, layer : NodeId) -> Bool {
  self.focus_firsts.contains(layer)
}

///|
/// A layer that gives back the focus as it goes (View::focus_opens's), giving it nothing as it opens: the focus left
/// where it is (a field a finger opened a menu beside: kit's dropdown_menu's initial focus none), what had it as it
/// opened, or what that one under it gives back, given it back as it goes where the focus is in it then or nowhere;
/// what opens over it in the same change gives back what had it before this one, as though this one were not there.
pub fn View::focus_returns(self : View) -> View {
  self.layer_focus(None)
}

///|
/// A layer that gives the focus back, as it goes, to `to` (what opened it: a menu's trigger, a sheet's button), not to
/// what had it as it opened (View::focus_opens), where `to` is there then and takes the focus; else to what had it. Said
/// with View::focus_opens, focus_opens_first or focus_returns, which say what it gives the focus to as it opens.
pub fn View::returns_focus_to(self : View, to : NodeId) -> View {
  guard self.live() is Some(_) else { return self }
  let layer = self.id()
  let tree = self.tree
  tree.focus_backs[layer] = to
  self.owns(fn() { tree.focus_backs.remove(layer) }) |> ignore
  self
}

///|
/// What layer `layer` gives the focus back to as it goes where it says (View::returns_focus_to); none: what had it as it
/// opened.
pub fn Tree::focus_back_of(self : Tree, layer : NodeId) -> NodeId? {
  self.focus_backs.get(layer)
}

///|
/// Layer `self` told as giving the focus to `target` as it opens (none: nothing), giving back as it goes.
fn View::layer_focus(self : View, target : NodeId?) -> View {
  guard self.live() is Some(_) else { return self }
  let layer = self.id()
  let tree = self.tree
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
/// where it can take it; each giving it back to what had it before it, the one under it's; none: View::focus_returns,
/// the focus left where it is, what is over it giving back what had it before it).
pub fn Tree::on_layers_focus(self : Tree, f : (Array[NodeId], Array[(NodeId, NodeId?)]) -> Unit) -> Unit {
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
  let opened : Array[(NodeId, NodeId?)] = []
  for o in self.focus_opened {
    if self.alive_id(o.0) && !self.leaving_at(o.0.at) && !opened.iter().any(fn(p) { p.0 == o.0 }) {
      opened.push(o)
    }
  }
  self.focus_opened.clear()
  let by : Array[((NodeId, NodeId?), Array[Int])] = []
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

///|
/// Whether Tab stops on it, as `on` says as it changes (View::focusable's `tab`, said once there): a roving group one
/// stop of, its current one's (Radix's roving focus: Tab to the group, its arrows within it). The last said of it is
/// what holds: said again, what was said before let go of; View::focusable said after it, its `tab` (said before it,
/// whether that takes the focus changing leaves this alone).
pub fn View::tab_stop(self : View, on : Live[Bool]) -> View {
  guard self.live() is Some(n) else { return self }
  match n.props.get(TabStop) {
    Some(stop) => {
      n.props.remove(TabStop)
      stop()
    }
    None => ()
  }
  n.tab_by_stop = true
  let set = fn(v : Bool, tell : Bool) {
    guard self.live() is Some(n) else { return }
    let was = n.focus_tab
    n.focus_tab = v
    if tell && was != v {
      self.tree.marked()
    }
  }
  match on {
    Is(v) => set(v, true)
    Painted(_) => not_painted("what is said here")
    Roomed(_, _) => not_roomed()
    By(f) =>
      self.owning(fn() {
        let first = Ref(true)
        let stop = self.tree.structured(f, fn(v) {
          self.owning(fn() { set(v, first.val) })
          first.val = false
        })
        n.props[TabStop] = stop
      })
  }
  self
}

///|
/// What waited for its node to come back for the focus (laid out nowhere as it had it: Tree::outs_told) waits no more:
/// the focus come to something of what hosts the tree (an old view's field or button) meanwhile, that keeps it.
pub fn Tree::focus_parked_drop(self : Tree) -> Unit {
  self.focus_parked = None
}
