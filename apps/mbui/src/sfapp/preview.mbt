// A file of a chat opened over the whole screen (ember apps/android chat/screens/FilePreview.kt, VideoViewer.kt,
// FileKinds.kt kindOf, ChatFiles.kt FileData; web/src/FilePreview.tsx): images to zoom (a double tap, the bar's − and
// +, the wheel) and pan; videos played by the system's player (a native view over the canvas, src/ui/native.mbt), its
// bytes read through the core a part at a time (`station.file.part`); PDFs drawn by the system page by page; HTML in a
// page of its own (a native web view: its scripts on, nothing of the app's reachable); Markdown rendered; CSV as a
// table; code and text as they are. Anything else says it cannot be shown and offers the download. One bar floats at
// the top with its name and tools and fades when left alone; a tap brings it back. Back (or ×) closes it.
//
// Not yet, against the Android app: the flight from the chat's thumbnail and back (it fades in and out, as the
// Android app does when the thumbnail is not on the screen), stepping through the chat's images (`imageNear`),
// pinching on iOS (no second finger told there yet), marking an image (ImageMarks.kt), a video's frame-exact steps (its frames' times
// read by MediaExtractor: here steps of a guessed 60 fps), saving a frame and turning to landscape, code
// highlighting, a code file's sideways scroll, installing an APK, the frosted glass (the bars are a solid tint: a
// native view under them cannot be blurred, and the canvas's blur is another slice's).

///|
/// The words this page adds (client/i18n/catalog/zh android-chat.json, common.json).
let pv_zh : Map[String, String] = {
  "android-chat.file.cantPreview": "此文件类型不支持预览",
  "android-chat.file.cut": "文件较大，仅显示前 {size}，完整内容请下载",
  "android-chat.file.cut.rows": "仅显示前 {n} 行，完整内容请下载",
  "android-chat.file.download": "下载",
  "android-chat.file.image.failed": "此图片无法在此显示",
  "android-chat.file.loadFailed": "无法读取：{error}",
  "android-chat.file.loading.size": "正在读取 {size}",
  "android-chat.file.pdf.failed": "无法打开此 PDF：{error}",
  "android-chat.file.saveFailed": "下载失败",
  "android-chat.file.saved": "已保存到「下载」",
  "android-chat.file.tab.preview": "预览",
  "android-chat.file.tab.source": "源码",
  "android-chat.file.tooBigToShow": "文件过大，无法在此显示，下载后可打开",
  "android-chat.file.zoomIn": "放大",
  "android-chat.file.zoomOut": "缩小",
  "android-chat.video.failed": "无法播放此视频",
  "android-chat.video.frames": "{at} / {n} 帧",
  "android-chat.video.next": "下一帧",
  "android-chat.video.pause": "暂停",
  "android-chat.video.play": "播放",
  "android-chat.video.prev": "上一帧",
  "android-chat.video.playFailed": "播放失败",
  "common.close": "关闭",
  "common.reading": "正在读取",
  "common.opening": "正在打开",
}

///|
fn pv(key : String) -> String {
  match pv_zh.get(key) {
    Some(s) => s
    None => tr(key)
  }
}

///|
fn pv_fill(key : String, args : Array[(String, String)]) -> String {
  let mut s = pv(key)
  for a in args {
    s = s.replace_all(old="{" + a.0 + "}", new=a.1)
  }
  s
}

// ── what a file is (FileKinds.kt kindOf) ───────────────────────────────

///|
priv enum PKind {
  KImage
  KVideo
  KAudio
  KPdf
  KMarkdown
  KCsv
  KHtml
  KCode
  KText
} derive(Eq)

///|
/// What a file shows as by its name: its kind (None: look at its bytes), its type, its language (code).
fn preview_kind(name : String) -> (PKind?, String, String) {
  let lower = lower(name)
  match lower {
    "dockerfile" => return (Some(KCode), "text/plain", "docker")
    "makefile" => return (Some(KCode), "text/plain", "make")
    "cmakelists.txt" => return (Some(KCode), "text/plain", "cmake")
    _ => ()
  }
  let ext = match lower.rev_find(".") {
    Some(i) if i > 0 => lower.view(start_offset=i + 1).to_owned()
    _ => ""
  }
  let media : (PKind, String)? = match ext {
    "png" => Some((KImage, "image/png"))
    "jpg" | "jpeg" => Some((KImage, "image/jpeg"))
    "gif" => Some((KImage, "image/gif"))
    "webp" => Some((KImage, "image/webp"))
    "svg" => Some((KImage, "image/svg+xml"))
    "avif" => Some((KImage, "image/avif"))
    "bmp" => Some((KImage, "image/bmp"))
    "ico" => Some((KImage, "image/x-icon"))
    "mp4" | "m4v" => Some((KVideo, "video/mp4"))
    "webm" => Some((KVideo, "video/webm"))
    "mov" => Some((KVideo, "video/quicktime"))
    "ogv" => Some((KVideo, "video/ogg"))
    "mp3" => Some((KAudio, "audio/mpeg"))
    "m4a" => Some((KAudio, "audio/mp4"))
    "aac" => Some((KAudio, "audio/aac"))
    "wav" => Some((KAudio, "audio/wav"))
    "ogg" | "oga" | "opus" => Some((KAudio, "audio/ogg"))
    "flac" => Some((KAudio, "audio/flac"))
    "pdf" => Some((KPdf, "application/pdf"))
    "md" | "markdown" => Some((KMarkdown, "text/markdown"))
    "csv" => Some((KCsv, "text/csv"))
    "tsv" => Some((KCsv, "text/tab-separated-values"))
    "html" | "htm" => Some((KHtml, "text/html"))
    _ => None
  }
  match media {
    Some((k, t)) => return (Some(k), t, if k == KHtml { "html" } else { "" })
    None => ()
  }
  if ["txt", "text", "log", "out", "err", "lock"].contains(ext) {
    return (Some(KText), "text/plain", "")
  }
  let language = match ext {
    "mjs" | "cjs" => "js"
    "mts" | "cts" => "ts"
    "h" => "c"
    "hh" | "hpp" | "cc" | "cxx" => "cpp"
    "kts" => "kotlin"
    "yml" => "yaml"
    "zsh" | "sh" => "bash"
    "patch" => "diff"
    "conf" | "cfg" => "ini"
    "env" => "dotenv"
    "gradle" => "groovy"
    "plist" | "svg" => "xml"
    e => e
  }
  if code_languages.contains(language) {
    return (Some(KCode), "text/plain", language)
  }
  (None, "application/octet-stream", "")
}

///|
let code_languages : Array[String] = [
  "ts", "tsx", "js", "jsx", "json", "jsonc", "json5", "py", "rs", "go", "java", "kt",
  "swift", "c", "cpp", "cs", "rb", "php", "bash", "fish", "ps1", "yaml", "toml", "xml",
  "sql", "css", "scss", "less", "html", "vue", "svelte", "lua", "dart", "diff", "ini",
  "dotenv", "groovy", "scala", "r", "pl", "ex", "exs", "erl", "hs", "ml", "clj", "zig",
  "nim", "proto", "graphql", "tex", "vim", "nix", "tf", "hcl", "docker", "make", "cmake",
  "asm", "wasm", "sol", "prisma", "astro", "mbt",
]

// ── the viewer's state ─────────────────────────────────────────────────

///|
/// Over this a file is not read into memory to be shown (ChatFiles.kt BIG_FILE); above SHOW_LIMIT only its start
/// shows as text; a table shows TABLE_ROWS rows at most.
let big_file : Double = 16.0 * 1024.0 * 1024.0

///|
let show_limit : Int = 2 * 1024 * 1024

///|
let table_rows : Int = 2000

///|
/// The bars fade after this long left alone; after a tap that brought them back, a while longer.
let rest_ms : Double = 2000.0

///|
let tap_rest_ms : Double = 4000.0

///|
/// Dark whatever the theme, as a viewer of pictures: its text, what is quieter, its canvas.
let dark_text : Int64 = 0xF4F4F5FFL

///|
let dark_muted : Int64 = 0xFFFFFF99L

