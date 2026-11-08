// A connect's page, one in every frame, laid out by its width (web/src/pages/Connect.tsx ConnectPage, ConnectDetail, SlackSection,
// ConnectTrouble, TokenDialog, ModeChoices, RunSection, ModeDialog, ChooseSessionDialog, ConnectSessions,
// OwnerDialog; Connect.css.ts; FeishuConnect.tsx FeishuSection, SecretDialog; FeishuConnect.css.ts): back to the
// connects; who it is and whether it is up (its picture, its name, how it is, where it is reached, its station, who
// owns it; what is done to it less often in its ⋯); what its link needs (Slack's tokens, or why it fails); how it runs
// (its model, how its conversations become sessions and the one they go into); a Feishu connect's app; its latest
// sessions. Everything said is the core's (its connects view, the core's ModeWords and ModeChange).

///|
/// A connect's page (ConnectPage, ConnectScreen), by its station and id: a wait until the connects are read (its
/// station's among them); one gone, that it is not there.
pub fn connect_page(c : @ui.Ctx, src : Source, core : Core, here : Here, frame : PageFrame, station : String, id : String) -> Unit {
  let connects = (core.topic)("connects", { "scope": str(here.workspace), "mine": Json::boolean(false) }).get()
  let found = items(connects.value, "items").iter().find_first(fn(i) {
    text(Some(i), "station") == station && text(field(Some(i), "connect"), "id") == id
  })
  let wait = field(connects.value, "wait")
  let key = "connect/" + station + "/" + id
  let back = @sf.t("web-pages.settings.nav.connects")
  if connects.value is None ||
    (found is None && (flag(wait, "reading") || items(wait, "failing").length() > 0)) {
    let error = match connects.error {
      Some(e) => error_text(e)
      None => ""
    }
    if error != "" {
      @sf.page(c, on_back=core.pop, frame~, key, back, [fn() { @sf.page_note(c, error, bad=true) }])
    } else {
      // (read the first time: a connect's page of made-up words, in its bones)
      @sf.page_waiting(
        c,
        back,
        text=@sf.t("web-pages.connect.loading"),
        note={ reading: flag(wait, "reading"), text: "", failing: failing_of(wait) },
        fn() {
          connect_detail(c, @sfbase.sample_source, core.quiet(), here, frame, Some({
            "station": "sample",
            "stationName": Json::string(@sf.sample_words(4)),
            "connect": {
              "id": "sample",
              "name": Json::string(@sf.sample_words(8)),
              "kind": "slack",
              "connection": { "state": "connected" },
            },
          }))
        },
      )
    }
    return
  }
  match found {
    None =>
      @sf.page(c, on_back=core.pop, frame~, key, back, [
        fn() { @sf.page_note(c, @sf.t("web-pages.connect.notFound", args=[("id", id)])) },
      ])
    Some(item) => connect_detail(c, src, core, here, frame, Some(item))
  }
}

///|
/// What a block of a page shows, said as its data (what it reads: its version on its page's list, @sf.page's `keys`).
pub fn json_sign(v : Json?) -> String {
  match v {
    Some(j) => j.stringify()
    None => ""
  }
}

///|
/// The page of a connect found (ConnectDetail), the same parts in the same order on every screen: who it is and whether
/// it is up (its head); what its link needs first where it does (Slack's tokens, or why it fails); how it runs (its
/// model, how its conversations become sessions, the one they go into); its app (a Feishu one's ID and secret, a Slack
/// one's look and permissions, folded); its latest sessions.
fn connect_detail(c : @ui.Ctx, src : Source, core : Core, here : Here, frame : PageFrame, item : Json?) -> Unit {
  let cv = field(item, "connect")
  let station = text(item, "station")
  let id = text(cv, "id")
  let feishu = text(cv, "kind") == "feishu"
  // (a Comma connect has no app of its own: its line is all it connects with)
  let comma = text(cv, "kind") == "comma"
  let blocks : Array[() -> Unit] = []
  // (each block by what it is and what it shows: one come or gone opens or closes where it is, one showing another
  // thing goes to its height, @sf.page's `keys`)
  let keys : Array[(String, String)] = []
  let sign = json_sign(cv)
  // what its link needs: Slack's tokens, or why it fails (a Feishu connect's only why)
  let state = text(field(cv, "connection"), "state")
  if !feishu && !comma && state == "no_tokens" {
    blocks.push(fn() { cd_slack_section(c, core, station, cv) })
    keys.push(("tokens", sign))
  } else if cd_trouble(cv) != "" {
    blocks.push(fn() { cd_callout(c, cd_trouble(cv)) })
    keys.push(("trouble", cd_trouble(cv)))
  }
  blocks.push(fn() { cd_run_section(c, src, core, here, station, item) })
  keys.push(("run", json_sign(item)))
  if feishu {
    if field(cv, "feishu") is Some(Object(_)) {
      blocks.push(fn() { cd_feishu_section(c, core, station, cv) })
      keys.push(("feishu", sign))
    }
  } else if !comma {
    blocks.push(fn() { slack_app_section(c, core, station, cv) })
    keys.push(("app", sign))
  }
  blocks.push(fn() { cd_sessions(c, core, station, item) })
  keys.push(("sessions", json_sign(item)))
  @sf.page(c, on_back=core.pop, frame~, "connect/" + station + "/" + id, text(cv, "name"), blocks, keys~, small=@sf.t("android-misc.bar.place.connects"), head=fn() {
    cd_identity(c, core, here, station, text(item, "stationName"), cv)
  })
}

