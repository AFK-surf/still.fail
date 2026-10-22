// The app over a kept conversation with its core (src/core/replay.mbt), for tests: the app's pages (src/sfapp) as
// src/stillfail shows them, over @core, with the core a run's trace given again. A scripted run against a live
// backend keeps the trace (MBUI_CORE_TRACE=1, e2e/run.sh: CORETRACE lines on the flow's log); `scripts/trace make`
// makes it a test's (e2e/traces, src/sfreplay/trace_*.mbt), and the test sees the run again frame by frame (flow.mbt),
// the same every time, no backend, no wall clock.

///|
/// Pictures and chats' images as the core gives them (`picture`, `station.file`), asked once each.
let images : Map[String, String] = {}

///|
/// Asked again in every Tester (mbui's on_reset): the pictures it had are gone from its images.
fn init {
  @ui.on_reset(fn() { images.clear() })
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
    call: fn(name, params, done) { @core.call(name, params~, on_done=done) },
    call_bytes: fn(name, params, bytes, done) {
      @core.call(name, params~, bytes=Some(bytes), on_done=done)
    },
    read_bytes: fn(name, params, done) {
      @core.call_bytes(name, params~, on_done=fn(r) {
        done(r.map(fn(a) { (a.0, a.1.unwrap_or(Bytes::new(0))) }))
      })
    },
    stream: fn(name, params, bytes, on_value, done) {
      @core.stream(name, params~, bytes~, on_value~, on_done=done)
    },
    cancel: fn(id) { @core.cancel(id) },
    sign_in: fn() { @sfcore.sign_in() },
    signing_in: fn() { @sfcore.state.busy },
    picture: fn(url) {
      image("picture", Json::object({ "url": Json::string(url) }), "picture " + url, "mem:picture/\{@ui.stable_hash(url)}/\{url.length()}")
    },
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
    @sfcore.begin()
  }
  @sfcore.frame(@core.subscribe("accounts"))
  @sfapp.view(c, the_source)
}
