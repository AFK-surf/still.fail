// Home made once (home.mbt's home_page as nodes of the window's tree): the workspace's chats' lists (sfpages'
// chats_lists_node) under the top bar (the filter · the workspace's switcher and settings), what the last update
// brought and what the update wants over the rows, what is left up long after their words.

///|
/// Home in node `v` for `src` (as the narrow frame makes it once: narrow_made_as's Home): the lists under the top bar's
/// room, over the bottom bar's; the top bar over them. Tips in `tips`, pictures asked for on `stint`.
fn home_node(v : @view.View, src : Source, tips : @sf.TipLayer, stint : () -> Int) -> Unit {
  let workspace = fn() { workspace_in_view(src).0 }
  let view = fn() {
    match workspace() {
      Some(w) => chats_of(src, w.id, filter_of(src, w.id)).0
      None => None
    }
  }
  let frame : @sfpages.ListsNodeFrame = {
    // under the top bar, the status bar's height and its own; over the bottom bar
    top: fn() { status_top_now(v.window().0) + bar_h + 8.0 },
    under: fn() { status_top_now(v.window().0) + bar_h },
    foot: fn() { nav_foot() + bar_room_now() },
    ground: fn() { @sf.theme().p.bg },
    // what the update wants of the person, over what the last one brought (until it is seen)
    before: fn(_, _) {
      let parts : Array[@sfpages.NodePart] = []
      if @sfpages.update_card_shown() {
        parts.push({ key: "update-card", make: fn(p) { @sfpages.update_card_node(p, src) } })
      }
      if @sfpages.news_of(src) is Some(_) {
        parts.push({ key: "changelog-news", make: fn(p) { @sfpages.changelog_news_node(p, src, tips) } })
      }
      parts
    },
    // what is left up a long while on the stations: nothing while there is none
    after: fn(_, _) {
      match workspace() {
        Some(w) if items(src.topic("longJobs", @sfbase.long_jobs_asked(w.id)).get().value, "groups").length() > 0 =>
          [{ key: "open-jobs", make: fn(p) { open_jobs_node(p, src, w) } }]
        _ => []
      }
    },
    others: [],
    shown: fn() {
      match workspace() {
        Some(w) => @sfpages.filter_at(src, w)
        None => 0
      }
    },
    at: Whole,
    // (in view while it is the page on top: what changes under another page is as it is as it is come back to)
    watched: fn() { app.nav.top() is Home },
  }
  // (what is left up long asked with the lists from the start, not once they have come: Home opens on both,
  // home_opens)
  @sfbase.long_jobs_read(v, src, workspace)
  // (a search the app starts with open: sfpages' search.mbt)
  @sfpages.search_start_now()
  // (while the app's first page waits for what it shows: drawn at none, the splash in its place, as the old views are)
  v.grow(Is(1.0)).min_height(Is(Some(0.0))).alpha(By(fn() { if @sfbase.first_page_waits.get() { 0.0 } else { 1.0 } }))
  |> ignore
  // under a finger's search the bar faded with the lists going away, the search over them (its old
  // view, hosted)
  let away = @sfpages.search_away_node(v)
  v.box(fn(lists) {
    lists.over(Is(true)) |> ignore
    @sfpages.chats_lists_node(lists, src, workspace, frame, tips, stint)
  })
  |> ignore
  v.box(fn(bar) {
    bar.over(Is(true)).lies_along(Is(Start)).alpha(By(fn() { 1.0 - away() })) |> ignore
    home_top_bar_node(bar, src, tips, workspace, view)
  })
  |> ignore
  v.show(@sfpages.search_on_lists, fn(s) {
    @sfpages.search_page_node(s, src, workspace, fn() { status_top_now(s.window().0) }, Whole)
  })
}

