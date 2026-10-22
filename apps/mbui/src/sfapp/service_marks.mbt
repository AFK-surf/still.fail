// Marking a service's page for its chat's agent (ember apps/android chat/screens/Preview.kt: MarkMode, MarksOver, Note,
// putIntoChat; web/src/annotate/Marks.tsx): the bar's edit key starts picking, page.js holds the page's taps and says
// what was picked (`marked`: picked, focus, at); each mark a box on its element with a numbered pin on its corner and
// what is said of it in a bubble beside it. Put into the chat, each mark goes into its draft as a screenshot of what
// the window shows with only that mark drawn on it (a mark out of sight scrolled into the middle first, the page put
// back after) and a quote saying where it is.
//
// What the page is asked (its scroll, where a mark is) it answers by saying it (`mbuiHost.post`, `p: "shot"`), each
// step begun by the answer to the one before, the picture taken once the page has said where the mark is: nothing
// waits on a time.

///|
/// A script for the page from marking (Preview.kt's js), sent once the frame's builds are over (service_body's
/// c.tell): one a build says is said once, whichever build of the frame says it.
fn page_say(p : ServicePage, js : String) -> Unit {
  p.marks.out.push(js)
}

///|
/// A mark: what was picked on the page (annotate/frame.ts's Picked), and what is said about it.
priv struct PageMark {
  n : Int
  path : String
  vw : Int
  vh : Int
  label : String
  kind : String
  selector : String
  text : String
  rect : (Double, Double, Double, Double)
  component : String
  mut comment : String
}

///|
/// Putting the marks into the chat (putIntoChat), a step at a time: the marks, the one at, the page's scroll when it
/// began, what the window showed (taken once for every mark in sight), what is waited for, where the mark is (its
/// box in the page's viewport, the viewport's width), the pictures and quotes made so far.
priv struct Shooting {
  k : Int
  todo : Array[PageMark]
  mut i : Int
  mut y0 : Double
  mut now : Bytes?
  mut wait : ShotWait
  mut place : (Double, Double, Double, Double, Double)
  pictures : Array[(String, Bytes, (String, String, String))]
  stamp : String
}

///|
priv enum ShotWait {
  /// the page's scroll
  Scroll
  /// where the mark is (`center`: scrolled into the middle first)
  Place(Bool)
  /// the page's picture (`center`: of the mark scrolled into sight)
  Grab(Bool)
  /// the picture with the mark drawn on it
  Draw(@ui.MarkedImage)
}

///|
/// A page's marks while it is in the stack (Preview.kt PageState): picking or not, the marks, where each is now in the
/// page's viewport (as the page last said) and the viewport's size in CSS pixels, the one whose note is open, putting
/// them into the chat, why that failed.
priv struct PageMarks {
  mut marking : Bool
  marks : Array[PageMark]
  at : Map[Int, (Double, Double, Double, Double)]
  mut css_w : Double
  mut css_h : Double
  mut editing : Int?
  /// the open note's words (its field shows them)
  note : @ui.Field
  mut error : String
  mut shot : Shooting?
  mut shots : Int
  /// scripts for the page not sent yet (page_say), how many times they were
  out : Array[String]
  mut sent : Int
}

///|
fn page_marks_new() -> PageMarks {
  { marking: false, marks: [], at: {}, css_w: 0.0, css_h: 0.0, editing: None, note: @ui.Field::new(), error: "", shot: None, shots: 0, out: [], sent: 0 }
}

///|
/// The accent marks are drawn in on the page's pictures (Preview.kt drawMark), and the pin's ground.
let page_mark_color : Int64 = 0xEF6A3CFFL

///|
let page_mark_halo : Int64 = 0xFFFFFFFFL

///|
/// A box of the page's viewport, as the page says it ({x, y, width, height}).
fn css_box(v : Json?) -> (Double, Double, Double, Double)? {
  match (field(v, "x"), field(v, "y"), field(v, "width"), field(v, "height")) {
    (Some(Number(x, ..)), Some(Number(y, ..)), Some(Number(w, ..)), Some(Number(h, ..))) => Some((x, y, w, h))
    _ => None
  }
}

