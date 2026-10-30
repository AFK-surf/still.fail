// A new profile on a station (Profiles.kt NewProfileScreen), as the core's add flow has it (`profileFlow`): the
// providers by group, then how to connect the one picked: a plan signed in (`login.new`, its steps relayed here, the
// profile made by the station once it is signed in), or a key checked first (`profile.flow.submit`: the profile made
// only if it works). And an account on several stations (ProfileAccountScreen).

///|
/// The new-profile pages open, by station: the draft's form, the sign-in it started (none: ""), why that failed.
pub(all) struct NewProfile {
  form : String
  opened : @signals.Signal[Bool]
  dropped : @signals.Signal[Bool]
  login : @signals.Signal[String]
  asked : @signals.Signal[Bool]
  error : @signals.Signal[String]
  key : @signals.Signal[String]
  endpoint : @signals.Signal[String]
  filled : @signals.Signal[Bool]
}

///|
let new_profiles : @sf.LiveMap[String, NewProfile] = @sf.LiveMap::new()

///|
/// A count of drafts opened.
pub let profile_forms : @signals.Signal[Int] = @signals.signal(0, same=fn(a, b) { a == b })

///|
/// The draft of a new profile's page, made the first time it is drawn.
pub fn new_profile_of(station : String) -> NewProfile {
  match new_profiles.get(station) {
    Some(n) if !n.dropped.get() => n
    _ => {
      profile_forms.set(profile_forms.get() + 1)
      let n = {
        form: "mbui-profile-" + profile_forms.get().to_string(),
        opened: @signals.signal(false, same=fn(a, b) { a == b }),
        dropped: @signals.signal(false, same=fn(a, b) { a == b }),
        login: @signals.signal(""),
        asked: @signals.signal(false, same=fn(a, b) { a == b }),
        error: @signals.signal(""),
        key: @signals.signal("", same=fn(a, b) { a == b }),
        endpoint: @signals.signal("", same=fn(a, b) { a == b }),
        filled: @signals.signal(false, same=fn(a, b) { a == b }),
      }
      new_profiles.set(station, n)
      n
    }
  }
}

///|
/// The page left: its draft dropped (`profile.flow.drop`), and a sign-in it started that made no profile let go
/// (`login.drop`: nothing left behind).
fn new_profile_left(core : Core, station : String) -> Unit {
  match new_profiles.get(station) {
    Some(n) if !n.dropped.get() => {
      n.dropped.set(true)
      drop_login(core, station, n)
      (core.call)("profile.flow.drop", obj([("station", str(station)), ("form", str(n.form))]), fn(_) {  })
    }
    _ => ()
  }
}

///|
/// The sign-in a new profile's page started let go, unless it made its profile.
pub fn drop_login(core : Core, station : String, n : NewProfile) -> Unit {
  if n.login.get() != "" {
    let made = match pending_login(core, station, n.login.get()) {
      Some(l) => has(Some(l), "created")
      None => false
    }
    if !made {
      (core.call)("login.drop", obj([("station", str(station)), ("id", str(n.login.get()))]), fn(_) {  })
    }
    n.login.set("")
  }
  n.asked.set(false)
}

///|
/// A sign-in under way on a station, by its id (its overview's `logins`).
pub fn pending_login(core : Core, station : String, id : String) -> Json? {
  let all = (core.topic)("stations", { "scope": str(workspace_of(station)) }).value
  match all {
    Some(Array(a)) =>
      match a.iter().find_first(fn(s) { text(Some(s), "station") == station }) {
        Some(s) => items(field(Some(s), "overview"), "logins").iter().find_first(fn(l) { text(Some(l), "id") == id })
        None => None
      }
    _ => None
  }
}

