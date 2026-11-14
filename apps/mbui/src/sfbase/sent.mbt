// What was sent from here and is not in the core's view yet (the rule: the viewer's own message is in the list from the
// frame it is sent, before the core has it), by chat: what both frames' composers put in and both lists draw.

///|
/// What was sent from each chat (its station and session, `\u{1}` between), not in the core's view yet: what reads it
/// follows it (a chat's list made of nodes reads it as its keys, sending_now), each change of it told (`touched` where
/// a chat's array of it is changed in place).
// kept across runs: let go by sent_reset
let local_sending : @sf.LiveMap[String, Array[LocalSent]] = @sf.LiveMap::new()

///|
/// What was sent from chat `rk` and is not in its view yet, as its list takes it over: the chat's own array of it, which
/// its writers change in place and then say so (sending_changed); where nothing was sent from it, an empty one of its
/// own, kept nowhere (what reads it in a frame's build writes nothing: sending_kept makes the chat's on its first send).
pub fn sending_of(rk : String) -> Array[LocalSent] {
  match @signals.untracked(fn() { local_sending.get(rk) }) {
    Some(a) => a
    None => []
  }
}

///|
/// Chat `rk`'s own array of what was sent from it (sending_of's), kept from its first send on.
fn sending_kept(rk : String) -> Array[LocalSent] {
  match @signals.untracked(fn() { local_sending.get(rk) }) {
    Some(a) => a
    None => {
      let a : Array[LocalSent] = []
      local_sending.set(rk, a)
      a
    }
  }
}

///|
/// What was sent from chat `rk` and is not in its view yet, as it is now, followed as it changes (a copy: read only).
pub fn sending_now(rk : String) -> Array[LocalSent] {
  match local_sending.get(rk) {
    Some(a) => a.copy()
    None => []
  }
}

///|
/// What was sent from a chat changed in place (sending_of's array: one pushed, one taken over, one gone).
fn sending_changed() -> Unit {
  local_sending.touched()
}

