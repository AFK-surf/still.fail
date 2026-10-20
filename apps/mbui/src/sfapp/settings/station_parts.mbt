// A station's page, past its machine and what runs on it (Stations.kt StationScreen): its screens (StationScreens),
// what macOS lets a Mac station's helper do (StationPermissions.kt), the variables its agents run with
// (StationAgentEnv, edited in a sheet), what its search finds (StationSearchSection), the workspaces it is in
// (StationWorkspaces), its versions (Versions.kt); and this device's adb lent to its agents (AdbShare.kt's page).

///|
/// The station's screens a person can see and drive (StationScreens: its display, its browser's tabs), a row each; a
/// station from before them, or none to show, says why in a quiet row. Nothing while the station has not said.
/// (Opening one is the remote screen's viewer, which this app does not have yet: said in a toast.)
fn station_screens(c : @ui.Ctx, core : Core, address : String) -> Array[() -> Unit] {
  let t = @sf.theme()
  let view = match (core.topic)("screens", { "station": str(address) }).value {
    Some(Object(_)) as v => v
    _ => return []
  }
  let screens = items(view, "screens")
  let why = match opt_text(view, "note") {
    Some(n) => n
    None => if flag(view, "outdated") { tr("android-misc.screen.outdatedRow") } else { "" }
  }
  if screens.length() == 0 && why == "" {
    return []
  }
  [
    fn() { section_header(c, tr("android-misc.screen.section"), start=S6) },
    fn() {
      list_card(c, fn() {
        for s in screens {
          let v = Some(s)
          if list_row(c, key="screen/" + text(v, "id"), fn() {
              @sf.icon(c, if text(v, "kind") == "browser" { "web" } else { "monitor" }, size=18.0, color=t.p.muted)
              |> ignore
              c.box(w=Fill(1.0), fn() {
                c.text(text(v, "title"), size=15.0, color=t.p.text, wrap=false, w=Fill(1.0), line=20.0) |> ignore
                // a grant missing (its line says which): the one thing on the row in colour
                c.text(
                  text(v, "line"),
                  size=13.0,
                  color=if has(v, "access") { warn } else { t.p.muted },
                  w=Fill(1.0),
                  line=18.0,
                )
                |> ignore
              })
              |> ignore
              chevron(c)
            }) {
            (core.say)(tr("android-misc.screen.failed"))
          }
        }
        if screens.length() == 0 && why != "" {
          list_row(c, fn() {
            c.text(why, size=14.0, color=t.p.muted, w=Fill(1.0), line=20.0) |> ignore
          })
          |> ignore
        }
      })
    },
  ]
}

///|
/// Each grant's mark (StationPermissions.kt grantMark).
fn grant_mark(id : String) -> String {
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
/// A row's state at its end, in words (EndWords).
fn end_words(c : @ui.Ctx, words : String, color : Int64, weight? : Int = 400) -> Unit {
  c.text(words, size=13.0, weight~, color~, wrap=false, line=18.0) |> ignore
}

///|
/// What may be done at a row's end, in the accent (StationPermissions.kt RowAction): a spinner before it while
/// `busy` (not pressed again), the mark of a failure a moment after. True on the frame after a tap.
fn end_action(c : @ui.Ctx, key : String, label : String, busy? : Bool = false, failed? : String? = None) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.box(dir=Row, pady=8.0, gap=6.0, align=ACenter, id~, opacity=if c.pressed(id) && !busy { 0.6 } else { 1.0 }, fn() {
    if busy || failed is Some(_) {
      doing_mark(c, busy, failed, inline=true)
    }
    c.text(label, size=13.0, weight=500, color=if busy { t.p.muted } else { t.p.accent }, wrap=false, line=18.0)
    |> ignore
  })
  |> ignore
  !busy && hit(c, id)
}

