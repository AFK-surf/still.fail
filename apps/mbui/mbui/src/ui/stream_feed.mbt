// An H.264 decoder driven from here (a host whose @hostapi.stream_feeds is true: Android's, Streams.java with
// MediaCodec onto a SurfaceTexture). The host only does what it is told (`stream_codec`) and says what its decoder and
// its surface said, as they said it, as the stream's events ("c ..."): which frame goes into which input buffer, which
// decoded frame goes onto the surface, when the decoder starts anew, what is told to the app ("f", "d", "b") is decided
// here, on the frames' thread, as each event is taken. So every order those callbacks can come in is a test's to give
// (Tester::stream_codec_said) and to look at (Tester::stream_fed), not something only a device runs into.
//
// What the host says ("c " then):
//   surf S          its surface is S now (numbered from 1; a new one after the GL context was lost, the old let go once
//                   no decoder draws on it)
//   up G / nostart G decoder G started / could not start (none now)
//   in G I          decoder G's input buffer I is free
//   out G I TS R    decoder G decoded frame TS into output buffer I (R 0: nothing to show in it, a config's or empty)
//   fmt G W H       decoder G's pictures are W × H
//   err G           decoder G failed (its callback, or a call that threw): its state lost
//   rej G I TS      frame TS could not go into input buffer I (not sound AVCC, larger than the buffer)
//   lost G TS       frame TS could not be put on the surface
//   arr S           a frame reached surface S (its frame-available)
// What it is told (`stream_codec`):
//   start G         a decoder G for the config and the surface there are (`up G` or `nostart G` follows)
//   stop G          decoder G stopped and released
//   queue G I TS K  the frame (the bytes beside it, AVCC: the host writes it in Annex B) into input buffer I
//   empty G I TS    input buffer I given back empty
//   release G I TS  output buffer I (frame TS) onto the surface
//   discard G I     output buffer I given back, not shown
//   latch TS N W H  the surface's frame latched (at most N updates, up to the one of time TS) and drawn into the
//                   stream's texture, W × H (now, on the frames' thread)
//   drop N          the surface's N frames no one was told of latched away (now, on the frames' thread)
//
// The rules (Android's remote/Decoders.kt, and what its SurfaceTexture asks):
// - a frame waits for an input buffer; with two inside the decoder, the older counts as taken (a decoder holding frames
//   back would wait for more while the sender waits for an acknowledgement)
// - one decoded frame at a time is on the surface: released, then told ("f") once it arrived, the next released only
//   once the app latched it. A frame that arrives when none was released (one a stopped decoder released just before:
//   its arrival comes after the stop) is latched away before the next is released: left there, the next would take its
//   place in the surface's queue without arriving (replaced), the surface busy for good
// - a decoder that failed, or a new surface, starts anew from a key frame ("b": the sender asked for one); one that
//   could not start is made again for the next key frame, as after a failure

///|
/// What the feed tells its host: a command, with a frame's bytes for "queue" (else empty).
priv struct FeedDo {
  cmd : String
  data : Bytes
}

///|
/// One stream's decoder, driven.
priv struct Feed {
  /// the config's NAL length size (1, 2 or 4); 0: none, or not one
  mut length_size : Int
  /// the surface the host draws on (its number), 0 none yet
  mut surface : Int
  /// the decoder now (its number), 0 none; how many were asked for
  mut gen : Int
  mut gens : Int
  /// frames let go until a key frame
  mut need_key : Bool
  /// frames waiting for an input buffer (time, key, AVCC)
  waiting : Array[(Double, Bool, Bytes)]
  /// the decoder's free input buffers
  inputs : Array[Int]
  /// frames in the decoder, not out yet (their times, in order)
  inside : Array[Double]
  /// frames decoded, in their output buffers, not on the surface yet (buffer, time)
  held : Array[(Int, Double)]
  /// the surface's frame: 0 none released; 1 released, not arrived; 2 arrived, told
  mut slot : Int
  mut slot_ts : Double
  /// frames that arrived on the surface and were not latched
  mut arrived : Int
  /// the decoded picture's size
  mut out_w : Int
  mut out_h : Int
  /// what it said for the app ("f", "d", "b") and what it tells its host, oldest first, taken by the stream
  said : Array[String]
  todo : Array[FeedDo]
}