///|
/// Where a picture shows in its stage (Zoom.kt ZoomState): `scale` is points per picture pixel (1 = 100%), x and y
/// move its centre from the stage's.
priv struct Zoom {
  mut nw : Double
  mut nh : Double
  mut bw : Double
  mut bh : Double
  mut scale : Double
  mut x : Double
  mut y : Double
  mut fitted : Bool
  // a glide (260 ms on (0.16, 1, 0.3, 1)): when it started (-1: none), from, to
  mut g0 : Double
  g_from : FixedArray[Double]
  g_to : FixedArray[Double]
}

///|
fn Zoom::new() -> Zoom {
  {
    nw: 0.0,
    nh: 0.0,
    bw: 0.0,
    bh: 0.0,
    scale: 1.0,
    x: 0.0,
    y: 0.0,
    fitted: true,
    g0: -1.0,
    g_from: FixedArray::make(3, 0.0),
    g_to: FixedArray::make(3, 0.0),
  }
}

///|
let max_scale : Double = 16.0

///|
fn Zoom::margin(self : Zoom) -> Double {
  if self.bw < 640.0 {
    12.0
  } else {
    32.0
  }
}

///|
/// Fitted: the whole picture within the stage (a margin round it), never enlarged.
fn Zoom::fit(self : Zoom) -> Double {
  if self.nw <= 0.0 || self.nh <= 0.0 || self.bw <= 0.0 || self.bh <= 0.0 {
    return 1.0
  }
  let m = self.margin()
  dmin(1.0, dmin((self.bw - 2.0 * m) / self.nw, (self.bh - 2.0 * m) / self.nh))
}

///|
fn Zoom::min_scale(self : Zoom) -> Double {
  dmin(self.fit(), 1.0) / 2.0
}

///|
fn Zoom::zoomed(self : Zoom) -> Bool {
  self.scale > self.fit() * 1.01
}

///|
fn Zoom::natural(self : Zoom, w : Double, h : Double) -> Unit {
  if w == self.nw && h == self.nh {
    return
  }
  self.nw = w
  self.nh = h
  if self.fitted {
    self.scale = self.fit()
    self.x = 0.0
    self.y = 0.0
  } else {
    self.clamp()
  }
}

///|
fn Zoom::boxed(self : Zoom, w : Double, h : Double) -> Unit {
  if w == self.bw && h == self.bh {
    return
  }
  self.bw = w
  self.bh = h
  if self.fitted {
    self.scale = self.fit()
    self.x = 0.0
    self.y = 0.0
  } else {
    self.clamp()
  }
}

///|
fn Zoom::clamp(self : Zoom) -> Unit {
  if self.nw <= 0.0 {
    return
  }
  self.scale = dmax(self.min_scale(), dmin(max_scale, self.scale))
  let sx = dmax(0.0, (self.nw * self.scale - self.bw) / 2.0)
  let sy = dmax(0.0, (self.nh * self.scale - self.bh) / 2.0)
  self.x = dmax(-sx, dmin(sx, self.x))
  self.y = dmax(-sy, dmin(sy, self.y))
}

///|
/// The picture's place on the stage (x, y, w, h), once its size is known.
fn Zoom::rect(self : Zoom) -> (Double, Double, Double, Double)? {
  if self.nw <= 0.0 || self.nh <= 0.0 {
    return None
  }
  let w = self.nw * self.scale
  let h = self.nh * self.scale
  Some((self.bw / 2.0 + self.x - w / 2.0, self.bh / 2.0 + self.y - h / 2.0, w, h))
}

///|
/// Moved by a finger (dx, dy), a glide called off.
fn Zoom::pan(self : Zoom, dx : Double, dy : Double) -> Unit {
  self.g0 = -1.0
  self.fitted = false
  self.x = self.x + dx
  self.y = self.y + dy
  self.clamp()
}

///|
/// By `zoom` around (ax, ay) on the stage, and moved by (dx, dy): two fingers pinching (Zoom.kt transform).
fn Zoom::transform(self : Zoom, ax : Double, ay : Double, zoom : Double, dx : Double, dy : Double) -> Unit {
  self.g0 = -1.0
  let next = dmax(self.min_scale(), dmin(max_scale, self.scale * zoom))
  let f = next / self.scale
  let px = ax - self.bw / 2.0
  let py = ay - self.bh / 2.0
  self.fitted = false
  self.scale = next
  self.x = px - (px - self.x) * f + dx
  self.y = py - (py - self.y) * f + dy
  self.clamp()
}

///|
/// To `target` (at once, or gliding from `now`), the picture's point under (ax, ay) on the stage staying put.
fn Zoom::zoom_to(self : Zoom, target : Double, ax : Double, ay : Double, now : Double, glide : Bool) -> Unit {
  let next = dmax(self.min_scale(), dmin(max_scale, target))
  let px = ax - self.bw / 2.0
  let py = ay - self.bh / 2.0
  let f = next / self.scale
  let mut tx = px - (px - self.x) * f
  let mut ty = py - (py - self.y) * f
  let sx = dmax(0.0, (self.nw * next - self.bw) / 2.0)
  let sy = dmax(0.0, (self.nh * next - self.bh) / 2.0)
  tx = dmax(-sx, dmin(sx, tx))
  ty = dmax(-sy, dmin(sy, ty))
  self.fitted = false
  self.glide(next, tx, ty, now, glide)
}

///|
fn Zoom::reset(self : Zoom, now : Double) -> Unit {
  self.glide(self.fit(), 0.0, 0.0, now, true)
  self.fitted = true
}

///|
fn Zoom::glide(self : Zoom, s : Double, x : Double, y : Double, now : Double, glide : Bool) -> Unit {
  if !glide {
    self.g0 = -1.0
    self.scale = s
    self.x = x
    self.y = y
    return
  }
  self.g_from[0] = self.scale
  self.g_from[1] = self.x
  self.g_from[2] = self.y
  self.g_to[0] = s
  self.g_to[1] = x
  self.g_to[2] = y
  self.g0 = now
}

///|
/// A glide's step; true while it goes on.
fn Zoom::step(self : Zoom, now : Double) -> Bool {
  if self.g0 < 0.0 {
    return false
  }
  let t = dmin(1.0, (now - self.g0) / 260.0)
  let e = @ui.bezier(0.16, 1.0, 0.3, 1.0, t)
  self.scale = self.g_from[0] + (self.g_to[0] - self.g_from[0]) * e
  self.x = self.g_from[1] + (self.g_to[1] - self.g_from[1]) * e
  self.y = self.g_from[2] + (self.g_to[2] - self.g_from[2]) * e
  if t >= 1.0 {
    self.g0 = -1.0
    return false
  }
  true
}

///|
/// A double tap: fitted, in to 2.5× the fitted size (at least 100%) around it; zoomed, back to fitted.
fn Zoom::double_tap(self : Zoom, ax : Double, ay : Double, now : Double) -> Unit {
  if self.zoomed() {
    self.reset(now)
  } else {
    self.zoom_to(dmax(self.fit() * 2.5, 1.0), ax, ay, now, true)
  }
}

///|
/// The file open, and how far it has got.
priv struct Viewer {
  station : String
  /// the session that keeps it
  key : String
  file : Attachment
  /// its name at the station (the last part of its path)
  name : String
  /// a file of a station's drive (open_file), read by `drive.read`; None: a chat's, read by `station.file`
  drive : DriveFile?
  kind : PKind?
  mime : String
  /// a file of no known kind: text (its first bytes UTF-8, no NULs)? None while asked
  mut sniffed : Bool?
  mut sniffing : Bool
  mut bytes : Bytes?
  mut fetching : Bool
  mut error : String?
  /// a file told of (not shown): asked for (to save)
  mut asked : Bool
  mut save_after : Bool
  /// the bars shown, and when they go
  mut awake : Bool
  mut rest_at : Double
  /// whether they fade when left alone after it opens (not in the fixture's shots, which come when they come)
  mut rests : Bool
  zoom : Zoom
  vzoom : Zoom
  /// 源码 rather than 预览
  mut source : Bool
  mut video : @ui.NativeView?
  mut page : @ui.NativeView?
  mut pdf : @ui.Pdf?
  mut text : String?
  /// the image's key once its bytes are given
  mut image : String
  mut opened : Double
  mut closing : Double
  // a finger on the stage: where it was last frame, how far it has gone, the last tap (time, where)
  mut held : Bool
  mut last_x : Double
  mut last_y : Double
  mut moved : Double
  mut tap_at : Double
  mut tap_x : Double
  mut tap_y : Double
  // two fingers: how far apart and where between them last frame (0: none), whether this press pinched
  mut pinch_d : Double
  mut pinch_x : Double
  mut pinch_y : Double
  mut pinched : Bool
  /// the video's speed
  mut rate : Double
  /// a read of the video's file, logged the first times
  mut reads : Int
  /// how a song's player stands, pinned for a fixture's shot
  mut pinned : @player.Status?
}

