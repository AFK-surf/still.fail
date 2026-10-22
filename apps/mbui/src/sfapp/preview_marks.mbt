// Marking an image opened in the viewer (ember apps/android chat/screens/ImageMarks.kt; web/src/annotate/ImageMarks.tsx):
// boxes, arrows, lines drawn by hand and words, drawn on the image where it is shown (zoomed and panned with it); a
// mark picked again to move, stretch, recolour or remove; undo and redo. Boxes and arrows are numbered: a pin on each,
// and something said about it in a note. Done, the image with its marks (and their pins), drawn again at its own size
// by the host (@ui.draw_marks), goes into the chat's draft as a new file with a quote per numbered mark, or is kept
// with the downloads.
//
// On the screen the marks are boxes of mbui's: a box is a bordered box, a line or an arrow a row of dots its width
// apart a half, words their text with their halo's copies round it; drawn at the image's zoom, so they look the same
// whatever it is.

///|
/// The tools (ImageMarks.kt MarkTool).
priv enum MarkTool {
  Select
  Rect
  Arrow
  Pen
  Words
} derive(Eq)

///|
/// still.fail's accent, what is drawn by default; the colours to draw in, each with the halo that edges its words.
// kept across runs: a table, never written
let mark_colors : Array[(Int64, Int64)] = [
  (0xE5704AFFL, 0xFFFFFFFFL),
  (0xE5484DFFL, 0xFFFFFFFFL),
  (0xF5C518FFL, 0x111111FFL),
  (0x30A46CFFL, 0xFFFFFFFFL),
  (0x3E7BFAFFL, 0xFFFFFFFFL),
  (0xFFFFFFFFL, 0x111111FFL),
  (0x111111FFL, 0xFFFFFFFFL),
]

///|
fn halo_of(color : Int64) -> Int64 {
  for c in mark_colors {
    if c.0 == color {
      return c.1
    }
  }
  0xFFFFFFFFL
}

///|
/// On the screen whatever the zoom: a line's width, words' size, how near a finger picks a mark.
let mark_line : Double = 3.0

///|
let mark_text : Double = 18.0

///|
let mark_reach : Double = 12.0

///|
/// A mark, in the image's own pixels (as shown: the zoom's natural size). `w`: its line (words' size), set by the zoom
/// as it is drawn, so it looks the same on the screen. `pts`: a box's corners, an arrow's tail and point, a line's
/// points, words' top left.
priv struct Mark {
  id : Int
  kind : String
  color : Int64
  w : Double
  pts : Array[Double]
  text : String
}

///|
fn Mark::numbered(self : Mark) -> Bool {
  self.kind == "box" || self.kind == "arrow"
}

///|
/// Its box (x, y, w, h).
fn Mark::bounds(self : Mark) -> (Double, Double, Double, Double) {
  if self.kind == "words" {
    (self.pts[0], self.pts[1], self.w * 0.62 * self.text.length().to_double(), self.w * 1.3)
  } else {
    let mut x0 = 1.0e18
    let mut y0 = 1.0e18
    let mut x1 = -1.0e18
    let mut y1 = -1.0e18
    let n = self.pts.length() / 2
    for i in 0..<n {
      x0 = dmin(x0, self.pts[2 * i])
      x1 = dmax(x1, self.pts[2 * i])
      y0 = dmin(y0, self.pts[2 * i + 1])
      y1 = dmax(y1, self.pts[2 * i + 1])
    }
    (x0, y0, x1 - x0, y1 - y0)
  }
}

///|
fn Mark::moved(self : Mark, dx : Double, dy : Double) -> Mark {
  { ..self, pts: self.pts.mapi(fn(i, v) { if i % 2 == 0 { v + dx } else { v + dy } }) }
}

///|
/// An arrow's barbs (ImageMarks.kt barbs): back from its point, a half its size apart.
fn arrow_barbs(ax : Double, ay : Double, bx : Double, by : Double, w : Double) -> (Double, Double, Double, Double) {
  let dx = bx - ax
  let dy = by - ay
  let len = dmax(1.0e-6, (dx * dx + dy * dy).sqrt())
  let ux = dx / len
  let uy = dy / len
  let size = dmin(w * 5.0, len * 0.6)
  let bkx = bx - ux * size
  let bky = by - uy * size
  (bkx - uy * size * 0.5, bky + ux * size * 0.5, bkx + uy * size * 0.5, bky - ux * size * 0.5)
}

