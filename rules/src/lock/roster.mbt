// A workspace's list from its people's own logs (station/test/lock-roster4-model.ts `inForce`, `openOff`, `rosterIn`,
// under its defaults, 2026-11-13; the list itself lock-roster-model.ts `roster`, `rule=grounded`): who belongs to it, in
// which role, by which of their person logs, its stations and its settings, from the statements in force. A statement is
// a commitment `ws {t, h}` in its signer's log with its body kept apart (`body.mbt`); it is in force where its entry is
// on its log's active chain (`chain.mbt`), under the workspace's tag in that log, its body is kept, and so is every body
// along its `prev` chain back to the first (`order=whole` is how signers choose `prev`; a keeper's rule is only this).
// The entries of the tag whose body is not kept are `lacking`: what a keeper asks for. A removal names the bodies it
// takes back (`cancels=h`): it cancels every statement in force of those bodies. The workspace is rooted in one person
// log (its genesis pinned, or named by the old chain's `moved`): what its pair says always counts, as an owner's; its
// settings and whether it is on are said only there (`open`, `off`: the newest in force; nothing is ever let go by an
// entry). That its person is in the list, bound by it, is an admit like any other (`~root`, below; the lead's,
// 2026-11-14): an owner's removal of them that names the root's genesis hash takes it out.
//
// The statements are a Dung argumentation framework, labelled by its grounded semantics (its least fixed point):
// - arguments: each admit (`a:<hash>`, "this admit holds"); for every (person, log) pair that signs an admit or a
//   cancellation and each role needed to (`n:<sub>|<lock>|<role>`, admin or owner: "the pair stands below that
//   role"); for each removal and each admit it names about the same person (`c:<removal>|<admit>`, "this cancellation
//   counts");
// - attacks: every admit giving a pair a role at least ρ attacks `n:<pair>|ρ` (a standing holds by any one of its
//   admits); `n:<signer>|<the role needed>` attacks each admit and cancellation its pair signed (owner to give owner,
//   admin to give admin, member or viewer; owner to cancel an owner's admit, admin the others); a cancellation attacks
//   the admit it names. The root's pair has no `n`: it always stands, as owner.
// - IN: every attacker OUT; OUT: some attacker IN; the rest UNDECIDED, taken as out.
// Choices kept from the model: the statements of a log are its genesis's person's; every admitted (person, log) counts
// as theirs for what they sign; the one a person is bound by (whose devices are let in) is the admit in force giving the
// highest role, then the smallest hash; the root's person by `~root` while it is in (the root's pair is no less an
// owner for what it signs where it is out). A station is admitted by a pair that stands as
// owner or admin, and cancelled by one. Hashes named in the list (`a:`, `c:`, `admit`, `cancelled`) are the entries'.

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
/// The chain as it moved (station/test/lock-roster4-model.ts D6, the lead's, 2026-11-14): its `moved` entry's hash and
/// the chain's state at it, frozen (nothing follows a `moved`). What the logs have not said yet of someone it named, it
/// still says: one admit by the root's person of each member it names but the root's person (`~<moved>/m/<sub>`: their
/// role and email there, the log it bound them to, "" where none) and one statement of each of its stations
/// (`~<moved>/s/<key>`), all in force, never lacking; a removal (`member.remove`, `station.remove`) cancels the one of
/// its subject as if its `cancels` named it, named or not (it may name them all by the `moved` entry's hash): so one
/// said before the chain was read so (build 9040's move), naming the admits of its time alone, takes out whom it did. So taking someone out, a role
/// changed (removed and admitted again), whom a removal takes out besides and a circle of removals are as for any
/// statement. Their devices are `state4.mbt`'s (`carry_of`).
pub(all) struct Carried {
  moved : String
  chain : LockState
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
  /// The statements in force (their entry's hash, their body's), and the entries of the workspace's tag on an active
  /// chain whose body is not kept, each in the order of their hashes.
  in_force : Array[(String, String)]
  lacking : Array[String]
  /// D6: the keys of the app devices the chain as it moved still says (`carry_of`'s `apps`, by the key each signs
  /// with), and whose they are; none where no chain is carried.
  carried_keys : Array[(String, String)]
  /// The newest of `open` and `off` in force on the root's active chain (its kind), and the newest `open`'s body.
  newest : String?
  settings : Json?
}

