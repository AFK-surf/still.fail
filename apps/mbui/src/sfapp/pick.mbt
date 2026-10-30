// Picking a passage of a message where it is, in the phone's chat: sfbase's pick.mbt (a finger's hold, the handles,
// the bar; a mouse's pill on the desktop), round the phone's message words, quoted into the phone composer's draft.

///|
/// As at the start (tests): nothing picked, no press remembered, no link's menu.
fn pick_reset() -> Unit {
  @sfbase.pick_reset()
  link_menu.href.set("")
  link_menu.items.set([])
  link_menu.pick = fn(_, _) {  }
  link_menu.x.set(0.0)
  link_menu.top.set(0.0)
  link_menu.bottom.set(0.0)
  link_menu.at.set(-1)
  link_menu.open.set(false)
}

///|
/// Back lets go of what is picked, and closes a link's menu, before it goes back a page (MessagePick.kt's
/// BackHandler): after the stack is drawn, as what lies over the pages.
fn pick_back(c : @ui.Ctx) -> Unit {
  if link_menu.open.get() {
    c.take_back(fn() { link_menu.open.set(false) })
  } else if pk.ts.get() != "" {
    c.take_back(fn() { pick_clear() })
  }
}

///|
/// How long a finger is held still for a long press (ViewConfiguration's long press timeout, as Compose has it).
let long_press_ms : Double = @ui.long_press_ms

///|
/// A message's words that a finger held still on picks from (sfbase's pickable): a search's strokes behind them
/// (search_marks.mbt); a press a link's menu or an image quoted took picks nothing.
fn pickable(
  c : @ui.Ctx,
  ts : String,
  author : String,
  role : String,
  words : String,
  fill_w : Bool,
  body : () -> Unit,
) -> Unit {
  let key = "pick/" + ts
  let press = c.press()
  // (a link held in it is told as it is built: then its menu's, not a pick)
  let body = fn() {
    body()
    if link_menu.at.get() == press.frame || image_quoted_at.get() == press.frame {
      pk.taken_at.set(press.frame)
    }
  }
  // a search's words in it (search_marks.mbt): their strokes behind its words
  let found = found_words_of(ts)
  @sfbase.pickable(c, ts, author, role, words, fill_w, desk_picks(), body, keep=!found.is_empty(), marks=fn(id) {
    if !found.is_empty() {
      let (x, y) = match c.laid_rect(id) {
        Some((x, y, _, _)) => (x, y)
        None => (0.0, 0.0)
      }
      found_strokes(c, key, found, found_marking.get().2, x, y, faint=found_marking.get().0 != ts)
    }
  })
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
  @sfbase.pick_layer(c, list_key(r), bar_foot(), dmax(@sfpages.composer_room(c, draft), tabletop_clear(c)), desk_picks(), fn(
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
