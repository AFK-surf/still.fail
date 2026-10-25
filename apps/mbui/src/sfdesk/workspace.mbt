// The workspace's page, one in every frame and the same on every width (the user, 2026-10-26: 「设置感觉很乱」; it was
// the web's desktop page wide and the narrow app's page narrow, two pages): who the viewer is there and how many it
// holds; its name and its mark, renamed and picked by its managers; its people in one list (those in it, those added
// who have not signed in, the invitations out), each pressed by a manager for what can be done about them (their role
// by the owner, moving them out: a panel, popover or sheet as the presenters say); 添加成员 at the title's end; its
// relays (中继), each removed, another added; leaving or deleting it in red at its foot, asked first. Its rows a list
// card's on either width (@sf.group), laid out by the page's width (page_look.mbt).

///|
/// The workspace's page (WorkspaceSettings, WorkspaceScreen), in the frame it is given.
fn workspace_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let look = look_of(c)
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
  // its name and its mark: renamed, picked by its managers
  blocks.push(fn() {
    @sf.group(c, fn() {
      if @sf.link_row(c, "ws-name", @sf.t("android-settings.workspace.name"), value=name, chevron=manager, goes=manager) {
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
        let marked = @sf.has_station_mark(emoji, icon)
        let on = [("workspace", ws)]
        if @sf.link_row(
            c,
            "ws-mark",
            @sf.t("android-settings.workspace.icon"),
            value=if marked { "" } else { @sf.t("android-settings.workspace.iconNone") },
            tail=fn() {
              doing_mark(c, is_doing(core, ["workspace.rename"], on), failed_of(core, ["workspace.rename"], on))
              if marked {
                @sf.station_mark(c, emoji, icon, ws_mark_narrow, t.p.text)
              }
            },
          ) {
          open_mark_pick(core, name, emoji, icon, @sf.t("android-settings.workspace.iconWhat"), fn(emoji, icon, done) {
            (core.call)(
              "workspace.rename",
              obj([("workspace", str(ws)), ("emoji", str(emoji)), ("icon", str(icon)), ("account", str(here.sub))]),
              done,
            )
          })
        }
      }
    })
  })
  // its people in one list
  blocks.push(fn() {
    @sf.section(
      c,
      @sf.t("android-settings.members.title"),
      note=if waiting > 0 {
        @sf.t("android-settings.members.waiting", args=[("n", n), ("waiting", waiting.to_string())])
      } else {
        @sf.t("android-settings.members.count", args=[("n", n)])
      },
      fn() {
        @sf.group(c, fn() {
          for m in members {
            ws_member_row(c, core, here, look, v, m)
          }
          if manager {
            for a in added {
              let email = text(Some(a), "email")
              let on = [("workspace", ws), ("email", email)]
              ws_person(
                c,
                look,
                fn() { avatar(c, core, email, email, ws_avatar) },
                email,
                @sf.t("android-settings.members.added", args=[("role", role_label(text(Some(a), "role")))]),
                fn() {
                  if ws_row_action(c, "remove-added/" + email, @sf.t("android-settings.members.remove"), core, ["workspace.removeAdded"], on) {
                    @settings.act(
                      core,
                      @sf.t("android-settings.members.removeWhat"),
                      "workspace.removeAdded",
                      obj([("workspace", str(ws)), ("email", str(email)), ("account", str(here.sub))]),
                      done=@sf.t("android-settings.members.removed"),
                    )
                  }
                },
              )
              |> ignore
            }
            for i in invitations {
              let iv = Some(i)
              let id = text(iv, "id")
              let email = text(iv, "email")
              let on = [("workspace", ws), ("invitation", id)]
              ws_person(
                c,
                look,
                fn() { avatar(c, core, if email != "" { email } else { id }, if email != "" { email } else { "?" }, ws_avatar) },
                if email != "" { email } else { @sf.t("android-settings.members.anyone") },
                @sf.t("android-settings.members.invitation", args=[("role", role_label(text(iv, "role"))), ("until", stamp(iv, "expires_at", "until"))]),
                fn() {
                  if ws_row_action(c, "revoke/" + id, @sf.t("android-settings.members.revoke"), core, ["workspace.revokeInvitation"], on) {
                    @settings.act(
                      core,
                      @sf.t("android-settings.members.revokeWhat"),
                      "workspace.revokeInvitation",
                      obj([("workspace", str(ws)), ("invitation", str(id)), ("account", str(here.sub))]),
                      done=@sf.t("android-settings.members.revoked"),
                    )
                  }
                },
              )
              |> ignore
            }
          }
        })
      },
    )
  })
  // its own relays
  if manager || relays.length() > 0 {
    blocks.push(fn() {
      let busy = is_doing(core, ["workspace.setRelays"], [("workspace", ws)])
      @sf.section(c, @sf.t("android-settings.relays.title"), note=@sf.t("android-settings.relays.lead", args=[("app", "still.fail")]), fn() {
        @sf.group(c, fn() {
          for url in relays {
            @sf.link_row(c, "", url.replace(old="https://", new="").replace(old="http://", new=""), goes=false, tail=fn() {
              if manager && @sf.button(c, @sf.t("android-settings.members.remove"), key="relay/" + url, tone=Ghost, disabled=busy) {
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
      })
    })
  }
  // leaving or deleting it, in red at the foot, asked first
  blocks.push(fn() {
    @sf.group(c, fn() {
      if @sf.link_row(c, "ws-leave", @sf.t("android-settings.workspace.leaveRow"), danger=true, chevron=false) {
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
      if role == "owner" && @sf.link_row(c, "ws-delete", @sf.t("android-settings.workspace.delete"), danger=true, chevron=false) {
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
  look_page(c, core, frame, "workspace",
    name,
    blocks,
    // who the viewer is there and how many it holds
    lead=@sf.t(if manager { "android-settings.workspace.aboutRename" } else { "android-settings.workspace.about" }, args=[
      ("role", role_label(role)),
      ("people", @sf.t("android-settings.members.count", args=[("n", n)])),
      ("stations", @sf.t("android-settings.workspace.stations", args=[("n", items(v, "stations").length().to_string())])),
    ]),
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
/// A person among the workspace's people, a row of its list card on either width (MemberRow): their picture, their
/// name (`badge` after it: 你), what is said under it, what is at its end (their role, what can be done there); pressed
/// where `id` is given.
fn ws_person(
  c : @ui.Ctx,
  look : Look,
  picture : () -> Unit,
  name : String,
  under : String,
  end : () -> Unit,
  badge? : String = "",
  id? : Int = 0,
) -> Int {
  let narrow = look == Narrow
  let style = match (narrow, id != 0) {
    (true, true) => narrow_row
    (true, false) => narrow_said_row
    (false, true) => desk_list_link
    (false, false) => desk_list_row
  }
  c.box(style~, id~, fn() {
    picture()
    c.box(style=if narrow { narrow_row_words } else { desk_list_text }, fn() {
      c.box(style=desk_named, fn() {
        c.text(name, style=if narrow { mem_narrow_title } else { desk_list_title }) |> ignore
        if badge != "" {
          you(c, badge)
        }
      })
      |> ignore
      c.text(under, style=if narrow { narrow_note } else { desk_note }) |> ignore
    })
    |> ignore
    end()
    if id != 0 && narrow {
      finger_ripple(c, id)
    }
  })
}

///|
/// A person in the workspace (MemberRow): their picture, name (你 for the viewer) and email, their role at its end;
/// pressed (where the viewer may), what can be done about them: their role (by the owner), moving them out, asked
/// first (ws_member_panel: a sheet with a finger, a popover with a mouse).
fn ws_member_row(c : @ui.Ctx, core : Core, here : Here, look : Look, v : Json?, m : Json) -> Unit {
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
  let b = ws_person(
    c,
    look,
    fn() { avatar(c, core, email, name, ws_avatar, picture=text(mv, "picture")) },
    name,
    email,
    fn() {
      let on = [("workspace", ws), ("member", sub)]
      let calls = ["workspace.setRole", "workspace.removeMember"]
      doing_mark(c, is_doing(core, calls, on), failed_of(core, calls, on))
      c.text(role_label(now), style=if look == Narrow { narrow_value } else { wide_value }) |> ignore
    },
    badge=if sub == here.sub { @sf.t("android-settings.members.you") } else { "" },
    id~,
  )
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
        if @sf.choice_row(c, "role/" + r, text(mv, "role") == r, role_label(r), note=@sf.t("android-misc.role." + r + ".hint"), disabled=!(!setting)) {
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
    if @sf.choice_row(c, "move-out", false, @sf.t("android-settings.members.moveOutRow"), ink=t.p.red) {
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
/// What a row does at its end (RowAction): a quiet button as every row's on the settings' pages (账号's 退出), turning
/// while it is under way, the failure mark before it a moment after.
fn ws_row_action(c : @ui.Ctx, key : String, words : String, core : Core, calls : Array[String], on : Array[(String, String)]) -> Bool {
  let busy = is_doing(core, calls, on)
  doing_mark(c, false, failed_of(core, calls, on))
  @sf.button(c, words, key~, tone=Ghost, busy~)
}

///|
let ws_avatar : Double = 28.0

///|
let ws_mark_narrow : Double = 20.0

///|
let ws_add_icon : Double = 20.0

///|
// kept across runs: a value (no field of it changes)
let ws_add_box : @ui.Style = @ui.css("w=S10 h=S10 radius=Full align=ACenter justify=JCenter hovered{bg=Hover}")

///|
/// ⋯ (an icon button: 32, its corner 12).
// kept across runs: a value (no field of it changes)
let ws_more : @ui.Style = @ui.css("w=S8 h=S8 radius=Xl align=ACenter justify=JCenter hovered{bg=Hover}")

///|
let ws_more_icon : Double = 16.0

///|
/// The ⋯ menu open, by the person's sub ("" none).
// kept across runs: said again by each press; settings_reset empties it
let ws_menu : Ref[String] = Ref("")