///|
/// The root's person's implicit admit (`~root`), by the hash it is named by in the list's labels.
pub let root_admit : String = "~root"

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
/// person log known (genesis first), each checked again (`fold_person`), and `bodies`, the bodies kept (of any
/// workspace: each by its hash, one whose shape is no statement's taken as not kept). Two chains of one log: the
/// longer, then the one of the lower head hash. Whatever the order of `chains` and `bodies`, the same list, each part
/// of it in MoonBit's `String` order (a shorter text first).
pub fn roster(ws : String, root : String, chains : Array[Array[Json]], bodies : Array[Json], c : &Crypto) -> Roster {
  roster_of(ws, root, chains, bodies, [], None, c).0
}

///|
/// `roster_without` of a workspace whose chain moved (`chain`, its active chain, the `moved` last): rooted in the log
/// that `moved` names, with what the chain as it moved still says (`Carried`). A chain that does not fold, or does not
/// end in a `moved`, roots it in nothing ("no root": nothing is told).
pub fn roster_moved(ws : String, chain : Array[Json], chains : Array[Array[Json]], bodies : Array[Json], without : Array[String], c : &Crypto) -> Roster {
  let (root, carried) = carried_of(chain, c)
  roster_of(ws, root, chains, bodies, without, carried, c).0
}

///|
/// The root a moved chain names and the chain as it moved, of its active chain (`moved` last): ("", none) where it does
/// not fold or did not move.
pub fn carried_of(chain : Array[Json], c : &Crypto) -> (String, Carried?) {
  let s = fold(chain, None, c) catch { _ => return ("", None) }
  match s.moved {
    Some(root) => (root, Some({ moved: s.head, chain: s }))
    None => ("", None)
  }
}

///|
/// `roster` with the statements of the bodies of hash `without` left out of those in force, once what is in force is
/// decided (a later statement whose `prev` chain goes through one left out still counts): the list as it would be
/// without them, which says whom a removal took out (station/test/lock-roster4-model.ts `admitsBefore`, its `left`).
pub fn roster_without(ws : String, root : String, chains : Array[Array[Json]], bodies : Array[Json], without : Array[String], c : &Crypto) -> Roster {
  roster_of(ws, root, chains, bodies, without, None, c).0
}

