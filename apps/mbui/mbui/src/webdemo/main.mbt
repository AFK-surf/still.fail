// Web pages in native views (native.mbt), side by side: a page of HTML (kind 2), clipped by the box it is in, and a
// site whose every request the app answers (kind 3: its page, a stylesheet, a script, a picture, and a POST the script
// makes with a body), with a badge painted over it. Where the host has no such view (or its web engine is missing),
// each says so in its place. For the hosts' screenshots: `APP=webdemo scripts/win.sh shot`, `scripts/mac.sh`.

///|
let page_html : String =
  #|<!doctype html><meta charset="utf-8">
  #|<style>
  #|  body { margin: 0; font: 15px/1.5 "Segoe UI", -apple-system, sans-serif; color: #1d1d1f; }
  #|  header { padding: 18px 20px; color: white; background: linear-gradient(135deg, #3a6df0, #8a3af0); }
  #|  h1 { margin: 0; font-size: 22px; }
  #|  p { margin: 12px 20px; }
  #|  .row { display: flex; gap: 8px; margin: 0 20px; }
  #|  .row div { flex: 1; height: 48px; border-radius: 10px; }
  #|  .tall { height: 300px; margin: 16px 20px; border-radius: 12px; background: repeating-linear-gradient(0deg, #f2f2f7 0 20px, #e5e5ea 20px 40px); }
  #|</style>
  #|<header><h1>一段 HTML</h1>kind 2，脚本开着</header>
  #|<p id="js">脚本没跑</p>
  #|<div class="row"><div style="background:#ff9f0a"></div><div style="background:#30d158"></div><div style="background:#64d2ff"></div></div>
  #|<p>这一页比框高，下面被框裁掉。</p>
  #|<div class="tall"></div>
  #|<script>document.getElementById("js").textContent = "脚本跑了：" + (6 * 7);</script>

///|
let site_index : String =
  #|<!doctype html><meta charset="utf-8">
  #|<title>app 回答的站点</title>
  #|<link rel="stylesheet" href="/style.css">
  #|<h1>app 回答的站点</h1>
  #|<p>这一页、样式、脚本、图都是 app 经 view_site_* 回答的。</p>
  #|<p><img src="/dot.svg" width="64" height="64" alt="dot"></p>
  #|<p id="echo">POST 还没回</p>
  #|<script src="/app.js"></script>

///|
let site_css : String =
  #|body { margin: 0; padding: 16px 20px; font: 15px/1.5 "Segoe UI", -apple-system, sans-serif; background: #fff8e6; color: #3d2f00; }
  #|h1 { margin: 0 0 8px; font-size: 22px; color: #b25000; }
  #|#echo { padding: 8px 12px; border-radius: 8px; background: #ffe2a8; }

///|
let site_js : String =
  #|var x = new XMLHttpRequest();
  #|x.open("POST", "/api/echo", false);
  #|x.setRequestHeader("Content-Type", "text/plain");
  #|x.send("ping-42");
  #|document.getElementById("echo").textContent = "POST 回来了：" + x.status + " " + x.responseText;

///|
let site_svg : String =
  #|<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><circle cx="32" cy="32" r="28" fill="#ff6a00"/><circle cx="32" cy="32" r="12" fill="#fff"/></svg>

///|
let page_view : Ref[@ui.NativeView?] = Ref(None)

///|
let site_view : Ref[@ui.NativeView?] = Ref(None)

///|
/// The requests the site's page made, as the app saw them.
let served : Array[String] = []

///|
fn answer(reply : @ui.SiteReply, status : Int, kind : String, body : String) -> Unit {
  reply.head(status, [("Content-Type", kind), ("Cache-Control", "no-store")])
  reply.chunk(@utf8.encode(body))
  reply.end()
}

///|
fn serve(req : @ui.SiteRequest, reply : @ui.SiteReply) -> Unit {
  served.push("\{req.verb} \{req.path}")
  @hostapi.log("webdemo: site asked \{req.verb} \{req.path} (page \{req.page}, body \{req.body.length()} bytes)")
  match req.path {
    "/" => answer(reply, 200, "text/html; charset=utf-8", site_index)
    "/style.css" => answer(reply, 200, "text/css; charset=utf-8", site_css)
    "/app.js" => answer(reply, 200, "text/javascript; charset=utf-8", site_js)
    "/dot.svg" => answer(reply, 200, "image/svg+xml", site_svg)
    "/api/echo" => {
      let got = @utf8.decode_lossy(req.body[:])
      answer(reply, 200, "text/plain; charset=utf-8", "app 收到 \{req.body.length()} 字节「\{got}」")
    }
    _ => answer(reply, 404, "text/plain; charset=utf-8", "没有 \{req.path}")
  }
}

///|
fn once(cell : Ref[@ui.NativeView?], make : () -> @ui.NativeView) -> @ui.NativeView {
  match cell.val {
    Some(v) => v
    None => {
      let v = make()
      cell.val = Some(v)
      v
    }
  }
}

///|
fn state_word(v : @ui.NativeView) -> String {
  match v.state() {
    n if n < 0 => "无法显示"
    1 => "已加载"
    _ => "加载中"
  }
}

///|
/// A pane: its name and how its view stands over the view, or the words saying it cannot be shown.
fn pane(c : @ui.Ctx, title : String, v : @ui.NativeView, body : () -> Unit) -> Unit {
  c.box(w=Fill(1.0), h=Fill(1.0), gap=8.0, fn() {
    c.text("\{title}：\{state_word(v)}", size=14.0, weight=600, wrap=false) |> ignore
    c.box(
      w=Fill(1.0),
      h=Fill(1.0),
      radius=10.0,
      border=1.0,
      border_color=0xC7C7CCFFL,
      bg=0xF2F2F7FFL,
      clip=true,
      fn() {
        if v.state() < 0 {
          c.box(w=Fill(1.0), h=Fill(1.0), align=ACenter, justify=JCenter, fn() {
            c.text("无法显示", size=18.0, weight=600, color=0x8E8E93FFL, wrap=false) |> ignore
          })
          |> ignore
        } else {
          body()
        }
      },
    )
    |> ignore
  })
  |> ignore
}

///|
fn view(c : @ui.Ctx) -> Unit {
  let page = once(page_view, fn() { @ui.NativeView::page(page_html) })
  let site = once(site_view, fn() {
    @ui.NativeView::site("/", serve, leave=fn(url) { @hostapi.log("webdemo: link left by to \{url}") })
  })
  c.box(w=Fill(1.0), h=Fill(1.0), bg=0xFFFFFFFFL, pad=20.0, gap=12.0, fn() {
    c.text("网页视图", size=22.0, weight=700, wrap=false) |> ignore
    c.text(
      "app 回答了 \{served.length()} 个请求：\{served.join("，")}",
      size=13.0,
      color=0x636366FFL,
    )
    |> ignore
    c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), gap=16.0, fn() {
      pane(c, "HTML", page, fn() {
        // taller than its box: the box clips it
        c.native(page, h=Px(640.0)) |> ignore
      })
      pane(c, "站点", site, fn() {
        c.native(site) |> ignore
        // painted after the view: over it
        c.layer(pad=12.0, align=AEnd, fn() {
          c.box(padx=10.0, pady=6.0, radius=8.0, bg=0x1C1C1EE6L, fn() {
            c.text("画在网页上面", size=13.0, color=0xFFFFFFFFL, wrap=false) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
    })
    |> ignore
  })
  |> ignore
}

///|
fn main {
  @hostapi.window_setup(640.0, 480.0, 900.0, 640.0)
  @ui.run("mbui web views", view)
}
