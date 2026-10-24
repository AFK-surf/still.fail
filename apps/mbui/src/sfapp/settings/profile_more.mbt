// A profile's page past its check, allowance and models (Profiles.kt ProfileScreen): its "…" (renaming, checking,
// deleting or stopping it), signing its subscription in (SignIn, LoginSteps), its sharing with the workspace's other
// stations (ShareSection) and the workspaces it serves (WorkspacesSection), how it runs (default Fast, commands put
// to the background), its key or its variables changed, what to do when it is in trouble (ProfileRecovery); the
// machine's own logins offered as profiles (MachineLoginOffers); and where something is added, a station picked.

///|
/// The states of a sign-in under way (Profiles.kt SIGNING_IN).
// kept across runs: a table of constants, never written
let signing_in : Array[String] = ["starting", "needs_code", "needs_approval", "verifying"]

///|
/// The kinds of account a key is kept for (Profiles.kt KEYED).
// kept across runs: a table of constants, never written
let keyed : Array[String] = ["anthropic-api", "api-provider", "opencode-go"]

///|
/// A machine login's runtime by name (RUNTIME_LABEL).
pub fn runtime_label(rt : String) -> String {
  match rt {
    "claude" => "Claude Code"
    "codex" => "Codex"
    "dsh" => "DeepSeek Harness"
    "grok" => "Grok Build"
    _ => rt
  }
}

///|
/// The online stations of the workspace, as `stations` has them.
fn online_stations(core : Core, here : Here, only? : String = "") -> Array[Json] {
  match stations_of(core, here).value {
    Some(Array(a)) =>
      a.filter(fn(s) { flag(Some(s), "online") && (only == "" || text(Some(s), "station") == only) })
    _ => []
  }
}

///|
/// Where something is added: one of the stations online picked in a sheet (openPickStation).
fn open_pick_station(title : String, stations : Array[Json], go : (String) -> Unit) -> Unit {
  open_sheet(0.5, fn(c, _core) {
    let t = @sf.theme()
    sheet_head(c, title)
    c.box(w=Fill(1.0), padx=20.0, pady=6.0, fn() {
      c.text(tr("android-settings.pickStation"), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
    })
    |> ignore
    for s in stations {
      if pick_row(c, "pick-station/" + text(Some(s), "station"), text(Some(s), "name")) {
        close_sheet()
        go(text(Some(s), "station"))
      }
    }
  })
}

///|
/// A profile's own actions (openProfileMenu): renamed (not one on the machine's login), checked again (its allowance
/// read again with it), its account
/// signed in to again or by hand on the machine while its card asks for neither (signed in and well), deleted (one on
/// the machine's login stopped instead: the login stays the machine's).
fn open_profile_menu(_core : Core, station : String, p : Json?) -> Unit {
  let id = text(p, "id")
  let name = text(p, "name")
  let machine = flag(p, "machine")
  let on = [("station", station), ("id", id)]
  open_sheet(0.5, fn(c, core) {
    let t = @sf.theme()
    sheet_head(c, name)
    if !machine && pick_row(c, "profile-rename", tr("android-settings.station.rename")) {
      ask(tr("android-settings.profile.nameTitle"), name, tr("android-settings.station.name"), tr("common.save"), fn(line) {
        act(
          core,
          tr("android-settings.profile.renameWhat"),
          "profile.put",
          obj([("station", str(station)), ("id", str(id)), ("input", obj([("name", str(line))]))]),
          done=tr("android-settings.renamed"),
        )
      })
    }
    // checked again with its allowance read again: whether it works and how much is left, as of now
    if pick_row(c, "profile-recheck", tr("android-settings.profile.recheck"), busy=is_doing(core, ["profile.check", "profile.quota"], on)) {
      close_sheet()
      act(
        core,
        tr("android-settings.profile.checkShort"),
        "profile.check",
        obj([("station", str(station)), ("id", str(id))]),
        done=tr("android-settings.profile.checked"),
      )
      if allowance_read(p) {
        act(core, tr("android-settings.quota.checkWhat"), "profile.quota", obj([("station", str(station)), ("id", str(id))]))
      }
    }
    if signs_in(p) && !sign_in_asked(p) {
      if pick_row(c, "profile-login", tr("android-settings.login.again"), busy=is_doing(core, ["profile.login"], on)) {
        close_sheet()
        start_sign_in(core, station, id)
      }
      // (OpenCode's has no command to run by hand)
      let command = text(p, "loginCommand")
      if command != "" && pick_row(c, "profile-login-manual", tr("android-settings.login.manualShort")) {
        open_manual_sign_in(command)
      }
    }
    let runtime = runtime_label(text(p, "runtime"))
    if pick_row(
        c,
        "profile-delete",
        tr(if machine { "android-settings.connect.disable" } else { "android-settings.profile.delete" }),
        color=t.p.red,
      ) {
      confirm(
        fill(if machine { "android-settings.profile.disableTitle" } else { "android-settings.connect.deleteTitle" }, [
          ("name", name),
        ]),
        if machine {
          fill("android-settings.profile.disableText", [("app", "still.fail"), ("runtime", runtime)])
        } else {
          fill("android-settings.profile.deleteText", [("app", "still.fail")])
        },
        tr(if machine { "android-settings.connect.disable" } else { "android-settings.profile.delete" }),
        danger=true,
        fn() {
          (core.pop)()
          act(
            core,
            tr(if machine { "android-settings.profile.disableWhat" } else { "android-settings.profile.deleteWhat" }),
            "profile.delete",
            obj([("station", str(station)), ("id", str(id))]),
            done=tr(if machine { "android-settings.profile.disabled" } else { "android-settings.profile.deleted" }),
          )
        },
      )
    }
  })
}

///|
/// Whether a profile has an allowance its provider says (a subscription's; not a key's, which has none to read).
fn allowance_read(p : Json?) -> Bool {
  let q = field(p, "quota")
  q is Some(Object(_)) && text(q, "state") != "unsupported"
}

///|
/// The core's diagnosis of a profile in trouble and its next step (ProfileRecovery), on its account's card under where
/// it stands (whose first line its title is: account_head): why, what to do, a command to run where that is it, the
/// button that does it (a key asked for, its variables, its allowance read again, checked again; signing in is the
/// card's own, profile_sign_in), one under the other as the card's column has them.
fn profile_trouble(c : @ui.Ctx, core : Core, s : Json?, p : Json?) -> Unit {
  let issue = field(p, "trouble")
  guard issue is Some(Object(_)) else { return }
  let station = text(s, "station")
  let id = text(p, "id")
  let on = [("station", station), ("id", id)]
  let action = text(issue, "action")
  let online = flag(s, "online")
  c.box(style=trouble_rows, fn() {
    if text(issue, "detail") != "" {
      c.text(text(issue, "detail"), style=trouble_words) |> ignore
    }
    if text(issue, "next") != "" {
      c.text(text(issue, "next"), style=@sf.meta.then(@sf.full_words)) |> ignore
    }
    if !online {
      c.text(fill("android-settings.profile.offline", [("name", text(s, "name"))]), style=@sf.meta.then(@sf.full_words)) |> ignore
    }
    if action == "command" {
      command_box(c, core, text(p, "loginCommand"))
    }
    let checking = is_doing(core, ["profile.check"], on)
    let refreshing = is_doing(core, ["profile.quota"], on)
    if action != "login" &&
      button(c, "recover-go", text(issue, "label"), false, enabled=online, busy=checking || refreshing) {
      match action {
        "key" => ask_key(core, station, p, tr("android-settings.profile.newKey"), tr("android-settings.profile.keyHintShort"))
        "env" => open_env_sheet(core, station, p)
        "quota" =>
          act(core, tr("android-settings.quota.checkWhat"), "profile.quota", obj([("station", str(station)), ("id", str(id))]), done=tr("android-settings.quota.updated"))
        _ =>
          act(core, tr("android-settings.profile.checkWhat"), "profile.check", obj([("station", str(station)), ("id", str(id))]), done=tr("android-settings.profile.checked"))
      }
    }
    if (action == "key" || action == "env") &&
      button(c, "recover-check", tr("android-settings.profile.recheck"), false, enabled=online, busy=checking) {
      act(core, tr("android-settings.profile.checkWhat"), "profile.check", obj([("station", str(station)), ("id", str(id))]), done=tr("android-settings.profile.checked"))
    }
  })
  |> ignore
}

///|
/// Whether a profile's trouble ends in a button of its own (all but signing in, which is its card's): its card's
/// corner then taken from it.
fn trouble_button(p : Json?) -> Bool {
  let issue = field(p, "trouble")
  issue is Some(Object(_)) && text(issue, "action") != "login"
}

///|
/// What a trouble says and its button, 10 apart.
// kept across runs: a value (no field of it changes)
let trouble_rows : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
/// Why it is in trouble (13, the text's ink).
// kept across runs: a value (no field of it changes)
let trouble_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L5, color=Fg, w=Full)

