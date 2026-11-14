// How a node's words are set and what is drawn round it besides its ground: their size, weight and line, whether they
// wrap (View::words' `look`), their ink as it changes (View::ink); how wide it may grow (View::max_width); the shadow
// it casts (View::shadow), the halo its words are drawn on (View::words_halo). Typed, what hosts the tree draws by them
// (ui's view_made), measured by what it measures with (Tree::new's `measure`).

///|
/// How a node's words are set: their size (points), weight (100 … 900), the height of a line (points, at the system's
/// size of words 1 and scaled with it; 0, the font's own; less than 0, that share of their size as it is drawn, the
/// system's size of words applied: -1.4, 1.4 times it), whether they wrap within
/// the width they are given (else one line, as wide as they are, cut to what it is given ending in an ellipsis where it
/// is given less: View::shrink; what is read out of them all of them).
#derive(Eq, Debug)
pub(all) struct WordsLook {
  size : Double
  weight : Int
  line : Double
  wrap : Bool
  /// how far apart its letters are set besides their own spacing (a large title's tighter)
  tracking : Spacing
  /// wrapped, broken where its lines come out as even as they may on as many lines (ui's TextPatch `balance`: a
  /// note's under a title)
  balance : Bool
  /// wrapped, on so many lines at most (0: as many as they take), the last ending in an ellipsis where they are cut
  /// after it, measured and drawn so (ui's TextPatch `max_lines`, as Ctx::text's and Ctx::rich's); on one line, none of
  /// it. Said in the look, not on the node, so no node that does not say it carries it (2026-11-12)
  max_lines : Int
}

///|
/// How far apart a node's letters are set besides their own spacing (ui's Tracking as it is resolved): a share of
/// their size as it is drawn (the system's size of words applied), so many points whatever their size, or so many
/// points at the system's size of words, made larger by it as a size of their own is (an old view's `tracking` said
/// with its words, Ctx::text: Ctx::sp of it).
#derive(Eq, Debug)
pub(all) enum Spacing {
  Ems(Double)
  Points(Double)
  ScaledPoints(Double)
}

///|
/// Letters as their font sets them, nothing added.
pub let letters_own : Spacing = Ems(0.0)

///|
/// Words as a node set them till they were said to be otherwise: 15 points, regular, 22 a line, wrapped, on as many
/// lines as they take.
pub let words_plain : WordsLook = { size: 15.0, weight: 400, line: 22.0, wrap: true, tracking: letters_own, balance: false, max_lines: 0 }

///|
/// How a node's words in pieces (View::words_runs) are set where a piece says nothing of it itself, as an old view's
/// paragraph is (Ctx::rich's): a link's ink and its ground while it is pressed, code's ink and ground and its share of
/// the words' size, and whether they are a person's words (in the face chosen for those). What changes how big they
/// are (`code_scale`, `words`, whether code has a ground at all: its room either side, a label kept whole on its line)
/// lays them out again; their inks (a ground's colour for another) draw them again alone.
#derive(Eq, Debug)
pub(all) struct RunsLook {
  link : Int64
  pressed : Int64
  code_ink : Int64
  code_ground : Int64
  code_scale : Double
  words : Bool
}

///|
/// Pieces set as an old view's paragraph is where it says nothing of it (Ctx::rich's own).
pub let runs_plain : RunsLook = {
  link: 0x0A84FFFFL,
  pressed: 0x0A84FF29L,
  code_ink: 0L,
  code_ground: 0x7676801FL,
  code_scale: 0.9,
  words: false,
}

///|
/// How its words in pieces are set where a piece says nothing of it itself (RunsLook), as it changes: their sizes
/// (code's share, a person's words' face) laid out again, their inks drawn again alone.
#callsite(autofill(loc))
pub fn View::runs_look(self : View, look : Live[RunsLook], loc~ : SourceLoc) -> View {
  let tree = self.tree
  let at = self.at
  let (set, ink) = match look {
    Is(l) => (Is((l.code_scale, l.words, l.code_ground != 0L)), Is((l.link, l.pressed, l.code_ink, l.code_ground)))
    By(f) =>
      (
        By(fn() {
          let l = f()
          (l.code_scale, l.words, l.code_ground != 0L)
        }),
        By(fn() {
          let l = f()
          (l.link, l.pressed, l.code_ink, l.code_ground)
        }),
      )
  }
  self.bind(loc~, RunsSet, set, Both, fn(s) {
    let l = tree.nodes[at].look.runs_look
    tree.nodes[at].look.runs_look = { ..l, code_scale: s.0, words: s.1 }
    // (how its words are set said: what follows it told, once this is)
    self.words_told()
  })
  self.bind(loc~, RunsInk, ink, Paint, fn(k) {
    let l = tree.nodes[at].look.runs_look
    tree.nodes[at].look.runs_look = { ..l, link: k.0, pressed: k.1, code_ink: k.2, code_ground: k.3 }
    // (code's ground come or gone is its sizes' too (RunsSet's, told before this is written): told again once it is,
    // what follows it reading both as they are now; another colour alone, nothing of how they are laid out)
    if (l.code_ground != 0L) != (k.3 != 0L) {
      self.words_told()
    }
  })
  self
}

