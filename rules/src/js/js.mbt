// The rules as JS calls them (rules/js/rules.js): JS values in (as JSON.parse makes them, or the objects themselves),
// text out. A value they refuse comes back as "!" and why (no JSON text starts with it). Values are read off the JS
// value, not parsed again here: MoonBit's JSON parser refuses what JSON.parse takes (a lone surrogate's escape).

///|
#external
pub type JsValue

///|
extern "js" fn js_kind(v : JsValue) -> Int =
  #|(v) => v === null ? 0 : typeof v === "boolean" ? 1 : typeof v === "number" ? 2 : typeof v === "string" ? 3 : Array.isArray(v) ? 4 : typeof v === "object" ? 5 : 6

///|
extern "js" fn js_bool(v : JsValue) -> Bool = "(v) => v"

///|
extern "js" fn js_num(v : JsValue) -> Double = "(v) => v"

///|
extern "js" fn js_str(v : JsValue) -> String = "(v) => v"

///|
extern "js" fn js_len(v : JsValue) -> Int = "(v) => v.length"

///|
extern "js" fn js_at(v : JsValue, i : Int) -> JsValue = "(v, i) => v[i]"

///|
/// An object's own keys whose values are not undefined (as JSON.stringify and lock-form.ts leave those out).
extern "js" fn js_keys(v : JsValue) -> JsValue =
  #|(v) => Object.keys(v).filter((k) => v[k] !== undefined)

///|
extern "js" fn js_get(v : JsValue, k : String) -> JsValue = "(v, k) => v[k]"

///|
fn json_of(v : JsValue) -> Json raise @form.Invalid {
  match js_kind(v) {
    0 => Json::null()
    1 => Json::boolean(js_bool(v))
    2 => Json::number(js_num(v))
    3 => Json::string(js_str(v))
    4 => {
      let xs : Array[Json] = []
      for i in 0..<js_len(v) {
        xs.push(json_of(js_at(v, i)))
      }
      Json::array(xs)
    }
    5 => {
      let keys = js_keys(v)
      let m : Map[String, Json] = Map([])
      for i in 0..<js_len(keys) {
        let k = js_str(js_at(keys, i))
        m[k] = json_of(js_get(v, k))
      }
      Json::object(m)
    }
    _ => raise @form.Invalid("not a lock value")
  }
}

///|
pub fn canonical_of(v : JsValue) -> String {
  @form.canonical(json_of(v)) catch {
    @form.Invalid(why) => "!" + why
  }
}

///|
pub fn entry_text_of(v : JsValue) -> String {
  @form.entry_text(json_of(v)) catch {
    @form.Invalid(why) => "!" + why
  }
}

///|
fn role_of(s : String) -> @role.Role {
  match s {
    "owner" => Owner
    "admin" => Admin
    "member" => Member
    _ => Viewer
  }
}

///|
fn role_name(r : @role.Role) -> String {
  match r {
    Owner => "owner"
    Admin => "admin"
    Member => "member"
    Viewer => "viewer"
  }
}

///|
/// The lower of two roles by their names (station/src/cloud/lock.ts `lowerRole`; an unknown one is the lowest).
pub fn lower_role(a : String, b : String) -> String {
  role_name(@role.lower(role_of(a), role_of(b)))
}

// ── the lock (rules/src/lock), with the caller's cryptography ───────────────────────────────────────────────────────

///|
/// The caller's cryptography: `{sha256Hex(text), sigValid(sig, hash, origins, rpId, passkey), validKeyId(id),
/// endpointProof(ws, base, endpoint, proof)}`.
#external
pub type JsCrypto

///|
extern "js" fn js_sha256_hex(c : JsCrypto, s : String) -> String = "(c, s) => c.sha256Hex(s)"

///|
extern "js" fn js_sig_valid(c : JsCrypto, sig : JsValue, hash : String, origins : JsValue, rp_id : String, passkey : Bool) -> Bool =
  "(c, sig, hash, origins, rp, passkey) => c.sigValid(sig, hash, origins, rp, passkey)"

