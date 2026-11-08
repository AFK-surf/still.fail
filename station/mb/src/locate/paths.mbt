// Where a session's transcripts are, as station/src/read/transcript.ts finds them (`transcriptPaths`,
// `transcriptSources` and what they call): its paths made as Node's path.join makes them, the filesystem asked through
// the shell (`fs.stat`, `fs.readdir`, `fs.realpath`, as Node's statSync, readdirSync and realpathSync answer), and the
// in-process hints it keeps (`elsewhere`, `rollouts`, `saidRollouts`) given for each batch by the station
// (`transcriptLocationHints`) and given back after it.

///|
/// A Codex rollout path a running thread said (transcript.ts `SaidRollout`).
pub(all) struct Said {
  suffix : String
  mut seen : Bool
}

///|
/// What finds transcripts: the shell, the platform's separator and the hints of the batch being looked for.
pub struct Finder {
  priv host : @host.Host
  priv sep : String
  priv elsewhere : Map[String, String?]
  priv rollouts : Map[String, String]
  priv said : Map[String, Map[String, Said]]
}

///|
pub fn Finder::new(host : @host.Host, sep : String) -> Finder {
  { host, sep, elsewhere: Map([]), rollouts: Map([]), said: Map([]) }
}

///|
/// Node's path.join (posix's, or win32's when the separator is `\`): the parts joined, then normalized.
pub fn Finder::join(self : Finder, parts : Array[String]) -> String {
  @nodepath.join(self.sep, parts)
}

///|
/// What stat says a path is ("file", "dir", "other"), none when it cannot.
fn Finder::stat(self : Finder, path : String) -> String? {
  match (try { Ok(self.host.shell_sync("fs.stat", { "path": Json::string(path) })) } catch { e => Err(e) }) {
    Ok(String(kind)) => Some(kind)
    _ => None
  }
}

///|
fn Finder::is_file(self : Finder, path : String) -> Bool {
  self.stat(path) == Some("file")
}

///|
fn Finder::is_dir(self : Finder, path : String) -> Bool {
  self.stat(path) == Some("dir")
}

///|
/// archive.rs `storage`: the file, or its `.zst` once put away.
fn Finder::storage(self : Finder, path : String) -> String {
  if self.stat(path) is Some(_) {
    path
  } else {
    path + ".zst"
  }
}

///|
fn Finder::kept(self : Finder, path : String) -> Bool {
  self.is_file(self.storage(path))
}

///|
/// A directory's names, none when it cannot be read.
fn Finder::entries(self : Finder, dir : String) -> Array[String]? {
  match (try { Ok(self.host.shell_sync("fs.readdir", { "path": Json::string(dir) })) } catch { e => Err(e) }) {
    Ok(Array(names)) => Some(names.filter_map(n => if n is String(s) { Some(s) } else { None }))
    _ => None
  }
}

///|
/// A directory's names with their kinds as the directory says them ("file", "dir", "link", "other").
fn Finder::typed_entries(self : Finder, dir : String) -> Array[(String, String)]? {
  match (try { Ok(self.host.shell_sync("fs.readdir", { "path": Json::string(dir), "types": true })) } catch { e => Err(e) }) {
    Ok(Array(entries)) =>
      Some(
        entries.filter_map(e => if e is Array([String(name), String(kind)]) { Some((name, kind)) } else { None }),
      )
    _ => None
  }
}

///|
fn Finder::real(self : Finder, path : String) -> String? {
  match (try { Ok(self.host.shell_sync("fs.realpath", { "path": Json::string(path) })) } catch { e => Err(e) }) {
    Ok(String(p)) => Some(p)
    _ => None
  }
}

///|
/// transcript.ts `transcriptDir`.
pub fn transcript_dir(runtime : String) -> String {
  match runtime {
    "claude" => "projects"
    "codex" => "sessions"
    "grok" => "grok/sessions"
    "cursor" => "cursor/sessions"
    "devin" => "devin/sessions"
    "hermes" => "hermes/sessions"
    "agy" => "agy/sessions"
    _ => "dsh-sessions"
  }
}

///|
/// agents/runtime.ts `RUNTIME_KINDS`.
pub fn runtime_kind(runtime : String) -> Bool {
  ["claude", "codex", "dsh", "grok", "cursor", "devin", "hermes", "agy"].contains(runtime)
}

///|
/// transcript.ts `claudeProject`: each character but an ASCII letter or digit a dash, none past 200 (UTF-16 units).
fn claude_project(cwd : String) -> String? {
  if cwd.length() > 200 {
    return None
  }
  let out = StringBuilder::new()
  for i in 0..<cwd.length() {
    let c = cwd.unsafe_charcode_at(i)
    if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') {
      out.write_char(c.unsafe_to_char())
    } else {
      out.write_char('-')
    }
  }
  Some(out.to_string())
}

