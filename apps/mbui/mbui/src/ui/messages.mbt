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
// kept across runs: as message_handlers, the app's code
let message_said : Map[String, (String, Bytes?) -> Bool] = Map::new()

///|
/// What of a message on `channel` changes only signals, taken by `said` as it comes, as the frame begins, before it is
/// decided what the frame does: `said` answers whether it took it (all it changes said by signals: what read them is
/// built again, nothing else); one it does not take is handed to the channel's handler (on_message) as the frame is
/// built, which builds the whole frame again (what came from outside and is no signal). In the order they came: once one
/// is left for the handler, those after it are too.
pub fn on_message_said(channel : String, said : (String, Bytes?) -> Bool) -> Unit {
  message_said[channel] = said
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
/// When that outside has its next to say (Tester::between_frames' `due`): +inf, nothing it knows of.
let outside_due : Ref[(() -> Double)?] = Ref::new(None)

///|
fn messages_reset() -> Unit {
  fake_posted.clear()
  messages_in.clear()
  said_left.val = 0
  post_wakes.val = 0
  messages_handed.val = 0
  tape.val = None
  between_frames.val = None
  outside_due.val = None
  system_bars_now.val = { top: 0.0, bottom: 0.0, left: 0.0, right: 0.0 }
  system_size_class_now.val = None
  system_fold_now.val = { hinge: NoHinge, divisions: [] }
  system_nav_action_now.val = None
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
    @hostapi.log(s)
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
/// What was posted since the last frame, taken as this one begins (messages_arrive), for its build to hand on.
// kept across runs: taken as each frame begins, handed on by its build (take_messages)
let messages_in : Array[(String, String, Bytes?)] = []

///|
/// As a frame begins, before it is decided what it does again (frame_watch.mbt): all that was posted since the last,
/// taken from the host in the order posted, said come from outside where any came (so the frame is built and hands
/// them on: take_messages).
fn messages_arrive() -> Unit {
  messages_handed.val = 0
  let came : Array[(String, String, Bytes?)] = []
  match fake.val {
    Some(_) =>
      if fake_posted.length() > 0 {
        for m in fake_posted {
          came.push(m)
        }
        fake_posted.clear()
      }
    None =>
      if @hostapi.post_take() > 0 {
        while @hostapi.post_next() is Some((channel, json, b)) {
          came.push((channel, json, if b.length() > 0 { Some(b) } else { None }))
        }
      }
  }
  messages_take(came)
  if messages_in.length() > 0 {
    outside_counted()
  }
}

///|
/// Between frames, something was posted (hostcall.mbt's outside_posted: a host that says so rather than asking for a
/// frame): taken now, what changes only signals handed to its handler as it comes (a topic's change, a remote screen's
/// frame), the rest kept for the next frame, which is asked for only then. Under a Tester the frame takes what came.
fn messages_between() -> Unit {
  // (while a frame runs, or under a Tester: the frame takes it, as it begins)
  if fake.val is Some(_) || in_frame.val || frame_running.val {
    outside_counted()
    return
  }
  if @hostapi.post_take() == 0 {
    return
  }
  let came : Array[(String, String, Bytes?)] = []
  while @hostapi.post_next() is Some((channel, json, b)) {
    came.push((channel, json, if b.length() > 0 { Some(b) } else { None }))
  }
  messages_take(came)
  // (what is left: a frame, which hands it on)
  if messages_in.length() > 0 {
    outside_left()
  }
}

///|
/// What came, in the order it came: while nothing is left for a handler, what changes only signals taken now
/// (`on_message_said`); from the first that is not, it and all after it left for the frame (messages_in).
fn messages_take(came : Array[(String, String, Bytes?)]) -> Unit {
  // (one event, at its own moment: what had ended by then settled before any handler runs, view_host.mbt)
  view_event(fn() { messages_take_now(came) })
}

///|
fn messages_take_now(came : Array[(String, String, Bytes?)]) -> Unit {
  // (what changes only signals taken now, in the order they came, till one is left for its handler: messages_in)
  for m in came {
    if messages_in.is_empty() {
      match message_said.get(m.0) {
        Some(said) => {
          if taping() {
            tape_line("MSG " + message_line(m.0, m.1, m.2))
          }
          if said(m.1, m.2) {
            messages_handed.val += 1
            continue
          }
          // (left: handed on as the frame is built, its MSG line on the tape already)
          said_left.val = said_left.val + 1
        }
        None => ()
      }
    }
    messages_in.push(m)
  }
}

///|
/// How many of the messages left for their handlers were put on the tape as they came (messages_arrive): not again as
/// they are handed on.
// kept across runs: taken as each frame's messages are handed on
let said_left : Ref[Int] = Ref(0)

///|
/// As a frame is built: all that was posted since the last (messages_arrive), handed to their handlers in the order
/// posted (app.mbt frame_body). What is posted meanwhile (a handler's own post, the other thread's) is the next frame's.
fn take_messages() -> Unit {
  if messages_in.length() == 0 {
    return
  }
  let taken = messages_in.copy()
  messages_in.clear()
  for m in taken {
    hand_on(m.0, m.1, m.2)
  }
}

///|
fn hand_on(channel : String, json : String, bytes : Bytes?) -> Unit {
  outside_came()
  if said_left.val > 0 {
    said_left.val = said_left.val - 1
  } else if taping() {
    tape_line("MSG " + message_line(channel, json, bytes))
  }
  if channel == @hostapi.system_channel {
    system_took(json)
  }
  // the framework's own: what a screen reader asks of a widget (a11y.mbt)
  if channel == @hostapi.a11y_channel {
    messages_handed.val += 1
    a11y_took(json)
    return
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
    Some(b) => m["b"] = Json::string(@codec.base64(b))
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
    Some(String(s)) => Some(@codec.from_base64(s))
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
/// frames; the next frame takes them. It asks for no frame itself: a post asks for the one that takes it. `due`: when
/// it has its next to say (a kept message's moment; +inf: nothing it knows of), a moment run_for draws a frame at, as
/// a host's message that comes then: what comes at a time comes at it, however the clock was run on.
pub fn Tester::between_frames(self : Tester, f : () -> Unit, due? : () -> Double) -> Unit {
  ignore(self)
  between_frames.val = Some(f)
  outside_due.val = due
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

