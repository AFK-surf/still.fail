// A service's page speaking with the app (ember apps/android chat/screens/PreviewWeb.kt PreviewLink, page.js): page.js
// first in each of its pages (/_stillfail/page.js, its tag put in each of the service's HTML pages), behind a script of
// the app's that gives it there what the Android app's JavascriptInterface (StillFailPreviewNative) gives it: its
// WebSockets carried through the core (preview.socket), its requests' bodies left here before they go (stash), its top
// page's fetch() answered here piece by piece as the station sends it (its port), what marking it picks (marked).
// Every call of the page's a message to the app (mbuiHost.post), in the order made; what the app says back a script it
// runs in the page (NativeView::script). Nothing the page says is trusted: any script in it may say anything.

///|
/// The page's own script, served here (never asked of the service).
pub let page_js_path : String = "/_stillfail/page.js"

///|
/// The header a request whose body the page left here carries: the id it was left under.
pub let body_header : String = "x-stillfail-body"

///|
/// First in page.js as served here: StillFailPreviewNative made of the page's way to the app (`mbuiHost.post`), each
/// call a message in the order made; none answers but fetchPort (a channel of the page's own: what the page says on it
/// goes to the app, what the app says back comes by `__mbuiPort`) and fetchBytes (false: bytes go as base64). The top
/// page says first that it is a new page (`p: "page"`): what the page before had open goes with it.
// kept across runs: a script's words, never written
pub let page_bridge_js : String =
  #|(() => {
  #|  if (window.StillFailPreviewNative || !window.mbuiHost) return;
  #|  const say = (m) => window.mbuiHost.post(JSON.stringify(m));
  #|  const top = window === window.top;
  #|  if (top) say({ p: "page" });
  #|  let port = null;
  #|  window.__mbuiPort = (data) => { if (port) port.postMessage(data); };
  #|  window.StillFailPreviewNative = {
  #|    open: (sid, path, protocols, ported) => say({ p: "open", sid, path, protocols }),
  #|    send: (sid, text) => say({ p: "send", sid, text }),
  #|    sendBinary: (sid, b64) => say({ p: "sendBinary", sid, b64 }),
  #|    close: (sid, code, reason) => say({ p: "close", sid, code, reason }),
  #|    stash: (id, b64, type) => say({ p: "stash", id, b64, type }),
  #|    marked: (json) => say({ p: "marked", json }),
  #|    fetchBytes: () => false,
  #|    fetchPort: (token) => {
  #|      if (!top || port || !window.__mbuiFetch) return false;
  #|      const ch = new MessageChannel();
  #|      port = ch.port1;
  #|      port.onmessage = ({ data }) => {
  #|        if (typeof data !== "string") return;
  #|        let m;
  #|        try { m = JSON.parse(data); } catch { return; }
  #|        say({ p: "port", m });
  #|      };
  #|      // as the app's own message: no window sent it
  #|      queueMicrotask(() => dispatchEvent(new MessageEvent("message", { data: token, ports: [ch.port2] })));
  #|      return true;
  #|    },
  #|  };
  #|})();

///|
/// page.js as served: the language said first (PreviewWeb.kt pageScript), behind the app's StillFailPreviewNative;
/// `fetches` whether the top page's fetch() comes here on its port (not where the host keeps the cookies: the app has
/// none of them to send along).
pub fn page_script_served(fetches : Bool) -> String {
  "self.__stillfailLang = \"zh\";\n" +
  (if fetches { "window.__mbuiFetch = true;\n" } else { "" }) +
  page_bridge_js +
  "\n" +
  page_js
}

///|
/// What a service's page has open through the app: its WebSockets (the core's call for each, by the page's name for
/// it), the bodies its requests left here (by the id they carry), its fetches under way (how each is stopped, by id).
pub(all) struct PageLink {
  sockets : @sf.LiveMap[String, Int]
  bodies : Map[String, (Bytes, String)]
  fetches : Map[String, () -> Unit]
}

///|
pub fn page_link_new() -> PageLink {
  { sockets: @sf.LiveMap::from({}), bodies: {}, fetches: {} }
}

///|
/// A new page, or none: what the one before had open goes with it (PreviewLink.pageStarted).
pub fn page_link_drop(src : Source, l : PageLink) -> Unit {
  for _, id in l.sockets {
    (src.cancel)(id)
  }
  l.sockets.clear()
  l.bodies.clear()
  let stops = []
  for _, f in l.fetches {
    stops.push(f)
  }
  l.fetches.clear()
  for f in stops {
    f()
  }
}

///|
/// A name the page gave a socket, a body or a fetch: 1 to 64 printable ASCII characters (else let go).
pub fn link_name(s : String) -> Bool {
  if s.length() == 0 || s.length() > 64 {
    return false
  }
  for ch in s {
    let u = ch.to_int()
    if u < 0x21 || u > 0x7e {
      return false
    }
  }
  true
}

