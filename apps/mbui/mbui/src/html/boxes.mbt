// A widget's boxes: its elements as the cascade styled them, in the shapes what draws them takes (widget/): a flow of
// blocks one under another, a flex or a grid container and its items, a table's rows and cells, a list's items with
// their markers, a run of inline content (its words in pieces, each as its element styles it, with what sits in the
// line whole: an inline-block, an inline-flex, a control), an SVG drawn as a picture, an image, a control. Text is
// collapsed as white-space says; ::before and ::after are pieces of words (or boxes, where they say a size and no
// words). An inline element that holds a block is laid out as a block (CSS splits it round the block; the same here
// where it is the only thing on its line, which is how widgets write it).

///|
pub(all) enum Kind {
  /// blocks one under another (CSS's flow), what it holds block-level boxes
  Flow
  Flex
  Grid
  Table
  TableRow
  TableCell
  /// a list's item: its marker's words ("" none), then a flow
  Item(String)
  /// a line's content: its pieces
  Line(Array[Inline])
  /// an <svg>, written out whole with its styles put in
  Svg(String)
  /// an image: its source and its words
  Img(String, String)
  /// a control: what it is (button, checkbox, radio, range, text, select, textarea, progress, meter) and its words
  Control(String, String)
}

///|
/// A piece of a line: words styled as an element says (its words, its style, the link it is in, the element it is
/// of: -1 none), a box sitting in the line whole, or a line's break.
pub(all) enum Inline {
  Words(String, Style, String, Int)
  Atom(Box)
  Break
}

///|
pub(all) struct Box {
  /// its element (-1: none of its own, a run of words or a pseudo-element)
  el : Int
  tag : String
  style : Style
  kind : Kind
  kids : Array[Box]
}

///|
/// A widget read and styled: its tree of elements and their cascade, its boxes.
pub(all) struct Styled {
  tree : Tree
  styles : Array[Cascaded]
  boxes : Array[Box]
  root : Style
  /// the root's custom properties (the theme's tokens and :root's)
  root_vars : Map[String, String]
}

///|
let unseen_tags : Array[String] = [
  "script", "style", "template", "head", "title", "meta", "link", "noscript", "base", "datalist", "param", "source",
  "track",
]

///|
/// `html` read, styled with `defaults` and its own <style> elements in `env`, its states asked of `state`.
pub fn style_widget(
  html : String,
  defaults : Sheet,
  env : Env,
  state : (Int, State) -> Bool,
  expand? : (Elem) -> String? = fn(_) { None },
  changed? : Map[Int, Array[(String, String?)]] = {},
) -> Styled {
  style_nodes(changed_nodes(parse(html), changed), defaults, env, state, expand~)
}

///|
/// A widget's nodes (its live document's: what is styled shares its elements' attributes) styled as style_widget says.
pub fn style_nodes(
  doc : Array[Node],
  defaults : Sheet,
  env : Env,
  state : (Int, State) -> Bool,
  expand? : (Elem) -> String? = fn(_) { None },
) -> Styled {
  let nodes = expand_nodes(doc, expand)
  let tree = Tree::new(nodes)
  // its own sheets, in the order they are in
  let css = StringBuilder()
  for p in tree.els {
    if p.elem.tag == "style" && !p.elem.svg {
      css.write_string(p.elem.text())
      css.write_char('\n')
    }
  }
  let sheets : Sheets = { defaults, author: parse_sheet(css.to_string(), from=defaults.rules.length()) }
  let root_style = {
    let s = Style::root(env)
    s.display = "block"
    s
  }
  // the root's own: what :root (and html, body) say, given the theme's tokens
  let root : Cascaded = cascade_root(sheets, env, root_style)
  let styles : Array[Cascaded] = []
  for i, p in tree.els {
    let parent = if p.parent >= 0 { styles[p.parent] } else { root }
    styles.push(cascade(tree, sheets, i, "", Some(parent), env, state))
  }
  let b : Builder = { tree, styles, sheets, env, state, root }
  let boxes = b.flow_of(nodes, -1, root.style)
  { tree, styles, boxes, root: root.style, root_vars: root.vars }
}

