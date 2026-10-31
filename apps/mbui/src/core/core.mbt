// The app's one core: the engine (src/host/core_api.h; Hermes on the Rust shell, on macOS, iOS, Android and Windows)
// linked into the app, its messages posted by core_native.c to mbui's queue on the channel "core" (mb_post, any thread), which hands each to `receive`
// on the UI thread as the next frame begins (the app's `@ui.on_message("core", @core.receive)`). In a browser it is the
// page's (js.mbt: still.fail's web core worker, its messages posted to the same queue).

///|
priv struct Engine {
  mut started : Bool
  mut data_dir : String
  mut cloud : String
  mut beta : Bool
  restarts : Array[Double]
  auths : Map[Int, (Result[String, String]) -> Unit]
  mut next_auth : Int
}

///|
let engine : Engine = {
  started: false,
  data_dir: "",
  cloud: "",
  beta: false,
  restarts: [],
  auths: {},
  next_auth: 1,
}

///|
/// The engine's way in: a message, and the bytes beside it if any.
fn engine_send(s : String, b : Bytes?) -> Unit {
  // (on the app's own clock, the core told it first: what this sets off is timed from now)
  clock_before_send()
  match b {
    Some(b) => ffi_send_bytes(s, b)
    None => ffi_send(s)
  }
}

///|
/// Where the app's messages go: the engine, or a kept conversation given again (replay.mbt).
let transport : Ref[(String, Bytes?) -> Unit] = { val: engine_send }

///|
/// Told as each message is received, before it is (a kept conversation given again: its wall clock then, replay.mbt).
let receive_hook : Ref[(() -> Unit)?] = { val: None }

///|
/// The wall clock a kept conversation had (replay.mbt), in place of this machine's.
let wall_override : Ref[(() -> Double)?] = { val: None }

///|
/// The app's client of its core.
pub let client : Client = Client::new(
  fn(s) {
    trace_out(s, ffi_wall_ms())
    (transport.val)(s, None)
  },
  send_bytes=fn(s, b) {
    trace_out(s, ffi_wall_ms(), bytes=b)
    (transport.val)(s, Some(b))
  },
)

///|
/// Starts the core: its files in `data_dir` (empty: the platform's place for the app's data, or $MBUI_CORE_DATA),
/// still.fail cloud at `cloud`. What it says is taken as a frame begins (mbui's queue, the app's handler for "core":
/// `receive`). False when this build has no engine linked in.
pub fn start(
  data_dir? : String = "",
  cloud? : String = "https://app.still.fail",
  beta? : Bool = false,
) -> Bool {
  if engine.started {
    return true
  }
  engine.data_dir = data_dir
  engine.cloud = cloud
  engine.beta = beta
  engine.started = ffi_start(data_dir, cloud, if beta { 1 } else { 0 }) != 0
  engine.started
}

///|
/// Where still.fail cloud is, as the core was started with it (`start`'s `cloud`).
pub fn cloud() -> String {
  engine.cloud
}

///|
/// Ends the core (waits for its thread); nothing comes from it after.
pub fn stop() -> Unit {
  if engine.started {
    ffi_stop()
    engine.started = false
  }
}

///|
/// What is asked of the core is awaited until answered or first read (see Client::track): an mbui app gives its
/// runtime's `outside_start` and `outside_end`, so its screens are settled only once what they asked of the core is in.
pub fn track(start : (String) -> Int, end : (Int) -> Unit) -> Unit {
  client.track(start, end)
}

///|
/// The subscription to `topic` (see Client::subscribe): the same one each time it is asked, so a view can call it
/// every frame.
pub fn subscribe(topic : String, params? : Map[String, Json] = {}) -> Sub {
  client.subscribe(topic, params~)
}

///|
/// Calls `name` (see Client::call); `bytes` beside it.
pub fn call(
  name : String,
  params? : Json = Json::object({}),
  bytes? : Bytes? = None,
  on_done? : (Result[Json, Json]) -> Unit = fn(_) {  },
) -> Unit {
  client.call(name, params~, bytes~, on_done~) |> ignore
}

