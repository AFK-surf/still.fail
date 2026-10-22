// csplit: the one C file moonc generates for a program, split into translation units that compile in parallel
// (mbc.mbt), as the same program: its stable split (moonc's made-up names made stable, a package's functions
// a unit, each unit with only the declarations it uses):
//
//   decls.h    the prelude and every declaration (types, prototypes, #defines), in moonc's order
//   externs.h  an `extern` declaration of each global
//   data.c     decls.h and the globals' definitions (it alone sees each global's definition)
//   init.c     moonbit_init, calling its packages' pieces (init.<package>.c; small ones together, init.s<k>.c)
//   <pkg>.c    a package's functions (a big package's in pieces by source file, <pkg>_<k>.c; small packages
//              together, s<k>.c), with the prelude and only the declarations and externs they use (a struct they
//              only pass by pointer declared, not defined), in an order of their own
//
// `static` on moonc's items becomes CSPLIT_INTERNAL (hidden visibility), so that what one unit defines the others
// can call. Files whose text did not change keep their mtime, so a build can skip the units it compiled already.
//
// Anything this does not recognise stops it rather than guess: an item it cannot classify, a #if among moonc's
// items, a #define after a function body, an item that does not end its line, a name defined twice, an empty result.

///|
suberror SplitError {
  SplitError(String)
}

///|
fn repr(t : BytesView, n : Int) -> String {
  let s = str(t[0:imin(n, t.length())])
  "'" + s.replace_all(old="\n", new="\\n") + "'"
}

///|
/// moonc's file-scope item: kind 0 a preprocessor line, 1 a function definition, 2 anything ending in `;`
struct Item {
  kind : Int
  text : Bytes
  line : Int
}

///|
/// The next token in t[j:e] as items_of's scan sees it (TOKEN at file scope, else BODY_TOKEN): (what, start, end);
/// what: 0 none, 1 //, 2 /*, 3 a literal, 4 a lone quote, 5 {, 6 }, 7 ( or [, 8 ) or ], 9 ;
fn next_token(t : Bytes, j : Int, e : Int, top : Bool) -> (Int, Int, Int) {
  let mut p = j
  while p < e {
    let c = t[p]
    if c == b'/' {
      if p + 1 < e && t[p + 1] == b'/' {
        return (1, p, p + 2)
      }
      if p + 1 < e && t[p + 1] == b'*' {
        return (2, p, p + 2)
      }
    } else if c == b'"' || c == b'\'' {
      let q = lit_end_line(t, p, e)
      return if q < 0 { (4, p, p + 1) } else { (3, p, q) }
    } else if c == b'{' {
      return (5, p, p + 1)
    } else if c == b'}' {
      return (6, p, p + 1)
    } else if top {
      if c == b'(' || c == b'[' {
        return (7, p, p + 1)
      }
      if c == b')' || c == b']' {
        return (8, p, p + 1)
      }
      if c == b';' {
        return (9, p, p + 1)
      }
    }
    p += 1
  }
  (0, e, e)
}

