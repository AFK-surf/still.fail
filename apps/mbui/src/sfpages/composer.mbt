// Where people write to a chat on the desktop (ember web/src/Chat.tsx ComposerView, ComposerTools, useComposerText's
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
}

///|
/// What the composer keeps of its own: the system's picker asked for files (for which draft), when the cursor left it
/// (it stays a box a moment, LET_GO_MS), when typing last warmed the agent's runtime, each quote's comment field, how
/// it was laid out as it was last drawn (a new chat's roomy, or a chat's: another, it has moved between the pages),
/// which chat it was for (another: switched to, the cursor put in it), the archived chats being restored and why
/// restoring one failed (by their drafts).
priv struct Composing {
  mut picking : (String, @ui.Pick)?
  let_go : @signals.Signal[Bool]
  warmed : Map[String, Int]
  comments : Map[String, @ui.Field]
  mut roomy : Bool?
  mut draft : String
  /// as the frame before left them (the frame each build of this one starts from: frame_body may build it twice), and
  /// that frame's number
  mut roomy_before : Bool?
  mut draft_before : String
  mut frame : Int
  /// whether what waits in it now was in it as the frame before drew it (the same draft): what is put in since comes in
  /// (held_coming), what a draft opened with is there at once
  mut same_draft : Bool
  /// whether a notice over a chat's composer, new to it, comes in (chat_notices: the chat shown the frame before)
  mut notices_new : Bool
  /// what each notice over a chat's composer said as it was last drawn, by its key: drawn so as it leaves
  notices_said : Map[String, (String, (Int, String, String, Bool)?, String??, String, Array[(Int, String, Bool)])]
  /// the page's choices in its row as it was last drawn, as the frame before left them, and those of the page it came
  /// from that this one has not, while they leave (a new chat's, gone to its chat)
  mut toolbar : (() -> Unit)?
  mut toolbar_before : (() -> Unit)?
  mut toolbar_leaving : (() -> Unit)?
  restoring : @sf.LiveMap[String, Bool]
  restore_errors : @sf.LiveMap[String, String]
  /// a finger went down outside it (keyboard_let_go); its `@` menu up over it as it was last drawn (a press in it is
  /// the composer's own)
  mut outside : Bool
  mut menu_up : Bool
  /// what its field says while empty as it was last drawn, till another is to be said and it has faded out
  /// (composer_text)
  hint_shown : @signals.Signal[String]
  /// the cursor asked into it in this frame (it has it from the next): what it says while empty is
  /// what it says with the cursor in it already
  taking : @signals.Signal[Bool]
  /// its 抄送 menu open (cc_chooser)
  mut cc_open : Bool
  /// the shape its field's hint was last shown on (composer_hint): changed, the hint waits till it is there
  mut hint_shape : String
  /// whether it is a box or a capsule and how roomy, as the frame began and as built now (frame, then, now): what opens
  /// or lets go of it (composer)
  mut opened : (Int, String, String)
  /// the cursor asked into it as it is next drawn, on any screen (composer_take_focus)
  mut wanted : Bool
  /// each quote's card's colour as it was last drawn, by quote: where its ground sets out from as it is sent
  /// (flying_quotes)
  grounds : Map[String, Int64]
  /// each quote's own picture as it was last drawn in its card, by quote: what flies from there as it is sent
  pictures : Map[String, String]
  /// what its box last changed shape for and how, in which build (composer_shape)
  mut shaped : (Int, String, @motion.Spec)?
}

///|
/// The cursor into the composer as it is next drawn, with touch too (its keyboard up): what opened it is for
/// writing (新建对话: pengxiao, 2026-10-25).
pub fn composer_take_focus() -> Unit {
  composing.wanted = true
}

///|
let composing : Composing = {
  picking: None,
  let_go: @signals.signal(false, same=fn(a, b) { a == b }),
  warmed: {},
  comments: {},
  roomy: None,
  draft: "",
  roomy_before: None,
  draft_before: "",
  frame: -1,
  same_draft: false,
  notices_new: false,
  notices_said: {},
  toolbar: None,
  toolbar_before: None,
  toolbar_leaving: None,
  restoring: @sf.LiveMap::new(),
  restore_errors: @sf.LiveMap::new(),
  outside: false,
  menu_up: false,
  hint_shown: @signals.signal("", same=fn(a, b) { a == b }),
  taking: @signals.signal(false, same=fn(a, b) { a == b }),
  cc_open: false,
  hint_shape: "",
  opened: (-1, "", ""),
  wanted: false,
  grounds: {},
  pictures: {},
  shaped: None,
}

///|
fn composing_reset() -> Unit {
  composing.picking = None
  composing.let_go.set(false)
  composing.warmed.clear()
  composing.comments.clear()
  composing.grounds.clear()
  composing.pictures.clear()
  composing.roomy = None
  composing.draft = ""
  composing.roomy_before = None
  composing.toolbar = None
  composing.toolbar_before = None
  composing.toolbar_leaving = None
  composing.draft_before = ""
  composing.frame = -1
  composing.same_draft = false
  composing.notices_new = false
  composing.notices_said.clear()
  composing.restoring.clear()
  composing.restore_errors.clear()
  composing.outside = false
  composing.menu_up = false
  composing.cc_open = false
  composing.hint_shape = ""
  composing.opened = (-1, "", "")
  composing.wanted = false
  composing.hint_shown.set("")
  composing.taking.set(false)
}

