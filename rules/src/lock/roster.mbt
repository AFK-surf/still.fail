// A workspace's list from its people's own logs (station/test/lock-roster-model.ts `roster`, `rule=grounded`, the
// coordinator's correction of 2026-11-12): who belongs to it, in which role, by which of their person logs, and its
// stations, from the statements on each log's active chain (`ws.*`, `fold_person_ws`). The workspace is rooted in one
// person log (its genesis pinned): that person is its owner by it, always.
//
// The statements are a Dung argumentation framework, labelled by its grounded semantics (its least fixed point):
// - arguments: each admit (`a:<hash>`, "this admit holds"); for every (person, log) pair that signs an admit or a
//   cancellation and each role needed to (`n:<sub>|<lock>|<role>`, admin or owner: "the pair stands below that
//   role"); for each removal and each admit it names about the same person (`c:<removal>|<admit>`, "this cancellation
//   counts");
// - attacks: every admit giving a pair a role at least ρ attacks `n:<pair>|ρ` (a standing holds by any one of its
//   admits); `n:<signer>|<the role needed>` attacks each admit and cancellation its pair signed (owner to give owner,
//   admin to give admin or member; owner to cancel an owner's admit, admin the others); a cancellation attacks the admit
//   it names. The root's pair has no `n`: it always stands, as owner.
// - IN: every attacker OUT; OUT: some attacker IN; the rest UNDECIDED, taken as out.
// Choices kept from the model: the statements of a log are its genesis's person's; every admitted (person, log) counts
// as theirs for what they sign; the one a person is bound by (whose devices are let in) is the admit in force giving the
// highest role, then the smallest hash; the root's binding never moves. A station is admitted by a pair that stands as
// owner or admin, and cancelled by one.

///|
/// A statement of the workspace on a log's active chain.
priv struct Stmt {
  hash : String
  kind : String
  body : Json?
  /// The log's genesis hash, and its person.
  log : String
  by : String
}

///|
/// A person in the list: their role, the person log they are bound by, the admit that binds them (none for the root),
/// and the keys on that log's head where it was given and is theirs.
pub(all) struct Bound {
  sub : String
  role : String
  lock : String
  admit : String?
  keys : Array[String]?
}

///|
/// What a statement did: its label (`in`, `out`, `undec`), why it has no effect where it has none, and the statement
/// that decided that where one did.
pub(all) struct Said {
  hash : String
  kind : String
  log : String
  by : String
  label : String
  why : String?
  decided : String?
}

///|
pub(all) struct Roster {
  /// Whether the root's log was given (else nothing is told).
  rooted : Bool
  members : Array[Bound]
  stations : Array[String]
  /// Every (person, log) that stands, with its highest role; those a circle of removals leaves undecided.
  pairs : Array[(String, String, String)]
  undecided : Array[(String, String)]
  /// The admits a cancellation that counts took out.
  cancelled : Array[String]
  statements : Array[Said]
  /// Every argument's label, by its name.
  labels : Array[(String, String)]
  /// The chains given that are not one (their genesis's hash where it has one), and why.
  refused : Array[(String, String)]
}

///|
fn rank_of(role : String) -> Int {
  @role.rank(role_named(role))
}

///|
fn mgr(role : String?) -> Bool {
  role == Some("owner") || role == Some("admin")
}

