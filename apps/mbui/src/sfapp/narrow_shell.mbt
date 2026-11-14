// Signed in with a workspace in view, laid out Small: the shell as nodes of the window's tree (mbui's view package,
// the way there's 4), made once and changed as the app's state does, the pages and what floats over
// them old views (islands) in it:
//
//   - under all of it, what the frame does in every tier before its pages (signed_in_frame: what is told as the frame
//     ends, the icon's number, whether the first page waits: narrow_under; the keys are the shell node's actions:
//     sfdesk's keys.mbt), and the back of the stack's root a node said as what it reads changes (narrow_takes_back);
//   - the pages: the stack (app.nav) a node, each page on it a node of its own made as it is put on and let go as it
//     leaves (what it made forgotten), the page in it built while it shows (an island), where it is drawn bound to its
//     slide, which sets out at its cause's moment, once the core has given what the page shows (mbui's nav_view.mbt);
//   - over them, the bottom bar, what is open over the pages and the presenters (narrow_over, signed_in_over).
//
// Still the old frame's (the way there): which island takes a press where they lie one over another (all of them are
// told of it), the back the islands take (a page's own, a menu's, a sheet's: said by them as they are built, in the
// tree's order; the stack's root's is the node above), the theme (each island built in it).

///|
/// What the signed-in app is laid out as (app_tree): the stack of pages laid out Small, the narrow shell made of the
/// window's tree's nodes; the tape (laid out Medium with a sidebar to show, or beside the system's bars: sfdesk's
/// tape_holds), its panels the window's tree's nodes (tape_shell.mbt); the wide frame off the tape (laid out Large, or
/// with no sidebar to show), its page and its block the tree's nodes (tape_shell.mbt's paned_shell); the landing's nodes
/// (no workspace yet, every account answered: entry_tree.mbt); the splash's nodes while the workspaces are read or fail
/// to be (app.mbt's reading_tree); a window of its own, its page in the tree's frame (app.mbt's lone_tree); or nothing
/// while the window's width is not known yet (the tree made before its first frame).
#derive(Eq)
priv enum ShellIs {
  Stacked
  Taped
  Paned
  Landing
  Reading
  Lone
  Unsized
}

///|
/// Which shell the signed-in app is in for a window `width` wide (app_tree).
fn shell_is(src : Source, width : Double) -> ShellIs {
  if width <= 0.0 {
    return Unsized
  }
  // (a window of its own: its page alone, the window's tree's frame round it: lone_tree)
  if @sfbase.lone_page.val is Some(_) {
    return Lone
  }
  // (no workspace yet, every account answered with none: the landing's nodes, entry_tree.mbt)
  if landing_now(src) {
    return Landing
  }
  let wide = !(@sf.layout(width) is Small) || @sf.native_able()
  match workspace_in_view(src).0 {
    Some(_) if !wide => Stacked
    Some(w) if @sfdesk.tape_holds(src, w, width) => Taped
    Some(_) => Paned
    // (none in view yet, the landing not shown: the workspaces still read, or failing to be: the splash's nodes)
    None => Reading
  }
}

