// The rest of settings' pages (the Android app's settings module): the automatic decisions (AutomaticDecisions.kt: the
// rule's page, each station's settings of it, a station's archive policy and its options), this device's bottom bars
// (BarSettings.kt), what this device keeps (KeptFiles.kt), the changelog (Changelog.kt), the prices the usage is
// counted at (Usage.kt UsagePricesScreen); and, used from the chats' pages, how an agent runs (History.kt
// RunSettingsScreen, run_page) and the machine's own sessions to go on with (NewChat.kt MachineSessions).

// ---------------------------------------------------------------------------
// 自动决策

///|
/// The automatic decisions (AutomaticDecisionsScreen): its rules, each a row to its page (one: completion).
fn decisions_page(c : @ui.Ctx, core : Core) -> Unit {
  scroll_page(c, "auto-decisions", [
    fn() { top_back(c, core, tr("android-settings.title")) },
    fn() { large_title(c, tr("web-pages.automaticDecisions.title")) },
    fn() {
      list_card(c, fn() {
        if list_row(c, key="auto-completion", fn() {
            c.box(w=Fill(1.0), gap=5.0, fn() {
              c.text(tr("web-pages.automaticDecisions.completion"), size=15.0, color=@sf.theme().p.text, w=Fill(1.0), line=21.0)
              |> ignore
              c.text(tr("web-pages.automaticDecisions.completionShort"), size=13.0, color=@sf.theme().p.muted, w=Fill(1.0), line=18.0)
              |> ignore
            })
            |> ignore
            chevron(c)
          }) {
          (core.push)(AutoCompletion)
        }
      })
    },
  ])
}

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
    fn() { large_title(c, tr("web-pages.automaticDecisions.completion")) },
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
  let form = match decision_forms.get(station) {
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
          switch(c, flag(d, "enabled"))
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
        open_sheet(0.5, fn(c, core) {
          let d = (core.topic)("decisionForm", { "station": str(station), "form": str(form) }).value
          sheet_head(c, tr("web-pages.automaticDecisions.model"))
          c.box(w=Fill(1.0), h=Fill(1.0), fn() {
            scroll_page(c, "auto-models/" + station, [
              fn() {
                for m in items(field(field(d, "pick"), "options"), "") {
                  ignore(m)
                }
                for m in items(field(d, "pick"), "options") {
                  let mv = Some(m)
                  if pick_row(
                      c,
                      "auto-pick/" + text(mv, "model"),
                      text(mv, "name"),
                      checked=text(d, "model") == text(mv, "model"),
                      mark=fn() { @sf.maker_mark(c, text(field(mv, "maker"), "id"), "codex", 18.0) |> ignore },
                    ) {
                    close_sheet()
                    act(
                      core,
                      tr("web-pages.automaticDecisions.configAction"),
                      "automaticDecisions.form.edit",
                      obj([("station", str(station)), ("form", str(form)), ("input", obj([("model", str(text(mv, "model")))]))]),
                    )
                  }
                }
              },
            ])
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
                c.text(tr("web-pages.archivePolicy.title"), size=15.0, color=t.p.text, w=Fill(1.0), line=21.0) |> ignore
                c.text(
                  join(
                    [fill("web-pages.archivePolicy.optionCount", [("n", items(policy, "options").length().to_string())]), text(policy, "summaryText")],
                    " · ",
                  ),
                  size=13.0,
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
        if button(c, "auto-save/" + station, tr("web-pages.automaticDecisions.save"), true, busy=saving, enabled=!busy) {
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
let policy_forms : Map[String, String] = Map([])

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
    fn() { large_title(c, tr("web-pages.archivePolicy.title")) },
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
      close_sheet()
      act(
        core,
        tr("web-pages.archivePolicy.saveAction"),
        "automaticDecisions.policy.save",
        obj([("station", str(station)), ("form", str(form)), ("input", obj([]))]),
        done=tr("web-pages.archivePolicy.saved"),
      )
    }
    let cancel = fn() {
      close_sheet()
      call("edit", [("reset", Json::boolean(true))], fn(_) {  })
    }
    // an option of the station's (by its id), else a new one (by its draft key), else the policy's words
    let sheet_of = fn(id : String, key : String, ov : Json?) {
      profile_forms.val += 1
      let serial = profile_forms.val.to_string()
      let filled : Map[String, Bool] = Map([])
      open_sheet(0.85, fn(c, core) {
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
            if button(c, "policy-cancel", tr("web-pages.archivePolicy.cancel"), false) {
              c.blur()
              cancel()
            }
            if button(c, "policy-save", tr("web-pages.archivePolicy.save"), true, enabled=flag(d, "dirty")) {
              c.blur()
              save()
            }
          })
          |> ignore
        }
        if id == "" && key == "" {
          sheet_head(c, tr("web-pages.archivePolicy.title"))
          c.box(w=Fill(1.0), padx=20.0, gap=12.0, fn() {
            c.text(tr("web-pages.archivePolicy.textLead"), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
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
        sheet_head(c, match ov {
          Some(_) => text(ov, "name")
          None => tr("web-pages.archivePolicy.newOption")
        })
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
                let i = seg(
                  c,
                  "policy-archive/" + serial,
                  [tr("web-pages.archivePolicy.archive"), tr("web-pages.archivePolicy.keep")],
                  if flag(ov2, "archive") { 0 } else { 1 },
                  fill=true,
                )
                if (i == 0) != flag(ov2, "archive") {
                  call("edit", [("option", str(okey)), ("archive", Json::boolean(i == 0))], fn(_) {  })
                }
                if count(ov, "count") > 0 {
                  c.text(fill("web-pages.archivePolicy.chats", [("days", count(policy, "days").to_string())]), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0)
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
                          c.text(text(Some(ch), "title"), style=row_title_words.then(@ui.text_style(size=Base))) |> ignore
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
                      close_sheet()
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
            c.text(text(policy, "text"), size=14.0, color=t.p.text, w=Fill(1.0), line=22.0) |> ignore
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
                  c.text(text(ov, "name"), size=15.0, color=t.p.text, w=Fill(1.0), line=21.0) |> ignore
                  c.text(text(ov, "rubric"), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
                })
                |> ignore
                c.text(count(ov, "count").to_string(), size=13.0, color=t.p.muted, wrap=false) |> ignore
              }) {
              open_one(text(ov, "id"), ov)
            }
          }
          if list_row(c, key=if busy { "" } else { "policy-add/" + archive.to_string() }, fn() {
              row_title(c, tr("web-pages.archivePolicy.add"), color=t.p.accent)
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
          size=13.0,
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
let bar_size : Int = 4

///|
/// Every place, in the picker's order (Places.kt PLACES).
// kept across runs: a table of constants, never written
let all_places : Array[String] = ["chats", "decisions", "files", "stations", "profiles", "connects", "usage", "archive"]

///|
/// What settings' row says of the bars (barsValue): how many, or the one bar's places.
fn bars_value(core : Core) -> String {
  let (sets, _) = (core.bars)()
  if sets.length() > 1 {
    fill("android-misc.bar.count", [("n", sets.length().to_string())])
  } else {
    join(sets[0].map(fn(p) { tr("android-misc.bar.place." + p) }), tr("android-misc.bar.sep"))
  }
}

///|
/// The bars kept whole (BarSettings.kt save): an empty one dropped, the one in view still the same bar after it.
fn save_bars(core : Core, sets : Array[Array[String]], current : Int) -> Unit {
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
/// A bar just made on the page, empty until a place is added (the core keeps no empty bar).
let bar_adding : Ref[Bool] = Ref(false)

///|
/// 下方栏 (BarSettingsScreen): this device's bottom bars, each a card of its places (a place taken out with the "−" at its
/// corner, one added from a sheet of them all, moved by the arrows of its sheet); a bar made the one in view, deleted,
/// or a new one made. (The Android app moves a place by holding it and sliding it sideways; here its slot's sheet moves
/// it left or right.)
fn bars_page(c : @ui.Ctx, core : Core) -> Unit {
  let t = @sf.theme()
  let (made, cur) = (core.bars)()
  let sets : Array[Array[String]] = made.copy()
  if bar_adding.val {
    sets.push([])
  }
  let pick_for = fn(i : Int) {
    open_bar_pick(core, i, fn(place) {
      let (now, ncur) = (core.bars)()
      if i >= now.length() {
        bar_adding.val = false
        save_bars(core, now + [[place]], ncur)
      } else {
        save_bars(core, now.mapi(fn(n, s) { if n == i && !s.contains(place) && s.length() < bar_size { s + [place] } else { s } }), ncur)
      }
    })
  }
  let blocks : Array[() -> Unit] = [
    fn() { top_back(c, core, tr("android-settings.title")) },
    fn() { large_title(c, tr("android-misc.bar.title")) },
    fn() { page_note(c, tr("android-misc.bar.note")) },
  ]
  for i, set in sets {
    let is_made = i < made.length()
    blocks.push(fn() {
      c.box(dir=Row, w=Fill(1.0), pl=24.0, pr=24.0, pt=16.0, pb=6.0, align=ACenter, fn() {
        c.text(fill("android-misc.bar.set", [("n", (i + 1).to_string())]), size=13.0, weight=600, color=t.p.text, wrap=false) |> ignore
        if is_made && i == cur {
          c.box(pl=8.0, fn() {
            c.box(padx=7.0, pady=1.0, radius=9.0, bg=t.p.accent_bg, fn() {
              c.text(tr("android-misc.bar.current"), size=11.0, weight=600, color=t.p.accent, wrap=false) |> ignore
            })
            |> ignore
          })
          |> ignore
        }
        c.spacer()
        if is_made && i != cur && tap_text(c, "bar-use/" + i.to_string(), tr("android-misc.bar.use"), size=13.0) {
          save_bars(core, made, i)
        }
        if sets.length() > 1 {
          c.box(pl=10.0, fn() {
            if tap_text(c, "bar-delete/" + i.to_string(), tr("android-misc.bar.delete"), color=t.p.red, size=13.0) {
              if !is_made {
                bar_adding.val = false
              } else {
                let left : Array[Array[String]] = []
                for n, x in made {
                  if n != i {
                    left.push(x)
                  }
                }
                save_bars(core, left, if cur > i || cur >= left.length() { if cur - 1 < 0 { 0 } else { cur - 1 } } else { cur })
              }
            }
          })
          |> ignore
        }
      })
      |> ignore
    })
    blocks.push(fn() { bar_card(c, core, i, set, made.length() == 1 && set.length() == 1, fn() { pick_for(i) }) })
  }
  blocks.push(fn() {
    c.box(w=Fill(1.0), pt=14.0, fn() {
      list_card(c, fn() {
        if list_row(c, key="bar-new", fn() {
            @sf.icon(c, "plus", size=20.0, color=t.p.accent) |> ignore
            row_title(c, tr("android-misc.bar.new"), color=t.p.accent)
          }) {
          bar_adding.val = true
          pick_for(made.length())
        }
      })
    })
    |> ignore
  })
  blocks.push(fn() { page_note(c, tr(if made.length() > 1 { "android-misc.bar.foot.many" } else { "android-misc.bar.foot.one" })) })
  blocks.push(fn() { gap(c, 30.0) })
  scroll_page(c, "bars", blocks)
}

///|
/// A bar's card (BarCard): its places in four slots, each its icon over its name with a "−" at its corner (none on the
/// last place of the only bar), a tap on it its sheet (moved left or right); with room left, a slot that adds one.
fn bar_card(c : @ui.Ctx, core : Core, i : Int, set : Array[String], only : Bool, add : () -> Unit) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), pl=12.0, pr=12.0, pb=10.0, fn() {
    c.box(dir=Row, w=Fill(1.0), padx=4.0, pady=8.0, radius=20.0, bg=t.p.card, fn() {
      for j, key in set {
        let id = c.id("bar-slot/" + i.to_string() + "/" + key)
        if hit(c, id) {
          open_bar_place(core, i, j, set)
        }
        // the slot, and its "−" over it beside (not inside) what a tap on the slot opens: the slot's press does not
        // take the "−"'s
        c.box(w=Fill(1.0), fn() {
          c.box(w=Fill(1.0), pt=12.0, pb=10.0, align=ACenter, id~, fn() {
            c.box(gap=6.0, align=ACenter, fn() {
              c.box(h=Px(30.0), justify=JCenter, fn() { (core.place_icon)(c, key, t.p.text) }) |> ignore
              c.text(tr("android-misc.bar.place." + key), size=12.0, color=t.p.muted, wrap=false) |> ignore
            })
            |> ignore
          })
          |> ignore
          if !only {
            c.layer(align=ACenter, fn() {
              let rid = c.id("bar-remove/" + i.to_string() + "/" + key)
              if hit(c, rid) {
                let (now, ncur) = (core.bars)()
                save_bars(core, now.mapi(fn(n, s) { if n == i { s.filter(fn(p) { p != key }) } else { s } }), ncur)
              }
              // at the icon's top right, 8 above the slot (BarSettings.kt: TopCenter, offset 16, -8)
              c.box(w=Px(20.0), h=Px(20.0), radius=10.0, bg=t.p.chip, tx=16.0, ty=-8.0, align=ACenter, justify=JCenter, id=rid, fn() {
                @sf.icon(c, "minus", size=12.0, color=t.p.muted) |> ignore
              })
              |> ignore
            })
            |> ignore
          }
        })
        |> ignore
      }
      if set.length() < bar_size {
        let aid = c.id("bar-add/" + i.to_string())
        if hit(c, aid) {
          add()
        }
        c.box(w=Fill(1.0), pt=12.0, pb=10.0, radius=16.0, align=ACenter, id=aid, fn() {
          c.box(gap=6.0, align=ACenter, fn() {
            c.box(w=Px(30.0), h=Px(30.0), align=ACenter, justify=JCenter, fn() {
              c.box(w=Px(44.0), h=Px(44.0), radius=22.0, border=1.5, border_color=t.p.line, align=ACenter, justify=JCenter, fn() {
                @sf.icon(c, "plus", size=22.0, color=t.p.subtle) |> ignore
              })
              |> ignore
            })
            |> ignore
            c.text(tr("android-misc.bar.add"), size=12.0, color=t.p.subtle, wrap=false) |> ignore
          })
          |> ignore
        })
        |> ignore
      }
      for _ in 0..<(bar_size - set.length() - 1) {
        c.box(w=Fill(1.0), fn() {  }) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A place on a bar moved left or right (BarSettings' drag and its screen readers' actions).
fn open_bar_place(core : Core, i : Int, j : Int, set : Array[String]) -> Unit {
  let shift = fn(to : Int) {
    close_sheet()
    let (now, ncur) = (core.bars)()
    save_bars(
      core,
      now.mapi(fn(n, s) {
        if n == i && j < s.length() && to >= 0 && to < s.length() {
          let moved = s.copy()
          let p = moved.remove(j)
          moved.insert(to, p)
          moved
        } else {
          s
        }
      }),
      ncur,
    )
  }
  open_sheet(0.3, fn(c, _core) {
    sheet_head(c, tr("android-misc.bar.place." + set[j]))
    if j > 0 && pick_row(c, "bar-left", tr("android-misc.bar.moveLeft")) {
      shift(j - 1)
    }
    if j < set.length() - 1 && pick_row(c, "bar-right", tr("android-misc.bar.moveRight")) {
      shift(j + 1)
    }
  })
}

///|
/// The places to add to bar `i` (openPick): all of them, those in it already greyed (已在这一栏), none when it is full.
fn open_bar_pick(_core : Core, i : Int, picked : (String) -> Unit) -> Unit {
  open_sheet(0.6, fn(c, core) {
    let t = @sf.theme()
    let (now, _) = (core.bars)()
    let set = now.get(i).unwrap_or([])
    let full = set.length() >= bar_size
    c.box(dir=Row, w=Fill(1.0), pl=18.0, pr=18.0, pt=4.0, pb=10.0, align=ACenter, fn() {
      c.text(fill("android-misc.bar.pick.title", [("n", (i + 1).to_string())]), size=17.0, weight=700, color=t.p.text, wrap=false, w=Fill(1.0), line=24.0)
      |> ignore
      c.text(
        if full {
          tr("android-misc.bar.pick.full")
        } else {
          fill("android-misc.bar.pick.left", [("n", (bar_size - set.length()).to_string())])
        },
        size=13.0,
        color=t.p.muted,
        wrap=false,
      )
      |> ignore
    })
    |> ignore
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      scroll_page(c, "bar-pick/" + i.to_string(), [
        fn() {
          for key in all_places {
            let there = set.contains(key)
            if pick_row(
                c,
                "bar-pick/" + key,
                tr("android-misc.bar.place." + key),
                sub=if there { tr("android-misc.bar.pick.there") } else { "" },
                enabled=!there && !full,
                mark=fn() {
                  c.box(w=Px(28.0), h=Px(28.0), align=ACenter, justify=JCenter, opacity=if there || full { 0.4 } else { 1.0 }, fn() {
                    (core.place_icon)(c, key, t.p.text)
                  })
                  |> ignore
                },
              ) {
              close_sheet()
              picked(key)
            }
          }
        },
      ])
    })
    |> ignore
  })
}

// ---------------------------------------------------------------------------
// 存储空间 (what this device keeps)

///|
/// What the core keeps of each chat (`cache.usage`), read as the page opens and again after a deletion.
priv struct Kept {
  mut chats : Array[Json]?
  mut asked : Int
  mut read : Int
}

///|
let kept : Kept = { chats: None, asked: 0, read: -1 }

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
    })
  })
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
/// A row of a size (SizeRow): what, a line under it, its size; tapped when `key` is given.
fn size_row(c : @ui.Ctx, key : String, title : String, sub : String, size : Double, more? : Bool = false) -> Bool {
  let t = @sf.theme()
  list_row(c, key~, fn() {
    row_lines(c, title, sub)
    c.text(size_words(size), size=14.0, color=t.p.muted, wrap=false) |> ignore
    if more {
      chevron(c)
    }
  })
}

///|
/// What this device keeps (KeptFilesScreen): by chat, what the core keeps of each (its messages, its transcripts, the
/// files it keeps), each to delete (`cache.clear`), or everything. (The Android app also lists the files its viewers
/// keep in its cache, its web pages' cache, update packages and temporary files: this app keeps none of its own on the
/// disk, its viewers reading through the core into memory.)
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
      let total = chats.fold(init=0.0, fn(s, x) { s + number(Some(x), "bytes") })
      blocks.push(fn() {
        section_header(c, tr("android-settings.files.byChat"), trailing=fill("android-settings.files.total", [("size", size_words(total))]), start=S6)
      })
      if chats.length() == 0 {
        blocks.push(fn() { page_note(c, tr("android-settings.files.none")) })
      } else {
        blocks.push(fn() {
          list_card(c, fn() {
            for x in chats {
              let xv = Some(x)
              let title = match text(xv, "title") {
                "" => fill("android-settings.files.untitled", [("n", count(xv, "thread").to_string())])
                s => s
              }
              if size_row(
                  c,
                  "kept/" + text(xv, "station") + "/" + count(xv, "thread").to_string(),
                  title,
                  fill("android-settings.files.chat.messages", [("size", size_words(number(xv, "bytes")))]),
                  number(xv, "bytes"),
                  more=true,
                ) {
                (core.push)(KeptChat(text(xv, "station"), count(xv, "thread")))
              }
            }
          })
        })
      }
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
/// A chat's (KeptChatScreen): what is kept of its messages, deleted when asked (`cache.clear`: read again from its
/// station when it is opened).
fn kept_chat_page(c : @ui.Ctx, core : Core, station : String, thread : Int) -> Unit {
  let t = @sf.theme()
  kept_read(c, core)
  let chat = match kept.chats {
    Some(a) => a.iter().find_first(fn(x) { text(Some(x), "station") == station && count(Some(x), "thread") == thread })
    None => None
  }
  let blocks : Array[() -> Unit] = [
    fn() { top_back(c, core, tr("android-settings.files.title")) },
    fn() { large_title(c, text(chat, "title")) },
  ]
  let clear = fn() {
    (core.call)("cache.clear", obj([("station", str(station)), ("thread", Json::number(thread.to_double()))]), fn(_) {
      kept.asked += 1
    })
  }
  match chat {
    Some(_) => {
      let size = number(chat, "bytes")
      blocks.push(fn() {
        list_card(c, fn() {
          if size_row(c, if size > 0.0 { "kept-messages" } else { "" }, tr("android-settings.files.messages"), tr("android-settings.files.messages.text"), size) {
            confirm(tr("android-settings.files.messages"), tr("android-settings.files.messages.clear"), tr("android-settings.files.clear.action"), danger=true, clear)
          }
        })
      })
      if size > 0.0 {
        blocks.push(fn() {
          list_card(c, fn() {
            if list_row(c, key="kept-chat-all", fn() { row_title(c, tr("android-settings.files.clearChat"), color=t.p.red) }) {
              confirm(
                tr("android-settings.files.clearChat"),
                fill("android-settings.files.clearChat.text", [("size", size_words(size))]),
                tr("android-settings.files.clear.action"),
                danger=true,
                clear,
              )
            }
          })
        })
      }
    }
    None => if kept.chats is None { blocks.push(fn() { waiting_rows(c) }) }
  }
  blocks.push(fn() { gap(c, 30.0) })
  scroll_page(c, "kept/" + station + "/" + thread.to_string(), blocks)
}

// ---------------------------------------------------------------------------
// 更新日志

///|
/// The changelog's tab chosen ("" the first), and whether the news was said seen.
priv struct ChangelogState {
  mut part : String
  mut seen : Bool
}

///|
let changelog_state : ChangelogState = { part: "", seen: false }

///|
/// What changed in still.fail (ChangelogScreen), from the core's `changelog`: a tab a part, by day on cards, each change
/// with where it is and whether this app has it; opened, what the last update brought is read (`changelog.seen`).
fn changelog_page(c : @ui.Ctx, core : Core) -> Unit {
  let t = @sf.theme()
  let topic = (core.topic)("changelog", Map([]))
  let v = topic.value
  if has(v, "news") && !changelog_state.seen {
    changelog_state.seen = true
    // (told once the frame's builds are over)
    c.tell("changelog.seen", fn() { (core.call)("changelog.seen", obj([]), fn(_) {  }) })
  }
  let tabs = items(v, "tabs")
  let at = match tabs.search_by(fn(x) { text(Some(x), "part") == changelog_state.part }) {
    Some(i) => i
    None => 0
  }
  let tab = tabs.get(at)
  let blocks : Array[() -> Unit] = [
    fn() { top_back(c, core, tr("android-settings.title")) },
    fn() { large_title(c, tr("android-settings.changelog.title")) },
  ]
  if has(v, "build") {
    blocks.push(fn() { page_note(c, fill("android-settings.changelog.build", [("build", count(v, "build").to_string())])) })
  }
  if tab is Some(_) {
    blocks.push(fn() {
      c.box(w=Fill(1.0), pl=16.0, pr=16.0, pt=4.0, pb=2.0, fn() {
        let i = seg(c, "changelog-tabs", tabs.map(fn(x) { text(Some(x), "label") }), at, fill=true, height=34.0)
        if i != at {
          changelog_state.part = text(Some(tabs[i]), "part")
        }
      })
      |> ignore
    })
  }
  if v is None || flag(v, "loading") {
    blocks.push(fn() {
      waiting_cards(
        c,
        error=match topic.error {
          Some(e) => error_text(e)
          None => ""
        },
      )
    })
  } else if has(v, "error") {
    blocks.push(fn() {
      c.box(w=Fill(1.0), padx=24.0, pady=8.0, fn() {
        c.text(text(v, "error"), size=14.0, color=t.p.red, w=Fill(1.0), line=20.0) |> ignore
      })
      |> ignore
    })
  } else {
    let days = match tab {
      Some(x) => items(Some(x), "days")
      None => []
    }
    if days.length() == 0 {
      blocks.push(fn() {
        c.box(w=Fill(1.0), padx=24.0, pady=8.0, fn() {
          c.text(tr("android-settings.changelog.empty"), size=14.0, color=t.p.muted, w=Fill(1.0), line=20.0) |> ignore
        })
        |> ignore
      })
    }
    for day in days {
      blocks.push(fn() { section_header(c, text(Some(day), "label"), start=S6) })
      blocks.push(fn() {
        list_card(c, fn() {
          for e in items(Some(day), "entries") {
            change_item(c, Some(e))
          }
        })
      })
    }
  }
  blocks.push(fn() { gap(c, 30.0) })
  scroll_page(c, "changelog/" + at.to_string(), blocks)
}

///|
/// One change (Change): each line led by its kind on a small tinted label (the accent's for something new), then its
/// version and what is not out yet (in the accent: an update would bring it).
fn change_item(c : @ui.Ctx, e : Json?) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), padx=16.0, pady=10.0, gap=2.0, fn() {
    for l in items(e, "lines") {
      let lv = Some(l)
      let label = text(lv, "label")
      if label == "" {
        c.text(text(lv, "text"), size=15.0, color=t.p.text, w=Fill(1.0), line=21.0) |> ignore
      } else {
        let fresh = text(lv, "kind") == "new"
        c.box(dir=Row, w=Fill(1.0), gap=6.0, fn() {
          c.box(padx=6.0, radius=6.0, bg=if fresh { t.p.accent_bg } else { t.p.chip }, fn() {
            c.text(label, size=13.0, color=if fresh { t.p.accent } else { t.p.muted }, wrap=false, line=19.0) |> ignore
          })
          |> ignore
          c.text(text(lv, "text"), size=15.0, color=t.p.text, w=Fill(1.0), line=21.0) |> ignore
        })
        |> ignore
      }
    }
    c.box(dir=Row, w=Fill(1.0), gap=10.0, fn() {
      c.text(text(e, "versionName"), size=13.0, color=t.p.muted, wrap=false, line=18.0) |> ignore
      if text(e, "note") != "" {
        c.text(text(e, "note"), size=13.0, color=if field(e, "has") is Some(False) { t.p.accent } else { t.p.muted }, wrap=false, line=18.0)
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

// ---------------------------------------------------------------------------
// 价格

///|
/// The prices the usage is counted at (UsagePricesScreen): each station's table, a row a model (its rates as the core
/// words them).
fn prices_page(c : @ui.Ctx, core : Core, here : Here, days : Int) -> Unit {
  let t = @sf.theme()
  let topic = (core.topic)("usage", { "scope": str(here.workspace), "days": Json::number(days.to_double()) })
  let v = topic.value
  let blocks : Array[() -> Unit] = [
    fn() { top_back(c, core, tr("android-misc.usage.title")) },
    fn() { large_title(c, tr("android-misc.usage.prices")) },
    fn() { page_note(c, tr("android-misc.usage.prices.note")) },
  ]
  match v {
    None =>
      blocks.push(fn() {
        waiting_cards(
          c,
          error=match topic.error {
            Some(e) => fill("android-misc.usage.prices.loadFailed", [("error", error_text(e))])
            None => ""
          },
        )
      })
    Some(_) => {
      let tables = items(v, "prices")
      let wait = field(v, "wait")
      if tables.length() == 0 && note_waits(wait) {
        blocks.push(fn() { waiting_cards(c, count=2, failing=failing_of(wait)) })
      } else if tables.length() == 0 {
        blocks.push(fn() { page_note(c, tr("android-misc.usage.prices.none")) })
      }
      for table in tables {
        let tv = Some(table)
        blocks.push(fn() {
          card(c, fn() {
            c.text(text(tv, "station"), size=16.0, weight=600, color=t.p.text, w=Fill(1.0), line=22.0) |> ignore
            c.box(w=Fill(1.0), pt=8.0, pb=20.0, fn() {
              c.text(text(tv, "note"), size=12.0, color=t.p.muted, w=Fill(1.0), line=17.0) |> ignore
            })
            |> ignore
            let rows = items(tv, "rows")
            if rows.length() == 0 {
              c.text(tr("android-misc.usage.prices.noModels"), size=12.0, color=t.p.muted, w=Fill(1.0), line=17.0) |> ignore
            } else {
              // a table: the model, then each rate, the head under a hairline
              let heads = [tr("android-misc.usage.prices.model")] + items(Some(rows[0]), "rates").map(fn(r) { text(Some(r), "label") })
              let line = fn(cells : Array[String], head : Bool) {
                c.box(dir=Row, w=Fill(1.0), pady=6.0, gap=8.0, fn() {
                  for k, cell in cells {
                    c.box(w=Fill(if k == 0 { 1.6 } else { 1.0 }), fn() {
                      c.text(cell, size=13.0, weight=if head { 600 } else { 400 }, color=t.p.text, w=Fill(1.0), line=18.0) |> ignore
                    })
                    |> ignore
                  }
                })
                |> ignore
              }
              line(heads, true)
              c.box(w=Fill(1.0), h=Px(0.5), bg=t.p.line, fn() {  }) |> ignore
              for r in rows {
                line([text(Some(r), "model")] + items(Some(r), "rates").map(fn(x) { text(Some(x), "value") }), false)
              }
            }
          })
          |> ignore
        })
      }
    }
  }
  blocks.push(fn() { gap(c, 30.0) })
  scroll_page(c, "prices/" + days.to_string(), blocks)
}