///|
/// The composer's text field (its words, a flight's from: flight.mbt), its box, what is in it.
pub let composer_field_key : String = "composer/field"

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
  // what the system's picker answered, taken in before the box is laid out (the host's word that it answered brings
  // this frame); the files pasted into the field; what 文件's 添加到消息 put in for this draft
  take_in(c, src, spec, w, no_files)
  // switched to another chat (Chat.tsx: its thread another; a new chat's has none, whichever station): the cursor in
  // it with keyboard and mouse (its keyboard at hand), before it is first drawn; not taken from a field in use (the switcher's, a dialog's)
  let whose = "\u{1}" + spec.session
  if composing.frame != c.frame_number() {
    composing.frame = c.frame_number()
    composing.roomy_before = composing.roomy
    composing.draft_before = composing.draft
    composing.toolbar_before = composing.toolbar
    composing.taking.set(false)
  }
  composing.same_draft = whose == composing.draft_before
  if whose != composing.draft {
    composing.draft = whose
    // (where the keyboard is at hand, typed into at once; not raising the screen's keyboard over the chat)
    if !@sf.soft_keyboard() && !c.field_focused() {
      c.focus_editor(composer_field_key)
      composing.taking.set(true)
      // (this frame's alone: what reads it built again the frame after, as it has the cursor)
      c.tell("composer/taking", fn() { composing.taking.set(false) })
    }
  }
  // asked for (a new chat: composer_take_focus), with touch too, its keyboard up
  // (asked again till it is found held as a frame begins: the page it was asked from let go of as the new one comes,
  // its field's focus with it, nav.mbt forget)
  if composing.wanted && !spec.locked {
    if c.editor_focused(composer_field_key) {
      composing.wanted = false
    } else {
      // (the press that asked for it, lifted outside it, not taken for one letting go of the keyboard)
      composing.outside = false
      c.focus_editor(composer_field_key)
      composing.taking.set(true)
      // (this frame's alone: what reads it built again the frame after, as it has the cursor)
      c.tell("composer/taking", fn() { composing.taking.set(false) })
    }
  }
  let focused = c.editor_focused(composer_field_key)
  // a box while it has the cursor; lost, a capsule a moment later (LET_GO_MS)
  if focused {
    composing.let_go.set(true)
  }
  let lost_long = @kit.after(c, "composer/let-go", !focused, let_go_ms)
  let held = composing.let_go.get() && !focused && !lost_long
  if lost_long {
    composing.let_go.set(false)
  }
  // words just sent from it still in it: as tall as it was then, its field where it was and its ＋ and send at its foot
  // (composer_hold), so nothing in it moves until it comes down
  let sent_box = composer_held_box(c, spec.draft)
  let multiline = spec.roomy ||
    focused ||
    held ||
    sent_box > 0.0 ||
    w.text.get() != "" ||
    w.files.length() > 0 ||
    w.quotes.length() > 0
  // ready as the core says, or as soon as there are words in the field: the core's say comes a moment after them (its
  // topic), and send pressed meanwhile is not lost (what goes is the core's to take: composer.take, nothing taken
  // nothing sent)
  let ready = (w.ready || (w.text.get().trim() != "" && !w.starting)) && !spec.locked
  // sent once what it refers to can be read in this workspace (OutsideShare.tsx, sfbase's outside.mbt): at once when
  // it refers to nothing of another workspace, else once the viewer has said so (outside.mbt's dialog)
  @sfbase.sharing_go(w.key)
  let submit = fn() {
    if ready {
      @sfbase.send_sharing(src, w.key, spec.station, w.text.get().trim(chars=" \n\t").to_string(), fn() { send(w) })
      // (sent in this build, after its field was built: their field's hint and caret gone with them from now, not
      // shown once over them as they set out)
      if @sfbase.flight_hint_away(c, w.key) {
        w.field.colors(placeholder=@sf.alpha(p.subtle, 0.0), caret=@sf.alpha(p.accent, 0.0))
      }
    }
  }
  outside_dialog(c, src, w.key)
  let cap = c.id("composer/cap")
  // (a press on it is its field's: the I-beam over it)
  if !spec.locked {
    c.cursor(cap, IBeam)
  }
  if !spec.locked && c.clicked(cap) {
    c.focus_editor(composer_field_key)
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
  // laid out for another page than the frame before (a new chat's roomy in the page, a chat's at its foot: dock.tsx)
  let moved = match composing.roomy_before {
    Some(was) => was != spec.roomy
    None => false
  }
  // (gone to its chat's foot as a new chat's first words set out from it: on their way and as long, one motion with
  // them, not a page's quick start that leaves them behind and goes far in its first frame)
  let opening = composer_opening(c, "\{spec.roomy}|\{multiline}")
  let shape = if moved && flight_carried(spec.draft) {
    @motion.tween(flight_desk_ms, ease=Flight)
  } else if composer_let_go(c, spec.draft) {
    // (let go by words sent from it: down on their flight's clock, with its room, composer_hold)
    // det-ok(motion-length): words sent's own, set with their flight (docs/motion.md kind 4)
    @motion.tween(@sfbase.sent_down_of(spec.draft), ease=Move)
  } else if opening && !moved {
    // (opened from a capsule or let go to one: its field passes by its ＋ and send on their way, kept off them only on
    // this clock so far; on a faster one it cut into ＋, the user 2026-10-30: 「输入框盖住了加号和发送」)
    // det-ok(motion-length): the field opening past ＋ and send kept off them on this clock, till their cutting is mended
    @motion.tween(composer_shape_ms, ease=Move)
  } else {
    @motion.move()
  }
  let hint = composer_hint(
    c,
    spec,
    w,
    focused || held,
    moved,
    "\{spec.roomy}|\{multiline}|\{sent_box > 0.0}|\{w.files.length()}|\{w.quotes.length()}|\{w.error != ""}",
    shape,
  )
  // gone to a page with no choices in its row from one with them (a new chat become its chat, or left for one): they
  // leave as the new chat's other parts by the composer do (madeChat.ts: fading where they are, @sfbase.new_fade),
  // carried with the row as it goes, drawn only; till the end that fade declared
  if moved {
    composing.toolbar_leaving = if spec.toolbar is None { composing.toolbar_before } else { None }
  }
  let fade = @sfbase.new_fade(c)
  if fade.over() {
    composing.toolbar_leaving = None
  }
  composing.toolbar = spec.toolbar
  // its parts (what goes with it from where it showed as it changes shape: morph.ts's PARTS), as this build has them
  let mut plus = -1
  let mut words = -1
  let mut send_i = -1
  let mut chosen = -1
  let mut said = -1
  let box = c.box(
    style=if sent_box > 0.0 {
      composer_box_open().then(@ui.style(min_h=Fixed(sent_box), justify=JBetween))
    } else if multiline {
      composer_box_open()
    } else {
      composer_box.then(capsule_place(place))
    },
    // (the raised ground's glass, the accent's over it while dragged over)
    glass=@sf.glass_floating(tint?=if dragging { Some(@sf.alpha(p.accent, drag_tint)) } else { None }),
    id=cap,
    fn() {
      if multiline {
        composer_extras(c, src, spec, w)
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
              c.look(chosen, @ui.look(alpha=1.0 - fade.get()))
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
            send_i = send_button(c, ready, w.starting, submit)
          })
          |> ignore
        })
        |> ignore
      } else {
        plus = attach(c, src, spec, w, no_files)
        words = composer_text(c, src, ws, spec, w, cap, multiline, hint, submit)
        c.box(style=tail_row, fn() {
          said = composer_note(c, spec.note)
          send_i = send_button(c, ready, w.starting, submit)
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
  // here (a new chat's choices) carried on its ground (morph.ts morph), what it held there and does not here leaving
  // on it; words sent from it, as they let go of it (held till then: composer_hold). Moved by nothing of these (the
  // window, the sidebar, a keyboard), or another chat's on the same page (what it holds swapped, not changed), it is
  // where it is laid out at once (docs/motion.md)
  composing.roomy = Some(spec.roomy)
  let holds = if whose != composing.draft_before && !moved {
    ""
  } else {
    "\{spec.roomy}|\{multiline}|\{sent_box > 0.0}|\{w.files.length()}|\{w.quotes.length()}|\{w.error != ""}|" +
    w.field.text()
  }
  // (at a page's foot down the system's column, not roomy in a new chat's middle: opened from its foot, a keyboard
  // coming in the same frame taken at once, the user 2026-10-30 「以底部为 origin」; there the keyboard lifts it from its
  // first point on, ios_app.m ime_over)
  @motion.reshape(c, box, "composer/box", by=holds, spec=shape, carry=moved, foot=!spec.roomy && @sf.native_side())
  composing.shaped = Some((c.build_number(), holds, shape))
  for part in [(plus, "plus"), (words, "words"), (send_i, "send"), (chosen, "choices"), (said, "note")] {
    if part.0 >= 0 {
      @motion.layout(c, part.0, "composer/part/" + part.1, spec=shape, by=holds)
    }
  }
  // with a finger: a tap outside it lets go of the keyboard (a scroll does wherever it is: mbui's list drag)
  if @ui.pointing() is Finger {
    keyboard_let_go(c, cap)
  }
  @motion.measure(c, box, "composer/content")
  if w.error != "" {
    c.box(style=error_box, fn() { c.text(w.error, style=composer_error_words) |> ignore }) |> ignore
  }
}

///|
/// What the composer built in this build changes shape for and how (its box's reshape: `by`, `spec`), for what stands
/// round it on its page (a new chat's choices over it, its scene): moved for that too, by the same, it goes with the
/// box's ground in the same frames, not to its new place at once. None while it is not built in this build.
fn composer_shape(c : @ui.Ctx) -> (String, @motion.Spec)? {
  match composing.shaped {
    Some((build, by, spec)) if build == c.build_number() => Some((by, spec))
    _ => None
  }
}

///|
/// Node `i` keyed `key`, standing round the composer built in this build (over it, under it, beside it), moves with
/// its box as that changes shape (composer_shape); called once the composer is built.
fn with_composer(c : @ui.Ctx, i : Int, key : String) -> Unit {
  match composer_shape(c) {
    Some((by, spec)) => @motion.layout(c, i, key, spec~, by~)
    None => ()
  }
}

///|
/// A finger down outside the composer (`cap`), nothing over it presented (its `@` menu, a sheet), lets go of the
/// keyboard once lifted; lifted after a long press (not a tap) the keyboard stays (still.fail's Android app's
/// Keyboard.kt letsGoOfKeyboard). A finger scrolling the messages lets go of it in mbui (a list's drag), for any field.
fn keyboard_let_go(c : @ui.Ctx, cap : Int) -> Unit {
  let press = c.press()
  if press.fresh {
    // (on the composer or what is in it, its `@` menu's too, as the press went down: the hand's, not where it was
    // drawn; a chat picked in the menu as the press is let go closes it before this frame is built)
    composing.outside = !c.press_within(cap) &&
      !c.press_within(c.id(ref_menu_key + "/panel")) &&
      !@sf.presenting() &&
      !composing.menu_up
  }
  if composing.outside && c.editor_focused(composer_field_key) && press.lifted && !press.long {
    composing.outside = false
    c.blur()
  }
  if press.lifted {
    composing.outside = false
  }
}

///|
/// What comes into the draft from outside the field before the box is laid out: the files the system's picker
/// answered (for this draft), the files pasted into the field (⌘V with files or a picture on the clipboard, as the
/// web's paste takes the clipboard's files), the rows the 文件 tab's 添加到消息 put in (named by their path, or as files where this chat
/// takes what is dragged in so).
fn take_in(c : @ui.Ctx, src : Source, spec : ComposerSpec, w : Writing, no_files : Bool) -> Unit {
  // (what was put into the draft from elsewhere: built again as it is)
  @sfbase.drafts_given_read()
  match composing.picking {
    Some((key, picker)) =>
      match picker.files() {
        Some(files) => {
          composing.picking = None
          if key == w.key && !no_files {
            for f in files {
              writing_add_picked(src, w, spec.station, f)
            }
          }
        }
        None => ()
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
      c.focus_editor(composer_field_key)
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
  let prefs = (src.topic)("prefs", {}).value
  match field(field(prefs, "dropFiles"), key) {
    Some(True) => true
    Some(False) => false
    _ => text(prefs, "dropAs") == "file"
  }
}

///|
/// A station's file or folder carried in (Drive.tsx droppedFrom): which station has it and where, and where it is in
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
/// The text field (useComposerText's textarea, Chat.css.ts composerText): 14 on 1.5, growing with the text up to 480 or
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
  let prefs = (src.topic)("prefs", {}).value
  let hint = space_hint(c, prefs, spec.locked)
  let away = @sfbase.flight_hint_away(c, w.key)
  let no_files = spec.locked || spec.offline
  // what the field was given since the last frame, as the core reads it (a mark taken whole, a chat's link pasted)
  @sfbase.refs_edits(c, src, w.key, w.field, spec.station, spec.locked)
  // what it says while empty changed (the cursor gone from it: the key that brings it back; back in it: what to write)
  // fades out, then the other in where it was, never one put for the other at once
  let wanted = if hint != "" { hint } else { spec.placeholder }
  // (another chat's, or its first: what it says from the first, as it is)
  if composing.hint_shown.get() == "" || !composing.same_draft {
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
  c.box(style=if multiline { text_open } else { text_shut }, fn() {
    words = c.box(style=text_own, fn() {
      // (what is typed set as its message will set it: the theme's words)
      let (size, line) = c.style_size(@sf.theme().t.words)
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
        placeholder_color=@sf.alpha(p.subtle, hint_in.get() * said_look.alpha),
        caret_color=if away { @sf.alpha(p.accent, 0.0) } else { p.accent },
        enter_sends=@sf.enter_sends(),
        // (the `@` menu open: ↑ / ↓ choose in it, Enter and Tab pick)
        leaves=ref_leaves(src, spec, w, c.editor_focused(composer_field_key)),
        files=!no_files,
        // words pasted at once past the core's bound: a file of their own (Chat.tsx onPaste)
        paste_limit=if no_files || w.starting { 0 } else { @sfbase.paste_threshold(c, src) },
        look=@sfbase.refs_look(w.key, p.accent),
        field=w.field,
      )
      match res.pasted {
        Some(words) => @sfbase.writing_paste(src, w, spec.station, words)
        None => ()
      }
      // `@` and a few letters: the chats they find over the composer (Enter picks one there)
      let menu = ref_menu(c, src, spec, w, cap, res.focused)
      composing.menu_up = menu
      match res.submitted {
        // (they stay in the field until they go)
        Some(words) => {
          if words != w.text.get() {
            writing_text(src, w, words)
          }
          submit()
        }
        None =>
          if res.text != w.text.get() && !w.starting {
            writing_text(src, w, res.text)
            warm(c, src, spec)
          }
      }
      // nothing typed: the chat above or below, as the list shows them now
      if res.focused && w.text.get() == "" && !(@sfbase.neighbour_held.val)() && !menu {
        if c.key_pressed(@ui.key_code_up, in_field=true) {
          (@sfbase.neighbour_go.val)(src, ws, -1)
        } else if c.key_pressed(@ui.key_code_down, in_field=true) {
          (@sfbase.neighbour_go.val)(src, ws, 1)
        }
      }
    })
  })
  |> ignore
  words
}

///|
/// How far its field's hint (its placeholder) shows: only on a composer at rest without the cursor, so it never moves
/// with the composer's shape. Gone at once as the field takes the cursor (`hidden`: or keeps the box a moment after),
/// and while words sent leave the emptied field, still over it (madeChat.ts data-made-hint, flight.mbt); back over 200 ms
/// once they are out of it, or, the composer changing `shape` (its box let go to a capsule, a file put in it, `moved`
/// to another page), once it is there (by `going`, the shape's motion).
fn composer_hint(
  c : @ui.Ctx,
  spec : ComposerSpec,
  w : Writing,
  hidden : Bool,
  moved : Bool,
  shape : String,
  going : @motion.Spec,
) -> @motion.Anim {
  let hint = @motion.anim(c, "composer/hint", 1.0)
  // (another chat's draft swapped in is no change of shape: it is where it is laid out at once)
  let reshaped = shape != composing.hint_shape &&
    composing.hint_shape != "" &&
    ("\u{1}" + spec.session == composing.draft_before || moved)
  composing.hint_shape = shape
  if hidden || @sfbase.flight_hint_away(c, w.key) {
    hint.snap(0.0)
  } else if reshaped {
    hint.snap(0.0)
    hint.animate(1.0, @motion.tween(@sf.hint_back_ms, ease=Out, delay=going.duration(0.0, 1.0, 0.0)))
  } else {
    hint.follow(1.0, @motion.tween(@sf.hint_back_ms, ease=Out))
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
  if spec.session == "" || spec.locked || spec.offline || src.read_only {
    return
  }
  let n = composing.warmed.get(spec.session).unwrap_or(0)
  if n > 0 && !@kit.after(c, "composer/warm/" + spec.session + "/\{n}", true, warm_every_ms, later=true) {
    return
  }
  composing.warmed[spec.session] = n + 1
  c.tell("composer/warm", fn() {
    (src.call)("session.warm", { "station": Json::string(spec.station), "key": Json::string(spec.session) }, fn(_) {  })
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
    if c.clicked(id) {
      if @sf.attach_from_sheet() {
        attach_open(id, src, w.key)
      } else {
        pick_files(w)
      }
    }
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
/// The system's file picker for draft `w`: what is picked comes in as the composer is next drawn (take_in).
pub fn pick_files(w : Writing) -> Unit {
  match @ui.pick(Files) {
    Some(p) => composing.picking = Some((w.key, p))
    None => ()
  }
}

///|
/// Send (sendBtn): 32 round, the text's ink with the canvas's arrow while it can go (a step lighter pointed at), the
/// ink faint over the box's ground while not, going from one to the other as a control answers (a button's background
/// over --dur: sent, it fades to faint); a turning ring while a new chat is made for it.
fn send_button(c : @ui.Ctx, ready : Bool, starting : Bool, submit : () -> Unit) -> Int {
  let p = @sf.theme().p
  let id = c.id("composer/send")
  let hot = ready && c.lit(id)
  if ready {
    if c.clicked(id) {
      submit()
    }
  }
  @sf.tip(c, "composer/send", id, @sf.t("web-main.composer.send"))
  let able = @sf.ease_to(c, "composer/send/able", ready)
  let lit = @sf.ease_to(c, "composer/send/lit", hot)
  let on = @sf.mix(@sf.mix(p.text, send_hot, p.canvas), lit, p.text)
  let ground = @sf.mix(on, able, @sf.over(p.raised, @sf.alpha(p.text, send_off)))
  let b = c.box(style=@sf.round_face().then(@ui.style(bg=Data(ground))), id~, fn() {
    if starting {
      @sf.spinner(c, size=@sf.theme().round.glyph) |> ignore
    } else {
      @sf.icon(c, "arrow-up", size=@sf.theme().round.glyph, color=@sf.mix(p.canvas, able, p.raised)) |> ignore
    }
  })
  c.semantics(b, Button, id~, label=@sf.t("web-main.composer.send"), disabled=!ready)
  b
}

///|
/// What waits to go with the message (ComposerExtras): the quotes, each with a line for what is said about it (the one
/// just added takes the focus; Enter in it goes back to the text), then the files: a picture as its picture, pasted
/// words as their card, a station's file as its card, a link as its card, any other file as its card.
fn composer_extras(c : @ui.Ctx, src : Source, spec : ComposerSpec, w : Writing) -> Unit {
  if w.quotes.length() > 0 {
    c.box(style=quotes_column, fn() {
      for q in w.quotes {
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
        if w.focus != "" && w.focus == id {
          c.focus_editor(key)
          writing_focused(src, w)
        }
        let done = @sf.quote_card(
          c,
          key,
          text(v, "author"),
          text(v, "text"),
          role=text(v, "role"),
          composer=true,
          remove=true,
          // its own picture (an image of a message quoted, a mark's screenshot) in its card as a picture waiting is,
          // where it flies from to its place in the message (flying_quotes)
          picture?=quote_picture(c, src, spec.station, v).map(fn(own) {
            fn() {
              let (picture, f) = own
              let tile = picture_tile(c, picture, going_now(f), gone_up(f), text(f, "error"))
              @motion.measure(c, tile, quote_picture_key(id))
              composing.pictures[id] = picture
            }
          }),
          comment_field=fn() {
            let res = c.editor(
              key,
              placeholder=@sf.t("web-main.quote.commentPlaceholder"),
              font_size=@sf.theme().t.ui,
              line=@sf.theme().t.ui_line,
              max_lines=1,
              plain=true,
              color=@sf.theme().p.text,
              placeholder_color=@sf.theme().p.subtle,
              caret_color=@sf.theme().p.accent,
              field=f,
            )
            if res.text != text(v, "comment") {
              writing_comment(src, w, id, res.text)
            }
            if res.submitted is Some(_) {
              c.focus_editor(composer_field_key)
            }
          },
        )
        held_coming(c, done.card, key)
        // (where it is and its colour: what flies from it as it is sent, flying_quotes)
        @motion.measure(c, done.card, quote_card_key(id))
        composing.grounds[id] = c.node_bg(done.card)
        if done.removed {
          writing_unquote(src, w, id)
        }
      }
    })
    |> ignore
  }
  // (a quote's picture is its own, not among them)
  if w.files.length() > 0 {
    c.box(style=files_flow(), flow=true, line_gap=files_lines(), fn() {
      for f in w.files {
        let i = c.box(fn() { composer_file(c, src, spec, w, f) })
        held_coming(c, i, "composer/file/" + text(Some(f), "id"))
      }
    })
    |> ignore
  }
}

///|
/// What waits in it (a quote's card, a file's: node `i`, keyed `key`) put in while it shows comes in (`@sf.waiting_in`, the
/// web's enterUp on composerQuote, fileCard and composerThumb), the first frame it is built; what a draft opened with,
/// or the composer gone to another page with, is there at once (docs/motion.md: what is on a page does not move of its
/// own as it comes), though said so as it is (built again the frame after, it was there before).
fn held_coming(c : @ui.Ctx, i : Int, key : String) -> Unit {
  @motion.entering(c, i, key + "/in", @sf.waiting_in, at_once=!composing.same_draft)
}

///|
/// One file waiting: a picture shown from here (its bytes) or from the station, pasted words, a station's file named
/// by its path or going as a file, a link, or any other file; each with its ✕, a failed one's ↻ where it can go again.
fn composer_file(c : @ui.Ctx, src : Source, spec : ComposerSpec, w : Writing, f : Json) -> Unit {
  let v = Some(f)
  let id = text(v, "id")
  let key = "composer/file/" + id
  let name = text(v, "name")
  match waiting_picture(src, w, v) {
    Some(picture) => composer_picture(c, src, w, key, id, name, picture, going_now(v), gone_up(v), text(v, "error"))
    None => {
      // as wide as a card is (236), however little the row has: a card hugging its words in a row that wraps had none
      // left for them (its words squeezed to …); its ✕ hung on its corner, as a picture's (@sf.with_corner_remove)
      let removed = @sf.with_corner_remove(c, key, remove_label(v, name), @sf.composer_inner(), w=dmin(@sf.file_card_w, c.width), fn() {
        let said = waiting_card(c, key, v, restore=restorable(w, v))
        match waiting_as(v) {
          // a link: tapped, it opens (Composer.kt LinkCard)
          Link =>
            if said.opened {
              let url = text(field(v, "link"), "url")
              c.tell("composer/link/" + id, fn() { open_link(url) })
            }
          // pasted words: put back as words; failed, made again from them
          Pasted => {
            if said.restored {
              let back = text(field(v, "pasted"), "text")
              let words = if w.text.get() == "" { back } else { w.text.get() + "\n" + back }
              @sfbase.refs_put(w.key, w.field, words)
              writing_text(src, w, words)
              writing_remove(src, w, id)
              c.focus_editor(composer_field_key)
            }
            if said.retried {
              @sfbase.writing_paste_again(src, w, id)
            }
          }
          // a station's file (by its path or as the file): pressed, how it goes (composer_ref.mbt)
          ByPath | AnyFile => {
            if said.opened && field(v, "ref") is Some(Object(_)) {
              c.tell(key + "/ref", fn() { ref_panel(src, w, spec.station, id, name, c.id(key)) })
            }
            if said.retried {
              writing_retry(src, w, id)
            }
          }
        }
      })
      if removed {
        writing_remove(src, w, id)
      }
    }
  }
}

///|
/// A file waiting's picture, if it is drawn as one: the bytes picked or pasted here, else (a draft kept, read again as
/// the app starts) an image's as the device keeps it (`composer.picture`), "" while that is read; None for any other
/// file, and an image the device keeps none of (drawn as a file).
fn waiting_picture(src : Source, w : Writing, v : Json?) -> String? {
  let id = text(v, "id")
  match writing_pictures.get(id) {
    Some(picture) => Some(picture)
    None if file_kind(text(v, "name")) == "image" && waiting_as(v) is AnyFile =>
      match (src.draft_picture)(w.key, id) {
        "!" => None
        kept => Some(kept)
      }
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
  field(field(v, "pasted"), "text") is Some(String(_)) && !w.starting
}

///|
/// A file waiting that is no picture, as its card (`key`), its ✕ aside: what the composer draws (composer_file) and
/// what flies from there as it is sent drawn as it was until it sets off (flying_files).
fn waiting_card(c : @ui.Ctx, key : String, v : Json?, restore~ : Bool) -> @sf.FileCardDone {
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
      )
    // a link shared in (share-in.ts): its title and its site, drawn as a file is (Composer.kt LinkCard); sent as
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
        path=text(done, "path"),
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
/// ↻ over it when it failed (`again` what a tap there is). Its node; `id` what a tap on it is.
fn picture_tile(
  c : @ui.Ctx,
  picture : String,
  pending : Bool,
  part : Double?,
  error : String,
  id? : Int = 0,
  again? : Int = 0,
) -> Int {
  c.box(style=thumb_box().then(if error != "" { thumb_failed } else { thumb_whole }), id~, fn() {
    c.image(picture, w=Px(thumb_side), h=Px(thumb_side), fit=FitCover) |> ignore
    if pending {
      c.layer(fn() {
        c.box(style=thumb_veil, fn() {
          @sf.progress_spinner(c, "composer/going/" + picture, part, size=@sf.theme().round.glyph) |> ignore
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
  let removed = @sf.with_corner_remove(c, key, @sf.t("web-main.file.remove", args=[("name", name)]), @sf.composer_inner(), w=thumb_side, fn() {
    tile.val = picture_tile(c, picture, pending, part, error, id=thumb, again~)
  })
  if removed {
    writing_remove(src, w, id)
  }
  if error != "" {
    if c.clicked(again) {
      writing_retry(src, w, id)
    }
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
      if c.clicked(thumb) {
        @sfbase.keep_read(seen, bytes)
        @sfbase.open_preview(station, "", a)
      }
      @sfbase.note_thumb(c, seen, tile.val, @sf.composer_inner(), picture~)
      // (not drawn while the viewer is its picture: one picture on the screen, never two)
      c.look(tile.val, @ui.look(alpha=@sfbase.thumb_shows(seen)))
    }
    None => ()
  }
}

///|
/// How long it stays a box after it loses the cursor (LET_GO_MS); how long its change of shape takes (morph.ts).
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
/// How many lines the field grows to before it scrolls.
fn text_lines(c : @ui.Ctx) -> Int {
  let n = (dmin(text_most, c.height * text_window_share) / c.style_size(@sf.theme().t.words).1).to_int()
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
fn capsule_h() -> Double {
  let side = @sf.theme().round.side
  @sf.foot_capsule_h(side + 2.0 * capsule_pad_alone, side)
}

///|
/// The capsule further in than the box by `place`'s capsule_in (composer's), from its left, its right and its foot, its
/// round buttons its capsule_pad in.
fn capsule_place(place : ComposerPlace) -> @ui.Style {
  let (l, r, b) = place.capsule_in
  @ui.style(ml=@sf.room_of(l), mr=@sf.room_of(r), mb=@sf.room_of(b), p=@sf.room_of(place.capsule_pad))
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
pub fn composer_place(pane : Double) -> ComposerPlace {
  let d = composer_side()
  if !@sf.in_pane() || composer_width(pane) < pane - 2.0 * d - 0.5 {
    return composer_alone
  }
  let h = capsule_h()
  let (l, r, b) = @sf.foot_capsule(h, @sf.corner_inset, @sf.corner_inset)
  {
    capsule_in: (l - d, r - d, b - d),
    capsule_pad: (h - @sf.theme().round.side) / 2.0,
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
/// The text's room (composerText): 5 over and under, 8 at its end on one line; opened, 8 in and 8 over.
// kept across runs: a value (no field of it changes)
let text_shut : @ui.Style = @ui.style(w=@sf.grow, pr=S2, py=S1_25)

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
let quotes_column : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
/// The files waiting (composerFiles: wrapped, 6 apart, flush with the box's padding); its lines further apart by the
/// reach of a ✕ above what it is hung on (@sf.with_corner_remove), so one on a later line keeps 6 from the line over it.
/// Over the words, at the top of the box: their lines end short of its top right corner (@sf.composer_files_end), so
/// the last of the first one never stands in it off its circle, however wide the box is.
fn files_flow() -> @ui.Style {
  @ui.style(row=true, w=Full, gap=S1_5, pr=@sf.room_of(@sf.composer_files_end()))
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
/// The files of a draft that are up, and its images and videos still going up (drawn where they land from their
/// pictures here: sent_local), flying as it is sent to what each is in its message (file_key: one put up from here, or
/// still going up, its upload; any other its path), each from its tile (ChatHost.kt sending): from where its card or
/// its picture is (its box's, keyed composer/file/<id>), drawn there as the composer draws it until it sets off.
fn flying_files(c : @ui.Ctx, src : Source, w : Writing) -> Array[FlyingFile] {
  let going = going_files(w).map(fn(f) { text(Some(f), "id") })
  w.files.filter_map(fn(f) {
    let v = Some(f)
    let id = text(v, "id")
    let key = flying_key(v, going.contains(id))
    match c.rect_of(c.id("composer/file/" + id)) {
      Some(from) if key != "" => {
        let picture = waiting_picture(src, w, v).unwrap_or("")
        let restore = restorable(w, v)
        let (_, _, wide, _) = from
        Some({
          key,
          from,
          picture,
          // as the composer drew it (composer_file), but its ✕: a new chat's picture waiting for its message not going
          // up, no spinner over it; a card on the composer's ground, as wide as there
          face: fn() {
            let c = @ui.current()
            if picture != "" {
              picture_tile(c, picture, going_now(v), gone_up(v), text(v, "error")) |> ignore
            } else {
              c.box(style=@ui.style(w=Fixed(wide)), fn() { waiting_card(c, "flying/" + id, v, restore~) |> ignore })
              |> ignore
            }
          },
          ground: 0L,
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
  w.quotes.map(fn(q) {
    let v = Some(q)
    let own = field(v, "own")
    let file = match field(own, "done") {
      Some(done) if text(Some(done), "name") != "" => text(Some(done), "name")
      _ => text(own, "name")
    }
    Json::object({
      "author": Json::string(text(v, "author")),
      "text": Json::string(text(v, "text")),
      "comment": Json::string(text(v, "comment").trim(chars=" \n\t").to_string()),
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
/// A quote's own picture, if it is an image or a video (Chat.tsx QuotedThumb, PendingFile), and its file: the picture
/// from here while it is this device's (a mark's screenshot), else the station's (an image of a message quoted; a
/// video's still, as its message draws it: what grows from here to its box there as it is sent, flight.mbt).
fn quote_picture(c : @ui.Ctx, src : Source, station : String, q : Json?) -> (String, Json?)? {
  let own = field(q, "own")
  let kind = file_kind(text(own, "name"))
  guard own is Some(_) && (kind == "image" || kind == "video") else { return None }
  match writing_pictures.get(text(own, "id")) {
    Some(picture) => Some((picture, own))
    None => {
      let done = field(own, "done")
      let owner = text(done, "owner")
      guard owner != "" else { return None }
      if kind == "image" {
        return Some(((src.file)(station, owner, stored_name(text(done, "path"))), own))
      }
      let a = attachment_of(done.unwrap())
      match video_still(c, src, station, owner, a, station + "/" + owner + "/" + a.path) {
        "" | "!" => None
        still => Some((still, own))
      }
    }
  }
}

///|
/// What a file waiting is in the message it goes with (file_key: one put up from here, or one with its picture here
/// still going up (`going`: an image, a video), its upload; any other its path), "" none.
fn flying_key(v : Json?, going : Bool) -> String {
  let id = text(v, "id")
  match field(v, "done") {
    Some(_) if @sfbase.writing_put_here(id) => @sfbase.upload_path(id)
    Some(done) => text(Some(done), "path")
    None if going && writing_pictures.contains(id) => @sfbase.upload_path(id)
    None => ""
  }
}

///|
/// The quotes of a draft, flying as it is sent to their cards in its message (quote_key: each by its place among
/// them), each from its card here (where it is, its colour: what its ground sets out from), drawn there as it was, what
/// is said about it as written, until it sets off; its own picture from its tile in the card to its place in the
/// message's card, as a picture sent goes (flight_files).
fn flying_quotes(c : @ui.Ctx, w : Writing) -> Array[FlyingFile] {
  let flying : Array[FlyingFile] = []
  let going = going_files(w).map(fn(f) { text(Some(f), "id") })
  for i, q in sent_quotes(w) {
    let v = Some(w.quotes[i])
    let id = text(v, "id")
    let own = field(v, "own")
    let picture = match (own, composing.pictures.get(id), @motion.measured_rect(c, quote_picture_key(id))) {
      (Some(_), Some(picture), Some(from)) => {
        let key = flying_key(own, going.contains(text(own, "id")))
        if key != "" {
          Some((key, picture, from))
        } else {
          None
        }
      }
      _ => None
    }
    match @motion.measured_rect(c, quote_card_key(id)) {
      Some((x, y, wide, high)) => {
        let s = @sfbase.quote_of(q)
        flying.push({
          key: @sfbase.quote_key(i),
          from: (x, y, wide, high),
          picture: "",
          face: fn() {
            let c = @ui.current()
            c.box(style=@ui.style(w=Fixed(wide)), fn() {
              @sf.quote_card(
                c,
                "flying/quote/" + id,
                s.author,
                s.text,
                role=s.role,
                comment=s.comment,
                composer=true,
                // (its picture's room: the picture is drawn there flying, over the card)
                picture?=picture.map(fn(p) {
                  let (_, _, pw, ph) = p.2
                  fn() { c.box(style=@ui.style(w=Fixed(pw), h=Fixed(ph)), fn() {  }) |> ignore }
                }),
              )
              |> ignore
            })
            |> ignore
          },
          ground: composing.grounds.get(id).unwrap_or(0L),
        })
      }
      None => ()
    }
    match (own, picture) {
      (Some(f), Some((key, picture, from))) =>
        flying.push({
          key,
          from,
          picture,
          face: fn() {
            picture_tile(@ui.current(), picture, going_now(Some(f)), gone_up(Some(f)), text(Some(f), "error")) |> ignore
          },
          ground: 0L,
        })
      _ => ()
    }
  }
  flying
}

///|
/// What is written sent into chat `r` (`v` its view: its thread, what is in it now; sendDraft, draft.ts send): in the
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
  let words = w.text.get().trim(chars=" \n\t").to_string()
  let rk = r.station + "\u{1}" + r.session
  // (its references as the field's marks till the core makes them links: drawn as the field drew them)
  let marks = @sfbase.refs_sent_marks(w.key, words)
  let row = sent_local(rk, Some(v), words, up_files(w), going=going_files(w), quotes=sent_quotes(w), marks~)
  // its words take off from the field as they are (before it is emptied), the composer (its box and its room) held as
  // tall as it is till they let go of it
  let room = @motion.measured(c, "composer/foot").unwrap_or(0.0)
  let box = @motion.measured(c, "composer/content").unwrap_or(0.0)
  // its quotes fly too, each from its card, and its files that are up, each from its tile (ChatHost.kt sending)
  let flying = flying_quotes(c, w) + flying_files(c, src, w)
  @sfbase.flight_start(
    c,
    w.key,
    rk,
    row,
    words,
    room,
    flying,
    field=composer_field_key,
    hold=fn(ms) { composer_hold(w.key, room, box, ms) },
    desk=true,
    marks~,
  )
  // the chat's list to its end, where the row is (gliding there while nothing flies to it); shown short of the chat's
  // end, its latest page in place of what was read, the row at its end
  c.list_to_end("chat/" + r.station + "/" + r.session, glide=@sfbase.flight_of(w.key) is None)
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
/// What was sent from draft `draft`'s composer holds it as tall as it was, its box (`box`) and its room (`room`), for
/// `ms`: the words are in it till then, and it comes down as they let go of it, not from under them as they set out
/// (ChatHost.kt hold; dock.tsx: the list's foot kept where it was till the message's row is in). Then its box is laid
/// out as it is, its ground going down to that (composer's reshape, for this), and its room down on the same curve.
fn composer_hold(draft : String, room : Double, box : Double, ms : Double) -> Unit {
  let c = @ui.current()
  @motion.anim(c, "composer/held/" + draft, 0.0, global=true).snap(room)
  let a = @motion.anim(c, "composer/hold/" + draft, 0.0, global=true)
  a.snap(1.0)
  // (down on the flight's clock of what was sent, as its ground does: composer_let_go)
  // det-ok(motion-length): words sent's own, set with their flight (docs/motion.md kind 4)
  a.animate(0.0, @motion.tween(@sfbase.sent_down_of(draft), ease=Move, delay=ms))
  let b = @motion.anim(c, "composer/held-box/" + draft, 0.0, global=true)
  b.snap(box)
  b.animate(0.0, @motion.Snap(ms))
}

///|
/// The least room a chat's composer takes at its page's foot: as tall as it takes opened with one line where it is
/// (its box that tall, what is round it as it is).
fn composer_least(c : @ui.Ctx) -> Double {
  let foot = @motion.measured(c, "composer/foot").unwrap_or(capsule_room(c.width))
  match @motion.measured(c, "composer/content") {
    Some(box) => foot - box + composer_open_box()
    None => composer_open_room(c.width)
  }
}

///|
/// The room under a chat's list for draft `draft`'s composer, `room` as its page has it (composer_room's): let go by
/// words sent from it, where it comes to stand (opened with one line, emptied), the list's foot going there on the
/// list's way as they leave it, one move with their row (sfbase's shown_rows, which says when: `let_go`); else as
/// it is.
pub fn composer_foot_room(c : @ui.Ctx, draft : String, room : Double, let_go~ : Bool) -> Double {
  if let_go {
    dmax(room - dmax(composer_room(c, draft) - composer_least(c), 0.0), 0.0)
  } else {
    room
  }
}

///|
/// How long the composer takes to open from a capsule or to be let go to one: its field passing by its ＋ and send is
/// kept off them on this clock (composer_hint_wbtest).
let composer_shape_ms : Double = 300.0

///|
/// Whether the composer opens or is let go this frame: `head` (how roomy, a box or not) other than as the frame began.
fn composer_opening(c : @ui.Ctx, head : String) -> Bool {
  let (frame, was, now) = composing.opened
  let was = if frame != c.frame_number() { now } else { was }
  composing.opened = (c.frame_number(), was, head)
  was != "" && was != head
}

///|
/// Whether draft `draft`'s composer is let go by words sent from it now (composer_hold: from as they let go of it till
/// it is down, its declared end), its ground going down with its room.
fn composer_let_go(c : @ui.Ctx, draft : String) -> Bool {
  let a = @motion.anim(c, "composer/hold/" + draft, 0.0, global=true)
  a.target() == 0.0 && !a.over()
}

///|
/// How tall draft `draft`'s composer box is held for words sent from it, while they are in it (composer_hold); 0 when
/// it is not.
fn composer_held_box(c : @ui.Ctx, draft : String) -> Double {
  @motion.anim(c, "composer/held-box/" + draft, 0.0, global=true).get()
}

///|
/// How much room draft `draft`'s composer takes at its page's foot (what the list leaves free under its last row): as
/// tall as its place (chat_composer: its box, what it says under it, its margins) with its ground as drawn (a line
/// more or less: the list's rows go with the ground as it reshapes, the frame it does), at least as tall as that opened
/// with one line; let go by words sent from it (composer_hold), from as tall as it was then down to that, on its
/// ground's curve.
pub fn composer_room(c : @ui.Ctx, draft : String, settled? : Bool = false) -> Double {
  // (not laid out yet: a capsule's)
  let foot = @motion.measured(c, "composer/foot").unwrap_or(capsule_room(c.width))
  // never less than it takes opened with one line where it is (its box that tall, what is round it as it is: the web's
  // --composer-room, max(the composer's height, an opened one-line composer's)): opened or let go, a capsule or a box,
  // the list keeps its words where they are; only a line more, a file, a quote, what is said over it move them
  let least = composer_least(c)
  // (`settled`: as it comes to stand, not where its shape is on its way: a new chat become its chat, the composer
  // coming down from the middle of the pane to its foot, the chat's rows standing over its foot from the first, not over
  // the middle of the pane where the new chat's scene still is)
  let now = dmax(foot + (if settled { 0.0 } else { @motion.reshaped_over(c, "composer/box") }), least)
  let held = @motion.anim(c, "composer/held/" + draft, 0.0, global=true).get()
  let share = @motion.anim(c, "composer/hold/" + draft, 0.0, global=true).get()
  if held > now {
    now + (held - now) * share
  } else {
    now
  }
}

///|
/// A chat's composer at its pane's foot (dock.tsx's chat place; cloud.css.ts composerWrap: 12 over it, 16 under it;
/// dock.css.ts: 12 clear of the pane's sides, the column and its curve wide at most, in the middle): the chat's draft
/// (ChatPage.tsx chatKey), what it sends going into the chat (send_in_chat), locked while the chat is archived, no
/// file taken in while its station is down. Its place measured (composer_room). `apart`: the page a panel of its own (the
/// frame's tape), the composer as far from its foot as from its sides.
pub fn chat_composer(c : @ui.Ctx, src : Source, ws : Workspace, r : ChatRef, v : ChatView?, apart? : Bool = false) -> Unit {
  let spec : ComposerSpec = {
    station: r.station,
    draft: r.station + ":" + r.session,
    session: r.session,
    placeholder: @sf.t(if v.map(fn(v) { v.archived }).unwrap_or(false) {
      "web-main.chat.archivedPlaceholder"
    } else {
      "web-main.composer.placeholder"
    }),
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
    locked: match v {
      Some(v) => v.archived
      None => false
    },
    offline: match v {
      Some(v) => v.offline
      None => false
    },
  }
  let width = composer_width(c.width)
  let place = if apart { composer_place(c.width) } else { composer_alone }
  let foot = c.box(style=chat_foot_top.then(@ui.style(pb=@sf.room_of(composer_foot_in(c.width)))), fn() {
    match v {
      Some(v) => chat_notices(c, src, r, v, width)
      None => ()
    }
    c.box(style=@ui.style(w=Fixed(width)), fn() {
      c.sized(width, c.height, fn() {
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
      })
    })
    |> ignore
  })
  @motion.measure(c, foot, "composer/foot")
}

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
  let marks : Map[String, (@ui.Ctx, Double) -> Unit] = {}
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
          c.tell("composer/cc", fn() { (src.call)("chat.cc", params, fn(_) {  }) })
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
let cc_trigger : @ui.Style = @ui.css(
  #|row h=S7 px=S2 gap=S1_5 radius=Lg align=ACenter hovered{bg=Hover} selected{bg=Hover}
)

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
  // (built before its composer: whether this chat's composer was drawn the frame before, as the composer has it once
  // it is built in this frame, or as it left it)
  let whose = "\u{1}" + r.session
  composing.notices_new = if composing.frame == c.frame_number() {
    composing.draft_before == whose
  } else {
    composing.draft == whose
  }
  if v.archived {
    let restore = c.id("composer/restore")
    let busy = composing.restoring.contains(key)
    if !busy && !v.offline {
      if !src.read_only && c.clicked(restore) {
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
            match res {
              Err(e) => composing.restore_errors[key] = error_words(e)
              Ok(_) => ()
            }
          })
        })
      }
    }
    composer_notice(
      c,
      width,
      "archive",
      @sf.t("web-main.archived.notice"),
      Some((restore, if busy { "web-main.archived.restoring" } else { "web-main.archived.restore" }, "web-main.archived.restore", busy || v.offline)),
      failed=composing.restore_errors.get(key),
      chat=key,
    )
  }
  match v.cache_cold {
    Some((session, said, afresh)) if !v.archived => {
      let go_on = c.id("composer/goOn")
      let fresh = c.id("composer/afresh")
      let doing = "session.settings/" + r.station + "/" + session
      let busy = @sfbase.doing(doing)
      // (the one not taken, pressed: taken from its next start)
      let (other, words) = if afresh { (go_on, "web-main.chat.goOn") } else { (fresh, "web-main.chat.afresh") }
      if !busy && !v.offline && c.clicked(other) {
        let params : Json = { "station": Json::string(r.station), "key": Json::string(session), "afresh": Json::boolean(!afresh) }
        c.tell("composer/afresh", fn() { @sfbase.act(src, @sf.t(words), doing, "session.settings", params) })
      }
      composer_notice(c, width, "wait", said, None, chat=key, choices=[(go_on, "web-main.chat.goOn", !afresh), (fresh, "web-main.chat.afresh", afresh)], held=busy || v.offline)
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
    composer_notice(c, width, "unplug", said, None, icon=if v.updating { "updating" } else { "unplug" }, chat=key)
  }
  notices_gone(c, width, key, [v.archived, v.cache_cold is Some(_) && !v.archived, v.offline])
}

///|
/// The notices over chat `chat`'s composer no longer said (`now`: whether each of archive, wait, unplug is), drawn as
/// they were while they leave (composer_notice).
fn notices_gone(c : @ui.Ctx, width : Double, chat : String, now : Array[Bool]) -> Unit {
  for i, mark in ["archive", "wait", "unplug"] {
    if now[i] {
      continue
    }
    match composing.notices_said.get("composer/notice/" + chat + "/" + mark) {
      Some((said, offer, failed, icon, choices)) => {
        let offer = offer.map(fn(o) { (o.0, o.1, o.2, true) })
        composer_notice(c, width, mark, said, offer, failed?=failed, icon~, chat~, gone=true, choices~, held=true)
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
/// the screen, whether it is out of reach) in the words' colour, a step heavier, or a choice of two or more
/// (`choices`: each its target, its words' key, whether it is the one taken: that one marked ✓ in the words' colour, the
/// others quiet, pressed to take them; `held`, out of reach); why what it offers failed (`failed`) under its words, red.
fn composer_notice(
  c : @ui.Ctx,
  width : Double,
  mark : String,
  said : String,
  offer : (Int, String, String, Bool)?,
  failed? : String?,
  icon? : String,
  chat? : String = "",
  gone? : Bool = false,
  choices? : Array[(Int, String, Bool)] = [],
  held? : Bool = false,
) -> Unit {
  let icon = icon.unwrap_or(mark)
  // shown while its chat is, it comes in as what is put in the composer does, one its chat opens with there at once;
  // gone, it leaves as a row of a list does, drawn as it was (notices_gone)
  let key = "composer/notice/" + chat + "/" + mark
  if !gone {
    composing.notices_said[key] = (said, offer, failed, icon, choices)
  }
  let look = @motion.presence(c, key, !gone, initial=composing.notices_new, enter=@sf.waiting_in, exit=@sf.leave)
  if gone && look is None {
    composing.notices_said.remove(key)
    return
  }
  let t = @sf.theme()
  // its mark over the composer's ＋, in the middle of its round start: in a square as high as it is (a line and its
  // padding), its ends drawn in from the composer's as far as that takes (2026-10-29 the user: 圆角往里缩, 图标依然对准
  // 加号; as wide as the composer, its mark stood 7.5 off the middle of its round end)
  let side = t.t.meta_line + 2.0 * composer_notice_pad
  // (the ＋'s middle as the composer draws it: its round control's, a point wider for the capsule's edge line, its
  // capsule_pad_alone in; measured, 24.5 in from the composer's edge)
  let inset = capsule_pad_alone + (t.round.side + 1.0) / 2.0 - side / 2.0
  let drawn_in = width - 2.0 * inset
  // round as a line of it is high: a capsule while its words fit one line; wrapped, its corners still that round start,
  // its mark in it on its first line (round all its height, 3 lines made it a blob, its mark halfway down)
  let round = @ui.style(w=Fixed(drawn_in), radius=@sf.line_capsule_corner(side))
  let b = c.box(style=composer_notice_box.then(round), glass=@sf.glass_floating(), fn() {
    c.box(style=composer_notice_line, fn() {
      c.box(style=@ui.style(w=Fixed(side), h=Fixed(t.t.meta_line), align=ACenter, justify=JCenter), fn() {
        // (its station gone for its update: the update's mark, turning)
        if icon == "updating" {
          @sf.updating_mark(c, composer_notice_mark, t.p.muted) |> ignore
        } else {
          @sf.icon(c, icon, size=composer_notice_mark, color=t.p.muted) |> ignore
        }
      })
      |> ignore
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
      if choices.length() > 0 {
        c.box(style=composer_notice_choices, fn() {
          for choice in choices {
            let (id, words, taken) = choice
            let b = c.box(id~, style=composer_notice_choice, fn() {
              if taken {
                @sf.icon(c, "check", size=composer_notice_check, color=t.p.text) |> ignore
              }
              c.text(@sf.t(words), style=if taken { composer_notice_button } else { composer_notice_other }) |> ignore
            })
            c.semantics(b, Radio, id~, label=@sf.t(words), check=if taken { On } else { Off }, disabled=held && !taken)
          }
        })
        |> ignore
      }
    })
    |> ignore
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
/// A choice a line offers: 12 from its words, its options 12 apart.
// kept across runs: a value (no field of it changes)
let composer_notice_choices : @ui.Style = @ui.css("row pl=S3 gap=S3")

///|
/// An option of it: the one taken with its ✓ 4 before its words, across their middle.
// kept across runs: a value (no field of it changes)
let composer_notice_choice : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
/// An option not taken: as quiet as its words, not a step heavier.
// kept across runs: a value (no field of it changes)
let composer_notice_other : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted)

///|
/// How big the ✓ of the option taken is.
let composer_notice_check : Double = 12.0

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
/// controls) 8 in, 12 over it and its foot's room under it (composer_foot_in).
fn capsule_room(pane : Double) -> Double {
  @sf.theme().round.side + 2.0 * 8.0 + 12.0 + composer_foot_in(pane)
}

///|
/// The room a chat's composer takes opened with one line at the foot of a pane `pane` wide (its box, composer_open_box;
/// 12 over it and its foot's room under it, composer_foot_in): what a list that keeps its words in place as the
/// composer closes keeps clear at least (ChatHost.kt roomForList).
pub fn composer_open_room(pane : Double) -> Double {
  composer_open_box() + 12.0 + composer_foot_in(pane)
}

///|
/// How far a chat's composer stands from the foot of a pane `pane` wide (over the system's navigation bar, which is the
/// page's): where it reaches across it, as far as from its sides (composer_side), the four sides of what it stands in
/// alike (a phone's screen, a panel of its own: there in its corners, InnerOr); in a pane wider than it (a wide column,
/// the composer 804 at most in its middle) the web's 16 (dock.css.ts).
pub fn composer_foot_in(pane : Double) -> Double {
  let d = composer_side()
  if composer_width(pane) >= pane - 2.0 * d - 0.5 {
    d
  } else {
    composer_foot_wide
  }
}

///|
let composer_foot_wide : Double = 16.0

///|
/// Its box opened with one line (composer_open_room without what is over and under it): as composer_box_open lays it
/// out, its padding over the line (text_open: 8 over it), its parts 10 apart, its buttons' row as far from its foot as
/// makes them concentric with its corners (tools_row).
fn composer_open_box() -> Double {
  let t = @sf.theme()
  @sf.composer_pad + (8.0 + @ui.current().style_size(t.t.words).1) + 10.0 + t.round.side + @sf.composer_round_in()
}

///|
/// A chat's foot: 12 over the composer, its room under it its pane's (composer_foot_in).
// kept across runs: a value (no field of it changes)
let chat_foot_top : @ui.Style = @ui.css("w=Full pt=S3 align=ACenter")
