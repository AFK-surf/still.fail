// A widget's scripts run by mbui itself (mbui/js): its <script> elements in order over a document of its own (the
// fragment's elements, live: what a script changes of them is what is drawn next), the DOM a widget's script uses
// (document's queries and making elements, an element's attributes, classes, style, words, HTML, children, events),
// what the app gives it (window.openai: what the widget keeps, words to send), and what a page's script takes for
// granted (getComputedStyle's custom properties, matchMedia, ResizeObserver told its width once). A press on what
// listens for one is a click dispatched through it and what holds it; a box ticked, an input and a change.

///|
let uid_attr : String = "data-mbui-uid"

///|
/// What the app gives a widget's script: what it kept last (null none), keeping a new state, putting words in the
/// composer to send (only from a press).
pub(all) struct Bridge {
  state : () -> String?
  keep : (String) -> Unit
  follow_up : (String) -> Unit
}

///|
/// A widget's live document and the realm its scripts run in.
pub struct Doc {
  nodes : Array[@html.Node]
  els : Map[Int, @html.Elem]
  mut next_uid : Int
  realm : @js.Realm
  /// each element's listeners (by its uid): the event's type, the function, whether it is a capture's
  listeners : Map[Int, Array[(String, @js.Value)]]
  /// the document's and the window's (uid -1, -2)
  wrappers : Map[Int, @js.Obj]
  /// what was changed since it was last drawn
  mut touched : Bool
  /// the latest styling (getComputedStyle's), and the room it was drawn in
  mut styled : @html.Styled?
  mut width : Double
  /// what its scripts threw as they ran first (it is drawn by a browser instead)
  mut failed : String?
  /// ResizeObservers' callbacks and what they observe, told the width once drawn
  observers : Array[(@js.Value, @js.Value, Array[Int])]
  bridge : Bridge
  mut pressing : Bool
  /// text nodes made by createTextNode, by their number
  texts : Map[Int, Ref[String]]
}

///|
fn uid_of(e : @html.Elem) -> Int {
  match e.attr(uid_attr) {
    Some(v) => @html.parse_int(v).unwrap_or(-1)
    None => -1
  }
}

///|
fn Doc::own(self : Doc, nodes : Array[@html.Node]) -> Unit {
  for n in nodes {
    if n is Elem(e) {
      if uid_of(e) < 0 {
        e.attrs.push((uid_attr, self.next_uid.to_string()))
        self.els[self.next_uid] = e
        self.next_uid += 1
      } else {
        self.els[uid_of(e)] = e
      }
      self.own(e.kids)
    }
  }
}

///|
/// The element that holds `e` (None: it is at the top, or not in the document).
fn Doc::parent(self : Doc, e : @html.Elem) -> @html.Elem? {
  fn find(nodes : Array[@html.Node], holder : @html.Elem?) -> @html.Elem?? {
    for n in nodes {
      if n is Elem(x) {
        if physical_equal(x, e) {
          return Some(holder)
        }
        match find(x.kids, Some(x)) {
          Some(h) => return Some(h)
          None => ()
        }
      }
    }
    None
  }

  match find(self.nodes, None) {
    Some(h) => h
    None => None
  }
}

///|
fn Doc::in_doc(self : Doc, e : @html.Elem) -> Bool {
  fn find(nodes : Array[@html.Node]) -> Bool {
    for n in nodes {
      if n is Elem(x) && (physical_equal(x, e) || find(x.kids)) {
        return true
      }
    }
    false
  }

  find(self.nodes)
}

///|
/// The list `e` is in (its parent's kids, or the document's).
fn Doc::siblings(self : Doc, e : @html.Elem) -> Array[@html.Node]? {
  match self.parent(e) {
    Some(p) => Some(p.kids)
    None => if self.in_doc(e) { Some(self.nodes) } else { None }
  }
}

///|
fn Doc::detach(self : Doc, e : @html.Elem) -> Unit {
  match self.siblings(e) {
    Some(list) =>
      match list.search_by(fn(n) { n is Elem(x) && physical_equal(x, e) }) {
        Some(i) => list.remove(i) |> ignore
        None => ()
      }
    None => ()
  }
}

///|
fn Doc::touch(self : Doc) -> Unit {
  self.touched = true
}

///|
/// The script object of element `e`, the same each time.
fn Doc::wrap(self : Doc, e : @html.Elem) -> @js.Value {
  let uid = uid_of(e)
  match self.wrappers.get(uid) {
    Some(o) => O(o)
    None => {
      let o = self.realm.new_obj(proto=Some(self.element_proto()), kind=Host(uid))
      self.wrappers[uid] = o
      O(o)
    }
  }
}

///|
fn Doc::element_proto(self : Doc) -> @js.Obj {
  match self.wrappers.get(-10) {
    Some(p) => p
    None => {
      let p = self.realm.new_obj()
      self.wrappers[-10] = p
      self.element_methods(p)
      p
    }
  }
}

///|
fn Doc::elem_of(self : Doc, v : @js.Value) -> @html.Elem? {
  match v {
    O({ kind: Host(uid), .. }) => self.els.get(uid)
    _ => None
  }
}

///|
fn Doc::this_elem(self : Doc, this : @js.Value) -> @html.Elem raise @js.Throw {
  match self.elem_of(this) {
    Some(e) => e
    None => raise self.realm.error("TypeError", "Illegal invocation")
  }
}

///|
/// A tree of the document's elements now, for selectors.
fn Doc::tree(self : Doc) -> @html.Tree {
  @html.Tree::new(self.nodes)
}

