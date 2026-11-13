// The widgets told to the system's accessibility (a screen reader: VoiceOver, TalkBack, Narrator), as AccessKit tells
// a window's to it: while something reads them out (@hostapi.a11y_on), what changed of the semantics tree
// (semantics.mbt), what is not hidden, goes to the host as it is painted (@hostapi.a11y_tree): the nodes that came out
// otherwise than they were last told, each whole, and which has the keyboard's focus; the host keeps the nodes by their
// numbers and makes its own elements of them (Mac: MBA11yElement, Windows: UI Automation's fragments, Android: MBView's
// A11y, an AccessibilityNodeProvider). What the reader asks of a node (a double tap: activate; a swipe up or down on a
// slider: a step) comes back on @hostapi.a11y_channel and is asked of its widget (Ctx::ask_action), as a test asks it.
//
// What changed is found where it changed: of the window's tree, a pass of what changed since the last
// (@view.Tree::said_pass: only what a change marked gone through, what names a node and what it holds worked out
// again only where its words or what it holds changed); of an old view, built again each frame, all of what it says,
// told where it differs. Nothing is put in one text to be compared whole.
//
// An update is lines, its fields split by U+001F (none of them holds one, nor a line's end). The first:
//
//   T  full  focus
//
// `full` 1: what the host has is dropped first (the first once something reads, again as the host asks:
// `{"action": "resend"}` on the channel); `focus` the number of the node with the keyboard's focus (0 none). Then a line
// for each node told:
//
//   N  node  role  flags  x  y  w  h  label  value  description  low  at  high  actions  widget  kids
//
// `node` its number, its own from one update to the next (0: the view itself, holding the rest); `role` the Role's
// name; `flags` letters: c checkable (C checked, M mixed), e expandable (E expanded), s selected, p pressable (P
// pressed), d disabled, m modal, v one of no use of its own (it says nothing: the node what a column scrolls is held in,
// told so that what it holds is placed in it and moves with it as it scrolls; never shown as an element: what it holds
// is its holder's); where it is (points) from where its holder is, its size; its range (a slider's, a progress bar's)
// or three empty fields; `actions` letters: a activate, i increment, d decrement, e expand, c collapse, x dismiss, f
// focus, t words put in it (set text: `{"action": "set_text", "text": words}` asked); `widget` the id its actions are
// asked of (0 none); `kids` the numbers of what it holds in their order, split by commas.
//
// A node is told whole whenever anything of it changed, what it holds too: the host keeps what it was told and replaces
// it. One no longer in what any node told holds, nor in what this update's hold, is gone with all it holds
// (A11yMirror::apply). A node's place on the screen is its holder's and its own `x`, `y` (the view's: 0, 0): so one that
// moves is told alone, what it holds where it was.

///|
let a11y_sep : String = "\u{1F}"

///|
/// A node as the host is told it (see above): where it is from where what holds it is.
#derive(Eq, Debug)
struct A11yNode {
  id : Int
  role : String
  flags : String
  x : Double
  y : Double
  w : Double
  h : Double
  label : String
  value : String
  description : String
  range : (Double, Double, Double)?
  actions : String
  widget : Int
  kids : Array[Int]
}

///|
/// What a host keeps of what it was told (each node by its number, what holds each, which has the focus), as an update
/// leaves it: what the app keeps of what it told (A11yTold) and a test's fake host of what it was told, made the same
/// way a host makes it.
priv struct A11yMirror {
  nodes : Map[Int, A11yNode]
  holder : Map[Int, Int]
  mut focus : Int
}

///|
fn A11yMirror::new() -> A11yMirror {
  { nodes: {}, holder: {}, focus: 0 }
}

///|
/// An update taken (see the file's head): what `full` says dropped first, each node told kept in its place, what is
/// in nothing told holds gone with all it holds. The numbers of those gone.
fn A11yMirror::apply(self : A11yMirror, full : Bool, focus : Int, told : Array[A11yNode]) -> Array[Int] {
  let gone : Array[Int] = []
  if full {
    for k, _ in self.nodes {
      gone.push(k)
    }
    self.nodes.clear()
    self.holder.clear()
  }
  self.focus = focus
  // (what this update's hold: none of it gone, wherever it was)
  let held : Map[Int, Bool] = Map([])
  for n in told {
    for k in n.kids {
      held[k] = true
    }
  }
  let let_go : Array[Int] = []
  for n in told {
    match self.nodes.get(n.id) {
      Some(was) =>
        for k in was.kids {
          if !n.kids.contains(k) {
            let_go.push(k)
          }
        }
      None => ()
    }
    self.nodes[n.id] = n
    for k in n.kids {
      self.holder[k] = n.id
    }
  }
  fn drop(k : Int) -> Unit {
    if held.contains(k) {
      return
    }
    match self.nodes.get(k) {
      Some(n) => {
        self.nodes.remove(k)
        self.holder.remove(k)
        gone.push(k)
        for c in n.kids {
          drop(c)
        }
      }
      None => ()
    }
  }

  for k in let_go {
    drop(k)
  }
  gone
}

