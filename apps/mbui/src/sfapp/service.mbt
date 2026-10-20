// A web service an agent started (a dev server, a report it serves), full screen over its chat (ember apps/android
// chat/screens/Preview.kt PreviewScreen, PreviewWeb.kt, PreviewLoad.kt; web mobile/Preview.tsx): found by its job (the
// `job` topic), known by its name, never its port. Its page is a site view (src/ui/native.mbt `NativeView::site`: a
// web view of a host of its own) whose every request is answered here from the station through the core
// (`station.preview` with `stream`: the head, then the body as it comes; stopped at the station when the page lets it
// go), redirects followed here (to the service only, 5 at most) and its cookies kept here and sent along. No port on the
// station is open to anyone.
//
// The bar: back and forward in the page's own history, reload, how far its resources came (the `previewLoad` topic's
// ring; tapped, each of them in a sheet), where it is (its name, then its path; typed, it goes there). The page fills
// what is under the bar, or is laid out at a size of its own (a phone's, a tablet's, a laptop's, a desktop's) on the
// grey of a canvas, fitted and centred, with its screen's corners: the toolbar under it chooses (自适应, the sizes,
// turned), held down it folds away and the bar's size button opens it again. A service being started again is said
// over the page, which loads anew once it is back; one stopped, or not found, is said in its place.
//
// Not yet, against the Android app: marking the page for the chat's agent (the edit key, its marks and their shots:
// page.js is not carried here), WebSockets and the bodies of a page's own requests on Android (a WebView hands over
// neither without page.js; Apple's scheme handler gives the bodies), moving and pinching the sized page on its canvas,
// typing a size of one's own (自定义 lists the sizes), the chosen size kept on the device across runs (kept while the
// app runs), a visualization's page (PreviewFileScreen), a link elsewhere opened in the browser (no URL hand-off on the
// hosts yet: it is copied and said so), document.cookie (the cookies are the app's, not the web view's).

///|
// kept across runs: a table, never written
let svc_zh : Map[String, String] = {
  "android-chat.link.failed": "无法打开此链接",
  "android-chat.load.failed": "失败",
  "android-chat.load.label": "资源加载 {percent}% · {finished}/{total}",
  "android-chat.load.label.failed": "资源加载 {percent}% · {finished}/{total} · {failed} 个失败",
  "android-chat.load.note": "按已发现的服务请求计算 · 新资源出现时更新",
  "android-chat.load.waiting": "等待页面请求",
  "android-chat.preview.auto": "自动",
  "android-chat.preview.back": "对话",
  "android-chat.preview.custom": "自定义",
  "android-chat.preview.fit": "自适应",
  "android-chat.preview.fit.note": "跟随预览区",
  "android-chat.preview.notFound": "找不到此服务：{error}",
  "android-chat.preview.preset.desktop": "桌面",
  "android-chat.preview.preset.laptop": "笔记本",
  "android-chat.preview.preset.phone": "手机",
  "android-chat.preview.preset.tablet": "平板",
  "android-chat.preview.reloads": "恢复后自动刷新",
  "android-chat.preview.restarting": "{name}正在重启",
  "android-chat.preview.restarts": "第 {n} 次 · 恢复后自动刷新",
  "android-chat.preview.service": "服务",
  "android-chat.preview.size.title": "页面尺寸",
  "android-chat.preview.stopped": "「{name}」已停止",
  "android-chat.web.badRedirect": "网页重定向到无法识别的地址：{location}",
  "android-chat.web.offsite": "网页重定向到其他地址：{location}",
  "android-chat.web.redirects": "重定向次数过多",
  "android-chat.web.unreachable": "无法从 station 获取：{error}",
  "common.reading": "正在读取",
  "common.copied": "已复制",
}

///|
fn svc(key : String, args? : Array[(String, String)] = []) -> String {
  let mut s = match svc_zh.get(key) {
    Some(w) => w
    None => tr(key)
  }
  for a in args {
    s = s.replace_all(old="{" + a.0 + "}", new=a.1)
  }
  s
}

///|
/// A size the page is laid out at (null height: as high as the preview leaves it at its scale).
priv struct Viewport {
  width : Int
  height : Int?
}

