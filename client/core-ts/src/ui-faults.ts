// What of a UI fault leaves the device: its category alone, never its text (which can hold editor keys made from file
// paths). The app sorts its faults by this list (apps/mbui/src/stillfail/ui_faults.mbt is made from it by
// scripts/ui-faults.ts) and the core takes no other category, whatever an app sends.

/** How a fault's text is recognised: the whole of it, or how it starts. */
export const UI_FAULTS: readonly { said: string; whole: boolean; category: string }[] = [
  { said: "Ctx::editor: one Field given to two editors in one build (", whole: false, category: "editor field reused" },
  { said: "Ctx::editor: a Field given to ", whole: false, category: "editor field already in tree" },
  { said: "field: one Field given to two fields of the tree's: a Field is one editor's", whole: true, category: "tree field reused" },
  { said: "scene: a frame put together round layers drawn again where they were not kept: ", whole: false, category: "scene layer conflict" },
  { said: "presented beside a node of the tree, drawn by the old frame: a kind of panel panel_node does not take yet", whole: true, category: "panel cannot be presented" },
];

/** Any other fault. */
export const UI_FAULT_OTHER = "UI fault";

/** The categories a UI fault may be reported as. */
export const UI_FAULT_CATEGORIES: readonly string[] = [UI_FAULT_OTHER, ...UI_FAULTS.map((f) => f.category)];
