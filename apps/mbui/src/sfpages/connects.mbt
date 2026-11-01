// 连接, one page in every frame (web/src/pages/Connects.tsx ConnectList, Connects.css.ts; the narrow app's
// mobile/Connects.tsx), laid out by its width (page_look.mbt): at its head its title with what a connect is and 添加连接;
// under it the filter (全部 or 我的); the Slack apps made and not connected yet, each to go on with; then the connects,
// each its bot's picture, its name and its Slack workspace, how it runs, its station, who added it, how it is and its
// dot (wide: one list, each with its station's tag; narrow: a card a station, under its name). With none at all yet,
// the page is about adding the first (a profile first where no station has one). `only`: one station's (its page's
// 连接). Adding is the new connect's dialog (new_connect.mbt); menus and asking first, the presenters.

///|
pub fn connects_page(c : @ui.Ctx, src : Source, core : Core, here : Here, frame : PageFrame, only : String) -> Unit {
  let look = look_of(c)
  let mine = connects_mine.val
  let topic = (core.topic)("connects", { "scope": str(here.workspace), "mine": Json::boolean(mine) })
  let st = @settings.stations_of(core, here)
  let stations = match st.value {
    Some(Array(a)) => if only == "" { a } else { a.filter(fn(x) { text(Some(x), "station") == only }) }
    _ => []
  }
  let view = topic.value
  let shown = items(view, "items").filter(fn(x) { only == "" || text(Some(x), "station") == only })
  let wait = field(view, "wait")
  let loading = wait is None || flag(wait, "reading")
  // the Slack apps the viewer made that no connect has taken yet, each on its station
  let waiting : Array[(Json, Json)] = []
  for s in stations {
    for app in items(field(Some(s), "overview"), "slackApps") {
      waiting.push((app, s))
    }
  }
  // none at all yet (not only none of the viewer's): the page is about adding the first
  let first = !loading && topic.error is None && shown.length() == 0 && !mine && waiting.length() == 0
  // a connect runs a profile's model: with none on any station (each read), the first step is a profile
  let no_profile = stations.length() > 0 &&
    stations.iter().all(fn(s) {
      field(Some(s), "overview") is Some(Object(_)) && items(field(Some(s), "overview"), "profiles").length() == 0
    })
  // where one is added: the stations online
  let targets = stations.filter(fn(s) { flag(Some(s), "online") })
  let station_of = fn(address : String) -> Json? {
    stations.iter().find_first(fn(s) { text(Some(s), "station") == address })
  }
  let gutter = fn(f : () -> Unit) { cn_gutter(c, look, f) }
  let blocks : Array[() -> Unit] = []
  if first && no_profile {
    blocks.push(fn() {
      gutter(fn() {
        @sf.first_one(c, @sf.t("web-pages.connects.profileFirst"), lead=@sf.t("web-pages.connects.profileFirstLead"), fn() {
          if @sf.button(c, @sf.t("web-pages.connects.goAddProfile"), key="connects-go-profiles", tone=Primary) {
            (core.push)(Profiles(""))
          }
        })
      })
    })
  } else if first {
    blocks.push(fn() {
      gutter(fn() {
        @sf.first_one(c, @sf.t("web-pages.connects.addFirst"), lead=@sf.t("web-pages.connects.addFirstLead"), fn() {
          match targets.length() {
            0 =>
              c.text(@sf.t(if stations.length() > 0 { "web-pages.connects.noOnline" } else { "web-pages.connects.stationFirst" }), style=cn_note)
              |> ignore
            _ => cn_add(c, src, core, here, targets, @sf.t("web-pages.connects.add"), "connects-add-first", true)
          }
        })
      })
    })
  } else {
    blocks.push(fn() {
      c.box(style=if look == Wide { cn_filter_room } else { cn_filter_room_narrow }, fn() {
        mine_filter(c, "connects-filter", "connects", mine, fn(v) { connects_mine.val = v })
      })
      |> ignore
    })
  }
  if waiting.length() > 0 {
    blocks.push(fn() {
      match look {
        Wide => {
          c.box(style=cn_quiet_room, fn() { c.text(@sf.t("web-pages.connects.waiting"), style=cn_quiet) |> ignore }) |> ignore
          c.box(style=cn_list_room, fn() {
            c.box(style=@sf.desk_list, fn() {
              for w in waiting {
                cn_waiting_app(c, src, core, here, look, w.0, w.1)
              }
            })
            |> ignore
          })
          |> ignore
        }
        Narrow => {
          @sf.heading(c, @sf.t("web-pages.connects.waiting"))
          @sf.group(c, fn() {
            for w in waiting {
              cn_waiting_app(c, src, core, here, look, w.0, w.1)
            }
          })
        }
      }
    })
  }
  if !first {
    if shown.length() == 0 && topic.error is None && (loading || items(wait, "failing").length() > 0) {
      blocks.push(fn() { gutter(fn() { block_waiting(c, fn() { connects_sample(c, core, look, only) }, wait~) }) })
    } else if shown.length() == 0 {
      blocks.push(fn() {
        c.box(style=if look == Wide { cn_none_room } else { cn_filter_room_narrow }, fn() {
          match topic.error {
            Some(e) => c.text(error_text(e), style=cn_error) |> ignore
            None => c.text(@sf.t(if mine { "web-pages.connects.noneMine" } else { "web-pages.connects.none" }), style=cn_note) |> ignore
          }
        })
        |> ignore
      })
    } else {
      blocks.append(connects_list(c, core, look, shown, only, station_of))
      // what the list still waits on: a row's shape for a station not read yet, each failure said
      if flag(wait, "reading") || items(wait, "failing").length() > 0 {
        blocks.push(fn() { gutter(fn() { @sf.wait_more(c, Some({ reading: flag(wait, "reading"), text: "", failing: failing_of(wait) }), fn() {
            connects_sample(c, core, look, only, count=1)
          }) }) })
      }
    }
  }
  let add = if targets.length() > 0 && !first {
    // (its primary action named as what it adds; narrow, the title's ＋)
    Some(fn() { cn_add(c, src, core, here, targets, @sf.t("android-misc.bar.action.connects"), "add-connect", false, round=look == Narrow) })
  } else {
    None
  }
  @sf.page(c, on_back=core.pop, frame~, "connects/" + only + "/" + mine.to_string(),
    @sf.t("android-settings.connects.title"),
    about=@sf.t("web-pages.connects.about", args=[("name", "still.fail")]),
    // (a place's top page under a phone's bar: its ＋ the bar's notch, connects_add)
    actions?=if frame.named { None } else { add },
    blocks,
  )
}

