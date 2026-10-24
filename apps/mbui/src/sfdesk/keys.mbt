// The frame's keys (ember web/src/keymap.ts useShortcut, Switcher.tsx GlobalShortcuts, Sidebar.tsx goToNeighbour,
// brand.tsx's sidebar.toggle): ⌘K the switcher, ⌘N a new chat, ⌥↑ / ⌥↓ the chat before or after, ⌘\ the sidebar, ⌘,
// settings, ⌘/ the shortcuts, Esc what the frame opened closed; the keys as the core's prefs keep them on this device
// (settings' 快捷键: prefs.keymap). The page in the pane answers its own after them (Pages.keys).

///|
/// The frame's keys, read as its frame is built (before the page's: Esc goes to what the frame opened over it first).
pub fn keys(c : @ui.Ctx, src : Source, w : Workspace, pages : Pages) -> Unit {
  let prefs = (src.topic)("prefs", {}).value
  let pressed = fn(action : String) { @settings.action_pressed(c, prefs, action) }
  if pressed("chat.switch") {
    switcher_toggle(c)
    wide.menu = None
    wide.attention_open = false
  }
  if pressed("chat.new") {
    new_chat(pages)
  }
  if pressed("sidebar.toggle") {
    wide.folded = !wide.folded
  }
  if pressed("settings") {
    open_settings(pages)
  }
  if pressed("shortcuts") {
    wide.keys_open = !wide.keys_open
  }
  // (奏's page steps its own decisions: DecisionDesk.tsx)
  if app.nav.top() != Decisions {
    if @settings.action_pressed(c, prefs, "chat.prev", in_field=true) {
      neighbour(src, w, pages, -1)
    }
    if @settings.action_pressed(c, prefs, "chat.next", in_field=true) {
      neighbour(src, w, pages, 1)
    }
  }
  let escape = c.key_pressed(@ui.key_escape) || c.key_pressed(@ui.key_escape, in_field=true)
  let left = escape && !frame_escape(c)
  // Esc in the open chat (chat_layers.mbt), then the page's
  let took = chat_escape(c, src, left)
  (pages.keys)(c, src, w, left && !took)
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
pub fn neighbour(src : Source, w : Workspace, pages : Pages, way : Int) -> Unit {
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
  open_row(pages, rows[next])
}

///|
/// An action's keys as the core's prefs keep them (settings' keymap), "" none: what a tip says after its words.
pub fn tip_keys(src : Source) -> (String) -> String {
  fn(action) { @settings.keys_text((src.topic)("prefs", {}).value, action) }
}
