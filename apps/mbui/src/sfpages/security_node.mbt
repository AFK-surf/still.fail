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
          // PairSteps is shared with the waiting page. Its node implementation is being provided separately.
          @ui.old(k, natural=true, unlaid=fn() { 120.0 }, fn(c) { pair_steps(c, core, here().workspace, in_card=true) }) |> ignore
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
/// The original security rows use a list card when narrow and a card of spaced rows when wide.
fn security_group_node(
  parent : @view.View,
  rows : (@view.View) -> Unit,
  top_button? : () -> Bool = fn() { false },
  bottom_button? : () -> Bool = fn() { false },
) -> Unit {
  if @sf.look_node(parent) is Narrow {
    @sf.group_node(parent, rows)
  } else {
    parent.box(fn(k) {
      k.padding(By(fn() {
        let inset = @sf.card_foot_in(@sf.button_height())
        (@sf.card_pad, if top_button() { inset } else { @sf.card_pad }, @sf.card_pad, if bottom_button() { inset } else { @sf.card_pad })
      })).gap(Is(12.0)).radius(By(fn() { @ui.tree_theme().corner(Xl3) }))
      .ground(By(fn() { @ui.tree_theme().color(Card) })) |> ignore
      rows(k)
    }) |> ignore
  }
}

///|
fn security_people_node(parent : @view.View, core : Core, here : () -> Here, lock : () -> Json?) -> Unit {
  @sf.section_node(parent, fn() { @sf.t("web-pages.security.people") }, fn(s) {
    security_group_node(s, fn(g) {
      g.each(fn() { items(lock(), "members") }, fn(m) { text(Some(m), "sub") }, fn(row, person) {
        let m = fn() { Some(person.get()) }
        let wide = @sf.look_node(row) is Wide
        row.gap(Is(if wide { 12.0 } else { 0.0 })) |> ignore
        security_line_node(row, fn() { text(m(), "nameText") }, fn() { if wide { text(m(), "roleText") } else { "" } },
          end=fn(e) { if !wide { security_end_node(e, fn() { text(m(), "roleText") }) } })
        row.box(fn(devices) {
          if wide { devices.padding(Is((40.0, 0.0, 0.0, 0.0))).gap(Is(8.0)) |> ignore }
          devices.each(fn() { items(m(), "groups").mapi(fn(i, group) { (i, group) }) }, fn(group) { text(Some(group.1), "appText") }, fn(gr, group) {
            let gv = fn() { Some(group.get().1) }
            if wide { gr.gap(Is(8.0)) |> ignore }
            gr.show(fn() { items(gv(), "devices").length() > 0 }, fn(h) {
              h.padding(By(fn() {
                if wide { (0.0, if group.get().0 > 0 { 6.0 } else { 0.0 }, 0.0, 0.0) } else { (24.0, 6.0, 12.0, 0.0) }
              })) |> ignore
              @sf.words_node(h, fn() { text(gv(), "appText") }, fn() { if wide { sec_over_words } else { sec_narrow_over_words } }) |> ignore
            })
            gr.each(fn() { items(gv(), "devices") }, fn(d) { text(Some(d), "id") }, fn(d, dev) {
              security_device_node(d, core, here, lock, fn() { Some(dev.get()) })
            })
          })
        }) |> ignore
      })
    })
  })
}

