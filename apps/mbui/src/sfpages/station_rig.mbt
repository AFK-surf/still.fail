// A station that only runs tasks (2026-11-10: a rig, the core's `rigs`: client/core-ts/src/rigs.ts), its page in the
// place of a whole station's (station_node picks it by its address), one page in every frame, laid out by its width.
// The app is not linked to it: the workspace's stations say how it is. Whose it is and whether a station reached it;
// its mode, made a whole station again by its person where they manage the workspace (`rig.setMode`); for its person,
// its code compared where the workspace is in security mode (`rig.vouch`), 免批准 (`rig.setOpen`), the chats asking
// for it answered (`rig.decide`) and those using it taken back (`rig.revoke`), what it was last told to run
// (`rig.log`), and taking it out (`workspace.removeStation`); for anyone else, the same read only. Made once as nodes
// of the window's tree (page_node).

///|
/// What each rig was last told to run, as last read here (`rig.log`), by its id: None while it is read.
// kept across runs: put back by reset (rigs_reset)
let rig_logs : @sf.LiveMap[String, Json?] = @sf.LiveMap::new()

///|
/// What the page keeps put back as the app begins anew.
fn rigs_reset() -> Unit {
  rig_logs.clear()
}

///|
/// The page of the station at `address` that only runs tasks (`rig`: as the core says it now), made once in node `v`
/// as wide as `width` gives it, in the frame it is given.
fn rig_station_node(
  v : @view.View,
  core : Core,
  here : () -> Here,
  address : String,
  rig : () -> Json?,
  on_back : () -> Unit,
  frame : () -> PageFrame,
  said : ((@sf.PageSaid) -> Unit)?,
  width : (() -> Double)?,
  tips : @sf.TipLayer,
) -> Unit {
  let id = match address.find("/") {
    Some(i) => address.exact_view(start=i + 1).to_owned()
    None => address
  }
  @sf.page_node(
    v,
    fn() { text(rig(), "name") },
    on_back~,
    frame~,
    said?,
    width?,
    tips~,
    lead=fn() { @settings.rig_whose(rig()) + " · " + @settings.rig_state(rig()) },
    // (its devices' own section once it has any; adding one is in its more's rows: rig_more_node)
    fn() {
      if @settings.devices_listed(core, here()).iter().any(fn(d) { text(Some(d), "station") == id && text(Some(d), "via") == "rig" }) {
        ["mode", "use", "devices", "more"]
      } else {
        ["mode", "use", "more"]
      }
    },
    fn(b, key) {
      match key {
        "mode" => rig_mode_node(b, core, here, rig, id)
        "use" => rig_use_node(b, core, here, rig, id, tips)
        // its devices: attached by its person, as they sign it
        "devices" => @settings.station_devices_node(b, core, here, id, true, fn() { false })
        _ => rig_more_node(b, core, here, rig, id)
      }
    },
  )
}

///|
/// Whether the viewer is one of the workspace's owners or admins.
fn rig_manager(core : Core, here : Here) -> Bool {
  let role = text(workspace_view(core, here).value, "role")
  role == "owner" || role == "admin"
}

