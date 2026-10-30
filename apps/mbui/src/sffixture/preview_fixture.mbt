// The file preview over made-up files (APP=sffix MBUI_FIXTURE=chat-preview-<what>: the first row's chat with a file
// of it open in the preview; scripts/shots.sh preview, web-preview): a picture, a PDF of two pages, a video (whose
// reads are never answered: the player waits, as on a slow link, the same on every run), a song (its reads the same,
// how its player stands pinned), a page of HTML, code,
// Markdown, a table, and a file of no kind that can be shown; a second picture beside the first (the `imageNear` view:
// chat-preview-step with the ways to it, chat-preview-swipe halfway to it under a finger). Its bytes are made here;
// none is a real document.

///|
/// The made-up files, by the name the preview fetches them by: the file as a message has it, and its bytes.
pub fn preview_files() -> Array[(Attachment, () -> Bytes)] {
  let at = fn(name : String, size : Double, w : Double, h : Double) -> Attachment {
    { name, path: "uploads/fx/" + name, size, width: w, height: h, thumbhash: "", owner: "s-c1", upload: "", duration: 0.0, frames: 0, held: false }
  }
  [
    (at("界面草图.png", 18000.0, 600.0, 400.0), fn() { fixture_png(600, 400) }),
    (at("第二版.png", 21000.0, 400.0, 560.0), fn() { fixture_png(400, 560) }),
    // the chat's own picture (chat_fixture.mbt rich_chat), opened from its thumbnail there: the same picture
    (at("compare.png", 402000.0, 1600.0, 900.0), fn() { fixture_file_png("compare.png") }),
    (at("设计说明.pdf", 2400.0, 0.0, 0.0), fn() { fixture_pdf() }),
    // what its message says of it, as the station read it from its header: 12.5 s, 375 frames
    ({ ..at("演示录屏.mp4", 5242880.0, 1280.0, 720.0), duration: 12500.0, frames: 375 }, fn() { b"" }),
    (at("会议录音.m4a", 1489000.0, 0.0, 0.0), fn() { b"" }),
    (at("报告.html", 900.0, 0.0, 0.0), fn() { @utf8.encode(fixture_html) }),
    // the chat's visualization (chat_fixture.mbt MBUI_FIXTURE=chat-viz)
    (at("release.html", 1200.0, 0.0, 0.0), fn() { @utf8.encode(fixture_viz_html) }),
    (at("list.ts", 600.0, 0.0, 0.0), fn() { @utf8.encode(fixture_code) }),
    (at("说明.md", 500.0, 0.0, 0.0), fn() { @utf8.encode(fixture_md) }),
    (at("数据.csv", 200.0, 0.0, 0.0), fn() { @utf8.encode(fixture_csv) }),
    (at("备份.bin", 4096.0, 0.0, 0.0), fn() { Bytes::makei(4096, fn(i) { (i % 7).to_byte() }) }),
    (at("测试版.apk", 8192.0, 0.0, 0.0), fn() { Bytes::makei(8192, fn(i) { (i % 5).to_byte() }) }),
    // the build its agent sent (MBUI_FIXTURE=chat-download, downloads_fixture.mbt): 50 MB as its message says
    (at("发布包.zip", 52428800.0, 0.0, 0.0), fn() { Bytes::makei(4096, fn(i) { (i % 3).to_byte() }) }),
  ]
}

