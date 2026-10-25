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
/// What the page keeps of its own: its station chooser's menu open (wide), the run picker showing who runs it, which
/// of its picks is asked open as it is next drawn narrow (a fixture's: new_chat_ask).
priv struct NewChatPage {
  mut station_menu : Bool
  mut accounts : Bool
  mut asked : String
}

///|
let new_chat_state : NewChatPage = { station_menu: false, accounts: false, asked: "" }

///|
fn new_chat_reset() -> Unit {
  new_chat_state.station_menu = false
  new_chat_state.accounts = false
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
/// The page narrow (the web's mobile NewChatOn, mNewBody, mNewFoot): the scene over what is left, scrolled when it
/// does not fit (the keyboard up, the choices and the composer stay over it); at its foot what is wrong for now, the
/// choices, the composer where a chat's is (chat_composer: the page becomes the chat, its composer where it was).
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
  let room = c.box(style=new_scene_room, fn() {
    c.list("new/scene", 1, new_scene_guess, fn(_) {
      let scene = c.box(style=new_scene_narrow, fn() { new_scene_narrow_body(c, src, w, frame, v, station, state) })
      // up out of view as it fades, a little smaller, from its middle (madeChat.ts: translateY(-32px) scale(.96))
      if going {
        c.look(scene, @ui.look(alpha=1.0 - up, dy=-new_leave_rise * up, scale=1.0 - new_leave_shrink * up))
      }
    })
    |> ignore
  })
  let width = composer_width(c.width)
  // (in a panel of its own, at its foot: as far from its foot as from its sides, in the panel's corners, as a chat's)
  let apart = @sf.in_pane() && frame.foot == 0.0
  let foot = c.box(style=if apart { chat_foot_apart() } else { chat_foot }, fn() {
    if !going {
      new_notices(c, v, station, width)
    }
    c.box(style=@ui.style(w=Fixed(width)), fn() {
      new_choosers(c, src, w, frame, v, station, state)
      new_composer_place(c, src, w, frame, v, address, station, state, width)
    })
    |> ignore
  })
  if going {
    c.look(foot, @ui.look(alpha=1.0 - fade))
  }
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
  @sf.drawable(c, new_scene_art(), new_scene_narrow_w) |> ignore
  c.box(style=new_heading_box, fn() { c.text(@sf.t("android-chat.new.heading"), style=new_title) |> ignore }) |> ignore
  match state {
    Held(error) =>
      c.box(style=new_held_lines, fn() {
        new_held_line(c, new_held_line_long, error == "")
        new_held_line(c, new_held_line_short, error == "")
      })
      |> ignore
    _ =>
      c.text(@sf.t("android-chat.new.sub", args=[("station", new_station_words(station))]), style=new_sub) |> ignore
  }
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
  new_offer(c, src, frame, station, state) |> ignore
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
    let address = text(station, "station")
    let t = @sf.theme()
    if glass_chooser(
        c,
        "new/station",
        fn() { @sf.station_icon(c, text(station, "emoji"), text(station, "icon"), new_mark, t.p.text) },
        text(station, "name"),
        @sf.glass_chooser_station_most,
        false,
      ) &&
      !going ||
      take_asked("station") {
      @sf.panel(
        @sf.t("android-chat.new.station.pick"),
        fn(c, close) { station_rows(c, src, w, v, close) },
        from=Of(c.id("new/station")),
      )
    }
    let p = field(v, "pick")
    let runtime = text(v, "runtime")
    let model = text(field(v, "model"), "model")
    if flag(v, "waiting") {
      @sf.bar(c, Px(held_model_w), held_chooser_h, breathing=true)
    } else if p is None || items(p, "options").length() == 0 {
      // nothing to choose from: the way to where models are enabled
      if glass_chooser(c, "new/models", fn() {  }, @sf.t("android-chat.new.noModels"), Full, false) && !going {
        open_page(Place("profiles"))
      }
    } else {
      let label = if runtime == "" || model == "" { @sf.t("android-chat.pick.model") } else { triple_label(p) }
      // (a model's maker: the core's Maker, its id the mark's)
      let maker = match text(field(field(p, "valueOption"), "maker"), "id") {
        "" => text(field(field(v, "model"), "maker"), "id")
        m => m
      }
      let lead = if runtime == "" || model == "" {
        fn() {  }
      } else {
        fn() { @sf.maker_mark(c, maker, runtime, new_mark) |> ignore }
      }
      if (glass_chooser(c, "new/model", lead, label, Full, true) && !going) || take_asked("model") {
        // picked from what it runs on now, each time it is opened
        new_chat_state.accounts = false
        pick_draft(src, address, "new", { "open": Json::boolean(true) })
        @sf.panel(
          @sf.t("android-chat.new.model"),
          fn(c, close) { run_picker(c, src, address) },
          from=Of(c.id("new/model")),
          tall=run_picker_tall,
          foot=fn(c, close) { run_picker_foot(c, src, frame.core, address, close) },
        )
      }
    }
  })
  |> ignore
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
/// A choice over the composer (mChooser, NewChat.kt Chooser): a capsule of the composer's glass, its mark, its words
/// (cut short, `most` wide at most), a chevron. True on the frame after it was pressed.
fn glass_chooser(c : @ui.Ctx, key : String, lead : () -> Unit, label : String, most : @ui.Len, chevron : Bool) -> Bool {
  let p = @sf.theme().p
  let id = c.id(key)
  c.cursor(id, Hand)
  let b = c.box(style=glass_chooser_box.then(@ui.style(max_w=most)), glass=@sf.glass_floating(), id~, fn() {
    lead()
    c.text(label, style=glass_chooser_words) |> ignore
    if chevron {
      @sf.icon(c, "chevron-down", size=new_chevron, color=p.muted) |> ignore
    }
    @sf.press_ripple(c, id, glass_chooser_corner)
  })
  c.semantics(b, Button, id~, label~)
  c.clicked(id)
}

