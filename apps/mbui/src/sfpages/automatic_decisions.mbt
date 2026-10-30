// 自动决策 (web/src/AutomaticDecisions.tsx; the narrow app's mobile/AutomaticDecisions.tsx), one page in every frame:
// the decision points, each a row to its page; the completion rule's page, a station a section, its rule a group of
// rows (启用, its model, a check now, its archive policy), 保存修改 under them once changed; a station's archive policy,
// its words on a card, its options in their two groups a row each with how many chats each got, 添加 under each, edited
// in dialogs (the presenters: a sheet with a finger). One page, the library's parts laid out by its own width: the
// phone's copies (src/sfapp/settings, a list card a station, sheets) and the desktop's (a station a row with its
// controls at its end, its options a table) are gone.

///|
/// 自动决策 (AutomaticDecisions; the narrow app's AutomaticDecisionsScreen): the point a decision is made at (the
/// completion of a turn), what it does, how many stations have it on (the core's `settings`), a row to its page.
pub fn decisions_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let said = (core.topic)("settings", { "scope": Json::string(here.workspace) }).value
  @sf.page(c, on_back=core.pop, frame~, "auto-decisions", @sf.t("web-pages.automaticDecisions.title"), about=@sf.t("web-pages.automaticDecisions.choosePoint"), [
    fn() {
      @sf.group(c, fn() {
        if @sf.link_row(c, "auto-completion",
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
/// The completion rule's page (AutomaticDecisionCompletion, the narrow app's AutomaticDecisionCompletionScreen): a
/// section a station, its rule where it can be set (completion_station), else why not (offline, older, connecting); a
/// wait while the stations are read; 重新发现模型 at its title's end.
pub fn completion_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let topic = @settings.stations_of(core, here)
  let body : Array[() -> Unit] = []
  match topic.value {
    Some(Array(a)) => {
      if a.length() == 0 {
        body.push(fn() { @sf.page_note(c, @sf.t("web-pages.automaticDecisions.addStation")) })
      }
      for st in a {
        let s = Some(st)
        let view = field(field(s, "overview"), "automaticDecisions")
        body.push(fn() {
          @sf.section(c, text(s, "name"), fn() {
            if flag(s, "online") && view is Some(Object(_)) {
              completion_station(c, core, s, view)
            } else {
              @sf.page_note(c, @sf.t(
                if !flag(s, "online") {
                  "web-pages.automaticDecisions.offlineNote"
                } else if !(field(s, "overview") is Some(Object(_))) {
                  "common.connecting"
                } else {
                  "web-pages.automaticDecisions.upgrade"
                },
              ))
            }
          })
        })
      }
    }
    _ =>
      body.push(fn() {
        match topic.error {
          Some(e) => @sf.page_note(c, error_text(e), bad=true)
          // (read the first time: rows' shapes where the stations' will be, AutomaticDecisions.tsx's Waiting, 2)
          None =>
            @sf.waiting(c, text=@sf.t("common.readingStations"), fn() {
              for st in [4, 6] {
                @sf.section(c, @sf.sample_words(st), fn() {
                  form_rows(c, core.quiet(), "sample", "sample", Some(form_view_sample()), Some({ "enabled": true }))
                })
              }
            })
        }
      })
  }
  @sf.page(
    c,
    on_back=core.pop,
    frame~,
    "auto-completion",
    @sf.t("web-pages.automaticDecisions.completion"),
    about=@sf.t("web-pages.automaticDecisions.completionNote"),
    // 重新发现模型: every online station's models read again
    actions=fn() {
      if @sf.button(c, @sf.t("web-pages.automaticDecisions.refresh"), key="auto-refresh", tone=Ghost, icon="refresh") {
        c.tell("auto-refresh", fn() {
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
/// A station's rule (AutomaticDecisionPanel, the narrow app's DecisionPanel), in the core's draft (`decisionForm`), a
/// group of its rows: 启用, the model it checks with (picked from the core's choices), 检查未决策的 chat where the station
/// can, its archive policy (to its page); 保存修改 under them once changed, what went wrong under that.
fn completion_station(c : @ui.Ctx, core : Core, s : Json?, view : Json?) -> Unit {
  let station = text(s, "station")
  if !flag(view, "canEdit") {
    @sf.page_note(c, @sf.t("web-pages.automaticDecisions.adminOnly"))
    return
  }
  let form = decision_form(c, core, station)
  let topic = (core.topic)("decisionForm", { "station": str(station), "form": str(form) })
  let d = topic.value
  guard d is Some(Object(_)) else {
    match topic.error {
      Some(e) => @sf.page_note(c, error_text(e), bad=true)
      None =>
        @sf.waiting(c, text=@sf.t("web-pages.automaticDecisions.readingConfig"), fn() {
          form_rows(c, core.quiet(), station, form, view, Some({ "enabled": true }))
        })
    }
  }
  form_rows(c, core, station, form, view, d)
}

///|
/// A station's rule as its draft (`d`, the core's `decisionForm`) says it, a group of its rows; 保存修改 under them
/// once changed, what went wrong under that.
fn form_rows(c : @ui.Ctx, core : Core, station : String, form : String, view : Json?, d : Json?) -> Unit {
  let call = fn(action : String, input : Array[(String, Json)]) {
    @settings.act(
      core,
      @sf.t("web-pages.automaticDecisions.configAction"),
      "automaticDecisions.form." + action,
      obj([("station", str(station)), ("form", str(form)), ("input", obj(input))]),
      done=if action == "save" { @sf.t("web-pages.automaticDecisions.saved") } else { "" },
    )
  }
  let saving = is_doing(core, ["automaticDecisions.form.save"], [("station", station), ("form", form)])
  let reviewing = is_doing(core, ["automaticDecisions.review"], [("station", station)])
  let busy = flag(d, "pending") || saving
  let model_id = text(d, "model")
  let chosen = match items(view, "models").iter().find_first(fn(m) { text(Some(m), "id") == model_id }) {
    Some(m) => text(Some(m), "name")
    None =>
      if model_id == "" {
        @sf.t("web-pages.automaticDecisions.pickModel")
      } else {
        @sf.t("web-pages.automaticDecisions.unavailable", args=[("model", model_id)])
      }
  }
  let can_review = flag(view, "canReview") && flag(field(field(view, "settings"), "completion"), "enabled") && !flag(d, "dirty")
  @sf.group(c, fn() {
    let on = flag(d, "enabled")
    if @sf.switch_row(c, "auto-enabled/" + station, @sf.t("web-pages.automaticDecisions.enabled"), on, disabled=busy) != on {
      c.tell("auto-enabled/" + station, fn() { call("edit", [("enabled", Json::boolean(!on))]) })
    }
    let mkey = "auto-model/" + station
    if @sf.link_row(c, mkey, @sf.t("web-pages.automaticDecisions.model"), value=chosen) && !busy {
      let choices = items(field(d, "pick"), "options").map(fn(o) { @sf.choice(text(Some(o), "model"), text(Some(o), "name")) })
      @sf.pick(@sf.t("web-pages.automaticDecisions.model"), choices, model_id, fn(now) {
        if now != model_id {
          call("edit", [("model", str(now))])
        }
      }, from=Of(c.id(mkey)))
    }
    if can_review &&
      @sf.link_row(
        c,
        "auto-review/" + station,
        @sf.t("web-pages.automaticDecisions.review"),
        acts=true,
        // (asked: a spinner at its end; failed: a mark there, why under the pointer)
        tail=fn() {
          @settings.doing_mark(c, reviewing, failed_of(core, ["automaticDecisions.review"], [("station", station)]), inline=true)
        },
      ) &&
      !reviewing &&
      !busy {
      @settings.act(
        core,
        @sf.t("web-pages.automaticDecisions.reviewAction"),
        "automaticDecisions.review",
        obj([("station", str(station))]),
        done=@sf.t("web-pages.automaticDecisions.reviewStarted"),
      )
    }
    match field(view, "policy") {
      Some(Object(_)) as policy => {
        let summary = text(policy, "summaryText")
        let line = @sf.t("web-pages.archivePolicy.optionCount", args=[("n", items(policy, "options").length().to_string())]) +
          (if summary == "" { "" } else { " · " + summary })
        let failed = count(policy, "failed") > 0
        if @sf.link_row(
            c,
            "auto-policy/" + station,
            @sf.t("web-pages.archivePolicy.title"),
            note=if failed { "" } else { line },
            trouble=if failed { line } else { "" },
          ) {
          (core.push)(AutoPolicy(station))
        }
      }
      _ => ()
    }
  })
  if flag(d, "dirty") {
    @sf.block(c, fn() {
      if @sf.button(c, @sf.t("web-pages.automaticDecisions.save"), key="auto-save/" + station, tone=Primary, busy=saving, disabled=busy) {
        c.tell("auto-save/" + station, fn() { call("save", []) })
      }
    })
  }
  match failed_of(core, ["automaticDecisions.form.save"], [("station", station), ("form", form)]) {
    Some(why) => @sf.page_note(c, why, bad=true)
    None => ()
  }
}

///|
/// What a station says of its rule, made up, for what is shown while it is read (form_rows in its bones): it may be
/// set, an archive policy of a few options.
fn form_view_sample() -> Json {
  { "canEdit": true, "policy": { "summaryText": Json::string(@sf.sample_words(10)), "options": [1, 2, 3] } }
}

///|
/// A station's archive policy (AutomaticDecisionPolicy, ArchivePolicy): its words (pressed, edited in a dialog), its
/// options in their two groups, each with how many chats the checks put there (pressed, edited in a dialog: its name,
/// what it means, which group, the chats it got; 删除), 添加选项 under each; what changed and what the checks said under
/// them. Each dialog edits the core's draft (`policyForm`), back to the station's first.
pub fn policy_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame, station : String) -> Unit {
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
            "web-pages.automaticDecisions.offlineNote"
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
  @sf.page(c, on_back=core.pop, frame~, "auto-policy/" + station, title, lead=@sf.t("web-pages.archivePolicy.textLead"), body)
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
      profile_forms.set(profile_forms.get() + 1)
      let f = "mbui-policy-" + profile_forms.get().to_string()
      policy_forms[station] = f
      f
    }
  }
}

///|
/// The dialog a fixture's mode puts up over the policy ("" none, "text", "option": its first option's).
// kept across runs: said by the fixture (sfdesk settings_fixture); reset empties it
pub let fx_policy_up : Ref[String] = Ref("")

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
  // a fixture's dialog (MBUI_FIXTURE=settings-policy-text, settings-policy-option), once the page is built: taken when
  // it is put up, not while it is built (a frame built again lets go of what its earlier builds said: Ctx::after_build)
  if fx_policy_up.val != "" {
    let what = fx_policy_up.val
    c.after_build("policy-fixture", fn() {
      fx_policy_up.val = ""
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
  if saving {
    @sf.page_note(c, @sf.t("common.saving"))
  }
  match failed {
    Some(why) => @sf.page_note(c, why, bad=true)
    None => ()
  }
  // its words, on a card: pressed, edited
  @sf.page_card(c, fn() {
    let wid = c.id("policy-text")
    if !busy && hit(c, wid) {
      c.tell("policy-text", fn() { open("", None) })
    }
    c.box(style=pol_words_box, id=wid, fn() { c.text(text(policy, "text"), style=pol_words) |> ignore }) |> ignore
  })
  // its options in their two groups, each a row with how many chats the checks put there; 添加 under them
  for archive in [true, false] {
    @sf.section(c, @sf.t(if archive { "web-pages.archivePolicy.archive" } else { "web-pages.archivePolicy.keep" }), fn() {
      @sf.group(c, fn() {
        for o in items(policy, "options").filter(fn(x) { flag(Some(x), "archive") == archive }) {
          let ov = Some(o)
          let key = "policy-option/" + text(ov, "id")
          if @sf.link_row(c, key, text(ov, "name"), note=text(ov, "rubric"), value=count(ov, "count").to_string(), chevron=false) && !busy {
            c.tell(key, fn() { open(text(ov, "id"), ov) })
          }
        }
        let akey = "policy-add/" + archive.to_string()
        if @sf.link_row(c, akey, @sf.t("web-pages.archivePolicy.add"), adds=true) && !busy {
          c.tell(akey, fn() { add(archive) })
        }
      })
    })
  }
  let change = text(policy, "changeText")
  @sf.page_note(
    c,
    (if change != "" { change + " · " } else { "" }) + text(policy, "summaryText"),
    bad=count(policy, "failed") > 0,
  )
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
        @sf.button(c, @sf.t("web-pages.archivePolicy.remove"), key="policy-remove", tone=GhostDanger) {
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
          c.tell("policy-archive", fn() { edit([("option", str(okey)), ("archive", Json::boolean(i == 0))]) })
        }
      })
      // the chats the checks put there, each to its chat
      if count(ov, "count") > 0 {
        c.box(style=pol_chats, fn() {
          c.text(@sf.t("web-pages.archivePolicy.chats", args=[("days", count(policy, "days").to_string())]), style=pol_group_name) |> ignore
          for ch in items(ov, "chats") {
            let cid = c.id("policy-chat/" + text(Some(ch), "session"))
            if hit(c, cid) {
              shut()
              edit([("reset", Json::boolean(true))])
              (core.open_chat)(station, text(Some(ch), "session"), text(Some(ch), "title"))
            }
            c.box(id=cid, style=pol_chat_box, fn() { c.text(text(Some(ch), "title"), style=pol_chat) |> ignore }) |> ignore
          }
          let more = count(ov, "count") - items(ov, "chats").length()
          if more > 0 {
            c.text(@sf.t("web-pages.archivePolicy.more", args=[("n", more.to_string())]), style=pol_more) |> ignore
          }
        })
        |> ignore
      }
    },
    foot(if fresh { "" } else { id }),
  )
}



///|
/// (policyWords: 8 above and under, 10 out to each side with its ground, the field's corner, the list's ground pointed
/// at)
// kept across runs: a value (no field of it changes)
let pol_words_box : @ui.Style = @ui.css("w=Full")



///|
/// (its words: the list's size, lines 1.6 of it, as they were written)
// kept across runs: a value (no field of it changes)
let pol_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, w=Full)

















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
let pol_chat : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, wrap=false, w=Full)

///|
/// How many more chats it got than are named (the meta's, muted).
// kept across runs: a value (no field of it changes)
let pol_more : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// What an option's chats are said under (the meta's, 600, muted).
// kept across runs: a value (no field of it changes)
let pol_group_name : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Semibold, color=Muted, w=Full)
