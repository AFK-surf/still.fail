// One UI client of the still.fail core, over whatever carries the protocol's JSON:
// `{id, call, params}` and `{id, subscribe, keyed, from?}` out; `{id, ok|error}`, `{id, value}`, `{id, delta}`,
// `{id, delta, from}` and `{fatal}` in; a topic whose value is kept to ask with again (Client::keep) is let go of with
// `{id, unsubscribe, keep}`, answered `{id, v}`, and asked again with `{id, subscribe, have}`, answered `{id, same}` where
// its value is still the one kept, `{id, delta, kept}` what changed from it where it is not (client/core-ts protocol.ts). Each subscription keeps its topic's current value, deltas applied (delta.mbt), and a version that
// changes with every message for it, so a view can tell what changed since its last frame without comparing values;
// and a signal of its changes (mbui/signals) set as each comes, and as it ends: what reads the topic in a computed
// follows it from here, the core's change pushed on to it, not looked for as it is read.
// The client is the UI thread's: messages come to `receive` in order on it (native.mbt drains the engine's queue).

///|
/// A subscription to a topic: `value` is its whole current value (None until the first, and after an error until the
/// next value), `error` the core's error for it while it could not be read, `version` changes with each message.
/// `changes` is set with each message too, and once more as it ends (unsubscribed, the client reset): what read it
/// reads the topic again then, from the subscription asked anew.
pub struct Sub {
  mut id : Int
  topic : Json
  mut value : Json?
  mut error : Json?
  mut version : Int
  /// told by the core, while it has no value, that its value waits on a station: none of what it shows is on the device
  /// (core-ts store.ts `waits`), not the core still reading it
  mut waiting : Bool
  priv key : String
  /// The lookup key; `key` remains the JSON text used to describe the subscription in waits.
  priv look : String
  changes : @signals.Signal[Int]
  /// A legacy untracked read holds this topic until it explicitly leaves.
  priv mut manual : Bool
  /// A caller directly holds the Sub itself until it explicitly unsubscribes.
  priv mut direct : Bool
  /// A signal or legacy holder asked to release it when no reader remains.
  priv mut retiring : Bool
  /// The core generation that produced the value currently kept in this subscription.
  priv mut value_generation : Int
  /// Asked as more of what another of its subscriptions has (`from_of`), till its first value: that one's id, its
  /// first value coming as what changed from that one's (the core's store.ts `#firstFrom`), not the whole of it again.
  priv mut from : Int?
  /// Let go of while one asked from it waits for its first value: kept till then, as the core's delta to it reads it,
  /// its readers told it ended. Or let go of keeping its value (`keeping`).
  priv mut ending : Bool
  /// Let go of with `keep` (Client::keep), till the core's `{id, v}`: what comes for it before that is applied still,
  /// that answer being its last message, so what is kept is the value `v` is the version of.
  priv mut keeping : Bool
}

///|
/// The subscription read: what reads it in a computed follows its changes (Sub.changes).
pub fn Sub::followed(self : Sub) -> Sub {
  if @signals.active_sub() is None {
    self.manual = true
  }
  self.changes.get() |> ignore
  self
}

///|
/// What reads it told it changed: a message for it, or its end (`ended`: -1, no version of its own).
fn Sub::changed(self : Sub, ended? : Bool = false) -> Unit {
  self.changes.set(if ended { -1 } else { self.version })
}

///|
// A retirement watch holds its client; remove it once it is no longer needed.
fn Sub::clear_retirement_watch(self : Sub) -> Unit {
  self.changes.on_unwatched(fn() {  })
}

///|
pub struct Client {
  priv send : (String) -> Unit
  /// a message with bytes beside it (a file's part going up)
  priv send_bytes : (String, Bytes) -> Unit
  priv subs : Map[Int, Sub]
  priv by_key : Map[String, Sub]
  priv calls : Map[Int, (Result[Json, Json]) -> Unit]
  /// what calls that say how they go are told before their answer (`{id, value}`), by the call's id
  priv progress : Map[Int, (Json, Bytes?) -> Unit]
  /// what of a call's values changes nothing a frame reads (Client::quiet), by the call's name; and by the id of each
  /// such call under way
  priv quiet_names : Map[String, (Json) -> Bool]
  priv quiet_calls : Map[Int, (Json) -> Bool]
  /// the calls whose answers nobody reads (Client::unread), by name; and the ids of those under way
  priv unread_names : Map[String, Bool]
  priv unread_calls : Map[Int, Bool]
  /// the calls whose answers change only signals (Client::said), by name; and the ids of those under way
  priv said_names : Map[String, Bool]
  priv said_calls : Map[Int, Bool]
  priv mut next_id : Int
  /// Distinguishes subscriptions when reset reuses an id.
  priv mut epoch : Int
  /// Changes when a new core starts, including a restart that keeps existing subscriptions.
  priv mut generation : Int
  /// the bytes beside the message being taken, if any
  priv mut beside : Bytes?
  /// Changes with every message that changed something (a sub's value or error, a call's answer).
  mut version : Int
  /// The core's reason, once it has failed (`{fatal}`); cleared by `restarted`.
  mut fatal : String?
  /// Set as `fatal` is: what reads it follows it (fatal)
  fatal_said : @signals.Signal[Int]
  /// Who keeps what is awaited of the core (Client::track: mbui's effect.mb outside): a ticket for each call until
  /// its answer, each subscription until its first value (or error)
  priv mut start_wait : (String) -> Int
  priv mut end_wait : (Int) -> Unit
  /// the tickets: by call id, by subscription id
  priv call_waits : Map[Int, Int]
  priv sub_waits : Map[Int, Int]
  /// calls whose effect the core shows on a draft topic (`echo_topic`), by call id: the draft's subscription, whether
  /// the call is answered, whether the draft has changed since it was made; its ticket held until both
  priv echo_waits : Map[Int, (Int, Bool, Bool)]
  /// Told of each subscription made (its id, its topic's name, None) and of its first message (its value, or None
  /// when it could not be read): Client::time_topics
  priv mut timing : ((Int, String, Json?, Bool) -> Unit)?
  /// where the app's attention is, as told last (`client.focus`): told again to a core started anew, which would else
  /// take the app for out of view. The app's own (shown, in front, the workspace) and the chat it shows are told by
  /// separate calls and kept apart: keeping only the last call lost the other, and a chat's call alone left a new core
  /// taking the app for out of view, so nothing it showed was read again (未读消不掉, 2026-11-10)
  priv mut focus : Json?
  /// the chat shown, as told last (`client.focus {chat}`; none once it is left): told again after `focus`
  priv mut focus_chat : Json?
  /// While the device's performance record is kept (@hostapi.perf_recording): each call's name by its id until it is
  /// answered, so what the core says of it is put to its name (Client::perf_name)
  priv perf_calls : Map[Int, String]
  /// What the ids let go of last were (a subscription ended, a stream cancelled: `topic chats`, `call screen.view`), the
  /// last `gone_kept`: what a message come for one of them after is counted as (Client::unheld)
  priv let_go_of : Map[Int, String]
  /// The messages come for ids nothing held, let be unread (Client::unheld), by what the id was: how many, their
  /// length in all (Client::unheld_said)
  priv unheld_counts : Map[String, (Int, Int)]
  /// Of a topic (its name, its JSON as asked), how many values of its name are kept at most as they are let go of, to
  /// be asked again with their version (Client::keep): 0, none
  priv mut keeps : (String, Json) -> Int
  /// The values kept so, by their subscriptions' lookup key: the value, the version the core said it is (`{id, v}`) and
  /// its topic's name, the oldest first (the last `kept_most`, and of each name as many as `keeps` says). One may be kept while its topic is subscribed again (the version of the
  /// one let go of came after the new one's first value): a version is made of the value alone, and what is kept is
  /// only ever taken where the core says the topic's value is that version, so it is never taken for another.
  priv kept : Map[String, (Json, String, String)]
  /// What the core is told before a topic is asked (its name, its JSON as asked), each time it is (Client::tells_before)
  priv mut tells : (String, Json) -> Array[(String, Json)]
}

