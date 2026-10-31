// Visualizations (ember apps/android shared/ui/Viz.kt, chat/screens/VizFiles.kt, Prose.kt; web/src/Viz.tsx): an HTML
// file an agent placed in its message's text (`[title](figure.html)` on a line of its own), drawn there in a page's
// view (src/ui/native.mbt NativeView::page) instead of shown as a card, with ways under it to open it over the whole
// screen or as a page of its own (PreviewFile, service.mbt); a ```mermaid block drawn the same way, by mermaid (from
// the CDN the web loads it from), shown as code while it will not draw.
//
// The page is the web's: its stylesheet and bridge (web/src/viz, web_assets.mbt), the web's tokens for the theme shown
// (as --e-*), the same CSP (scripts and styles from a few public CDNs, no requests of its own). It is as tall as its
// content (the bridge says), keeps what the widget asks to keep (widget.setState, on the station, given back by
// widget.state as it loads), and puts what it asks to send (sendFollowUpMessage, on a tap) in the chat's composer for
// the person to send. What the bridge posts to its own window is relayed to the app (`mbuiHost.post`): none of it is
// trusted, a field that is not what it should be is let go.

// ── the page itself ────────────────────────────────────────────────────

///|
/// A page drawn (Viz.kt VizFrame): its view, the height it said, whether it is shown yet (once it has drawn itself:
/// what is under it shows meanwhile), the theme it was told.
pub(all) struct VizFrame {
  view : @ui.NativeView
  /// The scoped place currently drawing this view; none once its page has left.
  mut owner : Int?
  html : String
  page : Bool
  mut height : Int
  /// the height it last said, and how many times running it grew a little to it (viz_runaway)
  mut said_height : Int
  mut grown : Int
  mut shown : Bool
  mut dark : Bool
  mut font_scale : Double
  mut ground : Int64
  /// the faces it was told (viz_faces_key)
  mut faces : String
  /// its way in once it has drawn itself (viz_reveal); None once it is in
  mut reveal : @motion.Anim?
}

///|
/// The pages drawn, by where they are drawn (their message's place and file, a chart's code, the full screen's).
pub let viz_frames : Map[String, VizFrame] = Map([])

///|
/// Additional views for a place shown in more than one page at once. The first is kept in viz_frames; each free view
/// is reused after its page leaves, so returning to a chat keeps its already drawn contents.
let viz_extra_frames : Map[String, Array[VizFrame]] = Map([])

///|
fn viz_frame_for(key : String, owner : Int) -> VizFrame? {
  let first = viz_frames.get(key)
  match first {
    Some(f) if f.owner == Some(owner) => return Some(f)
    _ => ()
  }
  let extras = viz_extra_frames.get(key)
  match extras {
    Some(frames) => for f in frames { if f.owner == Some(owner) { return Some(f) } }
    None => ()
  }
  match first {
    Some(f) if f.owner is None => return Some(f)
    _ => ()
  }
  match extras {
    Some(frames) => for f in frames { if f.owner is None { return Some(f) } }
    None => ()
  }
  None
}

///|
/// Heights pages were last drawn at (by their content), so one drawn again takes its room at once.
pub let viz_heights : Map[String, Int] = Map([])

///|
/// What a page says to the app (the bridge's messages, relayed): who hears what it keeps, a failure, words to send.
pub(all) struct VizHears {
  keep : ((Json) -> Unit)?
  failed : ((String) -> Unit)?
  /// words for the chat's composer: whether it took them
  follow_up : ((String) -> Bool)?
}

///|
/// What a page's view says, read (it says what it likes: a field that is not what it should be is let go).
pub fn viz_said(f : VizFrame, hears : VizHears, words : String) -> Unit {
  let m = match (try Some(@json.parse(words)) catch { _ => None }) {
    Some(Object(m)) => m
    _ => return
  }
  match m.get("type") {
    Some(String("height")) =>
      if !f.page {
        match m.get("height") {
          Some(Number(h, ..)) if h == h && h < 1.0e9 && h > 0.0 => {
            let tall = h.ceil().to_int()
            // held, it stays so until its content is shorter than where it was held
            if f.grown > viz_runaway && tall >= f.said_height {
              return
            }
            f.grown = if f.said_height > 0 && tall > f.said_height && tall - f.said_height <= 64 {
              f.grown + 1
            } else {
              0
            }
            if f.grown > viz_runaway {
              return
            }
            f.said_height = tall
            // only a height it did not creep to is kept: one kept mid-run would start the next load's run further on
            if f.grown == 0 {
              viz_heights[f.html] = tall
            }
            f.height = tall
            f.shown = true
          }
          _ => ()
        }
      }
    Some(String("state")) => {
      let s = m.get("state").unwrap_or(Json::null())
      if s.stringify().length() <= viz_max_state {
        match hears.keep {
          Some(k) => k(s)
          None => ()
        }
      }
    }
    Some(String("failed")) =>
      match (m.get("message"), hears.failed) {
        (Some(String(why)), Some(f)) => f(why)
        _ => ()
      }
    Some(String("followup")) =>
      match m.get("prompt") {
        Some(String(p)) => {
          let words = p.trim().to_owned()
          if words != "" {
            let cut = if words.length() > 4000 { words.view(end_offset=4000).to_owned() } else { words }
            let took = match hears.follow_up {
              Some(f) => f(cut)
              None => false
            }
            toast_later(viz_tr(if took { "android-misc.viz.followupDrafted" } else { "android-misc.viz.cantSend" }))
          }
        }
        _ => ()
      }
    _ => ()
  }
}

