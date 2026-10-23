// The app over a kept conversation with its core (src/core/replay.mbt), for tests: the app's pages (src/sfapp) as
// src/stillfail shows them, over @core, with the core a run's trace given again. A scripted run against a live
// backend keeps the trace (MBUI_CORE_TRACE=1, e2e/run.sh: CORETRACE lines on the flow's log); `scripts/trace make`
// makes it a test's (e2e/traces, src/sfreplay/trace_*.mbt), and the test sees the run again frame by frame (flow.mbt),
// the same every time, no backend, no wall clock.

///|
/// Chats' images as the core gives them (`station.file`), asked once each.
let images : Map[String, String] = {}

///|
/// Pictures by their address as the app's own are (src/stillfail: @sfapp.core_pictures, one that could not be had
/// asked again when its page is put up anew), so a run that asked again is asked again here; made anew in each
/// Tester.
let pictures : Ref[((String, Int) -> String)?] = Ref(None)

///|
fn picture(url : String, stint : Int) -> String {
  let f = match pictures.val {
    Some(f) => f
    None => {
      let f = @sfapp.core_pictures(fn(url, done) {
        @core.call_bytes("picture", params=Json::object({ "url": Json::string(url) }), on_done=fn(r) {
          match r {
            Ok((_, bytes)) => done(bytes)
            Err(_) => done(None)
          }
        })
      })
      pictures.val = Some(f)
      f
    }
  }
  f(url, stint)
}

///|
/// Asked again in every Tester (mbui's on_reset): the pictures it had are gone from its images.
fn init {
  @ui.on_reset(fn() {
    images.clear()
    pictures.val = None
  })
}

///|
/// `name`: the image's as src/stillfail names it (its key), so a scripted run's `img:NAME` and the host's answers kept
/// with the run's text (a picture's sizes, by its source) are the same here.
fn image(call : String, params : Json, key : String, name : String) -> String {
  match images.get(key) {
    Some(k) => k
    None => {
      images[key] = ""
      @core.call_bytes(call, params~, on_done=fn(r) {
        match r {
          Ok((_, Some(bytes))) if bytes.length() > 0 => {
            @ui.add_image(name, bytes)
            images[key] = name
          }
          _ => images[key] = "!"
        }
      })
      ""
    }
  }
}

///|
/// The app's source over @core, as src/stillfail's (without its logs and its read-only runs).
pub fn source() -> @sfapp.Source {
  {
    topic: fn(name, params) {
      let s = @core.subscribe(name, params~)
      { value: s.value, error: s.error, version: s.version }
    },
    // The core's pure calls (`markdown`, `code.ink`, `reader.*`) answered as the real core answered them, kept
    // (src/sfkept): tapes older than a call have none of it, and it is a pure function of what is asked, not made up
    // here. Any other ask the tape does not have still diverges; ⌘K's `commands.find` is the tape's (it says it in the
    // run's language, which only the run knows).
    call: fn(name, params, done) {
      if name == "commands.find" {
        @core.call(name, params~, on_done=done)
        return
      }
      match @sfkept.answer(name, params, None) {
        Some(Ok((v, _))) => done(Ok(v))
        _ => @core.call(name, params~, on_done=done)
      }
    },
    call_bytes: fn(name, params, bytes, done) {
      match @sfkept.answer(name, params, Some(bytes)) {
        Some(Ok((v, _))) => done(Ok(v))
        _ => @core.call(name, params~, bytes=Some(bytes), on_done=done)
      }
    },
    read_bytes: fn(name, params, done) {
      match @sfkept.answer(name, params, None) {
        Some(Ok((v, b))) => {
          done(Ok((v, b.unwrap_or(Bytes::new(0)))))
          return
        }
        _ => ()
      }
      @core.call_bytes(name, params~, on_done=fn(r) {
        done(r.map(fn(a) { (a.0, a.1.unwrap_or(Bytes::new(0))) }))
      })
    },
    read_going: fn(name, params, on_value, done) {
      @core.stream_bytes(name, params~, on_value=fn(v, _) { on_value(v) }, on_done=fn(r) {
        done(r.map(fn(a) { (a.0, a.1.unwrap_or(Bytes::new(0))) }))
      })
      |> ignore
    },
    stream: fn(name, params, bytes, on_value, done) {
      @core.stream(name, params~, bytes~, on_value~, on_done=done)
    },
    cancel: fn(id) { @core.cancel(id) },
    sign_in: fn() { @sfcore.sign_in() },
    signing_in: fn() { @sfcore.state.busy },
    picture: fn(url, stint) { picture(url, stint) },
    fatal: fn() { @core.fatal() },
    file: fn(station, key, name) {
      let params : Map[String, Json] = {
        "station": Json::string(station),
        "key": Json::string(key),
        "name": Json::string(name),
        "thumb": Json::boolean(true),
      }
      let id = station + "\u{1}" + key + "\u{1}" + name
      image("station.file", Json::object(params), "file " + id, "mem:chat-file/\{@ui.stable_hash(id)}/\{id.length()}/\{name}")
    },
    poster: fn(station, key, name) {
      let params : Map[String, Json] = {
        "station": Json::string(station),
        "key": Json::string(key),
        "name": Json::string(name),
      }
      let id = station + "\u{1}" + key + "\u{1}" + name + "\u{1}poster"
      image("station.poster", Json::object(params), "poster " + id, "mem:chat-poster/\{@ui.stable_hash(id)}/\{id.length()}/\{name}")
    },
    now: fn() { @ui.wall_ms() },
    leave: fn(name, params) { @core.unsubscribe(@core.subscribe(name, params~)) },
    read_only: false,
  }
}

///|
let the_source : @sfapp.Source = source()

///|
/// Whether this Tester's app has been started (sfcore.begin), as src/stillfail's is before its first frame.
let started : Ref[Bool] = Ref::new(false)

///|
fn init {
  @ui.on_reset(fn() { started.val = false })
}

///|
/// The app as src/stillfail draws it, over `source()`: a Tester's view. Started as src/stillfail's is (sfcore.begin:
/// the device told, what its environment (the run's, Flow::start) asks of signing in) as its first frame begins,
/// before anything it asks.
pub fn app(c : @ui.Ctx) -> Unit {
  if !started.val {
    started.val = true
    @sfapp.use_core_markdown(the_source)
    @sfcore.begin()
  }
  @sfcore.frame(@core.subscribe("accounts"))
  @sfapp.view(c, the_source)
}
