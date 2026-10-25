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
      // beside 自动分配, a chat's: the station picks its account again now (`pick.repick`), which it took said
      let repick = text(v, "repick")
      let repicking = fn() {
        let busy = is_doing(core, ["pick.repick"], [("station", station), ("of", of)])
        if @sf.button(c, repick, key="run-session-repick", busy~) {
          (core.call)("pick.repick", obj([("station", str(station)), ("of", str(of))]), fn(r) {
            match r {
              Ok(said) =>
                match text(Some(said), "said") {
                  "" => ()
                  words => (core.say)(words)
                }
              Err(e) => (core.say)(fill("android-misc.act.failed", [("what", repick), ("error", error_text(e))]))
            }
          })
        }
      }
      account_list(
        c,
        "run-session-accounts/" + key,
        items(v, "accounts"),
        runtime,
        text(draft, "profile"),
        fn(p) {
          pick([("profile", match p { Some(id) => str(id); None => Json::null() })])
          run_list.remove(of)
        },
        auto_trail?=if repick == "" { None } else { Some(repicking) },
      )
      return
    }
    let group = fn(words : String) {
      c.box(w=Fill(1.0), pl=6.0, pt=16.0, pb=6.0, fn() {
        c.text(words, size=t.t.meta, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
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
            c.text(o, size=t.t.ui, weight=if on { 600 } else { 400 }, color=if on { t.p.bg } else { t.p.text }, wrap=false)
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
              // (the labels' column as wide as the widest of them, in this language: words of a length known, whole)
              let label_w = labels.fold(init=0.0, fn(m, l) {
                dmax(m, c.words_across(l, run_label).ceil())
              })
              for i, label in labels {
                let w = was.get(i).unwrap_or("")
                let b = becomes.get(i).unwrap_or("")
                let moved = b != w
                c.box(dir=Row, w=Fill(1.0), gap=8.0, align=ACenter, fn() {
                  c.box(w=Px(label_w), fn() { c.text(label, style=run_label) |> ignore }) |> ignore
                  c.text(w, size=t.t.meta, color=if moved { t.p.muted } else { t.p.text }, wrap=false) |> ignore
                  if moved {
                    @sf.icon(c, "arrow-right", size=14.0, color=t.p.accent) |> ignore
                    c.text(b, size=@sf.theme().t.ui, weight=600, color=@sf.link_ink(), wrap=false, w=Fill(1.0)) |> ignore
                  }
                })
                |> ignore
              }
              match opt_text(v, "force") {
                Some(f) => c.text(f, size=t.t.caption, color=t.p.warn_ink, w=Fill(1.0), line=17.0) |> ignore
                None => ()
              }
              c.text(tr("android-chat.run.next"), size=t.t.caption, color=t.p.subtle, w=Fill(1.0), line=17.0) |> ignore
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
            c.text(tr("android-chat.run.effort.note"), size=t.t.caption, color=t.p.muted, w=Fill(1.0), line=17.0) |> ignore
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
              c.text(tr("android-chat.run.speed.note"), size=t.t.caption, color=t.p.muted, w=Fill(1.0), line=17.0) |> ignore
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
                c.text(text(v, "accountText"), size=t.t.ui, color=t.p.text, wrap=false, w=Fill(1.0), line=21.0) |> ignore
                c.text(text(v, "accountNote"), size=t.t.caption, color=t.p.muted, w=Fill(1.0), line=17.0) |> ignore
                if flag(v, "accountWarn") {
                  c.text(tr("android-chat.run.account.warn"), size=t.t.caption, color=t.p.warn_ink, w=Fill(1.0), line=17.0) |> ignore
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
    // its button at its foot: in a panel of its own, each end in the foot corner it is in concentric with it
    // (@sf.foot_capsule)
    let (foot_l, foot_r, foot_b) = @sf.foot_capsule(wide_button_h, 18.0, 12.0)
    // the model picked is another station's: said so over the button, which borrows it (asked again)
    match field(v, "borrow") {
      Some(Object(_)) as b => {
        let allowed = flag(b, "allowed")
        c.box(w=Fill(1.0), pl=22.0, pr=22.0, pt=8.0, fn() {
          c.text(if allowed { text(b, "note") } else { opt_text(b, "why").unwrap_or(text(b, "note")) }, size=t.t.caption, color=t.p.muted, w=Fill(1.0), line=17.0)
          |> ignore
        })
        |> ignore
        c.box(w=Fill(1.0), pl=foot_l, pr=foot_r, pt=12.0, pb=foot_b, fn() {
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
        c.box(w=Fill(1.0), pl=foot_l, pr=foot_r, pt=12.0, pb=foot_b, fn() {
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
/// The offer, where the station's machine kept sessions of its own Claude Code or Codex (MachineSessions.css.ts offer):
/// quiet as the words around it until pointed at, then its ground and its words the text's; its list and a look at one
/// before going on with it are sheets. Drawn by a new chat's page (sfpages), which says where it hangs.
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
  c.cursor(id, Hand)
  if hit(c, id) {
    open_machine_sessions(core, station, name, from=Of(id))
  }
  let lit = c.lit(id)
  let words = fill("android-chat.new.machine.offer", [
    ("station", if name == "" { tr("android-chat.new.machine.here") } else { name }),
  ])
  let b = c.box(style=machine_offer_box, id~, fn() {
    @sf.icon(c, "monitor", size=machine_offer_mark, color=if lit { t.p.text } else { t.p.muted }) |> ignore
    c.text(words, style=if lit { machine_offer_words_lit } else { machine_offer_words }) |> ignore
    @sf.press_ripple(c, id, @sf.small_corner)
  })
  c.semantics(b, Button, id~, label=words)
}

///|
/// The offer (offer: 4 by 10 in, its parts 6 apart, the hover's ground; 13 on 20, muted) and its mark (Monitor 14).
// kept across runs: a value (no field of it changes)
let machine_offer_box : @ui.Style = @ui.css("row px=S2_5 py=S1 gap=S1_5 align=ACenter hovered{bg=Hover}").then(
  @ui.style(radius=@sf.small_radius),
)

///|
// kept across runs: a value (no field of it changes)
let machine_offer_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let machine_offer_words_lit : @ui.TextStyle = machine_offer_words.then(@ui.text_style(color=Fg))

///|
let machine_offer_mark : Double = 14.0

///|
/// The machine's sessions (openMachineSessions), each a look at it before going on with it: the library's panel opened
/// `from` what was pressed, most of the window tall, what it holds at its own sides.
pub fn open_machine_sessions(core : Core, station : String, name : String, from? : @sf.Anchor = Unanchored) -> Unit {
  let shown = if name == "" { tr("android-chat.new.machine.here") } else { name }
  @sf.panel(fill("android-chat.new.machine.title", [("station", shown)]), from~, tall=0.7, fn(c, close) {
    let t = @sf.theme()
    c.box(style=@sf.panel_words_in(), w=Fill(1.0), pb=8.0, fn() {
      c.text(tr("android-chat.new.machine.text"), size=t.t.meta, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
    })
    |> ignore
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      scroll_page(c, "machine-sessions/" + station, [
        fn() {
          for s in machine_sessions.get(station).unwrap_or([]) {
            let sv = Some(s)
            let id = c.id("machine-session/" + text(sv, "id"))
            if hit(c, id) {
              // (the look in its place)
              close()
              look_at_machine_session(core, station, name, s)
            }
            c.box(style=@sf.panel_words_in(), dir=Row, w=Fill(1.0), pady=10.0, gap=12.0, align=ACenter, id~, fn() {
              @sf.maker_mark(c, "", text(sv, "runtime"), 18.0) |> ignore
              c.box(w=Fill(1.0), fn() {
                c.text(first_text(sv, ["title", "first"], ""), size=t.t.ui, color=t.p.text, wrap=false, w=Fill(1.0), line=21.0) |> ignore
                c.text(text(sv, "meta"), size=t.t.caption, color=t.p.muted, wrap=false, w=Fill(1.0), line=17.0) |> ignore
              })
              |> ignore
              if has(sv, "session") {
                c.text(fill("android-chat.new.machine.inApp", [("app", "still.fail")]), size=t.t.caption, color=t.p.muted, wrap=false) |> ignore
              }
              @motion.ripple(c, id, 0.0)
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
  @sf.panel(first_text(sv, ["title", "first"], ""), from=Unanchored, tall=0.85, fn(c, close) {
    let t = @sf.theme()
    c.box(style=@sf.panel_words_in(), w=Fill(1.0), pb=8.0, fn() {
      c.text(text(sv, "meta"), size=t.t.caption, color=t.p.muted, wrap=false, w=Fill(1.0), line=17.0) |> ignore
    })
    |> ignore
    c.box(style=@sf.panel_words_in(), w=Fill(1.0), h=Fill(1.0), fn() {
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
              c.text(fill("android-chat.new.machine.more", [("n", left.to_string())]), size=t.t.caption, color=t.p.muted, center=true, w=Fill(1.0), line=17.0)
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
                      c.text(text(mv, "text"), size=t.t.body, color=t.p.text, line=21.0) |> ignore
                    })
                    |> ignore
                  })
                  |> ignore
                } else {
                  c.box(w=Fill(1.0), gap=4.0, fn() {
                    c.box(dir=Row, gap=6.0, align=ACenter, fn() {
                      @sf.maker_mark(c, "", runtime, 16.0) |> ignore
                      c.text(model, size=t.t.meta, weight=600, color=t.p.text, wrap=false) |> ignore
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
      c.box(style=@sf.panel_words_in(), w=Fill(1.0), pady=6.0, fn() {
        c.text(error.val, size=t.t.meta, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore
      })
      |> ignore
    }
    let busy = is_doing(core, ["machineSessions.continue"], [("station", station), ("id", text(sv, "id"))])
    c.box(style=@sf.panel_words_in(), dir=Row, w=Fill(1.0), pt=10.0, pb=24.0, gap=8.0, justify=JEnd, fn() {
      if @sf.button(c, tr("common.back"), key="machine-back") {
        // (the list in its place)
        close()
        open_machine_sessions(core, station, name)
      }
      if @sf.button(c, tr(if has(sv, "session") { "android-chat.new.machine.open" } else { "android-chat.new.machine.continue" }), key="machine-go", tone=Primary, busy=busy) {
        error.val = ""
        (core.call)("machineSessions.continue", obj([("station", str(station)), ("runtime", str(text(sv, "runtime"))), ("id", str(text(sv, "id")))]), fn(r) {
          match r {
            Ok(v) => {
              close()
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
pub fn open_add_people(core : Core, here : Here, view : Json?, from? : @sf.Anchor = Unanchored) -> Unit {
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
  // the library's panel opened `from` what was pressed, most of the window tall, what it holds at its own sides
  @sf.panel(tr("android-settings.add.title"), from~, tall=0.8, form=true, fn(c, close) {
    let t = @sf.theme()
    let online = online_stations(core, here)
    if done.val != "" {
      c.box(style=@sf.panel_words_in(), w=Fill(1.0), fn() {
        c.text(done.val, size=t.t.ui, color=t.p.text, w=Fill(1.0), line=20.0) |> ignore
      })
      |> ignore
      return
    }
    let blocks : Array[() -> Unit] = [
      fn() {
        c.text(fill("android-settings.add.note", [("name", text(view, "name")), ("app", "still.fail")]), size=t.t.meta, color=t.p.muted, w=Fill(1.0), line=20.0)
        |> ignore
      },
      fn() {
        c.text(tr("android-settings.add.emails"), size=t.t.meta, weight=600, color=t.p.text, w=Fill(1.0), line=18.0) |> ignore
        c.box(w=Fill(1.0), pt=6.0, fn() {
          c.box(w=Fill(1.0), padx=12.0, pady=10.0, radius=12.0, bg=t.p.card, border=1.0, border_color=t.p.line, fn() {
            c.editor(
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
            )
            |> ignore
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
              if @sf.button(c, tr("android-settings.add.fromSlack"), key="add-from-slack", busy=reading.val > 0) {
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
                size=t.t.meta,
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
              if @sf.choice_row(c, "add-person/" + e, there || picked.contains(e), name, note=join([e, if there { tr("android-settings.add.in") } else if flag(pv, "guest") { tr("android-settings.add.guest") } else { "" }], " · "), disabled=!(!there), lead=fn() { avatar(c, core, e, name, 28.0, picture=text(pv, "image")) }) {
                match picked.search(e) {
                  Some(i) => picked.remove(i) |> ignore
                  None => picked.push(e)
                }
              }
            }
            if problems.length() > 0 {
              c.text(join(problems, tr("android-settings.add.problemSep")), size=t.t.meta, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore
            }
          })
        }
      }
    }
    blocks.push(fn() {
      c.text(tr("android-settings.add.role"), size=t.t.meta, weight=600, color=t.p.text, w=Fill(1.0), line=18.0) |> ignore
      for r in roles {
        if @sf.choice_row(c, "add-role/" + r, role.val == r, role_label(r), note=role_hint(r)) {
          role.val = r
        }
      }
    })
    if error.val != "" {
      blocks.push(fn() { c.text(error.val, size=t.t.meta, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore })
    }
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      scroll_page(c, key, blocks.map(fn(b) { fn() { @sf.sheet_column(c, fn() { c.box(style=sheet_block, b) |> ignore }) } }))
    })
    |> ignore
  }, foot=fn(c, close) {
    // its buttons at the panel's foot (the presenter's: as far from its foot as its corner says), from what is typed
    // and picked now
    if done.val != "" {
      if @sf.button(c, tr("common.done"), key="add-people-done", tone=Primary) {
        close()
      }
      return
    }
    let busy = is_doing(core, ["workspace.addMembers"], [("account", here.sub), ("workspace", here.workspace)])
    let emails : Array[String] = []
    for e in parse_emails(field_of(key).text()) + picked {
      if !inside.contains(e) && !emails.contains(e) {
        emails.push(e)
      }
    }
    if @sf.button(c, tr("common.cancel"), key="add-cancel") {
      c.blur()
      close()
    }
    if @sf.button(c, if emails.length() > 1 {
          fill("android-settings.add.many", [("n", emails.length().to_string())])
        } else {
          tr("android-settings.add.one")
        }, key="add-go", tone=Primary, busy=busy, disabled=emails.length() == 0) {
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
}

///|
/// The run's chips in lines (History.kt EffortChips), and a chip.
// kept across runs: a value (no field of it changes)
let run_chips : @ui.Style = @ui.css("row w=Full gap=S2")

///|
/// A chip of a choice (History.kt EffortChips): 16 either side of its words, 9 over and under, round by 18.
let chip_px : Double = 16.0

///|
let chip_py : Double = 9.0

///|
let chip_corner : Double = 18.0

///|
/// Who runs the model picked (SettingParts.kt AccountList): what 自动分配 means, then 自动分配 (none picked: the
/// station's pick; `auto_trail` at its end) and each account it may be kept to, its provider's mark before it and its
/// allowance after it, 18 from the sides. `pick` hears the account picked (None: 自动分配).
fn account_list(
  c : @ui.Ctx,
  key : String,
  accounts : Array[Json],
  runtime : String,
  picked : String,
  pick : (String?) -> Unit,
  auto_trail? : () -> Unit,
) -> Unit {
  scroll_page(c, key, [
    fn() {
      c.box(style=account_list_room, fn() {
        c.box(style=account_note_room, fn() { c.text(tr("android-chat.run.account.note"), style=account_note_words) |> ignore }) |> ignore
        if @sf.choice_row(c, key + "/auto", picked == "", tr("android-chat.run.account.auto"), trail?=auto_trail) {
          pick(None)
        }
        for a in accounts {
          let av = Some(a)
          let id = text(av, "id")
          let own = text(av, "runtime")
          if @sf.choice_row(
              c,
              key + "/" + id,
              picked == id,
              text(av, "name"),
              lead=fn() { @sf.provider_logo(c, if own == "" { runtime } else { own }, text(av, "kind"), 18.0, text(av, "mark")) },
              tag=fn() { @sf.quota_chips(c, field(av, "quota")) },
            ) {
            pick(Some(id))
          }
        }
      })
      |> ignore
    },
  ])
}

///|
/// The accounts' list, 18 from the sides (AccountList: padding(horizontal = 18)).
// kept across runs: a value (no field of it changes)
let account_list_room : @ui.Style = @ui.css("w=Full px=S4_5")

///|
/// What 自动分配 means, over the list: 8 above it, 4 below (padding(top = 8, bottom = 4)).
// kept across runs: a value (no field of it changes)
let account_note_room : @ui.Style = @ui.css("w=Full pt=S2 pb=S1")

///|
/// 12sp, muted.
// kept across runs: a value (no field of it changes)
let account_note_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, w=Full)

///|
/// The pickers opened (their `pick.set {open}` sent once a page), and which list a run page shows ("" its first view).
// kept across runs: said as a run's page opens; the settings' reset empties it
let run_opened : Map[String, Bool] = Map([])

///|
// kept across runs: said by a run's page; the settings' reset empties it
let run_list : Map[String, String] = Map([])

///|
/// A property's label in what a run was and becomes (meta, muted, on one line).
// kept across runs: a value (no field of it changes)
let run_label : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)
