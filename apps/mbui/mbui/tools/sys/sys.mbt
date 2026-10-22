// What mbui's tools ask of the system: files whole (text as UTF-8, a bad byte as U+FFFD), a directory's names, a
// path's kind, the environment, the working directory, stdout and stderr, an exit.

///|
extern "C" fn c_ok() -> Int = "tsys_ok"

///|
#borrow(path)
extern "C" fn c_read(path : Bytes) -> Bytes = "tsys_read"

///|
#borrow(path, data)
extern "C" fn c_write(path : Bytes, data : Bytes) -> Int = "tsys_write"

///|
#borrow(path)
extern "C" fn c_kind(path : Bytes) -> Int = "tsys_kind"

///|
#borrow(path)
extern "C" fn c_mkdir(path : Bytes) -> Int = "tsys_mkdir"

///|
#borrow(path)
extern "C" fn c_remove(path : Bytes) -> Int = "tsys_remove"

///|
#borrow(path)
extern "C" fn c_list(path : Bytes) -> Bytes = "tsys_list"

///|
#borrow(name)
extern "C" fn c_getenv(name : Bytes) -> Bytes = "tsys_getenv"

///|
extern "C" fn c_getcwd() -> Bytes = "tsys_getcwd"

///|
#borrow(s)
extern "C" fn c_out(s : Bytes, err : Int) -> Unit = "tsys_out"

///|
extern "C" fn c_exit(code : Int) -> Unit = "tsys_exit"

///|
fn enc(s : String) -> Bytes {
  @utf8.encode(s)
}

///|
fn dec(b : Bytes) -> String {
  @utf8.decode_lossy(b[:])
}

///|
/// A file's text, None when it cannot be read
pub fn read_text(path : String) -> String? {
  let b = c_read(enc(path))
  if c_ok() == 0 {
    None
  } else {
    Some(dec(b))
  }
}

///|
pub fn read_bytes(path : String) -> Bytes? {
  let b = c_read(enc(path))
  if c_ok() == 0 {
    None
  } else {
    Some(b)
  }
}

///|
pub fn write_text(path : String, text : String) -> Bool {
  c_write(enc(path), enc(text)) != 0
}

///|
pub fn write_bytes(path : String, data : Bytes) -> Bool {
  c_write(enc(path), data) != 0
}

///|
pub fn is_file(path : String) -> Bool {
  c_kind(enc(path)) == 1
}

///|
pub fn is_dir(path : String) -> Bool {
  c_kind(enc(path)) == 2
}

///|
pub fn exists(path : String) -> Bool {
  c_kind(enc(path)) != 0
}

///|
/// A directory and those it is in, as os.makedirs
pub fn makedirs(path : String) -> Unit {
  let cs = path.to_array()
  for i in 1..<cs.length() {
    if cs[i] == '/' {
      let _ = c_mkdir(enc(String::from_array(cs[:i])))

    }
  }
  let _ = c_mkdir(enc(path))

}

///|
pub fn remove(path : String) -> Bool {
  c_remove(enc(path)) != 0
}

///|
/// A directory's names (not . and ..), in the order the system gives them
pub fn list_dir(path : String) -> Array[String] {
  let all = c_list(enc(path))
  let out = []
  let mut s = 0
  for i in 0..<all.length() {
    if all[i] == b'\x00' {
      out.push(dec(all[s:i].to_bytes()))
      s = i + 1
    }
  }
  out
}

///|
pub fn getenv(name : String) -> String? {
  let v = c_getenv(enc(name))
  if c_ok() == 0 {
    None
  } else {
    Some(dec(v))
  }
}

///|
pub fn cwd() -> String {
  dec(c_getcwd())
}

///|
/// Text on stdout, as it is (no newline added)
pub fn out(s : String) -> Unit {
  c_out(enc(s), 0)
}

///|
pub fn println_out(s : String) -> Unit {
  c_out(enc(s + "\n"), 0)
}

///|
pub fn eprintln(s : String) -> Unit {
  c_out(enc(s + "\n"), 1)
}

