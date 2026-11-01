// What the last frame laid out in less room than it needs, as it shows (Tester::squeeze_faults): two things side by
// side drawn over each other, something cut off by the window's edge, words cut without saying they may be or cut down
// to nothing, words wrapped a letter or two a line, a field's placeholder cut down to nothing, words broken or cut
// short only for what shares their row.
// Room runs short by design in four ways only, none of them a fault: words said a shorter way (Ctx::text's, a field's
// placeholder's: `shorter`), words cut short with an ellipsis (keeping some of them; for what is beside them, only
// those said to be: `w=Cut`), what a row says may go left out of it (Ctx::box `drop`, into its ⋯ where it has one),
// what scrolls or is cut by its own box (a list, a scroll, `sideways`, `clip`). What overlaps on purpose says so: a
// margin below 0 (faces in a stack), a layer, something put where it is said.

///|
/// How far two things may run into each other, or past the window, and still be apart: the layout's rounding.
let squeeze_slack : Double = 1.0

///|
/// How many characters of words cut short with an ellipsis must still show: fewer, and the words were squeezed out.
let squeeze_kept_chars : Int = 2

///|
/// How narrow words wrapped onto lines may be laid where they may break anywhere (Chinese), in their size: four of them
/// a line at least (or all of them, fewer).
let squeeze_wrap_ems : Double = 4.0

