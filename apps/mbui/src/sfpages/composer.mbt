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
/// the page's choices in its row (a new chat's), laid out roomy (its text over its row even for one line), locked (it
/// takes words, nothing goes), its station offline (no file taken in).
pub(all) struct ComposerSpec {
  station : String
  draft : String
  session : String
  placeholder : String
  toolbar : (() -> Unit)?
  /// what it says before send on one line, nothing written (where a chat's messages are copied: each thread's mark,
  /// "slack" or "feishu", and its place): nothing to press; empty nothing
  note : Array[(String, String)]
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
  mut let_go : Bool
  warmed : Map[String, Int]
  comments : Map[String, @ui.Field]
  mut roomy : Bool?
  mut draft : String
  /// as the frame before left them (the frame each build of this one starts from: frame_body may build it twice), and
  /// that frame's number
  mut roomy_before : Bool?
  mut draft_before : String
  mut frame : Int
  /// the page's choices in its row as it was last drawn, as the frame before left them, and those of the page it came
  /// from that this one has not, while they leave (a new chat's, gone to its chat)
  mut toolbar : (() -> Unit)?
  mut toolbar_before : (() -> Unit)?
  mut toolbar_leaving : (() -> Unit)?
  restoring : Map[String, Bool]
  restore_errors : Map[String, String]
  /// a finger went down outside it (keyboard_let_go); its `@` menu up over it as it was last drawn (a press in it is
  /// the composer's own)
  mut outside : Bool
  mut menu_up : Bool
  /// its 抄送 menu open (cc_chooser)
  mut cc_open : Bool
  /// the cursor asked into it as it is next drawn, on any screen (composer_take_focus)
  mut wanted : Bool
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
  let_go: false,
  warmed: {},
  comments: {},
  roomy: None,
  draft: "",
  roomy_before: None,
  draft_before: "",
  frame: -1,
  toolbar: None,
  toolbar_before: None,
  toolbar_leaving: None,
  restoring: {},
  restore_errors: {},
  outside: false,
  menu_up: false,
  cc_open: false,
  wanted: false,
}

///|
fn composing_reset() -> Unit {
  composing.picking = None
  composing.let_go = false
  composing.warmed.clear()
  composing.comments.clear()
  composing.roomy = None
  composing.draft = ""
  composing.roomy_before = None
  composing.toolbar = None
  composing.toolbar_before = None
  composing.toolbar_leaving = None
  composing.draft_before = ""
  composing.frame = -1
  composing.restoring.clear()
  composing.restore_errors.clear()
  composing.outside = false
  composing.menu_up = false
  composing.cc_open = false
  composing.wanted = false
}

///|
/// The composer's text field (its words, a flight's from: flight.mbt), its box, what is in it.
pub let composer_field_key : String = "composer/field"

