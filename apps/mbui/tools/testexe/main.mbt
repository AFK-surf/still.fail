// A run of a package's tests (scripts/test.sh's: its files, or a file and `--index FROM-TO`) on its test program built
// already (check-mbui's app-build job's sfapp program, the replay job's own flows program), not through moon test:
// moon, finding the sources of a fresh checkout newer than what it built, compiles every package again (28 s on
// Studio for nothing). The program is asked as moon asks it (the native test driver's argument: file:from-to, joined
// by /), and says each test's start and result between its markers. scripts/test.sh runs the programs (xargs -P, each
// taking the next part when done with one: dealt out beforehand, by name round four, one took 75 s while another took
// 21 on CI's four cores, 2026-11-01); this says what to run and what they said.
//
//   testexe parts INFO JOBS FILE… | FILE --index FROM-TO
//       the driver's arguments, a line each ("K ARG"): a file each when JOBS > 1 and there are files, else one
//   testexe said INFO DIR PKG
//       what the programs said (DIR/parts as parts wrote it, DIR/K.out, DIR/K.code: "EXIT SECONDS"), as moon says
//       it: their own output, each failure, then "Total tests: N, passed: P, failed: F."; exits 1 on a failure. A test
//       that ended its program (an abort) is said by name, and every test asked of it that said no result is failed.
//
// INFO: the program's tests' list moon wrote beside it (__whitebox_test_info.json, __blackbox_test_info.json).

///|
fn fail(why : String) -> Unit {
  @sys.eprintln("testexe: " + why)
  @sys.exit(2)
}

///|
fn parse_int(s : String) -> Int {
  let mut n = 0
  if s == "" {
    return -1
  }
  for c in s {
    if c < '0' || c > '9' {
      return -1
    }
    n = n * 10 + (c.to_int() - '0'.to_int())
  }
  n
}

///|
/// The tests' names by file and index, from INFO.
fn tests_of(info : String) -> Map[String, Array[String]] {
  let text = match @sys.read_text(info) {
    Some(t) => t
    None => {
      fail("no \{info}")
      ""
    }
  }
  let j = @json.parse(text) catch {
    _ => {
      fail("\{info} is not JSON")
      Json::null()
    }
  }
  let all : Map[String, Array[String]] = {}
  match j {
    Object(m) =>
      match m.get("tests") {
        Some(Object(files)) =>
          for f, ts in files {
            let names : Array[String] = []
            if ts is Array(list) {
              for t in list {
                if t is Object(o) {
                  let i = match o.get("index") {
                    Some(Number(n, ..)) => n.to_int()
                    _ => names.length()
                  }
                  while names.length() <= i {
                    names.push("?")
                  }
                  if o.get("name") is Some(String(s)) {
                    names[i] = s
                  }
                }
              }
            }
            all[f] = names
          }
        _ => fail("\{info} has no tests")
      }
    _ => fail("\{info} is not an object")
  }
  all
}

///|
fn base(p : String) -> String {
  @sys.basename(p)
}

///|
/// A driver argument back as its (file, from, to) parts.
fn parts_of(arg : String) -> Array[(String, Int, Int)] {
  let out : Array[(String, Int, Int)] = []
  for p in arg.split("/") {
    let p = p.to_string()
    match p.rev_find(":") {
      Some(c) => {
        let f = p.view(end_offset=c).to_string()
        let r = p.view(start_offset=c + 1).to_string()
        match r.find("-") {
          Some(d) =>
            out.push(
              (
                f,
                parse_int(r.view(end_offset=d).to_string()),
                parse_int(r.view(start_offset=d + 1).to_string()),
              ),
            )
          None => fail("not file:from-to: \{p}")
        }
      }
      None => fail("not file:from-to: \{p}")
    }
  }
  out
}

///|
fn arg_of(parts : Array[(String, Int, Int)]) -> String {
  parts.map(fn(x) { "\{x.0}:\{x.1}-\{x.2}" }).join("/")
}

///|
fn cmd_parts(args : Array[String]) -> Unit {
  if args.length() < 2 {
    fail("parts INFO JOBS FILE… | FILE --index FROM-TO")
  }
  let tests = tests_of(args[0])
  let jobs = parse_int(args[1])
  let rest = args[2:].to_array()
  let asked : Array[(String, Int, Int)] = []
  if rest.length() == 3 && rest[1] == "--index" {
    let r = parts_of("x:" + rest[2])
    asked.push((base(rest[0]), r[0].1, r[0].2))
  } else {
    for p in rest {
      let f = base(p)
      let n = match tests.get(f) {
        Some(ts) => ts.length()
        None => 0
      }
      if n > 0 {
        asked.push((f, 0, n))
      }
    }
  }
  if asked.is_empty() {
    return
  }
  if jobs > 1 {
    for k, x in asked {
      @sys.println_out("\{k} \{arg_of([x])}")
    }
  } else {
    @sys.println_out("0 \{arg_of(asked)}")
  }
}

