// A person's own lock (docs/personal-lock.md): a chain of the keys their app devices sign with, written only by a device
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
pub fn fold_person(entries : Array[Json], sub : String, c : &Crypto) -> Person raise LockError {
  if entries.length() == 0 {
    raise Refused("no lock")
  }
  let devices : Map[String, PersonDevice] = Map([])
  let mut head = ""
  let mut genesis = ""
  for i, e in entries {
    let v = Some(e)
    guard safe_num(field(v, "v")) == Some(1.0) && text_of(field(v, "ws")) == Some(person_ws(sub)) else {
      raise Refused("an entry of another lock")
    }
    guard safe_int(field(v, "at")) is Some(_) else { raise Refused("at is unix seconds") }
    let follows = match safe_int(field(v, "seq")) {
      Some(seq) => i == 0 && seq.to_int64() == 0L || i > 0 && @history.follows(false, (i - 1).to_int64(), seq.to_int64())
      None => false
    }
    let kept_on = i == 0 && field(v, "prev") is Some(Null) || i > 0 && text_of(field(v, "prev")) == Some(head)
    guard follows && kept_on else { raise Refused("the entry does not follow this lock's head") }
    let key = sig_key(e)
    let b = field(v, "body")
    let kind = text_of(field(v, "kind")).unwrap_or("")
    let hash = entry_hash(e, c)
    if i == 0 {
      guard kind == "genesis" && text_of(field(b, "sub")) == Some(sub) else { raise Refused("a lock starts with its genesis") }
      let first = person_device(field(b, "device"), c)
      guard first.key == key else { raise Refused("the genesis is signed by the device it names") }
      devices[first.key] = first
      genesis = hash
    } else {
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
          // A base key identifies the connecting device. If older entries named it under several signing keys,
          // removing just one key would still admit that very device through another. Revoke all its aliases.
          let base = devices.get(gone).unwrap().id
          let aliases : Array[String] = []
          for id, d in devices {
            if d.id == base { aliases.push(id) }
          }
          for id in aliases { devices.remove(id) }
        }
        _ => raise Refused("unknown entry kind " + kind)
      }
    }
    if !c.sig_valid(sig_of(e), hash, [], "", false) {
      raise Refused("signature invalid")
    }
    head = hash
  }
  { sub, genesis, head, seq: (entries.length() - 1).to_double(), devices }
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
