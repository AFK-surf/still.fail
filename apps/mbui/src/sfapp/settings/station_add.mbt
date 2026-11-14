// Adding a station (Settings.kt openAddStation, AddStationSteps, JoinStation, FirstStation; the narrow web's
// Stations.tsx): a new machine named, the command that installs still.fail there and joins it (`workspace.enroll`:
// macOS's and Linux's, and Windows' in PowerShell) copied, and the wait for it to join; or, for whoever manages another
// workspace too, a station of that one added here as it is (`station.join`). The workspace's owners and admins add
// stations: Station's ＋, or its first one in the page itself while it has none. What the new machine will be is chosen
// as it is named (2026-11-10): a whole station, or one that only runs tasks (a rig: `rig.add`, its command naming its
// person's own lock), which any member adds, as theirs.

///|
/// What the adding has come to: the sheet's (and the first station's, in its page) as they go on.
priv struct Adding {
  /// a station of another workspace (the choice's second side)
  existing : @signals.Signal[Bool]
  /// one that only runs tasks (the mode's second side; a member's only one)
  tasks : @signals.Signal[Bool]
  /// the commands made: (macOS's and Linux's, Windows' in PowerShell: "" from a cloud that gives none)
  made : @signals.Signal[(String, String)?]
  /// why the command could not be made, or a station not joined
  error : @signals.Signal[String]
  /// why adding this machine via `station.join` failed
  here_error : @signals.Signal[String]
  /// the stations of the workspace when it opened (one not among them has joined)
  known : @signals.Signal[Array[String]]
  /// the stations of another workspace joined from the sheet: kept where they were, said so
  took : @sf.LiveArray[Json]
  /// the order the joinable ones came in
  order : @sf.LiveMap[String, Int]
  /// the one picked to join
  picked : @signals.Signal[String]
  /// a count of times opened: its field is its own
  serial : @signals.Signal[Int]
}

///|
let adding : Adding = {
  existing: @signals.signal(false, same=fn(a, b) { a == b }),
  tasks: @signals.signal(false, same=fn(a, b) { a == b }),
  made: @signals.signal(None),
  error: @signals.signal("", same=fn(a, b) { a == b }),
  here_error: @signals.signal("", same=fn(a, b) { a == b }),
  known: @signals.signal([]),
  took: @sf.LiveArray::new(),
  order: @sf.LiveMap::new(),
  picked: @signals.signal("", same=fn(a, b) { a == b }),
  serial: @signals.signal(0, same=fn(a, b) { a == b }),
}

