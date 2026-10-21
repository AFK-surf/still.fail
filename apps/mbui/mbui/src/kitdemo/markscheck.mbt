// The marks' contract (docs/determinism.md, "What is compared, and where"; scripts/host_contract.sh HOST marks): on a
// real host, MBUI_MARKS=<the marks' JSON, base64> MBUI_MARKS_IMAGE=<the picture's bytes, base64> (test/marks/): the
// marks drawn onto the picture by the host (@host.draw_marks), the PNG it made written on the log in base64 (`MARKS
// png <part>` lines, then `MARKS done N bytes`), then the app's end. `MARKS none` where the host draws none (Windows,
// the web), `MARKS failed` where it could not: the app ends with 1. The host asks for a frame once the PNG is made:
// each frame's build only asks whether it is.

///|
/// The drawing asked for (once, in the first frame's build), while the host draws it.
let marks_job : Ref[@host.MarkedImage?] = Ref(None)

///|
let marks_started : Ref[Bool] = Ref(false)

///|
fn marks_b64_value(c : Char) -> Int {
  if c >= 'A' && c <= 'Z' {
    c.to_int() - 'A'.to_int()
  } else if c >= 'a' && c <= 'z' {
    c.to_int() - 'a'.to_int() + 26
  } else if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int() + 52
  } else if c == '+' || c == '-' {
    62
  } else if c == '/' || c == '_' {
    63
  } else {
    -1
  }
}

///|
/// The bytes of `s` (base64, standard or URL-safe; padding and anything else skipped).
fn marks_bytes_of(s : String) -> Bytes {
  let out : Array[Byte] = []
  let mut acc = 0
  let mut bits = 0
  for ch in s {
    let v = marks_b64_value(ch)
    if v < 0 {
      continue
    }
    acc = ((acc << 6) | v) & 0xFFFFFF
    bits = bits + 6
    if bits >= 8 {
      bits = bits - 8
      out.push(((acc >> bits) & 0xFF).to_byte())
    }
  }
  Bytes::makei(out.length(), fn(i) { out[i] })
}

///|
/// `data` in base64 (standard, padded).
fn marks_base64(data : Bytes) -> String {
  let abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  let sb = StringBuilder()
  let n = data.length()
  let mut i = 0
  while i < n {
    let b0 = data[i].to_int()
    let b1 = if i + 1 < n { data[i + 1].to_int() } else { 0 }
    let b2 = if i + 2 < n { data[i + 2].to_int() } else { 0 }
    sb.write_char(abc[b0 >> 2].unsafe_to_char())
    sb.write_char(abc[((b0 & 3) << 4) | (b1 >> 4)].unsafe_to_char())
    sb.write_char(if i + 1 < n { abc[((b1 & 15) << 2) | (b2 >> 6)].unsafe_to_char() } else { '=' })
    sb.write_char(if i + 2 < n { abc[b2 & 63].unsafe_to_char() } else { '=' })
    i = i + 3
  }
  sb.to_string()
}

///|
/// MBUI_MARKS: the drawing asked for, then, once the host has made it, the PNG on the log and the app's end.
fn marks_run(c : @ui.Ctx, marks : String, image : String) -> Unit {
  if !marks_started.val {
    marks_started.val = true
    match @host.draw_marks(marks_bytes_of(image), @host.from_base64(marks)) {
      Some(job) => marks_job.val = Some(job)
      None => {
        @host.log("MARKS none: this host draws no marks")
        @host.exit(1)
      }
    }
  }
  match marks_job.val {
    Some(job) =>
      match job.made() {
        Some(png) => {
          marks_job.val = None
          if png.length() == 0 {
            @host.log("MARKS failed: the host could not draw them")
            @host.exit(1)
          } else {
            // in parts (a log line of a few kB: logcat's, the simulator's stderr)
            let text = marks_base64(png)
            let part = 3000
            let mut at = 0
            while at < text.length() {
              let end = if at + part < text.length() { at + part } else { text.length() }
              @host.log("MARKS png " + text.view(start_offset=at, end_offset=end).to_owned())
              at = end
            }
            @host.log("MARKS done \{png.length()} bytes")
            @host.exit(0)
          }
        }
        None => ()
      }
    None => ()
  }
  c.text("MARKS") |> ignore
}