///|
/// MBUI_FIXTURE=chat-preview-<what>: which file opens.
pub fn fixture_preview(mode : String) -> Unit {
  let which = match mode {
    "chat-preview-image" | "chat-preview-step" | "chat-preview-swipe" => "界面草图.png"
    "chat-preview-pdf" => "设计说明.pdf"
    "chat-preview-video" => "演示录屏.mp4"
    "chat-preview-audio" => "会议录音.m4a"
    "chat-preview-html" => "报告.html"
    "chat-preview-code" => "list.ts"
    "chat-preview-md" => "说明.md"
    "chat-preview-csv" => "数据.csv"
    "chat-preview-none" => "备份.bin"
    "chat-preview-apk" => "测试版.apk"
    _ => return
  }
  for f in preview_files() {
    if f.0.name == which {
      open_preview("ws1/st1", "s-c1", f.0, steps=if mode == "chat-preview-image" {
        NoSteps
      } else {
        InChat(Some(1.0), "s-c1")
      })
      if mode == "chat-preview-swipe" {
        pv_strip.pinned = Some(-150.0)
      }
      if viewer.get() is Some(v) {
        // the song paused at 0:31 of 1:35, the same on every run
        if which.has_suffix(".m4a") {
          v.pinned = Some({
            state: 1,
            duration: 95000.0,
            position: 31000.0,
            buffered: 95000.0,
            playing: false,
            buffering: false,
            ended: false,
            width: 0.0,
            height: 0.0,
          })
        }
      }
    }
  }
}

///|
/// What the fixture was asked with bytes, in order: the call and its params.
pub let fix_fetches : Array[(String, Json)] = []

///|
/// What the fixture answers with bytes: a made-up file whole (`station.file`) or a part of it (`station.file.part`;
/// a video's reads never answered).
pub fn fixture_fetch(
  name : String,
  params : Json,
  done : (Result[(Json, Bytes), Json]) -> Unit,
) -> Unit {
  fix_fetches.push((name, params))
  let p = Some(params)
  if name == "file.open" {
    fixture_named(text(p, "path"), p, done)
    return
  }
  let file = text(p, "name")
  let mut found : Bytes? = None
  for f in preview_files() {
    if base_name(f.0.path) == file {
      found = Some((f.1)())
    }
  }
  let bytes = match found {
    Some(b) => b
    None => {
      done(Err({ "code": "not_found", "message": "这份假数据没有 " + file }))
      return
    }
  }
  match name {
    "station.file" => done(Ok(({ "type": "" }, bytes)))
    "station.file.part" => {
      if @sf.lower(file).has_suffix(".mp4") || @sf.lower(file).has_suffix(".m4a") {
        // the player waits on the network
        return
      }
      let from = number(p, "offset").to_int()
      let n = number(p, "length").to_int()
      let from = if from > bytes.length() { bytes.length() } else { from }
      let to = if from + n > bytes.length() { bytes.length() } else { from + n }
      done(Ok(({ "total": Json::number(bytes.length().to_double()) }, Bytes::makei(to - from, fn(i) { bytes[from + i] }))))
    }
    _ => done(Err({ "code": "unknown_call", "message": "这份假数据没有 " + name }))
  }
}

///|
/// A file a message names by its path (`file.open`), as the made-up station reads it: the rich chat's place.mbt, and
/// a long log (`logs/build.log`: a line a step, 600 KB and more); a part of it with `offset`, its whole size `size`.
pub fn fixture_named(path : String, p : Json?, done : (Result[(Json, Bytes), Json]) -> Unit) -> Unit {
  let bytes = match path {
    "src/list/place.mbt" =>
      @utf8.encode(
        "///|\n/// Rows put in before the anchor move it with them.\nfn ListState::moved(self : ListState, at : Int, n : Int) -> Unit {\n  if self.anchor >= at {\n    self.anchor = self.anchor + n\n  }\n}\n",
      )
    "logs/build.log" => fixture_log()
    _ => {
      done(Err({ "code": "http_404", "message": "No such file or directory" }))
      return
    }
  }
  let said : Json = { "name": Json::string(base_name(path)), "path": Json::string(path), "type": "text/plain", "size": Json::number(bytes.length().to_double()) }
  if field(p, "offset") is None && field(p, "length") is None {
    done(Ok((said, bytes)))
    return
  }
  let from = number(p, "offset").to_int()
  let n = number(p, "length").to_int()
  let from = if from > bytes.length() { bytes.length() } else { from }
  let to = if from + n > bytes.length() { bytes.length() } else { from + n }
  done(Ok((said, Bytes::makei(to - from, fn(i) { bytes[from + i] }))))
}

