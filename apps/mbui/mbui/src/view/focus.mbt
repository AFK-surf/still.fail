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
#derive(Eq, Debug)
pub(all) struct FocusAt {
  id : NodeId
  hosted : Bool
  keys : Int
}

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
  match n.props.get(Prop::Focusable.ord()) {
    Some(stop) => {
      n.props.remove(Prop::Focusable.ord())
      stop()
    }
    None => ()
  }
  // (its `tab` the last said of Tab's stop on it: View::tab_stop said before let go of)
  match n.props.get(Prop::TabStop.ord()) {
    Some(stop) => {
      n.props.remove(Prop::TabStop.ord())
      stop()
    }
    None => ()
  }
  n.tab_by_stop = false
  // (`tell`: said by this call, not as what a binding read changed (Tree::structured marks the tree for that):
  // what is read out of it told by the frame then owed, where it changed)
  let set = fn(on : Bool, tell : Bool) {
    guard self.live() is Some(n) else { return }
    let was = (n.focusable, n.focus_keys, n.focus_tab)
    n.focusable = on
    self.tree.said_marked(self.at, words=false, state=true)
    n.focus_keys = keys
    // (Tab's stop on it View::tab_stop's where that was said after this: not undone as whether it takes the focus
    // changes)
    if !n.tab_by_stop {
      n.focus_tab = tab
    }
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
        n.props[Prop::Focusable.ord()] = stop
      })
  }
  self
}

