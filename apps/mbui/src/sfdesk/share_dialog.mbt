// A chat shared with the viewer's other workspaces (docs/chat-share.md; ember web/src/pages/ChatPage.tsx ShareOf,
// ShareDialog; ChatPage.css.ts shareList, shareWrite): from its info's 共享 row, for those who may change it, a dialog
// ticks the workspaces it is shared with and whether their agents may send in it; 完成 has the core tell its station
// (`chat.xshare`), the dialog gone at once, the row turning while it is told. What it lists is the chat's `xshare`,
// read while it is open.

///|
/// The dialog open for a chat (None: closed) and its thread, the workspaces ticked (as it was shared as it opened),
/// whether their agents may send.
priv struct ShareDialog {
  mut of : (ChatRef, Double?)?
  ticked : Map[String, Bool]
  mut write : Bool
}

///|
let share_dialog_state : ShareDialog = { of: None, ticked: {}, write: false }

///|
fn share_dialog_reset() -> Unit {
  share_dialog_state.of = None
  share_dialog_state.ticked.clear()
  share_dialog_state.write = false
}

///|
/// The dialog opened for chat `r` (its thread), ticked as it is shared now.
fn open_share(src : Source, r : ChatRef, thread : Double?) -> Unit {
  share_dialog_reset()
  let share = field((src.topic)("chat", chat_params(r)).value, "xshare")
  for p in items(share, "places") {
    if flag(Some(p), "on") {
      share_dialog_state.ticked[text(Some(p), "workspace")] = true
    }
  }
  share_dialog_state.write = flag(share, "write")
  share_dialog_state.of = Some((r, thread))
}

///|
/// The dialog (ShareDialog), while it is open and the chat says where it may be shared: the workspaces, each a row
/// with its box; 允许它们的 agent 发言 (off while none is ticked); 完成.
fn share_dialog(c : @ui.Ctx, src : Source) -> Unit {
  let (r, thread) = match share_dialog_state.of {
    Some(o) => o
    None => return
  }
  let share = field((src.topic)("chat", chat_params(r)).value, "xshare")
  if !(share is Some(Object(_))) {
    return
  }
  let places = items(share, "places")
  let none = share_dialog_state.ticked.is_empty()
  let shown = @sf.dialog(
    c,
    "xshare",
    true,
    @sf.t("web-pages.chat.xshare"),
    description=@sf.t("web-pages.chat.xshare.lead"),
    footer=fn() {
      if @sf.button(c, @sf.t("common.done"), key="xshare/done", tone=Primary) {
        // in the order the dialog lists them
        let to = places.map(fn(p) { text(Some(p), "workspace") }).filter(fn(ws) { share_dialog_state.ticked.contains(ws) })
        let p : Map[String, Json] = {
          "station": Json::string(r.station),
          "session": Json::string(text(share, "session")),
          "to": Json::array(to.map(Json::string(_))),
          "write": Json::boolean(share_dialog_state.write),
        }
        match thread {
          Some(th) => p["thread"] = Json::number(th)
          None => ()
        }
        share_dialog_reset()
        act(src, @sf.t("web-pages.chat.xshare.verb"), "", "chat.xshare", Json::object(p))
      }
    },
    fn() {
      c.box(style=desk_list, fn() {
        for p in places {
          let ws = text(Some(p), "workspace")
          let name = text(Some(p), "name")
          c.box(style=desk_list_row, fn() {
            let on = share_dialog_state.ticked.contains(ws)
            let now = @kit.checkbox(c, "xshare/" + ws, if on { On } else { Off }, label=name).value
            if (now == On) != on {
              if now == On {
                share_dialog_state.ticked[ws] = true
              } else {
                share_dialog_state.ticked.remove(ws)
              }
            }
            c.text(name, style=desk_list_title) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      c.box(style=share_write, fn() {
        let now = @sf.switch_row(
          c,
          "xshare/write",
          @sf.t("web-pages.chat.xshare.write"),
          share_dialog_state.write,
          note=@sf.t("web-pages.chat.xshare.writeNote"),
          disabled=none,
        )
        share_dialog_state.write = now
      })
      |> ignore
    },
  )
  if !shown {
    share_dialog_reset()
  }
}

///|
/// The write switch, 8 under the workspaces (shareWrite).
// kept across runs: a value (no field of it changes)
let share_write : @ui.Style = @ui.css("w=Full pt=S2")
