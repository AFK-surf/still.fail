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
fn station_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame, address : String) -> Unit {
  let look = look_of(c)
  let topic = @settings.stations_of(core, here)
  let manager = { let r = role_of(core, here); r == "owner" || r == "admin" }
  let back = "Station"
  match topic.value {
    Some(Array(list)) =>
      match list.search_by(fn(s) { text(Some(s), "station") == address }) {
        Some(i) => {
          let s = Some(list[i])
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
          let parts = blocks.map(fn(b) { fn() { cn_gutter(c, look, b) } })
          // its head says its name: no title over it (StationSettings: Head, then Body)
          look_page(c, core, frame, look, "station/" + address, text(s, "name"), parts, head=fn() {
            station_head(c, core, here, s, manager)
          })
        }
        // (removed, or a link from before: its list)
        None => look_page(c, core, frame, look, "station/" + address, back, [fn() { cn_gutter(c, look, fn() { @sf.waiting(c, shape=Cards) }) }])
      }
    _ =>
      look_page(c, core, frame, look, "station/" + address, back, [
        fn() {
          cn_gutter(c, look, fn() {
            @sf.waiting(c, shape=Cards, note={ reading: true, text: @sf.t("common.readingStations"), failing: [] })
          })
        },
      ])
  }
}

///|
/// The viewer's role in the workspace in view.
fn role_of(core : Core, here : Here) -> String {
  text(workspace_view(core, here).value, "role")
}

///|
/// Its head (Head): its mark (picked by its managers), its name (renamed by them where it is), how it is (its dot
/// before it), what the machine is, its version, where it is from; what is wrong with it under them; at its end trying
/// it again while away or silent, its ⋯.
fn station_head(c : @ui.Ctx, core : Core, here : Here, s : Json?, manager : Bool) -> Unit {
  let t = @sf.theme()
  let address = text(s, "station")
  let id = text(s, "id")
  let name = text(s, "name")
  let online = flag(s, "online")
  let problems = items(s, "problems")
  let silent = problems.iter().any(fn(p) { text(Some(p), "key") == "silent" })
  c.box(style=st_head, fn() {
    // its mark: its managers pick it
    let mid = c.id("station-mark/" + address)
    if manager {
      c.cursor(mid, Hand)
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
    // (called what it is for: its name to a screen reader and to a scripted run's tap)
    let mark_label = if manager { @sf.t("android-settings.station.emoji") } else { "" }
    let mb = c.box(style=st_mark, id=if manager { mid } else { 0 }, label=mark_label, fn() {
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
    })
    if manager {
      c.semantics(mb, Button, id=mid)
    }
    c.box(style=st_identity, fn() {
      // its name: its managers rename it where it is
      let nid = c.id("station-name/" + address)
      if manager {
        c.cursor(nid, IBeam)
        if hit(c, nid) {
          station_rename(core, here, s)
        }
      }
      c.box(style=if manager { st_name_box } else { st_name_still }, id=if manager { nid } else { 0 }, fn() {
        c.text(name, style=st_name) |> ignore
      })
      |> ignore
      // (on as many lines as they take, each with the dot before it: workspaceFacts' flex-wrap)
      c.box(style=st_facts, flow=true, line_gap=st_facts_line, fn() {
        // (its dot before how it is, or with nothing to say of that, before its first fact)
        let state = text(s, "stateText")
        let dot = fn() { @sf.status_dot(c, if online { "online" } else { "offline" }) }
        if state != "" {
          c.box(style=st_status, fn() {
            dot()
            c.text(state, style=if flag(s, "stateBusy") { st_fact_busy } else { st_fact }) |> ignore
          })
          |> ignore
        }
        let facts = [text(field(s, "host"), "identity")]
        if text(s, "version") != "" {
          facts.push("Station " + text(s, "version"))
        }
        facts.push(joined_text(s))
        let mut first = state == ""
        for f in facts {
          if f != "" {
            let lead = first
            first = false
            c.box(style=if lead { st_status } else { st_fact_part }, fn() {
              if lead {
                dot()
              } else {
                c.text("·", style=st_fact_dot) |> ignore
              }
              c.text(f, style=st_fact_wrap) |> ignore
            })
            |> ignore
          }
        }
        if first {
          dot()
        }
      })
      |> ignore
      // what is wrong with it, under how it is
      if problems.length() > 0 {
        c.box(style=st_warn, fn() {
          for p in problems {
            c.text(text(Some(p), "text"), style=if text(Some(p), "level") == "red" { st_warn_red } else { st_warn_amber })
            |> ignore
          }
        })
        |> ignore
      }
    })
    |> ignore
    c.box(style=st_head_actions, fn() {
      if !online || silent {
        station_retry(c, core, s)
      }
      if manager {
        @settings.doing_mark(
          c,
          is_doing(core, ["workspace.renameStation", "workspace.removeStation"], [("station", id)]),
          failed_of(core, ["workspace.renameStation", "workspace.removeStation"], [("station", id)]),
        )
        station_menu(c, core, here, s)
      }
    })
    |> ignore
  })
  |> ignore
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
/// Its ⋯ (edits.menu, without its 文件: its page opens them from its folders): renaming it, removing it from the
/// workspace (asked first).
fn station_menu(c : @ui.Ctx, core : Core, here : Here, s : Json?) -> Unit {
  let t = @sf.theme()
  let address = text(s, "station")
  let mid = c.id("station-more/" + address)
  c.cursor(mid, Hand)
  let b = c.box(style=st_more, id=mid, fn() { @sf.icon(c, "more", size=st_more_icon, color=t.p.muted) |> ignore })
  c.semantics(b, Button, id=mid, label=@sf.t("common.more"))
  if !c.clicked(mid) {
    return
  }
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
      Some(@sf.menu_item_of(@sf.t("web-pages.settings.stations.remove"), icon="trash", danger=true, remove)),
    ],
    from=Of(mid),
    along=End,
  )
}

