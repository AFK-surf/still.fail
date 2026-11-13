// A file of a chat opened over the whole screen (still.fail apps/android chat/screens/FilePreview.kt, VideoViewer.kt,
// FileKinds.kt kindOf, ChatFiles.kt FileData; web/src/FilePreview.tsx): images to zoom (a double tap, the bar's − and
// +, the wheel) and pan (mbui's @kit.Zoom); videos played by the system's player (a native view over the
// canvas, src/ui/native.mbt), its bytes read through the core a part at a time (`station.file.part`); PDFs drawn by the
// system page by page; HTML in a page of its own (a native web view: its scripts on, nothing of the app's reachable);
// Markdown rendered; CSV as a table; code and text as they are. Anything else says it cannot be shown and offers the
// download. One bar floats at the top with its name and tools and fades when left alone; a tap brings it back. Back (or
// ×) closes it.
//
// An image or a video flies from the chat's thumbnail and back into it; a video closed
// so keeps the frame it was left at, which its thumbnail shows and where it goes on from when opened again
// (FileViewers.frames). Its bytes stream (the Android app reads it whole first): a finger along its timeline puts its
// player in a mode of seeks one after another (NativeView::scrub), and the host keeps what it read.
//
// Not yet, against the Android app: pinching on iOS (no second finger told there yet). The bars are frosted glass over
// what the app draws (a picture, a document); over a native view (a video, a page) a solid tint, as it cannot be
// blurred.


///|
pub fn pv(key : String) -> String {
  tr(key)
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

// ── what a file is ───────────────────────────────

///|
#derive(Eq)
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
}

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
    Some(i) if i > 0 => lower.exact_view(start=i + 1).to_owned()
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
    "3gp" => Some((KVideo, "video/3gpp"))
    "3g2" => Some((KVideo, "video/3gpp2"))
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
/// Over this a file is not read into memory to be shown; above SHOW_LIMIT only its start
/// shows as text; a table shows TABLE_ROWS rows at most.
pub let big_file : Double = 16.0 * 1024.0 * 1024.0

///|
pub let show_limit : Int = 2 * 1024 * 1024

///|
pub let table_rows : Int = 2000

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
  /// a file a message names by its path (`file.path`, as the agent wrote it), read by `file.open`, whatever it is now
  named : Bool
  kind : PKind?
  mime : String
  /// a file of no known kind: text (its first bytes UTF-8, no NULs)? None while asked
  sniffed : @signals.Signal[Bool?]
  sniffing : @signals.Signal[Bool]
  bytes : @signals.Signal[Bytes?]
  fetching : @signals.Signal[Bool]
  /// how much of it has come while it is read whole, and its whole size where the station says it (FileData.progress)
  got : @signals.Signal[(Double, Double?)?]
  error : @signals.Signal[String?]
  /// a file told of (not shown): asked for (to save)
  mut asked : Bool
  mut save_after : Bool
  /// …or to be handed to another app (分享: Viewer::ask_share), as its whole comes
  mut share_after : Bool
  /// a chat's file asked to be downloaded by the core (downloads.mbt), said to it in the next frame (the old bars');
  /// told as it is asked (`asked_told`: the window's tree's viewer says it to the core then, and saves what was asked
  /// for to be saved as its whole comes, each once)
  mut download_asked : Bool
  asked_told : @signals.Signal[Int]
  /// …or to be installed (an APK)
  mut install_after : Bool
  /// the bars shown: till a tap (a click) hides them, and another brings them back (the user, 2026-10-28); told as it
  /// changes (`awake_told`: what shows the bars follows it)
  mut awake : Bool
  awake_told : @signals.Signal[Int]
  /// a mouse's pointer along the top, where the bar is: there while it is, hidden or not
  mut near_bar : Bool
  zoom : @kit.Zoom
  vzoom : @kit.Zoom
  /// 源码 rather than 预览
  mut source : Bool
  /// told as `source` changes (Viewer::set_source): what shows it and what says it follow it
  source_told : @signals.Signal[Int]
  mut page : @ui.NativeView?
  mut pdf : @ui.Pdf?
  mut text : String?
  /// its words highlighted, a line each (code, or Markdown's source), read once: None until then, Some([]) when not
  mut colored : Array[Array[@ui.Run]]?
  /// whether they were coloured for the dark theme
  mut colored_dark : Bool
  /// code and text shown as they come, a part at a time (viewer_flow.mbt), once its first part is asked
  mut flow : Flow?
  /// told as its flow is begun (Viewer::read_on): what follows what it shows as it comes (its parts) follows it from then
  flow_told : @signals.Signal[Int]
  /// the image's key once its bytes are given
  mut image : String
  /// drawn once (its way in set going), closed (only drawn going), how far it has faded in (0 … 1, a motion)
  mut started : Bool
  mut closing : Bool
  fade : @motion.Way
  // a finger on the stage: where it was last frame, how far it has gone
  mut held : Bool
  mut last_x : Double
  mut last_y : Double
  mut moved : Double
  // two fingers: how far apart and where between them last frame (0: none), whether this press pinched
  mut pinch_d : Double
  mut pinch_x : Double
  mut pinch_y : Double
  mut pinched : Bool
  /// a read of the video's file, logged the first times
  reads : @signals.Signal[Int]
  /// how a song's player stands, pinned for a fixture's shot
  mut pinned : @kit.MediaStatus?
  /// what it steps through (an image): its chat's images, a folder's
  steps : Stepping
  /// Where this occurrence is in its chat, distinct from the file shared by other messages or quotes.
  at : String
  /// a finger moving it sideways to the one before or after (fitted, not zoomed)
  mut swiping : Bool
  /// where the finger went down (in the window's terms; on the stage, `down_lx`, `down_ly`: the canvas's own)
  mut down_x : Double
  mut down_y : Double
  mut down_lx : Double
  mut down_ly : Double
  /// zoomed in, its left and its right edge in the stage as the finger went down (a fling on past one goes beside it)
  mut at_left : Bool
  mut at_right : Bool
  /// the finger came down on it flinging, and stopped it there: no tap
  mut caught : Bool
  /// where the strip was as the finger went down (a slide still going on caught there): what the swipe let go is
  /// measured from
  mut strip_down : Double
  /// its flight from the chat's thumbnail (or back into it): whether it flies, how far (0 the thumbnail … 1 the
  /// stage, a motion), back or not, from where
  mut flies : Bool
  fly : @motion.Way
  mut fly_back : Bool
  mut fly_from : Thumb?
  /// the share of the flight's way (`fly`, where it has got to on its Move) that is its thumbnail going out from under
  /// the chat's bar or composer, at its own size, to where they hide none of it, before it grows (or after it has
  /// shrunk, going back): 0 when nothing hides it
  mut fly_lift : Double
  /// a video going back: where its player last drew its picture (as a finger left it, zoomed in or taken down), what
  /// it flies back from
  mut fly_to : (Double, Double, Double, Double)?
  /// a video's picture as it flies (its still, or the frame it goes back with)
  mut fly_pic : String
  /// a video opened again: where it was left (ms; -1 from its start), until its player is ready to go on from there
  mut start_at : Double
  /// a video closing into its thumbnail: the frame it shows being grabbed first (what it goes back with), and where
  /// it was then
  mut leaving_grab : Bool
  mut left_at : Double
  /// told as leaving_grab changes (Viewer::grab_set): what is done at its going's end follows it
  grab_told : @signals.Signal[Int]
  /// a desktop's song: played in the player a drive's is, not the phone's strip
  mut media : @kit.Media?
  /// a desktop's image put on the clipboard: how many times (its check shown a while after each)
  mut copied : Int
  /// how wide the floating bar has been (it never narrows once open: @sf.viewer_frame_bar)
  mut head_w : Double
  /// which opening of a viewer it is (the window's tree picks its node by it: viewer_tree.mbt)
  serial : Int
  /// drawn by a node of the window's tree (viewer_tree.mbt), not by the old view's layer
  mut in_tree : Bool
  /// how many layers of the window's tree it has been drawn in (viewer_node): the last the one it is in
  mut tree_layers : Int
  /// closed back into its thumbnail drawn by the window's tree (Viewer::shut): its picture's node let go of at once,
  /// flown back by the tree (viewer_tree.mbt's image_layer)
  tree_back : @signals.Signal[Bool]
  /// the fingers on its stage by their ids (Drag's `finger`), where each is now; how fast the one moving it goes, by
  /// its events' own moments; what calls off the hold waited for (its picture's menu)
  fingers : Map[Int, (Double, Double)]
  speed : @ui.Velocity
  mut hold_off : () -> Unit
  /// how far the picture is lifted over the keyboard while marking (its way said as the keyboard or what is written
  /// changes, at that moment: viewer_tree.mbt)
  lift : @motion.Way
  /// a tab's beside a chat (viewer_tab.mbt), not the one over the whole window: its stage starts under the tab's own
  /// tools, nothing of the window's bars over it
  beside : Bool
  /// a film or a song played as its player opens (the whole window's always; a tab's only as the person opened it
  /// beside just now: viewer_tab.mbt's tab_asked), else there paused until its play key
  mut plays_now : Bool
}

///|
/// How many viewers have been opened: the next one's `serial`.
// kept across runs: only a count
let viewers_opened : Ref[Int] = Ref(0)

///|
/// A thumbnail of the chat's the viewer flies from and back into: where it is laid out (in the
/// window, its whole box: not cut to what clips it), its corners, how its picture sits in it and which picture that is.
pub(all) struct Thumb {
  x : Double
  y : Double
  w : Double
  h : Double
  corners : @motion.MeasuredCorners
  /// its picture letterboxed in it: fitted inside its box, not cropped to it
  letterbox : Bool
  /// a cropped picture starts at its top, rather than its middle
  top_crop : Bool
  /// the picture it shows (its image's key), what the viewer shows of it until it has the whole: "" none of its own
  picture : String
  /// the part of its box that shows, cut by what it is in (its list, its card), where that was last drawn: what the
  /// picture flying back into it is cut to as it lands, as the thumbnail is
  seen : (Double, Double, Double, Double)?
  /// where its list shows it with nothing over it (under the chat's bar, over its composer: note_list), top and
  /// bottom; None, nothing is drawn over it (a composer's tile)
  clear : (Double, Double)?
  /// what it draws over its picture (a film's play mark, its name's band), drawn in its box at the opacity given:
  /// carried by the picture as it flies, going as it leaves the thumbnail and coming back as it lands
  over : (Double) -> Unit
}

///|
/// How a thumbnail of the chat draws its picture (Thumb's but its place, which its measure keeps).
pub(all) struct ThumbLook {
  radius : Double
  letterbox : Bool
  top_crop : Bool
  picture : String
  /// its node's id, where it is pressed (0 none): where it showed, cut, as the last frame drew it (Ctx::rect_of)
  id : Int
  /// the list it is in (note_list), "" none
  list : String
  /// what it draws over its picture (Thumb's)
  over : (Double) -> Unit
  /// what decides how that looks, as its chat said it (note_thumb's `said`): told as it changes (thumbs_said)
  said : String
}

///|
/// The chat's thumbnails by their place (Viewer::thumb_id), as last built.
pub let pv_thumbs : Map[String, ThumbLook] = Map([])

///|
/// A video closed back into its thumbnail keeps the frame it was left at: the
/// thumbnail shows it from then on, and opened again the video goes on from there. By the thumbnail's id (Viewer::id):
/// the frame's image, where it was (ms).
pub let pv_frames : Map[String, (String, Double)] = Map([])

///|
/// What a node of the window's tree read of pv_frames (pv_frame_track), by the thumbnail's id: told as its frame is kept
/// or let go, made as one is first read so, let go as nothing reads it any more. The old views' reads track nothing.
// kept across runs: let go with pv_frames (viewer's clear)
let pv_frames_told : Map[String, @signals.Signal[Int]] = Map([])

///|
/// The frame kept for thumbnail `id` read by a node: what reads it told as one is kept or let go.
fn pv_frame_track(id : String) -> Unit {
  let s = match pv_frames_told.get(id) {
    Some(s) => s
    None => {
      let s = @signals.signal(0)
      pv_frames_told[id] = s
      s
    }
  }
  s.get() |> ignore
}

///|
/// The frame kept for thumbnail `id` changed: told, where a node reads it.
fn pv_frame_tell(id : String) -> Unit {
  match pv_frames_told.get(id) {
    Some(s) =>
      if s.watched() {
        s.set(s.untracked() + 1)
      } else {
        pv_frames_told.remove(id)
      }
    None => ()
  }
}

///|
/// How many frames have been kept (each one's image a key of its own).
pub let pv_frames_n : Ref[Int] = { val: 0 }

///|
/// A frame kept is this many pixels at most on its longer side (the station's poster's, posters.ts SIDE).
pub let kept_frame_side : Double = 640.0

///|
/// A chat's video the station made no poster of (one from before posters, or with neither QuickLook nor ffmpeg), small
/// enough to read for it, or one waiting in a draft that the host has no picture
/// of: its first frame drawn here. A player of it made out of sight (never placed), its frame at 0 grabbed, then let
/// go; what it read of a chat's kept with the chat by the core, as the viewer's reads are. By the thumbnail's id: the
/// player while it grabs, and the frame's image ("" while it comes, "!" none to be had).
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
  if !pv_first.contains(id) && (a.size <= 0.0 || a.size > big_file) {
    return ""
  }
  grab_first(c, id, a.name, fn() { first_player(src, station, key, a) })
}

