// The vault's rules (实现约定) as station/src/vault/crypto.ts has them: whether a box certificate is a
// lock app device's, whether a vault or item version may follow the one kept, whether a listing is one. The same
// answers, the same words (station/test/rules-vault.test.ts runs both on the same records). What the lock says is
// read off `LockView` (who the members are, each device's person, kind, signing keys and whether their own); the
// signatures are the caller's (`Crypto`).

///|
/// What the rules ask of the caller's cryptography: whether `sig` (as it came) is its key's over a record whose
/// canonical text without `sig` is `text`, under `tag` (the bytes signed: the tag, a NUL, the text's SHA-256).
pub(open) trait Crypto {
  record_sig_valid(Self, Json, String, String) -> Bool
}

///|
pub(all) struct Device {
  sub : String
  kind : String
  sign_key : String?
  own : Bool
}

///|
/// The lock as the vault reads it (station/src/cloud/lock.ts `LockState`: `ws`, `members`, `devices`, `signKeys`).
pub(all) struct LockView {
  ws : String
  members : Map[String, Unit]
  devices : Map[String, Device]
  sign_keys : Map[String, Array[String]]
}

///|
let scopes : Array[String] = ["once", "hour", "chat"]

///|
let kinds : Array[String] = ["token", "ssh_key", "login", "file", "browser"]

///|
let modes : Array[String] = ["proxy", "ssh", "env", "file", "browser"]

///|
let max_safe : Double = 9007199254740991.0

// ── what a JSON value is, as JS reads it ──────────────────────────────────────────────────────────────────────────

///|
fn field(v : Json?, k : String) -> Json? {
  match v {
    Some(Object(m)) => m.get(k)
    _ => None
  }
}

///|
fn is_object(v : Json?) -> Bool {
  v is Some(Object(_))
}

///|
/// JS's `String(v)`, as a regular expression's `test` reads a value that is not a string.
fn js_string(v : Json?) -> String {
  match v {
    None => "undefined"
    Some(String(s)) => s
    Some(Null) => "null"
    Some(True) => "true"
    Some(False) => "false"
    Some(Number(_, ..)) as n => @form.canonical(n.unwrap()) catch { _ => "NaN" }
    Some(Array(xs)) => {
      let b = StringBuilder::new()
      for i, x in xs {
        if i > 0 {
          b.write_string(",")
        }
        match x {
          Null => ()
          _ => b.write_string(js_string(Some(x)))
        }
      }
      b.to_string()
    }
    Some(Object(_)) => "[object Object]"
  }
}

///|
/// `Number.isSafeInteger(v) && v >= 0`.
fn int(v : Json?) -> Bool {
  match v {
    Some(Number(n, ..)) => n == n.floor() && n >= 0.0 && n <= max_safe
    _ => false
  }
}

///|
fn num(v : Json?) -> Double {
  match v {
    Some(Number(n, ..)) => n
    _ => 0.0
  }
}