///|
/// The connects (`shown`, of station `only`, else every station's): wide, a list of them; narrow, each station's under
/// its name, as a card (one offline said so).
fn connects_list(
  c : @ui.Ctx,
  core : Core,
  look : Look,
  shown : Array[Json],
  only : String,
  station_of : (String) -> Json?,
) -> Array[() -> Unit] {
  let blocks : Array[() -> Unit] = []
  match look {
    Wide =>
      blocks.push(fn() {
        c.box(style=cn_list_room, fn() {
          c.box(style=@sf.desk_list, fn() {
            for x in shown {
              let xv = Some(x)
              let address = text(xv, "station")
              cn_row(c, core, look, address, text(xv, "stationName"), station_of(address), field(xv, "connect"))
            }
          })
          |> ignore
        })
        |> ignore
      })
    // (narrow: each station's under its name, as a card; one offline said so)
    Narrow => {
      // (the stations in the order their connects come, each once)
      let addresses : Array[String] = []
      for x in shown {
        let a = text(Some(x), "station")
        if !addresses.contains(a) {
          addresses.push(a)
        }
      }
      for address in addresses {
        let here_list = shown.filter(fn(x) { text(Some(x), "station") == address })
        let sv = station_of(address)
        let name = text(Some(here_list[0]), "stationName")
        blocks.push(fn() {
          if only == "" {
            @sf.heading(c, if sv is None || flag(sv, "online") { name } else { @sf.t("android-settings.connects.offline", args=[("name", name)]) },
            )
          }
          // (each connect by its id: one made or taken out comes and goes where it is, @sf.group_rows)
          @sf.group(c, fn() {
            @sf.group_rows(
              c,
              "connects/" + address,
              here_list.mapi(fn(i, x) {
                let cn = field(Some(x), "connect")
                let id = if text(cn, "id") != "" { text(cn, "id") } else { "#" + i.to_string() }
                (id, fn() { cn_row(c, core, look, address, name, sv, cn) })
              }),
            )
          })
        })
      }
    }
  }
  blocks
}

