// A new chat (ember web/src/NewChat.tsx and NewChat.css.ts, web/src/mobile/NewChat.tsx and NewChat.css.ts,
// FrequentCombos.tsx; apps/android NewChat.kt): say what to do, having picked where it runs (the station) and on what
// (the model, its runtime, how hard it thinks, who runs it), as the core keeps them (the `newChat` topic; `newChat.pick`,
// `pick.set`, `pick.save`). One page in every frame, laid out by its own width as the web lays out its two:
// - narrow (under @sf.page_narrow_most), as the web's mobile page: the scene (the picture, what to do and where, the
//   frequent combinations, what keeps it from starting, the machine's own sessions) over all that is left, scrolled
//   when it does not fit; at its foot what is wrong for now, the choices in glass capsules (the station, the model: each
//   through the presenters), the composer where a chat has it;
// - wide, as the web's desktop page: all of it in a column 720 wide at most in the middle, the composer roomy in it with
//   the choices in the row under its words (the station's chooser, the model control: model_triple.mbt).
// The composer is the pages' (composer.mbt), its draft the station's new chat's (`new:<station>`). The first message
// makes the chat (`newChat.create`, made once a page, anew when the picks changed: useEnsureChat) and goes to it
// (`chat.send` by its key); the page becomes the chat in place, its first words carried where they were typed till
// their row is in the chat's list (flight.mbt), what is written meanwhile going on into the chat's draft
// (`composer.carry`); over the chat its scene goes up out of view as it fades and what is under it fades where it is
// (madeChat.ts toMadeChat, NewChat.kt). The frame says what is over it and under it, and what it does as the page
// becomes the chat (NewChatFrame).

///|
/// What the frame a new chat is drawn in gives it: the settings' core (the machine's own sessions, borrowing a
/// model), its bar over it (the Small stack's 取消 and 新对话; a pane's has none: its 文件 is the frame's, over the page),
/// the room under it (the navigation bar), whether the chat it becomes opens in its place (the Small stack's: its first
/// words fly as Android's do) or beside it, the composer going into the chat's (a pane's: as the web's do), and what
/// the frame does as the page becomes the chat (its files' tab carried over). Come to, it is there at once
/// (switch.mbt).
pub(all) struct NewChatFrame {
  core : Core
  bar : () -> Unit
  foot : Double
  in_place : Bool
  sent : (ChatRef) -> Unit
}

///|
/// What the page keeps of its own: which of its picks is asked open as it is next drawn (a fixture's: new_chat_ask).
priv struct NewChatPage {
  mut asked : String
}

///|
let new_chat_state : NewChatPage = { asked: "" }

///|
fn new_chat_reset() -> Unit {
  new_chat_state.asked = ""
}

///|
/// One of the page's picks opened as it is next drawn narrow, as though its capsule were pressed: "station" where it
/// runs, "model" what it runs on (a fixture's screen of it).
pub fn new_chat_ask(what : String) -> Unit {
  new_chat_state.asked = what
}

///|
/// A new chat in workspace `w` (NewChat, NewChatScreen): while its stations are read, the page as it will be on the
/// station it last started on, its composer taking words but sending nothing; with none at all, the first to add;
/// with none up, said so; nothing to run a chat with yet, its first step; else the page on the station it starts on.
pub fn new_chat_page(c : @ui.Ctx, src : Source, w : Workspace, frame : NewChatFrame) -> Unit {
  let topic = (src.topic)("newChat", { "scope": Json::string(w.id) })
  let v = topic.value
  c.box(style=new_ground, fn() {
    c.box(style=new_bar_room, frame.bar) |> ignore
    c.box(style=new_room, fn() {
      match field(v, "stations") {
        Some(Array(_)) =>
          match field(v, "station") {
            Some(Object(_)) as station => {
              // (what is picked now: a chat made with other picks, nothing sent to it, let go)
              @sfbase.fresh_picked(v)
              if text(v, "blocked") != "" {
                new_blocked(c, src, w, v, station)
              } else {
                new_on(c, src, w, frame, v, station, Here)
              }
            }
            _ => if flag(v, "any") { new_none_up(c) } else { new_first_station(c) }
          }
        _ => {
          let error = match text(v, "error") {
            "" =>
              match topic.error {
                Some(e) => text(Some(e), "message")
                None => ""
              }
            e => e
          }
          new_on(c, src, w, frame, v, None, Held(error))
        }
      }
    })
    |> ignore
    list_space(c, frame.foot)
  })
  |> ignore
  // the first words sent, where they were typed, while the chat is made (flight.mbt)
  @sfbase.flight_carry_waiting(c)
}

///|
/// The new chat of view `v` as it is left (madeChat.ts toMadeChat, data-made-leave): as it was but for its composer
/// (the chat's now, its place kept), its scene `up` of the way up out of view as it fades, what is under the composer
/// `fade` of the way faded where it is. The frame draws it over the chat it became (its scene leaving: 140 ms, what is
/// under the composer 80 ms: @sfbase.new_chat_leaving_of), or over the chat it was left for, in a layer drawn only.
pub fn new_chat_left(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  frame : NewChatFrame,
  v : Json?,
  up : Double,
  fade : Double,
) -> Unit {
  c.box(style=new_frame_box, fn() {
    // its bar gone at once (the chat has its own), its room kept
    let bar = c.box(style=new_bar_room, frame.bar)
    c.look(bar, @ui.look(alpha=0.0))
    c.box(style=new_room, fn() { new_on(c, src, w, frame, v, field(v, "station"), Going(up, fade)) }) |> ignore
    list_space(c, frame.foot)
  })
  |> ignore
}

