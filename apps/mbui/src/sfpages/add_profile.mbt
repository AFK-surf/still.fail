// A new profile, one page in every frame (ember web/src/pages/AddProfile.tsx, AddProfile.css.ts; the narrow app's
// mobile/Profiles.tsx NewProfileScreen, gone from here as a page of its own): the
// providers in their groups, then how to connect the one picked (its plan or a key) and the form. What is picked and
// typed, and what each step says, is the core's (`profileFlow`, `profile.flow.*`); this draws it. Which online
// station it is added on is chosen at its head; the machine's own logins not used yet are offered first.

///|
/// Where the add page of a station begins, when it is come to with a provider and how (the web's addProfilePath with
/// its provider and `method`), until its draft is opened.
// kept across runs: said by the pages that lead to it; add_profile_reset empties it
pub let add_profile_start : Map[String, Array[(String, Json)]] = {}

///|
pub fn add_profile_reset() -> Unit {
  add_profile_start.clear()
}

///|
/// The add page (AddProfile), on station `address` (another online one where it is not: the first).
pub fn add_profile_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame, address : String) -> Unit {
  guard @settings.stations_of(core, here).value is Some(Array(list)) else {
    @sf.page(c, on_back=core.pop, frame~, "add-profile", @sf.t("android-settings.profile.add"), [
      fn() { @sf.waiting(c, shape=Cards, note={ reading: true, text: @sf.t("common.readingStations"), failing: [] }) },
    ])
  }
  let online = list.filter(fn(s) { flag(Some(s), "online") })
  let chosen = match online.search_by(fn(s) { text(Some(s), "station") == address }) {
    Some(i) => Some(online[i])
    None => online.get(0)
  }
  match chosen {
    Some(s) => add_profile_flow(c, core, frame, Some(s), online)
    // none online to add it on: back to the list
    None => {
      c.tell("add-profile-none", fn() { (core.pop)() })
      @sf.page(c, on_back=core.pop, frame~, "add-profile", @sf.t("android-settings.profile.add"), [])
    }
  }
}

