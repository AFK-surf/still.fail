// A person's own lock: a chain of the keys their app devices sign with, written only by a device
// on it, the one thing a workspace's list and a phone's grant go back to. What station, cloud and devices all decide it
// by; what takes keys is the caller's (`Crypto`), as for the workspace's lock.

///|
pub(all) struct PersonDevice {
  key : String
  id : String
  label : String
}

///|
pub(all) struct Person {
  sub : String
  genesis : String
  head : String
  seq : Double
  devices : Map[String, PersonDevice]
}

///|
/// A lock's name in its entries: an entry of one person's lock is no one else's, nor a workspace's.
pub fn person_ws(sub : String) -> String {
  "person:" + sub
}

///|
fn person_device(v : Json?, c : &Crypto) -> PersonDevice raise LockError {
  guard text_of(field(v, "key")) is Some(key) && text_of(field(v, "id")) is Some(id) && text_of(field(v, "label")) is Some(label) else {
    raise Refused("a person's device is {key, id, label}")
  }
  guard key.has_prefix("ed25519:") && c.valid_key_id(key) && is_hex32(id) else {
    raise Refused("a person's device signs with an ed25519 key, and goes by its base key")
  }
  { key, id, label }
}

///|
/// What a person's chain says, each entry checked: signed by a device on it then, following the last. Raises why not.
/// It takes no statement of a workspace (`fold_person_ws` does): a station from before refuses a chain with a kind it
/// does not know, so no person's log may carry one until every station takes them.
pub fn fold_person(entries : Array[Json], sub : String, c : &Crypto) -> Person raise LockError {
  fold_person_of(entries, sub, false, c)
}

///|
/// A person's chain as `fold_person` has it, with the statements of a workspace (`ws.member`, `ws.member.remove`,
/// `ws.station`, `ws.station.remove`) taken as well: signed by a device on it, their body's shape checked. What they say
/// of a workspace is `roster`'s.
pub fn fold_person_ws(entries : Array[Json], sub : String, c : &Crypto) -> Person raise LockError {
  fold_person_of(entries, sub, true, c)
}

///|
fn fold_person_of(entries : Array[Json], sub : String, statements : Bool, c : &Crypto) -> Person raise LockError {
  if entries.length() == 0 {
    raise Refused("no lock")
  }
  let mut p : Person? = None
  for e in entries {
    p = Some(person_step(p, e, sub, statements, c))
  }
  p.unwrap()
}

///|
/// The person's log with one more entry (`was`: none before its genesis); raises why it does not follow. `statements`:
/// whether a workspace's statements are taken.
fn person_step(was : Person?, e : Json, sub : String, statements : Bool, c : &Crypto) -> Person raise LockError {
  let v = Some(e)
  guard safe_num(field(v, "v")) == Some(1.0) && text_of(field(v, "ws")) == Some(person_ws(sub)) else {
    raise Refused("an entry of another lock")
  }
  guard safe_int(field(v, "at")) is Some(_) else { raise Refused("at is unix seconds") }
  let follows = match (safe_int(field(v, "seq")), was) {
    (Some(seq), None) => seq.to_int64() == 0L
    (Some(seq), Some(w)) => @history.follows(false, w.seq.to_int64(), seq.to_int64())
    (None, _) => false
  }
  let kept_on = match was {
    None => field(v, "prev") is Some(Null)
    Some(w) => text_of(field(v, "prev")) == Some(w.head)
  }
  guard follows && kept_on else { raise Refused("the entry does not follow this lock's head") }
  let key = sig_key(e)
  let b = field(v, "body")
  let kind = text_of(field(v, "kind")).unwrap_or("")
  let hash = entry_hash(e, c)
  let devices : Map[String, PersonDevice] = match was {
    None => Map([])
    Some(w) => copy(w.devices)
  }
  match was {
    None => {
      guard kind == "genesis" && text_of(field(b, "sub")) == Some(sub) else { raise Refused("a lock starts with its genesis") }
      let first = person_device(field(b, "device"), c)
      guard first.key == key else { raise Refused("the genesis is signed by the device it names") }
      devices[first.key] = first
    }
    Some(_) =>
      match kind {
        "device" => {
          guard @role.person_changes(devices.contains(key), false) else { raise Refused("not signed by a device on the lock") }
          let d = person_device(b, c)
          devices[d.key] = d
        }
        "device.remove" => {
          guard text_of(field(b, "key")) is Some(gone) && devices.contains(gone) else { raise Refused("no such device") }
          guard @role.person_changes(devices.contains(key), devices.length() == 1) else {
            raise Refused("not signed by a device on the lock, or its last")
          }
          devices.remove(gone)
        }
        "ws.member" | "ws.member.remove" | "ws.station" | "ws.station.remove" if statements =>
          statement(kind, b, devices.contains(key))
        _ => raise Refused("unknown entry kind " + kind)
      }
  }
  if !c.sig_valid(sig_of(e), hash, [], "", false) {
    raise Refused("signature invalid")
  }
  match was {
    None => { sub, genesis: hash, head: hash, seq: 0.0, devices }
    Some(w) => { sub, genesis: w.genesis, head: hash, seq: w.seq + 1.0, devices }
  }
}

