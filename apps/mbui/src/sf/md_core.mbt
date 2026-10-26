// The core's Markdown tree (client/core-ts/src/markdown.ts) decoded to this renderer's blocks: nothing here reads
// Markdown. Words are runs of the text the tree was read from; formulas carry only glyph placements; a code block its
// ink (ink.mbt).
///|
priv enum MdInline {
  Text(String)
  Code(String)
  /// an inline code naming a file (the tree's `path`): its words as written, its path, the line it points at, a chip's
  /// words (paths.ts)
  FileRef(String, String, Int?, String)
  Formula(String, Json)
  Emph(Array[MdInline])
  Strong(Array[MdInline])
  Strike(Array[MdInline])
  Link(String, Array[MdInline])
  Image(String, String)
  SoftBreak
  HardBreak
}
///|
priv struct MdItem { task : Bool?; blocks : Array[MdBlock] }
///|
priv struct MdList { ordered : Bool; start : Int; tight : Bool; items : Array[MdItem] }
///|
/// How a table's column is aligned (GFM's `:--`, `:-:`, `--:`; none said).
priv enum MdAlign { Plain; Left; Center; Right }
///|
/// `md`, `csv`: the table to copy, as Markdown and as CSV, as the core wrote it (markdown.ts tableMarkdown, tableCsv).
priv struct MdTable { align : Array[MdAlign]; head : Array[Array[MdInline]]; rows : Array[Array[Array[MdInline]]]; md : String; csv : String }
///|
priv enum MdBlock {
  Paragraph(Array[MdInline])
  Heading(Int, Array[MdInline])
  Quote(Array[MdBlock])
  List(MdList)
  CodeBlock(String, String, String?)
  MathBlock(String, Json)
  Rule
  Table(MdTable)
}
///|
fn md_plain(xs : Array[MdInline]) -> String {
  let out = StringBuilder()
  for x in xs {
    match x {
      Text(s) | Code(s) | FileRef(s, _, _, _) | Formula(s, _) | Image(_, s) => out.write_string(s)
      Emph(c) | Strong(c) | Strike(c) | Link(_, c) => out.write_string(md_plain(c))
      SoftBreak | HardBreak => out.write_string(" ")
    }
  }
  out.to_string()
}
///|
fn md_words(j : Json, text : String) -> String? {
  match j {
    String(s) => Some(s)
    Array([Number(a,..),Number(b,..)]) if a >= 0.0 && b >= a && b <= text.length().to_double() =>
      Some(text.view(start_offset=a.to_int(), end_offset=b.to_int()).to_string())
    _ => None
  }
}
///|
fn md_parts(j : Json) -> (String, Array[Json], Json) {
  let a = math_array(j)
  if a.length() < 1 { return ("", [], Json::null()) }
  let name = math_string(a[0])
  if a.length() > 1 && a[1] is Array(children) {
    (name, children, if a.length() > 2 { a[2] } else { Json::null() })
  } else { (name, [], if a.length() > 1 { a[1] } else { Json::null() }) }
}
///|
fn core_inlines(nodes : Array[Json], text : String) -> Array[MdInline] {
  let out = []
  for j in nodes {
    if md_words(j,text) is Some(w) { out.push(MdInline::Text(w)); continue }
    let (name,kids,a) = md_parts(j)
    let words = fn(key) { md_words(math_field(a,key),text).unwrap_or("") }
    match name {
      "code" => {
        let source = words("content")
        if math_field(a,"math") == Json::boolean(true) { out.push(Formula(source,math_field(a,"drawing"))) }
        else if words("path") != "" {
          let line = match math_field(a,"line") { Number(n,..) => Some(n.to_int()); _ => None }
          out.push(FileRef(source, words("path"), line, words("shown")))
        }
        else { out.push(Code(source)) }
      }
      "b" => out.push(Strong(core_inlines(kids,text)))
      "i" => out.push(Emph(core_inlines(kids,text)))
      "s" => out.push(Strike(core_inlines(kids,text)))
      "a" => out.push(Link(words("href"),core_inlines(kids,text)))
      "img" => out.push(Image(words("src"),words("alt")))
      "br" => out.push(HardBreak)
      _ => out.append(core_inlines(kids,text))
    }
  }
  out
}
///|
fn core_blocks(nodes : Array[Json], text : String) -> Array[MdBlock] {
  let out = []
  for j in nodes {
    let (name,kids,a) = md_parts(j)
    match name {
      "p" => out.push(Paragraph(core_inlines(kids,text)))
      "h" => out.push(Heading(math_number(math_field(a,"depth")).to_int(),core_inlines(kids,text)))
      "pre" => {
        let source = md_words(math_field(a,"code"),text).unwrap_or("")
        if math_field(a,"math") == Json::boolean(true) { out.push(MathBlock(source,math_field(a,"drawing"))) }
        else { out.push(CodeBlock(math_string(math_field(a,"lang")),source,Some(math_string(math_field(a,"ink"))))) }
      }
      "quote" => out.push(Quote(core_blocks(kids,text)))
      "list" => {
        let mut tight = true
        let items = kids.map(fn(li) {
          let (_,k,a) = md_parts(li)
          let loose = k.iter().any(fn(j) { let (n,_,_) = md_parts(j); n == "p" })
          if loose { tight = false }
          let checked = match math_field(a,"checked") { True => Some(true); False => Some(false); _ => None }
          { task:checked, blocks:core_item(k,text) }
        })
        let start = math_number(math_field(a,"start")).to_int()
        out.push(List({ ordered:math_field(a,"ordered") == Json::boolean(true), start:if start>0 {start}else{1}, tight, items }))
      }
      "table" => {
        let rows = kids.map(fn(r) { let (_,cells,_) = md_parts(r); cells.map(fn(c) { let (_,k,_) = md_parts(c); core_inlines(k,text) }) })
        let align = math_array(math_field(a,"align")).map(fn(x) { match math_string(x) { "left" => MdAlign::Left; "center" => MdAlign::Center; "right" => MdAlign::Right; _ => MdAlign::Plain } })
        out.push(Table({ align, head:if rows.length()>0 {rows[0]}else{[]}, rows:if rows.length()>1 {rows[1:].to_array()}else{[]}, md:math_string(math_field(a,"md")), csv:math_string(math_field(a,"csv")) }))
      }
      "hr" => out.push(Rule)
      _ => if kids.length() > 0 { out.append(core_blocks(kids,text)) }
    }
  }
  out
}