///|
fn Doc::query(self : Doc, sel : String, within : @html.Elem?, all : Bool) -> Array[@html.Elem] raise @js.Throw {
  let list = match @html.parse_selectors(sel) {
    Some(l) => l
    None => raise self.realm.error("SyntaxError", "'\{sel}' is not a valid selector")
  }
  let tree = self.tree()
  let out = []
  for i, p in tree.els {
    if within is Some(w) {
      // inside it, not it
      let mut q = p.parent
      let mut inside = false
      while q >= 0 {
        if physical_equal(tree.els[q].elem, w) {
          inside = true
          break
        }
        q = tree.els[q].parent
      }
      if !inside {
        continue
      }
    }
    if list.iter().any(fn(s) { s.element == "" && tree.matches(s, i, fn(_, _) { false }) }) {
      out.push(p.elem)
      if !all {
        break
      }
    }
  }
  out
}

///|
fn camel_to_kebab(s : String) -> String {
  if s.has_prefix("--") {
    return s
  }
  let b = StringBuilder()
  for c in s {
    if c >= 'A' && c <= 'Z' {
      b.write_char('-')
      b.write_char(Int::unsafe_to_char(c.to_int() + 32))
    } else {
      b.write_char(c)
    }
  }
  b.to_string()
}

///|
fn kebab_to_camel(s : String) -> String {
  let b = StringBuilder()
  let mut up = false
  for c in s {
    if c == '-' {
      up = true
    } else if up && c >= 'a' && c <= 'z' {
      b.write_char(Int::unsafe_to_char(c.to_int() - 32))
      up = false
    } else {
      b.write_char(c)
      up = false
    }
  }
  b.to_string()
}

///|
fn set_attr(e : @html.Elem, name : String, value : String?) -> Unit {
  match (e.attrs.search_by(fn(a) { a.0 == name }), value) {
    (Some(i), Some(v)) => e.attrs[i] = (name, v)
    (Some(i), None) => e.attrs.remove(i) |> ignore
    (None, Some(v)) => e.attrs.push((name, v))
    (None, None) => ()
  }
}

///|
/// An element's inline style as its declarations.
fn style_decls(e : @html.Elem) -> Array[(String, String)] {
  @html.parse_decls(e.attr("style").unwrap_or("")).map(fn(d) { (d.name, d.value + (if d.important { " !important" } else { "" })) })
}

///|
fn set_style(e : @html.Elem, name : String, value : String) -> Unit {
  let ds = style_decls(e).filter(fn(d) { d.0 != name })
  if value != "" {
    ds.push((name, value))
  }
  set_attr(e, "style", Some(ds.map(fn(d) { d.0 + ": " + d.1 }).join("; ")))
}

///|
fn Doc::classes(self : Doc, e : @html.Elem) -> @js.Value {
  let r = self.realm
  let o = r.new_obj()
  let put = fn(list : Array[String]) {
    set_attr(e, "class", Some(list.join(" ")))
    self.touch()
  }
  r.method(o, "add", fn(_, args, r) {
    let have = e.classes()
    for a in args {
      let c = r.to_string(a)
      if !have.contains(c) {
        have.push(c)
      }
    }
    put(have)
    Undefined
  })
  r.method(o, "remove", fn(_, args, r) {
    let gone = []
    for a in args {
      gone.push(r.to_string(a))
    }
    put(e.classes().filter(fn(c) { !gone.contains(c) }))
    Undefined
  })
  r.method(o, "toggle", fn(_, args, r) {
    let c = r.to_string(args.get(0).unwrap_or(Undefined))
    let have = e.classes()
    let on = match args.get(1) {
      Some(B(f)) => f
      _ => !have.contains(c)
    }
    put(if on { if have.contains(c) { have } else { [..have, c] } } else { have.filter(fn(x) { x != c }) })
    B(on)
  })
  r.method(o, "contains", fn(_, args, r) { B(e.classes().contains(r.to_string(args.get(0).unwrap_or(Undefined)))) })
  r.method(o, "replace", fn(_, args, r) {
    let a = r.to_string(args.get(0).unwrap_or(Undefined))
    let b = r.to_string(args.get(1).unwrap_or(Undefined))
    put(e.classes().map(fn(c) { if c == a { b } else { c } }))
    Undefined
  })
  r.accessor(o, "length", fn(_, _, _) { N(e.classes().length().to_double()) })
  r.method(o, "item", fn(_, args, r) {
    match e.classes().get(r.to_number(args.get(0).unwrap_or(Undefined)).to_int()) {
      Some(c) => S(c)
      None => Null
    }
  })
  O(o)
}

///|
/// An element's style as a script reads and writes it: each property by its camelCase or its own name.
fn Doc::style_obj(self : Doc, e : @html.Elem) -> @js.Value {
  let r = self.realm
  let o = r.new_obj()
  r.method(o, "setProperty", fn(_, args, r) {
    set_style(e, r.to_string(args.get(0).unwrap_or(Undefined)), r.to_string(args.get(1).unwrap_or(S(""))))
    self.touch()
    Undefined
  })
  r.method(o, "getPropertyValue", fn(_, args, r) {
    let name = r.to_string(args.get(0).unwrap_or(Undefined))
    match style_decls(e).search_by(fn(d) { d.0 == name }) {
      Some(i) => S(style_decls(e)[i].1)
      None => S("")
    }
  })
  r.method(o, "removeProperty", fn(_, args, r) {
    set_style(e, r.to_string(args.get(0).unwrap_or(Undefined)), "")
    self.touch()
    Undefined
  })
  r.accessor(o, "cssText", fn(_, _, _) { S(e.attr("style").unwrap_or("")) }, set=Some(fn(_, args, r) {
    set_attr(e, "style", Some(r.to_string(args.get(0).unwrap_or(S("")))))
    self.touch()
    Undefined
  }))
  // any other property: the declaration it names (a host object: its reads and writes are the host's)
  let style_uid = -1000 - uid_of(e)
  o.kind = Host(style_uid)
  O(o)
}

///|
/// Its data-* attributes as dataset names them.
fn Doc::dataset(self : Doc, e : @html.Elem) -> @js.Value {
  let o = self.realm.new_obj(kind=Host(-2000000 - uid_of(e)))
  O(o)
}