///|
/// What the page on a station is: here (`Here`); its stations not read yet (`Held`: why they could not be, "" while
/// they are read), the station it last started on in its place; become its chat (`Going`: how far its scene has gone up
/// and how far what is under its composer has faded, 0 … 1 each).
priv enum NewState {
  Here
  Held(String)
  Going(Double, Double)
}

///|
/// The page on a station (NewChatOn), laid out by its width.
fn new_on(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  frame : NewChatFrame,
  v : Json?,
  station : Json?,
  state : NewState,
) -> Unit {
  if c.width < @sf.page_narrow_most {
    new_narrow(c, src, w, frame, v, station, state)
  } else {
    new_wide(c, src, w, frame, v, station, state)
  }
}

///|
/// The station a new chat is on: the one picked; while its stations are read, the one it last started on (the core's
/// `kept`), its draft the one the page will have ("" when it has started on none).
fn new_address(w : Workspace, v : Json?, station : Json?, state : NewState) -> String {
  match state {
    Held(_) =>
      match text(v, "kept") {
        "" => ""
        kept => w.id + "/" + kept
      }
    _ => text(station, "station")
  }
}

///|
/// A station's name as the page says it: "this machine" for one not named.
fn new_station_words(station : Json?) -> String {
  match text(station, "name") {
    "" => @sf.t("web-main.newChat.thisMachine")
    n => n
  }
}

// ── narrow: the web's mobile page ─────────────────────────────────────────

