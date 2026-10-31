// The wide frame's shortcuts, as the core says them (the prefs' `keymap`, client/core-ts/src/keymap.ts): each action,
// where it works, its keys here and as a key cap shows them, changed with `keys.set`. What is the app's own here is a
// key press turned into a binding (Mod+Shift+H) and a binding into a key press; and the 快捷键 page (Shortcuts.tsx),
// where they are changed by pressing new ones.

///|
/// The action whose new keys the next key press is ("" none): the page's.
pub let keys_recording : Ref[String] = Ref("")

///|
fn keymap_reset() -> Unit {
  keys_recording.val = ""
  action_asked.val = ""
}

///|
/// The core's keymap's actions (KeyAction), in the order they are listed.
pub fn key_actions(prefs : Json?) -> Array[Json] {
  items(field(prefs, "keymap"), "actions")
}

///|
/// An action as the keymap has it.
fn key_action(prefs : Json?, action : String) -> Json? {
  key_actions(prefs).iter().find_first(fn(a) { text(Some(a), "action") == action })
}

///|
/// The keys that do `action` here (`prefs` the core's prefs): bindings, Shift+Mod+H.
pub fn keys_of(prefs : Json?, action : String) -> Array[String] {
  strings(key_action(prefs, action), "keys")
}

///|
/// An action's first keys as a key cap shows them ("" none): ⌘⇧H on a Mac, Ctrl+Shift+H elsewhere.
pub fn key_label(prefs : Json?, action : String) -> String {
  match strings(key_action(prefs, action), "labels") {
    [first, ..] => first
    [] => ""
  }
}

///|
/// An action's keys in words, as the list of shortcuts says them ("未设置" none).
pub fn keys_text(prefs : Json?, action : String) -> String {
  text(key_action(prefs, action), "text")
}

///|
/// The modifier said `Mod`: ⌘ on a Mac, Ctrl elsewhere.
fn mod_key() -> Int {
  if @ui.keys_system() == 0 {
    @ui.mod_cmd
  } else {
    @ui.mod_ctrl
  }
}

///|
/// The keys' names a binding's key has (keymap.ts NAMED), by its code.
// kept across runs: a table, never written
let key_names : Array[(String, Int)] = [
  ("Up", 5),
  ("Down", 6),
  ("Left", 3),
  ("Right", 4),
  ("Enter", 7),
  ("Escape", 17),
  ("Space", 1032),
  ("Plus", 1043),
]

///|
/// A binding (Shift+Mod+H) as the key's code and the modifiers held, or None for one this app cannot have.
fn binding_key(binding : String) -> (Int, Int)? {
  let parts = binding.split("+").map(fn(p) { p.to_string() }).collect()
  // (a plus itself is no binding: the last part is always the key)
  let key = match parts.last() {
    Some(k) => k
    None => return None
  }
  let mut mods = 0
  for p in parts[:parts.length() - 1] {
    match p {
      "Mod" => mods = mods | mod_key()
      "Shift" => mods = mods | @ui.mod_shift_key
      "Alt" => mods = mods | @ui.mod_alt
      "Ctrl" => mods = mods | @ui.mod_ctrl
      _ => return None
    }
  }
  let code = match key_names.iter().find_first(fn(n) { n.0 == key }) {
    Some((_, code)) => code
    None =>
      match key.to_array() {
        [ch] => @ui.key_of_char(lower_char(ch))
        _ => return None
      }
  }
  Some((code, mods))
}

///|
fn lower_char(ch : Char) -> Char {
  let n = ch.to_int()
  if n >= 65 && n <= 90 {
    (n + 32).unsafe_to_char()
  } else {
    ch
  }
}

///|
/// The binding a key press makes (Shift+Mod+H: the modifiers in the core's order, Ctrl, Alt, Shift, Mod; keymap.ts
/// binding), or None for a key that is none here.
pub fn binding_of(code : Int, mods : Int) -> String? {
  let key = match key_names.iter().find_first(fn(n) { n.1 == code }) {
    Some((name, _)) => name
    None =>
      if code > 1032 && code < 1127 {
        let ch = (code - 1000).unsafe_to_char()
        let n = ch.to_int()
        if n >= 97 && n <= 122 {
          (n - 32).unsafe_to_char().to_string()
        } else {
          ch.to_string()
        }
      } else {
        return None
      }
  }
  let mac = @ui.keys_system() == 0
  let parts : Array[String] = []
  if mac && (mods & @ui.mod_ctrl) != 0 {
    parts.push("Ctrl")
  }
  if (mods & @ui.mod_alt) != 0 {
    parts.push("Alt")
  }
  if (mods & @ui.mod_shift_key) != 0 {
    parts.push("Shift")
  }
  if (mods & mod_key()) != 0 {
    parts.push("Mod")
  }
  parts.push(key)
  Some(parts.join("+"))
}

///|
/// Whether one of `action`'s keys came since the last frame (with `in_field`, one a focused field took too); none while
/// the 快捷键 page records new ones.
pub fn action_pressed(c : @ui.Ctx, prefs : Json?, action : String, in_field? : Bool = false) -> Bool {
  // chosen from the Mac's menu bar since the last frame: as if one of its keys was
  if action_asked.val == action {
    return true
  }
  // (no key came: none of its keys did, its bindings not looked up and read)
  if keys_recording.val != "" || !c.keys_came() {
    return false
  }
  keys_of(prefs, action).iter().any(fn(b) {
    match binding_key(b) {
      Some((code, mods)) => c.key_pressed(code, mods~, in_field~)
      None => false
    }
  })
}

///|
/// The action chosen from the Mac's menu bar since the last frame ("" none: the app's menu_bar.mbt), read by
/// `action_pressed` as one of its keys.
let action_asked : Ref[String] = Ref("")

///|
/// One of the menu bar's items chosen: `action` done by the frame after, as if one of its keys was pressed.
pub fn ask_action(action : String) -> Unit {
  action_asked.val = action
}

///|
/// The frame that read it built: asked no more.
pub fn action_asked_done() -> Unit {
  action_asked.val = ""
}

///|
/// The keymap's groups (where the actions work, as the list of shortcuts heads them), each with its listed actions'
/// names and keys in words: the shortcuts at a glance (⌘/).
pub fn key_groups(prefs : Json?) -> Array[(String, Array[(String, String)])] {
  items(field(prefs, "keymap"), "groups").map(fn(g) {
    let group = text(Some(g), "group")
    let rows = key_actions(prefs)
      .filter(fn(a) { flag(Some(a), "listed") && text(Some(a), "group") == group })
      .map(fn(a) { (text(Some(a), "name"), text(Some(a), "text")) })
    (text(Some(g), "name"), rows)
  })
}

///|
/// The keys that switch to the workspaces at the first and the last place of its menu, as shown (⌃1, ⌃9).
pub fn workspace_keys(prefs : Json?) -> (String, String) {
  let all = strings(field(prefs, "keymap"), "workspace")
  (all.get(0).unwrap_or(""), all.last().unwrap_or(""))
}

///|
/// Whether keys can be changed here (the desktop app's).
pub fn keys_changeable(prefs : Json?) -> Bool {
  flag(field(prefs, "keymap"), "changeable")
}