///|
/// Its mode: that it only runs tasks; made a whole station again by its person where they manage the workspace (asked
/// first), anyone else who is one of the two told who does; in security mode, its code compared by its person first.
fn rig_mode_node(b : @view.View, core : Core, here : () -> Here, rig : () -> Json?, id : String) -> Unit {
  let ws = fn() { here().workspace }
  let name = fn() { text(rig(), "name") }
  let mine = fn() { flag(rig(), "mine") }
  let vouched = fn() { flag(rig(), "vouched") }
  let manager = fn() { rig_manager(core, here()) }
  @sf.group_node(b, fn(g) {
    @sf.link_row_node(
      g,
      fn() { @sf.t("web-pages.rigs.mode") },
      fn() {  },
      value=fn() { @sf.t("web-pages.rigs.mode.tasks") },
      note=fn() { @sf.t("web-pages.rigs.mode.tasksNote") },
      goes=false,
      chevron=false,
    )
    g.show(fn() { mine() && manager() && vouched() }, fn(o) {
      @sf.link_row_node(
        o,
        fn() { @sf.t("web-pages.rigs.toFull") },
        fn() {
          let at = @signals.untracked(ws)
          confirm(@sf.t("web-pages.rigs.toFullAsk", args=[("name", @signals.untracked(name))]), @sf.t("web-pages.rigs.toFullNote"), @sf.t("web-pages.rigs.toFull"), fn() {
            @settings.act(
              core,
              @sf.t("web-pages.rigs.toFull"),
              "rig.setMode",
              obj([("workspace", str(at)), ("station", str(id)), ("mode", str("full"))]),
              done=@sf.t("web-pages.rigs.toFullDone"),
            )
          })
        },
        chevron=false,
      )
    })
    g.show(fn() { mine() != manager() }, fn(o) {
      @sf.link_row_node(o, fn() { @sf.t("web-pages.rigs.toFull") }, fn() {  }, note=fn() { @sf.t("web-pages.rigs.toFullWho") }, goes=false, chevron=false, lacks=true)
    })
    // security mode: its code compared by its person before any station sends it a task
    g.show(fn() { mine() && !vouched() }, fn(o) {
      @sf.link_row_node(
        o,
        fn() { @sf.t("web-pages.rigs.vouch.title") },
        fn() {
          let at = @signals.untracked(ws)
          ask(@sf.t("web-pages.rigs.vouch.title"), "", @sf.t("web-pages.rigs.vouch.code"), @sf.t("web-pages.rigs.vouch.confirm"), hint=@sf.t("web-pages.rigs.vouch.note"), fn(code) {
            @settings.act(core, @sf.t("web-pages.rigs.vouch.title"), "rig.vouch", obj([("workspace", str(at)), ("rig", str(id)), ("code", str(code))]))
          })
        },
        note=fn() { @sf.t("web-pages.rigs.vouch.note") },
      )
    })
  })
}

