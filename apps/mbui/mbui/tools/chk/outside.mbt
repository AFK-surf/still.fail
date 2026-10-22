// The outsides' kinds as src/ui/hostcall.mbt numbers them (its outside_kinds) and as each host does.
//
// hostcall.mbt: every `let outside_NAME = N` in outside_kinds as ("NAME", outside_NAME), no number twice. Each host:
// every kind it names (Native.java's OUTSIDE_*, apple.h's / win.h's / android_host.c's MB_OUTSIDE_*, web/host.js's
// OUTSIDE_*) one of those, by the same number; a kind told as a bare number (tell(9, …)) is not one. Exit 1 on any.

///|
let hosts : Array[(String, Array[String])] = [
  (
    "android",
    [
      "android/app/src/main/java/dev/mbui/*.java", "src/host/android_host.c", "src/host/android_*.h",
    ],
  ),
  (
    "mac",
    ["src/host/apple.h", "src/host/apple_*.h", "src/host/apple_*.m", "src/host/mac_app.m"],
  ),
  (
    "ios",
    ["src/host/apple.h", "src/host/apple_*.h", "src/host/apple_*.m", "src/host/ios_app.m"],
  ),
  (
    "windows",
    ["src/host/win.h", "src/host/win_*.h", "src/host/win_*.c", "src/host/win_*.cpp"],
  ),
  ("web", ["web/host.js"]),
]

///|
fn rx(p : String, flags? : @re.Flags = @re.no_flags) -> @re.Regex {
  @re.Regex::new(p, flags~) catch {
    _ => panic()
  }
}

///|
/// a kind named: OUTSIDE_X = N or MB_OUTSIDE_X = N (in a list, an enum, a const)
let named_kind : @re.Regex = rx("\\b(?:MB_)?OUTSIDE_([A-Z]+)\\s*=\\s*(\\d+)")

///|
/// a kind told as a number: the host's ways of telling one
let bare_kind : @re.Regex = rx("\\b(?:mb_host_outside|Native\\.tell|outside_cb|tell|f)\\(\\s*\\d+\\s*,")

///|
let multi : @re.Flags = { ..@re.no_flags, multiline: true }

///|
fn kinds_table(r : String) -> (Map[String, Int], Array[String]) {
  let src = @sys.read_text(@sys.join(r, "src/ui/hostcall.mbt")).unwrap_or("")
  let lets : Map[String, Int] = Map::new()
  for m in rx("^let outside_([a-z]+) = (\\d+)$", flags=multi).find_all(src) {
    lets[m.get(1)] = parse_int(m.get(2))
  }
  let block = rx(
    "^fn outside_kinds\\(\\) -> Array\\[\\(String, Int\\)\\] \\{\\n  \\[(.*?)^  \\]",
    flags={ ..multi, dotall: true },
  ).search(src)
  let body = match block {
    Some(m) => m.get(1)
    None => return (lets, ["hostcall.mbt: no outside_kinds"])
  }
  let bad = []
  let names = []
  for m in rx("\\(\"([a-z]+)\", outside_([a-z]+)\\)").find_all(body) {
    let name = m.get(1)
    let ref_ = m.get(2)
    if name != ref_ {
      bad.push("hostcall.mbt: outside_kinds has (\"\{name}\", outside_\{ref_})")
    }
    names.push(name)
  }
  for n, _ in lets {
    if !names.contains(n) {
      bad.push("hostcall.mbt: outside_\{n} not in outside_kinds")
    }
  }
  let seen : Map[Int, String] = Map::new()
  for n, v in lets {
    match seen.get(v) {
      Some(o) => bad.push("hostcall.mbt: outside_\{o} and outside_\{n} both \{v}")
      None => ()
    }
    seen[v] = n
  }
  (lets, bad)
}

///|
fn parse_int(s : String) -> Int {
  let mut n = 0
  for ch in s {
    n = n * 10 + (ch.to_int() - '0'.to_int())
  }
  n
}

///|
fn line_at(t : Array[Char], at : Int) -> Int {
  let mut n = 1
  for i in 0..<at {
    if t[i] == '\n' {
      n += 1
    }
  }
  n
}

///|
fn host_bad(r : String, h : String, globs : Array[String], kinds : Map[String, Int]) -> Array[String] {
  let bad = []
  let files : Map[String, Unit] = Map::new()
  for g in globs {
    for p in @sys.glob(r, g) {
      files[p] = ()
    }
  }
  let rels = files.keys().collect()
  rels.sort_by(@rjson.str_cmp)
  for rel in rels {
    let src = @sys.read_text(@sys.join(r, rel)).unwrap_or("")
    let t = src.to_array()
    for m in named_kind.find_all(src) {
      let up = m.get(1)
      let name = up.to_lower()
      let n = parse_int(m.get(2))
      let line = line_at(t, m.start())
      match kinds.get(name) {
        None =>
          bad.push("\{h}: \{rel}:\{line}: OUTSIDE_\{up} is no kind of hostcall.mbt's")
        Some(k) =>
          if k != n {
            bad.push(
              "\{h}: \{rel}:\{line}: OUTSIDE_\{up} = \{n}, hostcall.mbt's outside_\{name} is \{k}",
            )
          }
      }
    }
    for m in bare_kind.find_all(src) {
      let line = line_at(t, m.start())
      let from = rfind_char(t, '\n', m.start()) + 1
      let before = chars(t, from, m.start())
      if before.contains("//") || trim(before).has_prefix("*") {
        continue // (said in a comment)
      }
      bad.push("\{h}: \{rel}:\{line}: a kind told as a number (\{m.get(0)}): name it")
    }
  }
  bad
}

///|
fn outside_kinds(args : Array[String]) -> Int {
  let r = root()
  let names = hosts.map(fn(h) { h.0 })
  let want = if args.length() > 0 { args } else { names }
  for h in want {
    if !names.contains(h) {
      @sys.eprintln("chk outside-kinds: no host \{h} (\{names.join(", ")})")
      return 1
    }
  }
  let (kinds, bad) = kinds_table(r)
  for h in want {
    for x in hosts {
      if x.0 == h {
        bad.append(host_bad(r, h, x.1, kinds))
      }
    }
  }
  for b in bad {
    say(b)
  }
  if bad.length() > 0 {
    return 1
  }
  say(
    "outside kinds: \{kinds.length()} in hostcall.mbt, each its own; \{want.join(", ")} the same",
  )
  0
}