///|
/// moonc's file-scope items in lines [lo, hi) (`ls`: line_starts); a line's number is its index + 1 - lnbase
fn items_of(
  src : Bytes,
  ls : Array[Int],
  lo : Int,
  hi : Int,
  lnbase : Int,
) -> Array[Item] raise SplitError {
  let out : Array[Item] = []
  let mut buf_start = -1 // where the item being read starts (-1: none)
  let mut first = 0
  let mut depth = 0 // braces
  let mut paren = 0 // parentheses and brackets
  let mut in_comment = false
  let mut head_end = -1 // the text before an item's first file-scope `{`: src[buf_start:head_end]
  let mut i = lo
  while i < hi {
    let a = ls[i]
    let e = ls[i + 1]
    let s = {
      let mut k = a
      while k < e && is_space(src[k]) {
        k += 1
      }
      k
    }
    if buf_start < 0 && !in_comment {
      if s == e {
        i += 1
        continue
      }
      if src[s] == b'#' {
        let mut te = e
        while i + 1 < hi {
          let mut k = te
          while k > a && src[k - 1] == b'\n' {
            k -= 1
          }
          if !(k > a && src[k - 1] == b'\\') {
            break
          }
          i += 1
          te = ls[i + 1]
        }
        out.push({ kind: 0, text: sub(src, a, te), line: i + 1 - lnbase })
        i += 1
        continue
      }
    }
    if buf_start < 0 {
      buf_start = a
      first = i + 1 - lnbase
      head_end = -1
    }
    if s < e && src[s] == b'#' && !in_comment {
      // a directive inside an item (moonc's #line in function bodies): no braces of the program in it
      i += 1
      continue
    }
    if depth > 0 && !in_comment {
      let mut plain = true
      let mut opens = 0
      let mut closes = 0
      for k in a..<e {
        let c = src[k]
        if c == b'"' || c == b'\'' || c == b'/' {
          plain = false
          break
        }
        if c == b'{' {
          opens += 1
        } else if c == b'}' {
          closes += 1
        }
      }
      if plain && depth - closes > 0 {
        depth += opens - closes
        i += 1
        continue
      }
    }
    let mut j = a
    let mut ended_kind = -1
    let mut ended_pos = 0
    while true {
      if in_comment {
        let k = find(src[0:e], b"*/", j)
        if k < 0 {
          break
        }
        in_comment = false
        j = k + 2
        continue
      }
      let (tk, ts, tend) = next_token(src, j, e, depth == 0)
      if tk == 0 {
        break
      }
      j = tend
      if tk == 1 {
        break
      }
      if tk == 2 {
        in_comment = true
      } else if tk == 4 {
        raise SplitError(
          "line \{i + 1 - lnbase}: a literal that does not end on its line",
        )
      } else if tk == 5 {
        if depth == 0 && paren == 0 && head_end < 0 {
          head_end = ts
        }
        depth += 1
      } else if tk == 6 {
        depth -= 1
        if depth < 0 {
          raise SplitError("line \{i + 1 - lnbase}: an unmatched }")
        }
        if depth == 0 &&
          paren == 0 &&
          head_end >= 0 &&
          ends(src[buf_start:imax(buf_start, rskip(src[0:head_end], head_end))], b")") {
          ended_kind = 1
          ended_pos = ts
          break
        }
      } else if tk == 7 {
        paren += 1
      } else if tk == 8 {
        paren -= 1
        if paren < 0 {
          raise SplitError(
            "line \{i + 1 - lnbase}: an unmatched \{str(src[ts:tend])}",
          )
        }
      } else if tk == 9 && depth == 0 && paren == 0 {
        ended_kind = 2
        ended_pos = ts
        break
      }
    }
    if ended_kind >= 0 {
      let rest = strip(sub(src, ended_pos + 1, e))
      if rest.length() > 0 && !starts(rest, b"//") {
        raise SplitError(
          "line \{i + 1 - lnbase}: an item that does not end its line (\{repr(rest, 40)} after it)",
        )
      }
      out.push({ kind: ended_kind, text: sub(src, buf_start, e), line: first })
      buf_start = -1
    }
    i += 1
  }
  if buf_start >= 0 && strip(sub(src, buf_start, ls[hi])).length() > 0 {
    raise SplitError("line \{first}: the file ends inside an item")
  }
  if in_comment {
    raise SplitError("the file ends inside a comment")
  }
  out
}

///|
/// `text` without its leading `static`/`inline` (`mark` in their place), and whether it had them.
fn strip_static(text : Bytes, mark : Bytes) -> (Bytes, Bool) {
  let a = lskip(text, 0)
  let mut i = a
  let mut changed = false
  while true {
    let mut e = word_at(text, i, b"static")
    if e < 0 {
      e = word_at(text, i, b"inline")
    }
    if e < 0 {
      break
    }
    i = lskip(text, e)
    changed = true
  }
  (
    cat([
      sub(text, 0, a),
      if changed {
        mark
      } else {
        b""
      },
      sub(text, i, text.length()),
    ]),
    changed,
  )
}