///|
let viewer : Ref[Viewer?] = { val: None }

///|
/// Opens `a` of the chat on `station` (kept by the session `key`) over everything.
fn open_preview(station : String, key : String, a : Attachment, drive? : DriveFile? = None) -> Unit {
  close_now()
  let (kind, mime, _) = preview_kind(a.name)
  viewer.val = Some({
    station,
    key,
    file: a,
    name: base_name(a.path),
    drive,
    kind,
    mime,
    sniffed: None,
    sniffing: false,
    bytes: None,
    fetching: false,
    error: None,
    asked: false,
    save_after: false,
    awake: true,
    rest_at: -1.0,
    rests: true,
    zoom: Zoom::new(),
    vzoom: Zoom::new(),
    source: false,
    video: None,
    page: None,
    pdf: None,
    text: None,
    image: "",
    opened: -1.0,
    closing: -1.0,
    held: false,
    last_x: 0.0,
    last_y: 0.0,
    moved: 0.0,
    tap_at: -1.0e9,
    tap_x: 0.0,
    tap_y: 0.0,
    pinch_d: 0.0,
    pinch_x: 0.0,
    pinch_y: 0.0,
    pinched: false,
    rate: 1.0,
    reads: 0,
    pinned: None,
  })
}

///|
/// The viewer gone at once, what it holds let go (its player stopped, its page and PDF closed).
fn close_now() -> Unit {
  match viewer.val {
    Some(v) => {
      match v.video {
        Some(n) => n.close()
        None => ()
      }
      match v.page {
        Some(n) => n.close()
        None => ()
      }
      match v.pdf {
        Some(p) => p.close()
        None => ()
      }
      viewer.val = None
    }
    None => ()
  }
}

///|
/// Whether a viewer is open (the page under it takes no keys).
pub fn preview_open() -> Bool {
  viewer.val is Some(_)
}

///|
/// The kind it shows as, once known.
fn Viewer::shown_kind(self : Viewer) -> PKind? {
  match self.kind {
    Some(k) => Some(k)
    None =>
      match self.sniffed {
        Some(true) => Some(KText)
        _ => None
      }
  }
}

///|
/// Told of (its name, size and kind) rather than shown: of no kind it has a viewer for, or too big to read.
fn Viewer::told_of(self : Viewer) -> Bool {
  match self.shown_kind() {
    Some(KVideo) | Some(KAudio) | Some(KPdf) => false
    None => self.kind is None && self.sniffed is Some(_)
    Some(_) => self.file.size > big_file
  }
}

///|
fn Viewer::dark(self : Viewer) -> Bool {
  match self.shown_kind() {
    Some(KImage) | Some(KVideo) => true
    _ => false
  }
}

// ── reading it through the core ────────────────────────────────────────

///|
fn file_params(v : Viewer) -> Map[String, Json] {
  {
    "station": Json::string(v.station),
    "key": Json::string(v.key),
    "name": Json::string(v.name),
  }
}

///|
/// The call a part of it is read by: a chat's file `station.file.part`, a drive's `drive.read`.
fn Viewer::part_call(self : Viewer) -> String {
  if self.drive is Some(_) {
    "drive.read"
  } else {
    "station.file.part"
  }
}

///|
/// `length` bytes of it from `offset` (fewer at its end), and its whole size as the station says (in the answer's
/// `total`).
fn Viewer::read_part(
  self : Viewer,
  src : Source,
  offset : Double,
  length : Int,
  done : (Result[(Json, Bytes), Json]) -> Unit,
) -> Unit {
  let p = match self.drive {
    Some(d) =>
      {
        "station": Json::string(d.station),
        "root": Json::string(d.root),
        "path": Json::string(d.path),
      }
    None => file_params(self)
  }
  p["offset"] = Json::number(offset)
  p["length"] = Json::number(length.to_double())
  (src.read_bytes)(self.part_call(), Json::object(p), done)
}

///|
/// The whole of it: a chat's in one `station.file`; a drive's a part (4 MB) at a time, as its reader reads.
fn Viewer::read_whole(self : Viewer, src : Source, done : (Result[Bytes, Json]) -> Unit) -> Unit {
  match self.drive {
    None =>
      (src.read_bytes)("station.file", Json::object(file_params(self)), fn(r) {
        match r {
          Ok((_, bytes)) => done(Ok(bytes))
          Err(e) => done(Err(e))
        }
      })
    Some(_) => {
      let parts : Array[Bytes] = []
      let got : Ref[Int] = { val: 0 }
      fn next() {
        self.read_part(src, got.val.to_double(), drive_part, fn(r) {
          match r {
            Ok((answer, bytes)) => {
              let total = match field(Some(answer), "total") {
                Some(Number(n, ..)) => n.to_int()
                _ => got.val + bytes.length()
              }
              parts.push(bytes)
              got.val += bytes.length()
              if bytes.length() == 0 || got.val >= total {
                let all = Buffer(size_hint=got.val)
                for b in parts {
                  all.write_bytes(b)
                }
                done(Ok(all.to_bytes()))
              } else {
                next()
              }
            }
            Err(e) => done(Err(e))
          }
        })
      }
      next()
    }
  }
}

///|
/// What has to be asked of the core this frame: a file of no known kind's first bytes, the whole of one to show, a
/// video's player.
fn Viewer::fetch(self : Viewer, c : @ui.Ctx, src : Source) -> Unit {
  let v = self
  if v.kind is None && v.sniffed is None && !v.sniffing {
    v.sniffing = true
    v.read_part(src, 0.0, 8192, fn(r) {
      v.sniffing = false
      v.sniffed = Some(
        match r {
          Ok((_, bytes)) => looks_like_text(bytes)
          // a station from before parts cannot say: told of, as anything else not shown
          Err(_) => false
        },
      )
    })
    return
  }
  match v.shown_kind() {
    Some(KVideo) | Some(KAudio) => {
      if v.video is None {
        let n = @ui.NativeView::video(v.mime, fn(offset, length, answer) {
          v.read_part(src, offset, length, fn(r) {
            match r {
              Ok((answer_json, bytes)) => {
                let total = match field(Some(answer_json), "total") {
                  Some(Number(t, ..)) => t
                  _ => -1.0
                }
                if v.reads < 3 {
                  @ui.log(
                    "preview: \{v.name} @\{offset.to_int()} \{bytes.length()} bytes through the core (\{v.part_call()}, total \{total.to_int()})",
                  )
                }
                v.reads += 1
                answer(bytes, total)
              }
              Err(e) => {
                @ui.log("preview: \{v.name} @\{offset.to_int()} failed: \{e.stringify()}")
                answer(b"", -2.0)
              }
            }
          })
        })
        n.play()
        v.video = Some(n)
      }
      return
    }
    _ => ()
  }
  let want = !v.told_of() || v.asked
  if want && v.bytes is None && !v.fetching && v.error is None &&
    (v.kind is Some(_) || v.sniffed is Some(_)) {
    v.fetching = true
    v.read_whole(src, fn(r) {
      v.fetching = false
      match r {
        Ok(bytes) => {
          @ui.log(
            "preview: \{v.name} read whole through the core (\{if v.drive is Some(_) { "drive.read" } else { "station.file" }}, \{bytes.length()} bytes)",
          )
          v.bytes = Some(bytes)
        }
        Err(e) =>
          v.error = Some(
            match text(Some(e), "message") {
              "" => e.stringify()
              m => m
            },
          )
      }
    })
  }
  ignore(c)
}

