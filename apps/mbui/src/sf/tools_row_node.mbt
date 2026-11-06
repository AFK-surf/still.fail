// A row of tools made in the window's tree. Its layout decides which tools leave as their room changes, and the same
// nodes return when it comes back. The menu reads those left out and its own items as they change.

///|
/// One tool in tools_row_node. Its key is unique within the row and stays with the same tool as it moves. `draw` makes
/// its nodes once and binds their changing properties; `instead` supplies the menu items while it is left out.
/// `drop` is its order of leaving (0: never, otherwise the lowest first; equal orders leave from the end first).
pub(all) struct RowTool {
  key : String
  drop : Int
  draw : (@view.View) -> Unit
  instead : () -> Array[MenuItem]
}

///|
pub fn row_tool_of(
  key : String,
  draw : (@view.View) -> Unit,
  drop? : Int = 0,
  instead? : () -> Array[MenuItem] = fn() { [] },
) -> RowTool {
  { key, drop, draw, instead }
}

///|
fn row_tool_named(tools : Array[RowTool], key : String) -> RowTool? {
  for tool in tools {
    if tool.key == key {
      return Some(tool)
    }
  }
  None
}

///|
/// A row of `tools`, made in `parent`, with a ⋯ named `label`. Its actual layout leaves whole tools out in `drop`
/// order. Their `instead` items precede `more`, separated by a line when both have items. Without fixed `more` items,
/// the ⋯ itself is present only while a tool is left out. Both the tool collection and the menu contents are followed;
/// the tools' unique keys keep their nodes as their order and the room change. A tool's `draw` binds its own state,
/// rather than capturing a value to be rebuilt. The returned row can be given its room and alignment by its holder.
pub fn tools_row_node(
  parent : @view.View,
  tools : () -> Array[RowTool],
  more : () -> Array[MenuItem?],
  label : () -> String,
  tips? : TipLayer,
) -> @view.View {
  // A pane is a construction context; window-owned keys can change while this row stays alive.
  let in_panel = in_pane()
  let slots : Map[String, @view.View] = Map([])
  let opened = @signals.signal(false, same=fn(a, b) { a == b })
  let by_key = @signals.signal(false, same=fn(a, b) { a == b })
  let trigger : Ref[@view.View?] = Ref(None)
  let row = parent.box(fn(row) {
    row
    .row(Is(true))
    .lines_up(Is(Some(Middle)))
    .gap(By(fn() { keys_apart(least=tools_apart) }))
    .shrink(Is(1.0))
    .min_width(Is(Some(0.0)))
    .fits(Is(true))
    |> ignore
    row.each(
      fn() { tools().map(fn(tool) { tool.key }) },
      fn(key) { key },
      fn(slot, name) {
        let key = @signals.untracked(fn() { name.get() })
        slots[key] = slot
        slot.owns(fn() { slots.remove(key) }) |> ignore
        slot.drops(By(fn() {
          match row_tool_named(tools(), key) {
            Some(tool) => tool.drop
            None => 0
          }
        })) |> ignore
        match @signals.untracked(fn() { row_tool_named(tools(), key) }) {
          Some(tool) => (tool.draw)(slot)
          None => ()
        }
      },
    )
    row.box(fn(slot) {
      slot.drops(By(fn() { if more().is_empty() { -1 } else { 0 } })) |> ignore
      let button = icon_button_node(
        slot,
        "more",
        label,
        fn() {
          match trigger.val {
            Some(button) => by_key.set(button.focus_shown())
            None => ()
          }
          opened.set(!@signals.untracked(fn() { opened.get() }))
        },
        tips?=tips,
        linked=fn() { if in_panel || @ui.window_keys_own_now() { None } else { Some(window_corner_key()) } },
      )
      trigger.val = Some(button)
      button
      .says(By(fn() { Some(@view.said(Button, label=label(), expanded=opened.get(), pressed=opened.get())) }))
      .on_key(fn(k) {
        if button.focused() && k.code == @ui.key_code_down && k.mods == 0 && !@signals.untracked(fn() { opened.get() }) {
          by_key.set(true)
          opened.set(true)
          true
        } else {
          false
        }
      })
      |> ignore
      // Close when the trigger or any holder leaves or is omitted. The popup lives at the window root and would
      // otherwise remain modal after its anchor disappeared. It stays closed when the anchor returns.
      slot.reacts(fn() { slot.leaving() || slot.shown_nowhere() }, fn(unavailable) {
        if unavailable {
          opened.set(false)
        }
      })
    }) |> ignore
  })
  let contents = fn() {
    let gone : Array[MenuItem?] = []
    for tool in tools() {
      match slots.get(tool.key) {
        Some(slot) if slot.owed_left_out() => for item in (tool.instead)() { gone.push(Some(item)) }
        _ => ()
      }
    }
    let fixed = more()
    if gone.is_empty() {
      fixed
    } else if fixed.is_empty() {
      gone
    } else {
      gone + [None] + fixed
    }
  }
  let popup = popup_root_node(row)
  popup.show(fn() { opened.get() }, leave=@kit.pop_out_ms, fn(layer) {
    layer.over(Is(true)) |> ignore
    match trigger.val {
      Some(button) => {
        let keyboard = @signals.untracked(fn() { by_key.get() })
        menu_node(
          layer,
          fn() { opened.get() },
          fn(_) { button },
          contents,
          "",
          End,
          4.0,
          keyboard,
          !keyboard && @ui.pointing() is Finger,
          fn(item) { opened.set(false); (item.select)() },
          fn() { opened.set(false) },
          exit=true,
        )
      }
      None => ()
    }
  })
  row
}
