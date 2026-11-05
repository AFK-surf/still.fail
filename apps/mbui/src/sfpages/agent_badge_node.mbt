// AgentMark's corner, shared by the chat bar and the agent's other tiles, made once as nodes.

///|
pub fn agent_badge_node(parent : @view.View, badge : () -> String, side : Double, ground : () -> Int64) -> Unit {
  let k = dmin(side / agent_badge_full, 1.0)
  parent.show(fn() { badge() == "block" || badge() == "failed" }, fn(b) {
    let d = agent_badge_d * k
    let at = side - d + agent_badge_past * k
    let ring = agent_badge_ring * k
    b.over(Is(true)).offset(Is((at, at))).width(Is(Some(d))).height(Is(Some(d)))
    .radius(Is(d / 2.0)).ground(By(ground)).padding(Is((ring, ring, ring, ring))) |> ignore
    b.box(fn(dot) {
      dot.grow(Is(1.0)).radius(Is((d - 2.0 * ring) / 2.0))
      .ground(By(fn() { @ui.tree_theme().color(if badge() == "block" { @sf.mark_blue } else { @sf.mark_red }) })) |> ignore
    }) |> ignore
  })
  parent.show(fn() { badge() == "run" }, fn(b) {
    let d = agent_spokes * k
    let at = side - d + agent_spokes_past * k
    b.over(Is(true)).offset(Is((at, at))) |> ignore
    @sf.spokes_node(b, d, fn() { @sf.mark_yellow }) |> ignore
  })
}