///|
fn Doc::event(self : Doc, ty : String, target : @html.Elem?, extra : Array[(String, @js.Value)]) -> @js.Obj {
  let r = self.realm
  let ev = r.new_obj()
  ev.props["type"] = Data(S(ty))
  ev.props["target"] = Data(
    match target {
      Some(t) => self.wrap(t)
      None => Null
    },
  )
  ev.props["defaultPrevented"] = Data(B(false))
  ev.props["bubbles"] = Data(B(true))
  ev.props["@@stopped"] = Data(B(false))
  ev.hidden["@@stopped"] = true
  for x in extra {
    ev.props[x.0] = Data(x.1)
  }
  r.method(ev, "preventDefault", fn(_, _, _) {
    ev.props["defaultPrevented"] = Data(B(true))
    Undefined
  })
  r.method(ev, "stopPropagation", fn(_, _, _) {
    ev.props["@@stopped"] = Data(B(true))
    Undefined
  })
  r.method(ev, "stopImmediatePropagation", fn(_, _, _) {
    ev.props["@@stopped"] = Data(B(true))
    Undefined
  })
  ev
}

///|
/// Event `ty` dispatched at `target`, bubbling through what holds it to the document and the window; what a listener
/// threw logged.
pub fn Doc::dispatch(self : Doc, ty : String, target : @html.Elem?, extra? : Array[(String, @js.Value)] = []) -> Bool {
  let r = self.realm
  let ev = self.event(ty, target, extra)
  let path : Array[(Int, @js.Value)] = []
  let mut at = target
  while at is Some(e) {
    path.push((uid_of(e), self.wrap(e)))
    at = self.parent(e)
  }
  path.push((-1, self.document()))
  path.push((-2, O(r.global_obj)))
  for p in path {
    ev.props["currentTarget"] = Data(p.1)
    match self.listeners.get(p.0) {
      Some(ls) =>
        for l in ls.copy() {
          if l.0 == ty {
            let _ = r.call(l.1, p.1, [O(ev)]) catch {
              @js.Throw(v) => {
                r.log.push("error: " + r.to_display(v))
                Undefined
              }
            }
          }
        }
      None => ()
    }
    // an on<type> attribute's handler: its code a function of the event, `this` the element
    match path_elem(self, p.0) {
      Some(e) =>
        match e.attr("on" + ty) {
          Some(code) => {
            let _ = (try {
              let f = r.run("(function (event) {\n" + code + "\n})")
              r.call(f, p.1, [O(ev)])
            } catch {
              @js.Throw(v) => {
                r.log.push("error: " + r.to_display(v))
                Undefined
              }
            })
          }
          None => ()
        }
      None => ()
    }
    // a property set to a function
    match p.1 {
      O(o) =>
        match o.props.get("on" + ty) {
          Some(Data(f)) if f.is_callable() => {
            let _ = r.call(f, p.1, [O(ev)]) catch {
              @js.Throw(v) => {
                r.log.push("error: " + r.to_display(v))
                Undefined
              }
            }
          }
          _ => ()
        }
      _ => ()
    }
    if ev.props.get("@@stopped") is Some(Data(B(true))) {
      break
    }
  }
  r.drain()
  !(ev.props.get("defaultPrevented") is Some(Data(B(true))))
}

///|
/// Whether a listener for `ty` is on `e` or what holds it.
pub fn Doc::listens(self : Doc, e : @html.Elem, ty : String) -> Bool {
  let mut at : @html.Elem? = Some(e)
  while at is Some(x) {
    if x.has("on" + ty) {
      return true
    }
    match self.listeners.get(uid_of(x)) {
      Some(ls) => if ls.iter().any(fn(l) { l.0 == ty }) { return true }
      None => ()
    }
    at = self.parent(x)
  }
  match self.listeners.get(-1) {
    Some(ls) => if ls.iter().any(fn(l) { l.0 == ty }) { return true }
    None => ()
  }
  false
}

///|
fn Doc::add_listener(self : Doc, uid : Int, args : Array[@js.Value]) -> Unit raise @js.Throw {
  let ty = self.realm.to_string(args.get(0).unwrap_or(Undefined))
  let f = args.get(1).unwrap_or(Undefined)
  let f = if f.is_callable() {
    f
  } else {
    // an object with handleEvent
    match f {
      O(_) => {
        let h = self.realm.get(f, "handleEvent")
        if h.is_callable() {
          match self.realm.call(self.realm.get(h, "bind"), h, [f]) {
            x => x
          }
        } else {
          return
        }
      }
      _ => return
    }
  }
  let list = match self.listeners.get(uid) {
    Some(l) => l
    None => {
      let l = []
      self.listeners[uid] = l
      l
    }
  }
  if !list.iter().any(fn(l) { l.0 == ty && @js.strict_equal(l.1, f) }) {
    list.push((ty, f))
  }
  // a load that has happened: told now
  if ty == "DOMContentLoaded" || ty == "load" {
    ()
  }
}

///|
fn Doc::remove_listener(self : Doc, uid : Int, args : Array[@js.Value]) -> Unit raise @js.Throw {
  let ty = self.realm.to_string(args.get(0).unwrap_or(Undefined))
  let f = args.get(1).unwrap_or(Undefined)
  match self.listeners.get(uid) {
    Some(l) =>
      match l.search_by(fn(x) { x.0 == ty && @js.strict_equal(x.1, f) }) {
        Some(i) => l.remove(i) |> ignore
        None => ()
      }
    None => ()
  }
}

///|
fn Doc::document(self : Doc) -> @js.Value {
  match self.wrappers.get(-1) {
    Some(o) => O(o)
    None => abort("the document is made with the doc")
  }
}

///|
/// Nodes a script gives (elements, strings) as the document's.
fn Doc::nodes_of(self : Doc, args : Array[@js.Value]) -> Array[@html.Node] raise @js.Throw {
  let out = []
  for a in args {
    match self.elem_of(a) {
      Some(e) => {
        self.detach(e)
        out.push(@html.Node::Elem(e))
      }
      None =>
        match a {
          O({ kind: Host(uid), .. }) if uid <= -3000000 => {
            // a text node
            match self.texts.get(uid) {
              Some(t) => out.push(Text(t.val))
              None => ()
            }
          }
          _ => out.push(@html.Node::Text(self.realm.to_string(a)))
        }
    }
  }
  out
}

