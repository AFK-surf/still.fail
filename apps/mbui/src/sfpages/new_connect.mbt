// A new connect on the desktop, in a dialog (ember web/src/pages/Connect.tsx NewConnectDialog, CoreNewConnectDialog,
// SlackTeamIcon, TokenOwner, MadeAppSteps; FeishuConnect.tsx useFeishuStep; Connect.css.ts, FeishuConnect.css.ts): the
// core's wizard (`connectFlow {station, form}`: its step, title, count, what can be done, what is wrong) drawn a step
// at a time — the platform; Slack's (the workspace to make its app in, a configuration token to add, the app's look
// and permissions, making and installing it then its app-level token, or both tokens pasted by hand) or Feishu's (the
// model, how its conversations become sessions, a bot made by scanning or an app of one's own); last the model it
// runs. What is typed goes to the core's draft (`connect.flow.edit`), the way on (`connect.flow.go`), what is done
// (`connect.flow.<config|make|verify|register|create>`); added, its page.

///|
/// A wizard open on a station (its form), and what the dialog keeps of its own: the Feishu app's fields, the app's
/// look being made, whether it was opened and let go of.
priv struct NcFlow {
  station : String
  form : String
  resume : String
  app_id : @ui.Field
  app_secret : @ui.Field
  // (*_sent plain: what the core was last told, compared before telling it again)
  mut app_id_sent : String
  mut app_secret_sent : String
  look : @signals.Signal[SaDraft?]
  mut look_sent : String
  mut icon_sent : String
  gone : @signals.Signal[Bool]
}

///|
// kept across runs: counted by new_connect_dialog; new_connect_reset puts it back
let nc_made : Ref[Int] = Ref(0)

///|
fn new_connect_reset() -> Unit {
  nc_made.val = 0
}

///|
/// The calls that are the wizard's doing (useConnectFlow's actions).
// kept across runs: a table, never written
let nc_actions : Array[String] = [
  "connect.flow.config", "connect.flow.make", "connect.flow.verify", "connect.flow.register", "connect.flow.create",
]

///|
/// A new connect on `station`, in a dialog (NewConnectDialog): from the start, or (`resume`) from a Slack app made
/// before. Its wizard is opened once the frame is built, and let go of as the dialog closes.
pub fn new_connect_dialog(src : Source, core : Core, here : Here, station : String, resume? : String = "") -> Unit {
  nc_made.val += 1
  let key = "new-connect/" + nc_made.val.to_string()
  let f : NcFlow = {
    station,
    form: "desk-connect-" + nc_made.val.to_string(),
    resume,
    app_id: @ui.Field::new(),
    app_secret: @ui.Field::new(),
    app_id_sent: "",
    app_secret_sent: "",
    look: @signals.signal(None),
    look_sent: "",
    icon_sent: "",
    gone: @signals.signal(false, same=fn(a, b) { a == b }),
  }
  let opened = Ref(false)
  let view = fn() { (core.topic)("connectFlow", { "station": str(station), "form": str(f.form) }).value }
  open_dialog(
    @sf.t("web-pages.connects.add"),
    wide=true,
    live=fn() {
      let v = view()
      match v {
        Some(_) =>
          (
            text(v, "title"),
            text_number(v, "number").to_string() + " / " + text_number(v, "total").to_string(),
            if text(v, "step") == "team" && !flag(v, "gettingToken") {
              @sf.t("web-pages.connect.teamLead")
            } else {
              ""
            },
          )
        None => (@sf.t("web-pages.connects.add"), "", "")
      }
    },
    fn(c, shut) {
      if !opened.val {
        opened.val = true
        c.tell(key + "/open", fn() {
          (core.call)(
            "connect.flow.open",
            obj([
              ("station", str(station)),
              ("form", str(f.form)),
              // (no `mobile`: one page draws the one flow, the web desktop's, on every screen; told it, the core's phone flow
              // asked for a step of its own (token) this page has not)
              ("input", obj([("resume", if resume == "" { Json::null() } else { str(resume) })])),
            ]),
            fn(r) {
              match r {
                Ok(_) => ()
                Err(e) => (core.say)(error_text(e))
              }
            },
          )
        })
      }
      nc_body(c, src, core, here, f, view(), fn() { nc_close(core, f, shut) })
    },
    fn(c, shut) { nc_foot(c, core, here, f, view(), fn() { nc_close(core, f, shut) }) },
    on_gone=fn() { nc_drop(core, f) },
  )
}