///|
/// What the host has, as a screen reader finds it: a node a line in the tree's order, those of no use of their own
/// (flags `v`) left out, what they hold their holder's, in the lines Ctx::a11y_lines writes of the tree as it is (each
/// node's number, its holder's, its widget, its role, its flags (f where it has the focus), where it is in the window
/// and its size, its label, value, description, range and actions).
fn A11yMirror::lines(self : A11yMirror) -> String {
  let sb = StringBuilder()
  fn put(k : Int, holder : Int, px : Double, py : Double) -> Unit {
    guard self.nodes.get(k) is Some(n) else { return }
    let x = px + n.x
    let y = py + n.y
    let own = !n.flags.contains("v")
    if own && k != 0 {
      let (lo, at, hi) = a11y_range(n.range)
      let flags = if self.focus == k { a11y_focused_flags(n.flags) } else { n.flags }
      let fields = [
        k.to_string(),
        holder.to_string(),
        n.widget.to_string(),
        n.role,
        flags,
        a11y_length(x),
        a11y_length(y),
        a11y_length(n.w),
        a11y_length(n.h),
        n.label,
        n.value,
        n.description,
        lo,
        at,
        hi,
        n.actions,
      ]
      sb.write_string(fields.join(a11y_sep))
      sb.write_char('\n')
    }
    let next = if own && k != 0 { k } else { holder }
    for c in n.kids {
      put(c, next, x, y)
    }
  }

  put(0, 0, 0.0, 0.0)
  sb.to_string()
}

///|
/// Flags with the focus's `f` in its place among them (before `m`).
fn a11y_focused_flags(flags : String) -> String {
  if flags.contains("m") {
    flags.replace(old="m", new="fm")
  } else {
    flags + "f"
  }
}

///|
/// A range as told: its least, where it is, its most (three empty fields: none).
fn a11y_range(range : (Double, Double, Double)?) -> (String, String, String) {
  match range {
    Some((lo, v, hi)) => (lo.to_string(), v.to_string(), hi.to_string())
    None => ("", "", "")
  }
}

///|
/// A node's line of an update (see the file's head).
fn A11yNode::line(self : A11yNode) -> String {
  let (lo, at, hi) = a11y_range(self.range)
  [
    "N",
    self.id.to_string(),
    self.role,
    self.flags,
    a11y_length(self.x),
    a11y_length(self.y),
    a11y_length(self.w),
    a11y_length(self.h),
    self.label,
    self.value,
    self.description,
    lo,
    at,
    hi,
    self.actions,
    self.widget.to_string(),
    self.kids.map(fn(k) { k.to_string() }).join(","),
  ].join(a11y_sep)
}

///|
/// An update as the host is told it (see the file's head).
fn a11y_update_text(full : Bool, focus : Int, told : Array[A11yNode]) -> String {
  let sb = StringBuilder()
  sb.write_string(["T", if full { "1" } else { "0" }, focus.to_string()].join(a11y_sep))
  sb.write_char('\n')
  for n in told {
    sb.write_string(n.line())
    sb.write_char('\n')
  }
  sb.to_string()
}

///|
/// An update read as a host reads it (see the file's head): whether it is whole, the focus, the nodes told; None where
/// it is not one.
fn a11y_update_read(text : String) -> (Bool, Int, Array[A11yNode])? {
  let lines = text.split("\n").to_array()
  guard lines.length() > 0 else { return None }
  let head = lines[0].split(a11y_sep).map(fn(v) { v.to_owned() }).to_array()
  guard head.length() >= 3 && head[0] == "T" else { return None }
  let num = a11y_int
  let real = a11y_real
  let told : Array[A11yNode] = []
  for l in lines[1:] {
    let f = l.split(a11y_sep).map(fn(v) { v.to_owned() }).to_array()
    if f.length() < 17 || f[0] != "N" {
      continue
    }
    told.push({
      id: num(f[1]),
      role: f[2],
      flags: f[3],
      x: real(f[4]),
      y: real(f[5]),
      w: real(f[6]),
      h: real(f[7]),
      label: f[8],
      value: f[9],
      description: f[10],
      range: if f[12] == "" { None } else { Some((real(f[11]), real(f[12]), real(f[13]))) },
      actions: f[14],
      widget: num(f[15]),
      kids: if f[16] == "" { [] } else { f[16].split(",").map(fn(k) { num(k.to_owned()) }).to_array() },
    })
  }
  Some((head[1] == "1", num(head[2]), told))
}

