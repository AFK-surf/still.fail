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
      let kept : Map[String, Json] = Map([])
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
/// Whether this Tester's run asked one connect by the connects whole (its trace's head without MBUI_CONNECT_ROWS): the
/// page of one and its choice of a session read it out of `connects {scope, mine:false}`, whose items had all of it,
/// as the run's app did at the same moments; here they are read out of that (connects_made), as the core makes them.
/// Its rows are the run's items as they are (each whole: what a list reads of a row is there).
fn connects_whole() -> Bool {
  !@sfcore.trace_switch("MBUI_CONNECT_ROWS")
}

///|
/// Whether this Tester's run read one account off the accounts whole (its trace's head without MBUI_PROFILE_ROWS): the
/// list's items were each account whole then, its pages reading theirs out of `profiles {scope}` at the same moments;
/// here the list's rows (@settings.profiles_rows) and the app's `profile` (@settings.profile_said) are read out of that,
/// as the core makes them.
fn profiles_whole() -> Bool {
  !@sfcore.trace_switch("MBUI_PROFILE_ROWS")
}

///|
/// The accounts whole followed for the app's `profile` and `profiles` in such a run: `profiles {scope}`.
fn profiles_params(params : Map[String, Json]) -> Map[String, Json] {
  stations_params(params)
}

///|
/// A scope's accounts whole followed for the app's topic `name` with `params` (follow_whole).
fn follow_profiles(name : String, params : Map[String, Json]) -> @core.Sub {
  follow_whole("profiles", profiles_params(params), name, params)
}

///|
/// The app's `profile` with `params` read out of the run's accounts whole (profiles_whole).
fn profile_made(params : Map[String, Json]) -> @sfapp.Topic {
  made_once("profile", params, follow_profiles("profile", params), None, fn(all, _) { @settings.profile_said(all, params) })
}

///|
/// Whether this Tester's run read a chat's whole row off the chats' list (its trace's head without MBUI_CHAT_ROW): its
/// list's rows were whole then, so the app's `chatRow {station, session}` is that chat's row of the run's `chats` list
/// of its workspace (all of its chats, as the app asks it now: @sfbase.chats_asked), null where it has none such
/// (chat_row_made). That list is the app's own ask, followed as it is, never left for it.
fn chat_rows_listed() -> Bool {
  !@sfcore.trace_switch("MBUI_CHAT_ROW")
}

///|
/// Whether this Tester's run told a chats' list its window (its trace's head with MBUI_CHATS_WINDOW): one without it
/// asked each list with a `limit` (its first 50 rows) and a page more as another topic, its core knowing no window. Its
/// replay's app asks the list as the app does now, answered by the run's with its first limit (@core.Replay's twin
/// topics: what came for that one), and tells the core no window (replay_tells, the source's `call`): the run had none.
fn chats_windowed() -> Bool {
  @sfcore.trace_switch("MBUI_CHATS_WINDOW")
}

///|
/// The run's chats' list a chat's whole row is read out of in such a run.
fn chat_row_list(params : Map[String, Json]) -> Map[String, Json] {
  @sfbase.chats_asked(@settings.workspace_of(@settings.text(Some(Json::object(params)), "station")), "all")
}

///|
/// Chat `session` (its session, or its id) of station `station` in a `chats` value: its row there.
fn row_in_list(chats : Json?, station : String, session : String) -> Json? {
  for d in @settings.items(chats, "days") {
    for i in @settings.items(Some(d), "items") {
      let r = Some(i)
      if @settings.text(r, "station") == station && (@settings.text(r, "session") == session || @settings.text(r, "id") == session) {
        return Some(i)
      }
    }
  }
  None
}

///|
/// The app's `chatRow` with `params` read out of the run's chats' list (chat_rows_listed).
fn chat_row_made(params : Map[String, Json]) -> @sfapp.Topic {
  let p = Some(Json::object(params))
  let station = @settings.text(p, "station")
  let session = @settings.text(p, "session")
  made_once("chatRow", params, @core.follow_topic("chats", params=chat_row_list(params)), None, fn(list, _) {
    match list {
      Some(_) => Some(row_in_list(list, station, session).unwrap_or(Json::null()))
      None => None
    }
  })
}

