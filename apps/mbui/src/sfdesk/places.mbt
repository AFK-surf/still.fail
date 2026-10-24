// The rail's places beyond the chats and the files, as the web's (ember web/src/cloud/workspace.tsx StationsSidebar,
// ProfilesSidebar; cloud/StationPage.tsx StationsNav, StationRow; ProfilesNav.tsx): Station and Profile each a list of
// their own in the sidebar (添加 in the band over it), the one picked its page beside it (the first to begin with); 连接
// and 用量 a page across the pane, no sidebar. The pages themselves are still the settings' package's
// (@settings.page) but for 连接's (connects.mbt).

///|
/// A place of the rail's in the pane: Station's and Profile's the page picked in their list, 连接's its page, the
/// others (用量) the settings' page of it across the pane.
fn place_page(c : @ui.Ctx, src : Source, w : Workspace, pages : Pages, place : String) -> Unit {
  let core = (pages.core)(src, w)
  let here = @settings.here_of(core, w.id, w.name)
  // (at the stack's root: no back over its head)
  @settings.wide_deep.val = false
  @settings.frame(core, here, root=true)
  match place {
    "stations" | "profiles" => place_split(c, src, w, pages, place)
    "connects" => c.box(style=place_across, fn() { connects_page(c, core, here) }) |> ignore
    _ =>
      c.box(style=place_across, fn() {
        match @settings.route_of(place) {
          Some(r) => @settings.page(c, core, here, r, root=true)
          None => ()
        }
      })
      |> ignore
  }
}

///|
/// A place's sidebar, the stations' or the profiles'.
fn place_sidebar(c : @ui.Ctx, src : Source, w : Workspace, pages : Pages) -> Unit {
  match lit_place() {
    "stations" => stations_side(c, src, w, pages)
    _ => profiles_side(c, src, w, pages)
  }
}

///|
/// The page picked in a place with a list of its own (Station's, Profile's), by place; none: the first.
// kept across runs: said by a row pressed; places_reset empties it
let place_pick : Map[String, Route] = {}

///|
fn places_reset() -> Unit {
  place_pick.clear()
}

///|
/// A page across the pane (连接, 用量: no sidebar), on the page's ground.
// kept across runs: a value (no field of it changes)
let place_across : @ui.Style = @ui.css("w=Full h=Full bg=Bg")

///|
/// The page picked in a place (the stations' or the profiles' list), by place; none: the first.
fn place_route(src : Source, w : Workspace, place : String) -> @settings.Route? {
  match place_pick.get(place) {
    Some(r) => Some(r)
    None =>
      match place {
        "stations" =>
          match stations_listed(src, w).get(0) {
            Some(s) => Some(Route::Station(text(Some(s), "station")))
            None => None
          }
        "profiles" =>
          match items((src.topic)("profiles", { "scope": Json::string(w.id) }).value, "items").get(0) {
            Some(e) => Some(profile_route(Some(e)))
            None => None
          }
        _ => None
      }
  }
}

///|
/// The workspace's stations, as the core lists them.
fn stations_listed(src : Source, w : Workspace) -> Array[Json] {
  match (src.topic)("stations", { "scope": Json::string(w.id) }).value {
    Some(Array(a)) => a
    _ => []
  }
}

///|
/// A profile's page: an account signed in on several stations its own, else the station's copy the row shows.
fn profile_route(e : Json?) -> @settings.Route {
  let signed = items(e, "members").filter(fn(m) { text(Some(m), "role") != "user" }).length()
  if signed > 1 {
    Route::ProfileAccount(text(e, "key"))
  } else {
    Route::Profile(text(e, "station"), text(field(e, "profile"), "id"))
  }
}

///|
/// The page in the pane for a place with a list of its own: the one picked, as the settings draw it.
fn place_split(c : @ui.Ctx, src : Source, w : Workspace, pages : Pages, place : String) -> Unit {
  let core = (pages.core)(src, w)
  c.box(style=place_pane, fn() {
    match place_route(src, w, place) {
      Some(r) => @settings.page(c, core, @settings.here_of(core, w.id, w.name), r, root=true)
      None => @settings.page(c, core, @settings.here_of(core, w.id, w.name), Route::Stations, root=true)
    }
  })
  |> ignore
}

