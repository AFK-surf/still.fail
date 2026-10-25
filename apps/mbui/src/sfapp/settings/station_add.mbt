// Adding a station (Settings.kt openAddStation, AddStationSteps, JoinStation, FirstStation; the narrow web's
// Stations.tsx): a new machine named, the one command that installs still.fail there and joins it (`workspace.enroll`)
// copied, and the wait for it to join; or, for whoever manages another workspace too, a station of that one added
// here as it is (`station.join`). The workspace's owners and admins add stations: Station's ＋, or its first one in
// the page itself while it has none.

///|
/// What the adding has come to: the sheet's (and the first station's, in its page) as they go on.
priv struct Adding {
  /// a station of another workspace (the choice's second side)
  mut existing : Bool
  /// the command made: (install, command)
  mut made : (String, String)?
  /// why the command could not be made, or a station not joined
  mut error : String
  /// the stations of the workspace when it opened (one not among them has joined)
  mut known : Array[String]
  /// the stations of another workspace joined from the sheet: kept where they were, said so
  took : Array[Json]
  /// the order the joinable ones came in
  order : Map[String, Int]
  /// the one picked to join
  mut picked : String
  /// a count of times opened: its field is its own
  mut serial : Int
}

///|
let adding : Adding = {
  existing: false,
  made: None,
  error: "",
  known: [],
  took: [],
  order: {},
  picked: "",
  serial: 0,
}

///|
/// As before anything was asked.
fn adding_reset(known : Array[String], existing : Bool) -> Unit {
  adding.existing = existing
  adding.made = None
  adding.error = ""
  adding.known = known
  adding.took.clear()
  adding.order.clear()
  adding.picked = ""
  adding.serial += 1
}

///|
/// The ids of the workspace's stations as the core has them now (None while not read).
fn station_ids(core : Core, here : Here) -> Array[String]? {
  match stations_of(core, here).value {
    Some(Array(a)) => Some(a.map(fn(s) { text(Some(s), "id") }))
    _ => None
  }
}

///|
/// A place's primary action (PlaceAction: the bar's notch, a pushed page's ＋), None where it has none now: Station's
/// adds a station (its owners and admins, once its stations are read), Profile's a profile (once a station is online).
/// 连接's is its page's (src/sfdesk connects.mbt connects_add).
pub fn place_action(core : Core, here : Here, place : String) -> (() -> Unit)? {
  match place {
    "stations" =>
      match station_ids(core, here) {
        Some(ids) if manager_of(core, here) == Some(true) => Some(fn() { open_add_station(core, here, ids) })
        _ => None
      }
    // a profile is added on a station online (the only one, without asking)
    "profiles" => {
      let online = online_stations(core, here)
      if online.length() == 0 {
        return None
      }
      let go = fn(station : String) { (core.push)(NewProfile(station)) }
      Some(fn() {
        if online.length() == 1 {
          go(text(Some(online[0]), "station"))
        } else {
          open_pick_station(
            tr("android-settings.profile.add"),
            online,
            go,
          )
        }
      })
    }
    _ => None
  }
}

///|
/// 添加 station (openAddStation): the choice of a new machine or one of another workspace's (while there is one to
/// offer), then that one's steps.
fn open_add_station(_core : Core, here : Here, known : Array[String], existing? : Bool = false) -> Unit {
  adding_reset(known, existing)
  open_sheet(0.72, fn(c, core) {
    let joinable = (core.topic)("joinable", { "workspace": str(here.workspace) }).value
    let rows = joinable_rows(joinable)
    let offered = flag(joinable, "offered") && rows.length() > 0
    sheet_head(c, tr("android-settings.station.add"))
    // the choice stays at the top; only what is under it scrolls
    if offered && adding.made is None {
      c.box(w=Fill(1.0), pl=20.0, pr=20.0, pb=10.0, fn() {
        let i = @sf.segmented(
          c,
          "add-kind",
          [tr("web-pages.settings.stations.kindNew"), tr("web-pages.settings.stations.kindExisting")],
          if adding.existing { 1 } else { 0 },
        )
        adding.existing = i == 1
      })
      |> ignore
    }
    if offered && adding.existing && adding.made is None {
      join_existing(c, core, here, rows, flag(joinable, "loading"))
    } else {
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        scroll_page(c, "add-station/" + adding.serial.to_string(), [
          fn() {
            c.box(w=Fill(1.0), pl=20.0, pr=20.0, pb=10.0, fn() {
              c.text(
                fill("android-settings.station.addNote", [("app", "still.fail")]),
                size=@sf.theme().t.meta,
                color=@sf.theme().p.muted,
                w=Fill(1.0),
                line=20.0,
              )
              |> ignore
            })
            |> ignore
          },
          fn() {
            c.box(w=Fill(1.0), pl=20.0, pr=20.0, pb=24.0, fn() {
              add_station_steps(c, core, here, cancel=true, fn() { close_sheet() })
            })
            |> ignore
          },
        ])
      })
      |> ignore
    }
  })
}

