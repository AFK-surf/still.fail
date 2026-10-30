// A service's page and what serves it, as both frames show one (ember apps/android chat/screens/Preview.kt, PreviewWeb.kt;
// web Preview.tsx, PreviewStage.tsx): found by its job, known by its name, never its port. Its page is a site view
// (src/ui/native.mbt `NativeView::site`) whose every request is answered here from the station through the core
// (`station.preview` with `stream`), redirects followed here (to the service only, 5 at most) and its cookies kept here
// and sent along; page.js goes first in each of its pages (service_link.mbt). What a page keeps while it is shown: its
// size and its place on its stage, its marks (service_marks.mbt). The phone's page draws it in sfapp's service.mbt, the
// desktop's in sfdesk's side panel.


///|
pub fn svc(key : String, args? : Array[(String, String)] = []) -> String {
  fill(key, args)
}

///|
/// A size the page is laid out at (null height: as high as the preview leaves it at its scale).
pub(all) struct Viewport {
  width : Int
  height : Int?
} derive(Eq)

///|
/// The sizes offered (Preview.kt PRESETS).
// kept across runs: a table, never written
pub let svc_presets : Array[(String, Int, Int)] = [
  ("phone", 390, 844),
  ("tablet", 820, 1180),
  ("laptop", 1280, 800),
  ("desktop", 1440, 900),
]

///|
/// A service's page as it stands while it is in the stack.
pub(all) struct ServicePage {
  station : String
  job : String
  site : @signals.Signal[@ui.NativeView?]
  port : @signals.Signal[Int]
  /// the service's cookies, by name (kept here: sent along with each request)
  cookies : Map[String, String]
  viewport : @signals.Signal[Viewport?]
  restarting : @signals.Signal[Bool]
  /// requests under way: the core's call for each
  calls : @sf.LiveMap[Int, Int]
  asked : @signals.Signal[Int]
  /// the path the address field was last given, and the one last said on the log
  shown_path : @signals.Signal[String]
  logged_path : @signals.Signal[String]
  /// the address field's words (the field shows them)
  address : @ui.Field
  /// what its page has open through the app (service_link.mbt)
  link : PageLink
  /// a sized page on its canvas (mbui's Zoom, free: dragged anywhere, 0.05 to 4 times, fitted 16 in by thousandths;
  /// Preview.kt StageState), moved by a finger on it (the toolbar's 移动), where it was drawn last, the stage's fingers,
  /// when the ground was last tapped
  view : @kit.Zoom
  moving : @signals.Signal[Bool]
  placed : @signals.Signal[Placed?]
  hold : @signals.Signal[StageHold?]
  tapped_at : @signals.Signal[Double]
  /// its name and its chat's agent (marks go into that chat's draft: none, nothing to mark for), its marks
  name : @signals.Signal[String]
  session : @signals.Signal[String]
  marks : PageMarks
  /// a size being typed (the sizes sheet's 自定义): put once its field is let go of; its two fields' words
  custom_typing : @signals.Signal[Bool]
  custom_w : @ui.Field
  custom_h : @ui.Field
}

///|
pub let service_pages : Map[String, ServicePage] = Map([])

///|
/// The size chosen for each service while the app runs (None: not chosen since it started): what the core keeps of
/// them on the device (prefs `previewSizes`) is read only before.
pub let svc_viewports : Map[String, Viewport?] = Map([])


///|
/// Puts a patch into the core's prefs (the page's source's `prefs.set`; nothing until a page has been shown).
pub let svc_keep : Ref[(Json) -> Unit] = Ref(fn(_) {  })

///|
/// A size as the core keeps it: its width, or `<width>x<height>`.
pub fn size_kept(v : Viewport?) -> Json {
  match v {
    None => Json::null()
    Some({ width, height: None }) => Json::string(width.to_string())
    Some({ width, height: Some(h) }) => Json::string(width.to_string() + "x" + h.to_string())
  }
}

