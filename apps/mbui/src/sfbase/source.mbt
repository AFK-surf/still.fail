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
/// Whether the value is what the core last said before it was let go of (`lasting`, shown again at once while its
/// answer comes), not its answer now: its version is below every core's (LastSaid).
pub fn TopicState::kept(self : TopicState) -> Bool {
  self.version < -1
}

///|
/// A legacy topic read leaves by name; an owned read releases only the supplied, independently owned reader.
pub(all) enum TopicLeave {
  Legacy
  Owned(() -> Unit)
}

///|
/// How a source read is owned. A lease may explicitly move to another view after it is created.
#derive(Eq)
pub(all) enum TopicReadMode {
  Raw
  Graph
  Lease
}

///|
/// Where signing in to still.fail stands, as the sign-in page says it: nothing under way; its page being opened; out in
/// the browser, the app waiting for it to come back; what it brought back being checked; or failed, why in the person's
/// words ("" when there are none).
#derive(Eq, Debug)
pub(all) enum SignInStep {
  Idle
  Opening
  InBrowser
  Verifying
  Failed(String)
}

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
  /// a call to the core; `done` gets its answer or its error, or is `answer_unread`: nobody reads it
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
  /// whether what the places open on is kept as last said (`lasting`) and asked ahead of them (places_ahead): not of
  /// a run seen again that was recorded before the app did, whose core is asked only what the run asked
  reads_ahead : () -> Bool
  /// whether the stations' places and pages ask for the workspace's devices (`devices`): not of a run seen again that
  /// was recorded before the app did
  asks_devices : () -> Bool
  /// whether an open chat's page asks for its outline (`chatOutline`: its rail of ticks, its outline's panel): not of a
  /// run seen again that was recorded before the app did
  asks_outline : () -> Bool
  /// whether a choice that switches what its page reads asks ahead of the switch what it will read, the switch made as
  /// that is answered (switch_answered): not of a run seen again that was recorded before the app did, whose choice
  /// switched at the press and asked as the page then read
  switches_ahead : () -> Bool
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
    // An event in a build can read a topic the graph already holds. Use that value without adding a manual hold. So
    // can an event of a view's (a press on what its page shows, outside any build) through that view's source: as it
    // is then, held no longer than the graph holds it, not for as long as the view lives (Source::owned_by's raw read).
    if src.topic_scope is None || !held_building.val {
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
  let waiting = (src.waits)(name, params)
  // (the accounts said anew, one signed in or out: nothing kept of what another's showed)
  if name == "accounts" && src.topic_scope is None && topic.value is Some(now) {
    if last_accounts.val != Some(now) {
      last_accounts.val = Some(now)
      last_said.val = last_said.val.filter(fn(l) { !physical_equal(l.source, src) })
    }
  }
  // (a view's own source reads through the one it is of, which keeps them: topic_scope none)
  if src.topic_scope is None && lasting.contains(name) && !params.contains("q") && (src.reads_ahead)() {
    let key = name + "\u{1}" + Json::object(params).stringify()
    match (topic.value, topic.error) {
      (Some(value), _) => last_put(src, key, value)
      (None, None) =>
        match last_said.val.search_by(fn(l) { physical_equal(l.source, src) && l.key == key }) {
          Some(i) => {
            let l = last_said.val[i]
            return { value: Some(l.value), error: None, version: l.version, waiting: false }
          }
          None => ()
        }
      _ => ()
    }
  }
  { value: topic.value, error: topic.error, version: topic.version, waiting }
}

///|
/// The lists a place of the bar or the rail opens on: what the core last said of each is kept (last_said) and shown at
/// once when it is asked again, until its answer comes. A place left lets go of what it read, and come back to drew
/// its bones until the core answered across its thread (the user, 2026-11-10). Lists read only: nothing typed for
/// (`q`), nothing written in (a form, a draft), no chat. The stations' rows are one ask for every list, a chat's name of
/// its station too, which takes no kept value (station_marks: what changed while nothing read it is never shown as it
/// was, core_signal_wbtest.mbt). Home's own lists too (home_lasting): on 小屏 Home switched away from rests on the
/// stack's shelf and lets go of what it read, and taken back read it anew; shown only as the core answered, its long
/// jobs and its rows were gone meanwhile and then every row made again and coming in as new (the owner's phone,
/// 2026-11-12: 50–68 ms, the rows under 今天 drawn as slivers through that frame; bar_places_kept_wbtest.mbt).
// kept across runs: a value (nothing of it changes)
let lasting : Array[String] = [
  "workspace", "stations", "stationNet", "profiles", "connects", "vaults", "usage", "archive", "chats", "longJobs", "changelog",
]

