// The pages' contract (docs/determinism.md, "What is compared, and where"; scripts/host_contract.sh HOST site): on a
// real host, MBUI_SITECHECK=1: a site view and a page's view, each step started by what the page said before it, so
// nothing waits on a time:
//   the site's page says what cookies it has at the start (none: a run begins with none, whatever the last left), then
//   hello (mbuiHost.post), the app has it run a script, which answers (a script and its answer);
//   its document.cookie and a request of its own host after a request's answer that sets one (where the host keeps
//   the cookies: NativeView::keeps_cookies);
//   an event stream's first event, the next sent only once the page has said it has the first (an answer a line at a
//   time reaches the page as it is sent, not once the WebView's buffer is full);
//   what the page shows grabbed (a PNG);
//   a page of HTML (kind 2) that says hello and answers a script the same way.
// Each step on the log as `SITECHECK <step> <what>`, then `SITECHECK done` and the app's end.

///|
let site_check_view : Ref[@ui.NativeView?] = Ref(None)

///|
let site_check_page : Ref[@ui.NativeView?] = Ref(None)

///|
/// The event stream's answer, while it is open.
let site_check_events : Ref[@ui.SiteReply?] = Ref(None)

///|
let site_check_grabbing : Ref[Bool] = Ref(false)

///|
// kept across runs: a page, never written
let site_check_html : String =
  #|<!doctype html><html><head><title>sitecheck</title></head><body style="margin:0;background:#4a7">
  #|<script>
  #|const say = (t) => mbuiHost.post(String(t));
  #|window.__ping = (w) => say("pong " + w);
  #|say("start cookie " + (document.cookie || "none"));
  #|say("hello");
  #|</script></body></html>

///|
// kept across runs: a page, never written
let site_check_page_html : String =
  #|<!doctype html><html><body style="margin:0;background:#47a">
  #|<script>
  #|window.__ping = (w) => mbuiHost.post("page-pong " + w);
  #|mbuiHost.post("page-hello");
  #|</script></body></html>

///|
fn site_check_log(s : String) -> Unit {
  @host.log("SITECHECK " + s)
}

///|
fn site_check_bytes(s : String) -> Bytes {
  @utf8.encode(s)
}

///|
fn site_check_serve(req : @ui.SiteRequest, reply : @ui.SiteReply) -> Unit {
  let path = req.path
  if path == "/" {
    reply.head(200, [("Content-Type", "text/html; charset=utf-8")])
    reply.chunk(site_check_bytes(site_check_html))
    reply.end()
  } else if path == "/set" {
    reply.head(200, [("Content-Type", "text/plain"), ("Set-Cookie", "k=v; Path=/")])
    reply.chunk(site_check_bytes("set"))
    reply.end()
  } else if path == "/c" {
    let sent = req.headers.iter().any(fn(h) { h.0.to_lower() == "cookie" && h.1.contains("k=v") })
    reply.head(200, [("Content-Type", "text/plain")])
    reply.chunk(site_check_bytes(if sent { "cookie-sent" } else { "cookie-missing" }))
    reply.end()
  } else if path == "/events" {
    reply.head(200, [("Content-Type", "text/event-stream"), ("Cache-Control", "no-store")])
    reply.chunk(site_check_bytes("data: 1\n\n"))
    // (Windows' WebView2 takes an answer whole, at its end: both events at once there)
    if @ui.platform() == 3 {
      reply.chunk(site_check_bytes("data: 2\n\n"))
      reply.end()
    } else {
      site_check_events.val = Some(reply)
    }
  } else {
    reply.head(404, [("Content-Type", "text/plain")])
    reply.end()
  }
}

///|
fn site_check_said(v : @ui.NativeView, words : String) -> Unit {
  site_check_log("said " + words)
  if words == "hello" {
    v.script("__ping('one')")
  } else if words == "pong one" {
    v.script(
      "fetch('/set').then((r) => r.text()).then(() => { say('cookie ' + document.cookie); return fetch('/c'); }).then((r) => r.text()).then((t) => say('fetched ' + t), (e) => say('fetched failed ' + e))",
    )
  } else if words.has_prefix("fetched ") {
    site_check_log("cookies " + (if v.keeps_cookies() { "kept" } else { "app" }))
    v.script("window.__es = new EventSource('/events'); __es.onmessage = (e) => say('event ' + e.data)")
  } else if words == "event 1" {
    match site_check_events.val {
      Some(r) => r.chunk(site_check_bytes("data: 2\n\n"))
      None => ()
    }
  } else if words == "event 2" {
    v.script("__es.close()")
    match site_check_events.val {
      Some(r) => r.end()
      None => ()
    }
    site_check_events.val = None
    site_check_grabbing.val = true
    v.grab_frame(0.0)
  }
}

///|
/// The page of HTML's check: it says hello, a script of the app's has it answer.
fn site_check_page_open() -> Unit {
  let cell : Ref[@ui.NativeView?] = Ref(None)
  let p = @ui.NativeView::page(site_check_page_html, said=fn(w) {
    site_check_log("page " + w)
    match cell.val {
      Some(p) =>
        if w == "page-hello" {
          p.script("__ping('two')")
        } else if w == "page-pong two" {
          site_check_log("done")
          @host.exit(0)
        }
      None => ()
    }
  })
  cell.val = Some(p)
  site_check_page.val = Some(p)
}

///|
fn site_check_run(c : @ui.Ctx) -> Unit {
  let v = match site_check_view.val {
    Some(v) => v
    None => {
      let cell : Ref[@ui.NativeView?] = Ref(None)
      let v = @ui.NativeView::site("/", site_check_serve, said=fn(w) {
        match cell.val {
          Some(v) => site_check_said(v, w)
          None => ()
        }
      })
      cell.val = Some(v)
      site_check_view.val = Some(v)
      if !v.here() {
        // (the browser's: its page alone)
        site_check_log("no site view here")
        site_check_page_open()
      }
      v
    }
  }
  if site_check_grabbing.val {
    match v.grabbed() {
      Some(png) => {
        site_check_grabbing.val = false
        site_check_log("grab \{png.length()}")
        site_check_page_open()
      }
      None => ()
    }
  }
  c.column(fn() {
    if v.here() {
      c.native(v, h=Px(300.0)) |> ignore
    }
    match site_check_page.val {
      Some(p) => c.native(p, h=Px(200.0)) |> ignore
      None => ()
    }
  })
  |> ignore
}
