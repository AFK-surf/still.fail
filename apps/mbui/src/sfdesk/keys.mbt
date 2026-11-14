// The frame's keys (still.fail web/src/keymap.ts useShortcut, Switcher.tsx GlobalShortcuts, Sidebar.tsx goToNeighbour,
// brand.tsx's sidebar.toggle): ⌘K the switcher, ⌘N a new chat, ⌥↑ / ⌥↓ the chat before or after, ⌃1 … ⌃9 a workspace,
// ⌘\ the sidebar, ⌘, settings, ⌘/ the shortcuts, ⌘[ / ⌘] back and forward, Esc what the frame opened closed: actions
// of the shell's node, the keys as the core's prefs keep them on this device (settings' 快捷键: prefs.keymap, the
// window's keymap). What none of them takes the page in the pane answers itself.

///|
/// The app's keys as actions of node `v` (the shell's, in every tier: mbui's view keymap.mbt), each done at its key's
/// moment (or its menu's item's: @settings.ask_action), the keys as the window's keymap has them (@settings.keymap_of).
/// What is the wide frame's alone (the sidebar folded, the chat before or after in the list beside, a workspace by its
/// place, the chat's side panel's Esc) passes the key on laid out Small; what opens something opens it where the shell
/// has it. Esc goes to what the frame opened over the page, the one on top first, then to the open chat's; what took
/// none of it passes it on to the page.
pub fn frame_actions(v : @view.View, src : Source) -> Unit {
  let framed = fn() { !(@sf.layout(v.window().0) is Small) || @sf.native_able() }
  let blur = fn() { v.focus_let_go() }
  let act = fn(action : String, f : (Workspace) -> Bool) {
    v.on_action(action, fn(_) {
      match @sfbase.workspace_in_view(src).0 {
        Some(w) => f(w)
        None => false
      }
    })
    |> ignore
  }
  // ⌘K: laid out Medium or Large its panel over the page (switcher.mbt); Small, the search's page in the lists' box,
  // over the page open when it is not the lists (sfpages' search.mbt), what the panel offers in it
  act("chat.switch", fn(w) {
    if framed() {
      switcher_toggle(blur)
      attention_set(false)
    } else {
      @sfpages.search_summon(fn(c) { switcher_offered(c, src, w) }, app.nav.top() != Home)
    }
    true
  })
  act("chat.new", fn(_) {
    new_chat()
    true
  })
  act("sidebar.toggle", fn(_) {
    guard framed() else { return false }
    sidebar_toggle()
    true
  })
  act("settings", fn(_) {
    open_settings()
    true
  })
  act("shortcuts", fn(_) {
    wide.keys_open.set(!wide.keys_open.untracked())
    true
  })
  // ⌘[ / ⌘] back and forward (history.forward): back as the system's back is, whose it is deciding (@ui.go_back; the
  // hosts' own Alt+← and a mouse's back button come so); forward what back took off put back (sfbase's app history:
  // go_forward), also from a mouse's forward button and Alt+→ (the hosts' key_forward: the keymap's nav.forward)
  act("nav.back", fn(_) {
    @ui.go_back() |> ignore
    true
  })
  act("nav.forward", fn(_) {
    @sfbase.go_forward(src) |> ignore
    true
  })
  // ⌥↑ / ⌥↓ the chat before or after, in the list beside
  for way in [-1, 1] {
    act(if way < 0 { "chat.prev" } else { "chat.next" }, fn(w) {
      guard framed() else { return false }
      neighbour(src, w, way)
      true
    })
  }
  // ⌃1 … ⌃9 on a Mac (Alt elsewhere): the workspace at that place at the rail's foot, as the web's keys (keymap.ts
  // workspaceIndexOf), where the rail shows them
  for k in 0..<9 {
    act("workspace.\{k + 1}", fn(w) {
      guard framed() && !@sf.native_on() else { return false }
      let all = @sfbase.workspace_in_view(src).1
      guard k < all.length() else { return false }
      let to = all[k].id
      if to != w.id {
        @sfpages.switch_workspace(src, to)
      }
      true
    })
  }
  // Esc: what the frame opened first, then in the open chat (chat_layers.mbt)
  act("frame.escape", fn(_) { frame_escape(blur) || (framed() && chat_escape(src, blur)) })
}

///|
/// Esc to what the frame opened, the one on top first: the rail changed, ⌘K (one kind's list back to all of them,
/// else closed), ⌘/, 待处理's panel, a row's title renamed (what is presented over the frame has Escape before it:
/// overlay.mbt); the keyboard let go (`blur`) where what had it closes. Whether it took it.
fn frame_escape(blur : () -> Unit) -> Bool {
  let open = fn(s : @signals.Signal[Bool]) { s.untracked() }
  if open(wide.editing) {
    wide.editing.set(false)
  } else if switcher_escape(blur) {
    ()
  } else if open(wide.keys_open) {
    wide.keys_open.set(false)
  } else if open(wide.attention_open) {
    attention_set(false)
  } else if @sfpages.rename_escape(blur) {
    ()
  } else {
    return false
  }
  true
}

///|
/// The chat before (-1) or after (1) the one open, in the list as it shows. A list can
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
  fn(action) { @settings.keys_text(src.topic("prefs", {}).get().value, action) }
}
