// What a node is to whoever cannot see it (a screen reader) and to tests that find it as it would: its role, its
// state, what can be done to it (ARIA's terms; ui's semantics.mbt the old views', View::says the window's tree's).

///|
/// What a widget is (ARIA's roles, those the components use).
#derive(Eq, Debug)
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
}

///|
/// By its name, as tests and the said tree's text write a node's role: what `derive(Show)` wrote.
pub impl Show for Role with output(self, logger) {
  logger.write_string(
    match self {
      Text => "Text"
      Group => "Group"
      Button => "Button"
      Link => "Link"
      Checkbox => "Checkbox"
      Switch => "Switch"
      Radio => "Radio"
      RadioGroup => "RadioGroup"
      Slider => "Slider"
      ProgressBar => "ProgressBar"
      Tab => "Tab"
      TabList => "TabList"
      TabPanel => "TabPanel"
      Dialog => "Dialog"
      AlertDialog => "AlertDialog"
      Tooltip => "Tooltip"
      Menu => "Menu"
      MenuBar => "MenuBar"
      MenuItem => "MenuItem"
      MenuItemCheckbox => "MenuItemCheckbox"
      MenuItemRadio => "MenuItemRadio"
      Listbox => "Listbox"
      Option => "Option"
      Combobox => "Combobox"
      Toolbar => "Toolbar"
      Separator => "Separator"
      Image => "Image"
      TextField => "TextField"
      Status => "Status"
      Region => "Region"
      Navigation => "Navigation"
      Form => "Form"
      Heading => "Heading"
      ScrollArea => "ScrollArea"
    },
  )
}

///|
/// A checkbox's state (and a menu's checkbox item's): off, on, or neither (some of what it stands for is on).
#derive(Eq, Debug)
pub(all) enum Check {
  Off
  On
  Mixed
}

///|
/// By its name, as tests and the said tree's text write a checkbox's state: what `derive(Show)` wrote.
pub impl Show for Check with output(self, logger) {
  logger.write_string(
    match self {
      Off => "Off"
      On => "On"
      Mixed => "Mixed"
    },
  )
}

///|
/// What can be done to a widget: pressed (a click, a tap), moved up or down a step (a slider), opened or closed,
/// sent away (a dialog, a menu: Escape), given the keyboard's focus.
#derive(Eq, Debug)
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
}

///|
/// What a node of the window's tree says it is (View::says): its role, its label (none: the words it holds), what
/// describes it more, its value as words (and as a number in a range: a progress bar's, a slider's), its state, what can
/// be done to it (Activate where it is pressed: its on_press,
/// as a press there runs it). Whether it is disabled is what its presses say (View::presses), not said here.
#derive(Eq, Debug)
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
}

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
#callsite(autofill(loc))
pub fn View::says(self : View, said : Live[Said?], loc~ : SourceLoc) -> View {
  self.bind(loc~, Says, said, Said, fn(s) { self.tree.nodes[self.at].said = s })
  self
}

///|
/// What node `id` is called as it says (View::says: its label; "" none, or no live node).
pub fn Tree::said_label(self : Tree, id : NodeId) -> String {
  if self.alive_id(id) {
    match self.nodes[id.at].said {
      Some(s) => s.label
      None => ""
    }
  } else {
    ""
  }
}

///|
/// What node `id` says it is (View::says; None: nothing, or no live node).
pub fn Tree::said_of(self : Tree, id : NodeId) -> Said? {
  if self.alive_id(id) {
    self.nodes[id.at].said
  } else {
    None
  }
}