///|
/// A Mac station's grants to still.fail Helper (StationPermissionsSection): a row each with what it is for and whether
/// it is given; one not given asked for from here (`permissions.request`), which puts the helper's window up on that
/// Mac, where the person clicks Allow (the next step on the Mac's screen from here is the remote screen's viewer,
/// which this app does not have yet: the row then says to wait for it, as where the screen cannot be driven).
fn station_permissions(c : @ui.Ctx, core : Core, address : String, p : Json?) -> Array[() -> Unit] {
  let t = @sf.theme()
  let grants = items(p, "grants")
  let out : Array[() -> Unit] = [
    fn() { section_header(c, tr("android-misc.permissions.section"), start=S6) },
    fn() {
      list_card(c, fn() {
        for g in grants {
          let v = Some(g)
          let id = text(v, "id")
          let asking = flag(v, "asking")
          list_row(c, fn() {
            @sf.icon(c, grant_mark(id), size=18.0, color=t.p.muted) |> ignore
            c.box(w=Fill(1.0), fn() {
              c.text(text(v, "name"), size=15.0, color=t.p.text, wrap=false, w=Fill(1.0), line=20.0) |> ignore
              // while its window is up, how it is given there
              c.text(text(v, "line"), size=13.0, color=if asking { t.p.text } else { t.p.muted }, w=Fill(1.0), line=18.0)
              |> ignore
            })
            |> ignore
            if flag(v, "granted") {
              end_words(c, tr("android-misc.permissions.granted"), t.p.muted)
            } else if asking {
              end_words(c, tr("android-misc.permissions.waiting"), t.p.muted)
            } else if flag(p, "canRequest") {
              let on = [("station", address), ("grant", id)]
              if end_action(
                  c,
                  "grant/" + id,
                  tr("android-misc.permissions.request"),
                  busy=is_doing(core, ["permissions.request"], on),
                  failed=failed_of(core, ["permissions.request"], on),
                ) {
                act(
                  core,
                  fill("android-misc.permissions.requestWhat", [("name", text(v, "name"))]),
                  "permissions.request",
                  obj([("station", str(address)), ("grant", str(id))]),
                )
              }
            } else {
              end_words(c, tr("android-misc.permissions.missing"), warn, weight=500)
            }
          })
          |> ignore
        }
      })
    },
  ]
  // what is unavailable now for want of a grant
  match opt_text(p, "note") {
    Some(n) =>
      out.push(fn() {
        c.box(w=Fill(1.0), padx=24.0, pb=10.0, fn() {
          c.text(n, size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
        })
        |> ignore
      })
    None => ()
  }
  out
}

///|
/// The variables everything the station starts for its agents runs with (StationAgentEnv), a row each, a secret's
/// value masked as the station shows it; its managers edit them in a sheet.
fn station_agent_env(c : @ui.Ctx, core : Core, address : String, env : Array[Json], manager : Bool) -> Array[() -> Unit] {
  let t = @sf.theme()
  if env.length() == 0 && !manager {
    return []
  }
  [
    fn() { section_header(c, tr("android-settings.agentEnv.title"), start=S6) },
    fn() {
      list_card(c, fn() {
        if env.length() == 0 {
          list_row(c, fn() { row_title(c, tr("android-settings.agentEnv.empty"), color=t.p.muted) }) |> ignore
        }
        for e in env {
          list_row(c, fn() {
            c.box(w=Fill(1.0), fn() {
              mono(c, text(Some(e), "key"), size=15.0)
              mono(c, text(Some(e), "value"), size=13.0, color=t.p.muted)
            })
            |> ignore
          })
          |> ignore
        }
        if manager {
          let on = [("station", address)]
          if list_row(c, key="env-edit", fn() {
              row_title(c, tr("android-settings.env.edit"), color=t.p.accent)
              // saved (the sheet gone): a spinner until the station has them
              doing_mark(c, is_doing(core, ["agentEnv.form.save"], on), failed_of(core, ["agentEnv.form.save"], on))
            }) {
            open_agent_env(core, address)
          }
        }
      })
    },
  ]
}

///|
/// The station's variables as a .env file's lines (AgentEnvSheet), in the core's draft (`agentEnvForm`): what is wrong
/// with a line said under the field (in red where it keeps it from being saved); saved whole, the sheet closed at once.
fn open_agent_env(core : Core, station : String) -> Unit {
  env_form.val += 1
  let form = "mbui-env-" + env_form.val.to_string()
  let key = "agent-env/" + form
  let call = fn(action : String, input : Json) {
    act(
      core,
      tr(
        match action {
          "open" => "web-pages.stations.agentEnvRead"
          "edit" => "web-pages.stations.agentEnvEdit"
          "drop" => "web-pages.stations.agentEnvClose"
          _ => "web-pages.stations.agentEnvSave"
        },
      ),
      "agentEnv.form." + action,
      obj([("station", str(station)), ("form", str(form)), ("input", input)]),
      done=if action == "save" { tr("android-settings.saved") } else { "" },
    )
  }
  call("open", obj([]))
  let filled : Ref[Bool] = Ref(false)
  let sent : Ref[String] = Ref("")
  let dropped : Ref[Bool] = Ref(false)
  let drop = fn() {
    if !dropped.val {
      dropped.val = true
      call("drop", obj([]))
    }
  }
  open_sheet(
    0.85,
    fn(c, core) {
      let t = @sf.theme()
      let d = (core.topic)("agentEnvForm", { "station": str(station), "form": str(form) }).value
      sheet_head(c, tr("android-settings.agentEnv.title"))
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        scroll_page(c, key, [
          fn() {
            c.box(w=Fill(1.0), padx=20.0, pb=10.0, fn() {
              c.text(tr("android-settings.agentEnv.note"), size=12.0, color=t.p.muted, w=Fill(1.0), line=17.0) |> ignore
            })
            |> ignore
          },
          fn() {
            c.box(w=Fill(1.0), padx=20.0, pb=10.0, fn() {
              c.box(w=Fill(1.0), padx=12.0, pady=10.0, radius=12.0, bg=t.p.card, border=1.0, border_color=t.p.line, fn() {
                // the station's text in the field once it has come (set where the field is: its key is of this row)
                if !filled.val && d is Some(Object(_)) {
                  filled.val = true
                  sent.val = text(d, "text")
                  field_of(key).set(sent.val)
                }
                let r = c.editor(
                  key,
                  field=field_of(key),
                  placeholder="HTTPS_PROXY=http://127.0.0.1:7890\nNO_PROXY=localhost,.internal",
                  font_size=13.0,
                  max_lines=12,
                  plain=true,
                  line=20.0,
                  color=t.p.text,
                  placeholder_color=t.p.subtle,
                  caret_color=t.p.accent,
                  enter_sends=false,
                )
                // what was typed, to the core's draft (the field never waits on it)
                if filled.val && r.text != sent.val {
                  sent.val = r.text
                  call("edit", obj([("text", str(r.text))]))
                }
              })
              |> ignore
            })
            |> ignore
          },
          fn() {
            c.box(w=Fill(1.0), padx=20.0, gap=4.0, fn() {
              // (what the core read is of the words in the field now)
              if text(d, "text") == sent.val {
                for i, l in items(d, "lines") {
                  match opt_text(Some(l), "problem") {
                    Some(p) =>
                      c.text(
                        fill("web-pages.stations.agentEnvLine", [("line", (i + 1).to_string()), ("problem", p)]),
                        size=12.0,
                        color=if flag(Some(l), "error") { t.p.red } else { t.p.muted },
                        w=Fill(1.0),
                        line=17.0,
                      )
                      |> ignore
                    None => ()
                  }
                }
              }
            })
            |> ignore
          },
          fn() {
            let can_save = flag(d, "dirty") &&
              !flag(d, "pending") &&
              text(d, "text") == sent.val &&
              count(d, "errors") == 0
            c.box(dir=Row, w=Fill(1.0), padx=20.0, pt=10.0, pb=24.0, gap=8.0, justify=JEnd, fn() {
              if button(c, "env-cancel", tr("common.cancel"), false) {
                c.blur()
                close_sheet()
                drop()
              }
              if button(c, "env-save", tr("common.save"), true, enabled=can_save) {
                c.blur()
                close_sheet()
                dropped.val = true
                call("save", obj([]))
              }
            })
            |> ignore
          },
        ])
      })
      |> ignore
    },
    on_close=fn() { drop() },
  )
}

