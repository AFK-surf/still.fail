// The keyboard as actions (GPUI's key_dispatch.rs, keymap.rs, action.rs): a node says the contexts it is
// (View::key_context) and what it does for an action (View::on_action); the keys are a table of their own, the tree's
// (View::keymap: Binding, each its keys, its action, where it works), so one table says what a key does, what a menu's
// item shows and what the shortcuts list. A key is matched against it from where the focus is, outwards: the node with
// the focus and what holds it first, the innermost first, then the other nodes that do actions, the one drawn last first
// (as Tree::key_at asks them), each with the contexts of its own chain; the first that takes it ends it.
//
// A binding of keys one after another (⌘K ←) holds those that came while it is under way (Tree::keys_pending). It ends
// by a cause alone, said as it ends (Tree::keys_ended): its action done, a key that goes on with none of it (then
// matched alone, afresh), Escape, the focus moved, the keymap changed; and, where the keymap says one, its time out: a
// moment declared from the first key's (Keymap's `pending_ms`, on the tree's timeline), never a window found by
// waiting. A binding that is whole where a longer one goes on is done as it comes: nothing waits to tell them apart.

///|
/// A key as a binding says it: its code and exactly the modifiers held (ui's key codes and mods).
#derive(Eq, Debug)
pub(all) struct Stroke {
  code : Int
  mods : Int
}

///|
/// Where a binding works, of the contexts said by the chain a node is in (View::key_context) and the facts of the key
/// itself (Tree::stroke's: the focus in a field, `Field`): GPUI's context predicate, without `>`.
#derive(Eq, Debug)
pub(all) enum KeyWhen {
  Always
  In(String)
  Not(KeyWhen)
  All(Array[KeyWhen])
  Any(Array[KeyWhen])
}

///|
/// Whether it holds where `has` says which contexts are.
pub fn KeyWhen::holds(self : KeyWhen, has : (String) -> Bool) -> Bool {
  match self {
    Always => true
    In(name) => has(name)
    Not(w) => !w.holds(has)
    All(ws) => ws.iter().all(fn(w) { w.holds(has) })
    Any(ws) => ws.iter().any(fn(w) { w.holds(has) })
  }
}

///|
/// A predicate as written: names, `!`, `&&`, `||` (`&&` binding closer) and brackets, `Chat && !Field`; "" Always;
/// None where it is not one.
pub fn KeyWhen::parse(text : String) -> KeyWhen? {
  let toks : Array[String] = []
  let cs = text.to_array()
  let mut i = 0
  while i < cs.length() {
    let c = cs[i]
    if c == ' ' {
      i = i + 1
    } else if c == '!' || c == '(' || c == ')' {
      toks.push(c.to_string())
      i = i + 1
    } else if (c == '&' || c == '|') && i + 1 < cs.length() && cs[i + 1] == c {
      toks.push(c.to_string() + c.to_string())
      i = i + 2
    } else if c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '_' || c == '.' || c == '-' {
      let from = i
      while i < cs.length() &&
            (cs[i].is_ascii_alphabetic() || cs[i].is_ascii_digit() || cs[i] == '_' || cs[i] == '.' || cs[i] == '-') {
        i = i + 1
      }
      toks.push(String::from_array(cs[from:i]))
    } else {
      return None
    }
  }
  if toks.is_empty() {
    return Some(Always)
  }
  let p : WhenParse = { toks, at: 0 }
  match p.any() {
    Some(w) if p.at == toks.length() => Some(w)
    _ => None
  }
}

///|
/// A predicate's words as KeyWhen::parse goes through them.
priv struct WhenParse {
  toks : Array[String]
  mut at : Int
}

///|
fn WhenParse::peek(self : WhenParse) -> String {
  if self.at < self.toks.length() {
    self.toks[self.at]
  } else {
    ""
  }
}

///|
/// A name, `!` one, or one in brackets.
fn WhenParse::one(self : WhenParse) -> KeyWhen? {
  match self.peek() {
    "!" => {
      self.at += 1
      self.one().map(fn(w) { Not(w) })
    }
    "(" => {
      self.at += 1
      let w = self.any()
      if self.peek() != ")" {
        return None
      }
      self.at += 1
      w
    }
    "" | ")" | "&&" | "||" => None
    name => {
      self.at += 1
      Some(In(name))
    }
  }
}

