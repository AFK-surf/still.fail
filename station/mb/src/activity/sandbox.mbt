// The reverse lookup of sandbox names (station/src/store/sandbox-index.ts): a sandbox's name is a hash of its
// session's key (agents/sandbox-name.ts), so it is computed here, for an older store's sessions and the keys writers
// changed, in bounded batches, as `enableSandboxIndex`, `disableSandboxIndex` and `sandboxIndexStep` do.

///|
let sandbox_version : Int = 1

///|
let k_table : FixedArray[UInt] = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01,
  0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08,
  0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]

///|
fn rotr(x : UInt, n : Int) -> UInt {
  (x >> n) | (x << (32 - n))
}

///|
/// SHA-256 of `data`, as lowercase hex.
pub fn sha256_hex(data : Array[Int]) -> String {
  let h : FixedArray[UInt] = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ]
  let bytes = data.copy()
  let bits = data.length().to_uint64() * 8
  bytes.push(0x80)
  while bytes.length() % 64 != 56 {
    bytes.push(0)
  }
  for i = 7; i >= 0; i = i - 1 {
    bytes.push(((bits >> (i * 8)) & 0xff).to_int())
  }
  let w : FixedArray[UInt] = FixedArray::make(64, 0)
  for chunk = 0; chunk < bytes.length(); chunk = chunk + 64 {
    for i in 0..<16 {
      let b = (j : Int) => bytes[chunk + i * 4 + j].reinterpret_as_uint()
      w[i] = (b(0) << 24) | (b(1) << 16) | (b(2) << 8) | b(3)
    }
    for i in 16..<64 {
      let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
      let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
      w[i] = w[i - 16] + s0 + w[i - 7] + s1
    }
    let mut a = h[0]
    let mut b = h[1]
    let mut c = h[2]
    let mut d = h[3]
    let mut e = h[4]
    let mut f = h[5]
    let mut g = h[6]
    let mut hh = h[7]
    for i in 0..<64 {
      let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
      let ch = (e & f) ^ (e.lnot() & g)
      let t1 = hh + s1 + ch + k_table[i] + w[i]
      let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
      let maj = (a & b) ^ (a & c) ^ (b & c)
      let t2 = s0 + maj
      hh = g
      g = f
      f = e
      e = d + t1
      d = c
      c = b
      b = a
      a = t1 + t2
    }
    h[0] = h[0] + a
    h[1] = h[1] + b
    h[2] = h[2] + c
    h[3] = h[3] + d
    h[4] = h[4] + e
    h[5] = h[5] + f
    h[6] = h[6] + g
    h[7] = h[7] + hh
  }
  let hex = "0123456789abcdef"
  let out = StringBuilder::new()
  for word in h {
    for shift = 28; shift >= 0; shift = shift - 4 {
      out.write_char(hex.unsafe_charcode_at(((word >> shift) & 0xf).reinterpret_as_int()).unsafe_to_char())
    }
  }
  out.to_string()
}

///|
/// A string's UTF-8 bytes as JavaScript encodes it for a hash (a lone surrogate as U+FFFD).
pub fn utf8(s : String) -> Array[Int] {
  let out = []
  let n = s.length()
  let mut i = 0
  while i < n {
    let mut c = s.unsafe_charcode_at(i)
    i += 1
    if c >= 0xd800 && c <= 0xdbff && i < n && s.unsafe_charcode_at(i) >= 0xdc00 && s.unsafe_charcode_at(i) <= 0xdfff {
      c = 0x10000 + ((c - 0xd800) << 10) + (s.unsafe_charcode_at(i) - 0xdc00)
      i += 1
    } else if c >= 0xd800 && c <= 0xdfff {
      c = 0xfffd
    }
    if c < 0x80 {
      out.push(c)
    } else if c < 0x800 {
      out.push(0xc0 | (c >> 6))
      out.push(0x80 | (c & 0x3f))
    } else if c < 0x10000 {
      out.push(0xe0 | (c >> 12))
      out.push(0x80 | ((c >> 6) & 0x3f))
      out.push(0x80 | (c & 0x3f))
    } else {
      out.push(0xf0 | (c >> 18))
      out.push(0x80 | ((c >> 12) & 0x3f))
      out.push(0x80 | ((c >> 6) & 0x3f))
      out.push(0x80 | (c & 0x3f))
    }
  }
  out
}

