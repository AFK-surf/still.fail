// The workspace's security mode, its lock (settings/Security.kt, docs/workspace-lock.md; the core's `lock` and
// `lockDraft` topics, `lock.*` calls): its page from the settings, what it is while off, while on its devices waiting to
// be confirmed (each a sheet with the code its screen shows: 确认 or 拒绝), its people and their devices, its stations,
// and turning it off; turning it on (SecurityOpen) as a page of its own. The signing itself is the core's (it asks the
// host for the device's key: `secure.*`).

///|
/// A device's name as people know it (Security.kt deviceName): its label, or what kind of client it is.
fn device_name(kind : String, label : String, older? : Bool = false) -> String {
  if older {
    if label == "" {
      tr("web-pages.security.olderClient")
    } else {
      label
    }
  } else if label != "" {
    label
  } else if kind == "web" {
    tr("web-pages.security.webDevice")
  } else {
    tr("web-pages.security.appDevice")
  }
}

///|
/// `lock.<name>` on this workspace, let go on by itself and said how it ended (AppState.lockCall).
fn lock_call(
  core : Core,
  ws : String,
  name : String,
  what : String,
  params : Array[(String, String)],
  done? : String = "",
) -> Unit {
  let p : Array[(String, Json)] = [("workspace", str(ws))]
  for kv in params {
    p.push((kv.0, str(kv.1)))
  }
  act(core, what, "lock." + name, obj(p), done~)
}

///|
/// Whether the security page is turning the lock on (SecurityOpen) rather than showing it.
let opening_lock : Ref[Bool] = Ref(false)

///|
fn security_page(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  if opening_lock.val {
    security_open_page(c, core, here)
    return
  }
  let topic = (core.topic)("lock", { "workspace": str(here.workspace) })
  let lock = topic.value
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      let blocks : Array[() -> Unit] = [
        fn() { top_back(c, core, tr("android-settings.title")) },
        fn() { large_title(c, tr("web-pages.security.title")) },
      ]
      match lock {
        None =>
          blocks.push(fn() {
            waiting_cards(
              c,
              error=match topic.error {
                Some(e) => error_text(e)
                None => ""
              },
            )
          })
        Some(_) if !flag(lock, "available") =>
          blocks.push(fn() {
            list_card(c, fn() { body(c, fn() { note(c, tr("web-pages.security.unavailable")) }) })
          })
        Some(_) if flag(lock, "locked") => blocks.append(lock_on(c, core, here, lock))
        Some(_) => blocks.append(lock_off(c, lock))
      }
      blocks.push(fn() { gap(c, 30.0) })
      scroll_page(c, "security", blocks)
    })
    |> ignore
    if flag(lock, "available") && !flag(lock, "locked") && flag(lock, "owner") && flag(lock, "canSign") {
      foot(c, fn() {
        if wide_button(c, "lock-turn-on", tr("web-pages.security.turnOn"), true) {
          opening_lock.val = true
        }
      })
    }
  })
  |> ignore
}

///|
/// The page's main action along the screen's foot, as wide as it (Security.kt Foot); a note over it.
fn foot(c : @ui.Ctx, f : () -> Unit, words? : String = "") -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), padx=16.0, pady=10.0, gap=8.0, align=ACenter, bg=t.p.bg, fn() {
    if words != "" {
      note(c, words)
    }
    f()
  })
  |> ignore
}

///|
/// Off (Security.kt Off): what it is now and once on, how new devices come in; who may turn it on.
fn lock_off(c : @ui.Ctx, lock : Json?) -> Array[() -> Unit] {
  let t = @sf.theme()
  [
    fn() {
      list_card(c, fn() {
        body(c, fn() {
          c.box(dir=Row, gap=8.0, align=ACenter, fn() {
            dot(c, false)
            c.text(tr("web-pages.security.off"), size=15.0, weight=600, color=t.p.text, wrap=false, line=21.0) |> ignore
          })
          |> ignore
          para(c, tr("web-pages.security.now"), sub=tr("web-pages.security.nowRisk"))
          para(c, tr("web-pages.security.then"))
          para(c, tr("web-pages.security.newDevices"), sub=tr("web-pages.security.newDevicesHow"))
          if !flag(lock, "owner") {
            note(c, tr("web-pages.security.ownerOnly"))
          } else if !flag(lock, "canSign") {
            note(c, tr("web-pages.security.webCannotSign"))
          }
        })
      })
    },
    fn() { section_header(c, tr("web-pages.security.signing"), start=S6) },
    fn() { list_card(c, fn() { body(c, fn() { note(c, tr("web-pages.security.signingWho")) }) }) },
  ]
}

