// still.fail in mbui: the core started (src/sfcore), signed out its sign-in page, signed in
// Home (src/sfapp), over the account's own data. (The made-up chats are src/sffix's, never this app's.) A build with
// no core (the web's) says so.
//
// MBUI_CORE_DUMP=1 prints the topics Home reads as they come (DUMP <topic> …), for seeing their shapes; it changes
// nothing (no call is made).

///|
/// The topics asked for, by their key: one subscription each, asked again the same every frame.
let dumped : Map[String, Int] = {}

///|
fn core_topic(name : String, params : Map[String, Json]) -> @sfapp.Topic {
  // (read in a computed, followed: Sub.changes)
  let s = @core.subscribe(name, params~).followed()
  if dump {
    let key = name + " " + Json::object(params).stringify()
    if dumped.get(key) != Some(s.version) {
      dumped[key] = s.version
      match (s.value, s.error) {
        (Some(v), _) => @hostapi.log("DUMP \{key} \{v.stringify()}")
        (_, Some(e)) => @hostapi.log("DUMP \{key} error \{e.stringify()}")
        _ => ()
      }
    }
  }
  { value: s.value, error: s.error, version: s.version }
}

///|
let dump : Bool = @ui.env("MBUI_CORE_DUMP") == "1"

///|
/// MBUI_CALL_LOG=1: every call the app makes, and its answer, on the log (CALL …, ANSWER …), for scripted runs.
let call_log : Bool = @ui.env("MBUI_CALL_LOG") == "1"

///|
/// The fields whose values are secrets (keys, tokens, passwords, a vault item's value, recovery words, a sign-in's code):
/// never put on the call log, at any depth.
let secret_fields : Array[String] = [
  "key", "token", "appToken", "botToken", "refreshToken", "config", "secret", "secrets", "value", "password", "code",
  "words", "phrase", "recovery", "fields", "env",
]

///|
/// A call's params or answer as the call log may show them: every secret's value replaced (`redacted`), and an
/// agent environment's text (it holds proxies' passwords) too.
fn logged(name : String, v : Json) -> String {
  fn scrub(v : Json) -> Json {
    match v {
      Object(m) => {
        let out : Map[String, Json] = Map([])
        for k, x in m {
          out[k] = if secret_fields.contains(k) || (k == "text" && name.has_prefix("agentEnv")) {
            match x {
              Null => x
              _ => Json::string("<redacted>")
            }
          } else {
            scrub(x)
          }
        }
        Json::object(out)
      }
      Array(a) => Json::array(a.map(scrub))
      _ => v
    }
  }
  scrub(v).stringify()
}

///|
/// Pictures by their address as the core gives them (`picture`): kept as images, one that could not be had asked
/// again when it is put up anew (@sfapp.core_pictures).
let picture : (String, Int) -> String = @sfapp.core_pictures(fn(url, done) {
  let params : Map[String, Json] = { "url": Json::string(url) }
  @core.call_bytes("picture", params=Json::object(params), on_done=fn(r) {
    match r {
      Ok((_, bytes)) => done(bytes)
      Err(_) => done(None)
    }
  })
})

///|
/// Chats' images as their messages show them (`station.file` with `thumb`: the station's thumbnail where it keeps one,
/// how far it has come said as it comes), and videos' stills (`station.poster`): "" while one comes, "!" when it could not be had (@sfbase.ChatImages: one
/// whose station could not be reached asked again).
let chat_images : @sfbase.ChatImages = @sfbase.ChatImages::new()

///|
fn chat_file(station : String, key : String, name : String) -> String {
  let id = @sfbase.file_image_id(station, key, name)
  let params : Map[String, Json] = {
    "station": Json::string(station),
    "key": Json::string(key),
    "name": Json::string(name),
    "thumb": Json::boolean(true),
    "progress": Json::boolean(true),
  }
  // its name at the end: a scripted run finds it by it (`tap img:NAME`)
  chat_images.get(station, id, "mem:chat-file/\{@ui.stable_hash(id)}/\{id.length()}/\{name}", fn(heard, done) {
    @core.stream_bytes("station.file", params=Json::object(params), on_value=fn(v, _) { heard(v) }, on_done=done)
    |> ignore
  })
}

