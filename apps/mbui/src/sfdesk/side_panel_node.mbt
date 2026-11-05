// The chat's side panel shell kept in the tree: its tabs, title, close and resizing edge. Each tab's independent
// page stays at its host boundary, with the same page context it had inside side_panel.

///|
/// The chat's side panel on the tape: the shell and tabs kept with their chat as the tape moves them; the ground,
/// corners and semantics the tape's, as for its page. The new-chat page still owns its independent files panel.
fn tape_side_pane(v : @view.View, src : Source) -> Unit {
  v.clips(Is(true)) |> ignore
  v.pick(tape_shown_side, fn(pane, side) {
    pane.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
    match side {
      Some(ChatSide(r)) => {
        guard @signals.untracked(fn() { @sfbase.workspace_in_view(src).0 }) is Some(w) else { return }
        let ground = fn() {
          let k = tape_behind_at(Panel, tape_drawn_at(pane))
          if k <= 0.0 { @sf.theme().p.bg } else { @sf.behind_ground(k~) }
        }
        pane.clips(Is(true)).hides(By(fn() { wide.tape_at.get() != Panel }))
        .ground(By(ground)).edge(By(fn() { (1.0, @sf.theme().p.line) }))
        .padding(By(fn() { (0.0, 0.0, tape_room_now().under, 0.0) })) |> ignore
        @ui.tree_corners_linked(pane, fn() { Some(tape_pane_corners(Panel, true)) })
        let corners = fn() { Some(beside_column(tape_pane_corners(Panel, true), tape_room_now().under)) }
        side_panel_node(pane, src, w, r, fn() { @sfbase.chat_view_now(src, r) }, tape=true, over=fn() { true },
          leaving=fn() { (tape_goes.panel_of)() is None }, corners~, ground~, old_page=fn(c, build) {
            tape_behind(c, Panel, fn() {
              let was = @sf.pane_round.val
              @sf.pane_round.val = corners()
              build()
              @sf.pane_round.val = was
            })
          })
      }
      Some(NewSide(_)) => {
        @ui.old(pane, fn(c) { tape_panel_built(c, src) }, key=tape_island_key).over(Is(true)) |> ignore
      }
      None => ()
    }
  })
}

