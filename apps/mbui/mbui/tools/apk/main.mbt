// An Android app's APK without Gradle (scripts/apk, which builds this): its Java compiled, shrunk by R8, its
// resources and manifest linked by aapt2, its native libraries and assets packed, aligned and signed, with the SDK's
// own tools (and R8 at a version pinned here). What scripts/apk.py did, in MoonBit (2026-10-23: tools are MoonBit).
//
//     apk lock APP.json             its dependencies (APP.json's "lock": group:artifact:version a line) fetched once
//                                   and their SHA-256 written beside each, so builds take those bytes and no others
//     apk build APP.json --variant release|debug --version-code N --version-name S --out APP.apk
//                                   [--abi arm64-v8a] [--keystore PATH]
//     apk fetch PATH SHA256         a file of the Maven repositories (its path in one), checked, kept: its local path
//
// APP.json (paths relative to it): "namespace" (its Java package, R's), "applicationId", "minSdk", "targetSdk",
// "compileSdk", "manifest", "java" [dirs], "res" [dirs], "assets" [dirs], "jniLibs" [dirs], "rules" [R8 files],
// "lock" (the dependencies' file), "merged" [group:artifact prefixes: libraries whose manifests' components the app's
// manifest has merged by hand], "variants": {"release"|"debug": {"applicationIdSuffix", "placeholders": {…},
// "minify": bool, "debuggable": bool}}, "strings": {resource name: [env var naming a JSON file, its key]} (values put
// in as string resources: what is secret to the build, read by the app as it starts).
//
// Why: Gradle's release build (AGP 9) ran R8 and lint again on every build, as the versionCode (main's commit count)
// is in the manifest R8 reads for its resource shrinking, and its cache could never be hit: most of CI's minute of
// Gradle (2026-10-22). Here R8's output is kept by what it is made of (the classes, the dependencies, the rules, R8's
// version), the build's number only in the manifest linked at the end. The manifest is the app's with its placeholders
// filled and its components' names made whole, and what its libraries' manifests add to <application> (attributes
// alone: one with anything else stops this, rather than a merge it does not do, unless the app's manifest has merged
// it by hand: "merged"). The libraries' resources are linked beside the app's (R classes for each package); resources
// are not shrunk; stripped of nothing, the native libraries compressed (extractNativeLibs), as the release had them.
//
// Tools: $ANDROID_HOME's platforms/android-<compileSdk>/android.jar and the newest build-tools' aapt2, zipalign and
// apksigner; java and javac (17 or newer); R8 from Google's Maven at r8_version; curl, unzip, zip and shasum (or
// sha256sum). Everything fetched is kept in $APK_CACHE (default ~/.cache/mbui-apk) by its content's hash.

///|
let r8_version : String = "9.0.55"

///|
let repos : Array[String] = ["https://dl.google.com/dl/android/maven2", "https://repo1.maven.org/maven2"]

// ── the system ──────────────────────────────────────────────────────────

///|
fn say(msg : String) -> Unit {
  @sys.println_out("apk: " + msg)
}

///|
fn die(msg : String) -> Unit {
  @sys.eprintln("apk: " + msg)
  @sys.exit(1)
}

///|
/// A word of a shell command, quoted.
fn q(s : String) -> String {
  "'" + s.replace_all(old="'", new="'\\''") + "'"
}

///|
/// A command's output (its stdout and stderr), None when it did not end with 0.
fn try_sh(cmd : String) -> String? {
  @sys.run_out(cmd + " 2>&1")
}

///|
/// A command that must end with 0: its output, or what it said and a stop.
fn sh(cmd : String, what : String) -> String {
  match try_sh(cmd) {
    Some(out) => out
    None => {
      // (again, for what it said: run_out keeps no output of one that failed)
      let said = @sys.run_out("(" + cmd + ") 2>&1; true").unwrap_or("")
      @sys.eprintln(said)
      die("\{what} failed: " + sub(cmd, 0, @cmp.minimum(cmd.length(), 200)) + " …")
      ""
    }
  }
}

///|
/// `s` from `a` to `b` (UTF-16 offsets).
fn sub(s : String, a : Int, b : Int) -> String {
  s.view(start_offset=a, end_offset=b).to_string()
}

///|
fn home() -> String {
  @sys.getenv("HOME").unwrap_or("/tmp")
}

///|
fn sha256_file(path : String) -> String {
  let tool = if @sys.run_out("command -v shasum") is Some(_) { "shasum -a 256" } else { "sha256sum" }
  let out = sh(tool + " " + q(path), "sha256")
  match out.split(" ").next() {
    Some(h) => h.to_string()
    None => ""
  }
}

///|
/// A SHA-256 of words (cache keys).
fn sha256_text(text : String, at : String) -> String {
  let f = at + ".key"
  ignore(@sys.write_text(f, text))
  let h = sha256_file(f)
  ignore(@sys.remove(f))
  h
}

///|
fn cache_dir() -> String {
  let d = match @sys.getenv("APK_CACHE") {
    Some(d) if d != "" => d
    _ => @sys.join(home(), ".cache/mbui-apk")
  }
  @sys.makedirs(d)
  d
}

