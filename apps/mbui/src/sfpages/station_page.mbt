// A station's own page, one in every frame, laid out by its width (page_look.mbt) (web/src/cloud/StationPage.tsx StationSettings, Head, Body, Overview,
// Settings, Machine; StationPage.css.ts): its head (its mark and name, which its managers change where they are, how it
// is and what it is, what is wrong with it, trying it again while away, its ⋯), then its parts one at a time: how it
// is and what runs on it (what is left of the machine, its screens, profiles, connects and folders), what it is let do
// and set to (macOS's grants, the tools logged in on it, its agents' variables, what its search finds, the workspaces
// it is in), its software and the machine. Everything said is the core's (its station view, its topics).



///|
fn station_page_reset() -> Unit {
  env_forms.clear()
  env_forms_made.val = 0
  env_fields.clear()
  env_seeded.clear()
  env_sent.clear()
  rs_shown.clear()
}

///|
/// The page's parts (Body's PARTS), in order.
// kept across runs: a table, never written
let station_part_names : Array[String] = ["overview", "processes", "settings", "machine"]

///|
/// A station's page (StationSettings, StationScreen), by its address: a wait until the stations are read; one gone,
/// its list. Its parts each as wide as the page's column (narrow, 12 from its sides, as its cards are); its head, with
/// its name, first (narrow: in place of the large title).
pub fn station_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame, address : String) -> Unit {
  let topic = @settings.stations_of(core, here)
  let manager = { let r = role_of(core, here); r == "owner" || r == "admin" }
  let back = "Station"
  match topic.value {
    Some(Array(list)) =>
      match list.search_by(fn(s) { text(Some(s), "station") == address }) {
        Some(i) => station_view(c, core, here, frame, Some(list[i]), manager)
        // (removed, or a link from before: its list)
        None => station_waiting(c, core, here, frame, back, "")
      }
    _ => station_waiting(c, core, here, frame, back, @sf.t("common.readingStations"))
  }
}

///|
/// Station `s`'s page: its head, then its parts one at a time.
fn station_view(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame, s : Json?, manager : Bool) -> Unit {
  let address = text(s, "station")
  let blocks : Array[() -> Unit] = [fn() { station_parts_choice(c, address) }]
  // (the part shown, by station: the settings' own, which a login's card also moves to 设置)
  let part = match @settings.station_parts.get(address) {
    Some(p) if station_part_names.contains(p) => p
    _ => "overview"
  }
  let body = match part {
    "processes" => station_processes(c, core, here, s)
    "settings" => station_settings(c, core, s, manager)
    "machine" => station_machine(c, core, s, manager)
    _ => station_overview(c, core, here, s)
  }
  blocks.append(body)
  // its head says its name: no title over it (StationSettings: Head, then Body)
  @sf.page(c, on_back=core.pop, frame~, "station/" + address, text(s, "name"), blocks, small=@sf.t("android-misc.bar.place.stations"), head=fn() {
    station_head(c, core, here, s, manager)
  })
}

///|
/// A station's page while the stations are read (`text` what it waits on): a made-up one's, in its bones.
pub fn station_waiting(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame, title : String, text : String) -> Unit {
  @sf.page_waiting(c, title, text~, fn() {
    station_view(c, core.quiet(), here, frame, Some(station_sample()), false)
  })
}

///|
/// The viewer's role in the workspace in view.
fn role_of(core : Core, here : Here) -> String {
  text(workspace_view(core, here).value, "role")
}

///|
/// A station made up, for what its page shows while the stations are read (station_view in its bones): its head, the
/// machine's figures, a few profiles.
fn station_sample() -> Json {
  let w = fn(n : Int) { Json::string(@sf.sample_words(n)) }
  let meter = fn(left : Int) -> Json { { "big": w(2), "unit": "%", "left": Json::number(left.to_double()), "level": "ok", "title": w(4), "total": w(5) } }
  let profile = fn(i : Int, n : Int) -> Json { { "id": Json::string("sample" + i.to_string()), "name": w(n), "modelsText": w(12) } }
  {
    "station": "sample",
    "name": w(5),
    "online": true,
    "version": w(4),
    "host": { "identity": w(10), "meters": [meter(70), meter(40), meter(60)] },
    "overview": { "profiles": [profile(0, 7), profile(1, 9), profile(2, 6)] },
  }
}

