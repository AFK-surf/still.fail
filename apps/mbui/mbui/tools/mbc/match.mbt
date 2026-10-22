// split_stable's regular expressions, each matched as Python's re did (its pattern above it).

///|
/// \s*\* at i
fn star_after(t : BytesView, i : Int) -> Bool {
  let k = lskip(t, i)
  k < t.length() && t[k] == b'*'
}

///|
/// TAG.findall: \b(?:struct|union|enum)\s+(IDENT)
fn tag_findall(t : BytesView) -> Array[Bytes] {
  let out = []
  let n = t.length()
  let mut p = 0
  while p < n {
    let c = t[p]
    if (c == b's' || c == b'u' || c == b'e') && boundary(t, p) {
      let j = tag_kw(t, p, kw_sue)
      if j >= 0 {
        let e = ident_at(t, j)
        if e >= 0 {
          out.push(t[j:e].to_bytes())
          p = e
          continue
        }
      }
    }
    p += 1
  }
  out
}

///|
/// BY_VALUE.findall (a member of a struct type that is not a pointer to it):
/// \b(?:struct|union|enum)\s+(IDENT)\b(?!\s*\*)
fn by_value_all(t : BytesView) -> Array[Bytes] {
  let out = []
  let n = t.length()
  let mut p = 0
  while p < n {
    let c = t[p]
    if (c == b's' || c == b'u' || c == b'e') && boundary(t, p) {
      let j = tag_kw(t, p, kw_sue)
      if j >= 0 && j < n && is_start(t[j]) {
        let e = ident_end(t, j)
        let mut l = e
        let mut found = -1
        while l > j {
          if boundary(t, l) && !star_after(t, l) {
            found = l
            break
          }
          l -= 1
        }
        if found >= 0 {
          out.push(t[j:found].to_bytes())
          p = found
          continue
        }
      }
    }
    p += 1
  }
  out
}

///|
/// DECL_VAR.finditer, a variable of a struct type or a pointer to one where it is declared:
/// \b(?:struct|union)\s+(IDENT)\s*(\**)\s*(IDENT)\s*(?=[;,)=\[])  as (name, type, pointers)
fn decl_vars(t : BytesView) -> Array[(Bytes, Bytes, Int)] {
  let out = []
  let n = t.length()
  let follows = fn(z : Int) {
    z < n &&
    (t[z] == b';' || t[z] == b',' || t[z] == b')' || t[z] == b'=' || t[z] == b'[')
  }
  let mut p = 0
  while p < n {
    let c = t[p]
    if (c == b's' || c == b'u') && boundary(t, p) {
      let j = tag_kw(t, p, kw_su)
      if j >= 0 && j < n && is_start(t[j]) {
        let e1 = ident_end(t, j)
        let q = lskip(t, e1)
        let mut r = q
        while r < n && t[r] == b'*' {
          r += 1
        }
        let stars = r - q
        let r2 = lskip(t, r)
        let e2 = ident_at(t, r2)
        if e2 >= 0 {
          let z = lskip(t, e2)
          if follows(z) {
            out.push((t[r2:e2].to_bytes(), t[j:e1].to_bytes(), stars))
            p = z
            continue
          }
        }
        // (the type's name shortened, its end taken for the variable's: as the regular expression backtracks)
        let z = lskip(t, e1)
        if follows(z) {
          let mut l = e1 - 1
          while l > j && !is_start(t[l]) {
            l -= 1
          }
          if l > j {
            out.push((t[l:e1].to_bytes(), t[j:l].to_bytes(), 0))
            p = z
            continue
          }
        }
      }
    }
    p += 1
  }
  out
}

///|
/// VAR_USE.finditer: (?<![A-Za-z0-9_$])(IDENT)(?![A-Za-z0-9_$])\s*(->|\[|\.)  as (name, op)
fn var_uses(t : BytesView, f : (Bytes, Bytes) -> Unit) -> Unit {
  let n = t.length()
  let mut p = 0
  while p < n {
    let c = t[p]
    if is_ident(c) {
      let e = ident_end(t, p)
      if is_start(c) && (p == 0 || !is_ident(t[p - 1])) {
        let k = lskip(t, e)
        if starts_at(t, k, b"->") {
          f(t[p:e].to_bytes(), b"->")
          p = k + 2
          continue
        }
        if k < n && (t[k] == b'[' || t[k] == b'.') {
          f(t[p:e].to_bytes(), if t[k] == b'[' { b"[" } else { b"." })
          p = k + 1
          continue
        }
      }
      p = e
    } else {
      p += 1
    }
  }
}

