// The workspace's lock as station/src/cloud/lock.ts has it, entry by entry: which entries
// follow, who signed them, what they change, who a connection is. The same answers, the same words: rules/test runs
// both on the same chains. What takes keys (hashing, signatures, a key's form) is the caller's (`Crypto`): node's on the
// stations, @noble's on devices.

///|
/// What the rules ask of the caller's cryptography.
pub(open) trait Crypto {
  /// SHA-256 of the text's UTF-8, as hex.
  sha256_hex(Self, String) -> String
  /// Whether `sig` (an entry's, as it came) is the key's over `hash`; a passkey's also on one of `origins` for `rp_id`.
  sig_valid(Self, Json, String, Array[String], String, Bool) -> Bool
  /// Whether `id` is a signing key's id: `ed25519:<hex>`, `p256:<b64url point>`.
  valid_key_id(Self, String) -> Bool
  /// Whether base key `base` (hex) says `endpoint` is its own in workspace `ws` (`proof`, hex).
  endpoint_proof(Self, String, String, String, String) -> Bool
  /// Whether `sig` (hex) is signing key `key`'s over the bytes `tag`, a NUL, then the 32 bytes of `digest` (hex): the
  /// shape every form a device's signer signs besides a lock entry has (a vault's records, a rig's statements), each
  /// under a tag of its own (`bind_tag`, state4.mbt).
  tagged_sig_valid(Self, String, String, String, String) -> Bool
}

///|
/// Why an entry is refused, a lock is none, a connection is turned away (`refusal`: by the lock, the device to be
/// confirmed, not a bad credential).
pub(all) suberror LockError {
  Refused(String)
  Refusal(String)
}

///|
fn refuse(why : String) -> Unit raise LockError {
  raise Refused(why)
}

///|
pub(all) struct Member {
  sub : String
  email : String
  role : String
}

///|
pub(all) struct Device {
  id : String
  sub : String
  kind : String
  label : String
  sign_key : String?
  endpoints : Array[String]?
  exp : Double?
  by : String?
  own : Bool
}

///|
pub(all) struct Passkey {
  id : String
  sub : String
  key : String
  label : String
  own : Bool
}

///|
pub(all) struct Station {
  key : String
  name : String
}

///|
/// A lock as far as its chain goes (station/src/cloud/lock.ts `LockState`). Maps keep their keys in the order they
/// were first set, as JS's do.
pub(all) struct LockState {
  ws : String
  seq : Double
  head : String
  genesis : String
  origins : Array[String]
  rp_id : String
  cloud_keys : Json
  members : Map[String, Member]
  devices : Map[String, Device]
  sign_keys : Map[String, Array[String]]
  passkeys : Map[String, Passkey]
  signed : Map[String, Unit]
  stations : Map[String, Station]
  gateways : Map[String, Unit]
  /// The person's own lock each member bound themselves to (`person` entries): its genesis's hash.
  persons : Map[String, String]
  disabled : Bool
  /// Where the workspace went (`moved {root}`, its owner's): the genesis hash of the person log it is rooted in from
  /// then on (station/test/lock-roster4-model.ts D5). Nothing follows it in this chain.
  moved : String?
}

///|
/// How long a device added from a web page lasts at most (30 days, a day's slack for clocks).
pub let web_device_secs : Double = 2678400.0

///|
let max_safe : Double = 9007199254740991.0

// ── what a JSON value is, as JS reads it ──────────────────────────────────────────────────────────────────────────

///|
/// A field of an object (none of anything else: JS reads `undefined` there).
fn field(v : Json?, k : String) -> Json? {
  match v {
    Some(Object(m)) => m.get(k)
    _ => None
  }
}

