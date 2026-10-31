// What the widgets are, for whoever cannot see them (a screen reader) and for tests that find them as it would
// (Compose's semantics tree, the DOM's accessibility tree that Testing Library queries): each widget built says of its
// node its role, its label, its state (checked, expanded, selected, pressed, disabled, its value) and what can be done
// to it. The tree is that of the nodes: a widget's parent in it is the nearest node above it that said something.
// Words built under no widget that names itself are nodes of their own (role Text); a box that takes presses (an `id`,
// `taps`) and says nothing is a Button named by its `label` or the words in it, as Compose's clickable is, unless it
// covers nearly the whole window (a scrim, a page's ground). A part can be hidden from it
// (Ctx::hidden_from_semantics: what only decorates; one its row left out); a modal over the page hides what is under it. An action asked of
// a node (by a test, later by the host's VoiceOver, TalkBack or UI Automation) comes to its widget the next frame as
// though it were done by hand (Ctx::interact: Activate is a click). The tree is made when asked
// (Ctx::semantics_tree): the old views' from what the last frame built; the window's tree's nodes as they say they are
// now, what was told since that frame said (@view.Tree::said_order), no frame waited for.

///|
/// What a widget said of its node this frame.
struct Sem {
  node : Int
  id : Int
  role : Role
  label : String
  description : String
  value : String
  check : Check?
  expanded : Bool?
  selected : Bool?
  pressed : Bool?
  disabled : Bool
  modal : Bool
  range : (Double, Double, Double)?
  actions : Array[Action]
  hidden : Bool
}

///|
/// A node of the tree (Ctx::semantics_tree): what its widget said, where it is (x, y, w, h, as laid out), whether it
/// has the keyboard's focus, whether it is hidden (under a modal, in a hidden part: not read out, not found by
/// Tester::get), its parent's index in the tree (-1 none) and how deep it is.
pub struct SemNode {
  id : Int
  role : Role
  label : String
  description : String
  value : String
  check : Check?
  expanded : Bool?
  selected : Bool?
  pressed : Bool?
  disabled : Bool
  modal : Bool
  /// a range's least, where it is, its most (a slider's, a progress bar's)
  range : (Double, Double, Double)?
  actions : Array[Action]
  rect : (Double, Double, Double, Double)
  focused : Bool
  hidden : Bool
  parent : Int
  depth : Int
} derive(Show)

///|
/// Node `node` (as Ctx::box returns it) is a widget of `role`: its `label` (none: the words built in it, as a button
/// is named by them), what describes it more, its value as words, its state, what can be done to it. `id` is the
/// widget's (what its actions are asked of; 0 none).
pub fn Ctx::semantics(
  self : Ctx,
  node : Int,
  role : Role,
  id? : Int = 0,
  label? : String = "",
  description? : String = "",
  value? : String = "",
  check? : Check,
  expanded? : Bool,
  selected? : Bool,
  pressed? : Bool,
  disabled? : Bool = false,
  modal? : Bool = false,
  range? : (Double, Double, Double),
  actions? : Array[Action] = [],
) -> Unit {
  if node < 0 || node >= self.count {
    return
  }
  // (held by its node, docs/retained.md the way there's 1: the frame's `sems` are found from the nodes, sems_found)
  self.nodes[node].sem = Some({
    node,
    id,
    role,
    label,
    description,
    value,
    check,
    expanded,
    selected,
    pressed,
    disabled,
    modal,
    range,
    actions,
    hidden: self.sem_hide > 0,
  })
}

///|
/// `body` built hidden from the tree (ARIA's aria-hidden): what only decorates, what an accessible icon's label
/// stands for.
pub fn Ctx::hidden_from_semantics(self : Ctx, body : () -> Unit) -> Unit {
  // (what is made in it is marked so: Node's `sem_hid`)
  self.sem_hide = self.sem_hide + 1
  body()
  self.sem_hide = self.sem_hide - 1
}

