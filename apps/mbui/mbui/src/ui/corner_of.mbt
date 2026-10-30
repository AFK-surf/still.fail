// Corners linked (mbui/paint's corner.mbt): what a corner is worked out from where the old views ask it.

///|
/// What linked corners are worked out from as the old views ask them: the window's corner as the system draws it now,
/// the ranges of the theme being built under (Theme::corner_fit; the window's theme between builds).
pub fn corner_roots() -> CornerRoots {
  { window: window_corner(), fit: g().corner_fit }
}