///|
/// Text, when its first bytes decode as UTF-8 with no NULs (the cut may split a character: its last bytes left out).
fn looks_like_text(b : Bytes) -> Bool {
  let n = if b.length() < 8192 { b.length() } else { 8192 }
  for i in 0..<n {
    if b[i] == b'\x00' {
      return false
    }
  }
  let end = if b.length() > 8192 { 8188 } else { n }
  // UTF-8's shape: lead bytes and their continuations
  let mut i = 0
  while i < end {
    let x = b[i].to_int()
    let more = if x < 0x80 {
      0
    } else if x >= 0xC2 && x < 0xE0 {
      1
    } else if x >= 0xE0 && x < 0xF0 {
      2
    } else if x >= 0xF0 && x < 0xF5 {
      3
    } else {
      return false
    }
    if i + more >= end && more > 0 {
      return true
    }
    for k in 1..=more {
      let y = b[i + k].to_int()
      if y < 0x80 || y >= 0xC0 {
        return false
      }
    }
    i = i + 1 + more
  }
  true
}

///|
/// The first `limit` bytes as UTF-8 text (what does not decode, and a character the cut splits, as U+FFFD).
fn utf8_text(b : Bytes, limit : Int) -> String {
  let n = if b.length() < limit { b.length() } else { limit }
  let sb = StringBuilder()
  let mut i = 0
  while i < n {
    let x = b[i].to_int()
    let (more, start) = if x < 0x80 {
      (0, x)
    } else if x >= 0xC2 && x < 0xE0 {
      (1, x & 0x1F)
    } else if x >= 0xE0 && x < 0xF0 {
      (2, x & 0x0F)
    } else if x >= 0xF0 && x < 0xF5 {
      (3, x & 0x07)
    } else {
      (-1, 0)
    }
    let mut cp = start
    let mut ok = more >= 0 && i + more < n
    if ok {
      for k in 1..=more {
        let y = b[i + k].to_int()
        if y < 0x80 || y >= 0xC0 {
          ok = false
          break
        }
        cp = (cp << 6) | (y & 0x3F)
      }
    }
    if ok && (cp < 0xD800 || cp > 0xDFFF) && cp <= 0x10FFFF {
      sb.write_char(cp.unsafe_to_char())
      i = i + 1 + more
    } else {
      sb.write_char('\u{FFFD}')
      i = i + 1
    }
  }
  sb.to_string()
}

///|
/// ASCII letters in capitals.
fn upper(s : String) -> String {
  let sb = StringBuilder()
  for ch in s {
    let k = ch.to_int()
    sb.write_char(if k >= 97 && k <= 122 { (k - 32).unsafe_to_char() } else { ch })
  }
  sb.to_string()
}

// ── the viewer ─────────────────────────────────────────────────────────

///|
/// The viewer over the pages, if one is open: call after the pages are drawn.
fn preview(c : @ui.Ctx, src : Source) -> Unit {
  let v = match viewer.val {
    Some(v) => v
    None => return
  }
  let now = c.now()
  if v.opened < 0.0 {
    v.opened = now
    v.rest_at = if v.rests { now + rest_ms } else { -1.0 }
    // it comes up in the keyboard's place: what was being typed into lets go of it first
    c.blur()
  }
  // as web's: fading in and out (FilePreview.css.ts fp: 140 ms ease-out), when there is no thumbnail to grow from
  let shown = if v.closing >= 0.0 {
    1.0 - dmin(1.0, (now - v.closing) / 140.0)
  } else {
    dmin(1.0, (now - v.opened) / 140.0)
  }
  if v.closing >= 0.0 && shown <= 0.0 {
    close_now()
    c.request_frame()
    return
  }
  if shown < 1.0 {
    c.request_frame()
  }
  let shown = @ui.bezier(0.2, 0.7, 0.2, 1.0, shown)
  v.fetch(c, src)
  // asked for to be saved, and come: saved
  if v.save_after && v.bytes is Some(_) {
    v.save_after = false
    v.ask_save(c)
  }
  // the bars fade when left alone (not while it comes, nor over a page whose taps are its own)
  if v.awake && v.rest_at > 0.0 {
    if now >= v.rest_at {
      v.awake = false
    } else {
      c.wake_in(v.rest_at - now, later=true)
    }
  }
  let t = @sf.theme()
  let kind = v.shown_kind()
  let dark = v.dark()
  let ground = if dark {
    0x000000FFL
  } else if kind == Some(KPdf) {
    @sf.mix(t.p.text, 0.05, t.p.bg)
  } else {
    ink().canvas
  }
  c.layer(fn() {
    let stage = c.id("preview/stage")
    @ui.capture(c, stage)
    c.box(w=Fill(1.0), h=Fill(1.0), bg=@sf.alpha(ground, shown), opacity=shown, id=stage, fn() {
      v.content(c, src, stage)
    })
    |> ignore
    c.layer(fn() { v.bar(c, src, shown) }) |> ignore
    match kind {
      Some(KVideo) =>
        c.layer(fn() {
          c.spacer()
          v.video_controls(c, shown)
        })
        |> ignore
      _ => ()
    }
  })
  |> ignore
  c.take_back(fn() { v.close(c) })
}

///|
fn Viewer::close(self : Viewer, c : @ui.Ctx) -> Unit {
  if self.closing < 0.0 {
    self.closing = c.now()
    // the views under the canvas go at once (they cannot fade)
    match self.video {
      Some(n) => n.pause()
      None => ()
    }
    c.request_frame()
  }
}

///|
/// A tap on the stage shows or hides the bars.
fn Viewer::toggle(self : Viewer, now : Double) -> Unit {
  if self.awake {
    self.awake = false
    self.rest_at = -1.0
  } else {
    self.wake(now, tap_rest_ms)
  }
}

///|
fn Viewer::wake(self : Viewer, now : Double, ms : Double) -> Unit {
  self.awake = true
  self.rest_at = now + ms
}

///|
/// Whether the bars show: awake, or while the whole of an image comes, or over a page whose taps are its own.
fn Viewer::bars_shown(self : Viewer) -> Bool {
  self.awake || self.coming() || (self.shown_kind() == Some(KHtml) && !self.source)
}

///|
/// An image still coming (its thumbnail in its place meanwhile).
fn Viewer::coming(self : Viewer) -> Bool {
  self.shown_kind() == Some(KImage) && self.bytes is None && self.error is None
}

///|
/// The stage: what the file shows as.
fn Viewer::content(self : Viewer, c : @ui.Ctx, src : Source, stage : Int) -> Unit {
  let v = self
  let kind = v.shown_kind()
  match kind {
    Some(KImage) if v.file.size <= big_file => v.image_stage(c, src, stage)
    Some(KVideo) => v.video_stage(c, stage)
    Some(KAudio) => v.audio_stage(c, stage)
    _ =>
      if v.told_of() {
        v.note(c, fn() { v.facts(c) })
      } else if (v.kind is None && v.sniffed is None) || (v.bytes is None && v.error is None) {
        tap_stage(c, v, stage)
        v.note(c, fn() { reading_pill(c, pv("common.reading")) })
      } else {
        match v.error {
          Some(e) => {
            tap_stage(c, v, stage)
            v.note(c, fn() {
              c.text(pv_fill("android-chat.file.loadFailed", [("error", e)]), size=15.0, color=@sf.theme().p.muted)
              |> ignore
            })
          }
          None =>
            match (kind, v.bytes) {
              (Some(KPdf), Some(b)) => v.pdf_stage(c, b, stage)
              (Some(k), Some(b)) => v.text_stage(c, k, b, stage)
              _ => ()
            }
        }
      }
  }
}

///|
/// Taps on the stage (not on what is over it) show or hide the bars.
fn tap_stage(c : @ui.Ctx, v : Viewer, stage : Int) -> Unit {
  if c.clicked(stage) {
    v.toggle(c.now())
  }
}

///|
/// A note in the middle of the stage (FilePreview.kt Note): 24 round it, what it holds 14 apart.
fn Viewer::note(self : Viewer, c : @ui.Ctx, body : () -> Unit) -> Unit {
  ignore(self)
  c.box(w=Fill(1.0), h=Fill(1.0), pad=24.0, gap=14.0, align=ACenter, justify=JCenter, fn() { body() })
  |> ignore
}

