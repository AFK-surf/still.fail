// Made by client/core-ts/scripts/ui-faults.ts from the core's src/ui-faults.ts: do not edit.

///|
/// What of UI fault `said` may be reported: its category, never its text.
fn ui_fault_category(said : String) -> String {
  if said.has_prefix("Ctx::editor: one Field given to two editors in one build (") {
    return "editor field reused"
  }
  if said.has_prefix("Ctx::editor: a Field given to ") {
    return "editor field already in tree"
  }
  if said == "field: one Field given to two fields of the tree's: a Field is one editor's" {
    return "tree field reused"
  }
  if said.has_prefix("scene: a frame put together round layers drawn again where they were not kept: ") {
    return "scene layer conflict"
  }
  if said == "presented beside a node of the tree, drawn by the old frame: a kind of panel panel_node does not take yet" {
    return "panel cannot be presented"
  }
  "UI fault"
}
