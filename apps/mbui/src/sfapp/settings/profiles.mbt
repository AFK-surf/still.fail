// Profiles, the model accounts the agents run on (settings/Profiles.kt; the core's `profiles` view and each station's
// overview): every station's in one list, a section a kind of account, a shared one once; from a station's page that
// station's only. A profile's page: whether it works, its allowance (read again with `profile.quota`), which of its
// models may be used (ticked on and off: `profile.put` with `models`, read again with `profile.check`), who uses it,
// its key masked. (Signing a subscription in, adding a profile, its "…" and its sharing are a later slice's.)

///|
/// Why an allowance could not be read, in the provider's words (Profiles.kt quotaTrouble).
fn quota_trouble(q : Json?) -> String {
  match text(q, "state") {
    "blocked" | "unavailable" => text(q, "detail")
    _ => ""
  }
}

///|
/// How a profile reaches its model service, in a word (Words.kt ACCESS_LABEL).
fn access_label(kind : String) -> String {
  match kind {
    "subscription" => tr("android-misc.access.subscription")
    "opencode-go" => "OpenCode Go"
    "anthropic-api" => "Anthropic API"
    "api-provider" => tr("common.provider.title")
    "env" => tr("android-misc.access.env")
    k => k
  }
}

///|
/// A profile's allowance in a line (Parts.kt QuotaChips): a box per window, what is left in it, its mark when there is
/// more than one; `small`, a lower line (a chat's agents, an execution's notes); `gap` apart; `tip`: told each one's
/// box (its id) and window, for words over it while it is pointed at (the web's Tip over each).
pub fn quota_chips(
  c : @ui.Ctx,
  q : Json?,
  small? : Bool = false,
  gap? : Double = 8.0,
  tip? : (Int, Json) -> Unit,
) -> Unit {
  if text(q, "state") != "ok" {
    return
  }
  let windows = items(q, "windows")
  if windows.length() == 0 {
    return
  }
  c.box(dir=Row, gap~, align=ACenter, fn() {
    for w in windows {
      let wv = Some(w)
      let left = clamp(count(wv, "left"))
      let chip = fn() {
        fill_chip(
          c,
          left,
          text(wv, "level"),
          if windows.length() == 1 { "" } else { text(wv, "mark") },
          left.to_string() + "%",
          small~,
        )
      }
      match tip {
        Some(f) => {
          let id = c.id("quota-chip/" + text(wv, "mark"))
          c.box(id~, taps=false, chip) |> ignore
          f(id, w)
        }
        None => chip()
      }
    }
  })
  |> ignore
}

///|
/// The profiles (ProfilesScreen): the workspace's, or a station's (`only`) and back to it.
fn profiles_page(c : @ui.Ctx, core : Core, here : Here, only : String) -> Unit {
  let topic = stations_of(core, here)
  let all = match topic.value {
    Some(Array(a)) => Some(a)
    _ => None
  }
  let one = match all {
    Some(a) if only != "" => a.iter().find_first(fn(x) { text(Some(x), "station") == only })
    _ => None
  }
  let back = match one {
    Some(o) => text(Some(o), "name")
    None => tr("android-settings.title")
  }
  let add = match place_action(core, here, "profiles") {
    Some(run) => Some(("add-profile", run))
    None => None
  }
  place_page(c, core, tr("android-misc.bar.place.profiles"), back~, primary?=add, fn() {
    let blocks : Array[() -> Unit] = []
    let offers = fn(sv : Json?) {
      if flag(sv, "online") {
        let station = text(sv, "station")
        blocks.append(machine_login_offers(c, core, station, field(sv, "overview"), fn(_) { (core.push)(NewProfile(station)) }))
      }
    }
    if only == "" {
      blocks.append(workspace_profiles(c, core, here))
      // the machine's own logins not used yet, each offered as a profile
      match all {
        Some(a) =>
          for s in a {
            offers(Some(s))
          }
        None => ()
      }
    } else {
      match one {
        None =>
          blocks.push(fn() {
            waiting_rows(
              c,
              error=match topic.error {
                Some(e) => error_text(e)
                None => ""
              },
            )
          })
        Some(s) => {
          let sv = Some(s)
          let overview = field(sv, "overview")
          let list = items(overview, "profiles")
          if list.length() == 0 {
            blocks.push(fn() {
              list_card(c, fn() {
                list_row(c, fn() {
                  if overview is None && flag(sv, "online") {
                    wait_line(c, tr("common.reading"))
                  } else {
                    row_title(
                      c,
                      if overview is None {
                        tr("android-settings.profiles.stationOffline")
                      } else {
                        tr("android-settings.profiles.empty")
                      },
                      color=@sf.theme().p.muted,
                    )
                  }
                })
                |> ignore
              })
            })
          } else {
            ignore(0)
            for g in group_by(list) {
              blocks.append([
                fn() { section_header(c, g.1, mark=Some(fn() { group_mark(c, g.0) }), start=S6) },
                fn() {
                  list_card(c, fn() {
                    for p in g.2 {
                      profile_row(c, core, only, p)
                    }
                  })
                },
              ])
            }
          }
          offers(sv)
        }
      }
    }
    blocks.push(fn() { gap(c, 30.0) })
    scroll_page(c, "profiles/" + only, blocks)
  })
}

