// 自动决策, one page in every frame:
// the decision points, each a row to its page; the completion rule's page, a station a section, its rule a group of
// rows (启用, its model, a check now, its archive policy), 保存修改 under them once changed; a station's archive policy,
// its words on a card, its options in their two groups a row each with how many chats each got, 添加 under each, edited
// in dialogs (the presenters: a sheet with a finger). One page, the library's parts laid out by its own width: the
// phone's copies (src/sfapp/settings, a list card a station, sheets) and the desktop's (a station a row with its
// controls at its end, its options a table) are gone.

///|
/// 自动决策 (AutomaticDecisions; the narrow app's AutomaticDecisionsScreen) as nodes, laid out by the `width` its frame
/// gives it (page_node; what it is for a wide page's mark beside its title, its tips over the window from `tips`): its
/// one decision on a card: whether a chat is done, how it is decided now (the core's), short where narrow and whole where
/// wide; pressed, that decision's page.
pub fn decisions_node(
  v : @view.View,
  core : Core,
  here : () -> Here,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
  tips? : @sf.TipLayer,
) -> Unit {
  // (what it says of itself to a frame's bar that names it, what it is for with it: its `about`)
  let told = said
  let said = fn() { (core.topic)("settings", { "scope": Json::string(here().workspace) }).get().value }
  @sf.page_node(
    v,
    fn() { @sf.t("web-pages.automaticDecisions.title") },
    fn() { ["decisions"] },
    fn(b, _) {
      @sf.group_node(b, fn(g) {
        @sf.link_row_node(
          g,
          fn() { @sf.t("web-pages.automaticDecisions.completion") },
          fn() { (core.push)(AutoCompletion) },
          note=fn() { @sf.t("web-pages.automaticDecisions.completionShort") },
          wide_note=fn() { @sf.t("web-pages.automaticDecisions.completionNote") },
          value=fn() { text(said(), "decisionsText") },
        )
      })
    },
    on_back~,
    frame~,
    about=fn() { @sf.t("web-pages.automaticDecisions.choosePoint") },
    said?=told,
    width?,
    tips?,
  )
}

