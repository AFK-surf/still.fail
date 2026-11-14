// The workspace's page, one in every frame and the same on every width (the user, 2026-10-26: 「设置感觉很乱」; it was
// the web's desktop page wide and the narrow app's page narrow, two pages): who the viewer is there and how many it
// holds; its name and its mark, renamed and picked by its managers; its people in one list (those in it, those added
// who have not signed in, the invitations out), each pressed by a manager for what can be done about them (their role
// by the owner, moving them out: a panel, popover or sheet as the presenters say); 添加成员 at the title's end; its
// 中继 a row, its relays and the ways to its stations in a panel it opens (2026-10-29 the user: 不要平铺这么多
// 设置); leaving or deleting it in red at its foot, asked first. Its rows a list card's on either width (group_node),
// laid out by the page's width; made once as nodes of the window's tree (page_node).

///|
/// The workspace's page (WorkspaceSettings, WorkspaceScreen) made once as nodes (page_node, laid out by the `width` its
/// frame gives it, narrow where none is given) in node `v`: titled by its name, who the viewer is there and how many it
/// holds under that, adding people at its title's end (its managers'), then its blocks (workspace_block_node), each as
/// the core says it now; while it is read the first time, its blocks in their bones (waiting_node: a made-up
/// workspace's, the core asked nothing for it), what could not be read said over them. `here`: who and where, as that
/// changes; `stint`: the page's time on top (a person's picture, a mark's, asked for on it); a failure's why in `tips`.
pub fn workspace_node(
  v : @view.View,
  core : Core,
  here : () -> Here,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  stint~ : () -> Int,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
  tips? : @sf.TipLayer,
) -> Unit {
  let topic = fn() { workspace_view(core, here()) }
  let view = fn() { topic().value }
  let manager = fn() {
    let role = text(view(), "role")
    role == "owner" || role == "admin"
  }
  // (how its members' devices reach its stations: the core's `workspaceWays`, from what `/v1/me` said, there at once)
  let ways = fn() { (core.topic)("workspaceWays", { "workspace": str(text(view(), "id")) }).get().value }
  @sf.page_node(
    v,
    fn() {
      match view() {
        None => @sf.t("android-settings.workspace.title")
        w => text(w, "name")
      }
    },
    on_back~,
    frame~,
    said?,
    width?,
    tips?,
    // who the viewer is there and how many it holds
    lead=fn() {
      match view() {
        None => ""
        w => {
          let role = text(w, "role")
          @sf.t(if manager() { "android-settings.workspace.aboutRename" } else { "android-settings.workspace.about" }, args=[
            ("role", role_label(role)),
            ("people", @sf.t("android-settings.members.count", args=[("n", items(w, "members").length().to_string())])),
            ("stations", @sf.t("android-settings.workspace.stations", args=[("n", items(w, "stations").length().to_string())])),
          ])
        }
      }
    },
    // adding people, by email or from Slack: its managers'
    actions=fn(a) {
      a.show(manager, fn(s) {
        s.box(fn(k) {
          k
          .width(Is(Some(ws_add_side)))
          .height(Is(Some(ws_add_side)))
          // (round by its shape: the old view's radius=Full)
          .radius(Is(1.0e6))
          .lines_up(Is(Some(Middle)))
          .lies_along(Is(Middle))
          .ground(By(fn() { if @sf.lit_node(k) { @ui.tree_theme().color(Hover) } else { 0L } }))
          .says(By(fn() { Some(@view.said(Button, label=@sf.t("web-pages.settings.members.add"))) }))
          |> ignore
          @sf.presses_node(k, fn() {
            let (x, y, w, h) = k.placed_window_now()
            open_add_people(core, @signals.untracked(here), @signals.untracked(view), from=At(x, y, w, h))
          })
          @sf.icon_node(k, "user-plus", ws_add_icon, By(fn() { @sf.link_ink() })) |> ignore
        })
        |> ignore
      })
    },
    fn() {
      match view() {
        None => ["waiting"]
        w => {
          let out = ["name", "people"]
          if manager() || strings(w, "relays").length() > 0 || number(ways(), "off") > 0.0 {
            out.push("ways")
          }
          out.push("leave")
          out
        }
      }
    },
    fn(b, key) {
      if key == "waiting" {
        // (read the first time: a made-up workspace's blocks, in their bones)
        @sf.waiting_node(
          b,
          fn(s) {
            let sample = Some(workspace_sample())
            for k in ["name", "people", "leave"] {
              workspace_block_node(s, core.quiet(), here, fn() { sample }, stint, tips, k)
            }
          },
          error=fn() {
            match topic().error {
              Some(e) => error_text(e)
              None => ""
            }
          },
        )
      } else {
        workspace_block_node(b, core, here, view, stint, tips, key)
      }
    },
  )
}