///|
/// On (Security.kt On): how many sign and what it protects, the devices waiting (each opening its sheet, where this
/// device signs), its people and their devices, its stations, what a web page may do, turning it off.
fn lock_on(c : @ui.Ctx, core : Core, here : Here, lock : Json?) -> Array[() -> Unit] {
  let t = @sf.theme()
  let ws = here.workspace
  let signs = flag(lock, "signs")
  let me = field(lock, "me")
  // the devices waiting for someone to approve them: not this one's own request (said above as this device's), and
  // only where this device can approve (an untrusted one lists none: it has nothing to do with them)
  let requests = if signs {
    items(lock, "requests").filter(fn(r) { text(Some(r), "device") != text(me, "device") })
  } else {
    []
  }
  let blocks : Array[() -> Unit] = [
    fn() {
      list_card(c, fn() {
        body(c, fn() {
          c.box(dir=Row, gap=8.0, align=ACenter, fn() {
            dot(c, true)
            c.text(tr("web-pages.security.on"), size=15.0, weight=600, color=t.p.text, wrap=false, line=21.0) |> ignore
          })
          |> ignore
          note(
            c,
            fill("web-pages.security.onMeta", [
              ("signers", count(lock, "signers").to_string()),
              ("stations", count(lock, "protected").to_string()),
            ]),
          )
          if flag(me, "waiting") {
            // this device waits to be approved: its code, as its approver sees it, and how it comes in (the
            // waiting page in the chats' place: 发送批准请求)
            note(c, tr("web-pages.security.waitingTitle") + " · " + tr("mbui.security.waitingWhere"))
            c.box(dir=Row, gap=8.0, align=ACenter, fn() {
              c.text(tr("web-pages.security.thisDevice"), size=13.0, color=t.p.muted, line=18.0, wrap=false) |> ignore
              mono(c, text(me, "code"), size=13.0, weight=600)
            })
            |> ignore
          } else if !signs {
            note(
              c,
              tr(
                if flag(lock, "canSign") {
                  "web-pages.security.notSignerApp"
                } else {
                  "web-pages.security.notSignerWeb"
                },
              ),
            )
          }
        })
      })
    },
  ]
  if requests.length() > 0 {
    blocks.append([
      fn() { section_header(c, tr("web-pages.security.waiting") + " · " + requests.length().to_string(), start=S6) },
      fn() {
        list_card(c, fn() {
          for r in requests {
            let rv = Some(r)
            let device = text(rv, "device")
            if list_row(c, key=if signs { "request/" + device } else { "" }, fn() {
                row_lines(
                  c,
                  fill("web-pages.security.newDeviceOf", [
                    (
                      "name",
                      match text(rv, "name") {
                        "" => text(rv, "email")
                        n => n
                      },
                    ),
                  ]),
                  device_name(text(rv, "kind"), text(rv, "label")) + " · " + stamp(rv, "created_at", "ago"),
                )
                mono(c, text(rv, "code"), size=14.0, weight=600)
              }) {
              confirm_device(core, ws, r)
            }
          }
        })
      },
    ])
  }
  blocks.append([
    fn() { section_header(c, tr("web-pages.security.people"), start=S6) },
    fn() {
      list_card(c, fn() {
        for m in items(lock, "members") {
          let mv = Some(m)
          list_row(c, fn() {
            row_title(
              c,
              match text(mv, "name") {
                "" => text(mv, "email")
                n => n
              },
            )
            c.text(role_label(text(mv, "role")), size=14.0, color=t.p.subtle, wrap=false) |> ignore
          })
          |> ignore
          for d in items(mv, "devices") {
            device_row(c, core, ws, d, signs)
          }
        }
      })
    },
    fn() { section_header(c, "Station", start=S6) },
    fn() {
      list_card(c, fn() {
        let stations = items(lock, "stations")
        if stations.length() == 0 {
          body(c, fn() { note(c, tr("web-pages.security.noStations")) })
        }
        for st in stations {
          let sv = Some(st)
          let id = text(sv, "id")
          let guarded = flag(sv, "protected")
          let can_join = !guarded && flag(lock, "owner") && signs
          let joining = is_doing(core, ["lock.joinStation"], [("workspace", ws), ("station", id)])
          if list_row(c, key=if can_join && !joining { "lock-station/" + id } else { "" }, fn() {
              dot(c, guarded, warned=!guarded)
              row_lines(
                c,
                text(sv, "name"),
                if guarded {
                  ""
                } else {
                  tr("web-pages.security.unprotectedWhy")
                },
                wrap_sub=true,
              )
              if guarded {
                c.text(tr("web-pages.security.protected"), size=13.0, color=t.p.subtle, wrap=false) |> ignore
              } else if joining {
                spinner(c)
              } else if can_join {
                c.text(tr("web-pages.security.join"), size=14.0, color=t.p.accent, wrap=false) |> ignore
              } else {
                c.text(tr("web-pages.security.unprotected"), size=13.0, color=warn, wrap=false) |> ignore
              }
            }) {
            join_station(core, ws, id, text(sv, "name"))
          }
        }
      })
    },
    fn() { section_header(c, tr("web-pages.security.webTitle"), start=S6) },
    fn() { list_card(c, fn() { body(c, fn() { note(c, tr("web-pages.security.webRisk")) }) }) },
  ])
  if flag(lock, "owner") && signs {
    blocks.push(fn() {
      gap(c, 18.0)
      list_card(c, fn() {
        let off = is_doing(core, ["lock.disable"], [("workspace", ws)])
        if list_row(c, key=if off { "" } else { "lock-off" }, fn() {
            row_title(c, tr("web-pages.security.turnOff"), color=t.p.red)
            if off {
              spinner(c, inline=true)
            }
          }) {
          turn_off(core, ws, here.name)
        }
      })
    })
  }
  blocks
}