///|
/// A plan's sign-in started for the page (`login.new` with what it signs in to).
pub fn start_login(core : Core, station : String, n : NewProfile, runtime : String, access : String) -> Unit {
  n.asked.set(true)
  n.error.set("")
  let p = [("station", str(station)), ("runtime", str(runtime))]
  if access != "" {
    p.push(("access", str(access)))
  }
  (core.call)("login.new", obj(p), fn(r) {
    match r {
      Ok(v) =>
        n.login.set(match v {
          String(id) => id
          _ => text(Some(v), "id")
        })
      Err(e) => n.error.set(error_text(e))
    }
  })
}

///|
/// A new profile on station `station` (NewProfileScreen).
fn new_profile_page(c : @ui.Ctx, core : Core, here : Here, station : String) -> Unit {
  let t = @sf.theme()
  let n = new_profile_of(station)
  let form = n.form
  if !n.opened.get() {
    n.opened.set(true)
    // (opened once the frame's builds are over: the build that first comes to it alone)
    c.tell("profile-open/" + form, fn() {
      act(core, tr("web-pages.addProfile.openAction"), "profile.flow.open", obj([("station", str(station)), ("form", str(form))]))
    })
  }
  let s = station_of(core, here, station)
  let topic = (core.topic)("profileFlow", { "station": str(station), "form": str(form) })
  let d = topic.value
  let edit = fn(input : Array[(String, Json)]) {
    act(core, tr("web-pages.addProfile.editAction"), "profile.flow.edit", obj([("station", str(station)), ("form", str(form)), ("input", obj(input))]))
  }
  let step = text(d, "step")
  let sign = field(d, "signIn")
  let tile = field(d, "tile")
  // what the plan signs in to (the core's, at a plan's connect step): a runtime's subscription, or another account
  let runtime = text(sign, "runtime")
  let provider = text(sign, "provider")
  // a station without the runtime the plan signs in with installs it first (`install`): the sign-in starts after
  let install = field(d, "install")
  let planning = step == "connect" && text(d, "method") == "plan" && !(install is Some(Object(_))) && sign is Some(Object(_))
  // a plan's sign-in starts when it is chosen
  if planning && !n.asked.get() {
    // (once the frame's builds are over; start_login says it asked)
    c.tell("profile-login/" + form, fn() { start_login(core, station, n, runtime, text(sign, "access")) })
  }
  let pending = if n.login.get() == "" { None } else { pending_login(core, station, n.login.get()) }
  // the sign-in made its profile: on to it, in this page's place
  match opt_text(pending, "created") {
    Some(id) => {
      n.login.set("")
      (core.say)(tr("android-settings.profile.addedLogin"))
      // on to choosing its models (PickModels), the step chats need
      (core.in_place)(PickModels(station, id))
    }
    None => ()
  }
  let leave = fn() {
    if d is Some(_) && step != "pick" {
      drop_login(core, station, n)
      edit([("provider", str(""))])
    } else {
      (core.pop)()
    }
  }
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    if d is Some(_) && step != "pick" {
      c.on_back(leave)
    }
    // (Profiles.kt NewProfileScreen: NavBar, under the status bar, its title in the middle)
    nav_bar(
      c,
      core,
      tr(if d is Some(_) && step != "pick" { "web-mobile.profiles.pick" } else { "common.cancel" }),
      match opt_text(d, "title") {
        Some(x) => x
        None => tr("android-settings.profile.add")
      },
      sub=fn() { c.text(text(s, "name"), size=t.t.caption, color=t.p.muted, wrap=false, line=16.0) |> ignore },
      on_back=leave,
    )
    guard d is Some(Object(_)) else {
      waiting_cards(
        c,
        fn() {
          for g in [(4, 3), (5, 5)] {
            let providers = Array::makei(g.1, fn(i) {
              Json::object({ "id": Json::string("sample" + i.to_string()), "name": Json::string(@sf.sample_words(4 + i % 3)) })
            })
            pick_group(c, Some({ "title": Json::string(@sf.sample_words(g.0)), "providers": Json::array(providers) }), fn(_) {  })
          }
        },
        error=match topic.error {
          Some(e) => error_text(e)
          None => ""
        },
      )
      return
    }
    let blocks : Array[() -> Unit] = []
    // (as far in as every page's blocks: the page's room, 12; it stood 18 in, its cards beside others' 12)
    let pad = fn(f : () -> Unit) { c.box(style=new_profile_pad, f) |> ignore }
    let group_box = fn(f : () -> Unit) { rows_card(c, f) }
    if step == "pick" {
      blocks.push(fn() {
        pad(fn() { c.text(text(d, "hint"), size=t.t.meta, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore })
      })
      // the machine's own logins not used yet: a profile on one needs no sign-in
      for b in machine_login_offers(c, core, s, inset=12.0, fn(rt) {
          edit([("provider", str(if rt == "claude" { "anthropic" } else { "openai" })), ("method", str("plan"))])
        }) {
        blocks.push(b)
      }
      for g in items(d, "groups") {
        blocks.push(fn() { pick_group(c, Some(g), fn(id) { edit([("provider", str(id))]) }) })
      }
    } else if step == "method" {
      blocks.push(fn() {
        pad(fn() {
          group_box(fn() {
            for ch in items(d, "choices") {
              let cv = Some(ch)
              let cid = text(cv, "id")
              let kind = if cid == "plan" &&
                text(tile, "kind") != "opencode-go" &&
                text(tile, "id") != "moonshotai" {
                "subscription"
              } else {
                match text(tile, "kind") {
                  "" => "api-provider"
                  k => k
                }
              }
              if @sf.choice_row(c, "method/" + cid, false, text(cv, "title"), note=text(cv, "hint"), lead=fn() {
                  @sf.provider_logo(c, runtime, kind, 18.0, text(tile, "mark"))
                }) {
                edit([("method", str(cid))])
              }
            }
          })
        })
      })
    } else if step == "connect" && text(d, "method") == "plan" && install is Some(Object(_)) {
      blocks.push(fn() { pad(fn() { install_step(c, core, station, install) }) })
    } else if planning {
      blocks.push(fn() {
        pad(fn() {
          let job = field(pending, "job")
          let state = text(job, "state")
          if n.error.get() != "" || state == "failed" || state == "cancelled" {
            c.text(
              if n.error.get() != "" {
                n.error.get()
              } else {
                match opt_text(job, "error") {
                  Some(e) => e
                  None => tr("android-settings.login.unfinished")
                }
              },
              size=t.t.meta,
              color=t.p.red,
              w=Fill(1.0),
              line=18.0,
            )
            |> ignore
            if @sf.button(c, tr("android-settings.login.restart"), key="login-restart") {
              drop_login(core, station, n)
            }
          } else {
            login_steps(
              c,
              core,
              station + "/new/" + n.login.get(),
              job,
              provider,
              fn(code) {
                if n.login.get() != "" {
                  act(core, tr("android-settings.login.finish"), "login.code", obj([("station", str(station)), ("id", str(n.login.get())), ("code", str(code))]))
                }
              },
              in_station=(text(s, "name"), fn(what) {
                if n.login.get() != "" {
                  act(core, what, "login.browser", obj([("station", str(station)), ("id", str(n.login.get()))]), then=fn(v) {
                    (core.open_screen)(station, text(Some(v), "screen"))
                  })
                }
              }),
            )
          }
          if text(d, "usesLine") != "" {
            c.text(text(d, "usesLine"), size=t.t.meta, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
          }
        })
      })
    } else {
      blocks.push(fn() { pad(fn() { connect_form(c, core, station, n, d, edit) }) })
    }
    blocks.push(fn() { gap(c, 30.0) })
    c.box(w=Fill(1.0), h=Fill(1.0), fn() { scroll_page(c, "new-profile/" + form + "/" + step, blocks) }) |> ignore
  })
  |> ignore
}