///|
/// The link of its words in pieces held (by its first piece, as their runs say it: -1 none), as it changes: its
/// pressed ground (RunsLook's `pressed`) drawn under that link alone.
#callsite(autofill(loc))
pub fn View::runs_pressed(self : View, k : Live[Int], loc~ : SourceLoc) -> View {
  let tree = self.tree
  let at = self.at
  self.bind(loc~, RunsPressed, k, Paint, fn(k) { tree.nodes[at].look.runs_pressed = k })
  self
}

///|
/// What of its words in pieces is picked with the pointer (from, until, in their text's terms; none where the same), as
/// it changes: drawn picked under them alone (what picks them says it: mbui/ui's selection).
#callsite(autofill(loc))
pub fn View::runs_picked(self : View, span : Live[(Int, Int)], loc~ : SourceLoc) -> View {
  let tree = self.tree
  let at = self.at
  self.bind(loc~, RunsPicked, span, Paint, fn(s) { tree.nodes[at].look.runs_picked = s })
  self
}

///|
/// A part of a node's words in pieces marked under them (View::runs_marks): from, until (in their text's terms, as what
/// is picked is), a ground in `ground`, and where `line` is not 0 a line under it in that colour, `line_w` thick at its
/// foot (what is found: each a ground; the one gone to a line under it too); `round` above 0, its ground one a line,
/// round that much at the mark's two ends (its first line's start, its last line's end) and square where it runs on to
/// the next line, as a passage picked is drawn in an old view (a quote's passage lit where it is gone to).
#derive(Eq, Debug)
pub(all) struct RunsMark {
  from : Int
  to : Int
  ground : Int64
  line : Int64
  line_w : Double
  round : Double
}

///|
/// What of its words in pieces is marked under them as it changes, each part its own way (RunsMark): drawn under them
/// and under what is picked of them, laid out with them (as they wrap, as big as they are drawn, where they scroll),
/// taking no press, picking and copying them as ever.
#callsite(autofill(loc))
pub fn View::runs_marks(self : View, marks : Live[Array[RunsMark]], loc~ : SourceLoc) -> View {
  let tree = self.tree
  let at = self.at
  self.bind(loc~, RunsMarks, marks, Paint, fn(m) { tree.nodes[at].look.runs_marks = m })
  self
}

///|
/// What lends what holds it how what of a node's words in pieces is picked with the pointer is said (given the node, as
/// View::words_runs makes it, now or later: its View::runs_picked), as what picks them has it (mbui/ui's selection).
// kept across runs: what each node lends (View::lends), let go with it
pub let runs_picker : Lent[(View) -> Live[(Int, Int)]] = Lent::new()

///|
/// Which row of a list made by its key (View::each) it is in, nearest it, and where it is in that row (its place among
/// what holds it, each from the row down): the same while the row's key is there, whatever is made in it anew where it
/// was; a page's list's row (View::scrolls_window) by its list and its key's number there, whichever node it is made
/// in (the number says which row, never where: given as it is first asked, it is compared, not ordered; where a row is
/// among its list's keys now is View::row_order); the window's root and where it is from it where it is in none.
pub fn View::row_place(self : View) -> (NodeId, Array[Int]) {
  let up : Array[Int] = []
  let mut at = self
  while at.live() is Some(n) && !n.each_row && at.parent() is Some(p) {
    up.push(p.kids().search_by(fn(k) { k.at == at.at }).unwrap_or(0))
    at = p
  }
  // (a page's list's row, or the block made in it (marked as an each's row is): known by its key's number in that list,
  // whatever node it is made in, read as its key is (a block taken for another key is that key's row from then))
  match self.tree.rows_named.get(at.at) {
    Some((list, number, _)) => {
      up.push(number())
      (list, up.rev())
    }
    None => (at.id(), up.rev())
  }
}

///|
/// Where a page's list's row (a row of View::scrolls_window, `self` that row's node) is among the list's keys now; none
/// for any other node: the order its rows are in, whichever of them are made.
pub fn View::row_order(self : View) -> Int? {
  // (a row's node is marked so: no other node looked up)
  guard self.live() is Some(n) && n.each_row else { return None }
  self.tree.rows_named.get(self.at).map(fn(r) { (r.2)() })
}

///|
/// What of its words in pieces is picked with the pointer as it is said now (View::runs_picked).
pub fn View::runs_picked_now(self : View) -> (Int, Int) {
  guard self.live() is Some(n) else { return (0, 0) }
  n.look.runs_picked
}

///|
/// Where the pointer is in its own terms (where it is drawn now, as big as it is drawn), as the tree last had it; None
/// where the tree has it nowhere (gone from the window) or it is let go. Read once, not followed (what is under it worked out as things are placed: View::pointer_piece).
pub fn View::pointer_here(self : View) -> (Double, Double)? {
  guard self.alive() else { return None }
  self.tree.pointer_in(self.at)
}

///|
/// Where the pointer is in node `at`'s own terms as it was last placed (its holders' place and scale with it); None
/// where it is nowhere.
fn Tree::pointer_in(self : Tree, at : Int) -> (Double, Double)? {
  let (px, py) = self.pointer_xy
  if px < 0.0 || py < 0.0 || self.nodes.length() == 0 || self.last_w <= 0.0 {
    return None
  }
  let (x, y, s) = self.placed(at)
  let s = if s > 0.0 { s } else { 1.0 }
  Some(((px - x) / s, (py - y) / s))
}

