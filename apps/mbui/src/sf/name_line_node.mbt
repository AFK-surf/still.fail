// A name and what follows it on one line, as nodes of the window's tree, made once: the old views' run_row and
// wh_line, where a model's or a station's name came first and what followed it gave way to it.

///|
/// A name (`name`, in `name_style`) and what follows it (`rest`, in `rest_style`; nothing where it says none) on one
/// line in a row of `parent`'s, in the middle of it: the name whole while the line has the room for it, what follows it
/// what the line leaves after it, cut short; where the name alone is longer than the line leaves beside
/// name_line_rest_least of what follows it, the name cut short too. Both cut short with an ellipsis, whatever their
/// styles say. The row: `parent`'s to say how wide it is in what holds it.
#callsite(autofill(loc))
pub fn name_line_node(
  parent : @view.View,
  name : () -> String,
  name_style : () -> @ui.TextStyle,
  rest : () -> String,
  rest_style : () -> @ui.TextStyle,
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, fn(l) {
    l.row(Is(true)).lines_up(Is(Some(Middle))).min_width(Is(Some(0.0))) |> ignore
    words_node(l, name, name_style).cuts(Is(true)).min_width(Is(Some(0.0))).allow_ellipsis(Is(true)) |> ignore
    l.show(fn() { rest() != "" }, fn(r) {
      // (none of the line's room its own: all the name leaves, and no less than its least where the line has that)
      r
      .row(Is(true))
      .lines_up(Is(Some(Middle)))
      .grow(Is(1.0))
      .basis(Is(Some(0.0)))
      .min_width(Is(Some(name_line_rest_least)), within=true)
      |> ignore
      words_node(r, rest, rest_style).cuts(Is(true)).min_width(Is(Some(0.0))).allow_ellipsis(Is(true)) |> ignore
    })
  })
}

///|
/// How narrow what follows a name on its line (name_line_node) may come to beside the longest name: room for an
/// ellipsis and two or three characters before it, so it is never cut down to nothing. Not by the size of words (no
/// binding a row more for it, each row of a list paying for it as it is made: the history's are): measured to hold
/// so at the default size and at 1.3 (the app's history_said_wbtest.mbt), no larger.
// kept across runs: a value, never written
pub let name_line_rest_least : Double = 48.0