///|
/// A size the core kept (size_kept's), within the sizes a page can take; None for none, or one that does not read.
pub fn size_of_kept(s : String) -> Viewport? {
  let parts = s.split("x").map(fn(x) { x.to_string() }).to_array()
  let num = fn(x : String) -> Int? {
    if x.length() > 4 {
      None
    } else {
      size_of(x).map(clamp_size)
    }
  }
  match parts {
    [w] => num(w).map(fn(w) { { width: w, height: None } })
    [w, h] =>
      match (num(w), num(h)) {
        (Some(w), Some(h)) => Some({ width: w, height: Some(h) })
        _ => None
      }
    _ => None
  }
}

///|
/// A size chosen for a service: shown, and kept on the device.
pub fn keep_size(key : String, v : Viewport?) -> Unit {
  svc_viewports[key] = v
  (svc_keep.val)(Json::object({ "previewSizes": Json::object(Map::from_array([(key, size_kept(v))])) }))
}


///|
pub fn service_key(station : String, job : String) -> String {
  station + "\n" + job
}

///|
pub fn service_page_for(station : String, job : String, prefs? : Json? = None) -> ServicePage {
  let key = service_key(station, job)
  match service_pages.get(key) {
    Some(p) => p
    None => {
      let p : ServicePage = {
        station,
        job,
        site: @signals.signal(None),
        port: @signals.signal(0, same=fn(a, b) { a == b }),
        cookies: {},
        viewport: @signals.signal(
          match svc_viewports.get(key) {
            Some(v) => v
            None =>
              match field(field(prefs, "previewSizes"), key) {
                Some(String(s)) => size_of_kept(s)
                _ => None
              }
          },
          same=fn(a, b) { a == b },
        ),
        restarting: @signals.signal(false, same=fn(a, b) { a == b }),
        calls: @sf.LiveMap::from({}),
        asked: @signals.signal(0, same=fn(a, b) { a == b }),
        shown_path: @signals.signal("", same=fn(a, b) { a == b }),
        logged_path: @signals.signal("", same=fn(a, b) { a == b }),
        address: @ui.Field::new(),
        link: page_link_new(),
        view: stage_zoom(),
        moving: @signals.signal(false, same=fn(a, b) { a == b }),
        placed: @signals.signal(None),
        hold: @signals.signal(None),
        tapped_at: @signals.signal(-1.0e9, same=fn(a, b) { a == b }),
        name: @signals.signal("", same=fn(a, b) { a == b }),
        session: @signals.signal("", same=fn(a, b) { a == b }),
        marks: page_marks_new(),
        custom_typing: @signals.signal(false, same=fn(a, b) { a == b }),
        custom_w: @ui.Field::new(),
        custom_h: @ui.Field::new(),
      }
      service_pages[key] = p
      p
    }
  }
}

///|
/// Its page gone: its view closed, what it asked of the station stopped.
pub fn service_left(src : Source, station : String, job : String) -> Unit {
  let key = service_key(station, job)
  match service_pages.get(key) {
    Some(p) => {
      match p.site.get() {
        Some(v) => v.close()
        None => ()
      }
      page_link_drop(src, p.link)
      for _, id in p.calls {
        (src.cancel)(id)
      }
      service_pages.remove(key)
      service_files.remove(key)
    }
    None => ()
  }
}

///|
/// Where an answer goes as it comes: a request of the page's own (its site's reply) or a fetch of its top page (on its
/// port): its head (with where it came from in the end and whether it was redirected there), each piece of its body,
/// its end ("" whole, else why it broke off); `gone` given how to stop asking, for when the page lets it go.
pub(all) struct Sink {
  head : (Int, Array[(String, String)], String, Bool) -> Unit
  chunk : (Bytes) -> Unit
  end : (String) -> Unit
  gone : (() -> Unit) -> Unit
}