///|
/// Which piece of it the pointer is over (a link of its words'), as `piece` says from where the pointer is in its own
/// terms (-1: none of them; -1 too where the pointer is nowhere), followed: worked out by the tree as the pointer moves
/// and as anything is placed or laid out (it or what holds it moved, grown, its words set again under a pointer that
/// stays where it is), as what the pointer is within is (Tree::withins_told), and told only as that comes out
/// otherwise. `piece` the first one asked, for as long as it lives.
pub fn View::pointer_piece(self : View, piece : (Double, Double) -> Int) -> Int {
  guard self.live() is Some(n) else { return -1 }
  let cell = match n.piece_cell {
    Some((c, _)) => c
    None => {
      let c = @signals.signal(@signals.untracked(fn() { self.tree.piece_in(self.at, piece) }), same=fn(a, b) { a == b })
      n.piece_cell = Some((c, piece))
      if n.within_cell is None {
        self.tree.withins_at.push((self.at, n.gen))
      }
      c
    }
  }
  cell.get()
}

///|
/// Which piece of node `at` the pointer is over, by `piece` (View::pointer_piece): -1 where the pointer is nowhere.
fn Tree::piece_in(self : Tree, at : Int, piece : (Double, Double) -> Int) -> Int {
  match self.pointer_in(at) {
    Some((x, y)) => @signals.untracked(fn() { piece(x, y) })
    None => -1
  }
}

///|
/// How many times how its words are set was said (their words or pieces, how they look, how the pieces are set to
/// their size: View::words, View::words_runs, View::words_look, View::runs_look), followed: what is worked out of how
/// they are laid out read again as that is said, at that moment, whether or not how big it is changes.
pub fn View::words_said(self : View) -> Int {
  guard self.live() is Some(n) else { return 0 }
  let cell = match n.said_cell {
    Some(c) => c
    None => {
      let c = @signals.signal(0)
      n.said_cell = Some(c)
      c
    }
  }
  cell.get()
}

///|
/// How its words are set said again (words_said), told what follows it.
fn View::words_told(self : View) -> Unit {
  match self.live() {
    Some({ said_cell: Some(c), .. }) => c.set(c.untracked() + 1)
    _ => ()
  }
}

///|
/// Its words in pieces and how they are set as they are said now (what lays them out: its own, the same it is drawn
/// from as it is laid out next), not as the frame before drew them.
pub fn View::runs_set_now(self : View) -> (Array[@text.Run], WordsLook, RunsLook) {
  guard self.live() is Some(n) else { return ([], words_plain, runs_plain) }
  (n.look.runs, n.look.words_look, n.look.runs_look)
}

///|
/// Whether its words' lines each stand in the middle of its width as it is said now (View::words_centered).
pub fn View::words_centered_now(self : View) -> Bool {
  guard self.live() is Some(n) else { return false }
  n.look.words_center
}

///|
/// A piece of words, `text`, in `weight` (0: the words' own) and `ink` (0: the node's), the rest as the words are set
/// (a run of mbui/text's: View::words_runs).
pub fn words_run(text : String, weight? : Int = 0, ink? : Int64 = 0L) -> @text.Run {
  @text.span(text, weight~, color=ink)
}

///|
/// Words in pieces measured as a test's are: as their words one after another (words_measure).
pub fn runs_measure(
  runs : Array[@text.Run],
  look : WordsLook,
  set : RunsLook,
  width : Double,
  scale : Double,
) -> (Double, Double) {
  ignore(set)
  let words = StringBuilder()
  for r in runs {
    words.write_string(r.text)
  }
  words_measure(words.to_string(), look, width, scale)
}

///|
/// The ink its words are drawn in, as it changes (a theme's, a state's): paint's.
#callsite(autofill(loc))
pub fn View::ink(self : View, ink : Live[Int64], loc~ : SourceLoc) -> View {
  self.bind(loc~, Ink, ink, Paint, fn(k) { self.tree.nodes[self.at].look.ink = k })
  self
}

///|
/// The shadow it casts under its ground, in its corners (`blur`: its sigma, `dy` how far down, `ink` its colour; 0
/// blur: none), as it changes: paint's.
#callsite(autofill(loc))
pub fn View::shadow(self : View, cast : Live[(Double, Double, Int64)], loc~ : SourceLoc) -> View {
  self.bind(loc~, Shadow, cast, Paint, fn(c) { self.tree.nodes[self.at].look.shadow = c })
  self
}

///|
/// The halo its words are drawn on, as it changes (`blur`: its sigma in points, `ink` its colour; 0 blur: none): the
/// cover of their glyphs as they are laid out, blurred so, in that colour, under them, as CSS's text-shadow with no
/// offset, but brought up so that where it is densest it covers wholly (thin strokes blurred come to a fifth of a cover
/// or less): a name over a busy ground read clearly on it without a box round it. Paint's: drawn with its words, as
/// opaque, cut and big as they are; blurred once for the words, size and pixels they are drawn at, not each frame
/// (ui's halo.mbt). Drawn where the host gives its glyphs' pictures back (Windows); elsewhere none, its words as ever.
/// A property of its own, not WordsLook's, as View::words_breaks is.
#callsite(autofill(loc))
pub fn View::words_halo(self : View, halo : Live[(Double, Int64)], loc~ : SourceLoc) -> View {
  self.bind(loc~, WordsHalo, halo, Paint, fn(h) { self.tree.nodes[self.at].look.halo = h })
  self
}

