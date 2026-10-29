// A new chat in the pane (ember web/src/NewChat.tsx): the pages' (sfpages new_chat.mbt) in the wide frame, which adds
// what the frame has around it: the workspace's stations' files beside it, as beside a chat (its 文件 in the chat's
// bar's place, over the page; the side panel sliding in and out; a row of the tab let go over the page going into its
// message), its parts coming in as the sidebar switches to it from a chat (switch.mbt), and as it becomes its chat,
// the files open beside it open beside the chat.

///|
/// What the wide frame gives the page: no bar (its 文件 is the frame's, over it), nothing under it.
fn new_frame(src : Source, w : Workspace) -> @sfpages.NewChatFrame {
  {
    core: settings_core(src, w),
    bar: fn() {  },
    foot: 0.0,
    in_place: false,
    sent: fn(r) { new_sent(src, w, r) },
  }
}

///|
/// A new chat in the workspace (NewChat): the pages', the 文件 tab beside it where the stations lend their files
/// (useStationDrive: as the view has its stations), on a station it can start on.
pub fn new_chat_page(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let v = (src.topic)("newChat", { "scope": Json::string(w.id) }).value
  let frame = new_frame(src, w)
  let station = field(v, "station")
  let address = text(station, "station")
  let on = station is Some(Object(_)) && text(v, "blocked") == "" && address != ""
  // (what fades as it is left for a chat by the sidebar: switch.mbt)
  if on {
    page_switch.new_view = v
  }
  if new_drive_station(src, w) is None {
    @sfpages.new_chat_page(c, src, w, frame)
    return
  }
  let files = new_files_open(src, w.id)
  let page = c.id("new/page")
  let with_bar = fn() {
    c.box(style=new_frame_style, id=page, fn() {
      @sfpages.new_chat_page(c, src, w, frame)
      // its bar (newChatBar): 文件 where a chat's bar has it, over the page, what is in its middle where it is; its
      // empty part drags the window, as a chat's bar's (in one with its buttons in the app's top row)
      let bar = c.id("new/bar")
      if @ui.window_inset() {
        c.window_drag(bar)
      }
      c.layer(fn() {
        c.box(style=if @sf.in_pane() { new_files_bar_tape() } else { new_files_bar_wide(files) }, id=bar, fn() {
          if @sf.icon_button(c, "folder", key="new/files", round=true, linked?=@sf.bar_keys_link(), label=@sf.t("web-pages.chat.files")) {
            new_files_set(src, w.id, !files)
          }
          // (its end by the window's while the page is moved aside for the sidebar shown a while)
          page_bar_end(c)
        })
        |> ignore
      })
      |> ignore
      // a row of the 文件 tab carried over it, let go there: into its message (DropHint, useChatDrop)
      drop_hint(c, page)
      chat_drop(c, src, address, "new:" + w.id, page)
    })
    |> ignore
  }
  // (on the tape, laid out Medium, its panel is a panel of its own beside the page's, as a chat's: the frame's,
  // tape_side)
  if wide.tape {
    with_bar()
    return
  }
  // its panel slides in and out as a chat's does (useSidePanel)
  side_beside(c, "new:" + w.id, files, side_width(c.width), with_bar, fn() { new_files_panel(c, src, w, address) })
}

///|
/// The station workspace `w`'s new chat starts on, where the stations lend their files (useStationDrive: as the view
/// has its stations): its 文件 tab is had; None where it is not (blocked, no station, none with a drive).
fn new_drive_station(src : Source, w : Workspace) -> String? {
  let v = (src.topic)("newChat", { "scope": Json::string(w.id) }).value
  let station = field(v, "station")
  let address = text(station, "station")
  let on = station is Some(Object(_)) && text(v, "blocked") == "" && address != ""
  let drive = on &&
    items(v, "stations").iter().any(fn(s) { field(field(Some(s), "overview"), "drive") is Some(Object(_)) })
  if drive {
    Some(address)
  } else {
    None
  }
}

///|
/// The new chat of view `v` as it is left (`up`, `fade`: sfpages new_chat_left), as wide as it was: with its 文件 tab
/// open, beside where the panel is (the chat it became has the panel now, the chat it was left for its own).
fn new_left(c : @ui.Ctx, src : Source, w : Workspace, v : Json?, up : Double, fade : Double) -> Unit {
  let frame = new_frame(src, w)
  let files = new_files_open(src, w.id)
  let left = fn() { @sfpages.new_chat_left(c, src, w, frame, v, up, fade) }
  // (on the tape its panel is the frame's: the page alone)
  if wide.tape {
    left()
    return
  }
  side_beside(c, "new:" + w.id, files, side_width(c.width), left, fn() {  })
}

///|
/// The page as it becomes its chat (NewChat.tsx onSent): the chat opening without its agent's history beside it, the
/// files open beside the page open beside the chat.
fn new_sent(src : Source, w : Workspace, r : ChatRef) -> Unit {
  let files = new_files_open(src, w.id)
  side_ask(src, r, "clear", None)
  if files {
    side_ask(src, r, "open", Some("files"))
  }
}

