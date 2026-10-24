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
/// the agent's session typing warms ("" none), what its field says while empty, the page's choices in its row (a new
/// chat's), laid out roomy (its text over its row even for one line), locked (it takes words, nothing goes), its
/// station offline (no file taken in).
pub(all) struct ComposerSpec {
  station : String
  draft : String
  warm : String
  placeholder : String
  toolbar : (() -> Unit)?
  roomy : Bool
  locked : Bool
  offline : Bool
}

///|
/// What the composer keeps of its own: the system's picker asked for files (for which draft), when the cursor left it
/// (it stays a box a moment, LET_GO_MS), when typing last warmed the agent's runtime, each quote's comment field.
priv struct Composing {
  mut picking : (String, @ui.Pick)?
  mut let_go : Bool
  warmed : Map[String, Int]
  comments : Map[String, @ui.Field]
}

///|
let composing : Composing = { picking: None, let_go: false, warmed: {}, comments: {} }

///|
fn composing_reset() -> Unit {
  composing.picking = None
  composing.let_go = false
  composing.warmed.clear()
  composing.comments.clear()
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
  pages : Pages,
  spec : ComposerSpec,
  send : (Writing) -> Unit,
) -> Unit {
  let p = @sf.theme().p
  let w = writing(src, spec.draft)
  let no_files = spec.locked || spec.offline
  // what the system's picker answered, taken in before the box is laid out (the host's word that it answered brings
  // this frame); a picture pasted into the field; what 文件's 添加到消息 put in for this draft
  take_in(c, src, spec, w, no_files)
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
  let submit = fn() {
    if ready {
      send(w)
    }
  }
  let cap = c.id("composer/cap")
  if c.clicked(cap) && !spec.locked {
    c.focus_editor(composer_field_key)
  }
  // dragged over: marked (the 文件 tab's rows; files from the computer the page takes)
  let dragging = !no_files && dragged() is Some(_) && c.lit(cap)
  let box = c.box(
    style=if multiline { composer_box_open } else { composer_box },
    glass=@sf.glass_floating(tint=if dragging { @sf.alpha(p.accent, drag_tint) } else { 0L }),
    id=cap,
    fn() {
      if multiline {
        composer_extras(c, src, spec, w)
        composer_text(c, src, ws, pages, spec, w, multiline, submit)
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
        composer_text(c, src, ws, pages, spec, w, multiline, submit)
        send_button(c, ready, w.starting, submit)
      }
    },
  )
  // capsule ⇄ box in one motion (useMorph), its height following what it holds
  @motion.layout(c, box, "composer/box", spec=@motion.tween(morph_ms, ease=Out), listed=false)
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
  let sent = tab_take_sent(w.key)
  if !sent.is_empty() && !no_files {
    let prefs = (src.topic)("prefs", {}).value
    let as_files = match field(field(prefs, "dropFiles"), w.key) {
      Some(True) => true
      Some(False) => false
      _ => text(prefs, "dropAs") == "file"
    }
    writing_drop(src, w, spec.station, sent.map(dropped_of), as_files)
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
  pages : Pages,
  spec : ComposerSpec,
  w : Writing,
  multiline : Bool,
  submit : () -> Unit,
) -> Unit {
  let p = @sf.theme().p
  let prefs = (src.topic)("prefs", {}).value
  let hint = space_hint(c, prefs, spec.locked)
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
      pictures=!(spec.locked || spec.offline),
      field=w.field,
    )
    match res.submitted {
      // (the field gives its words up as sent: the draft keeps them until they go)
      Some(words) => {
        w.field.set(words)
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
    if res.focused && w.text == "" && !switcher_open() {
      if c.key_pressed(@ui.key_code_up, in_field=true) {
        neighbour(src, ws, pages, -1)
      } else if c.key_pressed(@ui.key_code_down, in_field=true) {
        neighbour(src, ws, pages, 1)
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
  if spec.warm == "" || spec.locked || spec.offline || src.read_only {
    return
  }
  let n = composing.warmed.get(spec.warm).unwrap_or(0)
  if n > 0 && !@kit.after(c, "composer/warm/" + spec.warm + "/\{n}", true, warm_every_ms, later=true) {
    return
  }
  composing.warmed[spec.warm] = n + 1
  c.tell("composer/warm", fn() {
    (src.call)("session.warm", { "station": Json::string(spec.station), "key": Json::string(spec.warm) }, fn(_) {  })
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
/// The composer's width on a chat's page (dock.css.ts, the chat's: the column and the capsule's curve each side, 760
/// and 22 each side at most, 12 clear of the pane's edges).
pub fn composer_width(pane : Double) -> Double {
  dmin(pane - 2.0 * composer_side, composer_most)
}

///|
/// How long it stays a box after it loses the cursor (LET_GO_MS); how long its change of shape takes (morph.ts).
let let_go_ms : Double = 300.0

///|
let morph_ms : Double = 260.0

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
/// The composer's widest (dock.css.ts: 760 and its curve each side), its clearance from the pane's sides.
let composer_most : Double = 804.0

///|
let composer_side : Double = 12.0

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
pub fn send_in_chat(c : @ui.Ctx, src : Source, pages : Pages, r : ChatRef, v : ChatView, w : Writing) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  let words = w.text.trim(chars=" \n\t").to_string()
  let up = w.files.filter_map(fn(f) { field(Some(f), "done") })
  let going = w.files.filter_map(fn(f) {
    let o = Some(f)
    if field(o, "done") is None && text(o, "error") == "" && field(o, "ref") is None && field(o, "link") is None {
      Some(Json::object({ "id": Json::string(text(o, "id")), "name": Json::string(text(o, "name")), "size": Json::number(number(o, "size")) }))
    } else {
      None
    }
  })
  let rk = r.station + "\u{1}" + r.session
  let row = sent_local(rk, Some(v), words, up)
  (pages.fly)(c, w.key, rk, row, words, @motion.measured(c, "composer/content").unwrap_or(0.0))
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
