// The widgets told to the system's accessibility (a screen reader: Android's TalkBack), as Compose tells its semantics
// to Android: while something reads them out (@hostapi.a11y_on), each frame's semantics tree (semantics.mbt), what is
// not hidden, goes to the host as lines when it is not as last told (@hostapi.a11y_tree); the host makes the view's
// virtual nodes of them (Android: MBView's A11y, an AccessibilityNodeProvider). What the reader asks of a node (a
// double tap: activate; a swipe up or down on a slider: a step) comes back on @hostapi.a11y_channel and is asked of
// its widget for the next frame (Ctx::ask_action), as a test asks it.
//
// A line a node, its fields split by U+001F (none of them holds one, nor a line's end):
//
//   node  parent  widget  role  flags  x  y  w  h  label  value  description  low  at  high  actions
//
// `node` a number of its own, kept from frame to frame (its widget's id; words: from their parent's and themselves),
// `parent` its parent's (0: the view), `widget` the id its actions are asked of (0 none), `role` the Role's name;
// `flags` letters: c checkable (C checked, M mixed), e expandable (E expanded), s selected, p pressable (P pressed), d
// disabled, f has the keyboard's focus, m modal; its rect in points; its range (a slider's, a progress bar's) or three
// empty fields; `actions` letters: a activate, i increment, d decrement, e expand, c collapse, x dismiss, f focus, t
// words put in it (set text: `{"action": "set_text", "text": words}` asked).

///|
let a11y_sep : String = "\u{1F}"

///|
/// The tree as the host is told it (see above): the nodes not hidden, in the tree's order.
pub fn Ctx::a11y_lines(self : Ctx) -> String {
  let tree = self.semantics_tree()
  // by the tree's index: the node's number (0 hidden), and how many words of a label its parent has had
  let num = Array::make(tree.length(), 0)
  let used : Map[Int, Bool] = {}
  let seen : Map[String, Int] = {}
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
    let base = if s.id != 0 {
      s.id
    } else {
      let key = "\{parent}\u{1F}\{s.role}\u{1F}\{s.label}"
      let nth = seen.get(key).unwrap_or(0)
      seen[key] = nth + 1
      a11y_hash("\{key}\u{1F}\{nth}")
    }
    let mut n = base & 0x3FFFFFFF
    while n == 0 || used.contains(n) {
      n = (n * 31 + 7) & 0x3FFFFFFF
    }
    used[n] = true
    num[k] = n
    let (x, y, w, h) = s.rect
    let z = window_zoom_drawn.val
    let (lo, at, hi) = match s.range {
      Some((lo, v, hi)) => (lo.to_string(), v.to_string(), hi.to_string())
      None => ("", "", "")
    }
    let fields = [
      n.to_string(),
      parent.to_string(),
      s.id.to_string(),
      s.role.to_string(),
      a11y_flags(s),
      a11y_length(x * z),
      a11y_length(y * z),
      a11y_length(w * z),
      a11y_length(h * z),
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
fn a11y_flags(s : SemNode) -> String {
  let sb = StringBuilder()
  match s.check {
    Some(Off) => sb.write_string("c")
    Some(On) => sb.write_string("cC")
    Some(Mixed) => sb.write_string("cM")
    None => ()
  }
  match s.expanded {
    Some(true) => sb.write_string("eE")
    Some(false) => sb.write_string("e")
    None => ()
  }
  if s.selected == Some(true) {
    sb.write_string("s")
  }
  match s.pressed {
    Some(true) => sb.write_string("pP")
    Some(false) => sb.write_string("p")
    None => ()
  }
  if s.disabled {
    sb.write_string("d")
  }
  if s.focused {
    sb.write_string("f")
  }
  if s.modal {
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
/// A place or a size as the host is told it: to a thousandth of a point, as no screen shows finer (what a layout summed
/// one way or another, 617 or 617.0000000000001, is told the same, and the same tree is not told again for it).
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
/// As a frame has been painted: the host told what the widgets are when something reads them out and they are not as
/// last told (app.mbt frame_body). Nothing while nothing reads them.
fn Ctx::a11y_after_paint(self : Ctx) -> Unit {
  if !self.reads_out {
    self.a11y_sent = ""
    return
  }
  let lines = self.a11y_lines()
  if lines != self.a11y_sent {
    self.a11y_sent = lines
    h_a11y_tree(lines)
  }
}

///|
/// What the system's accessibility asked of a widget (a message on @hostapi.a11y_channel: `{"id": widget, "action":
/// name}`), asked of it for the next frame.
fn a11y_took(json : String) -> Unit {
  let v = @json.parse(json) catch { _ => return }
  guard v is Object(m) else { return }
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
  self.fake.a11y = on
  self.fake.wants = true
}

///|
/// What the host's accessibility was last told the widgets are (the lines above; "" nothing yet).
pub fn Tester::a11y_said(self : Tester) -> String {
  self.fake.a11y_said
}