///|
/// Over the chat a new chat became (madeChat.ts toMadeChat): the page leaving; and a new chat left for a chat by the
/// sidebar, fading over it (switch.mbt). Drawn over the chat's page, after it.
pub fn new_chat_after(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef) -> Unit {
  if @sfbase.new_chat_leaving_of(c, r) {
    let l = c.layer(fn() { new_left(c, src, w, fresh.scene.get(), new_leave(c).get(), new_fade(c).get()) })
    // (drawn only, while it leaves)
    c.draw_only(l)
  }
  switch_new_out(c, src, w)
}

///|
/// Whether the workspace's new chat has its 文件 tab open (what the core keeps for it on this device, the prefs'
/// `chatTabs` by `new:<workspace>`).
fn new_files_open(src : Source, ws : String) -> Bool {
  let kept = field(field((src.topic)("prefs", {}).value, "chatTabs"), "new:" + ws)
  items(kept, "tabs").contains(Json::string("files"))
}

///|
/// The workspace's new chat's 文件 tab opened or closed, kept by the core on this device (`chat.tabs.*`).
fn new_files_set(src : Source, ws : String, on : Bool) -> Unit {
  let open = new_files_open(src, ws)
  side_changing("new:" + ws, if open { ["files"] } else { [] }, if open { "files" } else { "" }, on)
  let call = if on { "chat.tabs.open" } else { "chat.tabs.close" }
  (src.call)(call, { "chat": Json::string("new:" + ws), "tab": "files" }, fn(_) {  })
}

///|
/// The new chat's side panel: its one tab, Station 文件 (FilesTab), closed by its × or the panel's; the files of the
/// workspace's stations, what is added going into the new chat's draft (DriveTab).
fn new_files_panel(c : @ui.Ctx, src : Source, w : Workspace, address : String) -> Unit {
  c.box(style=side_panel_style, fn() {
    c.box(style=if side_on_tape.val || @sf.in_pane() { side_bar_tape() } else { side_bar() }, fn() {
      c.box(style=side_tab_list, fn() {
        let close = c.id("new/files-tab-close")
        if c.clicked(close) {
          new_files_set(src, w.id, false)
        }
        c.box(style=side_tab_in_front, fn() {
          @sf.icon(c, "folder", size=new_tab_icon, color=@sf.theme().p.text) |> ignore
          c.text(@sf.t("web-pages.chat.files"), style=side_tab_front) |> ignore
          c.box(style=side_tab_close, id=close, fn() {
            @sf.icon(c, "close", size=new_tab_close, color=if c.lit(close) { @sf.theme().p.text } else { @sf.theme().p.muted })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
      if @sf.icon_button(c, "panel-close", key="new/files-close", round=true, linked?=@sf.bar_keys_link(), label=@sf.t("web-pages.chat.closePanel"), shortcut="panel.close") {
        new_files_set(src, w.id, false)
      }
    })
    |> ignore
    c.box(style=side_pane, fn() { files_tab(c, src, w.id, "new:" + w.id, address) }) |> ignore
  })
  |> ignore
  // (panel.close: the panel closed)
  let prefs = (src.topic)("prefs", {}).value
  if @settings.action_pressed(c, prefs, "panel.close") {
    new_files_set(src, w.id, false)
  }
}

///|
/// The panel's tab's icons.
let new_tab_icon : Double = 14.0

///|
let new_tab_close : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let new_frame_style : @ui.Style = @ui.css("w=Full h=Full")

///|
/// Where 文件 is: the chat's bar's end, over the page.
// kept across runs: a value (no field of it changes)
let new_files_bar : @ui.Style = @ui.style(row=true, w=Full, h=@sf.wide_bar_h_size, px=S3, align=ACenter, justify=JEnd)

///|
/// The same in a window's whole (laid out Large), as a chat's bar (chat_page.mbt chat_bar_box, its line under it):
/// while its panel is not open beside the page, 文件 where a chat's bar's last stands (page_bar_room:
/// @sf.window_end_in), in the window's corner following it (a Mac's) or before the window's own buttons where they are
/// the app's; beside the panel, 12 in.
fn new_files_bar_wide(beside : Bool) -> @ui.Style {
  if beside {
    new_files_bar_lined
  } else {
    new_files_bar_lined.then(@ui.style(pr=@sf.room_of(@sf.window_end_in(new_files_end))))
  }
}

///|
// kept across runs: a value (no field of it changes)
let new_files_bar_lined : @ui.Style = new_files_bar.then(@ui.css("pb=SPx"))

///|
/// The same in a panel of the tape, as a chat's bar there (chat_page.mbt chat_bar_box_tape): on the tape's line, 文件 in
/// the panel's top right corner concentric with it (@sf.tape_bar_end), clear of the line under a chat's bar as it is.
fn new_files_bar_tape() -> @ui.Style {
  new_files_bar.then(
    @ui.style(
      h=Fixed(@sf.wide_bar_h + @sf.tape_bar_over()),
      pt=@sf.tape_bar_over_room(),
      pb=SPx,
      pr=@sf.room_of(@sf.tape_bar_end(new_files_end)),
    ),
  )
}

///|
/// 文件's room at the bar's end (new_files_bar: px=S3).
let new_files_end : Double = 12.0
