// The wide frame's keys and what the pointer's other button opens (ember web/src/keymap.ts, Switcher.tsx,
// Shortcuts.tsx, Sidebar.tsx's ContextMenu, Rename.tsx): ⌘K's switcher, ⌘N, ⌥↑ / ⌥↓, ⌘\\, ⌘,, ⌘/, Esc, Space; a
// chat's row's menu from its right click and its title renamed in place.

///|
/// The web app's shortcuts, at a desktop's width: ⌘K the switcher, ⌘N a new chat, ⌥↑ / ⌥↓ the chat before or after,
/// ⌘\ the sidebar folded or opened, ⌘, settings, ⌘/ the shortcuts, Esc what is open closed.
fn wide_keys(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  // (as kept on this device: settings' 快捷键, keymap.mbt)
  let prefs = (src.topic)("prefs", {}).value
  let pressed = fn(action : String) { @settings.action_pressed(c, prefs, action) }
  if pressed("chat.switch") {
    @sfdesk.switcher_toggle(c)
    wide.menu = None
    wide.attention_open = false
  }
  if pressed("chat.new") {
    new_chat_wide()
  }
  if pressed("sidebar.toggle") {
    wide.folded = !wide.folded
  }
  if pressed("settings") {
    open_settings()
  }
  if pressed("shortcuts") {
    wide.keys_open = !wide.keys_open
  }
  if @settings.action_pressed(c, prefs, "chat.prev", in_field=true) {
    neighbour(src, w, -1)
  }
  if @settings.action_pressed(c, prefs, "chat.next", in_field=true) {
    neighbour(src, w, 1)
  }
  if pressed("chat.jobs") && app.nav.top() is Chat(_) {
    wide.jobs_open = !wide.jobs_open
  }
  if c.key_pressed(@ui.key_escape) || c.key_pressed(@ui.key_escape, in_field=true) {
    if rail_ws.editing {
      rail_ws.editing = false
    } else if @sfdesk.switcher_escape(c) {
      // ⌘K's: one kind's list back to all of them, else closed
      ()
    } else if wide.find_chat != "" {
      find_forget()
      c.blur()
    } else if wide.keys_open {
      wide.keys_open = false
    } else if wide.menu is Some(_) || wide.filter_open || wide.attention_open {
      wide.menu = None
      wide.filter_open = false
      wide.attention_open = false
    } else if wide.renaming != "" {
      wide.renaming = ""
      c.blur()
    } else if pk.ts != "" {
      pick_clear()
    } else {
      // the chat's side panel closed, all its tabs (keymap.ts panel.close)
      match app.nav.top() {
        Chat(r) if side_now(r).0.length() > 0 => side_change(r, "clear", None)
        _ => ()
      }
    }
  }
  // ↑ / ↓ with the cursor in an empty composer: the chat above or below, as the list shows them now (Chat.tsx
  // useComposerText goToNeighbour)
  match app.nav.top() {
    Chat(r) if c.editor_focused(field_key) && !@sfdesk.switcher_open() =>
      match drafts.get(draft_key(r)) {
        Some(d) if d.text == "" => {
          if c.key_pressed(@ui.key_code_up, in_field=true) {
            neighbour(src, w, -1)
          } else if c.key_pressed(@ui.key_code_down, in_field=true) {
            neighbour(src, w, 1)
          }
        }
        _ => ()
      }
    _ => ()
  }
  // Space with no field focused: back to the composer (回到输入框)
  if !c.field_focused() && pressed("composer.focus") && !@sfdesk.switcher_open() {
    if app.nav.top() is Chat(_) {
      focus_composer.val = true
    }
  }
}

