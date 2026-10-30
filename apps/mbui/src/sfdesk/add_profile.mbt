// A new profile on the desktop, on a page of its own (ember web/src/pages/AddProfile.tsx, AddProfile.css.ts): the
// providers in their groups, then how to connect the one picked (its plan or a key) and the form. What is picked and
// typed, and what each step says, is the core's (`profileFlow`, `profile.flow.*`); this draws it. Which online
// station it is added on is chosen at its head; the machine's own logins not used yet are offered first.

///|
/// Where the add page of a station begins, when it is come to with a provider and how (the web's addProfilePath with
/// its provider and `method`), until its draft is opened.
// kept across runs: said by the pages that lead to it; add_profile_reset empties it
let add_profile_start : Map[String, Array[(String, Json)]] = {}

///|
fn add_profile_reset() -> Unit {
  add_profile_start.clear()
}

///|
/// The add page (AddProfile), on station `address` (another online one where it is not: the first).
fn add_profile_page(c : @ui.Ctx, core : Core, here : Here, address : String) -> Unit {
  let back = "Profile"
  guard @settings.stations_of(core, here).value is Some(Array(list)) else {
    desk_page(c, core, "add-profile", @sf.t("android-settings.profile.add"), back~, [
      fn() { @sf.waiting(c, fn() { providers_sample(c) }, text=@sf.t("common.readingStations")) },
    ])
  }
  let online = list.filter(fn(s) { flag(Some(s), "online") })
  let chosen = match online.search_by(fn(s) { text(Some(s), "station") == address }) {
    Some(i) => Some(online[i])
    None => online.get(0)
  }
  match chosen {
    Some(s) => add_profile_flow(c, core, Some(s), online)
    // none online to add it on: back to the list
    None => {
      c.tell("add-profile-none", fn() { (core.pop)() })
      desk_page(c, core, "add-profile", @sf.t("android-settings.profile.add"), back~, [])
    }
  }
}