///|
/// A station's profiles by the kind they are listed under (`group`, `groupTitle`), in order.
fn group_by(list : Array[Json]) -> Array[(String, String, Array[Json])] {
  let out : Array[(String, String, Array[Json])] = []
  for p in list {
    let g = text(Some(p), "group")
    match index_of(out, g) {
      Some(i) => out[i].2.push(p)
      None => out.push((g, text(Some(p), "groupTitle"), [p]))
    }
  }
  out
}

///|
/// A kind of account's mark, before its section's title (Profiles.kt GroupMark): its vendor's for a subscription, a
/// key for keys.
fn group_mark(c : @ui.Ctx, group : String) -> Unit {
  match group {
    "key" => @sf.icon(c, "key", size=16.0, color=@sf.theme().p.text) |> ignore
    // signed in to an account: its provider's
    "kimi" => provider_mark(c, "claude", "api-provider", 16.0, "kimi")
    "opencode" => provider_mark(c, "claude", "opencode-go", 16.0, "")
    // a subscription: its vendor's, by the runtime it is (ChatGPT's Codex; SuperGrok's xAI, Cursor's, Devin's)
    "chatgpt" => provider_mark(c, "codex", "subscription", 16.0, "")
    "" => provider_mark(c, "claude", "subscription", 16.0, "")
    g => provider_mark(c, g, "subscription", 16.0, "")
  }
}

///|
/// The workspace's profiles (Profiles.kt WorkspaceList): a section a kind of account, a shared one once, where it is
/// under it; one whose station is away dimmed, said why.
fn workspace_profiles(c : @ui.Ctx, core : Core, here : Here) -> Array[() -> Unit] {
  let t = @sf.theme()
  let topic = (core.topic)("profiles", { "scope": str(here.workspace) })
  let v = topic.value
  let wait = field(v, "wait")
  let list = items(v, "items")
  match v {
    None =>
      return [
        fn() {
          waiting_rows(
            c,
            error=match topic.error {
              Some(e) => error_text(e)
              None => ""
            },
          )
        },
      ]
    Some(_) if list.length() == 0 && note_waits(wait) =>
      return [fn() { waiting_rows(c, failing=failing_of(wait)) }]
    _ => ()
  }
  let blocks : Array[() -> Unit] = []
  if list.length() == 0 {
    blocks.push(fn() {
      list_card(c, fn() {
        list_row(c, fn() { row_title(c, tr("android-settings.profiles.empty"), color=t.p.muted) }) |> ignore
      })
      place_empty(c, tr("android-settings.profiles.note"))
    })
  }
  for g in profile_groups(list) {
    blocks.append([
      fn() { section_header(c, g.0, mark=Some(fn() { group_mark(c, text(g.1.get(0), "group")) }), start=S6) },
      fn() {
        list_card(c, fn() {
          for e in g.1 {
            let ev = Some(e)
            let p = field(ev, "profile")
            let usable = flag(ev, "usable")
            if list_row(c, key="ws-profile/" + text(ev, "key"), fn() {
                c.box(w=Fill(1.0), opacity=if usable { 1.0 } else { 0.55 }, fn() {
                  c.box(dir=Row, w=Fill(1.0), gap=6.0, align=ACenter, fn() {
                    presence_dot(c, if usable { tone_dot(text(p, "checkTone")) } else { "error" })
                    c.text(text(p, "name"), size=15.0, color=t.p.text, wrap=false, w=@sf.line_left, line=21.0) |> ignore
                  })
                  |> ignore
                  let line = if !usable {
                    fill("web-pages.settings.profiles.hostAway", [("station", text(ev, "hostName"))])
                  } else if text(ev, "where") != "" {
                    text(ev, "where")
                  } else {
                    join(
                      [
                        text(p, "checkText"),
                        match text(p, "usesText") {
                          "" => access_label(text(field(p, "access"), "kind"))
                          u => u
                        },
                      ],
                      " · ",
                    )
                  }
                  c.text(line, size=13.0, color=t.p.muted, wrap=false, w=Fill(1.0), line=18.0) |> ignore
                  // its allowance a line of its own, so the name and where it is keep the row's width (Profiles.kt)
                  if usable && text(field(p, "quota"), "state") == "ok" && items(field(p, "quota"), "windows").length() > 0 {
                    // (in its row's corner, 12 in: the row's corner concentric round its own, @sf.fill_chip_corner)
                    c.box(style=quota_line, fn() { quota_chips(c, field(p, "quota")) })
                    |> ignore
                  }
                })
                |> ignore
                chevron(c)
              }) {
              // an account on several stations: its own page, each station's part under it
              let signed = items(ev, "members").filter(fn(m) { text(Some(m), "role") != "user" }).length()
              (core.push)(if signed > 1 { ProfileAccount(text(ev, "key")) } else { Profile(text(ev, "station"), text(p, "id")) })
            }
          }
        })
      },
    ])
  }
  if flag(wait, "reading") {
    blocks.push(fn() {
      list_card(c, fn() {
        list_row(c, fn() {
          wait_line(
            c,
            match text(wait, "text") {
              "" => tr("common.reading")
              w => w
            },
          )
        })
        |> ignore
      })
    })
  }
  blocks
}

