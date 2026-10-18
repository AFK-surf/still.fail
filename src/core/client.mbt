// One UI client of the still.fail core, over whatever carries the protocol's JSON (ember docs/client-core.md,
// Protocol): `{id, call, params}` and `{id, subscribe, keyed}` out; `{id, ok|error}`, `{id, value}`, `{id, delta}`
// and `{fatal}` in. Each subscription keeps its topic's current value, deltas applied (delta.mbt), and a version that
// changes with every message for it, so a view can tell what changed since its last frame without comparing values.
// The client is the UI thread's: messages come to `receive` in order on it (native.mbt drains the engine's queue).

///|
/// A subscription to a topic: `value` is its whole current value (None until the first, and after an error until the
/// next value), `error` the core's error for it while it could not be read, `version` changes with each message.
pub struct Sub {
  id : Int
  topic : Json
  mut value : Json?
  mut error : Json?
  mut version : Int
  priv key : String
}

///|
pub struct Client {
  priv send : (String) -> Unit
  priv subs : Map[Int, Sub]
  priv by_key : Map[String, Sub]
  priv calls : Map[Int, (Result[Json, Json]) -> Unit]
  priv mut next_id : Int
  /// the bytes beside the message being taken, if any
  priv mut beside : Bytes?
  /// Changes with every message that changed something (a sub's value or error, a call's answer).
  mut version : Int
  /// The core's reason, once it has failed (`{fatal}`); cleared by `restarted`.
  mut fatal : String?
}

///|
/// A client whose messages go out through `send` (one JSON message each).
pub fn Client::new(send : (String) -> Unit) -> Client {
  {
    send,
    subs: {},
    by_key: {},
    calls: {},
    next_id: 1,
    beside: None,
    version: 0,
    fatal: None,
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
/// The subscription to `topic` with `params`: made (and asked of the core) the first time, the same one after that,
/// so a view can call this every frame.
pub fn Client::subscribe(
  self : Client,
  topic : String,
  params? : Map[String, Json] = {},
) -> Sub {
  let t = topic_json(topic, params)
  let key = t.stringify()
  match self.by_key.get(key) {
    Some(s) => s
    None => {
      let id = self.next_id
      self.next_id += 1
      let s = { id, topic: t, value: None, error: None, version: 0, key }
      self.subs[id] = s
      self.by_key[key] = s
      self.ask(s)
      s
    }
  }
}

///|
fn Client::ask(self : Client, s : Sub) -> Unit {
  // keyed: lists the core keys (threads, chats…) change item by item rather than as whole lists (delta.mbt applies both)
  let m : Map[String, Json] = {
    "id": Json::number(s.id.to_double()),
    "subscribe": s.topic,
    "keyed": Json::boolean(true),
  }
  (self.send)(Json::object(m).stringify())
}

///|
/// Ends a subscription: the core stops sending it, and `subscribe` makes a new one.
pub fn Client::unsubscribe(self : Client, s : Sub) -> Unit {
  if self.subs.contains(s.id) {
    self.subs.remove(s.id)
    self.by_key.remove(s.key)
    let m : Map[String, Json] = {
      "id": Json::number(s.id.to_double()),
      "unsubscribe": Json::boolean(true),
    }
    (self.send)(Json::object(m).stringify())
  }
}

///|
/// Calls `name` with `params`; `on_done` gets its answer (`ok`) or the core's error (`{code, message, status?}`).
/// Returns the call's id. A value the call sends before its answer (how far it has got) is not passed on yet.
pub fn Client::call(
  self : Client,
  name : String,
  params? : Json = Json::object({}),
  on_done? : (Result[Json, Json]) -> Unit = fn(_) {  },
) -> Int {
  let id = self.next_id
  self.next_id += 1
  self.calls[id] = on_done
  let m : Map[String, Json] = {
    "id": Json::number(id.to_double()),
    "call": Json::string(name),
    "params": params,
  }
  (self.send)(Json::object(m).stringify())
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
      // What was asked of this core is not answered by the next one.
      let calls = self.calls.to_array()
      self.calls.clear()
      let err = Json::object({
        "code": Json::string("fatal"),
        "message": Json::string(self.fatal.unwrap()),
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
    Some(s) => {
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
          match s.value {
            Some(v) => s.value = Some(apply_delta(v, ops))
            None => return
          }
        _ => return
      }
      s.version += 1
      self.version += 1
    }
    None =>
      // A call's answer; a value before it (progress) is not taken yet.
      match (m.get("ok"), m.get("error")) {
        (Some(ok), _) => self.answer(id, Ok(ok))
        (None, Some(e)) => self.answer(id, Err(e))
        _ => ()
      }
  }
}

///|
fn Client::answer(self : Client, id : Int, r : Result[Json, Json]) -> Unit {
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
  self.fatal = None
  let subs = self.subs.values().to_array()
  subs.sort_by_key(fn(s) { s.id })
  for s in subs {
    self.ask(s)
  }
}
