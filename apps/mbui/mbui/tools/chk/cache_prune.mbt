// chk cache-prune [--dry-run]: the Actions caches a newer one of the same kind has replaced, deleted (cache-prune.yml;
// GH_REPO=owner/name, gh logged in or GH_TOKEN with actions: write).
//
// A repository has 10 GB of caches; past that GitHub evicts the least recently used, and what went first were the
// caches read seldom that jobs cannot do without (WARP, the emulator's system images, MoonBit: "no WARP 1.0.21 in the
// Actions cache", runs 39536847651, 39731343052). A cache saved once per commit, run or content is keyed
// <kind>-<id>, the id a sha, a content's hash (16 hex digits or more) or a run's <id>-<attempt>; a restore by
// restore-keys takes the newest of a kind on its ref (then main's), so the older ones of a kind on a ref are never read
// again: kept is the newest of each kind on each live ref, the rest deleted (one under a megabyte left: it frees
// nothing). A deleted branch's caches cannot be restored by another branch, so all of its caches are removed once
// they have not been created or read for 30 minutes. Pull request and other refs keep their own existing rules.
// (A list of the kinds by name, as .github/cache_prune.py had, missed each new one: on 2026-10-22 mbui-apk-<sha>,
// android-lint-main-<sha>, android-build-main-<sha> and the mbui-linux-store-… ones were 4 GB of the 22.)
// setup-gradle's parts of a Gradle home (gradle-transforms-v1-<hash>, gradle-dependencies-v1-…: by their content,
// each read as a home that names it is restored) are deleted when read 30 minutes or more before the earliest last
// read of the homes kept on their ref (each job's newest): a part one of them names is read each time it is (a day's
// were 6 GB on 2026-10-22, when the rule was a day since they were read). Measured against the last read of a part
// of their kind instead, those of a job run less often went: check-android's home then named parts no longer there,
// its Gradle cold (2026-10-22, 39752751241).

///|
struct Cache {
  id : String
  key : String
  ref_ : String
  size : Int64
  created : Double
  accessed : Double
}

///|
let stale_parts_s : Double = 30.0 * 60.0

///|
let deleted_head_grace_s : Double = 30.0 * 60.0

