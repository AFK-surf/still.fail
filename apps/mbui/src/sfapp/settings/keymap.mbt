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
fn key_actions(prefs : Json?) -> Array[Json] {
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
  if @ui.platform() == 0 {
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
fn binding_of(code : Int, mods : Int) -> String? {
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
  let mac = @ui.platform() == 0
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
  if keys_recording.val != "" {
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
/// An action's keys changed (`keys.set`: none, its own again; no action, every one's), what the core says of it
/// (keys another action had, moved here) said.
fn set_keys(core : Core, action : String?, keys : Json) -> Unit {
  let params = match action {
    Some(a) => obj([("action", str(a)), ("keys", keys)])
    None => obj([])
  }
  (core.call)("keys.set", params, fn(r) {
    match r {
      Ok(v) =>
        match text(Some(v), "said") {
          "" => ()
          said => (core.say)(said)
        }
      Err(_) => ()
    }
  })
}

///|
/// 快捷键 (Shortcuts.tsx ShortcutsPage): each group's actions, their keys; pressed, the next key press is its new keys
/// (Esc leaves them, ⌫ clears them; keys another action had are moved here, said so); 恢复默认 an action's own again,
/// 全部恢复默认 every one's. Kept on this device.
fn shortcuts_page(c : @ui.Ctx, core : Core) -> Unit {
  let prefs = (core.topic)("prefs", Map::new()).value
  let keymap = field(prefs, "keymap")
  // recording: the next key press
  let recording = keys_recording.val
  if recording != "" {
    for k in c.keys() {
      let (code, mods, _) = k
      if code == @ui.key_escape && mods == 0 {
        keys_recording.val = ""
        break
      }
      if code == 1 && mods == 0 {
        // ⌫: none
        c.after_build("keys-clear", fn() { set_keys(core, Some(recording), Json::array([])) })
        keys_recording.val = ""
        break
      }
      match binding_of(code, mods) {
        Some(b) => {
          c.after_build("keys-set", fn() { set_keys(core, Some(recording), Json::array([Json::string(b)])) })
          keys_recording.val = ""
          break
        }
        None => ()
      }
    }
  }
  let listed = key_actions(prefs).filter(fn(a) { flag(Some(a), "listed") })
  let any = listed.iter().any(fn(a) { flag(Some(a), "changed") })
  let blocks : Array[() -> Unit] = []
  for i, g in items(keymap, "groups") {
    let group = text(Some(g), "group")
    blocks.push(fn() {
      @sf.section(
        c,
        text(Some(g), "name"),
        note=if i == 0 { tr("web-main.shortcuts.hint") } else { "" },
        actions?=if i == 0 && any {
          Some(fn() {
            if keys_toggle(c, "keys-reset-all", tr("web-main.shortcuts.resetAll")) {
              c.after_build("keys-reset-all", fn() { set_keys(core, None, Json::null()) })
            }
          })
        } else {
          None
        },
        fn() {
          c.box(style=keys_rows, fn() {
            for a in listed {
              if text(Some(a), "group") == group {
                keys_row(c, core, a)
              }
            }
          })
          |> ignore
        },
      )
    })
  }
  desk_page(c, core, "shortcuts", tr("web-main.shortcuts.title"), blocks)
}

///|
/// An action's row (Shortcuts.css.ts row): its name, 恢复默认 once changed, its keys on a button that, pressed, records
/// new ones.
fn keys_row(c : @ui.Ctx, core : Core, a : Json) -> Unit {
  let av = Some(a)
  let action = text(av, "action")
  let on = keys_recording.val == action
  c.box(style=keys_row_box, fn() {
    c.box(style=keys_row_label, fn() { c.text(text(av, "name"), style=keys_row_words) |> ignore }) |> ignore
    if flag(av, "changed") && keys_toggle(c, "keys-reset/" + action, tr("web-main.shortcuts.reset")) {
      c.after_build("keys-reset/" + action, fn() { set_keys(core, Some(action), Json::null()) })
    }
    let id = c.id("keys/" + action)
    c.cursor(id, Hand)
    c.focusable(id)
    let none = strings(av, "keys").length() == 0
    c.box(
      id~,
      style=if on {
        keys_record_on
      } else if c.hovered(id) {
        keys_record_hot
      } else {
        keys_record
      },
      fn() {
        c.text(if on { tr("web-main.shortcuts.recording") } else { text(av, "text") }, style=if on {
          keys_record_on_words
        } else if none {
          keys_record_none
        } else {
          keys_record_words
        })
        |> ignore
      },
    )
    |> ignore
    if hit(c, id) {
      keys_recording.val = if on { "" } else { action }
    }
  })
  |> ignore
}

///|
/// A quiet word to press (controls.css.ts textToggle): 12 muted, the words' colour pointed at. Whether it was pressed.
fn keys_toggle(c : @ui.Ctx, key : String, words : String) -> Bool {
  let id = c.id(key)
  c.cursor(id, Hand)
  c.focusable(id)
  c.box(id~, style=keys_toggle_box, fn() {
    c.text(words, style=if c.hovered(id) { keys_toggle_hot } else { keys_toggle_words }) |> ignore
  })
  |> ignore
  hit(c, id)
}

///|
// kept across runs: a value (no field of it changes)
let keys_rows : @ui.Style = @ui.style(w=Full, gap=S0_5)

///|
/// (Shortcuts.css.ts row: 40 high at least, 8 apart, the list's words)
// kept across runs: a value (no field of it changes)
let keys_row_box : @ui.Style = @ui.style(row=true, w=Full, min_h=S10, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let keys_row_label : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let keys_row_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L5, color=Fg, w=Full)

///|
/// Its keys (Shortcuts.css.ts record): 120 wide at least, 30 high, 12 in, the field's corner, the hover ground (the
/// selected one pointed at), in the middle; none, subtle; recording, the accent's ground and words.
// kept across runs: a value (no field of it changes)
let keys_record : @ui.Style = @ui.style(
  row=true,
  min_w=Fixed(keys_record_w),
  h=Fixed(keys_record_h),
  px=S3,
  radius=Xl,
  bg=Hover,
  align=ACenter,
  justify=JCenter,
)

///|
let keys_record_w : Double = 120.0

///|
let keys_record_h : Double = 30.0

///|
// kept across runs: a value (no field of it changes)
let keys_record_hot : @ui.Style = keys_record.then(@ui.style(bg=Selected))

///|
// kept across runs: a value (no field of it changes)
let keys_record_on : @ui.Style = keys_record.then(@ui.style(bg=AccentBg))

///|
// kept across runs: a value (no field of it changes)
let keys_record_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L5, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let keys_record_none : @ui.TextStyle = keys_record_words.then(@ui.text_style(color=Subtle))

///|
// kept across runs: a value (no field of it changes)
let keys_record_on_words : @ui.TextStyle = keys_record_words.then(@ui.text_style(color=AccentText))

///|
/// (controls.css.ts textToggle: 2 by 4 in)
// kept across runs: a value (no field of it changes)
let keys_toggle_box : @ui.Style = @ui.style(px=S1, py=S0_5)

///|
// kept across runs: a value (no field of it changes)
let keys_toggle_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L4_75, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let keys_toggle_hot : @ui.TextStyle = keys_toggle_words.then(@ui.text_style(color=Fg))

///|
/// A key cap (Shortcuts.css.ts record): a capsule on the words' tint; recording, the accent's ring.
// kept across runs: a value (no field of it changes)
let keys_cap : @ui.Style = @ui.style(h=S7, px=S3, align=ACenter, justify=JCenter, radius=Lg, bg=Tint, border=B1, border_color=Clear)

///|
// kept across runs: a value (no field of it changes)
let keys_cap_on : @ui.Style = keys_cap.then(@ui.style(border_color=Accent))

///|
// kept across runs: a value (no field of it changes)
let keys_cap_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let keys_reset_box : @ui.Style = @ui.style(px=S2, py=S1, radius=Base, hovered=@ui.patch(bg=Hover))

///|
// kept across runs: a value (no field of it changes)
let keys_reset_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// 版本 (AppVersion.tsx AppVersionPage): still.fail's desktop app's version, what is under way of a newer one, and the
/// way to it (检查更新, 更新到 …).
fn version_page(c : @ui.Ctx, core : Core) -> Unit {
  let (words, newer) = (core.version_words)()
  scroll_page(c, "version", [
    fn() { top_back(c, core, tr("android-settings.title")) },
    fn() { large_title(c, tr("web-pages.settings.nav.version")) },
    fn() {
      section_header(c, fill("web-pages.version.title", [("name", "still.fail")]))
      section_note(c, tr("web-pages.version.lead"))
    },
    fn() {
      list_card(c, boxed=true, fn() {
        if list_row(c, key="version-app", fn() {
            row_title(c, "still.fail mbui " + build_version())
            c.box(style=if newer { keys_cap_on } else { keys_cap }, fn() {
              c.text(words, style=if newer { keys_cap_accent } else { keys_cap_words }) |> ignore
            })
            |> ignore
          }) {
          (core.version_tap)()
        }
      })
    },
    fn() { gap(c, 30.0) },
  ])
}

///|
// kept across runs: a value (no field of it changes)
let keys_cap_accent : @ui.TextStyle = @ui.text_style(size=Xs, color=AccentText, wrap=false)

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
