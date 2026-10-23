// A new chat (ember apps/android chat/screens/NewChat.kt, ChatHost.kt): it rises from the bottom over the page under it
// (380 ms, (.2, .8, .2, 1)); say what to do, having picked where it runs (the station: a sheet of the workspace's
// stations up now) and on what (the model, its runtime, how hard it thinks, who runs it: a sheet of two columns, its
// accounts in its foot), as the core keeps them (the `newChat` topic; `newChat.pick`, `pick.set`, `pick.save`). The
// composer at its foot is a chat's (composer.mbt), its draft the station's (`new:<station>`). The first message makes
// the chat (`newChat.create`, the core has it at once under the key it answers, its station makes it behind it) and
// goes to it (`chat.send` by that key); then the page becomes that chat in place (@ui.Nav::become), its composer and
// focus kept: the new chat's scene goes up out of view as it fades (140 ms), its choices fade where they are (80 ms).
// The words sent stay where they were typed from the frame they are sent, and once their row is in the chat's list
// they go to it with the list coming up out of the composer (flight.mbt: carried, 480 ms after 90). Home lists it at
// once (the core's row).

///|
/// What the page keeps while it is a new chat, and as it becomes its chat.
priv struct FreshChat {
  /// the chat made for the first message (its key), and what was picked when it was made: picked anew, it is made
  /// anew (until a message went to it)
  mut made : String
  mut made_sig : String
  mut sent : Bool
  /// a message on its way (the create and the send)
  mut starting : Bool
  /// the chat it became (its scene leaving over it: new_leave)
  mut became : ChatRef?
  /// the scene's look as it left: the view it showed
  mut scene : Json?
}

///|
let fresh : FreshChat = {
  made: "",
  made_sig: "",
  sent: false,
  starting: false,
  became: None,
  scene: None,
}

///|
/// A new chat's page, rising over the page on top (Places.kt: 令 in the bar's notch); `in_place`, in the place of the
/// page on top if it is not the stack's root (AppState.open: the latest chats' on a wide screen, corners.mbt).
fn new_chat(c : @ui.Ctx, in_place? : Bool = false) -> Unit {
  ignore(c)
  fresh.made = ""
  fresh.made_sig = ""
  fresh.sent = false
  fresh.starting = false
  fresh.became = None
  fresh.scene = None
  lower_sheet()
  app.menu = false
  if in_place && app.nav.depth() > 1 {
    app.nav.replace(NewChat)
  } else {
    app.nav.rise(NewChat)
  }
}

///|
/// The runtimes' names (Words.kt RUNTIME_LABEL).
fn runtime_label(r : String) -> String {
  match r {
    "claude" => "Claude Code"
    "codex" => "Codex"
    "dsh" => "DeepSeek Harness"
    _ => r
  }
}

///|
/// The newChat topic of the workspace in view.
fn new_chat_topic(src : Source, ws : String) -> Topic {
  (src.topic)("newChat", { "scope": Json::string(ws) })
}

///|
/// Picks for a new chat in the workspace (`newChat.pick`, the core keeps them): each given changes only that.
fn pick_new(c : @ui.Ctx, src : Source, ws : String, fill : Map[String, Json]) -> Unit {
  if src.read_only {
    say(c, read_only_words)
    return
  }
  fill["scope"] = Json::string(ws)
  (src.call)("newChat.pick", Json::object(fill), fn(res) {
    match res {
      Err(e) => {
        app.toast = fill_words("android-chat.pick.failed", text(Some(e), "message"))
        app.toast_n += 1
      }
      _ => ()
    }
  })
}

///|
fn fill_words(key : String, error : String) -> String {
  fill(key, [("error", error)])
}

///|
/// The page's bar (Parts.kt NavBar): 取消 back, 新对话 in the middle.
fn new_chat_bar(c : @ui.Ctx) -> Unit {
  // the wide frame's new chat has no bar (the sidebar's 新建对话 is lit): what it holds is in the middle of all of the
  // pane, as the web's (its bar is over the page)
  if wide_on.val {
    return
  }
  if @sf.nav_bar(c, "new/cancel", tr("common.cancel"), tr("android-chat.new.title"), bg=@sf.theme().p.bg, top=status_top()) {
    app.nav.pop() |> ignore
  }
}

///|
/// The new chat's page (NewChatScreen): its bar; while its stations are read, their first read; with none at all, the
/// first station to add; with none up, said so; else the page on the station it starts on.
fn new_chat_page(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  // on a wide screen in a column in the middle, its composer too (Wide.kt NewChatColumn)
  new_chat_column(c, fn() { new_chat_in(c, src, w) })
  // the first words sent, where they were typed, while the chat is made (flight.mbt)
  flight_carry_waiting(c)
}

