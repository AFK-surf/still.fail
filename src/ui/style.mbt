// Style values (docs/style.md): a box's (Style, its state blocks Patch) and words' (TextStyle, TextPatch); made with
// `style(…)`, `patch(…)`, `text_style(…)`, `text_patch(…)`, put together with `then`. Every property is a token of
// style_tokens.mbt; one not said is the default (Ctx::box's, Ctx::text's) or what the style under it says.

///|
/// What a box looks like, every property optional (None: not said here). Padding from the finer to the coarser: `pl`
/// `pr` `pt` `pb` over `px` `py` over `p`.
pub(all) struct Patch {
  row : Bool?
  w : Len?
  h : Len?
  min_w : Len?
  max_w : Len?
  min_h : Len?
  max_h : Len?
  p : Space?
  px : Space?
  py : Space?
  pl : Space?
  pr : Space?
  pt : Space?
  pb : Space?
  gap : Space?
  align : Align?
  justify : Justify?
  bg : Color?
  radius : Radius?
  border : Stroke?
  border_color : Color?
  shadow : Shadow?
  clip : Bool?
  opacity : Opacity?
}

///|
/// A box's style: what it looks like, and what it looks like instead in a state (each a Patch over it). The states
/// are laid on in one order, the later winning: narrow, dark, selected, hovered, focused, pressed, disabled.
pub(all) struct Style {
  base : Patch
  narrow : Patch?
  dark : Patch?
  selected : Patch?
  hovered : Patch?
  focused : Patch?
  pressed : Patch?
  disabled : Patch?
}

///|
/// A box's look, every property a token (style_tokens.mbt); a state's block in place of none.
pub fn patch(
  row? : Bool,
  w? : Len,
  h? : Len,
  min_w? : Len,
  max_w? : Len,
  min_h? : Len,
  max_h? : Len,
  p? : Space,
  px? : Space,
  py? : Space,
  pl? : Space,
  pr? : Space,
  pt? : Space,
  pb? : Space,
  gap? : Space,
  align? : Align,
  justify? : Justify,
  bg? : Color,
  radius? : Radius,
  border? : Stroke,
  border_color? : Color,
  shadow? : Shadow,
  clip? : Bool,
  opacity? : Opacity,
) -> Patch {
  {
    row,
    w,
    h,
    min_w,
    max_w,
    min_h,
    max_h,
    p,
    px,
    py,
    pl,
    pr,
    pt,
    pb,
    gap,
    align,
    justify,
    bg,
    radius,
    border,
    border_color,
    shadow,
    clip,
    opacity,
  }
}

///|
/// A box's style: its look (as `patch`) and its states' blocks.
pub fn style(
  row? : Bool,
  w? : Len,
  h? : Len,
  min_w? : Len,
  max_w? : Len,
  min_h? : Len,
  max_h? : Len,
  p? : Space,
  px? : Space,
  py? : Space,
  pl? : Space,
  pr? : Space,
  pt? : Space,
  pb? : Space,
  gap? : Space,
  align? : Align,
  justify? : Justify,
  bg? : Color,
  radius? : Radius,
  border? : Stroke,
  border_color? : Color,
  shadow? : Shadow,
  clip? : Bool,
  opacity? : Opacity,
  narrow? : Patch,
  dark? : Patch,
  selected? : Patch,
  hovered? : Patch,
  focused? : Patch,
  pressed? : Patch,
  disabled? : Patch,
) -> Style {
  {
    base: {
      row,
      w,
      h,
      min_w,
      max_w,
      min_h,
      max_h,
      p,
      px,
      py,
      pl,
      pr,
      pt,
      pb,
      gap,
      align,
      justify,
      bg,
      radius,
      border,
      border_color,
      shadow,
      clip,
      opacity,
    },
    narrow,
    dark,
    selected,
    hovered,
    focused,
    pressed,
    disabled,
  }
}

///|
/// `a` if said, else `b`.
fn[T] first(a : T?, b : T?) -> T? {
  match a {
    Some(_) => a
    None => b
  }
}

///|
fn[T] or_else(b : T?, a : T?) -> T? {
  match b {
    Some(_) => b
    None => a
  }
}