///|
/// The chat before (-1) or after (1) the one open, in the list as it shows (Sidebar.tsx goToNeighbour); the first when
/// none is open. On the 奏 page, the decision before or after the one it shows.
fn neighbour(src : Source, w : Workspace, way : Int) -> Unit {
  // on the 奏 page: its list's (DecisionDesk.tsx DecisionRows)
  if app.nav.top() is Decisions {
    decision_step(src, w, way)
    return
  }
  let filter = filter_of(src, w.id)
  let rows : Array[ChatItem] = []
  match chats_of(src, w.id, filter) {
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
/// The composer to take the keyboard at the chat page's next drawing (Space with no field focused: 回到输入框).
let focus_composer : Ref[Bool] = Ref(false)

///|
/// A chat's row's menu (Sidebar.tsx ContextMenu): 固定 / 取消固定, 重命名, 保留 / 取消保留, 复制会话链接, 复制 session 文件
/// 路径, 归档; at where
/// the row was right clicked (mbui's dropdown menu there).
fn row_menu(c : @ui.Ctx, src : Source) -> Unit {
  let (key, item, x, y) = match wide.menu {
    Some(m) => m
    // (closed: told so, for its going)
    None => {
      @sf.menu(c, "row-menu", false, 0, [], {}, @sf.menu_w) |> ignore
      return
    }
  }
  let entries : Array[@kit.Entry] = []
  match item.pinned {
    Some(p) => entries.push(@kit.menu_item("pin", label=tr(if p { "web-main.chat.unpin" } else { "web-main.chat.pin" })))
    None => ()
  }
  entries.push(@kit.menu_item("rename", label=tr("web-main.chat.rename")))
  match item.thread {
    Some(_) =>
      entries.push(@kit.menu_item("keep", label=tr(if item.kept { "web-main.chat.unkeep" } else { "web-main.chat.keep" })))
    None => ()
  }
  let link = chat_link(item.station, item.session)
  if link != "" {
    entries.push(@kit.menu_item("link", label=tr("web-main.chat.copyLink")))
  }
  // relayed to a channel (docs/relay.md): a chat with an agent to go on there
  match item.thread {
    Some(_) if item.agents.length() > 0 => entries.push(@kit.menu_item("relay", label=tr("web-main.relay.action")))
    _ => ()
  }
  entries.push(@kit.menu_item("transcript", label=tr("web-main.chat.copyTranscript")))
  entries.push(@kit.menu_item("archive", label=tr("web-main.chat.archive")))
  let icons = {
    "pin": "pin",
    "rename": "edit",
    "keep": "shield-check",
    "link": "copy",
    "relay": "arrow-up-right",
    "transcript": "file",
    "archive": "archive",
  }
  // (its top left at the pointer, as the web's context menu opens)
  let m = @sf.menu(c, "row-menu", true, 0, entries, icons, @sf.menu_w, offset=0.0, at=(x, y, 0.0, 0.0))
  if !m.open {
    wide.menu = None
  }
  match m.chosen {
    Some("pin") =>
      match item.pinned {
        Some(p) =>
          act(
            src,
            tr(if p { "android-chat.unpin.verb" } else { "android-chat.pin.verb" }),
            "pin/" + item.station + "/" + item.session,
            "chat.pin",
            {
              "station": Json::string(item.station),
              "session": Json::string(item.session),
              "pinned": Json::boolean(!p),
            },
          )
        None => ()
      }
    Some("rename") => wide.renaming = key
    Some("keep") =>
      match item.thread {
        Some(th) =>
          act(
            src,
            tr(if item.kept { "web-main.chat.unkeep.what" } else { "web-main.chat.keep.what" }),
            "keep/" + item.station + "/" + th.to_int64().to_string(),
            "chat.keep",
            {
              "station": Json::string(item.station),
              "thread": Json::number(th),
              "kept": Json::boolean(!item.kept),
            },
            done=tr(if item.kept { "web-main.chat.unkeep.done" } else { "web-main.chat.keep.done" }),
          )
        None => ()
      }
    Some("link") => copy_chat_link(c, item.title, link)
    Some("relay") =>
      match item.thread {
        Some(th) =>
          open_relay(
            c,
            src,
            { station: item.station, session: item.session, title: item.title, station_name: item.station_name },
            th,
          )
        None => ()
      }
    Some("transcript") =>
      copy_transcripts(c, src, item.station, match item.agents.map(fn(a) { a.key }).filter(fn(k) { k != "" }) {
        [] => [item.session]
        keys => keys
      })
    Some("archive") => archive_row(c, src, item)
    _ => ()
  }
}


///|
/// Where a chat's agents' sessions are kept on their station's machine (ChatRef.tsx useCopyTranscripts:
/// `session.transcript` each), copied one a line; said if none is written yet.
fn copy_transcripts(c : @ui.Ctx, src : Source, station : String, keys : Array[String]) -> Unit {
  let paths : Array[String?] = keys.map(fn(_) { None })
  let mut left = keys.length()
  let mut failed : String? = None
  let done = fn() {
    match failed {
      Some(e) => say(c, fill("web-main.chat.copyFailed", [("error", e)]))
      None => {
        let found = paths.filter_map(fn(p) { p })
        if found.length() == 0 {
          say(c, tr("web-main.chat.transcriptNone"))
        } else {
          c.copy_text(found.join("\n"))
          say(c, if found.length() > 1 {
            fill("web-main.chat.transcriptsCopied", [("n", found.length().to_string())])
          } else {
            tr("web-main.chat.transcriptCopied")
          })
        }
      }
    }
  }
  for i, key in keys {
    (src.call)("session.transcript", { "station": Json::string(station), "key": Json::string(key) }, fn(r) {
      match r {
        Ok(v) =>
          match text(Some(v), "path") {
            "" => ()
            p => paths[i] = Some(p)
          }
        Err(e) => failed = Some(text(Some(e), "message"))
      }
      left = left - 1
      if left == 0 {
        done()
      }
    })
  }
}

///|
/// A row's title being renamed in place (its field shows it).
let side_rename_field : @ui.Field = @ui.Field::new()

///|
/// ⌘/ (Shortcuts.tsx ShortcutsDialog): every shortcut, by where it works (the core's keymap, then those of one place,
/// not changed here), quiet words beside each; the way to change them at its foot (the desktop app's).
fn keys_dialog(c : @ui.Ctx, src : Source) -> Unit {
  let prefs = (src.topic)("prefs", {}).value
  let (first_ws, last_ws) = @settings.workspace_keys(prefs)
  let groups = @settings.key_groups(prefs)
  groups.push((tr("web-main.shortcuts.group.workspace"), [(tr("web-main.shortcuts.switchWorkspace"), first_ws + " … " + last_ws)]))
  groups.push(
    (
      tr("web-main.shortcuts.group.composer"),
      [
        (tr("web-main.shortcuts.send"), "↩"),
        (tr("web-main.shortcuts.newline"), "⇧↩"),
        (tr("web-main.shortcuts.prevNextChat"), "↑ / ↓"),
      ],
    ),
  )
  groups.push(
    (
      tr("web-main.shortcuts.group.preview"),
      [
        (tr("web-main.shortcuts.prevNextImage"), "← / →"),
        (tr("web-main.shortcuts.zoom"), "+ / -"),
        (tr("web-main.shortcuts.fitActual"), "0 / 1"),
        (tr("common.close"), "Esc"),
      ],
    ),
  )
  let change = Ref(false)
  let footer : (() -> Unit)? = if @settings.keys_changeable(prefs) {
    Some(fn() {
      if @sf.button(c, tr("web-main.shortcuts.change"), key="keys-dialog/change", tone=Ghost) {
        change.val = true
      }
    })
  } else {
    None
  }
  let d = @sf.dialog(
    c,
    "keys-dialog",
    wide.keys_open,
    tr("web-main.shortcuts.title"),
    close_label=tr("common.close"),
    footer?,
    fn() {
      c.box(style=keys_sheet, fn() {
        for g in groups {
          c.box(style=keys_group, fn() {
            c.box(style=keys_group_head, fn() { c.text(g.0, style=keys_group_title) |> ignore }) |> ignore
            for k in g.1 {
              c.box(style=keys_line, fn() {
                c.text(k.0, style=keys_line_words) |> ignore
                c.text(k.1, style=keys_line_keys) |> ignore
              })
              |> ignore
            }
          })
          |> ignore
        }
      })
      |> ignore
    },
  )
  wide.keys_open = d && !change.val
  if change.val {
    open_settings_at(@settings.Route::Shortcuts)
  }
}

///|
/// (Shortcuts.css.ts sheet: the groups 18 apart; group: its lines 2 apart, its title 4 over them)
// kept across runs: a value (no field of it changes)
let keys_sheet : @ui.Style = @ui.style(w=Full, gap=S4_5)

///|
// kept across runs: a value (no field of it changes)
let keys_group : @ui.Style = @ui.style(w=Full, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let keys_group_head : @ui.Style = @ui.style(w=Full, pb=S1)

///|
/// (groupTitle: 12, 500, muted)
// kept across runs: a value (no field of it changes)
let keys_group_title : @ui.TextStyle = @ui.text_style(size=Xs, leading=L4_75, weight=Medium, color=Muted, wrap=false)

///|
/// (line: what it does and its keys at the two ends, 16 apart, 4 over and under, the list's words)
// kept across runs: a value (no field of it changes)
let keys_line : @ui.Style = @ui.style(row=true, w=Full, py=S1, gap=S4, align=AEnd, justify=JBetween)

///|
// kept across runs: a value (no field of it changes)
let keys_line_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L5, color=Fg, wrap=false)

///|
/// (keys: muted, their digits as wide as each other)
// kept across runs: a value (no field of it changes)
let keys_line_keys : @ui.TextStyle = @ui.text_style(size=Sm, leading=L5, color=Muted, wrap=false)

///|
/// A row's title as a field (Rename.tsx TitleInput, from its menu's 重命名): Enter saves it (`chat.rename`), Esc or
/// leaving it lets it be.
fn side_rename(c : @ui.Ctx, src : Source, item : ChatItem) -> Unit {
  let t = @sf.theme()
  let key = "side/rename"
  if rename_for.val != item.station + "/" + item.id {
    rename_for.val = item.station + "/" + item.id
    side_rename_field.set(item.title)
    c.focus_editor(key)
  }
  c.box(w=Fill(1.0), fn() {
    let res = c.editor(
      key,
      font_size=13.0,
      line=20.0,
      max_lines=1,
      plain=true,
      color=t.p.text,
      caret_color=t.p.accent,
      enter_sends=true,
      field=side_rename_field,
    )
    match res.submitted {
      Some(title) => {
        wide.renaming = ""
        rename_for.val = ""
        c.blur()
        let words = title.trim(chars=" \n\t").to_string()
        if words != "" && words != item.title {
          let p : Map[String, Json] = {
            "station": Json::string(item.station),
            "session": Json::string(item.session),
            "title": Json::string(words),
          }
          match item.thread {
            Some(th) => p["thread"] = Json::number(th)
            None => ()
          }
          act(src, tr("android-chat.rename.verb"), "", "chat.rename", Json::object(p))
        }
      }
      None => if !res.focused && rename_for.val != "" && rename_seen.val { wide.renaming = "" }
    }
    rename_seen.val = res.focused
  })
  |> ignore
}

///|
/// The row whose title the field holds; whether the field had the keyboard last frame (it losing it ends the rename).
let rename_for : Ref[String] = Ref("")

///|
let rename_seen : Ref[Bool] = Ref(false)


///|
/// What ⌘K offers of what the frame can do now (Switcher.tsx offered: the keys' actions it answers, and its own): the
/// open chat's (find, its services), the app's (a new chat, the sidebar, settings, the shortcuts), settings' pages (only
/// found by typing). The core names the keys' actions and finds what was typed among them (sfdesk/switcher.mbt).
fn switcher_offered(c : @ui.Ctx, src : Source) -> Array[@sfdesk.Offered] {
  // an action's first keys as shown (as kept on this device: settings' 快捷键)
  let prefs = (src.topic)("prefs", {}).value
  let keys = fn(action : String) { @settings.key_label(prefs, action) }
  let all : Array[@sfdesk.Offered] = []
  match app.nav.top() {
    Chat(r) => {
      all.push({
        id: "chat.find",
        group: "",
        label: "",
        words: "",
        icon: "search",
        keys: keys("chat.find"),
        typed: false,
        run: fn() { find_open(c, r) },
      })
      all.push({
        id: "chat.jobs",
        group: "",
        label: "",
        words: "",
        icon: "web",
        keys: keys("chat.jobs"),
        typed: false,
        run: fn() { wide.jobs_open = true },
      })
    }
    _ => ()
  }
  all.push({
    id: "chat.new",
    group: "",
    label: "",
    words: "",
    icon: "compose",
    keys: keys("chat.new"),
    typed: false,
    run: new_chat_wide,
  })
  all.push({
    id: "sidebar.toggle",
    group: "",
    label: "",
    words: "",
    icon: "panel-open",
    keys: keys("sidebar.toggle"),
    typed: false,
    run: fn() { wide.folded = !wide.folded },
  })
  all.push({
    id: "settings",
    group: "",
    label: "",
    words: "",
    icon: "settings",
    keys: keys("settings"),
    typed: false,
    run: open_settings,
  })
  all.push({
    id: "shortcuts",
    group: "",
    label: "",
    words: "",
    icon: "command",
    keys: keys("shortcuts"),
    typed: false,
    run: fn() { wide.keys_open = true },
  })
  let pages : Array[(String, @settings.Route, String)] = [
    ("appearance", @settings.Route::Appearance, tr("web-pages.settings.nav.appearance")),
    ("notifications", @settings.Route::Notifications, tr("web-pages.settings.nav.notifications")),
    ("permissions", @settings.Route::Permissions, tr("web-pages.settings.nav.permissions")),
    ("archive", @settings.Route::Archiving, tr("web-pages.archiving.title")),
    ("memory", @settings.Route::Memories, tr("web-pages.settings.nav.memory")),
    ("security", @settings.Route::Security, tr("web-pages.security.title")),
    ("vault", @settings.Route::Vault, tr("web-pages.vault.title")),
    ("changelog", @settings.Route::Changelog, tr("web-pages.settings.nav.changelog")),
    ("about", @settings.Route::About, tr("web-pages.settings.nav.about")),
  ]
  for p in pages {
    let (key, route, label) = p
    all.push({
      id: "settings." + key,
      group: "settings",
      label,
      words: "",
      icon: "settings",
      keys: "",
      typed: true,
      run: fn() {
        open_settings()
        app.nav.replace(Setting(route))
      },
    })
  }
  all
}