///|
/// As before anything was asked.
fn adding_reset(known : Array[String], existing : Bool, tasks? : Bool = false) -> Unit {
  adding.existing.set(existing)
  adding.tasks.set(tasks)
  adding.made.set(None)
  adding.error.set("")
  adding.here_error.set("")
  adding.known.set(known)
  adding.took.clear()
  adding.order.clear()
  adding.picked.set("")
  adding.serial.set(adding.serial.get() + 1)
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
/// 连接's is its page's (src/sfpages connects.mbt connects_add).
pub fn place_action(core : Core, here : Here, place : String) -> ((@sf.Beside) -> Unit)? {
  match place {
    "stations" =>
      match station_ids(core, here) {
        Some(ids) if manager_of(core, here) == Some(true) => Some(fn(from) { open_add_station(core, here, ids, from=from.anchor()) })
        // (a member adds one that only runs tasks, theirs: no whole station, none of another workspace's)
        Some(ids) if text(workspace_view(core, here).value, "role") == "member" => Some(fn(from) { open_add_station(core, here, ids, tasks=true, from=from.anchor()) })
        _ => None
      }
    // a profile is added on a station online (the only one, without asking)
    "profiles" => {
      let online = online_stations(core, here)
      if online.length() == 0 {
        return None
      }
      let go = fn(station : String) { (core.push)(NewProfile(station)) }
      Some(fn(from) {
        if online.length() == 1 {
          go(text(Some(online[0]), "station"))
        } else {
          open_pick_station(online, go, from~)
        }
      })
    }
    _ => None
  }
}

///|
/// 添加 station (openAddStation): the choice of a new machine or one of another workspace's (while there is one to
/// offer), then that one's steps: the library's panel opened `from` what was pressed (a form: a sheet on 小屏, a dialog
/// in the window's middle on 中屏 and 大屏), what it holds at its own sides. What it holds and its foot are nodes of the
/// window's tree, made once as it opens (@sf.panel_nodes), each bound to what the core and the adding say now.
fn open_add_station(
  core : Core,
  here : Here,
  known : Array[String],
  existing? : Bool = false,
  tasks? : Bool = false,
  from? : @sf.Anchor = Unanchored,
) -> Unit {
  let known = [..known, ..rigs_listed(core, here).map(fn(r) { text(Some(r), "id") })]
  adding_reset(known, existing, tasks~)
  let manager = manager_of(core, here) == Some(true)
  // (whether this machine can be added here, as the host says it as the panel opens: what the panel shows, on its way
  // out too, as sfpages' 本机 Station reads the host as it is asked)
  let here_addable = local_station_addable_in(here.workspace, known)
  @sf.panel_nodes(
    tr("android-settings.station.add"),
    fn(v, close) { add_station_body(v, core, here, manager, here_addable, close) },
    from~,
    tall=0.72,
    form=true,
    foot=fn(v, close) { add_station_foot(v, core, here, manager, close) },
  )
}

///|
/// What the adding offers now: the joinable stations to show (joinable_rows), whether another workspace's are offered
/// (to its managers, while there is one), whether that side is the one chosen, and whether a command is made.
priv struct AddingNow {
  rows : () -> Array[Json]
  offered : () -> Bool
  joining : () -> Bool
}

///|
fn adding_now(core : Core, here : Here, manager : Bool) -> AddingNow {
  let joinable = fn() { (core.topic)("joinable", { "workspace": str(here.workspace) }).get().value }
  let rows = fn() { joinable_rows(joinable()) }
  let offered = fn() { manager && flag(joinable(), "offered") && rows().length() > 0 }
  { rows, offered, joining: fn() { offered() && adding.existing.get() && adding.made.get() is None } }
}

///|
/// 添加 station's body in node `v`: the kind's choice at its top while one of another workspace's is offered, the
/// mode's (its managers', for a new machine), then the side chosen: those of another workspace, or this machine (where
/// it can be added here), what a station is and the steps.
fn add_station_body(
  v : @view.View,
  core : Core,
  here : Here,
  manager : Bool,
  here_addable : Bool,
  close : () -> Unit,
) -> Unit {
  let now = adding_now(core, here, manager)
  // (the order the joinable ones came in, kept as the core lists another: those joined from here stay where they were)
  v.reacts(
    fn() { items((core.topic)("joinable", { "workspace": str(here.workspace) }).get().value, "items").map(fn(s) { text(Some(s), "station") }) },
    fn(ids) {
      for id in ids {
        if !adding.order.contains(id) {
          adding.order[id] = adding.order.length()
        }
      }
    },
  )
  let made = fn() { adding.made.get() is Some(_) }
  // the choice stays at the top
  v.show(fn() { (now.offered)() && !made() }, fn(s) {
    s.box(fn(b) {
      @sf.style_node(b, fn() { @sf.panel_words_in_node(b).then(add_kind_room) })
      add_choice_node(
        b,
        fn() { [tr("web-pages.settings.stations.kindNew"), tr("web-pages.settings.stations.kindExisting")] },
        fn() { if adding.existing.get() { 1 } else { 0 } },
        fn(i) { adding.existing.set(i == 1) },
      )
    })
    |> ignore
  })
  // what the new machine will be, its managers' to choose (a member's is one that only runs tasks)
  if manager {
    v.show(fn() { !made() && !((now.offered)() && adding.existing.get()) }, fn(s) {
      s.box(fn(b) {
        @sf.style_node(b, fn() { @sf.panel_words_in_node(b).then(add_mode_room) })
        add_choice_node(
          b,
          fn() { [tr("web-pages.rigs.add.kind.full"), tr("web-pages.rigs.add.kind.tasks")] },
          fn() { if adding.tasks.get() { 1 } else { 0 } },
          fn(i) {
            if (i == 1) != adding.tasks.untracked() {
              adding.error.set("")
              adding.here_error.set("")
            }
            adding.tasks.set(i == 1)
          },
        )
      })
      |> ignore
    })
  }
  v.pick(now.joining, fn(b, joining) {
    if joining {
      join_existing_node(b, core, here, now.rows)
    } else {
      // this machine, where it has none: added here, no command to run (before a command is made)
      if here_addable {
        b.show(fn() { !made() && !adding.tasks.get() }, fn(s) {
          s.box(fn(h) {
            @sf.style_node(h, fn() { @sf.panel_words_in_node(h).then(here_room) })
            add_this_machine_node(h, core, here, close)
          })
          |> ignore
        })
      }
      b.box(fn(n) {
        @sf.style_node(n, fn() { @sf.panel_words_in_node(n).then(add_kind_room) })
        @sf.words_node(
          n,
          fn() { if adding.tasks.get() { tr("web-pages.rigs.add.lead") } else { fill("android-settings.station.addNote", [("app", "still.fail")]) } },
          fn() { add_note_words },
        )
        |> ignore
      })
      |> ignore
      b.box(fn(s) {
        @sf.style_node(s, fn() { @sf.panel_words_in_node(s).then(full_room) })
        add_station_steps_node(s, core, here)
      })
      |> ignore
    }
  })
}

///|
/// A choice of a few in node `b` (segmented_node), along a row of its own: laid out as along a line, its share of it.
fn add_choice_node(b : @view.View, labels : () -> Array[String], chosen : () -> Int, choose : (Int) -> Unit) -> Unit {
  b.box(fn(line) {
    line.row(Is(true)) |> ignore
    line.box(fn(slot) { @sf.segmented_node(slot, labels, chosen, choose) }) |> ignore
  })
  |> ignore
}

///|
/// The kind's choice over what is under it: across the panel's words, 10 over it.
// kept across runs: a value (no field of it changes)
let add_kind_room : @ui.Style = @ui.css("w=Full pb=S2_5")

///|
/// The mode's choice over the steps: across the panel's words, the steps 10 under it (as the kind's choice is).
// kept across runs: a value (no field of it changes)
let add_mode_room : @ui.Style = @ui.css("w=Full pb=S2_5")

///|
// kept across runs: a value (no field of it changes)
let full_room : @ui.Style = @ui.css("w=Full")

///|
/// What a station is, over the steps (and what one that only runs tasks is): the meta's size, muted, 20 a line.
// kept across runs: a value (no field of it changes)
let add_note_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full, leading=L6)

