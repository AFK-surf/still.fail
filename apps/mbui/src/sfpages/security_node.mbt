// Security settings, made once in the view tree. The core's lock remains the source of every state and action.

///|
pub fn security_node(
  v : @view.View,
  core : Core,
  here : () -> Here,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
  stint? : () -> Int = fn() { 0 },
) -> Unit {
  let topic = fn() { (core.topic)("lock", { "workspace": str(here().workspace) }) }
  let lock = fn() { topic().value }
  // The security fixture opens these presenters once as the page is made, as the old settings frame did.
  match @settings.fixture_desk() {
    "lock-join" => join_dialog(core, "ws1", "st2", "Maple")
    "lock-off" => turn_off_dialog(core, "ws1", "星火工作室")
    _ => ()
  }
  @sf.page_node(
    v,
    fn() { @sf.t("web-pages.security.title") },
    on_back~,
    frame~,
    said?,
    width?,
    lead=fn() { @sf.t("web-pages.security.lead") },
    fn() {
      match lock() {
        None => ["waiting"]
        Some(_) if !flag(lock(), "available") => ["unavailable"]
        Some(_) if !flag(lock(), "locked") => ["off", "signing"]
        Some(_) => {
          let blocks = ["on"]
          let me = field(lock(), "me")
          if flag(me, "waiting") || flag(me, "unsigned") { blocks.push("pair") }
          blocks.push("people")
          blocks.push("stations")
          blocks.push("web")
          if flag(lock(), "owner") && flag(lock(), "signs") { blocks.push("disable") }
          blocks
        }
      }
    },
    fn(b, key) {
      match key {
        "waiting" => @sf.waiting_node(b, fn(s) {
          security_off_node(s, core.quiet(), fn() { Some({ "available": true }) })
          security_signing_node(s)
        }, error=fn() {
          match topic().error {
            Some(e) => error_text(e)
            None => ""
          }
        })
        "unavailable" => @sf.page_card_node(b, fn(k) {
          @sf.words_node(k, fn() { @sf.t("web-pages.security.unavailable") }, fn() { sec_said }) |> ignore
        })
        "off" => security_off_node(b, core, lock)
        "signing" => security_signing_node(b)
        "on" => security_on_node(b, lock)
        "pair" => @sf.page_card_node(b, fn(k) {
          @sf.words_node(k, fn() {
            @sf.t(if flag(field(lock(), "me"), "unsigned") { "web-pages.security.upgradeTitle" } else { "web-pages.security.waitingTitle" })
          }, fn() { sec_state }) |> ignore
          pair_steps_node(k, fn() { core }, fn() { here().workspace }, in_card=true)
        })
        "people" => security_people_node(b, core, here, lock)
        "stations" => security_stations_node(b, core, here, lock, stint)
        "web" => @sf.section_node(b, fn() { @sf.t("web-pages.security.webTitle") }, fn(s) {
          @sf.page_card_node(s, fn(k) { @sf.words_node(k, fn() { @sf.t("web-pages.security.webRisk") }, fn() { sec_said }) |> ignore })
        })
        "disable" => security_disable_node(b, core, here)
        _ => ()
      }
    },
  )
}

///|
fn security_dot_node(parent : @view.View, on : Bool) -> Unit {
  parent.box(fn(dot) {
    dot.width(Is(Some(sec_dot_side))).height(Is(Some(sec_dot_side))).radius(Is(sec_dot_side / 2.0))
    .ground(By(fn() { @ui.tree_theme().color(if on { Positive } else { Warn }) })) |> ignore
  }) |> ignore
}

///|
fn security_point_node(parent : @view.View, icon : String, title : String, note : String) -> Unit {
  parent.box(fn(line) {
    line.row(Is(true)).gap(Is(8.0)) |> ignore
    line.box(fn(mark) {
      mark.width(Is(Some(20.0))).padding(Is((0.0, 1.0, 0.0, 0.0))).lines_up(Is(Some(Middle))) |> ignore
      @sf.icon_node(mark, icon, sec_point_glyph, By(fn() { @sf.theme().p.muted })) |> ignore
    }) |> ignore
    line.box(fn(words) {
      words.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
      @sf.words_node(words, fn() { @sf.t(title) }, fn() { sec_point_text }) |> ignore
      @sf.words_node(words, fn() { @sf.t(note) }, fn() { sec_point_rest }) |> ignore
    }) |> ignore
  }) |> ignore
}