///|
fn Feed::new() -> Feed {
  {
    length_size: 0,
    surface: 0,
    gen: 0,
    gens: 0,
    need_key: true,
    waiting: [],
    inputs: [],
    inside: [],
    held: [],
    slot: 0,
    slot_ts: 0.0,
    arrived: 0,
    out_w: 0,
    out_h: 0,
    said: [],
    todo: [],
  }
}

///|
fn Feed::tell(self : Feed, cmd : String) -> Unit {
  self.todo.push({ cmd, data: b"" })
}

///|
/// An avcC's NAL length size (1, 2 or 4), 0 when it is not one: version 1, at least one SPS, its sets within it (as
/// src/host/avc.h's mb_avc_parse reads it).
fn avcc_length_size(b : Bytes) -> Int {
  let n = b.length()
  if n < 7 || b[0].to_int() != 1 {
    return 0
  }
  let ls = (b[4].to_int() & 3) + 1
  if ls == 3 {
    return 0
  }
  let mut at = 5
  for kind in 0..<2 {
    if at >= n {
      return 0
    }
    let count = if kind == 0 { b[at].to_int() & 0x1f } else { b[at].to_int() }
    at += 1
    if count > 8 || (kind == 0 && count == 0) {
      return 0
    }
    for _ in 0..<count {
      if at + 2 > n {
        return 0
      }
      let len = (b[at].to_int() << 8) | b[at + 1].to_int()
      at += 2
      if len == 0 || at + len > n {
        return 0
      }
      at += len
    }
  }
  ls
}

///|
/// A config: the decoder starts anew for it (once there is a surface), from the next key frame; one that is not an
/// avcC stops it, frames let go until a sound one.
fn Feed::configure(self : Feed, avcc : Bytes, w : Int, h : Int) -> Unit {
  self.length_size = avcc_length_size(avcc)
  self.out_w = w
  self.out_h = h
  if self.length_size == 0 {
    self.stop()
    return
  }
  self.start()
}

///|
/// A decoder asked for, for the config and surface there are (none without either): the one there was stopped.
fn Feed::start(self : Feed) -> Unit {
  self.stop()
  if self.length_size == 0 || self.surface == 0 {
    return
  }
  self.gens += 1
  self.gen = self.gens
  self.need_key = true
  self.tell("start \{self.gen}")
}

///|
/// The decoder stopped: what was waiting, inside it, decoded and not on the surface, or released and not arrived, let
/// go ("d", the latest of them: taken, as far as the sender is concerned).
fn Feed::stop(self : Feed) -> Unit {
  if self.gen != 0 {
    self.tell("stop \{self.gen}")
  }
  self.gen = 0
  self.inputs.clear()
  let times : Array[Double] = []
  for f in self.waiting {
    times.push(f.0)
  }
  times.append(self.inside)
  for o in self.held {
    times.push(o.1)
  }
  if self.slot == 1 {
    times.push(self.slot_ts)
    self.slot = 0
  }
  let mut max : Double? = None
  for t in times {
    max = match max {
      Some(m) if m >= t => Some(m)
      _ => Some(t)
    }
  }
  match max {
    Some(t) => self.said.push("d \{t}")
    None => ()
  }
  self.waiting.clear()
  self.inside.clear()
  self.held.clear()
  self.need_key = true
}

///|
/// A frame from the sender: into the decoder, or let go ("d") before a key frame or with no decoder. A key frame with
/// none (it could not start) has one made for it.
fn Feed::frame(self : Feed, data : Bytes, key : Bool, ts : Double) -> Unit {
  if self.gen == 0 && key {
    self.start()
  }
  if self.gen == 0 || (self.need_key && !key) {
    self.said.push("d \{ts}")
    return
  }
  self.need_key = false
  self.waiting.push((ts, key, data))
  self.feed()
}

///|
/// The frames waiting into the free input buffers.
fn Feed::feed(self : Feed) -> Unit {
  while self.inputs.length() > 0 && self.waiting.length() > 0 {
    let i = self.inputs.remove(0)
    let (ts, key, data) = self.waiting.remove(0)
    self.inside.push(ts)
    self.todo.push({ cmd: "queue \{self.gen} \{i} \{ts} \{if key { 1 } else { 0 }}", data })
    if self.inside.length() >= 2 {
      self.said.push("d \{self.inside.remove(0)}")
    }
  }
}

