// How the reader lays text out (web/ui viewer/readerStyle.ts): the page keeps it (the host's reader_style and
// set_reader_style: the core's prefs, `prefs.reader`), and its bounds.

///|
/// The text's size (12 to 32), its lines' height as a multiple of it (1.2 to 2.4), the room either side (8 to 44),
/// its face ("serif" or "sans"), whether paragraphs start indented two characters, the paper under it ("follow" from
/// before: the light one, the app's dark being night; "white", "green", "grey", "night").
pub(all) struct ReaderStyle {
  size : Int
  line : Double
  margin : Int
  face : String
  indent : Bool
  paper : String
} derive(Eq)

///|
/// One setting changed (setReaderStyle's Partial, one field at a time).
pub(all) enum ReaderStyleChange {
  Size(Int)
  Line(Double)
  Margin(Int)
  Face(String)
  Indent(Bool)
  Paper(String)
}

///|
/// The core's defaults (client/core-ts/src/prefs.ts readerOf).
pub let reader_style_default : ReaderStyle = {
  size: 20,
  line: 1.7,
  margin: 22,
  face: "sans",
  indent: true,
  paper: "follow",
}

///|
/// `s` with `change` made.
pub fn ReaderStyle::changed(self : ReaderStyle, change : ReaderStyleChange) -> ReaderStyle {
  match change {
    Size(size) => { ..self, size }
    Line(line) => { ..self, line }
    Margin(margin) => { ..self, margin }
    Face(face) => { ..self, face }
    Indent(indent) => { ..self, indent }
    Paper(paper) => { ..self, paper }
  }
}

///|
/// The bounds (SIZES, LINES, MARGINS).
pub let reader_sizes : (Int, Int) = (12, 32)

///|
pub let reader_lines : (Double, Double) = (1.2, 2.4)

///|
pub let reader_margins : (Int, Int) = (8, 44)