///|
/// What the page's marking says (page.js `marked`; any script of the page may say it: what does not read is let go).
fn service_marked(p : ServicePage, said : Json) -> Unit {
  let m = p.marks
  let s = Some(said)
  match text(s, "event") {
    "picked" => {
      let k = field(s, "mark")
      let vp = field(k, "viewport")
      match (field(k, "n"), css_box(field(k, "rect"))) {
        (Some(Number(n, ..)), Some(rect)) => {
          let n = n.to_int()
          if m.marks.iter().any(fn(x) { x.n == n }) {
            return
          }
          m.marks.push({
            n,
            path: text(k, "path"),
            vw: number(vp, "width").to_int(),
            vh: number(vp, "height").to_int(),
            label: text(k, "label"),
            kind: text(k, "kind"),
            selector: text(k, "selector"),
            text: text(k, "text"),
            rect,
            component: text(k, "component"),
            comment: "",
          })
          m.at[n] = rect
          m.css_w = number(vp, "width")
          m.css_h = number(vp, "height")
          m.editing = Some(n)
          m.error = ""
        }
        _ => ()
      }
    }
    "focus" =>
      match field(s, "n") {
        Some(Number(n, ..)) => m.editing = Some(n.to_int())
        _ => ()
      }
    "at" => {
      if number(s, "width") > 0.0 {
        m.css_w = number(s, "width")
      }
      if number(s, "height") > 0.0 {
        m.css_h = number(s, "height")
      }
      let boxes : Map[Int, (Double, Double, Double, Double)] = {}
      for b in items(s, "at") {
        match (field(Some(b), "n"), css_box(Some(b))) {
          (Some(Number(n, ..)), Some(r)) => boxes[n.to_int()] = r
          _ => ()
        }
      }
      m.at.clear()
      for n, r in boxes {
        m.at[n] = r
      }
    }
    _ => ()
  }
}

///|
/// A new page: the marks of the one before are gone, picking goes on (Preview.kt PreviewClient's started, loaded).
fn page_marks_new_page(p : ServicePage, site : @ui.NativeView) -> Unit {
  let m = p.marks
  m.marks.clear()
  m.at.clear()
  m.editing = None
  if m.marking {
    page_say(p, "window.__stillfailMarks&&__stillfailMarks.on(true)")
  }
}

///|
/// Marking stopped: its marks gone (Preview.kt leave).
fn page_marks_leave(p : ServicePage, site : @ui.NativeView) -> Unit {
  let m = p.marks
  m.marks.clear()
  m.at.clear()
  m.editing = None
  m.error = ""
  m.marking = false
  page_say(p, "window.__stillfailMarks&&(__stillfailMarks.clear(),__stillfailMarks.on(false))")
}

///|
/// The bar's edit key turned (Preview.kt BarIcon(Icons.Edit)): picking on or off.
fn page_marks_toggle(p : ServicePage, site : @ui.NativeView) -> Unit {
  p.marks.marking = !p.marks.marking
  page_say(p, "window.__stillfailMarks&&__stillfailMarks.on(\{p.marks.marking})")
}

///|
/// One mark gone (its note's remove key).
fn page_marks_remove(p : ServicePage, site : @ui.NativeView, n : Int) -> Unit {
  let m = p.marks
  match m.marks.search_by(fn(x) { x.n == n }) {
    Some(i) => m.marks.remove(i) |> ignore
    None => ()
  }
  m.at.remove(n)
  m.editing = None
  page_say(p, "window.__stillfailMarks&&__stillfailMarks.remove(\{n})")
}

// ── into the chat's draft ─