///|
/// A client whose messages go out through `send` (one JSON message each).
/// `send_bytes` sends one with bytes beside it (by default the bytes are dropped: a client that never sends any).
pub fn Client::new(
  send : (String) -> Unit,
  send_bytes? : (String, Bytes) -> Unit = fn(s, _) { send(s) },
) -> Client {
  {
    send,
    send_bytes,
    subs: {},
    by_key: {},
    calls: {},
    progress: {},
    quiet_names: {},
    quiet_calls: {},
    unread_names: {},
    unread_calls: {},
    said_names: {},
    said_calls: {},
    next_id: 1,
    epoch: 0,
    generation: 0,
    beside: None,
    version: 0,
    fatal: None,
    fatal_said: @signals.signal(0),
    start_wait: fn(_) { 0 },
    end_wait: fn(_) {  },
    focus: None,
    focus_chat: None,
    call_waits: {},
    sub_waits: {},
    echo_waits: {},
    timing: None,
    perf_calls: {},
    let_go_of: {},
    unheld_counts: {},
    keeps: fn(_, _) { 0 },
    kept: {},
    tells: fn(_, _) { [] },
  }
}

///|
/// What the core is told before a topic is asked (`f` of its name and its JSON as asked: calls, each its name and its
/// params, none read the answer of), each time it is asked: as it is first read, asked anew (Client::refresh_topic), and
/// of a core started again (Client::restarted), which knows nothing of what the one before was told. A chat list's
/// window (`chats.window`: how many of its rows go out, no part of its topic) goes so before the list. Said once, as
/// the app starts.
pub fn Client::tells_before(self : Client, f : (String, Json) -> Array[(String, Json)]) -> Unit {
  self.tells = f
}

///|
/// The topics `f` gives a number above 0 (by name and JSON as asked) keep their value as they are let go of: the core
/// is told so (`keep`) and answers with its version, and the topic asked again says it (`have`), the core answering
/// `same`, no value, where it has not changed meanwhile, and what changed from it where it has (`{id, delta, kept}`,
/// applied to the value kept); the value kept is its value then, as it was (nothing parsed, nothing made of it anew).
/// The number is how many values of the topic's name are kept at a time, the oldest of that name forgotten past it
/// (a chat's, the largest the app holds, a few: its count bounded by itself), all of them together `kept_most`. Said
/// once, as the app starts.
///
/// The core it speaks to is always of the same build, so it knows `keep` (an unsubscribe answered `{id, v}`, the
/// subscription held till then): a native app's core is packed in it (`core.hbc`), and the web's runs in a worker of
/// the page's own build, which talks only to a core of that build (web/src/core/worker.ts: its channel by the build,
/// an older build's worker retiring and its pages loaded again onto the new one).
pub fn Client::keep(self : Client, f : (String, Json) -> Int) -> Unit {
  self.keeps = f
}

///|
/// How many values are kept (Client::keep), of every name together, the oldest forgotten.
let kept_most : Int = 64

///|
/// What the app times of its topics (still.fail's Android app's bar_switch): `f(id, topic,
/// None, false)` as a subscription is made and asked of the core, `f(id, topic, value, true)` as its first message is
/// taken (its value; None: an error). Nothing here reads a clock: the times are the caller's.
pub fn Client::time_topics(self : Client, f : ((Int, String, Json?, Bool) -> Unit)?) -> Unit {
  self.timing = f
}

///|
/// What is asked of the core is awaited until it is answered (a call) or first read (a subscription): `start` is told
/// what it is and gives a ticket, `end` is given the ticket back (mbui's `@ui.runtime().outside_start` and
/// `outside_end`, so a screen is not settled while it waits on the core).
pub fn Client::track(self : Client, start : (String) -> Int, end : (Int) -> Unit) -> Unit {
  self.start_wait = start
  self.end_wait = end
}

///|
fn Client::end_call_wait(self : Client, id : Int) -> Unit {
  match self.call_waits.get(id) {
    Some(t) => {
      self.call_waits.remove(id)
      (self.end_wait)(t)
    }
    None => ()
  }
}

///|
fn Client::end_sub_wait(self : Client, id : Int) -> Unit {
  match self.sub_waits.get(id) {
    Some(t) => {
      self.sub_waits.remove(id)
      (self.end_wait)(t)
    }
    None => ()
  }
}