///|
/// The form of a key (ConnectForm): where the provider is, its region and protocol where it has a choice, the key (a
/// secret's field), what is wrong with it; 验证并添加 (`profile.flow.submit`: made only if it works).
fn connect_form(
  c : @ui.Ctx,
  core : Core,
  station : String,
  n : NewProfile,
  d : Json?,
  edit : (Array[(String, Json)]) -> Unit,
) -> Unit {
  let t = @sf.theme()
  let form = n.form
  let label = fn(words : String) {
    c.text(words, size=t.t.meta, weight=600, color=t.p.text, w=Fill(1.0), line=18.0) |> ignore
  }
  let group_box = fn(f : () -> Unit) { rows_card(c, f) }
  let ekey = "profile-endpoint/" + form
  if !n.filled.get() {
    n.filled.set(true)
    field_of(ekey).set(text(d, "endpoint"))
    n.endpoint.set(text(d, "endpoint"))
  }
  if flag(d, "showEndpoint") {
    label(tr("common.provider.endpoint"))
    let endpoint = field_box(c, ekey, match text(d, "endpointExample") {
      "" => "https://"
      x => x
    }).trim(chars=" ").to_owned()
    if endpoint != n.endpoint.get() {
      n.endpoint.set(endpoint)
      edit([("endpoint", str(endpoint))])
    }
    match opt_text(d, "endpointHint") {
      Some(h) => c.text(h, size=t.t.caption, color=t.p.muted, w=Fill(1.0), line=17.0) |> ignore
      None => ()
    }
  }
  let regions = items(d, "regions")
  if regions.length() > 1 {
    label(tr("web-mobile.profiles.region"))
    group_box(fn() {
      for r in regions {
        if @sf.choice_row(c, "region/" + text(Some(r), "id"), text(Some(r), "id") == text(d, "region"), text(Some(r), "label")) {
          edit([("region", str(text(Some(r), "id")))])
        }
      }
    })
  }
  let protocols = items(d, "protocols")
  if protocols.length() > 1 {
    label(tr("web-mobile.profiles.protocol"))
    group_box(fn() {
      for p in protocols {
        if @sf.choice_row(c, "protocol/" + text(Some(p), "id"), text(Some(p), "id") == text(d, "protocol"), text(Some(p), "label")) {
          edit([("protocol", str(text(Some(p), "id")))])
        }
      }
    })
  }
  if flag(d, "showKey") {
    label(text(d, "keyLabel"))
    let key = field_box(c, "profile-key/" + form, tr("android-settings.profile.keyPlaceholder"), secret=true)
    if key != n.key.get() {
      n.key.set(key)
      edit([("key", str(key))])
    }
    let note = match opt_text(d, "error") {
      Some(e) => Some((e, true))
      None =>
        match opt_text(d, "keyHint") {
          Some(h) => Some((h, false))
          None => None
        }
    }
    match note {
      Some((words, bad)) => c.text(words, size=t.t.caption, color=if bad { t.p.red } else { t.p.muted }, w=Fill(1.0), line=17.0) |> ignore
      None => ()
    }
  }
  let submitting = is_doing(core, ["profile.flow.submit"], [("station", station), ("form", form)])
  c.box(dir=Row, w=Fill(1.0), justify=JEnd, fn() {
    if @sf.button(c, text(d, "submitLabel"), key="profile-submit", tone=Primary, busy=submitting || flag(d, "pending"), disabled=!flag(d, "canSubmit")) {
      c.blur()
      (core.call)("profile.flow.submit", obj([("station", str(station)), ("form", str(form))]), fn(r) {
        match r {
          Ok(v) => {
            (core.say)(tr("android-settings.profile.verifiedAdded"))
            (core.in_place)(PickModels(station, text(Some(v), "id")))
          }
          // (what is wrong is the draft's own `error`, under the key)
          Err(_) => ()
        }
      })
    }
  })
  |> ignore
  if text(d, "usesLine") != "" {
    c.text(text(d, "usesLine"), size=t.t.meta, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
  }
}

///|
/// A group of providers under its title, a row each; pressed, `pick` with its id.
fn pick_group(c : @ui.Ctx, g : Json?, pick : (String) -> Unit) -> Unit {
  let t = @sf.theme()
  c.box(style=pick_group_room, fn() {
    c.box(w=Fill(1.0), pl=6.0, pt=6.0, fn() {
      c.text(text(g, "title"), size=t.t.meta, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
    })
    |> ignore
    rows_card(c, fn() {
      for p in items(g, "providers") {
        let pv = Some(p)
        if list_row(c, key="provider/" + text(pv, "id"), fn() {
            @sf.provider_logo(
              c,
              match text(pv, "runtime") {
                "" => "claude"
                r => r
              },
              match text(pv, "kind") {
                "" => "api-provider"
                k => k
              },
              18.0,
              text(pv, "mark"),
            )
            row_title(c, text(pv, "name"))
            chevron(c)
          }) {
          pick(text(pv, "id"))
        }
      }
    })
  })
  |> ignore
}

///|
/// A group in the page's room (the pick step's pad: 18 in, 8 under what is over it, its parts 12 apart).
// kept across runs: a value (no field of it changes)
let pick_group_room : @ui.Style = @ui.css("w=Full px=S3 pt=S2 gap=S3")

///|
/// A block of a new profile's page, as far in as the page's room (12), 8 under what is over it.
// kept across runs: a value (no field of it changes)
let new_profile_pad : @ui.Style = @ui.css("w=Full px=S3 pt=S2 gap=S3")

///|
/// An account on several stations (ProfileAccountScreen): what they have in common, then each station's part, each
/// leading to its page there.
fn profile_account_page(c : @ui.Ctx, core : Core, here : Here, key : String) -> Unit {
  let t = @sf.theme()
  let topic = (core.topic)("profiles", { "scope": str(here.workspace) })
  let e = items(topic.value, "items").iter().find_first(fn(x) { text(Some(x), "key") == key })
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    match e {
      None => {
        nav_bar(c, core, "Profile", "Profile")
        if topic.value is Some(_) {
          place_empty(c, tr("android-settings.profile.none"))
        } else {
          waiting_cards(
            c,
            fn() {
              let ev = Some(account_sample())
              for b in account_blocks(c, core.quiet(), ev) {
                b()
              }
            },
            error=match topic.error {
              Some(x) => error_text(x)
              None => ""
            },
          )
        }
      }
      Some(ev) => {
        let ev = Some(ev)
        let p = field(ev, "profile")
        nav_bar(c, core, "Profile", text(p, "name"), sub=fn() {
          c.text(
            join(
              [
                text(p, "email"),
                text(p, "kindText"),
              ],
              " · ",
            ),
            size=t.t.caption,
            color=t.p.muted,
            wrap=false,
            line=16.0,
          )
          |> ignore
        })
        let blocks = account_blocks(c, core, ev)
        blocks.push(fn() { gap(c, 30.0) })
        scroll_page(c, "profile-account/" + key, blocks)
      }
    }
  })
  |> ignore
}