///|
/// A profile in a station's list (Profiles.kt ProfileRow): whether it works, what it is, how many of its models are
/// on, why its provider refuses it; its allowance.
fn profile_row(c : @ui.Ctx, core : Core, station : String, p : Json) -> Unit {
  let t = @sf.theme()
  let pv = Some(p)
  let id = text(pv, "id")
  if list_row(c, key="profile/" + station + "/" + id, fn() {
      c.box(w=Fill(1.0), fn() {
        c.box(dir=Row, w=Fill(1.0), gap=6.0, align=ACenter, fn() {
          presence_dot(c, tone_dot(text(pv, "checkTone")))
          c.text(text(pv, "name"), size=15.0, color=t.p.text, wrap=false, w=@sf.line_left, line=21.0) |> ignore
        })
        |> ignore
        let kind = text(field(pv, "access"), "kind")
        c.text(
          join(
            [
              text(pv, "checkText"),
              if flag(pv, "machine") {
                tr("android-settings.profile.machine")
              } else {
                match text(pv, "usesText") {
                  "" => access_label(kind)
                  u => u
                }
              },
              text(pv, "modelsText"),
            ],
            " · ",
          ),
          size=13.0,
          color=t.p.muted,
          wrap=false,
          w=Fill(1.0),
          line=18.0,
        )
        |> ignore
        match field(pv, "trouble") {
          Some(Object(_)) as tr_ => {
            c.text(text(tr_, "title") + " · " + text(tr_, "detail"), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0)
            |> ignore
            c.text(tr("android-settings.profile.seeFix"), size=13.0, color=@sf.link_ink(), wrap=false, line=18.0) |> ignore
          }
          _ => {
            let trouble = quota_trouble(field(pv, "quota"))
            if trouble != "" {
              c.text(trouble, size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
            }
          }
        }
      })
      |> ignore
      let calls = ["profile.check", "profile.quota"]
      let on = [("station", station), ("id", id)]
      doing_mark(c, is_doing(core, calls, on), failed_of(core, calls, on))
      quota_chips(c, field(pv, "quota"))
      chevron(c)
    }) {
    (core.push)(Profile(station, id))
  }
}

///|
/// A profile's page (ProfileScreen).
fn profile_page(c : @ui.Ctx, core : Core, here : Here, address : String, id : String) -> Unit {
  let t = @sf.theme()
  let topic = stations_of(core, here)
  let s = match topic.value {
    Some(Array(a)) => a.iter().find_first(fn(x) { text(Some(x), "station") == address })
    _ => None
  }
  let sv = match s {
    Some(x) => Some(x)
    None => None
  }
  let p = items(field(sv, "overview"), "profiles").iter().find_first(fn(x) { text(Some(x), "id") == id })
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    match p {
      None => {
        nav_bar(c, core, if sv is None { "Station" } else { text(sv, "name") }, "Profile")
        if field(sv, "overview") is Some(Object(_)) && topic.error is None {
          place_empty(c, tr("android-settings.profile.none"))
        } else {
          waiting_cards(
            c,
            error=match topic.error {
              Some(e) => error_text(e)
              None => ""
            },
          )
        }
      }
      Some(pj) => {
        let pv = Some(pj)
        let kind = text(field(pv, "access"), "kind")
        let copy = text(field(pv, "share"), "role") == "user"
        let more = fn() {
          if nav_button(c, "profile-more", "more") {
            open_profile_menu(core, address, pv)
          }
        }
        nav_bar(c, core, text(sv, "name"), text(pv, "name"), trailing?=if copy { None } else { Some(more) }, sub=fn() {
          c.text(
            if flag(pv, "machine") {
              tr("android-settings.profile.machine")
            } else {
              match opt_text(pv, "providerName") {
                Some(n) => n
                None => access_label(kind)
              }
            },
            size=11.0,
            color=t.p.muted,
            wrap=false,
            line=16.0,
          )
          |> ignore
        })
        let users = strings(pv, "usedBy").filter_map(fn(u) {
          items(field(sv, "overview"), "connects").iter().find_first(fn(x) { text(Some(x), "id") == u })
        })
        // where it stands (and, in trouble, why and what to do), the head of the account's one card
        let status = fn() { account_status(c, core, sv, pv) }
        // first what the page is opened for: whether the account works now, and how much of it is left; then who uses
        // it, how it runs, whom it is shared with
        let blocks : Array[() -> Unit] = [fn() { gap(c, 12.0) }]
        // a subscription's (or one on an account: OpenCode Go's, Kimi Code's) is the head of its sign-in's card; the
        // machine's own login's, of the card that says whose it is; a key's, of the card with its key (one card for the
        // account, not a card of a pill over another)
        if !copy && signs_in(pv) {
          blocks.append(profile_sign_in(c, core, address, pv, status))
        } else if !copy && flag(pv, "machine") {
          // on the machine's own login: whose it is is changed on that machine, not here
          let runtime = runtime_label(text(pv, "runtime"))
          blocks.push(fn() {
            card(c, fn() {
              status()
              c.box(style=machine_login_room, fn() {
                c.text(fill("android-settings.profile.machineLogin", [("station", text(sv, "name")), ("runtime", runtime)]), style=@sf.body.then(@sf.full_words))
                |> ignore
              })
              |> ignore
              c.box(w=Fill(1.0), pt=4.0, fn() {
                c.text(fill("android-settings.profile.machineNote", [("runtime", runtime)]), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0)
                |> ignore
              })
              |> ignore
            })
            |> ignore
          })
        } else if !copy && keyed.contains(kind) && !flag(field(pv, "access"), "login") {
          blocks.append(profile_key(c, core, address, pv, status))
        } else {
          // (a trouble's button its last: the card's corner taken from it)
          blocks.push(fn() { card(c, foot=trouble_button(pv), status) |> ignore })
        }
        if text(field(pv, "trouble"), "action") != "quota" {
          blocks.append(quota_section(c, core, address, pv))
        }
        if kind == "env" && !copy {
          blocks.append(profile_env(c, core, address, pv))
        }
        blocks.append([
          fn() { section_header(c, tr("android-settings.profile.users"), start=S6) },
          fn() {
            list_card(c, fn() {
              if users.length() == 0 {
                list_row(c, fn() { row_title(c, tr("android-settings.profile.noUsers"), color=t.p.muted) }) |> ignore
              }
              for u in users {
                let uv = Some(u)
                if list_row(c, key="profile-user/" + text(uv, "id"), fn() {
                    @sf.slack_mark(c, 15.0) |> ignore
                    row_title(c, text(uv, "name"))
                    c.text(
                      match opt_text(uv, "modelName") {
                        Some(n) => n
                        None =>
                          match opt_text(pv, "model") {
                            Some(m) => {
                              let named = text(field(pv, "names"), m)
                              if named == "" {
                                m
                              } else {
                                named
                              }
                            }
                            None => tr("android-settings.profile.defaultModel")
                          }
                      },
                      size=13.0,
                      color=t.p.muted,
                      wrap=false,
                    )
                    |> ignore
                  }) {
                  (core.push)(Connect(address, text(uv, "id")))
                }
              }
            })
          },
        ])
        if !copy {
          // a decision model's are said, not picked (models_section)
          if flag(pv, "decisionOnly") {
            blocks.append(models_section(c, core, address, pv))
          }
          blocks.append(profile_run(c, core, address, pv))
        }
        blocks.append(profile_sharing(c, core, here, sv, pv))
        blocks.push(fn() { gap(c, 30.0) })
        scroll_page(c, "profile/" + address + "/" + id, blocks)
      }
    }
  })
  |> ignore
}

