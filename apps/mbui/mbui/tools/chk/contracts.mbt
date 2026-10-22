// The hosts' contracts' checks of a run's log (scripts/host_contract.sh HOST views, site)

///|
/// A number as a log writes it: a sign, digits, a point and digits, an exponent; 0 for what is not one
fn num_of(s : String) -> Double {
  let cs = s.to_array()
  let mut i = 0
  let mut neg = false
  if i < cs.length() && (cs[i] == '-' || cs[i] == '+') {
    neg = cs[i] == '-'
    i += 1
  }
  let mut v = 0.0
  while i < cs.length() && cs[i] >= '0' && cs[i] <= '9' {
    v = v * 10.0 + (cs[i].to_int() - '0'.to_int()).to_double()
    i += 1
  }
  if i < cs.length() && cs[i] == '.' {
    i += 1
    let mut scale = 0.1
    while i < cs.length() && cs[i] >= '0' && cs[i] <= '9' {
      v = v + (cs[i].to_int() - '0'.to_int()).to_double() * scale
      scale = scale / 10.0
      i += 1
    }
  }
  if i < cs.length() && (cs[i] == 'e' || cs[i] == 'E') {
    i += 1
    let mut eneg = false
    if i < cs.length() && (cs[i] == '-' || cs[i] == '+') {
      eneg = cs[i] == '-'
      i += 1
    }
    let mut e = 0
    while i < cs.length() && cs[i] >= '0' && cs[i] <= '9' {
      e = e * 10 + (cs[i].to_int() - '0'.to_int())
      i += 1
    }
    v = v * @math.pow(10.0, (if eneg { -e } else { e }).to_double())
  }
  if neg {
    -v
  } else {
    v
  }
}

///|
/// Python's "%g": 6 significant digits, no trailing zeros
fn g6(x : Double) -> String {
  if x == 0.0 {
    return "0"
  }
  let e = @math.floor(@math.log10(x.abs())).to_int()
  if e < -4 || e >= 6 {
    return x.to_string()
  }
  let decimals = 5 - e
  let scale = @math.pow(10.0, decimals.to_double())
  let r = @math.round(x * scale) / scale
  let neg = r < 0.0
  let whole = @math.floor(r.abs())
  let mut frac = @math.round((r.abs() - whole) * scale).to_int64()
  let mut w = whole.to_int64()
  if frac.to_double() >= scale {
    w += 1L
    frac -= scale.to_int64()
  }
  let mut fs = if decimals > 0 {
    let f = frac.to_string()
    String::make(decimals - f.length(), '0') + f
  } else {
    ""
  }
  while fs.has_suffix("0") {
    fs = fs.view(end_offset=fs.length() - 1).to_string()
  }
  (if neg { "-" } else { "" }) + w.to_string() + (if fs == "" { "" } else { "." + fs })
}

///|
fn list_text(xs : Array[Double]) -> String {
  "[" + xs.map(fn(x) { x.to_string() }).join(", ") + "]"
}

///|
/// views: a native view placed between pixels (kitdemo's MBUI_VIEWCHECK): where the host put it (VIEWAT, in device
/// pixels) is where the app told it to (VIEWTOLD), on whole device pixels
fn views(args : Array[String]) -> Int {
  if args.length() != 2 {
    @sys.eprintln("chk views LOG HOST")
    return 2
  }
  let told : Map[String, Array[Double]] = Map::new()
  let at : Map[String, Array[Double]] = Map::new()
  for line in text_lines(@sys.read_text(args[0]).unwrap_or("")) {
    for kv in [("VIEWTOLD ", told), ("VIEWAT ", at)] {
      let (key, out) = kv
      match line.find(key) {
        Some(i) => {
          let p = split_ws(line.view(start_offset=i + key.length()).to_string())
          if p.length() > 0 {
            out[p[0]] = p[1:@cmp.minimum(10, p.length())].to_array().map(num_of)
          }
        }
        None => ()
      }
    }
  }
  let names = [
    "x", "y", "w", "h", "clip x0", "clip y0", "clip x1", "clip y1", "corners' radius",
  ]
  let bad = []
  if told.length() == 0 || at.length() == 0 {
    bad.push(
      "told \{told.length()}, placed \{at.length()}: the app or the host said nothing",
    )
  }
  for v, t in told {
    let a = match at.get(v) {
      Some(a) => a
      None => {
        bad.push("view \{v}: told \{list_text(t)}, the host said not where it put it")
        continue
      }
    }
    let n = @cmp.minimum(names.length(), @cmp.minimum(t.length(), a.length()))
    for k in 0..<n {
      let tv = t[k]
      let av = a[k]
      if k < 8 && (tv - @math.round(tv)).abs() > 1.0e-3 {
        bad.push("view \{v}: told \{names[k]} \{tv}, not on a device pixel")
      }
      if (tv - av).abs() > 1.0e-3 {
        bad.push("view \{v}: \{names[k]} told \{tv}, put at \{av}")
      }
    }
  }
  if bad.length() > 0 {
    say("views contract (\{args[1]}): " + bad.join("; "))
    return 1
  }
  let first = at.values().collect()[0]
  say(
    "views contract (\{args[1]}): \{told.length()} native view put where it was told, on whole device pixels: " +
    first.map(g6).join(" "),
  )
  0
}

///|
/// site: a site's page and a page speaking with the app (kitdemo's MBUI_SITECHECK), each step begun by what the page
/// said before it
fn site(args : Array[String]) -> Int {
  if args.length() != 2 {
    @sys.eprintln("chk site LOG HOST")
    return 2
  }
  let steps = []
  for l in text_lines(@sys.read_text(args[0]).unwrap_or("")) {
    match l.find("SITECHECK ") {
      Some(i) => steps.push(trim(l.view(start_offset=i + "SITECHECK ".length()).to_string()))
      None => ()
    }
  }
  let h = args[1]
  let bad = []
  let need = if steps.contains("no site view here") {
    // (the browser has no site view: its page alone is checked, by the same steps)
    ["page page-hello", "page page-pong two", "done"]
  } else {
    let need = [
      "said hello", "said pong one", "said event 1", "said event 2", "page page-hello", "page page-pong two",
      "done",
    ]
    if steps.contains("cookies kept") {
      // (a run's sites begin with no cookies, whatever the last run left)
      need.append(["said start cookie none", "said cookie k=v", "said fetched cookie-sent"])
    } else if !steps.iter().any(fn(s) { s.has_prefix("said fetched ") }) {
      bad.push("the page's own request was not answered")
    }
    let grabs = steps.filter(fn(s) { s.has_prefix("grab ") })
    let grabbed = grabs.length() > 0 &&
      {
        let ws = split_ws(grabs[0])
        ws.length() > 1 && num_of(ws[1]) > 0.0
      }
    if !grabbed {
      bad.push(
        "the page was not grabbed: " +
        (if grabs.length() > 0 { grabs[0] } else { "no grab" }),
      )
    }
    need
  }
  for n in need {
    if !steps.contains(n) {
      bad.push("missing: " + n)
    }
  }
  if bad.length() > 0 {
    say("site contract (\{h}): " + bad.join("; ") + " (steps: " + steps.join(" | ") + ")")
    return 1
  }
  say("site contract (\{h}): " + steps.join(" | "))
  0
}
