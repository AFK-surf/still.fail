// A new chat in the pane (ember web/src/NewChat.tsx, NewChat.css.ts, FrequentCombos.tsx and .css.ts): say what to do,
// having picked where it runs (the station) and on what (the model control: model_triple.mbt), as the core keeps them
// (the `newChat` topic, `newChat.pick`). All of it in a column 720 wide at most in the middle of the pane: the scene,
// 新对话, what it does and where; the composer, roomy, its choices in the row under the words; the frequent
// combinations under it, what it waits for, and the machine's own sessions to go on with. The composer is the
// desk's (composer.mbt), its draft the station's new chat's: the first message makes the chat (useEnsureChat, draft.ts
// send's first), and the page becomes it, its scene going up out of view as it fades and what is under the composer
// fading where it is (madeChat.ts), the composer going to the chat's foot by its own move (dock.tsx). The workspace's
// stations' files beside it, as beside a chat.

///|
/// What the page keeps of its own: its station chooser's menu open.
priv struct NewChatPage {
  mut station_menu : Bool
}

///|
let newchat : NewChatPage = { station_menu: false }

///|
fn newchat_reset() -> Unit {
  newchat.station_menu = false
}

///|
/// A new chat in the workspace (NewChat): while its stations are read, the page as it will be with the composer of the
/// station it last started on, locked; with none up, said so; else the page on the station it starts on.
pub fn new_chat_page(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let topic = (src.topic)("newChat", { "scope": Json::string(w.id) })
  let v = topic.value
  c.box(style=new_ground, fn() {
    match field(v, "stations") {
      Some(Array(_)) =>
        match field(v, "station") {
          Some(Object(_)) as station => new_chat_on(c, src, w, v, station)
          _ => new_offline(c)
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
        new_held(c, src, w, v, error)
      }
    }
  })
  |> ignore
}

///|
/// Its stations not read yet: laid out as the page will be (the composer's place held, the words under it), so nothing
/// moves when it comes; the composer the draft of the station it last started on (the core's `kept`), locked until
/// there is a station to write to; what is read, or why it could not be, under it.
fn new_held(c : @ui.Ctx, src : Source, w : Workspace, v : Json?, error : String) -> Unit {
  let address = match text(v, "kept") {
    "" => ""
    kept => w.id + "/" + kept
  }
  new_column(c, fn(col) {
    new_scene(c) |> ignore
    c.box(style=new_title_box, fn() { c.text(@sf.t("web-main.newChat.title"), style=new_title) |> ignore }) |> ignore
    c.box(style=new_sub_box, fn() { c.text(@sf.t("web-main.newChat.subChosen"), style=new_sub) |> ignore }) |> ignore
    // (none to hold it on, its first value not come yet: no draft asked for)
    if address != "" {
      c.box(style=new_composer_box, fn() {
        c.sized(col, c.height, fn() { new_composer(c, src, w, v, address, "", true, None) })
      })
      |> ignore
    }
    if error != "" {
      c.text(error, style=new_error) |> ignore
    } else {
      @sf.wait_line(c, @sf.t("common.readingStations"), key="new")
    }
  })
}

///|
/// No station up (NewChat's `!view`): the station offline, said so.
fn new_offline(c : @ui.Ctx) -> Unit {
  new_column(c, fn(_) {
    let t = @sf.theme()
    @sf.drawable(c, if t.dark { "illus_station_offline_dark" } else { "illus_station_offline" }, new_scene_w) |> ignore
    c.box(style=new_title_box, fn() { c.text(@sf.t("web-main.newChat.title"), style=new_title) |> ignore }) |> ignore
    c.text(@sf.t("web-main.newChat.noStation"), style=new_sub) |> ignore
  })
}

