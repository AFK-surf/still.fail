// mbc's commands (mbc.mbt says what each does), and one more:
//
//     mbc csplit IN.c OUTDIR [--json MANIFEST]   split IN.c into OUTDIR's units (csplit.mbt); files whose text did
//                                                not change keep their mtime, .c/.h files no longer made are removed

///|
fn json_str(buf : @buffer.Buffer, s : BytesView) -> Unit {
  buf.write_byte(b'"')
  for i in 0..<s.length() {
    let c = s[i]
    if c == b'"' || c == b'\\' {
      buf.write_byte(b'\\')
      buf.write_byte(c)
    } else if c < b' ' {
      let hex = b"0123456789abcdef"
      buf.write_bytes(b"\\u00")
      buf.write_byte(hex[c.to_int() >> 4])
      buf.write_byte(hex[c.to_int() & 15])
    } else {
      buf.write_byte(c)
    }
  }
  buf.write_byte(b'"')
}

///|
/// The split's numbers as JSON (--json)
fn manifest_json(s : Split) -> Bytes {
  let buf = @buffer.new()
  buf.write_bytes(b"{\"units\": {")
  for i, f in s.files {
    if i > 0 {
      buf.write_bytes(b", ")
    }
    json_str(buf, f.0)
    buf.write_bytes(b": ")
    buf.write_bytes(bint(f.1))
  }
  buf.write_bytes(b"}, \"functions\": ")
  buf.write_bytes(bint(s.functions))
  buf.write_bytes(b", \"globals\": ")
  buf.write_bytes(bint(s.globals))
  buf.write_bytes(b", \"stats\": {")
  for i, x in s.stats {
    if i > 0 {
      buf.write_bytes(b", ")
    }
    json_str(buf, utf8(x.0))
    buf.write_bytes(b": ")
    buf.write_bytes(bint(x.1))
  }
  buf.write_bytes(b"}, \"init_bytes\": ")
  buf.write_bytes(bint(s.init_bytes))
  buf.write_bytes(b", \"unit_loads\": [")
  for i, l in s.unit_loads {
    if i > 0 {
      buf.write_bytes(b", ")
    }
    buf.write_bytes(bint(l))
  }
  buf.write_bytes(b"], \"largest_function\": ")
  json_str(buf, s.largest_function)
  buf.write_bytes(b", \"made_global\": [")
  for i, n in s.made_global {
    if i > 0 {
      buf.write_bytes(b", ")
    }
    json_str(buf, n)
  }
  buf.write_bytes(b"]}")
  buf.to_bytes()
}

///|
/// Writes `data` to `path` unless it holds that already (its mtime kept then): true when written
fn write_if_changed(path : Bytes, data : Bytes) -> Bool {
  match read_file(path) {
    Some(old) if old == data => return false
    _ => ()
  }
  let tmp = cat([path, b".tmp"])
  if !write_file(tmp, data) || c_rename(tmp, path) == 0 {
    die("cannot write \{str(path)}")
  }
  true
}

///|
fn die(msg : String) -> Unit {
  eprint("mbc: " + msg)
  c_exit(2)
  panic()
}

///|
fn join_path(dir : Bytes, name : Bytes) -> Bytes {
  cat([dir, b"/", name])
}

///|
fn cmd_csplit(args : Array[String]) -> Unit {
  let pos = []
  let mut json : String? = None
  let mut i = 0
  while i < args.length() {
    let a = args[i]
    if a == "--json" && i + 1 < args.length() {
      json = Some(args[i + 1])
      i += 2
    } else if a == "-n" && i + 1 < args.length() {
      i += 2 // (the stable split's units are its own)
    } else {
      pos.push(a)
      i += 1
    }
  }
  if pos.length() != 2 {
    die("usage: mbc csplit IN.c OUTDIR [--json MANIFEST]")
    return
  }
  let src_path = utf8(pos[0])
  let outdir = utf8(pos[1])
  let src = match read_file(src_path) {
    Some(s) => s
    None => {
      die("cannot read \{pos[0]}")
      return
    }
  }
  let s = try split(src, outdir) catch {
    SplitError(e) => {
      eprint("csplit: \{pos[0]}: \{e}")
      c_exit(2)
      return
    }
  }
  let keep = BSet::new()
  for f in s.files {
    keep.add(f.0)
  }
  for old in list_dir(outdir) {
    if (ends(old, b".c") || ends(old, b".h")) && !keep.has(old) {
      let _ = c_remove(join_path(outdir, old))
    }
  }
  let changed = s.changed
  tick("written")
  match json {
    Some(j) => if !write_file(utf8(j), manifest_json(s)) { die("cannot write \{j}") }
    None => ()
  }
  let mut ntypes = 0
  let mut nprotos = 0
  let mut npp = 0
  for x in s.stats {
    if x.0 == "types" {
      ntypes = x.1
    } else if x.0 == "protos" {
      nprotos = x.1
    } else if x.0 == "pp" {
      npp = x.1
    }
  }
  let mut lo = 0
  let mut hi = 0
  for k, l in s.unit_loads {
    if k == 0 || l < lo {
      lo = l
    }
    if k == 0 || l > hi {
      hi = l
    }
  }
  eprint(
    "csplit: \{s.functions} functions, \{s.globals} globals, \{ntypes} types, \{nprotos} prototypes, \{npp} directives -> \{s.files.length() - 2} units (functions \{lo / 1024}-\{hi / 1024} KB each, moonbit_init \{s.init_bytes / 1024} KB, decls.h \{s.files[0].1 / 1024} KB); \{changed} changed",
  )
}