///|
fn side_panel_node(
  parent : @view.View, src : Source, w : Workspace, r : ChatRef, view : () -> ChatView?,
  tape? : Bool = false,
  over? : () -> Bool = fn() { false },
  leaving? : () -> Bool = fn() { false },
  corners? : () -> FixedArray[@ui.CornerOf]? = fn() { None },
  ground? : () -> Int64 = fn() { @sf.theme().p.bg },
  old_page? : (@ui.Ctx, () -> Unit) -> Unit = fn(_, build) { build() },
) -> Unit {
  let popup = @sf.popup_root_node(parent)
  let tips = @sf.TipLayer::new(fn() { Some(popup) })
  parent.show(fn() { view() is Some(_) }, fn(panel) {
    let initial = @signals.untracked(view).unwrap()
    let current = fn() { view().unwrap_or(initial) }
    let tabs = fn() {
      let now = side_of(current())
      if leaving() || now.0.is_empty() { side_leaving(chat_key(r)).unwrap_or(now) } else { now }
    }
    let alone = fn() { tape && tabs().0.length() == 1 }
    // (on its side the screen's tools are a rail, with no name of its own: the panel's row names it)
    let screen_alone = fn() { tape && screen_tab_alone(tabs().0) && !column_short.get() && window_upright.get() }
    let own_bar = fn() { (alone() && tab_service(tabs().1) is Some(_)) || screen_alone() }
    panel.grow(Is(1.0)).min_height(Is(Some(0.0))).ground(By(ground)) |> ignore
    panel.show(fn() { !own_bar() }, fn(bar) {
      bar.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(8.0))
      .height(By(fn() { if tape { None } else { Some(@ui.Space::px(S11)) } }))
      .padding(By(fn() {
        match corners() {
          Some(ks) if tape => {
            let roots = @ui.tree_corner_roots_now()
            (@sf.line_end_in(ks[0].radius(roots), side_bar_start, side=@sf.side_tab_side),
              @sf.capsule_in(@sf.tape_corner, @sf.bar_key_side),
              @sf.line_end_in(ks[1].radius(roots), side_bar_end, side=@sf.bar_key_side), 6.0)
          }
          _ => (side_bar_start, 0.0, @sf.window_end_in(side_bar_end, roots=@ui.tree_corner_roots_now()), 0.0)
        }
      })).moves_window(By(@ui.window_inset_now)) |> ignore
      bar.pick(alone, fn(labels, one) {
        labels.grow(Is(1.0)).min_width(Is(Some(0.0))).row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
        if one {
          labels.padding(Is((16.0, 0.0, 0.0, 0.0))).gap(Is(8.0))
          .says(By(fn() { Some(@view.said(Heading, label=side_tab_names(src, r, current(), tabs().1).0)) })) |> ignore
          side_tab_mark_node(labels, src, r, current, fn() { tabs().1 }, fn() { true })
          labels.box(fn(words) {
            side_words_node(words, fn() { side_tab_names(src, r, current(), tabs().1).0 }, fn() { side_title_words })
          }) |> ignore
        } else {
          labels.gap(Is(2.0)).clips(Is(true)) |> ignore
          labels.each(fn() { tabs().0 }, fn(tab) { tab }, fn(tab_node, key) {
            let tab = @signals.untracked(fn() { key.get() })
            side_tab_node(tab_node, src, r, current, tab, fn() { tabs().1 == tab }, tips)
          })
        }
      })
      let external = fn() {
        station_tab_page(r, tabs().1).bind(fn(p) { if @sfbase.window_opens_for(p) { Some(p) } else { None } })
      }
      bar.show(fn() { external() is Some(_) }, fn(button) {
        @sf.icon_button_node(button, "external", fn() { @sf.t("web-pages.screen.window") }, fn() {
          match external() {
            Some(p) if @sfbase.open_window(p) => side_change(src, r, "close", Some(tabs().1))
            _ => ()
          }
        }, tips~) |> ignore
      })
      bar.show(fn() { !column_short.get() && !(@sf.native_on() && screen_tab_alone(tabs().0)) }, fn(button) {
        @sf.icon_button_node(button, "panel-close", fn() { @sf.t("web-pages.chat.closePanel") }, fn() {
          side_change(src, r, "clear", None)
        }, tips~, icon_now=fn() { if alone() { "close" } else { "panel-close" } }, linked=fn() {
          if tape || @ui.window_keys_own() { None } else { Some(@sf.window_corner_key()) }
        }) |> ignore
      })
    })
    panel.box(fn(body) {
      body.grow(Is(1.0)).min_height(Is(Some(0.0))).clips(Is(true)) |> ignore
      @ui.old(body, fn(c) {
        old_page(c, fn() {
          let (was_tape, was_over) = (side_on_tape.val, side_over.val)
          side_on_tape.val = tape
          side_over.val = over()
          side_front(c, src, w, r, current(), tabs().1, own_bar(), screen_alone=screen_alone())
          side_on_tape.val = was_tape
          side_over.val = was_over
        })
      }).grow(Is(1.0)) |> ignore
    }) |> ignore
    panel.show(fn() { !tape && !over() }, fn(edge) {
      edge.over(Is(true)).width(Is(Some(@sf.handle_w))).height_share(Is(1.0))
      .offset(Is((-@sf.handle_out, 0.0))) |> ignore
      let held = @signals.signal(false)
      let e = @sf.edge_node(edge, fn() { @sf.t("web-pages.chat.resizePanel") },
        fn() { panel.placed_window_now().2 },
        fn() { panel_min }, fn() { panel_max }, Left, fn(said, _) {
          match said {
            Dragging(x) | Dropped(x) => panel_own.width.set(Some(x))
            Pressed => side_change(src, r, "clear", None)
            Twice => panel_own.width.set(None)
            Untouched => ()
          }
        }, fn(on) { held.set(on) }, tips~)
      e.box(fn(look) {
        look.over(Is(true)) |> ignore
        @sf.edge_look_node(look, @sf.edge_over, fn() { e.pointed() || held.get() }, fn() { held.get() }) |> ignore
      }) |> ignore
    })
  })
}

///|
fn side_words_node(v : @view.View, words : () -> String, style : () -> @ui.TextStyle) -> Unit {
  v.words(By(words)).words_look(By(fn() { @ui.style_words(style()) })).ink(By(fn() { @ui.style_ink(style()) }))
  .shrink(Is(1.0)).min_width(Is(Some(0.0))).cuts(Is(true)).allow_ellipsis(Is(true)) |> ignore
}