///|
/// A device in the lock (Security.kt DeviceRow): its name, what it is (signs, this device, days left); a web page's
/// renewed with a tap where this device signs.
fn device_row(c : @ui.Ctx, core : Core, ws : String, d : Json, can_renew : Bool) -> Unit {
  let t = @sf.theme()
  let dv = Some(d)
  let id = text(dv, "id")
  let renewing = is_doing(core, ["lock.renew"], [("workspace", ws), ("device", id)])
  let days = if has(dv, "daysLeft") { Some(count(dv, "daysLeft")) } else { None }
  let meta = join(
    [
      if text(dv, "kind") == "web" {
        tr("web-pages.security.web")
      } else {
        tr("web-pages.security.app")
      },
      if flag(dv, "signs") { tr("web-pages.security.signs") } else { "" },
      if flag(dv, "mine") { tr("web-pages.security.thisDevice") } else { "" },
      match days {
        Some(n) => fill("web-pages.security.daysLeft", [("n", n.to_string())])
        None => ""
      },
      if flag(dv, "recent") { tr("web-pages.security.recent") } else { "" },
    ],
    " · ",
  )
  let renew = days is Some(_) && can_renew
  if list_row(c, key=if renew && !renewing { "renew/" + id } else { "" }, fn() {
      c.box(w=Fill(1.0), pl=14.0, fn() {
        row_lines(
          c,
          device_name(text(dv, "kind"), text(dv, "label"), older=flag(dv, "older")),
          meta,
          sub_color=if flag(dv, "renewSoon") { warn } else { t.p.muted },
        )
      })
      |> ignore
      if renewing {
        spinner(c)
      } else if renew {
        c.text(tr("web-pages.security.renew"), size=14.0, color=t.p.accent, wrap=false) |> ignore
      }
    }) {
    lock_call(core, ws, "renew", tr("web-pages.security.renew"), [("device", id)], done=tr("web-pages.security.renewed"))
  }
}

