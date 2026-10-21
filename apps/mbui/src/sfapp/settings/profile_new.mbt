// A new profile on a station (Profiles.kt NewProfileScreen), as the core's add flow has it (`profileFlow`): the
// providers by group, then how to connect the one picked: a plan signed in (`login.new`, its steps relayed here, the
// profile made by the station once it is signed in), or a key checked first (`profile.flow.submit`: the profile made
// only if it works). And an account on several stations (ProfileAccountScreen).

///|
/// The new-profile pages open, by station: the draft's form, the sign-in it started (none: ""), why that failed.
priv struct NewProfile {
  form : String
  mut opened : Bool
  mut dropped : Bool
  mut login : String
  mut asked : Bool
  mut error : String
  mut key : String
  mut endpoint : String
  mut filled : Bool
}

///|
let new_profiles : Map[String, NewProfile] = Map([])

///|
/// A count of drafts opened.
let profile_forms : Ref[Int] = Ref(0)

///|
/// The draft of a new profile's page, made the first time it is drawn.
fn new_profile_of(station : String) -> NewProfile {
  match new_profiles.get(station) {
    Some(n) if !n.dropped => n
    _ => {
      profile_forms.val += 1
      let n = {
        form: "mbui-profile-" + profile_forms.val.to_string(),
        opened: false,
        dropped: false,
        login: "",
        asked: false,
        error: "",
        key: "",
        endpoint: "",
        filled: false,
      }
      new_profiles[station] = n
      n
    }
  }
}

///|
/// The page left: its draft dropped (`profile.flow.drop`), and a sign-in it started that made no profile let go
/// (`login.drop`: nothing left behind).
fn new_profile_left(core : Core, station : String) -> Unit {
  match new_profiles.get(station) {
    Some(n) if !n.dropped => {
      n.dropped = true
      drop_login(core, station, n)
      (core.call)("profile.flow.drop", obj([("station", str(station)), ("form", str(n.form))]), fn(_) {  })
    }
    _ => ()
  }
}

///|
/// The sign-in a new profile's page started let go, unless it made its profile.
fn drop_login(core : Core, station : String, n : NewProfile) -> Unit {
  if n.login != "" {
    let made = match pending_login(core, station, n.login) {
      Some(l) => has(Some(l), "created")
      None => false
    }
    if !made {
      (core.call)("login.drop", obj([("station", str(station)), ("id", str(n.login))]), fn(_) {  })
    }
    n.login = ""
  }
  n.asked = false
}