///|
fn side_tab_node(v : @view.View, src : Source, r : ChatRef, view : () -> ChatView, tab : String,
  front : () -> Bool, tips : @sf.TipLayer) -> Unit {
  let names = fn() { side_tab_names(src, r, view(), tab) }
  let lit = fn() { @sf.lit_node(v) }
  v.row(Is(true)).lines_up(Is(Some(Middle))).height(Is(Some(@sf.side_tab_side)))
  .shrink(Is(1.0)).min_width(Is(Some(0.0))).radius(Is(@sf.side_tab_side / 2.0)).gap(Is(6.0))
  .padding(Is((@sf.capsule_end_room(@sf.side_tab_side, side_tab_mark_side).px(), 0.0, 5.0, 0.0)))
  .ground(By(fn() { @ui.tree_theme().color(if front() { Selected } else if lit() { Hover } else { Clear }) }))
  .says(By(fn() { Some(@view.said(Tab, label=names().0, selected=front())) })) |> ignore
  @sf.presses_node(v, fn() { side_change(src, r, "front", Some(tab)) })
  side_tab_mark_node(v, src, r, view, fn() { tab }, fn() { front() || lit() })
  v.box(fn(words) {
    side_words_node(words, fn() { names().0 }, fn() {
      if front() { side_tab_front } else if lit() { side_tab_words_lit } else { side_tab_words }
    })
  }) |> ignore
  v.box(fn(close) {
    close.width(Is(Some(20.0))).height(Is(Some(20.0))).shrink(Is(0.0)).radius(Is(10.0))
    .lines_up(Is(Some(Middle))).lies_along(Is(Middle))
    .ground(By(fn() { if @sf.lit_node(close) { @ui.tree_theme().color(Hover) } else { 0L } }))
    .says(By(fn() { Some(@view.said(Button, label=names().1)) })) |> ignore
    @sf.presses_node(close, fn() { side_change(src, r, "close", Some(tab)) })
    @sf.icon_node(close, "close", 12.0, By(fn() { if @sf.lit_node(close) { @sf.theme().p.text } else { @sf.theme().p.muted } })) |> ignore
  }) |> ignore
  if !(tab == "jobs" || tab == "files" || tab == "letters" || tab == "things") {
    @sf.tip_node(tips, v, fn() { names().0 }, skip=false) |> ignore
  }
}

///|
fn side_tab_mark_node(parent : @view.View, src : Source, r : ChatRef, view : () -> ChatView,
  tab : () -> String, front : () -> Bool) -> Unit {
  let agent = fn() { view().agents.iter().find_first(fn(a) { a.key == tab() }) }
  let kind = fn() {
    match station_tab(tab()) {
      Some((kind, _, _)) => "icon/" + (match kind { "drive" => "folder"; "adb" => "phone"; _ => "monitor" })
      None => if agent() is Some(_) { "agent" } else if tab_service(tab()) is Some(_) { "job" }
      else { "icon/" + (if tab_file(tab()) is Some(_) { "file" } else if tab() == "jobs" { "boxes" }
        else if tab() == "files" { "folder" } else if tab() == "things" { "photo" } else { "chats" }) }
    }
  }
  parent.box(fn(mark) {
    mark.width(Is(Some(14.0))).height(Is(Some(14.0))).shrink(Is(0.0))
    .lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
    mark.pick(kind, fn(part, kind) {
      part.width(Is(Some(14.0))).height(Is(Some(14.0))).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
      if kind == "agent" {
        @sf.maker_mark_node(part, fn() { agent().map(fn(a) { a.maker }).unwrap_or("") },
          fn() { agent().map(fn(a) { a.runtime }).unwrap_or("") }, 14.0) |> ignore
      } else if kind == "job" {
        side_job_dot_node(part, fn() {
          text((src.topic)("job", { "station": Json::string(r.station), "id": Json::string(tab_service(tab()).unwrap_or("")) }).value, "tone")
        })
      } else {
        @sf.icon_node(part, kind[5:].to_string(), 14.0,
          By(fn() { if front() { @sf.theme().p.text } else { @sf.theme().p.muted } })) |> ignore
      }
    })
  }) |> ignore
}

///|
fn side_job_dot_node(parent : @view.View, tone : () -> String) -> Unit {
  parent.box(fn(dot) {
    let ink = fn() { @ui.tree_theme().color(match tone() { "up" | "live" => Positive; "restart" => Warn; "fail" => Danger; _ => Border }) }
    dot.width(Is(Some(8.0))).height(Is(Some(8.0))).radius(Is(4.0)).ground(By(ink))
    .alpha(By(fn() {
      if tone() != "restart" || @ui.reduced_motion() { 1.0 } else {
        let f = dot.cycle_resident(@sf.breath_ms)
        1.0 - 0.65 * @ui.Ease::InOut.at(if f < 0.5 { f * 2.0 } else { 2.0 - f * 2.0 })
      }
    })) |> ignore
    dot.show(fn() { tone() == "live" && !@ui.reduced_motion() }, fn(halo) {
      let way = fn() { let f = halo.cycle_resident(job_live_ms); if f < 0.5 { f * 2.0 } else { 2.0 - f * 2.0 } }
      halo.over(Is(true)).offset(Is((-job_halo_out, -job_halo_out))).width(Is(Some(16.0))).height(Is(Some(16.0)))
      .radius(Is(8.0)).ground(By(ink)).scale(By(fn() { 0.6 + 0.55 * way() }))
      .alpha(By(fn() { 0.35 * (1.0 - way()) })) |> ignore
    })
  }) |> ignore
}
