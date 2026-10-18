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
  listens : Map[Int, (Asked?) -> Unit]
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
  listens: {},
}

///|
/// The app's client of its core.
pub let client : Client = Client::new(fn(s) { ffi_send(s) })

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
  ffi_set_wake(fn() { pump() })
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
/// Calls `name` (see Client::call).
pub fn call(
  name : String,
  params? : Json = Json::object({}),
  on_done? : (Result[Json, Json]) -> Unit = fn(_) {  },
) -> Unit {
  client.call(name, params~, on_done~) |> ignore
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
/// The time of day, in milliseconds since 1970: when something was done, as
/// the core and the stations compare it (a reading place's `at`).
pub fn wall_ms() -> Double {
  ffi_wall_ms()
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
/// Takes what the core said since last time; `on_change` once if any of it changed something. On Apple's systems the
/// main queue calls this; elsewhere the host calls it each frame.
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
      Object(m) if m.contains("mbui_listen") => listen_took(m)
      _ => {
        let bytes = ffi_next_bytes()
        client.receive_json(msg, bytes=if bytes.length() > 0 {
          Some(bytes)
        } else {
          None
        })
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

///|
/// A request that came to one of the app's listeners (`listen`): its number (what `Listener::respond` answers), its
/// method, its path with its query, its headers as they came.
pub(all) struct Asked {
  request : Int
  method : String
  path : String
  headers : Array[(String, String)]
}

///|
/// The value of header `name` (any case), the first one.
pub fn Asked::header(self : Asked, name : String) -> String? {
  let want = name.to_lower()
  for h in self.headers {
    if h.0.to_lower() == want {
      return Some(h.1)
    }
  }
  None
}

///|
/// One of the app's loopback listeners: where it listens (127.0.0.1, `port`).
pub struct Listener {
  token : Int
  port : Int
}

///|
/// Listens on 127.0.0.1 at `port` (0: one the system picks), for a browser coming back to this machine. Each request
/// comes to `on_request` on the UI thread, to be answered once (`Listener::respond`); `None` once the listener has
/// closed. Err when the port is taken, or this build has no listener (the web).
pub fn listen(
  port? : Int = 0,
  on_request : (Asked?) -> Unit,
) -> Result[Listener, String] {
  let token = engine.next_auth
  engine.next_auth += 1
  let bound = ffi_listen_open(token, port)
  if bound < 0 {
    return Err("no listener in this build")
  }
  if bound == 0 {
    return Err("port \{port} is taken")
  }
  engine.listens[token] = on_request
  Ok({ token, port: bound })
}

///|
/// Answers request `request` (its connection closes after).
pub fn Listener::respond(
  self : Listener,
  request : Int,
  status : Int,
  content_type : String,
  body : String,
) -> Unit {
  ffi_listen_respond(self.token, request, status, content_type, body)
}

///|
/// Stops listening, once what was answered is written: `on_request` is told `None`.
pub fn Listener::close(self : Listener) -> Unit {
  ffi_listen_close(self.token)
}

///|
/// What a listener took (core_native.c queues it as `{mbui_listen, request, method, path, headers}`, or
/// `{mbui_listen, end}`).
fn listen_took(m : Map[String, Json]) -> Unit {
  let token = match m.get("mbui_listen") {
    Some(Number(d, ..)) => d.to_int()
    _ => return
  }
  guard engine.listens.get(token) is Some(f) else { return }
  if m.get("end") is Some(True) {
    engine.listens.remove(token)
    f(None)
    return
  }
  let headers = []
  if m.get("headers") is Some(Array(list)) {
    for h in list {
      if h is Array([String(k), String(v), ..]) {
        headers.push((k, v))
      }
    }
  }
  let text = fn(k : String) {
    match m.get(k) {
      Some(String(v)) => v
      _ => ""
    }
  }
  let request = match m.get("request") {
    Some(Number(d, ..)) => d.to_int()
    _ => 0
  }
  f(Some({ request, method: text("method"), path: text("path"), headers }))
}

///|
/// Where `sign_in_loopback`'s browser comes back to, on the port the listener got.
let loopback_path = "/oauth/callback"

///|
/// Signs a person in with a browser that comes back to this machine, the way a command-line tool does: listens on
/// 127.0.0.1 (a port the system picks), `auth.begin` with `http://127.0.0.1:<port>/oauth/callback`, hands the login
/// page's URL to `open` (an app opens the default browser; a station's remote login takes it from there, and relays
/// the person's browser coming back on their phone: ember docs/remote-login.md), then `auth.complete` with the
/// callback's query, answers the browser with a page saying how it went, and closes. `on_done` gets
/// `auth.complete`'s answer (`{account, return_to}`) or why not, once the page is out.
pub fn sign_in_loopback(
  open~ : (String) -> Unit,
  on_done : (Result[Json, Json]) -> Unit,
  device_name? : String = "",
) -> Unit {
  let mut listener : Listener? = None
  // What on_done gets once the listener has closed (the page written first); None until the callback is in.
  let mut result : Result[Json, Json]? = None
  let mut taken = false
  let finish = fn(r : Result[Json, Json]) {
    result = Some(r)
    match listener {
      Some(l) => l.close()
      None => on_done(r)
    }
  }
  let opened = listen(fn(asked) {
    guard listener is Some(l) else { return }
    match asked {
      None =>
        on_done(
          result.unwrap_or(Err(error_json("auth", "the listener closed before the browser came back"))),
        )
      Some(a) => {
        let path = match a.path.find("?") {
          Some(i) => a.path.view(end_offset=i).to_owned()
          None => a.path
        }
        let host = a.header("host").unwrap_or("")
        // Only the browser coming back to this sign-in: its address (a page elsewhere naming 127.0.0.1 by another
        // name, DNS rebinding, is not), its path, once.
        let ours = host == "127.0.0.1:\{l.port}" || host == "localhost:\{l.port}"
        if taken || !ours || a.method != "GET" || path != loopback_path {
          l.respond(a.request, 404, "text/html; charset=utf-8", page("Not found", "这不是这次登录的地址 · Not this sign-in"))
          return
        }
        taken = true
        let params : Map[String, Json] = { "query": Json::string(query_of(a.path)) }
        client.call("auth.complete", params=Json::object(params), on_done=fn(r) {
          let html = match r {
            Ok(Object(m)) => {
              let email = match m.get("account") {
                Some(Object(acc)) =>
                  match acc.get("email") {
                    Some(String(e)) => e
                    _ => ""
                  }
                _ => ""
              }
              page("Signed in", "已登录 still.fail\{if email != "" { "：" + email } else { "" }} · Signed in\n可以关掉这个页面 · You can close this page")
            }
            Ok(_) => page("Signed in", "已登录 still.fail · Signed in\n可以关掉这个页面 · You can close this page")
            Err(e) => {
              let why = match e {
                Object(m) =>
                  match m.get("message") {
                    Some(String(s)) => s
                    _ => e.stringify()
                  }
                _ => e.stringify()
              }
              page("Sign-in failed", "登录没有完成 · Sign-in failed\n" + why)
            }
          }
          l.respond(a.request, 200, "text/html; charset=utf-8", html)
          finish(r)
        })
        |> ignore
      }
    }
  })
  match opened {
    Err(why) => {
      on_done(Err(error_json("auth", why)))
      return
    }
    Ok(l) => listener = Some(l)
  }
  let l = listener.unwrap()
  let params : Map[String, Json] = {
    "redirect_uri": Json::string("http://127.0.0.1:\{l.port}" + loopback_path),
    "return_to": Json::string("/"),
  }
  if device_name != "" {
    params["device_name"] = Json::string(device_name)
  }
  client.call("auth.begin", params=Json::object(params), on_done=fn(r) {
    match r {
      Ok(Object(ok)) =>
        match ok.get("url") {
          Some(String(url)) => open(url)
          _ => finish(Err(error_json("auth", "auth.begin gave no url")))
        }
      Ok(_) => finish(Err(error_json("auth", "auth.begin gave no url")))
      Err(e) => finish(Err(e))
    }
  })
  |> ignore
}

///|
/// A small page for the browser: `title`, then `text`'s lines.
fn page(title : String, text : String) -> String {
  let body = StringBuilder::new()
  for line in text.split("\n") {
    body.write_string("<p>" + escape_html(line.to_string()) + "</p>")
  }
  "<!doctype html><meta charset=utf-8><meta name=viewport content=\"width=device-width\"><title>" +
  escape_html(title) +
  "</title><body style=\"font:16px -apple-system,system-ui,sans-serif;margin:3em 2em;color:#1c1c1e\">" +
  body.to_string() +
  "</body>"
}

///|
fn escape_html(s : String) -> String {
  let b = StringBuilder::new()
  for ch in s {
    match ch {
      '&' => b.write_string("&amp;")
      '<' => b.write_string("&lt;")
      '>' => b.write_string("&gt;")
      '"' => b.write_string("&quot;")
      _ => b.write_char(ch)
    }
  }
  b.to_string()
}
