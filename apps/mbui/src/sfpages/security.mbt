// 安全, one page in every frame (web/src/cloud/Security.tsx SecuritySettings, Off, On, StationRow, DeviceRow,
// SecurityOpen; the narrow app's mobile/Security.tsx), laid out by its width (page_look.mbt): what the lock is; off, a
// card of what it is now and once on, and the way to turn it on; on, a card of how many sign and what it protects, this
// device's own pairing where it waits, the devices waiting to be confirmed, its people and their devices, its stations,
// what a web page may do, and turning it off. All of it the core's (`lock`, `lockDraft`, their words included);
// confirming a device, taking a station in and turning it off asked first (the presenters). Turning it on is a page of
// its own (SecurityOpen).

///|
/// 安全 (SecuritySettings, SecurityScreen).
pub fn security_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let topic = (core.topic)("lock", { "workspace": str(here.workspace) })
  let lock = topic.value
  let blocks : Array[() -> Unit] = []
  match lock {
    None =>
      // (read the first time: the page as it is while the lock is off, the commonest, in its bones)
      blocks.push(fn() {
        block_waiting(
          c,
          fn() {
            for b in lock_off(c, core.quiet(), look, Some({ "available": true })) {
              b()
            }
          },
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
  @sf.page(c, on_back=core.pop, frame~, "security", @sf.t("web-pages.security.title"), blocks, lead=@sf.t("web-pages.security.lead"))
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
    Wide => c.box(style=@sf.desk_card, fn() { c.box(style=sec_rows, body) |> ignore }) |> ignore
  }
}

///|
/// A row of a section, going nowhere: `mark` before it, its title, `note` under it (narrow) or after it (wide; amber
/// where `warn`; where `drops`, whole or not at all where the row has not the room), `end` at its end; `acts`, what
/// it does where its title is words of no length known (a device's name): at its end wide, narrow a line of its own
/// under its words, the title never squeezed by it (docs/ui-panels.md 字和别的东西并排时). `over`: the name of the
/// rows it starts, over it at its mark (a person's devices of one app: still.fail 桌面版), `apart` from the rows
/// before it.
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
  acts? : () -> Unit,
  over? : String = "",
  apart? : Bool = false,
) -> Unit {
  match look {
    Narrow => {
      if over != "" {
        c.box(style=sec_narrow_over, fn() { c.text(over, style=sec_narrow_over_words) |> ignore }) |> ignore
      }
      let words = fn() {
        match mark {
          Some(f) => f()
          None => ()
        }
        // its title and what is at its end on its first line, its note under them as wide as its words (a line of its
        // own)
        @sf.row_lines(c, fn() {
          c.box(style=sec_title_room, fn() { c.text(title, style=narrow_row_title) |> ignore }) |> ignore
          // (at the row's top: at a card's first row's end in its corner as far from its top as from its side, and
          // clear of its last's foot corner)
          match end {
            Some(f) => c.box(style=sec_end_top, f) |> ignore
            None => ()
          }
        }, fn() {
          if note != "" {
            c.text(note, style=if warn { sec_narrow_warn } else { @sf.pg_link_note }) |> ignore
          }
        })
      }
      c.box(style=if indent { sec_narrow_row_in } else { @sf.pg_said_row }, fn() {
        match acts {
          None => words()
          // (its mark beside its title and its note as in a row doing nothing, what it does under them all from
          // where its words start)
          Some(f) =>
            c.box(style=sec_with_acts, fn() {
              c.box(style=sec_mark_words, words) |> ignore
              c.box(style=if mark is Some(_) { sec_acts_past_mark } else { sec_acts_under }, f) |> ignore
            })
            |> ignore
        }
      })
      |> ignore
    }
    Wide => {
      if over != "" {
        c.box(style=if apart { sec_over_apart } else { sec_over }, fn() { c.text(over, style=sec_over_words) |> ignore })
        |> ignore
      }
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
        match acts {
          Some(f) => f()
          None => ()
        }
      })
      |> ignore
    }
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
/// waits or was let in without signing; its people and their devices; its stations; what a web page may do; 关闭安全模式.
fn lock_on(c : @ui.Ctx, core : Core, here : Here, look : Look, lock : Json?) -> Array[() -> Unit] {
  let ws = here.workspace
  let signs = flag(lock, "signs")
  let me = field(lock, "me")
  let blocks : Array[() -> Unit] = [
    fn() {
      sec_lead_card(c, look, fn() {
        c.box(style=sec_state_line, fn() {
          c.box(style=sec_dot_on, fn() {  }) |> ignore
          c.text(@sf.t("web-pages.security.on"), style=sec_state) |> ignore
        })
        |> ignore
        // how many sign and what it protects, a line of its own under its state
        c.text(
          @sf.t("web-pages.security.onMeta", args=[
            ("signers", count(lock, "signers").to_string()),
            ("stations", count(lock, "protected").to_string()),
          ]),
          style=sec_state_meta,
        )
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
        pair_steps(c, core, ws, in_card=true)
      })
    })
  }
  blocks.push(fn() {
    @sf.section(c, @sf.t("web-pages.security.people"), heads=true, fn() {
      sec_group(c, look, fn() {
        for m in items(lock, "members") {
          let mv = Some(m)
          let groups = items(mv, "groups")
          let body = fn() {
            match look {
              Narrow => sec_line(c, look, text(mv, "nameText"), end=fn() { sec_end_words(c, look, text(mv, "roleText")) })
              Wide => sec_line(c, look, text(mv, "nameText"), note=text(mv, "roleText"))
            }
            if groups.length() > 0 {
              c.box(style=if look == Wide { sec_devices } else { @sf.full_width }, fn() {
                // by the app each is (still.fail 桌面版), its name over the first: which machine each is
                for i, g in groups {
                  let gv = Some(g)
                  for j, d in items(gv, "devices") {
                    sec_device_row(c, core, look, ws, d, signs, over=if j == 0 { text(gv, "appText") } else { "" }, apart=i > 0)
                  }
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
pub fn sec_section(c : @ui.Ctx, look : Look, title : String, count~ : Int, body : () -> Unit) -> Unit {
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
/// A device in the lock (DeviceRow): its mark (a web page's, an app's), which machine it is (the app `over` the first
/// of its group says), this device or when it was last used and the rest in a line (amber where it is to be renewed
/// soon); 续期 where this device signs, 移除 (asked first) where it may take it out.
fn sec_device_row(
  c : @ui.Ctx,
  core : Core,
  look : Look,
  ws : String,
  d : Json,
  can_renew : Bool,
  over? : String = "",
  apart? : Bool = false,
) -> Unit {
  let t = @sf.theme()
  let dv = Some(d)
  let id = text(dv, "id")
  let renewing = is_doing(core, ["lock.renew"], [("workspace", ws), ("device", id)])
  let removing = is_doing(core, ["lock.removeDevice"], [("workspace", ws), ("device", id)])
  let renews = has(dv, "daysLeft") && can_renew
  let removes = flag(dv, "removable")
  sec_line(
    c,
    look,
    text(dv, "nameText"),
    note=text(dv, "metaText"),
    warn=flag(dv, "renewSoon"),
    strong=false,
    indent=true,
    over~,
    apart~,
    mark=fn() {
      @sf.icon(c, if text(dv, "kind") == "web" { "web" } else { "monitor" }, size=sec_device_glyph, color=t.p.muted)
      |> ignore
    },
    acts?=if renews || removes {
      Some(fn() {
        if renews && sec_do(c, look, "renew/" + id, @sf.t("web-pages.security.renew"), busy=renewing) {
          lock_call(core, ws, "renew", @sf.t("web-pages.security.renew"), [("device", id)], done=@sf.t("web-pages.security.renewed"))
        }
        if removes && sec_do(c, look, "remove/" + id, @sf.t("web-pages.security.remove"), busy=removing) {
          remove_dialog(core, ws, id, text(dv, "fullText"))
        }
      })
    } else {
      None
    },
  )
}

///|
/// 移除「…」？ (Security.tsx's): a device taken out of the lock, said what that means first.
pub fn remove_dialog(core : Core, ws : String, device : String, name : String) -> Unit {
  @sf.confirm(
    @sf.t("web-pages.security.removeTitle", args=[("name", name)]),
    @sf.t("web-pages.security.removeBody"),
    @sf.t("web-pages.security.remove"),
    danger=true,
    fn() {
      lock_call(core, ws, "removeDevice", @sf.t("web-pages.security.remove"), [("device", device)], done=@sf.t("web-pages.security.removed"))
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
pub fn security_open_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let ws = here.workspace
  let topic = (core.topic)("lockDraft", { "workspace": str(ws) })
  let draft = topic.value
  let blocks : Array[() -> Unit] = []
  if draft is None || flag(draft, "loading") {
    blocks.push(fn() {
      block_waiting(
        c,
        fn() {
          for b in open_blocks(c, core.quiet(), look, ws, Some(open_sample())) {
            b()
          }
        },
        error=match topic.error {
          Some(e) => error_text(e)
          None => ""
        },
      )
    })
  } else {
    blocks.append(open_blocks(c, core, look, ws, draft))
  }
  @sf.page(c, on_back=core.pop, frame~, "security-open",
    @sf.t("web-pages.security.openTitle"),
    blocks,
    lead=@sf.t("web-pages.security.openLead"),
  )
}


///|
/// What turning the lock on would sign (`draft`, the core's `lockDraft`): its members, the devices and stations (each
/// ticked in or out), and 签名并开启 at its foot.
fn open_blocks(c : @ui.Ctx, core : Core, look : Look, ws : String, draft : Json?) -> Array[() -> Unit] {
  let blocks : Array[() -> Unit] = []
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
  blocks
}

///|
/// What turning the lock on would sign, made up, for what its page shows while it is read (open_blocks in its bones):
/// three people, two devices, two stations.
fn open_sample() -> Json {
  let line = fn(i : Int, name : Int, note : Int) -> Json {
    {
      "id": Json::string("sample" + i.to_string()),
      "nameText": Json::string(@sf.sample_words(name)),
      "name": Json::string(@sf.sample_words(name)),
      "email": Json::string(@sf.sample_words(note)),
      "howText": Json::string(@sf.sample_words(note)),
      "roleText": Json::string(@sf.sample_words(2)),
    }
  }
  {
    "members": [line(0, 3, 12), line(1, 4, 14), line(2, 3, 10)],
    "devices": [line(3, 6, 9), line(4, 5, 11)],
    "stations": [line(5, 4, 0), line(6, 5, 0)],
  }
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
/// A station of the workspace not in the lock, taken in once its owner says it is theirs (Security.tsx's join dialog).
pub fn join_dialog(core : Core, ws : String, station : String, name : String) -> Unit {
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
pub fn turn_off_dialog(core : Core, ws : String, name : String) -> Unit {
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
let sec_lead : @ui.Style = @sf.desk_card.then(@ui.css("mb=S7"))

///|
/// The state (state: the body's 14 in 500; its meta the ui's 13 muted).
// kept across runs: a value (no field of it changes)
let sec_state : @ui.TextStyle = @ui.text_style(size=Body, leading=L7, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sec_state_line : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sec_state_meta : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let sec_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full)

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
let sec_point_text : @ui.TextStyle = @ui.text_style(size=Body, leading=L7, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let sec_point_rest : @ui.TextStyle = @ui.text_style(size=Meta, leading=L7, color=Muted, w=Full)

///|
/// A card's rows (rows: 12 apart; a row 30 high at least, 12 apart, the ui's 13; its words in a line, the name in 500,
/// what it is the meta's 12 muted 6 after it); a person's devices 42 in, 8 apart.
// kept across runs: a value (no field of it changes)
let sec_rows : @ui.Style = @ui.css("w=Full gap=S3")

///|
/// A narrow row's title, taking what its first line leaves what is at its end.
// kept across runs: a value (no field of it changes)
let sec_title_room : @ui.Style = @ui.style(w=@sf.grow)

///|
/// A narrow row with what it does under it: its mark and its words, then that.
// kept across runs: a value (no field of it changes)
let sec_with_acts : @ui.Style = @ui.style(w=@sf.grow)

///|
/// A narrow row's mark and words over what it does, as a row doing nothing has them.
// kept across runs: a value (no field of it changes)
let sec_mark_words : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
/// What a narrow row does (a device's: 续期, 移除), a line of its own under its words (Security.tsx's mDeviceActs: 6
/// under them, 20 apart).
// kept across runs: a value (no field of it changes)
let sec_acts_under : @ui.Style = @ui.css("row gap=S5 pt=S1_5")

///|
/// The same from where its words start, past its mark (a device's glyph, `sec_device_glyph`, and the row's 12 after it).
// kept across runs: a value (no field of it changes)
let sec_acts_past_mark : @ui.Style = @ui.css("row gap=S5 pt=S1_5 pl=S7")

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
let sec_row_name : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sec_row_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sec_row_meta : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Cut)

///|
/// What leaves a waiting device's row first, short of room: which device it is and when it asked; whole on its line.
let sec_drop_meta : Int = 1

///|
// kept across runs: a value (no field of it changes)
let sec_meta_slot : @ui.Style = @ui.css("row")

///|
/// What a row says of itself at its end (受保护): the meta's words, never cut.
// kept across runs: a value (no field of it changes)
let sec_row_state : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sec_warn : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=WarnInk, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let sec_warn_state : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=WarnInk, wrap=false)

///|
/// A person's devices, 42 in, 8 apart; by app, its name (the meta's 12 in 500, muted, on a line) over the first, a
/// group 14 from the one before it (Security.tsx's devices, deviceGroup, deviceApp).
// kept across runs: a value (no field of it changes)
let sec_devices : @ui.Style = @ui.css("w=Full pl=S10 gap=S2")

///|
// kept across runs: a value (no field of it changes)
let sec_over : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let sec_over_apart : @ui.Style = @ui.css("w=Full pt=S1_5")

///|
// kept across runs: a value (no field of it changes)
let sec_over_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=Muted, wrap=false, w=Cut)

///|
/// The count of those waiting (count: the meta's 12 in 500 on the accent's ground, 7 in, round).
// kept across runs: a value (no field of it changes)
let sec_count : @ui.Style = @ui.css("px=S1_5 radius=Full bg=AccentBg")

///|
// kept across runs: a value (no field of it changes)
let sec_count_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=AccentText, wrap=false)

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
let sec_note_line : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted)

///|
/// Narrow: a person's device under them, further in (Security.tsx's mobile DeviceRow: 14 more); what it is amber where
/// it is to be renewed soon; what a row says at its end (the secondary's, on one line).
// kept across runs: a value (no field of it changes)
let sec_narrow_row_in : @ui.Style = @ui.css("row w=Full pl=S6 pr=S3 py=S2_5 gap=S3 radius=Inner align=ACenter")

///|
/// Narrow: the app a person's devices under it are, at their marks (sec_narrow_row_in's), 6 over the first (Security.tsx's
/// mobile mDeviceApp): the secondary's in 500, on a line.
// kept across runs: a value (no field of it changes)
let sec_narrow_over : @ui.Style = @ui.css("w=Full pl=S6 pr=S3 pt=S1_5")

///|
// kept across runs: a value (no field of it changes)
let sec_narrow_over_words : @ui.TextStyle = @sf.secondary.then(@ui.text_style(weight=Medium, wrap=false, w=Cut))

///|
// kept across runs: a value (no field of it changes)
let sec_narrow_warn : @ui.TextStyle = @sf.pg_link_note.then(@ui.text_style(color=WarnInk))

///|
// kept across runs: a value (no field of it changes)
let sec_narrow_end : @ui.TextStyle = @sf.secondary.then(@sf.one_line)

///|
// kept across runs: a value (no field of it changes)
let sec_narrow_end_warn : @ui.TextStyle = sec_narrow_end.then(@ui.text_style(color=WarnInk))

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
let sec_open_foot_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted)