///|
/// The dialog closed: its wizard and its tokens' draft let go of.
fn nc_close(core : Core, f : NcFlow, shut : () -> Unit) -> Unit {
  shut()
  nc_drop(core, f)
}

///|
/// Its wizard and tokens' draft let go of, once.
fn nc_drop(core : Core, f : NcFlow) -> Unit {
  if !f.gone.get() {
    f.gone.set(true)
    (core.call)("connect.flow.drop", obj([("station", str(f.station)), ("form", str(f.form))]), fn(_) {  })
    for k in slack_token_forms.keys().to_array() {
      if k.has_prefix("flow/" + f.form) {
        slack_token_forms.remove(k)
      }
    }
  }
}

///|
/// What is typed sent to the wizard's draft (`connect.flow.edit`).
fn nc_edit(core : Core, f : NcFlow, input : Json) -> Unit {
  (core.call)("connect.flow.edit", obj([("station", str(f.station)), ("form", str(f.form)), ("input", input)]), fn(r) {
    match r {
      Ok(_) => ()
      Err(e) => (core.say)(error_text(e))
    }
  })
}

///|
/// The way on (`connect.flow.go`): the core moves the wizard; where it says to close, it closes.
fn nc_go(core : Core, f : NcFlow, to : String, close : () -> Unit) -> Unit {
  (core.call)("connect.flow.go", obj([("station", str(f.station)), ("form", str(f.form)), ("input", obj([("to", str(to))]))]), fn(
    r,
  ) {
    match r {
      Ok(v) => if flag(Some(v), "close") { close() }
      Err(e) => (core.say)(error_text(e))
    }
  })
}

///|
/// What the wizard does (`connect.flow.<action>`), not while it is doing another; `done` its answer.
fn nc_act(core : Core, f : NcFlow, action : String, done? : (Json) -> Unit = fn(_) {  }) -> Unit {
  if nc_busy(core, f) {
    return
  }
  (core.call)("connect.flow." + action, obj([("station", str(f.station)), ("form", str(f.form))]), fn(r) {
    match r {
      Ok(v) => done(v)
      Err(e) => (core.say)(error_text(e))
    }
  })
}

///|
/// Whether the wizard is doing something, and why what it did last failed ("" none).
fn nc_busy(core : Core, f : NcFlow) -> Bool {
  is_doing(core, nc_actions, [("station", f.station), ("form", f.form)])
}

///|
fn nc_error(core : Core, f : NcFlow) -> String {
  failed_of(core, nc_actions, [("station", f.station), ("form", f.form)]).unwrap_or("")
}

///|
/// The connect added: said, the dialog closed onto its page.
fn nc_added(core : Core, f : NcFlow, id : String, close : () -> Unit, feishu : Bool) -> Unit {
  (core.say)(@sf.t(if feishu { "web-pages.connect.feishu.added" } else { "web-pages.connect.added" }))
  close()
  (core.push)(Connect(f.station, id))
}

///|
/// The wizard's tokens' draft (useSlackTokens with its form), opened for an app installed through Slack (`install`).
fn nc_tokens(c : @ui.Ctx, core : Core, f : NcFlow, install : String) -> SlackTokens {
  slack_tokens(c, core, f.station, "flow/" + f.form + "/" + install, install~, form=f.form)
}