///|
/// The narrow shell (above), in node `v`.
fn narrow_shell(v : @view.View, src : Source) -> Unit {
  // (on the window's ground, as the old view whole is (app_state_tree's): what no page covers, a page sliding, shows it)
  v.ground(By(fn() { @sf.theme().p.bg })) |> ignore
  @ui.old(v, fn(c) { narrow_under(c, src) }).over(Is(true)) |> ignore
  // back at the stack's root while the shell takes it (narrow_takes_back), a node of the window's tree's: before the
  // pages, what they and what is over them say takes back (a page's own stack, a menu, a sheet) taking it first; whose
  // it is said at the cause that changes it (a tab of the bar pressed), done as it is done (sfbase's back_step then)
  v.show(narrow_takes_back, fn(b) {
    b.takes_back(fn() {
      match @sfbase.back_step() {
        Some(f) => f()
        None => ()
      }
    })
    |> ignore
  })
  @ui.nav_view(
    v,
    app.nav,
    fn(c, page) {
      match workspace_in_view(src).0 {
        Some(w) => narrow_page_held(c, src, w, page)
        None => ()
      }
    },
    page_for=fn(entry, serial) {
      let retained = @sfbase.page_entry_source(src, entry, serial)
      let page_read = @sfbase.page_chat_reader(retained, entry, serial)
      fn(visible) {
        let shown = src.owned_by(visible)
        fn(c, page) {
          @sfbase.page_entry_read(serial, retained, page)
          page_read(page)
          let page_src = if page is Chat(_) { retained } else { shown }
          match workspace_in_view(page_src).0 {
            Some(w) => narrow_page_held(c, page_src, w, page)
            None => ()
          }
        }
      }
    },
    bg=fn() { @sf.theme().p.bg },
    // a page opened slides in once the core has given what it shows
    ready=fn(page) {
      match workspace_in_view(src).0 {
        Some(w) => page_ready(src, w, page)
        None => true
      }
    },
    most=page_local_ms,
    // (each page's island built again as what it is laid out by besides what it reads changes: narrow_page_key)
    page_key=fn(_page) { narrow_island_key(src) },
    // (the pages made once as nodes: narrow_made)
    made=fn(page) { narrow_made(src, page) },
    // (a place of the bottom bar switched away from kept, its nodes put by at rest, taken back as it is switched to:
    // go_place's, sfbase's nav_root_kept)
    keeps_made=true,
  )
  |> ignore
  // (none kept of another workspace: those put by left for good as the workspace in view changes)
  v.reacts(fn() { workspace_in_view(src).0.map(fn(w) { w.id }) }, fn(_) { app.nav.shelf_empty() })
  // a station's screen with a page put over it (a chat a notice opened): its page is not built there, so its view is
  // let go of as it is covered, and opened again by its page as it is on top again
  v.reacts(
    fn() {
      let pages = app.nav.pages()
      let screens : Array[(String, String, Bool)] = []
      for i, p in pages {
        match p {
          Screen(at) => screens.push((at.station, at.screen, i < pages.length() - 1))
          _ => ()
        }
      }
      screens
    },
    fn(screens) {
      for k in screens {
        @sfpages.screen_covered(src, k.0, k.1, k.2)
      }
    },
  )
  // what the places of the bar open on asked ahead of them from the moment it shows, held till its page is gone from
  // view under another (the stack at rest: Nav::root_shows), at those moments whatever frames are drawn (sfbase's
  // places_ahead_node)
  @sfbase.places_ahead_node(v, src, fn() {
    match workspace_in_view(src).0 {
      // (its page shows, on top or beside a page sliding over it or off it: held across that slide, let go of as it
      // is over with its page gone from view; another page sliding over one already over it is no cause of the bar's)
      Some(w) if narrow_bar_shown(src, w) || app.nav.root_shows() => Some(w.id)
      _ => None
    }
  })
  // a workspace switched shows once all its Home opens on is answered (home_opens), the screen as it was till then
  // (sfbase's workspace_switch_node)
  @sfbase.workspace_switch_node(v, src, home_opens)
  // the bottom bar told what the app's state and the window say of it as that changes, at the moment of what changed it
  // (a page put on the stack, a place come in, the bars' order, the window's width), whatever frames are drawn: the
  // frames only read where it is then (bar_tell)
  v.reacts(
    fn() {
      match workspace_in_view(src).0 {
        Some(w) => {
          let active = place_of(app.nav.top())
          // (the width of the box it is laid out in, this node's: the window's less the system's bars beside it, as
          // the root's sides say it, told as either changes)
          let (left, right) = sides_room()
          Some(bar_told(src, w, active, narrow_bar_shown(src, w), v.window().0 - left - right))
        }
        None => None
      }
    },
    fn(told) {
      match told {
        Some(t) => bar_tell(t, v.cause_at())
        None => ()
      }
    },
  )
  @ui.old(v, fn(c) {
    match workspace_in_view(src).0 {
      Some(w) => {
        // ⌘K's search over a page other than the lists (sfdesk's keys.mbt, sfpages' search.mbt), under the bars
        @sfpages.search_over(c, src, w, status_top())
        narrow_over(c, src, w)
        signed_in_over(c, src, w)
      }
      None => ()
    }
  })
  .over(Is(true))
  // (a press where it has nothing of its own its pages', a page made once as nodes among them: entry_tree's over's)
  |> @ui.old_takes_own
  |> ignore
  // the bottom bar's glass, where the bar is laid out: a finger on it the bar's at each event's moment (drawn by the old
  // view over the pages; what the old frame puts over all of it at its root, its notch's key, menus and sheets, first)
  bar_glass_node(v, src, fn() { workspace_in_view(src).0 })
  // an image opened over the pages, over the bar: nodes of the tree's of its own (sfbase's viewer_tree.mbt); what is
  // opened otherwise, the old view's over them (narrow_over's preview)
  // (its stage the box it is laid out in, this node's: the window's less the system's bars beside it, as the root's
  // sides say it, followed)
  @sfbase.viewer_node(v, src, fn() {
    let (w, h) = v.window()
    let (left, right) = sides_room()
    (dmax(0.0, w - left - right), h)
  })
}