///|
/// Calls `name` for an answer with bytes beside it (see Client::call_bytes):
/// `media.image`'s picture, say.
pub fn call_bytes(
  name : String,
  params? : Json = Json::object({}),
  on_done~ : (Result[(Json, Bytes?), Json]) -> Unit,
) -> Unit {
  client.call_bytes(name, params~, on_done~) |> ignore
}

///|
/// Calls `name` and hears how it goes (see Client::stream); the call's id, for `cancel`.
pub fn stream(
  name : String,
  params? : Json = Json::object({}),
  bytes? : Bytes? = None,
  on_value~ : (Json, Bytes?) -> Unit,
  on_done? : (Result[Json, Json]) -> Unit = fn(_) {  },
) -> Int {
  client.stream(name, params~, bytes~, on_value~, on_done~)
}

///|
/// A remote screen's frame `ts` acknowledged straight to its station, where the engine's shell reads the view of call
/// `call` itself (Apple's: client/shell `istream.tap`): no message to the core, no answer. False: not so (the app
/// calls `screen.ack`).
pub fn screen_ack(call : Int, ts : Double) -> Bool {
  ffi_screen_ack(call.to_double(), ts) != 0
}

///|
/// The values of call `name` for which `f` says true change nothing a frame reads: taken as they come, they build
/// nothing (Client::quiet). Said once, as the app starts.
pub fn quiet(name : String, f : (Json) -> Bool) -> Unit {
  client.quiet(name, f)
}

///|
/// Nobody reads the answer of call `name`: taken as it comes, it builds nothing (Client::unread). Said once, as the app
/// starts.
pub fn unread(name : String) -> Unit {
  client.unread(name)
}

///|
/// Calls `name` and hears how it goes, for an answer with bytes beside it (see Client::stream_bytes); the call's id,
/// for `cancel`.
pub fn stream_bytes(
  name : String,
  params? : Json = Json::object({}),
  on_value~ : (Json, Bytes?) -> Unit,
  on_done~ : (Result[(Json, Bytes?), Json]) -> Unit,
) -> Int {
  client.stream_bytes(name, params~, on_value~, on_done~)
}

///|
/// A streamed call stopped (see Client::cancel).
pub fn cancel(id : Int) -> Unit {
  client.cancel(id)
}

///|
/// The time of day, in milliseconds since 1970: when something was done, as
/// the core and the stations compare it (a reading place's `at`).
pub fn wall_ms() -> Double {
  match wall_override.val {
    Some(f) => f()
    None => ffi_wall_ms()
  }
}

///|
/// Ends a subscription.
pub fn unsubscribe(s : Sub) -> Unit {
  client.unsubscribe(s)
}

///|
/// The core's reason when it has failed and was not started again.
pub fn fatal() -> String? {
  client.fatal_said.get() |> ignore
  client.fatal
}

///|
/// What the core said, one message (its JSON, the bytes beside it): the app's handler for mbui's channel "core"
/// (`@ui.on_message("core", @core.receive)`), which mbui calls as a frame begins with everything posted since the last,
/// in the order it came; so what came is seen whole at a frame's boundary, never part-way through one, and how much a
/// frame sees depends on frames, not on when the core's thread answered. A kept conversation given again (replay.mbt)
/// comes this way too.
pub fn receive(text : String, bytes : Bytes?) -> Unit {
  let t0 = if @hostapi.perf_recording() { ffi_now() } else { -1.0 }
  let msg = @json.parse(text) catch { _ => return }
  let what = if t0 >= 0.0 { client.perf_name(msg) } else { "" }
  take(msg, bytes)
  if t0 >= 0.0 {
    perf_in(what, text, bytes, ffi_now() - t0)
  }
}

///|
/// While the device's performance record is kept: what the core said to the app, by what it was (Client::perf_name),
/// each its count, bytes and the app's time taking it (ms: parsed, a topic's delta applied, a call's answer handed
/// on); and what the app asked of the core, by name, each its count. Said and begun again with each summary of the
/// frames (perf_said).
// kept across runs: the record's counts, taken by perf_said
let perf_ins : Map[String, (Int, Int, Double)] = {}

///|
// kept across runs: the record's counts, taken by perf_said
let perf_outs : Map[String, Int] = {}