///|
/// Its head (Head): its mark (picked by its managers), its name (renamed by them), how it is (its dot before it), what
/// the machine is, its version, where it is from; what is wrong with it under them; at its end trying it again while
/// away or silent, its ⋯.
fn station_head(c : @ui.Ctx, core : Core, here : Here, s : Json?, manager : Bool) -> Unit {
  let t = @sf.theme()
  let address = text(s, "station")
  let id = text(s, "id")
  let name = text(s, "name")
  let online = flag(s, "online")
  let dot = if online { "online" } else { "offline" }
  let problems = items(s, "problems")
  let silent = problems.iter().any(fn(p) { text(Some(p), "key") == "silent" })
  // this machine's, not running here: started from here (本机 Station's 启动), read again as it starts
  let stopped = local_stopped(address)
  if stopped is Some(_) {
    ignore(c.every(@settings.local_read_ms))
  }
  let warnings = problems.map(fn(p) { (text(Some(p), "text"), text(Some(p), "level") == "red") })
  match local_failed_words(stopped) {
    "" => ()
    words => warnings.push((words, true))
  }
  let (state_text, state_busy) = match stopped {
    Some(_) => (local_stopped_words(stopped), text(stopped, "doing") != "")
    None => (text(s, "stateText"), flag(s, "stateBusy"))
  }
  let facts = [text(field(s, "host"), "identity")]
  if text(s, "version") != "" {
    facts.push("Station " + text(s, "version"))
  }
  facts.push(joined_text(s))
  @sf.own_head(
    c,
    fn(side) {
      // its mark: its managers pick it, by what it is called (图标)
      let mid = c.id("station-mark/" + address)
      if manager {
        if hit(c, mid) {
          open_mark_pick(core, name, text(s, "emoji"), text(s, "icon"), @sf.t("android-settings.station.emojiWhat"), fn(
            emoji,
            icon,
            done,
          ) {
            (core.call)(
              "workspace.renameStation",
              obj([("workspace", str(here.workspace)), ("station", str(id)), ("emoji", str(emoji)), ("icon", str(icon)), ("account", str(here.sub))]),
              done,
            )
          })
        }
      }
      let mb = c.box(
        style=@ui.style(w=Fixed(side), h=Fixed(side), align=ACenter, justify=JCenter),
        id=if manager { mid } else { 0 },
        label=if manager { @sf.t("android-settings.station.emoji") } else { "" },
        fn() {
          let emoji = text(s, "emoji")
          let icon = text(s, "icon")
          if @sf.has_station_mark(emoji, icon) {
            @sf.station_mark(c, emoji, icon, st_mark_glyph, t.p.text)
          } else {
            let letter = match name.iter().next() {
              Some(ch) => ch.to_string().to_upper()
              None => "?"
            }
            c.text(letter, style=st_mark_letter) |> ignore
          }
        },
      )
      if manager {
        c.semantics(mb, Button, id=mid)
      }
    },
    name,
    rename?=if manager { Some(fn() { station_rename(core, here, s) }) } else { None },
    rename_label=@sf.t("web-pages.settings.stations.rename"),
    lines=[join(facts, " · ")],
    // its dot before what it says of how it is (reconnecting …; this machine's, how it stands here: 已停止, 正在更新),
    // else before what the machine is
    dot=if state_text == "" { dot } else { "" },
    state?=if state_text != "" {
      Some(fn() {
        @sf.status_dot(c, if state_busy && stopped is Some(_) { "busy" } else { dot })
        c.text(state_text, style=if state_busy { st_fact_busy } else { st_fact }) |> ignore
      })
    } else {
      None
    },
    warnings~,
    actions=fn() {
      match stopped {
        Some(_) => station_start(c, core, stopped, address)
        None => if !online || silent { station_retry(c, core, s) }
      }
      if manager {
        @settings.doing_mark(
          c,
          is_doing(core, ["workspace.renameStation", "workspace.removeStation"], [("station", id)]),
          failed_of(core, ["workspace.renameStation", "workspace.removeStation"], [("station", id)]),
        )
        station_menu(c, core, here, s)
      }
    },
  )
}

///|
/// Where a station another workspace lent is from (StationCards.tsx joinedText): its home workspace's name, else that
/// it is another's; "" for one whose home is here.
fn joined_text(s : Json?) -> String {
  if !flag(s, "joined") {
    return ""
  }
  match opt_text(s, "home") {
    Some(h) => @sf.t("web-pages.stations.joinedFrom", args=[("name", h)])
    None => @sf.t("web-pages.stations.joinedElsewhere")
  }
}

///|
/// Its name asked anew (RenameStationDialog), kept when it changed (`workspace.renameStation`).
fn station_rename(core : Core, here : Here, s : Json?) -> Unit {
  let name = text(s, "name")
  ask(@sf.t("web-pages.settings.stations.rename"), name, @sf.t("web-pages.settings.stations.namePrompt"), @sf.t("common.save"), fn(
    line,
  ) {
    let to = line.trim(chars=" \t\n").to_owned()
    if to != "" && to != name {
      @settings.act(
        core,
        @sf.t("android-settings.station.renameWhat"),
        "workspace.renameStation",
        obj([("workspace", str(here.workspace)), ("station", str(text(s, "id"))), ("name", str(to)), ("account", str(here.sub))]),
        done=@sf.t("android-settings.renamed"),
      )
    }
  })
}

///|
/// Tried again now (RetryPill: the core's `client.wake`, every station at once): while it is, a ring before its word.
fn station_retry(c : @ui.Ctx, core : Core, s : Json?) -> Unit {
  let trying = flag(field(s, "link"), "retrying") || is_doing(core, ["client.wake"], [])
  if @sf.button(c, @sf.t("common.retry"), key="station-retry/" + text(s, "station"), tone=Ghost, busy=trying, disabled=trying) {
    @settings.act(
      core,
      @sf.t("common.retry"),
      "client.wake",
      obj([("away", Json::number(0.0)), ("network", Json::boolean(true)), ("retry", Json::boolean(true))]),
    )
  }
}

///|
/// Its 启动 where it is this machine's, not running here (local_stopped): no try at reaching it again, nothing there
/// to reach; while it is being started, installed or updated, busy.
fn station_start(c : @ui.Ctx, core : Core, local : Json?, address : String) -> Unit {
  let working = text(local, "doing") != ""
  if @sf.button(
      c,
      @sf.t("web-pages.localStation.start"),
      key="station-start/" + address,
      tone=Ghost,
      busy=working,
      disabled=working,
    ) {
    local_start(core, local)
  }
}