///|
/// What the page says to the app (its StillFailPreviewNative's calls, page_bridge_js), taken apart; anything else let go.
pub fn link_said(src : Source, p : ServicePage, site : @ui.NativeView, words : String) -> Unit {
  let m = match (try Some(@json.parse(words)) catch { _ => None }) {
    Some(Object(m)) => Some(Json::object(m))
    _ => return
  }
  let l = p.link
  match text(m, "p") {
    "page" => {
      page_link_drop(src, l)
      page_marks_new_page(p, site)
    }
    "open" => {
      let sid = text(m, "sid")
      let path = text(m, "path")
      if link_name(sid) && !l.sockets.contains(sid) && link_path(path) {
        link_open(src, p, site, sid, path, text(m, "protocols"))
      }
    }
    "send" => {
      let sid = text(m, "sid")
      if l.sockets.contains(sid) {
        match field(m, "text") {
          Some(String(words)) => link_send(src, l, sid, { "socket": Json::string(sid), "text": Json::string(words) }, None)
          _ => ()
        }
      }
    }
    "sendBinary" => {
      let sid = text(m, "sid")
      if l.sockets.contains(sid) {
        match @codec.from_base64_exact(text(m, "b64")) {
          Some(b) => link_send(src, l, sid, { "socket": Json::string(sid), "binary": Json::boolean(true) }, Some(b))
          None => ()
        }
      }
    }
    "close" => {
      let sid = text(m, "sid")
      if l.sockets.contains(sid) {
        let code = match field(m, "code") {
          Some(Number(n, ..)) => n.to_int()
          _ => 1000
        }
        link_send(
          src,
          l,
          sid,
          { "socket": Json::string(sid), "close": Json::array([Json::number(code.to_double()), Json::string(text(m, "reason"))]) },
          None,
        )
      }
    }
    "stash" => {
      let id = text(m, "id")
      match @codec.from_base64_exact(text(m, "b64")) {
        Some(b) if link_name(id) => l.bodies[id] = (b, text(m, "type"))
        _ => ()
      }
    }
    "marked" =>
      match (try Some(@json.parse(text(m, "json"))) catch { _ => None }) {
        Some(Object(o)) => service_marked(p, Json::object(o))
        _ => ()
      }
    "shot" =>
      match m {
        Some(said) => shot_said(p, site, said)
        None => ()
      }
    "port" =>
      match field(m, "m") {
        Some(Object(o)) => link_port(src, p, site, Json::object(o))
        _ => ()
      }
    _ => ()
  }
}

///|
/// A path on the service as the page may ask it: from its root, no spaces or controls, 16 KB at most.
pub fn link_path(path : String) -> Bool {
  if !path.has_prefix("/") || path.length() > 16384 {
    return false
  }
  for ch in path {
    let u = ch.to_int()
    if u <= 0x20 || u == 0x7f {
      return false
    }
  }
  true
}

///|
/// A script for the page: `f`'s call with `args` (JSON, each a value of JS), if the page has it.
pub fn link_js(f : String, args : Array[Json]) -> String {
  "window." + f + "&&" + f + "(" + args.map(fn(a) { a.stringify() }).join(",") + ")"
}

///|
/// One of the page's WebSockets opened through the core (PreviewLink.open, not `ported`: what it hears goes into the
/// page as script, a binary frame as base64).
pub fn link_open(src : Source, p : ServicePage, site : @ui.NativeView, sid : String, path : String, protocols : String) -> Unit {
  let l = p.link
  let event = fn(kind : String, args : Array[Json]) {
    site.script(link_js("__stillfailSocketEvent", [Json::string(sid), Json::string(kind)] + args))
  }
  let headers = if protocols != "" {
    [Json::array([Json::string("sec-websocket-protocol"), Json::string(protocols)])]
  } else {
    []
  }
  let id : Ref[Int] = { val: 0 }
  id.val = (src.stream)(
    "preview.socket",
    {
      "station": Json::string(p.station),
      "port": Json::number(p.port.get().to_double()),
      "path": Json::string(path),
      "socket": Json::string(sid),
      "headers": Json::array(headers),
    },
    None,
    fn(v, bytes) {
      if l.sockets.get(sid) != Some(id.val) {
        return
      }
      match (field(Some(v), "open"), field(Some(v), "text"), bytes) {
        (Some(Object(o)), _, _) => event("open", [Json::string(text(Some(Json::object(o)), "protocol"))])
        (_, Some(String(words)), _) => event("text", [Json::string(words)])
        (_, _, Some(b)) if field(Some(v), "binary") is Some(_) => event("binary", [Json::string(@codec.base64(b))])
        _ => ()
      }
    },
    fn(r) {
      if l.sockets.get(sid) != Some(id.val) {
        return
      }
      l.sockets.remove(sid)
      let (code, reason) = match r {
        Ok(closed) =>
          match field(Some(closed), "code") {
            Some(Number(n, ..)) => (n.to_int(), text(Some(closed), "reason"))
            _ => (1006, "")
          }
        Err(_) => (1006, "")
      }
      event("close", [Json::number(code.to_double()), Json::string(reason), Json::boolean(code == 1006)])
    },
  )
  l.sockets[sid] = id.val
}