///|
fn perf_in(what : String, text : String, bytes : Bytes?, ms : Double) -> Unit {
  let n = text.length() +
    (match bytes {
      Some(b) => b.length()
      None => 0
    })
  let (k, b, t) = perf_ins.get(what).unwrap_or((0, 0, 0.0))
  perf_ins[what] = (k + 1, b + n, t + ms)
}

///|
/// What the app asked of the core (a call's name, `sub <topic>`), counted while the record is kept (Client::call,
/// Client::ask).
fn perf_out(what : String) -> Unit {
  if @hostapi.perf_recording() {
    perf_outs[what] = perf_outs.get(what).unwrap_or(0) + 1
  }
}

///|
/// The record's line of the core's messages since it was last asked (@ui.perf_also "core"), the heaviest first:
/// `in (ms/count/KB, the 6 longest): 3.2ms/12/40.1KB topic chats delta | … || out (count, the 6 most): 4 chat.read |
/// …`; "" where none came or went. Begun again.
pub fn perf_said(span : Double) -> String {
  ignore(span)
  if !@hostapi.perf_recording() {
    client.perf_forget()
  }
  if perf_ins.is_empty() && perf_outs.is_empty() {
    return ""
  }
  let ins = perf_ins.to_array()
  ins.sort_by(fn(a, b) { b.1.2.compare(a.1.2) })
  let outs = perf_outs.to_array()
  outs.sort_by(fn(a, b) { b.1.compare(a.1) })
  let line = StringBuilder::new()
  line.write_string("in (ms/count/KB, the 6 longest):")
  for i, e in ins {
    if i >= 6 {
      break
    }
    let (k, b, t) = e.1
    line.write_string((if i == 0 { " " } else { " | " }) + "\{(t * 10.0).round() / 10.0}ms/\{k}/\{(b.to_double() / 102.4).round() / 10.0}KB \{e.0}")
  }
  line.write_string(" || out (count, the 6 most):")
  for i, e in outs {
    if i >= 6 {
      break
    }
    line.write_string((if i == 0 { " " } else { " | " }) + "\{e.1} \{e.0}")
  }
  perf_ins.clear()
  perf_outs.clear()
  line.to_string()
}

///|
/// What the core said, taken as it comes where it is a topic's change alone (Client::topic_said: what it changes is its
/// topic's signal and nothing else) or a call's that changes nothing a frame reads (Client::call_said: a quiet value, an
/// answer nobody reads), before the frame decides what it does: what read the topic is built again, nothing else
/// (@ui.on_message_said, "core"). Whether it was; else it is left for `receive`, as the frame is built.
pub fn receive_said(text : String, bytes : Bytes?) -> Bool {
  let t0 = if @hostapi.perf_recording() { ffi_now() } else { -1.0 }
  let msg = @json.parse(text) catch { _ => return false }
  match msg {
    Object(m) if !m.contains("mbui_auth") &&
      !m.contains("clocked") &&
      (client.topic_said(m) || client.call_said(m)) => {
      let what = if t0 >= 0.0 { client.perf_name(msg) } else { "" }
      take(msg, bytes)
      if t0 >= 0.0 {
        perf_in(what, text, bytes, ffi_now() - t0)
      }
      true
    }
    _ => false
  }
}

///|
fn take(msg : Json, bytes : Bytes?) -> Unit {
  match msg {
    Object(m) if m.contains("mbui_auth") => web_auth_done(m)
    Object(m) if m.contains("clocked") => clocked(m)
    // (the web's: the tab whose worker ran the core went, another tab's runs it now, web/src/core/worker.ts: asked
    // again what this client had asked of the one before)
    Object(m) if m.contains("rejoin") => client.restarted()
    _ => {
      match receive_hook.val {
        Some(f) => f()
        None => ()
      }
      trace_in(msg, bytes, ffi_wall_ms())
      client.receive_json(msg, bytes~)
      if client.fatal is Some(_) && engine.started {
        // (told before it is started again: the reason is the only trace of the core's own failure)
        match on_failed.val {
          Some(f) => f(client.fatal.unwrap())
          None => ()
        }
        restart()
      }
    }
  }
}

