// A chat shared with the viewer's other workspaces (docs/chat-share.md; ember apps/android chat/screens/ChatInfo.kt
// ShareRow, openShare; web mobile/Chat.tsx ShareRow): its row in the chat's sheet says where it is shared, under way a
// spinner there; for those who may (its starter, an owner or admin) a tap opens the sheet that changes it: the other
// workspaces to tick, whether their agents may send in it, 完成 (`chat.xshare`), the sheet gone at once.

///|
/// The xsharing sheet's state: the chat it is for, the workspaces ticked, whether their agents may send.
priv struct XSharing {
  mut of : String
  ticked : Map[String, Bool]
  mut write : Bool
}

///|
let xsharing : XSharing = { of: "", ticked: {}, write: false }

///|
/// As at the start (tests).
fn xsharing_reset() -> Unit {
  xsharing.of = ""
  xsharing.ticked.clear()
  xsharing.write = false
}

///|
/// What is under way while the xsharing is changed (its row's spinner).
fn xshare_key(station : String, session : String) -> String {
  "xshare/" + station + "/" + session
}

///|
/// The row's name (14, the ink, whole on one line).
// kept across runs: a value (no field of it changes)
let xshare_name : @ui.TextStyle = @ui.text_style(size=Base, color=Fg, wrap=false)

///|
/// Where it is shared, at the row's end (13, muted, cut short rather than wrapped).
// kept across runs: a value (no field of it changes)
let xshare_where : @ui.TextStyle = @sf.secondary.then(@sf.one_line)

///|
/// What takes the row's room after its name: where it is shared, at its end.
// kept across runs: a value (no field of it changes)
let xshare_where_box : @ui.Style = @ui.css("w=Full align=AEnd")

///|
/// The chat's xsharing in its sheet (ChatInfo.kt ShareRow).
fn xshare_row(c : @ui.Ctx, r : ChatRef, thread : Double?, share : Json?) -> Unit {
  let t = @sf.theme()
  let session = text(share, "session")
  let key = xshare_key(r.station, session)
  let busy = doing(key)
  let failed = failed_lately(c, key)
  let may = flag(share, "may")
  if info_row(c, if may && !busy { "info/xshare" } else { "" }, fn() {
      @sf.icon(c, "users", size=16.0, color=t.p.text) |> ignore
      c.text(tr("web-pages.chat.xshare"), style=xshare_name) |> ignore
      c.box(style=xshare_where_box, fn() { c.text(text(share, "text"), style=xshare_where) |> ignore }) |> ignore
      if busy || failed {
        @settings.doing_mark(c, busy, if failed { Some("") } else { None })
      } else if may {
        chevron(c)
      }
    }) {
    open_xshare(c, r, thread, share)
  }
}

///|
/// Opens the sheet that changes where the chat is shared, ticked as it is shared now.
fn open_xshare(c : @ui.Ctx, r : ChatRef, thread : Double?, share : Json?) -> Unit {
  xsharing_reset()
  xsharing.of = xshare_key(r.station, text(share, "session"))
  for p in items(share, "places") {
    if flag(Some(p), "on") {
      xsharing.ticked[text(Some(p), "workspace")] = true
    }
  }
  xsharing.write = flag(share, "write")
  open_sheet(c, XShare(r, thread))
}

///|
/// Its words 20 in from the sheet's sides, a little room over and under.
// kept across runs: a value (no field of it changes)
let xshare_lead : @ui.Style = @ui.css("w=Full px=S5 py=S1_5")

///|
/// The switch's row on its own ground, 20 in from the sheet's sides (12 above it, 16 under).
// kept across runs: a value (no field of it changes)
let xshare_write_room : @ui.Style = @ui.css("w=Full pl=S5 pr=S5 pt=S3 pb=S4")

///|
/// Whether their agents may send: a row on the ink at 5%, 14 round, its words and the switch.
// kept across runs: a value (no field of it changes)
let xshare_write : @ui.Style = @ui.css("row w=Full px=S3_5 py=S2_5 gap=S3 radius=Xl1_5 bg=A(Fg,O5) align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let xshare_write_off : @ui.Style = xshare_write.then(@ui.css("opacity=O50"))

///|
// kept across runs: a value (no field of it changes)
let xshare_write_title : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Fg)

///|
/// 完成 at the sheet's end, 20 in, 24 over its foot.
// kept across runs: a value (no field of it changes)
let xshare_done : @ui.Style = @ui.css("row w=Full px=S5 pb=S6 justify=JEnd")

///|
/// Which of the viewer's other workspaces the chat is shared with, ticked, and whether their agents may send: done,
/// the sheet goes at once and the station is told (ChatInfo.kt openShare).
fn xshare_sheet(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double?) -> Unit {
  let chat = (src.topic)("chat", chat_params(r)).value
  let share = field(chat, "xshare")
  let session = text(share, "session")
  sheet_frame(c, "xshare", c.height * 0.6, fit=true, fn() {
    sheet_head(c, tr("web-pages.chat.xshare"))
    c.box(style=xshare_lead, fn() {
      c.text(tr("web-pages.chat.xshare.lead"), style=@sf.secondary.then(@sf.full_words)) |> ignore
    })
    |> ignore
    for p in items(share, "places") {
      let ws = text(Some(p), "workspace")
      if @settings.pick_row(c, "xshare/" + ws, text(Some(p), "name"), checked=xsharing.ticked.contains(ws)) {
        if xsharing.ticked.contains(ws) {
          xsharing.ticked.remove(ws)
        } else {
          xsharing.ticked[ws] = true
        }
      }
    }
    let none = xsharing.ticked.is_empty()
    c.box(style=xshare_write_room, fn() {
      let id = c.id("xshare/write")
      if !none && c.clicked(id) {
        xsharing.write = !xsharing.write
      }
      c.box(style=if none { xshare_write_off } else { xshare_write }, id=if none { 0 } else { id }, fn() {
        c.box(style=@sf.full_width, fn() {
          c.text(tr("web-pages.chat.xshare.write"), style=xshare_write_title) |> ignore
          c.text(tr("web-pages.chat.xshare.writeNote"), style=@sf.secondary) |> ignore
        })
        |> ignore
        @settings.switch(c, "xshare/write", xsharing.write && !none)
      })
      |> ignore
    })
    |> ignore
    c.box(style=xshare_done, fn() {
      if @settings.button(c, "xshare/done", tr("common.done"), true) {
        close_sheet(c)
        // in the order the sheet lists them
        let to = items(share, "places")
          .map(fn(p) { text(Some(p), "workspace") })
          .filter(fn(ws) { xsharing.ticked.contains(ws) })
        let p : Map[String, Json] = {
          "station": Json::string(r.station),
          "session": Json::string(session),
          "to": Json::array(to.map(Json::string(_))),
          "write": Json::boolean(xsharing.write && !none),
        }
        match thread {
          Some(th) => p["thread"] = Json::number(th)
          None => ()
        }
        act(src, tr("web-pages.chat.xshare.verb"), xshare_key(r.station, session), "chat.xshare", Json::object(p))
      }
    })
    |> ignore
  })
}