///|
/// Under the narrow shell's pages (an island): what every frame of the app's state does (app_state_island's), what the
/// signed-in frame does before its pages (signed_in_frame), how the lists take a mouse.
fn narrow_under(c : @ui.Ctx, src : Source) -> Unit {
  if @ui.window_inset() {
    let id = c.id("window-ground-band")
    c.window_drag(id)
    c.box(style=@ui.style(h=Fixed(window_band())), left=0.0, top=0.0, right=0.0, id~, fn() {  }) |> ignore
  }
  frame_bare.val = false
  match workspace_in_view(src).0 {
    Some(w) => signed_in_frame(c, src, w)
    None => ()
  }
  narrow_lists(c)
}

///|
/// What a page's island in the narrow shell is built again by besides what it reads (narrow_page_key), with workspace
/// in view.
fn narrow_island_key(src : Source) -> String {
  match workspace_in_view(src).0 {
    Some(w) => narrow_page_key(@ui.current(), w)
    None => ""
  }
}

///|
/// Page `page` of the narrow shell's stack as its island builds it: picked words with a mouse (a finger holds to pick:
/// pick.mbt), the pictures it waits for said afresh (image_item, video_item).
fn narrow_page_held(c : @ui.Ctx, src : Source, w : Workspace, page : Page, barred? : Bool = false) -> Unit {
  @sfbase.held_pictures_waiting.val = []
  // (the page is its island, kept as its nodes by what it reads and its key (narrow_page_key): no part of its own)
  let built = fn() {
    let whole = c.box(style=page_whole, fn() {
      let (now, _, _, _) = workspace_in_view(src)
      page_view(c, src, now.unwrap_or(w), page, barred~)
    })
    @motion.scope(c, whole, bottom=true)
  }
  c.selectable(color=@sf.alpha(@sf.theme().p.blue, 0.28), built)
  // what is the page's own and takes back before it (said with it, in its island: what it reads is what the page
  // writes): the player sideways turned upright first; words picked in a chat, a link's menu, let go first (pick.mbt)
  play_back(c)
  pick_back(c)
}

///|
/// What the frame does with the app signed in and workspace `w` in view, in every tier, before its frame: what is
/// told as the frame ends, the icon's number, links, updates, what was shared in, whether the first page waits.
fn signed_in_frame(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  // The folder and its player both need the same entries. Keep them while moving between the two and when
  // replacing one film with the next, until the new page has its own reader.
  match app.nav.top() {
    Drive(at) => match at.root {
      Some(root) => src.topic("drive", @sfbase.drive_params(at.station, root, at.path)).get() |> ignore
      None => ()
    }
    DrivePlay(at) => {
      let root = at.root.unwrap_or("")
      let folder = @sfbase.dv_parent(at.path)
      src.topic("drive", @sfbase.drive_params(at.station, root, folder)).get() |> ignore
    }
    _ => ()
  }
  // (told once the frame's builds are over, as the last saw the app, the workspace and the page on top)
  c.after_build("attend", fn() { attend(src, w.id, app.nav.top() is NewChat) })
  // (a person's act taken as an old view builds (a row pressed: its change is that build's), done with it: where it
  // left from let go where it went nowhere; where the app is noted as it changes, app_state_tree)
  c.after_build("history", fn() { @sfbase.history_settled() })
  // notifications: shown while the app is, a tapped one's chat opened, the one of a chat on top taken off (once the
  // frame's builds are over: a build let go of follows no workspace)
  c.after_build("notices", fn() { notices_frame(src, w) })
  // the core and the workspace links are opened against, as the frame ends (links.mbt)
  c.after_build("links", fn() { links_frame(src, w) })
  // the number on the app's icon (app_frame.mbt)
  badge_frame(c, src)
  // a link the system opened the app with, told once: what the core says of it shown by the frame after (Ctx::tell)
  // (whether one waits read as a signal: this part, kept as its nodes, built again as one is given)
  if links_wait() {
    c.tell("links-given", fn() { links_given(src) })
  }
  // a newer build of the app asked for once (updates.mbt)
  // (asked once, with the app's version: nothing a build changes)
  update_first(src)
  // and again while it stays open (one never shown again asks no more otherwise)
  update_again(c, src)
  // and as soon as a release may be out
  update_on_release(c, src)
  // what another app shared in (share.mbt)
  share_in_frame(c)
  // files being kept on the device, said once kept (keep.mbt)
  keeps_frame(c)
  // the first page built as it opens, asking for all it shows, and shown once it has it (first_page_ms at most), as a
  // page opening is: under the splash till then (view_in), not its loading look and its list a frame or two later
  first_waiting.val = !first_page_shown(c, src, w)
  first_hide(first_waiting.val)
}