///|
extern "js" fn js_valid_key_id(c : JsCrypto, id : String) -> Bool = "(c, id) => c.validKeyId(id)"

///|
extern "js" fn js_endpoint_proof(c : JsCrypto, ws : String, base : String, endpoint : String, proof : String) -> Bool =
  "(c, ws, base, endpoint, proof) => c.endpointProof(ws, base, endpoint, proof)"

///|
impl @lock.Crypto for JsCrypto with sha256_hex(self, s) {
  js_sha256_hex(self, s)
}

///|
impl @lock.Crypto for JsCrypto with sig_valid(self, sig, hash, origins, rp_id, passkey) {
  js_sig_valid(self, to_js(sig), hash, to_js(Json::array(origins.map(Json::string(_)))), rp_id, passkey)
}

///|
impl @lock.Crypto for JsCrypto with valid_key_id(self, id) {
  js_valid_key_id(self, id)
}

///|
impl @lock.Crypto for JsCrypto with endpoint_proof(self, ws, base, endpoint, proof) {
  js_endpoint_proof(self, ws, base, endpoint, proof)
}

///|
extern "js" fn js_null() -> JsValue = "() => null"

///|
extern "js" fn js_of_bool(b : Bool) -> JsValue = "(b) => b"

///|
extern "js" fn js_of_num(n : Double) -> JsValue = "(n) => n"

///|
extern "js" fn js_of_str(s : String) -> JsValue = "(s) => s"

///|
extern "js" fn js_new_array() -> JsValue = "() => []"

///|
extern "js" fn js_push(a : JsValue, v : JsValue) -> Unit = "(a, v) => { a.push(v) }"

///|
extern "js" fn js_new_object() -> JsValue = "() => ({})"

///|
extern "js" fn js_put(o : JsValue, k : String, v : JsValue) -> Unit = "(o, k, v) => { o[k] = v }"

///|
fn to_js(v : Json) -> JsValue {
  match v {
    Null => js_null()
    True => js_of_bool(true)
    False => js_of_bool(false)
    Number(n, ..) => js_of_num(n)
    String(s) => js_of_str(s)
    Array(xs) => {
      let a = js_new_array()
      for x in xs {
        js_push(a, to_js(x))
      }
      a
    }
    Object(m) => {
      let o = js_new_object()
      for k, x in m {
        js_put(o, k, to_js(x))
      }
      o
    }
  }
}

///|
fn opt_num(v : JsValue) -> Double? {
  if js_kind(v) == 2 {
    Some(js_num(v))
  } else {
    None
  }
}

///|
fn opt_str(v : JsValue) -> String? {
  if js_kind(v) == 3 {
    Some(js_str(v))
  } else {
    None
  }
}