///|
/// A block of the workspace's page by its `key`, as its view (`view`) says it now: its name and its mark ("name",
/// renamed and picked by its managers), its people ("people"), how its members' devices reach its stations ("ways"),
/// leaving or deleting it ("leave").
fn workspace_block_node(
  b : @view.View,
  core : Core,
  here : () -> Here,
  view : () -> Json?,
  stint : () -> Int,
  tips : @sf.TipLayer?,
  key : String,
) -> Unit {
  let role = fn() { text(view(), "role") }
  let manager = fn() { role() == "owner" || role() == "admin" }
  let ws = fn() { text(view(), "id") }
  let name = fn() { text(view(), "name") }
  match key {
    // its name and its mark: renamed, picked by its managers
    "name" =>
      @sf.group_node(b, fn(g) {
        g.pick(manager, fn(p, managed) {
          @sf.link_row_node(
            p,
            fn() { @sf.t("android-settings.workspace.name") },
            fn() {
              let ws = @signals.untracked(ws)
              let name = @signals.untracked(name)
              ask(@sf.t("android-settings.workspace.name"), name, @sf.t("android-settings.workspace.namePlaceholder"), @sf.t("common.save"), fn(
                line,
              ) {
                @settings.act(
                  core,
                  @sf.t("android-settings.workspace.renameWhat"),
                  "workspace.rename",
                  obj([("workspace", str(ws)), ("name", str(line)), ("account", str(@signals.untracked(here).sub))]),
                  done=@sf.t("android-settings.renamed"),
                )
              })
            },
            value=name,
            chevron=managed,
            goes=managed,
          )
          if managed {
            let emoji = fn() { text(view(), "emoji") }
            let icon = fn() { text(view(), "icon") }
            let marked = fn() { @sf.has_station_mark(emoji(), icon()) }
            let on = fn() { [("workspace", ws())] }
            let busy = fn() { is_doing(core, ["workspace.rename"], on()) }
            let failed = fn() { failed_of(core, ["workspace.rename"], on()) }
            @sf.link_row_node(
              p,
              fn() { @sf.t("android-settings.workspace.icon") },
              fn() {
                let ws = @signals.untracked(ws)
                open_mark_pick(core, @signals.untracked(name), @signals.untracked(emoji), @signals.untracked(icon), @sf.t("android-settings.workspace.iconWhat"), fn(
                  emoji,
                  icon,
                  done,
                ) {
                  (core.call)(
                    "workspace.rename",
                    obj([("workspace", str(ws)), ("emoji", str(emoji)), ("icon", str(icon)), ("account", str(@signals.untracked(here).sub))]),
                    done,
                  )
                })
              },
              value=fn() { if marked() { "" } else { @sf.t("android-settings.workspace.iconNone") } },
              tail=fn(e) {
                e.gap(Is(ws_tail_gap)) |> ignore
                e.show(fn() { busy() || failed() is Some(_) }, fn(d) { doing_mark_node(d, busy, failed, tips?, size=ws_doing_mark) })
                e.show(marked, fn(m) { @sf.station_mark_node(m, emoji, icon, ws_mark_narrow, fn() { @sf.theme().p.text }, stint) })
              },
              tail_shown=fn() { busy() || failed() is Some(_) || marked() },
            )
          }
        })
      })
    // its people in one list
    "people" =>
      @sf.section_node(
        b,
        fn() { @sf.t("android-settings.members.title") },
        note=fn() {
          let n = items(view(), "members").length().to_string()
          let waiting = if manager() { items(view(), "added").length() + items(view(), "invitations").length() } else { 0 }
          if waiting > 0 {
            @sf.t("android-settings.members.waiting", args=[("n", n), ("waiting", waiting.to_string())])
          } else {
            @sf.t("android-settings.members.count", args=[("n", n)])
          }
        },
        fn(s) {
          @sf.group_node(s, fn(g) {
            // each by who it is: one who joins or leaves comes and goes where they are
            g.each(fn() { ws_people(view(), manager()) }, fn(p) { p.0 }, fn(row, p) {
              let pv = fn() { Some(p.get().1) }
              match @signals.untracked(fn() { p.get().0 }) {
                k if k.has_prefix("m/") => ws_member_row_node(row, core, here, view, pv, stint, tips)
                k if k.has_prefix("a/") => {
                  let email = fn() { text(pv(), "email") }
                  let on = fn() { [("workspace", ws()), ("email", email())] }
                  ws_person_node(
                    row,
                    fn(l) { ws_avatar_node(l, core, email, email, fn() { "" }, stint) },
                    email,
                    fn() { @sf.t("android-settings.members.added", args=[("role", role_label(text(pv(), "role")))]) },
                    control=fn(e) {
                      ws_row_action_node(e, @sf.t("android-settings.members.remove"), core, ["workspace.removeAdded"], on, tips, fn() {
                        @settings.act(
                          core,
                          @sf.t("android-settings.members.removeWhat"),
                          "workspace.removeAdded",
                          obj([("workspace", str(@signals.untracked(ws))), ("email", str(@signals.untracked(email))), ("account", str(@signals.untracked(here).sub))]),
                          done=@sf.t("android-settings.members.removed"),
                        )
                      })
                    },
                  )
                }
                _ => {
                  let id = fn() { text(pv(), "id") }
                  let email = fn() { text(pv(), "email") }
                  let on = fn() { [("workspace", ws()), ("invitation", id())] }
                  ws_person_node(
                    row,
                    fn(l) {
                      ws_avatar_node(l, core, fn() { if email() != "" { email() } else { id() } }, fn() { if email() != "" { email() } else { "?" } }, fn() {
                        ""
                      }, stint)
                    },
                    fn() { if email() != "" { email() } else { @sf.t("android-settings.members.anyone") } },
                    fn() {
                      @sf.t("android-settings.members.invitation", args=[("role", role_label(text(pv(), "role"))), ("until", stamp(pv(), "expires_at", "until"))])
                    },
                    control=fn(e) {
                      ws_row_action_node(e, @sf.t("android-settings.members.revoke"), core, ["workspace.revokeInvitation"], on, tips, fn() {
                        @settings.act(
                          core,
                          @sf.t("android-settings.members.revokeWhat"),
                          "workspace.revokeInvitation",
                          obj([("workspace", str(@signals.untracked(ws))), ("invitation", str(@signals.untracked(id))), ("account", str(@signals.untracked(here).sub))]),
                          done=@sf.t("android-settings.members.revoked"),
                        )
                      })
                    },
                  )
                }
              }
            })
          })
        },
      )
    // how its members' devices reach its stations: one row, how many ways are turned off at its end; pressed, its relays
    // and the ways in a panel (ws_ways_panel)
    "ways" =>
      @sf.group_node(b, fn(g) {
        g.box(fn(at) {
          @sf.link_row_node(
            at,
            fn() { @sf.t("android-settings.ways.title") },
            fn() {
              let (x, y, w, h) = at.placed_window_now()
              ws_ways_panel(core, @signals.untracked(here), At(x, y, w, h))
            },
            value=fn() { text((core.topic)("workspaceWays", { "workspace": str(ws()) }).get().value, "offLabel") },
          )
        })
        |> ignore
      })
    // leaving or deleting it, in red at the foot, asked first
    _ =>
      @sf.group_node(b, fn(g) {
        @sf.link_row_node(
          g,
          fn() { @sf.t("android-settings.workspace.leaveRow") },
          fn() {
            let ws = @signals.untracked(ws)
            let name = @signals.untracked(name)
            let sub = @signals.untracked(here).sub
            confirm(
              @sf.t("android-settings.workspace.leaveTitle", args=[("name", name)]),
              @sf.t("android-settings.workspace.leaveText"),
              @sf.t("android-settings.workspace.leave"),
              danger=true,
              fn() {
                ws_gone(
                  core,
                  ws,
                  @sf.t("android-settings.workspace.leaveWhat"),
                  "workspace.removeMember",
                  obj([("workspace", str(ws)), ("member", str(sub)), ("account", str(sub))]),
                  @sf.t("android-settings.workspace.left"),
                )
              },
            )
          },
          danger=true,
          chevron=false,
        )
        g.show(fn() { role() == "owner" }, fn(o) {
          @sf.link_row_node(
            o,
            fn() { @sf.t("android-settings.workspace.delete") },
            fn() {
              let v = @signals.untracked(view)
              let ws = text(v, "id")
              let name = text(v, "name")
              let sub = @signals.untracked(here).sub
              confirm(
                @sf.t("android-settings.workspace.deleteTitle", args=[("name", name)]),
                @sf.t("android-settings.workspace.deleteText", args=[("n", items(v, "stations").length().to_string()), ("app", "still.fail")]),
                @sf.t("android-settings.workspace.delete"),
                danger=true,
                fn() {
                  ws_gone(
                    core,
                    ws,
                    @sf.t("android-settings.workspace.deleteWhat"),
                    "workspace.delete",
                    obj([("workspace", str(ws)), ("account", str(sub))]),
                    @sf.t("android-settings.workspace.deleted"),
                  )
                },
              )
            },
            danger=true,
            chevron=false,
          )
        })
      })
  }
}