///|
/// A row's words and optional end. Narrow notes occupy their own line; wide notes follow the title.
fn security_line_node(
  parent : @view.View,
  title : () -> String,
  note : () -> String,
  end? : (@view.View) -> Unit,
  mark? : (@view.View) -> Unit,
  indent? : Bool = false,
  warn? : () -> Bool = fn() { false },
  strong? : Bool = true,
  acts? : (@view.View) -> Unit,
  acts_shown? : () -> Bool = fn() { true },
) -> Unit {
  let wide = @sf.look_node(parent) is Wide
  parent.box(fn(row) {
    row.row(Is(true)).gap(Is(12.0)).lines_up(Is(Some(Middle))) |> ignore
    if wide {
      row.min_height(Is(Some(sec_row_least))) |> ignore
    } else {
      row.padding(Is((if indent { 24.0 } else { 12.0 }, 10.0, 12.0, 10.0))) |> ignore
    }
    match mark { Some(f) => f(row); None => () }
    row.box(fn(body) {
      body.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
      body.box(fn(line) {
        line.row(Is(true)).gap(Is(if wide { 6.0 } else { 8.0 })).lines_up(Is(Some(if wide { End } else { Start }))) |> ignore
        line.show(fn() { title() != "" }, fn(t) {
          if !wide { t.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore }
          else { t.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore }
          @sf.words_node(t, title, fn() { if wide { if strong { sec_row_name } else { sec_row_words } } else { narrow_row_title } }) |> ignore
        })
        if wide {
          line.show(fn() { note() != "" }, fn(n) {
            n.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
            @sf.words_node(n, note, fn() { if warn() { sec_warn } else { sec_row_meta } }) |> ignore
          })
        } else {
          match end { Some(f) => f(line); None => () }
        }
      }) |> ignore
      if !wide {
        body.show(fn() { note() != "" }, fn(n) { @sf.words_node(n, note, fn() { if warn() { sec_narrow_warn } else { @sf.pg_link_note } }) |> ignore })
        match acts {
          Some(f) => body.show(acts_shown, fn(a) { a.row(Is(true)).gap(Is(20.0)).padding(Is((0.0, 6.0, 0.0, 0.0))) |> ignore; f(a) })
          None => ()
        }
      }
    }) |> ignore
    if wide {
      match end { Some(f) => f(row); None => () }
      match acts { Some(f) => row.show(acts_shown, fn(a) { a.row(Is(true)).gap(Is(12.0)) |> ignore; f(a) }); None => () }
    }
  }) |> ignore
}

///|
fn security_end_node(parent : @view.View, words : () -> String, warn? : Bool = false) -> Unit {
  let wide = @sf.look_node(parent) is Wide
  @sf.words_node(parent, words, fn() {
    if wide { if warn { sec_warn_state } else { sec_row_state } } else { if warn { sec_narrow_end_warn } else { sec_narrow_end } }
  }) |> ignore
}

///|
fn security_device_node(parent : @view.View, core : Core, here : () -> Here, lock : () -> Json?, dev : () -> Json?) -> Unit {
  let id = fn() { text(dev(), "id") }
  let ws = fn() { here().workspace }
  let renew = fn() { has(dev(), "daysLeft") && flag(lock(), "signs") }
  let remove = fn() { flag(dev(), "removable") }
  let busy = fn(action : String) { is_doing(core, [action], [("workspace", ws()), ("device", id())]) }
  security_line_node(parent, fn() { text(dev(), "nameText") }, fn() { text(dev(), "metaText") }, indent=true, strong=false,
    warn=fn() { flag(dev(), "renewSoon") },
    mark=fn(m) {
      m.pick(fn() { text(dev(), "kind") == "web" }, fn(p, web) {
        @sf.icon_node(p, if web { "web" } else { "monitor" }, sec_device_glyph, By(fn() { @sf.theme().p.muted })) |> ignore
      })
    },
    acts_shown=fn() { renew() || remove() }, acts=fn(a) {
      a.show(renew, fn(r) {
        security_action_node(r, fn() { @sf.t("web-pages.security.renew") }, fn() { busy("lock.renew") }, fn() {
          lock_call(core, ws(), "renew", @sf.t("web-pages.security.renew"), [("device", id())], done=@sf.t("web-pages.security.renewed"))
        })
      })
      a.show(remove, fn(r) {
        security_action_node(r, fn() { @sf.t("web-pages.security.remove") }, fn() { busy("lock.removeDevice") }, fn() {
          remove_dialog(core, ws(), id(), text(dev(), "fullText"))
        })
      })
    },
  )
}