///|
/// Its ⋯ (edits.menu, without its 文件: its page opens them from its folders): renaming it, restarting it while it is
/// online (its launcher hands over, its sessions go on, what its advanced settings saved taking effect), removing it
/// from the workspace (asked first).
fn station_menu(c : @ui.Ctx, core : Core, here : Here, s : Json?) -> Unit {
  let address = text(s, "station")
  let key = "station-more/" + address
  if !@sf.icon_action(c, "more", key, @sf.t("common.more")) {
    return
  }
  let mid = c.id(key)
  let remove = fn() {
    confirm(
      @sf.t("web-pages.settings.stations.removeConfirm", args=[("name", text(s, "name"))]),
      @sf.t("web-pages.settings.stations.removeConfirmBody", args=[("name", "still.fail")]),
      @sf.t("web-pages.settings.stations.removeAction"),
      danger=true,
      // back to the list at once (the page of a station going has nothing to show), its answer said there
      fn() {
        (core.pop)()
        @settings.act(
          core,
          @sf.t("web-pages.settings.stations.remove"),
          "workspace.removeStation",
          obj([("workspace", str(here.workspace)), ("station", str(text(s, "id"))), ("account", str(here.sub))]),
          done=@sf.t("android-settings.station.removed"),
        )
      },
    )
  }
  @sf.menu(
    [
      Some(@sf.menu_item_of(@sf.t("web-pages.settings.stations.rename"), icon="edit", fn() { station_rename(core, here, s) })),
      if flag(s, "online") {
        Some(@sf.menu_item_of(@sf.t("web-pages.settings.stations.restart"), icon="power", fn() {
          @settings.act(core, @sf.t("web-pages.settings.stations.restartWhat"), "station.restart",
            obj([("station", str(address))]), done=@sf.t("web-pages.settings.stations.restarting"))
        }))
      } else {
        None
      },
      Some(@sf.menu_item_of(@sf.t("web-pages.settings.stations.remove"), icon="trash", danger=true, remove)),
    ],
    from=Of(mid),
    along=End,
  )
}

///|
/// The parts to pick from (Body's Segmented): as wide as their names, at the column's start.
fn station_parts_choice(c : @ui.Ctx, address : String) -> Unit {
  let at = match @settings.station_parts.get(address) {
    Some(p) => station_part_names.search(p).unwrap_or(0)
    None => 0
  }
  c.box(style=st_parts, fn() {
    let picked = @sf.page_choice(
      c,
      "station-parts/" + address,
      station_part_names.map(fn(p) { @sf.t("web-pages.stations.page.part." + p) }),
      at,
    )
    if picked != at {
      @settings.station_parts[address] = station_part_names[picked]
    }
  })
  |> ignore
}

///|
/// A section of the page (ui Section), its count beside its title.
fn st_section(
  c : @ui.Ctx,
  title : String,
  body : () -> Unit,
  count? : Int = 0,
  description? : String = "",
  actions? : () -> Unit,
) -> Unit {
  @sf.section(
    c,
    title,
    body,
    note=description,
    actions?,
    title_after?=if count > 0 {
      Some(fn() { c.text(count.to_string(), style=st_count) |> ignore })
    } else {
      None
    },
  )
}

// ── Overview ────────────────────────────────────────────────────────────