///|
fn seg_distance(px : Double, py : Double, ax : Double, ay : Double, bx : Double, by : Double) -> Double {
  let dx = bx - ax
  let dy = by - ay
  let l2 = dx * dx + dy * dy
  let t = if l2 == 0.0 { 0.0 } else { dmax(0.0, dmin(1.0, ((px - ax) * dx + (py - ay) * dy) / l2)) }
  let qx = ax + t * dx - px
  let qy = ay + t * dy - py
  (qx * qx + qy * qy).sqrt()
}

///|
/// How far (x, y) is from the mark's line (words: 0 inside their box).
fn Mark::distance(self : Mark, x : Double, y : Double) -> Double {
  let p = self.pts
  match self.kind {
    "words" => {
      let (bx, by, bw, bh) = self.bounds()
      if x >= bx && x <= bx + bw && y >= by && y <= by + bh {
        0.0
      } else {
        1.0e18
      }
    }
    "arrow" => {
      let (lx, ly, rx, ry) = arrow_barbs(p[0], p[1], p[2], p[3], self.w)
      dmin(
        seg_distance(x, y, p[0], p[1], p[2], p[3]),
        dmin(seg_distance(x, y, lx, ly, p[2], p[3]), seg_distance(x, y, rx, ry, p[2], p[3])),
      )
    }
    "box" => {
      let (bx, by, bw, bh) = self.bounds()
      dmin(
        dmin(seg_distance(x, y, bx, by, bx + bw, by), seg_distance(x, y, bx + bw, by, bx + bw, by + bh)),
        dmin(seg_distance(x, y, bx + bw, by + bh, bx, by + bh), seg_distance(x, y, bx, by + bh, bx, by)),
      )
    }
    _ => {
      let n = p.length() / 2
      let mut d = 1.0e18
      if n == 1 {
        d = ((x - p[0]) * (x - p[0]) + (y - p[1]) * (y - p[1])).sqrt()
      }
      for i in 0..<(n - 1) {
        d = dmin(d, seg_distance(x, y, p[2 * i], p[2 * i + 1], p[2 * i + 2], p[2 * i + 3]))
      }
      d
    }
  }
}

///|
/// A finger on the image while marking: drawing a mark, or moving the one picked (its tail or point when an arrow's end
/// was taken: `end` 0 the tail, 1 the point; -1 the whole), from where (in the image's pixels).
priv enum MarkDrag {
  Drawing(Mark)
  Moving(Int, Double, Double, Mark, Int, Array[Mark], Bool)
}

///|
/// Marking, while the viewer marks one image.
priv struct Marking {
  mut on : Bool
  mut tool : MarkTool
  mut color : Int64
  mut palette : Bool
  mut shapes : Array[Mark]
  mut past : Array[Array[Mark]]
  mut future : Array[Array[Mark]]
  mut picked : Int
  mut drag : MarkDrag?
  /// words being written: their id (-1 new), where (image px), size, colour
  mut writing : (Int, Double, Double, Double, Int64)?
  /// what is said of each numbered mark (by its id), and the one whose note is open (-1 none)
  comments : Map[Int, String]
  mut note : Int
  mut busy : Bool
  mut error : String
  mut next_id : Int
  /// the marked image being drawn by the host, and whether it goes into the draft (else downloaded)
  mut job : @ui.MarkedImage?
  mut to_draft : Bool
  mut job_name : String
  /// the words being written and the open note's (their fields show them)
  write_field : @ui.Field
  note_field : @ui.Field
}

///|
let marking : Marking = {
  on: false,
  tool: Rect,
  color: 0xE5704AFFL,
  palette: false,
  shapes: [],
  past: [],
  future: [],
  picked: -1,
  drag: None,
  writing: None,
  comments: Map([]),
  note: -1,
  busy: false,
  error: "",
  next_id: 1,
  job: None,
  to_draft: false,
  job_name: "",
  write_field: @ui.Field::new(),
  note_field: @ui.Field::new(),
}

///|
fn marks_start() -> Unit {
  marks_leave()
  marking.on = true
}

///|
fn marks_leave() -> Unit {
  marking.on = false
  marking.tool = Rect
  marking.palette = false
  marking.shapes = []
  marking.past = []
  marking.future = []
  marking.picked = -1
  marking.drag = None
  marking.writing = None
  marking.comments.clear()
  marking.note = -1
  marking.busy = false
  marking.error = ""
  marking.job = None
}

///|
fn marks_commit(next : Array[Mark], before? : Array[Mark]) -> Unit {
  marking.past.push(before.unwrap_or(marking.shapes))
  marking.future = []
  marking.shapes = next
}