///|
/// Where the last frame shows something squeezed (see the file's head), a line each: two things beside each other in
/// a box drawn over each other (by how far), the outermost box that runs past the window's edge, words cut down to
/// an ellipsis not said by the words or a containing `Cut`, less than `squeeze_kept_chars` characters before an
/// ellipsis, words wrapped narrower than a word of them (broken
/// inside it) or than `squeeze_wrap_ems` of their size, a field's placeholder cut so (said its shortest way: Ctx::editor
/// `shorter`), words broken onto lines or cut short only for what shares their row (Ctx::beside_faults).
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
    match b.squeeze_kept() {
      Some((kept, need)) if self.squeeze_words_visible(i) => {
        if kept < squeeze_kept_chars {
          out.push("\{self.named(i)}: its words cut to \{kept} characters (they need \{need.round()})")
        } else if !self.squeeze_cut_said(i) {
          let shown = if b.kind == kind_text {
            match b.tl { Some(tl) => tl.text; None => "" }
          } else {
            match b.rl { Some(rl) => rl.text; None => "" }
          }
          out.push("\{self.named(i)}: its words cut short without saying they may be (showing ‘\{shown}’)")
        }
      }
      _ => ()
    }
    // a field's placeholder cut down to nothing, said its shortest way (Node::hint_shown)
    if b.kind == kind_editor {
      match self.editors.get(b.id).bind(st => b.hint_kept(st.line)) {
        Some((kept, need)) if kept < squeeze_kept_chars =>
          out.push("\{self.named(i)}: its placeholder cut to \{kept} characters (it needs \{need.round()})")
        _ => ()
      }
    }
    // words wrapped narrower than they break: a word broken inside it, a letter or two a line
    if b.kind == kind_text && b.wrap && b.fw > 0.0 && b.text != "" {
      let need = b.squeeze_wrap_w()
      if need > b.fw + squeeze_slack {
        out.push("\{self.named(i)}: its words wrapped \{b.fw.round()} across (they need \{need.round()})")
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
  out + self.beside_faults(seen) + self.view_squeeze_faults()
}

///|
/// Whether the words are actually drawn: looks can fade an ancestor independently of its node's opacity.
fn Ctx::squeeze_words_visible(self : Ctx, i : Int) -> Bool {
  let mut alpha = 1.0
  let mut p = i
  while p >= 0 {
    alpha = alpha * self.nodes[p].opacity
    match self.drawn_entry(p) {
      Some(e) => alpha = alpha * e.look_now().alpha
      None => ()
    }
    p = self.nodes[p].parent
  }
  alpha > 0.01
}

///|
/// Whether each node of the last frame shows (it and all it is in more than transparent).
fn Ctx::squeeze_seen(self : Ctx) -> Array[Bool] {
  let n = self.count
  let seen = Array::make(n, true)
  for i in 0..<n {
    let b = self.nodes[i]
    let p = b.parent
    seen[i] = (p < 0 || p >= n || seen[p]) && b.opacity > 0.01
  }
  seen
}

///|
/// A line may be cut when it says `Cut` or `Fill`, or a containing box says `Cut` or a maximum width.
fn Ctx::squeeze_cut_said(self : Ctx, i : Int) -> Bool {
  let mut k = i
  while k >= 0 && k < self.count {
    let n = self.nodes[k]
    let limited_lines = if k != i {
      false
    } else if n.kind == kind_rich {
      match n.rich { Some(r) => r.max_lines > 0; None => false }
    } else {
      n.max_lines > 0
    }
    if (k == i && n.allow_ellipsis) || limited_lines || n.w is Cut || (k == i && n.w is Fill(_)) || n.max_w < 1.0e9 {
      return true
    }
    // A fixed-width box is the boundary that constrained these words. A `Cut` or maximum on a more distant page
    // cannot say that everything inside this box was meant to be cut.
    if n.w is Px(_) {
      return false
    }
    k = n.parent
  }
  false
}

///|
/// The same check for words made by the window tree. Its drawn scene carries each node's own width and the opacity
/// and scale of what holds it; only nodes visible within the window and the boxes that clip them are inspected.
fn Ctx::view_squeeze_faults(self : Ctx) -> Array[String] {
  let out : Array[String] = []
  guard view_tree() is Some(tree) else { return out }
  let drawn = tree.drawn_held()
  let regions : Array[(Double, Double, Double, Double)] = []
  let visible : Map[@view.NodeId, Bool] = Map::new()
  for (d, parent, _) in drawn {
    let inherited = if parent >= 0 { regions[parent] } else { (0.0, 0.0, self.width, self.height) }
    let region = if parent >= 0 && drawn[parent].0.clips {
      let holder = drawn[parent].0
      (
        dmax(inherited.0, holder.x),
        dmax(inherited.1, holder.y),
        dmin(inherited.2, holder.x + holder.w),
        dmin(inherited.3, holder.y + holder.h),
      )
    } else {
      inherited
    }
    regions.push(region)
    visible[d.id] = d.alpha > 0.01 && d.w > 0.0 && d.h > 0.0 && d.x < region.2 && d.y < region.3 &&
      d.x + d.w > region.0 && d.y + d.h > region.1
  }
  tree.each_drawn_scaled(fn(c, _, _, alpha, _) {
    if c.words == "" || c.words_look.wrap || c.w <= 0.0 || alpha <= 0.01 || !visible.get(c.id).unwrap_or(false) {
      return
    }
    let say = fn(kept : Int, need : Double) {
      if kept < squeeze_kept_chars {
        out.push("window tree ‘\{c.words}’: its words cut to \{kept} characters (they need \{need.round()})")
      } else if !tree.allows_ellipsis(c.id) {
        out.push("window tree ‘\{c.words}’: its words cut short without saying they may be")
      }
    }
    let k = c.words_look
    if c.runs.is_empty() {
      let (size, line, style) = (self.sp(k.size), self.sp(k.line), view_words_style())
      let whole = layout_text(c.words, size, k.weight, 1.0e9, false, line~, style~)
      if whole.w > c.w + 0.5 {
        let shown = ellipsized(c.words, whole, c.w, fn(s) { layout_text(s, size, k.weight, 1.0e9, false, line~, style~) })
        say(shown.shaped.starts.length() - 1, whole.w)
      }
    } else {
      let rich = view_rich(c.runs, k)
      let whole = layout_rich(rich, 1.0e9)
      if whole.w > c.w + 0.5 {
        let cut = cut_rich({ ..rich, max_lines: 1 }, whole, c.w)
        let shown = layout_rich(cut, 1.0e9)
        say(shown.starts.length() - 1, whole.w)
      }
    }
  })
  out
}

///|
/// Words on one line cut short with an ellipsis (Ctx::text's, Ctx::rich's): how many characters of them show before it,
/// and how wide all of them are (said their shortest way: Ctx::text `shorter`); None where they are not cut.
fn Node::squeeze_kept(self : Node) -> (Int, Double)? {
  if !self.one_line_words() || self.fw <= 0.0 {
    return None
  }
  // (the ellipsis is the last of what shows)
  match (self.tl, self.full, self.rcut, self.rl) {
    (Some(shown), Some(whole), _, _) if self.kind == kind_text => {
      let need = self.one_line_least_w()
      if shown.text != whole.text && shown.text.has_suffix("…") && !self.shorter.contains(shown.text) {
        Some((shown.shaped.starts.length() - 1, need))
      } else {
        None
      }
    }
    (_, _, Some(_), Some(shown)) if self.kind == kind_rich => Some((shown.starts.length() - 1, self.rl_whole))
    _ => None
  }
}

///|
/// A field's placeholder cut short with an ellipsis, laid out in its `line` (Node::hint_shown): how many characters of
/// it show before it, and how wide it is said its shortest way; None where it is not cut, or the field has none.
fn Node::hint_kept(self : Node, line : Double) -> (Int, Double)? {
  if self.text == "" || self.fw <= 0.0 {
    return None
  }
  let shortest = match self.shorter {
    [.., last] => last
    [] => self.text
  }
  let need = self.hint_lay(line)(shortest).w
  if need <= self.fw - self.pad_l - self.pad_r + squeeze_slack {
    return None
  }
  Some((self.hint_shown(line).shaped.starts.length() - 1, need))
}

///|
/// The least words wrapped onto lines are laid across without being squeezed: their longest word (between spaces),
/// `squeeze_wrap_ems` of their size where they break anywhere (a wide character: Chinese, Japanese, Korean), all of
/// them where that is less.
fn Node::squeeze_wrap_w(self : Node) -> Double {
  let mut widest = 0.0
  let mut word = StringBuilder::new()
  let mut in_word = false
  // (a word ends where a line may: a space, a zero-width space, a CJK character)
  for ch in self.text + " " {
    if ch == ' ' || ch == '\n' || ch == '\t' || ch == '\u{200B}' || ch.to_int() >= 0x2E80 {
      if in_word {
        widest = dmax(widest, text_advance(word.to_string(), size=self.font_size, weight=self.weight))
        word = StringBuilder::new()
        in_word = false
      }
    } else {
      word.write_char(ch)
      in_word = true
    }
  }
  dmin(self.text_layout(1.0e9).w, dmax(widest, squeeze_wrap_ems * self.font_size))
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
  self.layer || self.portal || self.pager != 0 || self.placed_at() || self.moved_off()
}

///|
/// How far a node runs past the edges of a window `w` wide (below 0: inside it).
fn Node::squeeze_past(self : Node, w : Double) -> Double {
  dmax(self.x + self.fw - w, -self.x)
}

///|
/// Words broken onto lines, or cut short, only for what shares their row after them (in the frame's nodes `seen`, none
/// of it in what scrolls sideways): laid in the room what is at the row's end takes as well, they would be one line,
/// whole. A line shared with what is at a row's end holds words of a length known that fit beside it; words of no
/// length known stand on a line of their own (what stands before them, a mark's or a face's column, a table's labels,
/// is their row's own column: its lines stand after it). Words said to be cut short there (`w=Cut`, theirs or a box's they are in on the
/// way to that row: a name, beside a time or a count) may be.
fn Ctx::beside_faults(self : Ctx, seen : Array[Bool]) -> Array[String] {
  let out : Array[String] = []
  let n = self.count
  let apart = Array::make(n, false)
  for i in 0..<n {
    let p = self.nodes[i].parent
    if p >= 0 && p < n {
      apart[i] = apart[p] || self.nodes[p].sideways
    }
  }
  for i in 0..<n {
    let b = self.nodes[i]
    guard b.kind == kind_text && b.text != "" && b.fw > 0.0 && seen[i] && !apart[i] else { continue }
    guard b.tl is Some(shown) else { continue }
    let lines = shown.line_start.length()
    let wrapped = b.wrap && lines > 1
    let cut = !b.wrap &&
      (match b.full {
        Some(f) => f.w > b.fw + squeeze_slack
        None => false
      })
    guard wrapped || cut else { continue }
    // the room taken by what else shows in the nearest row it shares (not one that goes on in lines: what does not fit
    // there has a line of its own)
    // (words said to be cut short, or in a box that is, there: `w=Cut`)
    let mut k = i
    let mut p = b.parent
    let mut spare = 0.0
    let mut said_cut = b.w is Cut
    while p >= 0 && p < n {
      let a = self.nodes[p]
      if a.squeeze_cuts() {
        break
      }
      if a.dir == Row && !a.flow && self.shows_after(k) {
        let on = self.nodes[k]
        spare = if a.rtl {
          on.x - on.mar_l - (a.x + a.pad_l)
        } else {
          a.x + a.fw - a.pad_r - (on.x + on.fw + on.mar_r)
        }
        break
      }
      k = p
      p = a.parent
      said_cut = said_cut || a.w is Cut
    }
    let alone = dmin(b.fw + spare, b.max_w)
    guard !(cut && said_cut) && spare > squeeze_slack && alone > b.fw + squeeze_slack else { continue }
    let tl = layout_text(
      b.text,
      b.font_size,
      b.weight,
      alone,
      b.wrap,
      line=b.line_h,
      trim=b.line_trim,
      spacing=b.spacing,
      style=b.words_style(),
    )
    if wrapped && tl.line_start.length() == 1 {
      out.push("\{self.named(i)}: \{lines} lines for what shares their row (alone there, one: \{tl.w.round()} of \{alone.round()})")
    } else if cut && tl.w <= alone + squeeze_slack {
      out.push("\{self.named(i)}: cut short for what shares their row (alone there, whole: \{tl.w.round()} of \{alone.round()})")
    }
  }
  out
}

///|
/// Whether something shows after node `k` in the row it is in (at its end: what stands before it is the row's own
/// column, a mark's, a face's, a table's labels'), in its flow, drawn or holding what is; not another share of the row
/// where `k` is one (a grid's next column, a tile beside a tile: its words' room is their own share).
fn Ctx::shows_after(self : Ctx, k : Int) -> Bool {
  let shared = self.nodes[k].w is Fill(_)
  let mut ch = self.nodes[k].next
  while ch >= 0 {
    let cn = self.nodes[ch]
    if !cn.squeeze_aside() && cn.fw > squeeze_slack && cn.opacity > 0.01 && (cn.first >= 0 || cn.squeeze_shows()) &&
      !(shared && cn.w is Fill(_)) {
      return true
    }
    ch = cn.next
  }
  false
}

///|
/// The words of the last frame broken or cut short only for what shares their row (Ctx::beside_faults), a line each:
/// those squeeze_faults says among the rest.
pub fn Tester::beside_faults(self : Tester) -> Array[String] {
  ignore(self)
  let c = g()
  c.beside_faults(c.squeeze_seen())
}