///|
/// Ones joined by `&&`.
fn WhenParse::all(self : WhenParse) -> KeyWhen? {
  let ws : Array[KeyWhen] = []
  while true {
    match self.one() {
      Some(w) => ws.push(w)
      None => return None
    }
    if self.peek() != "&&" {
      break
    }
    self.at += 1
  }
  Some(if ws.length() == 1 { ws[0] } else { All(ws) })
}

///|
/// Those joined by `||`.
fn WhenParse::any(self : WhenParse) -> KeyWhen? {
  let ws : Array[KeyWhen] = []
  while true {
    match self.all() {
      Some(w) => ws.push(w)
      None => return None
    }
    if self.peek() != "||" {
      break
    }
    self.at += 1
  }
  Some(if ws.length() == 1 { ws[0] } else { Any(ws) })
}

///|
/// Keys (one after another where more than one) that do `action` where `when` holds.
#derive(Eq, Debug)
pub(all) struct Binding {
  keys : Array[Stroke]
  action : String
  when : KeyWhen
}

///|
/// A tree's keys: its bindings, a later one before an earlier (what a person changed put after what the app has), and
/// how long a sequence under way waits for its next key before it ends (None: till a cause ends it).
#derive(Eq, Debug)
pub(all) struct Keymap {
  bindings : Array[Binding]
  pending_ms : Double?
}

///|
pub fn Keymap::new(bindings : Array[Binding], pending_ms? : Double? = None) -> Keymap {
  { bindings, pending_ms }
}

///|
/// Why the last sequence of keys under way ended (Tree::keys_ended): none yet; its action done; a key that goes on with
/// none of it; Escape; the focus moved; the keymap changed; its time out (Keymap's `pending_ms`).
#derive(Eq, Debug)
pub(all) enum KeysEnd {
  NotYet
  Done(String)
  Unmatched
  Cancelled
  FocusMoved
  KeymapChanged
  TimedOut
}

///|
/// How an action came: by its keys, or asked by name (a menu's item, a command's list: Tree::ask_action).
#derive(Eq, Debug)
pub(all) enum ActionBy {
  Keys
  Asked
}

///|
/// An action as a node is told it (View::on_action): which, at what moment, the keys it came by (none asked by name).
#derive(Eq, Debug)
pub(all) struct ActionAt {
  action : String
  at : Double
  keys : Array[Stroke]
  by : ActionBy
}

///|
/// What a node says of the keyboard's actions: its contexts, and what it does for an action (whether it can now, and
/// what: true where it took it); and what an old view hosted in it said of them as it was last built (Tree::keys_said).
priv struct KeyNode {
  gen : Int
  contexts : Array[String]
  actions : Array[(String, (ActionAt) -> Bool, () -> Bool)]
  said_contexts : Array[String]
  said_actions : Array[(String, (ActionAt) -> Bool, () -> Bool)]
}

///|
/// A tree's keys (Tree's `keyed`): its keymap, its nodes' contexts and actions by index, a sequence under way (its keys,
/// where it began, what ends it at its time) and why the last one ended.
struct KeyBook {
  mut map : Keymap
  nodes : Map[Int, KeyNode]
  pending : @signals.Signal[Array[Stroke]]
  mut pending_from : NodeId?
  mut pending_off : () -> Unit
  ended : @signals.Signal[KeysEnd]
}

///|
fn KeyBook::new() -> KeyBook {
  {
    map: { bindings: [], pending_ms: None },
    nodes: {},
    pending: @signals.signal([], same=fn(a, b) { a == b }),
    pending_from: None,
    pending_off: fn() {  },
    ended: @signals.signal(NotYet, same=fn(a, b) { a == b }),
  }
}

///|
/// What node `self` says of the keyboard, made as first said and let go with it.
fn View::key_node(self : View) -> KeyNode? {
  guard self.live() is Some(_) else { return None }
  let book = self.tree.keyed
  match book.nodes.get(self.at) {
    Some(k) if k.gen == self.gen => Some(k)
    _ => {
      let k : KeyNode = { gen: self.gen, contexts: [], actions: [], said_contexts: [], said_actions: [] }
      book.nodes[self.at] = k
      let (at, gen) = (self.at, self.gen)
      self.owns(fn() {
        match book.nodes.get(at) {
          Some(k) if k.gen == gen => book.nodes.remove(at)
          _ => ()
        }
      })
      |> ignore
      Some(k)
    }
  }
}

