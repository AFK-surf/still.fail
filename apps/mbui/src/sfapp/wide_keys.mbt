// The wide frame's keys and what the pointer's other button opens (ember web/src/keymap.ts, Switcher.tsx,
// Shortcuts.tsx, Sidebar.tsx's ContextMenu, Rename.tsx): ⌘K's switcher, ⌘N, ⌥↑ / ⌥↓, ⌘\\, ⌘,, ⌘/, Esc, Space; a
// chat's row's menu from its right click and its title renamed in place.

///|
/// The web app's shortcuts, at a desktop's width: ⌘K the switcher, ⌘N a new chat, ⌥↑ / ⌥↓ the chat before or after,
/// ⌘\ the sidebar folded or opened, ⌘, settings, ⌘/ the shortcuts, Esc what is open closed.
fn wide_keys(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  if c.shortcut('k') {
    if wide.switcher {
      c.blur()
    }
    wide.switcher = !wide.switcher
    wide.chosen = 0
    switcher_query.val = ""
    switcher_field.set("")
    wide.menu = None
    wide.attention_open = false
  }
  if c.shortcut('n') {
    new_chat_wide()
  }
  if c.shortcut('\\') {
    wide.folded = !wide.folded
  }
  if c.shortcut(',') {
    open_settings()
  }
  if c.shortcut('/') {
    wide.keys_open = !wide.keys_open
  }
  let alt = @ui.mod_alt
  if c.key_pressed(@ui.key_code_up, mods=alt) || c.key_pressed(@ui.key_code_up, mods=alt, in_field=true) {
    neighbour(src, w, -1)
  }
  if c.key_pressed(@ui.key_code_down, mods=alt) || c.key_pressed(@ui.key_code_down, mods=alt, in_field=true) {
    neighbour(src, w, 1)
  }
  if c.key_pressed(@ui.key_escape) || c.key_pressed(@ui.key_escape, in_field=true) {
    if wide.switcher {
      // (its field let go: the keyboard goes nowhere until another is pressed)
      wide.switcher = false
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
    }
  }
  // Space with no field focused: back to the composer (回到输入框)
  if !c.field_focused() && c.key_pressed(@ui.key_of_char(' ')) && !wide.switcher {
    if app.nav.top() is Chat(_) {
      focus_composer.val = true
    }
  }
}

