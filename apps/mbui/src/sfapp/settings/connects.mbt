// Connects, the Slack apps the agents answer in (settings/Connects.kt; the core's `connects` view): every station's on
// one page, all or those the viewer made (the filter in the bar), each station's under its name; a station offline says
// so. A connect's page: who it is in Slack, what is wrong with its link, how it runs (its model, how its conversations
// become sessions, the one it delivers into), its recent sessions, each opening its chat. (Making one, its sheets and
// "…", its Slack app's page are a later slice's.)

///|
/// All the connects, or the viewer's (ConnectsScreen's filter), while the page is on the stack.
let connects_mine : Ref[Bool] = Ref(false)

///|
/// How a connect's conversations become sessions, in words (Words.kt MODE_LABEL, MODE_TEXT).
/// A Feishu connect's (`kind` feishu) in its groups' words (modeLabel, modeText).
fn mode_label(mode : String, kind? : String = "") -> String {
  match (mode, kind == "feishu") {
    ("multi-session", false) => tr("android-misc.mode.multi")
    ("single-session", false) => tr("android-misc.mode.single")
    ("multi-session", true) => tr("web-main.mode.feishu.multi.label")
    ("single-session", true) => tr("web-main.mode.feishu.single.label")
    (m, _) => m
  }
}

///|
fn mode_text(mode : String, kind? : String = "") -> String {
  match (mode, kind == "feishu") {
    ("multi-session", false) => tr("android-misc.mode.multi.text")
    ("single-session", false) => tr("android-misc.mode.single.text")
    ("multi-session", true) => tr("web-main.mode.feishu.multi.description")
    ("single-session", true) => tr("web-main.mode.feishu.single.description")
    _ => ""
  }
}

///|
/// A connect as its people see it in Slack (ConnectAvatar): its bot's picture; Slack's mark until Slack said it.
fn connect_avatar(c : @ui.Ctx, core : Core, cv : Json?, size : Double) -> Unit {
  match opt_text(cv, "botImage") {
    Some(image) => avatar(c, core, text(cv, "id"), text(cv, "name"), size, picture=image)
    None =>
      c.box(w=Px(size), h=Px(size), align=ACenter, justify=JCenter, fn() {
        if text(cv, "kind") == "feishu" {
          @sf.feishu_mark(c, size * 0.55) |> ignore
        } else {
          @sf.slack_mark(c, size * 0.55) |> ignore
        }
      })
      |> ignore
  }
}

///|
/// A connect in its station's list (ConnectRow): its bot's picture and name, how it runs, its presence.
fn connect_row(c : @ui.Ctx, core : Core, station : String, cv : Json?) -> Unit {
  let t = @sf.theme()
  if list_row(c, key="connect/" + station + "/" + text(cv, "id"), fn() {
      connect_avatar(c, core, cv, 30.0)
      let bind = field(cv, "bind")
      row_lines(
        c,
        text(cv, "name") +
        (match opt_text(cv, "team") {
          Some(team) => " · " + team
          None => ""
        }),
        join(
          [
            text(cv, "modeText"),
            text(cv, "runtimeText"),
            match opt_text(bind, "model") {
              Some(m) => opt_text(cv, "modelName").unwrap_or(m)
              None => ""
            },
          ],
          " · ",
        ),
        wrap_title=false,
      )
      c.box(dir=Row, gap=5.0, align=ACenter, fn() {
        presence_dot(c, text(cv, "presence"))
        c.text(text(cv, "statusText"), size=12.0, color=t.p.muted, wrap=false) |> ignore
      })
      |> ignore
    }) {
    (core.push)(Connect(station, text(cv, "id")))
  }
}