///|
/// The stations' sidebar (StationsNav): 添加 station, then a row each.
fn stations_side(c : @ui.Ctx, src : Source, w : Workspace, pages : Pages) -> Unit {
  let core = (pages.core)(src, w)
  let here = @settings.here_of(core, w.id, w.name)
  let picked = place_route(src, w, "stations")
  c.box(style=place_side, fn() {
    side_top(c)
    c.box(style=place_list, fn() {
      nav_action(c, "stations/add", @sf.t("web-pages.settings.stations.add"), @settings.place_action(core, here, "stations"))
      for s in stations_listed(src, w) {
        let s = Some(s)
        let address = text(s, "station")
        let on = picked == Some(Route::Station(address))
        station_side_row(c, src, s, on, fn() { place_pick["stations"] = Route::Station(address) })
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A station's row (StationRow): its mark and name, how it is at the end (its agents at work, or when it was last seen
/// away); while up, what is left of its CPU, memory and disk in small boxes, and how this device reaches it.
fn station_side_row(c : @ui.Ctx, src : Source, s : Json?, on : Bool, pick : () -> Unit) -> Unit {
  let t = @sf.theme()
  let address = text(s, "station")
  let online = flag(s, "online")
  let meters = if online { items(field(s, "host"), "meters") } else { [] }
  let net = if online { (src.topic)("stationNet", { "station": Json::string(address) }).value } else { None }
  let running = number(field(field(s, "overview"), "counts"), "running")
  if nav_row(c, "stations/" + address, on, align=AStart, fn() {
      c.box(style=place_mark, fn() {
        @sf.station_icon(c, text(s, "emoji"), text(s, "icon"), @sf.row_icon, t.p.text)
      })
      |> ignore
      c.box(style=place_row_words, fn() {
        c.box(style=place_row_head, fn() {
          c.text(text(s, "name"), style=place_row_name) |> ignore
          c.box(style=place_end, fn() {
            c.box(style=if online { place_dot_on } else { place_dot_off }, fn() {  }) |> ignore
            if !online {
              c.text(text(s, "summary"), style=place_meta) |> ignore
            } else if running > 0.0 {
              c.text(@sf.t("web-pages.stations.page.runningShort", args=[("n", running.to_int().to_string())]), style=place_busy)
              |> ignore
            }
          })
          |> ignore
        })
        |> ignore
        if meters.length() > 0 {
          c.box(style=place_meters, fn() {
            for m in meters {
              let m = Some(m)
              let level = text(m, "level")
              c.box(style=if level == "" || level == "ok" { meter_chip } else { meter_chip_low }, fn() {
                // (MeterChip brief: what is left, its unit's first letter)
                let unit = text(m, "unit")
                let brief = text(m, "big") +
                  (if unit == "%" || unit == "" { unit } else { unit.view(end_offset=1).to_string() })
                c.text(text(m, "short"), style=place_meta) |> ignore
                c.text(if text(m, "big") == "" { text(m, "remaining") } else { brief }, style=meter_value) |> ignore
              })
              |> ignore
            }
          })
          |> ignore
        }
        match net {
          Some(Object(_)) =>
            c.text(
              match text(field(net, "rtt"), "text") {
                "" => text(net, "path")
                rtt => text(net, "path") + " · " + rtt
              },
              style=place_meta,
            )
            |> ignore
          _ => ()
        }
      })
      |> ignore
    }) {
    pick()
  }
}

// ── Profile ─────────────────────────────────────────────────────────────

///|
/// The profiles' sidebar (ProfilesNav): 添加 Profile, a section each kind of account, a row an account; then each
/// station's own logins not made profiles yet.
fn profiles_side(c : @ui.Ctx, src : Source, w : Workspace, pages : Pages) -> Unit {
  let t = @sf.theme()
  let core = (pages.core)(src, w)
  let here = @settings.here_of(core, w.id, w.name)
  let picked = place_route(src, w, "profiles")
  let list = items((src.topic)("profiles", { "scope": Json::string(w.id) }).value, "items")
  c.box(style=place_side, fn() {
    side_top(c)
    c.box(style=place_list, fn() {
      nav_action(c, "profiles/add", @sf.t("web-pages.settings.profiles.add"), @settings.place_action(core, here, "profiles"))
      let mut group = ""
      for e in list {
        let e = Some(e)
        if text(e, "group") != group {
          group = text(e, "group")
          nav_heading(c, text(e, "groupTitle"))
        }
        let p = field(e, "profile")
        let route = profile_route(e)
        let usable = flag(e, "usable")
        let trouble = if !usable {
          @sf.t("web-pages.settings.profiles.hostAway", args=[("station", text(e, "hostName"))])
        } else if text(p, "checkTone") != "green" {
          text(p, "checkText")
        } else {
          ""
        }
        if nav_row(c, "profiles/" + text(e, "key"), picked == Some(route), align=AStart, fn() {
            c.box(style=place_mark, fn() {
              @sf.maker_mark(c, text(p, "providerMark"), text(p, "runtime"), @sf.row_icon) |> ignore
            })
            |> ignore
            c.box(style=place_row_words, fn() {
              c.text(text(p, "name"), style=if usable { place_row_name } else { place_name_away }) |> ignore
              c.box(style=place_end_line, fn() {
                if trouble != "" {
                  c.text(trouble, style=place_trouble) |> ignore
                }
                let quota = field(p, "quota")
                if text(quota, "state") == "ok" && items(quota, "windows").length() > 0 {
                  @settings.quota_chips(c, quota, small=true)
                } else if trouble == "" {
                  c.text(text(e, "where"), style=place_meta) |> ignore
                }
              })
              |> ignore
            })
            |> ignore
          }) {
          place_pick["profiles"] = route
        }
      }
      // each station's own logins, not profiles yet
      for s in stations_listed(src, w) {
        let s = Some(s)
        if !flag(s, "online") {
          continue
        }
        let station = text(s, "station")
        let offers = items(field(s, "overview"), "machineLogins").filter(fn(l) {
          flag(Some(l), "offered") && text(field(Some(l), "quota"), "state") != "blocked"
        })
        if offers.length() == 0 {
          continue
        }
        nav_heading(c, @sf.t("web-pages.profiles.machineSignedIn", args=[("station", text(s, "name"))]))
        for l in offers {
          let l = Some(l)
          if nav_row(c, "profiles/machine/" + station + "/" + text(l, "runtime"), false, align=AStart, fn() {
              c.box(style=place_mark, fn() {
                @sf.maker_mark(c, "", text(l, "runtime"), @sf.row_icon) |> ignore
              })
              |> ignore
              c.box(style=place_row_words, fn() {
                c.text(@settings.runtime_label(text(l, "runtime")), style=place_row_name) |> ignore
                c.box(style=place_end_line, fn() {
                  c.box(style=place_grow, fn() { c.text(text(l, "email"), style=place_meta) |> ignore }) |> ignore
                  c.text(@sf.t("android-settings.machine.use"), style=place_use) |> ignore
                })
                |> ignore
              })
              |> ignore
            }) {
            app.nav.push(Setting(Route::NewProfile(station)))
          }
        }
      }
      ignore(t)
    })
    |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let place_pane : @ui.Style = @ui.css("w=Full h=Full bg=Bg")

///|
// kept across runs: a value (no field of it changes)
let place_side : @ui.Style = @ui.css("w=Full h=Full")

///|
/// The list under the band: 8 in at its sides, 4 under the band (Sidebar.css.ts navList).
// kept across runs: a value (no field of it changes)
let place_list : @ui.Style = @ui.css("w=Full h=Full px=S2 pt=S1")

///|
/// A row's mark (NavItem's): 16, on its first line's middle.
// kept across runs: a value (no field of it changes)
let place_mark : @ui.Style = @ui.css("w=S4 h=S5 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let place_row_words : @ui.Style = @ui.style(w=@sf.grow, gap=S1)

///|
// kept across runs: a value (no field of it changes)
let place_row_head : @ui.Style = @ui.css("row w=Full gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let place_end : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let place_end_line : @ui.Style = @ui.css("row w=Full gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let place_grow : @ui.Style = @ui.style(w=@sf.grow, clip=true)

///|
// kept across runs: a value (no field of it changes)
let place_row_name : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let place_name_away : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let place_meta : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// Its agents at work (StationPage.css.ts busy): the accent's words.
// kept across runs: a value (no field of it changes)
let place_busy : @ui.TextStyle = @ui.text_style(size=Xs, color=AccentText, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let place_trouble : @ui.TextStyle = @ui.text_style(size=Xs, color=Danger, wrap=false)

///|
/// 使用此账号 (ProfilesNav MachineLoginRow): the accent's words.
// kept across runs: a value (no field of it changes)
let place_use : @ui.TextStyle = @ui.text_style(size=Xs, color=AccentText, wrap=false)

///|
/// Up or away: the rail's dot (railCss.dot: 6).
// kept across runs: a value (no field of it changes)
let place_dot_on : @ui.Style = @ui.css("w=S1_5 h=S1_5 radius=Full bg=Positive")

///|
// kept across runs: a value (no field of it changes)
let place_dot_off : @ui.Style = @ui.css("w=S1_5 h=S1_5 radius=Full bg=Faint")

///|
/// Its meters in a line (rowMeters), a chip each (MeterChip brief bare): its name muted and what is left, on a ground;
/// one running low with its level's edge.
// kept across runs: a value (no field of it changes)
let place_meters : @ui.Style = @ui.css("row w=Full gap=S1 align=ACenter clip")

///|
// kept across runs: a value (no field of it changes)
let meter_chip : @ui.Style = @ui.css("row px=S1 py=SPx gap=S1 align=ACenter radius=Base bg=Hover")

///|
// kept across runs: a value (no field of it changes)
let meter_chip_low : @ui.Style = meter_chip.then(@ui.css("border=B1 border_color=Warn"))

///|
// kept across runs: a value (no field of it changes)
let meter_value : @ui.TextStyle = @ui.text_style(size=Xs, weight=Semibold, color=Fg, wrap=false)