///|
/// The sizes offered (Preview.kt PRESETS).
// kept across runs: a table, never written
let svc_presets : Array[(String, Int, Int)] = [
  ("phone", 390, 844),
  ("tablet", 820, 1180),
  ("laptop", 1280, 800),
  ("desktop", 1440, 900),
]

///|
/// A service's page as it stands while it is in the stack.
priv struct ServicePage {
  station : String
  job : String
  mut site : @ui.NativeView?
  mut port : Int
  /// the service's cookies, by name (kept here: sent along with each request)
  cookies : Map[String, String]
  mut viewport : Viewport?
  mut folded : Bool
  mut restarting : Bool
  /// requests under way: the core's call for each
  calls : Map[Int, Int]
  mut asked : Int
  /// the path the address field was last given, and the one last said on the log
  mut shown_path : String
  mut logged_path : String
}

///|
let service_pages : Map[String, ServicePage] = Map([])

///|
/// The size chosen for each service, while the app runs (Preview.kt keeps it on the device).
let svc_viewports : Map[String, Viewport?] = Map([])

///|
let svc_folded : Ref[Bool] = Ref(false)

///|
fn service_key(station : String, job : String) -> String {
  station + "\n" + job
}

///|
fn service_page_for(station : String, job : String) -> ServicePage {
  let key = service_key(station, job)
  match service_pages.get(key) {
    Some(p) => p
    None => {
      let p : ServicePage = {
        station,
        job,
        site: None,
        port: 0,
        cookies: {},
        viewport: svc_viewports.get(key).unwrap_or(None),
        folded: svc_folded.val,
        restarting: false,
        calls: {},
        asked: 0,
        shown_path: "",
        logged_path: "",
      }
      service_pages[key] = p
      p
    }
  }
}

///|
/// Its page gone: its view closed, what it asked of the station stopped.
fn service_left(src : Source, station : String, job : String) -> Unit {
  let key = service_key(station, job)
  match service_pages.get(key) {
    Some(p) => {
      match p.site {
        Some(v) => v.close()
        None => ()
      }
      for _, id in p.calls {
        (src.cancel)(id)
      }
      service_pages.remove(key)
    }
    None => ()
  }
}

///|
/// A station's name as the workspace's stations say it.
fn station_name(src : Source, station : String) -> String {
  let scope = match station.find("/") {
    Some(i) => station.view(end_offset=i).to_owned()
    None => station
  }
  match stations_of((src.topic)("stations", { "scope": Json::string(scope) }).value).iter().find_first(fn(s) {
    s.address == station
  }) {
    Some(s) => s.name
    None => ""
  }
}

///|
/// The service `job` of `station`'s page (Preview.kt PreviewScreen).
pub fn service_page(c : @ui.Ctx, src : Source, station : String, job : String) -> Unit {
  let t = @sf.theme()
  let found = (src.topic)("job", { "station": Json::string(station), "id": Json::string(job) })
  let j = found.value
  let name = match text(j, "name") {
    "" => svc("android-chat.preview.service")
    n => n
  }
  let port = number(j, "port").to_int()
  let up = j is Some(Object(_)) && port > 0 && flag(j, "open")
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, fn() {
    service_bar(c, name, station_name(src, station))
    match (j, found.error) {
      (None, Some(e)) | (Some(Null), Some(e)) =>
        service_note(c, svc("android-chat.preview.notFound", args=[("error", text(Some(e), "message"))]))
      (None, _) | (Some(Null), _) =>
        c.box(w=Fill(1.0), padx=20.0, pady=8.0, align=ACenter, fn() {
          @sf.wait_line(c, svc("common.reading"), key="service")
        })
        |> ignore
      _ =>
        if !up {
          service_note(c, svc("android-chat.preview.stopped", args=[("name", name)]))
        } else {
          service_body(c, src, station, job, port, name, text(j, "state") == "exited", number(j, "restarts").to_int())
        }
    }
  })
  |> ignore
}

///|
/// What is said where the page would be (PreviewNote): 13, muted, centred.
fn service_note(c : @ui.Ctx, words : String) -> Unit {
  c.box(w=Fill(1.0), padx=20.0, pady=8.0, align=ACenter, fn() {
    c.text(words, size=13.0, color=@sf.theme().p.muted, center=true, w=Fill(1.0)) |> ignore
  })
  |> ignore
}

