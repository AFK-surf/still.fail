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
/// How its words are set, as it changes (a theme's for the window's width): layout's (what they measure) and paint's
/// (how they are drawn), one said value read by both.
pub fn View::words_look(self : View, look : Live[WordsLook]) -> View {
  self.bind(WordsLook, look, Both, fn(k) { self.tree.nodes[self.at].look.words_look = k })
  self
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
