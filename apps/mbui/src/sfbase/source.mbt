// Where the app's pages read and write: the still.fail core (src/stillfail, over mbui/core) or a fixture of made-up
// chats (fixture.mbt: no core, the same views' shapes), for screenshots that are the same on every run.

///|
/// A topic as it stands: its value, or why it could not be read; `version` counts its changes.
pub(all) struct Topic {
  value : Json?
  error : Json?
  version : Int
}

///|
/// A topic as a value a signal can carry, including whether its first value waits on a station.
pub(all) struct TopicState {
  value : Json?
  error : Json?
  version : Int
  waiting : Bool
}

///|
/// The fields used by older page code after reading a topic signal.
pub fn TopicState::snapshot(self : TopicState) -> Topic {
  { value: self.value, error: self.error, version: self.version }
}

///|
/// A legacy topic read leaves by name; an owned read releases only the supplied, independently owned reader.
pub(all) enum TopicLeave {
  Legacy
  Owned(() -> Unit)
}

///|
/// How a source read is owned. A lease may explicitly move to another view after it is created.
pub(all) enum TopicReadMode {
  Raw
  Graph
  Lease
} derive(Eq)

///|
/// Where signing in to still.fail stands, as the sign-in page says it: nothing under way; its page being opened; out in
/// the browser, the app waiting for it to come back; what it brought back being checked; or failed, why in the person's
/// words ("" when there are none).
pub(all) enum SignInStep {
  Idle
  Opening
  InBrowser
  Verifying
  Failed(String)
} derive(Eq, Show)

///|
/// The step a sign-in's state says (sfcore's SignIn: `failed` "" when it did not fail, "!" when it did with no words).
pub fn SignInStep::of(busy~ : Bool, verifying~ : Bool, waiting~ : Bool, failed~ : String) -> SignInStep {
  if verifying {
    Verifying
  } else if busy {
    Opening
  } else if waiting {
    InBrowser
  } else if failed != "" {
    Failed(if failed == "!" { "" } else { failed })
  } else {
    Idle
  }
}

///|
pub(all) struct Source {
  /// The low-level topic reader used to build `topic`. Use `prefetch` for an independent early read.
  topic_read : (String, Map[String, Json]) -> Topic
  /// This source's subscription identity, after any parameter normalization; equal keys share a subscription.
  topic_key : (String, Map[String, Json]) -> String
  /// A view source distinguishes graph evaluation from an independent read.
  topic_scope : ((TopicReadMode, () -> TopicState) -> TopicState)?
  /// Whether the source can still create a reader (a view-owned source ends with its view).
  topic_alive : () -> Bool
  /// Attach a new lease to all views which currently own this source; returns a cleanup deregistration.
  topic_lease_own : ((() -> Unit) -> () -> Unit)?
  /// whether the core said that topic, which has no value yet, waits on a station for it: none of what it shows is on
  /// the device (a chat whose messages are still to come), not the core still reading what is. Read as `topic` is.
  waits : (String, Map[String, Json]) -> Bool
  /// The core's lifetime and whether a retained topic value came from it; does not acquire the topic.
  generation : (String, Map[String, Json]) -> (Int, Bool)
  /// a call to the core; `done` gets its answer or its error
  call : (String, Json, (Result[Json, Json]) -> Unit) -> Unit
  /// a call with bytes beside it (a file's part going up: `station.upload.part`)
  call_bytes : (String, Json, Bytes, (Result[Json, Json]) -> Unit) -> Unit
  /// a call whose answer has bytes beside it (a part of a drive's file: `drive.read`)
  read_bytes : (String, Json, (Result[(Json, Bytes), Json]) -> Unit) -> Unit
  /// a call whose answer has bytes beside it and that says how far it has got before it (`station.file` with
  /// `progress`: `{loaded, total}` each time, then the file): `on_value` each time, then `done`
  read_going : (String, Json, (Json) -> Unit, (Result[(Json, Bytes), Json]) -> Unit) -> Unit
  /// a call that says how it goes before its answer (`station.preview` with `stream`: the answer's head, then each
  /// piece of its body with its bytes): `on_value(value, bytes)` each time, then `done`; the call's id, for `cancel`
  stream : (String, Json, Bytes?, (Json, Bytes?) -> Unit, (Result[Json, Json]) -> Unit) -> Int
  /// a streamed call stopped (nothing more of it comes)
  cancel : (Int) -> Unit
  /// 登录 pressed
  sign_in : () -> Unit
  /// whether a sign-in is under way
  signing_in : () -> Bool
  /// where signing in stands: what the sign-in page's button and the line under it say
  sign_in_step : () -> SignInStep
  /// a picture by its URL (a person's, a station's icon) as it is put up on its page's time on top `stint`
  /// (Ctx::page_stint): an image's src once it is here, "" until then (the core's `picture`: core_pictures.mbt)
  picture : (String, Int) -> String
  /// what the core said when it stopped, if it did
  fatal : () -> String?
  /// a file of a chat as its messages show it (`station.file`, an image's thumbnail): by its station, the session
  /// that keeps it and its name; an image's key once it is here, "" while it comes, "!" when it could not be had
  file : (String, String, String) -> String
  /// a video of a chat's still as the station makes it (`station.poster`: its first frame, a small JPEG), by the same
  /// three; an image's key once it is here, "" while it comes, "!" when the station has none
  poster : (String, String, String) -> String
  /// a picture of a draft's file the page holds no bytes of (a draft kept, read again as the app starts:
  /// `composer.picture`), by the draft's key and the file's id: an image's key once here, "" while it comes, "!" when
  /// the device keeps none
  draft_picture : (String, String) -> String
  /// what became of those pictures, each by its id (file_image_id, poster_image_id): which failed for want of their
  /// station, to be asked again (chat_images.mbt)
  images : ChatImages
  /// the time of day, in milliseconds since 1970 (how long an agent's turn has run)
  now : () -> Double
  /// a topic no page shows any more (`unsubscribe`)
  leave : (String, Map[String, Json], TopicLeave) -> Unit
  /// a signal reader ended; another graph reader or a legacy untracked hold may still need the topic
  release : (String, Map[String, Json]) -> Unit
  /// ask an already held topic for a fresh value without dropping its readers
  refresh : (String, Map[String, Json]) -> Unit
  /// nothing the reader does is told to the core (MBUI_READONLY=1): no read marks, no place kept, nothing sent, no
  /// draft kept, no file put up
  read_only : Bool
}

