// What a package's tests are run in, each a program of its own, where moon's test driver runs them all in one (wasm-gc,
// Wasm, JS: each test called in turn in one instance, nothing of it begun again between two tests, no hook there):
//
//     moon test --outline ARGS… > selected
//     chk tests-apart --files < selected                     the files of its tests
//     moon test --outline FILES… > whole; chk tests-apart whole < selected
//
// A test that aborts as it should (its name begins "panic") stops where it is, and what it had under way (a guard, a
// batch, a layout) is left to every test after it in that program: one that begins no run of its own (a bare Tree's)
// runs in it (mbui's view on wasm-gc, 2026-11-06: four of its tests after layout_box_sized_test's panic one failed
// there, and passed run without it). So each such test is run in a program of its own, alone; the tests of its file
// before and after it, each run of them between two of them, in a program of their own; and every file with none of
// them in one program, together. A file named stopped_… keeps its tests together in one program, panic ones too: it
// tests what a run stopped half way leaves to the next one in the same program (src/ui/stopped_run_test.mbt), so they
// run as they are written, in order, and only them.
//
// Only the tests selected are run (ARGS may select some of a file's, `-i`, `--filter`): what selected lists, each file
// read in whole's, its every test, to know which abort and whether all of it is selected (a file run by its path alone
// runs all of it). A file stopped_… selected in part runs each run of consecutive tests of it in a program.
//
// Run where the outline was made (a module's directory, or a workspace's: moon.work's members, each's moon.mod). Out: one
// line for each program, `COUNT<TAB>ARGS`: how many tests it runs, and what `moon test` runs them by (the files'
// paths, a package's under its module's source: mbui/view's under src/view; one file's tests by `-i FROM-TO`, TO not
// one of them). Exit 1 where selected lists no test; where a line of either is not a test's, numbered in turn (moon's
// outline is nothing else: what it says besides goes to stderr); where a test is of a package of no module here; where a
// file's tests are not in order in it, or one selected is not in whole's.

///|
priv struct Outlined {
  path : String
  index : Int
  panics : Bool
}

///|
/// A manifest's string value (`name = "mbui"`), None where it says none
fn said(text : String, key : String) -> String? {
  for line in text.split("\n") {
    let line = line.trim(chars=" \t\r").to_string()
    guard line.has_prefix(key) else { continue }
    let rest = line.unsafe_substring(start=key.length(), end=line.length()).trim(chars=" \t=").to_string()
    if rest.length() >= 2 && rest.has_prefix("\"") && rest.has_suffix("\"") {
      return Some(rest.unsafe_substring(start=1, end=rest.length() - 1))
    }
  }
  None
}

///|
/// The modules here, each (its name, where its packages are): moon.work's members, else this directory's own
fn modules_here() -> Array[(String, String)] {
  let members : Array[String] = []
  match @sys.read_text("moon.work") {
    Some(w) =>
      for line in w.split("\n") {
        let m = line.trim(chars=" \t\r,").to_string()
        if m.length() >= 2 && m.has_prefix("\"") && m.has_suffix("\"") {
          members.push(m.unsafe_substring(start=1, end=m.length() - 1))
        }
      }
    None => members.push(".")
  }
  let out : Array[(String, String)] = []
  for m in members {
    guard @sys.read_text(@sys.join(m, "moon.mod")) is Some(t) && said(t, "name") is Some(name) else { continue }
    let dir = match said(t, "source") {
      Some(s) => if m == "." { s } else { m + "/" + s }
      None => m
    }
    out.push((name, dir))
  }
  out
}

///|
/// The `n`th line of moon's outline (`  81. mbui/view stopped_run_test.mbt:6 index=0 name="panic: …"`), what it says;
/// Err where it is no test's, or not the `n`th, or a test of a package of none of `modules`
fn outlined(line : String, n : Int, modules : Array[(String, String)]) -> Result[Outlined, String] {
  let words = line.trim(chars=" \t\r").split(" ").filter(fn(w) { w != "" }).map(fn(w) { w.to_string() }).collect()
  guard words.length() >= 5 &&
    words[0] == "\{n}." &&
    words[3].has_prefix("index=") &&
    words[4].has_prefix("name=\"") else {
    return Err("line \{n} of the outline, not test \{n}'s: \{line}")
  }
  let pkg = words[1]
  // (the module whose name is the longest of those it begins with)
  let mut dir : String? = None
  let mut by = -1
  for m in modules {
    let (name, src) = m
    if name.length() > by {
      if pkg == name {
        dir = Some(src)
        by = name.length()
      } else if pkg.has_prefix(name + "/") {
        dir = Some(src + "/" + pkg.unsafe_substring(start=name.length() + 1, end=pkg.length()))
        by = name.length()
      }
    }
  }
  guard dir is Some(dir) else { return Err("\{pkg}: a package of no module here") }
  let file = match words[2].find(":") {
    Some(i) => words[2].unsafe_substring(start=0, end=i)
    None => words[2]
  }
  let digits = words[3].unsafe_substring(start=6, end=words[3].length())
  guard digits.length() > 0 && digits.iter().all(fn(c) { c >= '0' && c <= '9' }) else {
    return Err("\{line}: no index")
  }
  let index = digits.iter().fold(init=0, fn(n, c) { n * 10 + (c.to_int() - '0'.to_int()) })
  Ok({ path: dir + "/" + file, index, panics: words[4].has_prefix("name=\"panic") })
}

