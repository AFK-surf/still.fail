// The workspace's page, one in every frame and the same on every width (the user, 2026-10-26: 「设置感觉很乱」; it was
// the web's desktop page wide and the narrow app's page narrow, two pages): who the viewer is there and how many it
// holds; its name and its mark, renamed and picked by its managers; its people in one list (those in it, those added
// who have not signed in, the invitations out), each pressed by a manager for what can be done about them (their role
// by the owner, moving them out: a panel, popover or sheet as the presenters say); 添加成员 at the title's end; its
// 连接方式 a row, its relays and the ways to its stations in a panel it opens (2026-10-29 the user: 不要平铺这么多
// 设置); leaving or deleting it in red at its foot, asked first. Its rows a list card's on either width (@sf.group), laid
// out by the page's width (page_look.mbt).

///|
/// The workspace's page (WorkspaceSettings, WorkspaceScreen), in the frame it is given.
pub fn workspace_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let topic = workspace_view(core, here)
  let v = topic.value
  let title = @sf.t("android-settings.workspace.title")
  guard v is Some(_) else {
    // (read the first time: a made-up workspace's page, in its bones)
    let error = match topic.error {
      Some(e) => error_text(e)
      None => ""
    }
    @sf.page_waiting(c, title, error~, fn() { workspace_shown(c, core.quiet(), here, frame, look, Some(workspace_sample())) })
  }
  workspace_shown(c, core, here, frame, look, v)
}