///|
/// A script that asks the page something and has it say the answer (`p: "shot"`, `k` the putting it belongs to,
/// `t` what was asked); `then` after a frame or two of the page's (once a scroll is drawn).
fn shot_ask(k : Int, t : String, expr : String, drawn? : Bool = false) -> String {
  let say = "mbuiHost.post(JSON.stringify({p:\"shot\",k:\{k},t:\"\{t}\",v:\{expr}}))"
  if drawn {
    "requestAnimationFrame(()=>requestAnimationFrame(()=>" + say + "))"
  } else {
    say
  }
}

///|
/// The marks put into the chat's draft (Preview.kt putIntoChat): begun here, each step as the page answers.
fn page_marks_put(p : ServicePage, site : @ui.NativeView, src : Source) -> Unit {
  let m = p.marks
  if m.marks.length() == 0 || m.shot is Some(_) {
    return
  }
  m.error = ""
  m.editing = None
  m.shots += 1
  m.shot = Some({
    k: m.shots,
    todo: m.marks.copy(),
    i: 0,
    y0: 0.0,
    now: None,
    wait: Scroll,
    place: (0.0, 0.0, 0.0, 0.0, 0.0),
    pictures: [],
    // (the time of day the name carries, as the viewer's marked images have it)
    stamp: clock_stamp((src_now.val)()),
  })
  page_say(p, shot_ask(m.shots, "y0", "scrollY"))
}

///|
/// Putting them failed: said in the bar, in red (Preview.kt state.error).
fn shot_failed(p : ServicePage, words : String) -> Unit {
  p.marks.shot = None
  p.marks.error = svc("android-chat.preview.put.failed", args=[("error", words)])
}

///|
/// The next mark's place asked, or all of them done.
fn shot_next(p : ServicePage, site : @ui.NativeView) -> Unit {
  let s = match p.marks.shot {
    Some(s) => s
    None => return
  }
  if s.i >= s.todo.length() {
    shot_done(p, site, s)
    return
  }
  s.wait = Place(false)
  let n = s.todo[s.i].n
  page_say(p, shot_ask(s.k, "place", "__stillfailMarks.place(\{n},false)"))
}

///|
/// What the page answered while the marks are put (`p: "shot"`): its scroll, where a mark is.
fn shot_said(p : ServicePage, site : @ui.NativeView, said : Json) -> Unit {
  let s = match p.marks.shot {
    Some(s) if number(Some(said), "k").to_int() == s.k => s
    _ => return
  }
  let v = field(Some(said), "v")
  match (text(Some(said), "t"), s.wait) {
    ("y0", Scroll) => {
      s.y0 = match v {
        Some(Number(y, ..)) => y
        _ => 0.0
      }
      shot_next(p, site)
    }
    ("place", Place(center)) => {
      let n = s.todo[s.i].n
      let place = match v {
        Some(String(j)) =>
          match (try Some(@json.parse(j)) catch { _ => None }) {
            Some(o) =>
              match css_box(Some(o)) {
                Some((x, y, w, h)) if number(Some(o), "width") > 0.0 => Some((x, y, w, h, number(Some(o), "width")))
                _ => None
              }
            None => None
          }
        _ => None
      }
      match place {
        None => shot_failed(p, svc("android-chat.preview.mark.gone", args=[("n", n.to_string())]))
        Some(pl) => {
          s.place = pl
          let (_, y, _, h, _) = pl
          let in_sight = y + h > 0.0 && (p.marks.css_h <= 0.0 || y < p.marks.css_h)
          if center || in_sight {
            match s.now {
              Some(png) if !center => shot_draw(p, s, png)
              _ => {
                s.wait = Grab(center)
                site.grab_frame(0.0)
              }
            }
          } else {
            // out of sight: scrolled into the middle, and asked again once that is drawn
            s.wait = Place(true)
            page_say(p, shot_ask(s.k, "place", "__stillfailMarks.place(\{n},true)", drawn=true))
          }
        }
      }
    }
    _ => ()
  }
}

