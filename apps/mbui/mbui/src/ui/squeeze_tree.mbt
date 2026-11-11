// The squeeze's rules (squeeze.mbt) held to the window's tree: its nodes put among the frame's as they are drawn
// (Ctx::with_tree_nodes with `facts`), each told what an old view's node says of how it is laid out, read off the tree
// (Tree::laid_facts), and its words as the tree draws them; then the same rules say the same lines of it
// (Ctx::squeeze_said, Ctx::beside_said). What they say of a node of the tree is the tree's; what they say of an old
// view's node, the old view's own run says (Ctx::squeeze_faults, without the tree), not this. Run only as a check
// asks (Tester::squeeze_faults, a drive's `squeeze`): nothing of it is kept on a node, or done as a frame is.
//
// Each of an old view's node's facts, and the tree's it is read from:
// - `dir`, `rtl`, `flow`: how it lays out what it holds (View::row, a direction reversed, View::wraps);
// - `pad_*`, `mar_*`: View::padding, View::margin;
// - `w`: `Px` where its width is said in points (the boundary either way: Tree::allows_ellipsis stops there as
//   Ctx::squeeze_cut_said does); `Fill` where it grows along the row it is in (View::grow: an old view's Fill is its
//   share of the row's room, flex's grow; in a column a tree's grow is down it, nothing of its width); `Pct` where it is a
//   share of what holds it (View::width_share: CSS's width in percent either way; how much, none of the rules reads);
//   else `Auto`. Never `Cut` on a box: whether words may be cut short is said once, Tree::allows_ellipsis (#5258,
//   #5269: the app's say alone, not the framework's bound on one line of words in a column, not a holder's giving
//   way), and its answer of the box they are in is their node's `Cut` and `allow_ellipsis` alike (below), so what
//   says words may be cut ((a), Ctx::squeeze_cut_said) and words said to be cut short beside what shares their row
//   ((g), Ctx::beside_said, Ctx::gives_beside) read the one answer;
// - `keep`: View::keeps_held (never narrower along its row than what it holds needs: an old view's keep);
// - `least`: as the layout takes it (laid_facts.mbt's head): as wide as it is laid out where it never gives way
//   (shrink 0), else how narrow it is said it may be (View::min_width; within: no more than what holds it gives
//   inside its padding), else its padding across;
// - `max_w`: View::max_width;
// - drawn apart from the flow on purpose (Ctx::squeeze_aside_at): `layer`, laid over what holds it (View::over);
//   placed where it is said (`at_*`): beside another (View::beside), or put by its insets otherwise; `tx`, `ty`: drawn
//   off its place now (View::offset, View::moved_by); and where it is drawn its own to say, whatever that comes to now
//   (an offset bound to what moves it, what moves it said: LaidFacts' `moves_own`, tree_moved_at), as an old view's
//   `tx` is, read as said rather than as how far it is off at the moment: what is at rest at 0, a tape of panels side by
//   side wider than the window, lies where its own move says, past the window's edge or not;
// - a list's or a scroll's kind (`kind_scroll`) where it scrolls up and down, `sideways` where it scrolls across
//   (View::scrolls);
// - `opacity`: its own (the tree's composed one over what holds it's);
// - what it draws of its own besides a ground or words (a picture, a drawing, glass, a shadow, an old view hosted in
//   it: Content::draws), tree_draws_at, as an old view's node's shapes and lines are;
// - its words (a node of their own in it, as Ctx::with_tree_nodes puts them): set and laid out as the tree draws them
//   (view_host's: their size, line, letters' spacing, digits, balance, how many lines at most; what is drawn of them,
//   View::shorter's way of saying them chosen, one line cut with an ellipsis, lines cut after the last of those they
//   say, as `max_lines`); said they may be cut as Tree::allows_ellipsis says, both as `allow_ellipsis` and, on one
//   line, as `w=Cut` (on lines they are never cut short across);
// - a field (ui's field): its placeholder as the field is placed (Ctx::tree_field_box), held as an old view's.
// What an old view's node says that no node of the tree does, none of it read: `drop`'s ⋯ (a row's View::drops is,
// but the squeeze reads neither), `portal` (the tree's layers are what the root holds), `in_sideways`.

///|
/// The fields of the window's tree among the frame's nodes, as each is placed (Ctx::with_tree_nodes `facts`), by
/// their node there.
// kept across runs: filled and emptied round one asking of the squeeze (Ctx::with_tree_nodes)
let tree_field_boxes : Map[Int, FieldBox] = Map([])

///|
/// The nodes of the window's tree among the frame's drawn another size than what holds them (View::scale).
// kept across runs: filled and emptied round one asking of the squeeze (Ctx::with_tree_nodes)
let tree_scaled_at : Set[Int] = Set([])

///|
/// The first of the frame's nodes put there for the window's tree's (Ctx::with_tree_nodes `facts`), -1 none.
// kept across runs: set round one asking of the squeeze (Ctx::with_tree_nodes)
let tree_nodes_from : Ref[Int] = Ref(-1)