///|
/// The add flow on one station (Flow): its draft opened as the page is (another station: another draft), the step the
/// core is at drawn, a plan's sign-in started when it is chosen; added, on to choosing its models.
fn add_profile_flow(c : @ui.Ctx, core : Core, s : Json?, online : Array[Json]) -> Unit {
  let station = text(s, "station")
  let n = @settings.new_profile_of(station)
  let form = n.form
  if !n.opened.get() {
    n.opened.set(true)
    // (once the frame's builds are over: the build that first comes to it alone)
    c.tell("add-profile-open/" + form, fn() {
      @settings.act(core, @sf.t("web-pages.addProfile.openAction"), "profile.flow.open", obj([("station", str(station)), ("form", str(form))]))
      // come from elsewhere to a provider and how (a machine's login signed in again as its plan): said at once
      match add_profile_start.get(station) {
        Some(input) => {
          add_profile_start.remove(station)
          @settings.act(
            core,
            @sf.t("web-pages.addProfile.editAction"),
            "profile.flow.edit",
            obj([("station", str(station)), ("form", str(form)), ("input", obj(input))]),
          )
        }
        None => ()
      }
    })
  }
  let topic = (core.topic)("profileFlow", { "station": str(station), "form": str(form) })
  let d = topic.value
  let edit = fn(input : Array[(String, Json)]) {
    @settings.act(
      core,
      @sf.t("web-pages.addProfile.editAction"),
      "profile.flow.edit",
      obj([("station", str(station)), ("form", str(form)), ("input", obj(input))]),
    )
  }
  let key = "add-profile/" + form
  guard d is Some(Object(_)) else {
    desk_page(c, core, key, @sf.t("android-settings.profile.add"), back="Profile", [fn() { @sf.waiting(c, fn() { providers_sample(c) }) }])
  }
  let step = text(d, "step")
  // what a plan signs in to (the core's, at its connect step); a runtime to install first (`install`), the sign-in after
  let sign = field(d, "signIn")
  let install = field(d, "install")
  let plan = step == "connect" && text(d, "method") == "plan"
  let planning = plan && !(install is Some(Object(_))) && sign is Some(Object(_))
  if planning && !n.asked.get() {
    // (start_login says it asked)
    c.tell("add-profile-login/" + form, fn() {
      @settings.start_login(core, station, n, text(sign, "runtime"), text(sign, "access"))
    })
  }
  if !planning && n.asked.get() {
    // left unfinished: let go
    @settings.drop_login(core, station, n)
  }
  let pending = if n.login.get() == "" { None } else { @settings.pending_login(core, station, n.login.get()) }
  // the sign-in made its profile: on to choosing its models (PickModels), in this page's place
  match opt_text(pending, "created") {
    Some(id) => {
      n.login.set("")
      (core.say)(@sf.t("web-pages.profiles.signedInAdded"))
      (core.in_place)(PickModels(station, id))
    }
    None => ()
  }
  let picking = step == "pick"
  let blocks : Array[() -> Unit] = []
  if picking {
    if online.length() > 1 {
      blocks.push(fn() { add_profile_stations(c, station, online) })
    }
    blocks.push(fn() { machine_offers(c, core, s, fn(rt) { edit([("provider", str(if rt == "claude" { "anthropic" } else { "openai" })), ("method", str("plan"))]) }) })
    for g in items(d, "groups") {
      blocks.push(fn() { provider_group(c, Some(g), fn(id) { edit([("provider", str(id))]) }) })
    }
  } else if step == "method" {
    blocks.push(fn() { connect_methods(c, d, fn(id) { edit([("method", str(id))]) }) })
  } else if plan {
    blocks.push(fn() {
      if install is Some(Object(_)) {
        install_step(c, core, station, install)
      } else {
        let job = field(pending, "job")
        let state = text(job, "state")
        if n.error.get() != "" || state == "failed" || state == "cancelled" {
          c.box(style=ap_form, fn() {
            let why = if n.error.get() != "" {
              n.error.get()
            } else {
              match opt_text(job, "error") {
                Some(e) => e
                None => @sf.t("web-pages.profiles.signInUnfinished")
              }
            }
            c.text(why, style=desk_note_bad) |> ignore
            if @sf.button(c, @sf.t("web-pages.profiles.restart"), key="add-profile-restart/" + form) {
              // let go, then asked again as the step is drawn
              @settings.drop_login(core, station, n)
            }
          })
          |> ignore
        } else {
          c.box(style=ap_form, fn() {
            login_steps(
              c,
              core,
              "new/" + form,
              job,
              text(sign, "provider"),
              is_doing(core, ["login.code"], [("station", station), ("id", n.login.get())]),
              fn(code, sent) {
                if n.login.get() != "" {
                  @settings.act(
                    core,
                    @sf.t("web-pages.profiles.finish"),
                    "login.code",
                    obj([("station", str(station)), ("id", str(n.login.get())), ("code", str(code))]),
                    then=fn(_) { sent() },
                  )
                }
              },
              in_station=(text(s, "name"), is_doing(core, ["login.browser"], [("station", station), ("id", n.login.get())]), fn(what) {
                if n.login.get() != "" {
                  @settings.act(core, what, "login.browser", obj([("station", str(station)), ("id", str(n.login.get()))]), then=fn(v) {
                    (core.open_screen)(station, text(Some(v), "screen"))
                  })
                }
              }),
            )
          })
          |> ignore
        }
      }
      if text(d, "usesLine") != "" {
        c.box(style=ap_uses_below, fn() { c.text(text(d, "usesLine"), style=desk_muted) |> ignore }) |> ignore
      }
    })
  } else {
    blocks.push(fn() { connect_form(c, core, station, n, d, edit) })
  }
  desk_page(
    c,
    core,
    key + "/" + step,
    text(d, "title"),
    lead=text(d, "hint"),
    back=if picking { "Profile" } else { @sf.t("web-pages.addProfile.pick") },
    // back over it always (BackLink): to the list, or the step before
    on_back=fn() {
      if picking {
        (core.pop)()
      } else {
        @settings.drop_login(core, station, n)
        edit([("provider", str(""))])
      }
    },
    blocks,
  )
}

///|
/// Which station it is added on (its online ones, a segment each): another is another draft.
fn add_profile_stations(c : @ui.Ctx, station : String, online : Array[Json]) -> Unit {
  let at = match online.search_by(fn(s) { text(Some(s), "station") == station }) {
    Some(i) => i
    None => 0
  }
  c.box(style=ap_stations, fn() {
    @sf.field(c, @sf.t("web-pages.addProfile.station"), fn() {
      let now = @sf.segmented(c, "add-profile-station", online.map(fn(s) { text(Some(s), "name") }), at)
      if now != at {
        app.nav.replace(Setting(NewProfile(text(Some(online[now]), "station"))))
      }
    })
  })
  |> ignore
}

