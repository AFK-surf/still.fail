// The app over a kept conversation with its core (src/core/replay.mbt), for tests: the app's pages (src/sfapp) as
// src/stillfail shows them, over @core, with the core a run's trace given again. A scripted run against a live
// backend keeps the trace (MBUI_CORE_TRACE=1, e2e/run.sh: CORETRACE lines on the flow's log); `scripts/trace make`
// makes it a test's (e2e/traces, src/sfreplay/trace_*.mbt), and the test sees the run again frame by frame (flow.mbt),
// the same every time, no backend, no wall clock.

///|
/// Chats' images as the core gives them (`station.file`, `station.poster`): one whose station could not be reached
/// asked again (@sfbase.ChatImages).
let images : @sfbase.ChatImages = @sfbase.ChatImages::new()

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
/// with the run's text (a picture's sizes, by its source) are the same here. `going`: how far it has come said as it
/// comes (a chat's file's, as src/stillfail asks it).
fn image(station : String, id : String, call : String, params : Json, name : String, going? : Bool = false) -> String {
  images.get(station, id, name, fn(heard, done) {
    if going {
      @core.stream_bytes(call, params~, on_value=fn(v, _) { heard(v) }, on_done=done) |> ignore
    } else {
      @core.call_bytes(call, params~, on_done=done)
    }
  })
}

///|
/// The prefs of a tape from a core before the rail was the core's (prefs `railView`, core-ts rail.ts): the rail as the
/// real core draws it from what those prefs keep (`rail`, `rails`), kept (src/sfkept), a pure function of them.
fn with_rail_view(v : Json?) -> Json? {
  match v {
    Some(Object(m)) if !m.contains("railView") => {
      let kept : Map[String, Json] = {}
      for k in ["rail", "rails"] {
        match m.get(k) {
          Some(x) => kept[k] = x
          None => ()
        }
      }
      match @sfkept.answer("railView", Json::object(kept), None) {
        Some(Ok((rail, _))) => {
          let out = m.copy()
          out["railView"] = rail
          Some(Json::object(out))
        }
        _ => v
      }
    }
    _ => v
  }
}

///|
/// Older runs used one full jobs subscription for both the bar and the sheet. New runs keep each separately.
// kept across runs: Flow::start says which the next recording has before its first frame
let legacy_chat_jobs : Ref[Bool] = Ref(false)

///|
/// Match the jobs read by the replay to what this recording's core could say.
pub fn use_recorded_jobs(r : @core.Replay) -> Unit {
  legacy_chat_jobs.val = !r.has_jobs_summary()
}

///|
fn replay_topic_params(name : String, params : Map[String, Json]) -> Map[String, Json] {
  let out = @sfbase.core_topic_params(name, params)
  if name == "chatJobs" && legacy_chat_jobs.val {
    out.remove("summary")
  }
  out
}

///|
/// The app's source over @core, as src/stillfail's (without its logs and its read-only runs).
pub fn source() -> @sfapp.Source {
  {
    topic: fn(name, params) {
      let s = @core.subscribe(name, params=replay_topic_params(name, params)).followed()
      let value = if name == "prefs" { with_rail_view(s.value) } else { s.value }
      { value, error: s.error, version: s.version }
    },
    waits: fn(name, params) { @core.subscribe(name, params=replay_topic_params(name, params)).followed().waiting },
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
        Some(Ok((v, _))) => {
          // (the tape told it was asked, its answer to it let go: the run's ask of it, if the run asked, is had)
          @core.call(name, params~, on_done=fn(_) {  })
          // (answered at once, as the core's answer comes from outside: what it changes of what is no signal taken so)
          @ui.came_from_outside()
          done(Ok(v))
        }
        // (one always answered here, not kept yet: said on the output for scripts/kept, never the run's to give)
        Some(Err(e)) if @sfkept.has(name, params) => done(Err(e))
        _ => @core.call(name, params~, on_done=done)
      }
    },
    call_bytes: fn(name, params, bytes, done) {
      match @sfkept.answer(name, params, Some(bytes)) {
        Some(Ok((v, _))) => {
          @ui.came_from_outside()
          done(Ok(v))
        }
        _ => @core.call(name, params~, bytes=Some(bytes), on_done=done)
      }
    },
    read_bytes: fn(name, params, done) {
      match @sfkept.answer(name, params, None) {
        Some(Ok((v, b))) => {
          @ui.came_from_outside()
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
    signing_in: fn() { @sfcore.sign_in_now().busy },
    sign_in_step: fn() {
      let s = @sfcore.sign_in_now()
      @sfbase.SignInStep::of(busy=s.busy, verifying=s.verifying, waiting=s.waiting, failed=s.failed)
    },
    picture: fn(url, stint) { picture(url, stint) },
    fatal: fn() { @core.fatal() },
    file: fn(station, key, name) {
      let params : Map[String, Json] = {
        "station": Json::string(station),
        "key": Json::string(key),
        "name": Json::string(name),
        "thumb": Json::boolean(true),
        "progress": Json::boolean(true),
      }
      let id = @sfbase.file_image_id(station, key, name)
      image(station, id, "station.file", Json::object(params), "mem:chat-file/\{@ui.stable_hash(id)}/\{id.length()}/\{name}", going=true)
    },
    poster: fn(station, key, name) {
      let params : Map[String, Json] = {
        "station": Json::string(station),
        "key": Json::string(key),
        "name": Json::string(name),
      }
      let id = @sfbase.poster_image_id(station, key, name)
      image(station, id, "station.poster", Json::object(params), "mem:chat-poster/\{@ui.stable_hash(id)}/\{id.length()}/\{name}")
    },
    draft_picture: fn(key, id) {
      let params : Map[String, Json] = { "key": Json::string(key), "id": Json::string(id) }
      let at = "draft\u{1}" + key + "\u{1}" + id
      image("", at, "composer.picture", Json::object(params), "mem:draft-picture/\{@ui.stable_hash(at)}/\{at.length()}")
    },
    images,
    now: fn() { @ui.wall_ms() },
    leave: fn(name, params) { @core.unsubscribe_topic(name, params=replay_topic_params(name, params)) },
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
