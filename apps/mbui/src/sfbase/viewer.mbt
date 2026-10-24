// A file of a chat opened over the whole screen (ember apps/android chat/screens/FilePreview.kt, VideoViewer.kt,
// FileKinds.kt kindOf, ChatFiles.kt FileData; web/src/FilePreview.tsx): images to zoom (a double tap, the bar's − and
// +, the wheel) and pan (mbui's @kit.Zoom, Zoom.kt's); videos played by the system's player (a native view over the
// canvas, src/ui/native.mbt), its bytes read through the core a part at a time (`station.file.part`); PDFs drawn by the
// system page by page; HTML in a page of its own (a native web view: its scripts on, nothing of the app's reachable);
// Markdown rendered; CSV as a table; code and text as they are. Anything else says it cannot be shown and offers the
// download. One bar floats at the top with its name and tools and fades when left alone; a tap brings it back. Back (or
// ×) closes it.
//
// An image or a video flies from the chat's thumbnail and back into it (FilePreview.kt ViewerFlight); a video closed
// so keeps the frame it was left at, which its thumbnail shows and where it goes on from when opened again
// (FileViewers.frames). Its bytes stream (the Android app reads it whole first): a finger along its timeline puts its
// player in a mode of seeks one after another (NativeView::scrub), and the host keeps what it read.
//
// Not yet, against the Android app: pinching on iOS (no second finger told there yet). The bars are frosted glass over
// what the app draws (a picture, a document); over a native view (a video, a page) a solid tint, as it cannot be
// blurred.

///|
/// The words this page adds (client/i18n/catalog/zh android-chat.json, common.json).
// kept across runs: a table, never written
pub let pv_zh : Map[String, String] = {
  // what a marking's buttons say to a screen reader (ImageMarks.kt)
  "android-chat.marks.downloadMarked": "下载标注后的图片",
  "android-chat.marks.undo": "撤销",
  "android-chat.marks.redo": "重做",
  "android-chat.marks.color": "颜色",
  "android-chat.marks.pin": "标注 {n}",
  "android-chat.marks.tool.select": "选择",
  "android-chat.marks.tool.rect": "框",
  "android-chat.marks.tool.arrow": "箭头",
  "android-chat.marks.tool.pen": "画笔",
  "android-chat.marks.tool.text": "文字",
  // a note on a mark (Notes.kt NoteBox, Card)
  "android-chat.annotate.write": "添加批注（可选）",
  "android-chat.annotate.quoteOnly": "只引用",
  "android-chat.annotate.remove": "删除批注",
  "android-chat.annotate.done": "完成",
  "android-chat.file.cantPreview": "此文件类型不支持预览",
  "android-chat.file.cut": "文件较大，仅显示前 {size}，完整内容请下载",
  "android-chat.file.cut.rows": "仅显示前 {n} 行，完整内容请下载",
  "android-chat.file.download": "下载",
  "android-chat.file.install": "安装",
  "android-chat.file.installFailed": "无法安装：{error}",
  "android-chat.file.allowInstall": "允许 {app} 安装应用后，再次点击安装",
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
  "android-chat.file.mark": "标注图片",
  "android-chat.file.marked.name": "{name}-标注-{stamp}.png",
  "android-chat.file.drawFailed": "无法生成图片",
  "android-chat.marks.arrow.where": "箭头 · 从 ({ax}, {ay}) 指向 ({bx}, {by})",
  "android-chat.marks.box.where": "框 · 左上角 ({x}, {y})，{w}×{h}",
  "android-chat.marks.making": "正在生成",
  "android-chat.marks.note.arrow": "箭头",
  "android-chat.marks.note.box": "框",
  "android-chat.marks.quote.on": "在图片 {made}（{width}×{height}，原图 {original}）上，编号 {n}",
  "android-chat.marks.quote.title": "图片 {original} 标注 {n}",
  "android-chat.marks.write": "输入文字",
  "android-chat.preview.put": "添加到对话",
  "android-chat.preview.put.done": "已添加到对话，返回对话发送",
  "common.cancel": "取消",
  "common.delete": "删除",
  "common.done": "完成",
  "android-chat.video.reading": "正在读取帧",
  "android-chat.video.saveFrame": "保存此帧",
  "android-chat.video.saveFrame.failed": "无法保存此帧",
  "android-chat.video.landscape": "横屏",
  "android-chat.video.landscape.exit": "退出横屏",
  "android-chat.video.playFailed": "播放失败",
  "common.close": "关闭",
  "common.reading": "正在读取",
  "common.opening": "正在打开",
}

///|
pub fn pv(key : String) -> String {
  // (the app's words first, as its tables have them; else the viewer's own)
  let w = @sf.t(key)
  if w != key {
    return w
  }
  pv_zh.get(key).unwrap_or(key)
}

///|
pub fn pv_fill(key : String, args : Array[(String, String)]) -> String {
  let w = @sf.t(key, args~)
  if w != key {
    return w
  }
  let mut s = pv(key)
  for a in args {
    s = s.replace_all(old="{" + a.0 + "}", new=a.1)
  }
  s
}

// ── what a file is (FileKinds.kt kindOf) ───────────────────────────────