///|
/// A player of chat video `a` (on `station`, kept by session `key`) reading it from the station a part at a time, for
/// its first frame (first_frame's, first_frame_node's).
fn first_player(src : Source, station : String, key : String, a : Attachment) -> @ui.NativeView {
  let (_, mime, _) = preview_kind(a.name)
  @ui.NativeView::video(mime, fn(offset, length, answer) {
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
}

///|
/// The first frame of chat video `a` as first_frame has it, for a node of the window's tree `v` (a chat's things'
/// tile): what it shows read as it comes (an image's key, "" while it comes or where it is too big to read for it, "!"
/// when it could not be). The same grab as first_frame's (pv_first, by `id`): asked once at its moment, as an old
/// view's is once its frame is built; its answer taken as the host tells it (NativeView::grabs_told), none to be had as
/// the host says it has no player or one that cannot read it, or once its decoder has waited media_decode_wait_ms
/// from when all its bytes came (@kit.media_decode_stalled's): first_frame's rule, followed as it is told, not asked
/// each frame.
pub fn first_frame_node(v : @view.View, src : Source, station : String, key : String, a : Attachment, id : String) -> () -> String {
  let picture = fn() {
    pv_first_told.get() |> ignore
    match pv_first.get(id) {
      Some(f) => f.picture
      None => ""
    }
  }
  if !pv_first.contains(id) {
    if a.size <= 0.0 || a.size > big_file {
      return picture
    }
    let f : FirstFrame = { view: None, picture: "" }
    pv_first[id] = f
    let n = first_player(src, station, key, a)
    if !n.here() {
      f.picture = "!"
      return picture
    }
    f.view = Some(n)
    v.at_moment(v.cause_at(), fn() { n.grab_frame(0.0) }) |> ignore
  }
  // (its decoder's wait, as it stands: let go as another is set or it is settled)
  let stall : Ref[() -> Unit] = Ref(fn() {  })
  let waiting = fn() {
    match pv_first.get(id) {
      Some(f) => f.view
      None => None
    }
  }
  v.reacts(
    fn() { waiting().map(fn(n) { (n.grabs_told(), n.state()) }) },
    fn(told) {
      guard told is Some(_) && pv_first.get(id) is Some(f) && f.view is Some(n) else { return }
      match n.grabbed() {
        Some(png) => first_settled(f, n, id, a.name, png)
        None =>
          if n.state() < 0 && !n.grabbing() {
            first_settled(f, n, id, a.name, b"")
          } else if n.state() == 2 && n.decode_since() >= 0.0 {
            (stall.val)()
            stall.val = v.at_moment(n.decode_since() + @kit.media_decode_wait_ms, fn() {
              if f.view is Some(m) && physical_equal(m, n) {
                first_settled(f, n, id, a.name, b"")
              }
            })
          }
      }
    },
  )
  picture
}

///|
/// What a first frame came to (first_frame_node's): `png` its picture's (an image's key kept by `id`, as grab_first
/// keeps it), none: "!"; its player closed, what shows it told.
fn first_settled(f : FirstFrame, n : @ui.NativeView, id : String, name : String, png : Bytes) -> Unit {
  f.view = None
  if png.length() > 0 {
    let k = first_key(id, name)
    @ui.add_image(k, png)
    f.picture = k
  } else {
    f.picture = "!"
  }
  n.close()
  first_told()
}

///|
/// The key a first frame's picture is kept by (grab_first's).
fn first_key(id : String, name : String) -> String {
  "mem:pv-first/\{@ui.stable_hash(id)}/\{id.length()}/\{name}"
}

///|
/// How many first frames have come to what they are (grab_first's, first_frame_node's): what a node showing one reads,
/// told as any is.
// kept across runs: a count, only what changed is read of it
let pv_first_told : @signals.Signal[Int] = @signals.signal(0)

///|
/// A first frame come to what it is, told (pv_first_told).
fn first_told() -> Unit {
  pv_first_told.set(pv_first_told.untracked() + 1)
}

///|
/// The first frame of video `name` read whole here (a file picked or pasted where the host has no picture of it:
/// @hostapi.Picked.src), from its `bytes`; by `id`, as first_frame.
pub fn bytes_first_frame(c : @ui.Ctx, id : String, name : String, bytes : Bytes) -> String {
  let (_, mime, _) = preview_kind(name)
  grab_first(c, id, name, fn() {
    @ui.NativeView::video(mime, fn(offset, length, answer) {
      let n = bytes.length()
      let from = if offset < 0.0 { 0 } else if offset > n.to_double() { n } else { offset.to_int() }
      let to = if length > n - from { n } else { from + length }
      answer(bytes[from:to].to_owned(), n.to_double(), false)
      fn() {  }
    })
  })
}

///|
/// A video's first frame (`id` naming it, `name` its file's), from the player `open` makes of it (pv_first): an image's
/// key once here, "" while it comes, "!" when it could not be.
fn grab_first(c : @ui.Ctx, id : String, name : String, open : () -> @ui.NativeView) -> String {
  match pv_first.get(id) {
    Some(f) => {
      match f.view {
        Some(n) => {
          let got = match n.grabbed() {
            Some(png) => Some(png)
            // (no player here, or one that cannot read it: none to be had)
            None =>
              if (n.state() < 0 && !n.grabbing()) || @kit.media_decode_stalled(c, Some(n)) {
                Some(b"")
              } else {
                None
              }
          }
          match got {
            Some(png) => {
              f.view = None
              if png.length() > 0 {
                let k = first_key(id, name)
                @ui.add_image(k, png)
                f.picture = k
              } else {
                f.picture = "!"
              }
              c.tell("pv-first-close/" + id, fn() {
                n.close()
                first_told()
              })
            }
            None => ()
          }
        }
        None => ()
      }
      f.picture
    }
    None => {
      let f : FirstFrame = { view: None, picture: "" }
      pv_first[id] = f
      let n = open()
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
/// The thumbnail hidden while the viewer is its picture (one picture on the screen, never two), by its file's id: told
/// as it changes, what draws the thumbnail (its chat's view, kept as it is unless told) shown or hidden again then.
// kept across runs: put back by file_viewer_reset
pub let pv_hidden : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })

///|
/// A thumbnail of the chat built this frame as node `node`, showing `picture`: where it is
/// laid out kept as it moves (@motion.measure), under the viewer too, for the viewer to fly from and back into; in
/// chat list `list` (note_list), if it is in one. `over`: what it draws over its picture, at an opacity (Thumb's);
/// `said`: what decides how that looks (what draws it in flight is told as it changes: thumbs_said).
pub fn note_thumb(
  c : @ui.Ctx,
  id : String,
  node : Int,
  radius : Double,
  picture~ : String,
  letterbox? : Bool = false,
  top_crop? : Bool = false,
  list? : String = "",
  over? : (Double) -> Unit = fn(_) {  },
  said? : String = "",
) -> Unit {
  @motion.measure(c, node, "pv-thumb/" + id)
  let changed = match pv_thumbs.get(id) {
    Some(was) => was.said != said
    None => said != ""
  }
  pv_thumbs[id] = { radius, letterbox, top_crop, picture, id: c.node_id(node), list, over, said }
  if changed {
    match thumbs_said.get(id) {
      Some(s) => s.set(said)
      None => ()
    }
  }
}

///|
/// What its thumbnail draws over its picture (ThumbLook's over), as its chat said it last, followed as what decides
/// how that looks changes (thumbs_said, its own); its chat's not drawn any more, the one it flew from (fly_from's); else
/// none. Its place read none.
pub fn Viewer::thumb_over(self : Viewer) -> (Double) -> Unit {
  let id = self.thumb_id()
  let said = match thumbs_said.get(id) {
    Some(s) => s
    None => {
      let s = @signals.signal(pv_thumbs.get(id).map_or("", fn(l) { l.said }), same=fn(a, b) { a == b })
      thumbs_said[id] = s
      s
    }
  }
  said.get() |> ignore
  match pv_thumbs.get(id) {
    Some(l) => l.over
    None =>
      match self.fly_from {
        Some(t) => t.over
        None => fn(_) {  }
      }
  }
}

///|
/// What decides each thumbnail's look over its picture (note_thumb's `said`: its capsule's length, how far it is
/// brought, as its chat says it), by its thumbnail's id, as a signal of its own made as it is first read
/// (Viewer::thumb_over): told as that thumbnail's changes, not as another's.
// kept across runs: said as each changes; put back with the thumbnails
let thumbs_said : Map[String, @signals.Signal[String]] = Map([])

///|
/// What is drawn over each chat's list (by its key, as last built): how much of its top the bar takes, how much of
/// its foot the composer.
let pv_lists : Map[String, (Double, Double, Int)] = Map([])

///|
/// Chat list `key`, node `node`, built this frame, `bar` of its top under the chat's bar and `room` of its foot under
/// the composer (both drawn over the viewer's picture as it flies: over_flight): where its thumbnails show with nothing
/// over them; `slot`, the page (its stack entry) whose bar over it is that page's nodes, a picture flying from it drawn
/// under that bar in the page's slot (viewer_flight_slot), 0 none: its bar the old view's, lifted over the flight.
pub fn note_list(c : @ui.Ctx, node : Int, key : String, bar : Double, room : Double, slot? : Int = 0) -> Unit {
  @motion.measure(c, node, "pv-list/" + key)
  pv_lists[key] = (bar, room, slot)
}

///|
/// The page (its stack entry) whose slot draws the flight of viewer `self` while it is under that page's bar: the one
/// whose chat list holds the thumbnail it flies from, where that list's bar is the page's nodes (note_list's `slot`);
/// 0 none, its own layer drawing all of it. Read from pv_thumbs and pv_lists, which the graph does not follow: what it
/// comes to is fixed for as long as the thumbnail's list lives (the page a list is laid out in, and whether its bar is
/// that page's nodes, never change for it), and is there before any press on the thumbnail can open the viewer (the
/// list is laid out, noted so, before what it shows is pressed); what the graph follows of the flight is the viewer's
/// own (Viewer::fly, its `flies`).
fn Viewer::flies_from_page(self : Viewer) -> Int {
  match pv_thumbs.get(self.thumb_id()) {
    Some(l) =>
      match pv_lists.get(l.list) {
        Some((_, _, page)) => page
        None => 0
      }
    None => 0
  }
}

///|
/// How much of the chat's thumbnail `id` shows: none while the viewer is its picture, else all of it.
pub fn thumb_shows(id : String) -> Double {
  if pv_hidden.get() == id {
    0.0
  } else {
    1.0
  }
}

///|
/// A chat's page's bar or composer (node `i`) as the viewer flies from one of its pictures or back into it: over the
/// picture while it is at its thumbnail's size (going out from under them, or in under them as it lands: lift_of), as
/// the page has it there (over the viewer's layer: @ui.Stratum's OverLayers); once it grows, the page's again, under the
/// viewer's ground as the rest of the page is, gone as it darkens (not drawn over the ground, standing out of it).
pub fn over_flight(c : @ui.Ctx, i : Int) -> Unit {
  let v = match viewer.get() {
    Some(v) => Some(v)
    None => pv_leaving.get()
  }
  match v {
    Some(v) if v.flies && v.flying(c) <= 0.0 => c.stratum(i, OverLayers)
    _ => ()
  }
}

///|
/// Whether the thumbnail of `id` is a node of the window's tree drawn now (a chat's page made as nodes: its end of the
/// picture's flight that stays, View::shared's `stays`), to be flown back into by the tree.
fn tree_thumb_seen(id : String) -> Bool {
  match @ui.view_tree() {
    Some(tree) => tree.stays_seen(id)
    None => false
  }
}

///|
/// The thumbnail of `id` where it was last laid out, while some of it is on the screen.
pub fn thumb_of(c : @ui.Ctx, id : String) -> Thumb? {
  match (pv_thumbs.get(id), @motion.measured_rect(c, "pv-thumb/" + id)) {
    (Some(l), Some((x, y, w, h))) if w > 0.0 && h > 0.0 && x < c.width && x + w > 0.0 && y < c.height && y + h > 0.0 =>
      Some({
        x,
        y,
        w,
        h,
        corners: @motion.measured_radii(c, "pv-thumb/" + id).unwrap_or(@motion.MeasuredCorners::uniform(l.radius)),
        letterbox: l.letterbox,
        top_crop: l.top_crop,
        picture: l.picture,
        seen: if l.id != 0 { c.rect_of(l.id) } else { None },
        over: l.over,
        clear: match (pv_lists.get(l.list), @motion.measured_rect(c, "pv-list/" + l.list)) {
          (Some((bar, room, _)), Some((_, ly, _, lh))) => Some((ly + bar, ly + lh - room))
          _ => None
        },
      })
    _ => None
  }
}

///|
/// How far thumbnail `t` goes up (less than 0) or down to show whole between the chat's bar and its composer, a
/// little in from them (centred between them when it is taller than what they leave); 0 when nothing hides it.
pub fn lift_of(t : Thumb) -> Double {
  match t.clear {
    Some((top, foot)) => {
      let (top, foot) = (top + lift_gap, foot - lift_gap)
      if t.h > foot - top {
        (top + foot) / 2.0 - (t.y + t.h / 2.0)
      } else if t.y < top {
        top - t.y
      } else if t.y + t.h > foot {
        foot - (t.y + t.h)
      } else {
        0.0
      }
    }
    None => 0.0
  }
}

///|
/// How far from the bar and the composer a thumbnail going out from under them stops.
let lift_gap : Double = 12.0

///|
/// The flight's way between thumbnail `t` and `to` (where the picture is on the stage): the share of it that is the
/// thumbnail's going out from under the bar or composer (none when nothing hides it), and how far it goes in all
/// (points: the going out, then the growing as far as its furthest going edge goes). One move, the going out its first
/// share and the growing the rest, on one curve, so that nothing stops between them (the user, 2026-10-29: 「前段避让跟
/// 后段放大之间…顿一下…应该浑然一体」); its edges no quicker as it goes out than as it then grows (a picture mostly hidden
/// goes out far, the user, 2026-10-29: 「从上往下的还有问题」); a Move as long as it all is far. `to` not known: as far as
/// to the middle of the window, `window` (w, h); zoomed past the window, as far as what the window shows of it (its
/// edges out there are never seen going: one zoomed closes as quick as one fitted).
fn fly_way(t : Thumb, to : (Double, Double, Double, Double)?, window : (Double, Double)) -> (Double, Double) {
  let lift = lift_of(t).abs()
  let lift = if lift < 0.5 { 0.0 } else { lift }
  let y = t.y + (if lift > 0.0 { lift_of(t) } else { 0.0 })
  let grow = match to.map(fn(r) { seen_of(r, window.0, window.1) }) {
    Some((tx, ty, tw, th)) =>
      dmax(dmax((tx - t.x).abs(), (tx + tw - t.x - t.w).abs()), dmax((ty - y).abs(), (ty + th - y - t.h).abs()))
    None => {
      let (ww, wh) = window
      dmax((ww / 2.0 - t.x - t.w / 2.0).abs(), (wh / 2.0 - y - t.h / 2.0).abs())
    }
  }
  (if lift > 0.0 { lift / (lift + grow) } else { 0.0 }, lift + grow)
}

///|
/// The viewer fading in and out where there is no thumbnail to grow from.
pub let pv_fade_ms : Double = 140.0

///|
/// How much faster than its flight what a thumbnail draws over its picture goes (Thumb's over): gone halfway.
let flight_over_gone : Double = 2.0

///|
/// How far a film's flight has come (its ground as opaque) before the player's bars and controls begin to show: what
/// the page under it says is hidden by then (a fill this opaque covers words: @ui's words over words), so that no frame
/// shows the player's words over the page's, both seen.
pub let bars_from : Double = 0.9

///|
/// How much of the player's bars and controls show with its flight `p` of the way in (or still in, going back): none
/// till its ground is whole (bars_from), all once it is in.
fn bars_share(p : Double) -> Double {
  dmax(0.0, (p - bars_from) / (1.0 - bars_from))
}


///|
/// What an image opened in the viewer steps through: the images of the chat it is opened from,
/// of which the core tells those beside the one shown (`imageNear`: by the chat's thread, else its session), not the
/// chat's every image; or a folder's of a drive.
pub(all) enum Stepping {
  NoSteps
  InChat(Double?, String)
  InFolder(Array[DriveFile])
}

///|
pub let viewer : @signals.Signal[Viewer?] = @signals.signal(None)

///|
/// Whether this viewer is still the one open and not closing (what it said in the system's bars still its own).
pub fn Viewer::up_still(self : Viewer) -> Bool {
  match viewer.untracked() {
    Some(v) => physical_equal(v, self) && !self.closing
    None => false
  }
}

///|
/// The viewer closed and still drawn going (its fade or its flight back), no longer the one open: closing takes it
/// out of `viewer` at once, and what is under it is the page's again.
pub let pv_leaving : @signals.Signal[Viewer?] = @signals.signal(None)

///|
/// When the preview's way in or out is over (the frames' clock): the latest end told its fade and its flight, the one
/// open's or the one leaving's; once the one leaving is gone, the end of its way out (said to move: Viewer::shut,
/// Tester::rest_of); -1 when none was opened. What a test runs to after it opens or closes one.
pub fn preview_rest() -> Double {
  let mut at = -1.0
  for v in [viewer.get(), pv_leaving.get()] {
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
  if viewer.get() is None && pv_leaving.get() is None {
    at = @ui.rest_of("the preview's way out")
  }
  at
}

///|
/// Opens `a` of the chat on `station` (kept by the session `key`) over everything; `steps`: what an image steps
/// through; `named`: a file a message names by its path (`a.path`), not one sent with it. `beside`: asked beside the
/// page (by default as the command key is held as it is pressed: beside_held; a menu's 在侧边打开, the preview's
/// 移到侧边): a tab of the side panel where the shell has one for the page in view (Shell's `beside`; a film or a song
/// played there at once), else over everything all the same. Over everything, what the tabs beside the page play is
/// paused; `start`: where a film or a song starts there (ms; a tab's 全屏: where the tab's player was), else where it
/// was left.
pub fn open_preview(
  station : String,
  key : String,
  a : Attachment,
  drive? : DriveFile? = None,
  steps? : Stepping = NoSteps,
  named? : Bool = false,
  at? : String = "",
  beside? : Bool = beside_held(),
  start? : Double = -1.0,
) -> Unit {
  if beside && opens_beside(a.path, a.name) && beside_open(view_tab_key(station, key, a, drive, named), 0.0) {
    return
  }
  close_now()
  tab_players_pause()
  pv_strip.leaving = None
  let v = new_viewer(station, key, a, drive, steps, named~, at~)
  if start > 0.0 {
    v.start_at = start
  }
  viewer.set(Some(v))
}

///|
/// A viewer of `a` (what it read before, kept, taken at once).
pub fn new_viewer(
  station : String,
  key : String,
  a : Attachment,
  drive : DriveFile?,
  steps : Stepping,
  named? : Bool = false,
  at? : String = "",
  beside? : Bool = false,
) -> Viewer {
  let (kind, mime, _) = preview_kind(a.name)
  let v : Viewer = {
    station,
    key,
    file: a,
    name: base_name(a.path),
    drive,
    named,
    kind,
    mime,
    sniffed: @signals.signal(None),
    sniffing: @signals.signal(false),
    bytes: @signals.signal(None),
    fetching: @signals.signal(false),
    got: @signals.signal(None),
    error: @signals.signal(None),
    asked: false,
    save_after: false,
    share_after: false,
    download_asked: false,
    install_after: false,
    awake: true,
    awake_told: @signals.signal(0),
    asked_told: @signals.signal(0),
    near_bar: false,
    // (a tab's fitted as the whole window's is, but always as on a narrow stage: tab_picture_node lays it out so)
    zoom: if beside {
      @kit.Zoom::new(margin=fn(_) { tab_picture_margin })
    } else {
      @kit.Zoom::new()
    },
    // (a film edge to edge, enlarged, as the player puts it: what it flies to and from)
    vzoom: video_zoom(),
    source: false,
    source_told: @signals.signal(0),
    flow_told: @signals.signal(0),
    page: None,
    pdf: None,
    text: None,
    colored: None,
    colored_dark: false,
    flow: None,
    image: "",
    started: false,
    closing: false,
    fade: @motion.Way::new(0.0),
    held: false,
    last_x: 0.0,
    last_y: 0.0,
    moved: 0.0,
    pinch_d: 0.0,
    pinch_x: 0.0,
    pinch_y: 0.0,
    pinched: false,
    reads: @signals.signal(0),
    pinned: None,
    steps,
    at,
    swiping: false,
    down_x: 0.0,
    down_y: 0.0,
    down_lx: 0.0,
    down_ly: 0.0,
    at_left: false,
    at_right: false,
    caught: false,
    strip_down: 0.0,
    flies: false,
    // (at the stage till a flight says otherwise: its share of the ground whole)
    fly: @motion.Way::new(1.0),
    fly_back: false,
    fly_from: None,
    fly_lift: 0.0,
    fly_to: None,
    fly_pic: "",
    start_at: match pv_frames.get(station + "/" + key + "/" + a.path) {
      Some((_, ms)) if drive is None && ms > 0.0 => ms
      _ => -1.0
    },
    leaving_grab: false,
    left_at: 0.0,
    grab_told: @signals.signal(0),
    media: None,
    copied: 0,
    head_w: 0.0,
    serial: {
      viewers_opened.val = viewers_opened.val + 1
      viewers_opened.val
    },
    in_tree: false,
    tree_layers: 0,
    tree_back: @signals.signal(false),
    fingers: Map([]),
    speed: @ui.Velocity::new(),
    hold_off: fn() {  },
    lift: @motion.Way::new(0.0),
    beside,
    plays_now: !beside,
  }
  // (one named by its path read anew each time: it may have changed since)
  if !named {
    v.bytes.set(kept_read(v.id()))
  }
  v
}

///|
/// A file sent with a chat's message, kept by its name there (not a drive's, not one a message names by its path).
pub fn Viewer::chat_file(self : Viewer) -> Bool {
  self.drive is None && !self.named
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
/// The row in an occurrence's place and the file or quote within it.
fn place_parts(at : String) -> (String, String) {
  match at.rev_find("/") {
    Some(i) => (at.exact_view(end=i).to_owned(), at.exact_view(start=i).to_owned())
    None => (at, "")
  }
}

///|
/// The chat's row keeps the identity it had before the core took it over (Reading::sent_as).
fn placed_row(station : String, session : String, row : String) -> String {
  match readings.get(station + "\u{1}" + session) {
    Some(r) => {
      r.sent_as_told.get() |> ignore
      r.sent_as.get(row).unwrap_or(row)
    }
    None => row
  }
}

///|
/// The occurrence as its list knows it, including a row that went from local to the core's outbox.
pub fn thumb_occurrence(station : String, session : String, at : String) -> String {
  if at == "" {
    ""
  } else {
    let (row, part) = place_parts(at)
    placed_row(station, session, row) + part
  }
}

///|
/// A file can be drawn in several messages or quotes. Its thumbnail's place is separate from the file's identity,
/// which still names the shared bytes and video frame. The list's row identity survives the outbox handoff.
pub fn thumb_place(file : String, station : String, session : String, at : String) -> String {
  if at == "" {
    file
  } else {
    let place = thumb_occurrence(station, session, at)
    Json::array([Json::string(file), Json::string(session), Json::string(place)]).stringify()
  }
}

///|
pub fn Viewer::thumb_id(self : Viewer) -> String {
  match self.steps {
    InChat(_, session) => thumb_place(self.id(), self.station, session, self.at)
    _ => self.id()
  }
}

///|
/// What the core now calls an occurrence opened before its local row was handed over.
fn Viewer::gallery_at(self : Viewer) -> String {
  match self.steps {
    InChat(_, session) =>
      match readings.get(self.station + "\u{1}" + session) {
        Some(r) => {
          r.sent_as_told.get() |> ignore
          let (row, part) = place_parts(self.at)
          for source, sent_row in r.sent_as {
            if sent_row == row {
              return source + part
            }
          }
          self.at
        }
        None => self.at
      }
    _ => self.at
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
/// The images stepped through slide this far apart, on SLIDE (critically damped, 400).
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
  /// where the strip of pictures is (the one shown's offset across), its way said at each cause's moment
  way : @motion.Way
  mut leaving : Leaving?
  /// where the strip is held for a fixture's shot (a swipe halfway), else None
  mut pinned : Double?
  /// the viewers of the images beside the one shown (by their ids), read ahead
  near : Map[String, Viewer]
}

///|
pub let pv_strip : Strip = { way: @motion.Way::new(0.0), leaving: None, pinned: None, near: Map([]) }

///|
/// The images beside one asked of the core (`imageNear`), each by its params: let go with the chat they are of
/// (chat_left), as they hold its thread there.
pub let near_asked : Map[String, Map[String, Json]] = Map([])

///|
/// The images beside those of `station`'s chats let go (a chat of it left).
pub fn near_left(src : Source, station : String) -> Unit {
  let gone = []
  near_asked.each(fn(k, p) {
    if p.get("station") == Some(Json::string(station)) {
      gone.push(k)
      (src.leave)("imageNear", p, TopicLeave::Legacy)
    }
  })
  for k in gone {
    near_asked.remove(k)
  }
}

///|
/// The way out of a viewer closed (Viewer::shut), said to move: at rest at the latest end of its fade's and its
/// flight's.
priv struct PreviewOut {
  v : Viewer
}

///|
/// Who tells the way out of a viewer closed (PreviewOut).
// kept across runs: it only names the way out to the frame's context, which keeps its own list (Ctx::moving_as)
let pv_out_mover : @ui.Mover = @ui.Mover::new()

///|
impl @ui.Moving for PreviewOut with rest_at(self, now, frame) {
  ignore(now)
  ignore(frame)
  let (fade, fly) = (self.v.fade.ends_at(), self.v.fly.ends_at())
  if fade > fly {
    fade
  } else {
    fly
  }
}

///|
/// The viewer gone at once (the one open and the one going), what it holds let go (its player stopped, its page and
/// PDF closed).
pub fn close_now() -> Unit {
  marks_leave()
  // (closed at once: nothing of its strip goes on)
  pv_strip.leaving = None
  pv_strip.way.put(0.0)
  match viewer.get() {
    Some(v) => v.let_go()
    None => ()
  }
  viewer.set(None)
  leaving_done()
}

///|
/// The viewer that was going, gone.
pub fn leaving_done() -> Unit {
  match pv_leaving.get() {
    Some(v) => v.let_go()
    None => ()
  }
  pv_leaving.set(None)
}

///|
/// What a viewer holds of the host's, let go.
pub fn Viewer::let_go(self : Viewer) -> Unit {
  // read in a desktop's reader (@sf.reader): what it read let go with it
  @sf.reader_let_go(self.read_key())
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
  viewer.get() is Some(_)
}

///|
/// The kind it shows as, once known.
pub fn Viewer::shown_kind(self : Viewer) -> PKind? {
  match self.kind {
    Some(k) => Some(k)
    None =>
      match self.sniffed.get() {
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
    None => self.kind is None && self.sniffed.get() is Some(_)
    // (shown as it comes, however big)
    Some(_) if self.flows() => false
    Some(_) => self.file.size > big_file
  }
}

///|
pub fn Viewer::dark(self : Viewer) -> Bool {
  // on the page's own canvas whatever it shows; a film and a song in their player, dark as
  // the player is
  self.shown_kind() == Some(KVideo) || self.shown_kind() == Some(KAudio)
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
/// What a file a message names is read by (`file.open`): its path as the message has it, in its agent's session.
pub fn named_params(v : Viewer) -> Map[String, Json] {
  {
    "station": Json::string(v.station),
    "key": Json::string(v.key),
    "path": Json::string(v.file.path),
  }
}

///|
/// Where it was opened, as the core keeps it with what it reads of it (its KeptFrom: what is brought after everything
/// else is only what was opened, and is opened again from where it is listed): a drive's where it is; a chat's, the
/// chat and the file as its message has it.
pub fn Viewer::opened_from(self : Viewer) -> Json {
  match self.drive {
    Some(d) => { "root": Json::string(d.root), "path": Json::string(d.path) }
    None => {
      let o : Map[String, Json] = { "file": attachment_json(self.file, self.file.owner) }
      match self.steps {
        InChat(thread, session) => {
          o["session"] = Json::string(session)
          match thread {
            Some(n) => o["thread"] = Json::number(n)
            None => ()
          }
        }
        _ => ()
      }
      Json::object(o)
    }
  }
}

///|
/// The call a part of it is read by: a chat's file `station.file.part`, a drive's `drive.read`, one a message names
/// `file.open`.
pub fn Viewer::part_call(self : Viewer) -> String {
  if self.drive is Some(_) {
    "drive.read"
  } else if self.named {
    "file.open"
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
    None if self.named => named_params(self)
    None => {
      let p = file_params(self)
      if keep == "played" {
        chat_keep(p, self.file.size)
      }
      p
    }
  }
  // (where it was opened, for what is brought after everything else: a video or song, as played)
  if keep == "played" {
    p["from"] = self.opened_from()
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
/// How a host's own reader reads the parts `stream_part` would (@ui.NativeView::video's `direct`), past the app: the
/// core's `call` with `p` (its `offset` and `length` each part's own), the whole's size as `size` says it (0 not known).
pub fn direct_part(call : String, p : Map[String, Json], size : Double) -> String {
  let q : Map[String, Json] = Map([])
  for k, v in p {
    if k != "offset" && k != "length" {
      q[k] = v
    }
  }
  q["stream"] = Json::boolean(true)
  Json::object({ "call": Json::string(call), "params": Json::object(q), "size": Json::number(size) }).stringify()
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
/// Whether a chat's file read whole is kept with its chat: pictures as well as PDFs, videos, songs and big files.
/// A file named by its path may change and is always read as it is now.
pub fn Viewer::kept_whole(self : Viewer) -> Bool {
  guard !self.named else { return false }
  match self.shown_kind() {
    Some(KImage) | Some(KPdf) | Some(KVideo) | Some(KAudio) => true
    _ => self.file.size > big_file
  }
}

///|
/// The whole of it: a chat's in one `station.file`; a drive's a part (4 MB) at a time, as its reader reads.
pub fn Viewer::read_whole(self : Viewer, src : Source, done : (Result[Bytes, Json]) -> Unit) -> Unit {
  // (its answer one change, whoever asked (the one shown, or read ahead beside it): what came, or that it failed, told
  // with its no longer being read, never what follows either running between them and asking again)
  let done = fn(r) {
    @signals.start_batch()
    self.got.set(None)
    done(r)
    @signals.end_batch()
  }
  match self.drive {
    // one a message names: as it is now (at most 16 MB)
    None if self.named =>
      (src.read_bytes)("file.open", Json::object(named_params(self)), fn(r) {
        match r {
          Ok((_, bytes)) => done(Ok(bytes))
          Err(e) => done(Err(e))
        }
      })
    // what else, an image too (grown from its thumbnail meanwhile): how much has come as it comes, said in its bar
    // as the web's (the core's `{loaded, total}`)
    None => {
      let p = file_params(self)
      p["progress"] = Json::boolean(true)
      if self.kept_whole() {
        chat_keep(p, self.file.size)
        p["from"] = self.opened_from()
      }
      (src.read_going)(
        "station.file",
        Json::object(p),
        fn(v) {
          match field(Some(v), "loaded") {
            Some(Number(n, ..)) =>
              self.got.set(Some(
                (
                  n,
                  match field(Some(v), "total") {
                    Some(Number(t, ..)) => Some(t)
                    _ => None
                  },
                ),
              ))
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
              self.got.set(Some((got.val.to_double(), Some(total.to_double()))))
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
pub fn Viewer::fetch(self : Viewer, src : Source) -> Unit {
  let v = self
  // (each asked once a viewer, by its file: nothing a build changes)
  if v.kind is None && v.sniffed.get() is None && !v.sniffing.get() {
    v.sniffing.set(true)
    v.read_part(src, 0.0, 8192, "file", fn(r) {
      v.sniffing.set(false)
      v.sniffed.set(Some(
        match r {
          Ok((_, bytes)) => @codec.looks_like_text(bytes)
          // a station from before parts cannot say: told of, as anything else not shown
          Err(_) => false
        },
      ))
    })
    return
  }
  match v.shown_kind() {
    // a film or a song: the one player (@sf.player_view), read through the core a part at a time (never the whole file
    // first, a seek far ahead one more ranged read), from the frame it was left at (the thumbnail's)
    // (a tab's its own, by its viewer: its view and what its player's view holds not the whole window's, nor another
    // tab's)
    Some(KVideo) | Some(KAudio) => {
      if v.media is None {
        let m = @sf.new_media(if v.beside { "preview-media/" + v.serial.to_string() } else { "preview-media" })
        let start = if v.start_at > 0.0 { v.start_at } else { 0.0 }
        v.start_at = -1.0
        m.open(
          {
            name: v.file.name,
            mime: v.mime,
            audio: v.shown_kind() == Some(KAudio),
            read: fn(offset, length, answer) {
              // its bytes here already (one waiting in the composer: no station has it yet), played from them
              match v.bytes.get() {
                Some(b) => {
                  let from = offset.to_int()
                  let to = if from + length < b.length() { from + length } else { b.length() }
                  answer(if from < to { b[from:to].to_owned() } else { b"" }, b.length().to_double(), false)
                  return fn() {  }
                }
                None => ()
              }
              // (one a message names: each part in one piece, `file.open` streams none)
              if v.named {
                let gone = Ref(false)
                v.read_part(src, offset, length, "", fn(r) {
                  guard !gone.val else { return }
                  match r {
                    Ok((said, bytes)) => {
                      answer(bytes, number(Some(said), "size"), true)
                      answer(b"", number(Some(said), "size"), false)
                    }
                    Err(_) => answer(b"", -2.0, false)
                  }
                })
                return fn() { gone.val = true }
              }
              stream_part(src, v.part_call(), v.part_params(offset, length, "played"), v.listed_size(), answer, ended=fn(r) {
                match r {
                  Ok(bytes) => {
                    if v.reads.get() < 3 {
                      @ui.log("preview: \{v.name} @\{offset.to_int()} \{bytes} bytes through the core (\{v.part_call()})")
                    }
                    v.reads.set(v.reads.get() + 1)
                  }
                  Err(e) => @ui.log("preview: \{v.name} @\{offset.to_int()} failed: \{e.stringify()}")
                }
              })
            },
            // (its bytes here, or one a message names: read by the app alone, as above)
            direct: if v.bytes.get() is None && !v.named && !v.file.path.has_prefix("draft:") {
              direct_part(v.part_call(), v.part_params(0.0, 0, "played"), v.listed_size())
            } else {
              ""
            },
          },
          start~,
          play=v.plays_now,
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
  // code and text: shown as they come, a part at a time (viewer_flow.mbt), its first part asked here
  if v.flows() && !v.asked && v.bytes.get() is None {
    if v.flow is None {
      v.read_on(src)
    }
    return
  }
  let want = !v.told_of() || v.asked
  if want && v.bytes.get() is None && !v.fetching.get() && v.error.get() is None &&
    (v.kind is Some(_) || v.sniffed.get() is Some(_)) {
    v.fetching.set(true)
    v.read_whole(src, fn(r) {
      v.fetching.set(false)
      match r {
        Ok(bytes) => {
          @ui.log(
            "preview: \{v.name} read whole through the core (\{if v.drive is Some(_) { "drive.read" } else if v.named { "file.open" } else { "station.file" }}, \{bytes.length()} bytes)",
          )
          v.bytes.set(Some(bytes))
          if !v.named {
            keep_read(v.id(), bytes)
          }
        }
        Err(e) =>
          v.error.set(Some(
            match text(Some(e), "message") {
              "" => e.stringify()
              m => m
            },
          ))
      }
    })
  }
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
/// Viewer `v` set out at the moment `at` (its cause's: where it is a node of the window's tree, as that node is made,
/// viewer_tree.mbt), once: growing from its thumbnail, or fading in.
pub fn Viewer::set_out(self : Viewer, c : @ui.Ctx, src : Source, at : Double) -> Unit {
  let v = self
  if !v.started {
    v.started = true
    // it comes up in the keyboard's place: what was being typed into lets go of it first
    c.blur()
    // an image grows from its thumbnail when the chat shows it and its size is known here
    match v.flight_target(c, src) {
      Some(to) =>
        match thumb_of(c, v.thumb_id()) {
          Some(t) => {
            v.flies = true
            v.fly_back = false
            v.fly_from = Some(t)
            // a video's: its still (the frame it was left at, else what its thumbnail shows), the black where it has
            // none
            if v.shown_kind() == Some(KVideo) {
              v.fly_pic = v.still(src)
            }
            // (the whole way on one curve, its way out from under the bar or composer first, if any, then the growing:
            // Viewer::flying, Viewer::lifted_at)
            let (lift, far) = fly_way(t, Some(to), (c.width, c.height))
            v.fly_lift = lift
            v.fly.put(0.0)
            v.fly.go(1.0, @motion.moved(points=far), at~)
            pv_hidden.set(v.thumb_id())
          }
          None => ()
        }
      None => ()
    }
    // as web's: fading in, when there is no thumbnail to grow from
    if !v.flies {
      v.fade.go(1.0, @motion.tween(pv_fade_ms, ease=Out), at~)
    } else {
      v.fade.put(1.0)
    }
  }
}

///|
pub fn Viewer::shut(self : Viewer, c : @ui.Ctx) -> Unit {
  if !self.closing {
    self.closing = true
    // closed at once: the one going is only drawn (what was going before it, gone)
    marks_leave()
    leaving_done()
    // (an image's zoom on its way, a double tap's glide or a fling, stops where it is: what it goes back from)
    if self.shown_kind() == Some(KImage) {
      self.zoom.stop_glide(at=viewer_moment(c))
    }
    // an image shrinks back into its thumbnail when the chat shows it (from where a flight in has got to), else
    // it fades out
    match (thumb_of(c, self.thumb_id()), self.shown_kind(), self.zoom.rect_at(viewer_moment(c))) {
      (Some(t), Some(KImage), Some(r)) => {
        self.fly_from = Some(t)
        self.fly_back = true
        self.fly_home_from(t, Some(r), viewer_moment(c), (c.width, c.height))
        pv_hidden.set(self.thumb_id())
      }
      // a video, its thumbnail on the screen: back into it with the frame it shows (grabbed first: the thumbnail keeps
      // it, and where it was), else with its still (FilePreview.kt close: flight.frame())
      (Some(t), Some(KVideo), _) if self.chat_file() && self.video_rect(c) is Some(_) => {
        self.fly_from = Some(t)
        self.fly_to = self.player_place()
        match self.view() {
          // (still flying in: back from where that has got to at once, its player's picture not seen whole meanwhile)
          Some(n) if !self.flies && n.here() && n.shown() && !n.grabbing() => {
            self.grab_set(true)
            self.left_at = n.position()
            c.tell("preview-grab", fn() { n.grab_shown(kept_frame_side) })
          }
          _ => self.fly_home("", viewer_moment(c), (c.width, c.height))
        }
      }
      // an image of a chat's page made as nodes, its thumbnail drawn: let go of at once, its picture flown back into
      // it by the window's tree (viewer_tree.mbt's image_layer: View::shared, the thumbnail's end that stays)
      (None, Some(KImage), _) if self.in_tree && tree_thumb_seen(self.thumb_id()) => {
        self.tree_back.set(true)
        self.fade.go(0.0, @motion.tween(pv_fade_ms, ease=Leave), at=viewer_moment(c))
      }
      // the way in played backwards (web's fp: ease-out on the way in, the same curve run back on the way out): the
      // ground and the picture stay nearly whole at first, then go
      _ => self.fade.go(0.0, @motion.tween(pv_fade_ms, ease=Leave), at=viewer_moment(c))
    }
    // (closed: the one going from here, its way said: what follows its going reads where it goes)
    viewer.set(None)
    pv_leaving.set(Some(self))
    // (said to move from its cause on, as what moves is: what waits on it, Tester::moving, and once it is gone a
    // test's preview_rest)
    c.moving(pv_out_mover, { v: self } as &@ui.Moving, what="the preview's way out")
    // the views under the canvas go at once (they cannot fade)
    match self.view() {
      // (once the frame's builds are over: closed as the back is taken or the marks are put, once)
      Some(n) => c.tell("preview-pause", fn() { n.pause() })
      None => ()
    }
  }
}

///|
/// The moment what is told the viewer now happens at: the event's, where a node of the window's tree takes it (its
/// cause's: viewer_tree.mbt), else the frame's.
fn viewer_moment(c : @ui.Ctx) -> Double {
  @ui.tree_cause().unwrap_or(c.moment())
}

///|
/// A video back into its thumbnail with `picture` (from where a flight in has got to, in as much of its time), from the
/// moment `at`, in a window `window` (w, h): from where its player draws it now (flung, it went on while its frame was
/// grabbed).
pub fn Viewer::fly_home(self : Viewer, picture : String, at : Double, window : (Double, Double)) -> Unit {
  self.fly_pic = picture
  if self.player_place() is Some(r) {
    self.fly_to = Some(r)
  }
  self.fly_back = true
  match self.fly_from {
    Some(t) => self.fly_home_from(t, self.fly_to, at, window)
    None => ()
  }
  pv_hidden.set(self.thumb_id())
}

///|
/// Where its player draws a film's picture (@sf.player_picture_at: zoomed, moved, as it was last drawn).
fn Viewer::player_place(self : Viewer) -> (Double, Double, Double, Double)? {
  match self.media {
    Some(m) => @sf.player_picture_at(m.key())
    None => None
  }
}

///|
/// Back towards thumbnail `t` from as far along as it was (from `from`, where the picture is on the stage), in as much
/// of its time: shrinking, then (if the bar or the composer hides it now) going in under them at its own size. The
/// way re-shared for where `t` is now, so that it has grown, or gone out, as far as it had. A move of its own, on Move from where it is: quick as it sets out, at
/// rest as it lands (the way in run backwards would land at its quickest, the thumbnail and the bars come back at
/// once: a flash). From the moment `at`, in a window `window` (w, h).
fn Viewer::fly_home_from(
  self : Viewer,
  t : Thumb,
  from : (Double, Double, Double, Double)?,
  at : Double,
  window : (Double, Double),
) -> Unit {
  if !self.flies {
    self.flies = true
    self.fly_lift = 0.0
    self.fly.put(1.0)
  }
  let (was, q) = (self.fly_lift, self.fly.value_at(at))
  let (lift, far) = fly_way(t, from, window)
  let q = if q >= was {
    lift + (q - was) / (1.0 - was) * (1.0 - lift)
  } else if was > 0.0 {
    q / was * lift
  } else {
    0.0
  }
  self.fly_lift = lift
  self.fly.put(q)
  // (what is left of its way: as far as it had come)
  self.fly.go(0.0, @motion.moved(points=far), at~)
}

///|
/// A video closing into its thumbnail, its frame grabbed: once here, kept for the thumbnail (with where it was) and
/// gone back with; none to be had, back with its still: from the moment `at` (the answer's), in a window `window` (w, h).
pub fn Viewer::left_with_frame(self : Viewer, src : Source, at : Double, window : (Double, Double)) -> Unit {
  let n = match self.view() {
    Some(n) => n
    None => {
      self.grab_set(false)
      self.fly_home(self.still(src), at, window)
      return
    }
  }
  match n.grabbed() {
    Some(jpeg) => {
      self.grab_set(false)
      if jpeg.length() > 0 {
        pv_frames_n.val += 1
        let key = "mem:pv-frame/\{pv_frames_n.val}/\{self.name}"
        @ui.add_image(key, jpeg)
        pv_frames[self.id()] = (key, self.left_at)
        pv_frame_tell(self.id())
        self.fly_home(key, at, window)
      } else {
        self.fly_home(self.still(src), at, window)
      }
    }
    None => ()
  }
}

///|
/// Whether a video closing into its thumbnail waits for the frame it shows to be grabbed (leaving_grab), told
/// (grab_told).
fn Viewer::grab_set(self : Viewer, on : Bool) -> Unit {
  if self.leaving_grab != on {
    self.leaving_grab = on
    self.grab_told.set(self.grab_told.untracked() + 1)
  }
}

///|
/// A tap (a click) on the stage shows or hides the bars: nothing else hides them.
pub fn Viewer::toggle(self : Viewer) -> Unit {
  self.awake = !self.awake
  self.awake_said()
}

///|
pub fn Viewer::wake(self : Viewer) -> Unit {
  if !self.awake {
    self.awake = true
    self.awake_said()
  }
}

///|
fn Viewer::awake_said(self : Viewer) -> Unit {
  self.awake_told.set(self.awake_told.untracked() + 1)
}

///|
/// Whether the bars show: awake, or a mouse's pointer along the top where the bar is, or while the whole of an image
/// comes, or over a page whose taps are its own, or while it marks. As each is told (marking: marks_said).
pub fn Viewer::bars_shown(self : Viewer) -> Bool {
  self.awake_told.get() |> ignore
  self.source_told.get() |> ignore
  marks_said()
  self.awake || self.near_bar || self.coming() || (self.shown_kind() == Some(KHtml) && !self.source) || marking.on
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
/// chat's draft with a quote per numbered mark.
pub fn Viewer::finish_marks(self : Viewer, to_draft : Bool) -> Unit {
  let bytes = match self.bytes.get() {
    Some(b) => b
    None => return
  }
  marks_put_down()
  let z = self.zoom
  match @ui.draw_marks(bytes, marks_json(z.nw, z.nh)) {
    Some(j) => {
      marking.job = Some(j)
      marking.busy = true
      marking.error = ""
      marking.to_draft = to_draft
      let base = match self.file.name.rev_find(".") {
        Some(i) if i > 0 => self.file.name.exact_view(end=i).to_owned()
        _ => self.file.name
      }
      let stamp = clock_stamp((src_now.val)())
      marking.job_name = pv_fill("android-chat.file.marked.name", [("name", base), ("stamp", stamp)])
    }
    None => marking.error = pv("android-chat.file.drawFailed")
  }
  marks_changed()
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
            draft_given(key)
            marks_leave()
            // (closed back to the chat, where the picture and its quotes show in the composer: nothing said of it)
            self.shut(c)
          } else {
            // (the host's picture of the marks, said once)
            keep_bytes(c, marking.job_name, "image/png", png)
          }
          marks_changed()
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
  self.shown_kind() == Some(KImage) && self.bytes.get() is None && self.error.get() is None
}

///|
/// The stage: what the file shows as, as the window's tree hosts it (viewer_tree.mbt's viewer_hosted, its outer stage
/// Hosted: read whole, not told of, nothing failed): words read as they come, words in the reader, a PDF, a page, a
/// table, code. (A film or a song is the player's: viewer_tree.mbt's viewer_player.)
pub fn Viewer::content(self : Viewer, c : @ui.Ctx, src : Source, stage : Int) -> Unit {
  let v = self
  // (预览 or 源码, as it is told: Viewer::set_source)
  v.source_told.get() |> ignore
  let kind = v.shown_kind()
  if v.flowing() {
    match (v.flow, kind) {
      (Some(f), Some(k)) => v.flow_stage(c, src, f, k, stage)
      _ => ()
    }
  } else {
    match (kind, v.bytes.get()) {
      // a text and Markdown read in the reader, as a drive's are
      (_, Some(b)) if vf_reads(v) => vf_read(v, c, src, b)
      (Some(KPdf), Some(b)) => v.pdf_stage(c, b, stage)
      (Some(k), Some(b)) => v.text_stage(c, k, b, stage)
      _ => ()
    }
  }
}

///|
/// Taps on the stage (not on what is over it) show or hide the bars.
pub fn tap_stage(c : @ui.Ctx, v : Viewer, stage : Int) -> Unit {
  c.on_press(stage, fn() {
    v.toggle()
  })
}

///|
/// A note in the middle of the stage: 24 round it, what it holds 14 apart.
pub fn Viewer::note(self : Viewer, c : @ui.Ctx, body : () -> Unit) -> Unit {
  ignore(self)
  c.box(w=Fill(1.0), h=Fill(1.0), pad=24.0, gap=14.0, align=ACenter, justify=JCenter, fn() { body() })
  |> ignore
}

///|
/// A wait: a spinner and its words on the chip's ground, round.
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
pub let reading_pill_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, leading=L5, wrap=false)

///|
pub let reading_spinner : Double = 12.0

///|
pub let file_progress_corner : Double = 14.0

///|
/// Android's C.surface2, dark, what a file's progress is on
pub let surface2_dark : Int64 = 0x2C2D31FFL

///|
/// 安装: an APK handed to the system's installer, which asks the person to confirm, once
/// its bytes are here (fetched first when it was only told of). What the system says of it comes later (app.mbt
/// system_said): the leave to install apps asked for (its page opened), 允许 still.fail 安装应用后，再次点击安装; a
/// failure, 无法安装：…. Asked by a node of the window's tree (its press, its bytes come: viewer_tree.mbt), as that is
/// done, once.
pub fn Viewer::ask_install(self : Viewer) -> Unit {
  match self.bytes.get() {
    Some(b) => @ui.install_package(self.file.name, b)
    None => {
      self.error.set(None)
      self.asked = true
      self.install_after = true
      self.asked_told.set(self.asked_told.untracked() + 1)
    }
  }
}

///|
/// 下载: the file into the system's downloads (on a phone a picture or a film into its photo album: keep_way_of), once
/// it is here. A chat's not read yet is downloaded by the core
/// (downloads.mbt): on by itself whatever becomes of this viewer, how far it has come said here and on its message,
/// kept once it is all here; a drive's is fetched first.
pub fn Viewer::ask_save(self : Viewer, c : @ui.Ctx) -> Unit {
  match self.bytes.get() {
    // kept as keep_way_of says, said once the host has answered (keep.mbt)
    Some(b) => keep_bytes(c, self.file.name, self.mime, b)
    None => self.ask_whole()
  }
}

///|
/// Whether a file a preview shows is offered to other apps from it (分享): on a phone (iOS, Android), where the
/// system's share sheet is how a picture or a file goes on to another app (WeChat, Files); beside download, which
/// keeps it on the phone. Asked for 2026-11-11 (「建议图片和文件支持ios分享功能」, then Android's too).
pub fn shares_out() -> Bool {
  @sf.picture_to_album()
}

///|
/// 分享: the file handed to the system's share sheet (@ui.share) once it is here, read whole first where it was only
/// told of (as Viewer::ask_install's, then handed on as it comes: share_after); 本机没有可打开此文件的应用 when
/// nothing takes it.
pub fn Viewer::ask_share(self : Viewer) -> Unit {
  match self.bytes.untracked() {
    Some(b) => if !@ui.share("", self.file.name, self.mime, b) { toast_later(@sf.t("android-misc.drive.noApp")) }
    None => {
      self.error.set(None)
      self.asked = true
      self.share_after = true
      self.asked_told.set(self.asked_told.untracked() + 1)
    }
  }
}

///|
/// What was asked to be shared before it was here, handed on as its whole comes, once (Viewer::ask_share).
pub fn Viewer::share_came(self : Viewer) -> Unit {
  if self.share_after && self.bytes.untracked() is Some(_) {
    self.share_after = false
    self.ask_share()
  }
}

///|
/// 下载 pressed on a node of the window's tree (a tab's tools beside a chat: viewer_tab.mbt), outside any build: as
/// Viewer::ask_save, what is here handed to the host at once (keep_now).
pub fn Viewer::save_now(self : Viewer) -> Unit {
  match self.bytes.get() {
    Some(b) => keep_now(self.file.name, self.mime, b)
    None => self.ask_whole()
  }
}

///|
/// 下载 of what is not here yet: a chat's file downloaded by the core, anything else read whole first (Viewer::ask_save's).
fn Viewer::ask_whole(self : Viewer) -> Unit {
  if self.chat_file() {
    self.download_asked = true
  } else {
    self.error.set(None)
    self.asked = true
    self.save_after = true
  }
  self.asked_told.set(self.asked_told.untracked() + 1)
}

///|
/// The core's download of this chat's file while it is listed (under way, ready, failed): None for a drive's.
pub fn Viewer::download(self : Viewer, src : Source) -> Json? {
  if !self.chat_file() {
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
/// The core's download of the file this viewer shows called off (✕ under how far it has come: a press on a node of the
/// window's tree, viewer_tree.mbt), as it is pressed.
pub fn Viewer::cancel_download(self : Viewer, src : Source, dl : Json?) -> Unit {
  ignore(self)
  download_cancel(src, text(dl, "id"))
}

// ── an image ───────────────────────────────────────────────────────────

///|
/// How far its flight has got (0 the thumbnail, 1 the stage): its share past the going out of the flight's one Move
/// (a thing moved), as the old view `c` reads it; 1 when it is not flying.
pub fn Viewer::flying(self : Viewer, c : @ui.Ctx) -> Double {
  if !self.flies {
    return 1.0
  }
  let e = self.fly.get(c)
  if e <= self.fly_lift {
    0.0
  } else {
    (e - self.fly_lift) / (1.0 - self.fly_lift)
  }
}

///|
/// Where the picture is on the stage when it is still (fitted), once its size is known here.
pub fn Viewer::flight_target(self : Viewer, c : @ui.Ctx, src : Source) -> (Double, Double, Double, Double)? {
  if !self.chat_file() {
    return None
  }
  // a video: where its picture will be, by its size as sent, else its still's (FilePreview.kt: known from the still
  // before the player is ready); none known, it fades in
  if self.shown_kind() == Some(KVideo) {
    return self.video_target(src, c.width, c.height, c.moment())
  }
  if self.shown_kind() != Some(KImage) {
    return None
  }
  let picture = self.picture(src)
  if picture == "" {
    return None
  }
  let (nw, nh) = self.natural_size(src)
  match self.zoom.rect(c) {
    Some(r) => Some(r)
    None => fitted_rect(nw, nh, c.width, c.height)
  }
}

///|
/// The most pixels an image is decoded to on its longer side, on the stage.
pub let stage_px : Int = 4096

///|
/// What an image shows drawn at `r` (where it is on the stage, or lands): its whole picture once that is decoded (its
/// decode for that size asked for here where it is not), until then what stands in for it: one picture takes
/// another's place only once it can be drawn, never a frame of nothing between them.
pub fn Viewer::shown_picture(self : Viewer, c : @ui.Ctx, src : Source, r : (Double, Double, Double, Double)) -> String {
  let picture = self.picture(src)
  if picture != self.image {
    return picture
  }
  let (_, _, w, h) = r
  if c.image_ready(picture, dmin(dmax(w, h) * c.scale, stage_px.to_double())) {
    return picture
  }
  match self.stand_in(src) {
    "" => picture
    k => k
  }
}

///|
/// Where the picture in flight is drawn (viewer_tree.mbt's flight nodes, an image's and a film's): `cut`, what shows
/// of it, on the window (from what showed of the thumbnail, cut by what it is in, to the whole stage); `box`, the box
/// it is cut to, its corners `radius` round (from the thumbnail's box and corners, each as the thumbnail resolves it,
/// to the picture's place, what the stage shows of it where it is zoomed past it, and none); `picture`, the picture in
/// it (from where it lies in the box, covering it or fitted inside it, to its place), at its own proportions all the
/// way.
priv struct FlightBox {
  cut : (Double, Double, Double, Double)
  box : (Double, Double, Double, Double)
  corners : (Double, Double, Double, Double)
  picture : (Double, Double, Double, Double)
}

///|
/// What a stage `w` × `h` shows of `r` (x, y, w, h); `r` itself where it shows none of it.
fn seen_of(r : (Double, Double, Double, Double), w : Double, h : Double) -> (Double, Double, Double, Double) {
  let (x0, y0) = (dmax(r.0, 0.0), dmax(r.1, 0.0))
  let (x1, y1) = (dmin(r.0 + r.2, w), dmin(r.1 + r.3, h))
  if x1 > x0 && y1 > y0 {
    (x0, y0, x1 - x0, y1 - y0)
  } else {
    r
  }
}

///|
/// The picture's flight from thumbnail `from` (gone out from under the bar or the composer `lifted` of the way) to
/// `to` on a stage `stage_w` × `stage_h`, `p` of the way there (Viewer::flying's): None where it has nowhere to go.
fn flight_box(
  from : Thumb,
  lifted : Double,
  to : (Double, Double, Double, Double),
  p : Double,
  stage_w : Double,
  stage_h : Double,
) -> FlightBox? {
  // out from under the bar or the composer first, at its own size, uncut as it comes clear of what cut it there
  let dy = lift_of(from) * lifted
  let (sx, sy, sw, sh) = from.seen.unwrap_or((from.x, from.y, from.w, from.h))
  // (a side cut by what it is in stays where that cuts it, on the screen; a side nothing cut goes with the box, its
  // corners whole all the way)
  let (sx, sy, sw, sh) = if dy == 0.0 {
    (sx, sy, sw, sh)
  } else {
    let cut = 0.5
    let y0 = if sy > from.y + cut { sy } else { from.y + dy }
    let y1 = if sy + sh < from.y + from.h - cut { sy + sh } else { from.y + dy + from.h }
    (sx, y0, sw, y1 - y0)
  }
  let from = { ..from, y: from.y + dy }
  let (tx, ty, tw, th) = to
  if tw <= 0.0 || th <= 0.0 {
    return None
  }
  // where the picture lies in the thumbnail's box: covering it, or fitted inside it
  let k = if from.letterbox { dmin(from.w / tw, from.h / th) } else { dmax(from.w / tw, from.h / th) }
  let (pw0, ph0) = (tw * k, th * k)
  let (px0, py0) = (from.x + (from.w - pw0) / 2.0, from.y + (if from.top_crop { 0.0 } else { (from.h - ph0) / 2.0 }))
  let along = fn(a : Double, b : Double) { a + (b - a) * p }
  // (the box to what the stage shows of a picture zoomed past it: its round corners on what is seen all the way; out
  // past the stage's cut they were square till it landed)
  let (bx, by, bw, bh) = seen_of(to, stage_w, stage_h)
  // cut, at the thumbnail, as the thumbnail is by what it is in (its card's edge), the stage whole at the other end
  let (cx, cy) = (along(sx, 0.0), along(sy, 0.0))
  Some({
    cut: (cx, cy, along(sx + sw, stage_w) - cx, along(sy + sh, stage_h) - cy),
    box: (along(from.x, bx), along(from.y, by), along(from.w, bw), along(from.h, bh)),
    corners: {
      let (tl, tr, br, bl) = from.corners.each()
      let k = 1.0 - p
      (tl * k, tr * k, br * k, bl * k)
    },
    picture: (along(px0, tx), along(py0, ty), along(pw0, tw), along(ph0, th)),
  })
}

///|
/// The thumbnail the picture flies from and back into as `c` has it now: where the chat lays it out now (it may move
/// under the viewer: the keyboard let go as it opened, a message come), what showed of it as it was last drawn moved
/// with it where it is drawn nowhere now (hidden while the picture is out); where it is not on the screen, where it was
/// last (Viewer's fly_from). Read only.
pub fn Viewer::flight_from(self : Viewer, c : @ui.Ctx) -> Thumb? {
  match (thumb_of(c, self.thumb_id()), self.fly_from) {
    // (hidden while the picture is out, it is drawn nowhere: what showed of it as it was last drawn, moved with it)
    (Some(t), Some({ seen: Some((sx, sy, sw, sh)), x, y, .. })) if t.seen is None =>
      Some({ ..t, seen: Some((sx + t.x - x, sy + t.y - y, sw, sh)) })
    (Some(t), _) => Some(t)
    (None, last) => last
  }
}

///|
/// The picture's own menu at (`x`, `y`), its whole `b` here.
fn Viewer::picture_menu_at(self : Viewer, c : @ui.Ctx, x : Double, y : Double, b : Bytes) -> Unit {
  let (label, glyph) = @sf.picture_out_way()
  let out = fn() {
    if @sf.picture_to_album() {
      keep_bytes(c, self.name, self.mime, b, way=Photos)
    } else {
      c.copy_image(b)
      self.copied += 1
    }
  }
  let items = [Some(@sf.menu_item_of(label, out, icon=glyph))]
  if shares_out() {
    items.push(Some(@sf.menu_item_of(@sf.t("android-misc.drive.share"), fn() { self.ask_share() }, icon="share")))
  }
  @sf.menu(items, from=@sf.at_point(x, y))
}

///|
/// The images beside this one (after): a chat's as the core tells them (`imageNear`, each with
/// the session that keeps it), a folder's by its order; their viewers kept (and read ahead) while they are beside it.
pub fn Viewer::near(self : Viewer, src : Source) -> (Viewer?, Viewer?) {
  self.near_by(src, fn(id, f) {
    match pv_strip.near.get(id) {
      Some(n) => n
      None => {
        let n = f()
        pv_strip.near[id] = n
        n
      }
    }
  })
}

///|
/// Which images are beside this one (Viewer::near's, by their ids): what is said of them, no viewer made for them.
pub fn Viewer::near_ids(self : Viewer, src : Source) -> (String?, String?) {
  self.near_by(src, fn(id, _) { id })
}

///|
/// The images beside this one, each as `made` takes it (its id, and how its viewer is made).
fn[T] Viewer::near_by(self : Viewer, src : Source, made : (String, () -> Viewer) -> T) -> (T?, T?) {
  if self.shown_kind() != Some(KImage) {
    return (None, None)
  }
  match self.steps {
    NoSteps => (None, None)
    InChat(thread, session) => {
      let p : Map[String, Json] = { "station": Json::string(self.station), "path": Json::string(self.file.path) }
      let at = self.gallery_at()
      if at != "" {
        p["at"] = Json::string(at)
      }
      match thread {
        Some(th) => p["thread"] = Json::number(th)
        None => p["session"] = Json::string(session)
      }
      near_asked[Json::object(p).stringify()] = p
      let told = src.topic("imageNear", p).get().value
      let side = fn(k : String) -> T? {
        match field(told, k) {
          Some(Object(_) as j) => {
            let a = attachment_of(j)
            let key = if a.owner != "" { a.owner } else { self.key }
            let at = text(told, k + "At")
            let file = self.station + "/" + key + "/" + a.path
            Some(made(thumb_place(file, self.station, session, at), fn() { new_viewer(self.station, key, a, None, self.steps, at~) }))
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
      let side = fn(i : Int) -> T? {
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
  { name: f.name, path: f.path, size: f.size, width: 0.0, height: 0.0, thumbhash: "", owner: "", upload: "", duration: 0.0, frames: 0, held: false }
}

///|
/// Whether its whole picture, read, could not be decoded (what draws it then says so alone: no picture, no stand-in,
/// no marks, no flight). As the host says it.
pub fn Viewer::picture_failed(self : Viewer) -> Bool {
  match self.bytes.get() {
    Some(_) => @ui.image_state(self.image_name()) == -1
    None => false
  }
}

///|
/// Whether the size of what it shows (Viewer::picture) is neither sent with it nor known yet, nothing of it decoded:
/// what draws it asks a small decode of it, out of sight, that says it. As the host says it.
fn Viewer::size_unknown(self : Viewer, src : Source) -> Bool {
  let picture = self.picture(src)
  picture != "" && !(self.file.width > 0.0 && self.file.height > 0.0) && @ui.image_natural(picture) is None
}

///|
/// What its whole picture is called once read (Viewer::picture).
fn Viewer::image_name(self : Viewer) -> String {
  "mem:preview/" + self.id()
}

///|
/// What shows of an image: its whole picture once read, else what stands in for it; "" while none is here.
pub fn Viewer::picture(self : Viewer, src : Source) -> String {
  match self.bytes.get() {
    Some(b) if self.image == "" => {
      self.image = self.image_name()
      @ui.add_image(self.image, b)
    }
    _ => ()
  }
  if self.image != "" {
    return self.image
  }
  self.stand_in(src)
}

///|
/// What stands in for an image until its whole picture is here and decoded: the picture its thumbnail in the chat
/// shows (the same picture, decoded already: it flies out as the chat drew it, one sent from here the picture picked),
/// else the station's thumbnail of it, else its likeness; "" none.
pub fn Viewer::stand_in(self : Viewer, src : Source) -> String {
  match pv_thumbs.get(self.thumb_id()) {
    Some(l) if l.picture != "" => return l.picture
    _ => ()
  }
  let thumb = if self.chat_file() { (src.file)(self.station, self.key, self.name) } else { "" }
  if thumb != "" && thumb != "!" {
    thumb
  } else {
    @gallery.thumbhash_image(self.file.thumbhash).unwrap_or("")
  }
}

///|
/// The images beside the one shown read ahead after its bytes came or failed, so they do not compete with it on a slow
/// link. A step can still open either at once; those no longer beside it are let go.
pub fn Viewer::read_near(self : Viewer, src : Source, before : Viewer?, after : Viewer?) -> Unit {
  let ids = []
  let ready = self.bytes.get() is Some(_) || self.error.get() is Some(_)
  for n in [before, after] {
    match n {
      Some(n) => {
        ids.push(n.thumb_id())
        if ready && n.bytes.get() is None && !n.fetching.get() && n.error.get() is None && n.file.size <= big_file {
          n.fetching.set(true)
          n.read_whole(src, fn(r) {
            n.fetching.set(false)
            match r {
              Ok(b) => {
                n.bytes.set(Some(b))
                keep_read(n.id(), b)
              }
              Err(_) => n.error.set(Some(""))
            }
          })
        }
      }
      None => ()
    }
  }
  let gone = []
  pv_strip.near.each(fn(id, _) { if !ids.contains(id) && id != self.thumb_id() { gone.push(id) } })
  for id in gone {
    pv_strip.near.remove(id)
  }
}

///|
/// Where a picture of (nw, nh) shows fitted on a stage of (bw, bh) (the viewer's fit: a margin round it, never
/// enlarged).
pub fn fitted_rect(
  nw : Double,
  nh : Double,
  bw : Double,
  bh : Double,
  bar? : Double = 0.0,
) -> (Double, Double, Double, Double)? {
  // (a zoom of its own, told once and nothing moving on it: the same at any moment)
  let z = @kit.Zoom::new()
  z.boxed(bw, bh, at=0.0)
  z.under_bars(bar, 0.0, at=0.0)
  z.natural(nw, nh, at=0.0)
  z.rect_at(0.0)
}

///|
/// The size of a viewer's picture: as sent, else as decoded, else (its whole come and not yet decoded) its stand-in's
/// meanwhile: never none while something of it shows.
pub fn Viewer::natural_size(self : Viewer, src : Source) -> (Double, Double) {
  if self.file.width > 0.0 && self.file.height > 0.0 {
    return (self.file.width, self.file.height)
  }
  match @ui.image_natural(self.picture(src)) {
    Some(s) => s
    None => @ui.image_natural(self.stand_in(src)).unwrap_or((0.0, 0.0))
  }
}

///|
/// To the one before (`dir` -1) or after (1): it takes this one's place, coming in from that side
/// as this one goes out to the other (the strip on SLIDE from where the finger left it, at its speed); with none
/// there, back.
pub fn Viewer::go(self : Viewer, c : @ui.Ctx, src : Source, dir : Int, velocity : Double) -> Unit {
  let strip = pv_strip.way
  let at = viewer_moment(c)
  let (before, after) = self.near(src)
  let to = if dir < 0 { before } else { after }
  match to {
    None => strip.go(0.0, @motion.sheet_spring, at~, velocity~)
    Some(n) => {
      let width = self.zoom.bw + slide_gap
      let from = strip.value_at(at)
      // (as it shows: its stand-in while its whole is not decoded)
      pv_strip.leaving = match self.zoom.rect_at(at) {
        Some(r) if self.picture(src) != "" => {
          let (x, y, w, h) = r
          Some({ picture: self.shown_picture(c, src, r), x, y, w, h, dir, width })
        }
        _ => None
      }
      // shown at once: no fade; its bars as they were (only a tap hides or shows them, the user 2026-10-28)
      n.started = true
      n.fade.put(1.0)
      n.awake = self.awake
      n.awake_said()
      viewer.set(Some(n))
      pv_strip.near.remove(n.thumb_id())
      strip.put(from + dir.to_double() * width)
      strip.go(0.0, @motion.sheet_spring, at~, velocity~)
      // the frame built again from the one it stepped to: a swipe let go steps in the middle of the stage's build,
      // which would go on to draw this one's picture where the strip now puts the next one (a frame of this one in its
      // place, or of nothing where the one before comes)
      c.built_from_changed("the preview stepped")
      @ui.log("preview: stepped to \{n.file.name}")
    }
  }
}

///|
/// The wheel over the stage: a desktop's pans (⇧ sideways), with ⌃ or ⌘ held (or a trackpad's pinch) zooms round the
/// pointer; a phone's zooms. (Taken by the old view still where the stage is a node of the window's tree: the tree has
/// no wheel of its own yet.)
pub fn Viewer::wheel(self : Viewer, c : @ui.Ctx, stage : Int, z : @kit.Zoom) -> Unit {
  let (px, py, _) = c.pointer()
  let (wx, wy, mods) = @ui.wheel_of(c, stage)
  self.wheeled(z, px, py, wx, wy, mods, c.moment())
}

///|
/// The wheel turned (`wx`, `wy`, with `mods` held) at (`px`, `py`) on the stage at `at` (its moment: how big the picture
/// shows then, whether zoomed then, and what it is told from there, by its glide or fling as they have it then, never
/// by what a frame last copied): a desktop's pans (⇧ sideways), with ⌃ or ⌘ held (or a trackpad's pinch) zooms round
/// the pointer; a phone's zooms.
pub fn Viewer::wheeled(
  _self : Viewer,
  z : @kit.Zoom,
  px : Double,
  py : Double,
  wx : Double,
  wy : Double,
  mods : Int,
  at : Double,
) -> Unit {
  let desk = @sf.pointer_rests()
  // (a zoom's wheel over the picture is its own: a browser's page zooms by none of it)
  if (mods & (@ui.wheel_mod_ctrl | @ui.wheel_mod_cmd | @ui.wheel_mod_pinch)) != 0 {
    @ui.keep_zoom_wheel()
  }
  if desk && z.nw > 0.0 && (wx != 0.0 || wy != 0.0) {
    if (mods & (@ui.wheel_mod_ctrl | @ui.wheel_mod_cmd)) != 0 {
      let fine = (mods & @ui.wheel_mod_ctrl) != 0 && wy.abs() < desk_pinch_step
      z.zoom_to(
        z.scale_at(at) * @dmath.exp(-wy * (if fine { desk_pinch_rate } else { desk_wheel_rate })),
        px,
        py,
        false,
        at~,
      )
    } else if !z.zoomed_at(at) {
      // (fitted, it is all in view: nothing to pan, and it stays fitted as the window changes)
      ()
    } else if (mods & @ui.wheel_mod_shift) != 0 && wx == 0.0 {
      z.pan(-wy, 0.0, at~)
    } else {
      z.pan(-wx, -wy, at~)
    }
  } else if !desk && wy != 0.0 && z.nw > 0.0 {
    z.zoom_to(z.scale_at(at) * @dmath.pow(1.0015, -wy), px, py, false, at~)
  }
}

///|
/// One finger moving a zoomed picture by (dx, dy): it goes with the finger; at its edge, what of the way across it
/// cannot go pulls in the one beside it (the strip, as a swipe does it fitted: past the first or the last a third as
/// far), but only from an edge it was at as the finger went down: a press that brings it to its edge stops there, and
/// another from there goes on to the one beside it (the user, 2026-10-28); the finger going back takes the strip back
/// first.
pub fn Viewer::drag_zoomed(
  self : Viewer,
  z : @kit.Zoom,
  strip : @motion.Way,
  dx : Double,
  dy : Double,
  has_before : Bool,
  has_after : Bool,
  at : Double,
) -> Unit {
  // how far the strip goes for a point of the finger's way toward the one before (> 0) or after
  let give = fn(toward : Double) { if (if toward > 0.0 { has_before } else { has_after }) { 1.0 } else { 1.0 / 3.0 } }
  let mut across = dx
  let s = strip.value_at(at)
  if s != 0.0 && across != 0.0 && (across > 0.0) != (s > 0.0) {
    let back = -s / give(s)
    if across.abs() <= back.abs() {
      strip.put(s + across * give(s))
      across = 0.0
    } else {
      strip.put(0.0)
      across = across - back
    }
  }
  let x0 = z.rect_at(at).map(fn(r) { r.0 }).unwrap_or(0.0)
  z.pan(across, dy, at~)
  let left = across - (z.rect_at(at).map(fn(r) { r.0 }).unwrap_or(0.0) - x0)
  let from_edge = if left > 0.0 { self.at_left } else { self.at_right }
  if left.abs() > 0.001 && (has_before || has_after) && from_edge {
    if !self.swiping {
      self.swiping = true
      pv_strip.leaving = None
    }
    strip.put(strip.value_at(at) + left * give(left))
  }
}

// ── a video ────────────────────────────────────────────────────────────

///|
/// The chat's still of a video, as the chat shows it: the frame it was left at when it was
/// closed into its thumbnail, else what its thumbnail shows, else the station's poster (its first frame); an image's
/// key, "" while it comes or where there is none (a drive's file).
pub fn Viewer::still(self : Viewer, src : Source) -> String {
  if !self.chat_file() {
    return ""
  }
  match pv_frames.get(self.id()) {
    Some((k, _)) => return k
    None => ()
  }
  // what its thumbnail in the chat shows (video_still: one sent from here, the host's picture of it as it was picked)
  match pv_thumbs.get(self.thumb_id()) {
    Some(l) if l.picture != "" => return l.picture
    _ => ()
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
/// Where a film's picture is fitted in the viewer (vzoom), clear of the player's bar and controls (@sf.player_room).
fn Viewer::video_rect(self : Viewer, c : @ui.Ctx) -> (Double, Double, Double, Double)? {
  let top = @sf.player_room(c.width).0
  self.vzoom.rect(c).map(fn(r) { (r.0, r.1 + top, r.2, r.3) })
}

///|
/// The same at the moment `at`, its player laid out `width` wide.
fn Viewer::video_rect_in(self : Viewer, width : Double, at : Double) -> (Double, Double, Double, Double)? {
  let top = @sf.player_room(width).0
  self.vzoom.rect_at(at).map(fn(r) { (r.0, r.1 + top, r.2, r.3) })
}

///|
/// How a film's picture is fitted on the stage (Viewer's vzoom, and where it flies to before that is fitted): edge to
/// edge, no margin, made bigger where it is smaller than the stage.
fn video_zoom() -> @kit.Zoom {
  @kit.Zoom::new(margin=fn(_) { 0.0 }, enlarge=true)
}

///|
/// How big a film's picture is (what the player fits it by, Viewer::player_stage, and what its flight goes to before
/// that): as its player says, else as it was sent, else as its still is; none known, (0, 0).
fn Viewer::video_natural(self : Viewer, src : Source) -> (Double, Double) {
  match self.view().map(fn(n) { n.natural() }) {
    Some((nw, nh)) if nw > 0.0 && nh > 0.0 => return (nw, nh)
    _ => ()
  }
  if self.file.width > 0.0 && self.file.height > 0.0 {
    return (self.file.width, self.file.height)
  }
  let still = if self.shown_kind() == Some(KVideo) { self.still(src) } else { "" }
  match @ui.image_natural(still) {
    Some((sw, sh)) if still != "" && sw > 0.0 && sh > 0.0 => (sw, sh)
    _ => (0.0, 0.0)
  }
}

///|
/// Where a film's picture is, its player laid out `width` by `height`: where the player fitted it (Viewer::video_rect_in);
/// before it has (its first frame: the flight in setting out as it opens), where it will, by the same size
/// (Viewer::video_natural), in the room the player leaves it, at the moment `at`. None, its size not known.
fn Viewer::video_target(
  self : Viewer,
  src : Source,
  width : Double,
  height : Double,
  at : Double,
) -> (Double, Double, Double, Double)? {
  match self.video_rect_in(width, at) {
    Some(r) => Some(r)
    None => {
      let (nw, nh) = self.video_natural(src)
      let (top, foot) = @sf.player_room(width)
      // (fitted as the player fits it: its zoom's way, edge to edge, made bigger where it is smaller)
      let z = video_zoom()
      z.boxed(width, height - top - foot, at~)
      z.natural(nw, nh, at~)
      z.rect_at(at).map(fn(r) { (r.0, r.1 + top, r.2, r.3) })
    }
  }
}

///|
/// Esc closes the viewer, while nothing in it reads Esc of its own first (the player's menus and its list, once it is
/// up; marking's marks).
fn Viewer::shut_on_escape(self : Viewer, c : @ui.Ctx) -> Unit {
  // (the keymap's viewer.escape where it is up, at its key's moment)
  if !self.closing {
    c.key_context("Viewer")
    c.on_action("viewer.escape", fn() {
      if self.closing {
        return false
      }
      self.shut(c)
      true
    })
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
/// the chat's still of it shows until its first frame does. A tab's beside a chat embedded in the tab's stage
/// (@sf.player_view's `embedded`: on the page's ground, its picture in the room over its controls as far in as a tab's
/// picture is, tab_picture_margin), not flying, no keys.
pub fn Viewer::player_stage(self : Viewer, c : @ui.Ctx, src : Source, stage : Int) -> Unit {
  let v = self
  let m = match v.media {
    Some(m) => m
    // (a tab's: nothing of its own till its player is made, no keys)
    None => {
      if !v.beside {
        tap_stage(c, v, stage)
        v.shut_on_escape(c)
      }
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
  // (clear of the bar and the controls as the player fits it: player_room)
  let (top, foot) = @sf.player_room(c.width, embedded=v.beside)
  z.boxed(c.width, c.height - top - foot, at=c.moment())
  // (as big as its player says, else as sent, else as its still: Viewer::video_natural, what its flight goes to too)
  let (nw, nh) = v.video_natural(src)
  if nw > 0.0 && nh > 0.0 {
    z.natural(nw, nh, at=c.moment())
  }
  z.step(c)
  // flying (from the thumbnail's box to the picture's place, or back from where the player last drew it: the window's
  // tree's, viewer_tree.mbt's viewer_player, its bars coming with it there): the player not up yet, drawing no ground
  // of its own, its Esc not read: the viewer's, as it is over an image in flight
  let flying = v.flies && (!v.closing || !v.leaving_grab)
  if flying {
    v.shut_on_escape(c)
  }
  let file : @sf.ViewerFile = {
    name: v.file.name,
    size: v.file.size,
    mtime: 0.0,
    mime: v.mime,
    kind: if v.shown_kind() == Some(KAudio) { "audio" } else { "video" },
    title: if v.file.path.has_prefix("draft:") { "" } else { v.file.path },
    key: "",
    bytes: None,
    read: fn(_, _, done) { done(Err("")) },
    stream: None,
    direct: "",
    beside: None,
    place: fn() { NeverLeft },
    keep_place: fn(_, _) {  },
    save: fn() { v.ask_save(c) },
    facts: { width: v.file.width, height: v.file.height, duration: v.file.duration, frames: v.file.frames },
  }
  @sf.player_view(
    c,
    m,
    file,
    [],
    back_label=v.desk_back(src),
    on_back=fn() { v.shut(c) },
    on_go=fn(_) {  },
    // (the chat's still where its picture will be, until its first frame shows)
    still~,
    flying~,
    // (closed by its fade: its controls away at once, the page showing through as it goes; flown back into its
    // thumbnail they go with it as it shrinks, its ground whole till they are gone: bars_share)
    going=v.closing && !v.flies,
    move_beside=if !v.beside && beside_offered(v.file.path, v.file.name) { Some(fn() { v.move_beside() }) } else { None },
    // (a tab's: in its stage under the tab's tools, which have its name, 下载 and 全屏)
    embedded=v.beside,
    margin=if v.beside { tab_picture_margin } else { 0.0 },
  )
}

///|
/// Haze's blur of 24 dp and 20 dp as CSS's (glass.mbt: (px - 0.5) / 0.57735 dp).
pub let dark_glass_blur : Double = 24.0 * 0.57735 + 0.5

///|
pub let page_glass_blur : Double = 20.0 * 0.57735 + 0.5

///|
/// The frosted glass over a picture: 0x121214 at 62% over its blur; with transparency
/// reduced, that tint over black.
pub fn dark_glass() -> @ui.Glass {
  let tint = @sf.alpha(0x121214FFL, 0.62)
  @ui.Glass::frosted(blur=dark_glass_blur, tint~, solid=@sf.over(0x000000FFL, tint))
}

///|
/// The same over a document: the surface at 72% (dark, surface2's) over its blur, over the
/// viewer's canvas.
pub fn page_glass() -> @ui.Glass {
  @sf.viewer_page_glass()
}

///|
/// A button on the viewer's bars: 32 square, its corner 12, an 18 icon; quieter when
/// it cannot be pressed; `held` (the tool in use) on white at 16%, its icon near white. `on_press` as it is
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
  on_press? : () -> Unit,
) -> Unit {
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
  // named `said` (PictureButton's contentDescription), pressed while `held`; said on hover too
  c.semantics(b, Button, id~, label=said, disabled=!enabled, pressed=held)
  if live {
    @sf.tip(c, key + "/tip", id, said)
  }
  match on_press {
    Some(f) if live => c.on_press(id, f)
    _ => ()
  }
}

// ── a PDF ──────────────────────────────────────────────────────────────

///|
/// Pages drawn by the system, each as it scrolls near, as wide as the screen allows: 12
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
        pv_fill("android-chat.file.pdf.failed", [("error", if @ui.platform() >= 3 {
 @sf.t("android-chat.preview.noPdf") } else { "" })]),
        size=t.t.body,
        color=t.p.muted,
        center=true,
      )
      |> ignore
    })
    return
  }
  tap_stage(c, v, stage)
  // as the web's: 76 down, as wide as 1000 less 56 allows, 20 apart; under 640, 60 down,
  // 12 round them and between them
  let small = c.width <= @sf.viewer_small_w
  let w = if small { c.width - 2.0 * pdf_small_in } else { desk_pdf_width(c.width) }
  let side = (c.width - w) / 2.0
  let gap = if small { pdf_small_in } else { desk_pdf_gap }
  let top = v.stage_top(c, if small { page_small_top } else { desk_page_top }, gap)
  let foot = if v.beside { gap } else if small { pdf_small_in } else { viewer_foot(c) + desk_pdf_foot }
  let none = 0.0
  c.list(v.stage_key("preview/pdf/" + v.file.path), pdf.pages + 2, 400.0, fn(i) {
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
        let head = words.clamped_view(end=if words.length() < 2048 { words.length() } else { 2048 }).to_owned()
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
    // under the bar: 60 under the status bar, a desktop's 76
    let top = v.stage_top(c, if c.width <= @sf.viewer_small_w { page_small_top } else { desk_page_top }, 0.0)
    c.box(w=Fill(1.0), h=Fill(1.0), pt=top, fn() {
      if page.here() && !v.closing {
        c.native(page) |> ignore
      } else if !page.here() {
        v.note(c, fn() {
          c.text(pv("android-chat.file.cantPreview"), size=t.t.body, color=t.p.muted) |> ignore
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
  let cut = if cut {
    Some(pv_fill("android-chat.file.cut", [("size", @sf.file_size(show_limit.to_double()))]))
  } else {
    None
  }
  v.lines_stage(
    c,
    kind,
    lines.length(),
    fn(k) { lines[k] },
    fn(k) { colored.get(k) },
    cut,
    markdown=if kind == KMarkdown && !v.source { Some(words) } else { None },
  )
  |> ignore
}

///|
/// Code and text in the code face, `count` lines (`line(k)`, coloured as `colored(k)` says, else plain), in rows of 60
/// lines so a long file lays out only what is in view; or `markdown` rendered; `cut`: what it says over them of a file
/// shown only in part. Whether its last rows are in view (flow_ahead of them: a text shown as it comes reads on).
pub fn Viewer::lines_stage(
  self : Viewer,
  c : @ui.Ctx,
  kind : PKind,
  count : Int,
  line : (Int) -> String,
  colored : (Int) -> Array[@ui.Run]?,
  cut : String?,
  markdown? : String? = None,
) -> Bool {
  let v = self
  let t = @sf.theme()
  let chunks = if markdown is Some(_) { 1 } else { (count + 59) / 60 }
  let code = markdown is None && kind != KText && kind != KCsv
  // as the web's (FilePreview.css.ts fpCode 64 and the block's 16 down, 32 in, 12 on 1.6; fpPlain 76 down, 32 in, 12
  // on 1.65; under 640, 60 down, 16 in, 48 under)
  let small = c.width <= @sf.viewer_small_w && !code && markdown is None
  let top = v.stage_top(
    c,
    if small {
      page_small_top
    } else if markdown is Some(_) {
      64.0
    } else if code {
      80.0
    } else {
      desk_page_top
    },
    beside_text_top,
  )
  let foot = if markdown is Some(_) { 64.0 } else if small { plain_small_foot } else { desk_text_foot }
  let size = desk_code_size
  let height = if code { desk_code_line } else { desk_plain_line }
  let side = if small { plain_small_side } else { desk_text_side }
  let key = v.stage_key("preview/text/" + v.file.path + (if v.source { "/source" } else { "" }))
  c.list(key, chunks + 3, 400.0, fn(i) {
    if i == 0 {
      if cut is Some(_) {
        c.box(w=Fill(1.0), pl=20.0, pr=20.0, pt=8.0, pb=8.0, bg=@sf.alpha(t.p.red, 0.0), fn() {  })
        |> ignore
      }
      c.box(w=Fill(1.0), h=Px(top), fn() {  })
      |> ignore
      match cut {
        Some(words) => cut_line(c, words)
        None => ()
      }
    } else if i == chunks + 1 {
      c.box(w=Fill(1.0), h=Px(foot), fn() {  }) |> ignore
    } else if i == chunks + 2 {
      ()
    } else if markdown is Some(words) {
      c.box(w=Fill(1.0), pl=18.0, pr=18.0, fn() {
        @sf.markdown(c, words, key=v.stage_key("preview-md")) |> ignore
      })
      |> ignore
    } else {
      let from = (i - 1) * 60
      let to = if from + 60 < count { from + 60 } else { count }
      let sb = StringBuilder()
      let runs : Array[@ui.Run] = []
      let mut inked = true
      for k in from..<to {
        if k > from {
          sb.write_char('\n')
          runs.push(@ui.span("\n", mono=true))
        }
        let words = line(k)
        sb.write_string(words)
        match colored(k) {
          Some(l) => runs.push_iter(l.iter())
          None => {
            inked = inked && words == ""
            runs.push(@ui.span(words, mono=true))
          }
        }
      }
      let words = fn() {
        c.rich(
          if inked { runs } else { [@ui.span(sb.to_string(), mono=true)] },
          size~,
          color=t.p.text,
          line=height,
          wrap=!code,
          breaks=code,
        )
        |> ignore
      }
      if code {
        // scrolled across, its rows as one (32 in from its sides)
        c.sideways(v.stage_key("preview/code/" + v.file.path), across=true, padx=32.0, words) |> ignore
      } else {
        c.box(w=Fill(1.0), pl=side, pr=side, words) |> ignore
      }
    }
  })
  |> ignore
  // (built again only as that changes, not at each step of a scroll)
  let at_end = fn(i : @ui.ListInfo?) {
    match i {
      Some(i) => i.last >= chunks - flow_ahead
      None => false
    }
  }
  at_end(c.list_info_as(key, at_end))
}

///|
/// Past this a file shows as plain text, unhighlighted.
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
/// A file shown only in part: the warning's words on its tint.
pub fn cut_line(c : @ui.Ctx, words : String) -> Unit {
  let warn = 0xD9962BFFL
  c.box(w=Fill(1.0), pl=20.0, pr=20.0, pt=8.0, pb=8.0, bg=@sf.alpha(warn, 0.14), fn() {
    c.text(words, size=@sf.theme().t.meta, color=warn) |> ignore
  })
  |> ignore
}

///|
/// A table: a row number, then its columns, each as wide as what it holds (by its
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
  // a desktop's in the page's 13, 68 down to its head; a phone's in 15
  let size = desk_cell_size
  let top = v.stage_top(c, desk_table_top, 0.0)
  let cell = fn(s : String, w : Double, weight : Int, color : Int64) {
    c.box(w=Px(w), padx=16.0, pady=8.0, clip=true, fn() {
      c.text(s, size~, weight~, color~, wrap=false) |> ignore
    })
    |> ignore
  }
  c.list(v.stage_key("preview/csv/" + v.file.path), body_n + 3, 37.0, fn(i) {
    if i == 0 {
      c.box(w=Fill(1.0), h=Px(top), fn() {  }) |> ignore
    } else if i == 1 {
      c.box(dir=Row, bg=t.p.canvas, border=0.0, fn() {
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
  marks_changed()
  pv_thumbs.clear()
  thumbs_said.clear()
  pv_lists.clear()
  pv_frames.clear()
  let told = pv_frames_told.keys().to_array()
  for id in told {
    pv_frame_tell(id)
  }
  pv_frames_told.clear()
  pv_frames_n.val = 0
  pv_first.clear()
  pv_hidden.set("")
  marks_foot_taken.set(0.0)
  pv_read.clear()
  pv_strip.leaving = None
  pv_strip.way.put(0.0)
  pv_strip.pinned = None
  pv_strip.near.clear()
  near_asked.clear()
  tab_viewers_reset()
}

///|
/// A video's still as the viewer left it; else, one sent from here, the host's picture of it as it was picked (the
/// composer's tile's: going up and gone up alike, as an image sent from here is drawn: sent_picture); else the
/// station's poster (or its first frame drawn here when the station made none): its image's key ("" none). `thumb`:
/// its thumbnail's id.
pub fn video_still(c : @ui.Ctx, src : Source, station : String, owner : String, a : Attachment, thumb : String) -> String {
  match video_still_known(src, station, owner, a, thumb) {
    "!" => first_frame(c, src, station, owner, a, thumb)
    k => k
  }
}

///|
/// video_still for a node of the window's tree `v` (a chat's things' tile), read as it comes: the station's still, or
/// where it made none, the first frame drawn here (first_frame_node).
pub fn video_still_node(v : @view.View, src : Source, station : String, owner : String, a : Attachment, thumb : String) -> () -> String {
  let known = fn() { video_still_known(src, station, owner, a, thumb, told=true) }
  // (its first frame's, asked as the station is known to have made none: then, once)
  let first : @signals.Signal[(() -> String)?] = @signals.signal(None, same=fn(x, y) { physical_equal(x, y) })
  v.reacts(fn() { known() == "!" }, fn(none) {
    if none && first.untracked() is None {
      first.set(Some(first_frame_node(v, src, station, owner, a, thumb)))
    }
  })
  fn() {
    match known() {
      "!" =>
        match first.get() {
          Some(f) => f()
          None => ""
        }
      k => k
    }
  }
}

///|
/// The same as far as it is known without drawing a frame of it here (what a node shows: the viewer's still, one sent
/// from here, the station's poster): "!" where the station made none.
/// `told`: read by a node, told as the frame kept or the station's still changes (the tracking reads: pv_frame_track,
/// Source::poster_told).
fn video_still_known(src : Source, station : String, owner : String, a : Attachment, thumb : String, told? : Bool = false) -> String {
  if told {
    pv_frame_track(thumb)
  }
  match pv_frames.get(thumb) {
    Some((k, _)) => k
    None =>
      match (if told { sent_picture_told(station, a) } else { sent_picture(station, a) }) {
        Some(k) => k
        None => if told { src.poster_told(station, owner, base_name(a.path)) } else { (src.poster)(station, owner, base_name(a.path)) }
      }
  }
}

///|
/// 源码 (`on`) or 预览 shown, told at once to what shows it and what says it (Viewer::content, its bars,
/// Viewer::bars_shown): the page under the canvas let go while its source shows (and made again as it comes back).
pub fn Viewer::set_source(self : Viewer, on : Bool) -> Unit {
  if on == self.source {
    return
  }
  self.source = on
  if on {
    match self.page {
      Some(p) => p.close()
      None => ()
    }
    self.page = None
  }
  self.source_told.set(self.source_told.untracked() + 1)
}