///|
/// How it is and what runs on it (Overview): what is left of the machine (and what its agents take of it), its
/// screens, profiles, connects and folders, and what else of it has a page of its own.
fn station_overview(c : @ui.Ctx, core : Core, here : Here, s : Json?) -> Array[() -> Unit] {
  let address = text(s, "station")
  let o = field(s, "overview")
  let host = match field(s, "host") {
    Some(Object(_)) as h => h
    _ => None
  }
  let online = flag(s, "online")
  let out : Array[() -> Unit] = []
  if online && host is Some(_) {
    out.push(fn() {
      st_section(c, @sf.t("web-pages.stations.page.resources"), fn() {
        @sf.group(c, fn() {
          @sf.block(c, fn() {
            meter_dials(c, items(host, "meters"))
            match (core.topic)("stationNet", { "station": str(address) }).value {
              Some(Object(_)) as net => station_net(c, net)
              _ => ()
            }
            if items(o, "processes").length() > 0 {
              c.text(text(o, "processesText"), style=st_memory) |> ignore
            }
            // what still.fail itself uses of the machine, opening its 进程 (Uses: read while shown)
            match items(resources_of(core, here, address), "stations") {
              [u, ..] => station_uses(c, address, Some(u))
              [] => ()
            }
          })
        })
      })
    })
  }
  // its screens (docs/remote-screens.md); one from before them says so quietly
  match (core.topic)("screens", { "station": str(address) }).value {
    Some(Object(_)) as v => {
      let screens = items(v, "screens")
      let note = text(v, "note")
      if screens.length() > 0 || note != "" {
        out.push(fn() {
          st_section(c, @sf.t("web-pages.screen.section"), count=screens.length(), fn() {
            @sf.group(c, fn() {
              for sc in screens {
                let sv = Some(sc)
                let access = field(sv, "access")
                let lacks = access is Some(Object(_)) && (!flag(access, "capture") || !flag(access, "control"))
                // this machine's own display: said so, not opened (own_screen)
                let own = own_screen(address, text(sv, "id"))
                if @sf.link_row(
                    c,
                    "station-screen/" + address + "/" + text(sv, "id"),
                    text(sv, "title"),
                    // what it lacks says so in its line (the core's: what cannot be done now)
                    note=if own { @sf.t("android-misc.screen.here") } else { text(sv, "line") },
                    lacks=lacks && !own,
                    goes=!own,
                    lead=fn() { st_row_mark(c, if text(sv, "kind") == "browser" { "web" } else { "monitor" }) },
                  ) {
                  @sfbase.open_page(Screen({ station: address, screen: text(sv, "id"), title: text(sv, "title"), until_gone: false }))
                }
              }
              if screens.length() == 0 {
                @sf.link_row(c, "", note, goes=false, lead=fn() { st_row_mark(c, "monitor") }) |> ignore
              }
            })
          })
        })
      }
    }
    _ => ()
  }
  let profiles = items(o, "profiles")
  if profiles.length() > 0 {
    out.push(fn() {
      st_section(c, "Profile", count=profiles.length(), fn() {
        @sf.group(c, fn() {
          for p in profiles {
            station_profile_row(c, core, address, Some(p))
          }
        })
      })
    })
  }
  let connects = items(o, "connects")
  if connects.length() > 0 {
    out.push(fn() {
      st_section(c, @sf.t("web-pages.settings.nav.connects"), count=connects.length(), fn() {
        @sf.group(c, fn() {
          for cn in connects {
            let cv = Some(cn)
            if @sf.link_row(
                c,
                "station-connect/" + address + "/" + text(cv, "id"),
                text(cv, "name"),
                note=join([text(cv, "team"), text(cv, "runText")], " · "),
                value=if text(cv, "presence") != "online" { text(cv, "statusText") } else { "" },
                lead=fn() { @sf.status_dot(c, text(cv, "presence")) },
              ) {
              (core.push)(Connect(address, text(cv, "id")))
            }
          }
        })
      })
    })
  }
  // its drive (docs/drive.md): opened whole from here, or at one of the folders pinned
  match field(o, "drive") {
    Some(Object(_)) as drive => {
      let roots = items(drive, "roots")
      out.push(fn() {
        st_section(
          c,
          @sf.t("web-pages.drive.title"),
          count=roots.length(),
          actions=fn() {
            if @sf.action(c, "station-files/" + address, @sf.t("web-pages.stations.page.openFiles"), icon="folder") {
              @sfbase.open_page(Drive({ station: address, root: None, path: "" }))
            }
          },
          fn() {
            @sf.group(c, fn() {
              if roots.length() == 0 {
                @sf.said_row(c, @sf.t("web-pages.drive.noneYet"), "")
              }
              for r in roots {
                let rv = Some(r)
                if @sf.link_row(
                    c,
                    "station-folder/" + address + "/" + text(rv, "path"),
                    text(rv, "name"),
                    note=text(rv, "path"),
                    lead=fn() { st_row_mark(c, "folder") },
                  ) {
                  @sfbase.open_page(Drive({ station: address, root: Some(text(rv, "path")), path: "" }))
                }
              }
            })
          },
        )
      })
    }
    _ => ()
  }
  // what else of it has a page of its own: its memory, this device's adb lent to its agents (AdbShare)
  out.push(fn() {
    st_section(c, @sf.t("web-pages.stations.page.more"), fn() {
      @sf.group(c, fn() {
        if @sf.link_row(c, "st-memory/" + address, @sf.t("android-settings.memory")) {
          (core.push)(Memory(address))
        }
        // (共享调试 is no station's: a chat's agent asks for the phone, and settings' 共享调试 is where it stands)
      })
    })
  })
  out
}

///|
/// A row's mark (a screen's, a folder's, a grant's): its icon in the muted ink.
fn st_row_mark(c : @ui.Ctx, icon : String) -> Unit {
  @sf.icon(c, icon, size=st_row_glyph, color=@sf.theme().p.muted) |> ignore
}

///|
let st_row_glyph : Double = 16.0

///|
/// A profile of it (ProfileCard, as the Profile page lists it): its maker's mark, its name and its check where not
/// well, its models and who uses it under them, its allowance under that; the whole of it its page.
fn station_profile_row(c : @ui.Ctx, core : Core, address : String, p : Json?) -> Unit {
  let used = items(p, "usedBy").length()
  let facts = [text(p, "modelsText")]
  if used > 0 {
    facts.push(@sf.t("web-pages.settings.profiles.usedBy", args=[("n", used.to_string())]))
  }
  if @sf.link_row(
      c,
      "station-profile/" + address + "/" + text(p, "id"),
      text(p, "name"),
      note=join(facts, " · "),
      lead=fn() {
        c.box(style=st_profile_mark, fn() { @sf.maker_mark(c, text(p, "providerMark"), text(p, "runtime"), st_profile_glyph) |> ignore })
        |> ignore
      },
      // (its allowance under what it is, a line of its own: as the profiles' page lists it)
      below?=if text(field(p, "quota"), "state") == "ok" {
        Some(fn() { @sf.quota_chips(c, field(p, "quota"), small=true, key="station-profile/" + address + "/" + text(p, "id")) })
      } else {
        None
      },
      tail=fn() {
        if text(p, "checkTone") != "green" && text(p, "checkText") != "" {
          @sf.pill(
            c,
            text(p, "checkText"),
            tone=match text(p, "checkTone") {
              "red" => Red
              "amber" => Amber
              "blue" => Blue
              _ => Neutral
            },
          )
        }
      },
    ) {
    (core.push)(Profile(address, text(p, "id")))
  }
}

// ── Settings ────────────────────────────────────────────────────────────

