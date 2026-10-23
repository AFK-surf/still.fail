// The wide frame's shortcuts as kept on this device (ember web/src/keymap.ts): each action's keys, the app's own unless
// changed (prefs `keys`: an action's bindings, null its own again), a binding as words (Mod+Shift+H) and as a key cap
// (⌘⇧H on a Mac, Ctrl+Shift+H elsewhere); the 快捷键 page where they are changed by pressing new ones (Shortcuts.tsx).

///|
/// The actions this app has keys for, by part, with their own keys (keymap.ts ACTIONS, the desktop app's).
// kept across runs: a table, never written
let key_actions : Array[(String, String, Array[String])] = [
  ("chat.switch", "global", ["Mod+K"]),
  ("chat.new", "global", ["Mod+N"]),
  ("chat.prev", "global", ["Alt+Up"]),
  ("chat.next", "global", ["Alt+Down"]),
  ("sidebar.toggle", "global", ["Mod+\\"]),
  ("settings", "global", ["Mod+,"]),
  ("shortcuts", "global", ["Mod+/"]),
  ("composer.focus", "chat", ["Space"]),
  ("composer.file", "chat", ["Mod+U"]),
  ("chat.stop", "chat", ["Mod+."]),
  ("chat.history", "chat", ["Mod+Shift+H"]),
  ("chat.jobs", "chat", ["Mod+Shift+J"]),
  ("chat.latest", "chat", ["Mod+Down"]),
  ("chat.find", "chat", ["Mod+F"]),
  ("chat.archive", "chat", ["Mod+Shift+E"]),
  ("panel.close", "chat", ["Escape"]),
]

///|
/// The keys changed here before the prefs say them back (an action's bindings; null its own again).
let keys_set : Map[String, Json] = {}

///|
/// The action whose new keys the next key press is ("" none): the page's.
pub let keys_recording : Ref[String] = Ref("")

///|
fn keymap_reset() -> Unit {
  keys_set.clear()
  keys_recording.val = ""
  action_asked.val = ""
}

///|
/// An action's own keys.
fn own_keys(action : String) -> Array[String] {
  match key_actions.iter().find_first(fn(a) { a.0 == action }) {
    Some((_, _, keys)) => keys
    None => []
  }
}

///|
/// The keys that do `action` here (`prefs` the core's prefs): changed on this device, or its own.
pub fn keys_of(prefs : Json?, action : String) -> Array[String] {
  let kept = match keys_set.get(action) {
    Some(v) => Some(v)
    None => field(field(prefs, "keys"), action)
  }
  match kept {
    Some(Array(a)) => a.filter_map(fn(b) { if b is String(s) { Some(s) } else { None } })
    _ => own_keys(action)
  }
}