///|
fn connects_page(c : @ui.Ctx, core : Core, here : Here, only : String) -> Unit {
  let t = @sf.theme()
  let mine = connects_mine.val
  let topic = (core.topic)("connects", { "scope": str(here.workspace), "mine": Json::boolean(mine) })
  let st = stations_of(core, here)
  let stations = match st.value {
    Some(Array(a)) => Some(if only == "" { a } else { a.filter(fn(x) { text(Some(x), "station") == only }) })
    _ => None
  }
  let one = match stations {
    Some(a) if only != "" && a.length() > 0 => Some(a[0])
    _ => None
  }
  let view = topic.value
  let filters = [tr("android-settings.connects.all"), tr("android-settings.connects.mine")]
  let add = match place_action(core, here, "connects") {
    Some(run) => Some(("add-connect", run))
    None => None
  }
  place_page(
    c,
    core,
    tr("android-settings.connects.title"),
    primary?=add,
    back=match one {
      Some(o) => text(Some(o), "name")
      None => tr("android-settings.title")
    },
    actions=fn() {
      band_filter(c, "connects-filter", filters, if mine { 1 } else { 0 }, fn(i) { connects_mine.val = i == 1 })
    },
    fn() {
      let blocks : Array[() -> Unit] = []
      let list = items(view, "items")
      let wait = field(view, "wait")
      let no_apps = match stations {
        Some(a) => a.iter().all(fn(x) { items(field(Some(x), "overview"), "slackApps").length() == 0 })
        None => true
      }
      let none = view is Some(_) && list.length() == 0 && no_apps
      match (stations, view) {
        (Some(a), Some(_)) =>
          if one is None && none && note_waits(wait) {
            blocks.push(fn() { waiting_rows(c, failing=failing_of(wait)) })
          } else {
            for s in a {
              let sv = Some(s)
              let address = text(sv, "station")
              let here_list = list.filter(fn(x) { text(Some(x), "station") == address })
              let waiting = items(field(sv, "overview"), "slackApps")
              let online = flag(sv, "online")
              if online && here_list.length() == 0 && waiting.length() == 0 && mine && one is None {
                continue
              }
              if one is None {
                blocks.push(fn() {
                  section_header(
                    c,
                    if online {
                      text(sv, "name")
                    } else {
                      fill("android-settings.connects.offline", [("name", text(sv, "name"))])
                    },
                    start=S6,
                  )
                })
              }
              blocks.push(fn() {
                list_card(c, fn() {
                  if !online && here_list.length() == 0 {
                    list_row(c, fn() { row_title(c, tr("android-settings.connects.stationOffline"), color=t.p.muted) })
                    |> ignore
                  } else if here_list.length() == 0 && waiting.length() == 0 {
                    list_row(c, fn() {
                      if field(sv, "overview") is Some(Object(_)) {
                        row_title(c, tr("android-settings.connects.empty"), color=t.p.muted)
                      } else {
                        wait_line(c, tr("common.reading"))
                      }
                    })
                    |> ignore
                  }
                  for x in here_list {
                    connect_row(c, core, address, field(Some(x), "connect"))
                  }
                  // the Slack apps made here that no connect has taken yet: to be finished any time
                  for app in waiting {
                    waiting_app(c, core, address, app, online)
                  }
                })
              })
            }
          }
        _ =>
          blocks.push(fn() {
            waiting_rows(
              c,
              error=match (topic.error, st.error) {
                (Some(e), _) | (_, Some(e)) => error_text(e)
                _ => ""
              },
            )
          })
      }
      if one is None && none && !note_waits(wait) {
        blocks.push(fn() { place_empty(c, fill("android-settings.connects.note", [("app", "still.fail")])) })
      }
      blocks.push(fn() { gap(c, 30.0) })
      scroll_page(c, "connects/" + only + "/" + mine.to_string(), blocks)
    },
  )
}

