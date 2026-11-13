// One state out of a workspace said in its people's logs (station/test/lock-roster4-model.ts D4 `d4`, 2026-11-13), in
// the shape of a workspace chain's `LockState`, so that what reads a lock today (admission, `admit`, `admit_person`;
// the vault; the mesh) reads it unchanged: the list's members and stations, each bound person's app devices from the
// head of the log that binds them (their keys as `sign_keys`) and their web devices that count by this keeper's clock
// (put on no further ahead of it than `web_skew_secs`, not run out by it), the root's newest `open`'s settings, and
// `disabled` where the root's newest of `open` and `off` in force is `off`. No passkeys and no gateways: nothing says
// them in a person's log (the lead, 2026-11-13). `genesis`, `head` and `seq` are the root log's: its genesis hash is
// what the workspace is rooted in; its head and seq move only with the root's own log, not with the others' logs or
// the bodies, so they are no version of the list and no place in a workspace chain (whoever reads them so reads the
// root's log). Nothing calls this yet.

///|
/// How far ahead of a keeper's clock a web device's `at` may be and still count.
pub let web_skew_secs : Double = 600.0

///|
pub(all) struct State4 {
  /// "on" (the root's newest of `open` and `off` in force is an `open`), "off", "not on" (neither in force: nothing
  /// says the settings yet), "no root" (the root's log is not among those given; `lock` then names no one).
  on : String
  lock : LockState
}

///|
/// Workspace `ws`'s state, rooted in the person log of genesis hash `root`, from each log's active chain and the bodies
/// kept (`roster`), at `now` (unix seconds, this keeper's clock).
pub fn state4(ws : String, root : String, chains : Array[Array[Json]], bodies : Array[Json], now : Double, c : &Crypto) -> State4 {
  let (r, logs) = roster_of(ws, root, chains, bodies, [], c)
  let s : LockState = {
    ws,
    seq: 0.0,
    head: root,
    genesis: root,
    origins: [],
    rp_id: "",
    cloud_keys: Json::null(),
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
  guard r.rooted && logs.get(root) is Some((rp, _)) else { return { on: "no root", lock: s } }
  let set = r.settings
  let s : LockState = {
    ..s,
    seq: rp.seq,
    head: rp.head,
    origins: arr(field(set, "origins")).filter_map(fn(o) { text_of(Some(o)) }),
    rp_id: text_of(field(set, "rp_id")).unwrap_or(""),
    cloud_keys: field(set, "cloud_keys").unwrap_or(Json::null()),
    disabled: r.newest == Some("off"),
  }
  // The bodies in force by their entries' hashes: an admit's says its person's email; the root's is its `open`'s.
  let forced : Map[String, String] = Map([])
  for f in r.in_force {
    forced[f.0] = f.1
  }
  let bodies_by : Map[String, Json] = Map([])
  for b in bodies {
    if (try Ok(body_hash(b, c)) catch { e => Err(e) }) is Ok(h) {
      bodies_by[h] = b
    }
  }
  for m in r.members {
    let email = match m.admit {
      None => text_of(field(set, "email"))
      Some(x) =>
        match forced.get(x) {
          Some(h) => text_of(field(bodies_by.get(h), "email"))
          None => None
        }
    }
    s.members[m.sub] = { sub: m.sub, email: email.unwrap_or(""), role: m.role }
    s.persons[m.sub] = m.lock
    guard logs.get(m.lock) is Some((p, _)) && p.sub == m.sub && p.devices.length() > 0 else { continue }
    for _, d in p.devices {
      s.devices[d.id] = { id: d.id, sub: m.sub, kind: "app", label: d.label, sign_key: Some(d.key), endpoints: None, exp: None, by: None, own: true }
      s.sign_keys[d.id] = [d.key]
    }
    s.signed[m.sub] = ()
    for _, w in p.webs {
      if w.at <= now + web_skew_secs && now < w.exp {
        s.devices[w.id] = { id: w.id, sub: m.sub, kind: "web", label: w.label, sign_key: None, endpoints: None, exp: Some(w.exp), by: None, own: true }
      }
    }
  }
  for k in r.stations {
    s.stations[k] = { key: k, name: "" }
  }
  let on = match r.newest {
    Some("off") => "off"
    Some("open") => "on"
    _ => "not on"
  }
  { on, lock: s }
}
