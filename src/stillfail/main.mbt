// still.fail in mbui (docs/stillfail-port.md): the core started (src/sfcore), signed out its sign-in page, signed in
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
  let s = @core.subscribe(name, params~)
  if dump {
    let key = name + " " + Json::object(params).stringify()
    if dumped.get(key) != Some(s.version) {
      dumped[key] = s.version
      match (s.value, s.error) {
        (Some(v), _) => @host.log("DUMP \{key} \{v.stringify()}")
        (_, Some(e)) => @host.log("DUMP \{key} error \{e.stringify()}")
        _ => ()
      }
    }
  }
  { value: s.value, error: s.error, version: s.version }
}

///|
let dump : Bool = @host.env("MBUI_CORE_DUMP") == "1"

///|
/// MBUI_CALL_LOG=1: every call the app makes, and its answer, on the log (CALL …, ANSWER …), for scripted runs.
let call_log : Bool = @host.env("MBUI_CALL_LOG") == "1"

///|
/// People's pictures as the core gives them (`picture`): asked once each, kept as images.
let pictures : Map[String, String] = {}

///|
fn picture(url : String) -> String {
  match pictures.get(url) {
    Some(key) => key
    None => {
      pictures[url] = ""
      let params : Map[String, Json] = { "url": Json::string(url) }
      @core.call_bytes("picture", params=Json::object(params), on_done=fn(r) {
        match r {
          Ok((_, Some(bytes))) if bytes.length() > 0 => {
            let key = "mem:picture/\{url.hash()}/\{url.length()}"
            @ui.add_image(key, bytes)
            pictures[url] = key
            @host.request_frame()
          }
          _ => ()
        }
      })
      ""
    }
  }
}

///|
/// Chats' images as their messages show them (`station.file` with `thumb`: the station's thumbnail where it keeps one),
/// asked once each, kept as images: "" while one comes, "!" when it could not be had.
let chat_files : Map[String, String] = {}

///|
fn chat_file(station : String, key : String, name : String) -> String {
  let id = station + "\u{1}" + key + "\u{1}" + name
  match chat_files.get(id) {
    Some(k) => k
    None => {
      chat_files[id] = ""
      let params : Map[String, Json] = {
        "station": Json::string(station),
        "key": Json::string(key),
        "name": Json::string(name),
        "thumb": Json::boolean(true),
      }
      @core.call_bytes("station.file", params=Json::object(params), on_done=fn(r) {
        match r {
          Ok((_, Some(bytes))) if bytes.length() > 0 => {
            // its name at the end: a scripted run finds it by it (`tap img:NAME`)
            let k = "mem:chat-file/\{id.hash()}/\{id.length()}/\{name}"
            @ui.add_image(k, bytes)
            chat_files[id] = k
          }
          _ => chat_files[id] = "!"
        }
        @host.request_frame()
      })
      ""
    }
  }
}

///|
/// MBUI_READONLY=1: nothing the reader does is told to the core (no read marks, no place kept, nothing sent, no draft
/// kept, no file put up), for runs on a real account that must change nothing in it.
let read_only : Bool = @host.env("MBUI_READONLY") == "1"

///|
/// What a read-only run may still ask of the core: reads, and the prefs this device keeps (the workspace in view, the
/// list's filter). Anything else (sending, drafts kept, files put up, read marks, places, archiving…) is refused here,
/// whatever page asks it.
let read_only_calls : Array[String] = [
  "chat.older", "chat.newer", "chat.latest", "draft.get", "station.file", "station.file.part",
  "picture", "memory.get", "prefs.set", "drive.read", "drive.folders", "drive.refresh",
]

///|
fn refused(name : String) -> Json {
  @host.log("MBUI_READONLY: not calling " + name)
  {
    "code": "read_only",
    "message": "只读运行：不发送，不上传，不保存草稿（" + name + "）",
  }
}