///|
fn Doc::element_methods(self : Doc, p : @js.Obj) -> Unit {
  let r = self.realm
  let el = fn(this) raise @js.Throw { self.this_elem(this) }
  let arg = fn(args : Array[@js.Value], i : Int) { args.get(i).unwrap_or(@js.Value::Undefined) }
  r.method(p, "getAttribute", fn(this, args, r) {
    let name = @html.to_lower(r.to_string(arg(args, 0)))
    match el(this).attr(name) {
      Some(v) => S(v)
      None => Null
    }
  })
  r.method(p, "setAttribute", fn(this, args, r) {
    set_attr(el(this), @html.to_lower(r.to_string(arg(args, 0))), Some(r.to_string(arg(args, 1))))
    self.touch()
    Undefined
  })
  r.method(p, "removeAttribute", fn(this, args, r) {
    set_attr(el(this), @html.to_lower(r.to_string(arg(args, 0))), None)
    self.touch()
    Undefined
  })
  r.method(p, "hasAttribute", fn(this, args, r) { B(el(this).has(@html.to_lower(r.to_string(arg(args, 0))))) })
  r.method(p, "toggleAttribute", fn(this, args, r) {
    let e = el(this)
    let name = @html.to_lower(r.to_string(arg(args, 0)))
    let on = match arg(args, 1) {
      B(f) => f
      _ => !e.has(name)
    }
    set_attr(e, name, if on { Some("") } else { None })
    self.touch()
    B(on)
  })
  r.method(p, "querySelector", fn(this, args, r) {
    match self.query(r.to_string(arg(args, 0)), Some(el(this)), false).get(0) {
      Some(x) => self.wrap(x)
      None => Null
    }
  })
  r.method(p, "querySelectorAll", fn(this, args, r) { r.array(self.query(r.to_string(arg(args, 0)), Some(el(this)), true).map(fn(x) { self.wrap(x) })) })
  r.method(p, "getElementsByClassName", fn(this, args, r) {
    let sel = r.to_string(arg(args, 0)).split(" ").filter(fn(s) { s != "" }).map(fn(s) { "." + s.to_string() }).collect().join("")
    r.array(self.query(sel, Some(el(this)), true).map(fn(x) { self.wrap(x) }))
  })
  r.method(p, "getElementsByTagName", fn(this, args, r) { r.array(self.query(r.to_string(arg(args, 0)), Some(el(this)), true).map(fn(x) { self.wrap(x) })) })
  r.method(p, "closest", fn(this, args, r) {
    let list = match @html.parse_selectors(r.to_string(arg(args, 0))) {
      Some(l) => l
      None => raise r.error("SyntaxError", "not a valid selector")
    }
    let tree = self.tree()
    let mut at : @html.Elem? = Some(el(this))
    while at is Some(x) {
      match tree.els.search_by(fn(pl) { physical_equal(pl.elem, x) }) {
        Some(i) => if list.iter().any(fn(s) { tree.matches(s, i, fn(_, _) { false }) }) { return self.wrap(x) }
        None => ()
      }
      at = self.parent(x)
    }
    Null
  })
  r.method(p, "matches", fn(this, args, r) {
    let list = match @html.parse_selectors(r.to_string(arg(args, 0))) {
      Some(l) => l
      None => raise r.error("SyntaxError", "not a valid selector")
    }
    let tree = self.tree()
    let e = el(this)
    match tree.els.search_by(fn(pl) { physical_equal(pl.elem, e) }) {
      Some(i) => B(list.iter().any(fn(s) { tree.matches(s, i, fn(_, _) { false }) }))
      None => B(false)
    }
  })
  r.method(p, "addEventListener", fn(this, args, _) {
    self.add_listener(uid_of(el(this)), args)
    Undefined
  })
  r.method(p, "removeEventListener", fn(this, args, _) {
    self.remove_listener(uid_of(el(this)), args)
    Undefined
  })
  r.method(p, "dispatchEvent", fn(this, args, r) {
    let ty = r.to_string(r.get(arg(args, 0), "type"))
    B(self.dispatch(ty, Some(el(this))))
  })
  r.method(p, "click", fn(this, _, _) {
    self.dispatch("click", Some(el(this))) |> ignore
    Undefined
  })
  for name in ["focus", "blur", "scrollIntoView", "scrollTo", "select"] {
    r.method(p, name, fn(_, _, _) { Undefined })
  }
  r.method(p, "appendChild", fn(this, args, _) {
    let e = el(this)
    for n in self.nodes_of([arg(args, 0)]) {
      e.kids.push(n)
    }
    self.touch()
    arg(args, 0)
  })
  r.method(p, "append", fn(this, args, _) {
    let e = el(this)
    for n in self.nodes_of(args) {
      e.kids.push(n)
    }
    self.touch()
    Undefined
  })
  r.method(p, "prepend", fn(this, args, _) {
    let e = el(this)
    for i, n in self.nodes_of(args) {
      e.kids.insert(i, n)
    }
    self.touch()
    Undefined
  })
  r.method(p, "replaceChildren", fn(this, args, _) {
    let e = el(this)
    let ns = self.nodes_of(args)
    e.kids.clear()
    for n in ns {
      e.kids.push(n)
    }
    self.touch()
    Undefined
  })
  r.method(p, "insertBefore", fn(this, args, _) {
    let e = el(this)
    let ns = self.nodes_of([arg(args, 0)])
    let at = match self.elem_of(arg(args, 1)) {
      Some(ref) => e.kids.search_by(fn(n) { n is Elem(x) && physical_equal(x, ref) }).unwrap_or(e.kids.length())
      None => e.kids.length()
    }
    for i, n in ns {
      e.kids.insert(at + i, n)
    }
    self.touch()
    arg(args, 0)
  })
  let adjacent = fn(this : @js.Value, args : Array[@js.Value], after : Bool) raise @js.Throw {
    let e = el(this)
    let ns = self.nodes_of(args)
    match self.siblings(e) {
      Some(list) => {
        let i = list.search_by(fn(n) { n is Elem(x) && physical_equal(x, e) }).unwrap_or(list.length())
        for k, n in ns {
          list.insert(if after { i + 1 + k } else { i + k }, n)
        }
      }
      None => ()
    }
    self.touch()
    @js.Value::Undefined
  }
  r.method(p, "before", fn(this, args, _) { adjacent(this, args, false) })
  r.method(p, "after", fn(this, args, _) { adjacent(this, args, true) })
  r.method(p, "insertAdjacentHTML", fn(this, args, r) {
    let e = el(this)
    let pos = @html.to_lower(r.to_string(arg(args, 0)))
    let ns = @html.parse(r.to_string(arg(args, 1)))
    self.own(ns)
    match pos {
      "beforeend" => for n in ns { e.kids.push(n) }
      "afterbegin" => for i, n in ns { e.kids.insert(i, n) }
      "beforebegin" | "afterend" =>
        match self.siblings(e) {
          Some(list) => {
            let i = list.search_by(fn(n) { n is Elem(x) && physical_equal(x, e) }).unwrap_or(list.length())
            for k, n in ns {
              list.insert(if pos == "afterend" { i + 1 + k } else { i + k }, n)
            }
          }
          None => ()
        }
      _ => ()
    }
    self.touch()
    Undefined
  })
  r.method(p, "removeChild", fn(this, args, _) {
    let e = el(this)
    match self.elem_of(arg(args, 0)) {
      Some(x) =>
        match e.kids.search_by(fn(n) { n is Elem(y) && physical_equal(y, x) }) {
          Some(i) => e.kids.remove(i) |> ignore
          None => ()
        }
      None => ()
    }
    self.touch()
    arg(args, 0)
  })
  r.method(p, "remove", fn(this, _, _) {
    self.detach(el(this))
    self.touch()
    Undefined
  })
  r.method(p, "replaceWith", fn(this, args, _) {
    let e = el(this)
    let ns = self.nodes_of(args)
    match self.siblings(e) {
      Some(list) =>
        match list.search_by(fn(n) { n is Elem(x) && physical_equal(x, e) }) {
          Some(i) => {
            list.remove(i) |> ignore
            for k, n in ns {
              list.insert(i + k, n)
            }
          }
          None => ()
        }
      None => ()
    }
    self.touch()
    Undefined
  })
  r.method(p, "cloneNode", fn(this, args, _) {
    let deep = arg(args, 0).truthy()
    fn copy(e : @html.Elem, deep : Bool) -> @html.Elem {
      let kids = if deep {
        e.kids.map(fn(n) {
          match n {
            Elem(x) => @html.Node::Elem(copy(x, true))
            t => t
          }
        })
      } else {
        []
      }
      { ..e, attrs: e.attrs.filter(fn(a) { a.0 != uid_attr }), kids }
    }

    let c = copy(el(this), deep)
    self.own([Elem(c)])
    self.wrap(c)
  })
  r.method(p, "getBoundingClientRect", fn(_, _, r) {
    // what layout came to is not told back to what is made by it (mbui's rule): the widget's width, no more
    r.object([("x", N(0.0)), ("y", N(0.0)), ("left", N(0.0)), ("top", N(0.0)), ("width", N(self.width)), ("height", N(0.0)), ("right", N(self.width)), ("bottom", N(0.0))])
  })
  r.method(p, "contains", fn(this, args, _) {
    let e = el(this)
    match self.elem_of(arg(args, 0)) {
      Some(x) => {
        let mut at : @html.Elem? = Some(x)
        while at is Some(y) {
          if physical_equal(y, e) {
            return B(true)
          }
          at = self.parent(y)
        }
        B(false)
      }
      None => B(false)
    }
  })
  r.method(p, "animate", fn(_, _, r) { r.object([("finished", Undefined)]) })
}