///|
/// The step shown (CoreNewConnectDialog's body; useFeishuStep's).
fn nc_body(c : @ui.Ctx, src : Source, core : Core, here : Here, f : NcFlow, v : Json?, close : () -> Unit) -> Unit {
  guard v is Some(Object(_)) else { @settings.wait_line(c, @sf.t("common.reading")) }
  let step = text(v, "step")
  let fe = field(v, "feishu")
  let error = nc_error(core, f)
  // added on its own (a bot made by scanning): its page, once the frame is built
  if step == "done" && opt_text(fe, "connect") is Some(_) && !f.gone.get() {
    c.tell("nc-added/" + f.form, fn() { nc_watch_added(core, f, v, close) })
  }
  c.box(style=nc_body_box, fn() {
    match step {
      "platform" => {
        let offered = strings(v, "platforms").contains("feishu")
        let platform = opt_text(v, "platform").unwrap_or("slack")
        let picked = @sf.choices(
          c,
          "nc-platform/" + f.form,
          platform,
          [
            ("slack", "Slack", @sf.t("web-pages.connect.feishu.slackNote")),
            (
              "feishu",
              @sf.t("web-pages.connect.feishu.name"),
              @sf.t(if offered { "web-pages.connect.feishu.feishuNote" } else { "web-pages.connect.feishu.update" }),
            ),
          ],
          label=@sf.t("web-pages.connect.feishu.platform"),
          disabled=if offered { [] } else { ["feishu"] },
          icon=fn(p) {
            c.box(style=nc_platform_mark, fn() {
              if p == "feishu" {
                @sf.feishu_mark(c, nc_platform_size) |> ignore
              } else {
                @sf.slack_mark(c, nc_platform_size) |> ignore
              }
            })
            |> ignore
          },
        )
        if picked != platform {
          nc_edit(core, f, obj([("platform", str(picked))]))
        }
      }
      "feishuBind" | "bind" => {
        nc_models(c, src, core, f, v)
        @sf.field(c, @sf.t("web-pages.connect.mode"), fn() {
          let (m, r) = mode_choices(c, "nc-mode/" + f.form, field(v, "modeWords"), text(v, "mode"), flag(v, "requireMention"))
          if m != text(v, "mode") || r != flag(v, "requireMention") {
            nc_edit(core, f, obj([("mode", str(m)), ("requireMention", Json::boolean(r))]))
          }
        })
        if step == "bind" && error != "" {
          c.text(error, style=desk_note_bad) |> ignore
        }
      }
      "feishuWay" => {
        let way = text(fe, "way")
        let picked = @sf.choices(
          c,
          "nc-way/" + f.form,
          way,
          [
            ("scan", @sf.t("web-pages.connect.feishu.scan"), @sf.t("web-pages.connect.feishu.scanNote")),
            ("app", @sf.t("web-pages.connect.feishu.app"), @sf.t("web-pages.connect.feishu.appNote")),
          ],
          label=@sf.t("web-pages.connect.feishu.way"),
        )
        if picked != way {
          nc_edit(core, f, obj([("feishu", obj([("way", str(picked))]))]))
        }
        if error != "" {
          c.text(error, style=desk_note_bad) |> ignore
        }
      }
      "feishuScan" => nc_scan(c, core, fe)
      "done" if field(fe, "registration") is Some(Object(_)) => nc_scan(c, core, fe)
      "feishuApp" | "done" => nc_feishu_app(c, core, f, fe, error)
      "team" => nc_team(c, core, f, v, close)
      "app" => {
        let d = match f.look.get() {
          Some(d) => d
          None => {
            let d = sa_draft("nc-look/" + f.form, field(v, "settings"))
            f.look.set(Some(d))
            f.look_sent = sa_settings(d, field(v, "settings")).stringify()
            d
          }
        }
        app_fields(c, core, d, items(v, "sections"), true, nc_inner_w)
        // what is picked and typed goes to the draft; the icon made too
        let now = sa_settings(d, field(v, "settings"))
        if now.stringify() != f.look_sent {
          f.look_sent = now.stringify()
          c.tell("nc-look/" + f.form, fn() { nc_edit(core, f, obj([("settings", now)])) })
        }
        let icon = d.icon.get() + "\u{1}" + d.icon_error.get()
        if icon != f.icon_sent {
          f.icon_sent = icon
          c.tell("nc-icon/" + f.form, fn() {
            nc_edit(core, f, obj([("icon", if d.icon.get() == "" { Json::null() } else { str(d.icon.get()) }), ("iconError", if d.icon_error.get() == "" {
              Json::null()
            } else {
              str(d.icon_error.get())
            })]))
          })
        }
        match opt_text(v, "iconError") {
          Some(e) if e != "" => c.text(e, style=desk_note_bad) |> ignore
          _ => ()
        }
        if error != "" {
          c.text(error, style=desk_note_bad) |> ignore
        }
      }
      "install" =>
        match field(v, "made") {
          Some(Object(_)) as made => {
            nc_made_steps(c, core, f, made)
            match opt_text(v, "iconError") {
              Some(e) if e != "" => c.text(@sf.t("web-pages.connect.iconFailed", args=[("error", e)]), style=desk_note_bad) |> ignore
              _ => ()
            }
            token_fields(c, core, nc_tokens(c, core, f, text(made, "state")), install=opt_text(made, "install") is Some(_))
          }
          _ => ()
        }
      "manual" => {
        create_app_steps(c, core, f.station, "still.fail")
        token_fields(c, core, nc_tokens(c, core, f, ""))
      }
      _ => ()
    }
  })
  |> ignore
}