///|
fn main {
  let args = @env.args()
  if args.length() < 2 {
    die("usage: mbc csplit IN.c OUTDIR [--json MANIFEST]")
    return
  }
  let rest = args[2:].to_array()
  // (this program, by an absolute path: the shim runs it, and a split made by another build of it is not taken)
  let me = utf8(args[0])
  self_exe.val = if me.iter().any(fn(c) { is_sep(c) }) {
    abspath(me)
  } else {
    match which(me) {
      Some(p) => abspath(p)
      None => me
    }
  }
  match args[1] {
    "csplit" => cmd_csplit(rest)
    "gen" => cmd_gen(rest)
    "compile" => cmd_compile(rest)
    "wrap" => cmd_wrap(rest)
    "link" => cmd_link(rest)
    "shim" => cmd_shim(rest)
    "check" => cmd_check(rest)
    "work" => cmd_work(rest)
    "mirror" => cmd_mirror(rest)
    other => die("no command \{other}")
  }
}

///|
fn job_count() -> Int {
  match getenv("CSPLIT_JOBS") {
    Some(v) => imax(1, parse_int(strip(v)))
    None => imin(c_cpu_count(), 8)
  }
}

///|
/// work(i) for i in 0..<n, in processes of their own (forked: each sees this one's state as it is), the results in
/// order; the jobs given out largest first (size(i)) to the process with the least so far. CSPLIT_JOBS=1, or no
/// fork (Windows): here.
fn run_jobs(
  n : Int,
  outdir : Bytes,
  size : (Int) -> Int,
  work : (Int) -> (Int, Int, Int),
) -> Array[(Int, Int, Int)] {
  let out = Array::make(n, (0, 0, 0))
  let jobs = imin(job_count(), n)
  if jobs <= 1 {
    for i in 0..<n {
      out[i] = work(i)
    }
    return out
  }
  let order = stable_sort(Array::makei(n, fn(i) { i }), fn(a, b) {
    size(b) - size(a)
  })
  let load = Array::make(jobs, 0)
  let mine : Array[Array[Int]] = Array::makei(jobs, fn(_) { [] })
  for i in order {
    let mut w = 0
    for k in 1..<jobs {
      if load[k] < load[w] {
        w = k
      }
    }
    load[w] = load[w] + size(i)
    mine[w].push(i)
  }
  let result_path = fn(k : Int) {
    join_path(outdir, cat([b".mbc-job-", bint(k)]))
  }
  let mut forked = 0
  for k in 0..<jobs {
    let pid = c_fork()
    if pid < 0 {
      break
    }
    if pid == 0 {
      let buf = @buffer.new()
      for i in mine[k] {
        let r = work(i)
        buf.write_bytes(
          utf8("\{i} \{r.0} \{r.1} \{r.2}\n"),
        )
      }
      c_child_exit(if write_file(result_path(k), buf.to_bytes()) { 0 } else { 1 })
    }
    forked += 1
  }
  if c_wait_all() != 0 {
    die("a job failed")
  }
  for k in 0..<forked {
    let p = result_path(k)
    let data = match read_file(p) {
      Some(d) => d
      None => {
        die("no results from job \{k}")
        return out
      }
    }
    let _ = c_remove(p)
    let mut s = 0
    for e in 0..<data.length() {
      if data[e] == b'\n' {
        let nums = []
        let mut a = s
        for q in s..=e {
          if q == e || data[q] == b' ' {
            nums.push(parse_int(data[a:q]))
            a = q + 1
          }
        }
        out[nums[0]] = (nums[1], nums[2], nums[3])
        s = e + 1
      }
    }
  }
  // (the jobs of a process that could not be made, here)
  for k in forked..<jobs {
    for i in mine[k] {
      out[i] = work(i)
    }
  }
  out
}
