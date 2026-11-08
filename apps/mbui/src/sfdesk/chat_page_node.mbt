///|
fn chat_page_node(v : @view.View, src : Source, w : Workspace, r : ChatRef, page : () -> Page) -> Unit {
  let key = chat_key(r)
  let width = fn() {
    let ww = v.window().0
    ww - fold_along(fold_drawn_at(v), fold_target(src, w, ww).1).col
  }
  let tabs = fn() { side_now(src, r) }
  let opened = fn() { tabs().0.length() > 0 }
  let shown = fn() { if opened() { tabs() } else { side_leaving(key).unwrap_or(tabs()) } }
  side_beside_node(v, key, opened, width, fn(p, _left) {
    @ui.old(p, fn(c) {
      let page = page()
      let (_, target) = fold_target(src, w, c.window_size().0)
      fold_bars(fold_built(c, target))
      @sfbase.held_pictures_waiting.val = false
      let page_id = c.id("main-page")
      fold_goes.page_id = page_id
      c.shown_across(page_id, but="page-bar") |> ignore
      context_page(c, page_id)
      drawn_page.val = Some(page)
      if app.nav.top() == page { top_drawn.val = true }
      if page is History(_, history, entry) {
        c.tell("history-page/" + history, fn() { history_beside(src, r, history, entry) })
      }
      match page {
        Service(station, job) => tab_beside_say(c, src, station, r.session, "service:" + job) |> ignore
        PreviewFile(station, session, path, name) =>
          tab_beside_say(c, src, station, session, file_tab(session, path, name)) |> ignore
        _ => ()
      }
      let (way, to) = (@sfbase.page_way.id, @sfbase.page_way.to)
      let over = width() < side_both_least
      let target = if opened() && !over { side_width(width()) } else { 0.0 }
      if !over && (c.width != width() - target || way != "") {
        @sfbase.page_way_said(way + "/--side-panel/" + key + "/" + opened().to_string(),
          (if way != "" { to } else { width() }) - target)
      }
      let body = c.box(style=chat_ground, id=page_id, fn() {
        c.selectable(color=@sf.alpha(@sf.theme().p.blue, 0.28), fn() {
          chat_page(c, src, w, r, side=false)
        })
      })
      @motion.scope(c, body, bottom=true)
      @sfbase.page_way_said(way, to)
      drawn_page.val = None
    }, key=tape_island_key).grow(Is(1.0)) |> ignore
  }, fn(p, over) {
    p.ground(By(fn() { @sf.theme().p.bg })) |> ignore
    p.pick(fn() {
      let front = shown().1
      match station_tab_page(r, front) {
        Some(Screen(_)) => Some(front)
        _ => None
      }
    }, fn(holder, tab) {
      holder.grow(Is(1.0)).basis(Is(Some(0.0))) |> ignore
      guard tab is Some(tab) else {
        @ui.old(holder, fn(c) {
          side_over.val = over()
          match view_of_chat(src, r).0 {
            Some(view) => side_panel(c, src, w, r, view, shown().0, shown().1)
            None => ()
          }
        }, key=tape_island_key).grow(Is(1.0)) |> ignore
        return
      }
      guard station_tab_page(r, tab) is Some(Screen(at)) else { return }
      @ui.old(holder, natural=true, fn(c) {
        match view_of_chat(src, r).0 {
          Some(view) => side_panel_head(c, src, r, view, shown().0, shown().1) |> ignore
          None => ()
        }
      }) |> ignore
      holder.box(fn(content) {
        content.grow(Is(1.0)).basis(Is(Some(0.0))).clips(Is(true)) |> ignore
        @sfpages.screen_page_node(content, src, at, fn() { @sf.no_frame }, in_tab=true,
          on_close=fn() { side_change(src, r, "close", Some(tab)) }) |> ignore
      }) |> ignore
      @ui.old(holder, fn(c) { side_panel_edge(c, src, r, over()) }).over(Is(true)) |> ignore
      panel_screen_nodes[tab] = true
      holder.owns(fn() {
        panel_screen_nodes.remove(tab)
        match app.nav.top() {
          Screen(now) if now.station == at.station && now.screen == at.screen => ()
          _ => @sfpages.screen_left(src, at.station, at.screen)
        }
      }) |> ignore
    })
  })
}
