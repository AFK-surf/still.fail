// A service's page speaking with the app (service_link.mbt), marking it (service_marks.mbt) and its stage's fingers
// (service.mbt), over the fixture's service (service_fixture.mbt) with the core's calls the page makes seen by the test.

///|
/// What the core was asked while a test ran: the calls (name, params, bytes beside), and the streamed calls (name,
/// params, bytes beside, how each says how it goes, how it ends), oldest first.
priv struct Asked {
  calls : Array[(String, Json, Bytes?)]
  streams : Array[(String, Json, Bytes?, (Json, Bytes?) -> Unit, (Result[Json, Json]) -> Unit)]
}

///|
/// The service's page over the fixture, with its calls of the core's for the page seen by the test (station.preview
/// answered by the fixture's station as ever).
fn link_tester(mode? : String = "service") -> (@ui.Tester, Asked) {
  reset()
  let base = fixture(mode)
  open_drive_fixture(mode)
  let asked : Asked = { calls: [], streams: [] }
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      if name.has_prefix("preview.socket") {
        asked.calls.push((name, params, None))
        done(Ok(Json::object({})))
      } else {
        (base.call)(name, params, done)
      }
    },
    call_bytes: fn(name, params, bytes, done) {
      if name.has_prefix("preview.socket") {
        asked.calls.push((name, params, Some(bytes)))
        done(Ok(Json::object({})))
      } else {
        (base.call_bytes)(name, params, bytes, done)
      }
    },
    stream: fn(name, params, bytes, on_value, done) {
      asked.streams.push((name, params, bytes, on_value, done))
      // the page itself answered by the fixture's station; the rest by the test
      if name == "station.preview" && text(Some(params), "path") == "/" {
        (base.stream)(name, params, bytes, on_value, done)
      } else {
        asked.streams.length()
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  (t, asked)
}

///|
/// The service's page's view (the site the fake host opened).
fn site_id(t : @ui.Tester) -> Int {
  opened_views(t, 3)[0]
}

///|
/// The scripts the app had the page run, joined (to look for what is in them).
fn ran(t : @ui.Tester, id : Int) -> String {
  t.view_scripts(id).join("\n")
}

///|
test "page.js served from here, behind the app's StillFailPreviewNative, the language said first" {
  let js = page_script_served(true)
  assert_true(js.has_prefix("self.__stillfailLang = \"zh\";\nwindow.__mbuiFetch = true;\n"))
  assert_true(js.contains("window.StillFailPreviewNative = {"))
  assert_true(js.contains(page_js))
  assert_false(page_script_served(false).contains("__mbuiFetch = true"))
  let (t, _) = link_tester()
  t.frame()
  let site = site_id(t)
  t.site_says("{\"req\":9,\"method\":\"GET\",\"path\":\"/_stillfail/page.js?v=1\",\"headers\":[],\"page\":false}")
  t.frame()
  let v = t.views()
  assert_true(v.iter().any(fn(s) { s.has_prefix("site head \{site} 9 200 ") && s.contains("text/javascript") }))
  assert_true(v.contains("site end \{site} 9 "))
}

///|
test "a page of the service gets page.js's tag after its <head>, its length no longer said" {
  let (t, _) = link_tester()
  t.frame()
  let site = site_id(t)
  t.site_says("{\"req\":1,\"method\":\"GET\",\"path\":\"/\",\"headers\":[[\"Accept\",\"text/html\"]],\"page\":true}")
  t.frame()
  let v = t.views()
  let head = v.iter().find_first(fn(s) { s.has_prefix("site head \{site} 1 200 ") }).unwrap()
  assert_false(head.to_lower().contains("content-length"))
  let n = @utf8.encode(fix_service_html).length() + @utf8.encode(page_js_tag).length()
  assert_true(v.contains("site chunk \{site} 1 \{n}"))
}

///|
test "the tag's place: after <head>, else <html>, else the doctype, else first; waiting while it may come" {
  let tag = page_js_tag
  let tg = tagging_new()
  // the start waits until the <head> tag is there
  assert_eq(tagging_take(tg, @utf8.encode("<!doctype html><ht"), false).length(), 0)
  let out = tagging_take(tg, @utf8.encode("ml lang=zh><HEAD><title>"), false)
  assert_eq(@codec.utf8_text(out, 1000), "<!doctype html><html lang=zh><HEAD>" + tag + "<title>")
  assert_eq(@codec.utf8_text(tagging_take(tg, @utf8.encode("rest"), false), 100), "rest")
  // a page with no <head> or <html>: after its doctype once it ends
  let t2 = tagging_new()
  assert_eq(tagging_take(t2, @utf8.encode("<!DOCTYPE html><p>x"), false).length(), 0)
  assert_eq(@codec.utf8_text(tagging_take(t2, Bytes::new(0), true), 1000), "<!DOCTYPE html>" + tag + "<p>x")
  // none of them: first
  let t3 = tagging_new()
  assert_eq(@codec.utf8_text(tagging_take(t3, @utf8.encode("<p>x"), true), 1000), tag + "<p>x")
  // a <header> is no <head>
  let t4 = tagging_new()
  assert_eq(@codec.utf8_text(tagging_take(t4, @utf8.encode("<html><header>"), true), 1000), "<html>" + tag + "<header>")
}

///|
test "the page's WebSockets through the core: opened, what it hears said into it, what it sends sent, closed" {
  let (t, asked) = link_tester()
  t.frame()
  let site = site_id(t)
  t.view_says(site, "{\"p\":\"page\"}")
  t.view_says(site, "{\"p\":\"open\",\"sid\":\"s1\",\"path\":\"/ws?x=1\",\"protocols\":\"vite-hmr\"}")
  t.frame()
  let (name, params, _, on_value, done) = asked.streams[asked.streams.length() - 1]
  assert_eq(name, "preview.socket")
  assert_eq(text(Some(params), "socket"), "s1")
  assert_eq(text(Some(params), "path"), "/ws?x=1")
  assert_eq(text(Some(params), "station"), "ws1/st1")
  assert_eq(field(Some(params), "headers"), Some([["sec-websocket-protocol", "vite-hmr"]]))
  on_value({ "open": { "protocol": "vite-hmr" } }, None)
  on_value({ "text": "{\"type\":\"update\"}" }, None)
  on_value({ "binary": true }, Some(b"\x01\x02"))
  t.frame()
  let s = ran(t, site)
  assert_true(s.contains("__stillfailSocketEvent(\"s1\",\"open\",\"vite-hmr\")"))
  assert_true(s.contains("__stillfailSocketEvent(\"s1\",\"text\",\"{\\\"type\\\":\\\"update\\\"}\")"))
  assert_true(s.contains("__stillfailSocketEvent(\"s1\",\"binary\",\"AQI=\")"))
  t.view_says(site, "{\"p\":\"send\",\"sid\":\"s1\",\"text\":\"ping\"}")
  t.view_says(site, "{\"p\":\"sendBinary\",\"sid\":\"s1\",\"b64\":\"AQI=\"}")
  t.view_says(site, "{\"p\":\"close\",\"sid\":\"s1\",\"code\":1000,\"reason\":\"bye\"}")
  // another socket's name, or a socket not open: let go
  t.view_says(site, "{\"p\":\"send\",\"sid\":\"s2\",\"text\":\"nobody\"}")
  t.frame()
  assert_eq(asked.calls.length(), 3)
  assert_eq(asked.calls[0].1, { "socket": "s1", "text": "ping" })
  assert_eq(asked.calls[1].1, { "socket": "s1", "binary": true })
  assert_eq(asked.calls[1].2, Some(b"\x01\x02"))
  assert_eq(asked.calls[2].1, { "socket": "s1", "close": [1000, "bye"] })
  done(Ok({ "code": 1000, "reason": "bye" }))
  t.frame()
  assert_true(ran(t, site).contains("__stillfailSocketEvent(\"s1\",\"close\",1000,\"bye\",false)"))
}

///|
test "a new page: the sockets of the one before stopped; what does not read as the page's is let go" {
  let (t, asked) = link_tester()
  t.frame()
  let site = site_id(t)
  t.view_says(site, "{\"p\":\"open\",\"sid\":\"s1\",\"path\":\"/ws\",\"protocols\":\"\"}")
  // no name, a path not from the root, a control in it: none opened
  t.view_says(site, "{\"p\":\"open\",\"sid\":\"\",\"path\":\"/ws\"}")
  t.view_says(site, "{\"p\":\"open\",\"sid\":\"s3\",\"path\":\"ws\"}")
  t.view_says(site, "{\"p\":\"open\",\"sid\":\"s4\",\"path\":\"/a b\"}")
  t.view_says(site, "not json")
  t.frame()
  let opened = asked.streams.filter(fn(s) { s.0 == "preview.socket" })
  assert_eq(opened.length(), 1)
  let p = service_pages.get(service_key("ws1/st1", "j-web")).unwrap()
  assert_eq(p.link.sockets.length(), 1)
  t.view_says(site, "{\"p\":\"page\"}")
  t.frame()
  assert_eq(p.link.sockets.length(), 0)
}

///|
test "a request's body the page left here goes with it, under its type; the id taken off" {
  let (t, asked) = link_tester()
  t.frame()
  let site = site_id(t)
  t.view_says(site, "{\"p\":\"stash\",\"id\":\"b-1\",\"b64\":\"aGk=\",\"type\":\"text/plain\"}")
  t.frame()
  t.site_says(
    "{\"req\":5,\"method\":\"POST\",\"path\":\"/api\",\"headers\":[[\"x-stillfail-body\",\"b-1\"]],\"page\":false}",
  )
  t.frame()
  let (name, params, bytes, _, _) = asked.streams[asked.streams.length() - 1]
  assert_eq(name, "station.preview")
  assert_eq(text(Some(params), "method"), "POST")
  assert_eq(bytes, Some(b"hi"))
  assert_eq(field(Some(params), "headers"), Some([["Content-Type", "text/plain"]]))
  let p = service_pages.get(service_key("ws1/st1", "j-web")).unwrap()
  assert_eq(p.link.bodies.length(), 0)
}

///|
test "the top page's fetch() on its port: asked of the service, its answer said back as it comes" {
  let (t, asked) = link_tester()
  t.frame()
  let site = site_id(t)
  t.view_says(
    site,
    "{\"p\":\"port\",\"m\":{\"t\":\"go\",\"id\":\"f1\",\"method\":\"post\",\"path\":\"/api/log?n=2\",\"headers\":[[\"accept\",\"*/*\"],[\"Host\",\"evil\"]],\"redirect\":\"follow\",\"cookies\":true,\"body\":\"eyJhIjoxfQ==\"}}",
  )
  t.frame()
  let (name, params, bytes, on_value, done) = asked.streams[asked.streams.length() - 1]
  assert_eq(name, "station.preview")
  assert_eq(text(Some(params), "method"), "POST")
  assert_eq(text(Some(params), "path"), "/api/log?n=2")
  assert_eq(field(Some(params), "headers"), Some([["accept", "*/*"]]))
  assert_eq(bytes, Some(b"{\"a\":1}"))
  on_value({ "head": { "status": 200, "headers": [["Content-Type", "text/plain"]] } }, None)
  on_value({ "chunk": true }, Some(b"one\n"))
  t.frame()
  let s = ran(t, site)
  assert_true(s.contains("__mbuiPort("))
  assert_true(s.contains("\\\"t\\\":\\\"head\\\""))
  assert_true(s.contains("\\\"b\\\":\\\"b25lCg==\\\""))
  assert_false(s.contains("\\\"t\\\":\\\"end\\\""))
  done(Ok(Json::null()))
  t.frame()
  assert_true(ran(t, site).contains("\\\"t\\\":\\\"end\\\""))
  // a bad one: said so, nothing asked
  let n = asked.streams.length()
  t.view_says(site, "{\"p\":\"port\",\"m\":{\"t\":\"go\",\"id\":\"f2\",\"method\":\"GET\",\"path\":\"nope\"}}")
  t.frame()
  assert_eq(asked.streams.length(), n)
  assert_true(ran(t, site).contains("请求无效"))
}

///|
/// A PNG's start, `w` × `h` (what png_size reads; the fake host draws nothing on it).
fn png_hex_head(w : Int, h : Int) -> String {
  let hex = fn(n : Int) {
    let d = "0123456789abcdef".to_array()
    let out = StringBuilder::new()
    for i in [24, 16, 8, 0] {
      let b = (n >> i) & 0xFF
      out.write_char(d[b >> 4])
      out.write_char(d[b & 15])
    }
    out.to_string()
  }
  "89504e470d0a1a0a0000000d49484452" + hex(w) + hex(h) + "08060000001f15c489"
}

///|
test "marking: the edit key picks, a mark picked is boxed and pinned, put into the chat as a picture and a quote" {
  let (t, _) = link_tester()
  t.frame()
  t.frame()
  let site = site_id(t)
  // (the bar's edit key: no words to tap it by)
  let p = service_pages.get(service_key("ws1/st1", "j-web")).unwrap()
  page_marks_toggle(p, p.site.unwrap())
  t.frame()
  t.frame()
  assert_true(t.find("点选页面上的元素") is Some(_))
  assert_true(ran(t, site).contains("__stillfailMarks.on(true)"))
  t.view_says(
    site,
    "{\"p\":\"marked\",\"json\":\"{\\\"event\\\":\\\"picked\\\",\\\"mark\\\":{\\\"n\\\":1,\\\"path\\\":\\\"/\\\",\\\"viewport\\\":{\\\"width\\\":390,\\\"height\\\":600},\\\"label\\\":\\\"button.go\\\",\\\"kind\\\":\\\"按钮\\\",\\\"selector\\\":\\\"main > button\\\",\\\"text\\\":\\\"构建\\\",\\\"rect\\\":{\\\"x\\\":20,\\\"y\\\":40,\\\"width\\\":100,\\\"height\\\":30},\\\"page\\\":{\\\"x\\\":20,\\\"y\\\":40,\\\"width\\\":100,\\\"height\\\":30}}}\"}",
  )
  t.frame()
  t.frame()
  assert_true(t.find("已标注 1 处") is Some(_))
  // put: the page's scroll asked, then where the mark is; the window's picture; the mark drawn on it
  t.tap_text("添加到对话")
  t.frame()
  t.frame()
  assert_true(t.find("正在截图") is Some(_))
  assert_true(ran(t, site).contains("t:\"y0\",v:scrollY"))
  t.view_says(site, "{\"p\":\"shot\",\"k\":1,\"t\":\"y0\",\"v\":0}")
  t.frame()
  t.frame()
  assert_true(ran(t, site).contains("__stillfailMarks.place(1,false)"))
  // (the mark no longer on the page: place says null)
  t.view_says(site, "{\"p\":\"shot\",\"k\":1,\"t\":\"place\",\"v\":null}")
  t.frame()
  t.frame()
  assert_true(t.find("无法添加到对话：标注 1 已不在页面上") is Some(_))
  // (the key itself: why it failed says 添加到对话 too, beside it)
  t.click(Button, label="添加到对话")
  t.frame()
  t.frame()
  t.view_says(site, "{\"p\":\"shot\",\"k\":2,\"t\":\"y0\",\"v\":0}")
  t.frame()
  t.frame()
  t.view_says(
    site,
    "{\"p\":\"shot\",\"k\":2,\"t\":\"place\",\"v\":\"{\\\"x\\\":20,\\\"y\\\":40,\\\"width\\\":390,\\\"height\\\":30,\\\"scrollY\\\":0}\"}",
  )
  t.frame()
  t.frame()
  // the grab: the host's picture of the page, 780 wide (two pixels a CSS pixel)
  assert_true(t.view_said("{\"view\":{\"view\":\{site},\"what\":2,\"text\":\"2\"}}"))
  assert_true(t.view_said("{\"still\":{\"view\":\{site}},\"b\":\"" + png_hex_head(780, 1200) + "\"}"))
  t.frame()
  t.frame()
  t.frame()
  let drawn = t.marks_drawn()
  assert_eq(drawn.length(), 1)
  let d = @json.parse(drawn[0])
  assert_eq(number(Some(d), "w"), 780.0)
  let m = items(Some(d), "marks")[0]
  assert_eq(text(Some(m), "kind"), "box")
  assert_eq(field(Some(m), "pts"), Some([40, 80, 820, 140]))
  assert_eq(number(Some(m), "n"), 1.0)
  t.frame()
  t.frame()
  let into = marked_into.get("ws1/st1:s-c1").unwrap()
  assert_eq(into.length(), 1)
  assert_true(into[0].0.has_prefix("web-标注1-"))
  assert_eq(into[0].3, "page")
  assert_eq(into[0].2[0].0, "网页 web 标注 1")
  assert_true(into[0].2[0].1.has_prefix("按钮「构建」\n元素：button.go · 选择器：main > button\n页面：/（视口 390×600）"))
  assert_true(t.find("点选页面上的元素") is None)
}

///|
test "a sized page on its canvas: the ground dragged moves it, 适应 (its sizes' panel) and a double tap fit it again" {
  let (t, _) = link_tester(mode="service-sized")
  t.frame()
  let site = site_id(t)
  let (x0, y0, _, _) = view_rect(t, site).unwrap()
  // a sized page gives two fingers to the canvas
  assert_true(t.views().iter().any(fn(l) { l.has_prefix("touch \{site} pinch") }))
  // on the ground, right of the page (its left edge is the screen's: a drag there goes back)
  t.drag(362.0, 400.0, 302.0, 430.0)
  t.frame()
  let (x1, y1, _, _) = view_rect(t, site).unwrap()
  assert_true(x1 < x0 - 40.0)
  assert_true(y1 > y0 + 20.0)
  // 适应, among the sizes (its ⋯'s): fitted again, the sizes gone
  t.click(Button, label="更多操作")
  t.frame()
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  t.tap_text("页面尺寸")
  t.frame()
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  t.click(Button, label="适应")
  t.frame()
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_eq(view_rect(t, site).unwrap().0, x0)
  // moved again, then two taps on the ground
  t.drag(362.0, 400.0, 302.0, 430.0)
  t.frame()
  t.tap(362.0, 300.0)
  t.tap(362.0, 300.0)
  t.frame()
  assert_eq(view_rect(t, site).unwrap().0, x0)
  // 移动 (its key has no words to tap it by): the page's touches all the canvas's
  let p = service_pages.get(service_key("ws1/st1", "j-web")).unwrap()
  p.moving = true
  t.frame()
  assert_true(t.views().iter().any(fn(l) { l.has_prefix("touch \{site} through") }))
}

///|
test "redirects resolved as a browser does: dot segments out, a fragment never asked" {
  assert_eq(service_redirect("/a/b/c", "../d"), Ok("/a/d"))
  assert_eq(service_redirect("/a/b/c", "./d?x=1#top"), Ok("/a/b/d?x=1"))
  assert_eq(service_redirect("/a/b/", ".."), Ok("/a/"))
  assert_eq(service_redirect("/a", "/x/./y/../z"), Ok("/x/z"))
  assert_eq(service_redirect("/", "http://localhost:5173?x=1"), Ok("/?x=1"))
  assert_true(service_redirect("/", "mailto:a@b.c") is Err(_))
}

///|
test "the system's back steps the page back in its own history first; at its first page it leaves (Preview.kt BackHandler(canBack))" {
  let (t, _) = link_tester()
  let site = site_id(t)
  let depth = app.nav.depth()
  assert_true(depth > 1)
  let state = fn(path : String, back : Bool) {
    "{\"sitestate\":{\"view\":\{site},\"state\":{\"path\":\"\{path}\",\"loading\":false,\"title\":\"\",\"forward\":false,\"back\":\{back}}}}"
  }
  assert_true(t.view_said(state("/b.html", true)))
  // (the view's word taken as a frame begins, the page's back as the frame after builds it)
  t.frame()
  t.draw()
  t.back()
  // the page a step back, the service's page still there
  if !t.views().iter().any(fn(s) { s.has_prefix("control \{site} 5 ") }) {
    fail("the page not stepped back: \{t.views()}")
  }
  assert_eq(app.nav.depth(), depth)
  assert_true(t.view_said(state("/", false)))
  // (the view's word taken as a frame begins, the page's back as the frame after builds it)
  t.frame()
  t.draw()
  t.back()
  t.run_for(@ui.nav_rest() - t.time())
  assert_eq(app.nav.depth(), depth - 1)
}