///|
/// What the model capsule says (NewChat.kt tripleLabel): the model, the runtime where there is a choice, how hard it
/// thinks, how fast, who runs it when that matters.
fn triple_label(p : Json?) -> String {
  let value = field(p, "value")
  let on = field(p, "valueOption")
  let parts : Array[String] = []
  parts.push(
    match text(on, "name") {
      "" =>
        match text(value, "model") {
          "" => @sf.t("android-chat.pick.model")
          m => m
        }
      n => n
    },
  )
  if !flag(p, "runtimeFixed") && items(on, "runtimes").length() > 1 {
    parts.push(@settings.runtime_label(text(value, "runtime")))
  }
  parts.push(
    match text(value, "effort") {
      "" => @sf.t("android-chat.pick.effort.default")
      e => e
    },
  )
  match text(p, "fastText") {
    "" => ()
    f => parts.push(f)
  }
  match text(field(p, "account"), "text") {
    "" => ()
    a => parts.push(a)
  }
  parts.join(" · ")
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
    let row = c.box(style=station_row, id~, fn() {
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
  let here = new_station_words(station)
  new_column(c, fn(col) {
    // (data-made-leave="up": out of view above as it fades)
    new_part(c, new_scene(c), state, true)
    new_part(
      c,
      c.box(style=new_title_box, fn() { c.text(@sf.t("web-main.newChat.title"), style=new_title) |> ignore }),
      state,
      true,
    )
    let sub = match state {
      Held(_) => @sf.t("web-main.newChat.subChosen")
      _ => @sf.t("web-main.newChat.sub", args=[("name", here)])
    }
    new_part(c, c.box(style=new_sub_box, fn() { c.text(sub, style=new_sub) |> ignore }), state, true)
    if !(state is Held(_)) {
      // its station went as it was written in (the page stays, said so), or what is sent waits for its quota
      if flag(v, "down") {
        new_part(c, new_notice(c, @sf.t("web-main.newChat.down", args=[("name", here)]), col), state, true)
      }
      match text(v, "spent") {
        "" => ()
        spent => new_part(c, new_notice(c, spent, col), state, true)
      }
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
        new_part(c, new_offer(c, src, frame, station, state), state, false)
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
/// The composer's choices wide (NewChat.tsx toolbar): where it runs (its stations, a chooser over the composer), what
/// it runs on (the model control, its panel over the composer); with nothing to run, the way to where models are
/// chosen.
fn new_tools(c : @ui.Ctx, src : Source, w : Workspace, v : Json?, station : Json?) -> Unit {
  if text(station, "name") != "" {
    station_chooser(c, src, w, v, station, Top)
  }
  if text(v, "runtime") == "" || field(v, "model") is None {
    let id = c.id("new/no-models")
    c.cursor(id, Hand)
    if c.clicked(id) {
      open_page(Place("profiles"))
    }
    let b = c.box(style=new_link_box, id~, fn() { c.text(@sf.t("web-main.newChat.noModels"), style=new_link) |> ignore })
    c.semantics(b, Link, id~, label=@sf.t("web-main.newChat.noModels"))
  } else {
    model_triple(c, src, text(station, "station"), "new", up=true, page=field(v, "pick"), small=true)
  }
}

///|
/// Where it runs wide (Chooser of the stations, StationMark before each name), the one it is on checked; chosen, the
/// core picks it (`newChat.pick`).
fn station_chooser(c : @ui.Ctx, src : Source, w : Workspace, v : Json?, station : Json?, side : @ui.Side) -> Unit {
  let address = text(station, "station")
  let entries = items(v, "stations").map(fn(s) {
    let s = Some(s)
    @kit.menu_radio(text(s, "id"), text(s, "station") == address, label=text(s, "name"))
  })
  let m = @sf.chooser(c, "new/station", text(station, "name"), entries, new_chat_state.station_menu, side~, lead=fn(ink) {
    @sf.station_mark(c, text(station, "emoji"), text(station, "icon"), new_mark, ink)
  })
  new_chat_state.station_menu = m.open
  match m.chosen {
    // (told once the frame is built: what was chosen, once)
    Some(id) => c.tell("new/pick", fn() { @sfbase.pick_new(src, w.id, { "station": Json::string(id) }) })
    None => ()
  }
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
/// What is wrong for now, over the composer narrow (mNewSpent): what is sent waits for its quota; its station went as
/// it was written in.
fn new_notices(c : @ui.Ctx, v : Json?, station : Json?, width : Double) -> Unit {
  match text(v, "spent") {
    "" => ()
    spent => new_notice(c, spent, width) |> ignore
  }
  if flag(v, "down") {
    new_notice(c, @sf.t("web-main.newChat.down", args=[("name", new_station_words(station))]), width) |> ignore
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
/// nor read only.
fn new_offer(c : @ui.Ctx, src : Source, frame : NewChatFrame, station : Json?, state : NewState) -> Int {
  if state is Held(_) || !(field(station, "overview") is Some(Object(_))) || src.read_only {
    return c.box(fn() {  })
  }
  c.box(style=new_offer_box, fn() {
    @settings.machine_sessions_offer(c, frame.core, text(station, "station"), text(station, "name"))
  })
}

///|
/// The scene (Illustration "new-chat").
fn new_scene(c : @ui.Ctx) -> Int {
  @sf.drawable(c, new_scene_art(), new_scene_w)
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
          station_chooser(c, src, w, v, station, Bottom)
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
  let going = going_up(d)
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
/// What a new chat runs on narrow (NewChat.kt openRunPicker; the web's mobile pickModel, pickRuntime, pickEffort and
/// its speed's sheet in one), on station `station`, in a panel of the presenters: the models in a column by series,
/// the runtime, how hard it thinks and how fast beside them; who runs it in the foot (its list in the panel's place,
/// and back). Picks are a draft (`pick.set`) until 确定 (`pick.save`); closed otherwise, nothing changes. A model
/// another station has, picked: the foot borrows it, asked again first.
fn run_picker(c : @ui.Ctx, src : Source, station : String) -> Unit {
  let topic = (src.topic)("pick", pick_params(station, "new"))
  let v = topic.value
  if v is None {
    @sf.waiting(c, error=match topic.error {
      Some(e) => text(Some(e), "message")
      None => ""
    })
    return
  }
  if new_chat_state.accounts {
    run_accounts(c, src, station, v)
    return
  }
  let draft = field(v, "draft")
  let set = fn(patch : Map[String, Json]) { pick_draft(src, station, "new", patch) }
  // side by side: the models (by series, in the core's order), and what goes with the one picked
  c.box(style=run_columns, fn() {
    c.box(style=run_models, fn() {
      let series : Array[(String, Array[Json])] = []
      for o in items(v, "options") {
        let who = match text(Some(o), "family") {
          "" => @sf.t("android-chat.pick.family.other")
          f => f
        }
        match series.search_by(fn(s) { s.0 == who }) {
          Some(i) => series[i].1.push(o)
          None => series.push((who, [o]))
        }
      }
      for s in series {
        if series.length() > 1 {
          run_label(c, s.0)
        }
        for o in s.1 {
          let opt = Some(o)
          let picked = text(v, "option") == text(opt, "model")
          let runtime = match items(opt, "runtimes").get(0) {
            Some(String(r)) => r
            _ => text(draft, "runtime")
          }
          if run_option(
              c,
              "pick/model/" + text(opt, "model"),
              text(opt, "name"),
              text(field(opt, "spent"), "text"),
              picked,
              Some(fn() { @sf.maker_mark(c, text(field(opt, "maker"), "id"), runtime, run_mark) |> ignore }),
              faint=text(opt, "availability") == "borrowable" && !picked,
            ) {
            set({ "model": Json::string(text(opt, "model")) })
          }
        }
      }
    })
    |> ignore
    c.box(style=run_side, fn() {
      let runtimes = items(v, "runtimes")
      if runtimes.length() > 0 {
        run_label(c, @sf.t("android-chat.new.runtime"))
        for r in runtimes {
          if r is String(rt) &&
            run_option(
              c,
              "pick/runtime/" + rt,
              @settings.runtime_label(rt),
              "",
              text(draft, "runtime") == rt,
              Some(fn() { @sf.maker_mark(c, "", rt, run_mark) |> ignore }),
            ) {
            set({ "runtime": Json::string(rt) })
          }
        }
      }
      run_label(c, @sf.t("android-chat.new.effort"))
      if run_option(c, "pick/effort/", @sf.t("android-chat.pick.default"), "", text(draft, "effort") == "", None) {
        set({ "effort": Json::null() })
      }
      for e in items(v, "efforts") {
        if e is String(ef) &&
          run_option(c, "pick/effort/" + ef, ef, "", text(draft, "effort") == ef, None) {
          set({ "effort": Json::string(ef) })
        }
      }
      if flag(v, "fastAvailable") {
        run_label(c, @sf.t("android-chat.new.speed"))
        let fast = field(draft, "fast")
        if run_option(
            c,
            "pick/fast/follow",
            @sf.t("android-chat.pick.speed.follow"),
            "",
            !(fast is Some(True) || fast is Some(False)),
            None,
          ) {
          set({ "fast": Json::null() })
        }
        if run_option(c, "pick/fast/standard", @sf.t("android-chat.pick.speed.standard"), "", fast is Some(False), None) {
          set({ "fast": Json::boolean(false) })
        }
        if run_option(c, "pick/fast/fast", "Fast", @sf.t("android-chat.new.fast.note"), fast is Some(True), None) {
          set({ "fast": Json::boolean(true) })
        }
      }
    })
    |> ignore
  })
  |> ignore
  // the model picked is another station's: said so over the foot
  let borrow = field(v, "borrow")
  if borrow is Some(Object(_)) {
    c.box(style=run_borrow_box, fn() {
      c.text(
        if flag(borrow, "allowed") {
          text(borrow, "note")
        } else {
          match text(borrow, "why") {
            "" => text(borrow, "note")
            why => why
          }
        },
        style=run_note,
      )
      |> ignore
    })
    |> ignore
  }
}

///|
/// The run picker's foot (the presenter's, in its foot corner): who runs it, and 确定 (or borrowing it); nothing while
/// its accounts are in its place.
fn run_picker_foot(c : @ui.Ctx, src : Source, core : Core, station : String, close : () -> Unit) -> Unit {
  let v = (src.topic)("pick", pick_params(station, "new")).value
  if v is None || new_chat_state.accounts {
    return
  }
  let borrow = field(v, "borrow")
  c.box(style=run_foot, fn() {
    let who = c.id("pick/who")
    c.cursor(who, Hand)
    if c.clicked(who) {
      new_chat_state.accounts = true
    }
    let p = @sf.theme().p
    c.box(style=run_who, id=who, fn() {
      c.text(@sf.t("android-chat.new.account"), style=run_who_lead) |> ignore
      c.text(text(v, "who"), style=if text(v, "whoLevel") != "" { run_who_amber } else { run_who_name }) |> ignore
      @sf.icon(c, "chevron-right", size=new_mark, color=p.muted) |> ignore
      @sf.press_ripple(c, who, run_who_corner)
    })
    |> ignore
    if borrow is Some(Object(_)) {
      let allowed = flag(borrow, "allowed")
      if @sf.button(c, text(borrow, "action"), key="pick/borrow", tone=Primary, disabled=!allowed) && allowed {
        @settings.confirm_borrow(core, station, "new", borrow)
      }
      return
    }
    let changed = flag(v, "changed")
    let dkey = "pick.save/" + station + "/new"
    if @sf.button(
        c,
        @sf.t(if changed { "android-chat.new.confirm" } else { "android-chat.new.unchanged" }),
        key="pick/save",
        tone=if changed { Primary } else { Plain },
        busy=doing(dkey),
      ) &&
      text(v, "option") != "" &&
      !doing(dkey) {
      if !changed || src.read_only {
        close()
      } else {
        act(src, @sf.t("android-chat.new.confirm"), dkey, "pick.save", Json::object(pick_params(station, "new")), ok=fn(_) {
          close()
        })
      }
    }
  })
  |> ignore
}

///|
/// Who runs it, in the run picker's place (NewChat.kt's accounts): back to the picker, 自动 with what the station's pick
/// is on now, then each account with what is left of it; picked, back to the picker.
fn run_accounts(c : @ui.Ctx, src : Source, station : String, v : Json?) -> Unit {
  let p = @sf.theme().p
  let draft = field(v, "draft")
  let back = c.id("pick/accounts-back")
  c.cursor(back, Hand)
  if c.clicked(back) {
    new_chat_state.accounts = false
  }
  c.box(style=run_accounts_head, fn() {
    c.box(style=run_back, id=back, fn() {
      @sf.icon(c, "chevron-left", size=run_back_icon, color=p.text) |> ignore
      @sf.press_ripple(c, back, run_back_corner)
    })
    |> ignore
    c.text(@sf.t("android-chat.new.account"), style=run_accounts_title) |> ignore
  })
  |> ignore
  c.box(style=run_accounts_list, fn() {
    match text(v, "dropped") {
      "" => ()
      dropped => c.box(style=run_dropped_box, fn() { c.text(dropped, style=run_dropped) |> ignore }) |> ignore
    }
    if run_option(c, "pick/account/auto", @sf.t("android-chat.new.auto"), text(v, "autoNote"), text(draft, "profile") == "", None) {
      pick_draft(src, station, "new", { "profile": Json::null() })
      new_chat_state.accounts = false
    }
    for a in items(v, "accounts") {
      let acc = Some(a)
      let quota = field(acc, "quotaLine")
      let runtime = match text(acc, "runtime") {
        "" => text(draft, "runtime")
        r => r
      }
      if run_option(
          c,
          "pick/account/" + text(acc, "id"),
          text(acc, "name"),
          text(quota, "text"),
          text(draft, "profile") == text(acc, "id"),
          Some(fn() { @sf.maker_mark(c, text(acc, "mark"), runtime, run_mark) |> ignore }),
          amber=text(quota, "level") != "",
        ) {
        pick_draft(src, station, "new", { "profile": Json::string(text(acc, "id")) })
        new_chat_state.accounts = false
      }
    }
  })
  |> ignore
}

///|
/// A column's name in the run picker (CascadeLabel).
fn run_label(c : @ui.Ctx, label : String) -> Unit {
  c.box(style=run_label_box, fn() { c.text(label, style=run_label_words) |> ignore }) |> ignore
}

///|
/// A choice in a column of the run picker (CascadeOption): the chosen one on the accent's pale ground, its words in
/// the accent and bold, a check; `faint`: another station's not borrowed yet; `amber`: what is said under it a warning.
/// True on the frame after it was pressed.
fn run_option(
  c : @ui.Ctx,
  key : String,
  label : String,
  sub : String,
  checked : Bool,
  lead : (() -> Unit)?,
  faint? : Bool = false,
  amber? : Bool = false,
) -> Bool {
  let p = @sf.theme().p
  let id = c.id(key)
  c.cursor(id, Hand)
  let b = c.box(style=if checked { run_option_on } else { run_option_box }, id~, fn() {
    match lead {
      Some(f) => f()
      None => ()
    }
    c.box(style=run_option_words, fn() {
      c.text(label, style=if checked {
        run_picked
      } else if faint {
        run_faint
      } else {
        run_words
      })
      |> ignore
      if sub != "" {
        c.text(sub, style=if amber { run_amber } else { run_note }) |> ignore
      }
    })
    |> ignore
    if checked {
      @sf.icon(c, "check", size=new_mark, color=p.accent) |> ignore
    }
    @sf.press_ripple(c, id, run_option_corner)
  })
  c.semantics(b, Button, id~, label~, check=if checked { On } else { Off })
  c.clicked(id)
}

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
/// The run picker: as tall as two thirds of the window (NewChat.kt openRunPicker: 66%), its marks, the corners its
/// rows ripple in, its back's icon.
let run_picker_tall : Double = 0.66

///|
let run_mark : Double = 16.0

///|
let run_option_corner : Double = 10.0

///|
let run_who_corner : Double = 12.0

///|
let run_back_corner : Double = 18.0

///|
let run_back_icon : Double = 20.0

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
/// The scene narrow in what is left over the foot (mNewBody: 30 in, 10 under, its parts 6 apart, centred).
// kept across runs: a value (no field of it changes)
let new_scene_room : @ui.Style = @ui.style(w=Full, h=@sf.grow, clip=true)

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
let glass_chooser_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Fg, wrap=false, w=Cut)

///|
/// A station's row in its pick (PickRow): its mark, its name over what it is, a check; 12 by 8 in.
// kept across runs: a value (no field of it changes)
let station_row : @ui.Style = @ui.css("row w=Full px=S2 py=S3 gap=S3 align=ACenter radius=Lg")

///|
// kept across runs: a value (no field of it changes)
let station_row_words : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let station_row_name : @ui.TextStyle = @ui.text_style(size=Base, leading=L6, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let station_row_note : @ui.TextStyle = @ui.text_style(size=Xs, leading=L4, color=Muted)

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
let new_alone_title : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Fg, center=true, w=Full)

///|
/// 新对话 (newChatTitle: the heading's, 600).
// kept across runs: a value (no field of it changes)
let new_title_box : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let new_title : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Semibold, color=Fg, center=true, w=Full)

///|
/// What it does (newChatSub: 13 on 20, muted, 8 under it).
// kept across runs: a value (no field of it changes)
let new_sub_box : @ui.Style = @ui.css("w=Full pb=S2")

///|
// kept across runs: a value (no field of it changes)
let new_sub : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, center=true, w=Full)

///|
/// The composer: the column's whole width, its words from the left.
// kept across runs: a value (no field of it changes)
let new_composer_box : @ui.Style = @ui.css("w=Full")

///|
/// What it waits for (newChatStatus), why its stations could not be read (fieldError).
// kept across runs: a value (no field of it changes)
let new_status : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, center=true, w=Full)

///|
// kept across runs: a value (no field of it changes)
let new_error : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Danger, center=true, w=Full)

///|
/// Where the offer of the machine's sessions hangs, under the status line (newChatOffer).
// kept across runs: a value (no field of it changes)
let new_offer_box : @ui.Style = @ui.css("w=Full align=ACenter")

///|
/// spentNotice: the amber's 12% under 13's words, 8 by 12 in, 10 round, 8 under it.
// kept across runs: a value (no field of it changes)
let new_notice_box : @ui.Style = @ui.css("px=S3 py=S2 mb=S2 radius=Lg bg=A(Warn,O10)")

///|
// kept across runs: a value (no field of it changes)
let new_notice_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L5, color=Fg, w=Full)

///|
/// The way to where models are chosen (controls.css.ts chooser as a link): 28 high, 8 in, the link's ink.
// kept across runs: a value (no field of it changes)
let new_link_box : @ui.Style = @ui.css("row h=S7 px=S2 radius=Lg align=ACenter hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let new_link : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Link, wrap=false, w=Cut)

///|
/// FrequentCombos.css.ts frequent: its name over them, 8 apart, 12 over and under; label: 12, muted.
// kept across runs: a value (no field of it changes)
let combos_box : @ui.Style = @ui.css("w=Full py=S3 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let combos_label : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

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
let combo_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L5, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let combo_words_lit : @ui.TextStyle = combo_words.then(@ui.text_style(color=Fg))

///|
/// The run picker's columns side by side (the models a third wider than the rest, on the card's ground), 10 in, 8
/// apart; each filling the panel's height, scrolled in it.
// kept across runs: a value (no field of it changes)
let run_columns : @ui.Style = @ui.style(row=true, w=Full, h=@sf.grow, px=S2_5, gap=S2)

///|
// kept across runs: a value (no field of it changes)
let run_models : @ui.Style = @ui.style(w=@sf.run_models_grow, h=Full, clip=true)

///|
// kept across runs: a value (no field of it changes)
let run_side : @ui.Style = @ui.style(w=@sf.grow, h=Full, p=S1, radius=Xl, bg=Card, clip=true)

///|
/// A column's name (CascadeLabel: 12, muted, 10 in, 10 over, 2 under).
// kept across runs: a value (no field of it changes)
let run_label_box : @ui.Style = @ui.css("pl=S2_5 pt=S2_5 pb=S0_5")

///|
// kept across runs: a value (no field of it changes)
let run_label_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L4, color=Muted, wrap=false)

///|
/// A choice (CascadeOption): 10 in, 10 between, 10 round; the chosen on the accent's pale ground.
// kept across runs: a value (no field of it changes)
let run_option_box : @ui.Style = @ui.css("row w=Full p=S2_5 gap=S2_5 radius=Lg align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let run_option_on : @ui.Style = run_option_box.then(@ui.css("bg=AccentBg"))

///|
// kept across runs: a value (no field of it changes)
let run_option_words : @ui.Style = @ui.style(w=@sf.grow, clip=true)

///|
// kept across runs: a value (no field of it changes)
let run_words : @ui.TextStyle = @ui.text_style(size=Base, leading=L6, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let run_picked : @ui.TextStyle = run_words.then(@ui.text_style(weight=Semibold, color=AccentText))

///|
// kept across runs: a value (no field of it changes)
let run_faint : @ui.TextStyle = run_words.then(@ui.text_style(color=Muted))

///|
// kept across runs: a value (no field of it changes)
let run_note : @ui.TextStyle = @ui.text_style(size=Xs, leading=L4, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let run_amber : @ui.TextStyle = run_note.then(@ui.text_style(color=Warn))

///|
/// What borrowing the model would do, over the foot (20 in, 8 over it).
// kept across runs: a value (no field of it changes)
let run_borrow_box : @ui.Style = @ui.css("w=Full px=S5 pt=S2")

///|
/// The foot: who runs it, then 确定, 8 apart, at its foot (where it stands the presenter's: 确定 in its corner, however
/// tall who runs it is).
// kept across runs: a value (no field of it changes)
let run_foot : @ui.Style = @ui.css("row w=Full gap=S2 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let run_who : @ui.Style = @ui.style(row=true, w=@sf.grow, p=S2_5, gap=S1, radius=Xl, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let run_who_lead : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let run_who_name : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let run_who_amber : @ui.TextStyle = run_who_name.then(@ui.text_style(color=Warn))

///|
/// Who runs it in the picker's place: its head (back, 账号), its list, what was let go of over it.
// kept across runs: a value (no field of it changes)
let run_accounts_head : @ui.Style = @ui.css("row w=Full pl=S2 pr=S4_5 pt=S1 pb=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let run_back : @ui.Style = @ui.css("w=S9 h=S9 radius=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let run_accounts_title : @ui.TextStyle = @ui.text_style(size=Lg, weight=Bold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let run_accounts_list : @ui.Style = @ui.style(w=Full, h=@sf.grow, px=S3, clip=true)

///|
// kept across runs: a value (no field of it changes)
let run_dropped_box : @ui.Style = @ui.css("px=S3 py=S1")

///|
// kept across runs: a value (no field of it changes)
let run_dropped : @ui.TextStyle = @ui.text_style(size=Xs, leading=L4, color=Warn)
