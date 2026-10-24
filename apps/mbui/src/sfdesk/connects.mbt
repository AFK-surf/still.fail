// Connects in the wide frame, as the web's (ember web/src/pages/Connects.tsx ConnectList; Connects.css.ts): at its
// head its title with what a connect is beside it (a mark that says it on hover) and 添加连接; under it the filter
// (全部 or 我的); the Slack apps made and not connected yet, quietly titled, each to go on with; then every station's
// connects in one list, each its bot's picture, its name and its Slack workspace, how it runs, and at its end its
// station's tag, who added it, how it is and its dot. With none at all yet, the page is about adding the first (a
// profile first where no station has one). The phone's page, each station's under its name, is connects.mbt's.

///|
fn connects_page(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let mine = connects_mine.val
  let topic = (core.topic)("connects", { "scope": str(here.workspace), "mine": Json::boolean(mine) })
  let st = @settings.stations_of(core, here)
  let stations = match st.value {
    Some(Array(a)) => a
    _ => []
  }
  let view = topic.value
  let shown = items(view, "items")
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
  let add = place_action(core, here, "connects")
  let station_of = fn(address : String) -> Json? {
    stations.iter().find_first(fn(s) { text(Some(s), "station") == address })
  }
  desk_place(
    c,
    core,
    @sf.t("android-settings.connects.title"),
    about=@sf.t("web-pages.connects.about", args=[("name", "still.fail")]),
    actions?=match add {
      // (its primary action a pill named as what it adds)
      Some(run) if !first =>
        Some(fn() {
          if @sf.button(c, @sf.t("android-misc.bar.action.connects"), key="add-connect", icon="plus") {
            run()
          }
        })
      _ => None
    },
    fn() {
      let blocks : Array[() -> Unit] = []
      if first && no_profile {
        blocks.push(fn() {
          @sf.first_one(c, @sf.t("web-pages.connects.profileFirst"), lead=@sf.t("web-pages.connects.profileFirstLead"), fn() {
            if @sf.button(c, @sf.t("web-pages.connects.goAddProfile"), key="connects-go-profiles", tone=Primary) {
              (core.push)(Profiles(""))
            }
          })
        })
      } else if first {
        blocks.push(fn() {
          @sf.first_one(c, @sf.t("web-pages.connects.addFirst"), lead=@sf.t("web-pages.connects.addFirstLead"), fn() {
            match add {
              Some(run) =>
                if @sf.button(c, @sf.t("web-pages.connects.add"), key="connects-add-first", tone=Primary, icon="plus") {
                  run()
                }
              None =>
                c.text(
                  @sf.t(
                    if stations.length() > 0 {
                      "web-pages.connects.noOnline"
                    } else {
                      "web-pages.connects.stationFirst"
                    },
                  ),
                  style=cn_note,
                )
                |> ignore
            }
          })
        })
      } else {
        blocks.push(fn() {
          c.box(style=cn_filter_room, fn() {
            mine_filter(c, "connects-filter", "connects", mine, fn(v) { connects_mine.val = v })
          })
          |> ignore
        })
      }
      if waiting.length() > 0 {
        blocks.push(fn() {
          c.box(style=cn_quiet_room, fn() { c.text(@sf.t("web-pages.connects.waiting"), style=cn_quiet) |> ignore })
          |> ignore
          c.box(style=cn_list_room, fn() {
            c.box(style=desk_list, fn() {
              for w in waiting {
                cn_waiting_app(c, core, w.0, w.1)
              }
            })
            |> ignore
          })
          |> ignore
        })
      }
      if !first {
        if shown.length() == 0 && topic.error is None && (loading || items(wait, "failing").length() > 0) {
          blocks.push(fn() { desk_waiting_rows(c, wait) })
        } else if shown.length() == 0 {
          blocks.push(fn() {
            c.box(style=cn_none_room, fn() {
              match topic.error {
                Some(e) => c.text(error_text(e), style=cn_error) |> ignore
                None =>
                  c.text(@sf.t(if mine { "web-pages.connects.noneMine" } else { "web-pages.connects.none" }), style=cn_note)
                  |> ignore
              }
            })
            |> ignore
          })
        } else {
          blocks.push(fn() {
            c.box(style=cn_list_room, fn() {
              c.box(style=desk_list, fn() {
                for x in shown {
                  let xv = Some(x)
                  let address = text(xv, "station")
                  cn_row(c, core, address, text(xv, "stationName"), station_of(address), field(xv, "connect"))
                }
              })
              |> ignore
            })
            |> ignore
          })
          // what the list still waits on: a row's shape for a station not read yet, each failure said
          if flag(wait, "reading") || items(wait, "failing").length() > 0 {
            blocks.push(fn() { desk_waiting_rows(c, wait, count=1) })
          }
        }
      }
      desk_lanes(c, "connects-wide/" + mine.to_string(), blocks)
    },
  )
}

