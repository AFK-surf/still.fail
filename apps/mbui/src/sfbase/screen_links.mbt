// Links to a station's screens and to its 共享调试 in an agent's words (ember apps/android chat/screens/ScreenLinks.kt,
// AdbLinks.kt; docs/remote-screens.md, docs/adb-share.md), as the web draws them: one alone in a paragraph is its card
// (@sf.markdown's `screens`), a bare one within a sentence reads as its title. What a card says is the core's (the
// `screenCard` and `adbCard` topics). A screen its station previews is live in its card while the card is built (the
// messages' list builds only the rows in view) and the app is shown: `screen.view` with `peek`, JPEG only, small, each
// frame acknowledged peek_ms after the one before (the station sends the next once the last is acknowledged); stopped
// (the call cancelled) as the card goes from view or the app behind. A card's tap opens its link, as a tap on the link
// does (open_links.mbt open_link).

///|
/// A preview's pace (ScreenLinks.kt PEEK_MS): a picture at most this often.
pub let peek_ms : Double = 500.0

///|
/// The picture a preview asks for, in pixels at most (ScreenLinks.kt PEEK_SIZE): the card's width, twice over.
pub let peek_size : Double = 640.0

///|
/// A preview's shape when its station has not said the screen's size (16:10), and the shapes it is kept within.
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


// ── the cards' looks (ScreenLinks.kt ScreenLinkCard, AdbLinks.kt AdbLinkCard) ──

///|
/// A card: a row 236 wide, a capsule as a file's card (a row high, 52), on the chat's bubble ground: its mark, 24,
/// concentric with its round end (14 from its end, its top and its foot), 8 from its words, their end 14 from the
/// other end.
// kept across runs: a value (no field of it changes)
pub let link_card : @ui.Style = @ui.style(
  row=true,
  w=@sf.link_card_w,
  h=@sf.file_capsule_h,
  px=S3_5,
  gap=S2,
  align=ACenter,
  radius=Full,
  bg=Neutral,
)

///|
/// A screen's card with its preview: a column 280 wide, rounded as what a message carries is (@sf.message_file_radius),
/// the preview 4 in from its top and sides.
// kept across runs: a value (no field of it changes)
pub let peek_card : @ui.Style = @ui.style(
  w=@sf.peek_card_w,
  pt=S1,
  px=S1,
  radius=@sf.message_file_radius,
  bg=Neutral,
)

