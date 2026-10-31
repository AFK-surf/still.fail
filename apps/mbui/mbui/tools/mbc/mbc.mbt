// mbc: the C step of every native build: the C that moonc generates, split (csplit.mbt) and compiled in parallel.
//
//     mbc gen [--dir MOD] [--debug] [--target-dir DIR] src/PKG
//         moon's build of PKG with stand-ins for its C compiler and archiver (scripts/mbc-stub.sh): only moonc runs.
//         Prints the generated .c; fails if moon did not write it anew. (Android, iOS: their compiler is not moon's.)
//     mbc compile --cc CC --cflags FLAGS [--gen-flags F] [--init-flags F] [--extra FILE…] [--optional FILE…]
//                 [--objc-flags F] --obj DIR [-j N] [--link-flags FILE] FILE.c
//         FILE.c split into units and compiled with the extra C/Objective-C files, all at once (-j, default the
//         cores); prints the objects. An object whose command and inputs (its depfile's, by content) did not change
//         is kept. --optional files that do not compile are left out (as the runtime's that a platform lacks).
//     mbc wrap --real CC -- ARGS…
//         A C compiler for moon itself (`mbc shim` puts one first on PATH): every command goes to CC as is, except
//         the one that compiles and links moonc's C into the program, which is split, compiled in parallel and linked
//         from the objects. MBC_SPLIT=0 passes that one through too.
//     mbc link --out OUT [--dep PATH…] [--stamp FILE] -- LINK COMMAND…
//         The link, unless the same command made OUT of the same inputs already (by content: the files it names and
//         the --dep ones). wrap's link is the same.
//     mbc shim DIR
//         DIR/cc (Windows: DIR/cl.exe, lib.exe, link.exe) running `mbc wrap` over the real one; prints DIR.
//     mbc check --cc CC --cflags FLAGS [--nm NM] --obj DIR FILE.c
//         The self-check: FILE.c compiled whole and split; the global symbols each defines must be the same, none
//         defined twice among the units.
//     mbc work MOON.WORK COPY
//         A workspace's moon.work for a copy of its module elsewhere: the module ".", its other members by absolute
//         path.
//     mbc mirror STAGE COPY
//         COPY's files as STAGE has them (each file and directory at STAGE's top, the rest of COPY left alone: its
//         _build), a file only written when its content changed, so that moon, which goes by mtimes, builds anew
//         only what changed. Gone from STAGE: gone. A C source's content is what it includes too: moon compiles a
//         native stub again only for a newer stub, so each is written with the digest of the files it includes after
//         it (a comment), and anew when one of them changed.
//
// moonbit_init (every global's initial value, tens of thousands of lines, run once) is units of its own (one for
// each package's pieces of it), compiled with --init-flags (MBC_INIT_FLAGS) after the others' flags: by default -O0
// (/Od), as optimising it is most of the time the whole program takes to compile at any level. It runs once.
// scripts/mbc (the launcher) builds this program when it is not built or older than its sources, and says where
// mbui's scripts are (MBC_HOME: scripts/mbc-stub.sh, scripts/mbc-cl.c).

///|
fn log(msg : String) -> Unit {
  eprint("mbc: " + msg)
  match getenv("MBC_LOG") {
    // moon shows a command's output only when it fails: the wrapper's account of a build goes here too
    Some(p) if p.length() > 0 => {
      let _ = c_append(p, utf8("mbc: " + msg + "\n"))

    }
    _ => ()
  }
}

///|
fn fatal(msg : String) -> Unit {
  log(msg)
  c_exit(1)
  panic()
}

///|
fn home() -> Bytes {
  match getenv("MBC_HOME") {
    Some(h) if h.length() > 0 => h
    _ => {
      fatal("MBC_HOME is not set (run it through mbui's scripts/mbc)")
      b""
    }
  }
}

///|
let self_exe : Ref[Bytes] = { val: b"" }

///|
fn cpus() -> Int {
  imax(1, c_cpu_count())
}

///|
fn env_set_to(name : String, v : String) -> Bool {
  match getenv(name) {
    Some(x) => x == utf8(v)
    None => false
  }
}

///|
/// moonbit_init's flags after the others' (MBC_INIT_FLAGS)
fn default_init_flags(msvc : Bool) -> Array[Bytes] {
  match getenv("MBC_INIT_FLAGS") {
    Some(v) => split_words(v)
    None => if msvc { [b"/Od"] } else { [b"-O0"] }
  }
}

///|
fn lower(b : Bytes) -> Bytes {
  let buf = @buffer.new()
  for c in b {
    buf.write_byte(if c >= b'A' && c <= b'Z' { c + b' ' } else { c })
  }
  buf.to_bytes()
}

///|
fn is_msvc(cc : Array[Bytes]) -> Bool {
  let n = lower(basename(cc[0]))
  n == b"cl" || n == b"cl.exe" || n == b"clang-cl" || n == b"clang-cl.exe"
}

///|
let kinds_cache : Map[Bytes, (Int, Bool)] = Map::new()

///|
/// (0 msvc, 1 clang, 2 other (gcc…); whether it targets Apple's platforms: ld64)
fn compiler_kind(cc : Array[Bytes]) -> (Int, Bool) {
  let k = cat(cc.map(fn(w) { cat([w, b"\x00"]) }))
  match kinds_cache.get(k) {
    Some(v) => return v
    None => ()
  }
  let v = if is_msvc(cc) {
    (0, false)
  } else {
    let ask = fn(flag : Bytes) {
      let argv = cc.copy()
      argv.push(flag)
      run_capture(argv).1
    }
    (
      if contains(ask(b"--version"), b"clang") { 1 } else { 2 },
      contains(ask(b"-dumpmachine"), b"apple"),
    )
  }
  kinds_cache[k] = v
  v
}

///|
/// ThinLTO, or MSVC's /GL and /LTCG, only when asked (MBC_LTO=thin): the inlining across units the split loses,
/// brought back at the link. Not by default: mbui's bench (scripts/bench.sh, Studio) drew its scenes in the same time
/// with it and without (process CPU 107-111 µs a frame either way), while its link was most of a build of a changed
/// app: 57 s of Android's, 66 s of Windows' (LTCG made 28% of the functions again for a 116-line change), 2026-10-24.
/// The link's flags, or None.
fn lto_for(cc : Array[Bytes], j : Int) -> Array[Bytes]? {
  match getenv("MBC_LTO") {
    Some(v) if v == b"thin" || v == b"1" || v == b"on" => ()
    _ => return None
  }
  let (kind, apple) = compiler_kind(cc)
  if kind == 0 {
    // MSVC's counterpart: whole-program optimisation (/GL) and link-time code generation, on up to 8 threads.
    // Incremental: the code of the functions whose objects are as the last link's were is taken from its .iobj beside
    // the program, the rest generated again (the same code as a whole /LTCG, which a link with no .iobj is). The
    // Windows app's link was 64 s of its CI job's 225 s on a change to a few units (2026-10-22, 39723898515).
    return Some([b"/link", b"/LTCG:INCREMENTAL", utf8("/CGTHREADS:\{imin(8, j)}")])
  }
  if kind != 1 {
    return None
  }
  // ld64 runs ThinLTO's backends on every core by itself; lld takes the count. MBC_LTO_CACHE: the linker's ThinLTO
  // cache
  let cache = match getenv("MBC_LTO_CACHE") {
    Some(c) if c.length() > 0 => {
      makedirs(c)
      Some(abspath(c))
    }
    _ => None
  }
  if apple {
    let f = [b"-flto=thin"]
    match cache {
      Some(c) => f.push(cat([b"-Wl,-cache_path_lto,", c]))
      None => ()
    }
    return Some(f)
  }
  // (elsewhere lld, which these flags are for, as Linux's own ld takes no bitcode)
  let f = [b"-flto=thin", b"-fuse-ld=lld", utf8("-Wl,--thinlto-jobs=\{j}")]
  match cache {
    Some(c) => f.push(cat([b"-Wl,--thinlto-cache-dir=", c]))
    None => ()
  }
  Some(f)
}

///|
fn lto_compile(msvc : Bool) -> Array[Bytes] {
  if msvc {
    [b"/GL"]
  } else {
    [b"-flto=thin"]
  }
}

///|
/// A compile-and-link command with the link's flags added (MSVC's after its /link)
fn with_link_flags(args : Array[Bytes], flags : Array[Bytes]) -> Array[Bytes] {
  if flags.length() > 0 && flags[0] == b"/link" {
    for k, x in args {
      let l = lower(x)
      if l == b"/link" || l == b"-link" {
        let out = args[0:k + 1].to_array()
        for i in 1..<flags.length() {
          out.push(flags[i])
        }
        for i in (k + 1)..<args.length() {
          out.push(args[i])
        }
        return out
      }
    }
  }
  let out = args.copy()
  for f in flags {
    out.push(f)
  }
  out
}

// ---------------------------------------------------------------- what files are, by content

///|
let hash_cache : Map[Bytes, (Int64, Int64, Bytes)] = Map::new()

