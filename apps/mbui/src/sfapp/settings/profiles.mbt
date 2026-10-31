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
        blocks.append(machine_login_offers(c, core, sv, fn(_) { (core.push)(NewProfile(station)) }))
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
              fn() {
                for g in group_by(profiles_sample().map(fn(e) { field(Some(e), "profile").unwrap() })) {
                  section_header(c, g.1, mark=Some(fn() { group_mark(c, g.0) }), start=S6)
                  list_card(c, fn() {
                    for p in g.2 {
                      profile_row(c, core.quiet(), "sample", p)
                    }
                  })
                }
              },
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
/// A kind of account's mark, before its section's title (Profiles.kt GroupMark), and before an account's row of 全部密钥:
/// its vendor's for a subscription, a key for keys.
pub fn group_mark(c : @ui.Ctx, group : String) -> Unit {
  match group {
    "key" => @sf.icon(c, "key", size=16.0, color=@sf.theme().p.text) |> ignore
    // signed in to an account: its provider's
    "kimi" => @sf.provider_logo(c, "claude", "api-provider", 16.0, "kimi")
    "opencode" => @sf.provider_logo(c, "claude", "opencode-go", 16.0, "")
    // a subscription: its vendor's, by the runtime it is (ChatGPT's Codex; SuperGrok's xAI, Cursor's, Devin's)
    "chatgpt" => @sf.provider_logo(c, "codex", "subscription", 16.0, "")
    "" => @sf.provider_logo(c, "claude", "subscription", 16.0, "")
    g => @sf.provider_logo(c, g, "subscription", 16.0, "")
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
            fn() { profile_list_sample(c, core) },
            error=match topic.error {
              Some(e) => error_text(e)
              None => ""
            },
          )
        },
      ]
    Some(_) if list.length() == 0 && note_waits(wait) =>
      return [fn() { waiting_rows(c, fn() { profile_list_sample(c, core) }, failing=failing_of(wait)) }]
    _ => ()
  }
  let blocks : Array[() -> Unit] = []
  if list.length() == 0 {
    blocks.push(fn() {
      list_card(c, fn() {
        list_row(c, fn() { row_title(c, tr("web-pages.settings.profiles.none"), color=t.p.muted) }) |> ignore
      })
      place_empty(c, tr("android-settings.profiles.note"))
    })
  }
  blocks.append(profile_list_blocks(c, core, list))
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
/// The workspace's profiles (`list`, the core's entries), a section a kind of account with its card of rows.
fn profile_list_blocks(c : @ui.Ctx, core : Core, list : Array[Json]) -> Array[() -> Unit] {
  let t = @sf.theme()
  let blocks : Array[() -> Unit] = []
  for g in profile_groups(list) {
    blocks.append([
      fn() { section_header(c, g.0, mark=Some(fn() { group_mark(c, text(g.1.get(0), "group")) }), start=S6) },
      fn() {
        list_card(c, fn() {
          for e in g.1 {
            let ev = Some(e)
            let p = field(ev, "profile")
            let usable = flag(ev, "usable")
            // how it is where that is not simply fine, as the core says it (a dot in its tone; none while fine): what
            // needs a look said in its line
            let state = field(ev, "state")
            if list_row(c, key="ws-profile/" + text(ev, "key"), fn() {
                c.box(w=Fill(1.0), opacity=if usable { 1.0 } else { 0.55 }, fn() {
                  c.box(dir=Row, w=Fill(1.0), gap=6.0, align=ACenter, fn() {
                    if state is Some(Object(_)) {
                      presence_dot(c, tone_dot(text(state, "tone")))
                    }
                    // (a subscription by its account, a key by its name: the core's)
                    let title = match text(ev, "title") {
                      "" => text(p, "name")
                      x => x
                    }
                    c.text(title, size=t.t.ui, color=t.p.text, wrap=false, w=@sf.line_left, line=21.0) |> ignore
                  })
                  |> ignore
                  let line = if flag(ev, "look") {
                    text(state, "text")
                  } else if text(ev, "where") != "" {
                    text(ev, "where")
                  } else {
                    join(
                      [
                        text(p, "checkText"),
                        match text(p, "usesText") {
                          "" => text(p, "kindText")
                          u => u
                        },
                      ],
                      " · ",
                    )
                  }
                  c.text(line, size=t.t.meta, color=t.p.muted, wrap=false, w=Fill(1.0), line=18.0) |> ignore
                  // its allowance a line of its own, so the name and where it is keep the row's width (Profiles.kt)
                  if usable && text(field(p, "quota"), "state") == "ok" && items(field(p, "quota"), "windows").length() > 0 {
                    // (in its row's corner, 12 in: the row's corner concentric round its own, @sf.fill_chip_corner)
                    // (each window in words, 每周剩余 78%: a row has the room, and a touch has no tip to say what W is)
                    c.box(style=quota_line, fn() {
                      @sf.quota_chips(c, field(p, "quota"), worded=true, key="ws-profile/" + text(ev, "key"))
                    })
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
  blocks
}

///|
/// The workspace's profiles made up, for what is shown while they are read (in their bones): an account's kind with
/// three of them.
fn profiles_sample() -> Array[Json] {
  [(8, 14), (6, 18), (9, 12)].mapi(fn(i, n) {
    Json::object({
      "key": Json::string("sample" + i.to_string()),
      "usable": true,
      "group": "",
      "groupTitle": Json::string(@sf.sample_words(4)),
      "where": Json::string(@sf.sample_words(n.1)),
      "profile": {
        "id": Json::string("sample" + i.to_string()),
        "name": Json::string(@sf.sample_words(n.0)),
        "group": "",
        "groupTitle": Json::string(@sf.sample_words(4)),
        "kindText": Json::string(@sf.sample_words(n.1)),
      },
    })
  })
}

///|
/// The workspace's profiles to come (profile_list_blocks of made-up ones), drawn in turn.
fn profile_list_sample(c : @ui.Ctx, core : Core) -> Unit {
  for b in profile_list_blocks(c, core.quiet(), profiles_sample()) {
    b()
  }
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
          c.text(text(pv, "name"), size=t.t.ui, color=t.p.text, wrap=false, w=@sf.line_left, line=21.0) |> ignore
        })
        |> ignore
        c.text(
          join(
            [
              text(pv, "checkText"),
              if flag(pv, "machine") {
                text(pv, "kindText")
              } else {
                match text(pv, "usesText") {
                  "" => text(pv, "kindText")
                  u => u
                }
              },
              text(pv, "modelsText"),
            ],
            " · ",
          ),
          size=t.t.meta,
          color=t.p.muted,
          wrap=false,
          w=Fill(1.0),
          line=18.0,
        )
        |> ignore
        match field(pv, "trouble") {
          Some(Object(_)) as tr_ => {
            c.text(text(tr_, "title") + " · " + text(tr_, "detail"), size=t.t.meta, color=t.p.muted, w=Fill(1.0), line=18.0)
            |> ignore
            c.text(tr("android-settings.profile.seeFix"), size=@sf.theme().t.meta, color=@sf.link_ink(), wrap=false, line=18.0) |> ignore
          }
          _ => {
            let trouble = quota_trouble(field(pv, "quota"))
            if trouble != "" {
              c.text(trouble, size=t.t.meta, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
            }
          }
        }
      })
      |> ignore
      let calls = ["profile.check", "profile.quota"]
      let on = [("station", station), ("id", id)]
      doing_mark(c, is_doing(core, calls, on), failed_of(core, calls, on))
      @sf.quota_chips(c, field(pv, "quota"))
      chevron(c)
    }) {
    (core.push)(Profile(station, id))
  }
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
                size=t.t.body,
                color=t.p.text,
                line=21.0,
              )
              |> ignore
            })
            |> ignore
            c.text(trouble, size=t.t.meta, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
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
            c.text(credits, size=t.t.meta, color=t.p.muted, wrap=false) |> ignore
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
            row_lines(c, tr("android-settings.quota.resets"), text(q, "resetText"), end=fn() {
              doing_mark(c, resetting, failed_of(core, ["profile.resetQuota"], on))
              c.text(tr("android-settings.quota.reset"), style=if left > 0 { @sf.value.then(@sf.link) } else { @sf.value })
              |> ignore
            })
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
      let tone = @sf.level_color(level)
      let low = level == "amber" || level == "red"
      let left = clamp(count(wv, "left"))
      let lit = (left.to_double() / 10.0 + 0.5).floor().to_int()
      c.box(min_w=96.0, gap=2.0, fn() {
        dial_figure(c, left.to_string(), "%", if low { tone } else { t.p.text })
        c.box(dir=Row, pt=4.0, pb=6.0, gap=2.0, fn() {
          for i in 0..<10 {
            c.box(w=Px(7.0), h=Px(14.0), radius=2.0, bg=if i < lit { tone } else { t.p.line }, fn() {  }) |> ignore
          }
        })
        |> ignore
        c.text(text(wv, "label"), size=t.t.meta, weight=500, color=t.p.text, wrap=false, line=18.0) |> ignore
        c.text(
          match text(wv, "refills") {
            "" => " "
            r => r
          },
          size=t.t.caption,
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
/// A grouped profile's allowance, a line under its words (Profiles.kt: padding top 6).
// kept across runs: a value (no field of it changes)
let quota_line : @ui.Style = @ui.css("w=Full pt=S1_5")