///|
/// What the nodes say they are in the tree read out (Node's `sem`), in the order they were made: the frame's `sems`.
fn Ctx::sems_found(self : Ctx) -> Unit {
  self.sems.clear()
  for i in 0..<self.count {
    match self.nodes[i].sem {
      Some(s) => self.sems.push({ ..s, node: i })
      None => ()
    }
  }
}

///|
/// Words read out and found by tests but not seen (Radix's VisuallyHidden): a node of no size, and `role` (Text) with
/// `label` in the tree.
pub fn Ctx::visually_hidden(self : Ctx, label : String, role? : Role = Text) -> Unit {
  let i = self.box(w=Px(0.0), h=Px(0.0), fn() {  })
  self.semantics(i, role, label~)
}

///|
/// `action` asked of the widget `id` (by a test, by the host's accessibility): its widget sees it the next frame.
pub fn Ctx::ask_action(self : Ctx, id : Int, action : Action) -> Unit {
  // (where the window is a tree: one event of the tree's at this moment, what was due by then done first; asked inside
  // one already, that one's, nothing done ahead of it: what it is asked of found and judged as things are then)
  match view_app.val {
    Some(tree) => tree.event(view_moment(), fn() { self.asked(id, action) })
    None => self.asked(id, action)
  }
}

///|
/// `action` asked of `id`, as things are now (Ctx::ask_action).
fn Ctx::asked(self : Ctx, id : Int, action : Action) -> Unit {
  // (a node of the window's tree's: its own, as a press on it is)
  if tree_said_action(id, action) {
    return
  }
  // (an old view's widget: none where the tree keeps that old view from being read out or acted on now: a modal layer
  // of its over it, what holds it hidden, taking no presses, leaving: Tree::acts_on)
  if !old_said_allowed(self, id) {
    return
  }
  self.asked_actions.push((id, action))
  // (a reader's Activate a click, its moment the one it is asked at: Ctx::clicked_at)
  if action == Activate {
    self.click_times[id] = self.moment()
  }
  // an input, as a tap is: its frame and the one after, what reads what is asked built again (hand.mbt)
  hand_event()
  input_came()
}

///|
/// Whether `action` was asked of `id` for this frame.
pub fn Ctx::action_asked(self : Ctx, id : Int, action : Action) -> Bool {
  // (read by member: what nothing was asked of is not built again for what was asked of another)
  hand.asked.has(id) |> ignore
  for a in self.actions {
    if a.0 == id && a.1 == action {
      return true
    }
  }
  false
}

///|
/// The words asked to be put in `id` this frame in place of what it holds (Action::SetText), the last asked.
pub fn Ctx::text_asked(self : Ctx, id : Int) -> String? {
  hand.asked.has(id) |> ignore
  let mut got = None
  for a in self.actions {
    if a.0 == id && a.1 is SetText(s) {
      got = Some(s)
    }
  }
  got
}

///|
/// The tree as it is read now (see the file's head: the old views' nodes as the last frame built them, the window's
/// tree's as they say they are now), its nodes in the tree's order (a parent before what it
/// holds, what it holds in the order it is laid out: a list's rows top to bottom, though it builds the one it stands
/// at first), what no frame's tree holds left out (a row built again in its place).
pub fn Ctx::semantics_tree(self : Ctx) -> Array[SemNode] {
  match view_app.val {
    Some(tree) => self.semantics_spliced(tree)
    None => self.semantics_old().0
  }
}

