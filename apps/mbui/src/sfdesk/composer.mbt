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
  restoring : Map[String, Bool]
  restore_errors : Map[String, String]
}

///|
let composing : Composing = { picking: None, let_go: false, warmed: {}, comments: {}, roomy: None, draft: "", restoring: {}, restore_errors: {} }

///|
fn composing_reset() -> Unit {
  composing.picking = None
  composing.let_go = false
  composing.warmed.clear()
  composing.comments.clear()
  composing.roomy = None
  composing.draft = ""
  composing.restoring.clear()
  composing.restore_errors.clear()
}

///|
/// The composer's text field (its words, a flight's from: flight.mbt), its box, what is in it.
pub let composer_field_key : String = "composer/field"

///|
/// The composer (ComposerView) for `spec`, `send` what pressing send (or Enter) does with what is written once it is
/// ready. Drawn where its place is; a page lays it out (its width: composer_width).
pub fn composer(
  c : @ui.Ctx,
  src : Source,
  ws : Workspace,
  spec : ComposerSpec,
  send : (Writing) -> Unit,
) -> Unit {
  let p = @sf.theme().p
  let w = writing(src, spec.draft)
  let no_files = spec.locked || spec.offline
  // what the system's picker answered, taken in before the box is laid out (the host's word that it answered brings
  // this frame); a picture pasted into the field; what 文件's 添加到消息 put in for this draft
  take_in(c, src, spec, w, no_files)
  // switched to another chat (Chat.tsx: its thread another; a new chat's has none, whichever station): the cursor in
  // it, with a mouse, before it is first drawn; not taken from a field in use (the switcher's, a dialog's)
  let whose = "\u{1}" + spec.session
  if whose != composing.draft {
    composing.draft = whose
    if @ui.pointing() is Mouse && !c.field_focused() {
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
  let ready = w.ready && !spec.locked
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
  let dragging = !no_files && dragged() is Some(_) && c.lit(cap)
  let box = c.box(
    style=if multiline { composer_box_open } else { composer_box },
    // (the raised ground's glass, the accent's over it while dragged over)
    glass=@sf.glass_floating(tint?=if dragging { Some(@sf.alpha(p.accent, drag_tint)) } else { None }),
    id=cap,
    fn() {
      if multiline {
        composer_extras(c, src, spec, w)
        composer_text(c, src, ws, spec, w, cap, multiline, submit)
        c.box(style=tools_row, fn() {
          attach(c, spec, w, no_files)
          match spec.toolbar {
            Some(f) => c.box(style=choices, f) |> ignore
            None => c.box(style=tools_gap, fn() {  }) |> ignore
          }
          send_button(c, ready, w.starting, submit)
        })
        |> ignore
      } else {
        attach(c, spec, w, no_files)
        composer_text(c, src, ws, spec, w, cap, multiline, submit)
        send_button(c, ready, w.starting, submit)
      }
    },
  )
  // capsule ⇄ box in one motion (useMorph), its height following what it holds; laid out for the other page (a new
  // chat's in the page, a chat's at its foot: dock.tsx), from where it was there to here, one composer changing
  let moved = match composing.roomy {
    Some(was) => was != spec.roomy
    None => false
  }
  composing.roomy = Some(spec.roomy)
  @motion.layout(c, box, "composer/box", spec=@motion.tween(if moved { page_move_ms } else { morph_ms }, ease=Out), listed=false)
  @motion.measure(c, box, "composer/content")
  if w.error != "" {
    c.box(style=error_box, fn() { c.text(w.error, style=composer_error_words) |> ignore }) |> ignore
  }
}

///|
/// What comes into the draft from outside the field before the box is laid out: the files the system's picker
/// answered (for this draft), a picture pasted into the field (⌘V with one on the clipboard, as the web's paste takes
/// the clipboard's files), the rows the 文件 tab's 添加到消息 put in (named by their path, or as files where this chat
/// takes what is dragged in so).
fn take_in(c : @ui.Ctx, src : Source, spec : ComposerSpec, w : Writing, no_files : Bool) -> Unit {
  match composing.picking {
    Some((key, picker)) =>
      match picker.files() {
        Some(files) => {
          composing.picking = None
          if key == w.key && !no_files {
            for f in files {
              writing_add(src, w, spec.station, f.name, f.bytes)
            }
          }
        }
        None => ()
      }
    None => ()
  }
  match c.field_picture(composer_field_key) {
    Some(png) if !no_files => writing_add(src, w, spec.station, pasted_picture_name, png)
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
  let sent = tab_take_sent(w.key)
  if !sent.is_empty() && !no_files {
    writing_drop(src, w, spec.station, sent.map(dropped_of), drops_as_files(src, w.key))
  }
}

///|
/// Whether what is carried into draft `key` goes as files (the chat's own choice, else the device's: prefs
/// `dropFiles`, `dropAs`), not named by its path.
fn drops_as_files(src : Source, key : String) -> Bool {
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
fn dropped_of(d : Dragged) -> Json {
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
) -> Unit {
  let p = @sf.theme().p
  let prefs = (src.topic)("prefs", {}).value
  let hint = space_hint(c, prefs, spec.locked)
  let no_files = spec.locked || spec.offline
  // what the field was given since the last frame, as the core reads it (a mark taken whole, a chat's link pasted)
  @sfbase.refs_edits(c, src, w.key, w.field, spec.station, spec.locked)
  c.box(style=if multiline { text_open } else { text_shut }, fn() {
    let res = c.editor(
      composer_field_key,
      placeholder=if hint != "" { hint } else { spec.placeholder },
      words=true,
      font_size=text_size,
      line=text_line,
      trim=true,
      max_lines=text_lines(c),
      plain=true,
      color=p.text,
      placeholder_color=p.subtle,
      caret_color=p.accent,
      enter_sends=@ui.pointing() is Mouse,
      // (the `@` menu open: ↑ / ↓ choose in it, Enter and Tab pick)
      leaves=ref_leaves(src, spec, w, c.editor_focused(composer_field_key)),
      pictures=!no_files,
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
    match res.submitted {
      // (the field gives its words up as sent: the draft keeps them until they go)
      Some(words) => {
        // (put back as the app's own: what the core read of them is asked again, not taken as none)
        @sfbase.refs_put(w.key, w.field, words)
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
    if res.focused && w.text == "" && !switcher_open() && !menu {
      if c.key_pressed(@ui.key_code_up, in_field=true) {
        neighbour(src, ws, -1)
      } else if c.key_pressed(@ui.key_code_down, in_field=true) {
        neighbour(src, ws, 1)
      }
    }
  })
  |> ignore
}

///|
/// What the box says instead of its placeholder with a mouse and nothing that takes keys focused: that the composer's
/// key puts the cursor there ("" otherwise).
fn space_hint(c : @ui.Ctx, prefs : Json?, locked : Bool) -> String {
  if locked || @ui.pointing() is Finger || c.field_focused() {
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
fn attach(c : @ui.Ctx, spec : ComposerSpec, w : Writing, no_files : Bool) -> Unit {
  let p = @sf.theme().p
  let id = c.id("composer/plus")
  let hot = !no_files && c.lit(id)
  if !no_files {
    c.cursor(id, Hand)
    @sf.tip(c, "composer/plus", id, @sf.t("web-main.composer.attach"), shortcut="composer.file")
    if c.clicked(id) {
      pick_files(w)
    }
  }
  ignore(spec)
  let b = c.box(style=if hot { round_button_hot } else { round_button }, id~, fn() {
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
fn send_button(c : @ui.Ctx, ready : Bool, starting : Bool, submit : () -> Unit) -> Unit {
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
  let b = c.box(style=round_button.then(@ui.style(bg=Data(ground))), id~, fn() {
    if starting {
      @sf.spinner(c, size=send_icon) |> ignore
    } else {
      @sf.icon(c, "arrow-up", size=send_icon, color=if ready { p.canvas } else { p.raised }) |> ignore
    }
  })
  c.semantics(b, Button, id~, label=@sf.t("web-main.composer.send"), disabled=!ready)
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
              font_size=comment_size,
              line=comment_line,
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
    c.box(style=files_flow, flow=true, fn() {
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
      let ref_ = field(v, "ref")
      let said = match ref_ {
        // named by its path: its station and that it goes as a path
        Some(Object(_)) if text(ref_, "mode") != "file" =>
          @sf.file_card(
            c,
            key,
            name,
            number(v, "size"),
            path=text(ref_, "path"),
            error=text(ref_, "stationName") + " · " + @sf.t("web-main.file.modePath"),
            remove=true,
          )
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
            remove=true,
            remove_label=@sf.t("web-main.composer.removePaste"),
            retry=error != "",
            restore=can_restore,
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
        _ =>
          @sf.file_card(
            c,
            key,
            name,
            number(done, "size") + (if done is None { number(v, "size") } else { 0.0 }),
            path=text(done, "path"),
            pending~,
            sent=match field(v, "sent") {
              Some(Number(n, ..)) => Some(n)
              _ => None
            },
            error~,
            remove=true,
            retry=error != "" && field(v, "pasted") is None,
          )
      }
      if said.removed {
        writing_remove(src, w, id)
      }
      if said.retried {
        writing_retry(src, w, id)
      }
    }
  }
  ignore(spec)
}

///|
/// A picture waiting (composerThumb): its own picture from here, a turning ring over it while it goes up, red-edged
/// when it failed (↻ over it); its ✕ at its corner; its name its tip.
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
  let x = c.id(key + "/remove")
  let again = c.id(key + "/retry")
  @sf.tip(c, key + "/tip", thumb, if error != "" { error } else { name })
  c.box(style=if error != "" { thumb_failed } else { thumb_box }, id=thumb, fn() {
    c.image(picture, w=Px(thumb_side), h=Px(thumb_side), fit=FitCover) |> ignore
    if pending {
      c.layer(fn() { c.box(style=thumb_veil, fn() { @sf.spinner(c, size=send_icon) |> ignore }) |> ignore })
      |> ignore
    }
    if error != "" {
      c.layer(fn() {
        c.box(style=thumb_veil, id=again, fn() { @sf.icon(c, "refresh", size=retry_icon, color=on_veil) |> ignore })
        |> ignore
      })
      |> ignore
    }
    c.layer(fn() {
      c.box(style=thumb_x_at, fn() {
        c.box(style=thumb_x, id=x, fn() { @sf.icon(c, "close", size=thumb_x_icon, color=on_veil) |> ignore })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  c.cursor(x, Hand)
  if c.clicked(x) {
    writing_remove(src, w, id)
  }
  if error != "" {
    c.cursor(again, Hand)
    if c.clicked(again) {
      writing_retry(src, w, id)
    }
  }
}

///|
/// How long it stays a box after it loses the cursor (LET_GO_MS); how long its change of shape takes (morph.ts).
let let_go_ms : Double = 300.0

///|
let morph_ms : Double = 260.0

///|
/// Laid out for the other page, how long it goes there (dock.tsx: 340, the ease out).
let page_move_ms : Double = 340.0

///|
/// Typing warms the agent's runtime at most once a minute.
let warm_every_ms : Double = 60000.0

///|
/// A picture pasted is called so (a browser's paste names one so).
let pasted_picture_name : String = "image.png"

///|
/// The words' size and line (composerText: 14 on 1.5), the most it grows to (480, or 40% of the window).
let text_size : Double = 14.0

///|
let text_line : Double = 21.0

///|
let text_most : Double = 480.0

///|
let text_window_share : Double = 0.4

///|
/// How many lines the field grows to before it scrolls.
fn text_lines(c : @ui.Ctx) -> Int {
  let n = (dmin(text_most, c.height * text_window_share) / text_line).to_int()
  if n < 1 {
    1
  } else {
    n
  }
}

///|
/// What is said about a quote: 13 on 20 (quoteCardInput: the ui's size).
let comment_size : Double = 13.0

///|
let comment_line : Double = 20.0

///|
/// ＋'s and send's icons (Plus 18, ArrowUp 16), a picture's ↻ (18) and ✕ (12).
let plus_icon : Double = 18.0

///|
let send_icon : Double = 16.0

///|
let retry_icon : Double = 18.0

///|
let thumb_x_icon : Double = 12.0

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
/// The capsule (composerBox, one line): its parts on its centre line, 2 apart, 6 in at its start, a pill.
// kept across runs: a value (no field of it changes)
let composer_box : @ui.Style = @ui.css("row w=Full gap=SPx pl=S1_5 pr=S1_5 py=S1_5 radius=Full align=ACenter")

///|
/// The box (composerBox[data-multiline]): a column 12 in, its parts 10 apart, its corner its buttons' pill's with its
/// padding (COMPOSER_INNER + 12).
// kept across runs: a value (no field of it changes)
let composer_box_open : @ui.Style = @ui.style(
  w=Full,
  p=S3,
  gap=S2_5,
  radius=@sf.composer_corner,
)

///|
/// The text's room (composerText): 5 over and under, 8 at its end on one line; opened, 8 in and 8 over.
// kept across runs: a value (no field of it changes)
let text_shut : @ui.Style = @ui.style(w=@sf.grow, pr=S2, py=S1_25)

///|
// kept across runs: a value (no field of it changes)
let text_open : @ui.Style = @ui.css("w=Full px=S2 pt=S2")

///|
/// Its row under the text (composerToolbar, multiline: space-between, 4 apart).
// kept across runs: a value (no field of it changes)
let tools_row : @ui.Style = @ui.css("row w=Full gap=S1 align=ACenter")

///|
/// The page's choices (composerChoices: in what is left of the row, at its start).
// kept across runs: a value (no field of it changes)
let choices : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S1, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let tools_gap : @ui.Style = @ui.style(w=@sf.grow)

///|
/// ＋ and send: 32 round, centred.
// kept across runs: a value (no field of it changes)
let round_button : @ui.Style = @ui.css("w=S8 h=S8 radius=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let round_button_hot : @ui.Style = round_button.then(@ui.css("bg=Hover"))

///|
/// The quotes waiting, 6 apart.
// kept across runs: a value (no field of it changes)
let quotes_column : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
/// The files waiting (composerFiles: wrapped, 6 apart, flush with the box's padding).
// kept across runs: a value (no field of it changes)
let files_flow : @ui.Style = @ui.css("row w=Full gap=S1_5")

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
/// A picture's ✕ (composerThumbRemove): 20 round at its top right corner, 4 in, on the veil.
// kept across runs: a value (no field of it changes)
let thumb_x_at : @ui.Style = @ui.css("w=Full pt=S1 pr=S1 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let thumb_x : @ui.Style = @ui.css("w=S5 h=S5 radius=Full bg=Veil align=ACenter justify=JCenter")

///|
/// What went wrong (chatError: under the box, 32 in, 10 under it; fieldError's red).
// kept across runs: a value (no field of it changes)
let error_box : @ui.Style = @ui.css("w=Full px=S8 pt=S1 pb=S2_5")

///|
// kept across runs: a value (no field of it changes)
let composer_error_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Danger, leading=L5)

///|
/// What is written sent into chat `r` (`v` its view: its thread, what is in it now; sendDraft, draft.ts send): in the
/// list and flying there in the frame it is sent, before the core has it (sent_local: the rule), the composer empty at
/// once; then what the core took (`composer.take`: the words with the links and the paths after them, the files up,
/// the quotes) goes (`chat.send`), the files still going up named so it waits for them. Not taken in at all (the core
/// refused it, or went away with it): back in the composer unless something new is written there, saying why; one the
/// station did not take waits in the outbox, which says so.
pub fn send_in_chat(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView, w : Writing) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  let words = w.text.trim(chars=" \n\t").to_string()
  let up = w.files.filter_map(fn(f) { field(Some(f), "done") })
  let going = going_up(w)
  let rk = r.station + "\u{1}" + r.session
  let row = sent_local(rk, Some(v), words, up)
  // its words take off from the field as they are (before it is emptied), its room held till they let go of it
  let room = @motion.measured(c, "composer/foot").unwrap_or(0.0)
  @sfbase.flight_start(
    c,
    w.key,
    rk,
    row,
    words,
    room,
    [],
    field=composer_field_key,
    hold=fn(ms) { composer_hold(w.key, room, ms) },
    font=text_size,
    line=text_line,
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
/// tall as its place (chat_composer: its box, what it says under it, its margins), or as it was when words were sent
/// from it until they let go of it (composer_hold).
pub fn composer_room(c : @ui.Ctx, draft : String) -> Double {
  // (not laid out yet: a capsule's)
  let now = @motion.measured(c, "composer/foot").unwrap_or(capsule_room)
  let held = @motion.anim(c, "composer/held/" + draft, 0.0, global=true).get()
  let share = @motion.anim(c, "composer/hold/" + draft, 0.0, global=true).get()
  if held > now {
    now + (held - now) * share
  } else {
    now
  }
}

///|
/// The files of draft `w` still going up, as a message sent before they are up names them (`uploads`: the core sends
/// it once they are).
fn going_up(w : Writing) -> Array[Json] {
  w.files.filter_map(fn(f) {
    let o = Some(f)
    if field(o, "done") is None && text(o, "error") == "" && field(o, "ref") is None && field(o, "link") is None {
      Some(Json::object({ "id": Json::string(text(o, "id")), "name": Json::string(text(o, "name")), "size": Json::number(number(o, "size")) }))
    } else {
      None
    }
  })
}

///|
/// A chat's composer at its pane's foot (dock.tsx's chat place; cloud.css.ts composerWrap: 12 over it, 16 under it;
/// dock.css.ts: 12 clear of the pane's sides, the column and its curve wide at most, in the middle): the chat's draft
/// (ChatPage.tsx chatKey), what it sends going into the chat (send_in_chat), locked while the chat is archived, no
/// file taken in while its station is down. Its place measured (composer_room).
pub fn chat_composer(c : @ui.Ctx, src : Source, ws : Workspace, r : ChatRef, v : ChatView?) -> Unit {
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
  // (on the tape the page a panel of its own: the composer as far from its foot as from its sides, concentric with its
  // corners: @sf.page_panel_corner)
  let foot = c.box(style=if wide.tape { chat_foot_apart } else { chat_foot }, fn() {
    match v {
      Some(v) => chat_notices(c, src, r, v)
      None => ()
    }
    c.box(style=@ui.style(w=Fixed(width)), fn() {
      c.sized(width, c.height, fn() {
        composer(c, src, ws, spec, fn(w) {
          match v {
            Some(v) => send_in_chat(c, src, r, v, w)
            None => ()
          }
        })
      })
    })
    |> ignore
  })
  @motion.measure(c, foot, "composer/foot")
}

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
    c.box(style=composer_notice_box.then(@ui.style(w=Fixed(width))), fn() {
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
    |> ignore
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
    c.box(style=composer_notice_box.then(@ui.style(w=Fixed(width))), fn() { c.text(said, style=composer_notice_words) |> ignore })
    |> ignore
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
let composer_notice_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let composer_notice_button : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let composer_notice_failed : @ui.TextStyle = @ui.text_style(size=Sm, color=Danger)

///|
/// A chat's composer's place while it is a capsule: its buttons (32) 6 in, 12 over it and 16 under it.
let capsule_room : Double = 32.0 + 2.0 * 6.0 + 12.0 + 16.0

///|
// kept across runs: a value (no field of it changes)
let chat_foot : @ui.Style = @ui.css("w=Full pt=S3 pb=S4 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let chat_foot_apart : @ui.Style = @ui.css("w=Full pt=S3 pb=S3 align=ACenter")