///|
/// The model it runs (a Field): the core's pick of `connect-new:<form>` in the model control, both runtimes said
/// where its model runs on more than one; none on the station, to its profiles.
fn nc_models(c : @ui.Ctx, src : Source, core : Core, f : NcFlow, v : Json?) -> Unit {
  let pick = field(v, "pick")
  let runtimes = strings(field(pick, "valueOption"), "runtimes")
  @sf.field(c, @sf.t("web-pages.profiles.models"), hint=if runtimes.length() > 1 { @sf.t("web-pages.connect.bothRuntimes") } else { "" }, fn() {
    if items(pick, "options").length() == 0 {
      if cd_link(c, "nc-no-models/" + f.form, @sf.t("web-pages.connect.noModels")) {
        (core.push)(Profiles(f.station))
      }
    } else {
      model_triple(c, src, f.station, "connect-new:" + f.form)
    }
  })
}

///|
/// The Slack workspace to make its app in (the team step): getting a configuration token, as a view of its own while
/// there is none or another is added (why, the form, the way by hand where there is none); else the workspaces, each
/// its icon and whose token it is, 添加配置 token and 手动创建 under them.
fn nc_team(c : @ui.Ctx, core : Core, f : NcFlow, v : Json?, close : () -> Unit) -> Unit {
  let teams = items(v, "teams")
  if flag(v, "gettingToken") {
    c.box(style=nc_token_start, fn() {
      c.text(@sf.t("web-pages.connect.tokenWhy", args=[("name", "still.fail")]), style=desk_muted) |> ignore
      config_token_form(c, core, f.station, "nc-config/" + f.form, fn() {  }, flow=(
        v,
        fn() { nc_act(core, f, "config") },
        fn(token) { nc_edit(core, f, obj([("config", str(token))])) },
      ))
      if teams.length() == 0 {
        c.box(style=nc_manual_line, fn() {
          c.text(@sf.t("web-pages.connect.noToken"), style=nc_meta) |> ignore
          if cd_text_button(c, "nc-manual/" + f.form, @sf.t("web-pages.connect.manualApp")) {
            nc_go(core, f, "manual", close)
          }
        })
        |> ignore
      }
    })
    |> ignore
    return
  }
  let chosen = text(field(v, "chosen"), "teamId")
  let picked = @sf.choices(
    c,
    "nc-team/" + f.form,
    chosen,
    teams.map(fn(t) { (text(Some(t), "teamId"), text(Some(t), "name"), "") }),
    label=@sf.t("web-pages.connect.slackWorkspace"),
    icon=fn(id) {
      match teams.iter().find_first(fn(t) { text(Some(t), "teamId") == id }) {
        Some(t) => nc_team_icon(c, core, field(Some(t), "owner"))
        None => ()
      }
    },
    note=fn(id) {
      match teams.iter().find_first(fn(t) { text(Some(t), "teamId") == id }) {
        Some(t) => nc_token_owner(c, core, field(Some(t), "owner"))
        None => ()
      }
    },
  )
  if picked != chosen {
    nc_edit(core, f, obj([("team", str(picked))]))
  }
  c.box(style=nc_team_more, fn() {
    if @sf.button(c, @sf.t("web-pages.connect.addTeamToken"), key="nc-add-token/" + f.form, tone=Ghost, icon="plus") {
      nc_edit(core, f, obj([("adding", Json::boolean(true))]))
    }
    if cd_text_button(c, "nc-manual-short/" + f.form, @sf.t("web-pages.connect.manualShort")) {
      nc_go(core, f, "manual", close)
    }
  })
  |> ignore
}

///|
/// A Slack workspace's icon (SlackTeamIcon: its picture 28, round; Slack's mark 18 before it is known).
fn nc_team_icon(c : @ui.Ctx, core : Core, owner : Json?) -> Unit {
  c.box(style=nc_team_icon_box, fn() {
    match opt_text(owner, "teamIcon") {
      Some(url) if url != "" => avatar(c, core, url, "", nc_team_icon_size, picture=url)
      _ => @sf.slack_mark(c, nc_slack_size) |> ignore
    }
  })
  |> ignore
}

