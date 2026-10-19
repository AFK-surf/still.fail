// What the widgets are, for whoever cannot see them (a screen reader) and for tests that find them as it would
// (Compose's semantics tree, the DOM's accessibility tree that Testing Library queries): each widget built says of its
// node its role, its label, its state (checked, expanded, selected, pressed, disabled, its value) and what can be done
// to it. The tree is that of the nodes: a widget's parent in it is the nearest node above it that said something.
// Words built under no widget that names itself are nodes of their own (role Text). A part can be hidden from it
// (Ctx::hidden_from_semantics: what only decorates); a modal over the page hides what is under it. An action asked of
// a node (by a test, later by the host's VoiceOver, TalkBack or UI Automation) comes to its widget the next frame as
// though it were done by hand (Ctx::interact: Activate is a click). The tree is made when asked
// (Ctx::semantics_tree), from what the last frame built.

///|
/// What a widget is (ARIA's roles, those the components use).
pub(all) enum Role {
  Text
  Group
  Button
  Link
  Checkbox
  Switch
  Radio
  RadioGroup
  Slider
  ProgressBar
  Tab
  TabList
  TabPanel
  Dialog
  AlertDialog
  Tooltip
  Menu
  MenuBar
  MenuItem
  MenuItemCheckbox
  MenuItemRadio
  Listbox
  Option
  Combobox
  Toolbar
  Separator
  Image
  TextField
  Status
  Region
  Navigation
  Form
  Heading
  ScrollArea
} derive(Eq, Show, Debug)

///|
/// A checkbox's state (and a menu's checkbox item's): off, on, or neither (some of what it stands for is on).
pub(all) enum Check {
  Off
  On
  Mixed
} derive(Eq, Show, Debug)

///|
/// What can be done to a widget: pressed (a click, a tap), moved up or down a step (a slider), opened or closed,
/// sent away (a dialog, a menu: Escape), given the keyboard's focus.
pub(all) enum Action {
  Activate
  Increment
  Decrement
  Expand
  Collapse
  Dismiss
  Focus
} derive(Eq, Show, Debug)

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
  self.sems.push({
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
  let from = self.count
  self.sem_hide = self.sem_hide + 1
  body()
  self.sem_hide = self.sem_hide - 1
  self.sem_hidden.push((from, self.count))
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
  self.asked_actions.push((id, action))
  self.wants_frame = true
  h_request_frame()
}

///|
/// Whether `action` was asked of `id` for this frame.
pub fn Ctx::action_asked(self : Ctx, id : Int, action : Action) -> Bool {
  for a in self.actions {
    if a.0 == id && a.1 == action {
      return true
    }
  }
  false
}

///|
/// The tree of the last frame built (see the file's head), its nodes in the order they were built (a parent before
/// what it holds).
pub fn Ctx::semantics_tree(self : Ctx) -> Array[SemNode] {
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
  // the nodes built in hidden parts
  let hidden_node = Array::make(count, false)
  for r in self.sem_hidden {
    for i in r.0..<imin(r.1, count) {
      hidden_node[i] = true
    }
  }
  for i in 0..<count {
    let n = self.nodes[i]
    let p = n.parent
    let parent_out = if p >= 0 { up[p] } else { -1 }
    let parent_hid = (p >= 0 && hid[p]) || hidden_node[i]
    let parent_named = p >= 0 && named[p]
    if p >= 0 && in_modal[p] {
      in_modal[i] = true
    }
    if i == modal_node {
      in_modal[i] = true
    }
    up[i] = parent_out
    hid[i] = parent_hid
    named[i] = parent_named
    let k = said[i]
    if k >= 0 {
      let s = self.sems[k]
      let label = if s.label == "" { self.words_in(i) } else { s.label }
      let hidden = parent_hid || s.hidden || !in_modal[i]
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
  }
  out
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
