// A station's own page, one in every frame, laid out by its width (web/src/cloud/StationPage.tsx StationSettings, Head, Body, Overview,
// Settings, Machine; StationPage.css.ts): its head (its mark and name, which its managers change where they are, how it
// is and what it is, what is wrong with it, trying it again while away, its ⋯), then its parts one at a time: how it
// is and what runs on it (what is left of the machine, its screens, profiles, connects and folders), what it is let do
// and set to (macOS's grants, the tools logged in on it, its agents' variables, what its search finds, the workspaces
// it is in), its software and the machine. Everything said is the core's (its station view, its topics).

///|
fn station_page_reset() -> Unit {
  env_forms.clear()
  env_forms_made.val = 0
  env_drafts.clear()
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
  // (that station alone, whole: its page's own ask)
  let topic = @settings.station_read(core, here, address)
  let manager = { let r = role_of(core, here); r == "owner" || r == "admin" }
  let back = "Station"
  match topic.value {
    Some(Object(_)) as s => station_view(c, core, here, frame, s, manager)
    // (removed, or a link from before: its list)
    Some(_) => station_waiting(c, core, here, frame, back, "")
    None => station_waiting(c, core, here, frame, back, @sf.t("common.readingStations"))
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
    "profileGroups": [{ "group": "claude", "title": w(6), "profiles": ["sample0", "sample1", "sample2"], "attention": 0 }],
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
        c.on_press(mid, fn() {
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
        })
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
/// Where a station another workspace lent is from: its home workspace's name, else that
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
  @sf.button(c, @sf.t("common.retry"), key="station-retry/" + text(s, "station"), tone=Ghost, busy=trying, disabled=trying, on_press=fn() {
    @settings.act(
      core,
      @sf.t("common.retry"),
      "client.wake",
      obj([("away", Json::number(0.0)), ("network", Json::boolean(true)), ("retry", Json::boolean(true))]),
    )
  }) |> ignore
}

///|
/// Its 启动 where it is this machine's, not running here (local_stopped): no try at reaching it again, nothing there
/// to reach; while it is being started, installed or updated, busy.
fn station_start(c : @ui.Ctx, core : Core, own_station : Json?, address : String) -> Unit {
  let working = text(own_station, "doing") != ""
  @sf.button(
    c,
    @sf.t("web-pages.localStation.start"),
    key="station-start/" + address,
    tone=Ghost,
    busy=working,
    disabled=working,
    on_press=fn() {
      local_start(core, own_station)
    },
  ) |> ignore
}

///|
/// Its ⋯ (edits.menu, without its 文件: its page opens them from its folders): renaming it, restarting it while it is
/// online (its launcher hands over, its sessions go on, what its advanced settings saved taking effect), removing it
/// from the workspace (asked first).
fn station_menu(c : @ui.Ctx, core : Core, here : Here, s : Json?) -> Unit {
  let key = "station-more/" + text(s, "station")
  @sf.icon_action(c, "more", key, @sf.t("common.more"), on_press=fn() {
    @sf.menu(station_menu_items(core, here, s), from=Of(c.id(key)), along=End)
  })
}

///|
/// What its ⋯ holds (station_menu's): renaming it, restarting it while it is online, removing it (asked first).
fn station_menu_items(core : Core, here : Here, s : Json?) -> Array[@sf.MenuItem?] {
  let address = text(s, "station")
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
      // made one that only runs tasks by its owner, who added it (`mine`: the core says; asked first, with how many
      // chats it holds go out of sight): its own station asked, so only while it is up; one of another workspace's
      // stays whole
      if flag(s, "mine") && flag(s, "online") && !flag(s, "joined") {
        Some(@sf.menu_item_of(@sf.t("web-pages.rigs.toTasks"), icon="boxes", fn() {
          let chats = number(field(field(s, "overview"), "counts"), "sessions").to_int()
          confirm(
            @sf.t("web-pages.rigs.toTasksAsk", args=[("name", text(s, "name"))]),
            if chats > 0 { @sf.t("web-pages.rigs.toTasksNote", args=[("n", chats.to_string())]) } else { @sf.t("web-pages.rigs.toTasksNoteNone") },
            @sf.t("web-pages.rigs.toTasks"),
            fn() {
              @settings.act(
                core,
                @sf.t("web-pages.rigs.toTasks"),
                "rig.setMode",
                obj([("workspace", str(here.workspace)), ("station", str(text(s, "id"))), ("mode", str("tasks"))]),
                done=@sf.t("web-pages.rigs.toTasksDone"),
              )
            },
          )
        }))
      } else {
        None
      },
      Some(@sf.menu_item_of(@sf.t("web-pages.settings.stations.remove"), icon="trash", danger=true, remove)),
  ]
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
            station_resource_dials(c, items(host, "meters"), items(host, "gpus"))
            match (core.topic)("stationNet", { "station": str(address) }).get().value {
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
  // its browser pages (user-opened vs agent-opened) and physical/simulator screens; one from before them says so quietly
  match (core.topic)("screens", { "station": str(address) }).get().value {
    Some(Object(_)) as v => {
      let all = items(v, "screens")
      let user_tabs = all.filter(fn(sc) { is_user_screen(Some(sc)) })
      let agent_tabs = all.filter(fn(sc) { is_agent_screen(Some(sc)) })
      let screens = all.filter(fn(sc) { !is_browser_screen(Some(sc)) })
      let can_open = flag(v, "browser") && flag(v, "control")
      let note = text(v, "note")
      if !user_tabs.is_empty() || can_open {
        out.push(fn() {
          let actions : (() -> Unit)? = if can_open {
            Some(fn() {
              let btn = "station-open-browser/" + address
              let from = c.id(btn)
              @sf.action(
                c,
                btn,
                @sf.t("web-pages.screen.openBrowser"),
                icon="plus",
                busy=is_doing(core, ["screen.openBrowser"], [("station", address)]),
                on_press=fn() { @settings.open_station_browser(core, address, from=Of(from)) },
              )
            })
          } else {
            None
          }
          st_section(c, @sf.t("web-pages.screen.userPages"), count=user_tabs.length(), actions?, fn() {
            @sf.group(c, fn() {
              for sc in user_tabs {
                station_browser_row(c, core, here, address, Some(sc), true)
              }
              if user_tabs.is_empty() {
                @sf.link_row(c, "", @sf.t("web-pages.screen.noUserPages"), goes=false, lead=fn() { st_row_mark(c, "web") }) |> ignore
              }
            })
          })
        })
      }
      if !agent_tabs.is_empty() {
        out.push(fn() {
          st_section(c, @sf.t("web-pages.screen.agentPages"), count=agent_tabs.length(), fn() {
            @sf.group(c, fn() {
              for sc in agent_tabs {
                station_browser_row(c, core, here, address, Some(sc), false)
              }
            })
          })
        })
      }
      if screens.length() > 0 || (all.is_empty() && note != "") {
        out.push(fn() {
          st_section(c, @sf.t("web-pages.screen.section"), count=screens.length(), fn() {
            @sf.group(c, fn() {
              for sc in screens {
                let sv = Some(sc)
                let access = field(sv, "access")
                let lacks = access is Some(Object(_)) && (!flag(access, "capture") || !flag(access, "control"))
                // this machine's own display: said so, not opened (own_screen)
                let own = own_screen(address, text(sv, "id"))
                @sf.link_row(
                  c,
                  "station-screen/" + address + "/" + text(sv, "id"),
                  text(sv, "title"),
                  // what it lacks says so in its line (the core's: what cannot be done now)
                  note=if own { @sf.t("android-misc.screen.here") } else { text(sv, "line") },
                  lacks=lacks && !own,
                  goes=!own,
                  lead=fn() { st_row_mark(c, screen_row_icon(sv)) },
                  on_press=fn() {
                    @sfbase.open_page(Screen({ station: address, screen: text(sv, "id"), title: text(sv, "title"), until_gone: false }))
                  },
                ) |> ignore
                screen_views(c, core, here, address, sv)
              }
              if screens.length() == 0 && note != "" {
                @sf.link_row(c, "", note, goes=false, lead=fn() { st_row_mark(c, "monitor") }) |> ignore
              }
            })
          })
        })
      }
    }
    _ => ()
  }
  let profile_groups = items(s, "profileGroups")
  if profile_groups.length() > 0 {
    out.push(fn() {
      st_section(c, @sf.t("android-misc.bar.place.profiles"), fn() {
        @sf.group(c, fn() {
          for group in profile_groups {
            let gv = Some(group)
            let kind = text(gv, "group")
            let name = text(gv, "title")
            let ids = strings(gv, "profiles")
            let attention = match field(gv, "attention") {
              Some(Number(n, ..)) => n.to_int()
              _ => 0
            }
            let row = "station-profiles/" + address + "/" + kind
            let from = c.id(row)
            @sf.link_row(
              c,
              row,
              name,
              value=@sf.t("web-mobile.settings.profilesCount", args=[("n", ids.length().to_string())]),
              trouble=if attention > 0 { @sf.t("web-mobile.settings.profilesShort", args=[("n", attention.to_string())]) } else { "" },
              lead=fn() { @settings.group_mark(c, kind) },
              on_press=fn() {
                station_profiles_panel(core, here, address, kind, name, Of(from), ids.length() >= @sf.pick_search_from)
              },
            ) |> ignore
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
            @sf.link_row(
              c,
              "station-connect/" + address + "/" + text(cv, "id"),
              text(cv, "name"),
              note=join([text(cv, "team"), text(cv, "runText")], " · "),
              value=if text(cv, "presence") != "online" { text(cv, "statusText") } else { "" },
              lead=fn() { @sf.status_dot(c, text(cv, "presence")) },
              on_press=fn() {
                (core.push)(Connect(address, text(cv, "id")))
              },
            ) |> ignore
          }
        })
      })
    })
  }
  // Its drive: a station that offers its home opens there; older ones still show their configured folders.
  match field(o, "drive") {
    Some(Object(_)) as drive => {
      let roots = items(drive, "roots")
      out.push(fn() {
        if flag(drive, "anywhere") {
          st_section(c, @sf.t("web-pages.drive.title"), fn() {
            @sf.group(c, fn() {
              @sf.link_row(
                c,
                "station-files/" + address,
                @sf.t("web-pages.stations.page.openFiles"),
                lead=fn() { st_row_mark(c, "folder") },
                on_press=fn() {
                  @sfbase.open_page(Drive({ station: address, root: None, path: "" }))
                },
              ) |> ignore
            })
          })
        } else {
          st_section(
            c,
            @sf.t("web-pages.drive.title"),
            count=roots.length(),
            actions=fn() {
              @sf.action(c, "station-files/" + address, @sf.t("web-pages.stations.page.openFiles"), icon="folder", on_press=fn() {
                @sfbase.open_page(Drive({ station: address, root: None, path: "" }))
              })
            },
            fn() {
              @sf.group(c, fn() {
                if roots.length() == 0 {
                  @sf.said_row(c, @sf.t("web-pages.drive.noneYet"), "")
                }
                for r in roots {
                  let rv = Some(r)
                  @sf.link_row(
                    c,
                    "station-folder/" + address + "/" + text(rv, "path"),
                    text(rv, "name"),
                    note=text(rv, "path"),
                    lead=fn() { st_row_mark(c, "folder") },
                    on_press=fn() {
                      @sfbase.open_page(Drive({ station: address, root: Some(text(rv, "path")), path: "" }))
                    },
                  ) |> ignore
                }
              })
            },
          )
        }
      })
    }
    _ => ()
  }
  // its devices (设备: every chat's, as it is), and adding one: any member but one who only reads
  let id = text(s, "id")
  let devices = @settings.devices_listed(core, here).filter(fn(d) { text(Some(d), "station") == id && text(Some(d), "via") == "station" })
  let role = role_of(core, here)
  let can_add = role != "" && role != "viewer"
  // (while it is up: one is added there)
  if online && (devices.length() > 0 || can_add) {
    out.push(fn() {
      st_section(c, @sf.t("web-pages.devices.title"), count=devices.length(), description=@sf.t("web-pages.devices.stationNote"), fn() {
        @sf.group(c, fn() {
          for d in devices {
            let dv = Some(d)
            let row = "station-device/" + address + "/" + text(dv, "id")
            let from = c.id(row)
            @sf.link_row(
              c,
              row,
              text(dv, "name"),
              note=join([@settings.device_kind_words(dv), text(dv, "target"), @settings.device_whose(dv)], " · "),
              lead=fn() { st_row_mark(c, @settings.device_icon(dv)) },
              on_press=fn() { @settings.open_device(core, here, id, text(dv, "id"), @sf.Beside::Of(from).anchor()) },
            ) |> ignore
          }
          if can_add {
            let row = "station-device-add/" + address
            let from = c.id(row)
            @sf.link_row(
              c,
              row,
              @sf.t("web-pages.devices.add"),
              note=@sf.t("web-pages.devices.addNote"),
              lead=fn() { st_row_mark(c, "plus") },
              on_press=fn() { @settings.add_device(core, here, id, false, @sf.Beside::Of(from)) },
            ) |> ignore
          }
        })
      })
    })
  }
  // what else of it has a page of its own: its memory, this device's adb lent to its agents (AdbShare)
  out.push(fn() {
    st_section(c, @sf.t("web-pages.stations.page.more"), fn() {
      @sf.group(c, fn() {
        @sf.link_row(c, "st-memory/" + address, @sf.t("android-settings.memory"), on_press=fn() {
          (core.push)(Memory(address))
        }) |> ignore
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
/// One account kind, with its live profiles and their allowances, in a panel opened `from` what was pressed (a sheet
/// from the foot on 小屏, beside it on 中屏 and 大屏), made once as nodes (@sf.panel_nodes, station_kind_node). A long
/// kind (`many`: its list scrolls, a share of the window tall) can be searched without leaving it.
fn station_profiles_panel(
  core : Core,
  here : Here,
  address : String,
  kind : String,
  title : String,
  from : @sf.Anchor,
  many : Bool,
) -> Unit {
  @sf.panel_nodes(
    title,
    fn(v, close) { station_kind_node(v, core, here, address, kind, many, close) },
    from~,
    tall=if many { 0.85 } else { 0.0 },
    grows=many,
  )
}

///|
/// What one account kind's panel holds (station_profiles_panel), in node `v` (its body), as station `address` says now
/// (its own ask, held while the panel is up): a search over its accounts while it has as many as a pick searches
/// (pick_search_from) or words are in it, then its accounts it finds, a row each by its id (View::each; a long
/// list's rows made as they show, panel_list_node, where `many`), coming and going as the station lists them; none
/// found, a line saying so. A row pressed closes the panel (`close`) for its account's page. Once the station said
/// the kind and says it no more, the panel closes (`close`, as that is said), showing what it showed last till it is
/// gone; while the station is not said yet, or never said the kind, it stays.
fn station_kind_node(
  v : @view.View,
  core : Core,
  here : Here,
  address : String,
  kind : String,
  many : Bool,
  close : () -> Unit,
) -> Unit {
  let query = @ui.Field::new()
  let group_in = fn(s : Json?) { items(s, "profileGroups").iter().find_first(fn(g) { text(Some(g), "group") == kind }) }
  let said = fn() { @settings.station_of(core, here, address) }
  // (the kind gone: the panel closes, what it showed last kept as it goes, not emptied under it)
  let last : Ref[Json?] = Ref(None)
  let now = fn() {
    let s = said()
    match s {
      Some(_) if group_in(s) is None && last.val is Some(_) => last.val
      _ => {
        if group_in(s) is Some(_) {
          last.val = s
        }
        s
      }
    }
  }
  // (closed as a kind the station said comes to be gone: said once, as it does; while the station is not said, or
  // the kind never was, nothing)
  let had = Ref(false)
  v.reacts(
    fn() {
      let s = said()
      match s {
        None => 0
        Some(_) => if group_in(s) is Some(_) { 1 } else { 2 }
      }
    },
    fn(says) {
      if says == 1 {
        had.val = true
      } else if says == 2 && had.val {
        close()
      }
    },
  )
  let ids = fn() { strings(group_in(now()), "profiles") }
  let searched = fn() { ids().length() >= @sf.pick_search_from || query.text() != "" }
  // (its accounts it lists that the station has, in its order, those the search's words are in)
  let found = fn() {
    let words = if searched() { query.text().trim().to_owned().to_lower() } else { "" }
    let profiles = items(field(now(), "overview"), "profiles")
    let out : Array[String] = []
    for id in ids() {
      match profiles.iter().find_first(fn(p) { text(Some(p), "id") == id }) {
        Some(p) => {
          let hay = (text(Some(p), "name") + "\n" + text(Some(p), "email")).to_lower()
          if words == "" || hay.contains(words) {
            out.push(id)
          }
        }
        None => ()
      }
    }
    out
  }
  let profile = fn(id : String) {
    items(field(now(), "overview"), "profiles").iter().find_first(fn(p) { text(Some(p), "id") == id })
  }
  let state = fn(id : String) { field(field(now(), "profileStates"), id) }
  let row = fn(b : @view.View, id : String) {
    station_profile_row_node(b, core, address, id, fn() { profile(id) }, fn() { state(id) }, close)
  }
  v.show(searched, fn(s) {
    @sf.style_node(s, fn() { @sf.panel_words_in_node(s).then(st_profiles_search) })
    let f = @sf.input_node(s, query, placeholder=@sf.t("common.search"), small=true)
    // (a long kind's: the keys there as it opens beside what opened it, not on a sheet)
    if many {
      @sf.panel_search_at_hand_node(f)
    }
  })
  v.show(fn() { found().is_empty() }, fn(n) { @sf.panel_note_node(n, fn() { @sf.t("common.noMatch") }) })
  if many {
    @sf.panel_list_node(v, found, row, est=st_profile_row_est) |> ignore
  } else {
    v.box(fn(rows) {
      @sf.style_node(rows, fn() { st_profiles_rows })
      rows.each(found, fn(id) { id }, fn(r, id) { row(r, id.untracked()) })
    })
    |> ignore
  }
}

///|
/// An account's row (`id`, `p` as the station says it now, `state` how its check stands) in `b`: its name, its models
/// and how many use it, its maker's mark before them; its allowance's chips under them while the core can say it; a
/// pill at its end where its check (or the station's word on it) is not well. Pressed, the panel closes (`close`) for
/// its page.
fn station_profile_row_node(
  b : @view.View,
  core : Core,
  address : String,
  id : String,
  p : () -> Json?,
  state : () -> Json?,
  close : () -> Unit,
) -> Unit {
  let facts = fn() {
    let used = items(p(), "usedBy").length()
    let facts = [text(p(), "modelsText")]
    if used > 0 {
      facts.push(@sf.t("web-pages.settings.profiles.usedBy", args=[("n", used.to_string())]))
    }
    join(facts, " · ")
  }
  // (its check's words and tone, the station's own where it says any)
  let check = fn() {
    let st = state()
    if text(st, "text") != "" {
      (text(st, "text"), text(st, "tone"))
    } else {
      (text(p(), "checkText"), text(p(), "checkTone"))
    }
  }
  @sf.link_row_node(
    b,
    fn() { text(p(), "name") },
    fn() {
      close()
      (core.push)(Profile(address, id))
    },
    note=facts,
    lead=LeadLine(fn(l) {
      l.box(fn(m) {
        @sf.style_node(m, fn() { st_profile_mark.then(@sf.row_lead_out_node(m)) })
        m.pick(fn() { (text(p(), "runtime"), text(field(p(), "access"), "kind"), text(p(), "providerMark")) }, fn(k, mk) {
          @sf.provider_logo_node(k, mk.0, mk.1, st_profile_glyph, mk.2) |> ignore
        })
      })
      |> ignore
    }),
    below=fn(q) { @sf.quota_lines_node(q, fn() { field(p(), "quota") }, small=true, in_row=true) },
    below_open=fn() { if text(field(p(), "quota"), "state") == "ok" { 1.0 } else { 0.0 } },
    tail=fn(e) {
      e.pick(check, fn(k, c) {
        @sf.pill_node(k, fn() { c.0 }, tone=match c.1 {
          "red" => Red
          "amber" => Amber
          "blue" => Blue
          _ => Neutral
        })
        |> ignore
      })
    },
    tail_shown=fn() {
      let (status, tone) = check()
      tone != "green" && status != ""
    },
  )
}

///|
// kept across runs: a value (no field of it changes)
let st_profiles_rows : @ui.Style = @ui.css("w=Full gap=SPx")

///|
// kept across runs: a value (no field of it changes)
let st_profiles_search : @ui.Style = @ui.css("w=Full pt=S1 pb=S2_5")

///|
/// A long list's first estimate; its rows say their actual heights as they are laid out.
let st_profile_row_est : Double = 84.0

// ── Settings ────────────────────────────────────────────────────────────

///|
/// What it is let do and set to (Settings): the grants macOS gives it, the tools logged in on it, the programs of its
/// machine granted its data, its agents' variables, what its search finds, the workspaces it is in. Away, none of what
/// only it can change (用户定 2026-11-04: what cannot be changed while it is offline is not shown then), a line saying
/// so in their place (a login under way too: it goes on there only); what it has logged in and the workspaces it
/// is in stay, nothing there to change.
fn station_settings(c : @ui.Ctx, core : Core, s : Json?, manager : Bool) -> Array[() -> Unit] {
  let address = text(s, "station")
  let o = field(s, "overview")
  let out : Array[() -> Unit] = []
  if !flag(s, "online") {
    out.push(fn() {
      @sf.group(c, fn() { @sf.said_row(c, @sf.t("web-pages.stations.settingsOffline"), "") })
    })
    out.push(fn() { station_logins(c, core, address, online=false) })
    if manager {
      out.push(fn() { station_workspaces(c, core, address) })
    }
    return out
  }
  match field(o, "permissions") {
    Some(Object(_)) as p => out.push(fn() { station_permissions(c, core, address, p) })
    _ => ()
  }
  out.push(fn() { station_logins(c, core, address) })
  match field(o, "agentEnv") {
    Some(Array(env)) => out.push(fn() { station_env(c, core, address, env, manager) })
    _ => ()
  }
  match field(o, "search") {
    Some(Object(_)) as search if text(search, "files") == "spotlight" =>
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
    Some(Object(_)) as elevation => out.push(fn() { station_elevation(c, core, address, elevation) })
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
          // (a button at its end makes its first line as tall as the button: its mark across that line's middle,
          // by its title, not the body line's above it)
          lead=fn() {
            if end == "open" || end == "request" {
              c.box(style=grant_mark_by_button(), fn() { st_row_mark(c, grant_icon(gid)) }) |> ignore
            } else {
              st_row_mark(c, grant_icon(gid))
            }
          },
          tail=fn() {
            match end {
              "open" =>
                @sf.button(c, @sf.t("web-pages.stations.permissions.openScreen"), key="grant-open/" + address + "/" + gid, on_press=fn() {
                  open_screen_link(core, text(p, "screen"))
                }) |> ignore
              "request" => {
                let busy = is_doing(core, ["permissions.request"], [("station", address), ("grant", gid)])
                @sf.button(
                  c,
                  @sf.t("web-pages.stations.permissions.request"),
                  key="grant-request/" + address + "/" + gid,
                  tone=Primary,
                  busy~,
                  disabled=busy,
                  on_press=fn() {
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
                  },
                ) |> ignore
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
/// A grant's mark's room beside a button: as tall as the button, the mark across its middle.
fn grant_mark_by_button() -> @ui.Style {
  @ui.style(h=Fixed(@sf.button_height()), justify=JCenter)
}

///|
/// A grant's mark: the screen's two by what they do, the folders by what they
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
/// One browser tab row on a station's overview (`user_tab`: under 用户页面, offering 休眠 while idle and 关闭; else under
/// Agent 页面, offering 关闭 when closable).
fn station_browser_row(c : @ui.Ctx, core : Core, here : Here, address : String, sv : Json?, user_tab : Bool) -> Unit {
  let id = text(sv, "id")
  let can_sleep = user_tab && flag(sv, "closable") && !flag(sv, "sleeping") && items(sv, "views").is_empty()
  let can_close = flag(sv, "closable")
  @sf.link_row(
    c,
    "station-screen/" + address + "/" + id,
    text(sv, "title"),
    note=text(sv, "line"),
    lead=fn() { st_row_mark(c, screen_row_icon(sv)) },
    control?=if can_sleep || can_close {
      Some(fn() {
        let on = [("station", address), ("screen", id)]
        if can_sleep {
          let what = @sf.t("web-pages.screen.sleepWhat")
          @sf.button(
            c,
            @sf.t("web-pages.screen.sleep"),
            key="station-screen-sleep/" + address + "/" + id,
            tone=Ghost,
            busy=is_doing(core, ["screen.sleep"], on),
            on_press=fn() {
              @settings.act(core, what, "screen.sleep", obj([("station", str(address)), ("screen", str(id))]))
            },
          )
          |> ignore
        }
        if can_close {
          let what = @sf.t("web-pages.screen.closeTabWhat")
          @sf.button(
            c,
            @sf.t("web-pages.screen.closeTab"),
            key="station-screen-close/" + address + "/" + id,
            tone=Ghost,
            busy=is_doing(core, ["screen.close"], on),
            on_press=fn() {
              @settings.act(core, what, "screen.close", obj([("station", str(address)), ("screen", str(id))]))
            },
          )
          |> ignore
        }
      })
    } else {
      None
    },
    on_press=fn() {
      @sfbase.open_page(Screen({ station: address, screen: id, title: text(sv, "title"), until_gone: !user_tab }))
    },
  )
  |> ignore
  screen_views(c, core, here, address, sv)
}

///|
/// Who is on one of its screens now: a row a view, whose and on which
/// device, whether it drives it and since when; 转为只看 and 断开 at its end for one the viewer may let go of, and 全部断开
/// once there is more than one.
fn screen_views(c : @ui.Ctx, core : Core, here : Here, address : String, screen : Json?) -> Unit {
  let id = text(screen, "id")
  let views = items(screen, "views")
  let asked = fn(name : String, what : String, params : Array[(String, Json)]) {
    @settings.act(core, what, name, obj([("station", str(address)), ("screen", str(id)), ("account", str(here.sub)), ..params]))
  }
  for v in views {
    let vv = Some(v)
    let view = text(vv, "id")
    let on = [("view", view)]
    let device = if flag(vv, "here") { @sf.t("web-pages.screen.viewHere") } else { text(vv, "device") }
    let mode = @sf.t(if flag(vv, "control") { "web-pages.screen.viewControl" } else { "web-pages.screen.viewWatch" })
    @sf.link_row(
      c,
      "screen-view/" + address + "/" + id + "/" + view,
      text(vv, "name"),
      // (the device is what tells one's own views apart: in the note, which wraps where 转为只看 and 断开 leave little room)
      note=if device == "" { mode + " · " + text(vv, "ago") } else { device + " · " + mode + " · " + text(vv, "ago") },
      goes=false,
      control?=if flag(vv, "may") {
        Some(fn() {
          if flag(vv, "control") {
            let what = @sf.t("web-pages.screen.viewWatchOnly")
            @sf.button(c, what, key="screen-view-watch/" + view, tone=Ghost, busy=is_doing(core, ["screen.watchOnly"], on), on_press=fn() {
              asked("screen.watchOnly", what, [("view", str(view))])
            }) |> ignore
          }
          let what = @sf.t("web-pages.screen.viewEnd")
          @sf.button(c, what, key="screen-view-end/" + view, tone=Ghost, busy=is_doing(core, ["screen.endView"], on), on_press=fn() {
            asked("screen.endView", what, [("view", str(view))])
          }) |> ignore
        })
      } else {
        None
      },
    )
    |> ignore
  }
  if views.filter(fn(v) { flag(Some(v), "may") }).length() > 1 {
    let what = @sf.t("web-pages.screen.viewsEndAll")
    @sf.link_row(
      c,
      "screen-views-end/" + address + "/" + id,
      "",
      goes=false,
      control=fn() {
        @sf.button(c, what, key="screen-views-end/" + id, tone=Ghost, busy=is_doing(core, ["screen.endViews"], [("screen", id)]), on_press=fn() {
          asked("screen.endViews", what, [])
        }) |> ignore
      },
    )
    |> ignore
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
let env_forms : Map[String, String] = Map([])

///|
// kept across runs: counted as forms are opened; station_page_reset puts it back
let env_forms_made : Ref[Int] = Ref(0)

///|
/// The shared draft, independent of the editor and its page's layout and selection.
priv struct EnvDraft {
  pending : @signals.Signal[String?]
  reset : @signals.Signal[Int]
  mut source : String?
  mut sent : String?
}

///|
// kept across runs: made as a station's page opens its draft; station_page_reset empties it
let env_drafts : Map[String, EnvDraft] = Map([])

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
  let d = (core.topic)("agentEnvForm", { "station": str(address), "form": str(form) }).get().value
  let draft = match env_drafts.get(address) {
    Some(draft) => draft
    None => {
      let draft : EnvDraft = { pending: @signals.signal(None, same=fn(a, b) { a == b }), reset: @signals.signal(0), source: None, sent: None }
      env_drafts[address] = draft
      draft
    }
  }
  let field_ = c.editor_field("env/" + address)
  let pending = draft.pending.get()
  let generation = draft.reset.get()
  // Keep the latest edit visible on every page while the core catches up. A late answer for an older edit must not
  // replace it; only an answer for the latest edit clears the pending value.
  if d is Some(Object(_)) && !flag(d, "pending") {
    let now = text(d, "text")
    draft.source = Some(now)
    if pending == Some(now) {
      c.tell("env-ack/" + form, fn() {
        if draft.pending.untracked() == Some(now) {
          draft.pending.set(None)
          draft.sent = None
        }
      })
    }
  }
  let source = match pending {
    Some(_) => pending
    None => draft.source
  }
  match source {
    Some(words) => field_.follow(words, generation~)
    None => ()
  }
  // The core cannot edit a form while it saves. An edit typed then is still shared immediately, and sent once saving
  // finishes. An older acknowledgement never clears or resends a newer value.
  if pending is Some(words) && d is Some(Object(_)) && !flag(d, "pending") && text(d, "text") != words && draft.sent != Some(words) {
    c.tell("env-edit/" + form, fn() {
      if draft.pending.untracked() == Some(words) && draft.sent != Some(words) {
        draft.sent = Some(words)
        station_env_edit(core, address, form, words)
      }
    })
  }
  let saving = is_doing(core, ["agentEnv.form.save"], [("station", address), ("form", form)])
  c.box(style=st_editor, fn() {
    // (first in its card, a block in its corners: `corner_inset` in, a row's corner, its words on the card's line:
    // @sf.card_block_out)
    let mut typed = ""
    c.box(style=@sf.card_block_out(top=true), fn() {
      typed = @sf.textarea(c, "env/" + address, rows=6, field=field_, placeholder=env_placeholder, corner=@sf.row_corner)
    })
    |> ignore
    if source is Some(words) && typed != words {
      c.tell("env-edit/" + form, fn() {
        draft.pending.set(Some(typed))
        if flag(d, "pending") {
          draft.sent = None
        } else {
          draft.sent = Some(typed)
          station_env_edit(core, address, form, typed)
        }
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
      if flag(d, "dirty") {
        @sf.button(c, @sf.t("common.cancel"), key="env-reset/" + address, tone=Ghost, on_press=fn() {
          @signals.start_batch()
          draft.pending.set(None)
          draft.sent = None
          draft.reset.set(draft.reset.untracked() + 1)
          @signals.end_batch()
          @settings.act(
            core,
            @sf.t("web-pages.stations.agentEnvEdit"),
            "agentEnv.form.edit",
            obj([("station", str(address)), ("form", str(form)), ("input", obj([("reset", Json::boolean(true))]))]),
          )
        }) |> ignore
      }
      let can = d is Some(Object(_)) && flag(d, "dirty") && !flag(d, "pending") && !saving && read && count(d, "errors") == 0
      @sf.button(c, @sf.t("common.save"), key="env-save/" + address, tone=Primary, busy=saving, disabled=!can, on_press=fn() {
        @settings.act(
          core,
          @sf.t("web-pages.stations.agentEnvSave"),
          "agentEnv.form.save",
          obj([("station", str(address)), ("form", str(form))]),
          done=@sf.t("web-pages.profiles.saved"),
        )
      }) |> ignore
    })
  })
  |> ignore
}

///|
/// Sends one value of the shared variables draft to the core.
fn station_env_edit(core : Core, address : String, form : String, typed : String) -> Unit {
  @settings.act(
    core,
    @sf.t("web-pages.stations.agentEnvEdit"),
    "agentEnv.form.edit",
    obj([("station", str(address)), ("form", str(form)), ("input", obj([("text", str(typed))]))]),
  )
}

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
/// What it sends still.fail to find its problems by: whether its log goes, scrubbed, said by the
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
/// How it goes on with a session whose prompt cache is over: the station default
/// and its estimated cost threshold, said by the workspace's managers (others read them).
fn station_context(c : @ui.Ctx, core : Core, address : String, context : Json?, manager : Bool) -> Unit {
  let cost = match field(context, "afreshAbove") {
    Some(Number(value, ..)) => Some(value)
    _ => None
  }
  let busy = is_doing(core, ["context.setAfresh"], [("station", address)])
  let on = flag(context, "afreshWhenCold")
  // The default is one switch. Once enabled, its threshold can be edited directly from the section heading.
  let actions : (() -> Unit)? = match cost {
    Some(value) if on && manager =>
      Some(fn() {
        @sf.action(c, "context-cost/" + address, @sf.t("web-pages.stations.context.customAmount"), disabled=busy, on_press=fn() {
          station_cold_custom(core, address, value)
        })
      })
    _ => None
  }
  st_section(c, @sf.t("web-pages.stations.context.section"), actions?, fn() {
    @sf.group(c, fn() {
      let now = @sf.switch_row(
        c,
        "context-afresh/" + address,
        @sf.t("web-pages.stations.context.afresh"),
        on,
        note=match cost {
          Some(value) if value == 0.0 => @sf.t("web-pages.stations.context.afreshZeroLine")
          Some(value) => @sf.t("web-pages.stations.context.afreshCostLine", args=[("amount", "$" + value.to_string())])
          None => @sf.t("web-pages.stations.context.afreshLineLegacy")
        },
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
/// The threshold can be any non-negative, finite amount, including zero.
fn station_cold_amount(words : String) -> Double? {
  match (try Some(@json.parse(words.trim(chars=" \t\n").to_owned())) catch { _ => None }) {
    Some(Number(v, ..)) if v >= 0.0 && !v.is_inf() && !v.is_nan() => Some(v)
    _ => None
  }
}

///|
/// A custom threshold is entered in its own editor, keeping the words being typed there.
fn station_cold_custom(core : Core, address : String, cost : Double) -> Unit {
  let field_ = @ui.Field::new(text=cost.to_string())
  let key = "context-cost-custom/" + (desk_dialogs.val + 1).to_string()
  let title = @sf.t("web-pages.stations.context.threshold")
  open_dialog(
    @sf.t("web-pages.stations.context.customAmount"),
    fn(c, _) {
      @sf.field(c, title, hint=@sf.t("web-pages.stations.context.amountHint"), fn() {
        @sf.input(c, key, placeholder=title, field=field_) |> ignore
      })
    },
    fn(c, shut) {
      @sf.button(c, @sf.t("common.cancel"), key=key + "/cancel", tone=Ghost, on_press=fn() {
        shut()
      }) |> ignore
      let amount = station_cold_amount(field_.text())
      let changed = match amount {
        Some(v) => v != cost
        None => false
      }
      let busy = is_doing(core, ["context.setAfresh"], [("station", address)])
      @sf.button(c, @sf.t("common.save"), key=key + "/save", tone=Primary, busy~, disabled=!changed, on_press=fn() {
        match amount {
          Some(v) => {
            @settings.act(core, @sf.t("web-pages.stations.context.what"), "context.setAfresh", obj([("station", str(address)), ("afreshAbove", Json::number(v))]))
            shut()
          }
          None => ()
        }
      }) |> ignore
    },
  )
}

///|
/// Whether a Windows station runs as the machine's administrator: switched by
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
    @sf.link_row(c, "network-open/" + address, @sf.t("web-pages.stations.network.advanced"), folds=open, on_press=fn() {
      @settings.station_network_open[address] = !open
    }) |> ignore
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
  let m = (core.topic)("memberships", { "station": str(address) }).get().value
  let ws = items(m, "workspaces")
  if !flag(m, "manages") || ws.length() < 2 {
    return
  }
  st_section(c, "Workspace", count=ws.length(), description=@sf.t("web-pages.stations.workspacesLead"), fn() {
    @sf.group(c, fn() {
      for w in ws {
        let wv = Some(w)
        let name = text(wv, "name")
        let emoji = text(wv, "emoji")
        let icon = text(wv, "icon")
        @sf.said_row(c, name, text(wv, "line"), lead?=if @sf.has_station_mark(emoji, icon) {
          Some(fn(c) { @sf.workspace_badge(c, name, emoji, icon, st_ws_mark) })
        } else {
          None
        })
      }
    })
  })
}

///|
/// A workspace's mark before its name.
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
            let rows : Array[(String, String)] = details.map(fn(d) { (text(Some(d), "label"), text(Some(d), "value")) })
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

// ── styles ──────────

///|
let st_mark_glyph : Double = 28.0

///|
let st_profile_glyph : Double = 18.0

///|
// kept across runs: a value (no field of it changes)
let st_mark_letter : @ui.TextStyle = @ui.text_style(size=Heading, weight=Semibold, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let st_fact : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)

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
/// A profile's maker's mark, concentric with its row's corner.
// kept across runs: a value (no field of it changes)
let st_profile_mark : @ui.Style = @ui.css("w=S9 h=S9 bg=Neutral align=ACenter justify=JCenter").then(
  @ui.style(radius=@sf.small_radius),
)

///|
// kept across runs: a value (no field of it changes)
let st_env_problems : @ui.Style = @ui.css("w=Full gap=S1")

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
