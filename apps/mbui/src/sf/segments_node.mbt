// The ring of eight arcs round an agent at work (icons.mbt's segments) as a node of the window's tree: the same arcs,
// their lines said once in their colours as those change, turned a step at a time by the resident clock as spokes_node
// is, for as long as it shows.

///|
/// The ring of eight arcs (segments'), in a box `size` across, a circle `stroke` thick on its edge, each arc 31° of
/// its 45° with round ends, the first straight up; each in `color` at its strength over `ground` (as they change);
/// turning round once every eight steps (spoke_turn's), held at its first while motion is reduced. The node.
#callsite(autofill(loc))
pub fn segments_node(
  parent : @view.View,
  size : Double,
  stroke : Double,
  color : () -> Int64,
  ground : () -> Int64,
  loc~ : SourceLoc,
) -> @view.View {
  let r = size / 2.0 - stroke / 2.0
  let mid = size / 2.0
  let pi = 3.141592653589793
  let deg = pi / 180.0
  let cap = stroke / 2.0 / r / deg
  // (their points worked out once: only their colours change as it lives)
  let arcs = (0).until(8).map(fn(i) {
    let from = (i.to_double() * 45.0 - 90.0 - 15.5 + cap) * deg
    @ui.arc(mid, mid, r, from~, sweep=(31.0 - 2.0 * cap) * deg)
  }).collect()
  parent.box(made_for=loc, fn(v) {
    v
    .width(Is(Some(size)))
    .height(Is(Some(size)))
    .lines(By(fn() {
      let (ink, under) = (color(), ground())
      arcs.mapi(fn(i, a) { @ui.line(a, width=stroke, color=mix(ink, spoke_alpha[(8 - i) % 8], under)) })
    }))
    .turn(
      By(fn() {
        if @ui.reduced_motion() {
          0.0
        } else {
          v.cycle_resident(8.0 * spoke_step_ms) * 2.0 * pi
        }
      }),
      drawn=true,
    )
    |> ignore
  })
}