///|
/// A video of a chat's still as its station makes it (`station.poster`): its key once here, "" while it comes, "!"
/// when there is none (the station could not make one, or is from before posters).
fn chat_poster(station : String, key : String, name : String) -> String {
  let id = @sfbase.poster_image_id(station, key, name)
  let params : Map[String, Json] = {
    "station": Json::string(station),
    "key": Json::string(key),
    "name": Json::string(name),
  }
  chat_images.get(station, id, "mem:chat-poster/\{@ui.stable_hash(id)}/\{id.length()}/\{name}", fn(_, done) {
    @core.call_bytes("station.poster", params=Json::object(params), on_done=done)
  })
}

///|
/// A draft's picture the page holds no bytes of, as the device keeps it (`composer.picture`): its key once here, ""
/// while it comes, "!" when none is kept.
fn draft_picture(key : String, id : String) -> String {
  let at = "draft\u{1}" + key + "\u{1}" + id
  let params : Map[String, Json] = { "key": Json::string(key), "id": Json::string(id) }
  chat_images.get("", at, "mem:draft-picture/\{@ui.stable_hash(at)}/\{at.length()}", fn(_, done) {
    @core.call_bytes("composer.picture", params=Json::object(params), on_done=done)
  })
}

///|
/// MBUI_READONLY=1: nothing the reader does is told to the core (no read marks, no place kept, nothing sent, no draft
/// kept, no file put up), for runs on a real account that must change nothing in it.
let read_only : Bool = @ui.env("MBUI_READONLY") == "1"

///|
/// What a read-only run may still ask of the core: reads, and the prefs this device keeps (the workspace in view, the
/// list's filter) and the faces' files it keeps for them. Anything else (sending, drafts kept, files put up, read marks, places, archiving…) is refused here,
/// whatever page asks it.
let read_only_calls : Array[String] = [
  "chat.older", "chat.newer", "chat.latest", "draft.get", "station.file", "station.file.part", "station.poster", "composer.picture",
  "picture", "prefs.set", "drive.read", "drive.folders", "drive.refresh", "fonts.fetch", "fonts.file",
  "fonts.keep", "fonts.preview",
]

///|
fn refused(name : String) -> Json {
  @hostapi.log("MBUI_READONLY: not calling " + name)
  {
    "code": "read_only",
    "message": "只读运行：不发送，不上传，不保存草稿（" + name + "）",
  }
}

