// A chat shared with the viewer's other workspaces (docs/chat-share.md; ember web/src/pages/ChatPage.tsx ShareOf,
// ShareDialog, the phone's ShareSheet in mobile/Chat.tsx; ChatPage.css.ts shareList, shareWrite), one on every screen:
// from its info's 共享 row, for those who may change it (its starter, an owner or admin), the presenters' panel (a
// sheet on a touch device short of Large, the web's dialog otherwise) ticks the workspaces it is shared with and
// whether their agents may send in it; 完成 has the core tell its station (`chat.xshare`), the panel gone at once, the
// row turning while it is told (its key: xshare_key). What it lists is the chat's `xshare`.

///|
/// The workspaces ticked (as it was shared as it opened), whether their agents may send.
priv struct XSharing {
  ticked : Map[String, Bool]
  mut write : Bool
}

///|
let xsharing : XSharing = { ticked: {}, write: false }

///|
/// As at the start (the package's reset).
fn xsharing_reset() -> Unit {
  xsharing.ticked.clear()
  xsharing.write = false
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
  xsharing.write = flag(share, "write")
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
    "write": Json::boolean(xsharing.write),
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
      let set = fn(now : Bool) {
        if now {
          xsharing.ticked[ws] = true
        } else {
          xsharing.ticked.remove(ws)
        }
      }
      // (the row a label round its box: pressed anywhere, ticked or not)
      let id = c.id("xshare/row/" + ws)
      c.cursor(id, Hand)
      let mut ticked = false
      c.box(style=xshare_row_box, id~, fn() {
        let now = @kit.checkbox(c, "xshare/" + ws, if on { On } else { Off }, label=name).value
        if (now == On) != on {
          ticked = true
          set(now == On)
        }
        c.text(name, style=xshare_row_title) |> ignore
      })
      |> ignore
      if !ticked && c.clicked(id) {
        set(!on)
      }
    }
  })
  |> ignore
  c.box(style=xshare_write, fn() {
    xsharing.write = @sf.switch_row(
      c,
      "xshare/write",
      @sf.t("web-pages.chat.xshare.write"),
      xsharing.write,
      note=@sf.t("web-pages.chat.xshare.writeNote"),
      disabled=xsharing.ticked.is_empty(),
    )
  })
  |> ignore
}

///|
/// The workspaces (shareList: out past the panel's words by a row's room, 12, its rows as wide), 2 apart; a row (a
/// list's row, pages.css.ts listRow): 52 high at least, 12 by 10 in, its box 12 before its name, a row's corner, the
/// hover grey pointed at.
let xshare_list_out : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let xshare_list : @ui.Style = @sf.outset(xshare_list_out).then(@ui.css("gap=S0_5"))

///|
// kept across runs: a value (no field of it changes)
let xshare_row_box : @ui.Style = @ui.css("row w=Full px=S3 py=S2_5 gap=S3 align=ACenter hovered{bg=Hover}").then(
  @ui.style(min_h=Fixed(xshare_row_least), radius=@sf.row_radius),
)

///|
let xshare_row_least : Double = 52.0

///|
// kept across runs: a value (no field of it changes)
let xshare_row_title : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, weight=Medium, color=Fg, wrap=false)

///|
/// The write switch, 8 under the workspaces (shareWrite).
// kept across runs: a value (no field of it changes)
let xshare_write : @ui.Style = @ui.css("w=Full pt=S2")
