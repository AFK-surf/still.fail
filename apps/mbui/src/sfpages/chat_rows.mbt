// What a chat's list holds on the desktop besides its messages (ember web/src/Chat.tsx ChatRows, OutboxRow, Activity,
// useSteady; Chat.css.ts chatUnreadLine, chatOlder, chatNewer, chatEmpty, msgUnsent, msgUnsentBtn, agentActivity,
// activityLine, activityAvatar, activityRing, activityTail, activityNowText, activityElapsed, activityStop): the line
// over what is new, the pages being brought in, what was sent from here and is not in the chat yet, where it stands,
// and its agents at work.

///|
/// A line under or in a card saying something else once it is answered while it shows (`answered`), in the same room:
/// what it said fading out (options_out_ms, Leave), then what it says now fading in after it (as long, Out); nothing
/// moves. Its looks: what it said while that shows (None once gone), and what it says now.
fn said_in_place(c : @ui.Ctx, key : String, answered : Bool) -> (@ui.Look?, @ui.Look) {
  let was = @motion.presence(
    c,
    "said-was/" + key,
    !answered,
    exit=@motion.trans(fade=0.0, spec=@motion.tween(options_out_ms, ease=Leave)),
  )
  let now = match was {
    Some(_) => @ui.look(alpha=0.0)
    None =>
      @motion.presence(
        c,
        "said-now/" + key,
        true,
        enter=@motion.trans(fade=0.0, spec=@motion.tween(options_out_ms, ease=Out)),
        initial=true,
      ).unwrap_or(@ui.look())
  }
  (was, now)
}

///|
/// What is asked of the core of an entry of the outbox (`chat.retry`, `chat.discard`): by its thread, else its session.
fn outbox_call(src : Source, here : MessageHere, call : String, id : String) -> Unit {
  let p : Map[String, Json] = { "station": Json::string(here.station), "id": Json::string(id) }
  match here.view.thread {
    Some(th) => p["thread"] = Json::number(th)
    None => p["session"] = Json::string(here.session)
  }
  // (the verb alone: act says it as 无法{what}：{error})
  let what = if call == "chat.retry" {
    @sf.t("android-chat.chat.retry.verb")
  } else {
    @sf.t("android-chat.chat.delete.verb")
  }
  @ui.haptic(Confirm)
  act(src, what, "", call, Json::object(p))
}

///|
/// How many positions of either step can be seen; glyphs past the window do not make the visible change rush.
fn activity_change_places(old_cells : Array[(Double, Double)], new_cells : Array[(Double, Double)], visible : Double) -> Int {
  let mut count = 0
  let length = if old_cells.length() > new_cells.length() { old_cells.length() } else { new_cells.length() }
  for i in 0..<length {
    if (i < old_cells.length() && old_cells[i].0 < visible) || (i < new_cells.length() && new_cells[i].0 < visible) {
      count = i + 1
    }
  }
  if count > 0 { count } else { 1 }
}

///|
/// Let a new activity's room begin opening before its first words arrive.
let activity_glyph_delay_ms : Double = @ui.move_least_ms / 2.0

///|
let activity_glyph_in_ms : Double = activity_glyph_delay_ms + @sfbase.glyph_line_in_ms

///|
/// What the rows keep of their own, let go (the package's reset).
fn rows_reset() -> Unit {
  steady_nodes.clear()
  dismissed.clear()
}

///|
/// "正在发送" shows once a message has been on its way this long (SENDING_SHOWS_MS).
pub let sending_shows_ms : Double = 800.0

///|
/// An activity's line folding to its picture (FOLD_MS), its ring going as its turn ends (160).
let fold_ms : Double = 200.0

///|
/// Each thing an activity says stays this long at least (DWELL_MS) before the next begins.
let steady_dwell_ms : Double = 700.0

///|
/// A step gone before its glyphs could have arrived does not interrupt the words shown.
let steady_candidate_ms : Double = @sfbase.glyph_change_in_ms

///|
/// The ring round the picture: 24 across, its arcs 1.5 (3 round the 18).
let ring_side : Double = 24.0

///|
let ring_stroke : Double = 1.5

///|
/// The icons under what did not go (12), and an activity's stop (12).
let unsent_icon : Double = 12.0

///|
let stop_icon : Double = 12.0

///|
/// The unread line (chatUnreadLine): its rules each side 10 from its words (12 in 500, the accent), the accent at 50%.
// kept across runs: a value (no field of it changes)
let unread_row : @ui.Style = @ui.css("row w=Full gap=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let unread_rule : @ui.Style = @ui.style(w=@sf.grow, h=SPx, bg=A(Accent, O50))

///|
// kept across runs: a value (no field of it changes)
let unread_words : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=AccentText, wrap=false)

///|
/// The pages coming (chatOlder: 4 over, 8 under; chatNewer: 8 over, 4 under), a chat with nothing yet (chatEmpty).
// kept across runs: a value (no field of it changes)
let older_row : @ui.Style = @ui.css("w=Full pt=S1 pb=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let newer_row : @ui.Style = @ui.css("w=Full pt=S2 pb=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let empty_row : @ui.Style = @ui.css("w=Full py=S8 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let chat_empty_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Muted)

///|
/// What was sent from here, its words and files; what did not go as they are, not faded (at 55% its words were 3.4 to 1:
/// docs/ui-panels.md 对比度), the red under it saying so.
// kept across runs: a value (no field of it changes)
let outbox_words : @ui.Style = @ui.css("w=Full gap=S1 align=AEnd")

///|
/// Under it (msgUnsent): 4 under, at the column's end, 2 apart; its note 6 before the buttons.
// kept across runs: a value (no field of it changes)
let unsent_row : @ui.Style = @ui.css("row pt=S1 gap=SPx align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let unsent_note : @ui.Style = @ui.css("row pr=S1_5 gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let unsent_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Danger, wrap=false)

///|
/// Its buttons (msgUnsentBtn): 2 by 6 in, 4 apart, 7 round; the hover ground under the pointer; at 55% when they may
/// not be pressed.
// kept across runs: a value (no field of it changes)
let unsent_button_box : @ui.Style = @ui.css("row px=S1_5 py=S0_5 gap=S1 radius=Md align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let unsent_button_hot : @ui.Style = unsent_button_box.then(@ui.css("bg=Hover"))

///|
// kept across runs: a value (no field of it changes)
let unsent_button_off : @ui.Style = unsent_button_box.then(@ui.css("opacity=O55"))

///|
// kept across runs: a value (no field of it changes)
let unsent_label : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let unsent_label_hot : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let now_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let now_words_hot : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let activity_clock : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, wrap=false)

///|
/// Where it stands (chat_state): its icon's column (the theme's lists' state_slot, as high as a line of its words: the
/// row's line, the theme's), 6 before them; its words wrapping.
// kept across runs: a value (no field of it changes)
let chat_state_row : @ui.Style = @ui.css("row w=Full gap=S1_5 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let chat_state_wraps : @ui.TextStyle = @ui.text_style(wrap=true)

///|
/// What the chat needs of the viewer, with 忽略 (chat_state): its words taking what 忽略 leaves at its end (a column of
/// them, 忽略 under them at the end, where a native narrow chat has little room); after the bell's disc as far as a
/// state line's words after its icon (no disc drawn round it, an option's 12 leaves the bare bell far off).
// kept across runs: a value (no field of it changes)
let need_card_words : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S1_5, align=AStart)

///|
// kept across runs: a value (no field of it changes)
let need_card_actions : @ui.Style = @ui.css("row w=Full pt=S1_5 justify=JEnd")
