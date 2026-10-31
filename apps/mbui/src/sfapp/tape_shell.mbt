// Signed in with a workspace in view, on the tape (laid out Medium with a sidebar to show: sfdesk's tape_holds): the
// shell as nodes of the window's tree (mbui's view package, docs/retained.md, the way there's 4), made once, its panels
// the tape's nodes (sfdesk's tape_view.mbt), what they hold and what floats over them old views (islands):
//
//   - under all of it, what the frame does in every tier before its pages (signed_in_frame) and what the tape's frame
//     does under its panels (sfdesk's tape_under: the sidebar as it was left, the chat landed on, back);
//   - the tape: its row of panels, moved as its move says, what each holds an island of its own;
//   - over it, a station's screen, a file read or played over the whole window, what opens over the panels (sfdesk's
//     overlays.mbt), the presenters (signed_in_over): taking presses where they draw them alone, the panels' covers
//     under them the tree's;
//   - over all of it, an image opened: nodes of the tree's (wide_viewer, sfbase's viewer_tree.mbt).

///|
/// The tape's shell (above), in node `v`.
fn taped_shell(v : @view.View, src : Source) -> Unit {
  // (on the tape's ground, the sidebar's, as the old frame's tape was: what no panel covers shows it)
  v.ground(By(fn() { @sf.theme().p.sidebar })) |> ignore
  @ui.old(v, fn(c) { taped_under(c, src) }).over(Is(true)) |> ignore
  // a page opened in the page's panel shows once the core has given what it shows, the one before staying till then
  // (page_local_ms at most), as a page pushed on a phone slides in then
  @sfdesk.tape_view(v, src, ready=fn(p) { pane_ready(src, p) }, most=page_local_ms)
  @ui.old(v, fn(c) { taped_over(c, src) }).over(Is(true)) |> @ui.old_takes_own |> ignore
  wide_viewer(v, src)
}

///|
/// The wide frame off the tape (laid out Large, or with no sidebar to show), in node `v`: what the frame does in every
/// tier under all of it, the page and the block (sfdesk's pane_view.mbt), what opens over them (as taped_shell's).
fn paned_shell(v : @view.View, src : Source) -> Unit {
  // (on the page's ground, as the old frame's row was: what nothing covers shows it)
  v.ground(By(fn() { @sf.theme().p.bg })) |> ignore
  @ui.old(v, fn(c) { paned_under(c, src) }).over(Is(true)) |> ignore
  // a page opened in the pane shows once the core has given what it shows (page_local_ms at most: pane_page_built)
  @sfdesk.pane_view(v, src, ready=fn(p) { pane_ready(src, p) }, most=page_local_ms)
  @ui.old(v, fn(c) { taped_over(c, src) }).over(Is(true)) |> @ui.old_takes_own |> ignore
  wide_viewer(v, src)
}

///|
/// An image opened over the wide frame, over all of it (as narrow_shell's over its pages and bar): nodes of the
/// tree's of its own (sfbase's viewer_tree.mbt), its stage the whole window, followed; what is opened otherwise the
/// old view's over the panels (sfdesk's overlays.mbt, file_viewer).
fn wide_viewer(v : @view.View, src : Source) -> Unit {
  @sfbase.viewer_node(v, src, fn() { v.window() })
}

///|
/// Under the wide frame off the tape (an island): as taped_under, the frame's own sfdesk's pane_under.
fn paned_under(c : @ui.Ctx, src : Source) -> Unit {
  if @ui.window_inset() {
    let id = c.id("window-ground-band")
    c.window_drag(id)
    c.box(style=@ui.style(h=Fixed(window_band())), left=0.0, top=0.0, right=0.0, id~, fn() {  }) |> ignore
  }
  frame_bare.val = false
  let (now, all, _, _) = workspace_in_view(src)
  match now {
    Some(w) => {
      signed_in_frame(c, src, w)
      @sfdesk.pane_under(c, src, w, all)
    }
    None => ()
  }
}

///|
/// Under the tape's panels (an island): what every frame of the app's state does (app_state_island's), what the
/// signed-in frame does before its pages (signed_in_frame), what the tape's frame does under them (sfdesk's tape_under).
fn taped_under(c : @ui.Ctx, src : Source) -> Unit {
  if @ui.window_inset() {
    let id = c.id("window-ground-band")
    c.window_drag(id)
    c.box(style=@ui.style(h=Fixed(window_band())), left=0.0, top=0.0, right=0.0, id~, fn() {  }) |> ignore
  }
  frame_bare.val = false
  let (now, all, _, _) = workspace_in_view(src)
  match now {
    Some(w) => {
      signed_in_frame(c, src, w)
      @sfdesk.tape_under(c, src, w, all)
    }
    None => ()
  }
}

///|
/// Over the tape's panels (an island, taking presses where it draws them alone): a station's screen over the whole
/// window, as Android's ScreenActivity is over the app; a drive's text read, a film played over it too, as the web's
/// pages of a file opened (Drive.css.ts opened: fixed over everything); what opens over the panels (sfdesk's
/// overlays.mbt); the player sideways turned upright and words picked let go by back first; a visualization over the
/// whole screen; what is over the frame in every tier (signed_in_over).
fn taped_over(c : @ui.Ctx, src : Source) -> Unit {
  match workspace_in_view(src).0 {
    Some(w) => {
      match app.nav.top() {
        Screen(at) => c.layer(fn() { @sfpages.screen_page(c, src, at, system_frame()) }) |> ignore
        DriveRead(at) => c.layer(fn() { @sfpages.reader_page(c, src, at) }) |> ignore
        DrivePlay(at) => c.layer(fn() { @sfpages.play_page(c, src, at) }) |> ignore
        _ => ()
      }
      @sfdesk.overlays(c, src, w)
      play_back(c)
      pick_back(c)
      viz_full_layer(c, src)
      signed_in_over(c, src, w)
    }
    None => ()
  }
}