///|
/// what a static of moonc's becomes: a global hidden from outside the program (as a static was), so that the link
/// can still drop or inline it (moonc 0.10.16 makes most functions static)
let internal : Bytes = b"#if defined(__GNUC__) || defined(__clang__)\n#define CSPLIT_INTERNAL __attribute__((visibility(\"hidden\")))\n#else\n#define CSPLIT_INTERNAL\n#endif\n"

///|
fn func_name(text : Bytes, line : Int) -> Bytes raise SplitError {
  let k = find_byte(text, b'{', 0)
  let head = if k >= 0 { sub(text, 0, k) } else { text }
  let flat = top_level(head)
  let p = find_byte(flat, b'(', 0)
  if p < 0 {
    raise SplitError("line \{line}: no parameter list in \{repr(head, 60)}")
  }
  let (s, e) = last_ident(head, p, 0)
  if s < 0 {
    raise SplitError("line \{line}: no function name in \{repr(head, 60)}")
  }
  sub(head, s, e)
}

///|
/// What a 'decl' item is
enum Decl {
  Type
  Proto(Bytes)
  Data(Bytes, Bytes) // its name, its extern declaration
}

///|
/// (struct|union|enum)\s+IDENT\s*(\{\s*\}\s*)?;$
fn tag_decl_only(flat : Bytes) -> Bool {
  let n = flat.length()
  let i = tag_kw(flat, 0, kw_sue)
  if i < 0 {
    return false
  }
  let e = ident_at(flat, i)
  if e < 0 {
    return false
  }
  let mut k = lskip(flat, e)
  if k < n && flat[k] == b'{' {
    let k2 = lskip(flat, k + 1)
    if k2 < n && flat[k2] == b'}' {
      k = lskip(flat, k2 + 1)
    }
  }
  k < n &&
  flat[k] == b';' &&
  (k + 1 == n || (k + 2 == n && flat[k + 1] == b'\n'))
}

///|
fn classify(text : Bytes, line : Int) -> Decl raise SplitError {
  let t = strip(text)
  if word_at(t, 0, b"typedef") >= 0 {
    return Type
  }
  let flat = top_level(t)
  // struct/union/enum declarations and definitions without a declarator
  if tag_decl_only(flat) {
    return Type
  }
  let eq = find_byte(flat, b'=', 0)
  let decl = if eq >= 0 { sub(t, 0, eq) } else { pyslice(t, 0, -1) }
  let flat_decl = if eq >= 0 { sub(flat, 0, eq) } else { pyslice(flat, 0, -1) }
  if has_byte(flat_decl, b',') {
    raise SplitError(
      "line \{line}: more than one declarator in \{repr(t, 80)}",
    )
  }
  if eq < 0 && has_byte(flat_decl, b'(') && ends(rstrip(flat_decl), b")") {
    let p = find_byte(flat_decl, b'(', 0)
    let (s, e) = last_ident(decl, p, 0)
    if s < 0 {
      raise SplitError(
        "line \{line}: a prototype without a name: \{repr(t, 80)}",
      )
    }
    return Proto(sub(decl, s, e))
  }
  // a global: its name is the last identifier at file scope of the declarator (before any [size])
  let mut d = rstrip(flat_decl)
  while ends(d, b"]") {
    let k = rfind_byte(d, b'[')
    if k < 0 {
      raise SplitError("line \{line}: a global without a name: \{repr(t, 80)}")
    }
    d = rstrip(sub(d, 0, k))
  }
  let (s, e) = last_ident(d, d.length(), 0)
  // (re.search(IDENT + '$'): no space before the end)
  if s < 0 || e != rskip(d, d.length()) || e < d.length() - 1 {
    raise SplitError("line \{line}: a global without a name: \{repr(t, 80)}")
  }
  let name = sub(d, s, e)
  if name == b"const" || name == b"volatile" {
    raise SplitError("line \{line}: a global without a name: \{repr(t, 80)}")
  }
  let (ext, _) = strip_static(rstrip(decl), b"")
  if word_at(ext, lskip(ext, 0), b"extern") >= 0 {
    return Proto(name) // a declaration already
  }
  Data(name, cat([b"extern ", lstrip(ext), b";\n"]))
}