///|
/// A request of the page answered from the station through the core (PreviewLink.answer and follow): page.js served
/// from here, its body as the page left it here (x-stillfail-body), its cookies sent along, the service's redirects
/// followed (5 at most, to the service only), its Set-Cookie kept; a page of the service's with page.js's tag in it.
pub fn service_serve(src : Source, p : ServicePage, req : @ui.SiteRequest, reply : @ui.SiteReply) -> Unit {
  p.asked.set(p.asked.get() + 1)
  if p.asked.get() <= 3 {
    @ui.log("service: the page asks \{req.verb} \{req.path}")
  }
  let bare = match req.path.find("?") {
    Some(i) => req.path.view(end_offset=i).to_owned()
    None => req.path
  }
  if bare == page_js_path {
    reply.head(200, [("Content-Type", "text/javascript; charset=utf-8"), ("Cache-Control", "no-store")])
    reply.chunk(@utf8.encode(page_script_served(service_fetches(p))))
    reply.end()
    return
  }
  let headers = []
  let mut body = req.body
  let mut typed = ""
  for h in req.headers {
    if h.0.to_lower() == body_header {
      match p.link.bodies.get(h.1) {
        Some((b, t)) => {
          p.link.bodies.remove(h.1)
          body = b
          typed = t
        }
        None => ()
      }
    } else {
      headers.push(h)
    }
  }
  if typed != "" && !headers.iter().any(fn(h) { h.0.to_lower() == "content-type" }) {
    headers.push(("Content-Type", typed))
  }
  // a page of the service gets its script first (its sockets, its bodies, its marks)
  let tagging : Ref[Tagging?] = { val: None }
  let sink : Sink = {
    head: fn(status, hs, _, _) {
      let kind = match hs.iter().find_first(fn(h) { h.0.to_lower() == "content-type" }) {
        Some(h) => h.1
        None => ""
      }
      let base = match kind.find(";") {
        Some(i) => kind.view(end_offset=i).to_owned()
        None => kind
      }
      let mime = base.trim().to_owned().to_lower()
      let encoded = hs.iter().any(fn(h) { h.0.to_lower() == "content-encoding" && h.1.to_lower() != "identity" })
      if req.page && mime == "text/html" && !encoded {
        tagging.val = Some(tagging_new())
      }
      reply.head(status, match tagging.val {
        Some(_) => hs.filter(fn(h) { h.0.to_lower() != "content-length" })
        None => hs
      })
    },
    chunk: fn(b) {
      match tagging.val {
        Some(t) => reply.chunk(tagging_take(t, b, false))
        None => reply.chunk(b)
      }
    },
    end: fn(error) {
      match tagging.val {
        Some(t) if !t.placed => reply.chunk(tagging_take(t, Bytes::new(0), true))
        _ => ()
      }
      reply.end(error~)
    },
    gone: fn(stop) { reply.when_gone(stop) },
  }
  service_ask(src, p, req.verb, req.path, headers, body, 0, [], sink)
}

///|
/// Whether the page's top fetch() comes to the app on its port: where the app keeps the page's cookies (a host that
/// keeps them itself has them where the app cannot send them along).
pub fn service_fetches(p : ServicePage) -> Bool {
  match p.site.get() {
    Some(v) => !v.keeps_cookies()
    None => false
  }
}

