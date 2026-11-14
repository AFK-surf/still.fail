// The streams' contract (scripts/host_contract.sh windows stream): on a real host, MBUI_STREAMCHECK=<an AV1 picture's
// OBUs, base64> (test/host/streamcheck-av1.obu: a second of ffmpeg's testsrc2, 64 × 48 at 10 frames a second, 8-bit
// 4:2:0, in AV1's low overhead format, a temporal delimiter before each temporal unit) and MBUI_STREAMCHECK_SIZE=WxH
// (64x48 by default): whether the host decodes AV1 said first (`STREAMCHECK here 1`, or 0); then a stream given it as
// an app gives one of an MP4: its config an av1C made of the first sequence header, each temporal unit a frame as an
// MP4's sample holds it (no temporal delimiter) and with no sequence header of its own, so the host puts the config's
// before each key frame (one that had one); then, once every frame's fate is said, the picture shown and its time
// (`STREAMCHECK shown 64x48 at 9`: the last frame decoded and shown; `STREAMCHECK shown none` where none was: a host
// without the decoder, whose frames the stream let go), and the app's end. The host asks for a frame as each event
// comes: each frame's build only looks at what came.

///|
// kept across runs: the check's one run (kitdemo run with MBUI_STREAMCHECK), never reset
let stream_check_stream : Ref[@ui.Stream?] = Ref(None)

///|
/// the frames handed over, and those said shown or let go (Stream::new's `shown`)
// kept across runs: the check's one run, never reset
let stream_check_frames : Ref[Int] = Ref(0)

///|
// kept across runs: the check's one run, never reset
let stream_check_acked : Ref[Int] = Ref(0)

///|
// kept across runs: the check's one run, never reset
let stream_check_done : Ref[Bool] = Ref(false)

///|
/// The OBUs of `data` in order: each one's type and its bytes whole (its header and size with it); None where they are
/// not OBUs with their sizes.
fn stream_check_obus(data : Bytes) -> Array[(Int, Bytes)]? {
  let out = []
  let n = data.length()
  let mut at = 0
  while at < n {
    let from = at
    let head = data[at].to_int()
    let kind = (head >> 3) & 15
    at += 1 + ((head >> 2) & 1)
    if (head & 2) == 0 || (head & 0x80) != 0 || at > n {
      return None
    }
    let mut len = 0
    let mut shift = 0
    let mut more = true
    while more {
      if at >= n || shift > 28 {
        return None
      }
      let b = data[at].to_int()
      at += 1
      len = len | ((b & 0x7f) << shift)
      shift += 7
      more = (b & 0x80) != 0
    }
    if len > n - at {
      return None
    }
    at += len
    out.push((kind, data[from:at].to_owned()))
  }
  Some(out)
}

///|
/// What the check does once its first build is over: the stream opened and every frame handed over; then, once each
/// is said, the picture shown and the app's end.
fn stream_check_step(obus : String, size : String) -> Unit {
  match stream_check_stream.val {
    Some(s) => {
      if stream_check_done.val || stream_check_acked.val < stream_check_frames.val {
        return
      }
      stream_check_done.val = true
      match (s.size(), s.shown_at()) {
        (Some((w, h)), Some(ts)) =>
          @hostapi.log("STREAMCHECK shown \{w}x\{h} at \{ts.to_int()}")
        _ => @hostapi.log("STREAMCHECK shown none")
      }
      s.close()
      @hostapi.exit(0)
    }
    None => {
      @hostapi.log("STREAMCHECK here \{if @ui.av1_here() { 1 } else { 0 }}")
      let (w, h) = match size.split("x").map(fn(p) { @string.parse_int(p.to_owned()) catch { _ => 0 } }).collect() {
        [w, h] if w > 0 && h > 0 => (w, h)
        _ => (64, 48)
      }
      guard stream_check_obus(@codec.from_base64(obus)) is Some(list) else {
        @hostapi.log("STREAMCHECK no OBUs")
        @hostapi.exit(1)
        return
      }
      let s = @ui.Stream::new(shown=fn(_) { stream_check_acked.val += 1 }, broken=fn() {
        @hostapi.log("STREAMCHECK broken")
      })
      stream_check_stream.val = Some(s)
      // (an av1C: its marker and version, profile 0 level 0, 8-bit 4:2:0 (its bytes the host does not read), then the
      // first sequence header)
      let config = Buffer()
      for b in [b'\x81', b'\x00', b'\x0c', b'\x00'] {
        config.write_byte(b)
      }
      match list.search_by(fn(o) { o.0 == 1 }) {
        Some(i) => config.write_bytes(list[i].1)
        None => ()
      }
      s.av1(config.to_bytes(), w, h)
      // (a temporal unit after each delimiter (type 2), its sequence header taken out: the config's put back by the host)
      let unit = Buffer()
      let key = Ref(false)
      let hand = fn() {
        if unit.length() > 0 {
          s.frame(unit.to_bytes(), key.val, stream_check_frames.val.to_double())
          stream_check_frames.val += 1
          unit.reset()
        }
      }
      for o in list {
        match o.0 {
          2 => {
            hand()
            key.val = false
          }
          1 => key.val = true
          _ => unit.write_bytes(o.1)
        }
      }
      hand()
    }
  }
}

///|
pub fn stream_check_run(c : @ui.Ctx, obus : String) -> Unit {
  c.after_build("stream-check", fn() { stream_check_step(obus, @ui.env("MBUI_STREAMCHECK_SIZE")) })
  c.text("stream check") |> ignore
}
