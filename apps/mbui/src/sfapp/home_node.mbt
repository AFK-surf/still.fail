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
    // under the top bar, the status bar's height and its own (Home.kt padding: topBar + 8); over the bottom bar
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
    // what is left up a long while on the stations (OpenJobs.kt): nothing while there is none
    after: fn(_, _) {
      match workspace() {
        Some(w) if items((src.topic)("longJobs", { "scope": Json::string(w.id) }).value, "groups").length() > 0 =>
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
  // (a search the app starts with open: sfpages' search.mbt)
  @sfpages.search_start_now()
  // (while the app's first page waits for what it shows: drawn at none, the splash in its place, as the old views are)
  v.grow(Is(1.0)).min_height(Is(Some(0.0))).alpha(By(fn() { if @sfbase.first_page_waits.get() { 0.0 } else { 1.0 } }))
  |> ignore
  // under a finger's search the bar faded with the lists going away (Home.kt `away`), the search over them (its old
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
/// Home's top bar (top_bar's) in `v`, on its glass, under the status bar: the filter at the left (with stations to
/// narrow), what is catching up and going up beside it, the workspace's switcher and settings at the right. Tips in
/// `tips`.
fn home_top_bar_node(
  v : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  workspace : () -> Workspace?,
  view : () -> ChatsView?,
  invited? : () -> Bool = fn() { false },
) -> Unit {
  v.box(fn(g) {
    // (pointed at itself, the arrow over it where nothing of it says otherwise, as over main's bar: not left to what is
    // under its glass, an old view's words picked with the pointer and their I-beam)
    g.glass(By(fn() { Some(@sf.glass_bar()) })).cursor(Is(Some(Arrow))).points(Is(true)) |> ignore
    g.box(fn(row) {
      row
      .row(Is(true))
      .padding(By(fn() { (16.0, status_top_now(row.window().0), 16.0, 0.0) }))
      .min_height(By(fn() { Some(status_top_now(row.window().0) + bar_h) }))
      .gap(Is(10.0))
      .lines_up(Is(Some(Middle)))
      |> ignore
      // the filter, and the archive in its menu: nothing to narrow or look back on with no station
      row.show(fn() { view().map(fn(v) { v.stations > 0 }).unwrap_or(false) }, fn(f) {
        let key : Ref[@view.View?] = Ref(None)
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
            },
            icon_size=20.0,
          )
        })
        |> ignore
      })
      // catching up and transfers beside the filter, 10 apart (nothing of either laid out while it is not there)
      row.box(fn(k) {
        k.row(Is(true)).shrink(Is(0.0)).gap(Is(@ui.Space::px(S2_5))).lines_up(Is(Some(Middle))) |> ignore
        @sf.sync_key_node(
          k,
          tips,
          34.0,
          20.0,
          fn() { view() is Some({ syncing: Some(_), .. }) },
          fn() {
            match view() {
              Some({ syncing: Some(y), .. }) => y
              _ => ""
            }
          },
        )
        @sfdesk.transfers_key_node(k, src, fn() { workspace().map(fn(w) { w.id }) }, 34.0, 20.0)
      })
      |> ignore
      row.box(fn(end) {
        end.row(Is(true)).grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))).gap(Is(10.0)).lines_up(Is(Some(Middle))).lies_along(Is(End))
        |> ignore
        // the workspace's switcher: its mark, its name, what the others have waiting
        end.box(fn(s) {
          s.row(Is(true)).height(Is(Some(34.0))).gap(Is(6.0)).lines_up(Is(Some(Middle))).shrink(Is(1.0)).min_width(Is(Some(0.0)))
          |> ignore
          // (pressed: beside where it is on screen as it is pressed)
          @sf.presses_node(s, fn() {
            @sfpages.open_workspaces(src, match s.shown_rect() {
              Some((x, y, w, h)) => @sf.Anchor::At(x, y, w, h)
              None => Unanchored
            })
          })
          // (the fixture's home-sheet: opened as the app starts, as Home is made: a phone's sheet, from the screen's foot,
          // beside nothing)
          s.reacts(fn() { () }, fn(_) {
            if home_sheet_at_start.val {
              home_sheet_at_start.val = false
              @sfpages.open_workspaces(src, Unanchored)
            }
          })
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
          let marks = fn() {
            match workspace() {
              Some(w) => (src.topic)("workspaceMarks", { "workspace": Json::string(w.id) }).value
              None => None
            }
          }
          s.show(fn() { field(marks(), "others") is Some(String(_)) }, fn(m) {
            m.says(By(fn() { Some(@view.said(Image, label=text(marks(), "othersLabel"))) })) |> ignore
            @sfpages.chat_mark_node(m, fn() { text(marks(), "others") })
          })
          s.show(fn() { !(field(marks(), "others") is Some(String(_))) && invited() }, fn(m) {
            m.width(Is(Some(8.0)))
            .height(Is(Some(8.0)))
            .radius(Is(4.0))
            .ground(By(fn() { @ui.tree_theme().color(@sf.mark_blue) }))
            .says(By(fn() { Some(@view.said(Image, label=tr("android-chat.home.invited"))) }))
            |> ignore
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