///|
fn security_action_node(parent : @view.View, words : () -> String, busy : () -> Bool, press : () -> Unit) -> Unit {
  if @sf.look_node(parent) is Wide {
    @sf.button_node(parent, words, press, tone=Ghost, busy~) |> ignore
  } else {
    parent.pick(busy, fn(p, working) {
      if working { @sf.spinner_node(p, size=14.0) |> ignore } else { @sf.tap_text_node(p, words, press) }
    })
  }
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
        security_group_node(p, top_button=fn() {
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
            let wide = @sf.look_node(row) is Wide
            let named = fn() { wide && @sf.has_station_mark(text(st(), "emoji"), text(st(), "icon")) }
            security_line_node(row, fn() { if named() { "" } else { text(st(), "name") } }, fn() { if guarded() { "" } else { @sf.t("web-pages.security.unprotectedWhy") } },
              mark=fn(m) {
                m.pick(guarded, fn(d, on) { security_dot_node(d, on) })
                if wide {
                  m.show(named, fn(mark) {
                    mark.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Middle))) |> ignore
                    @sf.station_mark_node(mark, fn() { text(st(), "emoji") }, fn() { text(st(), "icon") }, desk_mark, fn() { @sf.theme().p.text }, stint)
                    @sf.words_node(mark, fn() { text(st(), "name") }, fn() { sec_row_name }) |> ignore
                  })
                }
              },
              end=fn(e) {
                e.pick(fn() { if guarded() { 0 } else if can() { 1 } else { 2 } }, fn(x, state) {
                  match state {
                    0 => security_end_node(x, fn() { @sf.t("web-pages.security.protected") })
                    1 => {
                      let button = @sf.button_node(x, fn() { @sf.t("web-pages.security.join") }, fn() {
                        join_dialog(core, here().workspace, id(), text(st(), "name"))
                      }, tone=Ghost, busy=fn() { is_doing(core, ["lock.joinStation"], [("workspace", here().workspace), ("station", id())]) })
                      if wide { button.margin(Is((0.0, 0.0, @sf.card_foot_in(@sf.button_height()) - @sf.card_pad, 0.0))) |> ignore }
                    }
                    _ => security_end_node(x, fn() { @sf.t("web-pages.security.unprotected") }, warn=true)
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
  if @sf.look_node(parent) is Wide {
    parent.box(fn(line) {
      line.row(Is(true)) |> ignore
      @sf.button_node(line, fn() { @sf.t("web-pages.security.turnOff") }, press, tone=Danger, busy~) |> ignore
    }) |> ignore
  } else {
    parent.box(fn(foot) {
      foot.padding(Is((0.0, 16.0, 0.0, 0.0))) |> ignore
      @sf.group_node(foot, fn(g) {
        g.box(fn(row) {
          row.row(Is(true)).padding(Is((12.0, 10.0, 12.0, 10.0))).lines_up(Is(Some(Middle)))
          .min_height(By(fn() { Some(@sf.theme().items.least) })) |> ignore
          row.pick(busy, fn(hit, working) {
            hit.over(Is(true)).width_share(Is(1.0)).height_share(Is(1.0)) |> ignore
            if working {
              hit.presses(Is(false)).says(By(fn() { Some(@view.said(Button, label=@sf.t("web-pages.security.turnOff"))) })) |> ignore
            } else {
              @sf.pressed_node(hit, press, Is(@sf.row_corner), Button, fn() { @sf.t("web-pages.security.turnOff") })
            }
          })
          @sf.words_node(row, fn() { @sf.t("web-pages.security.turnOff") }, fn() { acc_delete_words })
          .grow(Is(1.0)) |> ignore
          row.show(busy, fn(s) { @sf.spinner_node(s, size=14.0) |> ignore })
        }) |> ignore
      })
    }) |> ignore
  }
}