///|
/// 添加 station's foot in node `v`: joining one of another workspace, 取消 (完成 once one is joined) and 添加到此
/// workspace; a new machine's, its step's (add_station_buttons').
fn add_station_foot(v : @view.View, core : Core, here : Here, manager : Bool, close : () -> Unit) -> Unit {
  let now = adding_now(core, here, manager)
  let step = fn() { add_step(core, here) }
  // 取消 (joining, 完成 once one is joined), but where the machine has joined
  @sf.foot_place_node(v, fn() { (now.joining)() || step() != 1 }, fn(p) {
    @sf.button_node(
      p,
      fn() { tr(if (now.joining)() && adding.took.length() > 0 { "common.done" } else { "common.cancel" }) },
      fn() { close() },
    )
    |> ignore
  })
  @sf.foot_place_node(v, fn() { !(now.joining)() && step() == 0 }, fn(p) {
    let tasks = fn() { adding.tasks.get() }
    let name = fn() { station_name_field().text().trim(chars=" \t\n").to_owned() }
    @sf.button_node(
      p,
      fn() { tr("android-settings.station.make") },
      fn() {
        // (the keys and the keyboard let go of, as the field is done with)
        p.focus_let_go()
        make_station_command(core, here, @signals.untracked(tasks), @signals.untracked(name))
      },
      tone=Primary,
      busy=fn() { add_making(core, here, tasks()) },
      disabled=fn() { name() == "" },
    )
    |> ignore
  })
  @sf.foot_place_node(v, fn() { !(now.joining)() && step() == 1 }, fn(p) {
    @sf.button_node(p, fn() { tr("common.done") }, fn() { close() }, tone=Primary) |> ignore
  })
  @sf.foot_place_node(v, now.joining, fn(p) {
    let chosen = fn() { join_chosen(core, here, (now.rows)()) }
    @sf.button_node(
      p,
      fn() { tr("web-pages.settings.stations.joinAction") },
      fn() { join_station(core, here, @signals.untracked(chosen).0) },
      tone=Primary,
      busy=fn() { chosen().1 },
      disabled=fn() { chosen().0 is None },
    )
    |> ignore
  })
}

