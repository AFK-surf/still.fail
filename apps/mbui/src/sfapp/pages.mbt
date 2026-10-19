// The pages pushed from Home, as far as these slices go: a chat (chat.mbt), the archive and settings (Parts.kt NavBar
// over nothing yet); the filter's menu (Sheet.kt MenuHost) and the workspaces' sheet (Workspaces.kt WorkspacesSheet, in
// Sheet.kt's frame).

///|
/// A page's compact bar (Parts.kt NavBar): back to the chats, in the accent; its title in the middle.
fn nav_bar(c : @ui.Ctx, title : String) -> Unit {
  let t = @sf.theme()
  // the wide frame's page bar (wide_chat.mbt)
  if wide_on.val {
    if page_bar_wide(c, title, app.nav.depth() > 1, fn() {  }) {
      app.nav.pop() |> ignore
    }
    return
  }
  c.box(w=Fill(1.0), pl=10.0, pr=16.0, pt=6.0, pb=10.0, fn() {
    c.box(dir=Row, w=Fill(1.0), h=Px(32.0), align=ACenter, fn() {
      let back = c.id("nav-back")
      if c.clicked(back) {
        app.nav.pop() |> ignore
      }
      c.box(
        dir=Row,
        pr=6.0,
        pt=4.0,
        pb=4.0,
        radius=8.0,
        align=ACenter,
        opacity=if c.pressed(back) { 0.6 } else { 1.0 },
        id=back,
        fn() {
          @sf.icon(c, "chevron-left", size=22.0, color=t.p.accent) |> ignore
          c.text(tr("android-misc.bar.place.chats"), size=17.0, color=t.p.accent, wrap=false)
          |> ignore
        },
      )
      |> ignore
      c.layer(align=ACenter, fn() {
        c.box(h=Px(30.0), justify=JCenter, pl=84.0, pr=84.0, fn() {
          c.text(title, size=16.0, weight=600, color=t.p.text, wrap=false) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A page this slice does not fill yet: its bar.
fn placeholder_page(c : @ui.Ctx, title : String) -> Unit {
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    nav_bar(c, title)
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// The scrim under a menu or a sheet (black at 28%), which closes it when tapped.
fn scrim(
  c : @ui.Ctx,
  key : String,
  shown : Double,
  open? : Bool = true,
  close : () -> Unit,
) -> Unit {
  let id = c.id(key)
  if c.clicked(id) && open {
    close()
  }
  let l = c.layer(fn() {
    c.box(w=Fill(1.0), h=Fill(1.0), bg=@sf.alpha(0x000000FFL, 0.28 * shown), id~, fn() {  })
    |> ignore
  })
  // fading once let go of, only drawn: it takes no tap from the page coming back under it
  @motion.leaving(c, l, open)
}

///|
/// The filter's menu (Home.kt, in Sheet.kt MenuHost's look): 180 wide under the filter's button, its right edge
/// under the button's: 全部, 我参与的, 监控中 (the one in use checked), 已归档.
fn filter_menu(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let filter = filter_of(src, w.id)
  // in: its opacity 160 ms (Ease.Out), its scale from 90% on the menu's spring, from its top left; out: 120 ms (CSS's
  // ease-out), back to 90%; the scrim 200 ms (Sheet.kt MenuHost). Drawn until it has gone.
  let look = match
    @motion.presence(
      c,
      "filter-menu",
      app.menu,
      enter=@motion.trans(fade=0.0, scale=0.9, ox=0.0, oy=0.0, spec=@motion.menu_spring, fade_spec=@motion.tween(160.0, ease=Out)),
      exit=@motion.trans(fade=0.0, scale=0.9, ox=0.0, oy=0.0, spec=@motion.menu_spring, fade_spec=@motion.tween(120.0, ease=CssOut)),
    ) {
    Some(l) => l
    None => return
  }
  let shown = @motion.animate(c, "filter-menu/scrim", if app.menu { 1.0 } else { 0.0 }, spec=@motion.tween(200.0))
  scrim(c, "filter-scrim", shown, open=app.menu, fn() { app.menu = false })
  let x = dmax(12.0, c.width - 16.0 - 180.0)
  c.layer(fn() {
    let menu = c.box(
      w=Px(180.0),
      tx=x,
      ty=bar_h + 6.0,
      radius=14.0,
      bg=t.p.card,
      shadow=18.0,
      shadow_y=6.0,
      clip=true,
      fn() {
        let item = fn(label : String, icon : String, key : String) -> Bool {
          let id = c.id("filter/" + key)
          c.box(
            dir=Row,
            w=Fill(1.0),
            padx=16.0,
            pady=12.0,
            align=ACenter,
            justify=JBetween,
            bg=@sf.alpha(t.p.text, 0.06 * @motion.pressing(c, id)),
            id~,
            fn() {
              c.text(label, size=15.0, color=t.p.text, wrap=false, line=21.0) |> ignore
              if icon != "" {
                @sf.icon(c, icon, size=16.0, color=t.p.text) |> ignore
              } else {
                c.box(w=Px(16.0), h=Px(16.0), fn() {  }) |> ignore
              }
            },
          )
          |> ignore
          c.clicked(id)
        }
        for f in ["all", "mine", "watching"] {
          if item(
              tr("android-chat.home.filter." + f),
              if filter == f { "check" } else { "" },
              f,
            ) {
            app.menu = false
            app.filters[w.id] = f
            let pick : Map[String, Json] = {}
            pick[w.id] = Json::string(f)
            (src.call)(
              "prefs.set",
              Json::object({ "listFilter": Json::object(pick) }),
              fn(_) {  },
            )
          }
        }
        if item(tr("android-chat.home.filter.archived"), "archive", "archived") {
          app.menu = false
          app.nav.push(Archived)
        }
      },
    )
    c.look(menu, look)
    @motion.leaving(c, menu, app.menu)
  })
  |> ignore
}

///|
/// The workspaces' sheet (Workspaces.kt WorkspacesSheet, in a draggable sheet of 70%: sheet.mbt): the workspace in use
/// (checked), the others to switch to (what each has waiting at its end), signing in another account. A workspace
/// tapped is the one in view from then on (the prefs' `workspace`), Home at its top.
fn workspaces_sheet(c : @ui.Ctx, src : Source, w : Workspace, all : Array[Workspace]) -> Unit {
  let marks = (src.topic)("workspaceMarks", { "workspace": Json::string(w.id) })
  let by_ws = field(marks.value, "workspaces")
  let any_marked = all.iter().any(fn(x) { @sf.has_station_mark(x.emoji, x.icon) })
  sheet_grab(c)
  sheet_head(c, tr("android-misc.workspace.sheet.title"))
  c.box(w=Fill(1.0), h=Fill(1.0), pb=24.0, clip=true, fn() {
    sheet_label(c, tr("android-misc.workspace.current"))
    c.box(w=Fill(1.0), pl=12.0, pr=12.0, pt=4.0, pb=16.0, fn() {
      let t = @sf.theme()
      c.box(w=Fill(1.0), radius=16.0, bg=t.p.bg, clip=true, fn() {
        if pick_row(c, "ws/" + w.id, w.name, w.email, true, if any_marked {
            Some(w)
          } else {
            None
          }, "", Json::null()) {
          lower_sheet()
        }
      })
      |> ignore
    })
    |> ignore
    let others = all.filter(fn(x) { x.id != w.id })
    if others.length() > 0 {
      sheet_label(c, tr("android-misc.workspace.others"))
    }
    for o in others {
      let mark = field(by_ws, o.id).unwrap_or(Json::null())
      if pick_row(c, "ws/" + o.id, o.name, o.email, false, if any_marked {
          Some(o)
        } else {
          None
        }, "", mark) {
        app.picked = o.id
        (src.call)(
          "prefs.set",
          Json::object({ "workspace": Json::string(o.id) }),
          fn(_) {  },
        )
        home()
      }
    }
  })
  |> ignore
  c.box(w=Fill(1.0), pt=8.0, pb=16.0, fn() {
    if pick_row(
        c,
        "ws-sign-in",
        tr("android-misc.workspace.addAccount"),
        tr("android-misc.workspace.addAccount.sub"),
        false,
        None,
        "log-in",
        Json::null(),
      ) {
      lower_sheet()
      (src.sign_in)()
    }
    pick_row(c, "ws-new", tr("android-misc.workspace.new"), "", false, None, "plus", Json::null())
    |> ignore
  })
  |> ignore
}

///|
fn sheet_label(c : @ui.Ctx, label : String) -> Unit {
  let t = @sf.theme()
  c.box(pl=20.0, pr=20.0, pt=6.0, pb=2.0, fn() {
    c.text(label, size=13.0, color=t.p.muted, wrap=false) |> ignore
  })
  |> ignore
}

///|
/// A row of a picking sheet (Controls.kt PickRow, Workspaces.kt WorkspaceRow): what, a line under it, a check on
/// the chosen one; before it a workspace's mark (or its letter) or an icon; after it what a workspace has waiting
/// (`mark`: its WorkspaceMark). True on the frame after it was tapped.
fn pick_row(
  c : @ui.Ctx,
  key : String,
  label : String,
  sub : String,
  checked : Bool,
  lead : Workspace?,
  icon : String,
  mark : Json,
) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.box(w=Fill(1.0), pl=12.0, pr=12.0, fn() {
    c.box(
      dir=Row,
      w=Fill(1.0),
      padx=8.0,
      pady=12.0,
      gap=12.0,
      align=ACenter,
      bg=@sf.alpha(t.p.text, 0.06 * @motion.pressing(c, id)),
      id~,
      fn() {
        match lead {
          Some(w) =>
            c.box(w=Px(24.0), h=Px(24.0), align=ACenter, justify=JCenter, fn() {
              if @sf.has_station_mark(w.emoji, w.icon) {
                @sf.station_mark(c, w.emoji, w.icon, 22.0, t.p.text)
              } else {
                c.text(initial(w.name), size=15.0, weight=600, color=t.p.muted, wrap=false)
                |> ignore
              }
            })
            |> ignore
          None => ()
        }
        if icon != "" {
          @sf.icon(c, icon, size=20.0, color=t.p.text) |> ignore
        }
        c.box(w=Fill(1.0), fn() {
          c.text(label, size=15.0, color=t.p.text, wrap=false, line=21.0) |> ignore
          if sub != "" {
            c.text(sub, size=12.0, color=t.p.muted, wrap=false, line=17.0) |> ignore
          }
        })
        |> ignore
        mark_counts(c, mark)
        if checked {
          @sf.icon(c, "check", size=14.0, color=t.p.accent) |> ignore
        }
      },
    )
    |> ignore
  })
  |> ignore
  c.clicked(id)
}

///|
/// What a workspace has waiting, after its name (SettingParts.kt MarkCounts): a red dot and how many of the chats
/// its person takes part in want them, a blue ring and how many wait on them, a blue dot and how many are unread.
fn mark_counts(c : @ui.Ctx, mark : Json) -> Unit {
  let m = Some(mark)
  if text(m, "tone") == "" {
    return
  }
  let t = @sf.theme()
  c.box(dir=Row, gap=8.0, align=ACenter, fn() {
    for k in [("alert", "alert"), ("wait", "wait"), ("done", "unread")] {
      let n = count(m, k.1)
      if n > 0 {
        c.box(dir=Row, gap=4.0, align=ACenter, fn() {
          workspace_mark(c, k.0)
          c.text("\{n}", size=12.0, color=t.p.muted, wrap=false) |> ignore
        })
        |> ignore
      }
    }
  })
  |> ignore
}
