// A profile's page on the desktop (ember web/src/pages/Accounts.tsx AccountView and its sections; Accounts.css.ts): who
// the account is and whether it works now (its provider's mark, its name renamed here, the runtimes it serves, what it
// is, its last check, checking again; its ⋯ to delete it, or stop the machine's own), signing it in where that comes
// first, what is left of its allowance, what it spent, the stations it is on, sharing it, the workspaces it serves,
// fast mode, its models, how it runs, who uses it, the account itself (its key, signing in again) and its variables.
// Everything said is the core's (its overview's profile, the workspace's profiles, the usage view).

///|
/// What a profile's page keeps of its own while it is open: its models' list open, what is typed to name one more,
/// a sign-in's code, the command shown, the account's key being replaced (what is typed), the variables' rows.
priv struct ProfileEdit {
  mut choosing : String
  mut command : String
  mut replacing : String
  mut env_open : String
  env_rows : Array[EnvRow]
  mut env_of : String
  mut env_made : Int
}

///|
/// A variable's row being written: its name, its value, what it was (its name saved, "" a new one), its value masked
/// as saved ("" not a secret).
priv struct EnvRow {
  row : Int
  key : @ui.Field
  value : @ui.Field
  original : String
  masked : String
}

///|
// kept across runs: said by the page's presses; profile_page_reset puts it back
let profile_edit : ProfileEdit = { choosing: "", command: "", replacing: "", env_open: "", env_rows: [], env_of: "", env_made: 0 }

///|
/// The fields of a profile's page, by their key (made as first drawn).
// kept across runs: made as a page first shows one; profile_page_reset empties it
let profile_fields : Map[String, @ui.Field] = {}

///|
fn profile_page_reset() -> Unit {
  profile_edit.choosing = ""
  profile_edit.command = ""
  profile_edit.replacing = ""
  profile_edit.env_open = ""
  profile_edit.env_rows.clear()
  profile_edit.env_of = ""
  profile_edit.env_made = 0
  profile_fields.clear()
}

///|
/// A field of the page, by its key, made once.
pub fn profile_field(key : String) -> @ui.Field {
  match profile_fields.get(key) {
    Some(f) => f
    None => {
      let f = @ui.Field::new()
      profile_fields[key] = f
      f
    }
  }
}

///|
/// A profile's page (AccountPage), by its station and id, one in every frame (the Small stack's, the wide frame's
/// pane, the profiles' place): a wait until the station's overview is read; one gone, that it is not found.
pub fn profile_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame, address : String, id : String) -> Unit {
  let s = @settings.station_of(core, here, address)
  let o = field(s, "overview")
  let key = "profile/" + address + "/" + id
  guard o is Some(Object(_)) else {
    @sf.page_waiting(c, "Profile", text=@sf.t("web-pages.profiles.loading"), fn() {
      let p = profile_sample()
      profile_view(c, core.quiet(), here, frame, Some({ "station": "sample", "name": Json::string(@sf.sample_words(4)) }), Some({ "profiles": [p] }), Some(p))
    })
  }
  match items(o, "profiles").search_by(fn(p) { text(Some(p), "id") == id }) {
    Some(i) => profile_view(c, core, here, frame, s, o, Some(items(o, "profiles")[i]))
    None =>
      @sf.page(c, on_back=core.pop, frame~, key, "Profile", [
        fn() { @sf.page_note(c, @sf.t("web-pages.profiles.notFound", args=[("id", id)])) },
      ])
  }
}

///|
/// The page (AccountView), the same parts in the same order on every screen, by what a person comes to it for: who
/// the account is and whether it works now (its head, checked again there); what to do first where it does not
/// (signing it in, its trouble's next step); how much is left of it and what it spent; who uses it and the stations it
/// is on; which models it may use and how it runs; whom it is shared with; then the account itself (its key, its
/// sign-in) and its variables, what is changed least. How each part is drawn is the library's (sf/page.mbt), by the
/// page's width.
fn profile_view(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame, s : Json?, o : Json?, p : Json?) -> Unit {
  let address = text(s, "station")
  let id = text(p, "id")
  let access = field(p, "access")
  let kind = text(access, "kind")
  let check = field(p, "check")
  let login = field(p, "login")
  let copy = text(field(p, "share"), "role") == "user"
  let machine = flag(p, "machine")
  let signs_in = kind == "subscription" || flag(access, "login")
  let signing_in = ["starting", "needs_code", "needs_approval", "verifying"].contains(text(login, "state"))
  // its row of the workspace's list: the account it is, on whichever stations have it
  let list = items((core.topic)("profiles", { "scope": str(here.workspace) }).value, "items")
  let entry = match
    list.search_by(fn(e) {
      items(Some(e), "members").iter().any(fn(m) { text(Some(m), "station") == address && text(Some(m), "profileId") == id })
    }) {
    Some(i) => Some(list[i])
    None => None
  }
  let blocks : Array[() -> Unit] = []
  // what to do first: a subscription to sign in (or signing in, or its last sign-in failed), else what its trouble
  // says to do
  let needed = text(check, "state") == "login" || signing_in
  let asked = needed || text(login, "state") == "failed"
  if !copy && signs_in && !machine && asked {
    blocks.push(fn() { profile_sign_in(c, core, address, text(s, "name"), p, needed) })
  } else if field(p, "trouble") is Some(Object(_)) && text(field(p, "trouble"), "action") != "login" {
    blocks.push(fn() { profile_trouble(c, core, s, p) })
  }
  blocks.push(fn() { profile_quota(c, core, address, p) })
  blocks.push(fn() { profile_usage(c, core, here, s, p, entry) })
  blocks.push(fn() { profile_used_by(c, core, address, o, p) })
  if entry is Some(_) && !items(entry, "places").is_empty() {
    blocks.push(fn() { profile_stations(c, core, address, entry) })
  }
  if !copy {
    // its models other profiles of the workspace could have too (the core's, on its member of the list)
    let spread = match entry {
      Some(_) =>
        match
          items(entry, "members").search_by(fn(m) {
            text(Some(m), "station") == address && text(Some(m), "profileId") == id
          }) {
          Some(i) => items(Some(items(entry, "members")[i]), "spread")
          None => []
        }
      None => []
    }
    blocks.push(fn() { profile_models(c, core, address, p, spread) })
    // how it runs, in one section (the web's two of the same title: fast mode, and the background on a message)
    let fast = has(p, "fast") && !(field(p, "fast") is Some(Null))
    let background = items(p, "runtimes").iter().any(fn(r) { r == "claude" }) && has(p, "backgroundOnMessage")
    if fast || background {
      blocks.push(fn() { profile_run(c, core, address, p, fast, background) })
    }
  }
  if has(o, "sharing") && !(field(o, "sharing") is Some(Null)) {
    blocks.push(fn() { profile_share(c, core, s, p, entry) })
  }
  if !copy {
    blocks.push(fn() { profile_workspaces(c, core, address, p) })
    blocks.push(fn() { profile_account(c, core, s, p, !asked) })
    if kind == "env" {
      blocks.push(fn() { profile_env(c, core, address, p) })
    }
  }
  // its head says who it is: no title over it
  @sf.page(c, on_back=core.pop, frame~, "profile/" + address + "/" + id, text(p, "name"), blocks, small=@sf.t("android-misc.bar.place.profiles"), head=fn() {
    profile_head(c, core, here, address, text(s, "name"), p, entry)
  })
}

///|
/// Its head (AccountView's identity): its provider's mark, its name (renamed here, but for the machine's own and a
/// copy) and the runtimes it serves, what it is (`name`: its station's), its last check and when, checking again (its
/// allowance read again with it); its ⋯.
fn profile_head(c : @ui.Ctx, core : Core, here : Here, address : String, name : String, p : Json?, entry : Json?) -> Unit {
  let id = text(p, "id")
  let on = [("station", address), ("id", id)]
  let copy = text(field(p, "share"), "role") == "user"
  let machine = flag(p, "machine")
  // what it is, in a line: its kind, the address signed in (when not its name), where it is
  let email = text(p, "email")
  // of an account on several stations, this station's (each's own part is under 各 station), not all of them
  let several = items(entry, "members").filter(fn(m) { text(Some(m), "role") != "user" }).length() > 1
  let place = if several {
    @sf.t("web-pages.profiles.onStation", args=[("station", name)])
  } else {
    text(entry, "where")
  }
  let facts = join([text(p, "kindText"), if email != text(p, "name") { email } else { "" }, place], " · ")
  @sf.own_head(
    c,
    fn(_) { @sf.provider_logo(c, text(p, "runtime"), text(field(p, "access"), "kind"), pf_mark_glyph, text(p, "providerMark")) },
    text(p, "name"),
    // its new name shows while it is saved
    busy=is_doing(core, ["profile.put"], on),
    tags=fn() { runtime_tags(c, items(p, "runtimes"), items(p, "uses").iter().any(fn(u) { u == "decision" })) },
    rename?=if !machine && !copy { Some(fn() { profile_rename(core, address, p) }) } else { None },
    rename_label=@sf.t("web-pages.settings.stations.rename"),
    lines=[facts],
    state=fn() {
      if text(p, "checkTone") != "green" {
        @sf.pill(c, text(p, "checkText"), tone=pill_tone(text(p, "checkTone")))
      }
      // what the check said and when, words of one line (short of room, cut from its end: when it was checked first;
      // nothing of it moving under the rest as what the check said changes); checking again kept
      let ago = text(field(field(field(p, "check"), "time"), "checkedAt"), "ago")
      let when = if ago != "" { @sf.t("web-pages.profiles.checkedAt", args=[("time", ago)]) } else { "" }
      c.box(style=pf_state, fn() {
        c.text(join([text(p, "checkLine"), when], " · "), style=pf_check_words) |> ignore
        let checking = is_doing(core, ["profile.check"], on)
        if @sf.icon_action(c, "refresh", "profile-check/" + address + "/" + id, @sf.t("web-pages.profiles.recheck"), disabled=checking) {
          @settings.act(core, @sf.t("web-pages.profiles.recheck"), "profile.check", obj([("station", str(address)), ("id", str(id))]))
          // (its allowance read again with it: how much is left, as of now)
          let q = field(p, "quota")
          if q is Some(Object(_)) && text(q, "state") != "unsupported" {
            @settings.act(core, @sf.t("web-pages.profiles.refresh"), "profile.quota", obj([("station", str(address)), ("id", str(id))]))
          }
        }
        if checking {
          @sf.spinner(c, size=pf_spin) |> ignore
        }
      }) |> ignore
    },
    actions?=if copy {
      None
    } else {
      Some(fn() { profile_menu(c, core, here, address, p) })
    },
  )
}

///|
/// The tone of a pill by the core's (red, amber, blue, green).
fn pill_tone(tone : String) -> @sf.PillTone {
  match tone {
    "red" => Red
    "amber" => Amber
    "blue" => Blue
    "green" => Green
    _ => Neutral
  }
}