///|
fn marks_undo() -> Unit {
  match marking.past.pop() {
    Some(p) => {
      marking.future.insert(0, marking.shapes)
      marking.shapes = p
    }
    None => ()
  }
  marking.picked = -1
  marking.note = -1
}

///|
fn marks_redo() -> Unit {
  if marking.future.length() > 0 {
    let f = marking.future.remove(0)
    marking.past.push(marking.shapes)
    marking.shapes = f
  }
  marking.picked = -1
  marking.note = -1
}

///|
fn marks_remove(id : Int) -> Unit {
  marks_commit(marking.shapes.filter(fn(s) { s.id != id }))
  marking.picked = -1
  marking.note = -1
}

///|
/// The words being written, put down (all of them gone: the words they were, removed).
fn marks_put_down(c : @ui.Ctx) -> Unit {
  let (id, x, y, w, color) = match marking.writing {
    Some(x) => x
    None => return
  }
  let text = marking.write_field.text().trim(chars=" \n\t").to_string()
  marking.writing = None
  c.blur()
  if id >= 0 {
    match marking.shapes.iter().find_first(fn(s) { s.id == id }) {
      Some(was) =>
        if was.text != text || was.color != color {
          marks_commit(
            if text != "" {
              marking.shapes.map(fn(s) { if s.id == id { { ..s, text, color } } else { s } })
            } else {
              marking.shapes.filter(fn(s) { s.id != id })
            },
          )
        }
      None => ()
    }
  } else if text != "" {
    let m : Mark = { id: marking.next_id, kind: "words", color, w, pts: [x, y], text }
    marking.next_id += 1
    marks_commit(marking.shapes + [m])
  }
}

///|
/// The numbered marks' numbers, in the order they were drawn.
fn mark_numbers(shapes : Array[Mark]) -> Map[Int, Int] {
  let out : Map[Int, Int] = Map([])
  for s in shapes {
    if s.numbered() {
      out[s.id] = out.length() + 1
    }
  }
  out
}

///|
/// What is drawn now: the marks and the one being drawn, not the words being written again.
fn marks_drawn() -> Array[Mark] {
  let list = match marking.drag {
    Some(Drawing(m)) => marking.shapes + [m]
    _ => marking.shapes
  }
  match marking.writing {
    Some((id, _, _, _, _)) => list.filter(fn(s) { s.id != id })
    None => list
  }
}

