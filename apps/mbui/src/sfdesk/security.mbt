// 安全, one page in every frame (web/src/cloud/Security.tsx SecuritySettings, Off, On, StationRow, DeviceRow,
// SecurityOpen; the narrow app's mobile/Security.tsx), laid out by its width (page_look.mbt): what the lock is; off, a
// card of what it is now and once on, and the way to turn it on; on, a card of how many sign and what it protects, this
// device's own pairing where it waits, the devices waiting to be confirmed, its people and their devices, its stations,
// what a web page may do, and turning it off. All of it the core's (`lock`, `lockDraft`, their words included);
// confirming a device, taking a station in and turning it off asked first (the presenters). Turning it on is a page of
// its own (SecurityOpen).

///|
/// 安全 (SecuritySettings, SecurityScreen).
fn security_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let look = look_of(c)
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
      blocks.push(fn() { @sf.page_card(c, fn() { c.text(@sf.t("web-pages.security.unavailable"), style=sec_said) |> ignore }) })
    Some(_) if flag(lock, "locked") => blocks.append(lock_on(c, core, here, look, lock))
    Some(_) => blocks.append(lock_off(c, core, look, lock))
  }
  look_page(c, core, frame, "security", @sf.t("web-pages.security.title"), blocks, lead=@sf.t("web-pages.security.lead"))
}

///|
/// Off (Off): the lock's state, what it is now and once on and how new devices come in, a line each with its mark; the
/// way to turn it on (where this device signs), or who may; 签名 under it.
fn lock_off(c : @ui.Ctx, core : Core, look : Look, lock : Json?) -> Array[() -> Unit] {
  [
    fn() {
      sec_lead_card(c, look, fn() {
        c.box(style=sec_state_line, fn() {
          c.box(style=sec_dot_amber, fn() {  }) |> ignore
          c.text(@sf.t("web-pages.security.off"), style=sec_state) |> ignore
        })
        |> ignore
        c.box(style=sec_points, fn() {
          sec_point(c, "server", @sf.t("web-pages.security.now"), @sf.t("web-pages.security.nowRisk"))
          sec_point(c, "key", @sf.t("web-pages.security.then"), @sf.t("web-pages.security.thenSafe"))
          sec_point(c, "devices", @sf.t("web-pages.security.newDevices"), @sf.t("web-pages.security.newDevicesHow"))
        })
        |> ignore
        if !flag(lock, "owner") {
          c.text(@sf.t("web-pages.security.ownerOnly"), style=sec_note) |> ignore
        } else if flag(lock, "canSign") {
          c.box(style=sec_actions, flow=true, fn() {
            if @sf.button(c, @sf.t("web-pages.security.turnOn"), key="lock-turn-on", tone=Primary) {
              (core.push)(SecurityOpen)
            }
            c.text(@sf.t("web-pages.security.signsHere"), style=sec_note_line) |> ignore
          })
          |> ignore
        } else {
          c.text(@sf.t("web-pages.security.webCannotSign"), style=sec_note) |> ignore
        }
      })
    },
    fn() {
      @sf.section(c, @sf.t("web-pages.security.signing"), heads=true, fn() {
        @sf.page_card(c, fn() { c.text(@sf.t("web-pages.security.signingWho"), style=sec_said) |> ignore })
      })
    },
  ]
}