///|
fn hash10(s : String) -> String {
  sha256_hex(utf8(s)).view(end_offset=10).to_string()
}

///|
/// A key as a runner's id has it (`keyPart`): each UTF-16 unit not a letter, digit, `_` or `-` as `_`, 24 at most,
/// a hash when that changed it.
pub fn key_part(key : String) -> String {
  let clean = StringBuilder::new()
  let n = if key.length() < 24 { key.length() } else { 24 }
  for i in 0..<n {
    let c = key.unsafe_charcode_at(i)
    let ok = (c >= 'A'.to_int() && c <= 'Z'.to_int()) ||
      (c >= 'a'.to_int() && c <= 'z'.to_int()) ||
      (c >= '0'.to_int() && c <= '9'.to_int()) ||
      c == '_'.to_int() ||
      c == '-'.to_int()
    clean.write_char(if ok { c.unsafe_to_char() } else { '_' })
  }
  let cleaned = clean.to_string()
  if cleaned == key {
    cleaned
  } else {
    "\{cleaned}-\{hash10(key)}"
  }
}

///|
/// A sandbox's name for a key (`sandboxName`): the key lowercased as JavaScript does where that gives letters (ASCII,
/// the Kelvin sign, İ), its runs of other characters as `-`, trimmed, 16 at most; then a hash.
pub fn sandbox_name(key : String) -> String {
  let lower = StringBuilder::new()
  for c in key {
    let code = c.to_int()
    if code >= 'A'.to_int() && code <= 'Z'.to_int() {
      lower.write_char((code + 32).unsafe_to_char())
    } else if code == 0x212a {
      lower.write_char('k')
    } else if code == 0x130 {
      lower.write_char('i')
      lower.write_char('\u{307}')
    } else {
      lower.write_char(c)
    }
  }
  let dashed = StringBuilder::new()
  let mut run = false
  for c in lower.to_string() {
    if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') {
      dashed.write_char(c)
      run = false
    } else if !run {
      dashed.write_char('-')
      run = true
    }
  }
  let mut clean = dashed.to_string()
  // (trimmed of dashes, 16 at most, then of trailing dashes again)
  let mut start = 0
  while start < clean.length() && clean.unsafe_charcode_at(start) == '-'.to_int() {
    start += 1
  }
  let mut end = clean.length()
  while end > start && clean.unsafe_charcode_at(end - 1) == '-'.to_int() {
    end -= 1
  }
  clean = clean.view(start_offset=start, end_offset=end).to_string()
  if clean.length() > 16 {
    clean = clean.view(end_offset=16).to_string()
  }
  let mut cut = clean.length()
  while cut > 0 && clean.unsafe_charcode_at(cut - 1) == '-'.to_int() {
    cut -= 1
  }
  clean = clean.view(end_offset=cut).to_string()
  let hash = hash10(key)
  if clean == "" {
    "s-\{hash}"
  } else {
    "s-\{clean}-\{hash}"
  }
}

///|
fn sandbox_dirty(key : String) -> String {
  "INSERT INTO sandbox_name_dirty (session) SELECT \{key} WHERE \{key} IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sandbox_name_dirty d WHERE d.session = \{key});"
}

///|
let sandbox_conflicts : String = "INSERT INTO sandbox_name_dirty (session) SELECT s.key FROM sessions s WHERE (s.token = NEW.token OR s.rowid = NEW.rowid) AND s.key IS NOT NEW.key AND NOT EXISTS (SELECT 1 FROM sandbox_name_dirty d WHERE d.session = s.key);"

///|
let enabled_check : String = "(SELECT enabled FROM sandbox_name_meta WHERE id = 1) = 1"