///|
/// The name an item defines or declares
fn name_of(text : Bytes) -> Bytes raise SplitError {
  let t = strip(text)
  if ends(t, b"}") {
    return func_name(t, 0)
  }
  match classify(t, 0) {
    Proto(n) => n
    Data(n, _) => n
    Type => b""
  }
}

///|
/// The package in a name moonc mangled (_M0FP24mbui2ui3run: mbui/ui; _M0MPC15array…: core/array; …PB…: the
/// builtins), empty when it has none: _M0[A-Z]*?P(B|C\d|\d), then that many length-prefixed parts.
fn package_of(name : BytesView) -> Bytes {
  let n = name.length()
  if !starts(name, b"_M0") {
    return b""
  }
  let mut k = 3
  let mut count = 0
  let mut core = false
  let mut i = 0
  while true {
    if k + 1 < n && name[k] == b'P' {
      let g = name[k + 1]
      if g == b'B' {
        return b"core/builtin"
      }
      if g == b'C' && k + 2 < n && is_digit(name[k + 2]) {
        count = (name[k + 2] - b'0').to_int()
        core = true
        i = k + 3
        break
      }
      if is_digit(g) {
        count = (g - b'0').to_int()
        i = k + 2
        break
      }
    }
    if k < n && name[k] >= b'A' && name[k] <= b'Z' {
      k += 1
    } else {
      return b""
    }
  }
  let buf = @buffer.new()
  if core {
    buf.write_bytes(b"core/")
  }
  for c in 0..<count {
    let mut d = i
    let mut len = 0
    while d < n && is_digit(name[d]) {
      if len < 100000000 {
        len = len * 10 + (name[d] - b'0').to_int()
      }
      d += 1
    }
    if d == i {
      return b""
    }
    i = d
    if c > 0 {
      buf.write_byte(b'/')
    }
    buf.write_bytesview(name[imin(i, n):imin(i + len, n)])
    i += len
  }
  buf.to_bytes()
}

///|
/// The prelude with each definition of its own that is not static (the software clz/ctz/popcnt, sqrt… a compiler
/// without the builtins gets: MSVC) made `#ifdef CSPLIT_DEFS` (data.c, which defines it) `#else` a declaration:
/// defined once, declared in every unit. Its #ifdef __cplusplus blocks stay as they are.
fn prelude_definitions(prelude : Bytes) -> (Bytes, Int) {
  let ls = line_starts(prelude)
  let nl = ls.length() - 1
  let out = @buffer.new()
  let mut count = 0
  let mut seg_lo = -1
  let flush = fn(lo : Int, hi : Int) {
    if lo < 0 || lo >= hi {
      return
    }
    let items = try items_of(prelude, ls, lo, hi, lo) catch {
      _ => {
        // as it was: a definition twice is the link's to find (mbc check)
        out.write_bytesview(prelude[ls[lo]:ls[hi]])
        return
      }
    }
    for it in items {
      let text = it.text
      let b = blank(text)
      let li = lskip(b, 0)
      let lead = b[li:]
      if it.kind == 0 ||
        starts(lead, b"static") ||
        starts(lead, b"typedef") ||
        starts(lead, b"extern") ||
        starts(lead, b"#") {
        out.write_bytes(text)
        continue
      }
      let code = sub(text, li, text.length()) // past the comments before it
      let decl = if it.kind == 1 {
        cat([rstrip(sub(code, 0, find_byte(code, b'{', 0))), b";\n"])
      } else {
        let what = try classify(code, 0) catch {
          _ => {
            out.write_bytes(text)
            continue
          }
        }
        match what {
          Data(_, ext) => ext
          _ => {
            out.write_bytes(text)
            continue
          }
        }
      }
      count += 1
      out.write_bytes(b"#ifdef CSPLIT_DEFS\n")
      out.write_bytes(text)
      if !ends(text, b"\n") {
        out.write_bytes(b"\n")
      }
      out.write_bytes(b"#else\n")
      out.write_bytes(decl)
      out.write_bytes(b"#endif\n")
    }
  }
  let mut depth = 0 // inside #ifdef __cplusplus … #endif
  for i in 0..<nl {
    let line = prelude[ls[i]:ls[i + 1]]
    let d = strip(line.to_bytes())
    if depth > 0 {
      out.write_bytesview(line)
      if directive_is(d, [b"if", b"ifdef", b"ifndef"]) {
        depth += 1
      } else if directive_is(d, [b"endif"]) {
        depth -= 1
      }
      continue
    }
    if ifdef_cplusplus(d) {
      flush(seg_lo, i)
      seg_lo = -1
      out.write_bytesview(line)
      depth = 1
      continue
    }
    if seg_lo < 0 {
      seg_lo = i
    }
  }
  flush(seg_lo, nl)
  (out.to_bytes(), count)
}

