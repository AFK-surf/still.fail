// The keyboard's focus beyond a field's: any widget can take it (Ctx::interact registers what can; Tab goes among
// them in the tree's order, a list's rows where the list is). Tab goes to the next, Shift+Tab to the one before, round
// from the last to the first; inside a layer that traps it (a modal dialog's: overlay.mbt), only among what that layer
// holds. A roving group (Radix's RovingFocusGroup: a radio group, a toolbar, tabs, a menu's items) is one stop for Tab,
// its current item (the one
// last focused in it, else the one it says, else its first); the arrows along it move among its items (Left and Right
// swap where the direction is right to left), Home and End to its first and last. Enter and Space press what has the
// focus (as its widget says: a checkbox only takes Space). The focus shows (a ring) only once it came by the keyboard,
// as a browser's :focus-visible; a press lets it go from anything but a field, unless what was pressed takes it.
//
// The keys are dealt with as the frame starts, from what the last frame built, before the view builds this one: what
// they did (a focus moved, a press) is there for the widgets as they are built, and a key used so is taken (the
// view's Ctx::key_pressed does not see it, as a field's keys).

///|
/// How a roving group's items lie: the arrows that move along it.
pub(all) enum Orientation {
  Horizontal
  Vertical
  Both
} derive(Eq, Show, Debug)

///|
/// What can take the focus, as built: its id, its roving group (0 none), the layer it is in (0 the page), its node,
/// which keys press it (1 Enter, 2 Space), whether a press with the pointer gives it the focus.
struct Focusable {
  id : Int
  group : Int
  layer : Int
  node : Int
  keys : Int
  on_press : Bool
  /// the old view it was built in (view_host.mbt's island_allows), none in a layer of its own
  island : @view.NodeId?
}

///|
/// A roving group's state, kept by its id: how its items lie, whether the arrows go round, its current item, the item
/// it says holds the stop when none has been focused (a radio group's checked one, the tabs' selected one), the
/// frame it was last built.
struct Group {
  mut orientation : Orientation
  mut wrap : Bool
  mut current : Int
  mut preferred : Int
  mut frame : Int
}

///|
/// Keys that press what has the focus (Ctx::interact `keys`).
pub let press_enter : Int = 1

///|
pub let press_space : Int = 2

///|
/// The arrows, Home, End, Page Up and Page Down are its own (a slider's thumb: Ctx::take_key reads them), not a list's
/// under the pointer.
pub let own_arrows : Int = 4

///|
/// The key code of Space with no field focused (a character as 1000 + it).
pub let key_space : Int = 1032

///|
/// `id` can take the focus (from Tab, the arrows of its group, `on_press` a press on it): said each frame it is
/// built, in the order Tab goes. A finger pressing another control leaves an active field's focus with it; another
/// field takes it. `keys`: which of Enter (press_enter) and Space (press_space) press it, and whether the arrows are
/// its own (own_arrows).
pub fn Ctx::focusable(self : Ctx, id : Int, node? : Int = -1, keys? : Int = 3, on_press? : Bool = false) -> Unit {
  if id == 0 {
    return
  }
  // (the old view it is in, built in no layer of its own: what a modal layer of the window's tree asks of it, as it is
  // used: island_allows)
  let island = if self.layer_cur == 0 { island_building.val } else { None }
  let f = { id, group: self.group_cur, layer: self.layer_cur, node, keys, on_press, island }
  // (held by its node, docs/retained.md the way there's 1: by `node`, else by the id's, made or to be: Ctx::id_built)
  let i = if node >= 0 {
    node
  } else {
    match self.built_ids.get(id) {
      Some(i) if i < self.count && self.nodes[i].id == id => i
      _ => -1
    }
  }
  if i >= 0 {
    self.nodes[i].focus = Some(f)
  } else {
    self.focus_ahead[id] = f
  }
}

///|
/// What can take the focus this build, in Tab's order: the nodes said to (Node's `focus`), in the tree's order (a node
/// before what it holds, what it holds as it lies: a list's rows where the list is, top to bottom; Ctx::tree_order).
fn Ctx::focusables_found(self : Ctx) -> Unit {
  self.focusables.clear()
  for i in self.tree_order() {
    match self.nodes[i].focus {
      Some(f) => self.focusables.push({ ..f, node: i })
      None => ()
    }
  }
}

