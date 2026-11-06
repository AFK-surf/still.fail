// An agent's usage figures as retained nodes. The card and the context action's state are read as they change;
// the context tile itself stays in place while its figure, action and busy state change.

///|
/// The figures from `card`: cost, cache hit rate and context, as usage_tiles draws them. `can_open` says whether the
/// context has actions; `on_context` receives the tile to anchor them to. While `busy` it cannot be pressed. Without
/// actions, a known context's full text is shown in a tip. The caller may share its window's tip layer.
pub fn usage_tiles_node(
  parent : @view.View,
  card : () -> Json?,
  busy : () -> Bool,
  compacts : () -> Bool,
  can_open : () -> Bool,
  on_context : (@view.View) -> Unit,
  tips? : @sf.TipLayer,
) -> Unit {
  let cost = fn() { text(card(), "cost") }
  let cache = fn() { field(card(), "cache") }
  let context = fn() { field(card(), "context") }
  let has_tiles = fn() { cost() != "" || cache() is Some(_) || context() is Some(_) }
  parent.show(has_tiles, fn(row) {
    @sf.style_node(row, fn() { agent_card_tiles_row })
    let layer = match tips {
      Some(t) => t
      None => {
        let popup = @sf.popup_root_node(row)
        @sf.TipLayer::new(fn() { Some(popup) })
      }
    }
    row.show(fn() { cost() != "" }, fn(tile) {
      usage_tile_node(tile, cost, fn() { @sf.t("web-main.chat.agentCard.cost") }, fn() { "" })
    })
    row.show(fn() { cache() is Some(Object(_)) }, fn(tile) {
      usage_tile_node(tile, fn() { text(cache(), "text") }, fn() { @sf.t("web-main.chat.agentCard.cache") }, fn() { "" })
    })
    row.show(fn() { context() is Some(Object(_)) }, fn(tile) {
      let unknown = fn() { flag(context(), "unknown") }
      let level = fn() { if unknown() { "" } else { text(context(), "level") } }
      let figure = fn() {
        if unknown() { text(context(), "text") } else { number(context(), "percent").round().to_int().to_string() + "%" }
      }
      let name = fn() {
        if can_open() && compacts() && (level() == "amber" || level() == "red") {
          @sf.t("web-mobile.agent.contextCompactable")
        } else {
          @sf.t("web-main.chat.agentCard.context")
        }
      }
      @sf.style_node(tile, fn() { agent_card_tile }, in_row=true)
      let eligible = fn() { can_open() || !unknown() }
      tile.points(By(eligible)).presses(By(eligible)).focusable(By(eligible))
      .cursor(By(fn() { if can_open() && !busy() { None } else { Some(Arrow) } }))
      .says(By(fn() {
        if can_open() {
          Some(@view.said(Button, label=@sf.t("web-pages.chat.contextActions"), disabled=busy()))
        } else if !unknown() {
          Some(@view.said(Text, label=name() + ": " + text(context(), "text")))
        } else {
          None
        }
      })) |> ignore
      usage_figure_node(tile, figure, level)
      tile.box(fn(line) {
        @sf.style_node(line, fn() { agent_card_tile_more })
        @sf.words_node(line, name, fn() { agent_card_tile_name }) |> ignore
        line.show(can_open, fn(mark) {
          mark.pick(busy, fn(slot, working) {
            if working {
              @sf.spinner_node(slot, size=11.0) |> ignore
            } else {
              @sf.icon_node(slot, "chevron-right", 11.0, By(fn() { @sf.theme().p.muted })) |> ignore
            }
          })
        })
      }) |> ignore
      let tip = @sf.tip_node(layer, tile, fn() {
        if !can_open() && !unknown() { text(context(), "text") } else { "" }
      })
      let press = fn() {
        if @signals.untracked(fn() { can_open() && !busy() }) {
          on_context(tile)
        }
      }
      tile.on_press(press) |> ignore
      // 0: no hold, 1: the information tip, 2: an action held by a finger. A long hold on an action still
      // presses it when released on the tile; only the information tip consumes its hold.
      let held = Ref(0)
      let on_tile = fn(d : @view.Drag) { tile.finger_target(d.wx, d.wy) }
      tile.gesture(
        @ui.touch_slop(),
        press=fn(_) { held.val = 0 },
        tap=fn(d) { if on_tile(d) && held.val == 0 { press() } },
        hold=(@ui.long_press_ms, fn(_) {
          if @ui.pointing() is Finger {
            if @signals.untracked(can_open) {
              held.val = 2
            } else if @signals.untracked(fn() { !unknown() }) {
              held.val = 1
              (tip.hold)()
            }
          }
        }),
        drag=fn(d) {
          if held.val == 1 {
            if d.kind == Up { (tip.lift)(); held.val = 0 }
            else if d.kind == Off { (tip.cancel)(); held.val = 0 }
          } else if held.val == 2 {
            if d.kind == Up && on_tile(d) { press() }
            if d.kind == Up || d.kind == Off { held.val = 0 }
          } else if d.kind == Up && @ui.pointing() is Mouse && on_tile(d) {
            press()
          }
        },
      ) |> ignore
    })
  })
}

///|
fn usage_tile_node(tile : @view.View, figure : () -> String, name : () -> String, level : () -> String) -> Unit {
  @sf.style_node(tile, fn() { agent_card_tile }, in_row=true)
  usage_figure_node(tile, figure, level)
  @sf.words_node(tile, name, fn() { agent_card_tile_name }) |> ignore
}

///|
fn usage_figure_node(tile : @view.View, figure : () -> String, level : () -> String) -> Unit {
  @sf.words_node(tile, figure, fn() {
    match level() {
      "red" => agent_card_figure_red
      "amber" => agent_card_figure_amber
      _ => agent_card_figure
    }
  }) |> ignore
}