///|
/// What the page sends on a socket, in the order sent (a binary frame's bytes beside it); a close that does not get
/// there stops the socket's call, so nothing is left open for a page that let it go.
pub fn link_send(src : Source, l : PageLink, sid : String, message : Map[String, Json], bytes : Bytes?) -> Unit {
  let closing = message.contains("close")
  let done = fn(r : Result[Json, Json]) {
    match r {
      Err(_) if closing =>
        match l.sockets.get(sid) {
          Some(id) => {
            (src.cancel)(id)
            l.sockets.remove(sid)
          }
          None => ()
        }
      _ => ()
    }
  }
  match bytes {
    Some(b) => (src.call_bytes)("preview.socket.send", Json::object(message), b, done)
    None => (src.call)("preview.socket.send", Json::object(message), done)
  }
}

///|
/// What the page says on its port (PreviewWeb.kt fetchSaid): `go` (a fetch), `stop` (one it gave up); anything else let
/// go. Each fetch asks the service at the page's port only, as the page's other requests do; its answer goes back on
/// the port as it comes: its head, each piece of its body (base64), its end or why it broke off.
pub fn link_port(src : Source, p : ServicePage, site : @ui.NativeView, m : Json) -> Unit {
  let l = p.link
  let id = text(Some(m), "id")
  if !link_name(id) {
    return
  }
  let tell = fn(reply : Map[String, Json]) {
    reply["id"] = Json::string(id)
    site.script(link_js("__mbuiPort", [Json::string(Json::object(reply).stringify())]))
  }
  match text(Some(m), "t") {
    "stop" =>
      match l.fetches.get(id) {
        Some(stop) => {
          l.fetches.remove(id)
          stop()
        }
        None => ()
      }
    "go" => {
      let failed = fn(words : String) { tell({ "t": Json::string("error"), "message": Json::string(words) }) }
      let method = text(Some(m), "method").to_upper()
      let path = text(Some(m), "path")
      let headers = link_headers(field(Some(m), "headers"))
      let body = match field(Some(m), "body") {
        Some(String("")) | None => Some(Bytes::new(0))
        Some(String(s)) => @codec.from_base64_exact(s)
        _ => None
      }
      let body = match body {
        Some(b) => b
        None => {
          failed(svc("android-chat.web.badBody"))
          return
        }
      }
      if !link_method(method) || !link_path(path) || l.fetches.contains(id) {
        failed(svc("android-chat.web.badRequest"))
        return
      }
      let headers = match headers {
        Some(h) => h
        None => {
          failed(svc("android-chat.web.badRequest"))
          return
        }
      }
      let redirect = text(Some(m), "redirect")
      let follow = redirect != "manual" && redirect != "error"
      let cookies = !(field(Some(m), "cookies") is Some(False))
      let ended : Ref[Bool] = { val: false }
      l.fetches[id] = fn() {  }
      let sink : Sink = {
        head: fn(status, hs, at, redirected) {
          tell({
            "t": Json::string("head"),
            "status": Json::number(status.to_double()),
            "statusText": Json::string(status_reason(status)),
            "path": Json::string(at),
            "redirected": Json::boolean(redirected),
            "headers": Json::array(hs.map(fn(h) { Json::array([Json::string(h.0), Json::string(h.1)]) })),
          })
        },
        chunk: fn(b) { tell({ "t": Json::string("chunk"), "b": Json::string(@codec.base64(b)) }) },
        end: fn(error) {
          if ended.val {
            return
          }
          ended.val = true
          l.fetches.remove(id)
          if error == "" {
            tell({ "t": Json::string("end") })
          } else {
            failed(error)
          }
        },
        gone: fn(stop) {
          if !ended.val {
            l.fetches[id] = fn() {
              ended.val = true
              stop()
            }
          }
        },
      }
      service_ask(src, p, method, path, headers, body, 0, [], sink, follow~, cookies~)
    }
    _ => ()
  }
}