///|
/// The page's compact bar (Parts.kt NavBar): 对话 back in the accent, the service's name and under it its station.
fn service_bar(c : @ui.Ctx, title : String, station : String) -> Unit {
  let t = @sf.theme()
  let went = if station != "" {
    @sf.nav_bar(c, "service/back", svc("android-chat.preview.back"), title, sub=fn() {
      c.text(station, size=11.0, color=t.p.muted, wrap=false) |> ignore
    })
  } else {
    @sf.nav_bar(c, "service/back", svc("android-chat.preview.back"), title)
  }
  if went {
    app.nav.pop() |> ignore
  }
}

///|
/// The service's page under its bar (Preview.kt ServicePage): the bar of the page, the stage, the toolbar.
fn service_body(
  c : @ui.Ctx,
  src : Source,
  station : String,
  job : String,
  port : Int,
  name : String,
  restarting : Bool,
  restarts : Int,
) -> Unit {
  let p = service_page_for(station, job)
  p.port = port
  let site = match p.site {
    Some(v) => v
    None => {
      // (made once a page; the build places it, so it is made in it)
      let v = @ui.NativeView::site(
        "/",
        fn(req, reply) { service_serve(src, p, req, reply) },
        leave=fn(url) {
          // a link elsewhere: not followed in the page, handed to the system's browser (PreviewWeb.kt); copied and
          // said so when nothing takes it
          if !@ui.open_url(url) {
            c.copy_text(url)
            app.toast = svc("android-chat.link.failed") + " · " + svc("common.copied")
            app.toast_n += 1
          }
        },
      )
      @ui.log("service: \{name} on \{station} (port \{port}) opened in a site view")
      p.site = Some(v)
      v
    }
  }
  // up again after a restart: the page loads anew
  if p.restarting && !restarting {
    // (once the frame's builds are over: by the job's restart as the core says it)
    c.tell("service-reload", fn() { site.reload() })
  }
  p.restarting = restarting
  service_page_bar(c, src, p, site, name, station, port)
  service_stage(c, p, site, name, restarting, restarts)
  if !p.folded {
    service_toolbar(c, p)
  }
}

///|
/// A request of the page answered from the station through the core (PreviewLink.answer and follow): its cookies
/// sent along, the service's redirects followed (5 at most, to the service only), its Set-Cookie kept.
fn service_serve(src : Source, p : ServicePage, req : @ui.SiteRequest, reply : @ui.SiteReply) -> Unit {
  p.asked += 1
  if p.asked <= 3 {
    @ui.log("service: the page asks \{req.verb} \{req.path}")
  }
  service_ask(src, p, req.verb, req.path, req.headers, req.body, 0, [], reply)
}

///|
fn service_ask(
  src : Source,
  p : ServicePage,
  verb : String,
  path : String,
  headers : Array[(String, String)],
  body : Bytes,
  hop : Int,
  kept : Array[(String, String)],
  reply : @ui.SiteReply,
) -> Unit {
  let given = headers.iter().any(fn(h) { h.0.to_lower() == "cookie" })
  let sent = headers.copy()
  if !given && p.cookies.length() > 0 {
    let jar = []
    for k, v in p.cookies {
      jar.push(k + "=" + v)
    }
    sent.push(("Cookie", jar.join("; ")))
  }
  let params : Map[String, Json] = {
    "station": Json::string(p.station),
    "port": Json::number(p.port.to_double()),
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
          for h in hs {
            if h.0.to_lower() == "set-cookie" {
              service_keep_cookie(p, h.1)
            }
          }
          let location = match hs.iter().find_first(fn(h) { h.0.to_lower() == "location" }) {
            Some(h) => Some(h.1.trim().to_owned())
            None => None
          }
          match location {
            Some(loc) if status >= 300 && status <= 399 => {
              followed.val = true
              (src.cancel)(id.val)
              p.calls.remove(id.val)
              if hop >= 5 {
                service_fail(reply, 508, svc("android-chat.web.redirects"))
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
                    reply,
                  )
                }
                Err(words) => service_fail(reply, 502, words)
              }
            }
            _ => reply.head(status, hs + kept)
          }
        }
        None =>
          match bytes {
            Some(b) if flag(Some(v), "chunk") => reply.chunk(b)
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
        Ok(_) => if headed.val { reply.end() } else { service_fail(reply, 502, "station 未响应") }
        Err(e) => {
          let words = svc("android-chat.web.unreachable", args=[("error", text(Some(e), "message"))])
          if headed.val {
            reply.end(error=words)
          } else {
            service_fail(reply, 502, words)
          }
        }
      }
    },
  )
  if id.val > 0 {
    p.calls[id.val] = id.val
  }
  reply.when_gone(fn() {
    if !followed.val {
      (src.cancel)(id.val)
      p.calls.remove(id.val)
    }
  })
}

