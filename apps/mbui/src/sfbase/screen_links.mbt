// Links to a station's screens and to its 共享调试 in an agent's words (still.fail apps/android chat/screens/ScreenLinks.kt,
// AdbLinks.kt), as the web draws them: one alone in a paragraph is its card (a screen's; 共享调试's is a link to its page
// alone too) (@sf.markdown's `screens`), a bare one within a sentence reads as its title. What a card says is the core's (the
// `screenCard` and `adbCard` topics). A screen its station previews is live in its card while the card is built (the
// messages' list builds only the rows in view) and the app is shown: `screen.view` with `peek`, small, each frame
// acknowledged peek_ms after the one before (the station sends the next once the last is acknowledged); stopped (the
// call cancelled) as the card goes from view or the app behind. JPEG, and H.264 where the host decodes it: a source
// that has JPEG sends it a preview, one with nothing else (an Android device) H.264, decoded by a Stream of the card's,
// video_peeks_most of those at once. One refused (its station previews as many as it can) or ended asks again
// peek_again_ms on while its card is on the screen. A card's tap opens its link, as a tap on the link
// does (open_links.mbt open_link).

///|
/// A preview's pace: a picture at most this often.
pub let peek_ms : Double = 500.0

///|
/// The picture a preview asks for, in pixels at most: the card's width, twice over.
pub let peek_size : Double = 640.0

///|
/// A preview refused or ended is asked for again after this, while its card shows.
pub let peek_again_ms : Double = 5000.0

///|
/// The most previews the app decodes as a video at once (an Android device's): a phone has few hardware decoders.
/// One more is let go, its mark shown, and asks again peek_again_ms on.
pub let video_peeks_most : Int = 2

///|
/// The shape of a browser's preview (16:10), and the default before another screen's size is known.
pub let peek_ratio : Double = 1.6

///|
pub let peek_ratio_least : Double = 0.75

///|
pub let peek_ratio_most : Double = 2.0

///|
/// A card uses the same icon as its tab and the shared library, centered in the file tile's room.
pub(all) struct LinkMark {
  name : String
}

///|
// kept across runs: an immutable icon name
pub let monitor_mark : LinkMark = { name: "monitor" }

///|
// kept across runs: an immutable icon name
pub let globe_mark : LinkMark = { name: "web" }


// ── the cards' looks ──

///|
/// A card: a row 236 wide, a capsule as a file's card (a row high, 52), on the chat's bubble ground: its mark, 24,
/// concentric with its round end (14 from its end, its top and its foot), 8 from its words, their end where the other
/// round end begins (@sf.file_capsule_words_end).
// kept across runs: a value (no field of it changes)
pub let link_card : @ui.Style = @ui.style(
  row=true,
  w=@sf.link_card_w,
  h=@sf.file_capsule_h,
  pl=S3_5,
  pr=@sf.room_of(@sf.file_capsule_words_end),
  gap=S2,
  align=ACenter,
  radius=Full,
  bg=Neutral,
)

///|
/// A screen's card with its preview: a column 280 wide, rounded as what a message carries is (@sf.message_file_radius),
/// the preview the ladder's inset in from its top and sides (@sf.peek_card_in_px).
// kept across runs: a value (no field of it changes)
pub let peek_card : @ui.Style = @ui.style(
  w=@sf.peek_card_w,
  pt=@sf.room_of(@sf.peek_card_in_px),
  px=@sf.room_of(@sf.peek_card_in_px),
  radius=@sf.message_file_radius,
  bg=Neutral,
)

///|
/// The words under a preview: a card's words' in from its sides (card_pad: the card's inset and their own), 12 under the
/// preview, 16 over the card's foot.
// kept across runs: a value (no field of it changes)
pub let peek_card_words : @ui.Style = @ui.css("w=Full pt=S3 pb=S4").then(
  @ui.style(px=@sf.room_of(@sf.card_pad - @sf.peek_card_in_px)),
)

///|
/// The preview: on its ground, its corners concentric with the card's, its mark in its middle until a picture comes.
// kept across runs: a value (no field of it changes)
pub let peek_frame : @ui.Style = @ui.css("w=Full align=ACenter justify=JCenter radius=Inner bg=Wash clip")

