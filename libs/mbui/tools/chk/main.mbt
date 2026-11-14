// mbui's small checks and filters (scripts/chk COMMAND …):
//
//     chk errs                    moon's output (--output-json) on stdin: its errors, `path:loc: message`, 40 at most,
//                                 and their count; exit 1 when there is one
//     chk corner-sl [--check]     the renderers' corners from one copy (src/host/corner.sl, src/ui/smooth.mbt's in the
//                                 shaders' words): src/host/corner_sl.h (MB_CORNER_SL, a C string the Metal, Direct3D
//                                 and Android GL shaders take in) and web/host.js's lines between its "corner.sl"
//                                 marks written; --check says which of them is not what corner.sl makes, and fails
//     chk outside-kinds [HOST…]   the outsides' kinds as src/ui/hostcall.mbt numbers them and as each host does
//                                 (outside.mbt says how)
//     chk textrec …               a host's run kept as a Tester's test, the kept runs' list checked (textrec.mbt)
//     chk logwait …               waits for a log's line, a process's end, a path's going (logwait.mbt)
//     chk lines PNG               a renderer's lines drawn as they are (pictures.mbt)
//     chk shapes PNG              a renderer's shapes drawn as they are (pictures.mbt)
//     chk contained PNG           contained glass keeps edge detail and excludes rounded-corner surroundings
//     chk views-round LOG PNG     Android's round page and tall page pictured (pictures.mbt)
//     chk views LOG HOST          a native view put where it was told (contracts.mbt)
//     chk site LOG HOST           a site's page and a page speaking with the app, step by step (contracts.mbt)
//     chk cache-prune [--dry-run] the Actions caches a newer one of the same kind replaced, deleted (cache_prune.mbt)

///|
fn root() -> String {
  match @sys.getenv("CHK_HOME") {
    Some(h) => @sys.join(h, "..")
    None => "."
  }
}

///|
fn say(s : String) -> Unit {
  @sys.println_out(s)
}

///|
fn trim(s : String) -> String {
  s.trim(chars=" \t\r\n\u{b}\u{c}").to_owned()
}

///|
fn errs() -> Int {
  let mut n = 0
  for line in @sys.read_stdin().split("\n") {
    let line = trim(line.to_owned())
    if !line.has_prefix("{") {
      if line.contains("rror") {
        say(line)
      }
      // moon's own failures (parse errors in human form, a failed link)
      if line.has_prefix("Error: failed to run") {
        n += 1
      }
      continue
    }
    let d = @rjson.parse(line) catch { _ => continue }
    if d.get("level").bind(fn(v) { v.str() }) != Some("error") {
      continue
    }
    n += 1
    if n > 40 {
      continue
    }
    let path = d.get("path").bind(fn(v) { v.str() }).unwrap_or("")
    let parts = path.split("/src/").to_array()
    let p = parts[parts.length() - 1].to_owned()
    say("\{p}:\{shown(d.get("loc"))}: \{shown(d.get("message"))}")
  }
  say("errors: \{n}")
  if n > 0 {
    1
  } else {
    0
  }
}

///|
/// A value as Python's print shows it: a string as it is
fn shown(v : @rjson.Value?) -> String {
  match v {
    Some(Str(s)) => s
    Some(Num(s)) => s
    Some(x) => @rjson.dumps(x)
    None => "None"
  }
}

///|
fn main {
  let argv = @env.args()
  let args = argv[1:].to_owned()
  let code = match args {
    ["errs", ..] => errs()
    ["corner-sl", .. rest] => corner_sl(rest.to_owned())
    ["outside-kinds", .. rest] => outside_kinds(rest.to_owned())
    ["textrec", .. rest] => textrec(rest.to_owned())
    ["logwait", .. rest] => logwait(rest.to_owned())
    ["lines", .. rest] => lines(rest.to_owned())
    ["shapes", .. rest] => shapes(rest.to_owned())
    ["contained", .. rest] => contained(rest.to_owned())
    ["views-round", .. rest] => views_round(rest.to_owned())
    ["views", .. rest] => views(rest.to_owned())
    ["images", .. rest] => images(rest.to_owned())
    ["site", .. rest] => site(rest.to_owned())
    ["cache-prune", .. rest] => cache_prune(rest.to_owned())
    _ => {
      @sys.eprintln("chk: errs | corner-sl [--check] | outside-kinds [HOST…]")
      2
    }
  }
  @sys.exit(code)
}