///|
// Tight items mix words and nested blocks. Preserve both, in order.
fn core_item(nodes : Array[Json], text : String) -> Array[MdBlock] {
  let out : Array[MdBlock] = []
  let words : Array[Json] = []
  let flush = fn() {
    if words.length() > 0 { out.push(Paragraph(core_inlines(words,text))); words.clear() }
  }
  for j in nodes {
    let (name,_,_) = md_parts(j)
    match name {
      "p" | "h" | "list" | "quote" | "pre" | "table" | "hr" => { flush(); out.append(core_blocks([j],text)) }
      _ => words.push(j)
    }
  }
  flush()
  out
}

///|
/// Where in the text a node of the core's tree first has words of the text (its runs, a code's), or -1 (words of its
/// own, as an escape's, have none).
pub fn md_node_at(node : Json) -> Int {
  match node {
    Array([Number(a, ..), Number(_, ..)]) => a.to_int()
    _ => {
      let (_, kids, a) = md_parts(node)
      for key in ["code", "content"] {
        if math_field(a, key) is Array([Number(at, ..), Number(_, ..)]) {
          return at.to_int()
        }
      }
      for k in kids {
        let at = md_node_at(k)
        if at >= 0 {
          return at
        }
      }
      -1
    }
  }
}

///|
/// A heading's level (a node of the core's tree that is one), else None.
pub fn md_node_depth(node : Json) -> Int? {
  match md_parts(node) {
    ("h", _, a) => Some(math_number(math_field(a, "depth")).to_int())
    _ => None
  }
}