///|
/// The state's card, first on the page (lead: a card, as far from what follows as a section is).
fn sec_lead_card(c : @ui.Ctx, look : Look, body : () -> Unit) -> Unit {
  match look {
    Narrow => @sf.page_card(c, body)
    Wide => c.box(style=sec_lead, body) |> ignore
  }
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
/// A section's rows together: narrow, on a rounded card (ListCard); wide, on the web's card, 12 apart.
fn sec_group(c : @ui.Ctx, look : Look, body : () -> Unit) -> Unit {
  match look {
    Narrow => @sf.group(c, body)
    Wide => c.box(style=desk_card, fn() { c.box(style=sec_rows, body) |> ignore }) |> ignore
  }
}

///|
/// A row of a section, going nowhere: `mark` before it, its title, `note` under it (narrow) or after it (wide; amber
/// where `warn`; where `drops`, whole or not at all where the row has not the room), `end` at its end.
fn sec_line(
  c : @ui.Ctx,
  look : Look,
  title : String,
  note? : String = "",
  warn? : Bool = false,
  strong? : Bool = true,
  drops? : Bool = false,
  indent? : Bool = false,
  mark? : () -> Unit,
  end? : () -> Unit,
) -> Unit {
  match look {
    Narrow =>
      c.box(style=if indent { sec_narrow_row_in } else { narrow_said_row }, fn() {
        match mark {
          Some(f) => f()
          None => ()
        }
        c.box(style=narrow_row_words, fn() {
          c.text(title, style=narrow_row_title) |> ignore
          if note != "" {
            c.text(note, style=if warn { sec_narrow_warn } else { narrow_link_note }) |> ignore
          }
        })
        |> ignore
        // (at the row's top: at a card's first row's end in its corner as far from its top as from its side, and clear
        // of its last's foot corner)
        match end {
          Some(f) => c.box(style=sec_end_top, f) |> ignore
          None => ()
        }
      })
      |> ignore
    Wide =>
      c.box(style=sec_row, fn() {
        match mark {
          Some(f) => f()
          None => ()
        }
        c.box(style=sec_row_text, keep=true, fn() {
          if title != "" {
            c.text(title, style=if strong { sec_row_name } else { sec_row_words }) |> ignore
          }
          if note != "" {
            let style = if warn { sec_warn } else { sec_row_meta }
            if drops {
              c.box(style=sec_meta_slot, drop=sec_drop_meta, fn() { c.text(note, style=sec_row_state) |> ignore }) |> ignore
            } else {
              c.text(note, style~) |> ignore
            }
          }
        })
        |> ignore
        match end {
          Some(f) => f()
          None => ()
        }
      })
      |> ignore
  }
}

///|
/// What a row does at its end: narrow, words in the link's ink; wide, the web's quiet button (`primary`: its main one).
/// True on the frame it is pressed.
fn sec_do(c : @ui.Ctx, look : Look, key : String, words : String, busy? : Bool = false, primary? : Bool = false) -> Bool {
  match look {
    Narrow =>
      if busy {
        @settings.spinner(c)
        false
      } else {
        tap_text(c, key, words, color=@sf.link_ink())
      }
    Wide => @sf.button(c, words, key~, tone=if primary { Primary } else { Ghost }, busy~)
  }
}

///|
/// What a row says of itself at its end (受保护, a role): quieter, never cut.
fn sec_end_words(c : @ui.Ctx, look : Look, words : String, warn? : Bool = false) -> Unit {
  let style = match (look, warn) {
    (Narrow, false) => sec_narrow_end
    (Narrow, true) => sec_narrow_end_warn
    (Wide, false) => sec_row_state
    (Wide, true) => sec_warn_state
  }
  c.text(words, style~) |> ignore
}

///|
/// On (On): its state with how many sign and what it protects, what that means; this device's own pairing where it
/// waits or was let in without signing; the devices waiting (each with its code, 核对 where this device signs); its
/// people and their devices; its stations; what a web page may do; 关闭安全模式.
fn lock_on(c : @ui.Ctx, core : Core, here : Here, look : Look, lock : Json?) -> Array[() -> Unit] {
  let ws = here.workspace
  let signs = flag(lock, "signs")
  let me = field(lock, "me")
  let requests = items(lock, "requests")
  let blocks : Array[() -> Unit] = [
    fn() {
      sec_lead_card(c, look, fn() {
        c.box(style=sec_state_line, fn() {
          c.box(style=sec_dot_on, fn() {  }) |> ignore
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
        c.text(@sf.t("web-pages.security.onLead"), style=sec_said) |> ignore
        if !signs && !flag(me, "waiting") && !flag(me, "unsigned") {
          c.text(
            @sf.t(if flag(lock, "canSign") { "web-pages.security.notSignerApp" } else { "web-pages.security.notSignerWeb" }),
            style=sec_note,
          )
          |> ignore
        }
      })
    },
  ]
  // not confirmed yet, or in the lock without signing (let in before it kept a key): asked for here too
  if flag(me, "waiting") || flag(me, "unsigned") {
    blocks.push(fn() {
      sec_lead_card(c, look, fn() {
        c.text(
          @sf.t(if flag(me, "unsigned") { "web-pages.security.upgradeTitle" } else { "web-pages.security.waitingTitle" }),
          style=sec_state,
        )
        |> ignore
        @sfpages.pair_steps(c, core, ws, in_card=true)
      })
    })
  }
  if requests.length() > 0 {
    blocks.push(fn() {
      sec_section(c, look, @sf.t("web-pages.security.waiting"), count=requests.length(), fn() {
        sec_group(c, look, fn() {
          for r in requests {
            let rv = Some(r)
            sec_line(
              c,
              look,
              @sf.t("web-pages.security.newDeviceOf", args=[("name", text(rv, "whoText"))]),
              note=text(rv, "deviceText") + " · " + stamp(rv, "created_at", "ago"),
              drops=true,
              end=fn() {
                c.box(style=sec_code, fn() { mono(c, text(rv, "code"), style=sec_code_words) }) |> ignore
                if signs && sec_do(c, look, "request/" + text(rv, "device"), @sf.t("web-pages.security.check"), primary=true) {
                  confirm_dialog(core, ws, r)
                }
              },
            )
          }
        })
      })
    })
  }
  blocks.push(fn() {
    @sf.section(c, @sf.t("web-pages.security.people"), heads=true, fn() {
      sec_group(c, look, fn() {
        for m in items(lock, "members") {
          let mv = Some(m)
          let devices = items(mv, "devices")
          let body = fn() {
            match look {
              Narrow => sec_line(c, look, text(mv, "nameText"), end=fn() { sec_end_words(c, look, text(mv, "roleText")) })
              Wide => sec_line(c, look, text(mv, "nameText"), note=text(mv, "roleText"))
            }
            if devices.length() > 0 {
              c.box(style=if look == Wide { sec_devices } else { @sf.full_width }, fn() {
                for d in devices {
                  sec_device_row(c, core, look, ws, d, signs)
                }
              })
              |> ignore
            }
          }
          match look {
            Narrow => body()
            Wide => c.box(style=sec_rows, body) |> ignore
          }
        }
      })
    })
  })
  blocks.push(fn() {
    @sf.section(c, "Station", heads=true, fn() {
      let stations = items(lock, "stations")
      if stations.length() == 0 {
        @sf.page_card(c, fn() { c.text(@sf.t("web-pages.security.noStations"), style=sec_said) |> ignore })
      } else {
        sec_group(c, look, fn() {
          for st in stations {
            sec_station_row(c, core, look, ws, Some(st), flag(lock, "owner") && signs)
          }
        })
      }
    })
  })
  blocks.push(fn() {
    @sf.section(c, @sf.t("web-pages.security.webTitle"), heads=true, fn() {
      @sf.page_card(c, fn() { c.text(@sf.t("web-pages.security.webRisk"), style=sec_said) |> ignore })
    })
  })
  if flag(lock, "owner") && signs {
    blocks.push(fn() {
      let off = is_doing(core, ["lock.disable"], [("workspace", ws)])
      match look {
        Wide =>
          c.box(style=sec_actions, fn() {
            if @sf.button(c, @sf.t("web-pages.security.turnOff"), key="lock-off", tone=Danger, busy=off) {
              turn_off_dialog(core, ws, here.name)
            }
          })
          |> ignore
        // at the foot, in red, on a card of its own (Security.tsx's mobile On)
        Narrow =>
          c.box(style=acc_narrow_foot, fn() {
            @sf.group(c, fn() {
              let id = c.id("lock-off")
              if !off {
                c.cursor(id, Hand)
              }
              let b = c.box(style=narrow_row, id=if off { 0 } else { id }, fn() {
                c.text(@sf.t("web-pages.security.turnOff"), style=acc_delete_words) |> ignore
                if off {
                  @settings.spinner(c)
                }
                finger_ripple(c, id)
              })
              c.semantics(b, Button, id~, label=@sf.t("web-pages.security.turnOff"), disabled=off)
              if !off && c.clicked(id) {
                turn_off_dialog(core, ws, here.name)
              }
            })
          })
          |> ignore
      }
    })
  }
  blocks
}

///|
/// A section whose title says how many it holds (narrow: after its title, quieter; wide: the accent's count beside it).
fn sec_section(c : @ui.Ctx, look : Look, title : String, count~ : Int, body : () -> Unit) -> Unit {
  match look {
    Narrow => {
      @sf.heading(c, title + " · " + count.to_string())
      body()
    }
    Wide =>
      @sf.section(
        c,
        title,
        title_after=fn() {
          c.box(style=sec_count, fn() { c.text(count.to_string(), style=sec_count_words) |> ignore }) |> ignore
        },
        body,
      )
  }
}

///|
/// A device in the lock (DeviceRow): its mark (a web page's, an app's), its name, what it is in a line (amber where it
/// is to be renewed soon); 续期 where this device signs.
fn sec_device_row(c : @ui.Ctx, core : Core, look : Look, ws : String, d : Json, can_renew : Bool) -> Unit {
  let t = @sf.theme()
  let dv = Some(d)
  let id = text(dv, "id")
  let renewing = is_doing(core, ["lock.renew"], [("workspace", ws), ("device", id)])
  sec_line(
    c,
    look,
    text(dv, "nameText"),
    note=text(dv, "metaText"),
    warn=flag(dv, "renewSoon"),
    strong=false,
    indent=true,
    mark=fn() {
      @sf.icon(c, if text(dv, "kind") == "web" { "web" } else { "monitor" }, size=sec_device_glyph, color=t.p.muted)
      |> ignore
    },
    end=fn() {
      if has(dv, "daysLeft") && can_renew &&
        sec_do(c, look, "renew/" + id, @sf.t("web-pages.security.renew"), busy=renewing) {
        lock_call(core, ws, "renew", @sf.t("web-pages.security.renew"), [("device", id)], done=@sf.t("web-pages.security.renewed"))
      }
    },
  )
}

///|
/// A station and whether the lock protects it (StationRow): a dot (green, amber where not), its mark and name and why
/// not; 受保护, or 加入 (the owner's signing device), or 未保护 in amber.
fn sec_station_row(c : @ui.Ctx, core : Core, look : Look, ws : String, sv : Json?, can : Bool) -> Unit {
  let t = @sf.theme()
  let id = text(sv, "id")
  let guarded = flag(sv, "protected")
  let joining = is_doing(core, ["lock.joinStation"], [("workspace", ws), ("station", id)])
  let name = if look == Wide && @sf.has_station_mark(text(sv, "emoji"), text(sv, "icon")) {
    ""
  } else {
    text(sv, "name")
  }
  sec_line(
    c,
    look,
    name,
    note=if guarded { "" } else { @sf.t("web-pages.security.unprotectedWhy") },
    mark=fn() {
      c.box(style=if guarded { sec_dot_on } else { sec_dot_amber }, fn() {  }) |> ignore
      // (wide: its mark before its name, the two together)
      if name == "" {
        c.box(style=desk_named, fn() {
          @sf.station_mark(c, text(sv, "emoji"), text(sv, "icon"), desk_mark, t.p.text)
          c.text(text(sv, "name"), style=sec_row_name) |> ignore
        })
        |> ignore
      }
    },
    end=fn() {
      if guarded {
        sec_end_words(c, look, @sf.t("web-pages.security.protected"))
      } else if can {
        if sec_do(c, look, "lock-station/" + id, @sf.t("web-pages.security.join"), busy=joining) {
          join_dialog(core, ws, id, text(sv, "name"))
        }
      } else {
        sec_end_words(c, look, @sf.t("web-pages.security.unprotected"), warn=true)
      }
    },
  )
}

///|
/// 开启安全模式 (SecurityOpen, SecurityOpenScreen; the core's `lockDraft`): its members, the devices and stations it
/// would sign (each ticked in or out: `lock.toggle`), then 签名并开启 (`lock.open`); back to 安全 once it is on.
fn security_open_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let ws = here.workspace
  let topic = (core.topic)("lockDraft", { "workspace": str(ws) })
  let draft = topic.value
  let blocks : Array[() -> Unit] = []
  if draft is None || flag(draft, "loading") {
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
    let toggle = fn(id : String) {
      @settings.act(core, @sf.t("web-pages.security.turnOn"), "lock.toggle", obj([("workspace", str(ws)), ("id", str(id))]))
    }
    let members = items(draft, "members")
    blocks.push(fn() {
      @sf.section(c, @sf.t("web-pages.security.members"),
        heads=true,
        note=@sf.t("web-pages.security.peopleCount", args=[("n", members.length().to_string())]),
        fn() {
          sec_group(c, look, fn() {
            for m in members {
              let mv = Some(m)
              sec_line(c, look, text(mv, "nameText"), note=text(mv, "email"), end=fn() { sec_end_words(c, look, text(mv, "roleText")) })
            }
          })
        },
      )
    })
    blocks.push(fn() {
      @sf.section(c, @sf.t("web-pages.security.devices"), heads=true, note=@sf.t("web-pages.security.devicesWhich"), fn() {
        sec_group(c, look, fn() {
          for d in items(draft, "devices") {
            let dv = Some(d)
            sec_check_line(c, look, "draft-device/" + text(dv, "id"), text(dv, "nameText"), text(dv, "howText"), dv, fn() {
              toggle(text(dv, "id"))
            })
          }
        })
      })
    })
    blocks.push(fn() {
      @sf.section(c, "Station", heads=true, fn() {
        sec_group(c, look, fn() {
          for st in items(draft, "stations") {
            let sv = Some(st)
            let note = match (text(sv, "stateText"), text(sv, "version")) {
              ("", v) => v
              (why, "") => why
              (why, v) => why + " · " + v
            }
            sec_check_line(c, look, "draft-station/" + text(sv, "id"), text(sv, "name"), note, sv, fn() { toggle(text(sv, "id")) })
          }
        })
        @sf.page_note(c, @sf.t("web-pages.security.unprotectedNote"))
      })
    })
    // what signing it means for a web page, cancel, 签名并开启 (foot)
    blocks.push(fn() {
      c.box(style=if look == Wide { sec_open_foot } else { sec_open_foot_narrow }, flow=true, fn() {
        c.text(
          @sf.t(if flag(draft, "canSign") { "web-pages.security.webExpiry" } else { "web-pages.security.webCannotSign" }),
          style=sec_open_foot_note,
        )
        |> ignore
        c.box(style=sec_actions, fn() {
          if @sf.button(c, @sf.t("common.cancel"), key="lock-open-cancel", tone=Ghost) {
            (core.pop)()
          }
          let opening = is_doing(core, ["lock.open"], [("workspace", ws)])
          if @sf.button(
              c,
              @sf.t("web-pages.security.signAndTurnOn"),
              key="lock-open",
              tone=Primary,
              busy=opening,
              disabled=!(flag(draft, "ready") && flag(draft, "owner") && flag(draft, "canSign")),
            ) {
            @settings.act(
              core,
              @sf.t("web-pages.security.turnOn"),
              "lock.open",
              obj([("workspace", str(ws))]),
              done=@sf.t("web-pages.security.turnedOn"),
              then=fn(_) { (core.pop)() },
            )
          }
        })
        |> ignore
      })
      |> ignore
    })
  }
  look_page(c, core, frame, "security-open",
    @sf.t("web-pages.security.openTitle"),
    blocks,
    lead=@sf.t("web-pages.security.openLead"),
  )
}

///|
/// A row ticked in or out (SecurityOpen's label with its checkbox): the box, its title and what it is under it (narrow)
/// or after it (wide); fixed ones can't be changed. `toggle` goes on when it is pressed.
fn sec_check_line(c : @ui.Ctx, look : Look, key : String, title : String, note : String, v : Json?, toggle : () -> Unit) -> Unit {
  sec_line(c, look, title, note~, mark=fn() {
    let on = flag(v, "on")
    let now = @kit.checkbox(c, key, if on { On } else { Off }, label=title, disabled=flag(v, "fixed")).value
    if (now == On) != on {
      toggle()
    }
  })
}

///|
/// A waiting device, confirmed once its code is the one on its screen (Security.tsx ConfirmDevice): who and what it
/// is, its code large, 拒绝 and 确认; gone once answered on another device.
fn confirm_dialog(core : Core, ws : String, r : Json) -> Unit {
  let rv = Some(r)
  let device = text(rv, "device")
  let code = text(rv, "code")
  let who = text(rv, "whoText")
  open_dialog(
    @sf.t("web-pages.security.confirmTitle", args=[("name", who)]),
    description=@sf.t("web-pages.security.confirmBody", args=[
      ("device", text(rv, "deviceText")),
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
  @sf.confirm(
    @sf.t("web-pages.security.joinTitle", args=[("name", name)]),
    @sf.t("web-pages.security.joinBody"),
    @sf.t("web-pages.security.join"),
    fn() {
      lock_call(
        core,
        ws,
        "joinStation",
        @sf.t("web-pages.security.join"),
        [("station", station)],
        done=@sf.t("web-pages.security.joined", args=[("name", name)]),
      )
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
/// What a narrow row has at its end, at its top.
// kept across runs: a value (no field of it changes)
let sec_end_top : @ui.Style = @ui.css("row h=Full gap=S2 align=AStart")

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
/// A short code as the device shows it (code: the code face 14 in 600, 9 in, as tall as a row (so at a card's first or
/// last row's end, in its corner, as far from its top or foot as from its side), 8 round, the words at 6%); the count of
/// those waiting (count: the meta's 12 in 500 on the accent's ground, 7 in, round).
// kept across runs: a value (no field of it changes)
let sec_code : @ui.Style = @ui.css("px=S2 radius=Lg bg=Tint justify=JCenter").then(@ui.style(h=Fixed(sec_row_least)))

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

///|
/// A card's words (the web's sub: the ui's 13, muted).
// kept across runs: a value (no field of it changes)
let sec_said : @ui.TextStyle = desk_muted

///|
/// A note beside a button, as wide as it is (the row goes on under where it has not the room).
// kept across runs: a value (no field of it changes)
let sec_note_line : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted)

///|
/// Narrow: a person's device under them, further in (Security.tsx's mobile DeviceRow: 14 more); what it is amber where
/// it is to be renewed soon; what a row says at its end (the secondary's, on one line).
// kept across runs: a value (no field of it changes)
let sec_narrow_row_in : @ui.Style = @ui.css("row w=Full pl=S6 pr=S3 py=S2_5 gap=S3 radius=Inner align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sec_narrow_warn : @ui.TextStyle = narrow_link_note.then(@ui.text_style(color=Warn))

///|
// kept across runs: a value (no field of it changes)
let sec_narrow_end : @ui.TextStyle = @sf.secondary.then(@sf.one_line)

///|
// kept across runs: a value (no field of it changes)
let sec_narrow_end_warn : @ui.TextStyle = sec_narrow_end.then(@ui.text_style(color=Warn))

///|
/// 开启安全模式's foot (foot: what signing means for a web page, then cancel and 签名并开启; narrow, 16 from the page's
/// sides, 4 in its room).
// kept across runs: a value (no field of it changes)
let sec_open_foot : @ui.Style = @ui.css("row w=Full pt=S5 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sec_open_foot_narrow : @ui.Style = @ui.css("row w=Full px=S1 pt=S4 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sec_open_foot_note : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted)