///|
/// The old views' tree (Ctx::semantics_tree, with no window's tree), and the node each of its is said of.
fn Ctx::semantics_old(self : Ctx) -> (Array[SemNode], Array[Int]) {
  let count = self.count
  // by node: what said something of it (the last to say wins), -1 none
  let said = Array::make(count, -1)
  for k, s in self.sems {
    if s.node >= 0 && s.node < count {
      said[s.node] = k
    }
  }
  // the topmost modal layer: what is not in it is hidden
  let modal_node = self.modal_node()
  let out : Array[SemNode] = []
  // by node: its index in `out`, -1 none
  let at = Array::make(count, -1)
  // by node: the nearest node above it in `out` (or itself), -1 none; whether it is hidden; whether it is named
  let up = Array::make(count, -1)
  let hid = Array::make(count, false)
  let named = Array::make(count, false)
  let in_modal = Array::make(count, modal_node < 0)
  // the layers opened in the modal one (a submenu of a menu): theirs too, though laid over the window apart from it
  let over_modal : Array[Int] = []
  if modal_node >= 0 {
    let mut modal_id = 0
    for l in self.last_layers {
      if l.node == modal_node {
        modal_id = l.id
      }
    }
    for l in self.last_layers {
      if l.id != modal_id && !l.inert && self.layer_within(l.id, modal_id) {
        over_modal.push(l.node)
      }
    }
  }
  let nodes_of : Array[Int] = []
  for i in self.tree_order() {
    let said_before = out.length()
    let n = self.nodes[i]
    let p = n.parent
    let parent_out = if p >= 0 { up[p] } else { -1 }
    // (a part its row left out, Ctx::box `drop`: laid out nowhere, not read out either)
    let left = p >= 0 && n.fl.left_out() && self.nodes[p].fl.style.fits
    // (and what a page's bones are made of, wherever it was built: bones.mbt)
    let parent_hid = (p >= 0 && hid[p]) || n.sem_hid || left || n.bones != 0L
    let parent_named = p >= 0 && named[p]
    if p >= 0 && in_modal[p] {
      in_modal[i] = true
    }
    if i == modal_node || over_modal.contains(i) {
      in_modal[i] = true
    }
    up[i] = parent_out
    hid[i] = parent_hid
    named[i] = parent_named
    let k = said[i]
    if k >= 0 {
      let s = self.sems[k]
      let label = if s.label == "" { self.words_in(i) } else { s.label }
      // (and what an old view a modal layer of the window's tree keeps from input built: not read out either,
      // view_host.mbt's island_allows)
      let hidden = parent_hid || s.hidden || !in_modal[i] || !island_allows(n.island)
      let depth = if parent_out >= 0 { out[parent_out].depth + 1 } else { 0 }
      out.push({
        id: s.id,
        role: s.role,
        label,
        description: s.description,
        value: s.value,
        check: s.check,
        expanded: s.expanded,
        selected: s.selected,
        pressed: s.pressed,
        disabled: s.disabled,
        modal: s.modal,
        range: s.range,
        actions: s.actions,
        rect: (n.x, n.y, n.fw, n.fh),
        focused: s.id != 0 && s.id == self.focus,
        hidden,
        parent: parent_out,
        depth,
      })
      at[i] = out.length() - 1
      up[i] = at[i]
      hid[i] = hidden
      named[i] = label != "" && s.role != Group && s.role != Dialog && s.role != AlertDialog &&
        s.role != Menu && s.role != Toolbar && s.role != RadioGroup && s.role != TabList &&
        s.role != TabPanel && s.role != Region && s.role != Form && s.role != MenuBar &&
        s.role != Listbox && s.role != ScrollArea && s.role != Navigation
    } else if self.press_target(i) {
      // a box pressed and saying nothing: a button, named by its label or its own words (not a widget's in it)
      let label = if n.label != "" { n.label } else { self.own_words(i) }
      let hidden = parent_hid || !in_modal[i]
      let depth = if parent_out >= 0 { out[parent_out].depth + 1 } else { 0 }
      out.push({
        id: n.id,
        role: Button,
        label,
        description: "",
        value: "",
        check: None,
        expanded: None,
        selected: None,
        pressed: None,
        disabled: false,
        modal: false,
        range: None,
        actions: [Activate],
        rect: (n.x, n.y, n.fw, n.fh),
        focused: n.id == self.focus,
        hidden,
        parent: parent_out,
        depth,
      })
      at[i] = out.length() - 1
      up[i] = at[i]
      hid[i] = hidden
      named[i] = label != ""
    } else if n.kind == kind_box && n.label != "" && !parent_named {
      // a box that says what it is called and takes no presses (Compose's contentDescription on what is not
      // clickable): words read for it, an image's where it holds none
      let hidden = parent_hid || !in_modal[i]
      let depth = if parent_out >= 0 { out[parent_out].depth + 1 } else { 0 }
      out.push({
        id: 0,
        role: if self.words_in(i) == "" { Image } else { Text },
        label: n.label,
        description: "",
        value: "",
        check: None,
        expanded: None,
        selected: None,
        pressed: None,
        disabled: false,
        modal: false,
        range: None,
        actions: [],
        rect: (n.x, n.y, n.fw, n.fh),
        focused: false,
        hidden,
        parent: parent_out,
        depth,
      })
      at[i] = out.length() - 1
      up[i] = at[i]
      hid[i] = hidden
      named[i] = true
    } else if (n.kind == kind_text || n.kind == kind_rich) && !parent_named && n.text != "" {
      let hidden = parent_hid || !in_modal[i]
      let depth = if parent_out >= 0 { out[parent_out].depth + 1 } else { 0 }
      out.push({
        id: 0,
        role: Text,
        label: n.text,
        description: "",
        value: "",
        check: None,
        expanded: None,
        selected: None,
        pressed: None,
        disabled: false,
        modal: false,
        range: None,
        actions: [],
        rect: (n.x, n.y, n.fw, n.fh),
        focused: false,
        hidden,
        parent: parent_out,
        depth,
      })
    }
    if out.length() > said_before {
      nodes_of.push(i)
    }
  }
  (out, nodes_of)
}