///|
/// The completion rule's page (AutomaticDecisionCompletion, the narrow app's AutomaticDecisionCompletionScreen) made
/// once as nodes (page_node, laid out by the `width` its frame gives it, narrow where none is given): a section a
/// station, its rule where it can be set (completion_station_node), else why not (offline, older, connecting); while
/// the stations are read the first time, their sections in their bones, what could not be read said instead; 重新发现模型
/// at its title's end (where a frame's bar names it, in that bar: `bar_actions`). All as the core says it. What it
/// says of itself told `said`; what is said of what the pointer rests on, in `tips`.
pub fn completion_node(
  v : @view.View,
  core : Core,
  here : () -> Here,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
  tips? : @sf.TipLayer,
  bar_actions? : ((@view.View) -> Unit, (@sf.Look) -> Double) -> Unit,
) -> Unit {
  let topic = fn() { @settings.stations_of(core, here()) }
  // (the stations' drafts the page's own, as the old frame kept them by station: each opened as its rows first come,
  // kept while the station goes offline and comes back, all dropped as the page is let go)
  let forms : Map[String, String] = Map([])
  let form_of = fn(station : String) -> String {
    match forms.get(station) {
      Some(f) => f
      None => {
        let f = @settings.decision_form_open(core, station)
        forms[station] = f
        f
      }
    }
  }
  v.owns(fn() {
    for station, form in forms {
      @settings.decision_form_drop(core, station, form)
    }
    forms.clear()
  })
  |> ignore
  let stations = fn() {
    match topic().value {
      Some(Array(a)) => a
      _ => []
    }
  }
  // 重新发现模型: every online station's models read again
  let actions = fn(l : @view.View) {
    @sf.button_node(l, fn() { @sf.t("web-pages.automaticDecisions.refresh") }, fn() {
      for st in @signals.untracked(stations) {
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
    }, tone=Ghost, icon="refresh")
    |> ignore
  }
  match bar_actions {
    Some(f) => f(actions, fn(_) { @sf.button_height() })
    None => ()
  }
  @sf.page_node(
    v,
    fn() { @sf.t("web-pages.automaticDecisions.completion") },
    fn() {
      match topic().value {
        Some(Array(a)) => if a.length() == 0 { ["none"] } else { a.map(fn(st) { "station/" + text(Some(st), "station") }) }
        _ => ["waiting"]
      }
    },
    fn(b, key) {
      match key {
        "none" => @sf.page_note_node(b, fn() { @sf.t("web-pages.automaticDecisions.addStation") })
        "waiting" =>
          b.pick(fn() { topic().error is Some(_) }, fn(p, failed) {
            if failed {
              @sf.page_note_node(p, fn() {
                match topic().error {
                  Some(e) => error_text(e)
                  None => ""
                }
              }, bad=fn() { true })
            } else {
              // (read the first time: rows' shapes where the stations' will be, 2)
              @sf.waiting_node(
                p,
                fn(s) {
                  for n in [4, 6] {
                    @sf.section_node(s, fn() { @sf.sample_words(n) }, fn(sec) {
                      form_rows_node(sec, core.quiet(), "sample", "sample", fn() { Some(form_view_sample()) }, fn() {
                        Some({ "enabled": true })
                      })
                    })
                  }
                },
                note=fn() { { reading: true, text: @sf.t("common.readingStations"), failing: [] } },
              )
            }
          })
        _ => {
          let station = key.unsafe_substring(start=8, end=key.length())
          let s = fn() {
            match stations().search_by(fn(st) { text(Some(st), "station") == station }) {
              Some(i) => Some(stations()[i])
              None => None
            }
          }
          // (its rule, that part of its overview alone, asked by its own section)
          let view = fn() { @settings.station_part(core, here(), station, "automaticDecisions") }
          @sf.section_node(b, fn() { text(s(), "name") }, fn(sec) {
            sec.pick(
              fn() {
                if flag(s(), "online") && view() is Some(Object(_)) {
                  ""
                } else if !flag(s(), "online") {
                  "web-pages.automaticDecisions.offlineNote"
                } else if !(field(s(), "overview") is Some(Object(_))) || view() is None {
                  "common.connecting"
                } else {
                  "web-pages.automaticDecisions.upgrade"
                }
              },
              fn(p, why) {
                if why == "" {
                  completion_station_node(p, core, station, form_of, view, tips?)
                } else {
                  @sf.page_note_node(p, fn() { @sf.t(why) })
                }
              },
            )
          })
        }
      }
    },
    on_back~,
    frame~,
    about=fn() { @sf.t("web-pages.automaticDecisions.completionNote") },
    actions~,
    said?,
    width?,
    tips?,
  )
}

///|
/// A station's rule (AutomaticDecisionPanel, the narrow app's DecisionPanel) as nodes: only its managers' (else said
/// so); its draft (`decisionForm`, the page's: `form_of` opens it the first time it is asked for) read as the core says
/// it (its rows in their bones while it is read the first time, what could not be read said instead).
fn completion_station_node(
  v : @view.View,
  core : Core,
  station : String,
  form_of : (String) -> String,
  view : () -> Json?,
  tips? : @sf.TipLayer,
) -> Unit {
  v.pick(fn() { flag(view(), "canEdit") }, fn(p, can) {
    if !can {
      @sf.page_note_node(p, fn() { @sf.t("web-pages.automaticDecisions.adminOnly") })
      return
    }
    let form = form_of(station)
    let topic = fn() { (core.topic)("decisionForm", { "station": str(station), "form": str(form) }).get() }
    p.pick(
      fn() {
        match (topic().value, topic().error) {
          (Some(Object(_)), _) => 0
          (_, Some(_)) => 1
          _ => 2
        }
      },
      fn(q, state) {
        match state {
          0 => form_rows_node(q, core, station, form, view, fn() { topic().value }, tips?)
          1 =>
            @sf.page_note_node(q, fn() {
              match topic().error {
                Some(e) => error_text(e)
                None => ""
              }
            }, bad=fn() { true })
          _ =>
            @sf.waiting_node(
              q,
              fn(s) { form_rows_node(s, core.quiet(), station, form, view, fn() { Some({ "enabled": true }) }) },
              note=fn() { { reading: true, text: @sf.t("web-pages.automaticDecisions.readingConfig"), failing: [] } },
            )
        }
      },
    )
  })
}

///|
/// A station's rule as its draft (`d`, the core's `decisionForm`) says it, as nodes: a group of its rows (启用, the model
/// it checks with picked from the core's choices beside its row, 检查未决策的 chat where the station can, a spinner at
/// its end while asked and a mark while it failed, why said under the pointer; its archive policy, to its page);
/// 保存修改 under them once changed, what went wrong under that. None of it changed while a change of it is on its way.
fn form_rows_node(
  v : @view.View,
  core : Core,
  station : String,
  form : String,
  view : () -> Json?,
  d : () -> Json?,
  tips? : @sf.TipLayer,
) -> Unit {
  let call = fn(action : String, input : Array[(String, Json)]) {
    @settings.act(
      core,
      @sf.t("web-pages.automaticDecisions.configAction"),
      "automaticDecisions.form." + action,
      obj([("station", str(station)), ("form", str(form)), ("input", obj(input))]),
      done=if action == "save" { @sf.t("web-pages.automaticDecisions.saved") } else { "" },
    )
  }
  let on_form = [("station", station), ("form", form)]
  let saving = fn() { is_doing(core, ["automaticDecisions.form.save"], on_form) }
  let reviewing = fn() { is_doing(core, ["automaticDecisions.review"], [("station", station)]) }
  let review_failed = fn() { failed_of(core, ["automaticDecisions.review"], [("station", station)]) }
  let busy = fn() { flag(d(), "pending") || saving() }
  let model_id = fn() { text(d(), "model") }
  let chosen = fn() {
    match items(view(), "models").iter().find_first(fn(m) { text(Some(m), "id") == model_id() }) {
      Some(m) => text(Some(m), "name")
      None =>
        if model_id() == "" {
          @sf.t("web-pages.automaticDecisions.pickModel")
        } else {
          @sf.t("web-pages.automaticDecisions.unavailable", args=[("model", model_id())])
        }
    }
  }
  let can_review = fn() {
    flag(view(), "canReview") && flag(field(field(view(), "settings"), "completion"), "enabled") && !flag(d(), "dirty")
  }
  let policy = fn() {
    match field(view(), "policy") {
      Some(Object(_)) as p => p
      _ => None
    }
  }
  let policy_line = fn() {
    let summary = text(policy(), "summaryText")
    @sf.t("web-pages.archivePolicy.optionCount", args=[("n", items(policy(), "options").length().to_string())]) +
    (if summary == "" { "" } else { " · " + summary })
  }
  let policy_failed = fn() { count(policy(), "failed") > 0 }
  @sf.group_node(v, fn(g) {
    @sf.switch_row_node(
      g,
      fn() { @sf.t("web-pages.automaticDecisions.enabled") },
      fn() { flag(d(), "enabled") },
      fn(now) { call("edit", [("enabled", Json::boolean(now))]) },
      disabled=busy,
    )
    // (its choices beside its row, as what opened them)
    g.box(fn(at) {
      @sf.link_row_node(
        at,
        fn() { @sf.t("web-pages.automaticDecisions.model") },
        fn() {
          if !@signals.untracked(busy) {
            let now = @signals.untracked(model_id)
            let choices = @signals.untracked(fn() { items(field(d(), "pick"), "options") }).map(fn(o) {
              @sf.choice(text(Some(o), "model"), text(Some(o), "name"))
            })
            let (x, y, w, h) = at.rect()
            @sf.pick(@sf.t("web-pages.automaticDecisions.model"), choices, now, fn(picked) {
              if picked != now {
                call("edit", [("model", str(picked))])
              }
            }, from=At(x, y, w, h))
          }
        },
        value=chosen,
      )
    })
    |> ignore
    g.show(can_review, fn(r) {
      @sf.link_row_node(
        r,
        fn() { @sf.t("web-pages.automaticDecisions.review") },
        fn() {
          if !@signals.untracked(reviewing) && !@signals.untracked(busy) {
            @settings.act(
              core,
              @sf.t("web-pages.automaticDecisions.reviewAction"),
              "automaticDecisions.review",
              obj([("station", str(station))]),
              done=@sf.t("web-pages.automaticDecisions.reviewStarted"),
            )
          }
        },
        acts=true,
        // (asked: a spinner at its end; failed: a mark there, why under the pointer)
        tail=fn(e) { doing_mark_node(e, reviewing, review_failed, tips?) },
        tail_shown=fn() { reviewing() || review_failed() is Some(_) },
      )
    })
    g.show(fn() { policy() is Some(_) }, fn(r) {
      @sf.link_row_node(
        r,
        fn() { @sf.t("web-pages.archivePolicy.title") },
        fn() { (core.push)(AutoPolicy(station)) },
        note=fn() { if policy_failed() { "" } else { policy_line() } },
        trouble=fn() { if policy_failed() { policy_line() } else { "" } },
      )
    })
  })
  v.show(fn() { flag(d(), "dirty") }, fn(s) {
    @sf.block_node(s, fn(b) {
      @sf.button_node(b, fn() { @sf.t("web-pages.automaticDecisions.save") }, fn() { call("save", []) }, tone=Primary, busy=saving, disabled=busy)
      |> ignore
    })
  })
  v.show(fn() { failed_of(core, ["automaticDecisions.form.save"], on_form) is Some(_) }, fn(n) {
    @sf.page_note_node(n, fn() { failed_of(core, ["automaticDecisions.form.save"], on_form).unwrap_or("") }, bad=fn() { true })
  })
}

///|
/// Where what someone set going shows how it is (doing_mark's) as nodes: a spinner while it is under way, a small red
/// mark while it failed a moment ago, why said under the pointer (in `tips`, where given). `size`: its spinner's and its mark's
/// (doing_mark's: 12 beside a row's words, inline; 14 otherwise).
pub fn doing_mark_node(
  v : @view.View,
  running : () -> Bool,
  failed : () -> String?,
  tips? : @sf.TipLayer,
  size? : Double = doing_mark_inline,
) -> Unit {
  v.pick(fn() { if running() { 1 } else if failed() is Some(_) { 2 } else { 0 } }, fn(p, what) {
    match what {
      1 => @sf.spinner_node(p, size~) |> ignore
      2 => {
        let mark = @sf.icon_node(p, "info", size, By(fn() { @sf.theme().p.red }))
        match tips {
          Some(t) =>
            @sf.tip_node(t, mark, fn() {
              match failed() {
                Some("") | None => @sf.t("web-main.doing.failed")
                Some(why) => why
              }
            })
            |> ignore
          None => ()
        }
      }
      _ => ()
    }
  })
}

///|
/// doing_mark's mark and spinner beside a row's words (inline: 12), and at its end (14).
let doing_mark_inline : Double = 12.0

///|
let doing_mark_end : Double = 14.0

///|
/// What a station says of its rule, made up, for what is shown while it is read (form_rows in its bones): it may be
/// set, an archive policy of a few options.
fn form_view_sample() -> Json {
  { "canEdit": true, "policy": { "summaryText": Json::string(@sf.sample_words(10)), "options": [1, 2, 3] } }
}

///|
/// A station's archive policy (AutomaticDecisionPolicy, ArchivePolicy) made once as nodes in node `v`, laid out by the
/// `width` its frame gives it: its words (pressed, edited in a dialog), its options in their two groups, each with how
/// many chats the checks put there (pressed, edited in a dialog: its name, what it means, which group, the chats it got;
/// 删除), 添加选项 under each; what changed and what the checks said under them. Each dialog edits the core's draft
/// (`policyForm`, opened as the page is made the first time for the station), back to the station's first. Offline, too
/// old, or not the viewer's to change: that, alone. All as the core says it now.
pub fn policy_node(
  v : @view.View,
  core : Core,
  here : () -> Here,
  station : String,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
) -> Unit {
  let s = fn() { station_of(core, here(), station) }
  let view = fn() { if flag(s(), "online") { field(field(s(), "overview"), "automaticDecisions") } else { None } }
  let policy = fn() { field(view(), "policy") }
  let title = fn() {
    match text(s(), "name") {
      "" => @sf.t("web-pages.archivePolicy.title")
      name => @sf.t("web-pages.archivePolicy.title") + " · " + name
    }
  }
  let usable = fn() { policy() is Some(Object(_)) && flag(view(), "canEdit") }
  @sf.page_node(
    v,
    title,
    on_back~,
    frame~,
    said?,
    width?,
    lead=fn() { @sf.t("web-pages.archivePolicy.textLead") },
    fn() { if usable() { ["policy"] } else { ["why"] } },
    fn(b, key) {
      if key == "policy" {
        policy_body_node(b, core, station, policy)
      } else {
        @sf.page_note_node(b, fn() {
          @sf.t(
            if !flag(s(), "online") {
              "web-pages.automaticDecisions.offlineNote"
            } else if view() is Some(Object(_)) && !flag(view(), "canEdit") {
              "web-pages.automaticDecisions.adminOnly"
            } else {
              "web-pages.automaticDecisions.upgrade"
            },
          )
        })
      }
    },
  )
}

///|
/// The policy's draft for `station` (`policyForm`), opened the first time it is asked for (kept by station after).
fn policy_form_opened(core : Core, station : String) -> String {
  match policy_forms.get(station) {
    Some(f) => f
    None => {
      let f = policy_form_name(station)
      @settings.act(core, @sf.t("web-pages.archivePolicy.readAction"), "automaticDecisions.policy.open", obj([("station", str(station)), ("form", str(f)), ("input", obj([]))]))
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
// kept across runs: said by the fixture (sfdesk settings_fixture); reset empties it
pub let fx_policy_up : Ref[String] = Ref("")

///|
/// The policy (ArchivePolicy) in node `v`, as `policy` says it now: see policy_node.
fn policy_body_node(v : @view.View, core : Core, station : String, policy : () -> Json?) -> Unit {
  let form = policy_form_opened(core, station)
  let call = fn(action : String, input : Array[(String, Json)], then : (Json) -> Unit) {
    (core.call)("automaticDecisions.policy." + action, obj([("station", str(station)), ("form", str(form)), ("input", obj(input))]), fn(r) {
      match r {
        Ok(v) => then(v)
        Err(e) => (core.say)(@sf.t("android-misc.act.failed", args=[("what", @sf.t("web-pages.archivePolicy.editAction")), ("error", error_text(e))]))
      }
    })
  }
  let d = fn() { (core.topic)("policyForm", { "station": str(station), "form": str(form) }).get().value }
  // (as it is when pressed: what it reads not followed by what pressed it)
  let busy = fn() { @signals.untracked(fn() { !(d() is Some(Object(_))) || flag(d(), "pending") }) }
  let on_form = [("station", station), ("form", form)]
  let saving = fn() { is_doing(core, ["automaticDecisions.policy.save"], on_form) }
  let failed = fn() { failed_of(core, ["automaticDecisions.policy.save"], on_form) }
  // back to the station's first (what an earlier dialog left unsaved is gone), then the dialog
  let open = fn(id : String, ov : Json?) {
    call("edit", [("reset", Json::boolean(true))], fn(_) { policy_dialog(core, station, form, @signals.untracked(policy), id, "", ov) })
  }
  let add = fn(archive : Bool) {
    call("edit", [("reset", Json::boolean(true))], fn(_) {
      call("edit", [("add", Json::boolean(archive))], fn(made) {
        match items(Some(made), "options").last() {
          Some(o) => policy_dialog(core, station, form, @signals.untracked(policy), "", text(Some(o), "key"), None)
          None => ()
        }
      })
    })
  }
  // a fixture's dialog (MBUI_FIXTURE=settings-policy-text, settings-policy-option), once the page is made: put up at
  // the moment it is made, taken then
  if fx_policy_up.val != "" {
    let what = fx_policy_up.val
    fx_policy_up.val = ""
    v.at_moment(v.logic_at(), fn() {
      let p = @signals.untracked(policy)
      if what == "text" {
        policy_dialog(core, station, form, p, "", "", None)
      } else {
        match items(p, "options") {
          [o, ..] => policy_dialog(core, station, form, p, text(Some(o), "id"), "", Some(o))
          _ => ()
        }
      }
    })
    |> ignore
  }
  v.show(saving, fn(n) { @sf.page_note_node(n, fn() { @sf.t("common.saving") }) })
  v.show(fn() { failed() is Some(_) }, fn(n) { @sf.page_note_node(n, fn() { failed().unwrap_or("") }, bad=fn() { true }) })
  // its words, on a card: pressed, edited
  @sf.page_card_node(v, fn(k) {
    k.box(fn(w) {
      @sf.style_node(w, fn() { pol_words_box })
      @sf.presses_node(w, fn() { if !busy() { open("", None) } })
      w.says(By(fn() { Some(@view.said(Button, label=text(policy(), "text"))) })) |> ignore
      @sf.words_node(w, fn() { text(policy(), "text") }, fn() { pol_words }) |> ignore
    })
    |> ignore
  })
  // its options in their two groups, each a row with how many chats the checks put there; 添加 under them
  for archive in [true, false] {
    @sf.section_node(v, fn() { @sf.t(if archive { "web-pages.archivePolicy.archive" } else { "web-pages.archivePolicy.keep" }) }, fn(sec) {
      @sf.group_node(sec, fn(g) {
        g.each(fn() { items(policy(), "options").filter(fn(x) { flag(Some(x), "archive") == archive }) }, fn(o) { text(Some(o), "id") }, fn(
          row,
          o,
        ) {
          let ov = fn() { Some(o.get()) }
          @sf.link_row_node(
            row,
            fn() { text(ov(), "name") },
            fn() { if !busy() { open(text(@signals.untracked(ov), "id"), @signals.untracked(ov)) } },
            note=fn() { text(ov(), "rubric") },
            value=fn() { count(ov(), "count").to_string() },
            chevron=false,
          )
        })
        @sf.link_row_node(g, fn() { @sf.t("web-pages.archivePolicy.add") }, fn() { if !busy() { add(archive) } }, adds=true)
      })
    })
  }
  @sf.page_note_node(
    v,
    fn() {
      let change = text(policy(), "changeText")
      (if change != "" { change + " · " } else { "" }) + text(policy(), "summaryText")
    },
    bad=fn() { count(policy(), "failed") > 0 },
  )
}

///|
/// A part of the policy edited in a dialog (PolicyDialog): its words (`id` and `key` ""), an option of the station's
/// (`id`, with what the checks put there: `ov`), or a new one (`key`, its draft's). 保存 closes it and saves on under the
/// policy (a spinner, or what went wrong); 取消 and closing put the draft back. What it holds and its buttons are nodes
/// of the window's tree (open_dialog_nodes), made once as it opens: what they show follows the draft as it changes.
fn policy_dialog(core : Core, station : String, form : String, policy : Json?, id : String, key : String, ov : Json?) -> Unit {
  let edit = fn(input : Array[(String, Json)]) {
    (core.call)("automaticDecisions.policy.edit", obj([("station", str(station)), ("form", str(form)), ("input", obj(input))]), @sfbase.answer_unread)
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
  let draft = fn() { (core.topic)("policyForm", { "station": str(station), "form": str(form) }).get().value }
  let serial = (desk_dialogs.val + 1).to_string()
  let filled : Map[String, Bool] = Map([])
  // a field's words put in once, as the dialog opens; then what is typed is the draft's
  let words_of = fn(part : String, value : String) -> @ui.Field {
    let f = field_of("policy/" + serial + "/" + part)
    if !filled.contains(part) {
      filled[part] = true
      f.set(value)
    }
    f
  }
  // what is typed in `f` told to `edited` as it changes (at its cause's moment), not the words it was given
  let on_typed = fn(n : @view.View, f : @ui.Field, edited : (String) -> Unit) {
    let was = Ref(@signals.untracked(fn() { f.text() }))
    n.reacts(fn() { f.text() }, fn(words) {
      if words != was.val {
        was.val = words
        edited(words)
      }
    })
  }
  // `remove`: the option of the station's (its id) 删除 takes out and saves; "" none
  let foot = fn(remove : String) {
    fn(v : @view.View, shut : () -> Unit) {
      if remove != "" {
        @sf.button_node(
          v,
          fn() { @sf.t("web-pages.archivePolicy.remove") },
          fn() {
            shut()
            (core.call)("automaticDecisions.policy.edit", obj([("station", str(station)), ("form", str(form)), ("input", obj([("remove", str(remove))]))]), fn(
              _,
            ) {
              save()
            })
          },
          tone=GhostDanger,
        )
        |> ignore
      }
      @sf.foot_spacer_node(v)
      @sf.button_node(
        v,
        fn() { @sf.t("web-pages.archivePolicy.cancel") },
        fn() {
          v.focus_let_go()
          shut()
          edit([("reset", Json::boolean(true))])
        },
        tone=Ghost,
      )
      |> ignore
      @sf.button_node(
        v,
        fn() { @sf.t("web-pages.archivePolicy.save") },
        fn() {
          v.focus_let_go()
          shut()
          save()
        },
        tone=Primary,
        disabled=fn() { !flag(draft(), "dirty") },
      )
      |> ignore
    }
  }
  if id == "" && key == "" {
    open_dialog_nodes(
      @sf.t("web-pages.archivePolicy.title"),
      description=@sf.t("web-pages.archivePolicy.textLead"),
      wide=true,
      fn(v, _) {
        let f = words_of("policy", text(@signals.untracked(draft), "policy"))
        let area = @sf.textarea_node(v, f, rows=8, label=@sf.t("web-pages.archivePolicy.title"))
        on_typed(area, f, fn(words) {
          if @signals.untracked(draft) is Some(Object(_)) {
            edit([("policy", str(words))])
          }
        })
      },
      foot(""),
    )
    return
  }
  let fresh = key != ""
  open_dialog_nodes(
    if fresh {
      @sf.t("web-pages.archivePolicy.newOption")
    } else {
      text(ov, "name")
    },
    fn(v, shut) {
      // (the option as the draft has it now: none while it is read, nothing shown till then)
      let o = fn() {
        items(draft(), "options").iter().find_first(fn(x) { if fresh { text(Some(x), "key") == key } else { text(Some(x), "id") == id } })
      }
      let has = fn() { o() is Some(_) }
      // (its parts each shown once it is there, each made as the draft has it then: in the column the dialog gives
      // them, apart as it has them)
      let okey = fn() { text(@signals.untracked(o), "key") }
      v.show(has, fn(p) {
        @sf.field_node(p, fn() { @sf.t("web-pages.archivePolicy.name") }, fn(b) {
          let f = words_of("name", text(@signals.untracked(o), "name"))
          let line = @sf.input_node(b, f, label=@sf.t("web-pages.archivePolicy.name"))
          on_typed(line, f, fn(n) { edit([("option", str(okey())), ("name", str(n))]) })
        })
      })
      v.show(has, fn(p) {
        @sf.field_node(p, fn() { @sf.t("web-pages.archivePolicy.rubric") }, fn(b) {
          let f = words_of("rubric", text(@signals.untracked(o), "rubric"))
          let area = @sf.textarea_node(b, f, rows=3, label=@sf.t("web-pages.archivePolicy.rubric"))
          on_typed(area, f, fn(r) { edit([("option", str(okey())), ("rubric", str(r))]) })
        })
      })
      v.show(has, fn(p) {
        @sf.field_node(p, fn() { @sf.t("web-pages.archivePolicy.counts") }, fn(b) {
          // (the one pressed chosen at once, the draft's from then on as it says it)
          let picked : @signals.Signal[Int?] = @signals.signal(None)
          let drafted = fn() { if flag(o(), "archive") { 0 } else { 1 } }
          b.reacts(drafted, fn(_) { picked.set(None) })
          b.box(fn(line) {
            line.row(Is(true)) |> ignore
            line.box(fn(slot) {
              @sf.segmented_node(
                slot,
                fn() { [@sf.t("web-pages.archivePolicy.archive"), @sf.t("web-pages.archivePolicy.keep")] },
                fn() { picked.get().unwrap_or(drafted()) },
                fn(i) {
                  picked.set(Some(i))
                  edit([("option", str(okey())), ("archive", Json::boolean(i == 0))])
                },
              )
            })
            |> ignore
          })
          |> ignore
        })
      })
      // the chats the checks put there, each to its chat
      if count(ov, "count") > 0 {
        v.show(has, fn(p) {
          @sf.style_node(p, fn() { pol_chats })
          @sf.words_node(p, fn() { @sf.t("web-pages.archivePolicy.chats", args=[("days", count(policy, "days").to_string())]) }, fn() {
            pol_group_name
          })
          |> ignore
          for ch in items(ov, "chats") {
            let chv = Some(ch)
            p.box(fn(b) {
              @sf.style_node(b, fn() { pol_chat_box })
              @sf.presses_node(b, fn() {
                shut()
                edit([("reset", Json::boolean(true))])
                (core.open_chat)(station, text(chv, "session"), text(chv, "title"))
              })
              @sf.words_node(b, fn() { text(chv, "title") }, fn() { pol_chat }) |> ignore
            })
            |> ignore
          }
          let more = count(ov, "count") - items(ov, "chats").length()
          if more > 0 {
            @sf.words_node(p, fn() { @sf.t("web-pages.archivePolicy.more", args=[("n", more.to_string())]) }, fn() { pol_more })
            |> ignore
          }
        })
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
