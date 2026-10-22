// How a chat's agent runs, changed on a page of its own (History.kt RunSettingsScreen), the machine's own sessions to
// go on with (NewChat.kt MachineSessionsOffer, openMachineSessions, lookAtMachineSession), and adding people to the
// workspace (Settings.kt AddSheet) with the workspace's mark.

///|
/// How an agent runs (RunSettingsScreen): what it is now and what it becomes, the changes marked (and why its account
/// must change, when it must); then the model, how hard it thinks, how fast and who runs it, each picked in the core's
/// `pick` of `session:<key>` (`pick.set`); the button says what it becomes (不变 when nothing changed) and saves
/// (`pick.save`), or, another station's model, borrows it once asked again.
fn run_settings_page(c : @ui.Ctx, core : Core, station : String, key : String) -> Unit {
  let t = @sf.theme()
  let of = "session:" + key
  let topic = (core.topic)("pick", { "station": str(station), "of": str(of) })
  let v = topic.value
  let pick = fn(more : Array[(String, Json)]) {
    let p = [("station", str(station)), ("of", str(of))]
    for x in more {
      p.push(x)
    }
    (core.call)("pick.set", obj(p), fn(r) {
      match r {
        Ok(_) => ()
        Err(e) => (core.say)(fill("android-chat.pick.failed", [("error", error_text(e))]))
      }
    })
  }
  // picked from what it runs on now, each time it is opened
  if !run_opened.contains(of) {
    run_opened[of] = true
    pick([("open", Json::boolean(true))])
  }
  let list = run_list.get(of).unwrap_or("")
  let runtime = text(field(v, "value"), "runtime")
  let draft = field(v, "draft")
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    let title = match list {
      "model" => tr("android-chat.pick.model")
      "account" => tr("android-chat.run.account.choose")
      _ => tr("android-chat.run.title")
    }
    if list != "" {
      nav_bar(c, core, tr("android-chat.run.title"), title, on_back=fn() { run_list.remove(of) })
      c.on_back(fn() { run_list.remove(of) })
    } else {
      nav_bar(c, core, tr("common.back"), title)
    }
    guard v is Some(Object(_)) else {
      waiting_cards(
        c,
        error=match topic.error {
          Some(e) => error_text(e)
          None => ""
        },
      )
      return
    }
    if list == "model" {
      // every model it can move to (SettingParts.kt ModelList)
      model_list(c, "run-session-models/" + key, items(v, "options"), runtime, text(v, "option"), fn(m) {
        pick([("model", str(m))])
        run_list.remove(of)
      })
      return
    }
    if list == "account" {
      scroll_page(c, "run-session-accounts/" + key, [
        fn() {
          if pick_row(c, "session-account/auto", tr("android-settings.connect.autoAccount"), checked=!has(draft, "profile")) {
            pick([("profile", Json::null())])
            run_list.remove(of)
          }
          for a in items(v, "accounts") {
            let av = Some(a)
            if pick_row(c, "session-account/" + text(av, "id"), text(av, "name"), sub=text(av, "line"), checked=text(draft, "profile") == text(av, "id")) {
              pick([("profile", str(text(av, "id")))])
              run_list.remove(of)
            }
          }
        },
      ])
      return
    }
    let group = fn(words : String) {
      c.box(w=Fill(1.0), pl=6.0, pt=16.0, pb=6.0, fn() {
        c.text(words, size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
      })
      |> ignore
    }
    // as wide as their words, in lines when they do not fit one (History.kt EffortChips: a FlowRow, 8 apart each way;
    // 16 and 9 in, Smooth(18), the one picked on the ink in semibold)
    let chips = fn(k : String, options : Array[String], chosen : String, run : (String) -> Unit) {
      c.box(style=run_chips, flow=true, fn() {
        for o in options {
          let on = o == chosen
          let id = c.id(k + "/" + o)
          if hit(c, id) {
            run(o)
          }
          c.box(padx=chip_px, pady=chip_py, radius=chip_corner, bg=if on { t.p.text } else { t.p.chip }, id~, fn() {
            c.text(o, size=14.0, weight=if on { 600 } else { 400 }, color=if on { t.p.bg } else { t.p.text }, wrap=false)
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    }
    let setting_row = fn(k : String, body : () -> Unit) {
      let rid = c.id(k)
      let tapped = hit(c, rid)
      c.box(dir=Row, w=Fill(1.0), padx=14.0, pady=12.0, gap=12.0, radius=14.0, bg=t.p.card, align=ACenter, id=rid, fn() {
        body()
        chevron(c)
      })
      |> ignore
      tapped
    }
    let fast = flag(v, "fastAvailable")
    c.box(w=Fill(1.0), h=Fill(1.0), padx=18.0, fn() {
      scroll_page(c, "run-session/" + key, [
        fn() {
          // what it was and what it becomes, a line each property, the changes marked
          c.box(w=Fill(1.0), pt=8.0, fn() {
            c.box(w=Fill(1.0), pad=14.0, gap=6.0, radius=14.0, bg=t.p.chip, fn() {
              let labels = [tr("android-chat.run.label.model"), tr("android-chat.run.label.effort"), tr("android-chat.run.label.account")]
              if fast {
                labels.push(tr("android-chat.run.label.speed"))
              }
              let was = strings(v, "was")
              let becomes = strings(v, "becomes")
              for i, label in labels {
                let w = was.get(i).unwrap_or("")
                let b = becomes.get(i).unwrap_or("")
                let moved = b != w
                c.box(dir=Row, w=Fill(1.0), gap=8.0, align=ACenter, fn() {
                  c.box(w=Px(32.0), fn() { c.text(label, size=13.0, color=t.p.muted, wrap=false) |> ignore }) |> ignore
                  c.text(w, size=14.0, color=if moved { t.p.muted } else { t.p.text }, wrap=false) |> ignore
                  if moved {
                    @sf.icon(c, "arrow-right", size=14.0, color=t.p.accent) |> ignore
                    c.text(b, size=14.0, weight=600, color=@sf.link_ink(), wrap=false, w=Fill(1.0)) |> ignore
                  }
                })
                |> ignore
              }
              match opt_text(v, "force") {
                Some(f) => c.text(f, size=12.0, color=t.p.warn_ink, w=Fill(1.0), line=17.0) |> ignore
                None => ()
              }
              c.text(tr("android-chat.run.next"), size=12.0, color=t.p.subtle, w=Fill(1.0), line=17.0) |> ignore
            })
            |> ignore
          })
          |> ignore
        },
        fn() {
          group(tr("android-chat.run.label.model"))
          if setting_row("session-run-model", fn() {
              @sf.maker_mark(c, text(field(v, "maker"), "id"), runtime, 18.0) |> ignore
              row_title(c, text(v, "modelText"))
            }) {
            run_list[of] = "model"
          }
        },
        fn() {
          group(tr("android-chat.run.effort.title"))
          c.box(w=Fill(1.0), pb=8.0, fn() {
            c.text(tr("android-chat.run.effort.note"), size=12.0, color=t.p.muted, w=Fill(1.0), line=17.0) |> ignore
          })
          |> ignore
          let default = tr("android-chat.pick.default")
          chips("session-effort", [default] + strings(v, "efforts"), match text(draft, "effort") {
            "" => default
            e => e
          }, fn(e) { pick([("effort", if e == default { Json::null() } else { str(e) })]) })
        },
        fn() {
          if fast {
            group(tr("android-chat.run.label.speed"))
            c.box(w=Fill(1.0), pb=8.0, fn() {
              c.text(tr("android-chat.run.speed.note"), size=12.0, color=t.p.muted, w=Fill(1.0), line=17.0) |> ignore
            })
            |> ignore
            let as_plan = tr("android-chat.pick.speed.follow")
            let standard = tr("android-chat.pick.speed.standard")
            chips("session-speed", [as_plan, standard, "Fast"], match field(draft, "fast") {
              Some(True) => "Fast"
              Some(False) => standard
              _ => as_plan
            }, fn(s) {
              pick([("fast", if s == "Fast" { Json::boolean(true) } else if s == standard { Json::boolean(false) } else { Json::null() })])
            })
          }
        },
        fn() {
          group(tr("android-chat.run.label.account"))
          if setting_row("session-run-account", fn() {
              c.box(w=Fill(1.0), fn() {
                c.text(text(v, "accountText"), size=15.0, color=t.p.text, wrap=false, w=Fill(1.0), line=21.0) |> ignore
                c.text(text(v, "accountNote"), size=12.0, color=t.p.muted, w=Fill(1.0), line=17.0) |> ignore
                if flag(v, "accountWarn") {
                  c.text(tr("android-chat.run.account.warn"), size=12.0, color=t.p.warn_ink, w=Fill(1.0), line=17.0) |> ignore
                }
              })
              |> ignore
            }) {
            run_list[of] = "account"
          }
          gap(c, 16.0)
        },
      ])
    })
    |> ignore
    // the model picked is another station's: said so over the button, which borrows it (asked again)
    match field(v, "borrow") {
      Some(Object(_)) as b => {
        let allowed = flag(b, "allowed")
        c.box(w=Fill(1.0), pl=22.0, pr=22.0, pt=8.0, fn() {
          c.text(if allowed { text(b, "note") } else { opt_text(b, "why").unwrap_or(text(b, "note")) }, size=12.0, color=t.p.muted, w=Fill(1.0), line=17.0)
          |> ignore
        })
        |> ignore
        c.box(w=Fill(1.0), padx=18.0, pady=12.0, fn() {
          if wide_button(c, "session-borrow", text(b, "action"), allowed, busy=is_doing(core, ["pick.borrow"], [("station", station), ("of", of)]), enabled=allowed) {
            confirm_borrow(core, station, of, b)
          }
        })
        |> ignore
      }
      _ => {
        let busy = is_doing(core, ["pick.save"], [("station", station), ("of", of)])
        let changed = flag(v, "changed")
        let go = changed && has(v, "option") && !busy
        c.box(w=Fill(1.0), padx=18.0, pady=12.0, fn() {
          if wide_button(c, "session-save", text(v, "saveText"), changed, busy~) {
            // back at once, not waiting on the station; failed, a toast says why
            (core.pop)()
            if go {
              (core.call)("pick.save", obj([("station", str(station)), ("of", str(of))]), fn(r) {
                match r {
                  Ok(_) => (core.say)(tr("android-chat.run.saved"))
                  Err(e) => (core.say)(fill("android-chat.save.failed", [("error", error_text(e))]))
                }
              })
            }
          }
        })
        |> ignore
      }
    }
  })
  |> ignore
}

// ---------------------------------------------------------------------------
// The machine's own sessions (web/src/MachineSessions.tsx)

///|
/// The sessions a station's machine kept (by station), as `machineSessions.list` answered; asked once a page.
let machine_sessions : Map[String, Array[Json]] = Map([])

///|
/// The offer, where the station's machine kept sessions of its own Claude Code or Codex (MachineSessionsOffer): a
/// quiet line; its list and a look at one before going on with it are sheets. Drawn by a new chat's page (sfapp).
pub fn machine_sessions_offer(c : @ui.Ctx, core : Core, station : String, name : String) -> Unit {
  let t = @sf.theme()
  if !machine_sessions.contains(station) {
    machine_sessions[station] = []
    // (asked once the frame's builds are over: the build that first comes to it alone)
    c.tell("machineSessions.list/" + station, fn() {
      (core.call)("machineSessions.list", obj([("station", str(station))]), fn(r) {
        match r {
          Ok(v) => machine_sessions[station] = items(Some(v), "sessions")
          Err(_) => ()
        }
      })
    })
  }
  let sessions = machine_sessions.get(station).unwrap_or([])
  if sessions.length() == 0 {
    return
  }
  let id = c.id("machine-offer/" + station)
  if hit(c, id) {
    open_machine_sessions(core, station, name)
  }
  c.box(pt=8.0, fn() {
    c.box(dir=Row, padx=10.0, pady=6.0, gap=6.0, radius=10.0, align=ACenter, bg=if c.pressed(id) { @sf.alpha(t.p.text, 0.06) } else { 0L }, id~, fn() {
      @sf.icon(c, "monitor", size=14.0, color=t.p.muted) |> ignore
      c.text(
        fill("android-chat.new.machine.offer", [("station", if name == "" { tr("android-chat.new.machine.here") } else { name })]),
        size=14.0,
        color=t.p.muted,
        wrap=false,
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The machine's sessions in a sheet (openMachineSessions), each a look at it before going on with it.
pub fn open_machine_sessions(_core : Core, station : String, name : String) -> Unit {
  let shown = if name == "" { tr("android-chat.new.machine.here") } else { name }
  open_sheet(0.7, fn(c, core) {
    let t = @sf.theme()
    sheet_head(c, fill("android-chat.new.machine.title", [("station", shown)]))
    c.box(w=Fill(1.0), pl=20.0, pr=20.0, pb=8.0, fn() {
      c.text(tr("android-chat.new.machine.text"), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
    })
    |> ignore
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      scroll_page(c, "machine-sessions/" + station, [
        fn() {
          for s in machine_sessions.get(station).unwrap_or([]) {
            let sv = Some(s)
            let id = c.id("machine-session/" + text(sv, "id"))
            if hit(c, id) {
              look_at_machine_session(core, station, name, s)
            }
            c.box(dir=Row, w=Fill(1.0), padx=20.0, pady=10.0, gap=12.0, align=ACenter, bg=if c.pressed(id) { @sf.alpha(t.p.text, 0.05) } else { 0L }, id~, fn() {
              @sf.maker_mark(c, "", text(sv, "runtime"), 18.0) |> ignore
              c.box(w=Fill(1.0), fn() {
                c.text(first_text(sv, ["title", "first"], ""), size=15.0, color=t.p.text, wrap=false, w=Fill(1.0), line=21.0) |> ignore
                c.text(text(sv, "meta"), size=12.0, color=t.p.muted, wrap=false, w=Fill(1.0), line=17.0) |> ignore
              })
              |> ignore
              if has(sv, "session") {
                c.text(fill("android-chat.new.machine.inApp", [("app", "still.fail")]), size=12.0, color=t.p.muted, wrap=false) |> ignore
              }
            })
            |> ignore
          }
          gap(c, 24.0)
        },
      ])
    })
    |> ignore
  })
}

///|
/// One of them looked at before going on with it (lookAtMachineSession): what was said in it, the latest at the bottom
/// (`machineSessions.read`); 继续 makes the chat that goes on with it (`machineSessions.continue`) and opens it.
fn look_at_machine_session(core : Core, station : String, name : String, s : Json) -> Unit {
  let sv = Some(s)
  let said : Ref[(Array[Json], Int)?] = Ref(None)
  let error : Ref[String] = Ref("")
  (core.call)("machineSessions.read", obj([("station", str(station)), ("runtime", str(text(sv, "runtime"))), ("id", str(text(sv, "id"))), ("limit", Json::number(200.0))]), fn(r) {
    match r {
      Ok(v) => {
        let list = items(Some(v), "said")
        said.val = Some((list, if has(Some(v), "total") { count(Some(v), "total") } else { list.length() }))
      }
      Err(e) => error.val = error_text(e)
    }
  })
  open_sheet(0.85, fn(c, core) {
    let t = @sf.theme()
    sheet_head(c, first_text(sv, ["title", "first"], ""))
    c.box(w=Fill(1.0), pl=18.0, pr=18.0, pb=8.0, fn() {
      c.text(text(sv, "meta"), size=12.0, color=t.p.muted, wrap=false, w=Fill(1.0), line=17.0) |> ignore
    })
    |> ignore
    c.box(w=Fill(1.0), h=Fill(1.0), padx=16.0, fn() {
      match said.val {
        None =>
          if error.val == "" {
            c.box(w=Fill(1.0), pt=40.0, align=ACenter, fn() { wait_line(c, tr("common.reading")) }) |> ignore
          }
        Some((list, total)) => {
          let blocks : Array[() -> Unit] = []
          let left = total - list.length()
          if left > 0 {
            blocks.push(fn() {
              c.text(fill("android-chat.new.machine.more", [("n", left.to_string())]), size=12.0, color=t.p.muted, center=true, w=Fill(1.0), line=17.0)
              |> ignore
            })
          }
          let runtime = text(sv, "runtime")
          let model = match text(sv, "model") {
            "" => runtime_label(runtime)
            m => m
          }
          for i, m in list {
            let mv = Some(m)
            blocks.push(fn() {
              c.box(w=Fill(1.0), pb=18.0, fn() {
                if flag(mv, "person") {
                  c.box(dir=Row, w=Fill(1.0), justify=JEnd, fn() {
                    c.box(max_w=300.0, padx=14.0, pady=9.0, radius=18.0, bg=t.p.chip, fn() {
                      c.text(text(mv, "text"), size=15.0, color=t.p.text, line=21.0) |> ignore
                    })
                    |> ignore
                  })
                  |> ignore
                } else {
                  c.box(w=Fill(1.0), gap=4.0, fn() {
                    c.box(dir=Row, gap=6.0, align=ACenter, fn() {
                      @sf.maker_mark(c, "", runtime, 16.0) |> ignore
                      c.text(model, size=13.0, weight=600, color=t.p.text, wrap=false) |> ignore
                    })
                    |> ignore
                    @sf.markdown(c, text(mv, "text"), key="machine-said/" + i.to_string()) |> ignore
                  })
                  |> ignore
                }
              })
              |> ignore
            })
          }
          let k = "machine-said/" + text(sv, "id")
          c.list(k, blocks.length(), 120.0, stick_end=true, fn(i) { (blocks[i])() }) |> ignore
        }
      }
    })
    |> ignore
    if error.val != "" {
      c.box(w=Fill(1.0), padx=20.0, pady=6.0, fn() {
        c.text(error.val, size=13.0, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore
      })
      |> ignore
    }
    let busy = is_doing(core, ["machineSessions.continue"], [("station", station), ("id", text(sv, "id"))])
    c.box(dir=Row, w=Fill(1.0), pl=20.0, pr=20.0, pt=10.0, pb=24.0, gap=8.0, justify=JEnd, fn() {
      if button(c, "machine-back", tr("common.back"), false) {
        open_machine_sessions(core, station, name)
      }
      if button(c, "machine-go", tr(if has(sv, "session") { "android-chat.new.machine.open" } else { "android-chat.new.machine.continue" }), true, busy~) {
        error.val = ""
        (core.call)("machineSessions.continue", obj([("station", str(station)), ("runtime", str(text(sv, "runtime"))), ("id", str(text(sv, "id")))]), fn(r) {
          match r {
            Ok(v) => {
              close_sheet()
              (core.pop)()
              (core.open_chat)(station, text(Some(v), "key"), first_text(sv, ["title", "first"], ""))
            }
            Err(e) => error.val = error_text(e)
          }
        })
      }
    })
    |> ignore
  })
}

// ---------------------------------------------------------------------------
// Adding people (Settings.kt AddSheet) and the workspace's mark

///|
/// The emails in what was typed or pasted (parseEmails): each once, lowercased.
fn parse_emails(words : String) -> Array[String] {
  let out : Array[String] = []
  let stop = fn(ch : Char) { ch == ' ' || ch == '\n' || ch == '\t' || ch == ',' || ch == ';' || ch == '<' || ch == '>' || ch == '"' || ch == '\'' || ch == '(' || ch == ')' || ch == '，' || ch == '；' }
  let b = StringBuilder()
  let flush = fn() {
    let w = b.to_string()
    b.reset()
    match w.find("@") {
      Some(at) if at > 0 && w.unsafe_substring(start=at + 1, end=w.length()).contains(".") => {
        let e = w.to_lower()
        if !out.contains(e) && !e.has_suffix(".") {
          out.push(e)
        }
      }
      _ => ()
    }
  }
  for ch in words {
    if stop(ch) {
      flush()
    } else {
      b.write_char(ch)
    }
  }
  flush()
  out
}

///|
/// A role's line in the adding sheet (ROLE_HINT: "android-misc.role.member.hint" "android-misc.role.admin.hint"
/// "android-misc.role.owner.hint").
fn role_hint(role : String) -> String {
  tr("android-misc.role." + role + ".hint")
}

///|
/// Adding people by email (AddSheet): no invitation to accept, members at once when they have signed in to still.fail
/// before, from their first sign-in otherwise (`workspace.addMembers`). Typed or pasted, or picked from the people of
/// the Slack workspaces the online stations are in (`slack.people`); their role; what came of it said.
fn open_add_people(_core : Core, here : Here, view : Json?) -> Unit {
  vault_serial.val += 1
  let key = "add-people/" + vault_serial.val.to_string()
  let role : Ref[String] = Ref("member")
  let error : Ref[String] = Ref("")
  let done : Ref[String] = Ref("")
  let people : Ref[Array[Json]?] = Ref(None)
  let problems : Array[String] = []
  let reading : Ref[Int] = Ref(0)
  let picked : Array[String] = []
  let inside : Array[String] = []
  for m in items(view, "members") {
    inside.push(text(Some(m), "email").to_lower())
  }
  for a in items(view, "added") {
    inside.push(text(Some(a), "email").to_lower())
  }
  let roles = if text(view, "role") == "owner" { ["member", "admin", "owner"] } else { ["member", "admin"] }
  open_sheet(0.8, fn(c, core) {
    let t = @sf.theme()
    let online = online_stations(core, here)
    sheet_head(c, tr("android-settings.add.title"))
    if done.val != "" {
      c.box(w=Fill(1.0), padx=20.0, gap=10.0, fn() {
        c.text(done.val, size=14.0, color=t.p.text, w=Fill(1.0), line=20.0) |> ignore
        c.box(dir=Row, w=Fill(1.0), pb=24.0, justify=JEnd, fn() {
          if button(c, "add-people-done", tr("common.done"), true) {
            close_sheet()
          }
        })
        |> ignore
      })
      |> ignore
      return
    }
    let mut typed = ""
    let blocks : Array[() -> Unit] = [
      fn() {
        c.text(fill("android-settings.add.note", [("name", text(view, "name")), ("app", "still.fail")]), size=14.0, color=t.p.muted, w=Fill(1.0), line=20.0)
        |> ignore
      },
      fn() {
        c.text(tr("android-settings.add.emails"), size=13.0, weight=600, color=t.p.text, w=Fill(1.0), line=18.0) |> ignore
        c.box(w=Fill(1.0), pt=6.0, fn() {
          c.box(w=Fill(1.0), padx=12.0, pady=10.0, radius=12.0, bg=t.p.card, border=1.0, border_color=t.p.line, fn() {
            typed = c.editor(
              key,
              field=field_of(key),
              placeholder=tr("android-settings.add.emailsPlaceholder"),
              font_size=15.0,
              max_lines=3,
              plain=true,
              line=21.0,
              color=t.p.text,
              placeholder_color=t.p.subtle,
              caret_color=t.p.accent,
              enter_sends=false,
            ).text
          })
          |> ignore
        })
        |> ignore
      },
    ]
    if online.length() > 0 {
      match people.val {
        None =>
          blocks.push(fn() {
            c.box(dir=Row, fn() {
              if button(c, "add-from-slack", tr("android-settings.add.fromSlack"), false, busy=reading.val > 0) {
                reading.val = online.length()
                let seen : Map[String, Json] = Map([])
                for s in online {
                  (core.call)("slack.people", obj([("station", str(text(Some(s), "station")))]), fn(r) {
                    match r {
                      Ok(v) => {
                        for p in items(Some(v), "people") {
                          let e = text(Some(p), "email")
                          if !seen.contains(e) {
                            seen[e] = p
                          }
                        }
                        for e in strings(Some(v), "errors") {
                          problems.push(e)
                        }
                      }
                      Err(e) => problems.push(error_text(e))
                    }
                    reading.val -= 1
                    if reading.val == 0 {
                      let all = seen.values().collect()
                      all.sort_by(fn(a, b) {
                        let ga = flag(Some(a), "guest")
                        let gb = flag(Some(b), "guest")
                        if ga != gb {
                          if ga { 1 } else { -1 }
                        } else {
                          text(Some(a), "name").compare(text(Some(b), "name"))
                        }
                      })
                      people.val = Some(all)
                      // once read, the workspace's own Slack people are picked; guests are left to choose
                      for p in all {
                        let e = text(Some(p), "email")
                        if !flag(Some(p), "guest") && !inside.contains(e) && !picked.contains(e) {
                          picked.push(e)
                        }
                      }
                    }
                  })
                }
              }
            })
            |> ignore
          })
        Some(list) => {
          blocks.push(fn() {
            c.box(dir=Row, w=Fill(1.0), gap=12.0, align=ACenter, fn() {
              c.text(
                fill("android-settings.add.picked", [
                  ("n", list.length().to_string()),
                  ("picked", picked.filter(fn(e) { !inside.contains(e) }).length().to_string()),
                ]),
                size=13.0,
                color=t.p.muted,
                w=Fill(1.0),
                line=18.0,
              )
              |> ignore
              if tap_text(c, "add-all", tr("android-settings.all"), size=14.0) {
                picked.clear()
                for p in list {
                  let e = text(Some(p), "email")
                  if !inside.contains(e) {
                    picked.push(e)
                  }
                }
              }
              if tap_text(c, "add-none", tr("android-settings.none"), size=14.0) {
                picked.clear()
              }
            })
            |> ignore
          })
          blocks.push(fn() {
            for p in list {
              let pv = Some(p)
              let e = text(pv, "email")
              let there = inside.contains(e)
              let name = match text(pv, "name") {
                "" => e
                n => n
              }
              if pick_row(
                  c,
                  "add-person/" + e,
                  name,
                  sub=join([e, if there { tr("android-settings.add.in") } else if flag(pv, "guest") { tr("android-settings.add.guest") } else { "" }], " · "),
                  checked=there || picked.contains(e),
                  enabled=!there,
                  mark=fn() { avatar(c, core, e, name, 28.0, picture=text(pv, "image")) },
                ) {
                match picked.search(e) {
                  Some(i) => picked.remove(i) |> ignore
                  None => picked.push(e)
                }
              }
            }
            if problems.length() > 0 {
              c.text(join(problems, tr("android-settings.add.problemSep")), size=13.0, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore
            }
          })
        }
      }
    }
    blocks.push(fn() {
      c.text(tr("android-settings.add.role"), size=13.0, weight=600, color=t.p.text, w=Fill(1.0), line=18.0) |> ignore
      for r in roles {
        if pick_row(c, "add-role/" + r, role_label(r), sub=role_hint(r), checked=role.val == r) {
          role.val = r
        }
      }
    })
    let busy = is_doing(core, ["workspace.addMembers"], [("account", here.sub), ("workspace", here.workspace)])
    blocks.push(fn() {
      // (from the words typed above, this frame's: this block is drawn after the field's)
      let emails : Array[String] = []
      for e in parse_emails(typed) + picked {
        if !inside.contains(e) && !emails.contains(e) {
          emails.push(e)
        }
      }
      if error.val != "" {
        c.text(error.val, size=13.0, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore
      }
      c.box(dir=Row, w=Fill(1.0), pt=6.0, pb=24.0, gap=8.0, justify=JEnd, fn() {
        if button(c, "add-cancel", tr("common.cancel"), false) {
          c.blur()
          close_sheet()
        }
        if button(
            c,
            "add-go",
            if emails.length() > 1 {
              fill("android-settings.add.many", [("n", emails.length().to_string())])
            } else {
              tr("android-settings.add.one")
            },
            true,
            busy~,
            enabled=emails.length() > 0,
          ) {
          c.blur()
          error.val = ""
          (core.call)(
            "workspace.addMembers",
            obj([
              ("workspace", str(here.workspace)),
              ("role", str(role.val)),
              ("emails", Json::array(emails.map(str))),
              ("account", str(here.sub)),
            ]),
            fn(r) {
              match r {
                Ok(v) => {
                  let n = fn(k : String) { items(Some(v), k).length() }
                  done.val = fill("android-settings.add.done", [
                    (
                      "list",
                      join(
                        [
                          if n("joined") > 0 { fill("android-settings.add.joined", [("n", n("joined").to_string())]) } else { "" },
                          if n("added") > 0 { fill("android-settings.add.added", [("n", n("added").to_string()), ("app", "still.fail")]) } else { "" },
                          if n("already") > 0 { fill("android-settings.add.already", [("n", n("already").to_string())]) } else { "" },
                        ],
                        tr("android-settings.add.sep"),
                      ),
                    ),
                  ])
                }
                Err(e) => error.val = error_text(e)
              }
            },
          )
        }
      })
      |> ignore
    })
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      scroll_page(c, key, blocks.map(fn(b) { fn() { c.box(w=Fill(1.0), padx=20.0, pb=10.0, fn() { b() }) |> ignore } }))
    })
    |> ignore
  })
}

///|
/// The run's chips in lines (History.kt EffortChips), and a chip.
// kept across runs: a value (no field of it changes)
let run_chips : @ui.Style = @ui.style(row=true, w=Full, gap=S2)

///|
/// A chip of a choice (History.kt EffortChips): 16 either side of its words, 9 over and under, round by 18.
let chip_px : Double = 16.0

///|
let chip_py : Double = 9.0

///|
let chip_corner : Double = 18.0
