// Where people write to a chat on the desktop (still.fail web/src/Chat.tsx ComposerView, ComposerTools, useComposerText's
// field, ComposerExtras, sendDraft; styles/composer.css.ts, Chat.css.ts composerText, composerToolbar, sendBtn,
// attachBtn, composerFiles, composerChoices, chatError; NewChat.css.ts's frosted box; dock.css.ts's width): a frosted
// capsule that grows into a box with its text, ＋ and send at its ends; opened (focused, written in, a file or a quote
// waiting, a new chat's roomy one) the text above and its row of ＋, the page's choices and send under it, the quotes
// and files waiting over the text. What it holds is the draft as the core keeps it (sfbase's compose.mbt). Enter sends,
// ⇧Enter starts a line; with nothing typed ↑ / ↓ go to the chat above or below; a file picked, pasted or carried in goes
// up to the chat's station at once.

///|
/// What the composer writes to and how it shows (ComposerProps): its station (where its files go up), its draft's key,
/// its chat's session (typing warms its agent; the `@` menu leaves it out; "" none), what its field says while empty,
/// the page's choices in its row (a new chat's), what it says before send and the control for it beside that (a chat's
/// 抄送), laid out roomy (its text over its row even for one line), locked (it takes words, nothing goes), its station
/// offline (no file taken in).
pub(all) struct ComposerSpec {
  station : String
  draft : String
  session : String
  placeholder : String
  toolbar : (() -> Unit)?
  /// what it says just before send (where a chat's messages are copied: each thread's mark, "slack" or "feishu", and
  /// its place), nothing to press: on one line and in its row once opened alike, in one place, going with send as it
  /// changes shape; empty nothing
  note : Array[(String, String)]
  /// what changes that, in its row once opened, just before what it says (a chat's 抄送); not on one line
  tail : (() -> Unit)?
  roomy : Bool
  locked : Bool
  offline : Bool
  warm_agent : Bool
}

///|
/// What the composer keeps of its own: when the cursor left it (it stays a box a moment, LET_GO_MS), when typing last
/// warmed the agent's runtime, each quote's comment field, how it was laid out as it was last drawn (a new chat's
/// roomy, or a chat's: another, it has moved between the pages), which chat it was for (another: switched to, the
/// cursor put in it), the archived chats being restored and why restoring one failed (by their drafts).
priv struct Composing {
  let_go : @signals.Signal[Bool]
  /// the moment the box it stayed after the cursor left was last let go of (let_go's end): a change of its own then
  mut let_go_at : Double
  warmed : Map[String, Int]
  /// words typed into its field since it was last built (told the core as they were typed: composer_text's
  /// `on_change`), for its build to warm the agent's runtime
  mut typed : Bool
  comments : Map[String, @ui.Field]
  mut roomy : Bool?
  mut draft : String
  /// each draft's page's time on top (Ctx::page_stint) as it was last switched to it there: switched to it again in
  /// the same stint (two chats' composers built at once, the one under sliding away as another's comes over it), it
  /// does not take the cursor again; only the page come on top does
  took : Map[String, Int]
  /// the moment it was last switched to another chat and the one it was for till then (the switch as it was first built:
  /// each build and frame made at that moment starts from that one, frame_body may build it twice)
  mut draft_was : (Double, String)
  /// the moment it was last laid out for another page (a new chat's roomy in the page, a chat's at its foot) and how it
  /// was laid out, the choices in its row and whether the soft keyboard was up till then (as draft_was)
  mut roomy_was : (Double, Bool?, (() -> Unit)?, Bool?)
  /// as they were before what this build is built at changed them (draft_was, roomy_was): as this build has them
  mut roomy_before : Bool?
  /// whether the soft keyboard was up as it was last built (new_chat.mbt's `wide` reads the same)
  mut keys_up : Bool?
  mut draft_before : String
  /// whether what waits in it now was in it before it was switched to it at this moment (the same draft): what is put
  /// in since comes in (held_coming), what a draft opened with is there at once
  mut same_draft : Bool
  /// whether this build is the one that switched it to another chat (the first built for it): what its field says
  /// while empty put at once, as it is then (composer_text)
  mut switching : Bool
  /// whether a notice over a chat's composer, new to it, comes in (chat_notices: the chat shown before, composer_was)
  mut notices_new : Bool
  /// what each notice over a chat's composer said as it was last drawn, by its key: drawn so as it leaves
  notices_said : Map[String, (String, (Int, String, String, Bool)?, (Int, String, Bool)?, String??, String, Array[(Int, String, Bool)], (String, String)?)]
  /// the page's choices in its row as it was last built, as they were before this build's page (roomy_was), and those
  /// of the page it came from that this one has not, while they leave (a new chat's, gone to its chat)
  mut toolbar : (() -> Unit)?
  mut toolbar_before : (() -> Unit)?
  mut toolbar_leaving : (() -> Unit)?
  restoring : @sf.LiveMap[String, Bool]
  restore_errors : @sf.LiveMap[String, String]
  /// the draft its field was last built for and whether it was empty then (composer_foot_room)
  mut emptied : (String, Bool)
  /// till when words last sent from which draft held it (composer_held): its ground's ways said before then are theirs,
  /// none of the list's (composer_way_for_list)
  mut held_till : (String, Double)
  /// the draft, its field's lines and whether it was open as it was last built, and when its lines last changed while
  /// it stayed open (-inf: not since it opened): what words sent stop its shape for (composer_view)
  mut lines_seen : (String, Int, Bool)
  mut lines_moved_at : Double
  /// what its field says while empty as it was last drawn, till another is to be said and it has faded out
  /// (composer_text)
  hint_shown : @signals.Signal[String]
  /// the cursor asked into it in this frame (it has it from the next): what it says while empty is
  /// what it says with the cursor in it already
  taking : @signals.Signal[Bool]
  /// its 抄送 menu open (cc_chooser)
  mut cc_open : Bool
  /// the cache choice menu open for this notice (composer_notice)
  cold_open : @signals.Signal[String]
  /// the shape its field's hint was last shown on (composer_hint): changed, the hint waits till it is there
  mut hint_shape : String
  /// whether it is a box or a capsule and how roomy: the moment that last changed, what it was till then and what it is
  /// as built now (composer_opening)
  mut opened : (Double, String, String)
  /// the cursor asked into it as it is next drawn, on any screen (composer_take_focus)
  mut wanted : Bool
  /// each quote's card's colour as it was last drawn, by quote: where its ground sets out from as it is sent
  /// (flying_quotes)
  grounds : Map[String, Int64]
  /// each quote's own picture as it was last drawn in its card, by quote: what flies from there as it is sent
  pictures : Map[String, MediaPicture]
  /// what its box changed shape for and how as it was built in what composer_shaped builds (None till it is)
  mut shaped : (String, @motion.Spec)?
  /// each draft's composer's corner as it was last built, where it stands (its place's): what its chat's list keeps clear
  /// for it is worked out from (composer_least), not from another composer's built last (a chat beside another's)
  corners : @sf.LiveMap[String, Double]
}

///|
/// The cursor into the composer as it is next drawn, with touch too (its keyboard up): what opened it is for
/// writing (新建对话: pengxiao, 2026-10-25).
pub fn composer_take_focus() -> Unit {
  composing.wanted = true
}

///|
let composing : Composing = {
  let_go: @signals.signal(false, same=fn(a, b) { a == b }),
  let_go_at: @double.neg_infinity,
  warmed: {},
  typed: false,
  comments: {},
  roomy: None,
  draft: "",
  took: {},
  roomy_before: None,
  keys_up: None,
  draft_before: "",
  draft_was: (-1.0, ""),
  roomy_was: (-1.0, None, None, None),
  same_draft: false,
  switching: false,
  notices_new: false,
  notices_said: {},
  toolbar: None,
  toolbar_before: None,
  toolbar_leaving: None,
  restoring: @sf.LiveMap::new(),
  restore_errors: @sf.LiveMap::new(),
  emptied: ("", true),
  held_till: ("", -1.0),
  lines_seen: ("", 0, false),
  lines_moved_at: @double.neg_infinity,
  hint_shown: @signals.signal("", same=fn(a, b) { a == b }),
  taking: @signals.signal(false, same=fn(a, b) { a == b }),
  cc_open: false,
  cold_open: @signals.signal("", same=fn(a, b) { a == b }),
  hint_shape: "",
  opened: (-1.0, "", ""),
  wanted: false,
  grounds: {},
  pictures: {},
  shaped: None,
  corners: @sf.LiveMap::new(),
}

///|
fn composing_reset() -> Unit {
  composer_foot_way.val = None
  composer_set_off.val = ("", 0.0)
  picked_waiting.clear()
  composing.let_go.set(false)
  composing.let_go_at = @double.neg_infinity
  composing.warmed.clear()
  composing.typed = false
  composing.comments.clear()
  composing.grounds.clear()
  composing.pictures.clear()
  composing.roomy = None
  composing.draft = ""
  composing.took.clear()
  composing.roomy_before = None
  composing.keys_up = None
  composing.toolbar = None
  composing.toolbar_before = None
  composing.toolbar_leaving = None
  composing.draft_before = ""
  composing.draft_was = (-1.0, "")
  composing.roomy_was = (-1.0, None, None, None)
  composing.same_draft = false
  composing.switching = false
  composing.notices_new = false
  composing.notices_said.clear()
  composing.restoring.clear()
  composing.restore_errors.clear()
  composing.emptied = ("", true)
  composing.held_till = ("", -1.0)
  composing.lines_seen = ("", 0, false)
  composing.lines_moved_at = @double.neg_infinity
  ref_keyed.val = ""
  composing.cc_open = false
  composing.cold_open.set("")
  composing.hint_shape = ""
  composing.opened = (-1.0, "", "")
  composing.wanted = false
  composing.hint_shown.set("")
  composing.taking.set(false)
  composing.corners.clear()
}

///|
/// The composer's text field (its words, a flight's from: flight.mbt), its box, what is in it.
pub let composer_field_key : String = "composer/field"

///|
/// The menu belonging to a notice's choice, keyed by the chat and notice that showed it.
fn notice_choice_key(chat : String, mark : String) -> String {
  "composer/notice/" + chat + "/" + mark + "/choice"
}