///|
/// Of `lasting`, Home's own lists (its chats, its long jobs, the news over them): kept as they are let go of since
/// MBUI_HOME_SAME, what a replay of a run from before asks as that run did (sfreplay's replay_kept).
// kept across runs: a value (nothing of it changes)
let home_lasting : Array[String] = ["chats", "longJobs", "changelog"]

///|
/// Whether topic `name` is one of Home's own lists `lasting` keeps (home_lasting).
pub fn home_lasting_of(name : String) -> Bool {
  home_lasting.contains(name)
}

///|
/// How many values of topic `name` asked with `params` (its JSON as the core is asked it, its name in it too) the
/// core's client keeps as they are let go of, to ask them again with their version (@core.Client::keep: the core
/// answers `same` where one has not changed, what changed from it where it has); 0, none. The lists the places open
/// on (`lasting`, as many as last_said keeps), and a chat however it is asked (its session, a thread, `compact`):
/// `chats_kept` of those, a decoded chat being the largest tree the app holds. Unlike the lists (last_said), a chat's
/// value kept is never shown before the core's answer: a chat's page and a row's read ahead have it only as that comes.
pub fn topic_kept(name : String, params : Json) -> Int {
  if name == "chat" {
    chats_kept
  } else if lasting.contains(name) && !(params is Object(p) && p.contains("q")) {
    last_most
  } else {
    0
  }
}

///|
/// How many chats' values are kept at a time (topic_kept), the oldest forgotten: a chat opened again, or read ahead
/// again from its row, among the last few is answered with what changed in it, not the whole of it (a phone's ~180 KB,
/// 17-21 ms to decode).
let chats_kept : Int = 4

///|
/// What a source last said of a lasting topic. `version` is below every core's (those count up from 0), another for
/// each value kept: what is worked out of a topic by its version never takes this for the answer that follows it.
priv struct LastSaid {
  source : Source
  key : String
  value : Json
  version : Int
}

///|
/// The newest last (last_most of them: a list asked for many ways, the oldest forgotten).
// kept across runs: put back as a run begins (reset)
let last_said : Ref[Array[LastSaid]] = Ref([])

///|
let last_most : Int = 64

///|
// kept across runs: only counted on
let last_count : Ref[Int] = Ref(0)

///|
fn last_put(src : Source, key : String, value : Json) -> Unit {
  let at = last_said.val.search_by(fn(l) { physical_equal(l.source, src) && l.key == key })
  match at {
    Some(i) if physical_equal(last_said.val[i].value, value) => return
    _ => ()
  }
  last_count.val += 1
  let kept = last_said.val.filter(fn(l) { !(physical_equal(l.source, src) && l.key == key) })
  kept.push({ source: src, key, value, version: -2 - last_count.val })
  last_said.val = if kept.length() > last_most { kept[kept.length() - last_most:].to_owned() } else { kept }
}

///|
/// The accounts as last said (read_topic_state).
// kept across runs: put back as a run begins (reset)
let last_accounts : Ref[Json?] = Ref(None)

///|
fn last_reset() -> Unit {
  last_said.val = []
  last_accounts.val = None
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
  name : String
  params : Map[String, Json]
  independent : Bool
  holder : @signals.Computed[TopicState]
  token : Ref[Bool]
}

///|
// kept across runs: an active graph reader may outlive an app reset; its last reader removes the entry.
let followed_topics : Ref[Array[FollowedTopic]] = Ref([])

///|
/// Whether a reader holds topic `name` with `params` now (a page's, a graph's: followed and watched). It asks nothing
/// of the core and acquires nothing.
fn topic_held(name : String, params : Map[String, Json]) -> Bool {
  let key = name + "\u{1}" + Json::object(params).stringify()
  followed_topics.val.iter().any(fn(t) { t.key == key && t.holder.watched() })
}