///|
/// Laid out Small, how the lists take the hand: pointed at with a mouse (a desktop's narrow window), the wheel and the
/// trackpad scroll the lists and a drag picks words, as on the wide frame's page; a finger drags the lists and holds to
/// pick (pick.mbt).
fn narrow_lists(c : @ui.Ctx) -> Unit {
  c.mouse_drags_lists(stack_by_finger())
}

///|
/// Whether back at the narrow stack's root is the shell's now (back_where's: a place's top page other than the chats
/// back to the chats): nothing pushed on the stack, no menu, sheet or presenter over it. All it reads is told as it
/// changes (the stack, the presenters).
fn narrow_takes_back() -> Bool {
  app.nav.depth() == 1 && app.nav.top() != Home && !app.menu && !sheet_open() && !@sf.presenting()
}

///|
/// What a page laid out Small is laid out by besides what it reads: the window, the bars' room, the keyboard's, the
/// ground, where it stands in the stack and the way a place came in, the workspace (its key as a part kept as its
/// nodes: a page's island's, narrow_shell; its kept part's, narrow_page).
fn narrow_page_key(c : @ui.Ctx, w : Workspace) -> String {
  let t = @sf.theme()
  "\{c.width} \{c.height} \{status_top()} \{nav_foot()} \{bar_room_now()} " +
  "\{t.p.bg} \{t.dark} \{app.nav.under() is None} \{app.switch_way} \{w.id}"
}

///|
/// Over the pages laid out Small: the bottom bar, the chat being made public, a visualization over the whole screen (a
/// file open over them is the window's tree's: sfbase viewer_tree.mbt).
fn narrow_over(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  // the bottom bar: on a place's top page with nothing over it; none while this device waits to be confirmed in the
  // workspace's safe mode (its Home is the wait: lock_gate)
  bottom_bar(c, src, w, place_of(app.nav.top()), narrow_bar_shown(src, w))
  // the chat being made public (sfpages' publish.mbt)
  @sfpages.publish_layer(c, src)
  // a visualization over the whole screen (viz.mbt)
  viz_full_layer(c, src)
}

///|
/// Whether the bottom bar shows: on a place's top page with nothing over it; not while this device waits to be
/// confirmed in the workspace's safe mode (its Home is the wait: lock_gate).
fn narrow_bar_shown(src : Source, w : Workspace) -> Bool {
  let root = app.nav.top()
  let waiting = root == Home && @settings.lock_waiting(settings_core(src, w), w.id)
  app.nav.depth() == 1 && place_of(root) is Some(_) && !@sfpages.search_bar_away() && !waiting
}

///|
/// Over the frame with workspace `w` in view, in every tier: the sheets, a new device waiting on this one's code, what
/// the settings put up, ⌘K and ⌘/, the presenters, the toasts, the loupe.
fn signed_in_over(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  sheet_contents(fn(kind) {
    match kind {
      ShareSheet => share_in_sheet(c, src, w)
      InviteLink => invite_sheet(c, src)
      NoSheet => ()
    }
  })
  // a new device waiting on this one's code, in any workspace of the person's, over whichever page is open
  // : put up when no other sheet is
  @settings.lock_prompts(settings_core(src, w), !sheet_open())
  // a device of the person's waiting on this one for a vault's key (settings/vault_prompts.mbt), the same way
  @settings.vault_prompts(settings_core(src, w), !sheet_open())
  // (the core what the settings put up over a page draws with, put up by what has none at hand)
  @settings.panels_frame(settings_core(src, w), w.id)
  // what another app shares, in the wide window's panel (share.mbt; a sheet on Small, as ShareSheet)
  share_panel(c, src, w)
  // ⌘K's panel and ⌘/'s shortcuts, in every tier over the pages, under the presenters (sfdesk's switcher.mbt,
  // shortcuts.mbt)
  @sfdesk.switcher(c, src, w)
  @sfdesk.keys_dialog(c, src)
  // the library's menus, picks, panels, confirms and questions (src/sf presenters.mbt), over all of those
  @sf.presented(c)
  finger_loupe(c)
}

///|
/// The pages of the stack made once as nodes of the tree's in the narrow shell (nav_view's `made`), by their kind, the
/// rest old views (narrow_page_held): the settings' list (the gear's), 关于, 记忆, 一台 station 的记忆 and 归档, an agent's history;
/// a chat (and the new chat that becomes it), its old view in it as yet (chat_page_made). Each in the workspace in view, made
/// again as that changes; its frame what the shell gives a page (back to the one under it, under the status bar, over
/// the navigation bar: setting_page's) as that changes; under the status bar the page's ground over it, and a window's
/// band its buttons are in dragging it, as page_view puts them over a page that has no top of its own.
fn narrow_made(src : Source, page : Page) -> (String, (@view.View, () -> Page, Page?, () -> Int, Int) -> Unit)? {
  match page {
    // (a place of the bottom bar's whose page is one of those: that page under the place's top bar, place_page's, made
    // under its own kind)
    Place(name) =>
      match @settings.route_of(name) {
        // (those whose old view is gone: every frame makes them once, as a page or a place)
        Some(r) if @settings.made_once(r) =>
          narrow_made_as(src, Setting(r), true).map(fn(m) { ("place/" + m.0, m.1) })
        _ => None
      }
    _ => narrow_made_as(src, page, false)
  }
}