///|
/// The composer (ComposerView) for `spec`, `send` what pressing send (or Enter) does with what is written once it is
/// ready. Drawn where its place is; a page lays it out (its width: composer_width). `place`: where it stands at a
/// panel's foot (composer_place: each shape where it stands concentric with the corners it is in, the morph between
/// them).
pub fn composer(
  c : @ui.Ctx,
  src : Source,
  ws : Workspace,
  spec : ComposerSpec,
  send : (Writing) -> Unit,
  place? : ComposerPlace = composer_alone,
) -> Unit {
  let p = @sf.theme().p
  let w = writing(src, spec.draft)
  let no_files = spec.locked || spec.offline
  // (its corner where it stands, what waits in it and its ＋ and send following it)
  @sf.composer_round.val = place.corner
  if @signals.untracked(fn() { composing.corners.get(spec.draft) }) != Some(place.corner) {
    composing.corners.set(spec.draft, place.corner)
  }
  // what the system's picker answered, taken in before the box is laid out (the host's word that it answered brings
  // this frame); the files pasted into the field; what 文件's 添加到消息 put in for this draft
  take_in(c, src, spec, w, no_files)
  // switched to another chat (Chat.tsx: its thread another; a new chat's has none, whichever station): the cursor in
  // it with keyboard and mouse (its keyboard at hand), before it is first drawn; not taken from a field in use (the switcher's, a dialog's)
  let whose = "\u{1}" + spec.session
  // (switched to another chat or laid out for another page: recorded as it is first built so, with its moment and what
  // it was till then; what each build and frame at that moment starts from, frame_body building it again)
  composing.switching = whose != composing.draft
  if composing.switching {
    composing.draft_was = (c.moment(), composing.draft)
  }
  if composing.roomy != Some(spec.roomy) {
    composing.roomy_was = (c.moment(), composing.roomy, composing.toolbar, composing.keys_up)
  }
  composing.draft_before = composer_was(c)
  let (roomy_at, roomy_was, toolbar_was, keys_up_was) = composing.roomy_was
  composing.roomy_before = if roomy_at == c.moment() { roomy_was } else { composing.roomy }
  composing.toolbar_before = if roomy_at == c.moment() { toolbar_was } else { composing.toolbar }
  // (the keyboard as it was before this build's moment changed how roomy it is)
  let keys_up_before = if roomy_at == c.moment() { keys_up_was } else { composing.keys_up }
  composing.same_draft = whose == composing.draft_before
  if whose != composing.draft {
    composing.draft = whose
    // (once a time its page is on top: built again in the stint it was switched to in, as another chat's is built
    // beside it, it is the page under that one, not one come to; outside a stack, each switch)
    let stint = c.page_stint()
    let come = stint == 0 || composing.took.get(whose) != Some(stint)
    composing.took[whose] = stint
    // (where the keyboard is at hand, typed into at once; not raising the screen's keyboard over the chat; not taken from
    // a field written in, but asked under a modal layer over it all the same: kept for that layer to give back)
    if come && !@sf.soft_keyboard() && !c.field_focused_here() {
      c.focus_field(w.field)
      composing.taking.set(true)
      // (this frame's alone: what reads it built again the frame after, as it has the cursor)
      c.tell("composer/taking", fn() { composing.taking.set(false) })
    }
  }
  // asked for (a new chat: composer_take_focus), with touch too, its keyboard up
  // (asked again till it is found held as a frame begins: the page it was asked from let go of as the new one comes,
  // its field's focus with it, nav.mbt forget)
  if composing.wanted && !spec.locked {
    if w.field.focused() {
      composing.wanted = false
    } else {
      c.focus_field(w.field)
      composing.taking.set(true)
      // (this frame's alone: what reads it built again the frame after, as it has the cursor)
      c.tell("composer/taking", fn() { composing.taking.set(false) })
    }
  }
  let focused = w.field.focused()
  // The cache choice takes focus into its menu. Keep an already open composer in place while that menu is open, so
  // the notice and its menu do not move under the pointer. A composer that was a capsule stays one.
  let choosing_cache = composing.cold_open.get() == notice_choice_key(spec.draft, "wait")
  // a box while it has the cursor; lost, a capsule a moment later (LET_GO_MS)
  if focused {
    composing.let_go.set(true)
  }
  let lost_long = @kit.after(c, "composer/let-go", !focused && !w.field.parked() && !choosing_cache, let_go_ms)
  let held = composing.let_go.get() && !focused && !lost_long
  // (the box it stayed a moment after the cursor left, let go of now: a change of its own, at this moment, whatever
  // words sent from it are doing meanwhile)
  if lost_long && composing.let_go.get() {
    composing.let_go_at = c.moment()
  }
  // (as each build at this moment has it: frame_body may build it twice)
  let let_go_now = lost_long && composing.let_go_at == c.moment()
  if lost_long {
    composing.let_go.set(false)
  }
  // words just sent from it still in it: laid out as for them, as many lines as they took (composer_held_lines), so it
  // goes on to the shape it was on its way to and nothing in it moves until it comes down; its shape for the field's
  // words as they were, not as it is emptied
  let held_lines = composer_held_lines(c, spec.draft)
  let held_extras = composer_held_extras(c, spec.draft)
  composing.emptied = (spec.draft, w.field.text() == "")
  let multiline = spec.roomy ||
    focused ||
    held ||
    held_lines > 0 ||
    w.text.get() != "" ||
    w.files.get().length() > 0 ||
    w.quotes.get().length() > 0
  // ready as the core says, or as soon as there are words in the field: the core's say comes a moment after them (its
  // topic), and send pressed meanwhile is not lost (what goes is the core's to take: composer.take, nothing taken
  // nothing sent)
  let ready_now = fn() { (w.ready.get() || (w.field.text().trim() != "" && !w.starting.get())) && !spec.locked }
  let ready = ready_now()
  // sent once what it refers to can be read in this workspace (sfbase's outside.mbt): at once when
  // it refers to nothing of another workspace, else once the viewer has said so (outside.mbt's dialog)
  @sfbase.sharing_go(w.key)
  let quote_had = quote_has_focus(c, w)
  // (asked again as send is pressed, of the field: words typed since this build, a frame not drawn yet, told to the
  // core first and go with it)
  let submit = fn() {
    if ready_now() {
      writing_text(src, w, w.field.text())
      // (the line of a quote it takes had the focus: the words' field has it from here, as Enter in that line gives
      // it, not lost with the line as its card sets out)
      quote_focus_to_words(c, w, quote_had)
      @sfbase.send_sharing(src, w.key, spec.station, w.text.get().trim(chars=" \n\t").to_owned(), fn() { send(w) })
      // (sent in this build, after its field was built: their field's hint and caret gone with them from now, not
      // shown once over them as they set out)
      if @sfbase.flight_hint_away(c, w.key) {
        w.field.colors(placeholder=@sf.alpha(p.subtle, 0.0), caret=@sf.alpha(p.accent, 0.0))
      }
    }
  }
  outside_dialog(c, src, w.key)
  let cap = c.id("composer/cap")
  // Its glass covers the messages below, including where a press lands beside its field.
  c.blocks_selection(cap)
  // (a press on it is its field's: the I-beam over it)
  if !spec.locked {
    c.cursor(cap, IBeam)
  }
  if !spec.locked {
    // (its words' field given the focus: the field itself, as a press finds no editor built then)
    c.on_press(cap, fn() { c.focus_field(w.field) })
  }
  // words dragged in from another app and let go on it beside its field (its ＋, send, its edge: on the field they go
  // where they were let go): into its field at its caret, as a paste's
  // files from this machine's Finder let go on it (or on its field) where it is a station: by its station and path,
  // named so or sent as files as the chat takes what is dragged in; elsewhere into its field as their paths, as words
  if !no_files && @sfbase.finder_by_station() {
    match c.paths_into(cap, composer_field_key) {
      Some(paths) =>
        writing_drop(src, w, spec.station, @sfbase.finder_dragged(src, paths).map(dropped_of), drops_as_files(src, w.key))
      None => ()
    }
  }
  if !spec.locked {
    c.words_into(cap, composer_field_key)
  }
  // dragged over: marked (the 文件 tab's rows; files from the computer the page takes)
  let dragging = !no_files && (@sfbase.drag_carried.val)() is Some(_) && c.lit(cap)
  // laid out for another page than before (a new chat's roomy in the page, become its chat's at its foot): at the
  // moment it was. The same draft laid out roomy or not with the soft keyboard as it was (a new chat's page made
  // narrower or wider by the window, an edge dragged: new_chat.mbt's `wide`) has moved to no other page: what it is
  // laid out as there at once, nothing in it moving for it (apps/mbui/AGENTS.md, Motion). The keyboard come or gone as
  // it changed is its taking the focus or letting it go, seen through the keyboard: its own cause, moved as ever
  let roomy_changed = match composing.roomy_before {
    Some(was) => was != spec.roomy
    None => false
  }
  let keys_up = c.ime_inset() > 0.0
  let keys_same = keys_up_before == Some(keys_up)
  let laid_anew = roomy_changed && composing.same_draft && keys_same
  let moved = roomy_changed && !laid_anew
  // (gone to its chat's foot as a new chat's first words set out from it: on their way and as long, one motion with
  // them, not a page's quick start that leaves them behind and goes far in its first frame)
  let opening = composer_opening(c, "\{spec.roomy}|\{multiline}")
  // (words sent letting go of it shape it on their clock only for what they change: the cursor's box let go of
  // meanwhile (let_go_now) is a change of its own, from now, not one as far on as the time since they let go)
  let sent_lets_go = composer_let_go(c, spec.draft) && !let_go_now
  let shape = if moved && flight_carried(spec.draft) {
    @motion.tween(flight_desk_ms, ease=Flight)
  } else if sent_lets_go {
    // (let go by words sent from it: down on their flight's clock, with its room, flight_lets_go)
    // (said where their row's opening is: flight_lets_go)
    // det-ok(motion-length): words sent's own, set with their flight (sf/motion.mbt kind 4)
    @motion.tween(composer_down_ms(spec.draft), ease=Move)
  } else if opening && !moved {
    // (opened from a capsule or let go to one: its field passes by its ＋ and send on their way, kept off them only on
    // this clock so far; on a faster one it cut into ＋, the user 2026-10-30: 「输入框盖住了加号和发送」)
    // det-ok(motion-length): the field opening past ＋ and send kept off them on this clock, till their cutting is mended
    @motion.tween(composer_shape_ms, ease=Move)
  } else {
    @motion.moved()
  }
  let hint = composer_hint(
    c,
    spec,
    w,
    focused || held,
    moved,
    laid_anew,
    "\{spec.roomy}|\{multiline}|\{w.files.get().length()}|\{w.quotes.get().length()}|\{w.error.get() != ""}",
    shape,
  )
  // gone to a page with no choices in its row from one with them (a new chat become its chat, or left for one): they
  // leave as the new chat's other parts by the composer do (@sfbase.new_fade),
  // carried with the row as it goes, drawn only; till the end that fade declared
  if moved {
    composing.toolbar_leaving = if spec.toolbar is None { composing.toolbar_before } else { None }
  }
  let fade = @sfbase.new_fade(c)
  if fade.over(c) {
    composing.toolbar_leaving = None
  }
  composing.toolbar = spec.toolbar
  // its parts, as this build has them
  let mut plus = -1
  let mut words = -1
  let mut send_i = -1
  let mut chosen = -1
  let mut said = -1
  // A still appearing can turn a file card into a tile, and a quote can acquire its own picture. Both change what the
  // composer holds even when the number of files and quotes stays the same.
  let quote_pictures = w.quotes.get().map(fn(q) { quote_picture(c, src, w, spec.station, Some(q)) })
  let file_pictures = w.files.get().map(fn(f) { waiting_picture(src, w, Some(f)) })
  // (what it is shaped for: what it holds, or what words sent from it held as they were sent while they hold it, so
  // it is shaped for the same till they let go of it: composer_held_lines)
  let shapes = @sfbase.flight_held_shaped(c, spec.draft).unwrap_or(composer_shapes(w, quote_pictures, file_pictures))
  let holds = if (whose != composing.draft_before && !moved) || laid_anew {
    ""
  } else {
    "\{spec.roomy}|\{multiline}|\{w.error.get() != ""}|" + shapes
  }
  // (sent as it was on its way to another shape (a line more just typed, or one fewer): its shape told to stop there,
  // on from where it was and as fast, slowing to rest (its place going on), held so till the words let go of it: they
  // are gone, it grows no further for them, as they were sent, not where a frame drew it)
  // (only a way its lines set it on: one it is on as it opens or shuts is no line of theirs, and goes on)
  let lines_now = @sfbase.field_lines_n(w.field)
  match composing.lines_seen {
    (d, n, open) if d == spec.draft && open == multiline =>
      if multiline && n != lines_now {
        composing.lines_moved_at = c.moment()
      }
    _ => composing.lines_moved_at = @double.neg_infinity
  }
  composing.lines_seen = (spec.draft, lines_now, multiline)
  match @sfbase.flight_of(spec.draft) {
    Some(f) if !f.stopped && held_lines > 0 && composing.lines_moved_at > @double.neg_infinity => {
      f.stopped = true
      @motion.stop_for(c, holds, f.sent_at)
    }
    _ => ()
  }
  let box = c.box(
    style=if multiline {
      composer_box_open()
    } else {
      composer_box.then(capsule_place(c, place))
    },
    // (the raised ground's glass, the accent's over it while dragged over)
    glass=@sf.glass_floating(tint?=if dragging { Some(@sf.alpha(p.accent, drag_tint)) } else { None }),
    id=cap,
    fn() {
      composer_extras(c, src, spec, w, holds, shape, quote_pictures, file_pictures, held_extras)
      if multiline {
        words = composer_text(c, src, ws, spec, w, cap, multiline, hint, submit)
        c.box(style=tools_row(), fn() {
          plus = attach(c, src, spec, w, no_files)
          match (spec.toolbar, composing.toolbar_leaving) {
            (Some(f), _) => {
              chosen = c.box(style=choices, f)
              // a new chat's, the chat its first words were sent to not made: coming back as its other parts by the
              // composer do
              let (_, gone) = @sfbase.new_sending(c)
              if gone > 0.0 {
                c.look(chosen, @ui.look(alpha=1.0 - gone))
              }
            }
            (None, Some(f)) => {
              chosen = c.box(style=choices, fn() { c.hidden_from_semantics(f) })
              c.look(chosen, @ui.look(alpha=1.0 - fade.get(c)))
              c.draw_only(chosen)
            }
            (None, None) => c.box(style=tools_gap, fn() {  }) |> ignore
          }
          c.box(style=tail_row, fn() {
            match spec.tail {
              Some(f) => c.box(style=tail_box, f) |> ignore
              None => ()
            }
            said = composer_note(c, spec.note)
            send_i = send_button(c, ready, w.starting.get(), submit)
          })
          |> ignore
        })
        |> ignore
      } else {
        plus = attach(c, src, spec, w, no_files)
        words = composer_text(c, src, ws, spec, w, cap, multiline, hint, submit)
        c.box(style=tail_row, fn() {
          said = composer_note(c, spec.note)
          send_i = send_button(c, ready, w.starting.get(), submit)
        })
        |> ignore
      }
    },
  )
  // over a chat's messages: their scroll bar keeps clear of it
  c.floats_over(box)
  // capsule ⇄ box in one motion for what it holds (useMorph, morph.ts grow: its words, files, quotes, its being opened,
  // what it says under it): laid out as it ends at once, its ground going from the shape it had to this one, its parts
  // from where they showed to their places; laid out for the other page (a new chat's in the page, a chat's at its
  // foot: dock.tsx), the same from where it was there, one composer changing, and what it holds there that it did not
  // here (a new chat's choices) carried on its ground, what it held there and does not here leaving
  // on it; words sent from it, as they let go of it (held till then: composer_held_lines). Moved by nothing of these (the
  // window, the sidebar, a keyboard), or another chat's on the same page (what it holds swapped, not changed), it is
  // where it is laid out at once (sf/motion.mbt)
  composing.roomy = Some(spec.roomy)
  composing.keys_up = Some(keys_up)
  // (at a page's foot down the system's column, not roomy in a new chat's middle: opened from its foot, a keyboard
  // coming in the same frame taken at once, the user 2026-10-30 「以底部为 origin」; there the keyboard lifts it from its
  // first point on, ios_app.m ime_over)
  // (let go by words sent from it: the moment they let go of it, as their way said it (flight_lets_go), handed to the change
  // that makes, its ground down from then on their clock, the list's foot with it, not from the frame that lays it out
  // after; said only while they let go of it, so no other change carries it)
  @motion.reshape(
    c,
    box,
    "composer/box",
    by=holds,
    spec=shape,
    carry=moved,
    foot=!spec.roomy && @sf.native_side(),
    at?=if sent_lets_go { Some(composer_released_at(spec.draft)) } else { None },
  )
  composing.shaped = Some((holds, shape))
  // (its ＋ and send drawn whole on their way, its field going up past them as it opens: composer_hint_wbtest, the user
  // 2026-10-30 「输入框盖住了加号和发送」)
  for part in [(plus, "plus"), (words, "words"), (send_i, "send"), (chosen, "choices"), (said, "note")] {
    if part.0 >= 0 {
      @motion.layout(c, part.0, "composer/part/" + part.1, spec=shape, by=holds, whole=part.1 == "plus" || part.1 == "send")
    }
  }
  @motion.measure(c, box, "composer/content")
  if w.error.get() != "" {
    c.box(style=error_box, fn() { c.text(w.error.get(), style=composer_error_words) |> ignore }) |> ignore
  }
}

///|
/// `body` built (what builds the composer where it stands on its page), and what the composer built in it changes shape
/// for and how (its box's reshape: `by`, `spec`), for what stands round it on its page (a new chat's choices over it,
/// its scene): moved for that too, by the same, it goes with the box's ground in the same frames, not to its new place
/// at once. None when `body` did not build it.
fn[T] composer_shaped(body : () -> T) -> (T, (String, @motion.Spec)?) {
  composing.shaped = None
  // (left as it is after: one round it, its body this, reads it too)
  let made = body()
  (made, composing.shaped)
}

///|
/// Node `i` keyed `key`, standing round the composer (over it, under it, beside it), moves with its box as that
/// changes shape (`shaped`, composer_shaped's for what built it).
fn with_composer(c : @ui.Ctx, i : Int, key : String, shaped : (String, @motion.Spec)?) -> Unit {
  match shaped {
    Some((by, spec)) => @motion.layout(c, i, key, spec~, by~)
    None => ()
  }
}

///|
/// What comes into the draft from outside the field before the box is laid out: the files the system's picker
/// answered (for this draft), the files pasted into the field (⌘V with files or a picture on the clipboard, as the
/// web's paste takes the clipboard's files), the rows the 文件 tab's 添加到消息 put in (named by their path, or as files where this chat
/// takes what is dragged in so).
fn take_in(c : @ui.Ctx, src : Source, spec : ComposerSpec, w : Writing, no_files : Bool) -> Unit {
  // (what was put into the draft from elsewhere: built again as it is)
  @sfbase.drafts_given_read(w.key)
  match picked_waiting.get(w.key) {
    Some(list) => {
      picked_waiting.remove(w.key)
      if !no_files {
        @signals.untracked(fn() {
          for f in list {
            writing_add_picked(src, w, spec.station, f)
          }
        })
      }
    }
    None => ()
  }
  // files shared into the app from another, for this draft (share.mbt)
  match shared_into.get(w.key) {
    Some(list) if !no_files => {
      shared_into.remove(w.key)
      c.tell("composer/shared/" + w.key, fn() {
        for f in list {
          writing_add_picked(src, w, spec.station, f)
        }
      })
    }
    _ => ()
  }
  match c.field_files(composer_field_key) {
    Some(files) if !no_files =>
      for f in files {
        writing_add(src, w, spec.station, f.0, f.1)
      }
    _ => ()
  }
  // the videos waiting that the host has no picture of: their first frames, made from their bytes
  @sfbase.writing_stills(c)
  // a message's files quoted from their menus (sfpages menus.mbt): each a quote with its file in its card
  match quoted_into.get(w.key) {
    Some(list) if !no_files => {
      quoted_into.remove(w.key)
      c.tell("composer/quoted/" + w.key, fn() {
        for q in list {
          let name = text(Some(q.3), "name")
          writing_quote(
            src,
            w,
            {
              "author": Json::string(q.0),
              "text": Json::string(name),
              "ts": Json::string(q.1),
              "role": Json::string(q.2),
            },
            file=q.3,
          )
        }
      })
    }
    _ => ()
  }
  // words a visualization of this chat asked to send (sfbase viz_page.mbt): after what is written, the cursor in it
  match followed_into.get(w.key) {
    Some(words) => {
      followed_into.remove(w.key)
      let now = w.text.get()
      let said = if now.trim() == "" { words } else { now.trim_end().to_owned() + "\n" + words }
      w.field.set(said)
      c.tell("composer/followed/" + w.key, fn() { writing_text(src, w, said) })
      c.focus_field(w.field)
    }
    None => ()
  }
  // pictures marked for this chat (a service's page, an image viewed: sfbase's marked_into), each going up with a quote
  // per mark (what is said of it its comment): a page's mark's screenshot as its quote's picture, an image's as a file
  // beside its marks' quotes; taken once, whichever build takes them
  match marked_into.get(w.key) {
    Some(list) if !no_files => {
      marked_into.remove(w.key)
      c.tell("composer/marked/" + w.key, fn() {
        for x in list {
          let (name, bytes, quotes, kind) = x
          if kind != "page" {
            writing_add(src, w, spec.station, name, bytes)
          }
          for q in quotes {
            let quote : Json = {
              "author": Json::string(q.0),
              "text": Json::string(q.1),
              "comment": Json::string(q.2),
              "role": Json::string(kind),
            }
            if kind == "page" {
              writing_quote(src, w, quote, picture=(spec.station, name, bytes))
            } else {
              writing_quote(src, w, quote)
            }
          }
        }
      })
    }
    _ => ()
  }
  let sent = @sfbase.files_taken(w.key)
  if !sent.is_empty() && !no_files {
    writing_drop(src, w, spec.station, sent.map(dropped_of), drops_as_files(src, w.key))
  }
}

///|
/// Whether what is carried into draft `key` goes as files (the chat's own choice, else the device's: prefs
/// `dropFiles`, `dropAs`), not named by its path.
pub fn drops_as_files(src : Source, key : String) -> Bool {
  let prefs = src.topic("prefs", {}).get().value
  match field(field(prefs, "dropFiles"), key) {
    Some(True) => true
    Some(False) => false
    _ => text(prefs, "dropAs") == "file"
  }
}

///|
/// A station's file or folder carried in: which station has it and where, and where it is in
/// that station's drive.
pub fn dropped_of(d : Dragged) -> Json {
  {
    "name": Json::string(d.name),
    "size": Json::number(d.size),
    "ref": {
      "station": Json::string(d.station),
      "stationName": Json::string(d.station_name),
      "path": Json::string(d.abs),
      "dir": Json::boolean(d.dir),
    },
    "drive": { "station": Json::string(d.station), "root": Json::string(d.root), "path": Json::string(d.path) },
  }
}

