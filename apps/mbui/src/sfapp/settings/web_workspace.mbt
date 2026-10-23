// The workspace's page in the wide frame, as the web's (ember web/src/cloud/settings.tsx WorkspaceSettings, Members,
// Relays; settings.css.ts workspaceHead, workspaceFacts, titleCount, memberGroup, dangerList): at its head its mark (a
// square, its letter till one is picked; its managers pick it) and its name (renamed by them), who the viewer is there
// and how many it holds; then its people (成员 N, 添加成员; each their picture, name and email, their role in a pill,
// what can be done to them under ⋯; those added who have not signed in, the invitations out), its relays (中继, what
// they are, 添加中继), and leaving or deleting it at the end, each a row with its button. The phone's page is
// workspace.mbt's.

///|
fn workspace_page_wide(c : @ui.Ctx, core : Core, here : Here) -> Unit {
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
    scroll_page(c, "workspace", blocks)
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
          open_mark_pick(core, name, text(v, "emoji"), text(v, "icon"), tr("android-settings.workspace.iconWhat"), fn(
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
        c.semantics(mb, Button, id=mid, label=tr("android-settings.workspace.icon"))
      }
      c.box(style=ws_identity, fn() {
        let nid = c.id("ws-name")
        if manager {
          c.cursor(nid, IBeam)
          if hit(c, nid) {
            ask(tr("android-settings.workspace.name"), name, tr("android-settings.workspace.namePlaceholder"), tr("common.save"), fn(
              line,
            ) {
              act(
                core,
                tr("android-settings.workspace.renameWhat"),
                "workspace.rename",
                obj([("workspace", str(ws)), ("name", str(line)), ("account", str(here.sub))]),
                done=tr("android-settings.renamed"),
              )
            })
          }
        }
        c.box(style=ws_name_box, id=if manager { nid } else { 0 }, fn() { c.text(name, style=ws_name) |> ignore }) |> ignore
        c.box(style=ws_facts, fn() {
          let facts = [
            fill("web-pages.settings.workspace.youAreShort", [("role", role_label(role)), ("email", here.email)]),
            fill("web-pages.settings.members.count", [("n", members.length().to_string())]),
            fill("web-pages.settings.workspace.stationsCount", [("n", items(v, "stations").length().to_string())]),
          ]
          for i, f in facts {
            if i > 0 {
              c.text("·", style=ws_fact_dot) |> ignore
            }
            c.text(f, style=ws_fact) |> ignore
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
      tr("web-pages.settings.workspace.members"),
      count=members.length(),
      actions=fn() {
        if manager && @sf.button(c, tr("web-pages.settings.members.add"), key="ws-add-people", icon="user-plus") {
          open_add_people(core, here, v)
        }
      },
      fn() {
        for m in members {
          ws_member_row(c, core, here, v, m)
        }
        if manager && added.length() > 0 {
          ws_group(c, tr("web-pages.settings.members.added"), fill("web-pages.settings.members.addedNote", [("n", added.length().to_string()), ("name", "still.fail")]))
          for a in added {
            let email = text(Some(a), "email")
            ws_row(c, fn() {
              avatar(c, core, email, email, ws_avatar)
              ws_lines(c, email, role_label(text(Some(a), "role")))
              let on = [("workspace", ws), ("email", email)]
              if @sf.button(
                  c,
                  tr("web-pages.settings.members.unadd"),
                  key="ws-unadd/" + email,
                  tone=Ghost,
                  busy=is_doing(core, ["workspace.removeAdded"], on),
                ) {
                act(
                  core,
                  tr("android-settings.members.removeWhat"),
                  "workspace.removeAdded",
                  obj([("workspace", str(ws)), ("email", str(email)), ("account", str(here.sub))]),
                )
              }
            })
          }
        }
        if manager && invitations.length() > 0 {
          ws_group(c, tr("web-pages.settings.members.invitations"), fill("web-pages.settings.members.invitationsCount", [("n", invitations.length().to_string())]))
          for i in invitations {
            let iv = Some(i)
            let id = text(iv, "id")
            let email = text(iv, "email")
            ws_row(c, fn() {
              avatar(c, core, if email != "" { email } else { id }, if email != "" { email } else { "?" }, ws_avatar)
              ws_lines(
                c,
                if email != "" { email } else { tr("web-pages.settings.members.anyone") },
                fill("web-pages.settings.members.invitationNote", [
                  ("role", role_label(text(iv, "role"))),
                  ("until", stamp(iv, "expires_at", "until")),
                ]),
              )
              let on = [("workspace", ws), ("invitation", id)]
              if @sf.button(
                  c,
                  tr("web-pages.settings.members.revoke"),
                  key="ws-revoke/" + id,
                  tone=Ghost,
                  busy=is_doing(core, ["workspace.revokeInvitation"], on),
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
          }
        }
      },
    )
  })
  // 中继
  if manager || relays.length() > 0 {
    blocks.push(fn() {
      let busy = is_doing(core, ["workspace.setRelays"], [("workspace", ws)])
      ws_section(
        c,
        tr("web-pages.settings.relays.title"),
        count=relays.length(),
        description=fill("web-pages.settings.relays.lead", [("name", "still.fail")]),
        actions=fn() {
          if manager && @sf.button(c, tr("web-pages.settings.relays.add"), key="ws-relay-add", icon="plus", busy~) {
            ask(
              tr("web-pages.settings.relays.add"),
              "",
              "https://relay.example.com",
              tr("web-pages.settings.relays.addAction"),
              hint=tr("web-pages.settings.relays.hint"),
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
        },
        fn() {
          if relays.length() > 0 {
            c.box(style=ws_card, fn() {
              for url in relays {
                c.box(style=ws_card_row, fn() {
                  c.text(url.replace(old="https://", new="").replace(old="http://", new=""), style=ws_card_title) |> ignore
                  if manager &&
                    @sf.button(c, tr("web-pages.settings.relays.remove"), key="ws-relay/" + url, tone=Ghost, disabled=busy) {
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
            })
            |> ignore
          }
        },
      )
    })
  }
  // 退出与删除: each its row, asked again before it is done
  blocks.push(fn() {
    ws_section(c, tr("web-pages.settings.workspace.leaveDelete"), fn() {
      c.box(style=ws_danger_list, fn() {
        ws_danger(c, tr("web-pages.settings.workspace.leave"), tr("web-pages.settings.workspace.leaveBody"), fn() {
          if @sf.button(c, tr("web-pages.settings.workspace.leaveAction"), key="ws-leave", tone=Danger, icon="log-out") {
            confirm(
              fill("web-pages.settings.workspace.leaveConfirm", [("name", name)]),
              tr("web-pages.settings.workspace.leaveConfirmBody"),
              tr("web-pages.settings.workspace.leaveAction"),
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
        })
        if role == "owner" {
          ws_danger(
            c,
            tr("web-pages.settings.workspace.delete"),
            fill("web-pages.settings.workspace.deleteBody", [("name", "still.fail")]),
            fn() {
              if @sf.button(c, tr("common.delete"), key="ws-delete", tone=Danger, icon="trash") {
                confirm(
                  fill("web-pages.settings.workspace.deleteConfirm", [("name", name)]),
                  fill("web-pages.settings.workspace.deleteConfirmBody", [
                    ("n", items(v, "stations").length().to_string()),
                    ("name", "still.fail"),
                  ]),
                  tr("web-pages.settings.workspace.delete"),
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
            },
          )
        }
      })
      |> ignore
    })
  })
  scroll_page(c, "workspace", blocks)
}

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
  c.box(style=ws_section_box, fn() {
    c.box(style=ws_section_head, fn() {
      c.box(style=ws_section_words, fn() {
        c.box(style=ws_title_line, fn() {
          c.text(title, style=ws_section_title) |> ignore
          if count > 0 {
            c.text(count.to_string(), style=ws_section_count) |> ignore
          }
        })
        |> ignore
        if description != "" {
          c.text(description, style=ws_section_sub) |> ignore
        }
      })
      |> ignore
      c.box(style=ws_section_actions, fn() { actions() }) |> ignore
    })
    |> ignore
    body()
  })
  |> ignore
}

///|
/// A row of a list (pages.css.ts listRow: 52 high at least, 10 by 12 in).
fn ws_row(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=ws_list_row, fn() { body() }) |> ignore
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
    c.text(note, style=ws_row_sub) |> ignore
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
    ws_lines(c, name, email, badge=if sub == here.sub { tr("web-pages.settings.members.you") } else { "" })
    let on = [("workspace", ws), ("member", sub)]
    let calls = ["workspace.setRole", "workspace.removeMember"]
    doing_mark(c, is_doing(core, calls, on), failed_of(core, calls, on))
    let pid = c.id("ws-role/" + sub)
    let owner_sets = role == "owner" && sub != here.sub
    if owner_sets {
      c.cursor(pid, Hand)
      if hit(c, pid) {
        member_sheet(core, here, v, m)
      }
    }
    let pill = c.box(style=ws_pill, id=if owner_sets { pid } else { 0 }, fn() {
      c.text(role_label(text(mv, "role")), style=ws_pill_words) |> ignore
    })
    if owner_sets {
      c.semantics(pill, Button, id=pid, label=tr("web-pages.settings.members.role"))
    }
    if can {
      let mid = c.id("ws-member-more/" + sub)
      c.cursor(mid, Hand)
      if hit(c, mid) {
        member_sheet(core, here, v, m)
      }
      let b = c.box(style=ws_more, id=mid, fn() { @sf.icon(c, "more", size=ws_more_icon, color=t.p.muted) |> ignore })
      c.semantics(b, Button, id=mid, label=tr("web-pages.settings.members.remove"))
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
/// Its head (workspaceHead: 8 over, 36 under, 16 between its mark and its words).
// kept across runs: a value (no field of it changes)
let ws_head : @ui.Style = @ui.style(row=true, w=Full, px=S4, pt=S10, pb=S9, gap=S4, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let ws_mark : @ui.Style = @ui.style(w=S14, h=S14, radius=Xl, bg=Neutral, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let ws_mark_letter : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Semibold, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ws_identity : @ui.Style = @ui.style(w=@sf.grow, gap=SPx)

///|
/// Its name (titleField: the heading's 22 on 40, 600; a field's ground under the pointer).
// kept across runs: a value (no field of it changes)
let ws_name_box : @ui.Style = @ui.style(h=S10, px=S2, align=AStart, justify=JCenter, radius=Xl, hovered=@ui.patch(bg=Hover))

///|
// kept across runs: a value (no field of it changes)
let ws_name : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Semibold, color=Fg, wrap=false)

///|
/// Who the viewer is, how many (workspaceFacts: the ui's 13 on 20, muted, a subtle · 8 from each between).
// kept across runs: a value (no field of it changes)
let ws_facts : @ui.Style = @ui.style(row=true, px=S2, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let ws_fact : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ws_fact_dot : @ui.TextStyle = @ui.text_style(size=Sm, color=Subtle, wrap=false)

///|
/// A section (section: 28 under; its head 10 over what it holds, its title the body's 14 on 22 in 600, how many 8 after
/// it subtle in 500, what it is the meta's 12 muted 3 under).
// kept across runs: a value (no field of it changes)
let ws_section_box : @ui.Style = @ui.style(w=Full, px=S4, pb=S7)

///|
// kept across runs: a value (no field of it changes)
let ws_section_head : @ui.Style = @ui.style(row=true, w=Full, pb=S2_5, gap=S3, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let ws_section_words : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let ws_title_line : @ui.Style = @ui.style(row=true, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let ws_section_title : @ui.TextStyle = @ui.text_style(size=Base, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ws_section_count : @ui.TextStyle = @ui.text_style(size=Base, weight=Medium, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ws_section_sub : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let ws_section_actions : @ui.Style = @ui.style(row=true, gap=S2)

///|
/// A row of a list (listRow: 52 high at least, 10 by 12 in, 12 apart, the field's corner).
// kept across runs: a value (no field of it changes)
let ws_list_row : @ui.Style = @ui.style(row=true, w=Full, min_h=Fixed(ws_row_least), py=S2_5, gap=S3, align=ACenter, radius=Xl)

///|
let ws_row_least : Double = 52.0

///|
// kept across runs: a value (no field of it changes)
let ws_row_text : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let ws_row_title : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ws_row_sub : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ws_row_sub_wrap : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, w=Full)

///|
/// 你 by the viewer (choiceBadge: 1 by 7 in, a capsule on the accent's ground, the meta's 12 in 500).
// kept across runs: a value (no field of it changes)
let ws_badge : @ui.Style = @ui.style(px=S1_5, py=SPx, radius=Full, bg=AccentBg)

///|
// kept across runs: a value (no field of it changes)
let ws_badge_words : @ui.TextStyle = @ui.text_style(size=Xs, weight=Medium, color=AccentText, wrap=false)

///|
/// A role (Pill: 22 high, 9 in, a capsule on the neutral ground, the meta's 12 in 500 muted).
// kept across runs: a value (no field of it changes)
let ws_pill : @ui.Style = @ui.style(h=Fixed(ws_pill_h), px=S2, radius=Full, bg=Neutral, align=ACenter, justify=JCenter)

///|
let ws_pill_h : Double = 22.0

///|
// kept across runs: a value (no field of it changes)
let ws_pill_words : @ui.TextStyle = @ui.text_style(size=Xs, weight=Medium, color=Muted, wrap=false)

///|
/// ⋯ (an icon button: 32, its corner 12).
// kept across runs: a value (no field of it changes)
let ws_more : @ui.Style = @ui.style(w=S8, h=S8, radius=Xl, align=ACenter, justify=JCenter, hovered=@ui.patch(bg=Hover))

///|
/// A group's head among the people (memberGroup: 18 over, 12 in, 2 under, 8 apart).
// kept across runs: a value (no field of it changes)
let ws_group_box : @ui.Style = @ui.style(row=true, w=Full, pt=S4, pb=SPx, gap=S2, align=AEnd)

///|
// kept across runs: a value (no field of it changes)
let ws_group_title : @ui.TextStyle = @ui.text_style(size=Sm, weight=Semibold, color=Fg, wrap=false)

///|
/// A card (pages.css.ts card: 20 in, its corner the card's, the card's ground; its rows 14 apart).
// kept across runs: a value (no field of it changes)
let ws_card : @ui.Style = @ui.style(w=Full, p=S5, gap=S3_5, radius=Xl3, bg=Card)

///|
// kept across runs: a value (no field of it changes)
let ws_card_row : @ui.Style = @ui.style(row=true, w=Full, gap=S3, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let ws_card_title : @ui.TextStyle = @ui.text_style(size=Sm, weight=Semibold, color=Fg, w=@sf.grow, wrap=false)

///|
/// 退出与删除 (dangerList: 18 apart, 4 over and under).
// kept across runs: a value (no field of it changes)
let ws_danger_list : @ui.Style = @ui.style(w=Full, py=S1, gap=S4)

///|
// kept across runs: a value (no field of it changes)
let ws_danger_title : @ui.TextStyle = @ui.text_style(size=Sm, weight=Semibold, color=Fg, wrap=false)