///|
/// What the app told the host and keeps of it (A11yMirror: as the host has it); the zoom it was told at (another: all
/// again); where the host asked for all again; what the window holds of the tree's, as the tree's last pass found it
/// (Tree::said_pass's root); each node of the tree's number the nearest holder of use of its own has (one of no use
/// of its own: its holder's); how many times it told.
struct A11yTold {
  mirror : A11yMirror
  mut zoom : Double
  mut again : Bool
  mut root : Array[(Int, Array[@view.SaidKid])]
  named : Map[Int, Int]
  mut passes : Int
}

///|
fn A11yTold::new() -> A11yTold {
  { mirror: A11yMirror::new(), zoom: 1.0, again: false, root: [], named: {}, passes: 0 }
}

///|
/// The number a node of the window's tree is read out by (its id's, tree_said_id: those numbers apart from an old
/// view's, which are below them).
fn a11y_tree_num(id : @view.NodeId) -> Int {
  0x20000000 | ((tree_said_id(id) - -2_000_000_000) & 0x1FFFFFFF)
}

///|
/// What the numbers of an old view's widgets are given by (a11y_old_num): those given this pass, and how many of each
/// key named so far.
priv struct A11yNames {
  used : Map[Int, Bool]
  seen : Map[String, Int]
}

///|
/// The number an old view's widget is read out by, held by `holder` (its number, or of the nearest holder of use of
/// its own): its widget's id, else of its holder, role and label (and how many of those there were before it), kept from
/// frame to frame; another's taken, the next free.
fn a11y_old_num(names : A11yNames, s : SemNode, holder : Int) -> Int {
  let base = if s.id != 0 {
    s.id
  } else {
    let key = "\{holder}\u{1F}\{s.role}\u{1F}\{s.label}"
    let nth = names.seen.get(key).unwrap_or(0)
    names.seen[key] = nth + 1
    a11y_hash("\{key}\u{1F}\{nth}")
  }
  let mut n = base & 0x1FFFFFFF
  while n == 0 || names.used.contains(n) {
    n = (n * 31 + 7) & 0x1FFFFFFF
  }
  names.used[n] = true
  n
}

///|
/// A place or size in the window as it is told: zoomed as drawn, to a thousandth of a point (what a layout summed one
/// way or another, 617 or 617.0000000000001, is told the same, and nothing is told again for it).
fn a11y_at(v : Double) -> Double {
  let z = window_zoom_drawn.val
  (v * z * 1000.0).round() / 1000.0
}

///|
/// An old view's widgets read out: of `old` (Ctx::semantics_old's), those of `ks` in their order, under the node
/// `top` (its number; `named` the nearest of use of its own's; where it is in the window, as told), what `hide` says of
/// each hidden (and what it holds the nearest's not hidden), what `off` says taking no presses, each where `rect`
/// says. Each node put in `out`; the numbers of those `top` holds, in their order.
fn a11y_olds(
  old : Array[SemNode],
  ks : Array[Int],
  top : Int,
  named : Int,
  top_at : (Double, Double),
  hide : (Int) -> Bool,
  off : Bool,
  rect : (Int) -> (Double, Double, Double, Double),
  names : A11yNames,
  out : Array[A11yNode],
) -> Array[Int] {
  let tops : Array[Int] = []
  // by index in `old`: its node's number (0 hidden), where it is, its node in `out`
  let num : Map[Int, Int] = Map([])
  let place : Map[Int, (Double, Double)] = Map([])
  let made : Map[Int, A11yNode] = Map([])
  for k in ks {
    let s = old[k]
    if s.hidden || hide(k) {
      num[k] = 0
      continue
    }
    // (its holder: the nearest above it of these not hidden, else `top`)
    let mut p = s.parent
    while p >= 0 && num.get(p) == Some(0) {
      p = old[p].parent
    }
    let (holder, holder_at) = match num.get(p) {
      Some(n) if p >= 0 && n != 0 => (n, place.get(p).unwrap_or((0.0, 0.0)))
      _ => (top, top_at)
    }
    let n = a11y_old_num(names, s, if holder == top { named } else { holder })
    let (x, y, w, h) = rect(k)
    let ax = a11y_at(x)
    let ay = a11y_at(y)
    let disabled = s.disabled || off
    let node : A11yNode = {
      id: n,
      role: s.role.to_string(),
      flags: a11y_flags(s.check, s.expanded, s.selected, s.pressed, disabled, s.modal),
      x: a11y_round(ax - holder_at.0),
      y: a11y_round(ay - holder_at.1),
      w: a11y_at(w),
      h: a11y_at(h),
      label: a11y_clean(s.label),
      value: a11y_clean(s.value),
      description: a11y_clean(s.description),
      range: s.range,
      actions: if disabled { "" } else { a11y_actions(s.actions) },
      widget: s.id,
      kids: [],
    }
    num[k] = n
    place[k] = (ax, ay)
    made[k] = node
    out.push(node)
    match made.get(p) {
      Some(h) if holder != top => h.kids.push(n)
      _ => tops.push(n)
    }
  }
  tops
}