///|
/// Whether it has the keyboard's focus: what reads it told only as the focus comes to it or leaves it. Its cell made as
/// first read, let go with it.
pub fn View::focused(self : View) -> Bool {
  guard self.live() is Some(n) else { return false }
  self.tree.ground_reads(ground_read_focus)
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
  self.tree.ground_reads(ground_read_focus)
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
/// before what it holds, what it holds in its order): those that may have the keyboard's focus now (Tree::keys_at: a
/// modal layer over them says not, Tree::allows; not leaving, not said to take no press; in use, View::in_use).
pub fn Tree::focus_order(self : Tree) -> Array[FocusAt] {
  let out : Array[FocusAt] = []
  fn walk(at : Int) -> Unit {
    let n = self.nodes[at]
    if !n.live {
      return
    }
    if (n.hosted || (n.focusable && n.focus_tab)) && self.keys_at(at) {
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
    self.focus_parked = None
  }
  let was = self.focused
  let shown_was = self.focus_visible
  self.focused = id
  self.focus_visible = visible
  // (the page's list whose row it is in, walked up to once here: Tree::row_focus_holds)
  if was != id {
    self.focus_row_list = None
    match id {
      Some(to) => {
        let mut i = to.at
        while i >= 0 && self.focus_row_list is None {
          match self.rows_named.get(i) {
            Some(r) => self.focus_row_list = Some(r.0)
            None => i = self.nodes[i].parent
          }
        }
        if self.focus_row_list is Some(_) {
          self.focus_row_n = self.focus_row_n + 1
        }
      }
      None => ()
    }
  }
  // (a sequence of keys under way ends as the focus moves: keymap.mbt)
  if was != id {
    self.keys_end(FocusMoved)
  }
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
    // (kept in sight by what brings it as its room changes, while the focus stays on it: Tree::holds_now)
    Some(to) if was != id => self.show_in_sight(to, holds=fn() { self.focused == Some(to) })
    _ => ()
  }
  @signals.end_batch()
}

///|
/// Whether the focus is in one of the rows of the page's list `list` (Tree's focus_row_list), and the time it came
/// into one (each coming one more): a list holds what shows while it is so, and its hand's bringing it to its foot
/// lets go of the hold only till the focus next comes into a row (View::scrolls_window). One comparison where none is.
fn Tree::row_focus_holds(self : Tree, list : NodeId) -> Int? {
  match self.focus_row_list {
    Some(l) if l == list => Some(self.focus_row_n)
    _ => None
  }
}

///|
/// What brings a part of what it holds into its sight (Tree::show_in_sight: the focus come to it): `f` given where that
/// is in its own terms (its top, its foot; `across`, its start, its end), answering how far it moved what it holds to
/// (down, or `across` along it: a column that scrolls, a row that scrolls sideways, View::scrolls), all of it laid out,
/// before it is drawn. `room`: down a column, how tall it is and how much of that what lies over its top and its foot
/// covers, as it is now: what it keeps the focus in sight in as that changes (Tree::holds_now).
pub fn View::shows(
  self : View,
  f : (Double, Double) -> Double,
  across? : Bool = false,
  room? : () -> (Double, Double, Double),
) -> View {
  guard self.live() is Some(n) else { return self }
  n.shows = Some(f)
  n.shows_across = across
  n.shows_room = room
  self
}

///|
/// Whether node `id` can take the focus now (View::focusable, and it may have the keyboard's: Tree::keys_at, taking
/// presses, under no modal layer that does not hold it, in use): what a screen reader may give it.
pub fn Tree::can_focus(self : Tree, id : NodeId) -> Bool {
  // (held by no node from the root (put by: View::park): not to be focused, as it is in no focus order)
  self.alive_id(id) && self.nodes[id.at].focusable && self.keys_at(id.at) && self.held_from_root(id.at)
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
  // (each told once all are, what reads them run after: one run as one is told, in the middle of the walk, can change
  // what holds others not walked yet (laying the tree out at its moment, Tree::laid_now or settle_now: a page left out
  // of its row, whose own telling says all of it takes none), and the rest of the walk, carrying down what it found
  // above before that, told what that left out it takes input: a row of 小屏's Home under 设置 opened over it)
  @signals.start_batch()
  self.inputs_told_each()
  @signals.end_batch()
}

///|
/// Tree::inputs_told's telling, each set as one batch.
fn Tree::inputs_told_each(self : Tree) -> Unit {
  // (where only what changed and what it holds may take input otherwise (Tree::modals_told's `within`): those alone)
  if !self.inputs_whole {
    let todo = self.inputs_in.copy()
    self.inputs_in.clear()
    // (no modal layer, the old frame's or the tree's: whether each takes input is what holds it says, worked out once
    // for each change's node and carried down what it holds, not asked again of each all the way up)
    let plain = self.modals.is_empty() && self.held_under_now() == -2
    for at in todo {
      guard at >= 0 && at < self.nodes.length() && self.nodes[at].live else { continue }
      if plain {
        let p = self.nodes[at].parent
        self.inputs_down(at, p >= 0 && self.pressless_own_at(p))
      } else {
        self.inputs_each(at)
      }
    }
    return
  }
  self.inputs_whole = false
  self.inputs_in.clear()
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
/// Node `at` and what it holds told whether each takes input (Tree::inputs_told), no modal layer said: none where what
/// holds it takes no press (`above`: leaving, said to take none, left out, in its bones), else as it says itself.
fn Tree::inputs_down(self : Tree, at : Int, above : Bool) -> Unit {
  let n = self.nodes[at]
  guard n.live else { return }
  self.work.inputs_walked += 1
  let off = above || n.left_at >= 0.0 || n.inert || n.out || n.bones != 0L
  match n.input_cell {
    Some(s) => s.set(!off)
    None => ()
  }
  let kids = n.kids
  for i in 0..<kids.length() {
    self.inputs_down(kids[i], off)
  }
}

///|
/// Node `at` and what it holds told whether each takes input (Tree::inputs_told), each asked of all that holds it and
/// of the modal layers.
fn Tree::inputs_each(self : Tree, at : Int) -> Unit {
  let n = self.nodes[at]
  guard n.live else { return }
  self.work.inputs_walked += 1
  match n.input_cell {
    Some(s) => s.set(!self.pressless_at(at))
    None => ()
  }
  let kids = n.kids
  for i in 0..<kids.length() {
    self.inputs_each(kids[i])
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
/// no keys, no Tab stop: a dialog's), given it as it opens. `takes`: to the first of what it holds that takes it and says
/// what `takes` holds (View::says; a dialog's fields and choices, not its buttons), its own ground keeping it where none
/// does; an old view it hosts, what that registered.
pub fn View::focus_opens_first(self : View, takes? : (Said) -> Bool) -> View {
  guard self.live() is Some(_) else { return self }
  let layer = self.id()
  let tree = self.tree
  tree.focus_firsts.add(layer)
  match takes {
    Some(f) => tree.focus_first_takes[layer] = f
    None => ()
  }
  self.owns(fn() {
    tree.focus_firsts.remove(layer)
    tree.focus_first_takes.remove(layer)
  })
  |> ignore
  self.layer_focus(Some(layer))
}

///|
/// Whether layer `layer` gives the focus to the first of what it holds that takes it as it opens
/// (View::focus_opens_first).
pub fn Tree::opens_first(self : Tree, layer : NodeId) -> Bool {
  self.focus_firsts.contains(layer)
}

///|
/// What layer `layer` gives the focus to the first of only, as it opens: what that one says holding (View::focus_opens_first's
/// `takes`); None, the first of what it holds that takes it, whatever it says.
pub fn Tree::opens_first_takes(self : Tree, layer : NodeId) -> ((Said) -> Bool)? {
  self.focus_first_takes.get(layer)
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
/// What opened a layer (View::opened_by): a node of the tree's, or something of an old view its host keeps by its key
/// (the old frame's widget's id, as Ctx::overlay's `return_focus` names it).
#derive(Eq, Debug)
pub(all) enum Opener {
  ByNode(NodeId)
  ByOld(Int)
}

///|
/// The layers that give the focus (View::focus_opens, focus_opens_first, focus_returns) that are `self` or in it opened
/// by `opener`: each gives the focus back to it as it goes, not to what had the focus as it opened (a row a pointer
/// opened a menu from had none: Radix's and the old kit's `return_focus=trigger`), where it can still take it then;
/// where it cannot (let go meanwhile, leaving, taking no focus), back to what had it as it opened, as one opened by
/// nothing does. Said once where what is presented is made (a presented one's own node, whatever kind it is drawn as),
/// the nearest said of it holding for a layer (Tree::opener_of). Said again, the last said holds.
pub fn View::opened_by(self : View, opener : Opener) -> View {
  guard self.live() is Some(_) else { return self }
  let id = self.id()
  let tree = self.tree
  let first = !tree.layer_openers.contains(id)
  tree.layer_openers[id] = opener
  if first {
    self.owns(fn() { tree.layer_openers.remove(id) }) |> ignore
  }
  self
}

///|
/// What opened layer `layer` (View::opened_by): the nearest said of it or of what holds it; none where none was.
pub fn Tree::opener_of(self : Tree, layer : NodeId) -> Opener? {
  guard self.alive_id(layer) else { return None }
  let mut i = layer.at
  while i >= 0 {
    match self.layer_openers.get({ at: i, gen: self.nodes[i].gen }) {
      Some(o) => return Some(o)
      None => ()
    }
    i = self.nodes[i].parent
  }
  None
}

///|
/// Whether node `id` could be given the focus as a layer over it goes (View::opened_by): it lives, is not leaving and
/// takes the focus (View::focusable); what a modal layer over it keeps from input may still be given it, as that goes.
pub fn Tree::focus_back_takes(self : Tree, id : NodeId) -> Bool {
  self.alive_id(id) && !self.leaving_at(id.at) && self.nodes[id.at].focusable
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
  match n.props.get(Prop::TabStop.ord()) {
    Some(stop) => {
      n.props.remove(Prop::TabStop.ord())
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
    By(f) =>
      self.owning(fn() {
        let first = Ref(true)
        let stop = self.tree.structured(f, fn(v) {
          self.owning(fn() { set(v, first.val) })
          first.val = false
        })
        n.props[Prop::TabStop.ord()] = stop
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