///|
/// The runtimes it serves, a tag each (ui.tsx RuntimeTags: its mark and its short name), and 自动决策's.
fn runtime_tags(c : @ui.Ctx, runtimes : Array[Json], decision : Bool) -> Unit {
  c.box(style=pf_tags, fn() {
    for r in runtimes {
      match r {
        String(rt) =>
          // (its words alone: its maker's mark is the head's)
          c.box(style=pf_tag, fn() { c.text(runtime_tag(rt), style=pf_tag_words) |> ignore })
          |> ignore
        _ => ()
      }
    }
    if decision {
      c.box(style=pf_tag, fn() { c.text(@sf.t("common.decision"), style=pf_tag_words) |> ignore }) |> ignore
    }
  })
  |> ignore
}

///|
/// A runtime's short name on its tag (ui.tsx RUNTIME_TAG).
fn runtime_tag(r : String) -> String {
  match r {
    "claude" => "CC"
    "codex" => "Codex"
    "dsh" => "DSH"
    "grok" => "GROK"
    "cursor" => "Cursor"
    "devin" => "Devin"
    "hermes" => "Hermes"
    _ => r
  }
}

///|
/// Its new name asked for and saved (`profile.put` its name).
fn profile_rename(core : Core, address : String, p : Json?) -> Unit {
  let id = text(p, "id")
  ask(@sf.t("web-pages.profiles.name"), text(p, "name"), @sf.t("web-pages.profiles.name"), @sf.t("common.save"), fn(line) {
    let to = line.trim(chars=" \t\n").to_owned()
    if to != "" && to != text(p, "name") {
      @settings.act(
        core,
        @sf.t("web-pages.settings.stations.rename"),
        "profile.put",
        obj([("station", str(address)), ("id", str(id)), ("input", obj([("name", str(to))]))]),
        done=@sf.t("web-pages.settings.workspace.renamed"),
      )
    }
  })
}

///|
/// Its ⋯: renaming it (but the machine's own), deleting it (the machine's own login: stopping it, the login stays the
/// machine's), asked first.
fn profile_menu(c : @ui.Ctx, core : Core, here : Here, address : String, p : Json?) -> Unit {
  let id = text(p, "id")
  let machine = flag(p, "machine")
  let key = "profile-more/" + address + "/" + id
  if !@sf.icon_action(c, "more", key, @sf.t("common.more")) {
    return
  }
  let item = if machine { @sf.t("web-pages.profiles.disable") } else { @sf.t("web-pages.profiles.delete") }
  let remove = fn() {
    let (title, words) = if machine {
      (
        @sf.t("web-pages.profiles.disableConfirm", args=[("name", text(p, "name"))]),
        @sf.t("web-pages.profiles.disableBody", args=[("name", "still.fail"), ("runtime", @settings.runtime_label(text(p, "runtime")))]),
      )
    } else {
      (@sf.t("web-pages.archive.deleteConfirm", args=[("title", text(p, "name"))]), @sf.t("web-pages.profiles.deleteBody", args=[("name", "still.fail")]))
    }
    confirm(title, words, item, danger=true, fn() {
      // gone from here at once: the list shows it until the station has dropped it
      place_pick.remove(place_key(here.workspace, "profiles"))
      (core.pop)()
      @settings.act(
        core,
        item,
        "profile.delete",
        obj([("station", str(address)), ("id", str(id))]),
        done=if machine { @sf.t("web-pages.profiles.disabled") } else { @sf.t("web-pages.profiles.deleted") },
      )
    })
  }
  let items : Array[@sf.MenuItem?] = []
  if !machine {
    items.push(Some(@sf.menu_item_of(@sf.t("web-pages.settings.stations.rename"), icon="edit", fn() { profile_rename(core, address, p) })))
  }
  items.push(Some(@sf.menu_item_of(item, icon="trash", danger=true, remove)))
  @sf.menu(items, from=Of(c.id(key)), along=End)
  ignore(here)
}

// ── what to do first ────────────────────────────────────────────────────

///|
/// Signing a subscription in without a terminal (SignIn), on a card: still.fail runs the runtime's login on its machine
/// and this relays the browser's steps. Not under way: why (needed, or again), the way to start it, the command to run
/// by hand. Under way: what the person does in the browser (LoginSteps), there or in the station's own
/// (`station_name`'s), 取消.
fn profile_sign_in(c : @ui.Ctx, core : Core, address : String, station_name : String, p : Json?, needed : Bool) -> Unit {
  let id = text(p, "id")
  let on = [("station", address), ("id", id)]
  let job = field(p, "login")
  let state = text(job, "state")
  let provider = text(p, "signInProvider")
  let active = ["starting", "needs_code", "needs_approval", "verifying"].contains(state)
  let key = address + "/" + id
  @sf.page_card(c, footed=true, fn() {
    if !active {
      @sf.card_lines(
        c,
        if needed {
          @sf.t("web-pages.profiles.notSignedIn", args=[("provider", provider)])
        } else {
          @sf.t("web-pages.profiles.subscriptionSignIn", args=[("provider", provider)])
        },
        note=match state {
          "failed" => ""
          "done" => @sf.t("web-pages.profiles.signedInSwitch")
          _ => @sf.t("web-pages.profiles.signInNote", args=[("name", "still.fail")])
        },
        bad=if state == "failed" { @sf.t("web-pages.profiles.lastFailed", args=[("error", text(job, "error"))]) } else { "" },
      )
      let command = text(p, "loginCommand")
      if profile_edit.command == key && command != "" {
        @sf.copy_command(c, "profile-command/" + key, command, copy=@sf.t("common.copy"), copied=@sf.t("common.copied"))
      }
      @sf.card_foot(c, fn() {
        let starting = is_doing(core, ["profile.login"], on)
        if @sf.button(
            c,
            if state == "done" || !needed {
              @sf.t("web-pages.signIn.again")
            } else {
              @sf.t("web-pages.profiles.signIn")
            },
            key="profile-login/" + key,
            tone=Primary,
            icon="log-in",
            busy=starting,
          ) {
          @settings.act(core, @sf.t("web-pages.profiles.signIn"), "profile.login", obj([("station", str(address)), ("id", str(id))]))
        }
        if command != "" {
          let shown = profile_edit.command == key
          if @sf.button(
              c,
              // (the short words, the phone's: beside 登录 on a card's foot they fit a phone, the long ones ran past
              // its edge)
              if shown { @sf.t("web-pages.profiles.collapse") } else { @sf.t("android-settings.login.manualShort") },
              key="profile-manual/" + key,
              tone=Ghost,
            ) {
            profile_edit.command = if shown { "" } else { key }
          }
        }
      })
      return
    }
    @sf.card_lines(c, @sf.t("web-pages.profiles.signingIn", args=[("provider", provider)]), note=@sf.t("web-pages.profiles.signingInNote"))
    login_steps(
      c,
      core,
      address + "/" + id,
      job,
      provider,
      is_doing(core, ["profile.loginCode"], on),
      fn(code, sent) {
        @settings.act(
          core,
          @sf.t("web-pages.profiles.finish"),
          "profile.loginCode",
          obj([("station", str(address)), ("id", str(id)), ("code", str(code))]),
          then=fn(_) { sent() },
        )
      },
      in_station=(station_name, is_doing(core, ["profile.loginBrowser"], on), fn(what) {
        @settings.act(core, what, "profile.loginBrowser", obj([("station", str(address)), ("id", str(id))]), then=fn(v) {
          (core.open_screen)(address, text(Some(v), "screen"))
        })
      }),
    )
    @sf.card_foot(c, fn() {
      let cancelling = is_doing(core, ["profile.cancelLogin"], on)
      if @sf.button(c, @sf.t("common.cancel"), key="profile-login-cancel/" + key, tone=Ghost, busy=cancelling) {
        @settings.act(core, @sf.t("common.cancel"), "profile.cancelLogin", obj([("station", str(address)), ("id", str(id))]))
      }
    })
  })
}

