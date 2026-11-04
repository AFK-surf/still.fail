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
        parts.push({ key: "update-card", make: fn(p) { @ui.old(p, fn(c) { @sfpages.update_card(c, src) }, natural=true, unlaid=fn() { p.window().1 }) |> @ui.old_takes_own |> ignore } })
      }
      if @sfpages.news_of(src) is Some(_) {
        parts.push({ key: "changelog-news", make: fn(p) { @ui.old(p, fn(c) { @sfpages.changelog_news(c, src) }, natural=true, unlaid=fn() { p.window().1 }) |> @ui.old_takes_own |> ignore } })
      }
      parts
    },
    // what is left up a long while on the stations (OpenJobs.kt): nothing while there is none
    after: fn(_, _) {
      match workspace() {
        Some(w) if items((src.topic)("longJobs", { "scope": Json::string(w.id) }).value, "groups").length() > 0 =>
          [{ key: "open-jobs", make: fn(p) { @ui.old(p, fn(c) { open_jobs(c, src, w) }, natural=true, unlaid=fn() { p.window().1 }) |> ignore } }]
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
    home_top_bar_node(bar, src, workspace, view)
  })
  |> ignore
  v.show(@sfpages.search_on_lists, fn(s) {
    @sfpages.search_page_node(s, src, workspace, fn() { status_top_now(s.window().0) }, Whole)
  })
}

///|
/// Home's top bar (top_bar's) in `v`, on its glass, under the status bar: the filter at the left (with stations to
/// narrow), what is catching up and going up beside it, the workspace's switcher and settings at the right.
fn home_top_bar_node(
  v : @view.View,
  src : Source,
  workspace : () -> Workspace?,
  view : () -> ChatsView?,
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
      // catching up and transfers beside the filter (their old views, hosted)
      row.box(fn(k) {
        // (as wide as they are laid out, told by the old frame: what gives way is the workspace's name)
        let wide : @signals.Signal[Double?] = @signals.signal(None, same=fn(a, b) { a == b })
        k.shrink(Is(0.0)).width(By(fn() { wide.get() })) |> ignore
        @ui.old(k, fn(c) {
          c.box(style=home_keys_row, fn() {
            let (syncing, said) = match view() {
              Some({ syncing: Some(y), .. }) => (true, y)
              _ => (false, "")
            }
            @sf.sync_key(c, "home-syncing", 34.0, 20.0, syncing, said)
            match workspace() {
              Some(w) => @sfdesk.transfers_key(c, src, w.id, 34.0, 20.0)
              None => ()
            }
          })
          |> ignore
        }, natural=true, fits=(home_keys_most, wide))
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
          // (the fixture's home-sheet: opened by it as the app starts, once it is laid out where it opens from)
          s.reacts(fn() { s.laid_size_told() is Some(_) }, fn(laid) {
            if laid && home_sheet_at_start.val {
              home_sheet_at_start.val = false
              open()
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
/// What is catching up and going up beside the filter, 10 apart.
// kept across runs: a value (no field of it changes)
let home_keys_row : @ui.Style = @ui.css("row gap=S2_5 align=ACenter")

///|
/// How wide what is catching up and going up beside the filter may be at most (two keys and the room between).
let home_keys_most : Double = 120.0