///|
/// The connects to come while they are read (the library's Waiting, in its bones): `count` made-up ones on a station,
/// as connects_list draws them.
fn connects_sample(c : @ui.Ctx, core : Core, look : Look, only : String, count? : Int = 3) -> Unit {
  let name = @sf.sample_words(4)
  let shown = [8, 6, 10][:count].to_array().map(fn(n) {
    Json::object({
      "station": "sample",
      "stationName": Json::string(name),
      "connect": {
        "id": Json::string("sample" + n.to_string()),
        "name": Json::string(@sf.sample_words(n)),
        "modeText": Json::string(@sf.sample_words(4)),
        "runtimeText": Json::string(@sf.sample_words(3)),
      },
    })
  })
  for b in connects_list(c, core.quiet(), look, shown, only, fn(_) { None }) {
    b()
  }
}

///|
/// 连接's primary action where the frame holds it (a phone's bar's notch): a connect added on the station online, the
/// only one at once, else one picked first; None while none is online.
pub fn connects_add(src : Source, core : Core, here : Here) -> ((@sf.Beside) -> Unit)? {
  let online = match @settings.stations_of(core, here).value {
    Some(Array(a)) => a.filter(fn(s) { flag(Some(s), "online") })
    _ => []
  }
  if online.length() == 0 {
    return None
  }
  Some(fn(from) {
    if online.length() == 1 {
      new_connect_dialog(src, core, here, text(Some(online[0]), "station"))
      return
    }
    let items : Array[@sf.MenuItem?] = online.map(fn(s) {
      let station = text(Some(s), "station")
      Some(@sf.menu_item_of(text(Some(s), "name"), fn() { new_connect_dialog(src, core, here, station) }))
    })
    @sf.menu(items, from~, title=@sf.t("web-pages.connects.whichStation"))
  })
}

///|
/// What sits on the page's ground as wide as its column, narrow 12 from its sides (as its cards are).
fn cn_gutter(c : @ui.Ctx, look : Look, body : () -> Unit) -> Unit {
  match look {
    Wide => body()
    Narrow => c.box(style=@sf.pg_card_room, body) |> ignore
  }
}

///|
/// Adding one (Connects.tsx add): on the one station online at once, else on one picked from a menu under it (which
/// station?), in the new connect's dialog. `primary`: the first one's (a solid button); `round`: the narrow title's ＋.
fn cn_add(
  c : @ui.Ctx,
  src : Source,
  core : Core,
  here : Here,
  targets : Array[Json],
  label : String,
  key : String,
  primary : Bool,
  round? : Bool = false,
) -> Unit {
  let pressed = if round {
    @sf.icon_button(c, "plus", key~, round=true, label~)
  } else {
    @sf.button(c, label, key~, tone=if primary { Primary } else { Plain }, icon="plus")
  }
  if !pressed {
    return
  }
  if targets.length() == 1 {
    new_connect_dialog(src, core, here, text(Some(targets[0]), "station"))
    return
  }
  let items : Array[@sf.MenuItem?] = []
  for s in targets {
    let station = text(Some(s), "station")
    items.push(Some(@sf.menu_item_of(text(Some(s), "name"), fn() { new_connect_dialog(src, core, here, station) })))
  }
  @sf.menu(items, from=Of(c.id(key)), title=@sf.t("web-pages.connects.whichStation"), along=if primary { Middle } else { End })
}