///|
/// The page narrow (the web's mobile NewChatOn, mNewBody, mNewFoot): the scene in all of it, scrolled when it does not
/// fit, its end clear of the foot over it (the keyboard up, the choices and the composer stay over it); the foot a band
/// of glass, what is wrong for now, the choices, the composer where a chat's is (chat_composer: the page becomes the
/// chat, its composer where it was).
fn new_narrow(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  frame : NewChatFrame,
  v : Json?,
  station : Json?,
  state : NewState,
) -> Unit {
  let address = new_address(w, v, station, state)
  let (up, fade) = match state {
    Going(u, f) => (u, f)
    _ => (0.0, 0.0)
  }
  let going = state is Going(_, _)
  // the scene in all the page, its end clear of the foot over it (mNewBody's --m-new-foot: as tall as the foot was
  // last laid out)
  let clear = @motion.measured(c, "new/foot").unwrap_or(0.0)
  c.box(style=new_scene_room, fn() {
    c.list("new/scene", 1, new_scene_guess, fn(_) {
      c.box(style=new_scene_column, fn() {
        let scene = c.box(style=new_scene_narrow, fn() { new_scene_narrow_body(c, src, w, frame, v, station, state) })
        // up out of view as it fades, a little smaller, from its middle (madeChat.ts: translateY(-32px) scale(.96))
        if going {
          c.look(scene, @ui.look(alpha=1.0 - up, dy=-new_leave_rise * up, scale=1.0 - new_leave_shrink * up))
        }
        list_space(c, clear)
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  let width = composer_width(c.width)
  // (as far from the page's foot as a chat's composer: composer_foot_in)
  let under : @ui.Space = @sf.room_of(composer_foot_in(c.width))
  c.layer(fn() {
    c.spacer()
    let foot = c.box(style=new_foot, fn() {
      // a band of glass from over the choices to the page's foot (mNewFoot, glassFoot), the composer on it: what the
      // scene has under it frosted all over, not seen between the choices, nor pressed through it; as the page becomes
      // the chat, over the choices alone (the composer there is the chat's, under it, not to be frosted)
      let band = c.id("new/band")
      c.box(style=new_band.then(@ui.style(pb=if going { S0 } else { under })), glass=@sf.glass_foot(), id=band, fn() {
        if !going {
          new_notices(c, v, station, width)
        }
        c.box(style=@ui.style(w=Fixed(width)), fn() {
          new_choosers(c, src, w, frame, v, station, state)
          if !going {
            new_composer_place(c, src, w, frame, v, address, station, state, width)
          }
        })
        |> ignore
      })
      |> ignore
      if going {
        c.box(style=@ui.style(w=Fixed(width), pb=under), fn() {
          new_composer_place(c, src, w, frame, v, address, station, state, width)
        })
        |> ignore
      }
    })
    @motion.measure(c, foot, "new/foot")
    // over the scene: its scroll bar keeps clear of it
    c.floats_over(foot)
    if going {
      c.look(foot, @ui.look(alpha=1.0 - fade))
    }
  })
  |> ignore
}

///|
/// The scene narrow (mNewBody): the picture, what to do, where (while its stations are read, its two lines breathing,
/// still once what they wait on failed), the frequent combinations, what keeps it from starting (or why its stations
/// could not be read), the machine's own sessions to go on with.
fn new_scene_narrow_body(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  frame : NewChatFrame,
  v : Json?,
  station : Json?,
  state : NewState,
) -> Unit {
  new_head(c, station, state, new_scene_narrow_w, fn(_) {  })
  new_combos(c, src, w, v, state is Going(_, _)) |> ignore
  let problem = match state {
    Held(error) => error
    _ => text(v, "problem")
  }
  if problem != "" {
    c.box(style=new_problem_box, fn() {
      c.text(problem, style=if state is Held(_) { new_error } else { new_status }) |> ignore
    })
    |> ignore
  }
  new_offer(c, src, frame, station, state, hung=false) |> ignore
}

///|
/// The choices over the composer (mChoosers): where it runs, what it runs on, each a glass capsule opening its pick
/// through the presenters; while its stations are read, both breathing in their places, as high as they will be (still
/// once what they wait on failed); its profiles still read (the core's `waiting`), what it runs on breathing.
fn new_choosers(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  frame : NewChatFrame,
  v : Json?,
  station : Json?,
  state : NewState,
) -> Unit {
  let going = state is Going(_, _)
  c.box(style=new_choosers_row, fn() {
    match state {
      Held(error) => {
        @sf.bar(c, Px(held_station_w), held_chooser_h, breathing=error == "")
        @sf.bar(c, Px(held_model_w), held_chooser_h, breathing=error == "")
        return
      }
      _ => ()
    }
    new_controls(c, src, w, v, station, true, going)
  })
  |> ignore
}

///|
/// Where it runs and what it runs on: the station's control (its mark, its name; pressed, the stations through the
/// presenters) and the model's (model_triple.mbt, its panel through them too); with nothing to run it with, the way to
/// where models are enabled; while its profiles are read, what it runs on breathing in its place. `floating`: over
/// the composer (narrow: capsules of its glass), else in its row (wide).
fn new_controls(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  v : Json?,
  station : Json?,
  floating : Bool,
  going : Bool,
) -> Unit {
  let address = text(station, "station")
  if text(station, "name") != "" {
    new_station_control(c, src, w, v, station, floating, going)
  }
  let p = field(v, "pick")
  if flag(v, "waiting") {
    @sf.bar(c, Px(held_model_w), held_chooser_h, breathing=true)
  } else if p is None ||
    items(p, "options").length() == 0 ||
    text(v, "runtime") == "" ||
    field(v, "model") is None {
    // nothing to run it with: the way to where models are enabled
    if new_capsule(c, "new/models", @sf.t("web-main.newChat.noModels"), floating, fn() {
        c.text(@sf.t("web-main.newChat.noModels"), style=new_capsule_words) |> ignore
      }) &&
      !going {
      open_page(Place("profiles"))
    }
  } else {
    if take_asked("model") {
      open_triple(address, "new")
    }
    model_triple(c, src, address, "new", up=true, page=p, small=true, floating~)
  }
}

///|
/// Where it runs (Chooser of the stations, mChooser): its mark, its name, a chevron; pressed, the workspace's stations
/// through the presenters, the one it starts on checked (station_rows).
fn new_station_control(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  v : Json?,
  station : Json?,
  floating : Bool,
  going : Bool,
) -> Unit {
  let t = @sf.theme()
  if (new_capsule(
      c,
      "new/station",
      text(station, "name"),
      floating,
      fn() {
        @sf.station_mark(c, text(station, "emoji"), text(station, "icon"), new_mark, t.p.text)
        c.box(style=new_station_name, fn() { c.text(text(station, "name"), style=new_capsule_words) |> ignore })
        |> ignore
        @sf.icon(c, "chevron-down", size=new_chevron, color=t.p.muted) |> ignore
      },
    ) &&
    !going) ||
    take_asked("station") {
    @sf.panel(
      @sf.t("android-chat.new.station.pick"),
      fn(c, close) { station_rows(c, src, w, v, close) },
      from=Of(c.id("new/station")),
    )
  }
}

///|
/// A control of the page's (where it runs, the way to models): over the composer a capsule of its glass (mChooser,
/// NewChat.kt Chooser), in its row as the composer's other controls (Chooser in NewChat.tsx's toolbar); what it holds
/// `body`. True on the frame after it was pressed.
fn new_capsule(c : @ui.Ctx, key : String, label : String, floating : Bool, body : () -> Unit) -> Bool {
  let id = c.id(key)
  c.cursor(id, Hand)
  let b = if floating {
    c.box(style=glass_chooser_box, glass=@sf.glass_floating(), id~, fn() {
      body()
      @sf.press_ripple(c, id, glass_chooser_corner)
    })
  } else {
    c.box(style=new_capsule_in_row, id~, body)
  }
  c.semantics(b, Button, id~, label~)
  c.clicked(id)
}

///|
/// Whether `what` was asked open (new_chat_ask), let go of as it is.
fn take_asked(what : String) -> Bool {
  if new_chat_state.asked != what {
    return false
  }
  new_chat_state.asked = ""
  true
}

///|
/// Where a new chat runs (the mobile pickStation, NewChat.kt pickStation): the workspace's stations up now, each its
/// mark, its name and what it is, the one it starts on checked; picked, the core has it (`newChat.pick`).
fn station_rows(c : @ui.Ctx, src : Source, w : Workspace, v : Json?, close : () -> Unit) -> Unit {
  let p = @sf.theme().p
  let current = text(field(v, "station"), "station")
  for s in items(v, "stations") {
    let st = Some(s)
    let id = c.id("pick-station/" + text(st, "station"))
    c.cursor(id, Hand)
    if c.clicked(id) {
      @sfbase.pick_new(src, w.id, { "station": Json::string(text(st, "id")) })
      close()
    }
    // (its words on the panel's words' line wherever it is drawn: @sf.panel_row_in)
    let row = c.box(style=station_row.then(@sf.panel_row_in()), id~, fn() {
      @sf.station_icon(c, text(st, "emoji"), text(st, "icon"), station_row_mark, p.text)
      c.box(style=station_row_words, fn() {
        c.text(text(st, "name"), style=station_row_name) |> ignore
        if text(st, "summary") != "" {
          c.text(text(st, "summary"), style=station_row_note) |> ignore
        }
      })
      |> ignore
      if text(st, "station") == current {
        @sf.icon(c, "check", size=new_mark, color=p.accent) |> ignore
      }
      @sf.press_ripple(c, id, @sf.row_corner)
    })
    c.semantics(row, Button, id~, label=text(st, "name"), check=if text(st, "station") == current { On } else { Off })
  }
}

// ── wide: the web's desktop page ──────────────────────────────────────────

///|
/// The page wide (NewChatOn, newChat, newChatInner): the scene, 新对话, what it does and where (while its stations are
/// read, that it starts on the station chosen), what is wrong for now, the composer, roomy, its choices in its row; the
/// frequent combinations under it, what it waits for (or why its stations could not be read), the machine's own
/// sessions to go on with.
fn new_wide(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  frame : NewChatFrame,
  v : Json?,
  station : Json?,
  state : NewState,
) -> Unit {
  let address = new_address(w, v, station, state)
  new_column(c, fn(col) {
    // (data-made-leave="up": out of view above as it fades)
    new_head(c, station, state, new_scene_w, fn(i) { new_part(c, i, state, true) })
    if !(state is Held(_)) {
      // what is sent waits for its quota, or its station went as it was written in (the page stays, said so)
      new_notices(c, v, station, col, part=fn(i) { new_part(c, i, state, true) })
    }
    new_composer_place(c, src, w, frame, v, address, station, state, col)
    // (data-made-leave="fade": fading where it is)
    new_part(c, new_combos(c, src, w, v, state is Going(_, _)), state, false)
    match state {
      Held(error) =>
        if error != "" {
          c.text(error, style=new_error) |> ignore
        } else {
          @sf.wait_line(c, @sf.t("common.readingStations"), key="new")
        }
      _ => {
        // what it waits for, in a line of its own under the composer
        match text(v, "problem") {
          "" => ()
          p => new_part(c, c.text(p, style=new_status), state, false)
        }
        new_part(c, new_offer(c, src, frame, station, state, hung=true), state, false)
      }
    }
  })
}

///|
/// Its column (newChat: in the middle of the pane, 32 in; newChatInner: 720 at most, its parts 10 apart and centred),
/// `body` given its width.
fn new_column(c : @ui.Ctx, body : (Double) -> Unit) -> Unit {
  let col = dmin(new_column_w, c.width - 2.0 * new_column_in)
  c.box(style=new_page_box, fn() { c.box(style=new_inner.then(@ui.style(w=Fixed(col))), fn() { body(col) }) |> ignore })
  |> ignore
}

///|
/// Part `i` of the page wide as it leaves: `up`, out of view above as it fades (madeChat.ts: translateY(-32px)
/// scale(.96)); else fading where it is. While it stays, as it is.
fn new_part(c : @ui.Ctx, i : Int, state : NewState, up : Bool) -> Unit {
  match state {
    Going(u, _) if up => c.look(i, @ui.look(alpha=1.0 - u, dy=-new_leave_rise * u, scale=1.0 - new_leave_shrink * u))
    Going(_, f) => c.look(i, @ui.look(alpha=1.0 - f))
    _ => ()
  }
}

///|
/// The composer's choices wide (NewChat.tsx toolbar), in its row: the page's controls (new_controls).
fn new_tools(c : @ui.Ctx, src : Source, w : Workspace, v : Json?, station : Json?) -> Unit {
  new_controls(c, src, w, v, station, false, false)
}

// ── both ──────────────────────────────────────────────────────────────────

///|
/// The page's composer (ComposerSlot, the mobile host's): the station's new chat's draft, `width` wide, roomy wide with
/// the choices in its row; locked while nothing can run it (no model, no runtime) or while its stations are read. Its
/// place measured (what the scene leaving keeps clear); gone to the chat (`Going`), its place as it was. Held on no
/// station (none started on yet, the stations' first value not come): its place, no draft asked for.
fn new_composer_place(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  frame : NewChatFrame,
  v : Json?,
  address : String,
  station : Json?,
  state : NewState,
  width : Double,
) -> Unit {
  let wide = c.width >= @sf.page_narrow_most
  match state {
    Going(_, _) => list_space(c, @sfbase.fresh.room)
    Held(_) if address == "" => list_space(c, @motion.measured(c, "new/composer").unwrap_or(0.0))
    _ => {
      let held = state is Held(_)
      let spec : ComposerSpec = {
        station: address,
        draft: "new:" + address,
        session: "",
        placeholder: @sf.t("web-main.newChat.placeholder"),
        toolbar: if wide && !held { Some(fn() { new_tools(c, src, w, v, station) }) } else { None },
        roomy: wide,
        locked: held || text(v, "runtime") == "" || field(v, "model") is None,
        offline: false,
      }
      let name = text(station, "name")
      let place = c.box(style=new_composer_box, fn() {
        c.sized(width, c.height, fn() {
          composer(c, src, w, spec, fn(d) { new_send(c, src, frame, v, address, name, d) })
        })
      })
      // over what is under it on the page (the web's dock, over the page): going between its places, it passes over
      // what is there
      c.put_over(place)
      @motion.measure(c, place, "new/composer")
    }
  }
}

///|
/// What is wrong for now, over the composer (mNewSpent, spentNotice): what is sent waits for its quota; its station went as
/// it was written in.
fn new_notices(c : @ui.Ctx, v : Json?, station : Json?, width : Double, part? : (Int) -> Unit = fn(_) {  }) -> Unit {
  match text(v, "spent") {
    "" => ()
    spent => part(new_notice(c, spent, width))
  }
  if flag(v, "down") {
    part(new_notice(c, @sf.t("web-main.newChat.down", args=[("name", new_station_words(station))]), width))
  }
}

///|
/// A line of what is wrong for now (spentNotice, mNewSpent): the amber's 12% under it, `width` wide.
fn new_notice(c : @ui.Ctx, words : String, width : Double) -> Int {
  c.box(style=new_notice_box.then(@ui.style(w=Fixed(width))), fn() { c.text(words, style=new_notice_words) |> ignore })
}

///|
/// The frequent combinations (FrequentCombos): their name over them, each one press to pick (`newChat.pick`), the one
/// in use pressed in; `leaving`, none taken. Nothing when there are none.
fn new_combos(c : @ui.Ctx, src : Source, w : Workspace, v : Json?, leaving : Bool) -> Int {
  let combos = items(v, "frequent")
  if combos.length() == 0 {
    return c.box(fn() {  })
  }
  let b = c.box(style=combos_box, fn() {
    c.text(@sf.t("web-main.combos.short"), style=combos_label) |> ignore
    c.box(style=combos_choices, flow=true, fn() {
      for combo in combos {
        let v = Some(combo)
        let selected = flag(v, "selected")
        let id = c.id("new/combo/" + text(v, "runtime") + ":" + text(v, "model") + ":" + text(v, "effort"))
        c.cursor(id, Hand)
        if c.clicked(id) && !leaving {
          let m : Map[String, Json] = {
            "model": Json::string(text(v, "model")),
            "runtime": Json::string(text(v, "runtime")),
          }
          m["effort"] = match text(v, "effort") {
            "" => Json::null()
            e => Json::string(e)
          }
          c.tell("new/pick", fn() { @sfbase.pick_new(src, w.id, m) })
        }
        let lit = selected || c.lit(id)
        let chip = c.box(style=if selected { combo_on } else { combo_off }, id~, fn() {
          c.text(text(v, "label"), style=if lit { combo_words_lit } else { combo_words }) |> ignore
        })
        c.semantics(chip, Button, id~, label=text(v, "label"), check=if selected { On } else { Off })
      }
    })
    |> ignore
  })
  c.semantics(b, Group, label=@sf.t("web-main.combos.label"))
  b
}

///|
/// The machine's own sessions to go on with, where it kept any (MachineSessions); nothing while its stations are read,
/// nor read only. `hung`: out of the page's flow, hung under what is over it (newChatOffer): it comes once the station
/// has said what there is, and taking room then it would move what the page centres, the composer with it; else the
/// scene's last part (narrow, where what is over it stays as it comes).
fn new_offer(c : @ui.Ctx, src : Source, frame : NewChatFrame, station : Json?, state : NewState, hung~ : Bool) -> Int {
  if state is Held(_) || !(field(station, "overview") is Some(Object(_))) || src.read_only {
    return c.box(fn() {  })
  }
  let offer = fn() { @settings.machine_sessions_offer(c, frame.core, text(station, "station"), text(station, "name")) }
  if !hung {
    return c.box(style=new_offer_box, offer)
  }
  c.box(style=new_offer_hold, fn() { c.box(style=new_offer_hung, left=0.0, top=0.0, right=0.0, offer) |> ignore })
}

///|
/// The page's head, the same at every width (NewChat.tsx's and the mobile page's say the same): the picture
/// (Illustration "new-chat") `art_w` wide, what to do, where it starts (while its stations are read, two lines
/// breathing in its place, still once what they wait on failed); each part given to `part` (how it leaves).
fn new_head(c : @ui.Ctx, station : Json?, state : NewState, art_w : Double, part : (Int) -> Unit) -> Unit {
  part(@sf.drawable(c, new_scene_art(), art_w))
  part(c.box(style=new_heading_box, fn() { c.text(@sf.t("android-chat.new.heading"), style=new_title) |> ignore }))
  part(
    match state {
      Held(error) =>
        c.box(style=new_held_lines, fn() {
          new_held_line(c, new_held_line_long, error == "")
          new_held_line(c, new_held_line_short, error == "")
        })
      _ =>
        c.box(style=new_sub_box, fn() {
          c.text(@sf.t("android-chat.new.sub", args=[("station", new_station_words(station))]), style=new_sub)
          |> ignore
        })
    },
  )
}

///|
fn new_scene_art() -> String {
  if @sf.theme().dark {
    "illus_new_chat_dark"
  } else {
    "illus_new_chat"
  }
}

///|
/// A line of words to come, breathing (`breathing` false: still, what it waits on failed), `w` wide in the middle of a
/// line of the page's words.
fn new_held_line(c : @ui.Ctx, w : Double, breathing : Bool) -> Unit {
  c.box(style=new_held_line_box, fn() { @sf.bar(c, Px(w), held_bar_h, breathing~) }) |> ignore
}

///|
/// No station at all in the workspace (FirstStation): the first to add.
fn new_first_station(c : @ui.Ctx) -> Unit {
  new_alone(
    c,
    if @sf.theme().dark { "illus_no_station_dark" } else { "illus_no_station" },
    @sf.t("android-settings.station.first"),
    @sf.t("android-settings.station.firstNote"),
  )
}

///|
/// None of them up (mNewNone, NewChat's `!view`): said so, and how one comes.
fn new_none_up(c : @ui.Ctx) -> Unit {
  new_alone(
    c,
    if @sf.theme().dark { "illus_station_offline_dark" } else { "illus_station_offline" },
    @sf.t("android-chat.new.offline.title"),
    @sf.t("android-chat.new.offline.text", args=[("app", "still.fail")]),
  )
}

///|
/// A page of a picture, a title and what it means, in the middle of the page.
fn new_alone(c : @ui.Ctx, art : String, title : String, note : String) -> Unit {
  c.box(style=new_page_box, fn() {
    c.box(style=new_alone_box, fn() {
      @sf.drawable(c, art, new_scene_narrow_w) |> ignore
      c.text(title, style=new_alone_title) |> ignore
      c.text(note, style=new_sub) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// Nothing to run a chat with yet (NewChat's `blocked`: FirstOne): a station none of whose profiles is open here, what
/// to add; one whose profiles are not shared with this workspace, whom to ask; one with no model picked, where to pick
/// them; the station chosen anew among several.
fn new_blocked(c : @ui.Ctx, src : Source, w : Workspace, v : Json?, station : Json?) -> Unit {
  let address = text(station, "station")
  let name = new_station_words(station)
  let blocked = text(v, "blocked")
  let title = match blocked {
    "profile" => @sf.t("web-main.newChat.addProfileFor", args=[("name", name)])
    "shared" => @sf.t("web-main.newChat.notShared", args=[("name", name)])
    _ => @sf.t("web-main.newChat.pickModels")
  }
  let lead = match blocked {
    "profile" =>
      @sf.t("web-pages.profiles.lead", args=[("subscription", @sf.t("web-pages.profiles.leadSubscription"))])
    "shared" => text(v, "problem")
    _ => @sf.t("web-main.newChat.noModelsLead", args=[("name", name)])
  }
  new_column(c, fn(_) {
    @sf.first_one(
      c,
      title,
      lead~,
      art=fn() {
        @sf.drawable(c, if @sf.theme().dark { "illus_no_profile_dark" } else { "illus_no_profile" }, new_scene_w)
        |> ignore
      },
      fn() {
        match blocked {
          "profile" =>
            if @sf.button(c, @sf.t("web-main.newChat.addProfile"), key="new/add-profile", tone=Primary, icon="plus") {
              open_page(Setting(@settings.Route::NewProfile(address)))
            }
          "shared" => ()
          _ =>
            if @sf.button(c, @sf.t("web-main.newChat.goPickModels"), key="new/pick-models", tone=Primary) {
              open_page(Setting(@settings.Route::Profiles(address)))
            }
        }
        if items(v, "stations").length() > 1 {
          new_station_control(c, src, w, v, station, false, false)
        }
      },
    )
  })
}

///|
/// The new chat's first message (draft.ts send with `first`, NewChat.tsx useEnsureChat, onSending, onSent): its words
/// and files taken off the composer where they were typed, carried there while the chat is made (once a page:
/// `newChat.create`, made anew when the picks changed), then sent into it (`chat.send`); the page becomes the chat, its
/// first words in its list from now and going on there, what is written meanwhile going on into the chat's draft
/// (`composer.carry`). The chat not made, or the message never taken in: what was taken back in the composer, saying
/// why.
fn new_send(
  c : @ui.Ctx,
  src : Source,
  frame : NewChatFrame,
  v : Json?,
  station : String,
  name : String,
  d : Writing,
) -> Unit {
  let fresh = @sfbase.fresh
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  if fresh.starting {
    return
  }
  let words = d.text.trim(chars=" \n\t").to_string()
  let up = d.files.filter_map(fn(f) { field(Some(f), "done") })
  // (its words where they were typed while the chat is made, its files where their tiles were: carried)
  @sfbase.flight_carry_start(
    c,
    d.key,
    words,
    flying_files(c, d),
    field=composer_field_key,
    font=@sf.theme().t.input,
    line=@sf.theme().t.input_line,
    // (the flight where the chat opens has: in this page's place, Android's; beside it, the web's)
    desk=!frame.in_place,
  )
  fresh.starting = true
  @sfbase.writing_starting(src, d, true)
  let sig = @sfbase.picked_sig(v)
  let give_back = fn(e : Json) {
    fresh.starting = false
    @sfbase.flight_carry_gone(d.key)
    @sfbase.writing_starting(src, d, false)
    writing_restore(src, d, text(Some(e), "message"))
  }
  writing_take(src, d, fn(taken) {
    guard taken is Some(_) else {
      fresh.starting = false
      @sfbase.flight_carry_gone(d.key)
      @sfbase.writing_starting(src, d, false)
      return
    }
    let send = fn(key : String) {
      let params : Map[String, Json] = {
        "station": Json::string(station),
        "session": Json::string(key),
        "text": Json::string(text(taken, "text")),
        "attachments": Json::array(items(taken, "attachments")),
        "quotes": Json::array(items(taken, "quotes")),
      }
      let going = items(taken, "uploads")
      if going.length() > 0 {
        params["uploads"] = Json::array(going)
      }
      (src.call)("chat.send", Json::object(params), fn(res) {
        match res {
          Err(e) => give_back(e)
          Ok(_) => {
            fresh.sent = true
            fresh.starting = false
            @sfbase.writing_starting(src, d, false)
            // the page becomes the chat, in place, its first words in its list from now and going on there; called
            // what the page was (新对话) until someone names it, as the core calls it
            let r : ChatRef = { station, session: key, title: @sf.t("web-main.newChat.title"), station_name: name }
            let rk = station + "\u{1}" + key
            @sfbase.flight_carry_into(d.key, station + ":" + key, rk, sent_local(rk, None, words, up))
            // what is written meanwhile goes on in the chat's draft (dock.tsx carryTo)
            @sfbase.writing_carry(src, d.key, station + ":" + key)
            fresh.scene = v
            fresh.became = Some(r)
            fresh.room = @motion.measured(c, "new/composer").unwrap_or(0.0)
            // (its choices fade as where the chat opens has them: in this page's place, Android's)
            @sfbase.became_starts(wide=!frame.in_place)
            new_chat_reset()
            (frame.sent)(r)
            app.nav.become(Chat(r))
          }
        }
      })
    }
    if fresh.made != "" {
      send(fresh.made)
    } else {
      (src.call)("newChat.create", { "station": Json::string(station) }, fn(res) {
        match res {
          Ok(made) =>
            match text(Some(made), "key") {
              "" => give_back({ "message": Json::string("newChat.create: no key") })
              key => {
                fresh.made = key
                fresh.made_sig = sig
                send(key)
              }
            }
          Err(e) => give_back(e)
        }
      })
    }
  })
}

// ── the run picker ────────────────────────────────────────────────────────


///|
/// How far what leaves goes up, and how much smaller it gets.
let new_leave_rise : Double = 32.0

///|
let new_leave_shrink : Double = 0.04

///|
/// The column wide (newChatInner: 720 at most, 32 in from the pane's sides), the scene's width (ILLUS_SIZE: 320;
/// narrow 230), a mark and a chevron in a choice.
let new_column_w : Double = 720.0

///|
let new_column_in : Double = 32.0

///|
let new_scene_w : Double = 320.0

///|
let new_scene_narrow_w : Double = 230.0

///|
let new_mark : Double = 14.0

///|
let new_chevron : Double = 12.0

///|
/// The scene's height narrow as its list guesses it before it is laid out.
let new_scene_guess : Double = 600.0

///|
/// While the stations are read, the widths of where it runs and what it runs on breathing in their places, as high as
/// the choices; the two lines of what it does breathing.
let held_station_w : Double = 96.0

///|
let held_model_w : Double = 150.0

///|
let held_chooser_h : Double = 30.0

///|
let new_held_line_long : Double = 250.0

///|
let new_held_line_short : Double = 170.0

///|
let held_bar_h : Double = 12.0

///|
/// A glass choice's corner (a capsule 30 high), a station's mark in the station's pick.
let glass_chooser_corner : Double = 15.0

///|
let station_row_mark : Double = 22.0

///|
/// The page's ground, its whole pane; its bar's room; what is left under it.
// kept across runs: a value (no field of it changes)
let new_ground : @ui.Style = @ui.css("w=Full h=Full bg=Bg")

///|
// kept across runs: a value (no field of it changes)
let new_frame_box : @ui.Style = @ui.css("w=Full h=Full")

///|
// kept across runs: a value (no field of it changes)
let new_bar_room : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let new_room : @ui.Style = @ui.style(w=Full, h=@sf.grow)

///|
/// The scene narrow, all the page (mNewBody: 30 in, 10 under, its parts 6 apart, centred), the foot's room under it.
// kept across runs: a value (no field of it changes)
let new_scene_room : @ui.Style = @ui.style(w=Full, h=@sf.grow, clip=true)

///|
// kept across runs: a value (no field of it changes)
let new_scene_column : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let new_scene_narrow : @ui.Style = @ui.css("w=Full px=S8 pt=S8 pb=S2_5 gap=S1_5 align=ACenter")

///|
/// The heading narrow (h2: 6 over it).
// kept across runs: a value (no field of it changes)
let new_heading_box : @ui.Style = @ui.css("w=Full pt=S1_5")

///|
// kept across runs: a value (no field of it changes)
let new_held_lines : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let new_held_line_box : @ui.Style = @ui.css("w=Full h=S5 align=ACenter justify=JCenter")

///|
/// What keeps it from starting narrow (mNewProblem: 6 over it).
// kept across runs: a value (no field of it changes)
let new_problem_box : @ui.Style = @ui.css("w=Full pt=S1_5")

///|
/// The foot narrow, over the scene's end: the band, and as the page becomes the chat the composer's place under it.
// kept across runs: a value (no field of it changes)
let new_foot : @ui.Style = @ui.css("w=Full align=ACenter")

///|
/// The band (mNewFoot, mNewBottom): 8 over the choices; its corners square but where it lies in a panel's.
// kept across runs: a value (no field of it changes)
let new_band : @ui.Style = @ui.css("w=Full pt=S2 align=ACenter radius=InnerOr(Sharp)")

///|
/// The choices narrow (mChoosers: 6 apart, 6 over and under, 2 in).
// kept across runs: a value (no field of it changes)
let new_choosers_row : @ui.Style = @ui.css("row w=Full px=S0_5 py=S1_5 gap=S1_5 align=ACenter")

///|
/// A glass choice (mChooser): 30 high, 12 in, 6 between its parts, a capsule.
// kept across runs: a value (no field of it changes)
let glass_chooser_box : @ui.Style = @ui.style(
  row=true,
  h=@sf.glass_chooser_h,
  px=S3,
  gap=S1_5,
  align=ACenter,
  radius=Full,
  clip=true,
)

///|
// kept across runs: a value (no field of it changes)
let new_capsule_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Fg, wrap=false, w=Cut)

///|
/// A station's name in its control: cut short past 128 (mChooser's max-width).
// kept across runs: a value (no field of it changes)
let new_station_name : @ui.Style = @ui.style(max_w=@sf.glass_chooser_station_most, clip=true)

///|
/// A control in the composer's row (Chooser: 28 high, 8 in, its parts 6 apart, the hover's ground).
// kept across runs: a value (no field of it changes)
let new_capsule_in_row : @ui.Style = @ui.css("row h=S7 px=S2 gap=S1_5 align=ACenter radius=Lg clip hovered{bg=Hover}")

///|
/// A station's row in its pick (PickRow): its mark, its name over what it is, a check; 12 by 8 in.
// kept across runs: a value (no field of it changes)
let station_row : @ui.Style = @ui.css("row w=Full px=S2 py=S3 gap=S3 align=ACenter radius=Lg")

///|
// kept across runs: a value (no field of it changes)
let station_row_words : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let station_row_name : @ui.TextStyle = @ui.text_style(size=Body, leading=L6, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let station_row_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L4, color=Muted)

///|
/// newChat: what it holds in the middle of the pane; newChatInner: its parts 10 apart, centred.
// kept across runs: a value (no field of it changes)
let new_page_box : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let new_inner : @ui.Style = @ui.css("gap=S2_5 align=ACenter")

///|
/// A page of a picture and a title alone (mNewNone): 30 in, 10 apart.
// kept across runs: a value (no field of it changes)
let new_alone_box : @ui.Style = @ui.css("w=Full px=S8 gap=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let new_alone_title : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Fg, center=true, w=Full)

///|
/// 新对话 (newChatTitle: the heading's, 600).
// kept across runs: a value (no field of it changes)
let new_title_box : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let new_title : @ui.TextStyle = @ui.text_style(size=Heading, weight=Semibold, color=Fg, center=true, w=Full)

///|
/// What it does (newChatSub: 13 on 20, muted, 8 under it).
// kept across runs: a value (no field of it changes)
let new_sub_box : @ui.Style = @ui.css("w=Full pb=S2")

///|
// kept across runs: a value (no field of it changes)
let new_sub : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, center=true, w=Full)

///|
/// The composer: the column's whole width, its words from the left.
// kept across runs: a value (no field of it changes)
let new_composer_box : @ui.Style = @ui.css("w=Full")

///|
/// What it waits for (newChatStatus), why its stations could not be read (fieldError).
// kept across runs: a value (no field of it changes)
let new_status : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, center=true, w=Full)

///|
// kept across runs: a value (no field of it changes)
let new_error : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Danger, center=true, w=Full)

///|
/// The offer of the machine's sessions as the scene's last part narrow: 8 over it.
// kept across runs: a value (no field of it changes)
let new_offer_box : @ui.Style = @ui.css("w=Full pt=S2 align=ACenter")

///|
/// Where it hangs wide, under the status line (newChatOffer: no room of its own, what it holds from its top, in the
/// middle).
// kept across runs: a value (no field of it changes)
let new_offer_hold : @ui.Style = @ui.css("w=Full h=S0")

///|
// kept across runs: a value (no field of it changes)
let new_offer_hung : @ui.Style = @ui.css("align=ACenter")

///|
/// spentNotice: the amber's 12% under 13's words, 8 by 12 in, 10 round, 8 under it.
// kept across runs: a value (no field of it changes)
let new_notice_box : @ui.Style = @ui.css("px=S3 py=S2 mb=S2 radius=Lg bg=A(Warn,O10)")

///|
// kept across runs: a value (no field of it changes)
let new_notice_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L5, color=Fg, w=Full)

///|
/// The way to where models are chosen (controls.css.ts chooser as a link): 28 high, 8 in, the link's ink.
// kept across runs: a value (no field of it changes)
let new_link_box : @ui.Style = @ui.css("row h=S7 px=S2 radius=Lg align=ACenter hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let new_link : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Link, wrap=false, w=Cut)

///|
/// FrequentCombos.css.ts frequent: its name over them, 8 apart, 12 over and under; label: 12, muted.
// kept across runs: a value (no field of it changes)
let combos_box : @ui.Style = @ui.css("w=Full py=S3 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let combos_label : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// choices: wrapped, centred, 6 apart.
// kept across runs: a value (no field of it changes)
let combos_choices : @ui.Style = @ui.css("row w=Full gap=S1_5 justify=JCenter")

///|
/// combo: 8 by 10 in, the field's corner, on the pointer's ground; pressed in, on the chosen's; its words 13 on 18, muted
/// (the ink pointed at or pressed in).
// kept across runs: a value (no field of it changes)
let combo_off : @ui.Style = @ui.css("px=S2_5 py=S2 radius=Xl bg=Hover")

///|
// kept across runs: a value (no field of it changes)
let combo_on : @ui.Style = combo_off.then(@ui.css("bg=Selected"))

///|
// kept across runs: a value (no field of it changes)
let combo_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let combo_words_lit : @ui.TextStyle = combo_words.then(@ui.text_style(color=Fg))
