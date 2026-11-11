// The wide frame's shortcuts, as the core says them (the prefs' `keymap`, client/core-ts/src/keymap.ts): each action,
// where it works, its keys here and as a key cap shows them, changed with `keys.set`. What is the app's own here is a
// key press turned into a binding (Mod+Shift+H) and a binding into a key press; and the 快捷键 page,
// where they are changed by pressing new ones.

///|
/// The action whose new keys the next key press is ("" none): the page's, told as it changes (its keys' button says it
/// records; what else a key does stands aside meanwhile: the keymap's, keymap_of, and window_zoom's).
// kept across runs: put back as a run begins (keymap_reset)
pub let keys_recording : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })

///|
fn keymap_reset() -> Unit {
  keys_recording.set("")
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
  let parts = binding.split("+").map(fn(p) { p.to_owned() }).collect()
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
/// The window's keymap (mbui's view keymap.mbt) as the core's prefs say it: each action's keys here, where it works by
/// its group (anywhere; `Chat` in a chat; `Files` in a folder of the files) and with the cursor in a field by its
/// `typing` (always; never: `!Field`; with the field empty: `!Field || FieldEmpty`); then the app's own, never changed
/// (Escape the frame's `frame.escape`, a mouse's forward button `nav.forward`, ⌃1 … ⌃9 on a Mac and Alt elsewhere
/// `workspace.1` … `workspace.9`, a player's, a reader's and the files' keys where they are up: @sf.player_bindings,
/// reader_bindings, files_bindings). None while the 快捷键 page records new keys: the next key is its.
pub fn keymap_of(prefs : Json?) -> @view.Keymap {
  if keys_recording.get() != "" {
    return @view.Keymap::new([])
  }
  let bindings : Array[@view.Binding] = []
  let stroke = fn(code, mods) -> @view.Stroke { { code, mods } }
  bindings.push({ keys: [stroke(@ui.key_escape, 0)], action: "frame.escape", when: Always })
  bindings.push({ keys: [stroke(@ui.key_forward, 0)], action: "nav.forward", when: Always })
  let held = if @ui.keys_system() == 0 { @ui.mod_ctrl } else { @ui.mod_alt }
  for k in 0..<9 {
    bindings.push({
      keys: [stroke(@ui.key_of_char((49 + k).unsafe_to_char()), held)],
      action: "workspace.\{k + 1}",
      when: Always,
    })
  }
  // (a player's keys where one is up: its own, the library's, sf/player.mbt)
  bindings.append(@sf.player_bindings())
  // (a reader's where a text is read: sf/reader.mbt)
  bindings.append(@sf.reader_bindings())
  // (the files' own where they are: sfdesk's files.mbt)
  bindings.append(files_bindings())
  // (↓ ↑ in a chat's outline, with the cursor in its field too: the row the keys are at, sfpages' outline.mbt)
  bindings.push({ keys: [stroke(@ui.key_code_down, 0)], action: "outline.down", when: In("Outline") })
  bindings.push({ keys: [stroke(@ui.key_code_up, 0)], action: "outline.up", when: In("Outline") })
  // (⇧Enter in ⌘F's bar, with the cursor in its field: the one before, sfpages' find_bar_node.mbt)
  bindings.push({ keys: [stroke(@ui.key_code_enter, @ui.mod_shift_key)], action: "find.prev", when: In("Find") })
  // (what a field offers as it is typed in, where it is open: sf's offers_node.mbt)
  bindings.append(@sf.offers_bindings())
  // (Escape where a search is up, with the cursor in a field too, or a picture's old viewer, not in a field: sfpages'
  // search.mbt, sfbase's viewer.mbt)
  bindings.push({ keys: [stroke(@ui.key_escape, 0)], action: "search.escape", when: In("Search") })
  // (Enter where a message's sharing is asked, whatever has the focus under it: sfpages' outside.mbt)
  bindings.push({ keys: [stroke(@ui.key_code_enter, 0)], action: "outside.yes", when: In("OutsideAsk") })
  bindings.push({
    keys: [stroke(@ui.key_escape, 0)],
    action: "viewer.escape",
    when: All([In("Viewer"), Not(In("Field"))]),
  })
  for a in key_actions(prefs) {
    let action = text(Some(a), "action")
    let group : @view.KeyWhen = match text(Some(a), "group") {
      "chat" => In("Chat")
      "files" => In("Files")
      _ => Always
    }
    let typing : @view.KeyWhen = match text(Some(a), "typing") {
      "no" => Not(In("Field"))
      "empty" => Any([Not(In("Field")), In("FieldEmpty")])
      _ => Always
    }
    let when : @view.KeyWhen = match (group, typing) {
      (Always, w) | (w, Always) => w
      (g, w) => All([g, w])
    }
    for b in keys_of(prefs, action) {
      match binding_key(b) {
        Some((code, mods)) => bindings.push({ keys: [stroke(code, mods)], action, when })
        None => ()
      }
    }
  }
  @view.Keymap::new(bindings)
}

///|
/// One of the menu bar's items chosen: `action` done now by the node of the window's tree that does it (its keymap's
/// actions: View::on_action, an old view's Ctx::on_action), as if one of its keys was pressed.
pub fn ask_action(action : String) -> Unit {
  @ui.view_action(action) |> ignore
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

///|
/// The composer's keys as the core says them (the keymap's `send`): none from a core before it.
fn send_keys(prefs : Json?) -> Json? {
  field(field(prefs, "keymap"), "send")
}

///|
/// Whether ⌘Enter (Ctrl+Enter elsewhere) sends from the composer, Enter a new line (快捷键's choice, `sendKey`).
pub fn sends_by_command(prefs : Json?) -> Bool {
  text(send_keys(prefs), "by") == "mod"
}

///|
/// The keys that send and make a new line from the composer, as shown (↩ and ⇧↩ from a core before the choice).
pub fn send_lines(prefs : Json?) -> (String, String) {
  let s = send_keys(prefs)
  if s is None {
    ("↩", "⇧↩")
  } else {
    (text(s, "send"), text(s, "newline"))
  }
}

///|
/// The files' keys, the app's own, never changed (sfdesk's files.mbt and what is open in it): in the files (`Files`),
/// not with the cursor in a field, ⌘T (Ctrl elsewhere) a new tab, ⌃Tab or ⌘⇧] the next tab and ⌃⇧Tab or ⌘⇧[ the one
/// before, ⌘⌥D the other side, ⌘⇧G a folder by its path (Finder's 前往文件夹).
fn files_bindings() -> Array[@view.Binding] {
  // (not with the cursor in a field, as before: those keys its)
  let files : @view.KeyWhen = All([In("Files"), Not(In("Field"))])
  let shift = @ui.mod_shift_key
  let b = fn(code : Int, mods : Int, action : String, when : @view.KeyWhen) -> @view.Binding {
    { keys: [{ code, mods }], action, when }
  }
  [
    b(@ui.key_of_char('t'), mod_key(), "files.tab_new", files),
    b(@ui.key_tab, @ui.mod_ctrl, "files.tab_next", files),
    b(@ui.key_of_char(']'), mod_key() | shift, "files.tab_next", files),
    b(@ui.key_tab, @ui.mod_ctrl | shift, "files.tab_back", files),
    b(@ui.key_of_char('['), mod_key() | shift, "files.tab_back", files),
    b(@ui.key_of_char('d'), @ui.mod_cmd | @ui.mod_alt, "files.split", files),
    b(@ui.key_of_char('g'), @ui.mod_cmd | shift, "files.go_to", files),
    // (↓ ↑ in 前往文件夹, with the cursor in its field: what is chosen under it, sfdesk's files_go.mbt)
    b(@ui.key_code_down, 0, "files.go_to.down", In("GoTo")),
    b(@ui.key_code_up, 0, "files.go_to.up", In("GoTo")),
  ]
}