///|
/// A connect in the list (its row's Link): its picture, its name with its Slack workspace after it, how it runs; at
/// its end (wide) its station's tag, who added it, how it is (being deleted: a ring), its dot (narrow: how it is and
/// its dot). Pressed, its page.
fn cn_row(c : @ui.Ctx, core : Core, look : Look, station : String, station_name : String, s : Json?, cv : Json?) -> Unit {
  let id = text(cv, "id")
  let bind = field(cv, "bind")
  let model = match opt_text(bind, "model") {
    Some(m) => " · " + opt_text(cv, "modelName").unwrap_or(m)
    None => ""
  }
  let how = text(cv, "modeText") + " · " + text(cv, "runtimeText") + model
  let on = [("station", station), ("id", id)]
  // its Slack workspace after its name (short of room, its name kept: its team leaves its line first), what it
  // connects to before it where its own picture leads the row (a platform's mark is said once on a row: where the row
  // leads with it, not again)
  let pictured = opt_text(cv, "botImage") is Some(_)
  let team = match opt_text(cv, "team") {
    Some(team) =>
      Some(fn() {
        c.box(style=cn_team, drop=cn_drop_team, fn() {
          if pictured {
            cn_kind(c, text(cv, "kind"), cn_team_icon)
          }
          c.text(team, style=cn_meta) |> ignore
        })
        |> ignore
      })
    None => None
  }
  if @sf.link_row(
      c,
      "connect/" + station + "/" + id,
      text(cv, "name"),
      note=how,
      note_cut=true,
      chevron=false,
      lead=fn() { cn_avatar(c, core, cv) },
      // (its own picture a face across the row's middle; what it connects to a mark by its first line)
      face=pictured,
      title_after?=team,
      tail=fn() {
        // (wide: where it runs and who made it, dropped before its name where the line has not the room)
        if look == Wide {
          c.box(style=cn_facts, drop=cn_drop_facts, fn() {
            cn_station_tag(c, station_name, s)
            cn_owner(c, core, station + "/" + id, field(cv, "createdBy"))
          })
          |> ignore
        }
        doing_mark(c, is_doing(core, ["connect.delete"], on), failed_of(core, ["connect.delete"], on))
        c.box(style=cn_narrow_state, fn() {
          @sf.status_dot(c, text(cv, "presence"))
          c.text(text(cv, "statusText"), style=cn_meta) |> ignore
        })
        |> ignore
      },
    ) {
    (core.push)(Connect(station, id))
  }
}

///|
/// A connect as its people see it (ui.tsx ConnectAvatar, 28): its bot's picture; its kind's mark till that is said.
fn cn_avatar(c : @ui.Ctx, core : Core, cv : Json?) -> Unit {
  match opt_text(cv, "botImage") {
    Some(image) => avatar(c, core, text(cv, "id"), text(cv, "name"), cn_avatar_size, picture=image)
    None => c.box(style=cn_kind_box, fn() { cn_kind(c, text(cv, "kind"), cn_kind_size) }) |> ignore
  }
}

///|
/// What a connect connects to (ConnectKindIcon): Slack's mark or Feishu's.
fn cn_kind(c : @ui.Ctx, kind : String, size : Double) -> Unit {
  if kind == "feishu" {
    @sf.feishu_mark(c, size) |> ignore
  } else {
    @sf.slack_mark(c, size) |> ignore
  }
}