///|
fn new_chat_in(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let topic = new_chat_topic(src, w.id)
  let v = topic.value
  // over the navigation bar (ChatHost.kt: windowInsetsPadding(keyboard.union(navigationBars)))
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, pb=nav_foot(), fn() {
    new_chat_bar(c)
    let station = match field(v, "station") {
      Some(Object(_)) as s => s
      _ => None
    }
    match field(v, "stations") {
      Some(Array(_)) if v is Some(_) =>
        if !flag(v, "any") {
          c.box(w=Fill(1.0), pad=30.0, gap=10.0, align=ACenter, fn() {
            @sf.drawable(c, if t.dark { "illus_no_station_dark" } else { "illus_no_station" }, 240.0)
            |> ignore
            c.text(tr("android-settings.station.first"), size=17.0, weight=600, color=t.p.text, center=true, w=Fill(1.0))
            |> ignore
            c.text(tr("android-settings.station.firstNote"), size=14.0, color=t.p.muted, center=true, w=Fill(1.0), line=20.0)
            |> ignore
          })
          |> ignore
        } else {
          match station {
            None =>
              c.box(w=Fill(1.0), h=Fill(1.0), pad=30.0, gap=10.0, align=ACenter, justify=JCenter, fn() {
                @sf.drawable(
                  c,
                  if t.dark {
                    "illus_station_offline_dark"
                  } else {
                    "illus_station_offline"
                  },
                  240.0,
                )
                |> ignore
                c.text(tr("android-chat.new.offline.title"), size=17.0, weight=600, color=t.p.text, wrap=false)
                |> ignore
                c.text(
                  fill("android-chat.new.offline.text", [("app", "still.fail")]),
                  size=14.0,
                  color=t.p.muted,
                  center=true,
                  w=Fill(1.0),
                  line=20.0,
                )
                |> ignore
              })
              |> ignore
            Some(_) => new_chat_on(c, src, w, v, station, false)
          }
        }
      _ => {
        let error = match text(v, "error") {
          "" =>
            match topic.error {
              Some(e) => Some(text(Some(e), "message"))
              None => None
            }
          e => Some(e)
        }
        waiting(c, 7, None, error)
      }
    }
  })
  |> ignore
}

///|
/// What was picked, as one string: a pick changed makes the chat anew (until a message went to it).
fn picked_sig(v : Json?) -> String {
  text(field(v, "model"), "model") +
  "|" +
  text(v, "runtime") +
  "|" +
  text(v, "effort") +
  "|" +
  text(v, "profile") +
  "|" +
  (match field(v, "fast") {
    Some(True) => "fast"
    Some(False) => "standard"
    _ => ""
  })
}