///|
/// A lock's state as plain JSON, its maps as [key, value] pairs in their order (for comparing with the TypeScript's).
fn state_json(s : @lock.LockState) -> Json {
  let device = fn(d : @lock.Device) -> Json {
    let m : Map[String, Json] = Map([("id", Json::string(d.id)), ("sub", Json::string(d.sub)), ("kind", Json::string(d.kind)), ("label", Json::string(d.label)), ("own", Json::boolean(d.own))])
    if d.sign_key is Some(k) {
      m["sign_key"] = Json::string(k)
    }
    if d.endpoints is Some(es) {
      m["endpoints"] = Json::array(es.map(Json::string(_)))
    }
    if d.exp is Some(x) {
      m["exp"] = Json::number(x)
    }
    if d.by is Some(b) {
      m["by"] = Json::string(b)
    }
    Json::object(m)
  }
  let pairs = fn(xs : Array[(String, Json)]) -> Json { Json::array(xs.map(fn(p) { Json::array([Json::string(p.0), p.1]) })) }
  Json::object(Map([
    ("ws", Json::string(s.ws)),
    ("seq", Json::number(s.seq)),
    ("head", Json::string(s.head)),
    ("genesis", Json::string(s.genesis)),
    ("origins", Json::array(s.origins.map(Json::string(_)))),
    ("rp_id", Json::string(s.rp_id)),
    ("cloud_keys", s.cloud_keys),
    ("members", pairs(s.members.iter().map(fn(p) { (p.0, Json::object(Map([("sub", Json::string(p.1.sub)), ("email", Json::string(p.1.email)), ("role", Json::string(p.1.role))]))) }).collect())),
    ("devices", pairs(s.devices.iter().map(fn(p) { (p.0, device(p.1)) }).collect())),
    ("signKeys", pairs(s.sign_keys.iter().map(fn(p) { (p.0, Json::array(p.1.map(Json::string(_)))) }).collect())),
    ("passkeys", pairs(s.passkeys.iter().map(fn(p) { (p.0, Json::object(Map([("id", Json::string(p.1.id)), ("sub", Json::string(p.1.sub)), ("key", Json::string(p.1.key)), ("label", Json::string(p.1.label)), ("own", Json::boolean(p.1.own))]))) }).collect())),
    ("signed", Json::array(s.signed.keys().map(Json::string(_)).collect())),
    ("stations", pairs(s.stations.iter().map(fn(p) { (p.0, Json::object(Map([("key", Json::string(p.1.key)), ("name", Json::string(p.1.name))]))) }).collect())),
    ("gateways", Json::array(s.gateways.keys().map(Json::string(_)).collect())),
    ("persons", pairs(s.persons.iter().map(fn(p) { (p.0, Json::string(p.1)) }).collect())),
    ("disabled", Json::boolean(s.disabled)),
  ]))
}

///|
fn entries_of(v : JsValue) -> Array[Json] raise @form.Invalid {
  let out : Array[Json] = []
  for i in 0..<js_len(v) {
    out.push(json_of(js_at(v, i)))
  }
  out
}

///|
/// A whole chain folded (station/src/cloud/lock.ts `fold`): `{state}` (as `state_json` has it) or `{error}`.
pub fn fold_js(entries : JsValue, now : JsValue, crypto : JsCrypto) -> JsValue {
  let out = try {
    let s = @lock.fold(entries_of(entries), opt_num(now), crypto)
    Json::object(Map([("state", state_json(s))]))
  } catch {
    @lock.Refused(why) | @lock.Refusal(why) => Json::object(Map([("error", Json::string(why))]))
    @form.Invalid(why) => Json::object(Map([("error", Json::string(why))]))
    e => Json::object(Map([("error", Json::string(e.to_string()))]))
  }
  to_js(out)
}

///|
/// Who each connection is in the chain's lock (station/src/cloud/lock.ts `admit`), the chain folded once: for each
/// query `{sub, endpoint, base?, proof?, now}`, `{device, role}` or `{refusal}`; `{error}` alone when the chain is none.
pub fn admit_js(entries : JsValue, fold_now : JsValue, queries : JsValue, crypto : JsCrypto) -> JsValue {
  let s = @lock.fold(entries_of(entries), opt_num(fold_now), crypto) catch {
    @lock.Refused(why) | @lock.Refusal(why) => return to_js(Json::object(Map([("error", Json::string(why))])))
    @form.Invalid(why) => return to_js(Json::object(Map([("error", Json::string(why))])))
    e => return to_js(Json::object(Map([("error", Json::string(e.to_string()))])))
  }
  let out : Array[Json] = []
  for i in 0..<js_len(queries) {
    let q = js_at(queries, i)
    let answer = try {
      let (d, role) = @lock.admit(s, js_str(js_get(q, "sub")), js_str(js_get(q, "endpoint")), opt_str(js_get(q, "base")), opt_str(js_get(q, "proof")), js_num(js_get(q, "now")), crypto)
      Json::object(Map([("device", Json::string(d.id)), ("role", Json::string(role))]))
    } catch {
      @lock.Refusal(why) | @lock.Refused(why) => Json::object(Map([("refusal", Json::string(why))]))
    }
    out.push(answer)
  }
  to_js(Json::array(out))
}