///|
/// A wait (ui/Waiting.kt WaitPill): a spinner and its words on the chip's ground, round.
fn reading_pill(c : @ui.Ctx, words : String) -> Unit {
  let t = @sf.theme()
  c.box(dir=Row, padx=12.0, pady=6.0, gap=8.0, align=ACenter, bg=t.p.chip, radius=15.0, fn() {
    @sf.spinner(c, size=12.0) |> ignore
    c.text(words, size=13.0, color=t.p.muted, line=18.0, wrap=false) |> ignore
  })
  |> ignore
}

///|
/// A file told of, not shown (FilePreview.kt Facts and its buttons): its kind's mark, its name, its size and
/// extension, why it is not shown; 下载.
fn Viewer::facts(self : Viewer, c : @ui.Ctx) -> Unit {
  let v = self
  let t = @sf.theme()
  let kind = v.shown_kind()
  c.box(gap=6.0, align=ACenter, fn() {
    @sf.icon(c, if kind is None { "file" } else { "file-text" }, size=44.0, color=t.p.muted)
    |> ignore
    c.box(pt=6.0, max_w=c.width - 48.0, fn() {
      c.text(v.file.name, size=17.0, weight=600, color=t.p.text, line=23.0, center=true)
      |> ignore
    })
    |> ignore
    let ext = match lower(v.file.name).rev_find(".") {
      Some(i) if i > 0 && v.file.name.length() - i - 1 <= 12 =>
        upper(v.file.name.view(start_offset=i + 1).to_owned())
      _ => ""
    }
    let facts = if ext == "" { file_size(v.file.size) } else { file_size(v.file.size) + " · " + ext }
    c.text(facts, size=13.0, color=t.p.muted, wrap=false) |> ignore
    c.box(pt=4.0, fn() {
      c.text(
        if kind is None {
          pv("android-chat.file.cantPreview")
        } else {
          pv("android-chat.file.tooBigToShow")
        },
        size=14.0,
        color=t.p.muted,
        center=true,
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
  if v.asked && v.bytes is None && v.error is None {
    reading_pill(c, pv("common.reading"))
    return
  }
  c.box(w=Px(220.0), gap=8.0, fn() {
    match v.error {
      Some(e) =>
        c.text(pv_fill("android-chat.file.loadFailed", [("error", e)]), size=14.0, color=t.p.red, center=true)
        |> ignore
      None => ()
    }
    let id = c.id("preview/note-download")
    if c.clicked(id) {
      v.ask_save(c)
    }
    c.box(
      dir=Row,
      w=Fill(1.0),
      padx=14.0,
      pady=10.0,
      gap=6.0,
      align=ACenter,
      justify=JCenter,
      radius=12.0,
      bg=if c.pressed(id) { @sf.mix(0xFFFFFFFFL, 0.15, t.p.accent) } else { t.p.accent },
      id~,
      fn() {
        @sf.icon(c, "download", size=16.0, color=0xFFFFFFFFL) |> ignore
        c.text(pv("android-chat.file.download"), size=15.0, weight=500, color=0xFFFFFFFFL, wrap=false)
        |> ignore
      },
    )
    |> ignore
  })
  |> ignore
}

///|
/// 下载: the file into the system's downloads, once it is here (fetched first when it was only told of).
fn Viewer::ask_save(self : Viewer, c : @ui.Ctx) -> Unit {
  match self.bytes {
    Some(b) => {
      let ok = @host.save_file(self.file.name, b)
      app.toast = pv(if ok { "android-chat.file.saved" } else { "android-chat.file.saveFailed" })
      app.toast_at = -1.0
    }
    None => {
      self.error = None
      self.asked = true
      self.save_after = true
    }
  }
  c.request_frame()
}

// ── an image ───────────────────────────────────────────────────────────

///|
/// An image fitted to the stage, to double-tap, pan and zoom (the wheel, the bar's − and +); until the whole of it
/// comes, the chat's thumbnail (or its likeness) stands in its place.
fn Viewer::image_stage(self : Viewer, c : @ui.Ctx, src : Source, stage : Int) -> Unit {
  let v = self
  let now = c.now()
  match v.bytes {
    Some(b) if v.image == "" => {
      v.image = "mem:preview/\{v.station}/\{v.key}/\{v.file.path}"
      @ui.add_image(v.image, b)
    }
    _ => ()
  }
  let thumb = if v.drive is Some(_) { "" } else { (src.file)(v.station, v.key, v.name) }
  let picture = if v.image != "" {
    v.image
  } else if thumb != "" && thumb != "!" {
    thumb
  } else {
    match @gallery.thumbhash_image(v.file.thumbhash) {
      Some(k) => k
      None => ""
    }
  }
  if v.image != "" && @ui.image_state(v.image) == -1 {
    tap_stage(c, v, stage)
    v.note(c, fn() {
      c.text(pv("android-chat.file.image.failed"), size=15.0, color=dark_muted) |> ignore
    })
    return
  }
  // its size: as sent, else as decoded
  let (nw, nh) = if v.file.width > 0.0 && v.file.height > 0.0 {
    (v.file.width, v.file.height)
  } else {
    match @ui.image_natural(if v.image != "" { v.image } else { picture }) {
      Some(s) => s
      None => (0.0, 0.0)
    }
  }
  let z = v.zoom
  z.boxed(c.width, c.height)
  z.natural(nw, nh)
  if z.step(now) {
    c.request_frame()
  }
  v.gestures(c, stage, z)
  match z.rect() {
    Some((x, y, w, h)) if picture != "" =>
      c.picture(picture, x~, y~, w~, h~, max_px=4096) |> ignore
    // its size not sent with it: a small decode, out of sight, says it
    _ if picture != "" =>
      c.box(w=Px(1.0), h=Px(1.0), opacity=0.01, fn() {
        c.image(picture, w=Px(1.0), h=Px(1.0), bg=0L, fade=false) |> ignore
      })
      |> ignore
    _ => ()
  }
}

///|
/// The stage's gestures over a picture: a tap shows or hides the bars, a double tap zooms in (or back), a finger
/// moves it when it is larger than the stage, the wheel (or a trackpad's two fingers with ⌘… any wheel) zooms round
/// the pointer.
fn Viewer::gestures(self : Viewer, c : @ui.Ctx, stage : Int, z : Zoom) -> Unit {
  let v = self
  let now = c.now()
  let (px, py, _) = c.pointer()
  // two fingers: a pinch, round the point between them, which moves the picture as it moves
  match c.second_pointer() {
    Some((x2, y2)) if c.pressed(stage) && z.nw > 0.0 => {
      let cx = (px + x2) / 2.0
      let cy = (py + y2) / 2.0
      let d = ((px - x2) * (px - x2) + (py - y2) * (py - y2)).sqrt()
      if v.pinch_d > 0.0 && d > 0.0 {
        z.transform(cx, cy, d / v.pinch_d, cx - v.pinch_x, cy - v.pinch_y)
      }
      v.pinch_d = d
      v.pinch_x = cx
      v.pinch_y = cy
      v.pinched = true
      // one finger again after it: followed from where it is then
      v.held = false
      c.request_frame()
      return
    }
    _ => v.pinch_d = 0.0
  }
  if c.pressed(stage) {
    if v.held {
      let dx = px - v.last_x
      let dy = py - v.last_y
      v.moved = v.moved + dx.abs() + dy.abs()
      if v.moved > 8.0 && (dx != 0.0 || dy != 0.0) {
        z.pan(dx, dy)
      }
    } else {
      v.held = true
      if !v.pinched {
        v.moved = 0.0
      }
    }
    v.last_x = px
    v.last_y = py
    c.request_frame()
  } else {
    v.held = false
  }
  let pinched = v.pinched
  if !c.pressed(stage) {
    v.pinched = false
  }
  if c.clicked(stage) && v.moved <= 8.0 && !pinched {
    if now - v.tap_at < 300.0 && (px - v.tap_x).abs() < 40.0 && (py - v.tap_y).abs() < 40.0 {
      // the second of two: zoom (and the first's toggle undone)
      v.tap_at = -1.0e9
      v.toggle(now)
      z.double_tap(px, py, now)
      c.request_frame()
    } else {
      v.tap_at = now
      v.tap_x = px
      v.tap_y = py
      v.toggle(now)
    }
  }
  let dy = @ui.wheel(c, stage)
  if dy != 0.0 && z.nw > 0.0 {
    z.zoom_to(z.scale * @math.pow(1.0015, -dy), px, py, now, false)
    c.request_frame()
  }
}

// ── a video ────────────────────────────────────────────────────────────

///|
/// The video where its zoom puts it: the system's player, a native view under the canvas, shown through a hole in
/// it. Before its first frame the stage's black (the chat has no still of it yet).
fn Viewer::video_stage(self : Viewer, c : @ui.Ctx, stage : Int) -> Unit {
  let v = self
  let z = v.vzoom
  z.boxed(c.width, c.height)
  match v.video {
    Some(n) => {
      let (nw, nh) = n.natural()
      if nw > 0.0 && nh > 0.0 {
        z.natural(nw, nh)
      } else if v.file.width > 0.0 && v.file.height > 0.0 {
        z.natural(v.file.width, v.file.height)
      }
      if z.step(c.now()) {
        c.request_frame()
      }
      v.gestures(c, stage, z)
      if v.closing < 0.0 && n.here() {
        match z.rect() {
          Some(r) => c.native(n, content=Some(r)) |> ignore
          // its size not known yet (not sent with it): placed all the same, a point in the middle, so the player has
          // somewhere to draw (Android's decoder starts only with a surface, and tells the size once it has one)
          None =>
            c.native(n, content=Some((z.bw / 2.0, z.bh / 2.0, 1.0, 1.0))) |> ignore
        }
      }
      if n.state() == -1 {
        c.layer(align=ACenter, fn() {
          c.box(w=Fill(1.0), h=Fill(1.0), align=ACenter, justify=JCenter, fn() {
            c.text(pv("android-chat.video.failed"), size=14.0, color=0xFFFFFF99L, wrap=false)
            |> ignore
          })
          |> ignore
        })
        |> ignore
      }
    }
    None => tap_stage(c, v, stage)
  }
}

///|
/// A song (VideoViewer.kt AudioViewer, in the page's colours): its name and the capsule that plays it
/// (src/player's audio_strip), in the middle; its player has no picture to place.
fn Viewer::audio_stage(self : Viewer, c : @ui.Ctx, stage : Int) -> Unit {
  let v = self
  tap_stage(c, v, stage)
  match v.video {
    Some(n) =>
      v.note(c, fn() { @player.audio_strip(c, "preview/audio", n, v.file.name, pinned=v.pinned) })
    None => ()
  }
}

///|
/// The video's controls (VideoViewer.kt), floating over its foot: where it is (to tap or drag along), the steps and
/// play, which frame, the speed. The tint stands for the Android app's frosted glass (a native view cannot be blurred).
fn Viewer::video_controls(self : Viewer, c : @ui.Ctx, shown : Double) -> Unit {
  let v = self
  let n = match v.video {
    Some(n) => n
    None => return
  }
  let now = c.now()
  let on = v.bars_shown()
  let dur = n.duration()
  let pos = n.position()
  // a frame a 60th of a second (the file's own frames are not read here)
  let step = 1000.0 / 60.0
  let frames = if dur > 0.0 { (dur / step).round().to_int() } else { 0 }
  let at = if dur > 0.0 { (pos / step).floor().to_int() } else { 0 }
  let controls = c.id("preview/video-controls")
  if c.pressed(controls) {
    v.wake(now, tap_rest_ms)
  }
  c.box(w=Fill(1.0), pad=8.0, opacity=if on { shown } else { 0.0 }, fn() {
    c.box(
      w=Fill(1.0),
      pl=4.0,
      pr=4.0,
      pt=2.0,
      pb=4.0,
      radius=16.0,
      bg=solid_glass(),
      id=if on { controls } else { 0 },
      fn() {
        timeline(c, v, n, dur, pos)
        c.box(dir=Row, w=Fill(1.0), gap=12.0, align=ACenter, fn() {
          c.box(dir=Row, gap=2.0, fn() {
            if picture_button(c, "preview/prev", "chevron-left", dark_muted, on) {
              n.seek(dmax(0.0, (at - 1).to_double() * step))
              n.pause()
              v.wake(now, tap_rest_ms)
            }
            if picture_button(c, "preview/play", if n.playing() { "pause" } else { "play" }, dark_muted, on) {
              if n.playing() {
                n.pause()
              } else {
                n.play()
              }
              v.wake(now, tap_rest_ms)
            }
            if picture_button(c, "preview/next", "chevron-right", dark_muted, on) {
              n.seek(dmin(dmax(dur, 0.0), (at + 1).to_double() * step))
              n.pause()
              v.wake(now, tap_rest_ms)
            }
          })
          |> ignore
          c.box(w=Fill(1.0), fn() {
            if frames > 0 {
              let words = pv_fill("android-chat.video.frames", [("n", "\{frames}")])
              let parts = words.split("{at}").map(fn(s) { s.to_owned() }).to_array()
              c.rich(
                [
                  @ui.span(parts.get(0).unwrap_or(""), color=dark_muted, mono=true),
                  @ui.span("\{at + 1}", color=dark_text, weight=600, mono=true),
                  @ui.span(parts.get(1).unwrap_or(""), color=dark_muted, mono=true),
                ],
                size=12.0,
                wrap=false,
              )
              |> ignore
            } else if n.state() == 0 {
              c.box(dir=Row, gap=8.0, align=ACenter, fn() {
                @sf.spinner(c, size=12.0) |> ignore
                c.text(pv("common.reading"), size=13.0, color=dark_muted, wrap=false) |> ignore
              })
              |> ignore
            }
          })
          |> ignore
          let rate_id = c.id("preview/rate")
          if c.clicked(rate_id) && on {
            let rates = [0.1, 0.25, 0.5, 1.0]
            let mut i = 3
            for k, r in rates {
              if r == v.rate {
                i = k
              }
            }
            v.rate = rates[(i + rates.length() - 1) % rates.length()]
            n.rate(v.rate)
            v.wake(now, tap_rest_ms)
          }
          let r = if v.rate == 1.0 {
            "1"
          } else if v.rate == 0.5 {
            "0.5"
          } else if v.rate == 0.25 {
            "0.25"
          } else {
            "0.1"
          }
          c.box(
            h=Px(28.0),
            min_w=46.0,
            padx=8.0,
            radius=10.0,
            bg=0xFFFFFF1AL,
            align=ACenter,
            justify=JCenter,
            id=rate_id,
            fn() {
              c.rich([@ui.span(r + "×", weight=600, mono=true)], size=12.0, color=dark_text, wrap=false)
              |> ignore
            },
          )
          |> ignore
        })
        |> ignore
      },
    )
    |> ignore
  })
  |> ignore
}

///|
/// Where in the video it is (VideoViewer.kt Timeline): a thin track, what has played, a round head; tapped or dragged
/// along to go there.
fn timeline(c : @ui.Ctx, v : Viewer, n : @ui.NativeView, dur : Double, pos : Double) -> Unit {
  let id = c.id("preview/timeline")
  let part = if dur > 0.0 { dmax(0.0, dmin(1.0, pos / dur)) } else { 0.0 }
  match c.rect_of(id) {
    Some((x, _, w, _)) if c.pressed(id) && dur > 0.0 => {
      let (px, _, _) = c.pointer()
      n.seek(dmax(0.0, dmin(1.0, (px - x) / dmax(1.0, w))) * dur)
      v.wake(c.now(), tap_rest_ms)
      c.request_frame()
    }
    _ => ()
  }
  c.box(w=Fill(1.0), h=Px(22.0), padx=6.0, justify=JCenter, id~, fn() {
    // what has played, then the rest (Fill shares the row: one alone would fill it)
    c.box(dir=Row, w=Fill(1.0), h=Px(4.0), radius=2.0, bg=0xFFFFFF33L, fn() {
      if part > 0.0 {
        c.box(w=Fill(part), h=Px(4.0), radius=2.0, bg=dark_text, fn() {  }) |> ignore
      }
      if part < 1.0 {
        c.box(w=Fill(1.0 - part), h=Px(4.0), fn() {  }) |> ignore
      }
    })
    |> ignore
    c.layer(fn() {
      c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), align=ACenter, fn() {
        if part > 0.0 {
          c.box(w=Fill(part), fn() {  }) |> ignore
        }
        c.box(w=Px(12.0), h=Px(12.0), radius=6.0, bg=dark_text, tx=-6.0, fn() {  }) |> ignore
        if part < 1.0 {
          c.box(w=Fill(1.0 - part), fn() {  }) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The tint the bars over a picture or a video have (darkGlass's 0x121214 at 62% over a blur of what is under): no
/// blur here, so a deeper tint keeps their words as readable.
fn solid_glass() -> Int64 {
  0x121214D9L
}

///|
/// A button on the viewer's bars (ImageMarks.kt PictureButton): 32 square, its corner 12, an 18 icon; quieter when
/// it cannot be pressed. True on the frame after it was tapped.
fn picture_button(c : @ui.Ctx, key : String, icon : String, tint : Int64, on : Bool, enabled? : Bool = true) -> Bool {
  let id = c.id(key)
  let live = on && enabled
  c.box(
    w=Px(32.0),
    h=Px(32.0),
    radius=12.0,
    align=ACenter,
    justify=JCenter,
    bg=if c.pressed(id) && live { @sf.alpha(tint, 0.16) } else { 0L },
    opacity=if enabled { 1.0 } else { 0.35 },
    id=if live { id } else { 0 },
    fn() { @sf.icon(c, icon, size=18.0, color=tint) |> ignore },
  )
  |> ignore
  live && c.clicked(id)
}

// ── a PDF ──────────────────────────────────────────────────────────────

///|
/// Pages drawn by the system, each as it scrolls near, as wide as the screen allows (FilePreview.kt PdfViewer): 12
/// round them and between them, a page not drawn yet its shape on the bubble's grey.
fn Viewer::pdf_stage(self : Viewer, c : @ui.Ctx, b : Bytes, stage : Int) -> Unit {
  let v = self
  let t = @sf.theme()
  let pdf = match v.pdf {
    Some(p) => p
    None => {
      let p = @ui.Pdf::open(b)
      v.pdf = Some(p)
      @ui.log("preview: \{v.name}: a PDF of \{p.pages} pages")
      p
    }
  }
  if pdf.pages < 0 {
    tap_stage(c, v, stage)
    v.note(c, fn() {
      c.text(
        pv_fill("android-chat.file.pdf.failed", [("error", if @host.platform() == 3 || @host.platform() == 4 { "此平台不能显示 PDF" } else { "" })]),
        size=15.0,
        color=t.p.muted,
        center=true,
      )
      |> ignore
    })
    return
  }
  tap_stage(c, v, stage)
  let w = c.width - 24.0
  c.list("preview/pdf/" + v.file.path, pdf.pages + 2, 400.0, fn(i) {
    if i == 0 {
      c.box(w=Fill(1.0), h=Px(60.0), fn() {  }) |> ignore
    } else if i == pdf.pages + 1 {
      c.box(w=Fill(1.0), h=Px(12.0), fn() {  }) |> ignore
    } else {
      let (pw, ph) = pdf.sizes[i - 1]
      let h = if pw > 0.0 { w * ph / pw } else { w * 1.294 }
      c.box(w=Fill(1.0), pl=12.0, pr=12.0, pb=if i < pdf.pages { 12.0 } else { 0.0 }, fn() {
        c.box(w=Px(w), h=Px(h), bg=0xFFFFFFFFL, shadow=2.0, shadow_y=1.0, fn() {
          c.image(pdf.page_src(i - 1), w=Px(w), h=Px(h), fit=FitFill, bg=t.p.neutral_bg) |> ignore
        })
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

// ── text ───────────────────────────────────────────────────────────────

///|
/// Markdown rendered, CSV a table, HTML a page (each, or its source); code and text as they are, in the code face.
fn Viewer::text_stage(self : Viewer, c : @ui.Ctx, kind : PKind, b : Bytes, stage : Int) -> Unit {
  let v = self
  let t = @sf.theme()
  let cut = b.length() > show_limit
  let words = match v.text {
    Some(s) => s
    None => {
      let s = utf8_text(b, show_limit)
      v.text = Some(s)
      s
    }
  }
  if kind == KHtml && !v.source {
    // its scripts run, in a page of its own that reaches nothing of the app's
    let page = match v.page {
      Some(p) => p
      None => {
        let head = words.view(end_offset=if words.length() < 2048 { words.length() } else { 2048 }).to_owned()
        let low = lower(head)
        let html = if low.contains("<!doctype") || low.contains("<html") {
          words
        } else {
          "<!doctype html><meta charset=utf-8><meta name=viewport content=\"width=device-width,initial-scale=1\"><body style=\"margin:0;padding:16px;font-family:system-ui,sans-serif\">" +
          words
        }
        let p = @ui.NativeView::page(html)
        v.page = Some(p)
        p
      }
    }
    c.box(w=Fill(1.0), h=Fill(1.0), pt=60.0, fn() {
      if page.here() && v.closing < 0.0 {
        c.native(page) |> ignore
      } else if !page.here() {
        v.note(c, fn() {
          c.text(pv("android-chat.file.cantPreview"), size=15.0, color=t.p.muted) |> ignore
        })
      }
    })
    |> ignore
    return
  }
  tap_stage(c, v, stage)
  if kind == KCsv && !v.source {
    csv_table(c, v, words, lower(v.name).has_suffix(".tsv"), cut)
    return
  }
  // in rows of 60 lines, so a long file lays out only what is in view
  let lines = words.split("\n").map(fn(s) { s.to_owned() }).to_array()
  let chunks = (lines.length() + 59) / 60
  let markdown = kind == KMarkdown && !v.source
  let code = !markdown && (kind != KText && kind != KCsv)
  let count = if markdown { 1 } else { chunks }
  c.list("preview/text/" + v.file.path + (if v.source { "/source" } else { "" }), count + 3, 400.0, fn(i) {
    if i == 0 {
      if cut {
        c.box(w=Fill(1.0), pl=20.0, pr=20.0, pt=8.0, pb=8.0, bg=@sf.alpha(t.p.red, 0.0), fn() {  })
        |> ignore
      }
      c.box(w=Fill(1.0), h=Px(if markdown { 64.0 } else if code { 80.0 } else { 60.0 }), fn() {  })
      |> ignore
      if cut {
        cut_line(c, pv_fill("android-chat.file.cut", [("size", file_size(show_limit.to_double()))]))
      }
    } else if i == count + 1 {
      c.box(w=Fill(1.0), h=Px(if markdown { 64.0 } else { 48.0 }), fn() {  }) |> ignore
    } else if i == count + 2 {
      ()
    } else if markdown {
      c.box(w=Fill(1.0), pl=18.0, pr=18.0, fn() {
        @sf.markdown(c, words, key="preview-md") |> ignore
      })
      |> ignore
    } else {
      let from = (i - 1) * 60
      let to = if from + 60 < lines.length() { from + 60 } else { lines.length() }
      let sb = StringBuilder()
      for k in from..<to {
        if k > from {
          sb.write_char('\n')
        }
        sb.write_string(lines[k])
      }
      c.box(w=Fill(1.0), pl=if code { 32.0 } else { 16.0 }, pr=if code { 32.0 } else { 16.0 }, clip=code, fn() {
        c.rich(
          [@ui.span(sb.to_string(), mono=true)],
          size=12.5,
          color=t.p.text,
          line=if code { 20.0 } else { 20.6 },
          wrap=!code,
        )
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// A file shown only in part (FilePreview.kt Cut): the warning's words on its tint.
fn cut_line(c : @ui.Ctx, words : String) -> Unit {
  let warn = 0xD9962BFFL
  c.box(w=Fill(1.0), pl=20.0, pr=20.0, pt=8.0, pb=8.0, bg=@sf.alpha(warn, 0.14), fn() {
    c.text(words, size=13.0, color=warn) |> ignore
  })
  |> ignore
}

///|
/// Rows of a CSV (or TSV), quotes and all (FilePreview.kt parseCsv).
fn parse_csv(s : String, sep : Char, limit : Int) -> Array[Array[String]] {
  let rows : Array[Array[String]] = []
  let mut row : Array[String] = []
  let field = StringBuilder()
  let mut empty = true
  let mut quoted = false
  let chars : Array[Char] = []
  for ch in s {
    chars.push(ch)
  }
  let mut i = 0
  while i < chars.length() && rows.length() < limit {
    let ch = chars[i]
    if quoted {
      if ch == '"' && i + 1 < chars.length() && chars[i + 1] == '"' {
        field.write_char('"')
        i += 1
      } else if ch == '"' {
        quoted = false
      } else {
        field.write_char(ch)
      }
    } else if ch == '"' && empty {
      quoted = true
      empty = false
    } else if ch == sep {
      row.push(field.to_string())
      field.reset()
      empty = true
    } else if ch == '\n' || ch == '\r' {
      if ch == '\r' && i + 1 < chars.length() && chars[i + 1] == '\n' {
        i += 1
      }
      row.push(field.to_string())
      rows.push(row)
      row = []
      field.reset()
      empty = true
    } else {
      field.write_char(ch)
      empty = false
    }
    i += 1
  }
  if (!empty || row.length() > 0) && rows.length() < limit {
    row.push(field.to_string())
    rows.push(row)
  }
  rows
}

///|
/// A table (FilePreview.kt CsvTable): a row number, then its columns, each as wide as what it holds (by its
/// characters here: 48 to 420), the head on the canvas with a hairline under it.
fn csv_table(c : @ui.Ctx, v : Viewer, words : String, tab : Bool, cut : Bool) -> Unit {
  let t = @sf.theme()
  let rows = parse_csv(words, if tab { '\t' } else { ',' }, table_rows + 1)
  if rows.length() == 0 {
    return
  }
  let head = rows[0]
  let body_n = if rows.length() - 1 > table_rows { table_rows } else { rows.length() - 1 }
  let more = rows.length() - 1 > table_rows
  let widths = head.mapi(fn(j, _) {
    let mut most = 0.0
    for r in 0..<(if rows.length() < 201 { rows.length() } else { 201 }) {
      match rows[r].get(j) {
        Some(cell) => {
          let mut w = 0.0
          for ch in cell {
            w = w + (if ch.to_int() < 0x2E80 { 8.4 } else { 15.0 })
          }
          most = dmax(most, dmin(w, 80.0 * 8.4))
        }
        None => ()
      }
    }
    dmax(48.0, dmin(420.0, most + 32.0))
  })
  let number = "\{body_n}".length().to_double() * 8.4 + 36.0
  let cell = fn(s : String, w : Double, weight : Int, color : Int64) {
    c.box(w=Px(w), padx=16.0, pady=8.0, clip=true, fn() {
      c.text(s, size=15.0, weight~, color~, wrap=false) |> ignore
    })
    |> ignore
  }
  c.list("preview/csv/" + v.file.path, body_n + 3, 37.0, fn(i) {
    if i == 0 {
      c.box(w=Fill(1.0), h=Px(60.0), fn() {  }) |> ignore
    } else if i == 1 {
      c.box(dir=Row, bg=ink().canvas, border=0.0, fn() {
        c.box(w=Px(number), fn() {  }) |> ignore
        for j, h in head {
          cell(h, widths[j], 600, t.p.text)
        }
      })
      |> ignore
      c.box(w=Fill(1.0), h=Px(1.0), bg=t.p.line, fn() {  }) |> ignore
    } else if i == body_n + 2 {
      if more || cut {
        cut_line(c, pv_fill("android-chat.file.cut.rows", [("n", "\{table_rows}")]))
      }
      c.box(w=Fill(1.0), h=Px(48.0), fn() {  }) |> ignore
    } else {
      let r = rows[i - 1]
      c.box(dir=Row, fn() {
        c.box(w=Px(number), pl=20.0, pr=16.0, pt=8.0, pb=8.0, align=AEnd, fn() {
          c.text("\{i - 1}", size=15.0, color=t.p.muted, wrap=false) |> ignore
        })
        |> ignore
        for j, _ in head {
          cell(r.get(j).unwrap_or(""), widths[j], 400, t.p.text)
        }
      })
      |> ignore
    }
  })
  |> ignore
}

// ── the bar ────────────────────────────────────────────────────────────

///|
/// The bar at the top (FilePreview.kt): the file's name, its own tools (an image's zoom, a document's 预览 / 源码),
/// download and close; frosted in the Android app (a solid tint here), fading when left alone.
fn Viewer::bar(self : Viewer, c : @ui.Ctx, src : Source, shown : Double) -> Unit {
  let v = self
  let t = @sf.theme()
  let dark = v.dark()
  let on = v.bars_shown()
  let tint = if dark { dark_muted } else { t.p.muted }
  let kind = v.shown_kind()
  ignore(src)
  c.box(w=Fill(1.0), pt=8.0, align=ACenter, opacity=if on { shown } else { 0.0 }, fn() {
    c.box(
      dir=Row,
      h=Px(44.0),
      max_w=c.width - 16.0,
      pl=12.0,
      pr=2.0,
      gap=4.0,
      align=ACenter,
      radius=14.0,
      bg=if dark {
        solid_glass()
      } else if t.dark {
        @sf.alpha(t.p.card, 0.92)
      } else {
        0xFFFFFFEBL
      },
      shadow=if dark { 0.0 } else { 6.0 },
      shadow_color=0x0000001FL,
      fn() {
        c.box(w=Auto, pr=12.0, max_w=c.width - 16.0 - 14.0 - 4.0 * 36.0, clip=true, fn() {
          c.text(v.file.name, size=15.0, weight=600, color=if dark { dark_text } else { t.p.text }, wrap=false)
          |> ignore
        })
        |> ignore
        c.box(w=Fill(1.0), fn() {  }) |> ignore
        match kind {
          Some(KImage) if !v.coming() => {
            let z = v.zoom
            if picture_button(c, "preview/zoom-out", "minus", tint, on, enabled=z.scale > z.min_scale() + 0.0001) {
              z.zoom_to(z.scale / 1.25, z.bw / 2.0, z.bh / 2.0, c.now(), true)
              v.wake(c.now(), tap_rest_ms)
            }
            let pct = c.id("preview/zoom-reset")
            if c.clicked(pct) && on {
              z.reset(c.now())
            }
            c.box(h=Px(32.0), min_w=52.0, radius=12.0, align=ACenter, justify=JCenter, id=if on { pct } else { 0 }, fn() {
              c.text("\{(z.scale * 100.0).round().to_int()}%", size=13.0, color=tint, wrap=false) |> ignore
            })
            |> ignore
            if picture_button(c, "preview/zoom-in", "plus", tint, on, enabled=z.scale < max_scale - 0.0001) {
              z.zoom_to(z.scale * 1.25, z.bw / 2.0, z.bh / 2.0, c.now(), true)
              v.wake(c.now(), tap_rest_ms)
            }
          }
          Some(KMarkdown) | Some(KCsv) | Some(KHtml) if v.bytes is Some(_) => {
            let chosen = @sf.segmented(
              c,
              "preview/tabs",
              [pv("android-chat.file.tab.preview"), pv("android-chat.file.tab.source")],
              if v.source { 1 } else { 0 },
              item_w=57.0,
            )
            if (chosen == 1) != v.source {
              v.source = chosen == 1
              // the page under the canvas goes while its source shows (and comes again)
              if v.source {
                match v.page {
                  Some(p) => p.close()
                  None => ()
                }
                v.page = None
              }
            }
          }
          _ => ()
        }
        if !v.coming() {
          let saving = v.bytes is Some(_) || (v.told_of() && !v.asked)
          if picture_button(c, "preview/download", "download", tint, on && saving) {
            v.ask_save(c)
          }
        }
        if picture_button(c, "preview/close", "close", tint, on || true) {
          v.close(c)
        }
      },
    )
    |> ignore
  })
  |> ignore
}