///|
fn a11y_round(v : Double) -> Double {
  (v * 1000.0).round() / 1000.0
}

///|
/// The tree as it is read now (Ctx::semantics_tree), the nodes not hidden in its order, in lines (A11yMirror::lines
/// says them): what a host told every change has, as a test checks it.
pub fn Ctx::a11y_lines(self : Ctx) -> String {
  let tree = self.semantics_tree()
  // by the tree's index: the node's number (0 hidden)
  let num = Array::make(tree.length(), 0)
  let names : A11yNames = { used: {}, seen: {} }
  let sb = StringBuilder()
  for k, s in tree {
    if s.hidden {
      continue
    }
    // its parent: the nearest above it not hidden
    let mut p = s.parent
    while p >= 0 && num[p] == 0 {
      p = tree[p].parent
    }
    let parent = if p >= 0 { num[p] } else { 0 }
    let n = match tree_said_ids.get(s.id) {
      Some(id) => a11y_tree_num(id)
      None => a11y_old_num(names, s, parent)
    }
    num[k] = n
    let (x, y, w, h) = s.rect
    let (lo, at, hi) = a11y_range(s.range)
    let flags = a11y_flags(s.check, s.expanded, s.selected, s.pressed, s.disabled, s.modal)
    let fields = [
      n.to_string(),
      parent.to_string(),
      s.id.to_string(),
      s.role.to_string(),
      if s.focused { a11y_focused_flags(flags) } else { flags },
      a11y_length(a11y_at(x)),
      a11y_length(a11y_at(y)),
      a11y_length(a11y_at(w)),
      a11y_length(a11y_at(h)),
      a11y_clean(s.label),
      a11y_clean(s.value),
      a11y_clean(s.description),
      lo,
      at,
      hi,
      a11y_actions(s.actions),
    ]
    sb.write_string(fields.join(a11y_sep))
    sb.write_char('\n')
  }
  sb.to_string()
}

///|
fn a11y_flags(
  check : Check?,
  expanded : Bool?,
  selected : Bool?,
  pressed : Bool?,
  disabled : Bool,
  modal : Bool,
) -> String {
  let sb = StringBuilder()
  match check {
    Some(Off) => sb.write_string("c")
    Some(On) => sb.write_string("cC")
    Some(Mixed) => sb.write_string("cM")
    None => ()
  }
  match expanded {
    Some(true) => sb.write_string("eE")
    Some(false) => sb.write_string("e")
    None => ()
  }
  if selected == Some(true) {
    sb.write_string("s")
  }
  match pressed {
    Some(true) => sb.write_string("pP")
    Some(false) => sb.write_string("p")
    None => ()
  }
  if disabled {
    sb.write_string("d")
  }
  if modal {
    sb.write_string("m")
  }
  sb.to_string()
}

///|
fn a11y_actions(actions : Array[Action]) -> String {
  let sb = StringBuilder()
  for a in actions {
    sb.write_string(
      match a {
        Activate => "a"
        Increment => "i"
        Decrement => "d"
        Expand => "e"
        Collapse => "c"
        Dismiss => "x"
        Focus => "f"
        SetText(_) => "t"
      },
    )
  }
  sb.to_string()
}

///|
/// Words as a field holds them: what would end it, or the line, a space.
fn a11y_clean(s : String) -> String {
  if !s.contains("\n") && !s.contains(a11y_sep) {
    return s
  }
  let sb = StringBuilder()
  for ch in s {
    sb.write_char(if ch == '\n' || ch == '\u{1F}' { ' ' } else { ch })
  }
  sb.to_string()
}

///|
/// A place or a size written: to a thousandth of a point, as no screen shows finer.
fn a11y_length(v : Double) -> String {
  ((v * 1000.0).round() / 1000.0).to_string()
}

///|
/// FNV-1a over the words' code units (a number of their own from frame to frame, not the runtime's hash).
fn a11y_hash(s : String) -> Int {
  let mut h = 0x811C9DC5U
  for ch in s {
    h = (h ^ ch.to_int().reinterpret_as_uint()) * 0x01000193U
  }
  h.reinterpret_as_int()
}