///|
/// A new key asked for, in a field that shows dots (secret), and saved (`profile.put` with the account's kind and the
/// key); the station checks it again.
fn ask_key(core : Core, station : String, p : Json?, title : String, hint : String) -> Unit {
  let id = text(p, "id")
  let kind = text(field(p, "access"), "kind")
  ask(title, "", tr("android-settings.profile.pasteKey"), tr("common.save"), secret=true, hint~, fn(key) {
    act(
      core,
      tr("android-settings.profile.keyWhat"),
      "profile.put",
      obj([("station", str(station)), ("id", str(id)), ("input", obj([("access", obj([("kind", str(kind)), ("key", str(key))]))]))]),
      done=tr("android-settings.profile.savedChecking"),
    )
  })
}

///|
/// The key a profile runs with (masked as the station shows it) and where its provider is, each changed from here,
/// under `head` (where it stands) on the one card of the account (Profiles.kt: ListCard, the head CARD_PAD in).
fn profile_key(c : @ui.Ctx, core : Core, station : String, p : Json?, head : () -> Unit) -> Array[() -> Unit] {
  let t = @sf.theme()
  let id = text(p, "id")
  let kind = text(field(p, "access"), "kind")
  let on = [("station", station), ("id", id)]
  [
    fn() {
      list_card(c, fn() {
        c.box(style=key_card_head, fn() { head() }) |> ignore
        if list_row(c, key="profile-key", fn() {
            c.box(w=Fill(1.0), fn() {
              c.text(
                if kind == "opencode-go" {
                  "OpenCode Go key"
                } else {
                  match opt_text(p, "providerName") {
                    Some(n) => n + " key"
                    None => "API key"
                  }
                },
                size=15.0,
                color=t.p.text,
                line=21.0,
              )
              |> ignore
              mono(
                c,
                match text(field(p, "access"), "key") {
                  "" => tr("android-settings.profile.notSaved")
                  k => k
                },
                size=13.0,
                color=t.p.muted,
                line=18.0,
              )
            })
            |> ignore
            // a key saved (the sheet that asked gone): a spinner until the station has it
            doing_mark(c, is_doing(core, ["profile.put"], on), failed_of(core, ["profile.put"], on))
            c.text(tr("android-settings.profile.change"), size=14.0, color=@sf.link_ink(), wrap=false) |> ignore
          }) {
          ask_key(
            core,
            station,
            p,
            tr(if kind == "opencode-go" { "android-settings.profile.newGoKey" } else { "android-settings.profile.newApiKey" }),
            tr("android-settings.profile.keyHint"),
          )
        }
        match opt_text(field(p, "access"), "endpoint") {
          Some(endpoint) =>
            if list_row(c, key="profile-endpoint", fn() {
                c.box(w=Fill(1.0), fn() {
                  c.text(tr("common.provider.endpoint"), size=15.0, color=t.p.text, line=21.0) |> ignore
                  mono(c, endpoint, size=13.0, color=t.p.muted, line=18.0)
                })
                |> ignore
                c.text(tr("android-settings.profile.change"), size=14.0, color=@sf.link_ink(), wrap=false) |> ignore
              }) {
              ask(tr("common.provider.endpoint"), endpoint, "https://", tr("common.save"), fn(value) {
                act(
                  core,
                  tr("android-settings.profile.keyWhat"),
                  "profile.put",
                  obj([("station", str(station)), ("id", str(id)), ("input", obj([("access", obj([("kind", str(kind)), ("endpoint", str(value))]))]))]),
                  done=tr("android-settings.profile.savedChecking"),
                )
              })
            }
          None => ()
        }
      })
    },
  ]
}

