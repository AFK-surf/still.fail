// The operations the station's use reader asks of this program, a line each (read with JavaScript's JSON rules, so a
// vault or owner with a lone surrogate arrives exactly): `ready` answers a read or a pending preparation if it can be
// answered now (no write); `prepare` takes one bounded step toward it; `rebox` and `uses` one background batch.

///|
fn field(q : @jsjson.JValue, name : String) -> @jsjson.JValue? {
  q.get(name)
}

///|
fn text_of(v : @jsjson.JValue?) -> Json {
  match v {
    Some(Str(s)) => Json::string(@jsjson.text(s))
    _ => Json::null()
  }
}

///|
fn units_of(v : @jsjson.JValue?) -> Array[Int]? {
  match v {
    Some(Str(s)) => Some(s)
    _ => None
  }
}

///|
fn bool_of(v : @jsjson.JValue?) -> Bool {
  v is Some(Bool(true))
}

///|
fn read_of(q : @jsjson.JValue) -> UseRead {
  {
    ws: text_of(field(q, "ws")),
    vault: units_of(field(q, "vault")).unwrap_or([]),
    owner: units_of(field(q, "owner")),
    limit: match field(q, "limit") {
      Some(Num(n)) => Json::number(n)
      _ => Json::number(0.0)
    },
  }
}

///|
fn id_of(q : @jsjson.JValue) -> Json {
  match field(q, "id") {
    Some(Num(n)) => Json::number(n)
    _ => Json::null()
  }
}

///|
fn pending(q : @jsjson.JValue) -> Bool {
  field(q, "kind") is Some(Str(_))
}

///|
/// One operation's answer.
pub fn operate(db : @sql.Db, line : String) -> Json raise {
  let ask = @jsjson.parse(line) catch { @jsjson.SyntaxError(m) => raise Failure("unreadable request: \{m}") }
  let op = match field(ask, "op") {
    Some(Str(s)) => @jsjson.text(s)
    _ => ""
  }
  let q = field(ask, "q").unwrap_or(Null)
  match op {
    "ready" => {
      let id = id_of(q)
      if pending(q) {
        let ws = text_of(field(q, "ws"))
        if pending_preparation_complete(db, ws, bool_of(field(q, "members")), bool_of(field(q, "audit"))) {
          { "answered": { "id": id, "ready": true } }
        } else {
          { "unready": true }
        }
      } else {
        match try_read_uses(db, read_of(q)) {
          Some(bodies) => { "answered": { "id": id, "bodies": Json::array(bodies) } }
          None => { "unready": true }
        }
      }
    }
    "prepare" =>
      if pending(q) {
        let ws = text_of(field(q, "ws"))
        { "complete": Json::boolean(backfill_pending_preparation(db, ws, bool_of(field(q, "members")), bool_of(field(q, "audit")))) }
      } else {
        let r = read_of(q)
        if backfill_use_preparation(db, r.ws) {
          match try_read_uses(db, r) {
            Some(bodies) => { "complete": true, "bodies": Json::array(bodies) }
            None => { "complete": false }
          }
        } else {
          { "complete": false }
        }
      }
    "rebox" => { "done": Json::boolean(backfill_rebox(db)) }
    "uses" => { "done": Json::boolean(backfill_next_workspace(db)) }
    _ => raise Failure("unknown vault use operation \{op}")
  }
}