// ── the lock as station/src/cloud/lock.ts holds it ────────────────────────────────────────────────────────────────

///|
/// The rules' own state, handed to JS as it is, to be given back to `apply_js`, `signer_js` and `admit_one_js`.
extern "js" fn handle(s : @lock.LockState) -> JsValue = "(s) => s"

///|
fn held(s : @lock.LockState) -> JsValue {
  let o = js_new_object()
  js_put(o, "state", to_js(state_json(s)))
  js_put(o, "rules", handle(s))
  o
}

///|
fn refused(why : String) -> JsValue {
  let o = js_new_object()
  js_put(o, "error", js_of_str(why))
  o
}

///|
/// The lock its first entry starts (station/src/cloud/lock.ts `genesis`): `{state, rules}` or `{error}`.
pub fn genesis_js(entry : JsValue, crypto : JsCrypto) -> JsValue {
  try held(@lock.genesis(json_of(entry), crypto)) catch {
    @lock.Refused(why) | @lock.Refusal(why) => refused(why)
    @form.Invalid(why) => refused(why)
    e => refused(e.to_string())
  }
}

///|
/// The lock with one more entry (station/src/cloud/lock.ts `apply`): `{state, rules}` or `{error}`.
pub fn apply_js(prev : @lock.LockState, entry : JsValue, now : JsValue, crypto : JsCrypto) -> JsValue {
  try held(@lock.apply(prev, json_of(entry), opt_num(now), crypto)) catch {
    @lock.Refused(why) | @lock.Refusal(why) => refused(why)
    @form.Invalid(why) => refused(why)
    e => refused(e.to_string())
  }
}

///|
/// Who signed with `key` (station/src/cloud/lock.ts `signer`): `{sub, role, passkey, own}` or null.
pub fn signer_js(s : @lock.LockState, key : String, now : JsValue) -> JsValue {
  match @lock.signer(s, key, opt_num(now)) {
    None => js_null()
    Some(w) =>
      to_js(Json::object(Map([("sub", Json::string(w.sub)), ("role", Json::string(w.role)), ("passkey", Json::boolean(w.passkey)), ("own", Json::boolean(w.own))])))
  }
}

///|
/// Who a connection is (station/src/cloud/lock.ts `admit`), `who` `{sub, endpoint, base?, proof?}`: `{device, role}`
/// (the device's id) or `{refusal}`.
pub fn admit_one_js(s : @lock.LockState, who : JsValue, now : Double, crypto : JsCrypto) -> JsValue {
  let answer = try {
    let (d, role) = @lock.admit(s, js_str(js_get(who, "sub")), js_str(js_get(who, "endpoint")), opt_str(js_get(who, "base")), opt_str(js_get(who, "proof")), now, crypto)
    Json::object(Map([("device", Json::string(d.id)), ("role", Json::string(role))]))
  } catch {
    @lock.Refusal(why) | @lock.Refused(why) => Json::object(Map([("refusal", Json::string(why))]))
  }
  to_js(answer)
}

///|
/// A whole chain folded (station/src/cloud/lock.ts `fold`), as `genesis_js` and `apply_js` give it: `{state, rules}`
/// or `{error}`; the state made into JS once, at the end.
pub fn fold_held_js(entries : JsValue, now : JsValue, crypto : JsCrypto) -> JsValue {
  try held(@lock.fold(entries_of(entries), opt_num(now), crypto)) catch {
    @lock.Refused(why) | @lock.Refusal(why) => refused(why)
    @form.Invalid(why) => refused(why)
    e => refused(e.to_string())
  }
}

///|
fn person_json(p : @lock.Person) -> Json {
  let device = fn(d : @lock.PersonDevice) -> Json {
    Json::object(Map([("key", Json::string(d.key)), ("id", Json::string(d.id)), ("label", Json::string(d.label))]))
  }
  Json::object(Map([
    ("sub", Json::string(p.sub)),
    ("genesis", Json::string(p.genesis)),
    ("head", Json::string(p.head)),
    ("seq", Json::number(p.seq)),
    ("devices", Json::array(p.devices.values().map(device).collect())),
  ]))
}

