// A new chat (still.fail web/src/NewChat.tsx and NewChat.css.ts, web/src/mobile/NewChat.tsx and NewChat.css.ts;
// apps/android NewChat.kt; its frequent combinations in the model's panel, model_triple.mbt): say what to do, having
// picked where it runs (the station) and on what (the model, its runtime, how hard it thinks, who runs it), as the
// core keeps them (the `newChat` topic; `newChat.pick`, `pick.set`, `pick.save`). One page in every frame, laid out by
// its own width as the web lays out its two:
// - narrow (under @sf.page_narrow_most), as the web's mobile page: the scene (the picture, what to do and where, what
//   keeps it from starting, the machine's own sessions) over all that is left, scrolled when it does not fit; at its
//   foot what is wrong for now, the choices in glass capsules (the station, the model: each through the presenters),
//   the composer where a chat has it;
// - wide, as the web's desktop page: a column 720 wide at most, the scene and the composer in the middle of the pane,
//   the composer roomy with the choices in the row under its words (the station's chooser, the model control:
//   model_triple.mbt), what differs by the station and its picks under it, moving nothing over it.
// The composer is the pages' (composer.mbt), its draft the workspace's new chat's (`new:<workspace>`), whichever
// station it is to run on: its files wait, and go up to that one as the first message is taken to go
// (`composer.take {station}`), the message waiting for them. The first message
// makes the chat (`newChat.create`, made once a page, anew when the picks changed: useEnsureChat) and goes to it
// (`chat.send` by its key); the page becomes the chat in place, its first words carried where they were typed till
// their row is in the chat's list (flight.mbt), what is written meanwhile going on into the chat's draft
// (`composer.carry`); over the chat its scene and what is under it fade where they are
// . The frame says what is over it and under it, and what it does as the page
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
  bar : (@ui.Ctx) -> Unit
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
/// Workspace `ws`'s new chat as the core is asked it (`newChat`: where it starts, what it runs on, the stations it
/// can): one ask wherever it is read.
pub fn new_chat_asked(ws : String) -> Map[String, Json] {
  { "scope": Json::string(ws) }
}

///|
/// What workspace `ws`'s new chat opens on, asked of `ask` (sfbase's opens_answered): its view, or why it has none.
/// While it is not, the page shows its stations as read (in their bones).
pub fn new_chat_opens(ws : String, ask : (String, Map[String, Json]) -> @sfbase.TopicState) -> Bool {
  @sfbase.opens_answered(ask("newChat", new_chat_asked(ws)))
}