///|
/// What the person does in the browser for a sign-in under way (LoginSteps): the link and the code to paste back
/// (Claude, Devin), the code to enter on the page that opens (DeviceCode: Codex, Grok, OpenCode, Kimi, Cursor's page
/// alone); while it is checked or added, said so.
/// `key`: whose steps they are; `send`: a code pasted back sent, then `sent` (its field emptied); `sending` while it is.
/// Where its job says the station has a browser of its own (`browser`), the same page there (`in_station`: the
/// station's name, whether it is being opened, and what opens it given what it is called), seldom used: in a ⋯ after
/// the page's button (docs/ui-panels.md: what is used least goes into the row's ⋯). Its tab's view opens here, gone
/// back from as the sign-in ends; Claude's comes back to its command there, with no code to paste.
pub fn login_steps(
  c : @ui.Ctx,
  core : Core,
  key : String,
  job : Json?,
  provider : String,
  sending : Bool,
  send : (String, () -> Unit) -> Unit,
  in_station? : (String, Bool, (String) -> Unit),
) -> Unit {
  let state = text(job, "state")
  let url = text(job, "url")
  // the same page in the station's browser (回到 … while its tab is open), in a ⋯ after the page's button
  let station_more = fn() {
    match in_station {
      Some((name, busy, open)) if flag(job, "browser") => {
        let label = @sf.t(if text(job, "screen") != "" { "common.login.backToStation" } else { "common.login.openInStation" }, args=[("station", name)])
        let mkey = "profile-station/" + key
        if @sf.icon_button(c, "more", key=mkey, label=@sf.t("common.login.otherWays"), disabled=busy) {
          @sf.menu([Some(@sf.menu_item_of(label, fn() { open(label) }))], from=Of(c.id(mkey)))
        }
      }
      _ => ()
    }
  }
  let waiting = fn(words : String) {
    c.box(style=pf_wait_line, fn() {
      @sf.spinner(c, size=pf_spin) |> ignore
      c.text(words, style=pf_muted) |> ignore
    })
    |> ignore
  }
  match state {
    "needs_code" if url != "" => {
      c.box(style=pf_step, fn() {
        c.text(
          if provider == "Devin" {
            @sf.t("web-pages.profiles.step1Devin", args=[("name", "still.fail")])
          } else {
            @sf.t("web-pages.profiles.step1", args=[("name", "still.fail")])
          },
          style=pf_words,
        )
        |> ignore
        c.box(style=pf_step_buttons, fn() {
          if @sf.button(c, @sf.t("web-pages.profiles.openAuth"), key="profile-auth/" + key, tone=Primary, icon="external") {
            (core.open_link)(url)
          }
          station_more()
        })
        |> ignore
      })
      |> ignore
      c.box(style=pf_step, fn() {
        c.text(if provider == "Devin" { @sf.t("web-pages.profiles.step2Devin") } else { @sf.t("web-pages.profiles.step2") }, style=pf_words)
        |> ignore
        let f = profile_field("code/" + key)
        let send = fn() {
          let code = f.text().trim(chars=" \t\n").to_owned()
          if code != "" && !sending {
            send(code, fn() { f.set("") })
          }
        }
        c.box(style=pf_input_row, fn() {
          c.box(style=pf_input_grow, fn() {
            let typed = @sf.input(c, "profile-code/" + key, placeholder=@sf.t("web-pages.profiles.pasteCode"), field=f)
            if typed.submitted {
              send()
            }
          })
          |> ignore
          if @sf.button(
              c,
              @sf.t("web-pages.profiles.finish"),
              key="profile-code-send/" + key,
              tone=Primary,
              busy=sending,
              disabled=f.text().trim(chars=" \t\n").is_empty(),
            ) {
            send()
          }
        })
        |> ignore
      })
      |> ignore
    }
    "needs_approval" if url != "" => {
      // no code where the page only asks to confirm (Cursor's); OpenCode's and Kimi's carry it in their address
      let code = text(job, "userCode")
      let filled = provider == "OpenCode" || provider == "Kimi" || code == ""
      c.box(style=pf_device, fn() {
        if code != "" {
          c.box(style=pf_device_code, fn() { c.rich([@ui.span(code, mono=true)], style=pf_device_code_words) |> ignore })
          |> ignore
        }
        let copied = profile_edit.command == "copied/" + key
        c.box(style=pf_step_buttons, fn() {
          if @sf.button(
              c,
              if filled {
                @sf.t("web-pages.profiles.openAuth")
              } else if copied {
                @sf.t("web-pages.profiles.copiedReopen")
              } else {
                @sf.t("web-pages.profiles.copyOpen")
              },
              key="profile-device/" + key,
              tone=Primary,
              icon="external",
            ) {
            if !filled {
              @ui.clipboard_set(code)
              profile_edit.command = "copied/" + key
            }
            (core.open_link)(url)
          }
          station_more()
        })
        |> ignore
        c.text(
          if code == "" {
            @sf.t("web-pages.profiles.deviceCodeNoteCursor")
          } else {
            match provider {
              "OpenCode" => @sf.t("web-pages.profiles.deviceCodeNoteOpencode")
              "Kimi" => @sf.t("web-pages.profiles.deviceCodeNoteKimi")
              "Grok" => @sf.t("web-pages.profiles.deviceCodeNoteGrok")
              _ => @sf.t("web-pages.profiles.deviceCodeNote", args=[("name", "still.fail")])
            }
          },
          style=pf_muted,
        )
        |> ignore
      })
      |> ignore
    }
    "verifying" => waiting(@sf.t("web-pages.profiles.finishing"))
    "done" => waiting(@sf.t("web-pages.profiles.adding"))
    _ => waiting(@sf.t("web-pages.profiles.generatingLink", args=[("provider", provider)]))
  }
}

///|
/// What is wrong with it and its next step (ProfileRecovery), on a card where it is in trouble (not signing in: that
/// is its sign-in's): why, what to do, a command to run where that is it, the button that does it (a key asked for,
/// its variables written, its allowance read again, checked again).
fn profile_trouble(c : @ui.Ctx, core : Core, s : Json?, p : Json?) -> Unit {
  let issue = field(p, "trouble")
  let station = text(s, "station")
  let id = text(p, "id")
  let on = [("station", station), ("id", id)]
  let action = text(issue, "action")
  let online = flag(s, "online")
  let check = fn() {
    @settings.act(core, @sf.t("android-settings.profile.checkWhat"), "profile.check", obj([("station", str(station)), ("id", str(id))]), done=@sf.t("android-settings.profile.checked"))
  }
  @sf.page_card(c, footed=true, fn() {
    @sf.card_lines(
      c,
      text(issue, "title"),
      words=text(issue, "detail"),
      note=join([text(issue, "next"), if online { "" } else { @sf.t("android-settings.profile.offline", args=[("name", text(s, "name"))]) }], "\n"),
      bad=match failed_of(core, ["profile.check", "profile.quota"], on) {
        Some(f) => f
        None => ""
      },
    )
    if action == "command" {
      @sf.copy_command(c, "profile-trouble/" + station + "/" + id, text(p, "loginCommand"), copy=@sf.t("common.copy"), copied=@sf.t("common.copied"))
    }
    let checking = is_doing(core, ["profile.check"], on)
    let refreshing = is_doing(core, ["profile.quota"], on)
    @sf.card_foot(c, fn() {
      if @sf.button(c, text(issue, "label"), key="recover-go/" + station + "/" + id, tone=Primary, busy=checking || refreshing, disabled=!online) {
        match action {
          "key" => ask_key(core, station, p)
          "env" => profile_edit.env_open = station + "/" + id
          "quota" =>
            @settings.act(core, @sf.t("android-settings.quota.checkWhat"), "profile.quota", obj([("station", str(station)), ("id", str(id))]), done=@sf.t("android-settings.quota.updated"))
          _ => check()
        }
      }
      if (action == "key" || action == "env") &&
        @sf.button(c, @sf.t("android-settings.profile.recheck"), key="recover-check/" + station + "/" + id, tone=Ghost, busy=checking, disabled=!online) {
        check()
      }
    })
  })
}

// ── its allowance and what it spent ─────────────────────────────────────

///|
/// What is left of its allowance (QuotaSection): each window as a dial, when it was read under them, reading it again;
/// its credits and its resets (resetting one asked first), a row each.
fn profile_quota(c : @ui.Ctx, core : Core, address : String, p : Json?) -> Unit {
  let id = text(p, "id")
  let on = [("station", address), ("id", id)]
  let quota = field(p, "quota")
  let refreshing = is_doing(core, ["profile.quota"], on)
  let ago = text(field(field(quota, "time"), "checkedAt"), "ago")
  let windows = items(quota, "windows")
  let credits = text(quota, "creditsText")
  @sf.section(
    c,
    @sf.t("web-pages.profiles.quota"),
    actions=fn() {
      if @sf.action(c, "profile-quota/" + address + "/" + id, @sf.t("web-pages.profiles.refresh"), icon="refresh", busy=refreshing) {
        @settings.act(core, @sf.t("web-pages.profiles.refresh"), "profile.quota", obj([("station", str(address)), ("id", str(id))]))
      }
    },
    fn() {
      @sf.group(c, fn() {
        if quota is (None | Some(Null)) {
          @sf.said_row(c, @sf.t("web-main.quota.unchecked"), "")
        } else if text(quota, "state") != "ok" || windows.length() == 0 {
          if credits == "" {
            @sf.said_row(
              c,
              match opt_text(quota, "detail") {
                Some(d) => d
                None => @sf.t("web-main.quota.unknown")
              },
              "",
            )
          }
        } else {
          @sf.block(c, fn() {
            quota_dials(c, windows)
            if ago != "" {
              c.text(@sf.t("android-settings.quota.checkedAt", args=[("ago", ago)]), style=@sf.caption) |> ignore
            }
          })
        }
        if credits != "" {
          @sf.link_row(c, "", @sf.t("android-settings.quota.credits"), value=credits, goes=false) |> ignore
        }
        if has(quota, "resetCount") {
          let busy = is_doing(core, ["profile.resetQuota"], on)
          let left = count(quota, "resetCount")
          if @sf.link_row(
              c,
              "profile-reset/" + address + "/" + id,
              @sf.t("android-settings.quota.resets"),
              note=text(quota, "resetText"),
              value=@sf.t("web-pages.profiles.reset"),
              value_lit=left > 0,
              chevron=false,
              goes=left > 0 && !busy,
              tail=fn() { doing_mark(c, busy, failed_of(core, ["profile.resetQuota"], on)) },
            ) {
            confirm(
              @sf.t("web-pages.profiles.resetConfirm"),
              @sf.t("web-pages.profiles.resetBody", args=[("name", text(p, "name")), ("n", left.to_string())]),
              @sf.t("web-pages.profiles.resetAction"),
              fn() {
                @settings.act(
                  core,
                  @sf.t("web-pages.profiles.resetAction"),
                  "profile.resetQuota",
                  obj([("station", str(address)), ("id", str(id))]),
                  done=@sf.t("web-pages.profiles.quotaReset"),
                )
              },
            )
          }
        }
      })
    },
  )
}

///|
/// What it spent in the last 7 days (UsageSection): its cost (its share of the workspace's under it) and tokens (the
/// model it used most under them) as the usage view counts them for it (its calls not, nor what its tokens are made
/// of: they say nothing a person acts on, the user 2026-10-31),
/// side by side; on several stations, here's alone. The way to the whole usage at its heading.
fn profile_usage(c : @ui.Ctx, core : Core, here : Here, s : Json?, p : Json?, entry : Json?) -> Unit {
  let address = text(s, "station")
  let usage = (core.topic)("usage", { "scope": str(here.workspace), "days": Json::number(7.0) }).value
  guard usage is Some(_) else {  }
  let item = match items(usage, "lists").search_by(fn(l) { text(Some(l), "key") == "profiles" }) {
    Some(i) =>
      match items(Some(items(usage, "lists")[i]), "items").search_by(fn(x) { text(Some(x), "key") == address + "/" + text(p, "id") }) {
        Some(k) => Some(items(Some(items(usage, "lists")[i]), "items")[k])
        None => None
      }
    None => None
  }
  let several = items(entry, "members").length() > 1
  @sf.section(
    c,
    if several {
      @sf.t("web-pages.profiles.usageHere", args=[("station", text(s, "name"))])
    } else {
      @sf.t("web-pages.profiles.usage")
    },
    actions=fn() {
      if @sf.action(c, "profile-usage-all/" + address, @sf.t("web-pages.profiles.usageAll"), icon="chart") {
        @sfbase.history_push()
        app.nav.push(Setting(Usage))
      }
    },
    fn() {
      match item {
        Some(_) =>
          @sf.figures(c, [
            (@sf.t("web-pages.profiles.usageCost"), text(item, "costText"), @sf.t("web-pages.profiles.usageShare", args=[("share", text(item, "shareText"))])),
            ("Tokens", text(item, "tokensText"), text(item, "topModel")),
          ])
        None =>
          @sf.group(c, fn() {
            if flag(field(usage, "wait"), "reading") {
              @sf.block(c, fn() { @sf.wait_line(c, @sf.t("common.reading")) })
            } else {
              @sf.said_row(c, @sf.t("web-pages.profiles.usageNone"), "")
            }
          })
      }
    },
  )
}

// ── who uses it, where it is ────────────────────────────────────────────