///|
/// A file's SHA-1 (by its content; kept while its size and mtime are the same), None when it cannot be read
fn file_hash(p : Bytes) -> Bytes? {
  let st = match stat(p) {
    Some(s) => s
    None => return None
  }
  match hash_cache.get(p) {
    Some((size, mtime, h)) if size == st.0 && mtime == st.1 => return Some(h)
    _ => ()
  }
  match read_file(p) {
    Some(d) => {
      let h = sha1_hex(d, 40)
      hash_cache[p] = (st.0, st.1, h)
      Some(h)
    }
    None => None
  }
}

///|
let tools_cache : Map[Bytes, Bytes] = Map::new()

///|
/// What a compiler or linker is, beyond its command line: its own --version and the file it runs (a wrapper as the
/// shim, by its content too); MSVC's cl and link by their files. A new Xcode, a new MSVC or a wrapper changed: its
/// objects and links are not taken for the ones it makes.
fn tool_identity(tool : Array[Bytes]) -> Bytes {
  let k = cat(tool.map(fn(w) { cat([w, b"\x00"]) }))
  match tools_cache.get(k) {
    Some(v) => return v
    None => ()
  }
  let exe = if is_file(tool[0]) {
    tool[0]
  } else {
    which(tool[0]).unwrap_or(tool[0])
  }
  let parts = []
  match file_hash(exe) {
    Some(h) => parts.push(h)
    None => parts.push(cat([b"no file ", exe]))
  }
  let b = lower(basename(exe))
  if !is_msvc(tool) &&
    b != b"link" &&
    b != b"link.exe" &&
    b != b"lib" &&
    b != b"lib.exe" {
    let argv = tool.copy()
    argv.push(b"--version")
    parts.push(run_capture(argv).1)
  }
  let buf = @buffer.new()
  for i, p in parts {
    if i > 0 {
      buf.write_byte(b'\x00')
    }
    buf.write_bytes(p)
  }
  let v = sha1_hex(buf.to_bytes(), 40)
  tools_cache[k] = v
  v
}

///|
/// The files a depfile names (what an object was made of)
fn depfile_paths(dep : Bytes) -> Array[Bytes] {
  let text = replace_all(read_file(dep).unwrap_or(b""), b"\\\n", b" ")
  let colon = find_byte(text, b':', 0)
  let rest = if colon < 0 { b"" } else { strip(sub(text, colon + 1, text.length())) }
  let out = []
  let w = @buffer.new()
  let mut any = false
  let mut i = 0
  while i < rest.length() {
    let c = rest[i]
    if is_space(c) && !(i > 0 && rest[i - 1] == b'\\') {
      if any {
        out.push(replace_all(w.to_bytes(), b"\\ ", b" "))
        w.reset()
        any = false
      }
    } else {
      w.write_byte(c)
      any = true
    }
    i += 1
  }
  if any {
    out.push(replace_all(w.to_bytes(), b"\\ ", b" "))
  }
  out
}

// ---------------------------------------------------------------- jobs: a source compiled to an object

///|
priv struct Job {
  src : Bytes
  obj : Bytes
  argv : Array[Bytes]
  optional : Bool
  depfile : Bytes? // (none with MSVC: those always compile)
  weight : Int64
  cc : Array[Bytes]
  mut secs : Double
  mut cached : Bool
  mut shared : Bool
  mut ok : Bool
  mut err : Bytes
}

///|
fn Job::new(
  src : Bytes,
  obj : Bytes,
  argv : Array[Bytes],
  depfile : Bytes?,
  weight : Int64,
  cc : Array[Bytes],
  optional? : Bool = false,
) -> Job {
  {
    src,
    obj,
    argv,
    optional,
    depfile,
    weight,
    cc,
    secs: 0.0,
    cached: false,
    shared: false,
    ok: true,
    err: b"",
  }
}

///|
fn join_words(ws : Array[Bytes], s : Bytes) -> Bytes {
  let buf = @buffer.new()
  for i, w in ws {
    if i > 0 {
      buf.write_bytes(s)
    }
    buf.write_bytes(w)
  }
  buf.to_bytes()
}

///|
fn lines(t : Bytes) -> Array[Bytes] {
  let out = []
  let mut s = 0
  for k in 0..<t.length() {
    if t[k] == b'\n' {
      out.push(sub(t, s, k))
      s = k + 1
    }
  }
  if s < t.length() {
    out.push(sub(t, s, t.length()))
  }
  out
}

///|
/// (path, hash) lines: what a stamp or a store's entry says its object was made of
fn deps_text(deps : Array[Bytes]) -> Bytes? {
  let buf = @buffer.new()
  for d in deps {
    match file_hash(d) {
      Some(h) => {
        buf.write_bytes(d)
        buf.write_byte(b'\x1f')
        buf.write_bytes(h)
        buf.write_byte(b'\n')
      }
      None => return None
    }
  }
  Some(buf.to_bytes())
}

///|
/// Whether every (path, hash) line is as the file is now
fn deps_same(ls : ArrayView[Bytes]) -> Bool {
  for l in ls {
    let k = find_byte(l, b'\x1f', 0)
    if k < 0 {
      return false
    }
    match file_hash(sub(l, 0, k)) {
      Some(h) if h == sub(l, k + 1, l.length()) => ()
      _ => return false
    }
  }
  true
}

///|
fn Job::stamp(self : Job) -> Bytes {
  cat([self.obj, b".mbc"])
}

///|
/// The stamp: its command, its compiler's identity, then what it was made of
fn Job::up_to_date(self : Job) -> Bool {
  let st = match read_file(self.stamp()) {
    Some(s) => lines(s)
    None => return false
  }
  if st.length() < 2 ||
    st[0] != join_words(self.argv, b"\x1f") ||
    st[1] != tool_identity(self.cc) ||
    !exists(self.obj) {
    return false
  }
  deps_same(st[2:])
}

///|
fn Job::write_stamp(self : Job, deps : Array[Bytes]) -> Unit {
  match deps_text(deps) {
    Some(d) => {
      let _ = write_file(
        self.stamp(),
        cat([
          join_words(self.argv, b"\x1f"),
          b"\n",
          tool_identity(self.cc),
          b"\n",
          d,
        ]),
      )

    }
    None => ()
  }
}

///|
/// The object's key in MBC_STORE: its command (but for where it reads and writes), its compiler and its source's
/// content
fn Job::store_key(self : Job) -> Bytes {
  let argv = self.argv.map(fn(x) {
    if x == self.src {
      b"<src>"
    } else if x == self.obj {
      b"<obj>"
    } else {
      match self.depfile {
        Some(d) if x == d => b"<dep>"
        _ => x
      }
    }
  })
  argv.push(tool_identity(self.cc))
  argv.push(file_hash(self.src).unwrap_or(b""))
  sha1_hex(join_words(argv, b"\x00"), 40)
}

///|
fn Job::store_dir(self : Job, store : Bytes) -> Bytes {
  let k = self.store_key()
  joins([store, sub(k, 0, 2), k])
}

///|
/// The object another program's unit of the same text, command and compiler made, when what else it read (every
/// header its depfile named, by content) is as it was
fn Job::from_store(self : Job, store : Bytes) -> Bool {
  let d = self.store_dir(store)
  let deps = match read_file(path_join(d, b"deps")) {
    Some(t) => lines(t)
    None => return false
  }
  if !deps_same(deps[:]) {
    return false
  }
  let tmp = cat([self.obj, b".tmp"])
  if !copyfile(path_join(d, b"obj"), tmp) || c_rename(tmp, self.obj) == 0 {
    return false
  }
  // (used: what a store keeps is what was used since a time: CI's prune)
  let _ = c_touch(d)
  let all = [self.src]
  for l in deps {
    all.push(sub(l, 0, find_byte(l, b'\x1f', 0)))
  }
  self.write_stamp(all)
  true
}

///|
fn Job::to_store(self : Job, store : Bytes, deps : Array[Bytes]) -> Unit {
  let d = self.store_dir(store)
  let tmp = cat([d, utf8(".tmp\{c_getpid()}")])
  makedirs(tmp)
  let src = abspath(self.src)
  match deps_text(deps.filter(fn(p) { abspath(p) != src })) {
    Some(t) =>
      if copyfile(self.obj, path_join(tmp, b"obj")) &&
        write_file(path_join(tmp, b"deps"), t) {
        if is_dir(d) {
          rmtree(d)
        }
        if c_rename(tmp, d) != 0 {
          return
        }
      }
    None => ()
  }
  rmtree(tmp)
}

///|
/// An object already up to date here, said used in MBC_STORE as one taken from it is (put there when it is not):
/// what the store keeps is what a run used (CI prunes the rest), and a build over a restored _build compiled only
/// what changed and took nothing from the store, so main's store kept only those, 54 units of 376 (40125500788),
/// and a branch restoring it compiled the other 250 again (240 s, 40125788155, 2026-10-24)
fn Job::keep_in_store(self : Job, store : Bytes) -> Unit {
  let d = self.store_dir(store)
  if is_dir(d) {
    let _ = c_touch(d)
    return
  }
  match read_file(self.stamp()) {
    Some(s) => {
      let deps = lines(s)[2:].to_array().map(fn(l) { sub(l, 0, find_byte(l, b'\x1f', 0)) })
      deps.push(self.src)
      self.to_store(store, deps)
    }
    None => ()
  }
}