///|
/// A finger on the image while marking (ImageMarks.kt down, move, up): `px`, `py` on the stage, `r` the picture's
/// place (x, y, w, h) on it, `nw` its natural width; what `phase` is: 0 down, 1 moved, 2 up.
fn marks_finger(c : @ui.Ctx, phase : Int, px : Double, py : Double, r : (Double, Double, Double, Double), nw : Double) -> Unit {
  let (rx, ry, rw, _) = r
  let k = rw / dmax(1.0, nw)
  let x = (px - rx) / k
  let y = (py - ry) / k
  match phase {
    0 => {
      marking.palette = false
      if marking.writing is Some(_) {
        marks_put_down(c)
        return
      }
      if marking.note >= 0 {
        marking.note = -1
        return
      }
      let reach = mark_reach / k
      if marking.tool == Select || marking.tool == Words {
        let hit = marking.shapes
          .rev()
          .iter()
          .find_first(fn(s) {
            (marking.tool == Select || s.kind == "words") && s.distance(x, y) <= s.w / 2.0 + reach
          })
        match hit {
          Some(s) => {
            // an arrow's end near the finger: that end moves; words with the words tool: written again
            if s.kind == "words" && marking.tool == Words {
              marking.writing = Some((s.id, s.pts[0], s.pts[1], s.w, s.color))
              marking.write_field.set(s.text)
              c.focus_editor("marks/write")
              return
            }
            let mut end = -1
            if s.kind == "arrow" && marking.picked == s.id {
              for e in 0..<2 {
                let ex = s.pts[2 * e]
                let ey = s.pts[2 * e + 1]
                if ((ex - x) * (ex - x) + (ey - y) * (ey - y)).sqrt() < reach * 1.4 {
                  end = e
                }
              }
            }
            marking.picked = s.id
            marking.drag = Some(Moving(s.id, x, y, s, end, marking.shapes, false))
          }
          None =>
            if marking.tool == Select {
              marking.picked = -1
            } else {
              let w = mark_text / k
              marking.writing = Some((-1, x, y - w * 0.65, w, marking.color))
              marking.write_field.set("")
              c.focus_editor("marks/write")
            }
        }
        return
      }
      let w = mark_line / k
      let m : Mark = {
        id: marking.next_id,
        kind: match marking.tool {
          Pen => "pen"
          Arrow => "arrow"
          _ => "box"
        },
        color: marking.color,
        w,
        pts: if marking.tool == Pen { [x, y] } else { [x, y, x, y] },
        text: "",
      }
      marking.next_id += 1
      marking.drag = Some(Drawing(m))
    }
    1 =>
      match marking.drag {
        Some(Drawing(m)) =>
          marking.drag = Some(
            Drawing(
              if m.kind == "pen" {
                { ..m, pts: m.pts + [x, y] }
              } else {
                { ..m, pts: [m.pts[0], m.pts[1], x, y] }
              },
            ),
          )
        Some(Moving(id, fx, fy, orig, end, before, _)) => {
          let next = if end >= 0 {
            let pts = orig.pts.copy()
            pts[2 * end] = x
            pts[2 * end + 1] = y
            { ..orig, pts, }
          } else {
            orig.moved(x - fx, y - fy)
          }
          marking.shapes = marking.shapes.map(fn(s) { if s.id == id { next } else { s } })
          marking.drag = Some(Moving(id, fx, fy, orig, end, before, true))
        }
        None => ()
      }
    _ =>
      match marking.drag {
        Some(Drawing(m)) => {
          marking.drag = None
          // a tap, not a drag: nothing drawn
          let mut far = false
          let n = m.pts.length() / 2
          for i in 1..<n {
            let dx = m.pts[2 * i] - m.pts[0]
            let dy = m.pts[2 * i + 1] - m.pts[1]
            if (dx * dx + dy * dy).sqrt() > 4.0 / k {
              far = true
            }
          }
          if far {
            marks_commit(marking.shapes + [m])
            // a box or an arrow drawn: what to say about it, at once
            if m.numbered() {
              marking.note = m.id
              marking.note_field.set("")
              c.focus_editor("marks/note")
            }
          }
        }
        Some(Moving(_, _, _, _, _, before, changed)) => {
          marking.drag = None
          if changed {
            marking.past.push(before)
            marking.future = []
          }
        }
        None => ()
      }
  }
}

