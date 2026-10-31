// What a node is to whoever cannot see it (a screen reader) and to tests that find it as it would: its role, its
// state, what can be done to it (ARIA's terms; ui's semantics.mbt the old views', View::says the window's tree's).

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
  /// words put in a field in place of what it held, as a screen reader writes them (UI Automation's SetValue,
  /// TalkBack's set text); among what a widget says it takes, its words are none's (SetText(""))
  SetText(String)
} derive(Eq, Show, Debug)

///|
/// What a node of the window's tree says it is (View::says): its role, its label (none: the words it holds), what
/// describes it more, its value as words (and as a number in a range: a progress bar's, a slider's), its state, what can
/// be done to it (Activate where it is pressed: its on_press,
/// as a press there runs it). Whether it is disabled is what its presses say (View::presses), not said here.
pub(all) struct Said {
  role : Role
  label : String
  description : String
  value : String
  /// its least, where it is, its most (None: no number of a range)
  range : (Double, Double, Double)?
  check : Check?
  expanded : Bool?
  selected : Bool?
  pressed : Bool?
  actions : Array[Action]
} derive(Eq, Show, Debug)

///|
/// A node of `role`, what else it says as given.
pub fn said(
  role : Role,
  label? : String = "",
  description? : String = "",
  value? : String = "",
  range? : (Double, Double, Double),
  check? : Check,
  expanded? : Bool,
  selected? : Bool,
  pressed? : Bool,
  actions? : Array[Action] = [],
) -> Said {
  { role, label, description, value, range, check, expanded, selected, pressed, actions }
}

///|
/// A node of the window's tree as it is read out (Tree::said_order): which, what it said (None: it said nothing, a node
/// hosting an old view, read out as its own say), whether it hosts one, whether it takes input now (a modal layer over
/// it says not: Tree::allows), whether its presses are off (View::presses: disabled, read out so), where it is drawn
/// (the window's terms), the nearest of these that holds it (its index; -1 none) and how deep it is.
pub(all) struct SaidNode {
  id : NodeId
  said : Said?
  hosted : Bool
  allowed : Bool
  /// kept from what is read out (View::hides, its own or what holds it's)
  hidden : Bool
  disabled : Bool
  rect : (Double, Double, Double, Double)
  parent : Int
  depth : Int
}

///|
/// What it says it is, as it changes (None: nothing): what is read out of it, nothing else of it done again for it.
pub fn View::says(self : View, said : Live[Said?]) -> View {
  self.bind(17, said, Said, fn(s) { self.tree.nodes[self.at].said = s })
  self
}

///|
/// The nodes that say what they are, and those hosting an old view, in the tree's order (each before what it holds, what
/// it holds in its order): what is read out of the window's tree (ui's semantics_tree splices each old
/// view's in at its node), as it is now (what was told since the last frame said, no frame waited for).
pub fn Tree::said_order(self : Tree) -> Array[SaidNode] {
  // (what each says as of now: what the change under way set so far pulled into it, as where things are is for an
  // event, Tree::laid_now; no frame drawn for it)
  @signals.untracked(fn() { self.pull() })
  let out : Array[SaidNode] = []
  fn walk(at : Int, parent : Int, depth : Int, hid : Bool) -> Unit {
    let n = self.nodes[at]
    if !n.live {
      return
    }
    let hid = hid || n.said_hidden
    let id = { at, gen: n.gen }
    let mut up = parent
    let mut d = depth
    if n.said is Some(_) || n.hosted {
      let rect = match self.drawn_of(id) {
        Some(dr) => (dr.x, dr.y, dr.w, dr.h)
        None => (0.0, 0.0, 0.0, 0.0)
      }
      out.push({
        id,
        said: n.said,
        hosted: n.hosted,
        allowed: self.allows(id),
        hidden: hid,
        disabled: self.pressless_at(at),
        rect,
        parent,
        depth,
      })
      up = out.length() - 1
      d = depth + 1
    }
    for k in n.kids {
      walk(k, up, d, hid)
    }
  }

  if self.nodes.length() > 0 {
    walk(0, -1, 0, false)
  }
  out
}

///|
/// It and all it holds kept from what is read out while `hidden` holds (ARIA's aria-hidden: what only decorates, what is
/// shown and not there to be used), whatever it says; drawn and pressed as ever.
pub fn View::hides(self : View, hidden : Live[Bool]) -> View {
  self.bind(18, hidden, Said, fn(h) { self.tree.nodes[self.at].said_hidden = h })
  self
}
