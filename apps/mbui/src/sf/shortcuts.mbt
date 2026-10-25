// The keys that do what a control does, said in its tip after its words (web/ui shortcuts.ts, parts.tsx Tip's
// `shortcut`). The app names its actions and says their keys (set_shortcuts); with none, a tip names no keys.

///|
/// An action's keys as said ("" none), as the app said them.
// kept across runs: what the app says once as it starts (set_shortcuts), the same for every run of it
let shortcut_keys_of : Ref[(String) -> String] = Ref(fn(_) { "" })

///|
/// How an action's keys are said (`keys`: "" for none), from now on (setShortcuts).
pub fn set_shortcuts(keys : (String) -> String) -> Unit {
  shortcut_keys_of.val = keys
}

///|
/// The keys that do `action`, as the app says them ("" none: shortcutKeys).
pub fn shortcut_keys(action : String) -> String {
  if action == "" {
    ""
  } else {
    (shortcut_keys_of.val)(action)
  }
}