///|
/// Whose configuration token it is there (TokenOwner: their picture 16, their name and email, the workspace's address
/// muted, 6 apart).
fn nc_token_owner(c : @ui.Ctx, core : Core, o : Json?) -> Unit {
  guard o is Some(Object(_)) else { return }
  c.box(style=nc_owner_line, flow=true, fn() {
    match opt_text(o, "image") {
      Some(url) if url != "" => avatar(c, core, url, text(o, "user"), nc_owner_size, picture=url)
      _ => ()
    }
    let email = text(o, "email")
    c.text(text(o, "user") + (if email != "" { "（" + email + "）" } else { "" }), style=nc_meta_ink) |> ignore
    match opt_text(o, "teamDomain") {
      Some(d) if d != "" => c.text(d + ".slack.com", style=nc_meta) |> ignore
      _ => ()
    }
  })
  |> ignore
}

///|
/// What is left in Slack once the app is made (MadeAppSteps): installing it (through Slack's OAuth, which sends the
/// bot token to the station itself; else by hand, its OAuth page to copy it from), its app-level token, the token or
/// tokens filled in below.
fn nc_made_steps(c : @ui.Ctx, core : Core, f : NcFlow, made : Json?) -> Unit {
  let links = field(made, "links")
  let oauth = opt_text(made, "install")
  @sf.steps(c, [
    fn() {
      match oauth {
        Some(url) =>
          if flag(made, "installed") {
            @sf.verify_ok(
              c,
              @sf.t("web-pages.cloud.slackInstalled.done", args=[
                ("team", first_text(made, ["installedTeam", "team"], @sf.t("web-pages.cloud.slackInstalled.workspace"))),
              ]),
            )
          } else {
            c.text(@sf.t("web-pages.connect.made.oauth"), style=@sf.step_words) |> ignore
            if @sf.button(c, @sf.t("web-pages.connect.made.install"), key="nc-install/" + f.form, tone=Primary, icon="external") {
              (core.open_link)(url)
            }
          }
        None => {
          c.text(@sf.t("web-pages.connect.made.manual"), style=@sf.step_words) |> ignore
          if @sf.button(c, @sf.t("web-pages.connect.made.install"), key="nc-install/" + f.form, tone=Primary, icon="external") {
            (core.open_link)(text(links, "install"))
          }
          if @sf.button(c, @sf.t("web-pages.connect.made.openOauth"), key="nc-oauth/" + f.form) {
            (core.open_link)(text(links, "oauth"))
          }
        }
      }
    },
    fn() {
      c.text(@sf.t("web-pages.connect.made.appToken"), style=@sf.step_words) |> ignore
      if @sf.button(c, @sf.t("web-pages.connect.made.openSocket"), key="nc-socket/" + f.form, icon="external") {
        (core.open_link)(text(links, "appToken"))
      }
    },
    fn() {
      c.text(@sf.t(if oauth is Some(_) { "web-pages.connect.made.fillOne" } else { "web-pages.connect.made.fillBoth" }), style=@sf.step_words)
      |> ignore
    },
  ])
}

///|
/// A Feishu bot being made by scanning (useFeishuStep's scan step: FeishuConnect.css.ts scan): its QR code 196 (or, before
/// it, a ring or Feishu's mark in its place), beside it (narrow: under it) where it stands (a ring while the connect is
/// added, red where it failed), what went wrong, and while it waits how to scan it and the way to open it on this
/// device.
fn nc_scan(c : @ui.Ctx, core : Core, fe : Json?) -> Unit {
  let r = field(fe, "registration")
  let waiting = text(r, "state") == "waiting"
  let failing = flag(fe, "failed") || opt_text(fe, "error") is Some(_)
  // (narrow, its words under the code: beside it they had a phone's leftover hundred points, three lines a sentence
  // and the button cut off)
  @sf.figure_words(c, fn() {
    match field(fe, "qr") {
      Some(Object(_)) as code => @sf.qr_code(c, code, nc_qr_size, @sf.t("web-pages.connect.feishu.qr"))
      _ =>
        c.box(style=nc_qr_place, fn() {
          if (flag(fe, "creating") || text(r, "state") == "done") && opt_text(fe, "error") is None {
            @sf.spinner(c) |> ignore
          } else {
            @sf.feishu_mark(c, nc_feishu_size) |> ignore
          }
        })
        |> ignore
    }
  }, fn() {
    c.box(style=desk_said_line, fn() {
      if flag(fe, "creating") || (text(r, "state") == "done" && opt_text(fe, "error") is None && opt_text(fe, "connect") is None) {
        @sf.spinner(c, size=cd_icon) |> ignore
      }
      c.text(text(fe, "stateText"), style=if failing { nc_scan_bad } else { desk_words }) |> ignore
    })
    |> ignore
    match opt_text(fe, "error") {
      Some(e) => c.text(e, style=desk_note_bad) |> ignore
      None => ()
    }
    if waiting {
      c.text(@sf.t("web-pages.connect.feishu.scanHint"), style=desk_muted) |> ignore
      if @sf.button(c, @sf.t("web-pages.connect.feishu.openInFeishu"), key="nc-feishu-open", icon="external") {
        (core.open_link)(text(r, "url"))
      }
    }
  })
}