///|
/// The nodes the last frame built in its tree's order: each root (the page, each layer) as built, each node before what
/// it holds, what a node holds in its order (Node's `first`, `next`).
fn Ctx::tree_order(self : Ctx) -> Array[Int] {
  let order = []
  let stack = []
  let kids = []
  for r in 0..<self.count {
    if self.nodes[r].parent >= 0 {
      continue
    }
    stack.push(r)
    while stack.pop() is Some(i) {
      order.push(i)
      kids.clear()
      let mut ch = self.nodes[i].first
      while ch >= 0 {
        kids.push(ch)
        ch = self.nodes[ch].next
      }
      for k = kids.length() - 1; k >= 0; k = k - 1 {
        stack.push(kids[k])
      }
    }
  }
  order
}

///|
/// Whether node `i` is a box that takes presses and says nothing of itself (a Button in the tree): an id it takes
/// presses by, no widget's word of it, and less than nearly the whole window (not a scrim, nor a page's ground).
fn Ctx::press_target(self : Ctx, i : Int) -> Bool {
  let n = self.nodes[i]
  if n.kind != kind_box || n.id == 0 || !n.hit {
    return false
  }
  // (nor one whose id a widget said itself by on another node: the widget is the node)
  for s in self.sems {
    if s.node == i || s.id == n.id {
      return false
    }
  }
  n.fw * n.fh < 0.9 * self.width * self.height
}

///|
/// The words built in node `i` that are no widget's (none in what says it is something, nor in a button of its own in
/// it), joined by spaces: what names a box pressed that says nothing.
fn Ctx::own_words(self : Ctx, i : Int) -> String {
  let sb = StringBuilder()
  self.collect_own_words(i, sb)
  sb.to_string()
}