///|
/// The joinable stations to show (the core's `joinable`, with those joined from here kept where they were, in the order
/// they came in: adding.order).
fn joinable_rows(joinable : Json?) -> Array[Json] {
  let items_now = items(joinable, "items")
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
/// A station of another workspace the viewer manages picked and added here as it is (JoinStation: `station.join`), in
/// node `v`: what that shares of the machine said under the list, why it was refused in red; joined, it stays in its
/// place, said so, and the next one open is picked. In the sheet's column, its rows reaching out across its sides
/// (@sf.sheet_column_node).
fn join_existing_node(v : @view.View, core : Core, here : Here, rows : () -> Array[Json]) -> Unit {
  @sf.sheet_column_node(v, fn(col) {
    col.box(fn(l) {
      @sf.style_node(l, fn() { add_kind_room })
      @sf.words_node(l, fn() { tr("web-pages.settings.stations.existingLead") }, fn() { add_note_words }) |> ignore
    })
    |> ignore
    col.each(rows, fn(s) { text(Some(s), "station") }, fn(r, s) {
      // (a box of its own: what comes and goes, the whole row)
      r.box(fn(row) {
        let id = text(Some(s.untracked()), "station")
        let took = fn() { took_it(s.get()) }
        let st = fn() { Some(s.get()) }
        let marked = @sf.has_station_mark(text(Some(s.untracked()), "emoji"), text(Some(s.untracked()), "icon"))
        @sf.choice_row_node(
          row,
          fn() { text(st(), "name") },
          fn() { took() || join_chosen(core, here, rows()).0.map(fn(ch) { text(Some(ch), "station") == id }).unwrap_or(false) },
          press=fn() {
            if !@signals.untracked(took) {
              adding.picked.set(id)
              adding.error.set("")
              adding.here_error.set("")
            }
          },
          note=fn() { if took() { tr("web-pages.settings.stations.joinedRow") } else { text(st(), "line") } },
          lead?=if marked {
            Some(fn(m) { station_mark_node_of(m, st, 15.0) })
          } else {
            None
          },
          disabled=fn() { !took() && (join_chosen(core, here, rows()).1 || flag(st(), "needsLock")) },
        )
      })
      |> ignore
    })
    col.box(fn(f) {
      @sf.style_node(f, fn() { join_foot_room })
      @sf.words_node(f, fn() { tr("web-pages.settings.stations.softIsolation") }, fn() { join_soft_words }) |> ignore
      f.show(fn() { adding.error.get() != "" }, fn(e) {
        @sf.words_node(e, fn() { adding.error.get() }, fn() { add_error_words }) |> ignore
      })
    })
    |> ignore
  })
}

///|
/// What a station shares of its machine, under the joinable ones: 10 over it, its error 10 under it.
// kept across runs: a value (no field of it changes)
let join_foot_room : @ui.Style = @ui.css("w=Full pt=S2_5 gap=S2_5")

///|
/// What a station shares of its machine: the caption's size, muted, 18 a line (the old one's 17, off the scale).
// kept across runs: a value (no field of it changes)
let join_soft_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, w=Full, leading=L5)

///|
/// Why it was refused, or the command could not be made: the meta's size, red, 18 a line.
// kept across runs: a value (no field of it changes)
let add_error_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, w=Full, leading=L5)