///|
/// `nodes` with each element `expand` gives markup for (an element of what draws it: a chart) put in its place as
/// that markup reads.
pub fn expand_nodes(nodes : Array[Node], expand : (Elem) -> String?) -> Array[Node] {
  let out = []
  for n in nodes {
    match n {
      Text(_) => out.push(n)
      Elem(e) =>
        match expand(e) {
          Some(m) => for k in parse(m) { out.push(k) }
          None => out.push(Elem({ ..e, kids: expand_nodes(e.kids, expand) }))
        }
    }
  }
  out
}

///|
/// `nodes` with the attributes of their elements (by their place in document order, as Tree numbers them) set as
/// `changed` says (a value, or None: taken away): what using the widget changed of it (a tab chosen, a box ticked).
pub fn changed_nodes(nodes : Array[Node], changed : Map[Int, Array[(String, String?)]]) -> Array[Node] {
  if changed.is_empty() {
    return nodes
  }
  // numbered as Tree::new numbers them: each element, then what it holds, before its next sibling (depth first)
  let mut count = 0
  fn walk(ns : Array[Node]) -> Array[Node] {
    let out = []
    for n in ns {
      match n {
        Text(_) => out.push(n)
        Elem(e) => {
          let i = count
          count += 1
          let attrs = match changed.get(i) {
            Some(cs) => {
              let a = e.attrs.copy()
              for c in cs {
                match (a.search_by(fn(x) { x.0 == c.0 }), c.1) {
                  (Some(j), Some(v)) => a[j] = (c.0, v)
                  (Some(j), None) => a.remove(j) |> ignore
                  (None, Some(v)) => a.push((c.0, v))
                  (None, None) => ()
                }
              }
              a
            }
            None => e.attrs
          }
          out.push(Elem({ ..e, attrs, kids: walk(e.kids) }))
        }
      }
    }
    out
  }

  walk(nodes)
}

///|
/// The root's cascade: rules for :root, html and body, as a fragment's frame (they select no element of it).
fn cascade_root(sheets : Sheets, env : Env, base : Style) -> Cascaded {
  let frame = Tree::new([Elem({ tag: "html", attrs: [], kids: [], svg: false })])
  let html = cascade(frame, sheets, 0, "", None, env, fn(_, _) { false })
  let body_tree = Tree::new([Elem({ tag: "html", attrs: [], kids: [Elem({ tag: "body", attrs: [], kids: [], svg: false })], svg: false })])
  let body = cascade(body_tree, sheets, 1, "", Some(html), env, fn(_, _) { false })
  body.style.display = base.display
  body
}

///|
priv struct Builder {
  tree : Tree
  styles : Array[Cascaded]
  sheets : Sheets
  env : Env
  state : (Int, State) -> Bool
  root : Cascaded
}

///|
/// The element index of each element of `nodes` in document order (their Tree's), starting from `first`.
fn Builder::index_of(self : Builder, e : Elem, parent : Int) -> Int {
  // its element, found among its parent's (or the top's) by being the same object
  if parent >= 0 {
    for k in self.tree.kids[parent] {
      if physical_equal(self.tree.els[k].elem, e) {
        return k
      }
    }
  } else {
    for k, p in self.tree.els {
      if p.parent < 0 && physical_equal(p.elem, e) {
        return k
      }
    }
  }
  -1
}

///|
fn is_block_level(d : String) -> Bool {
  match d {
    "inline" | "inline-block" | "inline-flex" | "inline-grid" | "inline-table" | "contents" | "none" => false
    _ => true
  }
}

///|
fn is_atomic(d : String) -> Bool {
  d == "inline-block" || d == "inline-flex" || d == "inline-grid" || d == "inline-table"
}

