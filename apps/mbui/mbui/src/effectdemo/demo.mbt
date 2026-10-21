// The whole program under one clock: an mbui screen, the logic behind it on
// effect.mb, and a backend across a simulated network, all on the window's
// runtime (@ui.runtime): each frame moves it to the frame's time, its timers
// and fibers run, then the screen is built; a tap's handler runs in a frame and
// what it starts runs at the start of the next. Latency, jitter and which ready
// fiber runs first all come from one seed (Tester::new(seed=)): a run is a
// function of its seed.

///|
/// The core of a chat-like app: a send is a request over the network, its
/// reply shown on the screen. `fixed` false is the bug this demo hides on
/// purpose: a reply is shown when it arrives, so a slow reply to an earlier
/// message can land after a quicker one to a later one and replace it.
pub struct Chat {
  priv rt : @effect.Runtime
  priv net : @effect.Net
  priv fixed : Bool
  priv waiting : Map[Int, @effect.Deferred[String]]
  priv mut shown_id : Int
  /// The reply on the screen.
  mut shown : String
  /// Messages sent so far.
  mut sent : Int
  /// Sends not answered yet.
  mut pending : Int
}

///|
pub fn Chat::start(rt : @effect.Runtime, net : @effect.Net, fixed : Bool) -> Chat {
  let chat = {
    rt,
    net,
    fixed,
    waiting: {},
    shown_id: 0,
    shown: "none yet",
    sent: 0,
    pending: 0,
  }
  // what comes back is matched to its request by id
  ignore(
    rt.fork(name="chat inbox", async fn() {
      while true {
        let p = (net.recv)()
        guard p.body.split_once("|") is Some((id, text)) else { continue }
        let id = @string.parse_int(id) catch { _ => continue }
        if chat.waiting.get(id) is Some(d) {
          ignore(d.succeed(text.to_owned()))
        }
      }
    }),
  )
  chat
}

///|
/// The person sent `text` (called from the screen's frame): the request goes
/// out at once, the screen goes on.
pub fn Chat::send(self : Chat, text : String) -> Unit {
  self.sent += 1
  let id = self.sent
  self.pending += 1
  ignore(
    self.rt.fork(name="send \{id}", async fn() {
      let reply = @effect.Deferred::new()
      self.waiting.set(id, reply)
      defer {
        self.waiting.remove(id)
        self.pending -= 1
      }
      (self.net.send)("server", "\{id}|\{text}")
      match @effect.timeout(5000, () => reply.wait()) {
        Some(r) =>
          if !self.fixed || id > self.shown_id {
            self.shown = r
            self.shown_id = id
            @effect.trace("shown reply \{id}")
          } else {
            @effect.trace("stale reply \{id} dropped")
          }
        None => self.shown = "no answer"
      }
    }),
  )
}

///|
/// The backend: each request handled by a fiber of its own, taking as long as
/// the seed says (5–60 ms), so replies can overtake each other.
pub fn backend(rt : @effect.Runtime, net : @effect.Net) -> Unit {
  ignore(
    rt.fork(name="server", () => @effect.scoped(s => {
      while true {
        let p = (net.recv)()
        guard p.body.split_once("|") is Some((id, text)) else { continue }
        let id = id.to_owned()
        let text = text.to_owned()
        ignore(
          s.fork(async fn() {
            @effect.sleep(rt.rng.between(5, 60))
            (net.send)(p.from, "\{id}|\{text.to_upper()}")
          }),
        )
      }
    })),
  )
}

///|
/// The screen: a Send button, the reply, how many wait.
pub fn view(chat : Chat) -> (@ui.Ctx) -> Unit {
  fn(c) {
    c.column(w=Fill(1.0), pad=20.0, gap=12.0, fn() {
      if c.button("Send") {
        chat.send("message \{chat.sent + 1}")
      }
      c.text("reply: \{chat.shown}") |> ignore
      c.text("waiting: \{chat.pending}") |> ignore
    })
    |> ignore
  }
}

///|
/// The screen and the core on one clock.
pub struct World {
  t : @ui.Tester
  rt : @effect.Runtime
  chat : Chat
  net : @effect.SimNet
  /// What happened, frame by frame.
  frames : Array[String]
}

///|
/// A world on `seed`: the app (`fixed` or not), its backend, a network with
/// 10 ms latency and up to 40 ms jitter, on the window's runtime.
pub fn World::new(seed : Int, fixed~ : Bool) -> World {
  let screen : Ref[(@ui.Ctx) -> Unit] = Ref(fn(_c) { () })
  let t = @ui.Tester::new(c => (screen.val)(c), w=390.0, h=300.0, seed~)
  let rt = @ui.runtime()
  let net = @effect.SimNet::new(rt, latency=10, jitter=40)
  backend(rt, net.endpoint("server"))
  let chat = Chat::start(rt, net.endpoint("app"), fixed)
  screen.val = view(chat)
  let w = { t, rt, chat, net, frames: [] }
  w.step()
  w
}

///|
/// One frame: the runtime runs up to the frame's time, then the screen is built.
pub fn World::step(self : World, ms? : Int = 16) -> Unit {
  self.t.frame(ms=ms.to_double())
  self.frames.push("\{self.rt.now()} \{self.chat.shown} (\{self.chat.pending} waiting)")
}

///|
/// A tap on the text `label`: finger down, a frame, up, a frame.
pub fn World::tap(self : World, label : String) -> Unit {
  guard self.t.find(label) is Some((x, y)) else { abort("no \{label} on screen") }
  self.t.touch(0, x, y)
  self.step()
  self.t.touch(2, x, y)
  self.step()
}

///|
/// Everything the run did: the core's trace, the network's, the frames.
pub fn World::trace(self : World) -> String {
  [self.rt.trace_text(), self.net.log.join("\n"), self.frames.join("\n")].join(
    "\n--\n",
  )
}

///|
/// The person taps Send twice, a few frames apart (as many as the seed
/// says), then waits; true when the screen ends showing the reply to the
/// second message, as it must.
pub fn World::two_sends(self : World) -> Bool {
  self.tap("Send")
  for _ in 0..<self.rt.rng.between(0, 3) {
    self.step()
  }
  self.tap("Send")
  let mut n = 0
  while n < 100 && (self.chat.pending > 0 || n < 5) {
    self.step()
    n += 1
  }
  self.t.find("reply: MESSAGE 2") is Some(_) &&
  self.t.find("waiting: 0") is Some(_)
}