///|
/// A count of the variables' sheets opened: each its own draft (`form`).
let env_form : Ref[Int] = Ref(0)

///|
/// Whether the station's search finds the machine's person's own mail, messages and the like
/// (StationSearchSection: `search.setPersonal`, its managers').
fn station_search(c : @ui.Ctx, core : Core, address : String, personal : Bool, manager : Bool) -> Array[() -> Unit] {
  let t = @sf.theme()
  [
    fn() { section_header(c, tr("web-pages.stations.search.section"), start=S6) },
    fn() {
      list_card(c, fn() {
        let busy = is_doing(core, ["search.setPersonal"], [("station", address)])
        if list_row(c, key=if manager && !busy { "search-personal" } else { "" }, fn() {
            c.box(w=Fill(1.0), gap=5.0, fn() {
              c.text(tr("web-pages.stations.search.personal"), size=15.0, color=t.p.text, w=Fill(1.0), line=20.0)
              |> ignore
              c.text(tr("web-pages.stations.search.personalLine"), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0)
              |> ignore
            })
            |> ignore
            switch(c, personal)
          }) {
          act(
            core,
            tr("web-pages.stations.search.what"),
            "search.setPersonal",
            obj([("station", str(address)), ("personal", Json::boolean(!personal))]),
          )
        }
      })
    },
  ]
}