///|
/// ACCESS.finditer, a member's member: (?<!…)(IDENT)(?!…)((?:\s*(?:->|\.)\s*IDENT(?!…))+), its steps (STEP) as
/// (op, member)
fn accesses(t : BytesView, f : (Bytes, Array[(Bytes, Bytes)]) -> Unit) -> Unit {
  let n = t.length()
  let mut p = 0
  while p < n {
    let c = t[p]
    if is_ident(c) {
      let e = ident_end(t, p)
      if is_start(c) && (p == 0 || !is_ident(t[p - 1])) {
        let steps = []
        let mut q = e
        while true {
          let k = lskip(t, q)
          let (op, k2) = if starts_at(t, k, b"->") {
            (b"->", k + 2)
          } else if k < n && t[k] == b'.' {
            (b".", k + 1)
          } else {
            break
          }
          let k3 = lskip(t, k2)
          let e3 = ident_at(t, k3)
          if e3 < 0 {
            break
          }
          steps.push((op, t[k3:e3].to_bytes()))
          q = e3
        }
        if steps.length() > 0 {
          f(t[p:e].to_bytes(), steps)
          p = q
          continue
        }
      }
      p = e
    } else {
      p += 1
    }
  }
}

///|
/// HEADER_OF removed: Moonbit_object_header\s*\([^()]*\)\s*->
fn drop_header_of(t : Bytes) -> Bytes {
  let w = b"Moonbit_object_header"
  let buf = @buffer.new(size_hint=t.length())
  let n = t.length()
  let mut last = 0
  let mut p = 0
  while true {
    let s = find(t, w, p)
    if s < 0 {
      break
    }
    let k = lskip(t, s + w.length())
    let mut end = -1
    if k < n && t[k] == b'(' {
      let mut q = k + 1
      while q < n && t[q] != b'(' && t[q] != b')' {
        q += 1
      }
      if q < n && t[q] == b')' {
        let r = lskip(t, q + 1)
        if starts_at(t, r, b"->") {
          end = r + 2
        }
      }
    }
    if end < 0 {
      p = s + 1
      continue
    }
    buf.write_bytesview(t[last:s])
    last = end
    p = end
  }
  buf.write_bytesview(t[last:])
  buf.to_bytes()
}

///|
/// CAST_ACCESS at p, a member through a cast: \(\s*\(\s*(?:struct|union)\s+(IDENT)\s*\*\s*\)\s*IDENT\s*\)\s*->
/// as (the type's start, end, the match's end), or None
fn cast_access_at(t : BytesView, p : Int) -> (Int, Int, Int)? {
  let n = t.length()
  if t[p] != b'(' {
    return None
  }
  let mut k = lskip(t, p + 1)
  if !(k < n && t[k] == b'(') {
    return None
  }
  k = lskip(t, k + 1)
  let j = tag_kw(t, k, kw_su)
  if j < 0 {
    return None
  }
  let e = ident_at(t, j)
  if e < 0 {
    return None
  }
  k = lskip(t, e)
  if !(k < n && t[k] == b'*') {
    return None
  }
  k = lskip(t, k + 1)
  if !(k < n && t[k] == b')') {
    return None
  }
  k = lskip(t, k + 1)
  let e2 = ident_at(t, k)
  if e2 < 0 {
    return None
  }
  k = lskip(t, e2)
  if !(k < n && t[k] == b')') {
    return None
  }
  k = lskip(t, k + 1)
  if !starts_at(t, k, b"->") {
    return None
  }
  Some((j, e, k + 2))
}

///|
/// CAST_ACCESS's types, and the text without them
fn cast_accesses(t : Bytes) -> (Array[Bytes], Bytes) {
  let out = []
  let buf = @buffer.new(size_hint=t.length())
  let mut last = 0
  let mut p = 0
  while true {
    let s = find_byte(t, b'(', p)
    if s < 0 {
      break
    }
    match cast_access_at(t, s) {
      Some((j, e, end)) => {
        out.push(sub(t, j, e))
        buf.write_bytesview(t[last:s])
        last = end
        p = end
      }
      None => p = s + 1
    }
  }
  buf.write_bytesview(t[last:])
  (out, buf.to_bytes())
}

///|
/// re.search(r'[)\]]\s*(->|\.)')
fn member_after_bracket(t : BytesView) -> Bool {
  let n = t.length()
  for p in 0..<n {
    if t[p] == b')' || t[p] == b']' {
      let k = lskip(t, p + 1)
      if starts_at(t, k, b"->") || (k < n && t[k] == b'.') {
        return true
      }
    }
  }
  false
}