///|
/// #\s*ifdef\s+__cplusplus\b
fn ifdef_cplusplus(d : Bytes) -> Bool {
  if d.length() == 0 || d[0] != b'#' {
    return false
  }
  let i = lskip(d, 1)
  if !starts_at(d, i, b"ifdef") {
    return false
  }
  let k = lskip(d, i + 5)
  k > i + 5 && word_at(d, k, b"__cplusplus") >= 0
}

///|
struct Func {
  name : Bytes
  text : Bytes
  line : Int
}

///|
/// What split made: the files it wrote, in their order, and the manifest's numbers
struct Split {
  files : Array[(Bytes, Int)] // (name, characters), written already
  changed : Int // how many of them were written (the others were as they are)
  functions : Int
  globals : Int
  stats : Array[(String, Int)]
  init_bytes : Int
  unit_loads : Array[Int]
  largest_function : Bytes
  made_global : Array[Bytes]
}

///|
/// struct _M0[A-Za-z0-9_$]*;\s*$ at a line's start
fn first_struct_line(line : BytesView) -> Bool {
  if !starts(line, b"struct _M0") {
    return false
  }
  let e = ident_end(line, 10)
  if !(e < line.length() && line[e] == b';') {
    return false
  }
  lskip(line, e + 1) == line.length()
}

