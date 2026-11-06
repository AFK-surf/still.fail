// An agent's cost, cache and context as nodes of the window's tree. Each figure is made only while it is known;
// what it says, its colour and the context's action follow the card and entry supplied by its caller.

///|
/// The figures in `card`, with `top` over them. `entry` gives the context's action and its current state; without it
/// the context is a figure only (as in the history). `tips` is the window's layer for a failed action's explanation.
fn agent_tiles_node(
  parent : @view.View,
  card : () -> Json?,
  top? : Double = 0.0,
  entry? : () -> ContextTile? = fn() { None },
  tips? : @sf.TipLayer,
) -> Unit {
  let cost = fn() { text(card(), "cost") }
  let cache = fn() { field(card(), "cache") }
  let context = fn() { field(card(), "context") }
  let context_figure = fn() {
    if flag(context(), "unknown") {
      text(context(), "text")
    } else {
      "\{number(context(), "percent").round().to_int()}%"
    }
  }
  let context_name = fn() { context_tile_label(entry(), text(context(), "level")) }
  let context_color = fn() {
    let t = @sf.theme()
    if flag(context(), "unknown") { t.p.text } else {
      match text(context(), "level") {
        "red" => t.p.red
        "amber" => t.p.warn_ink
        _ => t.p.text
      }
    }
  }
  parent.show(fn() { cost() != "" || cache() is Some(Object(_)) || context() is Some(Object(_)) }, fn(row) {
    row.row(Is(true)).width_share(Is(1.0)).padding(Is((0.0, top, 0.0, 0.0))).gap(Is(8.0)) |> ignore
    row.show(fn() { cost() != "" }, fn(tile) {
      agent_figure_node(tile, cost, fn() { tr("android-chat.agent.cost") }, fn() { @sf.theme().p.text }, fn() { None }, false, tips)
    })
    row.show(fn() { cache() is Some(Object(_)) }, fn(tile) {
      agent_figure_node(tile, fn() { text(cache(), "text") }, fn() { tr("android-chat.agent.cache") }, fn() { @sf.theme().p.text }, fn() { None }, false, tips)
    })
    row.show(fn() { context() is Some(Object(_)) && entry() is None }, fn(tile) {
      agent_figure_node(tile, context_figure, context_name, context_color, entry, false, tips)
    })
    row.show(fn() { context() is Some(Object(_)) && entry() is Some(_) }, fn(tile) {
      agent_figure_node(tile, context_figure, context_name, context_color, entry, true, tips)
    })
  })
}

///|
/// One figure's block. Its label combines its name and figure for a screen reader; a context with an entry can be
/// pressed by touch, mouse, keyboard or accessibility action, and is ignored while its action is busy.
fn agent_figure_node(
  tile : @view.View,
  figure : () -> String,
  name : () -> String,
  color : () -> Int64,
  entry : () -> ContextTile?,
  interactive : Bool,
  tips : @sf.TipLayer?,
) -> Unit {
  tile
  .grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0)))
  .padding(Is((@sf.text_in, 9.0, @sf.text_in, 8.0)))
  .radius(Is(@sf.row_corner))
  .ground(By(fn() { @sf.alpha(@sf.theme().p.text, 0.05) }))
  .says(By(fn() {
    Some(@view.said(if interactive { Button } else { Text }, label=name() + " " + figure()))
  }))
  |> ignore
  if interactive {
    @sf.presses_node(tile, fn() {
      match entry() {
        Some(e) => if !e.busy { (e.open)() }
        None => ()
      }
    })
  }
  tile.box(fn(line) {
    line.height(Is(Some(26.0))).lies_along(Is(Middle)) |> ignore
    line.box(fn(words) {
      words.words(By(figure)).words_look(By(fn() {
        let size = if figure().length() > 6 { 16.0 } else { 20.0 }
        { size, weight: 600, line: -@ui.tree_theme().text_line, wrap: false, tracking: @view.letters_own, balance: false }
      })).ink(By(color)) |> ignore
    })
    |> ignore
  })
  |> ignore
  tile.box(fn(line) {
    line.row(Is(true)).gap(Is(2.0)).lines_up(Is(Some(Middle))) |> ignore
    @sf.words_node(line, name, fn() { tile_name }) |> ignore
    line.show(fn() { entry() is Some({ busy: true, .. }) }, fn(mark) {
      @sf.spinner_node(mark, size=14.0) |> ignore
    })
    line.show(fn() { entry() is Some({ busy: false, failed: true, .. }) }, fn(mark) {
      let icon = @sf.icon_node(mark, "info", 14.0, By(fn() { @sf.theme().p.red }))
      match tips {
        Some(layer) => @sf.tip_node(layer, icon, fn() { tr("web-main.doing.failed") }, within=true) |> ignore
        None => ()
      }
    })
    line.show(fn() { entry() is Some({ busy: false, failed: false, .. }) }, fn(mark) {
      @sf.icon_node(mark, "chevron-right", 11.0, By(fn() { @sf.theme().p.muted })) |> ignore
    })
  })
  |> ignore
}