///|
/// Element `e`'s property `key` as a script reads it (None: not one of the DOM's).
fn Doc::elem_get(self : Doc, e : @html.Elem, key : String) -> @js.Value? raise @js.Throw {
  let r = self.realm
  let s = fn(x : String?) -> @js.Value {
    match x {
      Some(v) => S(v)
      None => S("")
    }
  }
  let el_list = fn(list : Array[@html.Elem]) { r.array(list.map(fn(x) { self.wrap(x) })) }
  let kids = fn() {
    let out = []
    for n in e.kids {
      if n is Elem(x) {
        out.push(x)
      }
    }
    out
  }
  Some(
    match key {
      "id" => s(e.attr("id"))
      "className" => s(e.attr("class"))
      "tagName" | "nodeName" => S(e.tag.to_upper())
      "localName" => S(e.tag)
      "nodeType" => N(1.0)
      "classList" => self.classes(e)
      "style" => self.style_obj(e)
      "dataset" => self.dataset(e)
      "textContent" | "innerText" => S(e.text())
      "innerHTML" => S(@html.serialize(e.kids, skip=fn(a) { a == uid_attr }))
      "outerHTML" => S(@html.serialize([Elem(e)], skip=fn(a) { a == uid_attr }))
      "children" => el_list(kids())
      "childNodes" => el_list(kids())
      "childElementCount" => N(kids().length().to_double())
      "firstElementChild" | "firstChild" =>
        match kids().get(0) {
          Some(x) => self.wrap(x)
          None => Null
        }
      "lastElementChild" | "lastChild" =>
        match kids().last() {
          Some(x) => self.wrap(x)
          None => Null
        }
      "parentElement" | "parentNode" =>
        match self.parent(e) {
          Some(x) => self.wrap(x)
          None => if self.in_doc(e) { self.document() } else { Null }
        }
      "nextElementSibling" | "previousElementSibling" =>
        match self.siblings(e) {
          Some(list) => {
            let els = []
            for n in list {
              if n is Elem(x) {
                els.push(x)
              }
            }
            match els.search_by(fn(x) { physical_equal(x, e) }) {
              Some(i) => {
                let j = if key == "nextElementSibling" { i + 1 } else { i - 1 }
                match els.get(j) {
                  Some(x) => self.wrap(x)
                  None => Null
                }
              }
              None => Null
            }
          }
          None => Null
        }
      "value" =>
        if e.tag == "select" {
          let opts = self.query("option", Some(e), true)
          let chosen = match opts.iter().find_first(fn(o) { o.has("selected") }) {
            Some(o) => Some(o)
            None => opts.get(0)
          }
          match chosen {
            Some(o) => S(o.attr("value").unwrap_or(o.text()))
            None => S("")
          }
        } else if e.tag == "textarea" {
          S(e.text())
        } else {
          s(e.attr("value"))
        }
      "valueAsNumber" => N(@js.string_to_number(e.attr("value").unwrap_or("")))
      "checked" => B(e.has("checked"))
      "disabled" => B(e.has("disabled"))
      "hidden" => B(e.has("hidden"))
      "open" => B(e.has("open"))
      "selected" => B(e.has("selected"))
      "type" => s(e.attr("type"))
      "name" => s(e.attr("name"))
      "href" => s(e.attr("href"))
      "src" => s(e.attr("src"))
      "title" => s(e.attr("title"))
      "placeholder" => s(e.attr("placeholder"))
      "min" | "max" | "step" => s(e.attr(key))
      "clientWidth" | "offsetWidth" | "scrollWidth" => N(self.width)
      "clientHeight" | "offsetHeight" | "scrollHeight" => N(0.0)
      "ownerDocument" => self.document()
      "isConnected" => B(self.in_doc(e))
      _ => return None
    },
  )
}