///|
/// A person's own lock, its chain checked (docs/personal-lock.md): `{sub, genesis, head, seq, devices}` or `{error}`.
pub fn person_fold_js(entries : JsValue, sub : String, crypto : JsCrypto) -> JsValue {
  let answer = try person_json(@lock.fold_person(entries_of(entries), sub, crypto)) catch {
    @lock.Refused(why) | @lock.Refusal(why) => Json::object(Map([("error", Json::string(why))]))
    @form.Invalid(why) => Json::object(Map([("error", Json::string(why))]))
    e => Json::object(Map([("error", Json::string(e.to_string()))]))
  }
  to_js(answer)
}

///|
/// Who a connection is by a person's own lock, `who` as `admit_one_js` has it: `{device, role, person}` or `{refusal}`.
pub fn admit_person_js(s : @lock.LockState, who : JsValue, entries : JsValue, crypto : JsCrypto) -> JsValue {
  let answer = try {
    let (d, role, person) = @lock.admit_person(s, js_str(js_get(who, "sub")), js_str(js_get(who, "endpoint")), opt_str(js_get(who, "base")), opt_str(js_get(who, "proof")), entries_of(entries), crypto)
    Json::object(Map([("device", Json::string(d.id)), ("role", Json::string(role)), ("person", person_json(person))]))
  } catch {
    @lock.Refusal(why) | @lock.Refused(why) => Json::object(Map([("refusal", Json::string(why))]))
    @form.Invalid(why) => Json::object(Map([("refusal", Json::string(why))]))
    e => Json::object(Map([("refusal", Json::string(e.to_string()))]))
  }
  to_js(answer)
}

// ── the vault's rules, as station/src/vault/crypto.ts calls them ──────────────────────────────────────────────────

///|
extern "js" fn js_entries(m : JsValue) -> JsValue = "(m) => [...m]"

///|
extern "js" fn js_record_sig_valid(c : JsCrypto, sig : JsValue, tag : String, text : String) -> Bool =
  "(c, sig, tag, text) => c.recordSigValid(sig, tag, text)"

///|
impl @vault.Crypto for JsCrypto with record_sig_valid(self, sig, tag, text) {
  js_record_sig_valid(self, to_js(sig), tag, text)
}

///|
/// The lock as the vault reads it, off a station/src/cloud/lock.ts `LockState` (its maps JS Maps).
fn lock_view(lock : JsValue) -> @vault.LockView {
  let members : Map[String, Unit] = Map([])
  let ms = js_entries(js_get(lock, "members"))
  for i in 0..<js_len(ms) {
    members[js_str(js_at(js_at(ms, i), 0))] = ()
  }
  let devices : Map[String, @vault.Device] = Map([])
  let ds = js_entries(js_get(lock, "devices"))
  for i in 0..<js_len(ds) {
    let d = js_at(js_at(ds, i), 1)
    devices[js_str(js_at(js_at(ds, i), 0))] = {
      sub: js_str(js_get(d, "sub")),
      kind: js_str(js_get(d, "kind")),
      sign_key: opt_str(js_get(d, "sign_key")),
      own: js_kind(js_get(d, "own")) == 1 && js_bool(js_get(d, "own")),
    }
  }
  let sign_keys : Map[String, Array[String]] = Map([])
  let ks = js_entries(js_get(lock, "signKeys"))
  for i in 0..<js_len(ks) {
    let had = js_at(js_at(ks, i), 1)
    sign_keys[js_str(js_at(js_at(ks, i), 0))] = Array::makei(js_len(had), fn(j) { js_str(js_at(had, j)) })
  }
  { ws: js_str(js_get(lock, "ws")), members, devices, sign_keys }
}