///|
/// Where an account stands, at the top of its one card (ProfileScreen's head): its provider's mark; what it is now in
/// a line (what is wrong: its trouble's title; else what its check said beyond its words; else they); under it a dot
/// of its tone, its words (when the line above is not they) and when it was checked, coloured only where something is
/// off (its check under way said so; it or its allowance's refresh failed a moment ago, a red mark that says why);
/// then, in trouble, why and what to do (profile_trouble).
fn account_status(c : @ui.Ctx, core : Core, sv : Json?, pv : Json?) -> Unit {
  let on = [("station", text(sv, "station")), ("id", text(pv, "id"))]
  let check = field(pv, "check")
  let trouble = field(pv, "trouble")
  let words = text(pv, "checkText")
  let tone = text(pv, "checkTone")
  let detail = match check {
    Some(Object(_)) if opt_text(check, "detail") is Some(_) => strip_works(text(check, "detail"))
    _ => tr("android-settings.profile.notChecked")
  }
  let first = match trouble {
    Some(Object(_)) if text(trouble, "title") != "" => text(trouble, "title")
    _ => if detail != "" && detail != words { detail } else { words }
  }
  let checked = match stamp(check, "checkedAt", "ago") {
    "" => ""
    ago => fill("android-settings.profile.checkedAt", [("ago", ago)])
  }
  let said = first != words
  // (its words said on the line above already: only when it was checked, the key's " · " dropped)
  let under = if said {
    words + checked
  } else if checked.has_prefix(" · ") {
    checked.unsafe_substring(start=3, end=checked.length())
  } else {
    checked
  }
  let checking = is_doing(core, ["profile.check"], on)
  let failed = failed_of(core, ["profile.check", "profile.quota"], on)
  c.box(style=account_rows, fn() {
    c.box(style=account_head, fn() {
      provider_mark(c, text(pv, "runtime"), text(field(pv, "access"), "kind"), 26.0, text(pv, "providerMark"))
      c.box(style=account_head_words, fn() {
        c.text(first, style=@sf.body.then(@sf.full_words)) |> ignore
        if checking || under != "" || failed is Some(_) {
          c.box(style=account_state, fn() {
            presence_dot(c, tone_dot(tone))
            if checking {
              wait_line(c, tr("android-settings.version.checking"))
            } else {
              if under != "" {
                c.text(under, style=match tone {
                  "red" if said => account_state_bad
                  "amber" if said => account_state_warn
                  _ => @sf.meta
                })
                |> ignore
              }
              doing_mark(c, false, failed, inline=true)
            }
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
    profile_trouble(c, core, sv, pv)
  })
  |> ignore
}

///|
/// The account's head and what its trouble says under it, 12 apart.
// kept across runs: a value (no field of it changes)
let account_rows : @ui.Style = @ui.css("w=Full gap=S3")

///|
/// Its mark, then its words beside it, 12 apart.
// kept across runs: a value (no field of it changes)
let account_head : @ui.Style = @ui.css("row w=Full gap=S3")

///|
/// Its line, then its state under it, 4 apart.
// kept across runs: a value (no field of it changes)
let account_head_words : @ui.Style = @ui.css("w=Full gap=S1")

///|
/// Its state: a dot, then its words, 6 apart.
// kept across runs: a value (no field of it changes)
let account_state : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
/// Its words when it does not work (13, red).
// kept across runs: a value (no field of it changes)
let account_state_bad : @ui.TextStyle = @ui.text_style(size=Sm, leading=L5, color=Danger)

///|
/// Its words when it works but something is short (13, amber's ink).
// kept across runs: a value (no field of it changes)
let account_state_warn : @ui.TextStyle = @ui.text_style(size=Sm, leading=L5, color=Warn)

///|
/// A check's words without its leading 可用， (it is said by the pill already).
fn strip_works(s : String) -> String {
  for p in ["可用，", "可用,", "Works, ", "Works,"] {
    if s.has_prefix(p) {
      return s.unsafe_substring(start=p.length(), end=s.length()).trim(chars=" ").to_owned()
    }
  }
  s
}

///|
/// The profile's allowance (Profiles.kt QuotaSection), the card under its account's, no title over it (its windows
/// say what they are): its windows large, its credits, its resets; when it was read under them (read again from the
/// page's "…" with its check: open_profile_menu). One that could not be read says why; none to read (a key's), no card.
fn quota_section(c : @ui.Ctx, core : Core, station : String, pv : Json?) -> Array[() -> Unit] {
  let t = @sf.theme()
  let id = text(pv, "id")
  let q = field(pv, "quota")
  let on = [("station", station), ("id", id)]
  let refreshing = is_doing(core, ["profile.quota"], on)
  let trouble = quota_trouble(q)
  let windows = if text(q, "state") == "ok" { items(q, "windows") } else { [] }
  let blocks : Array[() -> Unit] = []
  if trouble != "" {
    let blocked = text(q, "state") == "blocked"
    blocks.push(fn() {
      list_card(c, fn() {
        list_row(c, fn() {
          c.box(w=Fill(1.0), fn() {
            c.box(dir=Row, gap=6.0, align=ACenter, fn() {
              presence_dot(c, if blocked { "error" } else { "offline" })
              c.text(
                tr(if blocked { "android-settings.quota.blocked" } else { "android-settings.quota.unavailable" }),
                size=15.0,
                color=t.p.text,
                line=21.0,
              )
              |> ignore
            })
            |> ignore
            c.text(trouble, size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
    })
    return blocks
  }
  if windows.length() == 0 && !has(q, "creditsText") && !has(q, "resetCount") {
    return blocks
  }
  blocks.push(fn() {
    list_card(c, fn() {
      if windows.length() > 0 {
        c.box(w=Fill(1.0), pl=16.0, pr=16.0, pt=16.0, pb=14.0, fn() {
          quota_dials(c, windows)
          // when it was read, under them (being read: said so)
          let at = stamp(q, "checkedAt", "ago")
          if refreshing {
            c.box(style=quota_read_room, fn() { wait_line(c, tr("android-settings.quota.checking")) }) |> ignore
          } else if at != "" {
            c.box(style=quota_read_room, fn() {
              c.text(fill("android-settings.quota.checkedAt", [("ago", at)]), style=@sf.caption) |> ignore
            })
            |> ignore
          }
        })
        |> ignore
      }
      match opt_text(q, "creditsText") {
        Some(credits) =>
          list_row(c, fn() {
            row_title(c, tr("android-settings.quota.credits"))
            c.text(credits, size=13.0, color=t.p.muted, wrap=false) |> ignore
          })
          |> ignore
        None => ()
      }
      if has(q, "resetCount") {
        // a reset used, asked first (the subscription's own: so many left, `resetText` what it does)
        let resetting = is_doing(core, ["profile.resetQuota"], on)
        let left = count(q, "resetCount")
        let reset = list_row(
          c,
          fn() {
            row_lines(c, tr("android-settings.quota.resets"), text(q, "resetText"))
            doing_mark(c, resetting, failed_of(core, ["profile.resetQuota"], on))
            c.text(tr("android-settings.quota.reset"), style=if left > 0 { @sf.value.then(@sf.link) } else { @sf.value })
            |> ignore
          },
          key=if left <= 0 || resetting { "" } else { "quota-reset" },
        )
        if reset {
          confirm(
            tr("android-settings.quota.resetTitle"),
            fill("android-settings.quota.resetText", [("name", text(pv, "name")), ("text", text(q, "resetText"))]),
            tr("android-settings.quota.resetUse"),
            fn() {
              act(
                core,
                tr("android-settings.quota.resetWhat"),
                "profile.resetQuota",
                obj([("station", str(station)), ("id", str(id))]),
                done=tr("android-settings.quota.resetDone"),
              )
            },
          )
        }
      }
    })
  })
  blocks
}

///|
/// When an allowance was read: 12 under its windows.
// kept across runs: a value (no field of it changes)
let quota_read_room : @ui.Style = @ui.css("w=Full pt=S3")

///|
/// An allowance on its own page (Parts.kt QuotaDials): each window's number large, ten cells lit as far as is left,
/// its name and when it refills.
fn quota_dials(c : @ui.Ctx, windows : Array[Json]) -> Unit {
  let t = @sf.theme()
  // (a FlowRow: 36 apart, 12 between its lines)
  c.box(dir=Row, w=Fill(1.0), gap=36.0, flow=true, line_gap=12.0, fn() {
    for w in windows {
      let wv = Some(w)
      let level = text(wv, "level")
      let tone = level_color(level)
      let low = level == "amber" || level == "red"
      let left = clamp(count(wv, "left"))
      let lit = (left.to_double() / 10.0 + 0.5).floor().to_int()
      c.box(min_w=96.0, gap=2.0, fn() {
        c.box(dir=Row, align=AEnd, fn() {
          c.text(left.to_string(), size=28.0, weight=600, color=if low { tone } else { t.p.text }, wrap=false, line=32.0)
          |> ignore
          c.box(pl=1.0, fn() {
            c.text("%", size=15.0, weight=500, color=t.p.muted, wrap=false, line=26.0) |> ignore
          })
          |> ignore
        })
        |> ignore
        c.box(dir=Row, pt=4.0, pb=6.0, gap=2.0, fn() {
          for i in 0..<10 {
            c.box(w=Px(7.0), h=Px(14.0), radius=2.0, bg=if i < lit { tone } else { t.p.chip }, fn() {  }) |> ignore
          }
        })
        |> ignore
        c.text(text(wv, "label"), size=13.0, weight=500, color=t.p.text, wrap=false, line=18.0) |> ignore
        c.text(
          match text(wv, "refills") {
            "" => " "
            r => r
          },
          size=12.0,
          color=t.p.muted,
          wrap=false,
          line=17.0,
        )
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The models a profile can be let use: those its provider lists, else those its check found with those it has on.
fn model_choices(pv : Json?) -> Array[String] {
  let a = strings(pv, "available")
  if a.length() > 0 {
    return a
  }
  let m = strings(field(pv, "check"), "models")
  for x in strings(pv, "models") {
    if !m.contains(x) {
      m.push(x)
    }
  }
  m
}

///|
/// Which of its models may be used (Profiles.kt ModelsSection): how many of how many, reading them again
/// (`profile.check`), all / none, then by series a row each, ticked on or off (`profile.put` with its models).
/// `bare`: on the step after a profile is added (pick_models.mbt), which says what these are: no header or note.
/// `page`: on a page of their own (profile_models_page), whose title says how many: the note, no header.
fn models_section(
  c : @ui.Ctx,
  core : Core,
  station : String,
  pv : Json?,
  bare? : Bool = false,
  page? : Bool = false,
) -> Array[() -> Unit] {
  let t = @sf.theme()
  let id = text(pv, "id")
  let on = [("station", station), ("id", id)]
  if flag(pv, "decisionOnly") {
    let blocks : Array[() -> Unit] = [fn() { section_header(c, tr("web-mobile.profiles.decisionModels"), start=S6) }]
    blocks.push(fn() {
      for m in strings(pv, "decisionModels") {
        c.box(w=Fill(1.0), padx=24.0, pady=6.0, fn() {
          c.text(m, size=15.0, color=t.p.text, line=21.0) |> ignore
        })
        |> ignore
      }
      match opt_text(pv, "decisionText") {
        Some(d) =>
          c.box(w=Fill(1.0), padx=24.0, pb=6.0, fn() {
            c.text(d, size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
          })
          |> ignore
        None => ()
      }
    })
    return blocks
  }
  let models = strings(pv, "models")
  let saving = has(pv, "modelsSaving")
  let pending = strings(pv, "modelsSaving")
  let all = model_choices(pv)
  let checking = is_doing(core, ["profile.check"], on)
  let add_key = "models-add/" + station + "/" + id
  let filter_key = "models-filter/" + station + "/" + id
  // what the filter leaves: a model whose id or name has the words its field holds
  let typed_filter = field_of(filter_key).text().trim(chars=" \t\n").to_string().to_lower()
  let filtered = typed_filter != ""
  let shown = all.filter(fn(m) {
    !filtered ||
    m.to_lower().contains(typed_filter) ||
    text(field(pv, "names"), m).to_lower().contains(typed_filter)
  })
  let save = fn(next : Array[String]) {
    let uniq : Array[String] = []
    for x in next {
      if !uniq.contains(x) {
        uniq.push(x)
      }
    }
    uniq.sort()
    act(
      core,
      tr("android-settings.profile.saveModels"),
      "profile.put",
      obj([("station", str(station)), ("id", str(id)), ("input", obj([("models", Json::array(uniq.map(str)))]))]),
    )
  }
  let blocks : Array[() -> Unit] = [
    fn() {
      if !bare && !page {
        section_header(
          c,
          fill(
            if saving {
              "android-settings.models.headerSaving"
            } else {
              "android-settings.models.header"
            },
            [("on", models.length().to_string()), ("n", all.length().to_string())],
          ),
          start=S6,
        )
      }
      if !bare {
        // (on a page of their own, 12 under its bar first)
        if page {
          gap(c, 12.0)
        }
        c.box(w=Fill(1.0), padx=24.0, pb=6.0, fn() {
          c.text(
            tr(if all.length() == 0 { "android-settings.models.empty" } else { "android-settings.models.note" }),
            size=13.0,
            color=t.p.muted,
            w=Fill(1.0),
            line=18.0,
          )
          |> ignore
        })
        |> ignore
      }
      c.box(dir=Row, w=Fill(1.0), padx=24.0, pb=8.0, gap=12.0, align=ACenter, fn() {
        let rid = c.id("models-refresh")
        if hit(c, rid) && !checking {
          act(
            core,
            tr("android-settings.models.refreshWhat"),
            "profile.check",
            obj([("station", str(station)), ("id", str(id))]),
            done=tr("android-settings.models.refreshed"),
          )
        }
        c.box(dir=Row, gap=6.0, align=ACenter, id=rid, fn() {
          doing_mark(c, checking, failed_of(core, ["profile.check"], on), inline=true)
          c.text(
            tr(if checking { "android-settings.refreshing" } else { "android-settings.models.refresh" }),
            size=14.0,
            color=if checking { t.p.muted } else { @sf.link_ink() },
            wrap=false,
          )
          |> ignore
        })
        |> ignore
        c.spacer()
        if all.length() > 0 {
          // all / none of what is shown (of what the filter leaves, while one is typed)
          if tap_text(
              c,
              "models-all",
              tr(if filtered { "android-settings.models.allFiltered" } else { "android-settings.all" }),
              size=14.0,
            ) &&
            !saving {
            save(models.copy()..append(shown))
          }
          if tap_text(
              c,
              "models-none",
              tr(if filtered { "android-settings.models.noneFiltered" } else { "android-settings.none" }),
              size=14.0,
            ) &&
            !saving {
            save(models.filter(fn(m) { !shown.contains(m) }))
          }
        }
      })
      |> ignore
    },
  ]
  // a provider that does not list its models: one named by hand (`profile.addModel`)
  if flag(pv, "canAddModel") {
    blocks.push(fn() {
      let adding = is_doing(core, ["profile.addModel"], on)
      c.box(style=models_add_row, fn() {
        let typed = field_box(c, add_key, tr("web-mobile.profiles.addModelPlaceholder"), mono=true)
          .trim(chars=" \t\n")
          .to_string()
        if adding {
          spinner(c)
        } else if tap_text(
            c,
            "models-add",
            tr("web-mobile.profiles.addModel"),
            size=14.0,
            color?=if typed == "" { Some(t.p.muted) } else { None },
          ) &&
          typed != "" {
          let model = typed
          field_of(add_key).set("")
          act(
            core,
            tr("android-settings.models.refreshWhat"),
            "profile.addModel",
            obj([("station", str(station)), ("id", str(id)), ("model", str(model))]),
          )
        }
      })
      |> ignore
    })
  }
  // a filter, where there are many
  if all.length() > models_filter_from {
    blocks.push(fn() {
      c.box(style=models_filter_room, fn() { field_box(c, filter_key, tr("android-settings.models.filter")) |> ignore })
      |> ignore
    })
  }
  for series in items(pv, "series") {
    let list = strings(Some(series), "models").filter(fn(m) { shown.contains(m) })
    if list.length() == 0 {
      continue
    }
    blocks.push(fn() {
      c.box(w=Fill(1.0), padx=24.0, pt=14.0, pb=2.0, fn() {
        c.text(text(Some(series), "name"), size=13.0, color=t.p.muted, wrap=false, line=18.0) |> ignore
      })
      |> ignore
      for m in list {
        let ticked = models.contains(m)
        let mid = c.id("model/" + m)
        if hit(c, mid) && !saving {
          save(if ticked { models.filter(fn(x) { x != m }) } else { models.copy()..push(m) })
        }
        c.box(
          dir=Row,
          w=Fill(1.0),
          padx=24.0,
          pady=11.0,
          gap=12.0,
          align=ACenter,
          id=mid,
          fn() {
            c.box(w=Px(20.0), h=Px(20.0), radius=6.0, bg=if ticked { t.p.accent } else { t.p.chip }, align=ACenter, justify=JCenter, fn() {
              if ticked {
                @sf.icon(c, "check", size=13.0, color=t.p.bg) |> ignore
              }
            })
            |> ignore
            let name = text(field(pv, "names"), m)
            c.text(if name == "" { m } else { name }, size=14.0, color=t.p.text, wrap=false, w=Fill(1.0), line=20.0)
            |> ignore
            if pending.contains(m) {
              spinner(c, inline=true)
            }
            // Profiles.kt ModelsSection: the row clickable
            @motion.ripple(c, mid, 0.0)
          },
        )
        |> ignore
      }
    })
  }
  blocks
}

///|
/// A filter over the models once there are more than ten of them (Profiles.kt ModelsSection).
let models_filter_from : Int = 10

///|
/// The filter's room: at the rows' words (24 in), 8 under it.
// kept across runs: a value (no field of it changes)
let models_filter_room : @ui.Style = @ui.css("w=Full px=S6 pb=S2")

///|
/// A model named by hand: its field and 添加 beside it, 12 apart, at the rows' words, 8 under them.
// kept across runs: a value (no field of it changes)
let models_add_row : @ui.Style = @ui.css("row w=Full px=S6 pb=S2 gap=S3 align=ACenter")

///|
/// A grouped profile's allowance, a line under its words (Profiles.kt: padding top 6).
// kept across runs: a value (no field of it changes)
let quota_line : @ui.Style = @ui.css("pt=S1_5")

///|
/// Whose the machine's own login is, 14 under where it stands (Profiles.kt: padding(top = 14)).
// kept across runs: a value (no field of it changes)
let machine_login_room : @ui.Style = @ui.css("w=Full pt=S3_5")