///|
/// The marks drawn over the picture at (x, y, w, h) on the stage (`nw` its natural width), with their pins.
fn marks_draw(c : @ui.Ctx, r : (Double, Double, Double, Double), nw : Double, nh : Double) -> Unit {
  let (rx, ry, rw, _) = r
  let k = rw / dmax(1.0, nw)
  let numbers = mark_numbers(marking.shapes)
  c.layer(fn() {
    for m in marks_drawn() {
      let lw = dmax(1.0, m.w * k)
      let at = fn(i : Int) -> (Double, Double) { (rx + m.pts[2 * i] * k, ry + m.pts[2 * i + 1] * k) }
      match m.kind {
        "box" => {
          let (bx, by, bw, bh) = m.bounds()
          c.box(
            w=Px(bw * k + lw),
            h=Px(bh * k + lw),
            tx=rx + bx * k - lw / 2.0,
            ty=ry + by * k - lw / 2.0,
            radius=dmin(lw * 1.5 + lw / 2.0, dmin(bw * k, bh * k) / 2.0 + lw / 2.0),
            border=lw,
            border_color=m.color,
            fn() {  },
          )
          |> ignore
        }
        "words" => {
          let (x, y) = at(0)
          let size = m.w * k
          let halo = halo_of(m.color)
          let e = size * 0.08
          for o in [(-e, 0.0), (e, 0.0), (0.0, -e), (0.0, e), (-e, -e), (e, e), (-e, e), (e, -e)] {
            c.box(tx=x + o.0, ty=y + o.1, fn() {
              c.text(m.text, size~, weight=600, color=halo, wrap=false, line=size * 1.3) |> ignore
            })
            |> ignore
          }
          c.box(tx=x, ty=y, fn() {
            c.text(m.text, size~, weight=600, color=m.color, wrap=false, line=size * 1.3) |> ignore
          })
          |> ignore
        }
        _ => {
          // a line drawn by hand, or an arrow and its barbs: dots along each stretch
          let segs : Array[(Double, Double, Double, Double)] = []
          if m.kind == "arrow" {
            let (ax, ay) = at(0)
            let (bx, by) = at(1)
            let (lx, ly, qx, qy) = arrow_barbs(ax, ay, bx, by, lw)
            segs.push((ax, ay, bx, by))
            segs.push((lx, ly, bx, by))
            segs.push((qx, qy, bx, by))
          } else {
            let n = m.pts.length() / 2
            if n == 1 {
              let (x, y) = at(0)
              segs.push((x, y, x, y))
            }
            for i in 0..<(n - 1) {
              let (x0, y0) = at(i)
              let (x1, y1) = at(i + 1)
              segs.push((x0, y0, x1, y1))
            }
          }
          for sg in segs {
            let (x0, y0, x1, y1) = sg
            let len = ((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)).sqrt()
            let steps = dmax(1.0, (len / dmax(0.75, lw * 0.35)).ceil()).to_int()
            for j in 0..=steps {
              let t = j.to_double() / steps.to_double()
              c.box(
                w=Px(lw),
                h=Px(lw),
                tx=x0 + (x1 - x0) * t - lw / 2.0,
                ty=y0 + (y1 - y0) * t - lw / 2.0,
                radius=lw / 2.0,
                bg=m.color,
                fn() {  },
              )
              |> ignore
            }
          }
        }
      }
    }
    // the picked mark's frame and its arrow's ends
    match marking.shapes.iter().find_first(fn(s) { s.id == marking.picked && marking.tool == Select }) {
      Some(s) => {
        let (bx, by, bw, bh) = s.bounds()
        let pad = mark_reach / 2.0
        if s.kind != "arrow" {
          c.box(
            w=Px(bw * k + 2.0 * pad),
            h=Px(bh * k + 2.0 * pad),
            tx=rx + bx * k - pad,
            ty=ry + by * k - pad,
            border=1.0,
            border_color=0xFFFFFFD9L,
            fn() {  },
          )
          |> ignore
        } else {
          for e in 0..<2 {
            c.box(
              w=Px(12.0),
              h=Px(12.0),
              tx=rx + s.pts[2 * e] * k - 6.0,
              ty=ry + s.pts[2 * e + 1] * k - 6.0,
              radius=6.0,
              bg=0xFFFFFFFFL,
              border=1.5,
              border_color=0xE5704AFFL,
              fn() {  },
            )
            |> ignore
          }
        }
      }
      None => ()
    }
    // the numbered marks' pins, each at its own size whatever the zoom; tapped, its note
    for s in marking.shapes {
      match numbers.get(s.id) {
        Some(n) => {
          let (px0, py0) = if s.kind == "box" {
            let (bx, by, _, _) = s.bounds()
            (bx, by)
          } else {
            (s.pts[0], s.pts[1])
          }
          let px = dmax(2.0 / k, dmin(dmax(2.0 / k, nw - 22.0 / k), px0))
          let py = dmax(22.0 / k, dmin(dmax(22.0 / k, nh - 2.0 / k), py0))
          let id = c.id("marks/pin/\{s.id}")
          if c.clicked(id) {
            marks_put_down(c)
            marking.picked = -1
            marking.note = if marking.note == s.id { -1 } else { s.id }
            if marking.note >= 0 {
              marking.note_field.set(marking.comments.get(s.id).unwrap_or(""))
              c.focus_editor("marks/note")
            }
          }
          let halo = halo_of(s.color)
          c.box(
            w=Px(24.0),
            h=Px(24.0),
            tx=rx + px * k - 2.0,
            ty=ry + py * k - 22.0,
            radius=12.0,
            bg=halo,
            pad=2.0,
            shadow=3.0,
            id~,
            fn() {
              c.box(w=Fill(1.0), h=Fill(1.0), radius=10.0, bg=s.color, align=ACenter, justify=JCenter, fn() {
                c.text("\{n}", size=11.0, weight=700, color=halo, wrap=false) |> ignore
              })
              |> ignore
            },
          )
          |> ignore
        }
        None => ()
      }
    }
    // the words being written, where they go, in their size and colour
    match marking.writing {
      Some((_, x, y, w, color)) => {
        let size = w * k
        c.box(tx=rx + x * k, ty=ry + y * k, w=Px(dmax(size * 6.0, 120.0)), fn() {
          let e = c.editor(
            "marks/write",
            placeholder=pv("android-chat.marks.write"),
            font_size=size,
            max_lines=1,
            plain=true,
            color~,
            placeholder_color=@sf.alpha(color, 0.55),
            caret_color=color,
            field=marking.write_field,
          )
          match e.submitted {
            Some(_) => marks_put_down(c)
            None => ()
          }
        })
        |> ignore
      }
      None => ()
    }
  })
  |> ignore
}