///|
/// The command compiling `src` to `obj`, and its depfile (none with MSVC)
fn compile_args(
  cc : Array[Bytes],
  flags : Array[Bytes],
  src : Bytes,
  obj : Bytes,
  msvc : Bool,
) -> (Array[Bytes], Bytes?) {
  let argv = cc.copy()
  for f in flags {
    argv.push(f)
  }
  if msvc {
    argv.push(b"/nologo")
    argv.push(b"/c")
    argv.push(src)
    argv.push(cat([b"/Fo", obj]))
    return (argv, None)
  }
  let dep = cat([obj, b".d"])
  for w in [b"-MD", b"-MF", dep, b"-c", src, b"-o", obj] {
    argv.push(w)
  }
  (argv, Some(dep))
}

///|
/// The jobs, j at a time (the heaviest first): the objects of those that compiled. An object whose stamp says it
/// is made of what it would be made of now is kept; with MBC_STORE, one another program made of the same is taken.
/// Another program compiling the same unit at the same time (moon builds a module's tests side by side): its object
/// waited for, not made again: a lock the system lets go when its holder ends however it ends (flock), waited on
/// only when nothing of this one's is running (no time, no deadlock).
fn run_jobs_c(jobs0 : Array[Job], j : Int, label : Bytes) -> Array[Bytes] {
  let t0 = now_s()
  let jobs = stable_sort(jobs0, fn(a, b) {
    if a.weight > b.weight {
      -1
    } else if a.weight < b.weight {
      1
    } else {
      0
    }
  })
  let store = match getenv("MBC_STORE") {
    Some(s) if s.length() > 0 => Some(s)
    _ => None
  }
  let queue : Array[Job] = []
  for x in jobs {
    if x.up_to_date() {
      x.cached = true
      match store {
        Some(s) => x.keep_in_store(s)
        None => ()
      }
      continue
    }
    let _ = c_remove(x.stamp())
    match store {
      Some(s) =>
        if x.from_store(s) {
          x.cached = true
          x.shared = true
          continue
        }
      None => ()
    }
    queue.push(x)
  }
  // (slot: the job, its lock, when it started, where its output goes)
  let running : Map[Int, (Job, Int, Double, Bytes)] = Map::new()
  let mut q = queue
  let mut deferred : Array[Job] = []
  let finish = fn(x : Job, fd : Int, started : Double, out : Bytes, code : Int) {
    x.secs = now_s() - started
    x.err = read_file(out).unwrap_or(b"")
    let _ = c_remove(out)
    x.ok = code == 0
    if x.ok {
      let deps = match x.depfile {
        Some(d) if exists(d) => depfile_paths(d)
        _ => [x.src]
      }
      x.write_stamp(deps)
      match store {
        Some(s) => x.to_store(s, deps)
        None => ()
      }
    }
    c_unlock(fd)
  }
  let mut next = 0
  while true {
    let mut started_any = false
    while running.length() < imax(1, j) && next < q.length() {
      let x = q[next]
      next += 1
      let mut fd = 0
      match store {
        Some(s) if !windows => {
          let d = x.store_dir(s)
          makedirs(dirname(d))
          let lock = cat([d, b".lock"])
          fd = c_lock(lock, 0)
          if fd < 0 {
            if running.length() == 0 {
              fd = c_lock(lock, 1)
            } else {
              deferred.push(x)
              continue
            }
          }
          if x.from_store(s) {
            x.cached = true
            x.shared = true
            c_unlock(fd)
            continue
          }
        }
        _ => ()
      }
      let out = tmp_path("cc")
      let slot = spawn(x.argv, out)
      if slot < 0 {
        x.ok = false
        x.err = utf8("cannot run \{str(x.argv[0])}\n")
        c_unlock(fd)
        continue
      }
      running[slot] = (x, fd, now_s(), out)
      started_any = true
    }
    if running.length() == 0 {
      if next >= q.length() && deferred.length() > 0 {
        q = deferred
        deferred = []
        next = 0
        continue
      }
      if next >= q.length() {
        break
      }
      continue
    }
    let _ = started_any
    let (s, code) = wait_any()
    match running.get(s) {
      Some((x, fd, started, out)) => {
        running.remove(s)
        finish(x, fd, started, out, code)
      }
      None => ()
    }
    // (what waited for a lock: again, once what this one holds is let go)
    if deferred.length() > 0 {
      for x in deferred {
        q.push(x)
      }
      deferred = []
    }
  }
  let wall = secs(t0)
  let mut bad = false
  for x in jobs {
    if !x.ok && x.optional {
      let first = match lines(x.err).search_by(fn(l) { contains(l, b"error") }) {
        Some(i) => lines(x.err)[i]
        None => pyslice(strip(x.err), 0, 200)
      }
      log("skip \{str(x.src)}: \{str(first)}")
    } else if !x.ok {
      c_write_err(x.err)
      log("\{str(x.src)} did not compile: \{str(quote_all(x.argv))}")
      bad = true
    }
  }
  let built = jobs.filter(fn(x) { !x.cached })
  let mut shared = 0
  for x in jobs {
    if x.shared {
      shared += 1
    }
  }
  let slow = stable_sort(built, fn(a, b) {
    if a.secs > b.secs {
      -1
    } else if a.secs < b.secs {
      1
    } else {
      0
    }
  })
  let buf = StringBuilder::new()
  buf.write_string(
    "\{str(label)}: \{built.length()} of \{jobs.length()} compiled (\{jobs.length() - built.length()} up to date",
  )
  if shared > 0 {
    buf.write_string(", \{shared} of them from MBC_STORE")
  }
  buf.write_string(") in \{wall} s on \{j} jobs")
  if slow.length() > 0 {
    buf.write_string("; slowest ")
    for i in 0..<imin(3, slow.length()) {
      if i > 0 {
        buf.write_string(", ")
      }
      let t = (slow[i].secs * 10.0 + 0.5).to_int()
      buf.write_string("\{str(basename(slow[i].src))} \{t / 10}.\{t % 10} s")
    }
  }
  log(buf.to_string())
  if bad {
    c_exit(1)
  }
  jobs.filter(fn(x) { x.ok }).map(fn(x) { x.obj })
}

///|
/// moonbit_init's units (csplit): init.c, and its packages' pieces, init.<package>.c
fn is_init(unit : Bytes) -> Bool {
  unit == b"init.c" || starts(unit, b"init.")
}

///|
/// What the split made, as mbc keeps it beside the units (manifest.txt)
priv struct Made {
  key : Bytes
  units : Array[Bytes]
  functions : Int
  globals : Int
  init_bytes : Int
  max_load : Int
  decls_h : Int
  statics_dropped : Int
  made_global : Array[Bytes]
}

///|
fn Made::text(self : Made) -> Bytes {
  let buf = @buffer.new()
  buf.write_bytes(
    utf8(
      "key \{str(self.key)}\nfunctions \{self.functions}\nglobals \{self.globals}\ninit_bytes \{self.init_bytes}\nmax_load \{self.max_load}\ndecls_h \{self.decls_h}\nstatics_dropped \{self.statics_dropped}\n",
    ),
  )
  for u in self.units {
    buf.write_bytes(b"unit ")
    buf.write_bytes(u)
    buf.write_byte(b'\n')
  }
  for m in self.made_global {
    buf.write_bytes(b"made ")
    buf.write_bytes(m)
    buf.write_byte(b'\n')
  }
  buf.to_bytes()
}

///|
fn Made::parse(t : Bytes) -> Made? {
  let units = []
  let made = []
  let nums : Map[Bytes, Int] = Map::new()
  let mut key = b""
  for l in lines(t) {
    let k = find_byte(l, b' ', 0)
    if k < 0 {
      return None
    }
    let name = sub(l, 0, k)
    let v = sub(l, k + 1, l.length())
    if name == b"key" {
      key = v
    } else if name == b"unit" {
      units.push(v)
    } else if name == b"made" {
      made.push(v)
    } else {
      nums[name] = parse_int(v)
    }
  }
  Some({
    key,
    units,
    functions: nums.get_or_default(b"functions", 0),
    globals: nums.get_or_default(b"globals", 0),
    init_bytes: nums.get_or_default(b"init_bytes", 0),
    max_load: nums.get_or_default(b"max_load", 0),
    decls_h: nums.get_or_default(b"decls_h", 0),
    statics_dropped: nums.get_or_default(b"statics_dropped", 0),
    made_global: made,
  })
}