///|
/// What draft `w`'s composer is shaped for (its box's reshape is for a change of it): its files, its quotes (each with
/// a picture or not: `file_pictures`, `quote_pictures`) and its field's words.
fn composer_shapes(w : Writing, quote_pictures : Array[(MediaPicture, Json?)?], file_pictures : Array[String?]) -> String {
  let quote_shapes = w.quotes.get().mapi(fn(i, q) {
    let v = Some(q)
    text(v, "id") + "\u{1}" + text(v, "author") + "\u{1}" + text(v, "text") + "\u{1}" + text(v, "role") +
    (if quote_pictures[i] is Some(_) { "|picture" } else { "|words" })
  }).join("\u{2}")
  let file_shapes = w.files.get().mapi(fn(i, f) {
    text(Some(f), "id") + (if file_pictures[i] is Some(_) { "|picture" } else { "|card" })
  }).join("\u{2}")
  "\{file_shapes}|\{quote_shapes}|" + w.field.text()
}

///|
/// What draft `w`'s composer is shaped for as it is sent (composer_shapes, its pictures as it builds them): what words
/// sent from it hold it shaped for (sfbase's SendFlight `shaped`).
fn composer_shapes_sent(c : @ui.Ctx, src : Source, w : Writing, station : String) -> String {
  composer_shapes(
    w,
    w.quotes.get().map(fn(q) { quote_picture(c, src, w, station, Some(q)) }),
    w.files.get().map(fn(f) { waiting_picture(src, w, Some(f)) }),
  )
}

///|
/// The text field (useComposerText's textarea): 14 on 1.5, growing with the text up to 480 or
/// 40% of the window, then scrolling; with a mouse and nothing focused it says which key brings the cursor back
/// (useSpaceHint); typed, told to the core (and the agent's runtime warmed, once a minute); Enter sends, ⇧Enter starts a
/// line; with nothing typed ↑ / ↓ go to the chat above or below.
fn composer_text(
  c : @ui.Ctx,
  src : Source,
  ws : Workspace,
  spec : ComposerSpec,
  w : Writing,
  cap : Int,
  multiline : Bool,
  hint_in : @motion.Anim,
  submit : () -> Unit,
) -> Int {
  let p = @sf.theme().p
  let prefs = src.topic("prefs", {}).get().value
  let hint = space_hint(c, prefs, spec.locked)
  // (⌘Enter sends, Enter a new line: as chosen in 快捷键)
  let by_command = @settings.sends_by_command(prefs)
  let away = @sfbase.flight_hint_away(c, w.key)
  let held_lines = composer_held_lines(c, spec.draft)
  let no_files = spec.locked || spec.offline
  // what it says while empty changed (the cursor gone from it: the key that brings it back; back in it: what to write)
  // fades out, then the other in where it was, never one put for the other at once
  let wanted = if hint != "" { hint } else { spec.placeholder }
  // (another chat's, or its first: what it says from the first, as it is)
  if composing.hint_shown.get() == "" || composing.switching {
    composing.hint_shown.set(wanted)
  }
  let said_key = "composer/said/" + spec.draft
  let said_fade = @motion.trans(fade=0.0, spec=@motion.tween(@sf.hint_back_ms, ease=Out))
  let said_leave = @motion.trans(fade=0.0, spec=@motion.tween(@sf.hint_back_ms, ease=Leave))
  let said_look = match
    @motion.presence(c, said_key, wanted == composing.hint_shown.get(), enter=said_fade, exit=said_leave) {
    Some(look) => look
    None => {
      composing.hint_shown.set(wanted)
      @motion.presence(c, said_key, true, enter=said_fade, exit=said_leave).unwrap_or(@ui.look(alpha=0.0))
    }
  }
  let said = composing.hint_shown.get()
  // (what moves with the box is the words' own room, not the room round them: their margins in it are other on one
  // line than opened, and moved from where that room showed, the words jumped by the difference as it set out)
  let mut words = -1
  // (what is typed set as its message will set it: the theme's words, the system's size of words applied by the editor)
  let (size, line) = c.style_size(@sf.theme().t.words)
  // (held by words sent from it: as tall as the lines they took, whatever it holds meanwhile)
  let own = if held_lines > 0 {
    text_own.then(@ui.style(min_h=Fixed(held_lines.to_double() * field_line(c))))
  } else {
    text_own
  }
  c.box(style=if multiline { text_open } else { text_shut(c) }, fn() {
    words = c.box(style=own, fn() {
      let res = c.editor(
        composer_field_key,
        placeholder=said,
        words=true,
        font_size=size,
        line~,
        trim=true,
        max_lines=text_lines(c),
        plain=true,
        color=p.text,
        placeholder_color=@sf.alpha(p.subtle, hint_in.get(c) * said_look.alpha),
        caret_color=if away { @sf.alpha(p.accent, 0.0) } else { p.accent },
        enter_sends=@sf.enter_sends(command=by_command),
        command_sends=@sf.command_sends(by_command),
        // (the `@` menu open: ↑ / ↓ choose in it, Enter and Tab pick, as each comes: it takes them, Ctx::on_key; what it
        // does not take is the field's)
        files=!no_files,
        // words pasted at once past the core's bound: a file of their own (Chat.tsx onPaste)
        paste_limit=if no_files || w.starting.get() { 0 } else { @sfbase.paste_threshold(c, src) },
        look=@sfbase.refs_look(w.key, p.accent),
        field=w.field,
        // (each edit of it by the person, as the core reads it, at its moment: a mark taken whole, a chat's link
        // pasted, the `@` words at its caret)
        on_edit=fn(e) { @sfbase.refs_edited(src, w.key, w.field, spec.station, spec.locked, e) },
        // (what is typed told to the core as it is typed, outside the build: the composer built once for it, not again
        // for what telling it set as it was built)
        on_change=fn(words) {
          if words != w.text.get() && !w.starting.get() {
            writing_text(src, w, words)
            composing.typed = true
          }
        },
      )
      match res.pasted {
        Some(words) => @sfbase.writing_paste(src, w, spec.station, words)
        None => ()
      }
      // `@` and a few letters: the chats they find over the composer (Enter picks one there)
      let menu = ref_menu(c, src, spec, w, cap, res.focused)
      match res.submitted {
        // (they stay in the field until they go)
        Some(words) => {
          if words != w.text.get() {
            writing_text(src, w, words)
          }
          submit()
        }
        None =>
          if res.text != w.text.get() && !w.starting.get() {
            writing_text(src, w, res.text)
            warm(c, src, spec)
          } else if composing.typed {
            composing.typed = false
            warm(c, src, spec)
          }
      }
      // nothing typed: ↑ ↓ the chat above or below, as the list shows them now, each as it comes, before the field
      // sees it (Ctx::on_key: what is typed then, whether the chat beside is held then)
      if res.focused && !menu {
        c.on_key(c.focused_id(), fn(code, mods) {
          guard mods == 0 && (code == @ui.key_code_up || code == @ui.key_code_down) else { return false }
          guard w.text.get() == "" && !(@sfbase.neighbour_held.val)() else { return false }
          (@sfbase.neighbour_go.val)(src, ws, if code == @ui.key_code_up { -1 } else { 1 })
          true
        })
      }
    })
  })
  |> ignore
  words
}

///|
/// How far its field's hint (its placeholder) shows: only on a composer at rest without the cursor, so it never moves
/// with the composer's shape. Gone at once as the field takes the cursor (`hidden`: or keeps the box a moment after),
/// and while words sent leave the emptied field, still over it (flight.mbt); back over 200 ms
/// once they are out of it, or, the composer changing `shape` (its box let go to a capsule, a file put in it, `moved`
/// to another page), once it is there (by `going`, the shape's motion).
fn composer_hint(
  c : @ui.Ctx,
  spec : ComposerSpec,
  w : Writing,
  hidden : Bool,
  moved : Bool,
  laid_anew : Bool,
  shape : String,
  going : @motion.Spec,
) -> @motion.Anim {
  let hint = @motion.anim(c, "composer/hint", 1.0)
  // (another chat's draft swapped in is no change of shape, nor the same draft laid out roomy or not by the width it is
  // given (`laid_anew`): it is where it is laid out at once)
  let reshaped = shape != composing.hint_shape &&
    composing.hint_shape != "" &&
    !laid_anew &&
    ("\u{1}" + spec.session == composing.draft_before || moved)
  composing.hint_shape = shape
  if hidden || @sfbase.flight_hint_away(c, w.key) {
    hint.snap(c, 0.0)
  } else if reshaped {
    hint.snap(c, 0.0)
    hint.animate(c, 1.0, @motion.tween(@sf.hint_back_ms, ease=Out, delay=going.duration(0.0, 1.0, 0.0)))
  } else {
    hint.follow(c, 1.0, @motion.tween(@sf.hint_back_ms, ease=Out))
  }
  hint
}

///|
/// What the box says instead of its placeholder with keyboard and mouse and nothing that takes keys focused: that the composer's
/// key puts the cursor there ("" otherwise).
fn space_hint(c : @ui.Ctx, prefs : Json?, locked : Bool) -> String {
  if locked || @sf.soft_keyboard() || c.field_focused() || composing.taking.get() {
    return ""
  }
  match @settings.key_label(prefs, "composer.focus") {
    "" => ""
    key => @sf.t("web-main.composer.pressToTypeCjk", args=[("key", key)])
  }
}

///|
/// Typing starts the agent's runtime, so a cold start overlaps the writing: the first time, then a minute after the last.
fn warm(c : @ui.Ctx, src : Source, spec : ComposerSpec) -> Unit {
  if spec.session == "" || spec.locked || spec.offline || !spec.warm_agent || src.read_only {
    return
  }
  let n = composing.warmed.get(spec.session).unwrap_or(0)
  if n > 0 && !@kit.after(c, "composer/warm/" + spec.session + "/\{n}", true, warm_every_ms, later=true) {
    return
  }
  composing.warmed[spec.session] = n + 1
  c.tell("composer/warm", fn() {
    (src.call)("session.warm", { "station": Json::string(spec.station), "key": Json::string(spec.session) }, @sfbase.answer_unread)
  })
}

///|
/// ＋ (ComposerTools' attach, Chat.css.ts attachBtn: 32 round, the muted ink, the hover's ground and the text's ink
/// pointed at, faint where no file is taken in): the system's file picker; its tip with its keys (composer.file).
fn attach(c : @ui.Ctx, src : Source, spec : ComposerSpec, w : Writing, no_files : Bool) -> Int {
  let p = @sf.theme().p
  let id = c.id("composer/plus")
  let hot = !no_files && c.lit(id)
  if !no_files {
    @sf.tip(c, "composer/plus", id, @sf.t("web-main.composer.attach"), shortcut="composer.file")
    // on a touch system the phone's sheet of what can go in (attach.mbt), with keyboard and mouse the system's picker at once
    c.on_press(id, fn() {
      if @sf.attach_from_sheet() {
        attach_open(id, src, w.key)
      } else {
        pick_files(w)
      }
    })
  }
  ignore(spec)
  // (a finger reaches it from round it, the system's least target: @ui's press_reach)
  let b = c.box(style=if hot { @sf.round_face().then(round_hot) } else { @sf.round_face() }, id~, fn() {
    @sf.icon(c, "plus", size=plus_icon, color=if no_files {
      @sf.alpha(p.text, faint)
    } else if hot {
      p.text
    } else {
      p.muted
    })
    |> ignore
  })
  c.semantics(b, Button, id~, label=@sf.t("web-main.composer.attach"), disabled=no_files)
  b
}

///|
/// Files the system's picker answered for each draft, waiting for its composer (`take_in`).
// kept across runs: cleared by composing_reset
let picked_waiting : Map[String, Array[@hostapi.Picked]] = Map([])

///|
/// Files the system's picker answered for draft `key`, put where its composer takes them (`take_in`) and told (`draft_given`).
fn picked_into(key : String, files : Array[@hostapi.Picked]) -> Unit {
  if files.is_empty() {
    return
  }
  let list = picked_waiting.get(key).unwrap_or([])
  list.push_iter(files.iter())
  picked_waiting[key] = list
  @sfbase.draft_given(key)
}

///|
/// The system's file picker for draft `w`: what is picked wakes its composer as the host's event tells it (`picked_into`).
pub fn pick_files(w : Writing) -> Unit {
  let key = w.key
  @ui.pick(Files, on_got=fn(files) { picked_into(key, files) }) |> ignore
}

///|
/// Send (sendBtn): 32 round, the text's ink with the canvas's arrow while it can go (a step lighter pointed at), the
/// ink faint over the box's ground while not, going from one to the other as a control answers (a button's background
/// over --dur: sent, it fades to faint); a turning ring while a new chat is made for it.
fn send_button(c : @ui.Ctx, ready : Bool, starting : Bool, submit : () -> Unit) -> Int {
  let p = @sf.theme().p
  let id = c.id("composer/send")
  let hot = ready && c.lit(id)
  // (whatever this build saw: submit asks whether it is ready as it is pressed)
  c.on_press(id, fn() { submit() })
  @sf.tip(c, "composer/send", id, @sf.t("web-main.composer.send"))
  // (told as it is built, eased as it is painted: what builds the composer is not built again each frame they go, as
  // its words are sent)
  let able = @motion.told(c, "composer/send/able", if ready { 1.0 } else { 0.0 }, spec=@motion.tween(@sf.dur_ms, ease=Out))
  let lit = @motion.told(c, "composer/send/lit", if hot { 1.0 } else { 0.0 }, spec=@motion.tween(@sf.dur_ms, ease=Out))
  let ground_at = fn(able : Double, lit : Double) {
    let on = @sf.mix(@sf.mix(p.text, send_hot, p.canvas), lit, p.text)
    @sf.mix(on, able, @sf.over(p.raised, @sf.alpha(p.text, send_off)))
  }
  let b = c.box(style=@sf.round_face().then(@ui.style(bg=Data(ground_at(able.target(), lit.target())))), id~, fn() {
    if starting {
      @sf.spinner(c, size=@sf.theme().round.glyph) |> ignore
    } else {
      let arrow = @sf.icon(c, "arrow-up", size=@sf.theme().round.glyph, color=@sf.mix(p.canvas, able.target(), p.raised))
      c.ink_by(arrow, fn() { @sf.mix(p.canvas, able.get(c), p.raised) })
    }
  })
  c.bg_by(b, fn() { ground_at(able.get(c), lit.get(c)) })
  c.semantics(b, Button, id~, label=@sf.t("web-main.composer.send"), disabled=!ready)
  b
}

///|
/// A quote's comment, laid out and drawn the same in the composer and as its card sets out.
fn quote_comment_field(c : @ui.Ctx, key : String, f : @ui.Field, hint? : Bool = true) -> @ui.EditorResult {
  c.editor(
    key,
    placeholder=@sf.t("web-main.quote.commentPlaceholder"),
    font_size=@sf.theme().t.ui,
    line=@sf.theme().t.ui_line,
    max_lines=1,
    plain=true,
    color=@sf.theme().p.text,
    placeholder_color=if hint { @sf.theme().p.subtle } else { 0L },
    caret_color=@sf.theme().p.accent,
    field=f,
  )
}

///|
/// Whether a quote's comment line has the focus, as the composer is built (and as a press then finds it: Ctx::on_press
/// runs before the next build): its quote sent or taken out, the line goes, and with it the focus and the screen's
/// keyboard, so the words' field is given it instead (quote_focus_to_words).
fn quote_has_focus(c : @ui.Ctx, w : Writing) -> Bool {
  w.quotes.get().iter().any(fn(q) { c.editor_focused("composer/quote/" + text(Some(q), "id")) })
}

///|
/// The words' field given the focus a quote's comment line had (`had`: quote_has_focus as it was built).
fn quote_focus_to_words(c : @ui.Ctx, w : Writing, had : Bool) -> Unit {
  if had {
    c.focus_field(w.field)
  }
}

///|
/// What waits to go with the message (ComposerExtras): the quotes, each with a line for what is said about it (the one
/// just added takes the focus; Enter in it goes back to the text), then the files: a picture as its picture, pasted
/// words as their card, a station's file as its card, a link as its card, any other file as its card.
fn composer_extras(c : @ui.Ctx, src : Source, spec : ComposerSpec, w : Writing, holds : String, shape : @motion.Spec, quote_pictures : Array[(MediaPicture, Json?)?], file_pictures : Array[String?], held : Double) -> Unit {
  // The room for what is added is present even when empty, outside the flow then. Its height and position change with
  // the ground; what is new in it grows with it as it opens, whole (held_coming), never cut through by its edge (a
  // picture's foot cut square and faded as it came in, 2026-11-02 the user: 「能看出问题吗」).
  // (held by words sent from it: as tall as what was added was laid out as they were sent, composer_held_extras)
  let empty = w.quotes.get().is_empty() && w.files.get().is_empty() && held <= 0.0
  // (the room, read where it is as what it holds is painted: held_coming)
  let room : Ref[@ui.NodeHeld?] = Ref(None)
  let area = c.box(
    style=extras_room(held),
    left?=if empty { Some(@sf.composer_pad) } else { None },
    top?=if empty { Some(@sf.composer_pad) } else { None },
    fn() { composer_extra_items(c, src, spec, w, holds, shape, quote_pictures, file_pictures, room) },
  )
  room.val = Some(c.node_held(area))
  // (how tall it is laid out: what words sent hold it as, composer_held_extras)
  @motion.measure(c, area, "composer/extras/room")
  @motion.scope(c, area)
  @motion.layout(c, area, "composer/extras", spec=shape, by=holds, cut=false)
}