///|
/// The words the marked image's quotes say (ImageMarks.kt quotes): a quote per numbered mark, where it is (for the
/// agent), on which image, what was said of it.
fn marks_quotes(made : String, original : String, nw : Double, nh : Double) -> Array[(String, String, String)] {
  let numbers = mark_numbers(marking.shapes)
  let out = []
  for s in marking.shapes {
    match numbers.get(s.id) {
      Some(n) => {
        let r = fn(v : Double) { "\{v.round().to_int()}" }
        let what = if s.kind == "box" {
          let (x, y, w, h) = s.bounds()
          pv_fill("android-chat.marks.box.where", [("x", r(x)), ("y", r(y)), ("w", r(w)), ("h", r(h))])
        } else {
          pv_fill("android-chat.marks.arrow.where", [
            ("ax", r(s.pts[0])),
            ("ay", r(s.pts[1])),
            ("bx", r(s.pts[2])),
            ("by", r(s.pts[3])),
          ])
        }
        let on = pv_fill("android-chat.marks.quote.on", [
          ("made", made),
          ("width", r(nw)),
          ("height", r(nh)),
          ("original", original),
          ("n", "\{n}"),
        ])
        out.push(
          (
            pv_fill("android-chat.marks.quote.title", [("original", original), ("n", "\{n}")]),
            what + "\n" + on,
            marking.comments.get(s.id).unwrap_or("").trim(chars=" \n\t").to_string(),
          ),
        )
      }
      None => ()
    }
  }
  out
}

///|
/// The marks as the host draws them (marks.mbt's JSON), in the picture's size as shown.
fn marks_json(nw : Double, nh : Double) -> String {
  let numbers = mark_numbers(marking.shapes)
  let list = marking.shapes.map(fn(s) {
    Json::object({
      "kind": Json::string(s.kind),
      "color": Json::number(s.color.to_double()),
      "halo": Json::number(halo_of(s.color).to_double()),
      "w": Json::number(s.w),
      "pts": Json::array(s.pts.map(fn(v) { Json::number(v) })),
      "text": Json::string(s.text),
      "n": Json::number(numbers.get(s.id).unwrap_or(0).to_double()),
    })
  })
  Json::object({ "w": Json::number(nw), "h": Json::number(nh), "marks": Json::array(list) }).stringify()
}

///|
/// Marked images waiting for their chat's composer: by its draft's key, the file and the quotes (title, what, comment),
/// whose they are ("image": an image's marks; "page": a service's page's, each quote with its screenshot's name).
let marked_into : Map[String, Array[(String, Bytes, Array[(String, String, String)], String)]] = Map([])

///|
/// Back while marking (ImageMarks.kt back): closes a note, puts down the words being written, closes the colours,
/// lets go of the picked mark, else stops marking.
fn marks_back(c : @ui.Ctx) -> Unit {
  if marking.note >= 0 {
    marks_note_done(c)
  } else if marking.writing is Some(_) {
    marks_put_down(c)
  } else if marking.palette {
    marking.palette = false
  } else if marking.picked >= 0 {
    marking.picked = -1
  } else {
    marks_leave()
  }
}

///|
fn marks_note_done(c : @ui.Ctx) -> Unit {
  if marking.note >= 0 {
    marking.comments[marking.note] = marking.note_field.text()
  }
  marking.note = -1
  c.blur()
}

///|
/// Something drawn (or being written) to be kept.
fn marks_any() -> Bool {
  marking.shapes.length() > 0 || (marking.writing is Some(_) && marking.write_field.text().trim(chars=" \n\t") != "")
}

