// A profile's page past its check, allowance and models (Profiles.kt ProfileScreen): its "…" (renaming, checking,
// deleting or stopping it), signing its subscription in (SignIn, LoginSteps), its sharing with the workspace's other
// stations (ShareSection) and the workspaces it serves (WorkspacesSection), how it runs (default Fast, commands put
// to the background), its key or its variables changed, what to do when it is in trouble (ProfileRecovery); the
// machine's own logins offered as profiles (MachineLoginOffers); and where something is added, a station picked.

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
/// Where something is added: one of the stations online picked (openPickStation), the library's pick opened `from`
/// what was pressed (a sheet on Small, else beside it), what it is for its title.
fn open_pick_station(stations : Array[Json], go : (String) -> Unit, from~ : @sf.Beside) -> Unit {
  // (each by its mark, as the sidebar and a chat's bar have it)
  let choices = stations.map(fn(s) {
    let sv = Some(s)
    @sf.choice(text(sv, "station"), text(sv, "name"), mark=fn(c, size) {
      @sf.station_icon(c, text(sv, "emoji"), text(sv, "icon"), size, @sf.theme().p.text)
    })
  })
  @sf.pick(tr("android-settings.pickStation"), choices, "", go, from~)
}

///|
/// A variable being edited (EnvRow): its row, the name and value typed, what a secret saved before shows masked, and
/// the name it had.
priv struct EnvRow {
  row : Int
  masked : String?
  original : String?
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
/// The accounts a station machine's own Claude Code and Codex are signed in with that no profile uses yet
/// (MachineLoginOffers), `s` the station as `stations` has it: one kept where the station reads it used as it is
/// (`profile.useMachineLogin`), one it cannot signed in again for still.fail (`go_new`), a refused one only said so. A
/// section of the page it is on (its title a section's, its rows a list card's, as the page's others), titled by the
/// station it is on (the workspace's page has a section each station: the same account signed in on two is in both);
/// `inset`, on a page of its own room (a new profile's sheet): its title and card that far in.
fn machine_login_offers(c : @ui.Ctx, core : Core, s : Json?, go_new : (String) -> Unit, inset? : Double) -> Array[() -> Unit] {
  let t = @sf.theme()
  let station = text(s, "station")
  let offers = items(field(s, "overview"), "machineLogins").filter(fn(l) { flag(Some(l), "offered") })
  if offers.length() == 0 {
    return []
  }
  let title = fill("web-mobile.profiles.machineLogins", [("station", text(s, "name"))])
  [
    fn() {
      match inset {
        Some(inset) =>
          // (its title as far in as the groups' titles under it: pick_group's, 6 in from their cards)
          c.box(w=Fill(1.0), pl=inset + 6.0, pr=inset + 6.0, pt=8.0, pb=4.0, fn() {
            c.text(title, size=t.t.meta, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
          })
          |> ignore
        None => section_header(c, title, start=S6)
      }
    },
    fn() {
      let card = fn(body : () -> Unit) {
        match inset {
          Some(inset) => c.box(w=Fill(1.0), pl=inset, pr=inset, pb=10.0, fn() { rows_card(c, body) }) |> ignore
          None => list_card(c, body)
        }
      }
      card(fn() {
          for l in offers {
            let lv = Some(l)
            let rt = text(lv, "runtime")
            let blocked = text(field(lv, "quota"), "state") == "blocked"
            let busy = is_doing(core, ["profile.useMachineLogin"], [("station", station), ("runtime", rt)])
            list_row(c, fn() {
              @sf.provider_logo(c, rt, "subscription", 18.0, "")
              // what it is and using it on its first line; how it is signed in, what is wrong and its allowance under
              // them, each as wide as its words (lines of their own)
              @sf.row_lines(c, fn() {
                c.box(dir=Row, w=Fill(1.0), gap=6.0, align=ACenter, fn() {
                  c.text(runtime_label(rt), size=t.t.ui, color=t.p.text, wrap=false, line=21.0) |> ignore
                  let plan = text(lv, "planText")
                  if plan != "" {
                    c.text(plan, size=t.t.meta, color=t.p.muted, wrap=false) |> ignore
                  }
                })
                |> ignore
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
                            (core.push)(Profile(station, text(Some(v), "id")))
                          }
                          Err(e) => (core.say)(error_text(e))
                        }
                      })
                    } else {
                      go_new(rt)
                    }
                  }
                }
              }, fn() {
                c.box(style=machine_under, fn() {
                  c.box(dir=Row, w=Fill(1.0), gap=5.0, align=ACenter, fn() {
                    c.box(w=Px(6.0), h=Px(6.0), radius=3.0, bg=if blocked { t.p.red } else { t.p.green }, fn() {  }) |> ignore
                    c.text(
                      tr(if blocked { "android-settings.quota.blocked" } else { "android-settings.machine.signedIn" }),
                      size=t.t.caption,
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
                      size=t.t.caption,
                      color=t.p.muted,
                      wrap=false,
                      w=Fill(1.0),
                    )
                    |> ignore
                  })
                  |> ignore
                  let trouble = quota_trouble(field(lv, "quota"))
                  if trouble != "" {
                    c.text(trouble, size=t.t.caption, color=if blocked { t.p.red } else { t.p.muted }, w=Fill(1.0), line=17.0) |> ignore
                  }
                  c.box(style=machine_chips, fn() { @sf.quota_chips(c, field(lv, "quota"), key="machine-use/" + rt) }) |> ignore
                })
                |> ignore
              })
            })
            |> ignore
          }
      })
    },
  ]
}

///|
/// What is under an account signed in on the machine's first line: how it is signed in, what is wrong, its allowance
/// 4 under them; 2 apart, 2 under its first line.
// kept across runs: a value (no field of it changes)
let machine_under : @ui.Style = @ui.css("w=Full pt=S0_5 gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let machine_chips : @ui.Style = @ui.css("row pt=S1")