///|
/// Whether element `i` holds a block-level box somewhere in its inline content.
fn Builder::holds_block(self : Builder, i : Int) -> Bool {
  for k in self.tree.kids[i] {
    let st = self.styles[k].style
    if st.display == "none" || unseen_tags.contains(self.tree.els[k].elem.tag) {
      continue
    }
    if is_block_level(st.display) && st.position != "absolute" {
      return true
    }
    if st.display == "inline" || st.display == "contents" {
      if self.holds_block(k) {
        return true
      }
    }
  }
  false
}

///|
/// Whether element `i` holds an input.
fn Builder::holds_input(self : Builder, i : Int) -> Bool {
  for k in self.tree.kids[i] {
    if self.tree.els[k].elem.tag == "input" || self.holds_input(k) {
      return true
    }
  }
  false
}

///|
/// What a node of the fragment comes to among its siblings: block-level boxes, or inline pieces.
priv enum Part {
  BlockPart(Box)
  InlinePart(Inline)
}

///|
/// The parts of `nodes` (children of element `parent`, -1 the fragment), styled under `pst`; `items`: they are a flex or
/// grid container's, each element a box of its own (blockified, as CSS says), so its width and the like hold.
fn Builder::parts_of(
  self : Builder,
  nodes : Array[Node],
  parent : Int,
  pst : Style,
  out : Array[Part],
  items? : Bool = false,
) -> Unit {
  for n in nodes {
    match n {
      Text(t) => out.push(InlinePart(Words(t, pst, "", parent)))
      Elem(e) => {
        let i = self.index_of(e, parent)
        if i < 0 || unseen_tags.contains(e.tag) {
          continue
        }
        let st = self.styles[i].style
        if st.display == "none" || e.has("hidden") {
          continue
        }
        if st.display == "contents" {
          self.parts_of(e.kids, i, st, out, items~)
          continue
        }
        if e.tag == "br" {
          out.push(InlinePart(Break))
          continue
        }
        let block = is_block_level(st.display) || st.position == "absolute"
        let replaced = self.replaced(e, i, st)
        match replaced {
          Some(b) => {
            if block {
              out.push(BlockPart(b))
            } else {
              out.push(InlinePart(Atom(b)))
            }
            continue
          }
          None => ()
        }
        // a label holding what it ticks is pressed whole: a box of its own in the line
        let pressed_whole = e.tag == "label" && self.holds_input(i)
        if block {
          out.push(BlockPart(self.element_box(e, i, st)))
        } else if items && !pressed_whole && !is_atomic(st.display) {
          out.push(BlockPart(self.element_box(e, i, { ..st, display: "block" })))
        } else if pressed_whole && !is_atomic(st.display) {
          out.push(InlinePart(Atom(self.element_box(e, i, { ..st, display: "inline-flex", align_items: "center" }))))
        } else if is_atomic(st.display) {
          out.push(InlinePart(Atom(self.element_box(e, i, st))))
        } else if self.holds_block(i) {
          // an inline element holding a block: a block of its own
          let b = self.element_box(e, i, { ..st, display: "block" })
          out.push(BlockPart(b))
        } else {
          // inline: its pieces, ::before and ::after round them
          let link = if e.tag == "a" { e.attr("href").unwrap_or("#") } else { "" }
          self.pseudo(i, "before", st, out)
          let inner = []
          self.parts_of(e.kids, i, st, inner)
          for p in inner {
            match p {
              InlinePart(Words(w, s, l, el)) => out.push(InlinePart(Words(w, s, if l == "" { link } else { l }, el)))
              other => out.push(other)
            }
          }
          self.pseudo(i, "after", st, out)
          // an empty inline element with a size of its own (an icon's mark) or a ground with room (a dot, a swatch) is
          // a box in the line
          if inner.is_empty() {
            let sized = st.width != Auto && st.height != Auto
            let grounded = (st.background != 0L || st.border_width.iter().any(fn(w) { w > 0.0 })) &&
              (st.width != Auto || st.padding.iter().any(fn(p) { p != Len::px(0.0) }))
            if sized || grounded {
              out.push(InlinePart(Atom({ el: i, tag: e.tag, style: { ..st, display: "inline-block" }, kind: Flow, kids: [] })))
            }
          }
        }
      }
    }
  }
}

