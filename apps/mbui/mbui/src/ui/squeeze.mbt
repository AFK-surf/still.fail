// What the last frame laid out in less room than it needs, as it shows (Tester::squeeze_faults): two things side by
// side drawn over each other, something cut off by the window's edge, words cut without saying they may be or cut down
// to nothing, words wrapped a letter or two a line, a field's placeholder cut down to nothing, words broken or cut
// short only for what shares their row.
// Room runs short by design in four ways only, none of them a fault: words said a shorter way (Ctx::text's, a field's
// placeholder's: `shorter`), words cut short with an ellipsis (keeping some of them; for what is beside them, only
// those said to be: `w=Cut`; the window tree's, Tree::allows_ellipsis, by the app alone, never by the bound the
// framework puts on one line of words in a column, for both), what a row says may go left out of it (Ctx::box `drop`, into its
// ⋯ where it has one), what scrolls or is cut by its own box (a list, a scroll, `sideways`, `clip`). What overlaps on
// purpose says so: a margin below 0 (faces in a stack), a layer, something put where it is said, or drawn where its
// own move says (the window tree's: an offset bound, View::moved_by).
// The window tree's nodes are held to these rules as an old view's are, put among the frame's (squeeze_tree.mbt).
//
// Controls neither scroll sideways nor wrap (the user, 2026-10-25: both ugly). The last-resort cutting is so the
// worst case stays readable (2026-10-26: 「保证在最差的情况下也没有现在这么差」). Words of uncertain length get
// their own line (2026-10-26: 「如果文字长度是不可确定的，那就应该尽量让它独立」).

///|
/// How far two things may run into each other, or past the window, and still be apart: the layout's rounding.
let squeeze_slack : Double = 1.0

///|
/// The fewest characters a note's last line may hold where it goes on in lines beside a control (sub_lines_beside):
/// fewer, a letter or two alone on a line, is said as the row squeezing it.
let squeeze_last_chars : Int = 3

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
/// `shorter`), words broken onto lines or cut short only for what shares their row (Ctx::beside_faults). The old views'
/// nodes and the window tree's alike, by the same rules: the tree's as squeeze_tree.mbt puts them among the frame's
/// (Ctx::tree_squeeze_said), each saying where it was made.
pub fn Tester::squeeze_faults(self : Tester) -> Array[String] {
  self.reads_own()
  ignore(self)
  g().squeeze_faults()
}

///|
fn Ctx::squeeze_faults(self : Ctx) -> Array[String] {
  self.squeeze_said().map(fn(f) { f.1 }) + self.beside_faults(self.squeeze_seen()) + self.tree_squeeze_said()
}

