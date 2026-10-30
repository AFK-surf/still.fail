// A chat shared with the viewer's other workspaces (docs/chat-share.md; ember web/src/pages/ChatPage.tsx ShareOf,
// ShareDialog, the phone's ShareSheet in mobile/Chat.tsx; ChatPage.css.ts shareList, shareWrite), one on every screen:
// from its info's 共享 row, for those who may change it (its starter, an owner or admin), the presenters' panel (a
// sheet with touch short of Large, the web's dialog otherwise) ticks the workspaces it is shared with and
// whether their agents may send in it; 完成 has the core tell its station (`chat.xshare`), the panel gone at once, the
// row turning while it is told (its key: xshare_key). What it lists is the chat's `xshare`.

///|
/// The workspaces ticked (as it was shared as it opened), whether their agents may send.
priv struct XSharing {
  ticked : Map[String, Bool]
  write : @signals.Signal[Bool]
}

///|
let xsharing : XSharing = { ticked: {}, write: @signals.signal(false, same=fn(a, b) { a == b }) }

///|
/// As at the start (the package's reset).
fn xsharing_reset() -> Unit {
  xsharing.ticked.clear()
  xsharing.write.set(false)
}

///|
/// What is under way while the chat's sharing is changed (its info's row turning).
pub fn xshare_key(station : String, session : String) -> String {
  "xshare/" + station + "/" + session
}

///|
/// Opens what changes where chat `r` (its thread) is shared, ticked as it is shared now, from `from`.
pub fn open_xshare(src : Source, r : ChatRef, thread : Double?, from~ : @sf.Anchor) -> Unit {
  xsharing_reset()
  let share = field((src.topic)("chat", chat_params(r)).value, "xshare")
  for p in items(share, "places") {
    if flag(Some(p), "on") {
      xsharing.ticked[text(Some(p), "workspace")] = true
    }
  }
  xsharing.write.set(flag(share, "write"))
  @sf.panel(
    @sf.t("web-pages.chat.xshare"),
    fn(c, _) { xshare_body(c, src, r) },
    from~,
    description=@sf.t("web-pages.chat.xshare.lead"),
    foot=fn(c, close) {
      if @sf.button(c, @sf.t("common.done"), key="xshare/done", tone=Primary) {
        xshare_done(src, r, thread)
        close()
      }
    },
  )
}

///|
/// 完成: the station told, in the order the panel lists them.
fn xshare_done(src : Source, r : ChatRef, thread : Double?) -> Unit {
  let share = field((src.topic)("chat", chat_params(r)).value, "xshare")
  let to = items(share, "places").map(fn(p) { text(Some(p), "workspace") }).filter(fn(ws) { xsharing.ticked.contains(ws) })
  let session = text(share, "session")
  let p : Map[String, Json] = {
    "station": Json::string(r.station),
    "session": Json::string(session),
    "to": Json::array(to.map(Json::string(_))),
    "write": Json::boolean(xsharing.write.get()),
  }
  match thread {
    Some(th) => p["thread"] = Json::number(th)
    None => ()
  }
  act(src, @sf.t("web-pages.chat.xshare.verb"), xshare_key(r.station, session), "chat.xshare", Json::object(p))
}

///|
/// The workspaces, each a row with its box; 允许它们的 agent 发言 (off while none is ticked: the switch's note says so).
fn xshare_body(c : @ui.Ctx, src : Source, r : ChatRef) -> Unit {
  let share = field((src.topic)("chat", chat_params(r)).value, "xshare")
  c.box(style=xshare_list, fn() {
    for p in items(share, "places") {
      let ws = text(Some(p), "workspace")
      let name = text(Some(p), "name")
      let on = xsharing.ticked.contains(ws)
      let lead = fn(c : @ui.Ctx) {
        @sf.workspace_badge(c, name, text(Some(p), "emoji"), text(Some(p), "icon"), xshare_mark)
      }
      if @sf.check_row(c, "xshare/" + ws, name, on, lead~) != on {
        if on {
          xsharing.ticked.remove(ws)
        } else {
          xsharing.ticked[ws] = true
        }
      }
    }
  })
  |> ignore
  c.box(style=xshare_write, fn() {
    xsharing.write.set(@sf.switch_row(
      c,
      "xshare/write",
      @sf.t("web-pages.chat.xshare.write"),
      xsharing.write.get(),
      note=@sf.t("web-pages.chat.xshare.writeNote"),
      disabled=xsharing.ticked.is_empty(),
    ))
  })
  |> ignore
}

///|
/// A workspace's mark before its name (WorkspaceNamed's 16 on the web's rows).
let xshare_mark : Double = 16.0

///|
/// The workspaces (shareList: out past the panel's words by a row's room, 12, its rows as wide), 2 apart, each a tick
/// row (@sf.check_row: its room the screen's).
let xshare_list_out : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let xshare_list : @ui.Style = @sf.outset(xshare_list_out).then(@ui.css("gap=S0_5"))

///|
/// The write switch, 8 under the workspaces (shareWrite).
// kept across runs: a value (no field of it changes)
let xshare_write : @ui.Style = @ui.css("w=Full pt=S2")