///|
/// Element `e`'s property `key` written by a script (false: not one of the DOM's: kept on its object).
fn Doc::elem_set(self : Doc, e : @html.Elem, key : String, v : @js.Value) -> Bool raise @js.Throw {
  let r = self.realm
  let flag = fn(name : String) { set_attr(e, name, if v.truthy() { Some("") } else { None }) }
  match key {
    "id" => set_attr(e, "id", Some(r.to_string(v)))
    "className" => set_attr(e, "class", Some(r.to_string(v)))
    "textContent" | "innerText" => {
      e.kids.clear()
      let t = r.to_string(v)
      if t != "" {
        e.kids.push(Text(t))
      }
    }
    "innerHTML" => {
      let ns = @html.parse(r.to_string(v))
      self.own(ns)
      e.kids.clear()
      for n in ns {
        e.kids.push(n)
      }
    }
    "outerHTML" => {
      let ns = @html.parse(r.to_string(v))
      self.own(ns)
      match self.siblings(e) {
        Some(list) =>
          match list.search_by(fn(n) { n is Elem(x) && physical_equal(x, e) }) {
            Some(i) => {
              list.remove(i) |> ignore
              for k, n in ns {
                list.insert(i + k, n)
              }
            }
            None => ()
          }
        None => ()
      }
    }
    "value" =>
      if e.tag == "select" {
        let want = r.to_string(v)
        for o in self.query("option", Some(e), true) {
          set_attr(o, "selected", if o.attr("value").unwrap_or(o.text()) == want { Some("") } else { None })
        }
      } else if e.tag == "textarea" {
        e.kids.clear()
        e.kids.push(Text(r.to_string(v)))
      } else {
        set_attr(e, "value", Some(r.to_string(v)))
      }
    "checked" | "disabled" | "hidden" | "open" | "selected" => flag(key)
    "title" | "href" | "src" | "type" | "name" | "placeholder" | "min" | "max" | "step" =>
      set_attr(e, key, Some(r.to_string(v)))
    "style" => set_attr(e, "style", Some(r.to_string(v)))
    _ => return false
  }
  self.touch()
  true
}

///|
/// A document over `nodes` (the fragment's, owned as they are), scripts run with what `bridge` gives them.
pub fn Doc::new(nodes : Array[@html.Node], bridge : Bridge, now? : Double = 0.0) -> Doc {
  let realm = @js.Realm::new()
  realm.now = now
  let d : Doc = {
    nodes,
    els: {},
    next_uid: 1,
    realm,
    listeners: {},
    wrappers: {},
    touched: false,
    styled: None,
    width: 0.0,
    failed: None,
    observers: [],
    bridge,
    pressing: false,
    texts: {},
  }
  d.own(nodes)
  d.els.each(fn(k, _) { if k >= d.next_uid { d.next_uid = k + 1 } })
  d.install()
  d
}