///|
/// Who uses it (the connects bound to it: Slack, Feishu), a row each, the model it runs at its end, to the connect's page.
fn profile_used_by(c : @ui.Ctx, core : Core, address : String, o : Json?, p : Json?) -> Unit {
  let users = strings(p, "usedBy").filter_map(fn(uid) {
    match items(o, "connects").search_by(fn(cn) { text(Some(cn), "id") == uid }) {
      Some(i) => Some(items(o, "connects")[i])
      None => None
    }
  })
  // none says nothing of the station's own chats, which run on any: no section then
  guard users.length() > 0 else {  }
  @sf.section(c, @sf.t("web-pages.profiles.usedBy"), fn() {
    @sf.group(c, fn() {
      for cn in users {
        let cv = Some(cn)
        let model = match opt_text(cv, "modelName") {
          Some(m) => m
          None =>
            match opt_text(p, "model") {
              Some(m) => match text(field(p, "names"), m) { "" => m; n => n }
              None => @sf.t("web-pages.profiles.defaultModel")
            }
        }
        if @sf.link_row(
            c,
            "profile-user/" + address + "/" + text(cv, "id"),
            text(cv, "name"),
            value=model,
            title_cut=true,
            value_cut=true,
            lead=fn() { @sf.avatar(c, text(cv, "id"), text(cv, "name"), "", pf_user_avatar) },
          ) {
          (core.push)(Connect(address, text(cv, "id")))
        }
      }
    })
  })
}

///|
/// Each station that has the account, once; a station with several profiles opens one that works.
fn profile_stations(c : @ui.Ctx, core : Core, here_station : String, entry : Json?) -> Unit {
  @sf.section(c, @sf.t("web-pages.profiles.account.each"), fn() {
    @sf.group(c, fn() {
      for m in items(entry, "places") {
        let mv = Some(m)
        let station = text(mv, "station")
        let pid = text(mv, "profileId")
        let state = field(mv, "state")
        let current = station == here_station
        if @sf.link_row(
            c,
            "profile-station/" + station,
            text(mv, "stationName"),
            goes=!current && pid != "",
            title_after=fn() {
              if current { @sf.pill(c, @sf.t("web-pages.connect.current")) }
            },
            tail=fn() {
              if !flag(mv, "online") {
                @sf.pill(c, @sf.t("web-pages.stations.offline"))
              } else if pid == "" && text(state, "text") != "" {
                @sf.pill(c, text(state, "text"), tone=pill_tone(text(state, "tone")))
              } else if !flag(mv, "usable") {
                @sf.pill(c, @sf.t("web-pages.settings.profiles.hostAway", args=[("station", text(mv, "sourceName"))]), tone=Red)
              } else if text(state, "text") != "" {
                @sf.pill(c, text(state, "text"), tone=pill_tone(text(state, "tone")))
              }
            },
          ) {
          place_pick[place_key(workspace_of(station), "profiles")] = Profile(station, pid)
          (core.push)(Profile(station, pid))
        }
      }
    })
  })
}

// ── how it runs ─────────────────────────────────────────────────────────

///|
/// Its models (ModelPool): what it can be used for now, as chips; the whole list to tick (by series, a filter when many,
/// all or none), each tick saved at once; one named by hand where the provider lists none. A provider that answers the
/// automatic decisions alone: the models its probe found. Under them, those of its models other profiles of the
/// workspace list and do not have on (`spread`), each given to all of them at a press.
fn profile_models(c : @ui.Ctx, core : Core, address : String, p : Json?, spread : Array[Json]) -> Unit {
  let id = text(p, "id")
  let key = address + "/" + id
  if flag(p, "decisionOnly") {
    @sf.section(c, @sf.t("web-pages.profiles.decisionModels"), fn() {
      @sf.loose(c, fn() {
        let found = strings(p, "decisionModels")
        if found.length() > 0 {
          c.box(style=pf_chips, flow=true, fn() {
            for m in found {
              c.box(style=pf_chip, fn() { c.text(m, style=pf_chip_words) |> ignore }) |> ignore
            }
          })
          |> ignore
        }
        if text(p, "decisionText") != "" {
          c.text(text(p, "decisionText"), style=pf_muted) |> ignore
        }
      })
    })
    return
  }
  let enabled = strings(p, "models")
  let all = strings(p, "available")
  let names = field(p, "names")
  let name = fn(m : String) { match text(names, m) { "" => m; n => n } }
  let choosing = profile_edit.choosing == key || (profile_edit.choosing == "" && enabled.length() == 0)
  @sf.section(
    c,
    @sf.t("web-pages.profiles.models"),
    note=if all.length() > 0 { @sf.t("web-pages.profiles.modelsAbout") } else { @sf.t("web-pages.profiles.modelsAboutNone") },
    actions=fn() {
      if all.length() > 0 &&
        @sf.action(
          c,
          "profile-choose/" + key,
          if choosing {
            @sf.t("web-pages.profiles.collapse")
          } else {
            @sf.t("web-pages.profiles.chooseModels", args=[("on", enabled.length().to_string()), ("all", all.length().to_string())])
          },
        ) {
        profile_edit.choosing = if choosing { "-" + key } else { key }
      }
    },
    fn() {
      @sf.loose(c, fn() {
          if all.length() > 0 && !choosing {
            // what it can be used for now, by the core's series' order
            let on : Array[String] = []
            for s in items(p, "series") {
              for m in strings(Some(s), "models") {
                if enabled.contains(m) {
                  on.push(m)
                }
              }
            }
            if on.length() == 0 {
              c.text(@sf.t("web-pages.profiles.noModels"), style=pf_muted) |> ignore
            } else {
              // (each's maker's mark where they are of more than one: one maker's are the head's)
              let makers = on.map(fn(m) { text(field(field(p, "makers"), m), "id") })
              let marked = makers.iter().any(fn(k) { k != makers[0] })
              c.box(style=pf_chips, flow=true, fn() {
                for m in on {
                  // (its id over it while it is pointed at: Accounts.tsx's tip)
                  let chip = c.id("profile-model-chip/" + key + "/" + m)
                  c.box(style=pf_chip, id=chip, taps=false, points=true, fn() {
                    if marked {
                      @sf.maker_mark(c, text(field(field(p, "makers"), m), "id"), text(p, "runtime"), pf_chip_glyph) |> ignore
                    }
                    c.text(name(m), style=pf_chip_words) |> ignore
                  })
                  |> ignore
                  @sf.tip(c, "profile-model-chip/" + key + "/" + m + "/tip", chip, m, repeats=name(m) == m)
                }
              })
              |> ignore
            }
          }
          if all.length() > 0 && choosing {
            model_checklist(c, core, address, p)
          }
          if flag(p, "canAddModel") {
            add_model(c, core, address, id)
          }
          if spread.length() > 0 {
            model_spread(c, core, address, id, spread)
          }
      })
    },
  )
}

///|
/// How it runs (FastSection, and a Claude profile's background on a message): fast mode by default, its agents' work
/// moved to the background when a message comes; each switch saved at once.
fn profile_run(c : @ui.Ctx, core : Core, address : String, p : Json?, fast : Bool, background : Bool) -> Unit {
  let id = text(p, "id")
  let on = [("station", address), ("id", id)]
  let busy = is_doing(core, ["profile.put"], on)
  let put = fn(what : String, key : String, value : Bool, done : String) {
    @settings.act(
      core,
      what,
      "profile.put",
      obj([("station", str(address)), ("id", str(id)), ("input", obj([(key, Json::boolean(value))]))]),
      done~,
    )
  }
  @sf.section(c, @sf.t("web-pages.profiles.run"), fn() {
    @sf.group(c, fn() {
      if fast {
        let now = flag(p, "fast")
        let next = @sf.switch_row(
          c,
          "profile-fast/" + address + "/" + id,
          @sf.t("web-pages.profiles.fast"),
          now,
          note=@sf.t("web-pages.profiles.fastLead"),
          busy~,
        )
        if next != now {
          put(@sf.t("web-pages.profiles.fastSave"), "fast", next, if next { @sf.t("web-pages.profiles.fastOn") } else { @sf.t("web-pages.profiles.fastOff") })
        }
      }
      if background {
        let now = flag(p, "backgroundOnMessage")
        let next = @sf.switch_row(
          c,
          "profile-background/" + address + "/" + id,
          @sf.t("web-pages.profiles.background"),
          now,
          note=if now { @sf.t("web-pages.profiles.backgroundOn") } else { @sf.t("web-pages.profiles.backgroundOff") },
          busy~,
        )
        if next != now {
          put(@sf.t("web-pages.profiles.background"), "backgroundOnMessage", next, if next { @sf.t("web-pages.profiles.turnedOn") } else { @sf.t("web-pages.profiles.turnedOff") })
        }
      }
    })
    match failed_of(core, ["profile.put"], on) {
      Some(f) => @sf.page_note(c, f, bad=true)
      None => ()
    }
  })
}

// ── whom it is shared with ──────────────────────────────────────────────

