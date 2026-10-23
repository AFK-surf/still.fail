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
    } else if wide.switcher && sw.kind != "" {
      // one kind's list: back to all of them
      sw.kind = ""
      wide.chosen = 0
    } else if wide.switcher {
      // (its field let go: the keyboard goes nowhere until another is pressed)
      wide.switcher = false
      c.blur()
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
    }
  }
  // Space with no field focused: back to the composer (回到输入框)
  if !c.field_focused() && pressed("composer.focus") && !wide.switcher {
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
/// A chat's row's menu (Sidebar.tsx ContextMenu): 固定 / 取消固定, 重命名, 保留 / 取消保留, 复制会话链接, 复制 session 文件
/// 路径, 归档; at where
/// the row was right clicked (mbui's dropdown menu there).
fn row_menu(c : @ui.Ctx, src : Source) -> Unit {
  let (key, item, x, y) = match wide.menu {
    Some(m) => m
    // (closed: told so, for its going)
    None => {
      wide_menu(c, "row-menu", false, 0, [], {}, menu_w) |> ignore
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
  let m = wide_menu(c, "row-menu", true, 0, entries, icons, menu_w, offset=0.0, at=(x, y, 0.0, 0.0))
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
/// What ⌘K's field holds.
let switcher_query : Ref[String] = Ref("")

///|
/// The switcher's words, and a row's title being renamed in place (their fields show them).
let switcher_field : @ui.Field = @ui.Field::new()

///|
let side_rename_field : @ui.Field = @ui.Field::new()

///|
/// ⌘K (Switcher.tsx ChatSwitcher): over a scrim, 14% down the window, 560 wide at most: a field (搜索全部内容和操作), the
/// list of what the words find and what can be done (wide_switcher.mbt), ↑ / ↓ to choose, Enter or a press to open;
/// Esc (in one kind's list: back to all of them) or a press outside closes it.
fn switcher(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  if !wide.switcher {
    sw_reset()
    return
  }
  let t = @sf.theme()
  let query = switcher_query.val.trim(chars=" ").to_string()
  let lines = sw_lines(c, src, w, query)
  let picks : Array[Int] = []
  // each line's place among those chosen (-1 a heading's)
  let pick_of : Array[Int] = []
  for i, l in lines {
    if sw_pickable(l) {
      pick_of.push(picks.length())
      picks.push(i)
    } else {
      pick_of.push(-1)
    }
  }
  if wide.chosen >= picks.length() {
    wide.chosen = dmax(0.0, (picks.length() - 1).to_double()).to_int()
  }
  let mut keyed = false
  if c.key_pressed(@ui.key_code_down, in_field=true) && wide.chosen < picks.length() - 1 {
    wide.chosen += 1
    keyed = true
  }
  if c.key_pressed(@ui.key_code_up, in_field=true) && wide.chosen > 0 {
    wide.chosen -= 1
    keyed = true
  }
  // the list as tall as its lines (as much as the panel holds), scrolled to the line the keys chose
  let est = lines.fold(init=0.0, fn(h, l) { h + sw_line_h(l) })
  let list_h = dmin(dmin(480.0, c.height * 0.72) - sw_panel_rest, est)
  if keyed {
    match picks.get(wide.chosen) {
      Some(k) => c.list_scroll_to("switcher/list", if k > sw_lead { k - sw_lead } else { 0 })
      None => ()
    }
  }
  let words = match sw.kept {
    Some(v) => v.words
    None => []
  }
  let width = dmin(560.0, c.width - 32.0)
  let panel = c.id("switcher")
  // mbui's layer over the page (modal: its scrim takes the presses outside, Tab stays in it; Esc, back or a press
  // outside dismiss it), the panel 14% down the window in its middle
  let o = c.overlay("switcher-layer", modal=true, scrim=t.p.overlay, initial_focus=0, fn() {
    let i = c.box(
      w=Px(width),
      max_h=dmin(480.0, c.height * 0.72),
      pad=12.0,
      gap=4.0,
      radius=31.0,
      bg=panel_ground(),
      border=1.0,
      border_color=t.p.line,
      shadow=32.0,
      shadow_y=24.0,
      shadow_color=t.p.shadow,
      clip=true,
      id=panel,
      fn() {
        c.box(dir=Row, w=Fill(1.0), h=Px(48.0), padx=10.0, gap=10.0, align=ACenter, fn() {
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
            Some(typed) => {
              switcher_field.set(typed)
              match picks.get(wide.chosen) {
                Some(k) => sw_go(c, lines[k], words)
                None => ()
              }
            }
            None => ()
          }
        })
        |> ignore
        if picks.length() == 0 {
          c.box(style=sw_head, fn() {
            c.text(
              tr(if query == "" { "web-main.switcher.none" } else { "web-main.switcher.noMatch" }),
              style=sw_title_muted,
            )
            |> ignore
          })
          |> ignore
        }
        c.list(
          "switcher/list",
          lines.length(),
          sw_row_est,
          fn(i) {
            let line = lines[i]
            let key = "switcher/row/" + sw_key(line)
            let k = pick_of[i]
            if k >= 0 {
              let id = c.id(key)
              c.cursor(id, Hand)
              if c.clicked(id) {
                sw_go(c, line, words)
              }
              if c.hovered(id) {
                wide.chosen = k
              }
              sw_line(c, key, line, k == wide.chosen)
            } else {
              sw_line(c, key, line, false)
            }
          },
          h=Px(list_h),
        )
        |> ignore
      },
    )
    c.place_by_size(i, fn(pw, _) { ((c.width - pw) / 2.0, c.height * 0.14) })
  })
  if o.dismissed is Some(_) {
    wide.switcher = false
    c.blur()
  }
}

///|
/// ⌘/ (Shortcuts.tsx ShortcutsDialog): the shortcuts this app keeps, by group, in mbui's dialog (over a scrim, in the
/// window's middle; Esc, back or a press outside close it) in the web's look.
fn keys_dialog(c : @ui.Ctx, src : Source) -> Unit {
  let t = @sf.theme()
  let mac = @ui.platform() == 0
  let shift = if mac { "⇧" } else { "Shift+" }
  let prefs = (src.topic)("prefs", {}).value
  let keys = fn(action : String) { (tr("web-main.keymap." + action), @settings.keys_text(prefs, action)) }
  let groups : Array[(String, Array[(String, String)])] = [
    (
      tr("web-main.keymap.group.global"),
      ["chat.switch", "chat.new", "chat.prev", "chat.next", "sidebar.toggle", "settings", "shortcuts"].map(keys),
    ),
    (tr("web-main.keymap.group.chat"), ["chat.find", "chat.jobs"].map(keys)),
    (
      tr("web-main.shortcuts.group.composer"),
      [
        (tr("web-main.shortcuts.send"), "Enter"),
        (tr("web-main.shortcuts.newline"), shift + "Enter"),
        keys("composer.focus"),
      ],
    ),
  ]
  let d = @kit.dialog(
    c,
    "keys-dialog",
    wide.keys_open,
    tr("web-main.shortcuts.title"),
    w=dmin(520.0, c.width - 32.0),
    close_label="",
    look=fn(c, s, body) {
      c.box(
        w=Px(s.w),
        pad=20.0,
        gap=6.0,
        radius=42.0,
        bg=panel_ground(),
        border=1.0,
        border_color=t.p.line,
        shadow=32.0,
        shadow_y=24.0,
        shadow_color=t.p.shadow,
        fn() {
          c.text(s.title, size=16.0, weight=600, color=t.p.text, wrap=false, line=24.0) |> ignore
          body()
        },
      )
      |> ignore
    },
    fn() {
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
  wide.keys_open = d.value
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