///|
/// The workspace's page as its view (`v`) says it.
fn workspace_shown(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame, look : Look, v : Json?) -> Unit {
  let role = text(v, "role")
  let manager = role == "owner" || role == "admin"
  let name = text(v, "name")
  let n = items(v, "members").length().to_string()
  let blocks = workspace_blocks(c, core, here, look, v)
  @sf.page(c, on_back=core.pop, frame~, "workspace",
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
        if c.clicked(id) {
          open_add_people(core, here, v, from=Of(id))
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
/// What the workspace's page holds (`v`, its view): its name and its mark, its people, its relays, leaving or deleting
/// it.
fn workspace_blocks(c : @ui.Ctx, core : Core, here : Here, look : Look, v : Json?) -> Array[() -> Unit] {
  let t = @sf.theme()
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
          // each by who it is: one who joins or leaves comes and goes where they are (@sf.group_rows)
          let rows : Array[(String, () -> Unit)] = []
          for m in members {
            let mv = Some(m)
            let who = if text(mv, "sub") != "" { text(mv, "sub") } else { text(mv, "email") }
            rows.push(("m/" + who, fn() { ws_member_row(c, core, here, v, m) }))
          }
          if manager {
            for a in added {
              let email = text(Some(a), "email")
              let on = [("workspace", ws), ("email", email)]
              rows.push(("a/" + email, fn() { ws_person(
                c,
                fn() { avatar(c, core, email, email, ws_avatar) },
                email,
                @sf.t("android-settings.members.added", args=[("role", role_label(text(Some(a), "role")))]),
                control=fn() {
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
              |> ignore }))
            }
            for i in invitations {
              let iv = Some(i)
              let id = text(iv, "id")
              let email = text(iv, "email")
              let on = [("workspace", ws), ("invitation", id)]
              rows.push(("i/" + id, fn() { ws_person(
                c,
                fn() { avatar(c, core, if email != "" { email } else { id }, if email != "" { email } else { "?" }, ws_avatar) },
                if email != "" { email } else { @sf.t("android-settings.members.anyone") },
                @sf.t("android-settings.members.invitation", args=[("role", role_label(text(iv, "role"))), ("until", stamp(iv, "expires_at", "until"))]),
                control=fn() {
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
              |> ignore }))
            }
          }
          @sf.group_rows(c, "ws-people/" + ws, rows)
        })
      },
    )
  })
  // how its members' devices reach its stations: one row, how many ways are turned off at its end; pressed, its relays
  // and the ways in a panel (ws_ways_panel)
  // (the core's `workspaceWays`, from what `/v1/me` said: there at once, the workspace not read again for it)
  let ways = (core.topic)("workspaceWays", { "workspace": str(ws) }).value
  let off = number(ways, "off")
  if manager || relays.length() > 0 || off > 0.0 {
    blocks.push(fn() {
      @sf.group(c, fn() {
        if @sf.link_row(c, "ws-ways", @sf.t("android-settings.ways.title"), value=text(ways, "offLabel")) {
          ws_ways_panel(core, here, Of(c.id("ws-ways")))
        }
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
  blocks
}

///|
/// A workspace made up, for what its page shows while it is read (workspace_blocks in its bones): its name, five
/// people.
fn workspace_sample() -> Json {
  {
    "name": Json::string(@sf.sample_words(4)),
    "role": "owner",
    "members": Json::array(
      [4, 3, 5, 3, 4].mapi(fn(i, n) {
        Json::object({
          "sub": Json::string("sample" + i.to_string()),
          "email": Json::string(@sf.sample_words(n + 8)),
          "name": Json::string(@sf.sample_words(n)),
          "role": "member",
        })
      }),
    ),
  }
}

///|
/// A person among the workspace's people, a row of its list card on either width (MemberRow): their picture, their
/// name (`badge` after it: 你), what is said under them, and at its end on its first line `value` (their role) or
/// `control` (移除, 撤回); pressed where `key` is given (what can be done about them, no chevron: it opens beside it).
fn ws_person(
  c : @ui.Ctx,
  picture : () -> Unit,
  name : String,
  under : String,
  value? : String = "",
  tail? : () -> Unit,
  control? : () -> Unit,
  badge? : String = "",
  key? : String = "",
) -> Bool {
  @sf.link_row(
    c,
    key,
    name,
    value~,
    note=under,
    lead=picture,
    face=true,
    tail?,
    control?,
    title_after?=if badge != "" { Some(fn() { you(c, badge) }) } else { None },
    goes=key != "",
    chevron=false,
  )
}

///|
/// A person in the workspace (MemberRow): their picture, name (你 for the viewer) and email, their role at its end;
/// pressed (where the viewer may), what can be done about them: their role (by the owner), moving them out, asked
/// first (ws_member_panel: a sheet with a finger, a popover with a mouse).
fn ws_member_row(c : @ui.Ctx, core : Core, here : Here, v : Json?, m : Json) -> Unit {
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
  let key = if can { "member/" + sub } else { "" }
  let on = [("workspace", ws), ("member", sub)]
  let calls = ["workspace.setRole", "workspace.removeMember"]
  let pressed = ws_person(
    c,
    fn() { avatar(c, core, email, name, ws_avatar, picture=text(mv, "picture")) },
    name,
    email,
    value=role_label(now),
    tail=fn() { doing_mark(c, is_doing(core, calls, on), failed_of(core, calls, on)) },
    badge=if sub == here.sub { @sf.t("android-settings.members.you") } else { "" },
    key~,
  )
  if pressed {
    ws_member_panel(core, here, v, m, name, Of(c.id(key)))
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
/// How the workspace's members' devices reach its stations (cloud setWay), by the row that opened it: still.fail's
/// relays, each on or off; the workspace's own, each removed, another added; the ways straight to a station (its LAN,
/// Tailscale, a path punched through), each on or off. Its managers' to change; the others see them. Read live: what
/// a change brings back shows at once.
fn ws_ways_panel(core : Core, here : Here, from : @sf.Anchor) -> Unit {
  @sf.panel(@sf.t("android-settings.ways.title"), from~, form=true, description=@sf.t("android-settings.ways.lead"), fn(c, close) {
    let v = workspace_view(core, here).value
    let role = text(v, "role")
    let manager = role == "owner" || role == "admin"
    let ws = text(v, "id")
    let ways = items((core.topic)("workspaceWays", { "workspace": str(ws) }).value, "ways")
    let relays = ways.filter(fn(w) { flag(Some(w), "own") }).map(fn(w) { text(Some(w), "id") })
    let busy = is_doing(core, ["workspace.setWay"], [("workspace", ws)])
    let turn = fn(w : Json, title : String, note : String) {
      let id = text(Some(w), "id")
      let on = flag(Some(w), "on")
      ws_way_row(c, title, note, fn() {
        if @sf.switch(c, "way/" + id, on, label=title, disabled=!manager, busy~) != on {
          @settings.act(
            core,
            @sf.t("android-settings.ways.setWhat"),
            "workspace.setWay",
            obj([("workspace", str(ws)), ("way", str(id)), ("on", Json::boolean(!on)), ("account", str(here.sub))]),
          )
        }
      })
    }
    let host = fn(url : String) { url.replace(old="https://", new="").replace(old="http://", new="") }
    // still.fail's relays
    ws_way_label(c, @sf.t("android-settings.ways.ours", args=[("app", "still.fail")]))
    for w in ways {
      if text(Some(w), "kind") == "relay" && !flag(Some(w), "own") {
        turn(w, text(Some(w), "name"), "")
      }
    }
    // its own: removed, added (one not wanted is taken away, not turned off)
    if manager || relays.length() > 0 {
      let setting = is_doing(core, ["workspace.setRelays"], [("workspace", ws)])
      ws_way_label(c, @sf.t("android-settings.ways.own"))
      for url in relays {
        ws_way_row(c, host(url), "", fn() {
          if manager && @sf.button(c, @sf.t("android-settings.members.remove"), key="relay/" + url, tone=Ghost, disabled=setting) {
            @settings.act(
              core,
              @sf.t("android-settings.relays.removeWhat"),
              "workspace.setRelays",
              obj([("workspace", str(ws)), ("relays", Json::array(relays.filter(fn(r) { r != url }).map(str))), ("account", str(here.sub))]),
              done=@sf.t("android-settings.relays.removed"),
            )
          }
        })
      }
      // (a row of its own, its words on the line the others' are, in the link's ink)
      if manager {
        let add = c.id("relay-add")
        if c.clicked(add) && !setting {
          close()
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
        let words = @sf.t(if setting { "common.saving" } else { "android-settings.relays.add" })
        let row = c.box(style=@sf.panel_words_in().then(ws_way_line), id=add, fn() {
          c.text(words, style=ws_way_link) |> ignore
        })
        c.semantics(row, Button, id=add, label=words)
      }
    }
    // straight to a station
    ws_way_label(c, @sf.t("android-settings.ways.straight"))
    for w in ways {
      match text(Some(w), "kind") {
        "lan" => turn(w, @sf.t("android-settings.ways.lan"), @sf.t("android-settings.ways.lanNote"))
        "tailnet" => turn(w, @sf.t("android-settings.ways.tailnet"), @sf.t("android-settings.ways.tailnetNote"))
        "direct" => turn(w, @sf.t("android-settings.ways.direct"), @sf.t("android-settings.ways.directNote"))
        _ => ()
      }
    }
    // (room under the last: its switch out of the panel's corner, not set in it)
    c.box(style=ws_way_end, fn() {  }) |> ignore
  })
}

///|
/// A row of the ways' panel: its title, `note` under it, `end` at its end (a switch, a button); on the panel's words'
/// line, as its description and its groups' labels are.
fn ws_way_row(c : @ui.Ctx, title : String, note : String, end : () -> Unit) -> Unit {
  c.box(style=@sf.panel_words_in().then(ws_way_line), fn() {
    c.box(style=ws_way_words, fn() {
      c.text(title, style=ws_way_title) |> ignore
      if note != "" {
        c.text(note, style=@sf.meta) |> ignore
      }
    })
    |> ignore
    end()
  })
  |> ignore
}

///|
/// A group's label in the ways' panel (still.fail's relays, its own, straight to a station): quiet, on the words' line.
fn ws_way_label(c : @ui.Ctx, words : String) -> Unit {
  c.box(style=@sf.panel_words_in().then(ws_way_label_at), fn() { c.text(words, style=@sf.meta) |> ignore }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let ws_way_line : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter py=S1_5")

///|
// kept across runs: a value (no field of it changes)
let ws_way_words : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let ws_way_label_at : @ui.Style = @ui.css("pt=S4 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let ws_way_end : @ui.Style = @ui.css("h=S3")

///|
// kept across runs: a value (no field of it changes)
let ws_way_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let ws_way_link : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=AccentText)

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
/// ⋯ (an icon button: 32, round: at its row's end in the middle of it, in none of its corners).
// kept across runs: a value (no field of it changes)
let ws_more : @ui.Style = @ui.css("w=S8 h=S8 radius=Full align=ACenter justify=JCenter hovered{bg=Hover}")

///|
pub let ws_more_icon : Double = 16.0