///|
/// How wide it may grow at most (points; None: as wide as its holder lets it), as it changes; `within`: no wider than
/// the width what holds it gives it where that is less (CSS's `max-width: min(100%, w)`). Layout's.
#callsite(autofill(loc))
pub fn View::max_width(self : View, w : Live[Double?], within? : Bool = false, loc~ : SourceLoc) -> View {
  if self.live() is Some(n) {
    n.max_w_within = within
  }
  self.bind(loc~, MaxWidth, w, Layout, fn(w) {
    // (said: as said, or, one line of words in a column, within the column's width: Tree::capped_applied)
    self.tree.nodes[self.at].max_w_said = Some(w)
    self.tree.capped_applied(self.at)
  })
  self
}

///|
/// How tall it is at the least, as it changes (none: as tall as what it holds makes it), whatever else lays it out
/// shorter: a dialog's title row as tall as its close button's room, its title on more lines taller. Its field is
/// min_height_share's too (one binding to a field: the one said last).
#callsite(autofill(loc))
pub fn View::min_height(self : View, h : Live[Double?], loc~ : SourceLoc) -> View {
  self.bind(loc~, MinHeight, h, Layout, fn(h) {
    self.tree.nodes[self.at].flex.style.set_min_height(match h {
      Some(h) => Pt(h)
      None => Auto
    })
  })
  self
}

///|
/// How tall it is at the most, as it changes (none: no bound), what it holds shrinking (View::shrink) or scrolling in it
/// past that: a dialog no taller than the window leaves it.
#callsite(autofill(loc))
pub fn View::max_height(self : View, h : Live[Double?], loc~ : SourceLoc) -> View {
  self.bind(loc~, MaxHeight, h, Layout, fn(h) {
    self.tree.nodes[self.at].flex.style.set_max_height(match h {
      Some(h) => Pt(h)
      None => Auto
    })
  })
  self
}

///|
/// How its words are set, as it changes (a theme's for the window's width): layout's (what they measure) and paint's
/// (how they are drawn), one said value read by both.
#callsite(autofill(loc))
pub fn View::words_look(self : View, look : Live[WordsLook], loc~ : SourceLoc) -> View {
  self.bind(loc~, WordsLook, look, Both, fn(k) {
    let n = self.tree.nodes[self.at]
    n.look.words_look = k
    // (on one line or not: held to its column's width or not)
    self.tree.capped_applied(self.at)
    // (cut short: what of them is kept, as they look now)
    self.tree.cut_applied(self.at)
    // (saying shorter words: how narrow it may be as they look now, and whether they are on one line)
    if n.shorter.length() > 0 {
      self.tree.give_way_applied(self.at)
    }
    // (how its words are set said: what follows it told, once this is)
    self.words_told()
  })
  self
}

///|
/// Whether its words, where they do not wrap (WordsLook's `wrap` false), keep their line breaks, as it changes: each line
/// a line of its own as it is, none broken, as wide as the widest, as tall as their lines (code shown as written, in
/// what scrolls across: an old view's `breaks`, Ctx::text's and Ctx::rich's, CSS's pre); else, as by default, what
/// breaks them is run on with a space (CSS's nowrap). Wrapped, their breaks are kept either way. Measured, drawn, found,
/// picked and read out so (what hosts the tree: its `measure_kept`). Layout's and paint's.
/// A property of its own, not WordsLook's (2026-11-11): every WordsLook is said whole, so a field of it is one to add
/// to each that is said, on every branch not yet in; it may go there once few are.
#callsite(autofill(loc))
pub fn View::words_breaks(self : View, on : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, WordsBreaks, on, Both, fn(on) {
    self.tree.nodes[self.at].look.words_breaks = on
    // (how its words are set said: what follows it told, once this is)
    self.words_told()
  })
  self
}

///|
/// Whether its words keep their line breaks as it is said now (View::words_breaks).
pub fn View::words_breaks_now(self : View) -> Bool {
  guard self.live() is Some(n) else { return false }
  n.look.words_breaks
}

///|
/// A last-resort ellipsis is intended without changing the words' layout sizing (as Ctx::text's allow_ellipsis).
#callsite(autofill(loc))
pub fn View::allow_ellipsis(self : View, on : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, AllowEllipsis, on, Said, fn(v) { self.tree.nodes[self.at].allow_ellipsis = v })
  self
}

