// Marking an image opened in the viewer (ember apps/android chat/screens/ImageMarks.kt; web/src/annotate/ImageMarks.tsx):
// boxes, arrows, lines drawn by hand and words, drawn on the image where it is shown (zoomed and panned with it); a
// mark picked again to move, stretch, recolour or remove; undo and redo. Boxes and arrows are numbered: a pin on each,
// and something said about it in a note. Done, the image with its marks (and their pins), drawn again at its own size
// by the host (@ui.draw_marks), goes into the chat's draft as a new file with a quote per numbered mark, or is kept
// with the downloads.
//
// On the screen the marks are lines (Ctx::lines: a box's rounded edge, an arrow, a line drawn by hand), words their
// text with their halo's copies round it, each pin a box of its own; drawn at the image's zoom, so they look the same
// whatever it is.

///|
/// The tools (ImageMarks.kt MarkTool).
pub(all) enum MarkTool {
  Select
  Rect
  Arrow
  Pen
  Words
} derive(Eq)

///|
/// still.fail's accent, what is drawn by default; the colours to draw in, each with the halo that edges its words.
// kept across runs: a table, never written
pub let mark_colors : Array[(Int64, Int64)] = [
  (0xE5704AFFL, 0xFFFFFFFFL),
  (0xE5484DFFL, 0xFFFFFFFFL),
  (0xF5C518FFL, 0x111111FFL),
  (0x30A46CFFL, 0xFFFFFFFFL),
  (0x3E7BFAFFL, 0xFFFFFFFFL),
  (0xFFFFFFFFL, 0x111111FFL),
  (0x111111FFL, 0xFFFFFFFFL),
]

///|
pub fn halo_of(color : Int64) -> Int64 {
  for c in mark_colors {
    if c.0 == color {
      return c.1
    }
  }
  0xFFFFFFFFL
}

///|
/// On the screen whatever the zoom: a line's width, words' size, how near a finger picks a mark.
pub let mark_line : Double = 3.0

///|
pub let mark_text : Double = 18.0

///|
pub let mark_reach : Double = 12.0

///|
/// A mark, in the image's own pixels (as shown: the zoom's natural size). `w`: its line (words' size), set by the zoom
/// as it is drawn, so it looks the same on the screen. `pts`: a box's corners, an arrow's tail and point, a line's
/// points, words' top left.
pub(all) struct Mark {
  id : Int
  kind : String
  color : Int64
  w : Double
  pts : Array[Double]
  text : String
}

///|
pub fn Mark::numbered(self : Mark) -> Bool {
  self.kind == "box" || self.kind == "arrow"
}

