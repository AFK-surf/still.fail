// A service's page over the fixture (APP=sffix MBUI_FIXTURE=service | service-sized | service-restart |
// service-stopped; scripts/shots.sh service, web-service): the first row's chat's web service (slice 8's j-web), its page
// answered as a station would (`station.preview`: a made-up page, its stylesheet; the rest not found), its resources'
// ring, laid out as a phone's on the canvas, being started again, stopped. Every word in it is made up.

///|
let fix_service_html : String =
  #|<!doctype html>
  #|<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
  #|<link rel="stylesheet" href="/app.css"><title>发布看板</title></head>
  #|<body><header>发布看板</header>
  #|<main><div class="card"><b>今日构建</b><p>3 个通过，1 个在跑</p><div class="bar" style="width:75%"></div></div>
  #|<div class="card"><b>待确认</b><p>安卓包签名、更新说明</p><div class="bar" style="width:40%"></div></div>
  #|<p id="n">脚本还没有运行</p></main>
  #|<script>document.getElementById('n').textContent = '脚本已运行：' + (6 * 7);</script>
  #|</body></html>

///|
let fix_service_css : String =
  #|body { margin: 0; font-family: system-ui, sans-serif; color: #24272b; background: #f7f6f3; }
  #|header { padding: 18px 20px; font-size: 20px; font-weight: 700; background: #e5704a; color: #fff; }
  #|main { padding: 12px 16px; }
  #|.card { background: #fff; border-radius: 12px; padding: 14px; margin: 10px 0; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
  #|.card p { margin: 6px 0 10px; color: #646970; }
  #|.bar { height: 8px; border-radius: 4px; background: #2f8f5b; }

///|
/// The service's own topics: its job (as the mode has it) and how its page's resources came.
fn fixture_service_topic(f : Fixture, name : String, params : Map[String, Json]) -> Json? {
  match name {
    "job" => {
      let m = match fix_job(text(Some(Json::object(params)), "id")) {
        Object(m) => m.copy()
        _ => return Some(Json::null())
      }
      if f.mode == "service-restart" {
        m["state"] = Json::string("exited")
        m["tone"] = Json::string("restart")
        m["restarts"] = Json::number(2.0)
      }
      if f.mode == "service-stopped" {
        m["state"] = Json::string("stopped")
        m["tone"] = Json::string("off")
        m["open"] = Json::boolean(false)
      }
      Some(Json::object(m))
    }
    "previewLoad" =>
      Some({
        "percent": 75,
        "total": 4,
        "finished": 3,
        "failed": 0,
        "resources": [
          { "id": 1, "method": "GET", "path": "/", "since": 0, "ended": 42, "status": 200 },
          { "id": 2, "method": "GET", "path": "/app.css", "since": 50, "ended": 61, "status": 200 },
          { "id": 3, "method": "GET", "path": "/favicon.ico", "since": 52, "ended": 60, "status": 404 },
          { "id": 4, "method": "GET", "path": "/api/builds", "since": 70 },
        ],
      })
    _ => None
  }
}

///|
/// `station.preview` as a station answers it: the page and its stylesheet, anything else not found; the head, then
/// the body in one piece.
fn fixture_stream(
  name : String,
  params : Json,
  on_value : (Json, Bytes?) -> Unit,
  done : (Result[Json, Json]) -> Unit,
) -> Int {
  if name == "screen.view" {
    // a link's card's preview (screen_links.mbt: peek), or the viewer's (screen.mbt)
    if params is Object(o) && o.get("peek") is Some(True) {
      return fixture_peek(on_value)
    }
    return screen_fixture_stream(params, on_value, done)
  }
  if name != "station.preview" {
    done(Err({ "code": "unknown_call", "message": "这份假数据没有 " + name }))
    return 0
  }
  let path = text(Some(params), "path")
  let (status, kind, body) = match path {
    "/" | "/index.html" => (200, "text/html; charset=utf-8", fix_service_html)
    "/app.css" => (200, "text/css; charset=utf-8", fix_service_css)
    _ => (404, "text/plain; charset=utf-8", "Not Found")
  }
  on_value({ "head": { "status": status, "headers": [["Content-Type", kind]] } }, None)
  on_value({ "chunk": true }, Some(utf8_bytes(body)))
  done(Ok(Json::null()))
  fix_stream_ids.val += 1
  fix_stream_ids.val
}

///|
let fix_stream_ids : Ref[Int] = Ref(0)

///|
/// MBUI_FIXTURE=service…: the first row's chat, its service's page over it.
fn open_service_fixture(mode : String) -> Unit {
  match mode {
    "service" | "service-sized" | "service-restart" | "service-stopped" => {
      app.nav.push(Chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }))
      app.nav.push(Service("ws1/st1", "j-web"))
      if mode == "service-sized" {
        svc_viewports[service_key("ws1/st1", "j-web")] = Some({ width: 390, height: Some(844) })
      }
    }
    _ => ()
  }
}