///|
fn Ctx::collect_own_words(self : Ctx, i : Int, sb : StringBuilder) -> Unit {
  let n = self.nodes[i]
  if (n.kind == kind_text || n.kind == kind_rich) && n.text != "" {
    if sb.to_string().length() > 0 {
      sb.write_char(' ')
    }
    sb.write_string(n.text)
  }
  let mut ch = n.first
  while ch >= 0 {
    // (as Compose merges what a clickable holds: a widget's words that takes nothing itself, a box's label, words;
    // not what is pressed on its own)
    let said = self.sems.filter(fn(s) { s.node == ch })
    let words = if self.press_target(ch) {
      ""
    } else if said.length() > 0 {
      let s = said[said.length() - 1]
      if s.hidden || s.id != 0 || s.actions.length() > 0 {
        ""
      } else if s.label != "" {
        s.label
      } else {
        self.words_in(ch)
      }
    } else if self.nodes[ch].kind == kind_box && self.nodes[ch].label != "" {
      self.nodes[ch].label
    } else {
      self.collect_own_words(ch, sb)
      ""
    }
    if words != "" {
      if sb.to_string().length() > 0 {
        sb.write_char(' ')
      }
      sb.write_string(words)
    }
    ch = self.nodes[ch].next
  }
}

///|
/// The words built in node `i`, its texts' joined by spaces (a button's name when it says none).
fn Ctx::words_in(self : Ctx, i : Int) -> String {
  let sb = StringBuilder()
  self.collect_words(i, sb)
  sb.to_string()
}

///|
fn Ctx::collect_words(self : Ctx, i : Int, sb : StringBuilder) -> Unit {
  let n = self.nodes[i]
  if (n.kind == kind_text || n.kind == kind_rich) && n.text != "" {
    if sb.to_string().length() > 0 {
      sb.write_char(' ')
    }
    sb.write_string(n.text)
  }
  let mut ch = n.first
  while ch >= 0 {
    // what said it is hidden, or names itself, is not part of the name
    let mut skip = false
    for s in self.sems {
      if s.node == ch && (s.hidden || s.label != "") {
        skip = true
        if !s.hidden {
          if sb.to_string().length() > 0 {
            sb.write_char(' ')
          }
          sb.write_string(s.label)
        }
      }
    }
    if !skip {
      self.collect_words(ch, sb)
    }
    ch = self.nodes[ch].next
  }
}

///|
/// The tree as text, a node a line indented by its depth: its role, its label quoted, its state; hidden nodes left
/// out (a test's snapshot of what a screen reader finds).
pub fn Ctx::semantics_dump(self : Ctx) -> String {
  let sb = StringBuilder()
  for s in self.semantics_tree() {
    if s.hidden {
      continue
    }
    for _ in 0..<s.depth {
      sb.write_string("  ")
    }
    sb.write_string(s.describe())
    sb.write_char('\n')
  }
  sb.to_string()
}

///|
/// A node in a line: its role, its label quoted, its state.
pub fn SemNode::describe(self : SemNode) -> String {
  let sb = StringBuilder()
  sb.write_string(self.role.to_string())
  if self.label != "" {
    sb.write_string(" \{self.label.escape()}")
  }
  if self.value != "" {
    sb.write_string(" value=\{self.value.escape()}")
  }
  match self.check {
    Some(Off) => sb.write_string(" unchecked")
    Some(On) => sb.write_string(" checked")
    Some(Mixed) => sb.write_string(" mixed")
    None => ()
  }
  match self.pressed {
    Some(true) => sb.write_string(" pressed")
    Some(false) => sb.write_string(" not-pressed")
    None => ()
  }
  match self.expanded {
    Some(true) => sb.write_string(" expanded")
    Some(false) => sb.write_string(" collapsed")
    None => ()
  }
  match self.selected {
    Some(true) => sb.write_string(" selected")
    _ => ()
  }
  match self.range {
    Some((lo, v, hi)) => sb.write_string(" range=\{lo}..\{hi}@\{v}")
    None => ()
  }
  if self.disabled {
    sb.write_string(" disabled")
  }
  if self.modal {
    sb.write_string(" modal")
  }
  if self.focused {
    sb.write_string(" focused")
  }
  sb.to_string()
}