///|
/// The providers to pick from while they are read (the library's Waiting, in its bones): two groups of made-up ones,
/// as provider_group draws them.
fn providers_sample(c : @ui.Ctx) -> Unit {
  for g in [(4, 3), (5, 5)] {
    let providers = Array::makei(g.1, fn(i) {
      Json::object({ "id": Json::string("sample" + i.to_string()), "name": Json::string(@sf.sample_words(4 + i % 3)) })
    })
    provider_group(c, Some({ "title": Json::string(@sf.sample_words(g.0)), "providers": Json::array(providers) }), fn(_) {  })
  }
}

///|
/// A group of providers under its small heading (group, groupHead, tiles: three a row, 4 apart; a tile its mark and
/// its name, flat, the hover's ground).
fn provider_group(c : @ui.Ctx, g : Json?, pick : (String) -> Unit) -> Unit {
  let providers = items(g, "providers")
  c.box(style=ap_group, fn() {
    c.text(text(g, "title"), style=ap_group_head) |> ignore
    c.box(style=ap_tiles, fn() {
      let rows = (providers.length() + 2) / 3
      for r in 0..<rows {
        c.box(style=ap_tile_row, fn() {
          for k in 0..<3 {
            let i = r * 3 + k
            if i >= providers.length() {
              c.box(style=ap_tile_room, fn() {  }) |> ignore
              continue
            }
            let pv = Some(providers[i])
            let id = c.id("add-profile-provider/" + text(pv, "id"))
            if c.clicked(id) {
              pick(text(pv, "id"))
            }
            let b = c.box(style=ap_tile, id~, fn() {
              c.box(style=ap_tile_mark, fn() {
                @sf.provider_logo(
                  c,
                  match text(pv, "runtime") {
                    "" => "claude"
                    rt => rt
                  },
                  match text(pv, "kind") {
                    "" => "api-provider"
                    k => k
                  },
                  ap_tile_glyph,
                  text(pv, "mark"),
                )
              })
              |> ignore
              c.text(text(pv, "name"), style=ap_tile_name) |> ignore
            })
            c.semantics(b, Button, id~, label=text(pv, "name"))
          }
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The two ways to connect a vendor that has both (methods: side by side, 12 apart; each its title and what it is, on
/// paper, the hover's ground).
fn connect_methods(c : @ui.Ctx, d : Json?, choose : (String) -> Unit) -> Unit {
  c.box(style=ap_methods, fn() {
    for ch in items(d, "choices") {
      let cv = Some(ch)
      let id = c.id("add-profile-method/" + text(cv, "id"))
      if c.clicked(id) {
        choose(text(cv, "id"))
      }
      let b = c.box(style=ap_method, id~, fn() {
        c.text(text(cv, "title"), style=desk_strong) |> ignore
        c.text(text(cv, "hint"), style=desk_muted) |> ignore
      })
      c.semantics(b, Button, id~, label=text(cv, "title"))
    }
  })
  |> ignore
}

///|
/// The form of a key (ConnectForm): where the provider is (its example as the placeholder), its region and protocol
/// where it has a choice, the key (a secret's field: its hint, or what is wrong with it); 验证并添加, made only if it
/// works (`profile.flow.submit`). What is typed is told to the core as it is typed.
fn connect_form(
  c : @ui.Ctx,
  core : Core,
  station : String,
  n : @settings.NewProfile,
  d : Json?,
  edit : (Array[(String, Json)]) -> Unit,
) -> Unit {
  let form = n.form
  let pending = flag(d, "pending")
  let endpoint = profile_field("add-endpoint/" + form)
  let key = profile_field("add-key/" + form)
  if !n.filled.get() {
    n.filled.set(true)
    endpoint.set(text(d, "endpoint"))
    n.endpoint.set(text(d, "endpoint"))
  }
  let submitting = is_doing(core, ["profile.flow.submit"], [("station", station), ("form", form)])
  let submit = fn() {
    if flag(d, "canSubmit") && !submitting {
      (core.call)("profile.flow.submit", obj([("station", str(station)), ("form", str(form))]), fn(r) {
        match r {
          Ok(v) => {
            (core.say)(@sf.t("web-pages.profiles.verifiedAdded"))
            (core.in_place)(PickModels(station, text(Some(v), "id")))
          }
          // (what is wrong is the draft's own `error`, under the key)
          Err(_) => ()
        }
      })
    }
  }
  c.box(style=ap_form, fn() {
    if flag(d, "showEndpoint") {
      @sf.field(c, @sf.t("common.provider.endpoint"), hint=text(d, "endpointHint"), fn() {
        let typed = @sf.input(
          c,
          "add-profile-endpoint/" + form,
          placeholder=match text(d, "endpointExample") {
            "" => "https://"
            x => x
          },
          disabled=pending,
          field=endpoint,
        )
        if endpoint.text() != n.endpoint.get() {
          n.endpoint.set(endpoint.text())
          edit([("endpoint", str(n.endpoint.get()))])
        }
        if typed.submitted {
          submit()
        }
      })
    }
    let regions = items(d, "regions")
    if regions.length() > 1 {
      @sf.field(c, @sf.t("web-pages.addProfile.region"), fn() {
        let at = match regions.search_by(fn(r) { text(Some(r), "id") == text(d, "region") }) {
          Some(i) => i
          None => 0
        }
        let now = @sf.segmented(c, "add-profile-region/" + form, regions.map(fn(r) { text(Some(r), "label") }), at)
        if now != at {
          edit([("region", str(text(Some(regions[now]), "id")))])
        }
      })
    }
    let protocols = items(d, "protocols")
    if protocols.length() > 1 {
      @sf.field(c, @sf.t("web-pages.addProfile.protocol"), fn() {
        @sf.select(
          c,
          "add-profile-protocol/" + form,
          text(d, "protocol"),
          protocols.map(fn(p) { (text(Some(p), "id"), text(Some(p), "label")) }),
          fn(now) {
            if now != text(d, "protocol") {
              edit([("protocol", str(now))])
            }
          },
          label=@sf.t("web-pages.addProfile.protocol"),
          disabled=pending,
        )
      })
    }
    if flag(d, "showKey") {
      @sf.field(c, text(d, "keyLabel"), hint=text(d, "keyHint"), error=text(d, "error"), fn() {
        let typed = @sf.input(c, "add-profile-key/" + form, secret=true, disabled=pending, field=key)
        if key.text() != n.key.get() {
          n.key.set(key.text())
          edit([("key", str(n.key.get()))])
        }
        if typed.submitted {
          submit()
        }
      })
    }
    c.box(style=ap_submit, fn() {
      if @sf.button(
          c,
          text(d, "submitLabel"),
          key="add-profile-submit/" + form,
          tone=Primary,
          icon=if flag(d, "showKey") { "" } else { "plus" },
          busy=submitting || pending,
          disabled=!flag(d, "canSubmit"),
        ) {
        submit()
      }
    })
    |> ignore
    if text(d, "usesLine") != "" {
      c.text(text(d, "usesLine"), style=desk_muted) |> ignore
    }
  })
  |> ignore
}

///|
/// A plan's sign-in on a station without the runtime it signs in with (InstallStep, the core's `install`): installing
/// it first, how that stands, its button where the viewer may (`software.update`); the sign-in starts once it is.
fn install_step(c : @ui.Ctx, core : Core, station : String, install : Json?) -> Unit {
  let runtime = text(install, "runtime")
  let busy = is_doing(core, ["software.update"], [("station", station), ("id", runtime)])
  c.box(style=desk_card, fn() {
    c.box(style=desk_card_text, fn() {
      c.text(text(install, "title"), style=desk_strong) |> ignore
      match opt_text(install, "detail") {
        Some(why) => c.text(why, style=desk_note_bad) |> ignore
        None =>
          c.text(
            match opt_text(install, "note") {
              Some(x) => x
              None => @sf.t("web-pages.profiles.installThenSignIn")
            },
            style=desk_muted,
          )
          |> ignore
      }
    })
    |> ignore
    if text(install, "state") == "installing" {
      @sf.progress(c, "add-profile/install", if has(install, "percent") && !(field(install, "percent") is Some(Null)) { Some(number(install, "percent") / 100.0) } else { None })
    }
    match opt_text(install, "action") {
      Some(action) =>
        // (last on its card: its button in its foot corner, concentric with it)
        c.box(style=pf_card_foot.then(@sf.foot_reach(@sf.button_height())), fn() {
          if @sf.button(c, action, key="add-profile-install/" + runtime, tone=Primary, busy~) {
            @settings.act(core, action, "software.update", obj([("station", str(station)), ("id", str(runtime))]))
          }
        })
        |> ignore
      None => ()
    }
  })
  |> ignore
}

///|
/// The accounts this machine's own Claude Code and Codex are signed in with, not used yet (MachineLoginOffers): one
/// kept in a file used as it is (a profile on the machine's login, `profile.useMachineLogin`), one kept only in the
/// keychain offered as a sign-in with the same account (`sign_in`, by its runtime). A refused one is said so.
fn machine_offers(c : @ui.Ctx, core : Core, s : Json?, sign_in : (String) -> Unit) -> Unit {
  let station = text(s, "station")
  let offers = items(field(s, "overview"), "machineLogins").filter(fn(l) { flag(Some(l), "offered") })
  if offers.length() == 0 {
    return
  }
  c.box(style=ap_offers, fn() {
    c.text(
      @sf.t("web-pages.profiles.machineSignedIn", args=[("station", if text(s, "name") != "" { text(s, "name") } else { @sf.t("web-main.machine.this") })]),
      style=ap_group_head,
    )
    |> ignore
    for l in offers {
      let lv = Some(l)
      let rt = text(lv, "runtime")
      let quota = field(lv, "quota")
      let blocked = text(quota, "state") == "blocked"
      // a card of the ladder's: its mark, words and quota in a row 20 in, its button across its foot corners
      c.box(style=if blocked { ap_offer } else { ap_offer_footed_style() }, fn() {
        c.box(style=ap_offer_head, fn() {
        c.box(style=ap_offer_mark, fn() { @sf.provider_logo(c, rt, "subscription", ap_offer_glyph, "") }) |> ignore
        // (short of room, its name kept: whether it is signed in leaves its line first, then its plan)
        c.box(style=desk_list_text, keep=true, fn() {
          c.box(style=pf_name_line, fn() {
            c.text(@settings.runtime_label(rt), style=desk_list_title) |> ignore
            if text(lv, "planText") != "" {
              c.box(style=pf_tag, drop=ap_drop_plan, fn() { c.text(text(lv, "planText"), style=pf_tag_words) |> ignore })
              |> ignore
            }
            c.box(style=ap_pill_slot, drop=ap_drop_state, fn() {
              @sf.pill(
                c,
                if blocked { @sf.t("web-main.profile.blocked") } else { @sf.t("web-main.profile.machineSignedIn") },
                tone=if blocked { Red } else { Green },
              )
            })
            |> ignore
          })
          |> ignore
          c.text(if text(lv, "email") != "" { text(lv, "email") } else { @sf.t("web-main.profile.signedIn") }, style=desk_note_line)
          |> ignore
          // why it cannot be used (what the provider said)
          if blocked || text(quota, "state") == "unavailable" {
            c.text(text(quota, "detail"), style=if blocked { desk_note_bad } else { desk_note }) |> ignore
          }
        })
        |> ignore
        @sf.quota_chips(c, quota, small=true, key="add-profile-machine/" + rt)
        })
        |> ignore
        if !blocked {
          let busy = is_doing(core, ["profile.useMachineLogin"], [("station", station), ("runtime", rt)])
          let reach = @sf.foot_across(@sf.button_height())
          if flag(lv, "usable") {
            if @sf.button(c, @sf.t("web-pages.profiles.useThis"), key="add-profile-machine/" + rt, busy~, w=Fill(1.0), reach~, hint=@sf.t("web-pages.profiles.useMachineTip")) {
              (core.call)("profile.useMachineLogin", obj([("station", str(station)), ("runtime", str(rt))]), fn(r) {
                match r {
                  Ok(v) => {
                    (core.say)(@sf.t("web-pages.profiles.machineAdded"))
                    (core.in_place)(PickModels(station, text(Some(v), "id")))
                  }
                  Err(e) => (core.say)(@settings.error_text(e))
                }
              })
            }
          } else if @sf.button(c, @sf.t("web-pages.profiles.signIn"), key="add-profile-machine/" + rt, w=Fill(1.0), reach~, hint=@sf.t("web-pages.profiles.keychainTip", args=[("name", "still.fail")])) {
            sign_in(rt)
          }
        }
      })
      |> ignore
    }
  })
  |> ignore
}

// ── styles (AddProfile.css.ts) ─────────────────────────────────────────

///|
let ap_tile_glyph : Double = 16.0

///|
let ap_offer_glyph : Double = 18.0

///|
/// The station it is added on (stations: 24 over what follows).
// kept across runs: a value (no field of it changes)
let ap_stations : @ui.Style = @ui.css("w=Full pb=S6")

///|
/// A group of providers (group: 28 under it; its heading 8 over its tiles).
// kept across runs: a value (no field of it changes)
let ap_group : @ui.Style = @ui.css("w=Full pb=S7 gap=S2")

///|
// kept across runs: a value (no field of it changes)
let ap_group_head : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=Muted, w=Full)

///|
/// Its tiles, three a row, 4 apart, their ground out to the column's sides (outset 12).
// kept across runs: a value (no field of it changes)
let ap_tiles : @ui.Style = @sf.outset(desk_list_out).then(@ui.css("gap=S1"))

///|
// kept across runs: a value (no field of it changes)
let ap_tile_row : @ui.Style = @ui.css("row w=Full gap=S1")

///|
/// A provider (tile: its mark and its name, 10 by 12 in, 12 apart, flat; the hover's ground).
// kept across runs: a value (no field of it changes)
let ap_tile : @ui.Style = @ui.style(w=@sf.grow).then(@ui.css("row px=S3 py=S2_5 gap=S3 align=ACenter radius=Lg hovered{bg=Hover}"))

///|
// kept across runs: a value (no field of it changes)
let ap_tile_room : @ui.Style = @ui.style(w=@sf.grow)

///|
/// Its mark in a 28 square (pages.css.ts mark).
// kept across runs: a value (no field of it changes)
let ap_tile_mark : @ui.Style = @ui.css("w=S7 h=S7 radius=Base bg=Neutral align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let ap_tile_name : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, wrap=false)

///|
/// The two ways to connect (methods: side by side, 12 apart; method: 18 in, 6 apart, on paper, the hover's ground).
// kept across runs: a value (no field of it changes)
let ap_methods : @ui.Style = @ui.css("row w=Full gap=S3 align=AStretch")

///|
// kept across runs: a value (no field of it changes)
let ap_method : @ui.Style = @ui.style(w=@sf.grow).then(@ui.css("p=S4_5 gap=S1_5 radius=Xl3 bg=Card hovered{bg=Hover}"))

///|
/// The form (form: 18 apart).
// kept across runs: a value (no field of it changes)
let ap_form : @ui.Style = @ui.css("w=Full gap=S4_5")

///|
// kept across runs: a value (no field of it changes)
let ap_submit : @ui.Style = @ui.css("row w=Full")

///|
/// What it will be usable for, under a plan's steps (usesBelow: 14 apart from them).
// kept across runs: a value (no field of it changes)
let ap_uses_below : @ui.Style = @ui.css("w=Full pt=S3_5")

///|
/// The machine's own logins (machineLogins: 4 apart, its heading over them).
// kept across runs: a value (no field of it changes)
let ap_offers : @ui.Style = @ui.css("w=Full pb=S7 gap=S1")

///|
/// A login of the machine's own (machineLogin): a card of the ladder's, its words 20 in, its mark in its top corner
/// (round by the ladder's there: mbui works it out), its button across its foot corners (@sf.card_foot_in).
// kept across runs: a value (no field of it changes)
let ap_offer : @ui.Style = @ui.css("w=Full p=S5 gap=S3 radius=Xl3 bg=Card")

///|
/// With its button: its foot as far in as makes the button concentric with its corner (the theme's button height).
fn ap_offer_footed_style() -> @ui.Style {
  ap_offer.then(@sf.foot_pad(@sf.button_height()))
}

///|
// kept across runs: a value (no field of it changes)
let ap_offer_head : @ui.Style = @ui.css("row w=Full gap=S3 align=AStart")

///|
/// An offer's mark: 32 on the neutral ground, on the card's words' inset in its corner, the ladder's small block's
/// corner there (10).
// kept across runs: a value (no field of it changes)
let ap_offer_mark : @ui.Style = @ui.css("w=S8 h=S8 bg=Neutral align=ACenter justify=JCenter").then(
  @ui.style(radius=@sf.small_radius),
)

///|
/// What leaves a machine's login's line first, short of room: whether it is signed in, then its plan.
let ap_drop_state : Int = 1

///|
let ap_drop_plan : Int = 2

///|
/// Its state's pill, whole on the line.
// kept across runs: a value (no field of it changes)
let ap_pill_slot : @ui.Style = @ui.css("row")