///|
/// `url` into `dest`; false where the repository has no such file. (Once: what is fetched is kept in the cache, CI's by
/// its Actions cache, so a build fetches only what a change of the lock asks for.) A name of its own (Maven Central
/// turns some default agents away); Google's Maven answers 403 for what it does not have: the next repository's.
fn fetch(url : String, dest : String) -> Bool {
  let tmp = dest + ".part"
  match try_sh("curl -fsSL --retry 2 --max-time 300 -A mbui-apk/1 -o " + q(tmp) + " " + q(url)) {
    Some(_) => {
      ignore(sh("mv -f " + q(tmp) + " " + q(dest), "mv"))
      true
    }
    None => {
      ignore(@sys.remove(tmp))
      false
    }
  }
}

///|
fn artifact_path(coord : String, ext : String) -> String {
  let p = coord.split(":").map(fn(x) { x.to_string() }).to_array()
  let g = p[0].replace_all(old=".", new="/")
  "\{g}/\{p[1]}/\{p[2]}/\{p[1]}-\{p[2]}.\{ext}"
}

///|
/// The artifact coord.ext, from the cache or the repositories; checked against `sha` when given.
fn get_artifact(coord : String, ext : String, sha? : String = "") -> String? {
  let dest = @sys.join(cache_dir(), "m2/" + coord.replace_all(old=":", new="_") + "." + ext)
  @sys.makedirs(@sys.dirname(dest))
  if !@sys.exists(dest) {
    if !repos.iter().any(fn(r) { fetch(r + "/" + artifact_path(coord, ext), dest) }) {
      return None
    }
  }
  if sha != "" && sha256_file(dest) != sha {
    ignore(@sys.remove(dest))
    die("\{coord}.\{ext}: not the SHA-256 the lock has (\{sha})")
  }
  Some(dest)
}

///|
fn cmd_fetch(path : String, sha : String) -> Unit {
  let dest = @sys.join(cache_dir(), "m2/" + path.replace_all(old="/", new="_"))
  @sys.makedirs(@sys.dirname(dest))
  if !@sys.exists(dest) && !repos.iter().any(fn(r) { fetch(r + "/" + path, dest) }) {
    die("\{path}: not found")
  }
  if sha256_file(dest) != sha {
    ignore(@sys.remove(dest))
    die("\{path}: not the SHA-256 asked for (\{sha})")
  }
  @sys.println_out(dest)
}

// ── the dependencies' lock ─────────────────────────────────────────────

///|
/// The lock's lines (group:artifact:version [ext sha256]), # comments left out.
fn read_lock(path : String) -> Array[(String, String, String)] {
  let out = []
  let text = @sys.read_text(path).unwrap_or("")
  for raw in text.split("\n") {
    let line = match raw.find("#") {
      Some(i) => raw.view(end_offset=i).trim(chars=" \t\r").to_string()
      None => raw.trim(chars=" \t\r").to_string()
    }
    if line == "" {
      continue
    }
    let parts = line.split(" ").filter(fn(x) { x != "" }).map(fn(x) { x.to_string() }).to_array()
    out.push((parts[0], parts.get(1).unwrap_or(""), parts.get(2).unwrap_or("")))
  }
  out
}

///|
fn cmd_lock(app : String) -> Unit {
  let (cfg, base) = load(app)
  let path = @sys.join(base, text_of(cfg, "lock"))
  let head = @sys.read_text(path).unwrap_or("").split("\n").filter(fn(l) { l.has_prefix("#") }).map(fn(l) {
    l.to_string()
  }).to_array()
  let lines = []
  for d in read_lock(path) {
    let coord = d.0
    let mut done = false
    for ext in ["aar", "jar"] {
      match get_artifact(coord, ext) {
        Some(p) => {
          lines.push("\{coord} \{ext} \{sha256_file(p)}")
          done = true
          break
        }
        None => ()
      }
    }
    if !done {
      // a BOM, or a root of Kotlin's multiplatform: nothing to pack
      lines.push("\{coord} none")
    }
  }
  ignore(@sys.write_text(path, (head + lines).join("\n") + "\n"))
  say("\{path}: \{lines.length()} dependencies")
}

// ── the build ──────────────────────────────────────────────────────────

///|
fn load(app : String) -> (@rjson.Value, String) {
  let text = @sys.read_text(app).unwrap_or("")
  let cfg = @rjson.parse(text) catch {
    _ => {
      die("\{app}: not JSON")
      @rjson.Value::Null
    }
  }
  (cfg, @sys.dirname(@sys.abspath(app)))
}

///|
fn text_of(v : @rjson.Value, key : String) -> String {
  match v.get(key) {
    Some(Str(s)) => s
    Some(Num(n)) => n
    _ => ""
  }
}

///|
fn texts_of(v : @rjson.Value, key : String) -> Array[String] {
  match v.get(key) {
    Some(Arr(a)) => a.filter_map(fn(x) { x.str() })
    _ => []
  }
}

///|
fn flag_of(v : @rjson.Value, key : String) -> Bool {
  v.get(key) is Some(Bool(true))
}