///|
fn topic_json(topic : String, params : Map[String, Json]) -> Json {
  let m : Map[String, Json] = { "topic": Json::string(topic) }
  for k, v in params {
    m[k] = v
  }
  Json::object(m)
}

///|
/// Find an existing subscription without constructing and escaping its whole JSON object on every read. Each part is
/// tagged and length-prefixed. `topic_json` lets a parameter named `topic` replace the supplied name, so do that here
/// too and keep the remaining parameters in the same order as the object sent to the core.
fn subscribe_key(topic : String, params : Map[String, Json]) -> String {
  let b = StringBuilder()
  let part = fn(kind : Char, x : String) {
    b.write_char(kind)
    b.write_string(x.length().to_string())
    b.write_char(':')
    b.write_string(x)
  }
  match params.get("topic") {
    Some(String(x)) => part('s', x)
    Some(v) => part('j', v.stringify())
    None => part('s', topic)
  }
  for k, v in params {
    if k != "topic" {
      part('k', k)
      match v {
        String(x) => part('s', x)
        _ => part('j', v.stringify())
      }
    }
  }
  b.to_string()
}

///|
/// A topic's name (its `topic`), without its params.
fn topic_name(t : Json) -> String {
  match t {
    Object(m) =>
      match m.get("topic") {
        Some(String(n)) => n
        _ => ""
      }
    _ => ""
  }
}

///|
/// An edit of a draft the core keeps (a form's), by call, and the topic that draft is read from: the call is answered
/// at once, the draft as the station has it comes after. What is asked is awaited until the draft has come too (a
/// scripted run's `answered NAME`, a screen settled), so what depends on the draft (a button it lets be pressed) is
/// there when the step after looks.
fn echo_topic(name : String) -> String? {
  match name {
    "agentEnv.form.edit" => Some("agentEnvForm")
    "profile.flow.edit" => Some("profileFlow")
    _ => None
  }
}

///|
/// The subscription to the draft an edit `name` with `params` changes (`echo_topic`: its topic, the same station and
/// form), if the client has one.
fn Client::echo_of(self : Client, name : String, params : Json) -> Sub? {
  guard echo_topic(name) is Some(topic) else { return None }
  guard params is Object(p) else { return None }
  for _, s in self.subs {
    guard s.topic is Object(t) else { continue }
    if topic_name(s.topic) == topic && t.get("station") == p.get("station") && t.get("form") == p.get("form") {
      return Some(s)
    }
  }
  None
}

///|
/// The subscription to `topic` with `params`: made (and asked of the core) the first time, the same one after that,
/// so a view can call this every frame. Repeated calls share one direct hold, not independently releasable handles;
/// `unsubscribe` releases that direct hold, while any graph or legacy readers continue to hold the topic.
pub fn Client::subscribe(
  self : Client,
  topic : String,
  params? : Map[String, Json] = {},
) -> Sub {
  self.subscribe_as(topic, params, true)
}

///|
/// Read a topic through the signal graph or a legacy source; unlike `subscribe`, this does not hold a raw Sub.
pub fn Client::follow_topic(self : Client, topic : String, params? : Map[String, Json] = {}) -> Sub {
  self.subscribe_as(topic, params, false).followed()
}

///|
fn Client::subscribe_as(self : Client, topic : String, params : Map[String, Json], direct : Bool) -> Sub {
  let look = subscribe_key(topic, params)
  match self.by_key.get(look) {
    Some(s) => {
      if direct { s.direct = true }
      s
    }
    None => {
      let t = topic_json(topic, params)
      let key = t.stringify()
      let id = self.next_id
      self.next_id += 1
      let from = self.from_of(t)
      let s = { id, topic: t, value: None, error: None, version: 0, waiting: false, key, look, changes: @signals.signal(0), manual: false, direct, retiring: false, value_generation: self.generation, from, ending: false, keeping: false }
      self.subs[id] = s
      self.by_key[look] = s
      self.ask(s)
      match self.timing {
        Some(f) => f(id, topic, None, false)
        None => ()
      }
      s
    }
  }
}

///|
/// Of topic `t` with a `limit` (the first rows of a list, more of them asked now), a subscription to it that has a
/// value with other params alike but its limit: what its first value comes as what changed from.
fn Client::from_of(self : Client, t : Json) -> Int? {
  guard t is Object(want) && want.get("limit") is Some(_) else { return None }
  let mut best : Sub? = None
  for _, s in self.subs {
    guard !s.ending && s.value is Some(_) && s.topic is Object(has) && has.length() == want.length() else { continue }
    let alike = want.iter().all(fn(kv) { kv.0 == "limit" || has.get(kv.0) == Some(kv.1) })
    if alike && has.get("limit") is Some(_) && (best is None || best.map_or(0, fn(b) { b.id }) < s.id) {
      best = Some(s)
    }
  }
  best.map(fn(s) { s.id })
}

///|
fn Client::watch_retirement(self : Client, s : Sub) -> Unit {
  let epoch = self.epoch
  let id = s.id
  s.changes.on_unwatched(fn() {
    @signals.after_flush(fn() {
      if self.epoch == epoch {
        match self.subs.get(id) {
          Some(current) => {
            current.clear_retirement_watch()
            self.retire_if_unused(current)
          }
          None => ()
        }
      }
    })
  })
}

///|
/// Look up an existing subscription without acquiring it.
pub fn Client::peek_topic(self : Client, topic : String, params? : Map[String, Json] = {}) -> Sub? {
  self.by_key.get(subscribe_key(topic, params))
}

///|
/// The core generation and whether this topic's retained value came from it. This lookup acquires no subscription.
pub fn Client::topic_generation(self : Client, topic : String, params? : Map[String, Json] = {}) -> (Int, Bool) {
  let fresh = match self.peek_topic(topic, params~) {
    Some(s) => s.value_generation == self.generation
    None => true
  }
  (self.generation, fresh)
}

