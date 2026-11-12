///|
/// A run's trace (e2e/traces/NAME.trace) for a test on Wasm, as trace_files.c finds it on native: under
/// $MBUI_APP_MOD, else under where the test runs (its package's directory) or a directory it is in.
pub fn read_trace(name : String) -> String? {
  let rel = "/e2e/traces/" + name + ".trace"
  let dirs : Array[String] = []
  match @env.get_env_var("MBUI_APP_MOD") {
    Some(m) if m != "" => dirs.push(m)
    _ => ()
  }
  let mut d = @env.current_dir().unwrap_or("")
  while d != "" {
    dirs.push(d)
    match d.rev_find("/") {
      Some(i) if i > 0 => d = d[:i].to_owned()
      _ => d = ""
    }
  }
  for dir in dirs {
    match @runfs.read(dir + rel) {
      Some(b) => return Some(@utf8.decode_lossy(b[:]))
      None => ()
    }
  }
  None
}
