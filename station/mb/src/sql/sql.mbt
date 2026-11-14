// The station's database as this program's own connection to the file the station keeps: SQLite's C API asked directly
// (sql.c: the SQLite client/shell links), statements kept prepared by their text, their rows by their columns' names.
// What it gives is what the shell's `sql.*` gave through JSON (rusqlite's values, serde's JSON, read back here): the
// same values, errors and refusals, without the JSON between, which took more of a read's time than SQLite did
// (2026-11-14: of the shared chat list on a station of 2342 chats, 59% of its 72 ms).

///|
#borrow(path)
extern "C" fn open_ffi(path : Bytes, flags : Int, wait : Int) -> Int64 = "sfq_open"

///|
extern "C" fn errstr_ffi(rc : Int) -> Bytes = "sfq_errstr"

///|
extern "C" fn errmsg_ffi(db : Int64) -> Bytes = "sfq_errmsg"

///|
extern "C" fn close_ffi(db : Int64) = "sfq_close"

///|
extern "C" fn changes_ffi(db : Int64) -> Int = "sfq_changes"

///|
extern "C" fn autocommit_ffi(db : Int64) -> Int = "sfq_autocommit"

///|
extern "C" fn readonly_ffi(s : Int64) -> Int = "sfq_readonly"

///|
#borrow(sql)
extern "C" fn exec_ffi(db : Int64, sql : Bytes) -> Int = "sfq_exec"

///|
#borrow(sql)
extern "C" fn prepare_ffi(db : Int64, sql : Bytes, n : Int) -> Int64 = "sfq_prepare"

///|
extern "C" fn finalize_ffi(s : Int64) = "sfq_finalize"

///|
extern "C" fn reset_ffi(s : Int64) = "sfq_reset"

///|
extern "C" fn params_ffi(s : Int64) -> Int = "sfq_params"

///|
extern "C" fn bind_null_ffi(s : Int64, i : Int) -> Int = "sfq_bind_null"

///|
extern "C" fn bind_int_ffi(s : Int64, i : Int, v : Int64) -> Int = "sfq_bind_int"

///|
extern "C" fn bind_double_ffi(s : Int64, i : Int, v : Double) -> Int = "sfq_bind_double"

///|
#borrow(v)
extern "C" fn bind_text_ffi(s : Int64, i : Int, v : Bytes) -> Int = "sfq_bind_text"

///|
#borrow(v)
extern "C" fn bind_blob_ffi(s : Int64, i : Int, v : Bytes) -> Int = "sfq_bind_blob"

///|
extern "C" fn step_ffi(s : Int64) -> Int = "sfq_step"

///|
extern "C" fn columns_ffi(s : Int64) -> Int = "sfq_columns"

///|
extern "C" fn column_name_ffi(s : Int64, i : Int) -> Bytes = "sfq_column_name"

///|
extern "C" fn type_ffi(s : Int64, i : Int) -> Int = "sfq_type"

///|
extern "C" fn int_ffi(s : Int64, i : Int) -> Int64 = "sfq_int"

///|
extern "C" fn double_ffi(s : Int64, i : Int) -> Double = "sfq_double"

///|
extern "C" fn text_ffi(s : Int64, i : Int) -> Bytes = "sfq_text"

///|
extern "C" fn blob_ffi(s : Int64, i : Int) -> Bytes = "sfq_blob"

///|
/// SQLite's result codes and open flags this needs.
const SQLITE_ROW : Int = 100

///|
const SQLITE_DONE : Int = 101

///|
const OPEN_READ_WRITE : Int = 0x2

///|
const OPEN_CREATE : Int = 0x4

///|
const OPEN_URI : Int = 0x40

///|
const OPEN_NO_MUTEX : Int = 0x8000

///|
/// At most this many statements kept prepared (rusqlite's cache the shell kept: 256); past it, all let go.
const KEPT_MOST : Int = 256

///|
/// A statement kept prepared: its handle, its columns' names and whether it writes nothing.
priv struct Kept {
  handle : Int64
  names : Array[String]
  reads_only : Bool
}

///|
pub struct Db {
  priv handle : Int64
  priv kept : Map[String, Kept]
  /// Counts what may have changed what this connection sees: each statement that may write (exec's, BEGIN and COMMIT
  /// too; run's; a query's that is not read-only).
  priv mut changed : Int
  /// What `known` found, each with `changed` as it was when it was found.
  priv found : Map[String, (Int, Json)]
}