///|
fn split(src : Bytes, outdir : Bytes, unit_bytes? : Int = 0) -> Split raise SplitError {
  let ls = line_starts(src)
  let nl = ls.length() - 1
  // the prelude: moonc's own text up to its first item, a declaration of one of its structs
  let mut start = -1
  for k in 0..<nl {
    if first_struct_line(src[ls[k]:ls[k + 1]]) {
      start = k
      break
    }
  }
  if start < 0 {
    raise SplitError(
      "no `struct _M0…;` declaration: not the file moonc generates (or its layout changed)",
    )
  }
  let prelude0 = sub(src, 0, ls[start])
  if count(prelude0, b"#if") != count(prelude0, b"#endif") {
    raise SplitError("the prelude ends inside a #if")
  }
  let (prelude, prelude_defs) = prelude_definitions(prelude0)
  tick("read, prelude")
  let items = items_of(src, ls, start, nl, 0)
  tick("items")
  let decls : Array[Bytes] = []
  let externs : Array[Bytes] = []
  let data : Array[Bytes] = []
  let funcs : Array[Func] = []
  // (for the stable split: what each declaration is (0 pp, 1 type, 2 proto: its name), each global's name, what
  // moonc made static by name)
  let decl_kinds : Array[(Int, Bytes)] = []
  let data_names : Array[Bytes] = []
  let static_names = BSet::new()
  let seen : Map[Bytes, Int] = Map::new() // 1 proto, 2 func, 3 data
  let protos = BSet::new()
  let mut statics_dropped = 0
  let mut npp = 0
  let mut ntypes = 0
  let mut nprotos = 0
  let mut first_func = -1
  let mut pp_open = 0
  for it in items {
    if it.kind == 0 {
      let d = strip(it.text)
      if directive_is(d, [b"if", b"ifdef", b"ifndef"]) {
        pp_open += 1
      } else if directive_is(d, [b"endif"]) {
        pp_open -= 1
      } else if !directive_is(d, [b"define", b"undef", b"line", b"pragma"]) &&
        !directive_is(d, [b"else"]) {
        raise SplitError(
          "line \{it.line}: a directive the split does not know: \{repr(d, 60)}",
        )
      }
      if first_func >= 0 {
        raise SplitError(
          "line \{it.line}: \{repr(d, 60)} after the first function definition (line \{first_func}): it would move before code that came before it",
        )
      }
      decls.push(it.text)
      decl_kinds.push((0, b""))
      npp += 1
      continue
    }
    if pp_open != 0 {
      // only `#ifndef X / #define X Y / #endif` guards are allowed among moonc's items
      raise SplitError("line \{it.line}: an item inside a #if")
    }
    let (text, dropped) = strip_static(it.text, b"CSPLIT_INTERNAL ")
    if dropped {
      statics_dropped += 1
    }
    if it.kind == 1 {
      let name = func_name(text, it.line)
      match seen.get(name) {
        Some(w) if w != 1 =>
          raise SplitError("line \{it.line}: \{str(name)} defined twice")
        _ => ()
      }
      seen[name] = 2
      if dropped {
        static_names.add(name)
      }
      funcs.push({ name, text, line: it.line })
      if first_func < 0 {
        first_func = it.line
      }
      continue
    }
    match classify(text, it.line) {
      Type => {
        decls.push(text)
        decl_kinds.push((1, b""))
        ntypes += 1
      }
      Proto(info) => {
        decls.push(text)
        decl_kinds.push((2, info))
        if dropped {
          static_names.add(info)
        }
        if !seen.contains(info) {
          seen[info] = 1
        }
        protos.add(info)
        nprotos += 1
      }
      Data(name, ext) => {
        match seen.get(name) {
          Some(w) if w == 3 || w == 2 =>
            raise SplitError("line \{it.line}: \{str(name)} defined twice")
          _ => ()
        }
        seen[name] = 3
        if dropped {
          static_names.add(name)
        }
        data.push(text)
        data_names.push(name)
        externs.push(ext)
      }
    }
  }
  if pp_open != 0 {
    raise SplitError("moonc's items end inside a #if")
  }
  if funcs.length() == 0 {
    raise SplitError("no function definitions")
  }
  // a function moonc defined before its callers without a prototype: one from its definition, for the other units
  let mut synth = 0
  for f in funcs {
    if !protos.has(f.name) && f.name != b"main" {
      decls.push(
        cat([rstrip(sub(f.text, 0, find_byte(f.text, b'{', 0))), b";\n"]),
      )
      decl_kinds.push((2, f.name))
      synth += 1
    }
  }
  let inits = funcs.filter(fn(f) { f.name == b"moonbit_init" })
  if inits.length() != 1 {
    raise SplitError(
      "\{inits.length()} definitions of moonbit_init (expected 1)",
    )
  }
  if !funcs.iter().any(fn(f) { f.name == b"main" }) {
    raise SplitError("no main")
  }
  let rest = funcs.filter(fn(f) { f.name != b"moonbit_init" })
  let stats : Array[(String, Int)] = [
    ("statics_dropped", statics_dropped),
    ("pp", npp),
    ("types", ntypes),
    ("protos", nprotos),
    ("data", data.length()),
    ("funcs", funcs.length()),
    ("prelude_definitions", prelude_defs),
    ("prototypes_added", synth),
  ]
  split_stable(
    prelude,
    decls,
    decl_kinds,
    externs,
    data,
    data_names,
    funcs,
    inits[0],
    rest,
    static_names,
    stats,
    items.length(),
    unit_bytes,
    outdir,
  )
}
