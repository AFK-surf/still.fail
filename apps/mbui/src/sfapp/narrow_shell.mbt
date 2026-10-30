// Signed in with a workspace in view, laid out Small: the shell as nodes of the window's tree (mbui's view package,
// docs/retained.md, the way there's 4), made once and changed as the app's state does, the pages and what floats over
// them old views (islands) in it:
//
//   - under all of it, what the frame does in every tier before its pages (signed_in_frame: what is told as the frame
//     ends, the icon's number, the keys, whether the first page waits) and the back of the stack's root (narrow_under);
//   - the pages: the stack (app.nav) a node, each page on it a node of its own made as it is put on and let go as it
//     leaves (what it made forgotten), the page in it built while it shows (an island), where it is drawn bound to its
//     slide, which sets out at its cause's moment, once the core has given what the page shows (mbui's nav_view.mbt);
//   - over them, the bottom bar, what is open over the pages and the presenters (narrow_over, signed_in_over).
//
// Still the old frame's (the way there): which island takes a press where they lie one over another (all of them are
// told of it), back (said by the islands as they are built, in the tree's order), the theme (each island built in it).

///|
/// What the signed-in app is laid out as (app_tree): the narrow shell made of the window's tree's nodes, or the old view
/// whole (a window of its own, the wide frame, no workspace in view yet, the window's width not known yet).
priv enum ShellIs {
  Narrow
  Whole
} derive(Eq)

///|
/// Which shell the signed-in app is in for a window `width` wide (app_tree).
fn shell_is(src : Source, width : Double) -> ShellIs {
  if width <= 0.0 || @sfbase.lone_page.val is Some(_) {
    return Whole
  }
  if !(@sf.layout(width) is Small) || @sf.native_able() {
    return Whole
  }
  match workspace_in_view(src).0 {
    Some(_) => Narrow
    None => Whole
  }
}

///|
/// The narrow shell (above), in node `v`.
fn narrow_shell(v : @view.View, src : Source) -> Unit {
  @ui.old(v, fn(c) { narrow_under(c, src) }).over(Is(true)) |> ignore
  @ui.nav_view(
    v,
    app.nav,
    fn(c, page) {
      match workspace_in_view(src).0 {
        Some(w) => narrow_page_held(c, src, w, page)
        None => ()
      }
    },
    bg=fn() { @sf.theme().p.bg },
    // a page opened slides in once the core has given what it shows (App.kt Pages: LOCAL_MS at most)
    ready=fn(page) {
      match workspace_in_view(src).0 {
        Some(w) => page_ready(src, w, page)
        None => true
      }
    },
    most=page_local_ms,
    // (each page's island built again as what it is laid out by besides what it reads changes: narrow_page_key)
    page_key=fn(_page) {
      match workspace_in_view(src).0 {
        Some(w) => narrow_page_key(@ui.current(), w)
        None => ""
      }
    },
  )
  |> ignore
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
  |> ignore
}

///|
/// Under the narrow shell's pages (an island): what every frame of the app's state does (app_state_island's), what the
/// signed-in frame does before its pages (signed_in_frame), how the lists take a mouse, the back of the stack's root.
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
  // (under the pages: the stack, a page or what is open over them taking back first, said after it)
  narrow_root_back(c)
}

///|
/// Page `page` of the narrow shell's stack as its island builds it: picked words with a mouse (a finger holds to pick:
/// pick.mbt), the pictures it waits for said afresh (image_item, video_item).
fn narrow_page_held(c : @ui.Ctx, src : Source, w : Workspace, page : Page) -> Unit {
  @sfbase.held_pictures_waiting.val = false
  // (the page is its island, kept as its nodes by what it reads and its key (narrow_page_key): no part of its own)
  let built = fn() {
    let whole = c.box(style=page_whole, fn() {
      let (now, all, _, invited) = workspace_in_view(src)
      page_view(c, src, now.unwrap_or(w), all, invited, page)
    })
    @motion.scope(c, whole, bottom=true)
  }
  if @ui.pointing() is Finger {
    built()
  } else {
    c.selectable(color=@sf.alpha(@sf.theme().p.blue, 0.28), built)
  }
  // what is the page's own and takes back before it (said with it, in its island: what it reads is what the page
  // writes): the player sideways turned upright first; words picked in a chat, a link's menu, let go first (pick.mbt)
  play_back(c)
  pick_back(c)
}