///|
/// Who may use it: 免批准 (its person's switch; anyone else told when it is on), the chats asking for it (answered by
/// its person) and those using it (taken back by its person).
fn rig_use_node(b : @view.View, core : Core, here : () -> Here, rig : () -> Json?, id : String, tips : @sf.TipLayer) -> Unit {
  let ws = fn() { here().workspace }
  let name = fn() { text(rig(), "name") }
  let mine = fn() { flag(rig(), "mine") }
  let vouched = fn() { flag(rig(), "vouched") }
  let open = fn() { flag(rig(), "open") }
  let on = fn() { [("rig", id)] }
  @sf.section_node(b, fn() { @sf.t("web-pages.rigs.use") }, fn(s) {
    @sf.group_node(s, fn(g) {
        // 免批准: its person's switch; anyone else told when it is on
        g.show(fn() { mine() && vouched() }, fn(o) {
          @sf.switch_row_node(
            o,
            fn() { @sf.t("web-pages.rigs.open") },
            open,
            fn(to) {
              @settings.act(core, @sf.t("web-pages.rigs.open"), "rig.setOpen", obj([("workspace", str(@signals.untracked(ws))), ("rig", str(id)), ("open", Json::boolean(to))]))
            },
            note=fn() { @sf.t("web-pages.rigs.openNote") },
            busy=fn() { is_doing(core, ["rig.setOpen"], on()) },
          )
        })
        g.show(fn() { !mine() && open() }, fn(o) {
          @sf.link_row_node(o, fn() { @sf.t("web-pages.rigs.openOn") }, fn() {  }, goes=false, chevron=false)
        })
        // the chats asking for it: answered by its person here too (the time the agent asked for)
        g.each(fn() { items(rig(), "requests") }, fn(q) { "q/" + text(Some(q), "id") }, fn(row, q) {
          let r = fn() { Some(q.get()) }
          let at = fn() { [("request", text(r(), "id"))] }
          @sf.link_row_node(
            row,
            fn() { rig_chat_title(r()) },
            fn() {  },
            note=fn() {
              if text(r(), "status") == "pending" {
                text(r(), "reason")
              } else {
                @sf.t("web-pages.rigs.request.away")
              }
            },
            goes=false,
            chevron=false,
            control=fn(e) {
              e.show(fn() { mine() && text(r(), "status") == "pending" }, fn(c) {
                c.row(Is(true)).gap(Is(ws_tail_gap)).lines_up(Is(Some(Middle))) |> ignore
                // (the last one alone goes out to the row's end: two would lie over each other)
                @sf.button_node(
                  c,
                  fn() { @sf.t("web-pages.rigs.deny") },
                  fn() {
                    let now = @signals.untracked(r)
                    @settings.act(core, @sf.t("web-pages.rigs.deny"), "rig.decide", obj([("station", str(text(now, "station"))), ("request", str(text(now, "id"))), ("allow", false)]))
                  },
                  tone=Ghost,
                  busy=fn() { is_doing(core, ["rig.decide"], at()) },
                )
                |> ignore
                @sf.row_end_button_node(
                  c,
                  fn() { @sf.t("web-pages.rigs.allow") },
                  fn() {
                    let now = @signals.untracked(r)
                    @settings.act(
                      core,
                      @sf.t("web-pages.rigs.allow"),
                      "rig.decide",
                      obj([
                        ("station", str(text(now, "station"))),
                        ("request", str(text(now, "id"))),
                        ("allow", true),
                        ("timeoutKind", str(text(now, "timeoutKind"))),
                        ("timeoutSeconds", Json::number(count(now, "timeoutSeconds").to_double())),
                        (
                          "ask",
                          obj([
                            ("rig", str(id)),
                            ("name", str(@signals.untracked(name))),
                            ("session", str(text(now, "session"))),
                            ("chat", str(text(now, "chat"))),
                            ("title", str(text(now, "title"))),
                            ("by", str(text(now, "by"))),
                          ]),
                        ),
                      ]),
                    )
                  },
                  busy=fn() { is_doing(core, ["rig.decide"], at()) },
                )
                |> ignore
              })
            },
          )
        })
        // the chats using it: taken back by its person
        g.each(fn() { items(rig(), "grants") }, fn(x) { "g/" + text(Some(x), "request") }, fn(row, x) {
          let r = fn() { Some(x.get()) }
          let at = fn() { [("request", text(r(), "request"))] }
          @sf.link_row_node(
            row,
            fn() { rig_chat_title(r()) },
            fn() {  },
            note=fn() {
              @sf.t("web-pages.rigs.grant.line", args=[
                ("by", text(r(), "by")),
                ("station", text(r(), "stationName")),
                ("time", @settings.rig_timeout_words(text(r(), "timeoutKind"), count(r(), "timeoutSeconds"))),
              ])
            },
            goes=false,
            chevron=false,
            control=fn(e) {
              e.show(mine, fn(c) {
                ws_row_action_node(c, @sf.t("web-pages.rigs.revoke"), core, ["rig.revoke"], at, Some(tips), fn() {
                  let now = @signals.untracked(r)
                  @settings.act(
                    core,
                    @sf.t("web-pages.rigs.revoke"),
                    "rig.revoke",
                    obj([("workspace", str(@signals.untracked(ws))), ("rig", str(id)), ("request", str(text(now, "request"))), ("station", str(text(now, "station")))]),
                  )
                })
              })
            },
          )
        })
        g.show(fn() { flag(rig(), "known") && !open() && items(rig(), "grants").length() == 0 && items(rig(), "requests").length() == 0 }, fn(o) {
          @sf.link_row_node(o, fn() { @sf.t("web-pages.rigs.grantsNone") }, fn() {  }, goes=false, chevron=false, lacks=true)
        })
    })
  })
}