///|
/// A sign-in's card: what it holds 12 apart (SignIn: spacedBy(12)).
// kept across runs: a value (no field of it changes)
let sign_in_rows : @ui.Style = @ui.css("w=Full gap=S3")

///|
/// 取消登录 at the end of its head while signing in: 2 down, its mark 6 before it.
// kept across runs: a value (no field of it changes)
let sign_in_cancel : @ui.Style = @ui.css("row pt=S0_5 gap=S1_5 align=ACenter")

///|
/// 登录 and 在机器上手动登录 beside it, 16 apart.
// kept across runs: a value (no field of it changes)
let sign_in_buttons : @ui.Style = @ui.css("row gap=S4 align=ACenter")

///|
/// Why a sign-in failed (13, red).
// kept across runs: a value (no field of it changes)
let sign_in_failed_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L5, color=Danger, w=Full)

///|
/// Where a key's account stands, at the top of its card: its words CARD_PAD from the card's edge, 12 above and below.
// kept across runs: a value (no field of it changes)
let key_card_head : @ui.Style = @ui.css("w=Full px=S3 py=S3")

///|
/// A variable being edited (EnvRow): its row, the name and value typed, what a secret saved before shows masked, and
/// the name it had.
priv struct EnvRow {
  row : Int
  masked : String?
  original : String?
}

///|
/// The variables a custom profile runs with, edited in a sheet (EnvSheet): a name and a value a row (a secret one
/// saved before shown masked, kept when left blank), rows added and taken away; saved whole (`profile.put` with `env`:
/// what is gone null).
fn open_env_sheet(_core : Core, station : String, p : Json?) -> Unit {
  let id = text(p, "id")
  env_form.val += 1
  let form = env_form.val.to_string()
  let start = items(p, "env")
  let rows : Array[EnvRow] = []
  let next : Ref[Int] = Ref(1)
  // the rows whose fields have had their words put in (each as it is first laid out)
  let filled : Map[Int, Bool] = Map([])
  let key_of = fn(r : EnvRow, part : String) { "profile-env/" + form + "/" + r.row.to_string() + "/" + part }
  for i, e in start {
    rows.push({
      row: -i - 1,
      masked: if flag(Some(e), "secret") { Some(text(Some(e), "value")) } else { None },
      original: Some(text(Some(e), "key")),
    })
  }
  open_sheet(0.8, fn(c, core) {
    let t = @sf.theme()
    sheet_head(c, tr("android-settings.env.title"))
    let words : Map[Int, (String, String)] = Map([])
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      let blocks : Array[() -> Unit] = [
        fn() {
          c.box(w=Fill(1.0), padx=20.0, pb=10.0, fn() {
            c.text(tr("android-settings.env.note"), size=12.0, color=t.p.muted, w=Fill(1.0), line=17.0) |> ignore
          })
          |> ignore
        },
      ]
      for r in rows {
        blocks.push(fn() {
          c.box(w=Fill(1.0), padx=20.0, pb=10.0, gap=6.0, fn() {
            if !filled.contains(r.row) {
              filled[r.row] = true
              match r.original {
                Some(k) => {
                  field_of(key_of(r, "name")).set(k)
                  match start.iter().find_first(fn(e) { text(Some(e), "key") == k && !flag(Some(e), "secret") }) {
                    Some(e) => field_of(key_of(r, "value")).set(text(Some(e), "value"))
                    None => ()
                  }
                }
                None => ()
              }
            }
            let mut name = ""
            c.box(dir=Row, w=Fill(1.0), gap=10.0, align=ACenter, fn() {
              c.box(w=Fill(1.0), fn() { name = field_box(c, key_of(r, "name"), "NAME") }) |> ignore
              if tap_text(c, "env-delete/" + r.row.to_string(), tr("common.delete"), size=14.0) {
                match rows.search_by(fn(x) { x.row == r.row }) {
                  Some(i) => rows.remove(i) |> ignore
                  None => ()
                }
              }
            })
            |> ignore
            let placeholder = match r.masked {
              Some(m) => fill("android-settings.tokens.kept", [("token", m)])
              None => tr("android-settings.env.value")
            }
            let up = name.to_upper()
            let secret = r.masked is Some(_) ||
              ["KEY", "TOKEN", "SECRET", "PASSWORD", "AUTH"].iter().any(fn(w) { up.contains(w) })
            let value = field_box(c, key_of(r, "value"), placeholder, secret~)
            words[r.row] = (name, value)
          })
          |> ignore
        })
      }
      blocks.push(fn() {
        c.box(w=Fill(1.0), padx=20.0, pb=10.0, fn() {
          if tap_text(c, "env-add", tr("android-settings.env.add"), size=14.0) {
            rows.push({ row: next.val, masked: None, original: None })
            next.val += 1
          }
        })
        |> ignore
      })
      blocks.push(fn() {
        let busy = is_doing(core, ["profile.put"], [("station", station), ("id", id)])
        c.box(dir=Row, w=Fill(1.0), padx=20.0, pt=6.0, pb=24.0, gap=8.0, justify=JEnd, fn() {
          if button(c, "env-cancel", tr("common.cancel"), false) {
            c.blur()
            close_sheet()
          }
          if button(c, "env-save", tr("common.save"), true, enabled=!busy) {
            // what is gone null, a kept secret left blank not sent
            let out : Map[String, Json] = Map([])
            let kept : Array[String] = []
            for r in rows {
              match words.get(r.row) {
                Some((n, _)) => kept.push(n.trim(chars=" ").to_owned())
                None => ()
              }
            }
            for e in start {
              let k = text(Some(e), "key")
              if !kept.contains(k) {
                out[k] = Json::null()
              }
            }
            for r in rows {
              let (n, v) = words.get(r.row).unwrap_or(("", ""))
              let k = n.trim(chars=" ").to_owned()
              if k == "" {
                continue
              }
              match r.original {
                Some(o) if o != k => out[o] = Json::null()
                _ => ()
              }
              if r.masked is Some(_) && v == "" && r.original == Some(k) {
                continue
              }
              out[k] = str(v)
            }
            c.blur()
            close_sheet()
            act(
              core,
              tr("android-settings.env.saveWhat"),
              "profile.put",
              obj([("station", str(station)), ("id", str(id)), ("input", obj([("env", Json::object(out))]))]),
              done=tr("android-settings.saved"),
            )
          }
        })
        |> ignore
      })
      scroll_page(c, "profile-env/" + form, blocks)
    })
    |> ignore
  })
}