///|
/// Each frame while the marks are put: the page's picture once it is here, the mark drawn on it once it is.
fn page_marks_frame(p : ServicePage, site : @ui.NativeView) -> Unit {
  let name = p.name
  let s = match p.marks.shot {
    Some(s) => s
    None => return
  }
  match s.wait {
    Grab(center) =>
      match site.grabbed() {
        Some(png) => {
          if png.length() == 0 {
            shot_failed(p, svc("android-chat.preview.shot.failed"))
            return
          }
          if center {
            page_say(p, "__stillfailMarks.back(\{s.y0})")
          } else {
            s.now = Some(png)
          }
          shot_draw(p, s, png)
        }
        None => ()
      }
    Draw(job) =>
      match job.made() {
        Some(png) => {
          if png.length() == 0 {
            shot_failed(p, svc("android-chat.preview.shot.failed"))
            return
          }
          let mark = s.todo[s.i]
          let file = svc("android-chat.preview.mark.file", args=[
            ("name", name),
            ("n", mark.n.to_string()),
            ("stamp", s.stamp),
          ])
          s.pictures.push((
            file,
            png,
            (
              svc("android-chat.preview.mark.quote", args=[("name", name), ("n", mark.n.to_string())]),
              mark_where(mark, file),
              mark.comment.trim(chars=" \n\t").to_string(),
            ),
          ))
          s.i += 1
          shot_next(p, site)
        }
        None => ()
      }
    _ => ()
  }
}

///|
/// The mark drawn on the window's picture (Preview.kt drawMark): its outline, its number in a pin on its corner, in
/// the picture's pixels (`ratio` of them to the page's CSS pixel).
fn shot_draw(p : ServicePage, s : Shooting, png : Bytes) -> Unit {
  let (pw, ph) = match png_size(png) {
    Some(wh) => wh
    None => {
      shot_failed(p, svc("android-chat.preview.shot.failed"))
      return
    }
  }
  let (x, y, w, h, css_w) = s.place
  let ratio = pw.to_double() / css_w
  let mark = Json::object({
    "kind": Json::string("box"),
    "color": Json::number(page_mark_color.to_double()),
    "halo": Json::number(page_mark_halo.to_double()),
    "w": Json::number(2.0 * ratio),
    "pts": Json::array([x * ratio, y * ratio, (x + w) * ratio, (y + h) * ratio].map(fn(v) { Json::number(v) })),
    "text": Json::string(""),
    "n": Json::number(s.todo[s.i].n.to_double()),
  })
  let marks = Json::object({
    "w": Json::number(pw.to_double()),
    "h": Json::number(ph.to_double()),
    "marks": Json::array([mark]),
  }).stringify()
  match @ui.draw_marks(png, marks) {
    Some(job) => s.wait = Draw(job)
    None => shot_failed(p, svc("android-chat.preview.shot.failed"))
  }
}

///|
/// A PNG's width and height (its IHDR's), None for anything else.
fn png_size(b : Bytes) -> (Int, Int)? {
  match @pixels.image_size(b) {
    Some((w, h)) if @pixels.is_png(b) && w > 0 && h > 0 => Some((w, h))
    _ => None
  }
}

///|
/// All the marks drawn: their pictures and quotes into the chat's draft, said so, marking left.
fn shot_done(p : ServicePage, site : @ui.NativeView, s : Shooting) -> Unit {
  let key = p.station + ":" + p.session
  let list = marked_into.get(key).unwrap_or([])
  for x in s.pictures {
    list.push((x.0, x.1, [x.2], "page"))
  }
  marked_into[key] = list
  p.marks.shot = None
  page_marks_leave(p, site)
  app.toast = svc("android-chat.preview.put.done")
  app.toast_n += 1
}

