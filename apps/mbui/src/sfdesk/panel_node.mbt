// A chat's side panel (panel.mbt) as nodes of the window's tree, beside the chat's page in the pane off the tape (the
// page made once: page_pane.mbt pane_made), the way there 4: its column as wide as the panel has slid in, a way set off
// at the change that opens or closes it (side_slides) and read where it is drawn, as the block's fold is (pane_view's
// fold_goes); over a page too narrow for both, over the page from its right edge, a shadow at its side; its edge the
// tree's (@sf.edge_node). In it an agent's history in front: its top an old view as tall as it is (the bar, the head,
// its details: history_top), its steps nodes (sfpages' history_steps_node); a file in the viewer, the panel's bar so
// too and the file's tools and stage under it (sfbase's viewer_tab_node); any other tab the panel's old view
// (side_panel), the page's island. On the tape the panel is a panel of its own (tape_view's tape_side_node).

///|
/// Whether `front` (one the panel shows: side_shows) is one of the chat's agents' histories: what the panel's old view
/// (side_panel) leaves to the tree.
fn side_history_tab(front : String) -> Bool {
  front != "" &&
  !(front is ("jobs" | "files" | "letters" | "things")) &&
  tab_service(front) is None &&
  tab_file(front) is None &&
  station_tab(front) is None &&
  @sfbase.view_tab_file(front) is None
}

///|
/// Whether `front` is one the window's tree shows under the panel's bar rather than the panel's old view: an agent's
/// history, a file in the viewer.
fn side_node_tab(front : String) -> Bool {
  side_history_tab(front) || @sfbase.view_tab_file(front) is Some(_)
}

///|
/// What chat `r`'s panel shows: its tabs as its view has them; its last closed, while it slides out, those it had.
fn side_shown(src : Source, r : ChatRef) -> (Array[String], String) {
  let (tabs, front) = side_now(src, r)
  if tabs.length() > 0 {
    (tabs, front)
  } else {
    side_leaving(chat_key(r)).unwrap_or(([], ""))
  }
}

///|
/// How wide chat `r`'s panel is as node `n` is drawn, at rest: over a page too narrow for both its least (side_over_w),
/// else as side_width has it beside the page.
fn side_whole(src : Source, n : @view.View) -> Double {
  let pane = pane_w_at(src, n)
  if pane < side_both_least {
    dmin(side_over_w, pane)
  } else {
    side_width(pane)
  }
}

///|
/// Page `key`'s panel's column's way (panel_own's `goes`), made at rest at none the first time it is asked for: what
/// reads it before it first slides (side_narrower) is told as it sets off.
fn side_way(key : String) -> @motion.Way {
  match panel_own.goes.get(key) {
    Some(w) => w
    None => {
      let w = @motion.Way::new(0.0)
      panel_own.goes[key] = w
      w
    }
  }
}

///|
/// Page `key`'s panel's column opened (`open`) or closed, as node `n` comes to have it so: from none to some tabs or back
/// by a change asked here (side_changing's `asked`), slid in or out from where it is at that change's moment, as long as
/// it is wide; else there at once (a page opened with its tabs as they were left). Slid out, what it showed let go of
/// at its end.
fn side_slides(n : @view.View, src : Source, key : String, open : Bool) -> Unit {
  let way = side_way(key)
  let target = if open { @signals.untracked(fn() { side_whole(src, n) }) } else { 0.0 }
  let was = @signals.untracked(fn() { panel_own.was.get(key) })
  match was {
    Some(was) if was != open && panel_own.asked.untracked() == key => {
      panel_own.asked.set("")
      way.go(target, @motion.moved(), at=n.cause_at())
      if !open {
        let ends = way.end()
        n.at_moment(ends, fn() { if way.end() == ends { side_left(key) } }) |> ignore
      }
    }
    _ => {
      way.put(target)
      if !open {
        side_left(key)
      }
    }
  }
  if was != Some(open) {
    panel_own.was[key] = open
  }
}

///|
/// How wide page `key`'s panel's column is as node `n` is drawn: where its way has it while it goes, else all of it
/// open (`open`), none closed.
fn side_col(src : Source, n : @view.View, key : String, open : Bool) -> Double {
  match panel_own.goes.get(key) {
    Some(way) => {
      way.said()
      let t = n.drawn_while(fn(at) { way.goes_at(at) })
      if t != @double.infinity && way.goes_at(t) {
        return way.value_at(t)
      }
    }
    None => ()
  }
  if open {
    side_whole(src, n)
  } else {
    0.0
  }
}