///|
/// A sign-in under way on a station, by its id (its overview's `logins`).
fn pending_login(core : Core, station : String, id : String) -> Json? {
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
fn start_login(core : Core, station : String, n : NewProfile, runtime : String, access : String) -> Unit {
  n.asked = true
  n.error = ""
  let p = [("station", str(station)), ("runtime", str(runtime))]
  if access != "" {
    p.push(("access", str(access)))
  }
  (core.call)("login.new", obj(p), fn(r) {
    match r {
      Ok(v) =>
        n.login = match v {
          String(id) => id
          _ => text(Some(v), "id")
        }
      Err(e) => n.error = error_text(e)
    }
  })
}

///|
/// A new profile on station `station` (NewProfileScreen).
fn new_profile_page(c : @ui.Ctx, core : Core, here : Here, station : String) -> Unit {
  let t = @sf.theme()
  let n = new_profile_of(station)
  let form = n.form
  if !n.opened {
    n.opened = true
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
  let runtime = match opt_text(sign, "runtime") {
    Some(r) => r
    None =>
      match text(tile, "runtime") {
        "codex" | "grok" as r => r
        _ => "claude"
      }
  }
  let provider = match opt_text(sign, "provider") {
    Some(p) => p
    None =>
      match runtime {
        "claude" => "Claude"
        "grok" => "Grok"
        _ => "ChatGPT"
      }
  }
  // a station without the runtime the plan signs in with installs it first (`install`): the sign-in starts after
  let install = field(d, "install")
  let planning = step == "connect" && text(d, "method") == "plan" && !(install is Some(Object(_)))
  // a plan's sign-in starts when it is chosen
  if planning && !n.asked {
    // (once the frame's builds are over; start_login says it asked)
    c.tell("profile-login/" + form, fn() { start_login(core, station, n, runtime, text(sign, "access")) })
  }
  let pending = if n.login == "" { None } else { pending_login(core, station, n.login) }
  // the sign-in made its profile: on to it, in this page's place
  match opt_text(pending, "created") {
    Some(id) => {
      n.login = ""
      (core.say)(tr("android-settings.profile.addedLogin"))
      (core.pop)()
      (core.push)(Profile(station, id))
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
    c.box(dir=Row, w=Fill(1.0), pl=10.0, pr=10.0, pt=6.0, pb=4.0, gap=8.0, align=ACenter, fn() {
      if nav_back(c, tr(if d is Some(_) && step != "pick" { "web-mobile.profiles.pick" } else { "common.cancel" })) {
        leave()
      }
      c.box(w=Fill(1.0), align=ACenter, fn() {
        c.text(
          match opt_text(d, "title") {
            Some(x) => x
            None => tr("android-settings.profile.add")
          },
          size=17.0,
          weight=600,
          color=t.p.text,
          wrap=false,
          line=22.0,
        )
        |> ignore
        c.text(text(s, "name"), size=11.0, color=t.p.muted, wrap=false, line=16.0) |> ignore
      })
      |> ignore
      c.box(w=Px(60.0), fn() {  }) |> ignore
    })
    |> ignore
    guard d is Some(Object(_)) else {
      waiting_cards(
        c,
        error=match topic.error {
          Some(e) => error_text(e)
          None => ""
        },
      )
      return
    }
    let blocks : Array[() -> Unit] = []
    let pad = fn(f : () -> Unit) { c.box(w=Fill(1.0), padx=18.0, pt=8.0, gap=12.0, f) |> ignore }
    let group_box = fn(f : () -> Unit) { c.box(w=Fill(1.0), radius=16.0, bg=t.p.card, clip=true, f) |> ignore }
    if step == "pick" {
      blocks.push(fn() {
        pad(fn() { c.text(text(d, "hint"), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore })
      })
      // the machine's own logins not used yet: a profile on one needs no sign-in
      for b in machine_login_offers(c, core, station, field(s, "overview"), inset=18.0, fn(rt) {
          edit([("provider", str(if rt == "claude" { "anthropic" } else { "openai" })), ("method", str("plan"))])
        }) {
        blocks.push(b)
      }
      for g in items(d, "groups") {
        blocks.push(fn() {
          pad(fn() {
            c.box(w=Fill(1.0), pl=6.0, pt=6.0, fn() {
              c.text(text(Some(g), "title"), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
            })
            |> ignore
            group_box(fn() {
              for p in items(Some(g), "providers") {
                let pv = Some(p)
                if list_row(c, key="provider/" + text(pv, "id"), fn() {
                    provider_mark(
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
                  edit([("provider", str(text(pv, "id")))])
                }
              }
            })
          })
        })
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
              if pick_row(c, "method/" + cid, text(cv, "title"), sub=text(cv, "hint"), mark=fn() {
                  provider_mark(c, runtime, kind, 18.0, text(tile, "mark"))
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
          if n.error != "" || state == "failed" || state == "cancelled" {
            c.text(
              if n.error != "" {
                n.error
              } else {
                match opt_text(job, "error") {
                  Some(e) => e
                  None => tr("android-settings.login.unfinished")
                }
              },
              size=13.0,
              color=t.p.red,
              w=Fill(1.0),
              line=18.0,
            )
            |> ignore
            if button(c, "login-restart", tr("android-settings.login.restart"), false) {
              drop_login(core, station, n)
            }
          } else {
            login_steps(c, core, station + "/new/" + n.login, job, provider, fn(code) {
              if n.login != "" {
                act(core, tr("android-settings.login.finish"), "login.code", obj([("station", str(station)), ("id", str(n.login)), ("code", str(code))]))
              }
            })
          }
          if text(d, "usesLine") != "" {
            c.text(text(d, "usesLine"), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
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
  let tile = field(d, "tile")
  let label = fn(words : String) {
    c.text(words, size=13.0, weight=600, color=t.p.text, w=Fill(1.0), line=18.0) |> ignore
  }
  let group_box = fn(f : () -> Unit) { c.box(w=Fill(1.0), radius=16.0, bg=t.p.card, clip=true, f) |> ignore }
  let ekey = "profile-endpoint/" + form
  if !n.filled {
    n.filled = true
    field_of(ekey).set(text(d, "endpoint"))
    n.endpoint = text(d, "endpoint")
  }
  if flag(d, "showEndpoint") {
    label(tr("common.provider.endpoint"))
    let endpoint = field_box(c, ekey, match text(tile, "endpointExample") {
      "" => "https://"
      x => x
    }).trim(chars=" ").to_owned()
    if endpoint != n.endpoint {
      n.endpoint = endpoint
      edit([("endpoint", str(endpoint))])
    }
    match opt_text(d, "endpointHint") {
      Some(h) => c.text(h, size=12.0, color=t.p.muted, w=Fill(1.0), line=17.0) |> ignore
      None => ()
    }
  }
  let regions = items(d, "regions")
  if regions.length() > 1 {
    label(tr("web-mobile.profiles.region"))
    group_box(fn() {
      for r in regions {
        if pick_row(c, "region/" + text(Some(r), "id"), text(Some(r), "label"), checked=text(Some(r), "id") == text(d, "region")) {
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
        if pick_row(c, "protocol/" + text(Some(p), "id"), text(Some(p), "label"), checked=text(Some(p), "id") == text(d, "protocol")) {
          edit([("protocol", str(text(Some(p), "id")))])
        }
      }
    })
  }
  if flag(d, "showKey") {
    label(text(d, "keyLabel"))
    let key = field_box(c, "profile-key/" + form, tr("android-settings.profile.keyPlaceholder"), secret=true)
    if key != n.key {
      n.key = key
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
      Some((words, bad)) => c.text(words, size=12.0, color=if bad { t.p.red } else { t.p.muted }, w=Fill(1.0), line=17.0) |> ignore
      None => ()
    }
  }
  let submitting = is_doing(core, ["profile.flow.submit"], [("station", station), ("form", form)])
  c.box(dir=Row, w=Fill(1.0), justify=JEnd, fn() {
    if button(c, "profile-submit", text(d, "submitLabel"), true, busy=submitting || flag(d, "pending"), enabled=flag(d, "canSubmit")) {
      c.blur()
      (core.call)("profile.flow.submit", obj([("station", str(station)), ("form", str(form))]), fn(r) {
        match r {
          Ok(v) => {
            (core.say)(tr("android-settings.profile.verifiedAdded"))
            (core.pop)()
            (core.push)(Profile(station, text(Some(v), "id")))
          }
          // (what is wrong is the draft's own `error`, under the key)
          Err(_) => ()
        }
      })
    }
  })
  |> ignore
  if text(d, "usesLine") != "" {
    c.text(text(d, "usesLine"), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
  }
}

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
        let station = text(ev, "station")
        nav_bar(c, core, "Profile", text(p, "name"), sub=fn() {
          c.text(
            join(
              [
                text(p, "email"),
                if flag(p, "machine") {
                  tr("android-settings.profile.machine")
                } else {
                  match opt_text(p, "providerName") {
                    Some(x) => x
                    None => access_label(text(field(p, "access"), "kind"))
                  }
                },
              ],
              " · ",
            ),
            size=11.0,
            color=t.p.muted,
            wrap=false,
            line=16.0,
          )
          |> ignore
        })
        let blocks : Array[() -> Unit] = [
          fn() { gap(c, 16.0) },
          fn() {
            list_card(c, fn() {
              list_row(c, fn() {
                c.box(w=Fill(1.0), fn() {
                  c.box(dir=Row, gap=6.0, align=ACenter, fn() {
                    presence_dot(c, tone_dot(text(p, "checkTone")))
                    c.text(text(p, "checkText"), size=15.0, color=t.p.text, wrap=false, line=21.0) |> ignore
                  })
                  |> ignore
                  c.text(
                    match opt_text(field(p, "check"), "detail") {
                      Some(x) => x
                      None => tr("android-settings.profile.notChecked")
                    },
                    size=13.0,
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
              if list_row(c, key="account-member/" + text(mv, "station"), fn() {
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
                      c.text(text(mv, "stationName"), size=15.0, color=t.p.text, wrap=false, line=21.0) |> ignore
                    })
                    |> ignore
                    c.text(
                      if flag(mv, "online") {
                        text(mv, "about")
                      } else {
                        tr("android-settings.profiles.stationOffline")
                      },
                      size=13.0,
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
        blocks.push(fn() { gap(c, 30.0) })
        scroll_page(c, "profile-account/" + key, blocks)
      }
    }
  })
  |> ignore
}

///|
/// A plan's sign-in on a station without the runtime it signs in with (InstallStep, core `install`): installing it
/// first, how that stands, its button where the viewer may (`software.update`).
fn install_step(c : @ui.Ctx, core : Core, station : String, install : Json?) -> Unit {
  let t = @sf.theme()
  let runtime = text(install, "runtime")
  let busy = is_doing(core, ["software.update"], [("station", station), ("id", runtime)])
  card(c, fn() {
    c.box(w=Fill(1.0), gap=10.0, fn() {
      c.text(text(install, "title"), size=15.0, weight=600, color=t.p.text, w=Fill(1.0), line=21.0) |> ignore
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
        size=13.0,
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
