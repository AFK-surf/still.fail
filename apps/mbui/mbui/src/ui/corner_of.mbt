// Corners linked (docs/style.md「Corners linked」): a corner says where its radius comes from, not a number worked out
// in each place that needs it. The roots are the window's corner, as the system draws it (@hostapi.window_corner: 0 for
// a square window, one maximized or filling the screen), and numbers of one's own (a theme's ladder); every other corner
// follows another, `inset` in from its edges: concentric with it where the theme's ranges let a corner be so round and
// stand so far in (Theme::corner_fit), else as round as it is standing alone. So a panel 6 in from a Mac window's corner
// is the window's 16 less that, a ground 6 in that panel's less that again; the window's corner changing (maximized,
// another system), the whole chain follows. A box takes one as its radius (`Radius::Linked`, `Radius::LinkedEach`, each
// corner its own), and where it lies in its container's corner the corner rule holds it to its link: as far in as its
// link says, and its container's corner the one it follows (corners.mbt corner_faults).

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
/// Its radius now.
pub fn CornerOf::radius(self : CornerOf) -> Double {
  match self {
    Window => window_corner()
    Own(r) => r
    Follow(from, inset, alone) => {
      let r = from.radius()
      let k = concentric(r, inset)
      if r > 0.0 && inset < r && corner_fit_ok(k, inset) {
        k
      } else {
        alone
      }
    }
  }
}

///|
/// Whether it follows what it says now (a `Follow` concentric with its source, not standing alone; a root always).
pub fn CornerOf::follows(self : CornerOf) -> Bool {
  match self {
    Follow(from, inset, _) => {
      let r = from.radius()
      r > 0.0 && inset < r && corner_fit_ok(concentric(r, inset), inset)
    }
    _ => true
  }
}

///|
/// Where it stands from its source's edges where it follows it (a `Follow`'s inset), None where it does not.
pub fn CornerOf::inset(self : CornerOf) -> Double? {
  match self {
    Follow(_, inset, _) if self.follows() => Some(inset)
    _ => None
  }
}

///|
/// The radius of what it follows, where it is a `Follow`.
pub fn CornerOf::source(self : CornerOf) -> Double? {
  match self {
    Follow(from, _, _) => Some(from.radius())
    _ => None
  }
}

///|
/// Where a capsule or a circle `height` high stands in it to be concentric with it (its radius as a circle reads it,
/// less the capsule's half: smooth.mbt round_like, a panel's wholly smooth, the window's as round as the system draws
/// it), where the theme's ranges let it stand there; None where they do not (it too square for the capsule, or too
/// round).
pub fn CornerOf::capsule_at(self : CornerOf, height : Double) -> Double? {
  let r = self.radius()
  let d = (if self is Window { r } else { round_like(r) }) - height / 2.0
  if place_fit_ok(d) {
    Some(d)
  } else {
    None
  }
}

///|
/// Whether a corner `k` round, `d` in from what it follows, is one the theme's ranges let it have (Theme::corner_fit;
/// any where the theme says none).
fn corner_fit_ok(k : Double, d : Double) -> Bool {
  match g().corner_fit {
    Some(f) => k >= f.least - 0.5 && k <= f.most + 0.5 && d >= f.near - 0.5 && d <= f.far + 0.5
    None => k >= 0.0
  }
}

///|
/// Whether `d` in from a corner's edges is a place the theme's ranges let what lies there stand.
fn place_fit_ok(d : Double) -> Bool {
  match g().corner_fit {
    Some(f) => d >= f.near - 0.5 && d <= f.far + 0.5
    None => d >= 0.0
  }
}