///|
/// The page on a station (NewChatOn): the scene (the illustration, what to do, the frequent combinations, what keeps
/// it from starting), and at its foot over the composer the choices: where it runs, what it runs on. `leaving`: it has
/// become its chat, which is under it now: only its scene is drawn, going.
fn new_chat_on(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  v : Json?,
  station : Json?,
  leaving : Bool,
) -> Unit {
  let t = @sf.theme()
  let address = text(station, "station")
  let name = text(station, "name")
  let sig = picked_sig(v)
  if !fresh.sent && !fresh.starting && sig != fresh.made_sig {
    fresh.made = ""
  }
  // at a desktop's width, the web's page (wide_newchat.mbt); once its first words are sent, the composer at the foot
  // where the chat's is, as the web's goes to the chat's dock (the words fly from there into the chat: flight.mbt)
  if wide_on.val && !leaving && !fresh.sent && !fresh.starting {
    new_chat_page_wide(c, src, w, v, station)
    return
  }
  // leaving: up out of view as it fades (140 ms, Arrive), the choices fading where they are (80 ms)
  let (up, fade) = if leaving {
    (new_leave(c).get(), new_fade(c).get())
  } else {
    (0.0, 0.0)
  }
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    // the scene in what is left over the foot, scrolled when it does not fit (NewChat.kt: weight(1f), verticalScroll):
    // the keyboard up, the choices and the composer stay over it
    c.box(style=new_scene_room, fn() {
    c.list("new/scene", 1, new_scene_h, fn(_) {
    let scene = c.box(
      w=Fill(1.0),
      pl=30.0,
      pr=30.0,
      pt=30.0,
      pb=10.0,
      gap=6.0,
      align=ACenter,
      ty=-32.0 * up,
      opacity=1.0 - up,
      fn() {
        @sf.drawable(c, if t.dark { "illus_new_chat_dark" } else { "illus_new_chat" }, 230.0)
        |> ignore
        // (the wide frame's, its first words sent: the web's words, as the page had them, going)
        c.box(pt=6.0, fn() {
          c.text(
            tr(if wide_on.val { "web-main.newChat.title" } else { "android-chat.new.heading" }),
            size=22.0,
            weight=700,
            color=t.p.text,
            wrap=false,
            line=30.8,
          )
          |> ignore
        })
        |> ignore
        c.text(
          if wide_on.val {
            fill("web-main.newChat.sub", [("name", if name == "" { tr("web-main.newChat.thisMachine") } else { name })])
          } else {
            fill("android-chat.new.sub", [("station", name)])
          },
          size=14.0,
          color=t.p.muted,
          center=true,
          w=Fill(1.0),
          line=20.0,
        )
        |> ignore
        let combos = items(v, "frequent")
        if combos.length() > 0 {
          c.box(w=Fill(1.0), pt=12.0, pb=12.0, gap=8.0, align=ACenter, fn() {
            c.text(tr("android-chat.new.frequent"), size=12.0, color=t.p.muted, wrap=false) |> ignore
            // as many a line as fit, in the middle (FlowRow, 6 apart each way): each as wide as its words
            c.box(style=frequent_flow, flow=true, fn() {
              for combo in combos {
                frequent_chip(c, src, w, Some(combo), leaving)
              }
            })
            |> ignore
          })
          |> ignore
        }
        match opt_text(v, "problem") {
          Some(p) =>
            c.box(pt=6.0, w=Fill(1.0), fn() {
              c.text(
                p,
                size=13.0,
                color=if flag(v, "waiting") || text(v, "blocked") == "" {
                  t.p.muted
                } else {
                  t.p.red
                },
                center=true,
                w=Fill(1.0),
                line=18.0,
              )
              |> ignore
            })
            |> ignore
          None => ()
        }
        if text(v, "blocked") == "profile" {
          c.box(pt=6.0, w=Fill(1.0), fn() {
            c.text(
              fill("android-chat.new.profile.text", [("station", name)]),
              size=13.0,
              color=t.p.muted,
              center=true,
              w=Fill(1.0),
              line=18.0,
            )
            |> ignore
          })
          |> ignore
          if @sf.button(c, tr("android-chat.new.profile.add"), key="new/profile", tone=Primary) {
            app.nav.push(Setting(@settings.Route::NewProfile(address)))
          }
        }
        // the machine's own sessions to go on with, where it kept any (NewChat.kt MachineSessionsOffer)
        let blocked = text(v, "blocked")
        if field(station, "overview") is Some(Object(_)) && blocked != "profile" && blocked != "shared" && !src.read_only {
          @settings.machine_sessions_offer(c, settings_core(src, w), address, name)
        }
      },
    )
    // and a little smaller as it goes, from its middle (NewChat.kt: scale 1 - 0.04 a)
    if up > 0.0 {
      c.look(scene, @ui.look(scale=1.0 - 0.04 * up))
    }
    }) |> ignore
    }) |> ignore
    // at the foot, on the page's paper: what was used up, the choices, the composer
    c.box(w=Fill(1.0), bg=if leaving { 0L } else { t.p.bg }, opacity=1.0 - fade, fn() {
      if !leaving {
        match opt_text(v, "spent") {
          Some(spent) =>
            c.box(w=Fill(1.0), padx=12.0, fn() {
              c.box(
                w=Fill(1.0),
                radius=12.0,
                bg=@sf.over(t.p.bg, @sf.alpha(0xD9962BFFL, 0.12)),
                padx=12.0,
                pady=8.0,
                fn() { c.text(spent, size=13.0, color=t.p.text, line=18.0) |> ignore },
              )
              |> ignore
            })
            |> ignore
          None => ()
        }
      }
      c.box(w=Fill(1.0), pl=10.0, pr=10.0, pt=8.0, fn() {
        c.box(dir=Row, w=Fill(1.0), padx=2.0, pady=6.0, gap=6.0, fn() {
          if chooser(
              c,
              "new/station",
              fn() {
                station_or_server(c, text(station, "emoji"), text(station, "icon"), 14.0, t.p.text)
              },
              name,
              128.0,
              false,
            ) &&
            !leaving {
            raise_sheet(PickStation(w.id))
          }
          let p = field(v, "pick")
          let options = items(p, "options")
          let runtime = text(v, "runtime")
          let model = text(field(v, "model"), "model")
          if p is None || options.length() == 0 {
            if chooser(c, "new/models", fn() {  }, tr("android-chat.new.noModels"), 1.0e9, false) && !leaving {
              app.nav.push(Place("profiles"))
            }
          } else if runtime == "" || model == "" {
            if chooser(c, "new/model", fn() {  }, tr("android-chat.pick.model"), 1.0e9, true) && !leaving {
              raise_sheet(RunPicker(address))
            }
          } else {
            let on = field(p, "valueOption")
            // (a model's maker: the core's Maker, its id the mark's)
            let maker = match text(field(on, "maker"), "id") {
              "" => text(field(field(v, "model"), "maker"), "id")
              m => m
            }
            if chooser(
                c,
                "new/model",
                fn() { @sf.maker_mark(c, maker, runtime, 14.0) |> ignore },
                triple_label(p),
                1.0e9,
                true,
              ) &&
              !leaving {
              raise_sheet(RunPicker(address))
            }
          }
        })
        |> ignore
      })
      |> ignore
      if !leaving {
        let r : ChatRef = { station: address, session: "", title: "", station_name: name }
        wide_center(c, fn() {
          composer(c, src, r, None, fresh=Some({
            key: "new:" + address,
            placeholder: tr("android-chat.new.placeholder"),
            send: fn(d) { send_first(c, src, w, v, address, name, d) },
            tools: None,
          }))
        })
      } else {
        c.box(h=Px(composer_room_of(c)), fn() {  }) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A station's mark where it has one (Parts.kt StationMark), else the server's (`none = Icons.Server`).
fn station_or_server(c : @ui.Ctx, emoji : String, icon : String, size : Double, tint : Int64) -> Unit {
  if @sf.has_station_mark(emoji, icon) {
    @sf.station_mark(c, emoji, icon, size, tint)
  } else {
    @sf.icon(c, "server", size~, color=tint) |> ignore
  }
}

///|
/// A frequent combination (model and depth), one tap to pick.
fn frequent_chip(c : @ui.Ctx, src : Source, w : Workspace, combo : Json?, leaving : Bool) -> Unit {
  let t = @sf.theme()
  let selected = flag(combo, "selected")
  let id = c.id("new/combo/" + text(combo, "label"))
  if c.clicked(id) && !leaving {
    let m : Map[String, Json] = {
      "model": Json::string(text(combo, "model")),
      "runtime": Json::string(text(combo, "runtime")),
    }
    m["effort"] = match opt_text(combo, "effort") {
      Some(e) => Json::string(e)
      None => Json::null()
    }
    pick_new(c, src, w.id, m)
  }
  c.box(
    padx=10.0,
    pady=8.0,
    radius=18.0,
    bg=@sf.alpha(t.p.text, if selected { 0.10 } else { 0.04 }),
    id~,
    fn() {
      c.text(
        text(combo, "label"),
        size=13.0,
        color=if selected { t.p.text } else { t.p.muted },
        wrap=false,
        line=18.0,
      )
      |> ignore
    },
  )
  |> ignore
}

///|
/// A choice over the composer (NewChat.kt Chooser): 30 high, a capsule of the composer's glass, its mark, its words
/// (cut short), a chevron. True on the frame after it was tapped.
fn chooser(
  c : @ui.Ctx,
  key : String,
  lead : () -> Unit,
  label : String,
  max_w : Double,
  chevron : Bool,
) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.box(
    dir=Row,
    h=Px(30.0),
    max_w~,
    padx=11.0,
    gap=6.0,
    align=ACenter,
    radius=15.0,
    glass=@sf.glass_floating(),
    shadow=@sf.floating.sigma,
    shadow_color=@sf.floating.color,
    shadow_y=@sf.floating.dy,
    clip=true,
    id~,
    fn() {
      lead()
      c.box(clip=true, fn() {
        c.text(label, size=13.0, color=t.p.text, wrap=false, line=18.0) |> ignore
      })
      |> ignore
      if chevron {
        @sf.icon(c, "chevron-down", size=12.0, color=t.p.muted) |> ignore
      }
      // NewChat.kt: floating(Smooth(15)).clickable
      @motion.ripple(c, id, 15.0)
    },
  )
  |> ignore
  c.clicked(id)
}

///|
/// What the model control says (NewChat.kt tripleLabel): the model, the runtime where there is a choice, how hard it
/// thinks, how fast, who runs it when that matters.
fn triple_label(p : Json?) -> String {
  let value = field(p, "value")
  let on = field(p, "valueOption")
  let parts : Array[String] = []
  parts.push(
    match text(on, "name") {
      "" =>
        match text(value, "model") {
          "" => tr("android-chat.pick.model")
          m => m
        }
      n => n
    },
  )
  if !flag(p, "runtimeFixed") && items(on, "runtimes").length() > 1 {
    parts.push(runtime_label(text(value, "runtime")))
  }
  parts.push(
    match text(value, "effort") {
      "" => tr("android-chat.pick.effort.default")
      e => e
    },
  )
  match opt_text(p, "fastText") {
    Some(f) => parts.push(f)
    None => ()
  }
  match text(field(p, "account"), "text") {
    "" => ()
    a => parts.push(a)
  }
  parts.join(" · ")
}

///|
/// The first message (NewChat.kt onSend): the composer emptied at once, the chat made if it was not (`newChat.create`),
/// the message sent to it by its key (`chat.send`: it waits in the chat's outbox until its station has made it); then
/// the page becomes the chat. Nothing sent: the draft comes back, and why is said.
fn send_first(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  v : Json?,
  station : String,
  station_name : String,
  d : Draft,
) -> Unit {
  ignore(w)
  if src.read_only {
    say(c, read_only_words)
    return
  }
  if fresh.starting {
    return
  }
  let words = with_link_words(d.text.trim(chars=" \n\t").to_owned(), d)
  let files = up_files(d)
  let uploads = up_uploads(d)
  let quotes = d.quotes.map(fn(q) { quote_json(d, q, true) })
  let taken_text = d.text
  let taken_files = d.files.copy()
  // the words stay where they were typed, the files where their tiles were, while the chat is made (flight.mbt:
  // carried; NewChat.kt host.sending)
  let here : ChatRef = { station, session: "", title: "", station_name }
  // (not from the wide frame's composer in the middle of the page: the chat's list would be carried up from there,
  // half a page, and its rows put where it is drawn would not stay put; the row is where it is, as with motion
  // reduced, the page going as it goes)
  if !wide_on.val {
    flight_carry_start(c, d.key, words, draft_flying(c, src, here, d))
  }
  ref_field_put(d, "")
  d.files.clear()
  d.quotes.clear()
  d.comments.clear()
  d.error = None
  // sent: what is written next is another draft, which the core names as this one is kept empty
  sent_draft(d, taken_files.length())
  save_draft(src, d)
  fresh.starting = true
  let sig = picked_sig(v)
  let give_back = fn(e : Json) {
    fresh.starting = false
    flight_carry_gone(d.key)
    if draft_empty(d) {
      d.text = taken_text
      d.put_text = Some(taken_text)
      for f in taken_files {
        d.files.push(f)
      }
      save_draft(src, d)
    }
    d.error = Some(text(Some(e), "message"))
  }
  let send = fn(key : String) {
    let params : Map[String, Json] = {
      "station": Json::string(station),
      "session": Json::string(key),
      "text": Json::string(words),
      "attachments": Json::array(files),
      "quotes": Json::array(quotes),
    }
    if uploads.length() > 0 {
      params["uploads"] = Json::array(uploads)
    }
    (src.call)("chat.send", Json::object(params), fn(res) {
      match res {
        Err(e) => give_back(e)
        Ok(_) => {
          fresh.sent = true
          fresh.starting = false
          // the page becomes the chat, in place, its first words in its list from now and going on there
          let r : ChatRef = { station, session: key, title: "", station_name }
          let rk = station + "\u{1}" + key
          flight_carry_into(d.key, draft_key(r), rk, sent_local(rk, None, words, files))
          fresh.scene = v
          fresh.became = Some(r)
          became_starts()
          app.nav.become(Chat(r))
        }
      }
    })
  }
  if fresh.made != "" {
    send(fresh.made)
  } else {
    (src.call)("newChat.create", Json::object({ "station": Json::string(station) }), fn(res) {
      match res {
        Ok(made) =>
          match text(Some(made), "key") {
            "" => give_back(Json::object({ "message": Json::string("newChat.create: no key") }))
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
}

///|
/// A new chat's scene leaving as it becomes the chat: up out of view as it fades; its choices fading where they are.
let new_leave_ms : Double = 140.0

///|
let new_fade_ms : Double = 80.0

///|
/// Over the chat a new chat became: its scene leaving (140 ms), then nothing.
fn new_chat_leaving(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef) -> Unit {
  match fresh.became {
    Some(b) if b == r => ()
    _ => return
  }
  // (drawn only, while it leaves)
  if !new_leave(c).moving() {
    return
  }
  let v = fresh.scene
  c.layer(fn() {
    new_chat_column(c, fn() {
      // its bar gone at once (the chat has its own), its room kept
      c.box(h=Px(48.0), fn() {  }) |> ignore
      new_chat_on(c, src, w, v, field(v, "station"), true)
    })
  })
  |> ignore
}

///|
/// Whether the page of chat `r` is the one a new chat just became, its first value not read yet (its scene leaving,
/// its first words on their way): the core's own, nothing breathing over it (Chat.kt made).
fn new_chat_made(c : @ui.Ctx, r : ChatRef) -> Bool {
  match fresh.became {
    Some(b) if b == r => new_leave(c).moving() || flight_carried(draft_key(r))
    _ => false
  }
}

///|
/// The new chat's scene leaving (0 … 1: up out of view, Arrive), its choices fading (0 … 1, LeaveFade).
fn new_leave(c : @ui.Ctx) -> @motion.Anim {
  @motion.anim(c, "new/leave", 1.0, global=true)
}

///|
fn new_fade(c : @ui.Ctx) -> @motion.Anim {
  @motion.anim(c, "new/fade", 1.0, global=true)
}

///|
/// The new chat became the chat: its scene leaves, from now.
fn became_starts() -> Unit {
  let c = @ui.current()
  let leave = new_leave(c)
  leave.snap(0.0)
  leave.animate(1.0, @motion.tween(new_leave_ms, ease=Arrive))
  let fade = new_fade(c)
  fade.snap(0.0)
  fade.animate(1.0, @motion.tween(new_fade_ms, ease=LeaveFade))
}

// ── the sheets ─────────────────────────────────────────────────────────

///|
/// Where a new chat runs (NewChat.kt pickStation): the workspace's stations up now, the one it starts on checked.
fn pick_station_sheet(c : @ui.Ctx, src : Source, ws : String) -> Unit {
  let t = @sf.theme()
  let v = new_chat_topic(src, ws).value
  let current = text(field(v, "station"), "station")
  @sf.sheet_grab(c)
  sheet_head(c, tr("android-chat.new.station.pick"))
  c.box(w=Fill(1.0), h=Fill(1.0), pb=24.0, clip=true, fn() {
    for s in items(v, "stations") {
      let st = Some(s)
      let id = c.id("pick-station/" + text(st, "station"))
      if c.clicked(id) {
        pick_new(c, src, ws, { "station": Json::string(text(st, "id")) })
        lower_sheet()
      }
      c.box(w=Fill(1.0), pl=12.0, pr=12.0, fn() {
        c.box(
          dir=Row,
          w=Fill(1.0),
          padx=8.0,
          pady=12.0,
          gap=12.0,
          align=ACenter,
          id~,
          fn() {
            station_or_server(c, text(st, "emoji"), text(st, "icon"), 22.0, t.p.text)
            c.box(w=Fill(1.0), fn() {
              c.text(text(st, "name"), size=15.0, color=t.p.text, wrap=false, line=21.0) |> ignore
              if text(st, "summary") != "" {
                c.text(text(st, "summary"), size=12.0, color=t.p.muted, line=17.0) |> ignore
              }
            })
            |> ignore
            if text(st, "station") == current {
              @sf.icon(c, "check", size=14.0, color=t.p.accent) |> ignore
            }
            // NewChat.kt: clip(Smooth(LIST_ROW_CORNER)).clickable
            @motion.ripple(c, id, @sf.row_corner)
          },
        )
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The run picker's label of a column (CascadeLabel).
fn cascade_label(c : @ui.Ctx, label : String) -> Unit {
  let t = @sf.theme()
  c.box(pl=10.0, pt=10.0, pb=2.0, fn() {
    c.text(label, size=12.0, color=t.p.muted, wrap=false, line=16.0) |> ignore
  })
  |> ignore
}

///|
/// A choice in a column of the picker (CascadeOption): the chosen one on the accent's pale ground, its words in the
/// accent and bold, a check. True on the frame after it was tapped.
fn cascade_option(
  c : @ui.Ctx,
  key : String,
  label : String,
  sub : String,
  checked : Bool,
  lead : (() -> Unit)?,
  faint? : Bool = false,
  sub_color? : Int64,
) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.box(
    dir=Row,
    w=Fill(1.0),
    padx=10.0,
    pady=10.0,
    gap=10.0,
    align=ACenter,
    radius=10.0,
    bg=if checked { t.p.accent_bg } else { 0L },
    id~,
    fn() {
      match lead {
        Some(f) => f()
        None => ()
      }
      c.box(w=Fill(1.0), clip=true, fn() {
        c.text(
          label,
          size=15.0,
          weight=if checked { 600 } else { 400 },
          color=if checked {
            t.p.accent_text
          } else if faint {
            t.p.muted
          } else {
            t.p.text
          },
          wrap=false,
          line=21.0,
        )
        |> ignore
        if sub != "" {
          c.text(sub, size=12.0, color=sub_color.unwrap_or(t.p.muted), line=16.0) |> ignore
        }
      })
      |> ignore
      if checked {
        @sf.icon(c, "check", size=14.0, color=t.p.accent) |> ignore
      }
      // NewChat.kt: the cascade's row, clip(Smooth(concentric(CASCADE_CORNER, CASCADE_PAD))).clickable
      @motion.ripple(c, id, 14.0 - 4.0 / @sf.smooth_scale)
    },
  )
  |> ignore
  c.clicked(id)
}

///|
/// What a new chat runs on (NewChat.kt openRunPicker), on station `station`: the models in a column (by series), the
/// runtime, how hard it thinks and how fast beside them, who runs it in the foot (its list in the sheet's place, and
/// back). Picks are a draft (`pick.set`) until 确定 (`pick.save`); closed otherwise, nothing changes.
fn run_picker_sheet(c : @ui.Ctx, src : Source, station : String) -> Unit {
  let t = @sf.theme()
  let topic = (src.topic)("pick", { "station": Json::string(station), "of": Json::string("new") })
  let set = fn(fill : Map[String, Json]) {
    if src.read_only {
      return
    }
    fill["station"] = Json::string(station)
    fill["of"] = Json::string("new")
    (src.call)("pick.set", Json::object(fill), fn(res) {
      match res {
        Err(e) => {
          app.toast = fill_words("android-chat.pick.failed", text(Some(e), "message"))
          app.toast_n += 1
        }
        _ => ()
      }
    })
  }
  // picked from what it runs on now, each time it is opened
  // (said once as it opens, with nothing of a build's in it)
  if !run_picker_opened.val {
    run_picker_opened.val = true
    set({ "open": Json::boolean(true) })
  }
  @sf.sheet_grab(c)
  if sheet_host.accounts {
    c.box(dir=Row, w=Fill(1.0), pl=8.0, pr=18.0, pt=4.0, pb=10.0, align=ACenter, fn() {
      let back = c.id("pick/accounts-back")
      if c.clicked(back) {
        sheet_host.accounts = false
      }
      c.box(w=Px(36.0), h=Px(36.0), radius=18.0, align=ACenter, justify=JCenter, id=back, fn() {
        @sf.icon(c, "chevron-left", size=20.0, color=t.p.text) |> ignore
      })
      |> ignore
      c.text(tr("android-chat.new.account"), size=17.0, weight=700, color=t.p.text, wrap=false, line=24.0)
      |> ignore
    })
    |> ignore
  } else {
    sheet_head(c, tr("android-chat.new.model"))
  }
  let v = topic.value
  if v is None {
    waiting(c, 5, None, match topic.error {
      Some(e) => Some(text(Some(e), "message"))
      None => None
    })
    return
  }
  let draft = field(v, "draft")
  if sheet_host.accounts {
    c.box(w=Fill(1.0), h=Fill(1.0), padx=12.0, clip=true, fn() {
      match opt_text(v, "dropped") {
        Some(dropped) =>
          c.box(padx=12.0, pady=4.0, fn() {
            c.text(dropped, size=12.0, color=0xD9962BFFL, line=16.0) |> ignore
          })
          |> ignore
        None => ()
      }
      if cascade_option(
          c,
          "pick/account/auto",
          tr("android-chat.new.auto"),
          text(v, "autoNote"),
          text(draft, "profile") == "",
          None,
        ) {
        set({ "profile": Json::null() })
        sheet_host.accounts = false
      }
      for a in items(v, "accounts") {
        let acc = Some(a)
        let quota = field(acc, "quotaLine")
        let runtime = match text(acc, "runtime") {
          "" => text(draft, "runtime")
          r => r
        }
        if cascade_option(
            c,
            "pick/account/" + text(acc, "id"),
            text(acc, "name"),
            text(quota, "text"),
            text(draft, "profile") == text(acc, "id"),
            Some(fn() { @sf.maker_mark(c, text(acc, "mark"), runtime, 16.0) |> ignore }),
            sub_color=if text(quota, "level") != "" { 0xD9962BFFL } else { t.p.muted },
          ) {
          set({ "profile": Json::string(text(acc, "id")) })
          sheet_host.accounts = false
        }
      }
    })
    |> ignore
    return
  }
  // side by side: the models (by series, in the core's order), and what goes with the one picked
  c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), padx=10.0, gap=8.0, fn() {
    c.box(w=Fill(1.35), h=Fill(1.0), clip=true, fn() {
      let families : Array[String] = []
      for o in items(v, "options") {
        let f = match text(Some(o), "family") {
          "" => tr("android-chat.pick.family.other")
          f => f
        }
        if !families.contains(f) {
          families.push(f)
        }
      }
      for fam in families {
        if families.length() > 1 {
          cascade_label(c, fam)
        }
        for o in items(v, "options") {
          let opt = Some(o)
          let f = match text(opt, "family") {
            "" => tr("android-chat.pick.family.other")
            f => f
          }
          if f != fam {
            continue
          }
          let picked = text(v, "option") == text(opt, "model")
          let faint = text(opt, "availability") == "borrowable" && !picked
          let runtimes = items(opt, "runtimes")
          let runtime = match runtimes.get(0) {
            Some(String(r)) => r
            _ => text(draft, "runtime")
          }
          if cascade_option(
              c,
              "pick/model/" + text(opt, "model"),
              text(opt, "name"),
              text(field(opt, "spent"), "text"),
              picked,
              Some(fn() { @sf.maker_mark(c, text(field(opt, "maker"), "id"), runtime, 16.0) |> ignore }),
              faint~,
            ) {
            set({ "model": Json::string(text(opt, "model")) })
          }
        }
      }
    })
    |> ignore
    c.box(w=Fill(1.0), h=Fill(1.0), radius=14.0, bg=t.p.card, pad=4.0, clip=true, fn() {
      let runtimes = items(v, "runtimes")
      if runtimes.length() > 0 {
        cascade_label(c, tr("android-chat.new.runtime"))
        for r in runtimes {
          let rt = match r {
            String(s) => s
            _ => ""
          }
          if cascade_option(
              c,
              "pick/runtime/" + rt,
              runtime_label(rt),
              "",
              text(draft, "runtime") == rt,
              Some(fn() { @sf.maker_mark(c, "", rt, 16.0) |> ignore }),
            ) {
            set({ "runtime": Json::string(rt) })
          }
        }
      }
      cascade_label(c, tr("android-chat.new.effort"))
      if cascade_option(c, "pick/effort/", tr("android-chat.pick.default"), "", text(draft, "effort") == "", None) {
        set({ "effort": Json::null() })
      }
      for e in items(v, "efforts") {
        let ef = match e {
          String(s) => s
          _ => ""
        }
        if cascade_option(c, "pick/effort/" + ef, ef, "", text(draft, "effort") == ef, None) {
          set({ "effort": Json::string(ef) })
        }
      }
      if flag(v, "fastAvailable") {
        cascade_label(c, tr("android-chat.new.speed"))
        let fast = field(draft, "fast")
        if cascade_option(c, "pick/fast/follow", tr("android-chat.pick.speed.follow"), "", !(fast is Some(True) || fast is Some(False)), None) {
          set({ "fast": Json::null() })
        }
        if cascade_option(c, "pick/fast/standard", tr("android-chat.pick.speed.standard"), "", fast is Some(False), None) {
          set({ "fast": Json::boolean(false) })
        }
        if cascade_option(c, "pick/fast/fast", "Fast", tr("android-chat.new.fast.note"), fast is Some(True), None) {
          set({ "fast": Json::boolean(true) })
        }
      }
    })
    |> ignore
  })
  |> ignore
  // the model picked is another station's: said so over the foot
  match field(v, "borrow") {
    Some(Object(_)) as b =>
      c.box(pl=20.0, pr=20.0, pt=8.0, fn() {
        c.text(
          if flag(b, "allowed") {
            text(b, "note")
          } else {
            match text(b, "why") {
              "" => text(b, "note")
              why => why
            }
          },
          size=12.0,
          color=t.p.muted,
          line=16.0,
        )
        |> ignore
      })
      |> ignore
    _ => ()
  }
  // the foot: who runs it, and 确定
  c.box(dir=Row, w=Fill(1.0), pl=10.0, pr=14.0, pt=10.0, pb=12.0, gap=8.0, align=ACenter, fn() {
    let who = c.id("pick/who")
    if c.clicked(who) {
      sheet_host.accounts = true
    }
    c.box(
      dir=Row,
      w=Fill(1.0),
      padx=10.0,
      pady=10.0,
      gap=4.0,
      radius=12.0,
      align=ACenter,
      id=who,
      fn() {
        c.text(tr("android-chat.new.account"), size=14.0, color=t.p.muted, wrap=false) |> ignore
        c.box(clip=true, fn() {
          c.text(
            text(v, "who"),
            size=14.0,
            color=if text(v, "whoLevel") != "" { 0xD9962BFFL } else { t.p.text },
            wrap=false,
          )
          |> ignore
        })
        |> ignore
        @sf.icon(c, "chevron-right", size=14.0, color=t.p.muted) |> ignore
        // NewChat.kt: clip(Smooth(12)).clickable
        @motion.ripple(c, who, 12.0)
      },
    )
    |> ignore
    // the model picked is another station's: the foot borrows it (asked again) rather than confirming
    match field(v, "borrow") {
      Some(Object(_)) as b => {
        let allowed = flag(b, "allowed")
        // (the calls the settings make here are the station's own: its workspace is the one in view)
        let ws_id = match station.find("/") {
          Some(i) => station.unsafe_substring(start=0, end=i)
          None => station
        }
        let core = settings_core(src, { id: ws_id, name: "", emoji: "", icon: "", email: "" })
        let bid = c.id("pick/borrow")
        if c.clicked(bid) && allowed {
          @settings.confirm_borrow(core, station, "new", b)
        }
        c.box(dir=Row, padx=22.0, pady=9.0, gap=6.0, radius=19.0, align=ACenter, bg=if allowed { t.p.text } else { t.p.chip }, id=bid, fn() {
          c.text(text(b, "action"), size=15.0, weight=600, color=if allowed { t.p.bg } else { t.p.muted }, wrap=false) |> ignore
        })
        |> ignore
        return
      }
      _ => ()
    }
    let changed = flag(v, "changed")
    let ok = c.id("pick/save")
    if c.clicked(ok) && text(v, "option") != "" && !run_picker_saving.val {
      if !changed || src.read_only {
        lower_sheet()
      } else {
        run_picker_saving.val = true
        (src.call)(
          "pick.save",
          Json::object({ "station": Json::string(station), "of": Json::string("new") }),
          fn(res) {
            run_picker_saving.val = false
            match res {
              Ok(_) => if sheet_host.kind == RunPicker(station) { lower_sheet() }
              Err(e) => {
                app.toast = fill_words("android-chat.save.failed", text(Some(e), "message"))
                app.toast_n += 1
              }
            }
                  },
        )
      }
    }
    c.box(
      dir=Row,
      padx=22.0,
      pady=9.0,
      gap=6.0,
      radius=19.0,
      align=ACenter,
      bg=if changed { t.p.text } else { t.p.chip },
      id=ok,
      fn() {
        if run_picker_saving.val {
          @sf.spinner(c, size=14.0, arc=if changed { t.p.bg } else { t.p.text }) |> ignore
        }
        c.text(
          tr(if changed { "android-chat.new.confirm" } else { "android-chat.new.unchanged" }),
          size=15.0,
          weight=600,
          color=if changed { t.p.bg } else { t.p.text },
          wrap=false,
        )
        |> ignore
      },
    )
    |> ignore
  })
  |> ignore
}

///|
/// The run picker asked to pick from what it runs on (once each time it opens), and saving.
let run_picker_opened : Ref[Bool] = { val: false }

///|
let run_picker_saving : Ref[Bool] = { val: false }

///|
/// The frequent choices in lines, in the middle, 6 apart each way (NewChat.kt: a FlowRow).
// kept across runs: a value (no field of it changes)
let frequent_flow : @ui.Style = @ui.style(row=true, w=Full, gap=S1_5, justify=JCenter)

///|
/// The new chat's scene's height as its list guesses it before it is laid out.
let new_scene_h : Double = 600.0

///|
// kept across runs: a value (no field of it changes)
let new_scene_room : @ui.Style = @ui.style(w=Full, h=@sf.grow, clip=true)