///|
/// Whether node `id` says it is a picture (View::says: Role Image; no live node, not).
pub fn Tree::says_picture(self : Tree, id : NodeId) -> Bool {
  self.alive_id(id) && self.nodes[id.at].said is Some({ role: Image, .. })
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
    // (left out of its row: none of it read out, Tree::out_at)
    if !n.live || n.out {
      return
    }
    // (in its bones: none of it there yet, View::bones)
    let hid = hid || n.said_hidden || n.bones != 0L
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
    for k in self.kids_in_order(at) {
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
#callsite(autofill(loc))
pub fn View::hides(self : View, hidden : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, Hides, hidden, Said, fn(h) { self.tree.nodes[self.at].said_hidden = h })
  self
}

///|
/// What node `id` is called where it says no label of its own (a screen reader's name from what it holds): its own words,
/// then what it holds's in order, each one that says a label of its own by that label alone (none of what is in it), one
/// kept from what is read out (View::hides) by nothing, one hosting an old view by what `hosted` says that old view is
/// called the same way, the rest by the same, all one line; as ui's old frame calls a box with no label of its own
/// (Ctx::words_in). Each node's words as `set` sets them for its look (the host's: on one line where they do not wrap,
/// as they are drawn and an old view's are).
pub fn Tree::words_within(
  self : Tree,
  id : NodeId,
  hosted : (NodeId) -> String,
  set? : (String, WordsLook) -> String = fn(w, _) { w },
) -> String {
  guard self.alive_id(id) else { return "" }
  let sb = StringBuilder()
  let put = fn(s : String) {
    if s != "" {
      if sb.to_string().length() > 0 {
        sb.write_char(' ')
      }
      sb.write_string(s)
    }
  }
  fn walk(at : Int) -> Unit {
    let n = self.nodes[at]
    let me = { at, gen: n.gen }
    match self.drawn_of(me) {
      // (on their lines as written where they keep their breaks, View::words_breaks: as they are, `set` none of theirs)
      Some(d) => put(if d.words_breaks { d.words } else { set(d.words, d.words_look) })
      None => ()
    }
    for k in self.kids_in_order(at) {
      let kn = self.nodes[k]
      if !kn.live || kn.out || kn.said_hidden || kn.bones != 0L {
        continue
      }
      match kn.said {
        Some(s) if s.label != "" => put(s.label)
        _ =>
          if kn.hosted {
            put(hosted({ at: k, gen: kn.gen }))
          } else {
            walk(k)
          }
      }
    }
  }

  walk(id.at)
  sb.to_string()
}

///|
/// What one of what is read out holds, in its order (Tree::said_pass): a node read out, or one hosting an old view (what
/// that old view says read out in its place, then what of the tree it holds).
#derive(Eq, Debug)
pub(all) enum SaidKid {
  Entry(NodeId)
  Hosts(NodeId)
}

///|
/// A node read out as a pass found it (Tree::said_pass): what it says (None: it says nothing, the node what a column
/// scrolls is held in, read out so that what it holds is placed in it, moving with it as it scrolls), where it is drawn
/// (the window's terms; none drawn yet, all 0), whether it takes no presses, whether a press does something and it can
/// take the focus, what it is called and what it holds where they were worked out again (None: as the pass before
/// found them), and the nearest of these that holds it (None: the window).
pub(all) struct SaidEntry {
  id : NodeId
  said : Said?
  rect : (Double, Double, Double, Double)
  disabled : Bool
  presses : Bool
  focus : Bool
  label : String?
  kids : Array[SaidKid]?
  parent : NodeId?
}

///|
/// What a pass of what is read out found (Tree::said_pass): the nodes it went through, each after what holds it, and
/// what the window holds where that was worked out again: by its layers, in their order, each its place in the window's
/// stack of layers and what of it is read out (what an old frame put over all of it goes among them by that place, as
/// Ctx::semantics_spliced puts it: before the first of them holding any node that says what it is, hidden or not).
pub(all) struct SaidPass {
  entries : Array[SaidEntry]
  root : Array[(Int, Array[SaidKid])]?
}

///|
/// Whether node `at` is read out as one of its own where it is not hidden (Tree::said_pass): it says what it is, or it is
/// what a column scrolls (one hosting an old view never: what that old view says is read out in its place).
fn Tree::said_entry_at(self : Tree, at : Int) -> Bool {
  let n = self.nodes[at]
  if n.hosted || at == 0 {
    return false
  }
  n.said is Some(_) || (n.parent >= 0 && self.nodes[n.parent].scroll_held == at)
}

///|
/// What is read out of the window's tree as it changed since the last pass, for what tells a screen reader of it as it
/// changes (ui's a11y.mbt): the nodes read out (Tree::said_order's, and what each column scrolls) that changed, or are
/// in what changed, gone through again, each with where it is drawn and whether it takes presses; what each is called
/// and what it holds worked out again only where its words or what it holds changed, it is new to what is told
/// (`known` says not), or what names it or what it holds is an old view's (`hosted` its name: those each pass); what
/// moves as a column scrolls each pass. Hidden as Tree::said_order hides; kept from input by a modal layer (or under
/// the old frame's own modal one, at `under` in the window's stack of layers: -2 none), not read out, what it holds in
/// what holds it. Everything again where `whole`, or the modal layers are otherwise than the last pass found them.
pub fn Tree::said_pass(
  self : Tree,
  known : (NodeId) -> Bool,
  hosted : (NodeId) -> String,
  set? : (String, WordsLook) -> String = fn(w, _) { w },
  under? : Int = -2,
  whole? : Bool = false,
) -> SaidPass {
  // (what each says as of now: as Tree::said_order)
  @signals.untracked(fn() { self.pull() })
  let seen = self.said_seen
  self.said_seen = self.said_revs
  self.said_revs = self.said_revs + 1
  let entries : Array[SaidEntry] = []
  guard self.nodes.length() > 0 && self.nodes[0].live else { return { entries, root: Some([]) } }
  let modal = match self.modal_top() {
    Some(m) => (m.at, m.gen)
    None => (-1, -1)
  }
  let held = match self.held_under_of {
    Some(f) => f()
    None => self.held_under
  }
  let sig = (modal.0, modal.1, held, under)
  let whole = whole || sig != self.said_modal
  self.said_modal = sig
  let kept_off = fn(at : Int) { !self.allows_at(at) || self.stack_at(at) <= under }
  let read = fn(at : Int) { self.said_entry_at(at) && !kept_off(at) }
  fn gather_one(k : Int, out : Array[SaidKid], crossed : Ref[Bool]) -> Unit {
    let kn = self.nodes[k]
    if !kn.live || kn.out || kn.said_hidden || kn.bones != 0L {
      return
    }
    let id = { at: k, gen: kn.gen }
    if kn.hosted {
      out.push(Hosts(id))
      crossed.val = true
    } else if read(k) {
      out.push(Entry(id))
      return
    }
    for c in self.kids_in_order(k) {
      gather_one(c, out, crossed)
    }
  }

  let visited : Map[Int, Bool] = Map([])
  // (one read out: what it says, what it is called and what it holds where `words`, `kids`)
  let entry = fn(
    at : Int,
    parent : NodeId?,
    x : Double,
    y : Double,
    s : Double,
    words : Bool,
    kids : Bool,
  ) {
    let n = self.nodes[at]
    let id = { at, gen: n.gen }
    visited[at] = true
    let crossed = Ref(false)
    let label = match n.said {
      Some(said) if said.label != "" => Some(said.label)
      Some(_) if words =>
        Some(
          self.words_within(
            id,
            fn(h) {
              crossed.val = true
              hosted(h)
            },
            set~,
          ),
        )
      Some(_) => None
      None => Some("")
    }
    let held = if kids {
      let out = []
      for k in self.kids_in_order(at) {
        gather_one(k, out, crossed)
      }
      Some(out)
    } else {
      None
    }
    // (what names it or what it holds an old view's: worked out again each pass; neither, not while both were)
    if crossed.val {
      self.said_again[at] = n.gen
    } else if words && kids {
      self.said_again.remove(at)
    }
    if n.said is None {
      self.said_helds[at] = n.gen
    }
    let rect = match n.content {
      Some(c) => (x, y, c.w * s, c.h * s)
      None => (0.0, 0.0, 0.0, 0.0)
    }
    entries.push({
      id,
      said: n.said,
      rect,
      disabled: self.pressless_at(at),
      presses: self.presses_do(id),
      focus: self.can_focus(id),
      label,
      kids: held,
      parent,
    })
  }
  fn walk(
    at : Int,
    parent : NodeId?,
    px : Double,
    py : Double,
    ps : Double,
    all : Bool,
    forced : Bool,
  ) -> Unit {
    let n = self.nodes[at]
    if !n.live || n.out || n.said_hidden || n.bones != 0L {
      return
    }
    // (nothing of it changed, nor what holds it: as the pass before found it)
    if !all && !forced && n.said_rev <= seen {
      return
    }
    // (it itself changed: what it holds read out again, where it is drawn, whether it takes presses)
    let forced = forced || n.own_rev > seen
    // (where it is drawn: Tree::projected's, from the window down)
    let (x, y, s) = if n.slot {
      (px, py, ps)
    } else {
      let (sx, sy) = self.scroll_off_now(n)
      (
        px + ps * (n.lx + sx + (1.0 - n.ls) * n.lpx),
        py + ps * (n.ly + sy + (1.0 - n.ls) * n.lpy),
        ps * n.ls,
      )
    }
    let mut up = parent
    let mut all = all
    if read(at) {
      let id = { at, gen: n.gen }
      // (new to what is told: all of it)
      let fresh = all || !known(id)
      all = fresh
      let again = self.said_again.get(at) == Some(n.gen)
      entry(
        at,
        parent,
        x,
        y,
        s,
        fresh || n.words_rev > seen || again,
        fresh || n.kids_rev > seen || again,
      )
      up = Some(id)
    }
    for k in self.kids_in_order(at) {
      walk(k, up, x, y, s, all, forced)
    }
  }

  walk(0, None, 0.0, 0.0, 1.0, whole, false)
  // (what was not gone through: where what names it or what it holds is an old view's, and what moves as a column
  // scrolls, as it is now; those no more read out let be)
  let shown = fn(at : Int, gen : Int) {
    if at <= 0 || at >= self.nodes.length() || self.nodes[at].gen != gen || !read(at) || !known({ at, gen }) {
      return false
    }
    let mut i = at
    while i >= 0 {
      let m = self.nodes[i]
      if !m.live || m.out || m.said_hidden || m.bones != 0L {
        return false
      }
      i = m.parent
    }
    true
  }
  let parent_of = fn(at : Int) -> NodeId? {
    let mut i = self.nodes[at].parent
    while i > 0 {
      if read(i) {
        return Some({ at: i, gen: self.nodes[i].gen })
      }
      i = self.nodes[i].parent
    }
    None
  }
  let again_now = self.said_again.to_array() |> Map::from_array
  for at, gen in again_now {
    if visited.contains(at) {
      continue
    }
    if !shown(at, gen) {
      self.said_again.remove(at)
      continue
    }
    let (x, y, _, s) = self.projected(at)
    entry(at, parent_of(at), x, y, s, true, true)
  }
  let helds_now = self.said_helds.to_array() |> Map::from_array
  for at, gen in helds_now {
    if visited.contains(at) {
      continue
    }
    if !shown(at, gen) || self.nodes[at].said is Some(_) {
      self.said_helds.remove(at)
      continue
    }
    let (x, y, _, s) = self.projected(at)
    entry(at, parent_of(at), x, y, s, false, false)
  }
  // (what the window holds: each of its layers' in their order, with its place in the window's stack)
  let root = if whole || self.nodes[0].kids_rev > seen || self.said_again.contains(0) {
    let out : Array[(Int, Array[SaidKid])] = []
    let crossed = Ref(false)
    // (whether it holds any node that says what it is or hosts an old view, hidden or not: Tree::said_order's)
    fn says_any(k : Int) -> Bool {
      let n = self.nodes[k]
      if !n.live || n.out {
        return false
      }
      if n.said is Some(_) || n.hosted {
        return true
      }
      self.kids_in_order(k).iter().any(fn(c) { says_any(c) })
    }

    for k in self.root_layers() {
      let one = []
      gather_one(k, one, crossed)
      if one.length() > 0 || says_any(k) {
        out.push((self.stack_at(k), one))
      }
    }
    if crossed.val {
      self.said_again[0] = self.nodes[0].gen
    } else {
      self.said_again.remove(0)
    }
    Some(out)
  } else {
    None
  }
  { entries, root }
}
