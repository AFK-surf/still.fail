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
pub fn page_say(p : ServicePage, js : String) -> Unit {
  p.marks.out.push(js)
}

///|
/// A mark: what was picked on the page (annotate/frame.ts's Picked), and what is said about it.
pub(all) struct PageMark {
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
pub(all) struct Shooting {
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
pub(all) enum ShotWait {
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
pub(all) struct PageMarks {
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
pub fn page_marks_new() -> PageMarks {
  { marking: false, marks: [], at: {}, css_w: 0.0, css_h: 0.0, editing: None, note: @ui.Field::new(), error: "", shot: None, shots: 0, out: [], sent: 0 }
}

///|
/// The accent marks are drawn in on the page's pictures (Preview.kt drawMark), and the pin's ground.
pub let page_mark_color : Int64 = 0xEF6A3CFFL

///|
pub let page_mark_halo : Int64 = 0xFFFFFFFFL

///|
/// A box of the page's viewport, as the page says it ({x, y, width, height}).
pub fn css_box(v : Json?) -> (Double, Double, Double, Double)? {
  match (field(v, "x"), field(v, "y"), field(v, "width"), field(v, "height")) {
    (Some(Number(x, ..)), Some(Number(y, ..)), Some(Number(w, ..)), Some(Number(h, ..))) => Some((x, y, w, h))
    _ => None
  }
}

///|
/// What the page's marking says (page.js `marked`; any script of the page may say it: what does not read is let go).
pub fn service_marked(p : ServicePage, said : Json) -> Unit {
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
pub fn page_marks_new_page(p : ServicePage, site : @ui.NativeView) -> Unit {
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
pub fn page_marks_leave(p : ServicePage, site : @ui.NativeView) -> Unit {
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
pub fn page_marks_toggle(p : ServicePage, site : @ui.NativeView) -> Unit {
  p.marks.marking = !p.marks.marking
  page_say(p, "window.__stillfailMarks&&__stillfailMarks.on(\{p.marks.marking})")
}

///|
/// One mark gone (its note's remove key).
pub fn page_marks_remove(p : ServicePage, site : @ui.NativeView, n : Int) -> Unit {
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
pub fn shot_ask(k : Int, t : String, expr : String, drawn? : Bool = false) -> String {
  let say = "mbuiHost.post(JSON.stringify({p:\"shot\",k:\{k},t:\"\{t}\",v:\{expr}}))"
  if drawn {
    "requestAnimationFrame(()=>requestAnimationFrame(()=>" + say + "))"
  } else {
    say
  }
}

///|
/// The marks put into the chat's draft (Preview.kt putIntoChat): begun here, each step as the page answers.
pub fn page_marks_put(p : ServicePage, site : @ui.NativeView, src : Source) -> Unit {
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
pub fn shot_failed(p : ServicePage, words : String) -> Unit {
  p.marks.shot = None
  p.marks.error = svc("android-chat.preview.put.failed", args=[("error", words)])
}

///|
/// The next mark's place asked, or all of them done.
pub fn shot_next(p : ServicePage, site : @ui.NativeView) -> Unit {
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
pub fn shot_said(p : ServicePage, site : @ui.NativeView, said : Json) -> Unit {
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
pub fn page_marks_frame(p : ServicePage, site : @ui.NativeView) -> Unit {
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
pub fn shot_draw(p : ServicePage, s : Shooting, png : Bytes) -> Unit {
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
pub fn png_size(b : Bytes) -> (Int, Int)? {
  match @pixels.image_size(b) {
    Some((w, h)) if @pixels.is_png(b) && w > 0 && h > 0 => Some((w, h))
    _ => None
  }
}

///|
/// All the marks drawn: their pictures and quotes into the chat's draft, said so, marking left.
pub fn shot_done(p : ServicePage, site : @ui.NativeView, s : Shooting) -> Unit {
  let key = p.station + ":" + p.session
  let list = marked_into.get(key).unwrap_or([])
  for x in s.pictures {
    list.push((x.0, x.1, [x.2], "page"))
  }
  marked_into[key] = list
  draft_given()
  p.marks.shot = None
  page_marks_leave(p, site)
  toast_later(svc("android-chat.preview.put.done"))
}

///|
/// Where a mark is, as the agent reads it with its screenshot `shot` (Preview.kt where): the first line is also what
/// the composer shows.
pub fn mark_where(m : PageMark, shot : String) -> String {
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
/// Marked images waiting for their chat's composer: by its draft's key, the file and the quotes (title, what, comment),
/// whose they are ("image": an image's marks; "page": a service's page's, each quote with its screenshot's name).
pub let marked_into : Map[String, Array[(String, Bytes, Array[(String, String, String)], String)]] = Map([])

///|
/// The time of day as HHmmss (what a marked image's name carries; UTC: the hosts tell no time zone yet).
pub fn clock_stamp(ms : Double) -> String {
  let s = (ms / 1000.0).to_int64()
  let day = ((s % 86400L) + 86400L) % 86400L
  let two = fn(n : Int64) { if n < 10L { "0\{n}" } else { "\{n}" } }
  two(day / 3600L) + two(day % 3600L / 60L) + two(day % 60L)
}

///|
/// The source's clock, for what the viewer names by the time (set each frame).
pub let src_now : Ref[() -> Double] = { val: fn() { 0.0 } }

