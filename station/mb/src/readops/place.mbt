// A file or directory a session's message names by its path, for its preview (station/src/read/sessions.ts
// `sessionPlace`, GET /sessions/:key/peek and /open): absolute (`~/` the home), under the session's working directory,
// or a file of a repository there whose path ends with it (as `git ls-files` lists them); only within the session's
// own directories, the station's repositories and the agents' home, its links followed first. On macOS nothing in a
// folder macOS protects is looked at (station/src/ops/places.ts `realOutside`, station/src/drive/fs.ts
// `protectedPlace`). What only the station's process knows comes with the read (`env`: its HOME, its home directory,
// whether macOS's folder permissions apply), and its words (`words`), and the time (`now`), which this clock is not.

///|
/// sessions.ts `listed`: the files git has of each repository, by its directory, as last listed (kept a minute).
let listed : Map[String, (Double, Array[String])] = Map([])

///|
/// unix.ts `mounted`: macOS's mounts as last read, and when (read again once two seconds old).
let mounted : Ref[(Double, Array[String])?] = { val: None }

///|
priv struct Env {
  host : @host.Host
  sep : String
  home : String
  homedir : String
  mac : Bool
  now : Double
}

///|
fn Env::win(self : Env) -> Bool {
  self.sep == "\\"
}

///|
fn is_separator(env : Env, c : Int) -> Bool {
  c == '/' || (env.win() && c == '\\')
}

///|
/// path.isAbsolute.
fn is_absolute(env : Env, p : String) -> Bool {
  if p.length() > 0 && is_separator(env, p.unsafe_charcode_at(0)) {
    return true
  }
  env.win() && p.length() >= 3 && p.unsafe_charcode_at(1) == ':' && is_separator(env, p.unsafe_charcode_at(2))
}

///|
/// platform.paths.clean: absolute, `.` and `..` worked out lexically (Windows' as win32.resolve does an absolute one).
fn clean_path(env : Env, path : String) -> String {
  if !env.win() {
    let out = []
    for part in path.split("/") {
      let part = part.to_owned()
      if part == "" || part == "." {
        continue
      }
      if part == ".." {
        ignore(out.pop())
      } else {
        out.push(part)
      }
    }
    return "/" + out.join("/")
  }
  let n = @nodepath.join(env.sep, [if path == "" { "\\" } else { path }])
  // (win32.resolve keeps no separator at the end but a root's)
  if n.length() > 3 && n.has_suffix("\\") { n.view(end_offset=n.length() - 1).to_owned() } else { n }
}

///|
/// ops/paths.ts `cleanPosix`: absolute, `.` and `..` worked out, `/` between the parts (and `\` where it separates).
fn clean_posix(env : Env, path : String) -> String {
  let out = []
  let mut start = 0
  for i = 0; i <= path.length(); i = i + 1 {
    if i < path.length() && !is_separator(env, path.unsafe_charcode_at(i)) {
      continue
    }
    let part = path.view(start_offset=start, end_offset=i).to_owned()
    start = i + 1
    if part == "" || part == "." {
      continue
    }
    if part == ".." {
      ignore(out.pop())
    } else {
      out.push(part)
    }
  }
  "/" + out.join("/")
}

///|
/// platform.paths.within: `path` is `dir` or under it.
fn within_dir(env : Env, path : String, dir : String) -> Bool {
  if !env.win() {
    return dir == "/" || path == dir || path.has_prefix(dir + "/")
  }
  let p = @jscase.lower(path)
  let d = @jscase.lower(dir)
  p == d || p.has_prefix(if d.has_suffix("\\") || d.has_suffix("/") { d } else { d + "\\" })
}

///|
/// path.basename.
fn place_name(env : Env, path : String) -> String {
  let mut end = path.length()
  while end > 0 && is_separator(env, path.unsafe_charcode_at(end - 1)) {
    end -= 1
  }
  let mut start = end
  while start > 0 && !is_separator(env, path.unsafe_charcode_at(start - 1)) {
    start -= 1
  }
  if env.win() && start == 0 && end >= 2 && path.unsafe_charcode_at(1) == ':' {
    start = 2
  }
  path.view(start_offset=start, end_offset=end).to_owned()
}

///|
/// realpathSync: None when a part is not there.
fn real_path(env : Env, path : String) -> String? {
  match (try { Ok(env.host.shell_sync("fs.realpath", { "path": Json::string(path) })) } catch { e => Err(e) }) {
    Ok(String(p)) => Some(p)
    _ => None
  }
}

