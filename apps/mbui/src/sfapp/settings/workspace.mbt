// The workspace itself, from settings (settings/Settings.kt WorkspaceScreen, still.fail cloud's `workspace` topic): its
// name as the title (its owners and admins rename it with a tap), its people in one list (those in it, those added who
// have not signed in, the invitations out), its own relays, leaving or deleting it at the bottom. A person's row opens
// what can be done about them (their role, moving them out).

///|
fn workspace_page(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let t = @sf.theme()
  let topic = workspace_view(core, here)
  let v = topic.value
  let role = text(v, "role")
  let manager = role == "owner" || role == "admin"
  let members = items(v, "members")
  let added = items(v, "added")
  let invitations = items(v, "invitations")
  let relays = strings(v, "relays")
  let ws = text(v, "id")
  let blocks : Array[() -> Unit] = [
    fn() {
      // (adding people by email or from Slack is a later slice's sheet: its ＋ is not shown yet)
      top_back(c, core, tr("android-settings.title"))
    },
  ]
  if v is None {
    blocks.push(fn() {
      waiting_cards(
        c,
        error=match topic.error {
          Some(e) => error_text(e)
          None => ""
        },
      )
    })
    scroll_page(c, "workspace", blocks)
    return
  }
  let waiting = if manager { added.length() + invitations.length() } else { 0 }
  let n = members.length().to_string()
  blocks.append([
    fn() {
      let id = c.id("ws-name")
      if manager && hit(c, id) {
        ask(
          tr("android-settings.workspace.name"),
          text(v, "name"),
          tr("android-settings.workspace.namePlaceholder"),
          tr("common.save"),
          fn(line) {
            act(
              core,
              tr("android-settings.workspace.renameWhat"),
              "workspace.rename",
              obj([("workspace", str(ws)), ("name", str(line)), ("account", str(here.sub))]),
              done=tr("android-settings.renamed"),
            )
          },
        )
      }
      c.box(w=Fill(1.0), id=if manager { id } else { 0 }, fn() {
        let emoji = text(v, "emoji")
        let icon = text(v, "icon")
        if @sf.has_station_mark(emoji, icon) {
          large_title(c, text(v, "name"), lead=fn() { @sf.station_mark(c, emoji, icon, 30.0, t.p.text) })
        } else {
          large_title(c, text(v, "name"))
        }
      })
      |> ignore
    },
    fn() {
      c.box(w=Fill(1.0), pl=20.0, pr=20.0, pb=4.0, fn() {
        c.text(
          fill(
            if manager {
              "android-settings.workspace.aboutRename"
            } else {
              "android-settings.workspace.about"
            },
            [
              ("role", role_label(role)),
              ("people", fill("android-settings.members.count", [("n", n)])),
              ("stations", fill("android-settings.workspace.stations", [("n", items(v, "stations").length().to_string())])),
            ],
          ),
          size=13.0,
          color=t.p.muted,
          w=Fill(1.0),
          line=18.0,
        )
        |> ignore
      })
      |> ignore
    },
  ])
  if manager {
    blocks.push(fn() {
      gap(c, 10.0)
      list_card(c, fn() {
        // (its mark is picked in the station's picker, a later slice's: the row says what it is)
        list_row(c, fn() {
          row_title(c, tr("android-settings.workspace.icon"))
          let busy = is_doing(core, ["workspace.rename"], [("workspace", ws)])
          doing_mark(c, busy, failed_of(core, ["workspace.rename"], [("workspace", ws)]))
          let emoji = text(v, "emoji")
          let icon = text(v, "icon")
          if @sf.has_station_mark(emoji, icon) {
            @sf.station_mark(c, emoji, icon, 20.0, t.p.text)
          } else {
            c.text(tr("android-settings.workspace.iconNone"), size=14.0, color=t.p.muted, wrap=false) |> ignore
          }
          chevron(c)
        })
        |> ignore
      })
    })
  }
  blocks.append([
    fn() {
      section_header(
        c,
        tr("android-settings.members.title"),
        trailing=if waiting > 0 {
          fill("android-settings.members.waiting", [("n", n), ("waiting", waiting.to_string())])
        } else {
          fill("android-settings.members.count", [("n", n)])
        },
      )
    },
    fn() {
      list_card(c, fn() {
        for m in members {
          member_row(c, core, here, v, m)
        }
        if manager {
          for a in added {
            let email = text(Some(a), "email")
            list_row(c, fn() {
              avatar(c, core, email, email, 28.0)
              row_lines(
                c,
                email,
                fill("android-settings.members.added", [("role", role_label(text(Some(a), "role")))]),
              )
              let on = [("workspace", ws), ("email", email)]
              if row_action(
                  c,
                  "remove-added/" + email,
                  tr("android-settings.members.remove"),
                  is_doing(core, ["workspace.removeAdded"], on),
                  failed_of(core, ["workspace.removeAdded"], on),
                ) {
                act(
                  core,
                  tr("android-settings.members.removeWhat"),
                  "workspace.removeAdded",
                  obj([("workspace", str(ws)), ("email", str(email)), ("account", str(here.sub))]),
                  done=tr("android-settings.members.removed"),
                )
              }
            })
            |> ignore
          }
          for i in invitations {
            let iv = Some(i)
            let id = text(iv, "id")
            let email = text(iv, "email")
            list_row(c, fn() {
              avatar(c, core, if email != "" { email } else { id }, if email != "" { email } else { "?" }, 28.0)
              row_lines(
                c,
                if email != "" {
                  email
                } else {
                  tr("android-settings.members.anyone")
                },
                fill("android-settings.members.invitation", [
                  ("role", role_label(text(iv, "role"))),
                  ("until", stamp(iv, "expires_at", "until")),
                ]),
              )
              let on = [("workspace", ws), ("invitation", id)]
              if row_action(
                  c,
                  "revoke/" + id,
                  tr("android-settings.members.revoke"),
                  is_doing(core, ["workspace.revokeInvitation"], on),
                  failed_of(core, ["workspace.revokeInvitation"], on),
                ) {
                act(
                  core,
                  tr("android-settings.members.revokeWhat"),
                  "workspace.revokeInvitation",
                  obj([("workspace", str(ws)), ("invitation", str(id)), ("account", str(here.sub))]),
                  done=tr("android-settings.members.revoked"),
                )
              }
            })
            |> ignore
          }
        }
      })
    },
  ])
  // the workspace's own relays (Settings.kt Relays): a row each, the way to add one
  if manager || relays.length() > 0 {
    blocks.append([
      fn() { section_header(c, tr("android-settings.relays.title")) },
      fn() {
        list_card(c, fn() {
          let busy = is_doing(core, ["workspace.setRelays"], [("workspace", ws)])
          for url in relays {
            list_row(c, fn() {
              row_title(c, url.replace(old="https://", new="").replace(old="http://", new=""))
              if manager &&
                row_action(c, "relay/" + url, tr("android-settings.members.remove"), busy, None) {
                act(
                  core,
                  tr("android-settings.relays.removeWhat"),
                  "workspace.setRelays",
                  obj([
                    ("workspace", str(ws)),
                    ("relays", Json::array(relays.filter(fn(r) { r != url }).map(str))),
                    ("account", str(here.sub)),
                  ]),
                  done=tr("android-settings.relays.removed"),
                )
              }
            })
            |> ignore
          }
          if manager &&
            list_row(c, key="relay-add", fn() {
              c.text(
                tr(if busy { "common.saving" } else { "android-settings.relays.add" }),
                size=15.0,
                color=t.p.accent,
                wrap=false,
                line=21.0,
              )
              |> ignore
            }) &&
            !busy {
            ask(
              tr("android-settings.relays.add"),
              "",
              "https://relay.example.com",
              tr("android-settings.relays.addAction"),
              hint=tr("android-settings.relays.hint"),
              fn(line) {
                let next = relays.copy()
                next.push(line)
                act(
                  core,
                  tr("android-settings.relays.add"),
                  "workspace.setRelays",
                  obj([("workspace", str(ws)), ("relays", Json::array(next.map(str))), ("account", str(here.sub))]),
                  done=tr("android-settings.relays.added"),
                )
              },
            )
          }
        })
        c.box(w=Fill(1.0), pl=20.0, pr=20.0, pt=6.0, fn() {
          c.text(fill("android-settings.relays.lead", [("app", "still.fail")]), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0)
          |> ignore
        })
        |> ignore
      },
    ])
  }
  blocks.append([
    fn() { gap(c, 18.0) },
    fn() {
      list_card(c, fn() {
        if list_row(c, key="ws-leave", fn() {
            c.text(tr("android-settings.workspace.leaveRow"), size=15.0, color=t.p.red, wrap=false, line=21.0)
            |> ignore
          }) {
          confirm(
            fill("android-settings.workspace.leaveTitle", [("name", text(v, "name"))]),
            tr("android-settings.workspace.leaveText"),
            tr("android-settings.workspace.leave"),
            danger=true,
            fn() {
              (core.home)()
              act(
                core,
                tr("android-settings.workspace.leaveWhat"),
                "workspace.removeMember",
                obj([("workspace", str(ws)), ("member", str(here.sub)), ("account", str(here.sub))]),
                done=tr("android-settings.workspace.left"),
              )
            },
          )
        }
        if role == "owner" &&
          list_row(c, key="ws-delete", fn() {
            c.text(tr("android-settings.workspace.delete"), size=15.0, color=t.p.red, wrap=false, line=21.0)
            |> ignore
          }) {
          confirm(
            fill("android-settings.workspace.deleteTitle", [("name", text(v, "name"))]),
            fill("android-settings.workspace.deleteText", [
              ("n", items(v, "stations").length().to_string()),
              ("app", "still.fail"),
            ]),
            tr("android-settings.workspace.delete"),
            danger=true,
            fn() {
              (core.home)()
              act(
                core,
                tr("android-settings.workspace.deleteWhat"),
                "workspace.delete",
                obj([("workspace", str(ws)), ("account", str(here.sub))]),
                done=tr("android-settings.workspace.deleted"),
              )
            },
          )
        }
      })
    },
    fn() { gap(c, 30.0) },
  ])
  scroll_page(c, "workspace", blocks)
}