///|
/// Its station (cloud.css.ts stationTag: 1 by 8 in, a corner of 6 on the neutral ground, the meta's 12 in 500 muted;
/// its mark 11 before its name).
fn cn_station_tag(c : @ui.Ctx, name : String, s : Json?) -> Unit {
  let t = @sf.theme()
  c.box(style=cn_tag, fn() {
    let emoji = text(s, "emoji")
    let icon = text(s, "icon")
    if @sf.has_station_mark(emoji, icon) {
      @sf.station_mark(c, emoji, icon, cn_team_icon, t.p.muted)
    }
    c.text(name, style=cn_tag_words) |> ignore
  })
  |> ignore
}

///|
/// Who added it (components.tsx OwnerLabel): their picture 16 and name (theirs said as the viewer's), 6 apart, the
/// meta's 12, who they are by their id over it while it is pointed at (but this machine's own); none said, so in the
/// subtle ink. `key`: the connect's.
fn cn_owner(c : @ui.Ctx, core : Core, key : String, by : Json?) -> Unit {
  let shown = field(by, "shown")
  if !(shown is Some(Object(_))) {
    c.text(@sf.t("web-main.owner.none"), style=cn_owner_none) |> ignore
    return
  }
  let name = text(shown, "name")
  let owner = text(by, "id")
  let id = c.id("connect-owner/" + key)
  c.box(style=cn_owner_box, id~, taps=false, points=true, fn() {
    avatar(c, core, owner, name, cn_owner_size, picture=text(shown, "picture"))
    c.text(if flag(shown, "mine") { @sf.t("web-main.owner.you", args=[("name", name)]) } else { name }, style=cn_owner_words)
    |> ignore
  })
  |> ignore
  @sf.tip(c, "connect-owner/" + key + "/tip", id, if owner == "local" { "" } else { owner })
}

///|
/// A Slack app made and not connected yet (WaitingApp): Slack's mark, its name and workspace, where it stands; its
/// station's tag (wide); 继续 while its station is online (else that it is not), dropped from under ⋯ (asked first).
fn cn_waiting_app(c : @ui.Ctx, src : Source, core : Core, here : Here, look : Look, a : Json, s : Json) -> Unit {
  let av = Some(a)
  let sv = Some(s)
  let station = text(sv, "station")
  let online = flag(sv, "online")
  let app_id = text(av, "appId")
  let where_ = if flag(av, "installed") {
    @sf.t("web-pages.connects.installedNeedsToken", args=[("team", first_text(av, ["installedTeam", "team"], @sf.t("android-settings.flow.team")))])
  } else if has(av, "install") {
    @sf.t("web-pages.connects.notInstalled")
  } else {
    @sf.t("web-pages.connects.needsToken")
  }
  let on = [("station", station), ("appId", app_id)]
  let dropping = is_doing(core, ["slack.dropApp"], on)
  let drop = fn() {
    confirm(
      @sf.t("web-pages.settings.stations.removeConfirm", args=[("name", text(av, "name"))]),
      @sf.t("web-pages.connects.removeBody", args=[("name", "still.fail")]),
      @sf.t("android-settings.members.remove"),
      danger=true,
      fn() {
        @settings.act(
          core,
          @sf.t("android-settings.waiting.removeWhat"),
          "slack.dropApp",
          obj([("station", str(station)), ("appId", str(app_id))]),
          done=@sf.t("android-settings.members.removed"),
        )
      },
    )
  }
  // its Slack workspace after its name, no mark again (the row leads with Slack's: a platform's mark said once on a row)
  let team = match opt_text(av, "team") {
    Some(team) =>
      Some(fn() {
        c.box(style=cn_team, drop=cn_drop_team, fn() {
          c.text(team, style=cn_meta) |> ignore
        })
        |> ignore
      })
    None => None
  }
  @sf.link_row(
    c,
    "",
    text(av, "name"),
    note=where_,
    note_cut=true,
    goes=false,
    lead=fn() { c.box(style=cn_kind_box, fn() { @sf.slack_mark(c, cn_waiting_mark) |> ignore }) |> ignore },
    title_after?=team,
    tail=fn() {
      if look == Wide {
        c.box(style=cn_facts, drop=cn_drop_facts, fn() { cn_station_tag(c, text(sv, "name"), sv) }) |> ignore
      }
      if !online {
        c.text(@sf.t("web-pages.connects.stationOffline"), style=cn_meta) |> ignore
      }
      doing_mark(c, dropping, failed_of(core, ["slack.dropApp"], on))
    },
    control?=if online {
      Some(fn() {
        let go = match look {
          Wide => @sf.button(c, @sf.t("web-pages.connects.continue"), key="waiting-go/" + app_id)
          Narrow => tap_text(c, "waiting-go/" + app_id, @sf.t("web-pages.connects.continue"), color=@sf.link_ink())
        }
        if go {
          new_connect_dialog(src, core, here, station, resume=app_id)
        }
        // dropped from under ⋯ (its menu), asked again first; it stays in Slack
        if !dropping {
          let mid = c.id("waiting-more/" + app_id)
          if c.clicked(mid) {
            @sf.menu([Some(@sf.menu_item_of(@sf.t("web-pages.connects.removeHere"), drop, danger=true))], from=Of(mid), along=End)
          }
          let b = c.box(style=cn_more, id=mid, fn() {
            @sf.icon(c, "more", size=cn_more_icon, color=@sf.theme().p.muted) |> ignore
          })
          c.semantics(b, Button, id=mid, label=@sf.t("web-pages.connects.removeHere"))
        }
      })
    } else {
      None
    },
  )
  |> ignore
}

