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
