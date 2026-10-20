// Messages from outside the frames (docs/determinism.md, rule 1): what a core answers, posted on its channel by the
// host from any thread (src/host/post.h `mb_post`, web/host.js `post`) or by a test (Tester::post), is the
// framework's to keep until a frame begins. Then all that came are taken and handed, in the order posted, to their
// channel's handler (`on_message`), before the frame reads anything: how much of it a frame sees depends on frames,
// never on when the other thread answered. The first posted since a frame took the last asks for one frame; nothing
// asks for frames to look for messages.
//
// Each one handed on is kept on the run's tape (MBUI_DRAW_LOG=1) as a MSG line, before the DRAWHASH line of the frame
// that took it, and `Tester::replay_frames` posts it again there, for that frame to take:
//
//   MSG {"c":CHANNEL,"j":"JSON","b":"BASE64"}     ("b" only with bytes beside it)

///|
// kept across runs: the app's handlers are its code, given once as it starts (by a test's app before its Tester), the
// same for every run; one a channel, a later one in its place
let message_handlers : Map[String, (String, Bytes?) -> Unit] = Map::new()

///|
/// `handler` is given each message posted on `channel`: its JSON and the bytes beside it (None: none), as the frame
/// after it begins, in the order they came. One handler a channel: the last given.
pub fn on_message(channel : String, handler : (String, Bytes?) -> Unit) -> Unit {
  message_handlers[channel] = handler
}

///|
/// A Tester's messages posted and not taken by a frame yet (the fake host's queue), oldest first.
let fake_posted : Array[(String, String, Bytes?)] = []

///|
/// How often a Tester's posts asked for a frame (the first posted since a frame took the last does).
let post_wakes : Ref[Int] = Ref::new(0)

///|
/// How many messages the last frame took and handed to their handlers.
let messages_handed : Ref[Int] = Ref::new(0)

///|
/// What a Tester keeps of its run, as a host's log keeps it with MBUI_DRAW_LOG=1 (Tester::start_tape): DRAWHASH,
/// INPUT and MSG lines. None: nothing kept.
let tape : Ref[Array[String]?] = Ref::new(None)

///|
/// What stands for the outside in a Tester (Tester::between_frames), told as each frame ends.
let between_frames : Ref[(() -> Unit)?] = Ref::new(None)

///|
fn messages_reset() -> Unit {
  fake_posted.clear()
  post_wakes.val = 0
  messages_handed.val = 0
  tape.val = None
  between_frames.val = None
}

///|
/// A frame of a Tester's ended: the outside it stands for says what has come by now (Tester::between_frames).
fn frame_ended_outside() -> Unit {
  match between_frames.val {
    Some(f) => f()
    None => ()
  }
}

///|
/// Whether the run's tape is being kept: on a real host's log (MBUI_DRAW_LOG), or a Tester's (Tester::start_tape).
fn taping() -> Bool {
  draw_logging() || tape.val is Some(_)
}

///|
/// A line of the run's tape, where it is kept.
fn tape_line(s : String) -> Unit {
  if draw_logging() {
    @host.log(s)
  }
  match tape.val {
    Some(lines) => lines.push(s)
    None => ()
  }
}

///|
/// A message posted to the fake host: the first since a frame took the last asks for a frame.
fn fake_post(f : FakeHost, channel : String, json : String, bytes : Bytes?) -> Unit {
  if channel == "" {
    return
  }
  if fake_posted.length() == 0 {
    f.wants = true
    post_wakes.val += 1
  }
  fake_posted.push((channel, json, bytes))
}

///|
/// As a frame begins: all that was posted since the last, taken and handed to their handlers in the order posted
/// (app.mbt frame_body). What is posted meanwhile (a handler's own post, the other thread's) is the next frame's.
fn take_messages() -> Unit {
  messages_handed.val = 0
  match fake.val {
    Some(_) => {
      if fake_posted.length() == 0 {
        return
      }
      let taken = fake_posted.copy()
      fake_posted.clear()
      for m in taken {
        hand_on(m.0, m.1, m.2)
      }
    }
    None => {
      if @host.post_take() == 0 {
        return
      }
      while @host.post_next() is Some((channel, json, b)) {
        hand_on(channel, json, if b.length() > 0 { Some(b) } else { None })
      }
    }
  }
}

///|
fn hand_on(channel : String, json : String, bytes : Bytes?) -> Unit {
  if taping() {
    tape_line("MSG " + message_line(channel, json, bytes))
  }
  match message_handlers.get(channel) {
    Some(f) => {
      messages_handed.val += 1
      f(json, bytes)
    }
    None => h_log("MSG on \{channel}: no handler for it (@ui.on_message): left")
  }
}

///|
fn message_line(channel : String, json : String, bytes : Bytes?) -> String {
  let m : Map[String, Json] = { "c": Json::string(channel), "j": Json::string(json) }
  match bytes {
    Some(b) => m["b"] = Json::string(base64_of(b))
    None => ()
  }
  Json::object(m).stringify()
}

///|
/// Whether a line of a run's log is a MSG line (a dump's text is not one).
fn is_message_line(line : String) -> Bool {
  line.find("MSG {") is Some(_) && line.find("DRAWDUMP ") is None
}