///|
/// The items built in `body` are a roving group's (see the file's head): one stop for Tab, `orientation` the arrows
/// that move along it, round from the last to the first unless not `wrap`. `current`: the item that holds the stop
/// while none of them has been focused (a radio group's checked one; 0: the first).
pub fn Ctx::roving(
  self : Ctx,
  key : String,
  orientation? : Orientation = Both,
  wrap? : Bool = true,
  current? : Int = 0,
  body : () -> Unit,
) -> Unit {
  let id = self.id(key)
  let gr = match self.groups.get(id) {
    Some(gr) => gr
    None => {
      let gr = { orientation, wrap, current: 0, preferred: current, frame: -1 }
      self.groups[id] = gr
      self.own(id)
      gr
    }
  }
  gr.orientation = orientation
  gr.wrap = wrap
  gr.preferred = current
  gr.frame = self.frame_no
  let saved = self.group_cur
  self.group_cur = id
  body()
  self.group_cur = saved
}

///|
/// The roving group being built has `id` hold its stop from now on while none of its items has been focused (a radio
/// checked by a tap as it is built: Tab lands on it next frame, though no frame comes between).
pub fn Ctx::roving_prefer(self : Ctx, id : Int) -> Unit {
  match self.groups.get(self.group_cur) {
    Some(gr) => gr.preferred = id
    None => ()
  }
}

///|
/// Whether `id` has the keyboard's focus.
pub fn Ctx::has_focus(self : Ctx, id : Int) -> Bool {
  if id == 0 {
    return false
  }
  // (read so: what reads it is built again as the focus comes to it or leaves it, hand.mbt)
  hand.focus.has(id) |> ignore
  self.focus == id
}

///|
/// Whether `id` has the focus and it shows (it came by the keyboard): where a focus ring is drawn.
pub fn Ctx::focus_shown(self : Ctx, id : Int) -> Bool {
  // (shown as the keys moved it, told as that changes: hand.mbt)
  hand.shown.has(id) |> ignore
  self.has_focus(id) && self.focus_visible
}

///|
/// The focus given to `id` (a field, a button, what a dialog opens on); `visible`: shown as though the keyboard moved
/// it.
pub fn Ctx::focus_on(self : Ctx, id : Int, visible? : Bool = false) -> Unit {
  if visible {
    self.focus_visible = true
  }
  self.focus_moved(id)
  if visible {
    // (as the keys moved it: in view where it scrolls)
    self.show(id)
  }
  // (in a build: built again from it; else what read it told by the focus's move itself: Ctx::focus_moved)
  if building.val {
    self.read_changed("the focus given")
  }
}

///|
/// Whether `id` came to have the focus since the last frame (a radio's, a tab's: chosen as the arrows reach it).
pub fn Ctx::focus_gained(self : Ctx, id : Int) -> Bool {
  self.has_focus(id) && self.focus_before != id
}

///|
/// Whether the focus came to `id` since the last frame by the arrows of its roving group (a radio's: chosen so; not
/// by Tab, which only lands on it).
pub fn Ctx::focus_roved_to(self : Ctx, id : Int) -> Bool {
  self.focus_gained(id) && self.focus_roved
}

///|
/// What had the focus as the frame started (0 nothing).
pub fn Ctx::focused_id(self : Ctx) -> Int {
  hand.focus_id.get() |> ignore
  self.focus
}

