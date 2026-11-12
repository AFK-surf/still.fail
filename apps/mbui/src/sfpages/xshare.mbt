// A chat shared with the viewer's other workspaces (still.fail web/src/pages/ChatPage.tsx ShareOf,
// ShareDialog, the phone's ShareSheet in mobile/Chat.tsx; ChatPage.css.ts shareList, shareWrite), one on every screen:
// from its info's 共享 row, for those who may change it (its starter, an owner or admin), the presenters' panel (a
// sheet with touch short of Large, the web's dialog otherwise) ticks the workspaces it is shared with and
// whether their agents may send in it; 完成 has the core tell its station (`chat.xshare`), the panel gone at once, the
// row turning while it is told (its key: xshare_key), and the chat's link copied at once when it is shared with any, to
// paste there (pengxiao, 2026-11-11). What it lists is the chat's `xshare`.

///|
/// The workspaces ticked (as it was shared as it opened), whether their agents may send; whether the chat's sharing was
/// read yet (opened from a row's menu, its page's `xshare` comes after: ticked as it is shared once it has come). Each a
/// signal: what the panel holds is bound to them.
priv struct XSharing {
  ticked : @signals.Signal[Array[String]]
  write : @signals.Signal[Bool]
  read : @signals.Signal[Bool]
}

///|
// kept across runs: the one panel's state, set afresh as it opens (xsharing_reset)
let xsharing : XSharing = {
  ticked: @signals.signal([]),
  write: @signals.signal(false),
  read: @signals.signal(false),
}

///|
/// As at the start (the package's reset).
fn xsharing_reset() -> Unit {
  xsharing.ticked.set([])
  xsharing.write.set(false)
  xsharing.read.set(false)
}

///|
/// Ticked as the chat is shared now (its `share`, the chat's `xshare`), once it is read (once only: what is ticked
/// afterwards is the viewer's).
fn xsharing_read(share : Json?) -> Unit {
  if xsharing.read.untracked() {
    return
  }
  guard share is Some(_) else { return }
  xsharing.read.set(true)
  xsharing.ticked.set(items(share, "places").filter(fn(p) { flag(Some(p), "on") }).map(fn(p) { text(Some(p), "workspace") }))
  xsharing.write.set(flag(share, "write"))
}

///|
/// Whether workspace `ws` is ticked.
fn xsharing_ticks(ws : String) -> Bool {
  xsharing.ticked.get().contains(ws)
}

///|
/// Workspace `ws` ticked or not.
fn xsharing_tick(ws : String, on : Bool) -> Unit {
  let was = xsharing.ticked.untracked()
  if on && !was.contains(ws) {
    xsharing.ticked.set([..was, ws])
  } else if !on {
    xsharing.ticked.set(was.filter(fn(w) { w != ws }))
  }
}

///|
/// What is under way while the chat's sharing is changed (its info's row turning).
pub fn xshare_key(station : String, session : String) -> String {
  "xshare/" + station + "/" + session
}

///|
/// Opens what changes where chat `r` (its thread) is shared, ticked as it is shared now, from `from`. What it holds and
/// its button are nodes of the window's tree, made once as it opens (@sf.panel_nodes), bound to the chat's `xshare`.
pub fn open_xshare(src : Source, r : ChatRef, thread : Double?, from~ : @sf.Anchor) -> Unit {
  xsharing_reset()
  let share = fn() { field(src.topic("chat", chat_params(r)).get().value, "xshare") }
  @sf.panel_nodes(
    @sf.t("web-pages.chat.xshare"),
    fn(v, _) { xshare_body(v, share) },
    from~,
    description=@sf.t("web-pages.chat.xshare.lead"),
    foot=fn(v, close) {
      // (not before what it is shared with now is read: 完成 would share it with none)
      @sf.button_node(
        v,
        fn() { @sf.t("common.done") },
        fn() {
          xshare_done(src, r, thread)
          close()
        },
        tone=Primary,
        disabled=fn() { !xsharing.read.get() },
      )
      |> ignore
    },
  )
}

///|
/// 完成: the station told, in the order the panel lists them; shared with any, the chat's link copied in the same
/// press (a browser lets the clipboard be written only so), said by its toast.
fn xshare_done(src : Source, r : ChatRef, thread : Double?) -> Unit {
  let share = field(src.topic("chat", chat_params(r)).get().value, "xshare")
  let ticked = xsharing.ticked.untracked()
  let to = items(share, "places").map(fn(p) { text(Some(p), "workspace") }).filter(fn(ws) { ticked.contains(ws) })
  let session = text(share, "session")
  let p : Map[String, Json] = {
    "station": Json::string(r.station),
    "session": Json::string(session),
    "to": Json::array(to.map(x => Json::string(x))),
    "write": Json::boolean(xsharing.write.untracked()),
  }
  match thread {
    Some(th) => p["thread"] = Json::number(th)
    None => ()
  }
  let link = @sfbase.chat_link(r.station, r.session)
  if to.length() > 0 && link != "" {
    @sfbase.copy_chat_link(r.title, link)
  }
  act(src, @sf.t("web-pages.chat.xshare.verb"), xshare_key(r.station, session), "chat.xshare", Json::object(p))
}

///|
/// The workspaces the chat's sharing (`share`, as it is now) lists, each a row with its box, in node `v` (the panel's
/// body's); 允许它们的 agent 发言 (off while none is ticked: the switch's note says so). Ticked as it is shared once that
/// is read, as it comes.
fn xshare_body(v : @view.View, share : () -> Json?) -> Unit {
  v.reacts(share, xsharing_read)
  v.box(fn(list) {
    @sf.style_node(list, fn() { xshare_list })
    list.each(fn() { items(share(), "places") }, fn(p) { text(Some(p), "workspace") }, fn(row, p) {
      let ws = text(Some(p.untracked()), "workspace")
      let place = fn(k : String) { text(Some(p.get()), k) }
      @sf.check_row_node(
        row,
        fn() { place("name") },
        fn() { xsharing_ticks(ws) },
        fn(now) { xsharing_tick(ws, now) },
        lead=fn(l) { @sf.workspace_badge_node(l, fn() { place("name") }, fn() { place("emoji") }, fn() { place("icon") }, xshare_mark) },
      )
    })
  })
  |> ignore
  v.box(fn(w) {
    @sf.style_node(w, fn() { xshare_write })
    @sf.panel_switch_noted_node(
      w,
      fn() { @sf.t("web-pages.chat.xshare.write") },
      fn() { xsharing.write.get() },
      fn(on) { xsharing.write.set(on) },
      note=fn() { @sf.t("web-pages.chat.xshare.writeNote") },
      disabled=fn() { xsharing.ticked.get().is_empty() },
    )
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
