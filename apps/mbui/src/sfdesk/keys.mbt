// The frame's keys (ember web/src/keymap.ts useShortcut, Switcher.tsx GlobalShortcuts, Sidebar.tsx goToNeighbour,
// brand.tsx's sidebar.toggle): ⌘K the switcher, ⌘N a new chat, ⌥↑ / ⌥↓ the chat before or after, ⌘\ the sidebar, ⌘,
// settings, ⌘/ the shortcuts, ⌘[ / ⌘] back and forward, Esc what the frame opened closed; the keys as the core's prefs
// keep them on this device (settings' 快捷键: prefs.keymap). The page in the pane answers its own after them.

///|
/// The app's keys, read as its frame is built in every tier (before the page's: Esc goes to what the frame opened over
/// it first). What is the wide frame's alone (the sidebar folded, the chat before or after in the list beside, the
/// chat's side panel's Esc) does nothing laid out Small; what opens something opens it where the shell has it.
pub fn keys(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let framed = is_wide(c)
  let prefs = (src.topic)("prefs", {}).value
  let pressed = fn(action : String) { @settings.action_pressed(c, prefs, action) }
  // ⌘K: laid out Medium or Large its panel over the page (switcher.mbt); Small, the search's page in the lists' box,
  // over the page open when it is not the lists (sfpages' search.mbt), what the panel offers in it
  if pressed("chat.switch") {
    if framed {
      switcher_toggle(c)
      wide.attention_open = false
    } else {
      @sfpages.search_summon(c, switcher_offered(c, src, w), app.nav.top() != Home)
    }
  }
  if pressed("chat.new") {
    new_chat()
  }
  if pressed("sidebar.toggle") && framed {
    sidebar_toggle()
  }
  if pressed("settings") {
    open_settings()
  }
  if pressed("shortcuts") {
    wide.keys_open = !wide.keys_open
  }
  // ⌘[ / ⌘] back and forward (Switcher.tsx history.back, history.forward): back as the system's back is, whose it is
  // deciding (Ctx::back; the hosts' own Alt+← and a mouse's back button come so); forward what back took off put back
  // (sfbase's app history: go_forward), also from a mouse's forward button and Alt+→ (the hosts' key_forward)
  if pressed("nav.back") {
    c.back() |> ignore
  }
  if pressed("nav.forward") || c.key_pressed(@ui.key_forward) {
    @sfbase.go_forward(src) |> ignore
  }
  // (奏's page steps its own decisions: DecisionDesk.tsx step, the one before or after the one it shows)
  let way = if @settings.action_pressed(c, prefs, "chat.prev", in_field=true) {
    -1
  } else if @settings.action_pressed(c, prefs, "chat.next", in_field=true) {
    1
  } else {
    0
  }
  if way != 0 && framed {
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
  if framed {
    chat_escape(c, src, left) |> ignore
  }
}

///|
/// Esc to what the frame opened, the one on top first: the rail changed, ⌘K (one kind's list back to all of them,
/// else closed), ⌘/, 待处理's panel, a row's title renamed (what is presented over the frame has Escape before it: overlay.mbt). Whether it took it.
fn frame_escape(c : @ui.Ctx) -> Bool {
  if wide.editing {
    wide.editing = false
  } else if switcher_escape(c) {
    ()
  } else if wide.keys_open {
    wide.keys_open = false
  } else if wide.attention_open {
    wide.attention_open = false
  } else if @sfpages.rename_escape(c) {
    ()
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
  let item = rows[next]
  open_page(Chat({ station: item.station, session: item.session, title: item.title, station_name: item.station_name }))
}

///|
/// An action's keys as the core's prefs keep them (settings' keymap), "" none: what a tip says after its words.
pub fn tip_keys(src : Source) -> (String) -> String {
  fn(action) { @settings.keys_text((src.topic)("prefs", {}).value, action) }
}