///|
/// SIZEOF.findall: \bsizeof\s*\(\s*(?:struct|union)\s+(IDENT)\s*\)
fn sizeof_all(t : BytesView) -> Array[Bytes] {
  let out = []
  let w = b"sizeof"
  let n = t.length()
  let mut p = 0
  while true {
    let s = find(t, w, p)
    if s < 0 {
      break
    }
    if boundary(t, s) {
      let k = lskip(t, s + 6)
      if k < n && t[k] == b'(' {
        let j = tag_kw(t, lskip(t, k + 1), kw_su)
        if j >= 0 {
          let e = ident_at(t, j)
          if e >= 0 {
            let r = lskip(t, e)
            if r < n && t[r] == b')' {
              out.push(t[j:e].to_bytes())
              p = r + 1
              continue
            }
          }
        }
      }
    }
    p = s + 1
  }
  out
}

///|
/// LAYOUT_RE: (Moonbit_make_regular_object_header\(\s*MOONBIT_REGULAR_LAYOUT_CLASS_INDEXED\s*,\s*)(\d+)(\s*,)
/// each as (the number's start, its end, the match's end)
fn layout_matches(t : BytesView) -> Array[(Int, Int, Int)] {
  let out = []
  let w = b"Moonbit_make_regular_object_header("
  let cls = b"MOONBIT_REGULAR_LAYOUT_CLASS_INDEXED"
  let n = t.length()
  let mut p = 0
  while true {
    let s = find(t, w, p)
    if s < 0 {
      break
    }
    let k = lskip(t, s + w.length())
    if starts_at(t, k, cls) {
      let k2 = lskip(t, k + cls.length())
      if k2 < n && t[k2] == b',' {
        let d1 = lskip(t, k2 + 1)
        let mut d2 = d1
        while d2 < n && is_digit(t[d2]) {
          d2 += 1
        }
        if d2 > d1 {
          let k4 = lskip(t, d2)
          if k4 < n && t[k4] == b',' {
            out.push((d1, d2, k4 + 1))
            p = k4 + 1
            continue
          }
        }
      }
    }
    p = s + 1
  }
  out
}

///|
fn parse_int(t : BytesView) -> Int {
  let mut v = 0
  for i in 0..<t.length() {
    if v < 100000000 {
      v = v * 10 + (t[i] - b'0').to_int()
    }
  }
  v
}

///|
/// LINE_FILE.search: ^\s*#\s*line\s+\d+\s+"([^"]*)"  (re.M)
fn line_file(t : BytesView) -> Bytes? {
  let n = t.length()
  let mut p = 0
  while p <= n {
    let q = lskip(t, p)
    if q < n && t[q] == b'#' {
      let a = lskip(t, q + 1)
      if starts_at(t, a, b"line") {
        let c = lskip(t, a + 4)
        if c > a + 4 {
          let mut d = c
          while d < n && is_digit(t[d]) {
            d += 1
          }
          if d > c {
            let e = lskip(t, d)
            if e > d && e < n && t[e] == b'"' {
              let close = find_byte(t, b'"', e + 1)
              if close >= 0 {
                return Some(t[e + 1:close].to_bytes())
              }
            }
          }
        }
      }
    }
    // (the next line's start past q: those before it come to the same q)
    let nl = find_byte(t, b'\n', q)
    if nl < 0 {
      break
    }
    p = nl + 1
  }
  None
}

///|
/// LINE_DIRECTIVE removed: ^[ \t]*#[ \t]*line\b[^\n]*\n  (re.M)
fn drop_line_directives(t : Bytes) -> Bytes {
  let n = t.length()
  let buf = @buffer.new(size_hint=n)
  let mut p = 0
  while p < n {
    let e = eol(t, p)
    let mut k = p
    while k < e && (t[k] == b' ' || t[k] == b'\t') {
      k += 1
    }
    let mut drop = false
    if k < e && t[k] == b'#' && e < n {
      k += 1
      while k < e && (t[k] == b' ' || t[k] == b'\t') {
        k += 1
      }
      drop = word_at(t[0:e], k, b"line") >= 0
    }
    if !drop {
      buf.write_bytesview(t[p:imin(e + 1, n)])
    }
    p = e + 1
  }
  buf.to_bytes()
}