///|
/// The parts to pick from (Body's Segmented): as wide as their names, at the column's start, 24 over what they show.
fn station_parts_choice(c : @ui.Ctx, address : String) -> Unit {
  let at = match @settings.station_parts.get(address) {
    Some(p) => station_part_names.search(p).unwrap_or(0)
    None => 0
  }
  c.box(style=st_parts, fn() {
    let picked = @sf.segmented(
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
  actions? : () -> Unit = fn() {  },
) -> Unit {
  @sf.section(
    c,
    title,
    body,
    note=description,
    actions~,
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
/// screens, profiles, connects and folders.
fn station_overview(c : @ui.Ctx, core : Core, here : Here, s : Json?) -> Array[() -> Unit] {
  let t = @sf.theme()
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
        c.box(style=st_machine, fn() {
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
        |> ignore
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
            c.box(style=desk_list, fn() {
              for sc in screens {
                let sv = Some(sc)
                let id = c.id("station-screen/" + address + "/" + text(sv, "id"))
                c.cursor(id, Hand)
                if c.clicked(id) {
                  @sfbase.open_page(Screen({ station: address, screen: text(sv, "id"), title: text(sv, "title"), until_gone: false }))
                }
                c.box(style=desk_list_link, id~, fn() {
                  @sf.icon(c, if text(sv, "kind") == "browser" { "web" } else { "monitor" }, size=desk_chevron, color=t.p.muted)
                  |> ignore
                  c.box(style=desk_list_text, fn() {
                    c.text(text(sv, "title"), style=desk_list_title) |> ignore
                    let access = field(sv, "access")
                    let lacks = access is Some(Object(_)) && (!flag(access, "capture") || !flag(access, "control"))
                    c.text(text(sv, "line"), style=if lacks { st_line_off } else { desk_note }) |> ignore
                  })
                  |> ignore
                  @sf.icon(c, "chevron-right", size=desk_chevron, color=t.p.muted) |> ignore
                })
                |> ignore
              }
              if screens.length() == 0 {
                c.box(style=desk_list_row, fn() {
                  @sf.icon(c, "monitor", size=desk_chevron, color=t.p.muted) |> ignore
                  c.text(note, style=desk_note) |> ignore
                })
                |> ignore
              }
            })
            |> ignore
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
        c.box(style=desk_list, fn() {
          for p in profiles {
            station_profile_row(c, core, address, Some(p))
          }
        })
        |> ignore
      })
    })
  }
  let connects = items(o, "connects")
  if connects.length() > 0 {
    out.push(fn() {
      st_section(c, @sf.t("web-pages.settings.nav.connects"), count=connects.length(), fn() {
        c.box(style=desk_list, fn() {
          for cn in connects {
            let cv = Some(cn)
            let id = c.id("station-connect/" + address + "/" + text(cv, "id"))
            c.cursor(id, Hand)
            if c.clicked(id) {
              (core.push)(Connect(address, text(cv, "id")))
            }
            c.box(style=desk_list_link, id~, fn() {
              @sf.status_dot(c, text(cv, "presence"))
              c.box(style=desk_list_text, fn() {
                c.text(text(cv, "name"), style=desk_list_title) |> ignore
                c.text(join([text(cv, "team"), text(cv, "runText")], " · "), style=desk_note) |> ignore
              })
              |> ignore
              if text(cv, "presence") != "online" {
                c.text(text(cv, "statusText"), style=st_end_words) |> ignore
              }
              @sf.icon(c, "chevron-right", size=desk_chevron, color=t.p.muted) |> ignore
            })
            |> ignore
          }
        })
        |> ignore
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
            if @sf.button(c, @sf.t("web-pages.stations.page.openFiles"), key="station-files/" + address, tone=Ghost, icon="folder") {
              @sfbase.open_page(Drive({ station: address, root: None, path: "" }))
            }
          },
          fn() {
            if roots.length() == 0 {
              c.text(@sf.t("web-pages.drive.noneYet"), style=st_note) |> ignore
            } else {
              c.box(style=desk_list, fn() {
                for r in roots {
                  let rv = Some(r)
                  let id = c.id("station-folder/" + address + "/" + text(rv, "path"))
                  c.cursor(id, Hand)
                  if c.clicked(id) {
                    @sfbase.open_page(Drive({ station: address, root: Some(text(rv, "path")), path: "" }))
                  }
                  c.box(style=st_folder, id~, fn() {
                    @sf.icon(c, "folder", size=desk_chevron, color=t.p.muted) |> ignore
                    c.text(text(rv, "name"), style=st_folder_name) |> ignore
                    c.text(text(rv, "path"), style=st_folder_path) |> ignore
                    @sf.icon(c, "chevron-right", size=desk_chevron, color=t.p.muted) |> ignore
                  })
                  |> ignore
                }
              })
              |> ignore
            }
          },
        )
      })
    }
    _ => ()
  }
  // what else of it has a page of its own: its memory, this device's adb lent to its agents (AdbShare)
  out.push(fn() {
    st_section(c, @sf.t("web-pages.stations.page.more"), fn() {
      c.box(style=desk_list, fn() {
        if look_link(c, Wide, "st-memory/" + address, @sf.t("android-settings.memory")) {
          (core.push)(Memory(address))
        }
        let shared = (core.topic)("adbShare", Map([])).value
        if look_link(
            c,
            Wide,
            "st-adb/" + address,
            @sf.t("android-misc.adb.title"),
            value=if flag(shared, "sharing") && text(shared, "station") == address { @sf.t("android-misc.adb.sharing") } else { "" },
          ) {
          (core.push)(AdbShare(address))
        }
      })
      |> ignore
    })
  })
  out
}

///|
/// A profile of it (ProfileCard, as the Profile page lists it): its maker's mark, its name and runtimes, what it is
/// and its models and who uses it, its allowance, its check where not well; the whole of it its page.
fn station_profile_row(c : @ui.Ctx, core : Core, address : String, p : Json?) -> Unit {
  let t = @sf.theme()
  let id = c.id("station-profile/" + address + "/" + text(p, "id"))
  c.cursor(id, Hand)
  if c.clicked(id) {
    (core.push)(Profile(address, text(p, "id")))
  }
  c.box(style=desk_list_link, id~, fn() {
    c.box(style=st_profile_mark, fn() { @sf.maker_mark(c, text(p, "providerMark"), text(p, "runtime"), st_profile_glyph) |> ignore })
    |> ignore
    c.box(style=desk_list_text, fn() {
      c.text(text(p, "name"), style=desk_list_title) |> ignore
      let used = items(p, "usedBy").length()
      let facts = [text(p, "modelsText")]
      if used > 0 {
        facts.push(@sf.t("web-pages.settings.profiles.usedBy", args=[("n", used.to_string())]))
      }
      c.text(join(facts, " · "), style=desk_note) |> ignore
    })
    |> ignore
    let quota = field(p, "quota")
    if text(quota, "state") == "ok" {
      @settings.quota_chips(c, quota, small=true)
    }
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
    @sf.icon(c, "chevron-right", size=desk_chevron, color=t.p.muted) |> ignore
  })
  |> ignore
}

// ── Settings ────────────────────────────────────────────────────────────

///|
/// What it is let do and set to (Settings): the grants macOS gives it, the tools logged in on it, its agents'
/// variables, what its search finds, the workspaces it is in.
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
  match field(o, "agentEnv") {
    Some(Array(env)) => out.push(fn() { station_env(c, core, address, env, manager) })
    _ => ()
  }
  match field(o, "search") {
    Some(Object(_)) as search if online && text(search, "files") == "spotlight" =>
      out.push(fn() { station_search(c, core, address, search, manager) })
    _ => ()
  }
  if manager {
    out.push(fn() { station_workspaces(c, core, address) })
  }
  out
}

