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
  // (at the stack's root: no back over its head, its own or the settings' pages')
  @settings.wide_deep.val = false
  settings_deep.val = false
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
fn places_reset() -> Unit {
  place_pick.clear()
}

///|
/// A page across the pane (连接, 用量: no sidebar), on the page's ground.
// kept across runs: a value (no field of it changes)
let place_across : @ui.Style = @ui.css("w=Full h=Full bg=Bg")

///|
/// The page picked in a place (the stations' or the profiles' list), by place; none: the first (of the profiles, the
/// first that needs a look).
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
        // (the first that needs a look, else the first: what its settings' row counts is what shows)
        "profiles" => {
          let list = items((src.topic)("profiles", { "scope": Json::string(w.id) }).value, "items")
          list.get(list.search_by(fn(e) { flag(Some(e), "look") }).or(0)).map(fn(e) { profile_route(Some(e)) })
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
      // a station's: one page in every frame (src/sfpages station_page.mbt)
      Some(Station(a)) => @sfpages.station_page(c, core, @settings.here_of(core, w.id, w.name), { back: None, top: 0.0, foot: 0.0, named: false }, a)
      // a profile's: one page in every frame (src/sfpages accounts.mbt)
      Some(Profile(a, id)) => @sfpages.profile_page(c, core, @settings.here_of(core, w.id, w.name), { back: None, top: 0.0, foot: 0.0, named: false }, a, id)
      Some(r) => @settings.page(c, core, @settings.here_of(core, w.id, w.name), r, root=true)
      // none to pick yet: the first to add (the web's StationsFirst, RuntimeSettings' first)
      None =>
        if place == "profiles" {
          profiles_first(c, core, @settings.here_of(core, w.id, w.name), stations_listed(src, w))
        } else {
          @sfpages.stations_first(c, src, core, @settings.here_of(core, w.id, w.name), w, @sf.no_frame)
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
    nav_action(c, "stations/add", @sf.t("web-pages.settings.stations.add"), @settings.place_action(core, here, "stations"))
    side_scroll(c, "stations-nav/" + w.id, fn() {
      // (sfpages' stations.mbt: the list standing in the side column, the one picked its page beside it)
      let chosen = match picked {
        Some(Route::Station(a)) => Some(a)
        _ => None
      }
      for line in @sfpages.stations_lines(c, src, core, w, Side, chosen, fn(address) {
          place_pick["stations"] = Route::Station(address)
          @sfbase.show_chosen()
        }) {
        line()
      }
    })
  })
  |> ignore
}

///|
/// The profiles' sidebar (ProfilesNav): 添加 Profile, a section each kind of account, a row an account; then each
/// station's own logins not made profiles yet.
fn profiles_side(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let core = settings_core(src, w)
  let here = @settings.here_of(core, w.id, w.name)
  let picked = place_route(src, w, "profiles")
  c.box(style=place_side, fn() {
    side_top(c)
    nav_action(c, "profiles/add", @sf.t("web-pages.settings.profiles.add"), @settings.place_action(core, here, "profiles"))
    side_scroll(c, "profiles-nav/" + w.id, fn() {
      // (sfpages' profiles.mbt: the list standing in the side column, the one picked its page beside it)
      @sfpages.profiles_rows(c, src, w, picked, fn(route) {
        place_pick["profiles"] = route
        @sfbase.show_chosen()
      }, fn(station) {
        app.nav.push(Setting(Route::NewProfile(station)))
        @sfbase.show_chosen()
      })
    })
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
let pl_first_name : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=Fg, wrap=false, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let desk_muted_line : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)
