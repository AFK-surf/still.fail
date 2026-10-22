// Paths as bytes, as os.path has them (Windows: either slash, the drive's)

///|
fn is_sep(c : Byte) -> Bool {
  c == b'/' || (windows && c == b'\\')
}

///|
fn sep() -> Bytes {
  if windows {
    b"\\"
  } else {
    b"/"
  }
}

///|
fn is_abs(p : BytesView) -> Bool {
  if p.length() > 0 && is_sep(p[0]) {
    return true
  }
  windows && p.length() > 2 && p[1] == b':' && is_sep(p[2])
}

///|
fn path_join(a : Bytes, b : Bytes) -> Bytes {
  if is_abs(b) || a.length() == 0 {
    return b
  }
  if is_sep(a[a.length() - 1]) {
    cat([a, b])
  } else {
    cat([a, sep(), b])
  }
}

///|
fn joins(parts : Array[Bytes]) -> Bytes {
  let mut p = parts[0]
  for i in 1..<parts.length() {
    p = path_join(p, parts[i])
  }
  p
}

///|
fn basename(p : Bytes) -> Bytes {
  let mut s = p.length()
  while s > 0 && !is_sep(p[s - 1]) {
    s -= 1
  }
  sub(p, s, p.length())
}

///|
fn dirname(p : Bytes) -> Bytes {
  let mut s = p.length()
  while s > 0 && !is_sep(p[s - 1]) {
    s -= 1
  }
  let mut e = s
  while e > 1 && is_sep(p[e - 1]) {
    e -= 1
  }
  sub(p, 0, e)
}

///|
/// (root, extension): os.path.splitext
fn splitext(p : Bytes) -> (Bytes, Bytes) {
  let b = basename(p)
  let start = p.length() - b.length()
  let mut k = b.length() - 1
  while k > 0 && b[k] != b'.' {
    k -= 1
  }
  // (a leading dot is not an extension's)
  let mut lead = 0
  while lead < b.length() && b[lead] == b'.' {
    lead += 1
  }
  if k <= 0 || k < lead {
    (p, b"")
  } else {
    (sub(p, 0, start + k), sub(p, start + k, p.length()))
  }
}

///|
fn normpath(p : Bytes) -> Bytes {
  if p.length() == 0 {
    return b"."
  }
  let mut prefix = b""
  let mut i = 0
  if windows && p.length() >= 2 && p[1] == b':' {
    prefix = sub(p, 0, 2)
    i = 2
  }
  let absolute = i < p.length() && is_sep(p[i])
  let parts : Array[Bytes] = []
  let mut s = i
  let n = p.length()
  for k in i..=n {
    if k == n || is_sep(p[k]) {
      let part = sub(p, s, k)
      if part.length() == 0 || part == b"." {
        ()
      } else if part == b".." {
        if parts.length() > 0 && parts[parts.length() - 1] != b".." {
          let _ = parts.pop()
        } else if !absolute {
          parts.push(part)
        }
      } else {
        parts.push(part)
      }
      s = k + 1
    }
  }
  let buf = @buffer.new()
  buf.write_bytes(prefix)
  if absolute {
    buf.write_bytes(sep())
  }
  for k, part in parts {
    if k > 0 {
      buf.write_bytes(sep())
    }
    buf.write_bytes(part)
  }
  let out = buf.to_bytes()
  if out.length() == 0 {
    b"."
  } else {
    out
  }
}

///|
fn abspath(p : Bytes) -> Bytes {
  if is_abs(p) {
    normpath(p)
  } else {
    normpath(path_join(c_getcwd(), p))
  }
}

///|
fn realpath(p : Bytes) -> Bytes {
  let r = c_realpath(p)
  if r.length() == 0 {
    abspath(p)
  } else {
    r
  }
}

///|
/// os.path.relpath(p, start)
fn relpath(p : Bytes, start : Bytes) -> Bytes {
  let a = split_parts(abspath(p))
  let b = split_parts(abspath(start))
  let mut k = 0
  while k < a.length() && k < b.length() && a[k] == b[k] {
    k += 1
  }
  let parts = []
  for _ in k..<b.length() {
    parts.push(b"..")
  }
  for i in k..<a.length() {
    parts.push(a[i])
  }
  if parts.length() == 0 {
    b"."
  } else {
    joins(parts)
  }
}

///|
fn split_parts(p : Bytes) -> Array[Bytes] {
  let out = []
  let mut s = 0
  for k in 0..=p.length() {
    if k == p.length() || is_sep(p[k]) {
      if k > s {
        out.push(sub(p, s, k))
      }
      s = k + 1
    }
  }
  out
}

///|
fn path_list() -> Array[Bytes] {
  let v = getenv("PATH").unwrap_or(b"")
  let d = if windows { b';' } else { b':' }
  let out = []
  let mut s = 0
  for k in 0..=v.length() {
    if k == v.length() || v[k] == d {
      if k > s {
        out.push(sub(v, s, k))
      }
      s = k + 1
    }
  }
  out
}

///|
/// shutil.which over `dirs` (default PATH)
fn which(name : Bytes, dirs? : Array[Bytes] = path_list()) -> Bytes? {
  let exts = if windows && !ends(name, b".exe") {
    [b"", b".exe", b".cmd", b".bat"]
  } else {
    [b""]
  }
  let has_sep = name.iter().any(fn(c) { is_sep(c) })
  if has_sep {
    for e in exts {
      let c = cat([name, e])
      if is_file(c) && c_executable(c) != 0 {
        return Some(c)
      }
    }
    return None
  }
  for d in dirs {
    for e in exts {
      let c = path_join(d, cat([name, e]))
      if is_file(c) && c_executable(c) != 0 {
        return Some(c)
      }
    }
  }
  None
}

///|
fn makedirs(p : Bytes) -> Unit {
  let _ = c_mkdir(p)
}

///|
/// os.walk's files under `top` (sorted in each directory), as paths under it
fn walk_files(top : Bytes) -> Array[Bytes] {
  let out = []
  let names = sort_bytes(list_dir(top))
  for n in names {
    let p = path_join(top, n)
    match kind_of_path(p) {
      1 => out.push(p)
      2 =>
        for x in walk_files(p) {
          out.push(x)
        }
      _ => ()
    }
  }
  out
}

///|
fn rmtree(p : Bytes) -> Unit {
  if is_dir(p) {
    for n in list_dir(p) {
      rmtree(path_join(p, n))
    }
    let _ = c_rmdir(p)
  } else {
    let _ = c_remove(p)
  }
}

///|
fn copyfile(src : Bytes, dst : Bytes) -> Bool {
  match read_file(src) {
    Some(d) => write_file(dst, d)
    None => false
  }
}