///|
fn meta_of(env : Env, path : String) -> Json? {
  match (try { Ok(env.host.shell_sync("fs.meta", { "path": Json::string(path) })) } catch { e => Err(e) }) {
    Ok(Object(_) as m) => Some(m)
    _ => None
  }
}

///|
/// platform.mounts: macOS's, as `mount` says them (text.ts `parseMounts`).
fn mounts(env : Env) -> Array[String] {
  if !env.mac {
    return []
  }
  if mounted.val is Some((at, points)) && env.now - at <= 2000.0 {
    return points
  }
  let out = match (try { Ok(env.host.shell_sync("proc.run", { "command": "/sbin/mount", "args": [], "timeoutMs": 60000, "maxBytes": 1048576 })) } catch { e => Err(e) }) {
    Ok(String(text)) => text
    _ => match mounted.val { Some((_, points)) => { mounted.val = Some((env.now, points)); return points }; None => "" }
  }
  let found = []
  for line in out.split("\n") {
    let line = line.to_owned()
    guard line.has_suffix(")") else { continue }
    let open = line.rev_find("(").unwrap_or(-1)
    guard open >= 1 && line.unsafe_charcode_at(open - 1) == ' ' else { continue }
    let inner = line.view(start_offset=open + 1, end_offset=line.length() - 1)
    guard !inner.contains(")") else { continue }
    guard line.find(" on /") is Some(s) && s + 5 <= open - 1 else { continue }
    let at = line.view(start_offset=s + 4, end_offset=open - 1).to_owned()
    if at == "/" || at == "/dev" || at.has_prefix("/System/Volumes/") {
      continue
    }
    found.push(at)
  }
  mounted.val = Some((env.now, found))
  found
}

///|
/// drive/fs.ts `protectedPlace`: the folder macOS protects that `path` is (or is under), if any.
fn protected_place(env : Env, path : String) -> String? {
  let lower = @jscase.lower(path)
  let under = (top : String) => {
    let t = @jscase.lower(top)
    lower == t || lower.has_prefix(t + "/")
  }
  for name in ["Documents", "Desktop", "Downloads", "Library/Mobile Documents", "Library/CloudStorage"] {
    let top = @nodepath.join(env.sep, [env.homedir, name])
    if under(top) {
      return Some(top)
    }
  }
  let mut mount : String? = None
  for m in mounts(env) {
    if !lower.has_prefix("/volumes/") && under(m) && m.length() > mount.map(x => x.length()).unwrap_or(0) {
      mount = Some(m)
    }
  }
  if mount is Some(_) {
    return mount
  }
  guard lower.has_prefix("/volumes/") && lower.length() > 9 && lower.unsafe_charcode_at(9) != '/' else { return None }
  let parts = path.split("/").collect()
  let top = "/Volumes/" + parts.get(2).map(p => p.to_owned()).unwrap_or("")
  match (try { Ok(env.host.shell_sync("fs.stat", { "path": Json::string(top), "lstat": true })) } catch { e => Err(e) }) {
    Ok(String("link")) => None
    Ok(String(_)) => Some(top)
    _ => None
  }
}

///|
/// ops/places.ts `follow`: `path` with its links followed, none at or under a protected folder touched: Ok(the real
/// path), Err(Some(as far as it was followed)) at a protected folder, Err(None) where a part is not there.
fn follow(env : Env, path : String) -> Result[String, String?] {
  let split = (p : String) => p.split("/").filter(x => x != "" && x != ".").map(x => x.to_owned()).collect()
  let mut pending : Array[String] = split(clean_path(env, path))
  let mut done : Array[String] = []
  let mut hops = 0
  while pending.length() > 0 {
    let name = pending.remove(0)
    if name == ".." {
      ignore(done.pop())
      continue
    }
    let next = done + [name]
    let at = "/" + next.join("/")
    if protected_place(env, at) is Some(_) {
      return Err(Some("/" + (next + pending).join("/")))
    }
    let link = match (try { Ok(env.host.shell_sync("fs.stat", { "path": Json::string(at), "lstat": true })) } catch { e => Err(e) }) {
      Ok(String(k)) => k == "link"
      _ => return Err(None)
    }
    if !link {
      done = next
      continue
    }
    hops += 1
    if hops > 40 {
      return Err(None)
    }
    let target = match (try { Ok(env.host.shell_sync("fs.readlink", { "path": Json::string(at) })) } catch { e => Err(e) }) {
      Ok(String(t)) => t
      _ => return Err(None)
    }
    if target.has_prefix("/") {
      done = []
    }
    pending = split(target) + pending
  }
  Ok("/" + done.join("/"))
}