///|
/// What it is let do and set to (Settings): the grants macOS gives it, the tools logged in on it, the programs of its
/// machine granted its data, its agents' variables, what its search finds, the workspaces it is in.
fn station_settings(c : @ui.Ctx, core : Core, s : Json?, manager : Bool) -> Array[() -> Unit] {
  let address = text(s, "station")
  let o = field(s, "overview")
  let online = flag(s, "online")
  let out : Array[() -> Unit] = []
  match field(o, "permissions") {
    Some(Object(_)) as p if online => out.push(fn() { station_permissions(c, core, address, p) })
    _ => ()
  }
  out.push(fn() { station_logins(c, core, address) })
  // (asked for only when the station's overview says there are some)
  match field(o, "outflowGrants") {
    Some(Number(n, ..)) if n > 0.0 => out.push(fn() { station_outflow(c, core, address, flag(o, "outflowAnswers")) })
    _ => ()
  }
  match field(o, "agentEnv") {
    Some(Array(env)) => out.push(fn() { station_env(c, core, address, env, manager) })
    _ => ()
  }
  match field(o, "search") {
    Some(Object(_)) as search if online && text(search, "files") == "spotlight" =>
      out.push(fn() { station_search(c, core, address, search, manager) })
    _ => ()
  }
  match field(o, "context") {
    Some(Object(_)) as context => out.push(fn() { station_context(c, core, address, context, manager) })
    _ => ()
  }
  match field(o, "diagnostics") {
    Some(Object(_)) as diagnostics => out.push(fn() { station_diagnostics(c, core, address, diagnostics, manager) })
    _ => ()
  }
  match field(o, "elevation") {
    Some(Object(_)) as elevation if online => out.push(fn() { station_elevation(c, core, address, elevation) })
    _ => ()
  }
  if manager {
    out.push(fn() { station_workspaces(c, core, address) })
  }
  match field(o, "network") {
    Some(Object(_)) as network => out.push(fn() { station_network(c, core, address, network, manager) })
    _ => ()
  }
  out
}

///|
/// What macOS lets its still.fail Helper do (PermissionsSection): a row each, what it is for, given or not; one not
/// given asked for from here (`permissions.request`), its screen opened where it can be driven.
fn station_permissions(c : @ui.Ctx, core : Core, address : String, p : Json?) -> Unit {
  st_section(c, @sf.t("web-pages.stations.permissions.section"), description=text(p, "note"), fn() {
    @sf.group(c, fn() {
      for g in items(p, "grants") {
        let gv = Some(g)
        let gid = text(gv, "id")
        let end = if flag(gv, "granted") {
          "granted"
        } else if flag(gv, "asking") {
          if text(p, "screen") != "" { "open" } else { "waiting" }
        } else if flag(p, "canRequest") {
          "request"
        } else {
          "missing"
        }
        @sf.link_row(
          c,
          "",
          text(gv, "name"),
          note=text(gv, "line"),
          value=match end {
            "granted" => @sf.t("web-pages.stations.permissions.granted")
            "waiting" => @sf.t("web-pages.stations.permissions.waiting")
            "missing" => @sf.t("web-pages.stations.permissions.missing")
            _ => ""
          },
          goes=false,
          lead=fn() { st_row_mark(c, grant_icon(gid)) },
          tail=fn() {
            match end {
              "open" =>
                if @sf.button(c, @sf.t("web-pages.stations.permissions.openScreen"), key="grant-open/" + address + "/" + gid) {
                  open_screen_link(core, text(p, "screen"))
                }
              "request" => {
                let busy = is_doing(core, ["permissions.request"], [("station", address), ("grant", gid)])
                if @sf.button(
                    c,
                    @sf.t("web-pages.stations.permissions.request"),
                    key="grant-request/" + address + "/" + gid,
                    tone=Primary,
                    busy~,
                    disabled=busy,
                  ) {
                  let screen = text(p, "screen")
                  @settings.act(
                    core,
                    @sf.t("web-pages.stations.permissions.requestWhat", args=[("name", text(gv, "name"))]),
                    "permissions.request",
                    obj([("station", str(address)), ("grant", str(gid))]),
                    then=fn(answer) {
                      if text(Some(answer), "window") == "up" && flag(Some(answer), "screen") && screen != "" {
                        open_screen_link(core, screen)
                      }
                    },
                  )
                }
              }
              _ => ()
            }
          },
        )
        |> ignore
      }
    })
  })
}

///|
/// A grant's mark (StationPermissions.tsx GRANT_MARK): the screen's two by what they do, the folders by what they
/// hold, the LAN by the devices on it.
fn grant_icon(id : String) -> String {
  match id {
    "capture" => "monitor"
    "control" => "cursor"
    "documents" => "file-text"
    "downloads" => "download"
    "removable" => "disk"
    "network" => "server"
    "localNetwork" => "devices"
    _ => "folder"
  }
}

///|
/// A screen the core links to, opened as the core reads its link (`link.parse`).
fn open_screen_link(core : Core, link : String) -> Unit {
  (core.call)("link.parse", obj([("url", str(link))]), fn(r) {
    match r {
      Ok(Object(_) as v) if text(Some(v), "opens") == "screen" =>
        @sfbase.open_page(Screen({ station: text(Some(v), "station"), screen: text(Some(v), "screen"), title: "", until_gone: false }))
      _ => ()
    }
  })
}

///|
/// Its agents' variables (AgentEnv, AgentEnvEditor): its managers edit them as a .env file's lines in the core's
/// draft (`agentEnvForm`), saved with 保存; the others see them, a secret's value masked.
fn station_env(c : @ui.Ctx, core : Core, address : String, env : Array[Json], manager : Bool) -> Unit {
  if manager {
    st_section(c, @sf.t("web-pages.stations.agentEnv"), description=@sf.t("web-pages.stations.agentEnvLead"), fn() {
      @sf.page_card(c, footed=true, fn() { station_env_editor(c, core, address) })
    })
    return
  }
  if env.length() == 0 {
    return
  }
  st_section(c, @sf.t("web-pages.stations.agentEnv"), fn() {
    @sf.group(c, fn() {
      for e in env {
        @sf.link_row(c, "", text(Some(e), "key"), note=text(Some(e), "value"), goes=false) |> ignore
      }
    })
  })
}

