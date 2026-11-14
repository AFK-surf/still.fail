// The agents' memory for the pages (station/src/read/memory.ts `memory`, GET /memory): the global MEMORY.md and the
// shared skills of the home workspace's agents' home, or of a joined workspace's (<agent home>/workspaces/<ws>).

///|
/// The skills the station brings, rewritten at every start (memory.ts BUILTIN).
let builtin_skills : Array[String] = [
  "stillfail-chats", "stillfail-jobs", "stillfail-show", "stillfail-viz", "stillfail-browser", "stillfail-login", "stillfail-vault",
  "stillfail-cron", "stillfail-github-ci", "stillfail-retire", "stillfail-feedback",
]

///|
/// What a project memory's description starts with.
let project_prefix = "项目记忆："

///|
fn line_terminator(c : Int) -> Bool {
  c == 0x0a || c == 0x0d || c == 0x2028 || c == 0x2029
}

///|
/// memory.ts `front`: a SKILL.md's frontmatter field (`key: value`), if it has one.
fn front(text : String, key : String) -> String? {
  guard text.has_prefix("---\n") else { return None }
  let body = text.view(start_offset=4).to_owned()
  guard body.find("\n---") is Some(end) else { return None }
  for part in body.view(end_offset=end).to_owned().split("\n") {
    let raw = part.to_owned()
    let line = if raw.has_suffix("\r") { raw.view(end_offset=raw.length() - 1).to_owned() } else { raw }
    let head = key + ":"
    if line.has_prefix(head) {
      let value = @jscase.trim(line.view(start_offset=head.length()).to_owned())
      let mut a = 0
      while a < value.length() && value.unsafe_charcode_at(a) == '"' {
        a += 1
      }
      let mut b = value.length()
      while b > a && value.unsafe_charcode_at(b - 1) == '"' {
        b -= 1
      }
      return Some(value.view(start_offset=a, end_offset=b).to_owned())
    }
  }
  None
}

///|
/// /^SKILL\.conflict-.*\.md$/
fn is_conflict(name : String) -> Bool {
  let head = "SKILL.conflict-"
  guard name.has_prefix(head) && name.has_suffix(".md") && name.length() >= head.length() + 3 else { return false }
  for i in head.length()..<(name.length() - 3) {
    if line_terminator(name.unsafe_charcode_at(i)) {
      return false
    }
  }
  true
}

