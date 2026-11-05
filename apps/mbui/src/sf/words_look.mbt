// Words' looks for nodes of the window's tree as an old view's text styles say them: a size and a line of the theme's.

///|
/// Words `size` big on lines `line` high as the window's theme has them (none: the size's own line), in `weight`,
/// wrapped or not (an old view's text_style(size=…, leading=…)).
pub fn theme_words(size : @ui.TextSize, line? : @ui.Leading, weight? : Int = 400, wrap? : Bool = false) -> @view.WordsLook {
  let th = @ui.tree_theme()
  let (px, own) = th.text_size(size)
  let line = match line {
    Some(l) => th.leading(l).unwrap_or(own)
    None => own
  }
  { size: px, weight, line, wrap, tracking: @view.letters_own, balance: false }
}