///|
/// One MSG line posted again (Tester::replay_frames): the frame the tape has after it takes it, as the run's did.
fn replay_message(f : FakeHost, line : String) -> Unit {
  guard line.find("MSG {") is Some(i) else { return }
  let j = @json.parse(line.view(start_offset=i + 4).to_owned()) catch { _ => return }
  guard j is Object(m) else { return }
  guard (m.get("c"), m.get("j")) is (Some(String(channel)), Some(String(json))) else { return }
  let bytes = match m.get("b") {
    Some(String(s)) => Some(bytes_of_base64(s))
    _ => None
  }
  fake_post(f, channel, json, bytes)
}

///|
/// Messages posted that no frame has taken: what came from outside and was not seen (Tester::assert_idle). "" when none.
fn posted_left() -> String {
  if fake_posted.length() == 0 {
    return ""
  }
  let on = fake_posted.map(m => m.0)
  "\{fake_posted.length()} messages posted that no frame took (on \{on.join(", ")})"
}

///|
/// A message on `channel` (its JSON, the bytes beside it) posted as a host posts one between frames (mb_post): the
/// next frame takes it, with all posted before it, and hands it to its handler (@ui.on_message) as it begins. The
/// first posted since a frame took the last asks for that frame (Tester::draw draws it). `assert_idle` fails while one
/// is left untaken.
pub fn Tester::post(self : Tester, channel : String, json : String, bytes? : Bytes) -> Unit {
  fake_post(self.fake, channel, json, bytes)
}

///|
/// What stands for the outside in this test (a kept conversation with a core given again: an app's replay): `f` is
/// told as each frame ends, and posts what has come by then (`post`), as a real core's answers come between two
/// frames; the next frame takes them. It asks for no frame itself: a post asks for the one that takes it.
pub fn Tester::between_frames(self : Tester, f : () -> Unit) -> Unit {
  ignore(self)
  between_frames.val = Some(f)
}

///|
/// How many messages are posted and not taken by a frame yet.
pub fn Tester::posted(self : Tester) -> Int {
  ignore(self)
  fake_posted.length()
}

///|
/// How many messages the last frame took and handed to their handlers.
pub fn Tester::messages_taken(self : Tester) -> Int {
  ignore(self)
  messages_handed.val
}

///|
/// How many frames the Tester's posts asked for since it began (one for each lot posted between two frames).
pub fn Tester::post_wakes(self : Tester) -> Int {
  ignore(self)
  post_wakes.val
}

///|
/// How many messages this frame took and handed to their handlers (so far, while it is built: all, as they are
/// handed on before the view builds).
pub fn Ctx::messages_taken(self : Ctx) -> Int {
  ignore(self)
  messages_handed.val
}

///|
/// The run from now on kept as a host's log keeps it with MBUI_DRAW_LOG=1 (`tape`): each frame's DRAWHASH line, the
/// INPUT lines of what came between, the MSG lines of what each took. `replay_frames` gives it again.
pub fn Tester::start_tape(self : Tester) -> Unit {
  ignore(self)
  tape.val = Some([])
  draw_frames.val = 0
  env_kept.val = ""
}

///|
/// The run kept since `start_tape`, a line each ("" when none is kept).
pub fn Tester::tape(self : Tester) -> String {
  ignore(self)
  match tape.val {
    Some(lines) => lines.join("\n")
    None => ""
  }
}

///|
fn base64_char(v : Int) -> Char {
  let n = if v < 26 {
    'A'.to_int() + v
  } else if v < 52 {
    'a'.to_int() + v - 26
  } else if v < 62 {
    '0'.to_int() + v - 52
  } else if v == 62 {
    '+'.to_int()
  } else {
    '/'.to_int()
  }
  n.unsafe_to_char()
}

///|
fn base64_of(b : Bytes) -> String {
  let sb = StringBuilder::new()
  let n = b.length()
  let mut i = 0
  while i < n {
    let a = b[i].to_int()
    let c1 = if i + 1 < n { b[i + 1].to_int() } else { 0 }
    let c2 = if i + 2 < n { b[i + 2].to_int() } else { 0 }
    let v = (a << 16) | (c1 << 8) | c2
    sb.write_char(base64_char((v >> 18) & 63))
    sb.write_char(base64_char((v >> 12) & 63))
    sb.write_char(if i + 1 < n { base64_char((v >> 6) & 63) } else { '=' })
    sb.write_char(if i + 2 < n { base64_char(v & 63) } else { '=' })
    i = i + 3
  }
  sb.to_string()
}

///|
fn base64_digit(c : Char) -> Int {
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

///|
fn bytes_of_base64(s : String) -> Bytes {
  let out : Array[Byte] = []
  let mut acc = 0
  let mut bits = 0
  for c in s {
    let v = base64_digit(c)
    if v < 0 {
      continue
    }
    acc = ((acc << 6) | v) & 0xffffff
    bits = bits + 6
    if bits >= 8 {
      bits = bits - 8
      out.push(((acc >> bits) & 255).to_byte())
    }
  }
  Bytes::from_array(out)
}