///|
fn Client::ask(self : Client, s : Sub) -> Unit {
  for told in (self.tells)(topic_name(s.topic), s.topic) {
    self.call(told.0, params=told.1) |> ignore
  }
  self.end_sub_wait(s.id)
  self.sub_waits[s.id] = (self.start_wait)("core: \{s.key}")
  perf_out("sub " + topic_name(s.topic))
  // keyed: lists the core keys (threads, chats…) change item by item rather than as whole lists (delta.mbt applies both)
  let m : Map[String, Json] = {
    "id": Json::number(s.id.to_double()),
    "subscribe": s.topic,
    "keyed": Json::boolean(true),
  }
  match s.from {
    Some(f) => m["from"] = Json::number(f.to_double())
    None => ()
  }
  // (its value kept as it was let go of: the version of it, for the core to answer `same` where it is that still)
  match self.kept.get(s.look) {
    Some((_, v, _)) => m["have"] = Json::string(v)
    None => ()
  }
  (self.send)(Json::object(m).stringify())
}

///|
/// Ask for a fresh value while keeping the same Sub and its readers. A new wire id discards replies to the old ask.
pub fn Client::refresh_topic(self : Client, topic : String, params? : Map[String, Json] = {}) -> Unit {
  match self.by_key.get(subscribe_key(topic, params)) {
    Some(s) => {
      let old_id = s.id
      self.end_sub_wait(old_id)
      s.clear_retirement_watch()
      self.subs.remove(old_id)
      self.let_go(old_id, "topic " + topic_name(s.topic))
      let id = self.next_id
      self.next_id += 1
      s.id = id
      self.subs[id] = s
      let pending = self.echo_waits.to_array()
      for p in pending {
        let (call, (sub, answered, seen)) = p
        if sub == old_id { self.echo_waits[call] = (id, answered, seen) }
      }
      (self.send)(({ "id": Json::number(old_id.to_double()), "unsubscribe": true } : Json).stringify())
      self.ask(s)
      self.retire_if_unused(s)
    }
    None => ()
  }
}

///|
/// Release a direct subscriber. Other graph or legacy readers keep the subscription until they leave too.
pub fn Client::unsubscribe(self : Client, s : Sub) -> Unit {
  if self.subs.get(s.id) is Some(current) && physical_equal(current, s) {
    s.direct = false
    s.retiring = true
    self.retire_if_unused(s)
  }
}

///|
/// `s`'s first value come: the one it was asked from let go of, if it is waiting for that.
fn Client::came_from(self : Client, s : Sub) -> Unit {
  guard s.from is Some(f) else { return }
  s.from = None
  match self.subs.get(f) {
    Some(o) if o.ending && !self.subs.values().any(fn(x) { x.from == Some(f) }) => {
      self.subs.remove(f)
      self.let_go(f, "topic " + topic_name(o.topic))
      (self.send)(({ "id": Json::number(f.to_double()), "unsubscribe": true } : Json).stringify())
    }
    _ => ()
  }
}

///|
/// End a subscription once no reader holds it.
fn Client::end_subscription(self : Client, s : Sub) -> Unit {
  if self.subs.get(s.id) is Some(current) && physical_equal(current, s) {
    self.end_sub_wait(s.id)
    s.clear_retirement_watch()
    self.by_key.remove(s.look)
    s.changed(ended=true)
    // (one asked from it still waiting for its first value, which comes as what changed from this one's: kept till
    // then, Client::came_from)
    if self.subs.values().any(fn(o) { o.from == Some(s.id) }) {
      s.ending = true
      return
    }
    let m : Map[String, Json] = {
      "id": Json::number(s.id.to_double()),
      "unsubscribe": Json::boolean(true),
    }
    // (its value kept: let go of once the core says what it is, Client::take. Said so whether its first value has come
    // yet or not: what the app sends is what it means to do with it, never which came first, the core's answer or its
    // leaving (a replay, a slow core). What comes before the core's word of it is applied to it as ever; none come, none
    // kept, and it is asked again as ever)
    if s.error is None && (self.keeps)(topic_name(s.topic), s.topic) > 0 {
      s.ending = true
      s.keeping = true
      m["keep"] = Json::boolean(true)
      (self.send)(Json::object(m).stringify())
      return
    }
    self.subs.remove(s.id)
    self.let_go(s.id, "topic " + topic_name(s.topic))
    (self.send)(Json::object(m).stringify())
  }
}

///|
/// Ends a topic if it was asked, without asking the core for a topic the page never read.
pub fn Client::unsubscribe_topic(
  self : Client,
  topic : String,
  params? : Map[String, Json] = {},
) -> Unit {
  match self.by_key.get(subscribe_key(topic, params)) {
    Some(s) => {
      s.manual = false
      s.direct = false
      s.retiring = true
      self.retire_if_unused(s)
    }
    None => ()
  }
}

///|
/// A legacy Source reader left; a direct Sub holder and other graph readers retain their interests.
pub fn Client::leave_topic(self : Client, topic : String, params? : Map[String, Json] = {}) -> Unit {
  match self.by_key.get(subscribe_key(topic, params)) {
    Some(s) => {
      s.manual = false
      s.retiring = true
      self.retire_if_unused(s)
    }
    None => ()
  }
}

///|
/// A graph-owned reader went away. Preserve any legacy untracked hold, and any other graph reader of this Sub.
pub fn Client::release_topic(
  self : Client,
  topic : String,
  params? : Map[String, Json] = {},
) -> Unit {
  match self.by_key.get(subscribe_key(topic, params)) {
    Some(s) => {
      s.retiring = true
      self.retire_if_unused(s)
    }
    None => ()
  }
}

///|
fn Client::retire_if_unused(self : Client, s : Sub) -> Unit {
  if self.subs.get(s.id) is Some(current) && physical_equal(current, s) &&
    s.retiring && !s.manual && !s.direct {
    if s.changes.watched() {
      // Only a pending retirement needs this callback. Installing it on every Sub would retain the Client in a cycle.
      self.watch_retirement(s)
    } else {
      self.end_subscription(s)
    }
  }
}