///|
/// A mark's box: its own, 24 (the gap to the words the card's).
// kept across runs: a value (no field of it changes)
pub let link_mark_box : @ui.Style = @ui.css("w=S6 h=S6 align=ACenter justify=JCenter")

///|
/// The words beside the mark (or under the preview): what is left across.
// kept across runs: a value (no field of it changes)
pub let link_words : @ui.Style = @ui.css("w=Full")

///|
/// Each of the two lines a line high, words or none (minLines = maxLines = 1): the title's 20, the line's 16.
// kept across runs: a value (no field of it changes)
pub let link_title_line : @ui.Style = @ui.css("w=Full h=S5")

///|
// kept across runs: a value (no field of it changes)
pub let link_line_line : @ui.Style = @ui.css("w=Full h=S4")

///|
/// The title (15/20, on one line); quieter for a screen its station no longer has.
// kept across runs: a value (no field of it changes)
pub let link_title : @ui.TextStyle = @sf.card_title.then(@sf.one_line).then(@sf.full_words)

///|
// kept across runs: a value (no field of it changes)
pub let link_title_gone : @ui.TextStyle = link_title.then(@sf.quiet)

///|
/// What its station says of it (11/16, muted, on one line).
// kept across runs: a value (no field of it changes)
pub let link_line : @ui.TextStyle = @sf.card_line.then(@sf.full_words)

// ── what the core says of them ──

///|
/// A link to a screen as a message shows it (the `screenCard` topic, client/core-ts/src/screens.ts screenCard).
pub(all) struct ScreenCard {
  kind : String
  title : String
  line : String
  gone : Bool
  peek : Bool
  width : Double
  height : Double
}

///|
/// The card of the screen `href` names, once the core has said.
pub fn screen_card_of(src : Source, to : @sf.LinkTo) -> ScreenCard? {
  guard to.card == "screen" else { return None }
  let (station, screen) = (to.station, to.screen)
  let v = src.topic("screenCard", { "station": Json::string(station), "screen": Json::string(screen) }).get().value
  guard v is Some(Object(_)) else { return None }
  Some({
    kind: text(v, "kind"),
    title: text(v, "title"),
    line: text(v, "line"),
    gone: flag(v, "gone"),
    peek: flag(v, "peek"),
    width: number(v, "width"),
    height: number(v, "height"),
  })
}

///|
/// The card of the 共享调试 `href` names, once the core has said.
pub fn adb_card_of(src : Source, to : @sf.LinkTo) -> Json? {
  guard to.card == "adb" else { return None }
  let station = to.station
  match src.topic("adbCard", { "station": Json::string(station) }).get().value {
    Some(Object(_)) as v => v
    _ => None
  }
}

///|
/// The links to screens in an agent's words as a chat draws them: their cards, and a bare
/// one's title (屏幕 until it is known); a station's 共享调试 a link alone too, its title its own. `message` names the message
/// (a screen's preview is its card's own).
pub fn screen_links(c : @ui.Ctx, src : Source, message : String) -> @sf.Screens {
  {
    card: fn(href, to, words) {
      match to.card {
        "service" => service_link_card(c, src, href, to, words)
        _ => screen_link_card(c, src, message + "\n" + href, href, to, words)
      }
    },
    title: fn(_href, to) {
      if to.card == "adb" {
        adb_title(src, to)
      } else if to.card == "service" {
        service_card_of(src, to).0
      } else {
        match screen_card_of(src, to) {
          Some(card) => card.title
          None => @sf.t("android-misc.screen.title")
        }
      }
    },
  }
}