///|
/// ops/places.ts `realOutside`: `path` with its links followed as realpath has it; on macOS one in a protected folder
/// said as far as it was followed; None when it is not there.
fn real_outside(env : Env, path : String) -> String? {
  if !env.mac {
    return real_path(env, path)
  }
  match follow(env, path) {
    Err(Some(p)) => Some(p)
    Err(None) => None
    Ok(real) => real_path(env, real)
  }
}

///|
/// sessions.ts `naming`: where a file's path as git lists it has `tail` (its parts between `/`, `...` or `…` any
/// directories), the first place it does, its end there: what it names ends there.
fn named_end(parts : Array[String], f : String) -> Int? {
  // the parts from `i` on matched from `at`: where the match ends, the longest a wildcard can take first
  fn from(parts : Array[String], f : String, i : Int, at : Int) -> Int? {
    if i == parts.length() {
      return if at == f.length() || f.unsafe_charcode_at(at) == '/' { Some(at) } else { None }
    }
    let sep_first = i > 0
    let mut start = at
    if sep_first {
      if at >= f.length() || f.unsafe_charcode_at(at) != '/' {
        return None
      }
      start = at + 1
    }
    let p = parts[i]
    if p == "..." || p == "…" {
      let mut end = f.length()
      while end > start {
        if from(parts, f, i + 1, end) is Some(e) {
          return Some(e)
        }
        end -= 1
      }
      return None
    }
    if f.length() - start >= p.length() && f.view(start_offset=start, end_offset=start + p.length()) == p.view() {
      from(parts, f, i + 1, start + p.length())
    } else {
      None
    }
  }
  for s = 0; s < f.length(); s = s + 1 {
    if s == 0 && from(parts, f, 0, 0) is Some(e) {
      return Some(e)
    }
    if f.unsafe_charcode_at(s) == '/' && from(parts, f, 0, s + 1) is Some(e) {
      return Some(e)
    }
  }
  None
}

///|
/// sessions.ts `touched`: when a repository was last fetched, checked out or committed to.
fn touched(env : Env, repo : String) -> Double {
  let mut at = 0.0
  for f in ["FETCH_HEAD", "HEAD", "index"] {
    if meta_of(env, @nodepath.join(env.sep, [repo, ".git", f])) is Some({ "mtime": Number(m, ..), .. }) && m > at {
      at = m
    }
  }
  at
}

///|
/// sessions.ts `inRepositories`: a relative path not under the working directory, as agents write one from inside a
/// repository: the file of a repository in `dirs` (one of them, or two levels below) whose path ends with it, or a
/// directory of one; the shortest, when several do; `latest`: of several repositories, the one last touched.
fn in_repositories(env : Env, dirs : Array[String?], given : String, latest~ : Bool = false) -> String? {
  let tail = clean_posix(env, given).view(start_offset=1).to_owned()
  if tail == "" {
    return None
  }
  let parts = tail.split("/").map(p => p.to_owned()).collect()
  let repos : Array[String] = []
  fn look(env : Env, repos : Array[String], dir : String, depth : Int) -> Unit {
    if meta_of(env, @nodepath.join(env.sep, [dir, ".git"])) is Some(_) {
      if !repos.contains(dir) {
        repos.push(dir)
      }
      return
    }
    if depth == 0 {
      return
    }
    let entries = match (try { Ok(env.host.shell_sync("fs.readdir", { "path": Json::string(dir), "types": true })) } catch { e => Err(e) }) {
      Ok(Array(es)) => es
      _ => return
    }
    for e in entries {
      if e is [String(name), String("dir")] && !name.has_prefix(".") && name != "node_modules" {
        look(env, repos, @nodepath.join(env.sep, [dir, name]), depth - 1)
      }
    }
  }
  for dir in dirs {
    guard dir is Some(d) && d != "" else { continue }
    if env.mac && protected_place(env, real_outside(env, d).unwrap_or(d)) is Some(_) {
      continue
    }
    look(env, repos, d, 2)
  }
  let mut best : String? = None
  let mut best_at = -1.0
  for repo in repos {
    let files = match listed.get(repo) {
      Some((at, files)) if !(env.now - at > 60000.0) => files
      _ => {
        let files = match (try { Ok(env.host.shell_sync("proc.run", { "command": "git", "args": ["-C", repo, "ls-files", "-z"], "timeoutMs": 5000, "maxBytes": 67108864 })) } catch { e => Err(e) }) {
          Ok(String(out)) => out.split("\u{0}").filter(x => x != "").map(x => x.to_owned()).collect()
          _ => []
        }
        listed[repo] = (env.now, files)
        files
      }
    }
    let at = if latest { touched(env, repo) } else { 0.0 }
    for f in files {
      guard named_end(parts, f) is Some(end) else { continue }
      let path = @nodepath.join(env.sep, [repo, f.view(end_offset=end).to_owned()])
      if best is None || at > best_at || (at == best_at && path.length() < best.unwrap().length()) {
        best = Some(path)
        best_at = at
      }
    }
  }
  match best {
    Some(b) => real_path(env, b)
    None => None
  }
}