///|
/// The draft of a station's variables open while the page shows it, by station (its form's key).
// kept across runs: said as the page opens one; station_page_reset empties it
let env_forms : Map[String, String] = {}

///|
// kept across runs: counted as forms are opened; station_page_reset puts it back
let env_forms_made : Ref[Int] = Ref(0)

///|
/// The field of a station's variables, by station.
// kept across runs: made as a page first shows one; station_page_reset empties it
let env_fields : Map[String, @ui.Field] = {}

///|
/// The editor (AgentEnvEditor): the field, what is wrong under it (a line the core cannot take), 取消 while changed,
/// 保存.
fn station_env_editor(c : @ui.Ctx, core : Core, address : String) -> Unit {
  let form = match env_forms.get(address) {
    Some(f) => f
    None => {
      env_forms_made.val += 1
      let f = "mbui-env-" + env_forms_made.val.to_string()
      env_forms[address] = f
      c.tell("env-open/" + f, fn() {
        @settings.act(core, @sf.t("web-pages.stations.agentEnvRead"), "agentEnv.form.open", obj([("station", str(address)), ("form", str(f))]))
      })
      f
    }
  }
  let d = (core.topic)("agentEnvForm", { "station": str(address), "form": str(form) }).value
  let field_ = match env_fields.get(address) {
    Some(f) => f
    None => {
      let f = @ui.Field::new()
      env_fields[address] = f
      f
    }
  }
  // what the core has, once it has it (again after 取消); after, what it comes to says the field too while nothing
  // typed here since waits on it (a save elsewhere, the draft read again): what is typed is the field's
  if d is Some(Object(_)) && !flag(d, "pending") {
    let now = text(d, "text")
    match env_seeded.get(address) {
      None => {
        env_seeded[address] = now
        // (what was typed before it came is kept, and goes to the draft as typed: never wiped by it)
        if field_.text() == "" {
          field_.set(now)
        }
      }
      Some(was) if was != now => {
        if field_.text() == was {
          field_.set(now)
        }
        env_seeded[address] = now
      }
      _ => ()
    }
  }
  let saving = is_doing(core, ["agentEnv.form.save"], [("station", address), ("form", form)])
  c.box(style=st_editor, fn() {
    // (first in its card, in its corners on the words' inset: the ladder's small block's corner there)
    let typed = @sf.textarea(c, "env/" + address, rows=6, field=field_, placeholder=env_placeholder, corner=@sf.small_corner)
    if env_seeded.contains(address) && typed != text(d, "text") && typed != env_sent.get(address).unwrap_or("") {
      env_sent[address] = typed
      c.tell("env-edit/" + form, fn() {
        @settings.act(
          core,
          @sf.t("web-pages.stations.agentEnvEdit"),
          "agentEnv.form.edit",
          obj([("station", str(address)), ("form", str(form)), ("input", obj([("text", str(typed))]))]),
        )
      })
    }
    // what is wrong, a line each
    let read = d is Some(Object(_)) && text(d, "text") == typed
    if read {
      let problems : Array[(Int, String, Bool)] = []
      for i, l in items(d, "lines") {
        let lv = Some(l)
        if text(lv, "problem") != "" {
          problems.push((i + 1, text(lv, "problem"), flag(lv, "error")))
        }
      }
      if problems.length() > 0 {
        c.box(style=st_env_problems, fn() {
          for p in problems {
            c.text(
              @sf.t("web-pages.stations.agentEnvLine", args=[("line", p.0.to_string()), ("problem", p.1)]),
              style=if p.2 { st_problem_bad } else { st_problem },
            )
            |> ignore
          }
        })
        |> ignore
      }
    }
    @sf.card_foot(c, at_end=true, fn() {
      if flag(d, "dirty") &&
        @sf.button(c, @sf.t("common.cancel"), key="env-reset/" + address, tone=Ghost) {
        env_seeded.remove(address)
        env_sent.remove(address)
        @settings.act(
          core,
          @sf.t("web-pages.stations.agentEnvEdit"),
          "agentEnv.form.edit",
          obj([("station", str(address)), ("form", str(form)), ("input", obj([("reset", Json::boolean(true))]))]),
        )
      }
      let can = d is Some(Object(_)) && flag(d, "dirty") && !flag(d, "pending") && !saving && read && count(d, "errors") == 0
      if @sf.button(c, @sf.t("common.save"), key="env-save/" + address, tone=Primary, busy=saving, disabled=!can) {
        @settings.act(
          core,
          @sf.t("web-pages.stations.agentEnvSave"),
          "agentEnv.form.save",
          obj([("station", str(address)), ("form", str(form))]),
          done=@sf.t("web-pages.profiles.saved"),
        )
      }
    })
  })
  |> ignore
}

///|
/// What of the core's a station's field last took (first, again after 取消, or as it changed with nothing typed since),
/// and what was last sent of it.
// kept across runs: said as the field is filled and typed in; station_page_reset empties them
let env_seeded : Map[String, String] = {}

///|
// kept across runs: said as what is typed is sent; station_page_reset empties it
let env_sent : Map[String, String] = {}

///|
let env_placeholder : String = "HTTPS_PROXY=http://127.0.0.1:7890\nNO_PROXY=localhost,.internal"