///|
/// Split c_file into objdir/src and the jobs compiling its units into objdir
fn split_jobs(
  c_file : Bytes,
  objdir : Bytes,
  cc : Array[Bytes],
  flags : Array[Bytes],
  gen_flags : Array[Bytes],
  init_flags : Array[Bytes],
  msvc : Bool,
  lto : Bool,
) -> (Array[Job], Made) {
  let srcdir = path_join(objdir, b"src")
  let raw = match read_file(c_file) {
    Some(r) => r
    None => {
      fatal("cannot read \{str(c_file)}")
      b""
    }
  }
  let t0 = now_s()
  // the same C split the same way as last time: the units are there already. (stable, the only grouping: moonc's
  // made-up names made stable and each unit with only the declarations it uses, so that a change compiles the units
  // whose functions changed, not all of them)
  match getenv("MBC_GROUP") {
    Some(g) if g != b"stable" => fatal("MBC_GROUP: only stable now")
    _ => ()
  }
  let key = sha1_hex(
    cat([raw, b"\x00stable\x00", file_hash(self_exe.val).unwrap_or(b"")]),
    40,
  )
  let saved = path_join(srcdir, b"manifest.txt")
  let mut made : Made? = None
  match read_file(saved) {
    Some(t) =>
      match Made::parse(t) {
        Some(m) if m.key == key &&
          m.units.iter().all(fn(n) { is_file(path_join(srcdir, n)) }) => made = Some(m)
        _ => ()
      }
    None => ()
  }
  let m = match made {
    Some(m) => m
    None => {
      makedirs(srcdir)
      let s = try split(raw, srcdir) catch {
        SplitError(e) => {
          fatal("\{str(c_file)}: \{e}")
          panic()
        }
      }
      let names = BSet::new()
      for f in s.files {
        names.add(f.0)
      }
      for old in list_dir(srcdir) {
        if !names.has(old) {
          let _ = c_remove(path_join(srcdir, old))

        }
      }
      let mut max_load = 0
      for l in s.unit_loads {
        max_load = imax(max_load, l)
      }
      let mut dropped = 0
      for x in s.stats {
        if x.0 == "statics_dropped" {
          dropped = x.1
        }
      }
      let m : Made = {
        key,
        units: s.files.map(fn(f) { f.0 }),
        functions: s.functions,
        globals: s.globals,
        init_bytes: s.init_bytes,
        max_load,
        decls_h: s.files[0].1,
        statics_dropped: dropped,
        made_global: s.made_global,
      }
      let _ = write_file(saved, m.text())
      m
    }
  }
  let units = BSet::of(m.units)
  for old in list_dir(objdir) {
    // a unit's object (u_<unit>.o and its .d, .mbc) when the split has fewer units than before
    if starts(old, b"u_") {
      let rest = sub(old, 2, old.length())
      let dot = find_byte(rest, b'.', 0)
      let base = if dot < 0 { rest } else { sub(rest, 0, dot) }
      if !units.has(cat([base, b".c"])) {
        let _ = c_remove(path_join(objdir, old))

      }
    }
  }
  log(
    "\{str(basename(c_file))}: \{m.functions} functions, \{m.globals} globals -> \{m.units.length() - 2} units in \{secs(t0)} s (moonbit_init \{m.init_bytes / 1024} KB, functions \{m.max_load / 1024} KB a unit, decls.h \{m.decls_h / 1024} KB" +
    (if m.statics_dropped > 0 { ", \{m.statics_dropped} static dropped" } else { "" }) +
    ")",
  )
  let ext = if msvc { b".obj" } else { b".o" }
  let jobs = []
  for name in m.units {
    if !ends(name, b".c") {
      continue
    }
    // the units but moonbit_init's as ThinLTO's bitcode (lto): the link inlines across them as the whole file did
    let f = flags.copy()
    for x in gen_flags {
      f.push(x)
    }
    let more = if is_init(name) {
      init_flags
    } else if lto {
      lto_compile(msvc)
    } else {
      []
    }
    for x in more {
      f.push(x)
    }
    let src = path_join(srcdir, name)
    let obj = path_join(objdir, cat([b"u_", sub(name, 0, name.length() - 2), ext]))
    let (argv, dep) = compile_args(cc, f, src, obj, msvc)
    // moonbit_init first: the slowest to compile at any level
    let size = match stat(src) {
      Some(s) => s.0
      None => 0L
    }
    jobs.push(
      Job::new(src, obj, argv, dep, if is_init(name) { size * 4L } else { size }, cc),
    )
  }
  (jobs, m)
}

// ---------------------------------------------------------------- arguments

///|
/// Options as argparse took them (--name VALUE or --name=VALUE; `lists`: may come again), the rest in order
priv struct Args {
  vals : Map[String, Bytes]
  lists : Map[String, Array[Bytes]]
  flags : Map[String, Bool]
  pos : Array[Bytes]
  rest : Array[Bytes] // after "--" (or everything after the first positional, with `remainder`)
}

///|
fn parse_args(
  args : Array[String],
  valued : Array[String],
  listed? : Array[String] = [],
  switches? : Array[String] = [],
  remainder? : Bool = false,
) -> Args {
  let a : Args = {
    vals: Map::new(),
    lists: Map::new(),
    flags: Map::new(),
    pos: [],
    rest: [],
  }
  let mut i = 0
  while i < args.length() {
    let x = args[i]
    if x == "--" {
      for k in (i + 1)..<args.length() {
        a.rest.push(utf8(args[k]))
      }
      break
    }
    let mut name = x
    let mut value : String? = None
    match x.find("=") {
      Some(k) if x.has_prefix("-") => {
        name = x.view(end_offset=k).to_string()
        value = Some(x.view(start_offset=k + 1).to_string())
      }
      _ => ()
    }
    let is_val = valued.contains(name)
    let is_list = listed.contains(name)
    if is_val || is_list {
      let v = match value {
        Some(v) => v
        None => {
          i += 1
          if i >= args.length() {
            fatal("\{name} wants a value")
          }
          args[i]
        }
      }
      if is_list {
        match a.lists.get(name) {
          Some(l) => l.push(utf8(v))
          None => a.lists[name] = [utf8(v)]
        }
      } else {
        a.vals[name] = utf8(v)
      }
    } else if switches.contains(x) {
      a.flags[x] = true
    } else if remainder && x.has_prefix("-") == false {
      for k in i..<args.length() {
        a.rest.push(utf8(args[k]))
      }
      break
    } else {
      a.pos.push(utf8(x))
    }
    i += 1
  }
  a
}

///|
fn Args::get(self : Args, name : String) -> Bytes? {
  self.vals.get(name)
}

///|
fn Args::list(self : Args, name : String) -> Array[Bytes] {
  self.lists.get_or_default(name, [])
}

///|
fn Args::need(self : Args, name : String) -> Bytes {
  match self.vals.get(name) {
    Some(v) => v
    None => {
      fatal("\{name} is needed")
      b""
    }
  }
}

///|
fn Args::int(self : Args, name : String) -> Int {
  match self.vals.get(name) {
    Some(v) => parse_int(strip(v))
    None => 0
  }
}

///|
fn Args::src(self : Args) -> Bytes {
  if self.pos.length() != 1 {
    fatal("one C file is needed")
  }
  self.pos[0]
}

// ---------------------------------------------------------------- gen

///|
/// `^\s*NAME\s*=\s*"([^"]*)"` (re.M): the value
fn toml_value(text : Bytes, name : Bytes) -> Bytes? {
  for l in lines(text) {
    let i = lskip(l, 0)
    if starts_at(l, i, name) {
      let k = lskip(l, i + name.length())
      if k < l.length() && l[k] == b'=' {
        let q = lskip(l, k + 1)
        if q < l.length() && l[q] == b'"' {
          let e = find_byte(l, b'"', q + 1)
          if e >= 0 {
            return Some(sub(l, q + 1, e))
          }
        }
      }
    }
  }
  None
}