///|
fn sdk() -> String {
  match @sys.getenv("ANDROID_HOME") {
    Some(s) if s != "" => s
    _ =>
      match @sys.getenv("ANDROID_SDK_ROOT") {
        Some(s) if s != "" => s
        _ => @sys.join(home(), "Library/Android/sdk")
      }
  }
}

///|
/// A whole number's digits (anything else: 0).
fn int_of(s : String) -> Int {
  let mut n = 0
  for ch in s {
    if ch < '0' || ch > '9' {
      return 0
    }
    n = n * 10 + (ch.to_int() - '0'.to_int())
  }
  n
}

///|
/// A version's numbers, compared as numbers.
fn version_cmp(a : String, b : String) -> Int {
  let na = a.split(".").map(fn(x) { int_of(x.to_string()) }).to_array()
  let nb = b.split(".").map(fn(x) { int_of(x.to_string()) }).to_array()
  for i in 0..<@cmp.maximum(na.length(), nb.length()) {
    let x = na.get(i).unwrap_or(0)
    let y = nb.get(i).unwrap_or(0)
    if x != y {
      return x.compare(y)
    }
  }
  0
}

///|
/// android.jar of `compile_sdk` and the newest build-tools.
fn sdk_tools(compile_sdk : String) -> (String, String) {
  let jar = @sys.join(sdk(), "platforms/android-\{compile_sdk}/android.jar")
  if !@sys.exists(jar) {
    die("no \{jar}")
  }
  let num = @re.Regex::new("^\\d+\\.\\d+\\.\\d+$") catch { _ => panic() }
  let bts = @sys.list_dir(@sys.join(sdk(), "build-tools")).filter(fn(d) { num.matches(d) })
  if bts.length() == 0 {
    die("no build-tools in \{sdk()}")
  }
  bts.sort_by(version_cmp)
  (jar, @sys.join(sdk(), "build-tools/" + bts[bts.length() - 1]))
}

///|
/// An AAR unpacked once into the cache (by its hash): its classes, libraries, res, manifest, rules, R.txt.
fn extract_aar(path : String, sha : String) -> String {
  let d = @sys.join(cache_dir(), "aar/" + sub(sha, 0, 24))
  if !@sys.exists(@sys.join(d, ".done")) {
    ignore(try_sh("rm -rf " + q(d)))
    @sys.makedirs(d)
    ignore(sh("unzip -q -o " + q(path) + " -d " + q(d), "unzip"))
    ignore(@sys.write_text(@sys.join(d, ".done"), ""))
  }
  d
}

///|
/// A hash of the files under `paths` (their paths below each and contents), in order.
fn tree_hash(paths : Array[String], at : String) -> String {
  let parts = []
  for base in paths {
    if @sys.is_file(base) {
      parts.push("F" + base + " " + sha256_file(base))
    } else if @sys.is_dir(base) {
      let tool = if @sys.run_out("command -v shasum") is Some(_) { "shasum -a 256" } else { "sha256sum" }
      parts.push(
        "D" +
        sh("cd " + q(base) + " && find . -type f | LC_ALL=C sort | while IFS= read -r f; do " + tool + " \"$f\"; done", "hash"),
      )
    }
  }
  sha256_text(parts.join("\n"), at)
}

///|
/// The build's string resources from the environment (cfg "strings"), as a values file under `d`.
fn write_strings(cfg : @rjson.Value, d : String) -> Unit {
  let vals = []
  match cfg.get("strings") {
    Some(Obj(kvs)) => {
      let sorted = kvs.copy()
      sorted.sort_by(fn(a, b) { @rjson.str_cmp(a.0, b.0) })
      for kv in sorted {
        let (name, spec) = kv
        let (env_var, key) = match spec {
          Arr([Str(v), Str(k)]) => (v, k)
          _ => ("", "")
        }
        let mut v = ""
        match @sys.getenv(env_var) {
          Some(p) if p != "" && @sys.exists(p) => {
            let j = @rjson.parse(@sys.read_text(p).unwrap_or("")) catch { _ => @rjson.Value::Null }
            v = match j.get(key) {
              Some(Str(s)) => s
              Some(Num(n)) => n
              Some(Bool(b)) => if b { "True" } else { "False" }
              _ => ""
            }
          }
          _ => ()
        }
        let v = v
          .replace_all(old="\\", new="\\\\")
          .replace_all(old="\"", new="\\\"")
          .replace_all(old="&", new="&amp;")
          .replace_all(old="<", new="&lt;")
          .replace_all(old="'", new="\\'")
        vals.push("  <string name=\"\{name}\" translatable=\"false\">\{v}</string>")
      }
    }
    _ => ()
  }
  @sys.makedirs(@sys.join(d, "values"))
  ignore(
    @sys.write_text(
      @sys.join(d, "values/build_strings.xml"),
      "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<resources>\n" + vals.join("\n") + "\n</resources>\n",
    ),
  )
}

///|
fn rx(p : String) -> @re.Regex {
  @re.Regex::new(p) catch {
    _ => panic()
  }
}