///|
let begin_mark = "----- BEGIN MOON TEST RESULT -----"

///|
let end_mark = "----- END MOON TEST RESULT -----"

///|
fn cmd_said(args : Array[String]) -> Unit {
  if args.length() != 3 {
    fail("said INFO DIR PKG")
  }
  let tests = tests_of(args[0])
  let dir = args[1]
  let pkg = args[2]
  let name = fn(f : String, i : Int) {
    match tests.get(f) {
      Some(ts) if i >= 0 && i < ts.length() => ts[i]
      _ => "?"
    }
  }
  let lines = @sys.read_text(@sys.join(dir, "parts")).unwrap_or("")
  let failed : Array[String] = []
  let times : Array[(String, Int)] = []
  let mut total = 0
  let mut skipped = 0
  for line in lines.split("\n") {
    let line = line.to_string()
    if line == "" {
      continue
    }
    let (k, arg) = match line.find(" ") {
      Some(s) => (line.view(end_offset=s).to_string(), line.view(start_offset=s + 1).to_string())
      None => {
        fail("not K ARG: \{line}")
        ("", "")
      }
    }
    let parts = parts_of(arg)
    let said = @sys.read_text(@sys.join(dir, k + ".out")).unwrap_or("")
    let code_line = @sys.read_text(@sys.join(dir, k + ".code")).unwrap_or("127 0").trim(chars=" \t\r\n").to_string()
    let words = code_line.split(" ").map(fn(w) { w.to_string() }).to_array()
    let code = parse_int(words[0])
    let secs = if words.length() > 1 { parse_int(words[1]) } else { 0 }
    times.push((parts[0].0, secs))
    // their markers' results, and what else they printed (passed through, as moon does)
    let done : Map[String, String] = {}
    let mut started = ""
    let rest = StringBuilder::new()
    let mut in_mark = false
    for l in said.split("\n") {
      let l = l.to_string()
      if in_mark {
        if l == end_mark {
          in_mark = false
          continue
        }
        let j = @json.parse(l) catch { _ => Json::null() }
        if j is Object(o) {
          let key = match (o.get("file"), o.get("index")) {
            (Some(String(f)), Some(Number(n, ..))) => "\{f}:\{n.to_int()}"
            _ => ""
          }
          match o.get("type") {
            Some(String("start")) => started = key
            Some(String("result")) =>
              done[key] = match o.get("message") {
                Some(String(m)) => m
                _ => ""
              }
            _ => ()
          }
        }
        continue
      }
      if l.has_suffix(begin_mark) {
        in_mark = true
        let head = l.view(end_offset=l.length() - begin_mark.length()).to_string()
        if head != "" {
          rest.write_string(head + "\n")
        }
        continue
      }
      rest.write_string(l + "\n")
    }
    let text = rest.to_string().trim(chars=" \t\r\n").to_string()
    if text != "" {
      @sys.println_out(text)
    }
    for x in parts {
      let (f, a, b) = x
      for i = a; i < b; i = i + 1 {
        let key = "\{f}:\{i}"
        total = total + 1
        match done.get(key) {
          None => {
            let why = if key == started {
              "the program ended in it"
            } else {
              "not run: the program ended before it"
            }
            failed.push("[\{pkg}] test \{key} (\{name(f, i)}) failed: \{why} (exit \{code})")
          }
          Some("skipped test") => skipped = skipped + 1
          Some("") => ()
          Some(m) => failed.push("[\{pkg}] test \{key} (\{name(f, i)}) failed: \{m}")
        }
      }
    }
  }
  if times.length() > 1 {
    times.sort_by(fn(a, b) { b.1 - a.1 })
    let top = times[0:@cmp.minimum(5, times.length())].to_array()
    @sys.println_out("testexe: the slowest files: " + top.map(fn(t) { "\{t.0} \{t.1} s" }).join(", "))
  }
  for f in failed {
    @sys.println_out(f)
  }
  let n = total - skipped
  @sys.println_out("Total tests: \{n}, passed: \{n - failed.length()}, failed: \{failed.length()}.")
  @sys.exit(if failed.is_empty() { 0 } else { 1 })
}

///|
fn main {
  let argv = @env.args()
  if argv.length() < 2 {
    fail("parts … | said …")
    return
  }
  let args = argv[2:].to_array()
  match argv[1] {
    "parts" => cmd_parts(args)
    "said" => cmd_said(args)
    w => fail("no command \{w}")
  }
}
