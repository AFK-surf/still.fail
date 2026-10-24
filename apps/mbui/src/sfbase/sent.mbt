// What was sent from here and is not in the core's view yet (the rule: the viewer's own message is in the list from the
// frame it is sent, before the core has it), by chat: what both frames' composers put in and both lists draw.

///|
/// What was sent from each chat (its station and session, `\u{1}` between), not in the core's view yet.
let local_sending : Map[String, Array[LocalSent]] = {}

///|
/// What was sent from chat `rk` and is not in its view yet, as its list takes it over.
pub fn sending_of(rk : String) -> Array[LocalSent] {
  match local_sending.get(rk) {
    Some(a) => a
    None => {
      let a : Array[LocalSent] = []
      local_sending[rk] = a
      a
    }
  }
}

///|
pub fn sent_reset() -> Unit {
  local_sending.clear()
  local_sent_n.val = 0
  sent_pictures.clear()
}

///|
/// What was sent from here, in the list from the frame it was sent until the core's view has it (Chat.kt shows the
/// core's outbox; here the core's row comes a round trip later, and what is sent is on screen first): drawn as an
/// outbox entry of its words, by a key of its own ("local:n"); the first of this device's own rows not there when it
/// was sent (an outbox entry, or the message it became) is it, from then on by that row's key.
pub(all) struct LocalSent {
  row : Outgoing
  before : Map[String, Bool]
}

///|
let local_sent_n : Ref[Int] = { val: 0 }

///|
pub fn local_sent(o : Outgoing) -> Bool {
  o.id.has_prefix("local:")
}

///|
/// The rows of the view `v` there when words were sent: an outbox entry's, a message's, and the outbox entry it was
/// (rows are keyed by it: row_keys).
fn sent_before(v : ChatView) -> Map[String, Bool] {
  let before : Map[String, Bool] = {}
  for o in v.outbox {
    before["o:" + o.id] = true
  }
  for m in v.messages {
    if m.outgoing != "" {
      before["o:" + m.outgoing] = true
    }
    before["m:" + m.ts] = true
  }
  before
}

///|
/// Words sent from chat `rk` (its station and session; `v` its view, None for one just made) are in its list now,
/// before the core has them (LocalSent). Its key, for what flies there (flight.mbt).
pub fn sent_local(rk : String, v : ChatView?, words : String, files : Array[Json]) -> String {
  local_sent_n.val += 1
  let id = "local:\{local_sent_n.val}"
  sending_of(rk).push({
    row: {
      id,
      text: words,
      attachments: files.map(attachment_of),
      quotes: [],
      state: "sending",
      error: "",
      joined: false,
      followed: false,
      seq: -1.0,
      time: None,
      waits: "",
      uploads: [],
      created_at: @ui.current().now,
      final: false,
    },
    // (a chat just made: none)
    before: match v {
      Some(v) => sent_before(v)
      None => Map::new()
    },
  })
  "o:" + id
}

///|
/// What was sent from chat `rk` (key: sent_local's) did not go: it leaves the list.
pub fn sent_local_gone(rk : String, key : String) -> Unit {
  let sending = sending_of(rk)
  match sending.search_by(fn(l) { "o:" + l.row.id == key }) {
    Some(i) => sending.remove(i) |> ignore
    None => ()
  }
}


///|
/// The pictures of images sent from here, as they were picked (ChatFiles.kt FileData.sentOf): by station and the name
/// it keeps the file under once up, or by the upload's id from when it starts going up (a message sent before it is up
/// names it so: Attachment.upload). What their messages draw, rather than the likeness and then the station's thumbnail
/// a round trip after the picture flew in; the bytes are kept for the run anyway (@ui.add_image).
pub let sent_pictures : Map[String, String] = {}

///|
pub fn sent_key(station : String, path : String) -> String {
  station + "\u{1}" + base_name(path)
}

///|
/// The picture `a` was sent from here as, if it was.
pub fn sent_picture(station : String, a : Attachment) -> String? {
  match sent_pictures.get(sent_key(station, a.path)) {
    Some(k) => Some(k)
    None => if a.upload != "" { sent_pictures.get("upload\u{1}" + a.upload) } else { None }
  }
}