///|
/// INIT_DECL.match, a local's declaration (its name):
/// \s*(?:const\s+)?(?:struct\s+|union\s+|enum\s+)?IDENT(?:\s*\*\s*|\s+)(?:\*\s*)*(IDENT)\s*;\s*$
fn init_decl(t : BytesView) -> Bytes? {
  let n = t.length()
  let i0 = lskip(t, 0)
  // A jump/return followed by a local-looking name has the same two-word shape as a declaration. It must stay
  // among the statements: hoisting a goto to the declarations skips the initialisation before its label.
  if word_at(t, i0, b"goto") >= 0 || word_at(t, i0, b"return") >= 0 {
    return None
  }
  for use_const in [true, false] {
    let mut i = i0
    if use_const {
      if !starts_at(t, i, b"const") {
        continue
      }
      let j = lskip(t, i + 5)
      if j == i + 5 {
        continue
      }
      i = j
    }
    for use_kw in [true, false] {
      let mut k = i
      if use_kw {
        let kk = tag_kw(t, k, kw_sue)
        if kk < 0 {
          continue
        }
        k = kk
      }
      let e = ident_at(t, k)
      if e < 0 {
        continue
      }
      let mut q = lskip(t, e)
      if q < n && t[q] == b'*' {
        q = lskip(t, q + 1)
      } else if q == e {
        continue
      }
      while q < n && t[q] == b'*' {
        q = lskip(t, q + 1)
      }
      let e2 = ident_at(t, q)
      if e2 < 0 {
        continue
      }
      let r = lskip(t, e2)
      if r < n && t[r] == b';' && lskip(t, r + 1) == n {
        return Some(t[q:e2].to_bytes())
      }
    }
  }
  None
}

///|
/// INIT_OWNER.match: \s*(?:Moonbit_object_header\s*\(\s*)?(_M0F[A-Za-z0-9_$]*)
fn init_owner(t : BytesView) -> Bytes? {
  let n = t.length()
  let i = lskip(t, 0)
  let w = b"Moonbit_object_header"
  if starts_at(t, i, w) {
    let j = lskip(t, i + w.length())
    if j < n && t[j] == b'(' {
      let k = lskip(t, j + 1)
      if starts_at(t, k, b"_M0F") {
        return Some(t[k:ident_end(t, k + 4)].to_bytes())
      }
    }
  }
  if starts_at(t, i, b"_M0F") {
    return Some(t[i:ident_end(t, i + 4)].to_bytes())
  }
  None
}

///|
/// FWD.match: \s*(?:struct|union|enum)\s+IDENT\s*;\s*$
fn is_fwd(t : BytesView) -> Bool {
  let n = t.length()
  let j = tag_kw(t, lskip(t, 0), kw_sue)
  if j < 0 {
    return false
  }
  let e = ident_at(t, j)
  if e < 0 {
    return false
  }
  let k = lskip(t, e)
  k < n && t[k] == b';' && lskip(t, k + 1) == n
}

///|
/// (IDENT)\s*;\s*$ searched, from `lo` on: the name before the last `;`
fn ident_before_semi(t : BytesView, lo : Int) -> Bytes? {
  let k = rskip(t, t.length())
  if !(k > lo && t[k - 1] == b';') {
    return None
  }
  let (s, e) = last_ident(t, k - 1, lo)
  if s < 0 {
    None
  } else {
    Some(t[s:e].to_bytes())
  }
}

///|
/// \s*typedef\b.*?(IDENT)\s*;\s*$ (re.S): what a typedef names
fn typedef_name(t : BytesView) -> Bytes? {
  let te = word_at(t, lskip(t, 0), b"typedef")
  if te < 0 {
    return None
  }
  ident_before_semi(t, te)
}

///|
/// \s*(?:struct|union|enum)\s+(IDENT)
fn tag_name(t : BytesView) -> Bytes? {
  let j = tag_kw(t, lskip(t, 0), kw_sue)
  if j < 0 {
    return None
  }
  let e = ident_at(t, j)
  if e < 0 {
    None
  } else {
    Some(t[j:e].to_bytes())
  }
}

///|
/// \s*struct\s+(_M0TW[A-Za-z0-9_$]*)\s*\{
fn fn_type_def(t : BytesView) -> Bytes? {
  let n = t.length()
  let i = lskip(t, 0)
  if !starts_at(t, i, b"struct") {
    return None
  }
  let k = lskip(t, i + 6)
  if k == i + 6 || !starts_at(t, k, b"_M0TW") {
    return None
  }
  let e = ident_end(t, k + 5)
  let l = lskip(t, e)
  if l < n && t[l] == b'{' {
    Some(t[k:e].to_bytes())
  } else {
    None
  }
}

