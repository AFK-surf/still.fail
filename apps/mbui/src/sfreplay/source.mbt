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
/// Whether this Tester's run asked the stations whole (its trace's head without MBUI_STATION_ROWS): its replay keeps the
/// run's `stations` itself (@core.Replay::keep_stations, Flow::start) and gives the app's `stations {scope}` the whole
/// stations it has, out of which the app's asks of them are read here (stations_made), as the core makes them.
fn stations_whole() -> Bool {
  !@sfcore.trace_switch("MBUI_STATION_ROWS")
}

///|
/// The app's topics read out of a scope's stations whole in such a run: the rows, one station, a part of one.
fn of_stations(name : String) -> Bool {
  name == "stations" || name == "station" || name == "stationPart"
}

///|
/// The app's topics the core works a field of out of the stations (`connects`' Slack apps and `noProfile`, `profiles`'
/// machine logins), which such a run's core had not: the run's value with it added.
fn with_stations(name : String) -> Bool {
  name == "connects" || name == "profiles"
}

///|
/// The stations followed for topic `name` with `params` (of_stations, with_stations): `stations {scope}`.
fn stations_params(params : Map[String, Json]) -> Map[String, Json] {
  match params.get("scope") {
    Some(s) => { "scope": s }
    None => {}
  }
}

///|
/// Who holds a scope's stations without a graph (a read outside one: the client's `manual` hold, @core's Sub), by the
/// app's topic (its wire key): let go of once the last of them leaves, as several of the app's topics are read out of
/// one followed `stations` (a graph's readers are counted by the client itself, by its signal's watchers).
// kept across runs: emptied as a Tester begins (on_reset)
let stations_holders : Map[String, Map[String, Bool]] = {}

///|
/// A scope's stations followed for the app's topic `name` with `params` (a hold of it counted, stations_holders).
fn follow_stations(name : String, params : Map[String, Json]) -> @core.Sub {
  let p = stations_params(params)
  if @signals.active_sub() is None {
    let scope = @sfbase.wire_topic_key("stations", p)
    let held = match stations_holders.get(scope) {
      Some(h) => h
      None => {
        let h : Map[String, Bool] = {}
        stations_holders[scope] = h
        h
      }
    }
    held[@sfbase.wire_topic_key(name, params)] = true
  }
  @core.follow_topic("stations", params=p)
}

///|
/// The app's topic `name` with `params`, held outside a graph, left: its scope's stations left once none holds them so.
fn leave_stations(name : String, params : Map[String, Json]) -> Unit {
  let p = stations_params(params)
  let scope = @sfbase.wire_topic_key("stations", p)
  match stations_holders.get(scope) {
    Some(held) => {
      held.remove(@sfbase.wire_topic_key(name, params))
      if held.is_empty() {
        stations_holders.remove(scope)
        @core.leave_topic("stations", params=p)
      }
    }
    None => @core.leave_topic("stations", params=p)
  }
}

///|
/// A value read out of the stations (stations_made): what it was made of (the stations, the run's own topic), and it.
priv struct Made {
  stations : Json?
  own : Json?
  topic : @sfapp.Topic
}

///|
/// Each made value by the app's topic (its wire key): made again only when what it is made of is another value, so a
/// page reading it each frame gets the same object while nothing changed (its version too).
// kept across runs: emptied as a Tester begins (on_reset)
let made : Map[String, Made] = {}

///|
/// The versions given made values: one more for each made anew, so none is given twice.
// kept across runs: only counted on
let made_count : Ref[Int] = Ref(0)

///|
fn same_json(a : Json?, b : Json?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(x), Some(y)) => physical_equal(x, y)
    _ => false
  }
}