///|
fn cstr(s : String) -> Bytes {
  let b = @utf8.encode(s)
  let out = FixedArray::make(b.length() + 1, b'\x00')
  for i = 0; i < b.length(); i = i + 1 {
    out[i] = b[i]
  }
  Bytes::from_array(out)
}

///|
fn open(path : String, flags : Int, wait : Int) -> Db raise @wire.ShellError {
  let handle = open_ffi(cstr(path), flags | OPEN_READ_WRITE | OPEN_NO_MUTEX | OPEN_URI, wait)
  if handle <= 0L {
    raise @wire.ShellError(@utf8.decode_lossy(errstr_ffi((-handle).to_int())))
  }
  let db = { handle, kept: Map([]), changed: 0, found: Map([]) }
  db.exec("PRAGMA synchronous = NORMAL;")
  db
}

///|
/// The database at `path`, another process's too (the station's), waited for `wait` ms when it is busy.
pub fn Db::attach(host : @host.Host, path : String, wait~ : Int) -> Db raise @wire.ShellError {
  ignore(host)
  open(path, 0, wait)
}

///|
/// A database of this program's own at `path` (made where it is not, `:memory:` one in memory), waited for `wait` ms
/// when it is busy.
pub fn Db::create(host : @host.Host, path : String, wait~ : Int) -> Db raise @wire.ShellError {
  ignore(host)
  open(path, OPEN_CREATE, wait)
}

///|
/// The connection let go.
pub fn Db::close(self : Db) -> Unit {
  for _, k in self.kept {
    finalize_ffi(k.handle)
  }
  self.kept.clear()
  close_ffi(self.handle)
}

///|
fn Db::failed(self : Db) -> @wire.ShellError {
  @wire.ShellError(@utf8.decode_lossy(errmsg_ffi(self.handle)))
}

///|
/// Statements with no rows (BEGIN, COMMIT, PRAGMA …).
pub fn Db::exec(self : Db, sql : String) -> Unit raise @wire.ShellError {
  self.changed += 1
  if exec_ffi(self.handle, cstr(sql)) != 0 {
    raise self.failed()
  }
}

///|
/// `sql` prepared, kept by its text, its parameters bound to `params` as the shell bound them (serde's JSON as
/// rusqlite's values).
fn Db::prepared(self : Db, sql : String, params : Array[Json]) -> Kept raise @wire.ShellError {
  let kept = match self.kept.get(sql) {
    Some(k) => k
    None => {
      let text = @utf8.encode(sql)
      let handle = prepare_ffi(self.handle, text, text.length())
      if handle == 0L {
        raise self.failed()
      }
      let names = Array::makei(columns_ffi(handle), i => @utf8.decode_lossy(column_name_ffi(handle, i)))
      if self.kept.length() >= KEPT_MOST {
        for _, k in self.kept {
          finalize_ffi(k.handle)
        }
        self.kept.clear()
      }
      let k = { handle, names, reads_only: readonly_ffi(handle) != 0 }
      self.kept[sql] = k
      k
    }
  }
  let needed = params_ffi(kept.handle)
  if needed != params.length() {
    raise @wire.ShellError(
      "Wrong number of parameters passed to query. Got \{params.length()}, needed \{needed}",
    )
  }
  for i, p in params {
    let at = i + 1
    let rc = match p {
      Null => bind_null_ffi(kept.handle, at)
      True => bind_int_ffi(kept.handle, at, 1L)
      False => bind_int_ffi(kept.handle, at, 0L)
      Number(n, repr~) => bind_number(kept.handle, at, n, repr)
      String(s) => bind_text_ffi(kept.handle, at, @utf8.encode(s))
      Array(bytes) =>
        bind_blob_ffi(
          kept.handle,
          at,
          Bytes::from_array(
            FixedArray::makei(bytes.length(), j => match bytes[j] {
              Number(b, ..) if b >= 0.0 && b == b.floor() => b.to_int64().to_byte()
              _ => b'\x00'
            }),
          ),
        )
      Object(_) => bind_text_ffi(kept.handle, at, @utf8.encode(p.stringify()))
    }
    if rc != 0 {
      reset_ffi(kept.handle)
      raise self.failed()
    }
  }
  kept
}