///|
let core_source : @sfapp.Source = {
  topic: core_topic,
  waits: fn(name, params) { @core.subscribe(name, params~).followed().waiting },
  call: fn(name, params, done) {
    if read_only && !read_only_calls.contains(name) {
      done(Err(refused(name)))
      return
    }
    // a remote screen's frame acknowledged straight to its station, where the engine's shell reads its view itself:
    // nothing through the core (sfpages' screen_ack says the view's call)
    if name == "screen.ack" {
      let view_call = @sfapp.number(Some(params), "call")
      if view_call > 0.0 && @core.screen_ack(view_call.to_int(), @sfapp.number(Some(params), "ts")) {
        done(Ok(Json::null()))
        return
      }
    }
    if call_log {
      @hostapi.log("CALL \{name} \{logged(name, params)}")
    }
    @core.call(name, params~, on_done=fn(r) {
      if call_log {
        match r {
          Ok(v) => @hostapi.log("ANSWER \{name} ok \{logged(name, v)}")
          Err(e) => @hostapi.log("ANSWER \{name} error \{e.stringify()}")
        }
      }
      done(r)
    })
  },
  call_bytes: fn(name, params, bytes, done) {
    if read_only {
      done(Err(refused(name)))
      return
    }
    if call_log {
      @hostapi.log("CALL \{name} \{logged(name, params)} with \{bytes.length()} bytes")
    }
    @core.call(name, params~, bytes=Some(bytes), on_done=fn(r) {
      if call_log {
        match r {
          Ok(v) => @hostapi.log("ANSWER \{name} ok \{logged(name, v)}")
          Err(e) => @hostapi.log("ANSWER \{name} error \{e.stringify()}")
        }
      }
      done(r)
    })
  },
  read_bytes: fn(name, params, done) {
    if read_only && !read_only_calls.contains(name) {
      done(Err(refused(name)))
      return
    }
    if call_log {
      @hostapi.log("CALL \{name} \{logged(name, params)}")
    }
    @core.call_bytes(name, params~, on_done=fn(r) {
      match r {
        Ok((v, bytes)) => {
          if call_log {
            @hostapi.log("ANSWER \{name} ok \{logged(name, v)} with \{bytes.map(fn(b) { b.length() }).unwrap_or(0)} bytes")
          }
          done(Ok((v, bytes.unwrap_or(Bytes::new(0)))))
        }
        Err(e) => {
          if call_log {
            @hostapi.log("ANSWER \{name} error \{e.stringify()}")
          }
          done(Err(e))
        }
      }
    })
  },
  read_going: fn(name, params, on_value, done) {
    if read_only && !read_only_calls.contains(name) {
      done(Err(refused(name)))
      return
    }
    if call_log {
      @hostapi.log("CALL \{name} \{logged(name, params)}")
    }
    @core.stream_bytes(name, params~, on_value=fn(v, _) { on_value(v) }, on_done=fn(r) {
      match r {
        Ok((v, bytes)) => {
          if call_log {
            @hostapi.log("ANSWER \{name} ok \{logged(name, v)} with \{bytes.map(fn(b) { b.length() }).unwrap_or(0)} bytes")
          }
          done(Ok((v, bytes.unwrap_or(Bytes::new(0)))))
        }
        Err(e) => {
          if call_log {
            @hostapi.log("ANSWER \{name} error \{e.stringify()}")
          }
          done(Err(e))
        }
      }
    })
    |> ignore
  },
  stream: fn(name, params, bytes, on_value, done) {
    // a read-only run reads a service's pages, never sends it anything to act on
    if read_only && !(name == "station.preview" && @sfapp.text(Some(params), "method") == "GET") {
      done(Err(refused(name)))
      return 0
    }
    if call_log {
      @hostapi.log("CALL \{name} \{logged(name, params)}")
    }
    @core.stream(name, params~, bytes~, on_value=fn(v, b) {
      on_value(v, b)
    }, on_done=fn(r) {
      if call_log {
        match r {
          Ok(_) => @hostapi.log("ANSWER \{name} ok")
          Err(e) => @hostapi.log("ANSWER \{name} error \{e.stringify()}")
        }
      }
      done(r)
    })
  },
  cancel: fn(id) { @core.cancel(id) },
  sign_in: fn() { @sfcore.sign_in() },
  signing_in: fn() { @sfcore.sign_in_now().busy },
  sign_in_step: fn() {
    let s = @sfcore.sign_in_now()
    @sfbase.SignInStep::of(busy=s.busy, verifying=s.verifying, waiting=s.waiting, failed=s.failed)
  },
  picture,
  fatal: fn() { @core.fatal() },
  file: chat_file,
  poster: chat_poster,
  draft_picture,
  images: chat_images,
  now: fn() { @ui.wall_ms() },
  leave: fn(name, params) { @core.unsubscribe(@core.subscribe(name, params~)) },
  read_only,
}

///|
/// Whether `url` is a cloud on this machine: its host, as written, 127.0.0.1 or localhost (not one that only begins so:
/// localhost.example.com, 127.0.0.1.nip.io, a user's part before an @).
fn local_cloud(url : String) -> Bool {
  let rest = if url.has_prefix("http://") {
    url.view(start_offset=7).to_owned()
  } else if url.has_prefix("https://") {
    url.view(start_offset=8).to_owned()
  } else {
    return false
  }
  let mut end = rest.length()
  for ch in ['/', '?', '#'] {
    match rest.find(ch.to_string()) {
      Some(i) if i < end => end = i
      _ => ()
    }
  }
  let authority = rest.view(end_offset=end).to_owned()
  if authority.contains("@") {
    return false
  }
  let host = match authority.rev_find(":") {
    Some(i) => authority.view(end_offset=i).to_owned()
    None => authority
  }
  host == "127.0.0.1" || host == "localhost"
}

///|
// kept across runs: the faces' database, made again when the faces given change (one come)
let svg_fonts : Ref[(Int, @font.FontDb, String)] = Ref((-1, @font.FontDb::new(), ""))