///|
fn cmd_gen(args : Array[String]) -> Unit {
  let a = parse_args(args, ["--dir", "--target-dir"], switches=["--debug"])
  let mod_ = abspath(a.get("--dir").unwrap_or(b"."))
  let text = read_file(path_join(mod_, b"moon.mod")).unwrap_or(b"")
  let source = toml_value(text, b"source").unwrap_or(b".")
  // a workspace's (moon.work) packages are built under their module's name: one of more than one module (an app's
  // beside mbui); mbui's own, itself alone (kept from the app's workspace above it), as a module's
  let name = toml_value(text, b"name")
  let work = path_join(mod_, b"moon.work")
  let in_work = is_file(work) &&
    name is Some(_) &&
    lines(read_file(work).unwrap_or(b"")).filter(fn(l) {
      let i = lskip(l, 0)
      i < l.length() && l[i] == b'"'
    }).length() >
    1
  if a.pos.length() != 1 {
    fatal("gen: a package is needed")
  }
  let mut pkg = a.pos[0]
  while pkg.length() > 1 && pkg[pkg.length() - 1] == b'/' {
    pkg = sub(pkg, 0, pkg.length() - 1)
  }
  let rel = if source.length() > 0 && source != b"." {
    relpath(pkg, source)
  } else {
    pkg
  }
  let debug = a.flags.contains("--debug")
  let mode = if debug { b"debug" } else { b"release" }
  let target = match a.get("--target-dir") {
    Some(t) => abspath(t)
    None => path_join(mod_, b"_build")
  }
  let parts = [target, b"native", mode, b"build"]
  if in_work {
    parts.push(name.unwrap())
  }
  parts.push(rel)
  parts.push(cat([basename(rel), b".c"]))
  let out = joins(parts)
  let stub = path_join(home(), b"mbc-stub.sh")
  let _ = c_setenv(b"MOON_CC", stub)
  let _ = c_setenv(b"MOON_AR", stub)
  let cmd = [b"moon", b"build", b"--target", b"native"]
  if !debug {
    cmd.push(b"--release")
  }
  match a.get("--target-dir") {
    Some(_) => {
      cmd.push(b"--target-dir")
      cmd.push(target)
    }
    None => ()
  }
  cmd.push(pkg)
  let t0 = now_s()
  let cwd = c_getcwd()
  let _ = c_chdir(mod_)
  let (code, said) = run_capture(cmd)
  let _ = c_chdir(cwd)
  c_write_err(said)
  // never an old one: moon succeeded, and the C is no older than the package's .core beside it (link-core's input;
  // when moon had nothing to do, both are as the last build left them)
  let core = cat([sub(out, 0, out.length() - 2), b".core"])
  for l in lines(said) {
    if word_at(l, lskip(l, 0), b"Error") >= 0 {
      fatal("moon reported errors (exit \{code}): its output above")
    }
  }
  let so = stat(out)
  let sc = stat(core)
  let fresh = match (so, sc) {
    (Some(o), Some(c)) => o.0 > 0L && o.1 >= c.1
    _ => false
  }
  if code != 0 || !fresh {
    fatal(
      "moon did not write \{str(out)} (exit \{code}" +
      (if sc is None { ", no \{str(core)}" } else { "" }) +
      "): its output above; if moon now puts it elsewhere, mbc gen needs to know",
    )
  }
  let size = so.unwrap().0.to_int() / 1024
  log("\{str(relpath(out, b"."))}: \{size} KB in \{secs(t0)} s (moon exit \{code})")
  out_line(out)
}

// ---------------------------------------------------------------- work, mirror

///|
/// A copy of a workspace's moon.work for a copy of its module elsewhere: the module itself stays ".", every other
/// member by its absolute path. Written only when it changes.
fn cmd_work(args : Array[String]) -> Unit {
  if args.length() != 2 {
    fatal("work: MOON.WORK COPY")
  }
  let src = utf8(args[0])
  let dst = utf8(args[1])
  let base = dirname(abspath(src))
  let text = read_file(src).unwrap_or(b"")
  let buf = @buffer.new()
  let mut i = 0
  while i < text.length() {
    if text[i] == b'"' {
      let e = find_byte(text, b'"', i + 1)
      if e >= 0 {
        let m = sub(text, i + 1, e)
        buf.write_bytes(
          if m == b"." {
            b"\".\""
          } else {
            json_dumps(realpath(path_join(base, m)))
          },
        )
        i = e + 1
        continue
      }
    }
    buf.write_byte(text[i])
    i += 1
  }
  let new = buf.to_bytes()
  match read_file(dst) {
    Some(old) if old == new => ()
    _ => {
      let _ = write_file(dst, new)

    }
  }
}

///|
fn cmd_mirror(args : Array[String]) -> Unit {
  if args.length() != 2 {
    fatal("mirror: STAGE COPY")
  }
  let src_top = utf8(args[0])
  let dst_top = utf8(args[1])
  let dirs = cl_include_dirs()
  let mut written = 0
  for top in sort_bytes(list_dir(src_top)) {
    let src = path_join(src_top, top)
    let dst = path_join(dst_top, top)
    let pairs : Array[(Bytes, Bytes)] = []
    if is_file(src) {
      pairs.push((src, dst))
      if is_dir(dst) {
        rmtree(dst)
      }
    } else {
      if is_file(dst) {
        let _ = c_remove(dst)

      }
      for f in walk_files(src) {
        pairs.push((f, path_join(dst, sub(f, src.length() + 1, f.length()))))
      }
      let keep = BSet::of(pairs.map(fn(p) { p.1 }))
      prune(dst, keep, dst)
    }
    for p in pairs {
      let (s, d) = p
      let want = match mirrored(s, dirs) {
        Some(w) => w
        None => continue
      }
      match read_file(d) {
        Some(b) if b == want => continue
        _ => ()
      }
      makedirs(dirname(d))
      if is_dir(d) {
        rmtree(d)
      }
      // (a file written now: newer than anything built from what it was)
      let _ = write_file(d, want)
      written += 1
    }
  }
  if getenv("MBC_VERBOSE") is Some(_) {
    log("mirror \{args[1]}: \{written} files written")
  }
}

///|
/// A file as mirror writes it: as it is, a C source with the digest of the files it includes after it, so that it is
/// written anew when one of them changes (still.fail's Windows host, src/host/win_core.c, is its win_engine.c's
/// #include: compiled on 2026-10-24, it was kept by every build after, though it changed). None: it cannot be read.
fn mirrored(src : Bytes, dirs : Array[Bytes]) -> Bytes? {
  let t = match read_file(src) {
    Some(t) => t
    None => return None
  }
  if !is_c_source(src) {
    return Some(t)
  }
  let files = included_files(src, dirs)
  if files.length() == 0 {
    return Some(t)
  }
  let all = @buffer.new()
  for f in files {
    match read_file(f) {
      Some(d) => {
        all.write_bytes(utf8("\{d.length()}:"))
        all.write_bytes(d)
      }
      None => ()
    }
  }
  let end = if t.length() > 0 && t[t.length() - 1] != b'\n' { b"\n" } else { b"" }
  Some(cat([t, end, b"// mbc mirror: what it includes, by content: ", sha1_hex(all.to_bytes(), 40), b"\n"]))
}

///|
/// What moon compiles as a package's native stub: C, C++, Objective-C
fn is_c_source(p : Bytes) -> Bool {
  let (_, ext) = splitext(p)
  ext == b".c" || ext == b".cc" || ext == b".cpp" || ext == b".m" || ext == b".mm"
}

///|
/// Where the C compiler looks for an #include beyond the includer's own directory: the directories given it in CL
/// (MSVC's options from the environment, as still.fail's scripts/win.sh gives them: /I<dir>, -I<dir>, /I <dir>)
fn cl_include_dirs() -> Array[Bytes] {
  let out = []
  let words = match getenv("CL") {
    Some(cl) => split_words(cl, posix=false)
    None => []
  }
  let mut i = 0
  while i < words.length() {
    let w = words[i]
    if w.length() >= 2 && (w[0] == b'/' || w[0] == b'-') && w[1] == b'I' {
      let mut d = sub(w, 2, w.length())
      if d.length() == 0 && i + 1 < words.length() {
        i += 1
        d = words[i]
      }
      if d.length() >= 2 && d[0] == b'"' && d[d.length() - 1] == b'"' {
        d = sub(d, 1, d.length() - 1)
      }
      if d.length() > 0 {
        out.push(d)
      }
    }
    i += 1
  }
  out
}

///|
/// What a C source's #include and #import lines name, in order: (the name, true for a "…" one, looked for beside the
/// file first; false for a <…> one)
fn include_names(t : Bytes) -> Array[(Bytes, Bool)] {
  let out = []
  let n = t.length()
  let mut i = 0
  while i < n {
    let e = eol(t, i)
    let mut k = i
    while k < e && (t[k] == b' ' || t[k] == b'\t') {
      k += 1
    }
    if k < e && t[k] == b'#' {
      k += 1
      while k < e && (t[k] == b' ' || t[k] == b'\t') {
        k += 1
      }
      let word = if starts_at(t, k, b"include") {
        7
      } else if starts_at(t, k, b"import") {
        6
      } else {
        0
      }
      if word > 0 {
        k += word
        while k < e && (t[k] == b' ' || t[k] == b'\t') {
          k += 1
        }
        if k < e && (t[k] == b'"' || t[k] == b'<') {
          let quoted = t[k] == b'"'
          let c = find_byte(t[:e], if quoted { b'"' } else { b'>' }, k + 1)
          if c > k + 1 {
            out.push((sub(t, k + 1, c), quoted))
          }
        }
      }
    }
    i = e + 1
  }
  out
}

///|
/// The files a C source includes and those include, each once, as the compiler finds them: a "…" one beside the file
/// naming it, else in `dirs`; a <…> one in `dirs` (the system's headers, past them, are not followed)
fn included_files(src : Bytes, dirs : Array[Bytes]) -> Array[Bytes] {
  let seen = BSet::of([normpath(src)])
  let out = []
  let todo = [src]
  while todo.length() > 0 {
    let p = todo.pop().unwrap()
    match read_file(p) {
      Some(t) =>
        for x in include_names(t) {
          let (name, quoted) = x
          let places = if quoted { [path_join(dirname(p), name)] } else { [] }
          for d in dirs {
            places.push(path_join(d, name))
          }
          for q in places {
            if is_file(q) {
              let q = normpath(q)
              if !seen.has(q) {
                seen.add(q)
                out.push(q)
                todo.push(q)
              }
              break
            }
          }
        }
      None => ()
    }
  }
  out
}