///|
/// A Feishu app of one's own (useFeishuStep's app step): where to find it (its console opened), its App ID and App
/// Secret (what verifying found wrong under the secret), whether it is Lark's; who it was verified as.
fn nc_feishu_app(c : @ui.Ctx, core : Core, f : NcFlow, fe : Json?, error : String) -> Unit {
  let lark = flag(fe, "lark")
  c.box(style=nc_hint_line, flow=true, fn() {
    c.text(@sf.t("web-pages.connect.feishu.appHint"), style=desk_muted) |> ignore
    if cd_link(c, "nc-console/" + f.form, @sf.t("web-pages.connect.feishu.openConsole")) {
      (core.open_link)(if lark { "https://open.larksuite.com/app" } else { "https://open.feishu.cn/app" })
    }
  })
  |> ignore
  // (the fields echo what is typed; the core has it a moment later)
  if f.app_id_sent == "" && f.app_id.text() == "" && text(fe, "appId") != "" {
    f.app_id.set(text(fe, "appId"))
    f.app_id_sent = text(fe, "appId")
  }
  @sf.field(c, "App ID", fn() {
    let typed = @sf.input(c, "nc-app-id/" + f.form, placeholder="cli_…", field=f.app_id).text
    if typed != f.app_id_sent {
      f.app_id_sent = typed
      c.tell("nc-app-id/" + f.form, fn() { nc_edit(core, f, obj([("feishu", obj([("appId", str(typed))]))])) })
    }
  })
  let errors = strings(fe, "errors")
  @sf.field(c, "App Secret", error=errors.iter().fold(init="", fn(a, e) { if a == "" { e } else { a + "；" + e } }), fn() {
    let typed = @sf.input(c, "nc-app-secret/" + f.form, secret=true, field=f.app_secret).text
    if typed != f.app_secret_sent {
      f.app_secret_sent = typed
      c.tell("nc-app-secret/" + f.form, fn() { nc_edit(core, f, obj([("feishu", obj([("appSecret", str(typed))]))])) })
    }
  })
  let now = @sf.switch_row(c, "nc-lark/" + f.form, @sf.t("web-pages.connect.feishu.lark"), lark, note=@sf.t("web-pages.connect.feishu.larkNote"))
  if now != lark {
    nc_edit(core, f, obj([("feishu", obj([("lark", Json::boolean(now))]))]))
  }
  let identity = field(fe, "identity")
  if flag(fe, "verified") && identity is Some(Object(_)) {
    let tenant = text(field(identity, "tenant"), "name")
    @sf.verify_ok(
      c,
      if tenant != "" {
        @sf.t("web-pages.connect.feishu.verified", args=[("bot", text(identity, "botName")), ("tenant", tenant)])
      } else {
        @sf.t("web-pages.connect.feishu.verifiedBot", args=[("bot", text(identity, "botName"))])
      },
    )
  }
  let said = match opt_text(fe, "error") {
    Some(e) => e
    None => error
  }
  if said != "" {
    c.text(said, style=desk_note_bad) |> ignore
  }
}

