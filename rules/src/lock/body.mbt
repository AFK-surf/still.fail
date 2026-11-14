// A workspace's statement as its people's logs carry it (station/test/lock-roster4-model.ts D1, 2026-11-13): in the
// signer's log only a commitment, `ws {t, h}`, with `t` the workspace's tag in that log and `h` the hash of the body;
// the body itself travels apart and is kept by the workspace's own keepers alone (its stations, the devices of its
// members), so that the stations of a person's other workspaces, which keep the same log, read nothing of this one.
// What a keeper takes of a body is here; what the bodies kept say is `roster.mbt`'s.

///|
/// The workspace `ws`'s tag in the person log of genesis hash `genesis`: the same for every statement of it there,
/// another in every other log.
pub fn ws_tag(ws : String, genesis : String, c : &Crypto) -> String {
  c.sha256_hex("stillfail/ws-tag/1\n" + ws + "\n" + genesis)
}

///|
/// A body's hash: of its canonical form (`@form.canonical`, what a commitment's `h` names). Raises where it has none.
pub fn body_hash(b : Json, c : &Crypto) -> String raise LockError {
  let text = @form.canonical(b) catch { @form.Invalid(why) => raise Refused(why) }
  c.sha256_hex(text)
}

///|
/// The roles an admit gives (the product's four).
fn is_role(v : Json?) -> Bool {
  match v {
    Some(String("owner")) | Some(String("admin")) | Some(String("member")) | Some(String("viewer")) => true
    _ => false
  }
}

///|
fn is_salt(v : Json?) -> Bool {
  match v {
    Some(String(s)) if s.length() == 32 => {
      for i in 0..<32 {
        let c = s.code_unit_at(i).to_int()
        if !((c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x66)) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
/// Why a body is not one a statement has, or none. Every body is `{ws, kind, …, salt, prev}`: `salt` 32 hex digits (two
/// statements that say the same are two bodies), `prev` the `h` of the statement of its workspace before it in its log
/// (null for the first). By kind: `member {sub, email, lock, role}` (one of the four roles), `member.remove {sub,
/// cancels}` (the bodies' hashes it takes back), `station {key}`, `station.remove {key, cancels}`, `open {origins,
/// rp_id, cloud_keys, email}` (the settings, and the root's person's email), `off {}`; nothing more.
pub fn body_why(b : Json) -> String? {
  let v = Some(b)
  let m = match b {
    Object(m) => m
    _ => return Some("a body is {ws, kind, …, salt}")
  }
  guard text_of(field(v, "ws")) is Some(_) && is_salt(field(v, "salt")) else { return Some("a body is {ws, kind, …, salt}") }
  match m.get("prev") {
    Some(Null) => ()
    Some(String(s)) if is_hex32(s) => ()
    _ => return Some("a body names the statement before it")
  }
  let keys = m.keys().filter(fn(k) { k != "prev" }).collect()
  let only = fn(want : Array[String]) { keys.length() == want.length() && want.iter().all(fn(k) { keys.contains(k) }) }
  let hexes = fn(x : Json?) {
    match x {
      Some(Array(xs)) => xs.iter().all(fn(y) { is_id(Some(y)) })
      _ => false
    }
  }
  let named = fn(k : String) { text_of(field(v, k)) is Some(_) }
  match text_of(field(v, "kind")) {
    Some("member") =>
      if only(["email", "kind", "lock", "role", "salt", "sub", "ws"]) && named("sub") && named("email") && is_id(field(v, "lock")) && is_role(field(v, "role")) {
        None
      } else {
        Some("an admit names a person, their email, a lock and a role")
      }
    Some("member.remove") =>
      if only(["cancels", "kind", "salt", "sub", "ws"]) && named("sub") && hexes(field(v, "cancels")) {
        None
      } else {
        Some("a removal names whom and what it cancels")
      }
    Some("station") =>
      if only(["key", "kind", "salt", "ws"]) && is_id(field(v, "key")) { None } else { Some("a station is named by its key") }
    Some("station.remove") =>
      if only(["cancels", "key", "kind", "salt", "ws"]) && is_id(field(v, "key")) && hexes(field(v, "cancels")) {
        None
      } else {
        Some("a removal names whom and what it cancels")
      }
    Some("open") => {
      let origins = match field(v, "origins") {
        Some(Array(xs)) => xs.iter().all(fn(o) { o is String(_) })
        _ => false
      }
      if only(["cloud_keys", "email", "kind", "origins", "rp_id", "salt", "ws"]) && named("email") && origins && named("rp_id") {
        None
      } else {
        Some("open names the settings")
      }
    }
    Some("off") => if only(["kind", "salt", "ws"]) { None } else { Some("off says nothing more") }
    _ => Some("no such statement")
  }
}

///|
/// A commitment a keeper keeps: the genesis hash of its log, and that log from its genesis to the `ws` entry itself
/// (the entry last), on whichever branch the keeper keeps it.
pub(all) struct Commit {
  genesis : String
  chain : Array[Json]
}

///|
/// Why a keeper of workspace `ws` does not take body `b`, or none (it takes it), given every commitment it keeps whose
/// `h` is the body's hash (`commits`; more than one where its device signed it again): the body names `ws`; one of
/// them is under `ws`'s tag in its log; its shape is a statement's; its `prev` is none, or the `h` of a statement of
/// the same tag before that commitment in its log (its body need not be kept yet). The log itself checks none of this:
/// it sees only the hash.
pub fn body_refusal(ws : String, b : Json, commits : Array[Commit], c : &Crypto) -> String? {
  guard text_of(field(Some(b), "ws")) == Some(ws) else { return Some("it names no workspace this keeper keeps") }
  let h = body_hash(b, c) catch { _ => return Some("no entry it keeps commits to it") }
  let mine = commits.filter(fn(x) {
    guard x.chain.length() > 0 else { return false }
    let e = Some(x.chain[x.chain.length() - 1])
    text_of(field(e, "kind")) == Some("ws") && (field(e, "body") |> field("h") |> text_of) == Some(h)
  })
  guard mine.length() > 0 else { return Some("no entry it keeps commits to it") }
  let tag = fn(x : Commit) { ws_tag(ws, x.genesis, c) }
  let tagged = mine.filter(fn(x) { (field(Some(x.chain[x.chain.length() - 1]), "body") |> field("t") |> text_of) == Some(tag(x)) })
  guard tagged.length() > 0 else { return Some("its entry's tag is not its workspace's in that log") }
  if body_why(b) is Some(why) {
    return Some("its shape: " + why)
  }
  let prev = text_of(field(Some(b), "prev"))
  guard prev is Some(p) else { return None }
  for x in tagged {
    let t = tag(x)
    for i in 0..<(x.chain.length() - 1) {
      let e = Some(x.chain[i])
      if text_of(field(e, "kind")) == Some("ws") && (field(e, "body") |> field("t") |> text_of) == Some(t) && (field(e, "body") |> field("h") |> text_of) == Some(p) {
        return None
      }
    }
  }
  Some("its prev is not a statement before it in that log")
}
