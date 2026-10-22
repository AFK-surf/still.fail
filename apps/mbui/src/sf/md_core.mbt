// The core's Markdown tree decoded to this renderer's blocks. Formulas carry only glyph placements; the local
// Markdown reader is kept for old fixture/static texts without a core tree, and never parses a formula.
///|
priv enum MdInline {
  Text(String)
  Code(String)
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
priv struct MdTable { align : Array[@md.Align]; head : Array[Array[MdInline]]; rows : Array[Array[Array[MdInline]]] }
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
      Text(s) | Code(s) | Formula(s, _) | Image(_, s) => out.write_string(s)
      Emph(c) | Strong(c) | Strike(c) | Link(_, c) => out.write_string(md_plain(c))
      SoftBreak | HardBreak => out.write_string(" ")
    }
  }
  out.to_string()
}
///|
fn old_inline(x : @md.Inline) -> MdInline {
  match x {
    Text(s) => Text(s); Code(s) => Code(s)
    Emph(c) => Emph(c.map(old_inline)); Strong(c) => Strong(c.map(old_inline)); Strike(c) => Strike(c.map(old_inline))
    Link(h,c) => Link(h,c.map(old_inline)); Image(s,a) => Image(s,a)
    SoftBreak => SoftBreak; HardBreak => HardBreak
  }
}
///|
fn old_block(x : @md.Block) -> MdBlock {
  match x {
    Paragraph(c) => Paragraph(c.map(old_inline)); Heading(l,c) => Heading(l,c.map(old_inline)); Quote(b) => Quote(b.map(old_block))
    List(l) => List({ ordered:l.ordered, start:l.start, tight:l.tight, items:l.items.map(fn(i) { { task:i.task, blocks:i.blocks.map(old_block) } }) })
    CodeBlock(l,c) => CodeBlock(l,c,None); Rule => Rule
    Table(t) => Table({ align:t.align, head:t.head.map(fn(c){c.map(old_inline)}), rows:t.rows.map(fn(r){r.map(fn(c){c.map(old_inline)})}) })
  }
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
        let align = math_array(math_field(a,"align")).map(fn(x) { match math_string(x) { "left" => @md.Left; "center" => @md.Center; "right" => @md.Right; _ => @md.Plain } })
        out.push(Table({ align, head:if rows.length()>0 {rows[0]}else{[]}, rows:if rows.length()>1 {rows[1:].to_array()}else{[]} }))
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
// The core's ink is a scope letter followed by a UTF-16 length (omitted for one). This only assigns colours to
// already classified runs; it does not interpret the code or its language.
fn core_ink(code : String, ink : String, dark : Bool) -> Array[@ui.Run] {
  let scopes : Array[Scope] = [Text,Comment,Punct,Str,Quote,Num,Control,Storage,Func,Var,Constant,TypeName,Property,PropertyQuote,Added,Removed,Hunk]
  let out = []
  let mut i = 0
  let mut at = 0
  while i < ink.length() && at < code.length() {
    let k = ink.at(i).to_int() - 97
    if k < 0 || k >= scopes.length() { break }
    i += 1
    let mut n = 0
    while i < ink.length() {
      let d = ink.at(i).to_int() - 48
      if d < 0 || d > 9 { break }
      n = imin(code.length(), n * 10 + d)
      i += 1
    }
    let end = imin(code.length(), at + (if n > 0 { n } else { 1 }))
    out.push(@ui.span(code.view(start_offset=at,end_offset=end).to_string(),mono=true,color=if dark {scopes[k].dark()}else{scopes[k].light()}))
    at = end
  }
  if at < code.length() { out.push(@ui.span(code.view(start_offset=at).to_string(),mono=true,color=if dark {Scope::Text.dark()}else{Scope::Text.light()})) }
  out
}