///|
/// A profile's variables on its page, a row each, with 编辑变量 (Profiles.kt's env section).
fn profile_env(c : @ui.Ctx, core : Core, station : String, p : Json?) -> Array[() -> Unit] {
  let t = @sf.theme()
  let on = [("station", station), ("id", text(p, "id"))]
  [
    fn() { section_header(c, tr("android-settings.env.title"), start=S6) },
    fn() {
      list_card(c, fn() {
        for e in items(p, "env") {
          list_row(c, fn() {
            c.box(w=Fill(1.0), fn() {
              mono(c, text(Some(e), "key"), size=15.0, line=21.0)
              mono(c, text(Some(e), "value"), size=13.0, color=t.p.muted, line=18.0)
            })
            |> ignore
          })
          |> ignore
        }
        if list_row(c, key="profile-env-edit", fn() {
            row_title(c, tr("android-settings.env.edit"), color=@sf.link_ink())
            doing_mark(c, is_doing(core, ["profile.put"], on), failed_of(core, ["profile.put"], on))
          }) {
          open_env_sheet(core, station, p)
        }
      })
    },
  ]
}

///|
/// How the profile runs (Profiles.kt), one card under 运行: which of its models may be used (a row to their page,
/// profile_models_page: how many of how many on), its subscription's default Fast, and commands put to the background
/// as a new message comes (Claude Code's), each a switch (`profile.put`). A decision model's models are said, not
/// picked (models_section, apart).
fn profile_run(c : @ui.Ctx, core : Core, station : String, p : Json?) -> Array[() -> Unit] {
  let id = text(p, "id")
  let on = [("station", station), ("id", id)]
  let picks = !flag(p, "decisionOnly")
  let fast = match field(p, "fast") {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
  let background = match field(p, "backgroundOnMessage") {
    Some(True) if strings(p, "runtimes").contains("claude") => Some(true)
    Some(False) if strings(p, "runtimes").contains("claude") => Some(false)
    _ => None
  }
  if !picks && fast is None && background is None {
    return []
  }
  let switch_row = fn(key : String, title : String, sub : String, value : Bool, field_name : String, what : String, done : String) {
    let busy = is_doing(core, ["profile.put"], on)
    if list_row(c, key=if busy { "" } else { key }, fn() {
        row_lines(c, title, sub, wrap_sub=true)
        doing_mark(c, busy, failed_of(core, ["profile.put"], on))
        switch(c, key, value)
      }) {
      act(
        core,
        what,
        "profile.put",
        obj([("station", str(station)), ("id", str(id)), ("input", obj([(field_name, Json::boolean(!value))]))]),
        done~,
      )
    }
  }
  [
    fn() { section_header(c, tr("android-settings.profile.run"), start=S6) },
    fn() {
      list_card(c, fn() {
        if picks {
          let ticked = strings(p, "models").length()
          let all = model_choices(p).length()
          if list_row(c, key="profile-models", fn() {
              row_title(c, tr("web-pages.profiles.models"))
              doing_mark(c, has(p, "modelsSaving"), None)
              c.text(if all > 0 { ticked.to_string() + " / " + all.to_string() } else { ticked.to_string() }, style=@sf.value)
              |> ignore
              chevron(c)
            }) {
            (core.push)(ProfileModels(station, id))
          }
        }
        match fast {
          Some(f) =>
            switch_row(
              "profile-fast",
              tr("android-settings.profile.fast"),
              tr("android-settings.profile.fastNote"),
              f,
              "fast",
              tr("android-settings.profile.saveFast"),
              tr(if f { "android-settings.profile.fastOff" } else { "android-settings.profile.fastOn" }),
            )
          None => ()
        }
        match background {
          Some(bg) =>
            switch_row(
              "profile-background",
              tr("android-settings.profile.background"),
              tr(if bg { "android-settings.profile.backgroundOn" } else { "android-settings.profile.backgroundOff" }),
              bg,
              "backgroundOnMessage",
              tr("android-settings.profile.run"),
              tr(if bg { "android-settings.profile.turnedOff" } else { "android-settings.profile.turnedOn" }),
            )
          None => ()
        }
      })
    },
  ]
}

///|
/// Which of the workspaces the station joined may run their chats on this profile too (WorkspacesSection), a switch
/// each, rows of its 分享 card (profile_sharing): for its home workspace's owners and admins, once the station is in
/// more than one.
fn profile_workspaces(c : @ui.Ctx, core : Core, station : String, p : Json?) -> Array[() -> Unit] {
  let view = (core.topic)("memberships", { "station": str(station) }).value
  if !flag(view, "manages") {
    return []
  }
  let joined = items(view, "workspaces").filter(fn(w) { !flag(Some(w), "home") })
  if joined.length() == 0 {
    return []
  }
  let id = text(p, "id")
  let now = strings(p, "workspaces")
  let on = [("station", station), ("id", id)]
  [
    fn() {
      let busy = is_doing(core, ["profile.put"], on)
      for w in joined {
        let ws = text(Some(w), "workspace")
        let name = text(Some(w), "name")
        let is_on = now.contains(ws)
        if list_row(c, key=if busy { "" } else { "profile-ws/" + ws }, fn() {
            row_lines(
              c,
              fill("web-pages.profiles.workspaces.for", [("name", name)]),
              fill(if is_on { "web-pages.profiles.workspaces.on" } else { "web-pages.profiles.workspaces.off" }, [
                ("name", name),
              ]),
              wrap_sub=true,
            )
            doing_mark(c, busy, failed_of(core, ["profile.put"], on))
            switch(c, "profile-ws/" + ws, is_on)
          }) {
          let next = if is_on { now.filter(fn(x) { x != ws }) } else { now + [ws] }
          act(
            core,
            tr("web-pages.profiles.workspaces.what"),
            "profile.put",
            obj([("station", str(station)), ("id", str(id)), ("input", obj([("workspaces", Json::array(next.map(str)))]))]),
            done=fill(
              if is_on { "web-pages.profiles.workspaces.turnedOff" } else { "web-pages.profiles.workspaces.turnedOn" },
              [("name", name)],
            ),
          )
        }
      }
    },
  ]
}

///|
/// Whom a profile is shared with, one card under 分享: the station's other workspaces whose chats may use it
/// (profile_workspaces), the workspace's other stations (profile_share; a copy of another station's, whose it is).
/// None of either to say, no section.
fn profile_sharing(c : @ui.Ctx, core : Core, here : Here, s : Json?, p : Json?) -> Array[() -> Unit] {
  let rows : Array[() -> Unit] = []
  if text(field(p, "share"), "role") != "user" {
    rows.append(profile_workspaces(c, core, text(s, "station"), p))
  }
  if flag(field(s, "overview"), "sharing") {
    rows.append(profile_share(c, core, here, s, p))
  }
  if rows.length() == 0 {
    return []
  }
  [
    fn() { section_header(c, tr("web-pages.profiles.share.title"), start=S6) },
    fn() {
      list_card(c, fn() {
        for r in rows {
          r()
        }
      })
    },
  ]
}

///|
/// Sharing a profile with the workspace's other stations (ShareSection), rows of its 分享 card (profile_sharing): a
/// switch; once on, where a subscription is signed in (moved from here) and which stations may use it. A copy of
/// another station's says whose, its page a tap away.
fn profile_share(c : @ui.Ctx, core : Core, here : Here, s : Json?, p : Json?) -> Array[() -> Unit] {
  let t = @sf.theme()
  let station = text(s, "station")
  let sid = text(s, "id")
  let id = text(p, "id")
  let share = field(p, "share")
  let list = items((core.topic)("profiles", { "scope": str(here.workspace) }).value, "items")
  // its row of the workspace's list (the account it is), and there the station that lends it
  let entry = list.iter().find_first(fn(e) {
    items(Some(e), "members").iter().any(fn(m) { text(Some(m), "station") == station && text(Some(m), "profileId") == id })
  })
  let stations = match entry {
    Some(e) => items(Some(e), "stations")
    None => []
  }
  let name_of = fn(sid : String) {
    match stations.iter().find_first(fn(x) { text(Some(x), "id") == sid }) {
      Some(x) => text(Some(x), "name")
      None => sid.unsafe_substring(start=0, end=if sid.length() > 8 { 8 } else { sid.length() })
    }
  }
  let subscription = text(field(p, "access"), "kind") == "subscription"
  if text(share, "role") == "user" {
    let host = name_of(text(share, "host"))
    let lender = match entry {
      Some(e) =>
        items(Some(e), "members").iter().find_first(fn(m) { text(Some(m), "stationId") == text(share, "host") && text(Some(m), "role") == "host" })
      None => None
    }
    return [
      fn() {
        if list_row(c, key=if lender is Some(_) { "share-lender" } else { "" }, fn() {
            c.box(w=Fill(1.0), fn() {
              c.text(fill("web-main.memory.share.from", [("station", host)]), size=15.0, color=t.p.text, w=Fill(1.0), line=21.0)
              |> ignore
              c.text(tr("web-pages.profiles.share.changeThere"), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0)
              |> ignore
              if subscription && field(share, "reachable") is Some(False) {
                c.text(fill("web-pages.profiles.share.hostAway", [("station", host)]), size=13.0, color=t.p.red, w=Fill(1.0), line=18.0)
                |> ignore
              }
            })
            |> ignore
            if lender is Some(_) {
              chevron(c)
            }
          }) {
          match lender {
            Some(m) => (core.push)(Profile(text(Some(m), "station"), text(Some(m), "profileId")))
            None => ()
          }
        }
      },
    ]
  }
  let shared = share is Some(Object(_))
  let allowed = match field(share, "allow") {
    Some(Array(_)) => Some(strings(share, "allow"))
    _ => None
  }
  let on = [("station", station), ("id", id)]
  let sharing = is_doing(core, ["profile.share"], on)
  let moving = is_doing(core, ["profile.move"], on)
  let names = match allowed {
    None => tr("web-pages.profiles.share.everyStation")
    Some(a) =>
      join(
        stations.filter(fn(x) { a.contains(text(Some(x), "id")) || text(Some(x), "id") == sid }).map(fn(x) { text(Some(x), "name") }),
        tr("web-main.list.separator"),
      )
  }
  let targets = stations.filter(fn(x) { text(Some(x), "id") != sid })
  [
    fn() {
      if list_row(c, key=if sharing { "" } else { "share-switch" }, fn() {
          row_lines(
            c,
            tr("web-pages.profiles.share.switch"),
            if !shared {
              fill("web-pages.profiles.share.onlyHere", [("station", text(s, "name"))])
            } else if subscription {
              tr("web-pages.profiles.share.lent")
            } else {
              tr("web-pages.profiles.share.copied")
            },
            wrap_sub=true,
          )
          doing_mark(c, sharing, failed_of(core, ["profile.share"], on))
          switch(c, "share-switch", shared)
        }) {
        act(
          core,
          tr("web-pages.profiles.share.switch"),
          "profile.share",
          obj([("station", str(station)), ("id", str(id)), ("on", Json::boolean(!shared))]),
          done=tr(if shared { "web-pages.profiles.share.unshared" } else { "web-pages.profiles.share.shared" }),
        )
      }
      if shared && subscription && !flag(p, "machine") {
        if list_row(c, key=if moving || targets.length() == 0 { "" } else { "share-move" }, fn() {
            row_title(c, tr("web-pages.profiles.share.signedIn"))
            doing_mark(c, moving, failed_of(core, ["profile.move"], on))
            c.text(text(s, "name"), size=13.0, color=t.p.muted, wrap=false) |> ignore
            chevron(c)
          }) {
          open_move(core, s, p, targets)
        }
      }
      if shared {
        if list_row(c, key="share-stations", fn() {
            let users = strings(share, "users")
            c.box(w=Fill(1.0), fn() {
              c.text(tr("web-pages.profiles.share.stations"), size=15.0, color=t.p.text, w=Fill(1.0), line=21.0) |> ignore
              if users.length() > 0 {
                c.text(
                  fill("web-pages.profiles.share.users", [("stations", join(users.map(name_of), tr("web-main.list.separator")))]),
                  size=13.0,
                  color=t.p.muted,
                  w=Fill(1.0),
                  line=18.0,
                )
                |> ignore
              }
            })
            |> ignore
            c.box(max_w=160.0, fn() {
              c.text(names, size=13.0, color=t.p.muted, wrap=false, line=18.0) |> ignore
            })
            |> ignore
            chevron(c)
          }) {
          open_pick_share(core, s, p, stations, allowed)
        }
      }
    },
  ]
}

///|
/// Where a shared subscription is signed in, moved to another station (openMove: `profile.move`).
fn open_move(_core : Core, s : Json?, p : Json?, targets : Array[Json]) -> Unit {
  let station = text(s, "station")
  let id = text(p, "id")
  open_sheet(0.5, fn(c, core) {
    let t = @sf.theme()
    sheet_head(c, tr("web-pages.profiles.share.moveTitle"))
    c.box(w=Fill(1.0), padx=20.0, pady=6.0, fn() {
      c.text(fill("web-pages.profiles.share.moveLead", [("station", text(s, "name"))]), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0)
      |> ignore
    })
    |> ignore
    for x in targets {
      let xv = Some(x)
      let online = flag(xv, "online")
      if pick_row(
          c,
          "move/" + text(xv, "id"),
          text(xv, "name"),
          sub=if online { "" } else { tr("android-settings.profiles.stationOffline") },
          enabled=online,
        ) {
        close_sheet()
        act(
          core,
          tr("web-pages.profiles.share.move"),
          "profile.move",
          obj([("station", str(station)), ("id", str(id)), ("to", str(text(xv, "id")))]),
          done=fill("web-pages.profiles.share.moved", [("station", text(xv, "name"))]),
        )
      }
    }
  })
}

///|
/// Which stations may use a shared profile, ticked in a sheet (openPickShare); all ticked is every station (those to
/// come too).
fn open_pick_share(_core : Core, s : Json?, p : Json?, stations : Array[Json], allowed : Array[String]?) -> Unit {
  let station = text(s, "station")
  let sid = text(s, "id")
  let id = text(p, "id")
  let ticked : Array[String] = match allowed {
    Some(a) => a.copy()
    None => stations.map(fn(x) { text(Some(x), "id") })
  }
  open_sheet(0.6, fn(c, core) {
    let t = @sf.theme()
    let all = stations.iter().all(fn(x) { text(Some(x), "id") == sid || ticked.contains(text(Some(x), "id")) })
    sheet_head(c, tr("web-pages.profiles.share.stations"))
    c.box(w=Fill(1.0), padx=20.0, pady=6.0, fn() {
      c.text(tr(if all { "web-pages.profiles.share.futureIn" } else { "web-pages.profiles.share.futureOut" }), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0)
      |> ignore
    })
    |> ignore
    for x in stations {
      let xid = text(Some(x), "id")
      if pick_row(c, "share-pick/" + xid, text(Some(x), "name"), checked=xid == sid || ticked.contains(xid), enabled=xid != sid) {
        match ticked.search(xid) {
          Some(i) => ticked.remove(i) |> ignore
          None => ticked.push(xid)
        }
      }
    }
    if pick_row(c, "share-pick-done", tr("web-pages.profiles.share.done"), color=@sf.link_ink()) {
      close_sheet()
      let params = [("station", str(station)), ("id", str(id)), ("on", Json::boolean(true))]
      if !all {
        let allow = ticked.copy()
        if !allow.contains(sid) {
          allow.push(sid)
        }
        params.push(("allow", Json::array(allow.map(str))))
      }
      act(core, tr("web-pages.profiles.share.stations"), "profile.share", obj(params))
    }
  })
}

///|
/// What a sign-in's sheet keeps while it is up: the code typed (by the sign-in's id), whether its link was copied, the
/// command to run by hand shown.
priv struct LoginState {
  copied : Map[String, Bool]
  manual : Map[String, Bool]
  error : Map[String, String]
  /// the sign-in's state last seen (a toast as it comes to done)
  seen : Map[String, String]
}

///|
let login_state : LoginState = { copied: {}, manual: {}, error: {}, seen: {} }

///|
/// Whether a profile is signed in to its account from here (a subscription's, or one on an account: OpenCode Go's,
/// Kimi Code's), not on the machine's own login.
fn signs_in(p : Json?) -> Bool {
  (text(field(p, "access"), "kind") == "subscription" || flag(field(p, "access"), "login")) && !flag(p, "machine")
}

///|
/// Whether its account is to be signed in to: its check says so, or a sign-in is under way.
fn sign_in_needed(p : Json?) -> Bool {
  text(field(p, "check"), "state") == "login" || signing_in.contains(text(field(p, "login"), "state"))
}

///|
/// Whether its sign-in's card asks for one (its buttons): needed, or the last one failed. Signed in and well, it is
/// asked for from its "…" instead.
fn sign_in_asked(p : Json?) -> Bool {
  sign_in_needed(p) || text(field(p, "login"), "state") == "failed"
}

///|
/// Its sign-in begun on the station (`profile.login`); one that could not begin, said so.
fn start_sign_in(core : Core, station : String, id : String) -> Unit {
  (core.call)("profile.login", obj([("station", str(station)), ("id", str(id))]), fn(r) {
    match r {
      Ok(_) => ()
      Err(e) => (core.say)(fill("android-settings.signIn.beginFailed", [("error", error_text(e))]))
    }
  })
}

///|
/// The command to sign its account in on the machine by hand, in a sheet of its own (from its "…").
fn open_manual_sign_in(command : String) -> Unit {
  open_sheet(0.36, fn(c, core) {
    sheet_head(c, tr("android-settings.login.manualShort"))
    c.box(style=manual_sign_in_room, fn() { command_box(c, core, command) }) |> ignore
  })
}

///|
/// Its command's room in its sheet: 20 in from the sheet's sides, 24 over its foot.
// kept across runs: a value (no field of it changes)
let manual_sign_in_room : @ui.Style = @ui.css("w=Full px=S5 pb=S6")

///|
/// A subscription's sign-in (SignIn): one card, `head` (where it stands: its pill says it once, no title over the
/// card saying it again) at its top, while signing in a way out of it at the head's end (取消登录) and the browser's
/// steps relayed here (LoginSteps). Asked for (`sign_in_asked`), what was off or how it is done in words, then 登录 /
/// 重新登录 (`profile.login`) with 在机器上手动登录 beside it and the command to sign in on the machine by hand under
/// them; signed in and well, the head alone (signing in again is in its "…", open_profile_menu), and while one asked
/// from there starts, the wait for its link. Its buttons at its foot, in its corners; the command last instead, its
/// corner taken from the command's box.
fn profile_sign_in(c : @ui.Ctx, core : Core, station : String, p : Json?, head : () -> Unit) -> Array[() -> Unit] {
  let t = @sf.theme()
  let id = text(p, "id")
  let on = [("station", station), ("id", id)]
  let job = field(p, "login")
  let state = text(job, "state")
  let active = job is Some(Object(_)) && signing_in.contains(state)
  let provider = text(p, "signInProvider")
  let k = station + "/" + id
  // signed in a moment ago (seen under way before): said so
  match login_state.seen.get(k) {
    Some(was) if was != "done" && state == "done" => (core.say)(tr("android-settings.login.done"))
    _ => ()
  }
  login_state.seen[k] = state
  let needed = sign_in_needed(p)
  let asked = sign_in_asked(p)
  let starting = is_doing(core, ["profile.login"], on)
  let command = text(p, "loginCommand")
  let manual = login_state.manual.get(k).unwrap_or(false)
  let command_last = !active && asked && command != "" && manual
  let waits = active && (state == "starting" || state == "verifying" || state == "done")
  [
    fn() {
      // (the command last: the card's corner taken from its box's, CARD_PAD in: concentricOut(COMMAND_BOX_CORNER, CARD_PAD);
      // signed in and well, no button at its foot: a card's own corner)
      card(c, foot=!command_last && !waits && asked, corner?=if command_last { Some(Around) } else { None }, fn() {
        c.box(style=sign_in_rows, fn() {
          c.box(dir=Row, w=Fill(1.0), fn() {
            c.box(w=Fill(1.0), fn() { head() }) |> ignore
            if active {
              let cancelling = is_doing(core, ["profile.cancelLogin"], on)
              c.box(style=sign_in_cancel, fn() {
                doing_mark(c, cancelling, failed_of(core, ["profile.cancelLogin"], on), inline=true)
                if tap_text(c, "login-cancel", tr("android-settings.login.cancel"), color=t.p.muted, size=14.0) && !cancelling {
                  act(core, tr("android-settings.login.cancelWhat"), "profile.cancelLogin", obj([("station", str(station)), ("id", str(id))]))
                }
              })
              |> ignore
            }
          })
          |> ignore
          if active {
            login_steps(c, core, k, job, provider, fn(code) {
              act(core, tr("android-settings.login.finish"), "profile.loginCode", obj([("station", str(station)), ("id", str(id)), ("code", str(code))]))
            })
          } else if asked {
            // what was off, or how it is done, in words
            if state == "failed" {
              c.text(fill("android-settings.login.failed", [("error", text(job, "error"))]), style=sign_in_failed_words) |> ignore
            } else if needed {
              c.text(fill("android-settings.login.note", [("app", "still.fail")]), style=@sf.meta.then(@sf.full_words)) |> ignore
            }
            c.box(style=sign_in_buttons, fn() {
              if button(
                  c,
                  "login-start",
                  tr(if needed && state != "done" { "android-settings.login.signIn" } else { "android-settings.login.again" }),
                  needed,
                  busy=starting,
                ) {
                start_sign_in(core, station, id)
              }
              // (OpenCode's has no command to run by hand)
              if command != "" && tap_text(c, "login-manual", tr("android-settings.login.manualShort"), size=14.0) {
                login_state.manual[k] = !manual
              }
            })
            |> ignore
            if manual && command != "" {
              command_box(c, core, command)
            }
          } else if starting {
            // signed in again from its "…": the card says it is under way until the station's sign-in says where it is
            wait_line(c, fill("android-settings.login.making", [("provider", provider)]))
          }
        })
        |> ignore
      })
      |> ignore
    },
  ]
}

///|
/// The accounts the station machine's own Claude Code and Codex are signed in with that no profile uses yet
/// (MachineLoginOffers): one kept where the station reads it used as it is (`profile.useMachineLogin`), one it cannot
/// signed in again for still.fail (`go_new`), a refused one only said so.
fn machine_login_offers(c : @ui.Ctx, core : Core, station : String, overview : Json?, go_new : (String) -> Unit, inset? : Double = 12.0) -> Array[() -> Unit] {
  let t = @sf.theme()
  let offers = items(overview, "machineLogins").filter(fn(l) { flag(Some(l), "offered") })
  if offers.length() == 0 {
    return []
  }
  [
    fn() {
      c.box(w=Fill(1.0), pl=inset + 12.0, pr=inset + 12.0, pt=8.0, pb=4.0, fn() {
        c.text(tr("android-settings.machine.title"), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
      })
      |> ignore
    },
    fn() {
      c.box(w=Fill(1.0), pl=inset, pr=inset, pb=10.0, fn() {
        rows_card(c, fn() {
          for l in offers {
            let lv = Some(l)
            let rt = text(lv, "runtime")
            let blocked = text(field(lv, "quota"), "state") == "blocked"
            let busy = is_doing(core, ["profile.useMachineLogin"], [("station", station), ("runtime", rt)])
            list_row(c, fn() {
              provider_mark(c, rt, "subscription", 18.0, "")
              c.box(w=Fill(1.0), gap=2.0, fn() {
                c.box(dir=Row, gap=6.0, align=ACenter, fn() {
                  c.text(runtime_label(rt), size=15.0, color=t.p.text, wrap=false, line=21.0) |> ignore
                  let plan = text(lv, "plan")
                  if plan != "" {
                    c.text(plan.unsafe_substring(start=0, end=1).to_upper() + plan.unsafe_substring(start=1, end=plan.length()), size=13.0, color=t.p.muted, wrap=false)
                    |> ignore
                  }
                })
                |> ignore
                c.box(dir=Row, gap=5.0, align=ACenter, fn() {
                  c.box(w=Px(6.0), h=Px(6.0), radius=3.0, bg=if blocked { t.p.red } else { t.p.green }, fn() {  }) |> ignore
                  c.text(
                    tr(if blocked { "android-settings.quota.blocked" } else { "android-settings.machine.signedIn" }),
                    size=12.0,
                    color=if blocked { t.p.red } else { t.p.muted },
                    wrap=false,
                  )
                  |> ignore
                  c.text(
                    "· " +
                    (match text(lv, "email") {
                      "" => tr("android-settings.machine.someone")
                      e => e
                    }),
                    size=12.0,
                    color=t.p.muted,
                    wrap=false,
                    w=Fill(1.0),
                  )
                  |> ignore
                })
                |> ignore
                let trouble = quota_trouble(field(lv, "quota"))
                if trouble != "" {
                  c.text(trouble, size=12.0, color=if blocked { t.p.red } else { t.p.muted }, w=Fill(1.0), line=17.0) |> ignore
                }
              })
              |> ignore
              quota_chips(c, field(lv, "quota"))
              // a refused account is said so, with nothing to do with it here
              if !blocked {
                if busy {
                  spinner(c)
                } else if tap_text(
                    c,
                    "machine-use/" + rt,
                    tr(if flag(lv, "usable") { "android-settings.machine.use" } else { "android-settings.login.signIn" }),
                    size=14.0,
                  ) {
                  if flag(lv, "usable") {
                    (core.call)("profile.useMachineLogin", obj([("station", str(station)), ("runtime", str(rt))]), fn(r) {
                      match r {
                        Ok(v) => {
                          (core.say)(tr("android-settings.machine.added"))
                          (core.push)(PickModels(station, text(Some(v), "id")))
                        }
                        Err(e) => (core.say)(error_text(e))
                      }
                    })
                  } else {
                    go_new(rt)
                  }
                }
              }
            })
            |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    },
  ]
}

///|
/// The provider a runtime's subscription is with (Profiles.kt SignIn's provider; Cursor's and Devin's their own).
fn provider_named(runtime : String) -> String {
  match runtime {
    "claude" => "Claude"
    "grok" => "Grok"
    "cursor" => "Cursor"
    "devin" => "Devin"
    _ => "ChatGPT"
  }
}
