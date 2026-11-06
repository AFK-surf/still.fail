// Home while this device waits for approval in its workspace's lock: the waiting page over the system's foot and
// Home's workspace switcher and settings above it.

///|
fn lock_wait_home_node(
  parent : @view.View,
  src : Source,
  core : @settings.Core,
  here : () -> @settings.Here,
  tips : @sf.TipLayer,
) -> Unit {
  parent.box(fn(page) {
    page.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
    @sfpages.lock_wait_page_node(page, core, here)
  })
  |> ignore
  parent.box(fn(foot) { foot.height(By(fn() { Some(nav_foot()) })) |> ignore }) |> ignore
  parent.box(fn(bar) {
    bar.over(Is(true)).lies_along(Is(Start)) |> ignore
    home_top_bar_node(
      bar,
      src,
      tips,
      fn() { workspace_in_view(src).0 },
      fn() { None },
      invited=fn() { workspace_in_view(src).3 },
    )
  })
  |> ignore
}