///|
/// What its search finds of the machine (SearchSection): whether the person's own mail and the like are found too, said
/// by the workspace's managers (others read it).
fn station_search(c : @ui.Ctx, core : Core, address : String, search : Json?, manager : Bool) -> Unit {
  st_section(c, @sf.t("web-pages.stations.search.section"), fn() {
    @sf.group(c, fn() {
      let busy = is_doing(core, ["search.setPersonal"], [("station", address)])
      let on = flag(search, "personal")
      let now = @sf.switch_row(
        c,
        "search-personal/" + address,
        @sf.t("web-pages.stations.search.personal"),
        on,
        note=@sf.t("web-pages.stations.search.personalLine"),
        disabled=!manager,
        busy~,
      )
      if now != on {
        @settings.act(
          core,
          @sf.t("web-pages.stations.search.what"),
          "search.setPersonal",
          obj([("station", str(address)), ("personal", Json::boolean(now))]),
        )
      }
    })
  })
}

///|
/// What it sends still.fail to find its problems by (StationDiagnostics.tsx): whether its log goes, scrubbed, said by the
/// workspace's managers (others read it).
fn station_diagnostics(c : @ui.Ctx, core : Core, address : String, diagnostics : Json?, manager : Bool) -> Unit {
  st_section(c, @sf.t("web-pages.stations.diagnostics.section"), fn() {
    @sf.group(c, fn() {
      let busy = is_doing(core, ["diagnostics.setLogs"], [("station", address)])
      let on = flag(diagnostics, "logs")
      let now = @sf.switch_row(
        c,
        "diagnostics-logs/" + address,
        @sf.t("web-pages.stations.diagnostics.logs"),
        on,
        note=@sf.t("web-pages.stations.diagnostics.logsLine"),
        disabled=!manager,
        busy~,
      )
      if now != on {
        @settings.act(
          core,
          @sf.t("web-pages.stations.diagnostics.what"),
          "diagnostics.setLogs",
          obj([("station", str(address)), ("logs", Json::boolean(now))]),
        )
      }
    })
  })
}

///|
/// How it goes on with a session whose prompt cache is over (StationContext.tsx ContextSection): whether a person's
/// message to an agent at rest whose large context's cache is over starts it afresh by itself, said by the workspace's
/// managers (others read it).
fn station_context(c : @ui.Ctx, core : Core, address : String, context : Json?, manager : Bool) -> Unit {
  st_section(c, @sf.t("web-pages.stations.context.section"), fn() {
    @sf.group(c, fn() {
      let busy = is_doing(core, ["context.setAfresh"], [("station", address)])
      let on = flag(context, "afreshWhenCold")
      let now = @sf.switch_row(
        c,
        "context-afresh/" + address,
        @sf.t("web-pages.stations.context.afresh"),
        on,
        note=@sf.t("web-pages.stations.context.afreshLine"),
        disabled=!manager,
        busy~,
      )
      if now != on {
        @settings.act(
          core,
          @sf.t("web-pages.stations.context.what"),
          "context.setAfresh",
          obj([("station", str(address)), ("afreshWhenCold", Json::boolean(now))]),
        )
      }
    })
  })
}

///|
/// Whether a Windows station runs as the machine's administrator (StationElevation.tsx ElevationSection): switched by
/// the workspace's managers, Windows asking on the machine and the station restarting; what it means or how a change
/// goes under it, how the last one failed under that.
fn station_elevation(c : @ui.Ctx, core : Core, address : String, elevation : Json?) -> Unit {
  st_section(c, @sf.t("web-pages.stations.elevation.section"), fn() {
    @sf.group(c, fn() {
      let busy = is_doing(core, ["elevation.set"], [("station", address)]) || flag(elevation, "busy")
      let on = flag(elevation, "on")
      let now = @sf.switch_row(
        c,
        "elevation/" + address,
        @sf.t("web-pages.stations.elevation.admin"),
        on,
        note=text(elevation, "line"),
        disabled=!flag(elevation, "canChange"),
        busy~,
      )
      if now != on {
        @settings.act(
          core,
          @sf.t("web-pages.stations.elevation.what"),
          "elevation.set",
          obj([("station", str(address)), ("on", Json::boolean(now))]),
        )
      }
    })
    if text(elevation, "failed") != "" {
      c.text(text(elevation, "failed"), style=st_problem_bad) |> ignore
    }
  })
}

///|
/// Advanced controls stay folded until asked for: opened, they are rows of its card under the row that folds them, as
/// a vault's accounts are; selection is stored for the next station start.
fn station_network(c : @ui.Ctx, core : Core, address : String, network : Json?, manager : Bool) -> Unit {
  @sf.group(c, fn() {
    let open = @settings.station_network_open.get(address).unwrap_or(false)
    if @sf.link_row(c, "network-open/" + address, @sf.t("web-pages.stations.network.advanced"), folds=open) {
      @settings.station_network_open[address] = !open
    }
    if open {
      @sf.setting(c, @sf.t("web-pages.stations.network.algorithm"), note=@sf.t("web-pages.stations.network.note"), fn() {
        let busy = is_doing(core, ["network.setCongestion"], [("station", address)])
        @sf.select(c, "network-select/" + address, text(network, "congestion"),
          ["cubic", "bbr"].map(fn(algorithm) { (algorithm, @sf.t("web-pages.stations.network." + algorithm)) }),
          fn(algorithm) {
            @settings.act(core, @sf.t("web-pages.stations.network.what"), "network.setCongestion",
              obj([("station", str(address)), ("congestion", str(algorithm))]), done=@sf.t("web-pages.stations.network.saved"))
          }, label=@sf.t("web-pages.stations.network.algorithm"), disabled=!manager || busy, whole=true)
      })
    }
  })
}