///|
/// As a frame has been painted: the host told what of the widgets changed when something reads them out (app.mbt
/// frame_body). Nothing while nothing reads them.
fn Ctx::a11y_after_paint(self : Ctx) -> Unit {
  let told = self.a11y
  // (whether something reads them out as the frame has it, followed: told all as it comes to read them)
  if !reads_out() {
    if told.mirror.nodes.length() > 0 {
      told.mirror.nodes.clear()
      told.mirror.holder.clear()
      told.named.clear()
    }
    return
  }
  let full = told.mirror.nodes.is_empty() || told.again || told.zoom != window_zoom_drawn.val
  told.again = false
  told.zoom = window_zoom_drawn.val
  let nodes : Array[A11yNode] = []
  let focus = match view_app.val {
    Some(tree) => self.a11y_tree_pass(tree, full, nodes)
    None => self.a11y_old_pass(nodes)
  }
  let changed = if full {
    nodes
  } else {
    nodes.filter(fn(n) { told.mirror.nodes.get(n.id) != Some(n) })
  }
  if !full && changed.is_empty() && focus == told.mirror.focus {
    return
  }
  let gone = told.mirror.apply(full, focus, changed)
  for k in gone {
    told.named.remove(k)
  }
  // (the ids of the tree's nodes gone and let go: nobody's, tree_said_id)
  match view_app.val {
    Some(tree) =>
      for k in gone {
        if (k & 0x20000000) != 0 {
          let id = (k & 0x1FFFFFFF) + -2_000_000_000
          match tree_said_ids.get(id) {
            Some(nid) if !tree.lives(nid) => {
              tree_said_ids.remove(id)
              tree_said_of.remove(nid)
            }
            _ => ()
          }
        }
      }
    None => ()
  }
  told.passes = told.passes + 1
  h_a11y_tree(a11y_update_text(full, focus, changed))
}

///|
/// What the window says where it is all an old view (no window's tree): all of it, each node in `out`, the view's own
/// first. The number of the node with the focus (0 none).
fn Ctx::a11y_old_pass(self : Ctx, out : Array[A11yNode]) -> Int {
  let (old, _) = self.semantics_old()
  let names : A11yNames = { used: {}, seen: {} }
  let root : A11yNode = {
    id: 0,
    role: "Group",
    flags: "",
    x: 0.0,
    y: 0.0,
    w: a11y_at(self.width),
    h: a11y_at(self.height),
    label: "",
    value: "",
    description: "",
    range: None,
    actions: "",
    widget: 0,
    kids: [],
  }
  out.push(root)
  let ks = Array::makei(old.length(), fn(k) { k })
  let tops = a11y_olds(old, ks, 0, 0, (0.0, 0.0), fn(_) { false }, false, fn(k) { old[k].rect }, names, out)
  for t in tops {
    root.kids.push(t)
  }
  self.a11y_old_focus(old, out)
}

///|
/// The number of the old view's widget with the keyboard's focus among `out` (0 none).
fn Ctx::a11y_old_focus(self : Ctx, old : Array[SemNode], out : Array[A11yNode]) -> Int {
  ignore(old)
  if self.focus == 0 {
    return 0
  }
  for n in out {
    if n.widget == self.focus && n.id != 0 {
      return n.id
    }
  }
  0
}

