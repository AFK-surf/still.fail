// What a new profile's page keeps of its draft and its sign-in (the page: src/sfpages add_profile.mbt, one in every
// frame): the core's add flow (`profileFlow`), a plan signed in (`login.new`, its steps relayed, the profile made by the
// station once it is signed in). And an account on several stations (ProfileAccountScreen).

///|
/// The new-profile pages open, by station: the draft's form, the sign-in it started (none: ""), why that failed.
pub(all) struct NewProfile {
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
pub let profile_forms : Ref[Int] = Ref(0)

///|
/// The draft of a new profile's page, made the first time it is drawn.
pub fn new_profile_of(station : String) -> NewProfile {
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
pub fn drop_login(core : Core, station : String, n : NewProfile) -> Unit {
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
                      c.text(text(mv, "stationName"), size=t.t.ui, color=t.p.text, wrap=false, line=21.0) |> ignore
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
        blocks.push(fn() { gap(c, 30.0) })
        scroll_page(c, "profile-account/" + key, blocks)
      }
    }
  })
  |> ignore
}