///|
/// The long log: 12000 lines, each saying which it is (and some Chinese, cut across parts' ends).
pub fn fixture_log() -> Bytes {
  let sb = StringBuilder()
  for i in 1..=12000 {
    sb.write_string("[build] 第 \{i} 行：编译 src/module_\{i % 97}.mbt 完成，用时 \{i % 13} ms\n")
  }
  @utf8.encode(sb.to_string())
}

///|
/// A picture of its own: a soft gradient with a few shapes on it, as a sketch of a screen.
pub fn fixture_png(w : Int, h : Int) -> Bytes {
  let rgba = FixedArray::make(w * h * 4, b'\x00')
  for y in 0..<h {
    for x in 0..<w {
      let k = (x + y).to_double() / (w + h - 2).to_double()
      let i = (y * w + x) * 4
      let mut r = 245.0 + (91.0 - 245.0) * k
      let mut g = 243.0 + (123.0 - 243.0) * k
      let mut b = 239.0 + (178.0 - 239.0) * k
      // a bar across the top, a card, a round button
      if y >= 24 && y < 72 && x >= 24 && x < w - 24 {
        r = 255.0
        g = 255.0
        b = 255.0
      }
      if y >= 104 && y < 296 && x >= 48 && x < 312 {
        r = 229.0
        g = 112.0
        b = 74.0
      }
      let dx = (x - 460).to_double()
      let dy = (y - 200).to_double()
      if dx * dx + dy * dy < 60.0 * 60.0 {
        r = 47.0
        g = 143.0
        b = 91.0
      }
      rgba[i] = r.round().to_int().to_byte()
      rgba[i + 1] = g.round().to_int().to_byte()
      rgba[i + 2] = b.round().to_int().to_byte()
      rgba[i + 3] = b'\xFF'
    }
  }
  @pixels.png(w, h, rgba)
}

///|
/// A PDF of two pages (US Letter), shapes and a few lines in Helvetica, its cross-reference table counted exactly.
pub fn fixture_pdf() -> Bytes {
  let page1 =
    #|0.898 0.439 0.290 rg 56 680 500 56 re f
    #|BT /F1 28 Tf 1 1 1 rg 72 700 Td (Design notes) Tj ET
    #|0.141 0.153 0.169 rg
    #|BT /F1 14 Tf 72 620 Td (1. The list keeps its rows by their real heights.) Tj ET
    #|BT /F1 14 Tf 72 596 Td (2. Pictures load at the size they are shown.) Tj ET
    #|0.906 0.890 0.863 rg 72 300 468 240 re f
    #|0.357 0.482 0.698 rg 96 330 180 180 re f
    #|0.184 0.561 0.357 rg 320 420 190 30 re f
    #|BT /F1 12 Tf 0.4 0.4 0.4 rg 72 60 Td (Page 1 of 2) Tj ET
  let page2 =
    #|0.141 0.153 0.169 rg
    #|BT /F1 22 Tf 72 700 Td (Checklist) Tj ET
    #|BT /F1 14 Tf 72 650 Td (- Version and notes) Tj ET
    #|BT /F1 14 Tf 72 626 Td (- Both packages signed) Tj ET
    #|BT /F1 14 Tf 72 602 Td (- New screenshots) Tj ET
    #|0.898 0.439 0.290 rg 72 520 468 4 re f
    #|BT /F1 12 Tf 0.4 0.4 0.4 rg 72 60 Td (Page 2 of 2) Tj ET
  let objs = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 7 0 R >> >> /Contents 4 0 R >>",
    "<< /Length \{page1.length()} >>\nstream\n" + page1 + "\nendstream",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 7 0 R >> >> /Contents 6 0 R >>",
    "<< /Length \{page2.length()} >>\nstream\n" + page2 + "\nendstream",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
  ]
  let sb = StringBuilder()
  sb.write_string("%PDF-1.4\n")
  let mut at = 9
  let offsets = []
  for i, o in objs {
    offsets.push(at)
    let s = "\{i + 1} 0 obj\n" + o + "\nendobj\n"
    sb.write_string(s)
    at = at + s.length()
  }
  sb.write_string("xref\n0 \{objs.length() + 1}\n0000000000 65535 f \n")
  for o in offsets {
    let d = "\{o}"
    sb.write_string("0000000000".view(end_offset=10 - d.length()).to_owned() + d + " 00000 n \n")
  }
  sb.write_string("trailer\n<< /Size \{objs.length() + 1} /Root 1 0 R >>\nstartxref\n\{at}\n%%EOF\n")
  @utf8.encode(sb.to_string())
}