///|
/// Asks the station for `path`, following the service's redirects as a browser does (`follow`; else a redirect is the
/// answer), with the page's cookies (`cookies`: the app's own, or those the host sent, with those set on the way);
/// what the service sets kept (unless the host keeps them, which takes them from the answer: those of every hop go
/// with it).
pub fn service_ask(
  src : Source,
  p : ServicePage,
  verb : String,
  path : String,
  headers : Array[(String, String)],
  body : Bytes,
  hop : Int,
  kept : Array[(String, String)],
  sink : Sink,
  follow? : Bool = true,
  cookies? : Bool = true,
) -> Unit {
  let host_keeps = match p.site.get() {
    Some(v) => v.keeps_cookies()
    None => false
  }
  let given = headers.iter().any(fn(h) { h.0.to_lower() == "cookie" })
  let sent = if host_keeps && cookies && kept.length() > 0 {
    // those set on the way here go along with the next hop, as the host's jar would send them
    let jar = cookie_jar(
      match headers.iter().find_first(fn(h) { h.0.to_lower() == "cookie" }) {
        Some(h) => h.1
        None => ""
      },
      kept,
    )
    headers.filter(fn(h) { h.0.to_lower() != "cookie" }) + [("Cookie", jar)]
  } else {
    headers.copy()
  }
  if cookies && !host_keeps && !given && p.cookies.length() > 0 {
    let jar = []
    for k, v in p.cookies {
      jar.push(k + "=" + v)
    }
    sent.push(("Cookie", jar.join("; ")))
  }
  let params : Map[String, Json] = {
    "station": Json::string(p.station),
    "port": Json::number(p.port.get().to_double()),
    "method": Json::string(verb),
    "path": Json::string(path),
    "headers": Json::array(sent.map(fn(h) { Json::array([Json::string(h.0), Json::string(h.1)]) })),
    "stream": Json::boolean(true),
  }
  let headed : Ref[Bool] = { val: false }
  let followed : Ref[Bool] = { val: false }
  let id : Ref[Int] = { val: 0 }
  id.val = (src.stream)(
    "station.preview",
    Json::object(params),
    if body.length() > 0 { Some(body) } else { None },
    fn(v, bytes) {
      if followed.val {
        return
      }
      match field(Some(v), "head") {
        Some(head) => {
          headed.val = true
          let status = number(Some(head), "status").to_int()
          let hs : Array[(String, String)] = []
          for h in items(Some(head), "headers") {
            match h {
              Array([String(k), String(x)]) => hs.push((k, x))
              _ => ()
            }
          }
          // the service's cookies kept (each Set-Cookie's name=value), and handed on with the answer
          if cookies && !host_keeps {
            for h in hs {
              if h.0.to_lower() == "set-cookie" {
                service_keep_cookie(p, h.1)
              }
            }
          }
          let location = match hs.iter().find_first(fn(h) { h.0.to_lower() == "location" }) {
            Some(h) => Some(h.1.trim().to_owned())
            None => None
          }
          match location {
            Some(loc) if status >= 300 && status <= 399 && follow => {
              followed.val = true
              (src.cancel)(id.val)
              p.calls.remove(id.val)
              if hop >= 5 {
                service_unanswered(sink, path, 508, svc("android-chat.web.redirects"))
                return
              }
              match service_redirect(path, loc) {
                Ok(next) => {
                  let get = status == 303 || ((status == 301 || status == 302) && verb == "POST")
                  service_ask(
                    src,
                    p,
                    if get { "GET" } else { verb },
                    next,
                    if get {
                      headers.filter(fn(h) {
                        h.0.to_lower() != "content-type" && h.0.to_lower() != "content-length"
                      })
                    } else {
                      headers
                    },
                    if get { Bytes::new(0) } else { body },
                    hop + 1,
                    kept + hs.filter(fn(h) { h.0.to_lower() == "set-cookie" }),
                    sink,
                    follow~,
                    cookies~,
                  )
                }
                Err(words) => service_unanswered(sink, path, 502, words)
              }
            }
            Some(_) if status >= 300 && status <= 399 => {
              // not followed (a fetch's redirect: "manual", "error"): the redirect is the answer, its body let go
              followed.val = true
              (src.cancel)(id.val)
              p.calls.remove(id.val)
              (sink.head)(status, hs + kept, path, hop > 0)
              (sink.end)("")
            }
            _ => (sink.head)(status, hs + kept, path, hop > 0)
          }
        }
        None =>
          match bytes {
            Some(b) if flag(Some(v), "chunk") => (sink.chunk)(b)
            _ => ()
          }
      }
    },
    fn(r) {
      p.calls.remove(id.val)
      if followed.val {
        return
      }
      match r {
        Ok(_) =>
          if headed.val {
            (sink.end)("")
          } else {
            service_unanswered(sink, path, 502, svc("android-chat.web.unreachable", args=[("error", svc("android-chat.web.noAnswer"))]))
          }
        Err(e) => {
          let words = svc("android-chat.web.unreachable", args=[("error", text(Some(e), "message"))])
          if headed.val {
            (sink.end)(words)
          } else {
            service_unanswered(sink, path, 502, words)
          }
        }
      }
    },
  )
  if id.val > 0 {
    p.calls[id.val] = id.val
  }
  (sink.gone)(fn() {
    if !followed.val {
      (src.cancel)(id.val)
      p.calls.remove(id.val)
    }
  })
}