///|
/// A pseudo-element of element `i` (`which`: before, after), if its content says one: words, or a box where it
/// says a size and no words.
fn Builder::pseudo(self : Builder, i : Int, which : String, pst : Style, out : Array[Part]) -> Unit {
  // only where a rule says one
  let c = cascade(self.tree, self.sheets, i, which, Some(self.styles[i]), self.env, self.state)
  match c.style.content {
    None => ()
    Some(text) => {
      ignore(pst)
      if c.style.display == "none" {
        return
      }
      if text == "" {
        if c.style.width != Auto || c.style.height != Auto {
          let b : Box = { el: -1, tag: "::" + which, style: c.style, kind: Flow, kids: [] }
          if is_block_level(c.style.display) || c.style.position == "absolute" {
            out.push(BlockPart(b))
          } else {
            out.push(InlinePart(Atom(b)))
          }
        }
      } else {
        out.push(InlinePart(Words(text, c.style, "", -1)))
      }
    }
  }
}

///|
/// Element `e` (index `i`) as a replaced box, where it is one (svg, img, a control).
fn Builder::replaced(self : Builder, e : Elem, i : Int, st : Style) -> Box? {
  let control = fn(what : String, words : String) -> Box? {
    Some({ el: i, tag: e.tag, style: st, kind: Control(what, words), kids: [] })
  }
  match e.tag {
    "svg" => Some({ el: i, tag: "svg", style: st, kind: Svg(self.svg_markup(e, i)), kids: [] })
    "img" => Some({ el: i, tag: "img", style: st, kind: Img(e.attr("src").unwrap_or(""), e.attr("alt").unwrap_or("")), kids: [] })
    "input" => {
      let ty = to_lower(e.attr("type").unwrap_or("text"))
      match ty {
        "hidden" => None
        "checkbox" | "radio" | "range" | "color" => control(ty, e.attr("value").unwrap_or(""))
        "button" | "submit" | "reset" => control("button", e.attr("value").unwrap_or(""))
        _ => control("text", e.attr("value").unwrap_or(e.attr("placeholder").unwrap_or("")))
      }
    }
    "select" => {
      // its chosen option's words (the first where none is chosen)
      let mut words = ""
      let mut first = ""
      fn go(n : Node) {
        if n is Elem(o) {
          if o.tag == "option" {
            if first == "" {
              first = o.text()
            }
            if o.has("selected") {
              words = o.text()
            }
          } else {
            for k in o.kids {
              go(k)
            }
          }
        }
      }
      for k in e.kids {
        go(k)
      }
      control("select", if words != "" { words } else { first })
    }
    "textarea" => control("textarea", e.text())
    "progress" | "meter" => control(e.tag, e.attr("value").unwrap_or("0") + "/" + e.attr("max").unwrap_or("1"))
    "iframe" | "canvas" | "video" | "audio" | "object" | "embed" => None
    _ => None
  }
}

///|
/// Element `i`'s own box, what it holds laid out as its display says.
fn Builder::element_box(self : Builder, e : Elem, i : Int, st : Style) -> Box {
  let d = st.display
  match d {
    "flex" | "inline-flex" =>
      { el: i, tag: e.tag, style: st, kind: Flex, kids: self.items_of(e.kids, i, st) }
    "grid" | "inline-grid" =>
      { el: i, tag: e.tag, style: st, kind: Grid, kids: self.items_of(e.kids, i, st) }
    "table" | "inline-table" =>
      { el: i, tag: e.tag, style: st, kind: Table, kids: self.rows_of(e.kids, i, st) }
    "table-row" =>
      { el: i, tag: e.tag, style: st, kind: TableRow, kids: self.cells_of(e.kids, i, st) }
    "table-cell" | "table-caption" =>
      { el: i, tag: e.tag, style: st, kind: TableCell, kids: self.flow_of(e.kids, i, st) }
    "list-item" => {
      let marker = self.marker_of(i, st)
      { el: i, tag: e.tag, style: st, kind: Item(marker), kids: self.flow_of(e.kids, i, st) }
    }
    _ => { el: i, tag: e.tag, style: st, kind: Flow, kids: self.flow_of(e.kids, i, st) }
  }
}