///|
/// Who it is and whether it is up (its head): its picture, its name, where people reach it and its station; how it is
/// (being reconnected, switched or saved: a ring and so; failed a moment ago: a red mark and so; else its dot and
/// state) and who owns it; its ⋯ at the end.
fn cd_identity(c : @ui.Ctx, core : Core, here : Here, station : String, station_name : String, cv : Json?) -> Unit {
  let id = text(cv, "id")
  let on = [("station", station), ("id", id)]
  let reconnecting = is_doing(core, ["connect.reconnect"], on)
  let saving = is_doing(core, ["connect.put"], on)
  let switching = saving && cd_switching.get(station + "/" + id).unwrap_or(false)
  let doing = if reconnecting {
    @sf.t("common.reconnecting")
  } else if switching {
    @sf.t(if flag(cv, "enabled") { "web-pages.connect.disabling" } else { "web-pages.connect.enabling" })
  } else if saving {
    @sf.t("common.saving")
  } else {
    ""
  }
  let failing = match failed_of(core, ["connect.reconnect"], on) {
    Some(_) => @sf.t("web-pages.connect.reconnectFailedShort")
    None =>
      match failed_of(core, ["connect.put"], on) {
        Some(_) => @sf.t("web-pages.connect.saveFailedShort")
        None => ""
      }
  }
  @sf.own_head(
    c,
    fn(side) { cd_avatar(c, core, cv, side) },
    text(cv, "name"),
    lines=[join([text(cv, "placeText"), station_name], " · ")],
    state=fn() {
      if doing != "" {
        @sf.spinner(c, size=cd_icon) |> ignore
        c.text(doing, style=cd_sub_words) |> ignore
      } else if failing != "" {
        doing_mark(c, false, Some(failing), inline=true)
        c.text(failing, style=cd_sub_words) |> ignore
      } else {
        @sf.status_dot(c, text(cv, "presence"))
        c.text(text(cv, "statusText"), style=cd_sub_words) |> ignore
      }
      c.text(@sf.t("web-pages.connect.owner"), style=cd_sub_words) |> ignore
      cn_owner(c, core, station + "/" + text(cv, "id"), field(cv, "createdBy"))
    },
    actions=fn() { cd_menu(c, core, here, station, cv) },
  )
}

///|
/// Whether the connect's last write was its turning on or off (said as such meanwhile), by station/id.
// kept across runs: said by the menu's 停用 and 启用; connect_reset empties it
let cd_switching : Map[String, Bool] = {}

///|
fn connect_reset() -> Unit {
  cd_switching.clear()
  cd_all_sessions.clear()
  slack_reset()
  slack_app_reset()
}

///|
/// The connect's call to the core with its station and id, said done by `done`.
fn cd_act(core : Core, station : String, id : String, what : String, name : String, more : Array[(String, Json)], done? : String = "") -> Unit {
  let p = [("station", str(station)), ("id", str(id))]
  p.append(more)
  @settings.act(core, what, name, obj(p), done~)
}

///|
/// Saved (useSaveConnect: `connect.put` with what changed), said by `done`.
fn cd_put(core : Core, station : String, id : String, input : Json, done? : String = "") -> Unit {
  cd_act(core, station, id, @sf.t("common.save"), "connect.put", [("input", input)], done~)
}