///|
fn text(v : Json?, max~ : Int = 200) -> Bool {
  match v {
    Some(String(s)) => s.length() <= max
    _ => false
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
fn b64(v : Json?, max : Int) -> Bool {
  match v {
    Some(String(s)) if s.length() <= max => all_units(s, fn(c) { alnum(c) || c == 95 || c == 45 })
    _ => false
  }
}

///|
fn all_units(s : String, ok : (Int) -> Bool) -> Bool {
  for i in 0..<s.length() {
    if !ok(s.code_unit_at(i).to_int()) {
      return false
    }
  }
  true
}

///|
fn digit(c : Int) -> Bool {
  c >= 48 && c <= 57
}

///|
fn lower(c : Int) -> Bool {
  c >= 97 && c <= 122
}

///|
fn upper(c : Int) -> Bool {
  c >= 65 && c <= 90
}

///|
fn alnum(c : Int) -> Bool {
  digit(c) || lower(c) || upper(c)
}

///|
/// `/^[0-9a-f]{64}$/`.
fn hex32(s : String) -> Bool {
  s.length() == 64 && all_units(s, fn(c) { digit(c) || (c >= 97 && c <= 102) })
}

///|
/// `/^x25519:[0-9a-f]{64}$/`.
fn box_key(s : String) -> Bool {
  s.has_prefix("x25519:") && hex32(s.view(start_offset=7).to_string())
}

///|
/// `/^<prefix>[0-9A-HJKMNP-TV-Z]{26}$/`: a ULID's alphabet (Crockford's, no I, L, O, U).
fn ulid_id(s : String, prefix : String) -> Bool {
  if !s.has_prefix(prefix) || s.length() != prefix.length() + 26 {
    return false
  }
  all_units(s.view(start_offset=prefix.length()).to_string(), fn(c) {
    digit(c) || (upper(c) && c != 73 && c != 76 && c != 79 && c != 85)
  })
}

///|
/// `/^(\*\.)?[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$/`: a domain name, `*.` before it allowed.
fn host(s : String) -> Bool {
  let name = if s.has_prefix("*.") { s.view(start_offset=2).to_string() } else { s }
  let labels = name.split(".").collect()
  for l in labels {
    let l = l.to_string()
    if l.length() == 0 {
      return false
    }
    let first = l.code_unit_at(0).to_int()
    let last = l.code_unit_at(l.length() - 1).to_int()
    let lc = fn(c : Int) { lower(c) || digit(c) }
    if !lc(first) || !lc(last) || !all_units(l, fn(c) { lc(c) || c == 45 }) {
      return false
    }
  }
  true
}

///|
/// `/^[A-Za-z_][A-Za-z0-9_]*$/`.
fn env_name(s : String) -> Bool {
  s.length() > 0 && !digit(s.code_unit_at(0).to_int()) && all_units(s, fn(c) { alnum(c) || c == 95 })
}

///|
fn strings(v : Json?) -> Array[Json] {
  match v {
    Some(Array(xs)) => xs
    _ => []
  }
}

///|
fn has_text(xs : Array[Json], s : String) -> Bool {
  xs.iter().any(fn(x) { x is String(t) && t == s })
}

///|
/// Distinct, as `new Set(a).size === a.length` finds them (by value for strings and numbers).
fn unique(xs : Array[Json]) -> Bool {
  for i in 0..<xs.length() {
    for j in 0..<i {
      if xs[i] == xs[j] {
        match xs[i] {
          String(_) | Number(_, ..) | Null | True | False => return false
          _ => ()
        }
      }
    }
  }
  true
}

///|
fn sig_shape(s : Json?) -> Bool {
  is_object(s) && text_of(field(s, "key")) is Some(_) && text_of(field(s, "sig")) is Some(_) &&
  (text_of(field(s, "alg")) == Some("Ed25519") || text_of(field(s, "alg")) == Some("ES256"))
}

///|
/// The record without its `sig`, as `const { sig: _, ...rest } = o` leaves it.
fn without_sig(o : Json) -> Json {
  match o {
    Object(m) => {
      let rest : Map[String, Json] = Map([])
      for k, v in m {
        if k != "sig" {
          rest[k] = v
        }
      }
      Json::object(rest)
    }
    _ => o
  }
}

///|
/// station/src/vault/crypto.ts `signedOk`: whether `o.sig` is its key's over `o` under `tag`.
fn signed_ok(o : Json, tag : String, c : &Crypto) -> Bool {
  let sig = field(Some(o), "sig")
  guard is_object(sig) && text_of(field(sig, "sig")) is Some(_) else { return false }
  let text = @form.canonical(without_sig(o)) catch { _ => return false }
  c.record_sig_valid(sig.unwrap(), tag, text)
}

// ── the rules ─────────────────────────────────────────────────────────────────────────────────────────────────────

///|
/// The member and lock device whose app `sign_key` is `key`; none when no app device in the lock signs with it, or the
/// one that does is not its person's own.
pub fn signer_of(lock : LockView, key : String) -> (String, String)? {
  for id, d in lock.devices {
    if @role.device_signs(d.kind == "app", d.sign_key == Some(key), d.own, lock.members.contains(d.sub)) {
      return Some((d.sub, id))
    }
  }
  None
}

///|
/// Why a box certificate is not a lock app device's for the workspace, or none when it is (station/src/vault/crypto.ts
/// `certOk`; `ever`: signed by any signing key the device has had, and kept by a device no longer its person's own).
pub fn cert_ok(lock : LockView, cert : Json?, ever : Bool, c : &Crypto) -> String? {
  let shape = "a box certificate is {v: 1, ws, device, box, at, sig} of this workspace"
  if !is_object(cert) || num(field(cert, "v")) != 1.0 || !(field(cert, "v") is Some(Number(_, ..))) || text_of(field(cert, "ws")) != Some(lock.ws) {
    return Some(shape)
  }
  let device = js_string(field(cert, "device"))
  if !hex32(device) || !box_key(js_string(field(cert, "box"))) || !int(field(cert, "at")) || !sig_shape(field(cert, "sig")) {
    return Some(shape)
  }
  // (a device id read off a value that is not a string finds no device, as a JS Map's `get` finds none)
  let d = match field(cert, "device") {
    Some(String(id)) => lock.devices.get(id)
    _ => None
  }
  guard d is Some(d) && d.kind == "app" && lock.members.contains(d.sub) else {
    return Some("the box certificate's device is not an app device in the lock")
  }
  if !@role.cert_device_ok(d.own, ever) {
    return Some("the box certificate's device was put in the lock by someone else, not its person")
  }
  let key = text_of(field(field(cert, "sig"), "key")).unwrap()
  let had = lock.sign_keys.get(device).unwrap_or([])
  if !@role.cert_key_ok(d.sign_key == Some(key), ever, had.contains(key)) {
    return Some("a box certificate is signed by its own device's key")
  }
  if !signed_ok(cert.unwrap(), "stillfail-vault-box/1", c) {
    return Some("the box certificate's signature is invalid")
  }
  None
}

///|
/// Why `next` may not follow `prev` (none: the vault's first version), or none when it may (station/src/vault/
/// crypto.ts `vaultOk`; `copy`: a later version brought from another station, only later than the one held).
pub fn vault_ok(lock : LockView, prev : Json?, next : Json, copy : Bool, c : &Crypto) -> String? {
  let v = Some(next)
  if !is_object(v) || !(field(v, "v") is Some(Number(1.0, ..))) || text_of(field(v, "ws")) != Some(lock.ws) {
    return Some("a vault is {v: 1, ws, …} of this workspace")
  }
  guard field(v, "id") is Some(String(id)) && ulid_id(id, "v_") else { return Some("a vault's id is v_<ULID>") }
  if !int(field(v, "seq")) || !int(field(v, "epoch")) || !int(field(v, "at")) {
    return Some("seq, epoch and at are whole numbers")
  }
  guard field(v, "owner") is Some(String(owner)) && owner.length() <= 200 && owner != "" && text(field(v, "name")) else {
    return Some("a vault has an owner and a name")
  }
  let members = match field(v, "members") {
    Some(Array(xs)) if xs.length() <= 256 && xs.iter().all(fn(m) { m is String(s) && s.length() <= 200 && s != "" }) && unique(xs) =>
      xs.map(fn(m) { text_of(Some(m)).unwrap() })
    _ => return Some("members are distinct subs")
  }
  if !members.contains(owner) {
    return Some("the owner is a member")
  }
  let keys = match field(v, "keys") {
    Some(Array(xs)) if xs.length() <= 1024 => xs
    _ => return Some("keys is a list")
  }
  if field(v, "recovery") is Some(_) && !b64(field(v, "recovery"), 200) {
    return Some("recovery is a seal")
  }
  if field(v, "lasts") is Some(l) && !(l is String(s) && scopes.contains(s)) {
    return Some("lasts is once, hour or chat")
  }
  let deleted = field(v, "deleted") is Some(True)
  if field(v, "deleted") is Some(_) && (!deleted || keys.length() > 0 || field(v, "recovery") is Some(_)) {
    return Some("a deleted vault is sealed to no one")
  }
  if !sig_shape(field(v, "sig")) {
    return Some("a vault is signed")
  }
  let seq = num(field(v, "seq"))
  let epoch = num(field(v, "epoch"))
  match prev {
    None => if seq != 0.0 && !copy { return Some("a vault's first version is seq 0") }
    Some(_) as p => {
      if text_of(field(p, "id")) != Some(id) {
        return Some("another vault")
      }
      let held = num(field(p, "seq"))
      if !@history.follows(copy, held.to_int64(), seq.to_int64()) {
        return Some(if copy { "a copy is later than seq " + whole(held) } else { "seq " + whole(held + 1.0) + " follows " + whole(held) })
      }
      if text_of(field(p, "owner")) != Some(owner) {
        return Some("a vault's owner does not change")
      }
      if !@history.deletion_ok(field(p, "deleted") is Some(True), deleted) {
        return Some("a deleted vault stays deleted")
      }
      let held_epoch = num(field(p, "epoch")).to_int64()
      if !@history.epoch_ok(false, held_epoch, epoch.to_int64()) {
        return Some("the epoch does not go back")
      }
      let devices = keys.map(fn(k) { field(field(Some(k), "cert"), "device") })
      let kept = fn(d : Json?) { devices.iter().any(fn(x) { x == d }) }
      let gone = strings(field(p, "members")).iter().any(fn(m) { !(m is String(s) && members.contains(s)) }) ||
        strings(field(p, "keys")).iter().any(fn(k) { !kept(field(field(Some(k), "cert"), "device")) })
      if !@history.epoch_ok(gone, held_epoch, epoch.to_int64()) {
        return Some("removing a member or device takes a new epoch (a new vault key)")
      }
    }
  }
  for m in members {
    if !lock.members.contains(m) {
      return Some("member " + m + " is not in the lock")
    }
  }
  let seen : Map[String, Unit] = Map([])
  for k in keys {
    let k = Some(k)
    if !is_object(k) || !b64(field(k, "wrapped"), 200) {
      return Some("a key is {cert, wrapped}")
    }
    if cert_ok(lock, field(k, "cert"), true, c) is Some(why) {
      return Some(why)
    }
    let device = text_of(field(field(k, "cert"), "device")).unwrap()
    let member = members.contains(lock.devices.get(device).unwrap().sub)
    if !@role.key_ok(seen.contains(device), member) {
      return Some(if seen.contains(device) { "one key per device" } else { "a key is for a member's device" })
    }
    seen[device] = ()
  }
  let key = text_of(field(field(v, "sig"), "key")).unwrap()
  let by = signer_of(lock, key)
  guard @role.signed_by(by is Some(_), by.map(fn(b) { b.0 == owner }).unwrap_or(false)) else {
    return Some("a vault is signed by one of its owner's devices in the lock")
  }
  if !signed_ok(next, "stillfail-vault/1", c) {
    return Some("the vault's signature is invalid")
  }
  None
}

///|
fn whole(n : Double) -> String {
  @form.canonical(Json::number(n)) catch { _ => "NaN" }
}

///|
/// Why a listing is not one as a sign-in (kind and mode browser) must be, or none (station/src/vault/crypto.ts
/// `browserListingOk`).
pub fn browser_listing_ok(kind : String, modes : Array[String], hosts : Array[String]) -> String? {
  let sign = kind == "browser"
  if sign != modes.contains("browser") || (sign && modes.length() != 1) {
    return Some("a sign-in (kind browser) is given into a chat's browser (modes: [\"browser\"]), and only a sign-in is")
  }
  if sign && (hosts.length() == 0 || hosts.iter().any(fn(h) { h.has_prefix("*.") })) {
    return Some("a sign-in names the sites it is for (github.com: its subdomains with it)")
  }
  None
}

///|
fn listing_ok(l : Json?) -> String? {
  guard is_object(l) && text(field(l, "name")) && field(l, "kind") is Some(String(kind)) && kinds.contains(kind) else {
    return Some("a listing is {name, kind, modes, hosts, env?}")
  }
  let ms = match field(l, "modes") {
    Some(Array(xs)) if xs.iter().all(fn(m) { m is String(s) && modes.contains(s) }) && unique(xs) => xs.map(fn(m) { text_of(Some(m)).unwrap() })
    _ => return Some("modes are proxy, ssh, env, file or browser")
  }
  let hs = match field(l, "hosts") {
    Some(Array(xs)) if xs.length() <= 64 && xs.iter().all(fn(h) { h is String(s) && s.length() <= 253 && host(s) }) => xs.map(fn(h) { text_of(Some(h)).unwrap() })
    _ => return Some("hosts are domain names (*.example.com allowed)")
  }
  if browser_listing_ok(kind, ms, hs) is Some(why) {
    return Some(why)
  }
  if field(l, "env") is Some(e) && !(e is String(s) && s.length() <= 100 && env_name(s)) {
    return Some("env is a variable name")
  }
  if field(l, "lasts") is Some(x) && !(x is String(s) && scopes.contains(s)) {
    return Some("lasts is once, hour or chat")
  }
  None
}

///|
/// Why `next` may not follow `prev` (none: the item's first version) in `vault`, or none when it may (station/src/
/// vault/crypto.ts `itemOk`; `copy`: a later version brought from another station, maybe of an earlier epoch).
pub fn item_ok(lock : LockView, vault : Json, prev : Json?, next : Json, copy : Bool, c : &Crypto) -> String? {
  let i = Some(next)
  let vault = Some(vault)
  if !is_object(i) || !(field(i, "v") is Some(Number(1.0, ..))) || text_of(field(i, "ws")) != Some(lock.ws) || field(i, "vault") != field(vault, "id") || !(field(i, "vault") is Some(String(_))) {
    return Some("an item is {v: 1, ws, vault, …} of this vault")
  }
  guard field(i, "id") is Some(String(id)) && ulid_id(id, "i_") else { return Some("an item's id is i_<ULID>") }
  if !int(field(i, "version")) || !int(field(i, "epoch")) || !int(field(i, "at")) {
    return Some("version, epoch and at are whole numbers")
  }
  if field(i, "deleted") is Some(d) && !(d is True) {
    return Some("deleted is true or absent")
  }
  let deleted = field(i, "deleted") is Some(True)
  if !b64(field(i, "ct"), 1 << 20) {
    return Some("ct is base64url")
  }
  let ct = text_of(field(i, "ct")).unwrap()
  if deleted && (ct != "" || field(i, "listing") is Some(_)) {
    return Some("a deleted item has no ciphertext or listing")
  }
  if !deleted && ct.length() < 38 {
    return Some("an item holds a ciphertext")
  }
  if field(i, "listing") is Some(_) && listing_ok(field(i, "listing")) is Some(why) {
    return Some(why)
  }
  if !sig_shape(field(i, "sig")) {
    return Some("an item is signed")
  }
  let epoch = num(field(i, "epoch"))
  let vault_epoch = num(field(vault, "epoch"))
  if !@history.item_epoch_ok(deleted, copy, epoch.to_int64(), vault_epoch.to_int64()) {
    return Some("an item is written under the vault's epoch " + whole(vault_epoch))
  }
  let version = num(field(i, "version"))
  match prev {
    None => if version != 0.0 && !copy { return Some("an item's first version is 0") }
    Some(_) as p => {
      if text_of(field(p, "id")) != Some(id) || field(p, "vault") != field(i, "vault") {
        return Some("another item")
      }
      if !@history.item_open(field(p, "deleted") is Some(True)) {
        return Some("the item was deleted")
      }
      let held = num(field(p, "version"))
      if !@history.follows(copy, held.to_int64(), version.to_int64()) {
        return Some(if copy { "a copy is later than version " + whole(held) } else { "version " + whole(held + 1.0) + " follows " + whole(held) })
      }
    }
  }
  let key = text_of(field(field(i, "sig"), "key")).unwrap()
  let members = strings(field(vault, "members"))
  let by = signer_of(lock, key)
  guard @role.signed_by(by is Some(_), by.map(fn(b) { has_text(members, b.0) }).unwrap_or(false)) else {
    return Some("an item is signed by a vault member's device in the lock")
  }
  if !signed_ok(next, "stillfail-vault-item/1", c) {
    return Some("the item's signature is invalid")
  }
  None
}