///|
/// An SVG picture drawn at `px` on its longer side, its text set in the app's faces (@sfbase.vector_faces): the app's
/// own words' face for every generic family but monospace, the code face for that.
fn draw_svg(data : Bytes, px : Int) -> (Int, Int, FixedArray[Byte])? {
  let faces = @sfbase.vector_faces(data)
  if svg_fonts.val.0 != faces.length() {
    let db = @font.FontDb::new()
    for f in faces {
      db.load_font_data(f)
    }
    let family = fn(i) {
      match db.faces().get(i) {
        Some(f) if f.families.length() > 0 => f.families[0].0
        _ => ""
      }
    }
    let own = family(0)
    db.set_serif_family(own)
    db.set_sans_serif_family(own)
    db.set_cursive_family(own)
    db.set_fantasy_family(own)
    db.set_monospace_family(family(1))
    svg_fonts.val = (faces.length(), db, own)
  }
  let (_, fonts, own) = svg_fonts.val
  @svg.rasterize(data, px, opt={ ..@svg.Options::default(), fonts, font_family: own })
}

///|
fn main {
  // the app as the system's keyboard (mbui's Keyboard.java, in a process of its own): the keyboard alone
  if @ui.env("MBUI_KEYBOARD") == "1" {
    @keyboard.run()
    return
  }
  // SVG pictures (a chat's .svg files) drawn by mbui's own SVG renderer, whatever the system decodes
  @ui.set_vector_pictures(draw_svg)
  // MBUI_PLATFORM=android: run as a phone's system has it (a test's trace recorded again on a Mac on the system its
  // Tester plays: scripts/rerecord.sh), and pointed at by a finger as a phone is; MBUI_POINTING=finger or mouse: pointed
  // at so, whatever the system
  match @ui.env("MBUI_PLATFORM") {
    "android" => @ui.set_platform(Some(2))
    "ios" => @ui.set_platform(Some(1))
    "mac" => @ui.set_platform(Some(0))
    "windows" => @ui.set_platform(Some(3))
    _ => ()
  }
  match @ui.env("MBUI_POINTING") {
    "finger" => @ui.set_pointing(Some(Finger))
    "mouse" => @ui.set_pointing(Some(Mouse))
    _ => ()
  }
  // MBUI_CORE_TRACE=1: the app's conversation with its core kept on the log (CORETRACE …), for a Tester to give
  // again (src/core/replay.mbt). Only on a local cloud (MBUI_CLOUD on this machine: its made-up account): what a real
  // account's core says (its tokens, a vault's values) is never put on a log.
  let cloud = @ui.env("MBUI_CLOUD")
  if @ui.env("MBUI_CORE_TRACE") == "1" && local_cloud(cloud) {
    // (bytes over MBUI_CORE_TRACE_BYTES, scripts/trace make's MAX_BYTES, kept as their length alone)
    let bytes_max = @string.parse_int(@ui.env("MBUI_CORE_TRACE_BYTES")[:]) catch { _ => 16384 }
    @core.trace_to(fn(line) { @hostapi.log("CORETRACE " + line) }, bytes_max~)
    // first, what the app was started with (sfcore.begin reads it: the local cloud, its made-up account, what is asked
    // of signing in), for a replay's app to be started the same (src/sfreplay: Flow::start)
    let started : Map[String, Json] = {}
    // (and where the host keeps downloads in a scripted run: what it says of a file kept, which the app tells the core)
    for name in @sfcore.started_by + ["MBUI_DOWNLOADS_DIR"] {
      let v = @sfcore.env_text(name)
      if v != "" {
        started[name] = Json::string(v)
      }
    }
    @hostapi.log("CORETRACE " + Json::object({ "env": Json::object(started) }).stringify())
    // and which station this machine is, as its host says it (@ui.local_station: what the files' page lists first), for
    // a replay's host to say the same
    let local = @json.parse(@ui.local_station()) catch { _ => Json::null() }
    @hostapi.log("CORETRACE " + ({ "host": { "localStation": local } } : Json).stringify())
    // and what the host said of its views (a video's frames' times, a frame grabbed), at the core's clock, beside it
    @ui.trace_views(fn(m) { @core.trace_note(m) })
    // and each line of a scripted run's script as it began (`{"step":…}`), and a line that acts again as its input
    // went to the host (`"acted":true`), at the same clock: when the run took each step and when it acted, for a replay
    // to take it when the run did (src/core/replay.mbt: Replay::step_at)
    @ui.trace_steps(fn(step, moment) {
      let m : Map[String, Json] = { "step": Json::string(step) }
      if moment == @ui.Acted {
        m["acted"] = Json::boolean(true)
      }
      @core.trace_note(m)
    })
  }
  // (a remote screen's frames and sound, and its acknowledgements' answers, change nothing a frame reads: taken as they
  // come, they build nothing, sfpages' screen.mbt)
  @core.quiet("screen.view", @sfpages.screen_value_quiet)
  for name in @sfpages.screen_unread_calls() {
    @core.unread(name)
  }
  if core_linked() == 0 || !@sfcore.start() {
    @sfapp.host_setup()
    @ui.run("still.fail", fn(c) {
      @sf.begin(c) |> ignore
      c.box(w=Fill(1.0), h=Fill(1.0), align=ACenter, justify=JCenter, fn() {
        c.text("这个版本没有链接内核（APP=stillfail scripts/mac.sh build）", size=13.0, color=@sf.theme().p.muted)
        |> ignore
      })
      |> ignore
    })
    return
  }
  // a window of its own (sfbase's window.mbt, MBUI_WINDOW: started by the app's run beside it, @ui.window_open): the
  // page it was started for alone, none of what follows (the app's run beside it has them)
  @sfbase.lone_page.val = @sfbase.window_page(@ui.env("MBUI_WINDOW"))
  if @sfbase.lone_page.val is None {
    // scripted runs: a chat opened by words in its title once Home lists it (MBUI_OPEN_CHAT), or by its station and
    // session at once (MBUI_OPEN_SESSION=<workspace>/<station>|<session>)
    @sfapp.open_titled.val = @ui.env("MBUI_OPEN_CHAT")
    match @ui.env("MBUI_OPEN_SESSION").split("|").map(fn(v) { v.to_string() }).to_array() {
      [station, session] =>
        @sfapp.open_chat({ station, session, title: "", station_name: "" })
      _ => ()
    }
    // MBUI_OPEN_PAGE=files: 文件 pushed over Home (scripted runs; the bottom bar's place until there is one)
    if @ui.env("MBUI_OPEN_PAGE") == "files" {
      @sfapp.open_page(Files)
    }
    // where newer builds of the app come from (src/sfapp/updates.mbt): still.fail cloud's feed MBUI_UPDATE_FEED (the
    // local cloud's in e2e); none by default, as this build ships apart from still.fail's own (its release elsewhere).
    // youdid.wtf's core (MBUI_BETA=1, still.fail's own: MBUI_OWN=1) asks the feed's beta, <feed>/beta, itself: its feed
    // is android, not android/beta (which asked android/beta/beta, a 404); an app of its own on the test channel
    // (still.fail mbui's: MBUI_BETA=1 alone) asks its feed as named (android/mbui)
    match @ui.env("MBUI_UPDATE_FEED") {
      "" => ()
      feed => {
        let origin = match @ui.env("MBUI_CLOUD") {
          "" => "https://app.still.fail"
          o => o
        }
        @sfapp.set_update_source(Some(@sfapp.cloud_updates(core_source, feed, origin)))
      }
    }
    // built in still.fail's desktop app's place: the station that app ran here carried on (sfbase local_station.mbt)
    @sfbase.local_station_carry_on()
  }
  // crash reports and the bar's timing, where the host has them (reports.mbt: Android)
  reports_start()
  @sfapp.use_core_markdown(core_source)
  // the faces the app carries (code's JetBrains Mono, as Android's): before its first frame
  @sf.give_faces()
  @sfapp.host_setup()
  // (said with each summary of the frames into the device's performance record while it is kept: the core's
  // messages, the page shown, the screens open; @ui.perf_also)
  @ui.perf_also("core", @core.perf_said)
  @ui.perf_also("page", fn(_) { @sfbase.page_kind(@sfbase.app.nav.top()) })
  @ui.perf_also("screens", @sfpages.screens_perf)
  @ui.run(
    "still.fail",
    fn(c) {
      // (what the core said since the last frame is handed to @core.receive as the frame begins, before this:
      // sfcore.start)
      let accounts = @core.subscribe("accounts")
      @sfcore.frame(accounts)
      report_signed_in(c, accounts)
      @sfapp.view(c, core_source)
    },
    tree=@sfapp.app_tree(core_source),
  )
}