///|
/// The share a link into <data>/share/<id>/skill names (/\/share\/(sh-[0-9a-z]+)\/skill$/).
fn share_of_link(target : String) -> String? {
  guard target.has_suffix("/skill") else { return None }
  let dir = target.view(end_offset=target.length() - "/skill".length()).to_owned()
  let cut = match dir.rev_find("/") {
    Some(i) => i
    None => return None
  }
  let id = dir.view(start_offset=cut + 1).to_owned()
  guard id.has_prefix("sh-") && id.length() > 3 else { return None }
  for i in 3..<id.length() {
    let c = id.unsafe_charcode_at(i)
    guard (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') else { return None }
  }
  guard dir.view(end_offset=cut).to_owned().has_suffix("/share") else { return None }
  Some(id)
}

///|
fn jget(v : @jsjson.JValue?, k : String) -> @jsjson.JValue? {
  match v {
    Some(Obj(_) as o) => o.get(k)
    _ => None
  }
}

///|
fn array_or_null(v : @jsjson.JValue?) -> Json {
  match v {
    Some(Arr(_) as a) => to_json(a)
    _ => Json::null()
  }
}

///|
/// memory.ts `sharing`: shared from here (config.json `sharedSkills`), a copy of another station's (its link into
/// <data>/share/<id>/skill), or neither.
fn sharing(host : @host.Host, data : String, sep : String, raw : @jsjson.JValue, dir : String, name : String) -> Json raise {
  let hosted = jget(jget(Some(raw), "sharedSkills"), name)
  let hosted_id = match hosted {
    Some(Str(s)) => Some(@jsjson.raw_text(s))
    _ =>
      match jget(hosted, "id") {
        Some(Str(s)) => Some(@jsjson.raw_text(s))
        _ => None
      }
  }
  if hosted_id is Some(id) {
    let station = match jget(Some(read_json(host, join_path(sep, data, "mesh/cloud.json"))), "station") {
      None | Some(Null) => Json::string("")
      Some(v) => to_json(v)
    }
    let conflicts = match read_dir(host, join_path(sep, dir, name)) {
      Some(names) => names.filter(is_conflict).map(Json::string)
      None => []
    }
    let state = match jget(jget(Some(read_json(host, join_path(sep, data, "share/state.json"))), "hosted"), id) {
      None | Some(Null) => @jsjson.JValue::Obj([])
      Some(v) => v
    }
    let missing = match jget(Some(state), "missing") {
      Some(Obj(_) | Arr(_)) as m => m
      _ => None
    }
    let missed = entries_of(missing).map(e => e.0)
    let told = match jget(Some(state), "told") {
      Some(Obj(_) | Arr(_)) as t => t
      _ => None
    }
    let users = entries_of(told).filter_map(e => match e.1 {
      Num(v) if v >= 0.0 && !missed.contains(e.0) => Some(Json::string(e.0))
      _ => None
    })
    let out : Map[String, Json] = {
      "id": Json::string(id),
      "role": "host",
      "host": station,
      "allow": array_or_null(jget(hosted, "allow")),
      "conflicts": Json::array(conflicts),
      "users": Json::array(users),
      "missing": Json::array(
        entries_of(missing).filter_map(e => match e.1 {
          Str(why) => Some({ "station": Json::string(e.0), "why": Json::string(@jsjson.text(why)) })
          _ => None
        }),
      ),
    }
    if jget(Some(state), "unread") is Some(Str(u)) {
      out["unread"] = Json::string(@jsjson.text(u))
    }
    return Json::object(out)
  }
  let link = match host.shell_sync("fs.readlink", { "path": Json::string(join_path(sep, dir, name)) }) {
    String(t) => t
    _ => return Json::null()
  }
  guard share_of_link(link) is Some(id) else { return Json::null() }
  let had = jget(jget(Some(read_json(host, join_path(sep, data, "share/state.json"))), "borrowed"), id)
  guard truthy(had) else { return Json::null() }
  {
    "id": Json::string(id),
    "role": "user",
    "host": match jget(had, "host") {
      None | Some(Null) => Json::string("")
      Some(v) => to_json(v)
    },
    "allow": array_or_null(jget(had, "allow")),
    "conflicts": [],
  }
}

///|
/// memory.ts `skillFiles`: the Markdown files beside a SKILL.md but the edits kept from an older copy, by name.
fn skill_files(host : @host.Host, sep : String, dir : String) -> Array[Json] raise {
  guard read_dir(host, dir) is Some(names) else { return [] }
  let picked = names.filter(n => n.has_suffix(".md") && n != "SKILL.md" && !n.has_prefix("SKILL.conflict-"))
  picked.sort_by(by_bytes)
  let out = []
  for name in picked {
    if read_text(host, join_path(sep, dir, name), strict=true) is Some(text) {
      out.push(({ "name": Json::string(name), "text": Json::string(text) } : Json))
    }
  }
  out
}

///|
/// memory.ts `listSkills`; `shares`: whether its skills may be shared with other stations (the home workspace's only).
fn list_skills(host : @host.Host, data : String, sep : String, raw : @jsjson.JValue, home : String, shares : Bool) -> Array[Json] raise {
  let dir = join_path(sep, home, "skills")
  guard read_dir(host, dir) is Some(names) else { return [] }
  let skills : Array[(String, Bool, Bool, Json)] = []
  for name in names {
    guard read_text(host, join_path(sep, join_path(sep, dir, name), "SKILL.md"), strict=true) is Some(text) else { continue }
    let description = front(text, "description").unwrap_or("")
    let builtin = builtin_skills.contains(name)
    let project = description.has_prefix(project_prefix)
    let share = if builtin || !shares { Json::null() } else { sharing(host, data, sep, raw, dir, name) }
    skills.push((name, builtin, project, {
      "name": Json::string(name),
      "description": Json::string(description),
      "project": Json::boolean(project),
      "builtin": Json::boolean(builtin),
      "text": Json::string(text),
      "files": Json::array(skill_files(host, sep, join_path(sep, dir, name))),
      "share": share,
    }))
  }
  let rank = (b : Bool) => if b { 1 } else { 0 }
  skills.sort_by((a, b) => {
    let by = rank(a.1) - rank(b.1)
    if by != 0 {
      return by
    }
    let by = rank(!a.2) - rank(!b.2)
    if by != 0 {
      return by
    }
    by_bytes(a.0, b.0)
  })
  skills.map(s => s.3)
}

///|
/// The workspace ids memory.ts takes (/^[0-9A-Za-z_-]{1,128}$/).
fn workspace_id(ws : String) -> Bool {
  ws.length() >= 1 &&
  ws.length() <= 128 &&
  ws.iter().all(c => (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_' || c == '-')
}

///|
/// GET /memory: the home workspace's, or with `workspace` that joined workspace's (none yet: empty).
pub fn memory(host : @host.Host, data : String, sep : String, args : Json) -> Json raise {
  let raw = read_json(host, join_path(sep, data, "config.json"))
  let ws = match args.value("workspace") {
    Some(String(w)) => Some(w)
    _ => None
  }
  if ws is Some(w) && !workspace_id(w) {
    raise Refused(400, "not a workspace id")
  }
  let agent = join_path(sep, data, match jget(Some(raw), "agentHome") {
    Some(Str(h)) => @jsjson.raw_text(h)
    _ => "agent"
  })
  let home = match ws {
    Some(w) => join_path(sep, join_path(sep, agent, "workspaces"), w)
    None => agent
  }
  let path = join_path(sep, home, "MEMORY.md")
  {
    "global": { "path": Json::string(path), "text": Json::string(read_text(host, path, strict=true).unwrap_or("")) },
    "skills": Json::array(list_skills(host, data, sep, raw, home, ws is None)),
  }
}
