// How a chat's agent runs, changed on a page of its own (History.kt RunSettingsScreen), the machine's own sessions to
// go on with (NewChat.kt MachineSessionsOffer, openMachineSessions, lookAtMachineSession), and adding people to the
// workspace (Settings.kt AddSheet) with the workspace's mark.

///|
/// How an agent runs (RunSettingsScreen): what it is now and what it becomes, the changes marked (and why its account
/// must change, when it must); then the model, how hard it thinks, how fast and who runs it, each picked in the core's
/// `pick` of `session:<key>` (`pick.set`); the button says what it becomes (不变 when nothing changed) and saves
/// (`pick.save`), or, another station's model, borrows it once asked again.
fn run_settings_page(c : @ui.Ctx, core : Core, station : String, key : String) -> Unit {
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
      // (read the first time: what it would show of a made-up agent's, in its bones)
      @sf.waiting(
        c,
        fill=true,
        fn() { run_view(c, core.quiet(), station, key, Some(run_sample()), fn(_) {  }, "") },
        error=match topic.error {
          Some(e) => error_text(e)
          None => ""
        },
      )
      return
    }
    run_view(c, core, station, key, v, pick, list)
  })
  |> ignore
}

///|
/// How an agent runs, as the core's `pick` (`v`) says it (`list`: the models or the accounts to pick from, else all of
/// it); what is picked told by `pick`.
fn run_view(
  c : @ui.Ctx,
  core : Core,
  station : String,
  key : String,
  v : Json?,
  pick : (Array[(String, Json)]) -> Unit,
  list : String,
) -> Unit {
  let t = @sf.theme()
  let of = "session:" + key
  let runtime = text(field(v, "value"), "runtime")
  let draft = field(v, "draft")
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
  // (a row of the library's list card, as every page's: the user, 2026-10-29, cards each page rounded its own way)
  let setting_row = fn(k : String, title : String, note : String, trouble : String, lead : (() -> Unit)?) {
    let mut tapped = false
    @sf.group(c, fn() { tapped = @sf.link_row(c, k, title, note~, trouble~, lead?) })
    tapped
  }
  let fast = flag(v, "fastAvailable")
  // (in the page's room, 12 from its sides, as every page's blocks: it stood 18 in)
  c.box(style=run_body, fn() {
    scroll_page(c, "run-session/" + key, [
      fn() {
        // what it was and what it becomes, a line each property, the changes marked
        c.box(w=Fill(1.0), pt=8.0, fn() {
          @sf.page_card(c, fn() {
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
        if setting_row("session-run-model", text(v, "modelText"), "", "", Some(fn() {
            @sf.maker_mark(c, text(field(v, "maker"), "id"), runtime, 18.0) |> ignore
          })) {
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
        if setting_row(
            "session-run-account",
            text(v, "accountText"),
            text(v, "accountNote"),
            if flag(v, "accountWarn") { tr("android-chat.run.account.warn") } else { "" },
            None,
          ) {
          run_list[of] = "account"
        }
        gap(c, 16.0)
      },
    ])
  })
  |> ignore
  // its button at its foot: in a panel of its own, each end in the foot corner it is in concentric with it
  // (@sf.foot_capsule)
  let (foot_l, foot_r, foot_b) = @sf.foot_capsule(wide_button_h, 12.0, 12.0)
  // the model picked is another station's: said so over the button, which borrows it (asked again)
  match field(v, "borrow") {
    Some(Object(_)) as b => {
      let allowed = flag(b, "allowed")
      c.box(w=Fill(1.0), pl=16.0, pr=16.0, pt=8.0, fn() {
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
}

///|
/// How an agent runs, made up, for what is shown while it is read (run_view in its bones).
fn run_sample() -> Json {
  let w = fn(n : Int) { Json::string(@sf.sample_words(n)) }
  {
    "was": [w(6), w(2), w(5)],
    "becomes": [w(6), w(2), w(5)],
    "modelText": w(7),
    "efforts": [w(1), w(1), w(1)],
    "accountText": w(6),
    "accountNote": w(14),
    "saveText": w(4),
  }
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
  if hit(c, id) {
    open_machine_sessions(core, station, name)
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
/// The machine's sessions (openMachineSessions), each a look at it before going on with it: a dialog of its own in the
/// window's middle (a sheet on a small screen), as the web's is, not a panel hanging off the offer's line of words.
/// Found by what they are (pengxiao, 2026-10-30: 「没有时间、没有 Provider 之类的过滤」): over the list, kept in view
/// as it scrolls, a search of their titles and folders, which runtime (where more than one ran: each with how many),
/// and which folder (the projects they ran in, most used first; still.fail's own sessions, under its directory, one of
/// them, not in the rest). The list under its days' headings (the core's `day`), each row the runtime's mark, its
/// title, when at its line's end (the core's `when`), where it ran under them.
pub fn open_machine_sessions(core : Core, station : String, name : String) -> Unit {
  let shown = if name == "" { tr("android-chat.new.machine.here") } else { name }
  let runtime : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })
  // (the folder chosen: "" all of them but still.fail's own, machine_own those alone)
  let folder : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })
  let search_key = "machine-search/" + station
  @sf.panel(
    fill("android-chat.new.machine.title", [("station", shown)]),
    description=tr("android-chat.new.machine.text"),
    from=Unanchored,
    wide=true,
    tall=0.75,
    fn(c, close) {
      let all = machine_sessions.get(station).unwrap_or([])
      // whether one is in the folder chosen
      let in_folder = fn(sv : Json?) {
        match folder.get() {
          "" => !flag(sv, "own")
          f if f == machine_own => flag(sv, "own")
          f => !flag(sv, "own") && text(sv, "folder") == f
        }
      }
      // what is chosen among: the folders of all of them (still.fail's own apart), the runtimes of those in the folder
      let runtimes : Array[(String, Int)] = []
      let folders : Array[(String, Int)] = []
      let mut own = 0
      let mut shown_n = 0
      for s in all {
        let sv = Some(s)
        if in_folder(sv) {
          shown_n += 1
          let rt = text(sv, "runtime")
          match runtimes.search_by(fn(r) { r.0 == rt }) {
            Some(i) => runtimes[i] = (rt, runtimes[i].1 + 1)
            None => runtimes.push((rt, 1))
          }
        }
        if flag(sv, "own") {
          own += 1
        } else {
          let f = text(sv, "folder")
          match folders.search_by(fn(r) { r.0 == f }) {
            Some(i) => folders[i] = (f, folders[i].1 + 1)
            None => folders.push((f, 1))
          }
        }
      }
      // the runtime chosen, while the folder has more than one and that among them (else all of them: nothing hidden by
      // a choice no longer shown)
      let rt_now = if runtimes.length() > 1 && runtimes.iter().any(fn(r) { r.0 == runtime.get() }) {
        runtime.get()
      } else {
        ""
      }
      folders.sort_by(fn(a, b) { if a.1 != b.1 { b.1 - a.1 } else { a.0.compare(b.0) } })
      // the filters, in view over the list
      let mut words = ""
      c.box(style=@sf.panel_words_in().then(machine_filters), fn() {
        c.box(style=machine_filters_line, fn() {
          c.box(style=machine_search, fn() {
            words = @sf.input(c, search_key, placeholder=tr("android-chat.new.machine.search"), small=true).text.trim().to_owned()
          })
          |> ignore
          let chip = "machine-folder/" + station
          let label = match folder.get() {
            "" => tr("android-chat.new.machine.allFolders")
            f if f == machine_own => tr("android-chat.new.machine.own")
            f => f
          }
          if @sf.chip(c, label, key=chip, icon="folder") {
            let choices = [@sf.choice("", tr("android-chat.new.machine.allFolders"), value=(all.length() - own).to_string())]
            for f in folders {
              choices.push(@sf.choice(f.0, f.0, value=f.1.to_string()))
            }
            if own > 0 {
              choices.push(@sf.choice(machine_own, tr("android-chat.new.machine.own"), value=own.to_string()))
            }
            @sf.pick(tr("android-chat.new.machine.folder"), choices, folder.get(), fn(k) { folder.set(k) }, from=Of(c.id(chip)))
          }
        })
        |> ignore
        if runtimes.length() > 1 {
          let labels = [tr("android-chat.new.machine.all") + " " + shown_n.to_string()]
          for r in runtimes {
            labels.push(runtime_label(r.0) + " " + r.1.to_string())
          }
          let now = match runtimes.search_by(fn(r) { r.0 == rt_now }) {
            Some(i) => i + 1
            None => 0
          }
          let picked = @sf.segmented(c, "machine-runtime/" + station, labels, now)
          runtime.set(if picked == 0 { "" } else { runtimes[picked - 1].0 })
        }
      })
      |> ignore
      // those the filters leave, under their days' headings
      let lower = words.to_lower()
      let rows : Array[MachineRow] = []
      let mut day = ""
      for s in all {
        let sv = Some(s)
        if rt_now != "" && text(sv, "runtime") != rt_now {
          continue
        }
        if !in_folder(sv) {
          continue
        }
        if lower != "" &&
          !first_text(sv, ["title", "first"], "").to_lower().contains(lower) &&
          !text(sv, "where").to_lower().contains(lower) {
          continue
        }
        if text(sv, "day") != day {
          day = text(sv, "day")
          rows.push(Day(day))
        }
        rows.push(Session(s))
      }
      if rows.is_empty() {
        c.box(style=@sf.panel_words_in().then(machine_none), fn() {
          c.text(tr("android-chat.new.machine.none"), style=machine_none_words) |> ignore
        })
        |> ignore
        return
      }
      @sf.panel_list(c, "machine-sessions/" + station, rows.length(), 60.0, fn(i) {
        match rows[i] {
          Day(d) =>
            c.box(style=@sf.panel_words_in().then(if i == 0 { machine_day_first } else { machine_day }), fn() {
              c.text(d, style=machine_day_words) |> ignore
            })
            |> ignore
          Session(s) => {
            let sv = Some(s)
            let key = "machine-session/" + text(sv, "id")
            let pressed = @sf.choice_row(
              c,
              key,
              false,
              first_text(sv, ["title", "first"], ""),
              note=first_text(sv, ["where", "meta"], ""),
              lead=fn() { @sf.maker_mark(c, "", text(sv, "runtime"), 18.0) |> ignore },
              tag=fn() {
                if has(sv, "session") {
                  @sf.pill(c, fill("android-chat.new.machine.inApp", [("app", "still.fail")]))
                }
              },
              trail=fn() {
                c.text(text(sv, "when"), style=machine_when) |> ignore
              },
            )
            if pressed {
              // (the look in its place)
              close()
              look_at_machine_session(core, station, name, s)
            }
            // its first words whole while it is pointed at (MachineSessions.tsx's tip: its title cut short is often them)
            @sf.tip(c, key + "/tip", c.id(key), text(sv, "first"))
          }
        }
      })
      |> ignore
    },
  )
}

///|
/// The filters over the machine's sessions (their search and folder's line, the runtimes under it), 10 apart.
// kept across runs: a value (no field of it changes)
let machine_filters : @ui.Style = @ui.css("w=Full gap=S2_5 pt=S1 pb=S2_5")

///|
// kept across runs: a value (no field of it changes)
let machine_filters_line : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let machine_search : @ui.Style = @ui.css("w=Full")

///|
/// Where none is left by the filters: its words in the middle, room over and under them.
// kept across runs: a value (no field of it changes)
let machine_none : @ui.Style = @ui.css("w=Full pt=S8 pb=S10 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let machine_none_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, center=true, w=Full)

///|
/// A day's heading among them (the first close under the filters, the rest a gap over them).
// kept across runs: a value (no field of it changes)
let machine_day : @ui.Style = @ui.css("w=Full pt=S3_5 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let machine_day_first : @ui.Style = @ui.css("w=Full pt=S1 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let machine_day_words : @ui.TextStyle = @ui.text_style(size=Caption, weight=Semibold, color=Muted, wrap=false)

///|
/// When at a row's end (the core's `when`).
// kept across runs: a value (no field of it changes)
let machine_when : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false)

///|
/// A line of the machine's sessions' list: a day's heading, or one of them.
priv enum MachineRow {
  Day(String)
  Session(Json)
}

///|
/// The folder chosen for still.fail's own sessions alone (no folder's name: a path's part never has a NUL).
let machine_own : String = "\u{0}own"

///|
/// One of them looked at before going on with it (lookAtMachineSession): what was said in it, the latest at the bottom
/// (`machineSessions.read`); 继续 makes the chat that goes on with it (`machineSessions.continue`) and opens it.
fn look_at_machine_session(core : Core, station : String, name : String, s : Json) -> Unit {
  let sv = Some(s)
  let said : @signals.Signal[(Array[Json], Int)?] = @signals.signal(None)
  let error : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })
  (core.call)("machineSessions.read", obj([("station", str(station)), ("runtime", str(text(sv, "runtime"))), ("id", str(text(sv, "id"))), ("limit", Json::number(200.0))]), fn(r) {
    match r {
      Ok(v) => {
        let list = items(Some(v), "said")
        said.set(Some((list, if has(Some(v), "total") { count(Some(v), "total") } else { list.length() })))
      }
      Err(e) => error.set(error_text(e))
    }
  })
  // (as wide as the list it was opened from, in its place; where it ran and how long ago under its title)
  @sf.panel(first_text(sv, ["title", "first"], ""), description=text(sv, "meta"), from=Unanchored, wide=true, tall=0.85, fn(c, close) {
    let t = @sf.theme()
    c.box(style=@sf.panel_words_in(), w=Fill(1.0), h=Fill(1.0), fn() {
      match said.get() {
        None =>
          if error.get() == "" {
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
          @sf.panel_list(c, k, blocks.length(), 120.0, stick_end=true, fn(i) { (blocks[i])() }) |> ignore
        }
      }
    })
    |> ignore
    if error.get() != "" {
      c.box(style=@sf.panel_words_in(), w=Fill(1.0), pady=6.0, fn() {
        c.text(error.get(), size=t.t.meta, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore
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
        error.set("")
        (core.call)("machineSessions.continue", obj([("station", str(station)), ("runtime", str(text(sv, "runtime"))), ("id", str(text(sv, "id")))]), fn(r) {
          match r {
            Ok(v) => {
              close()
              (core.pop)()
              (core.open_chat)(station, text(Some(v), "key"), first_text(sv, ["title", "first"], ""))
            }
            Err(e) => error.set(error_text(e))
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
  let error : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })
  let done : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })
  let people : @signals.Signal[Array[Json]?] = @signals.signal(None)
  let problems : Array[String] = []
  let reading : @signals.Signal[Int] = @signals.signal(0, same=fn(a, b) { a == b })
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
    if done.get() != "" {
      c.box(style=@sf.panel_words_in(), w=Fill(1.0), fn() {
        c.text(done.get(), size=t.t.ui, color=t.p.text, w=Fill(1.0), line=20.0) |> ignore
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
        // (the library's lines to type in: one frame for every field)
        c.box(w=Fill(1.0), pt=6.0, fn() {
          @sf.textarea(c, key, rows=1, most=3, placeholder=tr("android-settings.add.emailsPlaceholder"), field=field_of(key))
          |> ignore
        })
        |> ignore
      },
    ]
    if online.length() > 0 {
      match people.get() {
        None =>
          blocks.push(fn() {
            c.box(dir=Row, fn() {
              if @sf.button(c, tr("android-settings.add.fromSlack"), key="add-from-slack", busy=reading.get() > 0) {
                reading.set(online.length())
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
                    reading.set(reading.get() - 1)
                    if reading.get() == 0 {
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
                      people.set(Some(all))
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
    if error.get() != "" {
      blocks.push(fn() { c.text(error.get(), size=t.t.meta, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore })
    }
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      scroll_page(c, key, blocks.mapi(fn(i, b) {
        fn() { @sf.sheet_column(c, fn() { c.box(style=if i == 0 { @sf.full_width } else { sheet_block }, b) |> ignore }) }
      }))
    })
    |> ignore
  }, foot=fn(c, close) {
    // its buttons at the panel's foot (the presenter's: as far from its foot as its corner says), from what is typed
    // and picked now
    if done.get() != "" {
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
      error.set("")
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
              done.set(fill("android-settings.add.done", [
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
              ]))
            }
            Err(e) => error.set(error_text(e))
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
              tag=fn() { @sf.quota_chips(c, field(av, "quota"), key=key + "/" + id) },
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

///|
/// The run page's blocks, in the page's room (12 from its sides) and as tall as the page.
// kept across runs: a value (no field of it changes)
let run_body : @ui.Style = @sf.pg_room.then(@ui.style(h=@sf.grow))