///|
/// The nodes of the window's tree among the frame's that draw something of their own besides a ground or words
/// (Content::draws: a picture, a drawing, glass, a shadow, an old view hosted in it), what Ctx::squeeze_shows_at reads
/// of them as it reads an old view's node's shapes and lines.
// kept across runs: filled and emptied round one asking of the squeeze (Ctx::with_tree_nodes)
let tree_draws_at : Set[Int] = Set([])

///|
/// The nodes of the window's tree among the frame's where they are drawn is their own to say (LaidFacts' `moves_own`):
/// apart from the flow on purpose, as an old view's node drawn off its place is (Ctx::squeeze_aside_at).
// kept across runs: filled and emptied round one asking of the squeeze (Ctx::with_tree_nodes)
let tree_moved_at : Set[Int] = Set([])

///|
/// The nodes of the window's tree among the frame's whose height is said in points (LaidFacts' `height_points`), as an
/// old view's node's `h=Px` is: what Ctx::fixed_outgrown holds the words in them to.
// kept across runs: filled and emptied round one asking of the squeeze (Ctx::with_tree_nodes)
let tree_fixed_h_at : Set[Int] = Set([])

///|
/// Node `n`, put among the frame's as node `i` for the window's tree's drawn `d` (in `holder`, drawn), told how it is
/// said to be laid out, what it draws and how opaque it is of its own (see the file's head).
fn Ctx::tree_facts(
  self : Ctx,
  i : Int,
  n : Node,
  d : @view.Drawn,
  holder : @view.Drawn?,
  contents : Map[Int, (@view.Content, Double)],
  tree : @view.Tree,
) -> Unit {
  ignore(self)
  n.opacity = match holder {
    Some(h) if h.alpha > 0.0 => d.alpha / h.alpha
    _ => d.alpha
  }
  match contents.get(d.id.at) {
    Some((c, _)) =>
      if c.image is Some(_) ||
        c.picture is Some(_) ||
        !c.shapes.is_empty() ||
        !c.lines.is_empty() ||
        c.glass is Some(_) ||
        c.shadow.0 > 0.0 ||
        c.hosted {
        tree_draws_at.add(i)
      }
    None => ()
  }
  if tree_fields.contains(d.id) {
    n.kind = kind_editor
  }
  guard tree.laid_facts(d.id) is Some(f) else { return }
  let held = match holder {
    Some(h) => tree.laid_facts(h.id).map(fn(hf) { (hf, h.w) })
    None => None
  }
  let in_row = match held {
    Some((hf, _)) => hf.row
    None => false
  }
  n.dir = if f.row { Row } else { Column }
  n.rtl = f.row && f.reverse
  n.flow = f.row && f.wraps
  n.pad_l = f.pad.0
  n.pad_t = f.pad.1
  n.pad_r = f.pad.2
  n.pad_b = f.pad.3
  n.mar_l = f.margin.0
  n.mar_t = f.margin.1
  n.mar_r = f.margin.2
  n.mar_b = f.margin.3
  // (never Cut: whether its words may be cut is theirs, Tree::allows_ellipsis's answer, Ctx::tree_words_facts)
  n.w = if f.width_points {
    Px(d.w)
  } else if in_row && f.grow > 0.0 {
    Fill(f.grow)
  } else if f.width_share {
    Pct(100.0)
  } else {
    Auto
  }
  n.keep = f.keeps
  if f.height_points {
    tree_fixed_h_at.add(i)
  }
  // (as the layout takes it: laid_facts.mbt's head)
  n.least = if f.shrink <= 0.0 || f.keeps {
    d.w
  } else if f.min_w.is_nan() {
    f.pad.0 + f.pad.2
  } else if f.min_within {
    match held {
      Some((hf, hw)) => dmin(f.min_w, hw - hf.pad.0 - hf.pad.2)
      None => f.min_w
    }
  } else {
    f.min_w
  }
  n.max_w = if f.max_w < 1.0e9 { f.max_w } else { 1.0e9 }
  n.layer = f.apart == 1
  if f.apart >= 2 {
    n.at_l = 0.0
  }
  n.tx = f.off.0
  n.ty = f.off.1
  if f.moves_own {
    tree_moved_at.add(i)
  }
  n.sideways = f.scrolls == 2
  if f.scrolls == 1 && n.kind == kind_box {
    n.kind = kind_scroll
  }
  n.drop = f.drop
}