///|
/// What of `dir` is not in `keep` removed, and the directories left empty (not `top`)
fn prune(dir : Bytes, keep : BSet, top : Bytes) -> Unit {
  if !is_dir(dir) {
    return
  }
  for n in list_dir(dir) {
    let p = path_join(dir, n)
    if is_dir(p) {
      prune(p, keep, top)
    } else if !keep.has(p) {
      let _ = c_remove(p)

    }
  }
  if dir != top && list_dir(dir).length() == 0 {
    let _ = c_rmdir(dir)

  }
}

// ---------------------------------------------------------------- compile

///|
fn cmd_compile(args : Array[String]) -> Unit {
  let a = parse_args(
    args,
    [
      "--cc", "--cflags", "--gen-flags", "--init-flags", "--objc-flags", "--obj",
      "-j", "-n", "--link-flags",
    ],
    listed=["--extra", "--optional"],
  )
  let cc = split_words(a.need("--cc"))
  let msvc = is_msvc(cc)
  let flags = split_words(a.get("--cflags").unwrap_or(b""))
  let gen_flags = split_words(a.get("--gen-flags").unwrap_or(b""))
  let init_flags = match a.get("--init-flags") {
    Some(f) => split_words(f)
    None => default_init_flags(msvc)
  }
  let objdir = abspath(a.need("--obj"))
  makedirs(objdir)
  let j = if a.int("-j") > 0 { a.int("-j") } else { cpus() }
  let ext = if msvc { b".obj" } else { b".o" }
  let src = a.src()
  let mut link_flags : Array[Bytes] = []
  let jobs = if env_set_to("MBC_SPLIT", "0") {
    // the C whole, one unit (as before the split; for comparisons)
    let obj = path_join(objdir, cat([b"whole", ext]))
    let f = flags.copy()
    for x in gen_flags {
      f.push(x)
    }
    let (argv, dep) = compile_args(cc, f, abspath(src), obj, msvc)
    [Job::new(src, obj, argv, dep, 1L << 40, cc)]
  } else {
    let lto = lto_for(cc, j)
    let (jobs, _) = split_jobs(
      src,
      objdir,
      cc,
      flags,
      gen_flags,
      init_flags,
      msvc,
      lto is Some(_),
    )
    link_flags = lto.unwrap_or([])
    let _ = c_remove(path_join(objdir, cat([b"whole", ext])))
    jobs
  }
  let seen = BSet::new()
  let extras = a.list("--extra").map(fn(p) { (p, false) })
  for p in a.list("--optional") {
    extras.push((p, true))
  }
  for e in extras {
    let (path, optional) = e
    let base = basename(splitext(path).0)
    let mut name = base
    let mut k = 1
    while seen.has(name) {
      k += 1
      name = cat([base, bint(k)])
    }
    seen.add(name)
    let f = flags.copy()
    if ends(path, b".m") {
      for x in split_words(a.get("--objc-flags").unwrap_or(b"-fobjc-arc")) {
        f.push(x)
      }
    }
    let obj = path_join(objdir, cat([b"x_", name, ext]))
    let (argv, dep) = compile_args(cc, f, path, obj, msvc)
    let size = match stat(path) {
      Some(s) => s.0
      None => 0L
    }
    jobs.push(Job::new(path, obj, argv, dep, size, cc, optional~))
  }
  for o in run_jobs_c(jobs, j, basename(src)) {
    out_line(o)
  }
  match a.get("--link-flags") {
    // what the link of these objects needs (ThinLTO's flags), for the caller's link command
    Some(p) => {
      let _ = write_file(p, cat([quote_all(link_flags), b"\n"]))

    }
    None => ()
  }
}

// ---------------------------------------------------------------- link

///|
/// The files a link reads that it names (objects, archives; not its output) and `deps` (files, or directories:
/// their files)
fn link_inputs(argv : Array[Bytes], deps : Array[Bytes], out : Bytes) -> Array[Bytes] {
  let o = abspath(out)
  let files = argv.filter(fn(x) { is_file(x) && abspath(x) != o })
  for d in deps {
    if is_dir(d) {
      for f in walk_files(d) {
        files.push(f)
      }
    } else if is_file(d) {
      files.push(d)
    }
  }
  files
}

///|
fn link_key(argv : Array[Bytes], deps : Array[Bytes], out : Bytes) -> Bytes {
  let ins = sort_bytes(link_inputs(argv, deps, out))
  let buf = @buffer.new()
  buf.write_bytes(join_words(argv, b"\x1f"))
  buf.write_byte(b'\n')
  buf.write_bytes(tool_identity(argv[0:1].to_array()))
  buf.write_byte(b'\n')
  let mut last = b""
  for p in ins {
    if p == last {
      continue
    }
    last = p
    buf.write_bytes(p)
    buf.write_byte(b'\x1f')
    buf.write_bytes(file_hash(p).unwrap_or(b""))
    buf.write_byte(b'\n')
  }
  buf.to_bytes()
}

///|
/// Hundreds of split objects exceed Windows' process command-line limit. CL reads the same arguments from a
/// response file. Keep them on one line: /link applies only to the rest of its line in a CL command file.
fn msvc_link_command(argv : Array[Bytes], rsp : Bytes) -> Array[Bytes] {
  if !write_file(rsp, cat([list2cmdline(argv[1:].to_array()), b"\n"])) {
    fatal("cannot write link response file \{str(rsp)}")
  }
  [argv[0], cat([b"@", rsp])]
}

///|
/// Runs the link unless it made `out` of the same inputs already (then only its mtime moves on, for make-like tools
/// after it): its exit code
fn link(argv : Array[Bytes], out : Bytes, deps : Array[Bytes], stamp : Bytes?) -> Int {
  let st = match stamp {
    Some(s) => s
    None => cat([out, b".mbc-link"])
  }
  match read_file(st) {
    Some(k) if is_file(out) && k == link_key(argv, deps, out) => {
      let _ = c_touch(out)
      log("\{str(basename(out))}: linked already from the same objects and flags")
      return 0
    }
    _ => ()
  }
  let _ = c_remove(st)
  let t0 = now_s()
  let rsp = if is_msvc(argv) { Some(tmp_path("link.rsp")) } else { None }
  let command = match rsp {
    Some(p) => msvc_link_command(argv, p)
    None => argv
  }
  let code = run_inherit(command)
  if rsp is Some(p) {
    let _ = c_remove(p)
  }
  log("linked \{str(basename(out))} in \{secs(t0)} s")
  if code == 0 && is_file(out) {
    let _ = write_file(st, link_key(argv, deps, out))

  }
  code
}

///|
fn cmd_link(args : Array[String]) -> Unit {
  let a = parse_args(args, ["--out", "--stamp"], listed=["--dep"])
  let argv = if a.rest.length() > 0 { a.rest } else { a.pos }
  c_exit(link(argv, a.need("--out"), a.list("--dep"), a.get("--stamp")))
}

// ---------------------------------------------------------------- wrap

///|
/// What of a compile-and-link command concerns compiling (the rest is the link's)
fn gnu_compile_flags(args : ArrayView[Bytes]) -> Array[Bytes] {
  let out = []
  let mut i = 0
  let pairs = [
    b"-arch", b"-isysroot", b"-target", b"-include", b"-isystem", b"-iquote", b"-I",
    b"-D", b"-U",
  ]
  let prefixes = [
    b"-I", b"-D", b"-U", b"-f", b"-O", b"-g", b"-std=", b"-m", b"-W", b"-isysroot",
    b"-target=", b"-include",
  ]
  while i < args.length() {
    let x = args[i]
    if pairs.contains(x) {
      out.push(x)
      if i + 1 < args.length() {
        out.push(args[i + 1])
      }
      i += 2
      continue
    }
    if starts(x, b"-Wl,") ||
      starts(x, b"-l") ||
      starts(x, b"-L") ||
      starts(x, b"-framework") {
      i += if x == b"-framework" { 2 } else { 1 }
      continue
    }
    if prefixes.iter().any(fn(p) { starts(x, p) }) {
      out.push(x)
    }
    i += 1
  }
  out
}

///|
fn msvc_compile_flags(args : ArrayView[Bytes]) -> Array[Bytes] {
  let out = []
  let mut i = 0
  while i < args.length() {
    let x = args[i]
    let lx = lower(x)
    if lx == b"/link" || lx == b"-link" {
      break
    }
    if (lx == b"/i" ||
      lx == b"-i" ||
      lx == b"/d" ||
      lx == b"-d" ||
      lx == b"/u" ||
      lx == b"-u" ||
      lx == b"/fi" ||
      lx == b"-fi") &&
      i + 1 < args.length() {
      out.push(x)
      out.push(args[i + 1])
      i += 2
      continue
    }
    if x.length() > 0 &&
      (x[0] == b'/' || x[0] == b'-') &&
      !is_file(x) &&
      !(starts_at(lx, 1, b"fe") || starts_at(lx, 1, b"fo") || starts_at(lx, 1, b"link")) {
      out.push(x)
    }
    i += 1
  }
  out
}

