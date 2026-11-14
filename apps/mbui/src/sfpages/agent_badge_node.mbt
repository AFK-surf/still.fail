// The badge at the corner of an agent's mark as nodes (agent_mark.mbt's agent_badge), where a chat's bar draws it.

///|
/// The badge at the corner of an agent's mark `side` across (sfpages' agent_badge, as nodes): a dot ringed in the
/// page's ground (or `ground`: what the mark stands on, as agent_badge's), blue waiting on a person, red failed; yellow
/// spokes at work. A chat's bar's on every screen (小屏's chat_bar_node, 中屏's and 大屏's chat_bar_wide_node), a chat's
/// info's (its panel's ground).
pub fn agent_badge_node(
  v : @view.View,
  badge : String,
  side : Double,
  ground? : () -> Int64 = fn() { @sf.theme().p.bg },
) -> Unit {
  let k = if side / 20.0 < 1.0 { side / 20.0 } else { 1.0 }
  match badge {
    "block" | "failed" => {
      let d = 12.0 * k
      let at = side - d + 3.0 * k
      v.box(fn(r) {
        r
        .over(Is(true))
        .width(Is(Some(d)))
        .height(Is(Some(d)))
        .offset(Is((at, at)))
        .radius(Is(d / 2.0))
        .padding(Is((2.0 * k, 2.0 * k, 2.0 * k, 2.0 * k)))
        .ground(By(ground))
        |> ignore
        r.box(fn(dot) {
          let ink = if badge == "block" { @sf.mark_blue } else { @sf.mark_red }
          dot.grow(Is(1.0)).radius(Is(d / 2.0)).ground(By(fn() { @ui.tree_theme().color(ink) }))
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    "run" => {
      let d = 10.0 * k
      let at = side - d + 2.0 * k
      v.box(fn(r) {
        r.over(Is(true)).width(Is(Some(d))).height(Is(Some(d))).offset(Is((at, at))) |> ignore
        @sf.spokes_node(r, d, fn() { @sf.mark_yellow }) |> ignore
      })
      |> ignore
    }
    _ => ()
  }
}