///|
/// The workspace `ws`'s list, rooted in the person log of genesis hash `root`, from `chains`: the active chain of each
/// person log known (genesis first), each checked again (`fold_person_ws`). Two chains of one log: the longer, then the
/// one of the lower head hash. Whatever the order of `chains`, the same list, each part of it in MoonBit's `String`
/// order (a shorter text first).
pub fn roster(ws : String, root : String, chains : Array[Array[Json]], c : &Crypto) -> Roster {
  let refused : Array[(String, String)] = []
  let logs : Map[String, (Person, Array[Json])] = Map([])
  for chain in chains {
    let g = if chain.length() > 0 { entry_hash(chain[0], c) catch { _ => "" } } else { "" }
    let sub = if chain.length() > 0 { text_of(field(Some(chain[0]), "body") |> field("sub")).unwrap_or("") } else { "" }
    let p = match (try Ok(fold_person_ws(chain, sub, c)) catch { e => Err(e) }) {
      Ok(p) => p
      Err(Refused(why)) | Err(Refusal(why)) => {
        refused.push((g, why))
        continue
      }
    }
    match logs.get(p.genesis) {
      Some((q, _)) if q.seq > p.seq || (q.seq == p.seq && q.head <= p.head) =>
        refused.push((p.genesis, "another chain of the same log was taken"))
      Some(_) => {
        refused.push((p.genesis, "another chain of the same log was taken"))
        logs[p.genesis] = (p, chain)
      }
      None => logs[p.genesis] = (p, chain)
    }
  }
  refused.sort_by(fn(a, b) { a.compare(b) })
  let empty : Roster = { rooted: false, members: [], stations: [], pairs: [], undecided: [], cancelled: [], statements: [], labels: [], refused }
  guard logs.get(root) is Some((root_person, _)) else { return empty }
  let root_sub = root_person.sub
  let root_pair = root_sub + "|" + root
  // The statements, by their logs in the order of their hashes (none of it changes what is labelled).
  let stmts : Array[Stmt] = []
  let gs = logs.keys().collect()
  gs.sort()
  for g in gs {
    let (p, chain) = logs.get(g).unwrap()
    for i in 1..<chain.length() {
      let e = chain[i]
      let kind = text_of(field(Some(e), "kind")).unwrap_or("")
      let b = field(Some(e), "body")
      if kind.has_prefix("ws.") && text_of(field(b, "ws")) == Some(ws) {
        stmts.push({ hash: entry_hash(e, c) catch { _ => "" }, kind, body: b, log: g, by: p.sub })
      }
    }
  }
  let txt = fn(s : Stmt, k : String) { text_of(field(s.body, k)).unwrap_or("") }
  let pair_of = fn(s : Stmt) { s.by + "|" + s.log }
  let admits = stmts.filter(fn(s) { s.kind == "ws.member" })
  let removes = stmts.filter(fn(s) { s.kind == "ws.member.remove" })
  let admit_at : Map[String, Stmt] = Map([])
  for a in admits {
    admit_at[a.hash] = a
  }
  // The arguments and their attackers.
  let attackers : Map[String, Array[String]] = Map([])
  let arg = fn(id : String) -> Array[String] {
    match attackers.get(id) {
      Some(xs) => xs
      None => {
        let xs = []
        attackers[id] = xs
        xs
      }
    }
  }
  let lacks : Map[String, (String, String)] = Map([])
  let lack = fn(s : Stmt, role : String) -> String {
    let need = if role == "owner" { "owner" } else { "admin" }
    let id = "n:" + pair_of(s) + "|" + need
    ignore(arg(id))
    lacks[id] = (pair_of(s), need)
    id
  }
  for a in admits {
    let id = "a:" + a.hash
    let xs = arg(id)
    if pair_of(a) != root_pair {
      xs.push(lack(a, txt(a, "role")))
    }
  }
  let cancels_of : Map[String, Array[String]] = Map([])
  for r in removes {
    let ids : Array[String] = []
    for x in arr(field(r.body, "cancels")) {
      guard text_of(Some(x)) is Some(h) && admit_at.get(h) is Some(a) && txt(a, "sub") == txt(r, "sub") else { continue }
      let id = "c:" + r.hash + "|" + a.hash
      let xs = arg(id)
      if pair_of(r) != root_pair {
        xs.push(lack(r, txt(a, "role")))
      }
      arg("a:" + a.hash).push(id)
      ids.push(id)
    }
    cancels_of[r.hash] = ids
  }
  for id, (pair, role) in lacks {
    for a in admits {
      if txt(a, "sub") + "|" + txt(a, "lock") == pair && rank_of(txt(a, "role")) >= rank_of(role) {
        attackers.get(id).unwrap().push("a:" + a.hash)
      }
    }
  }
  // The grounded labelling.
  let label : Map[String, String] = Map([])
  let mut changed = true
  while changed {
    changed = false
    for id, by in attackers {
      if label.contains(id) {
        continue
      }
      if by.iter().any(fn(x) { label.get(x) == Some("in") }) {
        label[id] = "out"
        changed = true
      } else if by.iter().all(fn(x) { label.get(x) == Some("out") }) {
        label[id] = "in"
        changed = true
      }
    }
  }
  for id, _ in attackers {
    if !label.contains(id) {
      label[id] = "undec"
    }
  }
  // The pairs that stand, with their role; those left undecided; the admits cancelled.
  let pairs : Map[String, (String, String, String)] = Map([])
  let undecided : Map[String, (String, String)] = Map([])
  let cancelled : Array[String] = []
  let counts = fn(r : Stmt, a : Stmt) { label.get("c:" + r.hash + "|" + a.hash) == Some("in") }
  for a in admits {
    let l = label.get("a:" + a.hash).unwrap()
    let k = txt(a, "sub") + "|" + txt(a, "lock")
    if l == "in" {
      match pairs.get(k) {
        Some((_, _, was)) if rank_of(txt(a, "role")) <= rank_of(was) => ()
        _ => pairs[k] = (txt(a, "sub"), txt(a, "lock"), txt(a, "role"))
      }
    } else if l == "undec" && mgr(Some(txt(a, "role"))) {
      undecided[k] = (txt(a, "sub"), txt(a, "lock"))
    }
    if l == "out" && removes.iter().any(fn(r) { counts(r, a) }) {
      cancelled.push(a.hash)
    }
  }
  pairs[root_pair] = (root_sub, root, "owner")
  for k, _ in pairs {
    undecided.remove(k)
  }
  let role_of_pair = fn(s : Stmt) { pairs.get(pair_of(s)).map(fn(p) { p.2 }) }
  // Whom the list binds by which log: the root by its own; anyone else by the admit in force of the highest role,
  // then the smallest hash.
  let best : Map[String, (String, String, String?)] = Map([(root_sub, ("owner", root, None))])
  for a in admits {
    if label.get("a:" + a.hash) != Some("in") || txt(a, "sub") == root_sub {
      continue
    }
    let role = txt(a, "role")
    let takes = match best.get(txt(a, "sub")) {
      None => true
      Some((was, _, admit)) =>
        rank_of(role) > rank_of(was) ||
        (role == was &&
        (match admit {
          Some(x) => a.hash < x
          None => false
        }))
    }
    if takes {
      best[txt(a, "sub")] = (role, txt(a, "lock"), Some(a.hash))
    }
  }
  // Stations: admitted by a pair that stands as owner or admin, unless one such cancelled them.
  let st_cancelled : Map[String, String] = Map([])
  for r in stmts {
    if r.kind == "ws.station.remove" && mgr(role_of_pair(r)) {
      for x in arr(field(r.body, "cancels")) {
        if text_of(Some(x)) is Some(h) {
          let k = h + "|" + txt(r, "key")
          match st_cancelled.get(k) {
            Some(was) if was <= r.hash => ()
            _ => st_cancelled[k] = r.hash
          }
        }
      }
    }
  }
  let stations : Map[String, Unit] = Map([])
  for s in stmts {
    if s.kind == "ws.station" && mgr(role_of_pair(s)) && !st_cancelled.contains(s.hash + "|" + txt(s, "key")) {
      stations[txt(s, "key")] = ()
    }
  }
  // What each statement did.
  let undecided_pair = fn(s : Stmt) { undecided.contains(pair_of(s)) }
  let not_in = fn(s : Stmt) {
    if undecided_pair(s) { "its signer is undecided (a circle of removals)" } else { "its signer is not in the list" }
  }
  let said : Array[Said] = []
  for s in stmts {
    let mut l = "in"
    let mut why : String? = None
    let mut decided : String? = None
    match s.kind {
      "ws.member" => {
        l = label.get("a:" + s.hash).unwrap()
        if l == "undec" {
          why = Some(if undecided_pair(s) { "its signer is undecided (a circle of removals)" } else { "the admit is undecided (named by an undecided removal)" })
        } else if l == "out" {
          let by = removes.filter(fn(r) { counts(r, s) }).map(fn(r) { r.hash })
          by.sort()
          if by.length() > 0 {
            why = Some("admit cancelled")
            decided = Some(by[0])
          } else if !mgr(role_of_pair(s)) {
            why = Some(not_in(s))
          } else {
            why = Some("its signer may not give that role")
          }
        } else if best.get(txt(s, "sub")) is Some((role, lock, admit)) && (role != txt(s, "role") || lock != txt(s, "lock")) {
          why = Some("another admit of the person outranks it (a lower role given later changes nothing)")
          decided = admit
        }
      }
      "ws.member.remove" => {
        let cs = cancels_of.get(s.hash).unwrap_or([]).map(fn(id) { label.get(id).unwrap() })
        if cs.contains("in") {
          ()
        } else if cs.contains("undec") {
          l = "undec"
          why = Some("its cancellations are undecided (a circle of removals)")
        } else if cs.length() > 0 {
          l = "out"
          why = Some(if mgr(role_of_pair(s)) { "it may cancel none of what it names" } else { not_in(s) })
        }
      }
      "ws.station" =>
        if !mgr(role_of_pair(s)) {
          l = "out"
          why = Some(not_in(s))
        } else if st_cancelled.get(s.hash + "|" + txt(s, "key")) is Some(r) {
          l = "out"
          why = Some("station cancelled")
          decided = Some(r)
        }
      _ =>
        if !mgr(role_of_pair(s)) {
          l = "out"
          why = Some(not_in(s))
        }
    }
    said.push({ hash: s.hash, kind: s.kind, log: s.log, by: s.by, label: l, why, decided })
  }
  said.sort_by(fn(a, b) { a.hash.compare(b.hash) })
  let members : Array[Bound] = []
  let subs = best.keys().collect()
  subs.sort()
  for sub in subs {
    let (role, lock, admit) = best.get(sub).unwrap()
    let keys = match logs.get(lock) {
      Some((p, _)) if p.sub == sub => {
        let ks = p.devices.keys().collect()
        ks.sort()
        Some(ks)
      }
      _ => None
    }
    members.push({ sub, role, lock, admit, keys })
  }
  let sts = stations.keys().collect()
  sts.sort()
  let ps = pairs.values().collect()
  ps.sort_by(fn(a, b) { a.compare(b) })
  let us = undecided.values().collect()
  us.sort_by(fn(a, b) { a.compare(b) })
  cancelled.sort()
  let ls = label.iter().collect()
  ls.sort_by(fn(a, b) { a.0.compare(b.0) })
  { rooted: true, members, stations: sts, pairs: ps, undecided: us, cancelled, statements: said, labels: ls, refused }
}
