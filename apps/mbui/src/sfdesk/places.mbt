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
/// The page picked in a place (the stations' or the profiles' list) of the workspace `w`; none: the first.
fn place_route(src : Source, w : Workspace, place : String) -> @settings.Route? {
  match place_pick.get(place_key(w.id, place)) {
    // (a station gone from the list: the first, not its page waiting for it)
    Some(Station(a)) if !stations_listed(src, w).iter().any(fn(s) { text(Some(s), "station") == a }) =>
      place_route_first(src, w, place)
    Some(r) => Some(r)
    None => place_route_first(src, w, place)
  }
}

///|
/// The page a place shows with none picked in it: the first station; the first profile that needs a look, else the
/// first.
fn place_route_first(src : Source, w : Workspace, place : String) -> @settings.Route? {
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
    nav_action(c, "stations/add", @sf.t("web-pages.settings.stations.add"), @settings.place_action(core, here, "stations"))
    side_scroll(c, "stations-nav/" + w.id, fn() {
      let listed = stations_listed(src, w)
      for i, s in listed {
        let s = Some(s)
        let address = text(s, "station")
        let on = picked == Some(Route::Station(address))
        station_side_row(c, src, s, on, i + 1 < listed.length(), fn() {
          place_pick[place_key(w.id, "stations")] = Route::Station(address)
          @sfbase.show_chosen()
        })
      }
    })
  })
  |> ignore
}

