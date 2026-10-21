// The app's conversation with its core as it went, kept: every message out (a subscription, a call, an
// unsubscription, a cancel) and in (a value, a delta, an answer, a fatal), one line of JSON each, in the order the UI
// thread saw them. A scripted run against a live backend keeps it (the app's MBUI_CORE_TRACE=1: CORETRACE lines on
// its log); a Tester gives it again (replay.mbt), so what the run saw is shown frame by frame, with no backend and no
// wall clock.
//
//   {"out":MSG,"w":WALL,"b":"HEX"}    what the app sent, the wall clock as it went (a message in is due its time after
//                                     the last thing before it, in or out: replay.mbt), the bytes beside it if any (a
//                                     part going up: a test gives the same again, Replay::sent_bytes)
//   {"in":MSG,"w":WALL,"b":"HEX"}     what came, the wall clock (wall_ms) as it came, the bytes beside it if any
//   …,"bn":N                          bytes over trace_bytes_max: their length alone (as scripts/trace.py keeps them),
//                                     not written out in hex as they come (a drive's 4 MB part: seconds of the run's
//                                     UI thread, its next ask that much later)

///|
let tracer : Ref[((String) -> Unit)?] = { val: None }

///|
/// The most bytes beside a message written out (in hex); more: their length alone.
let trace_bytes_max : Ref[Int] = { val: 16384 }

///|
/// Every message out and in from now on given to `line`, as one line of JSON each; bytes beside a message over
/// `bytes_max` kept as their length alone.
pub fn trace_to(line : (String) -> Unit, bytes_max? : Int = 16384) -> Unit {
  tracer.val = Some(line)
  trace_bytes_max.val = bytes_max
}

///|
/// The bytes beside a message as the trace keeps them: in hex ("b"), or over trace_bytes_max their length ("bn").
fn trace_bytes(m : Map[String, Json], b : Bytes) -> Unit {
  if b.length() > trace_bytes_max.val {
    m["bn"] = Json::number(b.length().to_double())
  } else {
    m["b"] = Json::string(hex(b))
  }
}

///|
/// `m` kept on the trace beside the messages, stamped (`w`) with the core's clock as they are: what the app's host
/// says of its views, a scripted run's steps (src/stillfail). Nothing while no trace is kept.
pub fn trace_note(m : Map[String, Json]) -> Unit {
  match tracer.val {
    Some(line) => {
      m["w"] = Json::number(wall_ms())
      line(Json::object(m).stringify())
    }
    None => ()
  }
}

///|
/// Nothing kept from now on.
pub fn trace_stop() -> Unit {
  tracer.val = None
}

///|
fn trace_out(text : String, wall : Double, bytes? : Bytes) -> Unit {
  match tracer.val {
    Some(f) => {
      let msg = @json.parse(text) catch { _ => Json::string(text) }
      let m : Map[String, Json] = { "out": msg, "w": Json::number(wall) }
      match bytes {
        Some(b) => trace_bytes(m, b)
        None => ()
      }
      f(Json::object(m).stringify())
    }
    None => ()
  }
}

///|
fn trace_in(msg : Json, bytes : Bytes?, wall : Double) -> Unit {
  match tracer.val {
    Some(f) => {
      let m : Map[String, Json] = { "in": msg, "w": Json::number(wall) }
      match bytes {
        Some(b) => trace_bytes(m, b)
        None => ()
      }
      f(Json::object(m).stringify())
    }
    None => ()
  }
}

///|
let hex_digits : Array[Char] = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
]

///|
fn hex(b : Bytes) -> String {
  let out = StringBuilder::new()
  for i in 0..<b.length() {
    let v = b[i].to_int()
    out.write_char(hex_digits[v >> 4])
    out.write_char(hex_digits[v & 15])
  }
  out.to_string()
}

///|
fn hex_value(c : Char) -> Int {
  let n = c.to_int()
  if n >= '0'.to_int() && n <= '9'.to_int() {
    n - '0'.to_int()
  } else if n >= 'a'.to_int() && n <= 'f'.to_int() {
    n - 'a'.to_int() + 10
  } else {
    0
  }
}

///|
fn unhex(s : String) -> Bytes {
  let out : Array[Byte] = []
  let mut hi = -1
  for c in s {
    if hi < 0 {
      hi = hex_value(c)
    } else {
      out.push(((hi << 4) | hex_value(c)).to_byte())
      hi = -1
    }
  }
  Bytes::from_array(out)
}
