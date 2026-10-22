// The passes over C text csplit makes, each written out as the regular expression it was (kept as comments: the
// comments) matched: the same matches, so the same files.

///|
/// The end of a literal opened at t[p] ("…" or '…'), on one line (`.` not a newline: a backslash before one ends
/// it; the rest of the line may be in it), -1 when it does not end: "(?:\\.|[^"\\])*"
fn lit_end_line(t : BytesView, p : Int, e : Int) -> Int {
  let q = t[p]
  let mut k = p + 1
  while k < e {
    let c = t[k]
    if c == b'\\' {
      if k + 1 < e && t[k + 1] != b'\n' {
        k += 2
        continue
      }
      return -1
    }
    if c == q {
      return k + 1
    }
    k += 1
  }
  -1
}

///|
/// The same with re.S, where a plain character is not a newline: "(?:\\.|[^"\\\n])*"
fn lit_end(t : BytesView, p : Int) -> Int {
  let n = t.length()
  let q = t[p]
  let mut k = p + 1
  while k < n {
    let c = t[k]
    if c == b'\\' {
      if k + 1 < n {
        k += 2
        continue
      }
      return -1
    }
    if c == q {
      return k + 1
    }
    if c == b'\n' {
      return -1
    }
    k += 1
  }
  -1
}

///|
fn eol(t : BytesView, p : Int) -> Int {
  let k = find_byte(t, b'\n', p)
  if k < 0 {
    t.length()
  } else {
    k
  }
}

///|
fn write_spaces(buf : @buffer.Buffer, t : BytesView, i : Int, j : Int) -> Unit {
  for k in i..<j {
    buf.write_byte(if t[k] == b'\n' { b'\n' } else { b' ' })
  }
}

///|
/// `text` with its comments, directives and what is inside its literals replaced by spaces (positions kept):
/// /\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|^[ \t]*#[^\n]* (re.S, re.M)
fn blank(t : BytesView) -> Bytes {
  let n = t.length()
  let buf = @buffer.new(size_hint=n)
  let mut last = 0
  let mut p = 0
  while p < n {
    let c = t[p]
    let mut me = -1
    let mut lit = false
    if c == b'/' && p + 1 < n && t[p + 1] == b'*' {
      let e = find(t, b"*/", p + 2)
      if e >= 0 {
        me = e + 2
      }
    }
    if me < 0 && c == b'/' && p + 1 < n && t[p + 1] == b'/' {
      me = eol(t, p)
    }
    if me < 0 && (c == b'"' || c == b'\'') {
      let q = lit_end(t, p)
      if q >= 0 {
        me = q
        lit = true
      }
    }
    if me < 0 && (p == 0 || t[p - 1] == b'\n') {
      let mut q = p
      while q < n && (t[q] == b' ' || t[q] == b'\t') {
        q += 1
      }
      if q < n && t[q] == b'#' {
        me = eol(t, q)
      }
    }
    if me < 0 {
      p += 1
      continue
    }
    buf.write_bytesview(t[last:p])
    if lit {
      buf.write_byte(c)
      write_spaces(buf, t, p + 1, me - 1)
      buf.write_byte(t[me - 1])
    } else {
      write_spaces(buf, t, p, me)
    }
    last = me
    p = me
  }
  buf.write_bytesview(t[last:n])
  buf.to_bytes()
}

///|
/// `text` with its comments, literals' insides and what is inside braces, parentheses and brackets replaced by
/// spaces (positions kept).
fn top_level(t : BytesView) -> Bytes {
  let b = blank(t)
  let n = b.length()
  let buf = @buffer.new(size_hint=n)
  let mut depth = 0
  for i in 0..<n {
    let c = b[i]
    if c == b'{' || c == b'(' || c == b'[' {
      depth += 1
      buf.write_byte(if depth == 1 { c } else { b' ' })
    } else if c == b'}' || c == b')' || c == b']' {
      buf.write_byte(if depth == 1 { c } else { b' ' })
      depth -= 1
    } else {
      buf.write_byte(if depth == 0 { c } else { b' ' })
    }
  }
  buf.to_bytes()
}

