// A bar's tool as a node of the window's tree (the way there, docs/retained.md 4: the library's parts given their
// made-once form beside their old one): viewer_tool's, drawn and answering as it does, each of what it shows bound to
// what it says as that changes (its icon, its words, whether it is on or can be pressed, its ink), read where it is
// drawn, not taken once as it is made; its corner as what holds it says (round, or linked to the window's).

///|
/// What a tool says of itself as it changes (tool_node): the icon it shows, its words (read out, its tip), whether it
/// is on (its chosen ground, read out pressed), whether it can be pressed at all (not: faint, taking no press, no
/// focus, nothing to be done to it, read out so).
pub(all) struct ToolSaid {
  icon : String
  label : String
  on : Bool
  disabled : Bool
} derive(Eq, Show, Debug)

///|
/// How big a tool is (viewer_tool_box's S8), and how far its icon is in from its sides.
pub let tool_side : Double = @ui.Space::px(S8)

///|
let tool_icon_in : Double = (tool_side - viewer_tool_icon) / 2.0

///|
/// How faint a tool that cannot be pressed is drawn (viewer_tool_box's disabled opacity, O35).
let tool_faint : Double = 0.35

///|
/// A tool of a bar's in `parent`, as viewer_tool draws one (its 32 square, its icon `viewer_tool_icon` across in its
/// middle), saying what `said` says as that changes, in the ink `ink` says: its icon the ink's muted, its own where the
/// hand is on it (a mouse's pointer over it, a finger pressing it), pressed, or on; its ground the ink's hover where
/// the hand is on it, laid over its chosen one while on; faint and taking nothing where it cannot be pressed. Its
/// corner `corner` (round: Is(tool_side / 2.0); at the window's corner, linked to it: @ui.corner_of). Ringed where the
/// keyboard's focus is on it (a kit control's ring). Pressed (a press, Enter or Space with the focus, a screen reader's
/// Activate), `press`, as one change. Its words its tip below it (tip_node), in the window's tips' layer `tip`, as
/// viewer_tool's. The node.
pub fn tool_node(
  parent : @view.View,
  said : () -> ToolSaid,
  ink : () -> ViewerInk,
  corner : @view.Live[Double],
  press : () -> Unit,
  tip? : TipLayer,
) -> @view.View {
  parent.box(fn(v) {
    // (where the hand is on it, as a box's hovered look has it: a mouse's pointer over it, a finger pressing it)
    let lit = fn() {
      match @ui.pointing() {
        Mouse => v.pointed()
        Finger => v.pressed()
      }
    }
    v
    .width(Is(Some(tool_side)))
    .height(Is(Some(tool_side)))
    .padding(Is((tool_icon_in, tool_icon_in, tool_icon_in, tool_icon_in)))
    .radius(corner)
    .presses(By(fn() { !said().disabled }))
    .focusable(By(fn() { !said().disabled }))
    .alpha(By(fn() { if said().disabled { tool_faint } else { 1.0 } }))
    .ground(By(fn() {
      let s = said()
      let i = ink()
      let under = if s.on { i.chosen } else { 0L }
      if !s.disabled && lit() {
        if under != 0L {
          @ui.over(under, i.hover)
        } else {
          i.hover
        }
      } else {
        under
      }
    }))
    .says(By(fn() {
      let s = said()
      Some(@view.said(Button, label=s.label, pressed=s.on))
    }))
    .on_press(press)
    |> ignore
    v.box(fn(i) {
      i
      .width(Is(Some(viewer_tool_icon)))
      .height(Is(Some(viewer_tool_icon)))
      .shapes(By(fn() { tool_shapes(said().icon) }))
      .tint(By(fn() {
        let s = said()
        let k = ink()
        if s.on || (!s.disabled && (lit() || v.pressed())) {
          k.ink
        } else {
          k.muted
        }
      }))
      |> ignore
    })
    |> ignore
    // (its ring, where the keyboard's focus is on it, as a kit control's (kit's focus_ring): the theme's focus line, its
    // gap out from its edge, in its corner as far out)
    let out = fn() {
      let t = @ui.tree_theme()
      t.focus_gap + t.focus_w
    }
    v.box(fn(r) {
      r
      .over(Is(true))
      .width(By(fn() { Some(tool_side + 2.0 * out()) }))
      .height(By(fn() { Some(tool_side + 2.0 * out()) }))
      .offset(By(fn() { (-out(), -out()) }))
      .radius(By(fn() {
        let k = match corner {
          Is(k) => k
          By(f) => f()
        }
        k + out()
      }))
      .border(By(fn() {
        if v.focus_shown() {
          let t = @ui.tree_theme()
          (t.focus_w, t.focus)
        } else {
          (0.0, 0L)
        }
      }))
      |> ignore
    })
    |> ignore
    match tip {
      Some(tips) => tip_node(tips, v, fn() { said().label }, side=Bottom)
      None => ()
    }
  })
}

///|
/// Icon `name`'s shapes as a tool draws it (viewer_tool_icon across), in no colour of their own (the node's tint).
fn tool_shapes(name : String) -> Array[@ui.Shape] {
  match icon_numbers(name) {
    Some(d) => icon_shapes(d, viewer_tool_icon / 24.0, 0x000000FFL)
    None => []
  }
}

///|
/// A tool's place while what it does goes on, as viewer_download draws it while a download comes (its 32 square, faint
/// as a tool that cannot be pressed, a ring in the ink's own saying how far, `part` as it changes), in `parent`: read
/// out as the tool it stands for (`label`), unable to be pressed; its corner `corner`. The node.
pub fn tool_ring_node(
  parent : @view.View,
  part : () -> Double,
  label : () -> String,
  ink : () -> ViewerInk,
  corner : @view.Live[Double],
) -> @view.View {
  parent.box(fn(v) {
    v
    .width(Is(Some(tool_side)))
    .height(Is(Some(tool_side)))
    .padding(Is((tool_icon_in, tool_icon_in, tool_icon_in, tool_icon_in)))
    .radius(corner)
    .alpha(Is(tool_faint))
    // (read out disabled: taking no press)
    .presses(Is(false))
    .says(By(fn() { Some(@view.said(Button, label=label())) }))
    |> ignore
    v.box(fn(i) {
      i
      .width(Is(Some(viewer_tool_icon)))
      .height(Is(Some(viewer_tool_icon)))
      .shapes(By(fn() { ring_shapes(viewer_tool_icon, part(), ink().ink) }))
      |> ignore
    })
    |> ignore
  })
}