///|
/// The words under a preview: a card's words' 20 in from its sides (the card's 4 and 16 of their own), 12 under the
/// preview, 16 over the card's foot.
// kept across runs: a value (no field of it changes)
pub let peek_card_words : @ui.Style = @ui.css("w=Full px=S4 pt=S3 pb=S4")

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
/// The card of the screen `href` names, once the core has said (ScreenLinks.kt screenCardOf).
pub fn screen_card_of(src : Source, href : String) -> ScreenCard? {
  guard @sf.screen_of_link(href) is Some((station, screen)) else { return None }
  let v = (src.topic)("screenCard", { "station": Json::string(station), "screen": Json::string(screen) }).value
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
/// The card of the 共享调试 `href` names, once the core has said (AdbLinks.kt adbCardOf: the `adbCard` topic).
pub fn adb_card_of(src : Source, href : String) -> Json? {
  guard @sf.adb_of_link(href) is Some(station) else { return None }
  match (src.topic)("adbCard", { "station": Json::string(station) }).value {
    Some(Object(_)) as v => v
    _ => None
  }
}

///|
/// The links to screens in an agent's words as a chat draws them (ScreenLinks.kt ScreenLinks): their cards, and a bare
/// one's title (屏幕 until it is known); a station's 共享调试 as its own (AdbLinks.kt). `message` names the message
/// (a screen's preview is its card's own).
pub fn screen_links(c : @ui.Ctx, src : Source, message : String) -> @sf.Screens {
  {
    card: fn(href, words) {
      if @sf.adb_of_link(href) is Some(_) {
        adb_link_card(c, src, href, words)
      } else if @sf.service_of_link(href) is Some(_) {
        service_link_card(c, src, href, words)
      } else {
        screen_link_card(c, src, message + "\n" + href, href, words)
      }
    },
    title: fn(href) {
      if @sf.adb_of_link(href) is Some(_) {
        adb_title(src, href)
      } else if @sf.service_of_link(href) is Some(_) {
        service_card_of(src, href).0
      } else {
        match screen_card_of(src, href) {
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
pub fn service_card_of(src : Source, href : String) -> (String, String, Bool) {
  guard @sf.service_of_link(href) is Some((station, job)) else { return ("", "", false) }
  let j = (src.topic)("job", { "station": Json::string(station), "id": Json::string(job) }).value
  let name = match text(j, "name") {
    "" => @sf.t("android-chat.preview.service")
    n => n
  }
  guard j is Some(Object(_)) else { return (name, "", false) }
  let ws = match station.find("/") {
    Some(i) => station.view(end_offset=i).to_owned()
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
pub fn service_link_card(c : @ui.Ctx, src : Source, href : String, words : String?) -> Unit {
  let (name, line, down) = service_card_of(src, href)
  let open = c.id("service-link/" + href)
  if c.clicked(open) {
    open_link(href)
  }
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
/// A bare link to a station's 共享调试: what it reads as within a sentence (AdbLinks.kt adbTitle).
pub fn adb_title(src : Source, href : String) -> String {
  match adb_card_of(src, href) {
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
/// A screen as a card (ScreenLinks.kt ScreenLinkCard): its kind's mark, its title (the link's own words, when it has
/// them) over what its station says of it; one its station no longer has, its title quieter. Its size is kept while
/// the core has not said, its lines empty. One its station previews (a tab of its browser) is the screen live across
/// the card's top, the words under it. A tap opens it, as the link does. `key`: the card's own (its message's and its
/// link's), its preview's.
pub fn screen_link_card(c : @ui.Ctx, src : Source, key : String, href : String, words : String?) -> Unit {
  let card = screen_card_of(src, href)
  let open = c.id("screen-link/" + href)
  if c.clicked(open) {
    open_link(href)
  }
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
  match (card, @sf.screen_of_link(href)) {
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

///|
/// A station's 共享调试 asked for (an agent's link to it alone in a paragraph: docs/adb-share.md), as a card that asks
/// (vault_ask.mbt's look: the question for its title, the line the answer turns on, a solid button and a text one):
/// whether its agents may debug this device. Where the phone has all it takes (as its host says:
/// @settings.adb_ready), 共享 lends it from here; where it lacks something first, what, and 查看步骤 opens the page that
/// says how; while it is lent there, how that stands (the core's line) with 详情 and 停止共享. A device with no adb to
/// lend (the core's `lendable`; an Android before 11, as its host says) says so, with nothing to press. `words`, the
/// link's own, are not its title: the card asks its own question.
pub fn adb_link_card(c : @ui.Ctx, src : Source, href : String, words : String?) -> Unit {
  ignore(words)
  let card = adb_card_of(src, href)
  let station = @sf.adb_of_link(href).unwrap_or("")
  let sharing = flag(card, "sharing")
  let ready = if card is Some(_) && flag(card, "lendable") {
    @settings.adb_ready(c)
  } else if card is Some(_) {
    @settings.AdbCannot(text(card, "line"))
  } else {
    @settings.AdbUnknown
  }
  let ws = match station.find("/") {
    Some(i) => station.view(end_offset=i).to_owned()
    None => station
  }
  let name = match dv_stations(src, ws).0 {
    Some(list) =>
      match list.iter().find_first(fn(s) { s.station == station }) {
        Some(s) => s.name
        None => @settings.station_name(station)
      }
    None => @settings.station_name(station)
  }
  let key = "adb-ask/" + href
  let stopping = "adb-stop/" + station
  c.box(style=@sf.ask_card_room, fn() {
    @sf.card(c, fn() {
      if sharing {
        @sf.ask_words(c, @sf.t("android-misc.adb.ask.sharing", args=[("name", name)]), text(card, "line"))
        @sf.ask_buttons(c, fn() {
          if @sf.button(c, @sf.t("android-misc.adb.ask.more"), key=key + "/more", tone=Primary) {
            open_adb(src, station)
          }
          if @sf.button(c, @sf.t("android-misc.adb.ask.stop"), key=key + "/stop", tone=Ghost, busy=acting.doing.contains(stopping)) {
            act(src, @sf.t("android-misc.adb.stopWhat"), stopping, "adb.stop", Json::object({}))
          }
        })
        return
      }
      let title = @sf.t("android-misc.adb.ask.title", args=[("name", name)])
      match ready {
        @settings.AdbCannot(why) => @sf.ask_words(c, title, why)
        @settings.AdbLacks(step) => {
          @sf.ask_words(c, title, @sf.t("android-misc.adb.ask.first", args=[("step", step)]))
          @sf.ask_buttons(c, fn() {
            if @sf.button(c, @sf.t("android-misc.adb.ask.how"), key=key + "/how", tone=Primary) {
              open_adb(src, station)
            }
          })
        }
        @settings.AdbLends => {
          // lent to another station now: lending it here moves it
          let now = (src.topic)("adbShare", {}).value
          let elsewhere = flag(now, "sharing") && text(now, "station") != station
          @sf.ask_words(c, title, @sf.t(if elsewhere { "android-misc.adb.elsewhere" } else { "android-misc.adb.hour" }))
          @sf.ask_buttons(c, fn() {
            if @sf.button(c, @sf.t("android-misc.adb.ask.share"), key=key + "/share", tone=Primary, busy=@settings.adb_asking()) {
              @settings.adb_lend(station, name)
            }
            if @sf.button(c, @sf.t("android-misc.adb.ask.more"), key=key + "/more", tone=Ghost) {
              open_adb(src, station)
            }
          })
        }
        // (not known yet what the phone has: the question alone, its answer as it comes)
        @settings.AdbUnknown => @sf.ask_words(c, title, "")
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The 共享调试 of the station (`<workspace>/<station>`) a link's card names, opened as its link opens it (open_target),
/// whatever host the link was written with: the card is drawn for any (adb_of_link), and its 详情 opens what it shows
/// (2026-10-30: a link under another host than the cloud's was drawn as the card, and 详情 handed it to the browser).
fn open_adb(src : Source, station : String) -> Unit {
  guard station.find("/") is Some(i) else { return }
  let target = link_target({
    "opens": "adbShare",
    "workspace": Json::string(station.view(end_offset=i).to_owned()),
    "station": Json::string(station.view(start_offset=i + 1).to_owned()),
  })
  open_target(src, target, false, None) |> ignore
}

// ── a screen live in its card ──

///|
/// How a card's preview stands: not asked for, coming (its call), or ended by the station (refused, or the screen no
/// longer previewed: its picture, or its mark, stays until the card goes from view).
pub(all) enum PeekRun {
  PeekOff
  PeekOn
  PeekEnded
} derive(Eq)

///|
/// A card's preview (ScreenLinks.kt Peek).
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
  /// its card's target (0: none): where it shows, the card is on the screen (peeks_settle)
  mut target : Int
}

///|
/// The cards' previews, by card.
pub let peeks : Map[String, Peek] = {}

///|
/// The cards with a preview built in this pass of the frame, or held by a list's row kept as its nodes (@ui.built_used).
pub let peeks_built : Map[String, Bool] = {}

///|
/// Previews asked for so far: each view's name its own.
pub let peek_views : Ref[Int] = Ref(0)

///|
pub fn peeks_reset() -> Unit {
  peeks.clear()
  peeks_built.clear()
  peek_views.val = 0
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
      }
      peeks[key] = p
      p
    }
  }
}

///|
/// The screen live in its card (ScreenLinks.kt Peek): only looking (not among those on it, its tab not brought
/// forward), its mark until a picture comes (a tab behind another casts none); in its shape as its station lists it,
/// within bounds, so the card does not change size as it comes. The newest picture decoded is shown, cropped to the
/// preview from its top; a newer one is drawn over it once it is decoded. `target`: its card's (peeks_settle).
pub fn screen_peek(
  c : @ui.Ctx,
  key : String,
  station : String,
  screen : String,
  card : ScreenCard,
  target? : Int = 0,
) -> Unit {
  let p = peek_for(key, station, screen)
  p.target = target
  peeks_built[key] = true
  // (and each frame its row or part is put back as built, kept as its nodes: mbui's kept_nodes.mbt)
  @ui.built_used(fn() { peeks_built[key] = true })
  let listed = if card.width > 0.0 && card.height > 0.0 { card.width / card.height } else { 0.0 }
  let ratio = if listed > 0.0 {
    dclamp(listed, peek_ratio_least, peek_ratio_most)
  } else {
    peek_ratio
  }
  c.box(style=peek_frame, aspect=ratio, fn() {
    let mut shown = -1
    for i, k in p.pictures {
      if @ui.image_natural(k) is Some(_) {
        shown = i
      }
    }
    if shown < 0 {
      link_mark(c, Some(if card.kind == "browser" { globe_mark } else { monitor_mark }), Muted)
    }
    // the shown one's shape (else the screen's as listed) for those over it: a screen's frames keep its size
    let shape = if shown < 0 {
      listed
    } else {
      match @ui.image_natural(p.pictures[shown]) {
        Some((w, h)) if h > 0.0 => w / h
        _ => listed
      }
    }
    let from = if shown < 0 { 0 } else { shown }
    for i in from..<p.pictures.length() {
      let k = p.pictures[i]
      c.layer(fn() { peek_picture(c, k, shape, ratio) }) |> ignore
    }
  })
  |> ignore
}

///|
/// A picture over the preview as Android's Crop at TopCenter: as wide as the preview from its top when it is
/// taller than the preview, else as high, its middle across.
pub fn peek_picture(c : @ui.Ctx, key : String, shape : Double, ratio : Double) -> Unit {
  if shape > 0.0 && shape < ratio {
    c.image(key, w=Fill(1.0), h=Px(@sf.peek_frame_px / shape), fit=FitFill, bg=0L, fade=false)
    |> ignore
  } else {
    c.image(key, w=Fill(1.0), h=Fill(1.0), fit=FitCover, bg=0L, fade=false) |> ignore
  }
}

///|
/// A frame of a preview as it comes: its picture (a JPEG) handed over under a key of its own, its `ts` to acknowledge.
pub fn peek_took(p : Peek, view : String, value : Json, bytes : Bytes?) -> Unit {
  if p.view != view {
    return
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
/// The preview of `p` asked for (`screen.view` with `peek`: JPEG only, small).
pub fn peek_start(src : Source, p : Peek) -> Unit {
  peek_views.val += 1
  let view = "mbui-peek-\{peek_views.val}"
  p.view = view
  p.run = PeekOn
  p.call = 0
  p.acked = 0
  p.waiting.clear()
  let params : Map[String, Json] = {
    "station": Json::string(p.station),
    "screen": Json::string(p.screen),
    "view": Json::string(view),
    "codecs": ["jpeg"],
    "maxWidth": Json::number(peek_size),
    "maxHeight": Json::number(peek_size),
    "peek": true,
  }
  let id = (src.stream)("screen.view", Json::object(params), None, fn(v, b) { peek_took(p, view, v, b) }, fn(_) {
    // refused or ended (the station no longer previews it): what it shows stays
    if p.view == view {
      p.run = PeekEnded
      p.call = 0
      p.waiting.clear()
    }
  })
  if p.view == view && p.run == PeekOn {
    p.call = id
  }
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
  p.waiting.clear()
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
          (src.call)("screen.ack", { "view": Json::string(view), "ts": ts }, fn(_) {  })
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
    let held = peeks_built.contains(key)
    let on = held && (p.target == 0 || c.rect_of(p.target) is Some(_))
    let want = shown && on
    match p.run {
      PeekOn => if !want { peek_stop(src, p) }
      PeekEnded => if !want { p.run = PeekOff }
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
      let rest = p.pictures[newest:].to_array()
      p.pictures.clear()
      p.pictures.append(rest)
    }
  }
  for key in gone {
    peeks.remove(key)
  }
}