///|
/// What is done to it less often (Menu): reconnecting it, its token (a Feishu one's secret) replaced, Slack (or its
/// console) opened; it turned off or on, handed to another; deleted, asked first.
fn cd_menu(c : @ui.Ctx, core : Core, here : Here, station : String, cv : Json?) -> Unit {
  let t = @sf.theme()
  let id = text(cv, "id")
  let me = station + "/" + id
  let on = [("station", station), ("id", id)]
  let feishu = text(cv, "kind") == "feishu"
  let comma = text(cv, "kind") == "comma"
  let reconnecting = is_doing(core, ["connect.reconnect"], on)
  let saving = is_doing(core, ["connect.put"], on)
  let conn = field(cv, "connection")
  let up = text(conn, "state") == "connected" || text(conn, "state") == "reconnecting"
  let slack_url = if up { text(field(conn, "workspace"), "url") } else { "" }
  let console = text(field(cv, "feishu"), "console")
  if !@sf.icon_action(c, "more", "connect-more/" + me, @sf.t("common.more")) {
    return
  }
  let mid = c.id("connect-more/" + me)
  let delete = fn() {
    let sessions = text_number(cv, "sessions")
    confirm(
      @sf.t("web-pages.archive.deleteConfirm", args=[("title", text(cv, "name"))]),
      if sessions > 0 {
        @sf.t(cd_kind_key("web-pages.connect.deleteBodySessions", cv), args=[("n", sessions.to_string())])
      } else {
        @sf.t(cd_kind_key("web-pages.connect.deleteBody", cv))
      },
      @sf.t("web-pages.connect.delete"),
      danger=true,
      // back to the list at once: its row turns there until the station has dropped it
      fn() {
        (core.pop)()
        cd_act(core, station, id, @sf.t("web-pages.connect.delete"), "connect.delete", [], done=@sf.t("web-pages.connect.deleted"))
      },
    )
  }
  let items : Array[@sf.MenuItem?] = [
    Some(
      @sf.menu_item_of(@sf.t("web-pages.connect.reconnect"), icon="refresh", disabled=reconnecting, fn() {
        cd_act(core, station, id, @sf.t("web-pages.connect.reconnect"), "connect.reconnect", [], done=@sf.t("web-pages.connect.reconnected"))
      }),
    ),
  ]
  // (a Comma connect's line is made again in Comma: there is no token of its own to replace here)
  if !comma {
    items.push(Some(
      @sf.menu_item_of(@sf.t(if feishu { "web-pages.connect.feishu.replace" } else { "web-pages.connect.replaceToken" }), icon="key", fn() {
        if feishu {
          cd_secret_dialog(core, station, cv)
        } else {
          cd_token_dialog(core, station, cv)
        }
      }),
    ))
  }
  if !feishu && !comma && slack_url != "" {
    items.push(Some(@sf.menu_item_of(@sf.t("web-pages.connect.openSlack"), icon="external", fn() { (core.open_link)(slack_url) })))
  }
  if feishu && console != "" {
    items.push(Some(@sf.menu_item_of(@sf.t("web-pages.connect.feishu.openConsole"), icon="external", fn() { (core.open_link)(console) })))
  }
  items.push(None)
  items.push(
    Some(
      if flag(cv, "enabled") {
        @sf.menu_item_of(@sf.t("web-pages.profiles.disable"), icon="power", disabled=saving, fn() {
          cd_switching[me] = true
          cd_put(core, station, id, obj([("enabled", Json::boolean(false))]), done=@sf.t(cd_kind_key("web-pages.connect.disabled", cv)))
        })
      } else {
        @sf.menu_item_of(@sf.t("web-pages.connect.enable"), icon="power", disabled=saving, fn() {
          cd_switching[me] = true
          cd_put(core, station, id, obj([("enabled", Json::boolean(true))]), done=@sf.t("web-pages.connect.enabled"))
        })
      },
    ),
  )
  items.push(Some(@sf.menu_item_of(@sf.t("web-pages.connect.changeOwner"), icon="user", fn() { cd_owner_dialog(core, here, station, cv) })))
  items.push(None)
  items.push(Some(@sf.menu_item_of(@sf.t("web-pages.connect.delete"), icon="trash", danger=true, delete)))
  @sf.menu(items, from=Of(mid), along=End)
}

