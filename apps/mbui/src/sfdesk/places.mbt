// The rail's places beyond the chats and the files, as the web's (still.fail web/src/cloud/workspace.tsx StationsSidebar,
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
    Some(Station(a)) if !stations_listed(src, w).iter().any(fn(s) { text(Some(s), "station") == a }) && place_rig_at(src, w, a) is None =>
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
      let list = items(src.topic("profiles", { "scope": Json::string(w.id) }).get().value, "items")
      list.get(list.search_by(fn(e) { flag(Some(e), "look") }).unwrap_or(0)).map(fn(e) { profile_route(Some(e)) })
    }
    _ => None
  }
}

///|
/// The workspace's stations, their rows as the core lists them.
fn stations_listed(src : Source, w : Workspace) -> Array[Json] {
  match @sfbase.station_rows(src, w.id).value {
    Some(Array(a)) => a
    _ => []
  }
}

///|
/// The station at `address` picked in the stations' place of workspace `ws`, as a press on its row picks it (a made-up
/// run opened on it).
pub fn place_pick_station(ws : String, address : String) -> Unit {
  place_pick[place_key(ws, "stations")] = Route::Station(address)
}

///|
/// The workspace's station that only runs tasks at `address`, if it is one (the settings' rig_at).
fn place_rig_at(src : Source, w : Workspace, address : String) -> Json? {
  let core = settings_core(src, w)
  @settings.rig_at(core, @settings.here_of(core, w.id, w.name), address)
}

///|
/// The address of the station picked in the stations' place of the workspace in view where it is one that only runs
/// tasks, else "": its page is made once as nodes (pane_made's, tape_made's), in the place of the old view's.
fn place_rig(src : Source) -> String {
  match @sfbase.workspace_in_view(src).0 {
    Some(w) =>
      match place_route(src, w, "stations") {
        Some(Station(a)) if place_rig_at(src, w, a) is Some(_) => a
        _ => ""
      }
    None => ""
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
      Some(r) => @settings.page(c, core, @settings.here_of(core, w.id, w.name), r, root=true)
      // none to pick yet: the first to add (the web's StationsFirst, RuntimeSettings' first)
      // (the profiles' place made once as nodes: profiles_place_node)
      None => stations_first(c, core, @settings.here_of(core, w.id, w.name), src, w)
    }
  })
  |> ignore
}

///|
/// The profiles' place in node `v` (pane_made's, tape_made's): the profile picked in its list (place_route's), made once
/// as its page is (another, another page), at the stack's root; none to pick yet, the first to add.
fn profiles_place_node(
  v : @view.View,
  src : Source,
  core : @settings.Core,
  here : () -> @settings.Here,
  stint : () -> Int,
  frame : () -> @sf.PageFrame,
  width : () -> Double,
  said? : (@sf.PageSaid) -> Unit,
  tips? : @sf.TipLayer,
) -> Unit {
  let picked = fn() {
    match @sfbase.workspace_in_view(src).0 {
      Some(w) =>
        match place_route(src, w, "profiles") {
          Some(Profile(a, id)) => Some((a, id))
          _ => None
        }
      None => None
    }
  }
  v.pick(picked, fn(p, at) {
    p.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
    match at {
      Some((a, id)) => @sfpages.profile_node(p, core, here, a, id, on_back=core.pop, frame~, said?, width~, tips?, stint~)
      None => @sfpages.profiles_first_node(p, core, here, on_back=core.pop, frame~, said?, width~, tips?)
    }
  })
}

