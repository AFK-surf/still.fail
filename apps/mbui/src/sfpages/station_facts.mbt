// What a station's row says of it wherever the workspace's stations are listed (StationsNav.tsx StationRow): the
// stations' sidebar (sfdesk places.mbt station_side_row) and where a new chat runs (new_chat.mbt station_rows), the
// same in both. The row itself (its mark, its name, its ground) is the list's or the panel's.

///|
/// At the end of its name's line: up or away (the rail's dot), then its agents at work (in the accent) or, away, when
/// it was last seen.
pub fn station_state(c : @ui.Ctx, s : Json?) -> Unit {
  let online = flag(s, "online")
  let running = number(field(field(s, "overview"), "counts"), "running")
  c.box(style=station_state_box, fn() {
    c.box(style=if online { station_dot_on } else { station_dot_off }, fn() {  }) |> ignore
    if !online {
      c.text(text(s, "summary"), style=station_words()) |> ignore
    } else if running > 0.0 {
      let busy = @sf.t("web-pages.stations.page.runningShort", args=[("n", running.to_int().to_string())])
      c.text(busy, style=station_words().then(station_busy)) |> ignore
    }
  })
  |> ignore
}

///|
/// Under its name while it is up: a line of what is left of its CPU, memory and disk in small boxes (never onto
/// another: as short as the line needs, @sf.meter_chips), and a line of how this device reaches it (the core's
/// `stationNet`, there only while this device holds a connection of its own to it: 未连接 while it does not). Each
/// line kept whatever comes and goes in it, so a row is as high whichever station is open and whether this device is
/// connected to it.
pub fn station_figures(c : @ui.Ctx, src : Source, s : Json?) -> Unit {
  if !flag(s, "online") {
    return
  }
  let net = (src.topic)("stationNet", { "station": Json::string(text(s, "station")) }).value
  @sf.list_row_line(c, fn() { @sf.meter_chips(c, items(field(s, "host"), "meters"), brief=true) })
  @sf.list_row_line(c, fn() {
    let words = match net {
      Some(Object(_)) =>
        match text(field(net, "rtt"), "text") {
          "" => text(net, "path")
          rtt => text(net, "path") + " · " + rtt
        }
      _ => @sf.t("web-pages.stations.netNone")
    }
    c.text(words, style=station_words()) |> ignore
  })
}

///|
/// What it says (SidebarList.css.ts line, end): a chat's second line's words (the theme's chats' list's), as long as
/// they are.
fn station_words() -> @ui.TextStyle {
  @sf.theme().chat_list.last.then(station_words_hug)
}

///|
// kept across runs: a value (no field of it changes)
let station_words_hug : @ui.TextStyle = @ui.text_style(w=Hug)

///|
/// Its agents at work (StationPage.css.ts busy): the accent's words.
// kept across runs: a value (no field of it changes)
let station_busy : @ui.TextStyle = @ui.text_style(color=AccentText)

///|
/// The dot and what follows it (SidebarList.css.ts end), 5 apart.
// kept across runs: a value (no field of it changes)
let station_state_box : @ui.Style = @ui.css("row gap=S1_25 align=ACenter")

///|
/// Up or away: the rail's dot (railCss.dot: 6).
// kept across runs: a value (no field of it changes)
let station_dot_on : @ui.Style = @ui.css("w=S1_5 h=S1_5 radius=Full bg=Positive")

///|
// kept across runs: a value (no field of it changes)
let station_dot_off : @ui.Style = @ui.css("w=S1_5 h=S1_5 radius=Full bg=Faint")
