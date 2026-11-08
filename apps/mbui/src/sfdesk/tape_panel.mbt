///|
fn tape_screen_tab(src : Source) -> (ChatRef, String)? {
  guard tape_shown_side() is Some(ChatSide(r)) else { return None }
  guard view_of_chat(src, r).0 is Some(v) else { return None }
  let (_, front) = if (tape_goes.panel_of)() is None {
    side_leaving(chat_key(r)).unwrap_or(side_of(v))
  } else { side_of(v) }
  match station_tab_page(r, front) {
    Some(Screen(_)) => Some((r, front))
    _ => None
  }
}

///|
fn tape_panel_node(v : @view.View, src : Source) -> Unit {
  v.pick(fn() { tape_screen_tab(src) }, fn(holder, screen) {
    holder.over(Is(true)) |> ignore
    guard screen is Some((r, tab)) else {
      @ui.old(holder, fn(c) { tape_panel_built(c, src) }, key=tape_island_key).over(Is(true)) |> ignore
      return
    }
    guard station_tab_page(r, tab) is Some(Screen(at)) else { return }
    let tabs_now = fn() {
      let now = side_now(src, r)
      if (tape_goes.panel_of)() is None { side_leaving(chat_key(r)).unwrap_or(now) } else { now }
    }
    let own = fn() {
      let (w, h) = holder.window()
      screen_tab_alone(tabs_now().0) && !column_short.get() && w <= h
    }
    let ground = fn() {
      let k = tape_behind_at(Panel, tape_drawn_at(holder))
      if k <= 0.0 { @sf.theme().p.bg } else { @sf.behind_ground(k~) }
    }
    let scope = fn(c : @ui.Ctx, body : () -> Unit) {
      tape_behind(c, Panel, fn() {
        let was = @sf.pane_round.val
        @sf.pane_round.val = Some(beside_column(tape_pane_corners(Panel, true), tape_room_now().under))
        let old_side = side_on_tape.val
        side_on_tape.val = true
        body()
        side_on_tape.val = old_side
        @sf.pane_round.val = was
      })
    }
    holder.clips(Is(true)) |> ignore
    holder.box(fn(panel) {
      panel.grow(Is(1.0)).clips(Is(true)).ground(By(ground))
      .edge(By(fn() { (1.0, @sf.theme().p.line) }))
      .padding(By(fn() { (0.0, 0.0, tape_room_now().under, 0.0) })) |> ignore
      @ui.tree_corners_linked(panel, fn() { Some(tape_pane_corners(Panel, true)) })
      @ui.old(panel, natural=true, fn(c) {
        scope(c, fn() {
          match view_of_chat(src, r).0 {
            Some(view) => {
              let (tabs, front) = tabs_now()
              side_panel_head(c, src, r, view, tabs, front) |> ignore
            }
            None => ()
          }
        })
      }) |> ignore
      panel.box(fn(content) {
        content.grow(Is(1.0)).basis(Is(Some(0.0))).clips(Is(true)) |> ignore
        @sfpages.screen_page_node(content, src, at, fn() { @sf.no_frame }, in_tab=true,
          own_bar=fn() { if own() { Some(side_bar_tape()) } else { None } }, ground~, scope~,
          on_close=fn() { side_change(src, r, "close", Some(tab)) }) |> ignore
      }) |> ignore
    }) |> ignore
    panel_screen_nodes[tab] = true
    holder.owns(fn() {
      panel_screen_nodes.remove(tab)
      match app.nav.top() {
        Screen(now) if now.station == at.station && now.screen == at.screen => ()
        _ => @sfpages.screen_left(src, at.station, at.screen)
      }
    }) |> ignore
  })
}