///|
/// What the window says where it is a tree: what of the tree's changed (Tree::said_pass), each node of it found there
/// whole in `out`, with what the old views it hosts say (all of it, each pass: they are built again each frame), and the
/// view's own; `full`, all of it. The number of the node with the focus (0 none). As Ctx::semantics_spliced reads the
/// whole tree out.
fn Ctx::a11y_tree_pass(self : Ctx, tree : @view.Tree, full : Bool, out : Array[A11yNode]) -> Int {
  let told = self.a11y
  let (old, nodes_of) = self.semantics_old()
  // (each old widget's old view: its box's node, -1 the whole window, -2 what is over all of it at its root)
  let owner = nodes_of.map(fn(i) { self.said_owner(i) })
  let layer_of = nodes_of.map(fn(i) {
    let mut r = i
    while r >= 0 && r < self.count && self.nodes[r].parent > 0 {
      r = self.nodes[r].parent
    }
    if r >= 0 && r < self.count && self.nodes[r].parent == 0 { self.old_layer_stack(0, r) } else { -1 }
  })
  let tree_modal = tree.modal_stack()
  let old_modal = self.old_modal_stack()
  let names : A11yNames = { used: {}, seen: {} }
  let island_rect = fn(k : Int) {
    match self.island_now(nodes_of[k]) {
      Some((px, py, qx, qy, sc)) => {
        let (x, y, w, h) = old[k].rect
        (qx + (x - px) * sc, qy + (y - py) * sc, w * sc, h * sc)
      }
      None => old[k].rect
    }
  }
  // where node `id` of the tree is in the window, as told (as Tree::said_order says it: none drawn, 0, 0)
  let place_of = fn(id : @view.NodeId) {
    match tree.drawn_place(id) {
      Some((x, y, _, _)) => (a11y_at(x), a11y_at(y))
      None => (0.0, 0.0)
    }
  }
  // what an old view hosted in node `h` says, under node `top` (its number; `named` the nearest of use of its own's):
  // the numbers of what `top` holds of it
  let hosts = fn(h : @view.NodeId, top : Int, named : Int, top_at : (Double, Double)) {
    let mine = match old_boxes.get(h) {
      Some(_) => h.at
      None => -1
    }
    let ks : Array[Int] = []
    for k in 0..<old.length() {
      if owner[k] == mine || (old_whole.val && owner[k] == -1) {
        ks.push(k)
      }
    }
    let hide = !tree.allows(h)
    a11y_olds(old, ks, top, named, top_at, fn(_) { hide }, !tree.takes_presses(h), island_rect, names, out)
  }
  let held_by = fn(kids : Array[@view.SaidKid], top : Int, named : Int, top_at : (Double, Double)) {
    let nums : Array[Int] = []
    for kid in kids {
      match kid {
        Entry(id) => nums.push(a11y_tree_num(id))
        Hosts(h) =>
          for n in hosts(h, top, named, top_at) {
            nums.push(n)
          }
      }
    }
    nums
  }
  let pass = tree.said_pass(
    fn(id) { told.mirror.nodes.contains(a11y_tree_num(id)) },
    fn(h) {
      match old_boxes.get(h) {
        Some(b) if b >= 0 && b < self.count => self.words_in(b)
        _ => ""
      }
    },
    set=fn(w, k) { view_words_set(w, k, false) },
    under=old_modal,
    whole=full,
  )
  // the view: what the window holds, the old frame's layers over all of it among the tree's by their places in the
  // window's stack of layers (hidden under a modal layer of the tree's over them), as Ctx::semantics_spliced puts them
  match pass.root {
    Some(r) => told.root = r
    None => ()
  }
  let root : A11yNode = {
    id: 0,
    role: "Group",
    flags: "",
    x: 0.0,
    y: 0.0,
    w: a11y_at(self.width),
    h: a11y_at(self.height),
    label: "",
    value: "",
    description: "",
    range: None,
    actions: "",
    widget: 0,
    kids: [],
  }
  out.push(root)
  let put = Array::make(old.length(), false)
  let layers_under = fn(stack : Int) {
    let ks : Array[Int] = []
    for k in 0..<old.length() {
      if owner[k] == -2 && !put[k] && layer_of[k] < stack {
        put[k] = true
        ks.push(k)
      }
    }
    if ks.length() > 0 {
      for n in a11y_olds(
          old,
          ks,
          0,
          0,
          (0.0, 0.0),
          fn(k) { layer_of[k] < tree_modal },
          false,
          fn(k) { old[k].rect },
          names,
          out,
        ) {
        root.kids.push(n)
      }
    }
  }
  for one in told.root {
    let (stack, kids) = one
    if stack >= 0 {
      layers_under(stack)
    }
    for n in held_by(kids, 0, 0, (0.0, 0.0)) {
      root.kids.push(n)
    }
  }
  layers_under(2147483647)
  // what of the tree's the pass found, each after what holds it
  for e in pass.entries {
    let n = a11y_tree_num(e.id)
    let (_, holder_at, holder_named) = match e.parent {
      Some(p) => {
        let k = a11y_tree_num(p)
        (k, place_of(p), told.named.get(k).unwrap_or(k))
      }
      None => (0, (0.0, 0.0), 0)
    }
    let named = if e.said is None { holder_named } else { n }
    told.named[n] = named
    let (x, y, w, h) = e.rect
    let ax = a11y_at(x)
    let ay = a11y_at(y)
    let was = told.mirror.nodes.get(n)
    let label = match (e.label, was) {
      (Some(l), _) => a11y_clean(l)
      (None, Some(w)) => w.label
      (None, None) => ""
    }
    let kids = match (e.kids, was) {
      (Some(ks), _) => held_by(ks, n, named, (ax, ay))
      (None, Some(w)) => w.kids
      (None, None) => []
    }
    let node : A11yNode = match e.said {
      Some(s) => {
        // (what can be done to it, of what it said or would: Activate where a press does something, Focus where it can
        // take the focus)
        let actions : Array[Action] = if !e.disabled && e.presses { [Activate] } else { [] }
        if e.focus {
          actions.push(Focus)
        }
        {
          id: n,
          role: s.role.to_string(),
          flags: a11y_flags(s.check, s.expanded, s.selected, s.pressed, e.disabled, false),
          x: a11y_round(ax - holder_at.0),
          y: a11y_round(ay - holder_at.1),
          w: a11y_at(w),
          h: a11y_at(h),
          label,
          value: a11y_clean(s.value),
          description: a11y_clean(s.description),
          range: s.range,
          actions: a11y_actions(actions),
          widget: tree_said_id(e.id),
          kids,
        }
      }
      None =>
        {
          id: n,
          role: "ScrollArea",
          flags: "v",
          x: a11y_round(ax - holder_at.0),
          y: a11y_round(ay - holder_at.1),
          w: a11y_at(w),
          h: a11y_at(h),
          label: "",
          value: "",
          description: "",
          range: None,
          actions: "",
          widget: 0,
          kids,
        }
    }
    out.push(node)
  }
  // (the focus: a node of the tree's by the id it is read out by, else an old view's widget)
  if self.focus == 0 {
    return 0
  }
  match tree_said_ids.get(self.focus) {
    Some(id) => {
      let n = a11y_tree_num(id)
      if told.mirror.nodes.contains(n) || out.iter().any(fn(o) { o.id == n }) {
        n
      } else {
        0
      }
    }
    None => self.a11y_old_focus(old, out)
  }
}