///|
fn Doc::install(self : Doc) -> Unit {
  let r = self.realm
  let arg = fn(args : Array[@js.Value], i : Int) { args.get(i).unwrap_or(@js.Value::Undefined) }
  // properties of elements, their styles and datasets, as the host works them out
  r.host_get = fn(uid, key) {
    if uid <= -2000000 {
      match self.els.get(-2000000 - uid) {
        Some(e) => match e.attr("data-" + camel_to_kebab(key)) { Some(v) => Some(S(v)); None => Some(Undefined) }
        None => None
      }
    } else if uid <= -1000 {
      match self.els.get(-1000 - uid) {
        Some(e) => {
          let name = camel_to_kebab(key)
          let ds = style_decls(e)
          match ds.search_by(fn(d) { d.0 == name }) {
            Some(i) => Some(S(ds[i].1))
            None => if key == "length" { Some(N(ds.length().to_double())) } else { Some(S("")) }
          }
        }
        None => None
      }
    } else {
      match self.els.get(uid) {
        Some(e) => self.elem_get(e, key)
        None => None
      }
    }
  }
  r.host_set = fn(uid, key, v) {
    if uid <= -2000000 {
      match self.els.get(-2000000 - uid) {
        Some(e) => {
          set_attr(e, "data-" + camel_to_kebab(key), Some(r.to_string(v)))
          self.touch()
          true
        }
        None => false
      }
    } else if uid <= -1000 {
      match self.els.get(-1000 - uid) {
        Some(e) => {
          set_style(e, camel_to_kebab(key), r.to_string(v))
          self.touch()
          true
        }
        None => false
      }
    } else {
      match self.els.get(uid) {
        Some(e) => self.elem_set(e, key, v)
        None => false
      }
    }
  }
  // the document
  let doc = r.new_obj()
  self.wrappers[-1] = doc
  r.define_global("document", O(doc))
  r.method(doc, "getElementById", fn(_, args, r) {
    let id = r.to_string(arg(args, 0))
    match self.query("[id=\"" + id.replace_all(old="\"", new="\\\"") + "\"]", None, false).get(0) {
      Some(x) => self.wrap(x)
      None => Null
    }
  })
  r.method(doc, "querySelector", fn(_, args, r) {
    match self.query(r.to_string(arg(args, 0)), None, false).get(0) {
      Some(x) => self.wrap(x)
      None => Null
    }
  })
  r.method(doc, "querySelectorAll", fn(_, args, r) { r.array(self.query(r.to_string(arg(args, 0)), None, true).map(fn(x) { self.wrap(x) })) })
  r.method(doc, "getElementsByClassName", fn(_, args, r) {
    let sel = r.to_string(arg(args, 0)).split(" ").filter(fn(s) { s != "" }).map(fn(s) { "." + s.to_string() }).collect().join("")
    r.array(self.query(sel, None, true).map(fn(x) { self.wrap(x) }))
  })
  r.method(doc, "getElementsByTagName", fn(_, args, r) { r.array(self.query(r.to_string(arg(args, 0)), None, true).map(fn(x) { self.wrap(x) })) })
  r.method(doc, "createElement", fn(_, args, r) {
    let tag = @html.to_lower(r.to_string(arg(args, 0)))
    let e : @html.Elem = { tag, attrs: [], kids: [], svg: tag == "svg" }
    self.own([Elem(e)])
    self.wrap(e)
  })
  r.method(doc, "createElementNS", fn(_, args, r) {
    let tag = r.to_string(arg(args, 1))
    let e : @html.Elem = { tag, attrs: [], kids: [], svg: true }
    self.own([Elem(e)])
    self.wrap(e)
  })
  r.method(doc, "createTextNode", fn(_, args, r) {
    let uid = -3000000 - self.texts.length()
    self.texts[uid] = Ref(r.to_string(arg(args, 0)))
    O(r.new_obj(kind=Host(uid)))
  })
  r.method(doc, "createDocumentFragment", fn(_, _, _) {
    let e : @html.Elem = { tag: "div", attrs: [("style", "display: contents")], kids: [], svg: false }
    self.own([Elem(e)])
    self.wrap(e)
  })
  r.method(doc, "addEventListener", fn(_, args, _) {
    self.add_listener(-1, args)
    Undefined
  })
  r.method(doc, "removeEventListener", fn(_, args, _) {
    self.remove_listener(-1, args)
    Undefined
  })
  doc.props["readyState"] = Data(S("loading"))
  let body : @html.Elem = { tag: "body", attrs: [], kids: [], svg: false }
  ignore(body)
  r.accessor(doc, "body", fn(_, _, r) { r.object([]) })
  r.accessor(doc, "documentElement", fn(_, _, r) { r.object([]) })
  // the window
  let win = r.global_obj
  r.method(win, "addEventListener", fn(_, args, _) {
    self.add_listener(-2, args)
    Undefined
  })
  r.method(win, "removeEventListener", fn(_, args, _) {
    self.remove_listener(-2, args)
    Undefined
  })
  r.method(win, "matchMedia", fn(_, args, r) {
    let q = r.to_string(arg(args, 0))
    let env : @html.Env = { width: self.width, dark: false, reduced_motion: false, root_size: 15.0, tokens: [] }
    let m = r.object([("matches", B(@html.media_holds(q, env))), ("media", S(q))])
    match m {
      O(o) => {
        r.method(o, "addEventListener", fn(_, _, _) { Undefined })
        r.method(o, "addListener", fn(_, _, _) { Undefined })
        r.method(o, "removeEventListener", fn(_, _, _) { Undefined })
      }
      _ => ()
    }
    m
  })
  r.method(win, "getComputedStyle", fn(_, args, r) {
    let e = self.elem_of(arg(args, 0))
    let o = r.new_obj()
    r.method(o, "getPropertyValue", fn(_, a, r) {
      let name = r.to_string(arg(a, 0)).trim(chars=" ").to_string()
      S(self.computed(e, name))
    })
    O(o)
  })
  r.define_global("ResizeObserver", r.native("ResizeObserver", fn(this, args, r) {
    let cb = arg(args, 0)
    let watched : Array[Int] = []
    let o = match this {
      O(x) => x
      _ => r.new_obj()
    }
    self.observers.push((cb, O(o), watched))
    r.method(o, "observe", fn(_, a, _) {
      match self.elem_of(arg(a, 0)) {
        Some(e) => watched.push(uid_of(e))
        None => ()
      }
      Undefined
    })
    r.method(o, "unobserve", fn(_, _, _) { Undefined })
    r.method(o, "disconnect", fn(_, _, _) {
      watched.clear()
      Undefined
    })
    O(o)
  }))
  for name in ["MutationObserver", "IntersectionObserver"] {
    r.define_global(name, r.native(name, fn(this, _, r) {
      match this {
        O(o) => {
          r.method(o, "observe", fn(_, _, _) { Undefined })
          r.method(o, "disconnect", fn(_, _, _) { Undefined })
          O(o)
        }
        _ => Undefined
      }
    }))
  }
  r.define_global("vizIcons", r.native("vizIcons", fn(_, _, _) { Undefined }))
  // what the app gives it: window.openai (Codex's names)
  let openai = r.new_obj()
  r.define_global("openai", O(openai))
  r.accessor(openai, "widgetState", fn(_, _, r) {
    match (self.bridge.state)() {
      Some(text) => {
        let json = r.get(O(r.global_obj), "JSON")
        r.call(r.get(json, "parse"), json, [S(text)])
      }
      None => Null
    }
  })
  r.method(openai, "setWidgetState", fn(_, args, r) {
    let json = r.get(O(r.global_obj), "JSON")
    let text = r.to_string(r.call(r.get(json, "stringify"), json, [arg(args, 0)]))
    if text.length() <= 16 * 1024 {
      (self.bridge.keep)(text)
    }
    Undefined
  })
  r.method(openai, "sendFollowUpMessage", fn(_, args, r) {
    // only from a press, as a page's bridge allows it
    if self.pressing {
      let prompt = r.get(arg(args, 0), "prompt")
      (self.bridge.follow_up)(r.to_string(if prompt is Undefined { arg(args, 0) } else { prompt }))
    }
    Undefined
  })
  r.define_global("location", r.object([("href", S("about:srcdoc")), ("hash", S("")), ("search", S(""))]))
  r.define_global("navigator", r.object([("userAgent", S("mbui")), ("language", S("en-US")), ("languages", r.array([S("en-US")]))]))
  r.define_global("devicePixelRatio", N(2.0))
}