///|
/// It is context `name` for the bindings matched from it and what it holds (KeyWhen's In): said again, one more.
pub fn View::key_context(self : View, name : String) -> View {
  match self.key_node() {
    Some(k) if !k.contexts.contains(name) => k.contexts.push(name)
    _ => ()
  }
  self
}

///|
/// What it does for `action` (by its keys where the keymap binds them where it is, or asked by name): run at its
/// moment, as one change outside any tracking; true where it took it, which nothing else is told of then, false passing
/// it on outwards. `can`: whether it can now (read as it is asked; where not, passed by as if it said nothing).
pub fn View::on_action(self : View, action : String, f : (ActionAt) -> Bool, can? : () -> Bool = fn() { true }) -> View {
  match self.key_node() {
    Some(k) => k.actions.push((action, f, can))
    None => ()
  }
  self
}

///|
/// The tree's keys (Keymap): as `map` says, bound, a sequence under way ended as it changes (KeymapChanged).
pub fn View::keymap(self : View, map : Live[Keymap]) -> View {
  guard self.live() is Some(_) else { return self }
  match map {
    Is(m) => self.tree.keymap_set(m)
    By(f) => self.reacts(f, fn(m) { self.tree.keymap_set(m) })
  }
  self
}

///|
fn Tree::keymap_set(self : Tree, m : Keymap) -> Unit {
  if self.keyed.map == m {
    return
  }
  self.keyed.map = m
  self.keys_end(KeymapChanged)
}

///|
/// The keys of the sequence under way (none: none is), followed.
pub fn Tree::keys_pending(self : Tree) -> Array[Stroke] {
  self.keyed.pending.get()
}

///|
/// Why the last sequence of keys under way ended, followed.
pub fn Tree::keys_ended(self : Tree) -> KeysEnd {
  self.keyed.ended.get()
}

///|
/// The sequence under way ended, `why`; nothing where none is.
fn Tree::keys_end(self : Tree, why : KeysEnd) -> Unit {
  let book = self.keyed
  if book.pending.untracked().is_empty() {
    return
  }
  (book.pending_off)()
  book.pending_off = fn() {  }
  book.pending_from = None
  @signals.start_batch()
  book.pending.set([])
  book.ended.set(why)
  @signals.end_batch()
}

///|
/// The nodes that do actions as a key from `from` (the node with the focus, or what hosts it; None: none has it) asks
/// them: `from` and what holds it, the innermost first, those that may take input; then the rest that may, the one
/// drawn last first.
fn Tree::action_nodes(self : Tree, from : NodeId?) -> Array[Int] {
  let book = self.keyed
  let mine = fn(i : Int) {
    match book.nodes.get(i) {
      Some(k) => k.gen == self.nodes[i].gen && self.nodes[i].live
      None => false
    }
  }
  let out : Array[Int] = []
  match from {
    Some(id) if self.alive_id(id) => {
      let mut i = id.at
      while i >= 0 {
        if mine(i) && !self.pressless_at(i) {
          out.push(i)
        }
        i = self.nodes[i].parent
      }
    }
    _ => ()
  }
  if self.nodes.length() > 0 && self.nodes[0].live {
    let rest : Array[Int] = []
    self.topmost_from(0, fn(_) { true }, rest)
    for i in rest {
      if mine(i) && !out.contains(i) && !self.pressless_at(i) {
        out.push(i)
      }
    }
  }
  out
}

///|
/// Whether context `name` is so at node `at`: said by it or what holds it, or one of the key's `facts`.
fn Tree::key_has(self : Tree, at : Int, facts : Array[String], name : String) -> Bool {
  if facts.contains(name) {
    return true
  }
  let mut i = at
  while i >= 0 {
    match self.keyed.nodes.get(i) {
      Some(k) if k.gen == self.nodes[i].gen && (k.contexts.contains(name) || k.said_contexts.contains(name)) =>
        return true
      _ => ()
    }
    i = self.nodes[i].parent
  }
  false
}

