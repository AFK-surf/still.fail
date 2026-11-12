// The station's database through the shell (client/shell `sql.*`, answered at once on this thread): a connection of
// this program's own to the file the station keeps, statements run, their rows by their columns' names.

///|
pub struct Db {
  priv host : @host.Host
  priv id : Json
}

///|
/// The database at `path`, another process's too (the station's), waited for `wait` ms when it is busy.
pub fn Db::attach(host : @host.Host, path : String, wait~ : Int) -> Db raise @wire.ShellError {
  let opened = host.shell_sync("sql.attach", { "path": Json::string(path), "wait": Json::number(wait.to_double()) })
  guard opened is { "id": id, .. } else { raise @wire.ShellError("the shell gave no database") }
  { host, id }
}

///|
/// A database of this program's own at `path` (made where it is not, `:memory:` one in memory), waited for `wait` ms
/// when it is busy.
pub fn Db::create(host : @host.Host, path : String, wait~ : Int) -> Db raise @wire.ShellError {
  let opened = host.shell_sync("sql.attach", {
    "path": Json::string(path),
    "wait": Json::number(wait.to_double()),
    "create": true,
  })
  guard opened is { "id": id, .. } else { raise @wire.ShellError("the shell gave no database") }
  { host, id }
}

///|
/// The connection let go.
pub fn Db::close(self : Db) -> Unit {
  ignore(self.host.shell_sync("sql.close", { "id": self.id })) catch {
    _ => ()
  }
}

///|
/// Statements with no rows (BEGIN, COMMIT, PRAGMA …).
pub fn Db::exec(self : Db, sql : String) -> Unit raise @wire.ShellError {
  ignore(self.host.shell_sync("sql.exec", { "id": self.id, "sql": Json::string(sql) }))
}

///|
/// A statement with `params`; how many rows it changed.
pub fn Db::run(self : Db, sql : String, params : Array[Json]) -> Int raise @wire.ShellError {
  match self.host.shell_sync("sql.run", { "id": self.id, "sql": Json::string(sql), "params": Json::array(params) }) {
    Number(n, ..) => n.to_int()
    _ => 0
  }
}

///|
/// A statement's rows, each by its columns' names.
pub fn Db::all(self : Db, sql : String, params : Array[Json]) -> Array[Map[String, Json]] raise @wire.ShellError {
  let got = self.host.shell_sync("sql.all", {
    "id": self.id,
    "sql": Json::string(sql),
    "params": Json::array(params),
    "named": true,
  })
  guard got is { "columns": Array(columns), "rows": Array(rows), .. } else {
    raise @wire.ShellError("the shell gave no rows")
  }
  let names = columns.map(c => match c {
    String(s) => s
    _ => ""
  })
  rows.map(r => {
    let row : Map[String, Json] = Map([])
    if r is Array(values) {
      for i, name in names {
        row[name] = values[i]
      }
    }
    row
  })
}

///|
/// The database was busy or locked (SQLITE_BUSY, SQLITE_LOCKED): another's write holds it, nothing went wrong.
pub fn busy(e : Error) -> Bool {
  match e {
    @wire.ShellError(m) => m.contains("database is locked") || m.contains("is locked")
    _ => false
  }
}