///|
/// Whether the app said a node's words may be cut, as an old view's line says it (ui's squeeze.mbt,
/// Ctx::squeeze_cut_said): the words themselves (View::allow_ellipsis; a share of their holder's width, growing into
/// its room or giving way along a row: View::width_share, View::grow, View::shrink above 0), or they or what holds
/// them cut short (View::cuts) or held to a width at most (View::max_width). What holds them giving way along its row
/// lays them out narrower, never says they may be cut (an old view's Auto box in a row gives way too, and says
/// nothing): a row's part that says when its title may be cut (link_row_node's `title_cut`) says it so. Only what the
/// app said: the framework's own bound on one line of words in a column (Tree::capped_applied's), the giving way it
/// makes of words said shorter ways (Tree::give_way_applied's) and a scroll's giving way down its column
/// (View::scrolls') say nothing.
/// A fixed width is the boundary: a constraint on a more distant holder cannot allow cutting everything inside this
/// one.
pub fn Tree::allows_ellipsis(self : Tree, id : NodeId) -> Bool {
  if !self.lives(id) {
    return false
  }
  let mut at = id.at
  while at >= 0 && at < self.nodes.length() {
    let n = self.nodes[at]
    let style = n.flex.style
    let own = at == id.at
    // (what lays it out: what holds it, past any slot; how it gives way or grows is across only in a row)
    let mut p = n.parent
    while p >= 0 && self.nodes[p].slot {
      p = self.nodes[p].parent
    }
    let in_row = p >= 0 && self.nodes[p].flex.style.direction is (Row | RowReverse)
    let max_said = n.max_w_said is Some(Some(_)) || n.max_w_within
    // (giving way or growing along its row: the words' own say alone)
    let along = in_row && ((match n.shrink_said { Some(s) => s > 0.0; None => false }) || style.grow > 0.0)
    if (own && (n.allow_ellipsis || along || style.width_kind() == @flex.LEN_PCT)) || n.cut || max_said {
      return true
    }
    if style.width_kind() == @flex.LEN_PT {
      return false
    }
    at = n.parent
  }
  false
}

///|
/// How much it gives way where what holds it is short of room, as it changes (0: none, laid out as big as it would
/// be): one that does gives way down to as wide as it is at least (View::min_width: its own, else as wide as what it
/// holds needs; Some(0) to give way down to nothing), what it shows cut to what is left (words on one line ending in an
/// ellipsis: WordsLook's `wrap` false), the others kept whole. Its share alone: how wide it is at least is min_width's
/// (one binding to a field). Layout's.
#callsite(autofill(loc))
pub fn View::shrink(self : View, s : Live[Double], loc~ : SourceLoc) -> View {
  // (said so, not cut short by what holds it: its one say of how it gives way, View::cuts let go of)
  self.bind(loc~, Shrink, s, Layout, fn(s) {
    self.tree.nodes[self.at].cut = false
    self.tree.nodes[self.at].shrink_said = Some(s)
    self.tree.give_way_applied(self.at)
  })
  self
}

///|
/// Cut short where what holds it has not the room across (an old view's w=Cut: ui's layout.mbt, `Cut => if in_row {
/// shrink = 1.0 }`): in a row it gives way along the row's length; in a column it keeps its own height, never squeezed
/// down. That alone: how wide it may be and whether its words end in an ellipsis are their own properties
/// (View::min_width, View::max_width, View::allow_ellipsis). As what holds it lays out now (View::row), as it changes.
/// How much it gives way said otherwise (View::shrink) or this said again: the one said last.
#callsite(autofill(loc))
pub fn View::cuts(self : View, on : Live[Bool], loc~ : SourceLoc) -> View {
  // (how it gives way, as View::shrink says it: one binding of the two, the last said taking it; not cut short, it
  // gives way nowhere, as a node says nothing of it)
  self.bind(loc~, Shrink, on, Layout, fn(c) {
    let n = self.tree.nodes[self.at]
    n.cut = c
    if c {
      // (how it gives way its row's: Tree::cut_applied)
      n.shrink_said = None
      self.tree.cut_applied(self.at)
    } else {
      // (said not to give way: so, whatever else would have it give way, View::shorter's; nothing of it kept as cut)
      n.shrink_said = Some(0.0)
      if n.flex.style.cut_least == n.flex.style.cut_least {
        n.flex.style.cut_least = 0.0 / 0.0
        self.tree.layout_marked_at(self.at)
      }
      self.tree.give_way_applied(self.at)
    }
  })
  self
}

///|
/// Node `at`, cut short (View::cuts), giving way along what holds it where that is a row, not where it is a column;
/// there, its words on one line keeping four of their size (at its size of words) where its row leaves out what has not
/// the room, before a part of the row leaves, and as the least of a row kept no narrower than what it holds (flex's
/// cut_least: kept_of, fit_least_held), as an old view's words cut short keep them. Worked out again as all words are
/// measured anew (Tree::words_again) and as its words are said (View::words).
fn Tree::cut_applied(self : Tree, at : Int) -> Unit {
  let n = self.nodes[at]
  if !n.live || !n.cut {
    return
  }
  // (what lays it out: what holds it, past any slot, which lays what it holds out in its own place)
  let mut p = n.parent
  while p >= 0 && self.nodes[p].slot {
    p = self.nodes[p].parent
  }
  let along = p >= 0 && self.nodes[p].flex.style.direction is (Row | RowReverse)
  let s = if along { 1.0 } else { 0.0 }
  if n.flex.style.shrink != s {
    n.flex.style.shrink = s
    self.layout_marked_at(at)
  }
  let look = n.look.words_look
  // (what is not words measured takes nothing of this: kept_of)
  let least = if along && !look.wrap {
    @flex.cut_kept_ems * look.size * @signals.untracked(fn() { self.words_scale_at(at) })
  } else {
    0.0 / 0.0
  }
  let was = n.flex.style.cut_least
  if !(was == least || (was != was && least != least)) {
    n.flex.style.cut_least = least
    self.layout_marked_at(at)
  }
}