///|
/// Where each line starts (str.splitlines(keepends=True)'s line breaks), and the text's end last
fn line_starts(t : Bytes) -> Array[Int] {
  let n = t.length()
  let out = [0]
  let mut i = 0
  while i < n {
    let c = t[i]
    let e = if c == b'\n' ||
      c == b'\x0b' ||
      c == b'\x0c' ||
      c == b'\x1c' ||
      c == b'\x1d' ||
      c == b'\x1e' {
      i + 1
    } else if c == b'\r' {
      if i + 1 < n && t[i + 1] == b'\n' {
        i + 2
      } else {
        i + 1
      }
    } else if c == b'\xc2' && i + 1 < n && t[i + 1] == b'\x85' {
      i + 2
    } else if c == b'\xe2' &&
      i + 2 < n &&
      t[i + 1] == b'\x80' &&
      (t[i + 2] == b'\xa8' || t[i + 2] == b'\xa9') {
      i + 3
    } else {
      -1
    }
    if e >= 0 {
      out.push(e)
      i = e
    } else {
      i += 1
    }
  }
  if out[out.length() - 1] != n {
    out.push(n)
  }
  out
}

///|
/// The identifier (IDENT) that ends t[0:j] before whitespace (re.search(IDENT + r'\s*$')), as (start, end), or
/// (-1, -1): the run of identifier characters there from its first that may start one. `lo`: not before it.
fn last_ident(t : BytesView, j : Int, lo : Int) -> (Int, Int) {
  let mut e = j
  // ($ before a last newline, \s* the rest)
  while e > lo && is_space(t[e - 1]) {
    e -= 1
  }
  let mut s = e
  while s > lo && is_ident(t[s - 1]) {
    s -= 1
  }
  let mut k = s
  while k < e && !is_start(t[k]) {
    k += 1
  }
  if k >= e {
    (-1, -1)
  } else {
    (k, e)
  }
}

///|
/// The end of the run of identifier characters from i
fn ident_end(t : BytesView, i : Int) -> Int {
  let mut k = i
  while k < t.length() && is_ident(t[k]) {
    k += 1
  }
  k
}

///|
/// An IDENT at i: its end, or -1
fn ident_at(t : BytesView, i : Int) -> Int {
  if i < t.length() && is_start(t[i]) {
    ident_end(t, i)
  } else {
    -1
  }
}

///|
/// A word `w` at i followed by \b (re.match(w + r'\b')): the end, or -1
fn word_at(t : BytesView, i : Int, w : Bytes) -> Int {
  if starts_at(t, i, w) && boundary(t, i + w.length()) {
    i + w.length()
  } else {
    -1
  }
}

///|
/// A directive's name (re.match(r'#\s*(a|b|…)\b', d)): one of `names`
fn directive_is(d : BytesView, names : Array[Bytes]) -> Bool {
  if d.length() == 0 || d[0] != b'#' {
    return false
  }
  let i = lskip(d, 1)
  for w in names {
    if word_at(d, i, w) >= 0 {
      return true
    }
  }
  false
}

///|
/// struct|union|enum followed by \s+ at i: where what follows starts, or -1. `kws`: which of them.
fn tag_kw(t : BytesView, i : Int, kws : Array[Bytes]) -> Int {
  for w in kws {
    if starts_at(t, i, w) {
      let k = i + w.length()
      let e = lskip(t, k)
      if e > k {
        return e
      }
    }
  }
  -1
}

///|
let kw_sue : Array[Bytes] = [b"struct", b"union", b"enum"]

///|
let kw_su : Array[Bytes] = [b"struct", b"union"]

///|
/// A comment or literal at p as SCAN sees them: its end, or -1
fn skip_comment_lit(t : BytesView, p : Int) -> Int {
  let c = t[p]
  let n = t.length()
  if c == b'/' && p + 1 < n {
    if t[p + 1] == b'/' {
      return eol(t, p)
    }
    if t[p + 1] == b'*' {
      let e = find(t, b"*/", p + 2)
      return if e >= 0 { e + 2 } else { -1 }
    }
    return -1
  }
  if c == b'"' || c == b'\'' {
    return lit_end(t, p)
  }
  -1
}

///|
/// The identifiers outside comments and literals, as SCAN finds them:
/// //[^\n]*|/\*.*?\*/|"…"|'…'|([A-Za-z_$][A-Za-z0-9_$]*)|\d[A-Za-z0-9_.]*  (re.S)
/// `f` gets each one's start and end.
fn scan(t : BytesView, f : (Int, Int) -> Unit) -> Unit {
  let n = t.length()
  let mut p = 0
  while p < n {
    let c = t[p]
    if c == b'/' || c == b'"' || c == b'\'' {
      let e = skip_comment_lit(t, p)
      p = if e >= 0 { e } else { p + 1 }
    } else if is_start(c) {
      let e = ident_end(t, p)
      f(p, e)
      p = e
    } else if is_digit(c) {
      let mut e = p + 1
      while e < n && (is_ident(t[e]) || t[e] == b'.') && t[e] != b'$' {
        e += 1
      }
      p = e
    } else {
      p += 1
    }
  }
}