///|
/// @FILE arguments (a long command line) as the arguments in them
fn response_files(args : Array[Bytes], msvc : Bool) -> Array[Bytes] {
  let out = []
  for x in args {
    if starts(x, b"@") && is_file(sub(x, 1, x.length())) {
      let mut t = read_file(sub(x, 1, x.length())).unwrap_or(b"")
      if starts(t, b"\xef\xbb\xbf") {
        t = sub(t, 3, t.length())
      }
      for w in split_words(t, posix=!msvc) {
        out.push(
          if msvc && w.length() > 1 && w[0] == b'"' && w[w.length() - 1] == b'"' {
            sub(w, 1, w.length() - 1)
          } else {
            w
          },
        )
      }
    } else {
      out.push(x)
    }
  }
  out
}

///|
/// A Windows path without the \\?\ moon puts before it (cl does not open those)
fn plain_path(p : Bytes) -> Bytes {
  if starts(p, b"\\\\?\\") {
    sub(p, 4, p.length())
  } else {
    p
  }
}

///|
fn cmd_wrap(args : Array[String]) -> Unit {
  let a = parse_args(args, ["--real"])
  let real_s = a.need("--real")
  let real = if is_file(real_s) { [real_s] } else { split_words(real_s) }
  let msvc = is_msvc(real)
  let rest = if a.rest.length() > 0 { a.rest } else { a.pos }
  let wargs = response_files(rest, msvc)
  let mut out : Bytes? = None
  for i, x in wargs {
    if x == b"-o" && i + 1 < wargs.length() {
      out = Some(wargs[i + 1])
    }
    // [/-]Fe:?(.+) and (?i)[/-]out:(.+)
    if x.length() > 3 && (x[0] == b'/' || x[0] == b'-') && x[1] == b'F' && x[2] == b'e' {
      let k = if x[3] == b':' { 4 } else { 3 }
      if k < x.length() {
        out = Some(sub(x, k, x.length()))
      }
    }
    let lx = lower(x)
    if lx.length() > 5 && (lx[0] == b'/' || lx[0] == b'-') && starts_at(lx, 1, b"out:") {
      out = Some(sub(x, 5, x.length()))
    }
  }
  let out = out.map(plain_path)
  let links = !wargs.iter().any(fn(x) {
    x == b"-c" || x == b"/c" || x == b"-E" || x == b"/E" || x == b"-dumpmachine"
  })
  let cs = []
  for i, x in wargs {
    if ends(x, b".c") && is_file(x) {
      cs.push(i)
    }
  }
  let whole = real.copy()
  for x in wargs {
    whole.push(x)
  }
  let pass = env_set_to("MBC_SPLIT", "0") ||
    !links ||
    (match out {
      Some(o) => !ends(o, b".exe")
      None => true
    }) ||
    cs.length() != 1
  if pass {
    if getenv("MBC_VERBOSE") is Some(_) {
      log("as is: \{str(join_words(whole, b" "))}")
    }
    c_exit(run_inherit(whole))
    return
  }
  let out = out.unwrap()
  // a test program its build said has no tests (MBC_EMPTY_TESTS: "pkg/name.kind …", apps/mbui/scripts/test.sh): moon
  // builds a package's internal, blackbox and whitebox programs whatever it has, each the whole app, and runs only
  // those with tests. Not compiled: in its place a file that is no program, so that one run anyway fails, said
  // (sfapp's two empty ones were 27 s of the app part's compile, sfreplay's 29 s of the replay part's, 2026-10-24)
  match getenv("MBC_EMPTY_TESTS") {
    Some(list) =>
      for e in split_words(list) {
        if ends(out, cat([b"/", e, b".exe"])) {
          let _ = write_file(out, b"mbc: a test program with no tests (MBC_EMPTY_TESTS), not built\n")
          log("\{str(e)}: no tests, not built")
          c_exit(0)
          return
        }
      }
    None => ()
  }
  let c_file = wargs[cs[0]]
  let objdir = cat([sub(out, 0, out.length() - 4), b".mbc"])
  makedirs(objdir)
  let flags0 = if msvc {
    msvc_compile_flags(wargs[:])
  } else {
    gnu_compile_flags(wargs[:])
  }
  // a test program of a few tests compiled less optimised (MBC_LIGHT_TESTS: "pkg/name.kind …", its level
  // MBC_LIGHT_OPT, -O0 by default, apps/mbui/scripts/test.sh): what it tests is the code, not how fast it runs. (The
  // library's and the settings' three, against -O2 on Studio: compiled in 9 s for 13, run as fast, 2026-10-25; -O1 12 s)
  let mut light = false
  match getenv("MBC_LIGHT_TESTS") {
    Some(list) if !msvc =>
      for e in split_words(list) {
        if ends(out, cat([b"/", e, b".exe"])) {
          light = true
        }
      }
    _ => ()
  }
  let flags = if light {
    let f = flags0.filter(fn(x) { !starts(x, b"-O") })
    f.push(getenv("MBC_LIGHT_OPT").unwrap_or(b"-O0"))
    f
  } else {
    flags0
  }
  let init_flags = default_init_flags(msvc)
  let j = match getenv("MBC_JOBS") {
    Some(v) if parse_int(strip(v)) > 0 => parse_int(strip(v))
    _ => cpus()
  }
  let lto = lto_for(real, j)
  let (jobs, _) = split_jobs(c_file, objdir, real, flags, [], init_flags, msvc, lto is Some(_))
  let objs = run_jobs_c(jobs, j, basename(c_file))
  let largs = wargs[0:cs[0]].to_array()
  for o in objs {
    largs.push(o)
  }
  for i in (cs[0] + 1)..<wargs.length() {
    largs.push(wargs[i])
  }
  let cmd = real.copy()
  for x in with_link_flags(largs, lto.unwrap_or([])) {
    cmd.push(x)
  }
  if msvc && lto is Some(_) {
    drop_brepro()
  }
  c_exit(link(cmd, out, [], None))
}

///|
/// DIR/cc (DIR/cl.exe on Windows) that moon finds first on PATH: `mbc wrap` over the real one
fn cmd_shim(args : Array[String]) -> Unit {
  if args.length() != 1 {
    fatal("shim: DIR")
  }
  let d = abspath(utf8(args[0]))
  makedirs(d)
  let path = path_list().filter(fn(p) { abspath(p) != d })
  if windows {
    let real = match getenv("MBC_REAL_CC") {
      Some(r) if r.length() > 0 => r
      _ =>
        match which(b"cl", dirs=path) {
          Some(r) => r
          None => {
            fatal("no cl.exe on PATH (a Developer Command Prompt, or ilammy/msvc-dev-cmd)")
            b""
          }
        }
    }
    // moon takes MSVC's lib.exe and link.exe from beside the cl.exe it finds: the same forwarder for them, each
    // running the command line in its .txt (cl's: mbc wrap over the real cl; lib's and link's: the real ones)
    //
    // Made again only when what it is made of changed, by content (its source, the real cl's file): moon builds anew
    // every C its compiler's mtime is newer than, and a checkout's mtimes are all new. By mtime, every CI run made it
    // again (~7 s) and with it every stub and moon's runtime (35 cl runs, ahead of moonc on the runner's four cores)
    // whose objects the cache had kept (still.fail's mbui.yml, 2026-10-24). /Brepro: the same source, the same .exe.
    let exe = path_join(d, b"mbc-cl.exe")
    let src = path_join(home(), b"mbc-cl.c")
    let made_of = path_join(d, b"mbc-cl.exe.src")
    let key = cat([
      file_hash(src).unwrap_or(b"no source"),
      b" ",
      tool_identity([real]),
    ])
    if !is_file(exe) || read_file(made_of) != Some(key) {
      let (code, said) = run_capture([
        real,
        b"/nologo",
        b"/O1",
        b"/Brepro",
        src,
        cat([b"/Fe", exe]),
        cat([b"/Fo", path_join(d, b"mbc-cl.obj")]),
        b"/link",
        b"/Brepro",
      ])
      if code != 0 {
        fatal("mbc-cl.c did not compile:\n\{str(said)}")
      }
      let _ = write_file(made_of, key)

    }
    let lines_of : Array[(Bytes, Array[Bytes])] = [
      (b"cl", [self_exe.val, b"wrap", b"--real", real, b"--"]),
    ]
    // (beside MSVC's cl: LLVM's clang-cl, MBC_REAL_CC, has none beside it, only lld-link and llvm-lib)
    let n = lower(basename(real))
    let tools = if n == b"clang-cl" || n == b"clang-cl.exe" {
      match which(b"cl", dirs=path) {
        Some(c) => dirname(c)
        None => dirname(real)
      }
    } else {
      dirname(real)
    }
    for tool in [b"lib", b"link"] {
      let t = path_join(tools, cat([tool, b".exe"]))
      if !is_file(t) {
        fatal("no \{str(t)} beside \{str(real)}")
      }
      // (lib's archive with no time stamps in it: the same objects, the same .lib, and the link that takes it found
      // made already)
      lines_of.push((tool, if tool == b"lib" { [t, b"/Brepro"] } else { [t] }))
    }
    for x in lines_of {
      let (tool, line) = x
      let t = path_join(d, cat([tool, b".exe"]))
      if !is_file(t) || file_hash(t) != file_hash(exe) {
        let _ = copyfile(exe, t)

      }
      let _ = write_if_changed(path_join(d, cat([tool, b".txt"])), list2cmdline(line))

    }
  } else {
    let real = match getenv("MBC_REAL_CC") {
      Some(r) if r.length() > 0 => r
      _ =>
        match which(b"cc", dirs=path) {
          Some(r) => r
          None => {
            fatal("no cc on PATH")
            b""
          }
        }
    }
    let sh = path_join(d, b"cc")
    // written only when it changes: moon builds anew what its C compiler's mtime is newer than
    let _ = write_if_changed(
      sh,
      cat([
        b"#!/bin/sh\n# mbui's mbc shim: moon's C compiler, mbc wrap over ",
        real,
        b"\nexec ",
        quote(self_exe.val),
        b" wrap --real ",
        quote(real),
        b" -- \"$@\"\n",
      ]),
    )
    let _ = c_chmod(sh, 0o755)
    // (Linux: moon takes its archiver from beside the C compiler it finds, as it does MSVC's lib.exe)
    if c_is_linux() != 0 {
      let t = path_join(d, b"ar")
      match which(b"ar", dirs=path) {
        Some(ar) if !exists(t) => {
          let _ = c_symlink(ar, t)

        }
        _ => ()
      }
    }
  }
  out_line(d)
}

