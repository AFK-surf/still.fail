// The values of a copy (station/src/replica): rows and records as JavaScript has them (keys in their order, numbers and
// strings written as JSON.stringify writes them), what the shell is asked of the filesystem, and SHA-1 for the digests
// of what was written.

///|
using @jsjson { type JValue }

///|
/// A string as a JSON string value.
pub fn str(s : String) -> JValue {
  Str(@jsjson.units(s))
}

///|
/// A value the shell gave (a row's column) as JavaScript has it.
pub fn of_json(j : Json) -> JValue {
  match j {
    Null => Null
    True => Bool(true)
    False => Bool(false)
    Number(d, ..) => Num(d)
    String(s) => str(s)
    Array(items) => Arr(items.map(of_json))
    Object(m) => Obj(m.to_array().map(e => (@jsjson.units(e.0), of_json(e.1))))
  }
}

///|
/// A row the shell gave, by its columns' names in their order.
fn row_of(m : Map[String, Json]) -> JValue {
  Obj(m.to_array().map(e => (@jsjson.units(e.0), of_json(e.1))))
}

///|
/// A value as a statement's parameter (as node:sqlite binds a number, a string, null).
fn param(v : JValue?) -> Json {
  match v {
    Some(Num(d)) => Json::number(d)
    Some(Str(s)) => Json::string(@jsjson.text(s))
    Some(Bool(b)) => Json::boolean(b)
    Some(Null) | None => Json::null()
    Some(v) => Json::string(@jsjson.stringify(v))
  }
}

///|
fn get(v : JValue, name : String) -> JValue? {
  match v {
    Obj(_) => v.get(name)
    _ => None
  }
}

///|
/// `num` of station/src/replica/export.ts: a number as it is, anything else 0.
fn num(v : JValue?) -> Double {
  match v {
    Some(Num(d)) => d
    _ => 0.0
  }
}

///|
fn text_of(v : JValue?) -> String? {
  match v {
    Some(Str(s)) => Some(@jsjson.text(s))
    _ => None
  }
}

///|
/// `o` with `name` set: where it is, in its place, else last (as `{...o, name}` has it).
fn set(o : JValue, name : String, v : JValue) -> JValue {
  guard o is Obj(entries) else { return Obj([(@jsjson.units(name), v)]) }
  let key = @jsjson.units(name)
  let out = []
  let mut found = false
  for e in entries {
    if e.0 == key {
      if !found {
        out.push((key, v))
        found = true
      }
    } else {
      out.push(e)
    }
  }
  if !found {
    out.push((key, v))
  }
  Obj(out)
}

///|
/// `o` without `name`.
fn without(o : JValue, name : String) -> JValue {
  guard o is Obj(entries) else { return o }
  let key = @jsjson.units(name)
  Obj(entries.filter(e => e.0 != key))
}

///|
fn keys_of(o : JValue) -> Array[String] {
  match o {
    Obj(entries) => {
      let out : Array[String] = []
      for e in entries {
        let k = @jsjson.text(e.0)
        if !out.contains(k) {
          out.push(k)
        }
      }
      out
    }
    _ => []
  }
}

///|
fn stringify(v : JValue) -> String {
  @jsjson.stringify(v)
}

///|
/// How many bytes `s` is in UTF-8, as Buffer.from(s, "utf8") makes it (a lone surrogate three, as U+FFFD).
pub fn utf8_length(s : String) -> Int {
  let mut n = 0
  let len = s.length()
  let mut i = 0
  while i < len {
    let c = s.unsafe_charcode_at(i)
    i += 1
    if c < 0x80 {
      n += 1
    } else if c < 0x800 {
      n += 2
    } else if c >= 0xd800 && c <= 0xdbff && i < len && s.unsafe_charcode_at(i) >= 0xdc00 && s.unsafe_charcode_at(i) <= 0xdfff {
      n += 4
      i += 1
    } else {
      n += 3
    }
  }
  n
}