///|
/// Sharing it with the workspace's other stations (ShareSection): a switch; once on, where a subscription is signed in
/// (moved from here to another) and which stations may use it, a row each. A copy of another station's says whose it
/// is, its page a tap away.
fn profile_share(c : @ui.Ctx, core : Core, s : Json?, p : Json?, entry : Json?) -> Unit {
  let address = text(s, "station")
  let sid = text(s, "id")
  let id = text(p, "id")
  let on = [("station", address), ("id", id)]
  let share = field(p, "share")
  let stations = items(entry, "stations")
  let name_of = fn(sid : String) -> String {
    match stations.search_by(fn(x) { text(Some(x), "id") == sid }) {
      Some(i) => text(Some(stations[i]), "name")
      None => sid.view(end_offset=@cmp.minimum(8, sid.length())).to_string()
    }
  }
  let subscription = text(field(p, "access"), "kind") == "subscription"
  @sf.section(c, @sf.t("web-pages.profiles.share.title"), fn() {
    @sf.group(c, fn() {
      if text(share, "role") == "user" {
        let host = name_of(text(share, "host"))
        let lender = match items(entry, "members").search_by(fn(m) { text(Some(m), "stationId") == text(share, "host") && text(Some(m), "role") == "host" }) {
          Some(i) => Some(items(entry, "members")[i])
          None => None
        }
        let away = subscription && field(share, "reachable") is Some(False)
        if @sf.link_row(
            c,
            "profile-host/" + address + "/" + id,
            @sf.t("web-pages.profiles.share.copy", args=[("station", host)]),
            note=if away { @sf.t("web-pages.profiles.share.hostAway", args=[("station", host)]) } else { @sf.t("web-pages.profiles.share.changeThere") },
            goes=lender is Some(_),
          ) {
          match lender {
            Some(m) => (core.push)(Profile(text(Some(m), "station"), text(Some(m), "profileId")))
            None => ()
          }
        }
        return
      }
      let shared = share is Some(Object(_))
      let sharing = is_doing(core, ["profile.share"], on)
      let moving = is_doing(core, ["profile.move"], on)
      let now = @sf.switch_row(
        c,
        "profile-share/" + address + "/" + id,
        @sf.t("web-pages.profiles.share.switch"),
        shared,
        note=if !shared {
          @sf.t("web-pages.profiles.share.onlyHere", args=[("station", text(s, "name"))])
        } else if subscription {
          @sf.t("web-pages.profiles.share.lent")
        } else {
          @sf.t("web-pages.profiles.share.copied")
        },
        busy=sharing,
      )
      if now != shared {
        @settings.act(
          core,
          @sf.t("web-pages.profiles.share.switch"),
          "profile.share",
          obj([("station", str(address)), ("id", str(id)), ("on", Json::boolean(now))]),
          done=if now { @sf.t("web-pages.profiles.share.shared") } else { @sf.t("web-pages.profiles.share.unshared") },
        )
      }
      if !shared {
        return
      }
      let targets = stations.filter(fn(x) { text(Some(x), "id") != sid })
      if subscription && !flag(p, "machine") &&
        @sf.link_row(
          c,
          "profile-move/" + address + "/" + id,
          @sf.t("web-pages.profiles.share.signedIn"),
          value=text(s, "name"),
          goes=!moving && targets.length() > 0,
          tail=fn() { doing_mark(c, moving, failed_of(core, ["profile.move"], on)) },
        ) {
        move_dialog(core, s, p, targets)
      }
      let allowed = match field(share, "allow") {
        Some(Array(a)) => Some(a.filter_map(fn(x) { if x is String(v) { Some(v) } else { None } }))
        _ => None
      }
      let users = strings(share, "users").map(name_of)
      let names = match allowed {
        None => @sf.t("web-pages.profiles.share.everyStation")
        Some(a) =>
          stations
          .filter(fn(x) { a.contains(text(Some(x), "id")) || text(Some(x), "id") == sid })
          .map(fn(x) { text(Some(x), "name") })
          .join(@sf.t("web-main.list.separator"))
      }
      if @sf.link_row(
          c,
          "profile-share-pick/" + address + "/" + id,
          @sf.t("web-pages.profiles.share.stations"),
          note=if users.length() > 0 {
            @sf.t("web-pages.profiles.share.users", args=[("stations", users.join(@sf.t("web-main.list.separator")))])
          } else {
            ""
          },
          value=names,
          goes=!sharing,
        ) {
        pick_stations(core, address, id, stations, sid, allowed)
      }
    })
  })
}

///|
/// Where a shared subscription is signed in, moved to another station (`profile.move`): the others, a row each, picked
/// in a panel (one away, said so and not picked).
fn move_dialog(core : Core, s : Json?, p : Json?, targets : Array[Json]) -> Unit {
  let address = text(s, "station")
  let id = text(p, "id")
  open_dialog(
    @sf.t("web-pages.profiles.share.moveTitle"),
    description=@sf.t("web-pages.profiles.share.moveLead", args=[("station", text(s, "name"))]),
    fn(c, shut) {
      @sf.group(c, fn() {
        for x in targets {
          let xv = Some(x)
          let online = flag(xv, "online")
          if @sf.link_row(
              c,
              "profile-move-to/" + text(xv, "id"),
              text(xv, "name"),
              value=if online { "" } else { @sf.t("web-pages.stations.offline") },
              chevron=false,
              goes=online,
              lead=fn() { @sf.status_dot(c, if online { "online" } else { "offline" }) },
            ) {
            shut()
            @settings.act(
              core,
              @sf.t("web-pages.profiles.share.move"),
              "profile.move",
              obj([("station", str(address)), ("id", str(id)), ("to", str(text(xv, "id")))]),
              done=@sf.t("web-pages.profiles.share.moved", args=[("station", text(xv, "name"))]),
            )
          }
        }
      })
    },
    fn(_, _) {  },
  )
}

///|
/// Which stations may use a share (PickStations), ticked in a panel: every one (those to come too), or those ticked;
/// the one that has it always.
fn pick_stations(core : Core, address : String, id : String, stations : Array[Json], own : String, allowed : Array[String]?) -> Unit {
  let ticked : Map[String, Bool] = {}
  for x in stations {
    let xid = text(Some(x), "id")
    ticked[xid] = match allowed {
      None => true
      Some(a) => a.contains(xid)
    }
  }
  let all = fn() { stations.iter().all(fn(x) { text(Some(x), "id") == own || ticked.get(text(Some(x), "id")).unwrap_or(false) }) }
  open_dialog(
    @sf.t("web-pages.profiles.share.stations"),
    fn(c, _) {
      @sf.page_note(c, if all() { @sf.t("web-pages.profiles.share.futureIn") } else { @sf.t("web-pages.profiles.share.futureOut") })
      @sf.group(c, fn() {
        for x in stations {
          let xv = Some(x)
          let xid = text(xv, "id")
          let self = xid == own
          let on = self || ticked.get(xid).unwrap_or(false)
          let now = @sf.switch_row(
            c,
            "profile-pick/" + xid,
            text(xv, "name"),
            on,
            note=if self { @sf.t("web-pages.profiles.share.here") } else if flag(xv, "online") { "" } else { @sf.t("web-pages.stations.offline") },
            disabled=self,
          )
          if !self && now != on {
            ticked[xid] = now
          }
        }
      })
    },
    fn(c, shut) {
      if @sf.button(c, @sf.t("web-pages.profiles.share.done"), key="profile-pick-done/" + address + "/" + id, tone=Primary) {
        shut()
        let params = [("station", str(address)), ("id", str(id)), ("on", Json::boolean(true))]
        if !all() {
          let allow : Array[Json] = [str(own)]
          for x in stations {
            let xid = text(Some(x), "id")
            if xid != own && ticked.get(xid).unwrap_or(false) {
              allow.push(str(xid))
            }
          }
          params.push(("allow", Json::array(allow)))
        }
        @settings.act(core, @sf.t("web-pages.profiles.share.stations"), "profile.share", obj(params))
      }
    },
  )
}

///|
/// Which of the workspaces the station joined may run their chats on it (WorkspacesSection), a switch each, for its
/// home's managers once the station is in more than one.
fn profile_workspaces(c : @ui.Ctx, core : Core, address : String, p : Json?) -> Unit {
  let m = (core.topic)("memberships", { "station": str(address) }).value
  let joined = if flag(m, "manages") { items(m, "workspaces").filter(fn(w) { !flag(Some(w), "home") }) } else { [] }
  if joined.length() == 0 {
    return
  }
  let id = text(p, "id")
  let now = strings(p, "workspaces")
  let busy = is_doing(core, ["profile.put"], [("station", address), ("id", id)])
  @sf.section(c, @sf.t("web-pages.profiles.workspaces.title"), note=@sf.t("web-pages.profiles.workspaces.lead"), fn() {
    @sf.group(c, fn() {
      for w in joined {
        let wv = Some(w)
        let ws = text(wv, "workspace")
        let name = text(wv, "name")
        let on = now.contains(ws)
        let next = @sf.switch_row(
          c,
          "profile-ws/" + address + "/" + id + "/" + ws,
          @sf.t("web-pages.profiles.workspaces.for", args=[("name", name)]),
          on,
          note=@sf.t(if on { "web-pages.profiles.workspaces.on" } else { "web-pages.profiles.workspaces.off" }, args=[("name", name)]),
          busy~,
          // its mark before it, as the workspace is named everywhere
          lead=fn(c) { @sf.workspace_badge(c, name, text(wv, "emoji"), text(wv, "icon"), profile_ws_mark) },
        )
        if next != on {
          let list = if next { now.copy() } else { now.filter(fn(x) { x != ws }) }
          if next {
            list.push(ws)
          }
          @settings.act(
            core,
            @sf.t("web-pages.profiles.workspaces.title"),
            "profile.put",
            obj([("station", str(address)), ("id", str(id)), ("input", obj([("workspaces", Json::array(list.map(str)))]))]),
            done=@sf.t(if next { "web-pages.profiles.workspaces.turnedOn" } else { "web-pages.profiles.workspaces.turnedOff" }, args=[("name", name)]),
          )
        }
      }
    })
  })
}

// ── the account ─────────────────────────────────────────────────────────

///|
/// The account itself (AccountSection), a row each: its key masked and where its provider is (each changed from its
/// row: asked for), a subscription signed in again or by hand on the machine, or whose login the machine's own is.
fn profile_account(c : @ui.Ctx, core : Core, s : Json?, p : Json?, signed_in : Bool) -> Unit {
  let address = text(s, "station")
  let id = text(p, "id")
  let on = [("station", address), ("id", id)]
  let access = field(p, "access")
  let kind = text(access, "kind")
  let machine = flag(p, "machine")
  let keyed = ["opencode-go", "anthropic-api", "api-provider"].contains(kind) && !flag(access, "login")
  let signs = (kind == "subscription" || flag(access, "login")) && !machine
  if !machine && !keyed && !(signs && signed_in) {
    return
  }
  @sf.section(c, @sf.t("web-pages.profiles.account"), fn() {
    @sf.group(c, fn() {
      if machine {
        let runtime = @settings.runtime_label(text(p, "runtime"))
        @sf.said_row(
          c,
          if text(s, "name") != "" {
            @sf.t("web-pages.profiles.machineLoginOn", args=[("station", text(s, "name")), ("runtime", runtime)])
          } else {
            @sf.t("web-pages.profiles.machineLoginHere", args=[("runtime", runtime)])
          },
          @sf.t("web-pages.profiles.machineLoginAbout", args=[("runtime", runtime)]),
        )
      } else if keyed {
        let saving = is_doing(core, ["profile.put"], on)
        if @sf.link_row(
            c,
            "profile-key/" + address + "/" + id,
            if kind == "opencode-go" {
              "OpenCode Go key"
            } else if text(p, "providerName") != "" {
              text(p, "providerName") + " key"
            } else {
              "API key"
            },
            note=if text(access, "key") != "" { text(access, "key") } else { @sf.t("web-pages.profiles.notSaved") },
            value=@sf.t("web-pages.profiles.replace"),
            value_lit=true,
            chevron=false,
            goes=!saving,
            tail=fn() { doing_mark(c, saving, failed_of(core, ["profile.put"], on)) },
          ) {
          ask_key(core, address, p)
        }
        if has(access, "endpoint") {
          let endpoint = text(access, "endpoint")
          if @sf.link_row(
              c,
              "profile-endpoint/" + address + "/" + id,
              @sf.t("common.provider.endpoint"),
              note=endpoint,
              value=@sf.t("web-pages.profiles.replace"),
              value_lit=true,
              chevron=false,
              goes=!saving,
            ) {
            ask(@sf.t("common.provider.endpoint"), endpoint, "https://", @sf.t("common.save"), fn(value) {
              @settings.act(
                core,
                @sf.t("web-pages.profiles.replace"),
                "profile.put",
                obj([("station", str(address)), ("id", str(id)), ("input", obj([("access", obj([("kind", str(kind)), ("endpoint", str(value.trim(chars=" \t\n").to_owned()))]))]))]),
                done=@sf.t("web-pages.profiles.savedChecking"),
              )
            })
          }
        }
      } else {
        // signed in and well: signing in again, or by hand on the machine (OpenCode's has no command to run)
        let starting = is_doing(core, ["profile.login"], on)
        if @sf.link_row(
            c,
            "profile-login/" + address + "/" + id,
            @sf.t("web-pages.signIn.again"),
            note=@sf.t("web-pages.profiles.subscriptionSignIn", args=[("provider", text(p, "signInProvider"))]),
            chevron=false,
            goes=!starting,
            tail=fn() { doing_mark(c, starting, failed_of(core, ["profile.login"], on)) },
          ) {
          @settings.act(core, @sf.t("web-pages.profiles.signIn"), "profile.login", obj([("station", str(address)), ("id", str(id))]))
        }
        let command = text(p, "loginCommand")
        if command != "" && @sf.link_row(c, "profile-manual/" + address + "/" + id, @sf.t("web-pages.profiles.manual"), chevron=false) {
          @sf.panel(
            @sf.t("web-pages.profiles.manual"),
            fn(c, _) { @sf.copy_command(c, "profile-command/" + address + "/" + id, command, copy=@sf.t("common.copy"), copied=@sf.t("common.copied")) },
            from=Unanchored,
          )
        }
      }
    })
  })
}