///|
pub fn exit(code : Int) -> Unit {
  c_exit(code)
}

///|
/// os.path.join of two
pub fn join(a : String, b : String) -> String {
  if b.has_prefix("/") || a == "" {
    b
  } else if a.has_suffix("/") {
    a + b
  } else {
    a + "/" + b
  }
}

///|
pub fn basename(p : String) -> String {
  match p.rev_find("/") {
    Some(k) => p.view(start_offset=k + 1).to_string()
    None => p
  }
}

///|
pub fn dirname(p : String) -> String {
  match p.rev_find("/") {
    Some(k) => p.view(end_offset=k).to_string()
    None => ""
  }
}

///|
/// os.path.abspath (POSIX)
pub fn abspath(p : String) -> String {
  let full = if p.has_prefix("/") { p } else { cwd() + "/" + p }
  let parts : Array[String] = []
  for part in full.split("/") {
    let part = part.to_string()
    if part == "" || part == "." {
      continue
    }
    if part == ".." {
      let _ = parts.pop()
      continue
    }
    parts.push(part)
  }
  "/" + parts.join("/")
}

///|
#borrow(path)
extern "C" fn c_is_link(path : Bytes) -> Int = "tsys_is_link"

///|
/// Whether path is a symbolic link (not followed)
pub fn is_link(path : String) -> Bool {
  c_is_link(enc(path)) != 0
}

///|
extern "C" fn c_read_stdin() -> Bytes = "tsys_read_stdin"

///|
/// What stdin gives, to its end
pub fn read_stdin() -> String {
  dec(c_read_stdin())
}

///|
/// fnmatch: * anything (a / too), ? one character, [seq], [!seq]
pub fn fnmatch(name : String, pat : String) -> Bool {
  let n = name.to_array()
  let p = pat.to_array()
  fn go(i : Int, j : Int) -> Bool {
    if j == p.length() {
      return i == n.length()
    }
    match p[j] {
      '*' => {
        let mut k = i
        while k <= n.length() {
          if go(k, j + 1) {
            return true
          }
          k += 1
        }
        false
      }
      '?' => i < n.length() && go(i + 1, j + 1)
      '[' => {
        let mut e = j + 1
        if e < p.length() && p[e] == '!' {
          e += 1
        }
        if e < p.length() && p[e] == ']' {
          e += 1
        }
        while e < p.length() && p[e] != ']' {
          e += 1
        }
        if e >= p.length() {
          // (no closing bracket: a [ itself)
          return i < n.length() && n[i] == '[' && go(i + 1, j + 1)
        }
        if i >= n.length() {
          return false
        }
        let neg = p[j + 1] == '!'
        let mut k = if neg { j + 2 } else { j + 1 }
        let mut hit = false
        let mut first = true
        while k < e || (first && k == e) {
          first = false
          if k + 2 < e && p[k + 1] == '-' {
            if n[i] >= p[k] && n[i] <= p[k + 2] {
              hit = true
            }
            k += 3
          } else {
            if k < e && n[i] == p[k] {
              hit = true
            }
            k += 1
          }
          if k > e {
            break
          }
        }
        hit != neg && go(i + 1, e + 1)
      }
      c => i < n.length() && n[i] == c && go(i + 1, j + 1)
    }
  }

  go(0, 0)
}

///|
/// glob.glob(root/pat), relative to root: pat's last part may hold * ? [ ] (a name starting with . only when the
/// part does), the rest not; sorted
pub fn glob(root : String, pat : String) -> Array[String] {
  let dir = dirname(pat)
  let base = basename(pat)
  if !(base.contains("*") || base.contains("?") || base.contains("[")) {
    return if exists(join(root, pat)) { [pat] } else { [] }
  }
  let out = []
  for n in list_dir(if dir == "" { root } else { join(root, dir) }) {
    if n.has_prefix(".") && !base.has_prefix(".") {
      continue
    }
    if fnmatch(n, base) {
      out.push(if dir == "" { n } else { dir + "/" + n })
    }
  }
  out
}