///|
/// An outline's tests, by file (the files in the order it says them first), each file's in the order of their index
fn tests_of(
  outline : String,
  modules : Array[(String, String)],
) -> Result[(Array[String], Map[String, Array[Outlined]]), String] {
  let files : Array[String] = []
  let of : Map[String, Array[Outlined]] = {}
  let mut n = 0
  for line in outline.split("\n") {
    let line = line.to_string()
    if line.trim(chars=" \t\r").is_empty() {
      continue
    }
    n += 1
    let t = match outlined(line, n, modules) {
      Ok(t) => t
      Err(e) => return Err(e)
    }
    match of.get(t.path) {
      Some(ts) => {
        if ts[ts.length() - 1].index >= t.index {
          return Err("\{t.path}: its test \{t.index} after \{ts[ts.length() - 1].index}")
        }
        ts.push(t)
      }
      None => {
        files.push(t.path)
        of[t.path] = [t]
      }
    }
  }
  Ok((files, of))
}

///|
/// The programs the tests `selected` lists are run in: (how many tests, `moon test`'s arguments); `whole`, the
/// outline of every test of their files
fn apart(
  selected : String,
  whole : String,
  modules : Array[(String, String)],
) -> Result[Array[(Int, String)], String] {
  let (files, of) = match tests_of(selected, modules) {
    Ok(t) => t
    Err(e) => return Err(e)
  }
  if files.is_empty() {
    return Err("no test in the outline")
  }
  let every = match tests_of(whole, modules) {
    Ok(t) => t.1
    Err(e) => return Err(e)
  }
  let together : Array[String] = []
  let mut together_n = 0
  let out : Array[(Int, String)] = []
  for path in files {
    let ts = of.get(path).unwrap()
    guard every.get(path) is Some(all) else { return Err("\{path}: none of its tests in the whole outline") }
    let aborts : Map[Int, Bool] = {}
    for t in all {
      aborts[t.index] = t.panics
    }
    for t in ts {
      guard aborts.get(t.index) is Some(_) else {
        return Err("\{path}: its test \{t.index}, not in the whole outline")
      }
    }
    let stopped = @sys.basename(path).has_prefix("stopped_")
    let n = ts.length()
    if n == all.length() && !all.iter().any(fn(t) { t.panics }) {
      together.push(path)
      together_n += n
    } else if n == all.length() && stopped {
      out.push((n, path))
    } else {
      // (each run of consecutive tests selected, none aborting (of a stopped_ file: any), in a program; each that aborts
      // alone)
      let mut from = -1
      let mut to = -1
      let ran = fn(from : Int, to : Int) {
        if from >= 0 {
          out.push((to - from, "\{path} -i \{from}-\{to}"))
        }
      }
      for t in ts {
        let alone = t.panics && !stopped
        if alone || t.index != to {
          ran(from, to)
          from = -1
        }
        if alone {
          out.push((1, "\{path} -i \{t.index}"))
        } else {
          if from < 0 {
            from = t.index
          }
          to = t.index + 1
        }
      }
      ran(from, to)
    }
  }
  if !together.is_empty() {
    out.insert(0, (together_n, together.join(" ")))
  }
  Ok(out)
}

///|
fn tests_apart(args : Array[String]) -> Int {
  let said = match args {
    ["--files"] =>
      match tests_of(@sys.read_stdin(), modules_here()) {
        Ok(([], _)) => Err("no test in the outline")
        Ok((files, _)) => Ok(files)
        Err(e) => Err(e)
      }
    [whole] =>
      match @sys.read_text(whole) {
        Some(w) =>
          match apart(@sys.read_stdin(), w, modules_here()) {
            Ok(programs) => Ok(programs.map(fn(p) { "\{p.0}\t\{p.1}" }))
            Err(e) => Err(e)
          }
        None => Err("\{whole}: not read")
      }
    _ => {
      @sys.eprintln("chk tests-apart --files | WHOLE (moon test --outline's on stdin, in the module's directory)")
      return 2
    }
  }
  match said {
    Ok(lines) => {
      for l in lines {
        say(l)
      }
      0
    }
    Err(e) => {
      @sys.eprintln("chk tests-apart: \{e}")
      1
    }
  }
}