///|
/// The workspaces a station is in, a row each (StationWorkspaces): on its page in its home workspace for that one's
/// owners and admins, once it is in more than one.
fn station_workspaces(c : @ui.Ctx, core : Core, address : String) -> Array[() -> Unit] {
  let t = @sf.theme()
  let view = (core.topic)("memberships", { "station": str(address) }).value
  let list = items(view, "workspaces")
  if !flag(view, "manages") || list.length() < 2 {
    return []
  }
  [
    fn() { section_header(c, "Workspace", start=S6) },
    fn() {
      list_card(c, fn() {
        for w in list {
          list_row(c, fn() {
            row_title(c, text(Some(w), "name"))
            c.box(max_w=220.0, fn() {
              c.text(text(Some(w), "line"), size=14.0, color=t.p.muted, wrap=false, line=20.0) |> ignore
            })
            |> ignore
          })
          |> ignore
        }
      })
    },
  ]
}

///|
/// What changes of the versions from here are on their way (Versions.kt's own state: the one updating, checking, the
/// channel and the updating by itself as asked), and what failed: by the station.
priv struct VersionsState {
  updating : Map[String, String]
  checking : Map[String, Bool]
  switching : Map[String, String]
  turning : Map[String, Bool]
  failed : Map[String, String]
}

///|
let versions_state : VersionsState = {
  updating: {},
  checking: {},
  switching: {},
  turning: {},
  failed: {},
}

///|
/// A call of the station's versions (`software.*`) made, `before` set as under way, `after` once answered; its
/// failure said under the list.
fn version_call(core : Core, station : String, name : String, params : Array[(String, Json)], after : () -> Unit) -> Unit {
  versions_state.failed.remove(station)
  let p = [("station", str(station))]
  for x in params {
    p.push(x)
  }
  (core.call)(name, obj(p), fn(r) {
    after()
    match r {
      Ok(_) => ()
      Err(e) => versions_state.failed[station] = error_text(e)
    }
  })
}