///|
/// The app's manifest as it goes to aapt2: placeholders filled, its components' names whole, tools: gone, and what the
/// libraries' manifests put on <application> (their permissions too, those the app does not ask for).
fn manifest_text(
  cfg : @rjson.Value,
  base : String,
  variant : @rjson.Value,
  app_id : String,
  libs : Array[(String, String)],
) -> String {
  let mut text = @sys.read_text(@sys.join(base, text_of(cfg, "manifest"))).unwrap_or("")
  let ph : Array[(String, String)] = match variant.get("placeholders") {
    Some(Obj(kvs)) => kvs.filter_map(fn(kv) { kv.1.str().map(fn(s) { (kv.0, s) }) })
    _ => []
  }
  ph.push(("applicationId", app_id))
  for kv in ph {
    text = text.replace_all(old="${" + kv.0 + "}", new=kv.1)
  }
  let left = rx("\\$\\{(\\w+)\\}").findall(text)
  if left.length() > 0 {
    die("manifest placeholders not given: \{left}")
  }
  let ns = text_of(cfg, "namespace")
  text = rx("(<(?:application|activity|activity-alias|service|receiver|provider)\\b[^>]*?android:name=\")\\.").sub_with(
    text,
    fn(m) { m.get(1) + ns + "." },
  )
  text = rx("\\s+tools:\\w+=\"[^\"]*\"").sub(text, "")
  text = rx("\\s+xmlns:tools=\"[^\"]*\"").sub(text, "")
  let merged = texts_of(cfg, "merged")
  // the libraries' <application> attributes (androidx.core's appComponentFactory), not those the app sets, and the
  // permissions they ask for that the app does not
  let added : Array[(String, String)] = []
  let permissions : Array[String] = []
  let comment = @re.Regex::new("<!--.*?-->", flags={ ..@re.no_flags, dotall: true }) catch { _ => panic() }
  let app_rx = @re.Regex::new("<application\\b([^>]*?)(/>|>(.*?)</application>)", flags={ ..@re.no_flags, dotall: true }) catch {
    _ => panic()
  }
  for lib in libs {
    let (name, d) = lib
    let mpath = @sys.join(d, "AndroidManifest.xml")
    if !@sys.exists(mpath) {
      continue
    }
    let lm = comment.sub(@sys.read_text(mpath).unwrap_or(""), "")
    let mut body = rx("<\\?xml[^>]*>").sub(lm, "")
    body = rx("<manifest\\b[^>]*>|</manifest>|<uses-sdk\\b[^>]*/>").sub(body, "")
    let app = app_rx.search(body)
    let mut rest = match app {
      Some(m) => body.replace(old=m.get(0), new="")
      None => body
    }
    // (a permission it asks for: the app's own too, once)
    for perm in rx("<uses-permission\\b[^>]*/>").findall(rest) {
      match rx("android:name=\"([^\"]+)\"").search(perm) {
        Some(m) if !text.contains("android:name=\"" + m.get(1) + "\"") => permissions.push(perm)
        _ => ()
      }
      rest = rest.replace_all(old=perm, new="")
    }
    let inner = match app {
      Some(m) => m.group(g=3).unwrap_or("")
      None => ""
    }
    // (one the app's manifest has merged by hand, APP.json's "merged": its components there as the app wants them)
    let by_hand = merged.iter().any(fn(p) { name.has_prefix(p) })
    if (rest.trim(chars=" \t\r\n") != "" || inner.trim(chars=" \t\r\n") != "") && !by_hand {
      die("\{name}: its manifest adds more than <application> attributes; merge it here first:\n" + body.trim(chars=" \t\r\n").to_string())
    }
    match app {
      Some(m) =>
        for a in rx("(android:\\w+)=\"([^\"]*)\"").find_all(m.get(1)) {
          if !added.iter().any(fn(x) { x.0 == a.get(1) }) {
            added.push((a.get(1), a.get(2)))
          }
        }
      None => ()
    }
  }
  let app_open = match rx("<application\\b[^>]*").search(text) {
    Some(m) => m
    None => {
      die("no <application> in the manifest")
      panic()
    }
  }
  let have = rx("(android:\\w+)=").find_all(app_open.get(0)).map(fn(m) { m.get(1) })
  added.sort_by(fn(a, b) { @rjson.str_cmp(a.0, b.0) })
  let mut extra = ""
  for kv in added {
    if !have.contains(kv.0) {
      extra = extra + " \{kv.0}=\"\{kv.1}\""
    }
  }
  if !have.contains("android:extractNativeLibs") {
    extra = extra + " android:extractNativeLibs=\"true\""
  }
  if flag_of(variant, "debuggable") {
    extra = extra + " android:debuggable=\"true\""
  }
  text = sub(text, 0, app_open.end()) + extra + sub(text, app_open.end(), text.length())
  // its package: the application id (the namespace is R's and the components' names')
  match rx("<manifest\\b").search(text) {
    Some(m) => text = sub(text, 0, m.start()) + "<manifest package=\"\{app_id}\"" + sub(text, m.end(), text.length())
    None => ()
  }
  if permissions.length() > 0 {
    let at = text.find("<application").unwrap_or(0)
    let seen = []
    let mut add = ""
    for p in permissions {
      if !seen.contains(p) {
        seen.push(p)
        add = add + p + "\n    "
      }
    }
    text = sub(text, 0, at) + add + sub(text, at, text.length())
  }
  text
}