///|
/// The composer (ComposerView) for `spec`, `send` what pressing send (or Enter) does with what is written once it is
/// ready. Drawn where its place is; a page lays it out (its width: composer_width). `capsule_in`: at a panel's foot,
/// how much further in than its box its capsule stands from its left, its right and its foot (composer_capsule_in:
/// each shape where it stands concentric with the corners it is in, the morph between them).
pub fn composer(
  c : @ui.Ctx,
  src : Source,
  ws : Workspace,
  spec : ComposerSpec,
  send : (Writing) -> Unit,
  capsule_in? : (Double, Double, Double) = (0.0, 0.0, 0.0),
) -> Unit {
  let p = @sf.theme().p
  let w = writing(src, spec.draft)
  let no_files = spec.locked || spec.offline
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
  }
  if whose != composing.draft {
    composing.draft = whose
    if @sf.native_input() is Mouse && !c.field_focused() {
      c.focus_editor(composer_field_key)
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
    }
  }
  let focused = c.editor_focused(composer_field_key)
  // a box while it has the cursor; lost, a capsule a moment later (LET_GO_MS)
  if focused {
    composing.let_go = true
  }
  let lost_long = @kit.after(c, "composer/let-go", !focused, let_go_ms)
  let held = composing.let_go && !focused && !lost_long
  if lost_long {
    composing.let_go = false
  }
  let multiline = spec.roomy ||
    focused ||
    held ||
    w.text != "" ||
    w.files.length() > 0 ||
    w.quotes.length() > 0
  // ready as the core says, or as soon as there are words in the field: the core's say comes a moment after them (its
  // topic), and send pressed meanwhile is not lost (what goes is the core's to take: composer.take, nothing taken
  // nothing sent)
  let ready = (w.ready || (w.text.trim() != "" && !w.starting)) && !spec.locked
  // sent once what it refers to can be read in this workspace (OutsideShare.tsx, sfbase's outside.mbt): at once when
  // it refers to nothing of another workspace, else once the viewer has said so (outside.mbt's dialog)
  @sfbase.sharing_go(w.key)
  let submit = fn() {
    if ready {
      @sfbase.send_sharing(src, w.key, spec.station, w.text.trim(chars=" \n\t").to_string(), fn() { send(w) })
    }
  }
  outside_dialog(c, src, w.key)
  let cap = c.id("composer/cap")
  if c.clicked(cap) && !spec.locked {
    c.focus_editor(composer_field_key)
  }
  // dragged over: marked (the 文件 tab's rows; files from the computer the page takes)
  let dragging = !no_files && (@sfbase.drag_carried.val)() is Some(_) && c.lit(cap)
  // laid out for another page than the frame before (a new chat's roomy in the page, a chat's at its foot: dock.tsx)
  let moved = match composing.roomy_before {
    Some(was) => was != spec.roomy
    None => false
  }
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
  let box = c.box(
    style=if multiline { composer_box_open } else { composer_box.then(capsule_place(capsule_in)) },
    // (the raised ground's glass, the accent's over it while dragged over)
    glass=@sf.glass_floating(tint?=if dragging { Some(@sf.alpha(p.accent, drag_tint)) } else { None }),
    id=cap,
    fn() {
      if multiline {
        composer_extras(c, src, spec, w)
        words = composer_text(c, src, ws, spec, w, cap, multiline, submit)
        c.box(style=tools_row(), fn() {
          plus = attach(c, src, spec, w, no_files)
          match (spec.toolbar, composing.toolbar_leaving) {
            (Some(f), _) => chosen = c.box(style=choices, f)
            (None, Some(f)) => {
              chosen = c.box(style=choices, fn() { c.hidden_from_semantics(f) })
              c.look(chosen, @ui.look(alpha=1.0 - fade.get()))
              c.draw_only(chosen)
            }
            (None, None) => c.box(style=tools_gap, fn() {  }) |> ignore
          }
          send_i = send_button(c, ready, w.starting, submit)
        })
        |> ignore
      } else {
        plus = attach(c, src, spec, w, no_files)
        words = composer_text(c, src, ws, spec, w, cap, multiline, submit)
        if spec.note.length() > 0 {
          c.box(style=cc_note_box, fn() { cc_places(c, spec.note) }) |> ignore
        }
        send_i = send_button(c, ready, w.starting, submit)
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
  // on it. Moved by nothing of these (the window, the sidebar, a keyboard), or another chat's on the same page (what it
  // holds swapped, not changed), it is where it is laid out at once (docs/motion.md)
  composing.roomy = Some(spec.roomy)
  let holds = if whose != composing.draft_before && !moved {
    ""
  } else {
    "\{spec.roomy}|\{multiline}|\{w.files.length()}|\{w.quotes.length()}|\{w.error != ""}|" + w.field.text()
  }
  let shape = @motion.tween(if moved { page_move_ms } else { morph_ms }, ease=Out)
  @motion.reshape(c, box, "composer/box", by=holds, spec=shape, carry=moved)
  for part in [(plus, "plus"), (words, "words"), (send_i, "send"), (chosen, "choices")] {
    if part.0 >= 0 {
      @motion.layout(c, part.0, "composer/part/" + part.1, spec=shape, by=holds)
    }
  }
  // with a finger: a press outside it lets go of the keyboard once lifted or moved on (reading on)
  if @ui.pointing() is Finger {
    keyboard_let_go(c, cap)
  }
  @motion.measure(c, box, "composer/content")
  if w.error != "" {
    c.box(style=error_box, fn() { c.text(w.error, style=composer_error_words) |> ignore }) |> ignore
  }
}

///|
/// A finger down outside the composer (`cap`), nothing over it presented (its `@` menu, a sheet), lets go of the
/// keyboard once lifted or moved on; lifted after a long press (not a tap) the keyboard stays (still.fail's Android
/// app's Keyboard.kt letsGoOfKeyboard).
fn keyboard_let_go(c : @ui.Ctx, cap : Int) -> Unit {
  let press = c.press()
  if press.fresh {
    let within = match c.rect_of(cap) {
      Some((x, y, w, h)) => press.x >= x && press.x < x + w && press.y >= y && press.y < y + h
      None => false
    }
    composing.outside = !within && !@sf.presenting() && !composing.menu_up
  }
  if composing.outside && c.editor_focused(composer_field_key) && (press.moved || (press.lifted && !press.long)) {
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
              "file": Json::string(name),
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
      let now = w.text
      let said = if now.trim() == "" { words } else { now.trim_end().to_owned() + "\n" + words }
      w.field.set(said)
      c.tell("composer/followed/" + w.key, fn() { writing_text(src, w, said) })
      c.focus_editor(composer_field_key)
    }
    None => ()
  }
  // pictures marked for this chat (a service's page, an image viewed: sfbase's marked_into), each going up as a file
  // with a quote per mark (what is said of it its comment); taken once, whichever build takes them
  match marked_into.get(w.key) {
    Some(list) if !no_files => {
      marked_into.remove(w.key)
      c.tell("composer/marked/" + w.key, fn() {
        for x in list {
          let (name, bytes, quotes, kind) = x
          writing_add(src, w, spec.station, name, bytes)
          for q in quotes {
            writing_quote(src, w, {
              "author": Json::string(q.0),
              "text": Json::string(q.1),
              "comment": Json::string(q.2),
              "role": Json::string(kind),
              "file": Json::string(if kind == "page" { name } else { "" }),
            })
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
  submit : () -> Unit,
) -> Int {
  let p = @sf.theme().p
  let prefs = (src.topic)("prefs", {}).value
  let hint = space_hint(c, prefs, spec.locked)
  // words sent leave the field emptied: its hint gone while they are still over it, back once they are out of it
  // (madeChat.ts data-made-hint, flight.mbt)
  let hint_in = @motion.anim(c, "composer/hint", 1.0)
  if @sfbase.flight_hint_away(c, w.key) {
    hint_in.snap(0.0)
  } else {
    hint_in.follow(1.0, @motion.tween(@sf.hint_back_ms, ease=Arrive))
  }
  let no_files = spec.locked || spec.offline
  // what the field was given since the last frame, as the core reads it (a mark taken whole, a chat's link pasted)
  @sfbase.refs_edits(c, src, w.key, w.field, spec.station, spec.locked)
  c.box(style=if multiline { text_open } else { text_shut }, fn() {
    let res = c.editor(
      composer_field_key,
      placeholder=if hint != "" { hint } else { spec.placeholder },
      words=true,
      font_size=@sf.theme().t.input,
      line=@sf.theme().t.input_line,
      trim=true,
      max_lines=text_lines(c),
      plain=true,
      color=p.text,
      placeholder_color=@sf.alpha(p.subtle, hint_in.get()),
      caret_color=p.accent,
      enter_sends=@sf.native_input() is Mouse,
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
        if words != w.text {
          writing_text(src, w, words)
        }
        submit()
      }
      None =>
        if res.text != w.text && !w.starting {
          writing_text(src, w, res.text)
          warm(c, src, spec)
        }
    }
    // nothing typed: the chat above or below, as the list shows them now
    if res.focused && w.text == "" && !(@sfbase.neighbour_held.val)() && !menu {
      if c.key_pressed(@ui.key_code_up, in_field=true) {
        (@sfbase.neighbour_go.val)(src, ws, -1)
      } else if c.key_pressed(@ui.key_code_down, in_field=true) {
        (@sfbase.neighbour_go.val)(src, ws, 1)
      }
    }
  })
}

///|
/// What the box says instead of its placeholder with keyboard and mouse and nothing that takes keys focused: that the composer's
/// key puts the cursor there ("" otherwise).
fn space_hint(c : @ui.Ctx, prefs : Json?, locked : Bool) -> String {
  if locked || (@sf.native_input() is Finger) || c.field_focused() {
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
    c.cursor(id, Hand)
    @sf.tip(c, "composer/plus", id, @sf.t("web-main.composer.attach"), shortcut="composer.file")
    // on a touch system the phone's sheet of what can go in (attach.mbt), with keyboard and mouse the system's picker at once
    if c.clicked(id) {
      if @sf.native_input() is Finger {
        attach_open(id, src, w.key)
      } else {
        pick_files(w)
      }
    }
  }
  ignore(spec)
  // (a finger reaches it from round it, the system's least target: @ui's finger_reach)
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
/// ink faint over the box's ground while not; a turning ring while a new chat is made for it.
fn send_button(c : @ui.Ctx, ready : Bool, starting : Bool, submit : () -> Unit) -> Int {
  let p = @sf.theme().p
  let id = c.id("composer/send")
  let hot = ready && c.lit(id)
  if ready {
    c.cursor(id, Hand)
    if c.clicked(id) {
      submit()
    }
  }
  @sf.tip(c, "composer/send", id, @sf.t("web-main.composer.send"))
  let ground = if hot {
    @sf.mix(p.text, send_hot, p.canvas)
  } else if ready {
    p.text
  } else {
    @sf.over(p.raised, @sf.alpha(p.text, send_off))
  }
  let b = c.box(style=@sf.round_face().then(@ui.style(bg=Data(ground))), id~, fn() {
    if starting {
      @sf.spinner(c, size=@sf.theme().round.glyph) |> ignore
    } else {
      @sf.icon(c, "arrow-up", size=@sf.theme().round.glyph, color=if ready { p.canvas } else { p.raised }) |> ignore
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
        if w.focus == id {
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
        if done.removed {
          writing_unquote(src, w, id)
        }
      }
    })
    |> ignore
  }
  // the files but those shown in their quotes' cards
  let own = w.quotes.filter_map(fn(q) {
    match text(Some(q), "file") {
      "" => None
      n => Some(n)
    }
  })
  let rest = w.files.filter(fn(f) { !own.contains(text(Some(f), "name")) })
  if rest.length() > 0 {
    c.box(style=files_flow, flow=true, line_gap=files_lines, fn() {
      for f in rest {
        composer_file(c, src, spec, w, f)
      }
    })
    |> ignore
  }
}

///|
/// One file waiting: a picture shown from here (its bytes) or from the station, pasted words, a station's file named
/// by its path or going as a file, a link, or any other file; each with its ✕, a failed one's ↻ where it can go again.
fn composer_file(c : @ui.Ctx, src : Source, spec : ComposerSpec, w : Writing, f : Json) -> Unit {
  let v = Some(f)
  let id = text(v, "id")
  let key = "composer/file/" + id
  let name = text(v, "name")
  let error = text(v, "error")
  let done = field(v, "done")
  let pending = done is None && error == ""
  match writing_pictures.get(id) {
    Some(picture) => composer_picture(c, src, w, key, id, name, picture, pending, error)
    None => {
      // as wide as a card is (236), however little the row has: a card hugging its words in a row that wraps had none
      // left for them (its words squeezed to …); its ✕ hung on its corner, as a picture's (@sf.with_corner_remove)
      let removed = @sf.with_corner_remove(c, key, remove_label(v, name), @sf.message_file_corner, w=dmin(@sf.file_card_w, c.width), fn() {
        let ref_ = field(v, "ref")
        let said = match ref_ {
          // named by its path: its station and that it goes as a path, its card the named one's (RefCard)
          Some(Object(_)) if text(ref_, "mode") != "file" =>
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
          // a link shared in (share-in.ts): its title and its site, drawn as a file is; tapped, it opens (Composer.kt
          // LinkCard); sent as words, nothing going up
          _ if field(v, "link") is Some(Object(_)) => {
            let l = field(v, "link")
            let url = text(l, "url")
            let card = @sf.file_card(
              c,
              key,
              url,
              0.0,
              open=true,
              title=match text(l, "title") {
                "" => url
                t => t
              },
              meta=text(l, "site"),
              composer=true,
            )
            if card.opened {
              c.tell("composer/link/" + id, fn() { open_link(url) })
            }
            card
          }
          // pasted words (PendingFile's pasted card): what they begin with, how many, put back as words while not too
          // long; failed, made again from them
          _ if field(v, "pasted") is Some(Object(_)) => {
            let info = field(v, "pasted")
            let can_restore = field(info, "text") is Some(String(_)) && !w.starting
            let card = @sf.file_card(
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
              restore=can_restore,
              composer=true,
            )
            if card.restored {
              let words = if w.text == "" { text(info, "text") } else { w.text + "\n" + text(info, "text") }
              @sfbase.refs_put(w.key, w.field, words)
              writing_text(src, w, words)
              writing_remove(src, w, id)
              c.focus_editor(composer_field_key)
            }
            if card.retried {
              @sfbase.writing_paste_again(src, w, id)
            }
            { ..card, retried: false }
          }
          // (a station's folder going as the file: the zip it goes as, RefCard's `${name}.zip`)
          _ =>
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
        // a station's file (by its path or as the file): pressed, how it goes (composer_ref.mbt)
        if said.opened && field(v, "ref") is Some(Object(_)) {
          c.tell(key + "/ref", fn() { ref_panel(src, w, spec.station, id, name, c.id(key)) })
        }
        if said.retried {
          writing_retry(src, w, id)
        }
      })
      if removed {
        writing_remove(src, w, id)
      }
    }
  }
  ignore(spec)
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
/// A picture waiting (composerThumb): its own picture from here, a turning ring over it while it goes up, red-edged
/// when it failed (↻ over it); its ✕ on its corner (@sf.with_corner_remove); its name its tip.
fn composer_picture(
  c : @ui.Ctx,
  src : Source,
  w : Writing,
  key : String,
  id : String,
  name : String,
  picture : String,
  pending : Bool,
  error : String,
) -> Unit {
  let thumb = c.id(key)
  let again = c.id(key + "/retry")
  @sf.tip(c, key + "/tip", thumb, if error != "" { error } else { name })
  // (its picture's box, its ✕ hung on its corner as every waiting file's)
  let tile = Ref(-1)
  let removed = @sf.with_corner_remove(c, key, @sf.t("web-main.file.remove", args=[("name", name)]), thumb_corner, w=thumb_side, fn() {
    tile.val = c.box(style=if error != "" { thumb_failed } else { thumb_box }, id=thumb, fn() {
      c.image(picture, w=Px(thumb_side), h=Px(thumb_side), fit=FitCover) |> ignore
      if pending {
        c.layer(fn() { c.box(style=thumb_veil, fn() { @sf.spinner(c, size=@sf.theme().round.glyph) |> ignore }) |> ignore })
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
  })
  if removed {
    writing_remove(src, w, id)
  }
  if error != "" {
    c.cursor(again, Hand)
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
      }
      // the viewer's id of it (its station, no session, its path), its tile kept for it to fly from
      let seen = station + "//" + a.path
      c.cursor(thumb, Hand)
      if c.clicked(thumb) {
        @sfbase.keep_read(seen, bytes)
        @sfbase.open_preview(station, "", a)
      }
      @sfbase.note_thumb(c, seen, tile.val, thumb_corner, picture~)
      // (not drawn while the viewer is its picture: one picture on the screen, never two)
      c.look(tile.val, @ui.look(alpha=@sfbase.thumb_shows(seen)))
    }
    None => ()
  }
}

///|
/// A waiting picture's corner, as its tile's.
let thumb_corner : Double = @sf.message_file_corner

///|
/// How long it stays a box after it loses the cursor (LET_GO_MS); how long its change of shape takes (morph.ts).
pub let let_go_ms : Double = 300.0

///|
/// (what a test runs to once the composer changes shape)
pub let morph_ms : Double = @sf.shape_ms

///|
/// Laid out for the other page, how long it goes there (dock.tsx: 340, the ease out).
pub let page_move_ms : Double = @sf.composer_page_ms

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
  let n = (dmin(text_most, c.height * text_window_share) / @sf.theme().t.input_line).to_int()
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
/// The capsule (composerBox, one line): its parts on its centre line, 2 apart, 8 in all round, a pill 48 high (so in a
/// panel's corners, the ladder's inset in, concentric with them: the tape's page).
// kept across runs: a value (no field of it changes)
let composer_box : @ui.Style = @ui.css("row w=Full gap=SPx pl=S2 pr=S2 py=S2 radius=InnerOr(Full) align=ACenter")

///|
/// How high the capsule is: its buttons (32) 8 in.
let capsule_h : Double = 32.0 + 2.0 * 8.0

///|
/// The capsule further in than the box by `capsule_in` (composer's), from its left, its right and its foot.
fn capsule_place(capsule_in : (Double, Double, Double)) -> @ui.Style {
  let (l, r, b) = capsule_in
  @ui.style(ml=@sf.room_of(l), mr=@sf.room_of(r), mb=@sf.room_of(b))
}

///|
/// At a panel's foot (`pane` wide), how much further in than its box (composer_side) the composer's capsule stands from
/// the panel's left, its right and its foot: in a panel of its own (@sf.pane_round) whose foot corners it reaches (as
/// wide as the panel leaves it: composer_width), each end as far in as makes it concentric with the corner it is in,
/// an end that cannot the ladder's inset in, as it stands alone (@sf.foot_capsule); else none.
pub fn composer_capsule_in(pane : Double) -> (Double, Double, Double) {
  let d = composer_side()
  if !@sf.in_pane() || composer_width(pane) < pane - 2.0 * d - 0.5 {
    return (0.0, 0.0, 0.0)
  }
  let (l, r, b) = @sf.foot_capsule(capsule_h, @sf.corner_inset, @sf.corner_inset)
  (l - d, r - d, b - d)
}

///|
/// The box (composerBox[data-multiline]): a column its padding in (@sf.composer_pad: its buttons round in its corners
/// concentric with it), its parts 10 apart, a card's corner of the ladder's; in a panel's corners concentric with them.
// kept across runs: a value (no field of it changes)
let composer_box_open : @ui.Style = @ui.style(
  w=Full,
  p=@sf.composer_pad_room,
  gap=S2_5,
  radius=InnerOr(@sf.composer_corner),
)

///|
/// The text's room (composerText): 5 over and under, 8 at its end on one line; opened, 8 in and 8 over.
// kept across runs: a value (no field of it changes)
let text_shut : @ui.Style = @ui.style(w=@sf.grow, pr=S2, py=S1_25)

///|
// kept across runs: a value (no field of it changes)
let text_open : @ui.Style = @ui.css("w=Full px=S2 pt=S2")

///|
/// Its row under the text (composerToolbar, multiline: space-between, 4 apart), its ＋ and send round in the box's foot
/// corners: as far in as makes them concentric with it (外圆角 = 距离 + 半高: the computer's 32 the padding in, the
/// phone's 36 less), what stands over them (a quote, a file) the ladder's inset in.
fn tools_row() -> @ui.Style {
  let off = @sf.composer_round_off()
  tools_row_base.then(@ui.style(mx=off, mb=off))
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
// kept across runs: a value (no field of it changes)
let files_flow : @ui.Style = @ui.css("row w=Full gap=S1_5")

///|
let files_lines : Double = @ui.Space::px(S1_5) + @sf.corner_remove_reach(@sf.message_file_corner)

///|
/// A picture waiting: 56 square, the files' corner (MESSAGE_FILE_CORNER), clipped; failed, edged red.
// kept across runs: a value (no field of it changes)
let thumb_box : @ui.Style = @ui.style(w=S14, h=S14, radius=@sf.message_file_radius, clip=true)

///|
// kept across runs: a value (no field of it changes)
let thumb_failed : @ui.Style = thumb_box.then(@ui.css("border=B2 border_color=Danger"))

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
/// The files of a draft that are up, flying as it is sent, each from its tile (ChatHost.kt sending): from where its
/// card or its picture is (its box's, keyed composer/file/<id>).
fn flying_files(c : @ui.Ctx, w : Writing) -> Array[FlyingFile] {
  w.files.filter_map(fn(f) {
    let v = Some(f)
    let id = text(v, "id")
    match (field(v, "done"), c.rect_of(c.id("composer/file/" + id))) {
      (Some(done), Some(from)) if text(Some(done), "path") != "" => {
        let picture = writing_pictures.get(id).unwrap_or("")
        Some({
          path: text(Some(done), "path"),
          from,
          picture,
          face: fn() {
            let c = @ui.current()
            @sf.file_card(c, "flying/" + id, text(v, "name"), number(v, "size")) |> ignore
          },
        })
      }
      _ => None
    }
  })
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
  let words = w.text.trim(chars=" \n\t").to_string()
  let up = w.files.filter_map(fn(f) { field(Some(f), "done") })
  let rk = r.station + "\u{1}" + r.session
  let row = sent_local(rk, Some(v), words, up)
  // its words take off from the field as they are (before it is emptied), its room held till they let go of it
  let room = @motion.measured(c, "composer/foot").unwrap_or(0.0)
  // its files that are up fly too, each from its tile (ChatHost.kt sending)
  let flying = flying_files(c, w)
  @sfbase.flight_start(
    c,
    w.key,
    rk,
    row,
    words,
    room,
    flying,
    field=composer_field_key,
    hold=fn(ms) { composer_hold(w.key, room, ms) },
    font=@sf.theme().t.input,
    line=@sf.theme().t.input_line,
    desk=true,
  )
  // the chat's list to its end, where the row is (gliding there while nothing flies to it)
  c.list_to_end("chat/" + r.station + "/" + r.session, glide=@sfbase.flight_of(w.key) is None)
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
/// What was sent from draft `draft`'s composer holds its room as tall as it was (`room`) for `ms`, then gives it up as
/// it shrinks (dock.tsx: the list's foot kept where it was till the message's row is in).
fn composer_hold(draft : String, room : Double, ms : Double) -> Unit {
  let c = @ui.current()
  @motion.anim(c, "composer/held/" + draft, 0.0, global=true).snap(room)
  let a = @motion.anim(c, "composer/hold/" + draft, 0.0, global=true)
  a.snap(1.0)
  a.animate(0.0, @motion.tween(morph_ms, ease=Out, delay=ms))
}

///|
/// How much room draft `draft`'s composer takes at its page's foot (what the list leaves free under its last row): as
/// tall as its place (chat_composer: its box, what it says under it, its margins), at least as tall as that opened with
/// one line, or as it was when words were sent from it until they let go of it (composer_hold).
pub fn composer_room(c : @ui.Ctx, draft : String) -> Double {
  // (not laid out yet: a capsule's)
  let foot = @motion.measured(c, "composer/foot").unwrap_or(capsule_room(c.width))
  // never less than it takes opened with one line where it is (its box that tall, what is round it as it is: the web's
  // --composer-room, max(the composer's height, an opened one-line composer's)): opened or let go, a capsule or a box,
  // the list keeps its words where they are; only a line more, a file, a quote, what is said over it move them
  let least = match @motion.measured(c, "composer/content") {
    Some(box) => foot - box + composer_open_box()
    None => composer_open_room(c.width)
  }
  let now = dmax(foot, least)
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
    toolbar: match v {
      Some({ cc, thread: Some(thread), .. }) if cc.length() > 0 => Some(fn() { cc_chooser(c, src, r, thread, cc) })
      _ => None
    },
    note: match v {
      Some(v) => v.cc.filter(fn(o) { o.on }).map(fn(o) { (o.via, o.place) })
      None => []
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
  let capsule_in = if apart { composer_capsule_in(c.width) } else { (0.0, 0.0, 0.0) }
  let foot = c.box(style=chat_foot_top.then(@ui.style(pb=@sf.room_of(composer_foot_in(c.width)))), fn() {
    match v {
      Some(v) => chat_notices(c, src, r, v)
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
          capsule_in~,
        )
      })
    })
    |> ignore
  })
  @motion.measure(c, foot, "composer/foot")
}

///|
/// In a chat whose agents are in Slack or Feishu threads: which of them what is sent is copied to too (Chat.tsx
/// CcChooser, `chat.cc`), each thread's bot saying there who wrote it on still.fail. In the row under the words once the
/// composer is opened to write (on one line it only says where: `note`): 抄送, and each thread ticked (its mark and
/// place), a chooser's look (@sf.chooser), opening a menu of the threads to tick, each ticked one's check at its end:
/// several stay open to tick in turn, one closes once ticked. None until ticked.
fn cc_chooser(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double, to : Array[@sfbase.ChatCcTo]) -> Unit {
  let p = @sf.theme().p
  let id = c.id("composer/cc")
  let open = if c.clicked(id) { !composing.cc_open } else { composing.cc_open }
  let lit = c.lit(id) || open
  let on = to.filter(fn(o) { o.on }).map(fn(o) { (o.via, o.place) })
  let label = @sf.t("web-main.composer.ccLabel")
  let b = c.box(style=cc_trigger, selected=open, id~, fn() {
    c.text(label, style=if lit { cc_words_lit } else { cc_words }) |> ignore
    cc_places(c, on)
    @sf.icon(c, "chevron-down", size=12.0, color=if lit { p.text } else { p.muted }) |> ignore
  })
  c.semantics(b, Button, id~, label=([label] + on.map(fn(o) { o.1 })).join(" "), expanded=open)
  let entries = to.map(fn(o) { @kit.menu_check(o.thread.to_string(), o.on, label=o.place) })
  // each ticked one's check at its row's end (左子健)
  let m = @sf.dropdown(c, "composer/cc/menu", open, id, entries, {}, @sf.chooser_menu_w, side=Top, row_end=fn(c, s) {
    if s.entry.kind is Check(true) {
      @sf.icon(c, "check", size=14.0, color=p.text) |> ignore
    }
  })
  composing.cc_open = m.open
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
          // one: done once ticked; several: open to tick the next
          composing.cc_open = to.length() > 1
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
/// What is said over a chat's composer (Chat.tsx ChatShown, ArchiveNotice, offlineNotice): an archived chat's, with
/// its 还原对话 (why it failed after it, till it is tried again; not while its station is down); its station down, and
/// that what is shown was read before.
fn chat_notices(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView) -> Unit {
  let key = r.station + ":" + r.session
  let width = dmin(c.width - composer_notice_in, composer_notice_most)
  if v.archived {
    let restore = c.id("composer/restore")
    let busy = composing.restoring.contains(key)
    if !busy && !v.offline {
      c.cursor(restore, Hand)
      if c.clicked(restore) && !src.read_only {
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
    let archived_box = c.box(style=composer_notice_box.then(@ui.style(w=Fixed(width))), fn() {
      c.box(style=composer_notice_line, flow=true, fn() {
        c.text(@sf.t("web-main.archived.notice"), style=composer_notice_words) |> ignore
        let b = c.box(id=restore, fn() {
          c.rich(
            [@ui.span(@sf.t(if busy { "web-main.archived.restoring" } else { "web-main.archived.restore" }), underline=true)],
            style=if busy || v.offline { composer_notice_words } else { composer_notice_button },
          )
          |> ignore
        })
        c.semantics(b, Button, id=restore, label=@sf.t("web-main.archived.restore"), disabled=busy || v.offline)
      })
      |> ignore
      match composing.restore_errors.get(key) {
        Some(e) => c.text(e, style=composer_notice_failed) |> ignore
        None => ()
      }
    })
    c.floats_over(archived_box)
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
    let offline_box = c.box(style=composer_notice_box.then(@ui.style(w=Fixed(width))), fn() {
      c.text(said, style=composer_notice_words) |> ignore
    })
    c.floats_over(offline_box)
  }
}

///|
/// A notice over the composer (offlineNotice): 760 wide at most, 32 in from each side, 8 over the composer, 8 by 12 in,
/// rounded 10, on the hover's ground, the ui size, muted.
let composer_notice_most : Double = 760.0

///|
let composer_notice_in : Double = 64.0

///|
// kept across runs: a value (no field of it changes)
let composer_notice_box : @ui.Style = @ui.css("mb=S2 px=S3 py=S2 radius=Lg bg=Hover gap=S1")

///|
// kept across runs: a value (no field of it changes)
let composer_notice_line : @ui.Style = @ui.css("row w=Full gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let composer_notice_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let composer_notice_button : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let composer_notice_failed : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger)

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
/// makes them concentric with its corner (@sf.composer_round_in).
fn composer_open_box() -> Double {
  let t = @sf.theme()
  @sf.composer_pad + (8.0 + t.t.input_line) + 10.0 + t.round.side + @sf.composer_round_in()
}

///|
/// A chat's foot: 12 over the composer, its room under it its pane's (composer_foot_in).
// kept across runs: a value (no field of it changes)
let chat_foot_top : @ui.Style = @ui.css("w=Full pt=S3 align=ACenter")
