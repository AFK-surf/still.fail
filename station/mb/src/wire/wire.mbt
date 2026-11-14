// What passes between a station program and its host (host.c), without the host: stdin's bytes made lines, the host's
// events read, the shell's answers taken apart. Its own package, so that its tests link no host.

///|
/// The shell answered with an error.
pub(all) suberror ShellError {
  ShellError(String)
}

///|
/// Bytes as they come, made lines (each without its newline); what is left is kept for the next.
pub struct Lines {
  priv partial : Array[Byte]
}

///|
pub fn Lines::new() -> Lines {
  { partial: [] }
}

///|
/// The lines `data` ends, the first of them begun by what came before.
pub fn Lines::push(self : Lines, data : BytesView) -> Array[String] {
  let out = []
  for b in data {
    if b == b'\n' {
      out.push(@utf8.decode_lossy(Bytes::from_array(self.partial)))
      self.partial.clear()
    } else {
      self.partial.push(b)
    }
  }
  out
}

///|
/// One of the host's events (host.c `sfh_wait`).
pub(all) enum Event {
  /// A piece of stdin.
  Input(BytesView)
  /// Stdin has ended.
  End
  /// The shell's answer to a call: its JSON, or its error, and the bytes it carries (none where it carries none).
  Answer(Int64, Result[Json, ShellError], Bytes?)
  /// One this program does not know.
  Other
}

///|
fn le64(b : BytesView, at : Int) -> Int64 {
  let mut n = 0L
  for i = 7; i >= 0; i = i - 1 {
    n = (n << 8) | b[at + i].to_int64()
  }
  n
}

///|
/// The event as host.c gives it: its kind, its id (8 bytes, the low first), then what it carries (an answer: its
/// error's length in 8 bytes, the error, the JSON).
pub fn Event::read(e : BytesView) -> Event {
  guard e.length() >= 9 else { return Other }
  match e[0] {
    b'\x01' => Input(e[9:])
    b'\x02' => End
    b'\x03' => {
      // (its error's length and the error, its JSON's length and the JSON, whether it carries bytes, and the bytes)
      guard e.length() >= 17 else { return Other }
      let id = le64(e, 1)
      let el = le64(e, 9).to_int()
      guard el >= 0 && 25 + el <= e.length() else { return Other }
      let jl = le64(e, 17 + el).to_int()
      guard jl >= 0 && 26 + el + jl <= e.length() else { return Other }
      let carried = if e[25 + el + jl] == b'\x01' {
        Some(e[26 + el + jl:].to_bytes())
      } else {
        None
      }
      let error = @utf8.decode_lossy(e[17:17 + el])
      if error != "" {
        return Answer(id, Err(ShellError(error)), carried)
      }
      let text = @utf8.decode_lossy(e[25 + el:25 + el + jl])
      Answer(id, Ok(@json.parse(text) catch { _ => Json::null() }), carried)
    }
    _ => Other
  }
}

///|
/// The shell's answer at once, {"value": …} or {"error": …}, as its value or its error.
pub fn answered(text : String) -> Json raise ShellError {
  let json : Json = @json.parse(text) catch {
    e => raise ShellError("the shell's answer is not JSON: \{e}")
  }
  match json {
    { "error": String(e), .. } => raise ShellError(e)
    { "value": v, .. } => v
    _ => Json::null()
  }
}