///|
/// A read-only signal of one core subscription. Readers of the same source, name and params share its subscription;
/// the graph releases it when the last reader leaves. An immediate-mode page holds its untracked frame read until it leaves.
pub fn Source::topic(src : Source, name : String, params : Map[String, Json]) -> @signals.Computed[TopicState] {
  let key = params.copy()
  @signals.computed_scoped(fn(_) {
    followed_topic(src, name, key).get()
  }, untracked_read=Some(fn() {
    if !held_building.val && src.topic_scope is None {
      return None
    }
    // An event in a build can read a topic the graph already holds. Use that value without adding a manual hold.
    if src.topic_scope is None {
      match existing_followed_topic(src, name, key) {
        Some(holder) if holder.watched() => return Some(holder.get())
        _ => ()
      }
    }
    Some(match src.topic_scope {
      Some(scope) => scope(Raw, fn() { read_topic_state(src, name, key) })
      None => read_topic_state(src, name, key)
    })
  }))
}

///|
/// Read ahead independently of any current graph. A view source holds this read until it leaves or its view ends.
pub fn Source::prefetch(src : Source, name : String, params : Map[String, Json]) -> Topic {
  @signals.untracked(fn() {
    let read = fn() {
      let topic = (src.topic_read)(name, params)
      { value: topic.value, error: topic.error, version: topic.version, waiting: false }
    }
    let state = match src.topic_scope {
      Some(scope) => scope(Raw, read)
      None => read()
    }
    state.snapshot()
  })
}

///|
fn read_topic_state(src : Source, name : String, params : Map[String, Json]) -> TopicState {
  let topic = (src.topic_read)(name, params)
  { value: topic.value, error: topic.error, version: topic.version, waiting: (src.waits)(name, params) }
}

///|
/// A page scope already has a graph reader and must not also acquire an untracked frame hold.
fn scoped_topic(src : Source, name : String, params : Map[String, Json], independent? : Bool = false) -> @signals.Computed[TopicState] {
  let key = params.copy()
  @signals.computed_scoped(fn(_) { followed_topic(src, name, key, independent~).get() })
}

///|
/// A shared topic's computed and its lifetime, shared by every reader of the same source and parameters.
priv struct FollowedTopic {
  source : Source
  key : String
  independent : Bool
  holder : @signals.Computed[TopicState]
  token : Ref[Bool]
}

///|
// kept across runs: an active graph reader may outlive an app reset; its last reader removes the entry.
let followed_topics : Ref[Array[FollowedTopic]] = Ref([])

///|
fn existing_followed_topic(src : Source, name : String, params : Map[String, Json]) -> @signals.Computed[TopicState]? {
  let key = name + "\u{1}" + Json::object(params).stringify()
  followed_topics.val.search_by(fn(t) { physical_equal(t.source, src) && t.key == key && !t.independent }).map(fn(i) { followed_topics.val[i].holder })
}

///|
fn followed_topic(src : Source, name : String, params : Map[String, Json], independent? : Bool = false) -> @signals.Computed[TopicState] {
  let key = name + "\u{1}" + Json::object(params).stringify()
  match followed_topics.val.search_by(fn(t) { physical_equal(t.source, src) && t.key == key && t.independent == independent }) {
    Some(i) => followed_topics.val[i].holder
    None => {
      // Read first and on every evaluation, so the lifetime ends only when the holder loses its last reader.
      let lifetime = @signals.signal(0)
      let token = Ref(true)
      lifetime.on_unwatched(fn() {
        // Another reader may take over in this signal flush or this frame. Check again once both have finished.
        @signals.after_flush(fn() {
          @ui.after_frame(fn() {
            match followed_topics.val.search_by(fn(t) { physical_equal(t.token, token) }) {
              Some(i) if !followed_topics.val[i].holder.watched() => {
                // A removed Array slot keeps its old value alive; replace the array before releasing.
                followed_topics.val = followed_topics.val.filter(fn(t) { !physical_equal(t.token, token) })
                (src.release)(name, params)
              }
              _ => ()
            }
          })
        })
      })
      let holder = @signals.computed(fn(_) {
        lifetime.get() |> ignore
        match src.topic_scope {
          Some(scope) => scope(if independent { Lease } else { Graph }, fn() { read_topic_state(src, name, params) })
          None => read_topic_state(src, name, params)
        }
      })
      followed_topics.val.push({ source: src, key, independent, holder, token })
      holder
    }
  }
}