///|
/// The topics a reader holds now (topic_held's), each once, by the source that follows it: what a page that opens
/// another in its place hands over (open_handing_held).
fn topics_held() -> Array[(Source, String, Map[String, Json])] {
  let seen : Map[String, Bool] = Map([])
  let out : Array[(Source, String, Map[String, Json])] = []
  for t in followed_topics.val {
    if !seen.contains(t.key) && t.holder.watched() {
      seen[t.key] = true
      out.push((t.source, t.name, t.params))
    }
  }
  out
}

///|
/// What is declared (declare_topic) and not let go of: each by its source, name and parameters.
// kept across runs: put back as a run begins (declared_reset)
let declared_topics : Ref[Array[(Source, String, Map[String, Json])]] = Ref([])

///|
/// Topic `name` with `params` of `src` declared: asked of the core now, outside any build, and kept asked with no
/// reader of its own, so the first reader to come takes it over as it reads (the same subscription, never let go of
/// between) and the graph lets it go once its last reader leaves, as any. One no reader comes to is let go of as what
/// it was declared for ends (declared_let_go). What it holds now. What declares never reads what it declared, then
/// or after (the coordinator of the migration, 2026-11-12): a read of its own would be a reader that holds it past its
/// readers' leaving, its unsubscribe never sent.
pub fn declare_topic(src : Source, name : String, params : Map[String, Json]) -> TopicState {
  let key = name + "\u{1}" + Json::object(params).stringify()
  if !declared_topics.val.iter().any(fn(d) { physical_equal(d.0, src) && d.1 + "\u{1}" + Json::object(d.2).stringify() == key }) {
    declared_topics.val.push((src, name, params.copy()))
  }
  let owner = @signals.set_owner(None)
  let state = @signals.untracked(fn() { followed_topic(src, name, params).get() })
  @signals.set_owner(owner) |> ignore
  state
}

///|
/// What is declared that no reader took over, let go of now (what it was declared for ended: another workspace in view,
/// none); what a reader took is the graph's, let go of as its last reader leaves.
pub fn declared_let_go() -> Unit {
  let was = declared_topics.val
  declared_topics.val = []
  let_go_unread(was)
}

///|
/// Each of `declared` that no reader took over let go of now (declared_let_go's, page_declared_let_go's).
fn let_go_unread(declared : Array[(Source, String, Map[String, Json])]) -> Unit {
  for d in declared {
    let (src, name, params) = d
    let key = name + "\u{1}" + Json::object(params).stringify()
    match followed_topics.val.search_by(fn(t) { physical_equal(t.source, src) && t.key == key && !t.independent }) {
      Some(i) if !followed_topics.val[i].holder.watched() => {
        let holder = followed_topics.val[i].holder
        followed_topics.val = followed_topics.val.filter(fn(t) { !(physical_equal(t.source, src) && t.key == key && !t.independent) })
        (src.release)(name, params)
        // (its holder, read once as it was declared and by no reader since, let go of what it read: else that read
        // still follows the subscription, which the client then never ends, its unsubscribe never sent; till
        // 2026-11-12, every switch of workspace left what was declared and never read subscribed:
        // src/sfapp/declared_let_go_wbtest.mbt)
        holder.dispose()
      }
      _ => ()
    }
  }
}

///|
/// What the page on top declared as it came on top (declare_page_topic) and no reader took yet.
// kept across runs: put back as a run begins (declared_reset)
let page_declared : Ref[Array[(Source, String, Map[String, Json])]] = Ref([])

///|
/// Topic `name` with `params` of `src` declared as a page comes on top (page_opens_node: page_opens), as declare_topic
/// declares what a workspace's first screen reads: asked of the core at that moment, not as the frame that builds the
/// page runs, and taken over by the page's reader as it reads, the same subscription all along. One no reader comes
/// to is let go of as another page comes on top (page_declared_let_go), or another workspace comes in view.
pub fn declare_page_topic(src : Source, name : String, params : Map[String, Json]) -> Unit {
  let key = name + "\u{1}" + Json::object(params).stringify()
  if page_declared.val.iter().any(fn(d) { physical_equal(d.0, src) && d.1 + "\u{1}" + Json::object(d.2).stringify() == key }) {
    return
  }
  page_declared.val.push((src, name, params.copy()))
  let owner = @signals.set_owner(None)
  @signals.untracked(fn() { followed_topic(src, name, params).get() }) |> ignore
  @signals.set_owner(owner) |> ignore
  page_declared_told.set(page_declared_told.get() + 1)
}