///|
/// The sizes: its picture 28, its kind's mark 17 in a 20 square (a waiting app's 18), the team's and the tag's
/// marks 11, the owner's picture 16, ⋯ 16.
let cn_avatar_size : Double = 28.0

///|
let cn_kind_size : Double = 17.0

///|
let cn_waiting_mark : Double = 18.0

///|
let cn_team_icon : Double = 11.0

///|
let cn_owner_size : Double = 16.0

///|
let cn_more_icon : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let cn_kind_box : @ui.Style = @ui.css("w=S5 h=S5 align=ACenter justify=JCenter")

///|
/// The filter, as wide as what it says, 8 further under the head than the head's own room, where the web's is
/// (pageHead: 28 under it), and 12 over the list; the waiting apps' title (sectionTitleQuiet: the meta's 12 in 500 muted, 6 under).
// kept across runs: a value (no field of it changes)
let cn_filter_room : @ui.Style = @ui.css("w=Full pt=S2 pb=S3 align=AStart")

///|
/// The lists at the column's edges, as the head and every other page's (@sf.desk_list: a list card).
// kept across runs: a value (no field of it changes)
let cn_list_room : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let cn_quiet_room : @ui.Style = @ui.css("w=Full pb=S1_5")

///|
// kept across runs: a value (no field of it changes)
let cn_quiet : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let cn_none_room : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let cn_error : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Danger, w=Full)

///|
// kept across runs: a value (no field of it changes)
let cn_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, w=Full)

///|
/// Its Slack workspace after its name (connectTeam: 8 after it, its mark 4 from its name, the meta's 12 muted).
// kept across runs: a value (no field of it changes)
let cn_team : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let cn_meta : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// Its team after its name, whole or not at all where its line has not the room.
let cn_drop_team : Int = 1

///|
/// What leaves a connect's row first, short of room: where it runs and who made it.
let cn_drop_facts : Int = 1

///|
/// Its station and who added it (connectFacts: 10 apart).
// kept across runs: a value (no field of it changes)
let cn_facts : @ui.Style = @ui.css("row gap=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let cn_tag : @ui.Style = @ui.css("row px=S2 py=SPx gap=S1 align=ACenter radius=Md bg=Neutral")

///|
// kept across runs: a value (no field of it changes)
let cn_tag_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let cn_owner_box : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let cn_owner_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let cn_owner_none : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, wrap=false)

///|
/// ⋯ (an icon button: 32, its corner 12).
// kept across runs: a value (no field of it changes)
let cn_more : @ui.Style = @ui.css("w=S8 h=S8 radius=Xl align=ACenter justify=JCenter hovered{bg=Hover}")


