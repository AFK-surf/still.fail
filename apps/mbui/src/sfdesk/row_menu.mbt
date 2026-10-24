// A chat's row's menu and its title renamed in place (ember web/src/Sidebar.tsx ChatRow's ContextMenu, Rename.tsx
// TitleInput, ChatRef.tsx useCopyChatLink and useCopyTranscripts): at the pointer where the row was right clicked,
// the library's menu (@sf.menu: controls.css.ts popover, menuList, menuItem).

///|
/// What the row's menu and its rename keep: the row whose title the field holds, whether the field had the keyboard
/// last frame (it losing it ends the rename), the field.
priv struct RowMenu {
  mut rename_for : String
  mut rename_seen : Bool
  rename_field : @ui.Field
}

///|
let row_kept : RowMenu = { rename_for: "", rename_seen: false, rename_field: @ui.Field::new() }

///|
fn row_menu_reset() -> Unit {
  row_kept.rename_for = ""
  row_kept.rename_seen = false
  row_kept.rename_field.set("")
}

///|
/// A chat's row's menu (Sidebar.tsx ContextMenu): 固定 / 取消固定 (a station from before pins says nothing: none),
/// 重命名, 保留 / 取消保留 (a chat of its own: a thread), 复制会话链接, 转到频道 (a thread with an agent), 复制 session 文件
/// 路径, 归档; its top left at where the row was right clicked.
fn row_menu(c : @ui.Ctx, src : Source, pages : Pages) -> Unit {
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
    Some(p) => entries.push(@kit.menu_item("pin", label=@sf.t(if p { "web-main.chat.unpin" } else { "web-main.chat.pin" })))
    None => ()
  }
  entries.push(@kit.menu_item("rename", label=@sf.t("web-main.chat.rename")))
  match item.thread {
    Some(_) =>
      entries.push(
        @kit.menu_item("keep", label=@sf.t(if item.kept { "web-main.chat.unkeep" } else { "web-main.chat.keep" })),
      )
    None => ()
  }
  let link = chat_link(item.station, item.session)
  if link != "" {
    entries.push(@kit.menu_item("link", label=@sf.t("web-main.chat.copyLink")))
  }
  // relayed to a channel (docs/relay.md): a chat with an agent to go on there
  match item.thread {
    Some(_) if item.agents.length() > 0 => entries.push(@kit.menu_item("relay", label=@sf.t("web-main.relay.action")))
    _ => ()
  }
  entries.push(@kit.menu_item("transcript", label=@sf.t("web-main.chat.copyTranscript")))
  entries.push(@kit.menu_item("archive", label=@sf.t("web-main.chat.archive")))
  // (its top left at the pointer, as the web's context menu opens)
  let m = @sf.menu(c, "row-menu", true, 0, entries, row_menu_icons, @sf.menu_w, offset=0.0, at=(x, y, 0.0, 0.0))
  if !m.open {
    wide.menu = None
  }
  match m.chosen {
    Some("pin") =>
      match item.pinned {
        Some(p) =>
          act(
            src,
            @sf.t(if p { "android-chat.unpin.verb" } else { "android-chat.pin.verb" }),
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
            @sf.t(if item.kept { "web-main.chat.unkeep.what" } else { "web-main.chat.keep.what" }),
            "keep/" + item.station + "/" + th.to_int64().to_string(),
            "chat.keep",
            {
              "station": Json::string(item.station),
              "thread": Json::number(th),
              "kept": Json::boolean(!item.kept),
            },
            done=@sf.t(if item.kept { "web-main.chat.unkeep.done" } else { "web-main.chat.keep.done" }),
          )
        None => ()
      }
    Some("link") => copy_chat_link(c, item.title, link)
    Some("relay") =>
      match item.thread {
        Some(th) =>
          (pages.relay)(
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
/// Each of the row's menu's entries' icon (Sidebar.tsx: Pin, Edit, ShieldCheck, Copy, ArrowUpRight, File, Archive).
// kept across runs: a table, never written
let row_menu_icons : Map[String, String] = {
  "pin": "pin",
  "rename": "edit",
  "keep": "shield-check",
  "link": "copy",
  "relay": "arrow-up-right",
  "transcript": "file",
  "archive": "archive",
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
      Some(e) => say(c, @sf.t("web-main.chat.copyFailed", args=[("error", e)]))
      None => {
        let found = paths.filter_map(fn(p) { p })
        if found.length() == 0 {
          say(c, @sf.t("web-main.chat.transcriptNone"))
        } else {
          c.copy_text(found.join("\n"))
          say(c, if found.length() > 1 {
            @sf.t("web-main.chat.transcriptsCopied", args=[("n", found.length().to_string())])
          } else {
            @sf.t("web-main.chat.transcriptCopied")
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
/// A row's title as a field (Rename.tsx TitleInput, from its menu's 重命名): Enter saves it (`chat.rename`), Esc or
/// leaving it lets it be.
fn side_rename(c : @ui.Ctx, src : Source, item : ChatItem) -> Unit {
  let key = "side/rename"
  if row_kept.rename_for != item.station + "/" + item.id {
    row_kept.rename_for = item.station + "/" + item.id
    row_kept.rename_field.set(item.title)
    c.focus_editor(key)
  }
  c.box(style=rename_box.then(@ui.style(border_color=Data(@sf.theme().p.line_strong))), fn() {
    let res = c.editor(
      key,
      font_size=rename_size,
      line=rename_line,
      max_lines=1,
      plain=true,
      color=@sf.theme().p.text,
      caret_color=@sf.theme().p.accent,
      enter_sends=true,
      field=row_kept.rename_field,
    )
    match res.submitted {
      Some(title) => {
        wide.renaming = ""
        row_kept.rename_for = ""
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
          act(src, @sf.t("android-chat.rename.verb"), "", "chat.rename", Json::object(p))
        }
      }
      None => if !res.focused && row_kept.rename_for != "" && row_kept.rename_seen { wide.renaming = "" }
    }
    row_kept.rename_seen = res.focused
  })
  |> ignore
}

///|
/// The field in the title's place (Rename.css.ts titleInput): as wide as the row's head leaves, 24 high on the canvas,
/// its words where the title's were (6 past them each side), 4 taller than the title's line without making the row
/// taller; a 1 line round it in the strong grey, 6 round; the title's words (13 on 24).
// kept across runs: a value (no field of it changes)
let rename_box : @ui.Style = @sf.bleed_x(rename_bleed)
  .then(@sf.in_line(rename_taller))
  .then(@ui.css("w=Full h=S6 radius=Md bg=Bg border=B1 justify=JCenter"))

///|
let rename_bleed : Double = 6.0

///|
let rename_taller : Double = 4.0

///|
let rename_size : Double = 13.0

///|
let rename_line : Double = 24.0