///|
/// Where a mark is, as the agent reads it with its screenshot `shot` (Preview.kt where): the first line is also what
/// the composer shows.
fn mark_where(m : PageMark, shot : String) -> String {
  let lines = [
    if m.text != "" {
      svc("android-chat.preview.where.text", args=[("kind", m.kind), ("text", m.text)])
    } else {
      m.kind
    },
    svc("android-chat.preview.where.element", args=[("label", m.label), ("selector", m.selector)]),
    svc("android-chat.preview.where.page", args=[
      ("path", m.path),
      ("width", m.vw.to_string()),
      ("height", m.vh.to_string()),
      ("shot", shot),
    ]),
  ]
  if m.component != "" {
    lines.push(svc("android-chat.preview.where.component", args=[("name", m.component)]))
  }
  lines.join("\n")
}

// ── what marking shows ─

///|
/// The bar's edit key (Preview.kt BarIcon(Icons.Edit, pressed)): 28 round, a 14 icon; picking, the accent's 14% under
/// it and its icon in the accent's ink.
fn page_mark_key(c : @ui.Ctx, on : Bool) -> Bool {
  let t = @sf.theme()
  let id = c.id("service/mark")
  c.box(style=if on { mark_key_on } else { mark_key }, id~, fn() {
    @sf.icon(c, "edit", size=bar_icon_size, color=if on { t.p.accent_text } else { t.p.text }) |> ignore
  })
  |> ignore
  c.clicked(id)
}

///|
/// A bar key's icon (Preview.kt BarIcon: 14).
let bar_icon_size : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
let mark_key : @ui.Style = @ui.style(w=S7, h=S7, radius=Full, align=ACenter, justify=JCenter, pressed=@ui.patch(bg=Hover))

///|
// kept across runs: a value (no field of it changes)
let mark_key_on : @ui.Style = mark_key.then(@ui.style(bg=@sf.mark_key_on))

///|
/// The address's place while marking (Preview.kt Bar's `instead`: 4 in at each side, all the room there is).
// kept across runs: a value (no field of it changes)
let mark_mode_place : @ui.Style = @ui.style(w=Full, px=S1)

///|
/// MarkMode's capsule: 30 high, round, the chip's ground a tenth of the way to the accent, 12 in at its start and 3 at
/// its end, 8 apart.
// kept across runs: a value (no field of it changes)
let mark_mode_bar : @ui.Style = @ui.style(
  row=true,
  w=Full,
  h=@sf.mark_bar_h,
  radius=Full,
  bg=Over(A(Accent, O10), Faint),
  pl=S3,
  pr=@sf.mark_bar_end,
  gap=S2,
  align=ACenter,
  clip=true,
)

///|
/// Its dot (7, the accent while picking, else muted), in a 13 ring of the accent's 22% while picking.
// kept across runs: a value (no field of it changes)
let mark_dot_box : @ui.Style = @ui.style(w=@sf.dot_size, h=@sf.dot_size, radius=Full, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let mark_dot_ring : @ui.Style = mark_dot_box.then(@ui.style(w=@sf.mark_ring, h=@sf.mark_ring, bg=@sf.mark_ring_bg))

///|
// kept across runs: a value (no field of it changes)
let mark_dot : @ui.Style = @ui.style(w=@sf.dot_size, h=@sf.dot_size, radius=Full, bg=Muted)

///|
// kept across runs: a value (no field of it changes)
let mark_dot_on : @ui.Style = mark_dot.then(@ui.style(bg=Accent))

///|
/// What it says: how many (or what to do), 13 medium in the ink; 可继续点选 muted; why it failed in red; all on one line.
// kept across runs: a value (no field of it changes)
let mark_words_box : @ui.Style = @ui.style(row=true, w=Full, gap=S2, clip=true)

///|
// kept across runs: a value (no field of it changes)
let mark_count_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let mark_more_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let mark_error_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Danger, wrap=false)