///|
/// A person of the workspace (Settings.kt MemberRow): their picture, name (你 for the viewer) and email, their role;
/// the owner changes their role, a manager moves them out (an owner only by an owner).
fn member_row(c : @ui.Ctx, core : Core, here : Here, v : Json?, m : Json) -> Unit {
  let t = @sf.theme()
  let mv = Some(m)
  let sub = text(mv, "sub")
  let email = text(mv, "email")
  let name = match text(mv, "name") {
    "" => email
    x => x
  }
  let role = text(v, "role")
  let manager = role == "owner" || role == "admin"
  let ws = text(v, "id")
  let can = sub != here.sub && manager && (text(mv, "role") != "owner" || role == "owner")
  if list_row(c, key=if can { "member/" + sub } else { "" }, fn() {
      avatar(c, core, email, name, 28.0, picture=text(mv, "picture"))
      c.box(w=Fill(1.0), fn() {
        c.box(dir=Row, gap=6.0, align=ACenter, fn() {
          c.text(name, size=15.0, color=t.p.text, wrap=false, line=21.0) |> ignore
          if sub == here.sub {
            you(c, tr("android-settings.members.you"))
          }
        })
        |> ignore
        c.text(email, size=13.0, color=t.p.muted, wrap=false, w=Fill(1.0), line=18.0) |> ignore
      })
      |> ignore
      let on = [("workspace", ws), ("member", sub)]
      let calls = ["workspace.setRole", "workspace.removeMember"]
      doing_mark(c, is_doing(core, calls, on), failed_of(core, calls, on))
      c.text(role_label(text(mv, "role")), size=13.0, color=t.p.muted, wrap=false) |> ignore
    }) {
    member_sheet(core, here, v, m)
  }
}