///|
/// A new key asked for, in a field that shows dots (secret), and saved (`profile.put` with the account's kind and the
/// key); the station checks it again.
fn ask_key(core : Core, station : String, p : Json?) -> Unit {
  let id = text(p, "id")
  let kind = text(field(p, "access"), "kind")
  ask(
    if kind == "opencode-go" { @sf.t("web-pages.profiles.newOpencodeKey") } else { @sf.t("web-pages.profiles.newApiKey") },
    "",
    @sf.t("web-pages.profiles.pasteKey"),
    @sf.t("common.save"),
    secret=true,
    hint=@sf.t("web-pages.profiles.recheckHint"),
    fn(key) {
      @settings.act(
        core,
        @sf.t("web-pages.profiles.replace"),
        "profile.put",
        obj([("station", str(station)), ("id", str(id)), ("input", obj([("access", obj([("kind", str(kind)), ("key", str(key))]))]))]),
        done=@sf.t("web-pages.profiles.savedChecking"),
      )
    },
  )
}

///|
/// The variables a custom profile runs with (EnvSection): a row each, its name and its value (a secret's masked); the
/// last row opens them to be written on a card under them (a name and a value a row, deleted or added), saved as what
/// changed (a name gone or renamed: null).
fn profile_env(c : @ui.Ctx, core : Core, address : String, p : Json?) -> Unit {
  let id = text(p, "id")
  let key = address + "/" + id
  let env = items(p, "env")
  let busy = is_doing(core, ["profile.put"], [("station", address), ("id", id)])
  let open = profile_edit.env_open == key
  @sf.section(c, @sf.t("web-pages.profiles.env"), note=@sf.t("web-pages.profiles.envLead", args=[("route", "{route}")]), fn() {
    @sf.group(c, fn() {
      for e in env {
        @sf.link_row(c, "", text(Some(e), "key"), note=text(Some(e), "value"), goes=false) |> ignore
      }
      if @sf.link_row(
          c,
          "profile-env-edit/" + key,
          if open { @sf.t("web-pages.profiles.collapse") } else { @sf.t("android-settings.env.edit") },
          chevron=false,
          tail=fn() { doing_mark(c, busy, failed_of(core, ["profile.put"], [("station", address), ("id", id)])) },
        ) {
        profile_edit.env_open = if open { "" } else { key }
      }
    })
    if open {
      @sf.page_card(c, footed=true, fn() { env_editor(c, core, address, id, key, env, busy) })
    }
  })
}


///|
/// Its variables written (EnvSection's table): a name and a value a row (a secret's kept masked until it is written
/// anew), deleted or added, saved as what changed (a name gone or renamed: null).
fn env_editor(c : @ui.Ctx, core : Core, address : String, id : String, key : String, env : Array[Json], busy : Bool) -> Unit {
  // the rows as the profile has them, once its page shows them
  if profile_edit.env_of != key {
    profile_edit.env_of = key
    profile_edit.env_rows.clear()
    for e in env {
      let ev = Some(e)
      profile_edit.env_made += 1
      let kf = @ui.Field::new()
      kf.set(text(ev, "key"))
      let vf = @ui.Field::new()
      let secret = flag(ev, "secret")
      if !secret {
        vf.set(text(ev, "value"))
      }
      profile_edit.env_rows.push({ row: profile_edit.env_made, key: kf, value: vf, original: text(ev, "key"), masked: if secret { text(ev, "value") } else { "" } })
    }
  }
  c.box(style=pf_env_table, fn() {
    let gone : Array[Int] = []
    for r in profile_edit.env_rows {
      c.box(style=pf_env_row, fn() {
        c.box(style=pf_env_name, fn() {
          @sf.input(c, "profile-env-key/" + key + "/" + r.row.to_string(), placeholder="NAME", field=r.key) |> ignore
        })
        |> ignore
        c.box(style=pf_input_grow, fn() {
          @sf.input(
            c,
            "profile-env-value/" + key + "/" + r.row.to_string(),
            placeholder=if r.masked != "" {
              @sf.t("web-pages.profiles.envSaved", args=[("masked", r.masked)])
            } else {
              @sf.t("web-pages.profiles.envValue")
            },
            secret=true,
            field=r.value,
          )
          |> ignore
        })
        |> ignore
        if @sf.button(c, @sf.t("common.delete"), key="profile-env-del/" + key + "/" + r.row.to_string(), tone=Ghost) {
          gone.push(r.row)
        }
      })
      |> ignore
    }
    if gone.length() > 0 {
      let keep = profile_edit.env_rows.filter(fn(r) { !gone.contains(r.row) })
      profile_edit.env_rows.clear()
      profile_edit.env_rows.append(keep)
    }
    if @sf.button(c, @sf.t("web-pages.profiles.envAdd"), key="profile-env-add/" + key, tone=Ghost, icon="plus") {
      profile_edit.env_made += 1
      profile_edit.env_rows.push({ row: profile_edit.env_made, key: @ui.Field::new(), value: @ui.Field::new(), original: "", masked: "" })
    }
  })
  |> ignore
  @sf.card_foot(c, at_end=true, fn() {
    if @sf.button(c, @sf.t("common.save"), key="profile-env-save/" + key, tone=Primary, busy~) {
      // what changed: a name gone or renamed null, a secret left blank kept as it is
      let patch : Map[String, Json] = {}
      let kept = profile_edit.env_rows.map(fn(r) { r.key.text().trim(chars=" \t\n").to_owned() })
      for e in env {
        if !kept.contains(text(Some(e), "key")) {
          patch[text(Some(e), "key")] = Json::null()
        }
      }
      for r in profile_edit.env_rows {
        let k = r.key.text().trim(chars=" \t\n").to_owned()
        if k == "" {
          continue
        }
        if r.original != "" && r.original != k {
          patch[r.original] = Json::null()
        }
        if r.masked != "" && r.value.text() == "" && r.original == k {
          continue
        }
        patch[k] = str(r.value.text())
      }
      @settings.act(
        core,
        @sf.t("web-pages.profiles.env"),
        "profile.put",
        obj([("station", str(address)), ("id", str(id)), ("input", obj([("env", Json::object(patch))]))]),
        done=@sf.t("web-pages.profiles.saved"),
      )
    }
  })
}

