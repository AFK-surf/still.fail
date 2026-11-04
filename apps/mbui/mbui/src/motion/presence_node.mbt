// Presence on a retained node follows the cause that adds or removes it. Its owner keeps it with show/each's
// leave interval; the last data stays with that node, and no frame rebuild is needed while it leaves.

///|
/// The look of `v` coming in and leaving (View::leaving), as presence's transitions. `initial`: already there
/// when its page opens. The caller applies the returned look to the surface and its words.
pub fn presence_node(v : @view.View, initial~ : Bool, enter~ : Trans, exit~ : Trans) -> () -> @ui.Look {
  let alpha = NodeWay::new(if initial { 1.0 } else { enter.fade })
  let scale = NodeWay::new(if initial { 1.0 } else { enter.scale })
  let x = NodeWay::new(if initial { 0.0 } else { enter.dx })
  let y = NodeWay::new(if initial { 0.0 } else { enter.dy })
  v.reacts(fn() { v.leaving() }, fn(gone) {
    let t = if gone { exit } else { enter }
    alpha.go(v, if gone { t.fade } else { 1.0 }, t.fade_spec)
    scale.go(v, if gone { t.scale } else { 1.0 }, t.spec)
    x.go(v, if gone { t.dx } else { 0.0 }, t.spec)
    y.go(v, if gone { t.dy } else { 0.0 }, t.spec)
  })
  v.owns(fn() { (alpha.due)(); (scale.due)(); (x.due)(); (y.due)() }) |> ignore
  fn() {
    let t = if v.leaving() { exit } else { enter }
    let a = alpha.shown(v)
    let s = scale.shown(v)
    let g = if t.ground_first { dmin(1.0, 2.0 * a) } else { a }
    { alpha: g, sx: s, sy: s, dx: x.shown(v), dy: y.shown(v), ox: t.ox, oy: t.oy,
      rot: 0.0, circle: 0.0, words: if t.ground_first && g > 0.0 { dmax(0.0, 2.0 * a - 1.0) / g } else { 1.0 } }
  }
}