///|
/// The app's topics read out of a scope's connects whole in such a run: one connect, its choice's sessions.
fn of_connects(name : String) -> Bool {
  name == "connect" || name == "connectCandidates"
}

///|
/// The connects followed for those (of_connects) and what the app asks the same of itself: `connects {scope,
/// mine:false}`.
fn connects_params(params : Map[String, Json]) -> Map[String, Json] {
  match params.get("scope") {
    Some(s) => { "scope": s, "mine": Json::boolean(false) }
    None => { "mine": Json::boolean(false) }
  }
}

///|
/// Whether the app's topic `name` with `params` is itself the connects one is read out of (connects_params): held with
/// them, so that letting one go does not let go of what the others read.
fn is_all_connects(name : String, params : Map[String, Json]) -> Bool {
  name == "connects" && !(params.get("mine") is Some(True))
}

///|
/// Who holds a topic the app's topics are read out of (a scope's stations, its connects) without a graph (a read
/// outside one: the client's `manual` hold, @core's Sub), by that topic's wire key, then the app's topic's: let go of
/// once the last of them leaves, as several of the app's topics are read out of one followed (a graph's readers are
/// counted by the client itself, by its signal's watchers).
// kept across runs: emptied as a Tester begins (on_reset)
let holders : Map[String, Map[String, Bool]] = Map([])

///|
/// Topic `whole` with `whole_params` followed for the app's topic `name` with `params` (a hold of it counted, holders).
fn follow_whole(whole : String, whole_params : Map[String, Json], name : String, params : Map[String, Json]) -> @core.Sub {
  if @signals.active_sub() is None {
    let of = @sfbase.wire_topic_key(whole, whole_params)
    let held = match holders.get(of) {
      Some(h) => h
      None => {
        let h : Map[String, Bool] = Map([])
        holders[of] = h
        h
      }
    }
    held[@sfbase.wire_topic_key(name, params)] = true
  }
  @core.follow_topic(whole, params=whole_params)
}

///|
/// The app's topic `name` with `params`, held outside a graph, left: topic `whole` with `whole_params` left once none
/// holds it so.
fn leave_whole(whole : String, whole_params : Map[String, Json], name : String, params : Map[String, Json]) -> Unit {
  let of = @sfbase.wire_topic_key(whole, whole_params)
  match holders.get(of) {
    Some(held) => {
      held.remove(@sfbase.wire_topic_key(name, params))
      if held.is_empty() {
        holders.remove(of)
        @core.leave_topic(whole, params=whole_params)
      }
    }
    None => @core.leave_topic(whole, params=whole_params)
  }
}

///|
/// A scope's stations followed for the app's topic `name` with `params` (follow_whole).
fn follow_stations(name : String, params : Map[String, Json]) -> @core.Sub {
  follow_whole("stations", stations_params(params), name, params)
}

///|
/// The app's topic `name` with `params`, held outside a graph, left: its scope's stations left once none holds them so.
fn leave_stations(name : String, params : Map[String, Json]) -> Unit {
  leave_whole("stations", stations_params(params), name, params)
}

///|
/// A scope's connects whole followed for the app's topic `name` with `params` (follow_whole).
fn follow_connects(name : String, params : Map[String, Json]) -> @core.Sub {
  follow_whole("connects", connects_params(params), name, params)
}

///|
/// A value read out of another (made_once): what it was made of (the stations, the connects; the run's own topic),
/// and it.
priv struct Made {
  of : Json?
  own : Json?
  topic : @sfapp.Topic
}

