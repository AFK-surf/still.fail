// Picking a passage of a message where it is, in the phone's chat: sfbase's pick.mbt (a finger's hold, the handles,
// the bar; a mouse's pill on the desktop), round the phone's message words, quoted into the phone composer's draft.

///|
/// As at the start (tests): nothing picked, no press remembered, no link's menu.
fn pick_reset() -> Unit {
  @sfbase.pick_reset()
  link_menu.href = ""
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
  } else if pk.ts != "" {
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
    if link_menu.at == press.frame || image_quoted_at.val == press.frame {
      pk.taken_at = press.frame
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
      found_strokes(c, key, found, found_marking.val.2, x, y, faint=found_marking.val.0 != ts)
    }
  })
}

///|
/// Whether words are picked as a desktop's (a mouse's selection over the wide frame's page, its pill) rather than as a
/// phone's.
fn desk_picks() -> Bool {
  @sfbase.mouse_picks(wide_on.val)
}

///|
/// Over the phone's list: the picked passage's handles and its bar (sfbase's pick_layer), quoted into its draft.
fn pick_layer(c : @ui.Ctx, src : Source, r : ChatRef) -> Unit {
  @sfbase.pick_layer(c, list_key(r), bar_foot(), dmax(composer_room_of(c), tabletop_clear(c)), desk_picks(), fn(
    author,
    words,
    ts,
    role,
  ) {
    draft_quote(draft_of(c, src, r), author, words, ts, role)
  })
}
