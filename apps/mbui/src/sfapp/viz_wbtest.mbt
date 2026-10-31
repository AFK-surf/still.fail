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
test "two scoped copies of a visualization each own their native view" {
  new_run()
  let t = @ui.Tester::new(fn(c) {
    @sf.begin(c) |> ignore
    c.with_theme(@sf.ui_theme(), fn() {
      for page in [1, 2] {
        c.scope(page, fn() {
          viz_mermaid_block(c, "chat/ws1/st1:s-c1/message", "graph TD; A-->B", @sf.theme().p.subtle)
        })
      }
    })
  }, w=390.0, h=700.0, platform=1)
  t.keep_parts(true)
  t.check_looks(false)
  t.draw()
  let views = opened_views(t, 2)
  assert_eq(views.length(), 2, msg="each page has its own Mermaid view")
  assert_true(view_rect(t, views[0]).unwrap().1 != view_rect(t, views[1]).unwrap().1, msg="each view is placed at its own node")
}

///|
test "two copies of a visualization move with their rows while scrolling" {
  new_run()
  let t = @ui.Tester::new(fn(c) {
    @sf.begin(c) |> ignore
    c.with_theme(@sf.ui_theme(), fn() {
      c.list("rows", 6, 160.0, fn(i) {
        c.column(h=Px(160.0), fn() {
          if i == 1 || i == 2 {
            viz_mermaid_block(c, "chat/ws1/st1:s-c1/message", "graph TD; A-->B", @sf.theme().p.subtle)
          } else {
            c.text("row \{i}") |> ignore
          }
        }) |> ignore
      }, h=Px(340.0)) |> ignore
    })
  }, w=390.0, h=340.0, platform=1)
  t.keep_parts(true)
  t.check_looks(false)
  t.draw()
  let views = opened_views(t, 2)
  assert_eq(views.length(), 2)
  let a = view_rect(t, views[0]).unwrap().1
  let b = view_rect(t, views[1]).unwrap().1
  t.wheel(195.0, 180.0, 70.0)
  let next_a = view_rect(t, views[0]).unwrap().1
  let next_b = view_rect(t, views[1]).unwrap().1
  assert_true(next_a < a, msg="the first visualization follows its row")
  assert_eq(next_a - a, next_b - b, msg="both visualizations follow their rows by the same distance")
}

///|
test "a visualization view is reused after its page leaves and all its copies close together" {
  new_run()
  let nav = @ui.Nav::new(0)
  let t = @ui.Tester::new(fn(c) {
    @sf.begin(c) |> ignore
    c.with_theme(@sf.ui_theme(), fn() {
      c.nav(nav, fn(_) {
        viz_mermaid_block(c, "chat/ws1/st1:s-c1/message", "graph TD; A-->B", @sf.theme().p.subtle)
      }) |> ignore
    })
  }, w=390.0, h=700.0, platform=1)
  t.keep_parts(true)
  t.check_looks(false)
  t.draw()
  assert_eq(opened_views(t, 2).length(), 1)
  nav.push(1)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq(opened_views(t, 2).length(), 2)
  t.back()
  t.run_for(@ui.move_most_ms)
  nav.push(2)
  t.draw()
  t.run_for(@ui.move_most_ms)
  let views = opened_views(t, 2)
  assert_eq(views.length(), 2, msg="a page that left releases its view for the next page")
  @sfbase.viz_close("chat/ws1/st1:s-c1/")
  for id in views {
    assert_true(t.views().contains("close \{id}"), msg="closing a chat closes every copy")
  }
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
  // (there on a move from the height it had, as what is over and under it goes with it: rows_steady.mbt)
  t.run_for(@ui.move_most_ms)
  let (_, _, _, h2) = view_rect(t, page).unwrap()
  assert_eq(h2, 232.0)
  t.view_says(page, "{\"emberViz\":true,\"type\":\"height\",\"height\":5000}")
  t.run_for(@ui.move_most_ms)
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
  t.run_for(@ui.move_most_ms)
  // 60 times running it followed, then held
  assert_eq(view_rect(t, page).unwrap().3, 900.0)
  t.view_says(page, "{\"emberViz\":true,\"type\":\"height\",\"height\":2000}")
  t.frame()
  assert_eq(view_rect(t, page).unwrap().3, 900.0)
  t.view_says(page, "{\"emberViz\":true,\"type\":\"height\",\"height\":400}")
  t.run_for(@ui.move_most_ms)
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
  assert_eq(l.state.get(), Some({ "seen": true }))
  let big = "x".repeat(17000)
  t.view_says(page, "{\"emberViz\":true,\"type\":\"state\",\"state\":\"" + big + "\"}")
  t.frame()
  assert_eq(l.state.get(), Some({ "seen": true }))
}