///|
/// The app's topic `name` with `params` as the core makes it of the scope's stations whole (`stations`, in such a run)
/// and, for with_stations, of the run's own value (`own`): the settings' fixture_stations.mbt, as the made-up cores do.
fn stations_made(name : String, params : Map[String, Json], stations : @core.Sub, own : @core.Sub?) -> @sfapp.Topic {
  let key = @sfbase.wire_topic_key(name, params)
  let own_value = match own {
    Some(s) => s.value
    None => None
  }
  match made.get(key) {
    Some(m) if same_json(m.stations, stations.value) && same_json(m.own, own_value) => {
      let error = match own {
        Some(s) => s.error
        None => stations.error
      }
      return { ..m.topic, error }
    }
    _ => ()
  }
  let p = Some(Json::object(params))
  let value = match name {
    "stations" =>
      match stations.value {
        Some(Array(a)) => Some(Json::array(a.map(@settings.station_row)))
        v => v
      }
    "station" => @settings.station_said(stations.value, @settings.text(p, "station"), "")
    "stationPart" => @settings.station_said(stations.value, @settings.text(p, "station"), @settings.text(p, "part"))
    "connects" =>
      match own_value {
        Some(Object(o)) if !o.contains("slackApps") => @settings.connects_of_stations(own_value, stations.value)
        v => v
      }
    "profiles" =>
      match own_value {
        Some(Object(o)) if !o.contains("machineLogins") => @settings.profiles_of_stations(own_value, stations.value)
        v => v
      }
    _ => None
  }
  let error = match own {
    Some(s) => s.error
    None => stations.error
  }
  let version = if value is None {
    0
  } else {
    made_count.val += 1
    made_count.val
  }
  let topic : @sfapp.Topic = { value, error, version }
  made[key] = { stations: stations.value, own: own_value, topic }
  topic
}

///|
fn init {
  @ui.on_reset(fn() {
    stations_holders.clear()
    made.clear()
  })
}

///|
/// The app's source over @core, as src/stillfail's (without its logs and its read-only runs).
pub fn source() -> @sfapp.Source {
  {
    topic_read: fn(name, params) {
      if stations_whole() && of_stations(name) {
        return stations_made(name, params, follow_stations(name, params), None)
      }
      let s = @core.follow_topic(name, params=replay_topic_params(name, params))
      if stations_whole() && with_stations(name) {
        return stations_made(name, params, follow_stations(name, params), Some(s))
      }
      let value = if name == "prefs" { with_rail_view(s.value) } else { s.value }
      { value, error: s.error, version: s.version }
    },
    topic_key: fn(name, params) { @sfbase.wire_topic_key(name, replay_topic_params(name, params)) },
    topic_scope: None,
    topic_alive: fn() { true },
    topic_lease_own: None,
    waits: fn(name, params) {
      if stations_whole() && of_stations(name) {
        follow_stations(name, params).waiting
      } else {
        @core.follow_topic(name, params=replay_topic_params(name, params)).waiting
      }
    },
    generation: fn(name, params) {
      if stations_whole() && of_stations(name) {
        @core.client.topic_generation("stations", params=stations_params(params))
      } else {
        @core.client.topic_generation(name, params=replay_topic_params(name, params))
      }
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
    leave: fn(name, params, __reason) {
      if __reason is @sfbase.TopicLeave::Owned(__stop) { __stop(); return }
      if stations_whole() && (of_stations(name) || with_stations(name)) {
        leave_stations(name, params)
        if of_stations(name) {
          return
        }
      }
      @core.leave_topic(name, params=replay_topic_params(name, params)) },
    release: fn(name, params) {
      // (a graph's readers of the scope's stations counted by the client: it lets them go once none watches them)
      if stations_whole() && (of_stations(name) || with_stations(name)) {
        @core.release_topic("stations", params=stations_params(params))
        if of_stations(name) {
          return
        }
      }
      @core.release_topic(name, params=replay_topic_params(name, params))
    },
    refresh: fn(name, params) {
      if stations_whole() && of_stations(name) {
        @core.refresh_topic("stations", params=stations_params(params))
      } else {
        @core.refresh_topic(name, params=replay_topic_params(name, params))
      }
    },
    read_only: false,
    // (a run's core is asked what the run asked: as its app did, which says so in its trace's head since it does)
    reads_ahead: fn() { @sfcore.trace_switch("MBUI_PLACES_BAR") },
    asks_devices: fn() { @sfcore.trace_switch("MBUI_DEVICES") },
    asks_outline: fn() { @sfcore.trace_switch("MBUI_OUTLINE") },
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

///|
/// The app's window tree over the kept conversations (sfapp's app_tree over this package's source): what `app` is the
/// old frame around, the one way the app is drawn.
pub fn app_tree(root : @view.View) -> Unit {
  @sfapp.app_tree(the_source)(root)
}