///|
/// Its × (24 round, a 12 icon) and 添加到对话 (24 high, round, the ink's ground, 10 in, 5 apart; 12 medium, the
/// surface's colour: faint while it cannot be pressed).
// kept across runs: a value (no field of it changes)
let mark_close : @ui.Style = @ui.style(w=S6, h=S6, radius=Full, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let mark_put_pill : @ui.Style = @ui.style(
  row=true,
  h=S6,
  radius=Full,
  bg=Fg,
  px=S2_5,
  gap=@sf.mark_put_gap,
  align=ACenter,
)

///|
// kept across runs: a value (no field of it changes)
let mark_put_off : @ui.Style = mark_put_pill.then(@ui.style(bg=A(Fg, O40)))

///|
// kept across runs: a value (no field of it changes)
let mark_put_words : @ui.TextStyle = @ui.text_style(
  size=Xs,
  weight=Medium,
  color=Card,
  wrap=false,
  dark=@ui.text_patch(color=Bg),
)

///|
/// A small icon in marking's bar (Preview.kt: 12).
let mark_small_icon : Double = 12.0

///|
/// In the address's place while marking (Preview.kt MarkMode): what to do or how many, then putting them into the
/// chat.
fn page_mark_mode(c : @ui.Ctx, src : Source, p : ServicePage, site : @ui.NativeView) -> Unit {
  let t = @sf.theme()
  let m = p.marks
  let n = m.marks.length()
  let busy = m.shot is Some(_)
  c.box(style=mark_mode_bar, fn() {
    c.box(style=if m.marking { mark_dot_ring } else { mark_dot_box }, fn() {
      c.box(style=if m.marking { mark_dot_on } else { mark_dot }, fn() {  }) |> ignore
    })
    |> ignore
    c.box(style=mark_words_box, fn() {
      if m.error != "" {
        c.text(m.error, style=mark_error_words) |> ignore
      } else {
        let said = if n > 0 {
          svc("android-chat.preview.marked", args=[("n", n.to_string())])
        } else {
          svc("android-chat.preview.pick")
        }
        c.text(said, style=mark_count_words) |> ignore
        if m.marking && n > 0 {
          c.text(svc("android-chat.preview.pickMore"), style=mark_more_words) |> ignore
        }
      }
    })
    |> ignore
    // ×: marking left
    let close = c.id("service/mark-close")
    if !busy && c.clicked(close) {
      page_marks_leave(p, site)
    }
    c.box(style=mark_close, id=if busy { 0 } else { close }, fn() {
      @sf.icon(c, "close", size=mark_small_icon, color=t.p.muted) |> ignore
    })
    |> ignore
    // 添加到对话 (正在截图 while it is)
    let able = !busy && n > 0
    let put = c.id("service/mark-put")
    if able && c.clicked(put) {
      page_marks_put(p, site, src)
    }
    let ink = if t.dark { t.p.bg } else { 0xFFFFFFFFL }
    c.box(style=if able { mark_put_pill } else { mark_put_off }, id=if able { put } else { 0 }, fn() {
      @sf.icon(c, "send", size=mark_small_icon, color=ink) |> ignore
      let words = svc(if busy { "android-chat.preview.shooting" } else { "android-chat.preview.put" })
      c.text(words, style=mark_put_words) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A mark's box on its element (Preview.kt MarksOver): 4 round, its edge the accent's 55% (1.5), open the accent (2)
/// over its 8%.
// kept across runs: a value (no field of it changes)
let mark_box_open : @ui.Style = @ui.style(radius=Base, border=B2, border_color=Accent, bg=@sf.mark_open_bg)

///|
/// A mark's box not open: 4 round, its edge 1.5 of the accent's 55%.
let mark_box_r : Double = 4.0

///|
let mark_edge : Double = 1.5

///|
let mark_edge_a : Double = 0.55

///|
/// A mark's pin: 24, round, white, 2 in, a shadow; the accent inside, its number 11 bold in white.
// kept across runs: a value (no field of it changes)
let mark_pin : @ui.Style = @ui.style(w=S6, h=S6, radius=Full, bg=OnAccent, p=S0_5, shadow=@sf.pin_raised.cast())

///|
// kept across runs: a value (no field of it changes)
let mark_pin_in : @ui.Style = @ui.style(w=Full, h=Full, radius=Full, bg=Accent, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let mark_pin_words : @ui.TextStyle = @ui.text_style(size=@sf.mark_pin_size, weight=Bold, color=OnAccent, wrap=false)

///|
/// What is said of a mark beside its pin: 26 high, round, frosted, a shadow, 10 in; 12 in the ink, one line.
// kept across runs: a value (no field of it changes)
let mark_said : @ui.Style = @ui.style(
  h=@sf.mark_said_h,
  radius=Full,
  bg=@sf.mark_bubble,
  shadow=@sf.pin_raised.cast(),
  px=S2_5,
  justify=JCenter,
  clip=true,
  dark=@ui.patch(bg=@sf.mark_bubble_dark),
)

///|
// kept across runs: a value (no field of it changes)
let mark_said_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false)

///|
/// The marks over the page, where it is drawn (Preview.kt MarksOver): each a box on its element, a numbered pin on its
/// corner (kept in sight at the page's edges), what is said of it beside the pin, or its note open. `ox`, `oy`: the
/// page's top left on the stage; `view_w` its width there before its scale; `stage_w` the stage's width.
fn page_marks_over(
  c : @ui.Ctx,
  p : ServicePage,
  site : @ui.NativeView,
  ox : Double,
  oy : Double,
  view_w : Double,
  scale : Double,
  stage_w : Double,
) -> Unit {
  let t = @sf.theme()
  let m = p.marks
  // CSS pixels to the stage's: the page's own ratio, then the stage's scale
  let k = if m.css_w > 0.0 { view_w / m.css_w * scale } else { scale }
  c.layer(fn() {
    for mark in m.marks {
      let (bx, by, bw, bh) = m.at.get(mark.n).unwrap_or(mark.rect)
      let x = ox + bx * k
      let y = oy + by * k
      let open = m.editing == Some(mark.n)
      let size = @ui.style(w=Fixed(bw * k), h=Fixed(bh * k))
      if open {
        c.box(style=mark_box_open.then(size), tx=x, ty=y, fn() {  }) |> ignore
      } else {
        // (its edge 1.5, which no Stroke of the scale says: said loosely)
        c.box(style=size, tx=x, ty=y, radius=mark_box_r, border=mark_edge, border_color=@sf.alpha(t.p.accent, mark_edge_a), fn() {  })
        |> ignore
      }
      // the pin's point on the element's top-left corner
      let pin_x = dmax(pin_edge, x)
      let pin_y = dmax(pin_top, y)
      let pin = c.id("service/pin/\{mark.n}")
      if c.clicked(pin) {
        m.editing = if open { None } else { Some(mark.n) }
        if !open {
          m.note.set(mark.comment)
          c.focus_editor("service/note")
        }
      }
      c.box(style=mark_pin, tx=pin_x - pin_edge, ty=pin_y - pin_rise, id=pin, fn() {
        c.box(style=mark_pin_in, fn() { c.text("\{mark.n}", style=mark_pin_words) |> ignore }) |> ignore
      })
      |> ignore
      if open {
        page_mark_note(c, p, site, mark, pin_x, pin_y, stage_w)
      } else if mark.comment != "" {
        // beside the pin, on its left when the right has too little room
        let right = stage_w - pin_x - said_from >= dmin(said_room, pin_x - said_left)
        let max_w = dmax(said_least, if right { stage_w - pin_x - said_from } else { pin_x - said_left })
        let said = c.id("service/said/\{mark.n}")
        if c.clicked(said) {
          m.editing = Some(mark.n)
          m.note.set(mark.comment)
          c.focus_editor("service/note")
        }
        let row = @ui.style(row=true, w=Fixed(if right { max_w } else { pin_x - said_beside }), justify=if right {
          JStart
        } else {
          JEnd
        })
        c.box(style=row, tx=if right { pin_x + pin_w + pin_edge * 2.0 } else { 0.0 }, ty=pin_y - pin_rise - 1.0, fn() {
          c.box(style=mark_said.then(@ui.style(max_w=Fixed(max_w))), id=said, fn() {
            c.text(mark.comment, style=mark_said_words) |> ignore
          })
          |> ignore
        })
        |> ignore
      }
    }
  })
  |> ignore
}

///|
/// Where a pin sits (Preview.kt MarksOver): 24 wide, its point 2 in from its left and 22 down, kept 2 from the
/// stage's left and 24 from its top; what is said 36 right of its point (28 past it), 220 wanted there, else left of it
/// (14 clear, 6 from the pin), 40 at least.
let pin_w : Double = 24.0

///|
let pin_edge : Double = 2.0

///|
let pin_rise : Double = 22.0

///|
let pin_top : Double = 24.0

///|
let said_from : Double = 36.0

///|
let said_room : Double = 220.0

///|
let said_left : Double = 14.0

///|
let said_beside : Double = 6.0

///|
let said_least : Double = 40.0

///|
/// A mark's note (Preview.kt Note): 280 wide at most (8 clear of the stage's sides), 36 high, round, frosted, a
/// stronger shadow, 12 in at its start and 4 at its end, 6 apart; 28 right of the pin's point and 28 above it (8 from
/// the stage's top at least).
// kept across runs: a value (no field of it changes)
let mark_note : @ui.Style = @ui.style(
  row=true,
  h=S9,
  radius=Full,
  bg=@sf.mark_bubble,
  shadow=@sf.bubble_raised.cast(),
  pl=S3,
  pr=S1,
  gap=S1_5,
  align=ACenter,
  dark=@ui.patch(bg=@sf.mark_bubble_dark),
)

///|
// kept across runs: a value (no field of it changes)
let mark_note_field : @ui.Style = @ui.style(w=Full)

///|
// kept across runs: a value (no field of it changes)
let mark_note_remove : @ui.Style = @ui.style(w=S7, h=S7, radius=Full, align=ACenter, justify=JCenter)

///|
let note_most : Double = 280.0

///|
let note_clear : Double = 8.0

///|
let note_off : Double = 28.0

///|
/// The note's words (13) and its remove key's icon (14).
let note_font : Double = 13.0

///|
let note_icon : Double = 14.0

///|
/// What is said about one mark, in a bubble beside its pin (Preview.kt Note): what it is for while empty; done, closed;
/// its remove key takes the mark off the page too.
fn page_mark_note(
  c : @ui.Ctx,
  p : ServicePage,
  site : @ui.NativeView,
  mark : PageMark,
  x : Double,
  y : Double,
  stage_w : Double,
) -> Unit {
  let t = @sf.theme()
  let width = dmin(note_most, stage_w - 2.0 * note_clear)
  let left = dmin(dmax(note_clear, x + note_off), dmax(note_clear, stage_w - width - note_clear))
  let top = dmax(note_clear, y - note_off)
  c.box(style=mark_note.then(@ui.style(w=Fixed(width))), tx=left, ty=top, fn() {
    c.box(style=mark_note_field, fn() {
      let r = c.editor(
        "service/note",
        font_size=note_font,
        max_lines=1,
        plain=true,
        color=t.p.text,
        caret_color=t.p.accent,
        placeholder=svc("android-chat.preview.mark.comment", args=[("kind", mark.kind)]),
        placeholder_color=t.p.muted,
        field=p.marks.note,
      )
      mark.comment = r.text
      match r.submitted {
        Some(_) => {
          p.marks.editing = None
          c.blur()
        }
        None => ()
      }
    })
    |> ignore
    let remove = c.id("service/note-remove")
    if c.clicked(remove) {
      page_marks_remove(p, site, mark.n)
      c.blur()
    }
    c.box(style=mark_note_remove, id=remove, fn() {
      @sf.icon(c, "trash", size=note_icon, color=t.p.muted) |> ignore
    })
    |> ignore
  })
  |> ignore
}