///|
/// Calls `name` with `params`; `on_done` gets its answer (`ok`) or the core's error (`{code, message, status?}`).
/// Returns the call's id. A value the call sends before its answer (how far it has got) is passed on only to a
/// `stream`'s `on_value`.
/// `bytes` go beside the call (a file's part: `station.upload.part`).
/// No `on_done`: nobody reads its answer (a call told and let go: `client.focus`, `prefs.set`). It goes as any call,
/// its id its own; its answer, taken as it comes, runs nothing, builds nothing and is awaited by nothing (Client::
/// call_said), as one said unread by its name (Client::unread). One that reads it says so with an `on_done` that does
/// something: an empty one is no reader (detlint's `empty-on-done`).
pub fn Client::call(
  self : Client,
  name : String,
  params? : Json = Json::object({}),
  bytes? : Bytes? = None,
  on_done? : (Result[Json, Json]) -> Unit,
) -> Int {
  if name == "client.focus" {
    match params {
      Object(o) if o.contains("chat") => self.focus_chat = Some(params)
      // (left: only the chat it names, as the core lets go only of that one; another may have been told since)
      Object(o) if o.contains("left") =>
        match (self.focus_chat, o.get("left")) {
          (Some(Object(was)), Some(Object(left))) =>
            match was.get("chat") {
              Some(Object(c)) if c.get("station") == left.get("station") &&
                c.get("session") == left.get("session") => self.focus_chat = None
              _ => ()
            }
          _ => ()
        }
      _ => self.focus = Some(params)
    }
  }
  let id = self.next_id
  self.next_id += 1
  match on_done {
    Some(f) => self.calls[id] = f
    None => ()
  }
  // (its name, for what its answer is in the record and in a hang: Client::perf_name)
  self.perf_calls[id] = name
  if perf_counts() {
    perf_out(name)
  }
  // (one whose answer nobody reads is awaited by nothing: its answer, taken as it comes, asks for no frame)
  if on_done is None || self.unread_names.contains(name) {
    self.unread_calls[id] = true
  } else {
    self.call_waits[id] = (self.start_wait)("core: \{name} (call \{id})")
  }
  // (one whose answer changes only signals: taken as it comes, what read them built again, nothing else)
  if self.said_names.contains(name) {
    self.said_calls[id] = true
  }
  match self.echo_of(name, params) {
    Some(e) => self.echo_waits[id] = (e.id, false, false)
    None => ()
  }
  let m : Map[String, Json] = {
    "id": Json::number(id.to_double()),
    "call": Json::string(name),
    "params": params,
  }
  match bytes {
    Some(b) => (self.send_bytes)(Json::object(m).stringify(), b)
    None => (self.send)(Json::object(m).stringify())
  }
  id
}

///|
/// Calls `name` like `call`, for a call whose answer comes with bytes beside
/// it (a picture, a file's contents): `on_done` gets them with the answer.
pub fn Client::call_bytes(
  self : Client,
  name : String,
  params? : Json = Json::object({}),
  on_done~ : (Result[(Json, Bytes?), Json]) -> Unit,
) -> Int {
  self.call(name, params~, on_done=fn(r) {
    match r {
      Ok(j) => on_done(Ok((j, self.beside)))
      Err(e) => on_done(Err(e))
    }
  })
}

///|
/// Calls `name` like `call`, for a call that says how it goes before its answer (`station.preview` with `stream`: an
/// answer's head, then each piece of its body with the bytes beside it): `on_value` gets each such value and the bytes
/// beside it, then `on_done` the answer. Returns the call's id (`cancel` stops it).
pub fn Client::stream(
  self : Client,
  name : String,
  params? : Json = Json::object({}),
  bytes? : Bytes? = None,
  on_value~ : (Json, Bytes?) -> Unit,
  on_done? : (Result[Json, Json]) -> Unit,
) -> Int {
  let id = self.next_id
  self.progress[id] = on_value
  match self.quiet_names.get(name) {
    Some(f) => self.quiet_calls[id] = f
    None => ()
  }
  // (its values are read as they come: awaited till its answer, whether that is read or not)
  self.call(name, params~, bytes~, on_done=fn(r) {
    self.progress.remove(id)
    self.quiet_calls.remove(id)
    match on_done {
      Some(f) => f(r)
      None => ()
    }
  })
}

///|
/// Calls `name` like `stream`, for a call whose answer comes with bytes beside it (`station.file` with `progress`: how
/// much of the file has come, then the file): `on_done` gets them with the answer.
pub fn Client::stream_bytes(
  self : Client,
  name : String,
  params? : Json = Json::object({}),
  on_value~ : (Json, Bytes?) -> Unit,
  on_done~ : (Result[(Json, Bytes?), Json]) -> Unit,
) -> Int {
  self.stream(name, params~, on_value~, on_done=fn(r) {
    match r {
      Ok(j) => on_done(Ok((j, self.beside)))
      Err(e) => on_done(Err(e))
    }
  })
}

///|
/// A call that says how it goes (`stream`) stopped in the core: nothing more of it comes, its answer included.
pub fn Client::cancel(self : Client, id : Int) -> Unit {
  if self.progress.contains(id) {
    self.progress.remove(id)
    self.quiet_calls.remove(id)
    self.calls.remove(id)
    self.let_go(id, "call " + self.perf_calls.get(id).unwrap_or("?"))
    self.perf_calls.remove(id)
    self.end_call_wait(id)
    let m : Map[String, Json] = { "id": Json::number(id.to_double()), "cancel": Json::boolean(true) }
    (self.send)(Json::object(m).stringify())
  }
}

///|
/// Whether message `m` is a topic's change alone, its value or what changed of it (its first too: the runtime's wait
/// for it ended as it is taken, Runtime::outside_end being only that; no edit's draft come with it): what it changes is
/// said by its topic's signal and nothing else (Sub::changed), so it may be taken as it comes, before the frame decides
/// what it does (@ui.on_message_said). (A chat opened was built twice for its first values, taken by the frame: the
/// frame it was opened in again, or the next whole, 2026-10-30.)
pub fn Client::topic_said(self : Client, m : Map[String, Json]) -> Bool {
  if m.contains("fatal") {
    return false
  }
  let id = match m.get("id") {
    Some(Number(d, ..)) => d.to_int()
    _ => return false
  }
  match self.subs.get(id) {
    Some(s) =>
      !self.echo_waits.values().any(fn(w) { w.0 == id }) &&
      (
        m.contains("value") ||
        m.contains("delta") ||
        m.contains("error") ||
        m.contains("waiting") ||
        m.contains("same") ||
        (s.keeping && m.contains("v"))
      )
    None => false
  }
}