///|
/// transcript.ts `placedIn`.
fn Finder::placed_in(self : Finder, runtime : String, dir : String, id : String, places : Array[String]) -> String? {
  if runtime != "claude" {
    return None
  }
  for place in places {
    let ways = match self.real(place) {
      Some(at) => if at == place { [place] } else { [place, at] }
      None => [place]
    }
    for way in ways {
      guard claude_project(way) is Some(project) else { continue }
      let path = self.join([dir, project, id + ".jsonl"])
      if self.kept(path) {
        return Some(path)
      }
    }
  }
  None
}

///|
/// transcript.ts `transcriptIn`.
fn Finder::transcript_in(self : Finder, runtime : String, dir : String, id : String, placed : Bool, anywhere : Bool) -> String? {
  match runtime {
    "dsh" => return self.dsh(dir, id)
    "grok" => return self.grok(dir, id)
    "cursor" | "devin" | "hermes" | "agy" => {
      let path = self.join([dir, id + ".jsonl"])
      return if self.kept(path) { Some(path) } else { None }
    }
    "claude" => {
      let at = dir + "\u{0}" + id
      match self.elsewhere.get(at) {
        Some(None) => if placed { return None }
        Some(Some(kept)) => if self.kept(kept) { return Some(kept) }
        None => ()
      }
      if !anywhere {
        return None
      }
      for project in self.entries(dir).unwrap_or([]) {
        let path = self.join([dir, project, id + ".jsonl"])
        if self.kept(path) {
          self.elsewhere[at] = Some(path)
          return Some(path)
        }
      }
      if placed {
        self.elsewhere[at] = None
      }
      return None
    }
    _ => ()
  }
  let at = dir + "\u{0}" + id
  if self.rollouts.get(at) is Some(kept) && self.kept(kept) {
    return Some(kept)
  }
  let found = self.rollout(dir, id)
  if found is Some(path) {
    self.rollouts[at] = path
  }
  found
}

///|
/// A Codex rollout file under `dir`, through its days' directories, as `transcriptIn`'s `find`.
fn Finder::rollout(self : Finder, dir : String, id : String) -> String? {
  guard self.typed_entries(dir) is Some(entries) else { return None }
  for entry in entries {
    let (name, kind) = entry
    let path = self.join([dir, name])
    if kind == "dir" || (kind != "file" && self.is_dir(path)) {
      if self.rollout(path, id) is Some(found) {
        return Some(found)
      }
    } else if name.has_prefix("rollout-") && name.has_suffix(id + ".jsonl") {
      return Some(path)
    } else if name.has_prefix("rollout-") && name.has_suffix(id + ".jsonl.zst") {
      return Some(path.view(end_offset=path.length() - 4).to_owned())
    }
  }
  None
}

///|
/// The N of `session.v<N>.jsonl` (as Number reads its digits), none for another name.
fn dsh_version(name : String) -> Double? {
  guard name.has_prefix("session.v") && name.has_suffix(".jsonl") else { return None }
  let digits = name.view(start_offset=9, end_offset=name.length() - 6)
  if digits.length() == 0 {
    return None
  }
  let mut n = 0.0
  for c in digits {
    guard c >= '0' && c <= '9' else { return None }
    n = n * 10.0 + (c.to_int() - '0'.to_int()).to_double()
  }
  Some(n)
}

///|
/// transcript.ts `dshTranscript`: the highest version's file (the first of equal ones) in the first directory with one.
fn Finder::dsh(self : Finder, root : String, id : String) -> String? {
  for dir in self.entries(root).unwrap_or([]) {
    let mut best : (String, Double)? = None
    for name in self.entries(self.join([root, dir, id])).unwrap_or([]) {
      guard dsh_version(name) is Some(v) else { continue }
      match best {
        Some((_, b)) => if v > b { best = Some((name, v)) }
        None => best = Some((name, v))
      }
    }
    if best is Some((name, _)) {
      return Some(self.join([root, dir, id, name]))
    }
  }
  None
}

///|
/// transcript.ts `grokTranscript`.
fn Finder::grok(self : Finder, root : String, id : String) -> String? {
  for dir in self.entries(root).unwrap_or([]) {
    let path = self.join([root, dir, id, "chat_history.jsonl"])
    if self.kept(path) {
      return Some(path)
    }
  }
  None
}

///|
/// transcript.ts `homesFirst`.
fn homes_first(profiles : Array[(String, String)], first : String?) -> Array[String] {
  let out = []
  for p in profiles {
    if Some(p.0) == first {
      out.push(p.1)
    }
  }
  for p in profiles {
    if Some(p.0) != first {
      out.push(p.1)
    }
  }
  out
}