///|
pub fn sandbox_schema() -> String {
  [
    "CREATE TABLE sandbox_name_meta (id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL, enabled INTEGER NOT NULL, phase INTEGER NOT NULL, cursor TEXT, prune INTEGER NOT NULL, end_session TEXT, end_prune TEXT) WITHOUT ROWID;",
    "INSERT INTO sandbox_name_meta (id, version, enabled, phase, cursor, prune, end_session, end_prune) VALUES (1, \{sandbox_version}, 1, 0, NULL, 0, (SELECT key FROM sessions WHERE key IS NOT NULL ORDER BY key DESC LIMIT 1), NULL);",
    "CREATE TABLE sandbox_name_rows (session TEXT PRIMARY KEY, name TEXT NOT NULL) WITHOUT ROWID;",
    "CREATE INDEX sandbox_name_lookup ON sandbox_name_rows (name);",
    "CREATE TABLE sandbox_name_dirty (session TEXT PRIMARY KEY) WITHOUT ROWID;",
    "CREATE TRIGGER sandbox_name_before_add BEFORE INSERT ON sessions WHEN \{enabled_check} BEGIN \{sandbox_dirty("NEW.key")} \{sandbox_conflicts} END;",
    "CREATE TRIGGER sandbox_name_before_change BEFORE UPDATE ON sessions WHEN (OLD.rowid IS NOT NEW.rowid OR OLD.key IS NOT NEW.key OR OLD.token IS NOT NEW.token) AND \{enabled_check} BEGIN \{sandbox_dirty("OLD.key")} \{sandbox_dirty("NEW.key")} \{sandbox_conflicts} END;",
    "CREATE TRIGGER sandbox_name_before_drop BEFORE DELETE ON sessions WHEN \{enabled_check} BEGIN \{sandbox_dirty("OLD.key")} END;",
  ].join("\n")
}

///|
fn sandbox_meta(db : @sql.Db) -> Int? raise {
  if first(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'sandbox_name_meta'", []) is None {
    return None
  }
  let m = first(db, "SELECT version, enabled FROM sandbox_name_meta WHERE id = 1", [])
  let v = match m {
    Some(r) => get(r, "version")
    None => Json::null()
  }
  guard v is Number(n, ..) && n.to_int() == sandbox_version && m is Some(r) else {
    let said = if v is Null { "missing" } else { v.stringify() }
    raise Failure("sandbox name index version \{said} is incompatible with \{sandbox_version}")
  }
  match get(r, "enabled") {
    Number(e, ..) => Some(e.to_int())
    _ => Some(0)
  }
}

///|
/// The lookup made, or switched on again with every key checked anew (`enableSandboxIndex`).
pub fn sandbox_enable(db : @sql.Db) -> Unit raise {
  if sandbox_meta(db) == Some(1) {
    return
  }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  match sandbox_meta(db) {
    None => db.exec(sandbox_schema())
    Some(0) =>
      db.exec(
        "UPDATE sandbox_name_meta SET enabled = 1, phase = 0, cursor = NULL, prune = 1, end_session = (SELECT key FROM sessions WHERE key IS NOT NULL ORDER BY key DESC LIMIT 1), end_prune = (SELECT session FROM sandbox_name_rows ORDER BY session DESC LIMIT 1) WHERE id = 1",
      )
    _ => ()
  }
  db.exec("COMMIT")
}

///|
/// Journaling stopped while sandboxes are off (`disableSandboxIndex`).
pub fn sandbox_disable(db : @sql.Db) -> Unit raise {
  if sandbox_meta(db) == Some(1) {
    db.exec("UPDATE sandbox_name_meta SET enabled = 0 WHERE id = 1")
  }
}