///|
/// How much narrower than it is drawn in node `n` chat page `serial`'s column is laid out, and how far across it is moved
/// (chat_page_made's `narrower`): while its panel's column slides, as at the narrower of where the page was as it set
/// off and where it goes (the panel's wider end), moved across as laid_across has it; at rest, and over a page too
/// narrow for both (the page as wide as it is), none, laid out as wide as it is.
fn side_narrower(src : Source, n : @view.View, serial : Int) -> @sfbase.ColumnLaid {
  let pane = pane_w_at(src, n)
  guard app.nav.page_of(serial) is Some((Chat(r), _)) else { return { by: 0.0, across: 0.0, laid: pane } }
  let way = side_way(chat_key(r))
  way.said()
  let t = n.drawn_while(fn(at) { way.goes_at(at) })
  if pane < side_both_least {
    return { by: 0.0, across: 0.0, laid: pane }
  }
  if t == @double.infinity || !way.goes_at(t) {
    return { by: 0.0, across: 0.0, laid: pane - way.target() }
  }
  let ends = (way.value_at(way.starts_at()), way.target())
  laid_across(pane - way.value_at(t), pane - dmax(ends.0, ends.1), pane - dmin(ends.0, ends.1))
}

///|
/// A chat's column drawn `now` wide on its way between `laid` and `wide` (the narrower end it is laid out at, the
/// wider): how much narrower it is laid out, and how far across it is moved, by as much of the way as it has come from
/// `laid` to `wide`, as far as its rows' words start further in at `wide` than at `laid` (chat_page_made's `narrower`):
/// none at the narrower end, all of it at the wider, so that they go across with the page all the way, never stepping
/// where the width crosses one of row_side's (a breadth that lays them out otherwise).
fn laid_across(now : Double, laid : Double, wide : Double) -> @sfbase.ColumnLaid {
  let now = dmax(laid, dmin(now, wide))
  let part = if wide > laid { (now - laid) / (wide - laid) } else { 0.0 }
  { by: now - laid, across: part * (@sfpages.chat_row_side(wide) - @sfpages.chat_row_side(laid)), laid }
}

///|
/// The side panel of the chat page `serial` of the stack (a chat's, or the new chat's once it becomes one) in node `v`,
/// the row its page is in, after it, read by `src` (the page's, chat_page_made's: what it reads let go with the page): its column (side_col), moved aside with the page; in it, while it shows anything,
/// the panel as wide as it is at rest (cut to the column while it slides beside the page) and its edge.
fn side_panel_node(v : @view.View, src : Source, serial : Int, tips : @sf.TipLayer) -> Unit {
  let chat = fn() {
    match app.nav.page_of(serial) {
      Some((Chat(r), _)) => Some(r)
      _ => None
    }
  }
  v.pick(fn() { chat().map(chat_key) }, fn(col, key) {
    guard key is Some(key) && @signals.untracked(chat) is Some(r) else {
      col.width(Is(Some(0.0))) |> ignore
      return
    }
    let open = fn() { side_now(src, r).0.length() > 0 }
    col.reacts(open, fn(open) { side_slides(col, src, key, open) })
    // (its page kept under another, shown no more: what a file's tab plays here paused, as when its tab is let go)
    col.reacts(fn() { app.nav.shows(serial) }, fn(shows) {
      if !shows {
        @sfbase.tab_players_pause(chat=tabs_key(r))
      }
    })
    let over = fn() { pane_w_at(src, col) < side_both_least }
    let at = fn() { side_col(src, col, key, open()) }
    col
    .shrink(Is(0.0))
    .width(By(fn() { Some(if over() { 0.0 } else { at() }) }))
    .clips(By(fn() { !over() && at() < side_whole(src, col) }))
    .offset(By(fn() { (pane_aside_at(src, col), 0.0) }))
    |> ignore
    col.show(fn() { side_shown(src, r).0.length() > 0 }, fn(p) {
      p
      .grow(Is(1.0))
      .min_height(Is(Some(0.0)))
      .width(By(fn() { Some(side_whole(src, p)) }))
      .offset(By(fn() { (if over() { -at() } else { 0.0 }, 0.0) }))
      .ground(By(fn() { @sf.theme().p.bg }))
      .shadow(By(fn() {
        if over() {
          let (blur, fall) = @ui.Shadow::Xl.blur_y()
          (blur, fall, @ui.tree_theme().shadow)
        } else {
          (0.0, 0.0, 0L)
        }
      }))
      |> ignore
      let island = fn(n : @view.View, build : (@ui.Ctx) -> Unit, natural : Bool) {
        app.nav.page_island(n, serial, fn(c, _page) { build(c) }, key=tape_island_key, natural~)
      }
      p.pick(fn() { history_in_front(src, r) }, fn(q, agent) {
        q.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
        if agent == "" {
          // (every other tab: the panel's old view, all of it)
          island(
            q,
            fn(c) {
              match (@sfbase.workspace_in_view(src).0, view_of_chat(src, r).0) {
                (Some(w), Some(view)) => {
                  let (tabs, front) = side_shown(src, r)
                  side_panel(c, src, w, r, view, tabs, front)
                }
                _ => ()
              }
            },
            false,
          )
          .grow(Is(1.0))
          .min_height(Is(Some(0.0)))
          |> ignore
        } else if @sfbase.view_tab_file(agent) is Some(_) {
          side_view_node(q, src, r, agent, island)
        } else {
          side_history_node(q, src, r, agent, tips, island)
        }
      })
    })
    // its edge, beside the page only
    col.show(fn() { !over() && open() }, fn(e) { side_edge_node(e, src, r, tips) })
  })
}