///|
/// The words of the window tree's node `d` put among the frame's as node `w` (in its node there), set and laid
/// out as the tree draws them (view_host's words: at its node's size of words, Tree::words_scale_of), said they may be
/// cut as the tree says it (Tree::allows_ellipsis).
fn Ctx::tree_words_facts(
  _self : Ctx,
  w : Node,
  d : @view.Drawn,
  contents : Map[Int, (@view.Content, Double)],
  tree : @view.Tree,
) -> Unit {
  guard contents.get(d.id.at) is Some((c, _)) else { return }
  let k = c.words_look
  let scale = tree.words_scale_of(d.id)
  let (size, line, style, spacing) = (view_sp(scale, k.size), view_line(scale, k), view_words_style(), view_spacing(scale, k))
  w.wrap = k.wrap
  w.balance = k.balance
  w.max_lines = k.max_lines
  w.center = c.words_center
  w.line_h = line
  w.spacing = spacing
  w.tabular = tree_theme().tabular
  // (as big as it is laid out, its words laid out in that: as the tree lays them out and draws them)
  w.fw = c.w
  w.fh = c.h
  w.opacity = 1.0
  // (whether they may be cut short: the one answer, as said they may be (a) and as said to be cut beside what shares
  // their row (g); words on lines are never cut short, so theirs is no `Cut`: what gives way beside them, and they
  // broken onto lines for it, are judged as ever)
  let cut_said = tree.allows_ellipsis(d.id)
  w.allow_ellipsis = cut_said
  w.w = if cut_said && !k.wrap { Cut } else { Auto }
  w.shorter = match tree.laid_facts(d.id) {
    Some(f) => f.shorter.map(fn(s) { view_words_set(s, k, false) })
    None => []
  }
  if c.runs.is_empty() {
    let lay = fn(s : String) { layout_text(s, size, k.weight, 1.0e9, false, line~, style~, spacing~) }
    let shown = view_words_set(c.words_drawn.unwrap_or(c.words), k, c.words_breaks)
    let tl = layout_words(
      shown,
      size,
      k.weight,
      if k.wrap { c.w } else { 1.0e9 },
      k.wrap,
      balance=k.balance,
      line~,
      style~,
      spacing~,
      max_lines=k.max_lines,
    )
    // (cut after the last of the lines it says, as an old view's: Node::text_layout's)
    w.full_cut = k.wrap && k.max_lines > 0 && tl.text != shown
    let tl = if !k.wrap && tl.w > c.w + 0.5 { ellipsized(shown, tl, c.w, lay) } else { tl }
    w.tl = Some(tl)
    w.full = Some(if k.wrap { tl } else { lay(w.text) })
    w.full_max = if k.wrap { c.w } else { 1.0e9 }
  } else {
    w.kind = kind_rich
    w.text = c.words
    let rich = view_rich(c.runs, k, c.runs_look, scale, c.words_breaks)
    let whole = layout_rich(rich, 1.0e9)
    w.rich = Some(rich)
    w.rl_whole = if k.wrap { @double.not_a_number } else { whole.w }
    if runs_over(rich, whole, c.w) {
      let cut = cut_rich({ ..rich, max_lines: 1 }, whole, c.w)
      w.rcut = Some(cut)
      w.rl = Some(layout_rich(cut, 1.0e9))
    } else {
      let lay = layout_rich(rich, if k.wrap { c.w } else { 1.0e9 })
      // (cut after the last of the lines it says it is drawn on, as drawn: view_runs_laid)
      if runs_past(rich, lay) {
        let cut = cut_rich(rich, lay, c.w)
        w.rcut = Some(cut)
        w.rl = Some(layout_rich(cut, c.w))
      } else {
        w.rl = Some(layout_rich(rich, if k.wrap { c.w } else { 1.0e9 }))
      }
    }
  }
}

///|
/// The field of the window's tree drawn `d`, put among the frame's as node `i`, as it is placed (Ctx::tree_field_box).
fn Ctx::tree_field_facts(self : Ctx, i : Int, d : @view.Drawn, contents : Map[Int, (@view.Content, Double)]) -> Unit {
  guard tree_fields.get(d.id) is Some(tf) && contents.get(d.id.at) is Some((c, _)) else { return }
  tree_field_boxes[i] = self.tree_field_box(d.id, tf, d.x, d.y, c.w, c.h)
}

///|
/// Whether node `id` of the window's tree is drawn another size than `holder`, what holds it (View::scale).
fn Ctx::tree_scaled(
  self : Ctx,
  id : @view.NodeId,
  holder : @view.NodeId,
  contents : Map[Int, (@view.Content, Double)],
) -> Bool {
  ignore(self)
  match (contents.get(id.at), contents.get(holder.at)) {
    (Some((_, s)), Some((_, hs))) => (s - hs).abs() > 1.0e-6
    _ => false
  }
}

///|
/// What the squeeze's rules say of the window tree's nodes (see the file's head), each with where it was made; with
/// `beside` alone, what Ctx::beside_said says of them (words broken or cut short for what shares their row).
fn Ctx::tree_squeeze_said(self : Ctx, beside? : Bool = false) -> Array[String] {
  self.with_tree_nodes(facts=true, fn() {
    let from = tree_nodes_from.val
    if from < 0 {
      return []
    }
    let out : Array[String] = []
    let said = self.beside_said(self.squeeze_seen())
    for f in (if beside { said } else { self.squeeze_said() + said }) {
      let (i, line) = f
      if i < from {
        continue
      }
      // (the tree's node: the box, or the box its words are in)
      let id = match tree_frame_ids.get(i) {
        Some(id) => Some(id)
        None => tree_frame_ids.get(self.nodes[i].parent)
      }
      out.push(
        line +
        (match id {
          Some(id) => tree_source_said(id, paren=true)
          None => ""
        }),
      )
    }
    out
  })
}