///|
/// Told as the core fails, with its reason, before it is started again (or stopped, a third time in a minute): still.fail's
/// Android app reports it as CoreFailed (StillFailCore.onFailed, Crashes.kt), as src/stillfail's host does.
pub let on_failed : Ref[((String) -> Unit)?] = { val: None }

///|
/// What the app times of its topics as they are subscribed and first read (Client::time_topics).
pub fn time_topics(f : ((Int, String, Json?, Bool) -> Unit)?) -> Unit {
  client.time_topics(f)
}

///|
/// A core that failed is stopped and another started, as the Android and desktop apps do; not more than 3 times a
/// minute, so a core that fails as it starts does not spin.
fn restart() -> Unit {
  let now = ffi_now()
  let recent = engine.restarts.filter(fn(t) { now - t < 60000.0 })
  if recent.length() >= 3 {
    stop()
    return
  }
  engine.restarts.clear()
  for t in recent {
    engine.restarts.push(t)
  }
  engine.restarts.push(now)
  ffi_stop()
  engine.started = ffi_start(engine.data_dir, engine.cloud, if engine.beta {
    1
  } else {
    0
  }) !=
    0
  client.restarted()
  // (a core started anew runs on real time until told the app's clock again)
  clock_again()
}

///|
/// Signs a person in with still.fail cloud: `auth.begin` for the login page, the system's browser session for it
/// (ASWebAuthenticationSession on iOS), which brings back the `stillfail://auth/callback` URL the cloud
/// sends the browser to, then `auth.complete` with its query. `on_done` gets `auth.complete`'s answer
/// (`{account, return_to}`) or why not (the person closed the page, or an error of the core's).
pub fn sign_in(on_done : (Result[Json, Json]) -> Unit) -> Unit {
  let params : Map[String, Json] = {
    "redirect_uri": Json::string(auth_redirect()),
    "return_to": Json::string(auth_return_to()),
  }
  client.call("auth.begin", params=Json::object(params), on_done=fn(r) {
    match r {
      Ok(Object(ok)) =>
        match ok.get("url") {
          Some(String(url)) => {
            let token = engine.next_auth
            engine.next_auth += 1
            engine.auths[token] = fn(back) {
              match back {
                Ok(query) =>
                  client.call(
                    "auth.complete",
                    params=Json::object({ "query": Json::string(query) }),
                    on_done~,
                  )
                  |> ignore
                Err(why) => on_done(Err(error_json("auth", why)))
              }
            }
            if ffi_web_auth(token, url, "stillfail") == 0 {
              engine.auths.remove(token)
              on_done(Err(error_json("auth", "no browser session in this build")))
            }
          }
          _ => on_done(Err(error_json("auth", "auth.begin gave no url")))
        }
      Ok(_) => on_done(Err(error_json("auth", "auth.begin gave no url")))
      Err(e) => on_done(Err(e))
    }
  })
  |> ignore
}

///|
/// Whether this build has the system's browser session `sign_in` needs (ASWebAuthenticationSession on iOS); where it
/// has not (Android, macOS, Windows), an app signs in on `@hostapi.browser_login` (a loopback address) instead.
pub fn has_browser_session() -> Bool {
  ffi_has_web_auth() != 0
}

///|
fn error_json(code : String, message : String) -> Json {
  Json::object({ "code": Json::string(code), "message": Json::string(message) })
}

///|
/// The browser session's end (core_native.c queues it as `{mbui_auth, url}` or `{mbui_auth, error}`).
fn web_auth_done(m : Map[String, Json]) -> Unit {
  let token = match m.get("mbui_auth") {
    Some(Number(d, ..)) => d.to_int()
    _ => return
  }
  guard engine.auths.get(token) is Some(f) else { return }
  engine.auths.remove(token)
  match (m.get("url"), m.get("error")) {
    (Some(String(url)), _) => f(Ok(query_of(url)))
    (_, Some(String(e))) => f(Err(e))
    _ => f(Err("the browser session ended"))
  }
}

///|
/// A URL's query string, without its `?` (and without a `#fragment`).
pub fn query_of(url : String) -> String {
  let q = match url.find("?") {
    Some(i) => url.view(start_offset=i + 1)
    None => return ""
  }
  match q.find("#") {
    Some(j) => q.view(end_offset=j).to_owned()
    None => q.to_owned()
  }
}