///|
test "words a visualization asks to send go into the composer, said so; the person sends them" {
  let t = chat_tester("chat-viz")
  t.frame()
  let (page, _) = viz_views(t)
  t.view_says(page, "{\"emberViz\":true,\"type\":\"followup\",\"prompt\":\"  把周五的发布挪到周四 \"}")
  t.frame()
  // (left for the chat's composer, whichever frame's: taken as it is next drawn)
  t.frame()
  let d = @sfbase.writings.get("ws1/st1:s-c1").unwrap()
  assert_eq(d.field.text(), "把周五的发布挪到周四")
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
test "the whole window with the window's buttons in the app's top row (a Mac's): the bar every file opened has, clear of them; its way back closes it" {
  new_run()
  let src = fixture("chat-viz")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.set_window_inset(true)
  t.run_for(@ui.move_most_ms)
  viz_open_full("release.html", "ws1/st1", "s-c1", "work/s-c1/release.html", "s-c1")
  t.frame()
  t.frame()
  // (the host's buttons: 16 from the window's left, 54 across: mbui's mac_app.m)
  let name = t.words().filter(fn(w) { w.0 == "release.html" })
  assert_true(name.length() > 0, msg=t.words().map(fn(w) { w.0 }).join("|"))
  let back = t.find(tr("common.back"))
  match back {
    Some((x, _)) => assert_true(x > 16.0 + 54.0, msg="\{x}")
    None => fail("no way back")
  }
  assert_true(name[0].1 > 16.0 + 54.0, msg="\{name[0]}")
  t.tap_text(tr("common.back"))
  t.frame()
  t.frame()
  assert_true(@sfbase.viz_full.get() is None)
}

///|
test "beside: the visualization as a page of its own, served from here with what it kept; nothing else there" {
  let t = chat_tester("chat-viz")
  t.frame()
  let (page, _) = viz_views(t)
  let (x, y, w, h) = view_rect(t, page).unwrap()
  t.tap(x + w - 11.0, y + h + 2.0 + 11.0)
  t.run_for(@ui.move_most_ms)
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
  assert_eq(viz_loads.get(viz_id("ws1/st1", "s-c1", "work/s-c1/release.html")).unwrap().state.get(), Some({ "n": 2 }))
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
  assert_true(doc.contains("--e-canvas:#26272b"))
  assert_true(doc.contains("--e-line:#ececed1f"))
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

///|
test "on the tape what shows of a visualization's page beside the sidebar in use takes the presses there, not the page" {
  new_run()
  let src = fixture("chat-viz")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  // an opened fold's inner screen upright, a finger: laid out Medium
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=690.0, h=840.0, platform=2)
  say_room(t, "medium", "medium")
  t.run_for(@ui.move_most_ms)
  assert_true(@sfdesk.wide.tape)
  let (page, _) = viz_views(t)
  // as tall as it may be: the chat's page under all of what shows of it
  t.view_says(page, "{\"emberViz\":true,\"type\":\"height\",\"height\":5000}")
  t.frame()
  t.frame()
  // the sidebar in use at first, a strip of the page showing beside it
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  let (x, y, w, h) = view_rect(t, page).unwrap()
  let edge = 690.0 - @sfdesk.tape_shows
  assert_true(x + w > edge + 20.0, msg="the page \{x} \{w}, the strip from \{edge}")
  // (in the middle of what the window shows of it)
  let (px, py) = (dmax(x, edge) + 10.0, (dmax(y, 0.0) + dmin(y + h, 840.0)) / 2.0)
  // tapped: the cover's (the chat's page comes over), the page told nothing of it
  t.tap(px, py)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  assert_false(t.views().iter().any(fn(l) { l.has_prefix("finger \{page} ") }))
  // over and in use: the page takes a finger there again
  t.run_for(@ui.move_most_ms)
  let (x, y, w, h) = view_rect(t, page).unwrap()
  t.tap(x + w / 2.0, (dmax(y, 0.0) + dmin(y + h, 840.0)) / 2.0)
  assert_true(t.views().iter().any(fn(l) { l.has_prefix("finger \{page} down") }))
}

///|
test "a page opened over the chat on a wide window shows over the chat's visualization still painted under it, not under it" {
  new_run()
  let src = fixture("chat-viz")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t.frame()
  let (page, _) = viz_views(t)
  assert_true(view_rect(t, page) is Some(_))
  viz_open_full("release.html", "ws1/st1", "s-c1", "work/s-c1/release.html", "s-c1")
  t.frame()
  t.frame()
  let full = opened_views(t, 2)
  let top = full[full.length() - 1]
  assert_true(view_rect(t, top) is Some(_))
  // the chat's page still painted under the one opened over it: the host told to stack that one over it
  assert_true(view_rect(t, page) is Some(_), msg=t.views().join("\n"))
  let raises = t.views().filter(fn(l) { l.has_prefix("raise ") })
  assert_eq(raises.last(), Some("raise \{top}"), msg=t.views().join("\n"))
  let raised_page = raises.search("raise \{page}")
  assert_true(raised_page is Some(_), msg=raises.join(", "))
}

///|
/// Whether something is drawn over view `id`'s hole after it, in the last frame (what covers it), within a pixel (the
/// hole is put on whole pixels).
fn view_covered(t : @ui.Tester, id : Int) -> Bool {
  let hole = match view_rect(t, id) {
    Some(r) => r
    None => return false
  }
  let mut seen = false
  for d in t.drawn_order() {
    if d.0 == 9 && d.1 == hole.0 && d.2 == hole.1 && d.3 == hole.2 && d.4 == hole.3 {
      seen = true
    } else if seen &&
      d.0 == 0 &&
      d.1 <= hole.0 + 1.0 &&
      d.2 <= hole.1 + 1.0 &&
      d.1 + d.3 >= hole.0 + hole.2 - 1.0 &&
      d.2 + d.4 >= hole.1 + hole.3 - 1.0 {
      return true
    }
  }
  false
}

///|
test "a page that said its height stays covered till its host has drawn it (its first frame on the screen)" {
  new_run()
  let src = fixture("chat-viz")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2, finish=false)
  t.run_for(@ui.move_most_ms)
  let (page, _) = viz_views(t)
  assert_true(view_covered(t, page))
  // its height said (its page loaded): still covered, the host not done drawing it
  t.view_says(page, "{\"emberViz\":true,\"type\":\"height\",\"height\":231.4}")
  t.run_for(@ui.move_most_ms)
  assert_eq(view_rect(t, page).unwrap().3, 232.0)
  assert_true(view_covered(t, page))
  // drawn: brought in, as an image is (viz_reveal), then shown as it is
  t.finish(2, page)
  t.frame()
  t.run_for(@sfbase.viz_reveal_ms + 1.0)
  assert_false(view_covered(t, page))
}

