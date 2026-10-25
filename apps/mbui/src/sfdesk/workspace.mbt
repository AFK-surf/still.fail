// The workspace's page, one in every frame (laid out by its width, page_look.mbt): wide as the web's (ember web/src/cloud/settings.tsx WorkspaceSettings, Members,
// Relays; settings.css.ts workspaceHead, workspaceFacts, titleCount, memberGroup, dangerList): at its head its mark (a
// square, its letter till one is picked; its managers pick it) and its name (renamed by them), who the viewer is there
// and how many it holds; then its people (成员 N, 添加成员; each their picture, name and email, their role in a pill,
// what can be done to them under ⋯; those added who have not signed in, the invitations out), its relays (中继, what
// they are, 添加中继), and leaving or deleting it at the end, each a row with its button. Narrow as the web's mobile
// page (mobile/WorkspacePage.tsx): its name, its mark, its people in one list (a person pressed: what can be done
// about them, a menu), its relays, leaving or deleting it in red at its foot.

///|
/// The workspace's page, one in every frame: narrow as the narrow app's (workspace_narrow), wide as the web's.
fn workspace_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  if look_of(c) == Narrow {
    workspace_narrow(c, core, here, frame)
    return
  }
  let t = @sf.theme()
  let topic = workspace_view(core, here)
  let v = topic.value
  let role = text(v, "role")
  let manager = role == "owner" || role == "admin"
  let blocks : Array[() -> Unit] = []
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
    desk_lanes(c, "workspace", blocks)
    return
  }
  let ws = text(v, "id")
  let name = text(v, "name")
  let members = items(v, "members")
  let added = items(v, "added")
  let invitations = items(v, "invitations")
  let relays = strings(v, "relays")
  // its head: its mark, its name, who the viewer is there and how many it holds
  blocks.push(fn() {
    c.box(style=ws_head, fn() {
      let mid = c.id("ws-mark")
      if manager {
        c.cursor(mid, Hand)
        if hit(c, mid) {
          open_mark_pick(core, name, text(v, "emoji"), text(v, "icon"), @sf.t("android-settings.workspace.iconWhat"), fn(
            emoji,
            icon,
            done,
          ) {
            (core.call)(
              "workspace.rename",
              obj([("workspace", str(ws)), ("emoji", str(emoji)), ("icon", str(icon)), ("account", str(here.sub))]),
              done,
            )
          })
        }
      }
      let mb = c.box(style=ws_mark, id=if manager { mid } else { 0 }, fn() {
        let emoji = text(v, "emoji")
        let icon = text(v, "icon")
        if @sf.has_station_mark(emoji, icon) {
          @sf.station_mark(c, emoji, icon, ws_mark_glyph, t.p.text)
        } else {
          let letter = match name.iter().next() {
            Some(ch) => ch.to_string().to_upper()
            None => "?"
          }
          c.text(letter, style=ws_mark_letter) |> ignore
        }
      })
      if manager {
        c.semantics(mb, Button, id=mid, label=@sf.t("android-settings.workspace.icon"))
      }
      c.box(style=ws_identity, fn() {
        let nid = c.id("ws-name")
        if manager {
          c.cursor(nid, IBeam)
          if hit(c, nid) {
            ask(@sf.t("android-settings.workspace.name"), name, @sf.t("android-settings.workspace.namePlaceholder"), @sf.t("common.save"), fn(
              line,
            ) {
              @settings.act(
                core,
                @sf.t("android-settings.workspace.renameWhat"),
                "workspace.rename",
                obj([("workspace", str(ws)), ("name", str(line)), ("account", str(here.sub))]),
                done=@sf.t("android-settings.renamed"),
              )
            })
          }
        }
        c.box(style=ws_name_box, id=if manager { nid } else { 0 }, fn() { c.text(name, style=ws_name) |> ignore }) |> ignore
        // (on as many lines as they take, each with the dot before it: workspaceFacts' flex-wrap)
        c.box(style=ws_facts, flow=true, line_gap=ws_facts_line, fn() {
          let facts = [
            @sf.t("web-pages.settings.workspace.youAreShort", args=[("role", role_label(role)), ("email", here.email)]),
            @sf.t("web-pages.settings.members.count", args=[("n", members.length().to_string())]),
            @sf.t("web-pages.settings.workspace.stationsCount", args=[("n", items(v, "stations").length().to_string())]),
          ]
          for i, f in facts {
            c.box(style=ws_fact_part, fn() {
              if i > 0 {
                c.text("·", style=ws_fact_dot) |> ignore
              }
              c.text(f, style=ws_fact_wrap) |> ignore
            })
            |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  // 成员
  blocks.push(fn() {
    ws_section(
      c,
      @sf.t("web-pages.settings.workspace.members"),
      count=members.length(),
      actions=fn() {
        if manager && @sf.button(c, @sf.t("web-pages.settings.members.add"), key="ws-add-people", icon="user-plus") {
          open_add_people(core, here, v)
        }
      },
      fn() {
        c.box(style=desk_list, fn() {
        for m in members {
          ws_member_row(c, core, here, v, m)
        }
        if manager && added.length() > 0 {
          ws_group(c, @sf.t("web-pages.settings.members.added"), @sf.t("web-pages.settings.members.addedNote", args=[("n", added.length().to_string()), ("name", "still.fail")]))
          for a in added {
            let email = text(Some(a), "email")
            ws_row(c, fn() {
              avatar(c, core, email, email, ws_avatar)
              ws_lines(c, email, role_label(text(Some(a), "role")))
              let on = [("workspace", ws), ("email", email)]
              if @sf.button(
                  c,
                  @sf.t("web-pages.settings.members.unadd"),
                  key="ws-unadd/" + email,
                  tone=Ghost,
                  busy=is_doing(core, ["workspace.removeAdded"], on),
                ) {
                @settings.act(
                  core,
                  @sf.t("android-settings.members.removeWhat"),
                  "workspace.removeAdded",
                  obj([("workspace", str(ws)), ("email", str(email)), ("account", str(here.sub))]),
                )
              }
            })
          }
        }
        if manager && invitations.length() > 0 {
          ws_group(c, @sf.t("web-pages.settings.members.invitations"), @sf.t("web-pages.settings.members.invitationsCount", args=[("n", invitations.length().to_string())]))
          for i in invitations {
            let iv = Some(i)
            let id = text(iv, "id")
            let email = text(iv, "email")
            ws_row(c, fn() {
              avatar(c, core, if email != "" { email } else { id }, if email != "" { email } else { "?" }, ws_avatar)
              ws_lines(
                c,
                if email != "" { email } else { @sf.t("web-pages.settings.members.anyone") },
                @sf.t("web-pages.settings.members.invitationNote", args=[
                  ("role", role_label(text(iv, "role"))),
                  ("until", stamp(iv, "expires_at", "until")),
                ]),
              )
              let on = [("workspace", ws), ("invitation", id)]
              if @sf.button(
                  c,
                  @sf.t("web-pages.settings.members.revoke"),
                  key="ws-revoke/" + id,
                  tone=Ghost,
                  busy=is_doing(core, ["workspace.revokeInvitation"], on),
                ) {
                @settings.act(
                  core,
                  @sf.t("android-settings.members.revokeWhat"),
                  "workspace.revokeInvitation",
                  obj([("workspace", str(ws)), ("invitation", str(id)), ("account", str(here.sub))]),
                  done=@sf.t("android-settings.members.revoked"),
                )
              }
            })
          }
        }
        })
        |> ignore
      },
    )
  })
  // 中继
  if manager || relays.length() > 0 {
    blocks.push(fn() {
      let busy = is_doing(core, ["workspace.setRelays"], [("workspace", ws)])
      ws_section(
        c,
        @sf.t("web-pages.settings.relays.title"),
        count=relays.length(),
        description=@sf.t("web-pages.settings.relays.lead", args=[("name", "still.fail")]),
        actions=fn() {
          if manager && @sf.button(c, @sf.t("web-pages.settings.relays.add"), key="ws-relay-add", icon="plus", busy~) {
            ask(
              @sf.t("web-pages.settings.relays.add"),
              "",
              "https://relay.example.com",
              @sf.t("web-pages.settings.relays.addAction"),
              hint=@sf.t("web-pages.settings.relays.hint"),
              fn(line) {
                let next = relays.copy()
                next.push(line)
                @settings.act(
                  core,
                  @sf.t("android-settings.relays.add"),
                  "workspace.setRelays",
                  obj([("workspace", str(ws)), ("relays", Json::array(next.map(str))), ("account", str(here.sub))]),
                  done=@sf.t("android-settings.relays.added"),
                )
              },
            )
          }
        },
        fn() {
          if relays.length() > 0 {
            c.box(style=ws_card, fn() {
              for url in relays {
                c.box(style=ws_card_row, fn() {
                  c.text(url.replace(old="https://", new="").replace(old="http://", new=""), style=ws_card_title) |> ignore
                  if manager &&
                    @sf.button(c, @sf.t("web-pages.settings.relays.remove"), key="ws-relay/" + url, tone=Ghost, disabled=busy) {
                    @settings.act(
                      core,
                      @sf.t("android-settings.relays.removeWhat"),
                      "workspace.setRelays",
                      obj([
                        ("workspace", str(ws)),
                        ("relays", Json::array(relays.filter(fn(r) { r != url }).map(str))),
                        ("account", str(here.sub)),
                      ]),
                      done=@sf.t("android-settings.relays.removed"),
                    )
                  }
                })
                |> ignore
              }
            })
            |> ignore
          }
        },
      )
    })
  }
  // 退出与删除: each its row, asked again before it is done
  blocks.push(fn() {
    ws_section(c, @sf.t("web-pages.settings.workspace.leaveDelete"), fn() {
      c.box(style=ws_danger_list, fn() {
        ws_danger(c, @sf.t("web-pages.settings.workspace.leave"), @sf.t("web-pages.settings.workspace.leaveBody"), fn() {
          if @sf.button(c, @sf.t("web-pages.settings.workspace.leaveAction"), key="ws-leave", tone=Danger, icon="log-out") {
            confirm(
              @sf.t("web-pages.settings.workspace.leaveConfirm", args=[("name", name)]),
              @sf.t("web-pages.settings.workspace.leaveConfirmBody"),
              @sf.t("web-pages.settings.workspace.leaveAction"),
              danger=true,
              fn() {
                (core.home)()
                @settings.act(
                  core,
                  @sf.t("android-settings.workspace.leaveWhat"),
                  "workspace.removeMember",
                  obj([("workspace", str(ws)), ("member", str(here.sub)), ("account", str(here.sub))]),
                  done=@sf.t("android-settings.workspace.left"),
                )
              },
            )
          }
        })
        if role == "owner" {
          ws_danger(
            c,
            @sf.t("web-pages.settings.workspace.delete"),
            @sf.t("web-pages.settings.workspace.deleteBody", args=[("name", "still.fail")]),
            fn() {
              if @sf.button(c, @sf.t("common.delete"), key="ws-delete", tone=Danger, icon="trash") {
                confirm(
                  @sf.t("web-pages.settings.workspace.deleteConfirm", args=[("name", name)]),
                  @sf.t("web-pages.settings.workspace.deleteConfirmBody", args=[
                    ("n", items(v, "stations").length().to_string()),
                    ("name", "still.fail"),
                  ]),
                  @sf.t("web-pages.settings.workspace.delete"),
                  danger=true,
                  fn() {
                    (core.home)()
                    @settings.act(
                      core,
                      @sf.t("android-settings.workspace.deleteWhat"),
                      "workspace.delete",
                      obj([("workspace", str(ws)), ("account", str(here.sub))]),
                      done=@sf.t("android-settings.workspace.deleted"),
                    )
                  },
                )
              }
            },
          )
        }
      })
      |> ignore
    })
  })
  desk_lanes(c, "workspace", blocks)
}

///|
/// The workspace's page in a narrow box (WorkspaceScreen): who the viewer is there and how many it holds; its name and
/// its mark, renamed and picked by its managers; its people in one list (those in it, those added who have not signed
/// in, the invitations out), 添加成员 at the title's end; its relays; leaving or deleting it in red, asked first.
fn workspace_narrow(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let look : Look = Narrow
  let t = @sf.theme()
  let topic = workspace_view(core, here)
  let v = topic.value
  let title = @sf.t("android-settings.workspace.title")
  guard v is Some(_) else {
    look_page(c, core, frame, "workspace", title, [
      fn() {
        waiting_cards(
          c,
          error=match topic.error {
            Some(e) => error_text(e)
            None => ""
          },
        )
      },
    ])
  }
  let role = text(v, "role")
  let manager = role == "owner" || role == "admin"
  let ws = text(v, "id")
  let name = text(v, "name")
  let members = items(v, "members")
  let added = items(v, "added")
  let invitations = items(v, "invitations")
  let relays = strings(v, "relays")
  let waiting = if manager { added.length() + invitations.length() } else { 0 }
  let n = members.length().to_string()
  let blocks : Array[() -> Unit] = []
  // who the viewer is there and how many it holds
  blocks.push(fn() {
    @sf.page_note(c, @sf.t(if manager { "android-settings.workspace.aboutRename" } else { "android-settings.workspace.about" }, args=[
        ("role", role_label(role)),
        ("people", @sf.t("android-settings.members.count", args=[("n", n)])),
        ("stations", @sf.t("android-settings.workspace.stations", args=[("n", items(v, "stations").length().to_string())])),
      ]),
    )
  })
  // its name and its mark: renamed, picked by its managers
  blocks.push(fn() {
    @sf.group(c, fn() {
      if @sf.link_row(c, "ws-name", @sf.t("android-settings.workspace.name"), value=name, chevron=manager) && manager {
        ask(@sf.t("android-settings.workspace.name"), name, @sf.t("android-settings.workspace.namePlaceholder"), @sf.t("common.save"), fn(
          line,
        ) {
          @settings.act(
            core,
            @sf.t("android-settings.workspace.renameWhat"),
            "workspace.rename",
            obj([("workspace", str(ws)), ("name", str(line)), ("account", str(here.sub))]),
            done=@sf.t("android-settings.renamed"),
          )
        })
      }
      if manager {
        let emoji = text(v, "emoji")
        let icon = text(v, "icon")
        let id = c.id("ws-mark")
        c.cursor(id, Hand)
        if c.clicked(id) {
          open_mark_pick(core, name, emoji, icon, @sf.t("android-settings.workspace.iconWhat"), fn(emoji, icon, done) {
            (core.call)(
              "workspace.rename",
              obj([("workspace", str(ws)), ("emoji", str(emoji)), ("icon", str(icon)), ("account", str(here.sub))]),
              done,
            )
          })
        }
        let b = c.box(style=narrow_row, id~, fn() {
          c.text(@sf.t("android-settings.workspace.icon"), style=narrow_row_title) |> ignore
          let on = [("workspace", ws)]
          doing_mark(c, is_doing(core, ["workspace.rename"], on), failed_of(core, ["workspace.rename"], on))
          if @sf.has_station_mark(emoji, icon) {
            @sf.station_mark(c, emoji, icon, ws_mark_narrow, t.p.text)
          } else {
            c.text(@sf.t("android-settings.workspace.iconNone"), style=narrow_value) |> ignore
          }
          @sf.icon(c, "chevron-right", size=narrow_chevron, color=t.p.subtle) |> ignore
          finger_ripple(c, id)
        })
        c.semantics(b, Button, id~, label=@sf.t("android-settings.workspace.icon"))
      }
    })
  })
  // its people in one list
  blocks.push(fn() {
    @sf.heading(c, @sf.t("android-settings.members.title"),
      note=if waiting > 0 {
        @sf.t("android-settings.members.waiting", args=[("n", n), ("waiting", waiting.to_string())])
      } else {
        @sf.t("android-settings.members.count", args=[("n", n)])
      },
    )
  })
  blocks.push(fn() {
    @sf.group(c, fn() {
      for m in members {
        ws_member_narrow(c, core, here, v, m)
      }
      if manager {
        for a in added {
          let email = text(Some(a), "email")
          c.box(style=narrow_said_row, fn() {
            avatar(c, core, email, email, ws_avatar)
            c.box(style=narrow_row_words, fn() {
              c.text(email, style=narrow_row_title) |> ignore
              c.text(@sf.t("android-settings.members.added", args=[("role", role_label(text(Some(a), "role")))]), style=narrow_note) |> ignore
            })
            |> ignore
            let on = [("workspace", ws), ("email", email)]
            if ws_row_action(c, "remove-added/" + email, @sf.t("android-settings.members.remove"), core, ["workspace.removeAdded"], on) {
              @settings.act(
                core,
                @sf.t("android-settings.members.removeWhat"),
                "workspace.removeAdded",
                obj([("workspace", str(ws)), ("email", str(email)), ("account", str(here.sub))]),
                done=@sf.t("android-settings.members.removed"),
              )
            }
          })
          |> ignore
        }
        for i in invitations {
          let iv = Some(i)
          let id = text(iv, "id")
          let email = text(iv, "email")
          c.box(style=narrow_said_row, fn() {
            avatar(c, core, if email != "" { email } else { id }, if email != "" { email } else { "?" }, ws_avatar)
            c.box(style=narrow_row_words, fn() {
              c.text(if email != "" { email } else { @sf.t("android-settings.members.anyone") }, style=narrow_row_title) |> ignore
              c.text(
                @sf.t("android-settings.members.invitation", args=[("role", role_label(text(iv, "role"))), ("until", stamp(iv, "expires_at", "until"))]),
                style=narrow_note,
              )
              |> ignore
            })
            |> ignore
            let on = [("workspace", ws), ("invitation", id)]
            if ws_row_action(c, "revoke/" + id, @sf.t("android-settings.members.revoke"), core, ["workspace.revokeInvitation"], on) {
              @settings.act(
                core,
                @sf.t("android-settings.members.revokeWhat"),
                "workspace.revokeInvitation",
                obj([("workspace", str(ws)), ("invitation", str(id)), ("account", str(here.sub))]),
                done=@sf.t("android-settings.members.revoked"),
              )
            }
          })
          |> ignore
        }
      }
    })
  })
  // its own relays
  if manager || relays.length() > 0 {
    blocks.push(fn() { @sf.heading(c, @sf.t("android-settings.relays.title")) })
    blocks.push(fn() {
      let busy = is_doing(core, ["workspace.setRelays"], [("workspace", ws)])
      @sf.group(c, fn() {
        for url in relays {
          c.box(style=narrow_said_row, fn() {
            c.text(url.replace(old="https://", new="").replace(old="http://", new=""), style=narrow_row_title) |> ignore
            if manager && !busy && acc_sign_out_link(c, "relay/" + url, @sf.t("android-settings.members.remove")) {
              @settings.act(
                core,
                @sf.t("android-settings.relays.removeWhat"),
                "workspace.setRelays",
                obj([("workspace", str(ws)), ("relays", Json::array(relays.filter(fn(r) { r != url }).map(str))), ("account", str(here.sub))]),
                done=@sf.t("android-settings.relays.removed"),
              )
            }
          })
          |> ignore
        }
        if manager && @sf.link_row(c, "relay-add", @sf.t(if busy { "common.saving" } else { "android-settings.relays.add" }), chevron=false) && !busy {
          ask(
            @sf.t("android-settings.relays.add"),
            "",
            "https://relay.example.com",
            @sf.t("android-settings.relays.addAction"),
            hint=@sf.t("android-settings.relays.hint"),
            fn(line) {
              let next = relays.copy()
              next.push(line)
              @settings.act(
                core,
                @sf.t("android-settings.relays.add"),
                "workspace.setRelays",
                obj([("workspace", str(ws)), ("relays", Json::array(next.map(str))), ("account", str(here.sub))]),
                done=@sf.t("android-settings.relays.added"),
              )
            },
          )
        }
      })
      @sf.page_note(c, @sf.t("android-settings.relays.lead", args=[("app", "still.fail")]))
    })
  }
  // leaving or deleting it, in red at the foot, asked first
  blocks.push(fn() {
    c.box(style=ws_narrow_foot, fn() {
      @sf.group(c, fn() {
        if ws_red_row(c, "ws-leave", @sf.t("android-settings.workspace.leaveRow")) {
          confirm(
            @sf.t("android-settings.workspace.leaveTitle", args=[("name", name)]),
            @sf.t("android-settings.workspace.leaveText"),
            @sf.t("android-settings.workspace.leave"),
            danger=true,
            fn() {
              (core.home)()
              @settings.act(
                core,
                @sf.t("android-settings.workspace.leaveWhat"),
                "workspace.removeMember",
                obj([("workspace", str(ws)), ("member", str(here.sub)), ("account", str(here.sub))]),
                done=@sf.t("android-settings.workspace.left"),
              )
            },
          )
        }
        if role == "owner" && ws_red_row(c, "ws-delete", @sf.t("android-settings.workspace.delete")) {
          confirm(
            @sf.t("android-settings.workspace.deleteTitle", args=[("name", name)]),
            @sf.t("android-settings.workspace.deleteText", args=[("n", items(v, "stations").length().to_string()), ("app", "still.fail")]),
            @sf.t("android-settings.workspace.delete"),
            danger=true,
            fn() {
              (core.home)()
              @settings.act(
                core,
                @sf.t("android-settings.workspace.deleteWhat"),
                "workspace.delete",
                obj([("workspace", str(ws)), ("account", str(here.sub))]),
                done=@sf.t("android-settings.workspace.deleted"),
              )
            },
          )
        }
      })
    })
    |> ignore
  })
  look_page(c, core, frame, "workspace",
    name,
    blocks,
    // adding people, by email or from Slack: its managers'
    actions?=if manager {
      Some(fn() {
        let id = c.id("ws-add-people")
        c.cursor(id, Hand)
        if c.clicked(id) {
          open_add_people(core, here, v)
        }
        let b = c.box(style=ws_add_box, id~, fn() { @sf.icon(c, "user-plus", size=ws_add_icon, color=@sf.link_ink()) |> ignore })
        c.semantics(b, Button, id~, label=@sf.t("web-pages.settings.members.add"))
      })
    } else {
      None
    },
  )
}

///|
/// A person on the narrow page (MemberRow): their picture, name (你 for the viewer) and email, their role at its end;
/// pressed (where the viewer may), what can be done about them: their role (by the owner), moving them out, asked
/// first (ws_member_panel: a sheet with a finger).
fn ws_member_narrow(c : @ui.Ctx, core : Core, here : Here, v : Json?, m : Json) -> Unit {
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
  let now = text(mv, "role")
  let can = sub != here.sub && manager && (now != "owner" || role == "owner")
  let id = if can { c.id("member/" + sub) } else { 0 }
  if can {
    c.cursor(id, Hand)
    if c.clicked(id) {
      ws_member_panel(core, here, v, m, name, Of(id))
    }
  }
  let b = c.box(style=if can { narrow_row } else { narrow_said_row }, id~, fn() {
    avatar(c, core, email, name, ws_avatar, picture=text(mv, "picture"))
    c.box(style=narrow_row_words, fn() {
      c.box(style=desk_named, fn() {
        c.text(name, style=mem_narrow_title) |> ignore
        if sub == here.sub {
          you(c, @sf.t("android-settings.members.you"))
        }
      })
      |> ignore
      c.text(email, style=narrow_note) |> ignore
    })
    |> ignore
    let on = [("workspace", ws), ("member", sub)]
    let calls = ["workspace.setRole", "workspace.removeMember"]
    doing_mark(c, is_doing(core, calls, on), failed_of(core, calls, on))
    c.text(role_label(now), style=narrow_value) |> ignore
    if can {
      finger_ripple(c, id)
    }
  })
  if can {
    c.semantics(b, Button, id~, label=name)
  }
}

///|
/// What can be done about a person (MemberSheet), by what pressed them: their role (by the owner: each with what it may
/// do, the one now checked), moving them out (in red, asked first). A panel: a sheet with a finger.
fn ws_member_panel(core : Core, here : Here, v : Json?, m : Json, name : String, from : @sf.Anchor) -> Unit {
  let mv = Some(m)
  let sub = text(mv, "sub")
  let email = text(mv, "email")
  let ws = text(v, "id")
  @sf.panel(name, from~, fn(c, close) {
    let t = @sf.theme()
    if text(v, "role") == "owner" {
      let setting = is_doing(core, ["workspace.setRole"], [("workspace", ws), ("member", sub)])
      for r in ["owner", "admin", "member"] {
        if @settings.pick_row(
            c,
            "role/" + r,
            role_label(r),
            sub=@sf.t("android-misc.role." + r + ".hint"),
            checked=text(mv, "role") == r,
            enabled=!setting,
          ) {
          close()
          if r != text(mv, "role") {
            @settings.act(
              core,
              @sf.t("android-settings.members.roleWhat"),
              "workspace.setRole",
              obj([("workspace", str(ws)), ("member", str(sub)), ("role", str(r)), ("account", str(here.sub))]),
              done=@sf.t("android-settings.members.roleSet"),
            )
          }
        }
      }
    }
    if @settings.pick_row(c, "move-out", @sf.t("android-settings.members.moveOutRow"), color=t.p.red) {
      close()
      confirm(
        @sf.t("android-settings.members.moveOutTitle", args=[("email", email), ("name", text(v, "name"))]),
        @sf.t("android-settings.members.moveOutText"),
        @sf.t("android-settings.members.moveOut"),
        danger=true,
        fn() {
          @settings.act(
            core,
            @sf.t("android-settings.members.moveOutWhat"),
            "workspace.removeMember",
            obj([("workspace", str(ws)), ("member", str(sub)), ("account", str(here.sub))]),
            done=@sf.t("android-settings.members.movedOut"),
          )
        },
      )
    }
  })
}

///|
/// What a row does at its end, in red (RowAction): a spinner while it is under way, the failure mark a moment after.
fn ws_row_action(c : @ui.Ctx, key : String, words : String, core : Core, calls : Array[String], on : Array[(String, String)]) -> Bool {
  let busy = is_doing(core, calls, on)
  doing_mark(c, busy, failed_of(core, calls, on))
  !busy && acc_sign_out_link(c, key, words)
}

///|
/// A row in red that does something asked first (leaving, deleting).
fn ws_red_row(c : @ui.Ctx, key : String, words : String) -> Bool {
  let id = c.id(key)
  c.cursor(id, Hand)
  let b = c.box(style=narrow_row, id~, fn() {
    c.text(words, style=ws_red_words) |> ignore
    finger_ripple(c, id)
  })
  c.semantics(b, Button, id~, label=words)
  c.clicked(id)
}

///|
let ws_mark_narrow : Double = 20.0

///|
let ws_add_icon : Double = 20.0

///|
// kept across runs: a value (no field of it changes)
let ws_add_box : @ui.Style = @ui.css("w=S10 h=S10 radius=Full align=ACenter justify=JCenter hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let ws_red_words : @ui.TextStyle = @sf.body.then(@sf.bad).then(@sf.one_line).then(@sf.full_words)

///|
/// (the narrow page's foot: leaving, deleting, 18 over it)
// kept across runs: a value (no field of it changes)
let ws_narrow_foot : @ui.Style = @ui.css("w=Full pt=S4")

///|
/// A titled block (ui Section): its title (and how many, subtle), what it is under it, its buttons at its end; then
/// what it holds.
fn ws_section(
  c : @ui.Ctx,
  title : String,
  count? : Int = 0,
  description? : String = "",
  actions? : () -> Unit = fn() {  },
  body : () -> Unit,
) -> Unit {
  c.box(style=ws_section_room, fn() {
    @sf.section(
      c,
      title,
      body,
      note=description,
      actions~,
      title_after?=if count > 0 {
        Some(fn() { c.text(count.to_string(), style=ws_section_count) |> ignore })
      } else {
        None
      },
    )
  })
  |> ignore
}

///|
/// A row of a list (pages.css.ts listRow: 52 high at least, 10 by 12 in).
fn ws_row(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=desk_list_row, fn() { body() }) |> ignore
}

///|
/// A row's two lines: its title (500), what it is in the muted ink.
fn ws_lines(c : @ui.Ctx, title : String, sub : String, badge? : String = "") -> Unit {
  c.box(style=ws_row_text, fn() {
    c.box(style=ws_title_line, fn() {
      c.text(title, style=ws_row_title) |> ignore
      if badge != "" {
        c.box(style=ws_badge, fn() { c.text(badge, style=ws_badge_words) |> ignore }) |> ignore
      }
    })
    |> ignore
    c.text(sub, style=ws_row_sub) |> ignore
  })
  |> ignore
}

///|
/// A group's head among the people (memberGroup: its name, how many, muted after it).
fn ws_group(c : @ui.Ctx, title : String, note : String) -> Unit {
  c.box(style=ws_group_box, fn() {
    c.text(title, style=ws_group_title) |> ignore
    c.text(note, style=ws_group_note) |> ignore
  })
  |> ignore
}

///|
/// One of 退出与删除 (cardRow): what it does and what follows, its button at its end.
fn ws_danger(c : @ui.Ctx, title : String, body : String, button : () -> Unit) -> Unit {
  c.box(style=ws_card_row, fn() {
    c.box(style=ws_row_text, fn() {
      c.text(title, style=ws_danger_title) |> ignore
      c.text(body, style=ws_row_sub_wrap) |> ignore
    })
    |> ignore
    button()
  })
  |> ignore
}

///|
/// A person (Members' row): their picture, name (你 for the viewer) and email, their role in a pill; pressed by the
/// owner (the pill) their role changed, under ⋯ what a manager does to them.
fn ws_member_row(c : @ui.Ctx, core : Core, here : Here, v : Json?, m : Json) -> Unit {
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
  ws_row(c, fn() {
    avatar(c, core, email, name, ws_avatar, picture=text(mv, "picture"))
    ws_lines(c, name, email, badge=if sub == here.sub { @sf.t("web-pages.settings.members.you") } else { "" })
    let on = [("workspace", ws), ("member", sub)]
    let calls = ["workspace.setRole", "workspace.removeMember"]
    doing_mark(c, is_doing(core, calls, on), failed_of(core, calls, on))
    // its role: the owner sets another's (a Select, 120 wide), else said in a pill
    let now = text(mv, "role")
    if role == "owner" && sub != here.sub {
      let setting = is_doing(core, ["workspace.setRole"], on)
      @sf.select(
        c,
        "ws-role/" + sub,
        now,
        ["owner", "admin", "member"].map(fn(r) { (r, role_label(r)) }),
        fn(picked) {
          if picked != now {
            @settings.act(
              core,
              @sf.t("android-settings.members.roleWhat"),
              "workspace.setRole",
              obj([("workspace", str(ws)), ("member", str(sub)), ("role", str(picked)), ("account", str(here.sub))]),
              done=@sf.t("android-settings.members.roleSet"),
            )
          }
        },
        label=@sf.t("web-pages.settings.members.role"),
        disabled=setting,
        w=ws_role_w,
      )
    } else {
      @sf.pill(c, role_label(now))
    }
    // what a manager does to them, under ⋯ (Menu): taken out of the workspace, asked again first
    if can {
      let mid = c.id("ws-member-more/" + sub)
      c.cursor(mid, Hand)
      let open = ws_menu.val == sub
      if c.clicked(mid) {
        ws_menu.val = if open { "" } else { sub }
      }
      let b = c.box(style=ws_more, id=mid, fn() { @sf.icon(c, "more", size=ws_more_icon, color=t.p.muted) |> ignore })
      c.semantics(b, Button, id=mid, label=@sf.t("web-pages.settings.members.remove"), expanded=open)
      let m = @sf.dropdown(
        c,
        "ws-member-menu/" + sub,
        open,
        mid,
        [@kit.menu_item("remove", label=@sf.t("web-pages.settings.members.remove"))],
        { "remove": "trash" },
        @sf.menu_w,
        along=End,
      )
      if open && !m.open {
        ws_menu.val = ""
      }
      if m.chosen is Some(_) {
        ws_menu.val = ""
        confirm(
          @sf.t("android-settings.members.moveOutTitle", args=[("email", email), ("name", text(v, "name"))]),
          @sf.t("android-settings.members.moveOutText"),
          @sf.t("android-settings.members.moveOut"),
          danger=true,
          fn() {
            @settings.act(
              core,
              @sf.t("android-settings.members.moveOutWhat"),
              "workspace.removeMember",
              obj([("workspace", str(ws)), ("member", str(sub)), ("account", str(here.sub))]),
              done=@sf.t("android-settings.members.movedOut"),
            )
          },
        )
      }
    }
  })
}

///|
/// The mark's square (56), its glyph in it, a person's picture (28), ⋯'s mark (16).
let ws_mark_glyph : Double = 28.0

///|
let ws_avatar : Double = 28.0

///|
let ws_more_icon : Double = 16.0

///|
/// Its head (workspaceHead: 8 under the page's 40 top, 36 under it, 16 between its mark and its words).
// kept across runs: a value (no field of it changes)
let ws_head : @ui.Style = @ui.css("row w=Full px=S4 pt=S12 pb=S9 gap=S4 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ws_mark : @ui.Style = @ui.css("w=S14 h=S14 radius=Xl bg=Neutral align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let ws_mark_letter : @ui.TextStyle = @ui.text_style(size=Heading, weight=Semibold, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ws_identity : @ui.Style = @ui.style(w=@sf.grow, gap=SPx)

///|
/// Its name (titleField: the heading's 22 on 40, 600; a field's ground under the pointer).
// kept across runs: a value (no field of it changes)
let ws_name_box : @ui.Style = @ui.css("h=S10 px=S2 align=AStart justify=JCenter radius=Xl hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let ws_name : @ui.TextStyle = @ui.text_style(size=Heading, weight=Semibold, color=Fg, wrap=false)

///|
/// Who the viewer is, how many (workspaceFacts: the ui's 13 on 20, muted, a subtle · 8 from each between).
// kept across runs: a value (no field of it changes)
let ws_facts : @ui.Style = @ui.css("row px=S2 gap=S2 align=ACenter")

///|
/// A fact with the dot before it, 8 apart, kept together; its words on more lines where one has not the room; 4
/// between the facts' lines.
// kept across runs: a value (no field of it changes)
let ws_fact_part : @ui.Style = @ui.css("row gap=S2 align=AStart")

///|
let ws_facts_line : Double = 4.0

///|
/// How many in a group and what becomes of them, after its name: cut short where its line has not the room.
// kept across runs: a value (no field of it changes)
let ws_group_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let ws_fact : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)

///|
/// A fact after its dot, on more lines where one has not the room.
// kept across runs: a value (no field of it changes)
let ws_fact_wrap : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let ws_fact_dot : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Subtle, wrap=false)




///|
// kept across runs: a value (no field of it changes)
let ws_title_line : @ui.Style = @ui.css("row gap=S2 align=ACenter")


///|
// kept across runs: a value (no field of it changes)
let ws_section_count : @ui.TextStyle = @ui.text_style(size=Meta, leading=L7, weight=Medium, color=Subtle, wrap=false)





///|
// kept across runs: a value (no field of it changes)
let ws_row_text : @ui.Style = @ui.style(w=@sf.grow, min_w=S20, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let ws_row_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Medium, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let ws_row_sub : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ws_row_sub_wrap : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full)

///|
/// 你 by the viewer (choiceBadge: 1 by 7 in, a capsule on the accent's ground, the meta's 12 in 500).
// kept across runs: a value (no field of it changes)
let ws_badge : @ui.Style = @ui.css("px=S1_5 py=SPx radius=Full bg=AccentBg")

///|
// kept across runs: a value (no field of it changes)
let ws_badge_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=AccentText, wrap=false)




///|
/// ⋯ (an icon button: 32, its corner 12).
// kept across runs: a value (no field of it changes)
let ws_more : @ui.Style = @ui.css("w=S8 h=S8 radius=Xl align=ACenter justify=JCenter hovered{bg=Hover}")

///|
/// A group's head among the people (memberGroup: 18 over, 12 in, 2 under, 8 apart).
// kept across runs: a value (no field of it changes)
let ws_group_box : @ui.Style = @ui.css("row w=Full px=S6 pt=S4_5 pb=S0_5 gap=S2 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let ws_group_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=Fg, wrap=false)

///|
/// A card (pages.css.ts card: 20 in, its corner the card's, the card's ground; its rows 14 apart).
// kept across runs: a value (no field of it changes)
let ws_card : @ui.Style = @ui.css("w=Full p=S5 gap=S3_5 radius=Xl3 bg=Card")

///|
// kept across runs: a value (no field of it changes)
let ws_card_row : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ws_card_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=Fg, w=@sf.grow, wrap=false)

///|
/// 退出与删除 (dangerList: 18 apart, 4 over and under).
// kept across runs: a value (no field of it changes)
let ws_danger_list : @ui.Style = @ui.css("w=Full py=S1 gap=S4")

///|
// kept across runs: a value (no field of it changes)
let ws_danger_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=Fg, wrap=false)

///|
/// A section at the column's edges (the library's Section in it).
// kept across runs: a value (no field of it changes)
let ws_section_room : @ui.Style = @ui.css("w=Full px=S4")

///|
/// The owner's role choice (roleSelect: 120 wide).
let ws_role_w : Double = 120.0

///|
/// The ⋯ menu open, by the person's sub ("" none).
// kept across runs: said again by each press; settings_reset empties it
let ws_menu : Ref[String] = Ref("")