///|
/// A station's mark in node `m` (station_mark's), `size` across, in the words' ink, as `s` says it now.
fn station_mark_node_of(m : @view.View, s : () -> Json?, size : Double) -> Unit {
  @sf.station_mark_node(m, fn() { text(s(), "emoji") }, fn() { text(s(), "icon") }, size, fn() { @sf.theme().p.text }, fn() { 1 })
}

///|
/// The one picked joined (`station.join`): kept where it was, as the station calls it; why not, said under the list.
fn join_station(core : Core, here : Here, chosen : Json?) -> Unit {
  guard chosen is Some(s) else { return }
  adding.error.set("")
  adding.here_error.set("")
  let station = text(Some(s), "station")
  (core.call)("station.join", obj([("station", str(station)), ("workspace", str(here.workspace))]), fn(r) {
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
      Err(e) => adding.error.set(error_text(e))
    }
  })
}

///|
/// Which joinable station is picked (the one picked, else the first open: one whose home's security mode keeps it
/// out is shown, not picked) and whether it is being joined.
fn join_chosen(core : Core, here : Here, rows : Array[Json]) -> (Json?, Bool) {
  let open = rows.filter(fn(s) { !flag(Some(s), "needsLock") && !took_it(s) })
  let chosen = match open.iter().find_first(fn(s) { text(Some(s), "station") == adding.picked.get() }) {
    Some(s) => Some(s)
    None => open.get(0)
  }
  let busy = match chosen {
    Some(s) => is_doing(core, ["station.join"], [("station", text(Some(s), "station")), ("workspace", here.workspace)])
    None => false
  }
  (chosen, busy)
}

///|
/// Where the steps are: 0 before a command is made, 1 the machine joined, 2 waiting for it.
fn add_step(core : Core, here : Here) -> Int {
  match (adding.made.get(), station_joined(core, here)) {
    (None, _) => 0
    (Some(_), Some(_)) => 1
    (Some(_), None) => 2
  }
}

///|
/// Whether the command is being made (`rig.add` for one that only runs tasks, else `workspace.enroll`).
fn add_making(core : Core, here : Here, tasks : Bool) -> Bool {
  if tasks {
    is_doing(core, ["rig.add"], [("workspace", here.workspace)])
  } else {
    is_doing(core, ["workspace.enroll"], [("account", here.sub), ("workspace", here.workspace)])
  }
}

///|
/// The command made from `name` (生成命令): `rig.add` for one that only runs tasks, else `workspace.enroll`; why not, said
/// under the name.
fn make_station_command(core : Core, here : Here, tasks : Bool, name : String) -> Unit {
  adding.error.set("")
  adding.here_error.set("")
  (core.call)(
    if tasks { "rig.add" } else { "workspace.enroll" },
    if tasks { obj([("workspace", str(here.workspace)), ("name", str(name))]) } else { obj([("workspace", str(here.workspace)), ("name", str(name)), ("account", str(here.sub))]) },
    fn(r) {
      match r {
        Ok(v) => adding.made.set(Some((text(Some(v), "install"), text(Some(v), "installWindows"))))
        Err(e) => adding.error.set(error_text(e))
      }
    },
  )
}

///|
/// The steps in node `v` (add_station_steps', its buttons the panel's foot): the name's line, its field and why the
/// command could not be made; joined, said in green; else the commands to run there (macOS's and Linux's, Windows'
/// where the cloud gave it), each under its system's name and copied from here, and the wait.
fn add_station_steps_node(v : @view.View, core : Core, here : Here) -> Unit {
  let field = station_name_field()
  v.pick(fn() { add_step(core, here) }, fn(b, step) {
      @sf.style_node(b, fn() { steps_column })
      match step {
        0 => {
          @sf.words_node(b, fn() { tr("android-settings.station.name") }, fn() { step_label_words }) |> ignore
          @sf.input_node(b, field, placeholder=tr("android-settings.station.namePlaceholder")) |> ignore
          b.show(fn() { adding.error.get() != "" }, fn(e) {
            @sf.words_node(e, fn() { adding.error.get() }, fn() { add_error_words }) |> ignore
          })
        }
        1 => joined_line_node(b, fn() { text(station_joined(core, here), "name") })
        _ => {
          @sf.words_node(b, fn() { tr("android-settings.station.run") }, fn() { step_run_words }) |> ignore
          @sf.words_node(b, fn() { tr("android-settings.station.runUnix") }, fn() { step_label_words }) |> ignore
          command_box_node(b, core, fn() {
            match adding.made.get() {
              Some((install, _)) => install
              None => ""
            }
          })
          let windows = fn() {
            match adding.made.get() {
              Some((_, w)) => w
              None => ""
            }
          }
          b.show(fn() { windows() != "" }, fn(w) {
            @sf.style_node(w, fn() { steps_column })
            @sf.words_node(w, fn() { tr("android-settings.station.runWindows") }, fn() { step_label_words }) |> ignore
            command_box_node(w, core, windows)
          })
          @sf.words_node(b, fn() { fill("android-settings.station.runNote", [("app", "still.fail")]) }, fn() { step_note_words })
          |> ignore
          @sf.wait_line_node(b, fn() { tr("android-settings.station.waiting") }) |> ignore
        }
      }
    })
}