///|
/// What node `at` lays out (what it holds, and what a slot of it holds in its place) cut short given way along it or not,
/// as it is a row or not (View::row).
fn Tree::cuts_under(self : Tree, at : Int) -> Unit {
  for k in self.nodes[at].kids {
    self.cut_applied(k)
    // (one line of words, in a column or not now)
    self.capped_applied(k)
    // (saying shorter words, giving way along a row alone)
    if self.nodes[k].shorter.length() > 0 {
      self.give_way_applied(k)
    }
    if self.nodes[k].slot {
      self.cuts_under(k)
    }
  }
}

///|
/// Whether, where it wraps (View::wraps), what it holds goes on in another line only where a line has not the room for
/// its parts at the least each comes to, as it changes (false: at what each asks, CSS's): what never gives way as wide
/// as it is, the rest their least width, a row of parts at least theirs with its gaps; and none of them comes to less,
/// so a line holds each of its parts whole. On one line, while all of it has the room so, its parts sharing it as they
/// would without it. Layout's.
#callsite(autofill(loc))
pub fn View::wraps_at_least(self : View, on : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, WrapsLeast, on, Layout, fn(on) { self.tree.nodes[self.at].flex.style.wrap_least = on })
  self
}

///|
/// How far apart what it holds is laid out (points, along and across), as it changes: layout's.
#callsite(autofill(loc))
pub fn View::gap(self : View, g : Live[Double], loc~ : SourceLoc) -> View {
  self.bind(loc~, Gap, g, Layout, fn(g) {
    let n = self.tree.nodes[self.at]
    let st = n.flex.style
    // (between the lines of a row that wraps, as View::wraps says where it says so)
    st.set_gap_row(Pt(n.line_gap.unwrap_or(g)))
    st.set_gap_col(Pt(g))
  })
  self
}

///|
/// Whether what it holds, laid out in a row, goes on in another line where the row has not the room (Some: the lines
/// that far apart, its gap along each line as View::gap says; None: one line), as an old view's box's `flow` (with
/// its `line_gap`), as it changes: layout's. `reverse`: each line it goes on to over the one before it, the first at
/// its foot (an old view's `flow_reverse`, flex's WrapReverse: a card's buttons, the first kept at the foot), what each
/// line holds in its order along it; read out and stepped through by the keyboard in the order it is held, as ever,
/// not by where it is drawn.
#callsite(autofill(loc))
pub fn View::wraps(self : View, lines : Live[Double?], reverse? : Bool = false, loc~ : SourceLoc) -> View {
  self.bind(loc~, Wraps, lines, Layout, fn(lines) {
    let n = self.tree.nodes[self.at]
    let st = n.flex.style
    n.line_gap = lines
    match lines {
      Some(g) => {
        st.wrap = if reverse { WrapReverse } else { Wrap }
        st.set_gap_row(Pt(g))
      }
      None => {
        st.wrap = NoWrap
        // (one line: its gap's, the same both ways)
        st.set_gap_row(st.get_gap_col())
      }
    }
  })
  self
}

///|
/// How wide it is at least (points; None: as what it holds makes it), as it changes; `within`: no wider for it than the
/// width what holds it gives it where that is less (CSS's `min-width: min(100%, w)`). Layout's.
#callsite(autofill(loc))
pub fn View::min_width(self : View, w : Live[Double?], within? : Bool = false, loc~ : SourceLoc) -> View {
  if self.live() is Some(n) {
    n.min_w_within = within
  }
  self.bind(loc~, MinWidth, w, Layout, fn(w) {
    self.tree.nodes[self.at].min_w_said = Some(w)
    self.tree.give_way_applied(self.at)
  })
  self
}

///|
/// How tall it is at least as a share of what holds it (0 to 1, of the height what holds it is laid out at; None: as
/// what it holds makes it), as it changes: as tall as that, or taller as what it holds needs. Layout's.
#callsite(autofill(loc))
pub fn View::min_height_share(self : View, share : Live[Double?], loc~ : SourceLoc) -> View {
  self.bind(loc~, MinHeight, share, Layout, fn(s) {
    self.tree.nodes[self.at].flex.style.set_min_height(match s {
      Some(s) => Pct(s * 100.0)
      None => Auto
    })
  })
  self
}

///|
/// How wide it is for how tall (0: neither said by the other), as it changes: the side its holder or its own size leaves
/// open worked out from the other (a picture laid out as wide as it is given, as tall as it is drawn then). Layout's.
#callsite(autofill(loc))
pub fn View::aspect(self : View, wide_for_tall : Live[Double], loc~ : SourceLoc) -> View {
  self.bind(loc~, Aspect, wide_for_tall, Layout, fn(a) { self.tree.nodes[self.at].flex.style.aspect = a })
  self
}