///|
/// The agent whose history chat `r`'s panel has in front, or the file in the viewer; "" another tab.
fn history_in_front(src : Source, r : ChatRef) -> String {
  let front = side_shown(src, r).1
  if side_node_tab(front) {
    front
  } else {
    ""
  }
}

///|
/// Agent `agent`'s history in chat `r`'s panel, in node `q` (as large as the panel): the panel's bar an old view as tall
/// as it is (side_bar_row, as `island` hosts one, every tab's), then its head (history_head_node) and its steps the
/// rest (sfpages' history_steps_node), nodes.
fn side_history_node(
  q : @view.View,
  src : Source,
  r : ChatRef,
  agent : String,
  tips : @sf.TipLayer,
  island : (@view.View, (@ui.Ctx) -> Unit, Bool) -> @view.View,
) -> Unit {
  island(
    q,
    fn(c) {
      match view_of_chat(src, r).0 {
        Some(view) => c.box(style=history_top_box, fn() { side_bar_row(c, src, r, view, side_shown(src, r).0, agent) }) |> ignore
        None => ()
      }
    },
    true,
  )
  .shrink(Is(0.0))
  |> ignore
  history_head_node(q, src, r, agent, tips)
  q.box(fn(s) {
    s.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
    @sfpages.history_steps_node(s, src, r.station, agent, tips)
  })
  |> ignore
}

///|
/// File tab `tab` in chat `r`'s panel, in node `q` (as large as the panel): the panel's bar as an agent's history has it
/// (side_bar_row, as `island` hosts one), then the file's tools and its stage the rest (sfbase's viewer_tab_node, what
/// it hosts of the old view in `island` too); its picture over the whole window (its 全屏) stepping through the chat's.
fn side_view_node(
  q : @view.View,
  src : Source,
  r : ChatRef,
  tab : String,
  island : (@view.View, (@ui.Ctx) -> Unit, Bool) -> @view.View,
) -> Unit {
  island(
    q,
    fn(c) {
      match view_of_chat(src, r).0 {
        Some(view) => c.box(style=history_top_box, fn() { side_bar_row(c, src, r, view, side_shown(src, r).0, tab) }) |> ignore
        None => ()
      }
    },
    true,
  )
  .shrink(Is(0.0))
  |> ignore
  q.box(fn(s) {
    s.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
    @sfbase.viewer_tab_node(s, src, tabs_key(r), tab, island, fn() {
      let thread = match view_of_chat(src, r).0 {
        Some(v) => v.thread
        None => None
      }
      @sfbase.InChat(thread, r.session)
    })
  })
  |> ignore
}

///|
/// Chat `r`'s panel's edge (ResizeHandle) in node `n`, over its column's left, half over the page: dragged, its width
/// (kept while the app runs); pressed, the panel closed; pressed twice, its own width again.
fn side_edge_node(n : @view.View, src : Source, r : ChatRef, tips : @sf.TipLayer) -> Unit {
  let held = @signals.signal(false, same=fn(a, b) { a == b })
  n.over(Is(true)).width(Is(Some(@sf.handle_w))).offset(Is((-@sf.handle_out, 0.0))) |> ignore
  let e = @sf.edge_node(
    n,
    fn() { @sf.t("web-pages.chat.resizePanel") + " · " + @sf.t("web-pages.chat.closePanel") },
    fn() { side_whole(src, n) },
    fn() { panel_min },
    fn() { panel_max },
    Left,
    fn(said, _) {
      match said {
        Dragging(x) | Dropped(x) => panel_own.width.set(Some(x))
        Pressed => side_change(src, r, "clear", None)
        Twice => panel_own.width.set(None)
        Untouched => ()
      }
    },
    fn(h) { held.set(h) },
    tips~,
    side=Left,
  )
  e.box(fn(g) {
    g.over(Is(true)) |> ignore
    @sf.edge_look_node(g, fn() { false }, fn() { e.pointed() || e.focus_shown() || held.get() }, fn() { held.get() })
    |> ignore
  })
  |> ignore
}