///|
fn security_off_node(parent : @view.View, core : Core, lock : () -> Json?) -> Unit {
  @sf.page_card_node(parent, fn(k) {
    k.box(fn(line) {
      line.row(Is(true)).gap(Is(8.0)).lines_up(Is(Some(Middle))) |> ignore
      security_dot_node(line, false)
      @sf.words_node(line, fn() { @sf.t("web-pages.security.off") }, fn() { sec_state }) |> ignore
    }) |> ignore
    k.box(fn(points) {
      points.gap(Is(10.0)) |> ignore
      security_point_node(points, "server", "web-pages.security.now", "web-pages.security.nowRisk")
      security_point_node(points, "key", "web-pages.security.then", "web-pages.security.thenSafe")
      security_point_node(points, "devices", "web-pages.security.newDevices", "web-pages.security.newDevicesHow")
    }) |> ignore
    k.pick(fn() { if !flag(lock(), "owner") { 0 } else if flag(lock(), "canSign") { 1 } else { 2 } }, fn(a, state) {
      match state {
        0 => @sf.words_node(a, fn() { @sf.t("web-pages.security.ownerOnly") }, fn() { sec_note }) |> ignore
        1 => a.box(fn(line) {
          line.row(Is(true)).gap(Is(10.0)).lines_up(Is(Some(Middle))).wraps(Is(Some(10.0))) |> ignore
          @sf.button_node(line, fn() { @sf.t("web-pages.security.turnOn") }, fn() { (core.push)(SecurityOpen) }, tone=Primary) |> ignore
          @sf.words_node(line, fn() { @sf.t("web-pages.security.signsHere") }, fn() { sec_note_line }) |> ignore
        }) |> ignore
        _ => @sf.words_node(a, fn() { @sf.t("web-pages.security.webCannotSign") }, fn() { sec_note }) |> ignore
      }
    })
  })
}

///|
fn security_signing_node(parent : @view.View) -> Unit {
  @sf.section_node(parent, fn() { @sf.t("web-pages.security.signing") }, fn(s) {
    @sf.page_card_node(s, fn(k) { @sf.words_node(k, fn() { @sf.t("web-pages.security.signingWho") }, fn() { sec_said }) |> ignore })
  })
}

///|
fn security_on_node(parent : @view.View, lock : () -> Json?) -> Unit {
  @sf.page_card_node(parent, fn(k) {
    k.box(fn(line) {
      line.row(Is(true)).gap(Is(8.0)).lines_up(Is(Some(Middle))) |> ignore
      security_dot_node(line, true)
      @sf.words_node(line, fn() { @sf.t("web-pages.security.on") }, fn() { sec_state }) |> ignore
    }) |> ignore
    @sf.words_node(k, fn() {
      @sf.t("web-pages.security.onMeta", args=[("signers", count(lock(), "signers").to_string()), ("stations", count(lock(), "protected").to_string())])
    }, fn() { sec_state_meta }) |> ignore
    @sf.words_node(k, fn() { @sf.t("web-pages.security.onLead") }, fn() { sec_said }) |> ignore
    k.show(fn() {
      let me = field(lock(), "me")
      !flag(lock(), "signs") && !flag(me, "waiting") && !flag(me, "unsigned")
    }, fn(n) {
      @sf.words_node(n, fn() {
        @sf.t(if flag(lock(), "canSign") { "web-pages.security.notSignerApp" } else { "web-pages.security.notSignerWeb" })
      }, fn() { sec_note }) |> ignore
    })
  })
}

///|
fn security_people_node(parent : @view.View, core : Core, here : () -> Here, lock : () -> Json?) -> Unit {
  @sf.section_node(parent, fn() { @sf.t("web-pages.security.people") }, fn(s) {
    @sf.security_group_node(s, fn(g) {
      g.each(fn() { items(lock(), "members") }, fn(m) { text(Some(m), "sub") }, fn(row, person) {
        let m = fn() { Some(person.get()) }
        @sf.security_person_node(row, fn() { text(m(), "nameText") }, fn() { text(m(), "roleText") })
        row.show(fn() { items(m(), "groups").iter().any(fn(group) { items(Some(group), "devices").length() > 0 }) }, fn(shown) {
          @sf.security_devices_node(shown, fn(devices) {
            devices.each(fn() { items(m(), "groups").mapi(fn(i, group) { (i, group) }) }, fn(group) { text(Some(group.1), "appText") }, fn(gr, group) {
              let gv = fn() { Some(group.get().1) }
              gr.show(fn() { items(gv(), "devices").length() > 0 }, fn(has_devices) {
                @sf.security_device_group_node(has_devices, fn() { text(gv(), "appText") }, apart=fn() { group.get().0 > 0 }, fn(group_rows) {
                  group_rows.each(fn() { items(gv(), "devices") }, fn(d) { text(Some(d), "id") }, fn(d, dev) {
                    security_device_node(d, core, here, lock, fn() { Some(dev.get()) })
                  })
                })
              })
            })
          })
        })
      })
    })
  })
}

