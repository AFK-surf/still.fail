// What the page shows of the code: each state's own lines, cut from stories.mbt as it is (so what is shown is what
// runs), and each part's functions as the library declares them (their comments and their parameters), cut from its
// files. All of it from sources.txt (scripts/kit-web.sh: each file after a line `//@@ <path>`), read once.

///|
/// The files sources.txt holds, by their path under apps/mbui/src ("" none).
let files : Ref[Map[String, Array[String]]?] = Ref(None)

///|
fn sources() -> Map[String, Array[String]] {
  match files.val {
    Some(m) => m
    None => {
      let m : Map[String, Array[String]] = Map([])
      let text = @utf8.decode_lossy(carried("sources.txt")[:])
      let mut path = ""
      let mut lines : Array[String] = []
      for l in text.split("\n") {
        let line = l.to_owned()
        if line.has_prefix("//@@ ") {
          if path != "" {
            m[path] = lines
          }
          path = line.unsafe_substring(start=5, end=line.length())
          lines = []
        } else {
          lines.push(line)
        }
      }
      if path != "" {
        m[path] = lines
      }
      files.val = Some(m)
      m
    }
  }
}

///|
/// How many spaces a line starts with.
fn indent(line : String) -> Int {
  let mut n = 0
  for c in line {
    if c != ' ' {
      break
    }
    n += 1
  }
  n
}

///|
/// `lines` with the spaces all of them start with taken off, and the empty ones at either end left out.
fn dedent(lines : Array[String]) -> String {
  let kept = lines.filter(fn(l) { l.trim(chars=" ").length() > 0 })
  let least = kept.fold(init=1000, fn(m, l) { if indent(l) < m { indent(l) } else { m } })
  lines
  .map(fn(l) { if l.length() >= least { l.unsafe_substring(start=least, end=l.length()) } else { l.trim(chars=" ").to_owned() } })
  .join("\n")
  .trim(chars="\n")
  .to_owned()
}

///|
/// The lines that make the state `label` says in stories.mbt: the body of the `fn(card) { … }` after its label
/// ("" where stories.mbt did not come with the page).
fn case_code(label : String) -> String {
  guard sources().get("sfstories/stories.mbt") is Some(lines) else { return "" }
  let said = "\"" + label + "\""
  guard lines.search_by(fn(l) { l.contains(said) }) is Some(at) else { return "" }
  let head = "fn(card) {"
  for i in at..<(if lines.length() < at + 3 { lines.length() } else { at + 3 }) {
    let line = lines[i]
    guard line.find(head) is Some(h) else { continue }
    let after = line.unsafe_substring(start=h + head.length(), end=line.length())
    match after.rev_find("}") {
      // (all of it on its line)
      Some(end) if after.trim(chars=" ").length() > 0 =>
        return after.unsafe_substring(start=0, end=end).trim(chars=" ").to_owned()
      _ => ()
    }
    let level = indent(line)
    let body = []
    for j in (i + 1)..<lines.length() {
      let l = lines[j]
      if indent(l) == level && l.trim(chars=" ").has_prefix("}") {
        break
      }
      body.push(l)
    }
    return dedent(body)
  }
  ""
}

///|
/// Function `name` of the library as file `file` declares it: its comment, then its signature without the caller's
/// place it is given (`loc~`) ("" where the file did not come with the page or has no such function).
fn api_of(file : String, name : String) -> String {
  guard sources().get("sf/" + file) is Some(lines) else { return "" }
  guard lines.search_by(fn(l) { l.has_prefix("pub fn " + name + "(") || (l.has_prefix("pub fn[") && l.contains("] " + name + "(")) }) is Some(at) else {
    return ""
  }
  let doc = []
  let mut i = at - 1
  while i >= 0 && (lines[i].has_prefix("///") || lines[i].has_prefix("#")) {
    let l = lines[i]
    if l.has_prefix("/// ") {
      doc.insert(0, "// " + l.unsafe_substring(start=4, end=l.length()))
    }
    i -= 1
  }
  let sig = []
  for j in at..<lines.length() {
    let l = lines[j]
    if !l.contains("loc~ : SourceLoc") {
      sig.push(if l.has_suffix(" {") { l.unsafe_substring(start=0, end=l.length() - 2) } else { l })
    }
    if l.has_suffix("{") {
      break
    }
  }
  (doc + sig).join("\n")
}
