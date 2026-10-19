// The app's one core: the engine (src/host/core_api.h; JavaScriptCore on the Rust shell on macOS and iOS) linked into
// the app, its messages queued by core_native.c and drained here on the UI thread. On Apple's systems the queue wakes
// the main thread itself; a host without a main queue (Android's GL thread) calls `pump` each frame. On the web there
// is no engine yet (js.mbt): `start` says so.

///|
priv struct Engine {
  mut started : Bool
  mut data_dir : String
  mut cloud : String
  mut beta : Bool
  restarts : Array[Double]
  mut on_change : () -> Unit
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
  on_change: fn() {  },
  auths: {},
  next_auth: 1,
}

///|
/// The engine's way in: a message, and the bytes beside it if any.
fn engine_send(s : String, b : Bytes?) -> Unit {
  match b {
    Some(b) => ffi_send_bytes(s, b)
    None => ffi_send(s)
  }
}

///|
/// Where the app's messages go: the engine, or a kept conversation given again (replay.mbt).
let transport : Ref[(String, Bytes?) -> Unit] = { val: engine_send }

///|
/// The wall clock a kept conversation had (replay.mbt), in place of this machine's.
let wall_override : Ref[(() -> Double)?] = { val: None }

///|
/// The app's client of its core.
pub let client : Client = Client::new(
  fn(s) {
    trace_out(s)
    (transport.val)(s, None)
  },
  send_bytes=fn(s, b) {
    trace_out(s)
    (transport.val)(s, Some(b))
  },
)

///|
/// Starts the core: its files in `data_dir` (empty: the platform's place for the app's data, or $MBUI_CORE_DATA),
/// still.fail cloud at `cloud`. Messages are taken on the UI thread as they come; `on_change` is told after each run
/// of them that changed something. False when this build has no engine linked in.
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
  // what the core says is taken as a frame begins (`pump`, the app's frame), never between two: wakes ask for a frame
  ffi_set_wake(fn() { (engine.on_change)() })
  engine.started = ffi_start(data_dir, cloud, if beta { 1 } else { 0 }) != 0
  engine.started
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
/// What to do when something changed: request a frame (the redraw hook; `@host.request_frame` in an mbui app).
pub fn on_change(f : () -> Unit) -> Unit {
  engine.on_change = f
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
  client.fatal
}

///|
/// Takes what the core said since last time, in its order; `on_change` once if any of it changed something. The app
/// calls it as each frame begins, before it reads anything (src/stillfail): what came is seen whole at a frame's
/// boundary, never part-way through one or between two, so how much of it a frame sees depends on frames, not on when
/// the core's thread happened to answer (the queue's wake only asks for a frame).
pub fn pump() -> Unit {
  let v0 = client.version
  let mut n = 0
  while true {
    let text = ffi_next()
    if text.length() == 0 {
      break
    }
    n += 1
    let msg = @json.parse(text) catch { _ => continue }
    match msg {
      Object(m) if m.contains("mbui_auth") => web_auth_done(m)
      _ => {
        let b = ffi_next_bytes()
        let bytes = if b.length() > 0 { Some(b) } else { None }
        trace_in(msg, bytes, ffi_wall_ms())
        client.receive_json(msg, bytes~)
        if client.fatal is Some(_) {
          restart()
        }
      }
    }
  }
  if n > 0 && client.version != v0 {
    (engine.on_change)()
  }
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
}

///|
/// Signs a person in with still.fail cloud: `auth.begin` for the login page, the system's browser session for it
/// (ASWebAuthenticationSession on Apple's systems), which brings back the `stillfail://auth/callback` URL the cloud
/// sends the browser to, then `auth.complete` with its query. `on_done` gets `auth.complete`'s answer
/// (`{account, return_to}`) or why not (the person closed the page, or an error of the core's).
pub fn sign_in(on_done : (Result[Json, Json]) -> Unit) -> Unit {
  let params : Map[String, Json] = {
    "redirect_uri": Json::string("stillfail://auth/callback"),
    "return_to": Json::string("/"),
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
/// Whether this build has the system's browser session `sign_in` needs (ASWebAuthenticationSession on Apple's
/// systems); where it has not (Android), an app signs in on `@host.browser_login` (a loopback address) instead.
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
