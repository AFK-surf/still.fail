// A column's edge as a node of the window's tree (the way there, docs/retained.md 4: handle_drag and edge_tip given
// their made-once form beside their old one): what is done with it taken at each event's own moment, whatever frames
// come. A mouse drags it at once; a finger only once held still on it a long press's while (a swipe that passes over
// it is what lies under it's: View::gesture's `held_first`); dragged, the width it is dragged to, from the width it had
// as it went down, on whole pixels between its least and its most; let go, the width it ends at; pressed and let go
// without moving, a press of it (where it lies over what is beside the column, that one's), the second of two its
// own width again. Its pointer the resizing one, read out as a separator; its tip (edge_tip's: a mouse's, by the
// pointer as it moves along it, edge_tip_ms after it comes onto it, shut by a press till the pointer has left it).

///|
/// An edge in a node of `parent`'s (filling it: what holds it says where and how big): of a column `width()` wide, on
/// its `edge` (the right of a sidebar, the left of a side panel), between `least()` and `most()`; `said` told what is
/// done with it as it is done, at its moment (Dragging, Dropped, Pressed, Twice; `on_beside` said for a press at
/// across (its own terms) that lands where it lies over what is beside the column: that one's, `beside` told of it
/// instead); `held` told as a press of it goes down and as it ends (let go, called off, passed on to what lies under
/// it); its words `label()`, its tip in `tips` on `side`. The node.
pub fn edge_node(
  parent : @view.View,
  label : () -> String,
  width : () -> Double,
  least : () -> Double,
  most : () -> Double,
  edge : @ui.Side,
  said : (Resized, Double) -> Unit,
  held : (Bool) -> Unit,
  on_beside? : (Double) -> Bool = fn(_) { false },
  beside? : (Double) -> Unit = fn(_) {  },
  tips? : TipLayer,
  side? : @view.Side = Right,
) -> @view.View {
  parent.box(fn(v) {
    v
    .grow(Is(1.0))
    .presses(Is(true))
    .cursor(Is(Some(ResizeX)))
    .says(By(fn() { Some(@view.said(Separator, label=label())) }))
    |> ignore
    match tips {
      Some(t) => tip_node(t, v, label, side~, delay=edge_tip_ms, skip=false, gap=edge_tip_gap, at_pointer=true) |> ignore
      None => ()
    }
    // (where the press went down across the window, and the width then; the last press let go without moving, for a
    // second one)
    let from = Ref((0.0, 0.0))
    let last_tap : Ref[(Double, Double, Double)?] = Ref(None)
    let to = fn(wx : Double) {
      let (x0, w0) = from.val
      let d = if edge is Left { x0 - wx } else { wx - x0 }
      dmax(least(), dmin(most(), (w0 + d).round()))
    }
    // (let go without moving it: a press of it)
    let pressed = fn(d : @view.Drag) {
      held(false)
      // (let go on it, as a press is: what is there for the finger as the tree is then, it and nothing over it)
      if !v.finger_target(d.wx, d.wy) {
        last_tap.val = None
        return
      }
      if on_beside(d.x) {
        last_tap.val = None
        beside(d.at)
        return
      }
      match last_tap.val {
        Some((at, wx, wy)) if d.at - at <= @ui.double_click_ms &&
          (d.wx - wx).abs() <= @ui.double_click_slop &&
          (d.wy - wy).abs() <= @ui.double_click_slop => {
          last_tap.val = None
          said(Twice, d.at)
        }
        _ => {
          last_tap.val = Some((d.at, d.wx, d.wy))
          said(Pressed, d.at)
        }
      }
    }
    // (whether this press has moved it: a mouse's held long, not moved, and let go within the slop of where it went
    // down is a press, as a click is, as handle_drag had it; let go past it, with no move told, a drag's end)
    let moved = Ref(false)
    // (where it went down in the window, as the gesture's slop is reckoned)
    let went = Ref((0.0, 0.0))
    v.gesture(
      @ui.touch_slop(),
      press=fn(d) {
        from.val = (d.wx, @signals.untracked(width))
        moved.val = false
        went.val = (d.wx, d.wy)
        held(true)
      },
      hold=(@ui.long_press_ms, fn(_) {  }),
      held_first=fn(_) { @ui.pointing() is Finger },
      tap=pressed,
      drag=fn(d) {
        match d.kind {
          Down | Moved => {
            moved.val = true
            said(Dragging(@signals.untracked(fn() { to(d.wx) })), d.at)
          }
          Up if !moved.val &&
            @ui.pointing() is Mouse &&
            (d.wx - went.val.0).abs() <= @ui.touch_slop() &&
            (d.wy - went.val.1).abs() <= @ui.touch_slop() => pressed(d)
          Up => {
            said(Dropped(@signals.untracked(fn() { to(d.wx) })), d.at)
            held(false)
          }
          Off => held(false)
        }
      },
    )
    |> ignore
    // (let go: no press of it left held)
    v.owns(fn() { held(false) }) |> ignore
  })
}