///|
/// Each made value by the app's topic (its wire key): made again only when what it is made of is another value, so a
/// page reading it each frame gets the same object while nothing changed (its version too).
// kept across runs: emptied as a Tester begins (on_reset)
let made : Map[String, Made] = Map([])

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
/// The app's topic `name` with `params` made by `make` of topic `of`'s value and, where it has one, of the run's own
/// value of it (`own`): once for each value of theirs (made), its error the run's own's, else `of`'s.
fn made_once(
  name : String,
  params : Map[String, Json],
  of : @core.Sub,
  own : @core.Sub?,
  make : (Json?, Json?) -> Json?,
) -> @sfapp.Topic {
  let key = @sfbase.wire_topic_key(name, params)
  let own_value = match own {
    Some(s) => s.value
    None => None
  }
  let error = match own {
    Some(s) => s.error
    None => of.error
  }
  match made.get(key) {
    Some(m) if same_json(m.of, of.value) && same_json(m.own, own_value) => return { ..m.topic, error }
    _ => ()
  }
  let value = make(of.value, own_value)
  let version = if value is None {
    0
  } else {
    made_count.val += 1
    made_count.val
  }
  let topic : @sfapp.Topic = { value, error, version }
  made[key] = { of: of.value, own: own_value, topic }
  topic
}

///|
/// The app's topic `name` with `params` as the core makes it of the scope's stations whole (`stations`, in such a run)
/// and, for with_stations, of the run's own value (`own`): the settings' fixture_stations.mbt, as the made-up cores do.
fn stations_made(name : String, params : Map[String, Json], stations : @core.Sub, own : @core.Sub?) -> @sfapp.Topic {
  let p = Some(Json::object(params))
  made_once(name, params, stations, own, fn(all, own_value) {
    match name {
      "stations" =>
        match all {
          Some(Array(a)) => Some(Json::array(a.map(@settings.station_row)))
          v => v
        }
      "station" => @settings.station_said(all, @settings.text(p, "station"), "")
      "stationPart" => @settings.station_said(all, @settings.text(p, "station"), @settings.text(p, "part"))
      "connects" =>
        match own_value {
          Some(Object(o)) if !o.contains("slackApps") => @settings.connects_of_stations(own_value, all)
          v => v
        }
      "profiles" => {
        let v = match own_value {
          Some(Object(o)) if !o.contains("machineLogins") => @settings.profiles_of_stations(own_value, all)
          v => v
        }
        // (and a row each, where its items were whole: profiles_whole)
        if profiles_whole() {
          @settings.profiles_rows(v)
        } else {
          v
        }
      }
      _ => None
    }
  })
}

///|
/// The app's topic `name` (of_connects) with `params` as the core makes it of the scope's connects whole (`connects`,
/// in such a run): the settings' fixture_connects.mbt, as the made-up cores do.
fn connects_made(name : String, params : Map[String, Json], connects : @core.Sub) -> @sfapp.Topic {
  let p = Some(Json::object(params))
  made_once(name, params, connects, None, fn(all, _) {
    @settings.connect_said(all, @settings.text(p, "station"), @settings.text(p, "id"), name == "connectCandidates")
  })
}

///|
fn init {
  @ui.on_reset(fn() {
    holders.clear()
    made.clear()
  })
}

