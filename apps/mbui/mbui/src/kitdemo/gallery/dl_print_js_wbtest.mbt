///|
/// The process's environment (node's), to ask for what a test prints only when asked.
extern "js" fn node_env(name : String) -> String =
  #|(n) => (typeof process !== "undefined" && process.env[n]) || ""

///|
/// A file's words (node's), "" when there is none: a run's tape handed to the test by its path.
extern "js" fn node_read(path : String) -> String =
  #|(p) => { try { return process.getBuiltinModule("fs").readFileSync(p, "utf8"); } catch (e) { return ""; } }

