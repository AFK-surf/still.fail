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
      attention_set(false)
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
    wide.keys_open.set(!wide.keys_open.get())
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
  let way = if @settings.action_pressed(c, prefs, "chat.prev", in_field=true) {
    -1
  } else if @settings.action_pressed(c, prefs, "chat.next", in_field=true) {
    1
  } else {
    0
  }
  if way != 0 && framed {
    // A menu action remains asked through the frame's builds. Opening a chat can cause another build, so doing this
    // here would handle the same action again and skip rows. Tell it once after the builds, as for an input.
    c.tell("chat/neighbour", fn() { neighbour(src, w, way) })
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
  if wide.editing.get() {
    wide.editing.set(false)
  } else if switcher_escape(c) {
    ()
  } else if wide.keys_open.get() {
    wide.keys_open.set(false)
  } else if wide.attention_open.get() {
    attention_set(false)
  } else if @sfpages.rename_escape(c) {
    ()
  } else {
    return false
  }
  true
}

///|
/// The chat before (-1) or after (1) the one open, in the list as it shows (Sidebar.tsx goToNeighbour). A list can
/// hold its rows in place while its core view changes, so use the order last drawn, not the core's current order.
pub fn neighbour(src : Source, w : Workspace, way : Int) -> Unit {
  let open = match app.nav.top() {
    Chat(r) => r
    _ => return
  }
  if side_place() == "archive" {
    let rows : Array[Json] = []
    for day in items(archive_side.last, "days") {
      rows.append(items(Some(day), "items"))
    }
    let at = rows.search_by(fn(item) {
      let row = Some(item)
      text(row, "station") == open.station &&
      (text(row, "session") == open.session || text(row, "id") == open.session)
    })
    match at {
      Some(i) if i + way >= 0 && i + way < rows.length() => archive_open(rows[i + way])
      _ => ()
    }
    return
  }
  if side_place() != "chats" {
    return
  }
  let rows : Array[ChatItem] = []
  let key = "chats/" + w.id + "/" + filter_of(src, w.id)
  for d in shown_days.get(key).unwrap_or([]) {
    rows.append(d.items)
  }
  match rows.search_by(fn(item) { @sfbase.row_is(item, open) }) {
    Some(i) if i + way >= 0 && i + way < rows.length() => {
      let item = rows[i + way]
      open_page(Chat({ station: item.station, session: item.session, title: item.title, station_name: item.station_name }))
    }
    _ => ()
  }
}

///|
/// An action's keys as the core's prefs keep them (settings' keymap), "" none: what a tip says after its words.
pub fn tip_keys(src : Source) -> (String) -> String {
  fn(action) { @settings.keys_text((src.topic)("prefs", {}).value, action) }
}

///|
/// The app's keys in node `v` of the window's tree (what holds the signed-in shells' nodes), each done at its moment as
/// `keys` does them as a frame builds, while `ws` has a workspace: the keymap's (⌘K, a new chat, the sidebar, the
/// settings, the shortcuts, back and forward, the chat before or after) as the tree asks them and as the Mac's menu bar
/// chooses them (@settings.actions_node); a mouse's forward button and Esc to what the frame opened, which are no action
/// of the keymap's, by `outer`, which holds `v`. What has the focus asks them on its way out, a field's too (Tree::key_at:
/// what holds it). The shell's islands do them no more (sfapp's signed_in_frame).
pub fn keys_node(v : @view.View, outer : @view.View, src : Source, ws : () -> Workspace?) -> Unit {
  let act = fn(action : String) -> () -> Bool {
    fn() {
      match ws() {
        Some(w) => action_done(src, w, action)
        None => false
      }
    }
  }
  @settings.actions_node(
    v,
    fn() { (src.topic)("prefs", {}).value },
    [
      ("chat.switch", act("chat.switch")),
      ("chat.new", act("chat.new")),
      ("sidebar.toggle", act("sidebar.toggle")),
      ("settings", act("settings")),
      ("shortcuts", act("shortcuts")),
      ("nav.back", act("nav.back")),
      ("nav.forward", act("nav.forward")),
      ("chat.prev", act("chat.prev")),
      ("chat.next", act("chat.next")),
      ("composer.focus", act("composer.focus")),
    ],
  )
  // (the chat before or after goes on in a field: its caret moved by the key as well, as `keys` read them in_field)
  v.reacts(
    fn() {
      let prefs = (src.topic)("prefs", {}).value
      @settings.action_keys(prefs, "chat.prev") + @settings.action_keys(prefs, "chat.next")
    },
    fn(keys) { v.keys_in_fields(keys) |> ignore },
  )
  outer.on_key(fn(key) {
    if ws() is None {
      return false
    }
    // (a mouse's forward button, the hosts' Alt+→)
    if key.code == @ui.key_forward {
      return act("nav.forward")()
    }
    if key.code == @ui.key_escape && key.mods == 0 {
      let c = @ui.current()
      let left = !frame_escape(c)
      // Esc in the open chat (chat_layers.mbt)
      return !left || (is_wide(c) && chat_escape(c, src, left))
    }
    false
  })
  |> ignore
}

///|
/// What the app's key for `action` does (keys_node's, as `keys` does it): whether it did anything.
fn action_done(src : Source, w : Workspace, action : String) -> Bool {
  let c = @ui.current()
  let framed = is_wide(c)
  match action {
    "chat.switch" => {
      if framed {
        switcher_toggle(c)
        attention_set(false)
      } else {
        @sfpages.search_summon(c, switcher_offered(c, src, w), app.nav.top() != Home)
      }
      true
    }
    "chat.new" => {
      new_chat()
      true
    }
    "composer.focus" =>
      if app.nav.top() is NewChat && !switcher_open() {
        @sfpages.new_chat_focus(src, w)
      } else {
        false
      }
    "sidebar.toggle" =>
      if framed {
        sidebar_toggle()
        true
      } else {
        false
      }
    "settings" => {
      open_settings()
      true
    }
    "shortcuts" => {
      wide.keys_open.set(!wide.keys_open.get())
      true
    }
    "nav.back" => {
      c.back() |> ignore
      true
    }
    "nav.forward" => {
      @sfbase.go_forward(src) |> ignore
      true
    }
    "chat.prev" | "chat.next" =>
      if framed {
        neighbour(src, w, if action == "chat.prev" { -1 } else { 1 })
        true
      } else {
        false
      }
    _ => false
  }
}