///|
/// The page on a station (NewChatOn): nothing to run a chat with yet, its first step (blocked); else the scene and the
/// composer, the 文件 tab beside them where the stations lend their files.
fn new_chat_on(c : @ui.Ctx, src : Source, w : Workspace, v : Json?, station : Json?) -> Unit {
  // (what is picked now: a chat made with other picks, nothing sent to it, let go)
  fresh_picked(v)
  // (what fades as it is left for a chat by the sidebar: switch.mbt)
  page_switch.new_view = v
  if text(v, "blocked") != "" {
    new_blocked(c, src, w, v, station)
    return
  }
  new_page(c, src, w, v, station, None)
}

///|
/// The page itself; `going`: it has become its chat, under it now (new_chat_after): how far its scene has gone up and
/// how far what is under the composer has faded (0 … 1 each), its composer's place kept empty.
fn new_page(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  v : Json?,
  station : Json?,
  going : (Double, Double)?,
) -> Unit {
  let address = text(station, "station")
  // the stations' files beside it, where they lend them (useStationDrive: as the view has its stations)
  let drive = address != "" &&
    items(v, "stations").iter().any(fn(s) { field(field(Some(s), "overview"), "drive") is Some(Object(_)) })
  let files = drive && new_files_open(src, w.id)
  let page = c.id("new/page")
  let scene = fn() {
    c.box(style=new_frame, id=page, fn() {
      new_body(c, src, w, v, station, going)
      // its bar (newChatBar): 文件 where a chat's bar has it, over the page, what is in its middle where it is
      if drive && going is None {
        c.layer(fn() {
          c.box(style=new_files_bar, fn() {
            if icon_button(c, "new/files", "folder", label=@sf.t("web-pages.chat.files")) {
              new_files_set(src, w.id, !files)
            }
            // (its end by the window's while the page is moved aside for the sidebar shown a while)
            page_bar_end(c)
          })
          |> ignore
        })
        |> ignore
      }
      // a row of the 文件 tab carried over it, let go there: into its message (DropHint, useChatDrop)
      if going is None && address != "" {
        drop_hint(c, page)
        chat_drop(c, src, address, "new:" + address, page)
      }
    })
    |> ignore
  }
  // its panel slides in and out as a chat's does (useSidePanel)
  side_beside(c, "new:" + w.id, files, side_width(c.width), scene, fn() {
    // (leaving: the chat it became has it now)
    if going is None {
      new_files_panel(c, src, w, address)
    }
  })
}

///|
/// The scene, the composer and what is under it (newChat, newChatInner).
fn new_body(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  v : Json?,
  station : Json?,
  going : (Double, Double)?,
) -> Unit {
  let address = text(station, "station")
  let name = text(station, "name")
  let here = if name == "" { @sf.t("web-main.newChat.thisMachine") } else { name }
  new_column(c, fn(col) {
    // (data-made-leave="up": out of view above as it fades)
    new_going(c, new_scene(c), going, true)
    new_going(
      c,
      c.box(style=new_title_box, fn() { c.text(@sf.t("web-main.newChat.title"), style=new_title) |> ignore }),
      going,
      true,
    )
    new_going(
      c,
      c.box(style=new_sub_box, fn() {
        c.text(@sf.t("web-main.newChat.sub", args=[("name", here)]), style=new_sub) |> ignore
      }),
      going,
      true,
    )
    // its station went as it was written in (the page stays, said so), or what is sent waits for its quota
    if flag(v, "down") {
      new_going(c, new_notice(c, @sf.t("web-main.newChat.down", args=[("name", here)])), going, true)
    }
    match text(v, "spent") {
      "" => ()
      spent => new_going(c, new_notice(c, spent), going, true)
    }
    match going {
      // gone to the chat's foot (switch.mbt): its place as it was
      Some(_) => c.box(style=new_composer_box.then(@ui.style(h=Fixed(fresh.room))), fn() {  }) |> ignore
      None => {
        let place = c.box(style=new_composer_box, fn() {
          c.sized(col, c.height, fn() {
            new_composer(c, src, w, v, address, name, false, Some(fn() { new_tools(c, src, w, v, station) }))
          })
        })
        // (how tall it is, kept clear as the page leaves: new_chat_after)
        @motion.measure(c, place, "new/composer")
      }
    }
    // (data-made-leave="fade": fading where it is)
    let combos = items(v, "frequent")
    if combos.length() > 0 {
      new_going(c, frequent_combos(c, src, w, combos, going is Some(_)), going, false)
    }
    // what it waits for, in a line of its own under the composer
    if flag(v, "waiting") || field(v, "model") is None {
      match text(v, "problem") {
        "" => ()
        p => new_going(c, c.text(p, style=new_status), going, false)
      }
    }
    // the machine's own sessions to go on with, where it kept any (MachineSessions)
    if field(station, "overview") is Some(Object(_)) && !src.read_only {
      let offer = c.box(style=new_offer, fn() {
        @settings.machine_sessions_offer(c, settings_core(src, w), address, name)
      })
      new_going(c, offer, going, false)
    }
  })
}