///|
/// The stations' sidebar (StationsNav): 添加 station, then a row each.
fn stations_side(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let core = settings_core(src, w)
  let here = @settings.here_of(core, w.id, w.name)
  let picked = place_route(src, w, "stations")
  c.box(style=place_side, fn() {
    side_top(c)
    nav_action(c, "stations/add", @sf.t("web-pages.settings.stations.add"), @settings.place_action(core, here, "stations"), trailing?=update_trailing(c, src), band=update_band(), at=side_at())
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
      // those that only run tasks after the whole ones: whose each is and how it is, in the figures' place
      for r in @settings.rigs_listed(core, here) {
        let r = Some(r)
        let address = w.id + "/" + text(r, "id")
        let t = @sf.theme()
        nav_item(
          c,
          at=side_at(),
          "stations/" + address,
          picked == Some(Route::Station(address)),
          fn() { @sf.icon(c, "boxes", size=nav_mark_side, color=t.p.text) |> ignore },
          fn() { nav_title(c, text(r, "name")) },
          lines=fn() { @sfpages.rig_figures(c, r) },
          keep_lines=2,
          more=false,
          on_press=fn() {
            place_pick[place_key(w.id, "stations")] = Route::Station(address)
            @sfbase.show_chosen()
          },
        )
      }
      // the workspace's devices under their heading (设备: attached to a station, or a person's phone), each opening
      // its panel
      let devices = @settings.devices_listed(core, here)
      if devices.length() > 0 {
        @sf.list_heading(c, @sf.t("web-pages.devices.title"), side_at())
      }
      for d in devices {
        let d = Some(d)
        let t = @sf.theme()
        nav_item(
          c,
          at=side_at(),
          "devices/" + text(d, "station") + "/" + text(d, "id"),
          false,
          fn() { @sf.icon(c, @settings.device_icon(d), size=nav_mark_side, color=t.p.text) |> ignore },
          fn() { nav_title(c, text(d, "name"), away=field(d, "online") is Some(False)) },
          lines=fn() { c.text(@settings.device_said(d), style=nav_meta(), allow_ellipsis=true) |> ignore },
          keep_lines=1,
          more=false,
          on_press=fn() { @settings.open_device(core, here, text(d, "station"), text(d, "id"), Unanchored) },
        )
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
  nav_item(
      c,
      at=side_at(),
      "stations/" + text(s, "station"),
      on,
      fn() { @sf.station_icon(c, text(s, "emoji"), text(s, "icon"), nav_mark_side, t.p.text) },
      fn() { nav_title(c, text(s, "name")) },
      end=fn() { @sfpages.station_state(c, s) },
      lines=fn() { @sfpages.station_figures(c, src, s) },
      keep_lines=2,
      more~,
      on_press=pick,
    )
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
  let list = items(src.topic("profiles", { "scope": Json::string(w.id) }).get().value, "items")
  c.box(style=place_side, fn() {
    side_top(c)
    nav_action(c, "profiles/add", @sf.t("web-pages.settings.profiles.add"), @settings.place_action(core, here, "profiles"), trailing?=update_trailing(c, src), band=update_band(), at=side_at())
    side_scroll(c, "profiles-nav/" + w.id, fn() {
      let mut group = ""
      // each station's own logins, not profiles yet (under the profiles: each station up that offers one)
      let offered = @settings.profiles_offers(src.topic("profiles", { "scope": Json::string(w.id) }).get().value).map(fn(o) {
        (o.0, o.1.filter(fn(l) { flag(Some(l), "offered") && text(field(Some(l), "quota"), "state") != "blocked" }))
      })
      // (the room the widest allowance's chips of each provider need: one way for every row of a vendor's, a profile's
      // or an offered login's, nav_quota_chips; the user, 2026-11-13: 「按账号类型来搞，不要所有全用同一种」「相同供应商的
      // 账号用同一种就行」)
      let kind_of = fn(e : Json?) {
        let g = text(e, "group")
        if g != "key" {
          g
        } else {
          let a = field(field(e, "profile"), "access")
          let pv = text(a, "provider")
          if pv != "" { pv } else { text(a, "kind") }
        }
      }
      let offer_kind = fn(l : Json?) {
        let rt = text(l, "runtime")
        if rt == "codex" { "chatgpt" } else { rt }
      }
      let chips : Map[String, Double] = Map([])
      for e in list {
        let e = Some(e)
        let k = kind_of(e)
        let w = @sf.nav_quota_line(c, field(field(e, "profile"), "quota"))
        chips[k] = dmax(chips.get(k).unwrap_or(0.0), w)
      }
      for o in offered {
        for l in o.1 {
          let l = Some(l)
          let k = offer_kind(l)
          let w = @sf.nav_quota_line(c, field(l, "quota"))
          chips[k] = dmax(chips.get(k).unwrap_or(0.0), w)
        }
      }
      for i, e in list {
        let e = Some(e)
        // (another row under it: the next of its group)
        let more = i + 1 < list.length() && text(Some(list[i + 1]), "group") == text(e, "group")
        if text(e, "group") != group {
          group = text(e, "group")
          @sf.list_heading(c, text(e, "groupTitle"), side_at())
        }
        let p = field(e, "profile")
        let route = profile_route(e)
        let usable = flag(e, "usable")
        // how it is where that is not simply fine, as the core says it, in its tone: what
        // needs a look in colour
        let trouble = text(field(e, "state"), "text")
        let tone = text(field(e, "state"), "tone")
        // its name and its allowance: its plan, where it can be used and which connects use it are its page's (the user,
        // 2026-11-14: 「额度的第二行感觉现在就一个有效信息」; the plan beside the name cut the name short in the narrowest
        // sidebar); the line under the name is only for what is wrong, and a balance where it has no windows.
        let quota = field(p, "quota")
        let ok = text(quota, "state") == "ok"
        let windows = ok && items(quota, "windows").length() > 0
        let credits = ok && !windows && text(quota, "creditsText") != ""
        nav_item(
            c,
            at=side_at(),
            "profiles/" + text(e, "key"),
            picked == Some(route),
            fn() { @sf.provider_logo(c, text(p, "runtime"), text(field(p, "access"), "kind"), nav_mark_side, text(p, "providerMark")) },
            // (a subscription by its account, a key by its name: the core's)
            fn() { nav_title(c, if text(p, "name") != "" { text(p, "name") } else { text(e, "title") }, away=!usable) },
            lines=fn() {
              if trouble != "" {
                @sf.list_row_line(c, fn() { c.text(trouble, style=nav_meta().then(trouble_ink(tone)).then(place_fill)) |> ignore })
              }
              if credits {
                @sf.list_row_line(c, fn() { c.text(text(quota, "creditsText"), style=nav_meta()) |> ignore })
              }
            },
            more~,
            foot?=if windows {
              let widest = chips.get(kind_of(e)).unwrap_or(0.0)
              Some(fn() { @sf.nav_quota_chips(c, quota, key="profiles/" + text(e, "key"), at=side_at(), widest~) })
            } else {
              None
            },
            foot_capsule?=if windows { Some(@sf.fill_chip_small_h) } else { None },
            // (its page in the pane once what it shows is answered, the pane as it was meanwhile, what it asked handed
            // to that page: sfbase's account_open.mbt)
            on_press=fn() {
              // (the one shown already: nothing to ask, nothing made anew to take it)
              if @signals.untracked(fn() { place_route(src, w, "profiles") }) == Some(route) {
                @sfbase.show_chosen()
                return
              }
              let at = match route {
                Route::Profile(station, id) => @sfbase.profile_shown_at(station, id)
                _ => ""
              }
              @sfbase.show_answered(src, @sfbase.route_asks(w.id, route), at, fn() {
                place_pick[place_key(w.id, "profiles")] = route
                @sfbase.show_chosen()
              })
            },
          )
      }
      // as the profiles' list says them; its allowance under each as a profile's row has it (the same chips), so an
      // account not added yet shows what is left of its week as well
      for o in offered {
        let s = Some(o.0)
        let station = text(s, "station")
        let offers = o.1
        if offers.length() == 0 {
          continue
        }
        @sf.list_heading(c, @sf.t("web-pages.profiles.machineSignedIn", args=[("station", text(s, "name"))]), side_at())
        for j, l in offers {
          let l = Some(l)
          let quota = field(l, "quota")
          let windows = text(quota, "state") == "ok" && items(quota, "windows").length() > 0
          let key = "profiles/machine/" + station + "/" + text(l, "runtime")
          nav_item(
              c,
              at=side_at(),
              key,
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
              foot?=if windows {
                let widest = chips.get(offer_kind(l)).unwrap_or(0.0)
                Some(fn() { @sf.nav_quota_chips(c, quota, key~, at=side_at(), widest~) })
              } else {
                None
              },
              foot_capsule?=if windows { Some(@sf.fill_chip_small_h) } else { None },
              on_press=fn() {
                @sfbase.history_push()
                app.nav.push(Setting(Route::NewProfile(station)))
                @sfbase.show_chosen()
              },
            )
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
/// What is wrong, in its tone: amber, red, or muted (neutral).
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
/// The words that give way first.
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
  let read = @sfbase.station_rows(src, w.id).value is Some(_)
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
              {
                let id = c.id("stations-first/add")
                @sf.button(c, @sf.t("web-pages.settings.stations.add"), key="stations-first/add", tone=Primary, icon="plus", on_press=fn() {
                  add(Of(id))
                })
                |> ignore
              }
            None => c.text(@sf.t("web-pages.settings.stations.noneYet"), style=desk_muted_line) |> ignore
          }
        },
      )
    },
  ])
}

///|
let pl_art_w : Double = 240.0

///|
// kept across runs: a value (no field of it changes)
let desk_muted_line : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)