///|
/// A request that got no answer from the service: said to the page with `status` (PreviewLink.text).
fn service_fail(reply : @ui.SiteReply, status : Int, words : String) -> Unit {
  reply.head(status, [("Content-Type", "text/plain; charset=utf-8")])
  reply.chunk(utf8_bytes(words))
  reply.end()
}

///|
/// A Set-Cookie's name and value kept (its attributes left: the page's host is the service's alone); several joined
/// in one header split where a name= follows a comma.
fn service_keep_cookie(p : ServicePage, header : String) -> Unit {
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
fn split_cookies(header : String) -> Array[String] {
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
/// Where a redirect goes, as a path of the service: relative to `path`, or an address of the service itself
/// (localhost, 127.0.0.1); anywhere else refused, as the Android app's.
fn service_redirect(path : String, location : String) -> Result[String, String] {
  let loc = location
  if loc.has_prefix("http://") || loc.has_prefix("https://") {
    let rest = loc.view(start_offset=if loc.has_prefix("https://") { 8 } else { 7 }).to_owned()
    let (host, tail) = match rest.find("/") {
      Some(i) => (rest.view(end_offset=i).to_owned(), rest.view(start_offset=i).to_owned())
      None => (rest, "/")
    }
    let bare = match host.find(":") {
      Some(i) => host.view(end_offset=i).to_owned()
      None => host
    }
    if bare != "localhost" && bare != "127.0.0.1" && bare != "preview.stillfail.invalid" && bare != "svc" {
      return Err(svc("android-chat.web.offsite", args=[("location", location)]))
    }
    return Ok(tail)
  }
  if loc.has_prefix("//") {
    return Err(svc("android-chat.web.offsite", args=[("location", location)]))
  }
  if loc.has_prefix("/") {
    return Ok(loc)
  }
  if loc.has_prefix("?") {
    let base = match path.find("?") {
      Some(i) => path.view(end_offset=i).to_owned()
      None => path
    }
    return Ok(base + loc)
  }
  if loc.contains(":") && !loc.contains("/") {
    return Err(svc("android-chat.web.badRedirect", args=[("location", location)]))
  }
  // relative to the path's folder
  let base = match path.find("?") {
    Some(i) => path.view(end_offset=i).to_owned()
    None => path
  }
  let dir = match base.rev_find("/") {
    Some(i) => base.view(end_offset=i + 1).to_owned()
    None => "/"
  }
  Ok(dir + loc)
}

///|
/// Back, forward, reload, how far its resources came, where it is (typed to go elsewhere), its size once folded
/// (Preview.kt PreviewBar).
fn service_page_bar(
  c : @ui.Ctx,
  src : Source,
  p : ServicePage,
  site : @ui.NativeView,
  name : String,
  station : String,
  port : Int,
) -> Unit {
  let t = @sf.theme()
  let (at, can_back, can_forward, _, _) = site.page_at()
  let field_key = "service/address/" + service_key(p.station, p.job)
  let editing = c.editor_focused(field_key)
  // (said on the log as the page moves: e2e/flows check where it went)
  if at != p.logged_path {
    p.logged_path = at
    @ui.log("service: at \{at}")
  }
  // a tap anywhere on the address types there
  let pill = c.id("service/address")
  if c.clicked(pill) && !editing {
    c.focus_editor(field_key)
  }
  c.box(dir=Row, w=Fill(1.0), pl=14.0, pr=10.0, pt=4.0, pb=6.0, gap=2.0, align=ACenter, fn() {
    if bar_icon(c, "service/go-back", "arrow-left", can_back) {
      site.go_back()
    }
    if bar_icon(c, "service/go-forward", "arrow-right", can_forward) {
      site.go_forward()
    }
    if bar_icon(c, "service/reload", "refresh", true) {
      site.reload()
    }
    // how far the page's resources came (PreviewLoad.kt): a ring, red with one failed; tapped, each of them
    let load = (src.topic)("previewLoad", {
      "station": Json::string(station),
      "port": Json::number(port.to_double()),
    }).value
    match load {
      Some(Object(_)) => {
        let ring = c.id("service/load")
        if c.clicked(ring) {
          raise_sheet(LoadOf(station, port))
        }
        let color = if number(load, "failed") > 0.0 { t.p.red } else { t.p.muted }
        c.box(w=Px(28.0), h=Px(28.0), align=ACenter, justify=JCenter, id=ring, fn() {
          @sf.progress_ring(c, 20.0, number(load, "percent") / 100.0, color) |> ignore
        })
        |> ignore
      }
      _ => ()
    }
    c.box(w=Fill(1.0), padx=4.0, fn() {
      c.box(
        dir=Row,
        w=Fill(1.0),
        h=Px(30.0),
        radius=15.0,
        bg=if editing { t.p.card } else { t.p.chip },
        border=if editing { 1.5 } else { 0.0 },
        border_color=@sf.alpha(t.p.accent, 0.5),
        padx=12.0,
        gap=6.0,
        align=ACenter,
        clip=true,
        id=pill,
        fn() {
          @sf.icon(c, "web", size=14.0, color=t.p.muted) |> ignore
          c.text(name, size=13.0, weight=500, color=t.p.text, wrap=false) |> ignore
          // where it went is what the bar says, unless someone is typing there
          if !editing && at != p.shown_path {
            p.shown_path = at
            c.set_editor_text(field_key, at)
          }
          let r = c.editor(
            field_key,
            font_size=16.0,
            max_lines=1,
            plain=true,
            color=if editing { t.p.text } else { t.p.muted },
            caret_color=t.p.accent,
          )
          match r.submitted {
            Some(typed) => {
              let path = typed.trim().to_owned()
              site.load(if path.has_prefix("/") { path } else { "/" + path })
              c.blur()
            }
            None => ()
          }
        },
      )
      |> ignore
    })
    |> ignore
    if p.folded {
      let sid = c.id("service/size")
      if c.clicked(sid) {
        p.folded = false
        svc_folded.val = false
      }
      c.box(
        dir=Row,
        h=Px(28.0),
        radius=14.0,
        bg=if p.viewport is Some(_) { t.p.chip } else { 0L },
        padx=if p.viewport is Some(_) { 9.0 } else { 7.0 },
        gap=5.0,
        align=ACenter,
        id=sid,
        fn() {
          @sf.icon(c, "devices", size=14.0, color=t.p.text) |> ignore
          match p.viewport {
            Some(v) => c.text(dims(v.width, v.height), size=12.0, color=t.p.text, wrap=false) |> ignore
            None => ()
          }
        },
      )
      |> ignore
    }
  })
  |> ignore
}

///|
/// `390 × 844` (自动 for no height).
fn dims(w : Int, h : Int?) -> String {
  "\{w} × " +
  (match h {
    Some(x) => x.to_string()
    None => svc("android-chat.preview.auto")
  })
}

///|
/// A key of the page's bar (Preview.kt BarIcon): 28 round, a 14 icon in the ink, faint when it cannot be pressed.
fn bar_icon(c : @ui.Ctx, key : String, icon : String, enabled : Bool) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.box(
    w=Px(28.0),
    h=Px(28.0),
    radius=14.0,
    align=ACenter,
    justify=JCenter,
    bg=if enabled { @sf.alpha(t.p.text, 0.08 * @motion.pressing(c, id)) } else { 0L },
    id=if enabled { id } else { 0 },
    fn() {
      c.box(opacity=if enabled { 1.0 } else { 0.35 }, fn() {
        @sf.icon(c, icon, size=14.0, color=t.p.text) |> ignore
      })
      |> ignore
    },
  )
  |> ignore
  enabled && c.clicked(id)
}

///|
/// All of the room for the page, or the page at its own size on a canvas (PreviewStage.tsx): fitted (100% at most)
/// and centred, 16 round it, its screen's corners (a phone's 44, a tablet's 24, a desktop's all but square).
fn service_stage(
  c : @ui.Ctx,
  p : ServicePage,
  site : @ui.NativeView,
  name : String,
  restarting : Bool,
  restarts : Int,
) -> Unit {
  let t = @sf.theme()
  let ground = @sf.mix(t.p.chip, 0.55, t.p.card)
  let stage = c.id("service/stage")
  c.box(w=Fill(1.0), h=Fill(1.0), bg=if p.viewport is Some(_) { ground } else { t.p.card }, clip=true, id=stage, fn() {
    // (the stage's size as this frame lays it out: read back, built again once it is)
    match (p.viewport, c.laid_size(stage)) {
      (Some(v), Some((sw, sh))) => {
        let room_w = sw - 32.0
        let room_h = sh - 32.0
        let w = v.width.to_double()
        let fitted = dmax(
          0.05,
          (dmin(1.0, dmin(room_w / w, match v.height { Some(h) => room_h / h.to_double(); None => 1.0 })) * 1000.0).floor() /
          1000.0,
        )
        let h = match v.height {
          Some(x) => x.to_double()
          None => dmax(240.0, (room_h / fitted).floor())
        }
        let x = (16.0 + dmax(0.0, (room_w - w * fitted) / 2.0)).round()
        let y = (16.0 + dmax(0.0, (room_h - h * fitted) / 2.0)).round()
        let corner = if v.width <= 600 { 44.0 } else if v.width < 1024 { 24.0 } else { 5.0 / fitted }
        // (told once the frame's builds are over, as the last laid the stage out)
        c.after_build("scale", fn() { site.set_scale(fitted) })
        c.layer(fn() {
          c.box(pl=x, pt=y, fn() {
            c.box(
            w=Px(w * fitted),
            h=Px(h * fitted),
            radius=corner * fitted,
            clip=true,
            shadow=6.0,
            shadow_y=2.0,
            bg=0xFFFFFFFFL,
            fn() { c.native(site) |> ignore },
          )
            |> ignore
          })
          |> ignore
        })
        |> ignore
      }
      (Some(_), None) => ()
      (None, _) => {
        c.after_build("scale", fn() { site.set_scale(1.0) })
        c.native(site) |> ignore
      }
    }
    if restarting {
      c.layer(align=ACenter, fn() {
        c.spacer()
        c.box(pb=18.0, fn() { service_restart(c, name, restarts) }) |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// Over the page while its service starts again (Preview.kt Restart): its dot breathing, 「名字」正在重启 and what
/// happens next, on the surface, round, with a shadow.
fn service_restart(c : @ui.Ctx, name : String, restarts : Int) -> Unit {
  let t = @sf.theme()
  c.box(
    dir=Row,
    pl=16.0,
    pr=18.0,
    pt=10.0,
    pb=10.0,
    gap=12.0,
    radius=22.0,
    bg=t.p.card,
    shadow=8.0,
    align=ACenter,
    fn() {
      job_dot(c, "restart")
      c.box(fn() {
        c.text(svc("android-chat.preview.restarting", args=[("name", name)]), size=13.0, weight=600, color=t.p.text, wrap=false)
        |> ignore
        c.text(
          if restarts > 0 {
            svc("android-chat.preview.restarts", args=[("n", restarts.to_string())])
          } else {
            svc("android-chat.preview.reloads")
          },
          size=12.0,
          color=t.p.muted,
          wrap=false,
        )
        |> ignore
      })
      |> ignore
    },
  )
  |> ignore
}

///|
/// The toolbar under the page (Preview.kt Dock, Toolbar): a floating capsule of the sizes (the one chosen marked),
/// turning a sized page; held half a second, it folds away.
fn service_toolbar(c : @ui.Ctx, p : ServicePage) -> Unit {
  let t = @sf.theme()
  let sized = p.viewport is Some(_)
  let preset = preset_of(p.viewport)
  let key = service_key(p.station, p.job)
  let set = fn(v : Viewport?) {
    p.viewport = v
    svc_viewports[key] = v
  }
  let bar = c.id("service/toolbar")
  // held still half a second: folded away (the bar's size button opens it again)
  if @kit.after(c, "service/fold-hold", c.pressed(bar) || toolbar_child_pressed(c), svc_fold_hold_ms) {
    p.folded = true
    svc_folded.val = true
  }
  c.box(w=Fill(1.0), bg=if sized { @sf.mix(t.p.chip, 0.55, t.p.card) } else { t.p.card }, pl=10.0, pr=10.0, pb=10.0, fn() {
    c.box(
      dir=Row,
      w=Fill(1.0),
      h=Px(48.0),
      radius=24.0,
      bg=if t.dark { @sf.alpha(0x2C2D31FFL, 0.84) } else { @sf.alpha(t.p.card, 0.72) },
      shadow=4.0,
      padx=6.0,
      gap=4.0,
      align=ACenter,
      clip=true,
      id=bar,
      fn() {
        c.box(dir=Row, w=Fill(1.0), gap=2.0, align=ACenter, clip=true, fn() {
          if size_chip(c, "service/fit", svc("android-chat.preview.fit"), p.viewport is None) {
            set(None)
          }
          for pr in svc_presets {
            let label = svc("android-chat.preview.preset." + pr.0)
            if size_chip(c, "service/" + pr.0, label, preset == Some(pr.0)) && preset != Some(pr.0) {
              set(Some({ width: pr.1, height: Some(pr.2) }))
            }
          }
          let custom = sized && preset is None
          let label = match p.viewport {
            Some(v) if custom => dims(v.width, v.height)
            _ => svc("android-chat.preview.custom")
          }
          if size_chip(c, "service/custom", label, custom) {
            raise_sheet(PageSizes(key))
          }
        })
        |> ignore
        match p.viewport {
          Some(v) =>
            match v.height {
              Some(h) => {
                let id = c.id("service/turn")
                if c.clicked(id) {
                  set(Some({ width: h, height: Some(v.width) }))
                }
                c.box(w=Px(36.0), h=Px(36.0), radius=18.0, align=ACenter, justify=JCenter, id~, fn() {
                  @sf.icon(c, "landscape", size=18.0, color=t.p.text) |> ignore
                })
                |> ignore
              }
              None => ()
            }
          None => ()
        }
      },
    )
    |> ignore
  })
  |> ignore
}

///|
/// (The toolbar's hold is @kit.after's now; app.mbt's reset still puts this back, so it stays until that goes.)
let svc_hold : Ref[Double] = Ref(-1.0)

///|
/// How long the toolbar is held still before it folds away.
let svc_fold_hold_ms : Double = 500.0

///|
/// Whether a finger holds one of the toolbar's chips (a hold anywhere on it folds it).
fn toolbar_child_pressed(c : @ui.Ctx) -> Bool {
  let keys = ["service/fit", "service/phone", "service/tablet", "service/laptop", "service/desktop", "service/custom", "service/turn"]
  keys.iter().any(fn(k) { c.pressed(c.id(k)) })
}

///|
/// A size in the toolbar (Preview.kt Chip): 36 high, round; chosen, on the surface, semibold and the ink.
fn size_chip(c : @ui.Ctx, key : String, label : String, on : Bool) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.box(
    h=Px(36.0),
    radius=18.0,
    padx=13.0,
    align=ACenter,
    justify=JCenter,
    bg=if on { if t.dark { t.p.bg } else { t.p.card } } else { 0L },
    shadow=if on { 1.0 } else { 0.0 },
    id~,
    fn() {
      c.text(label, size=13.0, weight=if on { 600 } else { 400 }, color=if on { t.p.text } else { t.p.muted }, wrap=false)
      |> ignore
    },
  )
  |> ignore
  c.clicked(id)
}

///|
/// The preset a size is (either way round), if it is one.
fn preset_of(v : Viewport?) -> String? {
  match v {
    Some({ width, height: Some(h) }) =>
      match svc_presets.iter().find_first(fn(p) { (p.1 == width && p.2 == h) || (p.1 == h && p.2 == width) }) {
        Some(p) => Some(p.0)
        None => None
      }
    _ => None
  }
}

///|
/// All the sizes in a sheet (the toolbar's 自定义, Preview.kt openViewportSheet): as big as the preview, the presets.
fn page_sizes_sheet(c : @ui.Ctx, key : String) -> Unit {
  let t = @sf.theme()
  let p = service_pages.get(key)
  let current = match p {
    Some(x) => x.viewport
    None => None
  }
  let preset = preset_of(current)
  sheet_head_line(c, svc("android-chat.preview.size.title"))
  c.box(w=Fill(1.0), pl=10.0, pr=10.0, pb=24.0, fn() {
    let option = fn(k : String, checked : Bool, name : String, note : String, v : Viewport?) {
      let id = c.id("service/size/" + k)
      if c.clicked(id) {
        match p {
          Some(x) => {
            x.viewport = v
            svc_viewports[key] = v
          }
          None => ()
        }
        lower_sheet()
      }
      c.box(
        dir=Row,
        w=Fill(1.0),
        h=Px(48.0),
        radius=12.0,
        padx=10.0,
        gap=10.0,
        align=ACenter,
        bg=@sf.alpha(t.p.text, 0.06 * @motion.pressing(c, id)),
        id~,
        fn() {
          c.box(w=Px(18.0), align=ACenter, fn() {
            if checked {
              @sf.icon(c, "check", size=16.0, color=t.p.accent) |> ignore
            }
          })
          |> ignore
          c.box(w=Fill(1.0), fn() {
            c.text(name, size=15.0, weight=if checked { 500 } else { 400 }, color=t.p.text, wrap=false) |> ignore
          })
          |> ignore
          c.text(note, size=13.0, color=t.p.muted, wrap=false) |> ignore
        },
      )
      |> ignore
    }
    option("fit", current is None, svc("android-chat.preview.fit"), svc("android-chat.preview.fit.note"), None)
    for pr in svc_presets {
      option(
        pr.0,
        preset == Some(pr.0),
        svc("android-chat.preview.preset." + pr.0),
        dims(pr.1, Some(pr.2)),
        Some({ width: pr.1, height: Some(pr.2) }),
      )
    }
  })
  |> ignore
}

///|
/// A sheet's head (SheetHead): its words, 17 semibold, 20 in.
fn sheet_head_line(c : @ui.Ctx, words : String) -> Unit {
  c.box(w=Fill(1.0), padx=20.0, pt=4.0, pb=10.0, fn() {
    c.text(words, size=17.0, weight=600, color=@sf.theme().p.text, wrap=false) |> ignore
  })
  |> ignore
}

///|
/// How the page's resources came, each of them (PreviewLoad.kt PreviewLoadDetails).
fn load_sheet(c : @ui.Ctx, src : Source, station : String, port : Int) -> Unit {
  let t = @sf.theme()
  let v = (src.topic)("previewLoad", { "station": Json::string(station), "port": Json::number(port.to_double()) }).value
  let label = load_label(v)
  sheet_head_line(c, label)
  c.box(w=Fill(1.0), padx=20.0, fn() {
    c.text(svc("android-chat.load.note"), size=12.0, color=t.p.muted) |> ignore
    c.box(w=Fill(1.0), pt=12.0, fn() {
      if number(v, "total") <= 0.0 {
        c.text(svc("android-chat.load.waiting"), size=13.0, color=t.p.muted) |> ignore
      }
      for r in items(v, "resources") {
        let rr = Some(r)
        let failed = text(rr, "error") != "" || number(rr, "status") >= 400.0
        let color = if failed { t.p.red } else { t.p.muted }
        let ended = field(rr, "ended") is Some(Number(_, ..))
        c.box(w=Fill(1.0), pt=6.0, pb=6.0, fn() {
          c.box(dir=Row, w=Fill(1.0), gap=10.0, align=ACenter, fn() {
            c.box(w=Fill(1.0), clip=true, fn() {
              c.text(text(rr, "path"), size=13.0, color~, wrap=false) |> ignore
            })
            |> ignore
            c.text(
              if !ended {
                svc("common.reading")
              } else if text(rr, "error") != "" {
                svc("android-chat.load.failed")
              } else {
                number(rr, "status").to_int().to_string()
              },
              size=12.0,
              color~,
              wrap=false,
            )
            |> ignore
            if ended {
              let ms = dmax(0.0, number(rr, "ended") - number(rr, "since")).to_int64()
              c.text("\{ms} ms", size=12.0, color~, wrap=false) |> ignore
            }
          })
          |> ignore
          if text(rr, "error") != "" {
            c.text(text(rr, "error"), size=12.0, color~) |> ignore
          }
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
fn load_label(v : Json?) -> String {
  let n = fn(k : String) { number(v, k).to_int().to_string() }
  if number(v, "failed") > 0.0 {
    svc("android-chat.load.label.failed", args=[
      ("percent", n("percent")),
      ("finished", n("finished")),
      ("total", n("total")),
      ("failed", n("failed")),
    ])
  } else {
    svc("android-chat.load.label", args=[("percent", n("percent")), ("finished", n("finished")), ("total", n("total"))])
  }
}