///|
/// Whether an action's keys were changed on this device.
fn keys_changed(prefs : Json?, action : String) -> Bool {
  match keys_set.get(action) {
    Some(Array(_)) => true
    Some(_) => false
    None => field(field(prefs, "keys"), action) is Some(Array(_))
  }
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
/// The keys' names a binding's key has (keymap.ts CODES), by its code.
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
/// A binding (Mod+Shift+H) as the key's code and the modifiers held, or None for one this app cannot have.
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
/// The binding a key press makes (Mod+Shift+H; keymap.ts bindingOf), or None for a key that is none here.
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
/// A binding as a key cap shows it (keymap.ts keyLabel): ⌘⇧H on a Mac, Ctrl+Shift+H elsewhere.
pub fn key_label(binding : String) -> String {
  let parts = binding.split("+").map(fn(p) { p.to_string() }).collect()
  let key = parts.last().unwrap_or("")
  let mods = parts[:dmax(0.0, (parts.length() - 1).to_double()).to_int()].to_array()
  let shown = match key {
    "Space" => tr("web-main.keymap.space")
    "Up" => "↑"
    "Down" => "↓"
    "Left" => "←"
    "Right" => "→"
    "Escape" => "Esc"
    "Enter" => "↩"
    k => k
  }
  if @ui.platform() == 0 {
    let marks = [("Ctrl", "⌃"), ("Alt", "⌥"), ("Shift", "⇧"), ("Mod", "⌘")]
    marks.filter(fn(m) { mods.contains(m.0) }).map(fn(m) { m.1 }).join("") + shown
  } else {
    let named = mods.map(fn(m) { if m == "Mod" { "Ctrl" } else { m } })
    named.push(shown)
    named.join("+")
  }
}

///|
/// An action's keys as words ("未设置" none).
pub fn keys_text(prefs : Json?, action : String) -> String {
  match keys_of(prefs, action) {
    [] => tr("web-main.shortcuts.unset")
    keys => keys.map(key_label).join(" / ")
  }
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
/// An action's keys changed (`prefs.set {keys: {action: …}}`): shown at once.
fn set_keys(core : Core, action : String, keys : Json) -> Unit {
  keys_set[action] = keys
  (core.call)("prefs.set", obj([("keys", obj([(action, keys)]))]), fn(_) {  })
}

///|
/// 快捷键 (Shortcuts.tsx ShortcutsPage): each part's actions, their keys; pressed, the next key press is its new keys
/// (Esc leaves them, ⌫ clears them; keys another action had are moved here, said so); 恢复默认 an action's own again,
/// 全部恢复默认 every one's. Kept on this device.
fn shortcuts_page(c : @ui.Ctx, core : Core) -> Unit {
  let prefs = (core.topic)("prefs", Map::new()).value
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
        c.after_build("keys-clear", fn() { set_keys(core, recording, Json::array([])) })
        keys_recording.val = ""
        break
      }
      match binding_of(code, mods) {
        Some(b) => {
          let other = key_actions.iter().find_first(fn(a) { a.0 != recording && keys_of(prefs, a.0).contains(b) })
          c.after_build("keys-set", fn() {
            match other {
              Some((o, _, _)) => {
                set_keys(core, o, Json::array(keys_of(prefs, o).filter(fn(x) { x != b }).map(fn(x) { Json::string(x) })))
                (core.say)(fill("web-main.shortcuts.moved", [("keys", key_label(b)), ("action", tr("web-main.keymap." + o))]))
              }
              None => ()
            }
            set_keys(core, recording, Json::array([Json::string(b)]))
          })
          keys_recording.val = ""
          break
        }
        None => ()
      }
    }
  }
  let any = key_actions.iter().any(fn(a) { keys_changed(prefs, a.0) })
  let blocks : Array[() -> Unit] = [
    fn() { top_back(c, core, tr("android-settings.title")) },
    fn() { large_title(c, tr("web-main.shortcuts.title")) },
  ]
  for i, group in ["global", "chat"] {
    blocks.push(fn() {
      section_header(c, tr("web-main.keymap.group." + group))
      if i == 0 {
        section_note(c, tr("web-main.shortcuts.hint"))
      }
    })
    blocks.push(fn() {
      list_card(c, boxed=true, fn() {
        for a in key_actions {
          let (action, g, _) = a
          if g != group {
            continue
          }
          let on = keys_recording.val == action
          if list_row(c, key="keys/" + action, fn() {
              row_title(c, tr("web-main.keymap." + action))
              if keys_changed(prefs, action) && !on {
                let rid = c.id("keys-reset/" + action)
                if hit(c, rid) {
                  set_keys(core, action, Json::null())
                }
                c.cursor(rid, Hand)
                c.box(style=keys_reset_box, id=rid, fn() {
                  c.text(tr("web-main.shortcuts.reset"), style=keys_reset_words) |> ignore
                })
                |> ignore
              }
              c.box(style=if on { keys_cap_on } else { keys_cap }, fn() {
                c.text(if on { tr("web-main.shortcuts.recording") } else { keys_text(prefs, action) }, style=keys_cap_words)
                |> ignore
              })
              |> ignore
            }) {
            keys_recording.val = if on { "" } else { action }
          }
        }
      })
    })
  }
  if any {
    blocks.push(fn() {
      list_card(c, boxed=true, fn() {
        if list_row(c, key="keys-reset-all", fn() { row_title(c, tr("web-main.shortcuts.resetAll")) }) {
          for a in key_actions {
            set_keys(core, a.0, Json::null())
          }
        }
      })
    })
  }
  blocks.push(fn() { gap(c, 30.0) })
  scroll_page(c, "shortcuts", blocks)
}

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