///|
/// What macOS lets its still.fail Helper do (PermissionsSection): a row each, what it is for, given or not; one not
/// given asked for from here (`permissions.request`), its screen opened where it can be driven.
fn station_permissions(c : @ui.Ctx, core : Core, address : String, p : Json?) -> Unit {
  let t = @sf.theme()
  st_section(c, @sf.t("web-pages.stations.permissions.section"), description=text(p, "note"), fn() {
    c.box(style=desk_list, fn() {
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
        c.box(style=desk_list_row, fn() {
          c.box(style=st_grant_mark, fn() {
            @sf.icon(c, grant_icon(gid), size=st_grant_glyph, color=t.p.text) |> ignore
          })
          |> ignore
          c.box(style=desk_list_text, fn() {
            c.text(text(gv, "name"), style=desk_list_title) |> ignore
            c.text(text(gv, "line"), style=desk_note) |> ignore
          })
          |> ignore
          match end {
            "granted" => c.text(@sf.t("web-pages.stations.permissions.granted"), style=st_end_words) |> ignore
            "waiting" => c.text(@sf.t("web-pages.stations.permissions.waiting"), style=st_end_words) |> ignore
            "missing" => c.text(@sf.t("web-pages.stations.permissions.missing"), style=st_end_words) |> ignore
            "open" =>
              if @sf.button(c, @sf.t("web-pages.stations.permissions.openScreen"), key="grant-open/" + address + "/" + gid) {
                open_screen_link(core, text(p, "screen"))
              }
            _ => {
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
          }
        })
        |> ignore
      }
    })
    |> ignore
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
      station_env_editor(c, core, address)
    })
    return
  }
  if env.length() == 0 {
    return
  }
  st_section(c, @sf.t("web-pages.stations.agentEnv"), fn() {
    c.box(style=desk_card, fn() {
      for e in env {
        let ev = Some(e)
        c.box(style=desk_card_row, fn() {
          c.box(style=desk_card_text, fn() {
            c.rich([@ui.span(text(ev, "key"), mono=true)], style=desk_strong) |> ignore
            c.rich([@ui.span(text(ev, "value"), mono=true)], style=desk_muted) |> ignore
          })
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
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
  c.box(style=st_footed_card(), fn() {
    let typed = @sf.textarea(c, "env/" + address, rows=6, field=field_, placeholder=env_placeholder)
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
              style=if p.2 { desk_note_bad } else { desk_note },
            )
            |> ignore
          }
        })
        |> ignore
      }
    }
    c.box(style=st_foot_actions(), fn() {
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
    |> ignore
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
    c.box(style=desk_card, fn() {
      c.box(style=desk_card_row, fn() {
        c.box(style=desk_card_text, fn() {
          c.text(@sf.t("web-pages.stations.search.personal"), style=desk_strong) |> ignore
          c.text(@sf.t("web-pages.stations.search.personalLine"), style=desk_muted) |> ignore
        })
        |> ignore
        let busy = is_doing(core, ["search.setPersonal"], [("station", address)])
        let on = flag(search, "personal")
        let now = @sf.switch(
          c,
          "search-personal/" + address,
          on,
          label=@sf.t("web-pages.stations.search.personal"),
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
      |> ignore
    })
    |> ignore
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
    c.box(style=desk_card, fn() {
      for w in ws {
        let wv = Some(w)
        c.box(style=desk_card_row, fn() {
          c.box(style=desk_card_text, fn() {
            c.text(text(wv, "name"), style=desk_strong) |> ignore
            c.text(text(wv, "line"), style=desk_muted) |> ignore
          })
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
}

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
        if online {
          software_list(c, core, text(s, "station"), updates, manager, flag(s, "betaOffered"))
        } else {
          c.text(@sf.t("web-pages.stations.softwareOffline"), style=st_note) |> ignore
        }
        if updates.length() == 0 && text(s, "version") != "" {
          c.text("Station " + text(s, "version"), style=st_note) |> ignore
        }
      })
    },
    fn() {
      st_section(c, @sf.t("web-pages.stations.device"), fn() {
        match host {
          Some(_) => {
            let details = items(host, "details")
            let footprint = text(field(o, "footprint"), "text")
            let rows : Array[(String, String)] = details.map(fn(d) { (text(Some(d), "label"), text(Some(d), "value")) })
            if footprint != "" {
              rows.push((@sf.t("web-pages.stations.page.footprint"), footprint))
            }
            host_details(c, rows)
          }
          None =>
            c.text(
              if online {
                @sf.t("web-pages.stations.deviceLoading")
              } else {
                @sf.t("web-pages.stations.deviceOffline")
              },
              style=st_note,
            )
            |> ignore
        }
      })
    },
  ]
}

// ── styles (StationPage.css.ts, settings.css.ts workspaceHead) ──────────

///|
let st_mark_glyph : Double = 28.0

///|
let st_more_icon : Double = 16.0

///|
let st_profile_glyph : Double = 18.0

///|
let st_grant_glyph : Double = 18.0

///|
/// The head (workspaceHead): its mark, its name and facts, its actions; 16 apart, 8 under where the page's frame puts it
/// (the page's own top is the frame's: desk_own_head), 36 over its parts.
// kept across runs: a value (no field of it changes)
let st_head : @ui.Style = @ui.css("row w=Full pt=S2 pb=S9 gap=S4 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let st_mark : @ui.Style = @ui.css("w=S14 h=S14 radius=Xl bg=Neutral align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let st_mark_letter : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Semibold, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let st_identity : @ui.Style = @ui.style(w=@sf.grow, gap=SPx)

///|
/// Its name, renamed where it is (titleField): the title's words, the hover's ground under the pointer.
// kept across runs: a value (no field of it changes)
let st_name_box : @ui.Style = @ui.css("h=S10 px=S2 align=AStart justify=JCenter radius=Xl hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let st_name_still : @ui.Style = @ui.css("h=S10 px=S2 align=AStart justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let st_name : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Semibold, color=Fg, wrap=false)

///|
/// Its facts in a line (workspaceFacts: the ui's 13 muted, a · between them).
// kept across runs: a value (no field of it changes)
let st_facts : @ui.Style = @ui.css("row px=S2 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let st_status : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let st_fact : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, wrap=false)

///|
/// A fact after its dot: on more lines where one has not the room.
// kept across runs: a value (no field of it changes)
let st_fact_wrap : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted)

///|
/// A fact with the dot before it, 8 apart, kept together.
// kept across runs: a value (no field of it changes)
let st_fact_part : @ui.Style = @ui.css("row gap=S2 align=AStart")

///|
/// Between the facts' lines (workspaceFacts: 4).
let st_facts_line : Double = 4.0

///|
// kept across runs: a value (no field of it changes)
let st_fact_busy : @ui.TextStyle = st_fact.then(@ui.text_style(color=AccentText))

///|
// kept across runs: a value (no field of it changes)
let st_fact_dot : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Subtle, wrap=false)

///|
/// What is wrong (warn: 6 under its facts, 4 apart, the ui's 13 in 500, in its level's colour).
// kept across runs: a value (no field of it changes)
let st_warn : @ui.Style = @ui.css("w=Full px=S2 pt=S1_5 gap=S1")

///|
// kept across runs: a value (no field of it changes)
let st_warn_amber : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, weight=Medium, color=Warn, w=Full)

///|
// kept across runs: a value (no field of it changes)
let st_warn_red : @ui.TextStyle = st_warn_amber.then(@ui.text_style(color=Danger))

///|
/// What it does at its end (headActions: 8 apart).
// kept across runs: a value (no field of it changes)
let st_head_actions : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let st_more : @ui.Style = @ui.css("w=S8 h=S8 radius=Xl align=ACenter justify=JCenter hovered{bg=Hover}")

///|
/// The parts to pick from (parts: 24 over what they show).
// kept across runs: a value (no field of it changes)
let st_parts : @ui.Style = @ui.css("row w=Full pb=S6")

///|
/// A section's count beside its title (titleCount: 8 after it, 500, subtle).
// kept across runs: a value (no field of it changes)
let st_count : @ui.TextStyle = @ui.text_style(size=Base, leading=L7, weight=Medium, color=Subtle, wrap=false)

///|
/// What is left of the machine large, then this device's connection (machine: 18 apart, at the start).
// kept across runs: a value (no field of it changes)
let st_machine : @ui.Style = @ui.css("w=Full gap=S4_5 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let st_memory : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let st_note : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let st_end_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let st_line_off : @ui.TextStyle = desk_note.then(@ui.text_style(color=Warn))

///|
/// A folder lent (folder: 44 high at least; its name in 500, where it is quiet after it, cut at the end).
// kept across runs: a value (no field of it changes)
let st_folder : @ui.Style = desk_list_link.then(@ui.css("min_h=S11"))

///|
// kept across runs: a value (no field of it changes)
let st_folder_name : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let st_folder_path : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, wrap=false, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let st_profile_mark : @ui.Style = @ui.css("w=S9 h=S9 radius=Full bg=Neutral align=ACenter justify=JCenter")

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
/// A card with its buttons last (st_foot_actions): its foot as far in as makes them concentric with its corners
/// (@sf.card_foot_in).
fn st_footed_card() -> @ui.Style {
  desk_card.then(@sf.foot_pad(@sf.button_height()))
}

///|
/// A st_footed_card's buttons at its end, reaching past its words to its foot corner's.
fn st_foot_actions() -> @ui.Style {
  st_card_actions.then(@sf.foot_across(@sf.button_height()))
}