///|
/// What an account on several stations (`ev`, its entry) holds: how it is, its allowance, each station's part.
fn account_blocks(c : @ui.Ctx, core : Core, ev : Json?) -> Array[() -> Unit] {
  let t = @sf.theme()
  let p = field(ev, "profile")
  let station = text(ev, "station")
  let blocks : Array[() -> Unit] = [
    fn() { gap(c, 16.0) },
    fn() {
      list_card(c, fn() {
        list_row(c, fn() {
          c.box(w=Fill(1.0), fn() {
            c.box(dir=Row, gap=6.0, align=ACenter, fn() {
              presence_dot(c, tone_dot(text(p, "checkTone")))
              c.text(text(p, "checkText"), size=t.t.ui, color=t.p.text, wrap=false, line=21.0) |> ignore
            })
            |> ignore
            c.text(
              match opt_text(field(p, "check"), "detail") {
                Some(x) => x
                None => tr("android-settings.profile.notChecked")
              },
              size=t.t.meta,
              color=t.p.muted,
              w=Fill(1.0),
              line=18.0,
            )
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
    },
  ]
  blocks.append(quota_section(c, core, station, p))
  blocks.push(fn() { section_header(c, tr("web-pages.profiles.account.each"), start=S6) })
  blocks.push(fn() {
    list_card(c, fn() {
      // the stations it is signed in on: one borrowing it has nothing of its own to set
      for m in items(ev, "members").filter(fn(m) { text(Some(m), "role") != "user" }) {
        let mv = Some(m)
        if list_row(c, key="account-member/" + text(mv, "station") + "/" + text(mv, "profileId"), fn() {
            c.box(w=Fill(1.0), fn() {
              c.box(dir=Row, gap=6.0, align=ACenter, fn() {
                presence_dot(
                  c,
                  if !flag(mv, "online") {
                    "offline"
                  } else if !flag(mv, "usable") {
                    "error"
                  } else {
                    tone_dot(text(mv, "checkTone"))
                  },
                )
                c.text(text(mv, "title"), size=t.t.ui, color=t.p.text, wrap=false, line=21.0) |> ignore
              })
              |> ignore
              c.text(
                if flag(mv, "online") {
                  text(mv, "about")
                } else {
                  tr("android-settings.profiles.stationOffline")
                },
                size=t.t.meta,
                color=t.p.muted,
                w=Fill(1.0),
                line=18.0,
              )
              |> ignore
            })
            |> ignore
            chevron(c)
          }) {
          (core.push)(Profile(text(mv, "station"), text(mv, "profileId")))
        }
      }
    })
  })
  blocks
}

///|
/// An account made up, for what its page shows while it is read (account_blocks in its bones): on two stations.
fn account_sample() -> Json {
  let member = fn(i : Int) -> Json {
    {
      "station": Json::string("sample/" + i.to_string()),
      "stationName": Json::string(@sf.sample_words(4 + i)),
      "title": Json::string(@sf.sample_words(4 + i)),
      "about": Json::string(@sf.sample_words(12)),
      "online": true,
      "usable": true,
    }
  }
  {
    "station": "sample/0",
    "profile": { "checkText": Json::string(@sf.sample_words(4)), "check": { "detail": Json::string(@sf.sample_words(14)) } },
    "members": [member(0), member(1)],
  }
}

///|
/// A plan's sign-in on a station without the runtime it signs in with (InstallStep, core `install`): installing it
/// first, how that stands, its button where the viewer may (`software.update`).
pub fn install_step(c : @ui.Ctx, core : Core, station : String, install : Json?) -> Unit {
  let t = @sf.theme()
  let runtime = text(install, "runtime")
  let busy = is_doing(core, ["software.update"], [("station", station), ("id", runtime)])
  card(c, fn() {
    c.box(w=Fill(1.0), gap=10.0, fn() {
      c.text(text(install, "title"), size=t.t.ui, weight=600, color=t.p.text, w=Fill(1.0), line=21.0) |> ignore
      let detail = opt_text(install, "detail")
      c.text(
        match detail {
          Some(x) => x
          None =>
            match opt_text(install, "note") {
              Some(n) => n
              None => tr("web-pages.profiles.installThenSignIn")
            }
        },
        size=t.t.meta,
        color=if detail is Some(_) { t.p.red } else { t.p.muted },
        w=Fill(1.0),
        line=18.0,
      )
      |> ignore
      if text(install, "state") == "installing" {
        let pct = number(install, "percent")
        c.box(w=Fill(1.0), h=Px(4.0), radius=2.0, bg=t.p.chip, clip=true, fn() {
          c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), fn() {
            if pct > 0.0 {
              c.box(w=Fill(pct), h=Fill(1.0), bg=t.p.accent, fn() {  }) |> ignore
            }
            if pct < 100.0 {
              c.box(w=Fill(100.0 - pct), h=Fill(1.0), fn() {  }) |> ignore
            }
          })
          |> ignore
        })
        |> ignore
      }
      match opt_text(install, "action") {
        Some(action) =>
          if wide_button(c, "install-runtime", action, true, busy~) {
            act(core, action, "software.update", obj([("station", str(station)), ("id", str(runtime))]))
          }
        None => ()
      }
    })
    |> ignore
  })
  |> ignore
}