///|
/// sessions.ts `mime`: by the file's extension.
fn mime(env : Env, path : String) -> String {
  let name = place_name(env, path)
  let dot = name.rev_find(".").unwrap_or(-1)
  if dot <= 0 {
    return "application/octet-stream"
  }
  match @jscase.lower(name.view(start_offset=dot + 1).to_owned()) {
    "png" => "image/png"
    "jpg" | "jpeg" => "image/jpeg"
    "gif" => "image/gif"
    "webp" => "image/webp"
    "svg" => "image/svg+xml"
    "pdf" => "application/pdf"
    "txt" => "text/plain; charset=utf-8"
    "md" => "text/markdown; charset=utf-8"
    "json" => "application/json"
    _ => "application/octet-stream"
  }
}

///|
/// sessions.ts `sessionPlace`.
pub fn session_place(db : @sql.Db, host : @host.Host, data : String, sep : String, ask : Json) -> Json raise {
  let args = ask.value("args").unwrap_or(Json::null())
  let words = args.value("words").unwrap_or(Json::null())
  let word = (k : String) => match words.value(k) { Some(String(s)) => s; _ => k }
  let given = args.value("env").unwrap_or(Json::null())
  let env : Env = {
    host,
    sep,
    home: match given.value("home") { Some(String(h)) => h; _ => "" },
    homedir: match given.value("homedir") { Some(String(h)) => h; _ => "" },
    mac: given.value("mac") is Some(True),
    now: match args.value("now") { Some(Number(n, ..)) => n; _ => 0.0 },
  }
  let row = session_row(db, args.value("key").unwrap_or(Json::null()))
  let asked = match args.value("path") {
    Some(String(p)) => @jscase.trim(p)
    None | Some(Null) => ""
    Some(_) => raise Refused(500, "given.trim is not a function")
  }
  if asked == "" || asked.contains("\u{0}") {
    raise Refused(404, word("notFound"))
  }
  let cwd = match field(row, "cwd") { String(c) => Some(c); _ => None }
  let workspace = match field(row, "workspace") { String(w) => w; _ => "" }
  let base = cwd.unwrap_or(workspace)
  let tilde = asked.has_prefix("~/") && env.home != ""
  let relative = !tilde && !is_absolute(env, asked)
  let full = if tilde {
    @nodepath.join(sep, [env.home, asked.view(start_offset=2).to_owned()])
  } else if relative {
    @nodepath.join(sep, [base, asked])
  } else {
    asked
  }
  let outside = real_outside(env, clean_path(env, full))
  if outside is Some(o) && protected_place(env, o) is Some(_) && env.mac {
    raise Refused(403, word("protected"))
  }
  let path = match outside {
    Some(o) => Some(o)
    None if relative =>
      match in_repositories(env, [Some(workspace), cwd], asked) {
        Some(p) => Some(p)
        None => in_repositories(env, [Some(@nodepath.join(sep, [data, "repos"]))], asked, latest=true)
      }
    None => None
  }
  guard path is Some(path) else { raise Refused(404, word("notFound")) }
  let raw = read_json(host, join_path(sep, data, "config.json"))
  let agent = join_path(sep, data, match jget(Some(raw), "agentHome") {
    Some(Str(h)) => @jsjson.raw_text(h)
    _ => "agent"
  })
  let roots = [Some(workspace), cwd, Some(@nodepath.join(sep, [data, "repos"])), Some(agent)]
    .filter_map(r => match r { Some(r) if r != "" => real_outside(env, r); _ => None })
  if !roots.iter().any(r => within_dir(env, path, r)) {
    raise Refused(403, word("outside"))
  }
  guard meta_of(env, path) is Some(m) else { raise Refused(404, word("notFound")) }
  {
    "path": Json::string(path),
    "name": Json::string(place_name(env, path)),
    "dir": m.value("dir").unwrap_or(false),
    "size": m.value("size").unwrap_or(Json::number(0.0)),
    "mtime": match m.value("mtime") { Some(Number(t, ..)) => Json::number(t.round()); _ => Json::null() },
    "contentType": Json::string(mime(env, path)),
  }
}