///|
/// A waiting device, confirmed once its code is the one on its screen (Security.kt confirmSheet): who and what it is,
/// its code large, 拒绝 and 确认; gone once answered on another device.
fn confirm_device(core : Core, ws : String, r : Json) -> Unit {
  let rv = Some(r)
  let device = text(rv, "device")
  let code = text(rv, "code")
  let who = match text(rv, "name") {
    "" => text(rv, "email")
    n => n
  }
  open_sheet(0.55, fn(c, _) {
    let t = @sf.theme()
    let lock = (core.topic)("lock", { "workspace": str(ws) }).value
    if lock is Some(_) && !items(lock, "requests").iter().any(fn(x) { text(Some(x), "device") == device }) {
      close_sheet()
      return
    }
    sheet_head(c, fill("web-pages.security.confirmTitle", [("name", who)]))
    c.box(w=Fill(1.0), padx=20.0, gap=12.0, fn() {
      c.text(
        fill("web-pages.security.confirmBody", [("device", device_name(text(rv, "kind"), text(rv, "label"))), ("name", who)]),
        size=14.0,
        color=t.p.muted,
        w=Fill(1.0),
        line=20.0,
      )
      |> ignore
      mono(c, spaced(code), size=34.0, weight=600, line=44.0, center=true)
      note(
        c,
        tr(
          if text(rv, "kind") == "web" {
            "web-pages.security.confirmWeb"
          } else {
            "web-pages.security.confirmApp"
          },
        ),
      )
      c.box(dir=Row, w=Fill(1.0), pt=4.0, gap=10.0, fn() {
        c.box(w=Fill(1.0), fn() {
          if wide_button(c, "lock-deny", tr("web-pages.security.deny"), false) {
            close_sheet()
            lock_call(core, ws, "deny", tr("web-pages.security.deny"), [("device", device)])
          }
        })
        |> ignore
        c.box(w=Fill(1.0), fn() {
          if wide_button(c, "lock-confirm", tr("web-pages.security.confirm"), true) {
            close_sheet()
            lock_call(
              core,
              ws,
              "confirm",
              tr("web-pages.security.confirm"),
              [("device", device), ("code", code)],
              done=tr("web-pages.security.confirmed"),
            )
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// A code's letters a little apart (letterSpacing 5): a thin space between each two.
fn spaced(code : String) -> String {
  let b = StringBuilder()
  let mut first = true
  for ch in code {
    if !first {
      b.write_char('\u{2009}')
    }
    b.write_char(ch)
    first = false
  }
  b.to_string()
}

///|
/// A station of the workspace not in the lock, taken in once its owner says it is theirs (Security.kt joinSheet).
fn join_station(core : Core, ws : String, station : String, name : String) -> Unit {
  open_sheet(0.4, fn(c, _) {
    let t = @sf.theme()
    sheet_head(c, fill("web-pages.security.joinTitle", [("name", name)]))
    c.box(w=Fill(1.0), padx=20.0, gap=12.0, fn() {
      c.text(tr("web-pages.security.joinBody"), size=14.0, color=t.p.muted, w=Fill(1.0), line=20.0) |> ignore
      c.box(dir=Row, w=Fill(1.0), pt=4.0, gap=10.0, fn() {
        c.box(w=Fill(1.0), fn() {
          if wide_button(c, "join-cancel", tr("common.cancel"), false) {
            close_sheet()
          }
        })
        |> ignore
        c.box(w=Fill(1.0), fn() {
          if wide_button(c, "join-go", tr("web-pages.security.join"), true) {
            close_sheet()
            lock_call(
              core,
              ws,
              "joinStation",
              tr("web-pages.security.join"),
              [("station", station)],
              done=fill("web-pages.security.joined", [("name", name)]),
            )
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// 关闭安全模式？ (Security.kt turnOffSheet): what turning it off gives up, a line each, and the workspace's name typed
/// before it can go (`lock.disable`).
fn turn_off(core : Core, ws : String, name : String) -> Unit {
  let key = "turn-off/" + (sheet.serial + 1).to_string()
  open_sheet(0.62, fn(c, _) {
    let t = @sf.theme()
    sheet_head(c, tr("web-pages.security.turnOffTitle"))
    c.box(w=Fill(1.0), padx=20.0, gap=12.0, fn() {
      c.text(tr("web-pages.security.turnOffBody"), size=14.0, color=t.p.muted, w=Fill(1.0), line=20.0) |> ignore
      for said in [
        ("server", "web-pages.security.nowRisk"),
        ("devices", "web-pages.security.turnOffApproval"),
        ("key", "web-pages.security.turnOffVault"),
      ] {
        c.box(dir=Row, w=Fill(1.0), gap=10.0, fn() {
          c.box(pt=2.0, fn() { @sf.icon(c, said.0, size=18.0, color=t.p.muted) |> ignore }) |> ignore
          c.text(tr(said.1), size=15.0, color=t.p.text, w=Fill(1.0), line=22.0) |> ignore
        })
        |> ignore
      }
      c.box(w=Fill(1.0), pt=6.0, fn() {
        c.text(fill("web-pages.security.turnOffType", [("name", name)]), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0)
        |> ignore
      })
      |> ignore
      let typed = field_box(c, key, "")
      let named = typed.trim(chars=" \t\n").to_owned() == name.trim(chars=" \t\n").to_owned()
      c.box(dir=Row, w=Fill(1.0), pt=16.0, gap=10.0, fn() {
        c.box(w=Fill(1.0), fn() {
          if wide_button(c, "off-cancel", tr("common.cancel"), false) {
            c.blur()
            close_sheet()
          }
        })
        |> ignore
        c.box(w=Fill(1.0), fn() {
          if wide_button(c, "off-go", tr("web-pages.security.turnOff"), true, danger=true, enabled=named) {
            c.blur()
            close_sheet()
            act(core, tr("web-pages.security.turnOff"), "lock.disable", obj([("workspace", str(ws))]))
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// 开启安全模式 (Security.kt SecurityOpenScreen, the core's `lockDraft`): its members, the devices and stations it would
/// sign (each ticked in or out: `lock.toggle`), then 签名并开启 (`lock.open`) along the foot.
fn security_open_page(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let t = @sf.theme()
  let ws = here.workspace
  let topic = (core.topic)("lockDraft", { "workspace": str(ws) })
  let draft = topic.value
  let ready = draft is Some(_) && !flag(draft, "loading")
  let toggle = fn(id : String) {
    act(core, tr("web-pages.security.turnOn"), "lock.toggle", obj([("workspace", str(ws)), ("id", str(id))]))
  }
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      let blocks : Array[() -> Unit] = [
        fn() {
          c.box(dir=Row, w=Fill(1.0), pl=10.0, pr=10.0, pt=6.0, pb=4.0, align=ACenter, fn() {
            if nav_back(c, tr("web-pages.security.title")) {
              opening_lock.val = false
            }
          })
          |> ignore
        },
        fn() { large_title(c, tr("web-pages.security.openTitle")) },
      ]
      if !ready {
        blocks.push(fn() {
          waiting_cards(
            c,
            error=match topic.error {
              Some(e) => error_text(e)
              None => ""
            },
          )
        })
      } else {
        blocks.append([
          fn() { page_note(c, tr("web-pages.security.openLead")) },
          fn() { section_header(c, tr("web-pages.security.members"), start=S6) },
          fn() {
            list_card(c, fn() {
              for m in items(draft, "members") {
                let mv = Some(m)
                list_row(c, fn() {
                  row_lines(
                    c,
                    match text(mv, "name") {
                      "" => text(mv, "email")
                      n => n
                    },
                    text(mv, "email"),
                  )
                  c.text(role_label(text(mv, "role")), size=14.0, color=t.p.subtle, wrap=false) |> ignore
                })
                |> ignore
              }
            })
          },
          fn() { section_header(c, tr("web-pages.security.devices"), start=S6) },
          fn() {
            list_card(c, fn() {
              for d in items(draft, "devices") {
                let dv = Some(d)
                let older = flag(dv, "older")
                if pick_row(
                    c,
                    "draft-device/" + text(dv, "id"),
                    text(dv, "person") +
                    " · " +
                    (if flag(dv, "current") {
                      tr("web-pages.security.thisDevice")
                    } else {
                      device_name(text(dv, "kind"), text(dv, "label"), older~)
                    }),
                    sub=if older {
                      tr("web-pages.security.olderHow")
                    } else if text(dv, "kind") == "web" {
                      tr("web-pages.security.web")
                    } else {
                      tr("web-pages.security.app")
                    },
                    checked=flag(dv, "on"),
                    enabled=!flag(dv, "fixed"),
                  ) {
                  toggle(text(dv, "id"))
                }
              }
            })
          },
          fn() { section_header(c, "Station", start=S6) },
          fn() {
            list_card(c, fn() {
              for st in items(draft, "stations") {
                let sv = Some(st)
                if pick_row(
                    c,
                    "draft-station/" + text(sv, "id"),
                    text(sv, "name"),
                    sub=match text(sv, "state") {
                      "ok" => text(sv, "version")
                      "asking" => tr("web-pages.security.asking")
                      "old" => tr("web-pages.security.tooOld")
                      _ => tr("web-pages.security.offline")
                    },
                    checked=flag(sv, "on"),
                    enabled=!flag(sv, "fixed"),
                  ) {
                  toggle(text(sv, "id"))
                }
              }
            })
          },
          fn() { page_note(c, tr("web-pages.security.unprotectedNote")) },
        ])
      }
      blocks.push(fn() { gap(c, 24.0) })
      scroll_page(c, "security-open", blocks)
    })
    |> ignore
    if ready {
      foot(
        c,
        words=tr(
          if flag(draft, "canSign") {
            "web-pages.security.webExpiry"
          } else {
            "web-pages.security.webCannotSign"
          },
        ),
        fn() {
          let opening = is_doing(core, ["lock.open"], [("workspace", ws)])
          if wide_button(
              c,
              "lock-open",
              tr("web-pages.security.signAndTurnOn"),
              true,
              busy=opening,
              enabled=flag(draft, "ready") && flag(draft, "owner") && flag(draft, "canSign"),
            ) {
            act(
              core,
              tr("web-pages.security.turnOn"),
              "lock.open",
              obj([("workspace", str(ws))]),
              done=tr("web-pages.security.turnedOn"),
              then=fn(_) { opening_lock.val = false },
            )
          }
        },
      )
    }
  })
  |> ignore
}
