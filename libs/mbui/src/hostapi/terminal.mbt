// A terminal's screen, kept by the host (libghostty-vt where the host has it: src/host/term.h): what a program wrote to a
// terminal (VT: its text, its colours, its cursor's moves, its modes) made a screen of `cols` × `rows` cells, given back
// as its lines, each the runs of text of one look, for the app to draw. The host keeps it whole: an app writes what
// came (`Terminal::write`), says the size (`resize`), and reads the lines (`lines`) when it draws them anew.
//
// The lines come as JSON: `{"cols":C,"rows":R,"cursor":[x,y,shown],"keys":K,"lines":[[["text",fg,bg,flags],…],…]}`,
// `fg` and `bg` "#rrggbb" or "" (the terminal's own), `flags` bold 1, italic 2, underline 4, inverse 8, faint 16; `keys`
// 1 where the program asked for the application cursor keys (DECCKM: an arrow sent as ESC O A, not ESC [ A). A host
// with no terminal answers none (0) as it opens: the app cannot show one there.

///|
/// A terminal the host keeps.
pub struct Terminal {
  id : Int
}

///|
/// A new one of `cols` × `rows` cells; None where the host keeps none.
pub fn Terminal::open(cols : Int, rows : Int) -> Terminal? {
  match tm_open(cols, rows) {
    0 => None
    id => Some({ id, })
  }
}

///|
/// What its program wrote, as it came.
pub fn Terminal::write(self : Terminal, data : Bytes) -> Unit {
  tm_write(self.id, data)
}

///|
/// Its new size.
pub fn Terminal::resize(self : Terminal, cols : Int, rows : Int) -> Unit {
  tm_resize(self.id, cols, rows)
}

///|
/// Its screen as it is now (the JSON above).
pub fn Terminal::lines(self : Terminal) -> String {
  tm_lines(self.id)
}

///|
/// Let go of.
pub fn Terminal::close(self : Terminal) -> Unit {
  tm_close(self.id)
}