///|
/// The page as it becomes its chat (NewChat.tsx onSent): the composer going to the chat's foot from its place here,
/// the chat opening without its agent's history beside it, the files open beside the page open beside the chat.
fn new_sent(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef) -> Unit {
  fresh.room = @motion.measured(c, "new/composer").unwrap_or(0.0)
  let files = new_files_open(src, w.id)
  side_ask(src, r, "clear", None)
  if files {
    side_ask(src, r, "open", Some("files"))
  }
}

///|
/// The page's composer (NewChat.tsx's ComposerSlot): the station's new chat's draft, roomy, the page's choices in its
/// row (`tools`), locked while nothing can run it (no model, no runtime) or while the page waits for its stations
/// (`held`); its first words, while the chat is made for them, drawn where they were typed (madeChat.ts sendingFirst).
fn new_composer(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  v : Json?,
  address : String,
  name : String,
  held : Bool,
  tools : (() -> Unit)?,
) -> Unit {
  let spec : @sfpages.ComposerSpec = {
    station: address,
    draft: "new:" + address,
    session: "",
    placeholder: @sf.t("web-main.newChat.placeholder"),
    toolbar: tools,
    roomy: true,
    locked: held || text(v, "runtime") == "" || field(v, "model") is None,
    offline: false,
  }
  @sfpages.composer(c, src, w, spec, fn(d) { new_send(c, src, w, v, address, name, d) })
  @sfbase.flight_carry_waiting(c)
}