///|
/// A list item's marker: its list's kind of marker, its place among the items for a numbered one.
fn Builder::marker_of(self : Builder, i : Int, st : Style) -> String {
  let ls = st.list_style
  match ls {
    "none" => ""
    "disc" => "•"
    "circle" => "◦"
    "square" => "▪"
    _ => {
      // numbered: counted among its parent's list items, from its list's start
      let p = self.tree.els[i].parent
      let mut n = 0
      let mut start = 1
      let mut reversed = false
      let mut count = 0
      if p >= 0 {
        let list = self.tree.els[p].elem
        match list.attr("start").bind(parse_int) {
          Some(s) => start = s
          None => ()
        }
        reversed = list.has("reversed")
        for k in self.tree.kids[p] {
          if self.styles[k].style.display == "list-item" {
            count += 1
            if k <= i {
              n += 1
            }
          }
        }
      }
      let value = match self.tree.els[i].elem.attr("value").bind(parse_int) {
        Some(v) => v
        None => if reversed { start + count - n } else { start + n - 1 }
      }
      match ls {
        "lower-alpha" | "lower-latin" => alpha_marker(value, false) + "."
        "upper-alpha" | "upper-latin" => alpha_marker(value, true) + "."
        "lower-roman" => to_lower(roman(value)) + "."
        "upper-roman" => roman(value) + "."
        _ => value.to_string() + "."
      }
    }
  }
}

///|
fn alpha_marker(v : Int, upper : Bool) -> String {
  if v <= 0 {
    return v.to_string()
  }
  let b = StringBuilder()
  let mut n = v
  let digits = []
  while n > 0 {
    n -= 1
    digits.push(n % 26)
    n = n / 26
  }
  for k = digits.length() - 1; k >= 0; k = k - 1 {
    b.write_char(Int::unsafe_to_char((if upper { 'A' } else { 'a' }).to_int() + digits[k]))
  }
  b.to_string()
}

///|
fn roman(v : Int) -> String {
  if v <= 0 || v >= 4000 {
    return v.to_string()
  }
  let vals = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
  let syms = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
  let b = StringBuilder()
  let mut n = v
  for k, x in vals {
    while n >= x {
      b.write_string(syms[k])
      n -= x
    }
  }
  b.to_string()
}

///|
/// What a block container holds: its block-level boxes, its inline content in runs between them (each a Line).
fn Builder::flow_of(self : Builder, nodes : Array[Node], parent : Int, pst : Style) -> Array[Box] {
  let parts = []
  if parent >= 0 {
    self.pseudo(parent, "before", pst, parts)
  }
  self.parts_of(nodes, parent, pst, parts)
  if parent >= 0 {
    self.pseudo(parent, "after", pst, parts)
  }
  let out = []
  let line = []
  let close = fn() {
    match line_box(line, pst) {
      Some(b) => out.push(b)
      None => ()
    }
    line.clear()
  }
  for p in parts {
    match p {
      BlockPart(b) => {
        close()
        out.push(b)
      }
      InlinePart(x) => line.push(x)
    }
  }
  close()
  out
}