///|
fn is_hex(s : String) -> Bool {
  s.length() > 0 &&
  s.iter().all(fn(c) { (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') })
}

///|
fn is_digits(s : String) -> Bool {
  s.length() > 0 && s.iter().all(fn(c) { c >= '0' && c <= '9' })
}

///|
/// GitHub's cache sizes are non-negative whole bytes. Reject overflow rather than rounding through a Double.
fn cache_size(s : String) -> Int64? {
  if !is_digits(s) {
    return None
  }
  let mut n = 0L
  for c in s.to_array() {
    let d = (c.to_int() - '0'.to_int()).to_int64()
    if n > (9223372036854775807L - d) / 10L {
      return None
    }
    n = n * 10L + d
  }
  Some(n)
}

///|
/// setup-gradle's part of a home: gradle-<name>-v1-<32 hex digits>
fn is_gradle_part(key : String) -> Bool {
  if !key.has_prefix("gradle-") || key.has_prefix("gradle-home-") {
    return false
  }
  let parts = key.split("-").map(fn(p) { p.to_owned() }).to_array()
  let n = parts.length()
  n >= 4 && parts[n - 2] == "v1" && parts[n - 1].length() == 32 && is_hex(parts[n - 1])
}

///|
/// A rolling cache's kind (its key without the id), or None for one kept by its own name
fn kind_of(key : String) -> String? {
  let parts = key.split("-").map(fn(p) { p.to_owned() }).to_array()
  let n = parts.length()
  if n >= 2 && parts[n - 1].length() >= 16 && is_hex(parts[n - 1]) {
    return Some(parts[0:n - 1].join("-"))
  }
  if n >= 3 && is_digits(parts[n - 1]) && is_digits(parts[n - 2]) && parts[n - 2].length() >= 6 {
    return Some(parts[0:n - 2].join("-"))
  }
  None
}

///|
/// A GitHub UTC timestamp (2026-10-22T05:37:59.731503Z): seconds since 1970, or 0 for an invalid value.
fn iso_s(t : String) -> Double {
  // A partial or malformed time cannot safely order caches or determine their age.
  if t.length() < 20 || t.code_unit_at(t.length() - 1).to_int() != 90 {
    return 0.0
  }
  for (i, want) in [(4, 45), (7, 45), (10, 84), (13, 58), (16, 58)] {
    if t.code_unit_at(i).to_int() != want {
      return 0.0
    }
  }
  for i in 0..<19 {
    if i == 4 || i == 7 || i == 10 || i == 13 || i == 16 {
      continue
    }
    let c = t.code_unit_at(i).to_int()
    if c < 48 || c > 57 {
      return 0.0
    }
  }
  if t.length() > 20 {
    if t.length() < 22 || t.code_unit_at(19).to_int() != 46 {
      return 0.0
    }
    for i in 20..<(t.length() - 1) {
      let c = t.code_unit_at(i).to_int()
      if c < 48 || c > 57 {
        return 0.0
      }
    }
  }
  let num = fn(a : Int, b : Int) -> Int {
    let mut v = 0
    for i in a..<b {
      if i < t.length() {
        let c = t.code_unit_at(i).to_int()
        if c >= 48 && c <= 57 {
          v = v * 10 + (c - 48)
        }
      }
    }
    v
  }
  let y0 = num(0, 4)
  let m = num(5, 7)
  let d = num(8, 10)
  let hour = num(11, 13)
  let minute = num(14, 16)
  let second = num(17, 19)
  if y0 < 1970 || m < 1 || m > 12 || hour > 23 || minute > 59 || second > 59 {
    return 0.0
  }
  let leap = y0 % 4 == 0 && (y0 % 100 != 0 || y0 % 400 == 0)
  let last_day = if m == 2 {
    if leap { 29 } else { 28 }
  } else if m == 4 || m == 6 || m == 9 || m == 11 {
    30
  } else {
    31
  }
  if d < 1 || d > last_day {
    return 0.0
  }
  // days from 1970-01-01 (Howard Hinnant's days_from_civil)
  let y = if m <= 2 { y0 - 1 } else { y0 }
  let era = (if y >= 0 { y } else { y - 399 }) / 400
  let yoe = y - era * 400
  let mp = if m > 2 { m - 3 } else { m + 9 }
  let doy = (153 * mp + 2) / 5 + d - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  let days = era * 146097 + doe - 719468
  days.to_double() * 86400.0 +
  (hour * 3600 + minute * 60 + second).to_double()
}

///|
fn gh_lines(args : String) -> Array[String]? {
  match @sys.run_out("gh " + args) {
    Some(o) =>
      Some(
        o
        .split("\n")
        .map(fn(l) { l.to_owned() })
        .filter(fn(l) { l.length() > 0 })
        .to_array(),
      )
    None => None
  }
}

///|
/// A deleted branch's old caches are not available to live branches. Keep recent and non-branch refs.
fn deleted_head_cache(c : Cache, heads : Map[String, Bool], now : Double) -> Bool {
  c.ref_.has_prefix("refs/heads/") &&
  !heads.contains(c.ref_) &&
  c.created > 0.0 && c.accessed > 0.0 &&
  now - c.created >= deleted_head_grace_s && now - c.accessed >= deleted_head_grace_s
}

///|
/// A Git ref can contain shell metacharacters, including single quotes.
fn shell_arg(s : String) -> String {
  "'" + s.replace(old="'", new="'\\''") + "'"
}

///|
/// Recheck a missing ref: branch creation/deletion while listing pages can make one live branch fall between pages.
/// None means GitHub did not give a definite answer; never turn an API failure into permission to delete.
fn head_missing(repo : String, ref_ : String) -> Bool? {
  let names = repo.split("/").map(fn(p) { p.to_owned() }).to_array()
  if names.length() != 2 || names[0] == "" || names[1] == "" {
    return None
  }
  let query = "query($owner:String!,$name:String!,$ref:String!){repository(owner:$owner,name:$name){ref(qualifiedName:$ref){name}}}"
  let jq = "if ((.errors // []) | length) > 0 or .data.repository == null then \"error\" elif .data.repository.ref == null then \"missing\" else \"present\" end"
  let args = "api graphql -f " + shell_arg("owner=" + names[0]) + " -f " + shell_arg("name=" + names[1]) +
    " -f " + shell_arg("ref=" + ref_) + " -f " + shell_arg("query=" + query) + " --jq " + shell_arg(jq)
  match gh_lines(args) {
    Some(lines) if lines.length() == 1 && lines[0] == "missing" => Some(true)
    Some(lines) if lines.length() == 1 && lines[0] == "present" => Some(false)
    _ => None
  }
}

///|
fn still_there(repo : String, c : Cache) -> Bool {
  // Pass the ref as a query field, so quotes and URL metacharacters in a branch name stay part of the ref.
  let args = "api --paginate -X GET " + shell_arg("repos/" + repo + "/actions/caches") +
    " -f per_page=100 -f " + shell_arg("ref=" + c.ref_) + " -q '.actions_caches[].id'"
  match gh_lines(args) {
    Some(ids) => ids.contains(c.id)
    None => true
  }
}

///|
fn cache_prune(args : Array[String]) -> Int {
  let dry = args.contains("--dry-run")
  let repo = match @sys.getenv("GH_REPO") {
    Some(r) if r.length() > 0 => r
    _ =>
      match @sys.getenv("GITHUB_REPOSITORY") {
        Some(r) => r
        None => {
          @sys.eprintln("chk cache-prune: GH_REPO=owner/name")
          return 2
        }
      }
  }
  // A failed or incomplete branch listing must never make live branches look deleted.
  let default_head = match gh_lines("api repos/\{repo} -q .default_branch") {
    Some(l) if l.length() == 1 => "refs/heads/" + l[0]
    _ => {
      @sys.eprintln("chk cache-prune: the default branch (gh api) failed")
      return 1
    }
  }
  let branch_names = match gh_lines("api --paginate 'repos/\{repo}/branches?per_page=100' -q '.[].name'") {
    Some(l) => l
    None => {
      @sys.eprintln("chk cache-prune: the branches' list (gh api) failed")
      return 1
    }
  }
  let heads : Map[String, Bool] = Map([])
  for name in branch_names {
    heads["refs/heads/" + name] = true
  }
  if !heads.contains(default_head) {
    @sys.eprintln("chk cache-prune: the branches' list has no default branch")
    return 1
  }
  let now = match @sys.run_out("date -u +%s") {
    Some(s) if is_digits(trim(s)) => num_of(trim(s))
    _ => {
      @sys.eprintln("chk cache-prune: the current time is unavailable")
      return 1
    }
  }
  let lines = match
    gh_lines(
      "api --paginate 'repos/\{repo}/actions/caches?per_page=100' -q '.actions_caches[]|[.id,.key,.ref,.size_in_bytes,.created_at,.last_accessed_at]|@tsv'",
    ) {
    Some(l) => l
    None => {
      @sys.eprintln("chk cache-prune: the caches' list (gh api) failed")
      return 1
    }
  }
  let caches : Array[Cache] = []
  let mut total = 0L
  for l in lines {
    let f = l.split("\t").map(fn(p) { p.to_owned() }).to_array()
    if f.length() != 6 {
      @sys.eprintln("chk cache-prune: incomplete cache record; nothing deleted")
      return 1
    }
    let size = match cache_size(f[3]) {
      Some(n) if n <= 9223372036854775807L - total => n
      _ => {
        @sys.eprintln("chk cache-prune: invalid cache record; nothing deleted")
        return 1
      }
    }
    if !is_digits(f[0]) || f[1] == "" || f[2] == "" {
      // The id is interpolated into a shell command; never pass untrusted non-digits to it.
      @sys.eprintln("chk cache-prune: invalid cache record; nothing deleted")
      return 1
    }
    let created = iso_s(f[4])
    let accessed = iso_s(f[5])
    if created <= 0.0 || accessed <= 0.0 {
      // Bad times also poison sorting and Gradle's shared cutoffs. Do not make any deletion decision from this list.
      @sys.eprintln("chk cache-prune: invalid cache time; nothing deleted")
      return 1
    }
    caches.push({
      id: f[0],
      key: f[1],
      ref_: f[2],
      size,
      created,
      accessed,
    })
    total += size
  }
  caches.sort_by(fn(a, b) { b.created.compare(a.created) })
  // the homes kept (each job's newest) on each ref, and the earliest of their last reads: a part one of them names is
  // read with it, so read since then (less a while); each kind of part's last read too, for a ref with no home
  let homes_read : Map[String, Double] = Map([])
  let home_seen : Map[String, Bool] = Map([])
  let last_read : Map[String, Double] = Map([])
  for c in caches {
    if is_gradle_part(c.key) {
      let s = part_slot(c)
      if last_read.get(s).unwrap_or(0.0) < c.accessed {
        last_read[s] = c.accessed
      }
    } else if c.key.has_prefix("gradle-home-") {
      let slot = kind_of(c.key).unwrap_or(c.key) + "\n" + c.ref_
      if !home_seen.contains(slot) {
        home_seen[slot] = true
        match homes_read.get(c.ref_) {
          Some(t) if t <= c.accessed => ()
          _ => homes_read[c.ref_] = c.accessed
        }
      }
    }
  }
  let newest : Map[String, Bool] = Map([])
  let missing_heads : Map[String, Bool] = Map([])
  let gone : Array[Cache] = []
  for c in caches {
    if deleted_head_cache(c, heads, now) {
      let missing = match missing_heads.get(c.ref_) {
        Some(m) => m
        None =>
          match head_missing(repo, c.ref_) {
            Some(m) => {
              missing_heads[c.ref_] = m
              m
            }
            None => {
              @sys.eprintln("chk cache-prune: could not confirm branch \{c.ref_}")
              return 1
            }
          }
      }
      if missing {
        gone.push(c)
        continue
      }
    }
    if is_gradle_part(c.key) {
      let since = match homes_read.get(c.ref_) {
        Some(t) => t
        None => last_read.get(part_slot(c)).unwrap_or(c.accessed)
      }
      if since - c.accessed > stale_parts_s {
        gone.push(c)
      }
      continue
    }
    match kind_of(c.key) {
      Some(k) => {
        let slot = k + "\n" + c.ref_
        // (one under a megabyte left: it frees nothing, and some small ones are markers looked up by their exact
        // key, mbui-android-refs-same-<inputs>)
        if newest.contains(slot) {
          if c.size >= 1000000L {
            gone.push(c)
          }
        } else {
          newest[slot] = true
        }
      }
      None => ()
    }
  }
  let mut freed = 0L
  for c in gone {
    say(
      "\{if dry { "would delete" } else { "delete" }} \{c.key} (\{c.ref_}, \{c.size / 1000000L} MB)",
    )
    if !dry {
      let r = @sys.run_out(
        "gh api -X DELETE repos/\{repo}/actions/caches/\{c.id} 2>&1; echo \"exit=$?\"",
      ).unwrap_or("exit=1")
      // (gone already, between the list and here: GitHub's own eviction, run 39606378560; or a 5xx for a delete
      // that was done all the same, run 39620407496: what decides is whether it is still there)
      if !r.contains("exit=0") && !r.contains("HTTP 404") && still_there(repo, c) {
        @sys.eprintln("chk cache-prune: deleting \{c.key}: \{trim(r)}")
        return 1
      }
    }
    freed += c.size
  }
  say(
    "\{gone.length()} of \{caches.length()} caches, \{freed / 1000000L} MB of \{total / 1000000L} MB",
  )
  0
}

///|
/// A part's kind (gradle-transforms-v1, …) and ref
fn part_slot(c : Cache) -> String {
  let parts = c.key.split("-").map(fn(p) { p.to_owned() }).to_array()
  parts[0:parts.length() - 1].join("-") + "\n" + c.ref_
}