///|
fn security_device_node(parent : @view.View, core : Core, here : () -> Here, lock : () -> Json?, dev : () -> Json?) -> Unit {
  let id = fn() { text(dev(), "id") }
  let ws = fn() { here().workspace }
  let renew = fn() { has(dev(), "daysLeft") && flag(lock(), "signs") }
  let remove = fn() { flag(dev(), "removable") }
  let busy = fn(action : String) { is_doing(core, [action], [("workspace", ws()), ("device", id())]) }
  @sf.security_line_node(parent, fn() { text(dev(), "nameText") }, fn() { text(dev(), "metaText") }, indent=true, strong=false, drops=true,
    warn=fn() { flag(dev(), "renewSoon") },
    mark=fn(m) {
      m.pick(fn() { text(dev(), "kind") == "web" }, fn(p, web) {
        @sf.icon_node(p, if web { "web" } else { "monitor" }, sec_device_glyph, By(fn() { @sf.theme().p.muted })) |> ignore
      })
    },
    acts_shown=fn() { renew() || remove() }, acts=fn(a) {
      a.show(renew, fn(r) {
        @sf.security_action_node(r, fn() { @sf.t("web-pages.security.renew") }, fn() {
          lock_call(core, ws(), "renew", @sf.t("web-pages.security.renew"), [("device", id())], done=@sf.t("web-pages.security.renewed"))
        }, busy=fn() { busy("lock.renew") })
      })
      a.show(remove, fn(r) {
        @sf.security_action_node(r, fn() { @sf.t("web-pages.security.remove") }, fn() {
          remove_dialog(core, ws(), id(), text(dev(), "fullText"))
        }, busy=fn() { busy("lock.removeDevice") })
      })
    },
  )
}

///|
fn security_stations_node(parent : @view.View, core : Core, here : () -> Here, lock : () -> Json?, stint : () -> Int) -> Unit {
  @sf.section_node(parent, fn() { "Station" }, fn(s) {
    s.pick(fn() { items(lock(), "stations").length() == 0 }, fn(p, empty) {
      if empty {
        @sf.page_card_node(p, fn(k) { @sf.words_node(k, fn() { @sf.t("web-pages.security.noStations") }, fn() { sec_said }) |> ignore })
      } else {
        let stations = fn() { items(lock(), "stations") }
        let can_join = fn() { flag(lock(), "owner") && flag(lock(), "signs") }
        @sf.security_group_node(p, top_button=fn() {
          match stations().get(0) { Some(st) => can_join() && !flag(Some(st), "protected"); None => false }
        }, bottom_button=fn() {
          let all = stations()
          match all.get(all.length() - 1) { Some(st) => can_join() && !flag(Some(st), "protected"); None => false }
        }, fn(g) {
          g.each(fn() { items(lock(), "stations") }, fn(st) { text(Some(st), "id") }, fn(row, station) {
            let st = fn() { Some(station.get()) }
            let guarded = fn() { flag(st(), "protected") }
            let can = fn() { flag(lock(), "owner") && flag(lock(), "signs") }
            let id = fn() { text(st(), "id") }
            @sf.security_station_line_node(
              row,
              fn() { text(st(), "name") },
              fn() { if guarded() { "" } else { @sf.t("web-pages.security.unprotectedWhy") } },
              guarded,
              fn() { text(st(), "emoji") },
              fn() { text(st(), "icon") },
              stint,
              fn(e) {
                e.pick(fn() { if guarded() { 0 } else if can() { 1 } else { 2 } }, fn(x, state) {
                  match state {
                    0 => @sf.security_end_node(x, fn() { @sf.t("web-pages.security.protected") })
                    1 =>
                      @sf.security_join_button_node(x, fn() { @sf.t("web-pages.security.join") }, fn() {
                        join_dialog(core, here().workspace, id(), text(st(), "name"))
                      }, busy=fn() { is_doing(core, ["lock.joinStation"], [("workspace", here().workspace), ("station", id())]) })
                    _ => @sf.security_end_node(x, fn() { @sf.t("web-pages.security.unprotected") }, warn=fn() { true })
                  }
                })
              },
            )
          })
        })
      }
    })
  })
}

///|
fn security_disable_node(parent : @view.View, core : Core, here : () -> Here) -> Unit {
  let busy = fn() { is_doing(core, ["lock.disable"], [("workspace", here().workspace)]) }
  let press = fn() { turn_off_dialog(core, here().workspace, here().name) }
  @sf.security_danger_node(parent, fn() { @sf.t("web-pages.security.turnOff") }, press, busy~)
}