///|
pub(all) enum PKind {
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
pub fn preview_kind(name : String) -> (PKind?, String, String) {
  let lower = @sf.lower(name)
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
// kept across runs: a table, never written
pub let code_languages : Array[String] = [
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
pub let big_file : Double = 16.0 * 1024.0 * 1024.0

///|
pub let show_limit : Int = 2 * 1024 * 1024

///|
pub let table_rows : Int = 2000

///|
/// The bars fade after this long left alone; after a tap that brought them back, a while longer.
pub let rest_ms : Double = 2000.0

///|
pub let tap_rest_ms : Double = 4000.0

///|
/// A finger held still this long before it is let go flings nothing (its speed is of moves long past).
pub let swipe_still_ms : Double = 100.0

///|
/// Dark whatever the theme, as a viewer of pictures: its text, what is quieter, its canvas.
pub let dark_text : Int64 = 0xF4F4F5FFL

///|
pub let dark_muted : Int64 = 0xFFFFFF99L

///|
/// The file open, and how far it has got.
pub(all) struct Viewer {
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
  /// how much of it has come while it is read whole, and its whole size where the station says it (FileData.progress)
  mut got : (Double, Double?)?
  mut error : String?
  /// a file told of (not shown): asked for (to save)
  mut asked : Bool
  mut save_after : Bool
  /// a chat's file asked to be downloaded by the core (downloads.mbt), said to it in the next frame
  mut download_asked : Bool
  /// …or to be installed (an APK)
  mut install_after : Bool
  /// the bars shown, and how long they stay when left alone (-1: till a tap), counted anew each time they wake
  mut awake : Bool
  mut rest_len : Double
  mut rest_n : Int
  /// whether they fade when left alone after it opens (not in the fixture's shots, which come when they come)
  mut rests : Bool
  zoom : @kit.Zoom
  vzoom : @kit.Zoom
  /// 源码 rather than 预览
  mut source : Bool
  mut page : @ui.NativeView?
  mut pdf : @ui.Pdf?
  mut text : String?
  /// its words highlighted, a line each (code, or Markdown's source), read once: None until then, Some([]) when not
  mut colored : Array[Array[@ui.Run]]?
  /// whether they were coloured for the dark theme
  mut colored_dark : Bool
  /// the image's key once its bytes are given
  mut image : String
  /// drawn once (its way in set going), closed (only drawn going), how far it has faded in (0 … 1, a motion)
  mut started : Bool
  mut closing : Bool
  fade : @motion.Value
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
  /// a read of the video's file, logged the first times
  mut reads : Int
  /// how a song's player stands, pinned for a fixture's shot
  mut pinned : @kit.MediaStatus?
  /// what it steps through (an image): its chat's images, a folder's
  steps : Stepping
  // a finger's speed sideways (px/ms) and when it was last measured, for a swipe let go
  mut vx : Double
  mut vt : Double
  /// a finger moving it sideways to the one before or after (fitted, not zoomed)
  mut swiping : Bool
  /// where the finger went down
  mut down_x : Double
  mut down_y : Double
  /// zoomed in, its left and its right edge in the stage as the finger went down (a fling on past one goes beside it)
  mut at_left : Bool
  mut at_right : Bool
  /// the finger came down on it flinging, and stopped it there: no tap
  mut caught : Bool
  /// its flight from the chat's thumbnail (or back into it): whether it flies, how far (0 the thumbnail … 1 the
  /// stage, a motion), back or not, from where
  mut flies : Bool
  fly : @motion.Value
  mut fly_back : Bool
  mut fly_from : Thumb?
  /// a video's picture as it flies (its still, or the frame it goes back with)
  mut fly_pic : String
  /// a video opened again: where it was left (ms; -1 from its start), until its player is ready to go on from there
  mut start_at : Double
  /// a video closing into its thumbnail: the frame it shows being grabbed first (what it goes back with), and where
  /// it was then
  mut leaving_grab : Bool
  mut left_at : Double
  /// a desktop's mouse: where it was last frame (its moves wake the bars, preview_desk.mbt), once seen
  mut mouse_x : Double
  mut mouse_y : Double
  mut mouse_seen : Bool
  /// a desktop's song: played in the player a drive's is (play_desk.mbt), not the phone's strip
  mut media : @kit.Media?
  /// a desktop's image put on the clipboard: how many times (its check shown a while after each)
  mut copied : Int
  /// the frame drawing it (the phone's, the desktop's), as it was last drawn
  mut frame : ViewerFrame
}

///|
/// A thumbnail of the chat's the viewer flies from and back into (FilePreview.kt Thumb): where it was drawn (in the
/// window), its corners, the frame its row was last built in.
pub(all) struct Thumb {
  x : Double
  y : Double
  w : Double
  h : Double
  radius : Double
  /// its picture letterboxed in it (ChatFiles.kt imageBox's fit): fitted inside its box, not cropped to it
  letterbox : Bool
  frame : Int
}

///|
/// The chat's thumbnails by the file each shows (Viewer::id), as drawn last.
pub let pv_thumbs : Map[String, Thumb] = Map([])

///|
/// A video closed back into its thumbnail keeps the frame it was left at (FilePreview.kt FileViewers.frames): the
/// thumbnail shows it from then on, and opened again the video goes on from there. By the thumbnail's id (Viewer::id):
/// the frame's image, where it was (ms).
pub let pv_frames : Map[String, (String, Double)] = Map([])

///|
/// How many frames have been kept (each one's image a key of its own).
pub let pv_frames_n : Ref[Int] = { val: 0 }

///|
/// A frame kept is this many pixels at most on its longer side (the station's poster's, posters.ts SIDE).
pub let kept_frame_side : Double = 640.0

///|
/// A chat's video the station made no poster of (one from before posters, or with neither QuickLook nor ffmpeg), small
/// enough to read for it (ChatFiles.kt ChatVideo: BIG_FILE): its first frame drawn here. A player of it made out of
/// sight (never placed), its frame at 0 grabbed, then let go; what it read kept with the chat by the core, as the
/// viewer's reads are. By the thumbnail's id: the player while it grabs, and the frame's image ("" while it comes,
/// "!" none to be had).
pub(all) struct FirstFrame {
  mut view : @ui.NativeView?
  mut picture : String
}

///|
pub let pv_first : Map[String, FirstFrame] = Map([])

///|
/// The first frame of chat video `a` (on `station`, kept by session `key`; `id` its thumbnail's), drawn here where the
/// station made no poster: an image's key once here, "" while it comes or where it is too big to read for it, "!"
/// when it could not be.
pub fn first_frame(c : @ui.Ctx, src : Source, station : String, key : String, a : Attachment, id : String) -> String {
  match pv_first.get(id) {
    Some(f) => {
      match f.view {
        Some(n) => {
          let got = match n.grabbed() {
            Some(png) => Some(png)
            // (no player here, or one that cannot read it: none to be had)
            None => if n.state() == -1 && !n.grabbing() { Some(b"") } else { None }
          }
          match got {
            Some(png) => {
              f.view = None
              if png.length() > 0 {
                let k = "mem:pv-first/\{@ui.stable_hash(id)}/\{id.length()}/\{a.name}"
                @ui.add_image(k, png)
                f.picture = k
              } else {
                f.picture = "!"
              }
              c.tell("pv-first-close/" + id, fn() { n.close() })
            }
            None => ()
          }
        }
        None => ()
      }
      f.picture
    }
    None => {
      if a.size <= 0.0 || a.size > big_file {
        return ""
      }
      let f : FirstFrame = { view: None, picture: "" }
      pv_first[id] = f
      let (_, mime, _) = preview_kind(a.name)
      let n = @ui.NativeView::video(mime, fn(offset, length, answer) {
        let p : Map[String, Json] = {
          "station": Json::string(station),
          "key": Json::string(key),
          "name": Json::string(base_name(a.path)),
          "offset": Json::number(offset),
          "length": Json::number(length.to_double()),
        }
        chat_keep(p, a.size)
        stream_part(src, "station.file.part", p, a.size, answer)
      })
      if !n.here() {
        f.picture = "!"
        return "!"
      }
      f.view = Some(n)
      c.tell("pv-first/" + id, fn() { n.grab_frame(0.0) })
      ""
    }
  }
}

///|
/// The thumbnail hidden while the viewer is its picture (one picture on the screen, never two), by its file's id.
pub let pv_hidden : Ref[String] = { val: "" }

///|
/// A thumbnail of the chat drawn this frame as node `node` (messages.mbt): kept for the viewer to fly from.
pub fn note_thumb(c : @ui.Ctx, id : String, node : Int, radius : Double, letterbox? : Bool = false) -> Unit {
  match c.rect_of(node) {
    Some((x, y, w, h)) if w > 0.0 && h > 0.0 =>
      pv_thumbs[id] = { x, y, w, h, radius, letterbox, frame: c.frame_number() }
    _ =>
      match pv_thumbs.get(id) {
        // under the viewer nothing of the page is hit, so its place is not read back (Ctx::rect_of): where it was
        // last seen, its row still built (the chat under the viewer does not move)
        Some(t) if pv_hidden.val == id || viewer.val is Some(_) || pv_leaving.val is Some(_) =>
          pv_thumbs[id] = { ..t, frame: c.frame_number() }
        _ => pv_thumbs.remove(id)
      }
  }
}

///|
/// How much of the chat's thumbnail `id` shows: none while the viewer is its picture, else all of it.
pub fn thumb_shows(id : String) -> Double {
  if pv_hidden.val == id {
    0.0
  } else {
    1.0
  }
}

///|
/// The thumbnail of `id`, while it is on the screen (drawn in the last frames).
pub fn thumb_of(c : @ui.Ctx, id : String) -> Thumb? {
  match pv_thumbs.get(id) {
    Some(t) if c.frame_number() - t.frame <= 2 => Some(t)
    _ => None
  }
}

///|
/// The viewer grows from the thumbnail this long, and shrinks back into it, on (.2, .8, .2, 1) (FilePreview.kt
/// OPEN_MS, CLOSE_MS, Ease.Arrive).
pub let fly_open_ms : Double = 320.0

///|
pub let fly_close_ms : Double = 280.0

///|
/// The viewer fading in and out where there is no thumbnail to grow from (FilePreview.css.ts fp: 140 ms).
pub let pv_fade_ms : Double = 140.0

///|
/// A zoom gliding to where it was told.
pub let zoom_glide_ms : Double = 260.0

///|
/// Two taps within this long are a double tap.
pub let double_tap_ms : Double = 300.0


///|
/// What an image opened in the viewer steps through (FilePreview.kt Gallery): the images of the chat it is opened from,
/// of which the core tells those beside the one shown (`imageNear`: by the chat's thread, else its session), not the
/// chat's every image; or a folder's of a drive.
pub(all) enum Stepping {
  NoSteps
  InChat(Double?, String)
  InFolder(Array[DriveFile])
}

///|
pub let viewer : Ref[Viewer?] = { val: None }

///|
/// The viewer closed and still drawn going (its fade or its flight back), no longer the one open: closing takes it
/// out of `viewer` at once, and what is under it is the page's again.
pub let pv_leaving : Ref[Viewer?] = { val: None }

///|
/// When the preview's way in or out is over (the frames' clock): the latest end told its fade and its flight, the one
/// open's or the one leaving's; -1 when neither moves. What a test runs to after it opens or closes one.
pub fn preview_rest() -> Double {
  let mut at = -1.0
  for v in [viewer.val, pv_leaving.val] {
    match v {
      Some(v) => {
        if v.fade.ends_at() > at {
          at = v.fade.ends_at()
        }
        if v.fly.ends_at() > at {
          at = v.fly.ends_at()
        }
      }
      None => ()
    }
  }
  at
}

///|
/// Opens `a` of the chat on `station` (kept by the session `key`) over everything; `steps`: what an image steps
/// through.
pub fn open_preview(
  station : String,
  key : String,
  a : Attachment,
  drive? : DriveFile? = None,
  steps? : Stepping = NoSteps,
) -> Unit {
  close_now()
  pv_strip.leaving = None
  viewer.val = Some(new_viewer(station, key, a, drive, steps))
}

///|
/// What draws round a viewer (the phone's frame, sfapp/preview.mbt; the desktop's, sfdesk/viewer.mbt): whether it is
/// the desktop's (its stages laid out as the web's: viewer_desk.mbt), the canvas under what it shows, its bar, the ways
/// to the files before and after, what it says of a file it does not show and while one comes, what goes back to where
/// it was opened, and a text it reads itself (true: drawn).
pub(all) struct ViewerFrame {
  desk : Bool
  canvas : () -> Int64
  bar : (Viewer, @ui.Ctx, Source, Double) -> Unit
  steps : (Viewer, @ui.Ctx, Source, Double) -> Unit
  facts : (Viewer, @ui.Ctx, Source, Json?) -> Unit
  coming : (Viewer, @ui.Ctx) -> Unit
  back : (Viewer, Source) -> String
  read : (Viewer, @ui.Ctx, Source) -> Bool
}

///|
/// A frame of none (a viewer not drawn yet).
// kept across runs: a value (no field of it changes)
pub let viewer_no_frame : ViewerFrame = {
  desk: false,
  canvas: fn() { @sf.theme().p.canvas },
  bar: fn(_, _, _, _) {  },
  steps: fn(_, _, _, _) {  },
  facts: fn(_, _, _, _) {  },
  coming: fn(_, _) {  },
  back: fn(_, _) { @sf.t("common.back") },
  read: fn(_, _, _) { false },
}

///|
/// A viewer of `a` (what it read before, kept, taken at once).
pub fn new_viewer(station : String, key : String, a : Attachment, drive : DriveFile?, steps : Stepping) -> Viewer {
  let (kind, mime, _) = preview_kind(a.name)
  let v : Viewer = {
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
    got: None,
    error: None,
    asked: false,
    save_after: false,
    download_asked: false,
    install_after: false,
    awake: true,
    rest_len: -1.0,
    rest_n: 0,
    rests: true,
    zoom: @kit.Zoom::new(glide_ms=zoom_glide_ms),
    // (a film edge to edge, enlarged, as the player puts it: what it flies to and from)
    vzoom: @kit.Zoom::new(margin=fn(_) { 0.0 }, enlarge=true, glide_ms=zoom_glide_ms),
    source: false,
    page: None,
    pdf: None,
    text: None,
    colored: None,
    colored_dark: false,
    image: "",
    started: false,
    closing: false,
    fade: @motion.Value::new(0.0),
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
    reads: 0,
    pinned: None,
    steps,
    vx: 0.0,
    vt: -1.0,
    swiping: false,
    down_x: 0.0,
    down_y: 0.0,
    at_left: false,
    at_right: false,
    caught: false,
    flies: false,
    fly: @motion.Value::new(0.0),
    fly_back: false,
    fly_from: None,
    fly_pic: "",
    start_at: match pv_frames.get(station + "/" + key + "/" + a.path) {
      Some((_, ms)) if drive is None && ms > 0.0 => ms
      _ => -1.0
    },
    leaving_grab: false,
    left_at: 0.0,
    mouse_x: 0.0,
    mouse_y: 0.0,
    mouse_seen: false,
    media: None,
    copied: 0,
    frame: viewer_no_frame,
  }
  v.bytes = kept_read(v.id())
  v
}

///|
/// The file's own id: its station, the session that keeps it (or the drive's root), its path.
pub fn Viewer::id(self : Viewer) -> String {
  match self.drive {
    Some(d) => self.station + "/drive:" + d.root + "/" + d.path
    None => self.station + "/" + self.key + "/" + self.file.path
  }
}

///|
/// Whole files the viewer read (the one shown and those beside it, read ahead so a step shows the next at once), the
/// latest few.
pub let pv_read : Array[(String, Bytes)] = []

///|
pub fn kept_read(id : String) -> Bytes? {
  for x in pv_read {
    if x.0 == id {
      return Some(x.1)
    }
  }
  None
}

///|
pub fn keep_read(id : String, b : Bytes) -> Unit {
  pv_read.retain(fn(x) { x.0 != id })
  pv_read.push((id, b))
  if pv_read.length() > 5 {
    pv_read.remove(0) |> ignore
  }
}

///|
/// The images stepped through slide this far apart (FilePreview.kt SLIDE_GAP), on SLIDE (critically damped, 400).
pub let slide_gap : Double = 24.0

///|
/// The one going as the next comes: its picture where it was (x, y, w, h), moving out to the side away from `dir`,
/// `width` (the stage's and the gap) apart.
pub(all) struct Leaving {
  picture : String
  x : Double
  y : Double
  w : Double
  h : Double
  dir : Int
  width : Double
}

///|
pub(all) struct Strip {
  mut leaving : Leaving?
  /// where the strip is held for a fixture's shot (a swipe halfway), else None
  mut pinned : Double?
  /// the viewers of the images beside the one shown (by their ids), read ahead
  near : Map[String, Viewer]
}

///|
pub let pv_strip : Strip = { leaving: None, pinned: None, near: Map([]) }

///|
/// The images beside one asked of the core (`imageNear`), each by its params: let go with the chat they are of
/// (chat_left), as they hold its thread there.
pub let near_asked : Map[String, Map[String, Json]] = {}

///|
/// The images beside those of `station`'s chats let go (a chat of it left).
pub fn near_left(src : Source, station : String) -> Unit {
  let gone = []
  near_asked.each(fn(k, p) {
    if p.get("station") == Some(Json::string(station)) {
      gone.push(k)
      (src.leave)("imageNear", p)
    }
  })
  for k in gone {
    near_asked.remove(k)
  }
}

///|
/// The viewer gone at once (the one open and the one going), what it holds let go (its player stopped, its page and
/// PDF closed).
pub fn close_now() -> Unit {
  marks_leave()
  match viewer.val {
    Some(v) => v.let_go()
    None => ()
  }
  viewer.val = None
  leaving_done()
}

///|
/// The viewer that was going, gone.
pub fn leaving_done() -> Unit {
  match pv_leaving.val {
    Some(v) => v.let_go()
    None => ()
  }
  pv_leaving.val = None
}

///|
/// What a viewer holds of the host's, let go.
pub fn Viewer::let_go(self : Viewer) -> Unit {
  // read in a desktop's reader (@sf.reader): what it read let go with it
  @sf.reader_let_go("chat\n" + self.id())
  match self.media {
    Some(m) => {
      m.close()
      @sf.player_view_let_go(m.key())
    }
    None => ()
  }
  match self.page {
    Some(n) => n.close()
    None => ()
  }
  match self.pdf {
    Some(p) => p.close()
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
pub fn Viewer::shown_kind(self : Viewer) -> PKind? {
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
pub fn Viewer::told_of(self : Viewer) -> Bool {
  match self.shown_kind() {
    Some(KVideo) | Some(KAudio) | Some(KPdf) => false
    None => self.kind is None && self.sniffed is Some(_)
    Some(_) => self.file.size > big_file
  }
}

///|
pub fn Viewer::dark(self : Viewer) -> Bool {
  // a desktop's: on the page's own canvas whatever it shows (FilePreview.css.ts fp)
  if self.frame.desk {
    return false
  }
  match self.shown_kind() {
    Some(KImage) | Some(KVideo) => true
    _ => false
  }
}

// ── reading it through the core ────────────────────────────────────────

///|
pub fn file_params(v : Viewer) -> Map[String, Json] {
  {
    "station": Json::string(v.station),
    "key": Json::string(v.key),
    "name": Json::string(v.name),
  }
}

///|
/// The call a part of it is read by: a chat's file `station.file.part`, a drive's `drive.read`.
pub fn Viewer::part_call(self : Viewer) -> String {
  if self.drive is Some(_) {
    "drive.read"
  } else {
    "station.file.part"
  }
}

///|
/// `length` bytes of it from `offset` (fewer at its end), and its whole size as the station says (in the answer's
/// `total`). A drive's kept on the device as `keep` (drive_keep: `file` read from its start, `played` a video's or
/// song's ranges), as its folder lists it; a chat's video or song as played, with its chat (chat_keep).
pub fn Viewer::read_part(
  self : Viewer,
  src : Source,
  offset : Double,
  length : Int,
  keep : String,
  done : (Result[(Json, Bytes), Json]) -> Unit,
) -> Unit {
  (src.read_bytes)(self.part_call(), Json::object(self.part_params(offset, length, keep)), done)
}

///|
/// What a part of it is asked by: `length` bytes from `offset`, kept as `keep` (Viewer::read_part).
pub fn Viewer::part_params(self : Viewer, offset : Double, length : Int, keep : String) -> Map[String, Json] {
  let p = match self.drive {
    Some(d) => {
      let p : Map[String, Json] = {
        "station": Json::string(d.station),
        "root": Json::string(d.root),
        "path": Json::string(d.path),
      }
      drive_keep(p, keep, d.mtime, d.size)
      p
    }
    None => {
      let p = file_params(self)
      if keep == "played" {
        chat_keep(p, self.file.size)
      }
      p
    }
  }
  p["offset"] = Json::number(offset)
  p["length"] = Json::number(length.to_double())
  p
}

///|
/// Its size as its message or its folder says it (0: not known).
pub fn Viewer::listed_size(self : Viewer) -> Double {
  match self.drive {
    Some(d) => d.size
    None => self.file.size
  }
}

///|
/// A part read for the player (`call` with `p`), its bytes handed on as they come (the core's part read with
/// `stream`: each piece as it arrives, never the whole part waited for), as a player's read takes them:
/// `answer(bytes, total, more)`, the whole's size as `size` says it (its message's, its folder's; 0 not known) until
/// the core's answer says it. `ended` hears how it ended: the bytes it brought, or why it failed. What it gives back
/// stops it (the core's read let go of: nothing more of it comes over the network).
pub fn stream_part(
  src : Source,
  call : String,
  p : Map[String, Json],
  size : Double,
  answer : (Bytes, Double, Bool) -> Unit,
  ended? : (Result[Int, Json]) -> Unit = fn(_) {  },
) -> () -> Unit {
  p["stream"] = Json::boolean(true)
  let known = if size > 0.0 { size } else { -1.0 }
  let got = Ref(0)
  let id = (src.stream)(
    call,
    Json::object(p),
    None,
    fn(_, bytes) {
      match bytes {
        Some(b) if b.length() > 0 => {
          got.val += b.length()
          answer(b, known, true)
        }
        _ => ()
      }
    },
    fn(r) {
      match r {
        Ok(said) => {
          ended(Ok(got.val))
          answer(
            b"",
            match field(Some(said), "total") {
              Some(Number(t, ..)) => t
              _ => known
            },
            false,
          )
        }
        Err(e) => {
          ended(Err(e))
          answer(b"", -2.0, false)
        }
      }
    },
  )
  fn() { (src.cancel)(id) }
}

///|
/// A chat's file read through the core kept on the device with its chat, and answered from there when it is kept (the
/// core's drive-kept.ts `chat`), as Android keeps those its viewers open on the phone's disk (ChatFiles.kt toDisk,
/// onDisk), by its size as its message says (none known: not kept).
pub fn chat_keep(p : Map[String, Json], size : Double) -> Unit {
  if size > 0.0 {
    p["keep"] = Json::boolean(true)
    p["size"] = Json::number(size)
  }
}

///|
/// Whether a chat's file read whole is kept with its chat: what Android's viewers read off the disk (a PDF, a video,
/// a song) and a big one (FilePreview.kt: OnDisk, toDisk past BIG_FILE); others are held in memory only.
pub fn Viewer::kept_whole(self : Viewer) -> Bool {
  match self.shown_kind() {
    Some(KPdf) | Some(KVideo) | Some(KAudio) => true
    _ => self.file.size > big_file
  }
}

///|
/// The whole of it: a chat's in one `station.file`; a drive's a part (4 MB) at a time, as its reader reads.
pub fn Viewer::read_whole(self : Viewer, src : Source, done : (Result[Bytes, Json]) -> Unit) -> Unit {
  let done = fn(r) {
    self.got = None
    done(r)
  }
  match self.drive {
    // an image as it comes: grown from its thumbnail, nothing said of how far it has got (as Android's ImageStage)
    None if self.shown_kind() == Some(KImage) && self.file.size <= big_file =>
      (src.read_bytes)("station.file", Json::object(file_params(self)), fn(r) {
        match r {
          Ok((_, bytes)) => done(Ok(bytes))
          Err(e) => done(Err(e))
        }
      })
    // what else: how much has come as it comes (ChatFiles.kt fetch: `progress`, the core's `{loaded, total}`)
    None => {
      let p = file_params(self)
      p["progress"] = Json::boolean(true)
      if self.kept_whole() {
        chat_keep(p, self.file.size)
      }
      (src.read_going)(
        "station.file",
        Json::object(p),
        fn(v) {
          match field(Some(v), "loaded") {
            Some(Number(n, ..)) =>
              self.got = Some(
                (
                  n,
                  match field(Some(v), "total") {
                    Some(Number(t, ..)) => Some(t)
                    _ => None
                  },
                ),
              )
            _ => ()
          }
        },
        fn(r) {
          match r {
            Ok((_, bytes)) => done(Ok(bytes))
            Err(e) => done(Err(e))
          }
        },
      )
    }
    Some(_) => {
      let parts : Array[Bytes] = []
      let got : Ref[Int] = { val: 0 }
      fn next() {
        self.read_part(src, got.val.to_double(), drive_part, "file", fn(r) {
          match r {
            Ok((answer, bytes)) => {
              let total = match field(Some(answer), "total") {
                Some(Number(n, ..)) => n.to_int()
                _ => got.val + bytes.length()
              }
              parts.push(bytes)
              got.val += bytes.length()
              self.got = Some((got.val.to_double(), Some(total.to_double())))
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
pub fn Viewer::fetch(self : Viewer, c : @ui.Ctx, src : Source) -> Unit {
  let v = self
  // (each asked once a viewer, by its file: nothing a build changes)
  if v.kind is None && v.sniffed is None && !v.sniffing {
    v.sniffing = true
    v.read_part(src, 0.0, 8192, "file", fn(r) {
      v.sniffing = false
      v.sniffed = Some(
        match r {
          Ok((_, bytes)) => @codec.looks_like_text(bytes)
          // a station from before parts cannot say: told of, as anything else not shown
          Err(_) => false
        },
      )
    })
    return
  }
  match v.shown_kind() {
    // a film or a song: the one player (@sf.player_view), read through the core a part at a time (never the whole file
    // first, a seek far ahead one more ranged read), from the frame it was left at (the thumbnail's)
    Some(KVideo) | Some(KAudio) => {
      if v.media is None {
        let m = @sf.new_media("preview-media", rest_ms=if bars_rest() { @kit.media_rest_ms } else { 0.0 })
        let start = if v.start_at > 0.0 { v.start_at } else { 0.0 }
        v.start_at = -1.0
        m.open(
          {
            name: v.file.name,
            mime: v.mime,
            audio: v.shown_kind() == Some(KAudio),
            read: fn(offset, length, answer) {
              stream_part(src, v.part_call(), v.part_params(offset, length, "played"), v.listed_size(), answer, ended=fn(r) {
                match r {
                  Ok(bytes) => {
                    if v.reads < 3 {
                      @ui.log("preview: \{v.name} @\{offset.to_int()} \{bytes} bytes through the core (\{v.part_call()})")
                    }
                    v.reads += 1
                  }
                  Err(e) => @ui.log("preview: \{v.name} @\{offset.to_int()} failed: \{e.stringify()}")
                }
              })
            },
          },
          start~,
        )
        v.media = Some(m)
      }
      // played as it comes: read whole only once asked to be saved (the player's 下载)
      if !v.asked {
        return
      }
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
          keep_read(v.id(), bytes)
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
/// ASCII letters in capitals.
pub fn upper(s : String) -> String {
  let sb = StringBuilder()
  for ch in s {
    let k = ch.to_int()
    sb.write_char(if k >= 97 && k <= 122 { (k - 32).unsafe_to_char() } else { ch })
  }
  sb.to_string()
}

// ── the viewer ─────────────────────────────────────────────────────────

///|
/// The viewer over the pages, if one is open, in `frame` (the phone's, sfapp/preview.mbt; the desktop's,
/// sfdesk/viewer.mbt): call after the pages are drawn.
pub fn viewer_layer(c : @ui.Ctx, src : Source, frame : ViewerFrame) -> Unit {
  let v = match viewer.val {
    Some(v) => v
    None =>
      match pv_leaving.val {
        Some(v) => v
        None => return
      }
  }
  v.frame = frame
  if !v.started {
    v.started = true
    v.rest_n += 1
    v.rest_len = if v.rests && bars_rest() { rest_ms } else { -1.0 }
    // it comes up in the keyboard's place: what was being typed into lets go of it first
    c.blur()
    // an image grows from its thumbnail when the chat shows it and its size is known here (FilePreview.kt ViewerLayer)
    match v.flight_target(c, src) {
      Some(_) =>
        match thumb_of(c, v.id()) {
          Some(t) => {
            v.flies = true
            v.fly_back = false
            v.fly_from = Some(t)
            // a video's: its still (the frame it was left at, else the station's poster), the black where it has none
            if v.shown_kind() == Some(KVideo) {
              v.fly_pic = v.still(src)
            }
            v.fly.set(0.0)
            ignore(v.fly.start(1.0, @motion.tween(fly_open_ms, ease=Arrive)))
            pv_hidden.val = v.id()
          }
          None => ()
        }
      None => ()
    }
    // as web's: fading in (FilePreview.css.ts fp: 140 ms ease-out), when there is no thumbnail to grow from
    if !v.flies {
      ignore(v.fade.start(1.0, @motion.tween(pv_fade_ms, ease=Out)))
    } else {
      v.fade.set(1.0)
    }
  }
  src_now.val = src.now
  v.marks_frame(c)
  let p = v.flying()
  // (the motions ask for their frames, said once as they set out: the flight, the fade)
  let landed = v.flies && v.fly_back && !v.fly.is_animating()
  // (landed by the frame's time, the same in each build of the frame; what is let go is the viewer going, built
  // no more)
  if landed {
    // landed in its thumbnail: drawn there this once (where the thumbnail is, hidden this frame), then gone
    leaving_done()
    pv_hidden.val = ""
  }
  if v.flies && !v.fly_back && !v.fly.is_animating() {
    v.flies = false
    pv_hidden.val = ""
  }
  let faded = if v.flies { 1.0 } else { v.fade.get() }
  // (faded by the frame's time: the same in each build of the frame)
  // a video closing into its thumbnail: the frame it shows, once grabbed, kept and gone back with
  if v.leaving_grab {
    v.left_with_frame(c, src)
  }
  if v.closing && !v.flies && !v.leaving_grab && !v.fade.is_animating() {
    // faded out: gone
    leaving_done()
    return
  }
  // the ground and the bars: with the flight, or fading
  let shown = if v.flies { p } else { faded }
  v.fetch(c, src)
  // asked for to be saved, and come: saved
  if v.save_after && v.bytes is Some(_) {
    v.save_after = false
    v.ask_save(c)
  }
  if v.install_after && v.bytes is Some(_) {
    v.install_after = false
    v.ask_install(c)
  }
  // the bars fade when left alone (not while it comes, nor over a page whose taps are its own)
  if v.awake && v.rest_len > 0.0 && @kit.after(c, "pv-rest/\{v.rest_n}", true, v.rest_len) {
    v.awake = false
  }
  let t = @sf.theme()
  let kind = v.shown_kind()
  let dark = v.dark()
  let ground = if dark {
    0x000000FFL
  } else if kind == Some(KPdf) {
    @sf.mix(t.p.text, 0.05, t.p.bg)
  } else {
    (frame.canvas)()
  }
  // a film or a song: the player's own page (its bars, its controls, what a finger does on it)
  let media = kind == Some(KVideo) || kind == Some(KAudio)
  c.layer(fn() {
    let stage = c.id("preview/stage")
    if !media {
      @ui.capture(c, stage)
    }
    c.box(w=Fill(1.0), h=Fill(1.0), bg=@sf.alpha(ground, shown), opacity=faded, id=stage, fn() {
      v.content(c, src, stage)
    })
    |> ignore
    if !marking.on {
      c.layer(fn() { (frame.steps)(v, c, src, shown) }) |> ignore
    } else {
      c.layer(fn() {
        c.spacer()
        // over the navigation bar (FilePreview.kt MarksFoot)
        marks_foot(c)
        let nav = (@sf.viewer_host().room)().1
        if nav > 0.0 {
          c.box(style=@ui.style(w=Full, h=Fixed(nav)), fn() {  }) |> ignore
        }
      })
      |> ignore
    }
    if !media {
      c.layer(fn() { (frame.bar)(v, c, src, shown) }) |> ignore
    }
  })
  |> ignore
  // 下载 tapped (on the page or its bar, just built): asked of the core, on by itself whatever becomes of this viewer
  // (told once the frame's builds are over, as the tap is the build's that took it)
  if v.download_asked {
    v.download_asked = false
    let (station, key, name, size) = (v.station, v.key, v.name, v.file.size)
    c.tell("download/" + name, fn() { download_start(src, station, key, name, size) })
  }
  // (one going takes back no more: it is the page's)
  if !v.closing {
    c.take_back(fn() { if marking.on { marks_back(c) } else { v.shut(c) } })
  }
}

///|
pub fn Viewer::shut(self : Viewer, c : @ui.Ctx) -> Unit {
  if !self.closing {
    self.closing = true
    // closed at once: the one going is only drawn (what was going before it, gone)
    marks_leave()
    leaving_done()
    viewer.val = None
    pv_leaving.val = Some(self)
    // an image shrinks back into its thumbnail when the chat shows it (from where a flight in has got to), else
    // it fades out
    match (thumb_of(c, self.id()), self.shown_kind(), self.zoom.rect()) {
      (Some(t), Some(KImage), Some(_)) => {
        let p = self.flying()
        self.fly_from = Some(t)
        self.fly_back = true
        if !self.flies {
          self.flies = true
          self.fly.set(1.0)
        }
        // as far along as it was: back from there, in as much of its time
        ignore(self.fly.start(0.0, @motion.tween(dmax(1.0, fly_close_ms * p), ease=Arrive)))
        pv_hidden.val = self.id()
      }
      // a video, its thumbnail on the screen: back into it with the frame it shows (grabbed first: the thumbnail keeps
      // it, and where it was), else with its still (FilePreview.kt close: flight.frame())
      (Some(t), Some(KVideo), _) if self.drive is None && self.vzoom.rect() is Some(_) => {
        self.fly_from = Some(t)
        match self.view() {
          Some(n) if n.here() && n.shown() && !n.grabbing() => {
            self.leaving_grab = true
            self.left_at = n.position()
            c.tell("preview-grab", fn() { n.grab_shown(kept_frame_side) })
          }
          _ => self.fly_home("")
        }
      }
      // the way in played backwards (web's fp: ease-out on the way in, the same curve run back on the way out): the
      // ground and the picture stay nearly whole at first, then go
      _ => ignore(self.fade.start(0.0, @motion.tween(pv_fade_ms, ease=Bezier(0.8, 0.0, 0.8, 0.3))))
    }
    // the views under the canvas go at once (they cannot fade)
    match self.view() {
      // (once the frame's builds are over: closed as the back is taken or the marks are put, once)
      Some(n) => c.tell("preview-pause", fn() { n.pause() })
      None => ()
    }
  }
}

///|
/// A video back into its thumbnail with `picture` (from where a flight in has got to, in as much of its time).
pub fn Viewer::fly_home(self : Viewer, picture : String) -> Unit {
  let p = self.flying()
  self.fly_pic = picture
  self.fly_back = true
  if !self.flies {
    self.flies = true
    self.fly.set(1.0)
  }
  ignore(self.fly.start(0.0, @motion.tween(dmax(1.0, fly_close_ms * p), ease=Arrive)))
  pv_hidden.val = self.id()
}

///|
/// A video closing into its thumbnail, its frame grabbed: once here, kept for the thumbnail (with where it was) and
/// gone back with; none to be had, back with its still.
pub fn Viewer::left_with_frame(self : Viewer, c : @ui.Ctx, src : Source) -> Unit {
  let n = match self.view() {
    Some(n) => n
    None => {
      self.leaving_grab = false
      self.fly_home(self.still(src))
      return
    }
  }
  match n.grabbed() {
    Some(jpeg) => {
      self.leaving_grab = false
      if jpeg.length() > 0 {
        pv_frames_n.val += 1
        let key = "mem:pv-frame/\{pv_frames_n.val}/\{self.name}"
        @ui.add_image(key, jpeg)
        pv_frames[self.id()] = (key, self.left_at)
        self.fly_home(key)
      } else {
        self.fly_home(self.still(src))
      }
    }
    None => ()
  }
  ignore(c)
}

///|
/// A tap on the stage shows or hides the bars.
pub fn Viewer::toggle(self : Viewer) -> Unit {
  if self.awake {
    self.awake = false
    self.rest_len = -1.0
  } else {
    self.wake(tap_rest_ms)
  }
}

///|
pub fn Viewer::wake(self : Viewer, ms : Double) -> Unit {
  self.awake = true
  self.rest_n += 1
  self.rest_len = if bars_rest() { ms } else { -1.0 }
}

///|
/// Whether the bars fade when left alone: not in a scripted run that says so (MBUI_VIEWER_AWAKE=1: on a slow
/// emulator a flow's next step can outlast their rest), where only a tap hides them.
pub fn bars_rest() -> Bool {
  if viewer_awake_env.val < 0 {
    viewer_awake_env.val = if @ui.env("MBUI_VIEWER_AWAKE") == "1" { 1 } else { 0 }
  }
  viewer_awake_env.val == 0
}

///|
pub let viewer_awake_env : Ref[Int] = { val: -1 }

///|
/// Whether the bars show: awake, or while the whole of an image comes, or over a page whose taps are its own.
pub fn Viewer::bars_shown(self : Viewer) -> Bool {
  self.awake || self.coming() || (self.shown_kind() == Some(KHtml) && !self.source) || marking.on
}

///|
/// The chat's draft a marked image of this one goes into (its chat's: the session it was opened from), "" none (a
/// drive's picture).
pub fn Viewer::draft_key(self : Viewer) -> String {
  match self.steps {
    InChat(_, session) if session != "" && self.drive is None => self.station + ":" + session
    _ => ""
  }
}

///|
/// The marked image asked for: drawn by the host at the picture's own size (marks.mbt), then downloaded or put in the
/// chat's draft with a quote per numbered mark (ImageMarks.kt finish).
pub fn Viewer::finish_marks(self : Viewer, c : @ui.Ctx, to_draft : Bool) -> Unit {
  let bytes = match self.bytes {
    Some(b) => b
    None => return
  }
  marks_put_down(c)
  let z = self.zoom
  match @ui.draw_marks(bytes, marks_json(z.nw, z.nh)) {
    Some(j) => {
      marking.job = Some(j)
      marking.busy = true
      marking.error = ""
      marking.to_draft = to_draft
      let base = match self.file.name.rev_find(".") {
        Some(i) if i > 0 => self.file.name.view(end_offset=i).to_owned()
        _ => self.file.name
      }
      let stamp = clock_stamp((src_now.val)())
      marking.job_name = pv_fill("android-chat.file.marked.name", [("name", base), ("stamp", stamp)])
    }
    None => marking.error = pv("android-chat.file.drawFailed")
  }
}



///|
/// A marked image drawn by the host, come: kept, or into the chat's draft (the viewer closes back to it).
pub fn Viewer::marks_frame(self : Viewer, c : @ui.Ctx) -> Unit {
  match marking.job {
    Some(j) =>
      match j.made() {
        Some(png) => {
          marking.job = None
          marking.busy = false
          if png.length() == 0 {
            marking.error = pv("android-chat.file.drawFailed")
          } else if marking.to_draft {
            let z = self.zoom
            let quotes = marks_quotes(marking.job_name, self.file.name, z.nw, z.nh)
            let key = self.draft_key()
            let list = marked_into.get(key).unwrap_or([])
            list.push((marking.job_name, png, quotes, "image"))
            marked_into[key] = list
            marks_leave()
            say(c, pv("android-chat.preview.put.done"))
            self.shut(c)
          } else {
            // (the host's picture of the marks, said once)
            keep_bytes(c, marking.job_name, "image/png", png)
          }
        }
        // (drawn on the host's side: its word that it is done brings the frame that takes it)
        None => ()
      }
    None => ()
  }
}

///|
/// An image still coming (its thumbnail in its place meanwhile).
pub fn Viewer::coming(self : Viewer) -> Bool {
  self.shown_kind() == Some(KImage) && self.bytes is None && self.error is None
}

///|
/// The stage: what the file shows as.
pub fn Viewer::content(self : Viewer, c : @ui.Ctx, src : Source, stage : Int) -> Unit {
  let v = self
  let kind = v.shown_kind()
  match kind {
    Some(KImage) if v.file.size <= big_file => v.image_stage(c, src, stage)
    Some(KVideo) | Some(KAudio) => v.player_stage(c, src, stage)
    _ =>
      if (v.frame.read)(v, c, src) {
        // (read by the frame: a desktop's text and Markdown in the reader, as a drive's are)
        ()
      } else if v.told_of() {
        let dl = v.download(src)
        v.note(c, fn() { (v.frame.facts)(v, c, src, dl) })
      } else if (v.kind is None && v.sniffed is None) || (v.bytes is None && v.error is None) {
        tap_stage(c, v, stage)
        v.note(c, fn() { (v.frame.coming)(v, c) })
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
pub fn tap_stage(c : @ui.Ctx, v : Viewer, stage : Int) -> Unit {
  if c.clicked(stage) {
    v.toggle()
  }
}

///|
/// A note in the middle of the stage (FilePreview.kt Note): 24 round it, what it holds 14 apart.
pub fn Viewer::note(self : Viewer, c : @ui.Ctx, body : () -> Unit) -> Unit {
  ignore(self)
  c.box(w=Fill(1.0), h=Fill(1.0), pad=24.0, gap=14.0, align=ACenter, justify=JCenter, fn() { body() })
  |> ignore
}

///|
/// A wait (ui/Waiting.kt WaitPill): a spinner and its words on the chip's ground, round.
pub fn reading_pill(c : @ui.Ctx, words : String) -> Unit {
  c.box(style=reading_pill_box, fn() {
    @sf.spinner(c, size=reading_spinner) |> ignore
    c.text(words, style=reading_pill_words) |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
pub let reading_pill_box : @ui.Style = @ui.css("row px=S3 py=S1_5 gap=S2 align=ACenter bg=Neutral radius=Full")

///|
// kept across runs: a value (no field of it changes)
pub let reading_pill_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, leading=L5, wrap=false)

///|
pub let reading_spinner : Double = 12.0

///|
/// How much of a file has come, out of its size, the station's else the one sent with it (FilePreview.kt
/// FileProgress): "正在读取 **4 MB** / 12 MB" over a bar, on the surface (surface2 dark), 14 round, 14 and 12 in, 220
/// wide; its size not known, 正在读取 over a bar that sweeps. `said`: other words in its words' place (the core's of a
/// download: 正在下载 42% · 18.3 MB, FilePreview.tsx DownloadComing).
pub fn file_progress(c : @ui.Ctx, got : (Double, Double?), sent : Double, said? : String) -> Unit {
  let t = @sf.theme()
  let total = match got.1 {
    Some(n) => Some(n)
    None => if sent > 0.0 { Some(sent) } else { None }
  }
  let part = match total {
    Some(n) if n > 0.0 => Some(dmin(1.0, got.0 / n))
    _ => None
  }
  c.box(style=file_progress_card, radius=file_progress_corner, bg=if t.dark { surface2_dark } else { t.p.card }, fn() {
    match (said, total) {
      (Some(words), _) => c.text(words, style=file_progress_words) |> ignore
      (None, Some(n)) => {
        // the size so far in bold, where the sentence has it
        let words = pv("android-chat.file.loading.size")
        let (before, after) = match words.find("{size}") {
          Some(i) => (words.view(end_offset=i).to_owned(), words.view(start_offset=i + 6).to_owned())
          None => (words, "")
        }
        c.rich(
          [
            @ui.span(before),
            @ui.span(@sf.file_size(got.0), weight=600, color=t.p.text),
            @ui.span(" / " + @sf.file_size(n) + after),
          ],
          style=file_progress_words,
        )
        |> ignore
      }
      (None, None) => c.text(pv("common.reading"), style=file_progress_words) |> ignore
    }
    @sf.progress(c, part)
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
pub let file_progress_card : @ui.Style = @ui.style(w=@sf.file_progress_w, px=S3_5, py=S3, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
pub let file_progress_words : @ui.TextStyle = @ui.text_style(size=Lg, color=Muted, center=true)

///|
pub let file_progress_corner : Double = 14.0

///|
/// Android's C.surface2, dark (Theme.kt), what a file's progress is on
pub let surface2_dark : Int64 = 0x2C2D31FFL

///|
/// 安装: an APK handed to the system's installer, which asks the person to confirm (FilePreview.kt install), once
/// its bytes are here (fetched first when it was only told of). What the system says of it comes later (app.mbt
/// system_said): the leave to install apps asked for (its page opened), 允许 still.fail 安装应用后，再次点击安装; a
/// failure, 无法安装：….
pub fn Viewer::ask_install(self : Viewer, c : @ui.Ctx) -> Unit {
  match self.bytes {
    Some(b) => {
      let name = self.file.name
      // (handed to the host once the frame's builds are over: its bytes, given once)
      c.tell("install/" + name, fn() { @ui.install_package(name, b) })
    }
    None => {
      self.error = None
      self.asked = true
      self.install_after = true
    }
  }
}

///|
/// 下载: the file into the system's downloads, once it is here. A chat's not read yet is downloaded by the core
/// (downloads.mbt): on by itself whatever becomes of this viewer, how far it has come said here and on its message,
/// kept once it is all here; a drive's is fetched first.
pub fn Viewer::ask_save(self : Viewer, c : @ui.Ctx) -> Unit {
  match self.bytes {
    // kept where the system keeps downloads, said once the host has answered (keep.mbt)
    Some(b) => keep_bytes(c, self.file.name, self.mime, b)
    None if self.drive is None => self.download_asked = true
    None => {
      self.error = None
      self.asked = true
      self.save_after = true
    }
  }
}

///|
/// The core's download of this chat's file while it is listed (under way, ready, failed): None for a drive's.
pub fn Viewer::download(self : Viewer, src : Source) -> Json? {
  if self.drive is Some(_) {
    return None
  }
  download_of(src, self.station, self.key, self.name)
}

///|
/// Whether the core has the download `dl` under way (going, waiting for its station, ready, being saved).
pub fn downloading(dl : Json?) -> Bool {
  flag(dl, "active")
}

///|
/// The core's download of the file this viewer shows called off (✕ under how far it has come).
pub fn Viewer::cancel_download(self : Viewer, c : @ui.Ctx, src : Source, dl : Json?) -> Unit {
  ignore(self)
  let id = text(dl, "id")
  // (told once the frame's builds are over, as the tap is the build's that took it)
  c.tell("download-cancel/" + id, fn() { download_cancel(src, id) })
}

// ── an image ───────────────────────────────────────────────────────────

///|
/// How far its flight has got (0 the thumbnail, 1 the stage), on (.2, .8, .2, 1); 1 when it is not flying.
pub fn Viewer::flying(self : Viewer) -> Double {
  if !self.flies {
    return 1.0
  }
  self.fly.get()
}

///|
/// Where the picture is on the stage when it is still (fitted), once its size is known here.
pub fn Viewer::flight_target(self : Viewer, c : @ui.Ctx, src : Source) -> (Double, Double, Double, Double)? {
  if self.drive is Some(_) {
    return None
  }
  // a video: where its picture will be, by its size as sent, else its still's (FilePreview.kt: known from the still
  // before the player is ready); none known, it fades in
  if self.shown_kind() == Some(KVideo) {
    let still = self.still(src)
    let (nw, nh) = if self.file.width > 0.0 && self.file.height > 0.0 {
      (self.file.width, self.file.height)
    } else if still != "" {
      @ui.image_natural(still).unwrap_or((0.0, 0.0))
    } else {
      (0.0, 0.0)
    }
    return match self.vzoom.rect() {
      Some(r) => Some(r)
      None => fitted_rect(nw, nh, c.width, c.height)
    }
  }
  if self.shown_kind() != Some(KImage) {
    return None
  }
  let picture = self.picture(src)
  if picture == "" {
    return None
  }
  let (nw, nh) = self.natural_size(picture)
  match self.zoom.rect() {
    Some(r) => Some(r)
    None => fitted_rect(nw, nh, c.width, c.height)
  }
}

///|
/// What flies: the picture once it is decoded, until then the chat's thumbnail it grows from (the same picture, already
/// on the screen: no frame where the thumbnail's place is empty).
pub fn Viewer::flight_picture(self : Viewer, src : Source, picture : String) -> String {
  if @ui.image_state(picture) == 1 {
    return picture
  }
  let thumb = if self.drive is Some(_) { "" } else { (src.file)(self.station, self.key, self.name) }
  if thumb != "" && thumb != "!" {
    thumb
  } else {
    picture
  }
}

///|
/// The picture in flight (FilePreview.kt viewerFlying): a box from the thumbnail's to the picture's place, its corners
/// from the thumbnail's to none, the picture covering it (cropped as the chat crops it at the start, whole at the end).
pub fn Viewer::draw_flight(
  self : Viewer,
  c : @ui.Ctx,
  picture : String,
  to : (Double, Double, Double, Double),
  p : Double,
  ground? : Int64 = 0L,
) -> Unit {
  let from = match self.fly_from {
    Some(t) => t
    None => return
  }
  let (tx, ty, tw, th) = to
  // a picture letterboxed in its thumbnail flies from where it shows there, fitted inside the box (FilePreview.kt
  // fitted)
  let (fx, fy, fw, fh) = if from.letterbox && tw > 0.0 && th > 0.0 {
    let k = dmin(from.w / tw, from.h / th)
    (from.x + (from.w - tw * k) / 2.0, from.y + (from.h - th * k) / 2.0, tw * k, th * k)
  } else {
    (from.x, from.y, from.w, from.h)
  }
  let x = fx + (tx - fx) * p
  let y = fy + (ty - fy) * p
  let w = fw + (tw - fw) * p
  let h = fh + (th - fh) * p
  let r = from.radius * (1.0 - p)
  c.layer(fn() {
    c.box(w=Px(w), h=Px(h), tx=x, ty=y, radius=r, clip=true, bg=ground, fn() {
      if picture != "" {
        c.image(picture, w=Px(w), h=Px(h), fit=FitCover, radius=r, bg=0L, fade=false) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// An image fitted to the stage, to double-tap, pan and zoom (the wheel, the bar's − and +); until the whole of it
/// comes, the chat's thumbnail (or its likeness) stands in its place.
pub fn Viewer::image_stage(self : Viewer, c : @ui.Ctx, src : Source, stage : Int) -> Unit {
  let v = self
  let picture = v.picture(src)
  if v.image != "" && @ui.image_state(v.image) == -1 {
    tap_stage(c, v, stage)
    v.note(c, fn() {
      c.text(pv("android-chat.file.image.failed"), size=15.0, color=dark_muted) |> ignore
    })
    return
  }
  // its size: as sent, else as decoded
  let (nw, nh) = v.natural_size(picture)
  let z = v.zoom
  // the keyboard over the stage, not the stage made shorter for it (FilePreview.kt: the zoom's box is the window's)
  let ime = c.ime_inset()
  z.boxed(c.width, c.height + ime)
  z.natural(nw, nh)
  z.step()
  // lifted while the keyboard is up, as far as keeps what is being written (or the open note's pin, its box under it)
  // 24 clear of it (FilePreview.kt lift: animateFloatAsState's spring)
  let below = match marks_writing_bottom(z) {
    Some(b) => b + marks_keyboard_gap - c.height
    None => 0.0
  }
  let lift = @motion.animate(c, "preview/lift", if ime > 0.0 && below > 0.0 { below } else { 0.0 })
  let rect = fn() { z.rect().map(fn(r) { (r.0, r.1 - lift, r.2, r.3) }) }
  let (before, after) = v.near(src)
  // (once the frame's builds are over: a step taken further on in this one reads beside the image it comes to)
  c.after_build("pv-near", fn() { v.read_near(src, before, after) })
  if marking.on {
    // marking: one finger draws, two pinch as ever (no stepping meanwhile)
    if c.second_pointer() is Some(_) || v.pinched {
      v.gestures(c, src, stage, z, false, false)
    } else {
      let (px, py, _) = c.pointer()
      match rect() {
        Some(r) => {
          // down where the finger went down, then each place it has been seen at, the last where it was let go: a
          // slow frame (down, moved and up in one or two) loses none of it
          let moved_to = fn() {
            if px != v.last_x || py != v.last_y {
              marks_finger(c, 1, px, py, r, z.nw)
              v.last_x = px
              v.last_y = py
            }
          }
          let down = fn() {
            marks_finger(c, 0, c.press_x, c.press_y, r, z.nw)
            v.last_x = c.press_x
            v.last_y = c.press_y
          }
          if c.pressed(stage) {
            if !v.held {
              down()
              v.held = true
            }
            moved_to()
          } else if v.held || c.clicked(stage) {
            if !v.held {
              down()
            }
            v.held = false
            moved_to()
            marks_finger(c, 2, px, py, r, z.nw)
          }
        }
        None => ()
      }
    }
  } else {
    v.gestures(c, src, stage, z, before is Some(_), after is Some(_))
  }
  // the strip: the one shown and those beside it, the stage's width and the gap apart (FilePreview.kt strip)
  let strip = @motion.anim(c, "preview/strip", 0.0, global=true)
  match pv_strip.pinned {
    Some(x) => strip.snap(x)
    None => ()
  }
  let sx = strip.get()
  if !strip.moving() {
    pv_strip.leaving = None
  }
  let width = c.width + slide_gap
  let flying = v.flies
  match rect() {
    Some(r) if picture != "" && flying => {
      v.draw_flight(c, v.flight_picture(src, picture), r, v.flying())
      // the picture it lands as, asked for meanwhile out of sight (cut to a point): decoded by the time the flight
      // ends, so no frame goes without it
      let (x, y, w, h) = r
      c.box(w=Px(1.0), h=Px(1.0), opacity=0.01, clip=true, fn() {
        c.picture(picture, x=x + sx, y~, w~, h~, max_px=4096) |> ignore
      })
      |> ignore
    }
    Some((x, y, w, h)) if picture != "" => {
      // a desktop's: on the canvas with the web's shadow round it (preview_desk.mbt)
      if v.frame.desk {
        desk_image_ground(c, x + sx, y, w, h)
      }
      c.picture(picture, x=x + sx, y~, w~, h~, max_px=4096) |> ignore
    }
    // its size not sent with it: a small decode, out of sight, says it
    _ if picture != "" =>
      c.box(w=Px(1.0), h=Px(1.0), opacity=0.01, fn() {
        c.image(picture, w=Px(1.0), h=Px(1.0), bg=0L, fade=false) |> ignore
      })
      |> ignore
    _ => ()
  }
  if marking.on {
    match rect() {
      Some(r) => marks_draw(c, r, z.nw, z.nh)
      None => ()
    }
  }
  match pv_strip.leaving {
    // the one going, drawn from where it was (it has no place of its own any more)
    Some(l) =>
      c.layer(fn() {
        c.picture(l.picture, x=l.x + sx - l.dir.to_double() * l.width, y=l.y, w=l.w, h=l.h, max_px=4096) |> ignore
      })
      |> ignore
    // those beside it, out of sight until a swipe brings them in
    None =>
      if sx != 0.0 {
        for side in [(before, -1.0), (after, 1.0)] {
          match side.0 {
            Some(n) => {
              let p = n.picture(src)
              let (w0, h0) = n.natural_size(p)
              match fitted_rect(w0, h0, c.width, c.height) {
                Some((x, y, w, h)) if p != "" =>
                  c.layer(fn() { c.picture(p, x=x + sx + side.1 * width, y~, w~, h~, max_px=4096) |> ignore })
                  |> ignore
                _ => ()
              }
            }
            None => ()
          }
        }
      }
  }
}

///|
/// The images beside this one (FilePreview.kt before, after): a chat's as the core tells them (`imageNear`, each with
/// the session that keeps it), a folder's by its order; their viewers kept (and read ahead) while they are beside it.
pub fn Viewer::near(self : Viewer, src : Source) -> (Viewer?, Viewer?) {
  if self.shown_kind() != Some(KImage) {
    return (None, None)
  }
  let made = fn(id : String, f : () -> Viewer) -> Viewer {
    match pv_strip.near.get(id) {
      Some(n) => n
      None => {
        let n = f()
        pv_strip.near[id] = n
        n
      }
    }
  }
  match self.steps {
    NoSteps => (None, None)
    InChat(thread, session) => {
      let p : Map[String, Json] = { "station": Json::string(self.station), "path": Json::string(self.file.path) }
      match thread {
        Some(th) => p["thread"] = Json::number(th)
        None => p["session"] = Json::string(session)
      }
      near_asked[Json::object(p).stringify()] = p
      let told = (src.topic)("imageNear", p).value
      let side = fn(k : String) -> Viewer? {
        match field(told, k) {
          Some(Object(_) as j) => {
            let a = attachment_of(j)
            let key = if a.owner != "" { a.owner } else { self.key }
            Some(made(self.station + "/" + key + "/" + a.path, fn() { new_viewer(self.station, key, a, None, self.steps) }))
          }
          _ => None
        }
      }
      (side("before"), side("after"))
    }
    InFolder(files) => {
      let mut at = -1
      for i, f in files {
        if Some(f.path) == self.drive.map(fn(d) { d.path }) {
          at = i
        }
      }
      if at < 0 {
        return (None, None)
      }
      let side = fn(i : Int) -> Viewer? {
        match files.get(i) {
          Some(f) =>
            Some(
              made(f.station + "/drive:" + f.root + "/" + f.path, fn() {
                new_viewer(f.station, "", drive_attachment(f), Some(f), self.steps)
              }),
            )
          None => None
        }
      }
      (if at > 0 { side(at - 1) } else { None }, side(at + 1))
    }
  }
}

///|
/// A drive's file as the viewer takes one (no size of its picture, no likeness).
pub fn drive_attachment(f : DriveFile) -> Attachment {
  { name: f.name, path: f.path, size: f.size, width: 0.0, height: 0.0, thumbhash: "", owner: "", upload: "" }
}

///|
/// What shows of an image: its whole picture once read, else (a chat's) its thumbnail as the chat shows it, else its
/// likeness; "" while none is here.
pub fn Viewer::picture(self : Viewer, src : Source) -> String {
  match self.bytes {
    Some(b) if self.image == "" => {
      self.image = "mem:preview/" + self.id()
      @ui.add_image(self.image, b)
    }
    _ => ()
  }
  if self.image != "" {
    return self.image
  }
  let thumb = if self.drive is Some(_) { "" } else { (src.file)(self.station, self.key, self.name) }
  if thumb != "" && thumb != "!" {
    thumb
  } else {
    @gallery.thumbhash_image(self.file.thumbhash).unwrap_or("")
  }
}

///|
/// The images beside the one shown read ahead (those not too big to show), so a step shows the next at once; those
/// no longer beside it let go.
pub fn Viewer::read_near(self : Viewer, src : Source, before : Viewer?, after : Viewer?) -> Unit {
  let ids = []
  for n in [before, after] {
    match n {
      Some(n) => {
        ids.push(n.id())
        if n.bytes is None && !n.fetching && n.error is None && n.file.size <= big_file {
          n.fetching = true
          n.read_whole(src, fn(r) {
            n.fetching = false
            match r {
              Ok(b) => {
                n.bytes = Some(b)
                keep_read(n.id(), b)
              }
              Err(_) => n.error = Some("")
            }
          })
        }
      }
      None => ()
    }
  }
  let gone = []
  pv_strip.near.each(fn(id, _) { if !ids.contains(id) && id != self.id() { gone.push(id) } })
  for id in gone {
    pv_strip.near.remove(id)
  }
}

///|
/// Where a picture of (nw, nh) shows fitted on a stage of (bw, bh) (the viewer's fit: a margin round it, never
/// enlarged).
pub fn fitted_rect(nw : Double, nh : Double, bw : Double, bh : Double) -> (Double, Double, Double, Double)? {
  let z = @kit.Zoom::new(glide_ms=zoom_glide_ms)
  z.boxed(bw, bh)
  z.natural(nw, nh)
  z.rect()
}

///|
/// The size of a viewer's picture: as sent, else as decoded.
pub fn Viewer::natural_size(self : Viewer, picture : String) -> (Double, Double) {
  if self.file.width > 0.0 && self.file.height > 0.0 {
    (self.file.width, self.file.height)
  } else {
    @ui.image_natural(picture).unwrap_or((0.0, 0.0))
  }
}

///|
/// To the one before (`dir` -1) or after (1) (FilePreview.kt go): it takes this one's place, coming in from that side
/// as this one goes out to the other (the strip on SLIDE from where the finger left it, at its speed); with none
/// there, back.
pub fn Viewer::go(self : Viewer, c : @ui.Ctx, src : Source, dir : Int, velocity : Double) -> Unit {
  let strip = @motion.anim(c, "preview/strip", 0.0, global=true)
  let (before, after) = self.near(src)
  let to = if dir < 0 { before } else { after }
  match to {
    None => strip.animate(0.0, @motion.spring(ratio=1.0, stiffness=400.0), velocity~)
    Some(n) => {
      let width = c.width + slide_gap
      let from = strip.get()
      let picture = self.picture(src)
      pv_strip.leaving = match self.zoom.rect() {
        Some((x, y, w, h)) if picture != "" => Some({ picture, x, y, w, h, dir, width })
        _ => None
      }
      // shown at once: no fade; a step wakes the bars (FilePreview.kt: LaunchedEffect(file.path) { wake() })
      n.started = true
      n.fade.set(1.0)
      n.wake(rest_ms)
      viewer.val = Some(n)
      pv_strip.near.remove(n.id())
      strip.snap(from + dir.to_double() * width)
      strip.animate(0.0, @motion.spring(ratio=1.0, stiffness=400.0), velocity~)
      // the frame built again from the one it stepped to: a swipe let go steps in the middle of the stage's build,
      // which would go on to draw this one's picture where the strip now puts the next one (a frame of this one in its
      // place, or of nothing where the one before comes)
      c.built_from_changed("the preview stepped")
      @ui.log("preview: stepped to \{n.file.name}")
    }
  }
}

///|
/// The stage's gestures over a picture: a tap shows or hides the bars, a double tap zooms in (or back), a finger
/// moves it when it is larger than the stage (let go moving, it goes on, slowing; at its edge, on to the one beside
/// it), the wheel (or a trackpad's two fingers with ⌘… any wheel) zooms round the pointer.
pub fn Viewer::gestures(
  self : Viewer,
  c : @ui.Ctx,
  src : Source,
  stage : Int,
  z : @kit.Zoom,
  has_before : Bool,
  has_after : Bool,
) -> Unit {
  let v = self
  // what the finger did, by its events' own times (how fast, how far apart), not the frames'
  let at = c.pointer_at()
  let (px, py, _) = c.pointer()
  let strip = @motion.anim(c, "preview/strip", 0.0, global=true)
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
      return
    }
    _ => v.pinch_d = 0.0
  }
  if c.pressed(stage) {
    if v.held {
      let dx = px - v.last_x
      let dy = py - v.last_y
      v.moved = v.moved + dx.abs() + dy.abs()
      // its speed sideways, for a swipe let go (the latest moves count most)
      if v.vt >= 0.0 && at > v.vt {
        v.vx = v.vx * 0.5 + dx / (at - v.vt) * 0.5
      }
      v.vt = at
      if z.zoomed() {
        // zoomed in: it goes with the finger (at once after a pinch, the press moved already)
        if (v.moved > 8.0 || v.pinched) && (dx != 0.0 || dy != 0.0) {
          v.drag_zoomed(z, strip, dx, dy, has_before, has_after)
        }
      } else {
        // fitted, one finger sideways moves the strip (FilePreview.kt swipe): past the first or the last it gives
        // only a third as much
        if !v.swiping && v.moved > 8.0 && (px - v.down_x).abs() > (py - v.down_y).abs() &&
          (has_before || has_after) && !v.pinched {
          v.swiping = true
          pv_strip.leaving = None
        }
        if v.swiping {
          let next = strip.get() + dx
          let none = if next > 0.0 { !has_before } else { !has_after }
          strip.snap(if none { strip.get() + dx / 3.0 } else { next })
        } else if v.moved > 8.0 && (dx != 0.0 || dy != 0.0) {
          z.pan(dx, dy)
        }
      }
    } else {
      v.held = true
      v.vx = 0.0
      v.vt = at
      v.down_x = px
      v.down_y = py
      if !v.pinched {
        v.moved = 0.0
        // flinging, it stops where it is, and the press taps nothing (as a list moving on its own)
        v.caught = z.stop_fling()
      }
      let (x, _, w, _) = z.rect().unwrap_or((0.0, 0.0, 0.0, 0.0))
      v.at_left = x >= -0.5
      v.at_right = x + w <= z.bw + 0.5
    }
    v.last_x = px
    v.last_y = py
  } else {
    // held still a while before it was let go: no speed left (its frames come only as it moves)
    if v.held && at - v.vt > swipe_still_ms {
      v.vx = 0.0
    }
    // let go further sideways than its frames showed (a slow frame took the whole swipe, down and up in one or two
    // frames): from where it went down to where it was let go, as a swipe
    if (v.held || c.clicked(stage)) && !v.swiping && !z.zoomed() && !v.pinched && (has_before || has_after) {
      let tx = px - c.press_x
      let ty = py - c.press_y
      if tx.abs() > 8.0 && tx.abs() > ty.abs() {
        let none = if tx > 0.0 { !has_before } else { !has_after }
        strip.snap(strip.get() + (if none { tx / 3.0 } else { tx }))
        v.moved = tx.abs() + ty.abs()
        v.vx = tx / dmax(16.0, at - c.press_at)
        v.swiping = true
        v.held = true
        pv_strip.leaving = None
      }
    }
    if !v.held && c.clicked(stage) {
      // (down and up between two frames, never seen held)
      v.caught = z.stop_fling()
    }
    if v.held && v.swiping && (!z.zoomed() || strip.get() != 0.0) {
      // let go: far enough (80, or a fifth of the stage) or flung that way, the one beside it; else back (zoomed in,
      // flung only from an edge it was at as the finger went down: a quick move that came to its edge on the way goes
      // as far as it pulled)
      let dx = strip.get()
      let far = dx.abs() > dmin(80.0, c.width / 5.0)
      let from_edge = !z.zoomed() || (if dx > 0.0 { v.at_left } else { v.at_right })
      let flung = from_edge && v.vx.abs() > 0.3 && (v.vx > 0.0) == (dx > 0.0) && dx.abs() > 10.0
      if dx != 0.0 && (far || flung) {
        v.go(c, src, if dx > 0.0 { -1 } else { 1 }, v.vx * 1000.0)
      } else {
        strip.animate(0.0, @motion.spring(ratio=1.0, stiffness=400.0), velocity=v.vx * 1000.0)
      }
    } else if v.held && z.zoomed() && (v.moved > 8.0 || v.pinched) {
      // zoomed in, let go moving: on at the finger's speed, slowing, to a stop or its edge
      let (fx, fy) = c.pointer_velocity()
      z.fling(fx, fy)
    }
    v.swiping = false
    v.held = false
  }
  let pinched = v.pinched
  if !c.pressed(stage) {
    v.pinched = false
  }
  // a desktop's mouse: a click round an image (not on it) closes it, one on it does nothing until a second makes it a
  // double click (FilePreview.tsx ImageViewer onClick, useZoom onDoubleClick); the bars are the mouse's moves' (a
  // finger's tap, on a wide touch screen too, shows or hides them)
  let desk = v.frame.desk && @ui.pointing() is Mouse
  let on_picture = match z.rect() {
    Some((x, y, w, h)) => px >= x && px < x + w && py >= y && py < y + h
    None => false
  }
  if c.clicked(stage) && v.moved <= 8.0 && !pinched && !v.caught {
    if desk && !on_picture && !marking.on && v.shown_kind() == Some(KImage) {
      v.shut(c)
    } else if at - v.tap_at < double_tap_ms && (px - v.tap_x).abs() < 40.0 && (py - v.tap_y).abs() < 40.0 {
      // the second of two: zoom (and the first's toggle undone)
      v.tap_at = -1.0e9
      if !desk {
        v.toggle()
      }
      z.double_tap(px, py)
    } else {
      v.tap_at = at
      v.tap_x = px
      v.tap_y = py
      if !desk {
        v.toggle()
      }
    }
  }
  // the wheel: a desktop's pans (⇧ sideways), with ⌃ or ⌘ held (or a trackpad's pinch) zooms round the pointer
  // (FilePreview.tsx useZoom onWheel: a pinch's small steps finer than a wheel's notches); a phone's zooms
  let (wx, wy, mods) = @ui.wheel_of(c, stage)
  if desk && z.nw > 0.0 && (wx != 0.0 || wy != 0.0) {
    if (mods & (@ui.wheel_mod_ctrl | @ui.wheel_mod_cmd)) != 0 {
      let fine = (mods & @ui.wheel_mod_ctrl) != 0 && wy.abs() < desk_pinch_step
      z.zoom_to(z.scale * @dmath.exp(-wy * (if fine { desk_pinch_rate } else { desk_wheel_rate })), px, py, false)
    } else if !z.zoomed() {
      // (fitted, it is all in view: nothing to pan, and it stays fitted as the window changes)
      ()
    } else if (mods & @ui.wheel_mod_shift) != 0 && wx == 0.0 {
      z.pan(-wy, 0.0)
    } else {
      z.pan(-wx, -wy)
    }
  } else if !desk && wy != 0.0 && z.nw > 0.0 {
    z.zoom_to(z.scale * @dmath.pow(1.0015, -wy), px, py, false)
  }
}

///|
/// One finger moving a zoomed picture by (dx, dy): it goes with the finger; at its edge, what of the way across it
/// cannot go pulls in the one beside it (the strip, as a swipe does it fitted: past the first or the last a third as
/// far), and the finger going back takes the strip back first.
pub fn Viewer::drag_zoomed(
  self : Viewer,
  z : @kit.Zoom,
  strip : @motion.Anim,
  dx : Double,
  dy : Double,
  has_before : Bool,
  has_after : Bool,
) -> Unit {
  // how far the strip goes for a point of the finger's way toward the one before (> 0) or after
  let give = fn(toward : Double) { if (if toward > 0.0 { has_before } else { has_after }) { 1.0 } else { 1.0 / 3.0 } }
  let mut across = dx
  let s = strip.get()
  if s != 0.0 && across != 0.0 && (across > 0.0) != (s > 0.0) {
    let back = -s / give(s)
    if across.abs() <= back.abs() {
      strip.snap(s + across * give(s))
      across = 0.0
    } else {
      strip.snap(0.0)
      across = across - back
    }
  }
  let x0 = z.x
  z.pan(across, dy)
  let left = across - (z.x - x0)
  if left.abs() > 0.001 && (has_before || has_after) {
    if !self.swiping {
      self.swiping = true
      pv_strip.leaving = None
    }
    strip.snap(strip.get() + left * give(left))
  }
}

// ── a video ────────────────────────────────────────────────────────────

///|
/// The chat's still of a video, as the chat shows it (ChatFiles.kt ChatVideo): the frame it was left at when it was
/// closed into its thumbnail, else the station's poster (its first frame); an image's key, "" while it comes or where
/// there is none (a drive's file).
pub fn Viewer::still(self : Viewer, src : Source) -> String {
  if self.drive is Some(_) {
    return ""
  }
  match pv_frames.get(self.id()) {
    Some((k, _)) => return k
    None => ()
  }
  match (src.poster)(self.station, self.key, self.name) {
    // none made by the station: the first frame the chat drew of it, if it did
    "!" =>
      match pv_first.get(self.id()) {
        Some(f) if f.picture != "!" => f.picture
        _ => ""
      }
    k => k
  }
}

///|
/// The player's view of a film or a song (the system's player in a native view), while one is open.
pub fn Viewer::view(self : Viewer) -> @ui.NativeView? {
  match self.media {
    Some(m) => m.native()
    None => None
  }
}

///|
/// A film or a song in the one player (@sf.player_view, as a drive's plays), back to where it was opened from, its
/// 下载 the preview's. Where its picture is (edge to edge, as the player puts it) is worked out here too: what it flies
/// to from its thumbnail and back into it from (its still flying, the player's picture not placed meanwhile), and where
/// the chat's still of it shows until its first frame does.
pub fn Viewer::player_stage(self : Viewer, c : @ui.Ctx, src : Source, stage : Int) -> Unit {
  let v = self
  let m = match v.media {
    Some(m) => m
    None => {
      tap_stage(c, v, stage)
      return
    }
  }
  // (a fixture's: how it stands pinned, the same on every run)
  match v.pinned {
    Some(p) => m.pin(p)
    None => ()
  }
  // (a song has no picture: no still of it is asked for)
  let still = if v.shown_kind() == Some(KVideo) { v.still(src) } else { "" }
  let z = v.vzoom
  z.boxed(c.width, c.height)
  let (nw, nh) = match m.native() {
    Some(n) => n.natural()
    None => (0.0, 0.0)
  }
  if nw > 0.0 && nh > 0.0 {
    z.natural(nw, nh)
  } else if v.file.width > 0.0 && v.file.height > 0.0 {
    z.natural(v.file.width, v.file.height)
  } else {
    match @ui.image_natural(still) {
      Some((sw, sh)) if still != "" && sw > 0.0 && sh > 0.0 => z.natural(sw, sh)
      _ => ()
    }
  }
  z.step()
  // flying: from the thumbnail's box to the picture's place, or back, on the black the chat's box has
  if v.flies && (!v.closing || !v.leaving_grab) {
    match z.rect() {
      Some(r) => v.draw_flight(c, if v.fly_pic != "" { v.fly_pic } else { still }, r, v.flying(), ground=0x000000FFL)
      None => ()
    }
    return
  }
  let file : @sf.ViewerFile = {
    name: v.file.name,
    size: v.file.size,
    mtime: 0.0,
    mime: v.mime,
    kind: if v.shown_kind() == Some(KAudio) { "audio" } else { "video" },
    title: "",
    key: "",
    bytes: None,
    read: fn(_, _, done) { done(Err("")) },
    stream: None,
    beside: None,
    place: fn() { NeverLeft },
    keep_place: fn(_, _) {  },
    save: fn() { v.ask_save(c) },
  }
  @sf.player_view(
    c,
    m,
    file,
    [],
    back_label=(v.frame.back)(v, src),
    on_back=fn() { v.shut(c) },
    on_go=fn(_) {  },
    // (the chat's still where its picture will be, until its first frame shows)
    still~,
  )
}

///|
/// Haze's blur of 24 dp and 20 dp as CSS's (glass.mbt: (px - 0.5) / 0.57735 dp).
pub let dark_glass_blur : Double = 24.0 * 0.57735 + 0.5

///|
pub let page_glass_blur : Double = 20.0 * 0.57735 + 0.5

///|
/// The frosted glass over a picture (FilePreview.kt darkGlass): 0x121214 at 62% over its blur; with transparency
/// reduced, that tint over black.
pub fn dark_glass() -> @ui.Glass {
  let tint = @sf.alpha(0x121214FFL, 0.62)
  @ui.Glass::frosted(blur=dark_glass_blur, tint~, solid=@sf.over(0x000000FFL, tint))
}

///|
/// The same over a document (FilePreview.kt pageGlass): the surface at 72% (dark, surface2's) over its blur, over the
/// viewer's canvas.
pub fn page_glass() -> @ui.Glass {
  let t = @sf.theme()
  let tint = @sf.alpha(if t.dark { t.p.card2 } else { t.p.card }, 0.72)
  @ui.Glass::frosted(blur=page_glass_blur, tint~, solid=@sf.over(t.p.canvas, tint))
}

///|
/// A button on the viewer's bars (ImageMarks.kt PictureButton): 32 square, its corner 12, an 18 icon; quieter when
/// it cannot be pressed; `held` (the tool in use) on white at 16%, its icon near white. True on the frame after it was
/// tapped.
pub fn picture_button(
  c : @ui.Ctx,
  key : String,
  icon : String,
  tint : Int64,
  on : Bool,
  enabled? : Bool = true,
  held? : Bool = false,
  said~ : String,
) -> Bool {
  let id = c.id(key)
  let live = on && enabled
  let b = c.box(
    w=Px(32.0),
    h=Px(32.0),
    radius=picture_key,
    align=ACenter,
    justify=JCenter,
    bg=if held { 0xFFFFFF29L } else { 0L },
    opacity=if enabled { 1.0 } else { 0.35 },
    id=if live { id } else { 0 },
    fn() {
      @sf.icon(c, icon, size=18.0, color=if held { dark_text } else { tint }) |> ignore
      // PictureButton: clip(Smooth(PICTURE_KEY)).clickable (white at 16% only while held)
      if live {
        @motion.ripple(c, id, picture_key)
      }
    },
  )
  // named `said` (PictureButton's contentDescription), pressed while `held`
  c.semantics(b, Button, id~, label=said, disabled=!enabled, pressed=held)
  live && c.clicked(id)
}

// ── a PDF ──────────────────────────────────────────────────────────────

///|
/// Pages drawn by the system, each as it scrolls near, as wide as the screen allows (FilePreview.kt PdfViewer): 12
/// round them and between them, a page not drawn yet its shape on the bubble's grey.
pub fn Viewer::pdf_stage(self : Viewer, c : @ui.Ctx, b : Bytes, stage : Int) -> Unit {
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
        pv_fill("android-chat.file.pdf.failed", [("error", if @ui.platform() == 3 || @ui.platform() == 4 {
 @sf.t("android-chat.preview.noPdf") } else { "" })]),
        size=15.0,
        color=t.p.muted,
        center=true,
      )
      |> ignore
    })
    return
  }
  tap_stage(c, v, stage)
  // 60 under the status bar, 12 over the navigation bar, round them and between them (FilePreview.kt
  // contentPadding); a desktop's as the web's (preview_desk.mbt: 76 down, as wide as 1000 less 56 allows, 20 apart)
  let desk = v.frame.desk
  let w = if desk { desk_pdf_width(c.width) } else { c.width - 24.0 }
  let side = (c.width - w) / 2.0
  let gap = if desk { desk_pdf_gap } else { 12.0 }
  let (status, nav) = (@sf.viewer_host().room)()
  let top = if desk { desk_page_top } else { 60.0 + status }
  let foot = if desk { desk_pdf_foot } else { 12.0 + nav }
  let none = 0.0
  c.list("preview/pdf/" + v.file.path, pdf.pages + 2, 400.0, fn(i) {
    if i == 0 {
      c.box(w=Fill(1.0), h=Px(top), fn() {  }) |> ignore
    } else if i == pdf.pages + 1 {
      c.box(w=Fill(1.0), h=Px(foot), fn() {  }) |> ignore
    } else {
      let (pw, ph) = pdf.sizes[i - 1]
      let h = if pw > 0.0 { w * ph / pw } else { w * 1.294 }
      c.box(w=Fill(1.0), pl=side, pr=side, pb=if i < pdf.pages { gap } else { none }, fn() {
        c.box(w=Px(w), h=Px(h), bg=0xFFFFFFFFL, shadow=@sf.page_raised.sigma, shadow_y=@sf.page_raised.dy, shadow_color=@sf.page_raised.color, fn() {
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
pub fn Viewer::text_stage(self : Viewer, c : @ui.Ctx, kind : PKind, b : Bytes, stage : Int) -> Unit {
  let v = self
  let t = @sf.theme()
  let cut = b.length() > show_limit
  let words = match v.text {
    Some(s) => s
    None => {
      let s = @codec.utf8_text(b, show_limit)
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
        let low = @sf.lower(head)
        let html = if low.contains("<!doctype") || low.contains("<html") {
          words
        } else {
          "<!doctype html><meta charset=utf-8><meta name=viewport content=\"width=device-width,initial-scale=1\"><body style=\"margin:0;padding:16px;font-family:system-ui,sans-serif\">" +
          words
        }
        // (made once, from the file's words, which no build changes; the build places it, so it is made in it)
        let p = @ui.NativeView::page(html)
        v.page = Some(p)
        p
      }
    }
    // under the bar: 60 under the status bar, a desktop's 76 (FilePreview.css.ts fpPageFrame)
    let top = if v.frame.desk { desk_page_top } else { 60.0 + (@sf.viewer_host().room)().0 }
    c.box(w=Fill(1.0), h=Fill(1.0), pt=top, fn() {
      if page.here() && !v.closing {
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
    csv_table(c, v, words, @sf.lower(v.name).has_suffix(".tsv"), cut)
    return
  }
  // in rows of 60 lines, so a long file lays out only what is in view
  let lines = words.split("\n").map(fn(s) { s.to_owned() }).to_array()
  // code in the colours the core says of its language (`code.ink`), as a whole, then cut at its lines; Markdown's
  // source, plain text and what is past HIGHLIGHT_LIMIT as they are
  let colored = match v.colored {
    Some(cl) if v.colored_dark == t.dark => cl
    _ => {
      let (_, _, language) = preview_kind(v.name)
      let lang = if kind == KMarkdown || kind == KCsv || kind == KText { "" } else { language }
      let said = if lang != "" && words.length() <= highlight_limit {
        @sf.code_ink(c, words, lang)
      } else {
        Some(None)
      }
      match said {
        Some(ink) => {
          let cl = match ink {
            Some(ink) => runs_by_line(@sf.ink_runs(words, ink, t.dark))
            None => []
          }
          v.colored = Some(cl)
          v.colored_dark = t.dark
          cl
        }
        // (asked: plain until the core says)
        None => []
      }
    }
  }
  let chunks = (lines.length() + 59) / 60
  let markdown = kind == KMarkdown && !v.source
  let code = !markdown && (kind != KText && kind != KCsv)
  let count = if markdown { 1 } else { chunks }
  // a desktop's as the web's (FilePreview.css.ts fpCode 64 and the block's 16 down, 32 in, 12 on 1.6; fpPlain 76 down,
  // 32 in, 12 on 1.65), a phone's as the Android app's
  let desk = v.frame.desk
  let top = (@sf.viewer_host().room)().0 + (if markdown { 64.0 } else if code { 80.0 } else if desk { desk_page_top } else { 60.0 })
  let foot = if markdown { 64.0 } else if desk { desk_text_foot } else { 48.0 }
  let size = if desk { desk_code_size } else { 12.5 }
  let line = if desk && code { desk_code_line } else if desk { desk_plain_line } else if code { 20.0 } else { 20.6 }
  let side = if desk { desk_text_side } else { 16.0 }
  c.list("preview/text/" + v.file.path + (if v.source { "/source" } else { "" }), count + 3, 400.0, fn(i) {
    if i == 0 {
      if cut {
        c.box(w=Fill(1.0), pl=20.0, pr=20.0, pt=8.0, pb=8.0, bg=@sf.alpha(t.p.red, 0.0), fn() {  })
        |> ignore
      }
      c.box(w=Fill(1.0), h=Px(top), fn() {  })
      |> ignore
      if cut {
        cut_line(c, pv_fill("android-chat.file.cut", [("size", @sf.file_size(show_limit.to_double()))]))
      }
    } else if i == count + 1 {
      c.box(w=Fill(1.0), h=Px(foot), fn() {  }) |> ignore
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
      let runs : Array[@ui.Run] = []
      for k in from..<to {
        if k > from {
          sb.write_char('\n')
          runs.push(@ui.span("\n", mono=true))
        }
        sb.write_string(lines[k])
        match colored.get(k) {
          Some(line) => runs.push_iter(line.iter())
          None => ()
        }
      }
      let words = fn() {
        c.rich(
          if colored.length() > 0 { runs } else { [@ui.span(sb.to_string(), mono=true)] },
          size~,
          color=t.p.text,
          line~,
          wrap=!code,
        )
        |> ignore
      }
      if code {
        // scrolled across, its rows as one (FilePreview.kt: the code in a horizontalScroll, 32 in from its sides)
        c.sideways("preview/code/" + v.file.path, across=true, padx=32.0, words) |> ignore
      } else {
        c.box(w=Fill(1.0), pl=side, pr=side, words) |> ignore
      }
    }
  })
  |> ignore
}

///|
/// Past this a file shows as plain text, unhighlighted (FilePreview.kt HIGHLIGHT_LIMIT: 256 KB).
pub let highlight_limit : Int = 256 * 1024

///|
/// Highlighted runs cut at their line ends: a line's runs each (none for an empty line), in the code face.
pub fn runs_by_line(runs : Array[@ui.Run]) -> Array[Array[@ui.Run]] {
  let out : Array[Array[@ui.Run]] = [[]]
  for r in runs {
    let parts = r.text.split("\n").map(fn(p) { p.to_owned() }).to_array()
    for k, part in parts {
      if k > 0 {
        out.push([])
      }
      if part != "" {
        out[out.length() - 1].push({ ..r, text: part, mono: true })
      }
    }
  }
  out
}

///|
/// A file shown only in part (FilePreview.kt Cut): the warning's words on its tint.
pub fn cut_line(c : @ui.Ctx, words : String) -> Unit {
  let warn = 0xD9962BFFL
  c.box(w=Fill(1.0), pl=20.0, pr=20.0, pt=8.0, pb=8.0, bg=@sf.alpha(warn, 0.14), fn() {
    c.text(words, size=13.0, color=warn) |> ignore
  })
  |> ignore
}

///|
/// A table (FilePreview.kt CsvTable): a row number, then its columns, each as wide as what it holds (by its
/// characters here: 48 to 420), the head on the canvas with a hairline under it.
pub fn csv_table(c : @ui.Ctx, v : Viewer, words : String, tab : Bool, cut : Bool) -> Unit {
  let t = @sf.theme()
  let rows = @codec.parse_csv(words, if tab { '\t' } else { ',' }, table_rows + 1)
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
  // a desktop's in the page's 13 (FilePreview.css.ts fpTable), 68 down to its head; a phone's in 15
  let size = if v.frame.desk { desk_cell_size } else { 15.0 }
  let top = if v.frame.desk { desk_table_top } else { 60.0 + (@sf.viewer_host().room)().0 }
  let cell = fn(s : String, w : Double, weight : Int, color : Int64) {
    c.box(w=Px(w), padx=16.0, pady=8.0, clip=true, fn() {
      c.text(s, size~, weight~, color~, wrap=false) |> ignore
    })
    |> ignore
  }
  c.list("preview/csv/" + v.file.path, body_n + 3, 37.0, fn(i) {
    if i == 0 {
      c.box(w=Fill(1.0), h=Px(top), fn() {  }) |> ignore
    } else if i == 1 {
      c.box(dir=Row, bg=(v.frame.canvas)(), border=0.0, fn() {
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
          c.text("\{i - 1}", size~, color=t.p.muted, wrap=false) |> ignore
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
/// What the viewer keeps put back as the app begins anew (sfbase's reset).
pub fn file_viewer_reset() -> Unit {
  close_now()
  marking.color = 0xE5704AFFL
  marking.next_id = 1
  marking.to_draft = false
  marking.job_name = ""
  marking.write_field.set("")
  marking.note_field.set("")
  pv_thumbs.clear()
  pv_frames.clear()
  pv_frames_n.val = 0
  pv_first.clear()
  pv_hidden.val = ""
  pv_read.clear()
  pv_strip.leaving = None
  pv_strip.pinned = None
  pv_strip.near.clear()
  near_asked.clear()
  viewer_awake_env.val = -1
}

///|
/// A video's still as the viewer left it, else the station's poster (or its first frame drawn here when the station
/// made none): its image's key ("" none). `thumb`: its thumbnail's id.
pub fn video_still(c : @ui.Ctx, src : Source, station : String, owner : String, a : Attachment, thumb : String) -> String {
  match pv_frames.get(thumb) {
    Some((k, _)) => k
    None =>
      match (src.poster)(station, owner, base_name(a.path)) {
        "!" => first_frame(c, src, station, owner, a, thumb)
        k => k
      }
  }
}
