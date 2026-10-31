// Corners linked (docs/style.md「Corners linked」): a corner says where its radius comes from, not a number worked out
// in each place that needs it. The roots are the window's corner, as the system draws it (@hostapi.window_corner: 0 for
// a square window, one maximized or filling the screen), and numbers of one's own (a theme's ladder); every other corner
// follows another, `inset` in from its edges: concentric with it where the theme's ranges let a corner be so round and
// stand so far in (CornerFit), else as round as it is standing alone. So a panel 6 in from a Mac window's corner is the
// window's 16 less that, a ground 6 in that panel's less that again; the window's corner changing (maximized, another
// system), the whole chain follows. What a corner is now is worked out from those roots as given (CornerRoots), never
// from where it is asked: an old view's build gives its own (ui's corner_roots), a node of the window's tree the
// window's as told it.

///|
/// Where a corner's radius comes from: the window's (its system's), a number of its own, or another followed `inset` in
/// (concentric with it where the theme's ranges let it, else `alone`).
pub(all) enum CornerOf {
  /// the window's corner as the system draws it now (0 square)
  Window
  /// a corner of its own (a ladder's step)
  Own(Double)
  /// `from` followed `inset` in from its edges, concentric with it; `alone` where the ranges do not let it be
  Follow(CornerOf, Double, Double)
} derive(Eq, Show, Debug)

///|
/// What lies in a rounded container's corner and what the corner rule may make of it to be concentric with it (still.fail's
/// docs/ui-panels.md 圆角阶梯, 适应范围): its corner `least` at least and `most` at most, standing `near` to `far` from
/// the container's edges. The outermost container is the window, its corner the system's (@hostapi.window_corner: a
/// Mac's 16, Windows 11's 8, square full screen): where none of these makes a thing concentric with what it lies in
/// (the container too square for it, or too round: a window's 8, a phone's screen), it stands as it would alone, its
/// own corner where it is, and the rule asks nothing more of it there.
pub(all) struct CornerFit {
  least : Double
  most : Double
  near : Double
  far : Double
} derive(Eq, Show, Debug)

///|
/// What every linked corner is worked out from: the window's corner as the system draws it, and the theme's ranges
/// (None: any corner, any place).
pub(all) struct CornerRoots {
  window : Double
  fit : CornerFit?
} derive(Eq, Show, Debug)

///|
/// Its radius, from `at`.
pub fn CornerOf::radius(self : CornerOf, at : CornerRoots) -> Double {
  match self {
    Window => at.window
    Own(r) => r
    Follow(from, inset, alone) => {
      let r = from.radius(at)
      let k = concentric(r, inset)
      if r > 0.0 && inset < r && corner_fit_ok(at.fit, k, inset) {
        k
      } else {
        alone
      }
    }
  }
}

///|
/// Whether it follows what it says, from `at` (a `Follow` concentric with its source, not standing alone; a root
/// always).
pub fn CornerOf::follows(self : CornerOf, at : CornerRoots) -> Bool {
  match self {
    Follow(from, inset, _) => {
      let r = from.radius(at)
      r > 0.0 && inset < r && corner_fit_ok(at.fit, concentric(r, inset), inset)
    }
    _ => true
  }
}

///|
/// Where it stands from its source's edges where it follows it (a `Follow`'s inset), None where it does not.
pub fn CornerOf::inset(self : CornerOf, at : CornerRoots) -> Double? {
  match self {
    Follow(_, inset, _) if self.follows(at) => Some(inset)
    _ => None
  }
}

///|
/// The radius of what it follows, where it is a `Follow`.
pub fn CornerOf::source(self : CornerOf, at : CornerRoots) -> Double? {
  match self {
    Follow(from, _, _) => Some(from.radius(at))
    _ => None
  }
}

///|
/// Where a capsule or a circle `height` high stands in it to be concentric with it (its radius as a circle reads it,
/// less the capsule's half: smooth.mbt round_like, a panel's wholly smooth, the window's as round as the system draws
/// it), where the theme's ranges let it stand there; None where they do not (it too square for the capsule, or too
/// round).
pub fn CornerOf::capsule_at(self : CornerOf, height : Double, at : CornerRoots) -> Double? {
  let r = self.radius(at)
  let d = (if self is Window { r } else { round_like(r) }) - height / 2.0
  if place_fit_ok(at.fit, d) {
    Some(d)
  } else {
    None
  }
}

///|
/// Whether a corner `k` round, `d` in from what it follows, is one ranges `fit` let it have (any where there are none).
fn corner_fit_ok(fit : CornerFit?, k : Double, d : Double) -> Bool {
  match fit {
    Some(f) => k >= f.least - 0.5 && k <= f.most + 0.5 && d >= f.near - 0.5 && d <= f.far + 0.5
    None => k >= 0.0
  }
}

///|
/// Whether `d` in from a corner's edges is a place ranges `fit` let what lies there stand.
fn place_fit_ok(fit : CornerFit?, d : Double) -> Bool {
  match fit {
    Some(f) => d >= f.near - 0.5 && d <= f.far + 0.5
    None => d >= 0.0
  }
}