///|
/// narrow_made's page `page`, made as a place of the bottom bar's (`place`: named as the stack's entry is now, whichever
/// of its names it is) or as a page of the stack.
fn narrow_made_as(
  src : Source,
  page : Page,
  place : Bool,
) -> (String, (@view.View, () -> Page, Page?, () -> Int, Int) -> Unit)? {
  let made_at = fn(
    kind : String,
    place : Bool,
    f : (
      @view.View,
      @settings.Core,
      () -> @settings.Here,
      () -> PageFrame,
      () -> Int,
      ((@view.View) -> Unit, (@sf.Look) -> Double) -> Unit,
      Int,
    ) -> Unit,
  ) {
    Some(
      (
        kind,
        fn(outer : @view.View, page : () -> Page, under : Page?, stint : () -> Int, serial : Int) {
          // (a place switched to on the bar: all of it but its ground coming in from the ball's side, page_view's)
          let v = match place {
            true if under is None => {
              let mut inner : @view.View? = None
              outer.box(fn(i) {
                i.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
                place_comes_in(i)
                bar_built_node(i, page)
                inner = Some(i)
              })
              |> ignore
              inner.unwrap()
            }
            _ => outer
          }
          // (what the page does, given its place's top bar as it is made: each making of it its own, let go with it
          // where none since gave another)
          let page_actions : @signals.Signal[((@view.View) -> Unit, Int)?] = @signals.signal(None, same=fn(a, b) {
            match (a, b) {
              (None, None) => true
              (Some(x), Some(y)) => x.1 == y.1
              _ => false
            }
          })
          let frame = fn() -> PageFrame {
            // (under the status bar as the window it is in is now: status_top_now, by its width as it changes; a place
            // of the bottom bar's under the top bar, which names it, over the bottom bar: place_page's)
            if place {
              { back: None, top: status_top_now(v.window().0) + bar_h + 8.0, foot: nav_foot() + bar_room_now(), named: true }
            } else {
              { back: under.map(@sfbase.back_label), top: status_top_now(v.window().0), foot: nav_foot(), named: false }
            }
          }
          v.pick(fn() { workspace_in_view(src).0.map(fn(w) { w.id }) }, fn(p, _id) {
            let gen = next_place_actions_gen()
            let acts = fn(make : (@view.View) -> Unit, _side : (@sf.Look) -> Double) {
              page_actions.set(Some((make, gen)))
            }
            p.owns(fn() {
              if page_actions.untracked() is Some((_, g)) && g == gen {
                page_actions.set(None)
              }
            })
            |> ignore
            match @signals.untracked(fn() { workspace_in_view(src).0 }) {
              Some(w) => {
                let core = settings_core(src, w)
                let here = fn() { @settings.here_of(core, w.id, w.name) }
                @settings.frame(core, @signals.untracked(here))
                // (a dialog a fixture's mode puts up over its page, before the page is made: setting_page's)
                @sfdesk.settings_fixture(src, core)
                // (its words in pieces picked with the mouse, as an old view's page's in this frame are (narrow_page's
                // c.selectable), before what it holds is made)
                @ui.words_picked(p)
                f(p, core, here, frame, stint, acts, serial)
              }
              None => ()
            }
          })
          // Home and a place draw their own top bar under the status bar.
          narrow_made_top(v, has_top=place || kind == "home")
          // (a place of the bottom bar's: its top bar over it, the place's name as the entry is now (another of the same
          // page's names it may become), what its page does at its end, settings at its end: place_page's)
          if place {
            v.box(fn(o) {
              o.over(Is(true)) |> ignore
              place_top_bar_node(
                o,
                fn() {
                  match page() {
                    Place(n) => n
                    _ => ""
                  }
                },
                fn() { page_actions.get() },
              )
              |> ignore
            })
            |> ignore
          }
        },
      ),
    )
  }
  let made = fn(
    kind : String,
    f : (
      @view.View,
      @settings.Core,
      () -> @settings.Here,
      () -> PageFrame,
      () -> Int,
      ((@view.View) -> Unit, (@sf.Look) -> Double) -> Unit,
    ) -> Unit,
  ) {
    made_at(kind, place, fn(p, core, here, frame, stint, acts, _serial) { f(p, core, here, frame, stint, acts) })
  }
  match page {
    // (a chat, and the new chat that becomes one in place: the same page, a node of the tree's, its old view in it as
    // yet, built as the stack's island built it: narrow_page_held)
    page if @sfbase.chat_page_is(page) && !place =>
      Some(
        (
          "chat",
          fn(v, _page, _under, stint, k) {
            @sfbase.chat_page_made(
              v,
              src,
              k,
              fn(c, s, p) {
                match workspace_in_view(s).0 {
                  Some(w) => narrow_page_held(c, s, w, p, barred=true)
                  None => ()
                }
              },
              key=fn() { narrow_island_key(src) },
              // (its bar the page's node's, over its old view: chat_bar_node)
              over=chat_bar_node,
              stint~,
              // (with chat_page_nodes on: its messages nodes, its composer in their list's foot its old view)
              body=fn(col, s, r, composer, shows) {
                @sfpages.chat_page_body_node(
                  col,
                  s,
                  r,
                  // (its tips and hover cards over the page, in its node: an agent's card over its picture)
                  tips=@sf.TipLayer::new(fn() { Some(v) }),
                  stint~,
                  shows~,
                  top=fn() { list_top_live(col, r) },
                  foot=list_foot,
                  composer~,
                  lead=unread_lead(),
                )
              },
              foot=chat_foot_nodes,
            )
            |> ignore
          },
        ),
      )
    // the chats' lists under Home's top bar (home_node); a device waiting to be confirmed in the workspace's safe mode
    // sees that instead (lock_gate_node)
    Home =>
      made("home", fn(p, core, _here, _frame, stint, _acts) {
        let tips = @sf.TipLayer::new(fn() { None })
        p.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
        // (the bar's first place: coming in as a place switched to does, all of it but its ground, told built then:
        // page_view's, a place's made once, made_at's)
        let p = p.box(fn(i) {
          i.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
          place_comes_in(i)
          bar_built_node(i, fn() { Home })
        })
        p.pick(fn() { workspace_in_view(src).0.map(fn(w) { @settings.lock_waiting(core, w.id) }).unwrap_or(false) }, fn(
          q,
          waiting,
        ) {
          // (all of the page's room, the lock's page and Home alike)
          q.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
          if waiting {
            lock_gate_node(q, src, core)
          } else {
            home_node(q, src, tips, stint)
          }
        })
      })
    Settings =>
      made("settings", fn(p, core, here, frame, stint, _acts) {
        @sfpages.settings_home_node(p, core, here, fn(r) { (core.push)(r) }, on_back=core.pop, frame~, stint~, bars=fn() {
          @sf.layout(p.window().0) is Small
        })
      })
    Setting(About) => made("about", fn(p, core, _here, frame, _stint, _acts) { @sfpages.about_node(p, core, on_back=core.pop, frame~) })
    Setting(Changelog) =>
      made("changelog", fn(p, core, _here, frame, _stint, _acts) { @sfpages.changelog_node(p, core, on_back=core.pop, frame~) })
    Setting(Archiving) =>
      made("archiving", fn(p, core, here, frame, stint, _acts) {
        @sfpages.archiving_node(p, core, here, on_back=core.pop, frame~, stint~)
      })
    Setting(StationArchiving(st)) =>
      made("station-archiving/" + st, fn(p, core, here, frame, _stint, _acts) {
        @sfpages.station_archiving_node(p, core, here, st, on_back=core.pop, frame~)
      })
    Setting(AutoDecisions) =>
      made("auto-decisions", fn(p, core, here, frame, _stint, _acts) {
        @sfpages.decisions_node(p, core, here, on_back=core.pop, frame~)
      })
    Setting(AutoCompletion) =>
      // (what it does in its place's top bar as a place; at its head as a page of the stack)
      made("auto-completion", fn(p, core, here, frame, _stint, acts) {
        @sfpages.completion_node(p, core, here, on_back=core.pop, frame~, bar_actions?=if place { Some(acts) } else { None })
      })
    Setting(Usage) =>
      // (what it does in its place's top bar as a place; at its head as a page of the stack)
      made("usage", fn(p, core, here, frame, _stint, acts) {
        @sfpages.usage_node(p, core, src, here, on_back=core.pop, frame~, bar_actions?=if place { Some(acts) } else { None })
      })
    Setting(Shortcuts) =>
      // (recording while it is the one on top of the stack: its stay there, stint's)
      made("shortcuts", fn(p, core, _here, frame, stint, _acts) {
        @sfpages.shortcuts_node(p, core, on_back=core.pop, frame~, active=fn() { app.nav.top_stay().1 == stint() })
      })
    Setting(Notifications) =>
      made("notifications", fn(p, core, here, frame, stint, _acts) {
        @sfpages.notify_node(p, core, here, on_back=core.pop, frame~, stint~)
      })
    Setting(MemoryDoc(address, skill, at)) =>
      made("memory-doc/" + address + "/" + skill + "/" + at.to_string(), fn(p, core, here, frame, _stint, _acts) {
        @sfpages.memory_doc_node(p, core, here, address, skill, at, on_back=core.pop, frame~)
      })
    Setting(AutoPolicy(st)) =>
      made("auto-policy/" + st, fn(p, core, here, frame, _stint, _acts) { @sfpages.policy_node(p, core, here, st, on_back=core.pop, frame~) })
    Setting(Appearance) =>
      made("appearance", fn(p, core, _here, frame, _stint, _acts) { @sfpages.appearance_node(p, core, on_back=core.pop, frame~) })
    Setting(LocalStation) =>
      made("local-station", fn(p, core, _here, frame, _stint, _acts) { @sfpages.local_station_node(p, core, on_back=core.pop, frame~) })
    Setting(Permissions) =>
      made("permissions", fn(p, core, _here, frame, _stint, _acts) { @sfpages.permissions_node(p, core, on_back=core.pop, frame~) })
    Setting(Security) =>
      made("security", fn(p, core, here, frame, stint, _acts) { @sfpages.security_node(p, core, here, on_back=core.pop, frame~, stint~) })
    Setting(SecurityOpen) =>
      made("security-open", fn(p, core, here, frame, _stint, _acts) {
        @sfpages.security_open_node(p, core, here, on_back=core.pop, frame~)
      })
    Setting(Workspace) =>
      made("workspace", fn(p, core, here, frame, stint, _acts) { @sfpages.workspace_node(p, core, here, on_back=core.pop, frame~, stint~) })
    Setting(VaultItems) =>
      made("vault-items", fn(p, core, here, frame, _stint, _acts) { @sfpages.vault_items_node(p, core, here, on_back=core.pop, frame~) })
    // (by its station: another station's another page; as a place of the bottom bar's, its ＋ the bar's notch:
    // connects_add)
    Setting(Connects(only)) =>
      made("connects/" + only, fn(p, core, here, frame, stint, _acts) {
        @sfpages.connects_node(p, src, core, here, only, on_back=core.pop, frame~, stint~)
      })
    Setting(Connect(station, id)) =>
      made("connect/" + station + "/" + id, fn(p, core, here, frame, stint, _acts) {
        @sfpages.connect_node(p, src, core, here, station, id, on_back=core.pop, frame~, stint~)
      })
    // (by its station: another station's another page, not this one become it)
    Setting(Station(address)) =>
      made("station/" + address, fn(p, core, here, frame, stint, _acts) {
        @sfpages.station_node(p, core, src, here, address, on_back=core.pop, frame~, stint~)
      })
    Setting(UsagePrices(days)) =>
      made("usage-prices/" + days.to_string(), fn(p, core, here, frame, _stint, _acts) {
        @sfpages.usage_prices_node(p, core, here, days, on_back=core.pop, frame~)
      })
    Setting(Memories) =>
      made("memories", fn(p, core, here, frame, _stint, _acts) { @sfpages.memories_node(p, core, here, on_back=core.pop, frame~) })
    Setting(Memory(address)) =>
      made("memory/" + address, fn(p, core, here, frame, _stint, _acts) {
        @sfpages.memory_node(p, core, here, address, on_back=core.pop, frame~)
      })
    // an agent's history (history_node), made again for another agent's
    // (its old parts built as the stack builds its page's: Nav::page_island, by the page's serial)
    History(r, key, entry) =>
      made_at("history/" + r.station + "/" + key, place, fn(p, _core, _here, frame, _stint, _acts, serial) {
        history_node(p, src, r, key, entry, frame, serial)
      })
    Setting(Profile(address, id)) =>
      made("profile/" + address + "/" + id, fn(p, core, here, frame, stint, _acts) {
        @sfpages.profile_node(p, core, here, address, id, on_back=core.pop, frame~, stint~)
      })
    Setting(NewProfile(address)) =>
      made("new-profile/" + address, fn(p, core, here, frame, _stint, _acts) {
        @sfpages.new_profile_node(p, core, src, here, address, on_back=core.pop, frame~)
      })
    _ => None
  }
}