///|
/// A workspace's statement in a person's log, as far as the log goes: signed by a device on it (`held`), naming its
/// workspace and whom it is about; an admit (`ws.member {ws, sub, lock, role}`) the person log it binds them by and an
/// owner's, admin's or member's role; a removal (`… .remove {…, cancels}`) the admits or stations it cancels, by hash.
fn statement(kind : String, b : Json?, held : Bool) -> Unit raise LockError {
  guard held else { raise Refused("not signed by a device on the lock") }
  guard text_of(field(b, "ws")) is Some(_) else { raise Refused("a statement names its workspace") }
  let named = if kind.has_prefix("ws.member") {
    text_of(field(b, "sub")) is Some(_)
  } else {
    is_id(field(b, "key"))
  }
  guard named else { raise Refused("a statement names whom it is about") }
  if kind == "ws.member" {
    let role = text_of(field(b, "role"))
    guard is_id(field(b, "lock")) && (role == Some("owner") || role == Some("admin") || role == Some("member")) else {
      raise Refused("an admit names a lock and a role")
    }
  }
  if kind.has_suffix(".remove") {
    guard field(b, "cancels") is Some(Array(xs)) && xs.iter().all(fn(x) { is_id(Some(x)) }) else {
      raise Refused("a removal names what it cancels")
    }
  }
}

///|
/// A connection let in by a person's own lock (`entries`, the chain it brought): the lock is the one its member bound in
/// this workspace, and its device is on it. The member's role is the lock's. Raises a refusal why not.
pub fn admit_person(s : LockState, sub : String, endpoint : String, base : String?, proof : String?, entries : Array[Json], c : &Crypto) -> (PersonDevice, String, Person) raise LockError {
  guard s.members.get(sub) is Some(member) else { raise Refusal("not a member in the workspace's lock") }
  let person = fold_person(entries, sub, c) catch {
    Refused(why) | Refusal(why) => raise Refusal(why)
    e => raise e
  }
  let pinned = s.persons.get(sub) == Some(person.genesis)
  let base = base.unwrap_or("")
  let proved = base != "" && proof is Some(p) && p != "" && is_hex32(base) && c.endpoint_proof(s.ws, base, endpoint, p)
  let mut on : PersonDevice? = None
  for _, d in person.devices {
    if d.id == base {
      on = Some(d)
    }
  }
  if @role.person_admits(pinned, proved, on is Some(_)) {
    (on.unwrap(), member.role, person)
  } else {
    raise Refusal("this device is not on the lock its person bound in this workspace")
  }
}