///|
/// The NDK's llvm-strip (the newest NDK's), as AGP strips a release's native libraries with.
fn llvm_strip() -> String {
  let nd = @sys.join(sdk(), "ndk")
  let ndks = if @sys.is_dir(nd) { @sys.list_dir(nd) } else { [] }
  ndks.sort_by(fn(a, b) { version_cmp(b, a) })
  for n in ndks {
    for host in ["darwin-x86_64", "linux-x86_64", "windows-x86_64"] {
      let p = @sys.join(nd, "\{n}/toolchains/llvm/prebuilt/\{host}/bin/llvm-strip")
      if @sys.exists(p) {
        return p
      }
    }
  }
  die("no NDK llvm-strip in \{nd}")
  ""
}

///|
/// `path` with its debug symbols stripped (--strip-unneeded, as AGP's stripReleaseDebugSymbols), kept by its content's
/// hash.
fn stripped(path : String) -> String {
  let out = @sys.join(cache_dir(), "strip/" + sub(sha256_file(path), 0, 32) + ".so")
  if @sys.exists(out) {
    ignore(try_sh("touch " + q(out)))
  } else {
    @sys.makedirs(@sys.dirname(out))
    ignore(sh(q(llvm_strip()) + " --strip-unneeded -o " + q(out + ".tmp") + " " + q(path), "llvm-strip"))
    ignore(sh("mv -f " + q(out + ".tmp") + " " + q(out), "mv"))
  }
  out
}

///|
/// classes.dex, then classes2.dex, classes3.dex… in their number's order.
fn dex_names(dir : String) -> Array[String] {
  let names = @sys.list_dir(dir).filter(fn(n) { n.has_prefix("classes") && n.has_suffix(".dex") })
  let num = fn(n : String) -> Int {
    let mid = sub(n, 7, n.length() - 4)
    if mid == "" {
      1
    } else {
      int_of(mid)
    }
  }
  names.sort_by(fn(a, b) { num(a).compare(num(b)) })
  names.map(fn(n) { @sys.join(dir, n) })
}

///|
/// A dependency's jar dexed (D8, debug) once, kept by its bytes, R8's version and the API level.
fn lib_dex(r8 : String, android_jar : String, min_api : String, jar : String, others : Array[String], work : String) -> String {
  let key = sub(sha256_text("\{sha256_file(jar)} \{r8_version} \{min_api}", work + "/libkey"), 0, 32)
  let d = @sys.join(cache_dir(), "dexlib/" + key)
  if !@sys.exists(@sys.join(d, ".done")) {
    ignore(try_sh("rm -rf " + q(d)))
    @sys.makedirs(d)
    let cp = others.map(fn(o) { "--classpath " + q(o) }).join(" ")
    ignore(
      sh(
        "java -cp " + q(r8) + " com.android.tools.r8.D8 --debug --min-api " + min_api + " --lib " + q(android_jar) +
        " --output " + q(d) + " " + q(jar) + " " + cp,
        "d8",
      ),
    )
    ignore(@sys.write_text(@sys.join(d, ".done"), ""))
  }
  d
}

///|
/// The cache kept small: the newest 6 dex outputs, the newest 24 stripped libraries.
fn prune() -> Unit {
  for kv in [("dex", 6), ("strip", 24)] {
    let d = @sys.join(cache_dir(), kv.0)
    if @sys.is_dir(d) {
      ignore(try_sh("cd " + q(d) + " && ls -t | tail -n +\{kv.1 + 1} | while IFS= read -r n; do rm -rf \"$n\"; done"))
    }
  }
}

///|
/// Every file under `dir`, sorted (a path below it, its path).
fn files_under(dir : String) -> Array[String] {
  if !@sys.is_dir(dir) {
    return []
  }
  let out = sh("cd " + q(dir) + " && find . -type f | LC_ALL=C sort", "find")
  out
  .split("\n")
  .filter(fn(l) { l.has_prefix("./") })
  .map(fn(l) { sub(l.to_string(), 2, l.length()) })
  .to_array()
}

///|
fn now_s() -> Double {
  @env.now().to_double() / 1000.0
}

///|
fn secs(x : Double) -> String {
  let t = (x * 10.0).round() / 10.0
  let s = t.to_string()
  if s.contains(".") {
    s
  } else {
    s + ".0"
  }
}

///|
priv struct BuildArgs {
  app : String
  variant : String
  version_code : String
  version_name : String
  out : String
  abi : String
  keystore : String
}