///|
let core_source : @sfapp.Source = {
  topic: core_topic,
  call: fn(name, params, done) {
    if read_only && !read_only_calls.contains(name) {
      done(Err(refused(name)))
      return
    }
    if call_log {
      @host.log("CALL \{name} \{params.stringify()}")
    }
    @core.call(name, params~, on_done=fn(r) {
      if call_log {
        match r {
          Ok(v) => @host.log("ANSWER \{name} ok \{v.stringify()}")
          Err(e) => @host.log("ANSWER \{name} error \{e.stringify()}")
        }
      }
      done(r)
      @host.request_frame()
    })
  },
  call_bytes: fn(name, params, bytes, done) {
    if read_only {
      done(Err(refused(name)))
      return
    }
    if call_log {
      @host.log("CALL \{name} \{params.stringify()} with \{bytes.length()} bytes")
    }
    @core.call(name, params~, bytes=Some(bytes), on_done=fn(r) {
      if call_log {
        match r {
          Ok(v) => @host.log("ANSWER \{name} ok \{v.stringify()}")
          Err(e) => @host.log("ANSWER \{name} error \{e.stringify()}")
        }
      }
      done(r)
      @host.request_frame()
    })
  },
  read_bytes: fn(name, params, done) {
    if read_only && !read_only_calls.contains(name) {
      done(Err(refused(name)))
      return
    }
    if call_log {
      @host.log("CALL \{name} \{params.stringify()}")
    }
    @core.call_bytes(name, params~, on_done=fn(r) {
      match r {
        Ok((v, bytes)) => {
          if call_log {
            @host.log("ANSWER \{name} ok \{v.stringify()} with \{bytes.map(fn(b) { b.length() }).unwrap_or(0)} bytes")
          }
          done(Ok((v, bytes.unwrap_or(Bytes::new(0)))))
        }
        Err(e) => {
          if call_log {
            @host.log("ANSWER \{name} error \{e.stringify()}")
          }
          done(Err(e))
        }
      }
      @host.request_frame()
    })
  },
  stream: fn(name, params, bytes, on_value, done) {
    // a read-only run reads a service's pages, never sends it anything to act on
    if read_only && !(name == "station.preview" && @sfapp.text(Some(params), "method") == "GET") {
      done(Err(refused(name)))
      return 0
    }
    if call_log {
      @host.log("CALL \{name} \{params.stringify()}")
    }
    @core.stream(name, params~, bytes~, on_value=fn(v, b) {
      on_value(v, b)
      @host.request_frame()
    }, on_done=fn(r) {
      if call_log {
        match r {
          Ok(_) => @host.log("ANSWER \{name} ok")
          Err(e) => @host.log("ANSWER \{name} error \{e.stringify()}")
        }
      }
      done(r)
      @host.request_frame()
    })
  },
  cancel: fn(id) { @core.cancel(id) },
  sign_in: fn() { @sfcore.sign_in() },
  signing_in: fn() { @sfcore.state.busy },
  picture,
  fatal: fn() { @core.fatal() },
  file: chat_file,
  now: fn() { @core.wall_ms() },
  leave: fn(name, params) { @core.unsubscribe(@core.subscribe(name, params~)) },
  read_only,
}

///|
fn main {
  if core_linked() == 0 || !@sfcore.start() {
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
  // scripted runs: a chat opened by words in its title once Home lists it (MBUI_OPEN_CHAT), or by its station and
  // session at once (MBUI_OPEN_SESSION=<workspace>/<station>|<session>)
  @sfapp.open_titled.val = @host.env("MBUI_OPEN_CHAT")
  match @host.env("MBUI_OPEN_SESSION").split("|").map(fn(v) { v.to_string() }).to_array() {
    [station, session] =>
      @sfapp.open_chat({ station, session, title: "", station_name: "" })
    _ => ()
  }
  // MBUI_OPEN_PAGE=files: 文件 pushed over Home (scripted runs; the bottom bar's place until there is one)
  if @host.env("MBUI_OPEN_PAGE") == "files" {
    @sfapp.open_page(Files)
  }
  // MBUI_OPEN_PAGE=decisions: the 奏 page over Home from the start (its way in is the bottom bar's)
  if @host.env("MBUI_OPEN_PAGE") == "decisions" {
    @sfapp.open_decisions()
  }
  @ui.run("still.fail", fn(c) {
    @sfcore.frame(@core.subscribe("accounts"))
    @sfapp.view(c, core_source)
  })
}