///|
/// At most `limit` keys named, pruned or journaled keys settled (`sandboxIndexStep`): the old sessions by key, then
/// (switched on again) the old rows of keys gone, then the journal. Whether nothing is left then.
pub fn sandbox_step(db : @sql.Db, limit? : Int = 64) -> Bool raise {
  guard limit >= 1 else { raise Failure("sandbox name batch must be positive") }
  db.exec("BEGIN IMMEDIATE")
  errdefer (db.exec("ROLLBACK") catch { _ => () })
  guard first(db, "SELECT version, enabled, phase, cursor, prune, end_session, end_prune FROM sandbox_name_meta WHERE id = 1", [])
    is Some(meta) &&
    get(meta, "version") is Number(v, ..) &&
    v.to_int() == sandbox_version else {
    raise Failure("sandbox name index version is incompatible with \{sandbox_version}")
  }
  if !(get(meta, "enabled") is Number(1.0, ..)) {
    db.exec("COMMIT")
    return true
  }
  let save = (session : Json) => match session {
    String(key) =>
      ignore(
        db.run(
          "INSERT INTO sandbox_name_rows (session, name) VALUES (?, ?) ON CONFLICT(session) DO UPDATE SET name = excluded.name WHERE name IS NOT excluded.name",
          [session, Json::string(sandbox_name(key_part(key)))],
        ),
      )
    _ => ()
  }
  let present = (session : Json) => first(db, "SELECT 1 FROM sessions WHERE key = ?", [session]) is Some(_)
  let prune = get(meta, "prune") is Number(1.0, ..)
  let end_session = get(meta, "end_session")
  let end_prune = get(meta, "end_prune")
  let mut phase = match get(meta, "phase") {
    Number(p, ..) => p.to_int()
    _ => 0
  }
  let mut cursor = get(meta, "cursor")
  let mut visited = 0
  while visited < limit {
    let lim = Json::number((limit - visited).to_double())
    if phase == 0 {
      let rows = if end_session is Null {
        []
      } else if cursor is Null {
        db.all("SELECT key AS session FROM sessions WHERE key <= ? ORDER BY key LIMIT ?", [end_session, lim])
      } else {
        db.all("SELECT key AS session FROM sessions WHERE key > ? AND key <= ? ORDER BY key LIMIT ?", [cursor, end_session, lim])
      }
      if rows.length() == 0 {
        phase = if prune { 1 } else { 2 }
        cursor = Json::null()
        continue
      }
      for row in rows {
        let session = get(row, "session")
        save(session)
        ignore(db.run("DELETE FROM sandbox_name_dirty WHERE session = ?", [session]))
        cursor = session
        visited += 1
      }
    } else if phase == 1 {
      let rows = if end_prune is Null {
        []
      } else if cursor is Null {
        db.all("SELECT session FROM sandbox_name_rows WHERE session <= ? ORDER BY session LIMIT ?", [end_prune, lim])
      } else {
        db.all("SELECT session FROM sandbox_name_rows WHERE session > ? AND session <= ? ORDER BY session LIMIT ?", [cursor, end_prune, lim])
      }
      if rows.length() == 0 {
        phase = 2
        cursor = Json::null()
        continue
      }
      for row in rows {
        let session = get(row, "session")
        if !present(session) {
          ignore(db.run("DELETE FROM sandbox_name_rows WHERE session = ?", [session]))
        }
        cursor = session
        visited += 1
      }
    } else {
      let rows = db.all("SELECT session FROM sandbox_name_dirty ORDER BY session LIMIT ?", [lim])
      if rows.length() == 0 {
        break
      }
      for row in rows {
        let session = get(row, "session")
        if !present(session) {
          ignore(db.run("DELETE FROM sandbox_name_rows WHERE session = ?", [session]))
        } else {
          save(session)
        }
        ignore(db.run("DELETE FROM sandbox_name_dirty WHERE session = ?", [session]))
        visited += 1
      }
    }
  }
  ignore(db.run("UPDATE sandbox_name_meta SET phase = ?, cursor = ? WHERE id = 1", [Json::number(phase.to_double()), cursor]))
  let done = phase == 2 && first(db, "SELECT 1 FROM sandbox_name_dirty LIMIT 1", []) is None
  db.exec("COMMIT")
  done
}