///|
/// In the top bar while marking (ImageMarks.kt MarksActions): why it failed, 取消, 下载标注后的图片, 添加到对话 (when
/// there is a chat's draft to put it in). True on the frame one of them is tapped: `go(draft)`.
fn marks_actions(c : @ui.Ctx, can_draft : Bool, go : (Bool) -> Unit) -> Unit {
  let ready = !marking.busy && marks_any()
  // as wide as they are: the file's name before them cut short instead
  c.box(dir=Row, gap=4.0, align=ACenter, keep=true, fn() {
    if marking.error != "" {
      c.box(padx=6.0, max_w=140.0, clip=true, fn() {
        c.text(marking.error, size=13.0, color=0xFF7B6BFFL, wrap=false) |> ignore
      })
      |> ignore
    }
    let cancel = c.id("marks/cancel")
    if c.clicked(cancel) {
      marks_leave()
    }
    c.box(h=Px(32.0), padx=10.0, radius=picture_key, justify=JCenter, id=cancel, fn() {
      c.text(pv("common.cancel"), size=13.0, color=dark_muted, wrap=false) |> ignore
    })
    |> ignore
    if picture_button(c, "marks/download", "download", dark_muted, true, enabled=ready) {
      go(false)
    }
    if can_draft {
      let put = c.id("marks/put")
      if ready && c.clicked(put) {
        go(true)
      }
      // 4 further from the rest (ImageMarks.kt: padding(start = 4) outside its ground)
      c.box(style=marks_put_room, fn() {
        c.box(
          dir=Row,
          h=Px(32.0),
          padx=12.0,
          gap=5.0,
          radius=picture_key,
          bg=0xE5704AFFL,
          align=ACenter,
          opacity=if ready { 1.0 } else { 0.4 },
          id=if ready { put } else { 0 },
          fn() {
            @sf.icon(c, "send", size=12.0, color=0xFFFFFFFFL) |> ignore
            c.text(
              pv(if marking.busy { "android-chat.marks.making" } else { "android-chat.preview.put" }),
              size=13.0,
              weight=600,
              color=0xFFFFFFFFL,
              wrap=false,
            )
            |> ignore
          },
        )
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The corner of what is on the viewer's bars (ImageMarks.kt PICTURE_KEY).
let picture_key : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let marks_put_room : @ui.Style = @ui.style(pl=S1)

///|
/// The foot while marking (ImageMarks.kt MarksFoot, MarksTools): the note being written in its box, else the notes as
/// cards (a tap opens one again) over the tools (选择, 框, 箭头, 画笔, 文字 · the colour · 删除 the picked · 撤销, 重做),
/// the colours in a row over them when asked for; on the viewer's dark glass.
fn marks_foot(c : @ui.Ctx) -> Unit {
  let glass = solid_glass()
  c.box(w=Fill(1.0), pb=8.0, gap=10.0, align=ACenter, fn() {
    if marking.note >= 0 {
      let numbers = mark_numbers(marking.shapes)
      let kind = match marking.shapes.iter().find_first(fn(s) { s.id == marking.note }) {
        Some(s) => s.kind
        None => ""
      }
      c.box(w=Fill(1.0), padx=12.0, fn() {
        c.box(w=Fill(1.0), pad=14.0, gap=10.0, radius=16.0, bg=glass, fn() {
          c.text(
            "\{numbers.get(marking.note).unwrap_or(0)} · " +
            pv(if kind == "box" { "android-chat.marks.note.box" } else { "android-chat.marks.note.arrow" }),
            size=13.0,
            weight=600,
            color=dark_text,
            wrap=false,
          )
          |> ignore
          c.editor(
            "marks/note",
            font_size=15.0,
            max_lines=4,
            color=dark_text,
            placeholder_color=dark_muted,
            caret_color=0xE5704AFFL,
            enter_sends=false,
            field=marking.note_field,
          )
          |> ignore
          c.box(dir=Row, w=Fill(1.0), gap=8.0, justify=JEnd, fn() {
            let remove = c.id("marks/note-remove")
            if c.clicked(remove) {
              let id = marking.note
              marking.note = -1
              marks_remove(id)
              c.blur()
            }
            c.box(h=Px(30.0), padx=12.0, radius=15.0, justify=JCenter, id=remove, fn() {
              c.text(pv("common.delete"), size=13.0, color=0xFF7B6BFFL, wrap=false) |> ignore
            })
            |> ignore
            let done = c.id("marks/note-done")
            if c.clicked(done) {
              marks_note_done(c)
            }
            c.box(h=Px(30.0), padx=12.0, radius=15.0, bg=0xE5704AFFL, justify=JCenter, id=done, fn() {
              c.text(pv("common.done"), size=13.0, weight=600, color=0xFFFFFFFFL, wrap=false) |> ignore
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
      return
    }
    // the notes said so far, a card each
    let numbers = mark_numbers(marking.shapes)
    if numbers.length() > 0 {
      // scrolled across when they do not fit (ImageMarks.kt: horizontalScroll)
      c.sideways("marks/notes", padx=16.0, fn() {
        c.box(dir=Row, gap=8.0, fn() {
          for s in marking.shapes {
            match numbers.get(s.id) {
              Some(n) => {
                let id = c.id("marks/card/\{s.id}")
                if c.clicked(id) {
                  marks_put_down(c)
                  marking.note = s.id
                  marking.note_field.set(marking.comments.get(s.id).unwrap_or(""))
                  c.focus_editor("marks/note")
                }
                let said = marking.comments.get(s.id).unwrap_or("")
                c.box(dir=Row, max_w=200.0, padx=10.0, pady=8.0, gap=8.0, radius=14.0, bg=glass, align=ACenter, id~, fn() {
                  c.box(w=Px(18.0), h=Px(18.0), radius=9.0, bg=s.color, align=ACenter, justify=JCenter, fn() {
                    c.text("\{n}", size=10.0, weight=700, color=halo_of(s.color), wrap=false) |> ignore
                  })
                  |> ignore
                  c.text(
                    if said != "" {
                      said
                    } else {
                      pv(if s.kind == "box" { "android-chat.marks.note.box" } else { "android-chat.marks.note.arrow" })
                    },
                    size=13.0,
                    color=if said != "" { dark_text } else { dark_muted },
                    wrap=false,
                  )
                  |> ignore
                })
                |> ignore
              }
              None => ()
            }
          }
        })
        |> ignore
      })
      |> ignore
    }
    if marking.palette {
      c.box(dir=Row, pad=4.0, gap=2.0, radius=20.0, bg=glass, fn() {
        for col in mark_colors {
          let id = c.id("marks/color/\{col.0}")
          if c.clicked(id) {
            marks_pick_color(col.0)
          }
          c.box(
            w=Px(32.0),
            h=Px(32.0),
            radius=16.0,
            bg=if col.0 == marks_shown_color() { 0xFFFFFF29L } else { 0L },
            align=ACenter,
            justify=JCenter,
            id~,
            fn() { mark_swatch(c, col.0) },
          )
          |> ignore
        }
      })
      |> ignore
    }
    c.box(dir=Row, h=Px(44.0), padx=2.0, gap=2.0, radius=14.0, bg=glass, align=ACenter, fn() {
      for x in [(Select, "cursor"), (Rect, "square"), (Arrow, "arrow-up-right"), (Pen, "scribble"), (Words, "text")] {
        let (tool, icon) = x
        if picture_button(
            c,
            "marks/tool/" + icon,
            icon,
            if marking.tool == tool { dark_text } else { dark_muted },
            true,
          ) {
          marks_put_down(c)
          marking.note = -1
          marking.tool = tool
          if tool != Select {
            marking.picked = -1
          }
        }
      }
      mark_gap(c)
      let swatch = c.id("marks/palette")
      if c.clicked(swatch) {
        marking.palette = !marking.palette
      }
      c.box(w=Px(32.0), h=Px(32.0), radius=12.0, align=ACenter, justify=JCenter, id=swatch, fn() {
        mark_swatch(c, marks_shown_color())
      })
      |> ignore
      if marking.picked >= 0 && picture_button(c, "marks/remove", "trash", dark_muted, true) {
        marks_remove(marking.picked)
      }
      mark_gap(c)
      if picture_button(c, "marks/undo", "retry", dark_muted, true, enabled=marking.past.length() > 0) {
        marks_undo()
      }
      if picture_button(c, "marks/redo", "redo", dark_muted, true, enabled=marking.future.length() > 0) {
        marks_redo()
      }
    })
    |> ignore
  })
  |> ignore
}

///|
fn mark_gap(c : @ui.Ctx) -> Unit {
  c.box(w=Px(1.0), h=Px(18.0), bg=0xFFFFFF1AL, fn() {  }) |> ignore
  c.box(w=Px(6.0), fn() {  }) |> ignore
}

///|
/// A colour's swatch: a disc of it, ringed in white.
fn mark_swatch(c : @ui.Ctx, color : Int64) -> Unit {
  c.box(w=Px(18.0), h=Px(18.0), radius=9.0, bg=color, border=2.0, border_color=0xFFFFFFE6L, fn() {  }) |> ignore
}

///|
/// The colour shown: the words being written's, the picked mark's, else the one to draw in.
fn marks_shown_color() -> Int64 {
  match marking.writing {
    Some((_, _, _, _, col)) => col
    None =>
      match marking.shapes.iter().find_first(fn(s) { s.id == marking.picked }) {
        Some(s) => s.color
        None => marking.color
      }
  }
}

///|
/// A colour to draw in next; the picked mark (or the words being written) takes it at once.
fn marks_pick_color(col : Int64) -> Unit {
  marking.color = col
  marking.palette = false
  match marking.writing {
    Some((id, x, y, w, _)) => marking.writing = Some((id, x, y, w, col))
    None =>
      if marking.picked >= 0 {
        let id = marking.picked
        marks_commit(marking.shapes.map(fn(s) { if s.id == id { { ..s, color: col } } else { s } }))
      }
  }
}