///|
/// What it was last told to run (read when asked for, its lines under the row), and taking it out of the workspace
/// (its person's, and the workspace's managers').
fn rig_more_node(b : @view.View, core : Core, here : () -> Here, rig : () -> Json?, id : String) -> Unit {
  let ws = fn() { here().workspace }
  let name = fn() { text(rig(), "name") }
  let mine = fn() { flag(rig(), "mine") }
  let vouched = fn() { flag(rig(), "vouched") }
  let manager = fn() { rig_manager(core, here()) }
  @sf.group_node(b, fn(g) {
        // what it was last told to run: read when asked for, its lines under the row
        g.show(vouched, fn(o) {
          @sf.link_row_node(
            o,
            fn() { @sf.t("web-pages.rigs.log") },
            fn() {
              rig_logs[id] = None
              (core.call)("rig.log", obj([("workspace", str(@signals.untracked(ws))), ("rig", str(id))]), fn(r) {
                match r {
                  Ok(v) => rig_logs[id] = Some(v)
                  Err(e) => {
                    rig_logs.remove(id)
                    (core.say)(@sf.t("web-pages.rigs.logFailed", args=[("error", error_text(e))]))
                  }
                }
              })
            },
            value=fn() {
              match rig_logs.get(id) {
                Some(Some(v)) if items(Some(v), "commands").length() == 0 => @sf.t("web-pages.rigs.logNone")
                _ => ""
              }
            },
            chevron=false,
            tail=fn(e) { @sf.spinner_node(e, size=rig_spinner) |> ignore },
            tail_shown=fn() { rig_logs.get(id) is Some(None) },
          )
        })
        g.each(
          fn() {
            match rig_logs.get(id) {
              Some(Some(v)) => items(Some(v), "commands")
              _ => []
            }
          },
          fn(c) { "c/" + number(Some(c), "at").to_string() + "/" + text(Some(c), "key") },
          fn(row, c) {
            let r = fn() { Some(c.get()) }
            @sf.link_row_node(
              row,
              fn() { text(r(), "command") },
              fn() {  },
              note=fn() {
                let what = if text(r(), "kind") == "secret" { @sf.t("web-pages.rigs.log.secret") + " · " } else { "" }
                what + text(r(), "stationName")
              },
              goes=false,
              chevron=false,
              title_cut=true,
            )
          },
        )
        // a device attached to it: its person's, as they sign it (settings devices.mbt)
        g.show(fn() { mine() && vouched() }, fn(o) {
          o.box(fn(holder) {
            @sf.link_row_node(
              holder,
              fn() { @sf.t("web-pages.devices.add") },
              fn() {
                let (x, y, w, h) = holder.placed_window_now()
                @settings.add_device(core, @signals.untracked(here), id, true, At(x, y, w, h))
              },
              note=fn() { @sf.t("web-pages.devices.rigNote") },
              chevron=false,
            )
          })
          |> ignore
        })
        // taking it out: its person's, and the workspace's managers'
        g.show(fn() { mine() || manager() }, fn(o) {
          @sf.link_row_node(
            o,
            fn() { @sf.t("web-pages.rigs.remove") },
            fn() {
              let at = @signals.untracked(here)
              confirm(
                @sf.t("web-pages.rigs.removeAsk", args=[("name", @signals.untracked(name))]),
                @sf.t("web-pages.rigs.removeNote"),
                @sf.t("web-pages.rigs.remove"),
                danger=true,
                fn() {
                  @settings.act(
                    core,
                    @sf.t("web-pages.rigs.remove"),
                    "workspace.removeStation",
                    obj([("workspace", str(at.workspace)), ("station", str(id)), ("account", str(at.sub))]),
                  )
                },
              )
            },
            danger=true,
            chevron=false,
          )
        })
  })
}

///|
/// The spinner at a row's end while its log is read.
let rig_spinner : Double = 16.0

///|
/// A chat as a grant or a request names it: its title, or that it has none yet.
fn rig_chat_title(r : Json?) -> String {
  let title = text(r, "title")
  if title == "" {
    @sf.t("web-pages.rigs.grant.untitled")
  } else {
    title
  }
}