///|
/// The new chat's first message (draft.ts send with `first`, NewChat.tsx useEnsureChat, onSending, onSent): its words
/// and files taken off the composer where they were typed, carried there while the chat is made (once a page:
/// `newChat.create`, made anew when the picks changed), then sent into it (`chat.send`); the page becomes the chat, its
/// first words in its list from now and going on there, what is written meanwhile going on into the chat's draft
/// (`composer.carry`). The chat not made, or the message never taken in: what was taken back in the composer, saying
/// why.
fn new_send(c : @ui.Ctx, src : Source, w : Workspace, v : Json?, station : String, name : String, d : Writing) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  if fresh.starting {
    return
  }
  let words = d.text.trim(chars=" \n\t").to_string()
  let up = d.files.filter_map(fn(f) { field(Some(f), "done") })
  let going = @sfpages.going_up(d)
  // (its words where they were typed while the chat is made: carried; the desktop's flight, the web's)
  @sfbase.flight_carry_start(
    c,
    d.key,
    words,
    [],
    field=@sfpages.composer_field_key,
    font=@sfpages.text_size,
    line=@sfpages.text_line,
    desk=true,
  )
  fresh.starting = true
  @sfbase.writing_starting(src, d, true)
  let sig = picked_sig(v)
  let give_back = fn(e : Json) {
    fresh.starting = false
    @sfbase.flight_carry_gone(d.key)
    @sfbase.writing_starting(src, d, false)
    @sfbase.writing_restore(src, d, text(Some(e), "message"))
  }
  @sfbase.writing_take(src, d, fn(taken) {
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
            // the page becomes the chat, in place, its first words in its list from now and going on there
            let r : ChatRef = { station, session: key, title: "", station_name: name }
            let rk = station + "\u{1}" + key
            @sfbase.flight_carry_into(d.key, station + ":" + key, rk, sent_local(rk, None, words, up))
            // what is written meanwhile goes on in the chat's draft (dock.tsx carryTo)
            @sfbase.writing_carry(src, d.key, station + ":" + key)
            fresh.scene = v
            fresh.became = Some(r)
            became_starts(wide=true)
            new_sent(c, src, w, r)
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

///|
/// Its column (newChat: in the middle of the pane, 32 in; newChatInner: 720 at most, its parts 10 apart and centred),
/// `body` given its width.
fn new_column(c : @ui.Ctx, body : (Double) -> Unit) -> Unit {
  let col = dmin(new_column_w, c.width - 2.0 * new_column_in)
  c.box(style=new_page_box, fn() { c.box(style=new_inner.then(@ui.style(w=Fixed(col))), fn() { body(col) }) |> ignore })
  |> ignore
}

///|
/// The scene (Illustration "new-chat": 320 wide).
fn new_scene(c : @ui.Ctx) -> Int {
  @sf.drawable(c, if @sf.theme().dark { "illus_new_chat_dark" } else { "illus_new_chat" }, new_scene_w)
}

///|
/// Nothing to run a chat with yet (NewChat's `blocked`: FirstOne): a station none of whose profiles is open here, what
/// to add; one whose profiles are not shared with this workspace, whom to ask; one with no model picked, where to pick
/// them; the station chosen anew among several.
fn new_blocked(c : @ui.Ctx, src : Source, w : Workspace, v : Json?, station : Json?) -> Unit {
  let address = text(station, "station")
  let name = match text(station, "name") {
    "" => @sf.t("web-main.newChat.thisMachine")
    n => n
  }
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
        let t = @sf.theme()
        @sf.drawable(c, if t.dark { "illus_no_profile_dark" } else { "illus_no_profile" }, new_scene_w) |> ignore
      },
      fn() {
        match blocked {
          "profile" =>
            if @sf.button(c, @sf.t("web-main.newChat.addProfile"), key="new/add-profile", tone=Primary, icon="plus") {
              app.nav.push(Setting(@settings.Route::NewProfile(address)))
            }
          "shared" => ()
          _ =>
            if @sf.button(c, @sf.t("web-main.newChat.goPickModels"), key="new/pick-models", tone=Primary) {
              app.nav.push(Setting(@settings.Route::Profiles(address)))
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
/// The composer's choices (NewChat.tsx toolbar): where it runs (its stations, a chooser over the composer), what it
/// runs on (the model control, its panel over the composer); with nothing to run, the way to where models are chosen.
fn new_tools(c : @ui.Ctx, src : Source, w : Workspace, v : Json?, station : Json?) -> Unit {
  let address = text(station, "station")
  if text(station, "name") != "" {
    station_chooser(c, src, w, v, station, Top)
  }
  let p = field(v, "pick")
  if text(v, "runtime") == "" || field(v, "model") is None {
    // nothing to choose from: the chooser leads to where models are enabled
    let id = c.id("new/no-models")
    c.cursor(id, Hand)
    if c.clicked(id) {
      app.nav.push(Place("profiles"))
    }
    let b = c.box(style=new_link_box, id~, fn() { c.text(@sf.t("web-main.newChat.noModels"), style=new_link) |> ignore })
    c.semantics(b, Link, id~, label=@sf.t("web-main.newChat.noModels"))
  } else {
    @sfpages.model_triple(c, src, address, "new", up=true, page=p, small=true)
  }
}

///|
/// Where it runs (Chooser of the stations, StationMark before each name), the one it is on checked; chosen, the core
/// picks it (`newChat.pick`).
fn station_chooser(c : @ui.Ctx, src : Source, w : Workspace, v : Json?, station : Json?, side : @ui.Side) -> Unit {
  let address = text(station, "station")
  let entries = items(v, "stations").map(fn(s) {
    let s = Some(s)
    @kit.menu_radio(text(s, "id"), text(s, "station") == address, label=text(s, "name"))
  })
  let m = @sf.chooser(c, "new/station", text(station, "name"), entries, newchat.station_menu, side~, lead=fn(ink) {
    @sf.station_mark(c, text(station, "emoji"), text(station, "icon"), new_mark, ink)
  })
  newchat.station_menu = m.open
  match m.chosen {
    // (told once the frame is built: what was chosen, once)
    Some(id) => c.tell("new/pick", fn() { pick_new(src, w.id, { "station": Json::string(id) }) })
    None => ()
  }
}

///|
/// The frequent combinations (FrequentCombos): their name over them, each one press to pick (`newChat.pick`), the
/// one in use pressed in; `leaving`, none taken.
fn frequent_combos(c : @ui.Ctx, src : Source, w : Workspace, combos : Array[Json], leaving : Bool) -> Int {
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
          c.tell("new/pick", fn() { pick_new(src, w.id, m) })
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
/// A line of what is wrong for now (spentNotice): the amber's 12% under it, 8 by 12 in, 10 round.
fn new_notice(c : @ui.Ctx, words : String) -> Int {
  c.box(style=new_notice_box, fn() { c.text(words, style=new_notice_words) |> ignore })
}

///|
/// Node `i` of the page as it leaves (`going`: how far up, how far faded): `up`, out of view above as it fades
/// (madeChat.ts: translateY(-32px) scale(.96)); else fading where it is. While it stays, fading in as it comes from a
/// chat (switch.mbt).
fn new_going(c : @ui.Ctx, i : Int, going : (Double, Double)?, up : Bool) -> Unit {
  match going {
    Some((u, _)) if up => c.look(i, @ui.look(alpha=1.0 - u, dy=-new_leave_rise * u, scale=1.0 - new_leave_shrink * u))
    Some((_, f)) => c.look(i, @ui.look(alpha=1.0 - f))
    None => switch_appear(c, i)
  }
}

///|
/// Over the chat a new chat became (madeChat.ts toMadeChat, data-made-leave): the page as it was but for its composer
/// (gone to the chat's foot, its place kept): its scene going up out of view as it fades (140 ms), what is under the
/// composer fading where it is (80 ms); then nothing. And a new chat left for a chat by the sidebar, fading over it
/// (switch.mbt). Drawn over the chat's page, after it.
pub fn new_chat_after(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef) -> Unit {
  match fresh.became {
    Some(b) if b == r && new_leave(c).moving() => {
      let v = fresh.scene
      let l = c.layer(fn() {
        new_page(c, src, w, v, field(v, "station"), Some((new_leave(c).get(), new_fade(c).get())))
      })
      // (drawn only, while it leaves)
      c.draw_only(l)
    }
    _ => ()
  }
  switch_new_out(c, src, w)
}

///|
/// Whether the workspace's new chat has its 文件 tab open (what the core keeps for it on this device, the prefs'
/// `chatTabs` by `new:<workspace>`).
fn new_files_open(src : Source, ws : String) -> Bool {
  let kept = field(field((src.topic)("prefs", {}).value, "chatTabs"), "new:" + ws)
  items(kept, "tabs").contains(Json::string("files"))
}

///|
/// The workspace's new chat's 文件 tab opened or closed, kept by the core on this device (`chat.tabs.*`).
fn new_files_set(src : Source, ws : String, on : Bool) -> Unit {
  let open = new_files_open(src, ws)
  side_changing("new:" + ws, if open { ["files"] } else { [] }, if open { "files" } else { "" }, on)
  let call = if on { "chat.tabs.open" } else { "chat.tabs.close" }
  (src.call)(call, { "chat": Json::string("new:" + ws), "tab": "files" }, fn(_) {  })
}

///|
/// The new chat's side panel: its one tab, Station 文件 (FilesTab), closed by its × or the panel's; the files of the
/// workspace's stations, what is added going into the new chat's draft (DriveTab).
fn new_files_panel(c : @ui.Ctx, src : Source, w : Workspace, address : String) -> Unit {
  c.box(style=side_panel_style, fn() {
    c.box(style=side_bar, fn() {
      c.box(style=side_tab_list, fn() {
        let close = c.id("new/files-tab-close")
        c.cursor(close, Hand)
        if c.clicked(close) {
          new_files_set(src, w.id, false)
        }
        c.box(style=side_tab, selected=true, fn() {
          @sf.icon(c, "folder", size=new_tab_icon, color=@sf.theme().p.text) |> ignore
          c.text(@sf.t("web-pages.chat.files"), style=side_tab_front) |> ignore
          c.box(style=side_tab_close, id=close, fn() {
            @sf.icon(c, "close", size=new_tab_close, color=@sf.theme().p.muted) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
      if icon_button(c, "new/files-close", "panel-close", label=@sf.t("web-pages.chat.closePanel"), action="panel.close") {
        new_files_set(src, w.id, false)
      }
    })
    |> ignore
    c.box(style=side_pane, fn() { files_tab(c, src, w.id, "new:" + address, address) }) |> ignore
  })
  |> ignore
  // (panel.close: the panel closed)
  let prefs = (src.topic)("prefs", {}).value
  if @settings.action_pressed(c, prefs, "panel.close") {
    new_files_set(src, w.id, false)
  }
}

///|
/// How far what leaves goes up, and how much smaller it gets.
let new_leave_rise : Double = 32.0

///|
let new_leave_shrink : Double = 0.04

///|
/// The column (newChatInner: 720 at most, 32 in from the pane's sides), the scene's width (ILLUS_SIZE: 320), a station's
/// mark in its chooser (14), the panel's tab's icons.
let new_column_w : Double = 720.0

///|
let new_column_in : Double = 32.0

///|
let new_scene_w : Double = 320.0

///|
let new_mark : Double = 14.0

///|
let new_tab_icon : Double = 14.0

///|
let new_tab_close : Double = 12.0

///|
/// The page's ground, its whole pane.
// kept across runs: a value (no field of it changes)
let new_ground : @ui.Style = @ui.css("w=Full h=Full bg=Bg")

///|
// kept across runs: a value (no field of it changes)
let new_frame : @ui.Style = @ui.css("w=Full h=Full")

///|
/// Where 文件 is: the chat's bar's end, over the page.
// kept across runs: a value (no field of it changes)
let new_files_bar : @ui.Style = @ui.style(row=true, w=Full, h=@sf.wide_bar_h_size, px=S3, align=ACenter, justify=JEnd)

///|
/// newChat: what it holds in the middle of the pane.
// kept across runs: a value (no field of it changes)
let new_page_box : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
/// newChatInner: its parts 10 apart, centred.
// kept across runs: a value (no field of it changes)
let new_inner : @ui.Style = @ui.css("gap=S2_5 align=ACenter")

///|
/// 新对话 (newChatTitle: the heading's 22, 600).
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
let new_status : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Fg, center=true, w=Full)

///|
// kept across runs: a value (no field of it changes)
let new_error : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Danger, center=true, w=Full)

///|
/// Where the offer of the machine's sessions hangs, under the status line (newChatOffer).
// kept across runs: a value (no field of it changes)
let new_offer : @ui.Style = @ui.css("w=Full align=ACenter")

///|
/// spentNotice: the amber's 12% under 13's words, 8 by 12 in, 10 round, 8 under it.
// kept across runs: a value (no field of it changes)
let new_notice_box : @ui.Style = @ui.css("w=Full px=S3 py=S2 radius=Lg bg=A(Warn,O10)")

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