///|
/// `roster`, with the logs it took (by their genesis's hash) and, by member, the chain's devices of theirs their
/// bindings' logs took off (`binds_of`); `without` as `roster_without` has it; `carried`, the chain as it moved, where
/// one did.
fn roster_of(ws : String, root : String, chains : Array[Array[Json]], bodies : Array[Json], without : Array[String], carried : Carried?, c : &Crypto) -> (Roster, Map[String, (Person, Array[Json])], Map[String, Map[String, Unit]]) {
  let refused : Array[(String, String)] = []
  let logs : Map[String, (Person, Array[Json])] = Map([])
  for chain in chains {
    let g = if chain.length() > 0 { entry_hash(chain[0], c) catch { _ => "" } } else { "" }
    let sub = if chain.length() > 0 { text_of(field(Some(chain[0]), "body") |> field("sub")).unwrap_or("") } else { "" }
    let p = match (try Ok(fold_person(chain, sub, c)) catch { e => Err(e) }) {
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
  // The bodies kept, by their hashes.
  let kept : Map[String, Json] = Map([])
  for b in bodies {
    if body_why(b) is None {
      if (try Ok(body_hash(b, c)) catch { e => Err(e) }) is Ok(h) {
        kept[h] = b
      }
    }
  }
  let whole = fn(b : Json) -> Bool {
    let mut p = text_of(field(Some(b), "prev"))
    let mut n = 0
    while p is Some(x) && n < 10000 {
      match kept.get(x) {
        None => return false
        Some(q) => p = text_of(field(Some(q), "prev"))
      }
      n = n + 1
    }
    true
  }
  // The statements in force, by the logs in the order of their hashes, each in its chain's order; what is lacking.
  let gs = logs.keys().collect()
  gs.sort()
  let in_force : Array[(String, String, Json, String)] = []
  let lacking : Array[String] = []
  for g in gs {
    let (_, chain) = logs.get(g).unwrap()
    let t = ws_tag(ws, g, c)
    for i in 1..<chain.length() {
      let e = Some(chain[i])
      guard text_of(field(e, "kind")) == Some("ws") && (field(e, "body") |> field("t") |> text_of) == Some(t) else { continue }
      let x = entry_hash(chain[i], c) catch { _ => continue }
      let hb = (field(e, "body") |> field("h") |> text_of).unwrap_or("")
      match kept.get(hb) {
        Some(b) if text_of(field(Some(b), "ws")) == Some(ws) => if whole(b) { in_force.push((x, hb, b, g)) }
        _ => lacking.push(x)
      }
    }
  }
  lacking.sort()
  let in_force = if without.length() == 0 { in_force } else { in_force.filter(fn(f) { !without.contains(f.1) }) }
  let forced = in_force.map(fn(f) { (f.0, f.1) })
  forced.sort_by(fn(a, b) { a.compare(b) })
  // On or off, and the settings: the root's alone.
  let mut newest : String? = None
  let mut settings : Json? = None
  for f in in_force {
    if f.3 == root {
      match text_of(field(Some(f.2), "kind")) {
        Some("open") => {
          newest = Some("open")
          settings = Some(f.2)
        }
        Some("off") => newest = Some("off")
        _ => ()
      }
    }
  }
  let empty : Roster = {
    rooted: false, members: [], stations: [], pairs: [], undecided: [], cancelled: [], statements: [], labels: [], refused,
    in_force: forced, lacking, newest, settings, carried_keys: [],
  }
  let offs : Map[String, Map[String, Unit]] = Map([])
  guard logs.get(root) is Some((root_person, _)) else { return (empty, logs, offs) }
  let root_sub = root_person.sub
  let root_pair = root_sub + "|" + root
  // The statements of the list, each as round three had it in the clear: its kind `ws.<kind>`, its body with what a
  // removal cancels named by the entries in force of those bodies (none of it changes what is labelled).
  let by_body : Map[String, Array[String]] = Map([])
  for f in in_force {
    match by_body.get(f.1) {
      Some(xs) => xs.push(f.0)
      None => by_body[f.1] = [f.0]
    }
  }
  // D6: the chain's statements, as the root's (`Carried`), named together by the `moved` entry's hash.
  let carried_stmts : Array[Stmt] = []
  // (each by its subject, `m/<sub>` or `s/<key>`)
  let carried_ids : Map[String, String] = Map([])
  if carried is Some(cr) {
    let (binds, off) = binds_of(ws, cr, root_sub, in_force, logs, c)
    for sub, o in off {
      offs[sub] = o
    }
    let subs = cr.chain.members.keys().collect()
    subs.sort()
    for sub in subs {
      let m = cr.chain.members.get(sub).unwrap()
      guard sub != root_sub && is_role(Some(Json::string(m.role))) else { continue }
      // (one the chain bound to no log, bound to the log their own `bind` names: `binds_of`)
      let lock = match (cr.chain.persons.get(sub), binds.get(sub)) {
        (Some(l), _) => l
        (None, Some(g)) => g
        (None, None) => ""
      }
      let body : Map[String, Json] = Map([
        ("sub", Json::string(sub)), ("email", Json::string(m.email)), ("role", Json::string(m.role)),
        ("lock", Json::string(lock)),
      ])
      carried_ids["m/" + sub] = "~" + cr.moved + "/m/" + sub
      carried_stmts.push({ hash: "~" + cr.moved + "/m/" + sub, kind: "ws.member", body: Some(Json::object(body)), log: root, by: root_sub })
    }
    let keys = cr.chain.stations.keys().collect()
    keys.sort()
    for k in keys {
      carried_ids["s/" + k] = "~" + cr.moved + "/s/" + k
      carried_stmts.push({ hash: "~" + cr.moved + "/s/" + k, kind: "ws.station", body: Some(Json::object(Map([("key", Json::string(k))]))), log: root, by: root_sub })
    }
    by_body[cr.moved] = carried_stmts.map(fn(s) { s.hash })
  }
  // That the root's person is in the list, bound by the root's log, is an admit like any other (`~root`, the lead's,
  // 2026-11-14): of them, to the root, as owner, by the root's pair, in force, never lacking; a removal of them cancels
  // it only where its `cancels` names the root's genesis hash (never named or not, as the chain's: a removal of the
  // root's person said before this rule did nothing, and does nothing for every reader still).
  by_body[root] = [root_admit]
  let root_stmt : Stmt = {
    hash: root_admit,
    kind: "ws.member",
    body: Some(Json::object(Map([("sub", Json::string(root_sub)), ("lock", Json::string(root)), ("role", Json::string("owner"))]))),
    log: root,
    by: root_sub,
  }

  let stmts : Array[Stmt] = []
  for f in in_force {
    let (x, _, b, g) = f
    let kind = text_of(field(Some(b), "kind")).unwrap_or("")
    guard kind == "member" || kind == "member.remove" || kind == "station" || kind == "station.remove" else { continue }
    let body = match b {
      Object(m) => {
        let out : Map[String, Json] = Map([])
        for k, v in m {
          out[k] = v
        }
        if m.get("cancels") is Some(Array(cs)) {
          let named : Array[String] = []
          for y in cs {
            for z in by_body.get(text_of(Some(y)).unwrap_or("")).unwrap_or([]) {
              if !named.contains(z) {
                named.push(z)
              }
            }
          }
          // (D6: a removal takes back the chain's statement of its subject too, named or not: so one said before
          // the chain was read so, naming the admits of its time alone, still takes out whom it took out)
          let chains_own = match (kind, text_of(field(Some(b), "sub")), text_of(field(Some(b), "key"))) {
            ("member.remove", Some(sub), _) => carried_ids.get("m/" + sub)
            ("station.remove", _, Some(key)) => carried_ids.get("s/" + key)
            _ => None
          }
          if chains_own is Some(z) && !named.contains(z) {
            named.push(z)
          }
          out["cancels"] = Json::array(named.map(fn(x) { Json::string(x) }))
        }
        Json::object(out)
      }
      _ => b
    }
    stmts.push({ hash: x, kind: "ws." + kind, body: Some(body), log: g, by: logs.get(g).unwrap().0.sub })
  }
  stmts.append(carried_stmts)
  stmts.push(root_stmt)
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
  // Whom the list binds by which log: the root's person by the root while `~root` is in, before any other admit of
  // theirs; anyone else, and they once it is out, by the admit in force of the highest role, then one said in a log
  // before the chain's (`Carried`: `~<moved>/m/<sub>`), then the smallest hash. No admit of theirs in, not in the list.
  let before = fn(a : String, b : String) {
    match (a.has_prefix("~"), b.has_prefix("~")) {
      (false, true) => true
      (true, false) => false
      _ => a < b
    }
  }
  let root_in = label.get("a:" + root_admit) == Some("in")
  let best : Map[String, (String, String, String?)] = if root_in { Map([(root_sub, ("owner", root, None))]) } else { Map([]) }
  for a in admits {
    if label.get("a:" + a.hash) != Some("in") || a.hash == root_admit || (root_in && txt(a, "sub") == root_sub) {
      continue
    }
    let role = txt(a, "role")
    let takes = match best.get(txt(a, "sub")) {
      None => true
      Some((was, _, admit)) =>
        rank_of(role) > rank_of(was) ||
        (role == was &&
        (match admit {
          Some(x) => before(a.hash, x)
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
    // (the chain's are no statement of a log: told by `carried_keys` and the members they bind)
    if s.hash.has_prefix("~") {
      continue
    }
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
  let carried_keys : Array[(String, String)] = []
  if carried is Some(cr) {
    // (none of the root's person bound by a real admit: what the chain says of their devices is of the root's log)
    for m in members {
      guard !(m.sub == root_sub && m.admit is Some(_)) else { continue }
      for d in carry_of(cr, m.sub, m.lock, logs, 0.0, offs.get(m.sub).unwrap_or(Map([]))).apps {
        carried_keys.push((d.sign_key.unwrap_or(""), m.sub))
      }
    }
  }
  carried_keys.sort_by(fn(a, b) { a.compare(b) })
  let sts = stations.keys().collect()
  sts.sort()
  let ps = pairs.values().collect()
  ps.sort_by(fn(a, b) { a.compare(b) })
  let us = undecided.values().collect()
  us.sort_by(fn(a, b) { a.compare(b) })
  cancelled.sort()
  let ls = label.iter().collect()
  ls.sort_by(fn(a, b) { a.0.compare(b.0) })
  (
    {
      rooted: true, members, stations: sts, pairs: ps, undecided: us, cancelled, statements: said, labels: ls, refused,
      in_force: forced, lacking, newest, settings, carried_keys,
    },
    logs,
    offs,
  )
}

///|
/// What signs a binding (`bind`): its tag, which no other form a device's signer signs shares (a lock entry's
/// `stillfail-lock/1 sig`, a vault's `stillfail-vault*/1`, a rig's `stillfail-rig-*/1`).
pub let bind_tag : String = "stillfail-lock-bind/1"

///|
/// What a binding's signer signs, under `bind_tag`: the workspace, its member, the log they bind (its genesis's hash)
/// and the `moved` entry's hash of the chain whose signer proves it. So a proof is for one workspace, one person, one
/// log and one move: replayed for another of any of them it proves nothing.
pub fn bind_form(ws : String, sub : String, log : String, moved : String) -> Json {
  Json::object(Map([("kind", Json::string("bind")), ("log", Json::string(log)), ("moved", Json::string(moved)), ("sub", Json::string(sub)), ("ws", Json::string(ws))]))
}

///|
/// The SHA-256 (hex) of `bind_form`'s canonical text: what is signed after `bind_tag` and a NUL.
pub fn bind_digest(ws : String, sub : String, log : String, moved : String, c : &Crypto) -> String {
  let text = @form.canonical(bind_form(ws, sub, log, moved)) catch { _ => return "" }
  c.sha256_hex(text)
}

///|
/// A member's binding, a candidate (`binds_of`): its entry's hash, its log, its signer's key, the chain's own signing app
/// devices of the member's whose signer that key is (`dev`), and those of the chain's own app devices of the member's
/// that its log put on (its genesis's device, a `device`) and has not on now (`off`).
priv struct Bind {
  x : String
  g : String
  key : String
  dev : Map[String, Unit]
  off : Map[String, Unit]
}

///|
/// The bindings in force of members the chain as it moved bound to no log (the lead's, 2026-11-14: a carried member with
/// no log of their own does for themselves what they did before the move), by member, and the chain's devices of theirs
/// that their bindings took off. A candidate is a log's `bind` statement (its genesis's person the member) proved by the
/// signer the chain names for an own, signing app device of theirs, over `bind_form` of this workspace, that member,
/// that log and this move. It counts as the chain's own admit of them to that log (`~<moved>/m/<sub>`'s `lock`), so
/// whatever takes back the chain's saying of them (a removal of them, which cancels it named or not) takes it back too,
/// and a real admit of the same role binds before it as before the chain's; one where the chain bound them to a log, or
/// of the root's person, is nothing.
///
/// Between two of one member (the lead's review, 2026-11-14): one attacks another of another log where its log took off
/// a device that proves the other (its `off` meets the other's `dev`; never one of its own log, so a log that later
/// takes off the very device that proved it stays bound), and the grounded extension decides, as the list does for
/// removals: a candidate nothing attacks is in, one attacked by one in is out, again until nothing changes, a circle
/// left neither. The binding is the one in of the smaller signer key, then of the smaller entry hash: a key is one of
/// the few the chain names, an entry hash is ground at will by whoever makes the log. So a device the member took off
/// never binds them again: before the move a removal the stations took was final. Taken off: every device a candidate
/// not out took off, which the chain then carries no more (`state4.mbt` `carry_of`): where none is in (each took the
/// other's device off) the member stands bound to no log, without any of them, until an owner or admin admits them.
fn binds_of(ws : String, cr : Carried, root_sub : String, in_force : Array[(String, String, Json, String)], logs : Map[String, (Person, Array[Json])], c : &Crypto) -> (Map[String, String], Map[String, Map[String, Unit]]) {
  let cands : Map[String, Array[Bind]] = Map([])
  for f in in_force {
    let (x, _, b, g) = f
    guard text_of(field(Some(b), "kind")) == Some("bind") else { continue }
    guard logs.get(g) is Some((p, chain)) else { continue }
    let sub = p.sub
    guard sub != root_sub && cr.chain.members.contains(sub) && !cr.chain.persons.contains(sub) else { continue }
    guard text_of(field(Some(b), "key")) is Some(key) && text_of(field(Some(b), "sig")) is Some(sig) else { continue }
    let own : Map[String, Unit] = Map([])
    let dev : Map[String, Unit] = Map([])
    for _, d in cr.chain.devices {
      if d.sub == sub && d.kind == "app" && d.own && d.sign_key is Some(k) {
        own[d.id] = ()
        if k == key {
          dev[d.id] = ()
        }
      }
    }
    guard dev.length() > 0 && c.tagged_sig_valid(key, sig, bind_tag, bind_digest(ws, sub, g, cr.moved, c)) else { continue }
    let off : Map[String, Unit] = Map([])
    for e in chain {
      let id = match text_of(field(Some(e), "kind")) {
        Some("genesis") => text_of(field(Some(e), "body") |> field("device") |> field("id"))
        Some("device") => text_of(field(Some(e), "body") |> field("id"))
        _ => None
      }
      if id is Some(id) && own.contains(id) && !p.devices.values().any(fn(pd) { pd.id == id }) {
        off[id] = ()
      }
    }
    match cands.get(sub) {
      Some(cs) => cs.push({ x, g, key, dev, off })
      None => cands[sub] = [{ x, g, key, dev, off }]
    }
  }
  let binds : Map[String, String] = Map([])
  let offs : Map[String, Map[String, Unit]] = Map([])
  for sub, cs in cands {
    let n = cs.length()
    let attacks = fn(j : Int, i : Int) -> Bool {
      j != i && cs[j].g != cs[i].g && cs[j].off.keys().any(fn(id) { cs[i].dev.contains(id) })
    }
    // (0 neither, 1 in, 2 out)
    let label : Array[Int] = Array::make(n, 0)
    let mut changed = true
    while changed {
      changed = false
      for i in 0..<n {
        guard label[i] == 0 else { continue }
        let mut any_in = false
        let mut all_out = true
        for j in 0..<n {
          if attacks(j, i) {
            if label[j] == 1 {
              any_in = true
            }
            if label[j] != 2 {
              all_out = false
            }
          }
        }
        if any_in {
          label[i] = 2
          changed = true
        } else if all_out {
          label[i] = 1
          changed = true
        }
      }
    }
    let mut won : Bind? = None
    let off : Map[String, Unit] = Map([])
    for i in 0..<n {
      if label[i] == 1 {
        match won {
          Some(w) if w.key < cs[i].key || (w.key == cs[i].key && w.x <= cs[i].x) => ()
          _ => won = Some(cs[i])
        }
      }
      if label[i] != 2 {
        for id, _ in cs[i].off {
          off[id] = ()
        }
      }
    }
    if won is Some(w) {
      binds[sub] = w.g
    }
    offs[sub] = off
  }
  (binds, offs)
}
