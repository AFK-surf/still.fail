// One state out of a workspace said in its people's logs (station/test/lock-roster4-model.ts D4 `d4`, 2026-11-13), in
// the shape of a workspace chain's `LockState`, so that what reads a lock today (admission, `admit`, `admit_person`;
// the vault; the mesh) reads it unchanged: the list's members and stations, each bound person's app devices from the
// head of the log that binds them (each by the signing key its entries there said, `sign_key`, and those it said
// before as `sign_keys`; never the log's own key) and their web devices that count by this keeper's clock
// (put on no further ahead of it than `web_skew_secs`, not run out by it), the root's newest `open`'s settings, and
// `disabled` where the root's newest of `open` and `off` in force is `off`. No passkeys and no gateways: nothing says
// them in a person's log (the lead, 2026-11-13). `genesis`, `head` and `seq` are the root log's: its genesis hash is
// what the workspace is rooted in; its head and seq move only with the root's own log, not with the others' logs or
// the bodies, so they are no version of the list and no place in a workspace chain (whoever reads them so reads the
// root's log). Nothing calls this yet.
//
// Once a chain moved (`state4_moved`, D6, the lead's, 2026-11-14), the chain as it moved still says what the logs have
// not said yet of someone it named (`roster.mbt` `Carried` for the list): where the root's log says neither `open` nor
// `off`, its settings, on; and of a member it names, bound as it bound them (the log of their binding in the list is
// the one the chain bound them to, none where it bound them to none), their devices the log has not said (`carry_of`).
// So the handover signs `moved` alone, and nobody is waited for or asked. A member the chain bound to no log is bound
// to one by their own `bind` (`roster.mbt` `binds_of`), proved by the signer the chain names for an own app device of
// theirs; what a log of a binding of theirs took off of the chain's devices of theirs the chain carries no more.

///|
/// How far ahead of a keeper's clock a web device's `at` may be and still count.
pub let web_skew_secs : Double = 600.0

///|
pub(all) struct State4 {
  /// "on" (the root's newest of `open` and `off` in force is an `open`), "off", "not on" (neither in force: nothing
  /// says the settings yet), "no root" (the root's log is not among those given; `lock` then names no one).
  on : String
  lock : LockState
  /// Whether the root's person is bound by `~root` (`roster.mbt` `root_admit`): false where a removal that named the
  /// root's log took it out, which a reader from before reads as nothing (and where there is no root).
  root_in : Bool
}

///|
/// Workspace `ws`'s state, rooted in the person log of genesis hash `root`, from each log's active chain and the bodies
/// kept (`roster`), at `now` (unix seconds, this keeper's clock).
pub fn state4(ws : String, root : String, chains : Array[Array[Json]], bodies : Array[Json], now : Double, c : &Crypto) -> State4 {
  state4_of(ws, root, chains, bodies, now, None, c)
}

///|
/// `state4` of a workspace whose chain moved (`chain`, its active chain, the `moved` last), rooted in the log its
/// `moved` names, with what the chain as it moved still says. A chain that does not fold or did not move: "no root".
pub fn state4_moved(ws : String, chain : Array[Json], chains : Array[Array[Json]], bodies : Array[Json], now : Double, c : &Crypto) -> State4 {
  let (root, carried) = carried_of(chain, c)
  state4_of(ws, root, chains, bodies, now, carried, c)
}

