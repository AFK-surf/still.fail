// How a node's words are set and what is drawn round it besides its ground: their size, weight and line, whether they
// wrap (View::words' `look`), their ink as it changes (View::ink); how wide it may grow (View::max_width); the shadow
// it casts (View::shadow). Typed, what hosts the tree draws by them (ui's view_made), measured by what it measures
// with (Tree::new's `measure`).

///|
/// How a node's words are set: their size (points), weight (100 … 900), the height of a line (points, at the system's
/// size of words 1 and scaled with it; 0, the font's own; less than 0, that share of their size as it is drawn, the
/// system's size of words applied: -1.4, 1.4 times it), whether they wrap within
/// the width they are given (else one line, as wide as they are, cut to what it is given ending in an ellipsis where it
/// is given less: View::shrink; what is read out of them all of them).
pub(all) struct WordsLook {
  size : Double
  weight : Int
  line : Double
  wrap : Bool
  /// how far apart its letters are set besides their own spacing (a large title's tighter)
  tracking : Spacing
} derive(Eq, Debug)

///|
/// How far apart a node's letters are set besides their own spacing (ui's Tracking as it is resolved): a share of
/// their size as it is drawn (the system's size of words applied), so many points whatever their size, or so many
/// points at the system's size of words, made larger by it as a size of their own is (an old view's `tracking` said
/// with its words, Ctx::text: Ctx::sp of it).
pub(all) enum Spacing {
  Ems(Double)
  Points(Double)
  ScaledPoints(Double)
} derive(Eq, Debug)

///|
/// Letters as their font sets them, nothing added.
pub let letters_own : Spacing = Ems(0.0)

///|
/// Words as a node set them till they were said to be otherwise: 15 points, regular, 22 a line, wrapped.
pub let words_plain : WordsLook = { size: 15.0, weight: 400, line: 22.0, wrap: true, tracking: letters_own }