///|
/// What node `at` does for `action`, where it can now.
fn Tree::action_at(self : Tree, at : Int, action : String) -> Array[(ActionAt) -> Bool] {
  match self.keyed.nodes.get(at) {
    Some(k) =>
      [..k.actions, ..k.said_actions].filter_map(fn(a) {
        if a.0 == action && @signals.untracked(a.2) {
          Some(a.1)
        } else {
          None
        }
      })
    None => []
  }
}

///|
/// Whether `keys` begins with `head`.
fn strokes_begin(keys : Array[Stroke], head : Array[Stroke]) -> Bool {
  if keys.length() < head.length() {
    return false
  }
  for k, s in head {
    if keys[k] != s {
      return false
    }
  }
  true
}

///|
/// A key (`code`, `mods` held) at `at` from `from` (the node with the focus, or what hosts it), with the key's own
/// `facts` (contexts so wherever it is matched: the focus in a field, `Field`): matched against the keymap with what
/// came of a sequence under way, as one event of that moment (the tree brought there first where it is in none). A
/// binding whole with it done by the first node that takes it; one it goes on with but does not end, it held under way;
/// none, a sequence under way ended (Unmatched, Escape Cancelled) and the key matched alone. True where it was taken.
pub fn Tree::stroke(
  self : Tree,
  code : Int,
  mods : Int,
  at : Double,
  from? : NodeId? = None,
  facts? : Array[String] = [],
) -> Bool {
  if self.nodes.length() == 0 || !self.nodes[0].live {
    return false
  }
  let t = if self.cause_at >= 0.0 { self.cause_at } else { at }
  if self.cause_at < 0.0 {
    self.bring_to(t)
  }
  let took = Ref(false)
  self.event(t, fn() {
    let book = self.keyed
    let s : Stroke = { code, mods }
    // (begun from another focus than this key's: ended as it moved, the old view's focus too)
    let under = book.pending.untracked()
    if !under.is_empty() && book.pending_from != from {
      self.keys_end(FocusMoved)
    }
    took.val = self.stroke_now(s, t, from, facts)
  })
  took.val
}

///|
/// Tree::stroke's, in its event.
fn Tree::stroke_now(self : Tree, s : Stroke, t : Double, from : NodeId?, facts : Array[String]) -> Bool {
  let book = self.keyed
  let under = book.pending.untracked()
  let keys = [..under, s]
  let nodes = self.action_nodes(from)
  let bindings = book.map.bindings
  // (whole: each node in turn, its later bindings first, the first that takes it; the app's, then where none of them
  // took it a column's own keys, as an old view's list took what no action did: scroll_keys.mbt)
  for pass in [bindings, scroll_bindings] {
    for i in nodes {
      let mut b = pass.length() - 1
      while b >= 0 {
        let bd = pass[b]
        b = b - 1
        guard bd.keys == keys && bd.when.holds(fn(name) { self.key_has(i, facts, name) }) else { continue }
        for f in self.action_at(i, bd.action) {
          guard self.nodes[i].live else { break }
          if @signals.untracked(fn() { f({ action: bd.action, at: t, keys, by: Keys }) }) {
            self.keys_end(Done(bd.action))
            return true
          }
        }
      }
    }
  }
  // (begun: a longer binding it goes on with, where some node does its action)
  let goes_on = nodes.iter().any(fn(i) {
    bindings
    .iter()
    .any(fn(bd) {
      bd.keys.length() > keys.length() &&
      strokes_begin(bd.keys, keys) &&
      bd.when.holds(fn(name) { self.key_has(i, facts, name) }) &&
      self.action_at(i, bd.action).length() > 0
    })
  })
  if goes_on {
    if under.is_empty() {
      book.pending_from = from
      match book.map.pending_ms {
        Some(ms) => {
          let off = self.handle(0).at_moment(t + ms, fn() { self.keys_end(TimedOut) })
          book.pending_off = off
        }
        None => ()
      }
    }
    book.pending.set(keys)
    return true
  }
  if under.is_empty() {
    return false
  }
  // (none: what was under way ended by it, Escape taken so, any other key matched alone)
  if s.code == key_escape_code && s.mods == 0 {
    self.keys_end(Cancelled)
    return true
  }
  self.keys_end(Unmatched)
  self.stroke_now(s, t, from, facts)
}