///|
pub fn sent_reset() -> Unit {
  local_sending.clear()
  sent_here_n.clear()
  sent_here_made.clear()
  local_sent_n.val = 0
  sent_pictures.clear()
  let told = sent_pictures_told.keys().to_array()
  for k in told {
    sent_picture_tell(k)
  }
  sent_pictures_told.clear()
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
/// How many times something was sent from here into each chat (its station and session, `\u{1}` between): words
/// (sent_local) or an answer picked on one of its cards that says something in it (sent_here_told). What its list made
/// as nodes goes to its end for, from wherever it is read, as it is sent (the old list's: the composer's list_to_end, a
/// card's end_asked).
// kept across runs: let go by sent_reset
let sent_here_n : @sf.LiveMap[String, Int] = @sf.LiveMap::new()

///|
/// Something was sent from here into chat `rk` (sent_here_n).
pub fn sent_here_told(rk : String) -> Unit {
  sent_here_n.set(rk, @signals.untracked(fn() { sent_here_n.get(rk) }).unwrap_or(0) + 1)
}

///|
/// How many times something was sent from here into chat `rk`, followed as it changes (sent_here_n).
pub fn sent_here_count(rk : String) -> Int {
  sent_here_n.get(rk).unwrap_or(0)
}


///|
pub fn local_sent(o : Outgoing) -> Bool {
  o.id.has_prefix("local:")
}

///|
/// The rows of the view `v` there when words were sent: an outbox entry's, a message's, and the outbox entry it was
/// (rows are keyed by it: row_keys).
fn sent_before(v : ChatView) -> Map[String, Bool] {
  let before : Map[String, Bool] = Map([])
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
/// will have them), its words in the runs the core read them in (`runs`: refs_sent_runs). Its key, for what flies there
/// (flight.mbt). `now`, the core's time (its source's): close under the viewer's own row before it while the core says
/// it would be (sent_joins), as its row will say.
pub fn sent_local(
  rk : String,
  v : ChatView?,
  words : String,
  files : Array[Json],
  going? : Array[Json] = [],
  quotes? : Array[Json] = [],
  runs? : Json? = None,
  now~ : Double,
) -> String {
  local_sent_n.val += 1
  let id = "local:\{local_sent_n.val}"
  let (images, cards) = going_up(going)
  let joined = sent_joins(rk, v, now)
  sending_kept(rk).push({
    row: {
      id,
      text: words,
      words: runs,
      attachments: (files + images).map(attachment_of),
      quotes: quotes.map(quote_of),
      state: "sending",
      error: "",
      joined,
      followed: false,
      seq: -1.0,
      time: None,
      waits: if going.length() > 0 { @sf.t("common.uploading") } else { "" },
      progress: None,
      uploads: cards,
      created_at: now,
      refused: false,
    },
    // (a chat just made: none)
    before: match v {
      Some(v) => sent_before(v)
      None => Map([])
    },
    newest: match v {
      Some(v) => v.messages.fold(init=-@double.infinity, fn(n, m) { if m.seq > n { m.seq } else { n } })
      None => -@double.infinity
    },
  })
  sending_changed()
  sent_here_told(rk)
  "o:" + id
}

///|
/// Whether what is sent from chat `rk` now (`now`, the core's time; `v` its view) goes close under the row before it,
/// that row's time under it alone: the viewer's own sent a moment ago, not in the view yet, or the view's last while
/// the core says so (ChatView's `joins_until`). Laid out so the frame it is sent: told only by the core's row, which
/// comes a round trip later (late, on a busy device), the list had gone up as far as a row standing apart takes it
/// and came back down (the user, 2026-11-10: 「偶现发消息动效都会抖」).
fn sent_joins(rk : String, v : ChatView?, now : Double) -> Bool {
  if !sending_of(rk).is_empty() {
    return true
  }
  match v {
    Some({ joins_until: Some(till), .. }) => now <= till
    _ => false
  }
}

///|
/// The rows `all` with what was sent from here and is not among them yet (`still`) put in at `at`, each as its row
/// will be: one going close under the row before it (LocalSent's `joined`) has that row `followed`, its time under
/// the new one, from the frame it is sent.
fn sent_among(all : Array[Entry], keys : Array[String], at : Int, still : Array[LocalSent]) -> Unit {
  for j, l in still {
    all.insert(at + j, Out(l.row))
    keys.insert(at + j, "o:" + l.row.id)
    if l.row.joined && at + j > 0 {
      match all[at + j - 1] {
        Said(m) if !m.followed => all[at + j - 1] = Said({ ..m, followed: true })
        Out(o) if !o.followed => all[at + j - 1] = Out({ ..o, followed: true })
        _ => ()
      }
    }
  }
}

///|
/// What was sent from chat `rk` (key: sent_local's) did not go: it leaves the list.
pub fn sent_local_gone(rk : String, key : String) -> Unit {
  let sending = sending_of(rk)
  match sending.search_by(fn(l) { "o:" + l.row.id == key }) {
    Some(i) => {
      sending.remove(i) |> ignore
      sending_changed()
    }
    None => ()
  }
}


///|
/// The pictures of images sent from here, as they were picked: by station and the name
/// it keeps the file under once up, or by the upload's id from when it starts going up (a message sent before it is up
/// names it so: Attachment.upload). What their messages draw, rather than the likeness and then the station's thumbnail
/// a round trip after the picture flew in; the bytes are kept for the run anyway (@ui.add_image). Written only by
/// sent_picture_kept, which tells what a node of the window's tree read of it (sent_picture_told).
let sent_pictures : Map[String, String] = Map([])

///|
/// What a node read of sent_pictures (sent_picture_told), by its key: told as that one is kept, made as one is first
/// read so, let go as nothing reads it any more. The old views' reads (sent_picture) track nothing.
// kept across runs: let go with sent_pictures (sent_reset)
let sent_pictures_told : Map[String, @signals.Signal[Int]] = Map([])

///|
/// The picture an image sent from here was picked as, kept by `key` (sent_key's, or "upload\u{1}" and its upload's
/// id): what reads it by a node told.
pub fn sent_picture_kept(key : String, picture : String) -> Unit {
  sent_pictures[key] = picture
  sent_picture_tell(key)
}

///|
fn sent_picture_tell(key : String) -> Unit {
  match sent_pictures_told.get(key) {
    Some(s) =>
      if s.watched() {
        s.set(s.untracked() + 1)
      } else {
        sent_pictures_told.remove(key)
      }
    None => ()
  }
}

///|
fn sent_picture_track(key : String) -> Unit {
  let s = match sent_pictures_told.get(key) {
    Some(s) => s
    None => {
      let s = @signals.signal(0)
      sent_pictures_told[key] = s
      s
    }
  }
  s.get() |> ignore
}

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

///|
/// sent_picture read by a node of the window's tree: told as the picture is kept under either of its keys.
pub fn sent_picture_told(station : String, a : Attachment) -> String? {
  sent_picture_track(sent_key(station, a.path))
  if a.upload != "" {
    sent_picture_track("upload\u{1}" + a.upload)
  }
  sent_picture(station, a)
}

///|
/// Where the words of what was sent from here stood in the composer's field as they were sent (the top left of their
/// first line, in the window), by the key its row has in its chat's list (sent_local's), till that row's bubble takes
/// it to fly from there (sent_from_take): on a chat's page made as nodes, where the composer is an old view hosted in
/// the list's foot, so its words are none of the window's tree to pair with (mbui's View::flies_in).
let sent_from_at : Map[String, (Double, Double)] = Map([])

///|
/// The words of what was sent from here as `key` (sent_local's) stood at (`x`, `y`) in the composer's field.
pub fn sent_from_said(key : String, x : Double, y : Double) -> Unit {
  sent_from_at[key] = (x, y)
}

///|
/// Where the words of what was sent from here as `key` stood as they were sent (sent_from_said), taken: told once.
pub fn sent_from_take(key : String) -> (Double, Double)? {
  let at = sent_from_at.get(key)
  sent_from_at.remove(key)
  at
}
