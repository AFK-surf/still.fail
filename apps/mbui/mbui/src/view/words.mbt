// How a node's words are set and what is drawn round it besides its ground: their size, weight and line, whether they
// wrap (View::words' `look`), their ink as it changes (View::ink); how wide it may grow (View::max_width); the shadow
// it casts (View::shadow). Typed, what hosts the tree draws by them (ui's view_made), measured by what it measures
// with (Tree::new's `measure`).

///|
/// How a node's words are set: their size (points), weight (100 … 900), the height of a line, whether they wrap within
/// the width they are given (else one line, as wide as they are, cut to what it is given ending in an ellipsis where it
/// is given less: View::shrink; what is read out of them all of them).
pub(all) struct WordsLook {
  size : Double
  weight : Int
  line : Double
  wrap : Bool
} derive(Eq, Debug)

///|
/// Words as a node set them till they were said to be otherwise: 15 points, regular, 22 a line, wrapped.
pub let words_plain : WordsLook = { size: 15.0, weight: 400, line: 22.0, wrap: true }

///|
/// A piece of a node's words set its own way (View::words_runs): its weight (0: the words' own, WordsLook's), its ink
/// (0: the node's, View::ink); the rest as the words are set.
pub(all) struct WordsRun {
  text : String
  weight : Int
  ink : Int64
} derive(Eq, Debug)

///|
/// A piece of words, `text`, in `weight` (0: the words' own) and `ink` (0: the node's).
pub fn words_run(text : String, weight? : Int = 0, ink? : Int64 = 0L) -> WordsRun {
  { text, weight, ink }
}

///|
/// Words in pieces measured as a test's are: as their words one after another (words_measure).
pub fn runs_measure(runs : Array[WordsRun], look : WordsLook, width : Double) -> (Double, Double) {
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
    self.tree.nodes[self.at].flex.style.set_max_width(match w {
      Some(w) => Pt(w)
      None => Auto
    })
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
  self.bind(WordsLook, look, Both, fn(k) { self.tree.nodes[self.at].look.words_look = k })
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
  self.bind(Shrink, s, Layout, fn(s) { self.tree.nodes[self.at].flex.style.shrink = s })
  self
}

///|
/// How far apart what it holds is laid out (points, along and across), as it changes: layout's.
pub fn View::gap(self : View, g : Live[Double]) -> View {
  self.bind(Gap, g, Layout, fn(g) {
    let st = self.tree.nodes[self.at].flex.style
    st.set_gap_row(Pt(g))
    st.set_gap_col(Pt(g))
  })
  self
}

///|
/// How wide it is at least (points; None: as what it holds makes it), as it changes: layout's.
pub fn View::min_width(self : View, w : Live[Double?]) -> View {
  self.bind(MinWidth, w, Layout, fn(w) {
    self.tree.nodes[self.at].flex.style.set_min_width(match w {
      Some(w) => Pt(w)
      None => Auto
    })
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
/// How wide it is as a share of what holds it (0 to 1; the same binding as View::width, which says it in points), as it
/// changes: layout's.
pub fn View::width_share(self : View, share : Live[Double]) -> View {
  self.bind(Width, share, Layout, fn(s) { self.tree.nodes[self.at].flex.style.set_width(Pct(s * 100.0)) })
  self
}

///|
/// How tall it is as a share of what holds it (0 to 1; the same binding as View::height, which says it in points), as
/// it changes: layout's.
pub fn View::height_share(self : View, share : Live[Double]) -> View {
  self.bind(Height, share, Layout, fn(s) { self.tree.nodes[self.at].flex.style.set_height(Pct(s * 100.0)) })
  self
}