///|
/// The values of a call `name` (a `stream`'s) for which `f` says true change nothing a frame reads: what takes them
/// hands them on (a decoder's frame, a sound's packet) and keeps what it counts where no build reads it as it comes. So
/// they may be taken as they come, before the frame decides what it does (Client::call_said): a stream of them builds
/// nothing (a remote screen's frames and sound, sfpages' screen_value_quiet). Said once, as the app starts.
pub fn Client::quiet(self : Client, name : String, f : (Json) -> Bool) -> Unit {
  self.quiet_names[name] = f
}

///|
/// Whether the call this client made as `id` is one whose answer nobody reads (Client::call: no on_done, or unread):
/// awaited by nothing, so a scripted run cannot wait for its answer (src/sfreplay/emit.mbt writes no `answered` line
/// for it). Asked as the call goes out, before its answer.
fn Client::call_unread(self : Client, id : Int) -> Bool {
  self.unread_calls.contains(id)
}

///|
/// Nobody reads the answer of a call `name` (a call told and let go: `screen.ack`): nothing awaits it (no wait of the
/// runtime's) and it changes nothing a frame reads, so it may be taken as it comes (Client::call_said). Said once, as
/// the app starts.
pub fn Client::unread(self : Client, name : String) -> Unit {
  self.unread_names[name] = true
}

///|
/// Whether call `name`'s answers are taken as they come: said (Client::said) or read by nobody (Client::unread).
pub fn Client::taken_as_they_come(self : Client, name : String) -> Bool {
  self.said_names.contains(name) || self.unread_names.contains(name)
}

///|
/// The answer of a call `name` changes only signals (what is done with it sets them and nothing else a frame reads:
/// a draft's words told, `composer.text`), so it may be taken as it comes (Client::call_said): what read those signals
/// is built again, nothing else; awaited as any call. Said once, as the app starts.
pub fn Client::said(self : Client, name : String) -> Unit {
  self.said_names[name] = true
}

///|
/// Whether message `m` is a call's alone and changes nothing a frame reads but its signals: a value of a call that says
/// it changes nothing (Client::quiet), the answer of one whose answer nobody reads (Client::unread, its wait ended with
/// it) or of one whose answer changes only signals (Client::said),
/// so it may be taken as it comes, before the frame decides what it does (@ui.on_message_said).
pub fn Client::call_said(self : Client, m : Map[String, Json]) -> Bool {
  if m.contains("fatal") {
    return false
  }
  let id = match m.get("id") {
    Some(Number(d, ..)) => d.to_int()
    _ => return false
  }
  if self.subs.contains(id) {
    return false
  }
  if m.contains("ok") || m.contains("error") {
    return (self.unread_calls.contains(id) || self.said_calls.contains(id)) && !self.echo_waits.contains(id)
  }
  match (m.get("value"), self.quiet_calls.get(id)) {
    (Some(v), Some(f)) => self.progress.contains(id) && f(v)
    _ => false
  }
}

///|
/// How many of the ids let go of last are kept by what they were (Client::let_go).
let gone_kept : Int = 64

///|
/// Id `id` let go of (its subscription ended, its stream cancelled), `what` it was: kept among the last `gone_kept`,
/// for what the core still says to it to be counted by (Client::unheld).
fn Client::let_go(self : Client, id : Int, what : String) -> Unit {
  self.let_go_of[id] = what
  if self.let_go_of.length() > gone_kept {
    match self.let_go_of.keys().head() {
      Some(first) => self.let_go_of.remove(first)
      None => ()
    }
  }
}

///|
/// The id of a message that begins `{"id":<digits>,"value":` or `{"id":<digits>,"delta":`, read from its head alone:
/// as the core writes a topic's value, what changed of it, and a call's value before its answer (client/core-ts
/// store.ts `to`, JSON.stringify's order). None: not written so (read whole, as any message).
fn head_id(text : String) -> Int? {
  let lead = "{\"id\":"
  guard text.has_prefix(lead) else { return None }
  let n = text.length()
  let mut i = lead.length()
  let mut id = 0
  let from = i
  while i < n && i - from < 9 {
    let ch = text.unsafe_get(i).to_int()
    if ch < 48 || ch > 57 {
      break
    }
    id = id * 10 + (ch - 48)
    i += 1
  }
  guard i > from else { return None }
  let rest = text.exact_view(start=i)
  if rest.has_prefix(",\"value\":") || rest.has_prefix(",\"delta\":") {
    Some(id)
  } else {
    None
  }
}

///|
/// Whether message `text` is a value, or what changed, for an id nothing of this client holds (no subscription, one
/// let go of and kept for another's first value neither, no call awaiting its answer, no stream): the core said it
/// before it was told the id was let go of (a topic left as its value was on its way, a stream cancelled), and taking
/// it changes nothing. Told from its head alone, the message not read: one such was read whole twice and the frame
/// built again for it, 13 to 23 ms each reading on a phone (2026-11-10). Counted by what its id was
/// (Client::unheld_said).
pub fn Client::unheld(self : Client, text : String) -> Bool {
  guard head_id(text) is Some(id) else { return false }
  if self.subs.contains(id) ||
    self.calls.contains(id) ||
    self.progress.contains(id) ||
    self.echo_waits.contains(id) ||
    self.call_waits.contains(id) ||
    self.sub_waits.contains(id) {
    return false
  }
  let what = self.let_go_of.get(id).unwrap_or("?")
  let (k, b) = self.unheld_counts.get(what).unwrap_or((0, 0))
  self.unheld_counts[what] = (k + 1, b + text.length())
  true
}

///|
/// The messages let be unread since this was last asked (Client::unheld), by what their ids were, the most first (of as
/// many, by name): how many and their length in all. Begun again.
pub fn Client::unheld_said(self : Client) -> Array[(String, Int, Int)] {
  let out = self.unheld_counts.to_array().map(fn(e) { (e.0, e.1.0, e.1.1) })
  out.sort_by(fn(a, b) {
    let by = b.1.compare(a.1)
    if by != 0 {
      by
    } else {
      a.0.compare(b.0)
    }
  })
  self.unheld_counts.clear()
  out
}

///|
/// One message from the core, as its JSON text. False when it is not JSON.
pub fn Client::receive(self : Client, text : String) -> Bool {
  let msg = @json.parse(text) catch { _ => return false }
  self.receive_json(msg)
  true
}

