// The rest of settings' pages (the Android app's settings module): the automatic decisions (AutomaticDecisions.kt: the
// rule's page, each station's settings of it, a station's archive policy and its options), this device's bottom bars
// (BarSettings.kt), what this device keeps (KeptFiles.kt), the changelog (Changelog.kt), the prices the usage is
// counted at (Usage.kt UsagePricesScreen); and, used from the chats' pages, how an agent runs (History.kt
// RunSettingsScreen, run_page) and the machine's own sessions to go on with (NewChat.kt MachineSessions).

// ---------------------------------------------------------------------------
// 自动决策

///|
/// A wait said in a line where a page's note goes.
fn note_wait(c : @ui.Ctx, words : String, error? : Bool = false) -> Unit {
  c.box(w=Fill(1.0), pl=24.0, pr=24.0, pb=10.0, fn() { wait_line(c, words, error~) }) |> ignore
}

///|
/// The completion rule's page (AutomaticDecisionCompletionScreen): each station's settings of it, or why there are
/// none (offline, older, not read yet).
fn completion_page(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let topic = stations_of(core, here)
  let blocks : Array[() -> Unit] = [
    fn() { top_back(c, core, tr("web-pages.automaticDecisions.title")) },
    fn() { large_title(c, tr("web-pages.automaticDecisions.completion"), about=tr("web-pages.automaticDecisions.completionNote")) },
  ]
  match topic.value {
    Some(Array(a)) => {
      for st in a {
        let s = Some(st)
        let view = field(field(s, "overview"), "automaticDecisions")
        if flag(s, "online") && view is Some(Object(_)) {
          blocks.append(decision_panel(c, core, text(s, "station"), text(s, "name"), view))
        } else {
          blocks.push(fn() { section_header(c, text(s, "name"), start=S6) })
          blocks.push(fn() {
            if flag(s, "online") && !(field(s, "overview") is Some(Object(_))) {
              note_wait(c, tr("common.connecting"))
            } else {
              page_note(
                c,
                tr(if !flag(s, "online") { "web-pages.automaticDecisions.offlineNote" } else { "web-pages.automaticDecisions.upgrade" }),
              )
            }
          })
        }
      }
      if a.length() == 0 {
        blocks.push(fn() { page_note(c, tr("web-pages.automaticDecisions.addStation")) })
      }
    }
    _ =>
      blocks.push(fn() {
        waiting_cards(
          c,
          count=2,
          error=match topic.error {
            Some(e) => error_text(e)
            None => ""
          },
        )
      })
  }
  blocks.push(fn() { gap(c, 30.0) })
  scroll_page(c, "auto-completion", blocks)
}

///|
/// The drafts of the stations' rules open on the page (`decisionForm`), by station.
let decision_forms : Map[String, String] = Map([])