///|
/// A link to a chat's web service as a card says it (the core's `job` topic, jobs.ts shown): its name (网页服务 until
/// it is known), its station's name with its port, and how it stands (运行中, 已停止…); whether it is down (stopped or
/// failed: its title quieter).
pub fn service_card_of(src : Source, to : @sf.LinkTo) -> (String, String, Bool) {
  guard to.card == "service" else { return ("", "", false) }
  let (station, job) = (to.station, to.job)
  let j = src.topic("job", { "station": Json::string(station), "id": Json::string(job) }).get().value
  let name = match text(j, "name") {
    "" => @sf.t("android-chat.preview.service")
    n => n
  }
  guard j is Some(Object(_)) else { return (name, "", false) }
  let ws = match station.find("/") {
    Some(i) => station.exact_view(end=i).to_owned()
    None => station
  }
  let at = match dv_stations(src, ws).0 {
    Some(list) =>
      match list.iter().find_first(fn(s) { s.station == station }) {
        Some(s) => s.name
        None => @settings.station_name(station)
      }
    None => @settings.station_name(station)
  }
  let port = number(j, "port").to_int()
  let place = if port > 0 { at + " :" + port.to_string() } else { at }
  (name, place + " · " + text(j, "word"), !flag(j, "open"))
}

///|
/// A link to a chat's web service as a card (an agent's link to it alone in a paragraph): the web's mark, its title
/// (the link's own words, when it has them) over its station and port and how it stands; one no longer up, its title
/// quieter. A tap opens it, as the link does: the service over its chat (open_links.mbt).
pub fn service_link_card(c : @ui.Ctx, src : Source, href : String, to : @sf.LinkTo, words : String?) -> Unit {
  let (name, line, down) = service_card_of(src, to)
  let open = c.id("service-link/" + href)
  c.on_press(open, fn() {
    open_link(href)
  })
  let title = match words {
    Some(w) => w
    None => name
  }
  c.box(style=link_card, id=open, fn() {
    link_mark(c, Some(globe_mark), Muted)
    link_card_words(c, title, line, down, link_words)
  })
  |> ignore
}

///|
/// A bare link to a station's 共享调试: what it reads as within a sentence.
pub fn adb_title(src : Source, to : @sf.LinkTo) -> String {
  match adb_card_of(src, to) {
    Some(_) as v => text(v, "title")
    None => @sf.t("android-misc.adb.title")
  }
}

// ── the cards ──

///|
/// A mark in its room, in `tint`; none (its room kept) while what it is is not known.
pub fn link_mark(c : @ui.Ctx, mark : LinkMark?, tint : @ui.Color) -> Unit {
  c.box(style=link_mark_box, fn() {
    match mark {
      Some(m) =>
        @sf.icon(c, m.name, size=24.0, color=c.color(tint))
        |> ignore
      None => ()
    }
  })
  |> ignore
}