///|
/// One message from the core, and the bytes beside it if it has any.
pub fn Client::receive_json(
  self : Client,
  msg : Json,
  bytes? : Bytes? = None,
) -> Unit {
  self.beside = bytes
  self.take(msg)
  self.beside = None
}

///|
fn Client::take(self : Client, msg : Json) -> Unit {
  guard msg is Object(m) else { return }
  match m.get("fatal") {
    Some(reason) => {
      self.fatal = Some(
        match reason {
          String(s) => s
          r => r.stringify()
        },
      )
      self.fatal_said.set(self.fatal_said.untracked() + 1)
      // What was asked of this core is not answered by the next one.
      let calls = self.calls.to_array()
      self.calls.clear()
      self.unread_calls.clear()
      self.said_calls.clear()
      self.echo_waits.clear()
      for c in calls {
        self.end_call_wait(c.0)
      }
      // the subscriptions wait for the next core (restarted asks them again)
      let subs = self.sub_waits.keys().collect()
      for id in subs {
        self.end_sub_wait(id)
      }
      // (in the app's words; the reason is the core's own, on_failed)
      let err = Json::object({
        "code": Json::string("core_restarted"),
        "message": Json::string(restarted_text.val),
      })
      for c in calls {
        (c.1)(Err(err))
      }
      self.version += 1
      return
    }
    None => ()
  }
  let id = match m.get("id") {
    Some(Number(d, ..)) => d.to_int()
    _ => return
  }
  match self.subs.get(id) {
    Some(s) if s.ending => {
      // (let go of keeping its value: the core's last word of it, the version of what it holds now)
      if s.keeping && m.get("v") is Some(said) {
        self.subs.remove(id)
        self.let_go(id, "topic " + topic_name(s.topic))
        match (said, s.value) {
          (String(v), Some(value)) => self.keep_value(s, value, v)
          _ => ()
        }
        return
      }
      // (let go of, kept as what one asked from it reads, or as what is kept: its value as the core has it)
      match (m.get("value"), m.get("delta"), m.get("error"), s.value) {
        (_, _, Some(_), _) => s.value = None
        (Some(v), _, _, _) => s.value = Some(v)
        (_, Some(Array(ops)), _, Some(v)) => s.value = Some(apply_delta(v, ops))
        _ => ()
      }
    }
    Some(s) => {
      if m.get("waiting") is Some(True) && s.value is None && s.error is None {
        // (no value of it yet: what shows it shows what is to come, the core's wait for it going on)
        s.waiting = true
        self.version += 1
        s.changes.set(-2)
        return
      }
      // (its first message: asked with the version of the value kept, that one, the core may say, is its value still.
      // Only the first looks: what is kept matters to nothing after it)
      let kept = if s.value is None && s.error is None {
        let k = self.kept.get(s.look)
        self.kept.remove(s.look)
        k
      } else {
        None
      }
      if m.get("same") is Some(True) {
        match kept {
          Some((v, _, _)) => {
            s.value = Some(v)
            s.error = None
          }
          None => {
            // (none kept by now, forgotten for more of its name let go of since: asked again, whole)
            self.ask(s)
            return
          }
        }
      } else {
      match (m.get("value"), m.get("delta"), m.get("error")) {
        (_, _, Some(e)) => {
          // The topic could not be read: the next message is a whole value, not a delta.
          s.value = None
          s.error = Some(e)
        }
        (Some(v), _, _) => {
          s.value = Some(v)
          s.error = None
        }
        (_, Some(Array(ops)), _) =>
          match (s.value, m.get("from")) {
            (Some(v), _) => s.value = Some(apply_delta(v, ops))
            // its first value, as what changed from the value kept as it was let go of (asked with its version)
            (None, _) if m.get("kept") is Some(True) =>
              match kept {
                Some((v, _, _)) => s.value = Some(apply_delta(v, ops))
                None => {
                  // (none kept by now, forgotten for more of its name let go of since: asked again, whole)
                  self.ask(s)
                  return
                }
              }
            // its first value, as what changed from what another of its subscriptions has
            (None, Some(Number(f, ..))) =>
              match self.subs.get(f.to_int()).bind(fn(o) { o.value }) {
                Some(v) => s.value = Some(apply_delta(v, ops))
                None => {
                  // (that one not had: asked again, whole)
                  s.from = None
                  self.ask(s)
                  return
                }
              }
            (None, _) => return
          }
        _ => return
      }
      }
      self.came_from(s)
      s.waiting = false
      s.value_generation = self.generation
      match self.timing {
        Some(f) if s.version == 0 => f(id, topic_name(s.topic), s.value, true)
        _ => ()
      }
      let first = s.version == 0
      s.version += 1
      self.version += 1
      // (its first value an answer: @signals.first_told)
      if first {
        @signals.first_told(fn() { s.changed() })
      } else {
        s.changed()
      }
      self.end_sub_wait(id)
      self.draft_came(id)
    }
    None =>
      // A call's answer; a value before it says how it goes (to a `stream`'s `on_value`)
      match (m.get("ok"), m.get("error"), m.get("value")) {
        (Some(ok), _, _) => self.answer(id, Ok(ok))
        (None, Some(e), _) => self.answer(id, Err(e))
        (None, None, Some(v)) =>
          match self.progress.get(id) {
            Some(f) => {
              self.version += 1
              f(v, self.beside)
            }
            None => ()
          }
        _ => ()
      }
  }
}

///|
/// What a message of the core's is, for the performance record: `topic <name> value|delta|error|waiting` (a subscription's),
/// `answer <call>` (a call's answer), `progress <call>` (a value before it), `?` else.
pub fn Client::perf_name(self : Client, msg : Json) -> String {
  guard msg is Object(m) else { return "?" }
  let id = match m.get("id") {
    Some(Number(d, ..)) => d.to_int()
    _ => return if m.contains("fatal") { "fatal" } else { "?" }
  }
  match self.subs.get(id) {
    Some(s) => {
      let how = if m.contains("error") {
        "error"
      } else if m.contains("value") {
        "value"
      } else if m.contains("waiting") {
        "waiting"
      } else if m.contains("same") {
        "same"
      } else if m.contains("v") {
        "kept"
      } else {
        "delta"
      }
      "topic \{topic_name(s.topic)} \{how}"
    }
    None => {
      let name = self.perf_calls.get(id).unwrap_or("?")
      if m.contains("ok") || m.contains("error") {
        self.perf_calls.remove(id)
        "answer " + name
      } else {
        "progress " + name
      }
    }
  }
}