///|
/// A connect in the list (its row's Link): its picture, its name with its Slack workspace after it, how it runs; at
/// its end its station's tag, who added it, how it is (being deleted: a ring), its dot. Pressed, its page.
fn cn_row(c : @ui.Ctx, core : Core, station : String, station_name : String, s : Json?, cv : Json?) -> Unit {
  let id = text(cv, "id")
  let rid = c.id("connect/" + station + "/" + id)
  c.cursor(rid, Hand)
  if hit(c, rid) {
    (core.push)(Connect(station, id))
  }
  c.box(style=desk_list_link, id=rid, fn() {
      cn_avatar(c, core, cv)
      c.box(style=cn_text, fn() {
        c.box(style=cn_title_line, fn() {
          c.text(text(cv, "name"), style=cn_title) |> ignore
          match opt_text(cv, "team") {
            Some(team) =>
              c.box(style=cn_team, fn() {
                cn_kind(c, text(cv, "kind"), cn_team_icon)
                c.text(team, style=cn_meta) |> ignore
              })
              |> ignore
            None => ()
          }
        })
        |> ignore
        let bind = field(cv, "bind")
        let model = match opt_text(bind, "model") {
          Some(m) => " · " + opt_text(cv, "modelName").unwrap_or(m)
          None => ""
        }
        c.text(text(cv, "modeText") + " · " + text(cv, "runtimeText") + model, style=cn_sub) |> ignore
      })
      |> ignore
      c.box(style=cn_facts, fn() {
        cn_station_tag(c, station_name, s)
        cn_owner(c, core, field(cv, "createdBy"))
      })
      |> ignore
      c.text(text(cv, "statusText"), style=cn_meta) |> ignore
      let on = [("station", station), ("id", id)]
      doing_mark(c, is_doing(core, ["connect.delete"], on), failed_of(core, ["connect.delete"], on))
      @sf.status_dot(c, text(cv, "presence"))
    })
  |> ignore
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
/// meta's 12; none said, so in the subtle ink.
fn cn_owner(c : @ui.Ctx, core : Core, by : Json?) -> Unit {
  let shown = field(by, "shown")
  if !(shown is Some(Object(_))) {
    c.text(@sf.t("web-main.owner.none"), style=cn_owner_none) |> ignore
    return
  }
  let name = text(shown, "name")
  c.box(style=cn_owner_box, fn() {
    avatar(c, core, text(by, "id"), name, cn_owner_size, picture=text(shown, "picture"))
    c.text(if flag(shown, "mine") { @sf.t("web-main.owner.you", args=[("name", name)]) } else { name }, style=cn_owner_words)
    |> ignore
  })
  |> ignore
}

///|
/// A Slack app made and not connected yet (WaitingApp): Slack's mark, its name and workspace, where it stands; its
/// station's tag; 继续 while its station is online (else that it is not), dropped from under ⋯.
fn cn_waiting_app(c : @ui.Ctx, core : Core, a : Json, s : Json) -> Unit {
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
  c.box(style=desk_list_row, fn() {
    c.box(style=cn_kind_box, fn() { @sf.slack_mark(c, cn_waiting_mark) |> ignore }) |> ignore
    c.box(style=cn_text, fn() {
      c.box(style=cn_title_line, fn() {
        c.text(text(av, "name"), style=cn_title) |> ignore
        match opt_text(av, "team") {
          Some(team) =>
            c.box(style=cn_team, fn() {
              @sf.slack_mark(c, cn_team_icon) |> ignore
              c.text(team, style=cn_meta) |> ignore
            })
            |> ignore
          None => ()
        }
      })
      |> ignore
      c.text(where_, style=cn_sub) |> ignore
    })
    |> ignore
    c.box(style=cn_facts, fn() { cn_station_tag(c, text(sv, "name"), sv) }) |> ignore
    let on = [("station", station), ("appId", app_id)]
    let dropping = is_doing(core, ["slack.dropApp"], on)
    if online {
      if @sf.button(c, @sf.t("web-pages.connects.continue"), key="waiting-go/" + app_id) {
        open_new_connect(core, station, resuming=app_id)
      }
    } else {
      c.text(@sf.t("web-pages.connects.stationOffline"), style=cn_meta) |> ignore
    }
    doing_mark(c, dropping, failed_of(core, ["slack.dropApp"], on))
    // dropped from under ⋯ (Menu), asked again first (Confirm); it stays in Slack
    if online && !dropping {
      let mid = c.id("waiting-more/" + app_id)
      c.cursor(mid, Hand)
      let open = waiting_menu.val == app_id
      if c.clicked(mid) {
        waiting_menu.val = if open { "" } else { app_id }
      }
      let b = c.box(style=cn_more, id=mid, fn() {
        @sf.icon(c, "more", size=cn_more_icon, color=@sf.theme().p.muted) |> ignore
      })
      c.semantics(b, Button, id=mid, label=@sf.t("web-pages.connects.removeHere"), expanded=open)
      let m = @sf.menu(c, "waiting-menu/" + app_id, open, mid, [@kit.menu_item("remove", label=@sf.t("web-pages.connects.removeHere"))], {}, @sf.menu_w, along=End)
      if open && !m.open {
        waiting_menu.val = ""
      }
      if m.chosen is Some(_) {
        waiting_menu.val = ""
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
    }
  })
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
let cn_kind_box : @ui.Style = @ui.style(w=S5, h=S5, align=ACenter, justify=JCenter)

///|
/// The filter, as wide as what it says, 8 further under the head than the head's own room, where the web's is
/// (pageHead: 28 under it), and 12 over the list; the waiting apps' title (sectionTitleQuiet: the meta's 12 in 500 muted, 6 under).
// kept across runs: a value (no field of it changes)
let cn_filter_room : @ui.Style = @ui.style(w=Full, px=S4, pt=S2, pb=S3, align=AStart)

///|
/// The lists at the column's edges (their rows reaching 12 past them: desk_list).
// kept across runs: a value (no field of it changes)
let cn_list_room : @ui.Style = @ui.style(w=Full, px=S4)

///|
/// The ⋯ menu open, by the waiting app's id ("" none).
// kept across runs: said again by each press; settings_reset empties it
let waiting_menu : Ref[String] = Ref("")

///|
// kept across runs: a value (no field of it changes)
let cn_quiet_room : @ui.Style = @ui.style(w=Full, px=S4, pb=S1_5)

///|
// kept across runs: a value (no field of it changes)
let cn_quiet : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, weight=Medium, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let cn_none_room : @ui.Style = @ui.style(w=Full, px=S4)

///|
// kept across runs: a value (no field of it changes)
let cn_error : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Danger, w=Full)

///|
// kept across runs: a value (no field of it changes)
let cn_note : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, w=Full)

///|
/// A row's words (listRowText: 2 apart, as wide as the row lets them; its title in 500, how it runs muted).
// kept across runs: a value (no field of it changes)
let cn_text : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let cn_title_line : @ui.Style = @ui.style(row=true, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let cn_title : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let cn_sub : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, wrap=false)

///|
/// Its Slack workspace after its name (connectTeam: 8 after it, its mark 4 from its name, the meta's 12 muted).
// kept across runs: a value (no field of it changes)
let cn_team : @ui.Style = @ui.style(row=true, gap=S1, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let cn_meta : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, wrap=false)

///|
/// Its station and who added it (connectFacts: 10 apart).
// kept across runs: a value (no field of it changes)
let cn_facts : @ui.Style = @ui.style(row=true, gap=S2_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let cn_tag : @ui.Style = @ui.style(row=true, px=S2, py=SPx, gap=S1, align=ACenter, radius=Md, bg=Neutral)

///|
// kept across runs: a value (no field of it changes)
let cn_tag_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, weight=Medium, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let cn_owner_box : @ui.Style = @ui.style(row=true, gap=S1_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let cn_owner_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let cn_owner_none : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Subtle, wrap=false)

///|
/// ⋯ (an icon button: 32, its corner 12).
// kept across runs: a value (no field of it changes)
let cn_more : @ui.Style = @ui.style(w=S8, h=S8, radius=Xl, align=ACenter, justify=JCenter, hovered=@ui.patch(bg=Hover))