///|
/// The page of `html` (what its widget kept: `state`) drawn as `key`: as tall as its content (`fill`: the room it is
/// given), shown once it has drawn itself. Made once per place: a new page would lose what it holds; the theme is told
/// to it as it changes.
pub fn viz_frame(
  c : @ui.Ctx,
  key : String,
  html : String,
  state : Json?,
  hears : VizHears,
  fill? : Bool = false,
  ground? : Int64 = @sf.theme().p.bg,
) -> Unit {
  let dark = @sf.theme().dark
  if !viz_left_chats.is_empty() {
    viz_shown_again(key)
  }
  let owner = c.id("viz/owner/" + key)
  let f = match viz_frame_for(key, owner) {
    Some(f) => f
    None => {
      let page = !viz_is_fragment(html)
      let doc = if page { viz_page_document(html) } else { viz_document(html, state, dark, ground, scroll=fill) }
      let cell : Ref[VizFrame?] = Ref(None)
      let view = @ui.NativeView::page(doc, said=fn(w) {
        match cell.val {
          Some(f) => viz_said(f, hears, w)
          None => ()
        }
      })
      // in a list, an upright drag on the page moves the list (Viz.kt passVerticalDrags); a page of its own keeps them
      if !fill {
        view.touch(@ui.Touch::VerticalOut)
      }
      let f : VizFrame = {
        view,
        owner: None,
        html,
        page,
        height: viz_heights.get(html).unwrap_or(0),
        said_height: 0,
        grown: 0,
        shown: false,
        dark,
        font_scale: @ui.font_scale(),
        ground,
        faces: viz_faces_key(),
        reveal: Some(@motion.Anim::new(0.0)),
      }
      cell.val = Some(f)
      if viz_frames.contains(key) {
        match viz_extra_frames.get(key) {
          Some(extras) => extras.push(f)
          None => viz_extra_frames[key] = [f]
        }
      } else {
        viz_frames[key] = f
      }
      f
    }
  }
  if f.owner != Some(owner) {
    f.owner = Some(owner)
    c.on_page_release("viz/owner/" + key, fn() {
      if f.owner == Some(owner) {
        f.owner = None
      }
    })
  }
  // the theme told only when it changes (a page told it as it loads draws again: a chart redrawn)
  if f.dark != dark || f.ground != ground || f.font_scale != @ui.font_scale() || f.faces != viz_faces_key() {
    f.dark = dark
    f.font_scale = @ui.font_scale()
    f.ground = ground
    f.faces = viz_faces_key()
    let scheme = if dark { "dark" } else { "light" }
    let g = viz_css_color(ground)
    c.tell("viz/theme/" + key + "/" + owner.to_string(), fn() {
      f.view.script(
        "postMessage({emberViz:true,type:\"theme\",tokens:" +
        viz_tokens_json(dark) +
        ",scheme:\"" +
        scheme +
        "\",sheets:" +
        Json::array(viz_sheets().map(fn(h) { Json::string(h) })).stringify().replace_all(old="<", new="\\u003c") +
        "},\"*\");var g=document.getElementById(\"mbui-ground\");if(g)g.textContent=\":root:root{background:" +
        g +
        "}\"",
      )
    })
  }
  // a whole page (or a fragment that never says its height) is shown once it has loaded
  if f.view.state() == 1 && (f.page || f.height == 0) {
    f.shown = true
  }
  // what is under it shows till it has drawn itself: the ground (a page's paper), drawn over it; and till its host has
  // drawn it (host_done: its first frame on the screen), as a page that has loaded, or said its height, is not drawn
  // yet: the empty view showed through for a frame or more
  let cover = fn(style : @ui.Style) {
    if !f.shown || !f.view.host_done() {
      c.layer(fn() { c.box(style~, fn() {  }) |> ignore }) |> ignore
    }
  }
  if fill {
    c.box(style=viz_fill, fn() {
      c.native(f.view) |> ignore
      cover(viz_ground)
    })
    |> ignore
  } else if f.page {
    // a whole page sizes itself to its window: in a message a screen-shaped one (16:9 of the message's width, at most
    // 80% of the screen's height), its corners the card's, on the paper
    let box = c.id("viz/box/" + key)
    let w = match c.laid_size(box) {
      Some((w, _)) => w
      None => c.width
    }
    let h = dmin((w * viz_page_ratio).floor(), (c.height * viz_page_most).floor())
    c.box(style=viz_page_frame.then(@ui.style(h=Fixed(h))), id=box, taps=false, fn() {
      c.native(f.view) |> ignore
      cover(viz_paper_cover)
      viz_reveal(c, f, w, h, fn(w, h) {
        c.box(style=viz_paper_cover.then(@ui.style(w=Fixed(w), h=Fixed(h))), fn() {  })
      })
    })
    |> ignore
  } else {
    let said = (if f.height > 0 { f.height } else { viz_first_height }).to_double()
    // as tall as it said, from the height it had as it says another: a move for its cause, so what is over and under
    // it in a list goes there with it, not in one frame (rows_steady.mbt); on the list's way where it has one (a row's
    // own content, as under_post's)
    let tall = @motion.anim(c, "viz-h/" + key + "/" + owner.to_string(), said, global=true)
    if tall.target() != said {
      match c.row_way() {
        Some(way) => on_row_way(c, tall, said, way)
        None => tall.animate(said, @motion.move(over=(said - tall.get()).abs()))
      }
    }
    let h = tall.get()
    // till it has drawn itself, its place as while its file came (the line's grey, breathing, its corners the
    // placeholder's, the view's hole cut to them): not an empty gap (the user, 2026-10-29)
    let waiting = !f.shown || !f.view.host_done()
    let frame = @ui.style(w=Full, h=Fixed(h))
    let box = c.id("viz/box/" + key)
    let w = match c.laid_size(box) {
      Some((w, _)) => w
      None => c.width
    }
    c.box(style=frame, id=box, fn() {
      // (its corners the placeholder's till what it waited on has gone from over it)
      let rounded = waiting || f.reveal is Some(_)
      c.native(f.view, radius=if rounded { c.theme().corner(Xl) } else { 0.0 }) |> ignore
      viz_reveal(c, f, w, h, fn(w, h) {
        c.box(style=viz_wait_ground.then(@ui.style(w=Fixed(w), h=Fixed(h))), fn() {
          c.box(style=viz_wait_fill, fn() {  }) |> ignore
        })
      })
      if waiting {
        c.layer(fn() {
          c.box(style=viz_wait_ground, fn() {
            let i = c.box(style=viz_wait_fill, fn() {  })
            @sf.breathe(c, i)
          })
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  }
}

///|
/// A page come in once it has drawn itself, as a message's image once decoded (sfpages image_reveal, the web's
/// msgImageReveal; the user, 2026-10-29: inline html 的渲染显示要参考图片的展示逻辑): what it waited under (`waited`,
/// `w` by `h`) brushed off from its top, an edge half its height deep going down it over 1100 ms (the ease out), and
/// fading out from 800 ms (300 ms). A view drawn by its host is neither blurred nor scaled, as the image is: the
/// edge alone brings it in. One drawn already as it is first shown again (its chat kept) comes as it is.
fn viz_reveal(c : @ui.Ctx, f : VizFrame, w : Double, h : Double, waited : (Double, Double) -> Int) -> Unit {
  let a = match f.reveal {
    Some(a) => a
    None => return
  }
  if !f.shown || !f.view.host_done() {
    return
  }
  if a.target() == 0.0 {
    a.animate(1.0, @motion.tween(viz_reveal_ms, ease=Linear))
  }
  let p = a.get()
  if p >= 1.0 {
    f.reveal = None
    return
  }
  let e = @ui.Out.at(p)
  let gone = 1.0 - dmin(1.0, dmax(0.0, (p * viz_reveal_ms - viz_reveal_wait_after_ms) / viz_reveal_wait_out_ms))
  if gone <= 0.0 {
    return
  }
  // (each step on the screen's pixels: one meets the next with no seam)
  let px_of = fn(y : Double) { (y * c.scale).round() / c.scale }
  let strip = fn(y0 : Double, y1 : Double, alpha : Double) {
    let y0 = px_of(dmax(0.0, y0))
    let y1 = px_of(dmin(h, y1))
    if y1 <= y0 || alpha <= 0.0 {
      return
    }
    // (each laid out from the page's top, as a layer is: not under the one before)
    c.layer(fn() {
      if y0 > 0.0 {
        c.box(style=@ui.style(w=Full, h=Fixed(y0)), fn() {  }) |> ignore
      }
      let s = c.box(style=@ui.style(w=Full, h=Fixed(y1 - y0), clip=true), fn() {
        c.look(waited(w, h), @ui.look(dy=-y0))
      })
      c.look(s, @ui.look(alpha=alpha * gone))
    })
    |> ignore
  }
  let band = h * 0.5
  let top = -band + (h + band) * e
  let step = band / viz_reveal_steps.to_double()
  for k in 0..<viz_reveal_steps {
    let y = top + k.to_double() * step
    strip(y, y + step, (k.to_double() + 0.5) / viz_reveal_steps.to_double())
  }
  strip(top + band, h, 1.0)
}

///|
/// How long a page comes in, when and how fast what it waited under goes, its edge's steps (image_reveal's).
pub let viz_reveal_ms : Double = 1100.0

///|
let viz_reveal_wait_after_ms : Double = 800.0

///|
let viz_reveal_wait_out_ms : Double = 300.0

///|
let viz_reveal_steps : Int = 16

///|
/// The faces a page is set in, as one string: told again when it changes.
fn viz_faces_key() -> String {
  faces_web.map(fn(f) { f.0 + "\n" + f.1 }).join("\n")
}

///|
/// A whole page's window in a message: 16:9 of its width, at most this share of the screen's height.
pub let viz_page_ratio : Double = 9.0 / 16.0

///|
pub let viz_page_most : Double = 0.8

///|
/// All the room it is given (a page of its own).
// kept across runs: a value (no field of it changes)
pub let viz_fill : @ui.Style = @ui.css("w=Full h=Full")

///|
/// What shows under a page not drawn yet: the chat's ground.
// kept across runs: a value (no field of it changes)
pub let viz_ground : @ui.Style = @ui.css("w=Full h=Full bg=Bg")

///|
/// A whole page in a message: its corners the card's (Smooth 20), on the paper (Viz.kt: #F6F2EA, dark #26272B).
// kept across runs: a value (no field of it changes)
pub let viz_page_frame : @ui.Style = @ui.style(w=Full, radius=@sf.viz_card_radius, clip=true, bg=@sf.viz_paper, dark=@ui.patch(bg=@sf.viz_paper_dark))

///|
// kept across runs: a value (no field of it changes)
pub let viz_paper_cover : @ui.Style = @ui.style(w=Full, h=Full, bg=@sf.viz_paper, dark=@ui.patch(bg=@sf.viz_paper_dark))

///|
/// The pages drawn as `prefix…` let go (their place gone: the chat left, the full screen closed).
pub fn viz_close(prefix : String) -> Unit {
  let gone = []
  for k, f in viz_frames {
    if k.has_prefix(prefix) {
      f.view.close()
      match viz_extra_frames.get(k) {
        Some(extras) => for extra in extras { extra.view.close() }
        None => ()
      }
      gone.push(k)
    }
  }
  for k in gone {
    viz_frames.remove(k)
    viz_extra_frames.remove(k)
  }
}

///|
/// How many chats left last keep their pages (each its view, hidden while not painted): one gone back to shows them
/// as they were, not loaded and drawn again behind a placeholder (the user, 2026-10-29: 每次切换 chat 都会闪一下).
pub let viz_chats_kept : Int = 4

///|
/// The chats left whose pages are kept (their keys' prefix), the one left last at the end.
pub let viz_left_chats : Array[String] = []

///|
/// A chat left: its pages kept, as those of the few left before it; the one left longest ago lets its go.
pub fn viz_chat_left(station : String, session : String) -> Unit {
  let prefix = "chat/" + station + ":" + session + "/"
  match viz_left_chats.search(prefix) {
    Some(i) => ignore(viz_left_chats.remove(i))
    None => ()
  }
  viz_left_chats.push(prefix)
  while viz_left_chats.length() > viz_chats_kept {
    viz_close(viz_left_chats.remove(0))
  }
}

///|
/// A page drawn again: its chat is shown, no longer one left (its pages not let go for others left after it).
fn viz_shown_again(key : String) -> Unit {
  for i, p in viz_left_chats {
    if key.has_prefix(p) {
      ignore(viz_left_chats.remove(i))
      return
    }
  }
}

///|
/// One of the ways under a page (VizFiles.kt): a 22 box (corners Smooth 6), a 14 icon in the frame's subtle grey; named
/// `label`, said over it while it is pointed at (Viz.tsx's Tip).
pub fn viz_icon(c : @ui.Ctx, id : Int, icon : String, label : String, subtle : Int64) -> Unit {
  let b = c.box(style=viz_way, id~, fn() {
    @sf.icon(c, icon, size=14.0, color=subtle) |> ignore
    // VizFiles.kt: clip(Smooth(6)).clickable
    @motion.ripple(c, id, 6.0)
  })
  c.semantics(b, Button, id~, label~)
  @sf.tip(c, "viz-way/" + id.to_string(), id, label)
}

// ── in a message (VizFiles.kt VizFile) ─────────────────────────────────

///|
/// Where a visualization's words to send go: the chat's composer, whichever frame's (its draft: the words after what
/// is there, then the field focused, as Prose.kt's followUp): left for it by the chat's draft key, taken as it is next
/// drawn.
pub fn viz_follow_up(station : String, session : String) -> (String) -> Bool {
  fn(words) {
    let key = station + ":" + session
    followed_into[key] = match followed_into.get(key) {
      Some(w) => w + "\n" + words
      None => words
    }
    draft_given()
    true
  }
}

///|
/// Words a visualization asked to send, by the draft key of the chat whose composer they go into: taken by it.
// kept across runs: put back by viz_pages_reset (sfbase's reset)
pub let followed_into : Map[String, String] = {}

///|
/// The visualization a message of chat `session` on `station` places, kept by session `key`, drawn there; the ways
/// under it in `subtle` (the frame's grey).
pub fn viz_file_of(
  c : @ui.Ctx,
  src : Source,
  station : String,
  session : String,
  key : String,
  ts : String,
  a : Attachment,
  failed : () -> Unit,
  subtle : Int64,
) -> Unit {
  let t = @sf.theme()
  match viz_load(c, src, station, key, a.path, size=a.size) {
    Some(Err(_)) => failed()
    // its place, breathing as every wait's shapes, till the page comes
    None =>
      c.box(style=viz_wait_under, fn() {
        let i = c.box(style=viz_wait, fn() {  })
        @sf.breathe(c, i)
      })
      |> ignore
    Some(Ok((html, state))) => {
      let place = "chat/" + station + ":" + session + "/" + ts + "/" + a.path
      c.box(style=viz_file_box, fn() {
        viz_frame(c, place, html, state, {
          keep: Some(fn(s) { viz_keep(src, station, key, a.path, s) }),
          failed: None,
          follow_up: Some(viz_follow_up(station, session)),
        })
        // under the page, out of its way: the ways to open it on its own, icons in the chat's grey
        c.box(style=viz_ways, fn() {
          let full = c.id("viz/full/" + place)
          if c.clicked(full) {
            c.tell("viz/open-full", fn() { viz_open_full(a.name, station, key, a.path, session) })
          }
          viz_icon(c, full, "expand", viz_tr("android-misc.viz.fullscreen"), subtle)
          let aside = c.id("viz/aside/" + place)
          if c.clicked(aside) {
            open_page(PreviewFile(station, key, a.path, a.name))
          }
          viz_icon(c, aside, "panel-open", viz_tr("android-misc.viz.openAside"), subtle)
        })
        |> ignore
      })
      |> ignore
      ignore(t)
    }
  }
}

///|
/// Its place while it comes: 120 high, its corners Smooth 12, a placeholder's grey (the line's), 8 under it.
// kept across runs: a value (no field of it changes)
pub let viz_wait_under : @ui.Style = @ui.css("w=Full pb=S2")

///|
// kept across runs: a value (no field of it changes)
pub let viz_wait : @ui.Style = @ui.style(w=Full, h=@sf.viz_wait_h, radius=Xl, bg=Line)

///|
/// Its place while it draws itself: as `viz_wait`, as tall as its frame.
// kept across runs: a value (no field of it changes)
pub let viz_wait_fill : @ui.Style = @ui.css("w=Full h=Full radius=Xl bg=Line")

///|
/// The ground covering its view while it waits: its corners the placeholder's (the view's hole cut to them).
// kept across runs: a value (no field of it changes)
pub let viz_wait_ground : @ui.Style = @ui.css("w=Full h=Full radius=Xl bg=Bg")

///|
/// The page and the ways under it, 4 under them.
// kept across runs: a value (no field of it changes)
pub let viz_file_box : @ui.Style = @ui.css("w=Full pb=S1")

///|
/// The ways under the page: 2 under it, 22 high, at its end, 2 apart.
// kept across runs: a value (no field of it changes)
pub let viz_ways : @ui.Style = @ui.css("row w=Full pt=S0_5 h=S6 gap=S0_5 justify=JEnd")

///|
// kept across runs: a value (no field of it changes)
pub let viz_way : @ui.Style = @ui.style(
  w=@sf.viz_way_side,
  h=@sf.viz_way_side,
  radius=Md,
  align=ACenter,
  justify=JCenter,
)

// ── over the whole screen (Viz.kt VizFull, VizFiles.kt VizOpen) ────────

///|
/// A visualization open over the whole screen: its name, its file (to fetch, or fetched), the chat whose composer its
/// words go to.
pub(all) struct VizFull {
  name : String
  station : String
  key : String
  path : String
  session : String
  /// opened by a link within a sentence (VizOpen): its wait said under the words till it covers the screen
  linked : Bool
  /// a mermaid chart's source instead of a file (Viz.kt Mermaid): nothing to fetch, nothing kept, no words to send
  mermaid : String?
}

///|
/// The visualization open over the whole window, if one is: a signal, what draws it built again as one is opened or
/// closed, wherever that was.
// kept across runs: put back as a run begins (viz_pages_reset)
pub let viz_full : @signals.Signal[VizFull?] = @signals.signal(None)

///|
pub fn viz_open_full(name : String, station : String, key : String, path : String, session : String, linked? : Bool = false) -> Unit {
  viz_close("full/")
  viz_full.set(Some({ name, station, key, path, session, linked, mermaid: None }))
}

///|
/// A mermaid chart over the whole screen (Viz.kt Mermaid: VizFull("Mermaid", …)).
pub fn viz_open_mermaid(code : String) -> Unit {
  viz_close("full/")
  viz_full.set(
    Some({
      name: "Mermaid",
      station: "",
      key: "",
      path: "",
      session: "",
      linked: false,
      mermaid: Some(code),
    }),
  )
}

///|
pub fn viz_close_full() -> Unit {
  viz_close("full/")
  viz_full.set(None)
}

///|
/// The visualization over the whole window, if one is open, whatever the layout: call after what is under it. On the
/// page's ground, under the bar every file opened over the whole window has (@sf.viewer_frame_bar: across the top,
/// clear of the window's own buttons, its way back by name; laid out Small, floating with its ×), the page under it as
/// tall as the rest; back (Esc) closes it. One that cannot be read is said so and closes.
pub fn viz_full_layer(c : @ui.Ctx, src : Source) -> Unit {
  let v = match viz_full.get() {
    Some(v) => v
    None => return
  }
  let loaded = match v.mermaid {
    Some(code) => Some(Ok((viz_mermaid_document(code, full=true), None)))
    None => viz_load(c, src, v.station, v.key, v.path)
  }
  match loaded {
    // fetched once; a link's wait is said under its words
    None => ()
    Some(Err(_)) => {
      c.tell("viz/full-failed", fn() { viz_close_full() })
      toast_later(viz_tr("android-misc.viz.cantRead"))
    }
    Some(Ok((html, state))) => {
      let chart = v.mermaid is Some(_)
      let native = @sf.native_over_up(v.name)
      if native {
        @sf.native_over_act("close", @sf.t("common.close"), "close", fn() { c.tell("viz/full-close", fn() { viz_close_full() }) }, lead=true)
        if !chart {
          @sf.native_over_act("download", @sf.t("android-chat.file.download"), "download", fn() {
            keep_bytes(c, v.name, "text/html", @utf8.encode(html))
          })
        }
      }
      let t = @sf.theme()
      let (top, foot) = (@sf.viewer_host().room)()
      c.take_back(fn() { viz_close_full() })
      // under the bar, as a file's page is (Viewer::text_stage)
      let under = if native { top } else if c.width <= @sf.viewer_small_w { top + page_small_top } else { viewer_top(c) + desk_page_top }
      c.layer(fn() {
        c.box(style=viz_ground, fn() {
          c.box(style=@ui.style(w=Full, h=Fixed(under)), fn() {  }) |> ignore
          c.box(style=viz_full_page.then(@ui.style(pr=@sf.room_of(c.space(S3) + @sf.native_clear()))), fn() {
            viz_frame(
              c,
              if chart { "full/mermaid/" + html } else { "full/" + v.station + "/" + v.key + "/" + v.path },
              html,
              state,
              {
                keep: if chart { None } else { Some(fn(s) { viz_keep(src, v.station, v.key, v.path, s) }) },
                failed: None,
                follow_up: if chart { None } else { Some(viz_follow_up(v.station, v.session)) },
              },
              fill=true,
              ground=t.p.bg,
            )
          })
          |> ignore
          c.box(style=@ui.style(w=Full, h=Fixed(foot)), fn() {  }) |> ignore
        })
        |> ignore
        if !native {
          let (closed, _) = @sf.viewer_frame_bar(
            c,
            "viz/full",
            @sf.t("common.back"),
            v.name,
            "",
            false,
            true,
            0.0,
            1.0,
            @sf.page_viewer_ink(),
            fn() {  },
          )
          if closed {
            c.tell("viz/full-close", fn() { viz_close_full() })
          }
        }
      })
      |> ignore
    }
  }
}

///|
/// The page under it, 12 in at its sides, as tall as the rest.
// kept across runs: a value (no field of it changes)
pub let viz_full_page : @ui.Style = @ui.style(w=Full, h=@sf.grow, px=S3)

///|
pub let viz_mermaid : String = "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs"

///|
/// A mermaid chart's page (Viz.kt mermaidDocument): the source, drawn by mermaid in the web's colours, drawn again when
/// the theme changes, once the page has a width. In a message fitted to its width but never smaller than 0.8 (wider
/// than that it scrolls sideways); `full`: over the whole screen, fitted to it, pinched and moved by the page itself.
pub fn viz_mermaid_document(code : String, full? : Bool = false) -> String {
  "<pre class=\"mermaid-src\" hidden>" +
  code.replace_all(old="&", new="&amp;").replace_all(old="<", new="&lt;") +
  "</pre><div id=\"chart\"></div>\n<style>" +
  (if full { "html{overflow:hidden}#chart{position:relative;height:calc(100vh - 4px);overflow:hidden;touch-action:none}" } else { "#chart{overflow-x:auto}" }) +
  "</style>\n" +
  "<script type=\"module\">\n" +
  "  const post = (m) => parent.postMessage({ emberViz: true, ...m }, \"*\");\n" +
  "  const source = document.querySelector(\".mermaid-src\").textContent;\n" +
  "  const FULL = " +
  (if full { "true" } else { "false" }) +
  ", READABLE = 0.8;\n" +
  "  let mermaid;\n" +
  "  try { mermaid = (await import(\"" +
  viz_mermaid +
  "\")).default; } catch (e) { post({ type: \"failed\", message: \"" +
  viz_tr("android-misc.viz.mermaidFailed") +
  "\" }); }\n" +
  "  const pixel = document.createElement(\"canvas\").getContext(\"2d\", { willReadFrequently: true });\n" +
  "  // (laid over the page's ground: a colour at an opacity, as --muted is, the colour it comes to there)\n" +
  "  const rgb = (color, under) => { pixel.clearRect(0, 0, 1, 1); for (const c of [under, color]) { if (!c) continue; pixel.fillStyle = \"#000\"; pixel.fillStyle = c; pixel.fillRect(0, 0, 1, 1); } const [r, g, b] = pixel.getImageData(0, 0, 1, 1).data; return \"rgb(\" + r + \", \" + g + \", \" + b + \")\"; };\n" +
  "  const v = (name) => { const root = getComputedStyle(document.documentElement), value = root.getPropertyValue(name).trim(); return name === \"--font-sans\" ? value : rgb(value, name === \"--background\" ? null : root.getPropertyValue(\"--background\").trim()); };\n" +
  "  const chart = document.getElementById(\"chart\");\n" +
  "  let n = 0, waiting = false, width = 0;\n" +
  "  const fit = (w) => Math.min(1, chart.clientWidth / w);\n" +
  "  async function render(s) {\n" +
  "    const { svg } = await mermaid.render(\"chart-\" + ++n, s);\n" +
  "    const box = document.createElement(\"div\");\n" +
  "    box.innerHTML = svg;\n" +
  "    return box.querySelector(\"svg\");\n" +
  "  }\n" +
  "  // Over the whole screen: the chart fitted to the screen (`base`), zoomed `k` times that (1 to `most`), its corner at x, y.\n" +
  "  let base = 1, most = 4, k = 1, x = 0, y = 0;\n" +
  "  function show() {\n" +
  "    const svg = chart.querySelector(\"svg\");\n" +
  "    if (!svg) return;\n" +
  "    const { width: w, height: h } = svg.viewBox.baseVal;\n" +
  "    const s = base * k, cw = chart.clientWidth, ch = chart.clientHeight;\n" +
  "    // In the middle while it is smaller than the screen; else its edges kept on the screen.\n" +
  "    x = w * s <= cw ? (cw - w * s) / 2 : Math.min(0, Math.max(cw - w * s, x));\n" +
  "    y = h * s <= ch ? (ch - h * s) / 2 : Math.min(0, Math.max(ch - h * s, y));\n" +
  "    svg.style.width = w * s + \"px\";\n" +
  "    svg.style.height = h * s + \"px\";\n" +
  "    svg.style.left = x + \"px\";\n" +
  "    svg.style.top = y + \"px\";\n" +
  "  }\n" +
  "  function zoom(to, px, py) {\n" +
  "    to = Math.min(most, Math.max(1, to));\n" +
  "    x = px - (px - x) * to / k;\n" +
  "    y = py - (py - y) * to / k;\n" +
  "    k = to;\n" +
  "    show();\n" +
  "  }\n" +
  "  // The chart at its size: as written (its viewBox) scaled to fit, no smaller than READABLE in a message.\n" +
  "  function place() {\n" +
  "    const svg = chart.querySelector(\"svg\");\n" +
  "    if (!svg) return;\n" +
  "    const { width: w, height: h } = svg.viewBox.baseVal;\n" +
  "    if (!w || !h) return;\n" +
  "    svg.removeAttribute(\"width\");\n" +
  "    svg.removeAttribute(\"height\");\n" +
  "    svg.style.maxWidth = \"none\";\n" +
  "    svg.style.display = \"block\";\n" +
  "    if (FULL) {\n" +
  "      svg.style.position = \"absolute\";\n" +
  "      base = Math.min(1, chart.clientWidth / w, chart.clientHeight / h);\n" +
  "      // Up to twice its size as written, or 4 times the screen's fit if more.\n" +
  "      most = Math.max(4, 2 / base);\n" +
  "      k = 1;\n" +
  "      show();\n" +
  "      return;\n" +
  "    }\n" +
  "    const scale = Math.max(fit(w), READABLE);\n" +
  "    svg.style.margin = \"0 auto\";\n" +
  "    svg.style.width = w * scale + \"px\";\n" +
  "    svg.style.height = h * scale + \"px\";\n" +
  "  }\n" +
  "  async function draw() {\n" +
  "    if (!mermaid) return;\n" +
  "    if (!chart.clientWidth) { waiting = true; return; }\n" +
  "    waiting = false;\n" +
  "    width = chart.clientWidth;\n" +
  "    try {\n" +
  "      mermaid.initialize({ startOnLoad: false, securityLevel: \"strict\", theme: \"base\", fontFamily: v(\"--font-sans\"), themeVariables: {\n" +
  "        darkMode: document.documentElement.dataset.theme === \"dark\", fontSize: \"14px\",\n" +
  "        background: v(\"--background\"), primaryColor: v(\"--card\"), primaryTextColor: v(\"--foreground\"), primaryBorderColor: v(\"--border-strong\"),\n" +
  "        secondaryColor: v(\"--accent\"), tertiaryColor: v(\"--muted\"), lineColor: v(\"--muted-foreground\"), textColor: v(\"--foreground\"),\n" +
  "        noteBkgColor: v(\"--accent\"), noteTextColor: v(\"--foreground\"), noteBorderColor: v(\"--brand\"),\n" +
  "        actorBkg: v(\"--card\"), actorBorder: v(\"--border-strong\"), actorTextColor: v(\"--foreground\"), signalColor: v(\"--foreground\"), signalTextColor: v(\"--foreground\"),\n" +
  "      } });\n" +
  "      chart.replaceChildren(await render(source));\n" +
  "      place();\n" +
  "    } catch (e) { post({ type: \"failed\", message: String(e?.message ?? e) }); }\n" +
  "  }\n" +
  "  addEventListener(\"ember-viz:theme\", draw);\n" +
  "  // A new width (the screen turned): drawn now if it was waiting for one, else sized again. After the observer's turn:\n" +
  "  // drawing in it changes the layout it reports on.\n" +
  "  new ResizeObserver(() => {\n" +
  "    if (!chart.clientWidth || chart.clientWidth === width) return;\n" +
  "    if (waiting) setTimeout(draw); else { width = chart.clientWidth; setTimeout(place); }\n" +
  "  }).observe(chart);\n" +
  "  if (FULL) {\n" +
  "    // Pinched with two fingers, moved with one; a double tap zooms in to its size as written there, or back out. The\n" +
  "    // page's own, the same in every app: a WebView's own zoom is not there on every host.\n" +
  "    const at = (e) => { const r = chart.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };\n" +
  "    const fingers = new Map();\n" +
  "    let tap = null;\n" +
  "    chart.addEventListener(\"pointerdown\", (e) => { chart.setPointerCapture(e.pointerId); fingers.set(e.pointerId, at(e)); });\n" +
  "    chart.addEventListener(\"pointermove\", (e) => {\n" +
  "      if (!fingers.has(e.pointerId)) return;\n" +
  "      const was = [...fingers.values()];\n" +
  "      fingers.set(e.pointerId, at(e));\n" +
  "      const now = [...fingers.values()];\n" +
  "      if (now.length === 1) { x += now[0].x - was[0].x; y += now[0].y - was[0].y; show(); return; }\n" +
  "      const mid = (p) => ({ x: (p[0].x + p[1].x) / 2, y: (p[0].y + p[1].y) / 2 });\n" +
  "      const far = (p) => Math.hypot(p[0].x - p[1].x, p[0].y - p[1].y) || 1;\n" +
  "      const m0 = mid(was), m1 = mid(now);\n" +
  "      x += m1.x - m0.x;\n" +
  "      y += m1.y - m0.y;\n" +
  "      zoom(k * far(now) / far(was), m1.x, m1.y);\n" +
  "    });\n" +
  "    const up = (e) => {\n" +
  "      const p = fingers.get(e.pointerId);\n" +
  "      const alone = fingers.size === 1;\n" +
  "      fingers.delete(e.pointerId);\n" +
  "      if (!p || !alone || e.type !== \"pointerup\") return;\n" +
  "      if (tap && e.timeStamp - tap.t < 300 && Math.hypot(p.x - tap.x, p.y - tap.y) < 30) {\n" +
  "        zoom(k > 1.01 ? 1 : Math.max(2, 1 / base), p.x, p.y);\n" +
  "        tap = null;\n" +
  "      } else tap = { t: e.timeStamp, x: p.x, y: p.y };\n" +
  "    };\n" +
  "    chart.addEventListener(\"pointerup\", up);\n" +
  "    chart.addEventListener(\"pointercancel\", up);\n" +
  "    // A mouse's wheel moves it; with ctrl (a trackpad's pinch), zooms it.\n" +
  "    chart.addEventListener(\"wheel\", (e) => {\n" +
  "      e.preventDefault();\n" +
  "      const p = at(e);\n" +
  "      if (e.ctrlKey) zoom(k * Math.exp(-e.deltaY / 100), p.x, p.y);\n" +
  "      else { x -= e.deltaX; y -= e.deltaY; show(); }\n" +
  "    }, { passive: false });\n" +
  "  }\n" +
  "  draw();\n" +
  "</script>\n"
}

///|
/// Charts that would not draw (mermaid not reachable, or the source does not parse): shown as code from then on.
pub let viz_unmade : Map[String, Bool] = Map([])

///|
/// A ```mermaid block: drawn as a chart (`place`: the message it is in), with a way under it to open it over the whole
/// screen (in `subtle`, the frame's grey); shown as code while it will not draw.
pub fn viz_mermaid_block(c : @ui.Ctx, place : String, code : String, subtle : Int64) -> Unit {
  if viz_unmade.contains(code) {
    @sf.code_block(c, code, "mermaid")
    return
  }
  c.box(style=viz_mermaid_box, fn() {
    viz_frame(c, place + "/mermaid/" + code, viz_mermaid_document(code), None, {
      keep: None,
      failed: Some(fn(_why) { viz_unmade[code] = true }),
      follow_up: None,
    })
    // under the chart, out of its way, as a placed file has it
    c.box(style=viz_ways, fn() {
      let full = c.id("viz/full/" + place + "/mermaid/" + code)
      if c.clicked(full) {
        c.tell("viz/open-mermaid", fn() { viz_open_mermaid(code) })
      }
      viz_icon(c, full, "expand", viz_tr("android-misc.viz.fullscreen"), subtle)
    })
    |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
pub let viz_mermaid_box : @ui.Style = @ui.css("w=Full")

///|
/// What the visualizations keep put back as the app begins anew (sfbase's reset).
pub fn viz_pages_reset() -> Unit {
  viz_frames.clear()
  viz_extra_frames.clear()
  viz_left_chats.clear()
  viz_heights.clear()
  viz_full.set(None)
  viz_unmade.clear()
  followed_into.clear()
}