///|
fn cmd_build(a : BuildArgs) -> Unit {
  let t0 = now_s()
  let times : Array[(String, Double)] = []
  let mut t = t0
  let lap = fn(what : String, since : Double) -> Double {
    let n = now_s()
    times.push((what, n - since))
    n
  }
  let (cfg, base) = load(a.app)
  let variant = match cfg.get("variants") {
    Some(v) =>
      match v.get(a.variant) {
        Some(x) => x
        None => {
          die("no variant \{a.variant} in \{a.app}")
          @rjson.Value::Null
        }
      }
    None => @rjson.Value::Null
  }
  let app_id = text_of(cfg, "applicationId") + text_of(variant, "applicationIdSuffix")
  let minify = flag_of(variant, "minify")
  let min_sdk = text_of(cfg, "minSdk")
  let (android_jar, bt) = sdk_tools(text_of(cfg, "compileSdk"))
  let aapt2 = @sys.join(bt, "aapt2")
  let work = sh("mktemp -d -t apk-XXXXXX", "mktemp").trim(chars=" \n").to_string()
  // the dependencies: AARs unpacked (classes, their res), jars as they are
  let deps = read_lock(@sys.join(base, text_of(cfg, "lock"))).filter(fn(d) { d.1 != "" && d.1 != "none" })
  let jars : Array[String] = []
  let libs : Array[(String, String)] = []
  let rules : Array[String] = []
  for dep in deps {
    let (coord, ext, sha) = dep
    let p = match get_artifact(coord, ext, sha~) {
      Some(p) => p
      None => {
        die("\{coord}.\{ext}: not found")
        ""
      }
    }
    if ext == "jar" {
      jars.push(p)
      continue
    }
    let d = extract_aar(p, sha)
    libs.push((coord, d))
    let inner = [@sys.join(d, "classes.jar")]
    let ld = @sys.join(d, "libs")
    if @sys.is_dir(ld) {
      let names = @sys.list_dir(ld)
      names.sort_by(@rjson.str_cmp)
      for n in names {
        inner.push(@sys.join(ld, n))
      }
    }
    for j in inner {
      if @sys.exists(j) {
        jars.push(j)
      }
    }
    if @sys.exists(@sys.join(d, "proguard.txt")) {
      rules.push(@sys.join(d, "proguard.txt"))
    }
  }
  t = lap("dependencies", t)
  // resources: each library's compiled once (by its own content), the app's and the build's strings each time
  let strings = @sys.join(work, "strings")
  write_strings(cfg, strings)
  let compiled = []
  let lib_packages = []
  let pkg_rx = rx("package=\"([^\"]+)\"")
  for lib in libs {
    let d = lib.1
    let res = @sys.join(d, "res")
    if !@sys.is_dir(res) || @sys.list_dir(res).length() == 0 {
      continue
    }
    match pkg_rx.search(@sys.read_text(@sys.join(d, "AndroidManifest.xml")).unwrap_or("")) {
      Some(m) => lib_packages.push(m.get(1))
      None => ()
    }
    let out = @sys.join(cache_dir(), "flat/" + sub(tree_hash([res], work + "/flatkey"), 0, 24) + ".zip")
    if !@sys.exists(out) {
      @sys.makedirs(@sys.dirname(out))
      ignore(sh(q(aapt2) + " compile --dir " + q(res) + " -o " + q(out + ".tmp"), "aapt2 compile"))
      ignore(sh("mv -f " + q(out + ".tmp") + " " + q(out), "mv"))
    }
    compiled.push(out)
  }
  let app_flat = []
  let res_dirs = texts_of(cfg, "res").map(fn(r) { @sys.join(base, r) })
  res_dirs.push(strings)
  for i, res in res_dirs {
    if @sys.is_dir(res) {
      let out = @sys.join(work, "app\{i}.zip")
      ignore(sh(q(aapt2) + " compile --dir " + q(res) + " -o " + q(out), "aapt2 compile"))
      app_flat.push(out)
    }
  }
  t = lap("resources compiled", t)
  // the manifest, linked with everything: resources.arsc, res/, the binary manifest, R.java, the rules it keeps
  let man = @sys.join(work, "AndroidManifest.xml")
  ignore(@sys.write_text(man, manifest_text(cfg, base, variant, app_id, libs)))
  let gen = @sys.join(work, "gen")
  let ap = @sys.join(work, "res.ap_")
  let aapt_rules = @sys.join(work, "aapt_rules.txt")
  let mut link = q(aapt2) + " link -I " + q(android_jar) + " --manifest " + q(man) + " -o " + q(ap) + " --java " +
    q(gen) + " --proguard " + q(aapt_rules) + " --min-sdk-version " + min_sdk + " --target-sdk-version " +
    text_of(cfg, "targetSdk") + " --version-code " + a.version_code + " --version-name " + q(a.version_name) +
    " --custom-package " + q(text_of(cfg, "namespace")) + " --auto-add-overlay --no-version-vectors"
  if lib_packages.length() > 0 {
    let uniq = []
    for p in lib_packages {
      if !uniq.contains(p) {
        uniq.push(p)
      }
    }
    uniq.sort_by(@rjson.str_cmp)
    link = link + " --extra-packages " + q(uniq.join(":"))
  }
  for c in compiled {
    link = link + " -R " + q(c)
  }
  for c in app_flat {
    link = link + " -R " + q(c)
  }
  ignore(sh(link, "aapt2 link"))
  t = lap("linked", t)
  // dex: javac, then R8 (release) or D8, kept by what they are made of: the Java's sources (the app's and R's), the
  // dependencies, the rules, the tools (not the manifest: the build's number is in it); kept, neither runs
  let srcs = []
  let java_dirs = texts_of(cfg, "java").map(fn(j) { @sys.join(base, j) })
  java_dirs.push(gen)
  for d in java_dirs {
    for f in files_under(d) {
      if f.has_suffix(".java") {
        srcs.push(@sys.join(d, f))
      }
    }
  }
  let r8 = match get_artifact("com.android.tools:r8:\{r8_version}", "jar") {
    Some(p) => p
    None => {
      die("no R8 \{r8_version}")
      ""
    }
  }
  let all_rules = texts_of(cfg, "rules").map(fn(r) { @sys.join(base, r) }) + rules
  let default_rules = @sys.join(@sys.getenv("APK_HOME").unwrap_or("."), "apk-proguard-android-optimize.txt")
  // (aapt2's rules say where each came from: this build's own temporary paths, not what they keep)
  let kept = @sys.read_text(aapt_rules)
    .unwrap_or("")
    .split("\n")
    .filter(fn(l) { !l.trim(chars=" \t").has_prefix("#") })
    .map(fn(l) { l.to_string() })
    .to_array()
    .join("\n")
  ignore(@sys.write_text(aapt_rules, kept))
  let key = []
  key.push("\{r8_version} \{minify} \{min_sdk} \{a.variant} \{@sys.getenv("JAVA_HOME").unwrap_or("")}")
  for p in srcs {
    key.push(@sys.basename(p) + " " + sha256_file(p))
  }
  for p in jars + all_rules + [default_rules, android_jar] {
    key.push(sha256_file(p))
  }
  key.push(kept)
  let dex_dir = @sys.join(cache_dir(), "dex/" + sub(sha256_text(key.join("\n"), work + "/dexkey"), 0, 32))
  if !@sys.exists(@sys.join(dex_dir, ".done")) {
    let classes = @sys.join(work, "classes")
    @sys.makedirs(classes)
    ignore(@sys.write_text(@sys.join(work, "srcs.txt"), srcs.join("\n")))
    let cp = ([android_jar] + jars).join(":")
    ignore(
      sh(
        "javac -nowarn -encoding UTF-8 -source 17 -target 17 -Xlint:-options -cp " + q(cp) + " -d " + q(classes) + " @" +
        q(@sys.join(work, "srcs.txt")),
        "javac",
      ),
    )
    t = lap("javac", t)
    ignore(try_sh("rm -rf " + q(dex_dir)))
    @sys.makedirs(dex_dir)
    let jar_in = @sys.join(work, "app-classes.jar")
    ignore(sh("cd " + q(classes) + " && find . -type f | LC_ALL=C sort | zip -q -X " + q(jar_in) + " -@", "zip classes"))
    let cmd = if minify {
      "java -cp " + q(r8) + " com.android.tools.r8.R8 --release --min-api " + min_sdk + " --lib " + q(android_jar) +
      " --output " + q(dex_dir) + " --pg-conf " + q(default_rules) + " --pg-conf " + q(aapt_rules) +
      " --pg-map-output " + q(@sys.join(dex_dir, "mapping.txt")) +
      all_rules.map(fn(r) { " --pg-conf " + q(r) }).join("") + " " + q(jar_in) + " " + jars.map(q).join(" ")
    } else {
      // (debug: the app's own classes alone, the dependencies on their classpath: they are dexed apart, below)
      "java -cp " + q(r8) + " com.android.tools.r8.D8 --debug --min-api " + min_sdk + " --lib " + q(android_jar) +
      " --output " + q(dex_dir) + " " + q(jar_in) + jars.map(fn(j) { " --classpath " + q(j) }).join("")
    }
    ignore(sh(cmd, if minify { "r8" } else { "d8" }))
    ignore(@sys.write_text(@sys.join(dex_dir, ".done"), ""))
    t = lap(if minify { "r8" } else { "d8" }, t)
  } else {
    ignore(try_sh("touch " + q(dex_dir)))
    t = lap("dex (kept)", t)
  }
  // a debug build's dependencies: each dexed once, by its own bytes (the lock's), side by side with the app's
  // (classes2.dex on: minSdk 29 loads them all), as Gradle's debug builds dex each library apart
  let dexes = dex_names(dex_dir)
  if !minify {
    for j in jars {
      let d = lib_dex(r8, android_jar, min_sdk, j, jars.filter(fn(x) { x != j }), work)
      for x in dex_names(d) {
        dexes.push(x)
      }
    }
    t = lap("dependencies dexed", t)
  }
  // the APK: what aapt2 linked, the dex (stored), the native libraries (compressed), the assets, the jars' resources
  let unsigned = @sys.join(work, "unsigned.apk")
  ignore(sh("cp " + q(ap) + " " + q(unsigned), "cp"))
  let stage = @sys.join(work, "stage")
  @sys.makedirs(stage)
  for i, p in dexes {
    let n = if i == 0 { "classes.dex" } else { "classes\{i + 1}.dex" }
    ignore(sh("cp " + q(p) + " " + q(@sys.join(stage, n)), "cp"))
  }
  let dex_files = []
  for i, _ in dexes {
    dex_files.push(if i == 0 { "classes.dex" } else { "classes\{i + 1}.dex" })
  }
  ignore(sh("cd " + q(stage) + " && zip -q -X -0 " + q(unsigned) + " " + dex_files.join(" "), "zip dex"))
  let packed = @sys.join(work, "packed")
  @sys.makedirs(packed)
  for jd in texts_of(cfg, "jniLibs").map(fn(x) { @sys.join(base, x) }) {
    let abis = if a.abi != "" {
      [a.abi]
    } else if @sys.is_dir(jd) {
      let l = @sys.list_dir(jd)
      l.sort_by(@rjson.str_cmp)
      l
    } else {
      []
    }
    for abi in abis {
      let ad = @sys.join(jd, abi)
      if @sys.is_dir(ad) {
        let names = @sys.list_dir(ad)
        names.sort_by(@rjson.str_cmp)
        for n in names {
          if n.has_suffix(".so") {
            @sys.makedirs(@sys.join(packed, "lib/" + abi))
            ignore(sh("cp " + q(stripped(@sys.join(ad, n))) + " " + q(@sys.join(packed, "lib/\{abi}/\{n}")), "cp"))
          }
        }
      }
    }
  }
  for asd in texts_of(cfg, "assets").map(fn(x) { @sys.join(base, x) }) {
    if @sys.is_dir(asd) {
      @sys.makedirs(@sys.join(packed, "assets"))
      ignore(sh("cp -R " + q(asd) + "/. " + q(@sys.join(packed, "assets")), "cp assets"))
    }
  }
  // the jars' Kotlin builtins and version files, the first of each name (what the app's own linking did not put)
  for j in jars {
    ignore(try_sh("unzip -n -q " + q(j) + " '*.kotlin_builtins' 'META-INF/*.version' -d " + q(packed)))
  }
  if files_under(packed).length() > 0 {
    ignore(sh("cd " + q(packed) + " && find . -type f | LC_ALL=C sort | zip -q -X " + q(unsigned) + " -@", "zip"))
  }
  t = lap("packed", t)
  let aligned = @sys.join(work, "aligned.apk")
  ignore(sh(q(@sys.join(bt, "zipalign")) + " -P 16 -f 4 " + q(unsigned) + " " + q(aligned), "zipalign"))
  let ks = if a.keystore != "" {
    a.keystore
  } else {
    @sys.join(@sys.getenv("ANDROID_USER_HOME").unwrap_or(@sys.join(home(), ".android")), "debug.keystore")
  }
  if !@sys.exists(ks) {
    // (no key given, as a branch's CI has none: a debug key of its own, as Gradle made one)
    @sys.makedirs(@sys.dirname(@sys.abspath(ks)))
    ignore(
      sh(
        "keytool -genkeypair -keystore " + q(ks) +
        " -storepass android -alias androiddebugkey -keypass android -keyalg RSA -validity 10000 -dname 'CN=Android Debug,O=Android,C=US'",
        "keytool",
      ),
    )
  }
  @sys.makedirs(@sys.dirname(@sys.abspath(a.out)))
  ignore(
    sh(
      q(@sys.join(bt, "apksigner")) + " sign --ks " + q(ks) +
      " --ks-pass pass:android --ks-key-alias androiddebugkey --key-pass pass:android --v1-signing-enabled false --v2-signing-enabled true --v3-signing-enabled false --out " +
      q(a.out) + " " + q(aligned),
      "apksigner",
    ),
  )
  ignore(lap("signed", t))
  ignore(try_sh("rm -rf " + q(work)))
  prune()
  let size = sh("wc -c < " + q(a.out), "wc").trim(chars=" \n\t")
  say(
    "\{a.out}: \{size} bytes in \{secs(now_s() - t0)} s: " + times.map(fn(x) { "\{x.0} \{secs(x.1)} s" }).join(", "),
  )
}

///|
fn usage() -> Int {
  @sys.eprintln(
    "apk: lock APP.json | build APP.json --variant V --version-code N --version-name S --out APK [--abi A] [--keystore K] | fetch PATH SHA256",
  )
  2
}

///|
fn main {
  let args = @env.args()[1:].to_array()
  let code = match args {
    ["lock", app] => {
      cmd_lock(app)
      0
    }
    ["fetch", path, sha] => {
      cmd_fetch(path, sha)
      0
    }
    ["build", app, .. rest] => {
      let opt = fn(name : String, default : String) -> String {
        for i, x in rest {
          if x == name && i + 1 < rest.length() {
            return rest[i + 1]
          }
        }
        default
      }
      let out = opt("--out", "")
      if out == "" {
        usage()
      } else {
        cmd_build({
          app,
          variant: opt("--variant", "debug"),
          version_code: opt("--version-code", "1"),
          version_name: opt("--version-name", "0.1.1"),
          out,
          abi: opt("--abi", ""),
          keystore: opt("--keystore", ""),
        })
        0
      }
    }
    _ => usage()
  }
  @sys.exit(code)
}
