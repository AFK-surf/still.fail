// still.fail's corner rule (docs/ui-panels.md, "所有带圆角的东西"): what lies in a rounded container's corner stands as
// far from its two edges, and its own corner is concentric with the container's: `@ui.concentric(outer, inset)` (mbui's
// smooth corners, Corners.kt's: the inset over 1.25), never a number of its own. A circle or a capsule there is round
// and not smoothed: the container is drawn round it.

///|
/// The corner of a container whose corner holds a whole circle (or a capsule) of `inner` radius `inset` in from both
/// edges: round with it, the container's corner its inset plus its radius (a circle is not cut to the container: the
/// container is drawn round it).
pub fn around(inset : Double, inner : Double) -> Double {
  inset + inner
}

///|
/// How much longer Android's smooth corner (Corners.kt Smooth, the web's superellipse(1.5)) is than the radius it is
/// given: Corners.kt SMOOTH_SCALE.
pub let smooth_scale : Double = 1.25

///|
/// Android's corner of a smooth box round one of corner `inner`, `inset` in from its edges (Corners.kt concentricOut:
/// the inset taken a quarter smaller, as Smooth draws a corner a quarter larger than it is given). For a value the
/// Android original works out this way, taken as it is.
pub fn concentric_out(inner : Double, inset : Double) -> Double {
  inner + inset / smooth_scale
}