///|
/// A request that got no answer from the service: said to the page with `status`, in words (PreviewLink.text).
pub fn service_unanswered(sink : Sink, path : String, status : Int, words : String) -> Unit {
  (sink.head)(status, [("Content-Type", "text/plain; charset=utf-8")], path, false)
  (sink.chunk)(@utf8.encode(words))
  (sink.end)("")
}

///|
/// A request's Cookie with those set on its way here (each Set-Cookie's name=value, in place of one of that name; an
/// emptied or expired one left out).
pub fn cookie_jar(header : String, set : Array[(String, String)]) -> String {
  let names : Array[String] = []
  let values : Map[String, String] = {}
  for one in header.split(";") {
    let one = one.trim().to_owned()
    match one.find("=") {
      Some(i) if i > 0 => {
        let k = one.view(end_offset=i).to_owned()
        if !values.contains(k) {
          names.push(k)
        }
        values[k] = one.view(start_offset=i + 1).to_owned()
      }
      _ => ()
    }
  }
  for h in set {
    for one in split_cookies(h.1) {
      let first = match one.find(";") {
        Some(i) => one.view(end_offset=i).to_owned()
        None => one
      }
      match first.find("=") {
        Some(i) if i > 0 => {
          let k = first.view(end_offset=i).to_owned().trim().to_owned()
          let v = first.view(start_offset=i + 1).to_owned().trim().to_owned()
          let lower = one.to_lower()
          if v == "" || lower.contains("max-age=0") || lower.contains("expires=thu, 01 jan 1970") {
            values.remove(k)
          } else {
            if !values.contains(k) {
              names.push(k)
            }
            values[k] = v
          }
        }
        _ => ()
      }
    }
  }
  names.filter(fn(k) { values.contains(k) }).map(fn(k) { k + "=" + values.get(k).unwrap_or("") }).join("; ")
}

///|
/// A Set-Cookie's name and value kept (its attributes left: the page's host is the service's alone); several joined
/// in one header split where a name= follows a comma.
pub fn service_keep_cookie(p : ServicePage, header : String) -> Unit {
  for one in split_cookies(header) {
    let first = match one.find(";") {
      Some(i) => one.view(end_offset=i).to_owned()
      None => one
    }
    match first.find("=") {
      Some(i) if i > 0 => {
        let k = first.view(end_offset=i).to_owned().trim().to_owned()
        let v = first.view(start_offset=i + 1).to_owned().trim().to_owned()
        let lower = one.to_lower()
        // one that has expired is let go
        if v == "" || lower.contains("max-age=0") || lower.contains("expires=thu, 01 jan 1970") {
          p.cookies.remove(k)
        } else {
          p.cookies[k] = v
        }
      }
      _ => ()
    }
  }
}

///|
/// Several cookies come joined in one header (", " before the next name=; an Expires date's comma is not followed by
/// one): each apart.
pub fn split_cookies(header : String) -> Array[String] {
  let out : Array[String] = []
  let chars = header.to_array()
  let mut from = 0
  for i, ch in chars {
    if ch == ',' {
      // a name= after it (name chars, then =, before any ; or space)
      let mut k = i + 1
      while k < chars.length() && chars[k] == ' ' {
        k += 1
      }
      let start = k
      while k < chars.length() &&
        chars[k] != '=' &&
        chars[k] != ';' &&
        chars[k] != ' ' &&
        chars[k] != ',' {
        k += 1
      }
      if k < chars.length() && chars[k] == '=' && k > start {
        out.push(String::from_array(chars[from:i]).trim().to_owned())
        from = i + 1
      }
    }
  }
  out.push(String::from_array(chars[from:]).trim().to_owned())
  out.filter(fn(s) { s != "" })
}