///|
/// `s` in UTF-8, as Buffer.from(s, "utf8") makes it.
fn utf8_bytes(s : String) -> Array[Int] {
  let out : Array[Int] = []
  let len = s.length()
  let mut i = 0
  while i < len {
    let mut c = s.unsafe_charcode_at(i)
    i += 1
    if c >= 0xd800 && c <= 0xdbff && i < len && s.unsafe_charcode_at(i) >= 0xdc00 && s.unsafe_charcode_at(i) <= 0xdfff {
      c = 0x10000 + ((c - 0xd800) << 10) + (s.unsafe_charcode_at(i) - 0xdc00)
      i += 1
    } else if c >= 0xd800 && c <= 0xdfff {
      c = 0xfffd
    }
    if c < 0x80 {
      out.push(c)
    } else if c < 0x800 {
      out.push(0xc0 | (c >> 6))
      out.push(0x80 | (c & 0x3f))
    } else if c < 0x10000 {
      out.push(0xe0 | (c >> 12))
      out.push(0x80 | ((c >> 6) & 0x3f))
      out.push(0x80 | (c & 0x3f))
    } else {
      out.push(0xf0 | (c >> 18))
      out.push(0x80 | ((c >> 12) & 0x3f))
      out.push(0x80 | ((c >> 6) & 0x3f))
      out.push(0x80 | (c & 0x3f))
    }
  }
  out
}

///|
fn rotl(x : UInt, n : Int) -> UInt {
  (x << n) | (x >> (32 - n))
}

///|
/// SHA-1 of `s` in UTF-8, as lowercase hex (createHash("sha1").update(s)).
pub fn sha1_hex(s : String) -> String {
  let bytes = utf8_bytes(s)
  let bits = bytes.length().to_uint64() * 8
  bytes.push(0x80)
  while bytes.length() % 64 != 56 {
    bytes.push(0)
  }
  for i = 7; i >= 0; i = i - 1 {
    bytes.push(((bits >> (i * 8)) & 0xff).to_int())
  }
  let h : FixedArray[UInt] = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0]
  let w : FixedArray[UInt] = FixedArray::make(80, 0)
  for chunk = 0; chunk < bytes.length(); chunk = chunk + 64 {
    for i in 0..<16 {
      let b = (j : Int) => bytes[chunk + i * 4 + j].reinterpret_as_uint()
      w[i] = (b(0) << 24) | (b(1) << 16) | (b(2) << 8) | b(3)
    }
    for i in 16..<80 {
      w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1)
    }
    let mut a = h[0]
    let mut b = h[1]
    let mut c = h[2]
    let mut d = h[3]
    let mut e = h[4]
    for i in 0..<80 {
      let (f, k) : (UInt, UInt) = if i < 20 {
        ((b & c) | (b.lnot() & d), 0x5A827999)
      } else if i < 40 {
        (b ^ c ^ d, 0x6ED9EBA1)
      } else if i < 60 {
        ((b & c) | (b & d) | (c & d), 0x8F1BBCDC)
      } else {
        (b ^ c ^ d, 0xCA62C1D6)
      }
      let t = rotl(a, 5) + f + e + k + w[i]
      e = d
      d = c
      c = rotl(b, 30)
      b = a
      a = t
    }
    h[0] = h[0] + a
    h[1] = h[1] + b
    h[2] = h[2] + c
    h[3] = h[3] + d
    h[4] = h[4] + e
  }
  let hexd = "0123456789abcdef"
  let out = StringBuilder::new()
  for x in h {
    for shift = 28; shift >= 0; shift = shift - 4 {
      out.write_char(hexd.unsafe_charcode_at(((x >> shift) & 0xf).reinterpret_as_int()).unsafe_to_char())
    }
  }
  out.to_string()
}

///|
/// What the program asks of the filesystem, through the shell.
pub struct Files {
  host : @host.Host
  /// The platform's separator (Node's path.sep).
  sep : String
}

///|
fn Files::call(self : Files, op : String, args : Json) -> Json raise {
  self.host.shell_sync(op, args)
}

///|
fn Files::join(self : Files, parts : Array[String]) -> String {
  @nodepath.join(self.sep, parts)
}

