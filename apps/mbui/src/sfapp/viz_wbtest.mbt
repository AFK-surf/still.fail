// Visualizations (viz.mbt) over the made-up chat (MBUI_FIXTURE=chat-viz: its last message places release.html and has
// a mermaid chart), as Android's Viz.kt and VizFiles.kt have them.

///|
/// A number as a line of the fake host's says it.
fn test_num(s : String) -> Double {
  match (try Some(@json.parse(s)) catch { _ => None }) {
    Some(Number(n, ..)) => n
    _ => 0.0
  }
}

///|
/// The views the fake host opened of `kind`, by id, oldest first.
fn opened_views(t : @ui.Tester, kind : Int) -> Array[Int] {
  let out = []
  for l in t.views() {
    let p = l.split(" ").map(fn(x) { x.to_owned() }).to_array()
    if p.length() >= 4 && p[0] == "open" && p[2] == kind.to_string() {
      out.push(test_num(p[1]).to_int())
    }
  }
  out
}

///|
/// The page of the visualization the message places, and the mermaid chart's: by what each draws (the order they are
/// opened in is the frame's builds', not the message's).
fn viz_views(t : @ui.Tester) -> (Int, Int) {
  ignore(t)
  let mut page = 0
  let mut chart = 0
  for k, f in viz_frames {
    if k.has_suffix("/release.html") {
      page = f.view.id()
    } else if k.contains("/mermaid/") {
      chart = f.view.id()
    }
  }
  (page, chart)
}

///|
/// The hole the view `id` shows through, its rect (x, y, w, h): its last placing, shown.
fn view_rect(t : @ui.Tester, id : Int) -> (Double, Double, Double, Double)? {
  let mut out = None
  for l in t.views() {
    let p = l.split(" ").map(fn(x) { x.to_owned() }).to_array()
    if p.length() >= 6 && p[0] == "place" && p[1] == id.to_string() {
      out = if p[p.length() - 1] == "hidden" {
        None
      } else {
        Some((test_num(p[2]), test_num(p[3]), test_num(p[4]), test_num(p[5])))
      }
    }
  }
  out
}

///|
test "a placed HTML file is drawn in its message, 120 high, covered until it has drawn; then as tall as it says" {
  let t = chat_tester("chat-viz")
  t.frame()
  let (page, _) = viz_views(t)
  // its document: the web's stylesheet and bridge round its content, the relay to the app
  let (_, _, w, h) = view_rect(t, page).unwrap()
  assert_eq(h, 120.0)
  assert_true(w > 300.0)
  // in a list: an upright drag on it moves the list
  assert_true(t.views().iter().any(fn(l) { l.has_prefix("touch \{page} vertical ") }))
  // what it says of its height: taken, however tall (a long post's last part not cut off), and the page shown (heard
  // as a frame is painted: the next one has it)
  t.view_says(page, "{\"emberViz\":true,\"type\":\"height\",\"height\":231.4}")
  t.frame()
  t.frame()
  let (_, _, _, h2) = view_rect(t, page).unwrap()
  assert_eq(h2, 232.0)
  t.view_says(page, "{\"emberViz\":true,\"type\":\"height\",\"height\":5000}")
  t.frame()
  t.frame()
  assert_eq(view_rect(t, page).unwrap().3, 5000.0)
  // what is not a message of the bridge's is let go
  t.view_says(page, "not json")
  t.view_says(page, "{\"type\":\"height\",\"height\":\"tall\"}")
  t.frame()
  assert_eq(view_rect(t, page).unwrap().3, 5000.0)
}

///|
test "a page that grows a little with each height it is given (100vh) is held where it got to; shorter, it follows" {
  let t = chat_tester("chat-viz")
  t.frame()
  let (page, _) = viz_views(t)
  t.view_says(page, "{\"emberViz\":true,\"type\":\"height\",\"height\":300}")
  for i in 1..=100 {
    t.view_says(page, "{\"emberViz\":true,\"type\":\"height\",\"height\":\{300 + i * 10}}")
  }
  t.frame()
  t.frame()
  // 60 times running it followed, then held
  assert_eq(view_rect(t, page).unwrap().3, 900.0)
  t.view_says(page, "{\"emberViz\":true,\"type\":\"height\",\"height\":2000}")
  t.frame()
  assert_eq(view_rect(t, page).unwrap().3, 900.0)
  t.view_says(page, "{\"emberViz\":true,\"type\":\"height\",\"height\":400}")
  t.frame()
  t.frame()
  assert_eq(view_rect(t, page).unwrap().3, 400.0)
}

///|
test "what a visualization's widget keeps is kept, given back as it is shown again; over 16 KiB let go" {
  let t = chat_tester("chat-viz")
  t.frame()
  let (page, _) = viz_views(t)
  t.view_says(page, "{\"emberViz\":true,\"type\":\"state\",\"state\":{\"seen\":true}}")
  t.frame()
  let l = viz_loads.get(viz_id("ws1/st1", "s-c1", "work/s-c1/release.html")).unwrap()
  assert_eq(l.state, Some({ "seen": true }))
  let big = "x".repeat(17000)
  t.view_says(page, "{\"emberViz\":true,\"type\":\"state\",\"state\":\"" + big + "\"}")
  t.frame()
  assert_eq(l.state, Some({ "seen": true }))
}

///|
test "words a visualization asks to send go into the composer, said so; the person sends them" {
  let t = chat_tester("chat-viz")
  t.frame()
  let (page, _) = viz_views(t)
  t.view_says(page, "{\"emberViz\":true,\"type\":\"followup\",\"prompt\":\"  把周五的发布挪到周四 \"}")
  t.frame()
  let d = drafts.get("ws1/st1:s-c1").unwrap()
  assert_eq(d.text, "把周五的发布挪到周四")
  t.frame()
  assert_true(t.find("已添加到输入框，确认后发送") is Some(_))
}