///|
/// What the system's accessibility asked of a widget (a message on @hostapi.a11y_channel: `{"id": widget, "action":
/// name}`), asked of it now; `{"action": "resend"}`: all of it told again with the next frame (a host that made its
/// view again).
fn a11y_took(json : String) -> Unit {
  let v = @json.parse(json) catch { _ => return }
  guard v is Object(m) else { return }
  if m.get("action") is Some(String("resend")) {
    g().a11y.again = true
    h_frame_owed()
    return
  }
  guard (m.get("id"), m.get("action")) is (Some(Number(id, ..)), Some(String(name))) else { return }
  let action : Action? = match name {
    "activate" => Some(Activate)
    "increment" => Some(Increment)
    "decrement" => Some(Decrement)
    "expand" => Some(Expand)
    "collapse" => Some(Collapse)
    "dismiss" => Some(Dismiss)
    "focus" => Some(Focus)
    "set_text" =>
      match m.get("text") {
        Some(String(t)) => Some(SetText(t))
        _ => None
      }
    _ => None
  }
  match action {
    Some(a) => g().ask_action(id.to_int(), a)
    None => ()
  }
}

///|
/// Something reads the widgets out (a screen reader on), or not, from the next frame on.
pub fn Tester::set_a11y(self : Tester, on : Bool) -> Unit {
  host_setting_set("set_a11y")
  self.fake.a11y = on
  self.fake.wants = true
}

///|
/// What the host's accessibility has of the widgets, as the updates it was told left it (A11yMirror::lines: the lines
/// Ctx::a11y_lines writes; "" nothing yet).
pub fn Tester::a11y_said(self : Tester) -> String {
  if self.fake.a11y_told.nodes.is_empty() {
    ""
  } else {
    self.fake.a11y_told.lines()
  }
}

///|
/// The last update the host's accessibility was told (see the file's head; "" none yet).
pub fn Tester::a11y_update(self : Tester) -> String {
  self.fake.a11y_said
}

///|
/// What the host's accessibility has of the widgets, held to what is read out now, once a frame told it: where it is
/// otherwise (a change a pass did not go through), the test fails at once, with both (Tester::frame_shown_at, while
/// something reads them out).
fn Tester::hold_a11y_whole(self : Tester) -> Unit {
  if !self.fake.a11y || self.fake.a11y_held == g().a11y.passes {
    return
  }
  self.fake.a11y_held = g().a11y.passes
  self.hold_named(g().semantics_tree())
  let has = self.fake.a11y_told.lines()
  let whole = g().a11y_lines()
  if has == whole {
    return
  }
  let said = "what the host's accessibility was told is not what is read out, a frame drawn at \{self.fake.time} (mbui's src/ui/a11y.mbt: what changed not found):\n--- told\n\{has}--- read out\n\{whole}"
  @halt.saying(said)
}

///|
/// A whole number as an update writes it (0 where it is none).
fn a11y_int(s : String) -> Int {
  let mut n = 0
  let mut neg = false
  for i, ch in s.to_array() {
    if i == 0 && ch == '-' {
      neg = true
    } else if ch >= '0' && ch <= '9' {
      n = n * 10 + (ch.to_int() - '0'.to_int())
    } else {
      return 0
    }
  }
  if neg {
    -n
  } else {
    n
  }
}