///|
/// What the chain as it moved (`cr`) still says of member `sub`'s devices, bound by `lock` in the list ("" for none):
/// nothing unless that is the log the chain bound them to, or the chain bound them to none (so a member it named
/// unbound keeps their devices as an admit first binds them to a log, 2026-11-14), and, where it is a log, that log is
/// given (what it said is not known else). Then: each app device the chain names as theirs, their own
/// (`own`: put in by a device of theirs, or by an owner or admin while they had none that signs, as `handOverPlan`
/// takes them), that signs, and whose id the log never put on (its genesis, a `device`), by the chain's signer
/// (`apps`); each web page the chain names as theirs (whoever approved it: only here, only until its `exp` there, as
/// the chain had it) whose id the log never said (`web`, `web.remove`), not run out by `now` (`webs`); and of those own
/// app devices the log did put on, the chain's signer and the signers it had, by id (`sayless`), which a device the log
/// says no signer for signs with. Never a device the log took off (it put it on), nor one the chain took off or does
/// not call their own, nor one in `off`: the chain's devices of theirs that a log of a binding of theirs took off
/// (`roster.mbt` `binds_of`), so a device they took off never comes back by another log's binding.
fn carry_of(cr : Carried, sub : String, lock : String, logs : Map[String, (Person, Array[Json])], now : Double, off : Map[String, Unit]) -> Carry {
  let none : Carry = { apps: [], webs: [], sayless: Map([]) }
  let bound = cr.chain.persons.get(sub).unwrap_or("")
  guard cr.chain.members.contains(sub) && (bound == lock || bound == "") else { return none }
  let put : Map[String, Unit] = Map([])
  let said : Map[String, Unit] = Map([])
  if lock != "" {
    guard logs.get(lock) is Some((p, chain)) && p.sub == sub else { return none }
    for e in chain {
      let b = field(Some(e), "body")
      match text_of(field(Some(e), "kind")) {
        Some("genesis") => if text_of(field(b, "device") |> field("id")) is Some(id) { put[id] = () }
        Some("device") => if text_of(field(b, "id")) is Some(id) { put[id] = () }
        Some("web") | Some("web.remove") => if text_of(field(b, "id")) is Some(id) { said[id] = () }
        _ => ()
      }
    }
  }
  let out : Carry = { apps: [], webs: [], sayless: Map([]) }
  for d in cr.devices_of.get(sub).unwrap_or([]) {
    if d.kind == "app" && d.own && d.sign_key is Some(k) {
      if put.contains(d.id) {
        out.sayless[d.id] = (k, cr.chain.sign_keys.get(d.id).unwrap_or([k]))
      } else if !off.contains(d.id) {
        out.apps.push(d)
      }
    } else if d.kind == "web" && !said.contains(d.id) && d.exp is Some(exp) && now < exp {
      out.webs.push(d)
    }
  }
  out
}

///|
priv struct Carry {
  apps : Array[Device]
  webs : Array[Device]
  sayless : Map[String, (String, Array[String])]
}