///|
fn composer_extra_items(c : @ui.Ctx, src : Source, spec : ComposerSpec, w : Writing, holds : String, shape : @motion.Spec, quote_pictures : Array[(MediaPicture, Json?)?], file_pictures : Array[String?], room : Ref[@ui.NodeHeld?]) -> Unit {
  if !w.quotes.get().is_empty() {
    let quote_had = quote_has_focus(c, w)
    c.box(style=quotes_column, fn() {
      for i, q in w.quotes.get() {
        let v = Some(q)
        let id = text(v, "id")
        let key = "composer/quote/" + id
        let f = match composing.comments.get(id) {
          Some(f) => f
          None => {
            let f = @ui.Field::new(text=text(v, "comment"))
            composing.comments[id] = f
            f
          }
        }
        // (the one the core says asks for the focus: none where it says none, a quote of its own with no id among them)
        if w.focus.get() != "" && w.focus.get() == id {
          c.focus_editor(key)
          writing_focused(src, w)
        }
        let item = c.box(style=@ui.css("w=Full"), fn() {
          let card = @sf.quote_card(
            c,
            key,
            text(v, "author"),
            text(v, "text"),
            role=text(v, "role"),
            composer=true,
            on_remove=fn() {
              quote_focus_to_words(c, w, quote_had)
              writing_unquote(src, w, id)
            },
            words_key=quote_words_key(id),
            // its own picture (an image of a message quoted, a mark's screenshot) in its card as a picture waiting is,
            // where it flies from to its place in the message (flying_quotes)
            picture?=quote_pictures[i].map(fn(own) {
              fn() {
                let (picture, f) = own
                let tile = picture_tile(c, picture, going_now(f), gone_up(f), text(f, "error"), going=text(f, "id"))
                @motion.measure_drawn(c, tile, quote_picture_key(id))
                composing.pictures[id] = picture
              }
            }),
            comment_field=fn() {
              let res = quote_comment_field(c, key, f)
              if res.text != text(v, "comment") {
                writing_comment(src, w, id, res.text)
              }
              if res.submitted is Some(_) {
                c.focus_field(w.field)
              }
            },
          )
          // (where it is and its colour: what flies from it as it is sent, flying_quotes)
          @motion.measure_drawn(c, card, quote_card_key(id))
          composing.grounds[id] = c.node_bg(card)
        })
        @motion.layout(c, item, key + "/in", spec=shape, by=holds)
        held_coming(c, item, key, room)
      }
    })
    |> ignore
  }
  // (a quote's picture is its own, not among them)
  if !w.files.get().is_empty() {
    c.box(style=files_flow(), flow=true, line_gap=files_lines(), fn() {
      for n, f in w.files.get() {
        let i = c.box(fn() { composer_file(c, src, spec, w, f, file_pictures[n]) })
        let key = "composer/file/" + text(Some(f), "id")
        @motion.layout(c, i, key + "/in", spec=shape, by=holds)
        @motion.measure_drawn(c, i, key + "/shown")
        held_coming(c, i, key, room)
      }
    })
    |> ignore
  }
}

///|
/// What waits in it (a quote's card, a file's: node `i`, keyed `key`) put in while it shows comes in (`@sf.waiting_in`, the
/// web's enterUp on composerQuote, fileCard and composerThumb), the first frame it is built; what a draft opened with,
/// or the composer gone to another page with, is there at once (sf/motion.mbt: what is on a page does not move of its
/// own as it comes), though said so as it is (built again the frame after, it was there before). Below what the room
/// shows as it opens for it (`room`, composer_extras), it grows with it from its top, as a row coming where it is
/// (@ui.Ctx::held_look's size; faded in by its entrance alone): whole, as far as the room has reached down it.
fn held_coming(c : @ui.Ctx, i : Int, key : String, room : Ref[@ui.NodeHeld?]) -> Unit {
  @motion.entering(c, i, key + "/in", @sf.waiting_in, at_once=!composing.same_draft)
  // (it and its room read where they are as it is painted, not where they were built: what holds them kept as its
  // nodes is put back elsewhere among the frame's as what is built before it makes more nodes or fewer)
  let held = c.node_held(i)
  c.look_by(i, fn() {
    match (@motion.grown_shown(c, "composer/extras"), held.at(), room.val.bind(fn(r) { r.at() })) {
      (Some(shown), Some(i), Some(room)) => {
        let (_, top, _, _) = c.node_rect(room)
        let (_, y, _, h) = c.node_rect(i)
        if h > 0.0 {
          // (seen from the first, as it comes in: its own entrance fades it, not its room)
          { ..c.held_look(i, dclamp((shown - (y - top)) / h, 0.0, 1.0), top=true), alpha: 1.0 }
        } else {
          @ui.still_look
        }
      }
      _ => @ui.still_look
    }
  })
}

///|
/// One file waiting: a picture shown from here (its bytes) or from the station, pasted words, a station's file named
/// by its path or going as a file, a link, or any other file; each with its ✕, a failed one's ↻ where it can go again.
fn composer_file(c : @ui.Ctx, src : Source, spec : ComposerSpec, w : Writing, f : Json, picture : String?) -> Unit {
  let v = Some(f)
  let id = text(v, "id")
  let key = "composer/file/" + id
  let name = text(v, "name")
  match picture {
    Some(picture) => composer_picture(c, src, w, key, id, name, picture, going_now(v), gone_up(v), text(v, "error"))
    None => {
      // as wide as a card is (236), however little the row has: a card hugging its words in a row that wraps had none
      // left for them (its words squeezed to …); its ✕ hung on its corner, as a picture's (@sf.with_corner_remove)
      @sf.with_corner_remove(c, key, remove_label(v, name), @sf.composer_inner(), w=dmin(@sf.file_card_w, c.width), fn() {
        let card = c.id(key)
        waiting_card(c, key, v, restore=restorable(w, v), on_press=fn(on) {
          match (waiting_as(v), on) {
            // a link: tapped, it opens
            (Link, Open) => open_link(text(field(v, "link"), "url"))
            // pasted words: put back as words (its words' field given the focus); failed, made again from them
            (Pasted, Restore) => {
              let back = text(field(v, "pasted"), "text")
              let words = if w.text.get() == "" { back } else { w.text.get() + "\n" + back }
              @sfbase.refs_put(w.key, w.field, words)
              writing_text(src, w, words)
              writing_remove(src, w, id)
              c.focus_field(w.field)
            }
            (Pasted, Retry) => @sfbase.writing_paste_again(src, w, id)
            // a station's file (by its path or as the file): pressed, how it goes (composer_ref.mbt)
            (ByPath | AnyFile, Open) =>
              if field(v, "ref") is Some(Object(_)) {
                ref_panel(src, w, spec.station, id, name, card)
              }
            (ByPath | AnyFile, Retry) => writing_retry(src, w, id)
            _ => ()
          }
        })
      }, on_remove=fn() { writing_remove(src, w, id) })
    }
  }
}

///|
/// A file waiting's picture, if it is drawn as one: the bytes picked or pasted here, else (a draft kept, read again as
/// the app starts) an image's as the device keeps it (`composer.picture`), "" while that is read, or a video's put up
/// here while its first frame is read; None for any other file, and an image the device keeps none of (drawn as a file).
fn waiting_picture(src : Source, w : Writing, v : Json?) -> String? {
  let id = text(v, "id")
  match writing_pictures.get(id) {
    Some(picture) => Some(picture)
    None if file_kind(text(v, "name")) == "image" && waiting_as(v) is AnyFile =>
      match (src.draft_picture)(w.key, id) {
        "!" => None
        kept => Some(kept)
      }
    None if file_kind(text(v, "name")) == "video" && @sfbase.writing_put_here(id) && waiting_as(v) is AnyFile => Some("")
    None => None
  }
}

///|
/// Whether a file waiting is going up now (its tile darkened with a spinner, its card saying how far): not up, not
/// failed, nor a new chat's, which waits for its message (nothing going up yet).
fn going_now(v : Json?) -> Bool {
  field(v, "done") is None && text(v, "error") == "" && field(v, "waits") is None
}

///|
/// What a file waiting that is no picture is drawn as (waiting_card): a station's file named by its path, a link shared
/// in, pasted words, or any other file.
priv enum WaitingAs {
  ByPath
  Link
  Pasted
  AnyFile
}

///|
fn waiting_as(v : Json?) -> WaitingAs {
  let ref_ = field(v, "ref")
  match ref_ {
    Some(Object(_)) if text(ref_, "mode") != "file" => ByPath
    _ if field(v, "link") is Some(Object(_)) => Link
    _ if field(v, "pasted") is Some(Object(_)) => Pasted
    _ => AnyFile
  }
}

///|
/// Whether pasted words waiting can be put back as words (✎ on their card): while they are kept, and no chat is being
/// made for them.
fn restorable(w : Writing, v : Json?) -> Bool {
  field(field(v, "pasted"), "text") is Some(String(_)) && !w.starting.get()
}

///|
/// A file waiting that is no picture, as its card (`key`), its ✕ aside: what the composer draws (composer_file) and
/// what flies from there as it is sent drawn as it was until it sets off (flying_files).
fn waiting_card(c : @ui.Ctx, key : String, v : Json?, restore~ : Bool, on_press? : (@sf.FileCardPress) -> Unit) -> Unit {
  let name = text(v, "name")
  let error = text(v, "error")
  let pending = going_now(v)
  let ref_ = field(v, "ref")
  match waiting_as(v) {
    // named by its path: its station and that it goes as a path, its card the named one's (RefCard)
    ByPath =>
      @sf.file_card(
        c,
        key,
        name,
        number(v, "size"),
        path=text(ref_, "path"),
        dir=field(ref_, "dir") is Some(True),
        named=true,
        meta=text(ref_, "stationName") + " · " + @sf.t("web-main.file.modePath"),
        open=true,
        composer=true,
        on_press?,
      )
    // a link shared in (share-in.ts): its title and its site, drawn as a file is; sent as
    // words, nothing going up
    Link => {
      let l = field(v, "link")
      let url = text(l, "url")
      @sf.file_card(
        c,
        key,
        url,
        0.0,
        // (where it goes, over it while it is pointed at: Chat.tsx LinkCard's tip)
        path=url,
        open=true,
        title=match text(l, "title") {
          "" => url
          t => t
        },
        meta=text(l, "site"),
        composer=true,
        on_press?,
      )
    }
    // pasted words (PendingFile's pasted card): what they begin with, how many, put back as words while not too long
    // (`restore`); failed, made again from them
    Pasted => {
      let info = field(v, "pasted")
      @sf.file_card(
        c,
        key,
        name,
        number(v, "size"),
        pending~,
        error~,
        title=match text(info, "preview") {
          "" => @sf.t("web-main.composer.pastedText")
          first => first
        },
        meta=@sf.t("web-main.composer.pasteAttachment", args=[("count", @sf.grouped(number(info, "characters")))]),
        retry=error != "",
        restore~,
        composer=true,
        on_press?,
      )
    }
    // (a station's folder going as the file: the zip it goes as, RefCard's `${name}.zip`)
    AnyFile => {
      let done = field(v, "done")
      @sf.file_card(
        c,
        key,
        if field(ref_, "dir") is Some(True) { name + ".zip" } else { name },
        number(done, "size") + (if done is None { number(v, "size") } else { 0.0 }),
        pending~,
        sent=match field(v, "sent") {
          Some(Number(n, ..)) => Some(n)
          _ => None
        },
        error~,
        // (a station's file going as the file: how it goes, pressed)
        open=ref_ is Some(Object(_)),
        retry=error != "" && field(v, "pasted") is None,
        composer=true,
        on_press?,
      )
    }
  }
}

///|
/// What a waiting file's ✕ is called: pasted words' their own, a link's or a file's by its name.
fn remove_label(v : Json?, name : String) -> String {
  if field(v, "pasted") is Some(Object(_)) {
    @sf.t("web-main.composer.removePaste")
  } else {
    match field(v, "link") {
      Some(Object(_)) as l => @sf.t("web-main.file.remove", args=[("name", text(l, "url"))])
      _ => @sf.t("web-main.file.remove", args=[("name", name)])
    }
  }
}

///|
/// How much of a waiting file the station has (its `sent` of its size), once it says.
fn gone_up(v : Json?) -> Double? {
  match field(v, "sent") {
    Some(Number(sent, ..)) => Some(sent / dmax(number(v, "size"), 1.0))
    _ => None
  }
}