///|
/// What Home of workspace `ws` (home_node) opens on, asked of `ask` (sfbase's opens_answered): its chats' list as it is
/// filtered (sfbase's list_opens), what the last update brought over it, and what is left up long after its rows.
/// Whether all of it is answered: Home opening waits for it (app.mbt's page_ready), a workspace switched on 小屏 too
/// (narrow_shell: sfbase's workspace_switch_node). Not the core's marks its bar's 待处理 dot shows: the app's first
/// page would wait for every workspace's marks, made after the list (40 ms after it in Hermes on a Mac Studio at a
/// workspace of real size, 2026-11-11), for a dot.
fn home_opens(src : Source, ws : String, ask : (String, Map[String, Json]) -> @sfbase.TopicState) -> Bool {
  let list = @sfbase.list_opens(src, ws, ask)
  let news = @sfbase.opens_answered(ask("changelog", @sfpages.news_params()))
  let long = @sfbase.opens_answered(ask("longJobs", @sfbase.long_jobs_asked(ws)))
  // (and what the narrow shell round it reads as it is first built, asked with it and not waited for: Home shows,
  // and the splash goes, as it did before they were asked here: sfbase's shell_opens)
  @sfbase.shell_opens(src, ws, ask) |> ignore
  list && news && long
}

///|
/// Home's top bar in `v`, on its glass, under the status bar: the filter at the left (with stations to
/// narrow), what is catching up and going up beside it, the workspace's switcher and settings at the right; 待处理
/// first unless not `bell` (over the page of a device waiting in the lock: nothing of the workspace's to attend to).
/// Its tips in `tips`.
fn home_top_bar_node(
  v : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  workspace : () -> Workspace?,
  view : () -> ChatsView?,
  bell? : Bool = true,
) -> Unit {
  v.box(fn(g) {
    g.glass(By(fn() { Some(@sf.glass_bar()) })) |> ignore
    g.box(fn(row) {
      row
      .row(Is(true))
      .padding(By(fn() { (16.0, status_top_now(row.window().0), 16.0, 0.0) }))
      .min_height(By(fn() { Some(status_top_now(row.window().0) + bar_h) }))
      .gap(Is(10.0))
      .lines_up(Is(Some(Middle)))
      |> ignore
      // 待处理, first on the bar: as a system's bar has it (no rail here to hold its bell)
      if bell {
        row.box(fn(k) {
          @sf.round_key_node(k, "bell", fn() { tr("web-main.attention.entry") }, fn() {
            guard @signals.untracked(workspace) is Some(w) else { return }
            let (x, y, wd, h) = k.placed_window_now()
            @sfdesk.open_attention_panel(src, w, At(x, y, wd, h))
          })
          k.show(fn() { workspace().map(fn(w) { @sfdesk.attention_any(src, w) }).unwrap_or(false) }, fn(m) {
            m.over(Is(true)).row(Is(true)).lies_along(Is(End)).lines_up(Is(Some(Start))) |> ignore
            m.box(fn(at) {
              at.offset(Is((-home_bell_dot_at, home_bell_dot_at))) |> ignore
              @sfpages.chat_mark_node(at, fn() { "done" })
            })
            |> ignore
          })
        })
        |> ignore
      }
      // the filter, and the archive in its menu: nothing to narrow or look back on with no station
      row.show(fn() { view().map(fn(v) { v.stations > 0 }).unwrap_or(false) }, fn(f) {
        let key : Ref[@view.View?] = Ref(None)
        let opener = @sf.Opener::new()
        f.box(fn(k) {
          key.val = Some(k)
          @sf.round_key_node(
            k,
            "filter",
            fn() {
              let filter = match workspace() {
                Some(w) => filter_of(src, w.id)
                None => "all"
              }
              fill("android-chat.home.filter.label", [
                (
                  "filter",
                  tr(
                    match filter {
                      "mine" => "android-chat.home.filter.mine"
                      "watching" => "android-chat.home.filter.watching"
                      "hidden" => "web-main.filter.hidden"
                      _ => "android-chat.home.filter.all"
                    },
                  ),
                ),
              ])
            },
            fn() {
              guard @signals.untracked(workspace) is Some(w) else { return }
              let (x, y, wd, h) = key.val.map(fn(k) { k.placed_window_now() }).unwrap_or((0.0, 0.0, 0.0, 0.0))
              @sfpages.filter_menu(At(x, y, wd, h), filter_of(src, w.id), fn(f) { home_filter_go(src, w, f) })
              opener.mark()
            },
            icon_size=20.0,
            opener~,
          )
        })
        |> ignore
      })
      // catching up beside the filter (laid nowhere while it is not there)
      @sf.sync_key_node(row, tips, 34.0, 20.0, fn() {
        match view() {
          Some({ syncing: Some(y), .. }) => Some(y)
          _ => None
        }
      })
      // transfers beside it (its old view, hosted)
      row.box(fn(k) {
        // (as wide as it is laid out, told by the old frame: what gives way is the workspace's name)
        let wide : @signals.Signal[Double?] = @signals.signal(None, same=fn(a, b) { a == b })
        k.shrink(Is(0.0)).width(By(fn() { wide.get() })) |> ignore
        @ui.old(k, fn(c) {
          match workspace() {
            Some(w) => @sfdesk.transfers_key(c, src, w.id, 34.0, 20.0)
            None => ()
          }
        }, natural=true, fits=(home_transfers_most, wide))
        |> @ui.old_takes_own
        |> ignore
      })
      |> ignore
      row.box(fn(end) {
        end.row(Is(true)).grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))).gap(Is(10.0)).lines_up(Is(Some(Middle))).lies_along(Is(End))
        |> ignore
        // the workspace's switcher: its mark, its name, what the others have waiting
        end.box(fn(s) {
          s.row(Is(true)).height(Is(Some(34.0))).gap(Is(6.0)).lines_up(Is(Some(Middle))).shrink(Is(1.0)).min_width(Is(Some(0.0)))
          |> ignore
          let open = fn() {
            @sfpages.open_workspaces(src, {
              let (x, y, w, h) = s.placed_window_now()
              @sf.Anchor::At(x, y, w, h)
            })
          }
          @sf.presses_node(s, open)
          // (the fixture's home-sheet: opened by it as the app starts, beside it wherever it is laid out)
          if home_sheet_at_start.val {
            home_sheet_at_start.val = false
            @sfpages.open_workspaces(src, @sf.Anchor::Node(s))
          }
          s.says(By(fn() { Some(@view.said(Button, label=workspace().map(fn(w) { w.name }).unwrap_or(""))) })) |> ignore
          @sf.icon_node(s, "chevron-down", 16.0, By(fn() { @sf.theme().p.muted })) |> ignore
          s.show(fn() { workspace().map(fn(w) { @sf.has_station_mark(w.emoji, w.icon) }).unwrap_or(false) }, fn(m) {
            @sf.station_mark_node(
              m,
              fn() { workspace().map(fn(w) { w.emoji }).unwrap_or("") },
              fn() { workspace().map(fn(w) { w.icon }).unwrap_or("") },
              home_ws_mark,
              fn() { @sf.theme().p.muted },
              fn() { 0 },
            )
          })
          s.box(fn(t) {
            t.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
            let name = fn() { workspace().map(fn(w) { w.name }).unwrap_or("") }
            @sf.top_bar_title_node(t, name, look=@sf.home_workspace_title_look) |> ignore
          })
          |> ignore
          // (what the others have waiting, as the workspace shown's mark says it)
          let marks = fn() {
            match workspace() {
              Some(w) => field(field(src.topic("workspaceMarks", @sfbase.marks_asked()).get().value, "workspaces"), w.id)
              None => None
            }
          }
          s.show(fn() { field(marks(), "others") is Some(String(_)) }, fn(m) {
            m.says(By(fn() { Some(@view.said(Image, label=text(marks(), "othersLabel"))) })) |> ignore
            @sfpages.chat_mark_node(m, fn() { text(marks(), "others") })
          })
        })
        |> ignore
        @sf.round_key_node(end, "settings", fn() { tr("android-chat.home.settings") }, fn() {
          @sfbase.history_push()
          app.nav.push(Settings)
        })
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// How far in from its corner the bell's dot is.
let home_bell_dot_at : Double = 5.0

///|
/// How wide the transfers' key beside the filter may be at most (the key, as its old view lays it out).
let home_transfers_most : Double = 34.0