///|
/// Narrow: the filter in the page's room, 10 under; a row's line under its name (the secondary's, on one line);
/// how it is at its end, its dot before the words.
// kept across runs: a value (no field of it changes)
let cn_filter_room_narrow : @ui.Style = @ui.css("w=Full pb=S2_5 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let cn_narrow_state : @ui.Style = @ui.css("row gap=S1_25 align=ACenter")

///|
/// A list's filter on the wide page (components.tsx MineFilter, not compact; History.css.ts mineFilterBtn,
/// mineFilterWide): a 32 high button 8 in, the field's line round it, 12 over what it filters; its funnel 16 and what
/// it shows in the muted ink, the words' under the pointer or while open, never marked for what it shows;
/// pressed, its menu of choices under it (all or the viewer's, the shown checked), at its end. `of`: what it filters
/// (`connects`), as its words name it.
fn mine_filter(c : @ui.Ctx, key : String, of : String, mine : Bool, set : (Bool) -> Unit) -> Unit {
  let t = @sf.theme()
  let id = c.id(key)
  let open = mine_filter_open.get(key).unwrap_or(false)
  // (pressed: opened or closed as it is let go, as it is then)
  c.on_press(id, fn() { mine_filter_open[key] = !mine_filter_open.get(key).unwrap_or(false) })
  let named = if mine { @sf.t("web-main.filter." + of + ".mine") } else { @sf.t("web-main.filter.all") }
  let lit = c.lit(id) || open
  let ink = if lit { t.p.text } else { t.p.muted }
  let b = c.box(style=mine_filter_box, selected=open, id~, fn() {
    @sf.icon(c, "filter", size=mine_filter_icon, color=ink) |> ignore
    c.text(named, style=if lit { mine_filter_lit_words } else { mine_filter_words })
    |> ignore
  })
  c.semantics(b, Button, id~, label=@sf.t("web-main.filter." + of + ".named", args=[("named", named)]), expanded=open)
  let entries = [
    @kit.menu_radio("all", !mine, label=@sf.t("web-main.filter." + of + ".all")),
    @kit.menu_radio("mine", mine, label=@sf.t("web-main.filter." + of + ".mine")),
  ]
  // (dismissed by the hand, Escape or a press outside it and its button: closed at that moment; closed as one is chosen)
  let menu : Ref[@kit.Menu?] = Ref(None)
  c.with_dismissed(fn(_) { mine_filter_open[key] = false }, fn() {
    menu.val = Some(@sf.dropdown(c, key + "/menu", open, id, entries, {}, mine_filter_menu_w))
  })
  let m = menu.val.unwrap()
  match m.chosen {
    Some(v) => {
      mine_filter_open[key] = false
      if (v == "mine") != mine {
        set(v == "mine")
      }
    }
    None => ()
  }
}

///|
/// Which filter's menu is open, by its key.
// kept across runs: said again by each press; reset empties it
let mine_filter_open : Map[String, Bool] = {}

///|
/// Whether filter `key`'s menu is open (tests).
pub fn mine_filter_shown(key : String) -> Bool {
  mine_filter_open.get(key).unwrap_or(false)
}

///|
let mine_filter_icon : Double = 16.0

///|
/// A menu of choices (controls.css.ts chooserMenu: 220 wide at least).
let mine_filter_menu_w : Double = 220.0

///|
// kept across runs: a value (no field of it changes)
let mine_filter_box : @ui.Style = @ui.css(
  #|row h=S8 min_w=S8 px=S2 gap=S1_5 align=ACenter radius=Xl border=B1 border_color=Line hovered{bg=Hover}
  #|selected{bg=Hover}
)

///|
// kept across runs: a value (no field of it changes)
let mine_filter_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let mine_filter_lit_words : @ui.TextStyle = mine_filter_words.then(@ui.text_style(color=Fg))