///|
test "inline HTML type follows the system font scale without WebKit text inflation" {
  let sizes : Ref[Array[(String, String)]] = Ref([])
  let t = @ui.Tester::new(fn(_) { sizes.val = viz_tokens(false) })
  t.draw()
  let before = sizes.val
  t.set_font_scale(1.5)
  t.draw()
  let body = fn(ts : Array[(String, String)]) {
    ts.filter(fn(p) { p.0 == "--e-text-body" })[0].1
  }
  assert_true(body(before) != body(sizes.val))
  assert_true(viz_document("<p>文字</p>", None, false, 0xFFFFFFFFL).contains("-webkit-text-size-adjust:100%"))
}


///|
test "expanded fragments scroll while their inline copies grow with their content" {
  let content = "<p>用于验证长文档滚动的正文。</p>".repeat(100)
  let inline_doc = viz_document(content, None, false, 0xFFFFFFFFL)
  let full_doc = viz_document(content, None, false, 0xFFFFFFFFL, scroll=true)
  assert_false(inline_doc.contains("<style>html{overflow:auto}</style>"))
  assert_true(full_doc.contains("<style>html{overflow:auto}</style>"))
}

///|
test "inline HTML is set in the faces the app is set in, a face still.fail keeps linked from its stylesheet" {
  new_run()
  // none chosen: the stylesheet's own (no font token at all, an empty one would stand in its place)
  let plain = viz_document("<p>文字</p>", None, false, 0xFFFFFFFFL)
  assert_false(plain.contains("--e-font-body:"))
  assert_false(plain.contains("<link rel=\"stylesheet\""))
  @sfbase.faces_web[@hostapi.face_ui] = ("\"Inter Variable\"", "")
  @sfbase.faces_web[@hostapi.face_text] = ("\"SF LXGW WenKai\"", "https://app.still.fail/releases/fonts/lxgw-wenkai/1.530/font.css")
  @sfbase.faces_web[@hostapi.face_code] = ("\"JetBrains Mono\"", "")
  let doc = viz_document("<p>文字</p>", None, false, 0xFFFFFFFFL)
  assert_true(doc.contains("--e-font-body:\"Inter Variable\", -apple-system"))
  assert_true(doc.contains("--e-font-text:\"SF LXGW WenKai\", -apple-system"))
  assert_true(doc.contains("--e-font-mono:\"JetBrains Mono\", ui-monospace"))
  assert_true(doc.contains("<link rel=\"stylesheet\" href=\"https://app.still.fail/releases/fonts/lxgw-wenkai/1.530/font.css\">"))
  // its origin let in for the stylesheet and the files it names, nothing else of it
  assert_true(doc.contains("fonts.googleapis.com https://app.still.fail;"))
  assert_true(doc.contains("fonts.gstatic.com https://app.still.fail;"))
  new_run()
}

