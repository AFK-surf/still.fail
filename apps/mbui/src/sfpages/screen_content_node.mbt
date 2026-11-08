// The simulator's retained frame shares the stage, device controls and log pane
// with the legacy page while those controls move to retained nodes.

///|
fn screen_content_node(parent : @view.View, s : ScreenSess, u : ScreenUi, key : String) -> @view.View {
  parent.box(fn(v) {
    v.grow(Is(1.0)).basis(Is(Some(0.0))) |> ignore
    v.pick(fn() {
      s.said.get() |> ignore
      if !s.simulator() { 0 } else if @sf.look_for(if u.in_tab { 0.0 } else { v.window().0 }) is Wide { 2 } else { 1 }
    }, fn(body, mode) {
      body.grow(Is(1.0)).basis(Is(Some(0.0))) |> ignore
      if mode == 0 {
        screen_stage_node(body, fn(c, picture) {
          s.said.get() |> ignore
          screen_stage(c, s, u, key, picture~)
        }) |> ignore
      } else {
        body.row(Is(mode == 2)) |> ignore
        body.box(fn(stage) {
          stage.grow(Is(1.0)).basis(Is(Some(0.0))) |> ignore
          screen_stage_node(stage, fn(c, picture) {
            s.said.get() |> ignore
            u.logs.beside = mode == 2 && flag(s.state, "debug")
            u.logs.by_device = mode == 2
            // Keep the padding inside the old island: the device bezel extends
            // outside the picture's stage, but stays inside this padded body.
            c.box(style=debug_stage_body, fn() {
              screen_stage(c, s, u, key, picture=fn(value) {
                let pad = @ui.Space::S3.px()
                picture(value.map(fn(p) {
                  { ..p, rect: { ..p.rect, x:p.rect.x + pad, y:p.rect.y + pad } }
                }))
              })
            }) |> ignore
          }).clips(Is(false)) |> ignore
        }) |> ignore
        if mode == 2 {
          body.pick(fn() {
            s.said.get() |> ignore
            flag(s.state, "debug") && u.logs.shown.get()
          }, fn(pane, shown) {
            if shown {
              pane.width(Is(Some(debug_pane_w))) |> ignore
              @ui.old(pane, fn(c) {
                s.said.get() |> ignore
                debug_pane(c, s, u)
              }).over(Is(true)) |> ignore
            }
          })
        } else {
          @ui.old(body, natural=true, fn(c) {
            s.said.get() |> ignore
            if s.driving() && flag(s.state, "poses") {
              c.box(style=debug_tools_bar, fn() { debug_poses(c, s, u) }) |> ignore
            }
            c.box(style=debug_tools_bar, fn() { debug_tools(c, s, u) }) |> ignore
          }) |> ignore
        }
      }
    })
  })
}
