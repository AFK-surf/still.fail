// Words' style (TextStyle) for a node of the window's tree: what Ctx::text and Ctx::text_sizes make of it, as the
// theme the tree is drawn in has it now (tree_theme: read where it is drawn, so it follows the theme, the dark and the
// window's narrowness as they change), said so the node sets them as an old view's are at whatever system's size of
// words (view_line, view_spacing: its line and its letters' spacing worked out at their size as drawn).

///|
/// How words of `style` are set on a node of the tree's now (View::words_look), as Ctx::text sets them: its size (15
/// where it says none); its line its leading's where it says one (Font: the font's own, 0), else its size's as the
/// theme has it, else the theme's share of its size as drawn; its weight (400 where it says none); wrapped unless it
/// says not to; its letters' spacing its tracking's at its size as drawn; wrapped, on as many lines as it says at most.
pub fn style_words(style : TextStyle) -> @view.WordsLook {
  let th = tree_theme()
  let st = style.resolve(g().narrow, th.dark)
  let (size, line) = match st.size {
    Some(z) => {
      let (size, line) = th.text_size(z)
      (size, Some(line))
    }
    None => (15.0, None)
  }
  let line = match st.leading {
    Some(l) => Some(th.leading(l).unwrap_or(0.0))
    None => line
  }
  {
    size,
    weight: opt_weight(st.weight).unwrap_or(400),
    line: match line {
      Some(l) => l
      None => -th.text_line
    },
    wrap: st.wrap.unwrap_or(true),
    tracking: match st.tracking {
      Some(Exact(px)) => Points(px)
      Some(t) => Ems(t.px(1.0))
      None => @view.letters_own
    },
    balance: st.balance.unwrap_or(false),
    max_lines: st.max_lines.unwrap_or(0),
  }
}

///|
/// The ink of words of `style` on a node of the tree's now: its color as the theme has it, else the theme's words'.
pub fn style_ink(style : TextStyle) -> Int64 {
  let th = tree_theme()
  match style.resolve(g().narrow, th.dark).color {
    Some(c) => th.color(c)
    None => th.fg
  }
}

///|
/// Whether words of `style` are cut short on their line where they have not the room (`w=Cut`).
pub fn style_cut(style : TextStyle) -> Bool {
  style.resolve(g().narrow, tree_theme().dark).w is Some(Cut)
}

///|
/// Whether words of `style` say they fill their line (`w=Full`, `w=Grow(k)`: an old view's Fill, which its squeeze
/// takes as the words saying they may be cut on it: Ctx::squeeze_cut_said).
pub fn style_fills(style : TextStyle) -> Bool {
  style.resolve(g().narrow, tree_theme().dark).w is Some(Full | Grow(_))
}