///|
/// The workspace's people as its view (`v`) says them, each by who it is: those in it ("m/"); its managers' (`manager`)
/// also those added who have not signed in ("a/") and the invitations out ("i/").
fn ws_people(v : Json?, manager : Bool) -> Array[(String, Json)] {
  let out : Array[(String, Json)] = []
  for m in items(v, "members") {
    let mv = Some(m)
    out.push(("m/" + (if text(mv, "sub") != "" { text(mv, "sub") } else { text(mv, "email") }), m))
  }
  if manager {
    for a in items(v, "added") {
      out.push(("a/" + text(Some(a), "email"), a))
    }
    for i in items(v, "invitations") {
      out.push(("i/" + text(Some(i), "id"), i))
    }
  }
  out
}

///|
/// A person among the workspace's people, a row of its list card on either width (MemberRow) in `parent`: their
/// picture (`picture` makes it), their name (`badge` after it while it says one: 你), what is said under them, and at
/// its end on its first line `value` (their role) or `control` (移除, 撤回); pressed where it `goes` (what can be done
/// about them, no chevron: it opens beside it), `press` done then. Each as it is said now.
fn ws_person_node(
  parent : @view.View,
  picture : (@view.View) -> Unit,
  name : () -> String,
  under : () -> String,
  value? : () -> String = fn() { "" },
  tail? : (@view.View) -> Unit,
  tail_shown? : () -> Bool = fn() { true },
  control? : (@view.View) -> Unit,
  badge? : () -> String = fn() { "" },
  goes? : Bool = false,
  press? : () -> Unit = fn() {  },
) -> Unit {
  @sf.link_row_node(
    parent,
    name,
    press,
    value~,
    note=under,
    lead=LeadMade(picture),
    face=true,
    tail?,
    tail_shown~,
    control?,
    title_after=fn(a) { ws_you_node(a, badge) },
    title_after_shown=fn() { badge() != "" },
    goes~,
    chevron=false,
  )
}