///|
/// Whether, holding nothing laid out (nothing in it, or all of it laid out nowhere: View::laid_nowhere, a show's or a
/// pick's gone), it takes no room, as it changes: laid out nowhere itself, its padding, margins and the gap before it in
/// what holds it none (an old view's box `gone_empty`, CSS's :empty { display: none }), what it holds left out as one
/// laid out nowhere is. Down a column, while what it holds makes its way from nothing or closes it to nothing (View::comes:
/// the first to come, the last to go; not one in another's place), its padding top and foot and the gap before it open
/// or close with that way, as much of them as the most of what it holds is there: called back half way, they turn with
/// it; what comes or goes at once, at once. Only down a column: along a row, or as a row itself, all of its room is
/// there till the frame it holds nothing, and none of it from that frame on. What a structure makes for what it shows
/// (a show's, a pick's, an each's row's box) is nothing to it where it made nothing: a pick of a case that makes
/// nothing holds nothing so, and one changed to it closes the way of the one before, its padding with it. A box the
/// app says itself holding nothing (`v.box(fn(_) {})`) is something: it may be as tall or as padded as it says; say
/// `gone_empty` on it for it to be nothing too. Layout's.
#callsite(autofill(loc))
pub fn View::gone_empty(self : View, on : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, GoneEmpty, on, Layout, fn(on) {
    self.tree.nodes[self.at].flex.style.set_gone_empty(on)
    // (what lays it out told it holds such: the first not a slot holding it, its boxes', Tree::boxes_put)
    if on {
      let mut at = self.tree.nodes[self.at].parent
      while at >= 0 && self.tree.nodes[at].slot && self.tree.nodes[at].parent >= 0 {
        at = self.tree.nodes[at].parent
      }
      if at >= 0 {
        self.tree.nodes[at].flex.holds_gone = true
      }
    }
  })
  self
}

///|
/// Laid out nowhere while `on` says so, as it changes: no room of its own in what holds it, none of the gap that leaves
/// between what it holds (a room shut: an old view's not built while it is), left out as one its row has not the room
/// for is (View::drops, View::left_out): it and all it holds not drawn, pressed (by a finger, by its id, by a screen
/// reader) or read out, a press held on it called off, from the layout that lays it out so; back, the same nodes, as
/// it is laid out again. Layout's.
#callsite(autofill(loc))
pub fn View::laid_nowhere(self : View, on : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, Nowhere, on, Layout, fn(on) { self.tree.nodes[self.at].flex.style.display = if on { @flex.DisplayNone } else { @flex.Flex } })
  self
}

///|
/// How what it holds lines up across it (None: stretched across it; their starts, middles or ends), as it changes:
/// layout's.
#callsite(autofill(loc))
pub fn View::lines_up(self : View, along : Live[Along?], loc~ : SourceLoc) -> View {
  self.bind(loc~, LinesUp, along, Layout, fn(a) {
    self.tree.nodes[self.at].flex.style.align_items = match a {
      None => Stretch
      Some(Start) => FlexStart
      Some(Middle) => Center
      Some(End) => FlexEnd
    }
  })
  self
}

///|
/// Whether it fills what holds it across the way that lays it out (`on`: stretched from its start to its end there, its
/// margin kept, as flex's align-self: stretch), whatever that lines up what it holds by (View::lines_up), as it
/// changes; not said, or said off, as what holds it lines it up. An old view's box said Full across (a column's w=Full, a
/// row's h=Full). Layout's.
#callsite(autofill(loc))
pub fn View::fills_across(self : View, on : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, FillsAcross, on, Layout, fn(on) {
    self.tree.nodes[self.at].flex.style.align_self = if on { Stretch } else { Auto }
  })
  self
}

///|
/// Where what a node holds lies along the way it lays them out (View::lies_along; flex's justify): at its start, in its
/// middle, at its end, or `Between`, the first at its start and the last at its end, what is left of its room shared
/// out between them (each line's, where it wraps; one alone at its start). Along is the other thing: which end of
/// another thing (an anchor, the node across) something lines up with, where being spread between makes no sense, so
/// the two are types of their own and neither is made of the other.
#derive(Eq, Debug)
pub(all) enum Lies {
  Start
  Middle
  End
  Between
}

///|
/// Where what it holds lies along it, as it changes (its start, by default; their middle; its end; spread from its
/// start to its end, Lies's Between): what is left of its room on its main way before it, round it, after it or between
/// them. Layout's.
#callsite(autofill(loc))
pub fn View::lies_along(self : View, along : Live[Lies], loc~ : SourceLoc) -> View {
  self.bind(loc~, LiesAlong, along, Layout, fn(a) {
    self.tree.nodes[self.at].flex.style.justify = match a {
      Start => FlexStart
      Middle => Center
      End => FlexEnd
      Between => SpaceBetween
    }
  })
  self
}

///|
/// How wide it is as a share of what holds it (0 to 1; the same binding as View::width, which says it in points), as it
/// changes: layout's.
#callsite(autofill(loc))
pub fn View::width_share(self : View, share : Live[Double], loc~ : SourceLoc) -> View {
  self.bind(loc~, Width, share, Layout, fn(s) {
    self.tree.nodes[self.at].flex.style.set_width(Pct(s * 100.0))
    self.tree.capped_applied(self.at)
  })
  self
}

