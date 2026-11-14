// What the reads of this machine's files (memory.mbt, machine.mbt) ask of the filesystem, through the shell
// (client/shell `fs.*`), as Node's calls in station/src/read/memory.ts and machine.ts answer.

///|
/// A file's text: `strict` as TextDecoder("utf-8", { fatal: true }) reads it (a leading byte order mark dropped, none
/// when it is not UTF-8), else as readFileSync(path, "utf8"); none when it does not read.
fn read_text(host : @host.Host, path : String, strict~ : Bool) -> String? raise {
  match host.shell_sync("fs.read", { "path": Json::string(path), "strict": Json::boolean(strict) }) {
    String(s) => Some(s)
    _ => None
  }
}

///|
/// JSON.parse(readFileSync(path, "utf8")), `{}` when it does not read or parse.
fn read_json(host : @host.Host, path : String) -> @jsjson.JValue raise {
  match read_text(host, path, strict=false) {
    Some(text) => @jsjson.parse(text) catch { _ => Obj([]) }
    None => Obj([])
  }
}

///|
/// A directory's names (readdirSync: sorted by their bytes but on Windows; `disk`: opendirSync's order, as the file
/// system gives them); none when it cannot be read.
fn read_dir(host : @host.Host, path : String, disk~ : Bool = false) -> Array[String]? raise {
  match host.shell_sync("fs.readdir", { "path": Json::string(path), "disk": Json::boolean(disk) }) {
    Array(names) => Some(names.filter_map(n => if n is String(s) { Some(s) } else { None }))
    _ => None
  }
}

///|
/// statSync(path).isFile() / isDirectory(), links followed; false when there is nothing to stat.
fn kind_of(host : @host.Host, path : String) -> String? raise {
  match host.shell_sync("fs.stat", { "path": Json::string(path) }) {
    String(k) => Some(k)
    _ => None
  }
}

///|
/// platform.paths.join (ops/paths.ts `joinPath`): Path::join as Rust has it, an absolute `given` replacing `base`,
/// nothing normalised.
fn join_path(sep : String, base : String, given : String) -> String {
  if sep == "\\" {
    let absolute = given.has_prefix("\\") ||
      given.has_prefix("/") ||
      (given.length() >= 3 && given.unsafe_charcode_at(1) == ':' && given.unsafe_charcode_at(2) is ('\\' | '/'))
    if absolute || base == "" {
      given
    } else if base.has_suffix("\\") || base.has_suffix("/") {
      base + given
    } else {
      base + "\\" + given
    }
  } else if given.has_prefix("/") || base == "" {
    given
  } else if base.has_suffix("/") {
    base + given
  } else {
    base + "/" + given
  }
}

///|
/// A string's code points.
fn points(s : String) -> Array[Int] {
  let out = []
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s.unsafe_charcode_at(i)
    if c >= 0xd800 && c <= 0xdbff && i + 1 < n && s.unsafe_charcode_at(i + 1) >= 0xdc00 && s.unsafe_charcode_at(i + 1) <= 0xdfff {
      out.push(0x10000 + ((c - 0xd800) << 10) + (s.unsafe_charcode_at(i + 1) - 0xdc00))
      i += 2
    } else {
      out.push(c)
      i += 1
    }
  }
  out
}

///|
/// Rust's String order: by the bytes of UTF-8, which is the order of code points.
fn by_bytes(a : String, b : String) -> Int {
  let (x, y) = (points(a), points(b))
  let n = if x.length() < y.length() { x.length() } else { y.length() }
  for i in 0..<n {
    if x[i] != y[i] {
      return if x[i] < y[i] { -1 } else { 1 }
    }
  }
  x.length() - y.length()
}

///|
/// A value as JavaScript's truthiness sees it.
fn truthy(v : @jsjson.JValue?) -> Bool {
  match v {
    None | Some(Null) | Some(Bool(false)) => false
    Some(Num(n)) => n != 0.0 && !n.is_nan()
    Some(Str(s)) => s.length() > 0
    _ => true
  }
}

///|
/// Object.entries of a value `typeof` calls an object (an object's own keys, an array's indices).
fn entries_of(v : @jsjson.JValue?) -> Array[(String, @jsjson.JValue)] {
  match v {
    Some(Obj(es)) => es.map(e => (@jsjson.raw_text(e.0), e.1))
    Some(Arr(xs)) => xs.mapi((i, x) => (i.to_string(), x))
    _ => []
  }
}