///|
/// What a flex or grid container holds: each element a box of its own (blockified), each run of text an anonymous
/// item of its words.
fn Builder::items_of(self : Builder, nodes : Array[Node], parent : Int, pst : Style) -> Array[Box] {
  let parts = []
  self.pseudo(parent, "before", pst, parts)
  self.parts_of(nodes, parent, pst, parts, items=true)
  self.pseudo(parent, "after", pst, parts)
  let out = []
  let line = []
  // the child of the container the words in `line` are of (-1: its own text)
  let mut owner = -2
  let close = fn() {
    match line_box(line, pst) {
      Some(b) => out.push(b)
      None => ()
    }
    line.clear()
  }
  for p in parts {
    match p {
      BlockPart(b) => {
        close()
        owner = -2
        out.push(b)
      }
      InlinePart(Atom(b)) => {
        close()
        owner = -2
        out.push(b)
      }
      InlinePart(Words(_, _, _, el) as w) => {
        // each inline child an item of its own, its text runs together one item (CSS's anonymous flex items)
        let child = self.child_of(el, parent)
        if child != owner {
          close()
          owner = child
        }
        line.push(w)
      }
      InlinePart(x) => line.push(x)
    }
  }
  close()
  out
}

///|
/// Which child of element `parent` element `el` is or is in (-1: none, its own text).
fn Builder::child_of(self : Builder, el : Int, parent : Int) -> Int {
  let mut at = el
  while at >= 0 {
    let p = self.tree.els[at].parent
    if p == parent {
      return at
    }
    at = p
  }
  -1
}

///|
/// A table's rows: its row groups' rows, its own, a caption as a cell of its own row.
fn Builder::rows_of(self : Builder, nodes : Array[Node], parent : Int, pst : Style) -> Array[Box] {
  let out = []
  for n in nodes {
    if n is Elem(e) {
      let i = self.index_of(e, parent)
      if i < 0 {
        continue
      }
      let st = self.styles[i].style
      match st.display {
        "none" => ()
        "table-row-group" | "table-header-group" | "table-footer-group" =>
          for r in self.rows_of(e.kids, i, st) {
            out.push(r)
          }
        "table-row" => out.push(self.element_box(e, i, st))
        "table-caption" =>
          out.push({ el: i, tag: e.tag, style: st, kind: Flow, kids: self.flow_of(e.kids, i, st) })
        "table-column" | "table-column-group" => ()
        _ => out.push(self.element_box(e, i, st))
      }
    }
  }
  ignore(pst)
  out
}

///|
fn Builder::cells_of(self : Builder, nodes : Array[Node], parent : Int, pst : Style) -> Array[Box] {
  let out = []
  for n in nodes {
    if n is Elem(e) {
      let i = self.index_of(e, parent)
      if i < 0 {
        continue
      }
      let st = self.styles[i].style
      if st.display == "none" {
        continue
      }
      out.push({ el: i, tag: e.tag, style: st, kind: TableCell, kids: self.flow_of(e.kids, i, st) })
    }
  }
  ignore(pst)
  out
}

///|
/// A run of inline pieces as a line box: its words collapsed as white-space says (spaces running together one, none
/// at its ends); None where nothing is left.
fn line_box(pieces : Array[Inline], pst : Style) -> Box? {
  let out : Array[Inline] = []
  // whether the last thing put ends in a space (or the line's start): a space after it is let go
  let mut after_space = true
  for p in pieces {
    match p {
      Words(t, st, link, el) => {
        let ws = st.white_space
        let text = if ws == "pre" || ws == "pre-wrap" || ws == "break-spaces" {
          after_space = t.has_suffix(" ") || t.has_suffix("\n")
          t
        } else {
          let b = StringBuilder()
          for i in 0..<t.length() {
            let c = t.code_unit_at(i).to_int()
            if c == ' '.to_int() || c == '\t'.to_int() || c == '\r'.to_int() || (c == '\n'.to_int() && ws != "pre-line") {
              if !after_space {
                b.write_char(' ')
                after_space = true
              }
            } else {
              b.write_char(Int::unsafe_to_char(c))
              after_space = c == '\n'.to_int()
            }
          }
          b.to_string()
        }
        // a newline kept (pre, pre-wrap, pre-line) ends the line there
        let parts = text.split("\n").map(fn(x) { x.to_string() }).collect()
        for i, part in parts {
          if i > 0 {
            if ws != "pre" && ws != "pre-wrap" && ws != "break-spaces" {
              trim_end(out)
            }
            out.push(Break)
          }
          if part != "" {
            out.push(Words(transform(part, st.text_transform), st, link, el))
          }
        }
      }
      Atom(_) => {
        out.push(p)
        after_space = false
      }
      Break => {
        // the space before a break let go
        trim_end(out)
        out.push(Break)
        after_space = true
      }
    }
  }
  trim_end(out)
  if out.is_empty() {
    return None
  }
  // a box alone on its line (a picture, a chart) is laid out as a block of its own
  if out is [Atom(a)] && (a.kind is Svg(_) || a.kind is Img(_, _)) {
    return Some(a)
  }
  Some({ el: -1, tag: "", style: pst, kind: Line(out), kids: [] })
}