///|
/// No name kept of a call nothing more comes of (the record turned off): a call still answering keeps its own, for what
/// its progress is in a hang (`progress ?` once each summary forgot them all, 2026-11-10).
pub fn Client::perf_forget(self : Client) -> Unit {
  let gone = self.perf_calls.keys().filter(fn(id) { !self.calls.contains(id) }).to_array()
  for id in gone {
    self.perf_calls.remove(id)
  }
}

///|
fn Client::answer(self : Client, id : Int, r : Result[Json, Json]) -> Unit {
  self.unread_calls.remove(id)
  self.said_calls.remove(id)
  match self.echo_waits.get(id) {
    // (an edit answered before its draft came: awaited still, until it does; refused: nothing to come)
    Some((sub, _, false)) if r is Ok(_) => self.echo_waits[id] = (sub, true, false)
    Some(_) => {
      self.echo_waits.remove(id)
      self.end_call_wait(id)
    }
    None => self.end_call_wait(id)
  }
  match self.calls.get(id) {
    Some(f) => {
      self.calls.remove(id)
      self.version += 1
      f(r)
    }
    None => ()
  }
}

///|
/// After the core was started again (a fatal): every subscription asked of the new core, under its own id. Their
/// values stay until the new core's first value replaces them.
pub fn Client::restarted(self : Client) -> Unit {
  // A web worker can rejoin without a preceding fatal. Its former core cannot answer the calls it held.
  let calls = self.calls.to_array()
  calls.sort_by_key(fn(c) { c.0 })
  self.calls.clear()
  self.progress.clear()
  self.quiet_calls.clear()
  self.unread_calls.clear()
      self.said_calls.clear()
  self.echo_waits.clear()
  @signals.start_batch()
  self.generation += 1
  self.fatal = None
  self.fatal_said.set(self.fatal_said.untracked() + 1)
  let err : Json = { "code": "core_restarted", "message": Json::string(restarted_text.val) }
  for c in calls {
    self.end_call_wait(c.0)
    (c.1)(Err(err))
  }
  // (a new core has none of them: those let go of are gone, each asked whole)
  for s in self.subs.values().filter(fn(s) { s.ending }).to_array() {
    self.subs.remove(s.id)
  }
  let subs = self.subs.values().to_array()
  subs.sort_by_key(fn(s) { s.id })
  for s in subs {
    s.from = None
    self.ask(s)
  }
  for focus in [self.focus, self.focus_chat] {
    match focus {
      Some(p) => self.call("client.focus", params=p) |> ignore
      None => ()
    }
  }
  @signals.end_batch()
}

///|
/// Everything forgotten, as a new client: no subscription, no call waiting, ids from 1 (a Replay attached to the
/// app's client starts it so).
pub fn Client::reset(self : Client) -> Unit {
  // Clear the old client before telling readers: a live reader may immediately subscribe again.
  let ended = self.subs.values().to_array()
  ended.sort_by_key(fn(s) { s.id })
  let calls = self.calls.to_array()
  calls.sort_by_key(fn(c) { c.0 })
  let call_waits = self.call_waits.values().to_array()
  let sub_waits = self.sub_waits.values().to_array()
  @signals.start_batch()
  self.epoch += 1
  self.generation += 1
  self.subs.clear()
  self.by_key.clear()
  self.calls.clear()
  self.progress.clear()
  self.quiet_calls.clear()
  self.unread_calls.clear()
      self.said_calls.clear()
  self.echo_waits.clear()
  self.call_waits.clear()
  self.sub_waits.clear()
  self.focus = None
  self.focus_chat = None
  self.kept.clear()
  self.next_id = 1
  self.beside = None
  self.version = 0
  self.fatal = None
  for ticket in call_waits {
    (self.end_wait)(ticket)
  }
  for ticket in sub_waits {
    (self.end_wait)(ticket)
  }
  for s in ended {
    s.clear_retirement_watch()
    s.changed(ended=true)
  }
  // A call on the former client can never answer on the new one. Complete it so its optimistic state can settle.
  let err : Json = { "code": "core_restarted", "message": Json::string(restarted_text.val) }
  for c in calls {
    (c.1)(Err(err))
  }
  @signals.end_batch()
}

///|
/// A message for the subscription `sub`: the edits of its draft answered by now are over (their tickets given back),
/// those not answered yet have seen it come.
fn Client::draft_came(self : Client, sub : Int) -> Unit {
  let over = []
  let seen = []
  for id, w in self.echo_waits {
    let (s, answered, _) = w
    if s == sub {
      if answered {
        over.push(id)
      } else {
        seen.push(id)
      }
    }
  }
  for id in seen {
    self.echo_waits[id] = (sub, false, true)
  }
  for id in over {
    self.echo_waits.remove(id)
    self.end_call_wait(id)
  }
}

///|
/// What a call in flight as the core failed says (StillFailCore.restartedText: the app's 核心已重启，请重试), set by the
/// app as it starts.
// kept across runs: the app's words, set once as it starts
pub let restarted_text : Ref[String] = { val: "The core restarted; try again" }

///|
/// The value of subscription `s` kept as it was let go of, `v` the version the core says it is (Client::keep): the
/// oldest of its topic's name forgotten past what `keeps` says of it, the oldest of all past `kept_most`.
fn Client::keep_value(self : Client, s : Sub, value : Json, v : String) -> Unit {
  let name = topic_name(s.topic)
  self.kept.remove(s.look)
  self.kept[s.look] = (value, v, name)
  let most = (self.keeps)(name, s.topic)
  let of_name = self.kept.iter().filter(fn(kv) { kv.1.2 == name }).map(fn(kv) { kv.0 }).collect()
  for i in 0..<(of_name.length() - most) {
    self.kept.remove(of_name[i])
  }
  if self.kept.length() > kept_most {
    match self.kept.keys().head() {
      Some(first) => self.kept.remove(first)
      None => ()
    }
  }
}