///|
/// What the frame does with the app signed in and workspace `w` in view, in every tier, before its frame: what is
/// told as the frame ends, the icon's number, links, updates, what was shared in, the keys, whether the first page waits.
fn signed_in_frame(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  // (told once the frame's builds are over, as the last saw the app, the workspace and the page on top)
  c.after_build("attend", fn() { attend(src, w.id, app.nav.top() is NewChat) })
  // where the app is, put in the history's entry now as the frame ends (sfbase's app_history.mbt: a person's act
  // pushed an entry before it moved the stack); on the wide frame Home alone is passing (land)
  c.after_build("history", fn() {
    let ws = match workspace_in_view(src).0 {
      Some(now) => now.id
      None => ""
    }
    @sfbase.history_note(ws, @sfdesk.is_wide(c) && app.nav.pages() == [Home])
  })
  // notifications: shown while the app is, a tapped one's chat opened, the one of a chat on top taken off (once the
  // frame's builds are over: a build let go of follows no workspace)
  c.after_build("notices", fn() { notices_frame(src, w) })
  // the core and the workspace links are opened against, as the frame ends (links.mbt)
  c.after_build("links", fn() { links_frame(src, w) })
  // the number on the app's icon (app_frame.mbt)
  badge_frame(c, src, w)
  // a link the system opened the app with, told once: what the core says of it shown by the frame after (Ctx::tell)
  if !link_later.is_empty() {
    c.tell("links-given", fn() { links_given(src) })
  }
  // a newer build of the app asked for once (updates.mbt)
  // (asked once, with the app's version: nothing a build changes)
  update_first(src)
  // what another app shared in (share.mbt)
  share_in_frame(c)
  // files being kept on the device, said once kept (keep.mbt)
  keeps_frame(c)
  // the app's keys, in every tier (sfdesk's keys.mbt): what is the wide frame's alone does nothing laid out Small
  @sfdesk.keys(c, src, w)
  // the first page built as it opens, asking for all it shows, and shown once it has it (first_page_ms at most), as a
  // page opening is: under the splash till then (view_in), not its loading look and its list a frame or two later
  first_waiting.val = !first_page_shown(c, src, w)
}

///|
/// Laid out Small, how the lists take the hand: pointed at with a mouse (a desktop's narrow window), the wheel and the
/// trackpad scroll the lists and a drag picks words, as on the wide frame's page; a finger drags the lists and holds to
/// pick (pick.mbt).
fn narrow_lists(c : @ui.Ctx) -> Unit {
  c.mouse_drags_lists(@ui.pointing() is Finger)
}

///|
/// At the stack's root, with nothing over it or in it taking back: the shell's back (back_where: a place's top page
/// other than the chats back to the chats, in place). Above it the stack's own (swiped from the edge, the back key),
/// which pops as back_where does.
fn narrow_root_back(c : @ui.Ctx) -> Unit {
  if app.nav.depth() == 1 && !app.menu && !sheet_open() && !@sf.presenting() {
    match @sfbase.back_step() {
      Some(f) => c.on_back(f)
      None => ()
    }
  }
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
/// Page `page` of the stack laid out Small, in workspace `w`.
fn narrow_page(c : @ui.Ctx, src : Source, w : Workspace, page : Page) -> Unit {
  // what moves in the page of its own (the composer) takes its place from the page's foot, as the wide frame's pane
  // says (sfdesk's frame.mbt): the page sliding in or out, a keyboard making it shorter, move none of it (it goes with
  // the page, at once)
  let whole = c.box(style=page_whole, fn() {
    // kept as it was drawn while nothing it shows can have changed (mbui's Ctx::kept_part), read out, as the wide
    // frame's panes are (sfdesk's tape_part): a mark stepping in it, a list of another page scrolled builds none of it.
    // Its key what it is laid out by besides what it reads: the window, the bars' room, the keyboard's, the ground,
    // where it stands in the stack and the way a place came in
    let key = narrow_page_key(c, w)
    // (an island: built from its key and what it reads, the workspaces read in it, whatever else of the frame is
    // built anew; docs/retained.md, the way there's 3)
    c.kept_part(
      c.id("page/kept"),
      key,
      fn() {
        let (now, all, _, invited) = workspace_in_view(src)
        page_view(c, src, now.unwrap_or(w), all, invited, page)
      },
      read_out=true,
      own=true,
    )
  })
  @motion.scope(c, whole, bottom=true)
}

///|
/// Over the pages laid out Small: the bottom bar, a file open, the chat being made public, a visualization over the whole
/// screen.
fn narrow_over(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  // the bottom bar: on a place's top page with nothing over it; none while this device waits to be confirmed in the
  // workspace's safe mode (its Home is the wait: lock_gate; App.kt PlaceBar)
  let root = app.nav.top()
  let waiting = root == Home && @settings.lock_waiting(settings_core(src, w), w.id)
  bottom_bar(
    c,
    src,
    w,
    place_of(root),
    app.nav.depth() == 1 && place_of(root) is Some(_) && !@sfpages.search_bar_away() && !waiting,
  )
  // a file open over the pages (preview.mbt), under the menu, the sheet and the toasts
  preview(c, src)
  // the chat being made public (sfpages' publish.mbt)
  @sfpages.publish_layer(c, src)
  // a visualization over the whole screen (viz.mbt)
  viz_full_layer(c, src)
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
  // (App.kt LockPrompts): put up when no other sheet is
  @settings.lock_prompts(settings_core(src, w), !sheet_open())
  // (the core what the settings put up over a page draws with, put up by what has none at hand)
  @settings.panels_frame(settings_core(src, w))
  // ⌘K's panel and ⌘/'s shortcuts, in every tier over the pages, under the presenters (sfdesk's switcher.mbt,
  // shortcuts.mbt)
  @sfdesk.switcher(c, src, w)
  @sfdesk.keys_dialog(c, src)
  // the library's menus, picks, panels, confirms and questions (src/sf presenters.mbt), over all of those
  @sf.presented(c)
  toast(c)
  finger_loupe(c)
}