///|
/// The station's versions as a section of its page (Versions.kt Versions): one to a row, the test channel's and the
/// updating by itself's switches for its managers, then the check (with when it last looked).
fn station_versions(c : @ui.Ctx, core : Core, station : String, updates : Array[Json], manager : Bool, beta : Bool) -> Array[() -> Unit] {
  if updates.length() == 0 {
    return []
  }
  let t = @sf.theme()
  let first = Some(updates[0])
  let checked = has(first, "checkedAt")
  let own = updates.iter().find_first(fn(v) { text(Some(v), "id") == "station" })
  let channel = match own {
    Some(v) => opt_text(Some(v), "channel")
    None => None
  }
  let auto = match own {
    Some(v) =>
      match field(Some(v), "auto") {
        Some(True) => Some(true)
        Some(False) => Some(false)
        _ => None
      }
    None => None
  }
  let checking = versions_state.checking.contains(station)
  let out : Array[() -> Unit] = [
    fn() {
      // (when it last looked, 上次检查 …, is left out: the app has no clock of the day's time yet)
      section_header(c, tr("android-misc.versions.title"), start=S6)
    },
    fn() {
      list_card(c, fn() {
        for v in updates {
          let id = text(Some(v), "id")
          version_row(c, Some(v), manager, versions_state.updating.get(station) == Some(id), fn() {
            versions_state.updating[station] = id
            version_call(core, station, "software.update", [("id", str(id))], fn() {
              versions_state.updating.remove(station)
            })
          })
        }
        match channel {
          Some(ch) if beta && manager => {
            let on = versions_state.switching.get(station).unwrap_or(ch) == "beta"
            let busy = versions_state.switching.contains(station)
            if list_row(c, key=if busy { "" } else { "versions-beta" }, fn() {
                row_lines(c, tr("android-misc.versions.beta"), tr("android-misc.versions.beta.text"), wrap_sub=true)
                switch(c, on)
              }) {
              let to = if on { "stable" } else { "beta" }
              versions_state.switching[station] = to
              version_call(core, station, "software.channel", [("channel", str(to))], fn() {
                versions_state.switching.remove(station)
              })
            }
          }
          _ => ()
        }
        match auto {
          Some(a) if manager => {
            let on = versions_state.turning.get(station).unwrap_or(a)
            let busy = versions_state.turning.contains(station)
            let idle = match own {
              Some(v) => flag(Some(v), "idleOnly")
              None => false
            }
            if list_row(c, key=if busy { "" } else { "versions-auto" }, fn() {
                row_lines(
                  c,
                  tr("android-misc.versions.auto"),
                  tr(if idle { "android-misc.versions.auto.idle" } else { "android-misc.versions.auto.text" }),
                  wrap_sub=true,
                )
                switch(c, on)
              }) {
              versions_state.turning[station] = !on
              version_call(core, station, "software.auto", [("on", Json::boolean(!on))], fn() {
                versions_state.turning.remove(station)
              })
            }
          }
          _ => ()
        }
        if list_row(c, key=if !checked || checking { "" } else { "versions-check" }, fn() {
            row_title(
              c,
              tr(
                if !checked {
                  "android-misc.versions.checkingVersions"
                } else if checking {
                  "android-misc.versions.checking"
                } else {
                  "android-misc.versions.check"
                },
              ),
              color=t.p.muted,
            )
            if checking || !checked {
              spinner(c)
            }
          }) {
          versions_state.checking[station] = true
          version_call(core, station, "software.check", [], fn() { versions_state.checking.remove(station) })
        }
      })
    },
  ]
  match versions_state.failed.get(station) {
    Some(f) =>
      out.push(fn() {
        c.box(w=Fill(1.0), padx=24.0, pb=10.0, fn() {
          c.text(f, size=13.0, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore
        })
        |> ignore
      })
    None => ()
  }
  out
}

///|
/// One piece of software (VersionRow): its name and version, what is out, and what may be done with it; under it
/// what the web says on hover, its line kept while there is nothing to say.
fn version_row(c : @ui.Ctx, v : Json?, manager : Bool, busy : Bool, update : () -> Unit) -> Unit {
  let t = @sf.theme()
  let id = text(v, "id")
  let installed = flag(v, "installed")
  let shown = if installed {
    match opt_text(v, "version") {
      Some(x) => x
      None => tr(if id == "station" { "android-misc.versions.dev" } else { "android-misc.versions.unknown" })
    }
  } else {
    tr("android-misc.versions.notInstalled")
  }
  let state = text(v, "state")
  let latest = opt_text(v, "latest")
  let note = join(
    [
      if state == "idle" { text(v, "done") } else { "" },
      text(v, "note"),
      if installed && !flag(v, "newer") && !flag(v, "downgrade") && latest is Some(_) {
        tr("android-misc.updates.latest")
      } else {
        ""
      },
      if installed && latest is None && has(v, "checkedAt") { tr("android-misc.versions.checkFailed") } else { "" },
      if state == "failed" { text(v, "message") } else { "" },
    ].map(fn(s) { s.trim(chars=" \t\n").to_owned() }),
    tr("android-misc.versions.sep"),
  )
  let action = fn(label : String) {
    if manager && flag(v, "updatable") {
      if busy {
        spinner(c, inline=true)
      } else if tap_text(c, "version-do/" + id, label, size=13.0) {
        update()
      }
    }
  }
  let latest_words = fn(version : String) {
    c.box(dir=Row, gap=3.0, align=ACenter, fn() {
      @sf.icon(c, "arrow-right", size=18.0, color=t.p.accent) |> ignore
      c.text(version, size=13.0, weight=500, color=t.p.accent, wrap=false, line=18.0) |> ignore
    })
    |> ignore
  }
  list_row(c, fn() {
    c.box(w=Fill(1.0), fn() {
      c.box(dir=Row, w=Fill(1.0), align=ACenter, fn() {
        c.box(dir=Row, w=Fill(1.0), gap=6.0, align=ACenter, fn() {
          c.text(text(v, "name"), size=15.0, color=t.p.text, wrap=false, line=21.0) |> ignore
          c.text(shown, size=13.0, color=t.p.muted, wrap=false, line=18.0) |> ignore
          if text(v, "channel") == "beta" {
            c.box(padx=6.0, pady=1.0, radius=9.0, bg=t.p.accent_bg, fn() {
              c.text(tr("android-misc.versions.beta"), size=11.0, weight=500, color=t.p.accent, wrap=false, line=15.0)
              |> ignore
            })
            |> ignore
          }
        })
        |> ignore
        c.box(dir=Row, pl=12.0, gap=10.0, align=ACenter, fn() {
          if state == "updating" {
            c.box(dir=Row, gap=6.0, align=ACenter, fn() {
              if has(v, "percent") {
                fill_chip(c, count(v, "percent"), "progress", "", count(v, "percent").to_string() + "%", small=true)
              } else {
                spinner(c, inline=true)
              }
              c.text(
                match opt_text(v, "progress") {
                  Some(p) => p
                  None => tr(if installed { "android-misc.versions.updating" } else { "android-misc.versions.installing" })
                },
                size=13.0,
                weight=500,
                color=t.p.accent,
                wrap=false,
                line=18.0,
              )
              |> ignore
            })
            |> ignore
          } else if state == "failed" {
            c.text(
              tr(if installed { "android-misc.versions.updateFailed" } else { "android-misc.versions.installFailed" }),
              size=13.0,
              weight=500,
              color=t.p.red,
              wrap=false,
              line=18.0,
            )
            |> ignore
            action(tr("common.retry"))
          } else if !installed {
            action(tr("android-misc.versions.install"))
          } else {
            match latest {
              Some(l) if flag(v, "newer") => {
                latest_words(l)
                action(tr("android-misc.versions.update"))
              }
              Some(l) if flag(v, "downgrade") => {
                latest_words(l)
                action(tr("android-misc.versions.backToStable"))
              }
              _ => ()
            }
          }
        })
        |> ignore
      })
      |> ignore
      c.text(
        if note == "" { " " } else { note },
        size=13.0,
        color=if state == "failed" { t.p.red } else { t.p.muted },
        w=Fill(1.0),
        line=18.0,
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

// ---------------------------------------------------------------------------
// 共享调试: this device's adb lent to a station's agents (app/screens/AdbShare.kt)

///|
/// Whether this device can lend its adb (AdbShare.supported): Android 11 and on, with the host finding Wireless
/// debugging's ports, which this app's hosts do not do yet: none can.
fn adb_supported() -> Bool {
  false
}

///|
/// A station's 共享调试 page (AdbShareScreen): this device's adb lent to the station's agents, how it stands (the
/// core's `adbShare`), what the phone needs for it, pairing the first time. The lending itself is the core's and the
/// host's; this page shows and asks (`adb.stop`, `adb.pair`, `adb.grant`).
fn adb_page(c : @ui.Ctx, core : Core, here : Here, address : String) -> Unit {
  let t = @sf.theme()
  let name = match station_of(core, here, address) {
    Some(s) => text(Some(s), "name")
    None => station_name(address)
  }
  let view = (core.topic)("adbShare", Map([])).value
  let sharing = flag(view, "sharing")
  let there = sharing && text(view, "station") == address
  let elsewhere = sharing && text(view, "station") != address
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    nav_bar(c, core, "Station", tr("android-misc.adb.title"), sub=fn() {
      c.text(name, size=11.0, color=t.p.muted, wrap=false, line=16.0) |> ignore
    })
    let blocks : Array[() -> Unit] = [
      fn() { gap(c, 12.0) },
      fn() {
        c.box(w=Fill(1.0), padx=24.0, pb=10.0, fn() {
          c.text(fill("android-misc.adb.about", [("name", name)]), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0)
          |> ignore
        })
        |> ignore
      },
    ]
    if !adb_supported() && !there {
      blocks.push(fn() {
        list_card(c, fn() {
          list_row(c, fn() {
            c.text(tr("android-misc.adb.unsupported"), size=15.0, color=t.p.muted, w=Fill(1.0), line=21.0) |> ignore
          })
          |> ignore
        })
      })
    } else {
      blocks.push(fn() {
        list_card(c, fn() {
          // lent or not, as settings' switches are; what it is doing under the title
          if list_row(c, key="adb-switch", fn() {
              c.box(w=Fill(1.0), fn() {
                c.text(tr("android-misc.adb.title"), size=15.0, color=t.p.text, w=Fill(1.0), line=21.0) |> ignore
                let stopped = if !sharing { text(view, "message") } else { "" }
                let sub = if there {
                  adb_state(view)
                } else if elsewhere {
                  tr("android-misc.adb.elsewhere")
                } else if stopped != "" {
                  stopped
                } else {
                  tr("android-misc.adb.hour")
                }
                let adb = text(view, "adb")
                c.text(
                  sub,
                  size=13.0,
                  color=if there && (adb == "missing" || adb == "failed") { t.p.red } else { t.p.muted },
                  w=Fill(1.0),
                  line=18.0,
                )
                |> ignore
              })
              |> ignore
              let adb = text(view, "adb")
              doing_mark(c, there && (text(view, "phase") != "offered" || adb == "" || adb == "connecting"), None)
              switch(c, there)
            }) {
            if there {
              act(core, tr("android-misc.adb.stopWhat"), "adb.stop", obj([]))
            } else {
              (core.say)(tr("android-misc.adb.unsupported"))
            }
          }
          if there {
            match opt_text(view, "serial") {
              Some(serial) if text(view, "adb") == "connected" =>
                list_row(c, fn() {
                  row_title(c, tr("android-misc.adb.agentsUse"))
                  mono(c, "adb -s " + serial, size=13.0, color=t.p.muted)
                })
                |> ignore
              _ => ()
            }
            // what the station said, when it says more than the line above
            let said = text(view, "message")
            let line = adb_state(view)
            if text(view, "adb") != "connected" && said != "" && said != line && !line.has_suffix(said) {
              list_row(c, fn() {
                c.text(said, size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
              })
              |> ignore
            }
          }
        })
      })
      if there && text(view, "adb") == "unpaired" {
        let busy = is_doing(core, ["adb.pair"], [])
        let open = has(view, "pairPort")
        blocks.push(fn() { section_header(c, tr("android-misc.adb.pair.title"), start=S6) })
        blocks.push(fn() {
          list_card(c, fn() {
            // split screen: the code typed here
            if list_row(c, key=if open && !busy { "adb-pair-here" } else { "" }, fn() {
                row_lines(
                  c,
                  tr("android-misc.adb.pair.here"),
                  tr(if open { "android-misc.adb.pair.here.split" } else { "android-misc.adb.pair.here.wait" }),
                  title_color=if open { t.p.text } else { t.p.subtle },
                  wrap_sub=true,
                )
                doing_mark(c, busy, failed_of(core, ["adb.pair"], []))
              }) {
              ask(
                tr("android-misc.adb.pair.ask"),
                "",
                tr("android-misc.adb.code"),
                tr("android-misc.adb.pair.action"),
                hint=tr("android-misc.adb.pair.hint"),
                fn(code) {
                  let digits = StringBuilder()
                  for ch in code {
                    if ch >= '0' && ch <= '9' {
                      digits.write_char(ch)
                    }
                  }
                  act(
                    core,
                    tr("android-misc.adb.pair.action"),
                    "adb.pair",
                    obj([("code", str(digits.to_string()))]),
                    done=tr("android-misc.adb.paired"),
                  )
                },
              )
            }
          })
        })
      }
    }
    blocks.push(fn() {
      c.box(w=Fill(1.0), padx=24.0, pt=16.0, fn() {
        c.text(tr("android-misc.adb.warning"), size=12.0, color=t.p.subtle, w=Fill(1.0), line=17.0) |> ignore
      })
      |> ignore
    })
    blocks.push(fn() { gap(c, 30.0) })
    scroll_page(c, "adb/" + address, blocks)
  })
  |> ignore
}

///|
/// How the lending stands, in a line (AdbShare.kt state).
fn adb_state(view : Json?) -> String {
  let adb = text(view, "adb")
  if text(view, "phase") != "offered" {
    return match opt_text(view, "message") {
      Some(m) => fill("android-misc.adb.connecting.why", [("why", m)])
      None => tr("android-misc.adb.connecting")
    }
  }
  match adb {
    "connected" =>
      // (还剩 N 分钟 left out: the app has no clock of the day's time yet)
      tr("android-misc.adb.connected")
    "unpaired" => tr("android-misc.adb.unpaired")
    "unauthorized" => tr("android-misc.adb.unauthorized")
    "off" => tr("android-misc.adb.off")
    "missing" => tr("android-misc.adb.missing")
    "failed" => tr("android-misc.adb.failed")
    _ => tr("android-misc.adb.attaching")
  }
}

///|
/// The station at `address` as the workspace's `stations` has it.
fn station_of(core : Core, here : Here, address : String) -> Json? {
  match stations_of(core, here).value {
    Some(Array(a)) => a.iter().find_first(fn(x) { text(Some(x), "station") == address })
    _ => None
  }
}