///|
/// A custom property's value for element `e` (the root's where none), as the cascade last said it.
fn Doc::computed(self : Doc, e : @html.Elem?, name : String) -> String {
  match self.styled {
    Some(st) => {
      let vars = match e {
        Some(x) =>
          match st.tree.els.search_by(fn(p) { uid_of(p.elem) == uid_of(x) }) {
            Some(i) => st.styles[i].vars
            None => st.root_vars
          }
        None => st.root_vars
      }
      match vars.get(name) {
        Some(v) => @html.subst_vars(v, fn(n) { vars.get(n) }).unwrap_or(v).trim(chars=" ").to_string()
        None => ""
      }
    }
    None => ""
  }
}

///|
/// Its scripts run, in order, then DOMContentLoaded and load told; what threw first kept as why it failed.
pub fn Doc::run_scripts(self : Doc) -> Unit {
  let scripts = []
  fn find(nodes : Array[@html.Node]) {
    for n in nodes {
      if n is Elem(e) {
        if e.tag == "script" {
          let ty = @html.to_lower(e.attr("type").unwrap_or(""))
          if ty == "" || ty == "text/javascript" || ty == "module" || ty == "application/javascript" {
            if e.has("src") {
              self.failed = Some("a script from the network")
            } else {
              scripts.push(e.text())
            }
          }
        } else {
          find(e.kids)
        }
      }
    }
  }

  find(self.nodes)
  for src in scripts {
    if self.failed is Some(_) {
      break
    }
    let _ = self.realm.run(src) catch {
      @js.Throw(v) => {
        self.failed = Some(self.realm.to_display(v))
        Undefined
      }
    }
    self.realm.drain()
  }
  match self.wrappers.get(-1) {
    Some(d) => d.props["readyState"] = Data(S("complete"))
    None => ()
  }
  self.dispatch("DOMContentLoaded", None) |> ignore
  self.dispatch("load", None) |> ignore
  // timers due at once (setTimeout 0): their turn now
  self.realm.advance(self.realm.now)
  // what an error logged as it ran told: it failed
  for l in self.realm.log {
    if l.has_prefix("error: ") && self.failed is None {
      self.failed = Some(l.view(start_offset=7).to_owned())
    }
  }
}

///|
/// The room it is drawn in told to its ResizeObservers (once a width), as a page's would see it laid out.
pub fn Doc::sized(self : Doc, width : Double) -> Unit {
  if width == self.width {
    return
  }
  self.width = width
  let r = self.realm
  for ob in self.observers {
    if ob.2.is_empty() {
      continue
    }
    let entries = ob.2.filter_map(fn(uid) { self.els.get(uid) }).map(fn(e) {
      r.object([("target", self.wrap(e)), ("contentRect", r.object([("width", N(width)), ("height", N(0.0))]))])
    })
    let _ = r.call(ob.0, ob.1, [r.array(entries), ob.1]) catch {
      @js.Throw(v) => {
        r.log.push("error: " + r.to_display(v))
        Undefined
      }
    }
  }
  if !self.observers.is_empty() {
    self.dispatch("resize", None) |> ignore
  }
}

///|
/// Each element of `nodes` given its number (its live document's: a press and a script find it by it).
pub fn assign_uids(nodes : Array[@html.Node]) -> Unit {
  let mut next = 1
  fn go(ns : Array[@html.Node]) {
    for n in ns {
      if n is Elem(e) {
        if uid_of(e) < 0 {
          e.attrs.push((uid_attr, next.to_string()))
        }
        next += 1
        go(e.kids)
      }
    }
  }

  go(nodes)
}

///|
/// Whether `nodes` have a script that runs (not data: application/json).
pub fn has_script(nodes : Array[@html.Node]) -> Bool {
  for n in nodes {
    if n is Elem(e) {
      if e.tag == "script" {
        let ty = @html.to_lower(e.attr("type").unwrap_or(""))
        if ty == "" || ty == "text/javascript" || ty == "module" || ty == "application/javascript" {
          return true
        }
      }
      if has_script(e.kids) {
        return true
      }
    }
  }
  false
}

///|
fn path_elem(d : Doc, uid : Int) -> @html.Elem? {
  if uid < 0 {
    None
  } else {
    d.els.get(uid)
  }
}

///|
/// Whether `nodes` have an on<event> attribute (a handler written in place).
pub fn has_handlers(nodes : Array[@html.Node]) -> Bool {
  for n in nodes {
    if n is Elem(e) {
      if e.attrs.iter().any(fn(a) { a.0.has_prefix("on") }) || has_handlers(e.kids) {
        return true
      }
    }
  }
  false
}