///|
/// The steps one under another, 10 apart.
// kept across runs: a value (no field of it changes)
let steps_column : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
/// The name's line over its field: the meta's size, 600, the words' ink, 18 a line.
// kept across runs: a value (no field of it changes)
let step_label_words : @ui.TextStyle = @ui.text_style(size=Meta, weight=Semibold, color=Fg, w=Full, leading=L5)

///|
/// 在该机器的终端中执行: the interface's size, the words' ink, 20 a line.
// kept across runs: a value (no field of it changes)
let step_run_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, w=Full, leading=L6)

///|
/// What runs it, under the command: the meta's size, muted, 18 a line.
// kept across runs: a value (no field of it changes)
let step_note_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full, leading=L5)

///|
/// The machine joined, in node `v`: on green's ground at 0.12, round 12, 12 and 10 in, its check (16) and 「name」已加入 in
/// green beside it, 8 apart.
fn joined_line_node(v : @view.View, name : () -> String) -> Unit {
  v.box(fn(r) {
    @sf.style_node(r, fn() { joined_line })
    r.ground(By(fn() { @sf.alpha(@sf.theme().p.green, 0.12) })).radius(Is(12.0)) |> ignore
    @sf.icon_node(r, "check", 16.0, By(fn() { @sf.theme().p.green })) |> ignore
    r.box(fn(w) {
      w.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
      w
      .words(By(fn() { fill("android-settings.station.joined", [("name", name())]) }))
      .words_look(By(fn() { @ui.style_words(joined_words) }))
      .ink(By(fn() { @sf.theme().p.green }))
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let joined_line : @ui.Style = @ui.css("row w=Full px=S3 py=S2_5 gap=S2 align=ACenter")

///|
/// 「name」已加入: the interface's size, 20 a line (its ink the palette's green).
// kept across runs: a value (no field of it changes)
let joined_words : @ui.TextStyle = @ui.text_style(size=Ui, w=Full, leading=L6)

///|
/// A command to run elsewhere (command_box's, as nodes) in `parent`, `words` as they are now: on surface2 alone, its
/// words in the code face (12, 18 a line) wrapped, its copy button at its end, two of its lines high; pressed, the
/// words copied and 已复制 said.
fn command_box_node(parent : @view.View, core : Core, words : () -> String) -> Unit {
  parent.box(fn(b) {
    @sf.style_node(b, fn() { command_room })
    b
    .ground(By(fn() { @sf.theme().p.card2 }))
    .radius(Is(@sf.command_box_corner))
    .padding(Is((12.0, @sf.corner_inset, @sf.corner_inset, @sf.corner_inset)))
    |> ignore
    b.box(fn(w) {
      w.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
      w.box(fn(x) {
        x
        .words_runs(By(fn() { [@ui.span(words(), mono=true)] }), look=command_words)
        .ink(By(fn() { @sf.theme().p.text }))
        |> ignore
      })
      |> ignore
    })
    |> ignore
    b.box(fn(k) {
      k
      .width(Is(Some(command_copy)))
      .height(Is(Some(command_copy)))
      .radius(Is(@sf.small_corner))
      .ground(By(fn() { @sf.theme().p.chip }))
      .lines_up(Is(Some(Middle)))
      .lies_along(Is(Middle))
      |> ignore
      @sf.icon_node(k, "copy", 16.0, By(fn() { @sf.theme().p.text })) |> ignore
      @sf.rippled_node(k, fn() {
        @ui.clipboard_set(@signals.untracked(words))
        (core.say)(tr("common.copied"))
      }, @sf.small_corner, fn() { @sf.t("common.copy") })
    })
    |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let command_room : @ui.Style = @ui.css("row w=Full gap=S2")

///|
/// A command's words: the code face's 12, two to its copy button.
// kept across runs: a value (no field of it changes)
let command_words : @view.WordsLook = { size: 12.0, weight: 400, line: command_line, wrap: true, tracking: @view.letters_own, balance: false, max_lines: 0 }

///|
/// 添加这台 Mac in node `v` (add_this_machine's): what it does, its button; pressed, joins via `station.join` when
/// online and joinable in the mesh, else calls `local_install(true)` and opens 本机 Station.
fn add_this_machine_node(v : @view.View, core : Core, here : Here, close : () -> Unit) -> Unit {
  let pc = local_machine_pc()
  let state = fn() { local_here_join_state(core, here) }
  let joining = fn() {
    match state().0 {
      Some(st) => is_doing(core, ["station.join"], [("station", st), ("workspace", here.workspace)])
      None => false
    }
  }
  v.box(fn(b) {
    @sf.style_node(b, fn() { here_column })
    @sf.words_node(b, fn() { add_here_note(pc) }, fn() { here_words }) |> ignore
    b.show(fn() { state().2 != "" }, fn(w) {
      @sf.words_node(w, fn() { state().2 }, fn() { join_soft_words }) |> ignore
    })
    @sf.button_node(
      b,
      fn() { tr(if pc { "web-pages.settings.thisPc.add" } else { "web-pages.settings.thisMac.add" }) },
      fn() {
        let join_addr = @signals.untracked(fn() { state().0 })
        press_add_here(core, here, join_addr, true, close)
      },
      busy=joining,
      disabled=fn() { state().1 || joining() },
    )
    |> ignore
    b.show(fn() { adding.here_error.get() != "" }, fn(e) {
      @sf.words_node(e, fn() { adding.here_error.get() }, fn() { add_error_words }) |> ignore
    })
  })
  |> ignore
}

///|
/// The field a new station's name is typed in, this time 添加 station opened.
fn station_name_field() -> @ui.Field {
  field_of(@signals.untracked(station_name_key))
}

///|
/// A station's name, then the commands that install still.fail on that machine and join it (one with still.fail too:
/// macOS's and Linux's, Windows' where the cloud gave it), copied from here, and the wait for it (AddStationSteps);
/// joined, said in green with 完成 (`done`). `label` and `placeholder`: the name's line, as the first station's page words it.
fn add_station_steps(
  c : @ui.Ctx,
  core : Core,
  here : Here,
  done : () -> Unit,
  buttons? : Bool = true,
  label? : String = tr("android-settings.station.name"),
  placeholder? : String = tr("android-settings.station.namePlaceholder"),
) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), gap=10.0, fn() {
    match (adding.made.get(), station_joined(core, here)) {
      (None, _) => {
        c.text(label, style=step_label_words) |> ignore
        field_box(c, station_name_key(), placeholder) |> ignore
        if adding.error.get() != "" {
          c.text(adding.error.get(), style=add_error_words) |> ignore
        }
        if buttons {
          c.box(dir=Row, w=Fill(1.0), pt=6.0, gap=8.0, justify=JEnd, fn() { add_station_buttons(c, core, here, done) })
          |> ignore
        }
      }
      (Some(_), Some(s)) => {
        c.box(style=joined_line, radius=12.0, bg=@sf.alpha(t.p.green, 0.12), fn() {
          @sf.icon(c, "check", size=16.0, color=t.p.green) |> ignore
          c.text(fill("android-settings.station.joined", [("name", text(Some(s), "name"))]), style=joined_words, color=t.p.green)
          |> ignore
        })
        |> ignore
        if buttons {
          c.box(dir=Row, w=Fill(1.0), justify=JEnd, fn() { add_station_buttons(c, core, here, done) }) |> ignore
        }
      }
      (Some((install, windows)), None) => {
        c.text(tr("android-settings.station.run"), style=step_run_words) |> ignore
        c.text(tr("android-settings.station.runUnix"), style=step_label_words) |> ignore
        command_box(c, core, install)
        if windows != "" {
          c.text(tr("android-settings.station.runWindows"), style=step_label_words) |> ignore
          command_box(c, core, windows)
        }
        c.text(fill("android-settings.station.runNote", [("app", "still.fail")]), style=step_note_words) |> ignore
        wait_line(c, tr("android-settings.station.waiting"))
      }
    }
  })
  |> ignore
}

///|
/// The field a new station's name is typed in, this time 添加 station opened.
fn station_name_key() -> String {
  "station-name/" + adding.serial.get().to_string()
}

///|
/// The station joined since 添加 station opened (one not among those there when it opened), once its command is made.
fn station_joined(core : Core, here : Here) -> Json? {
  match adding.made.get() {
    // (one that only runs tasks joins the workspace's rigs, not its stations)
    Some(_) if adding.tasks.get() => rigs_listed(core, here).iter().find_first(fn(r) { !adding.known.get().contains(text(Some(r), "id")) })
    Some(_) =>
      match stations_of(core, here).value {
        Some(Array(a)) => a.iter().find_first(fn(s) { !adding.known.get().contains(text(Some(s), "id")) })
        _ => None
      }
    None => None
  }
}

///|
/// add_station_steps' buttons under the steps (the first station's page): 生成命令 from the name typed; joined, 完成
/// (`done`); while it waits for the machine, none.
fn add_station_buttons(c : @ui.Ctx, core : Core, here : Here, done : () -> Unit) -> Unit {
  match add_step(core, here) {
    0 => {
      let tasks = adding.tasks.get()
      let name = station_name_field().text().trim(chars=" \t\n").to_owned()
      @sf.button(c, tr("android-settings.station.make"), key="add-make", tone=Primary, busy=add_making(core, here, tasks), disabled=name == "", on_press=fn() {
        c.blur()
        make_station_command(core, here, tasks, name)
      })
    }
    1 =>
      @sf.button(c, tr("common.done"), key="add-done", tone=Primary, on_press=fn() {
        done()
      })
    _ => ()
  }
}

///|
/// A command to run elsewhere, with a button that copies it: on surface2 alone, no line round it (its ground sets it
/// apart; the user, 2026-11-09), a block of the ladder's (round by its row corner), its copy button the ladder's inset in from its top and end, as tall as two of
/// its lines and its inset under them (so with one or two lines as far from its foot too), round by the ladder's next
/// step there (mbui works it out). `reach`: in a card's foot corners, how it reaches past the card's words
/// (block_across).
fn command_box(c : @ui.Ctx, core : Core, words : String, reach? : @ui.Style) -> Unit {
  let t = @sf.theme()
  let id = c.id("command-copy")
  c.on_press(id, fn() {
    c.copy_text(words)
    (core.say)(tr("common.copied"))
  })
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
          if !@sf.presenting() && adding.known.get().length() > 0 {
            adding_reset([], false)
          }
          if local_station_addable_in(here.workspace, []) {
            add_this_machine(c, core, here, fn() {  })
          }
          add_station_steps(
            c,
            core,
            here,
            label=tr("android-settings.station.firstName"),
            placeholder=tr("android-settings.station.firstPlaceholder"),
            fn() {  },
          )
          let joinable = (core.topic)("joinable", { "workspace": str(here.workspace) }).get().value
          if flag(joinable, "offered") && items(joinable, "items").length() > 0 {
            tap_text(c, "first-existing", tr("web-pages.settings.stations.firstExisting"), size=14.0, on_press=fn() {
              open_add_station(core, here, [], existing=true)
            })
          }
        }
      }
    })
    |> ignore
  })
  |> ignore
}
