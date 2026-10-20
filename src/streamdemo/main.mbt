// A picture decoded frame by frame (@ui.Stream): the sample's H.264 (scripts/stream_sample.py: an avcC, then access
// units in AVCC), or its JPEG frames where the host decodes no H.264 or MBUI_STREAM=jpeg, handed over as a remote
// screen's station sends them: at most two ahead of the last one said shown. Each frame said shown and the decoder
// broken go on the log ("STREAM shown TS", "STREAM broken"), then "STREAM done" once every frame was. The picture is
// drawn contained in the window, the frame's time over it. For the hosts' checks: `APP=streamdemo scripts/mac.sh`,
// `scripts/android.sh` (a run at its rest shows the last frame), scripts/android-streams.sh.

///|
let stream : Ref[@ui.Stream?] = Ref(None)

///|
/// The frames handed over, and those said shown (the highest, counted from 1).
let fed : Ref[Int] = Ref(0)

///|
let acked : Ref[Int] = Ref(0)

///|
fn jpeg_mode() -> Bool {
  @ui.env("MBUI_STREAM") == "jpeg" || !@ui.h264_here()
}

///|
fn total() -> Int {
  if jpeg_mode() {
    sample_jpegs.length()
  } else {
    sample_frames.length()
  }
}

///|
/// Base64 (standard) decoded.
fn b64(s : String) -> Bytes {
  let v = fn(c : Char) -> Int {
    let n = c.to_int()
    if n >= 'A'.to_int() && n <= 'Z'.to_int() {
      n - 'A'.to_int()
    } else if n >= 'a'.to_int() && n <= 'z'.to_int() {
      n - 'a'.to_int() + 26
    } else if n >= '0'.to_int() && n <= '9'.to_int() {
      n - '0'.to_int() + 52
    } else if c == '+' {
      62
    } else if c == '/' {
      63
    } else {
      -1
    }
  }
  let out = []
  let mut acc = 0
  let mut bits = 0
  for c in s {
    let d = v(c)
    if d < 0 {
      continue
    }
    acc = (acc << 6) | d
    bits += 6
    if bits >= 8 {
      bits -= 8
      out.push(((acc >> bits) & 255).to_byte())
    }
  }
  Bytes::from_array(out)
}

///|
/// The next frames, as a station sends them: at most two ahead of the last one said shown.
fn feed(s : @ui.Stream) -> Unit {
  while fed.val < total() && fed.val - acked.val < 2 {
    let i = fed.val
    let ts = ((i + 1) * 100).to_double()
    if jpeg_mode() {
      s.jpeg(b64(sample_jpegs[i]), ts)
    } else {
      let (key, data) = sample_frames[i]
      s.frame(b64(data), key, ts)
    }
    fed.val = i + 1
  }
}

///|
/// MBUI_STREAM_REOPEN=N: the stream closed once frame N is said shown (its decoder busy with those after it) and a
/// new one fed from the start, as the viewer does going from one screen to another; "STREAM done" the new one's.
fn reopen_at() -> Int {
  let mut n = 0
  for c in @ui.env("MBUI_STREAM_REOPEN") {
    if c < '0' || c > '9' {
      return 0
    }
    n = n * 10 + (c.to_int() - '0'.to_int())
  }
  n
}

///|
let reopened : Ref[Bool] = Ref(false)

///|
fn start() -> Unit {
  let s = @ui.Stream::new(
    shown=fn(ts) {
      @ui.log("STREAM shown \{ts}")
      let n = (ts / 100.0).to_int()
      if n > acked.val {
        acked.val = n
      }
      if !reopened.val && reopen_at() > 0 && acked.val >= reopen_at() {
        reopened.val = true
        match stream.val {
          Some(old) => old.close()
          None => ()
        }
        @ui.log("STREAM reopen")
        fed.val = 0
        acked.val = 0
        start()
        return
      }
      if acked.val == total() {
        @ui.log("STREAM done")
        // (a host's check: the run's own end, MBUI_STREAM_EXIT=1)
        if @ui.env("MBUI_STREAM_EXIT") == "1" {
          @host.exit(0)
        }
      }
      match stream.val {
        Some(s) => feed(s)
        None => ()
      }
    },
    broken=fn() { @ui.log("STREAM broken") },
  )
  stream.val = Some(s)
  @ui.log("STREAM start \{if jpeg_mode() { "jpeg" } else { "h264" }} \{total()} frames")
  if !jpeg_mode() {
    s.h264(b64(sample_avcc), sample_w, sample_h)
  }
  feed(s)
}

///|
fn view(c : @ui.Ctx) -> Unit {
  if stream.val is None {
    c.after_build("start", start)
  }
  match stream.val {
    Some(s) => {
      c.stream(s, fit=FitContain) |> ignore
      let at = match s.shown_at() {
        Some(ts) => "frame \{ts}"
        None => "no frame yet"
      }
      let size = match s.size() {
        Some((w, h)) => " \{w}x\{h}"
        None => ""
      }
      c.text("stream: " + at + size) |> ignore
    }
    None => ()
  }
}

///|
fn main {
  @host.window_setup(480.0, 320.0, 720.0, 480.0)
  @ui.run("mbui streams", view)
}