///|
/// A new chat in workspace `w` (NewChat, NewChatScreen): while its stations are read, the page as it will be on the
/// station it last started on, its composer taking words but sending nothing; with none at all, the first to add;
/// with none up, said so; nothing to run a chat with yet, its first step; else the page on the station it starts on.
pub fn new_chat_page(c : @ui.Ctx, src : Source, w : Workspace, frame : NewChatFrame) -> Unit {
  let topic = src.topic("newChat", new_chat_asked(w.id)).get().snapshot()
  let v = topic.value
  c.box(style=new_ground, fn() {
    c.box(style=new_bar_room, fn() { (frame.bar)(c) }) |> ignore
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
/// The new chat of view `v` as it is left (data-made-leave): as it was but for its composer
/// (the chat's now, its place kept), its scene `up` of the way faded where it is, what is under the composer `fade` of
/// the way faded where it is, each read as it is drawn. The frame draws it over the chat it became (its scene leaving: 140 ms from its first
/// words sent, what is under the composer 80 ms: @sfbase.new_chat_leaving_of), or over the chat it was left for, in a
/// layer drawn only.
pub fn new_chat_left(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  frame : NewChatFrame,
  v : Json?,
  up : @motion.Anim,
  fade : @motion.Anim,
) -> Unit {
  c.box(style=new_frame_box, fn() {
    // its bar gone at once (the chat has its own), its room kept
    let bar = c.box(style=new_bar_room, fn() { (frame.bar)(c) })
    c.look(bar, @ui.look(alpha=0.0))
    c.box(style=new_room, fn() { new_on(c, src, w, frame, v, field(v, "station"), Going(up, fade)) }) |> ignore
    list_space(c, frame.foot)
  })
  |> ignore
}

///|
/// What the page on a station is: here (`Here`); its stations not read yet (`Held`: why they could not be, "" while
/// they are read), the station it last started on in its place; become its chat (`Going`: how far its scene and what is
/// under its composer have faded, 0 … 1 each, read as it is drawn).
priv enum NewState {
  Here
  Held(String)
  Going(@motion.Anim, @motion.Anim)
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
  if c.width < @sf.page_narrow_most || c.ime_inset() > 0.0 {
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
  let going = state is Going(_, _)
  // the page the new chat again after its first words were sent (the chat not made): its scene and choices coming back
  let (sending_up, sending_fade) = if going { (0.0, 0.0) } else { @sfbase.new_sending(c) }
  // the scene in all the page, its end clear of the foot over it (mNewBody's --m-new-foot: as tall as the foot was
  // last laid out)
  let clear = @motion.measured(c, "new/foot").unwrap_or(0.0)
  c.box(style=new_scene_room, fn() {
    c.list("new/scene", 1, new_scene_guess, fn(_) {
      c.box(style=new_scene_column, fn() {
        let scene = c.box(style=new_scene_narrow, fn() { new_scene_narrow_body(c, src, frame, v, station, state) })
        // fading where it is (as it is drawn); back, the chat not made
        match state {
          Going(up, _) => c.look_by(scene, fn() { @ui.look(alpha=1.0 - up.get(c)) })
          _ => if sending_up > 0.0 { c.look(scene, @ui.look(alpha=1.0 - sending_up)) }
        }
        list_space(c, clear)
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  // gone to the chat: the scene seen only where it was seen, over the foot; what the band frosted and the composer
  // covered stays hidden as they leave (the choices and the band fade sooner than the scene, the composer is the
  // chat's, under it)
  if going {
    list_space(c, @sfbase.fresh.foot.get())
  }
  let width = composer_width(c.width)
  // (as far from the page's foot as a chat's composer: composer_foot_in)
  let under : @ui.Space = @sf.room_of(composer_foot_in(c, c.width))
  c.layer(fn() {
    c.spacer()
    let foot = c.box(style=new_foot, fn() {
      // a band of glass from over the choices to the page's foot (mNewFoot, glassFoot), the composer on it: what the
      // scene has under it frosted all over, not seen between the choices, nor pressed through it; what is on it as far
      // under its top as the composer is from the page's foot and sides; as the page becomes the chat, over the choices
      // alone (the composer there is the chat's, under it, not to be frosted)
      let band = c.id("new/band")
      let band_room = @ui.style(pt=under, pb=if going { S0 } else { under })
      let mut over = -1
      let (ground, shaped) = composer_shaped(fn() {
        c.box(style=new_band.then(band_room), glass=@sf.glass_foot(), id=band, fn() {
          over = c.box(style=new_over, fn() {
            if !going {
              new_notices(c, v, station, width)
            }
            c.box(style=@ui.style(w=Fixed(width)), fn() { new_choosers(c, src, w, v, station, state) }) |> ignore
          })
          if !going {
            c.box(style=@ui.style(w=Fixed(width)), fn() {
              new_composer_place(c, src, w, frame, v, address, station, state, width)
            })
            |> ignore
          }
        })
      })
      // as the composer changes shape (a line more or less, opened or let go), what is over it and the band's top go
      // with its ground, on its curve, not to where they are laid out at once
      with_composer(c, over, "new/over", shaped)
      if sending_fade > 0.0 {
        c.look(over, @ui.look(alpha=1.0 - sending_fade))
      }
      match shaped {
        Some((by, spec)) => @motion.reshape(c, ground, "new/band", by~, spec~)
        None => ()
      }
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
    match state {
      Going(_, fade) => c.look_by(foot, fn() { @ui.look(alpha=1.0 - fade.get(c)) })
      _ => ()
    }
  })
  |> ignore
}

///|
/// The scene narrow (mNewBody): the picture, what to do, where (while its stations are read, its two lines breathing,
/// still once what they wait on failed), what keeps it from starting (or why its stations could not be
/// read), the machine's own sessions to go on with.
fn new_scene_narrow_body(
  c : @ui.Ctx,
  src : Source,
  frame : NewChatFrame,
  v : Json?,
  station : Json?,
  state : NewState,
) -> Unit {
  new_head(c, station, state, new_scene_narrow_w, fn(_) {  })
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
  new_offer(c, src, frame, station, state, new_offer_box) |> ignore
}

///|
/// The choices over the composer (mChoosers): where it runs, what it runs on, each a glass capsule opening its pick
/// through the presenters; while its stations are read, both breathing in their places, as high as they will be (still
/// once what they wait on failed); its profiles still read (the core's `waiting`), what it runs on breathing.
fn new_choosers(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  v : Json?,
  station : Json?,
  state : NewState,
) -> Unit {
  let going = state is Going(_, _)
  match state {
    // (while its stations are read: a made-up station's and model's, in their bones)
    Held(error) =>
      @sf.bones(c, still=error != "", fn() {
        c.box(style=new_choosers_row, fn() {
          new_controls(c, @sfbase.sample_source, w, Some(new_sample_view()), Some(new_sample_station()), true, false)
        })
        |> ignore
      })
    _ => c.box(style=new_choosers_row, fn() { new_controls(c, src, w, v, station, true, going) }) |> ignore
  }
}

///|
/// Where a new chat starts and what it runs on, made up, for what shows while they are read (in their bones).
fn new_sample_station() -> Json {
  { "station": "sample", "name": Json::string(@sf.sample_words(4)) }
}

///|
fn new_sample_view() -> Json {
  {
    "runtime": "claude",
    "model": "sample",
    "pick": {
      "value": { "runtime": "claude", "model": "sample" },
      "valueOption": { "name": Json::string(@sf.sample_words(6)) },
      "efforts": ["low"],
    },
  }
}

///|
/// Where it runs and what it runs on: the station's control (its mark, its name; pressed, the stations through the
/// presenters) and the model's (model_triple.mbt, drawn of the face the page has of it, its panel through them too, asked
/// as it opens); with nothing to run it with, the way to
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
  // (what it is for first, then where it runs and on what; short of room, each gives up its words, not its place)
  new_preset_control(c, src, w, v, station, floating, going)
  if text(station, "name") != "" {
    new_station_control(c, src, w, v, station, floating, going)
  }
  let p = field(v, "pick")
  if flag(v, "waiting") {
    // (its profiles read: a made-up model's, in its bones)
    @sf.bones(c, fn() {
      model_triple(c, @sfbase.sample_source, "sample", "new", face=field(Some(new_sample_view()), "pick"), small=true, floating~)
    })
  } else if p is None || text(v, "runtime") == "" || field(v, "model") is None {
    // nothing to run it with: the way to where models are enabled
    new_capsule(c, "new/models", @sf.t("web-main.newChat.noModels"), floating, fn() {
      c.text(@sf.t("web-main.newChat.noModels"), style=new_capsule_words) |> ignore
    }, on_press=fn() {
      if !going {
        open_page(Place("profiles"))
      }
    })
  } else {
    // (asked from elsewhere, opened here: not by what is drawn in a page's bones)
    if !c.in_bones() && take_asked("model") {
      open_triple(address, "new")
    }
    // (its face, as the page has it: its panel asked as the hand comes to it, opened whole once answered)
    // (a preset that names its model: shown as the preset's, not opened; changed by editing the preset or picking none)
    model_triple(c, src, address, "new", face=p, small=true, floating~, bound=flag(v, "presetModel"), on_bound=fn(from) {
      if !going {
        preset_fixed_menu(src, w, address, v, @sf.t("web-main.preset.fixedModel", args=[("name", @sf.title_accented(text(v, "presetName")))]), from)
      }
    })
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
  let from = c.id("new/station")
  // (a preset that names the stations: only those offered, none to pick where it names the one it is on)
  let fixed = flag(v, "presetStations") && items(v, "stations").length() <= 1
  let open = fn() {
    @sf.panel_nodes(@sf.t("android-chat.new.station.pick"), fn(n, close) { station_rows_node(n, src, w, v, close) }, from=Of(from))
  }
  new_capsule(
    c,
    "new/station",
    text(station, "name"),
    floating,
    fn() {
      // (a station of no mark of its own the server's, as in its pick: with its name left out, the control never a bare
      // chevron, the user, 2026-11-13: 「怎么 station 还会直接挤消失」)
      @sf.station_mark(c, text(station, "emoji"), text(station, "icon"), new_mark, t.p.text, none="server")
      // (its name left out after what the model's control leaves out, its mark kept: the page says where it starts)
      c.box(style=new_station_name, drop=new_drop_station_name, fn() {
        c.text(text(station, "name"), style=new_capsule_words) |> ignore
      })
      |> ignore
      if !fixed {
        @sf.icon(c, "chevron-down", size=new_chevron, color=t.p.muted) |> ignore
      }
    },
    on_press=fn() {
      if going {
        ()
      } else if fixed {
        // (held by the preset: said so, with the ways to change it)
        preset_fixed_menu(src, w, text(station, "station"), v, @sf.t("web-main.preset.fixedStation", args=[("name", @sf.title_accented(text(v, "presetName")))]), Of(from))
      } else {
        open()
      }
    },
  )
  // (asked from elsewhere: opened as it is seen)
  if !c.in_bones() && !fixed && take_asked("station") {
    open()
  }
}

///|
/// A control of the page's (where it runs, the way to models): over the composer a capsule of its glass (mChooser,
/// NewChat.kt Chooser), in its row as the composer's other controls; what it holds
/// `body`. True on the frame after it was pressed. `marked`: it starts with a mark of a corner of its own (a folder's
/// tile), stood as far in from the glass's start as from its top and foot, so the two are concentric.
fn new_capsule(
  c : @ui.Ctx,
  key : String,
  label : String,
  floating : Bool,
  body : () -> Unit,
  on_press? : () -> Unit,
  marked? : Bool = false,
) -> Unit {
  let id = c.id(key)
  let b = if floating {
    c.box(style=if marked { glass_chooser_marked_box } else { glass_chooser_box }, glass=@sf.glass_floating(), id~, fn() {
      body()
      @sf.press_ripple(c, id, glass_chooser_corner)
    })
  } else {
    c.box(style=new_capsule_in_row, id~, body)
  }
  c.semantics(b, Button, id~, label~)
  match on_press {
    Some(f) => c.on_press(id, f)
    None => ()
  }
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
/// Where a new chat runs (the mobile pickStation), in node `n` (its panel's body): the workspace's stations as `v` said
/// them as it opened, each its mark beside its name, the one it starts on checked, and what the stations' list says of
/// it (station_facts.mbt: its agents at work, what is left of its machine, how this device reaches it, followed as it
/// changes); picked, the core has it (`newChat.pick`) and the panel closes, showing what it showed till it is gone.
fn station_rows_node(n : @view.View, src : Source, w : Workspace, v : Json?, close : () -> Unit) -> Unit {
  let current = text(field(v, "station"), "station")
  for s in items(v, "stations") {
    let st = Some(s)
    let here = text(st, "station") == current
    n.box(fn(row) {
      // (its words on the panel's words' line wherever it is drawn: @sf.panel_row_in_node; its ground under a mouse, as
      // panel_row_in's `hovered`)
      @sf.style_node(row, fn() { station_row.then(@sf.panel_row_in_node(row)) })
      row.ground(By(fn() { if @sf.hovered_in_node(row) || row.focus_shown() { @sf.theme().p.hover } else { 0L } })) |> ignore
      @sf.rippled_node(row, fn() {
        @sfbase.pick_new(src, w.id, { "station": Json::string(text(st, "id")) })
        close()
      }, @sf.row_corner, fn() { text(st, "name") })
      // (read out checked or not: the one it starts on)
      row.says(Is(Some(@view.said(Button, label=text(st, "name"), check=if here { On } else { Off })))) |> ignore
      row.box(fn(m) {
        @sf.style_node(m, fn() { station_row_mark_box }, in_row=true)
        if @sf.has_station_mark(text(st, "emoji"), text(st, "icon")) {
          @sf.station_mark_node(m, fn() { text(st, "emoji") }, fn() { text(st, "icon") }, station_row_mark, fn() {
            @sf.theme().p.text
          }, fn() { 0 })
        } else {
          @sf.icon_node(m, "server", station_row_mark, By(fn() { @sf.theme().p.text })) |> ignore
        }
      })
      |> ignore
      row.box(fn(col) {
        @sf.style_node(col, fn() { station_row_words }, in_row=true)
        // (giving way to its mark beside it where its name is long, as the old one's grow did: its name cut short)
        col.min_width(Is(Some(0.0))) |> ignore
        col.box(fn(head) {
          @sf.style_node(head, fn() { station_row_head })
          // (as long as there is room, what follows it at the line's end: station_row_name's w=grow, a node's own)
          @sf.words_node(head, fn() { text(st, "name") }, fn() { station_row_name })
          .grow(Is(1.0))
          .shrink(Is(1.0))
          .min_width(Is(Some(0.0)))
          |> ignore
          station_state_node(head, fn() { st })
          if here {
            @sf.icon_node(head, "check", new_mark, By(fn() { @sf.theme().p.accent })) |> ignore
          }
        })
        |> ignore
        station_figures_node(col, src, fn() { st })
      })
      |> ignore
    })
    |> ignore
  }
}

// ── wide: the web's desktop page ──────────────────────────────────────────

///|
/// The page wide (NewChatOn, newChat, newChatInner): the scene, 新对话, what it does and where (while its stations are
/// read, that it starts on the station chosen), the composer, roomy, its choices in its row, the two in the middle of
/// the pane; under the composer what differs by the station and what is picked on it: what is wrong for now, what
/// it waits for (or why its stations could not be read), the machine's own sessions to go
/// on with.
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
  new_column(
    c,
    fn(col) {
      // (data-made-leave="up": the scene, fading where it is)
      let head : Array[Int] = []
      new_head(c, station, state, new_scene_w, fn(i) {
        new_part(c, i, state, true)
        head.push(i)
      })
      let (_, shaped) = composer_shaped(fn() {
        new_composer_place(c, src, w, frame, v, address, station, state, col)
      })
      // the composer changing shape in the middle of the column, what is over it goes with its ground (as what is
      // under it does: new_column)
      head.eachi(fn(k, i) { with_composer(c, i, "new/head/\{k}", shaped) })
    },
    under=fn(col) {
      // (data-made-leave="fade": fading where it is)
      if !(state is Held(_)) {
        // what is sent waits for its quota, or its station went as it was written in (the page stays, said so)
        new_notices(c, v, station, col, part=fn(i) { new_part(c, i, state, false) })
      }
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
          new_part(c, new_offer(c, src, frame, station, state, new_offer_under), state, false)
        }
      }
    },
  )
}

///|
/// Its column (newChat: in the middle of the pane, 32 in; newChatInner: 720 at most, its parts 10 apart and centred),
/// `body` given its width. With `under`: as tall as the pane, `body` in its middle and `under` from its foot down, as
/// much room under it as over it (more where what is under needs it, as it was last laid out): what is under comes,
/// goes and changes with the station and what is picked on it, and moves nothing in the middle with it, the composer
/// staying where it is as another station is picked.
fn new_column(c : @ui.Ctx, body : (Double) -> Unit, under? : (Double) -> Unit) -> Unit {
  let col = dmin(new_column_w, c.width - 2.0 * new_column_in)
  c.box(style=new_page_box, fn() {
    match under {
      None => c.box(style=new_inner.then(@ui.style(w=Fixed(col))), fn() { body(col) }) |> ignore
      Some(under) =>
        c.box(style=new_inner_tall.then(@ui.style(w=Fixed(col))), fn() {
          c.spacer()
          // (the composer in it: what is under it moves with its box)
          let (_, shaped) = composer_shaped(fn() { body(col) })
          let least = @motion.measured(c, "new/under").unwrap_or(0.0)
          c.box(style=new_under_room.then(@ui.style(min_h=Fixed(least))), fn() {
            let held = c.box(style=new_under, fn() { under(col) })
            @motion.measure(c, held, "new/under")
            // (the composer over it changing shape: with its ground)
            with_composer(c, held, "new/under/moves", shaped)
          })
          |> ignore
        })
        |> ignore
    }
  })
  |> ignore
}

///|
/// Part `i` of the page wide as it leaves, fading where it is: `up` (the scene) as its scene does, else as what is under
/// the composer does. While it stays, as it is.
fn new_part(c : @ui.Ctx, i : Int, state : NewState, up : Bool) -> Unit {
  match state {
    Going(u, _) if up => c.look_by(i, fn() { @ui.look(alpha=1.0 - u.get(c)) })
    Going(_, f) => c.look_by(i, fn() { @ui.look(alpha=1.0 - f.get(c)) })
    Here => {
      // the page the new chat again after its first words were sent (the chat not made): coming back
      let (u, f) = @sfbase.new_sending(c)
      let gone = if up { u } else { f }
      if gone > 0.0 {
        c.look(i, @ui.look(alpha=1.0 - gone))
      }
    }
    Held(_) => ()
  }
}

///|
/// The composer's choices wide, in its row: the page's controls (new_controls).
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
  let wide = c.width >= @sf.page_narrow_most && c.ime_inset() == 0.0
  match state {
    Going(_, _) => list_space(c, @sfbase.fresh.room.get())
    Held(_) if address == "" => list_space(c, @motion.measured(c, "new/composer").unwrap_or(0.0))
    _ => {
      let held = state is Held(_)
      let spec : ComposerSpec = {
        station: address,
        draft: "new:" + w.id,
        session: "",
        placeholder: @sf.t("web-main.newChat.placeholder"),
        toolbar: if wide && !held { Some(fn() { new_tools(c, src, w, v, station) }) } else { None },
        note: [],
        tail: None,
        roomy: wide,
        locked: held || (!flag(v, "waiting") && (text(v, "runtime") == "" || field(v, "model") is None)),
        offline: false,
        warm_agent: false,
      }
      let name = text(station, "name")
      // (at the page's foot, laid out narrow: in a panel's foot corners as a chat's is; roomy, in the page's middle)
      let at = if wide { composer_alone } else { composer_place(c, c.width) }
      let place = c.box(style=new_composer_box, fn() {
        c.sized(width, c.height, fn() {
          composer(c, src, w, spec, fn(d) { new_send(c, src, frame, v, address, name, d) }, place=at)
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
/// The machine's own sessions to go on with, where it kept any (MachineSessions), in a box of `style`; nothing while its
/// stations are read, nor read only.
fn new_offer(c : @ui.Ctx, src : Source, frame : NewChatFrame, station : Json?, state : NewState, style : @ui.Style) -> Int {
  if state is Held(_) || !(field(station, "overview") is Some(Object(_))) || src.read_only {
    return c.box(fn() {  })
  }
  c.box(style~, fn() { @settings.machine_sessions_offer(c, frame.core, text(station, "station"), text(station, "name")) })
}

///|
/// The page's head, the same at every width: the picture
/// (Illustration "new-chat") `art_w` wide, what to do, where it starts (while its stations are read, two lines
/// breathing in its place, still once what they wait on failed); each part given to `part` (how it leaves).
fn new_head(c : @ui.Ctx, station : Json?, state : NewState, art_w : Double, part : (Int) -> Unit) -> Unit {
  part(@sf.drawable(c, new_scene_art(), art_w))
  part(c.box(style=new_heading_box, fn() { c.text(@sf.t("android-chat.new.heading"), style=new_title) |> ignore }))
  part(
    match state {
      // (while its stations are read: where it starts said of a made-up one, in its bones)
      Held(error) =>
        c.box(style=new_sub_box, fn() {
          @sf.bones(c, still=error != "", fn() {
            c.text(@sf.t("android-chat.new.sub", args=[("station", @sf.sample_words(4))]), style=new_sub) |> ignore
          })
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
    "disabled" => @sf.t("web-main.newChat.profilesDisabled")
    "shared" => @sf.t("web-main.newChat.notShared", args=[("name", name)])
    _ => @sf.t("web-main.newChat.pickModels")
  }
  let lead = match blocked {
    "profile" =>
      @sf.t("web-pages.profiles.lead", args=[("subscription", @sf.t("web-pages.profiles.leadSubscription"))])
    "shared" | "disabled" => text(v, "problem")
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
            @sf.button(c, @sf.t("web-main.newChat.addProfile"), key="new/add-profile", tone=Primary, icon="plus", on_press=fn() {
              open_page(Setting(@settings.Route::NewProfile(address)))
            }) |> ignore
          "shared" => ()
          _ =>
            @sf.button(c, @sf.t("web-main.newChat.goPickModels"), key="new/pick-models", tone=Primary, on_press=fn() {
              open_page(Setting(@settings.Route::Profiles(address)))
            }) |> ignore
        }
        if items(v, "stations").length() > 1 {
          new_station_control(c, src, w, v, station, false, false)
        }
      },
    )
  })
}

///|
/// The new chat's first message (onSending, onSent): the page
/// becomes the chat the frame it is sent, by the key the core keeps for the next one made (the `newChat` topic's
/// `next`; the one made for it already while the picks are the same), its first words in its list from then and
/// flying there as any chat's do, its scene leaving at the same moment: what the core does then (its words taken off
/// the composer, `composer.take`; the chat made under that key, `newChat.create`; the message sent into it,
/// `chat.send`) goes on behind it in that order, nothing on screen waiting for any of it. What is written meanwhile
/// goes on into the chat's draft (`composer.carry`). The chat not made: the page the new chat again, what was taken
/// back in its composer, saying why; the message not taken in: back in the chat's composer.
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
  if fresh.starting.get() {
    return
  }
  // the chat it becomes: the one made for it already (its picks the same), else the next the core keeps for it
  let make = fresh.made.get() == ""
  let key = if make { text(v, "next") } else { fresh.made.get() }
  if key == "" {
    return
  }
  // sent, felt as a key's light tap (a no as something refused)
  @ui.haptic(KeyboardTap)
  let words = d.text.get().trim(chars=" \n\t").to_owned()
  remember_sent_pictures(src, d, station)
  // (as its message will have them: taken out of the draft as it is sent)
  let up = up_files(d)
  let going = going_files(d)
  let quotes = sent_quotes(d)
  // (its references as the field's marks, which its flight takes off as; its row's runs as the core read its words)
  let marks = @sfbase.refs_sent_marks(d.key, words)
  let runs = @sfbase.refs_sent_runs(d.key, words)
  let draft = station + ":" + key
  let rk = station + "\u{1}" + key
  // called what the page was (新对话) until someone names it, as the core calls it
  let r : ChatRef = { station, session: key, title: @sf.t("web-main.newChat.title"), station_name: name }
  // its words, its quotes and its files from where they were typed, their cards and their tiles, into their row in
  // the chat's list, in it from now (sent_local), the list coming up with them, the composer held as tall as it is
  // till they set out.
  // Where the chat it becomes is a page made as nodes, none is carried, till the flights' step: the page becomes it in
  // this change, nothing there lets a flight go (flight_placed, flight_frame), and the chat's composer was held as tall
  // as they took in it for good; with none, its composer is at its one line from this change, in which its list takes
  // their row. The flights' step carries them on nodes again, and must then either let go in the sent key's change or
  // have the list keep the room till it lets go.
  let carried = !@signals.untracked(fn() { @sfbase.chat_page_nodes.get() })
  if carried {
    @sfbase.flight_carry_start(
      c,
      d.key,
      words,
      flying_quotes(c, src, d, station) + flying_files(c, src, d),
      field=d.field,
      shaped=composer_shapes_sent(c, src, d, station),
      // (the flight where the chat opens has: in this page's place, Android's; beside it, the web's)
      desk=!frame.in_place,
      marks~,
      runs~,
    )
  }
  let row = sent_local(rk, None, words, up, going~, quotes~, runs~, now=(src.now)())
  if carried {
    @sfbase.flight_carry_into(c, d.key, draft, rk, row)
  }
  let sig = @sfbase.picked_sig(v)
  fresh.starting.set(true)
  fresh.sending.set(true)
  fresh.sent.set(true)
  fresh.made.set(key)
  fresh.made_sig.set(sig)
  // the page becomes the chat, in place, now: the scene leaving over it from here (new_chat_left), with the words
  fresh.scene.set(v)
  fresh.became.set(Some(r))
  fresh.room.set(@motion.measured(c, "new/composer").unwrap_or(0.0))
  fresh.foot.set(@motion.measured(c, "new/foot").unwrap_or(0.0))
  @sfbase.became_starts(c, wide=!frame.in_place)
  @sfbase.writing_starting(src, d, true)
  // what the core does, in order: the words taken, the chat made, what is written meanwhile on into its draft; then
  // the message sent into it, once both are
  let taken : Ref[Json?] = Ref(None)
  let made = Ref(!make)
  let sending = Ref(true)
  // (not sent after all: its row gone from the list, its words back in the chat's composer, saying why)
  let not_sent = fn(why : String) {
    @ui.haptic(Reject)
    sending.val = false
    fresh.starting.set(false)
    @sfbase.sent_local_gone(rk, row)
    @sfbase.flight_carry_gone(draft)
    @sfbase.writing_starting(src, d, false)
    let into = @sfbase.writing(src, draft)
    into.taken = d.taken
    d.taken = None
    writing_restore(src, into, why)
  }
  let send = fn() {
    match taken.val {
      Some(t) if made.val && sending.val => {
        sending.val = false
        let params : Map[String, Json] = {
          "station": Json::string(station),
          "session": Json::string(key),
          "text": Json::string(text(Some(t), "text")),
          "attachments": Json::array(items(Some(t), "attachments")),
          "quotes": Json::array(items(Some(t), "quotes")),
        }
        let going = items(Some(t), "uploads")
        if going.length() > 0 {
          params["uploads"] = Json::array(going)
        }
        (src.call)("chat.send", Json::object(params), fn(res) {
          match res {
            Err(e) => {
              sending.val = true
              not_sent(text(Some(e), "message"))
            }
            Ok(_) => {
              fresh.starting.set(false)
              @sfbase.writing_starting(src, d, false)
            }
          }
        })
      }
      _ => ()
    }
  }
  writing_take(src, d, station~, fn(t) {
    match t {
      Some(_) => {
        taken.val = t
        send()
      }
      // (nothing taken: nothing to put back but what it held)
      None => if sending.val { not_sent("") }
    }
  })
  if make {
    (src.call)("newChat.create", { "station": Json::string(station), "key": Json::string(key) }, fn(res) {
      match res {
        Ok(_) => {
          made.val = true
          send()
        }
        Err(e) => {
          // not made: the page the new chat again, its scene back, what was taken back in its composer
          sending.val = false
          fresh.made.set("")
          fresh.starting.set(false)
          fresh.became.set(None)
          @sfbase.leaving_back()
          @sfbase.sent_local_gone(rk, row)
          @sfbase.flight_carry_gone(draft)
          @sfbase.writing_carry(src, draft, d.key)
          @sfbase.writing_starting(src, d, false)
          writing_restore(src, d, text(Some(e), "message"))
          app.nav.become(NewChat)
        }
      }
    })
  }
  // what is written meanwhile goes on in the chat's draft
  @sfbase.writing_carry(src, d.key, draft)
  new_chat_reset()
  (frame.sent)(r)
  app.nav.become(Chat(r))
}

// ── the run picker ────────────────────────────────────────────────────────

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
/// What keeps it from starting narrow (mNewProblem: 6 over it).
// kept across runs: a value (no field of it changes)
let new_problem_box : @ui.Style = @ui.css("w=Full pt=S1_5")

///|
/// The foot narrow, over the scene's end: the band, and as the page becomes the chat the composer's place under it.
// kept across runs: a value (no field of it changes)
let new_foot : @ui.Style = @ui.css("w=Full align=ACenter")

///|
/// What is on the band over the composer: what is wrong for now, the choices.
// kept across runs: a value (no field of it changes)
let new_over : @ui.Style = @ui.css("w=Full align=ACenter")

///|
/// The band (mNewFoot, mNewBottom): its corners square but where it lies in a panel's.
// kept across runs: a value (no field of it changes)
let new_band : @ui.Style = @ui.css("w=Full align=ACenter radius=InnerOr(Sharp)")

///|
/// The choices narrow (mChoosers: 6 apart, 6 over the composer, 2 in).
// kept across runs: a value (no field of it changes)
let new_choosers_row : @ui.Style = @ui.css("row w=Full px=S0_5 pb=S1_5 gap=S1_5 align=ACenter")

///|
/// A glass choice (mChooser): 30 high, 12 in, 6 between its parts, a capsule; as wide as what it holds needs, never cut
/// by its row (what is beside it gives way, or what of it may leave leaves: its press's ripple keeps to its shape
/// itself).
// kept across runs: a value (no field of it changes)
let glass_chooser_box : @ui.Style = @ui.style(row=true, h=@sf.glass_chooser_h, px=S3, gap=S1_5, align=ACenter, radius=Full)

///|
/// The glass capsule starting with a mark of a corner of its own (new_capsule's `marked`): in from its start by what
/// it is in from the top (the capsule's 15 less the mark's small corner, 7: 8), as the corner rule holds; 12 till
/// 2026-11-14, found on 中屏's Home after a workspace switch with a preset picked.
// kept across runs: a value (no field of it changes)
let glass_chooser_marked_box : @ui.Style = @ui.style(
  row=true,
  h=@sf.glass_chooser_h,
  pl=S2,
  pr=S3,
  gap=S1_5,
  align=ACenter,
  radius=Full,
)

///|
// kept across runs: a value (no field of it changes)
let new_capsule_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Fg, wrap=false, w=Cut)

///|
/// A station's name in its control: cut short past 128 (mChooser's max-width); where its row has not the room for it
/// and the model's control, left out whole, after all that control leaves out (its runtime, how hard it thinks).
// kept across runs: a value (no field of it changes)
let new_station_name : @ui.Style = @ui.style(max_w=@sf.glass_chooser_station_most)

///|
let new_drop_station_name : Int = triple_drop_effort + 1

///|
/// A control in the composer's row (Chooser: 28 high, 8 in, its parts 6 apart, the hover's ground).
// kept across runs: a value (no field of it changes)
let new_capsule_in_row : @ui.Style = @ui.css("row h=S7 px=S2 gap=S1_5 align=ACenter radius=Lg hovered{bg=Hover}")

///|
/// A station's row in its pick (PickRow): its mark, its name over what it is, a check; 12 by 8 in.
// kept across runs: a value (no field of it changes)
let station_row : @ui.Style = @ui.css("row w=Full px=S2 py=S3 gap=S3 align=AStart radius=Lg")

///|
/// Its mark beside its name's line (as high as it: L6), in its middle.
// kept across runs: a value (no field of it changes)
let station_row_mark_box : @ui.Style = @ui.css("h=S6 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let station_row_words : @ui.Style = @ui.style(w=@sf.grow)

///|
/// Its name's line: its name, as long as there is room, then how it is and its check.
// kept across runs: a value (no field of it changes)
let station_row_head : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let station_row_name : @ui.TextStyle = @ui.text_style(size=Body, leading=L6, color=Fg, wrap=false, w=@sf.grow)

///|
/// newChat: what it holds in the middle of the pane; newChatInner: its parts 10 apart, centred.
// kept across runs: a value (no field of it changes)
let new_page_box : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let new_inner : @ui.Style = @ui.css("gap=S2_5 align=ACenter")

///|
/// newChatInner as tall as the pane: room over what is in its middle, what is under it in the room left under that.
// kept across runs: a value (no field of it changes)
let new_inner_tall : @ui.Style = @ui.css("h=Full gap=S2_5 align=ACenter")

///|
/// The room under the composer: as much as over the scene.
// kept across runs: a value (no field of it changes)
let new_under_room : @ui.Style = @ui.style(w=Full, h=@sf.grow)

///|
/// What is in it, from its top: its parts 10 apart, centred.
// kept across runs: a value (no field of it changes)
let new_under : @ui.Style = @ui.css("w=Full gap=S2_5 align=ACenter")

///|
/// A page of a picture and a title alone (mNewNone): 30 in, 10 apart.
// kept across runs: a value (no field of it changes)
let new_alone_box : @ui.Style = @ui.css("w=Full px=S8 gap=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let new_alone_title : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Fg, center=true, w=Full)

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
/// The offer wide, the last of what is under the composer (newChatOffer: in the middle).
// kept across runs: a value (no field of it changes)
let new_offer_under : @ui.Style = @ui.css("w=Full align=ACenter")

///|
/// spentNotice: the amber's 12% under 13's words, 8 by 12 in, the 常用 chips' corner (Xl: the web's rField, 12), 8 under
/// it. Lg, 8, the scale's next step down, drew the bar tighter than the chips right under it.
// kept across runs: a value (no field of it changes)
let new_notice_box : @ui.Style = @ui.css("px=S3 py=S2 mb=S2 radius=Xl bg=A(Warn,O10)")

///|
// kept across runs: a value (no field of it changes)
let new_notice_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L5, color=Fg, w=Full)
