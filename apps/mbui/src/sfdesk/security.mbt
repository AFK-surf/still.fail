// 安全 on the desktop, as the web's (ember web/src/cloud/Security.tsx SecuritySettings, Off, On, StationRow, DeviceRow;
// Security.css.ts): what the lock is said under the title; off, a card of what it is now and once on, and the way to
// turn it on; on, a card of how many sign and what it protects, this device's own pairing where it waits, the devices
// waiting to be confirmed, its people and their devices, its stations, what a web page may do, each a section with a
// card, and turning it off. All of it the core's (`lock`); the sheets that confirm, join and turn off are
// security.mbt's. The phone's page is security.mbt's.

///|
fn security_page(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let topic = (core.topic)("lock", { "workspace": str(here.workspace) })
  let lock = topic.value
  let blocks : Array[() -> Unit] = []
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
        c.box(style=desk_card, fn() { c.text(@sf.t("web-pages.security.unavailable"), style=desk_muted) |> ignore }) |> ignore
      })
    Some(_) if flag(lock, "locked") => blocks.append(lock_on(c, core, here, lock))
    Some(_) => blocks.append(lock_off(c, lock))
  }
  desk_page(c, core, "security", @sf.t("web-pages.security.title"), blocks, lead=@sf.t("web-pages.security.lead"))
}

///|
/// Off (Off): the lock's state, what it is now and once on and how new devices come in, a line each with its mark; the
/// way to turn it on (where this device signs), or who may; 签名 under it.
fn lock_off(c : @ui.Ctx, lock : Json?) -> Array[() -> Unit] {
  [
    fn() {
      c.box(style=sec_lead, fn() {
        c.text(@sf.t("web-pages.security.off"), style=sec_state) |> ignore
        c.box(style=sec_points, fn() {
          sec_point(c, "server", @sf.t("web-pages.security.now"), @sf.t("web-pages.security.nowRisk"))
          sec_point(c, "key", @sf.t("web-pages.security.then"), @sf.t("web-pages.security.thenSafe"))
          sec_point(c, "devices", @sf.t("web-pages.security.newDevices"), @sf.t("web-pages.security.newDevicesHow"))
        })
        |> ignore
        if !flag(lock, "owner") {
          c.text(@sf.t("web-pages.security.ownerOnly"), style=sec_note) |> ignore
        } else if flag(lock, "canSign") {
          c.box(style=sec_actions, fn() {
            if @sf.button(c, @sf.t("web-pages.security.turnOn"), key="lock-turn-on", tone=Primary) {
              opening_lock.val = true
            }
            c.text(@sf.t("web-pages.security.signsHere"), style=sec_note) |> ignore
          })
          |> ignore
        } else {
          c.text(@sf.t("web-pages.security.webCannotSign"), style=sec_note) |> ignore
        }
      })
      |> ignore
    },
    fn() {
      @sf.section(c, @sf.t("web-pages.security.signing"), fn() {
        c.box(style=desk_card, fn() { c.text(@sf.t("web-pages.security.signingWho"), style=desk_muted) |> ignore }) |> ignore
      })
    },
  ]
}