///|
/// The dialog's buttons for the step shown (CoreNewConnectDialog's footer; useFeishuStep's): back (or 取消) and the
/// way on, each as the core says the step stands.
fn nc_foot(c : @ui.Ctx, core : Core, here : Here, f : NcFlow, v : Json?, close : () -> Unit) -> Unit {
  ignore(here)
  guard v is Some(Object(_)) else {
    if @sf.button(c, @sf.t("common.cancel"), key="nc-cancel/" + f.form, tone=Ghost) {
      close()
    }
  }
  let step = text(v, "step")
  let fe = field(v, "feishu")
  let busy = nc_busy(core, f)
  let back = fn(label : String) {
    if @sf.button(c, label, key="nc-back/" + f.form, tone=Ghost) {
      nc_go(core, f, "back", close)
    }
  }
  let next = fn(label : String, disabled : Bool, busy : Bool, run : () -> Unit) {
    if @sf.button(c, label, key="nc-next/" + f.form, tone=Primary, disabled~, busy~) {
      run()
    }
  }
  let feishu_back = fn() { back(@sf.t(if text(v, "back") == "close" { "common.cancel" } else { "web-pages.connect.previous" })) }
  match step {
    "platform" => {
      feishu_back()
      let feishu = opt_text(v, "platform") == Some("feishu") && strings(v, "platforms").contains("feishu")
      next(@sf.t("web-pages.connect.next"), false, false, fn() { nc_go(core, f, if feishu { "feishuBind" } else { "team" }, close) })
    }
    "feishuBind" => {
      feishu_back()
      next(@sf.t("web-pages.connect.next"), !flag(v, "canCreate"), false, fn() { nc_go(core, f, "feishuWay", close) })
    }
    "feishuWay" => {
      feishu_back()
      next(@sf.t("web-pages.connect.next"), false, busy, fn() {
        if text(fe, "way") == "app" {
          nc_go(core, f, "feishuApp", close)
        } else {
          nc_act(core, f, "register")
        }
      })
    }
    "feishuScan" => nc_scan_foot(c, core, f, fe, feishu_back, busy, close)
    "done" if field(fe, "registration") is Some(Object(_)) => nc_scan_foot(c, core, f, fe, feishu_back, busy, close)
    "feishuApp" | "done" => {
      feishu_back()
      if flag(fe, "verified") {
        next(@sf.t("web-pages.connect.addConnect"), false, busy || flag(fe, "creating"), fn() {
          nc_act(core, f, "create", done=fn(a) { nc_added(core, f, text(Some(a), "id"), close, true) })
        })
      } else {
        next(@sf.t("web-pages.connect.feishu.verify"), !flag(fe, "canVerify"), busy, fn() { nc_act(core, f, "verify") })
      }
    }
    "team" => {
      let adding = flag(v, "adding")
      let teams = items(v, "teams")
      if adding && teams.length() > 0 {
        if @sf.button(c, @sf.t("common.back"), key="nc-back/" + f.form, tone=Ghost) {
          nc_edit(core, f, obj([("adding", Json::boolean(false))]))
        }
      } else if text(v, "back") == "platform" {
        back(@sf.t("web-pages.connect.previous"))
      } else if @sf.button(c, @sf.t("common.cancel"), key="nc-cancel/" + f.form, tone=Ghost) {
        close()
      }
      if !flag(v, "gettingToken") {
        next(@sf.t("web-pages.connect.next"), !(field(v, "chosen") is Some(Object(_))), false, fn() { nc_go(core, f, "app", close) })
      }
    }
    "app" => {
      if @sf.button(c, @sf.t("web-pages.connect.previous"), key="nc-back/" + f.form, tone=Ghost) {
        nc_go(core, f, "team", close)
      }
      next(@sf.t("web-pages.connect.createApp"), !flag(v, "canMake"), busy, fn() { nc_act(core, f, "make") })
    }
    "install" | "manual" => {
      if step == "manual" {
        if @sf.button(c, @sf.t("web-pages.connect.previous"), key="nc-back/" + f.form, tone=Ghost) {
          nc_go(core, f, "team", close)
        }
      } else if @sf.button(c, @sf.t("common.cancel"), key="nc-cancel/" + f.form, tone=Ghost) {
        close()
      }
      let install = text(field(v, "made"), "state")
      let tk = nc_tokens(c, core, f, if step == "install" { install } else { "" })
      next(@sf.t("web-pages.connect.next"), !tokens_ready(core, tk), busy || tokens_busy(core, tk), fn() { nc_act(core, f, "verify") })
    }
    _ => {
      if @sf.button(c, @sf.t("web-pages.connect.previous"), key="nc-back/" + f.form, tone=Ghost) {
        nc_go(core, f, if opt_text(v, "madeId") is Some(_) { "install" } else { "manual" }, close)
      }
      next(@sf.t("web-pages.connect.addConnect"), items(field(v, "pick"), "options").length() == 0, busy, fn() {
        nc_act(core, f, "create", done=fn(a) { nc_added(core, f, text(Some(a), "id"), close, false) })
      })
    }
  }
}