///|
/// A number as serde read its JSON: an integer where its text is one i64 holds, else a real (serde's `as_i64`, then
/// `as_f64`); one that is no number JSON says (NaN, ±∞, which MoonBit writes as null) null.
fn bind_number(handle : Int64, at : Int, n : Double, repr : String?) -> Int {
  match repr {
    Some(text) =>
      match (try Some(@string.parse_int64(text)) catch { _ => None }) {
        Some(v) => bind_int_ffi(handle, at, v)
        None => bind_double_ffi(handle, at, n)
      }
    None =>
      if n.is_nan() || n.is_inf() {
        bind_null_ffi(handle, at)
      } else if n == n.floor() && n >= -9223372036854775808.0 && n < 9223372036854775808.0 {
        bind_int_ffi(handle, at, n.to_int64())
      } else {
        bind_double_ffi(handle, at, n)
      }
  }
}

///|
/// A statement with `params`; how many rows it changed.
pub fn Db::run(self : Db, sql : String, params : Array[Json]) -> Int raise @wire.ShellError {
  self.changed += 1
  let kept = self.prepared(sql, params)
  let rc = step_ffi(kept.handle)
  reset_ffi(kept.handle)
  if rc == SQLITE_ROW {
    raise @wire.ShellError("Execute returned results - did you mean to call query?")
  }
  if rc != SQLITE_DONE {
    raise self.failed()
  }
  changes_ffi(self.handle)
}

///|
/// The largest integer a double holds exactly (JSON's parse here keeps the digits of one past it).
const SAFE_MOST : Int64 = 9007199254740991L

///|
/// A column's value as the shell's JSON of it read back: an integer a number (with its digits where a double does not
/// hold it), a real a number (null where it is no finite one), text a string (its bytes not UTF-8 as from_utf8_lossy
/// put them), a blob its bytes.
fn value(handle : Int64, i : Int) -> Json {
  match type_ffi(handle, i) {
    1 => {
      let v = int_ffi(handle, i)
      if v > SAFE_MOST || v < -SAFE_MOST {
        Json::number(v.to_double(), repr=v.to_string())
      } else {
        Json::number(v.to_double())
      }
    }
    2 => {
      let d = double_ffi(handle, i)
      if d.is_nan() || d.is_inf() {
        Json::null()
      } else {
        Json::number(d)
      }
    }
    3 => Json::string(@utf8.decode_lossy(text_ffi(handle, i)))
    4 => {
      let b = blob_ffi(handle, i)
      Json::array(Array::makei(b.length(), j => Json::number(b[j].to_int().to_double())))
    }
    _ => Json::null()
  }
}

///|
/// A statement's rows, each by its columns' names.
pub fn Db::all(self : Db, sql : String, params : Array[Json]) -> Array[Map[String, Json]] raise @wire.ShellError {
  let kept = self.prepared(sql, params)
  if !kept.reads_only {
    self.changed += 1
  }
  let rows = []
  while true {
    let rc = step_ffi(kept.handle)
    if rc == SQLITE_ROW {
      let row : Map[String, Json] = Map([])
      for i, name in kept.names {
        row[name] = value(kept.handle, i)
      }
      rows.push(row)
    } else if rc == SQLITE_DONE {
      break
    } else {
      let e = self.failed()
      reset_ffi(kept.handle)
      raise e
    }
  }
  reset_ffi(kept.handle)
  rows
}

///|
/// What `find` says of the database (a fact of its schema, a row of its state), found once in a transaction for as long
/// as this connection writes nothing: its snapshot holds still till then. Outside a transaction (each statement a
/// snapshot of its own) it is found every time. `key` names what `find` finds.
pub fn Db::known(self : Db, key : String, find : () -> Json raise) -> Json raise {
  if autocommit_ffi(self.handle) != 0 {
    return find()
  }
  if self.found.get(key) is Some((at, v)) && at == self.changed {
    return v
  }
  let at = self.changed
  let v = find()
  if at == self.changed {
    self.found[key] = (at, v)
  }
  v
}

///|
/// The database was busy or locked (SQLITE_BUSY, SQLITE_LOCKED): another's write holds it, nothing went wrong.
pub fn busy(e : Error) -> Bool {
  match e {
    @wire.ShellError(m) => m.contains("database is locked") || m.contains("is locked")
    _ => false
  }
}