///|
/// A card's two lines: its title over what is said of it, each a line high.
pub fn link_card_words(c : @ui.Ctx, title : String, line : String, gone : Bool, style : @ui.Style) -> Unit {
  c.box(style~, fn() {
    c.box(style=link_title_line, fn() {
      c.text(title, style=if gone { link_title_gone } else { link_title }) |> ignore
    })
    |> ignore
    c.box(style=link_line_line, fn() { c.text(line, style=link_line) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// A screen as a card: its kind's mark, its title (the link's own words, when it has
/// them) over what its station says of it; one its station no longer has, its title quieter. Its size is kept while
/// the core has not said, its lines empty. One its station previews (a tab of its browser) is the screen live across
/// the card's top, the words under it. A tap opens it, as the link does. `key`: the card's own (its message's and its
/// link's), its preview's.
pub fn screen_link_card(c : @ui.Ctx, src : Source, key : String, href : String, to : @sf.LinkTo, words : String?) -> Unit {
  let card = screen_card_of(src, to)
  let open = c.id("screen-link/" + href)
  c.on_press(open, fn() {
    open_link(href)
  })
  let gone = match card {
    Some(k) => k.gone
    None => false
  }
  let title = match (words, card) {
    (Some(w), _) => w
    (None, Some(k)) => k.title
    (None, None) => ""
  }
  let line = match card {
    Some(k) => k.line
    None => ""
  }
  match (card, if to.card == "screen" { Some((to.station, to.screen)) } else { None }) {
    (Some(k), Some((station, screen))) if k.peek && !k.gone => {
      c.box(style=peek_card, id=open, fn() {
        screen_peek(c, key, station, screen, k, target=open)
        link_card_words(c, title, line, false, peek_card_words)
      })
      |> ignore
      return
    }
    _ => ()
  }
  c.box(style=link_card, id=open, fn() {
    let mark = match card {
      None => None
      Some(k) => Some(if k.kind == "browser" { globe_mark } else { monitor_mark })
    }
    link_mark(c, mark, Muted)
    link_card_words(c, title, line, gone, link_words)
  })
  |> ignore
}

// ── a screen live in its card ──

///|
/// How a card's preview stands: not asked for, coming (its call), or ended by the station (refused, or the screen no
/// longer previewed: its picture, or its mark, stays until the card goes from view).
#derive(Eq)
pub(all) enum PeekRun {
  PeekOff
  PeekOn
  PeekEnded
}

///|
/// A card's preview.
pub(all) struct Peek {
  station : String
  screen : String
  mut run : PeekRun
  /// the view it is (`screen.view`'s `view`), and its streamed call
  mut view : String
  mut call : Int
  /// the frames come and not yet acknowledged: their `ts`, oldest first
  waiting : Array[Json]
  /// acknowledgements sent in this view
  mut acked : Int
  /// pictures come in all
  mut got : Int
  /// its pictures by their keys, oldest first: the one shown (the newest decoded) and any newer one decoding
  pictures : Array[String]
  /// its card's target (0: none): where it shows, the card is on the screen (peeks_settle); and, in the frame it changed
  /// in, the one it had before, the one the last frame showed (its row built at another place in its list, as older
  /// messages come in before it: a row's ids are by its place, while the card, its preview and its pictures are by its
  /// key)
  mut target : Int
  mut was : Int
  /// what its view's frames are (its config's `codec`): "jpeg" before one says otherwise
  mut codec : String
  /// its video's decoder (an H.264 preview), made as its config comes; each frame acknowledged as it is shown
  mut stream : @ui.Stream?
  /// it holds one of the app's video previews (video_peeks_most)
  mut video : Bool
  /// ended long enough: asked for again where its card shows (peeks_frame, peeks_settle)
  mut again : Bool
  /// held by a card made as nodes of the window's tree (screen_links_node.mbt's screen_peek_node), which starts and
  /// stops it itself: not the old view's frames' to settle (peeks_frame, peeks_settle pass it by)
  mut made : Bool
  /// how many times what a node draws of it changed (its pictures, its run, its frames waiting), told as it does: what
  /// its node binds reads it first, then the fields as they are
  mut changes : Int
  told : @signals.Signal[Int]
}

///|
/// What its node draws of it changed (Peek's `told`).
fn Peek::tell(self : Peek) -> Unit {
  self.changes += 1
  self.told.set(self.changes)
}

///|
/// The cards' previews, by card.
pub let peeks : Map[String, Peek] = Map([])

///|
/// The cards with a preview built in this pass of the frame, or held by a list's row kept as its nodes (@ui.built_used).
pub let peeks_built : Map[String, Bool] = Map([])

///|
/// Previews asked for so far: each view's name its own.
pub let peek_views : Ref[Int] = Ref(0)

///|
/// The previews decoded as a video now (video_peeks_most at most).
pub let video_peeks : Ref[Int] = Ref(0)

///|
pub fn peeks_reset() -> Unit {
  peeks.clear()
  peeks_built.clear()
  peek_views.val = 0
  video_peeks.val = 0
}

///|
pub fn peek_for(key : String, station : String, screen : String) -> Peek {
  match peeks.get(key) {
    Some(p) => p
    None => {
      let p : Peek = {
        station,
        screen,
        run: PeekOff,
        view: "",
        call: 0,
        waiting: [],
        acked: 0,
        got: 0,
        pictures: [],
        target: 0,
        was: 0,
        codec: "jpeg",
        stream: None,
        video: false,
        again: false,
        made: false,
        changes: 0,
        told: @signals.signal(0),
      }
      peeks[key] = p
      p
    }
  }
}

///|
/// The screen live in its card: only looking (not among those on it, its tab not brought
/// forward), its mark until a picture comes (a tab behind another casts none). A browser's preview keeps its shape as
/// its viewport adapts to a viewer; another screen's shape follows its picture, its listed size until one comes, within bounds. The newest picture
/// decoded fills the preview, cropped from the top; a newer one is drawn over it once it is decoded.
/// `target`: its card's (peeks_settle).
pub fn screen_peek(
  c : @ui.Ctx,
  key : String,
  station : String,
  screen : String,
  card : ScreenCard,
  target? : Int = 0,
) -> Unit {
  let p = peek_for(key, station, screen)
  if p.target != target {
    p.was = p.target
    p.target = target
  }
  peeks_built[key] = true
  // (and each frame its row or part is put back as built, kept as its nodes: mbui's kept_nodes.mbt)
  @ui.built_used(fn() { peeks_built[key] = true })
  let mut shown = -1
  let mut natural = 0.0
  for i, k in p.pictures {
    match @ui.image_natural(k) {
      Some((w, h)) => {
        shown = i
        natural = if h > 0.0 { w / h } else { 0.0 }
      }
      None => ()
    }
  }
  // (a video's picture, once one shows, over the pictures before it)
  let video = match p.stream {
    Some(st) if st.shown_any() => Some(st)
    _ => None
  }
  match video.bind(fn(st) { st.size() }) {
    Some((w, h)) if h > 0 => natural = w.to_double() / h.to_double()
    _ => ()
  }
  let listed = if card.width > 0.0 && card.height > 0.0 { card.width / card.height } else { 0.0 }
  // (a simulator's panel, and so its shape, may have changed since it was listed: as its picture has it)
  let own = if natural > 0.0 { natural } else { listed }
  let ratio = if card.kind != "browser" && own > 0.0 {
    dclamp(own, peek_ratio_least, peek_ratio_most)
  } else {
    peek_ratio
  }
  c.box(style=peek_frame, aspect=ratio, fn() {
    if shown < 0 && video is None {
      link_mark(c, Some(if card.kind == "browser" { globe_mark } else { monitor_mark }), Muted)
    }
    let from = if shown < 0 { 0 } else { shown }
    for i in from..<p.pictures.length() {
      let k = p.pictures[i]
      c.layer(fn() { peek_picture(c, k) }) |> ignore
    }
    match video {
      Some(st) =>
        c.layer(fn() { c.stream(st, fit=FitCoverAt(0.0), layer=false) |> ignore }) |> ignore
      None => ()
    }
  })
  |> ignore
}

///|
/// A picture fills the preview, centered across and cropped from the top if it is taller than the preview.
pub fn peek_picture(c : @ui.Ctx, key : String) -> Unit {
  c.image(key, w=Fill(1.0), h=Fill(1.0), fit=FitCoverAt(0.0), bg=0L, fade=false) |> ignore
}

///|
/// A value of a preview as it comes. A config: what its frames are; H.264's (an Android device's) to the card's Stream,
/// if the app decodes fewer than video_peeks_most videos now, else the preview let go (asked again later). A frame:
/// a JPEG handed over under a key of its own, its `ts` to acknowledge peek_ms after the one before; an H.264 one to
/// the Stream, acknowledged as soon as it is shown or let go (the station paces an Android preview itself).
pub fn peek_took(src : Source, p : Peek, view : String, value : Json, bytes : Bytes?) -> Unit {
  if p.view != view {
    return
  }
  peek_took_now(src, p, view, value, bytes)
  p.tell()
}

///|
/// peek_took's, of its own view's value.
fn peek_took_now(src : Source, p : Peek, view : String, value : Json, bytes : Bytes?) -> Unit {
  match field(Some(value), "config") {
    Some(Object(_) as cfg) => {
      let codec = text(Some(cfg), "codec")
      p.codec = codec
      if codec == "h264" {
        if !p.video {
          if video_peeks.val >= video_peeks_most {
            peek_end(src, p)
            return
          }
          p.video = true
          video_peeks.val += 1
        }
        let st = match p.stream {
          Some(st) => st
          None => {
            let st = @ui.Stream::new(
              // acknowledged as it is shown or let go, not at a later frame's build (nothing may build one: the
              // station would wait on it); its pace is the station's own (an Android preview's 2 frames a second)
              shown=fn(ts) {
                if p.view == view {
                  (src.call)("screen.ack", { "view": Json::string(view), "ts": Json::number(ts) }, answer_unread)
                }
              },
              broken=fn() {
                if p.view == view {
                  (src.call)("screen.keyframe", { "view": Json::string(view) }, answer_unread)
                }
              },
            )
            p.stream = Some(st)
            st
          }
        }
        match bytes {
          Some(b) => st.h264(b, number(Some(cfg), "width").to_int(), number(Some(cfg), "height").to_int())
          None => ()
        }
      }
      return
    }
    _ => ()
  }
  let f = field(Some(value), "frame")
  let ts = match field(f, "ts") {
    Some(Number(n, ..)) => Json::number(n)
    Some(String(s)) =>
      match (try Some(@json.parse(s)) catch { _ => None }) {
        Some(Number(n, ..)) => Json::number(n.floor())
        _ => return
      }
    _ => return
  }
  if p.codec == "h264" {
    match (p.stream, bytes, ts) {
      (Some(st), Some(b), Number(n, ..)) if b.length() > 0 => st.frame(b, flag(f, "key"), n)
      _ => p.waiting.push(ts)
    }
    return
  }
  match bytes {
    Some(b) if b.length() > 0 => {
      let k = "mem:sf/peek/\{view}/\{p.got}"
      p.got += 1
      @ui.add_image(k, b)
      p.pictures.push(k)
    }
    _ => ()
  }
  p.waiting.push(ts)
}

///|
/// The preview of `p` asked for (`screen.view` with `peek`, small: JPEG, and H.264 where the host decodes it).
pub fn peek_start(src : Source, p : Peek) -> Unit {
  peek_views.val += 1
  let view = "mbui-peek-\{peek_views.val}"
  p.view = view
  p.run = PeekOn
  p.call = 0
  p.acked = 0
  p.again = false
  p.codec = "jpeg"
  p.waiting.clear()
  let codecs : Array[Json] = if @ui.h264_here() { ["jpeg", "h264"] } else { ["jpeg"] }
  let params : Map[String, Json] = {
    "station": Json::string(p.station),
    "screen": Json::string(p.screen),
    "view": Json::string(view),
    "codecs": Json::array(codecs),
    "maxWidth": Json::number(peek_size),
    "maxHeight": Json::number(peek_size),
    "peek": true,
  }
  let id = (src.stream)("screen.view", Json::object(params), None, fn(v, b) { peek_took(src, p, view, v, b) }, fn(_) {
    // refused or ended (the station previews as many as it can now, or no longer this one): what it shows stays
    if p.view == view {
      p.call = 0
      peek_end(src, p)
    }
  })
  if p.view == view && p.run == PeekOn {
    p.call = id
  }
  p.tell()
}

///|
/// Its video's decoder stopped and its place among the app's video previews given back (its last picture goes with it:
/// a JPEG one, kept, shows until the next).
fn peek_drop_video(p : Peek) -> Unit {
  match p.stream {
    Some(st) => st.close()
    None => ()
  }
  p.stream = None
  if p.video {
    p.video = false
    video_peeks.val = if video_peeks.val > 0 { video_peeks.val - 1 } else { 0 }
  }
}

///|
/// The preview of `p` ended (refused, ended by the station, or let go for want of a decoder): its call cancelled if it
/// still runs; asked for again peek_again_ms on while its card shows (`view` kept, its wait's key).
fn peek_end(src : Source, p : Peek) -> Unit {
  if p.call != 0 {
    (src.cancel)(p.call)
  }
  p.call = 0
  p.run = PeekEnded
  p.waiting.clear()
  peek_drop_video(p)
  p.tell()
}

///|
/// The preview of `p` no longer asked for: its call cancelled.
pub fn peek_stop(src : Source, p : Peek) -> Unit {
  if p.call != 0 {
    (src.cancel)(p.call)
  }
  p.call = 0
  p.view = ""
  p.run = PeekOff
  p.again = false
  p.waiting.clear()
  peek_drop_video(p)
  p.tell()
}

///|
/// Every preview stopped (the app gone behind: no frame may come after it).
pub fn peeks_stop_all(src : Source) -> Unit {
  for _, p in peeks {
    if p.run == PeekOn {
      peek_stop(src, p)
    }
  }
}

///|
/// The previews as this frame has them, at its start (app.mbt view): the cards built in it say so as they are built;
/// each frame waiting is acknowledged peek_ms after the one before (the first at once); the previews started and
/// stopped once the frame's builds are over (peeks_settle).
pub fn peeks_frame(c : @ui.Ctx, src : Source) -> Unit {
  peeks_built.clear()
  for key, p in peeks {
    if p.made {
      continue
    }
    if p.run == PeekEnded &&
      @kit.after(c, "peek-again/\{key}/\{p.view}", true, peek_again_ms, later=true) {
      p.again = true
    }
    if p.run != PeekOn {
      continue
    }
    let n = p.acked
    let due = n == 0 || @kit.after(c, "peek-ack/\{p.view}/\{n}", true, peek_ms, later=true)
    if due && p.waiting.length() > 0 {
      // the next one's wait from this one's
      @kit.after(c, "peek-ack/\{p.view}/\{n + 1}", true, peek_ms, later=true) |> ignore
      let view = p.view
      let ts = p.waiting[0]
      c.after_build("peek-ack/" + key, fn() {
        if p.view == view && p.acked == n && p.waiting.length() > 0 {
          p.waiting.remove(0) |> ignore
          p.acked = n + 1
          (src.call)("screen.ack", { "view": Json::string(view), "ts": ts }, answer_unread)
        }
      })
    }
  }
  c.after_build("screen-peeks", fn() { peeks_settle(c, src) })
}

///|
/// Once the frame's builds are over: a preview asked for where its card is on the screen and the app shown, stopped
/// where it is not; a card no longer held let go of (as Android's list lets go of a row out of view), with its
/// pictures; the pictures under the one shown let go of (their bytes, emptied: nothing draws them again). A card is
/// held where it was built in this frame or its part or row was drawn again as it was built (mbui's kept_part.mbt,
/// kept_rows.mbt: what it draws is its last build's, its picture too); on the screen where it is held and any of its
/// target showed in the last frame (Ctx::rect_of: a frame says a target only where it shows), one with no target
/// where it is held. A card past its list's edge in a row that shows is held, its preview stopped, its picture kept
/// for the row drawn again.
pub fn peeks_settle(c : @ui.Ctx, src : Source) -> Unit {
  let shown = @ui.app_visible()
  let gone = []
  for key, p in peeks {
    if p.made {
      continue
    }
    let held = peeks_built.contains(key)
    // (a card whose target changed in this frame shows where the one it had showed in the last: its row built at
    // another place is the same card, its preview going on, nothing asked of the station again nor handed to the host
    // again)
    let shown_by = if p.was != 0 { p.was } else { p.target }
    p.was = 0
    let on = held && (p.target == 0 || c.rect_of(shown_by) is Some(_))
    let want = shown && on
    match p.run {
      PeekOn => if !want { peek_stop(src, p) }
      PeekEnded =>
        if !want {
          p.run = PeekOff
          p.again = false
        } else if p.again {
          peek_start(src, p)
        }
      PeekOff => if want { peek_start(src, p) }
    }
    let mut newest = -1
    for i, k in p.pictures {
      if @ui.image_natural(k) is Some(_) {
        newest = i
      }
    }
    if !held {
      newest = p.pictures.length()
      if p.run == PeekOff {
        gone.push(key)
      }
    }
    for i in 0..<newest {
      @ui.add_image(p.pictures[i], b"")
    }
    if newest > 0 {
      let rest = p.pictures[newest:].to_owned()
      p.pictures.clear()
      p.pictures.append(rest)
    }
  }
  for key in gone {
    peeks.remove(key)
  }
}