// ---------------------------------------------------------------- check

///|
/// (defined global symbols, undefined ones) of an object
fn symbols(nm : Array[Bytes], obj : Bytes) -> (Array[Bytes], BSet) {
  let argv = nm.copy()
  argv.push(obj)
  let (code, out) = run_capture(argv)
  if code != 0 {
    fatal("\{str(join_words(nm, b" "))} \{str(obj)}: \{str(pyslice(out, 0, 300))}")
  }
  let defined = []
  let undefined = BSet::new()
  for l in lines(out) {
    let parts = split_words(l, posix=false)
    let n = parts.length()
    if n >= 3 &&
      parts[n - 2].length() == 1 &&
      contains(b"TDRBSCVW", parts[n - 2]) {
      defined.push(parts[n - 1])
    } else if n >= 2 &&
      (parts[n - 2] == b"U" || parts[n - 2] == b"w" || parts[n - 2] == b"v") {
      undefined.add(parts[n - 1])
    }
  }
  (defined, undefined)
}

///|
/// The C library's functions a compiler calls or folds as it optimises (memset for a loop, sin and cos as sincos):
/// _?(mem\w*|bzero|free|malloc|calloc|realloc|abort|str\w*|__\w+|(a?sinh?|…|hypot)[fl]?)$
fn is_libc(s : Bytes) -> Bool {
  let t = if starts(s, b"_") && !starts(s, b"__") { sub(s, 1, s.length()) } else { s }
  let words = (fn(x : Bytes) { x.iter().all(fn(c) { is_word(c) }) })
  for x in [t, s] {
    if (starts(x, b"mem") || starts(x, b"str") || starts(x, b"__")) && words(x) {
      return true
    }
    for w in [b"bzero", b"free", b"malloc", b"calloc", b"realloc", b"abort"] {
      if x == w {
        return true
      }
    }
    let base = if x.length() > 0 && (x[x.length() - 1] == b'f' || x[x.length() - 1] == b'l') {
      [x, sub(x, 0, x.length() - 1)]
    } else {
      [x]
    }
    for b in base {
      if (starts(b, b"exp") || starts(b, b"log")) && words(b) {
        return true
      }
      for w in [
        b"sin", b"sinh", b"asin", b"asinh", b"cos", b"cosh", b"acos", b"acosh", b"tan",
        b"tanh", b"atan", b"atanh", b"atan2", b"sincos", b"pow", b"sqrt", b"cbrt", b"floor",
        b"ceil", b"round", b"trunc", b"fabs", b"fmod", b"hypot",
      ] {
        if b == w {
          return true
        }
      }
    }
  }
  false
}

///|
fn cmd_check(args : Array[String]) -> Unit {
  let a = parse_args(args, ["--cc", "--cflags", "--init-flags", "--nm", "--obj", "-j"])
  let cc = split_words(a.need("--cc"))
  let flags = split_words(a.get("--cflags").unwrap_or(b""))
  let nm = split_words(a.get("--nm").unwrap_or(b"nm"))
  let objdir = abspath(a.need("--obj"))
  makedirs(objdir)
  let j = if a.int("-j") > 0 { a.int("-j") } else { cpus() }
  let src = a.src()
  let whole = path_join(objdir, b"whole.o")
  let (argv, dep) = compile_args(cc, flags, abspath(src), whole, false)
  let (jobs, made) = split_jobs(
    src,
    path_join(objdir, b"split"),
    cc,
    flags,
    [],
    split_words(a.get("--init-flags").unwrap_or(b"")),
    false,
    false,
  )
  jobs.push(Job::new(src, whole, argv, dep, 1L << 40, cc))
  let objs = run_jobs_c(jobs, j, b"check")
  let (one_l, one_needs) = symbols(nm, whole)
  let one = BSet::of(one_l)
  let many = []
  let needs = BSet::new()
  for o in objs {
    if o != whole {
      let (d, u) = symbols(nm, o)
      for x in d {
        many.push(x)
      }
      needs.add_all(u)
    }
  }
  let counts : Map[Bytes, Int] = Map::new()
  for x in many {
    counts[x] = counts.get_or_default(x, 0) + 1
  }
  let twice = []
  for x, k in counts {
    if k > 1 {
      twice.push(x)
    }
  }
  let split_set = BSet::of(many)
  let only_whole = one.minus(split_set).sorted()
  let mut only_split = split_set.minus(one).sorted()
  // and what they take from outside (the runtime, the host, libc) is the same too
  let needs2 = needs.minus(split_set)
  // (moonc's statics are globals in the split, kept when nothing calls them, as the whole file's are not: what
  // they take from outside the split may take alone; never the other way)
  let extra = if made.made_global.length() > 0 {
    needs2.minus(one_needs)
  } else {
    BSet::new()
  }
  let sym = needs2.minus(one_needs)
  sym.add_all(one_needs.minus(needs2))
  let needs_diff = sym.minus(extra).sorted().filter(fn(x) { !is_libc(x) })
  let libc_diff = sym.sorted().filter(fn(x) { is_libc(x) })
  // moonc's statics are globals in the split: only those may be in the split alone
  let mg = BSet::of(made.made_global)
  only_split = only_split.filter(fn(s) {
    let bare = if starts(s, b"_") { sub(s, 1, s.length()) } else { s }
    !mg.has(bare) && !mg.has(s)
  })
  let twice_s = sort_bytes(twice)
  log(
    "check: whole \{one.size()} global symbols, split \{split_set.size()} (\{many.length()} definitions); only whole \{only_whole.length()}, only split \{only_split.length()}, defined twice \{twice_s.length()}; \{one_needs.size()} taken from outside, \{needs_diff.length()} different" +
    (if extra.size() > 0 {
      " (\{extra.size()} more by moonc statics the whole file dropped)"
    } else {
      ""
    }) +
    (if libc_diff.length() > 0 {
      " (and the C library \{str(join_words(libc_diff, b", "))})"
    } else {
      ""
    }),
  )
  for x in [
    ("only in the whole", only_whole),
    ("only in the split", only_split),
    ("twice", twice_s),
    ("taken from outside by one only", needs_diff),
  ] {
    let (title, xs) = x
    for i in 0..<imin(20, xs.length()) {
      log("  \{title}: \{str(xs[i])}")
    }
  }
  let ok = only_whole.length() == 0 &&
    only_split.length() == 0 &&
    twice_s.length() == 0 &&
    needs_diff.length() == 0
  out_line(if ok { b"ok" } else { b"FAIL" })
  c_exit(if ok { 0 } else { 1 })
}

///|
/// The link's CL and LINK (cl hands CL's to the link it runs) without /Brepro: with it, the .iobj and .ipdb a link
/// writes never match again and /LTCG:INCREMENTAL generates every function anew (the objects compiled with it are
/// taken; 2026-10-22, the mbui-probe-ltcg runs 39730817781, 39730895939)
fn drop_brepro() -> Unit {
  for name in ["CL", "LINK"] {
    match getenv(name) {
      Some(v) => {
        let ws = split_words(v).filter(fn(w) {
          let l = lower(w)
          l != b"/brepro" && l != b"-brepro"
        })
        let _ = c_setenv(utf8(name), join_words(ws, b" "))

      }
      None => ()
    }
  }
}