///|
/// A person in the workspace (MemberRow), `m` as it is now: their picture, name (你 for the viewer) and email, their
/// role at its end; pressed (where the viewer may), what can be done about them: their role (by the owner), moving them
/// out, asked first (ws_member_panel: a sheet with a finger, a popover with a mouse, beside the row).
fn ws_member_row_node(
  row : @view.View,
  core : Core,
  here : () -> Here,
  view : () -> Json?,
  m : () -> Json?,
  stint : () -> Int,
  tips : @sf.TipLayer?,
) -> Unit {
  let sub = fn() { text(m(), "sub") }
  let email = fn() { text(m(), "email") }
  let name = fn() {
    match text(m(), "name") {
      "" => email()
      x => x
    }
  }
  let can = fn() {
    let role = text(view(), "role")
    let manager = role == "owner" || role == "admin"
    sub() != here().sub && manager && (text(m(), "role") != "owner" || role == "owner")
  }
  let on = fn() { [("workspace", text(view(), "id")), ("member", sub())] }
  let calls = ["workspace.setRole", "workspace.removeMember"]
  let busy = fn() { is_doing(core, calls, on()) }
  let failed = fn() { failed_of(core, calls, on()) }
  row.pick(can, fn(r, can) {
    ws_person_node(
      r,
      fn(l) { ws_avatar_node(l, core, email, name, fn() { text(m(), "picture") }, stint) },
      name,
      email,
      value=fn() { role_label(text(m(), "role")) },
      tail=fn(e) { doing_mark_node(e, busy, failed, tips?, size=ws_doing_mark) },
      tail_shown=fn() { busy() || failed() is Some(_) },
      badge=fn() { if sub() == here().sub { @sf.t("android-settings.members.you") } else { "" } },
      goes=can,
      press=fn() {
        let (x, y, w, h) = r.placed_window_now()
        let mv = @signals.untracked(m)
        ws_member_panel(core, @signals.untracked(here), mv.unwrap_or(Json::null()), @signals.untracked(name), At(x, y, w, h))
      },
    )
  })
}