///|
/// A station's settings of the rule (AutomaticDecisionPanel), in the core's draft: on or off, its model (a sheet),
/// a review asked of the station as saved, its archive policy (a page), 保存 once changed; its models read again from
/// the head's ↻ (`automaticDecisions.refresh`).
fn decision_panel(c : @ui.Ctx, core : Core, station : String, name : String, view : Json?) -> Array[() -> Unit] {
  let t = @sf.theme()
  if !flag(view, "canEdit") {
    return [fn() { section_header(c, name, start=S6) }, fn() { page_note(c, tr("web-pages.automaticDecisions.adminOnly")) }]
  }
  let form = decision_form(c, core, station)
  let call = fn(action : String, input : Array[(String, Json)]) {
    act(
      core,
      tr("web-pages.automaticDecisions.configAction"),
      "automaticDecisions.form." + action,
      obj([("station", str(station)), ("form", str(form)), ("input", obj(input))]),
      done=if action == "save" { tr("web-pages.automaticDecisions.saved") } else { "" },
    )
  }
  let topic = (core.topic)("decisionForm", { "station": str(station), "form": str(form) })
  let d = topic.value
  let refreshing = is_doing(core, ["automaticDecisions.refresh"], [("station", station)])
  let head = fn() {
    c.box(dir=Row, w=Fill(1.0), pr=20.0, align=ACenter, fn() {
      c.box(w=Fill(1.0), fn() { section_header(c, name, start=S6) }) |> ignore
      // in the button's place, as big as it, so the head does not move
      if refreshing {
        c.box(w=Px(34.0), h=Px(34.0), align=ACenter, justify=JCenter, fn() { spinner(c) }) |> ignore
      } else if nav_button(c, "auto-refresh/" + station, "refresh") {
        act(
          core,
          tr("web-pages.automaticDecisions.refreshAction"),
          "automaticDecisions.refresh",
          obj([("station", str(station))]),
          done=tr("web-pages.automaticDecisions.refreshed"),
        )
      }
    })
    |> ignore
  }
  guard d is Some(Object(_)) else {
    return [
      fn() { section_header(c, name, start=S6) },
      fn() {
        note_wait(
          c,
          match topic.error {
            Some(e) => error_text(e)
            None => tr("web-pages.automaticDecisions.readingConfig")
          },
          error=topic.error is Some(_),
        )
      },
    ]
  }
  let saving = is_doing(core, ["automaticDecisions.form.save"], [("station", station), ("form", form)])
  let busy = flag(d, "pending") || saving
  let model_id = text(d, "model")
  let model = items(view, "models").iter().find_first(fn(m) { text(Some(m), "id") == model_id })
  let out : Array[() -> Unit] = [head]
  match failed_of(core, ["automaticDecisions.refresh"], [("station", station)]) {
    Some(why) => out.push(fn() { page_note(c, why) })
    None => ()
  }
  out.push(fn() {
    list_card(c, fn() {
      if list_row(c, key=if busy { "" } else { "auto-enabled/" + station }, fn() {
          row_title(c, tr("web-pages.automaticDecisions.enabled"))
          switch(c, "auto-enabled/" + station, flag(d, "enabled"))
        }) {
        call("edit", [("enabled", Json::boolean(!flag(d, "enabled")))])
      }
      if go_row(
          c,
          "auto-model/" + station,
          tr("web-pages.automaticDecisions.model"),
          value=match model {
            Some(m) => text(Some(m), "name")
            None =>
              if model_id == "" {
                tr("web-pages.automaticDecisions.pickModel")
              } else {
                fill("web-pages.automaticDecisions.unavailable", [("model", model_id)])
              }
          },
        ) &&
        !busy {
        // the library's panel, beside the row (a sheet with touch short of Large), half the window tall
        @sf.panel(tr("web-pages.automaticDecisions.model"), from=Of(c.id("auto-model/" + station)), tall=0.5, fn(c, close) {
          let d = (core.topic)("decisionForm", { "station": str(station), "form": str(form) }).value
          c.box(w=Fill(1.0), h=Fill(1.0), fn() {
            // every model it can move to (SettingParts.kt ModelList), codex's
            model_list(c, "auto-models/" + station, items(field(d, "pick"), "options"), "codex", text(d, "model"), fn(m) {
              close()
              act(
                core,
                tr("web-pages.automaticDecisions.configAction"),
                "automaticDecisions.form.edit",
                obj([("station", str(station)), ("form", str(form)), ("input", obj([("model", str(m))]))]),
              )
            })
          })
          |> ignore
        })
      }
      // asked of the station as saved: only once the rule is on there, and nothing unsaved
      if flag(view, "canReview") && flag(field(field(view, "settings"), "completion"), "enabled") && !flag(d, "dirty") {
        let reviewing = is_doing(core, ["automaticDecisions.review"], [("station", station)])
        if list_row(c, key=if busy || reviewing { "" } else { "auto-review/" + station }, fn() {
            row_title(c, tr("web-pages.automaticDecisions.review"))
            doing_mark(c, reviewing, failed_of(core, ["automaticDecisions.review"], [("station", station)]), inline=true)
          }) {
          act(
            core,
            tr("web-pages.automaticDecisions.reviewAction"),
            "automaticDecisions.review",
            obj([("station", str(station))]),
            done=tr("web-pages.automaticDecisions.reviewStarted"),
          )
        }
      }
      match field(view, "policy") {
        Some(Object(_)) as policy =>
          if list_row(c, key="auto-policy/" + station, fn() {
              c.box(w=Fill(1.0), gap=5.0, fn() {
                c.text(tr("web-pages.archivePolicy.title"), size=t.t.body, color=t.p.text, w=Fill(1.0), line=21.0) |> ignore
                c.text(
                  join(
                    [fill("web-pages.archivePolicy.optionCount", [("n", items(policy, "options").length().to_string())]), text(policy, "summaryText")],
                    " · ",
                  ),
                  size=t.t.meta,
                  color=if count(policy, "failed") > 0 { t.p.red } else { t.p.muted },
                  w=Fill(1.0),
                  line=18.0,
                )
                |> ignore
              })
              |> ignore
              chevron(c)
            }) {
            (core.push)(AutoPolicy(station))
          }
        _ => ()
      }
    })
  })
  if flag(d, "dirty") {
    out.push(fn() {
      c.box(dir=Row, w=Fill(1.0), padx=12.0, gap=12.0, align=ACenter, fn() {
        if @sf.button(c, tr("web-pages.automaticDecisions.save"), key="auto-save/" + station, tone=Primary, busy=saving, disabled=busy) {
          call("save", [])
        }
        doing_mark(c, false, failed_of(core, ["automaticDecisions.form.save"], [("station", station), ("form", form)]))
      })
      |> ignore
    })
  }
  out
}

///|
/// The drafts of the stations' archive policies open (`policyForm`), by station.
pub let policy_forms : Map[String, String] = Map([])