///|
/// A place, a size or a range's number as an update writes it (Double's own: sign, digits, a point, digits, an
/// exponent; 0 where it is none).
fn a11y_real(s : String) -> Double {
  let chars = s.to_array()
  let mut i = 0
  let neg = chars.length() > 0 && chars[0] == '-'
  if neg {
    i = 1
  }
  let mut v = 0.0
  while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
    v = v * 10.0 + (chars[i].to_int() - '0'.to_int()).to_double()
    i = i + 1
  }
  if i < chars.length() && chars[i] == '.' {
    i = i + 1
    let mut scale = 0.1
    while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
      v = v + (chars[i].to_int() - '0'.to_int()).to_double() * scale
      scale = scale / 10.0
      i = i + 1
    }
  }
  if i < chars.length() && (chars[i] == 'e' || chars[i] == 'E') {
    let e = a11y_int(String::from_array(chars[i + 1:].to_owned()).replace(old="+", new=""))
    for _ in 0..<(if e < 0 { -e } else { e }) {
      v = if e < 0 { v / 10.0 } else { v * 10.0 }
    }
  }
  if neg {
    -v
  } else {
    v
  }
}

///|
/// Whether `s` is one a screen reader cannot name: read out, of the window's tree (an old view's not held to it: the
/// user, 2026-11-09), something to do with it (pressed, a step, words put in it) and no name, its own nor its words.
fn sem_unnamed(s : SemNode) -> Bool {
  !s.hidden &&
  tree_said_ids.contains(s.id) &&
  s.label.iter().all(fn(c) { c == ' ' }) &&
  s.actions.iter().any(fn(a) { a is (Activate | SetText(_) | Increment | Decrement) })
}

///|
/// The rule that what can be done is named (a button, a field, a slider: a screen reader says what it is), held on the
/// tree as a test reads it (Tester::semantics: every query by role and name) and as a host that reads it is told
/// (Tester::hold_a11y_whole): one of the window's tree's that breaks it fails the test at once, with where it is.
fn Tester::hold_named(self : Tester, tree : Array[SemNode]) -> Unit {
  let bad = tree.filter(sem_unnamed)
  if bad.is_empty() {
    return
  }
  let said = "what can be done is named (mbui's src/ui/a11y.mbt, sem_unnamed), on a frame drawn at \{self.fake.time}:\n" +
    bad.map(fn(s) { "  \{s.describe()} at \{Repr(s.rect)}, actions \{Repr(s.actions)}" }).join("\n")
  @halt.saying(said)
}

///|
/// What the host's accessibility has of the widgets as a screen reader finds them, a node a line indented by how deep it
/// is, as Ctx::semantics_dump writes the tree (its role, its name quoted, its value and state; those of no use of their
/// own, flags v, left out): what a test asserts a screen reader is told.
pub fn Tester::a11y_dump(self : Tester) -> String {
  self.fake.a11y_told.dump()
}

///|
/// What a host has, as Tester::a11y_dump says it.
fn A11yMirror::dump(self : A11yMirror) -> String {
  let sb = StringBuilder()
  fn put(k : Int, depth : Int) -> Unit {
    guard self.nodes.get(k) is Some(n) else { return }
    let own = k != 0 && !n.flags.contains("v")
    if own {
      for _ in 0..<depth {
        sb.write_string("  ")
      }
      sb.write_string(n.role)
      if n.label != "" {
        sb.write_string(" \{n.label.escape()}")
      }
      if n.value != "" {
        sb.write_string(" value=\{n.value.escape()}")
      }
      let f = n.flags
      if f.contains("c") {
        sb.write_string(if f.contains("C") { " checked" } else if f.contains("M") { " mixed" } else { " unchecked" })
      }
      if f.contains("p") {
        sb.write_string(if f.contains("P") { " pressed" } else { " not-pressed" })
      }
      if f.contains("e") {
        sb.write_string(if f.contains("E") { " expanded" } else { " collapsed" })
      }
      if f.contains("s") {
        sb.write_string(" selected")
      }
      match n.range {
        Some((lo, v, hi)) => sb.write_string(" range=\{lo}..\{hi}@\{v}")
        None => ()
      }
      if f.contains("d") {
        sb.write_string(" disabled")
      }
      if f.contains("m") {
        sb.write_string(" modal")
      }
      if self.focus == k {
        sb.write_string(" focused")
      }
      sb.write_char('\n')
    }
    for c in n.kids {
      put(c, if own { depth + 1 } else { depth })
    }
  }

  put(0, 0)
  sb.to_string()
}