///|
/// The chat page asks for its agents' identities and state. Their full histories and jobs are read by their own
/// pages; older cores ignore the extra parameter and still return the full chat.
pub fn core_topic_params(name : String, params : Map[String, Json]) -> Map[String, Json] {
  if name != "chat" && name != "chatJobs" {
    return params
  }
  let out = params.copy()
  out["compact"] = Json::boolean(true)
  out
}

///|
/// A source which treats its name and each parameter object as given may use this identity.
pub fn exact_topic_key(name : String, params : Map[String, Json]) -> String {
  name.length().to_string() + ":" + name + Json::object(params).stringify()
}

///|
/// Identity of the object sent to a core Client, including the `topic` parameter's override and field order.
pub fn wire_topic_key(name : String, params : Map[String, Json]) -> String {
  let object : Map[String, Json] = { "topic": Json::string(name) }
  for key, value in params { object[key] = value }
  Json::object(object).stringify()
}

///|
/// Bind the client's core once when it starts: Markdown read and code coloured by it (`markdown`, `code.ink`). Static
/// fixtures have no core (the real core's answers kept instead: src/sfkept); a recorded client binds its replay of the
/// same operations. The live renderer never interprets Markdown, TeX or code while an answer is coming.
pub fn use_core_markdown(src : Source) -> Unit {
  @sf.markdown_read.val = Some(fn(words, done) {
    (src.call)("markdown", { "text": Json::string(words) }, fn(answer) {
      match answer {
        Ok(v) => done(field(Some(v), "md"))
        Err(_) => done(None)
      }
    })
  })
  @sf.ink_read.val = Some(fn(code, lang, done) {
    (src.call)("code.ink", { "code": Json::string(code), "lang": Json::string(lang) }, fn(answer) {
      match answer {
        Ok(v) =>
          done(
            match field(Some(v), "ink") {
              Some(String(s)) => Some(s)
              _ => None
            },
          )
        Err(_) => done(None)
      }
    })
  })
}

///|
/// A core made up for a page's own test (sfpages' tests, a page drawn alone in a Tester): what each topic says
/// (`topic`, none by default) and how each call is answered (`call`, an error saying so by default); a stream answered
/// the same way, once. Nothing else: no pictures, no files, no sign-in, the clock at 0.
pub fn made_source(
  topic? : (String, Map[String, Json]) -> Json? = fn(_, _) { None },
  call? : (String, Json, (Result[Json, Json]) -> Unit) -> Unit = fn(name, _, done) {
    done(Err({ "code": "unknown_call", "message": Json::string("no " + name + " made up") }))
  },
) -> Source {
  {
    topic_read: fn(name, params) {
      match topic(name, params) {
        Some(v) => { value: Some(v), error: None, version: 1 }
        None => { value: None, error: None, version: 0 }
      }
    },
    topic_key: exact_topic_key,
    topic_scope: None,
    topic_alive: fn() { true },
    topic_lease_own: None,
    waits: fn(_, _) { false },
    generation: fn(_, _) { (0, true) },
    call,
    call_bytes: fn(name, params, _, done) { call(name, params, done) },
    read_bytes: fn(name, _, done) { done(Err({ "code": "unknown_call", "message": Json::string("no " + name) })) },
    read_going: fn(name, _, _, done) { done(Err({ "code": "unknown_call", "message": Json::string("no " + name) })) },
    stream: fn(name, params, _, _, done) {
      call(name, params, done)
      0
    },
    cancel: fn(_) {  },
    sign_in: fn() {  },
    signing_in: fn() { false },
    sign_in_step: fn() { Idle },
    picture: fn(_, _) { "" },
    fatal: fn() { None },
    file: fn(_, _, _) { "" },
    poster: fn(_, _, _) { "" },
    draft_picture: fn(_, _) { "!" },
    images: ChatImages::new(),
    now: fn() { 0.0 },
    leave: fn(_, _, __reason) {
      if __reason is TopicLeave::Owned(__stop) { __stop(); return }
      },
    release: fn(_, _) {  },
    refresh: fn(_, _) {  },
    read_only: false,
  }
}

///|
/// The core a page's bones are drawn over (@sf.waiting's `sample`: what it will show, of made-up words): it says
/// nothing and answers nothing, so what is only shown asks the real core for nothing, reads nothing ahead and opens no
/// picture.
// kept across runs: a value (nothing in it is written: its topics none, its calls never answered)
pub let sample_source : Source = { ..made_source(call=fn(_, _, _) {  }), read_only: true }
