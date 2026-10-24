// 自动决策 (web/src/AutomaticDecisions.tsx; the narrow app's mobile/AutomaticDecisions.tsx): the decision points, each
// a row to its page, one page in every frame (page_look.mbt); the desktop's completion rule's page, a row for each
// station with its rule's controls at its end.

///|
/// 自动决策 (AutomaticDecisions; the narrow app's AutomaticDecisionsScreen): the point a decision is made at (the
/// completion of a turn), what it does, how many stations have it on (the core's `settings`), a row to its page.
fn decisions_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let said = (core.topic)("settings", { "scope": Json::string(here.workspace) }).value
  look_page(c, core, frame, look, "auto-decisions", @sf.t("web-pages.automaticDecisions.title"), about=@sf.t("web-pages.automaticDecisions.choosePoint"), [
    fn() {
      look_group(c, look, fn() {
        if look_link(
            c,
            look,
            "auto-completion",
            @sf.t("web-pages.automaticDecisions.completion"),
            note=@sf.t(if look == Narrow { "web-pages.automaticDecisions.completionShort" } else { "web-pages.automaticDecisions.completionNote" }),
            value=text(said, "decisionsText"),
          ) {
          (core.push)(AutoCompletion)
        }
      })
    },
  ])
}

///|
/// The completion rule's page (AutomaticDecisionCompletion): a row for each station, its rule's controls where it can
/// be set, else why not (offline, older, connecting); a wait while the stations are read.
fn completion_page(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let topic = @settings.stations_of(core, here)
  let body : Array[() -> Unit] = []
  match topic.value {
    Some(Array(a)) =>
      body.push(fn() {
        if a.length() == 0 {
          c.text(@sf.t("web-pages.automaticDecisions.addStation"), style=desk_note) |> ignore
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
                  @sf.t("web-pages.automaticDecisions.offline")
                } else if !(field(s, "overview") is Some(Object(_))) {
                  @sf.t("common.connecting")
                } else {
                  @sf.t("web-pages.automaticDecisions.upgrade")
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
          None => @sf.wait_line(c, @sf.t("common.readingStations"))
        }
      })
  }
  desk_page(
    c,
    core,
    "auto-completion",
    @sf.t("web-pages.automaticDecisions.completion"),
    about=@sf.t("web-pages.automaticDecisions.completionNote"),
    back=@sf.t("web-pages.automaticDecisions.title"),
    // 重新发现模型: every online station's models read again
    actions=fn() {
      if @sf.button(c, @sf.t("web-pages.automaticDecisions.refresh"), key="auto-refresh", tone=Ghost, icon="refresh") {
        c.after_build("auto-refresh", fn() {
          match topic.value {
            Some(Array(a)) =>
              for st in a {
                if flag(Some(st), "online") {
                  @settings.act(
                    core,
                    @sf.t("web-pages.automaticDecisions.refreshAction"),
                    "automaticDecisions.refresh",
                    obj([("station", str(text(Some(st), "station")))]),
                    done=@sf.t("web-pages.automaticDecisions.refreshed"),
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
    dc_status(c, s, @sf.t("web-pages.automaticDecisions.adminOnly"))
    return
  }
  let form = decision_form(c, core, station)
  let call = fn(action : String, input : Array[(String, Json)]) {
    @settings.act(
      core,
      @sf.t("web-pages.automaticDecisions.configAction"),
      "automaticDecisions.form." + action,
      obj([("station", str(station)), ("form", str(form)), ("input", obj(input))]),
      done=if action == "save" { @sf.t("web-pages.automaticDecisions.saved") } else { "" },
    )
  }
  let topic = (core.topic)("decisionForm", { "station": str(station), "form": str(form) })
  let d = topic.value
  guard d is Some(Object(_)) else {
    match topic.error {
      Some(e) => dc_status(c, s, error_text(e))
      None => dc_status(c, s, @sf.t("web-pages.automaticDecisions.readingConfig"), waiting=true)
    }
  }
  let saving = is_doing(core, ["automaticDecisions.form.save"], [("station", station), ("form", form)])
  let reviewing = is_doing(core, ["automaticDecisions.review"], [("station", station)])
  let busy = flag(d, "pending") || saving
  let model_id = text(d, "model")
  let chosen = match items(view, "models").iter().find_first(fn(m) { text(Some(m), "id") == model_id }) {
    Some(m) => text(Some(m), "name")
    None => @sf.t("web-pages.automaticDecisions.noModels")
  }
  let can_review = flag(view, "canReview") && flag(field(field(view, "settings"), "completion"), "enabled") && !flag(d, "dirty")
  c.box(style=desk_list_row, fn() {
    @sf.status_dot(c, "online")
    c.box(style=desk_list_text, fn() {
      dc_name(c, s)
      c.text(
        if flag(d, "enabled") {
          @sf.t("web-pages.automaticDecisions.enabledWith", args=[("model", chosen)])
        } else {
          @sf.t("web-pages.automaticDecisions.disabled")
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
          let now = @sf.select(c, "auto-model/" + station, model_id, options, disabled=busy, label=@sf.t("web-pages.automaticDecisions.model"))
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
        @sf.button(c, @sf.t("web-pages.automaticDecisions.save"), key="auto-save/" + station, tone=Primary, busy=saving, disabled=busy) {
        c.after_build("auto-save/" + station, fn() { call("save", []) })
      }
      if can_review &&
        @sf.button(c, @sf.t("web-pages.automaticDecisions.review"), key="auto-review/" + station, tone=Ghost, busy=reviewing, disabled=busy || reviewing) {
        c.after_build("auto-review/" + station, fn() {
          @settings.act(
            core,
            @sf.t("web-pages.automaticDecisions.reviewAction"),
            "automaticDecisions.review",
            obj([("station", str(station))]),
            done=@sf.t("web-pages.automaticDecisions.reviewStarted"),
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
        c.text(@sf.t("web-pages.archivePolicy.title"), style=desk_list_title) |> ignore
        let summary = text(policy, "summaryText")
        let line = @sf.t("web-pages.archivePolicy.optionCount", args=[("n", items(policy, "options").length().to_string())]) +
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
/// (AutomaticDecisions.css.ts note at a row's end: as wide as it is)
// kept across runs: a value (no field of it changes)
let dc_aside : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, wrap=false)

///|
/// (controls: at the row's end, 16 apart)
// kept across runs: a value (no field of it changes)
let dc_controls : @ui.Style = @ui.css("row gap=S4 align=ACenter justify=JEnd")

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
let dc_policy_row : @ui.Style = desk_list_link.then(@ui.css("min_h=S10"))

///|
/// Where a station's row has its dot (the dot's width, the row's gap after it).
// kept across runs: a value (no field of it changes)
let dc_dot_room : @ui.Style = @ui.style(w=@sf.dot_size)

///|
// kept across runs: a value (no field of it changes)
let dc_spin : @ui.Style = @ui.css("pr=S1")

///|
/// A station's archive policy (AutomaticDecisionPolicy, ArchivePolicy): its words (pressed, edited in a dialog), its
/// options in their two groups, each with how many chats the checks put there (pressed, edited in a dialog: its name,
/// what it means, which group, the chats it got; 删除), 添加选项 under each; what changed and what the checks said under
/// them. Each dialog edits the core's draft (`policyForm`), back to the station's first.
fn policy_page(c : @ui.Ctx, core : Core, here : Here, station : String) -> Unit {
  let s = station_of(core, here, station)
  let view = if flag(s, "online") { field(field(s, "overview"), "automaticDecisions") } else { None }
  let policy = field(view, "policy")
  let name = text(s, "name")
  let title = if name == "" {
    @sf.t("web-pages.archivePolicy.title")
  } else {
    @sf.t("web-pages.archivePolicy.title") + " · " + name
  }
  let body : Array[() -> Unit] = []
  if policy is Some(Object(_)) && flag(view, "canEdit") {
    body.push(fn() { policy_body(c, core, station, policy) })
  } else {
    body.push(fn() {
      c.text(
        @sf.t(
          if !flag(s, "online") {
            "web-pages.automaticDecisions.offline"
          } else if view is Some(Object(_)) && !flag(view, "canEdit") {
            "web-pages.automaticDecisions.adminOnly"
          } else {
            "web-pages.automaticDecisions.upgrade"
          },
        ),
        style=desk_note,
      )
      |> ignore
    })
  }
  desk_page(
    c,
    core,
    "auto-policy/" + station,
    title,
    about=@sf.t("web-pages.archivePolicy.textLead"),
    back=@sf.t("web-pages.automaticDecisions.completion"),
    body,
  )
}

///|
/// The policy's draft (`policyForm`), opened once (by the frame's builds' end) and kept by station.
fn policy_form(c : @ui.Ctx, core : Core, station : String) -> String {
  match policy_forms.get(station) {
    Some(f) => f
    None => {
      let f = policy_form_name(station)
      // (opened once the frame's builds are over: the build that first comes to it alone)
      c.tell("policy-open/" + f, fn() {
        @settings.act(core, @sf.t("web-pages.archivePolicy.readAction"), "automaticDecisions.policy.open", obj([("station", str(station)), ("form", str(f)), ("input", obj([]))]))
      })
      f
    }
  }
}

///|
/// The policy's draft's name for `station`, made the first time it is asked.
fn policy_form_name(station : String) -> String {
  match policy_forms.get(station) {
    Some(f) => f
    None => {
      profile_forms.val += 1
      let f = "mbui-policy-" + profile_forms.val.to_string()
      policy_forms[station] = f
      f
    }
  }
}

///|
/// The dialog a fixture's mode puts up over the policy ("" none, "text", "option": its first option's).
// kept across runs: said by settings_fixture; settings_reset empties it
let fx_policy_up : Ref[String] = Ref("")

///|
/// The policy (ArchivePolicy): see policy_page.
fn policy_body(c : @ui.Ctx, core : Core, station : String, policy : Json?) -> Unit {
  let t = @sf.theme()
  let form = policy_form(c, core, station)
  let call = fn(action : String, input : Array[(String, Json)], then : (Json) -> Unit) {
    (core.call)("automaticDecisions.policy." + action, obj([("station", str(station)), ("form", str(form)), ("input", obj(input))]), fn(r) {
      match r {
        Ok(v) => then(v)
        Err(e) => (core.say)(@sf.t("android-misc.act.failed", args=[("what", @sf.t("web-pages.archivePolicy.editAction")), ("error", error_text(e))]))
      }
    })
  }
  let d = (core.topic)("policyForm", { "station": str(station), "form": str(form) }).value
  let busy = !(d is Some(Object(_))) || flag(d, "pending")
  let saving = is_doing(core, ["automaticDecisions.policy.save"], [("station", station), ("form", form)])
  let failed = failed_of(core, ["automaticDecisions.policy.save"], [("station", station), ("form", form)])
  // back to the station's first (what an earlier dialog left unsaved is gone), then the dialog
  let open = fn(id : String, ov : Json?) {
    call("edit", [("reset", Json::boolean(true))], fn(_) { policy_dialog(core, station, form, policy, id, "", ov) })
  }
  let add = fn(archive : Bool) {
    call("edit", [("reset", Json::boolean(true))], fn(_) {
      call("edit", [("add", Json::boolean(archive))], fn(made) {
        match items(Some(made), "options").last() {
          Some(o) => policy_dialog(core, station, form, policy, "", text(Some(o), "key"), None)
          None => ()
        }
      })
    })
  }
  // a fixture's dialog (MBUI_FIXTURE=settings-policy-text, settings-policy-option), once the page is built
  if fx_policy_up.val != "" {
    let what = fx_policy_up.val
    fx_policy_up.val = ""
    c.after_build("policy-fixture", fn() {
      if what == "text" {
        policy_dialog(core, station, form, policy, "", "", None)
      } else {
        match items(policy, "options") {
          [o, ..] => policy_dialog(core, station, form, policy, text(Some(o), "id"), "", Some(o))
          _ => ()
        }
      }
    })
  }
  c.box(style=pol_box, fn() {
    if saving || failed is Some(_) {
      c.box(style=pol_head, fn() {
        if saving {
          @sf.spinner(c) |> ignore
        }
        match failed {
          Some(why) => c.text(why, style=dc_error) |> ignore
          None => ()
        }
      })
      |> ignore
    }
    let wid = c.id("policy-text")
    if !busy {
      c.cursor(wid, Hand)
      if hit(c, wid) {
        c.after_build("policy-text", fn() { open("", None) })
      }
    }
    c.box(style=if busy { pol_words_box } else { pol_words_live }, id=wid, fn() {
      c.text(text(policy, "text"), style=pol_words) |> ignore
    })
    |> ignore
    for archive in [true, false] {
      c.box(style=pol_group, fn() {
        c.box(style=pol_group_head, fn() {
          c.text(@sf.t(if archive { "web-pages.archivePolicy.archive" } else { "web-pages.archivePolicy.keep" }), style=pol_group_name)
          |> ignore
        })
        |> ignore
        for o in items(policy, "options").filter(fn(x) { flag(Some(x), "archive") == archive }) {
          let ov = Some(o)
          let oid = c.id("policy-option/" + text(ov, "id"))
          if !busy {
            c.cursor(oid, Hand)
            if hit(c, oid) {
              c.after_build("policy-option/" + text(ov, "id"), fn() { open(text(ov, "id"), ov) })
            }
          }
          c.box(style=if busy { pol_option } else { pol_option_live }, id=oid, fn() {
            c.box(style=pol_option_name_box, fn() { c.text(text(ov, "name"), style=pol_option_name) |> ignore }) |> ignore
            c.box(style=pol_option_rubric_box, fn() { c.text(text(ov, "rubric"), style=pol_option_rubric) |> ignore }) |> ignore
            c.box(style=pol_option_count_box, fn() { c.text(count(ov, "count").to_string(), style=pol_option_count) |> ignore })
            |> ignore
          })
          |> ignore
        }
        let aid = c.id("policy-add/" + archive.to_string())
        if !busy {
          c.cursor(aid, Hand)
          if hit(c, aid) {
            c.after_build("policy-add/" + archive.to_string(), fn() { add(archive) })
          }
        }
        c.box(style=if busy { pol_add } else { pol_add_live }, id=aid, fn() {
          @sf.icon(c, "plus", size=pol_plus, color=t.p.muted) |> ignore
          c.text(@sf.t("web-pages.archivePolicy.add"), style=pol_add_words) |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    let change = text(policy, "changeText")
    c.box(style=desk_said_line, fn() {
      if change != "" {
        c.text(change + " · ", style=dc_aside) |> ignore
      }
      c.text(text(policy, "summaryText"), style=if count(policy, "failed") > 0 { dc_error_line } else { dc_aside }) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A part of the policy edited in a dialog (PolicyDialog): its words (`id` and `key` ""), an option of the station's
/// (`id`, with what the checks put there: `ov`), or a new one (`key`, its draft's). 保存 closes it and saves on under the
/// policy (a spinner, or what went wrong); 取消 and closing put the draft back.
fn policy_dialog(core : Core, station : String, form : String, policy : Json?, id : String, key : String, ov : Json?) -> Unit {
  let edit = fn(input : Array[(String, Json)]) {
    (core.call)("automaticDecisions.policy.edit", obj([("station", str(station)), ("form", str(form)), ("input", obj(input))]), fn(_) {  })
  }
  let save = fn() {
    @settings.act(
      core,
      @sf.t("web-pages.archivePolicy.saveAction"),
      "automaticDecisions.policy.save",
      obj([("station", str(station)), ("form", str(form)), ("input", obj([]))]),
      done=@sf.t("web-pages.archivePolicy.saved"),
    )
  }
  let draft = fn() { (core.topic)("policyForm", { "station": str(station), "form": str(form) }).value }
  let serial = (desk_dialogs.val + 1).to_string()
  let filled : Map[String, Bool] = {}
  // a field's words put in once, as the dialog opens; then what is typed is the draft's
  let words_of = fn(part : String, value : String) -> @ui.Field {
    let f = field_of("policy/" + serial + "/" + part)
    if !filled.contains(part) {
      filled[part] = true
      f.set(value)
    }
    f
  }
  // `remove`: the option of the station's (its id) 删除 takes out and saves; "" none
  let foot = fn(remove : String) {
    fn(c : @ui.Ctx, shut : () -> Unit) {
      if remove != "" &&
        @sf.button(c, @sf.t("web-pages.archivePolicy.remove"), key="policy-remove", tone=GhostDanger, icon="trash") {
        shut()
        (core.call)("automaticDecisions.policy.edit", obj([("station", str(station)), ("form", str(form)), ("input", obj([("remove", str(remove))]))]), fn(
          _,
        ) {
          save()
        })
      }
      c.spacer()
      if @sf.button(c, @sf.t("web-pages.archivePolicy.cancel"), key="policy-cancel", tone=Ghost) {
        c.blur()
        shut()
        edit([("reset", Json::boolean(true))])
      }
      if @sf.button(c, @sf.t("web-pages.archivePolicy.save"), key="policy-save", tone=Primary, disabled=!flag(draft(), "dirty")) {
        c.blur()
        shut()
        save()
      }
    }
  }
  if id == "" && key == "" {
    open_dialog(
      @sf.t("web-pages.archivePolicy.title"),
      description=@sf.t("web-pages.archivePolicy.textLead"),
      wide=true,
      fn(c, _) {
        let d = draft()
        let f = words_of("policy", text(d, "policy"))
        let words = @sf.textarea(c, "policy/" + serial + "/policy", rows=8, field=f)
        if d is Some(Object(_)) && words != text(d, "policy") {
          c.after_build("policy-words", fn() { edit([("policy", str(words))]) })
        }
      },
      foot(""),
    )
    return
  }
  let fresh = key != ""
  open_dialog(
    if fresh {
      @sf.t("web-pages.archivePolicy.newOption")
    } else {
      text(ov, "name")
    },
    fn(c, shut) {
      let d = draft()
      let o = items(d, "options").iter().find_first(fn(x) { if fresh { text(Some(x), "key") == key } else { text(Some(x), "id") == id } })
      guard o is Some(oj) else { return }
      let o = Some(oj)
      let okey = text(o, "key")
      @sf.field(c, @sf.t("web-pages.archivePolicy.name"), fn() {
        let n = @sf.input(c, "policy/" + serial + "/name", field=words_of("name", text(o, "name"))).text
        if n != text(o, "name") {
          c.after_build("policy-name", fn() { edit([("option", str(okey)), ("name", str(n))]) })
        }
      })
      @sf.field(c, @sf.t("web-pages.archivePolicy.rubric"), fn() {
        let r = @sf.textarea(c, "policy/" + serial + "/rubric", rows=3, field=words_of("rubric", text(o, "rubric")))
        if r != text(o, "rubric") {
          c.after_build("policy-rubric", fn() { edit([("option", str(okey)), ("rubric", str(r))]) })
        }
      })
      @sf.field(c, @sf.t("web-pages.archivePolicy.counts"), fn() {
        let i = @sf.segmented(
          c,
          "policy/" + serial + "/archive",
          [@sf.t("web-pages.archivePolicy.archive"), @sf.t("web-pages.archivePolicy.keep")],
          if flag(o, "archive") { 0 } else { 1 },
        )
        if (i == 0) != flag(o, "archive") {
          c.after_build("policy-archive", fn() { edit([("option", str(okey)), ("archive", Json::boolean(i == 0))]) })
        }
      })
      // the chats the checks put there, each to its chat
      if count(ov, "count") > 0 {
        c.box(style=pol_chats, fn() {
          c.text(@sf.t("web-pages.archivePolicy.chats", args=[("days", count(policy, "days").to_string())]), style=pol_group_name) |> ignore
          for ch in items(ov, "chats") {
            let cid = c.id("policy-chat/" + text(Some(ch), "session"))
            c.cursor(cid, Hand)
            if hit(c, cid) {
              shut()
              edit([("reset", Json::boolean(true))])
              (core.open_chat)(station, text(Some(ch), "session"), text(Some(ch), "title"))
            }
            c.box(id=cid, style=pol_chat_box, fn() { c.text(text(Some(ch), "title"), style=pol_chat) |> ignore }) |> ignore
          }
          let more = count(ov, "count") - items(ov, "chats").length()
          if more > 0 {
            c.text(@sf.t("web-pages.archivePolicy.more", args=[("n", more.to_string())]), style=dc_aside) |> ignore
          }
        })
        |> ignore
      }
    },
    foot(if fresh { "" } else { id }),
  )
}

///|
/// (policy: its parts 12 apart)
// kept across runs: a value (no field of it changes)
let pol_box : @ui.Style = @ui.css("w=Full gap=S3")

///|
/// (policyHead: a spinner, or what went wrong, 28 high at least)
// kept across runs: a value (no field of it changes)
let pol_head : @ui.Style = @ui.css("row w=Full min_h=S7 gap=S2 align=ACenter")

///|
/// (policyWords: 8 above and under, 10 out to each side with its ground, the field's corner, the list's ground pointed
/// at)
// kept across runs: a value (no field of it changes)
let pol_words_box : @ui.Style = @sf.outset(pol_out).then(@ui.css("px=S2_5 py=S2 radius=Xl"))

///|
let pol_out : Double = 10.0

///|
// kept across runs: a value (no field of it changes)
let pol_words_live : @ui.Style = pol_words_box.then(@ui.css("hovered{bg=ListGround}"))

///|
/// (its words: the list's size, lines 1.6 of it, as they were written)
// kept across runs: a value (no field of it changes)
let pol_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Fg, w=Full)

///|
/// (policyGroup: its rows 2 apart; policyGroupName: 12, 600, muted, 4 above and under)
// kept across runs: a value (no field of it changes)
let pol_group : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let pol_group_name : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, weight=Semibold, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pol_group_head : @ui.Style = @ui.css("py=S1")

///|
/// (option: its name, what it means, its count in a line, 12 apart, 8 above and under, 10 out to each side)
// kept across runs: a value (no field of it changes)
let pol_option : @ui.Style = pol_words_box.then(@ui.css("row gap=S3 align=AStart"))

///|
// kept across runs: a value (no field of it changes)
let pol_option_live : @ui.Style = pol_option.then(@ui.css("hovered{bg=ListGround}"))

///|
/// (optionName: 120 wide, the list's words)
// kept across runs: a value (no field of it changes)
let pol_option_name_box : @ui.Style = @ui.style(w=Fixed(pol_name_w))

///|
let pol_name_w : Double = 120.0

///|
// kept across runs: a value (no field of it changes)
let pol_option_name : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let pol_option_rubric_box : @ui.Style = @ui.style(w=@sf.grow)

///|
/// (optionRubric: 12, muted, lines 1.5 of it)
// kept across runs: a value (no field of it changes)
let pol_option_rubric : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, w=Full)

///|
/// (optionCount: 2 of its digits wide at least, at its end)
// kept across runs: a value (no field of it changes)
let pol_option_count_box : @ui.Style = @ui.css("min_w=S6 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let pol_option_count : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, wrap=false)

///|
/// (addOption: a plus 14 and its words, muted, 6 apart)
// kept across runs: a value (no field of it changes)
let pol_add : @ui.Style = pol_words_box.then(@ui.css("row gap=S1_5 align=ACenter"))

///|
// kept across runs: a value (no field of it changes)
let pol_add_live : @ui.Style = pol_add.then(@ui.css("hovered{bg=ListGround}"))

///|
let pol_plus : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
let pol_add_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, wrap=false)

///|
/// (optionChats: 6 apart, 8 over them)
// kept across runs: a value (no field of it changes)
let pol_chats : @ui.Style = @ui.css("w=Full pt=S2 gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let pol_chat_box : @ui.Style = @ui.css("w=Full")

///|
/// (optionChat: the list's words, cut short, underlined pointed at)
// kept across runs: a value (no field of it changes)
let pol_chat : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Fg, wrap=false, w=Full)