///|
/// transcript.ts `transcriptPaths` for one id, `anywhere` false as the live locator asks it: its path, if found.
fn Finder::transcript_path(self : Finder, runtime : String, data : String, homes : Array[String], id : String, places : Array[String]) -> String? {
  let anywhere = false
  let shared = self.join([data, "transcripts", runtime])
  let ways = homes.map(home => self.join([home, transcript_dir(runtime)]))
  let said_dirs = if runtime == "codex" { [shared, ..ways] } else { [] }
  let dirs = [shared]
  let mut next_way = 0
  let mut seen : Set[String]? = None
  let dir_at = (i : Int) => {
    while dirs.length() <= i && next_way < ways.length() {
      let s = match seen {
        Some(s) => s
        None => {
          let s = Set([self.real(shared).unwrap_or(shared)])
          seen = Some(s)
          s
        }
      }
      let dir = ways[next_way]
      next_way += 1
      if self.real(dir) is Some(at) && !s.contains(at) {
        s.add(at)
        dirs.push(dir)
      }
    }
    if i < dirs.length() {
      Some(dirs[i])
    } else {
      None
    }
  }
  let in_dirs = (look : (String) -> String?) => {
    for i = 0; dir_at(i) is Some(dir); i = i + 1 {
      if look(dir) is Some(path) {
        return Some(path)
      }
    }
    None
  }
  let placed = places.length() > 0
  let mut reported : Said? = None
  if runtime == "codex" {
    for dir in said_dirs {
      let known = match self.said.get(id) {
        Some(m) =>
          match m.get(dir) {
            Some(s) => Some(s)
            None => m.get(self.real(dir).unwrap_or(dir))
          }
        None => None
      }
      guard known is Some(said) else { continue }
      if reported is None {
        reported = Some(said)
      }
      let path = self.join([dir, said.suffix])
      if self.kept(path) {
        said.seen = true
        return Some(path)
      }
      if !said.seen && !anywhere {
        return None
      }
    }
  }
  let path = match in_dirs(dir => self.placed_in(runtime, dir, id, places)) {
    Some(p) => Some(p)
    None => in_dirs(dir => self.transcript_in(runtime, dir, id, placed, anywhere))
  }
  if path is Some(_) && reported is Some(said) {
    said.seen = true
  }
  path
}

///|
/// A runtime session whose transcript is looked for (live-location-protocol.ts `LiveSource`).
pub(all) struct Source {
  id : String
  runtime : String
  profile : String?
}

///|
/// transcript.ts `transcriptSources` with `anywhere` false: each source's path with its runtime, and whether the last
/// one's was found.
pub fn Finder::sources(
  self : Finder,
  data : String,
  profiles : Array[(String, String)],
  sources : Array[Source],
  places : Array[String],
) -> (Array[(String, String)], Bool) {
  let paths = []
  let mut current = false
  for source in sources {
    if !runtime_kind(source.runtime) {
      current = false
      continue
    }
    let found = self.transcript_path(source.runtime, data, homes_first(profiles, source.profile), source.id, places)
    current = found is Some(_)
    if found is Some(path) {
      paths.push((path, source.runtime))
    }
  }
  (paths, current)
}

///|
/// transcript.ts `useTranscriptLocationHints`: the hints of one batch, read from what the station sent.
pub fn Finder::use_hints(self : Finder, hints : Json) -> Unit {
  self.elsewhere.clear()
  self.rollouts.clear()
  self.said.clear()
  if hints is { "elsewhere": Array(pairs), .. } {
    for pair in pairs {
      match pair {
        [String(key), String(path)] => self.elsewhere[key] = Some(path)
        [String(key), Null] => self.elsewhere[key] = None
        _ => ()
      }
    }
  }
  if hints is { "rollouts": Array(pairs), .. } {
    for pair in pairs {
      if pair is [String(key), String(path)] {
        self.rollouts[key] = path
      }
    }
  }
  if hints is { "said": Array(ids), .. } {
    for entry in ids {
      guard entry is [String(id), Array(dirs)] else { continue }
      let m : Map[String, Said] = Map([])
      for d in dirs {
        if d is [String(dir), { "suffix": String(suffix), "seen": seen, .. }] {
          m[dir] = { suffix, seen: seen is True }
        }
      }
      self.said[id] = m
    }
  }
}

///|
/// The hints as the batch left them, to be given back (`TranscriptLocationHints`): only this batch's are kept here.
pub fn Finder::hints(self : Finder) -> Json {
  let elsewhere : Array[Json] = []
  for key, path in self.elsewhere {
    elsewhere.push([Json::string(key), match path { Some(p) => Json::string(p); None => Json::null() }])
  }
  let rollouts : Array[Json] = []
  for key, path in self.rollouts {
    rollouts.push([Json::string(key), Json::string(path)])
  }
  let said : Array[Json] = []
  for id, dirs in self.said {
    let entries : Array[Json] = []
    for dir, s in dirs {
      entries.push([Json::string(dir), { "suffix": Json::string(s.suffix), "seen": Json::boolean(s.seen) }])
    }
    said.push([Json::string(id), Json::array(entries)])
  }
  { "elsewhere": Json::array(elsewhere), "rollouts": Json::array(rollouts), "said": Json::array(said) }
}
