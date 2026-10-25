// A chat shared with the viewer's other workspaces, as its sheet lists it (docs/chat-share.md; web mobile/Chat.tsx
// ShareRow): its row says where it is shared, under way a spinner there; for those who may (its starter, an owner or
// admin) a tap opens what changes it (sfpages' xshare.mbt, one on every screen).

///|
/// The row's name (14, the ink, whole on one line).
// kept across runs: a value (no field of it changes)
let xshare_name : @ui.TextStyle = @ui.text_style(size=Base, color=Fg, wrap=false)

///|
/// Where it is shared, at the row's end (13, muted, cut short rather than wrapped).
// kept across runs: a value (no field of it changes)
let xshare_where : @ui.TextStyle = @sf.secondary.then(@sf.one_line)

///|
/// What takes the row's room after its name: where it is shared, at its end, whole or not at all.
// kept across runs: a value (no field of it changes)
let xshare_where_box : @ui.Style = @ui.css("row w=Full justify=JEnd")

///|
let xshare_drop_where : Int = 1

///|
/// The chat's xsharing in its sheet (ChatInfo.kt ShareRow).
fn xshare_row(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double?, share : Json?) -> Unit {
  let t = @sf.theme()
  let session = text(share, "session")
  let key = @sfpages.xshare_key(r.station, session)
  let busy = doing(key)
  let failed = failed_lately(c, key)
  let may = flag(share, "may")
  if info_row(c, if may && !busy { "info/xshare" } else { "" }, fn() {
      @sf.icon(c, "users", size=16.0, color=t.p.text) |> ignore
      c.text(tr("web-pages.chat.xshare"), style=xshare_name) |> ignore
      // (short of room, where it is shared left out whole, its sheet saying it)
      c.box(style=xshare_where_box, fn() {
        c.box(drop=xshare_drop_where, fn() { c.text(text(share, "text"), style=xshare_where) |> ignore }) |> ignore
      })
      |> ignore
      if busy || failed {
        @settings.doing_mark(c, busy, if failed { Some("") } else { None })
      } else if may {
        chevron(c)
      }
    }) {
    // (the chat's sheet put down, what changes it up in its place)
    close_sheet(c)
    @sfpages.open_xshare(src, r, thread, from=Unanchored)
  }
}