///|
/// How tall it is as a share of what holds it (0 to 1; the same binding as View::height, which says it in points), as
/// it changes: layout's.
#callsite(autofill(loc))
pub fn View::height_share(self : View, share : Live[Double], loc~ : SourceLoc) -> View {
  self.bind(loc~, Height, share, Layout, fn(s) { self.tree.nodes[self.at].flex.style.set_height(Pct(s * 100.0)) })
  self
}

///|
/// Whether it is pointed at as the pointer is over it or over what it holds that takes the pointer not, as it changes
/// (an old view's box `points=true, taps=false`): View::pointed and View::pointed_in say so of it there, what holds it
/// as of what it holds; never pressed nor held for it (what takes a press or a hold under it takes it as ever), not
/// where something over it takes the pointer. Hit's.
pub fn View::points(self : View, on : Live[Bool]) -> View {
  // (what takes the pointer where, as whether it takes presses is (View::presses): said at the moment it changes, its
  // hits found anew, nothing laid out for it; said anew, what was said before let go of)
  guard self.live() is Some(n) else { return self }
  match n.props.get(Prop::Points.ord()) {
    Some(stop) => {
      n.props.remove(Prop::Points.ord())
      stop()
    }
    None => ()
  }
  let set = fn(on : Bool) {
    guard self.live() is Some(n) else { return }
    if n.points != on {
      n.points = on
      self.tree.inputs_own_said(self.at)
      self.tree.hits_bump()
      self.tree.marked()
    }
  }
  match on {
    Is(v) => set(v)
    By(f) =>
      self.owning(fn() {
        let stop = self.tree.structured(f, fn(v) { self.owning(fn() { set(v) }) })
        n.props[Prop::Points.ord()] = stop
      })
  }
  self
}

///|
/// How a glyph is drawn over how it is laid out: its opacity, offsets and uniform scale about its ink's middle. `sx`
/// scales horizontally about its advance's middle. One type for an old view's glyphs (ui's Ctx::glyphs_by, @ui.GlyphLook)
/// and a node's (View::glyphs_by).
#derive(Debug, Eq)
pub(all) struct GlyphLook {
  alpha : Double
  dx : Double
  dy : Double
  scale : Double
  sx : Double
}

///|
/// A glyph as it is painted, for its own look (View::glyphs_by; an old view's Ctx::glyphs_by):
/// - `index`: its number, from 0 in the order painted, the order read in. What is not a glyph (a list's mark, a
///   quote's bar, a code's ground) is said with the number of the glyph after it.
/// - `x`, `y`, `h`: where its line's box starts and its line's height: an old view's in the window, a node's in the
///   node's own terms (where its words are drawn from, before it is placed, moved or scaled).
/// - `top`, `foot`: the top and foot of what cuts what it is drawn in, in the same terms as `y`.
/// - `line`: the line of its words it is on, from 0 (a line its words break onto, wrapped or kept: View::words_breaks).
///   -1 for what is not a glyph.
/// - `cx`: where its middle is along that line, from the line's start: its advance's start and half its advance, in
///   the points its words are laid out in (the system's size of words applied; not what places, moves or scales them,
///   nor a centred line's shift). What it is in the cells its words are cut into (ui's glyph_cells). 0 for what is not
///   a glyph.
#derive(Debug, Eq)
pub(all) struct GlyphAt {
  index : Int
  x : Double
  y : Double
  h : Double
  top : Double
  foot : Double
  line : Int
  cx : Double
}

///|
/// Each glyph of its words drawn with what `f` gives for `state` as it is said now and that glyph (GlyphAt): words
/// coming or changing a glyph at a time. `state` is bound as any property is (what a way gives at the moment drawn,
/// View::drawn_while, Way::shown_on; the cells two lines of words are cut into), and `f` reads its two arguments alone:
/// no clock, no signal, nothing laid out (it is asked as the words are painted, under no tracking, as often as they
/// are). So its words are drawn again as `state` changes, and only then: what a way gives that is over asks for no
/// frame, as anything bound to it. How it is laid out, picked, pressed and read out is as without it. Paint's.
#callsite(autofill(loc))
pub fn[T : Eq] View::glyphs_by(self : View, state : Live[T], f : (T, GlyphAt) -> GlyphLook, loc~ : SourceLoc) -> View {
  self.bind(loc~, GlyphsBy, state, Paint, fn(s) {
    let n = self.tree.nodes[self.at]
    n.glyphs_fn = Some(fn(at) { f(s, at) })
    // (what it draws is another as this is: its words made again, Content's `glyphs_said`)
    n.look.glyphs_said = n.look.glyphs_said + 1
  })
  self
}

///|
/// What each glyph of node `id`'s words is drawn by as it is said now (View::glyphs_by): what hosts the tree asks it
/// as it paints them. None where nothing is said, or it is gone.
pub fn Tree::glyphs_of(self : Tree, id : NodeId) -> ((GlyphAt) -> GlyphLook)? {
  guard self.lives(id) else { return None }
  self.nodes[id.at].glyphs_fn
}