///|
/// Where a redirect goes, as a path of the service (PreviewWeb.kt follow: java.net.URI's resolve): relative to `path`
/// (its dot segments taken out), or an address of the service itself (localhost, 127.0.0.1); anywhere else refused,
/// as the Android app's.
pub fn service_redirect(path : String, location : String) -> Result[String, String] {
  let loc = location
  let (base_path, _) = split_query(path)
  if loc.has_prefix("http://") || loc.has_prefix("https://") {
    let rest = loc.view(start_offset=if loc.has_prefix("https://") { 8 } else { 7 }).to_owned()
    let (host, tail) = match rest.find("/") {
      Some(i) => (rest.view(end_offset=i).to_owned(), rest.view(start_offset=i).to_owned())
      None =>
        match rest.find("?") {
          Some(i) => (rest.view(end_offset=i).to_owned(), "/" + rest.view(start_offset=i).to_owned())
          None => (rest, "/")
        }
    }
    let bare = match host.find(":") {
      Some(i) => host.view(end_offset=i).to_owned()
      None => host
    }
    if bare != "localhost" && bare != "127.0.0.1" && bare != "preview.stillfail.invalid" && bare != "svc" {
      return Err(svc("android-chat.web.offsite", args=[("location", location)]))
    }
    let (tp, tq) = split_query(no_fragment(tail))
    return Ok(dots_out(tp) + tq)
  }
  if loc.has_prefix("//") {
    return Err(svc("android-chat.web.offsite", args=[("location", location)]))
  }
  let loc = no_fragment(loc)
  if loc.has_prefix("/") {
    let (lp, lq) = split_query(loc)
    return Ok(dots_out(lp) + lq)
  }
  if loc == "" {
    return Ok(path)
  }
  if loc.has_prefix("?") {
    return Ok(base_path + loc)
  }
  // a scheme of its own (mailto:, javascript:…): no path of the service's
  match loc.find(":") {
    Some(i) if !loc.view(end_offset=i).contains("/") && !loc.view(end_offset=i).contains("?") =>
      return Err(svc("android-chat.web.badRedirect", args=[("location", location)]))
    _ => ()
  }
  // relative to the path's folder
  let dir = match base_path.rev_find("/") {
    Some(i) => base_path.view(end_offset=i + 1).to_owned()
    None => "/"
  }
  let (lp, lq) = split_query(loc)
  Ok(dots_out(dir + lp) + lq)
}

///|
/// A path and its query ("?…", or "").
pub fn split_query(path : String) -> (String, String) {
  match path.find("?") {
    Some(i) => (path.view(end_offset=i).to_owned(), path.view(start_offset=i).to_owned())
    None => (path, "")
  }
}

///|
/// A link without its fragment (#…: the page's own, never asked of the service).
pub fn no_fragment(s : String) -> String {
  match s.find("#") {
    Some(i) => s.view(end_offset=i).to_owned()
    None => s
  }
}

///|
/// A path from the root with its `.` and `..` segments taken out (RFC 3986 remove_dot_segments, as URI.resolve does).
pub fn dots_out(path : String) -> String {
  let out : Array[String] = []
  let parts = path.split("/").map(fn(v) { v.to_string() }).to_array()
  for i, seg in parts {
    let last = i == parts.length() - 1
    if i == 0 {
      continue
    }
    if seg == "." {
      if last {
        out.push("")
      }
    } else if seg == ".." {
      if out.length() > 0 {
        out.pop() |> ignore
      }
      if last {
        out.push("")
      }
    } else {
      out.push(seg)
    }
  }
  "/" + out.join("/")
}

///|
/// Where the page is drawn on the stage, from the stage's top left: its top left, its scale, the size it is laid out
/// at (Preview.kt Placed).
pub(all) struct Placed {
  x : Double
  y : Double
  scale : Double
  w : Double
  h : Double
}