///|
/// What can be done about a person (Settings.kt MemberSheet): their role (by the owner), moving them out.
fn member_sheet(core : Core, here : Here, v : Json?, m : Json) -> Unit {
  let mv = Some(m)
  let sub = text(mv, "sub")
  let email = text(mv, "email")
  let ws = text(v, "id")
  open_sheet(0.5, fn(c, _) {
    let t = @sf.theme()
    sheet_head(
      c,
      match text(mv, "name") {
        "" => email
        x => x
      },
    )
    if text(v, "role") == "owner" {
      let setting = is_doing(core, ["workspace.setRole"], [("workspace", ws), ("member", sub)])
      for r in ["owner", "admin", "member"] {
        if pick_row(
            c,
            "role/" + r,
            role_label(r),
            sub=tr("android-misc.role." + r + ".hint"),
            checked=text(mv, "role") == r,
            enabled=!setting,
          ) {
          close_sheet()
          if r != text(mv, "role") {
            act(
              core,
              tr("android-settings.members.roleWhat"),
              "workspace.setRole",
              obj([("workspace", str(ws)), ("member", str(sub)), ("role", str(r)), ("account", str(here.sub))]),
              done=tr("android-settings.members.roleSet"),
            )
          }
        }
      }
    }
    if pick_row(c, "move-out", tr("android-settings.members.moveOutRow"), color=t.p.red) {
      confirm(
        fill("android-settings.members.moveOutTitle", [("email", email), ("name", text(v, "name"))]),
        tr("android-settings.members.moveOutText"),
        tr("android-settings.members.moveOut"),
        danger=true,
        fn() {
          act(
            core,
            tr("android-settings.members.moveOutWhat"),
            "workspace.removeMember",
            obj([("workspace", str(ws)), ("member", str(sub)), ("account", str(here.sub))]),
            done=tr("android-settings.members.movedOut"),
          )
        },
      )
    }
  })
}
