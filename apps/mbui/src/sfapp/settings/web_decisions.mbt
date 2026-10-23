// The desktop's 自动决策 (web/src/AutomaticDecisions.tsx) on the library's parts: the decision points, each a row to
// its page; the completion rule's page, a row for each station with its rule's controls at its end.

///|
/// 自动决策 (AutomaticDecisions): the point a decision is made at (the completion of a turn), what it does, how many
/// stations have it on, a row to its page.
fn decisions_page_wide(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let t = @sf.theme()
  let stations = stations_of(core, here).value
  desk_page(c, core, "auto-decisions", tr("web-pages.automaticDecisions.title"), about=tr("web-pages.automaticDecisions.choosePoint"), [
    fn() {
      c.box(style=desk_list, fn() {
        let id = c.id("auto-completion")
        c.cursor(id, Hand)
        if hit(c, id) {
          (core.push)(AutoCompletion)
        }
        c.box(style=desk_list_link, id~, fn() {
          c.box(style=desk_list_text, fn() {
            c.text(tr("web-pages.automaticDecisions.completion"), style=desk_list_title) |> ignore
            c.text(tr("web-pages.automaticDecisions.completionNote"), style=desk_note) |> ignore
          })
          |> ignore
          match stations {
            Some(Array(a)) => {
              let on = a.filter(fn(s) { flag(field(field(field(field(Some(s), "overview"), "automaticDecisions"), "settings"), "completion"), "enabled") }).length()
              c.text(
                if on > 0 {
                  fill("web-pages.automaticDecisions.stationsOn", [("n", on.to_string())])
                } else {
                  tr("web-pages.automaticDecisions.off")
                },
                style=dc_aside,
              )
              |> ignore
            }
            _ => ()
          }
          @sf.icon(c, "chevron-right", size=desk_chevron, color=t.p.muted) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
  ])
}

///|
/// The completion rule's page (AutomaticDecisionCompletion): a row for each station, its rule's controls where it can
/// be set, else why not (offline, older, connecting); a wait while the stations are read.
fn completion_page_wide(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let topic = stations_of(core, here)
  let body : Array[() -> Unit] = []
  match topic.value {
    Some(Array(a)) =>
      body.push(fn() {
        if a.length() == 0 {
          c.text(tr("web-pages.automaticDecisions.addStation"), style=desk_note) |> ignore
        }
        c.box(style=desk_list, fn() {
          for st in a {
            let s = Some(st)
            let view = field(field(s, "overview"), "automaticDecisions")
            if flag(s, "online") && view is Some(Object(_)) {
              completion_station(c, core, s, view)
            } else {
              dc_status(
                c,
                s,
                if !flag(s, "online") {
                  tr("web-pages.automaticDecisions.offline")
                } else if !(field(s, "overview") is Some(Object(_))) {
                  tr("common.connecting")
                } else {
                  tr("web-pages.automaticDecisions.upgrade")
                },
                waiting=flag(s, "online") && !(field(s, "overview") is Some(Object(_))),
              )
            }
          }
        })
        |> ignore
      })
    _ =>
      body.push(fn() {
        match topic.error {
          Some(e) => c.text(error_text(e), style=desk_note) |> ignore
          None => @sf.wait_line(c, tr("common.readingStations"))
        }
      })
  }
  desk_page(
    c,
    core,
    "auto-completion",
    tr("web-pages.automaticDecisions.completion"),
    about=tr("web-pages.automaticDecisions.completionNote"),
    back=tr("web-pages.automaticDecisions.title"),
    // 重新发现模型: every online station's models read again
    actions=fn() {
      if @sf.button(c, tr("web-pages.automaticDecisions.refresh"), key="auto-refresh", tone=Ghost, icon="refresh") {
        c.after_build("auto-refresh", fn() {
          match topic.value {
            Some(Array(a)) =>
              for st in a {
                if flag(Some(st), "online") {
                  act(
                    core,
                    tr("web-pages.automaticDecisions.refreshAction"),
                    "automaticDecisions.refresh",
                    obj([("station", str(text(Some(st), "station")))]),
                    done=tr("web-pages.automaticDecisions.refreshed"),
                  )
                }
              }
            _ => ()
          }
        })
      }
    },
    body,
  )
}

///|
/// A station's row with only what is said of it (its dot, its name, a line; `waiting`: a spinner before it).
fn dc_status(c : @ui.Ctx, s : Json?, words : String, waiting? : Bool = false) -> Unit {
  c.box(style=desk_list_row, fn() {
    @sf.status_dot(c, if flag(s, "online") { "online" } else { "offline" })
    c.box(style=desk_list_text, fn() {
      dc_name(c, s)
      c.box(style=desk_said_line, fn() {
        if waiting {
          c.box(style=dc_spin, fn() { @sf.spinner(c) |> ignore }) |> ignore
        }
        c.text(words, style=desk_note) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A station's name with its mark (StationNamed).
fn dc_name(c : @ui.Ctx, s : Json?) -> Unit {
  let t = @sf.theme()
  c.box(style=desk_named, fn() {
    if @sf.has_station_mark(text(s, "emoji"), text(s, "icon")) {
      @sf.station_mark(c, text(s, "emoji"), text(s, "icon"), desk_mark, t.p.text)
    }
    c.text(text(s, "name"), style=desk_list_title) |> ignore
  })
  |> ignore
}

///|
/// A station's rule (AutomaticDecisionPanel), in the core's draft (`decisionForm`): its name and whether it is on with
/// which model; at its end the model (a dropdown), on or off, 保存 once changed, 立即检查 where the station can; what went
/// wrong under it; its archive policy's row (to its page).
fn completion_station(c : @ui.Ctx, core : Core, s : Json?, view : Json?) -> Unit {
  let t = @sf.theme()
  let station = text(s, "station")
  if !flag(view, "canEdit") {
    dc_status(c, s, tr("web-pages.automaticDecisions.adminOnly"))
    return
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
  guard d is Some(Object(_)) else {
    match topic.error {
      Some(e) => dc_status(c, s, error_text(e))
      None => dc_status(c, s, tr("web-pages.automaticDecisions.readingConfig"), waiting=true)
    }
  }
  let saving = is_doing(core, ["automaticDecisions.form.save"], [("station", station), ("form", form)])
  let reviewing = is_doing(core, ["automaticDecisions.review"], [("station", station)])
  let busy = flag(d, "pending") || saving
  let model_id = text(d, "model")
  let chosen = match items(view, "models").iter().find_first(fn(m) { text(Some(m), "id") == model_id }) {
    Some(m) => text(Some(m), "name")
    None => tr("web-pages.automaticDecisions.noModels")
  }
  let can_review = flag(view, "canReview") && flag(field(field(view, "settings"), "completion"), "enabled") && !flag(d, "dirty")
  c.box(style=desk_list_row, fn() {
    @sf.status_dot(c, "online")
    c.box(style=desk_list_text, fn() {
      dc_name(c, s)
      c.text(
        if flag(d, "enabled") {
          fill("web-pages.automaticDecisions.enabledWith", [("model", chosen)])
        } else {
          tr("web-pages.automaticDecisions.disabled")
        },
        style=desk_note,
      )
      |> ignore
    })
    |> ignore
    c.box(style=dc_controls, fn() {
      match field(d, "pick") {
        Some(Object(_)) as pick => {
          let options = items(pick, "options").map(fn(o) { (text(Some(o), "model"), text(Some(o), "name")) })
          let now = @sf.select(c, "auto-model/" + station, model_id, options, disabled=busy, label=tr("web-pages.automaticDecisions.model"))
          if now != model_id {
            c.after_build("auto-model/" + station, fn() { call("edit", [("model", str(now))]) })
          }
        }
        _ => c.text(chosen, style=dc_aside) |> ignore
      }
      if @sf.switch(c, "auto-enabled/" + station, flag(d, "enabled"), disabled=busy) != flag(d, "enabled") {
        c.after_build("auto-enabled/" + station, fn() { call("edit", [("enabled", Json::boolean(!flag(d, "enabled")))]) })
      }
      if flag(d, "dirty") &&
        @sf.button(c, tr("web-pages.automaticDecisions.save"), key="auto-save/" + station, tone=Primary, busy=saving, disabled=busy) {
        c.after_build("auto-save/" + station, fn() { call("save", []) })
      }
      if can_review &&
        @sf.button(c, tr("web-pages.automaticDecisions.review"), key="auto-review/" + station, tone=Ghost, busy=reviewing, disabled=busy || reviewing) {
        c.after_build("auto-review/" + station, fn() {
          act(
            core,
            tr("web-pages.automaticDecisions.reviewAction"),
            "automaticDecisions.review",
            obj([("station", str(station))]),
            done=tr("web-pages.automaticDecisions.reviewStarted"),
          )
        })
      }
    })
    |> ignore
  })
  |> ignore
  for failed in [
    failed_of(core, ["automaticDecisions.form.save"], [("station", station), ("form", form)]),
    failed_of(core, ["automaticDecisions.review"], [("station", station)]),
  ] {
    match failed {
      Some(why) => c.text(why, style=dc_error) |> ignore
      None => ()
    }
  }
  match field(view, "policy") {
    Some(Object(_)) as policy => {
      let id = c.id("auto-policy/" + station)
      c.cursor(id, Hand)
      if hit(c, id) {
        (core.push)(AutoPolicy(station))
      }
      c.box(style=dc_policy_row, id~, fn() {
        // past the station's dot, lined up with its name
        c.box(style=dc_dot_room, fn() {  }) |> ignore
        c.text(tr("web-pages.archivePolicy.title"), style=desk_list_title) |> ignore
        let summary = text(policy, "summaryText")
        let line = fill("web-pages.archivePolicy.optionCount", [("n", items(policy, "options").length().to_string())]) +
          (if summary == "" { "" } else { " · " + summary })
        c.text(line, style=if count(policy, "failed") > 0 { dc_error_line } else { dc_aside }) |> ignore
        c.spacer()
        @sf.icon(c, "chevron-right", size=desk_chevron, color=t.p.muted) |> ignore
      })
      |> ignore
    }
    _ => ()
  }
}

///|
/// A station's rule's draft (`decisionForm`), opened once (by the frame's builds' end) and kept by station.
fn decision_form(c : @ui.Ctx, core : Core, station : String) -> String {
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

///|
/// (AutomaticDecisions.css.ts note at a row's end: as wide as it is)
// kept across runs: a value (no field of it changes)
let dc_aside : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, wrap=false)

///|
/// (controls: at the row's end, 16 apart)
// kept across runs: a value (no field of it changes)
let dc_controls : @ui.Style = @ui.style(row=true, gap=S4, align=ACenter, justify=JEnd)

///|
/// (error: red, 12, broken anywhere), under the row it is of, past its dot
// kept across runs: a value (no field of it changes)
let dc_error : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Danger, w=Full)

///|
// kept across runs: a value (no field of it changes)
let dc_error_line : @ui.TextStyle = dc_aside.then(@ui.text_style(color=Danger))

///|
/// (policyRow: 40 high at least, its words past the station's dot, lined up with its name)
// kept across runs: a value (no field of it changes)
let dc_policy_row : @ui.Style = desk_list_link.then(@ui.style(min_h=S10))

///|
/// Where a station's row has its dot (the dot's width, the row's gap after it).
// kept across runs: a value (no field of it changes)
let dc_dot_room : @ui.Style = @ui.style(w=@sf.dot_size)

///|
// kept across runs: a value (no field of it changes)
let dc_spin : @ui.Style = @ui.style(pr=S1)