///|
/// A page made once at the stack's root, at a place of the bottom bar's, coming in as page_view has a place's: as far
/// as the switch to it has gone (place_switch, from the moment it was switched to, whenever it is made), from the side
/// the ball goes to by switch_slide, fading in; all of it but its ground.
fn place_comes_in(v : @view.View) -> Unit {
  let w = place_switch
  // (told at the way's end, as each way is said: read again then)
  let ended : @signals.Signal[Int] = @signals.signal(0)
  let due : Ref[() -> Unit] = Ref(fn() {  })
  v.reacts(fn() { w.said(); w.ends_at() }, fn(end) {
    (due.val)()
    due.val = if end >= 0.0 {
      v.at_moment(end, fn() { ended.set(ended.untracked() + 1) })
    } else {
      fn() {  }
    }
  })
  let shown = fn() {
    ended.get() |> ignore
    w.shown_on(v)
  }
  v.alpha(By(shown)).offset(By(fn() { (app.switch_way.to_double() * switch_slide * (1.0 - shown()), 0.0) })) |> ignore
}

///|
/// Over a page made once: its ground under the status bar if it has no top of its own, and the band a window's buttons
/// are in dragging it where it has them (page_view's, an old view's).
fn narrow_made_top(v : @view.View, has_top~ : Bool) -> Unit {
  if !has_top {
    v.box(fn(o) {
      o.over(Is(true)) |> ignore
      o.show(fn() { status_top_now(v.window().0) > 0.0 }, fn(paper) {
        paper.height(By(fn() { Some(status_top_now(v.window().0)) })).ground(By(fn() { @sf.theme().p.bg })) |> @sf.ground_node |> ignore
      })
    })
    |> ignore
  }
  v.box(fn(o) {
    o.over(Is(true)) |> ignore
    // (where the frame is not wide: is_wide, by the window as it is)
    o.show(fn() { @ui.window_inset_now() && @sf.layout(v.window().0) is Small && !@sf.native_able() }, fn(band) {
      band.height(By(fn() { Some(window_band_now()) })).moves_window(Is(true)) |> ignore
    })
  })
  |> ignore
}