///|
/// A function's scan (split_stable's body_scan): only moonc's names (_…), what ends in a number, and `plain`:
/// …|(?<![A-Za-z0-9_$])(_[A-Za-z0-9_$]*|[A-Za-z$][A-Za-z0-9_$]*\d|plain…)(?![A-Za-z0-9_$])
fn scan_body(t : BytesView, plain : BSet, f : (Int, Int) -> Unit) -> Unit {
  let n = t.length()
  let mut p = 0
  while p < n {
    let c = t[p]
    if c == b'/' || c == b'"' || c == b'\'' {
      let e = skip_comment_lit(t, p)
      p = if e >= 0 { e } else { p + 1 }
    } else if is_ident(c) {
      let e = ident_end(t, p)
      if p > 0 && is_ident(t[p - 1]) {
        // (inside a run that a comment's end left: never, but as the lookbehind says)
        p = e
        continue
      }
      if c == b'_' ||
        (is_start(c) && e - p >= 2 && is_digit(t[e - 1])) ||
        plain.has_range(t, p, e) {
        f(p, e)
      }
      p = e
    } else {
      p += 1
    }
  }
}

///|
fn idents(t : BytesView) -> BSet {
  let s = BSet::new()
  scan(t, fn(i, j) { s.add_range(t, i, j) })
  s
}

///|
let local_not : Array[Bytes] = [b"moonbit", b"Moonbit", b"MOONBIT"]

///|
/// LOCAL: _M0L[A-Za-z0-9_$]*\d$|(?!moonbit|Moonbit|MOONBIT)[A-Za-z_][A-Za-z0-9_$]*_\d+$  (re.match on a name)
fn is_local(t : BytesView) -> Bool {
  let n = t.length()
  if n == 0 {
    return false
  }
  for i in 0..<n {
    if !is_ident(t[i]) {
      return false
    }
  }
  if n >= 5 && starts(t, b"_M0L") && is_digit(t[n - 1]) {
    return true
  }
  for w in local_not {
    if starts(t, w) {
      return false
    }
  }
  if !(is_start(t[0]) && t[0] != b'$') {
    return false
  }
  let mut k = n
  while k > 0 && is_digit(t[k - 1]) {
    k -= 1
  }
  k < n && k - 1 >= 1 && t[k - 1] == b'_'
}

///|
/// rename: `text` with `names` renamed; with local_ok (the identifiers that are not locals), its locals too, by the
/// order they first come in it; with `plain`, scanned as a function's body. Returns the text and the identifiers in
/// it (those the scan looks at).
fn rename(
  t : Bytes,
  names : BTab[Bytes],
  local_ok? : BSet? = None,
  plain? : BSet? = None,
) -> (Bytes, BSet) {
  let used = BSet::new()
  let locals : BTab[Bytes] = BTab::new()
  let buf = @buffer.new(size_hint=t.length())
  let mut last = 0
  let one = fn(s : Int, e : Int) {
    buf.write_bytesview(t[last:s])
    last = e
    let at = names.find_range(t, s, e)
    if at >= 0 {
      let o = names.vals[at]
      used.add(o)
      buf.write_bytes(o)
      return
    }
    match local_ok {
      Some(ok) =>
        if !ok.has_range(t, s, e) && is_local(t[s:e]) {
          // (a struct's member after . or -> is not a local)
          let mut i = s - 1
          while i >= 0 && (t[i] == b' ' || t[i] == b'\t') {
            i -= 1
          }
          if !(i >= 0 &&
            (t[i] == b'.' || (t[i] == b'>' && i > 0 && t[i - 1] == b'-'))) {
            let li = locals.find_range(t, s, e)
            let o = if li >= 0 {
              locals.vals[li]
            } else {
              let l = cat([b"_Ml", bint(locals.length())])
              locals.set(t[s:e].to_bytes(), l)
              l
            }
            used.add(o)
            buf.write_bytes(o)
            return
          }
        }
      None => ()
    }
    used.add_range(t, s, e)
    buf.write_bytesview(t[s:e])
  }
  match plain {
    Some(p) => scan_body(t, p, one)
    None => scan(t, one)
  }
  buf.write_bytesview(t[last:])
  (buf.to_bytes(), used)
}
