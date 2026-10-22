// chk cache-prune [--dry-run]: the Actions caches a newer one of the same kind has replaced, deleted (cache-prune.yml;
// GH_REPO=owner/name, gh logged in or GH_TOKEN with actions: write).
//
// A repository has 10 GB of caches; past that GitHub evicts the least recently used, and what went first were the
// caches read seldom that jobs cannot do without (WARP, the emulator's system images, MoonBit: "no WARP 1.0.21 in the
// Actions cache", runs 39536847651, 39731343052). A cache saved once per commit, run or content is keyed
// <kind>-<id>, the id a sha, a content's hash (16 hex digits or more) or a run's <id>-<attempt>; a restore by
// restore-keys takes the newest of a kind on its ref (then main's), so the older ones of a kind on a ref are never read
// again: kept is the newest of each kind on each ref, the rest deleted (one under a megabyte left: it frees nothing).
// (A list of the kinds by name, as .github/cache_prune.py had, missed each new one: on 2026-10-22 mbui-apk-<sha>,
// android-lint-main-<sha>, android-build-main-<sha> and the mbui-linux-store-… ones were 4 GB of the 22.)
// setup-gradle's parts of a Gradle home (gradle-transforms-v1-<hash>, gradle-dependencies-v1-…: by their content,
// each read as a home that names it is restored) are deleted when read 30 minutes or more before the last read of a
// part of their kind on their ref: the homes in use read theirs each run, the others are read no more (a day's were
// 6 GB on 2026-10-22, when the rule was a day since they were read; at worst a job's Gradle starts cold).

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
fn is_hex(s : String) -> Bool {
  s.length() > 0 &&
  s.iter().all(fn(c) { (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') })
}

///|
fn is_digits(s : String) -> Bool {
  s.length() > 0 && s.iter().all(fn(c) { c >= '0' && c <= '9' })
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
/// 2026-10-22T05:37:59.731503Z: seconds since 1970
fn iso_s(t : String) -> Double {
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
  if t.length() < 19 {
    return 0.0
  }
  let y0 = num(0, 4)
  let m = num(5, 7)
  let d = num(8, 10)
  // days from 1970-01-01 (Howard Hinnant's days_from_civil)
  let y = if m <= 2 { y0 - 1 } else { y0 }
  let era = (if y >= 0 { y } else { y - 399 }) / 400
  let yoe = y - era * 400
  let mp = if m > 2 { m - 3 } else { m + 9 }
  let doy = (153 * mp + 2) / 5 + d - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  let days = era * 146097 + doe - 719468
  days.to_double() * 86400.0 +
  (num(11, 13) * 3600 + num(14, 16) * 60 + num(17, 19)).to_double()
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
fn still_there(repo : String, c : Cache) -> Bool {
  match
    gh_lines(
      "api --paginate 'repos/\{repo}/actions/caches?per_page=100&ref=\{c.ref_}' -q '.actions_caches[].id'",
    ) {
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
  for l in lines {
    let f = l.split("\t").map(fn(p) { p.to_owned() }).to_array()
    if f.length() < 6 {
      continue
    }
    caches.push({
      id: f[0],
      key: f[1],
      ref_: f[2],
      size: num_of(f[3]).to_int64(),
      created: iso_s(f[4]),
      accessed: iso_s(f[5]),
    })
  }
  caches.sort_by(fn(a, b) { b.created.compare(a.created) })
  // each kind of part's last read on a ref: the parts a home in use names are read with it, each run
  let last_read : Map[String, Double] = Map([])
  for c in caches {
    if is_gradle_part(c.key) {
      let s = part_slot(c)
      if last_read.get(s).unwrap_or(0.0) < c.accessed {
        last_read[s] = c.accessed
      }
    }
  }
  let newest : Map[String, Bool] = Map([])
  let gone : Array[Cache] = []
  for c in caches {
    if is_gradle_part(c.key) {
      if last_read.get(part_slot(c)).unwrap_or(c.accessed) - c.accessed > stale_parts_s {
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
  let total = caches.fold(init=0L, fn(a, c) { a + c.size })
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