///|
pub let fixture_html : String =
  #|<!doctype html>
  #|<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
  #|<style>
  #|body { margin: 0; padding: 20px; font-family: system-ui, sans-serif; color: #24272b; background: #fff; }
  #|h1 { font-size: 22px; margin: 0 0 12px; }
  #|.card { background: #fbe6dc; border-radius: 12px; padding: 14px; margin: 12px 0; }
  #|.bar { height: 10px; border-radius: 5px; background: #e5704a; margin: 6px 0; }
  #|</style></head>
  #|<body>
  #|<h1>周报草稿</h1>
  #|<p>这是一页做测试用的网页，里面的脚本会写下一行字。</p>
  #|<div class="card"><div class="bar" style="width:80%"></div><div class="bar" style="width:55%"></div><div class="bar" style="width:30%"></div></div>
  #|<p id="n">脚本还没有运行</p>
  #|<script>document.getElementById('n').textContent = '脚本已运行：' + (6 * 7);</script>
  #|</body></html>

///|
pub let fixture_code : String =
  #|// 列表的行按真实高度排，没量过的先按估计的高度占位
  #|export function moved(rows: number[], at: number, n: number): number[] {
  #|  const out = rows.slice(0, at);
  #|  for (let i = 0; i < n; i++) out.push(-1);
  #|  return out.concat(rows.slice(at));
  #|}
  #|
  #|export const estimate = 66;

///|
pub let fixture_md : String =
  #|# 发布前要做的
  #|
  #|- 版本号和更新说明
  #|- 安卓和 mac 的包都签名
  #|- 截图换成**新的**
  #|
  #|> 第二屏的插画再小一点。
  #|
  #|`scripts/shots.sh` 会把新截图和旧的比一遍。

///|
pub let fixture_csv : String =
  #|名字,平台,帧时间（毫秒）,通过
  #|首页,安卓,0.42,是
  #|聊天,安卓,0.57,是
  #|聊天,mac,0.31,是
  #|"设置, 外观",web,0.66,否

///|
/// The `imageNear` view of the made-up chat: 界面草图.png has 第二版.png after it, the first of the two.
pub fn fixture_image_near(params : Map[String, Json]) -> Json? {
  match params.get("path") {
    Some(String("uploads/fx/界面草图.png")) =>
      Some({
        "index": 0,
        "count": 2,
        "after": {
          "name": "第二版.png",
          "path": "uploads/fx/第二版.png",
          "size": 21000,
          "width": 400,
          "height": 560,
          "owner": "s-c1",
        },
      })
    Some(String("uploads/fx/第二版.png")) =>
      Some({
        "index": 1,
        "count": 2,
        "before": {
          "name": "界面草图.png",
          "path": "uploads/fx/界面草图.png",
          "size": 18000,
          "width": 600,
          "height": 400,
          "owner": "s-c1",
        },
      })
    _ => Some(Json::object({}))
  }
}