///|
/// The add flow on one station (Flow): its draft opened as the page is (another station: another draft), the step the
/// core is at drawn, a plan's sign-in started when it is chosen; added, on to choosing its models.
fn add_profile_flow(c : @ui.Ctx, core : Core, frame : PageFrame, s : Json?, online : Array[Json]) -> Unit {
  let station = text(s, "station")
  let n = @settings.new_profile_of(station)
  let form = n.form
  if !n.opened {
    n.opened = true
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
    @sf.page(c, on_back=core.pop, frame~, key, @sf.t("android-settings.profile.add"), [fn() { @sf.waiting(c, shape=Cards) }])
  }
  let step = text(d, "step")
  // what a plan signs in to (the core's, at its connect step); a runtime to install first (`install`), the sign-in after
  let sign = field(d, "signIn")
  let install = field(d, "install")
  let plan = step == "connect" && text(d, "method") == "plan"
  let planning = plan && !(install is Some(Object(_))) && sign is Some(Object(_))
  if planning && !n.asked {
    // (start_login says it asked)
    c.tell("add-profile-login/" + form, fn() {
      @settings.start_login(core, station, n, text(sign, "runtime"), text(sign, "access"))
    })
  }
  if !planning && n.asked {
    // left unfinished: let go
    @settings.drop_login(core, station, n)
  }
  let pending = if n.login == "" { None } else { @settings.pending_login(core, station, n.login) }
  // the sign-in made its profile: on to choosing its models (PickModels), in this page's place
  match opt_text(pending, "created") {
    Some(id) => {
      n.login = ""
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
    // (on a card, as a page's words are, its buttons its foot: the profile's own sign-in's card, src/sfpages accounts.mbt)
    blocks.push(fn() {
      if install is Some(Object(_)) {
        install_step(c, core, station, install)
      } else {
        let job = field(pending, "job")
        let state = text(job, "state")
        if n.error != "" || state == "failed" || state == "cancelled" {
          let why = if n.error != "" {
            n.error
          } else {
            match opt_text(job, "error") {
              Some(e) => e
              None => ""
            }
          }
          @sf.page_card(c, footed=true, fn() {
            @sf.card_lines(c, @sf.t("web-pages.profiles.signInUnfinished"), bad=why)
            @sf.card_foot(c, fn() {
              if @sf.button(c, @sf.t("web-pages.profiles.restart"), key="add-profile-restart/" + form, tone=Primary) {
                // let go, then asked again as the step is drawn
                @settings.drop_login(core, station, n)
              }
            })
          })
        } else {
          @sf.page_card(c, footed=true, fn() {
            @sf.card_lines(c, @sf.t("web-pages.profiles.signingIn", args=[("provider", text(sign, "provider"))]), note=@sf.t("web-pages.profiles.signingInNote"))
            login_steps(
              c,
              core,
              "new/" + form,
              job,
              text(sign, "provider"),
              is_doing(core, ["login.code"], [("station", station), ("id", n.login)]),
              fn(code, sent) {
                if n.login != "" {
                  @settings.act(
                    core,
                    @sf.t("web-pages.profiles.finish"),
                    "login.code",
                    obj([("station", str(station)), ("id", str(n.login)), ("code", str(code))]),
                    then=fn(_) { sent() },
                  )
                }
              },
              in_station=(text(s, "name"), is_doing(core, ["login.browser"], [("station", station), ("id", n.login)]), fn(what) {
                if n.login != "" {
                  @settings.act(core, what, "login.browser", obj([("station", str(station)), ("id", str(n.login))]), then=fn(v) {
                    (core.open_screen)(station, text(Some(v), "screen"))
                  })
                }
              }),
            )
            // 取消: back to the providers, the sign-in let go (as back does)
            @sf.card_foot(c, fn() {
              if @sf.button(c, @sf.t("common.cancel"), key="add-profile-cancel/" + form, tone=Ghost) {
                @settings.drop_login(core, station, n)
                edit([("provider", str(""))])
              }
            })
          })
        }
      }
    })
    if text(d, "usesLine") != "" {
      blocks.push(fn() { @sf.page_note(c, text(d, "usesLine")) })
    }
  } else {
    blocks.push(fn() { connect_form(c, core, station, n, d, edit) })
  }
  // back over it always (BackLink): to the list, or the step before (named so); the system's back (a swipe, the
  // phone's button) the same, before the pages' (Profiles.kt leave: its BackHandler)
  let frame = if picking { frame } else { { ..frame, back: Some(@sf.t("web-pages.addProfile.pick")) } }
  let back = fn() {
    if picking {
      (core.pop)()
    } else {
      @settings.drop_login(core, station, n)
      edit([("provider", str(""))])
    }
  }
  if !picking {
    c.on_back(back)
  }
  // (the station it is added on, over its title)
  @sf.page(c, key + "/" + step, text(d, "title"), frame~, small=text(s, "name"), lead=text(d, "hint"), on_back=back, blocks)
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
/// A group of providers: a section, a row each (its mark, its whole name), pressed to go on with it.
fn provider_group(c : @ui.Ctx, g : Json?, pick : (String) -> Unit) -> Unit {
  let providers = items(g, "providers")
  let logo = fn(pv : Json?, size : Double) {
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
      size,
      text(pv, "mark"),
    )
  }
  // a row each, its name whole (three tiles abreast cut them on a phone: Anthro…, OpenRou…)
  @sf.section(c, text(g, "title"), fn() {
    @sf.group(c, fn() {
      for p in providers {
        let pv = Some(p)
        if @sf.link_row(c, "add-profile-provider/" + text(pv, "id"), text(pv, "name"), lead=fn() { logo(pv, ap_row_glyph) }) {
          pick(text(pv, "id"))
        }
      }
    })
  })
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
  let tile = field(d, "tile")
  let pending = flag(d, "pending")
  let endpoint = profile_field("add-endpoint/" + form)
  let key = profile_field("add-key/" + form)
  if !n.filled {
    n.filled = true
    endpoint.set(text(d, "endpoint"))
    n.endpoint = text(d, "endpoint")
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
  // (on a card, as a page's words are; 验证并添加 its foot)
  @sf.page_card(c, fn() {
    if flag(d, "showEndpoint") {
      @sf.field(c, @sf.t("common.provider.endpoint"), hint=text(d, "endpointHint"), fn() {
        let typed = @sf.input(
          c,
          "add-profile-endpoint/" + form,
          placeholder=match text(tile, "endpointExample") {
            "" => "https://"
            x => x
          },
          disabled=pending,
          field=endpoint,
        )
        if endpoint.text() != n.endpoint {
          n.endpoint = endpoint.text()
          edit([("endpoint", str(n.endpoint))])
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
        // (what it is for in it till it is typed: checked before it is added)
        let typed = @sf.input(
          c,
          "add-profile-key/" + form,
          placeholder=@sf.t("android-settings.profile.keyPlaceholder"),
          secret=true,
          disabled=pending,
          field=key,
        )
        if key.text() != n.key {
          n.key = key.text()
          edit([("key", str(n.key))])
        }
        if typed.submitted {
          submit()
        }
      })
    }
    @sf.card_foot(c, fn() {
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
  }, footed=true)
  if text(d, "usesLine") != "" {
    @sf.page_note(c, text(d, "usesLine"))
  }
}

///|
/// A plan's sign-in on a station without the runtime it signs in with (InstallStep, the core's `install`): installing
/// it first, how that stands, its button where the viewer may (`software.update`); the sign-in starts once it is.
fn install_step(c : @ui.Ctx, core : Core, station : String, install : Json?) -> Unit {
  let runtime = text(install, "runtime")
  let busy = is_doing(core, ["software.update"], [("station", station), ("id", runtime)])
  let action = opt_text(install, "action")
  // (its button, where the viewer may, its foot)
  @sf.page_card(c, footed=action is Some(_), fn() {
    match opt_text(install, "detail") {
      Some(why) => @sf.card_lines(c, text(install, "title"), bad=why)
      None =>
        @sf.card_lines(c, text(install, "title"), note=match opt_text(install, "note") {
          Some(x) => x
          None => @sf.t("web-pages.profiles.installThenSignIn")
        })
    }
    if text(install, "state") == "installing" {
      @sf.progress(c, "add-profile/install", if has(install, "percent") && !(field(install, "percent") is Some(Null)) { Some(number(install, "percent") / 100.0) } else { None })
    }
    match action {
      Some(action) =>
        @sf.card_foot(c, fn() {
          if @sf.button(c, action, key="add-profile-install/" + runtime, tone=Primary, busy~) {
            @settings.act(core, action, "software.update", obj([("station", str(station)), ("id", str(runtime))]))
          }
        })
      None => ()
    }
  })
}

///|
/// The accounts this machine's own Claude Code and Codex are signed in with, not used yet (MachineLoginOffers): one
/// kept in a file used as it is (a profile on the machine's login, `profile.useMachineLogin`), one kept only in the
/// keychain offered as a sign-in with the same account (`sign_in`, by its runtime). A refused one is said so.
pub fn machine_offers(c : @ui.Ctx, core : Core, s : Json?, sign_in : (String) -> Unit) -> Unit {
  let station = text(s, "station")
  let offers = items(field(s, "overview"), "machineLogins").filter(fn(l) { flag(Some(l), "offered") })
  if offers.length() == 0 {
    return
  }
  let heading = @sf.t("web-pages.profiles.machineSignedIn", args=[("station", if text(s, "name") != "" { text(s, "name") } else { @sf.t("web-main.machine.this") })])
  // a row each, as a provider's below it (the web's narrow MachineLoginOffers: its mark, its name and plan, whether it
  // is signed in and as whom, its quota; 使用此账号 at its end in the link's ink, the row pressed doing it)
  @sf.section(c, heading, fn() {
    @sf.group(c, fn() {
      for l in offers {
        let lv = Some(l)
        let rt = text(lv, "runtime")
        let quota = field(lv, "quota")
        let blocked = text(quota, "state") == "blocked"
        let busy = is_doing(core, ["profile.useMachineLogin"], [("station", station), ("runtime", rt)])
        let usable = flag(lv, "usable")
        let plan = text(lv, "planText")
        let who = if text(lv, "email") != "" { text(lv, "email") } else { @sf.t("web-main.profile.signedIn") }
        // why it cannot be used (what the provider said)
        let detail = if blocked || text(quota, "state") == "unavailable" { text(quota, "detail") } else { "" }
        if @sf.link_row(
            c,
            "add-profile-machine/" + rt,
            @settings.runtime_label(rt) + (if plan != "" { " · " + plan } else { "" }),
            note=(if blocked { @sf.t("web-main.profile.blocked") } else { @sf.t("web-main.profile.machineSignedIn") }) + " · " + who +
              (if !blocked && detail != "" { "\n" + detail } else { "" }),
            trouble=if blocked { detail } else { "" },
            value=if blocked { "" } else if usable { @sf.t("web-pages.profiles.useThis") } else { @sf.t("web-pages.profiles.signIn") },
            value_lit=true,
            chevron=false,
            goes=!blocked,
            lead=fn() { @sf.provider_logo(c, rt, "subscription", ap_row_glyph, "") },
            tail=fn() { @settings.doing_mark(c, busy, None, inline=true) },
            // (its quota under it, where it says one: none, no line kept for it)
            below?=if @sf.has_quota(quota) {
              Some(fn() { @sf.quota_chips(c, quota, small=true, key="add-profile-machine/" + rt) })
            } else {
              None
            },
          ) &&
          !busy {
          if usable {
            (core.call)("profile.useMachineLogin", obj([("station", str(station)), ("runtime", str(rt))]), fn(r) {
              match r {
                Ok(v) => {
                  (core.say)(@sf.t("web-pages.profiles.machineAdded"))
                  (core.in_place)(PickModels(station, text(Some(v), "id")))
                }
                Err(e) => (core.say)(@settings.error_text(e))
              }
            })
          } else {
            sign_in(rt)
          }
        }
      }
    })
  })
}

// ── styles (AddProfile.css.ts) ─────────────────────────────────────────

///|
/// A provider's mark leading its row (narrow: the Kotlin app's 18).
let ap_row_glyph : Double = 18.0

///|
/// The station it is added on (stations: 24 over what follows).
// kept across runs: a value (no field of it changes)
let ap_stations : @ui.Style = @ui.css("w=Full pb=S6")

///|
/// The two ways to connect (methods: side by side, 12 apart; method: 18 in, 6 apart, on paper, the hover's ground).
// kept across runs: a value (no field of it changes)
let ap_methods : @ui.Style = @ui.css("row w=Full gap=S3 align=AStretch")

///|
// kept across runs: a value (no field of it changes)
let ap_method : @ui.Style = @ui.style(w=@sf.grow).then(@ui.css("p=S4_5 gap=S1_5 radius=Xl3 bg=Card hovered{bg=Hover}"))