///|
/// A person's picture on the workspace's page (avatar's, as a node): `picture` (the core's, asked for on the page's
/// time on top, `stint`) once it comes, their initial on their colour (by `id`) till then, 28 round.
fn ws_avatar_node(
  parent : @view.View,
  core : Core,
  id : () -> String,
  name : () -> String,
  picture : () -> String,
  stint : () -> Int,
) -> Unit {
  @sf.avatar_node(parent, id, name, fn() {
    let p = picture()
    if p == "" { "" } else { (core.picture)(p, stint()) }
  }, ws_avatar)
}

///|
/// A word in the accent's wash after a person's name (you's: 你), whole on its line, as `words` says it now.
fn ws_you_node(parent : @view.View, words : () -> String) -> Unit {
  parent.box(fn(g) {
    @sf.style_node(g, fn() { ws_you_ground })
    @sf.words_node(g, words, fn() { ws_you_words }) |> ignore
  })
  |> ignore
}

///|
/// You's wash: 6 in at its sides, 6 round.
// kept across runs: a value (no field of it changes)
let ws_you_ground : @ui.Style = @ui.css("px=S1_5 radius=Md bg=AccentBg")

///|
/// Small words in the accent's ink.
// kept across runs: a value (no field of it changes)
let ws_you_words : @ui.TextStyle = @sf.caption.then(@ui.text_style(color=AccentText, wrap=false))

///|
/// What a row does at its end (RowAction) in `e`: a quiet button as every row's on the settings' pages (账号's 退出),
/// turning while it is under way, the failure mark before it a moment after (why in `tips`); `run` done as it is
/// pressed.
fn ws_row_action_node(
  e : @view.View,
  words : String,
  core : Core,
  calls : Array[String],
  on : () -> Array[(String, String)],
  tips : @sf.TipLayer?,
  run : () -> Unit,
) -> Unit {
  e.row(Is(true)).gap(Is(ws_tail_gap)).lines_up(Is(Some(Middle))) |> ignore
  let failed = fn() { failed_of(core, calls, on()) }
  e.show(fn() { failed() is Some(_) }, fn(d) { doing_mark_node(d, fn() { false }, failed, tips?, size=ws_doing_mark) })
  @sf.row_end_button_node(e, fn() { words }, run, busy=fn() { is_doing(core, calls, on()) }) |> ignore
}

///|
/// The workspace `ws` left or deleted (`call`): another of the viewer's workspaces in view at once, at its Home, while
/// still.fail cloud is asked; `done` said once it answers. (Home on `ws` itself read as broken: its chats turned to
/// 已登录的账号均无法访问此 workspace as the cloud let it go, until the list dropped it.)
fn ws_gone(core : Core, ws : String, what : String, call : String, params : Json, done : String) -> Unit {
  let (all, _, _) = @sfbase.workspaces_of((core.topic)("workspaces", {}).get().value)
  match all.iter().find_first(fn(w) { w.id != ws }) {
    Some(o) => {
      app.picked.set(o.id)
      (core.call)("prefs.set", { "workspace": Json::string(o.id) }, @sfbase.answer_unread)
    }
    None => ()
  }
  (core.home)()
  @settings.act(core, what, call, params, done~)
}