///|
/// A connect's page (ConnectScreen).
fn connect_page(c : @ui.Ctx, core : Core, here : Here, station : String, id : String) -> Unit {
  let t = @sf.theme()
  let topic = (core.topic)("connects", { "scope": str(workspace_of(station)), "mine": Json::boolean(false) })
  let view = topic.value
  let item = items(view, "items").iter().find_first(fn(x) {
    text(Some(x), "station") == station && text(field(Some(x), "connect"), "id") == id
  })
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    match item {
      None => {
        nav_bar(c, core, tr("android-settings.connects.title"), tr("android-settings.connects.title"))
        let wait = field(view, "wait")
        if view is None || topic.error is Some(_) {
          waiting_cards(
            c,
            error=match topic.error {
              Some(e) => error_text(e)
              None => ""
            },
          )
        } else if note_waits(wait) {
          waiting_cards(c, failing=failing_of(wait))
        } else {
          place_empty(c, tr("android-settings.connects.none"))
        }
      }
      Some(it) => {
        let iv = Some(it)
        let cv = field(iv, "connect")
        let link = field(cv, "connection")
        let bind = field(cv, "bind")
        let mode = text(cv, "mode")
        nav_bar(c, core, tr("android-settings.connects.title"), text(cv, "name"), trailing=fn() {
          if nav_button(c, "connect-more", "more") {
            open_connect_menu(core, here, station, iv)
          }
        }, sub=fn() {
          presence_dot(c, text(cv, "presence"))
          c.text(text(cv, "statusText"), size=11.0, color=t.p.muted, wrap=false, line=16.0) |> ignore
        })
        let state = text(link, "state")
        let blocks : Array[() -> Unit] = [
          fn() { gap(c, 12.0) },
          fn() {
            card(c, fn() {
              c.box(dir=Row, w=Fill(1.0), gap=12.0, align=ACenter, fn() {
                connect_avatar(c, core, cv, 44.0)
                row_lines(
                  c,
                  opt_text(cv, "team").unwrap_or("Slack"),
                  text(iv, "stationName") +
                  (match field(cv, "createdBy") {
                    Some(Object(_)) as by => {
                      let shown = text(field(by, "shown"), "display")
                      fill("android-settings.connect.owner", [("name", if shown != "" { shown } else { text(by, "name") })])
                    }
                    _ => ""
                  }),
                  wrap_title=false,
                )
                let calls = ["connect.reconnect", "connect.put"]
                let on = [("station", station), ("id", id)]
                doing_mark(c, is_doing(core, calls, on), failed_of(core, calls, on))
              })
              |> ignore
            })
            |> ignore
          },
        ]
        let feishu = field(cv, "feishu")
        if (state == "no_tokens" && !(feishu is Some(Object(_)))) || state == "error" || (state == "reconnecting" && has(link, "lastError")) {
          blocks.push(fn() {
            c.box(w=Fill(1.0), padx=12.0, pb=10.0, fn() {
              c.box(w=Fill(1.0), padx=12.0, pady=10.0, radius=12.0, bg=@sf.alpha(warn, 0.12), fn() {
                if state == "no_tokens" {
                  c.box(dir=Row, w=Fill(1.0), gap=8.0, align=ACenter, fn() {
                    c.text(tr("android-settings.connect.noTokens"), size=13.0, color=t.p.text, wrap=false, line=18.0) |> ignore
                    if tap_text(c, "connect-fill-tokens", tr("android-settings.connect.fillTokens"), size=13.0) {
                      open_tokens(core, station, cv)
                    }
                  })
                  |> ignore
                  return
                }
                c.text(
                  if state == "no_tokens" {
                    tr("android-settings.connect.noTokens")
                  } else if state == "error" {
                    text(link, "error")
                  } else {
                    fill("android-settings.connect.reconnecting", [("error", text(link, "lastError"))])
                  },
                  size=13.0,
                  color=t.p.text,
                  w=Fill(1.0),
                  line=18.0,
                )
                |> ignore
              })
              |> ignore
            })
            |> ignore
          })
        }
        blocks.append([
          fn() { section_header(c, tr("android-settings.connect.run"), start=S6) },
          fn() {
            list_card(c, fn() {
              let label = fn(words : String) {
                c.box(min_w=32.0, fn() {
                  c.text(words, size=13.0, color=t.p.muted, wrap=false, line=18.0) |> ignore
                })
                |> ignore
              }
              if list_row(c, key="connect-run", fn() {
                label(tr("android-settings.connect.model"))
                row_title(
                  c,
                  join(
                    [
                      match opt_text(bind, "model") {
                        Some(m) => opt_text(cv, "modelName").unwrap_or(m)
                        None => tr("android-settings.connect.pickModel")
                      },
                      match text(bind, "effort") {
                        "" => tr("android-settings.connect.defaultEffort")
                        e => e
                      },
                      if has(bind, "profile") {
                        tr("android-settings.connect.fixedAccount")
                      } else {
                        tr("android-settings.connect.autoAccount")
                      },
                    ],
                    " · ",
                  ),
                )
                chevron(c)
              }) {
                (core.push)(ConnectRun(station, id))
              }
              if list_row(c, key="connect-mode", fn() {
                label(tr("android-settings.connect.sessions"))
                row_lines(
                  c,
                  mode_label(mode, kind=text(cv, "kind")),
                  mode_text(mode, kind=text(cv, "kind")) +
                  (if mode == "single-session" {
                    if flag(cv, "requireMention") {
                      tr("android-settings.connect.mentionOnly")
                    } else {
                      tr("android-settings.connect.everyMessage")
                    }
                  } else {
                    ""
                  }),
                  wrap_sub=true,
                )
                chevron(c)
              }) {
                open_mode(core, station, iv)
              }
              if mode == "single-session" {
                if list_row(c, key="connect-session", fn() {
                  label(tr("android-settings.connect.current"))
                  let bound = field(iv, "bound")
                  row_title(
                    c,
                    match bound {
                      Some(Object(_)) => text(bound, "titleText")
                      _ => tr("android-settings.connect.noSession")
                    },
                    color=if bound is Some(Object(_)) { t.p.text } else { t.p.muted },
                  )
                  let on = [("station", station), ("connect", id)]
                  doing_mark(c, is_doing(core, ["connect.bindSession"], on), failed_of(core, ["connect.bindSession"], on))
                  chevron(c)
                }) {
                  open_session(core, station, iv)
                }
              }
            })
            c.box(w=Fill(1.0), padx=24.0, pady=4.0, fn() {
              c.text(fill("android-settings.connect.runtime", [("runtime", text(cv, "runtimeText"))]), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0)
              |> ignore
            })
            |> ignore
          },
          // a Feishu connect's app (its App ID, its secret replaced from here); a Slack one's Slack app
          fn() {
            section_header(c, if text(cv, "kind") == "feishu" { tr("web-mobile.connects.feishu.section") } else { "Slack app" }, start=S6)
          },
          fn() {
            if field(cv, "feishu") is Some(Object(_)) {
              feishu_section(c, core, station, cv)
            } else if text(cv, "kind") != "feishu" {
              list_card(c, fn() {
                if list_row(c, key="connect-slack-app", fn() {
                  @sf.slack_mark(c, 16.0) |> ignore
                  row_lines(c, tr("android-settings.slack.sub"), tr("android-settings.connect.slackAppNote"))
                  chevron(c)
                }) {
                  (core.push)(SlackApp(station, id))
                }
              })
            }
          },
          fn() { section_header(c, tr("android-settings.connect.recent"), start=S6) },
          fn() {
            list_card(c, fn() {
              let sessions = items(iv, "sessions")
              if sessions.length() == 0 {
                list_row(c, fn() {
                  row_title(
                    c,
                    fill(if text(cv, "kind") == "feishu" { "web-mobile.connects.noSessions.feishu" } else { "android-settings.connect.noSessions" }, [("name", text(cv, "name"))]),
                    color=t.p.muted,
                  )
                })
                |> ignore
              }
              for x in sessions {
                let xv = Some(x)
                if list_row(c, key="connect-session/" + text(xv, "key"), fn() {
                    row_title(c, text(xv, "titleText"))
                    c.text(text(xv, "statusText"), size=13.0, color=t.p.muted, wrap=false) |> ignore
                  }) {
                  (core.open_chat)(station, text(xv, "key"), text(xv, "titleText"))
                }
              }
            })
          },
          fn() { gap(c, 30.0) },
        ])
        scroll_page(c, "connect/" + station + "/" + id, blocks)
      }
    }
  })
  |> ignore
}