///|
/// The scan step's buttons: back, and a new QR code where it ended without an app, or trying again where adding the
/// connect failed.
fn nc_scan_foot(c : @ui.Ctx, core : Core, f : NcFlow, fe : Json?, back : () -> Unit, busy : Bool, close : () -> Unit) -> Unit {
  ignore(close)
  back()
  if flag(fe, "failed") {
    if @sf.button(c, @sf.t("web-pages.connect.feishu.newQr"), key="nc-qr/" + f.form, tone=Primary, icon="refresh", busy~) {
      nc_act(core, f, "register")
    }
  } else if opt_text(fe, "error") is Some(_) {
    if @sf.button(c, @sf.t("web-pages.connect.feishu.retry"), key="nc-retry/" + f.form, tone=Primary, busy=busy || flag(fe, "creating")) {
      nc_act(core, f, "create")
    }
  }
}

///|
/// Watching for a Feishu connect added on its own (its bot made by scanning): its page, once.
fn nc_watch_added(core : Core, f : NcFlow, v : Json?, close : () -> Unit) -> Unit {
  if text(v, "step") == "done" && text(v, "platform") == "feishu" {
    match opt_text(field(v, "feishu"), "connect") {
      Some(id) if !f.gone.get() => nc_added(core, f, id, close, true)
      _ => ()
    }
  }
}

///|
/// The sizes: a platform's mark 22 in its 28 square, a team's icon 28 (Slack's mark 18), its owner's picture 16, the QR
/// code 196 (Feishu's mark 40 in its place), the dialog's inside (a wide dialog's 640 less its 24 each side).
let nc_platform_size : Double = 22.0

///|
let nc_team_icon_size : Double = 28.0

///|
let nc_slack_size : Double = 18.0

///|
let nc_owner_size : Double = 16.0

///|
let nc_qr_size : Double = 196.0

///|
let nc_feishu_size : Double = 40.0

///|
let nc_inner_w : Double = 592.0

///|
// kept across runs: a value (no field of it changes)
let nc_body_box : @ui.Style = @ui.css("w=Full gap=S4")

///|
// kept across runs: a value (no field of it changes)
let nc_platform_mark : @ui.Style = @ui.css("w=S7 h=S7 align=ACenter justify=JCenter")

///|
/// Getting a token (tokenStart: 8 apart; tokenManual: the meta's 12, 8 over it).
// kept across runs: a value (no field of it changes)
let nc_token_start : @ui.Style = @ui.css("w=Full gap=S2")

///|
// kept across runs: a value (no field of it changes)
let nc_manual_line : @ui.Style = @ui.css("row w=Full pt=S2 gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let nc_meta : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let nc_meta_ink : @ui.TextStyle = nc_meta.then(@ui.text_style(color=Fg))

///|
/// The workspaces' foot (teamMore: 添加 and 手动 at its ends, 8 under them).
// kept across runs: a value (no field of it changes)
let nc_team_more : @ui.Style = @ui.css("row w=Full pt=S2 align=ACenter justify=JBetween")

///|
// kept across runs: a value (no field of it changes)
let nc_team_icon_box : @ui.Style = @ui.css("w=S7 h=S7 radius=Full clip align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let nc_owner_line : @ui.Style = @ui.css("row w=Full gap=S1_5 align=ACenter")

///|
/// Scanning (scan: the code and its words, @sf.figure_words; qrPlace: 196, the dialog's inner corner, on the neutral
/// ground; scanBad: red).
// kept across runs: a value (no field of it changes)
let nc_qr_place : @ui.Style = @ui.style(w=Fixed(nc_qr_size), h=Fixed(nc_qr_size)).then(@ui.css("radius=Xl bg=Neutral align=ACenter justify=JCenter"))


///|
// kept across runs: a value (no field of it changes)
let nc_scan_bad : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Danger, w=Full)

///|
// kept across runs: a value (no field of it changes)
let nc_hint_line : @ui.Style = @ui.css("row w=Full gap=S1 align=ACenter")
