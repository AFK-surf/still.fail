///|
/// The process's environment, to ask for what a test prints only when asked.
fn node_env(name : String) -> String {
  @env.get_env_var(name).unwrap_or("")
}

///|
/// A file's words, "" when there is none: a run's tape handed to the test by its path (moonrun's: mbui/runfs).
fn node_read(path : String) -> String {
  match @runfs.read(path) {
    Some(b) => @utf8.decode_lossy(b[:])
    None => ""
  }
}