///|
/// #\s*define\s+(IDENT)
fn define_name(d : BytesView) -> Bytes? {
  if d.length() == 0 || d[0] != b'#' {
    return None
  }
  let i = lskip(d, 1)
  if !starts_at(d, i, b"define") {
    return None
  }
  let k = lskip(d, i + 6)
  if k == i + 6 {
    return None
  }
  let e = ident_at(d, k)
  if e < 0 {
    None
  } else {
    Some(d[k:e].to_bytes())
  }
}

///|
/// \bNAME\b(?!\s*\*) searched
fn named_not_ptr(t : BytesView, name : Bytes) -> Bool {
  let mut p = 0
  while true {
    let s = find(t, name, p)
    if s < 0 {
      return false
    }
    let e = s + name.length()
    if boundary(t, s) && boundary(t, e) && !star_after(t, e) {
      return true
    }
    p = s + 1
  }
  false
}

///|
/// FN_TYPE.sub: \b(_M0TW[A-Za-z0-9_$]*)\b, each replaced by f's answer
fn fn_type_sub(t : BytesView, f : (Bytes) -> Bytes) -> Bytes {
  let n = t.length()
  let buf = @buffer.new(size_hint=n)
  let mut last = 0
  let mut p = 0
  while true {
    let s = find(t, b"_M0TW", p)
    if s < 0 {
      break
    }
    if boundary(t, s) {
      let e = ident_end(t, s + 5)
      let mut l = e
      let mut found = -1
      while l >= s + 5 {
        if boundary(t, l) {
          found = l
          break
        }
        l -= 1
      }
      if found >= 0 {
        buf.write_bytesview(t[last:s])
        buf.write_bytes(f(t[s:found].to_bytes()))
        last = found
        p = found
        continue
      }
    }
    p = s + 1
  }
  buf.write_bytesview(t[last:])
  buf.to_bytes()
}

///|
/// re.sub(r'[^A-Za-z0-9]+', '_', pkg).strip('_') or 'main'
fn unit_label(pkg : Bytes) -> Bytes {
  let buf = @buffer.new()
  let mut gap = false
  let mut wrote = 0
  for i in 0..<pkg.length() {
    let c = pkg[i]
    if (c >= b'a' && c <= b'z') || (c >= b'A' && c <= b'Z') || is_digit(c) {
      if gap && wrote > 0 {
        buf.write_byte(b'_')
      }
      gap = false
      wrote += 1
      buf.write_byte(c)
    } else {
      gap = true
    }
  }
  let t = buf.to_bytes()
  // (leading and trailing underscores: none written; a name's own underscores inside are not alphanumeric either)
  let mut a = 0
  while a < t.length() && t[a] == b'_' {
    a += 1
  }
  let r = sub(t, a, t.length())
  if r.length() == 0 {
    b"main"
  } else {
    r
  }
}

///|
/// re.sub(r'\s+', ' ', w)
fn collapse_space(t : BytesView) -> Bytes {
  let buf = @buffer.new()
  let mut i = 0
  let n = t.length()
  while i < n {
    if is_space(t[i]) {
      while i < n && is_space(t[i]) {
        i += 1
      }
      buf.write_byte(b' ')
    } else {
      buf.write_byte(t[i])
      i += 1
    }
  }
  buf.to_bytes()
}

///|
/// A function's text with its lines as moonc broke them joined (a directive and what ends in a // comment keep
/// theirs): moonc breaks a line by its length, which its made-up names' lengths changed.
fn flatten(t : Bytes) -> Bytes {
  let out = @buffer.new(size_hint=t.length())
  let mut any = false
  let mut cur_open = false
  let n = t.length()
  let put_line_break = fn() {
    if any {
      out.write_byte(b'\n')
    }
    any = true
  }
  let mut p = 0
  while p <= n {
    let e = eol(t, p)
    let st = strip(sub(t, p, e))
    p = e + 1
    if st.length() == 0 {
      continue
    }
    if st[0] == b'#' {
      cur_open = false
      put_line_break()
      out.write_bytes(st)
      continue
    }
    if cur_open {
      out.write_byte(b' ')
    } else {
      put_line_break()
      cur_open = true
    }
    out.write_bytes(st)
    if contains(st, b"//") || ends(st, b"\\") {
      cur_open = false
    }
  }
  out.write_byte(b'\n')
  out.to_bytes()
}