///|
/// A place's top bar as nodes, over a page made once at a place of the bottom bar's (place_top_bar's): on the bar's
/// glass, under the status bar, 16 in, 10 apart, as high as a top bar at least; the place's name (the page's entry as it
/// is now, `place`), what its page does at its end where it gave the bar any (`actions`: made again as the page that
/// gave them is, laid out narrow at a head's end: head_end's), settings at the right edge (as at Home's).
fn place_top_bar_node(
  v : @view.View,
  place : () -> String,
  actions : () -> ((@view.View) -> Unit, Int)?,
) -> Unit {
  // (over the page, as place_page draws it: nothing of it cut but its name)
  place_top_bar_glass(v, place, actions)
}

///|
/// place_top_bar_node's bar on its glass, in `v`.
fn place_top_bar_glass(
  v : @view.View,
  place : () -> String,
  actions : () -> ((@view.View) -> Unit, Int)?,
) -> Unit {
  v.box(fn(g) {
    g.glass(By(fn() { Some(@sf.glass_bar()) })) |> ignore
    g.box(fn(row) {
      row
      .row(Is(true))
      .padding(By(fn() { (16.0, status_top(), 16.0, 0.0) }))
      .min_height(By(fn() { Some(top_bar_h()) }))
      .gap(Is(10.0))
      .lines_up(Is(Some(Middle)))
      |> ignore
      // (its words whole: what the page does at its end gives way where the bar has not the room)
      row.box(fn(t) {
        t.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))).height(Is(Some(34.0))).row(Is(true)).lines_up(Is(Some(Middle)))
        |> ignore
        @sf.top_bar_title_node(t, fn() { place_label(place()) }) |> ignore
      })
      |> ignore
      row.show(fn() { actions() is Some(_) }, fn(a) {
        a.pick(
          fn() {
            match actions() {
              Some((_, g)) => g
              None => 0
            }
          },
          fn(k, _) {
            @sf.top_bar_actions_lent(k)
            k.row(Is(true)).gap(Is(10.0)).lines_up(Is(Some(Middle))) |> ignore
            match @signals.untracked(actions) {
              Some((make, _)) => make(k)
              None => ()
            }
          },
        )
      })
      // settings at the right edge, as at Home's
      @sf.round_key_node(row, "settings", fn() { tr("android-chat.home.settings") }, fn() {
        @sfbase.history_push()
        app.nav.push(Settings)
      })
    })
    |> ignore
  })
  |> ignore
}

///|
/// The makings of pages that give a place's top bar what they do, numbered.
// kept across runs: a count
let place_actions_made : Ref[Int] = Ref(0)

///|
fn next_place_actions_gen() -> Int {
  place_actions_made.val += 1
  place_actions_made.val
}
