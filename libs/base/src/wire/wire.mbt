// What goes on a stream of a link and how what comes on one is read, with no stream: the bytes alone, so that they
// are tested with nothing linked. A stream carries lines of JSON and what follows them:
//   the control stream   a line each way at a time: `{"credential": …, …}` out, its answer back;
//   a request's stream   a head line `{"method", "path", "headers"}`, with what its kind says after those (an
//                        ask's, a socket's, a duplex's: `more`), then its body out; a head line
//                        `{"status", "headers"}` then its body back.
// The lines are written as JavaScript's JSON.stringify writes them (client/core-ts/src/mesh.ts, whose bytes
// these are held to: wire_test.mbt), and read as its peer's door writes them (station/src/mesh/wire.ts).

///|
/// What came on a stream and is not read yet: lines are taken off its front, the rest is what follows them.
pub struct Carry {
  priv mut held : Bytes
}

///|
pub fn Carry::new() -> Carry {
  { held: b"" }
}

///|
/// How much is held.
pub fn Carry::length(self : Carry) -> Int {
  self.held.length()
}

///|
/// `chunk` came.
pub fn Carry::push(self : Carry, chunk : Bytes) -> Unit {
  self.held = if self.held.length() == 0 { chunk } else { self.held + chunk }
}

///|
/// The first whole line held, without its newline, taken; None while none is whole.
pub fn Carry::line(self : Carry) -> String? {
  for i = 0; i < self.held.length(); i = i + 1 {
    if self.held[i] == b'\n' {
      let line = @utf8.decode_lossy(self.held[0:i])
      self.held = self.held[i + 1:].to_owned()
      return Some(line)
    }
  }
  None
}

///|
/// All that is held, taken.
pub fn Carry::take(self : Carry) -> Bytes {
  let all = self.held
  self.held = b""
  all
}

///|
/// A line of the control stream: the credential, then what every line says (`says`), then what is said with this
/// credential (`also`), then the dial's `traceparent`; a field said again keeps its first place and takes the later
/// value (as an object spread does).
pub fn hello_line(
  credential : String,
  says? : Map[String, Json],
  also? : Map[String, Json],
  traceparent? : String,
) -> String {
  let line : Map[String, Json] = { "credential": Json::string(credential) }
  for more in [says, also] {
    if more is Some(fields) {
      for k, v in fields {
        line[k] = v
      }
    }
  }
  if traceparent is Some(t) && t != "" {
    line["traceparent"] = Json::string(t)
  }
  written(Json::object(line)) + "\n"
}

///|
/// `json` as JavaScript's JSON.stringify writes it. One thing MoonBit's own writes otherwise: a number that is none
/// (NaN, an infinity) is `null` there.
fn written(json : Json) -> String {
  finite(json).stringify()
}

///|
fn finite(json : Json) -> Json {
  match json {
    Number(n, ..) => if n.is_nan() || n.is_inf() { Json::null() } else { json }
    Array(items) => Json::array(items.map(finite))
    Object(fields) => {
      let out : Map[String, Json] = Map([])
      for k, v in fields {
        out[k] = finite(v)
      }
      Json::object(out)
    }
    _ => json
  }
}

///|
/// A request's head line; `more`: further fields of it, after its headers. A header said twice keeps its first place
/// and takes the later value, as a field of `more` that names one before it does (an object spread).
///
/// One thing JavaScript writes otherwise, and no head says: a header or a field named as a whole number ("2") is
/// written there before every other, in ascending order; here where it was given.
pub fn head_line(
  method_ : String,
  path : String,
  headers : Array[(String, String)],
  more? : Map[String, Json],
) -> String {
  let said : Map[String, Json] = Map([])
  for header in headers {
    said[header.0] = Json::string(header.1)
  }
  let line : Map[String, Json] = {
    "method": Json::string(method_),
    "path": Json::string(path),
    "headers": Json::object(said),
  }
  if more is Some(fields) {
    for k, v in fields {
      line[k] = v
    }
  }
  written(Json::object(line)) + "\n"
}

///|
/// A reply's head line, read.
pub(all) enum Head {
  /// Its status and its headers (a header that is no string, as its JSON).
  Head(Int, Array[(String, String)])
  /// The line is not JSON: what the parser said.
  Unreadable(String)
  /// It says no status (a whole number, 0 to 65535).
  NoStatus
}

///|
pub fn reply_head(line : String) -> Head {
  let reply : Json = @json.parse(line) catch { e => return Unreadable(e.to_string()) }
  guard reply is { "status": Number(status, ..), .. } else { return NoStatus }
  guard status == status.floor() && status >= 0.0 && status <= 65535.0 else { return NoStatus }
  let headers : Array[(String, String)] = []
  if reply is { "headers": Object(said), .. } {
    for k, v in said {
      headers.push(
        (
          k,
          match v {
            String(s) => s
            other => other.stringify()
          },
        ),
      )
    }
  }
  Head(status.to_int(), headers)
}
