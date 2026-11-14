///|
/// The process's environment, to ask for what a test prints only when asked.
fn node_env(name : String) -> String {
  @env.get_env_var(name).unwrap_or("")
}

///|
#borrow(path)
extern "C" fn read_file_bytes(path : Bytes) -> Bytes = "mbui_gallery_read_file"

///|
/// A file's words, "" when there is none: a run's tape handed to the test by its path.
fn node_read(path : String) -> String {
  let b = read_file_bytes(@utf8.encode(path + "\u{0}"))
  @utf8.decode_lossy(b)
}
