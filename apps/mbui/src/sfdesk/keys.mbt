// The frame's keys (ember web/src/keymap.ts useShortcut, Switcher.tsx GlobalShortcuts, Sidebar.tsx goToNeighbour,
// brand.tsx's sidebar.toggle): ⌘K the switcher, ⌘N a new chat, ⌥↑ / ⌥↓ the chat before or after, ⌘\ the sidebar, ⌘,
// settings, ⌘/ the shortcuts, Esc what the frame opened closed; the keys as the core's prefs keep them on this device
// (settings' 快捷键: prefs.keymap). The page in the pane answers its own after them.

///|
/// The frame's keys, read as its frame is built (before the page's: Esc goes to what the frame opened over it first).
pub fn keys(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let prefs = (src.topic)("prefs", {}).value
  let pressed = fn(action : String) { @settings.action_pressed(c, prefs, action) }
  if pressed("chat.switch") {
    switcher_toggle(c)
    wide.menu = None
    wide.attention_open = false
  }
  if pressed("chat.new") {
    new_chat()
  }
  if pressed("sidebar.toggle") {
    sidebar_toggle()
  }
  if pressed("settings") {
    open_settings()
  }
  if pressed("shortcuts") {
    wide.keys_open = !wide.keys_open
  }
  // (奏's page steps its own decisions: DecisionDesk.tsx step, the one before or after the one it shows)
  let way = if @settings.action_pressed(c, prefs, "chat.prev", in_field=true) {
    -1
  } else if @settings.action_pressed(c, prefs, "chat.next", in_field=true) {
    1
  } else {
    0
  }
  if way != 0 {
    if app.nav.top() == Decisions {
      let view = (src.topic)("decisions", { "workspace": Json::string(w.id) }).value
      let shown = items(view, "items")
      match shown.get(decision_front(view, shown) + way) {
        Some(d) => c.tell("zou/step", fn() { decision_show(src, w, d) })
        None => ()
      }
    } else {
      neighbour(src, w, way)
    }
  }
  let escape = c.key_pressed(@ui.key_escape) || c.key_pressed(@ui.key_escape, in_field=true)
  let left = escape && !frame_escape(c)
  // Esc in the open chat (chat_layers.mbt)
  chat_escape(c, src, left) |> ignore
}

///|
/// Esc to what the frame opened, the one on top first: the rail changed, ⌘K (one kind's list back to all of them,
/// else closed), ⌘/, a menu or 待处理's panel, a row's title renamed. Whether it took it.
fn frame_escape(c : @ui.Ctx) -> Bool {
  if wide.editing {
    wide.editing = false
  } else if switcher_escape(c) {
    ()
  } else if wide.keys_open {
    wide.keys_open = false
  } else if wide.menu is Some(_) || wide.filter_open || wide.attention_open {
    wide.menu = None
    wide.filter_open = false
    wide.attention_open = false
  } else if wide.renaming != "" {
    wide.renaming = ""
    c.blur()
  } else {
    return false
  }
  true
}

///|
/// The chat before (-1) or after (1) the one open, in the list as it shows (Sidebar.tsx goToNeighbour); the first when
/// none is open.
pub fn neighbour(src : Source, w : Workspace, way : Int) -> Unit {
  let rows : Array[ChatItem] = []
  match chats_of(src, w.id, filter_of(src, w.id)) {
    (Some(v), _) =>
      for d in v.days {
        for item in d.items {
          rows.push(item)
        }
      }
    _ => ()
  }
  if rows.length() == 0 {
    return
  }
  let at = match app.nav.top() {
    Chat(r) =>
      rows.search_by(fn(i) { i.station == r.station && (i.session == r.session || i.id == r.session) })
    _ => None
  }
  let next = match at {
    Some(i) => i + way
    None => if way > 0 { 0 } else { rows.length() - 1 }
  }
  if next < 0 || next >= rows.length() {
    return
  }
  open_row(rows[next])
}

///|
/// An action's keys as the core's prefs keep them (settings' keymap), "" none: what a tip says after its words.
pub fn tip_keys(src : Source) -> (String) -> String {
  fn(action) { @settings.keys_text((src.topic)("prefs", {}).value, action) }
}