///|
/// How a node's words in pieces (View::words_runs) are set where a piece says nothing of it itself, as an old view's
/// paragraph is (Ctx::rich's): a link's ink and its ground while it is pressed, code's ink and ground and its share of
/// the words' size, and whether they are a person's words (in the face chosen for those). What changes how big they
/// are (`code_scale`, `words`, whether code has a ground at all: its room either side, a label kept whole on its line)
/// lays them out again; their inks (a ground's colour for another) draw them again alone.
pub(all) struct RunsLook {
  link : Int64
  pressed : Int64
  code_ink : Int64
  code_ground : Int64
  code_scale : Double
  words : Bool
} derive(Eq, Debug)

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
pub fn View::runs_look(self : View, look : Live[RunsLook]) -> View {
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
  self.bind(RunsSet, set, Both, fn(s) {
    let l = tree.nodes[at].look.runs_look
    tree.nodes[at].look.runs_look = { ..l, code_scale: s.0, words: s.1 }
    // (how its words are set said: what follows it told, once this is)
    self.words_told()
  })
  self.bind(RunsInk, ink, Paint, fn(k) {
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
pub fn View::runs_pressed(self : View, k : Live[Int]) -> View {
  let tree = self.tree
  let at = self.at
  self.bind(RunsPressed, k, Paint, fn(k) { tree.nodes[at].look.runs_pressed = k })
  self
}

///|
/// What of its words in pieces is picked with the pointer (from, until, in their text's terms; none where the same), as
/// it changes: drawn picked under them alone (what picks them says it: mbui/ui's selection).
pub fn View::runs_picked(self : View, span : Live[(Int, Int)]) -> View {
  let tree = self.tree
  let at = self.at
  self.bind(RunsPicked, span, Paint, fn(s) { tree.nodes[at].look.runs_picked = s })
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
/// was; the window's root and where it is from it where it is in none.
pub fn View::row_place(self : View) -> (NodeId, Array[Int]) {
  let up : Array[Int] = []
  let mut at = self
  while at.live() is Some(n) && !n.each_row && at.parent() is Some(p) {
    up.push(p.kids().search_by(fn(k) { k.at == at.at }).unwrap_or(0))
    at = p
  }
  (at.id(), up.rev())
}

///|
/// What of its words in pieces is picked with the pointer as it is said now (View::runs_picked).
pub fn View::runs_picked_now(self : View) -> (Int, Int) {
  guard self.live() is Some(n) else { return (0, 0) }
  n.look.runs_picked
}

///|
/// Where the pointer is in its own terms (where it is drawn now, as big as it is drawn), as the tree last had it; None
/// where the tree has it nowhere (gone from the window) or it is let go. Read once, not followed (pointer_here_told).
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
/// Where the pointer is in its own terms (pointer_here's), followed: told as the pointer moves and as what changed is
/// placed (it, or what holds it, moved or grown under a pointer that stays where it is), at the change's end, no frame
/// waited for (as View::pointer_within is: Tree::withins_told). Never what a move of the pointer's own is told by
/// (View::on_pointer_moved).
pub fn View::pointer_here_told(self : View) -> (Double, Double)? {
  guard self.live() is Some(n) else { return None }
  let cell = match n.here_cell {
    Some(c) => c
    None => {
      let c = @signals.signal(self.tree.pointer_in(self.at), same=fn(a, b) { a == b })
      n.here_cell = Some(c)
      if n.within_cell is None {
        self.tree.withins_at.push((self.at, n.gen))
      }
      c
    }
  }
  cell.get()
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
    Some({ said_cell: Some(c), .. }) => c.set(@signals.untracked(fn() { c.get() }) + 1)
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
pub fn runs_measure(runs : Array[@text.Run], look : WordsLook, set : RunsLook, width : Double) -> (Double, Double) {
  ignore(set)
  let words = StringBuilder()
  for r in runs {
    words.write_string(r.text)
  }
  words_measure(words.to_string(), look, width)
}

///|
/// The ink its words are drawn in, as it changes (a theme's, a state's): paint's.
pub fn View::ink(self : View, ink : Live[Int64]) -> View {
  self.bind(Ink, ink, Paint, fn(k) { self.tree.nodes[self.at].look.ink = k })
  self
}

///|
/// The shadow it casts under its ground, in its corners (`blur`: its sigma, `dy` how far down, `ink` its colour; 0
/// blur: none), as it changes: paint's.
pub fn View::shadow(self : View, cast : Live[(Double, Double, Int64)]) -> View {
  self.bind(Shadow, cast, Paint, fn(c) { self.tree.nodes[self.at].look.shadow = c })
  self
}

///|
/// How wide it may grow at most (points; None: as wide as its holder lets it), as it changes: layout's.
pub fn View::max_width(self : View, w : Live[Double?]) -> View {
  self.bind(MaxWidth, w, Layout, fn(w) {
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
pub fn View::min_height(self : View, h : Live[Double?]) -> View {
  self.bind(MinHeight, h, Layout, fn(h) {
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
pub fn View::max_height(self : View, h : Live[Double?]) -> View {
  self.bind(MaxHeight, h, Layout, fn(h) {
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
pub fn View::words_look(self : View, look : Live[WordsLook]) -> View {
  self.bind(WordsLook, look, Both, fn(k) {
    let n = self.tree.nodes[self.at]
    n.look.words_look = k
    // (on one line or not: held to its column's width or not)
    self.tree.capped_applied(self.at)
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
/// A last-resort ellipsis is intended without changing the words' layout sizing (as Ctx::text's allow_ellipsis).
pub fn View::allow_ellipsis(self : View, on : Live[Bool]) -> View {
  self.bind(AllowEllipsis, on, Said, fn(v) { self.tree.nodes[self.at].allow_ellipsis = v })
  self
}

///|
/// Whether a node's words or their enclosing layout explicitly say that the words may be cut. A fixed width is the
/// boundary: a constraint on a more distant holder cannot allow cutting everything inside this one.
pub fn Tree::allows_ellipsis(self : Tree, id : NodeId) -> Bool {
  if !self.lives(id) {
    return false
  }
  let mut at = id.at
  while at >= 0 && at < self.nodes.length() {
    let n = self.nodes[at]
    let style = n.flex.style
    if (at == id.at && n.allow_ellipsis) || style.shrink > 0.0 || style.max_width_kind() != @flex.LEN_AUTO ||
      (at == id.at && style.width_kind() == @flex.LEN_PCT) {
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
pub fn View::shrink(self : View, s : Live[Double]) -> View {
  // (said so, not cut short by what holds it: its one say of how it gives way, View::cuts let go of)
  self.bind(Shrink, s, Layout, fn(s) {
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
pub fn View::cuts(self : View, on : Live[Bool]) -> View {
  // (how it gives way, as View::shrink says it: one binding of the two, the last said taking it; not cut short, it
  // gives way nowhere, as a node says nothing of it)
  self.bind(Shrink, on, Layout, fn(c) {
    let n = self.tree.nodes[self.at]
    n.cut = c
    if c {
      // (how it gives way its row's: Tree::cut_applied)
      n.shrink_said = None
      self.tree.cut_applied(self.at)
    } else {
      // (said not to give way: so, whatever else would have it give way, View::shorter's)
      n.shrink_said = Some(0.0)
      self.tree.give_way_applied(self.at)
    }
  })
  self
}

///|
/// Node `at`, cut short (View::cuts), giving way along what holds it where that is a row, not where it is a column.
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
pub fn View::wraps_at_least(self : View, on : Live[Bool]) -> View {
  self.bind(WrapsLeast, on, Layout, fn(on) { self.tree.nodes[self.at].flex.style.wrap_least = on })
  self
}

///|
/// How far apart what it holds is laid out (points, along and across), as it changes: layout's.
pub fn View::gap(self : View, g : Live[Double]) -> View {
  self.bind(Gap, g, Layout, fn(g) {
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
/// its `line_gap`), as it changes: layout's.
pub fn View::wraps(self : View, lines : Live[Double?]) -> View {
  self.bind(Wraps, lines, Layout, fn(lines) {
    let n = self.tree.nodes[self.at]
    let st = n.flex.style
    n.line_gap = lines
    match lines {
      Some(g) => {
        st.wrap = Wrap
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
/// How wide it is at least (points; None: as what it holds makes it), as it changes: layout's.
pub fn View::min_width(self : View, w : Live[Double?]) -> View {
  self.bind(MinWidth, w, Layout, fn(w) {
    self.tree.nodes[self.at].min_w_said = Some(w)
    self.tree.give_way_applied(self.at)
  })
  self
}

///|
/// How tall it is at least as a share of what holds it (0 to 1, of the height what holds it is laid out at; None: as
/// what it holds makes it), as it changes: as tall as that, or taller as what it holds needs. Layout's.
pub fn View::min_height_share(self : View, share : Live[Double?]) -> View {
  self.bind(MinHeight, share, Layout, fn(s) {
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
pub fn View::aspect(self : View, wide_for_tall : Live[Double]) -> View {
  self.bind(Aspect, wide_for_tall, Layout, fn(a) { self.tree.nodes[self.at].flex.style.aspect = a })
  self
}

///|
/// Laid out nowhere while `on` says so, as it changes: no room of its own in what holds it, none of the gap that leaves
/// between what it holds (a room shut: an old view's not built while it is), left out as one its row has not the room
/// for is (View::drops, View::left_out): it and all it holds not drawn, pressed (by a finger, by its id, by a screen
/// reader) or read out, a press held on it called off, from the layout that lays it out so; back, the same nodes, as
/// it is laid out again. Layout's.
pub fn View::laid_nowhere(self : View, on : Live[Bool]) -> View {
  self.bind(Nowhere, on, Layout, fn(on) { self.tree.nodes[self.at].flex.style.display = if on { @flex.DisplayNone } else { @flex.Flex } })
  self
}

///|
/// How what it holds lines up across it (None: stretched across it; their starts, middles or ends), as it changes:
/// layout's.
pub fn View::lines_up(self : View, along : Live[Along?]) -> View {
  self.bind(LinesUp, along, Layout, fn(a) {
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
/// Where what it holds lies along it, as it changes (its start, by default; their middle; its end): what is left of its
/// room on its main way before it, round it or after it. Layout's.
pub fn View::lies_along(self : View, along : Live[Along]) -> View {
  self.bind(LiesAlong, along, Layout, fn(a) {
    self.tree.nodes[self.at].flex.style.justify = match a {
      Start => FlexStart
      Middle => Center
      End => FlexEnd
    }
  })
  self
}

///|
/// How wide it is as a share of what holds it (0 to 1; the same binding as View::width, which says it in points), as it
/// changes: layout's.
pub fn View::width_share(self : View, share : Live[Double]) -> View {
  self.bind(Width, share, Layout, fn(s) {
    self.tree.nodes[self.at].flex.style.set_width(Pct(s * 100.0))
    self.tree.capped_applied(self.at)
  })
  self
}

///|
/// How tall it is as a share of what holds it (0 to 1; the same binding as View::height, which says it in points), as
/// it changes: layout's.
pub fn View::height_share(self : View, share : Live[Double]) -> View {
  self.bind(Height, share, Layout, fn(s) { self.tree.nodes[self.at].flex.style.set_height(Pct(s * 100.0)) })
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
  match n.props.get(Points) {
    Some(stop) => {
      n.props.remove(Points)
      stop()
    }
    None => ()
  }
  let set = fn(on : Bool) {
    guard self.live() is Some(n) else { return }
    if n.points != on {
      n.points = on
      self.tree.hits = self.tree.hits + 1
      self.tree.marked()
    }
  }
  match on {
    Is(v) => set(v)
    By(f) =>
      self.owning(fn() {
        let stop = self.tree.structured(f, fn(v) { self.owning(fn() { set(v) }) })
        n.props[Points] = stop
      })
  }
  self
}