///|
/// A count the core gives as a number.
fn text_number(v : Json?, key : String) -> Int {
  match field(v, key) {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
}

///|
/// A key of words that differ for a Feishu connect: its `.feishu` twin for one (the web's kindKey).
fn cd_kind_key(key : String, cv : Json?) -> String {
  if text(cv, "kind") == "feishu" {
    key + ".feishu"
  } else {
    key
  }
}

///|
/// Why its link fails, or comes back after it did (ConnectTrouble); "" while up.
fn cd_trouble(cv : Json?) -> String {
  let conn = field(cv, "connection")
  match text(conn, "state") {
    "error" => text(conn, "error")
    "reconnecting" if text(conn, "lastError") != "" =>
      @sf.t("web-pages.connect.retrying", args=[("error", text(conn, "lastError"))])
    _ => ""
  }
}

///|
/// What is wrong said on amber (a corner of 14, the ui's 13 in the ink).
fn cd_callout(c : @ui.Ctx, words : String) -> Unit {
  c.box(style=cd_amber.then(@ui.style(bg=Data(@sf.theme().p.amber_bg))), fn() {
    c.text(words, style=cd_words) |> ignore
  })
  |> ignore
}

///|
/// The Slack link needing its tokens (SlackSection): how to make the app, the tokens' fields, 保存并连接 checking them
/// first (then they are saved and it connects).
fn cd_slack_section(c : @ui.Ctx, core : Core, station : String, cv : Json?) -> Unit {
  let id = text(cv, "id")
  let tk = slack_tokens(c, core, station, "connect-slack/" + station + "/" + id, connect=id)
  let saving = is_doing(core, ["connect.put"], [("station", station), ("id", id)])
  @sf.section(c, @sf.t("web-pages.connect.slack"), note=@sf.t("web-pages.connect.slackLead"), fn() {
    @sf.page_card(c, footed=true, fn() {
      create_app_steps(c, core, station, text(cv, "name"))
      token_fields(c, core, tk)
      @sf.card_foot(c, at_end=true, fn() {
        @sf.button(
          c,
          @sf.t("web-pages.connect.saveConnect"),
          key="connect-save-tokens/" + id,
          tone=Primary,
          busy=tokens_busy(core, tk) || saving,
          disabled=!tokens_ready(core, tk),
          on_press=fn() {
            tokens_check(core, tk, fn() {
              let input = obj([("slack", tokens_input(tk))])
              tokens_clear(core, tk)
              cd_put(core, station, id, input, done=@sf.t("web-pages.connect.tokenSavedConnecting"))
            })
          },
        ) |> ignore
      })
    })
  })
}

///|
/// Its Slack tokens replaced (TokenDialog: either one, the other kept), checked before they are saved; it closes as
/// they go, said done or not by a toast.
fn cd_token_dialog(core : Core, station : String, cv : Json?) -> Unit {
  let id = text(cv, "id")
  let key = "connect-tokens/" + (desk_dialogs.val + 1).to_string()
  let slack = field(cv, "slack")
  open_dialog(
    @sf.t("web-pages.connect.replaceTitle"),
    description=@sf.t("web-pages.connect.replaceLead"),
    fn(c, _) {
      let tk = slack_tokens(c, core, station, key, connect=id)
      token_fields(c, core, tk, masked=(text(slack, "appToken"), text(slack, "botToken")))
    },
    fn(c, shut) {
      let tk = slack_tokens(c, core, station, key, connect=id)
      @sf.button(c, @sf.t("common.cancel"), key=key + "/cancel", tone=Ghost, on_press=fn() {
        shut()
        tokens_drop(core, key)
      }) |> ignore
      let saving = is_doing(core, ["connect.put"], [("station", station), ("id", id)])
      @sf.button(
        c,
        @sf.t("web-pages.connect.saveReconnect"),
        key=key + "/save",
        tone=Primary,
        busy=tokens_busy(core, tk) || saving,
        disabled=!tokens_ready(core, tk),
        on_press=fn() {
          tokens_check(core, tk, fn() {
            cd_put(core, station, id, obj([("slack", tokens_input(tk))]), done=@sf.t("web-pages.connect.tokenSavedReconnecting"))
            shut()
            tokens_drop(core, key)
          })
        },
      ) |> ignore
    },
  )
}

///|
/// How its conversations become sessions, to choose from (ModeChoices; the core's ModeWords, as its kind says them):
/// one each (a Feishu connect's by its group or its thread) or all in one, the latter with whether it waits for an @.
/// What is chosen now: the mode, the @, thread mode.
fn mode_choices(c : @ui.Ctx, key : String, words : Json?, mode : String, mention : Bool, threads : Bool) -> (String, Bool, Bool) {
  let multi = field(words, "multi")
  let by_thread = field(words, "threads")
  let single = field(words, "single")
  let out = Ref((mode, mention, threads))
  let now = if threads { "threads" } else { mode }
  let ways = [("multi-session", text(multi, "label"), text(multi, "description"))]
  if text(by_thread, "label") != "" {
    ways.push(("threads", text(by_thread, "label"), text(by_thread, "description")))
  }
  ways.push(("single-session", text(single, "label"), text(single, "description")))
  let picked = @sf.choices(
    c,
    key,
    now,
    ways,
    label=@sf.t("web-pages.connect.mode"),
    extra=fn(v) {
      guard v == "single-session" else { None }
      Some(fn() {
        let waits = @sf.switch_row(
          c,
          key + "/mention",
          @sf.t("web-pages.connect.mentionOnly"),
          mention,
          note=text(words, if mention { "mentionOn" } else { "mentionOff" }),
        )
        if waits != mention {
          out.val = (mode, waits, false)
        }
      })
    },
  )
  if picked != now {
    // (one each always waits for an @)
    out.val = match picked {
      "threads" => ("multi-session", true, true)
      "multi-session" => ("multi-session", true, false)
      _ => (picked, mention, false)
    }
  }
  out.val
}

///|
/// How it runs, in one card (RunSection: runCard): the model it runs and who runs it (the core's pick of
/// `connect:<id>`; none on its runtime: to its profiles), how its conversations become sessions (更改), in single-session
/// the one they go into (切换; being switched, a ring beside it); under them what a change reaches.
fn cd_run_section(c : @ui.Ctx, src : Source, core : Core, here : Here, station : String, item : Json?) -> Unit {
  let cv = field(item, "connect")
  let id = text(cv, "id")
  let runtime = text(field(cv, "bind"), "runtime")
  let changes = flag(item, "runtimeChanges")
  // the models its station can run, each with the runtimes it runs on (the core's station view)
  let sv = match @settings.stations_of(core, here).value {
    Some(Array(a)) => a.iter().find_first(fn(s) { text(Some(s), "station") == station })
    _ => None
  }
  let models = items(
      match sv {
        Some(s) => Some(s)
        None => None
      },
      "models",
    ).filter(fn(m) { changes || strings(Some(m), "runtimes").contains(runtime) })
  let single = text(cv, "mode") == "single-session"
  let bind_on = [("station", station), ("connect", id)]
  let binding = is_doing(core, ["connect.bindSession"], bind_on)
  @sf.section(c, @sf.t("web-pages.connect.run"), fn() {
    @sf.group(c, fn() {
      // its model: picked here, or none its station runs for its runtime (to the station's profiles)
      if models.length() == 0 {
        @sf.link_row(
          c,
          "connect-no-models/" + id,
          @sf.t("web-pages.profiles.models"),
          note=@sf.t("web-pages.connect.noModelsFor", args=[("runtime", text(cv, "runtimeText"))]),
          on_press=fn() {
            (core.push)(Profiles(station))
          },
        ) |> ignore
      } else {
        @sf.said_row(c, @sf.t("web-pages.profiles.models"), "", value=fn() {
          model_triple(c, src, station, "connect:" + id, saved=@sf.t("web-pages.connect.bindSaved"))
        })
      }
      // how its conversations become sessions, switched in a dialog
      @sf.link_row(
        c,
        "connect-mode/" + id,
        @sf.t("web-pages.connect.session"),
        value=text(cv, "modeLabel"),
        note=text(cv, "modeSentence"),
        on_press=fn() {
          cd_mode_dialog(core, station, item)
        },
      ) |> ignore
      // the one they all go into: its chat, another chosen
      if single {
        let bound = field(item, "bound")
        @sf.link_row(
          c,
          "connect-bound/" + id,
          @sf.t("web-pages.connect.current"),
          value=if bound is Some(Object(_)) { text(bound, "titleText") } else { @sf.t("web-pages.connect.noSession") },
          goes=bound is Some(Object(_)),
          on_press=fn() {
            (core.open_chat)(station, text(bound, "key"), text(bound, "titleText"))
          },
        ) |> ignore
        @sf.link_row(
          c,
          "connect-switch/" + id,
          @sf.t("web-pages.connect.switch"),
          chevron=false,
          goes=!binding,
          tail=fn() { doing_mark(c, binding, failed_of(core, ["connect.bindSession"], bind_on), inline=true) },
          on_press=fn() {
            cd_choose_dialog(core, station, item)
          },
        ) |> ignore
      }
    })
    @sf.page_note(c, @sf.t(if changes { "web-pages.connect.runtimeChanges" } else { "web-pages.connect.runtimeNote" }, args=[("runtime", text(cv, "runtimeText"))]))
  })
}

///|
/// Words to press beside a row's (the ui's 13 muted); whether it
/// was pressed.
fn cd_text_button(c : @ui.Ctx, key : String, label : String, disabled? : Bool = false) -> Bool {
  let id = c.id(key)
  let b = c.box(style=cd_text_button_box, id=if disabled { 0 } else { id }, disabled~, fn() {
    c.rich([@ui.span(label, underline=true)], style=if c.hovered(id) { cd_text_button_lit } else { cd_text_button_words })
    |> ignore
  })
  c.semantics(b, Button, id~, label~, disabled~)
  !disabled && hit(c, id)
}

///|
/// A link in its words (underlined); whether it was pressed.
fn cd_link(c : @ui.Ctx, key : String, label : String) -> Bool {
  let id = c.id(key)
  let b = c.box(style=cd_link_box, id~, fn() { c.rich([@ui.span(label, underline=true)], style=cd_link_words) |> ignore })
  c.semantics(b, Link, id~, label~)
  hit(c, id)
}

///|
/// How its conversations become sessions, switched (ModeDialog): the ways to choose from, what switching does said
/// under them (the core's ModeChange), its button the core's words; it closes as it goes, said by a toast.
pub fn cd_mode_dialog(core : Core, station : String, item : Json?) -> Unit {
  let cv = field(item, "connect")
  let id = text(cv, "id")
  let key = "connect-mode/" + (desk_dialogs.val + 1).to_string()
  let next : Ref[(String, Bool, Bool)] = Ref((text(cv, "mode"), flag(cv, "requireMention"), flag(field(cv, "feishu"), "threads")))
  let change = fn() -> Json? {
    let (mode, mention, threads) = next.val
    items(item, "changes")
    .iter()
    .find_first(fn(ch) {
      text(Some(ch), "mode") == mode && flag(Some(ch), "threads") == threads && (mode == "multi-session" || flag(Some(ch), "requireMention") == mention)
    })
  }
  open_dialog(
    @sf.t("web-pages.connect.modeTitle"),
    description=@sf.t("web-pages.connect.modeLead"),
    wide=true,
    fn(c, _) {
      next.val = mode_choices(c, key + "/choices", field(cv, "modeWords"), next.val.0, next.val.1, next.val.2)
      let effects = strings(change(), "effects")
      if effects.length() > 0 {
        c.box(style=cd_amber.then(@ui.style(bg=Data(@sf.theme().p.amber_bg))), fn() {
          c.text(@sf.t("web-pages.connect.afterChange"), style=cd_amber_title) |> ignore
          c.box(style=cd_effects, fn() {
            for e in effects {
              c.box(style=cd_effect, fn() {
                c.text("•", style=cd_bullet) |> ignore
                c.box(style=cd_effect_words, fn() { c.text(e, style=cd_words) |> ignore }) |> ignore
              })
              |> ignore
            }
          })
          |> ignore
        })
        |> ignore
      }
    },
    fn(c, shut) {
      @sf.button(c, @sf.t("common.cancel"), key=key + "/cancel", tone=Ghost, on_press=fn() {
        shut()
      }) |> ignore
      let ch = change()
      @sf.button(c, text(ch, "action"), key=key + "/save", tone=Primary, disabled=!flag(ch, "changed"), on_press=fn() {
        let (mode, mention, threads) = next.val
        let input = [("mode", str(mode)), ("requireMention", Json::boolean(mention))]
        if text(cv, "kind") == "feishu" {
          input.push(("feishu", obj([("threads", Json::boolean(threads))])))
        }
        cd_put(
          core,
          station,
          id,
          obj(input),
          done=@sf.t("web-pages.connect.modeChanged"),
        )
        shut()
      }) |> ignore
    },
  )
}

///|
/// A single-session connect's session chosen (ChooseSessionDialog): a new one (its name typed, or not), or one of
/// those it could go into (the one now marked 当前); it closes as it goes, the session's line turning meanwhile.
fn cd_choose_dialog(core : Core, station : String, item : Json?) -> Unit {
  let cv = field(item, "connect")
  let id = text(cv, "id")
  let key = "connect-session/" + (desk_dialogs.val + 1).to_string()
  let choice : Ref[String] = Ref(
    match opt_text(cv, "session") {
      Some(s) => s
      None => "new"
    },
  )
  let title = field_of(key + "/title")
  open_dialog(
    @sf.t("web-pages.connect.chooseTitle"),
    description=@sf.t("web-pages.connect.chooseLead", args=[("name", text(cv, "name"))]),
    wide=true,
    fn(c, _) {
      let options = [("new", @sf.t("web-pages.connect.newSession"), @sf.t("web-pages.connect.newSessionLead"))]
      for s in items(item, "candidates") {
        let sv = Some(s)
        let named = if flag(sv, "current") {
          text(sv, "titleText") + " · " + @sf.t("web-pages.connect.current")
        } else {
          text(sv, "titleText")
        }
        options.push((text(sv, "key"), named, text(sv, "description")))
      }
      c.box(style=cd_session_choices, fn() {
        choice.val = @sf.choices(c, key + "/choices", choice.val, options, label=@sf.t("web-pages.connect.session"), extra=fn(v) {
          guard v == "new" else { None }
          Some(fn() {
            @sf.input(c, key + "/title-input", placeholder=@sf.t("web-pages.connect.newSessionPlaceholder"), field=title)
            |> ignore
          })
        })
      })
      |> ignore
    },
    fn(c, shut) {
      @sf.button(c, @sf.t("common.cancel"), key=key + "/cancel", tone=Ghost, on_press=fn() {
        shut()
      }) |> ignore
      let fresh = choice.val == "new"
      @sf.button(
        c,
        @sf.t(if fresh { "web-pages.connect.createUse" } else { "web-pages.connect.useThis" }),
        key=key + "/use",
        tone=Primary,
        disabled=opt_text(cv, "session") == Some(choice.val),
        on_press=fn() {
          @settings.act(
            core,
            @sf.t("web-pages.connect.switch"),
            "connect.bindSession",
            obj([
              ("station", str(station)),
              ("connect", str(id)),
              ("session", if fresh { Json::null() } else { str(choice.val) }),
              ("title", str(title.text())),
            ]),
            done=@sf.t(if fresh { "web-pages.connect.sessionCreated" } else { "web-pages.connect.sessionSwitched" }),
          )
          shut()
        },
      ) |> ignore
    },
  )
}

///|
/// How many of its latest sessions show before the rest are asked for (SESSIONS_SHOWN).
let cd_sessions_shown : Int = 5

///|
/// The connects whose sessions are all shown, by station/id.
// kept across runs: said by 显示全部 and 收起; connect_reset empties it
let cd_all_sessions : Map[String, Bool] = {}

///|
/// Its latest sessions (ConnectSessions): each its title, how it is in a pill, when it was last active, opening its
/// chat; five, the rest asked for; none, that none came yet.
fn cd_sessions(c : @ui.Ctx, core : Core, station : String, item : Json?) -> Unit {
  let cv = field(item, "connect")
  let me = station + "/" + text(cv, "id")
  let sessions = items(item, "sessions")
  let all = cd_all_sessions.get(me).unwrap_or(false)
  @sf.section(c, @sf.t("web-pages.connect.recent"), fn() {
    @sf.group(c, fn() {
      if sessions.length() == 0 {
        @sf.said_row(c, @sf.t(cd_kind_key("web-pages.connect.recentNone", cv), args=[("name", text(cv, "name"))]), "")
      }
      for i, s in sessions {
        if !all && i >= cd_sessions_shown {
          break
        }
        cd_session_row(c, core, station, Some(s))
      }
      if sessions.length() > cd_sessions_shown {
        @sf.link_row(
          c,
          "connect-sessions-all/" + me,
          if all {
            @sf.t("web-pages.profiles.collapse")
          } else {
            @sf.t("web-pages.connect.showAll", args=[("n", sessions.length().to_string())])
          },
          chevron=false,
          on_press=fn() {
            cd_all_sessions[me] = !all
          },
        ) |> ignore
      }
    })
  })
}

///|
/// A session of it (listRow): its title, how it is in a pill (StatusText: its check or wait, else its words), when it
/// was last active at its end; pressed, its chat.
fn cd_session_row(c : @ui.Ctx, core : Core, station : String, s : Json?) -> Unit {
  let key = text(s, "key")
  let tone : @sf.PillTone = match text(s, "tone") {
    "green" => Green
    "blue" => Blue
    "amber" => Amber
    "red" => Red
    "accent" => Accented
    _ => Neutral
  }
  @sf.link_row(
    c,
    "connect-session-row/" + key,
    text(s, "titleText"),
    value=text(field(field(s, "time"), "lastActiveAt"), "ago"),
    title_cut=true,
    value_cut=true,
    chevron=false,
    tail=fn() {
      match text(s, "statusLead") {
        "done" => @sf.pill(c, text(s, "statusRest"), tone~, icon="check")
        "wait" => @sf.pill(c, text(s, "statusRest"), tone~, icon="wait")
        _ => @sf.pill(c, text(s, "statusText"), tone~)
      }
    },
    on_press=fn() {
      (core.open_chat)(station, key, text(s, "titleText"))
    },
  ) |> ignore
}

///|
/// It handed to another person (OwnerDialog): a member of the workspace picked, or any email while its members are not
/// read; 保存 once it is another, closing as it goes.
fn cd_owner_dialog(core : Core, here : Here, station : String, cv : Json?) -> Unit {
  let id = text(cv, "id")
  let key = "connect-owner/" + (desk_dialogs.val + 1).to_string()
  let people = items(workspace_view(core, here).value, "members")
  let current = text(field(cv, "createdBy"), "id")
  let owner : Ref[String] = Ref(
    if current != "" {
      current
    } else {
      match people.get(0) {
        Some(p) => text(Some(p), "email")
        None => ""
      }
    },
  )
  let email = field_of(key + "/email")
  if people.length() == 0 {
    email.set(owner.val)
  }
  open_dialog(
    @sf.t("web-pages.connect.changeOwner"),
    description=@sf.t("web-pages.connect.ownerLead"),
    fn(c, _) {
      let people = items(workspace_view(core, here).value, "members")
      if people.length() > 0 {
        @sf.field(c, @sf.t("web-pages.connect.ownerLabel"), fn() {
          @sf.select(
            c,
            key + "/select",
            owner.val,
            people.map(fn(p) {
              let pv = Some(p)
              let mail = text(pv, "email")
              (mail, if text(pv, "name") != "" { @sf.t("web-pages.connect.person", args=[("name", text(pv, "name")), ("email", mail)]) } else { mail })
            }),
            fn(v) { owner.val = v },
            label=@sf.t("web-pages.connect.ownerLabel"),
            w=cd_select_w,
          )
        })
      } else {
        @sf.field(c, @sf.t("web-pages.connect.ownerEmail"), fn() {
          owner.val = @sf.input(c, key + "/email-input", placeholder="name@example.com", field=email).text
        })
      }
    },
    fn(c, shut) {
      @sf.button(c, @sf.t("common.cancel"), key=key + "/cancel", tone=Ghost, on_press=fn() {
        shut()
      }) |> ignore
      let to = owner.val.trim(chars=" \t\n").to_owned()
      @sf.button(c, @sf.t("common.save"), key=key + "/save", tone=Primary, disabled=to == "" || owner.val == current, on_press=fn() {
        let people = items(workspace_view(core, here).value, "members")
        let chosen = people.iter().find_first(fn(p) { text(Some(p), "email").to_lower() == to.to_lower() })
        let name = match chosen {
          Some(p) if text(Some(p), "name") != "" => text(Some(p), "name")
          _ => to
        }
        cd_put(core, station, id, obj([("owner", obj([("id", str(to)), ("name", str(name))]))]), done=@sf.t("web-pages.connect.ownerChanged"))
        shut()
      }) |> ignore
    },
  )
}

///|
/// A Feishu connect's app (FeishuSection: in a run card, its labels 84 wide): its App ID (its console opened beside
/// it), its App Secret masked (replaced beside it), which of Feishu or Lark it is on.
fn cd_feishu_section(c : @ui.Ctx, core : Core, station : String, cv : Json?) -> Unit {
  let app = field(cv, "feishu")
  let id = text(cv, "id")
  @sf.section(c, @sf.t("web-pages.connect.feishu.section"), fn() {
    @sf.group(c, fn() {
      match opt_text(app, "console") {
        Some(url) if url != "" =>
          @sf.link_row(c, "feishu-console/" + id, "App ID", note=text(app, "appId"), value=@sf.t("web-pages.connect.feishu.openConsole"), out=true, on_press=fn() {
            (core.open_link)(url)
          }) |> ignore
        _ => @sf.said_row(c, "App ID", text(app, "appId"))
      }
      @sf.link_row(
        c,
        "feishu-replace/" + id,
        "App Secret",
        note=if text(app, "appSecret") == "" { "••••••••" } else { text(app, "appSecret") },
        value=@sf.t("web-pages.connect.feishu.replace"),
        value_lit=true,
        chevron=false,
        on_press=fn() {
          cd_secret_dialog(core, station, cv)
        },
      ) |> ignore
      @sf.link_row(
        c,
        "",
        @sf.t("web-pages.connect.feishu.version"),
        value=if text(app, "domain") == "lark" { "Lark" } else { @sf.t("web-pages.connect.feishu.name") },
        goes=false,
      )
      |> ignore
    })
  })
}

///|
/// A Feishu connect's App Secret replaced (SecretDialog): checked by its station before it is kept, then it
/// reconnects; the dialog stays while it is, why it was refused under the field.
fn cd_secret_dialog(core : Core, station : String, cv : Json?) -> Unit {
  let id = text(cv, "id")
  let key = "connect-secret/" + (desk_dialogs.val + 1).to_string()
  let secret = field_of(key + "/secret")
  let error : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })
  open_dialog(
    @sf.t("web-pages.connect.feishu.replace"),
    description=@sf.t("web-pages.connect.feishu.replaceLead"),
    fn(c, _) {
      @sf.field(c, "App Secret", error=error.get(), fn() {
        @sf.input(c, key + "/secret-input", placeholder=text(field(cv, "feishu"), "appSecret"), secret=true, field=secret)
        |> ignore
      })
    },
    fn(c, shut) {
      @sf.button(c, @sf.t("common.cancel"), key=key + "/cancel", tone=Ghost, on_press=fn() {
        shut()
      }) |> ignore
      let typed = secret.text().trim(chars=" \t\n").to_owned()
      let saving = is_doing(core, ["feishu.putSecret"], [("station", station), ("id", id)])
      @sf.button(c, @sf.t("web-pages.connect.saveReconnect"), key=key + "/save", tone=Primary, busy=saving, disabled=typed == "", on_press=fn() {
        error.set("")
        (core.call)("feishu.putSecret", obj([("station", str(station)), ("id", str(id)), ("appSecret", str(typed))]), fn(r) {
          match r {
            Ok(_) => {
              (core.say)(@sf.t("web-pages.connect.feishu.secretSaved"))
              shut()
            }
            Err(e) => error.set(error_text(e))
          }
        })
      }) |> ignore
    },
  )
}

