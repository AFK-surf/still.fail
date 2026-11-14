// A column that scrolls (View::scrolls, a page's list's too) answers the keys an old view's list does (ui's
// Ctx::list_key): Home and End to its ends, Page Up and Page Down by what shows less a line, ↑ and ↓ by a line, each at
// once at the key's moment, as an old view's list is moved by them. They are the tree's keymap's (scroll_bindings,
// after all an app binds: what it binds them to is its), never while a field has the focus, and go to one column alone,
// decided once as the key is matched: the one with the focus in it (the innermost), else the one under the pointer (the
// innermost there); at its end it keeps the key, as an old view's list does, nothing outside it moved.

///|
/// The actions a column's keys do, by name (View::on_action's).
pub let scroll_page_down : String = "scroll.page_down"

///|
pub let scroll_page_up : String = "scroll.page_up"

///|
pub let scroll_line_down : String = "scroll.line_down"

///|
pub let scroll_line_up : String = "scroll.line_up"

///|
pub let scroll_top : String = "scroll.top"

///|
pub let scroll_foot : String = "scroll.foot"

///|
/// A line, as an arrow key scrolls an old view's list (ui's Ctx::list_key: 40), and what a page keeps of what showed
/// (its height less this).
pub let scroll_key_line : Double = 40.0

///|
/// The keys of a column's actions (ui's key codes: ↑ 5, ↓ 6, Home 8, End 9, Page Up 15, Page Down 16), none held, and
/// not while a field has the focus (Tree::stroke's `Field`).
let scroll_bindings : Array[Binding] = {
  let not_field = Not(In("Field"))
  [
    { keys: [{ code: 16, mods: 0 }], action: scroll_page_down, when: not_field },
    { keys: [{ code: 15, mods: 0 }], action: scroll_page_up, when: not_field },
    { keys: [{ code: 6, mods: 0 }], action: scroll_line_down, when: not_field },
    { keys: [{ code: 5, mods: 0 }], action: scroll_line_up, when: not_field },
    { keys: [{ code: 8, mods: 0 }], action: scroll_top, when: not_field },
    { keys: [{ code: 9, mods: 0 }], action: scroll_foot, when: not_field },
  ]
}

///|
/// Whether node `at` (a column that scrolls) is the one a column's key goes to as it is matched: the focus in it, or
/// none in a column and the pointer over it (where it is drawn now, the window's points). Asked the innermost first
/// (the focus's chain, then the nodes the one drawn last first: Tree::action_nodes), so the innermost such takes it.
fn Tree::scroll_keys_here(self : Tree, at : Int) -> Bool {
  guard at >= 0 && at < self.nodes.length() && self.nodes[at].live else { return false }
  let me : NodeId = { at, gen: self.nodes[at].gen }
  match self.focused {
    Some(f) if self.holds(me, f) => return true
    Some(f) if self.scroll_holding_focus(f) => return false
    _ => ()
  }
  // (an old view's list under the pointer: its, ui's Ctx::list_key)
  if @signals.untracked(fn() { (self.old_scroll_here)() }) {
    return false
  }
  self.scroll_under_pointer() == Some(at)
}

///|
/// The innermost column that scrolls under the pointer, as things are drawn now: what of it is drawn topmost there
/// (within what bounds it, as a wheel finds it: Tree::wheel_at), up to the first column that holds it.
fn Tree::scroll_under_pointer(self : Tree) -> Int? {
  let (px, py) = self.pointer_said()
  guard px >= 0.0 && py >= 0.0 else { return None }
  let now = self.logic_said()
  let found : Ref[Int?] = Ref(None)
  // (of what takes input there, as a wheel finds it: what is only drawn over it (a bar's glass) passed)
  self.each_drawn_scaled(fn(c, cx, cy, _, s) {
    if self.finger_on(c, cx, cy, s, px, py, now, tracked=false) {
      let n = self.nodes[c.id.at]
      if n.on_wheel is Some(_) ||
        n.on_drag is Some(_) ||
        n.on_press is Some(_) ||
        n.top_row ||
        (n.hosted && @signals.untracked(fn() { (self.old_there)(c.id, px, py) })) {
        found.val = Some(c.id.at)
      }
    }
  })
  guard found.val is Some(i) else { return None }
  let mut q = i
  while q >= 0 {
    if self.scrolls_at.contains(q) {
      return Some(q)
    }
    q = self.nodes[q].parent
  }
  None
}