///|
/// As the frame starts: the keys since the last one that move or use the focus, and the actions asked (see the file's
/// head).
fn Ctx::focus_frame_start(self : Ctx) -> Unit {
  // (the keys, what a reader asked and the focus, read so: hand.mbt)
  hand_presses_read()
  hand.focus_id.get() |> ignore
  self.actions.clear()
  for a in self.asked_actions {
    self.actions.push(a)
    if a.1 == Focus {
      self.focus_moved(a.0)
    }
  }
  self.asked_actions.clear()
  // a layer's own keys first (Escape: overlay.mbt)
  self.layer_keys()
  // (the focus where a modal layer of the window's tree lets it take input; else, for these keys, none's:
  // Ctx::focus_allowed)
  let focus = self.focus_allowed()
  let field = self.editors.contains(focus)
  // (the keys a field focused leaves to the app: Tab there picks from what it offers, the focus stays)
  let left = match self.editors.get(focus) {
    Some(st) => st.leaves
    None => []
  }
  for k in 0..<desk.keys.length() {
    let (code, mods, taken) = desk.keys[k]
    if taken || (mods == 0 && left.contains(code)) {
      continue
    }
    let used = if code == key_tab && (mods | mod_shift_key) == mod_shift_key {
      self.tab((mods & mod_shift_key) != 0)
      true
    } else if field {
      false
    } else if mods == 0 &&
      (
        code == key_left ||
        code == key_right ||
        code == key_up ||
        code == key_down ||
        code == key_home ||
        code == key_end
      ) {
      self.rove(code)
    } else if mods == 0 && (code == key_enter || code == key_space) {
      self.press_focused(if code == key_enter { press_enter } else { press_space })
    } else {
      false
    }
    if used {
      desk.keys[k] = (code, mods, true)
    }
  }
}

///|
/// What can take the focus now, in Tab's order: the last frame's (where the window is a tree, spliced with its nodes'
/// as it is now: Ctx::focus_spliced), those of the layer that traps it if one does, each roving group once (at its
/// stop).
fn Ctx::tab_stops(self : Ctx) -> Array[Focusable] {
  let trap = self.trapping_layer()
  let out : Array[Focusable] = []
  let seen : Map[Int, Bool] = {}
  for f in self.focus_spliced() {
    // (and what of the window's tree is over the trapping layer in the window's stack of layers: no layer under it
    // traps it, View::stacked; under a modal layer of the tree's over it, an old one's none: Tree::allows)
    if trap != 0 && !self.layer_within(f.layer, trap) && focus_stack(f.id) <= self.trap_stack(trap) {
      continue
    }
    if f.layer != 0 && self.layer_stack_of(f.layer) < tree_modal_stack() {
      continue
    }
    if self.layer_inert(f.layer) || !island_allows(f.island) {
      continue
    }
    if f.group == 0 {
      out.push(f)
    } else if !seen.contains(f.group) {
      seen[f.group] = true
      out.push(self.group_stop(f.group))
    }
  }
  out
}

///|
/// The item of group `gid` that is its stop for Tab (see Ctx::roving).
fn Ctx::group_stop(self : Ctx, gid : Int) -> Focusable {
  let items = self.group_items(gid)
  let (current, preferred) = match self.groups.get(gid) {
    Some(gr) => (gr.current, gr.preferred)
    None => (0, 0)
  }
  for want in [current, preferred] {
    if want != 0 {
      for f in items {
        if f.id == want {
          return f
        }
      }
    }
  }
  items[0]
}

///|
/// Group `gid`'s items as the last frame built them.
fn Ctx::group_items(self : Ctx, gid : Int) -> Array[Focusable] {
  self.last_focusables.filter(fn(f) { f.group == gid && island_allows(f.island) })
}

///|
/// Tab (`back`: Shift+Tab): the focus to the next stop (the one before), round.
fn Ctx::tab(self : Ctx, back : Bool) -> Unit {
  let stops = self.tab_stops()
  if stops.is_empty() {
    return
  }
  // where the focus is among them (in a group: the group's stop)
  let mut at = -1
  let mut group = 0
  for f in self.last_focusables {
    if f.id == self.focus {
      group = f.group
    }
  }
  for k, f in stops {
    if f.id == self.focus || (group != 0 && f.group == group) {
      at = k
    }
  }
  let n = stops.length()
  let next = if at < 0 {
    if back {
      n - 1
    } else {
      0
    }
  } else if back {
    (at + n - 1) % n
  } else {
    (at + 1) % n
  }
  self.move_focus(stops[next].id)
}

///|
/// The focus moved to `id` by the keyboard: it shows, brought into view where it scrolls (Ctx::show); its group (if
/// any) has it as its current item.
fn Ctx::move_focus(self : Ctx, id : Int, roved? : Bool = false) -> Unit {
  self.focus_moved(id, visible=true)
  self.show(id)
  self.focus_roved = roved
  for f in self.last_focusables {
    if f.id == id && f.group != 0 {
      match self.groups.get(f.group) {
        Some(gr) => gr.current = id
        None => ()
      }
    }
  }
  // (in a build: built again from it; else what read it told by the focus's move itself: Ctx::focus_moved)
  if building.val {
    self.read_changed("the focus moved")
  }
}