///|
/// The workspaces it is in (Workspaces), for its home's owners and admins once it is in more than one: its home
/// first, what each has of the machine.
fn station_workspaces(c : @ui.Ctx, core : Core, address : String) -> Unit {
  let m = (core.topic)("memberships", { "station": str(address) }).value
  let ws = items(m, "workspaces")
  if !flag(m, "manages") || ws.length() < 2 {
    return
  }
  st_section(c, "Workspace", count=ws.length(), description=@sf.t("web-pages.stations.workspacesLead"), fn() {
    @sf.group(c, fn() {
      for w in ws {
        let wv = Some(w)
        let name = text(wv, "name")
        @sf.said_row(c, name, text(wv, "line"), lead=fn(c) {
          @sf.workspace_badge(c, name, text(wv, "emoji"), text(wv, "icon"), st_ws_mark)
        })
      }
    })
  })
}

///|
/// A workspace's mark before its name (StationPage.tsx WorkspaceNamed: 16).
let st_ws_mark : Double = 16.0

// ── Machine ─────────────────────────────────────────────────────────────

///|
/// Its software and the machine (Machine): its versions (updated by its home's managers), then what the machine is.
fn station_machine(c : @ui.Ctx, core : Core, s : Json?, manager : Bool) -> Array[() -> Unit] {
  let o = field(s, "overview")
  let online = flag(s, "online")
  let updates = items(o, "updates")
  let host = match field(s, "host") {
    Some(Object(_)) as h => h
    _ => None
  }
  [
    fn() {
      st_section(c, @sf.t("web-pages.stations.software"), fn() {
        @sf.group(c, fn() {
          if online {
            software_list(c, core, text(s, "station"), updates, manager, flag(s, "betaOffered"))
          } else {
            @sf.said_row(c, @sf.t("web-pages.stations.softwareOffline"), "")
          }
          if updates.length() == 0 && text(s, "version") != "" {
            @sf.said_row(c, "Station " + text(s, "version"), "")
          }
        })
      })
    },
    fn() {
      st_section(c, @sf.t("web-pages.stations.device"), fn() {
        @sf.group(c, fn() {
        match host {
          Some(_) => {
            let details = items(host, "details")
            let footprint = text(field(o, "footprint"), "text")
            let rows : Array[(String, String)] = details.map(fn(d) { (text(Some(d), "label"), text(Some(d), "value")) })
            if footprint != "" {
              rows.push((@sf.t("web-pages.stations.page.footprint"), footprint))
            }
            @sf.block(c, fn() { host_details(c, rows) })
          }
          None =>
            @sf.said_row(
              c,
              if online {
                @sf.t("web-pages.stations.deviceLoading")
              } else {
                @sf.t("web-pages.stations.deviceOffline")
              },
              "",
            )
        }
        })
      })
    },
  ]
}

// ── styles (StationPage.css.ts, settings.css.ts workspaceHead) ──────────

///|
let st_mark_glyph : Double = 28.0

///|
let st_profile_glyph : Double = 18.0

///|
let st_grant_glyph : Double = 18.0

///|
// kept across runs: a value (no field of it changes)
let st_mark_letter : @ui.TextStyle = @ui.text_style(size=Heading, weight=Semibold, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let st_fact : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)

///|
/// Between the facts' lines (workspaceFacts: 4).
let st_facts_line : Double = 4.0

///|
// kept across runs: a value (no field of it changes)
let st_fact_busy : @ui.TextStyle = st_fact.then(@ui.text_style(color=AccentText))

///|
/// The parts to pick from, as far over what they show as the page's blocks are (page_choice's).
// kept across runs: a value (no field of it changes)
let st_parts : @ui.Style = @ui.css("row w=Full")

///|
/// A section's count beside its title (titleCount: 8 after it, 500, subtle).
// kept across runs: a value (no field of it changes)
let st_count : @ui.TextStyle = @ui.text_style(size=Meta, leading=L7, weight=Medium, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let st_memory : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, w=Full)

///|
/// A profile's maker's mark leading its row: a tile in the row's corner the ladder's inset in, concentric with it (the
/// small block's 10), not a circle, which no row's corner there could hold concentric (the user, 2026-10-25: 不用圆形就行了).
// kept across runs: a value (no field of it changes)
let st_profile_mark : @ui.Style = @ui.css("w=S9 h=S9 bg=Neutral align=ACenter justify=JCenter").then(
  @ui.style(radius=@sf.small_radius),
)

///|
// kept across runs: a value (no field of it changes)
let st_grant_mark : @ui.Style = @ui.css("w=S9 h=S9 radius=Full bg=Neutral align=ACenter justify=JCenter")


///|
// kept across runs: a value (no field of it changes)
let st_env_problems : @ui.Style = @ui.css("w=Full gap=S1")

///|
/// A card's buttons at its foot, at its end (cardActions: 8 apart).
// kept across runs: a value (no field of it changes)
let st_card_actions : @ui.Style = @ui.css("row w=Full gap=S2 justify=JEnd")

///|
/// A st_footed_card's buttons at its end, reaching past its words to its foot corner's.
fn st_foot_actions() -> @ui.Style {
  st_card_actions.then(@sf.foot_across(@sf.button_height()))
}

///|
/// The variables' editor on its card: the field, what is wrong under it, its buttons, 12 apart.
// kept across runs: a value (no field of it changes)
let st_editor : @ui.Style = @ui.css("w=Full gap=S3")

///|
/// A line of the variables the core cannot take (the meta's 12, muted; red where it is an error).
// kept across runs: a value (no field of it changes)
let st_problem : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let st_problem_bad : @ui.TextStyle = st_problem.then(@ui.text_style(color=Danger))