///|
fn text_of(v : Json?) -> String? {
  match v {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
/// station/src/cloud/lock.ts `str`: a string at most `max` long, else none.
fn str(v : Json?, max~ : Int = 200) -> String? {
  match v {
    Some(String(s)) if s.length() <= max => Some(s)
    _ => None
  }
}

///|
fn safe_int(v : Json?) -> Double? {
  match v {
    Some(Number(n, ..)) if n == n.floor() && n.abs() <= max_safe => Some(n)
    _ => None
  }
}

///|
fn arr(v : Json?) -> Array[Json] {
  match v {
    Some(Array(xs)) => xs
    _ => []
  }
}

///|
fn is_hex32(s : String) -> Bool {
  is_hex_of(s, 64)
}

///|
/// Whether `s` is `n` lowercase hex digits.
fn is_hex_of(s : String, n : Int) -> Bool {
  if s.length() != n {
    return false
  }
  for i in 0..<n {
    let c = s.code_unit_at(i).to_int()
    if !((c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x66)) {
      return false
    }
  }
  true
}

///|
fn is_id(v : Json?) -> Bool {
  match v {
    Some(String(s)) => is_hex32(s)
    _ => false
  }
}

///|
fn role_of(v : Json?) -> @role.Role? {
  match v {
    Some(String("owner")) => Some(Owner)
    Some(String("admin")) => Some(Admin)
    Some(String("member")) => Some(Member)
    Some(String("viewer")) => Some(Viewer)
    _ => None
  }
}

///|
fn role_named(s : String) -> @role.Role {
  match s {
    "owner" => Owner
    "admin" => Admin
    "member" => Member
    _ => Viewer
  }
}

///|
fn managing(role : String) -> Bool {
  @role.rank(role_named(role)) >= 2
}

// ── an entry's parts ──────────────────────────────────────────────────────────────────────────────────────────────

///|
fn member(v : Json?) -> Member raise LockError {
  let sub = str(field(v, "sub"))
  let email = str(field(v, "email"), max=320)
  let role = field(v, "role")
  match (sub, email, role_of(role)) {
    (Some(sub), Some(email), Some(_)) if sub != "" => { sub, email, role: text_of(role).unwrap() }
    _ => raise Refused("a member is {sub, email, role}")
  }
}

///|
fn device(v : Json?, at : Double, c : &Crypto) -> Device raise LockError {
  let id = field(v, "id")
  let sub = str(field(v, "sub"))
  let label = str(field(v, "label")).unwrap_or("")
  let kind = text_of(field(v, "kind"))
  guard is_id(id) && sub is Some(sub) && sub != "" && kind is Some(kind) && (kind == "app" || kind == "web") else {
    raise Refused("a device is {id, sub, kind, label}")
  }
  let sign_key = match field(v, "sign_key") {
    None => None
    Some(k) =>
      match k {
        String(k) if kind == "app" && k.length() <= 200 && c.valid_key_id(k) => Some(k)
        _ => raise Refused("only an app's device signs, with an ed25519 or p256 key")
      }
  }
  let endpoints = match field(v, "endpoints") {
    None => None
    Some(Array(xs)) if xs.length() <= 64 && xs.iter().all(fn(x) { is_id(Some(x)) }) =>
      Some(xs.map(fn(x) { text_of(Some(x)).unwrap() }))
    Some(_) => raise Refused("endpoints are iroh ids")
  }
  let exp = match field(v, "exp") {
    None => None
    Some(_) as e =>
      match safe_int(e) {
        Some(n) => Some(n)
        None => raise Refused("exp is unix seconds")
      }
  }
  if kind == "web" && at > 0.0 && (exp is None || exp.unwrap() > at + web_device_secs) {
    raise Refused("a web page's device lasts 30 days at most")
  }
  { id: text_of(id).unwrap(), sub, kind, label, sign_key, endpoints, exp, by: None, own: false }
}

///|
fn passkey(v : Json?, c : &Crypto) -> Passkey raise LockError {
  let id = str(field(v, "id"), max=1400)
  let sub = str(field(v, "sub"))
  let key = text_of(field(v, "key"))
  let label = str(field(v, "label")).unwrap_or("")
  match (id, sub, key) {
    (Some(id), Some(sub), Some(key)) if id != "" && sub != "" && key.has_prefix("p256:") && key.length() <= 200 && c.valid_key_id(key) =>
      { id, sub, key, label, own: false }
    _ => raise Refused("a passkey is {id, sub, key: p256:…}")
  }
}

///|
fn station(v : Json?) -> Station raise LockError {
  guard is_id(field(v, "key")) else { raise Refused("a station is {key, name}") }
  { key: text_of(field(v, "key")).unwrap(), name: str(field(v, "name")).unwrap_or("") }
}

// ── who signed ────────────────────────────────────────────────────────────────────────────────────────────────────

///|
pub(all) struct Signer {
  sub : String
  role : String
  passkey : Bool
  own : Bool
}

///|
fn with_role(s : LockState, sub : String, passkey : Bool, own : Bool) -> Signer? {
  match s.members.get(sub) {
    Some(m) => Some({ sub, role: m.role, passkey, own })
    None => None
  }
}

///|
/// Who signed with `key`: the member whose app device or passkey holds it, with their role now, and whether it is
/// their own (an own one first: a key put in again under another device, someone else's, does not take its signatures
/// away). `now`: none for entries taken before.
pub fn signer(s : LockState, key : String, now : Double?) -> Signer? {
  let mut found : Signer? = None
  for _, p in s.passkeys {
    if p.key == key {
      if with_role(s, p.sub, true, p.own) is Some(w) {
        found = Some(w)
      }
    }
  }
  for _, d in s.devices {
    let live = match (d.exp, now) {
      (None, _) | (_, None) => true
      (Some(exp), Some(now)) => exp > now
    }
    let own_found = match found {
      Some(f) => f.own
      None => false
    }
    if @role.replaces(own_found, d.sign_key == Some(key) && d.kind == "app", live, s.members.contains(d.sub)) {
      found = with_role(s, d.sub, false, d.own)
    }
  }
  found
}

///|
/// Whether a device or passkey of `sub` an entry signed by `by` puts in is the person's own: put in by an own one of
/// theirs, or by an owner or admin while they have had none that signs (`was`: the same device as it stood).
fn own_of(s : LockState, sub : String, by : Signer, was : Device?, key : String?) -> Bool {
  let kept = match was {
    Some(w) => w.own && w.sign_key == key
    None => false
  }
  @role.own_device(by.sub == sub, kept, role_named(by.role), s.signed.contains(sub))
}

///|
fn owners(s : LockState) -> Int {
  let mut n = 0
  for _, m in s.members {
    if m.role == "owner" {
      n = n + 1
    }
  }
  n
}

///|
fn add(s : LockState, d : Device) -> Unit raise LockError {
  if !s.members.contains(d.sub) {
    refuse("a device is a member's")
  }
  s.devices[d.id] = d
  if d.sign_key is Some(k) {
    let had = s.sign_keys.get(d.id).unwrap_or([])
    if !had.contains(k) {
      s.sign_keys[d.id] = [..had, k]
    }
    if d.own {
      s.signed[d.sub] = ()
    }
  }
}

///|
fn add_passkey(s : LockState, p : Passkey) -> Unit {
  s.passkeys[p.key] = p
  if p.own {
    s.signed[p.sub] = ()
  }
}

///|
/// An entry's hash (hex): of everything but its signature.
pub fn entry_hash(e : Json, c : &Crypto) -> String raise LockError {
  let text = @form.entry_text(e) catch { @form.Invalid(why) => raise Refused(why) }
  c.sha256_hex(text)
}

///|
fn sig_key(e : Json) -> String {
  text_of(field(Some(e), "sig") |> field("key")).unwrap_or("")
}

///|
fn sig_of(e : Json) -> Json {
  field(Some(e), "sig").unwrap_or(Json::null())
}

// ── the chain ─────────────────────────────────────────────────────────────────────────────────────────────────────

///|
fn[K : Hash + Eq, V] copy(m : Map[K, V]) -> Map[K, V] {
  let out : Map[K, V] = Map([])
  for k, v in m {
    out[k] = v
  }
  out
}

///|
/// The lock its first entry starts. Raises why it is not one.
pub fn genesis(e : Json, c : &Crypto) -> LockState raise LockError {
  let v = Some(e)
  let ws = text_of(field(v, "ws"))
  guard text_of(field(v, "kind")) == Some("genesis") && safe_num(field(v, "seq")) == Some(0.0) && field(v, "prev") is Some(Null) &&
    safe_num(field(v, "v")) == Some(1.0) && ws is Some(ws) && ws != "" else {
    raise Refused("a lock starts with its genesis")
  }
  let b = match field(v, "body") {
    None | Some(Null) => Some(Json::object(Map([])))
    x => x
  }
  let origins = arr(field(b, "origins")).filter_map(fn(o) { text_of(Some(o)) })
  let hash = entry_hash(e, c)
  let s : LockState = {
    ws,
    seq: 0.0,
    head: hash,
    genesis: hash,
    origins,
    rp_id: str(field(b, "rp_id")).unwrap_or(""),
    cloud_keys: match field(b, "cloud_keys") {
      None => Json::null()
      Some(k) => k
    },
    members: Map([]),
    devices: Map([]),
    sign_keys: Map([]),
    passkeys: Map([]),
    signed: Map([]),
    stations: Map([]),
    gateways: Map([]),
    persons: Map([]),
    disabled: false,
    moved: None,
  }
  for m in arr(field(b, "members")) {
    let m = member(Some(m))
    s.members[m.sub] = m
  }
  let owner = str(field(b, "owner"))
  // (the genesis's devices and passkeys are the ones the owner found each person had: all their own)
  for d in arr(field(b, "devices")) {
    add(s, { ..device(Some(d), 0.0, c), own: true, by: owner })
  }
  for p in arr(field(b, "passkeys")) {
    add_passkey(s, { ..passkey(Some(p), c), own: true })
  }
  for st in arr(field(b, "stations")) {
    let st = station(Some(st))
    s.stations[st.key] = st
  }
  for g in arr(field(b, "gateways")) {
    if is_id(Some(g)) {
      s.gateways[text_of(Some(g)).unwrap()] = ()
    }
  }
  let owns = match text_of(field(b, "owner")) {
    Some(o) =>
      match s.members.get(o) {
        Some(m) => m.role == "owner"
        None => false
      }
    None => false
  }
  if !owns {
    refuse("the genesis names its owner among its members")
  }
  // (an `at` that is no number: JS compares `exp > undefined` false, so a device that runs out is no signer then)
  let by = signer(s, sig_key(e), Some(safe_num(field(v, "at")).unwrap_or(1.0 / 0.0)))
  let signed_by_owner = match (by, text_of(field(b, "owner"))) {
    (Some(by), Some(o)) => by.sub == o && c.sig_valid(sig_of(e), s.head, s.origins, s.rp_id, by.passkey)
    _ => false
  }
  if !signed_by_owner {
    refuse("the genesis is not signed by its owner")
  }
  s
}

///|
/// A number as JS compares it with `===` to an integer: none when it is not a number.
fn safe_num(v : Json?) -> Double? {
  match v {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
}

///|
/// The lock with one more entry; raises why the entry does not follow. `now`: the station's time (unix seconds), for
/// signing devices that ran out; none for entries taken before (kept in lock.json).
pub fn apply(prev : LockState, e : Json, now : Double?, c : &Crypto) -> LockState raise LockError {
  let v = Some(e)
  if prev.moved is Some(_) {
    refuse("the lock moved to a person's own log: nothing follows it here")
  }
  if prev.disabled {
    refuse("the lock is turned off")
  }
  if safe_num(field(v, "v")) != Some(1.0) || text_of(field(v, "ws")) != Some(prev.ws) {
    refuse("an entry of another lock")
  }
  let follows = match safe_int(field(v, "seq")) {
    Some(seq) => @history.follows(false, prev.seq.to_int64(), seq.to_int64())
    None => false
  }
  if !follows || text_of(field(v, "prev")) != Some(prev.head) {
    refuse("the entry does not follow this lock's head")
  }
  if safe_int(field(v, "at")) is None {
    refuse("at is unix seconds")
  }
  let at = safe_int(field(v, "at")).unwrap()
  let hash = entry_hash(e, c)
  guard signer(prev, sig_key(e), now) is Some(by) else {
    raise Refused("not signed by a device or passkey in the lock")
  }
  if !c.sig_valid(sig_of(e), hash, prev.origins, prev.rp_id, by.passkey) {
    refuse("signature invalid")
  }
  let s : LockState = {
    ..prev,
    seq: prev.seq + 1.0,
    head: hash,
    members: copy(prev.members),
    devices: copy(prev.devices),
    sign_keys: copy(prev.sign_keys),
    passkeys: copy(prev.passkeys),
    signed: copy(prev.signed),
    stations: copy(prev.stations),
    gateways: copy(prev.gateways),
    persons: copy(prev.persons),
  }
  let b = match field(v, "body") {
    None | Some(Null) => Some(Json::object(Map([])))
    x => x
  }
  let who = role_named(by.role)
  let need = fn(ok : Bool, why : String) -> Unit raise LockError { if !ok { raise Refused(why) } }
  let kind = text_of(field(v, "kind")).unwrap_or("")
  let mut out = s
  match kind {
    "member" => {
      let m = member(b)
      let was_owner = match s.members.get(m.sub) {
        Some(w) => w.role == "owner"
        None => false
      }
      need(@role.may(who, MemberSet(was_owner, m.role == "owner")), if @role.rank(who) >= 2 { "only owners make or change owners" } else { "only owners and admins change members" })
      let kept = @role.keeps_owner(owners(s), was_owner, m.role == "owner")
      s.members[m.sub] = m
      need(kept, "a lock keeps an owner")
    }
    "member.remove" => {
      let sub = str(field(b, "sub"))
      guard sub is Some(sub) && s.members.contains(sub) else { raise Refused("no such member") }
      let was_owner = s.members.get(sub).unwrap().role == "owner"
      need(@role.may(who, MemberRemove(was_owner)), "only owners and admins remove members, owners owners")
      need(@role.keeps_owner(owners(s), was_owner, false), "a lock keeps an owner")
      s.members.remove(sub)
      for k in s.devices.keys().collect() {
        if s.devices.get(k).unwrap().sub == sub {
          s.devices.remove(k)
        }
      }
      for k in s.passkeys.keys().collect() {
        if s.passkeys.get(k).unwrap().sub == sub {
          s.passkeys.remove(k)
        }
      }
      // (made a member again, their first device is put in by an owner or admin as anyone's first is)
      s.signed.remove(sub)
      s.persons.remove(sub)
    }
    "device" => {
      let d = device(b, at, c)
      need(@role.may(who, Own(d.sub == by.sub)), "members add only their own devices")
      add(s, { ..d, by: Some(by.sub), own: own_of(prev, d.sub, by, prev.devices.get(d.id), d.sign_key) })
    }
    "device.remove" => {
      let d = match text_of(field(b, "id")) {
        Some(id) => s.devices.get(id)
        None => None
      }
      guard d is Some(d) else { raise Refused("no such device") }
      need(@role.may(who, Own(d.sub == by.sub)), "members remove only their own devices")
      s.devices.remove(d.id)
    }
    "passkey" => {
      let p = passkey(b, c)
      need(s.members.contains(p.sub), "a passkey is a member's")
      need(@role.may(who, Own(p.sub == by.sub)), "members add only their own passkeys")
      add_passkey(s, { ..p, own: own_of(prev, p.sub, by, None, None) })
    }
    "passkey.remove" => {
      let p = match text_of(field(b, "key")) {
        Some(k) => s.passkeys.get(k)
        None => None
      }
      guard p is Some(p) else { raise Refused("no such passkey") }
      need(@role.may(who, Own(p.sub == by.sub)), "members remove only their own passkeys")
      s.passkeys.remove(p.key)
    }
    "person" => {
      let sub = text_of(field(b, "sub"))
      guard sub is Some(sub) && s.members.contains(sub) else { raise Refused("a person's lock is a member's") }
      guard text_of(field(b, "person")) is Some(person) && is_hex32(person) else { raise Refused("a person's lock is named by its genesis's hash") }
      // (their own device or passkey, not a manager's: no one binds someone else to a lock)
      need(@role.binds(sub == by.sub, by.own), "members bind only themselves to a lock of their own, from their own device")
      s.persons[sub] = person
    }
    "station" => {
      need(@role.may(who, Roster), "only owners and admins add stations")
      let st = station(b)
      s.stations[st.key] = st
    }
    "station.remove" => {
      need(@role.may(who, Roster), "only owners and admins remove stations")
      if text_of(field(b, "key")) is Some(k) {
        s.stations.remove(k)
      }
    }
    "gateway" => {
      need(@role.may(who, Roster) && is_id(field(b, "key")), "only owners and admins add gateways, by iroh id")
      s.gateways[text_of(field(b, "key")).unwrap()] = ()
    }
    "gateway.remove" => {
      need(@role.may(who, Roster), "only owners and admins remove gateways")
      if text_of(field(b, "key")) is Some(k) {
        s.gateways.remove(k)
      }
    }
    "cloud_keys" => {
      need(@role.may(who, CloudKeys) && field(b, "keys") is Some(_), "only owners change the control plane's keys")
      out = { ..s, cloud_keys: field(b, "keys").unwrap() }
    }
    "disable" => {
      need(@role.may(who, Disable), "only owners turn the lock off")
      out = { ..s, disabled: true }
    }
    "moved" => {
      // (an owner's own app device: what only the person it is rooted in could say of the workspace from then on)
      need(by.role == "owner" && by.own && !by.passkey, "only an owner's own app device hands the lock over")
      let one = match b {
        Some(Object(m)) => m.length() == 1
        _ => false
      }
      guard one && text_of(field(b, "root")) is Some(root) && is_hex32(root) else {
        raise Refused("a handover names the person log it goes to, by its genesis's hash")
      }
      out = { ..s, moved: Some(root) }
    }
    _ => refuse("unknown entry kind " + kind_text(field(v, "kind")))
  }
  // Signed with a device or passkey someone else put in under the signer's name: it stays in the chain, as the rules
  // let its signer's role make it (so a lock with one from before keeps folding), and changes nothing.
  if @role.takes_effect(by.own) {
    out
  } else {
    { ..prev, seq: prev.seq + 1.0, head: hash }
  }
}

///|
/// What JS's `String(e.kind)` writes of a kind that is none it knows.
fn kind_text(v : Json?) -> String {
  match v {
    None => "undefined"
    Some(String(s)) => s
    Some(Null) => "null"
    Some(True) => "true"
    Some(False) => "false"
    Some(Number(_, ..)) as n => @form.canonical(n.unwrap()) catch { _ => "NaN" }
    Some(Array(_)) => ""
    Some(Object(_)) => "[object Object]"
  }
}

///|
/// A whole chain, from its genesis. Raises at the first entry that does not follow.
pub fn fold(entries : Array[Json], now : Double?, c : &Crypto) -> LockState raise LockError {
  if entries.length() == 0 {
    refuse("no lock")
  }
  let mut s = genesis(entries[0], c)
  for i in 1..<entries.length() {
    s = apply(s, entries[i], now, c)
  }
  s
}

///|
/// The device a connection is, by the base key's proof for its endpoint or (an older client) the endpoint itself, and
/// that device's member's role in the lock. Raises a refusal why it may not connect.
pub fn admit(s : LockState, sub : String, endpoint : String, base : String?, proof : String?, now : Double, c : &Crypto) -> (Device, String) raise LockError {
  let mut d : Device? = None
  match (base, proof) {
    (Some(base), Some(proof)) if base != "" && proof != "" && is_hex32(base) && c.endpoint_proof(s.ws, base, endpoint, proof) => d = s.devices.get(base)
    _ => ()
  }
  if d is None {
    d = s.devices.get(endpoint)
  }
  if d is None {
    for _, x in s.devices {
      if x.endpoints is Some(es) && es.contains(endpoint) {
        d = Some(x)
        break
      }
    }
  }
  let theirs = match d {
    Some(d) => d.sub == sub
    None => false
  }
  let live = match d {
    Some(d) => @history.unexpired(d.exp is Some(_), d.exp.unwrap_or(0.0).to_int64(), now.to_int64())
    None => false
  }
  let role = match d {
    Some(d) => s.members.get(d.sub).map(fn(m) { m.role })
    None => None
  }
  match @role.admission(d is Some(_), theirs, live, role is Some(_)) {
    Admitted => (d.unwrap(), role.unwrap())
    Unknown => raise Refusal("this device is not confirmed in the workspace's lock")
    Others => raise Refusal("this device is someone else's in the workspace's lock")
    RanOut => raise Refusal("this device's confirmation ran out")
    NoMember => raise Refusal("not a member in the workspace's lock")
  }
}