///|
/// What of the frame's nodes Ctx::squeeze_faults says but for what shares a row (Ctx::beside_said), each with the node
/// it is said of (two drawn over each other: the box they are in). The window tree's nodes among them where they are
/// put there (Ctx::with_tree_nodes with its `facts`): Ctx::tree_squeeze_said.
fn Ctx::squeeze_said(self : Ctx) -> Array[(Int, String)] {
  let out : Array[(Int, String)] = []
  let n = self.count
  // what each node draws, with what it holds, as far as it shows (x0, y0, x1, y1; x0 > x1: nothing), and whether it
  // is in what cuts or scrolls what it holds (a box past its edges is not cut off by the window, but by that)
  let ext = Array::make(n * 4, 0.0)
  for i in 0..<n {
    let b = self.nodes[i]
    if self.squeeze_shows_at(i) {
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
    if p < 0 || p >= n || self.squeeze_aside_at(i) || b.opacity <= 0.01 || ext[i * 4] > ext[i * 4 + 2] {
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
  // where each node may be seen at all, by the boxes that clip round it (x0, y0, x1, y1), and whether it is drawn off its
  // place on purpose inside the nearest of them (it, or what holds it there: Ctx::squeeze_aside_at): words so moved
  // wholly out of sight are not judged as cut (on their way in or out, over what holds them); words laid in the flow
  // and clipped away are, and what lies past the window's edge with nothing clipping it
  let sight = Array::make(n * 4, 0.0)
  let moved = Array::make(n, false)
  for i in 0..<n {
    let b = self.nodes[i]
    let p = b.parent
    if p >= 0 && p < n {
      let a = self.nodes[p]
      cut[i] = cut[p] || a.squeeze_cuts()
      seen[i] = seen[p] && b.opacity > 0.01
      // (what scrolls across shows what it holds as it is scrolled; what is drawn at another size than it is laid out at
      // clips its words where they are drawn, not laid out: as `room` below)
      if a.sideways || self.squeeze_scaled(p) {
        sight[i * 4] = -1.0e9
        sight[i * 4 + 1] = -1.0e9
        sight[i * 4 + 2] = 1.0e9
        sight[i * 4 + 3] = 1.0e9
      } else {
        for j in 0..<4 {
          sight[i * 4 + j] = sight[p * 4 + j]
        }
      }
      if a.clip && !a.sideways && !self.squeeze_scaled(p) {
        sight[i * 4] = dmax(sight[i * 4], a.x)
        sight[i * 4 + 1] = dmax(sight[i * 4 + 1], a.y)
        sight[i * 4 + 2] = dmin(sight[i * 4 + 2], a.x + a.fw)
        sight[i * 4 + 3] = dmin(sight[i * 4 + 3], a.y + a.fh)
      }
      moved[i] = self.squeeze_aside_at(i) || (!a.clip && moved[p])
      // (what scrolls sideways may run past its edges; a list or a scroll runs up and down, and cuts across as a box
      // that clips does)
      // (nor what is drawn at another size than it is laid out at, a picture of a page drawn small: what holds it cuts
      // it as drawn, its words lie where they are laid out)
      if a.sideways || self.squeeze_scaled(p) {
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
      moved[i] = self.squeeze_aside_at(i)
      sight[i * 4] = -1.0e9
      sight[i * 4 + 1] = -1.0e9
      sight[i * 4 + 2] = 1.0e9
      sight[i * 4 + 3] = 1.0e9
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
      Some((kept, need)) if self.squeeze_words_visible(i) &&
        !(
          moved[i] &&
          (
            b.x >= sight[i * 4 + 2] ||
            b.y >= sight[i * 4 + 3] ||
            b.x + b.fw <= sight[i * 4] ||
            b.y + b.fh <= sight[i * 4 + 1]
          )
        ) => {
        if kept < squeeze_kept_chars {
          out.push((i, "\{self.named(i)}: its words cut to \{kept} characters (they need \{need.round()})"))
        } else if !self.squeeze_cut_said(i) {
          let shown = if b.kind == kind_text {
            match b.tl { Some(tl) => tl.text; None => "" }
          } else {
            match b.rl { Some(rl) => rl.text; None => "" }
          }
          out.push((i, "\{self.named(i)}: its words cut short without saying they may be (showing ‘\{shown}’)"))
        }
      }
      _ => ()
    }
    // a field's placeholder cut down to nothing, said its shortest way (Node::hint_shown)
    // (a field of the window's tree's as it is placed: Ctx::tree_field_box)
    if b.kind == kind_editor {
      let kept = match tree_field_boxes.get(i) {
        Some(fb) => fb.hint_kept()
        None => self.editors.get(b.id).bind(_ => b.hint_kept())
      }
      match kept {
        Some((kept, need)) if kept < squeeze_kept_chars =>
          out.push((i, "\{self.named(i)}: its placeholder cut to \{kept} characters (it needs \{need.round()})"))
        _ => ()
      }
    }
    // words wrapped narrower than they break: a word broken inside it, a letter or two a line
    if b.kind == kind_text && b.wrap && b.fw > 0.0 && b.text != "" {
      let need = b.squeeze_wrap_w()
      if need > b.fw + squeeze_slack {
        out.push((i, "\{self.named(i)}: its words wrapped \{b.fw.round()} across (they need \{need.round()})"))
      }
    }
    // the outermost box that runs past the window's edge, partly in it, where nothing it is in cuts it
    if !cut[i] && b.fw > 0.0 && b.x < w && b.x + b.fw > 0.0 {
      let past = b.squeeze_past(w)
      let p = b.parent
      let parent_past = p >= 0 && p < n && self.nodes[p].squeeze_past(w) > squeeze_slack
      if past > squeeze_slack && !parent_past && !self.squeeze_aside_at(i) {
        out.push((i, "\{self.named(i)} runs \{past.round()} past the window's edge"))
      }
    }
    // words, or what is pressed, cut off part way by a box that clips round it: the outermost so
    let words = (b.kind == kind_text || b.kind == kind_rich) && (b.text != "" || b.rich is Some(_))
    let pressed = b.kind == kind_box && b.id != 0 && b.hit
    if (words || pressed) && b.fw > 0.0 && !self.squeeze_aside_at(i) {
      let (lo, hi) = (room[i * 2], room[i * 2 + 1])
      let off = dmax(lo - b.x, b.x + b.fw - hi)
      let p = b.parent
      if off > squeeze_slack && b.x < hi && b.x + b.fw > lo && !(p >= 0 && p < n && said[p]) {
        said[i] = true
        out.push((i, "\{self.named(i)} is cut off \{off.round()} by what clips it"))
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
      if !self.squeeze_aside_at(k) && ext[k * 4] <= ext[k * 4 + 2] {
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
          out.push((i, "\{self.named(a)} and \{self.named(c)} overlap by \{by.round()}, in \{self.named(i)}"))
        }
      }
    }
  }
  out
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
/// A line may be cut when it says `Cut` or `Fill`, or a containing box says `Cut` or a maximum width (the window
/// tree's the same: Tree::allows_ellipsis).
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
/// A field's placeholder cut short with an ellipsis, laid out as it shows (Node::hint_shown): how many characters of
/// it show before it, and how wide it is said its shortest way; None where it is not cut, or the field has none.
fn Node::hint_kept(self : Node) -> (Int, Double)? {
  self.field_box().hint_kept()
}

///|
/// The same of the field placed as `b`, an old view's or the window tree's (Ctx::tree_field_box).
fn FieldBox::hint_kept(self : FieldBox) -> (Int, Double)? {
  if self.hint == "" || self.w <= 0.0 {
    return None
  }
  let shortest = match self.shorter {
    [.., last] => last
    [] => self.hint
  }
  let need = self.hint_lay()(shortest).w
  if need <= self.w - self.pad_l - self.pad_r + squeeze_slack {
    return None
  }
  Some((self.hint_shown().shaped.starts.length() - 1, need))
}

///|
/// The least words wrapped onto lines are laid across without being squeezed: their longest word (between spaces),
/// `squeeze_wrap_ems` of their size where they break anywhere (a wide character: Chinese, Japanese, Korean), all of
/// them where that is less.
fn Node::squeeze_wrap_w(self : Node) -> Double {
  let mut widest = 0.0
  let mut word = StringBuilder()
  let mut in_word = false
  // (a word ends where a line may: a space, a zero-width space, a CJK character)
  for ch in self.text + " " {
    if ch == ' ' || ch == '\n' || ch == '\t' || ch == '\u{200B}' || ch.to_int() >= 0x2E80 {
      if in_word {
        widest = dmax(widest, text_advance(word.to_string(), size=self.font_size, weight=self.weight))
        word = StringBuilder()
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
/// Whether node `i` draws something of its own (Node::squeeze_shows); a node of the window's tree's, what it draws besides
/// a ground or words too, its picture, drawing, glass or shadow among it, as Content::draws says (tree_draws_at).
fn Ctx::squeeze_shows_at(self : Ctx, i : Int) -> Bool {
  let b = self.nodes[i]
  b.squeeze_shows() || (tree_draws_at.contains(i) && b.fw > 0.0 && b.fh > 0.0 && b.opacity > 0.01)
}

///|
/// Whether a node cuts or scrolls what it holds, which may then lie past its edges: a list, a scroll, what scrolls
/// sideways, a box that clips.
fn Node::squeeze_cuts(self : Node) -> Bool {
  self.clip || self.sideways || self.kind == kind_list || self.kind == kind_scroll || self.kind == kind_page
}

///|
/// Whether node `i` is drawn at another size than it is laid out at (its look scales it).
fn Ctx::squeeze_scaled(self : Ctx, i : Int) -> Bool {
  // (a node of the window's tree's drawn another size than what holds it: View::scale, Ctx::with_tree_nodes `facts`)
  if tree_scaled_at.contains(i) {
    return true
  }
  match self.drawn_entry(i) {
    Some(e) => {
      let l = e.look_now()
      l.sx != 1.0 || l.sy != 1.0
    }
    None => false
  }
}

///|
/// Whether a node lies apart from its parent's flow, over what is beside it on purpose: a layer, one put where it
/// is said, what is over the whole window, one drawn moved off its place (`tx`, `ty`: a face over the one
/// before it, something on its way).
fn Node::squeeze_aside(self : Node) -> Bool {
  self.layer || self.portal || self.placed_at() || self.moved_off()
}

///|
/// Whether node `i` lies apart from its parent's flow on purpose (Node::squeeze_aside); a node of the window's tree's, where
/// it is drawn its own to say too, whatever its move comes to now (tree_moved_at: squeeze_tree.mbt's head).
fn Ctx::squeeze_aside_at(self : Ctx, i : Int) -> Bool {
  self.nodes[i].squeeze_aside() || tree_moved_at.contains(i)
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
  self.beside_said(seen).map(fn(f) { f.1 })
}

///|
/// What Ctx::beside_faults says, each with the node it is said of (the words).
fn Ctx::beside_said(self : Ctx, seen : Array[Bool]) -> Array[(Int, String)] {
  let out : Array[(Int, String)] = []
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
    if b.wrap {
      match self.gives_beside(i) {
        Some(o) => {
          out.push(
            (
              i,
              "\{self.named(i)}: may go on in lines beside \{self.named(o)}, after it in their row, which gives way too: how far each gives is the other's length (a short name broken beside long words)",
            ),
          )
          continue
        }
        None => ()
      }
    }
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
    // (a note under a title beside a control across their middle takes the lines the row leaves it: sub_lines_beside;
    // not a letter or two left on a line of its own)
    let left = b.text.length() - shown.line_start[lines - 1]
    if wrapped && tl.line_start.length() == 1 && !(left >= squeeze_last_chars && self.sub_lines_beside(i)) {
      out.push((i, "\{self.named(i)}: \{lines} lines for what shares their row (alone there, one: \{tl.w.round()} of \{alone.round()})"))
    } else if cut && tl.w <= alone + squeeze_slack {
      out.push((i, "\{self.named(i)}: cut short for what shares their row (alone there, whole: \{tl.w.round()} of \{alone.round()})"))
    }
  }
  out
}

///|
/// What shows after words `i` that may go on in lines, in the nearest row they share (not one that goes on in lines),
/// and gives way there as well: a row short of room squeezes both, each by the other's length, so short words (a
/// station's name) are broken onto lines beside long ones (what its machine is) that could have been cut instead,
/// whatever the fixture's words. Nothing when the words, or a box on their way to that row, keep their own width
/// (`keep`, `Px`) or are said to give way first (`w=Cut`), when they share a column with more (what is beside it is
/// not on their line), or when what is after them in that row keeps its own.
fn Ctx::gives_beside(self : Ctx, i : Int) -> Int? {
  let n = self.count
  let mut k = i
  let mut p = self.nodes[i].parent
  while p >= 0 && p < n {
    let on = self.nodes[k]
    if on.keep || on.w is Px(_) || on.w is Cut {
      return None
    }
    let a = self.nodes[p]
    // (a box that cuts what it holds still squeezes it in its row; one that scrolls has the room)
    if a.sideways || a.kind == kind_list || a.kind == kind_scroll || a.kind == kind_page {
      return None
    }
    if a.dir == Row && !a.flow {
      let shared = on.w is Fill(_)
      let mut ch = on.next
      while ch >= 0 {
        let cn = self.nodes[ch]
        if !(shared && cn.w is Fill(_)) && cn.fw > squeeze_slack && cn.least + squeeze_slack < cn.fw &&
          self.squeeze_gives(ch) {
          return Some(ch)
        }
        ch = cn.next
      }
      return None
    }
    // (a column holding more than them: what is beside it is beside the column, not on their line)
    if a.first != k || on.next >= 0 {
      return None
    }
    k = p
    p = a.parent
  }
  None
}

///|
/// Whether node `k`, shown, gives way where its row is short of room: words in it that go on in lines or are cut
/// short, nothing on their way keeping its width (`keep`, `Px`).
fn Ctx::squeeze_gives(self : Ctx, k : Int) -> Bool {
  let b = self.nodes[k]
  if b.keep || b.w is Px(_) || self.squeeze_aside_at(k) || b.opacity <= 0.01 || b.fw <= squeeze_slack {
    return false
  }
  if b.kind == kind_text {
    return b.text != "" && (b.wrap || b.w is Cut)
  }
  let mut ch = b.first
  while ch >= 0 {
    if self.squeeze_gives(ch) {
      return true
    }
    ch = self.nodes[ch].next
  }
  false
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
    if !self.squeeze_aside_at(ch) && cn.fw > squeeze_slack && cn.opacity > 0.01 && (cn.first >= 0 || self.squeeze_shows_at(ch)) &&
      !(shared && cn.w is Fill(_)) {
      return true
    }
    ch = cn.next
  }
  false
}

///|
/// Whether words `i` that go on in lines are a line under a title (in a column of words, after what stands over them)
/// beside what keeps its width standing across the middle of the whole column, not on their line (a switch, a
/// button at a row's end, across the middle of a title and its note: settings' rows, @sf.switch_row): there they
/// may take the lines the row leaves them, as a note beside a control does. A title itself, words beside words that
/// give way too, or what is on the line of its words are not.
fn Ctx::sub_lines_beside(self : Ctx, i : Int) -> Bool {
  let n = self.count
  let mut k = i
  let mut p = self.nodes[i].parent
  let mut under = false
  while p >= 0 && p < n {
    let a = self.nodes[p]
    if a.sideways || a.kind == kind_list || a.kind == kind_scroll || a.kind == kind_page {
      return false
    }
    if a.dir == Row && !a.flow {
      guard under else { return false }
      let words = self.nodes[k]
      let middle = words.y + words.fh / 2.0
      let mut beside = false
      let mut ch = words.next
      while ch >= 0 {
        let cn = self.nodes[ch]
        if !self.squeeze_aside_at(ch) && cn.fw > squeeze_slack && cn.opacity > 0.01 && (cn.first >= 0 || self.squeeze_shows_at(ch)) {
          // (what gives way too, or stands on a line of the words, not across their middle: as before)
          if self.squeeze_gives(ch) || cn.fh + squeeze_slack >= words.fh ||
            (cn.y + cn.fh / 2.0 - middle).abs() > squeeze_slack {
            return false
          }
          beside = true
        }
        ch = cn.next
      }
      return beside
    }
    // (in a column of words after a title shown over them: words, not only room or what is hidden)
    let mut over = a.first
    while over >= 0 && over != k && !under {
      under = self.shows_words(over)
      over = self.nodes[over].next
    }
    k = p
    p = a.parent
  }
  false
}

///|
/// Whether node `k` shows words: words of its own or in what it holds, drawn, not apart from the flow.
fn Ctx::shows_words(self : Ctx, k : Int) -> Bool {
  let b = self.nodes[k]
  if self.squeeze_aside_at(k) || b.opacity <= 0.01 || b.fw <= squeeze_slack || b.fh <= squeeze_slack {
    return false
  }
  if b.kind == kind_text {
    return b.text.trim().length() > 0
  }
  let mut ch = b.first
  while ch >= 0 {
    if self.shows_words(ch) {
      return true
    }
    ch = self.nodes[ch].next
  }
  false
}

///|
/// The words of the last frame broken or cut short only for what shares their row (Ctx::beside_faults), a line each:
/// those squeeze_faults says among the rest.
pub fn Tester::beside_faults(self : Tester) -> Array[String] {
  self.reads_own()
  ignore(self)
  let c = g()
  c.beside_faults(c.squeeze_seen()) + c.tree_squeeze_said(beside=true)
}
