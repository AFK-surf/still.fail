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
/// The ink its words are drawn in, as it changes (a theme's, a state's): paint's.
pub fn View::ink(self : View, ink : Live[Int64]) -> View {
  self.bind(22, ink, Paint, fn(k) { self.tree.nodes[self.at].look.ink = k })
  self
}

///|
/// The shadow it casts under its ground, in its corners (`blur`: its sigma, `dy` how far down, `ink` its colour; 0
/// blur: none), as it changes: paint's.
pub fn View::shadow(self : View, cast : Live[(Double, Double, Int64)]) -> View {
  self.bind(23, cast, Paint, fn(c) { self.tree.nodes[self.at].look.shadow = c })
  self
}

///|
/// How wide it may grow at most (points; None: as wide as its holder lets it), as it changes: layout's.
pub fn View::max_width(self : View, w : Live[Double?]) -> View {
  self.bind(24, w, Layout, fn(w) {
    self.tree.nodes[self.at].flex.style.set_max_width(match w {
      Some(w) => Pt(w)
      None => Auto
    })
  })
  self
}

///|
/// How its words are set, as it changes (a theme's for the window's width): layout's (what they measure) and paint's
/// (how they are drawn), one said value read by both.
pub fn View::words_look(self : View, look : Live[WordsLook]) -> View {
  self.bind(25, look, Both, fn(k) { self.tree.nodes[self.at].look.words_look = k })
  self
}

///|
/// How much it gives way where what holds it is short of room, as it changes (0: none, laid out as big as it would
/// be): one that does gives way down to nothing, what it shows cut to what is left (words on one line ending in an
/// ellipsis: WordsLook's `wrap` false), the others kept whole. Layout's.
pub fn View::shrink(self : View, s : Live[Double]) -> View {
  self.bind(26, s, Layout, fn(s) {
    let st = self.tree.nodes[self.at].flex.style
    st.shrink = s
    st.set_min_width(if s > 0.0 { Pt(0.0) } else { Auto })
  })
  self
}

///|
/// How far apart what it holds is laid out (points, along and across), as it changes: layout's.
pub fn View::gap(self : View, g : Live[Double]) -> View {
  self.bind(27, g, Layout, fn(g) {
    let st = self.tree.nodes[self.at].flex.style
    st.set_gap_row(Pt(g))
    st.set_gap_col(Pt(g))
  })
  self
}

///|
/// How wide it is at least (points; None: as what it holds makes it), as it changes: layout's.
pub fn View::min_width(self : View, w : Live[Double?]) -> View {
  self.bind(28, w, Layout, fn(w) {
    self.tree.nodes[self.at].flex.style.set_min_width(match w {
      Some(w) => Pt(w)
      None => Auto
    })
  })
  self
}

///|
/// How what it holds lines up across it (None: stretched across it; their starts, middles or ends), as it changes:
/// layout's.
pub fn View::lines_up(self : View, along : Live[Along?]) -> View {
  self.bind(29, along, Layout, fn(a) {
    self.tree.nodes[self.at].flex.style.align_items = match a {
      None => Stretch
      Some(Start) => FlexStart
      Some(Middle) => Center
      Some(End) => FlexEnd
    }
  })
  self
}