///|
test "under the page: the whole screen, its name and a close over it; back closes it" {
  let t = chat_tester("chat-viz")
  t.frame()
  let (page, _) = viz_views(t)
  let (x, y, w, h) = view_rect(t, page).unwrap()
  // the two 22 boxes under it, at its right: the whole screen, then beside
  t.tap(x + w - 22.0 - 2.0 - 11.0, y + h + 2.0 + 11.0)
  t.frame()
  assert_true(t.find("release.html") is Some(_))
  let full = opened_views(t, 2)
  assert_eq(full.length(), 3)
  // a page of its own: it keeps its touches
  assert_false(t.views().iter().any(fn(l) { l.has_prefix("touch \{full[2]} ") }))
  t.back()
  t.frame()
  assert_true(t.find("release.html") is None)
  assert_true(t.views().contains("close \{full[2]}"))
}

///|
test "beside: the visualization as a page of its own, served from here with what it kept; nothing else there" {
  let t = chat_tester("chat-viz")
  t.frame()
  let (page, _) = viz_views(t)
  let (x, y, w, h) = view_rect(t, page).unwrap()
  t.tap(x + w - 11.0, y + h + 2.0 + 11.0)
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("release.html") is Some(_))
  let sites = opened_views(t, 3)
  assert_eq(sites.length(), 1)
  let site = sites[0]
  // (said to the site's view: the pages in the chat under it take what is said to any view)
  let ask = fn(e : String) {
    let said = Json::object({
      "site": Json::object({ "view": Json::number(site.to_double()), "event": Json::string(e) }),
    })
    t.view_said(said.stringify()) |> ignore
  }
  ask("{\"req\":1,\"method\":\"GET\",\"path\":\"/\",\"headers\":[],\"page\":true}")
  ask("{\"req\":2,\"method\":\"GET\",\"path\":\"/app.js\",\"headers\":[],\"page\":false}")
  t.frame()
  let v = t.views()
  assert_true(v.iter().any(fn(s) { s.has_prefix("site head \{site} 1 200 ") && s.contains("text/html") }))
  assert_true(v.iter().any(fn(s) { s.has_prefix("site head \{site} 2 404 ") }))
  // what its widget keeps from there is kept too
  t.view_says(site, "{\"emberViz\":true,\"type\":\"state\",\"state\":{\"n\":2}}")
  t.frame()
  assert_eq(viz_loads.get(viz_id("ws1/st1", "s-c1", "work/s-c1/release.html")).unwrap().state, Some({ "n": 2 }))
}

///|
test "a mermaid chart is drawn as a page of its own; one that will not draw is shown as code from then on" {
  let t = chat_tester("chat-viz")
  t.frame()
  let (_, chart) = viz_views(t)
  assert_true(t.find("graph LR; 构建-->签名-->发布") is None)
  t.view_says(chart, "{\"emberViz\":true,\"type\":\"failed\",\"message\":\"mermaid 加载失败\"}")
  t.frame()
  t.frame()
  assert_true(t.find("graph LR; 构建-->签名-->发布") is Some(_))
  assert_true(view_rect(t, chart) is None)
}

///|
test "under a mermaid chart: the whole screen, the chart as written to pinch, its touches its own; back closes it" {
  let t = chat_tester("chat-viz")
  t.frame()
  let (_, chart) = viz_views(t)
  // drawn (a line of it, so what is under it is above the composer)
  t.view_says(chart, "{\"emberViz\":true,\"type\":\"height\",\"height\":40}")
  t.frame()
  t.frame()
  let (x, y, w, h) = view_rect(t, chart).unwrap()
  // one 22 box under it, at its right
  t.tap(x + w - 11.0, y + h + 2.0 + 11.0)
  t.frame()
  assert_true(t.find("Mermaid") is Some(_))
  let mut full = 0
  for k, f in viz_frames {
    if k.has_prefix("full/mermaid/") {
      full = f.view.id()
      // fitted to the screen, the page moving it under the fingers
      assert_true(f.html.contains("const FULL = true"))
      assert_true(f.html.contains("touch-action:none"))
    }
  }
  assert_true(full != 0)
  assert_false(t.views().iter().any(fn(l) { l.has_prefix("touch \{full} ") }))
  t.back()
  t.frame()
  assert_true(t.find("Mermaid") is None)
  assert_true(t.views().contains("close \{full}"))
}

///|
test "a visualization's document: a fragment in the stylesheet with its tokens and what it kept; a whole page as written" {
  let doc = viz_document("<p>hi</p>", Some({ "a": "<b>" }), true, 0xF7F6F3FFL)
  assert_true(doc.has_prefix("<!doctype html><html data-theme=\"dark\">"))
  assert_true(doc.contains("--e-canvas:#1f2023"))
  assert_true(doc.contains("{\"widgetState\":{\"a\":\"\\u003cb>\"}}"))
  assert_true(doc.contains(":root:root{background:#f7f6f3}"))
  assert_true(doc.contains("mbuiHost.post"))
  assert_true(doc.has_suffix("<body><p>hi</p></body></html>"))
  assert_true(viz_is_fragment("<div>x</div>"))
  assert_false(viz_is_fragment("<!DOCTYPE html><p>x"))
  assert_false(viz_is_fragment("<html lang=zh><p>x"))
  let page = viz_page_document("<!doctype html><html><head><title>t</title></head><body></body></html>")
  assert_true(page.has_prefix("<!doctype html><html><head><meta http-equiv=\"Content-Security-Policy\""))
  assert_true(page.contains("<title>t</title>"))
}