///|
test "an inline page not drawn yet holds its place with a placeholder, gone once it is drawn" {
  new_run()
  let src = fixture("chat-viz")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2, finish=false)
  t.run_for(@ui.move_most_ms)
  let (page, _) = viz_views(t)
  // the line's grey (whatever its breath's alpha), over all its place
  let line = @sf.palette_of(false).line >> 8
  let placeholder = fn() {
    let (x, y, w, h) = view_rect(t, page).unwrap()
    t.drawn_rects().iter().any(fn(r) {
      r.4 >> 8 == line && r.0 <= x + 1.0 && r.1 <= y + 1.0 && r.0 + r.2 >= x + w - 1.0 && r.1 + r.3 >= y + h - 1.0
    })
  }
  assert_true(placeholder())
  t.view_says(page, "{\"emberViz\":true,\"type\":\"height\",\"height\":231.4}")
  t.frame()
  t.frame()
  // its height said, its host not done drawing it: still held
  assert_true(placeholder())
  t.finish(2, page)
  t.frame()
  let began = t.time()
  // half way: what it waited under brushed off it in strips (an image's way in), each its own layer
  t.run_for(@sfbase.viz_reveal_ms / 2.0)
  let greys = fn() { t.drawn_rects().filter(fn(r) { r.4 >> 8 == line }).length() }
  let half = greys()
  // in: nothing over it (the chat's other lines alone)
  t.run_for(began + @sfbase.viz_reveal_ms + 1.0 - t.time())
  assert_true(half > greys() + 1, msg="\{half} \{greys()}")
  assert_false(placeholder())
  assert_false(view_covered(t, page))
}

///|
test "a chat left keeps its pages, as the few left before it: gone back to, they show as they were" {
  let t = chat_tester("chat-viz")
  t.frame()
  let (page, _) = viz_views(t)
  let key = viz_frames.keys().filter(fn(k) { k.has_suffix("/release.html") }).collect()[0]
  let chat = key.unsafe_substring(start=0, end=key.length() - "release.html".length())
  let (station, session) = match chat.unsafe_substring(start=5, end=chat.length() - 1).split(":").collect() {
    [a, .. rest] => (a.to_owned(), rest.map(fn(v) { v.to_owned() }).join(":"))
    _ => abort("no chat in \{key}")
  }
  viz_chat_left(station, session)
  assert_true(viz_frames.contains(key))
  assert_false(t.views().contains("close \{page}"))
  // others left after it: it the oldest of more than are kept, its pages let go
  for i in 0..<@sfbase.viz_chats_kept {
    viz_chat_left("ws1/other", "s-\{i}")
  }
  assert_false(viz_frames.contains(key))
  assert_true(t.views().contains("close \{page}"))
}