///|
/// Whether a column that scrolls holds node `f` (the focus): its keys then that column's, none under the pointer's.
fn Tree::scroll_holding_focus(self : Tree, f : NodeId) -> Bool {
  guard f.at >= 0 && f.at < self.nodes.length() && self.nodes[f.at].live && self.nodes[f.at].gen == f.gen else {
    return false
  }
  let mut q = f.at
  while q >= 0 {
    if self.scrolls_at.contains(q) {
      return true
    }
    q = self.nodes[q].parent
  }
  false
}

///|
/// Whether the focus is in a column that scrolls (a column's keys then its, ahead of an old view's list under the
/// pointer: ui's view_key).
pub fn Tree::focus_in_scroll(self : Tree) -> Bool {
  match self.focused {
    Some(f) => self.scroll_holding_focus(f)
    None => false
  }
}

///|
/// The column's key's `action` done at `t` (v: the node it scrolls in): moved at once, as an old view's list is by its
/// keys, as far as it goes; true, at its end too (the key its).
fn Scroll::keyed(self : Scroll, v : View, t : Double, action : String) -> Bool {
  if self.as_list {
    self.wheel_stops(v, t)
  }
  let shown = match self.seen.untracked() {
    Some((_, h)) => h
    None => 0.0
  }
  let page = shown - scroll_key_line
  if action == scroll_page_down {
    self.moved(t, page) |> ignore
  } else if action == scroll_page_up {
    self.moved(t, -page) |> ignore
  } else if action == scroll_line_down {
    self.moved(t, scroll_key_line) |> ignore
  } else if action == scroll_line_up {
    self.moved(t, -scroll_key_line) |> ignore
  } else if action == scroll_top {
    self.sent(t, 0.0)
  } else if action == scroll_foot {
    if !(self.to_foot)(t) {
      self.sent(t, self.most())
    }
  } else {
    return false
  }
  true
}

///|
/// A column's keys said on the node it scrolls in (View::scrolls, down a column alone).
fn View::scroll_keys(self : View, s : Scroll) -> Unit {
  let tree = self.tree
  let at = self.at
  for a in [scroll_page_down, scroll_page_up, scroll_line_down, scroll_line_up, scroll_top, scroll_foot] {
    self.on_action(a, fn(e) { s.keyed(self, e.at, a) }, can=fn() { tree.scroll_keys_here(at) }) |> ignore
  }
}

///|
/// What says an old view's list is under the pointer (ui's: its frame's lists, as Ctx::list_key finds them), asked as
/// a column's key comes with the focus in none of the tree's columns: then the key is that list's.
pub fn Tree::on_old_scroll(self : Tree, f : () -> Bool, there? : (NodeId, Double, Double) -> Bool) -> Unit {
  self.old_scroll_here = f
  match there {
    Some(t) => self.old_there = t
    None => ()
  }
}

///|
/// Where the pointer is in the window as the tree was last told (Tree::point_at; (-1, -1) none): where an old view's
/// list under it is found as a key comes (ui's), the tree taking the pointer's events.
pub fn Tree::pointer_said(self : Tree) -> (Double, Double) {
  if self.pointer_xy.0 >= 0.0 {
    self.pointer_xy
  } else {
    self.key_point
  }
}

///|
/// Where the pointer, a mouse's or a finger's, is as an event of it comes (ui's, each event): where a column's key
/// goes where nothing is hovered, as an old view's list's did where the last touch was.
pub fn Tree::key_point_is(self : Tree, x : Double, y : Double) -> Unit {
  self.key_point = (x, y)
}