///|
/// The next decoded frame onto the surface, when none is there: frames on it no one was told of latched away first.
fn Feed::pump(self : Feed) -> Unit {
  if self.slot != 0 || self.held.length() == 0 {
    return
  }
  if self.arrived > 0 {
    self.tell("drop \{self.arrived}")
    self.arrived = 0
  }
  let (i, ts) = self.held.remove(0)
  self.tell("release \{self.gen} \{i} \{ts}")
  self.slot = 1
  self.slot_ts = ts
}

///|
/// The app shows frame `ts` (its "f" taken): latched, then the next one released.
fn Feed::latch(self : Feed, ts : Double) -> Unit {
  if self.slot != 2 || self.slot_ts != ts {
    return
  }
  self.tell("latch \{ts} \{self.arrived} \{self.out_w} \{self.out_h}")
  self.arrived = 0
  self.slot = 0
  self.pump()
}

///|
/// One of the host's words ("c ..." without the "c ").
fn Feed::event(self : Feed, w : Array[String]) -> Unit {
  let num = fn(i : Int) -> Int {
    match w.get(i) {
      Some(s) =>
        match stream_num(s) {
          Some(d) => d.to_int()
          None => -1
        }
      None => -1
    }
  }
  let dnum = fn(i : Int) -> Double? {
    match w.get(i) {
      Some(s) => stream_num(s)
      None => None
    }
  }
  match w.get(0) {
    Some("surf") => {
      let s = num(1)
      if s <= 0 || s == self.surface {
        return
      }
      let replaced = self.surface != 0
      self.surface = s
      self.arrived = 0
      // a frame told and not shown yet was on the old one: let go with it (its "f" still comes)
      if self.slot == 2 {
        self.slot = 0
      }
      if self.length_size != 0 {
        self.start()
        if replaced {
          self.said.push("b")
        }
      }
    }
    Some("up") => ()
    Some("nostart") =>
      if num(1) == self.gen && self.gen != 0 {
        // (nothing to stop: the host let go of what it made)
        self.gen = 0
        self.stop()
        self.said.push("b")
      }
    Some("in") =>
      if num(1) == self.gen && self.gen != 0 {
        self.inputs.push(num(2))
        self.feed()
      }
    Some("out") =>
      if num(1) == self.gen && self.gen != 0 {
        let i = num(2)
        match dnum(3) {
          Some(ts) if num(4) != 0 => {
            while self.inside.length() > 0 && self.inside[0] <= ts {
              self.inside.remove(0) |> ignore
            }
            self.held.push((i, ts))
            self.pump()
          }
          _ => self.tell("discard \{self.gen} \{i}")
        }
      }
    Some("fmt") =>
      if num(1) == self.gen && self.gen != 0 && num(2) > 0 && num(3) > 0 {
        self.out_w = num(2)
        self.out_h = num(3)
      }
    Some("err") =>
      if num(1) == self.gen && self.gen != 0 {
        self.start()
        self.said.push("b")
      }
    Some("rej") =>
      if num(1) == self.gen && self.gen != 0 {
        match dnum(3) {
          Some(ts) => {
            // not a frame it can take: the buffer given back empty, the next key frame asked for
            self.tell("empty \{self.gen} \{num(2)} \{ts}")
            match self.inside.search(ts) {
              Some(k) => self.inside.remove(k) |> ignore
              None => ()
            }
            self.said.push("d \{ts}")
            self.need_key = true
            self.said.push("b")
          }
          None => ()
        }
      }
    Some("lost") =>
      if num(1) == self.gen && self.gen != 0 {
        match dnum(2) {
          Some(ts) if self.slot == 1 && self.slot_ts == ts => {
            self.slot = 0
            self.said.push("d \{ts}")
            self.pump()
          }
          _ => ()
        }
      }
    Some("arr") =>
      if num(1) == self.surface {
        self.arrived += 1
        if self.slot == 1 {
          self.slot = 2
          self.said.push("f \{self.slot_ts} \{self.out_w} \{self.out_h}")
        }
      }
    _ => ()
  }
}