///|
/// The joinable stations to show (the core's `joinable`, with those joined from here kept where they were).
fn joinable_rows(joinable : Json?) -> Array[Json] {
  let items_now = items(joinable, "items")
  for s in items_now {
    let id = text(Some(s), "station")
    if !adding.order.contains(id) {
      adding.order[id] = adding.order.length()
    }
  }
  let rows = items_now.filter(fn(s) {
    !adding.took.iter().any(fn(t) { text(Some(t), "station") == text(Some(s), "station") })
  })
  for t in adding.took {
    rows.push(t)
  }
  rows.sort_by_key(fn(s) { adding.order.get(text(Some(s), "station")).unwrap_or(0) })
  rows
}

///|
/// Whether a station of another workspace was joined from here.
fn took_it(s : Json) -> Bool {
  adding.took.iter().any(fn(t) { text(Some(t), "station") == text(Some(s), "station") })
}

///|
/// A station of another workspace the viewer manages picked and added here as it is (JoinStation: `station.join`):
/// what that shares of the machine said under the list, why it was refused in red; joined, it stays in its place, said
/// so, and the next one open is picked.
fn join_existing(c : @ui.Ctx, core : Core, here : Here, rows : Array[Json], loading : Bool) -> Unit {
  let t = @sf.theme()
  let ws = here.workspace
  // one whose home's security mode keeps it out is shown, not picked
  let open = rows.filter(fn(s) { !flag(Some(s), "needsLock") && !took_it(s) })
  let chosen = match open.iter().find_first(fn(s) { text(Some(s), "station") == adding.picked }) {
    Some(s) => Some(s)
    None => open.get(0)
  }
  let busy = match chosen {
    Some(s) => is_doing(core, ["station.join"], [("station", text(Some(s), "station")), ("workspace", ws)])
    None => false
  }
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      let blocks : Array[() -> Unit] = [
        fn() {
          c.box(w=Fill(1.0), pb=10.0, fn() {
            c.text(tr("web-pages.settings.stations.existingLead"), size=t.t.meta, color=t.p.muted, w=Fill(1.0), line=20.0)
            |> ignore
          })
          |> ignore
        },
      ]
      if rows.length() == 0 {
        blocks.push(fn() {
          c.box(w=Fill(1.0), pb=10.0, fn() {
            if loading {
              wait_line(c, tr("common.reading"))
            } else {
              c.text(tr("web-pages.settings.stations.existingNone"), size=t.t.meta, color=t.p.muted, w=Fill(1.0), line=20.0)
              |> ignore
            }
          })
          |> ignore
        })
      }
      for s in rows {
        blocks.push(fn() {
          let v = Some(s)
          let id = text(v, "station")
          let mark = fn() { station_mark(c, v, 15.0, t.p.text) }
          let marked = @sf.has_station_mark(text(v, "emoji"), text(v, "icon"))
          if took_it(s) {
            @sf.choice_row(c, "join/" + id, true, text(v, "name"), note=tr("web-pages.settings.stations.joinedRow"), lead?=if marked {
              Some(mark)
            } else {
              None
            })
            |> ignore
          } else if @sf.choice_row(c, "join/" + id, match chosen {
                Some(ch) => text(Some(ch), "station") == id
                None => false
              }, text(v, "name"), note=text(v, "line"), disabled=!(!busy && !flag(v, "needsLock")), lead?=if marked {
                Some(mark)
              } else {
                None
              }) {
            adding.picked = id
            adding.error = ""
          }
        })
      }
      blocks.push(fn() {
        c.box(w=Fill(1.0), pt=10.0, gap=10.0, fn() {
          c.text(tr("web-pages.settings.stations.softIsolation"), size=t.t.caption, color=t.p.muted, w=Fill(1.0), line=17.0)
          |> ignore
          if adding.error != "" {
            c.text(adding.error, size=t.t.meta, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore
          }
        })
        |> ignore
      })
      // (in the sheet's column, its rows reaching out across its sides: @sf.sheet_column)
      scroll_page(c, "join-station/" + adding.serial.to_string(), blocks.map(fn(b) { fn() { @sf.sheet_column(c, b) } }))
    })
    |> ignore
    c.box(dir=Row, w=Fill(1.0), padx=20.0, pt=10.0, pb=24.0, gap=8.0, justify=JEnd, fn() {
      if @sf.button(c, tr(if adding.took.length() == 0 { "common.cancel" } else { "common.done" }), key="join-close") {
        close_sheet()
      }
      if @sf.button(c, tr("web-pages.settings.stations.joinAction"), key="join-go", tone=Primary, busy=busy, disabled=chosen is None) {
        match chosen {
          Some(s) => {
            adding.error = ""
            let station = text(Some(s), "station")
            (core.call)("station.join", obj([("station", str(station)), ("workspace", str(ws))]), fn(r) {
              match r {
                Ok(v) => {
                  // as it is called here, when the station says
                  let name = match text(field(Some(v), "joined"), "name") {
                    "" => text(Some(s), "name")
                    n => n
                  }
                  let kept = match s {
                    Object(m) => {
                      let m2 = m.copy()
                      m2["name"] = str(name)
                      Json::object(m2)
                    }
                    other => other
                  }
                  adding.took.push(kept)
                }
                Err(e) => adding.error = error_text(e)
              }
            })
          }
          None => ()
        }
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A station's name, then the command that installs still.fail on that machine and joins it (one with still.fail too),
/// copied from here, and the wait for it (AddStationSteps); joined, said in green with 完成 (`done`). `cancel`: a way
/// out beside the first step. `label` and `placeholder`: the name's line, as the first station's page words it.
fn add_station_steps(
  c : @ui.Ctx,
  core : Core,
  here : Here,
  done : () -> Unit,
  cancel? : Bool = false,
  label? : String = tr("android-settings.station.name"),
  placeholder? : String = tr("android-settings.station.namePlaceholder"),
) -> Unit {
  let t = @sf.theme()
  let busy = is_doing(core, ["workspace.enroll"], [("account", here.sub), ("workspace", here.workspace)])
  // one not among those there when it opened has joined
  let joined = match adding.made {
    Some(_) =>
      match stations_of(core, here).value {
        Some(Array(a)) => a.iter().find_first(fn(s) { !adding.known.contains(text(Some(s), "id")) })
        _ => None
      }
    None => None
  }
  c.box(w=Fill(1.0), gap=10.0, fn() {
    match (adding.made, joined) {
      (None, _) => {
        c.text(label, size=t.t.meta, weight=600, color=t.p.text, w=Fill(1.0), line=18.0) |> ignore
        let name = field_box(c, "station-name/" + adding.serial.to_string(), placeholder).trim(chars=" \t\n").to_owned()
        if adding.error != "" {
          c.text(adding.error, size=t.t.meta, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore
        }
        c.box(dir=Row, w=Fill(1.0), pt=6.0, gap=8.0, justify=JEnd, fn() {
          if cancel && @sf.button(c, tr("common.cancel"), key="add-cancel") {
            c.blur()
            close_sheet()
          }
          if @sf.button(c, tr("android-settings.station.make"), key="add-make", tone=Primary, busy=busy, disabled=name == "") {
            c.blur()
            adding.error = ""
            (core.call)(
              "workspace.enroll",
              obj([("workspace", str(here.workspace)), ("name", str(name)), ("account", str(here.sub))]),
              fn(r) {
                match r {
                  Ok(v) => adding.made = Some((text(Some(v), "install"), text(Some(v), "command")))
                  Err(e) => adding.error = error_text(e)
                }
              },
            )
          }
        })
        |> ignore
      }
      (Some(_), Some(s)) => {
        c.box(dir=Row, w=Fill(1.0), padx=12.0, pady=10.0, gap=8.0, radius=12.0, bg=@sf.alpha(t.p.green, 0.12), align=ACenter, fn() {
          @sf.icon(c, "check", size=16.0, color=t.p.green) |> ignore
          c.text(fill("android-settings.station.joined", [("name", text(Some(s), "name"))]), size=t.t.ui, color=t.p.green, w=Fill(1.0), line=20.0)
          |> ignore
        })
        |> ignore
        c.box(dir=Row, w=Fill(1.0), justify=JEnd, fn() {
          if @sf.button(c, tr("common.done"), key="add-done", tone=Primary) {
            done()
          }
        })
        |> ignore
      }
      (Some((install, _)), None) => {
        c.text(tr("android-settings.station.run"), size=t.t.ui, color=t.p.text, w=Fill(1.0), line=20.0) |> ignore
        command_box(c, core, install)
        c.text(fill("android-settings.station.runNote", [("app", "still.fail")]), size=t.t.meta, color=t.p.muted, w=Fill(1.0), line=18.0)
        |> ignore
        wait_line(c, tr("android-settings.station.waiting"))
      }
    }
  })
  |> ignore
}

///|
/// A command to run elsewhere, with a button that copies it (Settings.kt CommandBox): on surface2, a block of the
/// ladder's (round by its row corner), its copy button the ladder's inset in from its top and end, as tall as two of
/// its lines and its inset under them (so with one or two lines as far from its foot too), round by the ladder's next
/// step there (mbui works it out). `reach`: in a card's foot corners, how it reaches past the card's words
/// (block_across).
fn command_box(c : @ui.Ctx, core : Core, words : String, reach? : @ui.Style) -> Unit {
  let t = @sf.theme()
  let id = c.id("command-copy")
  if hit(c, id) {
    c.copy_text(words)
    (core.say)(tr("common.copied"))
  }
  c.box(
    style=reach.unwrap_or(@ui.style()),
    dir=Row,
    w=Fill(1.0),
    pl=12.0,
    pr=@sf.corner_inset,
    pt=@sf.corner_inset,
    pb=@sf.corner_inset,
    gap=8.0,
    radius=@sf.command_box_corner,
    bg=t.p.card2,
    border=1.0,
    border_color=t.p.line,
    fn() {
      c.box(w=Fill(1.0), fn() { mono(c, words, size=12.0, line=command_line, wrap=true) }) |> ignore
      c.box(
        w=Px(command_copy),
        h=Px(command_copy),
        radius=@sf.small_corner,
        bg=t.p.chip,
        align=ACenter,
        justify=JCenter,
        id~,
        fn() {
          @sf.icon(c, "copy", size=16.0, color=t.p.text) |> ignore
          @motion.ripple(c, id, @sf.small_corner)
        },
      )
      |> ignore
    },
  )
  |> ignore
}

///|
/// A command's line, and its copy button: two of its lines high.
let command_line : Double = 18.0

///|
let command_copy : Double = command_line * 2.0

///|
/// A workspace with no station (FirstStation): what a station is, then, for its owners and admins, its first one added
/// in the page (its name, the command, the wait), with a station of another workspace offered instead; anyone else is
/// told to wait for them.
fn first_station(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let t = @sf.theme()
  let w = workspace_view(core, here)
  c.box(w=Fill(1.0), pad=30.0, gap=10.0, align=ACenter, fn() {
    @sf.drawable(c, if t.dark { "illus_no_station_dark" } else { "illus_no_station" }, 240.0) |> ignore
    c.text(tr("android-settings.station.first"), size=t.t.title, weight=600, color=t.p.text, center=true, w=Fill(1.0))
    |> ignore
    c.text(tr("android-settings.station.firstNote"), size=t.t.meta, color=t.p.muted, center=true, w=Fill(1.0), line=20.0)
    |> ignore
    c.box(w=Fill(1.0), pt=8.0, gap=12.0, fn() {
      match w.value {
        // not read yet, or could not be: in red then, no longer turning
        None =>
          wait_line(
            c,
            match w.error {
              Some(e) => error_text(e)
              None => tr("android-settings.workspace.reading")
            },
            error=w.error is Some(_),
          )
        Some(_) if !(text(w.value, "role") == "owner" || text(w.value, "role") == "admin") =>
          c.box(w=Fill(1.0), padx=12.0, pady=10.0, radius=12.0, bg=@sf.alpha(warn, 0.12), fn() {
            c.text(tr("android-settings.station.wait"), size=t.t.meta, color=t.p.text, w=Fill(1.0), line=19.5) |> ignore
          })
          |> ignore
        Some(_) => {
          // (the page's own steps: a new start each time the page has no station)
          if sheet.draw is None && adding.known.length() > 0 {
            adding_reset([], false)
          }
          add_station_steps(
            c,
            core,
            here,
            label=tr("android-settings.station.firstName"),
            placeholder=tr("android-settings.station.firstPlaceholder"),
            fn() {  },
          )
          let joinable = (core.topic)("joinable", { "workspace": str(here.workspace) }).value
          if flag(joinable, "offered") && items(joinable, "items").length() > 0 {
            if tap_text(c, "first-existing", tr("web-pages.settings.stations.firstExisting"), size=14.0) {
              open_add_station(core, here, [], existing=true)
            }
          }
        }
      }
    })
    |> ignore
  })
  |> ignore
}