///|
/// A station's archive policy (AutomaticDecisionPolicyScreen, ArchivePolicySection): its words and its options in two
/// groups (to archive, to keep), each with how many chats the checks put there; a tap edits what it is on in a sheet
/// (the core's draft `policyForm`): the words, an option (with the chats it got), a new option.
fn policy_page(c : @ui.Ctx, core : Core, here : Here, station : String) -> Unit {
  let t = @sf.theme()
  let s = station_of(core, here, station)
  let view = if flag(s, "online") { field(field(s, "overview"), "automaticDecisions") } else { None }
  let policy = field(view, "policy")
  let blocks : Array[() -> Unit] = [
    fn() { top_back(c, core, tr("web-pages.automaticDecisions.completion")) },
    fn() { large_title(c, tr("web-pages.archivePolicy.title"), about=tr("web-pages.archivePolicy.textLead")) },
  ]
  if policy is Some(Object(_)) && flag(view, "canEdit") {
    let form = match policy_forms.get(station) {
      Some(f) => f
      None => {
        profile_forms.val += 1
        let f = "mbui-policy-" + profile_forms.val.to_string()
        policy_forms[station] = f
        // (opened once the frame's builds are over: the build that first comes to it alone)
        c.tell("policy-open/" + f, fn() {
          act(core, tr("web-pages.archivePolicy.readAction"), "automaticDecisions.policy.open", obj([("station", str(station)), ("form", str(f)), ("input", obj([]))]))
        })
        f
      }
    }
    let call = fn(action : String, input : Array[(String, Json)], then : (Json) -> Unit) {
      (core.call)("automaticDecisions.policy." + action, obj([("station", str(station)), ("form", str(form)), ("input", obj(input))]), fn(r) {
        match r {
          Ok(v) => then(v)
          Err(e) =>
            (core.say)(fill("android-misc.act.failed", [("what", tr("web-pages.archivePolicy.editAction")), ("error", error_text(e))]))
        }
      })
    }
    let d = (core.topic)("policyForm", { "station": str(station), "form": str(form) }).value
    let busy = !(d is Some(Object(_))) || flag(d, "pending")
    let saving = is_doing(core, ["automaticDecisions.policy.save"], [("station", station), ("form", form)])
    let save = fn() {
      @sf.close_presented()
      act(
        core,
        tr("web-pages.archivePolicy.saveAction"),
        "automaticDecisions.policy.save",
        obj([("station", str(station)), ("form", str(form)), ("input", obj([]))]),
        done=tr("web-pages.archivePolicy.saved"),
      )
    }
    let cancel = fn() {
      @sf.close_presented()
      call("edit", [("reset", Json::boolean(true))], fn(_) {  })
    }
    // an option of the station's (by its id), else a new one (by its draft key), else the policy's words
    let sheet_of = fn(id : String, key : String, ov : Json?) {
      profile_forms.val += 1
      let serial = profile_forms.val.to_string()
      let filled : Map[String, Bool] = Map([])
      let title = if id == "" && key == "" {
        tr("web-pages.archivePolicy.title")
      } else {
        match ov {
          Some(_) => text(ov, "name")
          None => tr("web-pages.archivePolicy.newOption")
        }
      }
      // the library's panel, as tall as most of the window, what it holds at its own sides
      @sf.panel(title, from=Unanchored, tall=0.85, fn(c, _) {
        let t = @sf.theme()
        let d = (core.topic)("policyForm", { "station": str(station), "form": str(form) }).value
        guard d is Some(Object(_)) else { return }
        let field_in = fn(part : String, value : String, placeholder : String, lines : Int) -> String {
          let k = "policy/" + serial + "/" + part
          if !filled.contains(part) {
            filled[part] = true
            field_of(k).set(value)
          }
          let mut words = value
          c.box(w=Fill(1.0), padx=12.0, pady=10.0, radius=12.0, bg=t.p.card, border=1.0, border_color=t.p.line, fn() {
            words = c.editor(
              k,
              field=field_of(k),
              placeholder~,
              font_size=15.0,
              max_lines=lines,
              plain=true,
              line=21.0,
              color=t.p.text,
              placeholder_color=t.p.subtle,
              caret_color=t.p.accent,
              enter_sends=lines == 1,
            ).text
          })
          |> ignore
          words
        }
        let tools = fn(remove : (() -> Unit)?) {
          c.box(dir=Row, w=Fill(1.0), pt=4.0, pb=24.0, gap=8.0, align=ACenter, fn() {
            match remove {
              Some(r) => if tap_text(c, "policy-remove", tr("web-pages.archivePolicy.remove"), color=t.p.red, size=14.0) { r() }
              None => ()
            }
            c.spacer()
            if @sf.button(c, tr("web-pages.archivePolicy.cancel"), key="policy-cancel") {
              c.blur()
              cancel()
            }
            if @sf.button(c, tr("web-pages.archivePolicy.save"), key="policy-save", tone=Primary, disabled=!flag(d, "dirty")) {
              c.blur()
              save()
            }
          })
          |> ignore
        }
        if id == "" && key == "" {
          c.box(w=Fill(1.0), padx=20.0, gap=12.0, fn() {
            c.text(tr("web-pages.archivePolicy.textLead"), size=t.t.meta, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
            let words = field_in("policy", text(d, "policy"), tr("web-pages.archivePolicy.title"), 8)
            if words != text(d, "policy") {
              call("edit", [("policy", str(words))], fn(_) {  })
            }
            tools(None)
          })
          |> ignore
          return
        }
        let o = items(d, "options").iter().find_first(fn(x) {
          if key != "" {
            text(Some(x), "key") == key
          } else {
            text(Some(x), "id") == id
          }
        })
        guard o is Some(oj) else { return }
        let ov2 = Some(oj)
        let okey = text(ov2, "key")
        c.box(w=Fill(1.0), h=Fill(1.0), fn() {
          scroll_page(c, "policy-option/" + serial, [
            fn() {
              c.box(w=Fill(1.0), padx=20.0, gap=12.0, fn() {
                let n = field_in("name", text(ov2, "name"), tr("web-pages.archivePolicy.name"), 1)
                if n != text(ov2, "name") {
                  call("edit", [("option", str(okey)), ("name", str(n))], fn(_) {  })
                }
                let r = field_in("rubric", text(ov2, "rubric"), tr("web-pages.archivePolicy.rubric"), 3)
                if r != text(ov2, "rubric") {
                  call("edit", [("option", str(okey)), ("rubric", str(r))], fn(_) {  })
                }
                let i = @sf.segmented(
                  c,
                  "policy-archive/" + serial,
                  [tr("web-pages.archivePolicy.archive"), tr("web-pages.archivePolicy.keep")],
                  if flag(ov2, "archive") { 0 } else { 1 },
                )
                if (i == 0) != flag(ov2, "archive") {
                  call("edit", [("option", str(okey)), ("archive", Json::boolean(i == 0))], fn(_) {  })
                }
                if count(ov, "count") > 0 {
                  c.text(fill("web-pages.archivePolicy.chats", [("days", count(policy, "days").to_string())]), size=t.t.meta, color=t.p.muted, w=Fill(1.0), line=18.0)
                  |> ignore
                }
              })
              |> ignore
            },
            fn() {
              if count(ov, "count") > 0 {
                c.box(w=Fill(1.0), pt=8.0, fn() {
                  list_card(c, fn() {
                    for ch in items(ov, "chats") {
                      if list_row(c, key="policy-chat/" + text(Some(ch), "session"), fn() {
                          c.text(text(Some(ch), "title"), style=row_title_words.then(@ui.text_style(size=Ui))) |> ignore
                          chevron(c)
                        }) {
                        cancel()
                        (core.open_chat)(station, text(Some(ch), "session"), text(Some(ch), "title"))
                      }
                    }
                  })
                })
                |> ignore
              }
            },
            fn() {
              c.box(w=Fill(1.0), padx=20.0, fn() {
                tools(
                  if key == "" {
                    Some(fn() {
                      @sf.close_presented()
                      call("edit", [("remove", str(okey))], fn(_) {
                        act(core, tr("web-pages.archivePolicy.saveAction"), "automaticDecisions.policy.save", obj([("station", str(station)), ("form", str(form)), ("input", obj([]))]), done=tr("web-pages.archivePolicy.saved"))
                      })
                    })
                  } else {
                    None
                  },
                )
              })
              |> ignore
            },
          ])
        })
        |> ignore
      })
    }
    // back to the station's first: what an earlier sheet left unsaved is gone
    let open_one = fn(id : String, ov : Json?) {
      call("edit", [("reset", Json::boolean(true))], fn(_) { sheet_of(id, "", ov) })
    }
    let add = fn(archive : Bool) {
      call("edit", [("reset", Json::boolean(true))], fn(_) {
        call("edit", [("add", Json::boolean(archive))], fn(made) {
          let opts = items(Some(made), "options")
          match opts.last() {
            Some(o) => sheet_of("", text(Some(o), "key"), None)
            None => ()
          }
        })
      })
    }
    blocks.push(fn() {
      c.box(dir=Row, w=Fill(1.0), pr=20.0, align=ACenter, fn() {
        c.box(w=Fill(1.0), fn() { page_note(c, tr("web-pages.archivePolicy.textLead")) }) |> ignore
        doing_mark(c, saving, failed_of(core, ["automaticDecisions.policy.save"], [("station", station), ("form", form)]), inline=true)
      })
      |> ignore
    })
    blocks.push(fn() {
      list_card(c, fn() {
        if list_row(c, key=if busy { "" } else { "policy-text" }, fn() {
            c.text(text(policy, "text"), size=t.t.ui, color=t.p.text, w=Fill(1.0), line=22.0) |> ignore
          }) {
          open_one("", None)
        }
      })
    })
    for archive in [true, false] {
      blocks.push(fn() {
        section_header(c, tr(if archive { "web-pages.archivePolicy.archive" } else { "web-pages.archivePolicy.keep" }), start=S6)
      })
      blocks.push(fn() {
        list_card(c, fn() {
          for o in items(policy, "options").filter(fn(x) { flag(Some(x), "archive") == archive }) {
            let ov = Some(o)
            if list_row(c, key=if busy { "" } else { "policy-option/" + text(ov, "id") }, fn() {
                c.box(w=Fill(1.0), gap=3.0, fn() {
                  c.text(text(ov, "name"), size=t.t.body, color=t.p.text, w=Fill(1.0), line=21.0) |> ignore
                  c.text(text(ov, "rubric"), size=t.t.meta, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
                })
                |> ignore
                c.text(count(ov, "count").to_string(), size=t.t.meta, color=t.p.muted, wrap=false) |> ignore
              }) {
              open_one(text(ov, "id"), ov)
            }
          }
          if list_row(c, key=if busy { "" } else { "policy-add/" + archive.to_string() }, fn() {
              row_title(c, tr("web-pages.archivePolicy.add"), color=@sf.link_ink())
            }) {
            add(archive)
          }
        })
      })
    }
    blocks.push(fn() {
      c.box(w=Fill(1.0), pl=24.0, pr=24.0, pt=4.0, pb=10.0, fn() {
        c.text(
          join([text(policy, "changeText"), text(policy, "summaryText")], " · "),
          size=t.t.meta,
          color=if count(policy, "failed") > 0 { t.p.red } else { t.p.muted },
          w=Fill(1.0),
          line=18.0,
        )
        |> ignore
      })
      |> ignore
    })
  } else {
    blocks.push(fn() {
      page_note(
        c,
        tr(
          if !flag(s, "online") {
            "web-pages.automaticDecisions.offlineNote"
          } else if view is Some(Object(_)) && !flag(view, "canEdit") {
            "web-pages.automaticDecisions.adminOnly"
          } else {
            "web-pages.automaticDecisions.upgrade"
          },
        ),
      )
    })
  }
  blocks.push(fn() { gap(c, 30.0) })
  scroll_page(c, "auto-policy/" + station, blocks)
}

///|
/// The drafts a decisions' page opened, dropped as it is left.
fn decisions_left(core : Core, route : Route) -> Unit {
  match route {
    AutoCompletion => {
      for station, form in decision_forms {
        act(core, tr("web-pages.automaticDecisions.configAction"), "automaticDecisions.form.drop", obj([("station", str(station)), ("form", str(form)), ("input", obj([]))]))
      }
      decision_forms.clear()
    }
    AutoPolicy(station) =>
      match policy_forms.get(station) {
        Some(form) => {
          policy_forms.remove(station)
          act(core, tr("web-pages.archivePolicy.closeAction"), "automaticDecisions.policy.drop", obj([("station", str(station)), ("form", str(form)), ("input", obj([]))]))
        }
        None => ()
      }
    _ => ()
  }
}

// ---------------------------------------------------------------------------
// 下方栏

///|
/// How many places a bar holds (BAR_SIZE).
pub let bar_size : Int = 4

///|
/// Every place, in the picker's order (Places.kt PLACES).
// kept across runs: a table of constants, never written
pub let all_places : Array[String] = ["chats", "decisions", "files", "stations", "profiles", "connects", "usage", "archive"]

///|
/// What settings' row says of the bars (barsValue): how many, or the one bar's places.
pub fn bars_value(core : Core) -> String {
  let (sets, _) = (core.bars)()
  if sets.length() > 1 {
    fill("android-misc.bar.count", [("n", sets.length().to_string())])
  } else {
    join(sets[0].map(fn(p) { tr("android-misc.bar.place." + p) }), tr("android-misc.bar.sep"))
  }
}

///|
/// The bars kept whole (BarSettings.kt save): an empty one dropped, the one in view still the same bar after it.
pub fn save_bars(core : Core, sets : Array[Array[String]], current : Int) -> Unit {
  let mut cur = current
  let kept : Array[Array[String]] = []
  for i, s in sets {
    if s.length() == 0 {
      if i < current {
        cur -= 1
      }
    } else {
      kept.push(s)
    }
  }
  if kept.length() > 0 {
    (core.set_bars)(kept, if cur < 0 { 0 } else if cur >= kept.length() { kept.length() - 1 } else { cur })
  }
}

///|
/// A bar just made on 下方栏's page (sfdesk bars.mbt), empty until a place is added (the core keeps no empty bar): let
/// go of as the page is left.
pub let bar_adding : Ref[Bool] = Ref(false)

///|
/// How far a place held on 下方栏's page is moved along its bar (BarCard's `dx`: the finger's way past the slop), by
/// its bar and its name, while a finger has it.
pub let bar_moves : Map[String, Double] = {}

// ---------------------------------------------------------------------------
// 存储空间 (what this device keeps)

///|
/// What the core keeps of each chat (its messages, the files opened in it) and of the drives' files, and the files of
/// no chat known (`cache.usage`), read as the page opens and again after a deletion.
priv struct Kept {
  mut chats : Array[Json]?
  /// the bytes of the drives' files kept (drive.read's `keep`)
  mut drive : Double
  /// the files of no chat known (`loose`)
  mut loose : Array[Json]
  mut asked : Int
  mut read : Int
}

///|
let kept : Kept = { chats: None, drive: 0.0, loose: [], asked: 0, read: -1 }

///|
/// The chats' kept data asked of the core again.
fn kept_read(c : @ui.Ctx, core : Core) -> Unit {
  if kept.read == kept.asked {
    return
  }
  kept.read = kept.asked
  // (asked once the frame's builds are over: the build that first comes to it alone)
  c.tell("cache.usage", fn() {
    (core.call)("cache.usage", obj([]), fn(r) {
      kept.chats = Some(
        match r {
          Ok(v) => items(Some(v), "chats")
          Err(_) => []
        },
      )
      kept.drive = match r {
        Ok(v) => number(Some(v), "drive")
        Err(_) => 0.0
      }
      kept.loose = match r {
        Ok(v) => items(Some(v), "loose")
        Err(_) => []
      }
    })
  })
}

///|
/// What 本机缓存's row in the settings' list says (SettingsHome.kt: KeptFiles.read's total): the chats' kept data in
/// all, once the core has said it ("" until then).
pub fn kept_said(c : @ui.Ctx, core : Core) -> String {
  kept_read(c, core)
  match kept.chats {
    Some(chats) => size_words(chats.fold(init=0.0, fn(s, x) { s + number(Some(x), "bytes") }))
    None => ""
  }
}

///|
/// The bytes kept of `files` (a chat's, or those of no chat).
fn files_bytes(files : Array[Json]) -> Double {
  files.fold(init=0.0, fn(s, f) { s + number(Some(f), "bytes") })
}

///|
/// What is kept of a chat: its messages and the files opened in it.
fn chat_bytes(x : Json) -> Double {
  number(Some(x), "bytes") + files_bytes(items(Some(x), "files"))
}

///|
/// A size in bytes in words (fileSize).
fn size_words(n : Double) -> String {
  let one = fn(x : Double) { ((x * 10.0).round() / 10.0).to_string() }
  if n < 1024.0 {
    n.to_int().to_string() + " B"
  } else if n < 1024.0 * 1024.0 {
    one(n / 1024.0) + " KB"
  } else if n < 1024.0 * 1024.0 * 1024.0 {
    one(n / 1024.0 / 1024.0) + " MB"
  } else {
    one(n / 1024.0 / 1024.0 / 1024.0) + " GB"
  }
}

///|
/// How long ago `at` was, in the app's words (KeptFiles.kt since): just now, minutes, hours, days.
fn since_words(now : Double, at : Double) -> String {
  let minutes = ((now - at) / 60000.0).floor().to_int()
  if minutes < 1 {
    tr("android-settings.files.justNow")
  } else if minutes < 60 {
    fill("android-settings.files.minutes", [("n", minutes.to_string())])
  } else if minutes < 24 * 60 {
    fill("android-settings.files.hours", [("n", (minutes / 60).to_string())])
  } else {
    fill("android-settings.files.days", [("n", (minutes / (24 * 60)).to_string())])
  }
}

///|
/// A row of a size (SizeRow): what, a line under it, its size; tapped when `key` is given; `piece`: a piece of its card
/// (list_row).
fn size_row(
  c : @ui.Ctx,
  key : String,
  title : String,
  sub : String,
  size : Double,
  more? : Bool = false,
  piece? : (Bool, Bool),
) -> Bool {
  let t = @sf.theme()
  list_row(c, key~, piece?, fn() {
    // its size and chevron by its title, what it holds under them as wide as the row
    row_lines(c, title, sub, end=fn() {
      c.text(size_words(size), size=t.t.meta, color=t.p.muted, wrap=false) |> ignore
      if more {
        chevron(c)
      }
    })
  })
}

///|
/// What this device keeps (KeptFilesScreen): by chat, what the core keeps of each (its messages, its transcripts, the
/// files opened in it), each to look into; then what is of no chat: files of no chat known, the drives' files opened
/// (`drive.kept.clear`); or everything. (The Android app also lists its web pages' cache, update packages, temporary
/// files and the core's own data: this app keeps none of those apart.)
fn kept_page(c : @ui.Ctx, core : Core) -> Unit {
  let t = @sf.theme()
  kept_read(c, core)
  let blocks : Array[() -> Unit] = [
    fn() { top_back(c, core, tr("android-settings.title")) },
    fn() { large_title(c, tr("android-settings.files.title")) },
    fn() { page_note(c, tr("android-settings.files.note")) },
  ]
  match kept.chats {
    None => blocks.push(fn() { waiting_rows(c) })
    Some(chats) => {
      let loose = kept.loose
      let total = chats.fold(init=kept.drive + files_bytes(loose), fn(s, x) { s + chat_bytes(x) })
      blocks.push(fn() {
        section_header(c, tr("android-settings.files.byChat"), trailing=fill("android-settings.files.total", [("size", size_words(total))]), start=S6)
      })
      if chats.length() == 0 {
        blocks.push(fn() { page_note(c, tr("android-settings.files.none")) })
      } else {
        // a block each, one card's pieces: of many chats only the rows in view are laid out (one block of them all was
        // built whole each frame, every row's words with it)
        let n = chats.length()
        for i, x in chats {
          blocks.push(fn() {
            let xv = Some(x)
            let title = match text(xv, "title") {
              "" => fill("android-settings.files.untitled", [("n", count(xv, "thread").to_string())])
              s => s
            }
            let files = items(xv, "files")
            let messages = size_words(number(xv, "bytes"))
            let sub = if files.length() == 0 {
              fill("android-settings.files.chat.messages", [("size", messages)])
            } else {
              fill("android-settings.files.chat.both", [
                ("size", messages),
                ("n", files.length().to_string()),
                ("files", size_words(files_bytes(files))),
              ])
            }
            if size_row(
                c,
                "kept/" + text(xv, "station") + "/" + count(xv, "thread").to_string(),
                title,
                sub,
                chat_bytes(x),
                more=true,
                piece=(i == 0, i == n - 1),
              ) {
              (core.push)(KeptChat(text(xv, "station"), count(xv, "thread")))
            }
          })
        }
      }
      // what is of no chat (KeptFiles.kt 其他): files of no chat known, the drives' files opened (文件浏览), each to
      // delete when there are some
      blocks.push(fn() { section_header(c, tr("android-settings.files.other"), start=S6) })
      blocks.push(fn() {
        list_card(c, fn() {
          if loose.length() > 0 &&
            size_row(
              c,
              "kept-loose",
              tr("android-settings.files.loose"),
              fill("android-settings.files.count", [("n", loose.length().to_string())]),
              files_bytes(loose),
              more=true,
            ) {
            (core.push)(KeptChat("", -1))
          }
          let drive = kept.drive
          if size_row(c, if drive > 0.0 { "kept-drive" } else { "" }, tr("android-settings.files.drive"), tr("android-settings.files.drive.sub"), drive) {
            confirm(tr("android-settings.files.drive"), tr("android-settings.files.drive.text"), tr("android-settings.files.clear.action"), danger=true, fn() {
              (core.call)("drive.kept.clear", obj([]), fn(_) { kept.asked += 1 })
            })
          }
        })
      })
      if total > 0.0 {
        blocks.push(fn() {
          list_card(c, fn() {
            if list_row(c, key="kept-all", fn() { row_title(c, tr("android-settings.files.clearAll"), color=t.p.red) }) {
              confirm(
                tr("android-settings.files.clearAll.title"),
                fill("android-settings.files.clearAll.text", [("size", size_words(total))]),
                tr("android-settings.files.clear.action"),
                danger=true,
                fn() {
                  for x in chats {
                    (core.call)("cache.clear", obj([("station", str(text(Some(x), "station"))), ("thread", Json::number(number(Some(x), "thread")))]), fn(_) {
                      kept.asked += 1
                    })
                  }
                  kept_files_clear(core, loose)
                  if kept.drive > 0.0 {
                    (core.call)("drive.kept.clear", obj([]), fn(_) { kept.asked += 1 })
                  }
                },
              )
            }
          })
        })
      }
    }
  }
  blocks.push(fn() { gap(c, 30.0) })
  scroll_page(c, "kept", blocks)
}

///|
/// Files kept let go, each (`cache.file.clear`), of no chat known: by the station each says.
fn kept_files_clear(core : Core, files : Array[Json]) -> Unit {
  for f in files {
    kept_file_clear(core, text(Some(f), "station"), f)
  }
}

///|
/// A file kept of a chat on `station` let go (`cache.file.clear`): read again from its station when opened.
fn kept_file_clear(core : Core, station : String, f : Json) -> Unit {
  let fv = Some(f)
  (core.call)("cache.file.clear", obj([("station", str(station)), ("key", str(text(fv, "key"))), ("name", str(text(fv, "name")))]), fn(_) {
    kept.asked += 1
  })
}

///|
/// A file kept (KeptChatScreen's row): its name, how much and when it was last opened (未下载完成 when only a part of
/// it came), deleted by its bin (a 36 circle, its 18 icon muted); a piece of its card (list_row).
fn kept_file_row(c : @ui.Ctx, core : Core, station : String, f : Json, piece : (Bool, Bool)) -> Unit {
  let t = @sf.theme()
  let fv = Some(f)
  let name = text(fv, "name")
  let bytes = number(fv, "bytes")
  let sub = if bytes < number(fv, "size") {
    fill("android-settings.files.partial", [("size", size_words(bytes))])
  } else {
    fill("android-settings.files.meta", [("size", size_words(bytes)), ("opened", since_words((core.now)(), number(fv, "opened")))])
  }
  list_row(c, key="", piece~, fn() {
    // its bin by its name, how much and when under them as wide as the row
    row_lines(c, name, sub, end=fn() {
      let id = c.id("kept-file/" + station + "/" + text(fv, "key") + "/" + name)
      let b = c.box(style=kept_bin, id~, fn() {
        @sf.icon(c, "trash", size=18.0, color=t.p.muted) |> ignore
        // clip(CircleShape).clickable
        @motion.ripple(c, id, 18.0)
      })
      c.semantics(b, Button, id~, label=tr("android-settings.files.clear.action") + "「" + name + "」")
      if hit(c, id) {
        kept_file_clear(core, station, f)
      }
    })
  })
  |> ignore
}

///|
/// A kept file's bin (KeptFiles.kt: a 36 circle, its icon in its middle).
// kept across runs: a value (no field of it changes)
let kept_bin : @ui.Style = @ui.css("w=S9 h=S9 radius=Full align=ACenter justify=JCenter")

///|
/// A chat's (KeptChatScreen): what is kept of its messages, deleted when asked (`cache.clear`: read again from its
/// station when it is opened), and the files opened in it, each to delete; or all of it. Station "": the files of no
/// chat known.
fn kept_chat_page(c : @ui.Ctx, core : Core, station : String, thread : Int) -> Unit {
  let t = @sf.theme()
  kept_read(c, core)
  let loose = station == ""
  let chat = match kept.chats {
    Some(a) if !loose => a.iter().find_first(fn(x) { text(Some(x), "station") == station && count(Some(x), "thread") == thread })
    _ => None
  }
  let files = if loose { kept.loose } else { items(chat, "files") }
  let blocks : Array[() -> Unit] = [
    fn() { top_back(c, core, tr("android-settings.files.title")) },
    fn() { large_title(c, if loose { tr("android-settings.files.loose") } else { text(chat, "title") }) },
  ]
  let clear = fn() {
    match chat {
      Some(_) =>
        (core.call)("cache.clear", obj([("station", str(station)), ("thread", Json::number(thread.to_double()))]), fn(_) {
          kept.asked += 1
        })
      None => kept_files_clear(core, files)
    }
  }
  if kept.chats is None {
    blocks.push(fn() { waiting_rows(c) })
  } else {
    let messages = number(chat, "bytes")
    if chat is Some(_) {
      blocks.push(fn() {
        list_card(c, fn() {
          if size_row(c, if messages > 0.0 { "kept-messages" } else { "" }, tr("android-settings.files.messages"), tr("android-settings.files.messages.text"), messages) {
            confirm(tr("android-settings.files.messages"), tr("android-settings.files.messages.clear"), tr("android-settings.files.clear.action"), danger=true, fn() {
              (core.call)("cache.clear", obj([("station", str(station)), ("thread", Json::number(thread.to_double()))]), fn(_) {
                kept.asked += 1
              })
            })
          }
        })
      })
    }
    if files.length() > 0 {
      blocks.push(fn() {
        section_header(
          c,
          tr("android-settings.files.files"),
          trailing=fill("android-settings.files.filesTotal", [("n", files.length().to_string()), ("size", size_words(files_bytes(files)))]),
          start=S6,
        )
      })
      // a block each, one card's pieces (as the chats' on 本机缓存): of many only those in view laid out
      let n = files.length()
      for i, f in files {
        blocks.push(fn() { kept_file_row(c, core, if loose { text(Some(f), "station") } else { station }, f, (i == 0, i == n - 1)) })
      }
    }
    let all = messages + files_bytes(files)
    if all > 0.0 {
      blocks.push(fn() {
        list_card(c, fn() {
          if list_row(c, key="kept-chat-all", fn() { row_title(c, tr("android-settings.files.clearChat"), color=t.p.red) }) {
            confirm(
              tr("android-settings.files.clearChat"),
              fill("android-settings.files.clearChat.text", [("size", size_words(all))]),
              tr("android-settings.files.clear.action"),
              danger=true,
              clear,
            )
          }
        })
      })
    }
  }
  blocks.push(fn() { gap(c, 30.0) })
  scroll_page(c, "kept/" + station + "/" + thread.to_string(), blocks)
}

///|
/// A station's rule's draft (`decisionForm`), opened once (by the frame's builds' end) and kept by station: the
/// phone's completion page's and the desktop's (src/sfdesk automatic_decisions.mbt).
pub fn decision_form(c : @ui.Ctx, core : Core, station : String) -> String {
  match decision_forms.get(station) {
    Some(f) => f
    None => {
      profile_forms.val += 1
      let f = "mbui-decision-" + profile_forms.val.to_string()
      decision_forms[station] = f
      // (opened once the frame's builds are over: the build that first comes to it alone)
      c.tell("decision-open/" + f, fn() {
        act(core, tr("web-pages.automaticDecisions.configAction"), "automaticDecisions.form.open", obj([("station", str(station)), ("form", str(f)), ("input", obj([]))]))
      })
      f
    }
  }
}