///|
/// An arrow, Home or End with the focus in a roving group: the focus along it. False when it is not the group's.
fn Ctx::rove(self : Ctx, code : Int) -> Bool {
  match self.roved_to(code) {
    Some(id) => {
      self.move_focus(id, roved=true)
      true
    }
    None => false
  }
}

///|
/// Where an arrow, Home or End takes the focus along its roving group (Ctx::rove), if it is the group's: none where it
/// is not, or the focus is in no group, or where a modal layer of the window's tree keeps it from input.
fn Ctx::roved_to(self : Ctx, code : Int) -> Int? {
  // (none where a modal layer of the window's tree keeps the focus from input: Ctx::focus_allowed)
  if self.focus_allowed() == 0 {
    return None
  }
  let mut gid = 0
  for f in self.last_focusables {
    if f.id == self.focus && f.group != 0 {
      gid = f.group
    }
  }
  if gid == 0 {
    return None
  }
  let gr = match self.groups.get(gid) {
    Some(gr) => gr
    None => return None
  }
  let items = self.group_items(gid)
  let n = items.length()
  let mut at = 0
  for k, f in items {
    if f.id == self.focus {
      at = k
    }
  }
  let rtl = self.direction == Rtl
  let horizontal = gr.orientation != Vertical
  let vertical = gr.orientation != Horizontal
  let step = if horizontal && code == key_right {
    if rtl {
      -1
    } else {
      1
    }
  } else if horizontal && code == key_left {
    if rtl {
      1
    } else {
      -1
    }
  } else if vertical && code == key_down {
    1
  } else if vertical && code == key_up {
    -1
  } else {
    0
  }
  let next = if code == key_home {
    0
  } else if code == key_end {
    n - 1
  } else if step == 0 {
    return None
  } else if gr.wrap {
    (at + step + n) % n
  } else {
    imax(0, imin(n - 1, at + step))
  }
  Some(items[next].id)
}

///|
/// Enter or Space (`key`: press_enter, press_space) on what has the focus: pressed, if it takes that key.
fn Ctx::press_focused(self : Ctx, key : Int) -> Bool {
  if self.focus == 0 {
    return false
  }
  for f in self.last_focusables {
    if f.id == self.focus && (f.keys & key) != 0 && !self.layer_inert(f.layer) && island_allows(f.island) {
      self.clicked.push(f.id)
      made_pressed(f.id)
      self.focus_moved(self.focus, visible=true)
      return true
    }
  }
  false
}

///|
/// A primary press went down on `target` (0 nothing): it takes the focus if it does on a press; else the focus is let
/// go from anything but a field (a field keeps it: what is tapped beside it, a send button, does not take its keys).
fn Ctx::focus_on_press(self : Ctx, target : Int) -> Unit {
  self.focus_moved(self.focus, visible=false)
  // a press on the ground of a layer that traps the focus leaves it where it is (in the layer)
  let trap = self.trapping_layer()
  if trap != 0 && target == trap {
    return
  }
  // (a field on Android takes it as the finger lifts where it came down: a tap, app.mbt editor_tap)
  let tap_later = h_feel() == 2 && self.editors.contains(target)
  // A finger using another control can keep writing in the field; a mouse press and a tap in another field still
  // move focus as that control asks.
  let field_keeps = pointing() is Finger && self.editors.contains(self.focus) && !self.editors.contains(target)
  for f in self.last_focusables {
    if f.id == target && f.on_press && !tap_later && !field_keeps {
      self.focus_moved(target)
      return
    }
  }
  // (one a modal layer of the window's tree keeps from input kept as it is: no input of its takes it away, view_host.mbt)
  if self.focus != target &&
    self.focus_allowed() != 0 &&
    !self.editors.contains(self.focus) &&
    !self.dev.catchers.contains(self.focus) {
    self.focus_moved(0)
  }
}

