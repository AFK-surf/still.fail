// What the last frame laid out in less room than it needs, as it shows (Tester::squeeze_faults): two things side by
// side drawn over each other, something cut off by the window's edge, words cut down to nothing. Room runs short by
// design in three ways only, none of them a fault: words cut short with an ellipsis (keeping some of them), what a
// row says may go left out of it (Ctx::box `drop`, into its ⋯ where it has one), what scrolls or is cut by its own box
// (a list, a scroll, `sideways`, `clip`). What overlaps on purpose says so: a margin below 0 (faces in a stack), a
// layer, something put where it is said.

///|
/// How far two things may run into each other, or past the window, and still be apart: the layout's rounding.
let squeeze_slack : Double = 1.0

///|
/// How many characters of words cut short with an ellipsis must still show: fewer, and the words were squeezed out.
let squeeze_kept_chars : Int = 2

///|
/// Where the last frame shows something squeezed (see the file's head), a line each: two things beside each other in
/// a box drawn over each other (by how far), the outermost box that runs past the window's edge, words cut down to
/// less than `squeeze_kept_chars` characters before their ellipsis.
pub fn Tester::squeeze_faults(self : Tester) -> Array[String] {
  ignore(self)
  g().squeeze_faults()
}

///|
fn Ctx::squeeze_faults(self : Ctx) -> Array[String] {
  let out : Array[String] = []
  let n = self.count
  // what each node draws, with what it holds, as far as it shows (x0, y0, x1, y1; x0 > x1: nothing), and whether it
  // is in what cuts or scrolls what it holds (a box past its edges is not cut off by the window, but by that)
  let ext = Array::make(n * 4, 0.0)
  for i in 0..<n {
    let b = self.nodes[i]
    if b.squeeze_shows() {
      ext[i * 4] = b.x
      ext[i * 4 + 1] = b.y
      ext[i * 4 + 2] = b.x + b.fw
      ext[i * 4 + 3] = b.y + b.fh
    } else {
      ext[i * 4] = 1.0e9
      ext[i * 4 + 1] = 1.0e9
      ext[i * 4 + 2] = -1.0e9
      ext[i * 4 + 3] = -1.0e9
    }
  }
  // (a node's parent comes before it in the pool: what it holds is folded into it from the last up)
  for k in 0..<n {
    let i = n - 1 - k
    let b = self.nodes[i]
    let p = b.parent
    // (what is drawn off its place on purpose, by its own offset or as a layer, is not its parent's to fit)
    if p < 0 || p >= n || b.squeeze_aside() || b.opacity <= 0.01 || ext[i * 4] > ext[i * 4 + 2] {
      continue
    }
    let a = self.nodes[p]
    let (x0, y0, x1, y1) = if a.squeeze_cuts() {
      (
        dmax(ext[i * 4], a.x),
        dmax(ext[i * 4 + 1], a.y),
        dmin(ext[i * 4 + 2], a.x + a.fw),
        dmin(ext[i * 4 + 3], a.y + a.fh),
      )
    } else {
      (ext[i * 4], ext[i * 4 + 1], ext[i * 4 + 2], ext[i * 4 + 3])
    }
    if x0 > x1 || y0 > y1 {
      continue
    }
    ext[p * 4] = dmin(ext[p * 4], x0)
    ext[p * 4 + 1] = dmin(ext[p * 4 + 1], y0)
    ext[p * 4 + 2] = dmax(ext[p * 4 + 2], x1)
    ext[p * 4 + 3] = dmax(ext[p * 4 + 3], y1)
  }
  let cut = Array::make(n, false)
  let seen = Array::make(n, true)
  // what of the window across each node may show in, by the boxes that cut round it (what scrolls sideways starts
  // again: what it holds runs past it on purpose), and whether a fault was said of it
  let room = Array::make(n * 2, 0.0)
  let said = Array::make(n, false)
  for i in 0..<n {
    let b = self.nodes[i]
    let p = b.parent
    if p >= 0 && p < n {
      let a = self.nodes[p]
      cut[i] = cut[p] || a.squeeze_cuts()
      seen[i] = seen[p] && b.opacity > 0.01
      // (what scrolls sideways may run past its edges; a list or a scroll runs up and down, and cuts across as a box
      // that clips does)
      if a.sideways {
        room[i * 2] = -1.0e9
        room[i * 2 + 1] = 1.0e9
      } else if a.squeeze_cuts() {
        room[i * 2] = dmax(room[p * 2], a.x)
        room[i * 2 + 1] = dmin(room[p * 2 + 1], a.x + a.fw)
      } else {
        room[i * 2] = room[p * 2]
        room[i * 2 + 1] = room[p * 2 + 1]
      }
    } else {
      seen[i] = b.opacity > 0.01
      room[i * 2] = -1.0e9
      room[i * 2 + 1] = 1.0e9
    }
  }
  let w = self.width
  for i in 0..<n {
    let b = self.nodes[i]
    if !seen[i] {
      continue
    }
    // words cut down to nothing
    if b.kind == kind_text && !b.wrap && b.fw > 0.0 {
      match (b.tl, b.full) {
        (Some(shown), Some(full)) if full.w > b.fw + squeeze_slack => {
          // (the ellipsis is the last of what shows)
          let kept = shown.shaped.starts.length() - 1
          if kept < squeeze_kept_chars {
            out.push("\{self.named(i)}: its words cut to \{kept} characters (they need \{full.w.round()})")
          }
        }
        _ => ()
      }
    }
    // the outermost box that runs past the window's edge, partly in it, where nothing it is in cuts it
    if !cut[i] && b.fw > 0.0 && b.x < w && b.x + b.fw > 0.0 {
      let past = b.squeeze_past(w)
      let p = b.parent
      let parent_past = p >= 0 && p < n && self.nodes[p].squeeze_past(w) > squeeze_slack
      if past > squeeze_slack && !parent_past && !b.squeeze_aside() {
        out.push("\{self.named(i)} runs \{past.round()} past the window's edge")
      }
    }
    // words, or what is pressed, cut off part way by a box that clips round it: the outermost so
    let words = (b.kind == kind_text || b.kind == kind_rich) && (b.text != "" || b.rich is Some(_))
    let pressed = b.kind == kind_box && b.id != 0 && b.hit
    if (words || pressed) && b.fw > 0.0 && !b.squeeze_aside() {
      let (lo, hi) = (room[i * 2], room[i * 2 + 1])
      let off = dmax(lo - b.x, b.x + b.fw - hi)
      let p = b.parent
      if off > squeeze_slack && b.x < hi && b.x + b.fw > lo && !(p >= 0 && p < n && said[p]) {
        said[i] = true
        out.push("\{self.named(i)} is cut off \{off.round()} by what clips it")
      }
    }
    let p = b.parent
    if p >= 0 && p < n && said[p] {
      said[i] = true
    }
    // two things beside each other in it drawn over each other
    if b.kind != kind_box || b.first < 0 || b.squeeze_cuts() {
      continue
    }
    let kids : Array[Int] = []
    let mut k = b.first
    while k >= 0 {
      let ch = self.nodes[k]
      if !ch.squeeze_aside() && ext[k * 4] <= ext[k * 4 + 2] {
        kids.push(k)
      }
      k = ch.next
    }
    for x in 0..<kids.length() {
      for y in (x + 1)..<kids.length() {
        let (a, c) = (kids[x], kids[y])
        let na = self.nodes[a]
        let nc = self.nodes[c]
        // laid over each other on purpose: pulled back by a margin below 0
        if na.mar_r < 0.0 || na.mar_b < 0.0 || nc.mar_l < 0.0 || nc.mar_t < 0.0 {
          continue
        }
        let ox = dmin(ext[a * 4 + 2], ext[c * 4 + 2]) - dmax(ext[a * 4], ext[c * 4])
        let oy = dmin(ext[a * 4 + 3], ext[c * 4 + 3]) - dmax(ext[a * 4 + 1], ext[c * 4 + 1])
        if ox > squeeze_slack && oy > squeeze_slack {
          // (by how far along the box: across a row, down a column)
          let by = if b.dir == Row { ox } else { oy }
          out.push("\{self.named(a)} and \{self.named(c)} overlap by \{by.round()}, in \{self.named(i)}")
        }
      }
    }
  }
  out
}

