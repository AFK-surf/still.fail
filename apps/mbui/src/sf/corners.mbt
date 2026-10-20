// still.fail's corner rule (docs/ui-panels.md, "所有带圆角的东西"): what lies in a rounded container's corner stands as
// far from its two edges, and its own corner is the container's less that distance (concentric). The one place that
// works it out: a corner inside another is written as `concentric(outer, inset)`, never as a number of its own.

///|
/// The corner of what stands `inset` in from both edges of a container rounded `outer`: concentric with it (never
/// below 0).
pub fn concentric(outer : Double, inset : Double) -> Double {
  if outer > inset {
    outer - inset
  } else {
    0.0
  }
}