///|
/// What it changes, a line (point): its mark 18 muted, its words and the rest quieter after them.
fn sec_point(c : @ui.Ctx, icon : String, words : String, rest : String) -> Unit {
  let t = @sf.theme()
  c.box(style=sec_point_line, fn() {
    c.box(style=sec_point_icon, fn() { @sf.icon(c, icon, size=sec_point_glyph, color=t.p.muted) |> ignore }) |> ignore
    c.box(style=sec_point_words, fn() {
      c.text(words, style=sec_point_text) |> ignore
      c.text(rest, style=sec_point_rest) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// On (On): its state with how many sign and what it protects, what that means; this device's own pairing where it
/// waits or was let in without signing; the devices waiting (each with its code, 验证 where this device signs); its
/// people and their devices; its stations; what a web page may do; 关闭安全模式.
fn lock_on(c : @ui.Ctx, core : Core, here : Here, lock : Json?) -> Array[() -> Unit] {
  let ws = here.workspace
  let signs = flag(lock, "signs")
  let me = field(lock, "me")
  let requests = items(lock, "requests")
  let blocks : Array[() -> Unit] = [
    fn() {
      c.box(style=sec_lead, fn() {
        c.box(style=sec_state_line, fn() {
          c.text(@sf.t("web-pages.security.on"), style=sec_state) |> ignore
          c.text(
            "· " +
            @sf.t("web-pages.security.onMeta", args=[
              ("signers", count(lock, "signers").to_string()),
              ("stations", count(lock, "protected").to_string()),
            ]),
            style=sec_state_meta,
          )
          |> ignore
        })
        |> ignore
        c.text(@sf.t("web-pages.security.onLead"), style=desk_muted) |> ignore
        if !signs && !flag(me, "waiting") && !flag(me, "unsigned") {
          c.text(
            @sf.t(if flag(lock, "canSign") { "web-pages.security.notSignerApp" } else { "web-pages.security.notSignerWeb" }),
            style=sec_note,
          )
          |> ignore
        }
      })
      |> ignore
    },
  ]
  // not confirmed yet, or in the lock without signing (let in before it kept a key): asked for here too
  if flag(me, "waiting") || flag(me, "unsigned") {
    blocks.push(fn() {
      c.box(style=sec_lead, fn() {
        c.text(
          @sf.t(if flag(me, "unsigned") { "web-pages.security.upgradeTitle" } else { "web-pages.security.waitingTitle" }),
          style=sec_state,
        )
        |> ignore
        pair_steps(c, core, ws)
      })
      |> ignore
    })
  }
  if requests.length() > 0 {
    blocks.push(fn() {
      @sf.section(
        c,
        @sf.t("web-pages.security.waiting"),
        title_after=fn() {
          c.box(style=sec_count, fn() { c.text(requests.length().to_string(), style=sec_count_words) |> ignore }) |> ignore
        },
        fn() {
          c.box(style=desk_card, fn() {
            c.box(style=sec_rows, fn() {
              for r in requests {
                let rv = Some(r)
                c.box(style=sec_row, fn() {
                  c.box(style=sec_row_text, keep=true, fn() {
                    c.text(
                      @sf.t("web-pages.security.newDeviceOf", args=[
                        (
                          "name",
                          match text(rv, "name") {
                            "" => text(rv, "email")
                            n => n
                          },
                        ),
                      ]),
                      style=sec_row_name,
                    )
                    |> ignore
                    // (which device and when, whole or not at all where the row has not the room)
                    c.box(style=sec_meta_slot, drop=sec_drop_meta, fn() {
                      c.text(device_name(text(rv, "kind"), text(rv, "label")) + " · " + stamp(rv, "created_at", "ago"), style=sec_row_state)
                      |> ignore
                    })
                    |> ignore
                  })
                  |> ignore
                  c.box(style=sec_code, fn() { mono(c, text(rv, "code"), style=sec_code_words) }) |> ignore
                  if signs &&
                    @sf.button(c, @sf.t("web-pages.security.check"), key="request/" + text(rv, "device"), tone=Primary) {
                    confirm_dialog(core, ws, r)
                  }
                })
                |> ignore
              }
            })
            |> ignore
          })
          |> ignore
        },
      )
    })
  }
  blocks.push(fn() {
    @sf.section(c, @sf.t("web-pages.security.people"), fn() {
      c.box(style=desk_card, fn() {
        c.box(style=sec_rows, fn() {
          for m in items(lock, "members") {
            let mv = Some(m)
            c.box(style=sec_rows, fn() {
              c.box(style=sec_row, fn() {
                c.box(style=sec_row_text, keep=true, fn() {
                  c.text(
                    match text(mv, "name") {
                      "" => text(mv, "email")
                      n => n
                    },
                    style=sec_row_name,
                  )
                  |> ignore
                  c.text(sec_role(text(mv, "role")), style=sec_row_meta) |> ignore
                })
                |> ignore
              })
              |> ignore
              let devices = items(mv, "devices")
              if devices.length() > 0 {
                c.box(style=sec_devices, fn() {
                  for d in devices {
                    sec_device_row(c, core, ws, d, signs)
                  }
                })
                |> ignore
              }
            })
            |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    })
  })
  blocks.push(fn() {
    @sf.section(c, "Station", fn() {
      c.box(style=desk_card, fn() {
        let stations = items(lock, "stations")
        if stations.length() == 0 {
          c.text(@sf.t("web-pages.security.noStations"), style=desk_muted) |> ignore
        } else {
          c.box(style=sec_rows, fn() {
            for st in stations {
              sec_station_row(c, core, ws, Some(st), flag(lock, "owner") && signs)
            }
          })
          |> ignore
        }
      })
      |> ignore
    })
  })
  blocks.push(fn() {
    @sf.section(c, @sf.t("web-pages.security.webTitle"), fn() {
      c.box(style=desk_card, fn() { c.text(@sf.t("web-pages.security.webRisk"), style=desk_muted) |> ignore }) |> ignore
    })
  })
  if flag(lock, "owner") && signs {
    blocks.push(fn() {
      c.box(style=sec_actions, fn() {
        let off = is_doing(core, ["lock.disable"], [("workspace", ws)])
        if @sf.button(c, @sf.t("web-pages.security.turnOff"), key="lock-off", tone=Danger, busy=off) {
          turn_off_dialog(core, ws, here.name)
        }
      })
      |> ignore
    })
  }
  blocks
}

///|
/// A role as this page names it (roleName).
fn sec_role(role : String) -> String {
  match role {
    "owner" => "Owner"
    "admin" => "Admin"
    "member" => @sf.t("web-pages.roles.member")
    "viewer" => @sf.t("web-pages.security.viewer")
    r => r
  }
}

///|
/// A device in the lock (DeviceRow): its mark (a web page's, an app's), its name, what it is in a line (amber where it
/// is to be renewed soon); 续期 where this device signs.
fn sec_device_row(c : @ui.Ctx, core : Core, ws : String, d : Json, can_renew : Bool) -> Unit {
  let t = @sf.theme()
  let dv = Some(d)
  let id = text(dv, "id")
  let renewing = is_doing(core, ["lock.renew"], [("workspace", ws), ("device", id)])
  let days = if has(dv, "daysLeft") { Some(count(dv, "daysLeft")) } else { None }
  let meta = join(
    [
      @sf.t(if text(dv, "kind") == "web" { "web-pages.security.web" } else { "web-pages.security.app" }),
      if flag(dv, "signs") { @sf.t("web-pages.security.signs") } else { "" },
      if flag(dv, "mine") { @sf.t("web-pages.security.thisDevice") } else { "" },
      match days {
        Some(n) => @sf.t("web-pages.security.daysLeft", args=[("n", n.to_string())])
        None => ""
      },
      if flag(dv, "recent") { @sf.t("web-pages.security.recent") } else { "" },
    ],
    " · ",
  )
  c.box(style=sec_row, fn() {
    @sf.icon(c, if text(dv, "kind") == "web" { "web" } else { "monitor" }, size=sec_device_glyph, color=t.p.muted)
    |> ignore
    c.box(style=sec_row_text, keep=true, fn() {
      c.text(device_name(text(dv, "kind"), text(dv, "label"), older=flag(dv, "older")), style=sec_row_words) |> ignore
      c.text(meta, style=if flag(dv, "renewSoon") { sec_warn } else { sec_row_meta }) |> ignore
    })
    |> ignore
    if days is Some(_) && can_renew &&
      @sf.button(c, @sf.t("web-pages.security.renew"), key="renew/" + id, tone=Ghost, busy=renewing) {
      lock_call(core, ws, "renew", @sf.t("web-pages.security.renew"), [("device", id)], done=@sf.t("web-pages.security.renewed"))
    }
  })
  |> ignore
}

///|
/// A station and whether the lock protects it (StationRow): a dot (green, amber where not), its mark and name and why
/// not; 受保护, or 加入 (the owner's signing device), or 未保护 in amber.
fn sec_station_row(c : @ui.Ctx, core : Core, ws : String, sv : Json?, can : Bool) -> Unit {
  let t = @sf.theme()
  let id = text(sv, "id")
  let guarded = flag(sv, "protected")
  let joining = is_doing(core, ["lock.joinStation"], [("workspace", ws), ("station", id)])
  c.box(style=sec_row, fn() {
    c.box(style=if guarded { sec_dot_on } else { sec_dot_amber }, fn() {  }) |> ignore
    c.box(style=sec_row_text, keep=true, fn() {
      c.box(style=desk_named, fn() {
        if @sf.has_station_mark(text(sv, "emoji"), text(sv, "icon")) {
          @sf.station_mark(c, text(sv, "emoji"), text(sv, "icon"), desk_mark, t.p.text)
        }
        c.text(text(sv, "name"), style=sec_row_name) |> ignore
      })
      |> ignore
      if !guarded {
        c.text(@sf.t("web-pages.security.unprotectedWhy"), style=sec_row_meta) |> ignore
      }
    })
    |> ignore
    if guarded {
      c.text(@sf.t("web-pages.security.protected"), style=sec_row_state) |> ignore
    } else if can {
      if @sf.button(c, @sf.t("web-pages.security.join"), key="lock-station/" + id, tone=Ghost, busy=joining) {
        join_dialog(core, ws, id, text(sv, "name"))
      }
    } else {
      c.text(@sf.t("web-pages.security.unprotected"), style=sec_warn_state) |> ignore
    }
  })
  |> ignore
}

///|
/// A waiting device, confirmed once its code is the one on its screen (Security.tsx ConfirmDevice): who and what it
/// is, its code large, 拒绝 and 确认; gone once answered on another device.
fn confirm_dialog(core : Core, ws : String, r : Json) -> Unit {
  let rv = Some(r)
  let device = text(rv, "device")
  let code = text(rv, "code")
  let who = match text(rv, "name") {
    "" => text(rv, "email")
    n => n
  }
  open_dialog(
    "lock-confirm/" + device,
    @sf.t("web-pages.security.confirmTitle", args=[("name", who)]),
    description=@sf.t("web-pages.security.confirmBody", args=[
      ("device", device_name(text(rv, "kind"), text(rv, "label"))),
      ("name", who),
    ]),
    fn(c, shut) {
      let lock = (core.topic)("lock", { "workspace": str(ws) }).value
      if lock is Some(_) && !items(lock, "requests").iter().any(fn(x) { text(Some(x), "device") == device }) {
        shut()
      }
      c.box(style=sec_big_code_box, fn() { mono(c, code, style=sec_big_code, center=true) }) |> ignore
      let says = if text(rv, "kind") == "web" {
        "web-pages.security.confirmWeb"
      } else {
        "web-pages.security.confirmApp"
      }
      c.text(@sf.t(says), style=sec_note_centred) |> ignore
    },
    fn(c, shut) {
      if @sf.button(c, @sf.t("web-pages.security.deny"), key="lock-deny", tone=Ghost) {
        shut()
        lock_call(core, ws, "deny", @sf.t("web-pages.security.denyDevice"), [("device", device)])
      }
      if @sf.button(c, @sf.t("web-pages.security.confirm"), key="lock-confirm", tone=Primary) {
        shut()
        lock_call(
          core,
          ws,
          "confirm",
          @sf.t("web-pages.security.confirmDevice"),
          [("device", device), ("code", code)],
          done=@sf.t("web-pages.security.confirmed"),
        )
      }
    },
  )
}

///|
/// A station of the workspace not in the lock, taken in once its owner says it is theirs (Security.tsx's join dialog).
fn join_dialog(core : Core, ws : String, station : String, name : String) -> Unit {
  open_dialog(
    "lock-join/" + station,
    @sf.t("web-pages.security.joinTitle", args=[("name", name)]),
    description=@sf.t("web-pages.security.joinBody"),
    fn(_, _) {  },
    fn(c, shut) {
      if @sf.button(c, @sf.t("common.cancel"), key="join-cancel", tone=Ghost) {
        shut()
      }
      if @sf.button(c, @sf.t("web-pages.security.join"), key="join-go", tone=Primary) {
        shut()
        lock_call(
          core,
          ws,
          "joinStation",
          @sf.t("web-pages.security.join"),
          [("station", station)],
          done=@sf.t("web-pages.security.joined", args=[("name", name)]),
        )
      }
    },
  )
}

///|
/// 关闭安全模式？ (Security.tsx TurnOff): what turning it off gives up, a line each, and the workspace's name typed
/// before it can go (`lock.disable`, Enter too); written in as it opens.
fn turn_off_dialog(core : Core, ws : String, name : String) -> Unit {
  let key = "lock-off/" + (desk_dialogs.val + 1).to_string()
  let named = fn() { field_of(key).text().trim(chars=" \t\n").to_owned() == name.trim(chars=" \t\n").to_owned() }
  let typed_in = Ref(false)
  let go = fn(c : @ui.Ctx, shut : () -> Unit) {
    c.blur()
    shut()
    @settings.act(core, @sf.t("web-pages.security.turnOff"), "lock.disable", obj([("workspace", str(ws))]))
  }
  open_dialog(
    key,
    @sf.t("web-pages.security.turnOffTitle"),
    description=@sf.t("web-pages.security.turnOffBody"),
    fn(c, shut) {
      c.box(style=sec_points, fn() {
        sec_off_point(c, "server", @sf.t("web-pages.security.nowRisk"))
        sec_off_point(c, "devices", @sf.t("web-pages.security.turnOffApproval"))
        sec_off_point(c, "key", @sf.t("web-pages.security.turnOffVault"))
      })
      |> ignore
      @sf.field(c, @sf.t("web-pages.security.turnOffType", args=[("name", name)]), fn() {
        if @sf.input(c, key, field=field_of(key)).submitted && named() {
          go(c, shut)
        }
      })
      if !typed_in.val {
        typed_in.val = true
        c.focus_editor(key)
      }
    },
    fn(c, shut) {
      if @sf.button(c, @sf.t("common.cancel"), key="off-cancel", tone=Ghost) {
        c.blur()
        shut()
      }
      if @sf.button(c, @sf.t("web-pages.security.turnOff"), key="off-go", tone=DangerSolid, disabled=!named()) {
        go(c, shut)
      }
    },
  )
}

///|
/// One thing turning it off gives up (Security.css.ts point): its icon, muted, beside a line of it.
fn sec_off_point(c : @ui.Ctx, icon : String, words : String) -> Unit {
  let t = @sf.theme()
  c.box(style=sec_point_line, fn() {
    c.box(style=sec_point_icon, fn() { @sf.icon(c, icon, size=sec_point_glyph, color=t.p.muted) |> ignore }) |> ignore
    c.box(style=sec_point_words, fn() { c.text(words, style=sec_point_text) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// A device's code large (Security.css.ts bigCode: the display size, a line 1.3 of it, 6 apart, 600, 6 over and under).
// kept across runs: a value (no field of it changes)
let sec_big_code_box : @ui.Style = @ui.css("w=Full my=S1_5")

///|
// kept across runs: a value (no field of it changes)
let sec_big_code : @ui.TextStyle = @ui.text_style(
  size=@sf.code_big_size,
  weight=Semibold,
  color=Fg,
  tracking=@sf.code_big_tracking,
  wrap=false,
)

///|
/// A note under it, in the middle (Security.css.ts note, centred).
// kept across runs: a value (no field of it changes)
let sec_note_centred : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, w=Full, center=true)

///|
/// The sizes: what it changes, its marks 18 in a column of 20; a device's mark 16.
let sec_point_glyph : Double = 18.0

///|
let sec_device_glyph : Double = 16.0

///|
let sec_dot_side : Double = 7.0

///|
let sec_row_least : Double = 30.0

///|
/// The state's card, first on the page, as far from what follows as a section is (lead: a card, 28 under it).
// kept across runs: a value (no field of it changes)
let sec_lead : @ui.Style = desk_card.then(@ui.css("mb=S7"))

///|
/// The state (state: the body's 14 in 500; its meta the ui's 13 muted).
// kept across runs: a value (no field of it changes)
let sec_state : @ui.TextStyle = @ui.text_style(size=Base, leading=L7, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sec_state_line : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sec_state_meta : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let sec_note : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let sec_actions : @ui.Style = @ui.css("row gap=S2_5 align=ACenter")

///|
/// What it changes (points: 10 apart; each its mark in a 20 column, 8 from its words, the body's 14).
// kept across runs: a value (no field of it changes)
let sec_points : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let sec_point_line : @ui.Style = @ui.css("row w=Full gap=S2 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let sec_point_icon : @ui.Style = @ui.css("w=S5 pt=SPx align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sec_point_words : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let sec_point_text : @ui.TextStyle = @ui.text_style(size=Base, leading=L7, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let sec_point_rest : @ui.TextStyle = @ui.text_style(size=Base, leading=L7, color=Muted, w=Full)

///|
/// A card's rows (rows: 12 apart; a row 30 high at least, 12 apart, the ui's 13; its words in a line, the name in 500,
/// what it is the meta's 12 muted 6 after it); a person's devices 42 in, 8 apart.
// kept across runs: a value (no field of it changes)
let sec_rows : @ui.Style = @ui.css("w=Full gap=S3")

///|
// kept across runs: a value (no field of it changes)
let sec_row : @ui.Style = @ui.style(row=true, w=Full, min_h=Fixed(sec_row_least), gap=S3, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let sec_row_text : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S1_5, align=AEnd)

///|
// kept across runs: a value (no field of it changes)
let sec_row_name : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sec_row_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sec_row_meta : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, wrap=false, w=Cut)

///|
/// What leaves a waiting device's row first, short of room: which device it is and when it asked; whole on its line.
let sec_drop_meta : Int = 1

///|
// kept across runs: a value (no field of it changes)
let sec_meta_slot : @ui.Style = @ui.css("row")

///|
/// What a row says of itself at its end (受保护): the meta's words, never cut.
// kept across runs: a value (no field of it changes)
let sec_row_state : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sec_warn : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Warn, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let sec_warn_state : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Warn, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sec_devices : @ui.Style = @ui.css("w=Full pl=S10 gap=S2")

///|
/// A short code as the device shows it (code: the code face 14 in 600, 3 by 9 in, 8 round, the words at 6%); the
/// count of those waiting (count: the meta's 12 in 500 on the accent's ground, 7 in, round).
// kept across runs: a value (no field of it changes)
let sec_code : @ui.Style = @ui.css("py=S0_5 px=S2 radius=Lg bg=Tint")

///|
// kept across runs: a value (no field of it changes)
let sec_code_words : @ui.TextStyle = @ui.text_style(size=Base, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sec_count : @ui.Style = @ui.css("px=S1_5 radius=Full bg=AccentBg")

///|
// kept across runs: a value (no field of it changes)
let sec_count_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, weight=Medium, color=AccentText, wrap=false)

///|
/// A station's dot (dot: 7 round, the online green, amber where it is not protected).
// kept across runs: a value (no field of it changes)
let sec_dot_on : @ui.Style = @ui.style(w=Fixed(sec_dot_side), h=Fixed(sec_dot_side), radius=Full, bg=Positive)

///|
// kept across runs: a value (no field of it changes)
let sec_dot_amber : @ui.Style = sec_dot_on.then(@ui.css("bg=Warn"))