///|
/// A connect as its people see it (ui.tsx ConnectAvatar): its bot's picture, filling its head's tile with the tile's
/// corners (the app's icon it is: a square, as Slack shows it), once it is here; its kind's mark till then, and where
/// it is not said.
fn cd_avatar(c : @ui.Ctx, core : Core, cv : Json?, size : Double) -> Unit {
  let picture = match opt_text(cv, "botImage") {
    Some(image) => (core.picture)(image, c.page_stint())
    None => ""
  }
  match picture {
    key if key != "" && c.image_ready(key, size * c.scale) =>
      c.image(key, w=Px(size), h=Px(size), radius=c.theme().corner(Lg), bg=0L, fade=false) |> ignore
    // (its kind's mark three fifths of it, on a tile of its side: no larger than the room its head gives it, which
    // a tile 2.4 times the mark was, over the lines under it on a phone)
    _ => {
      let mark = (size * cd_avatar_mark).round()
      c.box(style=cd_avatar_box.then(@ui.style(w=Fixed(size), h=Fixed(size), bg=Data(@sf.theme().p.paper))), fn() {
        cn_kind(c, text(cv, "kind"), mark)
      })
      |> ignore
    }
  }
}

///|
let cd_avatar_mark : Double = 0.6

///|
let cd_icon : Double = 14.0

