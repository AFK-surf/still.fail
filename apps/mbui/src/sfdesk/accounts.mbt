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
let profile_edit : ProfileEdit = { choosing: "", command: "", replacing: "", env_rows: [], env_of: "", env_made: 0 }

///|
/// The fields of a profile's page, by their key (made as first drawn).
// kept across runs: made as a page first shows one; profile_page_reset empties it
let profile_fields : Map[String, @ui.Field] = {}

///|
/// Whether a profile's models are being chosen ("" none: its page's own, by station and id), and the ⋯ open.
// kept across runs: said by the page's presses; profile_page_reset puts it back
let profile_menu_open : Ref[String] = Ref("")

///|
fn profile_page_reset() -> Unit {
  profile_edit.choosing = ""
  profile_edit.command = ""
  profile_edit.replacing = ""
  profile_edit.env_rows.clear()
  profile_edit.env_of = ""
  profile_edit.env_made = 0
  profile_fields.clear()
  profile_menu_open.val = ""
}

///|
/// A field of the page, by its key, made once.
fn profile_field(key : String) -> @ui.Field {
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
/// A profile's page (AccountPage), by its station and id: a wait until the station's overview is read; one gone,
/// that it is not found.
fn profile_page(c : @ui.Ctx, core : Core, here : Here, address : String, id : String) -> Unit {
  let s = @settings.station_of(core, here, address)
  let o = field(s, "overview")
  let back = "Profile"
  guard o is Some(Object(_)) else {
    desk_page(c, core, "profile/" + address + "/" + id, back, back~, [
      fn() { @sf.waiting(c, shape=Cards, note={ reading: true, text: @sf.t("web-pages.profiles.loading"), failing: [] }) },
    ])
  }
  match items(o, "profiles").search_by(fn(p) { text(Some(p), "id") == id }) {
    Some(i) => profile_view(c, core, here, s, o, Some(items(o, "profiles")[i]))
    None =>
      desk_page(c, core, "profile/" + address + "/" + id, back, back~, [
        fn() { c.text(@sf.t("web-pages.profiles.notFound", args=[("id", id)]), style=desk_muted) |> ignore },
      ])
  }
}

///|
/// The page (AccountView).
fn profile_view(c : @ui.Ctx, core : Core, here : Here, s : Json?, o : Json?, p : Json?) -> Unit {
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
  let entry = match
    items((core.topic)("profiles", { "scope": str(here.workspace) }).value, "items").search_by(fn(e) {
      items(Some(e), "members").iter().any(fn(m) { text(Some(m), "station") == address && text(Some(m), "profileId") == id })
    }) {
    Some(i) => Some(items((core.topic)("profiles", { "scope": str(here.workspace) }).value, "items")[i])
    None => None
  }
  let blocks : Array[() -> Unit] = []
  // a subscription that needs signing in, or is signing in: that first
  if !copy && signs_in && !machine && (text(check, "state") == "login" || signing_in) {
    blocks.push(fn() { profile_sign_in(c, core, address, p, true) })
  }
  blocks.push(fn() { profile_quota(c, core, address, p) })
  blocks.push(fn() { profile_usage(c, core, here, s, p, entry) })
  if entry is Some(_) && items(entry, "members").filter(fn(m) { text(Some(m), "role") != "user" }).length() > 1 {
    blocks.push(fn() { profile_stations(c, core, address, entry) })
  }
  if has(o, "sharing") && !(field(o, "sharing") is Some(Null)) {
    blocks.push(fn() { profile_share(c, core, s, p, entry) })
  }
  if !copy {
    blocks.push(fn() { profile_workspaces(c, core, address, p) })
    blocks.push(fn() { profile_models(c, core, address, p) })
    // how it runs, in one section (the web's two of the same title: fast mode, and the background on a message)
    let fast = has(p, "fast") && !(field(p, "fast") is Some(Null))
    let background = items(p, "runtimes").iter().any(fn(r) { r == "claude" }) && has(p, "backgroundOnMessage")
    if fast || background {
      blocks.push(fn() { profile_run(c, core, address, p, fast, background) })
    }
  }
  blocks.push(fn() { profile_used_by(c, core, address, o, p) })
  if !copy {
    if machine {
      blocks.push(fn() { profile_machine_account(c, s, p) })
    } else {
      blocks.push(fn() {
        profile_account(c, core, address, p, text(check, "state") != "login" && !signing_in)
      })
    }
    if kind == "env" {
      blocks.push(fn() { profile_env(c, core, address, p) })
    }
  }
  desk_page(c, core, "profile/" + address + "/" + id, text(p, "name"), back="Profile", head=fn() {
      profile_head(c, core, here, address, p, entry)
    }, blocks)
}

///|
/// Its head (AccountView's identity): its provider's mark, its name (renamed here, but for the machine's own and a
/// copy) and the runtimes it serves, what it is, its last check and when, checking again; its ⋯.
fn profile_head(c : @ui.Ctx, core : Core, here : Here, address : String, p : Json?, entry : Json?) -> Unit {
  let t = @sf.theme()
  let id = text(p, "id")
  let on = [("station", address), ("id", id)]
  let copy = text(field(p, "share"), "role") == "user"
  let machine = flag(p, "machine")
  c.box(style=pf_head, fn() {
    c.box(style=pf_mark, fn() {
      @sf.maker_mark(c, text(p, "providerMark"), text(p, "runtime"), pf_mark_glyph) |> ignore
    })
    |> ignore
    c.box(style=pf_identity, keep=true, fn() {
      c.box(style=pf_name_line, fn() {
        // its new name shows while it is saved
        let saving = is_doing(core, ["profile.put"], on)
        // (short of room, its name is cut short, its tags and its rename kept)
        c.text(text(p, "name"), style=pf_name) |> ignore
        if saving {
          @sf.spinner(c, size=pf_spin) |> ignore
        }
        runtime_tags(c, items(p, "runtimes"), items(p, "uses").iter().any(fn(u) { u == "decision" }))
        if !machine && !copy &&
          @sf.icon_button(c, "edit", key="profile-rename/" + address + "/" + id, label=@sf.t("web-pages.settings.stations.rename")) {
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
      })
      |> ignore
      // what it is, in a line: its kind, the address signed in (when not its name), where it is
      let email = text(p, "email")
      let facts = [text(p, "kindText"), if email != text(p, "name") { email } else { "" }, text(entry, "where")]
      let line = join(facts, " · ")
      if line != "" {
        c.text(line, style=pf_sub) |> ignore
      }
      c.box(style=pf_state, fn() {
        if text(p, "checkTone") != "green" {
          @sf.pill(c, text(p, "checkText"), tone=pill_tone(text(p, "checkTone")))
        }
        // (short of room, when it was checked leaves, then what the check said is cut short; checking again kept)
        c.text(text(p, "checkLine"), style=pf_check_words) |> ignore
        let ago = text(field(field(field(p, "check"), "time"), "checkedAt"), "ago")
        if ago != "" {
          c.box(drop=pf_drop_checked, fn() {
            c.text(@sf.t("web-pages.profiles.checkedAt", args=[("time", ago)]), style=pf_sub_quiet) |> ignore
          })
          |> ignore
        }
        let checking = is_doing(core, ["profile.check"], on)
        if @sf.icon_button(c, "refresh", key="profile-check/" + address + "/" + id, disabled=checking, label=@sf.t("web-pages.profiles.recheck")) {
          @settings.act(core, @sf.t("web-pages.profiles.recheck"), "profile.check", obj([("station", str(address)), ("id", str(id))]))
        }
        if checking {
          @sf.spinner(c, size=pf_spin) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
    if !copy {
      profile_menu(c, core, here, address, p)
    }
  })
  |> ignore
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
          c.box(style=pf_tag, fn() {
            @sf.maker_mark(c, "", rt, pf_tag_glyph) |> ignore
            c.text(runtime_tag(rt), style=pf_tag_words) |> ignore
          })
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
    _ => r
  }
}

///|
/// Its ⋯: deleting it (the machine's own login: stopping it, the login stays the machine's), asked first.
fn profile_menu(c : @ui.Ctx, core : Core, here : Here, address : String, p : Json?) -> Unit {
  let t = @sf.theme()
  let id = text(p, "id")
  let key = address + "/" + id
  let machine = flag(p, "machine")
  let mid = c.id("profile-more/" + key)
  c.cursor(mid, Hand)
  let open = profile_menu_open.val == key
  if c.clicked(mid) {
    profile_menu_open.val = if open { "" } else { key }
  }
  let b = c.box(style=st_more, id=mid, fn() { @sf.icon(c, "more", size=st_more_icon, color=t.p.muted) |> ignore })
  c.semantics(b, Button, id=mid, label=@sf.t("common.more"), expanded=open)
  let item = if machine { @sf.t("web-pages.profiles.disable") } else { @sf.t("web-pages.profiles.delete") }
  let m = @sf.dropdown(c, "profile-menu/" + key, open, mid, [@kit.menu_item("remove", label=item)], { "remove": "trash" }, @sf.menu_w, along=End)
  if open && !m.open {
    profile_menu_open.val = ""
  }
  if m.chosen is Some(_) {
    profile_menu_open.val = ""
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
      place_pick.remove("profiles")
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
  ignore(here)
}

// ── signing in ──────────────────────────────────────────────────────────

///|
/// Signing a subscription in without a terminal (SignIn): still.fail runs the runtime's login on its machine and this
/// relays the browser's steps. Not under way: why (needed, or again), the way to start it, the command to run by hand.
/// Under way: what the person does in the browser (LoginSteps), 取消.
fn profile_sign_in(c : @ui.Ctx, core : Core, address : String, p : Json?, needed : Bool) -> Unit {
  let id = text(p, "id")
  let on = [("station", address), ("id", id)]
  let job = field(p, "login")
  let state = text(job, "state")
  let provider = text(p, "signInProvider")
  let active = ["starting", "needs_code", "needs_approval", "verifying"].contains(state)
  let key = address + "/" + id
  c.box(style=desk_card, fn() {
    if !active {
      c.box(style=desk_card_text, fn() {
        c.text(
          if needed {
            @sf.t("web-pages.profiles.notSignedIn", args=[("provider", provider)])
          } else {
            @sf.t("web-pages.profiles.subscriptionSignIn", args=[("provider", provider)])
          },
          style=desk_strong,
        )
        |> ignore
        c.text(
          match state {
            "failed" => @sf.t("web-pages.profiles.lastFailed", args=[("error", text(job, "error"))])
            "done" => @sf.t("web-pages.profiles.signedInSwitch")
            _ => @sf.t("web-pages.profiles.signInNote", args=[("name", "still.fail")])
          },
          style=desk_muted,
        )
        |> ignore
      })
      |> ignore
      let command = text(p, "loginCommand")
      if profile_edit.command == key && command != "" {
        @sf.copy_command(c, "profile-command/" + key, command, copy=@sf.t("common.copy"), copied=@sf.t("common.copied"))
      }
      c.box(style=pf_card_foot, fn() {
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
              if shown { @sf.t("web-pages.profiles.collapse") } else { @sf.t("web-pages.profiles.manual") },
              key="profile-manual/" + key,
              tone=Ghost,
            ) {
            profile_edit.command = if shown { "" } else { key }
          }
        }
      })
      |> ignore
      return
    }
    c.box(style=desk_card_text, fn() {
      c.text(@sf.t("web-pages.profiles.signingIn", args=[("provider", provider)]), style=desk_strong) |> ignore
      c.text(@sf.t("web-pages.profiles.signingInNote"), style=desk_muted) |> ignore
    })
    |> ignore
    login_steps(c, core, address + "/" + id, job, provider, is_doing(core, ["profile.loginCode"], on), fn(code, sent) {
      @settings.act(
        core,
        @sf.t("web-pages.profiles.finish"),
        "profile.loginCode",
        obj([("station", str(address)), ("id", str(id)), ("code", str(code))]),
        then=fn(_) { sent() },
      )
    })
    c.box(style=pf_card_foot, fn() {
      let cancelling = is_doing(core, ["profile.cancelLogin"], on)
      if @sf.button(c, @sf.t("common.cancel"), key="profile-login-cancel/" + key, tone=Ghost, busy=cancelling) {
        @settings.act(core, @sf.t("common.cancel"), "profile.cancelLogin", obj([("station", str(address)), ("id", str(id))]))
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// What the person does in the browser for a sign-in under way (LoginSteps): the link and the code to paste back
/// (Claude, Devin), the code to enter on the page that opens (DeviceCode: Codex, Grok, OpenCode, Kimi, Cursor's page
/// alone); while it is checked or added, said so.
/// `key`: whose steps they are; `send`: a code pasted back sent, then `sent` (its field emptied); `sending` while it is.
fn login_steps(
  c : @ui.Ctx,
  core : Core,
  key : String,
  job : Json?,
  provider : String,
  sending : Bool,
  send : (String, () -> Unit) -> Unit,
) -> Unit {
  let state = text(job, "state")
  let url = text(job, "url")
  let waiting = fn(words : String) {
    c.box(style=pf_wait_line, fn() {
      @sf.spinner(c, size=pf_spin) |> ignore
      c.text(words, style=desk_muted) |> ignore
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
          style=desk_words,
        )
        |> ignore
        if @sf.button(c, @sf.t("web-pages.profiles.openAuth"), key="profile-auth/" + key, tone=Primary, icon="external") {
          (core.open_link)(url)
        }
      })
      |> ignore
      c.box(style=pf_step, fn() {
        c.text(if provider == "Devin" { @sf.t("web-pages.profiles.step2Devin") } else { @sf.t("web-pages.profiles.step2") }, style=desk_words)
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
          style=desk_muted,
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

// ── its allowance and what it spent ─────────────────────────────────────

///|
/// What is left of its allowance (QuotaSection): each window as a dial, when it was read on hover, reading it again;
/// its credits and its resets (resetting one asked first).
fn profile_quota(c : @ui.Ctx, core : Core, address : String, p : Json?) -> Unit {
  let id = text(p, "id")
  let on = [("station", address), ("id", id)]
  let quota = field(p, "quota")
  let refreshing = is_doing(core, ["profile.quota"], on)
  let ago = text(field(field(quota, "time"), "checkedAt"), "ago")
  @sf.section(
    c,
    @sf.t("web-pages.profiles.quota"),
    title_after?=if ago != "" {
      Some(fn() { @sf.about(c, "profile-quota-about/" + address + "/" + id, @sf.t("web-pages.profiles.quotaAbout", args=[("ago", ago)]), label=@sf.t("web-main.about")) })
    } else {
      None
    },
    actions=fn() {
      if @sf.button(c, @sf.t("web-pages.profiles.refresh"), key="profile-quota/" + address + "/" + id, tone=Ghost, icon="refresh", busy=refreshing) {
        @settings.act(core, @sf.t("web-pages.profiles.refresh"), "profile.quota", obj([("station", str(address)), ("id", str(id))]))
      }
    },
    fn() {
      let windows = items(quota, "windows")
      let credits = text(quota, "creditsText")
      if quota is (None | Some(Null)) {
        c.text(@sf.t("web-main.quota.unchecked"), style=desk_muted) |> ignore
      } else if text(quota, "state") != "ok" || windows.length() == 0 {
        if credits == "" {
          c.text(
            match opt_text(quota, "detail") {
              Some(d) => d
              None => @sf.t("web-main.quota.unknown")
            },
            style=desk_muted,
          )
          |> ignore
        }
      } else {
        quota_dials(c, windows)
      }
      if credits != "" {
        c.text(@sf.t("web-pages.profiles.credits", args=[("credits", credits)]), style=desk_words) |> ignore
      }
      if has(quota, "resetCount") {
        let busy = is_doing(core, ["profile.resetQuota"], on)
        c.box(style=pf_line, fn() {
          c.text(@sf.t("web-pages.profiles.resets", args=[("resets", text(quota, "resetText"))]), style=desk_words) |> ignore
          if @sf.button(
              c,
              @sf.t("web-pages.profiles.reset"),
              key="profile-reset/" + address + "/" + id,
              tone=Ghost,
              busy~,
              disabled=count(quota, "resetCount") == 0 || busy,
            ) {
            confirm(
              @sf.t("web-pages.profiles.resetConfirm"),
              @sf.t("web-pages.profiles.resetBody", args=[("name", text(p, "name")), ("n", count(quota, "resetCount").to_string())]),
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
        })
        |> ignore
        match failed_of(core, ["profile.resetQuota"], on) {
          Some(f) => c.text(f, style=desk_note_bad) |> ignore
          None => ()
        }
      }
    },
  )
}

///|
/// What it spent in the last 7 days (UsageSection): its cost, calls and tokens as the usage view counts them for it;
/// on several stations, here's alone. The way to the whole usage at its head.
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
      if @sf.button(c, @sf.t("web-pages.profiles.usageAll"), key="profile-usage-all/" + address, tone=Ghost, icon="chart") {
        app.nav.push(Setting(Usage))
      }
    },
    fn() {
      match item {
        Some(_) =>
          c.box(style=ug_tiles, fn() {
            let tile = fn(label : String, value : String, sub : String) {
              c.box(style=ug_tile, fn() {
                c.text(label, style=ug_tile_label) |> ignore
                c.text(value, style=ug_tile_value) |> ignore
                c.text(sub, style=ug_tile_sub) |> ignore
              })
              |> ignore
            }
            tile(@sf.t("web-pages.profiles.usageCost"), text(item, "costText"), @sf.t("web-pages.profiles.usageShare", args=[("share", text(item, "shareText"))]))
            tile(@sf.t("web-pages.profiles.usageCalls"), text(item, "callsText"), @sf.t("web-pages.profiles.usageCallsSub"))
            tile("Tokens", text(item, "tokensText"), @sf.t("web-pages.profiles.usageTokensSub"))
          })
          |> ignore
        None =>
          if flag(field(usage, "wait"), "reading") {
            @sf.wait_line(c, @sf.t("common.reading"))
          } else {
            c.text(@sf.t("web-pages.profiles.usageNone"), style=desk_muted) |> ignore
          }
      }
    },
  )
}

// ── where it is ─────────────────────────────────────────────────────────

///|
/// The same account on several stations (StationsSection): each one's part, its state and who uses it there, leading
/// to its page there.
fn profile_stations(c : @ui.Ctx, core : Core, here_station : String, entry : Json?) -> Unit {
  let t = @sf.theme()
  @sf.section(c, @sf.t("web-pages.profiles.account.each"), fn() {
    c.box(style=desk_list, fn() {
      for m in items(entry, "members") {
        let mv = Some(m)
        let station = text(mv, "station")
        let pid = text(mv, "profileId")
        let id = c.id("profile-station/" + station + "/" + pid)
        let here = station == here_station
        c.cursor(id, Hand)
        if c.clicked(id) && !here {
          place_pick["profiles"] = Profile(station, pid)
          (core.push)(Profile(station, pid))
        }
        c.box(style=if here { desk_list_row.then(@ui.css("bg=Hover")) } else { desk_list_link }, id~, fn() {
          @sf.status_dot(c, if flag(mv, "online") { "online" } else { "offline" })
          c.box(style=desk_list_text, fn() {
            c.text(text(mv, "stationName"), style=desk_list_title) |> ignore
            let used = count(mv, "usedBy")
            c.text(
              join([text(mv, "about"), if used > 0 { @sf.t("web-pages.settings.profiles.usedBy", args=[("n", used.to_string())]) } else { "" }], " · "),
              style=desk_note,
            )
            |> ignore
          })
          |> ignore
          if !flag(mv, "online") {
            @sf.pill(c, @sf.t("web-pages.stations.offline"))
          } else if !flag(mv, "usable") {
            @sf.pill(c, @sf.t("web-pages.settings.profiles.hostAway", args=[("station", text(entry, "hostName"))]), tone=Red)
          } else if text(mv, "checkTone") != "green" {
            @sf.pill(c, text(mv, "checkText"), tone=pill_tone(text(mv, "checkTone")))
          }
          @sf.icon(c, "chevron-right", size=desk_chevron, color=t.p.muted) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
}

///|
/// Sharing it with the workspace's other stations (ShareSection): a switch; once on, where a subscription is signed in
/// (moved from here to another) and which stations may use it. A copy of another station's says whose it is.
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
  if text(share, "role") == "user" {
    @sf.section(c, @sf.t("web-pages.profiles.share.title"), fn() {
      let host = name_of(text(share, "host"))
      c.text(@sf.t("web-pages.profiles.share.copy", args=[("station", host)]), style=desk_words) |> ignore
      match items(entry, "members").search_by(fn(m) { text(Some(m), "stationId") == text(share, "host") && text(Some(m), "role") == "host" }) {
        Some(i) => {
          let lender = Some(items(entry, "members")[i])
          if @sf.button(c, @sf.t("web-pages.profiles.share.goHost", args=[("station", host)]), key="profile-host/" + address + "/" + id, tone=Ghost) {
            (core.push)(Profile(text(lender, "station"), text(lender, "profileId")))
          }
        }
        None => ()
      }
      if subscription && field(share, "reachable") is Some(False) {
        c.text(@sf.t("web-pages.profiles.share.hostAway", args=[("station", host)]), style=desk_note_bad) |> ignore
      }
    })
    return
  }
  let shared = share is Some(Object(_))
  let sharing = is_doing(core, ["profile.share"], on)
  let moving = is_doing(core, ["profile.move"], on)
  let allowed = match field(share, "allow") {
    Some(Array(a)) => Some(a.filter_map(fn(x) { if x is String(v) { Some(v) } else { None } }))
    _ => None
  }
  @sf.section(c, @sf.t("web-pages.profiles.share.title"), fn() {
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
      disabled=sharing,
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
    c.box(style=pf_share_rows, fn() {
      if subscription && !flag(p, "machine") {
        c.box(style=desk_card_row, fn() {
          c.box(style=desk_card_text, fn() { c.text(@sf.t("web-pages.profiles.share.signedIn"), style=desk_strong) |> ignore }) |> ignore
          c.box(style=pf_share_value, fn() {
            @sf.status_dot(c, "online")
            c.text(text(s, "name"), style=desk_note_line) |> ignore
          })
          |> ignore
          let targets = stations.filter(fn(x) { text(Some(x), "id") != sid })
          if @sf.button(
              c,
              @sf.t("web-pages.profiles.share.move"),
              key="profile-move/" + address + "/" + id,
              tone=Ghost,
              busy=moving,
              disabled=moving || targets.length() == 0,
            ) {
            open_dialog(
              "profile-move/" + address + "/" + id,
              @sf.t("web-pages.profiles.share.moveTitle"),
              description=@sf.t("web-pages.profiles.share.moveLead", args=[("station", text(s, "name"))]),
              fn(c, shut) {
                c.box(style=desk_list, fn() {
                  for x in targets {
                    let xv = Some(x)
                    let online = flag(xv, "online")
                    let rid = c.id("profile-move-to/" + text(xv, "id"))
                    if online {
                      c.cursor(rid, Hand)
                      if c.clicked(rid) {
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
                    c.box(style=if online { desk_list_link } else { desk_list_row }, id=if online { rid } else { 0 }, fn() {
                      @sf.status_dot(c, if online { "online" } else { "offline" })
                      c.text(text(xv, "name"), style=desk_list_title) |> ignore
                      if !online {
                        c.text(@sf.t("web-pages.stations.offline"), style=desk_note_line) |> ignore
                      }
                    })
                    |> ignore
                  }
                })
                |> ignore
              },
              fn(_, _) {  },
            )
          }
        })
        |> ignore
      }
      c.box(style=desk_card_row, fn() {
        c.box(style=desk_card_text, fn() {
          c.text(@sf.t("web-pages.profiles.share.stations"), style=desk_strong) |> ignore
          let users = match field(share, "users") {
            Some(Array(u)) => u.filter_map(fn(x) { if x is String(v) { Some(name_of(v)) } else { None } })
            _ => []
          }
          if users.length() > 0 {
            c.text(@sf.t("web-pages.profiles.share.users", args=[("stations", users.join(@sf.t("web-main.list.separator")))]), style=desk_muted)
            |> ignore
          }
        })
        |> ignore
        let names = match allowed {
          None => @sf.t("web-pages.profiles.share.everyStation")
          Some(a) =>
            stations
            .filter(fn(x) { a.contains(text(Some(x), "id")) || text(Some(x), "id") == sid })
            .map(fn(x) { text(Some(x), "name") })
            .join(@sf.t("web-main.list.separator"))
        }
        c.text(names, style=desk_note_line) |> ignore
        if @sf.button(c, @sf.t("web-pages.profiles.share.change"), key="profile-share-pick/" + address + "/" + id, tone=Ghost, disabled=sharing) {
          pick_stations(core, address, id, stations, sid, allowed)
        }
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// Which stations may use a share (PickStations): every one (those to come too), or those ticked; the one that has it
/// always.
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
    "profile-pick/" + address + "/" + id,
    @sf.t("web-pages.profiles.share.stations"),
    fn(c, _) {
      c.text(if all() { @sf.t("web-pages.profiles.share.futureIn") } else { @sf.t("web-pages.profiles.share.futureOut") }, style=desk_muted) |> ignore
      c.box(style=desk_list, fn() {
        for x in stations {
          let xv = Some(x)
          let xid = text(xv, "id")
          let self = xid == own
          c.box(style=desk_list_row, fn() {
            let on = self || ticked.get(xid).unwrap_or(false)
            let now = @kit.checkbox(c, "profile-pick/" + xid, if on { On } else { Off }, label=text(xv, "name"), disabled=self).value
            if !self && (now == On) != on {
              ticked[xid] = now == On
            }
            @sf.status_dot(c, if flag(xv, "online") { "online" } else { "offline" })
            c.text(text(xv, "name"), style=desk_list_title) |> ignore
            if self {
              c.text(@sf.t("web-pages.profiles.share.here"), style=desk_note_line) |> ignore
            }
          })
          |> ignore
        }
      })
      |> ignore
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
        disabled=busy,
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
}

// ── how it runs ─────────────────────────────────────────────────────────

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
    c.box(style=pf_run_rows, fn() { profile_run_rows(c, address, id, p, fast, background, busy, put) }) |> ignore
    match failed_of(core, ["profile.put"], on) {
      Some(f) => c.text(f, style=desk_note_bad) |> ignore
      None => ()
    }
  })
}

///|
/// Its switches, one under the other.
fn profile_run_rows(
  c : @ui.Ctx,
  address : String,
  id : String,
  p : Json?,
  fast : Bool,
  background : Bool,
  busy : Bool,
  put : (String, String, Bool, String) -> Unit,
) -> Unit {
  if fast {
    let now = flag(p, "fast")
    let next = @sf.switch_row(c, "profile-fast/" + address + "/" + id, @sf.t("web-pages.profiles.fast"), now, note=@sf.t("web-pages.profiles.fastLead"), disabled=busy)
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
      disabled=busy,
    )
    if next != now {
      put(@sf.t("web-pages.profiles.background"), "backgroundOnMessage", next, if next { @sf.t("web-pages.profiles.turnedOn") } else { @sf.t("web-pages.profiles.turnedOff") })
    }
  }
}

///|
/// Its models (ModelPool): what it can be used for now, as chips; the whole list to tick (by series, a filter when many,
/// all or none), each tick saved at once; one named by hand where the provider lists none. A provider that answers the
/// automatic decisions alone: the models its probe found.
fn profile_models(c : @ui.Ctx, core : Core, address : String, p : Json?) -> Unit {
  let id = text(p, "id")
  let key = address + "/" + id
  if flag(p, "decisionOnly") {
    @sf.section(c, @sf.t("web-pages.profiles.decisionModels"), fn() {
      let found = strings(p, "decisionModels")
      if found.length() > 0 {
        c.box(style=pf_chips, fn() {
          for m in found {
            c.box(style=pf_chip, fn() { c.text(m, style=pf_chip_words) |> ignore }) |> ignore
          }
        })
        |> ignore
      }
      if text(p, "decisionText") != "" {
        c.text(text(p, "decisionText"), style=desk_muted) |> ignore
      }
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
    title_after=fn() {
      @sf.about(
        c,
        "profile-models-about/" + key,
        if all.length() > 0 { @sf.t("web-pages.profiles.modelsAbout") } else { @sf.t("web-pages.profiles.modelsAboutNone") },
        label=@sf.t("web-main.about"),
      )
    },
    actions=fn() {
      if all.length() > 0 &&
        @sf.button(
          c,
          if choosing {
            @sf.t("web-pages.profiles.collapse")
          } else {
            @sf.t("web-pages.profiles.chooseModels", args=[("on", enabled.length().to_string()), ("all", all.length().to_string())])
          },
          key="profile-choose/" + key,
          tone=Ghost,
        ) {
        profile_edit.choosing = if choosing { "-" + key } else { key }
      }
    },
    fn() {
      c.box(style=pf_models_body, fn() {
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
            c.text(@sf.t("web-pages.profiles.noModels"), style=desk_muted) |> ignore
          } else {
            c.box(style=pf_chips, fn() {
              for m in on {
                c.box(style=pf_chip, fn() {
                  @sf.maker_mark(c, text(field(field(p, "makers"), m), "id"), text(p, "runtime"), pf_chip_glyph) |> ignore
                  c.text(name(m), style=pf_chip_words) |> ignore
                })
                |> ignore
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
      })
      |> ignore
    },
  )
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
  let commit = fn(next : Array[String]) {
    let sorted = next.copy()
    sorted.sort()
    @settings.act(
      core,
      @sf.t("web-pages.profiles.models"),
      "profile.put",
      obj([("station", str(address)), ("id", str(id)), ("input", obj([("models", Json::array(sorted.map(str)))]))]),
    )
  }
  c.box(style=pf_pool, fn() {
    c.box(style=pf_pool_tools, fn() {
      if all.length() > 10 {
        c.box(style=pf_pool_filter, fn() {
          @sf.input(c, "profile-filter/" + key, placeholder=@sf.t("web-pages.profiles.filter"), field=filter) |> ignore
        })
        |> ignore
      }
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
            c.box(style=pf_pool_item, fn() {
              let now = @kit.checkbox(c, "profile-model/" + key + "/" + m, if on { On } else { Off }, label=name(m), disabled=busy).value
              if (now == On) != on {
                commit(if on { enabled.filter(fn(x) { x != m }) } else { enabled.copy()..push(m) })
              }
              @sf.maker_mark(c, text(field(field(p, "makers"), m), "id"), text(p, "runtime"), pf_chip_glyph) |> ignore
              c.text(name(m), style=pf_chip_words) |> ignore
              if saving.contains(m) {
                @sf.spinner(c, size=pf_spin) |> ignore
              }
              match found {
                Some(f) if !f.contains(m) => c.text(@sf.t("web-pages.profiles.gone"), style=pf_gone) |> ignore
                _ => ()
              }
            })
            |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// A quiet word that does something (controls.css.ts textToggle): muted, the words' ink under the pointer.
fn text_toggle(c : @ui.Ctx, key : String, words : String, disabled : Bool) -> Bool {
  let id = c.id(key)
  if !disabled {
    c.cursor(id, Hand)
  }
  let b = c.box(style=pf_toggle, id=if disabled { 0 } else { id }, fn() {
    c.text(words, style=if c.hovered(id) && !disabled { pf_toggle_lit } else { pf_toggle_words }) |> ignore
  })
  c.semantics(b, Button, id~, label=words, disabled~)
  !disabled && c.clicked(id)
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
      if @sf.input(c, "profile-add-model/" + address + "/" + id, placeholder=@sf.t("web-pages.profiles.addModelPlaceholder"), field=f).submitted {
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

///|
/// Who uses it (its connects), each its page.
fn profile_used_by(c : @ui.Ctx, core : Core, address : String, o : Json?, p : Json?) -> Unit {
  let users = strings(p, "usedBy").filter_map(fn(uid) {
    match items(o, "connects").search_by(fn(cn) { text(Some(cn), "id") == uid }) {
      Some(i) => Some(items(o, "connects")[i])
      None => None
    }
  })
  @sf.section(c, @sf.t("web-pages.profiles.usedBy"), fn() {
    if users.length() == 0 {
      c.text(@sf.t("web-pages.profiles.usedByNone"), style=desk_muted) |> ignore
      return
    }
    c.box(style=desk_list, fn() {
      for cn in users {
        let cv = Some(cn)
        let id = c.id("profile-user/" + address + "/" + text(cv, "id"))
        c.cursor(id, Hand)
        if c.clicked(id) {
          (core.push)(Connect(address, text(cv, "id")))
        }
        c.box(style=desk_list_link, id~, fn() {
          @sf.avatar(c, text(cv, "id"), text(cv, "name"), "", pf_user_avatar)
          c.text(text(cv, "name"), style=desk_list_title) |> ignore
          let model = match opt_text(cv, "modelName") {
            Some(m) => m
            None =>
              match opt_text(p, "model") {
                Some(m) => match text(field(p, "names"), m) { "" => m; n => n }
                None => @sf.t("web-pages.profiles.defaultModel")
              }
          }
          c.text(model, style=st_end_words) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
}

// ── the account ─────────────────────────────────────────────────────────

///|
/// A profile on the machine's own login (MachineAccount): whose it is, changed on the machine.
fn profile_machine_account(c : @ui.Ctx, s : Json?, p : Json?) -> Unit {
  let runtime = @settings.runtime_label(text(p, "runtime"))
  @sf.section(c, @sf.t("web-pages.profiles.account"), fn() {
    c.box(style=pf_line, fn() {
      c.text(
        if text(s, "name") != "" {
          @sf.t("web-pages.profiles.machineLoginOn", args=[("station", text(s, "name")), ("runtime", runtime)])
        } else {
          @sf.t("web-pages.profiles.machineLoginHere", args=[("runtime", runtime)])
        },
        style=desk_words,
      )
      |> ignore
      @sf.about(c, "profile-machine-about/" + text(p, "id"), @sf.t("web-pages.profiles.machineLoginAbout", args=[("runtime", runtime)]), label=@sf.t("web-main.about"))
    })
    |> ignore
  })
}

///|
/// The account itself (AccountSection): its key masked (replaced here: a new key, its address where the provider is
/// the person's own), or a subscription signed in again.
fn profile_account(c : @ui.Ctx, core : Core, address : String, p : Json?, signed_in : Bool) -> Unit {
  let id = text(p, "id")
  let key = address + "/" + id
  let access = field(p, "access")
  let kind = text(access, "kind")
  let keyed = ["opencode-go", "anthropic-api", "api-provider"].contains(kind) && !flag(access, "login")
  if !keyed && kind != "subscription" && !flag(access, "login") {
    return
  }
  if !keyed && !signed_in {
    return
  }
  @sf.section(c, @sf.t("web-pages.profiles.account"), fn() {
    if !keyed {
      profile_sign_in(c, core, address, p, false)
      return
    }
    let label = if kind == "opencode-go" {
      "OpenCode Go key"
    } else if text(p, "providerName") != "" {
      text(p, "providerName") + " key"
    } else {
      "API key"
    }
    let has_endpoint = has(access, "endpoint")
    c.box(style=desk_card, fn() {
      if profile_edit.replacing != key {
        c.box(style=desk_card_row, fn() {
          c.box(style=desk_card_text, fn() {
            c.text(label, style=desk_strong) |> ignore
            c.rich(
              [@ui.span(if text(access, "key") != "" { text(access, "key") } else { @sf.t("web-pages.profiles.notSaved") }, mono=true)],
              style=desk_muted,
            )
            |> ignore
            if text(access, "endpoint") != "" {
              c.rich([@ui.span(text(access, "endpoint"), mono=true)], style=desk_muted) |> ignore
            }
          })
          |> ignore
          if @sf.button(c, @sf.t("web-pages.profiles.replace"), key="profile-replace/" + key, busy=is_doing(core, ["profile.put"], [("station", address), ("id", id)])) {
            profile_edit.replacing = key
            profile_field("endpoint/" + key).set(text(access, "endpoint"))
            profile_field("key/" + key).set("")
          }
        })
        |> ignore
        return
      }
      let endpoint = profile_field("endpoint/" + key)
      let new_key = profile_field("key/" + key)
      if has_endpoint {
        @sf.field(c, @sf.t("common.provider.endpoint"), fn() { @sf.input(c, "profile-endpoint/" + key, field=endpoint) |> ignore })
      }
      @sf.field(
        c,
        if kind == "opencode-go" { @sf.t("web-pages.profiles.newOpencodeKey") } else { @sf.t("web-pages.profiles.newApiKey") },
        hint=@sf.t("web-pages.profiles.recheckHint"),
        fn() {
          c.box(style=pf_input_row, fn() {
            c.box(style=pf_input_grow, fn() {
              @sf.input(c, "profile-key/" + key, placeholder=@sf.t("web-pages.profiles.pasteKey"), secret=true, field=new_key) |> ignore
            })
            |> ignore
            let typed = new_key.text().trim(chars=" \t\n").to_owned()
            let at = endpoint.text().trim(chars=" \t\n").to_owned()
            let changed = typed != "" || (has_endpoint && at != text(access, "endpoint"))
            if @sf.button(c, @sf.t("common.cancel"), key="profile-replace-cancel/" + key, tone=Ghost) {
              profile_edit.replacing = ""
            }
            if @sf.button(c, @sf.t("common.save"), key="profile-replace-save/" + key, tone=Primary, disabled=!changed) {
              let acc = [("kind", str(kind))]
              if typed != "" {
                acc.push(("key", str(typed)))
              }
              if has_endpoint {
                acc.push(("endpoint", str(at)))
              }
              profile_edit.replacing = ""
              @settings.act(
                core,
                @sf.t("web-pages.profiles.replace"),
                "profile.put",
                obj([("station", str(address)), ("id", str(id)), ("input", obj([("access", obj(acc))]))]),
                done=@sf.t("web-pages.profiles.savedChecking"),
              )
            }
          })
          |> ignore
        },
      )
    })
    |> ignore
  })
}

///|
/// The variables a custom profile runs with (EnvSection): a row each, its name and its value (a secret's kept masked
/// until it is written anew), deleted or added; saved as what changed (a name gone or renamed: null).
fn profile_env(c : @ui.Ctx, core : Core, address : String, p : Json?) -> Unit {
  let id = text(p, "id")
  let key = address + "/" + id
  let env = items(p, "env")
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
  let busy = is_doing(core, ["profile.put"], [("station", address), ("id", id)])
  @sf.section(c, @sf.t("web-pages.profiles.env"), note=@sf.t("web-pages.profiles.envLead", args=[("route", "{route}")]), fn() {
    c.box(style=desk_card, fn() {
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
      c.box(style=st_card_actions, fn() {
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
      |> ignore
    })
    |> ignore
  })
}

// ── styles (pages.css.ts identity, Accounts.css.ts) ─────────────────────

///|
let pf_mark_glyph : Double = 26.0

///|
let pf_tag_glyph : Double = 12.0

///|
let pf_chip_glyph : Double = 14.0

///|
let pf_spin : Double = 14.0

///|
let pf_user_avatar : Double = 24.0

///|
/// Who the account is (identity: its mark 48, its words beside it, 16 apart, 28 over what follows).
// kept across runs: a value (no field of it changes)
let pf_head : @ui.Style = @ui.css("row w=Full pt=S10 pb=S7 gap=S4 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pf_mark : @ui.Style = @ui.css("w=S12 h=S12 radius=Lg bg=Neutral align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let pf_identity : @ui.Style = @ui.style(w=@sf.grow, gap=S1_5)

///|
// kept across runs: a value (no field of it changes)
let pf_name_line : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pf_name : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Semibold, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let pf_sub : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, w=Full)

///|
/// What its last check said, cut short where its line has less.
// kept across runs: a value (no field of it changes)
let pf_check_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, wrap=false, w=Cut)

///|
/// What leaves its check's line first, short of room: when it was checked.
let pf_drop_checked : Int = 1

///|
// kept across runs: a value (no field of it changes)
let pf_sub_quiet : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Subtle, wrap=false)

///|
/// Its state under its name (profileState: 8 apart).
// kept across runs: a value (no field of it changes)
let pf_state : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
/// The runtimes' tags (runtimeTags: 4 apart, 8 after the name; a tag 18 high, 5 in, round 5, the hover's ground).
// kept across runs: a value (no field of it changes)
let pf_tags : @ui.Style = @ui.css("row pl=S2 gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pf_tag : @ui.Style = @ui.css("row h=S4_5 px=S1 gap=SPx align=ACenter radius=Base bg=Hover")

///|
// kept across runs: a value (no field of it changes)
let pf_tag_words : @ui.TextStyle = @ui.text_style(size=Xs2, leading=L4, weight=Medium, color=Muted, wrap=false)

///|
/// A card's buttons at its foot (cardFoot).
// kept across runs: a value (no field of it changes)
let pf_card_foot : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pf_wait_line : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
/// A sign-in's step (steps: its words over what is done in it).
// kept across runs: a value (no field of it changes)
let pf_step : @ui.Style = @ui.css("w=Full gap=S2 align=AStart")

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
let pf_device_code_words : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Semibold, color=Fg, wrap=false)

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
// kept across runs: a value (no field of it changes)
let pf_chips : @ui.Style = @ui.css("row w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let pf_chip : @ui.Style = @ui.css("row px=S2_5 py=S1 gap=S1_5 align=ACenter radius=Full bg=Hover")

///|
// kept across runs: a value (no field of it changes)
let pf_chip_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Fg, wrap=false)

///|
/// The list to tick (modelPool): its tools (a filter, all, none), each series' head and its models.
// kept across runs: a value (no field of it changes)
let pf_pool : @ui.Style = @ui.css("w=Full gap=S3")

///|
// kept across runs: a value (no field of it changes)
let pf_pool_tools : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pf_pool_filter : @ui.Style = @ui.css("w=S60")

///|
// kept across runs: a value (no field of it changes)
let pf_series : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let pf_series_head : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pf_series_name : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pf_pool_list : @ui.Style = @ui.css("w=Full gap=SPx")

///|
// kept across runs: a value (no field of it changes)
let pf_pool_item : @ui.Style = @ui.css("row w=Full py=S1 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pf_gone : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let pf_toggle : @ui.Style = @ui.css("px=S1")

///|
// kept across runs: a value (no field of it changes)
let pf_toggle_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, weight=Medium, color=Muted, wrap=false)

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
/// Choosing a new profile's models (PickModelsPage), the step chats need once it is added: the whole list to tick, one
/// named by hand where the provider lists none; 跳过 or 完成 (once one is on) to its page. While its list is read, said
/// so; none to list, why.
fn pick_models_page(c : @ui.Ctx, core : Core, here : Here, address : String, id : String) -> Unit {
  let s = @settings.station_of(core, here, address)
  let o = field(s, "overview")
  let key = "pick-models/" + address + "/" + id
  let title = @sf.t("web-pages.profiles.pickModels.title")
  guard o is Some(Object(_)) else {
    desk_page(c, core, key, title, [
      fn() { @sf.waiting(c, shape=Cards, note={ reading: true, text: @sf.t("web-pages.profiles.loading"), failing: [] }) },
    ])
  }
  guard items(o, "profiles").search_by(fn(p) { text(Some(p), "id") == id }) is Some(i) else {
    desk_page(c, core, key, title, [
      fn() { c.text(@sf.t("web-pages.profiles.notFound", args=[("id", id)]), style=desk_muted) |> ignore },
    ])
  }
  let p = Some(items(o, "profiles")[i])
  // on to its page, in this one's place
  let leave = fn() {
    (core.pop)()
    (core.push)(Profile(address, id))
  }
  let listed = items(p, "available").length() > 0
  let check = field(p, "check")
  desk_page(
    c,
    core,
    key,
    title,
    lead=@sf.t("web-pages.profiles.pickModels.lead", args=[("name", text(p, "name"))]),
    actions=fn() {
      c.box(style=pf_pick_actions, fn() {
        if @sf.button(c, @sf.t("web-pages.profiles.pickModels.skip"), key=key + "/skip", tone=Ghost) {
          leave()
        }
        if @sf.button(c, @sf.t("common.done"), key=key + "/done", tone=Primary, disabled=items(p, "models").length() == 0) {
          leave()
        }
      })
      |> ignore
    },
    [
      fn() {
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
          c.box(style=pf_models_body, fn() {
            if listed {
              model_checklist(c, core, address, p)
            }
            if flag(p, "canAddModel") {
              add_model(c, core, address, id)
            }
          })
          |> ignore
        }
        match failed_of(core, ["profile.put"], [("station", address), ("id", id)]) {
          Some(f) => c.text(f, style=desk_note_bad) |> ignore
          None => ()
        }
      },
    ],
  )
}

///|
/// Its two buttons at the head's end (pickModelsActions: 8 apart).
// kept across runs: a value (no field of it changes)
let pf_pick_actions : @ui.Style = @ui.css("row gap=S2 align=ACenter")
