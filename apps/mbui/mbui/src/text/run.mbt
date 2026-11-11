// What a paragraph of words is made of, each piece in a style of its own (a run: its weight, slant, face, size, colour,
// ground, strikethrough, a link, a drawing within it): plain data, read alike by what lays it out and draws it (mbui/ui's
// rich text, a node of the window's tree: mbui/view's words in runs) and what makes it (a reader of Markdown).

///|
/// A run of a paragraph's words in one style. `span` makes one with only
/// what differs from the paragraph said.
#derive(Eq, Debug)
pub(all) struct Run {
  text : String
  /// 0: the paragraph's
  weight : Int
  italic : Bool
  /// the paragraph's look for code: the code face at its code_scale, in its
  /// code_color on its code_bg
  code : Bool
  /// the code face alone
  mono : Bool
  /// the serif face (a reader's words)
  serif : Bool
  /// None: the paragraph's face; Some(0): the app's face; Some(n): host face n.
  face : Int?
  /// of the paragraph's size
  scale : Double
  /// 0: the paragraph's (a link's own colour, a code run's)
  color : Int64
  /// a ground behind the words, rounded, a little room either side; 0 none
  bg : Int64
  /// its ground's shape (None: a code run's)
  ground : Ground?
  strike : Bool
  underline : Bool
  /// where it leads ("" nowhere): tapped, the paragraph's on_link hears it
  link : String
  /// A positioned inline drawing; text is still its copyable, accessible alternative.
  drawing : InlineDrawing?
}

///|
/// A run's ground shaped as a label on its line rather than code's (CSS's inline-block: a tag before words), in ems of
/// the run's size: `room` either side of its words on it, `height` (centred on its words' ink), its `corner`, and
/// `after` it, off it, before what follows.
#derive(Eq, Debug)
pub(all) struct Ground {
  room : Double
  height : Double
  corner : Double
  after : Double
}

///|
/// A drawing within text, measured in em. Its paths are already laid out, from its top left, y down. Words outside
/// its alphabet use the host's serif face: (words, x, baseline, size), also in em. It has no parser or markup.
#derive(Eq, Debug)
pub(all) struct InlineDrawing {
  width : Double
  height : Double
  baseline : Double
  paths : Array[Array[(Array[Double], Bool)]]
  words : Array[(String, Double, Double, Double)]
}

///|
pub fn span(
  text : String,
  weight? : Int = 0,
  bold? : Bool = false,
  italic? : Bool = false,
  code? : Bool = false,
  mono? : Bool = false,
  serif? : Bool = false,
  face? : Int? = None,
  scale? : Double = 1.0,
  color? : Int64 = 0L,
  bg? : Int64 = 0L,
  ground? : Ground? = None,
  strike? : Bool = false,
  underline? : Bool = false,
  link? : String = "",
  drawing? : InlineDrawing? = None,
) -> Run {
  {
    text,
    weight: if bold && weight == 0 { 700 } else { weight },
    italic,
    code,
    mono,
    serif,
    face,
    scale,
    color,
    bg,
    ground,
    strike,
    underline,
    link,
    drawing,
  }
}

///|
pub fn plain(text : String) -> Run {
  span(text)
}

///|
pub fn bold(text : String) -> Run {
  span(text, bold=true)
}

///|
pub fn italic(text : String) -> Run {
  span(text, italic=true)
}

///|
pub fn code(text : String) -> Run {
  span(text, code=true)
}

///|
pub fn strike(text : String) -> Run {
  span(text, strike=true)
}

///|
pub fn link(text : String, href : String) -> Run {
  span(text, link=href)
}