///|
let cd_kind_icon : Double = 13.0

///|
let cd_select_w : Double = 280.0

///|
// kept across runs: a value (no field of it changes)
let cd_avatar_box : @ui.Style = @ui.css("align=ACenter justify=JCenter radius=Xl")

///|
// kept across runs: a value (no field of it changes)
let cd_sub_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// The callout on amber (12 by 14 in, a corner of 14; its title in the amber's ink, its list 6 under it, 4 apart).
// kept across runs: a value (no field of it changes)
let cd_amber : @ui.Style = @ui.css("w=Full px=S3_5 py=S3 radius=Xl1_5")

///|
// kept across runs: a value (no field of it changes)
let cd_amber_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=WarnInk, w=Full)

///|
// kept across runs: a value (no field of it changes)
let cd_effects : @ui.Style = @ui.css("w=Full pt=S1_5 gap=S1")

///|
// kept across runs: a value (no field of it changes)
let cd_effect : @ui.Style = @ui.css("row w=Full gap=S2 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let cd_effect_words : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let cd_bullet : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, wrap=false)

///|
/// textButton: underlined (here the muted ink, the words' under the pointer); inlineLink: the accent's ink.
// kept across runs: a value (no field of it changes)
let cd_text_button_box : @ui.Style = @ui.css("disabled{opacity=O55}")

///|
// kept across runs: a value (no field of it changes)
let cd_text_button_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let cd_text_button_lit : @ui.TextStyle = cd_text_button_words.then(@ui.text_style(color=Fg))

///|
// kept across runs: a value (no field of it changes)
let cd_link_box : @ui.Style = @ui.css("")

///|
// kept across runs: a value (no field of it changes)
let cd_link_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=AccentText)

///|
/// The sessions to choose from (sessionChoices: 52vh at most, scrolling).
// kept across runs: a value (no field of it changes)
let cd_session_choices : @ui.Style = @ui.css("w=Full")

///|
/// What is wrong on its callout (the ui's 13, the words' ink).
// kept across runs: a value (no field of it changes)
let cd_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, w=Full)