///|
/// A workspace made up, for what its page shows while it is read (workspace_block_node in its bones): its name, five
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
/// What can be done about person `m` (MemberSheet), by what pressed them: their role (by the owner: each with what it
/// may do, the one now checked, not picked again while one is being set), moving them out (in red, asked first: closed
/// for the asking, a step further in). A panel (a sheet with a finger) of nodes of the window's tree, made once as it
/// opens, bound to the workspace as the core says it now (`here`'s): their role set elsewhere moves the check, the
/// viewer made owner or no longer shows or hides the roles; closed once they are no longer in it or the viewer may no
/// longer do anything about them (ws_member_row_node's `can`), what it showed last kept as it goes.
fn ws_member_panel(core : Core, here : Here, m : Json, name : String, from : @sf.Anchor) -> Unit {
  let sub = text(Some(m), "sub")
  @sf.panel_nodes(name, from~, fn(v, close) {
    // (the workspace and the person in it as the core says them now, while the viewer may act on them; else what was
    // last so, kept as the panel goes)
    let now = fn() -> (Json?, Json)? {
      let w = workspace_view(core, here).value
      guard w is Some(_) else { return None }
      match items(w, "members").iter().find_first(fn(x) { text(Some(x), "sub") == sub }) {
        Some(x) => {
          let role = text(w, "role")
          let may = (role == "owner" || role == "admin") && (text(Some(x), "role") != "owner" || role == "owner")
          if may { Some((w, x)) } else { None }
        }
        None => None
      }
    }
    let last : Ref[(Json?, Json)] = Ref((None, m))
    let shown = fn() {
      match now() {
        Some(x) => {
          last.val = x
          x
        }
        None => last.val
      }
    }
    v.reacts(fn() { workspace_view(core, here).value is Some(_) && now() is None }, fn(gone) { if gone { close() } })
    let ws = fn() { text(shown().0, "id") }
    let role = fn() { text(Some(shown().1), "role") }
    let setting = fn() { is_doing(core, ["workspace.setRole"], [("workspace", ws()), ("member", sub)]) }
    for r in ["owner", "admin", "member"] {
      v.show(fn() { text(shown().0, "role") == "owner" }, fn(row) {
        @sf.choice_row_node(
          row,
          fn() { role_label(r) },
          fn() { role() == r },
          note=fn() { @sf.t("android-misc.role." + r + ".hint") },
          disabled=setting,
          press=fn() {
            let was = @signals.untracked(role)
            let ws = @signals.untracked(ws)
            close()
            if r != was {
              @settings.act(
                core,
                @sf.t("android-settings.members.roleWhat"),
                "workspace.setRole",
                obj([("workspace", str(ws)), ("member", str(sub)), ("role", str(r)), ("account", str(here.sub))]),
                done=@sf.t("android-settings.members.roleSet"),
              )
            }
          },
        )
      })
    }
    @sf.choice_row_node(
      v,
      fn() { @sf.t("android-settings.members.moveOutRow") },
      fn() { false },
      ink=fn() { @sf.theme().p.red },
      press=fn() {
        let (w, x) = @signals.untracked(shown)
        let ws = text(w, "id")
        close()
        confirm(
          @sf.t("android-settings.members.moveOutTitle", args=[("email", text(Some(x), "email")), ("name", text(w, "name"))]),
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
      },
    )
  })
}

///|
/// How the workspace's members' devices reach its stations (cloud setWay, setRelays), by the row that opened it: the
/// workspace's own relays first (each removed, another added right in the panel), then still.fail's relays as one master
/// switch (turned off only while the workspace has a relay of its own). Its managers' to change; the others see them.
/// A panel of nodes of the window's tree, made once as it opens and bound to what the core says now (`here`'s workspace,
/// its `workspaceWays`): what a change brings back shows at once, the viewer no longer a manager turns nothing of it.
fn ws_ways_panel(core : Core, here : Here, from : @sf.Anchor) -> Unit {
  let new_relay = @ui.Field::new()
  @sf.panel_nodes(@sf.t("android-settings.ways.title"), from~, form=true, description=@sf.t("android-settings.ways.lead"), fn(v, _close) {
    let view = fn() { workspace_view(core, here).value }
    let manager = fn() {
      let role = text(view(), "role")
      role == "owner" || role == "admin"
    }
    let ws = fn() { text(view(), "id") }
    let ways = fn() { items((core.topic)("workspaceWays", { "workspace": str(ws()) }).get().value, "ways") }
    let ours_ways = fn() { ways().filter(fn(w) { text(Some(w), "kind") == "relay" && !flag(Some(w), "own") }) }
    let relays = fn() { ways().filter(fn(w) { flag(Some(w), "own") }).map(fn(w) { text(Some(w), "id") }) }
    let ours_on = fn() { relays().is_empty() || ours_ways().iter().any(fn(w) { flag(Some(w), "on") }) }
    let ours_note = fn() {
      if !manager() {
        ours_ways().map(fn(w) { text(Some(w), "name") }).filter(fn(n) { n != "" }).join("、")
      } else if relays().is_empty() {
        @sf.t("android-settings.ways.oursNeedOwn")
      } else {
        @sf.t("android-settings.ways.oursNote")
      }
    }
    let busy = fn() { is_doing(core, ["workspace.setWay"], [("workspace", ws())]) }
    let setting = fn() { is_doing(core, ["workspace.setRelays"], [("workspace", ws())]) }
    let id = fn(w : Json) { text(Some(w), "id") }
    let host = fn(url : String) { url.replace(old="https://", new="").replace(old="http://", new="") }
    // (who added each, as its stations keep it: an agent's chat, a person)
    let added_by = fn(url : String) {
      match ways().filter(fn(w) { id(w) == url }).get(0) {
        Some(w) => {
          let by = text(Some(w), "by")
          if by == "" { "" } else { @sf.t("android-settings.relays.by", args=[("by", by)]) }
        }
        None => ""
      }
    }
    let can_add = fn() { !setting() && !new_relay.text().trim(chars=" \t\n").is_empty() }
    let add_relay = fn() {
      guard @signals.untracked(can_add) else { return }
      let line = @signals.untracked(fn() { new_relay.text().trim(chars=" \t\n").to_owned() })
      new_relay.set("")
      let next = @signals.untracked(relays).copy()
      next.push(line)
      @settings.act(
        core,
        @sf.t("android-settings.relays.add"),
        "workspace.setRelays",
        obj([("workspace", str(@signals.untracked(ws))), ("relays", Json::array(next.map(str))), ("account", str(here.sub))]),
        done=@sf.t("android-settings.relays.added"),
      )
    }
    v.box(fn(body) {
      @sf.style_node(body, fn() {
        if @sf.look_node(body) is Wide || (manager() && relays().length() < 4) {
          ws_way_body_wide
        } else {
          ws_way_body_narrow
        }
      })
      // add a custom relay at the top of the panel
      body.show(fn() { manager() && relays().length() < 4 }, fn(a) {
        a.box(fn(row) {
          @sf.style_node(row, fn() {
            let at = if @sf.look_node(row) is Wide { ws_way_add_row_wide } else { ws_way_add_row_narrow }
            @sf.panel_words_in_node(row).then(at)
          })
          row.box(fn(f) {
            @sf.style_node(f, fn() { ws_way_add_input }, in_row=true)
            @sf.input_node(
              f,
              new_relay,
              placeholder="https://relay.example.com",
              label=@sf.t("android-settings.relays.add"),
              disabled=setting,
              submitted=fn(_) { add_relay() },
            )
            |> ignore
          })
          |> ignore
          @sf.button_node(
            row,
            fn() { @sf.t("android-settings.relays.addAction") },
            add_relay,
            tone=Primary,
            busy=setting,
            disabled=fn() { !can_add() },
          )
          |> ignore
        })
        |> ignore
      })
      // its own relays: each removed right in the panel (one not wanted is taken away, not turned off)
      body.each(relays, fn(url) { url }, fn(row, url) {
        row.box(fn(b) {
          ws_way_row_node(b, fn() { host(url.get()) }, fn() { added_by(url.get()) }, fn(e) {
            e.show(manager, fn(k) {
              @sf.row_end_button_node(
                k,
                fn() { @sf.t("android-settings.members.remove") },
                fn() {
                  let url = @signals.untracked(fn() { url.get() })
                  let all = @signals.untracked(relays)
                  @settings.act(
                    core,
                    @sf.t("android-settings.relays.removeWhat"),
                    "workspace.setRelays",
                    obj([("workspace", str(@signals.untracked(ws))), ("relays", Json::array(all.filter(fn(r) { r != url }).map(str))), ("account", str(here.sub))]),
                    done=@sf.t("android-settings.relays.removed"),
                  )
                },
                disabled=setting,
              )
              |> ignore
            })
          })
        })
        |> ignore
      })
      // still.fail's relays: one switch for all of them, what it does under it
      let title = fn() { @sf.t("android-settings.ways.ours") }
      ws_way_row_node(body, title, ours_note, last=true, fn(e) {
        e.show(busy, fn(s) { @sf.spinner_node(s, size=@sf.spinner_size) |> ignore })
        @sf.switch_node(
          e,
          ours_on,
          fn(on) {
            @settings.act(
              core,
              @sf.t("android-settings.ways.setWhat"),
              "workspace.setWay",
              obj([("workspace", str(@signals.untracked(ws))), ("way", str("ours")), ("on", Json::boolean(on)), ("account", str(here.sub))]),
            )
          },
          title,
          disabled=fn() { !manager() || busy() || relays().is_empty() },
        )
      })
    })
    |> ignore
  })
}

///|
/// A row of the ways' panel in `parent`: its title, `note` under it (none where it says ""), what `end` makes at its end
/// (a switch, a button) aligned with its first line (`title`); on the panel's words' line, as its description and its
/// groups' labels are. Each as it is said now.
fn ws_way_row_node(
  parent : @view.View,
  title : () -> String,
  note : () -> String,
  end : (@view.View) -> Unit,
  last? : Bool = false,
) -> Unit {
  parent.box(fn(r) {
    let line = if last { ws_way_last_line } else { ws_way_line }
    @sf.style_node(r, fn() { @sf.panel_words_in_node(r).then(line) })
    r.box(fn(w) {
      @sf.style_node(w, fn() { ws_way_words }, in_row=true)
      @sf.words_node(w, title, fn() { ws_way_title }) |> ignore
      w.show(fn() { note() != "" }, fn(n) { @sf.words_node(n, note, fn() { @sf.meta.then(@sf.in_lines) }) |> ignore })
    })
    |> ignore
    r.box(fn(e) {
      @sf.style_node(e, fn() { ws_way_end_line }, in_row=true)
      end(e)
    })
    |> ignore
  })
  |> ignore
}

///|
/// A group's label in a panel in `parent` (station_retire_panel's): quiet, on the words' line, `words` as they are said
/// now.
fn ws_way_label_node(parent : @view.View, words : () -> String) -> Unit {
  parent.box(fn(l) {
    @sf.style_node(l, fn() { @sf.panel_words_in_node(l).then(ws_way_label_at) })
    @sf.words_node(l, words, fn() { @sf.meta }) |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let ws_way_body_wide : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let ws_way_body_narrow : @ui.Style = @ui.css("w=Full pt=S2")

///|
// kept across runs: a value (no field of it changes)
let ws_way_line : @ui.Style = @ui.css("row w=Full gap=S3 align=AStart py=S1_5")

///|
// kept across runs: a value (no field of it changes)
let ws_way_last_line : @ui.Style = @ui.css("row w=Full gap=S3 align=AStart pt=S1_5")

///|
// kept across runs: a value (no field of it changes)
let ws_way_end_line : @ui.Style = @ui.css("row gap=S2 align=ACenter h=S5")

///|
// kept across runs: a value (no field of it changes)
let ws_way_words : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let ws_way_label_at : @ui.Style = @ui.css("pt=S4 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let ws_way_add_row_wide : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter pb=S2_5")

///|
// kept across runs: a value (no field of it changes)
let ws_way_add_row_narrow : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter pt=S3_5 pb=S2_5")

///|
// kept across runs: a value (no field of it changes)
let ws_way_add_input : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let ws_way_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg)

///|
let ws_avatar : Double = 28.0

///|
let ws_mark_narrow : Double = 20.0

///|
/// What a person's row or the mark's says at its end, how it stands (doing_mark's, not inline: 14), and the room
/// between what stands there.
let ws_doing_mark : Double = 14.0

///|
let ws_tail_gap : Double = 12.0

///|
/// 添加成员 at the title's end: 40 round (w=S10 h=S10), its icon 20 in the link's ink.
let ws_add_side : Double = 40.0

///|
let ws_add_icon : Double = 20.0

///|
pub let ws_more_icon : Double = 16.0