///|
fn trim_end(out : Array[Inline]) -> Unit {
  while out.length() > 0 {
    match out[out.length() - 1] {
      Words(t, st, l, e) if st.white_space != "pre" && st.white_space != "pre-wrap" => {
        let trimmed = t.trim_end(chars=" ").to_string()
        if trimmed == "" {
          out.pop() |> ignore
        } else {
          out[out.length() - 1] = Words(trimmed, st, l, e)
          return
        }
      }
      _ => return
    }
  }
}

///|
fn transform(t : String, how : String) -> String {
  match how {
    "uppercase" => t.to_upper()
    "lowercase" => t.to_lower()
    "capitalize" => {
      let b = StringBuilder()
      let mut start = true
      for c in t {
        if start && c >= 'a' && c <= 'z' {
          b.write_char(Int::unsafe_to_char(c.to_int() - 32))
        } else {
          b.write_char(c)
        }
        start = c == ' '
      }
      b.to_string()
    }
    _ => t
  }
}

// ── SVG ──────────────────────────────────────────────────────────────

///|
/// The SVG properties written into a drawn SVG's elements as the cascade said them.
let svg_props : Array[String] = [
  "fill", "fill-opacity", "fill-rule", "stroke", "stroke-width", "stroke-opacity", "stroke-dasharray",
  "stroke-dashoffset", "stroke-linecap", "stroke-linejoin", "opacity", "font-size", "font-weight", "font-family",
  "font-style", "text-anchor", "dominant-baseline", "display", "visibility", "stop-color", "stop-opacity", "color",
  "paint-order", "letter-spacing", "transform",
]

///|
/// An <svg> written out whole for the picture renderer: its elements' styles (their style attribute and the rules
/// selecting them) put into each, var() put in, currentColor its colour, its size where it says one in CSS.
fn Builder::svg_markup(self : Builder, e : Elem, i : Int) -> String {
  let b = StringBuilder()
  self.svg_write(e, i, b, true)
  b.to_string()
}

///|
fn css_color_text(c : Int64) -> String {
  let r = ((c >> 24) & 0xFFL).to_int()
  let g = ((c >> 16) & 0xFFL).to_int()
  let bl = ((c >> 8) & 0xFFL).to_int()
  let a = (c & 0xFFL).to_int()
  "rgba(" + r.to_string() + "," + g.to_string() + "," + bl.to_string() + "," + (a.to_double() / 255.0).to_string() + ")"
}

///|
fn xml_escape(s : String) -> String {
  s.replace_all(old="&", new="&amp;").replace_all(old="<", new="&lt;").replace_all(old="\"", new="&quot;")
}

