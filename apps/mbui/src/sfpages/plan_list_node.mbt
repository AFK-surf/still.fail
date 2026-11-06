// A plan in an agent's work panel or an opened history call, as nodes of the window's tree.

///|
/// A changing list of {text, status} items, in order. The core gives plan items no stable key, so each place in the
/// list owns its row and is told the new item when the list changes.
pub fn plan_list_node(parent : @view.View, list : () -> Array[Json]) -> Unit {
  parent.box(fn(plan) {
    plan.width_share(Is(1.0)).padding(Is((2.0, 0.0, 2.0, 0.0))).gap(Is(2.0)) |> ignore
    plan.each(fn() { list().mapi(fn(i, it) { (i, it) }) }, fn(it) { it.0 }, fn(row, it) {
      let value = fn() { Some(it.get().1) }
      let status = fn() { text(value(), "status") }
      let style = fn() {
        match status() {
          "completed" => tool_plan_done
          "in_progress" => tool_plan_now
          _ => tool_plan_words
        }
      }
      row.width_share(Is(1.0)).row(Is(true)) |> ignore
      row.box(fn(mark) {
        mark.width(Is(Some(16.0))).shrink(Is(0.0))
        .words_runs(By(fn() {
          let (word, ink) = match status() {
            "completed" => ("✓", @sf.theme().p.green)
            "in_progress" => ("›", @sf.theme().p.accent)
            _ => ("·", @sf.theme().p.subtle)
          }
          [@ui.span(word, color=ink)]
        }))
        .words_look(By(fn() { @ui.style_words(tool_plan_words) }))
        .ink(By(fn() { @ui.style_ink(tool_plan_words) })) |> ignore
      }) |> ignore
      row.box(fn(words) {
        words.grow(Is(1.0)).basis(Is(Some(0.0))).shrink(Is(1.0)).min_width(Is(Some(0.0)))
        .words_runs(By(fn() { [@ui.span(text(value(), "text"), strike=status() == "completed")] }))
        .words_look(By(fn() { @ui.style_words(style()) }))
        .ink(By(fn() { @ui.style_ink(style()) })) |> ignore
      }) |> ignore
    })
  }) |> ignore
}