///|
/// How many topics pages have declared as they came on top, or as what they read said more (declare_page_topic):
/// read by what waits for a page's reads held (sfapp's first_page_node, page_opens_node's chat), told again as one is.
// kept across runs: a count, read only for its changes
let page_declared_told : @signals.Signal[Int] = @signals.signal(0)

///|
/// page_declared_told, read where it is followed.
pub fn page_declared_now() -> Int {
  page_declared_told.get()
}

///|
/// What the page on top before declared and no reader took, let go of now (another page on top).
pub fn page_declared_let_go() -> Unit {
  let was = page_declared.val
  page_declared.val = []
  let_go_unread(was)
}

///|
/// What is declared and read by no reader now (`name` and parameters, as JSON): at the moment what declared it is
/// shown whole, none; one here is declared and not read, a fault of the declaration (sfapp's declared_read_wbtest).
pub fn declared_unread() -> Array[String] {
  [..declared_topics.val, ..page_declared.val].filter_map(fn(d) {
    let (src, name, params) = d
    // (one no longer followed was taken by its reader and let go of as that left: read, not a fault)
    match existing_followed_topic(src, name, params) {
      Some(h) if !h.watched() => Some(name + " " + Json::object(params).stringify())
      _ => None
    }
  })
}

///|
/// As a run begins: what the run before declared and no reader took let go of, as another workspace coming in view
/// would (declared_let_go), not left followed by nothing into the next run (where it was taken as asked already, its
/// subscription never sent again: a replay's pace pass after one ended before the reader came).
fn declared_reset() -> Unit {
  declared_let_go()
  page_declared_let_go()
}

///|
/// Topics asked as the core holds them now for what follows them, asking for none (one nothing follows yet is answered
/// by nothing): what reads it follows its value and error while it reads, holding nothing it would not hold else
/// (sfapp's first_page_node, reading between frames whether what a page builds is answered).
pub fn read_held(src : Source) -> (String, Map[String, Json]) -> TopicState {
  fn(name, params) {
    match existing_followed_topic(src, name, params) {
      Some(h) => h.get()
      None => { value: None, error: None, version: -1, waiting: false }
    }
  }
}

///|
/// What `src` holds of a topic followed now, as read_held reads it; None where nothing follows it.
pub fn read_held_found(src : Source) -> (String, Map[String, Json]) -> TopicState? {
  fn(name, params) { existing_followed_topic(src, name, params).map(fn(h) { h.get() }) }
}

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
        // Another reader may take over in this signal flush, outside event or frame. Check once it is finished.
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
      followed_topics.val.push({ source: src, key, name, params: params.copy(), independent, holder, token })
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
    reads_ahead: fn() { true },
    asks_devices: fn() { true },
    asks_outline: fn() { true },
    switches_ahead: fn() { true },
  }
}

///|
/// The core a page's bones are drawn over (@sf.waiting's `sample`: what it will show, of made-up words): it says
/// nothing and answers nothing, so what is only shown asks the real core for nothing, reads nothing ahead and opens no
/// picture.
// kept across runs: a value (nothing in it is written: its topics none, its calls never answered)
pub let sample_source : Source = { ..made_source(call=fn(_, _, _) {  }), read_only: true }

///|
/// The `done` of a call whose answer nobody reads (@settings.answer_unread, the one value for every page's calls).
pub let answer_unread : (Result[Json, Json]) -> Unit = @settings.answer_unread

///|
/// Whether `done` is answer_unread: the call's answer read by nobody (a source's `call`, as it asks the core).
pub fn unread_answer(done : (Result[Json, Json]) -> Unit) -> Bool {
  physical_equal(done, answer_unread)
}