///|
/// A method as a fetch may say it: 1 to 16 capitals.
pub fn link_method(m : String) -> Bool {
  if m.length() == 0 || m.length() > 16 {
    return false
  }
  for ch in m {
    if ch < 'A' || ch > 'Z' {
      return false
    }
  }
  true
}

///|
/// A fetch's headers as the page says them (200 at most), each a token's name and a value on one line; the host's and
/// the body's id left out. None: not headers.
pub fn link_headers(v : Json?) -> Array[(String, String)]? {
  let all = match v {
    Some(Array(a)) => a
    None => []
    _ => return None
  }
  let out = []
  for i, h in all {
    if i >= 200 {
      break
    }
    match h {
      Array([String(k), String(x)]) =>
        if link_token(k) &&
          !x.contains("\r") &&
          !x.contains("\n") &&
          k.to_lower() != "host" &&
          k.to_lower() != body_header {
          out.push((k, x))
        }
      _ => return None
    }
  }
  Some(out)
}

///|
/// A header's name: 1 to 256 of a token's characters.
pub fn link_token(k : String) -> Bool {
  if k.length() == 0 || k.length() > 256 {
    return false
  }
  for ch in k {
    let ok = (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      "!#$%&'*+.^_`|~-".contains(ch.to_string())
    if !ok {
      return false
    }
  }
  true
}

///|
/// The reason said with a status (PreviewLink.reason).
pub fn status_reason(status : Int) -> String {
  if status >= 200 && status <= 299 {
    "OK"
  } else if status == 404 {
    "Not Found"
  } else if status >= 500 && status <= 599 {
    "Error"
  } else {
    "Status"
  }
}

// ── a page's HTML with page.js's tag in it ─

///|
/// The tag put in each of the service's HTML pages (PreviewWeb.kt WithTag.TAG).
pub let page_js_tag : String = "<script src=\"/_stillfail/page.js\"></script>"

///|
/// A page's body on its way with page.js's tag in it (PreviewWeb.kt WithTag, as the web's service worker puts it):
/// after the <head> tag, else after <html>, else after the doctype, else first; its first bytes wait until <head> or
/// <html> is there (or 4 KB, or its end), so it never goes before a doctype cut in two.
pub(all) struct Tagging {
  // (plain: a page's body on its way to its view, nothing shown)
  start : @buffer.Buffer
  mut placed : Bool
}

///|
pub fn tagging_new() -> Tagging {
  { start: @buffer.new(size_hint=4096), placed: false }
}

///|
/// The next piece of the body: what of it may go now (the start once the tag's place is known, with the tag in it).
pub fn tagging_take(t : Tagging, b : Bytes, last : Bool) -> Bytes {
  if t.placed {
    return b
  }
  t.start.write_bytes(b)
  let so_far = t.start.to_bytes()
  let whole = last || so_far.length() >= 4096
  let at = match tag_place(so_far, whole) {
    Some(i) => i
    None if whole => 0
    None => return Bytes::new(0)
  }
  t.placed = true
  let out = @buffer.new(size_hint=so_far.length() + 64)
  out.write_bytes(so_far[0:at].to_bytes())
  out.write_bytes(@utf8.encode(page_js_tag))
  out.write_bytes(so_far[at:].to_bytes())
  out.to_bytes()
}

///|
/// Where the tag goes in a page's first bytes (their first 4 KB, as Latin-1, any case): just after the <head> tag, else
/// <html>; `last` (nothing more to wait for) else just after the doctype.
pub fn tag_place(b : Bytes, last : Bool) -> Int? {
  let n = if b.length() < 4096 { b.length() } else { 4096 }
  let lower = Array::makei(n, fn(i) {
    let x = b[i].to_int()
    if x >= 65 && x <= 90 {
      x + 32
    } else {
      x
    }
  })
  let names = if last { ["<head", "<html", "<!doctype"] } else { ["<head", "<html"] }
  for name in names {
    match tag_end(lower, name) {
      Some(i) => return Some(i)
      None => ()
    }
  }
  None
}

///|
/// Just after the first `name` tag (its name followed by a space or `>`): after the `>` that ends it.
pub fn tag_end(lower : Array[Int], name : String) -> Int? {
  let want = name.to_array().map(fn(ch) { ch.to_int() })
  let k = want.length()
  let mut i = 0
  while i + k < lower.length() {
    let mut same = true
    for j in 0..<k {
      if lower[i + j] != want[j] {
        same = false
        break
      }
    }
    let after = lower[i + k]
    if same && (after == 0x3e || after == 0x20 || after == 0x09 || after == 0x0a || after == 0x0d || after == 0x0c) {
      let mut e = i + k
      while e < lower.length() {
        if lower[e] == 0x3e {
          return Some(e + 1)
        }
        e += 1
      }
      return None
    }
    i += 1
  }
  None
}

// ── base64 ─