///|
/// A station's row (StationRow): its mark and name, how it is at the end (@sfpages.station_state); while up, what is
/// left of its CPU, memory and disk and how this device reaches it (@sfpages.station_figures); those two lines' room
/// kept while it is away, every station's row as high.
fn station_side_row(c : @ui.Ctx, src : Source, s : Json?, on : Bool, more : Bool, pick : () -> Unit) -> Unit {
  let t = @sf.theme()
  if nav_item(
      c,
      "stations/" + text(s, "station"),
      on,
      fn() { @sf.station_icon(c, text(s, "emoji"), text(s, "icon"), nav_mark_side, t.p.text) },
      fn() { nav_title(c, text(s, "name")) },
      end=fn() { @sfpages.station_state(c, s) },
      lines=fn() { @sfpages.station_figures(c, src, s) },
      keep_lines=2,
      more~,
    ) {
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
    nav_action(c, "profiles/add", @sf.t("web-pages.settings.profiles.add"), @settings.place_action(core, here, "profiles"))
    side_scroll(c, "profiles-nav/" + w.id, fn() {
      let mut group = ""
      for i, e in list {
        let e = Some(e)
        // (another row under it: the next of its group)
        let more = i + 1 < list.length() && text(Some(list[i + 1]), "group") == text(e, "group")
        if text(e, "group") != group {
          group = text(e, "group")
          @sf.list_heading(c, text(e, "groupTitle"), Side)
        }
        let p = field(e, "profile")
        let route = profile_route(e)
        let usable = flag(e, "usable")
        // how it is where that is not simply fine, as the core says it, in its tone (ProfilesNav.tsx ProfileRow): what
        // needs a look in colour
        let trouble = text(field(e, "state"), "text")
        let tone = text(field(e, "state"), "tone")
        // where it is and who uses it
        let used = items(p, "usedBy").length()
        let facts = [
          text(e, "where"),
          if used > 0 {
            @sf.t("web-pages.settings.profiles.usedBy", args=[("n", used.to_string())])
          } else {
            ""
          },
        ].filter(fn(x) { x != "" })
        let facts = facts.join(" · ")
        let quota = field(p, "quota")
        let ok = text(quota, "state") == "ok"
        let windows = ok && items(quota, "windows").length() > 0
        let credits = ok && !windows && text(quota, "creditsText") != ""
        if nav_item(
            c,
            "profiles/" + text(e, "key"),
            picked == Some(route),
            fn() { @sf.maker_mark(c, text(p, "providerMark"), text(p, "runtime"), nav_mark_side) |> ignore },
            // (a subscription by its account, a key by its name: the core's)
            fn() { nav_title(c, if text(e, "title") == "" { text(p, "name") } else { text(e, "title") }, away=!usable) },
            lines=fn() {
              // The state (or where the account can be used) and its allowance each have their own line: neither
              // may take the room the other's words need. Keeping both lines also keeps the row's height as its
              // station goes offline and comes back.
              if windows || credits {
                @sf.list_row_line(c, fn() {
                  if trouble != "" {
                    c.text(trouble, style=nav_meta().then(trouble_ink(tone))) |> ignore
                  } else {
                    c.text(facts, style=nav_meta().then(place_fill)) |> ignore
                  }
                })
              }
              if !windows {
                @sf.list_row_line(c, fn() {
                  if trouble != "" && !credits {
                    c.text(trouble, style=nav_meta().then(trouble_ink(tone))) |> ignore
                  }
                  if credits {
                    c.text(text(quota, "creditsText"), style=nav_meta()) |> ignore
                  } else {
                    if trouble != "" && facts != "" {
                      c.text("·", style=nav_meta()) |> ignore
                    }
                    c.text(facts, style=nav_meta().then(place_fill)) |> ignore
                  }
                })
              }
            },
            more~,
            foot?=if windows {
              Some(fn() { @sf.nav_quota_chips(c, quota, key="profiles/" + text(e, "key")) })
            } else {
              None
            },
            foot_capsule?=if windows { Some(@sf.fill_chip_small_h) } else { None },
          ) {
          place_pick[place_key(w.id, "profiles")] = route
          @sfbase.show_chosen()
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
        @sf.list_heading(c, @sf.t("web-pages.profiles.machineSignedIn", args=[("station", text(s, "name"))]), Side)
        for j, l in offers {
          let l = Some(l)
          if nav_item(
              c,
              "profiles/machine/" + station + "/" + text(l, "runtime"),
              false,
              fn() { @sf.maker_mark(c, "", text(l, "runtime"), nav_mark_side) |> ignore },
              fn() { nav_title(c, @settings.runtime_label(text(l, "runtime"))) },
              lines=fn() {
                @sf.list_row_line(c, fn() {
                  c.box(style=place_grow, fn() { c.text(text(l, "email"), style=nav_meta(), allow_ellipsis=true) |> ignore }) |> ignore
                  c.text(@sf.t("android-settings.machine.use"), style=nav_meta().then(place_use)) |> ignore
                })
              },
              more=j + 1 < offers.length(),
            ) {
            @sfbase.history_push()
            app.nav.push(Setting(Route::NewProfile(station)))
            @sfbase.show_chosen()
          }
        }
      }
      ignore(t)
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
// kept across runs: a value (no field of it changes)
let place_grow : @ui.Style = @ui.style(w=@sf.grow, clip=true)

///|
/// What is wrong, in its tone (ProfilesNav.css.ts trouble): amber, red, or muted (neutral).
fn trouble_ink(tone : String) -> @ui.TextStyle {
  match tone {
    "red" => place_trouble_red
    "neutral" => place_trouble_neutral
    _ => place_trouble_amber
  }
}

///|
// kept across runs: a value (no field of it changes)
let place_trouble_red : @ui.TextStyle = @ui.text_style(color=Danger)

///|
// kept across runs: a value (no field of it changes)
let place_trouble_amber : @ui.TextStyle = @ui.text_style(color=WarnInk)

///|
// kept across runs: a value (no field of it changes)
let place_trouble_neutral : @ui.TextStyle = @ui.text_style(color=Muted)

///|
/// The words that give way first (SidebarList.css.ts fill).
// kept across runs: a value (no field of it changes)
let place_fill : @ui.TextStyle = @ui.text_style(w=Cut)

///|
/// 使用此账号 (ProfilesNav MachineLoginRow): the accent's words.
// kept across runs: a value (no field of it changes)
let place_use : @ui.TextStyle = @ui.text_style(color=AccentText)

///|
/// No station picked: while they are read, said so; none in the workspace, the first to add (its scene, 添加 station).
fn stations_first(c : @ui.Ctx, core : Core, here : Here, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let read = (src.topic)("stations", { "scope": Json::string(w.id) }).value is Some(_)
  // (while they are read: a station's page, the one picked once they are, in its bones)
  if !read {
    @sfpages.station_waiting(c, core, here, @sf.no_frame, "Station", @sf.t("common.readingStations"))
    return
  }
  desk_page(c, core, "stations-first", "Station", [
    fn() {
      @sf.first_one(
        c,
        @sf.t("web-pages.settings.stations.add"),
        art=fn() { @sf.drawable(c, if t.dark { "illus_no_station_dark" } else { "illus_no_station" }, pl_art_w) |> ignore },
        fn() {
          // (its managers': the others wait for one)
          match @settings.place_action(core, here, "stations") {
            Some(add) =>
              if @sf.button(c, @sf.t("web-pages.settings.stations.add"), key="stations-first/add", tone=Primary, icon="plus") {
                add(Of(c.id("stations-first/add")))
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
let pl_first_name : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=Fg, wrap=false, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let desk_muted_line : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)
