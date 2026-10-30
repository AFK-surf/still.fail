// A new chat in the Small stack (ember web/src/mobile/NewChat.tsx; apps/android NewChat.kt, ChatHost.kt): the pages'
// (sfpages new_chat.mbt), risen from the bottom over the page under it (380 ms, (.2, .8, .2, 1)) under its bar (取消,
// 新对话), over the navigation bar. The first message makes the chat and the page becomes it in place
// (@ui.Nav::become), its composer and focus kept; its scene leaves over the chat (new_chat_leaving).

///|
/// A new chat's page, rising over the page on top (Places.kt: 令 in the bar's notch).
fn new_chat(c : @ui.Ctx) -> Unit {
  ignore(c)
  fresh_reset()
  lower_sheet()
  app.menu.set(false)
  open_page(NewChat)
}

///|
/// What the Small stack gives the page: its bar (Parts.kt NavBar: 取消 back, 新对话 in the middle), the navigation bar's
/// room under it (ChatHost.kt: windowInsetsPadding(keyboard.union(navigationBars))).
fn new_frame(src : Source, w : Workspace) -> @sfpages.NewChatFrame {
  {
    core: settings_core(src, w),
    bar: fn() {
      let c = @ui.current()
      if @sf.nav_bar(c, "new/cancel", tr("common.cancel"), tr("android-chat.new.title"), bg=@sf.theme().p.bg, top=status_top()) {
        @sfbase.close_page(NewChat) |> ignore
      }
    },
    foot: nav_foot(),
    in_place: true,
    sent: fn(_) {  },
  }
}

///|
/// The new chat's page (NewChatScreen).
fn new_chat_page(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  @sfpages.new_chat_page(c, src, w, new_frame(src, w))
}

///|
/// Over the chat a new chat became: its scene leaving (140 ms), then nothing.
fn new_chat_leaving(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef) -> Unit {
  if !@sfbase.new_chat_leaving_of(c, r) {
    return
  }
  let l = c.layer(fn() {
    @sfpages.new_chat_left(c, src, w, new_frame(src, w), fresh.scene.get(), new_leave(c).get(), new_fade(c).get())
  })
  // (drawn only, while it leaves)
  c.draw_only(l)
}