///|
fn state4_of(ws : String, root : String, chains : Array[Array[Json]], bodies : Array[Json], now : Double, carried : Carried?, c : &Crypto) -> State4 {
  let (r, logs, offs) = roster_of(ws, root, chains, bodies, [], carried, c)
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
  guard r.rooted && logs.get(root) is Some((rp, _)) else { return { on: "no root", lock: s, root_in: false } }
  let set = r.settings
  // (D6: where the root's log says no `open`, the chain as it moved says the settings, off or on: on where it says no
  // `off` either. So an `open` said after an `off` says the chain's settings again; 2026-11-14, the moved workspace's
  // round on real stations: the settings of an `off` read as none, the `open` after it said no credential keys.)
  let by_chain = match (r.settings, carried) {
    (None, Some(cr)) => Some(cr.chain)
    _ => None
  }
  let s : LockState = match by_chain {
    Some(ch) => { ..s, seq: rp.seq, head: rp.head, origins: ch.origins, rp_id: ch.rp_id, cloud_keys: ch.cloud_keys, disabled: r.newest == Some("off") }
    None => {
      ..s,
      seq: rp.seq,
      head: rp.head,
      origins: arr(field(set, "origins")).filter_map(fn(o) { text_of(Some(o)) }),
      rp_id: text_of(field(set, "rp_id")).unwrap_or(""),
      cloud_keys: field(set, "cloud_keys").unwrap_or(Json::null()),
      disabled: r.newest == Some("off"),
    }
  }
  let chain_email = fn(sub : String) {
    match carried {
      Some(cr) => cr.chain.members.get(sub).map(fn(m) { m.email })
      None => None
    }
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
      None => if set is None { chain_email(m.sub) } else { text_of(field(set, "email")) }
      Some(x) if x.has_prefix("~") => chain_email(m.sub)
      Some(x) =>
        match forced.get(x) {
          Some(h) => text_of(field(bodies_by.get(h), "email"))
          None => None
        }
    }
    s.members[m.sub] = { sub: m.sub, email: email.unwrap_or(""), role: m.role }
    if m.lock != "" {
      s.persons[m.sub] = m.lock
    }
    // (the root's person bound by a real admit, `~root` out: what the chain says of their devices is of the root's
    // log, which binds them no more)
    let carry = match carried {
      Some(cr) if !(m.sub == rp.sub && m.admit is Some(_)) => carry_of(cr, m.sub, m.lock, logs, now, offs.get(m.sub).unwrap_or(Map([])))
      _ => { apps: [], webs: [], sayless: Map([]) }
    }
    if logs.get(m.lock) is Some((p, _)) && p.sub == m.sub && p.devices.length() > 0 {
      // (named by the key each signs the workspace's things with, as its log says it: one that says none is listed and
      // signs nothing here, as an app on a chain without a signing key, but where the chain as it moved names it as
      // its person's own by a signer, D6; the log's own key signs that log alone)
      for _, d in p.devices {
        let (sign_key, sign_keys) = match (d.sign_key, carry.sayless.get(d.id)) {
          (None, Some((k, ks))) => (Some(k), [..d.sign_keys, ..ks.filter(fn(x) { !d.sign_keys.contains(x) })])
          _ => (d.sign_key, d.sign_keys)
        }
        s.devices[d.id] = { id: d.id, sub: m.sub, kind: "app", label: d.label, sign_key, endpoints: None, exp: None, by: None, own: true }
        if sign_keys.length() > 0 {
          s.sign_keys[d.id] = sign_keys
        }
        if sign_key is Some(_) {
          s.signed[m.sub] = ()
        }
      }
      for _, w in p.webs {
        if w.at <= now + web_skew_secs && now < w.exp {
          s.devices[w.id] = { id: w.id, sub: m.sub, kind: "web", label: w.label, sign_key: None, endpoints: None, exp: Some(w.exp), by: None, own: true }
        }
      }
    }
    // (D6: what the chain as it moved still says of their devices, under the log's: `carry_of`; each `by` "chain", so
    // that what admits an app device of a member bound to a log by that log alone knows one their log never put on)
    for d in carry.apps {
      if !s.devices.contains(d.id) {
        s.devices[d.id] = { ..d, endpoints: None, by: Some("chain"), own: true }
        if cr_keys(carried, d.id) is Some(ks) {
          s.sign_keys[d.id] = ks
        }
        s.signed[m.sub] = ()
      }
    }
    for d in carry.webs {
      if !s.devices.contains(d.id) {
        s.devices[d.id] = { ..d, sign_key: None, endpoints: None, by: Some("chain"), own: true }
      }
    }
  }
  for k in r.stations {
    s.stations[k] = { key: k, name: "" }
  }
  let on = match (r.newest, carried) {
    (Some("off"), _) => "off"
    (Some("open"), _) | (None, Some(_)) => "on"
    _ => "not on"
  }
  let root_in = r.members.iter().any(fn(m) { m.sub == rp.sub && m.admit is None })
  { on, lock: s, root_in }
}

///|
/// The signers the chain as it moved had for device `id`.
fn cr_keys(carried : Carried?, id : String) -> Array[String]? {
  match carried {
    Some(cr) => cr.chain.sign_keys.get(id)
    None => None
  }
}
