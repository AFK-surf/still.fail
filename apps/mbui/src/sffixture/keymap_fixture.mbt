// The fixture's keymap, as the core makes it (client/core-ts/src/keymap.ts view, change): the desktop app's (a Mac's or
// Windows'), its keys changed with `keys.set`.

///|
/// The actions, their group, their own keys and the desktop app's before them (keymap.ts ACTIONS).
// kept across runs: a table, never written
pub let fx_key_actions : Array[(String, String, Array[String], Array[String], String)] = [
  ("chat.switch", "global", ["Mod+K"], [], "yes"),
  ("chat.new", "global", ["Alt+Mod+N"], ["Mod+N"], "yes"),
  ("chat.prev", "global", ["Alt+Up"], [], "yes"),
  ("chat.next", "global", ["Alt+Down"], [], "yes"),
  ("sidebar.toggle", "global", ["Mod+\\"], [], "yes"),
  ("nav.back", "global", [], ["Mod+["], "yes"),
  ("nav.forward", "global", [], ["Mod+]"], "yes"),
  ("settings", "global", [], ["Mod+,"], "yes"),
  ("shortcuts", "global", ["Mod+/"], [], "yes"),
  ("composer.focus", "chat", ["Space"], [], "no"),
  ("composer.file", "chat", ["Mod+U"], [], "yes"),
  ("chat.stop", "chat", ["Mod+."], [], "yes"),
  ("chat.history", "chat", ["Shift+Mod+H"], [], "yes"),
  ("chat.jobs", "chat", ["Shift+Mod+J"], [], "yes"),
  ("chat.screen", "chat", ["Shift+Mod+D"], [], "yes"),
  ("chat.latest", "chat", ["Mod+Down"], [], "empty"),
  ("chat.find", "chat", ["Mod+F"], [], "yes"),
  ("chat.archive", "chat", ["Shift+Mod+E"], [], "yes"),
  ("panel.close", "chat", ["Escape"], [], "yes"),
  ("files.preview", "files", ["Shift+Mod+P"], [], "yes"),
]

///|
/// A binding as a key cap shows it (keymap.ts label): ⌘⇧H on a Mac, Ctrl+Shift+H elsewhere.
pub fn fx_key_label(b : String, mac : Bool) -> String {
  let parts = b.split("+").map(fn(p) { p.to_string() }).collect()
  let key = parts.pop().unwrap_or("")
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
  if mac {
    [("Ctrl", "⌃"), ("Alt", "⌥"), ("Shift", "⇧"), ("Mod", "⌘")]
    .filter(fn(m) { parts.contains(m.0) })
    .map(fn(m) { m.1 })
    .join("") +
    shown
  } else {
    let named = ["Mod", "Ctrl", "Alt", "Shift"]
      .filter(fn(m) { parts.contains(m) })
      .map(fn(m) { if m == "Mod" { "Ctrl" } else { m } })
    named.push(shown)
    named.join("+")
  }
}

///|
/// The keys that do an action: changed here, or its own (the desktop app's first).
pub fn fx_keys_of(changed : Map[String, Array[String]], a : (String, String, Array[String], Array[String], String)) -> Array[String] {
  match changed.get(a.0) {
    Some(keys) => keys
    None => a.3 + a.2
  }
}

///|
/// The prefs' `keymap` (KeymapView) with `changed` the keys changed here; as on a Mac where the Tester plays one.
pub fn fixture_keymap(changed : Map[String, Array[String]]) -> Json {
  let mac = @ui.platform() == 0
  let actions = fx_key_actions.map(fn(a) {
    let keys = fx_keys_of(changed, a)
    let labels = keys.map(fn(b) { fx_key_label(b, mac) })
    Json::object({
      "action": Json::string(a.0),
      "group": Json::string(a.1),
      "name": Json::string(tr("web-main.keymap." + a.0)),
      "typing": Json::string(a.4),
      "keys": Json::array(keys.map(Json::string(_))),
      "labels": Json::array(labels.map(Json::string(_))),
      "text": Json::string(if labels.length() == 0 { tr("web-main.shortcuts.unset") } else { labels.join(" / ") }),
      "changed": Json::boolean(changed.contains(a.0)),
      "listed": Json::boolean(true),
    })
  })
  let ws = [1, 2, 3, 4, 5, 6, 7, 8, 9].map(fn(n) {
    Json::string(fx_key_label(if mac { "Ctrl+\{n}" } else { "Alt+\{n}" }, mac))
  })
  Json::object({
    "changeable": Json::boolean(true),
    "mac": Json::boolean(mac),
    "groups": Json::array(
      ["global", "chat", "files"].map(fn(g) {
        Json::object({ "group": Json::string(g), "name": Json::string(tr("web-main.keymap.group." + g)) })
      }),
    ),
    "actions": Json::array(actions),
    "workspace": Json::array(ws),
  })
}

///|
/// `keys.set` (keymap.ts change): an action's keys (null: its own again), each taken from any other action that had
/// it, said so; no action, every one's own again. What it answers: `{moved, said}`.
pub fn fixture_keys_set(changed : Map[String, Array[String]], params : Json) -> Json {
  let action = match field(Some(params), "action") {
    Some(String(a)) => a
    _ => {
      changed.clear()
      return { "moved": [], "said": Json::null() }
    }
  }
  let keys = match field(Some(params), "keys") {
    Some(Array(a)) => Some(a.filter_map(fn(k) { if k is String(s) { Some(s) } else { None } }))
    _ => None
  }
  let moved : Array[Json] = []
  let mut said = Json::null()
  match keys {
    Some(ks) => {
      for a in fx_key_actions {
        if a.0 == action {
          continue
        }
        let had = fx_keys_of(changed, a)
        if had.iter().any(fn(b) { ks.contains(b) }) {
          changed[a.0] = had.filter(fn(b) { !ks.contains(b) })
          moved.push(Json::string(a.0))
          if said is Null {
            let b = ks.iter().find_first(fn(b) { had.contains(b) }).unwrap_or("")
            said = Json::string(
              fill("web-main.shortcuts.moved", [("keys", fx_key_label(b, @ui.platform() == 0)), ("action", tr("web-main.keymap." + a.0))]),
            )
          }
        }
      }
      changed[action] = ks
    }
    None => changed.remove(action)
  }
  { "moved": Json::array(moved), "said": said }
}

///|
/// The prefs' `keys`: each action's keys changed here.
pub fn fixture_keys(changed : Map[String, Array[String]]) -> Json {
  let o : Map[String, Json] = {}
  for k, v in changed {
    o[k] = Json::array(v.map(Json::string(_)))
  }
  Json::object(o)
}