///|
/// Its box (x, y, w, h).
pub fn Mark::bounds(self : Mark) -> (Double, Double, Double, Double) {
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
pub fn Mark::moved(self : Mark, dx : Double, dy : Double) -> Mark {
  { ..self, pts: self.pts.mapi(fn(i, v) { if i % 2 == 0 { v + dx } else { v + dy } }) }
}

///|
/// Stretched from `anchor` (ax, ay) by (`sx`, `sy`) (ImageMarks.kt scaled): words evenly, by `sx`, their size with
/// them.
pub fn Mark::scaled(self : Mark, ax : Double, ay : Double, sx : Double, sy : Double) -> Mark {
  if self.kind == "words" {
    let k = dmax(0.2, sx.abs())
    { ..self, w: self.w * k, pts: [ax + (self.pts[0] - ax) * k, ay + (self.pts[1] - ay) * k] }
  } else {
    { ..self, pts: self.pts.mapi(fn(i, v) { if i % 2 == 0 { ax + (v - ax) * sx } else { ay + (v - ay) * sy } }) }
  }
}

///|
/// A handle of the picked mark (ImageMarks.kt MarkHandle): a corner of its box (`Corner(1, 1)` its foot right; the
/// corner across stays), or an end of an arrow (0 its tail, 1 its point).
pub(all) enum MarkHandle {
  Corner(Int, Int)
  End(Int)
} derive(Eq)

///|
/// The picked mark's handles and where each is drawn, in the image's pixels at `k` stage points to one: an arrow's on
/// its ends; a box's (words': their foot right only) on the corners of its dashed frame, half a reach out of its own.
/// Where they are drawn is where a finger takes them.
pub fn Mark::handles(self : Mark, k : Double) -> Array[(MarkHandle, Double, Double)] {
  if self.kind == "arrow" {
    return [(End(0), self.pts[0], self.pts[1]), (End(1), self.pts[2], self.pts[3])]
  }
  let (bx, by, bw, bh) = self.bounds()
  let out = mark_reach / 2.0 / k
  let corners = if self.kind == "words" { [(1, 1)] } else { [(0, 0), (1, 0), (0, 1), (1, 1)] }
  corners.map(fn(cc) {
    let (cx, cy) = cc
    (
      Corner(cx, cy),
      if cx == 1 { bx + bw + out } else { bx - out },
      if cy == 1 { by + bh + out } else { by - out },
    )
  })
}

///|
/// The mark as its handle `h` (None: the whole of it) taken from `orig` is moved by (`dx`, `dy`): an arrow's end goes
/// with it; a corner too, the box stretched from the corner across.
pub fn Mark::dragged(self : Mark, h : MarkHandle?, dx : Double, dy : Double) -> Mark {
  match h {
    None => self.moved(dx, dy)
    Some(End(e)) => {
      let pts = self.pts.copy()
      pts[2 * e] += dx
      pts[2 * e + 1] += dy
      { ..self, pts, }
    }
    Some(Corner(cx, cy)) => {
      let (bx, by, bw, bh) = self.bounds()
      let ax = bx + (1 - cx).to_double() * bw
      let ay = by + (1 - cy).to_double() * bh
      let ratio = fn(d : Double, from : Double, a : Double) {
        if (from - a).abs() < 1.0e-6 {
          1.0
        } else {
          (from + d - a) / (from - a)
        }
      }
      self.scaled(ax, ay, ratio(dx, bx + cx.to_double() * bw, ax), ratio(dy, by + cy.to_double() * bh, ay))
    }
  }
}

///|
/// An arrow's barbs (ImageMarks.kt barbs): back from its point, a half its size apart.
pub fn arrow_barbs(ax : Double, ay : Double, bx : Double, by : Double, w : Double) -> (Double, Double, Double, Double) {
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
pub fn seg_distance(px : Double, py : Double, ax : Double, ay : Double, bx : Double, by : Double) -> Double {
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
pub fn Mark::distance(self : Mark, x : Double, y : Double) -> Double {
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
/// A finger on the image while marking: drawing a mark, or moving the one picked (by the handle taken, None the
/// whole), from where (in the image's pixels).
pub(all) enum MarkDrag {
  Drawing(Mark)
  Moving(Int, Double, Double, Mark, MarkHandle?, Array[Mark], Bool)
}

///|
/// Marking, while the viewer marks one image.
pub(all) struct Marking {
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
  /// the note whose box came in last (it pops in as it opens: Notes.kt pop), -1 none
  mut popped : Int
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
pub let marking : Marking = {
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
  popped: -1,
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
pub fn marks_start() -> Unit {
  marks_leave()
  marking.on = true
  marks_changed()
}

///|
/// Told as marking changes (each of the ways it is changed: a finger on the picture, the bar's tools and undo, a note,
/// leaving it): what draws the marks over the picture and the bars over it (each built on its own: viewer_tree.mbt)
/// follow it by reading it (marks_said).
// kept across runs: only a count
let marks_told : @signals.Signal[Int] = @signals.signal(0)

///|
/// Marking changed (marks_told).
pub fn marks_changed() -> Unit {
  marks_told.set(@signals.untracked(fn() { marks_told.get() }) + 1)
}

///|
/// Read where what is built follows marking (marks_told).
pub fn marks_said() -> Unit {
  marks_told.get() |> ignore
}

///|
pub fn marks_leave() -> Unit {
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
  marking.popped = -1
  marking.busy = false
  marking.error = ""
  marking.job = None
  marks_changed()
}

///|
pub fn marks_commit(next : Array[Mark], before? : Array[Mark]) -> Unit {
  marking.past.push(before.unwrap_or(marking.shapes))
  marking.future = []
  marking.shapes = next
  marks_changed()
}

///|
pub fn marks_undo() -> Unit {
  match marking.past.pop() {
    Some(p) => {
      marking.future.insert(0, marking.shapes)
      marking.shapes = p
    }
    None => ()
  }
  marking.picked = -1
  marking.note = -1
  marks_changed()
}

///|
pub fn marks_redo() -> Unit {
  if marking.future.length() > 0 {
    let f = marking.future.remove(0)
    marking.past.push(marking.shapes)
    marking.shapes = f
  }
  marking.picked = -1
  marking.note = -1
  marks_changed()
}

///|
pub fn marks_remove(id : Int) -> Unit {
  marks_commit(marking.shapes.filter(fn(s) { s.id != id }))
  marking.picked = -1
  marking.note = -1
  marks_changed()
}

///|
/// The words being written, put down (all of them gone: the words they were, removed).
pub fn marks_put_down(c : @ui.Ctx) -> Unit {
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
  // (told once all of it is so)
  marks_changed()
}

///|
/// The numbered marks' numbers, in the order they were drawn.
pub fn mark_numbers(shapes : Array[Mark]) -> Map[Int, Int] {
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
pub fn marks_drawn() -> Array[Mark] {
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
pub fn marks_finger(c : @ui.Ctx, phase : Int, px : Double, py : Double, r : (Double, Double, Double, Double), nw : Double) -> Unit {
  let (rx, ry, rw, _) = r
  let k = rw / dmax(1.0, nw)
  let x = (px - rx) / k
  let y = (py - ry) / k
  match phase {
    0 => {
      // (what a finger put down does to the marks told, once done: what draws them and the bars follow it)
      marks_finger_down(c, x, y, k)
      marks_changed()
    }
    1 =>
      match marking.drag {
        Some(Drawing(m)) => {
          marking.drag = Some(
            Drawing(
              if m.kind == "pen" {
                { ..m, pts: m.pts + [x, y] }
              } else {
                { ..m, pts: [m.pts[0], m.pts[1], x, y] }
              },
            ),
          )
          marks_changed()
        }
        Some(Moving(id, fx, fy, orig, handle, before, _)) => {
          let next = orig.dragged(handle, x - fx, y - fy)
          marking.shapes = marking.shapes.map(fn(s) { if s.id == id { next } else { s } })
          // (changed only when it is not where it was: a tap's let go comes as a move of its own, to no undo)
          let changed = next.pts != orig.pts || next.w != orig.w
          marking.drag = Some(Moving(id, fx, fy, orig, handle, before, changed))
          marks_changed()
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
            }
          }
          marks_changed()
          if far && m.numbered() {
            c.focus_editor("marks/note")
          }
        }
        Some(Moving(_, _, _, _, _, before, changed)) => {
          marking.drag = None
          if changed {
            marking.past.push(before)
            marking.future = []
          }
          marks_changed()
        }
        None => ()
      }
  }
}

///|
/// A finger put down on the picture while marking, at (`x`, `y`) in its pixels (`k` stage points to one): what it
/// takes up (marks_finger's down).
fn marks_finger_down(c : @ui.Ctx, x : Double, y : Double, k : Double) -> Unit {
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
    // the picked mark's handles first (ImageMarks.kt down), then the marks, the topmost first
    if marking.tool == Select {
      match marking.shapes.iter().find_first(fn(s) { s.id == marking.picked }) {
        Some(s) =>
          match
            s
            .handles(k)
            .iter()
            .find_first(fn(h) { ((h.1 - x) * (h.1 - x) + (h.2 - y) * (h.2 - y)).sqrt() < reach * 1.4 }) {
            Some((h, _, _)) => {
              marking.drag = Some(Moving(s.id, x, y, s, Some(h), marking.shapes, false))
              return
            }
            None => ()
          }
        None => ()
      }
    }
    let hit = marking.shapes
      .rev()
      .iter()
      .find_first(fn(s) {
        (marking.tool == Select || s.kind == "words") && s.distance(x, y) <= s.w / 2.0 + reach
      })
    match hit {
      Some(s) => {
        // words with the words tool: written again
        if s.kind == "words" && marking.tool == Words {
          marking.writing = Some((s.id, s.pts[0], s.pts[1], s.w, s.color))
          marking.write_field.set(s.text)
          c.focus_editor("marks/write")
          return
        }
        marking.picked = s.id
        marking.drag = Some(Moving(s.id, x, y, s, None, marking.shapes, false))
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

///|
/// The finger on the picture called off (the system took it, a second finger came, the viewer closed): what it was
/// drawing dropped, a mark it was moving back where it was; nothing kept of it, nothing to undo.
pub fn marks_finger_off() -> Unit {
  match marking.drag {
    Some(Drawing(_)) => marking.drag = None
    Some(Moving(_, _, _, _, _, before, changed)) => {
      marking.drag = None
      if changed {
        marking.shapes = before
      }
    }
    None => return
  }
  marks_changed()
}

///|
/// The marks drawn over the picture at `r` (x, y, w, h on the stage), of `nw` × `nh` natural pixels (ImageMarks.kt
/// drawMarks, drawPicked, Pins, WritingField): the lines (a box's rounded edge, an arrow and its barbs, a line drawn by
/// hand smoothed through its midpoints) in one drawing over the stage; words with their halo; the picked mark's
/// dashed frame and its handles; the numbered marks' pins; the words being written. Each placed where it is on the
/// stage, a layer of its own (nothing in it flows after what came before).
pub fn marks_draw(c : @ui.Ctx, r : (Double, Double, Double, Double), nw : Double, nh : Double) -> Unit {
  marks_said()
  let (rx, ry, rw, _) = r
  let k = rw / dmax(1.0, nw)
  let numbers = mark_numbers(marking.shapes)
  // what is put at (x, y) on the stage, over what came before
  let at_place = fn(x : Double, y : Double, body : () -> Unit) {
    c.layer(fn() { c.box(tx=x, ty=y, body) |> ignore }) |> ignore
  }
  let lines : Array[@ui.Line] = []
  let drawn = marks_drawn()
  for m in drawn {
    let lw = m.w * k
    let at = fn(i : Int) -> (Double, Double) { (rx + m.pts[2 * i] * k, ry + m.pts[2 * i + 1] * k) }
    match m.kind {
      "box" => {
        let (bx, by, bw, bh) = m.bounds()
        lines.push(@ui.line(round_rect(rx + bx * k, ry + by * k, bw * k, bh * k, dmin(lw * 1.5, dmin(bw * k, bh * k) / 2.0)), width=lw, color=m.color))
      }
      "arrow" => {
        let (ax, ay) = at(0)
        let (bx, by) = at(1)
        let (lx, ly, qx, qy) = arrow_barbs(ax, ay, bx, by, lw)
        lines.push(@ui.line([(ax, ay), (bx, by)], width=lw, color=m.color))
        lines.push(@ui.line([(lx, ly), (bx, by), (qx, qy)], width=lw, color=m.color))
      }
      "pen" => lines.push(@ui.line(smoothed(m.pts.length() / 2, at), width=lw, color=m.color))
      _ => ()
    }
  }
  // the picked mark's dashed frame (white at 85%, 1 wide, 4 on 3 off), its handles round and white, ringed in the ink
  let handles : Array[(Double, Double)] = []
  match marking.shapes.iter().find_first(fn(s) { s.id == marking.picked && marking.tool == Select }) {
    Some(s) => {
      if s.kind != "arrow" {
        let (bx, by, bw, bh) = s.bounds()
        let reach = mark_reach / 2.0
        let x0 = rx + bx * k - reach
        let y0 = ry + by * k - reach
        let x1 = rx + (bx + bw) * k + reach
        let y1 = ry + (by + bh) * k + reach
        dashes([(x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0)], lines)
      }
      for h in s.handles(k) {
        handles.push((rx + h.1 * k, ry + h.2 * k))
      }
    }
    None => ()
  }
  c.layer(fn() { c.lines(lines, w=Fill(1.0), h=Fill(1.0)) |> ignore }) |> ignore
  // words, edged in their halo
  for m in drawn {
    if m.kind == "words" {
      let x = rx + m.pts[0] * k
      let y = ry + m.pts[1] * k
      let size = m.w * k
      let halo = halo_of(m.color)
      let e = size * 0.08
      for o in [(-e, 0.0), (e, 0.0), (0.0, -e), (0.0, e), (-e, -e), (e, e), (-e, e), (e, -e)] {
        at_place(x + o.0, y + o.1, fn() {
          c.text(m.text, size~, weight=600, color=halo, wrap=false, line=size * 1.3) |> ignore
        })
      }
      at_place(x, y, fn() { c.text(m.text, size~, weight=600, color=m.color, wrap=false, line=size * 1.3) |> ignore })
    }
  }
  for h in handles {
    at_place(h.0 - 6.0, h.1 - 6.0, fn() {
      c.box(w=Px(12.0), h=Px(12.0), radius=6.0, bg=0xFFFFFFFFL, border=1.5, border_color=0xE5704AFFL, fn() {  })
      |> ignore
    })
  }
  // the numbered marks' pins, each at its own size whatever the zoom, up and to the right of their point; tapped, its
  // note; a little bigger while it is open
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
          }
          marks_changed()
          if marking.note >= 0 {
            c.focus_editor("marks/note")
          }
        }
        at_place(rx + px * k - 2.0, ry + py * k - 22.0, fn() {
          let pin = picture_pin(c, n, s.color, 24.0, id~)
          // what a screen reader says of it (ImageMarks.kt Pins: 标注 n)
          c.semantics(pin, Button, id~, label=pv_fill("android-chat.marks.pin", [("n", n.to_string())]))
          if marking.note == s.id {
            c.look(pin, @ui.look(scale=pin_open_scale, ox=2.0 / 24.0, oy=22.0 / 24.0))
          }
        })
      }
      None => ()
    }
  }
  // the words being written, where they go, in their size and colour
  match marking.writing {
    Some((_, x, y, w, color)) => {
      let size = w * k
      at_place(rx + x * k, ry + y * k, fn() {
        c.box(w=Px(dmax(size * 6.0, 120.0)), fn() {
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
      })
    }
    None => ()
  }
}

///|
/// A pin's number (ImageMarks.kt Pins; Notes.kt Pin): the mark's colour edged 2 in its halo (`size` 24), or no edge
/// (`size` 16, a note's), round but for its corner at the foot towards the mark (3; 2 the small one), the number in
/// the halo. Its node.
pub fn picture_pin(c : @ui.Ctx, n : Int, color : Int64, size : Double, id? : Int = 0) -> Int {
  let halo = halo_of(color)
  let small = size < 20.0
  let edge = if small { 0.0 } else { 2.0 }
  let point = if small { 2.0 } else { 3.0 }
  c.box(w=Px(size), h=Px(size), id~, shadow=if small { 0.0 } else { @sf.pin_raised.sigma }, shadow_y=@sf.pin_raised.dy, shadow_color=@sf.pin_raised.color, radius=size / 2.0, bg=if small { color } else { halo }, fn() {
    // its pointed corner: a square over the round one at the foot towards the mark
    c.layer(fn() {
      c.box(w=Px(size / 2.0), h=Px(size / 2.0), ty=size / 2.0, radius=point, bg=if small { color } else { halo }, fn() {  })
      |> ignore
    })
    |> ignore
    if !small {
      c.layer(fn() {
        c.box(w=Px(size - 2.0 * edge), h=Px(size - 2.0 * edge), tx=edge, ty=edge, radius=size / 2.0 - edge, bg=color, fn() {
          c.layer(fn() {
            c.box(w=Px(size / 2.0 - edge), h=Px(size / 2.0 - edge), ty=size / 2.0 - edge, radius=point / 2.0, bg=color, fn() {  })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    c.layer(align=ACenter, fn() {
      c.box(h=Px(size), justify=JCenter, fn() {
        c.text("\{n}", size=if small { 10.0 } else { 11.0 }, weight=if small { 650 } else { 700 }, color=if small { 0xFFFFFFFFL } else { halo }, wrap=false)
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// How much bigger an open note's pin is (ImageMarks.kt Pins: 1.12, from its point).
pub let pin_open_scale : Double = 1.12

///|
/// The points of a rectangle at (x, y), `w` × `h`, its corners round by `r`, all the way round.
pub fn round_rect(x : Double, y : Double, w : Double, h : Double, r : Double) -> Array[(Double, Double)] {
  let pi = @math.PI
  let out : Array[(Double, Double)] = [(x + r, y)]
  out.append(@ui.arc(x + w - r, y + r, r, from=-pi / 2.0, sweep=pi / 2.0))
  out.append(@ui.arc(x + w - r, y + h - r, r, from=0.0, sweep=pi / 2.0))
  out.append(@ui.arc(x + r, y + h - r, r, from=pi / 2.0, sweep=pi / 2.0))
  out.append(@ui.arc(x + r, y + r, r, from=pi, sweep=pi / 2.0))
  out.push((x + r, y))
  out
}

///|
/// A line drawn by hand through its `n` points (`at`), smoothed as ImageMarks.kt pathOf has it: through the midpoints,
/// each point bending the line (quadratics, each in pieces a few pixels long).
pub fn smoothed(n : Int, at : (Int) -> (Double, Double)) -> Array[(Double, Double)] {
  let out : Array[(Double, Double)] = [at(0)]
  if n < 3 {
    for i in 1..<n {
      out.push(at(i))
    }
    return out
  }
  let mut from = at(0)
  for i in 1..<(n - 1) {
    let (cx, cy) = at(i)
    let (nx, ny) = at(i + 1)
    let to = ((cx + nx) / 2.0, (cy + ny) / 2.0)
    let pieces = 6
    for j in 1..=pieces {
      let t = j.to_double() / pieces.to_double()
      let u = 1.0 - t
      out.push((u * u * from.0 + 2.0 * u * t * cx + t * t * to.0, u * u * from.1 + 2.0 * u * t * cy + t * t * to.1))
    }
    from = to
  }
  out.push(at(n - 1))
  out
}

///|
/// A path's dashes (4 on, 3 off) as lines in white at 85%, 1 wide.
pub fn dashes(path : Array[(Double, Double)], out : Array[@ui.Line]) -> Unit {
  let mut on = true
  let mut left = 4.0
  for i in 0..<(path.length() - 1) {
    let (x0, y0) = path[i]
    let (x1, y1) = path[i + 1]
    let len = ((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)).sqrt()
    let mut d = 0.0
    while d < len {
      let step = dmin(left, len - d)
      if on {
        out.push(
          @ui.line(
            [(x0 + (x1 - x0) * d / len, y0 + (y1 - y0) * d / len), (x0 + (x1 - x0) * (d + step) / len, y0 + (y1 - y0) * (d + step) / len)],
            width=1.0,
            color=0xFFFFFFD9L,
          ),
        )
      }
      d = d + step
      left = left - step
      if left <= 0.0 {
        on = !on
        left = if on { 4.0 } else { 3.0 }
      }
    }
  }
}

///|
/// The words the marked image's quotes say (ImageMarks.kt quotes): a quote per numbered mark, where it is (for the
/// agent), on which image, what was said of it.
pub fn marks_quotes(made : String, original : String, nw : Double, nh : Double) -> Array[(String, String, String)] {
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
pub fn marks_json(nw : Double, nh : Double) -> String {
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
/// Back while marking (ImageMarks.kt back): closes a note, puts down the words being written, closes the colours,
/// lets go of the picked mark, else stops marking.
pub fn marks_back(c : @ui.Ctx) -> Unit {
  if marking.note >= 0 {
    marks_note_done(c)
  } else if marking.writing is Some(_) {
    marks_put_down(c)
  } else if marking.palette {
    marking.palette = false
    marks_changed()
  } else if marking.picked >= 0 {
    marking.picked = -1
    marks_changed()
  } else {
    marks_leave()
  }
}

///|
pub fn marks_note_done(c : @ui.Ctx) -> Unit {
  if marking.note >= 0 {
    marking.comments[marking.note] = marking.note_field.text()
  }
  marking.note = -1
  marks_changed()
  c.blur()
}

///|
/// Something drawn (or being written) to be kept.
pub fn marks_any() -> Bool {
  marking.shapes.length() > 0 || (marking.writing is Some(_) && marking.write_field.text().trim(chars=" \n\t") != "")
}

///|
/// In the top bar while marking (ImageMarks.kt MarksActions): why it failed, 取消, 下载标注后的图片, 添加到对话 (when
/// there is a chat's draft to put it in). True on the frame one of them is tapped: `go(draft)`.
/// `ink`: what its words and icons are drawn in (a desktop's bar is the page's, preview_desk.mbt).
pub fn marks_actions(c : @ui.Ctx, can_draft : Bool, go : (Bool) -> Unit, ink? : Int64 = dark_muted) -> Unit {
  let ready = !marking.busy && marks_any()
  // as wide as they are: the file's name before them cut short instead
  c.box(dir=Row, gap=4.0, align=ACenter, keep=true, fn() {
    if marking.error != "" {
      c.box(padx=6.0, max_w=140.0, clip=true, fn() {
        c.text(marking.error, size=@sf.theme().t.meta, color=0xFF7B6BFFL, wrap=false) |> ignore
      })
      |> ignore
    }
    let cancel = c.id("marks/cancel")
    if c.clicked(cancel) {
      marks_leave()
    }
    let cancel_box = c.box(h=Px(32.0), padx=10.0, radius=picture_key, justify=JCenter, id=cancel, fn() {
      c.text(pv("common.cancel"), size=@sf.theme().t.meta, color=ink, wrap=false) |> ignore
    })
    c.semantics(cancel_box, Button, id=cancel, label=pv("common.cancel"))
    if picture_button(c, "marks/download", "download", ink, true, enabled=ready, said=pv("android-chat.marks.downloadMarked")) {
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
              size=@sf.theme().t.meta,
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
/// The corner of what is on the viewer's bars (ImageMarks.kt PICTURE_KEY): round, half their 32 (in the middle of a
/// bar's capsule ends, 6 in, concentric with them: picture_bar_corner).
pub let picture_key : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
pub let marks_put_room : @ui.Style = @ui.css("pl=S1")

///|
/// How far over the tools (the window's tree's, marks_tools_node) the notes are, drawn without them: as far as from the
/// tools here (8 under the notes, and the tools' column's 2 more).
let marks_notes_over_tools : Double = 10.0

///|
/// The foot while marking (ImageMarks.kt MarksFoot, in the viewer's dark): the note being written in its box over the
/// keyboard (Notes.kt NoteBox), else the notes as cards (a tap opens one again; Notes.kt Card) over the tools
/// (ImageMarks.kt MarksTools: 选择, 框, 箭头, 画笔, 文字 · the colour · 删除 the picked · 撤销, 重做), the colours in a row
/// over them when asked for. `tools` false: none of them, the tools nodes of the window's tree's under it
/// (marks_tools_node).
pub fn marks_foot(c : @ui.Ctx, tools? : Bool = true, note? : Bool = true) -> Unit {
  // (the note being written elsewhere, `note` false: nothing here while it is, note_box_node)
  if !note && marking.note >= 0 && mark_notes().iter().any(fn(x) { x.0 == marking.note }) {
    return
  }
  if marking.note >= 0 {
    match mark_notes().iter().find_first(fn(x) { x.0 == marking.note }) {
      Some(note) => {
        // (8 over the keyboard, or the navigation bar: FilePreview.kt MarksFoot's place)
        c.box(w=Fill(1.0), padx=12.0, pb=8.0, fn() { note_box(c, note) }) |> ignore
        return
      }
      None => ()
    }
  }
  marking.popped = -1
  // (over the picture: FilePreview.kt's darkGlass, as MarksTools has it)
  let glass = dark_glass()
  // (its tools elsewhere, `tools` false: the notes as far over them as they are from the tools here)
  c.box(w=Fill(1.0), pb=if tools { 8.0 } else { marks_notes_over_tools }, gap=10.0, align=ACenter, fn() {
    // the notes said so far, a card each; where they do not all fit, the last leave the row first, a +N card at its
    // end standing for them (a menu of them, in their order): nothing scrolled, nothing wrapped
    let notes = mark_notes()
    if notes.length() > 0 {
      let n = notes.length()
      let slot = fn(mid : Int) { c.id("marks/card-slot/\{mid}") }
      // (those the row left out as last laid out: read back, the frame built again where that changes)
      let gone : Array[@sf.MenuItem?] = []
      for x in notes {
        if c.left_out(slot(x.0)) {
          gone.push(Some(@sf.menu_item_of("\{x.1}  " + note_said(x.0), fn() { marks_open_note(c, x.0) })))
        }
      }
      c.box(style=marks_notes_row, fn() {
        for i, x in notes {
          let id = c.id("marks/card/\{x.0}")
          if c.clicked(id) {
            marks_open_note(c, x.0)
          }
          c.box(id=slot(x.0), taps=false, drop=n - i, fn() { note_card(c, x, id) }) |> ignore
        }
        c.box(more=true, fn() {
          let id = c.id("marks/notes-more")
          if c.clicked(id) {
            @sf.menu(gone, from=Of(id), along=End)
          }
          note_tray_card(c, id, note_more_w, fn() { note_first(c, "+\{gone.length()}", false) })
        })
        |> ignore
      })
      |> ignore
    }
    // (the tools nodes of the window's tree's, under what this draws: marks_tools_node)
    if !tools {
      return
    }
    c.box(gap=12.0, align=ACenter, fn() {
      if marking.palette {
        c.box(dir=Row, pad=4.0, gap=2.0, radius=20.0, glass~, fn() {
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
      c.box(dir=Row, h=Px(44.0), padx=6.0, gap=2.0, radius=picture_bar_corner, glass~, align=ACenter, fn() {
        for x in [(Select, "cursor", "select"), (Rect, "square", "rect"), (Arrow, "arrow-up-right", "arrow"), (Pen, "scribble", "pen"), (Words, "text", "text")] {
          let (tool, icon, name) = x
          if picture_button(c, "marks/tool/" + icon, icon, dark_muted, true, held=marking.tool == tool, said=pv("android-chat.marks.tool." + name)) {
            marks_put_down(c)
            marking.note = -1
            marking.tool = tool
            if tool != Select {
              marking.picked = -1
            }
            marks_changed()
          }
        }
        mark_gap(c)
        let swatch = c.id("marks/palette")
        if c.clicked(swatch) {
          marking.palette = !marking.palette
          marks_changed()
        }
        let swatch_box = c.box(w=Px(32.0), h=Px(32.0), radius=picture_key, align=ACenter, justify=JCenter, id=swatch, fn() {
          mark_swatch(c, marks_shown_color())
        })
        c.semantics(swatch_box, Button, id=swatch, label=pv("android-chat.marks.color"))
        @sf.tip(c, "marks/palette/tip", swatch, pv("android-chat.marks.color"))
        if marking.picked >= 0 && picture_button(c, "marks/remove", "trash", dark_muted, true, said=pv("common.delete")) {
          marks_remove(marking.picked)
        }
        mark_gap(c)
        if picture_button(c, "marks/undo", "retry", dark_muted, true, enabled=marking.past.length() > 0, said=pv("android-chat.marks.undo")) {
          marks_undo()
        }
        if picture_button(c, "marks/redo", "redo", dark_muted, true, enabled=marking.future.length() > 0, said=pv("android-chat.marks.redo")) {
          marks_redo()
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The numbered marks' notes in their numbers' order (ImageMarks.kt notes): the mark's id, its number, what it is (框,
/// 箭头), its colour.
pub fn mark_notes() -> Array[(Int, Int, String, Int64)] {
  let numbers = mark_numbers(marking.shapes)
  let out = []
  for s in marking.shapes {
    match numbers.get(s.id) {
      Some(n) => out.push((s.id, n, pv(if s.kind == "box" { "android-chat.marks.note.box" } else { "android-chat.marks.note.arrow" }), s.color))
      None => ()
    }
  }
  out
}

///|
/// The note of the mark `id` opened (ImageMarks.kt open): what was being written put down, nothing picked.
pub fn marks_open_note(c : @ui.Ctx, id : Int) -> Unit {
  marks_put_down(c)
  marking.picked = -1
  marking.note = id
  marking.note_field.set(marking.comments.get(id).unwrap_or(""))
  marks_changed()
  c.focus_editor("marks/note")
}

///|
/// How a note's box comes in (Notes.kt pop: from nothing and 97% of its size, 140 ms on Arrive).
pub let note_pop_ms : Double = 140.0

///|
/// The note being written (Notes.kt NoteBox, in the dark): a frosted card floating over the keyboard (26 round, 8 in at
/// its sides, 10 over, 8 under, 6 between): its pin and what it is, muted; then 删除批注 (a bin, 36 round), the field
/// (16 on 21, 添加批注（可选） till something is written, 8 lines at most), 完成 (a tick on the ink, 36 round).
pub fn note_box(c : @ui.Ctx, note : (Int, Int, String, Int64)) -> Unit {
  let (id, n, what, color) = note
  let pop = @motion.anim(c, "marks/note-pop", 1.0, global=true)
  if marking.popped != id {
    marking.popped = id
    pop.snap(0.0)
    pop.animate(1.0, @motion.tween(note_pop_ms, ease=Out))
  }
  let p = pop.get()
  let remove = c.id("marks/note-remove")
  if c.clicked(remove) {
    marking.note = -1
    marks_remove(id)
    c.blur()
  }
  let done = c.id("marks/note-done")
  if c.clicked(done) {
    marks_note_done(c)
  }
  // (its round buttons, 36, in its foot corners as far in as makes them concentric with it: @sf.capsule_in)
  let keys_in = @sf.capsule_in(note_box_corner, 36.0)
  let box = c.box(w=Fill(1.0), pl=keys_in, pr=keys_in, pt=10.0, pb=keys_in, gap=6.0, radius=note_box_corner, bg=note_ground, shadow=@sf.floating.sigma, shadow_y=@sf.floating.dy, shadow_color=@sf.floating.color, fn() {
    c.box(style=note_head, fn() {
      picture_pin(c, n, color, 16.0) |> ignore
      c.text(what, size=@sf.theme().t.meta, line=18.0, color=note_muted, wrap=false) |> ignore
    })
    |> ignore
    c.box(style=note_row, fn() {
      c.box(w=Px(36.0), h=Px(36.0), radius=18.0, align=ACenter, justify=JCenter, label=pv("android-chat.annotate.remove"), id=remove, fn() {
        @sf.icon(c, "trash", size=17.0, color=note_muted) |> ignore
      })
      |> ignore
      c.box(w=Fill(1.0), min_h=36.0, padx=8.0, pady=7.0, justify=JCenter, fn() {
        c.editor(
          "marks/note",
          placeholder=pv("android-chat.annotate.write"),
          font_size=16.0,
          line=21.0,
          max_lines=8,
          plain=true,
          color=note_ink,
          placeholder_color=note_subtle,
          caret_color=note_accent,
          enter_sends=false,
          field=marking.note_field,
        )
        |> ignore
      })
      |> ignore
      c.box(w=Px(36.0), h=Px(36.0), radius=18.0, bg=note_ink, align=ACenter, justify=JCenter, label=pv("android-chat.annotate.done"), id=done, fn() {
        @sf.icon(c, "check", size=18.0, color=note_bg) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  if p < 1.0 {
    c.look(box, @ui.look(alpha=p, scale=0.97 + 0.03 * p))
  }
}

///|
/// A note's card in the tray (Notes.kt Card, in the dark): 160 wide, frosted, round by the ladder's row step: its pin
/// and what is said of it (只引用, muted, while nothing is), over what it is, muted. Its pin (16 round) in its top left
/// corner as far from both edges as makes it concentric with it (@sf.capsule_in), level with the first line (20).
pub fn note_card(c : @ui.Ctx, note : (Int, Int, String, Int64), id : Int) -> Unit {
  let (mid, n, what, color) = note
  let said = marking.comments.get(mid).unwrap_or("").trim(chars=" \n\t").to_string()
  note_tray_card(c, id, note_card_w, fn() {
    c.box(style=card_head, fn() {
      picture_pin(c, n, color, note_pin) |> ignore
      note_first(c, note_said(mid), said == "")
    })
    |> ignore
    c.text(what, size=@sf.theme().t.caption, line=17.0, color=note_muted, wrap=false) |> ignore
  })
}

///|
/// What is said of note `mid`, else 只引用.
fn note_said(mid : Int) -> String {
  match marking.comments.get(mid).unwrap_or("").trim(chars=" \n\t").to_string() {
    "" => pv("android-chat.annotate.quoteOnly")
    said => said
  }
}

///|
/// A card in the notes' tray, `w` wide (frosted, round by the ladder's row step, its first line level with a pin
/// concentric in its corner): `body` in it.
fn note_tray_card(c : @ui.Ctx, id : Int, w : Double, body : () -> Unit) -> Unit {
  let pin_in = @sf.capsule_in(note_card_corner, note_pin)
  c.box(w=Px(w), pl=pin_in, pr=note_card_end, pt=pin_in - (note_first_line - note_pin) / 2.0, pb=note_card_foot, gap=3.0, radius=note_card_corner, bg=note_ground, shadow=@sf.floating.sigma, shadow_y=@sf.floating.dy, shadow_color=@sf.floating.color, id~, body)
  |> ignore
}

///|
/// A tray card's first line: `words`, muted where `quiet` (only quoting), cut by its card where long.
fn note_first(c : @ui.Ctx, words : String, quiet : Bool) -> Unit {
  c.box(w=Fill(1.0), clip=true, fn() {
    c.text(words, size=@sf.theme().t.meta, line=20.0, color=if quiet { note_muted } else { note_ink }, wrap=false) |> ignore
  })
  |> ignore
}

///|
/// A note's card's width, and the +N card's standing for those that left the tray (a picture's tile's).
let note_card_w : Double = 160.0

///|
let note_more_w : Double = 56.0

///|
/// The notes' tray: 16 in from the sides, 8 between.
// kept across runs: a value (no field of it changes)
let marks_notes_row : @ui.Style = @ui.css("row w=Full px=S4 gap=S2")

///|
/// A note's card's corner in the tray: the ladder's row step (Notes.kt Card's 16 before it), its pin concentric in it;
/// its pin's side, its first line's height, its room at its end and its foot (Notes.kt Card: 12, 9).
let note_card_corner : Double = @sf.row_corner

///|
let note_pin : Double = 16.0

///|
let note_first_line : Double = 20.0

///|
let note_card_end : Double = 12.0

///|
let note_card_foot : Double = 9.0

///|
/// A note's box's head (its pin and what it is: 8 in, 6 apart), the row under it (the bin, the field, the tick: 2
/// apart, at its foot), a card's head (6 apart); the room either side of a tools' gap (4).
// kept across runs: a value (no field of it changes)
pub let note_head : @ui.Style = @ui.css("row px=S2 gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
pub let note_row : @ui.Style = @ui.css("row w=Full gap=S0_5 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
pub let card_head : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
pub let mark_gap_room : @ui.Style = @ui.css("px=S1")

///|
/// The dark theme's colours the notes take (Theme.kt Dark): the page, its words, muted, subtle, the accent; their
/// ground the raised grey at 72% over the page (Glass.kt floatingStill).
pub let note_bg : Int64 = 0x1B1C1FFFL

///|
pub let note_ink : Int64 = 0xECECEDFFL

///|
pub let note_muted : Int64 = 0x9A9DA3FFL

///|
pub let note_subtle : Int64 = 0x84888FFFL

///|
pub let note_accent : Int64 = 0xEF7A55FFL

///|
pub let note_ground : Int64 = @sf.over(note_bg, @sf.alpha(0x2A2C31FFL, 0.72))

///|
/// The note's box's corner (Notes.kt NoteBox: Smooth(26), the composer's).
pub let note_box_corner : Double = 26.0

///|
/// The bars' corner over a picture (ImageMarks.kt PictureBar): its keys' 16 and the 6 they stand in (外圆角 = 距离 +
/// 半高): a capsule 44 high.
pub let picture_bar_corner : Double = picture_bar_in + picture_key

///|
/// How far in the bar's keys stand (its 6).
let picture_bar_in : Double = 6.0

///|
/// Between the tools' groups (ImageMarks.kt Gap): a line 1 by 18, white at 10%, 4 either side.
pub fn mark_gap(c : @ui.Ctx) -> Unit {
  c.box(style=mark_gap_room, fn() { c.box(w=Px(1.0), h=Px(18.0), bg=0xFFFFFF1AL, fn() {  }) |> ignore }) |> ignore
}

///|
/// A colour's swatch (ImageMarks.kt Swatch): a disc of it 16 across, ringed 1.5 inside its edge in white at 50%.
pub fn mark_swatch(c : @ui.Ctx, color : Int64) -> Unit {
  c.box(w=Px(16.0), h=Px(16.0), radius=8.0, bg=color, border=1.5, border_color=0xFFFFFF80L, fn() {  }) |> ignore
}

///|
/// The colour shown: the words being written's, the picked mark's, else the one to draw in.
pub fn marks_shown_color() -> Int64 {
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
pub fn marks_pick_color(col : Int64) -> Unit {
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
  marks_changed()
}

///|
/// Where what is being written ends on the stage (ImageMarks.kt writingBottom): the words being written's foot; the
/// open note's pin's point and the note's box under it (NOTE_BOX, 140); None while neither is.
pub fn marks_writing_bottom(z : @kit.Zoom) -> Double? {
  marks_writing_bottom_in(z, z.rect())
}

///|
/// Where what is being written (or the open note's box) ends on the stage, the picture at `r` (marks_writing_bottom's,
/// the picture where it is at a moment of the caller's).
pub fn marks_writing_bottom_in(z : @kit.Zoom, r : (Double, Double, Double, Double)?) -> Double? {
  marks_said()
  if !marking.on {
    return None
  }
  let (_, ry, rw, _) = match r {
    Some(r) => r
    None => return None
  }
  let k = rw / dmax(1.0, z.nw)
  if marking.note >= 0 {
    return match marking.shapes.iter().find_first(fn(s) { s.id == marking.note }) {
      Some(s) => {
        let py0 = if s.kind == "box" { s.bounds().1 } else { s.pts[1] }
        let py = dmax(22.0 / k, dmin(dmax(22.0 / k, z.nh - 2.0 / k), py0))
        Some(ry + py * k + note_box_room)
      }
      None => None
    }
  }
  match marking.writing {
    Some((_, _, y, w, _)) => Some(ry + (y + w * 1.3) * k)
    None => None
  }
}

///|
/// The room the open note's box takes under its pin (ImageMarks.kt NOTE_BOX).
pub let note_box_room : Double = 140.0

///|
/// How far what is being written stays over the keyboard (FilePreview.kt: 24).
pub let marks_keyboard_gap : Double = 24.0