///|
/// Whether a node draws something of its own: words, a field, a picture, a native view, a drawing, a ground or an
/// edge.
fn Node::squeeze_shows(self : Node) -> Bool {
  if self.fw <= 0.0 || self.fh <= 0.0 || self.opacity <= 0.01 {
    return false
  }
  if self.kind == kind_text || self.kind == kind_rich {
    self.text != "" || self.rich is Some(_)
  } else if self.kind == kind_editor || self.kind == kind_image || self.kind == kind_native {
    true
  } else {
    self.grounded() || self.shapes.length() > 0 || self.lines.length() > 0
  }
}

///|
/// Whether a node cuts or scrolls what it holds, which may then lie past its edges: a list, a scroll, what scrolls
/// sideways, a box that clips.
fn Node::squeeze_cuts(self : Node) -> Bool {
  self.clip || self.sideways || self.kind == kind_list || self.kind == kind_scroll || self.kind == kind_page
}

///|
/// Whether a node lies apart from its parent's flow, over what is beside it on purpose: a layer, a pager's page, one put
/// where it is said, what is over the whole window, one drawn moved off its place (`tx`, `ty`: a face over the one
/// before it, something on its way).
fn Node::squeeze_aside(self : Node) -> Bool {
  self.layer || self.portal || self.pager != 0 || self.placed_at() || self.tx != 0.0 || self.ty != 0.0 || self.slide != 0.0
}

///|
/// How far a node runs past the edges of a window `w` wide (below 0: inside it).
fn Node::squeeze_past(self : Node, w : Double) -> Double {
  dmax(self.x + self.fw - w, -self.x)
}