///|
/// Escape's code (ui's key_escape).
let key_escape_code : Int = 17

///|
/// Action `action` asked by name (a menu's item, a command's list) at `at`, from `from` as a key is: done by the first
/// node that does it and takes it, as one event of that moment. True where one took it.
pub fn Tree::ask_action(self : Tree, action : String, at : Double, from? : NodeId? = None) -> Bool {
  if self.nodes.length() == 0 || !self.nodes[0].live {
    return false
  }
  let t = if self.cause_at >= 0.0 { self.cause_at } else { at }
  if self.cause_at < 0.0 {
    self.bring_to(t)
  }
  let took = Ref(false)
  self.event(t, fn() {
    for i in self.action_nodes(from) {
      for f in self.action_at(i, action) {
        guard self.nodes[i].live && !took.val else { break }
        if @signals.untracked(fn() { f({ action, at: t, keys: [], by: Asked }) }) {
          took.val = true
        }
      }
      if took.val {
        break
      }
    }
  })
  took.val
}

///|
/// The keys that do `action` from `from` as things are now (a menu's item's, a tip's, the shortcuts' list), the one a
/// key matches first first: of the bindings that hold where the first node that does it is (none does: where `from`
/// is), with `facts`.
pub fn Tree::keys_for(
  self : Tree,
  action : String,
  from? : NodeId? = None,
  facts? : Array[String] = [],
) -> Array[Array[Stroke]] {
  if self.nodes.length() == 0 || !self.nodes[0].live {
    return []
  }
  let at = match self.action_nodes(from).iter().find_first(fn(i) { self.action_at(i, action).length() > 0 }) {
    Some(i) => i
    None =>
      match from {
        Some(id) if self.alive_id(id) => id.at
        _ => 0
      }
  }
  let out : Array[Array[Stroke]] = []
  let bindings = self.keyed.map.bindings
  let mut b = bindings.length() - 1
  while b >= 0 {
    let bd = bindings[b]
    b = b - 1
    if bd.action == action && bd.when.holds(fn(name) { self.key_has(at, facts, name) }) && !out.contains(bd.keys) {
      out.push(bd.keys)
    }
  }
  out
}

///|
/// The actions some node does now from `from` (a command's list, whether a menu's item can be chosen), each once, in
/// the order they are asked.
pub fn Tree::actions_here(self : Tree, from? : NodeId? = None) -> Array[String] {
  let out : Array[String] = []
  if self.nodes.length() == 0 || !self.nodes[0].live {
    return out
  }
  for i in self.action_nodes(from) {
    match self.keyed.nodes.get(i) {
      Some(k) =>
        for a in [..k.actions, ..k.said_actions] {
          if !out.contains(a.0) && @signals.untracked(a.2) {
            out.push(a.0)
          }
        }
      None => ()
    }
  }
  out
}

///|
/// What an old view hosted in node `id` (ui's) says of the keyboard as it is built, its contexts and what it does for
/// an action, as a node says them (ui's Ctx::key_context, Ctx::on_action): `anew` as it is built again from its start,
/// all it said before let go; then each said added. Nothing where the node is gone.
pub fn Tree::keys_said(
  self : Tree,
  id : NodeId,
  anew? : Bool = false,
  context? : String,
  action? : (String, (ActionAt) -> Bool),
) -> Unit {
  guard self.alive_id(id) else { return }
  // (nothing said of it yet and nothing said now: nothing made for it)
  let had = match self.keyed.nodes.get(id.at) {
    Some(k) => k.gen == id.gen
    None => false
  }
  if !had && context is None && action is None {
    return
  }
  let k = match self.handle(id.at).key_node() {
    Some(k) => k
    None => return
  }
  if anew {
    k.said_contexts.clear()
    k.said_actions.clear()
  }
  match context {
    Some(name) if !k.said_contexts.contains(name) => k.said_contexts.push(name)
    _ => ()
  }
  match action {
    Some((name, f)) => k.said_actions.push((name, f, fn() { true }))
    None => ()
  }
}