///|
/// A record as JS holds it: none for `undefined` (or null, for what may be none), else its JSON.
fn record(v : JsValue, null_none~ : Bool = false) -> Json? {
  if js_kind(v) == 6 || (null_none && js_kind(v) == 0) {
    return None
  }
  Some(json_of(v)) catch {
    _ => None
  }
}

///|
fn why_js(why : String?) -> JsValue {
  match why {
    Some(w) => js_of_str(w)
    None => js_null()
  }
}

///|
/// station/src/vault/crypto.ts `certOk`: why the certificate is not one (text) or null.
pub fn cert_ok_js(lock : JsValue, cert : JsValue, ever : Bool, crypto : JsCrypto) -> JsValue {
  why_js(@vault.cert_ok(lock_view(lock), record(cert), ever, crypto))
}

///|
/// station/src/vault/crypto.ts `vaultOk`: why `next` may not follow `prev` (null: none held), or null.
pub fn vault_ok_js(lock : JsValue, prev : JsValue, next : JsValue, copy : Bool, crypto : JsCrypto) -> JsValue {
  why_js(@vault.vault_ok(lock_view(lock), record(prev, null_none=true), record(next).unwrap_or(Json::null()), copy, crypto))
}

///|
/// station/src/vault/crypto.ts `itemOk`: why `next` may not follow `prev` (null: none held) in `vault`, or null.
pub fn item_ok_js(lock : JsValue, vault : JsValue, prev : JsValue, next : JsValue, copy : Bool, crypto : JsCrypto) -> JsValue {
  why_js(@vault.item_ok(lock_view(lock), record(vault).unwrap_or(Json::null()), record(prev, null_none=true), record(next).unwrap_or(Json::null()), copy, crypto))
}

///|
/// station/src/vault/crypto.ts `browserListingOk`, of `{kind, modes, hosts}`.
pub fn browser_listing_ok_js(l : JsValue) -> JsValue {
  let ms = js_get(l, "modes")
  let hs = js_get(l, "hosts")
  why_js(@vault.browser_listing_ok(
    js_str(js_get(l, "kind")),
    Array::makei(js_len(ms), fn(i) { js_str(js_at(ms, i)) }),
    Array::makei(js_len(hs), fn(i) { js_str(js_at(hs, i)) }),
  ))
}

///|
/// station/src/vault/crypto.ts `signerOf`: `{sub, device}` of the own app device signing with `key`, or null.
pub fn signer_of_js(lock : JsValue, key : String) -> JsValue {
  match @vault.signer_of(lock_view(lock), key) {
    Some((sub, device)) => to_js(Json::object(Map([("sub", Json::string(sub)), ("device", Json::string(device))])))
    None => js_null()
  }
}

///|
fn supersedes_of(a : JsValue, b : JsValue, number : String) -> Bool {
  let (a, b) = try (json_of(a), json_of(b)) catch { _ => return false }
  let n = fn(v : Json, k : String) -> Int64 {
    match v {
      Object(m) =>
        match m.get(k) {
          Some(Number(x, ..)) => x.to_int64()
          _ => 0L
        }
      _ => 0L
    }
  }
  let deleted = fn(v : Json) { v is Object(m) && m.get("deleted") is Some(True) }
  let text = try @form.canonical(a).compare(@form.canonical(b)) catch { _ => return false }
  @history.supersedes(n(a, number), deleted(a), n(a, "epoch"), n(b, number), deleted(b), n(b, "epoch"), text)
}

///|
/// Whether vault version `a` is kept over `b`, by every station and device alike (rules/src/history `supersedes`):
/// the later; of one seq, the one that deletes it, then the one under the later key, then the greater text.
pub fn vault_supersedes_js(a : JsValue, b : JsValue) -> Bool {
  supersedes_of(a, b, "seq")
}

///|
/// Whether item version `a` is kept over `b`, as `vault_supersedes_js` has it of vaults (by `version`).
pub fn item_supersedes_js(a : JsValue, b : JsValue) -> Bool {
  supersedes_of(a, b, "version")
}