///|
/// The chat before (-1) or after (1) the one open, in the list as it shows (Sidebar.tsx goToNeighbour); the first when
/// none is open.
fn neighbour(src : Source, w : Workspace, way : Int) -> Unit {
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
/// A chat's row's menu (Sidebar.tsx ContextMenu): 固定 / 取消固定, 重命名, 保留 / 取消保留, 复制会话链接, 归档.
fn row_menu(c : @ui.Ctx, src : Source) -> Unit {
  guard wide.menu is Some((key, item, x, y)) else { return }
  let close = fn() { wide.menu = None }
  popover(c, "row-menu", x, y, 200.0, 220.0, close, fn() {
    match item.pinned {
      Some(p) =>
        if menu_item(c, "row-menu/pin", "pin", tr(if p { "web-main.chat.unpin" } else { "web-main.chat.pin" })) {
          close()
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
        }
      None => ()
    }
    if menu_item(c, "row-menu/rename", "edit", tr("web-main.chat.rename")) {
      close()
      wide.renaming = key
    }
    match item.thread {
      Some(th) =>
        if menu_item(c, "row-menu/keep", "shield-check", tr(if item.kept { "web-main.chat.unkeep" } else { "web-main.chat.keep" })) {
          close()
          act(
            src,
            tr("android-chat.chat.keep.verb"),
            "keep/" + item.station + "/" + th.to_int64().to_string(),
            "chat.keep",
            {
              "station": Json::string(item.station),
              "thread": Json::number(th),
              "kept": Json::boolean(!item.kept),
            },
            done=tr(if item.kept { "web-main.chat.unkeep.done" } else { "web-main.chat.keep.done" }),
          )
        }
      None => ()
    }
    let link = chat_link(item.station, item.session)
    if link != "" && menu_item(c, "row-menu/link", "copy", tr("web-main.chat.copyLink")) {
      close()
      copy_chat_link(c, item.title, link)
    }
    if menu_item(c, "row-menu/archive", "archive", tr("web-main.chat.archive")) {
      close()
      archive_row(c, src, item)
    }
  })
}

///|
/// What ⌘K's field holds.
let switcher_query : Ref[String] = Ref("")

///|
/// The switcher's words, and a row's title being renamed in place (their fields show them).
let switcher_field : @ui.Field = @ui.Field::new()

///|
let side_rename_field : @ui.Field = @ui.Field::new()

///|
/// ⌘K (Switcher.tsx ChatSwitcher): over a scrim, 14% down the window, 560 wide at most: a field (搜索全部内容和操作), the
/// chats whose titles hold what is typed (all of them, newest first, while nothing is), ↑ / ↓ to choose, Enter or a
/// press to open; Esc or a press outside closes it.
fn switcher(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  if !wide.switcher {
    return
  }
  let t = @sf.theme()
  let query = switcher_query.val.trim(chars=" ").to_string()
  let rows : Array[ChatItem] = []
  match chats_of(src, w.id, "all") {
    (Some(v), _) =>
      for d in v.days {
        for item in d.items {
          if query == "" || lower(item.title).contains(lower(query)) {
            rows.push(item)
          }
        }
      }
    _ => ()
  }
  let shown = if rows.length() > 12 { rows[:12].to_array() } else { rows }
  if wide.chosen >= shown.length() {
    wide.chosen = dmax(0.0, (shown.length() - 1).to_double()).to_int()
  }
  if c.key_pressed(@ui.key_code_down, in_field=true) && wide.chosen < shown.length() - 1 {
    wide.chosen += 1
  }
  if c.key_pressed(@ui.key_code_up, in_field=true) && wide.chosen > 0 {
    wide.chosen -= 1
  }
  let open = fn(item : ChatItem) {
    wide.switcher = false
    c.blur()
    open_row(item)
  }
  let width = dmin(560.0, c.width - 32.0)
  let panel = c.id("switcher")
  let (px, py, _) = c.pointer()
  if cui.press_new {
    match c.rect_of(panel) {
      Some((rx, ry, rw, rh)) if !(px >= rx && px < rx + rw && py >= ry && py < ry + rh) => {
        wide.switcher = false
        c.blur()
        return
      }
      _ => ()
    }
  }
  c.layer(fn() {
    c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.overlay, align=ACenter, fn() {
      c.box(h=Px(c.height * 0.14), fn() {  }) |> ignore
      c.box(
        w=Px(width),
        max_h=dmin(480.0, c.height * 0.72),
        pad=12.0,
        gap=4.0,
        radius=31.0,
        bg=panel_ground(),
        border=1.0,
        border_color=t.p.line,
        shadow=64.0,
        shadow_y=24.0,
        shadow_color=t.p.shadow,
        clip=true,
        id=panel,
        fn() {
          c.box(dir=Row, w=Fill(1.0), h=Px(48.0), padx=10.0, gap=10.0, align=ACenter, fn() {
            @sf.icon(c, "search", size=18.0, color=t.p.muted) |> ignore
            let res = c.editor(
              "switcher/field",
              placeholder=tr("web-main.switcher.search"),
              font_size=16.0,
              line=24.0,
              max_lines=1,
              plain=true,
              color=t.p.text,
              placeholder_color=t.p.subtle,
              caret_color=t.p.accent,
              enter_sends=true,
              field=switcher_field,
            )
            if !res.focused && !c.field_focused() {
              c.focus_editor("switcher/field")
            }
            if res.text != switcher_query.val {
              switcher_query.val = res.text
              wide.chosen = 0
            }
            match res.submitted {
              Some(words) => {
                switcher_field.set(words)
                if wide.chosen < shown.length() {
                  open(shown[wide.chosen])
                }
              }
              None => ()
            }
          })
          |> ignore
          if shown.length() == 0 {
            c.box(w=Fill(1.0), padx=10.0, pady=10.0, fn() {
              c.text(
                tr(if query == "" { "web-main.switcher.none" } else { "web-main.switcher.noMatch" }),
                size=13.0,
                color=t.p.muted,
                wrap=false,
              )
              |> ignore
            })
            |> ignore
          } else {
            c.box(padx=10.0, pt=6.0, pb=2.0, fn() {
              c.text(tr("web-main.switcher.chats"), size=12.0, color=t.p.muted, wrap=false) |> ignore
            })
            |> ignore
          }
          for k, item in shown {
            let id = c.id("switcher/row/" + item.station + "/" + item.id)
            c.cursor(id, Hand)
            if c.clicked(id) {
              open(item)
            }
            if c.hovered(id) {
              wide.chosen = k
            }
            c.box(
              dir=Row,
              w=Fill(1.0),
              min_h=38.0,
              padx=10.0,
              gap=8.0,
              align=ACenter,
              radius=12.0,
              bg=if k == wide.chosen { @sf.alpha(t.p.text, 0.07) } else { 0L },
              id~,
              fn() {
                @sf.icon(c, "chat", size=16.0, color=t.p.muted) |> ignore
                c.box(w=Fill(1.0), fn() {
                  c.text(item.title, size=13.0, color=t.p.text, wrap=false, line=20.0) |> ignore
                })
                |> ignore
                c.text(item.station_name, size=12.0, color=t.p.subtle, wrap=false) |> ignore
              },
            )
            |> ignore
          }
        },
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// ⌘/ (Shortcuts.tsx ShortcutsDialog): the shortcuts this app keeps, by group, over a scrim.
fn keys_dialog(c : @ui.Ctx) -> Unit {
  if !wide.keys_open {
    return
  }
  let t = @sf.theme()
  let mac = @ui.platform() == 0
  let cmd = if mac { "⌘" } else { "Ctrl+" }
  let alt = if mac { "⌥" } else { "Alt+" }
  let shift = if mac { "⇧" } else { "Shift+" }
  let groups : Array[(String, Array[(String, String)])] = [
    (
      tr("web-main.keymap.group.global"),
      [
        (tr("web-main.keymap.chat.switch"), cmd + "K"),
        (tr("web-main.keymap.chat.new"), cmd + "N"),
        (tr("web-main.keymap.chat.prev"), alt + "↑"),
        (tr("web-main.keymap.chat.next"), alt + "↓"),
        (tr("web-main.keymap.sidebar.toggle"), cmd + "\\"),
        (tr("web-main.keymap.settings"), cmd + ","),
        (tr("web-main.keymap.shortcuts"), cmd + "/"),
      ],
    ),
    (
      tr("web-main.shortcuts.group.composer"),
      [
        (tr("web-main.shortcuts.send"), "Enter"),
        (tr("web-main.shortcuts.newline"), shift + "Enter"),
        (tr("web-main.keymap.composer.focus"), tr("web-main.keymap.space")),
      ],
    ),
  ]
  let panel = c.id("keys-dialog")
  let (px, py, _) = c.pointer()
  if cui.press_new {
    match c.rect_of(panel) {
      Some((rx, ry, rw, rh)) if !(px >= rx && px < rx + rw && py >= ry && py < ry + rh) => {
        wide.keys_open = false
        return
      }
      _ => ()
    }
  }
  c.layer(fn() {
    c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.overlay, align=ACenter, justify=JCenter, fn() {
      c.box(
        w=Px(dmin(520.0, c.width - 32.0)),
        pad=20.0,
        gap=6.0,
        radius=42.0,
        bg=panel_ground(),
        border=1.0,
        border_color=t.p.line,
        shadow=64.0,
        shadow_y=24.0,
        shadow_color=t.p.shadow,
        id=panel,
        fn() {
          c.text(tr("web-main.shortcuts.title"), size=16.0, weight=600, color=t.p.text, wrap=false, line=24.0)
          |> ignore
          for g in groups {
            c.box(pt=10.0, pb=2.0, fn() {
              c.text(g.0, size=12.0, color=t.p.muted, wrap=false, line=18.0) |> ignore
            })
            |> ignore
            for k in g.1 {
              c.box(dir=Row, w=Fill(1.0), h=Px(30.0), align=ACenter, fn() {
                c.box(w=Fill(1.0), fn() { c.text(k.0, size=13.0, color=t.p.text, wrap=false) |> ignore })
                |> ignore
                c.box(padx=6.0, pady=2.0, radius=6.0, bg=t.p.hover, fn() {
                  c.text(k.1, size=12.0, color=t.p.muted, wrap=false) |> ignore
                })
                |> ignore
              })
              |> ignore
            }
          }
        },
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
}
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

