// What opens over the wide frame, drawn after it (the web's Radix portals): a right click's menu, a chat's row's menu,
// the rail's, the lists' filter, 待处理's panel, ⌘K's switcher and ⌘/'s shortcuts over a scrim, the relay's dialog. Each is the library's (@sf.menu, @sf.panel: web/ui parts.tsx Menu,
// controls.css.ts popover and menuList) over mbui's (@kit's menus and popover, the layer under them: the keys a
// menu's, the focus kept in what is open, a screen reader told what it is). A press outside one, or Esc, closes it.

///|
/// Everything the frame opens over itself, drawn after it.
pub fn overlays(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  // a right click's menu (context_menu.mbt)
  context_menu(c)
  row_menu(c, src)
  // the rail's menu, and what can be added beside it while it is changed (rail.mbt)
  rail_overlays(c, src, w)
  filter_menu(c, src, w)
  attention_panel(c, src, w)
  // ⌘K (switcher.mbt): what the frame and its page can do now offered to it
  switcher(c, src, w)
  keys_dialog(c, src)
  // a chat relayed to a channel (relay.mbt)
  relay_dialog(c, src)
  // a workspace made (new_workspace.mbt)
  new_workspace_dialog(c, src)
  // a chat shared with the viewer's other workspaces (share_dialog.mbt)
  share_dialog(c, src)
  // a chat made public (publish.mbt)
  publish_dialog(c, src)
  // a file open over the window (sfbase viewer_frame.mbt)
  file_viewer(c, src)
}
