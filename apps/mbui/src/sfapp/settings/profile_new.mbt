// A new profile's draft on a station, as the core's add flow has it (`profileFlow`; its page sfpages new_profile.mbt):
// opened, a plan's sign-in started and let go. And an account on several stations (ProfileAccountScreen).

///|
/// The new-profile pages open, by station: the draft's form, the sign-in it started (none: ""), why that failed.
pub(all) struct NewProfile {
  form : String
  mut dropped : Bool
  login : @signals.Signal[String]
  mut asked : Bool
  error : @signals.Signal[String]
}

///|
let new_profiles : Map[String, NewProfile] = Map([])

///|
/// A count of drafts opened.
pub let profile_forms : Ref[Int] = Ref(0)

///|
/// The draft of a new profile's page on `station`, opened (`profile.flow.open`) as it is first made, `start` told it at
/// once (where the page begins: a provider and how, come from elsewhere); the one open there till it is left after.
pub fn new_profile_opened(core : Core, station : String, start : Array[(String, Json)]?) -> NewProfile {
  // (what is let go of as the page is left: this core's draft)
  left_core.val = Some(core)
  match new_profiles.get(station) {
    Some(n) if !n.dropped => n
    _ => {
      profile_forms.val += 1
      let n = {
        form: "mbui-profile-" + profile_forms.val.to_string(),
        dropped: false,
        login: @signals.signal(""),
        asked: false,
        error: @signals.signal(""),
      }
      new_profiles[station] = n
      act(core, tr("web-pages.addProfile.openAction"), "profile.flow.open", obj([("station", str(station)), ("form", str(n.form))]))
      match start {
        Some(input) =>
          act(
            core,
            tr("web-pages.addProfile.editAction"),
            "profile.flow.edit",
            obj([("station", str(station)), ("form", str(n.form)), ("input", obj(input))]),
          )
        None => ()
      }
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
      (core.call)("profile.flow.drop", obj([("station", str(station)), ("form", str(n.form))]), answer_unread)
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
      (core.call)("login.drop", obj([("station", str(station)), ("id", str(n.login.get()))]), answer_unread)
    }
    n.login.set("")
  }
  n.asked = false
}

///|
/// A sign-in under way on a station, by its id (its overview's `logins`, that part alone).
pub fn pending_login(core : Core, station : String, id : String) -> Json? {
  match station_part_in(core, workspace_of(station), station, "logins") {
    Some(Array(a)) => a.iter().find_first(fn(l) { text(Some(l), "id") == id })
    _ => None
  }
}

///|
/// A plan's sign-in started for the page (`login.new` with what it signs in to).
pub fn start_login(core : Core, station : String, n : NewProfile, runtime : String, access : String) -> Unit {
  n.asked = true
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
/// An account on several stations (ProfileAccountScreen): what they have in common, then each station's part, each
/// leading to its page there.
fn profile_account_page(c : @ui.Ctx, core : Core, here : Here, key : String) -> Unit {
  let t = @sf.theme()
  // (that account alone, whole: its own topic, by its key; null where the workspace has it no more)
  let topic = profile_by_key_read(core, here, key)
  let e = match topic.value {
    Some(Object(_)) as x => x
    _ => None
  }
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
      Some(_) as ev => {
        let p = field(ev, "profile")
        nav_bar(c, core, "Profile", text(p, "name"), sub=fn() {
          c.text(
            join(
              [
                text(p, "email"),
                text(p, "kindText"),
                text(p, "planText"),
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
        list_row(c, key="account-member/" + text(mv, "station") + "/" + text(mv, "profileId"), fn() {
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
        }, on_press=fn() {
          (core.push)(Profile(text(mv, "station"), text(mv, "profileId")))
        })
      }
    })
  })
  blocks
}

///|
/// An account made up, for what its page shows while it is read (account_blocks in its bones): on two stations.
fn account_sample() -> Json {
  let profile_host = fn(i : Int) -> Json {
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
    "members": [profile_host(0), profile_host(1)],
  }
}
