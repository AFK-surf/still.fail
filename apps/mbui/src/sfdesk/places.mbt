// The rail's places beyond the chats and the files, as the web's (ember web/src/cloud/workspace.tsx StationsSidebar,
// ProfilesSidebar; cloud/StationPage.tsx StationsNav, StationRow; ProfilesNav.tsx): Station and Profile each a list of
// their own in the sidebar (添加 in the band over it), the one picked its page beside it (the first to begin with); 连接
// and 用量 a page across the pane, no sidebar. A page merged for every frame is setting_route's (连接's, 用量's), the
// others still the settings' package's (@settings.page).

///|
/// A place of the rail's in the pane: Station's and Profile's the page picked in their list, 连接's its page, the
/// others (用量) the settings' page of it across the pane.
fn place_page(c : @ui.Ctx, src : Source, w : Workspace, place : String) -> Unit {
  let core = settings_core(src, w)
  let here = @settings.here_of(core, w.id, w.name)
  // (at the stack's root: no back over its head)
  @settings.wide_deep.val = false
  @settings.frame(core, here, root=true)
  match place {
    "stations" | "profiles" => place_split(c, src, w, place)
    _ =>
      c.box(style=place_across, fn() {
        match @settings.route_of(place) {
          Some(r) =>
            if !setting_route(c, src, w, r, { back: None, top: 0.0, foot: 0.0, named: false }) {
              @settings.page(c, core, here, r, root=true)
            }
          None => ()
        }
      })
      |> ignore
  }
}

///|
/// A place's sidebar, the stations' or the profiles'.
fn place_sidebar(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  match lit_place() {
    "stations" => stations_side(c, src, w)
    _ => profiles_side(c, src, w)
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
/// A profile's page (the web's profilePath): the station's copy the row shows; its page lists the account's other
/// stations.
fn profile_route(e : Json?) -> @settings.Route {
  Route::Profile(text(e, "station"), text(field(e, "profile"), "id"))
}

///|
/// The page in the pane for a place with a list of its own: the one picked, as the settings draw it.
fn place_split(c : @ui.Ctx, src : Source, w : Workspace, place : String) -> Unit {
  let core = settings_core(src, w)
  c.box(style=place_pane, fn() {
    match place_route(src, w, place) {
      // a station's: the desktop's own (station_page.mbt)
      Some(Station(a)) => station_page(c, core, @settings.here_of(core, w.id, w.name), a)
      // a profile's: the desktop's own (accounts.mbt)
      Some(Profile(a, id)) => profile_page(c, core, @settings.here_of(core, w.id, w.name), a, id)
      Some(r) => @settings.page(c, core, @settings.here_of(core, w.id, w.name), r, root=true)
      // none to pick yet: the first to add (the web's StationsFirst, RuntimeSettings' first)
      None =>
        if place == "profiles" {
          profiles_first(c, core, @settings.here_of(core, w.id, w.name), stations_listed(src, w))
        } else {
          stations_first(c, core, @settings.here_of(core, w.id, w.name), src, w)
        }
    }
  })
  |> ignore
}

///|
/// The stations' sidebar (StationsNav): 添加 station, then a row each.
fn stations_side(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let core = settings_core(src, w)
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
fn profiles_side(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let core = settings_core(src, w)
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

///|
/// No station picked: while they are read, said so; none in the workspace, the first to add (its scene, 添加 station).
fn stations_first(c : @ui.Ctx, core : Core, here : Here, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let read = (src.topic)("stations", { "scope": Json::string(w.id) }).value is Some(_)
  desk_page(c, core, "stations-first", "Station", [
    fn() {
      if !read {
        @sf.waiting(c, shape=Cards, note={ reading: true, text: @sf.t("common.readingStations"), failing: [] })
        return
      }
      @sf.first_one(
        c,
        @sf.t("web-pages.settings.stations.add"),
        art=fn() { @sf.drawable(c, if t.dark { "illus_no_station_dark" } else { "illus_no_station" }, pl_art_w) |> ignore },
        fn() {
          // (its managers': the others wait for one)
          match @settings.place_action(core, here, "stations") {
            Some(add) =>
              if @sf.button(c, @sf.t("web-pages.settings.stations.add"), key="stations-first/add", tone=Primary, icon="plus") {
                add()
              }
            None => c.text(@sf.t("web-pages.settings.stations.noneYet"), style=desk_muted_line) |> ignore
          }
        },
      )
    },
  ])
}

///|
/// Not one profile yet (RuntimeSettings' first): what a profile is, then each station in a row, where one is added (an
/// online one's 添加 Profile; an offline one's, later), with its machine's own logins not used yet under it.
fn profiles_first(c : @ui.Ctx, core : Core, here : Here, stations : Array[Json]) -> Unit {
  let t = @sf.theme()
  desk_page(c, core, "profiles-first", "Profile", [
    fn() {
      @sf.first_one(
        c,
        @sf.t("web-pages.settings.profiles.addFirst"),
        lead=@sf.t("web-pages.settings.profiles.lead", args=[("name", "still.fail")]),
        art=fn() { @sf.drawable(c, if t.dark { "illus_no_profile_dark" } else { "illus_no_profile" }, pl_art_w) |> ignore },
        fn() {
          c.box(style=pl_first_stations, fn() {
            for st in stations {
              let sv = Some(st)
              let address = text(sv, "station")
              let online = flag(sv, "online")
              c.box(style=pl_first_station, fn() {
                c.box(style=pl_first_row, fn() {
                  @sf.status_dot(c, if online { "online" } else { "offline" })
                  c.text(text(sv, "name"), style=pl_first_name) |> ignore
                  if online {
                    if @sf.button(
                        c,
                        @sf.t("web-pages.settings.profiles.add"),
                        key="profiles-first/add/" + address,
                        tone=if stations.length() == 1 { Primary } else { Plain },
                        icon="plus",
                      ) {
                      (core.push)(NewProfile(address))
                    }
                  } else {
                    c.text(@sf.t("web-pages.settings.profiles.offlineAdd"), style=desk_muted_line) |> ignore
                  }
                })
                |> ignore
                if online {
                  machine_offers(c, core, sv, fn(rt) {
                    // the machine's login signed in again as its vendor's plan, on the add page
                    add_profile_start[address] = [("provider", str(if rt == "claude" { "anthropic" } else { "openai" })), ("method", str("plan"))]
                    (core.push)(NewProfile(address))
                  })
                }
              })
              |> ignore
            }
          })
          |> ignore
        },
      )
    },
  ])
  ignore(here)
}

///|
let pl_art_w : Double = 240.0

///|
/// Each station a row (firstStations: 28 apart, at the start; firstStationRow: 10 apart; its name semibold, taking the
/// room; its machine's logins 14 under it).
// kept across runs: a value (no field of it changes)
let pl_first_stations : @ui.Style = @ui.css("w=Full gap=S7 align=AStretch")

///|
// kept across runs: a value (no field of it changes)
let pl_first_station : @ui.Style = @ui.css("w=Full gap=S3_5")

///|
// kept across runs: a value (no field of it changes)
let pl_first_row : @ui.Style = @ui.css("row w=Full gap=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pl_first_name : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, weight=Semibold, color=Fg, wrap=false, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let desk_muted_line : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, wrap=false)
