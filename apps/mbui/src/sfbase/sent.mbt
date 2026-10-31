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
  local_marks.clear()
  local_sent_n.val = 0
  sent_pictures.clear()
}

///|
/// What was sent from here, in the list from the frame it was sent until the core's view has it (Chat.kt shows the
/// core's outbox; here the core's row comes a round trip later, and what is sent is on screen first): drawn as an
/// outbox entry of its words, by a key of its own ("local:n"); the first of this device's own rows not there when it
/// was sent (an outbox entry, or a message after the newest there then: what it became) is it, from then on by that
/// row's key. (An older page of the chat read meanwhile has the viewer's own messages in it, not there when it was sent
/// either: taken for it, it left the list and its words had nowhere to fly, pengxiao 2026-10-25.)
pub(all) struct LocalSent {
  row : Outgoing
  before : Map[String, Bool]
  newest : Double
}

///|
let local_sent_n : Ref[Int] = { val: 0 }

///|
/// The composer's marks in the words of what was sent from here (by its id: refs_sent_marks), which its row draws as
/// the references the core makes them (message_runs) until the core's row has them so.
let local_marks : Map[String, Array[(Int, Int)]] = {}

///|
/// The marks in the words of outbox row `o`: one sent from here not the core's yet (sent_local).
pub fn sent_marks(o : Outgoing) -> Array[(Int, Int)] {
  local_marks.get(o.id).unwrap_or([])
}

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
/// Where a message's image still going up is (its upload's id): no station has it yet (the core's views.ts goingUp).
pub fn upload_path(id : String) -> String {
  "upload:" + id
}

///|
/// The file a message's file is, here (the web's Files, keyed `upload ?? path`): one put up from here its upload, which
/// the core says of every one (`upload`), the same before it is up and after, whatever its path; any other the path its
/// station keeps it at. What tells its files apart as its row goes from what was sent from here to the core's outbox
/// entry and on to its message: what flies to each (flight.mbt), each one's box.
pub fn file_key(a : Attachment) -> String {
  if a.upload != "" {
    upload_path(a.upload)
  } else {
    a.path
  }
}

///|
/// The files still going up with words sent from here (each its id, name, size and an image's size: the uploads of
/// `composer.take`), as their row draws them until the core's has them (views.ts goingUp): an image or a video among
/// the message's files, named by its upload (what its picture flies to: a video as a card here, its still had nowhere
/// to land until the core's row came); any other a card saying how far (name, size, sent).
fn going_up(going : Array[Json]) -> (Array[Json], Array[(String, Int, Int)]) {
  let images : Array[Json] = []
  let cards : Array[(String, Int, Int)] = []
  for u in going {
    let s = Some(u)
    if preview_kind(text(s, "name")).0 is Some(KImage | KVideo) {
      let a : Map[String, Json] = {
        "name": Json::string(text(s, "name")),
        "path": Json::string(upload_path(text(s, "id"))),
        "size": Json::number(number(s, "size")),
        "upload": Json::string(text(s, "id")),
      }
      if number(s, "width") > 0.0 && number(s, "height") > 0.0 {
        a["width"] = Json::number(number(s, "width"))
        a["height"] = Json::number(number(s, "height"))
      }
      images.push(Json::object(a))
    } else {
      cards.push((text(s, "name"), number(s, "size").to_int(), number(s, "sent").to_int()))
    }
  }
  (images, cards)
}

///|
/// Words sent from chat `rk` (its station and session; `v` its view, None for one just made) are in its list now,
/// before the core has them (LocalSent), with its files up (`files`, each one put up from here naming its upload as the
/// core's row will: file_key), those still going up (`going`: going_up) and what it quotes (`quotes`, as the core's row
/// will have them), its references as the composer's marks (`marks`: refs_sent_marks). Its key, for what flies there
/// (flight.mbt).
pub fn sent_local(
  rk : String,
  v : ChatView?,
  words : String,
  files : Array[Json],
  going? : Array[Json] = [],
  quotes? : Array[Json] = [],
  marks? : Array[(Int, Int)] = [],
) -> String {
  local_sent_n.val += 1
  let id = "local:\{local_sent_n.val}"
  if marks.length() > 0 {
    local_marks[id] = marks
  }
  let (images, cards) = going_up(going)
  sending_of(rk).push({
    row: {
      id,
      text: words,
      attachments: (files + images).map(attachment_of),
      quotes: quotes.map(quote_of),
      state: "sending",
      error: "",
      joined: false,
      followed: false,
      seq: -1.0,
      time: None,
      waits: if going.length() > 0 { @sf.t("common.uploading") } else { "" },
      progress: None,
      uploads: cards,
      created_at: @ui.current().moment(),
      final: false,
    },
    // (a chat just made: none)
    before: match v {
      Some(v) => sent_before(v)
      None => Map::new()
    },
    newest: match v {
      Some(v) => v.messages.fold(init=-@double.infinity, fn(n, m) { if m.seq > n { m.seq } else { n } })
      None => -@double.infinity
    },
  })
  "o:" + id
}

///|
/// What was sent from chat `rk` (key: sent_local's) did not go: it leaves the list.
pub fn sent_local_gone(rk : String, key : String) -> Unit {
  let sending = sending_of(rk)
  match sending.search_by(fn(l) { "o:" + l.row.id == key }) {
    Some(i) => local_marks.remove(sending.remove(i).row.id)
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