///|
/// `path`'s folder (path.dirname, for a path this program made).
fn Files::dirname(self : Files, path : String) -> String {
  let slash = path.rev_find("/").unwrap_or(-1)
  let back = if self.sep == "\\" { path.rev_find("\\").unwrap_or(-1) } else { -1 }
  let cut = if slash > back { slash } else { back }
  if cut <= 0 {
    if cut == 0 { self.sep } else { "." }
  } else {
    path.view(end_offset=cut).to_string()
  }
}

///|
/// Whether something is there (existsSync: links followed).
fn Files::exists(self : Files, path : String) -> Bool {
  match (try { Ok(self.call("fs.stat", { "path": Json::string(path) })) } catch { e => Err(e) }) {
    Ok(String(_)) => true
    _ => false
  }
}

///|
fn Files::kind(self : Files, path : String) -> String? {
  match (try { Ok(self.call("fs.stat", { "path": Json::string(path) })) } catch { e => Err(e) }) {
    Ok(String(k)) => Some(k)
    _ => None
  }
}

///|
/// A file's size and modification time (ms, floored), none when it is not there.
fn Files::meta(self : Files, path : String) -> (Double, Double)? {
  match (try { Ok(self.call("fs.meta", { "path": Json::string(path) })) } catch { e => Err(e) }) {
    Ok({ "size": Number(size, ..), "mtimeMs": Number(mtime, ..), .. }) => Some((size, mtime))
    Ok({ "size": Number(size, ..), .. }) => Some((size, 0.0))
    _ => None
  }
}

///|
fn Files::size(self : Files, path : String) -> Double raise {
  match self.meta(path) {
    Some((size, _)) => size
    None => fail("ENOENT: no such file or directory, stat '\{path}'")
  }
}

///|
/// A file's text (zstd's frames read as what they hold, with `zstd`); none where it does not open.
fn Files::read(self : Files, path : String, zstd? : Bool = false) -> String? raise {
  match self.call("fs.read", { "path": Json::string(path), "zstd": Json::boolean(zstd) }) {
    String(s) => Some(s)
    _ => None
  }
}

///|
/// `text` written whole at `path` (zstd's frame of it, with `zstd`): the SHA-256 of what was written.
fn Files::write(self : Files, path : String, text : String, zstd? : Bool = false) -> String raise {
  match self.call("fs.write", { "path": Json::string(path), "text": Json::string(text), "zstd": Json::boolean(zstd) }) {
    { "sha256": String(h), .. } => h
    _ => fail("the shell wrote nothing")
  }
}

///|
fn Files::hash(self : Files, path : String) -> String? raise {
  match self.call("fs.hash", { "path": Json::string(path) }) {
    String(h) => Some(h)
    _ => None
  }
}

///|
fn Files::mkdir(self : Files, path : String) -> Unit raise {
  ignore(self.call("fs.mkdir", { "path": Json::string(path) }))
}

///|
fn Files::remove(self : Files, path : String, recursive? : Bool = false) -> Unit raise {
  ignore(self.call("fs.remove", { "path": Json::string(path), "recursive": Json::boolean(recursive) }))
}

///|
fn Files::rename(self : Files, from : String, to : String) -> Unit raise {
  ignore(self.call("fs.rename", { "from": Json::string(from), "to": Json::string(to) }))
}

///|
fn Files::copy(self : Files, from : String, to : String) -> Unit raise {
  ignore(self.call("fs.copy", { "from": Json::string(from), "to": Json::string(to) }))
}

///|
/// A folder's names in readdirSync's order; none where it does not read.
fn Files::names(self : Files, path : String) -> Array[String]? {
  match (try { Ok(self.call("fs.readdir", { "path": Json::string(path) })) } catch { e => Err(e) }) {
    Ok(Array(names)) => Some(names.filter_map(n => if n is String(s) { Some(s) } else { None }))
    _ => None
  }
}

///|
/// `n` random bytes, as hex (randomBytes(n).toString("hex")).
fn Files::random(self : Files, n : Int) -> String raise {
  match self.call("crypto.random", { "bytes": Json::number(n.to_double()) }) {
    String(h) => h
    _ => fail("the shell gave no random bytes")
  }
}
