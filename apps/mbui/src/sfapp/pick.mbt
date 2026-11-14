// Picking a passage of a message where it is, in the phone's chat: sfbase's pick.mbt (a finger's hold, the handles,
// the bar; a mouse's pill on the desktop), round the phone's message words, quoted into the phone composer's draft.

///|
/// As at the start (tests): nothing picked, no press remembered, no link's menu.
fn pick_reset() -> Unit {
  @sfbase.pick_reset()
  link_menu.items = []
  link_menu.pick = fn(_, _) {  }
  link_menu.x = 0.0
  link_menu.top = 0.0
  link_menu.bottom = 0.0
  link_menu.at = -1
  link_menu.open = false
}

///|
/// Back lets go of what is picked, and closes a link's menu, before it goes back a page (MessagePick.kt's
/// BackHandler): after the stack is drawn, as what lies over the pages.
fn pick_back(c : @ui.Ctx) -> Unit {
  if link_menu.open {
    c.take_back(fn() { link_menu.open = false })
  } else if @sfbase.picked.get().ts != "" {
    // (as told: picked as a message's row is built, elsewhere than this may be built: what lies over the tape's)
    c.take_back(fn() { pick_clear() })
  }
}

///|
/// Whether words are picked as a desktop's (a mouse's selection over the page, its pill) rather than as a phone's: by the
/// hand (@sfbase.mouse_picks).
fn desk_picks() -> Bool {
  @sfbase.mouse_picks()
}

///|
/// Over the phone's list: the picked passage's handles and its bar (sfbase's pick_layer), quoted into its draft.
fn pick_layer(c : @ui.Ctx, src : Source, r : ChatRef) -> Unit {
  let draft = draft_key(r)
  @sfbase.pick_layer(c, list_key(r), bar_foot_of(r), dmax(@sfpages.composer_room(c, draft), tabletop_clear(c)), desk_picks(), fn(
    author,
    words,
    ts,
    role,
  ) {
    // into the chat's draft, as the core keeps it (the composer's: sfpages)
    c.tell("pick/quote", fn() {
      @sfbase.writing_quote(src, @sfbase.writing(src, draft), {
        "author": Json::string(author),
        "text": Json::string(words),
        "ts": Json::string(ts),
        "role": Json::string(role),
      })
    })
  })
}