///|
/// The app's source over @core, as src/stillfail's (without its logs and its read-only runs).
pub fn source() -> @sfapp.Source {
  {
    topic_read: fn(name, params) {
      if chat_rows_listed() && name == "chatRow" {
        return chat_row_made(params)
      }
      if stations_whole() && of_stations(name) {
        return stations_made(name, params, follow_stations(name, params), None)
      }
      if connects_whole() && of_connects(name) {
        return connects_made(name, params, follow_connects(name, params))
      }
      if profiles_whole() && name == "profile" {
        return profile_made(params)
      }
      let s = if connects_whole() && is_all_connects(name, params) {
        follow_connects(name, params)
      } else if profiles_whole() && name == "profiles" {
        follow_profiles(name, params)
      } else {
        @core.follow_topic(name, params=replay_topic_params(name, params))
      }
      if stations_whole() && with_stations(name) {
        return stations_made(name, params, follow_stations(name, params), Some(s))
      }
      // (the accounts whole of such a run, a row each)
      if profiles_whole() && name == "profiles" {
        return made_once(name, params, s, None, fn(v, _) { @settings.profiles_rows(v) })
      }
      let value = if name == "prefs" { with_rail_view(s.value) } else { s.value }
      { value, error: s.error, version: s.version }
    },
    topic_key: fn(name, params) { @sfbase.wire_topic_key(name, replay_topic_params(name, params)) },
    topic_scope: None,
    topic_alive: fn() { true },
    topic_lease_own: None,
    waits: fn(name, params) {
      if chat_rows_listed() && name == "chatRow" {
        @core.follow_topic("chats", params=chat_row_list(params)).waiting
      } else if stations_whole() && of_stations(name) {
        follow_stations(name, params).waiting
      } else if connects_whole() && of_connects(name) {
        follow_connects(name, params).waiting
      } else if profiles_whole() && name == "profile" {
        follow_profiles(name, params).waiting
      } else {
        @core.follow_topic(name, params=replay_topic_params(name, params)).waiting
      }
    },
    generation: fn(name, params) {
      if chat_rows_listed() && name == "chatRow" {
        @core.client.topic_generation("chats", params=chat_row_list(params))
      } else if stations_whole() && of_stations(name) {
        @core.client.topic_generation("stations", params=stations_params(params))
      } else if connects_whole() && of_connects(name) {
        @core.client.topic_generation("connects", params=connects_params(params))
      } else if profiles_whole() && name == "profile" {
        @core.client.topic_generation("profiles", params=profiles_params(params))
      } else {
        @core.client.topic_generation(name, params=replay_topic_params(name, params))
      }
    },
    // The core's pure calls (`markdown`, `code.ink`, `reader.*`) answered as the real core answered them, kept
    // (src/sfkept): tapes older than a call have none of it, and it is a pure function of what is asked, not made up
    // here. Any other ask the tape does not have still diverges; ⌘K's `commands.find` is the tape's (it says it in the
    // run's language, which only the run knows).
    call: fn(name, params, done) {
      // (a list's window, which a run from before it never told: nothing asked of the run, answered nothing)
      if name == "chats.window" && !chats_windowed() {
        return
      }
      // (one whose answer nobody reads: asked as the app asks it, none given to the core, @sfbase.answer_unread)
      if @sfbase.unread_answer(done) {
        @core.call(name, params~)
        return
      }
      if name == "commands.find" {
        @core.call(name, params~, on_done=done)
        return
      }
      match @sfkept.answer(name, params, None) {
        Some(Ok((v, _))) => {
          // (the tape told it was asked, its answer to it let go: the run's ask of it, if the run asked, is had)
          @core.call(name, params~)
          // (answered at once, as the core's answer comes from outside: what it changes of what is no signal taken so;
          // asked as a read works its value out, once that read is over, @ui.answered_from_outside)
          @ui.answered_from_outside(fn() { done(Ok(v)) })
        }
        // (one always answered here, not kept yet: said on the output for scripts/kept, never the run's to give)
        Some(Err(e)) if @sfkept.has(name, params) => done(Err(e))
        _ => @core.call(name, params~, on_done=done)
      }
    },
    call_bytes: fn(name, params, bytes, done) {
      if @sfbase.unread_answer(done) {
        @core.call(name, params~, bytes=Some(bytes))
        return
      }
      match @sfkept.answer(name, params, Some(bytes)) {
        Some(Ok((v, _))) => @ui.answered_from_outside(fn() { done(Ok(v)) })
        _ => @core.call(name, params~, bytes=Some(bytes), on_done=done)
      }
    },
    read_bytes: fn(name, params, done) {
      match @sfkept.answer(name, params, None) {
        Some(Ok((v, b))) => {
          @ui.answered_from_outside(fn() { done(Ok((v, b.unwrap_or(Bytes::new(0))))) })
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
      // (read out of the app's own list: nothing of the run's to leave)
      if chat_rows_listed() && name == "chatRow" {
        return
      }
      if stations_whole() && (of_stations(name) || with_stations(name)) {
        leave_stations(name, params)
        if of_stations(name) {
          return
        }
      }
      // (one connect, or the connects it is read out of: left once none of them holds those)
      if connects_whole() && (of_connects(name) || is_all_connects(name, params)) {
        leave_whole("connects", connects_params(params), name, params)
        return
      }
      // (one account, or the accounts whole it is read out of: left once none of them holds those)
      if profiles_whole() && (name == "profile" || name == "profiles") {
        leave_whole("profiles", profiles_params(params), name, params)
        return
      }
      @core.leave_topic(name, params=replay_topic_params(name, params)) },
    release: fn(name, params) {
      if chat_rows_listed() && name == "chatRow" {
        return
      }
      // (a graph's readers of the scope's stations counted by the client: it lets them go once none watches them)
      if stations_whole() && (of_stations(name) || with_stations(name)) {
        @core.release_topic("stations", params=stations_params(params))
        if of_stations(name) {
          return
        }
      }
      if connects_whole() && of_connects(name) {
        @core.release_topic("connects", params=connects_params(params))
        return
      }
      if profiles_whole() && name == "profile" {
        @core.release_topic("profiles", params=profiles_params(params))
        return
      }
      @core.release_topic(name, params=replay_topic_params(name, params))
    },
    refresh: fn(name, params) {
      if chat_rows_listed() && name == "chatRow" {
        @core.refresh_topic("chats", params=chat_row_list(params))
      } else if stations_whole() && of_stations(name) {
        @core.refresh_topic("stations", params=stations_params(params))
      } else if connects_whole() && of_connects(name) {
        @core.refresh_topic("connects", params=connects_params(params))
      } else if profiles_whole() && name == "profile" {
        @core.refresh_topic("profiles", params=profiles_params(params))
      } else {
        @core.refresh_topic(name, params=replay_topic_params(name, params))
      }
    },
    read_only: false,
    // (a run's core is asked what the run asked: as its app did, which says so in its trace's head since it does)
    reads_ahead: fn() { @sfcore.trace_switch("MBUI_PLACES_BAR") },
    asks_devices: fn() { @sfcore.trace_switch("MBUI_DEVICES") },
    asks_outline: fn() { @sfcore.trace_switch("MBUI_OUTLINE") },
    switches_ahead: fn() { @sfcore.trace_switch("MBUI_SWITCH_AHEAD") },
  }
}

///|
let the_source : @sfapp.Source = source()

///|
/// Whether this Tester's app has been started (sfcore.begin), as src/stillfail's is before its first frame.
let started : Ref[Bool] = Ref(false)

///|
fn init {
  @ui.on_reset(fn() { started.val = false })
  @core.client.keep(replay_kept)
  @core.client.tells_before(replay_tells)
}

///|
/// What the core's client tells it before a topic is asked (sfbase's chats_told_before, as src/stillfail's app tells
/// it), where the run's app did, its trace's head saying so: a chats' list's first window with MBUI_CHATS_WINDOW. A
/// chat's (`chat.window`) is told whatever the run did, one of the replay's reports (@core.Replay's): its topic is the
/// same either way, and its tape's answers the run's.
fn replay_tells(name : String, topic : Json) -> Array[(String, Json)] {
  if name == "chat" || chats_windowed() {
    @sfbase.chats_told_before(name, topic)
  } else {
    []
  }
}

///|
/// What the core's client keeps as it lets go of it (sfbase's topic_kept, as src/stillfail's main has it), where the
/// run's app did, its trace's head saying so: the lists the places open on with MBUI_HAVE_SAME, Home's own with
/// MBUI_HOME_SAME, a chat with MBUI_KEEP_CHAT, each asked again as that run asked it.
fn replay_kept(name : String, params : Json) -> Int {
  let on = if name == "chat" {
    @sfcore.trace_switch("MBUI_KEEP_CHAT")
  } else if @sfbase.home_lasting_of(name) {
    @sfcore.trace_switch("MBUI_HOME_SAME")
  } else {
    @sfcore.trace_switch("MBUI_HAVE_SAME")
  }
  if on {
    @sfbase.topic_kept(name, params)
  } else {
    0
  }
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