///|
/// A picture's tile (56): darkened while it goes up, a ring over it filling as it goes (`part`: turning until it says),
/// ↻ over it when it failed (`again` what a tap there is); a video's still a solid play mark in its middle otherwise
/// (told apart from an image's while it waits). Its node; `id` what a tap on it is.
fn picture_tile(
  c : @ui.Ctx,
  picture : MediaPicture,
  pending : Bool,
  part : Double?,
  error : String,
  going? : String = picture.key,
  id? : Int = 0,
  again? : Int = 0,
) -> Int {
  c.box(style=thumb_box().then(if error != "" { thumb_failed } else { thumb_whole }), id~, fn() {
    media_content(c, picture, thumb_side, thumb_side, FitCover, 0.0)
    if pending {
      c.layer(fn() {
        c.box(style=thumb_veil, fn() {
          @sf.progress_spinner(c, "composer/going/" + going, part, size=@sf.theme().round.glyph) |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    if error != "" {
      c.layer(fn() {
        c.box(style=thumb_veil, id=again, fn() { @sf.icon(c, "refresh", size=retry_icon, color=on_veil) |> ignore })
        |> ignore
      })
      |> ignore
    }
    if picture.kind == "video" && !pending && error == "" {
      c.layer(fn() {
        c.box(style=thumb_play, fn() { @sf.icon(c, "play-mark", size=thumb_play_side, color=on_veil) |> ignore }) |> ignore
      })
      |> ignore
    }
  })
}

///|
/// A picture waiting (composerThumb): its own picture from here, a ring over it filling while it goes up (`part`),
/// red-edged when it failed (↻ over it); its ✕ on its corner (@sf.with_corner_remove); its name its tip.
fn composer_picture(
  c : @ui.Ctx,
  src : Source,
  w : Writing,
  key : String,
  id : String,
  name : String,
  picture : String,
  pending : Bool,
  part : Double?,
  error : String,
) -> Unit {
  let thumb = c.id(key)
  let again = c.id(key + "/retry")
  @sf.tip(c, key + "/tip", thumb, if error != "" { error } else { name })
  // (its picture's box, its ✕ hung on its corner as every waiting file's)
  let tile = Ref(-1)
  @sf.with_corner_remove(c, key, @sf.t("web-main.file.remove", args=[("name", name)]), @sf.composer_inner(), w=thumb_side, fn() {
    tile.val = picture_tile(c, local_media(picture, file_kind(name)), pending, part, error, going=id, id=thumb, again~)
  }, on_remove=fn() { writing_remove(src, w, id) })
  if error != "" {
    c.on_press(again, fn() {
      writing_retry(src, w, id)
    })
  }
  // tapped, it opens in the viewer, growing out of its tile, from the bytes picked (`draft:<id>`, no session's: nothing
  // to mark it into, it is in the draft already); one whose bytes are not here (a draft kept) opens nothing
  match @sfbase.writing_went_to(id) {
    Some((station, _, bytes)) => {
      let a : Attachment = {
        name,
        path: "draft:" + id,
        size: bytes.length().to_double(),
        width: 0.0,
        height: 0.0,
        thumbhash: "",
        owner: "",
        upload: "",
        duration: 0.0,
        frames: 0,
        held: false,
      }
      // the viewer's id of it (its station, no session, its path), its tile kept for it to fly from
      let seen = station + "//" + a.path
      c.on_press(thumb, fn() {
        @sfbase.keep_read(seen, bytes)
        @sfbase.open_preview(station, "", a)
      })
      @sfbase.note_thumb(c, seen, tile.val, @sf.composer_inner(), picture~)
      // (not drawn while the viewer is its picture: one picture on the screen, never two)
      c.look(tile.val, @ui.look(alpha=@sfbase.thumb_shows(seen)))
    }
    None => ()
  }
}

///|
/// How long it stays a box after it loses the cursor (LET_GO_MS); how long its change of shape takes.
pub let let_go_ms : Double = 300.0

///|
/// Typing warms the agent's runtime at most once a minute.
let warm_every_ms : Double = 60000.0

///|
/// The words' size and line are the theme's (Type.input: the screen's), the most it grows to (480, or 40% of the window).
let text_most : Double = 480.0

///|
let text_window_share : Double = 0.4

///|
/// How many lines the field grows to before it scrolls: as many of its lines as are as tall as it grows to at most.
fn text_lines(c : @ui.Ctx) -> Int {
  let n = (dmin(text_most, c.height * text_window_share) / field_line(c)).to_int()
  if n < 1 {
    1
  } else {
    n
  }
}

///|

///|
/// ＋'s icon (Plus 18; send's is the theme's round glyph) and a picture's ↻ (18).
let plus_icon : Double = 18.0

///|
let retry_icon : Double = 18.0

///|
/// What is faint where it cannot be pressed (attachBtn :disabled: .4); send not ready: the text at 18% over the box's
/// ground; pointed at, the text at 82% over the canvas.
let faint : Double = 0.4

///|
let send_off : Double = 0.18

///|
let send_hot : Double = 0.82

///|
/// Dragged over (composerBox[data-dragging]): the focus ring's colour at 8% over its ground.
let drag_tint : Double = 0.08

///|
/// A picture waiting (composerThumb): 56 square; what is said on its veil, white.
let thumb_side : Double = 56.0

///|
let on_veil : Int64 = 0xFFFFFFFFL

///|
/// A video waiting: its solid play mark, white, in its tile's middle.
let thumb_play_side : Double = 24.0

///|
// kept across runs: a value (no field of it changes)
let thumb_play : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
/// The capsule (composerBox, one line): its parts on its centre line, 2 apart, its round buttons its padding in all round
/// (ComposerPlace's capsule_pad), a pill as high as that makes it.
// kept across runs: a value (no field of it changes)
let composer_box : @ui.Style = @ui.css("row w=Full gap=SPx radius=InnerOr(Full) align=ACenter")

///|
/// How far in the capsule's round buttons stand (the theme's: keyboard and mouse's 32, a finger's 36) alone: 8.
let capsule_pad_alone : Double = 8.0

///|
/// How high the capsule is: its round buttons capsule_pad_alone in; in a panel's foot corners too square for that to
/// stand concentric in them, as high as does (@sf.foot_capsule_h: a finger's 52 in the tape's 28, 48), so it stands
/// where its ends are concentric with them as high as it is (the user, 2026-10-26: a finger's, 52 high, stood where a 48
/// would, its ends not on the page's corners).
fn capsule_h(c : @ui.Ctx) -> Double {
  let side = @sf.theme().round.side
  @sf.foot_capsule_h(side + 2.0 * (capsule_pad_alone + capsule_extra(c)), side)
}

///|
/// How much further in its round buttons stand than its padding says (ComposerPlace's capsule_pad), every way: half
/// what its text's line is taller than they are, the system's size of words as the user's (text_shut: as high as
/// they are, else as its line), so that they stand as far in at their ends as over and under them, concentric with it;
/// none while its line is no taller than they are.
fn capsule_extra(c : @ui.Ctx) -> Double {
  dmax(0.0, (field_line(c) - @sf.theme().round.side) / 2.0)
}

///|
/// The line the composer's field is laid out on: the theme's words' line (Ctx::style_size) at the system's size of
/// words, as Ctx::editor takes the line it is given (Ctx::sp: at 1.3, 22 is 25). What is worked out of its lines (how
/// tall it is opened, how many it grows to) is worked out of this one, not the theme's.
fn field_line(c : @ui.Ctx) -> Double {
  c.sp(c.style_size(@sf.theme().t.words).1)
}

///|
/// The capsule further in than the box by `place`'s capsule_in (composer's), from its left, its right and its foot, its
/// round buttons its capsule_pad in.
fn capsule_place(c : @ui.Ctx, place : ComposerPlace) -> @ui.Style {
  let (l, r, b) = place.capsule_in
  // (over and under, its padding: its text's room, as high as its line, stands its buttons in its middle that much
  // further in, capsule_extra; at its ends that much more, so they stand as far in every way)
  let pad = place.capsule_pad
  @ui.style(
    ml=@sf.room_of(l),
    mr=@sf.room_of(r),
    mb=@sf.room_of(b),
    px=@sf.room_of(pad + capsule_extra(c)),
    py=@sf.room_of(pad),
  )
}

///|
/// Where the composer stands at a panel's foot (composer_place): how much further in than its box (composer_side) its
/// capsule stands from the panel's left, its right and its foot, and how far in its round buttons stand in it (as high
/// as it is there: capsule_h). Its box, opened, is as far in as makes it concentric with a panel's foot corner
/// (@sf.pane_foot_in), its `corner` what that makes it (@sf.pane_composer_corner), a card's alone.
pub(all) struct ComposerPlace {
  capsule_in : (Double, Double, Double)
  capsule_pad : Double
  corner : Double
}

///|
/// Standing in no panel's corners (ComposerPlace).
// kept across runs: a value (no field of it changes)
pub let composer_alone : ComposerPlace = {
  capsule_in: (0.0, 0.0, 0.0),
  capsule_pad: capsule_pad_alone,
  corner: @sf.card_corner,
}

///|
/// Where the composer stands at a panel's foot (`pane` wide): in a panel of its own (@sf.pane_round) whose foot corners
/// it reaches (as wide as the panel leaves it: composer_width), its capsule's ends each as far in as makes it
/// concentric with the corner it is in, an end that cannot the ladder's inset in, as it stands alone
/// (@sf.foot_capsule); else as it stands alone (composer_alone).
pub fn composer_place(c : @ui.Ctx, pane : Double) -> ComposerPlace {
  let d = composer_side()
  if !@sf.in_pane() || composer_width(pane) < pane - 2.0 * d - 0.5 {
    return composer_alone
  }
  let h = capsule_h(c)
  let (l, r, b) = @sf.foot_capsule(h, d, d)
  {
    capsule_in: (l - d, r - d, b - d),
    capsule_pad: (h - @sf.theme().round.side) / 2.0 - capsule_extra(c),
    corner: @sf.pane_composer_corner(),
  }
}

///|
/// The box (composerBox[data-multiline]): a column its padding in (@sf.composer_pad: its buttons round in its corners
/// concentric with it), its parts 10 apart, all four corners alike: alone a card's of the ladder's; where it stands in
/// a panel's foot corners (@sf.pane_foot_in) concentric with them (@sf.composer_corner: the tape's 28, 24.8); in a
/// corner it would follow only in some of its corners (a phone's screen's, a Mac window's at a panel's foot), that one
/// too (InnerOr: corners not alike are a design's, said).
fn composer_box_open() -> @ui.Style {
  composer_box_open_base.then(@ui.style(radius=InnerOr(@sf.composer_radius())))
}

///|
// kept across runs: a value (no field of it changes)
let composer_box_open_base : @ui.Style = @ui.style(w=Full, p=@sf.composer_pad_room, gap=S2_5)

///|
/// The text's room (composerText) on one line: 8 at its end, as high as the capsule's round buttons, its line in its
/// middle (5 over and under at the theme's line; less as the system's size of words grows it, so that the buttons stand
/// as far in over and under as at their ends, concentric with the capsule, not pushed in by a taller line; a line
/// taller than they are, as tall as it); opened, 8 in and 8 over (text_open).
fn text_shut(c : @ui.Ctx) -> @ui.Style {
  @ui.style(w=@sf.grow, h=Fixed(dmax(@sf.theme().round.side, field_line(c))), pr=S2, justify=JCenter)
}

///|
// kept across runs: a value (no field of it changes)
let text_open : @ui.Style = @ui.css("w=Full px=S2 pt=S2")

///|
/// The words' own room in it (composer_text): as wide as what is round them, what moves as the box changes shape.
// kept across runs: a value (no field of it changes)
let text_own : @ui.Style = @ui.css("w=Full")

///|
/// How wide the composer opened sets what is typed in it, at the foot of a pane `pane` wide (its box less its padding
/// and its words' room's sides: text_open's px=S2): where what the viewer sent breaks its lines too (its bubble's,
/// message.mbt mine_most).
pub fn composer_words_width(pane : Double) -> Double {
  composer_width(pane) - 2.0 * @sf.composer_pad - 2.0 * 8.0
}

///|
/// Its row under the text (composerToolbar, multiline: space-between, 4 apart), its ＋ and send round in the box's foot
/// corners, concentric with its card's corner (@sf.composer_round_in, 外圆角 = 距离 + 半高), what stands over them (a
/// quote, a file) the ladder's inset in (the theme's round controls: a finger's larger).
fn tools_row() -> @ui.Style {
  let d = @sf.room_of(@sf.composer_round_in() - @sf.composer_pad)
  tools_row_base.then(@ui.style(ml=d, mr=d, mb=d))
}

///|
// kept across runs: a value (no field of it changes)
let tools_row_base : @ui.Style = @ui.css("row w=Full gap=S1 align=ACenter")

///|
/// The page's choices (composerChoices: in what is left of the row, at its start).
// kept across runs: a value (no field of it changes)
let choices : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S1, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let tools_gap : @ui.Style = @ui.style(w=@sf.grow)

///|
/// What stands before send and send (the spec's `tail` and `note`), as far apart in either shape: as the composer
/// changes shape what it says goes with send, never closer to it or further.
// kept across runs: a value (no field of it changes)
let tail_row : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let tail_box : @ui.Style = @ui.css("row align=ACenter")

///|
/// What the composer says before send (the spec's `note`), its node; -1 when it says nothing.
fn composer_note(c : @ui.Ctx, note : Array[(String, String)]) -> Int {
  if note.is_empty() {
    -1
  } else {
    c.box(style=cc_note_box, fn() { cc_places(c, note) })
  }
}

///|
/// ＋ pointed at: the hover's ground (round as the theme's round controls are: @sf.round_face).
// kept across runs: a value (no field of it changes)
let round_hot : @ui.Style = @ui.css("bg=Hover")


///|
/// The quotes waiting, 6 apart.
// kept across runs: a value (no field of it changes)
let extras_column : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
/// Where what waits stands (extras_column): in from the padding where the box is too round for it there
/// (@sf.composer_waiting_in), at least `held` tall.
fn extras_room(held : Double) -> @ui.Style {
  let d = @sf.composer_waiting_in()
  let base = if d > 0.0 {
    let r = @sf.room_of(d)
    extras_column.then(@ui.style(pl=r, pr=r, pt=r))
  } else {
    extras_column
  }
  if held > 0.0 {
    base.then(@ui.style(min_h=Fixed(held)))
  } else {
    base
  }
}

///|
// kept across runs: a value (no field of it changes)
let quotes_column : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
/// The files waiting (composerFiles: wrapped, 6 apart, flush with the box's padding); its lines further apart by the
/// reach of a ✕ above what it is hung on (@sf.with_corner_remove), so one on a later line keeps 6 from the line over it.
/// Over the words, at the top of the box: their lines end short of its top right corner (@sf.composer_files_end), so
/// the last of the first one never stands in it off its circle, however wide the box is.
fn files_flow() -> @ui.Style {
  @ui.style(row=true, w=Full, gap=S1_5, pr=@sf.room_of(@sf.composer_files_end() - @sf.composer_waiting_in()))
}

///|
fn files_lines() -> Double {
  @ui.Space::px(S1_5) + @sf.corner_remove_reach(@sf.composer_inner())
}

///|
/// A picture waiting: 56 square, as round as what waits in the composer is (@sf.composer_inner: its corners' next step
/// in, every one alike, the first in its corner concentric with it), clipped; failed, edged red.
fn thumb_box() -> @ui.Style {
  @ui.style(w=S14, h=S14, radius=@sf.composer_inner_radius(), clip=true)
}

///|
// kept across runs: a value (no field of it changes)
let thumb_whole : @ui.Style = @ui.css("")

///|
// kept across runs: a value (no field of it changes)
let thumb_failed : @ui.Style = @ui.css("border=B2 border_color=Danger")

///|
/// Over a picture going up or failed: the ink's veil, what it says in its middle.
// kept across runs: a value (no field of it changes)
let thumb_veil : @ui.Style = @ui.css("w=Full h=Full bg=Veil align=ACenter justify=JCenter")

///|
/// What went wrong (chatError: under the box, 32 in, 10 under it; fieldError's red).
// kept across runs: a value (no field of it changes)
let error_box : @ui.Style = @ui.css("w=Full px=S8 pt=S1 pb=S2_5")

///|
// kept across runs: a value (no field of it changes)
let composer_error_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Danger, leading=L5)

///|
/// The files of a draft still going up as it is sent (composer.ts take's `uploads`: neither up nor failed, nor a link
/// or a file named by its path, which go as words), its quotes' own pictures among them.
fn going_files(w : Writing) -> Array[Json] {
  @sfbase.writing_files(w).filter(fn(f) {
    let v = Some(f)
    field(v, "done") is None &&
    text(v, "error") == "" &&
    field(v, "link") is None &&
    text(field(v, "ref"), "mode") != "path"
  })
}

///|
/// The files of a draft that are up, as its message has them (its quotes' own pictures among them): one put up from
/// here naming its upload (`upload`), as the core's row does (file_key).
fn up_files(w : Writing) -> Array[Json] {
  @sfbase.writing_files(w).filter_map(fn(f) {
    match field(Some(f), "done") {
      Some(Object(done)) if @sfbase.writing_put_here(text(Some(f), "id")) => {
        let a = done.copy()
        a["upload"] = Json::string(text(Some(f), "id"))
        Some(Json::object(a))
      }
      done => done
    }
  })
}

///|
/// The pictures the composer is showing go with its message, including those read back from a kept draft. Remember each
/// by its upload and, once up, by the station's path, so the local and core rows both draw the same picture.
fn remember_sent_pictures(src : Source, w : Writing, station : String) -> Unit {
  let remember = fn(v : Json?, picture : String) {
    if picture == "" || picture == "!" { return }
    let id = text(v, "id")
    if id != "" {
      @sfbase.sent_picture_kept("upload\u{1}" + id, picture)
    }
    let path = text(field(v, "done"), "path")
    if station != "" && path != "" {
      @sfbase.sent_picture_kept(@sfbase.sent_key(station, path), picture)
    }
  }
  for file in w.files.get() {
    let v = Some(file)
    remember(v, waiting_picture(src, w, v).unwrap_or(""))
  }
  for q in w.quotes.get() {
    let v = Some(q)
    // A station's picture already has the same source in both places. Calling it a local one would make its reveal
    // stop halfway when the message takes over. Only carry pictures this device supplied itself.
    match composing.pictures.get(text(v, "id")) {
      Some(p) if p.sent => remember(field(v, "own"), p.key)
      _ => ()
    }
  }
}

///|
/// The files of a draft that are up, and its images and videos still going up (drawn where they land from their
/// pictures here: sent_local), flying as it is sent to what each is in its message (file_key: one put up from here, or
/// still going up, its upload; any other its path), each from its tile: from where its card or
/// its picture is (its box's, keyed composer/file/<id>), drawn there as the composer draws it until it sets off.
fn flying_files(c : @ui.Ctx, src : Source, w : Writing) -> Array[FlyingFile] {
  let going = going_files(w).map(fn(f) { text(Some(f), "id") })
  w.files.get().filter_map(fn(f) {
    let v = Some(f)
    let id = text(v, "id")
    let picture = waiting_picture(src, w, v)
    let key = flying_key(v, going.contains(id), picture is Some(_))
    match c.rect_of(c.id("composer/file/" + id)) {
      Some((x, y, wide, high)) if key != "" => {
        let restore = restorable(w, v)
        // The tile is inside a moving composer: take it from where that held it on screen, not its final layout, as big
        // as it showed there (grown with its room as it came in, held_coming).
        let item = "composer/file/" + id + "/shown"
        let from = match (@motion.measured_rect(c, item), @motion.measured_drawn_state(c, item).map(fn(s) { s.grown })) {
          (Some((lx, ly, lw, _)), Some((sx, sy, sw, _))) => {
            let k = if lw > 0.0 { sw / lw } else { 1.0 }
            (sx + (x - lx) * k, sy + (y - ly) * k, wide * k, high * k)
          }
          _ => (x, y, wide, high)
        }
        Some({
          key,
          from,
          shown: @motion.measured_drawn_state(c, item),
          picture,
          paint: None,
          // as the composer drew it (composer_file), but its ✕: a new chat's picture waiting for its message not going
          // up, no spinner over it; a card on the composer's ground, as wide as there
          face: fn(c) {
            match picture {
              Some(p) => {
                let shown = writing_pictures.get(id).unwrap_or(p)
                picture_tile(c, local_media(shown, file_kind(text(v, "name"))), going_now(v), gone_up(v), text(v, "error"), going=id) |> ignore
              }
              None => {
                c.box(style=@ui.style(w=Fixed(wide)), fn() { waiting_card(c, "flying/" + id, v, restore~) })
                |> ignore
              }
            }
          },
          ground: 0L,
          leaving: None,
          quote_words: None,
          quote_to: None,
        })
      }
      _ => None
    }
  })
}

///|
/// The quotes of a draft as its message has them (composer.ts sentQuote): what is said about each trimmed, its own
/// picture named as its file goes.
fn sent_quotes(w : Writing) -> Array[Json] {
  w.quotes.get().map(fn(q) {
    let v = Some(q)
    let own = field(v, "own")
    let file = match field(own, "done") {
      Some(done) if text(Some(done), "name") != "" => text(Some(done), "name")
      _ => text(own, "name")
    }
    Json::object({
      "author": Json::string(text(v, "author")),
      "text": Json::string(text(v, "text")),
      "comment": Json::string(text(v, "comment").trim(chars=" \n\t").to_owned()),
      "ts": Json::string(text(v, "ts")),
      "role": Json::string(text(v, "role")),
      "file": Json::string(file),
    })
  })
}

///|
/// Where quote `id` waiting in the composer is (composer_extras).
fn quote_card_key(id : String) -> String {
  "composer/quote-card/" + id
}

///|
/// Where quote `id`'s own picture is in its card in the composer (composer_extras).
fn quote_picture_key(id : String) -> String {
  "composer/quote-picture/" + id
}

///|
/// The quote's words as laid out in its card, before it is sent.
fn quote_words_key(id : String) -> String {
  "composer/quote-words/" + id
}

///|
/// A quote's own picture, if it is an image or a video (Chat.tsx QuotedThumb, PendingFile), and its file: the picture
/// from here while it is this device's (a mark's screenshot), else the station's (an image of a message quoted; a
/// video's still, as its message draws it: what grows from here to its box there as it is sent, flight.mbt).
fn quote_picture(c : @ui.Ctx, src : Source, w : Writing, station : String, q : Json?) -> (MediaPicture, Json?)? {
  let own = field(q, "own")
  let kind = file_kind(text(own, "name"))
  guard own is Some(_) && (kind == "image" || kind == "video") else { return None }
  match writing_pictures.get(text(own, "id")) {
    Some(picture) => Some((local_media(picture, kind), own))
    None => {
      let done = field(own, "done")
      match done {
        Some(j) => {
          let a = attachment_of(j)
          let owner = text(done, "owner")
          if owner != "" || sent_picture(station, a) is Some(_) {
            return Some((message_media(c, src, station, owner, a), own))
          }
        }
        None => ()
      }
      waiting_picture(src, w, own).map(fn(picture) { (local_media(picture, kind), own) })
    }
  }
}

///|
/// What a file waiting is in the message it goes with (file_key: one put up from here, or one with its picture here
/// still going up (`going`: an image, a video), its upload; any other its path), "" none.
fn flying_key(v : Json?, going : Bool, pictured : Bool) -> String {
  let id = text(v, "id")
  match field(v, "done") {
    Some(_) if @sfbase.writing_put_here(id) => @sfbase.upload_path(id)
    Some(done) => text(Some(done), "path")
    None if going && pictured => @sfbase.upload_path(id)
    None => ""
  }
}

///|
/// The quotes of a draft, flying as it is sent to their cards in its message (quote_key: each by its place among
/// them), each from its card here (where it is, its colour: what its ground sets out from), drawn there as it was, what
/// is said about it as written, until it sets off; its own picture from its tile in the card to its place in the
/// message's card, as a picture sent goes (flight_files).
fn flying_quotes(c : @ui.Ctx, src : Source, w : Writing, station : String) -> Array[FlyingFile] {
  let flying : Array[FlyingFile] = []
  let going = going_files(w).map(fn(f) { text(Some(f), "id") })
  for i, q in sent_quotes(w) {
    let v = Some(w.quotes.get()[i])
    let id = text(v, "id")
    let own = field(v, "own")
    let picture = match (own, composing.pictures.get(id), @motion.measured_drawn_state(c, quote_picture_key(id))) {
      (Some(_), Some(picture), Some(shown)) => {
        let key = flying_key(own, going.contains(text(own, "id")), true)
        if key != "" {
          Some((@sfbase.quote_picture_key(i), picture, shown))
        } else {
          None
        }
      }
      _ => None
    }
    match @motion.measured_drawn_state(c, quote_card_key(id)) {
      Some(shown) => {
        let (x, y, wide, high) = shown.rect
        let (dx, dy) = match @motion.measured_rect(c, quote_card_key(id)) {
          Some((lx, ly, _, _)) => (x - lx, y - ly)
          None => (0.0, 0.0)
        }
        let s = @sfbase.quote_of(q)
        let written = text(v, "comment")
        let copy = @ui.Field::new(text=written)
        let words_width = match c.words_shape_of(quote_words_key(id)) {
          Some(words) if words.pieces.length() == 1 => Some(words.pieces[0].w)
          _ => None
        }
        let quote_words = words_width.map(fn(width) { ("flight/quote-words/" + id, width) })
        // An empty field's hint belongs to the composer alone: carry it from where it was and let it leave with the ✕.
        let leaving = if written == "" {
          match composing.comments.get(id).bind(fn(f) { f.words_at() }) {
            Some((_, (lx, ly, lw, lh))) if lw > 0.0 && lh > 0.0 => {
              let hint_field = @ui.Field::new()
              Some(((lx + dx, ly + dy, lw, lh), fn(c) {
                quote_comment_field(c, "flying/quote-hint/" + id, hint_field) |> ignore
              }))
            }
            _ => None
          }
        } else {
          None
        }
        flying.push({
          key: @sfbase.quote_key(i),
          from: (x, y, wide, high),
          shown: Some(shown),
          picture: None,
          paint: None,
          face: fn(c) {
            c.box(style=@ui.style(w=Fixed(wide)), fn() {
              @sf.quote_card(
                c,
                "flying/quote/" + id,
                s.author,
                s.text,
                role=s.role,
                composer=true,
                words_width?=words_width,
                // (its picture's room: the picture is drawn there flying, over the card)
                picture?=picture.map(fn(p) {
                  let (_, _, pw, ph) = p.2.rect
                  fn() { c.box(style=@ui.style(w=Fixed(pw), h=Fixed(ph)), fn() {  }) |> ignore }
                }),
                comment_field=fn() {
                  quote_comment_field(c, "flying/quote-comment/" + id, copy, hint=leaving is None) |> ignore
                },
              )
              |> ignore
            })
            |> ignore
          },
          ground: composing.grounds.get(id).unwrap_or(0L),
          leaving,
          quote_words,
          quote_to: None,
        })
      }
      None => ()
    }
    match (own, picture) {
      (Some(f), Some((key, picture, shown))) =>
        flying.push({
          key,
          from: shown.rect,
          shown: Some(shown),
          picture: Some(picture.key),
          paint: None,
          face: fn(c) {
            // The row may still be on its way. Follow the same source as the quote, including a cover that arrives
            // while it waits; a picture already shown does not go back to an empty source when the draft is taken.
            let latest = quote_picture(c, src, w, station, v).map(fn(p) { p.0 }).unwrap_or(picture)
            let shown = if latest.key == "" && picture.key != "" { picture } else { latest }
            picture_tile(c, shown, going_now(Some(f)), gone_up(Some(f)), text(Some(f), "error"), going=text(Some(f), "id")) |> ignore
          },
          ground: 0L,
          leaving: None,
          quote_words: None,
          quote_to: None,
        })
      _ => ()
    }
  }
  flying
}

///|
/// What is written sent into chat `r` (`v` its view: its thread, what is in it now; sendDraft): in the
/// list and flying there in the frame it is sent, before the core has it (sent_local: the rule), the composer empty at
/// once; then what the core took (`composer.take`: the words with the links and the paths after them, the files up,
/// the quotes, those still going up as it took them, which it waits for) goes (`chat.send`). Not taken in at all (the
/// core refused it, or went away with it): back in the composer unless something new is written there, saying why; one
/// the station did not take waits in the outbox, which says so.
pub fn send_in_chat(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView, w : Writing) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  // sent, felt as a key's light tap (a no as something refused)
  @ui.haptic(KeyboardTap)
  let words = w.text.get().trim(chars=" \n\t").to_owned()
  let rk = r.station + "\u{1}" + r.session
  remember_sent_pictures(src, w, r.station)
  // (its references as the field's marks, which its flight takes off as; its row's runs as the core read its words)
  let marks = @sfbase.refs_sent_marks(w.key, words)
  let runs = @sfbase.refs_sent_runs(w.key, words)
  let row = sent_local(rk, Some(v), words, up_files(w), going=going_files(w), quotes=sent_quotes(w), runs~, now=(src.now)())
  // its words take off from the field as they are (before it is emptied), the composer held as it is laid out for them
  // till they let go of it (theirs: composer_held_lines); on its way to another shape (a line more just typed), it
  // slows to rest from as fast as it went as they are sent (composer_view's @motion.stop_for), its room with it
  let room = composer_room(c, w.key)
  // its quotes fly too, each from its card, and its files that are up, each from its tile
  let flying = flying_quotes(c, src, w, r.station) + flying_files(c, src, w)
  @sfbase.flight_start(
    c,
    w.key,
    rk,
    row,
    words,
    room,
    flying,
    field=w.field,
    shaped=composer_shapes_sent(c, src, w, r.station),
    // (the list's foot drawn over where it comes to stand: the composer's ground on its way, its room at its target)
    foot_lift=fn(c) { composer_room(c, w.key) - composer_room(c, w.key, settled=true) },
    desk=true,
    marks~,
    runs~,
  )
  // At the end, the new row and its neighbours move together with the flight. When reading above it, glide there
  // instead of putting the list at the end in a single frame.
  let list = "chat/" + r.station + "/" + r.session
  let above = c.list_info_as(list, fn(i) { i.map(fn(v) { v.at_end }) }).map(fn(i) { !i.at_end }).unwrap_or(false)
  c.list_to_end(list, glide=@sfbase.flight_of(w.key) is None || above)
  @sfbase.chat_latest(c, src, r, v, @sf.t("web-main.chat.toLatest"))
  writing_take(src, w, fn(taken) {
    guard taken is Some(_) else {
      sent_local_gone(rk, row)
      return
    }
    let params : Map[String, Json] = {
      "station": Json::string(r.station),
      "text": Json::string(text(taken, "text")),
      "attachments": Json::array(items(taken, "attachments")),
      "quotes": Json::array(items(taken, "quotes")),
    }
    let going = items(taken, "uploads")
    if going.length() > 0 {
      params["uploads"] = Json::array(going)
    }
    match v.thread {
      Some(th) => params["thread"] = Json::number(th)
      None => params["session"] = Json::string(r.session)
    }
    (src.call)("chat.send", Json::object(params), fn(res) {
      match res {
        Err(e) => {
          sent_local_gone(rk, row)
          @ui.haptic(Reject)
          let why = @sf.t("web-main.draft.notSent", args=[("error", text(Some(e), "message"))])
          match text(Some(e), "code") {
            "invalid_params" | "core_restarted" | "closed" => writing_restore(src, w, why, unless_written=true)
            _ => toast_later(why)
          }
        }
        Ok(_) => ()
      }
    })
  })
}

///|
/// The least room a chat's composer takes at its page's foot: as tall as it takes opened with one line where it is
/// (its box that tall, what is round it as it is), draft `draft`'s with its own corner (a card's till it is first built).
fn composer_least(c : @ui.Ctx, draft : String) -> Double {
  let corner = composing.corners.get(draft).unwrap_or(@sf.card_corner)
  let foot = @motion.measured(c, "composer/foot").unwrap_or(capsule_room(c, c.width))
  match @motion.measured(c, "composer/content") {
    // (its foot round its box, both measured of the same composer: a foot shorter than the box holds them measured of
    // two, the box a new chat's in its pane's middle, many lines tall, the foot a chat's from before or none yet; that
    // way round the room came out under 0, a chat's rows over it a height under 0, and the app stopped on the frame a
    // new chat became its chat, laid out Medium (0.1.8569: newchat_send_wbtest's unfolded))
    Some(box) if foot >= box => foot - box + composer_open_box(c, corner~)
    _ => composer_open_room(c, c.width, corner~)
  }
}


///|
/// How long the composer takes to open from a capsule or to be let go to one: its field passing by its ＋ and send is
/// kept off them on this clock (composer_hint_wbtest).
pub let composer_shape_ms : Double = 300.0

///|
/// Whether the composer opens or is let go at this moment: `head` (how roomy, a box or not) changed at it, from what
/// it was as last built (each build and frame at that moment alike).
fn composer_opening(c : @ui.Ctx, head : String) -> Bool {
  let (_, _, now) = composing.opened
  if head != now {
    composing.opened = (c.moment(), now, head)
  }
  let (at, was, _) = composing.opened
  at == c.moment() && was != "" && was != head
}

///|
/// The chat the composer was for before it was switched to the one it is for now, at this moment; else the one it is
/// for (as last built).
fn composer_was(c : @ui.Ctx) -> String {
  let (at, was) = composing.draft_was
  if at == c.moment() {
    was
  } else {
    composing.draft
  }
}

///|
/// Whether draft `draft`'s composer is let go by words sent from it now (sfbase's flight_lets_go: from as they let go
/// of it till it is down, its declared end), its ground going down with its room.
fn composer_let_go(c : @ui.Ctx, draft : String) -> Bool {
  match @sfbase.flight_lets_go(draft) {
    Some((at, ms)) => {
      // (built again as it is let go and as it is down, in the first frames drawn at or past those moments: their way is
      // drawn each frame meanwhile)
      if c.moment() < at {
        c.shows_from(at)
      } else if c.moment() < at + ms {
        c.shows_from(at + ms)
      }
      c.moment() >= at && c.moment() < at + ms
    }
    None => false
  }
}

///|
/// The room under a chat's list for draft `draft`'s composer, `room` as its page has it (composer_room's): let go by
/// words sent from it, where it comes to stand (its target, as it is laid out), the list's foot going there on the
/// list's way as they leave it, one move with their row (sfbase's shown_rows, which says when: `let_go`); else as
/// it is.
pub fn composer_foot_room(c : @ui.Ctx, draft : String, room : Double, let_go~ : Bool) -> Double {
  if let_go {
    ignore(room)
    composer_room(c, draft, settled=true)
  } else {
    room
  }
}

///|
/// Whether draft `draft`'s composer has nothing in its field (none typed since what was sent from it).
fn composing_field_empty(draft : String) -> Bool {
  let (was, empty) = composing.emptied
  was != draft || empty
}

///|
/// How long draft `draft`'s composer takes to come down as words sent let go of it, as their way said it, the same as
/// their row's opening and the list's way then (sfbase's flight_lets_go, shown_rows).
fn composer_down_ms(draft : String) -> Double {
  match @sfbase.flight_lets_go(draft) {
    Some((_, ms)) => ms
    None => @sfbase.sent_down_ms
  }
}

///|
/// When words sent from draft `draft`'s composer let go of it, as their way said it (flight_lets_go; +inf: not said).
fn composer_released_at(draft : String) -> Double {
  match @sfbase.flight_lets_go(draft) {
    Some((at, _)) => at
    None => @double.infinity
  }
}

///|
/// Whether words sent from draft `draft`'s composer hold its room (from as they are sent till it is down, as their way
/// said: flight_lets_go): its room theirs, the list's foot under the rows on the list's way with their row, not on its
/// ground's as that reshapes (sfpages chat_list's `on_foot_way`).
fn composer_held(c : @ui.Ctx, draft : String) -> Bool {
  match (@sfbase.flight_of(draft), @sfbase.flight_lets_go(draft)) {
    (Some(f), _) if f.carried => false
    (Some(_), Some((at, ms))) => {
      composing.held_till = (draft, at + ms)
      // (built again as it is down, in the first frame drawn at or past that moment: their way is drawn each frame
      // meanwhile)
      if c.moment() < at + ms {
        c.shows_from(at + ms)
      }
      c.moment() < at + ms
    }
    (Some(_), None) => {
      composing.held_till = (draft, @double.infinity)
      true
    }
    _ => false
  }
}

///|
/// The way draft `draft`'s composer's ground last set out on (@motion.reshape_way), for the list's room under its rows
/// to go on: none while words sent from it hold it, nor one it set out on while they did (its coming down as they let
/// go of it: their row's opening's, the list's own way then, sfbase's shown_rows), which is no cause of the list's
/// once they are gone.
pub fn composer_way_for_list(c : @ui.Ctx, draft : String) -> (Double, Double)? {
  if composer_held(c, draft) {
    return None
  }
  match @motion.reshape_way(c, "composer/box") {
    Some((at, ms)) => {
      let (was, till) = composing.held_till
      if was == draft && at < till {
        None
      } else {
        Some((at, ms))
      }
    }
    None => None
  }
}

///|
/// How many lines of its field words sent from draft `draft`'s composer hold it as tall as, while they are in it (as
/// they took in it as they were sent: sfbase's flight_held_lines, theirs, this send's), at most as many as it shows; 0
/// when none do. Laid out so (its words' room that tall, whatever its field holds meanwhile), it goes on to the shape it
/// was on its way to as they were sent and stays there till they let go of it.
fn composer_held_lines(c : @ui.Ctx, draft : String) -> Int {
  let n = @sfbase.flight_held_lines(c, draft)
  if n > text_lines(c) {
    text_lines(c)
  } else {
    n
  }
}

///|
/// How tall what was added to draft `draft`'s composer (its quotes, its files) is held while words sent from it are in
/// it: as it was laid out with them as they were sent. Read once, in the frame they were sent, as it is built again
/// once laid out with them (sfbase's flight_start), the layout of that frame's draft, not a frame before; 0 when
/// nothing holds it.
fn composer_held_extras(c : @ui.Ctx, draft : String) -> Double {
  guard composer_held_lines(c, draft) > 0 else { return 0.0 }
  match @sfbase.flight_of(draft) {
    Some(f) => {
      if f.held_extras < 0.0 {
        f.held_extras = @motion.measured(c, "composer/extras/room").unwrap_or(0.0)
      }
      f.held_extras
    }
    None => 0.0
  }
}

///|
/// How much room draft `draft`'s composer takes at its page's foot (what the list leaves free under its last row): as
/// tall as its place (chat_composer: its box, what it says under it, its margins) with its ground as drawn (a line
/// more or less: the list's rows go with the ground as it reshapes, the frame it does), at least as tall as that opened
/// with one line. Words sent from it hold it as it was laid out for them (composer_held_lines), so its room is theirs
/// till they let go of it, and comes down with its ground then.
pub fn composer_room(c : @ui.Ctx, draft : String, settled? : Bool = false) -> Double {
  ignore(draft)
  // (not laid out yet: a capsule's)
  let foot = @motion.measured(c, "composer/foot").unwrap_or(capsule_room(c, c.width))
  // never less than it takes opened with one line where it is (its box that tall, what is round it as it is: the web's
  // --composer-room, max(the composer's height, an opened one-line composer's)): opened or let go, a capsule or a box,
  // the list keeps its words where they are; only a line more, a file, a quote, what is said over it move them
  let least = composer_least(c, draft)
  // (as it comes to stand while words sent from it hold it, nothing typed in it since: as it will once they let go of
  // it, opened with one line and emptied, not as it is laid out for them (it stops short of the shape it was on its way
  // to, @motion.stop_for); a new chat's first words as much, the chat it became under them)
  if settled && composer_held_lines(c, draft) > 0 && composing_field_empty(draft) {
    return least
  }
  // (`settled`: as it comes to stand, not where its shape is on its way: a new chat become its chat, the composer
  // coming down from the middle of the pane to its foot, the chat's rows standing over its foot from the first, not over
  // the middle of the pane where the new chat's scene still is)
  dmax(foot + (if settled { 0.0 } else { @motion.reshaped_over(c, "composer/box") }), least)
}

///|
/// A chat's composer at its pane's foot (dock.tsx's chat place; cloud.css.ts composerWrap: 12 over it, 16 under it;
/// dock.css.ts: 12 clear of the pane's sides, the column and its curve wide at most, in the middle): the chat's draft
/// , what it sends going into the chat (send_in_chat), no file taken in while its station is down.
/// Its place measured (composer_room). `apart`: the page a panel of its own (the
/// frame's tape), the composer as far from its foot as from its sides.
pub fn chat_composer(c : @ui.Ctx, src : Source, ws : Workspace, r : ChatRef, v : ChatView?, apart? : Bool = false) -> Unit {
  let spec : ComposerSpec = {
    station: r.station,
    draft: r.station + ":" + r.session,
    session: r.session,
    placeholder: @sf.t("web-main.composer.placeholder"),
    toolbar: None,
    note: match v {
      Some(v) => v.cc.filter(fn(o) { o.on }).map(fn(o) { (o.via, o.place) })
      None => []
    },
    tail: match v {
      Some({ cc, thread: Some(thread), .. }) if cc.length() > 0 => Some(fn() { cc_chooser(c, src, r, thread, cc) })
      _ => None
    },
    roomy: false,
    locked: false,
    offline: match v {
      Some(v) => v.offline
      None => false
    },
    warm_agent: !v.map(fn(v) { v.archived }).unwrap_or(false),
  }
  let width = composer_width(c.width)
  let place = if apart { composer_place(c, c.width) } else { composer_alone }
  let mut notices = -1
  let mut shaped = None
  let foot = c.box(style=chat_foot_top.then(@ui.style(pb=@sf.room_of(composer_foot_in(c, c.width)))), fn() {
    match v {
      Some(v) => notices = c.box(style=chat_notices_box, fn() { chat_notices(c, src, r, v, width) })
      None => ()
    }
    c.box(style=@ui.style(w=Fixed(width)), fn() {
      c.sized(width, c.height, fn() {
        shaped = composer_shaped(fn() {
          composer(
            c,
            src,
            ws,
            spec,
            fn(w) {
              match v {
                Some(v) => send_in_chat(c, src, r, v, w)
                None => ()
              }
            },
            place~,
          )
        }).1
      })
    })
    |> ignore
  })
  // what is said over it stands on its ground: up and down with it as it changes shape, in the same frames, not at
  // its new place at once (as a new chat's choices over it: new_chat.mbt)
  if notices >= 0 {
    with_composer(c, notices, "composer/notices/" + spec.draft, shaped)
  }
  @motion.measure(c, foot, "composer/foot")
}

///|
/// What is said over a chat's composer (chat_notices), one block standing on it.
// kept across runs: a value (no field of it changes)
let chat_notices_box : @ui.Style = @ui.css("w=Full align=ACenter")

///|
/// Whether the composer's 抄送 menu is open now (cc_chooser).
pub fn composer_cc_open() -> Bool {
  composing.cc_open
}

///|
/// In a chat whose agents are in Slack or Feishu threads: which of them what is sent is copied to too (Chat.tsx
/// CcChooser, `chat.cc`), each thread's bot saying there who wrote it on still.fail. Each thread ticked (its mark and
/// place) is said just before send, on one line and once opened alike (the composer's `note`: where it is copied stays
/// where it is as the composer opens and shuts; said at the row's start once opened, it jumped across, 2026-10-29
/// 「乱飞」). Once the composer is opened to write, 抄送 just before that (its `tail`), a chooser's look (@sf.chooser),
/// opening a menu of the threads to tick (each its mark and place, lined up with its end), each ticked one's check at
/// its end: several stay open to tick in turn, one closes once ticked.
fn cc_chooser(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double, to : Array[@sfbase.ChatCcTo]) -> Unit {
  let p = @sf.theme().p
  let id = c.id("composer/cc")
  // (pressed as it is let go: open or not as it is then)
  c.on_press(id, fn() { composing.cc_open = !composing.cc_open })
  let open = composing.cc_open
  let lit = c.lit(id) || open
  let on = to.filter(fn(o) { o.on }).map(fn(o) { (o.via, o.place) })
  let label = @sf.t("web-main.composer.ccLabel")
  let b = c.box(style=cc_trigger, selected=open, id~, fn() {
    c.text(label, style=if lit { cc_words_lit } else { cc_words }) |> ignore
    @sf.icon(c, "chevron-down", size=12.0, color=if lit { p.text } else { p.muted }) |> ignore
  })
  c.semantics(b, Button, id~, label=([label] + on.map(fn(o) { o.1 })).join(" "), expanded=open)
  let entries = to.map(fn(o) { @kit.menu_check(o.thread.to_string(), o.on, label=o.place) })
  // each its platform's mark before its place, as beside 抄送
  let marks : Map[String, (@ui.Ctx, Double) -> Unit] = Map([])
  for o in to {
    let via = o.via
    marks[o.thread.to_string()] = fn(c, _) { cc_mark(c, via) }
  }
  // each ticked one's check at its row's end (左子健), none before its mark
  let row_end = fn(c : @ui.Ctx, s : @kit.MenuItemState) {
    if s.entry.kind is Check(true) {
      @sf.icon(c, "check", size=14.0, color=p.text) |> ignore
    }
  }
  // (dismissed, closed at the moment of what dismissed it: Escape, a press beside it)
  let menu : Ref[@kit.Menu?] = Ref(None)
  c.with_dismissed(fn(_) { composing.cc_open = false }, fn() {
    menu.val = Some(
      @sf.dropdown(c, "composer/cc/menu", open, id, entries, {}, @sf.chooser_menu_w, side=Top, along=End, marks~, check_end=true, row_end~),
    )
  })
  let m = menu.val.unwrap()
  match m.chosen {
    Some(v) =>
      match to.search_by(fn(o) { o.thread.to_string() == v }) {
        Some(i) => {
          let o = to[i]
          let params : Json = {
            "station": Json::string(r.station),
            "thread": Json::number(thread),
            "to": Json::number(o.thread),
            "on": Json::boolean(!o.on),
          }
          c.tell("composer/cc", fn() { (src.call)("chat.cc", params, @sfbase.answer_unread) })
          // one: done once ticked; several: left as it is, open to tick the next (a tick never opens it: closed by
          // then, Escape after the tick, it stays closed)
          if to.length() <= 1 {
            composing.cc_open = false
          }
        }
        None => ()
      }
    None => ()
  }
}

///|
/// Where what is sent is copied: each thread's platform mark and place.
fn cc_places(c : @ui.Ctx, on : Array[(String, String)]) -> Unit {
  for o in on {
    c.box(style=cc_place, fn() {
      cc_mark(c, o.0)
      c.text(o.1, style=cc_words) |> ignore
    })
    |> ignore
  }
}

///|
// kept across runs: a value (no field of it changes)
let cc_trigger : @ui.Style = @ui.css((
  #|row h=S7 px=S2 gap=S1_5 radius=Lg align=ACenter hovered{bg=Hover} selected{bg=Hover}
))

///|
// kept across runs: a value (no field of it changes)
let cc_place : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let cc_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, wrap=false, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let cc_words_lit : @ui.TextStyle = cc_words.then(@ui.text_style(color=Fg))

///|
/// The mark of the platform it is copied to (the web's ElsewhereLogo): Feishu's for Feishu, else Slack's, 14.
fn cc_mark(c : @ui.Ctx, via : String) -> Unit {
  (if via == "feishu" { @sf.feishu_mark(c, 14.0) } else { @sf.slack_mark(c, 14.0) }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let cc_note_box : @ui.Style = @ui.css("row px=S2 gap=S2 align=ACenter")


///|
/// What is said over a chat's composer (Chat.tsx ChatShown, ArchiveNotice, CacheColdNotice, offlineNotice), each a
/// capsule of its own over it, as the composer is (`width` wide: composer_notice): an archived chat's, with its
/// 还原对话 (why it failed under it, till it is tried again; not while its station is down); its agent's prompt cache
/// over, saying what going on would read again, with the choice of how it goes on as it is next started, by a message
/// or a notice: 接着聊 or 换新上下文, the one it takes marked, the other pressed to take it (as its chat chose, or else
/// its station is set; why it failed in a toast); its station down.
fn chat_notices(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView, width : Double) -> Unit {
  let key = r.station + ":" + r.session
  // (built before its composer: whether this chat's composer was drawn before, not switched to at this moment, as the
  // composer has it once it is built, or as it left it)
  let whose = "\u{1}" + r.session
  composing.notices_new = composer_was(c) == whose
  if v.archived {
    let restore = c.id("composer/restore")
    let busy = composing.restoring.contains(key)
    if !busy && !v.offline {
      if !src.read_only {
        c.on_press(restore, fn() {
          composing.restoring[key] = true
          composing.restore_errors.remove(key)
          let p : Map[String, Json] = {
            "station": Json::string(r.station),
            "session": Json::string(r.session),
            "archived": Json::boolean(false),
          }
          match v.thread {
            Some(th) => p["thread"] = Json::number(th)
            None => ()
          }
          c.tell("composer/restore", fn() {
            (src.call)("chat.archive", Json::object(p), fn(res) {
              composing.restoring.remove(key)
              // felt as something done, or refused
              match res {
                Err(e) => {
                  composing.restore_errors[key] = error_words(e)
                  @ui.haptic(Reject)
                }
                Ok(_) => @ui.haptic(Confirm)
              }
            })
          })
        })
      }
    }
    composer_notice(
      c,
      width,
      "archive",
      @sf.t("web-main.archived.sendRestores"),
      Some((restore, if busy { "web-main.archived.restoring" } else { "web-main.archived.restore" }, "web-main.archived.restore", busy || v.offline)),
      failed=composing.restore_errors.get(key),
      chat=key,
    ) |> ignore
  }
  match v.cache_cold {
    Some((session, status, detail, afresh)) if !v.archived => {
      let go_on = c.id("composer/goOn")
      let fresh = c.id("composer/afresh")
      let doing = "session.settings/" + r.station + "/" + session
      let busy = @sfbase.doing(doing)
      let chosen = composer_notice(c, width, "wait", status, None, chat=key, choices=[(go_on, "web-main.chat.goOn", !afresh), (fresh, "web-main.chat.afresh", afresh)], held=busy || v.offline, summary=Some((status, detail)))
      match chosen {
        Some(value) => {
          composing.cold_open.set("")
          let next = value == fresh.to_string()
          if !busy && !v.offline && next != afresh && (value == fresh.to_string() || value == go_on.to_string()) {
            let words = if next { "web-main.chat.afresh" } else { "web-main.chat.goOn" }
            let params : Json = { "station": Json::string(r.station), "key": Json::string(session), "afresh": Json::boolean(next) }
            c.tell("composer/afresh", fn() { @sfbase.act(src, @sf.t(words), doing, "session.settings", params) })
          }
        }
        None => ()
      }
    }
    _ => ()
  }
  if v.offline {
    let said = match v.offline_note {
      Some(n) => n
      None =>
        if r.station_name != "" {
          @sf.t("web-main.chat.offline.named", args=[("name", r.station_name)])
        } else {
          @sf.t("web-main.chat.offline")
        }
    }
    composer_notice(c, width, "unplug", said, None, icon=if v.updating { "updating" } else { "unplug" }, chat=key) |> ignore
  }
  // the still.fail team's reply on a bug report sent from it: the chat's people's to read, never its agents'
  let replied = feedback_notice(c, src, r, width, key)
  notices_gone(c, width, key, [v.archived, v.cache_cold is Some(_) && !v.archived, v.offline, replied])
}

///|
/// The notices over chat `chat`'s composer no longer said (`now`: whether each of archive, wait, unplug, feedback is),
/// drawn as they were while they leave (composer_notice).
fn notices_gone(c : @ui.Ctx, width : Double, chat : String, now : Array[Bool]) -> Unit {
  for i, mark in ["archive", "wait", "unplug", "feedback"] {
    if now[i] {
      continue
    }
    match composing.notices_said.get("composer/notice/" + chat + "/" + mark) {
      Some((said, offer, dismiss, failed, icon, choices, summary)) => {
        let offer = offer.map(fn(o) { (o.0, o.1, o.2, true) })
        let dismiss = dismiss.map(fn(d) { (d.0, d.1, true) })
        composer_notice(c, width, mark, said, offer, dismiss~, failed?=failed, icon~, chat~, gone=true, choices~, held=true, summary~) |> ignore
      }
      None => ()
    }
  }
}

///|
/// A notice over a chat's composer (chat_notices): a capsule as the composer is, on its glass, 8 over it, its ends
/// drawn in from the composer's (`width`) so its mark (icon `icon`, else `mark`, which notice it is; `updating`, the
/// update's mark turning) stands over the composer's ＋ in the middle of its round start, its words quiet where the
/// composer's are, what it offers at its end (`offer`: its target, its words' key now, its name's key for what reads
/// the screen, whether it is out of reach) in the words' colour, a step heavier, with an optional × concentric with
/// its round end (`dismiss`: its target, its name's key, whether it is out of reach), or a choice of two or more
/// (`choices`: each its target, its words' key, whether it is the one taken; `held`, out of reach). The chosen
/// value is shown in a quiet menu control. Why what it offers failed (`failed`) is under its words, red. `summary`
/// holds the status and detail as separate words when the core supplies them. The choice's value comes back.
fn composer_notice(
  c : @ui.Ctx,
  width : Double,
  mark : String,
  said : String,
  offer : (Int, String, String, Bool)?,
  dismiss? : (Int, String, Bool)? = None,
  failed? : String?,
  icon? : String,
  chat? : String = "",
  gone? : Bool = false,
  choices? : Array[(Int, String, Bool)] = [],
  held? : Bool = false,
  summary? : (String, String)? = None,
) -> String? {
  let icon = icon.unwrap_or(mark)
  // shown while its chat is, it comes in as what is put in the composer does, one its chat opens with there at once;
  // gone, it leaves as a row of a list does, drawn as it was (notices_gone)
  let key = "composer/notice/" + chat + "/" + mark
  if !gone {
    composing.notices_said[key] = (said, offer, dismiss, failed, icon, choices, summary)
  }
  let look = @motion.presence(c, key, !gone, initial=composing.notices_new, enter=@sf.waiting_in, exit=@sf.leave)
  if gone && look is None {
    composing.notices_said.remove(key)
    return None
  }
  let t = @sf.theme()
  // its mark over the composer's ＋, in the middle of its round start: in a square as high as it is (a line and its
  // padding), its ends drawn in from the composer's as far as that takes (2026-10-29 the user: 圆角往里缩, 图标依然对准
  // 加号; as wide as the composer, its mark stood 7.5 off the middle of its round end)
  // If the summary and the chooser fit together, they share a line. Otherwise the chooser follows the summary.
  let text_line = if choices.is_empty() { t.t.meta_line } else { c.sp(t.t.meta_line) }
  let inline_high = dmax(text_line, @ui.Space::S7.px())
  let inline_side = inline_high + 2.0 * composer_notice_pad
  let inline_inset = capsule_pad_alone + capsule_extra(c) + (t.round.side + 1.0) / 2.0 - inline_side / 2.0
  // The 28-high chooser's capsule is concentric with the notice when its end is this far from the edge.
  let inline_end = (inline_side - @ui.Space::S7.px()) / 2.0
  let beside = if choices.is_empty() {
    false
  } else {
    let summary_width = match summary {
      Some((status, detail)) => c.words_across(status, composer_notice_status) + @ui.Space::S2.px() + c.words_across(detail, composer_notice_flow_words)
      None => c.words_across(said, composer_notice_flow_words)
    }
    let choice_width = choices.fold(init=0.0, fn(w, choice) {
      dmax(w, c.words_across(@sf.t(choice.1), composer_notice_choice_words))
    }) + 2.0 * @ui.Space::S2.px() + @ui.Space::S1_25.px() + 12.0
    inline_side + summary_width + @ui.Space::S3.px() + choice_width + inline_end <= width - 2.0 * inline_inset
  }
  let line_high = if beside { inline_high } else { text_line }
  let side = line_high + 2.0 * composer_notice_pad
  // (the ＋'s middle as the composer draws it: its round control's, a point wider for the capsule's edge line, its
  // capsule_pad_alone in; measured, 24.5 in from the composer's edge)
  let inset = capsule_pad_alone + capsule_extra(c) + (t.round.side + 1.0) / 2.0 - side / 2.0
  let drawn_in = width - 2.0 * inset
  // round as a line of it is high: a capsule while its words fit one line; wrapped, its corners still that round start,
  // its mark in it on its first line (round all its height, 3 lines made it a blob, its mark halfway down)
  let round = @ui.style(w=Fixed(drawn_in), radius=@sf.line_capsule_corner(side))
  let draw_mark = fn() {
    c.box(style=@ui.style(w=Fixed(side), h=Fixed(line_high), align=ACenter, justify=JCenter), fn() {
      // (its station gone for its update: the update's mark, turning)
      if icon == "updating" {
        @sf.updating_mark(c, composer_notice_mark, t.p.muted) |> ignore
      } else {
        @sf.icon(c, icon, size=composer_notice_mark, color=t.p.muted) |> ignore
      }
    }) |> ignore
  }
  let draw_title = fn() {
    c.box(style=if beside { composer_notice_title_inline } else { composer_notice_title }, fn() {
      draw_mark()
      match summary {
        Some((status, detail)) =>
          c.box(style=composer_notice_summary, flow=true, line_gap=@ui.Space::S1.px(), fn() {
            c.text(status, style=composer_notice_status) |> ignore
            c.text(detail, style=composer_notice_flow_words) |> ignore
          }) |> ignore
        None => c.text(said, style=composer_notice_flow_words) |> ignore
      }
    }) |> ignore
  }
  let selected : Ref[String?] = Ref(None)
  let draw_choice = fn() {
    let current = choices.fold(init="", fn(words, choice) {
      if choice.2 { @sf.t(choice.1) } else { words }
    })
    let entries = choices.map(fn(choice) {
      @kit.menu_radio(choice.0.to_string(), choice.2, label=@sf.t(choice.1), disabled=held)
    })
    let choice_key = notice_choice_key(chat, mark)
    let menu = @sf.chooser(
      c, choice_key, current, entries,
      fn() { composing.cold_open.get() == choice_key },
      fn(open) {
        if open { composing.cold_open.set(choice_key) }
        else if composing.cold_open.get() == choice_key { composing.cold_open.set("") }
      },
      side=Top, disabled=held, capsule=beside,
    )
    selected.val = menu.chosen
  }
  let box_style = if beside {
    composer_notice_box.then(@ui.style(pr=@sf.room_of(inline_end)))
  } else if dismiss is Some(_) {
    composer_notice_box_dismiss
  } else {
    composer_notice_box
  }
  let b = c.box(style=box_style.then(round), glass=@sf.glass_floating(), fn() {
    if choices.length() > 0 {
      if beside {
        c.box(style=composer_notice_flow, fn() {
          draw_title()
          draw_choice()
        }) |> ignore
      } else {
        draw_title()
        c.box(style=composer_notice_choice_line, fn() {
          // The chooser's own inset puts its label on the same line as the summary's words.
          c.box(style=@ui.style(w=Fixed(side - @ui.Space::S2.px())), fn() {  }) |> ignore
          draw_choice()
        }) |> ignore
      }
    } else if dismiss is Some((close_id, close_label, close_off)) {
      c.box(style=composer_notice_line, fn() {
        c.box(style=@ui.style(w=Fixed(side), h=Fixed(side), align=ACenter, justify=JCenter), fn() {
          @sf.icon(c, icon, size=composer_notice_mark, color=t.p.muted) |> ignore
        }) |> ignore
        c.box(style=composer_notice_words_dismiss, fn() {
          c.text(said, style=composer_notice_words) |> ignore
        }) |> ignore
        c.box(style=composer_notice_actions_dismiss, fn() {
          match offer {
            Some((id, words, name, off)) => {
              let b = c.box(id~, style=composer_notice_offer_dismiss.then(@ui.style(min_w=Fixed(side), min_h=Fixed(side))), fn() {
                c.text(@sf.t(words), style=if off { composer_notice_quiet } else { composer_notice_button }) |> ignore
              })
              c.semantics(b, Button, id~, label=@sf.t(name), disabled=off)
            }
            None => ()
          }
          let hot = !close_off && c.lit(close_id)
          if !close_off {
            @sf.tip(c, key + "/dismiss", close_id, @sf.t(close_label))
          }
          let cb = c.box(id=close_id, style=@ui.style(w=Fixed(side), h=Fixed(side), align=ACenter, justify=JCenter), fn() {
            @sf.icon(c, "close", size=composer_notice_mark, color=if hot { t.p.text } else { t.p.muted }) |> ignore
          })
          c.semantics(cb, Button, id=close_id, label=@sf.t(close_label), disabled=close_off)
        }) |> ignore
      }) |> ignore
    } else {
      c.box(style=composer_notice_line, fn() {
        draw_mark()
        c.text(said, style=composer_notice_words) |> ignore
        match offer {
          Some((id, words, name, off)) => {
            let b = c.box(id~, style=composer_notice_offer, fn() {
              c.text(@sf.t(words), style=if off { composer_notice_quiet } else { composer_notice_button }) |> ignore
            })
            c.semantics(b, Button, id~, label=@sf.t(name), disabled=off)
          }
          None => ()
        }
      }) |> ignore
    }
    match failed {
      Some(Some(e)) =>
        c.box(style=@ui.style(w=Full, pl=@sf.room_of(side)), fn() { c.text(e, style=composer_notice_failed) |> ignore })
        |> ignore
      _ => ()
    }
  })
  match look {
    Some(l) => {
      c.look(b, l)
      @motion.leaving(c, b, !gone)
    }
    None => ()
  }
  // over a chat's messages, as the composer: their scroll bar keeps clear of it
  c.floats_over(b)
  selected.val
}

///|
/// A notice's capsule (composer_notice): round at its ends as the composer's capsule (as round as a line of it is high:
/// composer_notice), its mark over the composer's ＋ in the middle of its round start (its ends drawn in to stand so),
/// what it offers 16 from its end, 8 over and under its words, 8 over the composer.
// kept across runs: a value (no field of it changes)
let composer_notice_box : @ui.Style = @ui.css("mb=S2 pr=S4 py=S2 gap=S1")

///|
/// How far a notice's line is in from its top and bottom (its box's py=S2).
let composer_notice_pad : Double = 8.0

///|
/// A notice's line: its mark, its words and what it offers on its first line (its words wrapped under it).
// kept across runs: a value (no field of it changes)
let composer_notice_line : @ui.Style = @ui.css("row w=Full align=AStart")

///|
/// How big a line's mark is.
let composer_notice_mark : Double = 16.0

///|
/// What a line offers: 12 from its words.
// kept across runs: a value (no field of it changes)
let composer_notice_offer : @ui.Style = @ui.css("pl=S3")

///|
/// A notice's capsule with its × concentric with its round end (composer_notice): its top and bottom room on its words
/// so its mark and its × stand `side` square at its ends.
// kept across runs: a value (no field of it changes)
let composer_notice_box_dismiss : @ui.Style = @ui.css("mb=S2 gap=S1")

///|
// kept across runs: a value (no field of it changes)
let composer_notice_words_dismiss : @ui.Style = @ui.css("row w=Full py=S2")

///|
// kept across runs: a value (no field of it changes)
let composer_notice_actions_dismiss : @ui.Style = @ui.css("row pl=S3 gap=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let composer_notice_offer_dismiss : @ui.Style = @ui.css("align=ACenter justify=JCenter")

///|
/// Words and choices fit on one line when there is room, otherwise the choices follow the words.
// kept across runs: a value (no field of it changes)
let composer_notice_flow : @ui.Style = @ui.css("row w=Full gap=S3 justify=JBetween align=ACenter")

///|
/// A wrapped choice starts under the summary rather than under the mark.
// kept across runs: a value (no field of it changes)
let composer_notice_choice_line : @ui.Style = @ui.css("row w=Full")

///|
/// The mark and summary stay together; where they share a line with the choice they are centred in that line.
// kept across runs: a value (no field of it changes)
let composer_notice_title : @ui.Style = @ui.css("row w=Full align=AStart")

///|
// kept across runs: a value (no field of it changes)
let composer_notice_title_inline : @ui.Style = @ui.css("row align=ACenter")

///|
/// Status and cost read together, each whole if the line has to wrap.
// kept across runs: a value (no field of it changes)
let composer_notice_summary : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let composer_notice_status : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Fg, wrap=true)

///|
/// The words take their own width in a flow, wrapping only if the line itself is too narrow.
// kept across runs: a value (no field of it changes)
let composer_notice_flow_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=true)

///|
/// The chooser's own text style, used to measure its widest possible label before placing it.
// kept across runs: a value (no field of it changes)
let composer_notice_choice_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, wrap=false, color=Muted)

///|
/// Its words: the ui size, muted, wrapped in the rest of the line.
// kept across runs: a value (no field of it changes)
let composer_notice_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=true, w=@sf.grow)

///|
/// What it offers, out of reach (busy, its station down): as quiet as its words.
// kept across runs: a value (no field of it changes)
let composer_notice_quiet : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let composer_notice_button : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let composer_notice_failed : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, wrap=true, w=Full)

///|
/// A chat's composer's place while it is a capsule at the foot of a pane `pane` wide: its buttons (the theme's round
/// controls) 8 in, further while its field's line is taller than they are (capsule_extra), 12 over it and its foot's
/// room under it (composer_foot_in).
fn capsule_room(c : @ui.Ctx, pane : Double) -> Double {
  @sf.theme().round.side + 2.0 * (capsule_pad_alone + capsule_extra(c)) + 12.0 + composer_foot_in(c, pane)
}

///|
/// The room a chat's composer takes opened with one line at the foot of a pane `pane` wide (its box, composer_open_box;
/// 12 over it and its foot's room under it, composer_foot_in): what a list that keeps its words in place as the
/// composer closes keeps clear at least.
pub fn composer_open_room(c : @ui.Ctx, pane : Double, corner? : Double = @sf.composer_corner()) -> Double {
  composer_open_box(c, corner~) + 12.0 + composer_foot_in(c, pane)
}

///|
/// How far a chat's composer stands from the foot of a pane `pane` wide (over the system's navigation bar, which is the
/// page's): where it reaches across it, as far as from its sides (composer_side), the four sides of what it stands in
/// alike (a phone's screen, a panel of its own: there in its corners, InnerOr); in a pane wider than it (a wide column,
/// the composer 804 at most in its middle) the web's 16. On the page's way to another width (a side panel sliding
/// beside a chat, the sidebar opening or folding: @sfbase.page_way) across the width it reaches across at, as at the
/// narrower of where the pane set off and where it goes, as the chat's list is laid out then (chat_list's laid_w): from
/// one to the other on the way the page goes (moved or reshaped, sf/motion.mbt) from the frame it sets off, or from the
/// moment it is there (page_way's `ends`, whichever frame finds it so), not at once: what it holds under it and the
/// chat's rows standing over its room (composer_room) going with it, not stepped 8 in one frame (rows_steady.mbt). The
/// window taking the pane across with no way going: there at once.
pub fn composer_foot_in(c : @ui.Ctx, pane : Double) -> Double {
  let way = @sfbase.page_way
  let w = if way.id == "" {
    pane
  } else {
    let from = match composer_set_off.val {
      (id, w) if id == way.id => w
      _ => {
        composer_set_off.val = (way.id, pane)
        pane
      }
    }
    // (across that width on the way, as at the narrower of where it set off and where it goes; else as it is)
    if composer_across(from) != composer_across(way.to) {
      dmin(dmin(from, way.to), pane)
    } else {
      pane
    }
  }
  let to = composer_foot_at(w)
  match composer_foot_way.val {
    None if way.id == "" => to
    None => {
      let a = @motion.Anim::new(composer_foot_at(pane))
      a.follow(c, to, @sf.move_spring)
      composer_foot_way.val = Some((a, way.id, way.ends))
      a.get(c)
    }
    Some((a, last, _)) if way.id == "" && last == "" && to != a.target() => {
      composer_foot_way.val = None
      to
    }
    // (the way there: on from the moment it is, whichever frame sees it)
    Some((a, last, ends)) if way.id == "" && last != "" => {
      if to != a.target() {
        a.animate(c, to, @sf.move_spring, start_at=dmin(ends, c.moment()))
      }
      composer_foot_way.val = Some((a, "", 0.0))
      a.get(c)
    }
    Some((a, _, _)) => {
      a.follow(c, to, @sf.move_spring)
      composer_foot_way.val = Some((a, way.id, way.ends))
      a.get(c)
    }
  }
}

///|
/// How far a chat's composer stands from the foot of a pane `pane` wide at rest (composer_foot_in).
fn composer_foot_at(pane : Double) -> Double {
  if composer_across(pane) {
    composer_side()
  } else {
    composer_foot_wide
  }
}

///|
/// How far under the composer its room is since a page's way set it off (composer_foot_in), and the way it was on as it
/// was last asked ("" none) and when that is there: none till then, and none once the window takes the pane across with no way going.
let composer_foot_way : Ref[(@motion.Anim, String, Double)?] = Ref(None)

///|
/// The page's way the composer's pane is on, and how wide it was as it set off (composer_foot_in).
let composer_set_off : Ref[(String, Double)] = Ref(("", 0.0))

///|
/// Whether a chat's composer reaches across a pane `pane` wide, as far from its sides as from its foot
/// (composer_foot_in), not narrower than it in its middle.
fn composer_across(pane : Double) -> Bool {
  composer_width(pane) >= pane - 2.0 * composer_side() - 0.5
}

///|
let composer_foot_wide : Double = 16.0

///|
/// Its box opened with one line (composer_open_room without what is over and under it): as composer_box_open lays it
/// out, its padding over the line (text_open: 8 over it), its field's one line as it is laid out at the system's size
/// of words (field_line), its parts 10 apart, its buttons' row as far from its foot as makes them concentric with its
/// corners (tools_row).
fn composer_open_box(c : @ui.Ctx, corner? : Double = @sf.composer_corner()) -> Double {
  let t = @sf.theme()
  @sf.composer_pad + (8.0 + field_line(c)) + 10.0 + t.round.side + @ui.capsule_in(corner, t.round.side)
}

///|
/// A chat's foot: 12 over the composer, its room under it its pane's (composer_foot_in).
// kept across runs: a value (no field of it changes)
let chat_foot_top : @ui.Style = @ui.css("w=Full pt=S3 align=ACenter")