///|
fn Builder::svg_write(self : Builder, e : Elem, i : Int, b : StringBuilder, root : Bool) -> Unit {
  let c = if i >= 0 { Some(self.styles[i]) } else { None }
  let current = match c {
    Some(x) => x.style.color
    None => 0x000000FFL
  }
  let vars = fn(name : String) {
    match c {
      Some(x) => x.vars.get(name)
      None => None
    }
  }
  let put = fn(v : String) -> String {
    let s = subst_vars(v, vars).unwrap_or(v)
    if s.contains("currentColor") || s.contains("currentcolor") {
      s.replace_all(old="currentColor", new=css_color_text(current)).replace_all(old="currentcolor", new=css_color_text(current))
    } else {
      s
    }
  }
  b.write_char('<')
  b.write_string(e.tag)
  if root && !e.has("xmlns") {
    b.write_string(" xmlns=\"http://www.w3.org/2000/svg\"")
  }
  let style = StringBuilder()
  for a in e.attrs {
    if a.0 == "style" || a.0 == "class" || a.0.has_prefix("on") || a.0.has_prefix("data-") || a.0.has_prefix("aria-") {
      continue
    }
    // what the cascade says of a property overrides its attribute
    match c {
      Some(x) if svg_props.contains(a.0) && x.specified.contains(a.0) => continue
      _ => ()
    }
    b.write_string(" " + a.0 + "=\"" + xml_escape(put(a.1)) + "\"")
  }
  match c {
    Some(x) => {
      for p in svg_props {
        match x.specified.get(p) {
          Some(v) if p != "color" => style.write_string(p + ":" + put(v) + ";")
          _ => ()
        }
      }
      if x.style.display == "none" {
        style.write_string("display:none;")
      }
    }
    None => ()
  }
  // the root: its size where CSS says it in points
  if root {
    match c {
      Some(x) => {
        match x.style.width {
          Of(p, 0.0) if p > 0.0 && !e.has("width") => b.write_string(" width=\"" + p.to_string() + "\"")
          _ => ()
        }
        match x.style.height {
          Of(p, 0.0) if p > 0.0 && !e.has("height") => b.write_string(" height=\"" + p.to_string() + "\"")
          _ => ()
        }
        style.write_string("color:" + css_color_text(current) + ";")
        if !x.specified.contains("font-size") {
          style.write_string("font-size:" + x.style.font_size.to_string() + "px;")
        }
      }
      None => ()
    }
  }
  if !style.is_empty() {
    b.write_string(" style=\"" + xml_escape(style.to_string()) + "\"")
  }
  if e.kids.is_empty() {
    b.write_string("/>")
    return
  }
  b.write_char('>')
  for k in e.kids {
    match k {
      Text(t) => b.write_string(xml_escape(t))
      Elem(ke) => {
        let ki = if i >= 0 { self.index_of(ke, i) } else { -1 }
        self.svg_write(ke, ki, b, false)
      }
    }
  }
  b.write_string("</" + e.tag + ">")
}

// ── what is drawn natively ───────────────────────────────────────────

///|
/// Why `html` is not drawn by the app itself (None: it is): what it would need a browser for. Its outside resources (a
/// stylesheet linked, a script's source, an image or a font from the network) and the elements a browser draws by
/// itself (frames, canvas, media). Its own scripts run here; one that fails is said as it runs (widget's failed).
pub fn needs_browser(html : String) -> String? {
  let nodes = parse(html)
  let mut why : String? = None
  fn go(n : Node) {
    if why is Some(_) {
      return
    }
    match n {
      Text(_) => ()
      Elem(e) => {
        match e.tag {
          // a script's own is run here (mbui/js); one from the network is not
          "script" => if e.has("src") { why = Some("a script from the network") }
          "link" => if to_lower(e.attr("rel").unwrap_or("")).contains("stylesheet") { why = Some("stylesheet") }
          "iframe" | "frame" | "canvas" | "video" | "audio" | "object" | "embed" | "form" | "dialog" | "math" =>
            why = Some(e.tag)
          "img" => {
            let src = e.attr("src").unwrap_or("")
            if !src.has_prefix("data:") {
              why = Some("image")
            }
          }
          "style" =>
            if e.text().contains("@import") || e.text().contains("url(http") || e.text().contains("@font-face") {
              why = Some("style resources")
            }
          _ => ()
        }
        for k in e.kids {
          go(k)
        }
      }
    }
  }

  for n in nodes {
    go(n)
  }
  why
}