///|
/// A finger (or two) on the stage, from where it went down (Preview.kt Stage's gesture): where they were the frame
/// before (or when one came or went), how far one finger went, when it went down, whether on the page.
pub(all) struct StageHold {
  was : @signals.Signal[Array[(Double, Double)]]
  travelled : @signals.Signal[Double]
  down_at : Double
  on_page : Bool
}

///|
/// How far the page can be zoomed by hand (Preview.kt StageState.zoom, pinch).
pub let stage_min_scale : Double = 0.05

///|
pub let stage_max_scale : Double = 4.0

///|
/// A sized page's place on its canvas (Preview.kt StageState): fitted 16 in, never enlarged, by thousandths; dragged
/// anywhere; zoomed by hand within `stage_min_scale` … `stage_max_scale`.
pub fn stage_zoom() -> @kit.Zoom {
  @kit.Zoom::new(
    margin=fn(_) { 16.0 },
    min_scale=fn(_) { stage_min_scale },
    max_scale=fn(_) { stage_max_scale },
    free=true,
    fit_step=0.001,
  )
}

///|
/// The smallest and largest a size may be (Preview.kt LIMIT_MIN, LIMIT_MAX).
pub let size_min : Int = 240

///|
pub let size_max : Int = 3840

///|
pub fn clamp_size(n : Int) -> Int {
  if n < size_min {
    size_min
  } else if n > size_max {
    size_max
  } else {
    n
  }
}

///|
/// A size typed: its digits' number (None: none there).
pub fn size_of(s : String) -> Int? {
  if s == "" {
    return None
  }
  let mut n = 0
  for ch in s {
    if ch < '0' || ch > '9' {
      return None
    }
    n = n * 10 + (ch.to_int() - '0'.to_int())
  }
  Some(n)
}

///|
/// Digits only, four at most (a size typed).
pub fn size_digits(s : String) -> String {
  let out = StringBuilder::new()
  let mut n = 0
  for ch in s {
    if ch >= '0' && ch <= '9' && n < 4 {
      out.write_char(ch)
      n += 1
    }
  }
  out.to_string()
}

///|
/// A visualization's page for service_body: its file, what its widget keeps now, where it is kept.
pub(all) struct FilePage {
  html : String
  state : @signals.Signal[Json?]
  station : String
  key : String
  path : String
}

///|
/// The visualizations' pages open, by their key as service pages (their station, `file:<session>\n<path>`).
pub let service_files : Map[String, FilePage] = Map([])


///|
/// As at the start (tests): no service's page kept, no size or fold chosen, nothing marked waiting for a composer.
pub fn service_pages_reset() -> Unit {
  service_pages.clear()
  svc_viewports.clear()
  service_files.clear()
  svc_keep.val = fn(_) {  }
  marked_into.clear()
  src_now.val = fn() { 0.0 }
  viz_loads.clear()
}

///|
/// Service page `p`'s site view, made the first time (the build places it, so it is made in it): every request of its
/// page answered from the station through the core (service_serve), or for a visualization's (`file`) from here
/// (file_serve); what its page says taken apart (a visualization's bridge its own, page.js the rest: link_said); a link
/// elsewhere not followed in the page but handed to `leave`.
pub fn service_site(src : Source, p : ServicePage, file : FilePage?, leave : (String) -> Unit) -> @ui.NativeView {
  match p.site.get() {
    Some(v) => v
    None => {
      let v = @ui.NativeView::site(
        "/",
        fn(req, reply) {
          match file {
            Some(f) => file_serve(f, req, reply)
            None => service_serve(src, p, req, reply)
          }
        },
        said=fn(words) {
          match file {
            Some(f) => file_said(src, f, words)
            None => ()
          }
          match p.site.get() {
            Some(v) => link_said(src, p, v, words)
            None => ()
          }
        },
        no_answer=svc("android-chat.web.timeout", args=[("s", (@ui.site_head_wait_ms / 1000.0).to_int().to_string())]),
        too_slow=svc("android-chat.web.slow"),
        leave~,
      )
      @ui.log("service: \{p.name.get()} on \{p.station} (port \{p.port.get()}) opened in a site view")
      p.site.set(Some(v))
      v
    }
  }
}