///|
/// As the frame ends: what can take the focus now is what Tab goes among next frame.
fn Ctx::focus_frame_end(self : Ctx) -> Unit {
  // what has it now is what the next frame's keys and presses move it from (Ctx::focus_gained)
  self.focus_before = self.focus
  self.focus_roved = false
  let last = self.last_focusables
  self.last_focusables = self.focusables
  last.clear()
  self.focusables = last
  // groups not built for a while are forgotten
  if self.frame_no % 120 == 0 {
    let old : Array[Int] = []
    self.groups.each(fn(id, gr) { if self.frame_no - gr.frame > 120 { old.push(id) } })
    for id in old {
      self.groups.remove(id)
    }
  }
}

///|
/// Whether key `code` is the focused widget's (an arrow in a roving group, Enter or Space it is pressed by): it goes
/// to it as the next frame starts, and scrolls nothing.
fn Ctx::focus_takes(self : Ctx, code : Int) -> Bool {
  if self.focus_allowed() == 0 {
    return false
  }
  for f in self.last_focusables {
    if f.id == self.focus {
      return f.group != 0 ||
        (code == key_enter && (f.keys & press_enter) != 0) ||
        (code == key_space && (f.keys & press_space) != 0) ||
        ((f.keys & own_arrows) != 0 &&
        (
          code == key_left ||
          code == key_right ||
          code == key_up ||
          code == key_down ||
          code == key_home ||
          code == key_end ||
          code == key_page_up ||
          code == key_page_down
        ))
    }
  }
  false
}

///|
/// Whether what has the focus (where it may take input: Ctx::focus_allowed) takes key `code` (`mods` held) as its own,
/// as the keys are taken (Ctx::focus_frame_start: no modifier; an arrow, Home or End along its roving group, Ctx::rove;
/// Enter or Space it is pressed by, Ctx::press_focused; the arrows, Home, End, PageUp and PageDown of what says they are
/// its own, own_arrows): what else would have the key first leaves it to it.
fn Ctx::focus_keeps(self : Ctx, code : Int, mods : Int) -> Bool {
  let focus = self.focus_allowed()
  if focus == 0 || mods != 0 {
    return false
  }
  if self.roved_to(code) is Some(_) {
    return true
  }
  for f in self.last_focusables {
    if f.id == focus && !self.layer_inert(f.layer) {
      return (code == key_enter && (f.keys & press_enter) != 0) ||
        (code == key_space && (f.keys & press_space) != 0) ||
        ((f.keys & own_arrows) != 0 &&
        [key_left, key_right, key_up, key_down, key_home, key_end, key_page_up, key_page_down].contains(code))
    }
  }
  false
}

///|
/// The focus to `id` (0: none; an old widget's id, or the one a node of the window's tree is read out by: tree_said_id),
/// shown as `visible` says (none: as it was): every move of the focus, whoever moves it (Tab, a press, a field, a layer
/// opening or closing, a screen reader), the window's tree told at once of what of its own has it (its node's, Tree::
/// focus_to: one focus, read on either side); a node's no longer able to take it (let go, another tree's, leaving,
/// taking no press, under a modal layer), the focus to none.
fn Ctx::focus_moved(self : Ctx, id : Int, visible? : Bool) -> Unit {
  self.focus = id
  match visible {
    Some(v) => self.focus_visible = v
    None => ()
  }
  // (both sides told as one change)
  @signals.start_batch()
  focus_told_tree(self)
  // (what of the old views reads it told now, with the tree's, in a build too: what read it as it was before (a field
  // read without it, given it back in the same build) built again from it, nothing else; between builds, the host owing
  // a frame for it)
  hand_focus_said(self)
  if !building.val {
    h_frame_owed()
  }
  @signals.end_batch()
}

///|
/// Where the old frame's layer `id` (as the last frame built it) is in the window's stack of layers (Ctx::layer_stack);
/// -1 where it is none of them.
fn Ctx::layer_stack_of(self : Ctx, id : Int) -> Int {
  match self.last_layers.iter().find_first(fn(l) { l.id == id }) {
    Some(l) => self.layer_stack(l)
    None => -1
  }
}

///|
/// Where the layer trapping the focus is in the window's stack of layers (Ctx::layer_stack_of).
fn Ctx::trap_stack(self : Ctx, trap : Int) -> Int {
  self.layer_stack_of(trap)
}

///|
/// Where the window's tree's topmost modal layer is in the window's stack of layers (Tree::modal_stack), -2 none.
fn tree_modal_stack() -> Int {
  match view_app.val {
    Some(tree) => tree.modal_stack()
    None => -2
  }
}