///|
/// The whole list of a profile's models to enable (ModelChecklist), by the core's series, a filter when many, all or
/// none of what is shown, each tick saved at once (`profile.put` models).
fn model_checklist(c : @ui.Ctx, core : Core, address : String, p : Json?) -> Unit {
  let id = text(p, "id")
  let key = address + "/" + id
  let enabled = strings(p, "models")
  let all = strings(p, "available")
  let found = match field(field(p, "check"), "models") {
    Some(Array(a)) => Some(a.filter_map(fn(x) { if x is String(v) { Some(v) } else { None } }))
    _ => None
  }
  let saving = strings(p, "modelsSaving")
  let busy = has(p, "modelsSaving") && !(field(p, "modelsSaving") is Some(Null))
  let names = field(p, "names")
  let name = fn(m : String) { match text(names, m) { "" => m; n => n } }
  let filter = profile_field("filter/" + key)
  let q = filter.text().trim(chars=" \t\n").to_owned().to_lower()
  let shown = all.filter(fn(m) { q == "" || m.to_lower().contains(q) || name(m).to_lower().contains(q) })
  // (each once and in order, as the core puts them: ops.ts profileInput)
  let commit = fn(next : Array[String]) {
    @settings.act(
      core,
      @sf.t("web-pages.profiles.models"),
      "profile.put",
      obj([("station", str(address)), ("id", str(id)), ("input", obj([("models", Json::array(next.map(str)))]))]),
    )
  }
  c.box(style=pf_pool, fn() {
    // (all and none together, going on under the filter where the two have not the room)
    let filtered = all.length() > 10
    c.box(style=pf_pool_tools, flow=true, line_gap=@ui.Space::S3.px(), fn() {
      if filtered {
        c.box(style=pf_pool_filter, fn() {
          @sf.input(c, "profile-filter/" + key, placeholder=@sf.t("web-pages.profiles.filter"), field=filter) |> ignore
        })
        |> ignore
      }
      c.box(style=pf_pool_toggles, fn() {
        if text_toggle(c, "profile-all/" + key, if q != "" { @sf.t("web-pages.profiles.selectFiltered") } else { @sf.t("web-pages.settings.members.all") }, busy) {
          let next = enabled.copy()
          for m in shown {
            if !next.contains(m) {
              next.push(m)
            }
          }
          commit(next)
        }
        if text_toggle(c, "profile-none/" + key, if q != "" { @sf.t("web-pages.profiles.unselectFiltered") } else { @sf.t("web-pages.settings.members.none") }, busy) {
          commit(enabled.filter(fn(m) { !shown.contains(m) }))
        }
      })
      |> ignore
    })
    |> ignore
    // (the series side by side, each as wide as its longest name, going on under where the page has not the room: the
    // list a glance wide, each model's id under the pointer beside its own name, 2026-10-27 用户「信息密度也很低」)
    c.box(style=pf_series_all, flow=true, line_gap=pf_series_lines, fn() {
      for s in items(p, "series") {
        let sv = Some(s)
        let list = strings(sv, "models").filter(fn(m) { shown.contains(m) })
        if list.length() == 0 {
          continue
        }
        let every = list.iter().all(fn(m) { enabled.contains(m) })
        c.box(style=pf_series, fn() {
          c.box(style=pf_series_head, fn() {
            c.text(text(sv, "name"), style=pf_series_name) |> ignore
            if text_toggle(
                c,
                "profile-series/" + key + "/" + text(sv, "name"),
                if every { @sf.t("web-pages.settings.members.none") } else { @sf.t("web-pages.settings.members.all") },
                busy,
              ) {
              if every {
                commit(enabled.filter(fn(m) { !list.contains(m) }))
              } else {
                let next = enabled.copy()
                for m in list {
                  if !next.contains(m) {
                    next.push(m)
                  }
                }
                commit(next)
              }
            }
          })
          |> ignore
          c.box(style=pf_pool_list, fn() {
            for m in list {
              let on = enabled.contains(m)
              // (its id over it while it is pointed at: Accounts.tsx's tip)
              let item = c.id("profile-model-item/" + key + "/" + m)
              c.box(style=pf_pool_item.then(@sf.row_least_h()), id=item, taps=false, points=true, fn() {
                // (one being saved: its spinner in its box's place, as big, so nothing beside or after it moves; a
                // spinner after its name widened its series and moved the ones after it, 2026-10-31 用户「loading 会
                // 导致页面抖动」)
                if saving.contains(m) {
                  c.box(style=pf_pool_spin, fn() { @sf.spinner(c, size=pf_spin) |> ignore }) |> ignore
                } else {
                  let now = @kit.checkbox(c, "profile-model/" + key + "/" + m, if on { On } else { Off }, label=name(m), disabled=busy).value
                  if (now == On) != on {
                    commit(if on { enabled.filter(fn(x) { x != m }) } else { enabled.copy()..push(m) })
                  }
                }
                @sf.maker_mark(c, text(field(field(p, "makers"), m), "id"), text(p, "runtime"), pf_chip_glyph) |> ignore
                c.text(name(m), style=pf_chip_words) |> ignore
                match found {
                  Some(f) if !f.contains(m) => c.text(@sf.t("web-pages.profiles.gone"), style=pf_gone) |> ignore
                  _ => ()
                }
              })
              |> ignore
              @sf.tip(c, "profile-model-item/" + key + "/" + m + "/tip", item, m, repeats=name(m) == m)
            }
          })
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A quiet word that does something (controls.css.ts textToggle): muted, the words' ink under the pointer.
fn text_toggle(c : @ui.Ctx, key : String, words : String, disabled : Bool) -> Bool {
  let id = c.id(key)
  let b = c.box(style=pf_toggle, id=if disabled { 0 } else { id }, fn() {
    c.text(words, style=if c.hovered(id) && !disabled { pf_toggle_lit } else { pf_toggle_words }) |> ignore
  })
  c.semantics(b, Button, id~, label=words, disabled~)
  !disabled && c.clicked(id)
}

///|
/// A profile's models other profiles of the workspace list and do not have on (the core's `spread`): one quiet press
/// under its models, 加到其他 profile (how many could be given), opening them in a dialog, not on the page (2026-10-31
/// 用户「不要直接展开在主页面」).
fn model_spread(c : @ui.Ctx, core : Core, address : String, id : String, spread : Array[Json]) -> Unit {
  let n = spread.fold(init=0, fn(k, s) { k + items(Some(s), "targets").length() })
  let asked = fx_spread_up.val
  fx_spread_up.val = false
  if text_toggle(c, "profile-spread/" + address + "/" + id, @sf.t("web-pages.profiles.spreadOpen", args=[("n", n.to_string())]), false) ||
    asked {
    spread_dialog(core, address, id, spread)
  }
}

///|
/// The dialog of a profile's models others could have, put up by a fixture's mode (settings-profile-spread-dialog) as
/// its page is drawn.
// kept across runs: said by the settings' fixture; pages.mbt reset puts it back
pub let fx_spread_up : Ref[Bool] = Ref(false)

///|
/// The dialog of a profile's models others could have: each model's name over a box for each profile that could have
/// it, none ticked; 添加 gives each ticked one its model (`profile.addModel` on its station, as that provider spells
/// it), and closes.
fn spread_dialog(core : Core, address : String, id : String, spread : Array[Json]) -> Unit {
  let ticked : Map[String, Bool] = {}
  let key_of = fn(s : Json, x : Json) { text(Some(s), "model") + "\n" + text(Some(x), "station") + "\n" + text(Some(x), "profileId") }
  let any = fn() { ticked.iter().any(fn(e) { e.1 }) }
  open_dialog(
    @sf.t("web-pages.profiles.spreadTitle"),
    description=@sf.t("web-pages.profiles.spreadLead"),
    fn(c, _) {
      c.box(style=pf_spread, fn() {
        for s in spread {
          c.box(style=pf_spread_model, fn() {
            c.text(text(Some(s), "name"), style=pf_spread_name) |> ignore
            // (its rows straight on the dialog, out past its words by a row's room so each box stands under the
            // model's name, as 共享到其他 workspace's: a group's card was lost on the dialog's ground but for its
            // room, 2026-10-31 用户「为啥有这么大的缩进」)
            c.box(style=pf_spread_rows, fn() {
              for x in items(Some(s), "targets") {
                let k = key_of(s, x)
                let on = ticked.get(k).unwrap_or(false)
                let now = @sf.check_row(c, "profile-spread-pick/" + k, text(Some(x), "profileName"), on, note=text(Some(x), "stationName"))
                if now != on {
                  ticked[k] = now
                }
              }
            })
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    },
    fn(c, shut) {
      if @sf.button(c, @sf.t("web-pages.profiles.spreadAdd"), key="profile-spread-add/" + address + "/" + id, tone=Primary, disabled=!any()) {
        shut()
        for s in spread {
          let what = @sf.t("web-pages.profiles.spreadWhat", args=[("model", text(Some(s), "name"))])
          for x in items(Some(s), "targets") {
            if ticked.get(key_of(s, x)).unwrap_or(false) {
              let xv = Some(x)
              @settings.act(core, what, "profile.addModel", obj([("station", str(text(xv, "station"))), ("id", str(text(xv, "profileId"))), ("model", str(text(xv, "model")))]))
            }
          }
        }
      }
    },
  )
}

///|
/// A model named by hand (AddModel), for a provider that does not list them all.
fn add_model(c : @ui.Ctx, core : Core, address : String, id : String) -> Unit {
  let f = profile_field("add-model/" + address + "/" + id)
  let adding = is_doing(core, ["profile.addModel"], [("station", address), ("id", id)])
  let add = fn() {
    let m = f.text().trim(chars=" \t\n").to_owned()
    if m != "" && !adding {
      @settings.act(core, @sf.t("web-pages.profiles.addModelWhat"), "profile.addModel", obj([("station", str(address)), ("id", str(id)), ("model", str(m))]))
      f.set("")
    }
  }
  c.box(style=pf_input_row, fn() {
    c.box(style=pf_input_grow, fn() {
      if @sf.input(
          c,
          "profile-add-model/" + address + "/" + id,
          placeholder=@sf.t("web-pages.profiles.addModelPlaceholder"),
          shorter=[@sf.t("web-mobile.profiles.addModelPlaceholder")],
          field=f,
        ).submitted {
        add()
      }
    })
    |> ignore
    if @sf.button(c, @sf.t("web-pages.profiles.addModel"), key="profile-add-model-go/" + address + "/" + id, busy=adding, disabled=f.text().trim(chars=" \t\n").is_empty()) {
      add()
    }
  })
  |> ignore
}

// ── styles (pages.css.ts identity, Accounts.css.ts) ─────────────────────

///|
/// Words on its cards, and the quieter ones (the ui's 13 on 24; muted).
// kept across runs: a value (no field of it changes)
let pf_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let pf_muted : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, w=Full)

///|
let pf_mark_glyph : Double = 26.0

///|
let pf_chip_glyph : Double = 14.0


///|
let pf_user_avatar : Double = 24.0







///|
/// What its last check said, cut short where its line has less.
// kept across runs: a value (no field of it changes)
let pf_check_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false, w=Cut)

///|
/// Its state under its name (profileState: 8 apart).
// kept across runs: a value (no field of it changes)
let pf_state : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
/// The runtimes' tags (runtimeTags: 4 apart, 8 after the name; a tag 18 high, 5 in, round 5, the hover's ground).
// kept across runs: a value (no field of it changes)
let pf_tags : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
pub let pf_tag : @ui.Style = @ui.css("row h=S4_5 px=S1 gap=SPx align=ACenter radius=Base bg=Hover")

///|
// kept across runs: a value (no field of it changes)
pub let pf_tag_words : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4, weight=Medium, color=Muted, wrap=false)


///|
// kept across runs: a value (no field of it changes)
let pf_wait_line : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
/// A sign-in's step (steps: its words over what is done in it).
// kept across runs: a value (no field of it changes)
let pf_step : @ui.Style = @ui.css("w=Full gap=S2 align=AStart")

///|
/// A step's page button, and the ⋯ after it of the other way of opening it (the station's browser).
// kept across runs: a value (no field of it changes)
let pf_step_buttons : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pf_input_row : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pf_input_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
/// A device's code (deviceCode: the code large, then its one button, 10 apart).
// kept across runs: a value (no field of it changes)
let pf_device : @ui.Style = @ui.css("w=Full gap=S2_5 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let pf_device_code : @ui.Style = @ui.css("px=S3 py=S1_5 radius=Lg bg=Hover")

///|
// kept across runs: a value (no field of it changes)
let pf_device_code_words : @ui.TextStyle = @ui.text_style(size=Heading, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pf_line : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pf_share_rows : @ui.Style = @ui.css("w=Full pt=S2_5 gap=S3_5")

///|
// kept across runs: a value (no field of it changes)
let pf_share_value : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
/// The models' parts (modelsBody: 10 apart); a chip (modelChip: 4 by 10 in, round, the hover's ground).
// kept across runs: a value (no field of it changes)
let pf_models_body : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
/// The dialog's models, 16 apart.
// kept across runs: a value (no field of it changes)
let pf_spread : @ui.Style = @ui.css("w=Full gap=S4")

///|
// kept across runs: a value (no field of it changes)
let pf_spread_name : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Medium, color=Fg, w=Full)

///|
/// A model's profiles, a tick row each, out past the dialog's words by a row's own room (check_row's: its box under
/// the model's name).
// kept across runs: a value (no field of it changes)
let pf_spread_rows : @ui.Style = @sf.outset_start(@sf.row_corner)

///|
/// A model of them: its name, its profiles' boxes 6 under it.
// kept across runs: a value (no field of it changes)
let pf_spread_model : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let pf_chips : @ui.Style = @ui.css("row w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let pf_chip : @ui.Style = @ui.css("row px=S2_5 py=S1 gap=S1_5 align=ACenter radius=Full bg=Hover")

///|
// kept across runs: a value (no field of it changes)
let pf_chip_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, wrap=false)

///|
/// The list to tick (modelPool): its tools (a filter, all, none), each series' head and its models.
// kept across runs: a value (no field of it changes)
let pf_pool : @ui.Style = @ui.css("w=Full gap=S3")

///|
// kept across runs: a value (no field of it changes)
let pf_pool_tools : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
/// Its all and none, one beside the other (each 4 in: pf_toggle), moving as one.
// kept across runs: a value (no field of it changes)
let pf_pool_toggles : @ui.Style = @ui.css("row gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pf_pool_filter : @ui.Style = @ui.css("w=S60")

///|
/// The series side by side, 36 apart (as an allowance's windows are: quota_dials), 16 between their lines.
// kept across runs: a value (no field of it changes)
let pf_series_all : @ui.Style = @ui.css("row w=Full gap=S9")

///|
let pf_series_lines : Double = 16.0

///|
/// A series: its name over its models, as wide as the longest of them, each model as wide as its own words (its id's
/// tip under them, not under the middle of the card).
// kept across runs: a value (no field of it changes)
let pf_series : @ui.Style = @ui.css("gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let pf_series_head : @ui.Style = @ui.css("row gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pf_series_name : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pf_pool_list : @ui.Style = @ui.css("gap=SPx")

///|
/// A model's row (its height at least a row's, row_least_h at its use: the press's room).
// kept across runs: a value (no field of it changes)
let pf_pool_item : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
/// A model's spinner while it is saved, in its checkbox's place: as big (the kit's 18).
// kept across runs: a value (no field of it changes)
let pf_pool_spin : @ui.Style = @ui.css("row w=S4_5 h=S4_5 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let pf_gone : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pf_toggle : @ui.Style = @ui.css("px=S1")

///|
// kept across runs: a value (no field of it changes)
let pf_toggle_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pf_toggle_lit : @ui.TextStyle = pf_toggle_words.then(@ui.text_style(color=Fg))

///|
/// The variables' rows (envTable: 8 apart; a row its name, its value wider, deleting it).
// kept across runs: a value (no field of it changes)
let pf_env_table : @ui.Style = @ui.css("w=Full gap=S2")

///|
// kept across runs: a value (no field of it changes)
let pf_env_row : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pf_env_name : @ui.Style = @ui.css("w=S48")

///|
/// How it runs: its switches 14 apart.
// kept across runs: a value (no field of it changes)
let pf_run_rows : @ui.Style = @ui.css("w=Full gap=S3_5")

// ── choosing its models ─────────────────────────────────────────────────

///|
/// 选择模型, right after a profile is added (PickModelsPage; the narrow app's PickModelsScreen): what it is for, the list
/// to tick (or a wait while it is read, or why none is listed), a model named by hand where the provider lists none;
/// 跳过 and 完成 (wide: at the head's end; narrow: over the list) go on to its page in this one's place.
pub fn pick_models_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame, address : String, id : String) -> Unit {
  let look = look_of(c)
  let s = @settings.station_of(core, here, address)
  let o = field(s, "overview")
  let key = "pick-models/" + address + "/" + id
  let title = @sf.t("web-pages.profiles.pickModels.title")
  guard o is Some(Object(_)) else {
    @sf.page(c, on_back=core.pop, frame~, key, title, [
      fn() { @sf.waiting(c, fn() { models_sample(c, core, look) }, text=@sf.t("web-pages.profiles.loading")) },
    ])
  }
  guard items(o, "profiles").search_by(fn(p) { text(Some(p), "id") == id }) is Some(i) else {
    @sf.page(c, on_back=core.pop, frame~, key, title, [
      fn() { @sf.page_note(c, @sf.t("web-pages.profiles.notFound", args=[("id", id)])) },
    ])
  }
  let p = Some(items(o, "profiles")[i])
  // on to its page, in this one's place
  let leave = fn() { (core.in_place)(Profile(address, id)) }
  let buttons = fn() {
    if @sf.button(c, @sf.t("web-pages.profiles.pickModels.skip"), key=key + "/skip", tone=Ghost) {
      leave()
    }
    if @sf.button(c, @sf.t("common.done"), key=key + "/done", tone=Primary, disabled=items(p, "models").length() == 0) {
      leave()
    }
  }
  let listed = items(p, "available").length() > 0
  let check = field(p, "check")
  let blocks : Array[() -> Unit] = [
    fn() {
      models_body(c, core, look, address, p, fn() {
        if flag(p, "modelsReading") {
          @sf.wait_line(c, @sf.t("web-pages.profiles.pickModels.reading"))
        } else if !listed && !flag(p, "canAddModel") {
          c.text(
            if text(check, "state") == "ok" {
              @sf.t("web-pages.profiles.pickModels.none")
            } else if text(check, "detail") != "" {
              text(check, "detail")
            } else {
              text(p, "checkText")
            },
            style=desk_muted,
          )
          |> ignore
        } else {
          models_pool(c, core, look, address, id, p)
        }
      })
    },
  ]
  // (narrow: 跳过 and 完成 under what the page is for, over the list, at its end)
  if look == Narrow {
    blocks.insert(0, fn() { c.box(style=pf_pick_foot, buttons) |> ignore })
  }
  @sf.page(c, on_back=core.pop, frame~, key,
    title,
    lead=@sf.t("web-pages.profiles.pickModels.lead", args=[("name", text(p, "name"))]),
    actions?=if look == Wide { Some(fn() { c.box(style=pf_pick_actions, buttons) |> ignore }) } else { None },
    blocks,
  )
}

///|
/// 模型, which of a profile's models may be used, on a page of their own (the narrow app's ProfileModelsScreen; the
/// wide page has the same list on the profile's): how many are on under its title, the list to tick, a model named by
/// hand where the provider lists none.
pub fn profile_models_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame, address : String, id : String) -> Unit {
  let look = look_of(c)
  let s = @settings.station_of(core, here, address)
  let o = field(s, "overview")
  let key = "profile-models/" + address + "/" + id
  let title = @sf.t("web-pages.profiles.models")
  guard items(o, "profiles").search_by(fn(p) { text(Some(p), "id") == id }) is Some(i) else {
    @sf.page(c, on_back=core.pop, frame~, key, title, [
      fn() {
        if o is Some(Object(_)) {
          @sf.page_note(c, @sf.t("web-pages.profiles.notFound", args=[("id", id)]))
        } else {
          @sf.waiting(c, fn() { models_sample(c, core, look) }, text=@sf.t("web-pages.profiles.loading"))
        }
      },
    ])
  }
  let p = Some(items(o, "profiles")[i])
  let ticked = items(p, "models").length()
  @sf.page(c, on_back=core.pop, frame~, key,
    title,
    lead=if ticked > 0 { @sf.t("android-settings.profile.pickModels.selected", args=[("n", ticked.to_string())]) } else { "" },
    // read again (its models as the provider lists them now), at its title's end
    actions=fn() {
      let on = [("station", address), ("id", id)]
      let checking = is_doing(core, ["profile.check"], on)
      if tap_text(
          c,
          "models-refresh/" + key,
          @sf.t(if checking { "android-settings.refreshing" } else { "android-settings.models.refresh" }),
          color=@sf.link_ink(),
          size=link_size,
        ) &&
        !checking {
        @settings.act(
          core,
          @sf.t("android-settings.models.refreshWhat"),
          "profile.check",
          obj([("station", str(address)), ("id", str(id))]),
          done=@sf.t("android-settings.models.refreshed"),
        )
      }
    },
    [
      // what they are for (the narrow app's note)
      fn() { @sf.page_note(c, @sf.t("android-settings.models.note")) },
      fn() {
        models_body(c, core, look, address, p, fn() { models_pool(c, core, look, address, id, p) })
      },
    ],
  )
}

///|
/// A profile made up, for what its page shows while it is read (profile_view in its bones): its name, how it stands,
/// its allowance, the models it may use.
fn profile_sample() -> Json {
  let models = [7, 9, 6, 8, 5].mapi(fn(i, n) { ("sample" + i.to_string(), @sf.sample_words(n)) })
  let w = fn(n : Int) { Json::string(@sf.sample_words(n)) }
  let window = fn(left : Int) -> Json { { "left": Json::number(left.to_double()), "level": "ok", "label": w(3), "refills": w(5) } }
  {
    "id": "sample",
    "name": Json::string(@sf.sample_words(8)),
    "kindText": w(4),
    "checkTone": "green",
    "checkLine": w(4),
    "check": { "time": { "checkedAt": { "ago": w(5) } } },
    "quota": { "state": "ok", "windows": [window(60), window(20)], "time": { "checkedAt": { "ago": w(5) } } },
    "available": Json::array(models.map(fn(m) { Json::string(m.0) })),
    "models": Json::array(models.map(fn(m) { Json::string(m.0) })),
    "names": Json::object(Map::from_array(models.map(fn(m) { (m.0, Json::string(m.1)) }))),
  }
}

///|
/// A profile's models to come while they are read (the library's Waiting, in its bones): the list to tick, made up, as
/// the page draws it.
fn models_sample(c : @ui.Ctx, core : Core, look : Look) -> Unit {
  let p = Some(profile_sample())
  let core = core.quiet()
  models_body(c, core, look, "sample", p, fn() { models_pool(c, core, look, "sample", "sample", p) })
}

///|
/// A profile's models to tick (those listed) and one to name by hand (where it can be), loose on its page (models_body):
/// as far in as the page's words, nothing reaching for a card's corners.
fn models_pool(c : @ui.Ctx, core : Core, look : Look, address : String, id : String, p : Json?) -> Unit {
  ignore(look)
  c.box(style=pf_models_body, fn() {
    if items(p, "available").length() > 0 {
      model_checklist(c, core, address, p)
    }
    if flag(p, "canAddModel") {
      add_model(c, core, address, id)
    }
  })
  |> ignore
}

///|
/// What a page of a profile's models holds, and why saving them failed under it: narrow, on a card 12 from the page's
/// sides.
fn models_body(c : @ui.Ctx, core : Core, look : Look, address : String, p : Json?, body : () -> Unit) -> Unit {
  ignore(look)
  @sf.loose(c, fn() {
    body()
    match failed_of(core, ["profile.put"], [("station", address), ("id", text(p, "id"))]) {
      Some(f) => @sf.card_lines(c, "", bad=f)
      None => ()
    }
  })
}

///|
/// 跳过 and 完成 on a narrow page, over its list: in the page's room, 10 under them, 10 apart, at the end.
// kept across runs: a value (no field of it changes)
let pf_pick_foot : @ui.Style = @ui.css("row w=Full pb=S2_5 gap=S2_5 justify=JEnd")

///|
/// Its two buttons at the head's end (pickModelsActions: 8 apart).
// kept across runs: a value (no field of it changes)
let pf_pick_actions : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
/// A workspace's mark before its switch's title (Accounts.tsx WorkspaceNamed: 16).
let profile_ws_mark : Double = 16.0