///|
/// `self` with what `o` says over it. Padding said coarser in `o` takes the finer of `self` with it: `o`'s `p` is
/// every side's, its `px` the left's and the right's.
pub fn Patch::then(self : Patch, o : Patch) -> Patch {
  let a = self
  // what o's coarser padding covers is o's, whatever a said finer
  let a_px = if o.p is Some(_) { None } else { a.px }
  let a_py = if o.p is Some(_) { None } else { a.py }
  let a_pl = if o.p is Some(_) || o.px is Some(_) { None } else { a.pl }
  let a_pr = if o.p is Some(_) || o.px is Some(_) { None } else { a.pr }
  let a_pt = if o.p is Some(_) || o.py is Some(_) { None } else { a.pt }
  let a_pb = if o.p is Some(_) || o.py is Some(_) { None } else { a.pb }
  {
    row: or_else(o.row, a.row),
    w: or_else(o.w, a.w),
    h: or_else(o.h, a.h),
    min_w: or_else(o.min_w, a.min_w),
    max_w: or_else(o.max_w, a.max_w),
    min_h: or_else(o.min_h, a.min_h),
    max_h: or_else(o.max_h, a.max_h),
    p: or_else(o.p, a.p),
    px: or_else(o.px, a_px),
    py: or_else(o.py, a_py),
    pl: or_else(o.pl, a_pl),
    pr: or_else(o.pr, a_pr),
    pt: or_else(o.pt, a_pt),
    pb: or_else(o.pb, a_pb),
    gap: or_else(o.gap, a.gap),
    align: or_else(o.align, a.align),
    justify: or_else(o.justify, a.justify),
    bg: or_else(o.bg, a.bg),
    radius: or_else(o.radius, a.radius),
    border: or_else(o.border, a.border),
    border_color: or_else(o.border_color, a.border_color),
    shadow: or_else(o.shadow, a.shadow),
    clip: or_else(o.clip, a.clip),
    opacity: or_else(o.opacity, a.opacity),
  }
}

///|
fn opt_with(a : Patch?, b : Patch?) -> Patch? {
  match (a, b) {
    (Some(a), Some(b)) => Some(a.then(b))
    (None, _) => b
    (_, None) => a
  }
}

///|
/// `self` with what `o` says over it, its state blocks too (each over the same state's: Patch::then).
pub fn Style::then(self : Style, o : Style) -> Style {
  {
    base: self.base.then(o.base),
    narrow: opt_with(self.narrow, o.narrow),
    dark: opt_with(self.dark, o.dark),
    selected: opt_with(self.selected, o.selected),
    hovered: opt_with(self.hovered, o.hovered),
    focused: opt_with(self.focused, o.focused),
    pressed: opt_with(self.pressed, o.pressed),
    disabled: opt_with(self.disabled, o.disabled),
  }
}

///|
/// The look of `s` for a node in these states, its blocks laid on in their order.
fn Style::resolve(
  self : Style,
  narrow : Bool,
  dark : Bool,
  selected : Bool,
  hovered : Bool,
  focused : Bool,
  pressed : Bool,
  disabled : Bool,
) -> Patch {
  let blocks = [
    (self.narrow, narrow),
    (self.dark, dark),
    (self.selected, selected),
    (self.hovered, hovered),
    (self.focused, focused),
    (self.pressed, pressed),
    (self.disabled, disabled),
  ]
  let mut p = self.base
  for b in blocks {
    match b {
      (Some(b), true) => p = p.then(b)
      _ => ()
    }
  }
  p
}

///|
/// What words look like, every property optional. `wrap=false`: one line, cut with an ellipsis.
pub(all) struct TextPatch {
  size : TextSize?
  weight : Weight?
  color : Color?
  w : Len?
  center : Bool?
  wrap : Bool?
}

///|
/// Words' style: their look, and instead in the dark and on a narrow screen (the states words have).
pub(all) struct TextStyle {
  base : TextPatch
  narrow : TextPatch?
  dark : TextPatch?
}

///|
pub fn text_patch(
  size? : TextSize,
  weight? : Weight,
  color? : Color,
  w? : Len,
  center? : Bool,
  wrap? : Bool,
) -> TextPatch {
  { size, weight, color, w, center, wrap }
}

///|
pub fn text_style(
  size? : TextSize,
  weight? : Weight,
  color? : Color,
  w? : Len,
  center? : Bool,
  wrap? : Bool,
  narrow? : TextPatch,
  dark? : TextPatch,
) -> TextStyle {
  { base: { size, weight, color, w, center, wrap }, narrow, dark }
}

///|
pub fn TextPatch::then(self : TextPatch, o : TextPatch) -> TextPatch {
  {
    size: or_else(o.size, self.size),
    weight: or_else(o.weight, self.weight),
    color: or_else(o.color, self.color),
    w: or_else(o.w, self.w),
    center: or_else(o.center, self.center),
    wrap: or_else(o.wrap, self.wrap),
  }
}

///|
fn opt_text_with(a : TextPatch?, b : TextPatch?) -> TextPatch? {
  match (a, b) {
    (Some(a), Some(b)) => Some(a.then(b))
    (None, _) => b
    (_, None) => a
  }
}

///|
pub fn TextStyle::then(self : TextStyle, o : TextStyle) -> TextStyle {
  {
    base: self.base.then(o.base),
    narrow: opt_text_with(self.narrow, o.narrow),
    dark: opt_text_with(self.dark, o.dark),
  }
}

///|
fn TextStyle::resolve(self : TextStyle, narrow : Bool, dark : Bool) -> TextPatch {
  let mut p = self.base
  match self.narrow {
    Some(b) if narrow => p = p.then(b)
    _ => ()
  }
  match self.dark {
    Some(b) if dark => p = p.then(b)
    _ => ()
  }
  p
}
